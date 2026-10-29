//! The player's build orders (S69, S70, S73, S74): farms, fields and roads
//! ordered on fine tiles (1.5625 km, settle::FINE_KM) from the build menu
//! (app/scripts/build_menu.gd). The game hands commands to the sim thread,
//! which applies them between two days, so an order is part of the
//! simulated state and never changes a day half done.
//!
//! Every command applied is logged with the sim day it was applied on (the
//! sim thread runs up to a few days ahead of the screen), so a log played
//! again on the same days gives the same orders.
//!
//! One order per tile: a new order of another kind replaces the old one,
//! a cancel removes it. Orders are kept by tile, so going over them is the
//! same on every run.
//!
//! Not yet built: carrying the orders out. Per S102 day labourers from the
//! tents and from farms with time to spare build them, paid the market
//! wage in denarii from the treasury; the building time follows from the
//! work days. Until then an order stays a plan on the map.

use std::collections::BTreeMap;

pub const FARM: u8 = 0;
pub const FIELD: u8 = 1;
pub const ROAD: u8 = 2;
pub const KIND_NAMES: [&str; 3] = ["Hof", "Feld", "Strasse"];

/// A fine tile in absolute rows and columns (row = floor(z / FINE_KM),
/// column = floor(x / FINE_KM), world km).
pub type Tile = (i32, i32);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Order {
    pub kind: u8,
    /// The day it was ordered.
    pub day: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Command {
    Place { kind: u8, tiles: Vec<Tile> },
    Cancel { tiles: Vec<Tile> },
}

#[derive(Clone, Debug, Default)]
pub struct Orders {
    by_tile: BTreeMap<Tile, Order>,
    /// Bumped whenever an order is added, replaced or removed.
    pub version: u64,
    /// The commands applied, with the day, in order.
    pub log: Vec<(i64, Command)>,
}

impl Orders {
    /// Applies one command on `day`; returns how many tiles changed.
    pub fn apply(&mut self, cmd: &Command, day: i64) -> usize {
        self.log.push((day, cmd.clone()));
        let mut changed = 0;
        match cmd {
            Command::Place { kind, tiles } => {
                if (*kind as usize) >= KIND_NAMES.len() {
                    return 0;
                }
                for &t in tiles {
                    if self.by_tile.get(&t).map(|o| o.kind) != Some(*kind) {
                        self.by_tile.insert(t, Order { kind: *kind, day });
                        changed += 1;
                    }
                }
            }
            Command::Cancel { tiles } => {
                for t in tiles {
                    if self.by_tile.remove(t).is_some() {
                        changed += 1;
                    }
                }
            }
        }
        if changed > 0 {
            self.version += 1;
        }
        changed
    }

    pub fn get(&self, t: Tile) -> Option<Order> {
        self.by_tile.get(&t).copied()
    }

    pub fn len(&self) -> usize {
        self.by_tile.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_tile.is_empty()
    }

    /// All orders by tile, row by row.
    pub fn iter(&self) -> impl Iterator<Item = (Tile, Order)> + '_ {
        self.by_tile.iter().map(|(&t, &o)| (t, o))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_order_per_tile() {
        let mut o = Orders::default();
        assert_eq!(o.apply(&Command::Place { kind: FIELD, tiles: vec![(1, 2), (1, 3)] }, 5), 2);
        // the same kind again changes nothing
        assert_eq!(o.apply(&Command::Place { kind: FIELD, tiles: vec![(1, 2)] }, 6), 0);
        assert_eq!(o.version, 1);
        // a farm replaces the field on its tile
        assert_eq!(o.apply(&Command::Place { kind: FARM, tiles: vec![(1, 2)] }, 7), 1);
        assert_eq!(o.get((1, 2)), Some(Order { kind: FARM, day: 7 }));
        assert_eq!(o.len(), 2);
        assert_eq!(o.apply(&Command::Cancel { tiles: vec![(1, 2), (9, 9)] }, 8), 1);
        assert_eq!(o.iter().collect::<Vec<_>>(), vec![((1, 3), Order { kind: FIELD, day: 5 })]);
        assert_eq!(o.version, 3);
    }

    #[test]
    fn log_plays_again() {
        let mut a = Orders::default();
        a.apply(&Command::Place { kind: ROAD, tiles: vec![(4, 4), (4, 5)] }, 3);
        a.apply(&Command::Place { kind: FARM, tiles: vec![(4, 5)] }, 3);
        a.apply(&Command::Cancel { tiles: vec![(4, 4)] }, 9);
        let mut b = Orders::default();
        for (day, c) in a.log.clone() {
            b.apply(&c, day);
        }
        assert_eq!(a.iter().collect::<Vec<_>>(), b.iter().collect::<Vec<_>>());
        assert_eq!(a.log, b.log);
    }

    #[test]
    fn unknown_kind_is_ignored() {
        let mut o = Orders::default();
        assert_eq!(o.apply(&Command::Place { kind: 7, tiles: vec![(0, 0)] }, 0), 0);
        assert!(o.is_empty());
        assert_eq!(o.version, 0);
    }
}
