//! A road between two markets, 100 years with and without it (the check
//! for built roads, S113; proposal "Felder und Strassen", 29.10.2026):
//! prices at both ends and their gap, grain traded, trader traffic on the
//! road's cells, people and hunger. The road is ordered on day 30 as a
//! straight chain of lots (0.5 km) between the two market squares, as the
//! build menu would send it.
//!
//! Usage: cargo run --release --example road_run -- [--years N] [--seed S]
//!        [--from NAME] [--to NAME] [--no-road] [--root DIR]

use apoleia_sim::build::{self, Command, ROAD};
use apoleia_sim::game::{Game, Start};
use std::path::PathBuf;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let years: i64 = arg("--years").map_or(100, |v| v.parse().unwrap());
    let seed: u64 = arg("--seed").map_or(1, |v| v.parse().unwrap());
    let (from, to) = (arg("--from").unwrap_or_else(|| "Rome".into()), arg("--to").unwrap_or_else(|| "Capua".into()));
    let road = !args.iter().any(|a| a == "--no-road");
    let root = PathBuf::from(arg("--root").unwrap_or_else(|| "..".into()));
    let inp = apoleia_sim::inputs::load(&root, false).expect("inputs");
    let cols: Vec<String> = apoleia_sim::grain::CLEAR_COVER.iter().map(|c| c.to_string()).collect();
    let clear = apoleia_sim::grain::clearable(&root, &cols).ok();
    let cover = apoleia_sim::grain::fine_cover(&root, true).ok();
    let mut g = Game::new(Start { inputs: &inp, clear: clear.as_ref(), cover: cover.as_ref() }, seed);
    let find = |name: &str| g.grain.markets.iter().position(|m| m.name == name || m.name.starts_with(&format!("{name} ("))).unwrap_or_else(|| panic!("no market {name}"));
    let (a, b) = (find(&from), find(&to));
    let (_, cols_f) = g.grain.fine_size();
    let (row0, col0) = (g.people.grid.row0 * 16, g.people.grid.col0 * 16);
    let spot = |m: usize| {
        let f = g.grain.markets[m].fine as i32;
        build::fine_centre(f / cols_f + row0, f % cols_f + col0)
    };
    let (sa, sb) = (spot(a), spot(b));
    let km = (((sb.0 - sa.0) as f64).powi(2) + ((sb.1 - sa.1) as f64).powi(2)).sqrt() / 1000.0;
    let n = (km / 0.5).ceil() as i32;
    let lots: Vec<build::Tile> = (0..=n).map(|k| (sa.0 + (sb.0 - sa.0) * k / n, sa.1 + (sb.1 - sa.1) * k / n)).collect();
    let cells: Vec<u32> = {
        let mut c: Vec<u32> = lots.iter().map(|&t| build::fine_of(t)).map(|(r, c)| ((r / 16 - g.people.grid.row0) * g.people.grid.cols + c / 16 - g.people.grid.col0) as u32).collect();
        c.dedup();
        c
    };
    println!("{from} – {to}: {km:.0} km, {} lots, {} cells, road {}", lots.len(), cells.len(), if road { "built" } else { "none" });
    println!("year  price {from:>7}  price {to:>7}  gap %  traded t/yr  trips/yr  traffic  people  hunger/yr");
    let mut last = (0i64, 0u64, 0i64);
    for d in 0..years * 360 {
        if road && d == 30 {
            g.command(&Command::Place { kind: ROAD, tiles: lots.clone() });
        }
        g.day();
        if (d + 1) % 3600 == 0 || d + 1 == 360 {
            let (pa, pb) = (g.grain.markets[a].price as f64 / 1000.0, g.grain.markets[b].price as f64 / 1000.0);
            let s = &g.grain.stats;
            let years_since = if d + 1 == 360 { 1 } else { 10 };
            let traffic: i64 = cells.iter().map(|c| g.grain.lanes.get(c).copied().unwrap_or(0)).sum();
            let hunger: i64 = g.grain.history().iter().map(|r| r.flows[2]).sum();
            println!(
                "{:>4}  {:>13.2}  {:>13.2}  {:>5.1}  {:>11.0}  {:>8}  {:>7}  {:>6}  {:>9}",
                (d + 1) / 360,
                pa,
                pb,
                (pa - pb).abs() / ((pa + pb) / 2.0) * 100.0,
                (s.traded_kg - last.0) as f64 / 1000.0 / years_since as f64,
                (s.trade_trips - last.1) / years_since as u64,
                traffic,
                g.people.count,
                (hunger - last.2) / years_since,
            );
            last = (s.traded_kg, s.trade_trips, hunger);
        }
    }
    println!("left to build: {}, road lots: {}", g.orders.len(), g.grain.road_lots().count());
}
