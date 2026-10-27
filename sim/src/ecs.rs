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
use rustc_hash::{FxHashMap, FxHashSet};
use std::collections::{BTreeSet, HashMap};
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

/// log10 for x ≥ 1 with only + − × ÷ and the exponent bits, so it has the
/// same bits on every platform (libm `log10` may differ). Error < 1e-6.
fn log10(x: f64) -> f64 {
    let bits = x.to_bits();
    let e = ((bits >> 52) & 0x7ff) as i64 - 1023;
    let m = f64::from_bits((bits & ((1u64 << 52) - 1)) | (1023u64 << 52));
    // ln m = 2·atanh(s), s = (m − 1)/(m + 1) ≤ 1/3.
    let s = (m - 1.0) / (m + 1.0);
    let s2 = s * s;
    let ln_m = 2.0 * s * (1.0 + s2 * (1.0 / 3.0 + s2 * (1.0 / 5.0 + s2 * (1.0 / 7.0 + s2 * (1.0 / 9.0 + s2 / 11.0)))));
    (e as f64 * std::f64::consts::LN_2 + ln_m) * std::f64::consts::LOG10_E
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
    migration_rate: f64,
    migration_threshold: f64,
    /// Monthly excess deaths per tenfold city size, and the size they start at.
    urban_excess_month: f64,
    /// Yearly logistic decay factor e^(−r), Q32 (rural surplus of a year).
    decay_year_q32: i128,
    urban_excess_from: f64,
    city_pull_rate: f64,
    city_draw_cap: f64,
}

/// Quadtree bookkeeping in ID order (Paradox-style lookup table, S41).
/// Edge-adjacent leaves (same, coarser or finer level), in ID order, as
/// entity indices. Stored inline (at most two per edge under the 2:1 rule)
/// so the migration pass reads them straight from the table instead of
/// chasing one heap allocation per tile. Rebuilt only for tiles touched by a
/// split or merge.
#[derive(Component, Default, Clone, Copy, Debug, PartialEq, Eq)]
pub struct Neighbors {
    len: u8,
    at: [u32; 8],
}

impl Neighbors {
    #[cfg(test)]
    fn of(list: &[Entity]) -> Neighbors {
        let mut n = Neighbors::default();
        for (slot, e) in n.at.iter_mut().zip(list) {
            *slot = e.index_u32();
        }
        n.len = list.len().min(8) as u8;
        n
    }

    pub fn indices(&self) -> &[u32] {
        &self.at[..self.len as usize]
    }
}

/// City share of a tile's capacity, fixed point Q32 (2^32 = all urban).
/// Q32, not Q16: in a city tile the rural rest 1 − u is tiny (Rome: 4e-5),
/// and Q16 got it wrong by 13 % (found by the reference comparison).
#[derive(Component, Default, Clone, Copy, Debug)]
pub struct UrbanShare(pub i64);

const U_ONE: i64 = 1 << 32;

fn urban_share(local: f64, urban: f64) -> UrbanShare {
    let k = local + urban;
    UrbanShare(if k > 0.0 { (urban / k * U_ONE as f64).round() as i64 } else { 0 })
}

/// Net migration of the current month (fixed point, + = arrivals).
#[derive(Component, Default, Clone, Copy, Debug)]
pub struct Moved(pub i64);

/// Quadtree bookkeeping (Paradox-style lookup table, S41). Hash tables:
/// lookups are O(1) at any map size (a B-tree costs ~20 key comparisons at
/// a million tiles). Nothing iterates them to make a decision, so their
/// order never reaches the results; where an order is needed (fingerprint,
/// save) the keys are sorted.
#[derive(Resource, Default)]
pub struct TileIndex {
    pub leaves: FxHashMap<Key, Entity>,
    /// Ancestors of leaves.
    pub internal: FxHashSet<Key>,
    /// Positions split at runtime; only these can merge back.
    pub split_nodes: FxHashSet<Key>,
    /// Nodes a merge may have unblocked; checked next month.
    pub(crate) pending_merge: BTreeSet<Key>,
    /// Leaves created this month; their neighbourhoods need new lists.
    pub(crate) born: Vec<Key>,
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
    /// Net migrants this month (+ = arrivals).
    pub moved: f64,
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

/// Attraction of a tile for migrants: free share of its capacity (S35 K),
/// clamped so an overfull tile counts as at most -1.
fn attraction(p: f64, k: f64) -> f64 {
    if k > 0.0 {
        (1.0 - p / k).clamp(-1.0, 1.0)
    } else {
        -1.0
    }
}

/// What a neighbour needs to know about a tile, computed once per tile and
/// month so both sides of an edge use the very same numbers.
#[derive(Clone, Copy, Default)]
struct Side {
    attraction: f64,
    pop: f64,
    free: f64,
    level: u8,
}

fn side(p: i64, k: i64, level: u8) -> Side {
    let (pf, kf) = (p as f64, k as f64);
    Side { attraction: attraction(pf, kf), pop: pf.max(0.0), free: (kf - pf).max(0.0), level }
}

/// Edge weight of tile `a` towards `b`: shared edge over a's perimeter.
/// Sizes are powers of two, so this is an exact constant.
fn edge_weight(a: u8, b: u8) -> f64 {
    if b <= a { 0.25 } else { 0.25 / (1u64 << (b - a)) as f64 }
}

/// People (fixed point) moving between neighbours this month, positive
/// from `a` to `b`. Both tiles evaluate this with the same `Side` values, so
/// the amount leaving one and arriving at the other is bit-identical and the
/// total is conserved exactly. Weights sum to 1 over a tile's edges, which
/// bounds a month's outflow by rate·2·P and inflow by rate·2·free capacity.
fn flux(c: &TickConst, a: Side, b: Side) -> i64 {
    let d = b.attraction - a.attraction;
    if d > c.migration_threshold {
        let amount = (a.pop * edge_weight(a.level, b.level)).min(b.free * edge_weight(b.level, a.level));
        (c.migration_rate * d * amount + 0.5) as i64
    } else if -d > c.migration_threshold {
        let amount = (b.pop * edge_weight(b.level, a.level)).min(a.free * edge_weight(a.level, b.level));
        -((c.migration_rate * -d * amount + 0.5) as i64)
    } else {
        0
    }
}

/// Migration as a tick task (MIGRATION.md): each tile sums what it sends to
/// and receives from its edge neighbours. Reads only the start-of-month
/// state, so it runs in parallel and in any order. The state is first copied
/// into a dense array indexed by entity index; random `Query::get` calls per
/// neighbour cost several times more.
/// Migration and the city draw run in the first month of each year: people
/// move once a year (the slow flows hardly change within a year), which
/// takes their cost out of the other eleven months.
fn flow_month(stats: &Stats) -> bool {
    stats.month % 12 == 0
}

/// Base pointer of the migration array for disjoint parallel writes.
#[derive(Clone, Copy)]
struct Slots(*mut Side);
// SAFETY: used only for writes to distinct indices (one per entity).
unsafe impl Send for Slots {}
unsafe impl Sync for Slots {}

impl Slots {
    /// # Safety
    /// `i` must be in bounds and written by no other task at the same time.
    unsafe fn put(self, i: usize, v: Side) {
        unsafe { *self.0.add(i) = v };
    }
}

fn migrate(
    c: Res<TickConst>,
    stats: Res<Stats>,
    mut dense: Local<Vec<Side>>,
    state: Query<(Entity, &TileKey, &Pop, &Cap)>,
    mut tiles: Query<(Entity, &Neighbors, &mut Moved)>,
) {
    let c = *c;
    if !flow_month(&stats) {
        return;
    }
    if c.migration_rate <= 0.0 {
        // Still clear last year's balance (the city draw adds to it).
        for (_, _, mut m) in &mut tiles {
            m.0 = 0;
        }
        return;
    }
    // Size the array by the largest entity index, then fill it in parallel:
    // every tile writes only its own slot.
    let mut top = 0usize;
    for (ents, ..) in state.contiguous_iter().expect("tiles live in tables") {
        top = ents.iter().fold(top, |m, e| m.max(e.index_u32() as usize + 1));
    }
    if dense.len() < top {
        dense.resize(top, Side::default());
    }
    let slots = Slots(dense.as_mut_ptr());
    state.contiguous_par_iter().expect("tiles live in tables").for_each(move |(ents, keys, pop, cap)| {
        for i in 0..ents.len() {
            // SAFETY: entity indices are unique and < top, so writes are
            // disjoint and in bounds; `dense` is not read until all are done.
            unsafe { slots.put(ents[i].index_u32() as usize, side(pop[i].0, cap[i].0, keys[i].0.level)) };
        }
    });
    let dense = &*dense;
    let chunks = tiles.contiguous_par_iter_mut().expect("tiles live in tables");
    chunks.for_each(|(ents, nbs, moved)| {
        let (moved, _) = ContiguousMut::split(moved);
        for i in 0..ents.len() {
            let me = dense[ents[i].index_u32() as usize];
            let mut net = 0i64;
            for &at in nbs[i].indices() {
                // Positive flux leaves the first argument.
                net -= flux(&c, me, dense[at as usize]);
            }
            moved[i].0 = net;
        }
    });
}

/// The 200 km root squares as a dense grid: a city draws its migrants from
/// the rural population of its own root square (S12 level 0).
#[derive(Resource, Clone, Copy)]
pub struct Regions {
    pub(crate) row0: i32,
    pub(crate) col0: i32,
    pub(crate) cols: usize,
    pub(crate) count: usize,
}

impl Regions {
    fn of(start: &[Key]) -> Regions {
        let roots: Vec<Key> = start.iter().map(|k| k.at_level(0)).collect();
        let (row0, row1) = (roots.iter().map(|k| k.row).min().unwrap_or(0), roots.iter().map(|k| k.row).max().unwrap_or(0));
        let (col0, col1) = (roots.iter().map(|k| k.col).min().unwrap_or(0), roots.iter().map(|k| k.col).max().unwrap_or(0));
        let cols = (col1 - col0 + 1) as usize;
        Regions { row0, col0, cols, count: cols * (row1 - row0 + 1) as usize }
    }

    /// The root square and its eight neighbours (inside the grid).
    fn around(&self, r: usize) -> impl Iterator<Item = usize> + '_ {
        let rows = self.count / self.cols;
        let (row, col) = ((r / self.cols) as i64, (r % self.cols) as i64);
        (-1..=1).flat_map(move |dr| (-1..=1).map(move |dc| (row + dr, col + dc))).filter_map(move |(y, x)| {
            (y >= 0 && x >= 0 && (y as usize) < rows && (x as usize) < self.cols).then(|| y as usize * self.cols + x as usize)
        })
    }

    fn index(&self, k: Key) -> usize {
        // Arithmetic shift = floor division by 2^level (as `at_level(0)`).
        let (row, col) = (k.row >> k.level, k.col >> k.level);
        (row - self.row0) as usize * self.cols + (col - self.col0) as usize
    }
}

/// Cities draw migrants from their surroundings (MIGRATION.md, step
/// "Städte"): neighbour diffusion alone cannot feed Rome, which historically
/// drew on all of Italy. A city in root square r asks for a share of its
/// free city capacity from the rural people of the 3×3 root squares around
/// r (about 600 km, EU5's market-wide pull with a distance limit). Every
/// rural tile gives the same fraction asked of its catchment (capped). The
/// total taken is shared by all cities by what they asked, in ID order, the
/// last taking the remainder, so the sum is exact. Runs once a year: one
/// pass over the columns, then only the giving tiles and the cities.
fn city_draw(
    c: Res<TickConst>,
    regions: Res<Regions>,
    stats: Res<Stats>,
    mut parts: Local<Parallel<DrawPart>>,
    mut given: Local<Parallel<i64>>,
    mut q: Query<(Entity, &TileKey, &Pop, &Cap, &UrbanShare, &mut Moved)>,
) {
    let c = *c;
    if c.city_pull_rate <= 0.0 || !flow_month(&stats) {
        return;
    }
    let (n, rg) = (regions.count, *regions);
    // Pass 1, parallel: what each city asks and what each root square can
    // give. Sums are integers (fixed point), so the result does not depend
    // on how the tiles are split across threads.
    // A tile is city and country at once: its city share u asks for
    // u·(K − P), its rural share (1 − u) of the people can be drawn.
    q.contiguous_par_iter().expect("tiles live in tables").for_each(|(ents, keys, pop, cap, urban, _)| {
        parts.scope(|a| {
            if a.demand.len() != n {
                a.demand = vec![0; n];
                a.pool = vec![0; n];
            }
            for i in 0..ents.len() {
                let (p, k, u) = (pop[i].0, cap[i].0, urban[i].0);
                let r = rg.index(keys[i].0);
                let uf = u as f64 * (1.0 / U_ONE as f64);
                if u > 0 {
                    let want = (c.city_pull_rate * uf * (k - p).max(0) as f64) as i64;
                    if want >= 1 {
                        a.demand[r] += want;
                        a.cities.push((keys[i].0, want, ents[i]));
                    }
                }
                a.pool[r] += (p.max(0) as f64 * (1.0 - uf)) as i64;
            }
        });
    });
    let (mut demand, mut pool, mut cities) = (vec![0i64; n], vec![0i64; n], Vec::new());
    for a in parts.iter_mut() {
        for r in 0..a.demand.len() {
            demand[r] += std::mem::take(&mut a.demand[r]);
            pool[r] += std::mem::take(&mut a.pool[r]);
        }
        cities.append(&mut a.cities);
    }
    if cities.is_empty() {
        // Rates are zero without demand: nobody leaves.
        return;
    }
    // Rate asked of each catchment, then summed back onto each root square.
    let asked: Vec<f64> = (0..n)
        .map(|r| {
            let p3: i64 = regions.around(r).map(|q| pool[q]).sum();
            if p3 > 0 { demand[r] as f64 / p3 as f64 } else { 0.0 }
        })
        .collect();
    let rate: Vec<f64> = (0..n).map(|q| regions.around(q).map(|r| asked[r]).sum::<f64>().min(c.city_draw_cap)).collect();
    // Pass 2, parallel: only the rural birth surplus leaves (landless
    // children, Wrigley 1967; de Vries 1984): this year's logistic gain of
    // the rural share. A drained countryside stops sending instead of
    // emptying.
    let d = c.decay_year_q32 as f64 / Q32 as f64;
    q.contiguous_par_iter_mut().expect("tiles live in tables").for_each(|(_, keys, pop, cap, urban, moved)| {
        let (moved, _) = ContiguousMut::split(moved);
        let mut out_sum = 0i64;
        for i in 0..keys.len() {
            let (p, k, u) = (pop[i].0, cap[i].0, urban[i].0);
            if u < U_ONE && p > 0 && k > p {
                let rest = 1.0 - u as f64 * (1.0 / U_ONE as f64);
                let (pp, kk) = (p as f64, k as f64);
                let surplus = pp * (kk - pp) * (1.0 - d) / (pp + (kk - pp) * d) * rest;
                let out = ((pp * rest * rate[rg.index(keys[i].0)]).min(surplus) + 0.5) as i64;
                moved[i].0 -= out;
                out_sum += out;
            }
        }
        given.scope(|t| *t += out_sum);
    });
    let taken: i64 = given.iter_mut().map(std::mem::take).sum();
    // Hand out in ID order: the last city takes the remainder.
    cities.sort_unstable_by_key(|c| c.0);
    let wanted: i64 = cities.iter().map(|c| c.1).sum();
    let mut left = taken;
    let last = cities.len() - 1;
    for (i, &(_, want, e)) in cities.iter().enumerate() {
        let g = if i == last { left } else { ((taken as i128 * want as i128) / wanted as i128) as i64 };
        left -= g;
        q.get_mut(e).expect("city").5 .0 += g;
    }
}

/// Per-thread sums of `city_draw` pass 1, kept between years.
#[derive(Default)]
pub struct DrawPart {
    demand: Vec<i64>,
    pool: Vec<i64>,
    cities: Vec<(Key, i64, Entity)>,
}

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
fn growth(c: Res<TickConst>, stats: Res<Stats>, found: Res<Scratch>, mut q: Query<(&TileKey, &mut Pop, &Cap, &Land, &mut MonthsLow, &Moved, &UrbanShare)>) {
    let c = *c;
    let d = c.decay_q32 as f64 / Q32 as f64;
    let flow = flow_month(&stats);
    // Dense tile table: work on whole column slices (bevy_ecs 0.19
    // contiguous iteration), one chunk per task.
    let chunks = q.contiguous_par_iter_mut().expect("tiles live in tables");
    chunks.for_each(|(keys, pop, cap, land, low, moved, urban)| {
        // Population changes on practically every tile each month, so the
        // whole chunk is marked changed once instead of per tile (S47).
        let (pop, _) = ContiguousMut::split(pop);
        let (low, _) = ContiguousMut::split(low);
        for i in 0..keys.len() {
            let p = &mut pop[i].0;
            // Migration first (computed from the start-of-month state).
            if flow {
                *p += moved[i].0;
            }
            if *p > 0 {
                let (pp, kk) = (*p as f64, cap[i].0 as f64);
                // Values are positive, so +0.5 and truncation round to nearest
                // without calling the software `round`.
                *p = if kk > 0.0 { (kk * pp / (pp + (kk - pp) * d) + 0.5) as i64 } else { (pp * d + 0.5) as i64 };
                // Urban graveyard: the city share of the tile loses its
                // excess deaths; only migration refills it.
                let u = urban[i].0;
                if u > 0 {
                    let city = *p as f64 * (u as f64 / U_ONE as f64);
                    // Size in people (P is fixed point).
                    let size = city / FX as f64;
                    if size > c.urban_excess_from {
                        let rate = c.urban_excess_month * log10(size / c.urban_excess_from);
                        *p -= (city * rate + 0.5) as i64;
                    }
                }
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
    refresh_neighbors(world, &mut idx);
    world.insert_resource(idx);
    world.insert_resource(cand);
    world.resource_mut::<Stats>().month += 1;
}

/// Leaves sharing an edge with leaf `k`: the covering leaf of each edge
/// neighbour (same or coarser level), or, where that position is split,
/// its children along the shared edge (2:1 rule keeps them leaves).
fn leaf_neighbors(idx: &TileIndex, k: Key) -> KeyList {
    let mut out = KeyList::default();
    for (i, n) in k.edge_neighbors().into_iter().enumerate() {
        if let Some(c) = covering_leaf(idx, n) {
            out.push(c);
        } else if idx.internal.contains(&n) {
            // The two children of n along the shared edge (up, down, left,
            // right as in `edge_neighbors`); the 2:1 rule keeps them leaves.
            let (r, c, l) = (n.row * 2, n.col * 2, n.level + 1);
            let pair = match i {
                0 => [(r + 1, c), (r + 1, c + 1)],
                1 => [(r, c), (r, c + 1)],
                2 => [(r, c + 1), (r + 1, c + 1)],
                _ => [(r, c), (r + 1, c)],
            };
            for (r, c) in pair {
                let ch = Key::new(l, r, c);
                if idx.leaves.contains_key(&ch) {
                    out.push(ch);
                }
            }
        }
    }
    out.sort_dedup();
    out
}

/// Up to eight keys inline (no heap allocation per tile).
#[derive(Clone, Copy)]
struct KeyList {
    len: usize,
    at: [Key; 8],
}

impl Default for KeyList {
    fn default() -> Self {
        KeyList { len: 0, at: [Key::new(0, 0, 0); 8] }
    }
}

impl KeyList {
    fn push(&mut self, k: Key) {
        self.at[self.len] = k;
        self.len += 1;
    }
    fn sort_dedup(&mut self) {
        let v = &mut self.at[..self.len];
        v.sort_unstable();
        let mut n = 0;
        for i in 0..v.len() {
            if n == 0 || v[i] != v[n - 1] {
                v[n] = v[i];
                n += 1;
            }
        }
        self.len = n;
    }
    fn keys(&self) -> &[Key] {
        &self.at[..self.len]
    }
}

/// New neighbour lists for leaves born this month and every leaf next to
/// them (their old lists may point at despawned tiles).
/// `f` over chunks of `items` on the task pool, results concatenated in
/// chunk order (so the output is the same as one sequential call).
fn par_chunks<T: Sync, R: Send + 'static>(items: &[T], f: &(dyn Fn(&[T]) -> Vec<R> + Sync)) -> Vec<R> {
    if items.len() < 4096 {
        return f(items);
    }
    let pool = bevy_tasks::ComputeTaskPool::get();
    let size = items.len().div_ceil(pool.thread_num().max(1) * 4);
    pool.scope(|s| {
        for chunk in items.chunks(size) {
            s.spawn(async move { f(chunk) });
        }
    })
    .into_iter()
    .flatten()
    .collect()
}

pub(crate) fn refresh_neighbors(world: &mut World, idx: &mut TileIndex) {
    let born = std::mem::take(&mut idx.born);
    if born.is_empty() {
        return;
    }
    let mut dirty: Vec<Key>;
    if born.len() >= idx.leaves.len() {
        // A new or loaded game: every leaf.
        dirty = idx.leaves.keys().copied().collect();
    } else {
        let around = |chunk: &[Key]| {
            let mut v = Vec::with_capacity(chunk.len() * 5);
            for &k in chunk {
                if idx.leaves.contains_key(&k) {
                    v.push(k);
                    v.extend_from_slice(leaf_neighbors(idx, k).keys());
                }
            }
            v
        };
        dirty = par_chunks(&born, &around);
        dirty.sort_unstable();
        dirty.dedup();
    }
    // The lists only read the index, so they are built in parallel; the
    // writes follow. The result does not depend on the order.
    let idx = &*idx;
    let build = |k: &Key| {
        let list = leaf_neighbors(idx, *k);
        let mut n = Neighbors { len: list.len as u8, ..Neighbors::default() };
        for (slot, key) in n.at.iter_mut().zip(list.keys()) {
            *slot = idx.leaves[key].index_u32();
        }
        (idx.leaves[k], n)
    };
    let lists = par_chunks(&dirty, &|chunk: &[Key]| chunk.iter().map(build).collect());
    for (e, n) in lists {
        *world.get_mut::<Neighbors>(e).expect("neighbors") = n;
    }
}

fn covering_leaf(idx: &TileIndex, k: Key) -> Option<Key> {
    if idx.leaves.contains_key(&k) {
        return Some(k);
    }
    // A subdivided position has no leaf above it either.
    if idx.internal.contains(&k) {
        return None;
    }
    (0..k.level).rev().map(|l| k.at_level(l)).find(|a| idx.leaves.contains_key(a))
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
    let parts: Vec<(i64, i64, UrbanShare)> = {
        let db = &world.resource::<InputDb>().0;
        kids.iter()
            .map(|&ch| {
                let (local, urban, land) = db.capacity_parts(ch);
                (to_fx(local + urban), to_fx(land), urban_share(local, urban))
            })
            .collect()
    };
    let ksum: i128 = parts.iter().map(|p| p.0 as i128).sum();
    let lsum: i128 = parts.iter().map(|p| p.1 as i128).sum();
    let mut given = 0i128;
    for (i, (&ch, &(cap, land, urban))) in kids.iter().zip(parts.iter()).enumerate() {
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
        let ent = world.spawn((TileKey(ch), Pop(p.max(0) as i64), Cap(cap), Land(land), MonthsLow(0), Neighbors::default(), Moved(0), urban)).id();
        idx.leaves.insert(ch, ent);
        idx.born.push(ch);
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
    let e = world.spawn((TileKey(q), Pop(p), Cap(to_fx(local + urban)), Land(to_fx(land)), MonthsLow(0), Neighbors::default(), Moved(0), urban_share(local, urban))).id();
    idx.leaves.insert(q, e);
    idx.born.push(q);
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

/// Hash of the parameters and static inputs (cells in key order, cities in
/// list order), xxh3 over their exact bits.
#[derive(Resource, Clone, Copy)]
pub struct InputsHash(pub u64);

pub(crate) fn hash_inputs(params: &Params, cells: &HashMap<(i32, i32), Cell>, cities: &[City]) -> u64 {
    let mut h = xxhash_rust::xxh3::Xxh3::new();
    // Debug prints every f64 as its shortest round-trip form: exact bits.
    h.update(format!("{params:?}").as_bytes());
    let mut keys: Vec<&(i32, i32)> = cells.keys().collect();
    keys.sort_unstable();
    let mut buf = Vec::with_capacity(keys.len() * 72);
    let mut f = |v: f64| buf.extend_from_slice(&v.to_bits().to_le_bytes());
    for k in keys {
        let c = &cells[k];
        f(k.0 as f64);
        f(k.1 as f64);
        f(c.land_km2);
        f(c.frac_bare);
        f(c.frac_snow);
        f(c.frac_above_1500m);
        // NaN marks "no value", distinct from every real number.
        let hy = c.hyde.unwrap_or(crate::Hyde { crop_km2: f64::NAN, pop: f64::NAN, rural: None });
        f(hy.crop_km2);
        f(hy.pop);
        f(hy.rural.unwrap_or(f64::NAN));
    }
    for c in cities {
        f(c.x_m);
        f(c.z_m);
        f(c.pop);
    }
    h.update(&buf);
    h.digest()
}

/// The world without tiles: inputs, tick constants and empty work buffers.
/// `hash`: the inputs hash when the caller already has it.
pub(crate) fn base_world(params: Params, cells: HashMap<(i32, i32), Cell>, cities: Vec<City>, regions: Regions, hash: Option<u64>) -> World {
    bevy_tasks::ComputeTaskPool::get_or_init(bevy_tasks::TaskPool::default);
    let r_month_q32 = (params.r_per_year / 12.0 * Q32 as f64).round() as i128;
    let tc = TickConst {
        decay_q32: exp_neg_q32(r_month_q32),
        split_density: params.split_density.round() as i64,
        merge_density: params.merge_density.round() as i64,
        merge_months: params.merge_months,
        budget: params.budget,
        adaptive: params.adaptive,
        migration_rate: params.migration_rate,
        migration_threshold: params.migration_threshold,
        urban_excess_month: params.urban_excess_death / 12.0,
        decay_year_q32: exp_neg_q32((params.r_per_year * Q32 as f64).round() as i128),
        urban_excess_from: params.urban_excess_from,
        city_pull_rate: params.city_pull_rate,
        city_draw_cap: params.city_draw_cap,
    };
    let hash = hash.unwrap_or_else(|| hash_inputs(&params, &cells, &cities));
    let mut world = World::new();
    world.insert_resource(InputDb(Inputs::new(params, &[], cells, cities)));
    world.insert_resource(tc);
    world.insert_resource(InputsHash(hash));
    world.insert_resource(Candidates::default());
    world.insert_resource(Scratch::default());
    world.insert_resource(regions);
    world.insert_resource(Stats::default());
    world
}

/// The authoritative game state (S40) and its monthly schedule.
pub struct Sim {
    pub world: World,
    monthly: Schedule,
    /// Submitted, not yet applied: (issuer, sequence, command).
    pub(crate) pending: Vec<(u32, u32, Command)>,
    pub(crate) seq: u32,
    /// Applied commands with the month they were applied in.
    pub(crate) log: Vec<(u32, Command)>,
    /// Double buffer (S45): readers keep `front` alive while the next one is
    /// written into `back`, which is reused when no reader holds it.
    front: Arc<Snapshot>,
    back: Arc<Snapshot>,
    views: QueryState<(&'static TileKey, &'static Pop, &'static Cap, &'static Land, &'static Moved)>,
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
        settings: ScheduleBuildSettings,
    ) -> Sim {
        let mut world = base_world(params, cells, cities, Regions::of(start), None);
        let mut idx = TileIndex::default();
        let db = &world.resource::<InputDb>().0;
        let tiles: Vec<_> = start
            .iter()
            .map(|&k| {
                let (local, urban, land) = db.capacity_parts(k);
                let p = db.start_population(k, local, urban);
                (TileKey(k), Pop(to_fx(p)), Cap(to_fx(local + urban)), Land(to_fx(land)), MonthsLow(0), Neighbors::default(), Moved(0), urban_share(local, urban))
            })
            .collect();
        // One batch: the table grows once instead of per tile.
        for (&k, e) in start.iter().zip(world.spawn_batch(tiles)) {
            idx.leaves.insert(k, e);
            idx.born.push(k);
            let mut a = k;
            while a.level > 0 {
                a = a.parent();
                if !idx.internal.insert(a) {
                    break;
                }
            }
        }
        refresh_neighbors(&mut world, &mut idx);
        world.insert_resource(idx);
        Sim::assemble(world, settings)
    }

    /// Schedule, queues and snapshot around a world whose tiles and index
    /// are in place (a new game or a loaded save).
    pub(crate) fn assemble(mut world: World, mut settings: ScheduleBuildSettings) -> Sim {
        // Any two systems that touch the same data without an order are a
        // build error, so the result can never depend on thread timing.
        settings.ambiguity_detection = LogLevel::Error;
        let mut monthly = Schedule::default();
        monthly.set_build_settings(settings);
        // The tasks form one chain, so a multi-threaded executor has nothing to
        // overlap and only adds about 60 µs of wake-up cost per tick; the
        // parallelism is inside the tasks (parallel chunks on the task pool).
        monthly.set_executor(bevy_ecs::schedule::SingleThreadedExecutor::new());
        monthly.add_systems((migrate, city_draw, growth, collect, structure).chain_weak());
        let views = world.query::<(&TileKey, &Pop, &Cap, &Land, &Moved)>();
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

    /// Hash of the parameters and static inputs this game was built from;
    /// a save only loads into the same ones.
    pub fn inputs_hash(&self) -> u64 {
        self.world.resource::<InputsHash>().0
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
        for (keys, pop, cap, land, moved) in self.views.contiguous_iter(&self.world).expect("tiles live in tables") {
            buf.tiles.extend((0..keys.len()).map(|i| TileView {
                key: keys[i].0,
                pop: from_fx(pop[i].0),
                cap: from_fx(cap[i].0),
                land_km2: from_fx(land[i].0),
                moved: from_fx(moved[i].0),
            }));
        }
        self.back = std::mem::replace(&mut self.front, next);
    }

    /// FNV fingerprint over keys and fixed-point populations in ID order.
    pub fn fingerprint(&self) -> u64 {
        let idx = self.world.resource::<TileIndex>();
        let mut leaves: Vec<(&Key, &Entity)> = idx.leaves.iter().collect();
        leaves.sort_unstable_by_key(|l| *l.0);
        let mut h: u64 = 0xcbf29ce484222325;
        for (k, &e) in leaves {
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

    #[test]
    fn log10_matches_libm() {
        for x in [1.0, 2.0, 9.99, 10.0, 100.0, 5000.0, 123_456.7, 1e6, 3.3e9] {
            assert!((log10(x) - x.log10()).abs() < 1e-6, "{x}");
        }
    }

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
        let still = Params { migration_rate: 0.0, urban_excess_death: 0.0, city_pull_rate: 0.0, ..Params::default() };
        let mut s = sim(still.clone());
        let mut q = s.world.query::<&Pop>();
        let before: i64 = q.iter(&s.world).map(|p| p.0).sum();
        // One tick of growth plus splits; compare against growth alone.
        let mut flat = sim(Params { adaptive: false, ..still });
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

    fn test_cells() -> HashMap<(i32, i32), Cell> {
        let mut cells = HashMap::new();
        for r in 0..4 {
            for c in 0..4 {
                cells.insert((r, c), Cell { land_km2: 625.0, frac_bare: 0.0, frac_snow: 0.0, frac_above_1500m: 0.0, hyde: None });
            }
        }
        cells
    }

    fn test_start() -> Vec<Key> {
        (0..2).flat_map(|r| (0..2).map(move |c| Key::new(2, r, c))).collect()
    }

    /// Largest per-tile difference between the ECS core and the plain
    /// reference (`crate::World`) after each month, or None when their tile
    /// sets differ. Differential testing (McKeeman, 1998): the reference is
    /// written independently, in f64 and without fixed point, columns or
    /// parallelism, so a disagreement points at a bug in either.
    fn max_deviation(params: Params, months: u32) -> Vec<Option<f64>> {
        let mut s = Sim::new(params.clone(), &test_start(), test_cells(), cities());
        let mut r = Inputs::new(params, &test_start(), test_cells(), cities());
        (0..months)
            .map(|_| {
                s.tick();
                r.tick();
                let snap = s.snapshot();
                if snap.tiles.len() != r.leaves.len() {
                    return None;
                }
                let mut worst = 0.0f64;
                for t in &snap.tiles {
                    let want = r.leaves.get(&t.key)?.p;
                    // Relative, with a floor of 1000 people: fixed point
                    // rounds every step to 1/65536 person, which is a large
                    // share of a nearly empty tile.
                    worst = worst.max((t.pop - want).abs() / want.max(1000.0));
                }
                Some(worst)
            })
            .collect()
    }

    #[test]
    fn matches_the_reference_month_by_month() {
        // Every mechanic on, and each one alone with the others off.
        let all = Params::default();
        let none = Params { migration_rate: 0.0, urban_excess_death: 0.0, city_pull_rate: 0.0, ..Params::default() };
        let cases = [
            ("all", all.clone()),
            ("growth", none.clone()),
            ("migration", Params { migration_rate: all.migration_rate, ..none.clone() }),
            ("urban deaths", Params { urban_excess_death: all.urban_excess_death, ..none.clone() }),
            ("city draw", Params { urban_excess_death: all.urban_excess_death, city_pull_rate: all.city_pull_rate, ..none.clone() }),
        ];
        for (name, params) in cases {
            let dev = max_deviation(params, 50 * 12);
            for (m, d) in dev.iter().enumerate() {
                let d = d.unwrap_or_else(|| panic!("{name}: tile sets differ in month {m}"));
                // Fixed point rounds every step to 1/65536 person, so a
                // tile near K loses sub-unit growth (measured: 0.003 people
                // in 50 years). 1e-5 is far below anything a wrong mechanic
                // would produce.
                assert!(d < 1e-5, "{name}: month {m} differs by {d:e}");
            }
        }
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
        let mut leaves: Vec<Key> = s.world.resource::<TileIndex>().leaves.keys().copied().collect();
        leaves.sort();
        assert_eq!(keys, leaves, "every leaf exactly once");
    }

    #[test]
    fn migration_conserves_people() {
        // Without splits every tile keeps its Moved until the next month, so
        // the net over all tiles is the month's balance.
        let mut s = sim(Params { adaptive: false, ..Params::default() });
        let mut moved_any = false;
        for _ in 0..120 {
            s.tick();
            let mut q = s.world.query::<&Moved>();
            let net: i64 = q.iter(&s.world).map(|m| m.0).sum();
            assert_eq!(net, 0, "migration must neither create nor destroy people");
            moved_any |= q.iter(&s.world).any(|m| m.0 != 0);
        }
        assert!(moved_any, "the test grid has a city and rural tiles, so people move");
    }

    #[test]
    fn neighbor_lists_match_a_full_rebuild() {
        let mut s = sim(Params::default());
        for _ in 0..60 {
            s.tick();
        }
        let idx = s.world.resource::<TileIndex>();
        for (&k, &e) in &idx.leaves {
            let want: Vec<Entity> = leaf_neighbors(idx, k).keys().iter().map(|n| idx.leaves[n]).collect();
            assert_eq!(*s.world.get::<Neighbors>(e).unwrap(), Neighbors::of(&want), "{}", k.id());
        }
    }

    /// The small test world's state after 20 years, pinned: any change to
    /// results must update this number on purpose (golden master).
    #[test]
    fn pinned_fingerprint() {
        let mut s = sim(Params::default());
        for _ in 0..240 {
            s.tick();
        }
        assert_eq!(format!("{:016x}", s.fingerprint()), "41e5847821cf0fe2");
    }

    mod props {
        use super::*;
        use proptest::prelude::*;

        fn params() -> impl Strategy<Value = Params> {
            (0.0f64..0.5, 0.01f64..0.2, 0.0f64..0.01, 0.0f64..1.0, 0.001f64..0.05, 0.001f64..0.02).prop_map(
                |(m, t, e, p, c, r)| Params {
                    migration_rate: m,
                    migration_threshold: t,
                    urban_excess_death: e,
                    city_pull_rate: p,
                    city_draw_cap: c,
                    r_per_year: r,
                    ..Params::default()
                },
            )
        }

        fn world(params: Params, pops: [f64; 3]) -> (Sim, Inputs) {
            let cities = vec![
                City { x_m: 30_000.0, z_m: 30_000.0, pop: pops[0] },
                City { x_m: 80_000.0, z_m: 20_000.0, pop: pops[1] },
                City { x_m: 60_000.0, z_m: 90_000.0, pop: pops[2] },
            ];
            (
                Sim::new(params.clone(), &test_start(), test_cells(), cities.clone()),
                Inputs::new(params, &test_start(), test_cells(), cities),
            )
        }

        proptest! {
            // Fixed seed: the same cases on every run and machine.
            #![proptest_config(ProptestConfig { cases: 32, rng_seed: proptest::test_runner::RngSeed::Fixed(0xA9014), failure_persistence: None, ..ProptestConfig::default() })]

            /// Migration and the city draw only move people: in every flow
            /// month the balances add up to exactly zero.
            #[test]
            fn flows_conserve_people(p in params(), pops in prop::array::uniform3(1_000.0f64..1_500_000.0)) {
                let (mut s, _) = world(Params { adaptive: false, ..p }, pops);
                for m in 0..10 * 12u32 {
                    s.tick();
                    if m % 12 == 0 {
                        let mut q = s.world.query::<&Moved>();
                        prop_assert_eq!(q.iter(&s.world).map(|x| x.0).sum::<i64>(), 0);
                    }
                }
            }

            /// Whatever the rates: no negative or lost people, the 2:1 rule
            /// holds, the budget holds, snapshot and index agree.
            #[test]
            fn invariants_hold(p in params(), pops in prop::array::uniform3(1_000.0f64..1_500_000.0), budget in 16usize..200) {
                let (mut s, _) = world(Params { budget, ..p }, pops);
                for _ in 0..10 * 12 {
                    s.tick();
                    prop_assert!(s.leaf_count() <= budget);
                    prop_assert!(s.balanced());
                    let mut q = s.world.query::<&Pop>();
                    prop_assert!(q.iter(&s.world).all(|p| p.0 >= 0));
                    prop_assert_eq!(s.snapshot().tiles.len(), s.leaf_count());
                }
            }

            /// Differential test over random rates and cities: same tiles
            /// and the same people as the reference, month by month.
            #[test]
            fn agrees_with_reference(p in params(), pops in prop::array::uniform3(1_000.0f64..1_500_000.0)) {
                let (mut s, mut r) = world(p, pops);
                for m in 0..20 * 12 {
                    s.tick();
                    r.tick();
                    let snap = s.snapshot();
                    prop_assert_eq!(snap.tiles.len(), r.leaves.len(), "tile count, month {}", m);
                    for t in &snap.tiles {
                        let want = r.leaves.get(&t.key).map(|x| x.p);
                        prop_assert!(want.is_some(), "tile {} only in ECS, month {}", t.key.id(), m);
                        let d = (t.pop - want.unwrap()).abs() / want.unwrap().max(1000.0);
                        prop_assert!(d < 1e-5, "month {}: {} differs by {:e}", m, t.key.id(), d);
                    }
                }
            }
        }
    }

    /// Population of the leaves that cover the big test city (x 30 km, z 30 km).
    fn city_pop(s: &mut Sim) -> f64 {
        s.snapshot()
            .tiles
            .iter()
            .filter(|t| {
                let (size, x0, z0) = (t.key.size_m(), t.key.col as f64 * t.key.size_m(), t.key.row as f64 * t.key.size_m());
                (x0..x0 + size).contains(&30_000.0) && (z0..z0 + size).contains(&30_000.0)
            })
            .map(|t| t.pop)
            .sum()
    }

    #[test]
    fn cities_shrink_alone_and_are_refilled_by_migration() {
        let years = 50 * 12;
        let mut alone = sim(Params { migration_rate: 0.0, city_pull_rate: 0.0, ..Params::default() });
        let mut fed = sim(Params::default());
        let start = city_pop(&mut alone);
        for _ in 0..years {
            alone.tick();
            fed.tick();
        }
        let (a, f) = (city_pop(&mut alone), city_pop(&mut fed));
        assert!(a < start, "without migration the city loses people: {start:.0} -> {a:.0}");
        assert!(f > a, "migration from the countryside refills it: {a:.0} vs {f:.0}");
    }
}
