//! The grain economy as map layers for the terrain shader (S69–S87 made
//! visible): what the farms, markets, footpaths and trade roads of
//! crate::grain look like on the ground. Once a month (and when a building
//! site is done) the sim thread takes what the layers show from Grain's
//! read-only views (`MapJob::take`, a few milliseconds); the raster of
//! eight million tiles is drawn on a thread of its own (`MapThread`), so
//! the day after does not wait for it (REALTIME_GAMEPLAY.md phase 8). The
//! main thread cuts a window of the fine layer around the camera and
//! uploads it, plus the small road layer.
//!
//! Fine layer, one RGBA8 texel per 1.5625 km tile (16 × 16 per 25 km cell):
//! R share of the tile under fields (of what a tile can hold), G sown share
//! of those fields, B growth of the crop (0 bare … 255 ripe), A market
//! tile (bit 6).
//! Way layer (S127), one RG8 texel per fine tile: R the neighbours its way
//! leads to (bit k = DIRS[k]), G the way's level 0 … 7 in the low three
//! bits and bit 3 (8) on a tile the public works paved (S133; a paved tile
//! no one walks now leads to its paved neighbours).
//! Road layer, one RG8 texel per 25 km cell: R trade road level (1 track,
//! 2 road; at sea a sea lane, the only part drawn, S127), G the neighbours
//! it joins (bit k = DIRS[k]).

use apoleia_sim::grain::{tile_room_m2, Grain};
use apoleia_sim::people::People;
use std::sync::mpsc;
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
    pub ways: Arc<Vec<u8>>,
    pub roads: Arc<Vec<u8>>,
    /// Market (region) of each 25 km cell, u32::MAX at sea (Grain::cell_markets).
    pub regions: Arc<Vec<u32>>,
    /// Bumped on every rebuild.
    pub version: u64,
}

/// What the layers of one day are drawn from, taken on the sim thread.
pub struct MapJob {
    /// Each field plot: fine tile, m², m² sown, growth (Grain::for_each_plot),
    /// in parts by farm.
    plots: Vec<Vec<(u32, u32, u32, u8)>>,
    /// Footpaths per market; None while its walk is away (keep the last).
    paths: Vec<Option<Vec<(u32, u8, u8)>>>,
    markets: Vec<u32>,
    road_levels: Vec<u8>,
    regions: Vec<u32>,
    /// S133: fine tiles the public works paved (Grain::paved_tiles).
    paved: Vec<u32>,
}

impl MapJob {
    pub fn take(g: &Grain, day: i64) -> MapJob {
        MapJob {
            plots: g.plot_lists(day),
            paths: (0..g.markets.len()).map(|m| g.market_paths(m)).collect(),
            markets: g.markets.iter().map(|m| m.fine).collect(),
            road_levels: g.road_levels().to_vec(),
            regions: g.cell_markets().to_vec(),
            paved: g.paved_tiles().collect(),
        }
    }

    /// A newer job, keeping the footpaths of this one where the newer has
    /// none (the job between was dropped unseen).
    fn then(mut self, newer: MapJob) -> MapJob {
        for (m, p) in newer.paths.into_iter().enumerate() {
            if p.is_some() || m >= self.paths.len() {
                if m < self.paths.len() {
                    self.paths[m] = p;
                } else {
                    self.paths.push(p);
                }
            }
        }
        MapJob { paths: self.paths, ..newer }
    }
}

/// Draws the layers on a thread of its own and hands each set to
/// `publish`; jobs that pile up meanwhile are folded into the newest.
/// Ends when it is dropped.
pub struct MapThread {
    send: mpsc::Sender<MapJob>,
}

impl MapThread {
    pub fn start(mut map: GrainMap, publish: impl Fn(MapLayers) + Send + 'static) -> MapThread {
        let (send, recv) = mpsc::channel::<MapJob>();
        std::thread::Builder::new()
            .name("apoleia-map".into())
            .spawn(move || {
                while let Ok(mut job) = recv.recv() {
                    while let Ok(newer) = recv.try_recv() {
                        job = job.then(newer);
                    }
                    map.draw(job);
                    publish(map.layers.clone());
                }
            })
            .expect("map thread");
        MapThread { send }
    }

    pub fn draw(&self, job: MapJob) {
        let _ = self.send.send(job);
    }
}

/// Builds the layers.
pub struct GrainMap {
    pub layers: MapLayers,
    /// Last known ways per market: (fine tile, level, links; a market's
    /// field is away while the path worker walks it).
    paths: Vec<Vec<(u32, u8, u8)>>,
}

impl GrainMap {
    pub fn new(p: &People) -> GrainMap {
        let g = &p.grid;
        GrainMap { layers: MapLayers { row0: g.row0, col0: g.col0, rows: g.rows, cols: g.cols, ..Default::default() }, paths: Vec::new() }
    }

    /// Rebuilds both layers from the grain economy of `day`, here and now.
    pub fn build(&mut self, g: &Grain, day: i64) {
        debug_assert_eq!(g.fine_size(), self.layers.fine_size());
        self.draw(MapJob::take(g, day));
    }

    /// Rebuilds both layers from a job.
    pub fn draw(&mut self, job: MapJob) {
        let (rf, cf) = self.layers.fine_size();
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
        for &(t, m2, s, growth) in job.plots.iter().flatten() {
            let room = room_of[(t / cfu) as usize / FINE as usize];
            let i = t as usize * 4;
            let share = |x: u32| ((x as u64 * 255 + room / 2) / room).min(255) as u8;
            fine[i] = fine[i].saturating_add(share(m2));
            fine[i + 1] = fine[i + 1].saturating_add(share(s));
            if s > 0 {
                fine[i + 2] = growth;
            }
        }
        for px in fine.chunks_exact_mut(4) {
            if px[0] > 0 {
                px[1] = (px[1] as u32 * 255 / px[0] as u32).min(255) as u8;
            }
        }
        // the ways people wear, the last known of each market
        let mut ways = vec![0u8; n * 2];
        self.paths.resize(job.paths.len(), Vec::new());
        for (known, now) in self.paths.iter_mut().zip(job.paths) {
            if let Some(v) = now {
                *known = v;
            }
            for &(t, level, links) in known.iter() {
                ways[t as usize * 2] = links;
                ways[t as usize * 2 + 1] = level.min(7);
            }
        }
        // S133: a paved tile keeps its level (wear) and carries bit 3, drawn
        // as gravel as wide as its wear (sim_map.gdshaderinc sim_ways)
        for &t in &job.paved {
            ways[t as usize * 2 + 1] |= 8;
        }
        // S133: a paved tile no one walks now (no links) joins its paved
        // neighbours, and they join it back: the straight ones always, a
        // diagonal only where neither straight tile beside it is paved
        // (no triangles; as the trade roads below)
        let mut paved = vec![false; n];
        for &t in &job.paved {
            paved[t as usize] = true;
        }
        let is_paved = |r: i32, c: i32| r >= 0 && c >= 0 && r < rf && c < cf && paved[(r * cf + c) as usize];
        let lone: Vec<u32> = job.paved.iter().copied().filter(|&t| ways[t as usize * 2] == 0).collect();
        for t in lone {
            let (r, c) = (t as i32 / cf, t as i32 % cf);
            for (k, &(dr, dc)) in DIRS.iter().enumerate() {
                if !is_paved(r + dr, c + dc) || (dr != 0 && dc != 0 && (is_paved(r + dr, c) || is_paved(r, c + dc))) {
                    continue;
                }
                ways[t as usize * 2] |= 1 << k;
                ways[((r + dr) * cf + c + dc) as usize * 2] |= 1 << (7 - k);
            }
        }
        self.layers.ways = Arc::new(ways);
        for &t in &job.markets {
            fine[t as usize * 4 + 3] |= MARKET_BIT;
        }
        self.layers.fine = Arc::new(fine);
        // trade roads and sea lanes: join neighbours that carry one too; a
        // diagonal only where no straight pair already makes the turn (the
        // terrain draws them only at sea: on land the wagons wear the fine
        // layer's ways, S127)
        let lv = &job.road_levels;
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
        self.layers.regions = Arc::new(job.regions);
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
        Self::cut(&self.fine, 4, self.fine_size(), fr0, fc0, n)
    }

    /// The way layer's `n` × `n` tiles from (fr0, fc0), as `window`.
    pub fn ways_window(&self, fr0: i32, fc0: i32, n: i32) -> Vec<u8> {
        Self::cut(&self.ways, 2, self.fine_size(), fr0, fc0, n)
    }

    fn cut(layer: &[u8], bytes: i32, (rf, cf): (i32, i32), fr0: i32, fc0: i32, n: i32) -> Vec<u8> {
        let mut out = vec![0u8; (n * n * bytes) as usize];
        if layer.is_empty() {
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
            let src = ((fr * cf + c0) * bytes) as usize..((fr * cf + c1) * bytes) as usize;
            let dst = ((y * n + c0 - fc0) * bytes) as usize;
            out[dst..dst + src.len()].copy_from_slice(&layer[src]);
        }
        out
    }
}
