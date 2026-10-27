//! Load test for individually simulated people (S50–S60): spawns about
//! 100,000 people from HYDE and Hanson, runs them day by day and reports tick
//! times, memory and a fingerprint.
//!
//! Usage: people [--years N] [--seed S] [--threads N] [--root DIR]

use apoleia_sim::people::{Fields, People, PEOPLE_PER_PERSON};
use std::path::PathBuf;
use std::time::Instant;

fn rss_mb() -> f64 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("VmRSS:"))
                .and_then(|l| l.split_whitespace().nth(1)?.parse::<f64>().ok())
        })
        .map_or(f64::NAN, |kb| kb / 1024.0)
}

fn pct(mut v: Vec<f64>, q: f64) -> f64 {
    if v.is_empty() {
        return f64::NAN;
    }
    v.sort_by(f64::total_cmp);
    v[((v.len() - 1) as f64 * q) as usize]
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |name: &str| {
        args.iter()
            .position(|a| a == name)
            .and_then(|i| args.get(i + 1))
            .cloned()
    };
    let years: i64 = arg("--years").map_or(10, |v| v.parse().unwrap());
    let seed: u64 = arg("--seed").map_or(1, |v| v.parse().unwrap());
    let root = PathBuf::from(arg("--root").unwrap_or_else(|| "..".into()));
    if let Some(n) = arg("--threads") {
        bevy_tasks::ComputeTaskPool::get_or_init(|| {
            bevy_tasks::TaskPoolBuilder::new()
                .num_threads(n.parse().unwrap())
                .build()
        });
    }
    let inp = apoleia_sim::inputs::load(&root, false).expect("inputs");
    let rss0 = rss_mb();
    let t0 = Instant::now();
    let mut p = People::new(&inp, seed);
    let spawn_ms = t0.elapsed().as_secs_f64() * 1e3;
    println!(
        "people={} (1 per {PEOPLE_PER_PERSON} real) places={} grid={}x{} spawn_ms={spawn_ms:.0} (flow fields {} in {:.0} ms) rss_mb={:.0} (+{:.0})",
        p.count,
        p.places.len(),
        p.grid.rows,
        p.grid.cols,
        p.world.resource::<Fields>().map.len(),
        p.world.resource::<Fields>().build_ms,
        rss_mb(),
        rss_mb() - rss0
    );
    let (mut plain, mut month, mut year) = (Vec::new(), Vec::new(), Vec::new());
    for y in 1..=years {
        for _ in 0..360 {
            let t = Instant::now();
            let (m, yr) = p.day();
            let us = t.elapsed().as_secs_f64() * 1e6;
            match (m, yr) {
                (_, true) => year.push(us),
                (true, _) => month.push(us),
                _ => plain.push(us),
            }
        }
        let travelling = p.travelling();
        println!("year {y}: travelling={travelling} rss_mb={:.0}", rss_mb());
    }
    println!(
        "day_us p50={:.0} p95={:.0} max={:.0} | month_day_us p50={:.0} p95={:.0} max={:.0} | year_day_us p50={:.0} max={:.0}",
        pct(plain.clone(), 0.5),
        pct(plain.clone(), 0.95),
        pct(plain, 1.0),
        pct(month.clone(), 0.5),
        pct(month.clone(), 0.95),
        pct(month, 1.0),
        pct(year.clone(), 0.5),
        pct(year, 1.0)
    );
    let days = (years * 360) as f64;
    let t = p.timing;
    println!(
        "per day us: needs={:.0} travel={:.0} | per month us: index={:.0} relations={:.0} trips={:.0} pops={:.0} ({} pops) | per year us: jobs={:.0}",
        t.needs / days,
        t.travel / days,
        t.index / (days / 30.0),
        t.relations / (days / 30.0),
        t.trips / (days / 30.0),
        t.pops / (days / 30.0),
        p.groups.pops.len(),
        t.jobs / (days / 360.0)
    );
    println!("fingerprint={:016x}", p.fingerprint());
}
