//! Prototype run for the grain economy (S69–S76) on top of the people
//! (S50–S67): farms, harvest and day labour, one market per region,
//! carriers, traders, hunger, tents and footpaths. Reports a yearly table,
//! tick times (people and grain apart), memory and fingerprints.
//!
//! Usage: grain [--years N] [--seed S] [--threads N] [--root DIR]
//!              [--clear-pct P] [--clear-cover COL,COL,…|usable] [--crop-pct P]
//!              [--inherit equal|now|one] [--no-floor] [--no-sow-price]
//!              [--sales-month] [--no-carry-sale]

use apoleia_sim::grain::{Grain, GOODS};
use apoleia_sim::people::People;
use std::path::PathBuf;
use std::time::Instant;

fn rss_mb() -> f64 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| s.lines().find(|l| l.starts_with("VmRSS:")).and_then(|l| l.split_whitespace().nth(1)?.parse::<f64>().ok()))
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
    let arg = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let years: i64 = arg("--years").map_or(10, |v| v.parse().unwrap());
    let seed: u64 = arg("--seed").map_or(1, |v| v.parse().unwrap());
    let root = PathBuf::from(arg("--root").unwrap_or_else(|| "..".into()));
    if let Some(n) = arg("--threads") {
        bevy_tasks::ComputeTaskPool::get_or_init(|| bevy_tasks::TaskPoolBuilder::new().num_threads(n.parse().unwrap()).build());
    }
    let inp = apoleia_sim::inputs::load(&root, false).expect("inputs");
    let t0 = Instant::now();
    let mut p = People::new(&inp, seed);
    // Inheritance at the father's death (S83): equal (default) | now | one.
    p.inherit = match arg("--inherit").as_deref() {
        Some("now") => apoleia_sim::people::INHERIT_NOW,
        None | Some("equal") => apoleia_sim::people::INHERIT_EQUAL,
        Some("one") => apoleia_sim::people::INHERIT_ONE,
        Some(v) => panic!("--inherit now|equal|one, not {v}"),
    };
    // S86 calibration: never-married women per 1,000, divorces per 10,000 marriages and year.
    if let Some(v) = arg("--never") {
        p.never_marry_per_1000 = v.parse().unwrap();
    }
    if let Some(v) = arg("--divorce") {
        p.divorce_per_10k_year = v.parse().unwrap();
    }
    // S89: hunger deaths per 1,000 deaths taken out of the life table.
    if let Some(v) = arg("--table-hunger") {
        p.table_hunger_per_1000 = v.parse().unwrap();
    }
    let people_ms = t0.elapsed().as_secs_f64() * 1e3;
    let t0 = Instant::now();
    let clear: i64 = arg("--clear-pct").map_or(apoleia_sim::grain::CLEAR_PCT, |v| v.parse().unwrap());
    // Clearable land (S73): the columns of sim/inputs/landcover25.csv that
    // count, by default today's farmland below 16 % slope
    // (grain::CLEAR_COVER); `--clear-cover usable` for all usable land.
    let cols = arg("--clear-cover").unwrap_or_else(|| apoleia_sim::grain::CLEAR_COVER.join(","));
    let cover = (cols != "usable").then(|| {
        let cols: Vec<String> = cols.split(',').map(str::to_owned).collect();
        apoleia_sim::grain::clearable(&root, &cols).expect("landcover25.csv")
    });
    println!("clearable land: {cols}");
    let crop: i64 = arg("--crop-pct").map_or(apoleia_sim::grain::CROP_PCT, |v| v.parse().unwrap());
    println!("fields under grain each year: {crop} % (fallow {} %)", 100 - crop);
    // Fields on fine tiles (S73): on farmland tiles with the default
    // columns, else on land tiles.
    let fine = apoleia_sim::grain::fine_cover(&root, cols == apoleia_sim::grain::CLEAR_COVER.join(",")).expect("landcover-fine.bin.zst");
    let mut g = Grain::with_clearing(&inp, &mut p, clear, cover.as_ref(), Some(&fine), crop);
    // S123, S124: off to measure without the storage floor or the own
    // sowing by price.
    g.storage_floor = !args.iter().any(|a| a == "--no-floor");
    g.sow_by_price = !args.iter().any(|a| a == "--no-sow-price");
    g.sales_year = !args.iter().any(|a| a == "--sales-month");
    g.carry_sale = !args.iter().any(|a| a == "--no-carry-sale");
    g.state_spend = !args.iter().any(|a| a == "--no-state-spend");
    g.food_plan = !args.iter().any(|a| a == "--no-food-plan");
    println!("storage floor (S123): {}, own sowing by price (S124): {}, sales over a year (S125): {}, granaries sell carry-over (S126): {}", g.storage_floor, g.sow_by_price, g.sales_year, g.carry_sale);
    println!("treasury spends its surplus (S129): {}, farms' food plan (S130): {}", g.state_spend, g.food_plan);
    drop(fine);
    // S106: pasture near the fields, grassland per farmland of each cell.
    let grass = apoleia_sim::grain::clearable(&root, &["grass_8", "grass_16", "grass_30", "grass_steep"].map(String::from)).expect("landcover25.csv");
    let farm = apoleia_sim::grain::clearable(&root, &["farm_8", "farm_16", "farm_30", "farm_steep"].map(String::from)).expect("landcover25.csv");
    g.set_pasture(&p, &grass, &farm);
    // S110 off, for comparison: the state wage for all wage and trader
    // households.
    g.wage_all = arg("--state-wage").is_some_and(|v| v == "all");
    let grain_ms = t0.elapsed().as_secs_f64() * 1e3;
    let (farms, kinds, tents, tent_people, ha, fs, ms) = g.summary();
    println!(
        "people={} markets={} farms={farms} (family {} tenant {} estate {}) tents={tents} ({tent_people} people) fields_ha={ha:.0} farm_store_t={fs:.0} market_t={ms:.0} | spawn people {people_ms:.0} ms, grain {grain_ms:.0} ms, rss_mb={:.0}",
        p.count,
        g.markets.len(),
        kinds[0],
        kinds[1],
        kinds[2],
        rss_mb()
    );
    // Rome: the cell with the most people.
    let rome = (0..p.pop.len() as u32).max_by_key(|&c| p.pop[c as usize]).unwrap();
    let (mut all, mut grain_us) = (Vec::new(), Vec::new());
    let mut worst = (0.0, 0i64);
    let mut last = p.count as f64;
    println!(
        "year  people growth%  births deaths hunger left  farms tents/ppl  harvest_t lost_t sow_short_ha hired_d  sold_t bought_t trade_trips traded_t  alms_t stolen_t  eaten%  price min/med/max  rome  trails paths  hungry  ms_day married_w% divorces"
    );
    let (mut heirs, mut splits, mut by_wage) = (0u64, 0u64, 0u64);
    for y in 1..=years {
        by_wage += g.stats.start_by_wage;
        heirs += g.stats.heirs_given;
        splits += p.stats.split_households;
        p.stats = Default::default();
        g.stats = Default::default();
        let mut ysum = 0.0;
        for _ in 0..360 {
            let t = Instant::now();
            p.day();
            let tg = Instant::now();
            g.day(&mut p);
            let gu = tg.elapsed().as_secs_f64() * 1e6;
            let us = t.elapsed().as_secs_f64() * 1e6;
            ysum += us;
            all.push(us);
            grain_us.push(gu);
            if gu > worst.0 {
                worst = (gu, (y - 1) * 360 + all.len() as i64 % 360);
            }
        }
        let s = p.stats;
        let gs = g.stats;
        let (mw, w, _, hungry) = p.census();
        let (farms, _, tents, tent_people, _, _, _) = g.summary();
        let (pmin, pmed, pmax) = g.price_spread();
        let (trails, paths) = g.path_cells();
        let growth = 100.0 * (p.count as f64 / last - 1.0);
        last = p.count as f64;
        println!(
            "{y:4} {:7} {:6.2} {:7} {:6} {:6} {:5} {:6} {:5}/{:5} {:9.0} {:6.0} {:12.0} {:8} {:7.0} {:8.0} {:11} {:8.0} {:7.0} {:8.0} {:7.1} {:5.2}/{:5.2}/{:5.2} {:5.2} {:6} {:5} {:7} {:6.2} {:6.1} {:5}",
            p.count,
            growth,
            s.births,
            s.deaths.iter().sum::<u64>(),
            s.deaths[2],
            s.left_people,
            farms,
            tents,
            tent_people,
            gs.harvest_kg as f64 / 1e3,
            gs.harvest_lost_kg as f64 / 1e3,
            gs.sow_short_m2 as f64 / 1e4,
            gs.hired_days,
            gs.sold_kg as f64 / 1e3,
            gs.bought_kg as f64 / 1e3,
            gs.trade_trips,
            gs.traded_kg as f64 / 1e3,
            gs.alms_kg as f64 / 1e3,
            gs.stolen_kg as f64 / 1e3,
            100.0 * gs.eaten_kg as f64 / gs.need_kg.max(1) as f64,
            pmin,
            pmed,
            pmax,
            g.price_at(rome),
            trails,
            paths,
            hungry,
            ysum / 360.0 / 1e3,
            100.0 * mw as f64 / w.max(1) as f64,
            s.divorces
        );
        // The money cycle (S94 step 1), in denarii since the start.
        let (m, t) = (g.money, g.treasury);
        let den = |x: i64| x as f64 / 1e3;
        println!(
            "      money den (S94): held {:.0} treasury {:.0} | start {:.0} + minted {:.0} + endowed {:.0} - freight {:.0} - left map {:.0} | unbooked {:.3} | state wages {:.0} tax {:.0} state rent {:.0} estates {:.0} tax grain t {:.0} | public works (S129) den {:.0} days {} (this year den {:.0} days {})",
            den(g.money_held()),
            den(t.cash),
            den(m.start),
            den(m.minted),
            den(m.endowed),
            den(m.freight),
            den(m.left_map),
            den(g.money_unbooked()),
            den(t.wages),
            den(t.tax),
            den(t.rent),
            den(t.estates),
            t.grain_kg as f64 / 1e3,
            den(t.public_works),
            t.public_days,
            den(gs.public_paid),
            gs.public_days
        );
        let by: Vec<String> = (0..5).map(|k| format!("{:.0}%", 100.0 * gs.eaten_by[k] as f64 / gs.need_by[k].max(1) as f64)).collect();
        if std::env::var("PRICE_DEBUG").is_ok() {
            print!("{}", g.price_debug());
        }
        if std::env::var("GRAIN_DEBUG").is_ok() {
            print!("{}", g.debug());
            println!("  field rebuilds {} sell trips {} buy trips {} seed t {:.0} unsown for want of seed ha {:.0}", gs.field_rebuilds, gs.sell_trips, gs.buy_trips, gs.seed_kg as f64 / 1e3, gs.seed_short_m2 as f64 / 1e4);
        }
        // S121: the markets beyond the map.
        let outer: Vec<String> = g
            .outer
            .iter()
            .zip(gs.outer)
            .map(|(o, x)| format!("{} {} ppl price {:.2} store/held t {:.0}/{:.0} harvest t {:.0} eaten {:.0} % from/to us t {:.0}/{:.0}", o.name, o.people, o.price as f64 / 1e3, o.store as f64 / 1e3, o.held as f64 / 1e3, x[0] as f64 / 1e3, 100.0 * x[1] as f64 / x[2].max(1) as f64, x[4] as f64 / 1e3, x[3] as f64 / 1e3))
            .collect();
        println!("      beyond the map (S121): {}", outer.join(" | "));
        println!("      spoiled t {:.0} | eaten by kind (farm/tent/wage/trader/elite): {} | to tents without workers or kin (S79): {} | tent moves (S75): {} | Manciana farms new/lost (S92): {}/{} | fed by own food (S91): {} | moved people yearly/monthly (S66/S93): {}/{} | trade tracks/roads/sea lanes (cells): {:?}", gs.spoiled_kg as f64 / 1e3, by.join(" "), gs.to_tents, gs.tent_moves, gs.manciana_new, gs.manciana_lost, gs.own_food_people / 12, s.moved_people - s.moved_monthly, s.moved_monthly, g.road_cells(&p));
        // Craft goods (S105–S110, S118): per good wool/iron/clothing/tools/pottery/pork.
        let (held, store, price) = g.goods_report();
        let gg = gs.goods;
        let per = |v: [i64; GOODS]| v.map(|x| format!("{:.0}", x as f64 / 1e3)).join("/");
        println!(
            "      goods (wool/iron/cloth/tools/pots/pork): median price den {} | market stock {} | made {} | bought {} | moved {} | gate in {} out {} | home cloth {:.0} shorn kg {:.0} | months labour/weaver/smith/potter {:?} state {} | clothes short {:.0} % | hired for money days {} den {:.0} (by dealers {:.0}) | held: clothes {:.0} pots kg {:.0} tools kg {:.0} jars kg {:.0} wool kg {:.0} sheep {:.0} pigs a year {:.0} | spend den {:.0} | grain fed to pigs t {:.0} | rations to state servants t {:.0}",
            price.map(|x| format!("{x:.2}")).join("/"),
            store.map(|x| format!("{x:.0}")).join("/"),
            per(gg.made),
            per(gg.bought),
            per(gg.moved),
            per(gg.out_import),
            per(gg.out_export),
            gg.home_cloth as f64 / 1e3,
            gg.shorn as f64 / 1e3,
            gg.crafts,
            gg.state_months,
            100.0 * gg.clothes_short as f64 / gg.clothes_need.max(1) as f64,
            gg.serve_days,
            gg.serve_paid as f64 / 1e3,
            gg.dealer_paid as f64 / 1e3,
            held[0],
            held[1],
            held[2],
            held[3],
            held[4],
            held[5],
            held[6],
            gg.budget as f64 / 1e3,
            gs.feed_kg as f64 / 1e3,
            gs.rations_kg as f64 / 1e3
        );
        if std::env::var("GOODS_DEBUG").is_ok() {
            println!("      money by kind (farm/tent/wage/trader/elite), dealers: {:.0?}", g.money_by_kind());
            println!("      clothes held % of need, households, below half (farm/tent/wage/trader/elite): {:?}", g.clothes_by_kind());
        }
        let (kh, kp, idle_n, idle_ha) = g.kinds_report();
        println!("      households (farm/tent/wage/trader/elite): {:?} people {:?} | farms without household: {idle_n} ({idle_ha:.0} ha), fields back to free land: {}", kh, kp, gs.farms_lapsed);
    }
    println!(
        "day_us all p50={:.0} p95={:.0} p99={:.0} max={:.0} | grain p50={:.0} mean={:.0} p95={:.0} p99={:.0} max={:.0} (day {}) | rss_mb={:.0} peak_people={}",
        pct(all.clone(), 0.5),
        pct(all.clone(), 0.95),
        pct(all.clone(), 0.99),
        pct(all, 1.0),
        pct(grain_us.clone(), 0.5),
        grain_us.iter().sum::<f64>() / grain_us.len().max(1) as f64,
        pct(grain_us.clone(), 0.95),
        pct(grain_us.clone(), 0.99),
        pct(grain_us, 1.0),
        worst.1,
        rss_mb(),
        p.peak
    );
    let days = (years * 360) as f64;
    let t = g.timing;
    println!(
        "grain per day us: events={:.0} peaks={:.0} labour={:.0} markets={:.0} eat={:.0} traders={:.0} paths={:.0} (rebuild {:.0}, first builds in total {:.0} ms) | per month us: census={:.0}",
        t.events / days,
        t.peaks / days,
        t.labour / days,
        t.markets / days,
        t.eat / days,
        t.traders / days,
        t.paths / days,
        t.rebuild / days,
        t.first_build / 1e3,
        t.census / (days / 30.0)
    );
    let mut lanes: Vec<(i64, u32)> = g.lanes.iter().map(|(&c, &n)| (n, c)).collect();
    lanes.sort_unstable_by(|a, b| b.cmp(a));
    println!("busiest trade cells (trips, cell): {:?}", &lanes[..lanes.len().min(10)]);
    by_wage += g.stats.start_by_wage;
    heirs += g.stats.heirs_given;
    splits += p.stats.split_households;
    let (n, ha, short) = g.land_report();
    println!(
        "start: farm households living by a wage instead (S87) {by_wage} | inherit={} | splits {splits}, heirs given land {heirs} | farms {n}: ha p10 {:.1} median {:.1} p90 {:.1} mean {:.1}; too small to feed their household {short:.1} %",
        arg("--inherit").unwrap_or_else(|| "equal".into()),
        ha[0],
        ha[1],
        ha[2],
        ha[3]
    );
    println!("fingerprint people={:016x} grain={:016x}", p.fingerprint(), g.fingerprint());
}
