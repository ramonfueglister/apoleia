//! Prototype run for individually simulated people (S50–S67): spawns about
//! 117,000 people from HYDE and Hanson, runs them day by day with births,
//! marriages, deaths and migration, and reports a yearly census, tick times,
//! memory and a fingerprint.
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
    let mut all = Vec::new();
    let mut worst = (0.0, 0);
    let mut worst_parts = String::new();
    // Mean time per day of the month and per part (--slices).
    let slices = args.iter().any(|a| a == "--slices");
    let mut by_slice = vec![[0.0f64; 13]; 30];
    println!("year  people  births  deaths(krank/alter/hunger/geburt)  <1y  marriages age_f age_m  married_w%  waited  moved_hh left_hh/people left_map  health%  hungry  events_in_cal  rss_mb");
    for y in 1..=years {
        p.stats = Default::default();
        for _ in 0..360 {
            let before = p.timing;
            let t = Instant::now();
            let (m, yr) = p.day();
            let us = t.elapsed().as_secs_f64() * 1e6;
            all.push(us);
            if us > worst.0 {
                let a = p.timing;
                worst = (us, all.len());
                worst_parts = format!(
                    "events={:.0} needs={:.0} travel={:.0} health={:.0} marriage={:.0} relations={:.0} trips={:.0} jobs={:.0} migration={:.0} index={:.0} pops={:.0}",
                    a.events - before.events,
                    a.needs - before.needs,
                    a.travel - before.travel,
                    a.health - before.health,
                    a.marriage - before.marriage,
                    a.relations - before.relations,
                    a.trips - before.trips,
                    a.jobs - before.jobs,
                    a.migration - before.migration,
                    a.index - before.index,
                    a.pops - before.pops
                );
            }
            if slices {
                let a = p.timing;
                let d = [a.events - before.events, a.needs - before.needs, a.travel - before.travel, a.health - before.health, a.marriage - before.marriage, a.relations - before.relations, a.trips - before.trips, a.jobs - before.jobs, a.migration - before.migration, a.index - before.index, a.pops - before.pops, us, 1.0];
                let row = &mut by_slice[(all.len() % 30) as usize];
                for k in 0..13 {
                    row[k] += d[k];
                }
            }
            match (m, yr) {
                (_, true) => year.push(us),
                (true, _) => month.push(us),
                _ => plain.push(us),
            }
        }
        let s = p.stats;
        let (mw, w, health, hungry) = p.census();
        let m = s.marriages.max(1) as f64;
        println!(
            "{y:4} {:7} {:7} {:6} ({}/{}/{}/{}) {:5} {:6} {:5.1} {:5.1} {:6.1} {:7} {:6} {:5}/{:5} {:6} {:6.1} {:7} {:8} {:6.0}",
            p.count,
            s.births,
            s.deaths.iter().sum::<u64>(),
            s.deaths[0],
            s.deaths[1],
            s.deaths[2],
            s.deaths[3],
            s.deaths_under1,
            s.marriages,
            s.marry_age_f / m,
            s.marry_age_m / m,
            100.0 * mw as f64 / w.max(1) as f64,
            s.waited_for_land,
            s.moved_households,
            s.left_households,
            s.left_people,
            s.left_map,
            health,
            hungry,
            p.scheduled(),
            rss_mb()
        );
    }
    println!(
        "day_us p50={:.0} p95={:.0} p99={:.0} max={:.0} | first_of_month_us p50={:.0} max={:.0} | new_year_us p50={:.0} max={:.0} | rss_mb={:.0} peak_people={} cap={}",
        pct(all.clone(), 0.5),
        pct(all.clone(), 0.95),
        pct(all.clone(), 0.99),
        pct(all, 1.0),
        pct(month.clone(), 0.5),
        pct(month, 1.0),
        pct(year.clone(), 0.5),
        pct(year, 1.0),
        rss_mb(),
        p.peak,
        apoleia_sim::people::CAP
    );
    let _ = plain;
    println!("slowest day: {:.0} us on day {} ({worst_parts})", worst.0, worst.1);
    let days = (years * 360) as f64;
    let t = p.timing;
    println!(
        "per day us: events={:.1} needs={:.0} travel={:.1} health={:.0} marriage={:.0} relations={:.0} trips={:.0} jobs={:.0} migration={:.0} | per month us: index={:.0} pops={:.0} ({} pops)",
        t.events / days,
        t.needs / days,
        t.travel / days,
        t.health / days,
        t.marriage / days,
        t.relations / days,
        t.trips / days,
        t.jobs / days,
        t.migration / days,
        t.index / (days / 30.0),
        t.pops / (days / 30.0),
        p.groups.pops.len(),
    );
    let g = &p.groups;
    let list = |names: &[&str], n: &[u32]| names.iter().zip(n).map(|(k, v)| format!("{k} {v}")).collect::<Vec<_>>().join(", ");
    println!("pops: {} for {} people (last monthly count)", g.pops.len(), g.people);
    println!("occupations: {}", list(&apoleia_sim::groups::JOB_NAMES, &g.economic));
    println!("political groups (members): {}", list(&apoleia_sim::groups::POLITICAL_NAMES, &g.political));
    if slices {
        println!("day of month: total us (events needs travel health marriage relations trips jobs migration index pops)");
        for (d, r) in by_slice.iter().enumerate() {
            let n = r[12].max(1.0);
            println!("{d:2}: {:6.0} ({})", r[11] / n, (0..11).map(|k| format!("{:.0}", r[k] / n)).collect::<Vec<_>>().join(" "));
        }
    }
    println!("fingerprint={:016x}", p.fingerprint());
}
