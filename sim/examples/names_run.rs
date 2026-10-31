//! Names over the years (crate::names, docs/kit2/NAMES.md): how parents
//! chose, the most frequent names of each origin by decade, how many lines
//! live on, a sample of full names, and the fingerprints (names change
//! nothing else in the simulation).
//!
//! Usage: cargo run --release --example names_run -- [--years N] [--seed S]
//!        [--root DIR] [--csv PATH]

use apoleia_sim::game::{Game, Start};
use apoleia_sim::names::{stock, NONE};
use rustc_hash::FxHashMap;
use std::fmt::Write as _;
use std::path::PathBuf;

const HOW: [&str; 6] = ["Start", "Verwandte", "abgeleitet", "Nachbarschaft", "Kultur", "selten alt"];

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let arg = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let years: i64 = arg("--years").map_or(10, |v| v.parse().unwrap());
    let seed: u64 = arg("--seed").map_or(1, |v| v.parse().unwrap());
    let root = PathBuf::from(arg("--root").unwrap_or_else(|| "..".into()));
    let inp = apoleia_sim::inputs::load(&root, false).expect("inputs");
    let cols: Vec<String> = apoleia_sim::grain::CLEAR_COVER.iter().map(|c| c.to_string()).collect();
    let clear = apoleia_sim::grain::clearable(&root, &cols).ok();
    let cover = apoleia_sim::grain::fine_cover(&root, true).ok();
    let start = Start { inputs: &inp, clear: clear.as_ref(), cover: cover.as_ref() };
    let mut g = Game::new(start, seed);
    let s = stock();
    let mut csv = String::from("decade,origin,sex,rank,name,births,share\n");
    let mut first = g.people.names.people.len();
    // what the names cost at the start: the same again, timed
    {
        let mut q = g.people.world.query::<(&apoleia_sim::people::Pid, &apoleia_sim::people::Sex, &apoleia_sim::people::Household, &apoleia_sim::people::Stand, &apoleia_sim::people::Born)>();
        let v: Vec<apoleia_sim::names::StartPerson> = q
            .iter(&g.people.world)
            .map(|(p, sx, h, st, b)| apoleia_sim::names::StartPerson { pid: p.0, female: sx.0 == 0, household: h.0, stand: st.0, origin: (p.0 % 7) as u8, region: p.0 % 1800, born: b.0 })
            .collect();
        let t = std::time::Instant::now();
        let again = apoleia_sim::names::Names::start(seed, &v, 1800);
        println!("names at the start: {:.1} ms for {} people", t.elapsed().as_secs_f64() * 1e3, again.people.len());
    }
    println!("start: {} people, {} lines", g.people.count, g.people.names.lines.len());
    for y in 1..=years {
        for _ in 0..apoleia_sim::life::YEAR {
            g.day();
        }
        if y % 10 != 0 && y != years {
            continue;
        }
        let n = &g.people.names;
        let total: u64 = n.chosen.iter().sum();
        let how: Vec<String> = (1..6).map(|k| format!("{} {:.0} %", HOW[k], 100.0 * n.chosen[k] as f64 / total.max(1) as f64)).collect();
        // living lines and people
        let mut q = g.people.world.query::<&apoleia_sim::people::Pid>();
        let alive: Vec<u32> = q.iter(&g.people.world).map(|p| p.0).collect();
        let mut lines: FxHashMap<u32, u32> = FxHashMap::default();
        for &pid in &alive {
            if let Some(l) = n.line_of(pid) {
                *lines.entry(l).or_default() += 1;
            }
        }
        let start_lines = lines.keys().filter(|&&l| n.lines[l as usize].since == 0).count();
        let biggest = lines.values().max().copied().unwrap_or(0);
        println!("year {y}: {} people, births {total}: {}; lines alive {} of {} ({} from the start), largest {biggest}", alive.len(), how.join(", "), lines.len(), n.lines.len(), start_lines);
        // the births since the last report, by origin and sex
        let mut by: FxHashMap<(u8, bool), FxHashMap<u16, u32>> = FxHashMap::default();
        for named in &n.people[first..] {
            if named.line == NONE {
                continue;
            }
            let o = n.lines[named.line as usize].origin;
            *by.entry((o, s.forms[named.given as usize].female)).or_default().entry(named.given).or_default() += 1;
        }
        for o in 0..7u8 {
            let mut line = format!("  {:8}", apoleia_sim::dna::ORIGINS[o as usize]);
            for female in [false, true] {
                let Some(c) = by.get(&(o, female)) else { continue };
                let sum: u32 = c.values().sum();
                let mut v: Vec<(u16, u32)> = c.iter().map(|(&f, &k)| (f, k)).collect();
                v.sort_by_key(|x| (std::cmp::Reverse(x.1), x.0));
                let top: Vec<String> = v.iter().take(5).map(|(f, k)| format!("{} {:.1}", s.forms[*f as usize].text, 100.0 * *k as f64 / sum as f64)).collect();
                let _ = write!(line, " | {} ({sum}, {} Namen): {}", if female { "w" } else { "m" }, v.len(), top.join(", "));
                for (rank, (f, k)) in v.iter().take(20).enumerate() {
                    let _ = writeln!(csv, "{},{},{},{},{},{},{:.4}", y - 1, apoleia_sim::dna::ORIGINS[o as usize], if female { "f" } else { "m" }, rank + 1, s.forms[*f as usize].text, k, *k as f64 / sum as f64);
                }
            }
            println!("{line}");
        }
        first = n.people.len();
    }
    // a sample of full names with their parts
    let n = &g.people.names;
    let mut q = g.people.world.query::<&apoleia_sim::people::Pid>();
    let mut alive: Vec<u32> = q.iter(&g.people.world).map(|p| p.0).collect();
    alive.sort_unstable();
    let mut shown = [0; 7];
    for &pid in alive.iter().rev() {
        let Some(sh) = n.shown(pid) else { continue };
        let o = apoleia_sim::dna::ORIGINS.iter().position(|x| *x == sh.origin).unwrap();
        if shown[o] >= 3 {
            continue;
        }
        shown[o] += 1;
        println!("{:8} {}", sh.origin, sh.full);
        for p in &sh.parts {
            println!("           {} ({}): {}", p.text, p.role, p.about);
        }
    }
    let (fp, fg) = g.fingerprints();
    println!("fingerprints: people {fp:016x} grain {fg:016x}");
    if let Some(path) = arg("--csv") {
        std::fs::write(path, csv).expect("csv");
    }
}
