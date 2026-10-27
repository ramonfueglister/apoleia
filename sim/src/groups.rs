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

/// PLACEHOLDER (open): occupations by estate at the start, in per cent.
/// Order of magnitude only; slaves 10–15 % as estimated in SCALE.md.
const START_SHARES: [&[(u8, u8)]; 4] = [
    // Land (RURAL)
    &[(BAUERN, 45), (PAECHTER, 25), (TAGELOEHNER, 15), (UNFREIE, 12), (SOLDATEN, 2), (GEISTLICHE, 1)],
    // Stadt (CITY)
    &[
        (HANDWERKER, 25),
        (TAGELOEHNER, 27),
        (HAENDLER, 15),
        (UNFREIE, 15),
        (SOLDATEN, 8),
        (BEAMTE, 4),
        (GEISTLICHE, 4),
        (GELEHRTE, 2),
    ],
    // Ritter (EQUES)
    &[(UNTERNEHMER, 40), (BEAMTE, 30), (OFFIZIERE, 30)],
    // Senatoren (SENATOR)
    &[(ADEL, 100)],
];

fn shares(stand: u8) -> &'static [(u8, u8)] {
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

/// PLACEHOLDER (open): chance per year, in per cent, that a person takes
/// up another occupation of their estate.
const CHANGE_PER_YEAR: u64 = 10;

/// PLACEHOLDER (open): the yearly occupation choice. With
/// `CHANGE_PER_YEAR` a person draws a new occupation from the start shares
/// of their estate, so the mix stays near the start. Nobody becomes unfree
/// this way, and the unfree do not choose.
pub fn yearly_job(stand: u8, job: u8, r: u64) -> u8 {
    if job == UNFREIE || r % 100 >= CHANGE_PER_YEAR {
        return job;
    }
    let free: u64 = shares(stand).iter().filter(|s| s.0 != UNFREIE).map(|s| s.1 as u64).sum();
    let mut x = (r / 100) % free;
    for &(j, p) in shares(stand).iter().filter(|s| s.0 != UNFREIE) {
        if x < p as u64 {
            return j;
        }
        x -= p as u64;
    }
    job
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

impl Pop {
    fn add(&mut self, o: &Pop) {
        self.people += o.people;
        for j in 0..JOBS {
            self.jobs[j] += o.jobs[j];
        }
        for g in 0..POLITICAL {
            self.political[g] += o.political[g];
        }
    }
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

/// Counts every person once into their pop, occupation and political
/// groups. `cell_region` maps a home cell to a dense region index into
/// `region_key` (NONE at sea; then `region_of` gives the key).
pub fn count(world: &mut World, cell_region: &[u32], region_key: &[u32], region_of: impl Fn(u32) -> u32 + Sync) -> Groups {
    let mut local: Parallel<FxHashMap<PopKey, Pop>> = Parallel::default();
    let mut q = world.query::<(&Home, &Stand, &Culture, &Religion, &Job, &Faction)>();
    q.contiguous_par_iter(world).expect("people live in tables").for_each_init(
        || local.borrow_local_mut(),
        |map, (home, stand, culture, religion, job, faction)| {
            for i in 0..home.len() {
                let cell = home[i].0;
                let region = match cell_region.get(cell as usize) {
                    Some(&r) if r != NONE => region_key[r as usize],
                    _ => region_of(cell),
                };
                let key = (region, stand[i].0, culture[i].0, religion[i].0);
                let pop = map.entry(key).or_insert_with(|| Pop { key, ..Pop::default() });
                pop.people += 1;
                pop.jobs[job[i].0 as usize] += 1;
                let mask = faction[i].0;
                for g in 0..POLITICAL {
                    pop.political[g] += (mask >> g) as u32 & 1;
                }
            }
        },
    );
    let mut all: FxHashMap<PopKey, Pop> = FxHashMap::default();
    for map in local.iter_mut() {
        for (k, p) in map.drain() {
            all.entry(k).or_insert_with(|| Pop { key: k, ..Pop::default() }).add(&p);
        }
    }
    let mut g = Groups { pops: all.into_values().collect(), ..Groups::default() };
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
    g
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
        assert_eq!(n[BAUERN as usize], 4500);
        assert_eq!(n[UNFREIE as usize], 1200);
        assert_eq!(n[ADEL as usize], 0);
        // The yearly choice keeps the unfree and draws only free occupations.
        assert!((0..1000).all(|r| yearly_job(0, UNFREIE, r) == UNFREIE));
        let changed: Vec<u8> = (0..10_000).map(|r| yearly_job(0, BAUERN, r)).filter(|&j| j != BAUERN).collect();
        assert!(!changed.is_empty() && changed.iter().all(|&j| j != UNFREIE));
        for stand in 0..4 {
            assert_eq!(shares(stand).iter().map(|s| s.1 as u32).sum::<u32>(), 100);
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
}
