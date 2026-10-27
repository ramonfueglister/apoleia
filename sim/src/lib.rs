//! Kit 2, subsystem 1: population per tile (decisions S30–S34, S12–S15, S21).
//!
//! One number per tile, capacity from food, logistic growth, adaptive tiles
//! that split and merge while conserving population. No hunger, disease,
//! migration or trade yet.

use std::collections::{BTreeMap, BTreeSet, HashMap};

pub mod ecs;
pub mod groups;
pub mod inputs;
pub mod life;
pub mod people;
pub mod save;
pub mod view;

pub const MAX_LEVEL: u8 = 7;
pub const ROOT_SIZE_M: f64 = 200_000.0;
/// Level of the 25 km terrain cells.
pub const CELL_LEVEL: u8 = 3;

/// Estimated parameters. Every value is an assumption to be replaced by data
/// or calibration; see docs/kit2/ESTIMATES.md.
#[derive(Clone, Debug)]
pub struct Params {
    /// Intrinsic growth rate per year below capacity.
    pub r_per_year: f64,
    /// Share of usable land under cultivation (incl. fallow).
    pub cropland_share: f64,
    /// People fed per km² of cropland.
    pub people_per_cropland_km2: f64,
    /// Usable share lost per unit of land above 1500 m.
    pub highland_penalty: f64,
    /// Start rural population as share of local capacity.
    pub start_fill: f64,
    /// Split when density (people per km² land) exceeds this (S15).
    pub split_density: f64,
    /// Merge when all four children stay below this density (S15).
    pub merge_density: f64,
    /// Months all four children must stay below `merge_density` (S15).
    pub merge_months: u16,
    /// Runtime cell budget (S12).
    pub budget: usize,
    /// Disable splitting and merging (for comparison runs, B02).
    pub adaptive: bool,
    /// Migration (Kit 2 MIGRATION.md): share of the smaller of sender
    /// population and receiver free capacity, per unit attraction difference
    /// and year, across a full edge. Migration and the city draw run once a
    /// year (January). 0 switches migration off.
    pub migration_rate: f64,
    /// Attraction differences up to this cause no migration (EU5: only
    /// locations far enough from their surroundings migrate).
    pub migration_threshold: f64,
    /// Pre-modern cities had more deaths than births ("urban graveyard",
    /// Kit 2 MIGRATION.md), the more the bigger the city (Davenport 2020):
    /// yearly excess deaths = this × log10(city / `urban_excess_from`),
    /// none below that size. 0.005 gives 1 %/yr at 500 000 (London, Wrigley
    /// 1967). Refilled only by migration. 0 switches it off.
    pub urban_excess_death: f64,
    /// City size (people) from which excess deaths start.
    pub urban_excess_from: f64,
    /// Share of a city tile's free capacity (K − P) that it asks for from
    /// its region each year (jobs, grain, EU5's market-wide pull).
    pub city_pull_rate: f64,
    /// At most this share of a region's rural population leaves for its
    /// cities in one year.
    pub city_draw_cap: f64,
    /// With HYDE data: true = K from HYDE cropland × `people_per_cropland_km2`;
    /// false = K anchored on the HYDE start population (start = `start_fill` × K).
    pub k_from_cropland: bool,
}

impl Default for Params {
    fn default() -> Self {
        Params {
            r_per_year: 0.006,
            cropland_share: 0.15,
            people_per_cropland_km2: 100.0,
            highland_penalty: 0.8,
            start_fill: 0.7,
            split_density: 200.0,
            merge_density: 100.0,
            merge_months: 12,
            budget: 65_536,
            adaptive: true,
            k_from_cropland: false,
            migration_rate: 0.24,
            urban_excess_death: 0.005,
            urban_excess_from: 5000.0,
            city_pull_rate: 0.6,
            city_draw_cap: 0.024,
            migration_threshold: 0.05,
        }
    }
}

/// Tile address: level, row, column (ordering gives the fixed ID order, S13).
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Key {
    pub level: u8,
    pub row: i32,
    pub col: i32,
}

impl Key {
    pub fn new(level: u8, row: i32, col: i32) -> Self {
        Key { level, row, col }
    }
    pub fn size_m(self) -> f64 {
        ROOT_SIZE_M / f64::from(1u32 << self.level)
    }
    pub fn parent(self) -> Key {
        Key::new(self.level - 1, self.row.div_euclid(2), self.col.div_euclid(2))
    }
    pub fn children(self) -> [Key; 4] {
        let (l, r, c) = (self.level + 1, self.row * 2, self.col * 2);
        [Key::new(l, r, c), Key::new(l, r, c + 1), Key::new(l, r + 1, c), Key::new(l, r + 1, c + 1)]
    }
    /// The ancestor (or self) at a coarser or equal level.
    pub fn at_level(self, level: u8) -> Key {
        let d = self.level - level;
        Key::new(level, self.row.div_euclid(1 << d), self.col.div_euclid(1 << d))
    }
    pub fn edge_neighbors(self) -> [Key; 4] {
        let (l, r, c) = (self.level, self.row, self.col);
        [Key::new(l, r - 1, c), Key::new(l, r + 1, c), Key::new(l, r, c - 1), Key::new(l, r, c + 1)]
    }
    pub fn id(self) -> String {
        format!("eqc41-gt-v1:{}:{}:{}", self.level, self.row, self.col)
    }
    pub fn parse(id: &str) -> Option<Key> {
        let mut it = id.strip_prefix("eqc41-gt-v1:")?.split(':');
        let level = it.next()?.parse().ok()?;
        let row = it.next()?.parse().ok()?;
        let col = it.next()?.parse().ok()?;
        Some(Key::new(level, row, col))
    }
}

/// Static inputs for one 25 km cell.
#[derive(Clone, Copy, Debug, Default)]
pub struct Cell {
    pub land_km2: f64,
    pub frac_bare: f64,
    pub frac_snow: f64,
    pub frac_above_1500m: f64,
    /// HYDE 3.3 values for 200 AD when available; replaces the estimates.
    pub hyde: Option<Hyde>,
}

/// HYDE 3.3 data aggregated to a 25 km cell (tools/sim_hyde.py).
#[derive(Clone, Copy, Debug, Default)]
pub struct Hyde {
    pub crop_km2: f64,
    pub pop: f64,
    /// Rural population (HYDE `rurc`); when present, cities come from the
    /// city list instead of HYDE's urban share (S35).
    pub rural: Option<f64>,
}

#[derive(Clone, Copy, Debug)]
pub struct City {
    pub x_m: f64,
    pub z_m: f64,
    pub pop: f64,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct Tile {
    pub p: f64,
    pub k: f64,
    pub land_km2: f64,
    /// Consecutive months below the merge density.
    pub months_low: u16,
    /// City share of the capacity, urban / (local + urban).
    pub u: f64,
    /// Net migration of the last flow month (+ = arrivals).
    pub moved: f64,
}

pub struct World {
    pub params: Params,
    pub leaves: BTreeMap<Key, Tile>,
    /// Ancestors of leaves (subdivided positions).
    pub internal: BTreeSet<Key>,
    /// Positions subdivided at runtime (at or below a start leaf); only these
    /// can merge back, so merging never goes above the start grid.
    pub split_nodes: BTreeSet<Key>,
    cells: HashMap<(i32, i32), Cell>,
    cities: HashMap<(i32, i32), Vec<City>>,
    pub month: u32,
    /// Nodes a merge may have unblocked; checked in the next month.
    pending_merge: BTreeSet<Key>,
    pub splits: u64,
    pub merges: u64,
    /// Root squares spanned by the start grid: first row, first column,
    /// rows, columns (catchments of the city draw).
    roots: (i32, i32, i32, i32),
}

impl World {
    pub fn new(params: Params, start: &[Key], cells: HashMap<(i32, i32), Cell>, cities: Vec<City>) -> World {
        let cell_size = Key::new(CELL_LEVEL, 0, 0).size_m();
        let mut by_cell: HashMap<(i32, i32), Vec<City>> = HashMap::new();
        for c in cities {
            let rc = ((c.z_m / cell_size).floor() as i32, (c.x_m / cell_size).floor() as i32);
            by_cell.entry(rc).or_default().push(c);
        }
        let mut w = World {
            params,
            leaves: BTreeMap::new(),
            internal: BTreeSet::new(),
            split_nodes: BTreeSet::new(),
            cells,
            cities: by_cell,
            month: 0,
            pending_merge: BTreeSet::new(),
            splits: 0,
            merges: 0,
            roots: (0, 0, 0, 0),
        };
        if !start.is_empty() {
            let r: Vec<Key> = start.iter().map(|k| k.at_level(0)).collect();
            let (r0, r1) = (r.iter().map(|k| k.row).min().unwrap(), r.iter().map(|k| k.row).max().unwrap());
            let (c0, c1) = (r.iter().map(|k| k.col).min().unwrap(), r.iter().map(|k| k.col).max().unwrap());
            w.roots = (r0, c0, r1 - r0 + 1, c1 - c0 + 1);
        }
        for &k in start {
            let (local, urban, _) = w.capacity_parts(k);
            let p = w.start_population(k, local, urban);
            w.leaves.insert(k, Tile { p, ..w.fresh_tile(k) });
            let mut a = k;
            while a.level > 0 {
                a = a.parent();
                w.internal.insert(a);
            }
        }
        w
    }

    /// Local (non-city) capacity of a 25 km cell; `urban` is the city
    /// capacity inside it, which the start-anchored mode leaves out.
    fn cell_capacity(&self, c: &Cell, urban: f64) -> f64 {
        let p = &self.params;
        if let Some(h) = c.hyde {
            if p.k_from_cropland {
                return h.crop_km2 * p.people_per_cropland_km2;
            }
            return match h.rural {
                Some(r) => r / p.start_fill,
                None => (h.pop / p.start_fill - urban).max(0.0),
            };
        }
        let usable = (1.0 - c.frac_bare - c.frac_snow).max(0.0) * (1.0 - p.highland_penalty * c.frac_above_1500m).max(0.0);
        c.land_km2 * usable * p.cropland_share * p.people_per_cropland_km2
    }

    /// Start population of a start leaf: HYDE 200 AD where present, otherwise
    /// `start_fill` × local capacity plus cities. Below cell level the cell's
    /// HYDE count is spread by capacity, like a split (S34).
    pub fn start_population(&self, k: Key, local: f64, urban: f64) -> f64 {
        let estimate = self.params.start_fill * local + urban;
        if k.level <= CELL_LEVEL {
            let n = 1i32 << (CELL_LEVEL - k.level);
            let (mut any, mut total, mut rural, mut all_rural) = (false, 0.0, 0.0, true);
            for r in k.row * n..(k.row + 1) * n {
                for c in k.col * n..(k.col + 1) * n {
                    if let Some(h) = self.cells.get(&(r, c)).and_then(|cell| cell.hyde) {
                        any = true;
                        total += h.pop;
                        match h.rural {
                            Some(v) => rural += v,
                            None => all_rural = false,
                        }
                    }
                }
            }
            if !any {
                return estimate;
            }
            // With rural data: HYDE countryside plus the listed cities.
            return if all_rural { rural + urban } else { total };
        }
        let ck = k.at_level(CELL_LEVEL);
        let Some(h) = self.cells.get(&(ck.row, ck.col)).and_then(|cell| cell.hyde) else {
            return estimate;
        };
        let (cl, cu, cland) = self.capacity_parts(ck);
        if let Some(rural) = h.rural {
            let share = if cl > 0.0 { local / cl } else if cland > 0.0 { self.capacity_parts(k).2 / cland } else { 0.0 };
            return rural * share + urban;
        }
        if cl + cu > 0.0 {
            h.pop * (local + urban) / (cl + cu)
        } else if cland > 0.0 {
            h.pop * self.capacity_parts(k).2 / cland
        } else {
            0.0
        }
    }

    /// (local food capacity, urban import placeholder, land km²) for a tile.
    /// Below cell level, cell values are spread evenly by area; cities are
    /// assigned to the sub-tile that contains them.
    pub fn capacity_parts(&self, k: Key) -> (f64, f64, f64) {
        let size = k.size_m();
        let (x0, z0) = (k.col as f64 * size, k.row as f64 * size);
        let in_tile = |c: &City| c.x_m >= x0 && c.x_m < x0 + size && c.z_m >= z0 && c.z_m < z0 + size;
        let (mut local, mut urban, mut land) = (0.0, 0.0, 0.0);
        if k.level <= CELL_LEVEL {
            let n = 1i32 << (CELL_LEVEL - k.level);
            for r in k.row * n..(k.row + 1) * n {
                for c in k.col * n..(k.col + 1) * n {
                    let u: f64 = self.cities.get(&(r, c)).map_or(0.0, |cs| cs.iter().map(|c| c.pop).sum());
                    if let Some(cell) = self.cells.get(&(r, c)) {
                        local += self.cell_capacity(cell, u);
                        land += cell.land_km2;
                    }
                    urban += u;
                }
            }
        } else {
            let ck = k.at_level(CELL_LEVEL);
            let share = 1.0 / f64::from(1u32 << (2 * (k.level - CELL_LEVEL)));
            let u: f64 = self.cities.get(&(ck.row, ck.col)).map_or(0.0, |cs| cs.iter().map(|c| c.pop).sum());
            if let Some(cell) = self.cells.get(&(ck.row, ck.col)) {
                local = self.cell_capacity(cell, u) * share;
                land = cell.land_km2 * share;
            }
            if let Some(cs) = self.cities.get(&(ck.row, ck.col)) {
                urban = cs.iter().filter(|c| in_tile(c)).map(|c| c.pop).sum();
            }
        }
        (local, urban, land)
    }

    /// Leaf covering a position, if the position is not subdivided further.
    pub fn covering_leaf(&self, k: Key) -> Option<Key> {
        (0..=k.level).rev().map(|l| k.at_level(l)).find(|a| self.leaves.contains_key(a))
    }

    fn density(t: &Tile) -> f64 {
        if t.land_km2 > 0.0 {
            t.p / t.land_km2
        } else {
            0.0
        }
    }

    pub fn total_population(&self) -> f64 {
        self.leaves.values().map(|t| t.p).sum()
    }

    /// A tile at `k` with its static values and no people yet.
    fn fresh_tile(&self, k: Key) -> Tile {
        let (local, urban, land) = self.capacity_parts(k);
        let cap = local + urban;
        Tile { p: 0.0, k: cap, land_km2: land, months_low: 0, u: if cap > 0.0 { urban / cap } else { 0.0 }, moved: 0.0 }
    }

    /// One monthly tick (S21), written as plainly as possible so it can serve
    /// as the test oracle of the ECS core (differential testing): once a
    /// year (first month) migration and the city draw, then every month
    /// growth with urban excess deaths, then split/merge.
    pub fn tick(&mut self) {
        let flow = self.month % 12 == 0;
        if flow {
            self.migrate();
            self.city_draw();
        }
        let rm = self.params.r_per_year / 12.0;
        let decay = (-rm).exp();
        let merge_d = self.params.merge_density;
        let need = self.params.merge_months;
        let split_d = self.params.split_density;
        let (excess, from) = (self.params.urban_excess_death / 12.0, self.params.urban_excess_from);
        // Parents whose children just became eligible for merging, and leaves
        // over the split density (collected here to avoid a second scan).
        let mut fresh: Vec<Key> = Vec::new();
        let mut split_cand: Vec<(Key, f64)> = Vec::new();
        for (k, t) in self.leaves.iter_mut() {
            if flow {
                t.p += t.moved;
            }
            if t.p > 0.0 {
                // Exact solution of the logistic equation over one month:
                // stable, never negative, approaches K without overshoot.
                t.p = if t.k > 0.0 { t.k / (1.0 + (t.k - t.p) / t.p * decay) } else { t.p * decay };
                // Urban graveyard: excess deaths grow with city size.
                let city = t.p * t.u;
                if city > from {
                    t.p -= city * excess * (city / from).log10();
                }
            }
            let d = Self::density(t);
            t.months_low = if d < merge_d { t.months_low.saturating_add(1) } else { 0 };
            if t.months_low == need && k.level > 0 {
                fresh.push(k.parent());
            }
            if d > split_d && k.level < MAX_LEVEL {
                split_cand.push((*k, t.p));
            }
        }
        if self.params.adaptive {
            self.split_pass(split_cand);
            // A split never unblocks a merge. A merge can unblock its parent
            // and that parent's neighbours (queued in `pending_merge`); all
            // other nodes can only become mergeable when their last child
            // crosses the threshold (`fresh`).
            fresh.extend(std::mem::take(&mut self.pending_merge));
            self.merge_pass(fresh);
        }
        self.month += 1;
    }

    /// Leaves sharing an edge with leaf `k`: per side, the leaf covering
    /// the same-level neighbour position, or the two finer leaves along that
    /// side when the position is subdivided (2:1 rule).
    pub fn neighbors(&self, k: Key) -> Vec<Key> {
        let mut out = Vec::new();
        for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let n = Key::new(k.level, k.row + dr, k.col + dc);
            if let Some(c) = self.covering_leaf(n) {
                out.push(c);
                continue;
            }
            // The two children of n that touch k.
            let (r, c) = (n.row * 2, n.col * 2);
            let touching = match (dr, dc) {
                (-1, 0) => [(r + 1, c), (r + 1, c + 1)],
                (1, 0) => [(r, c), (r, c + 1)],
                (0, -1) => [(r, c + 1), (r + 1, c + 1)],
                _ => [(r, c), (r + 1, c)],
            };
            for (r, c) in touching {
                let ch = Key::new(k.level + 1, r, c);
                if self.leaves.contains_key(&ch) {
                    out.push(ch);
                }
            }
        }
        out.sort();
        out.dedup();
        out
    }

    /// Neighbour migration (MIGRATION.md): along each edge, people move from
    /// the fuller to the emptier tile when their attraction 1 − P/K differs
    /// by more than the threshold.
    fn migrate(&mut self) {
        let rate = self.params.migration_rate;
        let threshold = self.params.migration_threshold;
        // Attraction, people, free places of a tile at the start of the month.
        let side = |t: &Tile| {
            let a = if t.k > 0.0 { (1.0 - t.p / t.k).clamp(-1.0, 1.0) } else { -1.0 };
            (a, t.p.max(0.0), (t.k - t.p).max(0.0))
        };
        // Share of a tile's perimeter that one neighbour's edge covers.
        let w = |from: u8, to: u8| if to <= from { 0.25 } else { 0.25 / f64::from(1u32 << (to - from)) };
        let mut moved: BTreeMap<Key, f64> = BTreeMap::new();
        for (&a, ta) in &self.leaves {
            let (aa, pa, fa) = side(ta);
            let mut net = 0.0;
            for b in self.neighbors(a) {
                let (ab, pb, fb) = side(&self.leaves[&b]);
                let d = ab - aa;
                if rate > 0.0 && d > threshold {
                    net -= rate * d * (pa * w(a.level, b.level)).min(fb * w(b.level, a.level));
                } else if rate > 0.0 && -d > threshold {
                    net += rate * -d * (pb * w(b.level, a.level)).min(fa * w(a.level, b.level));
                }
            }
            moved.insert(a, net);
        }
        for (k, m) in moved {
            self.leaves.get_mut(&k).unwrap().moved = m;
        }
    }

    /// City draw (MIGRATION.md): each city asks for a share of its free city
    /// places from the rural people of the 3×3 root squares around it; every
    /// rural tile gives the rate asked of it, at most its own yearly birth
    /// surplus; the total goes to the cities in proportion to what they asked.
    fn city_draw(&mut self) {
        let pull = self.params.city_pull_rate;
        if pull <= 0.0 {
            return;
        }
        let (row0, col0, rows, cols) = self.roots;
        let root = |k: &Key| {
            let r = k.at_level(0);
            ((r.row - row0) * cols + (r.col - col0)) as usize
        };
        let around = |i: usize| {
            let (r, c) = (i as i32 / cols, i as i32 % cols);
            let mut v = Vec::new();
            for y in r - 1..=r + 1 {
                for x in c - 1..=c + 1 {
                    if y >= 0 && x >= 0 && y < rows && x < cols {
                        v.push((y * cols + x) as usize);
                    }
                }
            }
            v
        };
        let n = (rows * cols) as usize;
        let (mut demand, mut pool) = (vec![0.0; n], vec![0.0; n]);
        let mut wants: Vec<(Key, f64)> = Vec::new();
        for (k, t) in &self.leaves {
            if t.u > 0.0 {
                let want = pull * t.u * (t.k - t.p).max(0.0);
                if want > 0.0 {
                    demand[root(k)] += want;
                    wants.push((*k, want));
                }
            }
            pool[root(k)] += t.p.max(0.0) * (1.0 - t.u);
        }
        if wants.is_empty() {
            return;
        }
        let asked: Vec<f64> = (0..n)
            .map(|r| {
                let p: f64 = around(r).iter().map(|&q| pool[q]).sum();
                if p > 0.0 { demand[r] / p } else { 0.0 }
            })
            .collect();
        let cap = self.params.city_draw_cap;
        let rate: Vec<f64> = (0..n).map(|q| around(q).iter().map(|&r| asked[r]).sum::<f64>().min(cap)).collect();
        let year = (-self.params.r_per_year).exp();
        let mut taken = 0.0;
        for (k, t) in self.leaves.iter_mut() {
            if t.u < 1.0 && t.p > 0.0 && t.k > t.p {
                let rural = t.p * (1.0 - t.u);
                let surplus = t.p * (t.k - t.p) * (1.0 - year) / (t.p + (t.k - t.p) * year) * (1.0 - t.u);
                let out = (rural * rate[root(k)]).min(surplus);
                t.moved -= out;
                taken += out;
            }
        }
        let wanted: f64 = wants.iter().map(|w| w.1).sum();
        for (k, want) in wants {
            self.leaves.get_mut(&k).unwrap().moved += taken * want / wanted;
        }
    }

    fn split_pass(&mut self, mut cand: Vec<(Key, f64)>) {
        // Importance = population, ties by ID (S12, S13).
        cand.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.cmp(&b.0)));
        for (k, _) in cand {
            if self.leaves.contains_key(&k) {
                self.split_balanced(k);
            }
        }
    }

    /// Split a leaf, first splitting coarser edge neighbours so the 2:1 rule
    /// holds. Returns false if the budget does not allow it.
    pub fn split_balanced(&mut self, k: Key) -> bool {
        for n in k.edge_neighbors() {
            while let Some(c) = self.covering_leaf(n) {
                if c.level >= k.level {
                    break;
                }
                if !self.split_balanced(c) {
                    return false;
                }
            }
        }
        self.split(k)
    }

    fn split(&mut self, k: Key) -> bool {
        if self.leaves.len() + 3 > self.params.budget {
            return false;
        }
        let parent = match self.leaves.remove(&k) {
            Some(t) => t,
            None => return false,
        };
        let kids = k.children();
        let parts: Vec<(f64, f64, f64)> = kids.iter().map(|&c| self.capacity_parts(c)).collect();
        let ksum: f64 = parts.iter().map(|p| p.0 + p.1).sum();
        let lsum: f64 = parts.iter().map(|p| p.2).sum();
        let mut given = 0.0;
        for (i, (&c, &(local, urban, land))) in kids.iter().zip(parts.iter()).enumerate() {
            // S33: weight by capacity, else by land; last child takes the rest.
            let p = if i == 3 {
                parent.p - given
            } else if ksum > 0.0 {
                parent.p * (local + urban) / ksum
            } else if lsum > 0.0 {
                parent.p * land / lsum
            } else {
                parent.p / 4.0
            };
            given += p;
            self.leaves.insert(c, Tile { p: p.max(0.0), ..self.fresh_tile(c) });
        }
        self.internal.insert(k);
        self.split_nodes.insert(k);
        self.splits += 1;
        true
    }

    fn merge_pass(&mut self, mut nodes: Vec<Key>) {
        let need = self.params.merge_months;
        nodes.sort();
        nodes.dedup();
        nodes.retain(|q| self.split_nodes.contains(q));
        let cand: Vec<Key> = nodes
            .into_iter()
            .filter(|q| {
                q.children().iter().all(|c| self.leaves.get(c).is_some_and(|t| t.months_low >= need))
            })
            .collect();
        for q in cand {
            if self.can_merge(q) {
                self.merge(q);
            }
        }
    }

    fn can_merge(&self, q: Key) -> bool {
        if !q.children().iter().all(|c| self.leaves.contains_key(c)) {
            return false;
        }
        // 2:1 rule: no position next to q at child level may be subdivided.
        let l = q.level + 1;
        let (r0, c0) = (q.row * 2, q.col * 2);
        let ring = [
            (r0 - 1, c0), (r0 - 1, c0 + 1), (r0 + 2, c0), (r0 + 2, c0 + 1),
            (r0, c0 - 1), (r0 + 1, c0 - 1), (r0, c0 + 2), (r0 + 1, c0 + 2),
        ];
        ring.iter().all(|&(r, c)| !self.internal.contains(&Key::new(l, r, c)))
    }

    fn merge(&mut self, q: Key) {
        let mut p = 0.0;
        for c in q.children() {
            p += self.leaves.remove(&c).map_or(0.0, |t| t.p);
        }
        self.leaves.insert(q, Tile { p, ..self.fresh_tile(q) });
        self.internal.remove(&q);
        self.split_nodes.remove(&q);
        self.merges += 1;
        if q.level > 0 {
            let up = q.parent();
            self.pending_merge.insert(up);
            self.pending_merge.extend(up.edge_neighbors());
        }
    }

    /// Checks the 2:1 rule over all leaves.
    pub fn balanced(&self) -> bool {
        self.leaves.keys().all(|k| {
            k.edge_neighbors().iter().all(|n| match self.covering_leaf(*n) {
                Some(c) => k.level <= c.level + 1,
                None => true,
            })
        })
    }

    /// Order-sensitive fingerprint of the state for determinism checks.
    pub fn fingerprint(&self) -> u64 {
        let mut h: u64 = 0xcbf29ce484222325;
        for (k, t) in &self.leaves {
            for v in [k.level as u64, k.row as u64, k.col as u64, t.p.to_bits()] {
                h ^= v;
                h = h.wrapping_mul(0x100000001b3);
            }
        }
        h
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn growth_only() -> Params {
        Params { migration_rate: 0.0, urban_excess_death: 0.0, city_pull_rate: 0.0, ..Params::default() }
    }

    /// A 4×4 block of 25 km cells with one large city, started at 50 km.
    fn small_world(params: Params) -> World {
        let cities = vec![
            City { x_m: 30_000.0, z_m: 40_000.0, pop: 900_000.0 },
            City { x_m: 80_000.0, z_m: 10_000.0, pop: 20_000.0 },
        ];
        world_with_cities(params, cities)
    }

    fn world_with_cities(params: Params, cities: Vec<City>) -> World {
        let mut cells = HashMap::new();
        for r in 0..4 {
            for c in 0..4 {
                cells.insert((r, c), Cell { land_km2: 625.0, frac_bare: 0.0, frac_snow: 0.0, frac_above_1500m: 0.0, hyde: None });
            }
        }
        let start: Vec<Key> = (0..2).flat_map(|r| (0..2).map(move |c| Key::new(2, r, c))).collect();
        World::new(params, &start, cells, cities)
    }

    #[test]
    fn split_and_merge_conserve_population() {
        let mut w = small_world(Params::default());
        let before = w.total_population();
        assert!(w.split_balanced(Key::new(2, 0, 0)));
        assert!(w.split_balanced(Key::new(3, 1, 1)));
        let after = w.total_population();
        assert!((after - before).abs() <= before * 1e-12, "{before} vs {after}");
        w.merge(Key::new(3, 1, 1));
        assert!((w.total_population() - before).abs() <= before * 1e-12);
    }

    #[test]
    fn split_keeps_ratio_to_capacity() {
        let mut w = small_world(Params::default());
        let k = Key::new(2, 0, 0);
        let ratio = w.leaves[&k].p / w.leaves[&k].k;
        w.split_balanced(k);
        for c in k.children() {
            let t = w.leaves[&c];
            assert!((t.p / t.k - ratio).abs() < 1e-9);
        }
    }

    #[test]
    fn runs_are_deterministic() {
        let mut a = small_world(Params::default());
        let mut b = small_world(Params::default());
        for _ in 0..600 {
            a.tick();
            b.tick();
        }
        assert_eq!(a.fingerprint(), b.fingerprint());
    }

    #[test]
    fn stays_balanced_finite_and_within_budget() {
        let params = Params { budget: 40, ..growth_only() };
        let mut w = small_world(params);
        let p0 = w.total_population();
        for _ in 0..1200 {
            w.tick();
            assert!(w.leaves.len() <= 40);
            assert!(w.balanced());
            assert!(w.leaves.values().all(|t| t.p.is_finite() && t.p >= 0.0));
        }
        assert!(w.splits > 0);
        assert!(w.total_population() > p0);
    }

    #[test]
    fn approaches_capacity_without_overshoot() {
        // Growth alone (migration and cities move people around).
        let params = Params { adaptive: false, ..growth_only() };
        let mut w = small_world(params);
        let mut prev: Vec<f64> = w.leaves.values().map(|t| t.p).collect();
        for _ in 0..12_000 {
            w.tick();
            let now: Vec<f64> = w.leaves.values().map(|t| t.p).collect();
            for ((p, n), t) in prev.iter().zip(&now).zip(w.leaves.values()) {
                assert!(n >= p && *n <= t.k * (1.0 + 1e-12));
            }
            prev = now;
        }
    }

    #[test]
    fn merges_back_when_density_drops() {
        // Rural only: nothing else splits, so the block may merge back.
        let params = Params { merge_months: 2, ..Params::default() };
        let mut w = world_with_cities(params, Vec::new());
        w.split_balanced(Key::new(2, 1, 1));
        assert!(w.leaves.contains_key(&Key::new(3, 2, 2)));
        for _ in 0..3 {
            w.tick();
        }
        assert!(w.leaves.contains_key(&Key::new(2, 1, 1)), "low-density block should merge");
        assert!(w.merges > 0);
    }

    #[test]
    fn key_round_trip_and_geometry() {
        let k = Key::new(5, -3, 7);
        assert_eq!(Key::parse(&k.id()), Some(k));
        assert_eq!(k.parent(), Key::new(4, -2, 3));
        assert_eq!(k.at_level(3), Key::new(3, -1, 1));
        assert!(k.children().iter().all(|c| c.parent() == k));
    }
}
