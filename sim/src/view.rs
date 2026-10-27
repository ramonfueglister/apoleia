//! Presentation view of the people (S45 snapshot rule): one record per
//! person for the renderer, which draws every person as a dot on the map.
//!
//! Each person keeps a fixed slot while alive (freed slots are reused), so
//! a day only changes the slots of people who were born, died, moved or are
//! on the road. Slots are grouped in pages of `PAGE` records; `update`
//! returns which pages changed, and only those go to the GPU.
//!
//! A record is four f32 (RGBA32F texel): x and z of the anchor in world
//! km (eqc41, as tiles.csv and the tile terrain), the area and
//! `key * 4 + kind`. Area: 0 = empty slot; 1..=VILLAGES = a village of the
//! 25 km cell around the anchor (1 + village seed); ROAD = anywhere in the
//! cell (people on the road); < 0 = disk of that radius in km around a city.
//! The key is the low 22 bits of the household id (the person id on the
//! road), so a family shares one home spot and a village one place in its
//! cell. The GPU picks those spots on land from hashes of the keys, so they
//! never change while the people stay put. The sim itself only knows the
//! cell (Home); villages are a presentation rule until the sim has home
//! tiles. Floats only carry whole numbers below 2^24 here, so no bit pattern
//! can turn into a NaN on the way to the GPU.

use crate::people::{Home, Household, People, Pid, Stand, Travel, CITY};
use crate::City;
use bevy_ecs::prelude::*;
use rustc_hash::FxHashMap;

/// Records per page: one 64 × 64 layer of the GPU texture array.
pub const PAGE: usize = 4096;
/// Record size in f32.
pub const REC: usize = 4;
/// Dot kinds (low two bits of the last field).
pub const AT_HOME: u32 = 0;
pub const IN_CITY: u32 = 1;
pub const TRAVELLING: u32 = 2;
pub const LEAVING: u32 = 3;
const CELL_KM: f32 = 25.0;
/// Village seeds per cell are 0..VILLAGES-1; the area code is seed + 1.
pub const VILLAGES: u32 = 4096;
/// Area code of people on the road (anywhere in their current cell).
pub const ROAD: f32 = 8192.0;
/// Simulated people per village at the start (about 14,000 real people per
/// village is far too many, but a simulated person stands for 566; this
/// gives 2-10 dot clusters per rural cell).
const PEOPLE_PER_VILLAGE: u32 = 25;
const NONE: u32 = u32::MAX;

/// A listed place: centre in km, radius in km and its share of the city
/// people of its cell (cumulative, 0–65535).
#[derive(Clone, Copy)]
struct Place {
    x: f32,
    z: f32,
    r: f32,
    upto: u32,
}

pub struct PeopleView {
    /// Records by slot.
    pub data: Vec<f32>,
    slot_of: Vec<u32>,
    pid_of: Vec<u32>,
    free: Vec<u32>,
    /// Day at which each slot was last seen alive (to find the dead).
    seen: Vec<u32>,
    stamp: u32,
    /// Records rewritten by the last update (changed people).
    pub last_writes: usize,
    dirty: Vec<bool>,
    places: FxHashMap<u32, Vec<Place>>,
    /// Villages per cell, fixed at the start (so households keep theirs).
    villages: Vec<u8>,
    query: Option<QueryState<(&'static Pid, &'static Home, &'static Household, &'static Stand, Option<&'static Travel>)>>,
}

/// City radius in km, the same rule the tile terrain uses for its town
/// tiles (tools/build_tile_terrain.py, settlements), so city dots sit on
/// the drawn town.
fn city_radius_km(pop: f64) -> f32 {
    (0.6 * (pop / 10_000.0).sqrt()).max(0.5) as f32
}

fn hash(v: u32) -> u32 {
    let mut x = v.wrapping_mul(0x9e37_79b9) ^ 0x85eb_ca6b;
    x ^= x >> 16;
    x = x.wrapping_mul(0x7feb_352d);
    x ^= x >> 15;
    x = x.wrapping_mul(0x846c_a68b);
    x ^ (x >> 16)
}

impl PeopleView {
    /// Builds the place table (listed cities by grid cell) once.
    pub fn new(p: &People, cities: &[City]) -> PeopleView {
        let mut by_cell: FxHashMap<u32, Vec<(f32, f32, f64)>> = FxHashMap::default();
        for c in cities {
            let (r, col) = ((c.z_m / 25_000.0).floor() as i32, (c.x_m / 25_000.0).floor() as i32);
            if let Some(i) = p.grid.index(r, col) {
                by_cell.entry(i).or_default().push(((c.x_m / 1000.0) as f32, (c.z_m / 1000.0) as f32, c.pop));
            }
        }
        let places = by_cell
            .into_iter()
            .map(|(cell, list)| {
                let total: f64 = list.iter().map(|c| c.2).sum::<f64>().max(1.0);
                let mut acc = 0.0;
                let v = list
                    .iter()
                    .map(|&(x, z, pop)| {
                        acc += pop;
                        Place { x, z, r: city_radius_km(pop), upto: ((acc / total) * 65535.0).round() as u32 }
                    })
                    .collect();
                (cell, v)
            })
            .collect();
        PeopleView {
            data: Vec::new(),
            slot_of: Vec::new(),
            pid_of: Vec::new(),
            free: Vec::new(),
            seen: Vec::new(),
            stamp: 0,
            last_writes: 0,
            dirty: Vec::new(),
            places,
            villages: p.pop.iter().map(|&n| (n / PEOPLE_PER_VILLAGE).clamp(1, 255) as u8).collect(),
            query: None,
        }
    }

    /// Slots in use or free (a multiple of PAGE).
    pub fn slots(&self) -> usize {
        self.data.len() / REC
    }

    pub fn pages(&self) -> usize {
        self.slots() / PAGE
    }

    fn cell_centre(&self, p: &People, cell: u32) -> (f32, f32) {
        let (r, c) = (p.grid.row0 + cell as i32 / p.grid.cols, p.grid.col0 + cell as i32 % p.grid.cols);
        ((c as f32 + 0.5) * CELL_KM, (r as f32 + 0.5) * CELL_KM)
    }

    fn record(&self, p: &People, pid: u32, home: u32, household: u32, stand: u8, travel: Option<&Travel>) -> [f32; REC] {
        if let Some(t) = travel {
            let (x, z) = self.cell_centre(p, t.at);
            let kind = if t.leave { LEAVING } else { TRAVELLING };
            return [x, z, ROAD, (pid & 0x3f_ffff) as f32 * 4.0 + kind as f32];
        }
        let key = (household & 0x3f_ffff) as f32 * 4.0;
        if stand >= CITY {
            if let Some(list) = self.places.get(&home) {
                let u = hash(household ^ 0x51ce) & 0xffff;
                let pl = list.iter().find(|pl| u <= pl.upto).unwrap_or(&list[list.len() - 1]);
                return [pl.x, pl.z, -pl.r, key + IN_CITY as f32];
            }
        }
        let (x, z) = self.cell_centre(p, home);
        let n = self.villages.get(home as usize).copied().unwrap_or(1).max(1) as u32;
        let seed = hash(home.wrapping_mul(256) + hash(household) % n) % VILLAGES;
        [x, z, 1.0 + seed as f32, key + AT_HOME as f32]
    }

    /// Brings the records to the people's current state. Returns the pages
    /// that changed since the last call (all pages after a resize).
    pub fn update(&mut self, p: &mut People) -> Vec<u32> {
        self.stamp = self.stamp.wrapping_add(1).max(1);
        let stamp = self.stamp;
        let mut query = self.query.take().unwrap_or_else(|| p.world.query());
        let mut grew = false;
        let mut writes: Vec<(u32, [f32; REC])> = Vec::with_capacity(1024);
        for (pid, home, household, stand, travel) in query.iter(&p.world) {
            let pid = pid.0;
            if pid as usize >= self.slot_of.len() {
                self.slot_of.resize(pid as usize + 1, NONE);
            }
            let mut slot = self.slot_of[pid as usize];
            if slot == NONE {
                slot = match self.free.pop() {
                    Some(s) => s,
                    None => {
                        let s = self.slots() as u32;
                        self.data.resize(self.data.len() + PAGE * REC, 0.0);
                        self.seen.resize(self.slots(), 0);
                        self.pid_of.resize(self.slots(), NONE);
                        self.free.extend((s + 1..self.slots() as u32).rev());
                        grew = true;
                        s
                    }
                };
                self.slot_of[pid as usize] = slot;
                self.pid_of[slot as usize] = pid;
            }
            self.seen[slot as usize] = stamp;
            let rec = self.record(p, pid, home.0, household.0, stand.0, travel);
            let o = slot as usize * REC;
            if self.data[o..o + REC] != rec {
                writes.push((slot, rec));
            }
        }
        self.last_writes = writes.len();
        self.query = Some(query);
        self.dirty.resize(self.pages(), false);
        for (slot, rec) in writes {
            let o = slot as usize * REC;
            self.data[o..o + REC].copy_from_slice(&rec);
            self.dirty[slot as usize / PAGE] = true;
        }
        // The dead and the emigrated: slots not seen today. Their pids are
        // never reused, so the pid → slot entry is dropped for good.
        for slot in 0..self.pid_of.len() {
            let pid = self.pid_of[slot];
            if pid != NONE && self.seen[slot] != stamp {
                self.slot_of[pid as usize] = NONE;
                self.pid_of[slot] = NONE;
                let slot = slot as u32;
                let o = slot as usize * REC;
                self.data[o..o + REC].fill(0.0);
                self.dirty[slot as usize / PAGE] = true;
                self.free.push(slot);
            }
        }
        if grew {
            self.dirty.fill(true);
        }
        let out = self.dirty.iter().enumerate().filter(|(_, &d)| d).map(|(i, _)| i as u32).collect();
        self.dirty.fill(false);
        out
    }

    /// Records of one page.
    pub fn page(&self, page: usize) -> &[f32] {
        &self.data[page * PAGE * REC..(page + 1) * PAGE * REC]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slots_are_stable_and_only_changes_are_dirty() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let inp = crate::inputs::load(&root, false).expect("inputs");
        let mut p = People::new(&inp, 1);
        let mut v = PeopleView::new(&p, &inp.cities);
        let first = v.update(&mut p);
        assert_eq!(first.len(), v.pages());
        let used = (0..v.slots()).filter(|&s| v.data[s * REC + 2] != 0.0).count();
        assert_eq!(used, p.count as usize);
        assert!(v.update(&mut p).is_empty(), "nothing changed, nothing dirty");
        for _ in 0..30 {
            p.day();
        }
        let pages = v.update(&mut p);
        let used = (0..v.slots()).filter(|&s| v.data[s * REC + 2] != 0.0).count();
        assert_eq!(used, p.count as usize);
        assert!(pages.len() <= v.pages());
    }
}
