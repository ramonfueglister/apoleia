//! Markets beyond the map (S121, Ramon 30.10.2026: „draussen märkte müssen
//! auch angebot und nachfrage folgen natürlich“, then the card „Märkte
//! draussen plus Saatgut“ on the proposal „Hunger und Märkte draussen:
//! Befund und Vorschlag“, https://claude.ai/artifact/DvWYeGWVBj2fR2XTCuYvXC).
//! They replace S98's fixed price and unlimited quantity.
//!
//! Beyond each edge of the map lies a band of OUT_KM with its people in
//! HYDE 3.3, the source of the map's people (Klein Goldewijk, 2024;
//! `tools/sim_outside.py`). Each band is one market, computed as the
//! markets on the map are:
//! - its farmers bring in a harvest once a year and keep food to the next
//!   harvest and the reserve (as the farms on the map); that they sell to
//!   the dealers when these pay the usual price of the season, as far as
//!   the dealers plan stock (S112: storage), what they hold beyond it for
//!   what the dealers pay, up to the dealers' limit (S100);
//! - its people eat every day, a little less when grain is dear and a
//!   little more when it is cheap;
//! - its dealers quote from their stock and sales (`pricing::quote`);
//! - the gate markets on the map (S98: a way over the edge) trade with it
//!   as with a neighbour, both ways: fetch (S114) and send (S120), with the
//!   freight of OUT_KM by wagon or by the sea route.
//! This is the spatial price equilibrium with storage (Samuelson, 1952;
//! Takayama & Judge, 1971; Williams & Wright, 1991; Makki et al., 2001):
//! beyond the map is one more place, not a price.
//!
//! Built here (own choices, PLACEHOLDER where marked):
//! - A normal harvest feeds the band's people for a year, with the
//!   spoilage of carrying half of it (PLACEHOLDER: no weather, as on the
//!   map until S101). HYDE's cropland per head is about the map's (east
//!   1.27 ha, map 1.06 ha); where it is lower (south 0.56 ha) people lived
//!   more from herds, which this model does not have, so the cropland is
//!   not used. Their need per head is the map's.
//! - They sow for their own food as the farms on the map (S99): a normal
//!   harvest less what they still hold beyond it. They sow nothing more
//!   for the market when grain is dear (PLACEHOLDER: their wage is not
//!   known).
//! - The demand is linear around the usual price with the elasticity of
//!   DEMAND_ELAST_X1000 there, between half and one and a half of the need
//!   (bounds frei gewählt).
//! - Their money is not on the map: what we sell them brings denarii in
//!   (`Money::exports`), what we buy carries them out (`Money::imports`),
//!   and the freight they pay is theirs. Their dealers buy as far as they
//!   plan stock, without a cash limit (PLACEHOLDER).
//! - Craft goods still meet S98's fixed prices at the gates (a later step).

use super::*;

pub const SIDES: usize = 4;
const EAST: usize = 0;
const SOUTH: usize = 1;
const NORTH: usize = 2;
const WEST: usize = 3;

/// The OUT_KM band beyond each edge of the map: name, people in HYDE 3.3
/// for 200 AD, and their mean longitude and latitude × 10
/// (`tools/sim_outside.py`).
const OUTERS: [(usize, &str, i64, i64, i64); SIDES] = [
    // Mesene, Susiana, Media, the Caspian lowland.
    (EAST, "Jenseits des Zagros", 3_488_240, 489, 364),
    // Nubia with Meroë, Asir, the Sahara.
    (SOUTH, "Nubien und Arabien", 728_797, 346, 187),
    // Southern Scandinavia, Finland, northern Russia.
    (NORTH, "Skandinavien und Nordrussland", 402_320, 206, 597),
    // The Atlantic coast of the Western Sahara.
    (WEST, "Atlantikküste", 40_028, -144, 282),
];

/// Price elasticity of their demand for grain at the usual price, per
/// mille, as a positive number: −0.05 to −0.08 for the world's calories
/// from wheat, maize, rice and soybeans (Roberts & Schlenker, 2013), the
/// middle.
const DEMAND_ELAST_X1000: i64 = 65;

/// Their sowing day: the map's from late October (`new_farm`, PLACEHOLDER
/// there too).
const SOW_DOY: i64 = 295;

/// One market beyond the map.
pub struct Outer {
    pub name: &'static str,
    pub lon: f64,
    pub lat: f64,
    /// Simulated people (HYDE ÷ PEOPLE_PER_PERSON) and what they eat at
    /// the usual price, kg a day.
    pub people: i64,
    need_day: i64,
    /// A normal harvest, kg; the coming harvest, sown less by what the
    /// farmers still hold beyond their need (S99); its day of the year.
    base: i64,
    pub harvest: i64,
    pub harvest_doy: i64,
    /// Grain held by the farmers, and by the dealers.
    pub held: i64,
    pub store: i64,
    pub price: i64,
    norm: i64,
    /// Smoothed sales per day, kg × 1000, with what was asked for and not
    /// there (as `Market::demand`).
    pub demand: i64,
    sold_today: i64,
    missed_today: i64,
}

/// Yearly figures per market beyond the map, kg (`GrainStats::outer`).
pub const HARVEST: usize = 0;
pub const EATEN: usize = 1;
pub const WANTED: usize = 2;
/// Sold to the gates on the map, bought from them.
pub const TO_MAP: usize = 3;
pub const FROM_MAP: usize = 4;

impl Grain {
    /// S98, S121: freight from each market to each market beyond the map:
    /// by sea from its port (the cheapest way over sea cells to a sea cell
    /// at that edge of the map, then OUT_KM), or by wagon OUT_KM from a
    /// region that has a land cell at that edge; the cheaper of the two,
    /// 0 without a way. `out_cost` is the cheapest of them (craft goods).
    pub(super) fn gates(&mut self, p: &People) {
        let (rows, cols) = (p.grid.rows, p.grid.cols);
        let n = (rows * cols) as usize;
        let kind = &p.grid.kind;
        // Row 0 is the north (the rows run south, tools/sim_hyde.py).
        let at_edge = |i: usize, side: usize| {
            let (r, c) = (i as i32 / cols, i as i32 % cols);
            match side {
                EAST => c == cols - 1,
                SOUTH => r == rows - 1,
                NORTH => r == 0,
                _ => c == 0,
            }
        };
        for side in 0..SIDES {
            // Sea km × 1000 from each sea cell to this edge (Dijkstra, 8 ways).
            let mut dist = vec![i64::MAX; n];
            let mut open = BinaryHeap::new();
            for i in 0..n {
                if kind[i] == 0 && at_edge(i, side) {
                    dist[i] = 0;
                    open.push(Reverse((0i64, i as u32)));
                }
            }
            while let Some(Reverse((d, i))) = open.pop() {
                if d > dist[i as usize] {
                    continue;
                }
                let (r, c) = (i as i32 / cols, i as i32 % cols);
                for (dr, dc) in DIRS {
                    let (rr, cc) = (r + dr, c + dc);
                    if rr < 0 || cc < 0 || rr >= rows || cc >= cols {
                        continue;
                    }
                    let j = (rr * cols + cc) as usize;
                    if kind[j] != 0 {
                        continue;
                    }
                    let nd = d + if dr != 0 && dc != 0 { 35_355 } else { 25_000 };
                    if nd < dist[j] {
                        dist[j] = nd;
                        open.push(Reverse((nd, j as u32)));
                    }
                }
            }
            let mut cost = vec![i64::MAX; self.markets.len()];
            for (i, &m) in self.cell_market.iter().enumerate() {
                if m != NONE && at_edge(i, side) {
                    cost[m as usize] = cost[m as usize].min(OUT_KM * WAGON_COST);
                }
            }
            for (k, mk) in self.markets.iter().enumerate() {
                let c = mk.cell as usize;
                if kind[c] != 1 {
                    continue;
                }
                let (r, col) = (c as i32 / cols, c as i32 % cols);
                for (dr, dc) in DIRS {
                    let (rr, cc) = (r + dr, col + dc);
                    if rr < 0 || cc < 0 || rr >= rows || cc >= cols {
                        continue;
                    }
                    let d = dist[(rr * cols + cc) as usize];
                    if d != i64::MAX {
                        cost[k] = cost[k].min((d / 1000 + 25 + OUT_KM) * SEA_COST);
                    }
                }
            }
            for (mk, c) in self.markets.iter_mut().zip(cost) {
                mk.outs[side] = if c == i64::MAX { 0 } else { c.max(1) };
            }
        }
        for mk in self.markets.iter_mut() {
            mk.out_cost = mk.outs.iter().copied().filter(|&c| c > 0).min().unwrap_or(0);
        }
    }

    /// S121: the markets beyond the map on the first day, after the map's
    /// start stocks: people from HYDE with the map's need per head, a
    /// harvest that feeds them; farmers hold the rest of last year's
    /// harvest, dealers the stock they plan (as on the map, S112).
    pub(super) fn outer_start(&mut self) {
        let (mut need, mut people) = (0i64, 0i64);
        for i in self.info.values() {
            need += i.need_w as i64 * KG_PER_ADULT_YEAR / 10;
            people += i.size as i64;
        }
        self.outer = OUTERS
            .iter()
            .map(|&(_, name, pop, lon10, lat10)| {
                let sim_people = (pop as f64 / crate::people::PEOPLE_PER_PERSON).round() as i64;
                let need_day = sim_people * need / people.max(1) / YEAR;
                let harvest = need_day * YEAR * (200 + SPOIL_PCT_YEAR) / 200;
                // The harvest day as on the map (`new_farm`): from the north
                // coordinate of the people's mean latitude (tools/sim_hyde.py).
                let z = -6_371_008.8 * ((lat10 as f64 / 10.0) - 41.0).to_radians();
                let harvest_doy = (165 + ((-99_842.0 - z) / 100_000.0 * 2.0) as i64).clamp(100, 230);
                Outer {
                    name,
                    lon: lon10 as f64 / 10.0,
                    lat: lat10 as f64 / 10.0,
                    people: sim_people,
                    need_day,
                    base: harvest,
                    harvest,
                    harvest_doy,
                    held: harvest * doy_until(self.today, harvest_doy) / YEAR,
                    store: need_day * TARGET_DAYS,
                    price: BASE_PRICE,
                    norm: BASE_PRICE * 1000,
                    demand: need_day * 1000,
                    sold_today: 0,
                    missed_today: 0,
                }
            })
            .collect();
    }

    /// S121, daily: harvest, the farmers' sales to the dealers, the
    /// dealers' quote, the people's purchases and the spoilage.
    pub(super) fn outer_day(&mut self) {
        let today = doy(self.today);
        let carry = pricing::INTEREST_PCT_YEAR + SPOIL_PCT_YEAR;
        for (k, o) in self.outer.iter_mut().enumerate() {
            let st = &mut self.stats.outer[k];
            if today == o.harvest_doy {
                o.held += o.harvest;
                st[HARVEST] += o.harvest;
            }
            // S99 as on the map: at sowing the farmers sow a normal harvest,
            // less what they will still hold beyond their food and reserve
            // at the next harvest (after a year's spoilage). They feed
            // themselves; a surplus stays in their stores.
            if today == SOW_DOY {
                let carry = (o.held - o.need_day * (doy_until(self.today, o.harvest_doy) + RESERVE_DAYS)).max(0) * (100 - SPOIL_PCT_YEAR) / 100;
                o.harvest = (o.base - carry).max(0);
            }
            // Yesterday's sales, here and to the gates, with what was asked
            // for and not there (as `Market::demand`).
            o.demand += ((o.sold_today + o.missed_today) * 1000 - o.demand) / MONTH;
            o.sold_today = 0;
            o.missed_today = 0;
            let season = pricing::season(today - o.harvest_doy, carry);
            let usual = (o.norm / 1000 * season / 1000).max(1);
            // The farmers sell their food to the next harvest and the
            // reserve when the dealers pay the usual price of the season
            // (S112), as far as the dealers plan stock (TARGET_DAYS); what
            // they hold beyond it for any price, up to the dealers' limit
            // (S100). At most a week of sales a day.
            let keep = o.need_day * (doy_until(self.today, o.harvest_doy) + RESERVE_DAYS);
            let per_day = o.demand / 1000;
            let at_usual = if o.price >= usual { (per_day * TARGET_DAYS - o.store).min(o.held) } else { 0 };
            let beyond = (o.held - keep).min(per_day * DEALER_MAX_DAYS - o.store);
            let kg = at_usual.max(beyond).min(per_day * 7).max(0);
            o.held -= kg;
            o.store += kg;
            // The dealers quote for the day from that stock, then the
            // people buy their need moved by the price against the usual
            // price (linear, elasticity DEMAND_ELAST_X1000).
            pricing::quote(&mut o.price, &mut o.norm, o.store, o.demand / 1000, season);
            let usual = (o.norm / 1000 * season / 1000).max(1);
            let want = (o.need_day * (1000 - DEMAND_ELAST_X1000 * (o.price - usual) / usual) / 1000).clamp(o.need_day / 2, o.need_day * 3 / 2);
            let sold = want.min(o.store).max(0);
            o.store -= sold;
            o.sold_today += sold;
            o.missed_today += want - sold;
            st[EATEN] += sold;
            st[WANTED] += want;
            // Spoilage (S72), a day's share.
            o.held -= o.held * SPOIL_PCT_YEAR / 100 / YEAR;
            o.store -= o.store * SPOIL_PCT_YEAR / 100 / YEAR;
        }
    }

    /// S121 (in place of S98's fixed price): each gate market trades with
    /// the markets beyond the map it has a way to, on its day of the week,
    /// as with a neighbour on the map. Their dealers fetch from it (S114)
    /// when its price with freight is below theirs, and it fetches from
    /// them the other way round; dealers holding more than they plan send
    /// to the other side when it pays more after freight (S120). The
    /// gate's dealers pay with their cash; the freight goes with the
    /// fetching or sending side.
    pub(super) fn outside(&mut self, day: i64) {
        let wd = day.rem_euclid(7) as usize;
        for mi in (wd..self.markets.len()).step_by(7) {
            if self.markets[mi].out_cost == 0 {
                continue;
            }
            for k in 0..SIDES {
                if self.markets[mi].outs[k] == 0 {
                    continue;
                }
                let cost = self.freight(self.markets[mi].outs[k], mi);
                // Their dealers fetch from the gate (S114, up to a week of
                // their sales and the stock they plan).
                let (g, o) = (&self.markets[mi], &self.outer[k]);
                let room = (o.demand / 1000 * TARGET_DAYS - o.store).min(o.demand / 1000 * 7);
                let price = Self::sell_price(g);
                if room > 0 && o.price - price - cost > 0 {
                    let kg = (g.store / 4).min(room).max(0);
                    self.sell_out(mi, k, kg, price, 0);
                }
                // The gate's dealers send them what they hold beyond their
                // plan (S120), up to the stock those dealers take.
                let (g, o) = (&self.markets[mi], &self.outer[k]);
                let excess = (g.store - g.demand / 1000 * TARGET_DAYS).min(g.store / 4);
                let price = Self::buy_price_of(o.price);
                if excess > 0 && price - cost - g.price > 0 {
                    let kg = excess.min(o.demand / 1000 * DEALER_MAX_DAYS - o.store).max(0);
                    self.sell_out(mi, k, kg, price, cost);
                }
                // The gate's dealers fetch from them (S114).
                let (g, o) = (&self.markets[mi], &self.outer[k]);
                let room = (g.demand / 1000 * TARGET_DAYS - g.store).min(g.demand / 1000 * 7);
                let price = Self::sell_price_of(o.price);
                if room > 0 && g.price - price - cost > 0 {
                    let kg = (o.store / 4).min(room).min(g.money.max(0) / (price + cost).max(1)).max(0);
                    self.buy_in(mi, k, kg, price, cost);
                }
                // Their dealers send what they hold beyond their plan
                // (S120), as far as the gate's dealers take it and pay.
                let (g, o) = (&self.markets[mi], &self.outer[k]);
                let excess = (o.store - o.demand / 1000 * TARGET_DAYS).min(o.store / 4);
                let price = Self::buy_price(g);
                if excess > 0 && price - cost - o.price > 0 {
                    let kg = excess.min(g.demand / 1000 * DEALER_MAX_DAYS - g.store).min(g.money.max(0) / price.max(1)).max(0);
                    self.buy_in(mi, k, kg, price, 0);
                }
            }
        }
    }

    /// `kg` from gate `mi` to market `k` beyond the map at `price` a kg,
    /// the gate paying `freight` a kg.
    fn sell_out(&mut self, mi: usize, k: usize, kg: i64, price: i64, freight: i64) {
        if kg <= 0 {
            return;
        }
        let g = &mut self.markets[mi];
        g.store -= kg;
        // S114: sales like any other, so neighbours fetch grain for it.
        g.sold_today += kg;
        g.money += kg * (price - freight);
        self.money.exports += kg * price;
        self.money.freight += kg * freight;
        self.stats.out_export_kg += kg;
        self.stats.outer[k][FROM_MAP] += kg;
        self.outer[k].store += kg;
    }

    /// `kg` from market `k` beyond the map to gate `mi` at `price` a kg,
    /// the gate paying `freight` a kg on top.
    fn buy_in(&mut self, mi: usize, k: usize, kg: i64, price: i64, freight: i64) {
        if kg <= 0 {
            return;
        }
        let o = &mut self.outer[k];
        o.store -= kg;
        o.sold_today += kg;
        let g = &mut self.markets[mi];
        g.store += kg;
        g.money -= kg * (price + freight);
        self.money.imports += kg * price;
        self.money.freight += kg * freight;
        self.stats.inflow[1] += kg;
        self.stats.out_import_kg += kg;
        self.stats.outer[k][TO_MAP] += kg;
    }

    fn sell_price_of(price: i64) -> i64 {
        price * (100 + SPREAD_PCT) / 100
    }

    fn buy_price_of(price: i64) -> i64 {
        price * (100 - SPREAD_PCT) / 100
    }

    /// The markets beyond the map (S121), one row each: people, price,
    /// stocks and this year's flows so far (`GrainStats::outer`, reset
    /// with the yearly figures).
    pub(super) fn outside_table(&self, day: i64) -> Table {
        let os = &self.outer;
        let st = &self.stats.outer;
        let t_of = |k: usize| (0..os.len()).map(|i| st[i][k] as f64 / 1000.0).collect::<Vec<f64>>();
        let mut t = Table::new("outside", "Märkte draussen", day);
        t.id((0..os.len() as i64).collect());
        t.text("name", "Markt", os.iter().map(|o| o.name.to_string()).collect())
            .int("persons", "Menschen", "", os.iter().map(|o| o.people).collect())
            .float("price", "Preis", "Denar/kg", os.iter().map(|o| o.price as f64 / 1000.0).collect())
            .float("store_t", "Lager der Händler", "t", os.iter().map(|o| o.store as f64 / 1000.0).collect())
            .float("held_t", "Lager der Bauern", "t", os.iter().map(|o| o.held as f64 / 1000.0).collect())
            .float("harvest_t", "Kommende Ernte", "t", os.iter().map(|o| o.harvest as f64 / 1000.0).collect())
            .float("eaten", "Gegessen vom Bedarf", "%", (0..os.len()).map(|i| if st[i][WANTED] == 0 { 1.0 } else { (st[i][EATEN] as f64 / st[i][WANTED] as f64).min(1.0) }).collect())
            .float("from_map_t", "Von uns gekauft", "t", t_of(FROM_MAP))
            .float("to_map_t", "An uns verkauft", "t", t_of(TO_MAP))
            .hidden_float("lon", "°", os.iter().map(|o| o.lon).collect())
            .hidden_float("lat", "°", os.iter().map(|o| o.lat).collect());
        t
    }
}
