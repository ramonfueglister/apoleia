//! The grain economy as map layers for the terrain shader (S69–S87 made
//! visible): what the farms, markets, footpaths and trade roads of
//! crate::grain look like on the ground. Built on the sim thread once a
//! month from Grain's read-only views; the main thread cuts a window of the
//! fine layer around the camera and uploads it, plus the small road layer.
//!
//! Fine layer, one RGBA8 texel per 1.5625 km tile (16 × 16 per 25 km cell):
//! R share of the tile under fields (of what a tile can hold), G sown share
//! of those fields, B growth of the crop (0 bare … 255 ripe), A footpath
//! level (bits 0–1), direction of its next step towards the market + 1
//! (bits 2–5, 0 = none) and market tile (bit 6).
//! Road layer, one RG8 texel per 25 km cell: R trade road level (1 track,
//! 2 road; at sea a sea lane), G the neighbours it joins (bit k = DIRS[k]).

use apoleia_sim::grain::{tile_room_m2, Grain};
use apoleia_sim::people::People;
use std::sync::Arc;

/// Neighbour steps, row by row (as grain.rs DIRS).
pub const DIRS: [(i32, i32); 8] = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)];
pub const FINE: i32 = 16;
pub const MARKET_BIT: u8 = 64;

/// The two layers as of one rebuild; cheap to clone (the main thread
/// keeps one while the sim thread builds the next).
#[derive(Clone, Default)]
pub struct MapLayers {
    /// Grid origin and size in 25 km cells (absolute rows and columns).
    pub row0: i32,
    pub col0: i32,
    pub rows: i32,
    pub cols: i32,
    pub fine: Arc<Vec<u8>>,
    pub roads: Arc<Vec<u8>>,
    /// Bumped on every rebuild.
    pub version: u64,
}

/// Builds the layers on the sim thread.
pub struct GrainMap {
    pub layers: MapLayers,
    /// Last known footpaths per market (a market's field is away while
    /// the path worker walks it).
    paths: Vec<Vec<(u32, u8, u8)>>,
}

impl GrainMap {
    pub fn new(p: &People) -> GrainMap {
        let g = &p.grid;
        GrainMap { layers: MapLayers { row0: g.row0, col0: g.col0, rows: g.rows, cols: g.cols, ..Default::default() }, paths: Vec::new() }
    }

    /// Rebuilds both layers from the grain economy of `day`.
    pub fn build(&mut self, g: &Grain, day: i64) {
        let (rf, cf) = self.layers.fine_size();
        debug_assert_eq!(g.fine_size(), (rf, cf));
        let n = (rf * cf) as usize;
        // fields: shares of what a tile holds, summed straight into the
        // bytes (no buffer per tile: the raster has 8 million tiles); G
        // first sums the sown share the same way, then becomes the share
        // of the fields; B is the growth of the last farm on the tile
        let mut fine = vec![0u8; n * 4];
        let (row0, cfu) = (self.layers.row0, cf as u32);
        let mut room_of = vec![0u64; (rf / FINE) as usize];
        for (r, x) in room_of.iter_mut().enumerate() {
            *x = tile_room_m2(r as i32 + row0).max(1) as u64;
        }
        g.for_each_plot(day, |t, m2, s, growth| {
            let room = room_of[(t / cfu) as usize / FINE as usize];
            let i = t as usize * 4;
            let share = |x: u32| ((x as u64 * 255 + room / 2) / room).min(255) as u8;
            fine[i] = fine[i].saturating_add(share(m2));
            fine[i + 1] = fine[i + 1].saturating_add(share(s));
            if s > 0 {
                fine[i + 2] = growth;
            }
        });
        for px in fine.chunks_exact_mut(4) {
            if px[0] > 0 {
                px[1] = (px[1] as u32 * 255 / px[0] as u32).min(255) as u8;
            }
        }
        // footpaths, the last known of each market
        self.paths.resize(g.markets.len(), Vec::new());
        for (m, known) in self.paths.iter_mut().enumerate() {
            if let Some(v) = g.market_paths(m) {
                *known = v;
            }
            for &(t, level, dir) in known.iter() {
                let a = &mut fine[t as usize * 4 + 3];
                let step = if dir == 255 { 0 } else { dir + 1 };
                *a = (*a & MARKET_BIT) | level.min(3) | step << 2;
            }
        }
        for mk in &g.markets {
            fine[mk.fine as usize * 4 + 3] |= MARKET_BIT;
        }
        self.layers.fine = Arc::new(fine);
        // trade roads and sea lanes: join neighbours that carry one too; a
        // diagonal only where no straight pair already makes the turn
        let lv = g.road_levels();
        let (rows, cols) = (self.layers.rows, self.layers.cols);
        let at = |r: i32, c: i32| -> u8 { if r < 0 || c < 0 || r >= rows || c >= cols { 0 } else { lv[(r * cols + c) as usize] } };
        let mut roads = vec![0u8; (rows * cols * 2) as usize];
        for r in 0..rows {
            for c in 0..cols {
                let l = at(r, c);
                if l == 0 {
                    continue;
                }
                let mut mask = 0u8;
                for (k, &(dr, dc)) in DIRS.iter().enumerate() {
                    if at(r + dr, c + dc) == 0 {
                        continue;
                    }
                    if dr != 0 && dc != 0 && (at(r + dr, c) > 0 || at(r, c + dc) > 0) {
                        continue;
                    }
                    mask |= 1 << k;
                }
                let i = ((r * cols + c) * 2) as usize;
                roads[i] = l;
                roads[i + 1] = mask;
            }
        }
        self.layers.roads = Arc::new(roads);
        self.layers.version += 1;
    }
}

impl MapLayers {
    pub fn fine_size(&self) -> (i32, i32) {
        (self.rows * FINE, self.cols * FINE)
    }

    /// The fine layer of `n` × `n` tiles from tile (fr0, fc0) (raster rows
    /// and columns, may reach past the edges: zero there), RGBA8 bytes.
    pub fn window(&self, fr0: i32, fc0: i32, n: i32) -> Vec<u8> {
        let (rf, cf) = self.fine_size();
        let mut out = vec![0u8; (n * n * 4) as usize];
        if self.fine.is_empty() {
            return out;
        }
        for y in 0..n {
            let fr = fr0 + y;
            if fr < 0 || fr >= rf {
                continue;
            }
            let (c0, c1) = (fc0.max(0), (fc0 + n).min(cf));
            if c0 >= c1 {
                continue;
            }
            let src = ((fr * cf + c0) * 4) as usize..((fr * cf + c1) * 4) as usize;
            let dst = ((y * n + c0 - fc0) * 4) as usize;
            out[dst..dst + src.len()].copy_from_slice(&self.fine[src]);
        }
        out
    }
}
