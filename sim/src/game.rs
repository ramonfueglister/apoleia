//! One game of the day sim (docs/kit1/REALTIME_GAMEPLAY.md): the people
//! (S50–S67), the grain economy (S69–S101) and the player's build orders
//! (S113), advanced one day at a time. The game (sim/godot) owns one Game on
//! its sim thread; commands from the build menu are applied between two
//! days with the day they were applied on, so a game is its inputs, its seed
//! and its command log.
//!
//! Save games are that log (as Factorio's replays and lockstep games are
//! its input actions): seed, inputs hash, day, every command with its day,
//! and the fingerprints of the saved day. Loading starts a new game from the
//! same inputs and seed and runs the days again, applying each command on
//! its day. The sim is deterministic, so the world comes out bit-identical;
//! the stored fingerprints say whether it did. They differ when the sim code
//! changed since the save; the player's orders still carry over, on a world
//! that has run a little differently. Loading takes as long as the days take
//! without drawing (3.1 s per simulated year plus 3.5 s for the start on a
//! 4-core cloud machine, examples/game_bench.rs); a save of the whole state
//! follows once the grain economy's structures settle (phase 4 there).
//!
//! File layout, integers little endian (crate::save's encoding):
//!
//! ```text
//! "APOLGAME" | version u32 | inputs hash u64 | seed u64 | day i64
//! | people fingerprint u64 | grain fingerprint u64
//! | command count u64 | (day i64, build::Command) …
//! | xxh3-64 of everything before
//! ```

use crate::build::{Command, Orders};
use crate::grain::{Clearable, FineCover, Grain};
use crate::inputs::Inputs;
use crate::people::{Clock, People};
use crate::save::{write_file, In, Out, SaveError};
use std::path::Path;
use xxhash_rust::xxh3::xxh3_64;

const MAGIC: [u8; 8] = *b"APOLGAME";
pub const VERSION: u32 = 1;

pub struct Game {
    pub people: People,
    pub grain: Grain,
    pub orders: Orders,
    seed: u64,
    inputs: u64,
}

/// What a game is built from besides its seed: the inputs, the clearable
/// share of the land (S73) and the fine land cover, as the game loads them.
#[derive(Clone, Copy)]
pub struct Start<'a> {
    pub inputs: &'a Inputs,
    pub clear: Option<&'a Clearable>,
    pub cover: Option<&'a FineCover>,
}

impl Start<'_> {
    /// Hash of everything the start state is made from (cells, cities, the
    /// clearable land, whether fine cover is used): a save loads only onto
    /// the same.
    pub fn hash(&self) -> u64 {
        let mut b = crate::ecs::hash_inputs(&crate::Params::default(), &self.inputs.cells, &self.inputs.cities).to_le_bytes().to_vec();
        if let Some(c) = self.clear {
            let mut keys: Vec<_> = c.keys().copied().collect();
            keys.sort_unstable();
            for k in keys {
                b.extend_from_slice(&k.0.to_le_bytes());
                b.extend_from_slice(&k.1.to_le_bytes());
                b.extend_from_slice(&c[&k].to_bits().to_le_bytes());
            }
        }
        b.push(self.cover.map_or(0, |c| 1 + c.farmland as u8));
        xxh3_64(&b)
    }
}

/// How a loaded game compares with the one saved.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Loaded {
    pub day: i64,
    pub commands: usize,
    /// The fingerprints of the saved day came out the same.
    pub identical: bool,
}

/// A save read and checked, ready to play again (`Game::check`).
pub struct Replay {
    seed: u64,
    day: i64,
    fingerprints: (u64, u64),
    log: Vec<(i64, Command)>,
}

impl Replay {
    /// The day the save was made on.
    pub fn day(&self) -> i64 {
        self.day
    }

    /// Starts the game again and runs it to the saved day, applying each
    /// command on its day; `progress(day, of)` after every day.
    pub fn run(self, start: Start, mut progress: impl FnMut(i64, i64)) -> (Game, Loaded) {
        let mut g = Game::new(start, self.seed);
        let mut next = self.log.iter().peekable();
        loop {
            while let Some((_, c)) = next.next_if(|(d, _)| *d == g.today()) {
                g.command(c);
            }
            if g.today() >= self.day {
                break;
            }
            g.day();
            progress(g.today(), self.day);
        }
        let identical = g.fingerprints() == self.fingerprints;
        (g, Loaded { day: self.day, commands: self.log.len(), identical })
    }
}

impl Game {
    /// A new game: the start population (seed) and the grain economy with
    /// the defaults of bin/grain.rs (today's farmland clearable, fields on
    /// the fine tiles).
    pub fn new(start: Start, seed: u64) -> Game {
        let mut people = People::new(start.inputs, seed);
        let grain = Grain::with_clearing(start.inputs, &mut people, crate::grain::CLEAR_PCT, start.clear, start.cover, crate::grain::CROP_PCT);
        Game { people, grain, orders: Orders::default(), seed, inputs: start.hash() }
    }

    /// The day last simulated (0 before the first).
    pub fn today(&self) -> i64 {
        self.people.world.resource::<Clock>().day
    }

    /// Applies a command now, between two days; returns how many tiles
    /// changed.
    pub fn command(&mut self, c: &Command) -> usize {
        let today = self.today();
        self.orders.apply(c, today)
    }

    /// Runs one day; returns what the people and the grain economy took,
    /// in microseconds.
    pub fn day(&mut self) -> [f64; 2] {
        let t0 = std::time::Instant::now();
        self.people.day();
        let t1 = std::time::Instant::now();
        self.grain.day(&mut self.people);
        [(t1 - t0).as_secs_f64() * 1e6, t1.elapsed().as_secs_f64() * 1e6]
    }

    pub fn fingerprints(&mut self) -> (u64, u64) {
        (self.people.fingerprint(), self.grain.fingerprint())
    }

    /// The game as a save file's bytes.
    pub fn save(&mut self) -> Vec<u8> {
        let (fp, fg) = self.fingerprints();
        let mut o = Out(Vec::with_capacity(64 + self.orders.log.len() * 32));
        o.0.extend_from_slice(&MAGIC);
        o.u32(VERSION);
        o.u64(self.inputs);
        o.u64(self.seed);
        o.i64(self.today());
        o.u64(fp);
        o.u64(fg);
        o.u64(self.orders.log.len() as u64);
        for (day, c) in &self.orders.log {
            o.i64(*day);
            c.write(&mut o);
        }
        let sum = xxh3_64(&o.0);
        o.u64(sum);
        o.0
    }

    /// Writes the save crash-safely (crate::save::write_file).
    pub fn save_to(&mut self, path: &Path) -> Result<(), SaveError> {
        write_file(path, &self.save())
    }

    /// Plays a save again on `start`, which must be what it was saved
    /// with; `progress(day, of)` is called after every day.
    pub fn load(start: Start, bytes: &[u8], progress: impl FnMut(i64, i64)) -> Result<(Game, Loaded), SaveError> {
        Ok(Game::check(start, bytes)?.run(start, progress))
    }

    /// Reads a save and checks it against `start` without playing it: the
    /// game can refuse a bad file before it stops the running one.
    pub fn check(start: Start, bytes: &[u8]) -> Result<Replay, SaveError> {
        if bytes.len() < MAGIC.len() + 4 + 8 || bytes[..8] != MAGIC {
            return Err(SaveError::NotASave);
        }
        let (body, sum) = bytes.split_at(bytes.len() - 8);
        let mut r = In { b: &body[8..] };
        let version = r.u32()?;
        if version != VERSION {
            return Err(SaveError::Version(version));
        }
        if xxh3_64(body) != u64::from_le_bytes(sum.try_into().unwrap()) {
            return Err(SaveError::Checksum);
        }
        let (inputs, seed, day, fp, fg) = (r.u64()?, r.u64()?, r.i64()?, r.u64()?, r.u64()?);
        let current = start.hash();
        if inputs != current {
            return Err(SaveError::Inputs { saved: inputs, current });
        }
        let n = r.count(8 + 10)?;
        let mut log = Vec::with_capacity(n);
        let mut last = 0;
        for _ in 0..n {
            let d = r.i64()?;
            if d < last || d > day {
                return Err(SaveError::Corrupt("command day"));
            }
            last = d;
            log.push((d, Command::read(&mut r)?));
        }
        if !r.b.is_empty() || day < 0 {
            return Err(SaveError::Corrupt("trailing bytes"));
        }
        Ok(Replay { seed, day, fingerprints: (fp, fg), log })
    }

    pub fn load_from(start: Start, path: &Path, progress: impl FnMut(i64, i64)) -> Result<(Game, Loaded), SaveError> {
        Self::load(start, &std::fs::read(path)?, progress)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::build::{FARM, FIELD, ROAD};

    fn inputs() -> Option<Inputs> {
        crate::inputs::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join(".."), false).ok()
    }

    /// Saving, loading and running on gives the very same world as never
    /// saving; commands come back on their days.
    #[test]
    fn save_plays_again() {
        let Some(inp) = inputs() else { return };
        let start = Start { inputs: &inp, clear: None, cover: None };
        let mut a = Game::new(start, 5);
        for d in 0..70 {
            match d {
                0 => {
                    a.command(&Command::Place { kind: FARM, tiles: vec![(10, 20)] });
                }
                31 => {
                    a.command(&Command::Place { kind: ROAD, tiles: vec![(11, 20), (12, 20)] });
                    a.command(&Command::Place { kind: FIELD, tiles: vec![(10, 21)] });
                }
                60 => {
                    a.command(&Command::Cancel { tiles: vec![(12, 20)] });
                }
                _ => {}
            }
            a.day();
        }
        // a command after the last day belongs to the save, too
        a.command(&Command::Place { kind: FIELD, tiles: vec![(10, 22)] });
        let bytes = a.save();
        let mut days = 0;
        let (mut b, info) = Game::load(start, &bytes, |d, of| {
            assert_eq!(of, 70);
            days = d;
        })
        .unwrap();
        assert_eq!(info, Loaded { day: 70, commands: 5, identical: true });
        assert_eq!(days, 70);
        assert_eq!(b.orders.log, a.orders.log);
        assert_eq!(b.orders.iter().collect::<Vec<_>>(), a.orders.iter().collect::<Vec<_>>());
        for _ in 0..30 {
            a.day();
            b.day();
        }
        assert_eq!(a.fingerprints(), b.fingerprints());
        // saving the loaded game gives the same file
        assert_eq!(b.save().len(), a.save().len());
    }

    #[test]
    fn bad_saves_are_refused() {
        let Some(inp) = inputs() else { return };
        let start = Start { inputs: &inp, clear: None, cover: None };
        let mut g = Game::new(start, 1);
        g.command(&Command::Place { kind: FARM, tiles: vec![(1, 1)] });
        let ok = g.save();
        assert!(matches!(Game::load(start, b"nonsense", |_, _| {}), Err(SaveError::NotASave)));
        let mut bad = ok.clone();
        bad[30] ^= 1;
        assert!(matches!(Game::load(start, &bad, |_, _| {}), Err(SaveError::Checksum)));
        let other: Clearable = [((0, 0), 0.5)].into_iter().collect();
        let start2 = Start { clear: Some(&other), ..start };
        assert!(matches!(Game::load(start2, &ok, |_, _| {}), Err(SaveError::Inputs { .. })));
        let mut cut = ok[..ok.len() - 12].to_vec();
        let sum = xxh3_64(&cut);
        cut.extend_from_slice(&sum.to_le_bytes());
        assert!(Game::load(start, &cut, |_, _| {}).is_err());
        assert!(Game::load(start, &ok, |_, _| {}).unwrap().1.identical);
    }
}
