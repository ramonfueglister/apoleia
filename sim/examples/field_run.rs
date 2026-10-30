//! Fields of state land beside a market, 100 years with and without them
//! (the check for built fields, S116): how much is built and leased, the
//! rent to the state's granary, the market's price and people, hunger.
//! The fields are ordered on day 30 as one rectangle of lots (0.5 km, at
//! most 24 × 24 as the build menu sends it) from the market square; lots
//! without free land build nothing.
//!
//! Usage: cargo run --release --example field_run -- [--years N] [--seed S]
//!        [--at NAME|auto] [--lots N] [--no-fields] [--root DIR]

use apoleia_sim::build::{self, Command, FIELD};
use apoleia_sim::game::{Game, Start};
use std::path::PathBuf;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let years: i64 = arg("--years").map_or(100, |v| v.parse().unwrap());
    let seed: u64 = arg("--seed").map_or(1, |v| v.parse().unwrap());
    let at = arg("--at").unwrap_or_else(|| "Rome".into());
    let side: i32 = arg("--lots").map_or(24, |v| v.parse().unwrap());
    let fields = !args.iter().any(|a| a == "--no-fields");
    let root = PathBuf::from(arg("--root").unwrap_or_else(|| "..".into()));
    let inp = apoleia_sim::inputs::load(&root, false).expect("inputs");
    let cols: Vec<String> = apoleia_sim::grain::CLEAR_COVER.iter().map(|c| c.to_string()).collect();
    let clear = apoleia_sim::grain::clearable(&root, &cols).ok();
    let cover = apoleia_sim::grain::fine_cover(&root, true).ok();
    let mut g = Game::new(Start { inputs: &inp, clear: clear.as_ref(), cover: cover.as_ref() }, seed);
    let (_, cols_f) = g.grain.fine_size();
    let rect = |g: &Game, m: usize| {
        let f = g.grain.markets[m].fine as i32;
        let (z0, x0) = build::fine_centre(f / cols_f + g.people.grid.row0 * 16, f % cols_f + g.people.grid.col0 * 16);
        let lots: Vec<build::Tile> = (0..side).flat_map(|r| (0..side).map(move |c| (z0 + 500 * r, x0 + 500 * c))).collect();
        let open = lots.iter().filter(|&&t| g.grain.site_check(&g.people, FIELD, t).status == apoleia_sim::grain::CHECK_BUILDS).count();
        (lots, open)
    };
    // --at auto: of the markets whose rectangle has free land on at least
    // a quarter of its lots, the one with the most people
    let m = if at == "auto" {
        (0..g.grain.markets.len()).filter(|&m| rect(&g, m).1 * 4 >= (side * side) as usize).max_by_key(|&m| (g.grain.markets[m].people, std::cmp::Reverse(m))).expect("a market with free land")
    } else {
        g.grain.markets.iter().position(|mk| mk.name == at || mk.name.starts_with(&format!("{at} ("))).unwrap_or_else(|| panic!("no market {at}"))
    };
    let at = g.grain.markets[m].name.clone();
    let (lots, open) = rect(&g, m);
    println!("{at}: {} lots ordered, {open} with free land, fields {}", lots.len(), if fields { "built" } else { "none" });
    println!("year  built ha  leased ha  rent t/yr  price  people at market  people  hunger/yr");
    let (mut last_rent, mut last_hunger) = (0i64, 0i64);
    for d in 0..years * 360 {
        if fields && d == 30 {
            g.command(&Command::Place { kind: FIELD, tiles: lots.clone() });
        }
        g.day();
        if (d + 1) % 3600 == 0 || d + 1 == 360 {
            let span = if d + 1 == 360 { 1 } else { 10 };
            let (free, leased) = g.grain.state_land();
            let rent = g.grain.stats.state_rent_kg;
            let hunger: i64 = g.grain.history().iter().map(|r| r.flows[2]).sum();
            println!(
                "{:>4}  {:>8.1}  {:>9.1}  {:>9.1}  {:>5.2}  {:>16}  {:>6}  {:>9}",
                (d + 1) / 360,
                (free + leased) as f64 / 1e4,
                leased as f64 / 1e4,
                (rent - last_rent) as f64 / 1000.0 / span as f64,
                g.grain.markets[m].price as f64 / 1000.0,
                g.grain.markets[m].people,
                g.people.count,
                (hunger - last_hunger) / span,
            );
            (last_rent, last_hunger) = (rent, hunger);
        }
    }
    println!("left to build: {}, field lots: {}", g.orders.len(), g.grain.field_lots().count());
}
