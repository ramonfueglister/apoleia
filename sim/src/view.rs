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
//! `child << 23 | female << 22 | key << 8 | job << 4 | estate << 2 | kind`
//! (the occupation of S77 and the estate for colouring by group, sex and
//! childhood for the figures up close). Area: 0 = empty slot; 1..=VILLAGES = a village of the
//! 25 km cell around the anchor (1 + village seed); ROAD = anywhere in the
//! cell (people on the road); < 0 = disk of that radius in km around a city.
//! At home the anchor is the centre of the household's village tile
//! (crate::settle, 1.5625 km fine tile) and the area 1 + a seed of that
//! tile; the GPU puts the village on the best open land of the tile and the
//! household's house within 0.6 km of it. The key is the low 14 bits of the
//! household id (the person id on the road), so a family shares one house.
//! The GPU picks those spots from hashes of the keys, so they never change
//! while the people stay put. Floats only carry whole numbers below 2^24 in
//! the last two fields, so no bit pattern can turn into a NaN on the way to
//! the GPU.

use crate::groups::{JOB_GROUP, JOB_NAMES, POLITICAL_NAMES};
use crate::life::YEAR;
use crate::people::{Born, Clock, Culture, Faction, Health, Home, Household, Intelligence, Job, People, Pid, Religion, Sex, Spouse, Stand, Travel};
use crate::grain::FineCover;
use crate::settle::{CoverOf, Settle, Spot};
use crate::City;
use bevy_ecs::prelude::*;
use rustc_hash::FxHashMap;

/// Records per page: one 64 × 64 layer of the GPU texture array.
pub const PAGE: usize = 4096;
/// Record size in f32.
pub const REC: usize = 4;
/// Dot kinds (low two bits of the last field; the key starts at bit 8, so
/// the field stays below 2^24).
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
/// Household (or person) key bits in the record.
const KEY_MASK: u32 = 0x3fff;
/// Younger than this, a person is drawn as a child.
const CHILD_YEARS: i64 = 14;

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
    /// Household and home behind each slot's house (`house_key`), and the
    /// (home, household, estate) it was worked out from.
    member: Vec<u64>,
    member_src: Vec<[u32; 3]>,
    /// One house per village household (see `Houses`).
    pub houses: Houses,
    /// Village and house of each household.
    pub settle: Settle,
    query: Option<QueryState<(&'static Pid, &'static Home, &'static Household, &'static Stand, &'static Job, &'static Sex, &'static Born, Option<&'static Travel>)>>,
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
    /// Builds the home spots (villages, listed places) once; with the fine
    /// land cover (grain::fine_cover) villages sit on the most farmland.
    pub fn new(p: &People, cities: &[City], cover: Option<&FineCover>) -> PeopleView {
        let lookup = |r: i32, c: i32| cover.and_then(|cv| cv.get((r, c)));
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
            member: Vec::new(),
            member_src: Vec::new(),
            houses: Houses::default(),
            settle: Settle::new(&p.grid, &p.pop, cities, cover.map(|_| &lookup as CoverOf), 1),
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

    #[allow(clippy::too_many_arguments)]
    fn record(&self, p: &People, pid: u32, home: u32, household: u32, stand: u8, job: u8, look: u32, travel: Option<&Travel>) -> [f32; REC] {
        let w = |key: u32, kind: u32| (look << 22 | (key & KEY_MASK) << 8 | (job as u32 & 15) << 4 | (stand as u32 & 3) << 2 | kind) as f32;
        if let Some(t) = travel {
            let (x, z) = self.cell_centre(p, t.at);
            return [x, z, ROAD, w(pid, if t.leave { LEAVING } else { TRAVELLING })];
        }
        match self.settle.spot(home, household, stand) {
            Spot::City { place } => [place.x, place.z, -place.r, w(household, IN_CITY)],
            Spot::Village { fine, .. } => {
                let (x, z) = self.settle.fine_centre_km(fine);
                [x as f32, z as f32, 1.0 + (hash(fine) % VILLAGES) as f32, w(household, AT_HOME)]
            }
        }
    }

    /// Person id in a slot (picking a dot), if the slot is in use.
    pub fn pid_at(&self, slot: usize) -> Option<u32> {
        self.pid_of.get(slot).copied().filter(|&p| p != NONE)
    }

    /// Brings the records to the people's current state. Returns the pages
    /// that changed since the last call (all pages after a resize).
    pub fn update(&mut self, p: &mut People) -> Vec<u32> {
        self.stamp = self.stamp.wrapping_add(1).max(1);
        let stamp = self.stamp;
        let mut query = self.query.take().unwrap_or_else(|| p.world.query());
        let mut grew = false;
        let mut writes: Vec<(u32, [f32; REC])> = Vec::with_capacity(1024);
        let day = p.world.resource::<Clock>().day;
        for (pid, home, household, stand, job, sex, born, travel) in query.iter(&p.world) {
            // female bit and child bit for the figures
            let look = (sex.0 == 0) as u32 | ((day - born.0 as i64) < CHILD_YEARS * YEAR) as u32 * 2;
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
                        self.member.resize(self.slots(), NO_HOUSE);
                        self.member_src.resize(self.slots(), [NONE; 3]);
                        self.pid_of.resize(self.slots(), NONE);
                        self.free.extend((s + 1..self.slots() as u32).rev());
                        grew = true;
                        s
                    }
                };
                self.slot_of[pid as usize] = slot;
                self.pid_of[slot as usize] = pid;
                self.inputs[slot as usize] = [NONE; 3];
                self.member_src[slot as usize] = [NONE; 3];
            }
            self.seen[slot as usize] = stamp;
            // the household's house: kept while members travel, moved when
            // the household moves, gone with its last member
            let src = [home.0, household.0, stand.0 as u32];
            if self.member_src[slot as usize] != src {
                self.member_src[slot as usize] = src;
                let key = match self.settle.spot(home.0, household.0, stand.0) {
                    Spot::Village { fine, .. } => {
                        let (x, z) = self.settle.fine_centre_km(fine);
                        Some((house_key(household.0, home.0), [x as f32, z as f32, 1.0 + (hash(fine) % VILLAGES) as f32, ((household.0 & KEY_MASK) << 8) as f32]))
                    }
                    Spot::City { .. } => None,
                };
                let old = std::mem::replace(&mut self.member[slot as usize], key.map_or(NO_HOUSE, |k| k.0));
                if key.map(|k| k.0) != Some(old) {
                    self.houses.leave(old);
                    if let Some((k, rec)) = key {
                        self.houses.join(k, rec);
                    }
                }
            }
            let now = if travel.is_some() { [NONE; 3] } else { [home.0, household.0, stand.0 as u32 | (job.0 as u32) << 8 | look << 16] };
            if now[0] != NONE && self.inputs[slot as usize] == now {
                continue;
            }
            self.inputs[slot as usize] = now;
            let rec = self.record(p, pid, home.0, household.0, stand.0, job.0, look, travel);
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
                self.houses.leave(std::mem::replace(&mut self.member[slot], NO_HOUSE));
                self.member_src[slot] = [NONE; 3];
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

    /// What a click on a dot shows: one person and their household, read
    /// from the world (a pass over all people, only on request).
    pub fn person(p: &mut People, pid: u32) -> Option<Person> {
        let day = p.world.resource::<Clock>().day;
        let mut q = p.world.query::<(&Pid, &Born, &Sex, &Household, &Home, &Job, &Stand, &Health, &Faction, &Culture, &Religion, Option<&Intelligence>, Option<&Spouse>, Option<&Travel>)>();
        let (_, born, sex, hh, home, job, stand, health, faction, culture, religion, iq, spouse, travel) = q.iter(&p.world).find(|t| t.0 .0 == pid)?;
        let age = (day - born.0 as i64) as f64 / YEAR as f64;
        let mut out = Person {
            pid,
            age,
            female: sex.0 == 0,
            household: hh.0,
            members: 0,
            home: home.0,
            job: JOB_NAMES.get(job.0 as usize).copied().unwrap_or("?"),
            group: JOB_GROUP.get(job.0 as usize).and_then(|&g| POLITICAL_NAMES.get(g as usize)).copied().unwrap_or("?"),
            factions: (0..8).filter(|b| faction.0 >> b & 1 == 1).filter_map(|b| POLITICAL_NAMES.get(b)).copied().collect(),
            stand: stand.0,
            health: health.0,
            culture: culture.0,
            religion: religion.0,
            iq: iq.map(|i| i.iq(age)),
            spouse: spouse.map(|s| s.0).filter(|&s| s != NONE),
            travelling: travel.map(|t| t.leave),
        };
        let house = hh.0;
        out.members = q.iter(&p.world).filter(|t| t.3 .0 == house).count() as u32;
        Some(out)
    }

    /// Houses that changed since the last call (all after a resize).
    pub fn take_house_pages(&mut self) -> Vec<u32> {
        self.houses.take_dirty()
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
        let cover = crate::grain::fine_cover(&root, true).ok();
        let mut v = PeopleView::new(&p, &inp.cities, cover.as_ref());
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
        let pid = v.pid_at((0..v.slots()).find(|&s| v.data[s * REC + 2] != 0.0).unwrap()).unwrap();
        let who = PeopleView::person(&mut p, pid).expect("a living person");
        // one house per village household with a member at home or away
        let houses = (0..v.houses.slots()).filter(|&s| v.houses.data[s * REC + 2] != 0.0).count();
        assert_eq!(houses, v.houses.count());
        assert!(houses > 1000 && houses < p.count as usize);
        assert!(who.members >= 1 && who.age >= 0.0);
    }
}

/// One person as a click on their dot shows them.
#[derive(Clone, Debug)]
pub struct Person {
    pub pid: u32,
    pub age: f64,
    pub female: bool,
    pub household: u32,
    /// People in the household, the person included.
    pub members: u32,
    pub home: u32,
    pub job: &'static str,
    /// Political group of the occupation (groups::JOB_GROUP).
    pub group: &'static str,
    /// Political groups the person belongs to (Faction).
    pub factions: Vec<&'static str>,
    pub stand: u8,
    pub health: u16,
    pub culture: u16,
    pub religion: u16,
    pub iq: Option<f64>,
    pub spouse: Option<u32>,
    /// On the road: Some(leaving for good).
    pub travelling: Option<bool>,
}

const NO_HOUSE: u64 = u64::MAX;

fn house_key(household: u32, home: u32) -> u64 {
    (household as u64) << 32 | home as u64
}

/// One house per village household (city people live in the town tiles):
/// a record like the household's people at home (anchor, village area,
/// key << 8), in fixed slots and pages like the people, so a day uploads
/// only the pages where a household appeared, moved or died out. A house
/// counts the members whose home it is, travellers included.
#[derive(Default)]
pub struct Houses {
    pub data: Vec<f32>,
    dirty: Vec<bool>,
    free: Vec<u32>,
    grew: bool,
    /// Slot and members by household and home.
    by_key: FxHashMap<u64, (u32, u32)>,
}

impl Houses {
    pub fn slots(&self) -> usize {
        self.data.len() / REC
    }

    pub fn pages(&self) -> usize {
        self.slots() / PAGE
    }

    /// Houses standing.
    pub fn count(&self) -> usize {
        self.by_key.len()
    }

    pub fn page(&self, page: usize) -> &[f32] {
        &self.data[page * PAGE * REC..(page + 1) * PAGE * REC]
    }

    fn join(&mut self, key: u64, rec: [f32; REC]) {
        if let Some(e) = self.by_key.get_mut(&key) {
            e.1 += 1;
            return;
        }
        let slot = match self.free.pop() {
            Some(s) => s,
            None => {
                let s = self.slots() as u32;
                self.data.resize(self.data.len() + PAGE * REC, 0.0);
                self.free.extend((s + 1..self.slots() as u32).rev());
                self.grew = true;
                s
            }
        };
        self.by_key.insert(key, (slot, 1));
        self.write(slot, rec);
    }

    fn leave(&mut self, key: u64) {
        if key == NO_HOUSE {
            return;
        }
        let Some(e) = self.by_key.get_mut(&key) else { return };
        e.1 -= 1;
        if e.1 == 0 {
            let slot = e.0;
            self.by_key.remove(&key);
            self.write(slot, [0.0; REC]);
            self.free.push(slot);
        }
    }

    fn write(&mut self, slot: u32, rec: [f32; REC]) {
        let o = slot as usize * REC;
        self.data[o..o + REC].copy_from_slice(&rec);
        self.dirty.resize(self.pages(), false);
        self.dirty[slot as usize / PAGE] = true;
    }

    fn take_dirty(&mut self) -> Vec<u32> {
        self.dirty.resize(self.pages(), false);
        if std::mem::take(&mut self.grew) {
            self.dirty.fill(true);
        }
        let out = self.dirty.iter().enumerate().filter(|(_, &d)| d).map(|(i, _)| i as u32).collect();
        self.dirty.fill(false);
        out
    }
}
