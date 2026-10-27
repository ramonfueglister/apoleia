//! Prototype for individually simulated people (decisions S50–S67,
//! docs/kit2/SCALE.md, docs/kit2/run-people/README.md).
//!
//! Population rules follow the decisions: children only from couples (S62),
//! marriage arranged by the family with a search radius by estate (S63),
//! death from a model life table plus health (S64), food and living space
//! as an emergent brake (S65), households in need move or leave the map
//! (S66). Values the decisions leave open are marked `PLACEHOLDER` and are
//! not game rules. Needs, trips and the yearly job choice are load
//! placeholders as before.
//!
//! Performance: births and deaths run from an event calendar (crate::life),
//! so a day only touches the people with an event that day. Everything that
//! runs monthly or yearly per person is spread over the days by person id
//! (staggering, as CK2 2.6 did with its year end), so no day carries a
//! whole month of work.
//!
//! Determinism: every random draw is a hash of (seed, person, salt, day),
//! and every structural change runs serially in person id order, so the
//! result does not depend on thread count or iteration order.

use crate::groups::{self, Groups};
use crate::inputs::Inputs;
use crate::life::{self, Calendar, Ev, BIRTH, DEATH, YEAR};
use bevy_ecs::change_detection::ContiguousMut;
use bevy_ecs::prelude::*;
use bevy_ecs::query::Has;
use bevy_utils::Parallel;
use rustc_hash::FxHashMap;
use std::cmp::Reverse;
use std::collections::BinaryHeap;
use xxhash_rust::xxh3::xxh3_64;

/// Real people per simulated person (S50).
pub const PEOPLE_PER_PERSON: f64 = 566.5;
/// Minimum inhabitants of a listed place (S57).
pub const MIN_PER_PLACE: u32 = 2;
/// Fixed population cap (S59). What happens there (S67) is not built yet.
pub const CAP: u32 = 200_000;
/// No person (spouse, parent).
pub const NONE: u32 = u32::MAX;
/// Size of the path-search grid cell in real metres (the 25 km cells).
const CELL_M: f64 = 25_000.0;
pub const MAX_REL: usize = 30;
const NEEDS: usize = 4;
const MONTH: i64 = 30;
/// Placeholder travel speeds in real km per day: on foot and by ship.
const LAND_KM_DAY: i32 = 30;
const SEA_KM_DAY: i32 = 100;
/// Placeholder: share of people starting a trip each month, per 10,000.
const TRIPS_PER_10K_MONTH: u64 = 30;
/// HYDE rural population is taken as this share of the food capacity K, as
/// in the tile model (Params::start_fill).
const START_FILL: f64 = 0.7;

/// Estates in the prototype. Senators and equites are placed by S58 (40 and
/// about 60); decurions are not separated yet.
pub const RURAL: u8 = 0;
pub const CITY: u8 = 1;
pub const EQUES: u8 = 2;
pub const SENATOR: u8 = 3;
const SENATORS: usize = 40;
const EQUITES: usize = 60;

// PLACEHOLDER values for what S63–S66 leave open. Ages after Saller (first
// marriage: commoner women late teens, men late 20s; elite earlier).
/// Age from which a family looks for a spouse: (women, men) by estate.
const MARRY_AGE: [(f64, f64); 4] = [(15.0, 20.0), (15.0, 20.0), (13.0, 20.0), (13.0, 20.0)];
/// S79: a household with nobody of working age moves in with the nearest
/// relative. PLACEHOLDER ages (the decision names 15–60) and order of kin:
/// parent, child, sibling, uncle or aunt; within a degree the lowest id.
const WORK_AGE: (f64, f64) = (15.0, 60.0);
/// S80: from this share of the cap (S59) on, emigration rises softly.
const CAP_SOFT: f64 = 0.9;
/// S80 PLACEHOLDER: share of households a year that leave at the cap, the
/// worst fed first (in between it rises linearly from 0 at CAP_SOFT).
const CAP_LEAVE_PER_YEAR: f64 = 0.03;
/// S82 PROPOSAL (Ramon to decide, off until then): partners further apart
/// than this many IQ points are not considered. Calibrated so that new
/// couples correlate at about life::IQ_MATE_R (30 gives r = 0.44 over 10
/// years, ~19,500 marriages); inheritance then uses life::IQ_MATE_RG.
pub const IQ_MATE_GAP_PROPOSED: f64 = 30.0;
/// Inheritance at the father's death (S83). INHERIT_EQUAL, the default:
/// the father's family farm is shared in equal parts between the old
/// household and the married sons' new households (Roman intestate
/// succession, Twelve Tables V.4, Gaius Inst. 3.1–8; no primogeniture,
/// Saller 1994). For comparison runs: INHERIT_NOW, the farm stays with the
/// old household and the sons start landless; INHERIT_ONE, the eldest
/// married son stays in the household with the farm.
pub const INHERIT_NOW: u8 = 0;
pub const INHERIT_EQUAL: u8 = 1;
pub const INHERIT_ONE: u8 = 2;
/// Women are not sought after this age.
const MARRY_AGE_MAX_F: f64 = 45.0;
/// Preferred age gap husband − wife in years (Saller: about 10).
const PREF_GAP: f64 = 10.0;
/// Months without a match before the search widens (S63 "mehrere Monate").
const WIDEN_MONTHS: u8 = 6;
/// Without free land in the cell a marriage goes ahead with this chance
/// per month (S65: later marriage), otherwise the family waits.
const NO_LAND_MARRY_PER_16: u64 = 4;
/// Minimum time from a birth to the next (pregnancy plus nursing), years.
/// The fertility rate is raised so the yearly rate of the table holds.
const BIRTH_GAP: f64 = 1.25;
/// Pregnancy, years: the earliest first birth after a marriage.
const PREGNANCY: f64 = 0.75;
/// Death of the mother per birth (pre-modern order of magnitude).
const MATERNAL_DEATH_PER_10K: u64 = 100;
/// Health multiplies the death hazard by 1 + HUNGER_DEATH × (1 − h) and
/// the birth hazard by h (h = health / 1000).
const HUNGER_DEATH: f64 = 2.0;
/// Health moves this fraction of the way to its target each month.
const HEALTH_STEP: i32 = 3;

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
/// Day of birth.
#[derive(Component, Clone, Copy)]
pub struct Born(pub i32);
/// 0 = female, 1 = male.
#[derive(Component, Clone, Copy)]
pub struct Sex(pub u8);
#[derive(Component, Clone, Copy)]
pub struct Household(pub u32);
#[derive(Component, Clone, Copy)]
pub struct Home(pub u32);
/// Occupation, one of the 13 of S77 (crate::groups); the economic group.
#[derive(Component, Clone, Copy)]
pub struct Job(pub u8);
#[derive(Component, Clone, Copy)]
pub struct Traits(pub u32);
/// Intelligence (Ramon, 27.10.2026): standardized genetic value and
/// environment, each N(0, 1) in steps of 1/4096; the IQ follows from age
/// (crate::life::iq). Inherited additively, does nothing yet.
#[derive(Component, Clone, Copy)]
pub struct Intelligence {
    pub gene: i16,
    pub env: i16,
}

impl Intelligence {
    const STEP: f64 = 4096.0;

    fn from(gene: f64, env: f64) -> Intelligence {
        let q = |x: f64| (x * Self::STEP).round().clamp(i16::MIN as f64, i16::MAX as f64) as i16;
        Intelligence { gene: q(gene), env: q(env) }
    }

    pub fn gene(&self) -> f64 {
        self.gene as f64 / Self::STEP
    }

    pub fn iq(&self, age: f64) -> f64 {
        life::iq(self.gene(), self.env as f64 / Self::STEP, age)
    }
}

/// 0–1000; driven by food (S64, S65).
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
/// Political groups the person belongs to, a bit mask over the 8 groups of
/// S77 (crate::groups): one or more (S61).
#[derive(Component, Clone, Copy)]
pub struct Faction(pub u8);
#[derive(Component, Clone, Copy)]
pub struct Needs(pub [u16; NEEDS]);
#[derive(Component, Clone, Copy)]
pub struct Relations {
    pub n: u8,
    pub ids: [u32; MAX_REL],
    pub opinion: [i8; MAX_REL],
}
#[derive(Component, Clone, Copy)]
pub struct Spouse(pub u32);
/// Father and mother (NONE for the start population).
#[derive(Component, Clone, Copy)]
pub struct Parents(pub u32, pub u32);
/// Generation of the scheduled death and birth events.
#[derive(Component, Clone, Copy, Default)]
pub struct Sched {
    pub death: u16,
    pub birth: u16,
}
/// Months the family has searched a spouse without success.
#[derive(Component, Clone, Copy, Default)]
pub struct Search(pub u8);
/// A trip in progress. Round trips go there and back home: the way there
/// comes from the destination's flow field, the way back retraces the cells
/// walked. Emigrants (`leave`) follow the field to the map edge and are gone
/// when they reach it (S66).
#[derive(Component, Clone)]
pub struct Travel {
    pub to: u32,
    pub at: u32,
    pub km: i32,
    pub back: bool,
    pub leave: bool,
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

    /// The region and its eight neighbours.
    pub fn regions_around(region: u32) -> [u32; 9] {
        let (r, c) = (region >> 16, region & 0xffff);
        let mut out = [0; 9];
        let mut k = 0;
        for dr in [0u32, 1, 2] {
            for dc in [0u32, 1, 2] {
                out[k] = (r + dr - 1) << 16 | (c + dc - 1);
                k += 1;
            }
        }
        out.swap(0, 4);
        out
    }

    /// Dijkstra from `sources` over the whole grid (costs are symmetric): for
    /// every cell the direction (0–7) of the next step towards the nearest
    /// source, 255 at a source or where none can be reached. One field per
    /// destination serves every trip there (flow field).
    pub fn flow_field_from(&self, sources: &[u32]) -> Vec<u8> {
        let n = self.kind.len();
        let mut best = vec![i32::MAX; n];
        let mut dir = vec![255u8; n];
        let mut open = BinaryHeap::new();
        for &s in sources {
            best[s as usize] = 0;
            open.push(Reverse((0, s)));
        }
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

    pub fn flow_field(&self, to: u32) -> Vec<u8> {
        self.flow_field_from(&[to])
    }

    /// The field to the nearest cell on the edge of the map (S66).
    pub fn edge_field(&self) -> Vec<u8> {
        let mut edge = Vec::new();
        for r in 0..self.rows {
            for c in 0..self.cols {
                if r == 0 || c == 0 || r == self.rows - 1 || c == self.cols - 1 {
                    edge.push((r * self.cols + c) as u32);
                }
            }
        }
        self.flow_field_from(&edge)
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
/// but deterministic (hash of the cell). Also returns the listed places and
/// the food capacity K of every cell in simulated people (HYDE rural / 0.7
/// plus the cities, which import grain), the source of food in S65.
pub fn populate(inp: &Inputs, seed: u64) -> (Grid, Vec<Seed>, Vec<u32>, Vec<f32>) {
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
    let mut food = vec![0f32; grid.kind.len()];
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
        let n = round(rural / PEOPLE_PER_PERSON, ((r as u64) << 32) ^ (c as u32 as u64));
        let home = grid.index(r, c).unwrap();
        food[home as usize] += (rural / START_FILL / PEOPLE_PER_PERSON) as f32;
        people.extend((0..n).map(|_| Seed { home, stand: RURAL }));
    }
    let mut places = Vec::new();
    for (k, city) in inp.cities.iter().enumerate() {
        let (r, c) = ((city.z_m / CELL_M).floor() as i32, (city.x_m / CELL_M).floor() as i32);
        let Some(home) = grid.index(r, c) else {
            continue;
        };
        let n = round(city.pop / PEOPLE_PER_PERSON, 0x5eed_0000_0000 ^ k as u64).max(MIN_PER_PLACE);
        food[home as usize] += (city.pop / PEOPLE_PER_PERSON) as f32;
        places.push(home);
        people.extend((0..n).map(|_| Seed { home, stand: CITY }));
    }
    (grid, people, places, food)
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
    /// Flow field to the map edge (emigrants).
    pub edge: Vec<u8>,
    pub build_ms: f64,
}

/// Food from the grain economy (crate::grain, S69–S76). When set, it
/// replaces the capacity K of S35: health follows what each household ate,
/// marriage waits where the region has no free land, and households in need
/// compare regions by the food they offer per head.
pub struct Econ {
    /// Permille of its need a household ate last month, by household id.
    pub fed: Vec<u16>,
    /// Per region key: (food per head, free land, cell to move to).
    pub region: FxHashMap<u32, (f32, bool, u32)>,
    /// Below this a household is in need (S66).
    pub need_fed: u16,
}

/// Time per part, summed over the run (µs).
#[derive(Default, Clone, Copy, Debug)]
pub struct Timing {
    pub events: f64,
    pub needs: f64,
    pub travel: f64,
    pub health: f64,
    pub marriage: f64,
    pub relations: f64,
    pub trips: f64,
    pub index: f64,
    pub pops: f64,
    pub jobs: f64,
    pub migration: f64,
}

/// Named causes of death (S64). War, accidents, murder and plague come later.
pub const CAUSES: [&str; 4] = ["Krankheit", "Alter", "Hunger", "Geburt"];

/// Counters, reset by the caller when it wants yearly figures.
#[derive(Default, Clone, Copy, Debug)]
pub struct Stats {
    pub births: u64,
    pub deaths: [u64; 4],
    pub deaths_under1: u64,
    pub age_at_death_sum: f64,
    pub marriages: u64,
    pub marry_age_f: f64,
    pub marry_age_m: f64,
    pub waited_for_land: u64,
    pub moved_households: u64,
    pub moved_people: u64,
    pub left_households: u64,
    pub left_people: u64,
    pub left_map: u64,
    /// Households with nobody of working age that joined a relative (S79).
    pub joined_households: u64,
    pub joined_people: u64,
    /// New households of married sons after the father's death (S81).
    pub split_households: u64,
    pub split_people: u64,
    /// IQ of the partners at marriage: n, Σx, Σy, Σx², Σy², Σxy (S82).
    pub marry_iq: [f64; 6],
    /// The same for the partners' genetic values.
    pub marry_gene: [f64; 6],
}

fn corr([n, sx, sy, sxx, syy, sxy]: [f64; 6]) -> f64 {
    let cov = sxy / n - sx / n * sy / n;
    cov / ((sxx / n - (sx / n).powi(2)) * (syy / n - (sy / n).powi(2))).sqrt()
}

impl Stats {
    /// Correlation of the partners' IQ at marriage.
    pub fn marry_iq_r(&self) -> f64 {
        corr(self.marry_iq)
    }

    /// Correlation of the partners' genetic values at marriage.
    pub fn marry_gene_r(&self) -> f64 {
        corr(self.marry_gene)
    }

    /// Adds another period's partner sums.
    pub fn add_marry(&mut self, o: &Stats) {
        for k in 0..6 {
            self.marry_iq[k] += o.marry_iq[k];
            self.marry_gene[k] += o.marry_gene[k];
        }
    }
}

/// Person ids grouped by a key (compressed rows): ids of key k are
/// ids[start[k]..start[k + 1]], ascending.
#[derive(Default)]
pub struct Csr {
    pub start: Vec<u32>,
    pub ids: Vec<u32>,
}

impl Csr {
    /// Counting sort; `pairs` in id order keep that order within a key.
    fn counting(keys: usize, pairs: &[(u32, u32)]) -> Csr {
        let mut start = vec![0u32; keys + 1];
        for &(k, _) in pairs {
            start[k as usize + 1] += 1;
        }
        for k in 0..keys {
            start[k + 1] += start[k];
        }
        let mut fill = start.clone();
        let mut ids = vec![0u32; pairs.len()];
        for &(k, id) in pairs {
            ids[fill[k as usize] as usize] = id;
            fill[k as usize] += 1;
        }
        Csr { start, ids }
    }

    #[cfg(test)]
    fn build(keys: usize, mut pairs: Vec<(u32, u32)>) -> Csr {
        pairs.sort_unstable();
        let mut start = vec![0u32; keys + 1];
        for &(k, _) in &pairs {
            start[k as usize + 1] += 1;
        }
        for k in 0..keys {
            start[k + 1] += start[k];
        }
        Csr { start, ids: pairs.into_iter().map(|p| p.1).collect() }
    }
    pub fn get(&self, k: u32) -> &[u32] {
        let k = k as usize;
        if k + 1 >= self.start.len() {
            return &[];
        }
        &self.ids[self.start[k] as usize..self.start[k + 1] as usize]
    }
}

/// Stable LSD radix sort by a u32 key below `max`, 11 bits per pass (the
/// counters stay in L1), two passes for up to 4 million person ids. Linear
/// in the number of living people, where an array indexed by person id
/// would grow with everyone ever born.
fn radix_sort<T: Copy>(v: &mut Vec<T>, max: u32, key: impl Fn(&T) -> u32) {
    const BITS: u32 = 11;
    const MASK: u32 = (1 << BITS) - 1;
    let mut tmp = v.clone();
    let mut count = [0usize; (1 << BITS) + 1];
    let mut shift = 0;
    loop {
        count.fill(0);
        for x in v.iter() {
            count[((key(x) >> shift) & MASK) as usize + 1] += 1;
        }
        for d in 0..1 << BITS {
            count[d + 1] += count[d];
        }
        for x in v.iter() {
            let d = ((key(x) >> shift) & MASK) as usize;
            tmp[count[d]] = *x;
            count[d] += 1;
        }
        std::mem::swap(v, &mut tmp);
        shift += BITS;
        if shift >= 32 || max >> shift == 0 {
            break;
        }
    }
}

/// One living person in the monthly index snapshot.
#[derive(Clone, Copy)]
struct IndexRow {
    pid: u32,
    home: u32,
    /// 100 km region, only for brides.
    region: u32,
    flags: u8,
    stand: u8,
}

/// The monthly lists for marriage and relations, built from a snapshot.
struct Index {
    grooms: Vec<Vec<u32>>,
    brides: FxHashMap<(u32, u8), Vec<u32>>,
    brides_by_stand: [Vec<u32>; 4],
    by_cell: Csr,
}

impl Index {
    /// Everything in person id order, as the marriage search expects.
    fn build(mut rows: Vec<IndexRow>, max_pid: u32, cells: usize) -> Index {
        radix_sort(&mut rows, max_pid, |r| r.pid);
        let mut i = Index { grooms: vec![Vec::new(); MONTH as usize], brides: FxHashMap::default(), brides_by_stand: Default::default(), by_cell: Csr::default() };
        let mut by_cell = Vec::with_capacity(rows.len());
        for r in &rows {
            if r.home == NONE {
                continue;
            }
            by_cell.push((r.home, r.pid));
            if r.flags & 1 != 0 {
                i.grooms[r.pid as usize % MONTH as usize].push(r.pid);
            }
            if r.flags & 2 != 0 {
                i.brides.entry((r.region, r.stand)).or_default().push(r.pid);
                if r.stand >= CITY {
                    i.brides_by_stand[r.stand as usize].push(r.pid);
                }
            }
        }
        i.by_cell = Csr::counting(cells, &by_cell);
        i
    }
}

/// Monthly households: (household, person) grouped by household, persons in
/// id order, and the households by yearly slice (household id mod 360).
type HouseholdLists = (Vec<(u32, u32)>, Vec<Vec<(u32, u32)>>);

fn households(mut pairs: Vec<(u32, u32)>, max_pid: u32) -> HouseholdLists {
    radix_sort(&mut pairs, max_pid, |p| p.1);
    radix_sort(&mut pairs, max_pid, |p| p.0);
    let mut slices = vec![Vec::new(); YEAR as usize];
    let mut i = 0;
    while i < pairs.len() {
        let h = pairs[i].0;
        let mut j = i + 1;
        while j < pairs.len() && pairs[j].0 == h {
            j += 1;
        }
        slices[(h % YEAR as u32) as usize].push((i as u32, j as u32));
        i = j;
    }
    (pairs, slices)
}

/// (parent, child) of the living children, grouped by parent (S79); the
/// search takes the lowest id itself, so the order within a parent does
/// not matter.
fn kids(rows: Vec<(u32, u32, u32)>, max_pid: u32) -> Vec<(u32, u32)> {
    let mut kids: Vec<(u32, u32)> = Vec::with_capacity(rows.len() * 2);
    for (c, f, m) in rows {
        for p in [f, m] {
            if p != NONE {
                kids.push((p, c));
            }
        }
    }
    radix_sort(&mut kids, max_pid, |k| k.0);
    kids
}

pub struct People {
    pub world: World,
    pub grid: Grid,
    pub places: Vec<u32>,
    /// People alive.
    pub count: u32,
    pub peak: u32,
    next_pid: u32,
    /// Entity by person id; PLACEHOLDER once the person is gone.
    ent: Vec<Entity>,
    /// Traits by person id (kept for the dead too, for old relations).
    traits: Vec<u32>,
    /// Father and mother by person id (kept for the dead too, to find
    /// uncles and aunts, S79).
    parents: Vec<(u32, u32)>,
    /// (parent, child) of the living children, rebuilt monthly (S79).
    kids: Vec<(u32, u32)>,
    /// Fathers who died since the last split, with their household (S81).
    splits: Vec<(u32, u32)>,
    /// INHERIT_EQUAL (default), INHERIT_NOW or INHERIT_ONE (S83).
    pub inherit: u8,
    /// With the grain economy and INHERIT_EQUAL: (old household, new
    /// household of a son) for each split since crate::grain took them.
    pub split_log: Vec<(u32, u32)>,
    /// Largest IQ gap between partners (infinite: no choice by IQ) and the
    /// partners' genetic correlation inheritance assumes (S82).
    pub iq_mate_gap: f64,
    pub iq_mate_rg: f64,
    /// Person ids by home cell, rebuilt monthly.
    by_cell: Csr,
    /// (household, person) sorted, rebuilt monthly.
    households: Vec<(u32, u32)>,
    /// Single men of age by id mod 30 and households (ranges into
    /// `households`) by id mod 360, rebuilt monthly in id order.
    grooms: Vec<Vec<u32>>,
    hh_slices: Vec<Vec<(u32, u32)>>,
    /// Single women looking for a husband by (region, estate), and by
    /// estate empire-wide for the elite search; rebuilt monthly.
    brides: FxHashMap<(u32, u8), Vec<u32>>,
    brides_by_stand: [Vec<u32>; 4],
    /// Land cells by region (for the move search, S66).
    region_cells: FxHashMap<u32, Vec<u32>>,
    /// Food capacity K and people per cell, in simulated people.
    pub food: Vec<f32>,
    pub pop: Vec<u32>,
    /// Food is shared within a region through its market (S70), so food per
    /// person is counted per region: dense region index per cell (NONE at
    /// sea), region key, food and people per region.
    cell_region: Vec<u32>,
    region_key: Vec<u32>,
    region_index: FxHashMap<u32, u32>,
    pub region_food: Vec<f32>,
    pub region_pop: Vec<u32>,
    cal: Calendar,
    pub timing: Timing,
    pub stats: Stats,
    pub groups: Groups,
    census: groups::Census,
    /// Monthly index and households being built in the background.
    index_job: Option<std::thread::JoinHandle<Index>>,
    households_job: Option<std::thread::JoinHandle<HouseholdLists>>,
    kids_job: Option<std::thread::JoinHandle<Vec<(u32, u32)>>>,
    /// Set by the grain economy; None keeps the capacity K of S35.
    pub econ: Option<Econ>,
}

/// The rows of a table of `len` handled on day `slice` of `parts`: work
/// that runs once a month (or year) per person is spread over the days by
/// table position, so it stays contiguous. Rows move when people are added
/// or removed, so over a period someone may be handled twice or skipped;
/// fine for slow quantities, and deterministic.
fn part(len: usize, slice: u32, parts: i64) -> std::ops::Range<usize> {
    let (s, p) = (slice as usize, parts as usize);
    len * s / p..len * (s + 1) / p
}

fn age_y(day: i64, born: i32) -> f64 {
    (day - born as i64) as f64 / YEAR as f64
}

fn mu(sex: u8) -> &'static [f64; 21] {
    if sex == 0 {
        &life::MU_F
    } else {
        &life::MU_M
    }
}

fn death_mult(health: u16) -> f64 {
    1.0 + HUNGER_DEATH * (1.0 - health as f64 / 1000.0)
}

/// Fertility rate per year raised so that with a gap of BIRTH_GAP after
/// each birth the mean yearly rate stays that of the table: r / (1 − r·gap).
fn fert_adjusted() -> [f64; 8] {
    let mut out = [0.0; 8];
    for (o, &r) in out.iter_mut().zip(life::FERT.iter()) {
        *o = r / (1.0 - r * BIRTH_GAP);
    }
    out
}

impl People {
    pub fn new(inp: &Inputs, seed: u64) -> People {
        People::with_iq_mate_gap(inp, seed, f64::INFINITY)
    }

    /// As `new`, with partners at most `iq_mate_gap` IQ points apart
    /// (calibration, IQ_MATE_GAP_PROPOSED).
    pub fn with_iq_mate_gap(inp: &Inputs, seed: u64, iq_mate_gap: f64) -> People {
        bevy_tasks::ComputeTaskPool::get_or_init(bevy_tasks::TaskPool::default);
        let (grid, mut seeds, places, food) = populate(inp, seed);
        let mut world = World::new();
        world.insert_resource(Clock { day: 0, seed });

        // Elite (S58): 40 senators in the largest place, about 60 equites in
        // the next largest places, both men of 25–60.
        let mut city_order: Vec<(u32, u32)> = Vec::new();
        {
            let mut n: FxHashMap<u32, u32> = FxHashMap::default();
            for s in seeds.iter().filter(|s| s.stand == CITY) {
                *n.entry(s.home).or_default() += 1;
            }
            city_order.extend(n.into_iter().map(|(c, k)| (k, c)));
            city_order.sort_unstable_by_key(|&(k, c)| (Reverse(k), c));
        }
        let born: Vec<(u8, i32)> = (0..seeds.len() as u32)
            .map(|pid| {
                let sex = (rnd(seed, pid, 2, 0) & 1) as u8;
                let a = life::stable_age(mu(sex), life::unit(rnd(seed, pid, 1, 0)));
                (sex, -((a * YEAR as f64) as i32))
            })
            .collect();
        let mut want = [(SENATOR, SENATORS), (EQUES, EQUITES)];
        for (ci, &(_, cell)) in city_order.iter().enumerate() {
            for w in want.iter_mut() {
                if w.1 == 0 || (w.0 == SENATOR && ci > 0) || (w.0 == EQUES && ci == 0) {
                    continue;
                }
                let mut taken = 0;
                for (pid, s) in seeds.iter_mut().enumerate() {
                    let (sex, b) = born[pid];
                    let a = -b as f64 / YEAR as f64;
                    if s.home == cell && s.stand == CITY && sex == 1 && (25.0..60.0).contains(&a) {
                        s.stand = w.0;
                        w.1 -= 1;
                        taken += 1;
                        // Equites: a few per large city.
                        if w.1 == 0 || (w.0 == EQUES && taken == 3) {
                            break;
                        }
                    }
                }
            }
        }

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
                let mut rel = Relations { n: 0, ids: [0; MAX_REL], opinion: [0; MAX_REL] };
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
                let (sex, b) = born[pid as usize];
                let job = groups::start_job(s.stand, r(3));
                (
                    (Pid(pid), Born(b), Sex(sex), Household(mates[hh]), Home(s.home), Job(job)),
                    (Traits(r(4) as u32), Health(1000), Stand(s.stand), Needs([30000; NEEDS]), rel, Intelligence::from(life::normal(life::unit(r(5))), life::normal(life::unit(r(6))))),
                    (
                        Culture((s.home % 192 / 16) as u16),
                        Religion((s.home / 192 / 40) as u16),
                        Faction(groups::membership(job)),
                        Spouse(NONE),
                        Parents(NONE, NONE),
                        Sched::default(),
                        Search(0),
                    ),
                )
            })
            .collect();
        // Reserve table rows up to the cap (S59), so later births never
        // regrow the tables (a regrow copies every column, 50–80 ms).
        let spare = (CAP as usize).saturating_sub(batch.len());
        let template = batch[0];
        let ent: Vec<Entity> = world.spawn_batch(batch).collect();
        let dummies: Vec<Entity> = world.spawn_batch(std::iter::repeat_n(template, spare)).collect();
        for e in dummies {
            world.despawn(e);
        }
        let count = seeds.len() as u32;
        let t0 = std::time::Instant::now();
        let mut dests = places.clone();
        dests.sort_unstable();
        dests.dedup();
        let grid_ref = &grid;
        let built: Vec<(u32, Vec<u8>)> = bevy_tasks::ComputeTaskPool::get()
            .scope(|s| {
                for chunk in dests.chunks(dests.len().div_ceil(16).max(1)) {
                    s.spawn(async move { chunk.iter().map(|&d| (d, grid_ref.flow_field(d))).collect::<Vec<_>>() });
                }
            })
            .into_iter()
            .flatten()
            .collect();
        let edge = grid.edge_field();
        world.insert_resource(Fields { map: built.into_iter().collect(), edge, build_ms: t0.elapsed().as_secs_f64() * 1e3 });
        let mut region_cells: FxHashMap<u32, Vec<u32>> = FxHashMap::default();
        for i in 0..grid.kind.len() as u32 {
            if grid.kind[i as usize] != 0 {
                region_cells.entry(grid.region(i)).or_default().push(i);
            }
        }
        let mut pop = vec![0u32; grid.kind.len()];
        for s in &seeds {
            pop[s.home as usize] += 1;
        }
        let mut cell_region = vec![NONE; grid.kind.len()];
        let mut region_key: Vec<u32> = region_cells.keys().copied().collect();
        region_key.sort_unstable();
        let region_index: FxHashMap<u32, u32> = region_key.iter().enumerate().map(|(i, &k)| (k, i as u32)).collect();
        let mut region_food = vec![0f32; region_key.len()];
        let mut region_pop = vec![0u32; region_key.len()];
        for (&k, cells) in &region_cells {
            for &c in cells {
                cell_region[c as usize] = region_index[&k];
            }
        }
        for c in 0..grid.kind.len() {
            if cell_region[c] != NONE {
                region_food[cell_region[c] as usize] += food[c];
                region_pop[cell_region[c] as usize] += pop[c];
            }
        }
        let mut p = People {
            cell_region,
            region_key,
            region_index,
            region_food,
            region_pop,
            world,
            grid,
            places,
            count,
            peak: count,
            next_pid: count,
            ent,
            traits: Vec::new(),
            parents: Vec::new(),
            kids: Vec::new(),
            splits: Vec::new(),
            inherit: INHERIT_EQUAL,
            split_log: Vec::new(),
            iq_mate_gap,
            iq_mate_rg: if iq_mate_gap.is_finite() { life::IQ_MATE_RG } else { 0.0 },
            by_cell: Csr::default(),
            households: Vec::new(),
            grooms: Vec::new(),
            hh_slices: Vec::new(),
            brides: FxHashMap::default(),
            brides_by_stand: Default::default(),
            region_cells,
            food,
            pop,
            cal: Calendar::new(0),
            timing: Timing::default(),
            stats: Stats::default(),
            groups: Groups::default(),
            census: groups::Census::default(),
            index_job: None,
            households_job: None,
            kids_job: None,
            econ: None,
        };
        let mut q = p.world.query::<&Traits>();
        p.traits = q.iter(&p.world).map(|t| t.0).collect();
        p.parents = vec![(NONE, NONE); p.next_pid as usize];
        // Marriages at the start: let the families search for a year.
        for m in 0..12 {
            p.refresh_index();
            p.marriages(None, -12 + m);
        }
        p.stats = Stats::default();
        // First death and birth for everyone.
        let mut q = p.world.query::<(&Pid, &Born, &Sex, &Spouse, &Health, &Sched)>();
        let mut first: Vec<_> = q.iter(&p.world).map(|(a, b, c, d, e, f)| (a.0, b.0, c.0, d.0, e.0, *f)).collect();
        first.sort_unstable_by_key(|f| f.0);
        for (pid, born, sex, spouse, health, sched) in first {
            p.schedule_death(pid, sched.death, born, sex, health, 0);
            if sex == 0 && spouse != NONE {
                p.schedule_birth(pid, sched.birth, born, health, 0, PREGNANCY);
            }
        }
        p.refresh_index();
        p.refresh_households();
        p
    }

    fn seed(&self) -> u64 {
        self.world.resource::<Clock>().seed
    }

    fn schedule_death(&mut self, pid: u32, gen: u16, born: i32, sex: u8, health: u16, day: i64) {
        let h = rnd(self.seed(), pid, 0xdead ^ (gen as u32) << 8, day);
        let w = life::wait(&life::AGES, mu(sex), age_y(day, born), death_mult(health), h).unwrap_or(100.0);
        let at = day + ((w * YEAR as f64) as i64).max(1);
        self.cal.push(at, Ev { kind: DEATH, pid, gen });
    }

    /// Next birth for a married woman, at the earliest `gap` years from now.
    fn schedule_birth(&mut self, pid: u32, gen: u16, born: i32, health: u16, day: i64, gap: f64) {
        let h = rnd(self.seed(), pid, 0xb127 ^ (gen as u32) << 8, day);
        let rates = fert_adjusted();
        let age = age_y(day, born) + gap;
        if let Some(w) = life::wait(&life::FERT_AGES, &rates, age, health as f64 / 1000.0, h) {
            let at = day + (((gap + w) * YEAR as f64) as i64).max(1);
            self.cal.push(at, Ev { kind: BIRTH, pid, gen });
        }
    }

    /// Add `d` people to a cell (and its region).
    fn add_pop(&mut self, cell: u32, d: i32) {
        let c = cell as usize;
        self.pop[c] = (self.pop[c] as i32 + d) as u32;
        let r = self.cell_region[c];
        if r != NONE {
            self.region_pop[r as usize] = (self.region_pop[r as usize] as i32 + d) as u32;
        }
    }

    /// Food per person in the region of `cell` with `add` more people.
    fn share(&self, cell: u32, add: u32) -> f64 {
        match self.cell_region[cell as usize] {
            NONE => 0.0,
            r => self.region_food[r as usize] as f64 / (self.region_pop[r as usize] + add).max(1) as f64,
        }
    }

    pub fn is_alive(&self, pid: u32) -> bool {
        self.alive(pid).is_some()
    }

    /// One more than the highest person id so far (household ids are
    /// person ids).
    pub fn next_pid(&self) -> u32 {
        self.next_pid
    }

    /// Moves the members of a household at home to another cell (a
    /// landless household taking a free farm, S69). The members come from
    /// the caller's count the day before; someone who joined since (born
    /// or married in that day) stays behind.
    pub fn relocate_household(&mut self, house: u32, members: &[u32], cell: u32) {
        for &pid in members {
            let Some(e) = self.alive(pid) else { continue };
            if self.world.get::<Household>(e).unwrap().0 != house || self.world.get::<Travel>(e).is_some() {
                continue;
            }
            let old = self.world.get::<Home>(e).unwrap().0;
            self.add_pop(old, -1);
            self.add_pop(cell, 1);
            self.world.get_mut::<Home>(e).unwrap().0 = cell;
        }
    }

    /// Whether a household counts as in need (S66): it ate too little
    /// (grain economy), else the region's food per person is below 1.
    fn in_need(&self, house: u32, home: u32) -> bool {
        match &self.econ {
            Some(e) => e.fed.get(house as usize).is_some_and(|&f| f < e.need_fed),
            None => self.share(home, 0) < 1.0,
        }
    }

    /// S65: without free land the family waits with the marriage.
    fn no_land(&self, home: u32) -> bool {
        match &self.econ {
            Some(e) => !e.region.get(&self.grid.region(home)).is_some_and(|r| r.1),
            None => self.share(home, 0) <= 1.0,
        }
    }

    fn alive(&self, pid: u32) -> Option<Entity> {
        self.ent.get(pid as usize).copied().filter(|&e| e != Entity::PLACEHOLDER)
    }

    /// Monthly rebuild of the lookups: one parallel pass over the people,
    /// then one pass in id order (counting sort, no comparison sort).
    /// Snapshot for the monthly index: per living person id, home, region,
    /// flags (1 groom, 2 bride) and estate. One parallel pass.
    fn index_rows(&mut self) -> Vec<IndexRow> {
        let day = self.world.resource::<Clock>().day;
        let grid = &self.grid;
        let mut parts: Parallel<Vec<IndexRow>> = Parallel::default();
        let mut q = self.world.query::<(&Pid, &Home, &Born, &Sex, &Stand, &Spouse, Has<Travel>)>();
        q.par_iter(&self.world).for_each_init(
            || parts.borrow_local_mut(),
            |out, (pid, h, b, sex, st, sp, travel)| {
                let a = age_y(day, b.0);
                let single = sp.0 == NONE && !travel;
                let mut f = 0;
                if single && sex.0 == 1 && a >= MARRY_AGE[st.0 as usize].1 {
                    f |= 1;
                }
                if single && sex.0 == 0 && a >= MARRY_AGE[st.0 as usize].0 && a < MARRY_AGE_MAX_F {
                    f |= 2;
                }
                let region = if f & 2 != 0 && h.0 != NONE { grid.region(h.0) } else { 0 };
                out.push(IndexRow { pid: pid.0, home: h.0, region, flags: f, stand: st.0 });
            },
        );
        let mut rows = Vec::with_capacity(self.count as usize);
        parts.drain_into(&mut rows);
        rows
    }

    /// Rebuilds the monthly index at once (start of the game).
    fn refresh_index(&mut self) {
        let rows = self.index_rows();
        let built = Index::build(rows, self.next_pid, self.grid.kind.len());
        self.install_index(built);
    }

    /// Monthly index in the background: the snapshot is taken now, the
    /// lists are built on another thread while the next day starts, and
    /// installed before the marriages of that day, the first to read them.
    /// The lists are the same as when built at once.
    fn start_index(&mut self) {
        let rows = self.index_rows();
        let (max, cells) = (self.next_pid, self.grid.kind.len());
        self.index_job = Some(std::thread::spawn(move || Index::build(rows, max, cells)));
    }

    fn finish_index(&mut self) {
        if let Some(job) = self.index_job.take() {
            let built = job.join().expect("index thread");
            self.install_index(built);
        }
    }

    fn install_index(&mut self, i: Index) {
        self.grooms = i.grooms;
        self.brides = i.brides;
        self.brides_by_stand = i.brides_by_stand;
        self.by_cell = i.by_cell;
    }

    /// Snapshot of (household, person) of the living.
    fn household_pairs(&mut self) -> Vec<(u32, u32)> {
        let mut pairs: Vec<(u32, u32)> = Vec::with_capacity(self.count as usize);
        let mut q = self.world.query::<(&Pid, &Household)>();
        for (pid, h) in q.contiguous_iter(&self.world).expect("people live in tables") {
            pairs.extend((0..pid.len()).filter(|&i| h[i].0 != NONE).map(|i| (h[i].0, pid[i].0)));
        }
        pairs
    }

    /// Snapshot of (person, father, mother) of the living.
    fn kid_rows(&mut self) -> Vec<(u32, u32, u32)> {
        let mut rows = Vec::with_capacity(self.count as usize);
        let mut q = self.world.query::<(&Pid, &Parents)>();
        for (pid, pa) in q.contiguous_iter(&self.world).expect("people live in tables") {
            rows.extend((0..pid.len()).map(|i| (pid[i].0, pa[i].0, pa[i].1)));
        }
        rows
    }

    /// Children by parent, monthly in the background on its own day (S79);
    /// installed before the migration of the next day, its only reader.
    fn start_kids(&mut self) {
        let rows = self.kid_rows();
        let max = self.next_pid;
        self.kids_job = Some(std::thread::spawn(move || kids(rows, max)));
    }

    fn finish_kids(&mut self) {
        if let Some(job) = self.kids_job.take() {
            self.kids = job.join().expect("kids thread");
        }
    }

    /// Households and their yearly slices, rebuilt monthly on another day
    /// than the index so the work does not pile up (at once at the start).
    fn refresh_households(&mut self) {
        let pairs = self.household_pairs();
        (self.households, self.hh_slices) = households(pairs, self.next_pid);
        let rows = self.kid_rows();
        self.kids = kids(rows, self.next_pid);
    }

    /// Monthly households in the background, like the index; installed
    /// before the migration of the next day, the first to read them.
    fn start_households(&mut self) {
        let pairs = self.household_pairs();
        let max = self.next_pid;
        self.households_job = Some(std::thread::spawn(move || households(pairs, max)));
    }

    fn finish_households(&mut self) {
        if let Some(job) = self.households_job.take() {
            (self.households, self.hh_slices) = job.join().expect("households thread");
        }
    }

    /// One day. Returns which periodic parts ran (month, year).
    pub fn day(&mut self) -> (bool, bool) {
        let day = self.world.resource::<Clock>().day + 1;
        self.world.resource_mut::<Clock>().day = day;
        let t = std::time::Instant::now;
        let us = |t0: std::time::Instant| t0.elapsed().as_secs_f64() * 1e6;
        let slice = day.rem_euclid(MONTH) as u32;
        let yslice = day.rem_euclid(YEAR) as u32;

        let t0 = t();
        self.events(day);
        self.timing.events += us(t0);
        let t0 = t();
        self.daily_needs();
        self.timing.needs += us(t0);
        let t0 = t();
        self.daily_travel();
        self.timing.travel += us(t0);
        let t0 = t();
        self.health(day, slice);
        self.timing.health += us(t0);
        let t0 = t();
        self.finish_index();
        self.timing.index += us(t0);
        let t0 = t();
        self.marriages(Some(slice), day);
        self.timing.marriage += us(t0);
        let t0 = t();
        self.relations(day, slice);
        self.timing.relations += us(t0);
        let t0 = t();
        self.trips(day, slice);
        self.timing.trips += us(t0);
        let t0 = t();
        self.finish_households();
        self.finish_kids();
        self.timing.index += us(t0);
        let t0 = t();
        self.migration(day, yslice);
        if slice == 11 {
            self.split_households();
        }
        self.timing.migration += us(t0);
        let month = slice == 0;
        if month {
            let t0 = t();
            self.start_index();
            self.timing.index += us(t0);
        }
        if slice == 10 {
            let t0 = t();
            self.start_households();
            self.timing.index += us(t0);
        }
        if slice == 20 {
            let t0 = t();
            self.start_kids();
            self.timing.index += us(t0);
        }
        let t0 = t();
        self.monthly_groups(slice);
        self.timing.pops += us(t0);
        self.peak = self.peak.max(self.count);
        // Removal and change trackers grow without bound unless cleared
        // once per tick (a Bevy app does this every frame).
        self.world.clear_trackers();
        (month, yslice == 0)
    }

    /// Births and deaths due today, in (kind, person) order.
    fn events(&mut self, day: i64) {
        for ev in self.cal.take(day) {
            let Some(e) = self.alive(ev.pid) else { continue };
            let sched = *self.world.get::<Sched>(e).unwrap();
            match ev.kind {
                DEATH if sched.death == ev.gen => {
                    let h = self.world.get::<Health>(e).unwrap().0;
                    let born = self.world.get::<Born>(e).unwrap().0;
                    let a = age_y(day, born);
                    let m = death_mult(h);
                    let u = life::unit(rnd(self.seed(), ev.pid, 0xca05e, day));
                    let cause = if u < (m - 1.0) / m {
                        2
                    } else if a >= 60.0 {
                        1
                    } else {
                        0
                    };
                    self.die(ev.pid, day, cause);
                }
                BIRTH if sched.birth == ev.gen => self.birth(ev.pid, e, day),
                _ => {}
            }
        }
    }

    fn die(&mut self, pid: u32, day: i64, cause: usize) {
        let e = self.ent[pid as usize];
        let born = self.world.get::<Born>(e).unwrap().0;
        let home = self.world.get::<Home>(e).unwrap().0;
        let spouse = self.world.get::<Spouse>(e).unwrap().0;
        let leaving = self.world.get::<Travel>(e).is_some_and(|t| t.leave);
        if !leaving && self.world.get::<Sex>(e).unwrap().0 == 1 {
            self.splits.push((pid, self.world.get::<Household>(e).unwrap().0));
        }
        let a = age_y(day, born);
        self.stats.deaths[cause] += 1;
        self.stats.age_at_death_sum += a;
        if a < 1.0 {
            self.stats.deaths_under1 += 1;
        }
        if let Some(se) = self.alive(spouse) {
            self.world.get_mut::<Spouse>(se).unwrap().0 = NONE;
            // A widow's next birth is void.
            self.world.get_mut::<Sched>(se).unwrap().birth += 1;
        }
        if !leaving {
            self.add_pop(home, -1);
        }
        self.world.despawn(e);
        self.ent[pid as usize] = Entity::PLACEHOLDER;
        self.count -= 1;
    }

    fn birth(&mut self, mother: u32, me: Entity, day: i64) {
        let father = self.world.get::<Spouse>(me).unwrap().0;
        let Some(fe) = self.alive(father) else { return };
        let seed = self.seed();
        let pid = self.next_pid;
        self.next_pid += 1;
        let r = |salt| rnd(seed, pid, salt, day);
        let m_home = self.world.get::<Home>(me).unwrap().0;
        let m_house = self.world.get::<Household>(me).unwrap().0;
        let travel = self.world.get::<Travel>(me).filter(|t| t.leave).cloned();
        let f = (
            *self.world.get::<Stand>(fe).unwrap(),
            *self.world.get::<Culture>(fe).unwrap(),
            *self.world.get::<Religion>(fe).unwrap(),
            *self.world.get::<Faction>(fe).unwrap(),
            *self.world.get::<Job>(fe).unwrap(),
        );
        let mask = r(1) as u32;
        let traits = ((self.traits[father as usize] & mask) | (self.traits[mother as usize] & !mask)) ^ (1 << (r(2) % 32));
        let sex = (r(3) & 1) as u8;
        let gene = life::child_gene_rg(self.world.get::<Intelligence>(fe).unwrap().gene(), self.world.get::<Intelligence>(me).unwrap().gene(), life::normal(life::unit(r(5))), self.iq_mate_rg);
        let mind = Intelligence::from(gene, life::normal(life::unit(r(6))));
        let mut rel = Relations { n: 2, ids: [0; MAX_REL], opinion: [0; MAX_REL] };
        rel.ids[0] = mother;
        rel.ids[1] = father;
        rel.opinion[0] = 80;
        rel.opinion[1] = 80;
        let mut ec = self.world.spawn((
            // PLACEHOLDER (open): a child takes the father's occupation and
            // political groups, as it takes his estate.
            (Pid(pid), Born(day as i32), Sex(sex), Household(m_house), Home(m_home), f.4),
            (Traits(traits), Health(1000), f.0, Needs([30000; NEEDS]), rel, mind),
            (f.1, f.2, f.3, Spouse(NONE), Parents(father, mother), Sched::default(), Search(0)),
        ));
        let leaving = travel.is_some();
        if let Some(t) = travel {
            ec.insert(t);
        }
        let e = ec.id();
        if !leaving {
            self.add_pop(m_home, 1);
        }
        self.ent.push(e);
        self.traits.push(traits);
        self.parents.push((father, mother));
        self.count += 1;
        self.stats.births += 1;
        self.schedule_death(pid, 0, day as i32, sex, 1000, day);
        // The mother may die in childbirth (S64).
        if rnd(seed, mother, 0xb0b, day) % 10_000 < MATERNAL_DEATH_PER_10K {
            self.die(mother, day, 3);
            return;
        }
        let (born, health) = (self.world.get::<Born>(me).unwrap().0, self.world.get::<Health>(me).unwrap().0);
        let gen = {
            let mut s = self.world.get_mut::<Sched>(me).unwrap();
            s.birth += 1;
            s.birth
        };
        self.schedule_birth(mother, gen, born, health, day, BIRTH_GAP);
    }

    /// Health follows the food share of the home cell (S65). When it crosses
    /// a band of 100 the death and birth draws are redone (S64).
    /// Health follows the food share of the home cell (S65). When it crosses
    /// a band of 100 the death and birth draws are redone (S64). Runs on the
    /// day's 1/30 of every table, so each person about once a month.
    fn health(&mut self, day: i64, slice: u32) {
        let mut redo = Vec::new();
        let (food, pop, region) = (&self.region_food, &self.region_pop, &self.cell_region);
        let fed = self.econ.as_ref().map(|e| &e.fed);
        let mut q = self.world.query_filtered::<(&Pid, &Home, &Household, &Born, &Sex, &Spouse, &mut Health, &mut Sched), Without<Travel>>();
        for (pid, home, house, born, sex, spouse, health, sched) in q.contiguous_iter_mut(&mut self.world).expect("people live in tables") {
            let (health, _) = ContiguousMut::split(health);
            let (sched, _) = ContiguousMut::split(sched);
            for i in part(pid.len(), slice, MONTH) {
                let share = match fed {
                    // Grain economy: what the household ate.
                    Some(f) => f.get(house[i].0 as usize).map_or(1.0, |&v| v as f64 / 1000.0),
                    None => {
                        let r = region[home[i].0 as usize] as usize;
                        food[r] as f64 / pop[r].max(1) as f64
                    }
                };
                let target = (1000.0 * share.min(1.0)) as i32;
                let h = health[i].0 as i32;
                let new = (h + (target - h) / HEALTH_STEP) as u16;
                if new / 100 != health[i].0 / 100 {
                    sched[i].death += 1;
                    let birth = sex[i].0 == 0 && spouse[i].0 != NONE;
                    if birth {
                        sched[i].birth += 1;
                    }
                    redo.push((pid[i].0, born[i].0, sex[i].0, new, sched[i], birth));
                }
                health[i].0 = new;
            }
        }
        redo.sort_unstable_by_key(|r| r.0);
        for (pid, born, sex, h, s, birth) in redo {
            self.schedule_death(pid, s.death, born, sex, h, day);
            if birth {
                self.schedule_birth(pid, s.birth, born, h, day, 0.0);
            }
        }
    }

    fn marriages(&mut self, slice: Option<u32>, day: i64) {
        let seed = self.seed();
        let grooms: Vec<u32> = match slice {
            Some(s) => std::mem::take(&mut self.grooms[s as usize]),
            None => {
                let mut all: Vec<u32> = self.grooms.iter().flatten().copied().collect();
                all.sort_unstable();
                all
            }
        };
        let mut cands: Vec<u32> = Vec::new();
        for g in grooms {
            // The list is from the start of the month: skip who has died,
            // married or left since.
            let Some(ge) = self.alive(g) else { continue };
            if self.world.get::<Spouse>(ge).unwrap().0 != NONE || self.world.get::<Travel>(ge).is_some() {
                continue;
            }
            let (home, born, stand, culture, religion, parents, search, rel, house) = (
                self.world.get::<Home>(ge).unwrap().0,
                self.world.get::<Born>(ge).unwrap().0,
                self.world.get::<Stand>(ge).unwrap().0,
                self.world.get::<Culture>(ge).unwrap().0,
                self.world.get::<Religion>(ge).unwrap().0,
                *self.world.get::<Parents>(ge).unwrap(),
                self.world.get::<Search>(ge).unwrap().0,
                *self.world.get::<Relations>(ge).unwrap(),
                self.world.get::<Household>(ge).unwrap().0,
            );
            // S65: without free land the family waits.
            if self.no_land(home)
                && rnd(seed, g, 0x1a2d, day) % 16 >= NO_LAND_MARRY_PER_16
            {
                self.stats.waited_for_land += 1;
                continue;
            }
            cands.clear();
            // Acquaintances of the groom and his father.
            cands.extend_from_slice(&rel.ids[..rel.n as usize]);
            if let Some(fe) = self.alive(parents.0) {
                let fr = self.world.get::<Relations>(fe).unwrap();
                cands.extend_from_slice(&fr.ids[..fr.n as usize]);
            }
            let region = self.grid.region(home);
            if stand >= EQUES {
                // Elite: empire-wide among their own estate, then one below.
                cands.extend_from_slice(&self.brides_by_stand[stand as usize]);
                if search >= WIDEN_MONTHS {
                    cands.extend_from_slice(&self.brides_by_stand[stand as usize - 1]);
                }
            } else {
                let around = Grid::regions_around(region);
                let n = if search >= WIDEN_MONTHS { 9 } else { 1 };
                for &r in &around[..n] {
                    if let Some(v) = self.brides.get(&(r, stand)) {
                        cands.extend_from_slice(v);
                    }
                }
            }
            cands.sort_unstable();
            cands.dedup();
            let ga = age_y(day, born);
            let g_iq = self.world.get::<Intelligence>(ge).unwrap().iq(ga);
            let mut best: Option<(i64, u32)> = None;
            for &c in &cands {
                let Some(ce) = self.alive(c) else { continue };
                let w = (
                    self.world.get::<Sex>(ce).unwrap().0,
                    self.world.get::<Spouse>(ce).unwrap().0,
                    self.world.get::<Born>(ce).unwrap().0,
                    self.world.get::<Stand>(ce).unwrap().0,
                    *self.world.get::<Parents>(ce).unwrap(),
                    self.world.get::<Household>(ce).unwrap().0,
                    self.world.get::<Travel>(ce).is_some(),
                );
                let wa = age_y(day, w.2);
                if w.0 != 0 || w.1 != NONE || w.6 || wa < MARRY_AGE[w.3 as usize].0 || wa >= MARRY_AGE_MAX_F || w.5 == house {
                    continue;
                }
                // No siblings.
                if (parents.0 != NONE && w.4 .0 == parents.0) || (parents.1 != NONE && w.4 .1 == parents.1) {
                    continue;
                }
                // S82: partners of similar intelligence (Horwitz et al. 2023).
                if (g_iq - self.world.get::<Intelligence>(ce).unwrap().iq(wa)).abs() > self.iq_mate_gap {
                    continue;
                }
                // CK3-like weighting, in tenths.
                let mut s = -(((ga - wa) - PREF_GAP).abs() * 10.0) as i64;
                s -= 50 * (stand as i64 - w.3 as i64).abs();
                if self.world.get::<Culture>(ce).unwrap().0 == culture {
                    s += 30;
                }
                if self.world.get::<Religion>(ce).unwrap().0 == religion {
                    s += 30;
                }
                if let Some(k) = rel.ids[..rel.n as usize].iter().position(|&x| x == c) {
                    s += rel.opinion[k] as i64 / 2;
                }
                s += (rnd(seed, g ^ c, 0x5c0e, day) % 20) as i64;
                if best.is_none_or(|b| s > b.0) {
                    best = Some((s, c));
                }
            }
            match best {
                Some((_, b)) => self.marry(g, b, day),
                None => {
                    let mut s = self.world.get_mut::<Search>(ge).unwrap();
                    s.0 = s.0.saturating_add(1);
                }
            }
        }
    }

    /// The bride moves into the groom's household (S63).
    fn marry(&mut self, g: u32, b: u32, day: i64) {
        let (ge, be) = (self.ent[g as usize], self.ent[b as usize]);
        let home = self.world.get::<Home>(ge).unwrap().0;
        let house = self.world.get::<Household>(ge).unwrap().0;
        let stand = self.world.get::<Stand>(ge).unwrap().0;
        let gborn = self.world.get::<Born>(ge).unwrap().0;
        self.world.get_mut::<Spouse>(ge).unwrap().0 = b;
        self.world.get_mut::<Search>(ge).unwrap().0 = 0;
        let old = self.world.get::<Home>(be).unwrap().0;
        self.add_pop(old, -1);
        self.add_pop(home, 1);
        let mut w = self.world.entity_mut(be);
        w.get_mut::<Spouse>().unwrap().0 = g;
        w.get_mut::<Home>().unwrap().0 = home;
        w.get_mut::<Household>().unwrap().0 = house;
        w.get_mut::<Stand>().unwrap().0 = stand;
        let born = w.get::<Born>().unwrap().0;
        let health = w.get::<Health>().unwrap().0;
        let gen = {
            let mut s = w.get_mut::<Sched>().unwrap();
            s.birth += 1;
            s.birth
        };
        self.stats.marriages += 1;
        self.stats.marry_age_f += age_y(day, born);
        self.stats.marry_age_m += age_y(day, gborn);
        let (gi, bi) = (*self.world.get::<Intelligence>(ge).unwrap(), *self.world.get::<Intelligence>(be).unwrap());
        let (x, y) = (gi.iq(age_y(day, gborn)), bi.iq(age_y(day, born)));
        let (u, v) = (gi.gene(), bi.gene());
        for k in 0..6 {
            self.stats.marry_iq[k] += [1.0, x, y, x * x, y * y, x * y][k];
            self.stats.marry_gene[k] += [1.0, u, v, u * u, v * v, u * v][k];
        }
        // Marriages before day 1 (the start) are scheduled in People::new.
        if day > 0 {
            self.schedule_birth(b, gen, born, health, day, PREGNANCY);
        }
    }

    /// Households in need compare their cell with the reachable ones about
    /// once a year and move; with nothing better they leave the map (S66).
    /// PLACEHOLDER: need = food per person in the region below 1; reachable
    /// = the eight neighbouring 100 km regions; better = more food per
    /// person there after moving.
    fn migration(&mut self, day: i64, yslice: u32) {
        let mut moves: Vec<(Vec<u32>, Option<u32>)> = Vec::new();
        let mut joins: Vec<(Vec<u32>, u32)> = Vec::new();
        // S80: near the cap, households in need rather leave than move, and
        // a share of the others leaves too, the worst fed first.
        let seed = self.seed();
        let pressure = ((self.count as f64 / CAP as f64 - CAP_SOFT) / (1.0 - CAP_SOFT)).clamp(0.0, 1.0);
        let leave_instead = |pid: u32| pressure > 0.0 && life::unit(rnd(seed, pid, 0xca9, day)) <= pressure;
        let mut rest: Vec<(u32, u32, Vec<u32>)> = Vec::new();
        let mut checked = 0usize;
        for &(i, j) in &self.hh_slices[yslice as usize] {
            let members: Vec<u32> = self.households[i as usize..j as usize]
                .iter()
                .map(|p| p.1)
                .filter(|&p| self.alive(p).is_some_and(|e| self.world.get::<Travel>(e).is_none() && self.world.get::<Household>(e).unwrap().0 == self.households[i as usize].0))
                .collect();
            let Some(&first) = members.first() else { continue };
            if let Some(to) = self.kin_to_join(&members, day) {
                joins.push((members, to));
                continue;
            }
            let home = self.world.get::<Home>(self.ent[first as usize]).unwrap().0;
            let house = self.households[i as usize].0;
            checked += 1;
            if let Some(e) = &self.econ {
                // Grain economy: a household that ate too little looks for
                // the region around with the most food per head (stores
                // and free land, crate::grain); PLACEHOLDER as below.
                if !self.in_need(house, home) {
                    if pressure > 0.0 {
                        rest.push((e.fed.get(house as usize).map_or(1000, |&f| f as u32), house, members));
                    }
                    continue;
                }
                let own = self.grid.region(home);
                let now = e.region.get(&own).map_or(0.0, |r| r.0);
                let mut best = (now, NONE);
                for k in Grid::regions_around(own) {
                    if let Some(r) = e.region.get(&k) {
                        if k != own && r.0 > best.0 {
                            best = (r.0, r.2);
                        }
                    }
                }
                let to = (best.1 != NONE && !leave_instead(house)).then_some(best.1);
                moves.push((members, to));
                continue;
            }
            let now = self.share(home, 0);
            if now >= 1.0 {
                if pressure > 0.0 {
                    rest.push(((now * 1000.0).min(u32::MAX as f64) as u32, house, members));
                }
            } else {
                // The best region around (food per person once they are
                // there), and in it the cell with the most free food.
                let n = members.len() as u32;
                let own = self.cell_region[home as usize];
                let mut best = (now, NONE);
                for k in Grid::regions_around(self.grid.region(home)) {
                    let Some(&r) = self.region_index.get(&k) else { continue };
                    let s = self.region_food[r as usize] as f64 / (self.region_pop[r as usize] + n) as f64;
                    if r != own && s > best.0 {
                        best = (s, r);
                    }
                }
                let to = (best.1 != NONE && !leave_instead(house)).then(|| {
                    let cells = &self.region_cells[&self.region_key[best.1 as usize]];
                    *cells.iter().max_by(|&&a, &&b| (self.food[a as usize] - self.pop[a as usize] as f32).total_cmp(&(self.food[b as usize] - self.pop[b as usize] as f32)).then(b.cmp(&a))).unwrap()
                });
                moves.push((members, to));
            }
        }
        if pressure > 0.0 {
            // This day's share of the yearly leavers, rounded by chance.
            let want = pressure * CAP_LEAVE_PER_YEAR * checked as f64;
            let k = want as usize + (life::unit(rnd(seed, yslice, 0xca8, day)) <= want.fract()) as usize;
            rest.sort_unstable_by_key(|r| (r.0, r.1));
            for (_, _, members) in rest.into_iter().take(k) {
                moves.push((members, None));
            }
        }
        let at = |p: &Self, pid: u32| p.world.get::<Home>(p.ent[pid as usize]).unwrap().0;
        for (members, kin) in joins {
            // The relative's household and home as of now (S79).
            let Some(ke) = self.alive(kin) else { continue };
            let (house, home) = (self.world.get::<Household>(ke).unwrap().0, self.world.get::<Home>(ke).unwrap().0);
            for &m in &members {
                let old = at(self, m);
                self.add_pop(old, -1);
                self.add_pop(home, 1);
                let mut w = self.world.entity_mut(self.ent[m as usize]);
                w.get_mut::<Home>().unwrap().0 = home;
                w.get_mut::<Household>().unwrap().0 = house;
            }
            self.stats.joined_households += 1;
            self.stats.joined_people += members.len() as u64;
        }
        for (members, to) in moves {
            let n = members.len() as u64;
            match to {
                Some(c) => {
                    for &m in &members {
                        let old = at(self, m);
                        self.add_pop(old, -1);
                        self.add_pop(c, 1);
                        self.world.get_mut::<Home>(self.ent[m as usize]).unwrap().0 = c;
                    }
                    self.stats.moved_households += 1;
                    self.stats.moved_people += n;
                }
                None => {
                    for &m in &members {
                        let old = at(self, m);
                        self.add_pop(old, -1);
                        self.world.entity_mut(self.ent[m as usize]).insert(Travel { to: old, at: old, km: 0, back: false, leave: true, path: Vec::new() });
                    }
                    self.stats.left_households += 1;
                    self.stats.left_people += n;
                }
            }
        }
    }

    /// S79 for the grain economy: nobody alive in `members` is of working
    /// age and `kin_to_join` finds no relative, so the household goes to
    /// the tents (crate::grain).
    pub fn alone_without_workers(&self, members: &[u32]) -> bool {
        let day = self.world.resource::<Clock>().day;
        let alive: Vec<u32> = members.iter().copied().filter(|&m| self.alive(m).is_some()).collect();
        if alive.is_empty() {
            return false;
        }
        let works = alive.iter().any(|&m| (WORK_AGE.0..WORK_AGE.1).contains(&age_y(day, self.world.get::<Born>(self.ent[m as usize]).unwrap().0)));
        !works && self.kin_to_join(&alive, day).is_none()
    }

    /// S81: when a father has died, each of his married sons in the
    /// household founds his own with his wife and his descendants (and their
    /// wives); the widow, the unmarried and everyone else stay. Runs monthly
    /// on the day the household lists are fresh, so a split follows the
    /// death by up to a month. The new household's id is the son's id; it
    /// stays in the same cell. Who inherits the farm: People::inherit
    /// (S83, crate::grain).
    fn split_households(&mut self) {
        let mut splits = std::mem::take(&mut self.splits);
        splits.sort_unstable();
        for (father, house) in splits {
            let lo = self.households.partition_point(|p| p.0 < house);
            let members: Vec<u32> = self.households[lo..]
                .iter()
                .take_while(|p| p.0 == house)
                .map(|p| p.1)
                .filter(|&p| self.alive(p).is_some_and(|e| self.world.get::<Household>(e).unwrap().0 == house))
                .collect();
            let get = |p: &Self, m: u32| {
                let e = p.ent[m as usize];
                (p.world.get::<Parents>(e).unwrap().0, p.world.get::<Sex>(e).unwrap().0, p.world.get::<Spouse>(e).unwrap().0)
            };
            let sons: Vec<u32> = members.iter().copied().filter(|&m| {
                let (f, sex, spouse) = get(self, m);
                f == father && sex == 1 && spouse != NONE
            }).collect();
            // INHERIT_ONE: the eldest (lowest id on the same day) stays.
            let heir = (self.inherit == INHERIT_ONE)
                .then(|| sons.iter().copied().min_by_key(|&s| (self.world.get::<Born>(self.ent[s as usize]).unwrap().0, s)))
                .flatten();
            let mut taken: Vec<u32> = Vec::new();
            for son in sons {
                // A son whose id is already the household's keeps it; the
                // id of another household with people in it is not reused.
                if son == house || taken.contains(&son) || Some(son) == heir {
                    continue;
                }
                let lo2 = self.households.partition_point(|p| p.0 < son);
                if self.households[lo2..].iter().take_while(|p| p.0 == son).any(|p| self.alive(p.1).is_some_and(|e| self.world.get::<Household>(e).unwrap().0 == son)) {
                    continue;
                }
                // The son, then everyone whose father is in the group, and
                // the wives of the men in it.
                let mut group = vec![son];
                loop {
                    let before = group.len();
                    for &m in &members {
                        if group.contains(&m) || taken.contains(&m) {
                            continue;
                        }
                        let (f, _, spouse) = get(self, m);
                        let wife_of = spouse != NONE && get(self, m).1 == 0 && group.contains(&spouse);
                        if group.contains(&f) || wife_of {
                            group.push(m);
                        }
                    }
                    if group.len() == before {
                        break;
                    }
                }
                for &m in &group {
                    self.world.get_mut::<Household>(self.ent[m as usize]).unwrap().0 = son;
                }
                self.stats.split_households += 1;
                self.stats.split_people += group.len() as u64;
                if self.inherit == INHERIT_EQUAL && self.econ.is_some() {
                    self.split_log.push((house, son));
                }
                taken.extend(group);
            }
        }
    }

    /// S79: if nobody in the household is of working age, the nearest
    /// living relative of working age at home in another household, in the
    /// order parent, child, sibling, uncle or aunt (lowest id first within
    /// a degree, members in id order). None if someone can work or there is
    /// no such relative.
    fn kin_to_join(&self, members: &[u32], day: i64) -> Option<u32> {
        let age = |p: u32| age_y(day, self.world.get::<Born>(self.ent[p as usize]).unwrap().0);
        if members.iter().any(|&m| (WORK_AGE.0..WORK_AGE.1).contains(&age(m))) {
            return None;
        }
        let house = self.world.get::<Household>(self.ent[members[0] as usize]).unwrap().0;
        let fit = |p: u32| {
            self.alive(p).is_some_and(|e| {
                self.world.get::<Household>(e).unwrap().0 != house
                    && self.world.get::<Travel>(e).is_none()
                    && (WORK_AGE.0..WORK_AGE.1).contains(&age_y(day, self.world.get::<Born>(e).unwrap().0))
            })
        };
        let kids = |p: u32| {
            let lo = self.kids.partition_point(|k| k.0 < p);
            self.kids[lo..].iter().take_while(move |k| k.0 == p).map(|k| k.1)
        };
        let parents = |p: u32| {
            let (f, m) = self.parents[p as usize];
            [f, m].into_iter().filter(|&x| x != NONE)
        };
        let best = |c: &mut dyn Iterator<Item = u32>| c.filter(|&p| fit(p)).min();
        for &m in members {
            if let Some(k) = best(&mut parents(m)) {
                return Some(k);
            }
        }
        for &m in members {
            if let Some(k) = best(&mut kids(m)) {
                return Some(k);
            }
        }
        for &m in members {
            if let Some(k) = best(&mut parents(m).flat_map(|p| kids(p)).filter(|&s| s != m)) {
                return Some(k);
            }
        }
        for &m in members {
            if let Some(k) = best(&mut parents(m).flat_map(|p| parents(p)).flat_map(|g| kids(g)).filter(|&u| u != self.parents[m as usize].0 && u != self.parents[m as usize].1)) {
                return Some(k);
            }
        }
        None
    }

    fn daily_needs(&mut self) {
        let (seed, day) = {
            let c = self.world.resource::<Clock>();
            (c.seed, c.day)
        };
        let mut q = self.world.query::<(&Pid, &Job, &Traits, &mut Needs)>();
        q.contiguous_par_iter_mut(&mut self.world).expect("people live in tables").for_each(|(pid, job, tr, needs)| {
            let (needs, _) = ContiguousMut::split(needs);
            for i in 0..pid.len() {
                let r = rnd(seed, pid[i].0, 7, day);
                let n = &mut needs[i].0;
                for (k, v) in n.iter_mut().enumerate() {
                    let decay = 300 + ((tr[i].0 >> (k * 4)) & 0xf) as u16 * 20;
                    let gain = if (job[i].0 as usize + k) % 3 == 0 { 400 } else { 200 } + ((r >> (k * 8)) & 0xff) as u16;
                    *v = v.saturating_sub(decay).saturating_add(gain).min(60000);
                }
            }
        });
    }

    fn daily_travel(&mut self) {
        let fields = std::mem::take(&mut *self.world.resource_mut::<Fields>());
        let grid = &self.grid;
        let mut done = Vec::new();
        let mut q = self.world.query::<(Entity, &Pid, &mut Travel, &Home)>();
        for (e, pid, mut t, home) in q.iter_mut(&mut self.world) {
            let mut budget = 1.0f32;
            let mut gone = false;
            while budget > 0.0 {
                let step = if t.leave {
                    match grid.next(&fields.edge, t.at) {
                        Some(s) => s,
                        None => {
                            gone = true;
                            break;
                        }
                    }
                } else if t.back {
                    let Some(&prev) = t.path.last() else { break };
                    grid.leg(t.at, prev)
                } else {
                    if t.at == t.to {
                        t.back = true;
                        continue;
                    }
                    match grid.next(&fields.map[&t.to], t.at) {
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
                    } else if !t.leave {
                        let at = t.at;
                        t.path.push(at);
                    }
                    t.at = cell;
                } else {
                    t.km += can;
                    budget = 0.0;
                }
            }
            if gone {
                done.push((pid.0, e, true));
            } else if t.back && t.at == home.0 {
                done.push((pid.0, e, false));
            }
        }
        *self.world.resource_mut::<Fields>() = fields;
        done.sort_unstable_by_key(|d| d.0);
        for (pid, e, gone) in done {
            if gone {
                // Off the map and out of the system (S66); spouses left behind are widowed.
                let spouse = self.world.get::<Spouse>(e).unwrap().0;
                if let Some(se) = self.alive(spouse) {
                    if self.world.get::<Travel>(se).is_none_or(|t| !t.leave) {
                        self.world.get_mut::<Spouse>(se).unwrap().0 = NONE;
                        self.world.get_mut::<Sched>(se).unwrap().birth += 1;
                    }
                }
                self.world.despawn(e);
                self.ent[pid as usize] = Entity::PLACEHOLDER;
                self.count -= 1;
                self.stats.left_map += 1;
            } else {
                self.world.entity_mut(e).remove::<Travel>();
            }
        }
    }

    fn relations(&mut self, day: i64, slice: u32) {
        let seed = self.seed();
        let traits = &self.traits;
        let by_cell = &self.by_cell;
        let ent = &self.ent;
        let pool = bevy_tasks::ComputeTaskPool::get();
        let mut q = self.world.query::<(&Pid, &Home, &Traits, &mut Relations)>();
        for (pid, home, tr, rel) in q.contiguous_iter_mut(&mut self.world).expect("people live in tables") {
            let (rel, _) = ContiguousMut::split(rel);
            let range = part(pid.len(), slice, MONTH);
            let (pid, home, tr, rel) = (&pid[range.clone()], &home[range.clone()], &tr[range.clone()], &mut rel[range]);
            let chunk = rel.len().div_ceil(pool.thread_num().max(1)).max(256);
            pool.scope(|s| {
                for (c, rel) in rel.chunks_mut(chunk).enumerate() {
                    let o = c * chunk;
                    s.spawn(async move {
                        for (i, rel) in rel.iter_mut().enumerate() {
                            let (pid, home, mine) = (pid[o + i].0, home[o + i].0, tr[o + i].0);
                            let mut weakest = (i8::MAX, usize::MAX);
                            for k in 0..rel.n as usize {
                                let id = rel.ids[k];
                                if ent[id as usize] == Entity::PLACEHOLDER {
                                    weakest = (i8::MIN, k);
                                    continue;
                                }
                                let other = traits[id as usize];
                                let same = (!(mine ^ other)).count_ones() as i32 - 16;
                                let op = (rel.opinion[k] as i32 + same / 4).clamp(-100, 100);
                                rel.opinion[k] = op as i8;
                                if (op as i8) < weakest.0 {
                                    weakest = (op as i8, k);
                                }
                            }
                            // Meet someone new in the home cell, replacing the weakest tie.
                            let r = rnd(seed, pid, 11, day);
                            let mates = by_cell.get(home);
                            if !mates.is_empty() {
                                let other = mates[(r % mates.len() as u64) as usize];
                                if other != pid && ent[other as usize] != Entity::PLACEHOLDER && !rel.ids[..rel.n as usize].contains(&other) {
                                    let k = if (rel.n as usize) < MAX_REL {
                                        rel.n += 1;
                                        rel.n as usize - 1
                                    } else {
                                        weakest.1
                                    };
                                    rel.ids[k] = other;
                                    rel.opinion[k] = 0;
                                }
                            }
                        }
                    });
                }
            });
        }
    }

    fn trips(&mut self, day: i64, slice: u32) {
        let seed = self.seed();
        let mut start = Vec::new();
        let mut q = self.world.query_filtered::<(&Pid, &Home), Without<Travel>>();
        for (pid, home) in q.contiguous_iter(&self.world).expect("people live in tables") {
            for i in part(pid.len(), slice, MONTH) {
                let r = rnd(seed, pid[i].0, 13, day);
                if r % 10_000 < TRIPS_PER_10K_MONTH {
                    let to = self.places[((r >> 20) % self.places.len() as u64) as usize];
                    if to != home[i].0 {
                        start.push((pid[i].0, home[i].0, to));
                    }
                }
            }
        }
        start.sort_unstable_by_key(|s| s.0);
        for (pid, from, to) in start {
            let e = self.ent[pid as usize];
            self.world.entity_mut(e).insert(Travel { to, at: from, km: 0, back: false, leave: false, path: Vec::new() });
        }
    }

    /// Pops, occupations and political groups counted from the people (S61):
    /// a snapshot in mid-month, counted over the following days.
    fn monthly_groups(&mut self, slice: u32) {
        if slice == MONTH as u32 / 2 {
            let grid = &self.grid;
            self.census.start(&mut self.world, &self.cell_region, &self.region_key, |c| grid.region(c));
        } else if let Some(g) = self.census.step() {
            self.groups = g;
        }
    }

    /// Households (as of the last monthly list) and how many of them have
    /// nobody of working age (S79).
    pub fn households_without_workers(&self) -> (u32, u32) {
        let day = self.world.resource::<Clock>().day;
        let (mut all, mut idle) = (0, 0);
        for (h, group) in self.households.chunk_by(|a, b| a.0 == b.0).map(|g| (g[0].0, g)) {
            let alive: Vec<Entity> = group.iter().filter_map(|p| self.alive(p.1)).filter(|&e| self.world.get::<Household>(e).unwrap().0 == h).collect();
            if alive.is_empty() {
                continue;
            }
            all += 1;
            if !alive.iter().any(|&e| (WORK_AGE.0..WORK_AGE.1).contains(&age_y(day, self.world.get::<Born>(e).unwrap().0))) {
                idle += 1;
            }
        }
        (all, idle)
    }

    /// IQ of the living aged 20 and over: mean, SD, share below 70 and
    /// at 130 or above (in %).
    pub fn iq_summary(&mut self) -> (f64, f64, f64, f64) {
        let day = self.world.resource::<Clock>().day;
        let mut q = self.world.query::<(&Born, &Intelligence)>();
        let (mut n, mut s, mut s2, mut lo, mut hi) = (0.0f64, 0.0, 0.0, 0.0, 0.0);
        for (b, m) in q.iter(&self.world) {
            let a = age_y(day, b.0);
            if a < 20.0 {
                continue;
            }
            let x = m.iq(a);
            n += 1.0;
            s += x;
            s2 += x * x;
            lo += (x < 70.0) as u8 as f64;
            hi += (x >= 130.0) as u8 as f64;
        }
        let mean = s / n.max(1.0);
        (mean, (s2 / n.max(1.0) - mean * mean).sqrt(), 100.0 * lo / n.max(1.0), 100.0 * hi / n.max(1.0))
    }

    pub fn travelling(&mut self) -> usize {
        self.world.query::<&Travel>().iter(&self.world).count()
    }

    /// Events waiting in the calendar.
    pub fn scheduled(&self) -> usize {
        self.cal.len
    }

    /// (married women 15–49, all women 15–49, mean health, people in cells
    /// with less food than people).
    pub fn census(&mut self) -> (u32, u32, f64, u32) {
        let day = self.world.resource::<Clock>().day;
        let (mut mw, mut w, mut h, mut n, mut hungry) = (0, 0, 0.0, 0, 0);
        let mut q = self.world.query_filtered::<(&Born, &Sex, &Spouse, &Health, &Home, &Household), Without<Travel>>();
        for (b, s, sp, he, home, house) in q.iter(&self.world) {
            let a = age_y(day, b.0);
            if s.0 == 0 && (15.0..50.0).contains(&a) {
                w += 1;
                if sp.0 != NONE {
                    mw += 1;
                }
            }
            h += he.0 as f64;
            n += 1;
            let poor = match &self.econ {
                Some(_) => self.in_need(house.0, home.0),
                None => self.share(home.0, 0) < 1.0,
            };
            if poor {
                hungry += 1;
            }
        }
        (mw, w, h / n.max(1) as f64 / 10.0, hungry)
    }

    /// Hash of every person's state in id order.
    pub fn fingerprint(&mut self) -> u64 {
        let mut rows: Vec<(u32, [u64; 7])> = Vec::with_capacity(self.count as usize);
        let mut q = self.world.query::<(&Pid, &Home, &Job, &Health, &Needs, &Relations, &Spouse, &Born, Option<&Travel>, &Intelligence)>();
        for (pid, home, job, health, needs, rel, sp, born, t, mind) in q.iter(&self.world) {
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
                    rel.n as u64 | (mind.gene as u16 as u64) << 16 | (mind.env as u16 as u64) << 32,
                    (sp.0 as u64) << 32 | born.0 as u32 as u64,
                ],
            ));
        }
        rows.sort_unstable_by_key(|r| r.0);
        let bytes: Vec<u8> = rows.iter().flat_map(|(p, v)| p.to_le_bytes().into_iter().chain(v.iter().flat_map(|x| x.to_le_bytes()))).collect();
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

    /// S82 over decades: couples correlate in IQ as in Horwitz et al. 2023
    /// (r 0.44), and the adult IQ keeps mean 100 and SD 15 over two
    /// generations because inheritance (life::child_gene) assumes the
    /// genetic correlation the rule produces (life::IQ_MATE_RG).
    /// Without the gap rule couples are uncorrelated. Slow: run with
    /// cargo test --release -- --ignored iq_mating_over_decades
    #[test]
    #[ignore]
    fn iq_mating_over_decades() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let run = |gap: f64, years: i64| {
            let mut p = People::with_iq_mate_gap(&inp, 3, gap);
            for _ in 0..years * 360 {
                p.day();
            }
            let n = p.stats.marry_iq[0];
            (p.stats.marry_iq_r(), p.stats.marry_gene_r(), n, p.iq_summary())
        };
        let (r, rg, n, (mean, sd, lo, hi)) = run(IQ_MATE_GAP_PROPOSED, 60);
        assert!(n > 100_000.0, "marriages {n}");
        assert!((r - crate::life::IQ_MATE_R).abs() < 0.05, "partner r {r}");
        // Inheritance must assume the genetic correlation the rule produces.
        assert!((rg - crate::life::IQ_MATE_RG).abs() < 0.03, "genetic r {rg}");
        assert!((mean - 100.0).abs() < 1.0, "mean {mean}");
        assert!((sd - 15.0).abs() < 0.6, "sd {sd}");
        // Normal tails: 2.28 % below 70 and above 130.
        assert!((lo - 2.28).abs() < 0.5 && (hi - 2.28).abs() < 0.5, "tails {lo} {hi}");
        let (r0, _, _, _) = run(f64::INFINITY, 10);
        assert!(r0.abs() < 0.05, "partner r without the rule {r0}");
    }

    #[test]
    fn csr_groups() {
        let c = Csr::build(4, vec![(2, 7), (0, 3), (2, 1)]);
        assert_eq!(c.get(0), &[3]);
        assert_eq!(c.get(1), &[] as &[u32]);
        assert_eq!(c.get(2), &[1, 7]);
        assert_eq!(c.get(9), &[] as &[u32]);
    }
}
