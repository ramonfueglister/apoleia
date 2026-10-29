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

use crate::build::Tile;
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
/// Ages at which a household member counts as one who works (the hired
/// hand a click on a day labourer shows), as the grain economy's workers:
/// the adults 15–60 first, then all 10–65 who work in the peaks.
const WORK_YEARS: [std::ops::Range<i64>; 2] = [15..61, 10..66];
/// Household of a building site's house: nobody lives there yet.
const SITE: u32 = u32::MAX;

/// The key a farm is drawn with when its family lives on the farm, not in
/// its village (`set_homes`): for a farm built from an order its spot's,
/// from the building site on (`set_sites`), so the house stands where the
/// site stood and several farms can stand on one fine tile; else its fine
/// tile's (heirs).
fn site_key(spot: Option<Tile>, fine: u32) -> u32 {
    match spot {
        Some(t) => spot_code(t) & KEY_MASK,
        None => hash(fine ^ 0x51e5) & KEY_MASK,
    }
}

/// A building site's stand-in for a household id in its house key.
fn spot_code(t: Tile) -> u32 {
    hash(hash(t.0 as u32 ^ 0x51e5) ^ t.1 as u32)
}

/// An order's spot (world metres, row = z, column = x) in world km (x, z).
fn spot_km(t: Tile) -> (f64, f64) {
    (t.1 as f64 / 1000.0, t.0 as f64 / 1000.0)
}

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
    /// Household and fine tile behind each slot's house (`house_key`), and the
    /// (home, household, estate) it was worked out from.
    member: Vec<u64>,
    member_src: Vec<[u32; 3]>,
    /// One house per village household (see `Houses`).
    pub houses: Houses,
    /// Village and house of each household.
    pub settle: Settle,
    /// Fine tile of the households whose farm stands elsewhere than their
    /// village (`set_homes`, crate::grain homes_moved), and the order's
    /// spot for a farm built from one: they live there.
    homes: FxHashMap<u32, (u32, Option<Tile>)>,
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
            homes: FxHashMap::default(),
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

    /// The key the GPU places a household's people and house by: the
    /// tile's site key for a household living on its farm's tile.
    fn key_of(&self, household: u32) -> u32 {
        self.homes.get(&household).map_or(household, |&(fine, spot)| site_key(spot, fine))
    }

    /// The building sites of farms (S113): (order's spot, fine tile, share
    /// built × 255). Each is a house record where the farm's house will
    /// stand, marked by a negative village code: [x, z, -village code,
    /// site key << 8 | built]. An empty list takes them all away.
    pub fn set_sites(&mut self, sites: &[(Tile, u32, u8)]) {
        let now: FxHashMap<u64, [f32; REC]> = sites
            .iter()
            .map(|&(t, fine, built)| {
                let (x, z) = spot_km(t);
                (house_key(SITE, spot_code(t)), [x as f32, z as f32, -(1.0 + (hash(fine) % VILLAGES) as f32), (site_key(Some(t), fine) << 8 | built as u32) as f32])
            })
            .collect();
        self.houses.set_sites(now);
    }

    /// Where a household lives: its farm's tile when `set_homes` named
    /// one, else its village (crate::settle).
    fn spot(&self, home: u32, household: u32, stand: u8) -> Spot {
        match self.homes.get(&household) {
            Some(&(fine, _)) => Spot::Village { fine, village: 0 },
            None => self.settle.spot(home, household, stand),
        }
    }

    /// Where the house of a household on `fine` stands: on its order's
    /// spot for a farm built from one, else in the tile's middle.
    fn house_at(&self, household: u32, fine: u32) -> (f64, f64) {
        match self.homes.get(&household) {
            Some(&(f, Some(t))) if f == fine => spot_km(t),
            _ => self.settle.fine_centre_km(fine),
        }
    }

    /// The households that live on their farm instead of their village,
    /// (household, fine tile, the order's spot for a farm built from one);
    /// the next update redraws the people and houses of those that changed.
    pub fn set_homes(&mut self, homes: &[(u32, u32, Option<Tile>)]) {
        let homes: FxHashMap<u32, (u32, Option<Tile>)> = homes.iter().map(|&(h, f, t)| (h, (f, t))).collect();
        if homes == self.homes {
            return;
        }
        let changed: rustc_hash::FxHashSet<u32> = homes
            .iter()
            .filter(|(h, f)| self.homes.get(h) != Some(f))
            .chain(self.homes.iter().filter(|(h, _)| !homes.contains_key(h)))
            .map(|(&h, _)| h)
            .collect();
        self.homes = homes;
        for slot in 0..self.member_src.len() {
            if changed.contains(&self.member_src[slot][1]) {
                self.inputs[slot] = [NONE; 3];
                self.member_src[slot] = [NONE; 3];
            }
        }
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
        match self.spot(home, household, stand) {
            Spot::City { place } => [place.x, place.z, -place.r, w(household, IN_CITY)],
            Spot::Village { fine, .. } => {
                let (x, z) = self.house_at(household, fine);
                [x as f32, z as f32, 1.0 + (hash(fine) % VILLAGES) as f32, w(self.key_of(household), AT_HOME)]
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
                let key = match self.spot(home.0, household.0, stand.0) {
                    Spot::Village { fine, .. } => {
                        let (x, z) = self.house_at(household.0, fine);
                        Some((house_key(household.0, fine), [x as f32, z as f32, 1.0 + (hash(fine) % VILLAGES) as f32, ((self.key_of(household.0) & KEY_MASK) << 8) as f32]))
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

    /// A living member of a household who can work, the one with the
    /// lowest id (else the youngest or eldest who works in the peaks, else
    /// any member): who a hired hand of the household is.
    /// A pass over all people, only on request.
    pub fn member_of(p: &mut People, household: u32) -> Option<u32> {
        let day = p.world.resource::<Clock>().day;
        let mut q = p.world.query::<(&Pid, &Household, &Born)>();
        q.iter(&p.world)
            .filter(|t| t.1 .0 == household)
            .map(|(pid, _, born)| {
                let age = (day - born.0 as i64) / YEAR;
                (WORK_YEARS.iter().position(|r| r.contains(&age)).unwrap_or(WORK_YEARS.len()), pid.0)
            })
            .min()
            .map(|m| m.1)
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

    /// A household pinned to its farm's tile (crate::grain homes_moved)
    /// lives there: its house and its people at home move to that tile,
    /// under the tile's site key; the same pins again change nothing.
    #[test]
    fn pinned_households_live_on_their_farm() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let inp = crate::inputs::load(&root, false).expect("inputs");
        let mut p = People::new(&inp, 1);
        let mut v = PeopleView::new(&p, &inp.cities, None);
        v.update(&mut p);
        let key = *v.houses.by_key.keys().min().unwrap();
        let (hh, from) = ((key >> 32) as u32, key as u32);
        let to = from + 1;
        v.set_homes(&[(hh, to, None)]);
        assert!(!v.update(&mut p).is_empty());
        assert!(!v.houses.by_key.contains_key(&key));
        let (x, z) = v.settle.fine_centre_km(to);
        let s = v.houses.by_key[&house_key(hh, to)].0 as usize * REC;
        assert_eq!((v.houses.data[s], v.houses.data[s + 1]), (x as f32, z as f32));
        let home = (0..v.slots())
            .map(|s| &v.data[s * REC..(s + 1) * REC])
            .filter(|r| r[2] != 0.0 && (r[3] as u32 & 3) == AT_HOME && (r[3] as u32 >> 8 & KEY_MASK) == site_key(None, to))
            .filter(|r| (r[0], r[1]) == (x as f32, z as f32))
            .count();
        assert!(home >= 1);
        v.set_homes(&[(hh, to, None)]);
        assert!(v.update(&mut p).is_empty());
    }

    /// A click on a day labourer shows a member of working age when the
    /// household has one.
    #[test]
    fn hired_hand_is_of_working_age() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let inp = crate::inputs::load(&root, false).expect("inputs");
        let mut p = People::new(&inp, 1);
        let day = p.world.resource::<Clock>().day;
        let mut q = p.world.query::<(&Pid, &Household, &Born)>();
        let mut ages: FxHashMap<u32, Vec<(u32, i64)>> = FxHashMap::default();
        for (pid, hh, born) in q.iter(&p.world) {
            ages.entry(hh.0).or_default().push((pid.0, (day - born.0 as i64) / YEAR));
        }
        let mut checked = 0;
        for (&hh, m) in ages.iter().filter(|(_, m)| m.len() >= 3).take(200) {
            let pid = PeopleView::member_of(&mut p, hh).expect("a member");
            let age = m.iter().find(|x| x.0 == pid).unwrap().1;
            if m.iter().any(|x| WORK_YEARS[0].contains(&x.1)) {
                assert!(WORK_YEARS[0].contains(&age), "household {hh}: picked age {age}");
                checked += 1;
            }
        }
        assert!(checked > 100);
        assert_eq!(PeopleView::member_of(&mut p, u32::MAX - 1), None);
    }

    /// A farm's building site is a house record on the order's spot with a
    /// negative village code and the share built; the family that takes
    /// the farm gets a house with the same key on the same spot, so it
    /// stands where the site stood. A second site on the same fine tile
    /// has a key of its own. Workshops leave sites alone.
    #[test]
    fn sites_turn_into_the_farm() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let inp = crate::inputs::load(&root, false).expect("inputs");
        let mut p = People::new(&inp, 1);
        let mut v = PeopleView::new(&p, &inp.cities, None);
        v.update(&mut p);
        v.take_house_pages();
        let key = *v.houses.by_key.keys().min().unwrap();
        let (hh, fine) = ((key >> 32) as u32, key as u32 + 1);
        let n = v.houses.count();
        let (t, beside): (Tile, Tile) = ((41_250, 1_750), (41_250, 2_250));
        let site = |v: &PeopleView| v.houses.by_key.get(&house_key(SITE, spot_code(t))).map(|e| v.houses.data[e.0 as usize * REC..][..REC].to_vec());
        v.set_sites(&[(t, fine, 100)]);
        let r = site(&v).expect("a site house");
        assert_eq!((r[0], r[1]), (1.75, 41.25), "on the spot");
        assert!(r[2] < 0.0 && r[2] == -(1.0 + (hash(fine) % VILLAGES) as f32));
        assert_eq!(r[3] as u32, site_key(Some(t), fine) << 8 | 100);
        assert_ne!(site_key(Some(t), fine), site_key(Some(beside), fine));
        assert_eq!((v.houses.count(), v.take_house_pages().len()), (n + 1, 1));
        v.houses.set_work([(SITE, 2, 9)]);
        assert_eq!(site(&v).unwrap()[3] as u32 & 255, 100, "no workshop on a site");
        v.set_sites(&[(t, fine, 200)]);
        assert_eq!(site(&v).unwrap()[3] as u32 & 255, 200);
        v.set_sites(&[(t, fine, 200)]);
        assert!(v.take_house_pages().len() == 1, "only the change above");
        // done: the site goes, the family moves in under the same key
        v.set_sites(&[]);
        v.set_homes(&[(hh, fine, Some(t))]);
        v.update(&mut p);
        assert!(site(&v).is_none());
        let h = v.houses.by_key[&house_key(hh, fine)].0 as usize * REC;
        assert_eq!(&v.houses.data[h..h + 2], &r[..2]);
        assert_eq!((v.houses.data[h + 2], v.houses.data[h + 3] as u32 >> 8 & KEY_MASK), (-r[2], site_key(Some(t), fine)));
        assert_eq!(v.houses.count(), n);
    }

    /// A workshop marks its household's house (craft and how busy) next to
    /// the key; only houses whose work changed are written again, and a
    /// house built later gets its household's work at once.
    #[test]
    fn houses_carry_their_workshop() {
        let mut h = Houses::default();
        let rec = |hh: u32| [1.0, 2.0, 3.0, ((hh & KEY_MASK) << 8) as f32];
        h.join(house_key(7, 100), rec(7));
        h.join(house_key(9, 100), rec(9));
        h.take_dirty();
        let w = |h: &Houses, hh: u32| h.data[h.by_key[&house_key(hh, 100)].0 as usize * REC + 3] as u32;
        h.set_work([(7, 2, 200)]);
        assert_eq!(w(&h, 7), 2 << 22 | 7 << 8 | 200);
        assert_eq!(w(&h, 9), 9 << 8);
        assert_eq!(h.take_dirty().len(), 1);
        h.set_work([(7, 2, 200)]);
        assert!(h.take_dirty().is_empty(), "same work, nothing dirty");
        h.set_work([(9, 3, 5)]);
        assert_eq!((w(&h, 7), w(&h, 9)), (7 << 8, 3 << 22 | 9 << 8 | 5));
        h.join(house_key(9, 101), rec(9));
        assert_eq!(h.data[h.by_key[&house_key(9, 101)].0 as usize * REC + 3] as u32, 3 << 22 | 9 << 8 | 5);
        assert!(((3u32 << 22 | KEY_MASK << 8 | 255) as f32) < (1u32 << 24) as f32, "stays a whole float");
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

fn house_key(household: u32, fine: u32) -> u64 {
    (household as u64) << 32 | fine as u64
}

/// One house per village household (city people live in the town tiles):
/// a record like the household's people at home (anchor, village area,
/// `craft << 22 | key << 8 | busy`), in fixed slots and pages like the
/// people, so a day uploads only the pages where a household appeared,
/// moved, died out or changed its work. A house counts the members whose
/// home it is, travellers included. Craft and busy are the household's
/// workshop as the grain economy has it (`set_work`: crate::grain
/// CRAFT_NAMES 1–3, 0 none; share of the month's work sold, 0–255), for
/// the graphics to put the workshop at the house. A farm's building site
/// (S113) is a house too, with a negative village code and the share
/// built in place of busy (`PeopleView::set_sites`).
#[derive(Default)]
pub struct Houses {
    pub data: Vec<f32>,
    dirty: Vec<bool>,
    free: Vec<u32>,
    grew: bool,
    /// Slot and members by household and fine tile.
    by_key: FxHashMap<u64, (u32, u32)>,
    /// `craft << 22 | busy` by household, as of the last `set_work`.
    work: FxHashMap<u32, u32>,
    /// The building sites' houses (`PeopleView::set_sites`).
    sites: Vec<u64>,
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

    fn join(&mut self, key: u64, mut rec: [f32; REC]) {
        if let Some(e) = self.by_key.get_mut(&key) {
            e.1 += 1;
            return;
        }
        rec[3] = (rec[3] as u32 | self.work.get(&((key >> 32) as u32)).copied().unwrap_or(0)) as f32;
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

    /// The workshops of the households: (household, craft, busy) for each
    /// that has one; the others have none. Rewrites only the houses whose
    /// work changed.
    pub fn set_work(&mut self, work: impl IntoIterator<Item = (u32, u8, u8)>) {
        self.work = work.into_iter().filter(|w| w.1 != 0).map(|(h, craft, busy)| (h, (craft as u32 & 3) << 22 | busy as u32)).collect();
        let changed: Vec<(u32, f32)> = self
            .by_key
            .iter()
            .filter(|(&key, _)| (key >> 32) as u32 != SITE)
            .filter_map(|(&key, &(slot, _))| {
                let o = slot as usize * REC + 3;
                let w = ((self.data[o] as u32 & (KEY_MASK << 8)) | self.work.get(&((key >> 32) as u32)).copied().unwrap_or(0)) as f32;
                (w != self.data[o]).then_some((slot, w))
            })
            .collect();
        for (slot, w) in changed {
            let mut rec: [f32; REC] = self.data[slot as usize * REC..][..REC].try_into().unwrap();
            rec[3] = w;
            self.write(slot, rec);
        }
    }

    /// The record of a household's house, if it has one.
    pub fn of(&self, household: u32) -> Option<&[f32]> {
        let (_, &(slot, _)) = self.by_key.iter().find(|(&k, _)| (k >> 32) as u32 == household)?;
        Some(&self.data[slot as usize * REC..][..REC])
    }

    fn set_sites(&mut self, now: FxHashMap<u64, [f32; REC]>) {
        for key in std::mem::take(&mut self.sites) {
            if !now.contains_key(&key) {
                self.leave(key);
            }
        }
        let mut keys: Vec<u64> = now.keys().copied().collect();
        keys.sort_unstable();
        for &key in &keys {
            let rec = now[&key];
            match self.by_key.get(&key) {
                Some(&(slot, _)) if self.data[slot as usize * REC..][..REC] != rec => self.write(slot, rec),
                Some(_) => {}
                None => self.join(key, rec),
            }
        }
        self.sites = keys;
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
