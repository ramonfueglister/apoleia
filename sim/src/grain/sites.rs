//! S113: the player's build orders (crate::build) carried out. Each order
//! becomes a building site of its market (region). The state hires day
//! labourers for its sites in `labour()`, after the farms and the
//! households that hire for money (S111), and pays the market's day wage
//! in denarii (S114) from the treasury (`state_pays`).
//! `build_day` hands the days worked to the sites in tile order and tells
//! each market how many days its sites still want.
//!
//! A finished farm is taken by a landless household of the region, the
//! first by id with adults (S69: "wird automatisch bezogen"); it moves to
//! the farm's cell and gets fields around it like a cleared farm (S73,
//! S92). Until one is there the finished farm waits. Its order is taken off
//! the map once someone lives there.
//!
//! A finished road lot makes its fine tile a road for carriers (their
//! market's path field is worked out again the next morning), and a 25 km
//! cell with roads on half its width a road for traders' wagons (the
//! markets that reach it look for trade partners again the next day):
//! both cost ROAD_PCT of open ground to cross (grain.rs). Roads never wear
//! away; trails beside them come and go with traffic as before.
//!
//! A finished field lot (S116, Ramon 29.10.2026: state land at first,
//! privatisation later) turns up to a lot of free land on its fine tile
//! into state land: free good land at once, clearable land after
//! clearing (FIELD_CLEAR_DAYS_HA). Farms within FIELD_RADIUS that want
//! more land lease it at their sowing after the free good land and before
//! clearing their own (`take_state`), Manciana settlers before clearing;
//! its crop pays RENT_PCT to the state's granary and nothing else (grain.rs
//! harvest). A farm that shrinks or lapses gives the leased land back to
//! the state first (`give_state`).

use super::*;
use crate::build::{self, Orders, Tile};

/// PLACEHOLDER: work days to build a farmstead (house, yard, stable). No
/// source yet; a crew of four for about seven weeks.
pub const FARM_DAYS: i64 = 200;
/// PLACEHOLDER: most hands on one site, so a site wants at most this many
/// days of each weekly hiring (`labour()` hires once a week per market).
pub const CREW: i64 = 4;

/// PLACEHOLDER: work days per lot (0.5 km) of road. Own estimate: a
/// gravel road body 60–90 cm deep (Moreno Gallo 2024) and about 5 m wide
/// is 3,000–4,500 m³ per km, at about one day per m³ some 3,000 work days
/// per real km; shared out by the number of users like every common work
/// (S51): 3,000 / 566.5 × 0.5 km ≈ 3 days.
pub const ROAD_LOT_DAYS: i64 = 3;
/// A 25 km cell counts as a road for traders' wagons once this many of its
/// fine tiles carry a built road, half its width. PLACEHOLDER.
const ROAD_CELL_TILES: u32 = (FINE / 2) as u32;

/// PLACEHOLDER: work days to clear a hectare for the plough, own estimate
/// from Primack (1962): clearing specialists managed about 200 acres in a
/// working life, some 37 days an acre.
pub const FIELD_CLEAR_DAYS_HA: i64 = 90;
/// A lot (0.5 km) is (0.5 / 1.5625)² of a fine tile, × 10,000.
const LOT_PER_TILE_X10000: i64 = 1024;

/// Work days an order of `kind` needs (fields: `field_need`).
fn site_need(kind: u8) -> i64 {
    match kind {
        build::FARM => FARM_DAYS,
        build::ROAD => ROAD_LOT_DAYS,
        _ => 0,
    }
}

/// `Grain::site_check`: the order would be built.
pub const CHECK_BUILDS: u8 = 0;
/// Off the map or at sea: no market, nobody builds it.
pub const CHECK_NO_MARKET: u8 = 1;
/// Kept for the build menu's codes; no kind is undecided any more.
pub const CHECK_UNDECIDED: u8 = 2;
/// A farm that gets built, but no landless household of its region could
/// move in today; done, it waits for one.
pub const CHECK_NO_TENANT: u8 = 3;
/// A field on a tile without free land to plough or clear (S116).
pub const CHECK_NO_LAND: u8 = 4;

/// What an order on a tile would come to, asked before it is placed
/// (REALTIME_GAMEPLAY.md phases 3 and 6).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SiteCheck {
    pub status: u8,
    /// The market whose day labourers would build it, NONE off the map.
    pub market: u32,
    /// Work days it needs, and what they cost the treasury at the
    /// market's day wage today (milli-denarii).
    pub need: i64,
    pub cost: i64,
}

#[derive(Clone, Copy, Debug)]
pub struct Site {
    pub kind: u8,
    pub market: u32,
    /// Fine tile (grid-relative index) and its 25 km cell.
    pub fine: u32,
    pub cell: u32,
    pub need: i64,
    pub done: i64,
    /// The order's spot (world metres, build::Tile).
    pub spot: Tile,
}

impl Grain {
    /// Fine tile index and 25 km cell of an order's spot, None off the grid.
    fn site_place(&self, p: &People, t: Tile) -> Option<(u32, u32)> {
        let (r, c) = build::fine_of(t);
        let (fr, fc) = (r - p.grid.row0 * FINE, c - p.grid.col0 * FINE);
        if fr < 0 || fc < 0 || fr >= self.rows_f || fc >= self.cols_f {
            return None;
        }
        let cell = ((fr / FINE) * (self.cols_f / FINE) + fc / FINE) as u32;
        Some(((fr * self.cols_f + fc) as u32, cell))
    }

    /// Once a day after `day`: brings the sites in line with the orders,
    /// hands out the days worked and finishes what is done.
    pub fn build_day(&mut self, p: &mut People, orders: &mut Orders) {
        // sites for new orders, none for taken back ones
        let mut sites = std::mem::take(&mut self.sites);
        sites.retain(|t, s| orders.get(*t).is_some_and(|o| o.kind == s.kind));
        for (t, o) in orders.iter() {
            if sites.contains_key(&t) {
                continue;
            }
            let Some((fine, cell)) = self.site_place(p, t) else { continue };
            let market = self.cell_market[cell as usize];
            if market == NONE {
                continue;
            }
            let need = if o.kind == build::FIELD { self.field_need(p, cell, fine).0 } else { site_need(o.kind) };
            sites.insert(t, Site { kind: o.kind, market, fine, cell, need, done: 0, spot: t });
        }
        // the days worked since yesterday, to the sites in tile order
        let mut pool: Vec<i64> = self.markets.iter_mut().map(|m| std::mem::take(&mut m.state_done)).collect();
        let mut want = vec![0i64; self.markets.len()];
        for s in sites.values_mut() {
            let m = s.market as usize;
            let take = (s.need - s.done).min(CREW * 7).min(pool[m]).max(0);
            s.done += take;
            pool[m] -= take;
            want[m] += (s.need - s.done).min(CREW * 7);
        }
        for (m, w) in want.into_iter().enumerate() {
            self.markets[m].state_want = w;
        }
        // finished farms: someone moves in
        let done: Vec<Tile> = sites.iter().filter(|(_, s)| s.kind == build::FARM && s.need > 0 && s.done >= s.need).map(|(&t, _)| t).collect();
        for t in done {
            if self.site_moves_in(p, sites[&t]) {
                sites.remove(&t);
                orders.finish(t);
            }
        }
        // finished fields: state land for lease from now on
        let done: Vec<Tile> = sites.iter().filter(|(_, s)| s.kind == build::FIELD && s.done >= s.need).map(|(&t, _)| t).collect();
        for t in done {
            let s = sites.remove(&t).unwrap();
            self.field_built(p, t, s);
            orders.finish(t);
        }
        // finished roads: in use from tomorrow
        let done: Vec<Tile> = sites.iter().filter(|(_, s)| s.kind == build::ROAD && s.done >= s.need).map(|(&t, _)| t).collect();
        for t in done {
            let s = sites.remove(&t).unwrap();
            self.road_built(t, s);
            orders.finish(t);
        }
        self.sites = sites;
    }

    /// A road lot is done: its fine tile becomes a road the next morning
    /// (`fields_redo`), and its 25 km cell too once half its width has one
    /// (`renet`, the markets that reach it search the next day).
    fn road_built(&mut self, t: Tile, s: Site) {
        if !self.road_lots.insert(t) {
            return;
        }
        let n = self.road_fine.entry(s.fine).or_default();
        *n += 1;
        if *n > 1 {
            return;
        }
        if !self.field_todo.contains(&s.market) {
            self.field_todo.push(s.market);
        }
        *self.road_cells.entry(s.cell).or_default() += 1;
        let was = self.net.level[s.cell as usize];
        self.renet();
        if self.net.level[s.cell as usize] != was {
            for (mi, m) in self.markets.iter().enumerate() {
                if m.reach.binary_search(&s.cell).is_ok() {
                    self.road_urgent.push(mi);
                }
            }
        }
    }

    /// The neighbour search's and the path fields' inputs again, after a
    /// trade road level changed or a road was built: a cell with roads on
    /// half its width counts as BUILT_ROAD, whatever its traffic.
    pub(super) fn renet(&mut self) {
        let level: Vec<u8> = self
            .road_level
            .iter()
            .enumerate()
            .map(|(c, &l)| if self.road_cells.get(&(c as u32)).is_some_and(|&n| n >= ROAD_CELL_TILES) { BUILT_ROAD } else { l })
            .collect();
        let net = &*self.net;
        self.net = std::sync::Arc::new(Net { row0: net.row0, col0: net.col0, rows: net.rows, cols: net.cols, kind: net.kind.clone(), at: net.at.clone(), level, roads: self.road_fine.keys().copied().collect() });
    }

    /// The path fields a road built yesterday runs through, worked out
    /// again with it (start of the day, after the walks came back); wear
    /// and trails stay. A market without a field yet builds it with the
    /// road when it first needs it.
    pub(super) fn fields_redo(&mut self, day: i64) {
        for m in std::mem::take(&mut self.field_todo) {
            let mk = &mut self.markets[m as usize];
            if let Some(old) = mk.field.take() {
                mk.field = Some(build_field(&self.net, self.cols_f, mk.region, mk.fine, Some(old), day));
                mk.dirty = false;
                self.stats.field_rebuilds += 1;
            }
        }
    }

    /// The player's finished roads, by lot (build::Tile, world metres).
    pub fn road_lots(&self) -> impl Iterator<Item = Tile> + '_ {
        self.road_lots.iter().copied()
    }

    /// The player's finished fields, by lot (build::Tile, world metres).
    pub fn field_lots(&self) -> impl Iterator<Item = Tile> + '_ {
        self.field_lots.iter().copied()
    }

    /// State land from the player's fields (S116), m²: not leased yet,
    /// and leased by farms.
    pub fn state_land(&self) -> (i64, i64) {
        (self.state_free.values().map(|v| (v[0] + v[1]) as i64).sum(), self.farms.iter().map(|f| f.state).sum())
    }

    /// The `tiles` index of fine tile `fine` in 25 km cell `cell`, None
    /// in a cell without land.
    fn tile_of(&self, cell: u32, fine: u32) -> Option<u32> {
        let base = self.tile_base[cell as usize];
        let (r, c) = (fine as i32 / self.cols_f, fine as i32 % self.cols_f);
        (base != NONE).then(|| base + ((r % FINE) * FINE + c % FINE) as u32)
    }

    /// A lot's area in m² (simulated, S50) in `cell`.
    fn lot_m2(&self, p: &People, cell: u32) -> i64 {
        tile_room_m2(cell as i32 / (self.cols_f / FINE) + p.grid.row0) * LOT_PER_TILE_X10000 / 10_000
    }

    /// What a field lot on `fine` would take today: work days (clearing
    /// the part that is not free good land), and the free good and
    /// clearable m² it turns into state land; (0, 0, 0) without free land.
    fn field_need(&self, p: &People, cell: u32, fine: u32) -> (i64, i64, i64) {
        let Some(t) = self.tile_of(cell, fine) else { return (0, 0, 0) };
        let lot = self.lot_m2(p, cell);
        let [good, poor] = self.tiles[t as usize];
        let g = lot.min(good as i64);
        let c = (lot - g).min(poor as i64);
        ((c * FIELD_CLEAR_DAYS_HA + 9_999) / 10_000, g, c)
    }

    /// A field lot is done: its land becomes state land for lease.
    fn field_built(&mut self, p: &People, t: Tile, s: Site) {
        let (_, g, c) = self.field_need(p, s.cell, s.fine);
        if g + c == 0 || self.field_lots.contains(&t) {
            return;
        }
        let tile = self.tile_of(s.cell, s.fine).unwrap();
        self.tiles[tile as usize][0] -= g as u16;
        self.tiles[tile as usize][1] -= c as u16;
        self.free_m2[s.cell as usize] -= g;
        self.free_poor[s.cell as usize] -= c;
        let e = self.state_free.entry(tile).or_default();
        e[0] += g as u32;
        e[1] += c as u32;
        self.field_lots.insert(t);
        self.stats.state_fields_m2 += g + c;
    }

    /// Farm `f` leases up to `want` m² of state fields on the tiles
    /// nearest its farmstead, within FIELD_RADIUS, good land before
    /// cleared; returns what it got.
    pub(super) fn take_state(&mut self, f: usize, want: i64) -> i64 {
        if want <= 0 || self.state_free.is_empty() {
            return 0;
        }
        let fine = self.farms[f].fine as i32;
        let (fr, fc) = (fine / self.cols_f, fine % self.cols_f);
        let cols = self.cols_f / FINE;
        let mut got = 0i64;
        for k in 0..self.offsets.len() {
            let (dr, dc, d2) = self.offsets[k];
            if got >= want || d2 > FIELD_RADIUS * FIELD_RADIUS {
                break;
            }
            let (r, c) = (fr + dr, fc + dc);
            if r < 0 || c < 0 || r >= self.rows_f || c >= self.cols_f {
                continue;
            }
            let Some(t) = self.tile_of(((r / FINE) * cols + c / FINE) as u32, (r * self.cols_f + c) as u32) else { continue };
            let Some(free) = self.state_free.get_mut(&t) else { continue };
            let mut took = [0i64; 2];
            for q in 0..2 {
                took[q] = (want - got).min(free[q] as i64);
                free[q] -= took[q] as u32;
                got += took[q];
            }
            if *free == [0, 0] {
                self.state_free.remove(&t);
            }
            let fm = &mut self.farms[f];
            let j = match fm.state_plots.iter().position(|pl| pl.tile == t) {
                Some(j) => j,
                None => {
                    fm.state_plots.push(Plot { tile: t, good: 0, poor: 0 });
                    fm.state_plots.len() - 1
                }
            };
            fm.state_plots[j].good += took[0] as u32;
            fm.state_plots[j].poor += took[1] as u32;
            fm.area += took[0] + took[1];
            fm.poor += took[1];
            fm.state += took[0] + took[1];
        }
        got
    }

    /// Farm `f` gives up to `n` m² of its leased state fields back, the
    /// last taken and the cleared first (as give_land); returns how much.
    pub(super) fn give_state(&mut self, f: usize, n: i64) -> i64 {
        if n <= 0 || self.farms[f].state == 0 {
            return 0;
        }
        let mut plots = std::mem::take(&mut self.farms[f].state_plots);
        let mut left = n;
        for pl in plots.iter_mut().rev() {
            for poor in [true, false] {
                let have = if poor { &mut pl.poor } else { &mut pl.good };
                let k = left.min(*have as i64);
                if k == 0 {
                    continue;
                }
                *have -= k as u32;
                left -= k;
                self.state_free.entry(pl.tile).or_default()[poor as usize] += k as u32;
                if poor {
                    self.farms[f].poor -= k;
                }
            }
        }
        plots.retain(|pl| pl.good + pl.poor > 0);
        let fm = &mut self.farms[f];
        fm.state_plots = plots;
        fm.area -= n - left;
        fm.state -= n - left;
        n - left
    }

    /// A landless household of the site's region takes the finished farm;
    /// false while there is none.
    fn site_moves_in(&mut self, p: &mut People, s: Site) -> bool {
        let Some(id) = self.site_tenant(s.market) else { return false };
        let i = self.info[&id];
        if i.home != s.cell {
            p.relocate_household(id, &self.members[i.at as usize..(i.at + i.size as u32) as usize], s.cell);
            self.info.get_mut(&id).unwrap().home = s.cell;
        }
        let i = self.info[&id];
        let f = self.new_farm(p, id, &i, s.fine) as usize;
        self.spots.insert(f as u32, s.spot);
        // S69: a farm of the family, which pays tax for it
        self.farms[f].kind = FAMILY;
        let want = self.want_m2(id);
        let good = self.take_land(f, want, false, false);
        let good = good + self.take_state(f, want - good);
        let clear = (want - good).min(i.adults as i64 * CLEAR_M2_ADULT_YEAR * self.work_x1000(id) / 1000).max(0);
        self.take_land(f, clear, true, false);
        let h = self.hh.get_mut(&id).unwrap();
        h.kind = FARM;
        h.farm = f as u32;
        h.fine = s.fine;
        self.farms[f].store += h.pantry;
        h.pantry = 0;
        self.stats.built_farms += 1;
        self.events.push(crate::events::Event { day: self.today, kind: crate::events::FARM_TAKEN, household: id, pid: NONE, cell: s.cell, to: NONE, fine: s.fine, other: NONE, amount: 0 });
        true
    }

    /// The landless household of a region that takes its next finished
    /// farm: the first by id with adults.
    fn site_tenant(&self, market: u32) -> Option<u32> {
        let pick = self.market_hh[market as usize].iter().copied().filter(|id| {
            let (Some(h), Some(i)) = (self.hh.get(id), self.info.get(id)) else { return false };
            h.kind == TENT && i.adults > 0 && !h.busy && !h.own_food
        });
        pick.min()
    }

    /// What an order of `kind` on `t` would come to, without placing it.
    pub fn site_check(&self, p: &People, kind: u8, t: Tile) -> SiteCheck {
        let market = self.site_place(p, t).map_or(NONE, |(_, cell)| self.cell_market[cell as usize]);
        if market == NONE {
            return SiteCheck { status: CHECK_NO_MARKET, market, need: 0, cost: 0 };
        }
        let (need, land) = match kind {
            build::FIELD => {
                let (cell, fine) = self.site_place(p, t).map(|(f, c)| (c, f)).unwrap();
                let (need, g, c) = self.field_need(p, cell, fine);
                (need, g + c)
            }
            _ => (site_need(kind), 1),
        };
        let cost = need * self.day_wage(market);
        let status = if land == 0 {
            CHECK_NO_LAND
        } else if kind == build::FARM && self.site_tenant(market).is_none() {
            CHECK_NO_TENANT
        } else {
            CHECK_BUILDS
        };
        SiteCheck { status, market, need, cost }
    }

    /// A day of work at a market today, in milli-denarii: what the state
    /// pays its day labourers there (S72, S113).
    pub fn day_wage(&self, market: u32) -> i64 {
        self.markets[market as usize].wage
    }

    /// Farm households whose farm stands on another fine tile than the
    /// village tile the view would give them (crate::settle::home_fine):
    /// those that took a farm built from an order (S113), and some fifty
    /// in the first months who took over a farm (heirs) or changed estate.
    /// (household, fine tile, the order's spot for a farm built from one),
    /// by household; the view draws their house and people there, by their
    /// fields.
    pub fn homes_moved(&self) -> Vec<(u32, u32, Option<Tile>)> {
        let mut out: Vec<(u32, u32, Option<Tile>)> = self
            .hh
            .iter()
            .filter(|(_, h)| h.kind == FARM)
            .filter_map(|(&id, h)| {
                let i = self.info.get(&id)?;
                let spot = self.spots.get(&h.farm).copied().filter(|_| self.farms.get(h.farm as usize).is_some_and(|f| f.hh == id));
                (self.settle.home_fine(i.home, id, i.stand) != h.fine).then_some((id, h.fine, spot))
            })
            .collect();
        out.sort_unstable();
        out
    }

    /// Where the household of a farm built from an order lives: the
    /// order's spot in world km (x, z), None for every other farm (their
    /// houses stand in a village of the cell, crate::settle).
    pub fn built_spot(&self, household: u32) -> Option<(f64, f64)> {
        let f = self.hh.get(&household)?.farm;
        let &(z, x) = self.spots.get(&f)?;
        (self.farms.get(f as usize)?.hh == household).then_some((x as f64 / 1000.0, z as f64 / 1000.0))
    }

    /// The building sites, by tile: kind, work days needed and done.
    pub fn sites(&self) -> impl Iterator<Item = (Tile, Site)> + '_ {
        self.sites.iter().map(|(&t, &s)| (t, s))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::build::Command;
    use std::path::Path;

    /// S113: a farm ordered next to the tents is built by day labour paid
    /// from the treasury, a tent household moves in and the order goes;
    /// every denarius is booked, and the same orders give the same state.
    #[test]
    fn ordered_farm_is_built_and_taken() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let run = || {
            let mut p = People::new(&inp, 3);
            let mut g = Grain::new(&inp, &mut p);
            let mut orders = Orders::default();
            let (mut t_fine, mut spot) = (NONE, (0, 0));
            for day in 0..150 {
                if day == 40 {
                    // the cell of the first tent household with adults, in its middle
                    let id = (0..g.markets.len())
                        .flat_map(|m| g.market_hh[m].clone())
                        .filter(|id| g.hh.get(id).is_some_and(|h| h.kind == TENT) && g.info.get(id).is_some_and(|i| i.adults > 0))
                        .min()
                        .expect("a tent household");
                    let cell = g.info[&id].home as i32;
                    let cols = g.cols_f / FINE;
                    let t = build::fine_centre((cell / cols + p.grid.row0) * FINE + FINE / 2, (cell % cols + p.grid.col0) * FINE + FINE / 2);
                    orders.apply(&Command::Place { kind: build::FARM, tiles: vec![t] }, day);
                    t_fine = g.site_place(&p, t).expect("on the grid").0;
                    spot = t;
                }
                p.day();
                g.day(&mut p);
                g.build_day(&mut p, &mut orders);
                assert_eq!(g.money_unbooked(), 0);
            }
            assert!(g.stats.build_days >= FARM_DAYS && g.stats.build_paid > 0);
            // a crew of CREW: at least FARM_DAYS / (CREW × 7) weeks
            assert!(g.stats.build_days <= FARM_DAYS + CREW * 7);
            assert_eq!(g.stats.built_farms, 1);
            // the new farmer's house is drawn on the ordered spot
            let built = g.farms.iter().find(|f| f.fine == t_fine && f.hh != NONE).expect("the built farm").hh;
            assert!(g.homes_moved().contains(&(built, t_fine, Some(spot))));
            assert!(orders.is_empty() && g.sites.is_empty());
            (p.fingerprint(), g.fingerprint())
        };
        assert_eq!(run(), run());
    }

    /// The build menu's question before placing: a farm by the tents is
    /// built at the day wage, a field is not yet, the sea or off the map
    /// has nobody to build.
    #[test]
    fn site_check_answers() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let mut p = People::new(&inp, 3);
        let g = Grain::new(&inp, &mut p);
        let id = (0..g.markets.len())
            .flat_map(|m| g.market_hh[m].clone())
            .filter(|id| g.hh.get(id).is_some_and(|h| h.kind == TENT) && g.info.get(id).is_some_and(|i| i.adults > 0))
            .min()
            .expect("a tent household");
        let cell = g.info[&id].home as i32;
        let cols = g.cols_f / FINE;
        let t = build::fine_centre((cell / cols + p.grid.row0) * FINE + FINE / 2, (cell % cols + p.grid.col0) * FINE + FINE / 2);
        let farm = g.site_check(&p, build::FARM, t);
        assert_eq!(farm.status, CHECK_BUILDS);
        assert_eq!(farm.market, g.cell_market[cell as usize]);
        assert_eq!((farm.need, farm.cost), (FARM_DAYS, FARM_DAYS * g.day_wage(farm.market)));
        assert!(farm.cost > 0);
        let field = g.site_check(&p, build::FIELD, t);
        assert!(field.status == CHECK_BUILDS || field.status == CHECK_NO_LAND);
        let road = g.site_check(&p, build::ROAD, t);
        assert_eq!((road.status, road.need), (CHECK_BUILDS, ROAD_LOT_DAYS));
        let off = g.site_check(&p, build::FARM, (i32::MIN / 2, i32::MIN / 2));
        assert_eq!((off.status, off.market, off.cost), (CHECK_NO_MARKET, NONE, 0));
    }

    /// Two field lots on a fine tile with free land become state land
    /// (good land at once, clearable land after clearing); a farm nearby
    /// leases it and gives it back; the land is neither made nor lost on
    /// the way. The same orders give the same state.
    #[test]
    fn ordered_fields_become_state_land() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let run = || {
            let mut p = People::new(&inp, 3);
            let mut g = Grain::new(&inp, &mut p);
            let mut orders = Orders::default();
            let cols = g.cols_f / FINE;
            // the first fine tile with room for two lots of clearable land,
            // in a cell with a market and farms
            let (cell, fine, tile) = (0..g.tile_base.len() as u32)
                .filter(|&c| g.tile_base[c as usize] != NONE && g.cell_market[c as usize] != NONE)
                .flat_map(|c| (0..256u32).map(move |l| (c, l)))
                .map(|(c, l)| {
                    let (r, col) = ((c as i32 / cols) * FINE + l as i32 / FINE, (c as i32 % cols) * FINE + l as i32 % FINE);
                    (c, (r * g.cols_f + col) as u32, g.tile_base[c as usize] + l)
                })
                .find(|&(c, _, t)| g.tiles[t as usize][1] as i64 >= 2 * g.lot_m2(&p, c) && g.farms.iter().any(|f| f.hh != NONE && f.cell == c))
                .expect("clearable land");
            let (r, c) = (fine as i32 / g.cols_f + p.grid.row0 * FINE, fine as i32 % g.cols_f + p.grid.col0 * FINE);
            let at = build::fine_centre(r, c);
            let lots = vec![at, (at.0, at.1 + 500)];
            let free0 = g.free_m2[cell as usize] + g.free_poor[cell as usize];
            let check = g.site_check(&p, build::FIELD, at);
            assert_eq!(check.status, CHECK_BUILDS);
            assert!(check.need > 0, "clearing takes work");
            for day in 0..200 {
                if day == 40 {
                    orders.apply(&Command::Place { kind: build::FIELD, tiles: lots.clone() }, day);
                }
                p.day();
                g.day(&mut p);
                g.build_day(&mut p, &mut orders);
                if day > 40 && orders.is_empty() {
                    break;
                }
            }
            assert!(orders.is_empty(), "both lots built");
            assert_eq!(g.field_lots().collect::<Vec<_>>(), { let mut l = lots.clone(); l.sort(); l });
            let made = g.stats.state_fields_m2;
            assert!(made > 0 && made <= 2 * g.lot_m2(&p, cell));
            let leased = |g: &Grain| g.farms.iter().map(|f| f.state).sum::<i64>();
            let state = |g: &Grain| g.state_free.values().map(|v| (v[0] + v[1]) as i64).sum::<i64>();
            assert_eq!(state(&g) + leased(&g), made, "state land kept");
            assert!(g.free_m2[cell as usize] + g.free_poor[cell as usize] <= free0 - made + 1, "taken from the free land");
            // a farm of the cell leases what is left and gives it back
            let f = (0..g.farms.len()).find(|&f| g.farms[f].hh != NONE && g.farms[f].cell == cell).unwrap();
            let (area, before) = (g.farms[f].area, state(&g));
            let got = g.take_state(f, i64::MAX / 4);
            assert_eq!((got, g.farms[f].area, g.farms[f].state >= got), (before, area + before, true));
            assert!(!g.state_free.contains_key(&tile) || before == 0);
            assert_eq!(g.give_state(f, got), got);
            assert_eq!((g.farms[f].area, state(&g)), (area, before));
            (p.fingerprint(), g.fingerprint())
        };
        assert_eq!(run(), run());
    }

    /// A road ordered from a market into its region is built by day
    /// labourers lot by lot; the carriers' way along it then costs
    /// ROAD_PCT of open ground, a 25 km cell with road on half its width
    /// is a road for wagons, and the markets that reach that cell look for
    /// trade partners again. The same orders give the same state.
    #[test]
    fn ordered_road_is_built_and_used() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let run = || {
            let mut p = People::new(&inp, 3);
            let mut g = Grain::new(&inp, &mut p);
            let mut orders = Orders::default();
            let (mut m, mut far, mut open_km) = (NONE, NONE, 0);
            for day in 0..400 {
                if day == 40 {
                    // the market of the first tent household with adults,
                    // a road from its square 12 fine tiles into its region
                    let id = (0..g.markets.len())
                        .flat_map(|m| g.market_hh[m].clone())
                        .filter(|id| g.hh.get(id).is_some_and(|h| h.kind == TENT) && g.info.get(id).is_some_and(|i| i.adults > 0))
                        .min()
                        .expect("a tent household");
                    m = g.cell_market[g.info[&id].home as usize];
                    g.ensure_field(&p, m);
                    let f = g.markets[m as usize].field.as_ref().unwrap();
                    let at = g.markets[m as usize].fine as i32;
                    let (r, c) = (at / g.cols_f, at % g.cols_f);
                    let step = if c - f.c0 < f.n / 2 { 1 } else { -1 };
                    far = (r * g.cols_f + c + 12 * step) as u32;
                    open_km = (12.0 * 1.5625) as i64;
                    assert!(g.route_km(&p, m, far) >= open_km * LEVEL_COST_PCT[2] / 100, "no road yet");
                    let (z0, x0) = build::fine_centre(r + p.grid.row0 * FINE, c + p.grid.col0 * FINE);
                    let lots: Vec<Tile> = (0..=37).map(|k| (z0, x0 + step * 500 * k)).collect();
                    orders.apply(&Command::Place { kind: build::ROAD, tiles: lots }, day);
                }
                p.day();
                g.day(&mut p);
                g.build_day(&mut p, &mut orders);
                if day > 40 && orders.is_empty() {
                    break;
                }
            }
            assert!(orders.is_empty(), "every lot built");
            assert_eq!(g.road_lots().count(), 38);
            assert_eq!(g.road_fine.len(), 13);
            // one more day: the market's path field takes the road
            p.day();
            g.day(&mut p);
            let km = g.route_km(&p, m, far);
            assert!(km <= open_km * ROAD_PCT / 100 + 1, "along the road {km} km, open {open_km} km");
            for (&cell, &n) in &g.road_cells {
                assert_eq!(g.net.level[cell as usize] == BUILT_ROAD, n >= ROAD_CELL_TILES);
            }
            (p.fingerprint(), g.fingerprint())
        };
        assert_eq!(run(), run());
    }
}
