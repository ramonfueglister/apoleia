//! The player's build orders (S69, S70, S73, S74): farms, fields and roads
//! ordered on village lots (0.5 km, the lots the view puts farmhouses on)
//! from the build menu (app/scripts/build_menu.gd), each at the middle of
//! its lot in world metres; the sim works on the fine tile (1.5625 km,
//! settle::FINE_KM) the spot lies on. The game hands commands to the sim thread,
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
//! Carrying the orders out (S113) is Grain::build_day (grain/sites.rs):
//! day labourers build them, paid the market wage in denarii from the
//! treasury; a finished order is taken off (`finish`).
//!
//! S131: a change of a tax law's level (`Command::Law`) is a command too,
//! logged like an order; the game hands it to the grain economy
//! (`Grain::set_law`), so a save played again sets the same laws on the
//! same days.

use crate::save::{In, Out, SaveError};
use std::collections::BTreeMap;

pub const FARM: u8 = 0;
pub const FIELD: u8 = 1;
pub const ROAD: u8 = 2;
pub const KIND_NAMES: [&str; 3] = ["Hof", "Feld", "Strasse"];

/// An order's spot: world metres, row = z, column = x (the middle of a
/// village lot as the build menu lays them out; Ramon 29.10.2026: build
/// like Anno, on the lots, not on 1.5 km tiles).
pub type Tile = (i32, i32);

/// Twice a fine tile's edge in metres (1562.5 m, settle::FINE_KM).
const FINE_M2: i64 = 3125;

/// The absolute fine tile (row, column) a spot lies on.
pub fn fine_of(t: Tile) -> (i32, i32) {
    ((t.0 as i64 * 2).div_euclid(FINE_M2) as i32, (t.1 as i64 * 2).div_euclid(FINE_M2) as i32)
}

/// The middle of an absolute fine tile as a spot (rounded down to the metre).
pub fn fine_centre(row: i32, col: i32) -> Tile {
    (((row as i64 * 2 + 1) * FINE_M2 / 4) as i32, ((col as i64 * 2 + 1) * FINE_M2 / 4) as i32)
}

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
    /// S131: tax law `law` (crate::grain::LAW_NAMES) to `level`
    /// (crate::grain::LEVEL_NAMES).
    Law { law: u8, level: u8 },
    /// S133: spending law `law` (crate::grain::SPEND_LAW_NAMES) to
    /// `choice` (crate::grain::spend_choices).
    Spend { law: u8, choice: u8 },
}

impl Command {
    /// Appends the command to a save (crate::game): tag (0 place, 1
    /// cancel), kind, tile count, then rows and columns; a law: tag 2,
    /// law, level; a spending law (S133): tag 3, law, choice.
    pub(crate) fn write(&self, o: &mut Out) {
        let (tag, kind, tiles) = match self {
            Command::Place { kind, tiles } => (0, *kind, tiles),
            Command::Cancel { tiles } => (1, 0, tiles),
            Command::Law { law, level } => {
                o.u8(2);
                o.u8(*law);
                o.u8(*level);
                return;
            }
            Command::Spend { law, choice } => {
                o.u8(3);
                o.u8(*law);
                o.u8(*choice);
                return;
            }
        };
        o.u8(tag);
        o.u8(kind);
        o.u64(tiles.len() as u64);
        for &(r, c) in tiles {
            o.i32(r);
            o.i32(c);
        }
    }

    pub(crate) fn read(r: &mut In) -> Result<Command, SaveError> {
        let (tag, kind) = (r.u8()?, r.u8()?);
        if tag == 2 {
            let level = r.u8()?;
            return if (kind as usize) < crate::grain::LAWS && (level as usize) < crate::grain::LAW_LEVELS { Ok(Command::Law { law: kind, level }) } else { Err(SaveError::Corrupt("unknown law")) };
        }
        if tag == 3 {
            let choice = r.u8()?;
            return if (kind as usize) < crate::grain::SPEND_LAWS && (choice as usize) < crate::grain::spend_choices(kind as usize).len() { Ok(Command::Spend { law: kind, choice }) } else { Err(SaveError::Corrupt("unknown spending law")) };
        }
        let n = r.count(8)?;
        let tiles = r.col(n, |r| Ok((r.i32()?, r.i32()?)))?;
        match tag {
            0 if (kind as usize) < KIND_NAMES.len() => Ok(Command::Place { kind, tiles }),
            1 => Ok(Command::Cancel { tiles }),
            _ => Err(SaveError::Corrupt("unknown build command")),
        }
    }
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
            // logged only; the game sets the law (`Game::command`)
            Command::Law { .. } | Command::Spend { .. } => {}
        }
        if changed > 0 {
            self.version += 1;
        }
        changed
    }

    /// Takes off the order on `t` once the sim has built it (S113). Not a
    /// command: playing the log again builds and finishes it again.
    pub fn finish(&mut self, t: Tile) {
        if self.by_tile.remove(&t).is_some() {
            self.version += 1;
        }
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
    fn commands_read_back() {
        let cmds = [Command::Place { kind: ROAD, tiles: vec![(-4, 7), (-4, 8)] }, Command::Cancel { tiles: vec![] }, Command::Law { law: 1, level: 5 }, Command::Spend { law: 1, choice: 2 }, Command::Place { kind: FARM, tiles: vec![(0, 0)] }];
        let mut o = Out(Vec::new());
        cmds.iter().for_each(|c| c.write(&mut o));
        let mut r = In { b: &o.0 };
        for c in &cmds {
            assert_eq!(&Command::read(&mut r).unwrap(), c);
        }
        assert!(r.b.is_empty());
        // an unknown kind or a cut-off command is an error, not a panic
        assert!(Command::read(&mut In { b: &[0, 9, 0, 0, 0, 0, 0, 0, 0, 0] }).is_err());
        assert!(Command::read(&mut In { b: &o.0[..o.0.len() - 3] }).is_ok());
        assert!(Command::read(&mut In { b: &o.0[..5] }).is_err());
        // a law out of range or cut off is an error too
        assert!(Command::read(&mut In { b: &[2, 3, 0] }).is_err());
        assert!(Command::read(&mut In { b: &[2, 0, 6] }).is_err());
        assert!(Command::read(&mut In { b: &[2, 0] }).is_err());
        assert_eq!(Command::read(&mut In { b: &[2, 2, 0] }).unwrap(), Command::Law { law: 2, level: 0 });
        assert_eq!(Command::read(&mut In { b: &[3, 0, 3] }).unwrap(), Command::Spend { law: 0, choice: 3 });
        assert!(Command::read(&mut In { b: &[3, 1, 3] }).is_err());
    }

    #[test]
    fn spots_lie_on_their_fine_tile() {
        for (r, c) in [(0, 0), (-1, 5), (-1423, 3302), (7, -9)] {
            assert_eq!(fine_of(fine_centre(r, c)), (r, c));
        }
        assert_eq!(fine_of((1562, 1563)), (0, 1));
        assert_eq!(fine_of((-1, -1563)), (-1, -2));
    }

    #[test]
    fn unknown_kind_is_ignored() {
        let mut o = Orders::default();
        assert_eq!(o.apply(&Command::Place { kind: 7, tiles: vec![(0, 0)] }, 0), 0);
        assert!(o.is_empty());
        assert_eq!(o.version, 0);
    }
}
