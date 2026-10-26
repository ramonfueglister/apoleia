//! Game state as an ECS (bevy_ecs 0.20), decisions S40–S48 in
//! docs/kit2/ARCHITECTURE.md.
//!
//! Tiles are entities with fixed-point components; the monthly tick is a
//! schedule of tick tasks (parallel growth, then a sort step, then structure
//! changes). Stored state is integer only (S44): population is in units of
//! 1/65536 person, and the logistic step uses only correctly rounded IEEE
//! operations, so a run gives the same bits on every platform. Splitting and merging run in one
//! exclusive system, sorted by tile ID (S42). The reference implementation in
//! `crate::World` stays as the input database and as a comparison baseline.

use crate::{Cell, City, Key, Params, World as Inputs, MAX_LEVEL};
use bevy_ecs::change_detection::ContiguousMut;
use bevy_ecs::prelude::*;
use bevy_ecs::schedule::{LogLevel, ScheduleBuildSettings};
use bevy_utils::Parallel;
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::sync::Arc;

/// Fixed point scale: 1.0 person (or km²) = 65 536 units.
pub const FX: i64 = 1 << 16;
const Q32: i128 = 1 << 32;

fn to_fx(v: f64) -> i64 {
    (v * FX as f64).round() as i64
}

pub fn from_fx(v: i64) -> f64 {
    v as f64 / FX as f64
}

/// e^(-x) in Q32 for x in Q32, by Taylor series in integer arithmetic, so the
/// monthly decay factor has the same bits everywhere (no libm `exp`).
fn exp_neg_q32(x: i128) -> i128 {
    const S: i128 = 1 << 60;
    let x60 = x << 28;
    let (mut term, mut sum, mut n) = (S, S, 1i128);
    while term != 0 {
        term = -term * x60 / S / n;
        sum += term;
        n += 1;
    }
    (sum + (1 << 27)) >> 28
}

#[derive(Component, Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct TileKey(pub Key);

/// Population, fixed point.
#[derive(Component, Clone, Copy, Debug)]
pub struct Pop(pub i64);

/// Capacity K (food plus cities), fixed point.
#[derive(Component, Clone, Copy, Debug)]
pub struct Cap(pub i64);

/// Land area in km², fixed point.
#[derive(Component, Clone, Copy, Debug)]
pub struct Land(pub i64);

/// Consecutive months below the merge density.
#[derive(Component, Clone, Copy, Debug, Default)]
pub struct MonthsLow(pub u16);

/// Static inputs (cells, cities, parameters) used to derive capacity.
#[derive(Resource)]
pub struct InputDb(pub Inputs);

/// Tick constants derived once from the parameters.
#[derive(Resource, Clone, Copy)]
pub struct TickConst {
    decay_q32: i128,
    split_density: i64,
    merge_density: i64,
    merge_months: u16,
    budget: usize,
    adaptive: bool,
}

/// Quadtree bookkeeping in ID order (Paradox-style lookup table, S41).
#[derive(Resource, Default)]
pub struct TileIndex {
    pub leaves: BTreeMap<Key, Entity>,
    /// Ancestors of leaves.
    pub internal: BTreeSet<Key>,
    /// Positions split at runtime; only these can merge back.
    pub split_nodes: BTreeSet<Key>,
    /// Nodes a merge may have unblocked; checked next month.
    pending_merge: BTreeSet<Key>,
}

/// Work handed from the parallel tasks to the structure task.
#[derive(Resource, Default)]
pub struct Candidates {
    split: Vec<(Key, i64)>,
    fresh: Vec<Key>,
}

#[derive(Resource, Default, Clone, Copy, Debug)]
pub struct Stats {
    pub month: u32,
    pub splits: u64,
    pub merges: u64,
}

/// One tile as the presentation layer sees it (S45).
#[derive(Clone, Copy, Debug)]
pub struct TileView {
    pub key: Key,
    pub pop: f64,
    pub cap: f64,
    pub land_km2: f64,
}

/// Everything the presentation layer may read about one month (S45).
/// Godot's tile-ID texture stores the index into `tiles`.
#[derive(Clone, Debug, Default)]
pub struct Snapshot {
    pub month: u32,
    /// Changes whenever tiles were split or merged, i.e. whenever `tiles`
    /// may have a new order; the presentation layer rebuilds its tile-ID
    /// texture only then.
    pub structure: u64,
    pub tiles: Vec<TileView>,
}

/// A change to the game state (S43). Player, AI, map tools and replays all
/// go through `Sim::submit`; for now the only command advances the clock.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Command {
    AdvanceMonth,
}

// ---- Tick tasks -----------------------------------------------------------

/// Per-thread candidate lists filled during the parallel growth pass.
#[derive(Default)]
pub struct Found {
    split: Vec<(Key, i64)>,
    fresh: Vec<Key>,
}

#[derive(Resource, Default)]
pub struct Scratch(Parallel<Found>);

/// Monthly logistic step: P' = K·P / (P + (K−P)·d), d = e^(−r/12) from Q32.
/// Stored state stays fixed point (S44). The step itself uses f64 with only
/// + − × ÷, which IEEE 754 rounds identically on every platform
/// (Rust never fuses them into FMA), so the result is still bit-exact; it
/// avoids a 128-bit division per tile. Independent per tile, so it runs in
/// parallel and notes split and merge candidates on the way (one pass over
/// the tiles, like the reference loop).
fn growth(c: Res<TickConst>, found: Res<Scratch>, mut q: Query<(&TileKey, &mut Pop, &Cap, &Land, &mut MonthsLow)>) {
    let c = *c;
    let d = c.decay_q32 as f64 / Q32 as f64;
    // Dense tile table: work on whole column slices (bevy_ecs 0.19
    // contiguous iteration), one chunk per task.
    let chunks = q.contiguous_par_iter_mut().expect("tiles live in tables");
    chunks.for_each(|(keys, pop, cap, land, low)| {
        // Population changes on practically every tile each month, so the
        // whole chunk is marked changed once instead of per tile (S47).
        let (pop, _) = ContiguousMut::split(pop);
        let (low, _) = ContiguousMut::split(low);
        for i in 0..keys.len() {
            let p = &mut pop[i].0;
            if *p > 0 {
                let (pp, kk) = (*p as f64, cap[i].0 as f64);
                // Values are positive, so +0.5 and truncation round to nearest
                // without calling the software `round`.
                *p = if kk > 0.0 { (kk * pp / (pp + (kk - pp) * d) + 0.5) as i64 } else { (pp * d + 0.5) as i64 };
            }
            let land = land[i].0;
            let below = land <= 0 || *p < c.merge_density * land;
            let next = if below { low[i].0.saturating_add(1) } else { 0 };
            low[i].0 = next;
            let key = keys[i].0;
            let fresh = next == c.merge_months && key.level > 0;
            let split = c.adaptive && key.level < MAX_LEVEL && land > 0 && *p > c.split_density * land;
            if fresh || split {
                found.0.scope(|f| {
                    if fresh {
                        f.fresh.push(key.parent());
                    }
                    if split {
                        f.split.push((key, *p));
                    }
                });
            }
        }
    });
}

/// Sort step between the parallel and the serial part (Victoria 3, DD76):
/// merges the per-thread lists into one order that does not depend on
/// threads or entity order.
fn collect(mut found: ResMut<Scratch>, mut out: ResMut<Candidates>) {
    out.split.clear();
    out.fresh.clear();
    for f in found.0.iter_mut() {
        out.split.append(&mut f.split);
        out.fresh.append(&mut f.fresh);
    }
    // Importance = population, ties by ID (S12, S13).
    out.split.sort_unstable_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    out.fresh.sort_unstable();
    out.fresh.dedup();
}

/// Splits and merges: structural, serial, in ID order (S42).
fn structure(world: &mut World) {
    let c = *world.resource::<TickConst>();
    let mut idx = world.remove_resource::<TileIndex>().expect("index");
    let cand = std::mem::take(&mut *world.resource_mut::<Candidates>());
    if c.adaptive {
        for (k, _) in &cand.split {
            if idx.leaves.contains_key(k) {
                split_balanced(world, &mut idx, &c, *k);
            }
        }
        let mut nodes = cand.fresh.clone();
        nodes.extend(std::mem::take(&mut idx.pending_merge));
        merge_pass(world, &mut idx, &c, nodes);
    }
    world.insert_resource(idx);
    world.insert_resource(cand);
    world.resource_mut::<Stats>().month += 1;
}

fn covering_leaf(idx: &TileIndex, k: Key) -> Option<Key> {
    (0..=k.level).rev().map(|l| k.at_level(l)).find(|a| idx.leaves.contains_key(a))
}

fn split_balanced(world: &mut World, idx: &mut TileIndex, c: &TickConst, k: Key) -> bool {
    for n in k.edge_neighbors() {
        while let Some(cov) = covering_leaf(idx, n) {
            if cov.level >= k.level {
                break;
            }
            if !split_balanced(world, idx, c, cov) {
                return false;
            }
        }
    }
    split(world, idx, c, k)
}

fn split(world: &mut World, idx: &mut TileIndex, c: &TickConst, k: Key) -> bool {
    if idx.leaves.len() + 3 > c.budget {
        return false;
    }
    let Some(e) = idx.leaves.remove(&k) else { return false };
    let parent = world.get::<Pop>(e).expect("pop").0 as i128;
    world.despawn(e);
    let kids = k.children();
    let parts: Vec<(i64, i64)> = {
        let db = &world.resource::<InputDb>().0;
        kids.iter()
            .map(|&ch| {
                let (local, urban, land) = db.capacity_parts(ch);
                (to_fx(local + urban), to_fx(land))
            })
            .collect()
    };
    let ksum: i128 = parts.iter().map(|p| p.0 as i128).sum();
    let lsum: i128 = parts.iter().map(|p| p.1 as i128).sum();
    let mut given = 0i128;
    for (i, (&ch, &(cap, land))) in kids.iter().zip(parts.iter()).enumerate() {
        // S33: weight by capacity, else by land; the last child takes the rest.
        let p = if i == 3 {
            parent - given
        } else if ksum > 0 {
            parent * cap as i128 / ksum
        } else if lsum > 0 {
            parent * land as i128 / lsum
        } else {
            parent / 4
        };
        given += p;
        let ent = world.spawn((TileKey(ch), Pop(p.max(0) as i64), Cap(cap), Land(land), MonthsLow(0))).id();
        idx.leaves.insert(ch, ent);
    }
    idx.internal.insert(k);
    idx.split_nodes.insert(k);
    world.resource_mut::<Stats>().splits += 1;
    true
}

fn merge_pass(world: &mut World, idx: &mut TileIndex, c: &TickConst, mut nodes: Vec<Key>) {
    nodes.sort();
    nodes.dedup();
    nodes.retain(|q| idx.split_nodes.contains(q));
    let ready: Vec<Key> = nodes
        .into_iter()
        .filter(|q| {
            q.children().iter().all(|ch| {
                idx.leaves.get(ch).and_then(|&e| world.get::<MonthsLow>(e)).is_some_and(|m| m.0 >= c.merge_months)
            })
        })
        .collect();
    for q in ready {
        if can_merge(idx, q) {
            merge(world, idx, q);
        }
    }
}

fn can_merge(idx: &TileIndex, q: Key) -> bool {
    if !q.children().iter().all(|ch| idx.leaves.contains_key(ch)) {
        return false;
    }
    // 2:1 rule: no position next to q at child level may be subdivided.
    let l = q.level + 1;
    let (r0, c0) = (q.row * 2, q.col * 2);
    let ring = [
        (r0 - 1, c0), (r0 - 1, c0 + 1), (r0 + 2, c0), (r0 + 2, c0 + 1),
        (r0, c0 - 1), (r0 + 1, c0 - 1), (r0, c0 + 2), (r0 + 1, c0 + 2),
    ];
    ring.iter().all(|&(r, c)| !idx.internal.contains(&Key::new(l, r, c)))
}

fn merge(world: &mut World, idx: &mut TileIndex, q: Key) {
    let mut p = 0i64;
    for ch in q.children() {
        if let Some(e) = idx.leaves.remove(&ch) {
            p += world.get::<Pop>(e).map_or(0, |x| x.0);
            world.despawn(e);
        }
    }
    let (local, urban, land) = world.resource::<InputDb>().0.capacity_parts(q);
    let e = world.spawn((TileKey(q), Pop(p), Cap(to_fx(local + urban)), Land(to_fx(land)), MonthsLow(0))).id();
    idx.leaves.insert(q, e);
    idx.internal.remove(&q);
    idx.split_nodes.remove(&q);
    world.resource_mut::<Stats>().merges += 1;
    if q.level > 0 {
        let up = q.parent();
        idx.pending_merge.insert(up);
        idx.pending_merge.extend(up.edge_neighbors());
    }
}

// ---- Simulation handle -----------------------------------------------------

/// The authoritative game state (S40) and its monthly schedule.
pub struct Sim {
    pub world: World,
    monthly: Schedule,
    /// Submitted, not yet applied: (issuer, sequence, command).
    pending: Vec<(u32, u32, Command)>,
    seq: u32,
    /// Applied commands with the month they were applied in.
    log: Vec<(u32, Command)>,
    /// Double buffer (S45): readers keep `front` alive while the next one is
    /// written into `back`, which is reused when no reader holds it.
    front: Arc<Snapshot>,
    back: Arc<Snapshot>,
    views: QueryState<(&'static TileKey, &'static Pop, &'static Cap, &'static Land)>,
}

impl Sim {
    pub fn new(params: Params, start: &[Key], cells: HashMap<(i32, i32), Cell>, cities: Vec<City>) -> Sim {
        Self::with_settings(params, start, cells, cities, ScheduleBuildSettings::default())
    }

    pub fn with_settings(
        params: Params,
        start: &[Key],
        cells: HashMap<(i32, i32), Cell>,
        cities: Vec<City>,
        mut settings: ScheduleBuildSettings,
    ) -> Sim {
        bevy_tasks::ComputeTaskPool::get_or_init(bevy_tasks::TaskPool::default);
        let r_month_q32 = (params.r_per_year / 12.0 * Q32 as f64).round() as i128;
        let tc = TickConst {
            decay_q32: exp_neg_q32(r_month_q32),
            split_density: params.split_density.round() as i64,
            merge_density: params.merge_density.round() as i64,
            merge_months: params.merge_months,
            budget: params.budget,
            adaptive: params.adaptive,
        };
        let db = Inputs::new(params, &[], cells, cities);
        let mut world = World::new();
        let mut idx = TileIndex::default();
        for &k in start {
            let (local, urban, land) = db.capacity_parts(k);
            let p = db.start_population(k, local, urban);
            let e = world.spawn((TileKey(k), Pop(to_fx(p)), Cap(to_fx(local + urban)), Land(to_fx(land)), MonthsLow(0))).id();
            idx.leaves.insert(k, e);
            let mut a = k;
            while a.level > 0 {
                a = a.parent();
                idx.internal.insert(a);
            }
        }
        world.insert_resource(InputDb(db));
        world.insert_resource(tc);
        world.insert_resource(idx);
        world.insert_resource(Candidates::default());
        world.insert_resource(Scratch::default());
        world.insert_resource(Stats::default());
        // Any two systems that touch the same data without an order are a
        // build error, so the result can never depend on thread timing.
        settings.ambiguity_detection = LogLevel::Error;
        let mut monthly = Schedule::default();
        monthly.set_build_settings(settings);
        // The tasks form one chain, so a multi-threaded executor has nothing to
        // overlap and only adds about 60 µs of wake-up cost per tick; the
        // parallelism is inside growth (parallel chunks on the task pool).
        monthly.set_executor(bevy_ecs::schedule::SingleThreadedExecutor::new());
        monthly.add_systems((growth, collect, structure).chain_weak());
        let views = world.query::<(&TileKey, &Pop, &Cap, &Land)>();
        let mut sim = Sim {
            world,
            monthly,
            pending: Vec::new(),
            seq: 0,
            log: Vec::new(),
            front: Arc::default(),
            back: Arc::default(),
            views,
        };
        sim.publish();
        sim
    }

    /// Queues a command; it takes effect at the next `step` (S43).
    pub fn submit(&mut self, issuer: u32, cmd: Command) {
        self.pending.push((issuer, self.seq, cmd));
        self.seq += 1;
    }

    /// Applies all queued commands in a fixed order (issuer, then submission
    /// order), so the same commands give the same state on every machine.
    pub fn step(&mut self) {
        let mut cmds = std::mem::take(&mut self.pending);
        cmds.sort_unstable();
        for &(_, _, cmd) in &cmds {
            self.log.push((self.stats().month, cmd));
            match cmd {
                Command::AdvanceMonth => self.monthly.run(&mut self.world),
            }
        }
        cmds.clear();
        self.pending = cmds;
    }

    /// One monthly tick (S21, S42), as a command like any other.
    pub fn tick(&mut self) {
        self.submit(0, Command::AdvanceMonth);
        self.step();
    }

    /// Applied commands with their month, enough to replay a run.
    pub fn log(&self) -> &[(u32, Command)] {
        &self.log
    }

    pub fn stats(&self) -> Stats {
        *self.world.resource::<Stats>()
    }

    pub fn leaf_count(&self) -> usize {
        self.world.resource::<TileIndex>().leaves.len()
    }

    pub fn total_population(&mut self) -> f64 {
        let mut q = self.world.query::<&Pop>();
        from_fx(q.iter(&self.world).map(|p| p.0).sum())
    }

    /// The state as of the last completed tick (S45). Cheap to call every
    /// frame: it is rebuilt only after the month has changed, and only when
    /// someone asks for it.
    pub fn snapshot(&mut self) -> Arc<Snapshot> {
        if self.front.month != self.stats().month {
            self.publish();
        }
        Arc::clone(&self.front)
    }

    fn publish(&mut self) {
        let mut next = std::mem::take(&mut self.back);
        let buf = match Arc::get_mut(&mut next) {
            Some(b) => b,
            None => {
                next = Arc::default();
                Arc::get_mut(&mut next).expect("fresh")
            }
        };
        let st = *self.world.resource::<Stats>();
        buf.month = st.month;
        buf.structure = st.splits + st.merges;
        buf.tiles.clear();
        // Storage order, not ID order: a linear pass over the tile table is
        // several times cheaper than walking the index. The order is still
        // deterministic, because spawns and despawns happen in one serial,
        // sorted system.
        for (keys, pop, cap, land) in self.views.contiguous_iter(&self.world).expect("tiles live in tables") {
            buf.tiles.extend((0..keys.len()).map(|i| TileView {
                key: keys[i].0,
                pop: from_fx(pop[i].0),
                cap: from_fx(cap[i].0),
                land_km2: from_fx(land[i].0),
            }));
        }
        self.back = std::mem::replace(&mut self.front, next);
    }

    /// FNV fingerprint over keys and fixed-point populations in ID order.
    pub fn fingerprint(&self) -> u64 {
        let idx = self.world.resource::<TileIndex>();
        let mut h: u64 = 0xcbf29ce484222325;
        for (k, &e) in &idx.leaves {
            let p = self.world.get::<Pop>(e).unwrap().0;
            for v in [k.level as u64, k.row as u64, k.col as u64, p as u64] {
                h ^= v;
                h = h.wrapping_mul(0x100000001b3);
            }
        }
        h
    }

    /// Checks the 2:1 rule over all leaves.
    pub fn balanced(&self) -> bool {
        let idx = self.world.resource::<TileIndex>();
        idx.leaves.keys().all(|k| {
            k.edge_neighbors().iter().all(|n| match covering_leaf(idx, *n) {
                Some(c) => k.level <= c.level + 1,
                None => true,
            })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cities() -> Vec<City> {
        vec![City { x_m: 30_000.0, z_m: 30_000.0, pop: 900_000.0 }, City { x_m: 80_000.0, z_m: 20_000.0, pop: 20_000.0 }]
    }

    fn sim(params: Params) -> Sim {
        let mut cells = HashMap::new();
        for r in 0..4 {
            for c in 0..4 {
                cells.insert((r, c), Cell { land_km2: 625.0, frac_bare: 0.0, frac_snow: 0.0, frac_above_1500m: 0.0, hyde: None });
            }
        }
        let start: Vec<Key> = (0..2).flat_map(|r| (0..2).map(move |c| Key::new(2, r, c))).collect();
        Sim::new(params, &start, cells, cities())
    }

    #[test]
    fn decay_matches_float_exp() {
        let x = (0.006 / 12.0 * Q32 as f64).round() as i128;
        let d = exp_neg_q32(x) as f64 / Q32 as f64;
        assert!((d - (-0.006f64 / 12.0).exp()).abs() < 1e-9);
    }

    #[test]
    fn runs_are_deterministic_and_balanced() {
        let mut a = sim(Params::default());
        let mut b = sim(Params::default());
        for _ in 0..240 {
            a.tick();
            b.tick();
        }
        assert!(a.stats().splits > 0);
        assert_eq!(a.fingerprint(), b.fingerprint());
        assert!(a.balanced());
    }

    #[test]
    fn splitting_conserves_population_exactly() {
        let mut s = sim(Params::default());
        let mut q = s.world.query::<&Pop>();
        let before: i64 = q.iter(&s.world).map(|p| p.0).sum();
        // One tick of growth plus splits; compare against growth alone.
        let mut flat = sim(Params { adaptive: false, ..Params::default() });
        s.tick();
        flat.tick();
        let mut q = s.world.query::<&Pop>();
        let after: i64 = q.iter(&s.world).map(|p| p.0).sum();
        let mut qf = flat.world.query::<&Pop>();
        let after_flat: i64 = qf.iter(&flat.world).map(|p| p.0).sum();
        assert!(s.stats().splits > 0);
        assert!(after > before);
        assert_eq!(after, after_flat);
    }

    #[test]
    fn shuffled_system_order_gives_same_result() {
        let mut a = sim(Params::default());
        for seed in [1u64, 7, 42] {
            let mut cells = HashMap::new();
            for r in 0..4 {
                for c in 0..4 {
                    cells.insert((r, c), Cell { land_km2: 625.0, frac_bare: 0.0, frac_snow: 0.0, frac_above_1500m: 0.0, hyde: None });
                }
            }
            let start: Vec<Key> = (0..2).flat_map(|r| (0..2).map(move |c| Key::new(2, r, c))).collect();
            let settings = ScheduleBuildSettings { shuffle_seed: Some(seed), ..Default::default() };
            let mut b = Sim::with_settings(Params::default(), &start, cells, cities(), settings);
            let mut a2 = sim(Params::default());
            for _ in 0..120 {
                a2.tick();
                b.tick();
            }
            assert_eq!(a2.fingerprint(), b.fingerprint());
        }
        a.tick();
    }

    #[test]
    fn matches_reference_within_rounding() {
        let mut s = sim(Params::default());
        let mut cells = HashMap::new();
        for r in 0..4 {
            for c in 0..4 {
                cells.insert((r, c), Cell { land_km2: 625.0, frac_bare: 0.0, frac_snow: 0.0, frac_above_1500m: 0.0, hyde: None });
            }
        }
        let start: Vec<Key> = (0..2).flat_map(|r| (0..2).map(move |c| Key::new(2, r, c))).collect();
        let mut r = Inputs::new(Params::default(), &start, cells, cities());
        for _ in 0..240 {
            s.tick();
            r.tick();
        }
        assert_eq!(s.leaf_count(), r.leaves.len());
        let rel = (s.total_population() - r.total_population()).abs() / r.total_population();
        assert!(rel < 1e-6, "relative difference {rel}");
    }

    #[test]
    fn replaying_the_command_log_gives_the_same_state() {
        let mut a = sim(Params::default());
        for _ in 0..240 {
            a.tick();
        }
        let mut b = sim(Params::default());
        for &(_, cmd) in a.log() {
            b.submit(0, cmd);
        }
        b.step();
        assert_eq!(a.log().len(), 240);
        assert_eq!(a.fingerprint(), b.fingerprint());
    }

    #[test]
    fn snapshot_is_stable_between_ticks_and_double_buffered() {
        let mut s = sim(Params::default());
        let first = s.snapshot();
        assert!(Arc::ptr_eq(&first, &s.snapshot()), "no rebuild without a tick");
        s.tick();
        let second = s.snapshot();
        assert_eq!((first.month, second.month), (0, 1));
        // A reader still holding the old month keeps valid data.
        assert_eq!(first.tiles.len(), 4);
        assert_eq!(second.tiles.len(), s.leaf_count());
        let total: f64 = second.tiles.iter().map(|t| t.pop).sum();
        assert!((total - s.total_population()).abs() < 1e-6);
        let mut keys: Vec<Key> = second.tiles.iter().map(|t| t.key).collect();
        keys.sort();
        let leaves: Vec<Key> = s.world.resource::<TileIndex>().leaves.keys().copied().collect();
        assert_eq!(keys, leaves, "every leaf exactly once");
    }
}
