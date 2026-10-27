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
//! At home the anchor is the centre of the household's village tile
//! (crate::settle, 1.5625 km fine tile) and the area 1 + a seed of that
//! tile; the GPU puts the village on the best open land of the tile and the
//! household's house within 0.6 km of it. The key is the low 22 bits of the
//! household id (the person id on the road), so a family shares one house.
//! The GPU picks those spots from hashes of the keys, so they never change
//! while the people stay put. Floats only carry whole numbers below 2^24 in
//! the last two fields, so no bit pattern can turn into a NaN on the way to
//! the GPU.

use crate::people::{Home, Household, People, Pid, Stand, Travel};
use crate::settle::{Settle, Spot};
use crate::City;
use bevy_ecs::prelude::*;

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
const NONE: u32 = u32::MAX;

pub struct PeopleView {
    /// Records by slot.
    pub data: Vec<f32>,
    slot_of: Vec<u32>,
    pid_of: Vec<u32>,
    free: Vec<u32>,
    /// Day at which each slot was last seen alive (to find the dead).
    seen: Vec<u32>,
    /// (home, household, estate) behind the record of each slot at home,
    /// so an unchanged person costs no home lookup; NONE otherwise.
    inputs: Vec<[u32; 3]>,
    stamp: u32,
    /// Records rewritten by the last update (changed people).
    pub last_writes: usize,
    dirty: Vec<bool>,
    /// Village and house of each household.
    pub settle: Settle,
    query: Option<QueryState<(&'static Pid, &'static Home, &'static Household, &'static Stand, Option<&'static Travel>)>>,
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
    /// Builds the home spots (villages, listed places) once.
    pub fn new(p: &People, cities: &[City]) -> PeopleView {
        PeopleView {
            data: Vec::new(),
            slot_of: Vec::new(),
            pid_of: Vec::new(),
            free: Vec::new(),
            seen: Vec::new(),
            inputs: Vec::new(),
            stamp: 0,
            last_writes: 0,
            dirty: Vec::new(),
            settle: Settle::new(&p.grid, &p.pop, cities, None, 1),
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
        match self.settle.spot(home, household, stand) {
            Spot::City { place } => [place.x, place.z, -place.r, key + IN_CITY as f32],
            Spot::Village { fine, .. } => {
                let (x, z) = self.settle.fine_centre_km(fine);
                [x as f32, z as f32, 1.0 + (hash(fine) % VILLAGES) as f32, key + AT_HOME as f32]
            }
        }
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
                        self.inputs.resize(self.slots(), [NONE; 3]);
                        self.pid_of.resize(self.slots(), NONE);
                        self.free.extend((s + 1..self.slots() as u32).rev());
                        grew = true;
                        s
                    }
                };
                self.slot_of[pid as usize] = slot;
                self.pid_of[slot as usize] = pid;
                self.inputs[slot as usize] = [NONE; 3];
            }
            self.seen[slot as usize] = stamp;
            let now = if travel.is_some() { [NONE; 3] } else { [home.0, household.0, stand.0 as u32] };
            if now[0] != NONE && self.inputs[slot as usize] == now {
                continue;
            }
            self.inputs[slot as usize] = now;
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
