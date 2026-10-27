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
    migration_rate: f64,
    migration_threshold: f64,
    /// Monthly keep factor of the city population, Q32.
    urban_keep_q32: i128,
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

/// City share of a tile's capacity (fixed point Q16: 65536 = all urban).
#[derive(Component, Default, Clone, Copy, Debug)]
pub struct UrbanShare(pub i64);

fn urban_share(local: f64, urban: f64) -> UrbanShare {
    let k = local + urban;
    UrbanShare(if k > 0.0 { to_fx(urban / k) } else { 0 })
}

/// Net migration of the current month (fixed point, + = arrivals).
#[derive(Component, Default, Clone, Copy, Debug)]
pub struct Moved(pub i64);

#[derive(Resource, Default)]
pub struct TileIndex {
    pub leaves: BTreeMap<Key, Entity>,
    /// Ancestors of leaves.
    pub internal: BTreeSet<Key>,
    /// Positions split at runtime; only these can merge back.
    pub split_nodes: BTreeSet<Key>,
    /// Nodes a merge may have unblocked; checked next month.
    pending_merge: BTreeSet<Key>,
    /// Leaves created this month; their neighbourhoods need new lists.
    born: Vec<Key>,
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
fn migrate(
    c: Res<TickConst>,
    mut dense: Local<Vec<Side>>,
    state: Query<(Entity, &TileKey, &Pop, &Cap)>,
    mut tiles: Query<(Entity, &Neighbors, &mut Moved)>,
) {
    let c = *c;
    if c.migration_rate <= 0.0 {
        return;
    }
    for (ents, keys, pop, cap) in state.contiguous_iter().expect("tiles live in tables") {
        for i in 0..ents.len() {
            let at = ents[i].index_u32() as usize;
            if at >= dense.len() {
                dense.resize(at + 1, Side::default());
            }
            dense[at] = side(pop[i].0, cap[i].0, keys[i].0.level);
        }
    }
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
    row0: i32,
    col0: i32,
    cols: usize,
    count: usize,
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
        let r = k.at_level(0);
        (r.row - self.row0) as usize * self.cols + (r.col - self.col0) as usize
    }
}

/// Cities draw migrants from their surroundings (MIGRATION.md, step
/// "Städte"): neighbour diffusion alone cannot feed Rome, which historically
/// drew on all of Italy. A city in root square r asks for a share of its
/// free city capacity from the rural people of the 3×3 root squares around
/// r (about 600 km, EU5's market-wide pull with a distance limit). Every
/// rural tile gives the same fraction asked of its catchment (capped). The
/// total taken is shared by all cities by what they asked, in ID order, the
/// last taking the remainder, so the sum is exact. Two passes over the tiles
/// plus a few hundred root squares.
fn city_draw(
    c: Res<TickConst>,
    regions: Res<Regions>,
    mut scratch: Local<(Vec<f64>, Vec<f64>)>,
    mut tiles: Query<(&TileKey, &Pop, &Cap, &UrbanShare, &mut Moved)>,
) {
    let c = *c;
    if c.city_pull_rate <= 0.0 {
        return;
    }
    let n = regions.count;
    let (demand, pool) = &mut *scratch;
    demand.clear();
    demand.resize(n, 0.0);
    pool.clear();
    pool.resize(n, 0.0);
    let mut cities: Vec<(Key, i64)> = Vec::new();
    // A tile is city and country at once: its city share u asks for
    // u·(K − P), its rural share (1 − u) of the people can be drawn.
    for (key, p, k, u, _) in &tiles {
        let r = regions.index(key.0);
        let uf = u.0 as f64 / FX as f64;
        if u.0 > 0 {
            let want = (c.city_pull_rate * uf * (k.0 - p.0).max(0) as f64) as i64;
            if want >= 1 {
                demand[r] += want as f64;
                cities.push((key.0, want));
            }
        }
        pool[r] += p.0.max(0) as f64 * (1.0 - uf);
    }
    // Rate asked of each catchment, then summed back onto each root square.
    let catchment = |r: usize| regions.around(r);
    let asked: Vec<f64> = (0..n)
        .map(|r| {
            let p3: f64 = catchment(r).map(|q| pool[q]).sum();
            if p3 > 0.0 { demand[r] / p3 } else { 0.0 }
        })
        .collect();
    let rate: Vec<f64> = (0..n).map(|q| catchment(q).map(|r| asked[r]).sum::<f64>().min(c.city_draw_cap)).collect();
    // Only the rural birth surplus leaves (landless children, Wrigley 1967;
    // de Vries 1984): this month's logistic gain of the rural share. A
    // drained countryside therefore stops sending instead of emptying.
    let d = c.decay_q32 as f64 / Q32 as f64;
    let mut taken = 0i64;
    for (key, p, k, u, mut moved) in &mut tiles {
        if u.0 < FX && p.0 > 0 && k.0 > p.0 {
            let rest = 1.0 - u.0 as f64 / FX as f64;
            let (pp, kk) = (p.0 as f64, k.0 as f64);
            let surplus = pp * (kk - pp) * (1.0 - d) / (pp + (kk - pp) * d) * rest;
            let asked = pp * rest * rate[regions.index(key.0)];
            let out = (asked.min(surplus) + 0.5) as i64;
            if out > 0 {
                moved.0 -= out;
                taken += out;
            }
        }
    }
    if cities.is_empty() {
        // Nobody to receive: give it back (cannot happen with taken > 0,
        // since rates are zero without demand).
        debug_assert_eq!(taken, 0);
        return;
    }
    // Hand out in ID order: the last city takes the remainder.
    cities.sort_unstable();
    let wanted: i64 = cities.iter().map(|c| c.1).sum();
    let mut left = taken;
    let mut gets: HashMap<Key, i64> = HashMap::with_capacity(cities.len());
    for (i, &(key, want)) in cities.iter().enumerate() {
        let g = if i + 1 == cities.len() { left } else { ((taken as i128 * want as i128) / wanted as i128) as i64 };
        left -= g;
        gets.insert(key, g);
    }
    for (key, _, _, u, mut moved) in &mut tiles {
        if u.0 > 0 {
            if let Some(g) = gets.get(&key.0) {
                moved.0 += g;
            }
        }
    }
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
fn growth(c: Res<TickConst>, found: Res<Scratch>, mut q: Query<(&TileKey, &mut Pop, &Cap, &Land, &mut MonthsLow, &Moved, &UrbanShare)>) {
    let c = *c;
    let d = c.decay_q32 as f64 / Q32 as f64;
    // Dense tile table: work on whole column slices (bevy_ecs 0.19
    // contiguous iteration), one chunk per task.
    let chunks = q.contiguous_par_iter_mut().expect("tiles live in tables");
    let keep = c.urban_keep_q32 as f64 / Q32 as f64;
    chunks.for_each(|(keys, pop, cap, land, low, moved, urban)| {
        // Population changes on practically every tile each month, so the
        // whole chunk is marked changed once instead of per tile (S47).
        let (pop, _) = ContiguousMut::split(pop);
        let (low, _) = ContiguousMut::split(low);
        for i in 0..keys.len() {
            let p = &mut pop[i].0;
            // Migration first (computed from the start-of-month state).
            *p += moved[i].0;
            if *p > 0 {
                let (pp, kk) = (*p as f64, cap[i].0 as f64);
                // Values are positive, so +0.5 and truncation round to nearest
                // without calling the software `round`.
                *p = if kk > 0.0 { (kk * pp / (pp + (kk - pp) * d) + 0.5) as i64 } else { (pp * d + 0.5) as i64 };
                // Urban graveyard: the city share of the tile loses its
                // excess deaths; only migration refills it.
                let u = urban[i].0;
                if u > 0 {
                    let city = *p as f64 * (u as f64 / FX as f64);
                    *p -= (city * (1.0 - keep) + 0.5) as i64;
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
fn leaf_neighbors(idx: &TileIndex, k: Key) -> Vec<Key> {
    let mut out = Vec::with_capacity(6);
    for n in k.edge_neighbors() {
        if let Some(c) = covering_leaf(idx, n) {
            out.push(c);
        } else if idx.internal.contains(&n) {
            for ch in n.children() {
                if idx.leaves.contains_key(&ch) && ch.edge_neighbors().iter().any(|m| m.at_level(k.level) == k) {
                    out.push(ch);
                }
            }
        }
    }
    out.sort();
    out.dedup();
    out
}

/// New neighbour lists for leaves born this month and every leaf next to
/// them (their old lists may point at despawned tiles).
fn refresh_neighbors(world: &mut World, idx: &mut TileIndex) {
    let born = std::mem::take(&mut idx.born);
    if born.is_empty() {
        return;
    }
    let mut dirty: BTreeSet<Key> = BTreeSet::new();
    for &k in &born {
        if idx.leaves.contains_key(&k) {
            dirty.insert(k);
            dirty.extend(leaf_neighbors(idx, k));
        }
    }
    for k in dirty {
        let list: Vec<Entity> = leaf_neighbors(idx, k).iter().map(|n| idx.leaves[n]).collect();
        debug_assert!(list.len() <= 8, "2:1 rule allows at most two neighbours per edge");
        let e = idx.leaves[&k];
        *world.get_mut::<Neighbors>(e).expect("neighbors") = Neighbors::of(&list);
    }
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
            migration_rate: params.migration_rate,
            migration_threshold: params.migration_threshold,
            urban_keep_q32: exp_neg_q32((params.urban_excess_death / 12.0 * Q32 as f64).round() as i128),
            city_pull_rate: params.city_pull_rate,
            city_draw_cap: params.city_draw_cap,
        };
        let db = Inputs::new(params, &[], cells, cities);
        let mut world = World::new();
        let mut idx = TileIndex::default();
        for &k in start {
            let (local, urban, land) = db.capacity_parts(k);
            let p = db.start_population(k, local, urban);
            let e = world.spawn((TileKey(k), Pop(to_fx(p)), Cap(to_fx(local + urban)), Land(to_fx(land)), MonthsLow(0), Neighbors::default(), Moved(0), urban_share(local, urban))).id();
            idx.leaves.insert(k, e);
            idx.born.push(k);
            let mut a = k;
            while a.level > 0 {
                a = a.parent();
                idx.internal.insert(a);
            }
        }
        world.insert_resource(InputDb(db));
        world.insert_resource(tc);
        refresh_neighbors(&mut world, &mut idx);
        world.insert_resource(idx);
        world.insert_resource(Candidates::default());
        world.insert_resource(Scratch::default());
        world.insert_resource(Regions::of(start));
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

    #[test]
    fn matches_reference_within_rounding() {
        // The reference has no migration and no urban excess deaths.
        let mut s = sim(Params { migration_rate: 0.0, urban_excess_death: 0.0, city_pull_rate: 0.0, ..Params::default() });
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
            let want: Vec<Entity> = leaf_neighbors(idx, k).iter().map(|n| idx.leaves[n]).collect();
            assert_eq!(*s.world.get::<Neighbors>(e).unwrap(), Neighbors::of(&want), "{}", k.id());
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
