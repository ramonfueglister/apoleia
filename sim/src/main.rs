//! Runs the population prototype over the real start grid.
//!
//! Usage: apoleia-sim [--years N] [--out DIR] [--root DIR] [--static] [--estimates] [--k-from-cropland] [--snap-every N]
//! Inputs: data/gametiles/tiles.csv and sim/inputs/*.csv (tools/sim_inputs.py,
//! tools/sim_hyde.py). `--estimates` ignores hyde25.csv.

use apoleia_sim::{Cell, City, Hyde, Key, Params, World};
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Instant;

const START_YEAR: i32 = 180;

fn read_csv(path: &Path) -> Vec<HashMap<String, String>> {
    let text = fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    let mut lines = text.lines();
    let header: Vec<String> = lines.next().unwrap_or("").split(',').map(str::to_owned).collect();
    lines
        .filter(|l| !l.is_empty())
        .map(|l| header.iter().cloned().zip(l.split(',').map(str::to_owned)).collect())
        .collect()
}

fn num(row: &HashMap<String, String>, key: &str) -> f64 {
    row.get(key).and_then(|v| v.parse().ok()).unwrap_or(0.0)
}

fn write_snapshot(w: &World, path: &Path) {
    let mut f = fs::File::create(path).unwrap();
    writeln!(f, "id,level,x0_m,z0_m,size_m,p,k,land_km2").unwrap();
    for (k, t) in &w.leaves {
        let s = k.size_m();
        writeln!(f, "{},{},{},{},{},{:.1},{:.1},{:.3}", k.id(), k.level, k.col as f64 * s, k.row as f64 * s, s, t.p, t.k, t.land_km2)
            .unwrap();
    }
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

    let start: Vec<Key> = read_csv(&root.join("data/gametiles/tiles.csv"))
        .iter()
        .map(|r| Key::parse(&r["id"]).expect("tile id"))
        .collect();
    let mut cells: HashMap<(i32, i32), Cell> = read_csv(&root.join("sim/inputs/cells25.csv"))
        .iter()
        .map(|r| {
            let rc = (num(r, "row") as i32, num(r, "col") as i32);
            let cell = Cell {
                land_km2: num(r, "land_km2"),
                frac_bare: num(r, "frac_bare"),
                frac_snow: num(r, "frac_snow"),
                frac_above_1500m: num(r, "frac_above_1500m"),
                hyde: None,
            };
            (rc, cell)
        })
        .collect();
    // Real data replaces the estimates when tools/sim_hyde.py has been run.
    let hyde_path = root.join("sim/inputs/hyde25.csv");
    let use_hyde = hyde_path.exists() && !args.iter().any(|a| a == "--estimates");
    if use_hyde {
        for r in read_csv(&hyde_path) {
            let rc = (num(&r, "row") as i32, num(&r, "col") as i32);
            if let Some(cell) = cells.get_mut(&rc) {
                let rural = r.get("rural200").and_then(|v| v.parse().ok());
                cell.hyde = Some(Hyde { crop_km2: num(&r, "crop_km2"), pop: num(&r, "pop200"), rural });
            }
        }
    }
    let cities: Vec<City> = read_csv(&root.join("sim/inputs/cities.csv"))
        .iter()
        .map(|r| City { x_m: num(r, "x_m"), z_m: num(r, "z_m"), pop: num(r, "pop117") })
        .collect();

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
    all_us.sort_by(f64::total_cmp);
    let pct = |q: f64| all_us[((all_us.len() - 1) as f64 * q) as usize];
    println!(
        "inputs={} years={years} leaves={} splits={} merges={} population={:.0} balanced={} fingerprint={:016x} tick_us p50={:.0} p95={:.0} max={:.0}",
        if use_hyde { "hyde33" } else { "estimates" },
        w.leaves.len(),
        w.splits,
        w.merges,
        w.total_population(),
        w.balanced(),
        w.fingerprint(),
        pct(0.5),
        pct(0.95),
        pct(1.0)
    );
}
