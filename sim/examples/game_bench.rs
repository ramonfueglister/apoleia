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
    let t1 = Instant::now();
    for d in 0..days {
        if d % 90 == 0 {
            let r = 400 + (d / 90) as i32;
            g.command(&Command::Place { kind: FARM, tiles: vec![(r, 900)] });
            g.command(&Command::Place { kind: ROAD, tiles: vec![(r, 901), (r, 902)] });
        }
        let t = Instant::now();
        g.day();
        ms.push(t.elapsed().as_secs_f64() * 1e3);
    }
    let run_s = t1.elapsed().as_secs_f64();
    let (p50, p95, p99, max) = (pct(&mut ms, 0.5), pct(&mut ms, 0.95), pct(&mut ms, 0.99), pct(&mut ms, 1.0));
    println!("{days} days: {:.2} s per year; day p50 {p50:.2} ms, p95 {p95:.2}, p99 {p99:.2}, max {max:.2}", run_s / years as f64);
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
    assert!(info.identical && h.fingerprints() == g.fingerprints());
}
