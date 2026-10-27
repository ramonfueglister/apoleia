//! Runs the population prototype over the real start grid.
//!
//! Usage: apoleia-sim [--years N] [--out DIR] [--root DIR] [--static] [--estimates] [--k-from-cropland] [--snap-every N] [--reference]
//! Inputs: data/gametiles/tiles.csv and sim/inputs/*.csv (tools/sim_inputs.py,
//! tools/sim_hyde.py). `--estimates` ignores hyde25.csv. The ECS core (S41) runs by
//! default; `--reference` runs the plain-struct version it was ported from.

use apoleia_sim::ecs::Sim;
use apoleia_sim::{Params, World};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Instant;

const START_YEAR: i32 = 180;

fn write_snapshot(w: &World, path: &Path) {
    let mut f = fs::File::create(path).unwrap();
    writeln!(f, "id,level,x0_m,z0_m,size_m,p,k,land_km2").unwrap();
    for (k, t) in &w.leaves {
        let s = k.size_m();
        writeln!(f, "{},{},{},{},{},{:.1},{:.1},{:.3}", k.id(), k.level, k.col as f64 * s, k.row as f64 * s, s, t.p, t.k, t.land_km2)
            .unwrap();
    }
}

fn write_views(sim: &mut Sim, path: &Path) {
    let mut f = fs::File::create(path).unwrap();
    writeln!(f, "id,level,x0_m,z0_m,size_m,p,k,land_km2").unwrap();
    for t in &sim.snapshot().tiles {
        let k = t.key;
        let s = k.size_m();
        writeln!(f, "{},{},{},{},{},{:.1},{:.1},{:.3}", k.id(), k.level, k.col as f64 * s, k.row as f64 * s, s, t.pop, t.cap, t.land_km2)
            .unwrap();
    }
}

fn percentiles(mut us: Vec<f64>) -> (f64, f64, f64) {
    us.sort_by(f64::total_cmp);
    let pct = |q: f64| us[((us.len() - 1) as f64 * q) as usize];
    (pct(0.5), pct(0.95), pct(1.0))
}

/// The ECS core: same output files and summary line as the reference run.
fn run_ecs(mut sim: Sim, years: u32, snap_every: u32, out: &Path, inputs: &str) {
    write_views(&mut sim, &out.join(format!("leaves-{START_YEAR}.csv")));
    let mut series = fs::File::create(out.join("series.csv")).unwrap();
    writeln!(series, "year,population,capacity,leaves,max_level,splits,merges,mean_tick_us,max_tick_us,migrants_year").unwrap();
    let level = |v: &[apoleia_sim::ecs::TileView]| v.iter().map(|t| t.key.level).max().unwrap();
    let v = sim.snapshot();
    let v = &v.tiles;
    let k_total: f64 = v.iter().map(|t| t.cap).sum();
    writeln!(series, "{START_YEAR},{:.0},{k_total:.0},{},{},0,0,0,0,0", sim.total_population(), v.len(), level(&v)).unwrap();
    let mut all_us = Vec::new();
    let mut snap_us = Vec::new();
    for y in 1..=years {
        let mut ticks = Vec::with_capacity(12);
        for _ in 0..12 {
            let t0 = Instant::now();
            sim.tick();
            ticks.push(t0.elapsed().as_secs_f64() * 1e6);
        }
        all_us.extend_from_slice(&ticks);
        let year = START_YEAR + y as i32;
        let t0 = Instant::now();
        let v = sim.snapshot();
        snap_us.push(t0.elapsed().as_secs_f64() * 1e6);
        let v = &v.tiles;
        let k_total: f64 = v.iter().map(|t| t.cap).sum();
        let st = sim.stats();
        let mean = ticks.iter().sum::<f64>() / 12.0;
        let max = ticks.iter().cloned().fold(0.0, f64::max);
        // People who changed tile in December of this year.
        let migrants: f64 = v.iter().map(|t| t.moved.max(0.0)).sum();
        writeln!(series, "{year},{:.0},{k_total:.0},{},{},{},{},{mean:.1},{max:.1},{migrants:.0}", sim.total_population(), v.len(), level(&v), st.splits, st.merges)
            .unwrap();
        if y % snap_every == 0 || y == years {
            write_views(&mut sim, &out.join(format!("leaves-{year}.csv")));
        }
    }
    let (p50, p95, max) = percentiles(all_us);
    let (snap50, _, _) = percentiles(snap_us);
    let st = sim.stats();
    println!(
        "core=ecs inputs={inputs} years={years} leaves={} splits={} merges={} population={:.0} balanced={} fingerprint={:016x} tick_us p50={p50:.0} p95={p95:.0} max={max:.0} snapshot_us p50={snap50:.0}",
        sim.leaf_count(),
        st.splits,
        st.merges,
        sim.total_population(),
        sim.balanced(),
        sim.fingerprint(),
    );
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let years: u32 = arg("--years").and_then(|v| v.parse().ok()).unwrap_or(500);
    let snap_every: u32 = arg("--snap-every").and_then(|v| v.parse().ok()).unwrap_or(100);
    let out = PathBuf::from(arg("--out").unwrap_or_else(|| "sim/out".into()));
    let root = PathBuf::from(arg("--root").unwrap_or_else(|| ".".into()));
    let params = Params {
        adaptive: !args.iter().any(|a| a == "--static"),
        k_from_cropland: args.iter().any(|a| a == "--k-from-cropland"),
        ..Params::default()
    };
    fs::create_dir_all(&out).unwrap();

    let data = apoleia_sim::inputs::load(&root, args.iter().any(|a| a == "--estimates")).unwrap_or_else(|e| panic!("{e}"));
    let (start, cells, cities, use_hyde) = (data.start, data.cells, data.cities, data.hyde);
    let inputs = if use_hyde { "hyde33" } else { "estimates" };
    if !args.iter().any(|a| a == "--reference") {
        run_ecs(Sim::new(params, &start, cells, cities), years, snap_every, &out, inputs);
        return;
    }
    let mut w = World::new(params.clone(), &start, cells, cities);
    write_snapshot(&w, &out.join(format!("leaves-{START_YEAR}.csv")));
    let mut series = fs::File::create(out.join("series.csv")).unwrap();
    writeln!(series, "year,population,capacity,leaves,max_level,splits,merges,mean_tick_us,max_tick_us").unwrap();
    let k_total: f64 = w.leaves.values().map(|t| t.k).sum();
    writeln!(series, "{START_YEAR},{:.0},{k_total:.0},{},{},0,0,0,0", w.total_population(), w.leaves.len(), w.leaves.keys().map(|k| k.level).max().unwrap()).unwrap();

    let mut all_us = Vec::new();
    for y in 1..=years {
        let mut ticks = Vec::with_capacity(12);
        for _ in 0..12 {
            let t0 = Instant::now();
            w.tick();
            ticks.push(t0.elapsed().as_secs_f64() * 1e6);
        }
        all_us.extend_from_slice(&ticks);
        let year = START_YEAR + y as i32;
        let k_total: f64 = w.leaves.values().map(|t| t.k).sum();
        let mean = ticks.iter().sum::<f64>() / 12.0;
        let max = ticks.iter().cloned().fold(0.0, f64::max);
        writeln!(
            series,
            "{year},{:.0},{k_total:.0},{},{},{},{},{mean:.1},{max:.1}",
            w.total_population(),
            w.leaves.len(),
            w.leaves.keys().map(|k| k.level).max().unwrap(),
            w.splits,
            w.merges
        )
        .unwrap();
        if y % snap_every == 0 || y == years {
            write_snapshot(&w, &out.join(format!("leaves-{year}.csv")));
        }
    }
    let (p50, p95, max) = percentiles(all_us);
    println!(
        "core=reference inputs={inputs} years={years} leaves={} splits={} merges={} population={:.0} balanced={} fingerprint={:016x} tick_us p50={p50:.0} p95={p95:.0} max={max:.0}",
        w.leaves.len(),
        w.splits,
        w.merges,
        w.total_population(),
        w.balanced(),
        w.fingerprint(),
    );
}
