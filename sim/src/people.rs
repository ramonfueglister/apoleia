//! Load prototype for individually simulated people (decisions S50–S60,
//! docs/kit2/SCALE.md).
//!
//! Measures whether 100,000 people as ECS entities fit the tick budget. The
//! rules here are placeholders that generate realistic load (needs, relations,
//! trips with path search, a yearly job choice); they are not game rules.
//! There are no births, deaths or marriages: those are still open (S54, S59).
//!
//! Determinism: every random draw is a hash of (seed, person, salt, day), so
//! the result does not depend on thread count or iteration order. Structural
//! changes (trips starting and ending) run serially, sorted by person id.

use crate::inputs::Inputs;
use bevy_ecs::change_detection::ContiguousMut;
use bevy_ecs::prelude::*;
use rustc_hash::FxHashMap;
use std::cmp::Reverse;
use std::collections::BinaryHeap;
use xxhash_rust::xxh3::xxh3_64;

/// Real people per simulated person (S50).
pub const PEOPLE_PER_PERSON: f64 = 566.5;
/// Minimum inhabitants of a listed place (S57).
pub const MIN_PER_PLACE: u32 = 2;
/// Size of the path-search grid cell in real metres (the 25 km cells).
const CELL_M: f64 = 25_000.0;
pub const MAX_REL: usize = 30;
const NEEDS: usize = 4;
/// Placeholder travel speeds in real km per day: on foot and by ship.
const LAND_KM_DAY: i32 = 30;
const SEA_KM_DAY: i32 = 100;
/// Placeholder: share of people starting a trip each month, per 10,000.
const TRIPS_PER_10K_MONTH: u64 = 30;
const JOBS: u8 = 12;
/// Neighbour offsets; index d and 7 − d are opposite directions.
const DIRS: [(i32, i32); 8] = [
    (-1, -1),
    (-1, 0),
    (-1, 1),
    (0, -1),
    (0, 1),
    (1, -1),
    (1, 0),
    (1, 1),
];

#[derive(Component, Clone, Copy)]
pub struct Pid(pub u32);
#[derive(Component, Clone, Copy)]
pub struct Born(pub i32);
#[derive(Component, Clone, Copy)]
pub struct Sex(pub u8);
#[derive(Component, Clone, Copy)]
pub struct Household(pub u32);
#[derive(Component, Clone, Copy)]
pub struct Home(pub u32);
#[derive(Component, Clone, Copy)]
pub struct Job(pub u8);
#[derive(Component, Clone, Copy)]
pub struct Traits(pub u32);
#[derive(Component, Clone, Copy)]
pub struct Health(pub u16);
#[derive(Component, Clone, Copy)]
pub struct Stand(pub u8);
/// Placeholder culture and religion ids (by region band); real values
/// come later. Together with Home and Stand they key the person's pop.
#[derive(Component, Clone, Copy)]
pub struct Culture(pub u16);
#[derive(Component, Clone, Copy)]
pub struct Religion(pub u16);
/// Political group membership (placeholder id).
#[derive(Component, Clone, Copy)]
pub struct Faction(pub u16);
#[derive(Component, Clone, Copy)]
pub struct Needs(pub [u16; NEEDS]);
#[derive(Component, Clone, Copy)]
pub struct Relations {
    pub n: u8,
    pub ids: [u32; MAX_REL],
    pub opinion: [i8; MAX_REL],
}
/// A trip in progress: there and back home. `at` is the current cell, `km`
/// the distance walked on the current leg. The way to the destination comes
/// from its flow field; the way back retraces the cells walked.
#[derive(Component, Clone)]
pub struct Travel {
    pub to: u32,
    pub at: u32,
    pub km: i32,
    pub back: bool,
    pub path: Vec<u32>,
}

fn rnd(seed: u64, pid: u32, salt: u32, t: i64) -> u64 {
    let mut b = [0u8; 24];
    b[..8].copy_from_slice(&seed.to_le_bytes());
    b[8..12].copy_from_slice(&pid.to_le_bytes());
    b[12..16].copy_from_slice(&salt.to_le_bytes());
    b[16..24].copy_from_slice(&t.to_le_bytes());
    xxh3_64(&b)
}

/// The 25 km grid as a graph: land cells from cells25.csv, every other cell
/// in the bounding box is sea. Cells with land and sea are ports.
pub struct Grid {
    pub row0: i32,
    pub col0: i32,
    pub rows: i32,
    pub cols: i32,
    /// 0 = sea, 1 = coast (port), 2 = inland.
    pub kind: Vec<u8>,
}

impl Grid {
    pub fn index(&self, row: i32, col: i32) -> Option<u32> {
        let (r, c) = (row - self.row0, col - self.col0);
        (r >= 0 && c >= 0 && r < self.rows && c < self.cols).then(|| (r * self.cols + c) as u32)
    }
    fn rc(&self, i: u32) -> (i32, i32) {
        (i as i32 / self.cols, i as i32 % self.cols)
    }
    /// Cost in km-days ×100 of a step between neighbouring cells.
    fn step(&self, a: u32, b: u32, diag: bool) -> Option<i32> {
        let (ka, kb) = (self.kind[a as usize], self.kind[b as usize]);
        let km = if diag { 35 } else { 25 };
        let speed = match (ka, kb) {
            (0, 2) | (2, 0) => return None,
            (0, _) | (_, 0) => SEA_KM_DAY,
            _ => LAND_KM_DAY,
        };
        Some(km * 100 / speed)
    }
    /// The step from `i` to the neighbouring cell `j`: cell and km
    /// (negative for a sea leg).
    pub fn leg(&self, i: u32, j: u32) -> (u32, i32) {
        let ((ri, ci), (rj, cj)) = (self.rc(i), self.rc(j));
        let km = if ri != rj && ci != cj { 35 } else { 25 };
        let sea = self.kind[i as usize] == 0 || self.kind[j as usize] == 0;
        (j, if sea { -km } else { km })
    }

    /// The 100 km region (tile level 1, four 25 km cells per side) of a cell:
    /// the area a pop is grouped over (S61), until there are provinces.
    pub fn region(&self, i: u32) -> u32 {
        let (r, c) = self.rc(i);
        let (r, c) = ((r + self.row0).div_euclid(4), (c + self.col0).div_euclid(4));
        ((r + 64) as u32) << 16 | (c + 64) as u32
    }

    /// Dijkstra from `to` over the whole grid (costs are symmetric): for every
    /// cell the direction (0–7) of the next step towards `to`, 255 if none.
    /// One field per destination serves every trip there (flow field).
    pub fn flow_field(&self, to: u32) -> Vec<u8> {
        let n = self.kind.len();
        let mut best = vec![i32::MAX; n];
        let mut dir = vec![255u8; n];
        let mut open = BinaryHeap::new();
        best[to as usize] = 0;
        open.push(Reverse((0, to)));
        while let Some(Reverse((g, i))) = open.pop() {
            if g > best[i as usize] {
                continue;
            }
            let (r, c) = self.rc(i);
            for (d, (dr, dc)) in DIRS.iter().enumerate() {
                let (nr, nc) = (r + dr, c + dc);
                if nr < 0 || nc < 0 || nr >= self.rows || nc >= self.cols {
                    continue;
                }
                let j = (nr * self.cols + nc) as u32;
                let Some(cost) = self.step(j, i, *dr != 0 && *dc != 0) else {
                    continue;
                };
                let ng = g + cost;
                if ng < best[j as usize] {
                    best[j as usize] = ng;
                    // From j, step opposite to d to reach i.
                    dir[j as usize] = (7 - d) as u8;
                    open.push(Reverse((ng, j)));
                }
            }
        }
        dir
    }

    /// The next step from `i` along a flow field: cell and km (negative for
    /// a sea leg). None at the destination or where it cannot be reached.
    pub fn next(&self, field: &[u8], i: u32) -> Option<(u32, i32)> {
        let d = field[i as usize];
        if d == 255 {
            return None;
        }
        let (dr, dc) = DIRS[d as usize];
        let (r, c) = self.rc(i);
        let j = ((r + dr) * self.cols + c + dc) as u32;
        let km = if dr != 0 && dc != 0 { 35 } else { 25 };
        let sea = self.kind[i as usize] == 0 || self.kind[j as usize] == 0;
        Some((j, if sea { -km } else { km }))
    }
}

/// One person at the start, before spawning.
pub struct Seed {
    pub home: u32,
    pub stand: u8,
}

/// Places people on the grid: rural people from HYDE (rural200), city people
/// from Hanson 117, at least MIN_PER_PLACE per place. Rounding is stochastic
/// but deterministic (hash of the cell).
pub fn populate(inp: &Inputs, seed: u64) -> (Grid, Vec<Seed>, Vec<u32>) {
    let (mut r0, mut r1, mut c0, mut c1) = (i32::MAX, i32::MIN, i32::MAX, i32::MIN);
    for &(r, c) in inp.cells.keys() {
        r0 = r0.min(r);
        r1 = r1.max(r);
        c0 = c0.min(c);
        c1 = c1.max(c);
    }
    let (rows, cols) = (r1 - r0 + 1, c1 - c0 + 1);
    let mut grid = Grid {
        row0: r0,
        col0: c0,
        rows,
        cols,
        kind: vec![0; (rows * cols) as usize],
    };
    for (&(r, c), cell) in &inp.cells {
        let i = grid.index(r, c).unwrap() as usize;
        grid.kind[i] = if cell.land_km2 > 0.9 * 625.0 { 2 } else { 1 };
    }
    let mut cells: Vec<_> = inp.cells.iter().collect();
    cells.sort_by_key(|(rc, _)| **rc);
    let mut people = Vec::new();
    // Stochastic rounding with a hash of (seed, salt) as the coin.
    let round = |x: f64, salt: u64| -> u32 {
        let whole = x.floor();
        let frac = ((x - whole) * 65536.0) as u64;
        whole as u32 + u32::from((xxh3_64(&(salt ^ seed).to_le_bytes()) & 0xffff) < frac)
    };
    for (&(r, c), cell) in &cells {
        let rural = cell.hyde.as_ref().and_then(|h| h.rural).unwrap_or(0.0);
        let n = round(
            rural / PEOPLE_PER_PERSON,
            ((r as u64) << 32) ^ (c as u32 as u64),
        );
        let home = grid.index(r, c).unwrap();
        people.extend((0..n).map(|_| Seed { home, stand: 0 }));
    }
    let mut places = Vec::new();
    for (k, city) in inp.cities.iter().enumerate() {
        let (r, c) = (
            (city.z_m / CELL_M).floor() as i32,
            (city.x_m / CELL_M).floor() as i32,
        );
        let Some(home) = grid.index(r, c) else {
            continue;
        };
        let n = round(city.pop / PEOPLE_PER_PERSON, 0x5eed_0000_0000 ^ k as u64).max(MIN_PER_PLACE);
        places.push(home);
        people.extend((0..n).map(|_| Seed { home, stand: 1 }));
    }
    (grid, people, places)
}

#[derive(Resource)]
pub struct Clock {
    pub day: i64,
    pub seed: u64,
}

#[derive(Resource, Default)]
pub struct Fields {
    /// Flow field per destination cell (every listed place).
    pub map: FxHashMap<u32, Vec<u8>>,
    pub build_ms: f64,
}

/// Time per part, summed over the run (µs).
#[derive(Default, Clone, Copy, Debug)]
pub struct Timing {
    pub needs: f64,
    pub travel: f64,
    pub index: f64,
    pub relations: f64,
    pub trips: f64,
    pub jobs: f64,
    pub pops: f64,
}

/// Pops as a derived layer (S61): every person belongs to the pop
/// (100 km region, estate, culture, religion), to an economic
/// group (job) and a political group; counts are rebuilt from the people.
#[derive(Default)]
pub struct Groups {
    pub pops: FxHashMap<(u32, u8, u16, u16), u32>,
    pub economic: [u32; JOBS as usize],
    pub political: FxHashMap<u16, u32>,
}

pub struct People {
    pub world: World,
    pub grid: Grid,
    pub places: Vec<u32>,
    pub count: u32,
    /// Traits by person id, refreshed monthly for relation updates.
    traits: Vec<u32>,
    /// Person ids by home cell (sorted), refreshed monthly.
    by_cell: FxHashMap<u32, Vec<u32>>,
    pub timing: Timing,
    pub groups: Groups,
}

impl People {
    pub fn new(inp: &Inputs, seed: u64) -> People {
        bevy_tasks::ComputeTaskPool::get_or_init(bevy_tasks::TaskPool::default);
        let (grid, seeds, places) = populate(inp, seed);
        let mut world = World::new();
        world.insert_resource(Clock { day: 0, seed });

        let mut by_cell: FxHashMap<u32, Vec<u32>> = FxHashMap::default();
        for (pid, s) in seeds.iter().enumerate() {
            by_cell.entry(s.home).or_default().push(pid as u32);
        }
        let batch: Vec<_> = seeds
            .iter()
            .enumerate()
            .map(|(pid, s)| {
                let pid = pid as u32;
                let r = |salt| rnd(seed, pid, salt, 0);
                let mates = &by_cell[&s.home];
                let me = mates.binary_search(&pid).unwrap();
                // Household: blocks of five neighbours in the cell list.
                let hh = me / 5 * 5;
                let mut rel = Relations {
                    n: 0,
                    ids: [0; MAX_REL],
                    opinion: [0; MAX_REL],
                };
                for &o in &mates[hh..(hh + 5).min(mates.len())] {
                    if o != pid {
                        rel.ids[rel.n as usize] = o;
                        rel.opinion[rel.n as usize] = 50;
                        rel.n += 1;
                    }
                }
                for k in 0..20u32 {
                    if (rel.n as usize) >= MAX_REL || mates.len() < 2 {
                        break;
                    }
                    let o = mates[(r(100 + k) % mates.len() as u64) as usize];
                    if o != pid && !rel.ids[..rel.n as usize].contains(&o) {
                        rel.ids[rel.n as usize] = o;
                        rel.n += 1;
                    }
                }
                (
                    Pid(pid),
                    Born(-((r(1) % (60 * 365)) as i32)),
                    Sex((r(2) & 1) as u8),
                    Household(mates[hh]),
                    Home(s.home),
                    Job((r(3) % JOBS as u64) as u8),
                    Traits(r(4) as u32),
                    Health(800 + (r(5) % 200) as u16),
                    (
                        Stand(s.stand),
                        Needs([30000; NEEDS]),
                        rel,
                        Culture((s.home % 192 / 16) as u16),
                        Religion((s.home / 192 / 40) as u16),
                        Faction((r(6) % 8) as u16),
                    ),
                )
            })
            .collect();
        world.spawn_batch(batch);
        let count = seeds.len() as u32;
        let t0 = std::time::Instant::now();
        let mut dests = places.clone();
        dests.sort_unstable();
        dests.dedup();
        let grid_ref = &grid;
        let built: Vec<(u32, Vec<u8>)> = bevy_tasks::ComputeTaskPool::get()
            .scope(|s| {
                for chunk in dests.chunks(dests.len().div_ceil(16).max(1)) {
                    s.spawn(async move {
                        chunk
                            .iter()
                            .map(|&d| (d, grid_ref.flow_field(d)))
                            .collect::<Vec<_>>()
                    });
                }
            })
            .into_iter()
            .flatten()
            .collect();
        world.insert_resource(Fields {
            map: built.into_iter().collect(),
            build_ms: t0.elapsed().as_secs_f64() * 1e3,
        });
        let mut p = People {
            world,
            grid,
            places,
            count,
            traits: Vec::new(),
            by_cell,
            timing: Timing::default(),
            groups: Groups::default(),
        };
        p.refresh_index();
        p
    }

    fn refresh_index(&mut self) {
        self.traits.resize(self.count as usize, 0);
        let mut q = self.world.query::<(&Pid, &Traits)>();
        for (pid, t) in q.iter(&self.world) {
            self.traits[pid.0 as usize] = t.0;
        }
        self.by_cell.clear();
        let mut q = self.world.query::<(&Pid, &Home)>();
        for (pid, h) in q.iter(&self.world) {
            self.by_cell.entry(h.0).or_default().push(pid.0);
        }
        for v in self.by_cell.values_mut() {
            v.sort_unstable();
        }
    }

    /// One day. Returns which periodic parts ran (month, year).
    pub fn day(&mut self) -> (bool, bool) {
        let day = self.world.resource::<Clock>().day + 1;
        self.world.resource_mut::<Clock>().day = day;
        let t = std::time::Instant::now;
        let us = |t0: std::time::Instant| t0.elapsed().as_secs_f64() * 1e6;
        let t0 = t();
        self.daily_needs();
        self.timing.needs += us(t0);
        let t0 = t();
        self.daily_travel();
        self.timing.travel += us(t0);
        let month = (day as u64).is_multiple_of(30);
        let year = (day as u64).is_multiple_of(360);
        if month {
            let t0 = t();
            self.refresh_index();
            self.timing.index += us(t0);
            let t0 = t();
            self.monthly_relations();
            self.timing.relations += us(t0);
            let t0 = t();
            self.monthly_trips();
            self.timing.trips += us(t0);
            let t0 = t();
            self.monthly_groups();
            self.timing.pops += us(t0);
        }
        if year {
            let t0 = t();
            self.yearly_jobs();
            self.timing.jobs += us(t0);
        }
        (month, year)
    }

    fn daily_needs(&mut self) {
        let (seed, day) = {
            let c = self.world.resource::<Clock>();
            (c.seed, c.day)
        };
        let mut q = self
            .world
            .query::<(&Pid, &Job, &Traits, &mut Needs, &mut Health)>();
        q.contiguous_par_iter_mut(&mut self.world)
            .expect("people live in tables")
            .for_each(|(pid, job, tr, needs, health)| {
                let (needs, _) = ContiguousMut::split(needs);
                let (health, _) = ContiguousMut::split(health);
                for i in 0..pid.len() {
                    let r = rnd(seed, pid[i].0, 7, day);
                    let n = &mut needs[i].0;
                    for (k, v) in n.iter_mut().enumerate() {
                        let decay = 300 + ((tr[i].0 >> (k * 4)) & 0xf) as u16 * 20;
                        let gain = if (job[i].0 as usize + k) % 3 == 0 {
                            400
                        } else {
                            200
                        } + ((r >> (k * 8)) & 0xff) as u16;
                        *v = v.saturating_sub(decay).saturating_add(gain).min(60000);
                    }
                    let low = n.iter().filter(|&&v| v < 10000).count() as u16;
                    let h = &mut health[i].0;
                    *h = (*h + 1).saturating_sub(low).min(1000);
                }
            });
    }

    fn daily_travel(&mut self) {
        let fields = std::mem::take(&mut self.world.resource_mut::<Fields>().map);
        let grid = &self.grid;
        let mut done = Vec::new();
        let mut q = self.world.query::<(Entity, &Pid, &mut Travel, &Home)>();
        for (e, pid, mut t, home) in q.iter_mut(&mut self.world) {
            let mut budget = 1.0f32;
            while budget > 0.0 {
                let step = if t.back {
                    let Some(&prev) = t.path.last() else { break };
                    grid.leg(t.at, prev)
                } else {
                    if t.at == t.to {
                        t.back = true;
                        continue;
                    }
                    match grid.next(&fields[&t.to], t.at) {
                        Some(s) => s,
                        None => {
                            t.back = true;
                            continue;
                        }
                    }
                };
                let (cell, km) = step;
                let (len, speed) = if km < 0 { (-km, SEA_KM_DAY) } else { (km, LAND_KM_DAY) };
                let left = len - t.km;
                let can = (budget * speed as f32) as i32;
                if can >= left {
                    budget -= left as f32 / speed as f32;
                    t.km = 0;
                    if t.back {
                        t.path.pop();
                    } else {
                        let at = t.at;
                        t.path.push(at);
                    }
                    t.at = cell;
                } else {
                    t.km += can;
                    budget = 0.0;
                }
            }
            if t.back && t.at == home.0 {
                done.push((pid.0, e));
            }
        }
        self.world.resource_mut::<Fields>().map = fields;
        done.sort_unstable_by_key(|d| d.0);
        for (_, e) in done {
            self.world.entity_mut(e).remove::<Travel>();
        }
    }

    fn monthly_relations(&mut self) {
        let (seed, day) = {
            let c = self.world.resource::<Clock>();
            (c.seed, c.day)
        };
        let traits = &self.traits;
        let by_cell = &self.by_cell;
        let mut q = self.world.query::<(&Pid, &Home, &Traits, &mut Relations)>();
        q.contiguous_par_iter_mut(&mut self.world)
            .expect("people live in tables")
            .for_each(|(pid, home, tr, rel)| {
                let (rel, _) = ContiguousMut::split(rel);
                for i in 0..pid.len() {
                    let rel = &mut rel[i];
                    let mine = tr[i].0;
                    let mut weakest = (i8::MAX, usize::MAX);
                    for k in 0..rel.n as usize {
                        let other = traits[rel.ids[k] as usize];
                        let same = (!(mine ^ other)).count_ones() as i32 - 16;
                        let o = (rel.opinion[k] as i32 + same / 4).clamp(-100, 100);
                        rel.opinion[k] = o as i8;
                        if (o as i8) < weakest.0 {
                            weakest = (o as i8, k);
                        }
                    }
                    // Meet someone new in the home cell, replacing the weakest tie.
                    let r = rnd(seed, pid[i].0, 11, day);
                    if let Some(mates) = by_cell.get(&home[i].0) {
                        let o = mates[(r % mates.len() as u64) as usize];
                        if o != pid[i].0 && !rel.ids[..rel.n as usize].contains(&o) {
                            let k = if (rel.n as usize) < MAX_REL {
                                rel.n += 1;
                                rel.n as usize - 1
                            } else {
                                weakest.1
                            };
                            rel.ids[k] = o;
                            rel.opinion[k] = 0;
                        }
                    }
                }
            });
    }

    fn monthly_trips(&mut self) {
        let (seed, day) = {
            let c = self.world.resource::<Clock>();
            (c.seed, c.day)
        };
        let mut start = Vec::new();
        let mut q = self
            .world
            .query_filtered::<(Entity, &Pid, &Home), Without<Travel>>();
        for (e, pid, home) in q.iter(&self.world) {
            let r = rnd(seed, pid.0, 13, day);
            if r % 10_000 < TRIPS_PER_10K_MONTH {
                let to = self.places[((r >> 20) % self.places.len() as u64) as usize];
                if to != home.0 {
                    start.push((pid.0, e, home.0, to));
                }
            }
        }
        start.sort_unstable_by_key(|s| s.0);
        for (_, e, _, to) in start {
            let from = self.world.get::<Home>(e).unwrap().0;
            self.world.entity_mut(e).insert(Travel { to, at: from, km: 0, back: false, path: Vec::new() });
        }
    }

    fn monthly_groups(&mut self) {
        let grid = &self.grid;
        let g = &mut self.groups;
        g.pops.clear();
        g.economic = [0; JOBS as usize];
        g.political.clear();
        let mut q = self
            .world
            .query::<(&Home, &Stand, &Culture, &Religion, &Job, &Faction)>();
        for (h, st, cu, re, job, fa) in q.iter(&self.world) {
            *g.pops.entry((grid.region(h.0), st.0, cu.0, re.0)).or_default() += 1;
            g.economic[job.0 as usize] += 1;
            *g.political.entry(fa.0).or_default() += 1;
        }
    }

    fn yearly_jobs(&mut self) {
        let (seed, day) = {
            let c = self.world.resource::<Clock>();
            (c.seed, c.day)
        };
        let mut q = self
            .world
            .query::<(&Pid, &Traits, &Needs, &Health, &mut Job)>();
        q.contiguous_par_iter_mut(&mut self.world)
            .expect("people live in tables")
            .for_each(|(pid, tr, needs, health, job)| {
                let (job, _) = ContiguousMut::split(job);
                for i in 0..pid.len() {
                    let mut best = (i64::MIN, job[i].0);
                    for cand in 0..JOBS {
                        let fit = ((tr[i].0 >> (cand as u32 * 2)) & 0xff) as i64;
                        let need = needs[i].0[cand as usize % NEEDS] as i64 / 1000;
                        let noise = (rnd(seed, pid[i].0, 17 + cand as u32, day) & 0x3f) as i64;
                        let stay = if cand == job[i].0 { 40 } else { 0 };
                        let score = fit - need + noise + stay + health[i].0 as i64 / 100;
                        if score > best.0 {
                            best = (score, cand);
                        }
                    }
                    job[i].0 = best.1;
                }
            });
    }

    pub fn travelling(&mut self) -> usize {
        self.world.query::<&Travel>().iter(&self.world).count()
    }

    /// Hash of every person's state in id order.
    pub fn fingerprint(&mut self) -> u64 {
        let mut rows: Vec<(u32, [u64; 6])> = Vec::with_capacity(self.count as usize);
        let mut q = self.world.query::<(
            &Pid,
            &Home,
            &Job,
            &Health,
            &Needs,
            &Relations,
            Option<&Travel>,
        )>();
        for (pid, home, job, health, needs, rel, t) in q.iter(&self.world) {
            let n = needs.0;
            let mut h = 0u64;
            for k in 0..rel.n as usize {
                h = h.rotate_left(5) ^ ((rel.ids[k] as u64) << 8 | rel.opinion[k] as u8 as u64);
            }
            let t = t.map_or(0, |t| (t.to as u64) << 40 | (t.at as u64) << 20 ^ t.km as u32 as u64 ^ (t.back as u64) << 63 ^ t.path.len() as u64);
            rows.push((
                pid.0,
                [
                    home.0 as u64,
                    (job.0 as u64) << 16 | health.0 as u64,
                    (n[0] as u64) << 48 | (n[1] as u64) << 32 | (n[2] as u64) << 16 | n[3] as u64,
                    h,
                    t,
                    rel.n as u64,
                ],
            ));
        }
        rows.sort_unstable_by_key(|r| r.0);
        let bytes: Vec<u8> = rows
            .iter()
            .flat_map(|(p, v)| {
                p.to_le_bytes()
                    .into_iter()
                    .chain(v.iter().flat_map(|x| x.to_le_bytes()))
            })
            .collect();
        xxh3_64(&bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// Same seed, same state after two months, independent of iteration order.
    #[test]
    fn deterministic_fingerprint() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let run = || {
            let mut p = People::new(&inp, 7);
            for _ in 0..60 {
                p.day();
            }
            (p.count, p.fingerprint())
        };
        let a = run();
        assert!(a.0 > 50_000);
        assert_eq!(a, run());
    }
}
