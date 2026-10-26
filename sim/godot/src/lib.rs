//! GDExtension bridge (S45, S46): Godot owns no game state. It sends
//! commands and reads the snapshot of the last completed month as two
//! textures, one tile index per 1.5625 km map cell and one value row per
//! tile, which the terrain shader colours as a map mode.

use apoleia_sim::ecs::{Command, Sim, Snapshot};
use apoleia_sim::{Params, MAX_LEVEL, ROOT_SIZE_M};
use godot::classes::image::Format;
use godot::classes::Image;
use godot::prelude::*;
use std::path::Path;
use std::sync::Arc;
use std::time::Instant;

struct ApoleiaExtension;

#[gdextension]
unsafe impl ExtensionLibrary for ApoleiaExtension {}

/// Width of the value texture; tile i sits at (i % W, i / W).
const VALUE_WIDTH: usize = 1024;

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct ApoleiaSim {
    sim: Option<Sim>,
    snap: Option<Arc<Snapshot>>,
    /// Finest-level grid covering all tiles: origin column/row and size.
    grid: (i64, i64, usize, usize),
    /// Tile index + 1 per grid cell (0 = no tile), rebuilt on structure change.
    index: Vec<f32>,
    index_structure: Option<u64>,
    last_step_usec: f64,
    base: Base<RefCounted>,
}

fn cell_m() -> f64 {
    ROOT_SIZE_M / (1u64 << MAX_LEVEL) as f64
}

#[godot_api]
impl ApoleiaSim {
    /// Loads the inputs below `repo_root` and builds the start state.
    #[func]
    fn load(&mut self, repo_root: GString) -> bool {
        let root = repo_root.to_string();
        match apoleia_sim::inputs::load(Path::new(&root), false) {
            Ok(d) => {
                let mut sim = Sim::new(Params::default(), &d.start, d.cells, d.cities);
                let snap = sim.snapshot();
                let shift = |level: u8| 1i64 << (MAX_LEVEL - level);
                let (mut c0, mut r0, mut c1, mut r1) = (i64::MAX, i64::MAX, i64::MIN, i64::MIN);
                for t in &snap.tiles {
                    let s = shift(t.key.level);
                    let (c, r) = (t.key.col as i64 * s, t.key.row as i64 * s);
                    c0 = c0.min(c);
                    r0 = r0.min(r);
                    c1 = c1.max(c + s);
                    r1 = r1.max(r + s);
                }
                self.grid = (c0, r0, (c1 - c0) as usize, (r1 - r0) as usize);
                self.sim = Some(sim);
                self.snap = Some(snap);
                self.index_structure = None;
                true
            }
            Err(e) => {
                godot_error!("ApoleiaSim.load: {e}");
                false
            }
        }
    }

    /// Advances the given number of months through the command queue (S43).
    #[func]
    fn advance(&mut self, months: i64) {
        let Some(sim) = self.sim.as_mut() else { return };
        let t0 = Instant::now();
        for _ in 0..months.max(0) {
            sim.submit(0, Command::AdvanceMonth);
        }
        sim.step();
        self.last_step_usec = t0.elapsed().as_secs_f64() * 1e6;
        self.snap = Some(sim.snapshot());
    }

    #[func]
    fn month(&self) -> i64 {
        self.snap.as_ref().map_or(0, |s| s.month as i64)
    }

    #[func]
    fn tile_count(&self) -> i64 {
        self.snap.as_ref().map_or(0, |s| s.tiles.len() as i64)
    }

    #[func]
    fn total_population(&self) -> f64 {
        self.snap.as_ref().map_or(0.0, |s| s.tiles.iter().map(|t| t.pop).sum())
    }

    #[func]
    fn fingerprint(&self) -> GString {
        self.sim.as_ref().map_or(GString::new(), |s| format!("{:016x}", s.fingerprint()).as_str().into())
    }

    /// Wall time of the last `advance`, in microseconds.
    #[func]
    fn last_step_usec(&self) -> f64 {
        self.last_step_usec
    }

    /// Size of one index cell in metres (finest tile level).
    #[func]
    fn index_cell_m(&self) -> f64 {
        cell_m()
    }

    /// World position (metres, eqc41) of the index texture's top-left corner.
    #[func]
    fn index_origin_m(&self) -> Vector2 {
        Vector2::new((self.grid.0 as f64 * cell_m()) as f32, (self.grid.1 as f64 * cell_m()) as f32)
    }

    /// True when the tile-ID texture must be fetched again.
    #[func]
    fn index_changed(&self) -> bool {
        self.snap.as_ref().map(|s| s.structure) != self.index_structure
    }

    /// Tile index + 1 per 1.5625 km cell as an RF image (0 = no tile).
    #[func]
    fn index_image(&mut self) -> Option<Gd<Image>> {
        let snap = self.snap.clone()?;
        let (c0, r0, w, h) = self.grid;
        self.index.clear();
        self.index.resize(w * h, 0.0);
        for (i, t) in snap.tiles.iter().enumerate() {
            let s = 1i64 << (MAX_LEVEL - t.key.level);
            let (c, r) = (t.key.col as i64 * s - c0, t.key.row as i64 * s - r0);
            let v = (i + 1) as f32;
            for y in r..r + s {
                let row = &mut self.index[y as usize * w..][..w];
                row[c as usize..(c + s) as usize].fill(v);
            }
        }
        self.index_structure = Some(snap.structure);
        let mut bytes = PackedByteArray::new();
        bytes.resize(w * h * 4);
        for (dst, v) in bytes.as_mut_slice().chunks_exact_mut(4).zip(&self.index) {
            dst.copy_from_slice(&v.to_le_bytes());
        }
        Image::create_from_data(w as i32, h as i32, false, Format::RF, &bytes)
    }

    /// Per tile (population, population per km²) as an RGF image,
    /// `VALUE_WIDTH` tiles per row, in the order of the index texture.
    #[func]
    fn value_image(&self) -> Option<Gd<Image>> {
        let snap = self.snap.as_ref()?;
        let h = snap.tiles.len().div_ceil(VALUE_WIDTH).max(1);
        let mut bytes = PackedByteArray::new();
        bytes.resize(VALUE_WIDTH * h * 8);
        let out = bytes.as_mut_slice();
        for (i, t) in snap.tiles.iter().enumerate() {
            let d = if t.land_km2 > 0.0 { t.pop / t.land_km2 } else { 0.0 };
            out[i * 8..i * 8 + 4].copy_from_slice(&(t.pop as f32).to_le_bytes());
            out[i * 8 + 4..i * 8 + 8].copy_from_slice(&(d as f32).to_le_bytes());
        }
        Image::create_from_data(VALUE_WIDTH as i32, h as i32, false, Format::RGF, &bytes)
    }

    #[func]
    fn value_width(&self) -> i64 {
        VALUE_WIDTH as i64
    }

    /// Largest tile population (scale for the map mode, like the viewer).
    #[func]
    fn max_population(&self) -> f64 {
        self.snap.as_ref().map_or(0.0, |s| s.tiles.iter().map(|t| t.pop).fold(0.0, f64::max))
    }

    /// The tile under a world position in metres, for tooltip and panel.
    #[func]
    fn tile_at(&self, x_m: f64, z_m: f64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(snap) = self.snap.as_ref() else { return d };
        if self.index_structure != Some(snap.structure) {
            return d;
        }
        let (c0, r0, w, h) = self.grid;
        let (c, r) = ((x_m / cell_m()).floor() as i64 - c0, (z_m / cell_m()).floor() as i64 - r0);
        if c < 0 || r < 0 || c as usize >= w || r as usize >= h {
            return d;
        }
        let i = self.index[r as usize * w + c as usize] as usize;
        let Some(t) = i.checked_sub(1).and_then(|i| snap.tiles.get(i)) else { return d };
        d.set("id", t.key.id().as_str());
        d.set("level", t.key.level as i64);
        d.set("size_km", t.key.size_m() / 1000.0);
        d.set("population", t.pop);
        d.set("capacity", t.cap);
        d.set("land_km2", t.land_km2);
        d.set("density", if t.land_km2 > 0.0 { t.pop / t.land_km2 } else { 0.0 });
        d
    }
}
