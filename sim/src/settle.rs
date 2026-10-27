//! Home spots (presentation, S45 snapshot rule): every household has a
//! fixed village and house tile inside its 25 km home cell, so the dots of
//! a family stand together and other systems (grain farms, a click on a
//! person) can ask where a household lives.
//!
//! The sim state is not touched: a home spot is a pure function of the
//! home cell, the household id and its estate, computed with salts of its
//! own. It never enters the fingerprint, and a household that moves to
//! another cell simply gets the spot of that cell.
//!
//! Tiles are the fine grid of the grain economy (grain.rs): 16 × 16 fine
//! tiles of 1.5625 km per 25 km cell, index `fr * cols_f + fc` counted from
//! the grid origin. Villages sit on the fine tiles with the most farmland
//! (`CoverOf`, landcover-fine); without that data they sit on hashed
//! tiles of the cell and the renderer moves each dot to land.
//!
//! City people (estate CITY) live in a disk around one of the listed places
//! of their cell (cities.csv), with the radius the tile terrain gives its
//! town tiles; their house tile is a hashed spot in that disk.

use crate::people::{Grid, CITY};
use crate::City;
use rustc_hash::FxHashMap;

/// Fine tiles per 25 km cell side (grain.rs FINE).
pub const FINE: i32 = 16;
pub const CELL_KM: f64 = 25.0;
pub const FINE_KM: f64 = CELL_KM / FINE as f64;
/// Simulated people per village at the start: 2–10 villages per rural cell
/// (a simulated person stands for 566 real ones). Frei gewählt.
pub const PEOPLE_PER_VILLAGE: u32 = 25;
/// Houses of a village lie within this radius of its centre (km).
pub const VILLAGE_KM: f64 = 0.6;
const SALT_VILLAGE: u64 = 0x5e77_1e00_0000_0001;
const SALT_SITE: u64 = 0x5e77_1e00_0000_0002;
const SALT_HOUSE: u64 = 0x5e77_1e00_0000_0003;
const SALT_PLACE: u64 = 0x5e77_1e00_0000_0004;

/// Land cover of the fine tiles of one 25 km cell by absolute (row, col),
/// laid out as grain.rs `FineCover::get` gives it (landcover-fine): 256
/// land samples, then 256 farmland samples (farm_8), row-major by tile.
pub type CoverOf<'a> = &'a dyn Fn(i32, i32) -> Option<&'a [u8]>;

/// A listed place: centre and radius in km, and its share of the city
/// people of its cell (cumulative, 0–65535).
#[derive(Clone, Copy, Debug)]
pub struct Place {
    pub x: f32,
    pub z: f32,
    pub r: f32,
    upto: u32,
}

/// Where a household lives.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Spot {
    /// Village `village` (0.. of the cell) on fine tile `fine`.
    Village { fine: u32, village: u32 },
    /// A listed place of the cell (the house tile: `Settle::home_fine`).
    City { place: Place },
}

impl PartialEq for Place {
    fn eq(&self, o: &Place) -> bool {
        (self.x, self.z, self.r) == (o.x, o.z, o.r)
    }
}

pub struct Settle {
    row0: i32,
    col0: i32,
    cols: i32,
    cols_f: i32,
    seed: u64,
    /// Village tiles by cell, fixed at the start (so households keep
    /// theirs while the cell grows or shrinks).
    villages: Vec<Vec<u32>>,
    places: FxHashMap<u32, Vec<Place>>,
}

/// splitmix64 finaliser over the inputs: asked for every person every
/// day by the view, so cheaper than xxh3 over a buffer.
fn h(seed: u64, salt: u64, a: u64, b: u64) -> u64 {
    let mix = |mut z: u64| {
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^ (z >> 31)
    };
    mix(mix(seed ^ salt ^ a.wrapping_mul(0x9e37_79b9_7f4a_7c15)) ^ b)
}

/// City radius in km, the rule of the town tiles
/// (tools/build_tile_terrain.py, settlements).
pub fn city_radius_km(pop: f64) -> f32 {
    (0.6 * (pop / 10_000.0).sqrt()).max(0.5) as f32
}

impl Settle {
    /// `pop`: simulated people per cell at the start (People::pop).
    pub fn new(grid: &Grid, pop: &[u32], cities: &[City], cover: Option<CoverOf>, seed: u64) -> Settle {
        let cols_f = grid.cols * FINE;
        let mut villages = Vec::with_capacity(pop.len());
        for (cell, &n) in pop.iter().enumerate() {
            let want = (n / PEOPLE_PER_VILLAGE).clamp(1, 255) as usize;
            let (r, c) = (cell as i32 / grid.cols, cell as i32 % grid.cols);
            let tiles: Vec<u32> = (0..FINE * FINE).map(|k| ((r * FINE + k / FINE) * cols_f + c * FINE + k % FINE) as u32).collect();
            let fine = cover.and_then(|f| f(r + grid.row0, c + grid.col0)).filter(|b| b.len() >= 512);
            // score: farmland first, then land; the hash breaks ties and
            // stands in for the cover where there is no fine data
            let mut scored: Vec<(u64, u64, u32)> = tiles
                .iter()
                .enumerate()
                .map(|(k, &t)| {
                    let (farm, land) = fine.map_or((0, 1), |b| (b[256 + k] as u64, b[k] as u64));
                    (farm, land, t)
                })
                .filter(|&(_, land, _)| land > 0)
                .collect();
            if scored.is_empty() {
                // a sea cell (people only pass through): any tile
                scored = tiles.iter().map(|&t| (0, 0, t)).collect();
            }
            scored.sort_by_key(|&(farm, land, t)| std::cmp::Reverse((farm, land, h(seed, SALT_SITE, cell as u64, t as u64))));
            // no two villages on neighbouring tiles while there is room
            let mut chosen: Vec<u32> = Vec::with_capacity(want);
            for &(_, _, t) in &scored {
                if chosen.len() == want {
                    break;
                }
                let near = chosen.iter().any(|&o| ((o as i32 / cols_f) - (t as i32 / cols_f)).abs() <= 1 && ((o as i32 % cols_f) - (t as i32 % cols_f)).abs() <= 1);
                if !near {
                    chosen.push(t);
                }
            }
            for &(_, _, t) in &scored {
                if chosen.len() == want {
                    break;
                }
                if !chosen.contains(&t) {
                    chosen.push(t);
                }
            }
            villages.push(chosen);
        }
        let mut by_cell: FxHashMap<u32, Vec<(f32, f32, f64)>> = FxHashMap::default();
        for c in cities {
            let (r, col) = ((c.z_m / 25_000.0).floor() as i32, (c.x_m / 25_000.0).floor() as i32);
            if let Some(i) = grid.index(r, col) {
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
        Settle { row0: grid.row0, col0: grid.col0, cols: grid.cols, cols_f, seed, villages, places }
    }

    /// Villages of a cell (fine tiles).
    pub fn villages(&self, cell: u32) -> &[u32] {
        self.villages.get(cell as usize).map_or(&[], |v| v.as_slice())
    }

    /// The home of a household in `cell`.
    pub fn spot(&self, cell: u32, household: u32, stand: u8) -> Spot {
        if stand >= CITY {
            if let Some(list) = self.places.get(&cell) {
                let u = (h(self.seed, SALT_PLACE, household as u64, 0) & 0xffff) as u32;
                return Spot::City { place: *list.iter().find(|pl| u <= pl.upto).unwrap_or(&list[list.len() - 1]) };
            }
        }
        let list = self.villages(cell);
        if list.is_empty() {
            return Spot::Village { fine: 0, village: 0 };
        }
        let village = (h(self.seed, SALT_VILLAGE, cell as u64, household as u64) % list.len() as u64) as u32;
        Spot::Village { fine: list[village as usize], village }
    }

    /// Fine tile of a household's house (grain: where its farm stands).
    pub fn home_fine(&self, cell: u32, household: u32, stand: u8) -> u32 {
        match self.spot(cell, household, stand) {
            Spot::Village { fine, .. } => fine,
            Spot::City { place } => {
                let (x, z) = self.in_disk(place.x as f64, place.z as f64, place.r as f64, household);
                self.fine_at(x, z).or_else(|| self.fine_at(place.x as f64, place.z as f64)).unwrap_or(0)
            }
        }
    }

    /// The house of a household in world km (eqc41): a hashed point within
    /// VILLAGE_KM of the village tile's centre, or in the city disk. The
    /// renderer may move it to the nearest land.
    pub fn house_km(&self, cell: u32, household: u32, stand: u8) -> (f64, f64) {
        match self.spot(cell, household, stand) {
            Spot::Village { fine, .. } => {
                let (x, z) = self.fine_centre_km(fine);
                self.in_disk(x, z, VILLAGE_KM, household)
            }
            Spot::City { place } => self.in_disk(place.x as f64, place.z as f64, place.r as f64, household),
        }
    }

    /// Centre of a fine tile in world km.
    pub fn fine_centre_km(&self, fine: u32) -> (f64, f64) {
        let (fr, fc) = (fine as i32 / self.cols_f + self.row0 * FINE, fine as i32 % self.cols_f + self.col0 * FINE);
        ((fc as f64 + 0.5) * FINE_KM, (fr as f64 + 0.5) * FINE_KM)
    }

    /// Fine tile at a point in world km, if it lies on the grid.
    pub fn fine_at(&self, x_km: f64, z_km: f64) -> Option<u32> {
        let fr = (z_km / FINE_KM).floor() as i32 - self.row0 * FINE;
        let fc = (x_km / FINE_KM).floor() as i32 - self.col0 * FINE;
        let rows_f = self.villages.len() as i32 / self.cols * FINE;
        (fr >= 0 && fc >= 0 && fr < rows_f && fc < self.cols_f).then(|| (fr * self.cols_f + fc) as u32)
    }

    fn in_disk(&self, x: f64, z: f64, r: f64, household: u32) -> (f64, f64) {
        let v = h(self.seed, SALT_HOUSE, household as u64, 0);
        let a = (v & 0xffff) as f64 / 65536.0 * std::f64::consts::TAU;
        let d = ((v >> 16 & 0xffff) as f64 / 65535.0).sqrt() * r;
        (x + a.cos() * d, z + a.sin() * d)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::people::People;

    #[test]
    fn homes_are_fixed_inside_the_cell_and_leave_the_sim_alone() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let inp = crate::inputs::load(&root, false).expect("inputs");
        let mut a = People::new(&inp, 1);
        let mut b = People::new(&inp, 1);
        let s = Settle::new(&a.grid, &a.pop, &inp.cities, None, 1);
        for _ in 0..30 {
            a.day();
            b.day();
        }
        // the same household always gets the same spot, inside its cell
        let cols_f = a.grid.cols * FINE;
        for cell in (0..a.pop.len() as u32).filter(|&c| a.grid.kind[c as usize] != 0).step_by(37) {
            for hh in [1u32, 17, 4242, 99_999] {
                let f = s.home_fine(cell, hh, 0);
                assert_eq!(f, s.home_fine(cell, hh, 0));
                assert_eq!((f as i32 / cols_f / FINE, f as i32 % cols_f / FINE), (cell as i32 / a.grid.cols, cell as i32 % a.grid.cols));
                let (x, z) = s.fine_centre_km(f);
                assert_eq!(s.fine_at(x, z), Some(f));
            }
        }
        // building and asking for homes does not touch the sim
        let _ = Settle::new(&b.grid, &b.pop, &inp.cities, None, 1);
        assert_eq!(a.fingerprint(), b.fingerprint());
    }
}
