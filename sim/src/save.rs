//! Save games (docs/kit2/SAVEGAME.md).
//!
//! A save holds the authoritative state only: every tile's components in
//! table order, the quadtree index, clock and counters, and the command log.
//! Static inputs (cells, cities, parameters) are not stored; the save names
//! them by hash and only loads into the same ones. Loading rebuilds the
//! world so that the next months run bit-identically to a game that was
//! never saved (tested), which is what replays, multiplayer joins and desync
//! checks rely on.
//!
//! File layout, all integers little endian:
//!
//! ```text
//! header  "APOLSAVE" | version u32 | inputs hash u64 | raw length u64
//!         | packed length u64 | xxh3-64 of the header fields and payload
//! payload zstd frame of sections: tag [u8; 4] | length u64 | body
//! ```
//!
//! Sections carry their length, so a reader skips tags it does not know
//! (forward compatibility); the version number changes only when the
//! meaning of an existing section changes. Tile columns are stored one after
//! the other (structure of arrays), which compresses far better than rows.
//! Files are written to a temporary name, flushed to disk and renamed over
//! the old save, so a crash leaves either the old or the new save, never a
//! torn one.

use crate::ecs::{
    base_world, hash_inputs, refresh_neighbors, Cap, Command, Land, MonthsLow, Moved, Neighbors, Pop, Regions, Sim, Stats,
    TileIndex, TileKey, UrbanShare,
};
use crate::{Cell, City, Key, Params};
use bevy_ecs::schedule::ScheduleBuildSettings;
use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::io::Write;
use std::path::Path;

const MAGIC: [u8; 8] = *b"APOLSAVE";
/// Format version; bump when an existing section changes meaning.
pub const VERSION: u32 = 1;
const HEADER: usize = 8 + 4 + 8 + 8 + 8 + 8;
/// zstd level: 3 is the library default, the usual trade-off for game saves.
const LEVEL: i32 = 3;

#[derive(Debug)]
pub enum SaveError {
    Io(std::io::Error),
    NotASave,
    /// Written by a newer (or unknown) format version.
    Version(u32),
    /// The payload does not match its checksum: damaged file.
    Checksum,
    /// The save belongs to other parameters or input data.
    Inputs { saved: u64, current: u64 },
    /// Structurally invalid content behind a valid checksum.
    Corrupt(&'static str),
}

impl fmt::Display for SaveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SaveError::Io(e) => write!(f, "save: {e}"),
            SaveError::NotASave => write!(f, "save: not an Apoleia save"),
            SaveError::Version(v) => write!(f, "save: format version {v}, this build reads {VERSION}"),
            SaveError::Checksum => write!(f, "save: checksum mismatch (damaged file)"),
            SaveError::Inputs { saved, current } => {
                write!(f, "save: made with other inputs or parameters ({saved:016x}, now {current:016x})")
            }
            SaveError::Corrupt(what) => write!(f, "save: invalid content ({what})"),
        }
    }
}

impl std::error::Error for SaveError {}

impl From<std::io::Error> for SaveError {
    fn from(e: std::io::Error) -> Self {
        SaveError::Io(e)
    }
}

// ---- Encoding ---------------------------------------------------------------

pub(crate) struct Out(pub(crate) Vec<u8>);

impl Out {
    pub(crate) fn u8(&mut self, v: u8) {
        self.0.push(v);
    }
    pub(crate) fn u16(&mut self, v: u16) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    pub(crate) fn u32(&mut self, v: u32) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    pub(crate) fn i32(&mut self, v: i32) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    pub(crate) fn u64(&mut self, v: u64) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    pub(crate) fn i64(&mut self, v: i64) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    /// A section: tag, then its body with the length in front.
    pub(crate) fn section(&mut self, tag: &[u8; 4], body: impl FnOnce(&mut Out)) {
        self.0.extend_from_slice(tag);
        let at = self.0.len();
        self.u64(0);
        body(self);
        let len = (self.0.len() - at - 8) as u64;
        self.0[at..at + 8].copy_from_slice(&len.to_le_bytes());
    }
    /// Keys as three columns (level, row, col).
    pub(crate) fn keys<'a>(&mut self, keys: impl ExactSizeIterator<Item = &'a Key> + Clone) {
        self.u64(keys.len() as u64);
        keys.clone().for_each(|k| self.u8(k.level));
        keys.clone().for_each(|k| self.i32(k.row));
        keys.for_each(|k| self.i32(k.col));
    }
}

pub(crate) struct In<'a> {
    pub(crate) b: &'a [u8],
}

impl<'a> In<'a> {
    pub(crate) fn take(&mut self, n: usize) -> Result<&'a [u8], SaveError> {
        if self.b.len() < n {
            return Err(SaveError::Corrupt("truncated"));
        }
        let (head, rest) = self.b.split_at(n);
        self.b = rest;
        Ok(head)
    }
    pub(crate) fn arr<const N: usize>(&mut self) -> Result<[u8; N], SaveError> {
        Ok(self.take(N)?.try_into().unwrap())
    }
    pub(crate) fn u8(&mut self) -> Result<u8, SaveError> {
        Ok(self.arr::<1>()?[0])
    }
    pub(crate) fn u16(&mut self) -> Result<u16, SaveError> {
        Ok(u16::from_le_bytes(self.arr()?))
    }
    pub(crate) fn u32(&mut self) -> Result<u32, SaveError> {
        Ok(u32::from_le_bytes(self.arr()?))
    }
    pub(crate) fn i32(&mut self) -> Result<i32, SaveError> {
        Ok(i32::from_le_bytes(self.arr()?))
    }
    pub(crate) fn u64(&mut self) -> Result<u64, SaveError> {
        Ok(u64::from_le_bytes(self.arr()?))
    }
    pub(crate) fn i64(&mut self) -> Result<i64, SaveError> {
        Ok(i64::from_le_bytes(self.arr()?))
    }
    /// A count that must fit the remaining bytes at `min` bytes per item.
    pub(crate) fn count(&mut self, min: usize) -> Result<usize, SaveError> {
        let n = self.u64()?;
        if n > (self.b.len() / min.max(1)) as u64 {
            return Err(SaveError::Corrupt("count larger than the data"));
        }
        Ok(n as usize)
    }
    pub(crate) fn col<T>(&mut self, n: usize, f: impl Fn(&mut Self) -> Result<T, SaveError>) -> Result<Vec<T>, SaveError> {
        (0..n).map(|_| f(self)).collect()
    }
    pub(crate) fn keys(&mut self) -> Result<Vec<Key>, SaveError> {
        let n = self.count(9)?;
        let level = self.col(n, |r| r.u8())?;
        let row = self.col(n, |r| r.i32())?;
        let col = self.col(n, |r| r.i32())?;
        if level.iter().any(|&l| l > crate::MAX_LEVEL) {
            return Err(SaveError::Corrupt("tile level"));
        }
        Ok((0..n).map(|i| Key::new(level[i], row[i], col[i])).collect())
    }
}

fn command_code(c: Command) -> u8 {
    match c {
        Command::AdvanceMonth => 0,
    }
}

fn command(code: u8) -> Result<Command, SaveError> {
    match code {
        0 => Ok(Command::AdvanceMonth),
        _ => Err(SaveError::Corrupt("unknown command")),
    }
}

/// Writes `bytes` crash-safely: temporary file, flush to disk, rename over
/// the target, flush the directory (Pillai et al., 2014).
pub(crate) fn write_file(path: &Path, bytes: &[u8]) -> Result<(), SaveError> {
    let tmp = path.with_extension("tmp");
    {
        let mut f = fs::File::create(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
    }
    fs::rename(&tmp, path)?;
    #[cfg(unix)]
    if let Some(dir) = path.parent().filter(|d| !d.as_os_str().is_empty()) {
        fs::File::open(dir)?.sync_all()?;
    }
    Ok(())
}

// ---- Save -------------------------------------------------------------------

/// One tile's stored components, in table order.
type Row = (Key, i64, i64, i64, u16, i64, i64);

impl Sim {
    /// The game as a save file's bytes.
    pub fn save(&mut self) -> Vec<u8> {
        let mut q = self.world.query::<(&TileKey, &Pop, &Cap, &Land, &MonthsLow, &UrbanShare, &Moved)>();
        // Table order: the order in which later months touch the tiles.
        let rows: Vec<Row> = q.iter(&self.world).map(|(k, p, c, l, m, u, mv)| (k.0, p.0, c.0, l.0, m.0, u.0, mv.0)).collect();
        let st = *self.world.resource::<Stats>();
        let rg = *self.world.resource::<Regions>();
        let idx = self.world.resource::<TileIndex>();
        let mut o = Out(Vec::with_capacity(64 + rows.len() * 51));
        o.section(b"META", |o| {
            o.u32(st.month);
            o.u64(st.splits);
            o.u64(st.merges);
            o.u32(self.seq);
            o.i32(rg.row0);
            o.i32(rg.col0);
            o.u64(rg.cols as u64);
            o.u64(rg.count as u64);
        });
        o.section(b"TILE", |o| {
            o.keys(rows.iter().map(|r| &r.0));
            rows.iter().for_each(|r| o.i64(r.1));
            rows.iter().for_each(|r| o.i64(r.2));
            rows.iter().for_each(|r| o.i64(r.3));
            rows.iter().for_each(|r| o.u16(r.4));
            rows.iter().for_each(|r| o.i64(r.5));
            rows.iter().for_each(|r| o.i64(r.6));
        });
        // Hash sets: sorted, so equal games give equal bytes.
        let sorted = |set: &rustc_hash::FxHashSet<Key>| {
            let mut v: Vec<Key> = set.iter().copied().collect();
            v.sort_unstable();
            v
        };
        let (internal, split_nodes) = (sorted(&idx.internal), sorted(&idx.split_nodes));
        o.section(b"TREE", |o| {
            o.keys(internal.iter());
            o.keys(split_nodes.iter());
            o.keys(idx.pending_merge.iter());
        });
        o.section(b"CMDS", |o| {
            o.u64(self.log.len() as u64);
            self.log.iter().for_each(|&(m, c)| {
                o.u32(m);
                o.u8(command_code(c));
            });
            o.u64(self.pending.len() as u64);
            self.pending.iter().for_each(|&(i, s, c)| {
                o.u32(i);
                o.u32(s);
                o.u8(command_code(c));
            });
        });
        let raw = o.0;
        let packed = compress(&raw);
        let mut file = Vec::with_capacity(HEADER + packed.len());
        file.extend_from_slice(&MAGIC);
        file.extend_from_slice(&VERSION.to_le_bytes());
        file.extend_from_slice(&self.inputs_hash().to_le_bytes());
        file.extend_from_slice(&(raw.len() as u64).to_le_bytes());
        file.extend_from_slice(&(packed.len() as u64).to_le_bytes());
        let sum = checksum(&file[8..], &packed);
        file.extend_from_slice(&sum.to_le_bytes());
        file.extend_from_slice(&packed);
        file
    }

    /// Writes the save crash-safely (`write_file`).
    pub fn save_to(&mut self, path: &Path) -> Result<(), SaveError> {
        write_file(path, &self.save())
    }

    // ---- Load ---------------------------------------------------------------

    /// Restores a game from `bytes` onto the given inputs, which must be the
    /// ones it was saved with.
    pub fn load(params: Params, cells: HashMap<(i32, i32), Cell>, cities: Vec<City>, bytes: &[u8]) -> Result<Sim, SaveError> {
        Self::load_with_settings(params, cells, cities, bytes, ScheduleBuildSettings::default())
    }

    pub fn load_from(params: Params, cells: HashMap<(i32, i32), Cell>, cities: Vec<City>, path: &Path) -> Result<Sim, SaveError> {
        Self::load(params, cells, cities, &fs::read(path)?)
    }

    pub fn load_with_settings(
        params: Params,
        cells: HashMap<(i32, i32), Cell>,
        cities: Vec<City>,
        bytes: &[u8],
        settings: ScheduleBuildSettings,
    ) -> Result<Sim, SaveError> {
        let hash = hash_inputs(&params, &cells, &cities);
        let raw = unpack(bytes, hash)?;
        let mut r = In { b: &raw };
        let mut sections: HashMap<[u8; 4], &[u8]> = HashMap::new();
        while !r.b.is_empty() {
            let tag = r.arr::<4>()?;
            let len = r.u64()?;
            let body = r.take(usize::try_from(len).map_err(|_| SaveError::Corrupt("section length"))?)?;
            sections.insert(tag, body);
        }
        let section = |t: &[u8; 4]| sections.get(t).map(|b| In { b }).ok_or(SaveError::Corrupt("missing section"));

        let mut m = section(b"META")?;
        let stats = Stats { month: m.u32()?, splits: m.u64()?, merges: m.u64()? };
        let seq = m.u32()?;
        let regions = Regions { row0: m.i32()?, col0: m.i32()?, cols: m.u64()? as usize, count: m.u64()? as usize };
        if regions.cols == 0 || regions.count % regions.cols != 0 {
            return Err(SaveError::Corrupt("region grid"));
        }

        let mut t = section(b"TILE")?;
        let keys = t.keys()?;
        let n = keys.len();
        let pop = t.col(n, |r| r.i64())?;
        let cap = t.col(n, |r| r.i64())?;
        let land = t.col(n, |r| r.i64())?;
        let low = t.col(n, |r| r.u16())?;
        let urban = t.col(n, |r| r.i64())?;
        let moved = t.col(n, |r| r.i64())?;

        let mut tr = section(b"TREE")?;
        let (internal, split_nodes, pending_merge) = (tr.keys()?, tr.keys()?, tr.keys()?);

        let mut c = section(b"CMDS")?;
        let nlog = c.count(5)?;
        let log = (0..nlog).map(|_| Ok((c.u32()?, command(c.u8()?)?))).collect::<Result<Vec<_>, SaveError>>()?;
        let npending = c.count(9)?;
        let pending =
            (0..npending).map(|_| Ok((c.u32()?, c.u32()?, command(c.u8()?)?))).collect::<Result<Vec<_>, SaveError>>()?;

        let mut world = base_world(params, cells, cities, regions, Some(hash));
        *world.resource_mut::<Stats>() = stats;
        let mut idx = TileIndex::default();
        // Spawning in saved table order recreates the same table order, so
        // every later pass visits the tiles in the same sequence.
        let tiles = (0..n).map(|i| {
            (TileKey(keys[i]), Pop(pop[i]), Cap(cap[i]), Land(land[i]), MonthsLow(low[i]), Neighbors::default(), Moved(moved[i]), UrbanShare(urban[i]))
        });
        let ents: Vec<_> = world.spawn_batch(tiles).collect();
        idx.leaves.reserve(n);
        for (&k, e) in keys.iter().zip(ents) {
            if idx.leaves.insert(k, e).is_some() {
                return Err(SaveError::Corrupt("duplicate tile"));
            }
        }
        idx.born = keys;
        idx.internal = internal.into_iter().collect();
        idx.split_nodes = split_nodes.into_iter().collect();
        idx.pending_merge = pending_merge.into_iter().collect();
        // Neighbour lists are derived data: rebuilt, not stored.
        refresh_neighbors(&mut world, &mut idx);
        world.insert_resource(idx);
        let mut sim = Sim::assemble(world, settings);
        sim.seq = seq;
        sim.log = log;
        sim.pending = pending;
        Ok(sim)
    }
}

/// xxh3-64 over the header fields after the magic and the payload, so a
/// damaged length or hash is caught as well as damaged data.
fn checksum(fields: &[u8], packed: &[u8]) -> u64 {
    let mut h = xxhash_rust::xxh3::Xxh3::new();
    h.update(fields);
    h.update(packed);
    h.digest()
}

fn compress(raw: &[u8]) -> Vec<u8> {
    let mut enc = zstd::stream::Encoder::new(Vec::with_capacity(raw.len() / 4), LEVEL).expect("zstd encoder");
    // Large saves use several cores; the output does not depend on it.
    if raw.len() > 4 << 20 {
        let threads = std::thread::available_parallelism().map_or(1, |n| n.get()).min(8) as u32;
        let _ = enc.multithread(threads);
    }
    enc.write_all(raw).expect("write to memory");
    enc.finish().expect("zstd finish")
}

/// Checks header and checksum and returns the decompressed payload.
fn unpack(bytes: &[u8], current: u64) -> Result<Vec<u8>, SaveError> {
    if bytes.len() < HEADER || bytes[..8] != MAGIC {
        return Err(SaveError::NotASave);
    }
    let mut h = In { b: &bytes[8..HEADER] };
    let version = h.u32()?;
    if version != VERSION {
        return Err(SaveError::Version(version));
    }
    let saved = h.u64()?;
    let raw_len = h.u64()?;
    let packed_len = h.u64()?;
    let sum = h.u64()?;
    let packed = &bytes[HEADER..];
    if packed.len() as u64 != packed_len || checksum(&bytes[8..HEADER - 8], packed) != sum {
        return Err(SaveError::Checksum);
    }
    if saved != current {
        return Err(SaveError::Inputs { saved, current });
    }
    let raw_len = usize::try_from(raw_len).map_err(|_| SaveError::Corrupt("length"))?;
    let raw = zstd::bulk::decompress(packed, raw_len).map_err(|_| SaveError::Corrupt("zstd"))?;
    if raw.len() != raw_len {
        return Err(SaveError::Corrupt("length"));
    }
    Ok(raw)
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn cells() -> HashMap<(i32, i32), Cell> {
        let mut cells = HashMap::new();
        for r in 0..4 {
            for c in 0..4 {
                cells.insert((r, c), Cell { land_km2: 625.0, frac_bare: 0.0, frac_snow: 0.0, frac_above_1500m: 0.0, hyde: None });
            }
        }
        cells
    }

    fn cities() -> Vec<City> {
        vec![City { x_m: 30_000.0, z_m: 30_000.0, pop: 900_000.0 }, City { x_m: 80_000.0, z_m: 20_000.0, pop: 20_000.0 }]
    }

    fn start() -> Vec<Key> {
        (0..2).flat_map(|r| (0..2).map(move |c| Key::new(2, r, c))).collect()
    }

    fn new_game(params: &Params) -> Sim {
        Sim::new(params.clone(), &start(), cells(), cities())
    }

    /// Every stored value of every tile, in table order, plus the index.
    fn state(s: &mut Sim) -> (Vec<Row>, Vec<Key>, Vec<Key>, Vec<Key>, u32) {
        let mut q = s.world.query::<(&TileKey, &Pop, &Cap, &Land, &MonthsLow, &UrbanShare, &Moved)>();
        let rows = q.iter(&s.world).map(|(k, p, c, l, m, u, mv)| (k.0, p.0, c.0, l.0, m.0, u.0, mv.0)).collect();
        let idx = s.world.resource::<TileIndex>();
        let keys = |set: &rustc_hash::FxHashSet<Key>| {
            let mut v = set.iter().copied().collect::<Vec<_>>();
            v.sort();
            v
        };
        (rows, keys(&idx.internal), keys(&idx.split_nodes), idx.pending_merge.iter().copied().collect(), s.stats().month)
    }

    /// Save after `at` months, load, and play on to `end`: the loaded game
    /// must equal one that was never saved, state for state and month for
    /// month (Factorio's rule: save/load causes no observable change).
    fn round_trip(params: &Params, at: u32, end: u32) {
        let mut a = new_game(params);
        for _ in 0..at {
            a.tick();
        }
        let bytes = a.save();
        let mut b = Sim::load(params.clone(), cells(), cities(), &bytes).expect("load");
        assert_eq!(state(&mut a), state(&mut b), "loaded state differs");
        assert_eq!(a.log(), b.log());
        for m in at..end {
            a.tick();
            b.tick();
            assert_eq!(a.fingerprint(), b.fingerprint(), "month {m}");
        }
        assert_eq!(state(&mut a), state(&mut b));
        assert_eq!(a.save(), b.save(), "a re-save is byte-identical");
    }

    #[test]
    fn loaded_game_continues_bit_identically() {
        // Saves in a flow month, right after one, and mid-year with splits.
        for at in [0, 1, 12, 13, 125, 240] {
            round_trip(&Params::default(), at, 360);
        }
    }

    #[test]
    fn saves_to_disk_atomically() {
        let dir = std::env::temp_dir().join(format!("apoleia-save-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("game.apsave");
        let mut a = new_game(&Params::default());
        for _ in 0..30 {
            a.tick();
        }
        a.save_to(&path).unwrap();
        a.tick();
        a.save_to(&path).unwrap();
        assert!(!path.with_extension("tmp").exists(), "temporary file renamed away");
        let mut b = Sim::load_from(Params::default(), cells(), cities(), &path).unwrap();
        assert_eq!(a.fingerprint(), b.fingerprint());
        assert_eq!(b.stats().month, 31);
        b.tick();
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn rejects_damaged_foreign_and_newer_files() {
        let mut a = new_game(&Params::default());
        for _ in 0..24 {
            a.tick();
        }
        let good = a.save();
        let load = |b: &[u8], p: Params| Sim::load(p, cells(), cities(), b).map(|_| ());
        assert!(load(&good, Params::default()).is_ok());
        assert!(matches!(load(b"hello", Params::default()), Err(SaveError::NotASave)));
        // Any flipped bit after the magic is caught by the checksum.
        for at in [8, 12, 20, 28, HEADER + 3, good.len() - 1] {
            let mut bad = good.clone();
            bad[at] ^= 0x10;
            let e = load(&bad, Params::default());
            assert!(matches!(e, Err(SaveError::Checksum) | Err(SaveError::Version(_))), "byte {at}: {e:?}");
        }
        let mut newer = good.clone();
        newer[8..12].copy_from_slice(&(VERSION + 1).to_le_bytes());
        assert!(matches!(load(&newer, Params::default()), Err(SaveError::Version(_))));
        let other = Params { migration_rate: 0.1, ..Params::default() };
        assert!(matches!(load(&good, other), Err(SaveError::Inputs { .. })));
        assert!(matches!(load(&good[..good.len() - 5], Params::default()), Err(SaveError::Checksum)));
    }

    proptest! {
        // Fixed seed: the same cases on every run and machine.
        #![proptest_config(ProptestConfig { cases: 24, rng_seed: proptest::test_runner::RngSeed::Fixed(0xA9013), failure_persistence: None, ..ProptestConfig::default() })]

        /// Round trip at any month, with any rates.
        #[test]
        fn round_trip_holds_for_any_month_and_rates(
            at in 0u32..200,
            migration in 0.0f64..0.5,
            pull in 0.0f64..1.0,
            excess in 0.0f64..0.01,
        ) {
            let params = Params { migration_rate: migration, city_pull_rate: pull, urban_excess_death: excess, ..Params::default() };
            round_trip(&params, at, at + 30);
        }
    }
}
