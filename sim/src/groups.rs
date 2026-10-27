//! Pops, occupations and political groups as a layer derived from the
//! people (decisions S61, S77).
//!
//! Every person carries their own memberships: the pop is the key (100 km
//! region, estate, culture, religion), the economic group is the
//! occupation (`Job`), the political groups are a bit mask (`Faction`, one
//! or more of eight). Groups store no people of their own: once a month
//! they are counted again from their members, so nobody is counted twice
//! and whoever changes estate, job or home is in the new group at the next
//! count. What the groups do is open (S61, S77) and not built.
//!
//! The count runs in parallel over the person tables with one map per
//! thread; the maps are added up and sorted by key, so the result does not
//! depend on the thread count.

use crate::people::{Culture, Faction, Home, Job, Religion, Stand, CITY, EQUES, NONE, SENATOR};
use bevy_ecs::prelude::*;
use bevy_utils::Parallel;
use rustc_hash::FxHashMap;

/// Occupations, timeless names (S77); the Victoria 3 profession in the
/// comment.
pub const JOBS: usize = 13;
pub const ADEL: u8 = 0; // aristocrats
pub const UNTERNEHMER: u8 = 1; // capitalists
pub const GEISTLICHE: u8 = 2; // clergy
pub const OFFIZIERE: u8 = 3; // officers
pub const HAENDLER: u8 = 4; // shopkeepers
pub const BEAMTE: u8 = 5; // bureaucrats, clerks
pub const GELEHRTE: u8 = 6; // academics
pub const HANDWERKER: u8 = 7; // machinists, engineers
pub const BAUERN: u8 = 8; // farmers
pub const PAECHTER: u8 = 9; // peasants
pub const TAGELOEHNER: u8 = 10; // laborers
pub const SOLDATEN: u8 = 11; // soldiers
pub const UNFREIE: u8 = 12; // slaves
pub const JOB_NAMES: [&str; JOBS] = [
    "Adel",
    "Unternehmer",
    "Geistliche",
    "Offiziere",
    "Händler",
    "Beamte",
    "Gelehrte",
    "Handwerker",
    "Bauern",
    "Pächter",
    "Tagelöhner",
    "Soldaten",
    "Unfreie",
];

/// Political groups, as many as Victoria 3 has, names by Ramon (S77).
pub const POLITICAL: usize = 8;
pub const GRUNDBESITZER: u8 = 0; // landowners
pub const INDUSTRIELLE: u8 = 1; // industrialists
pub const INTELLIGENZIJA: u8 = 2; // intelligentsia
pub const KLEINBUERGERTUM: u8 = 3; // petite bourgeoisie
pub const BAUERNSCHAFT: u8 = 4; // rural folk
pub const MILITAER: u8 = 5; // armed forces
pub const KLERUS: u8 = 6; // devout
pub const ARBEITERSCHAFT: u8 = 7; // trade unions
pub const POLITICAL_NAMES: [&str; POLITICAL] =
    ["Grundbesitzer", "Industrielle", "Intelligenzija", "Kleinbürgertum", "Bauernschaft", "Militär", "Klerus", "Arbeiterschaft"];

/// PLACEHOLDER (S77 leaves open which occupation joins which group): the
/// group the occupation leans to most in Victoria 3. A person is a member
/// of their occupation's group; further memberships are open.
pub const JOB_GROUP: [u8; JOBS] = [
    GRUNDBESITZER,  // Adel
    INDUSTRIELLE,   // Unternehmer
    KLERUS,         // Geistliche
    MILITAER,       // Offiziere
    KLEINBUERGERTUM, // Händler
    KLEINBUERGERTUM, // Beamte
    INTELLIGENZIJA, // Gelehrte
    ARBEITERSCHAFT, // Handwerker
    BAUERNSCHAFT,   // Bauern
    BAUERNSCHAFT,   // Pächter
    ARBEITERSCHAFT, // Tagelöhner
    MILITAER,       // Soldaten
    BAUERNSCHAFT,   // Unfreie
];

/// Political groups (bit mask) of a person with this occupation.
pub fn membership(job: u8) -> u8 {
    1 << JOB_GROUP[job as usize]
}

/// Occupations by estate at the start, in per mille: an estimate for the
/// Roman Empire around 180 AD (Ramon, 27.10.2026), see docs/kit2/GROUPS.md
/// for the sources. Nobody changes occupation for now (Ramon, 27.10.2026);
/// children take the father's (placeholder).
const START_SHARES: [&[(u8, u16)]; 4] = [
    // Land (RURAL): owner-farmers, tenants (coloni), day labourers, rural
    // slaves, village crafts and trade, soldiers in the frontier camps.
    &[
        (BAUERN, 453),
        (PAECHTER, 290),
        (TAGELOEHNER, 110),
        (UNFREIE, 100),
        (HANDWERKER, 30),
        (HAENDLER, 10),
        (SOLDATEN, 4),
        (GEISTLICHE, 3),
    ],
    // Stadt (CITY): crafts and trade, labourers, more slaves than on the
    // land, townspeople farming their land outside the walls, garrisons,
    // decurions counted with the businessmen until they are an estate.
    &[
        (HANDWERKER, 270),
        (TAGELOEHNER, 235),
        (UNFREIE, 150),
        (HAENDLER, 130),
        (BAUERN, 150),
        (SOLDATEN, 15),
        (BEAMTE, 20),
        (UNTERNEHMER, 10),
        (GEISTLICHE, 10),
        (GELEHRTE, 10),
    ],
    // Ritter (EQUES): landowners, procurators, tax and trade business,
    // military tribunes and prefects.
    &[(ADEL, 300), (BEAMTE, 250), (UNTERNEHMER, 250), (OFFIZIERE, 200)],
    // Senatoren (SENATOR)
    &[(ADEL, 1000)],
];

fn shares(stand: u8) -> &'static [(u8, u16)] {
    START_SHARES[match stand {
        CITY => 1,
        EQUES => 2,
        SENATOR => 3,
        _ => 0,
    }]
}

/// Start occupation for a person of this estate from a random value.
pub fn start_job(stand: u8, r: u64) -> u8 {
    let s = shares(stand);
    let total: u64 = s.iter().map(|&(_, p)| p as u64).sum();
    let mut x = r % total;
    for &(job, p) in s {
        if x < p as u64 {
            return job;
        }
        x -= p as u64;
    }
    s[s.len() - 1].0
}

/// Pop key: 100 km region (tile level 1), estate, culture, religion.
pub type PopKey = (u32, u8, u16, u16);

/// One pop: its key and head counts by occupation and political group.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Pop {
    pub key: PopKey,
    pub people: u32,
    pub jobs: [u32; JOBS],
    pub political: [u32; POLITICAL],
}

/// The derived layer, rebuilt monthly: pops sorted by key, and totals.
#[derive(Default, Debug)]
pub struct Groups {
    pub pops: Vec<Pop>,
    /// People per occupation (economic group).
    pub economic: [u32; JOBS],
    /// Members per political group; a person in two groups counts once in
    /// each.
    pub political: [u32; POLITICAL],
    pub people: u32,
}

impl Groups {
    pub fn pop(&self, key: PopKey) -> Option<&Pop> {
        self.pops.binary_search_by_key(&key, |p| p.key).ok().map(|i| &self.pops[i])
    }
}

/// One person in a census snapshot: pop key, occupation, political groups.
#[derive(Clone, Copy)]
struct Row {
    key: PopKey,
    job: u8,
    mask: u8,
}

/// Days a census is spread over after its snapshot.
pub const CENSUS_DAYS: usize = 10;

/// A monthly count spread over several days so no day carries all of it.
/// `start` takes a snapshot of everyone's memberships in one parallel pass;
/// `step` counts the next part of that snapshot and returns the finished
/// groups after the last part. Everything comes from the one snapshot, so
/// nobody is counted twice or missed even if people are born, die or move
/// while the count runs. The sums are integers and the pops are sorted by
/// key at the end, so the result does not depend on the thread count.
#[derive(Default)]
pub struct Census {
    rows: Vec<Row>,
    next: usize,
    pops: FxHashMap<PopKey, Pop>,
}

impl Census {
    pub fn running(&self) -> bool {
        self.next < self.rows.len()
    }

    /// Snapshot of every person's pop key, occupation and political groups.
    /// `cell_region` maps a home cell to a dense region index into
    /// `region_key` (NONE at sea; then `region_of` gives the key).
    pub fn start(&mut self, world: &mut World, cell_region: &[u32], region_key: &[u32], region_of: impl Fn(u32) -> u32 + Sync) {
        let mut local: Parallel<Vec<Row>> = Parallel::default();
        let mut q = world.query::<(&Home, &Stand, &Culture, &Religion, &Job, &Faction)>();
        q.contiguous_par_iter(world).expect("people live in tables").for_each_init(
            || local.borrow_local_mut(),
            |rows, (home, stand, culture, religion, job, faction)| {
                rows.extend((0..home.len()).map(|i| {
                    let cell = home[i].0;
                    let region = match cell_region.get(cell as usize) {
                        Some(&r) if r != NONE => region_key[r as usize],
                        _ => region_of(cell),
                    };
                    Row { key: (region, stand[i].0, culture[i].0, religion[i].0), job: job[i].0, mask: faction[i].0 }
                }));
            },
        );
        self.rows.clear();
        local.drain_into(&mut self.rows);
        self.next = 0;
        self.pops.clear();
    }

    /// Counts the next of `CENSUS_DAYS` parts; the groups once all are done.
    pub fn step(&mut self) -> Option<Groups> {
        if !self.running() {
            return None;
        }
        let part = self.rows.len().div_ceil(CENSUS_DAYS).max(1);
        let end = (self.next + part).min(self.rows.len());
        for r in &self.rows[self.next..end] {
            let pop = self.pops.entry(r.key).or_insert_with(|| Pop { key: r.key, ..Pop::default() });
            pop.people += 1;
            pop.jobs[r.job as usize] += 1;
            for g in 0..POLITICAL {
                pop.political[g] += (r.mask >> g) as u32 & 1;
            }
        }
        self.next = end;
        if self.running() {
            return None;
        }
        let mut g = Groups { pops: self.pops.drain().map(|(_, p)| p).collect(), ..Groups::default() };
        g.pops.sort_unstable_by_key(|p| p.key);
        for p in &g.pops {
            g.people += p.people;
            for j in 0..JOBS {
                g.economic[j] += p.jobs[j];
            }
            for k in 0..POLITICAL {
                g.political[k] += p.political[k];
            }
        }
        Some(g)
    }
}

/// Counts every person once into their pop, occupation and political
/// groups, all at once (a census run to the end).
pub fn count(world: &mut World, cell_region: &[u32], region_key: &[u32], region_of: impl Fn(u32) -> u32 + Sync) -> Groups {
    let mut c = Census::default();
    c.start(world, cell_region, region_key, region_of);
    loop {
        if let Some(g) = c.step() {
            return g;
        }
        if !c.running() {
            return Groups::default();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn start_jobs_follow_the_estate() {
        assert!((0..1000).all(|r| start_job(SENATOR, r) == ADEL));
        let mut n = [0u32; JOBS];
        for r in 0..10_000 {
            n[start_job(0, r) as usize] += 1;
        }
        assert_eq!(n[BAUERN as usize], 4530);
        assert_eq!(n[UNFREIE as usize], 1000);
        assert_eq!(n[ADEL as usize], 0);
        for stand in 0..4 {
            assert_eq!(shares(stand).iter().map(|s| s.1 as u32).sum::<u32>(), 1000);
        }
    }

    #[test]
    fn every_occupation_belongs_to_a_group() {
        for j in 0..JOBS as u8 {
            assert_eq!(membership(j).count_ones(), 1);
        }
        assert_eq!(JOB_NAMES.len(), 13);
        assert_eq!(POLITICAL_NAMES.len(), 8);
    }

    /// The parallel count equals a plain serial count, and nobody is
    /// counted twice: every person is in exactly one pop and one
    /// occupation, and once in each of their political groups.
    #[test]
    fn parallel_count_equals_plain_count() {
        bevy_tasks::ComputeTaskPool::get_or_init(|| bevy_tasks::TaskPoolBuilder::new().num_threads(4).build());
        let mut world = World::new();
        let cell_region: Vec<u32> = (0..50).map(|c| if c % 7 == 0 { NONE } else { c / 10 }).collect();
        let region_key: Vec<u32> = (0..5).map(|r| 1000 + r).collect();
        let region_of = |c: u32| 9000 + c;
        let mut plain: BTreeMap<PopKey, (u32, [u32; JOBS], [u32; POLITICAL])> = BTreeMap::new();
        let mut members = 0;
        for i in 0..20_000u32 {
            let h = i.wrapping_mul(2654435761);
            let (cell, stand, culture, religion) = (h % 50, (h >> 8) as u8 % 4, (h >> 10) as u16 % 3, (h >> 12) as u16 % 2);
            let job = start_job(stand, h as u64 >> 3);
            // Some people in two or three groups.
            let mask = membership(job) | if h % 5 == 0 { 1 << ((h >> 20) % 8) } else { 0 };
            members += mask.count_ones();
            world.spawn((Home(cell), Stand(stand), Culture(culture), Religion(religion), Job(job), Faction(mask)));
            let region = if cell_region[cell as usize] != NONE { region_key[cell_region[cell as usize] as usize] } else { region_of(cell) };
            let e = plain.entry((region, stand, culture, religion)).or_insert((0, [0; JOBS], [0; POLITICAL]));
            e.0 += 1;
            e.1[job as usize] += 1;
            for g in 0..POLITICAL {
                e.2[g] += (mask >> g) as u32 & 1;
            }
        }
        let g = count(&mut world, &cell_region, &region_key, region_of);
        let got: Vec<_> = g.pops.iter().map(|p| (p.key, (p.people, p.jobs, p.political))).collect();
        let want: Vec<_> = plain.into_iter().collect();
        assert_eq!(got, want);
        assert_eq!(g.people, 20_000);
        assert_eq!(g.economic.iter().sum::<u32>(), 20_000);
        assert_eq!(g.political.iter().sum::<u32>(), members);
        let k = g.pops[3].key;
        assert_eq!(g.pop(k).map(|p| p.key), Some(k));
    }

    /// A census counts the people as they were at its start: changes while
    /// it runs (here everyone moves and half are removed) do not show.
    #[test]
    fn census_counts_its_snapshot() {
        bevy_tasks::ComputeTaskPool::get_or_init(|| bevy_tasks::TaskPoolBuilder::new().num_threads(4).build());
        let mut world = World::new();
        let ids: Vec<Entity> = (0..5_000u32).map(|i| world.spawn((Home(i % 20), Stand(0), Culture(0), Religion(0), Job(BAUERN), Faction(membership(BAUERN)))).id()).collect();
        let region_of = |c: u32| c / 4;
        let once = count(&mut world, &[], &[], region_of);
        let mut c = Census::default();
        c.start(&mut world, &[], &[], region_of);
        let mut days = 0;
        let g = loop {
            days += 1;
            for (i, &e) in ids.iter().enumerate() {
                if days == 1 && i % 2 == 0 {
                    world.despawn(e);
                } else if let Some(mut h) = world.get_mut::<Home>(e) {
                    h.0 = 99;
                }
            }
            if let Some(g) = c.step() {
                break g;
            }
        };
        assert_eq!(days, CENSUS_DAYS);
        assert_eq!(g.pops, once.pops);
        assert_eq!(g.people, 5_000);
        assert!(c.step().is_none(), "nothing more until the next start");
    }
}
