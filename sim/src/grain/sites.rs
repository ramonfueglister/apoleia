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

#[derive(Clone, Copy, Debug)]
pub struct Site {
    pub kind: u8,
    pub market: u32,
    /// Fine tile (grid-relative index) and its 25 km cell.
    pub fine: u32,
    pub cell: u32,
    pub need: i64,
    pub done: i64,
}

impl Grain {
    /// Fine tile index and 25 km cell of an absolute tile, None off the grid.
    fn site_place(&self, p: &People, t: Tile) -> Option<(u32, u32)> {
        let (fr, fc) = (t.0 - p.grid.row0 * FINE, t.1 - p.grid.col0 * FINE);
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
            let need = match o.kind {
                build::FARM => FARM_DAYS,
                _ => 0, // fields and roads: not decided yet
            };
            sites.insert(t, Site { kind: o.kind, market, fine, cell, need, done: 0 });
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
        let pick = self.market_hh[s.market as usize].iter().copied().filter(|id| {
            let (Some(h), Some(i)) = (self.hh.get(id), self.info.get(id)) else { return false };
            h.kind == TENT && i.adults > 0 && !h.busy && !h.own_food
        });
        let Some(id) = pick.min() else { return false };
        let i = self.info[&id];
        if i.home != s.cell {
            p.relocate_household(id, &self.members[i.at as usize..(i.at + i.size as u32) as usize], s.cell);
            self.info.get_mut(&id).unwrap().home = s.cell;
        }
        let i = self.info[&id];
        let f = self.new_farm(p, id, &i, s.fine) as usize;
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
                    let t = ((cell / cols + p.grid.row0) * FINE + FINE / 2, (cell % cols + p.grid.col0) * FINE + FINE / 2);
                    orders.apply(&Command::Place { kind: build::FARM, tiles: vec![t] }, day);
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
            assert!(orders.is_empty() && g.sites.is_empty());
            (p.fingerprint(), g.fingerprint())
        };
        assert_eq!(run(), run());
    }
}
