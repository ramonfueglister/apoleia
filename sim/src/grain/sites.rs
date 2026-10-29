//! S113: the player's build orders (crate::build) carried out. Each order
//! becomes a building site of its market (region). The state hires day
//! labourers for its sites in `labour()`, after the farms and the
//! households that hire for money (S111), and pays the market's day wage
//! in denarii (WAGE_KG_DAY × buy price) from the treasury (`state_pays`).
//! `build_day` hands the days worked to the sites in tile order and tells
//! each market how many days its sites still want.
//!
//! A finished farm is taken by a landless household of the region, the
//! first by id with adults (S69: "wird automatisch bezogen"); it moves to
//! the farm's cell and gets fields around it like a cleared farm (S73,
//! S92). Until one is there the finished farm waits. Its order is taken off
//! the map once someone lives there.
//!
//! Fields and roads: what a finished one does is not decided yet; their
//! sites hire nobody until it is.

use super::*;
use crate::build::{self, Orders, Tile};

/// PLACEHOLDER: work days to build a farmstead (house, yard, stable). No
/// source yet; a crew of four for about seven weeks.
pub const FARM_DAYS: i64 = 200;
/// PLACEHOLDER: most hands on one site, so a site wants at most this many
/// days of each weekly hiring (`labour()` hires once a week per market).
pub const CREW: i64 = 4;

/// Work days an order of `kind` needs; 0 for fields and roads, which
/// nobody builds until it is decided what a finished one does.
fn site_need(kind: u8) -> i64 {
    match kind {
        build::FARM => FARM_DAYS,
        _ => 0,
    }
}

/// `Grain::site_check`: the order would be built.
pub const CHECK_BUILDS: u8 = 0;
/// Off the map or at sea: no market, nobody builds it.
pub const CHECK_NO_MARKET: u8 = 1;
/// A field or a road: nobody builds it yet (`site_need`).
pub const CHECK_UNDECIDED: u8 = 2;
/// A farm that gets built, but no landless household of its region could
/// move in today; done, it waits for one.
pub const CHECK_NO_TENANT: u8 = 3;

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
            let need = site_need(o.kind);
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
        self.sites = sites;
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
        let need = site_need(kind);
        let cost = need * self.day_wage(market);
        let status = if need == 0 {
            CHECK_UNDECIDED
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
        WAGE_KG_DAY * Self::buy_price(&self.markets[market as usize])
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
        assert_eq!(g.site_check(&p, build::FIELD, t).status, CHECK_UNDECIDED);
        let off = g.site_check(&p, build::FARM, (i32::MIN / 2, i32::MIN / 2));
        assert_eq!((off.status, off.market, off.cost), (CHECK_NO_MARKET, NONE, 0));
    }
}
