//! Day sim as the game runs it (crate::game, docs/kit1/REALTIME_GAMEPLAY.md
//! phases 4 and 8): what a day costs against the budget of each speed, and
//! how long a save takes to play again.
//!
//! Usage: cargo run --release --example game_bench -- [--years N] [--seed S]
//!        [--root DIR] [--save PATH]

use apoleia_sim::build::{Command, FARM, ROAD};
use apoleia_sim::game::{Game, Start};
use std::path::{Path, PathBuf};
use std::time::Instant;

/// Days per second of the speeds 1–4 (app/scripts/sim/game_clock.gd).
const SPEEDS: [f64; 4] = [2.0, 10.0, 30.0, 100.0];

fn pct(v: &mut [f64], q: f64) -> f64 {
    v.sort_by(f64::total_cmp);
    v[((v.len() - 1) as f64 * q) as usize]
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let years: i64 = arg("--years").map_or(2, |v| v.parse().unwrap());
    let seed: u64 = arg("--seed").map_or(1, |v| v.parse().unwrap());
    let root = PathBuf::from(arg("--root").unwrap_or_else(|| "..".into()));
    let save = PathBuf::from(arg("--save").unwrap_or_else(|| std::env::temp_dir().join("game_bench.apgame").to_string_lossy().into()));
    let inp = apoleia_sim::inputs::load(&root, false).expect("inputs");
    let cols: Vec<String> = apoleia_sim::grain::CLEAR_COVER.iter().map(|c| c.to_string()).collect();
    let clear = apoleia_sim::grain::clearable(&root, &cols).ok();
    let cover = apoleia_sim::grain::fine_cover(&root, true).ok();
    let start = Start { inputs: &inp, clear: clear.as_ref(), cover: cover.as_ref() };
    let t0 = Instant::now();
    let mut g = Game::new(start, seed);
    println!("start: {:.0} ms, {} people", t0.elapsed().as_secs_f64() * 1e3, g.people.count);
    let days = years * apoleia_sim::life::YEAR;
    let mut ms = Vec::with_capacity(days as usize);
    let mut parts = [0.0f64; 2];
    let t1 = Instant::now();
    for d in 0..days {
        if d % 90 == 0 {
            let r = 400 + (d / 90) as i32;
            let at = apoleia_sim::build::fine_centre;
            g.command(&Command::Place { kind: FARM, tiles: vec![at(r, 900)] });
            g.command(&Command::Place { kind: ROAD, tiles: vec![at(r, 901), at(r, 902)] });
        }
        let t = Instant::now();
        let [people_us, grain_us] = g.day();
        ms.push(t.elapsed().as_secs_f64() * 1e3);
        parts[0] += people_us / 1e3;
        parts[1] += grain_us / 1e3;
    }
    let run_s = t1.elapsed().as_secs_f64();
    // where the slow days fall: the ten slowest, and the mean by day of the month
    let mut slow: Vec<(f64, usize)> = ms.iter().copied().zip(0..).collect();
    slow.sort_by(|a, b| b.0.total_cmp(&a.0));
    let top: Vec<String> = slow.iter().take(10).map(|(m, d)| format!("{d} ({}.): {m:.1}", d % 30)).collect();
    println!("slowest days (day of month): {}", top.join(", "));
    let mut by_dom = [0.0f64; 30];
    for (d, m) in ms.iter().enumerate() {
        by_dom[d % 30] += m / (days as f64 / 30.0);
    }
    println!("mean ms by day of month: {}", by_dom.iter().map(|m| format!("{m:.1}")).collect::<Vec<_>>().join(" "));
    let (p50, p95, p99, max) = (pct(&mut ms, 0.5), pct(&mut ms, 0.95), pct(&mut ms, 0.99), pct(&mut ms, 1.0));
    println!("{days} days: {:.2} s per year; day p50 {p50:.2} ms, p95 {p95:.2}, p99 {p99:.2}, max {max:.2}", run_s / years as f64);
    println!("mean per day: people {:.2} ms, grain {:.2} ms", parts[0] / days as f64, parts[1] / days as f64);
    let t = g.people.timing;
    let per = |us: f64| us / 1e3 / days as f64;
    println!(
        "people per part, ms per day: marriage {:.2}, needs {:.2}, relations {:.2}, health {:.2}, travel {:.2}, migration {:.2}, events {:.2}, pops {:.2}, index {:.2}, trips {:.2}",
        per(t.marriage),
        per(t.needs),
        per(t.relations),
        per(t.health),
        per(t.travel),
        per(t.migration),
        per(t.events),
        per(t.pops),
        per(t.index),
        per(t.trips)
    );
    let t = &g.grain.timing;
    println!(
        "grain per part, ms per day: events {:.2}, peaks {:.2}, labour {:.2}, markets {:.2}, eat {:.2}, traders {:.2}, paths {:.2}, rebuild {:.2}, census {:.2}",
        per(t.events),
        per(t.peaks),
        per(t.labour),
        per(t.markets),
        per(t.eat),
        per(t.traders),
        per(t.paths),
        per(t.rebuild),
        per(t.census)
    );
    for (i, s) in SPEEDS.iter().enumerate() {
        let budget = 1000.0 / s;
        let over = ms.iter().filter(|&&m| m > budget).count();
        println!("speed {} ({s} days/s): budget {budget:.1} ms per day, {over} days over, sim alone keeps up: {}", i + 1, p99 < budget);
    }
    let t2 = Instant::now();
    g.save_to(Path::new(&save)).expect("save");
    let bytes = std::fs::metadata(&save).map_or(0, |m| m.len());
    println!("save: {:.1} ms, {bytes} bytes, {} commands", t2.elapsed().as_secs_f64() * 1e3, g.orders.log.len());
    let t3 = Instant::now();
    let (mut h, info) = Game::load_from(start, Path::new(&save), |_, _| {}).expect("load");
    println!("load: {:.2} s ({:.2} s per year), identical: {}", t3.elapsed().as_secs_f64(), t3.elapsed().as_secs_f64() / years as f64, info.identical);
    let fp = g.fingerprints();
    assert!(info.identical && h.fingerprints() == fp);
    println!("fingerprints: {:016x} {:016x}", fp.0, fp.1);
}
