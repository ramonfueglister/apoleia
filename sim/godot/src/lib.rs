//! GDExtension bridge (S45, S46): Godot owns no game state. It sends
//! commands and reads the snapshot of the last completed month as two
//! textures, a paged tile index per 1.5625 km map cell and one value texel
//! per tile slot, which the terrain shader colours as a map mode.
//!
//! The simulation runs on its own thread, as in Paradox's engines: `advance`
//! only queues months and returns, the frame never waits for a tick. The
//! sim thread publishes a snapshot after each month; `refresh` picks up the
//! newest one. Results stay deterministic (one thread owns the world).

mod grain_map;
mod map_index;
mod people_dots;
mod tables;
#[allow(dead_code)] // called by people_dots (ask_trips) on the game branch
mod trips;

use apoleia_sim::ecs::{Command, Sim, Snapshot};
use apoleia_sim::{Params, MAX_LEVEL, ROOT_SIZE_M};
use map_index::{MapIndex, PAGE};
use godot::classes::image::Format;
use godot::classes::Image;
use godot::prelude::*;
use std::path::Path;
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::Instant;

struct ApoleiaExtension;

#[gdextension]
unsafe impl ExtensionLibrary for ApoleiaExtension {}

/// Width of the value texture; slot s sits at (s % W, s / W).
const VALUE_WIDTH: usize = 1024;
/// The value texture grows in steps of this many rows, so it is recreated
/// (and rebound to the materials) rarely, not on every new slot.
const VALUE_ROW_STEP: usize = 16;

/// State shared between Godot's main thread and the sim thread.
#[derive(Default)]
struct Shared {
    queue: Mutex<Queue>,
    wake: Condvar,
    /// Newest published snapshot and the wall time of the month behind it.
    latest: Mutex<Option<(Arc<Snapshot>, f64)>>,
}

#[derive(Default)]
struct Queue {
    months: u64,
    quit: bool,
}

/// The sim thread: owns the world through the mutex, steps one month at a
/// time and publishes each finished month.
fn run(sim: Arc<Mutex<Sim>>, shared: Arc<Shared>) {
    loop {
        {
            let mut q = shared.queue.lock().unwrap();
            while q.months == 0 && !q.quit {
                q = shared.wake.wait(q).unwrap();
            }
            if q.quit {
                return;
            }
            q.months -= 1;
        }
        let mut sim = sim.lock().unwrap();
        let t0 = Instant::now();
        sim.submit(0, Command::AdvanceMonth);
        sim.step();
        let usec = t0.elapsed().as_secs_f64() * 1e6;
        let snap = sim.snapshot();
        drop(sim);
        *shared.latest.lock().unwrap() = Some((snap, usec));
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct ApoleiaSim {
    sim: Option<Arc<Mutex<Sim>>>,
    shared: Arc<Shared>,
    worker: Option<JoinHandle<()>>,
    /// Repository root the inputs were loaded from (needed to load saves).
    root: String,
    snap: Option<Arc<Snapshot>>,
    /// Tile slots and the paged index texture data.
    map: Option<MapIndex>,
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
        self.root = repo_root.to_string();
        match apoleia_sim::inputs::load(Path::new(&self.root), false) {
            Ok(d) => {
                self.start(Sim::new(Params::default(), &d.start, d.cells, d.cities));
                true
            }
            Err(e) => {
                godot_error!("ApoleiaSim.load: {e}");
                false
            }
        }
    }

    /// Writes a save game (absolute path) and returns the month it holds,
    /// or -1. Waits for the month the sim thread is computing; queued months
    /// continue afterwards. The saved month is the sim thread's, which may
    /// be a few months ahead of the snapshot on screen.
    #[func]
    fn save_game(&mut self, path: GString) -> i64 {
        let Some(sim) = self.sim.as_ref() else { return -1 };
        let mut sim = sim.lock().unwrap();
        match sim.save_to(Path::new(&path.to_string())) {
            Ok(()) => sim.stats().month as i64,
            Err(e) => {
                godot_error!("ApoleiaSim.save_game: {e}");
                -1
            }
        }
    }

    /// Replaces the running game with a save game (absolute path). The save
    /// must come from the same inputs and parameters.
    #[func]
    fn load_game(&mut self, path: GString) -> bool {
        let loaded = apoleia_sim::inputs::load(Path::new(&self.root), false)
            .map_err(|e| e.to_string())
            .and_then(|d| Sim::load_from(Params::default(), d.cells, d.cities, Path::new(&path.to_string())).map_err(|e| e.to_string()));
        match loaded {
            Ok(sim) => {
                self.start(sim);
                true
            }
            Err(e) => {
                godot_error!("ApoleiaSim.load_game: {e}");
                false
            }
        }
    }

    /// Queues months for the sim thread (S43) and returns at once.
    #[func]
    fn advance(&mut self, months: i64) {
        if self.sim.is_none() || months <= 0 {
            return;
        }
        self.shared.queue.lock().unwrap().months += months as u64;
        self.shared.wake.notify_one();
    }

    /// Months queued but not yet computed (the sim is behind by this much).
    #[func]
    fn backlog(&self) -> i64 {
        self.shared.queue.lock().unwrap().months as i64
    }

    /// Takes the newest finished month, if any. True when it is new; then
    /// clock and textures should be updated.
    #[func]
    fn refresh(&mut self) -> bool {
        let Some((snap, usec)) = self.shared.latest.lock().unwrap().take() else { return false };
        self.snap = Some(snap);
        self.last_step_usec = usec;
        true
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

    /// Waits for the sim thread's current month (debug and tests only).
    #[func]
    fn fingerprint(&self) -> GString {
        self.sim.as_ref().map_or(GString::new(), |s| format!("{:016x}", s.lock().unwrap().fingerprint()).as_str().into())
    }

    /// Wall time of the last finished month on the sim thread, in microseconds.
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
        let (c0, r0, _, _) = self.map.as_ref().map_or((0, 0, 0, 0), |m| m.grid);
        Vector2::new((c0 as f64 * cell_m()) as f32, (r0 as f64 * cell_m()) as f32)
    }

    /// Edge of one index page in cells.
    #[func]
    fn index_page_cells(&self) -> i64 {
        PAGE as i64
    }

    /// Index pages per row; page (x, y) is layer y * pages_x + x.
    #[func]
    fn index_pages_x(&self) -> i64 {
        self.map.as_ref().map_or(0, |m| m.pages_x as i64)
    }

    /// Layers of the index texture array.
    #[func]
    fn index_layers(&self) -> i64 {
        self.map.as_ref().map_or(0, |m| m.layers() as i64)
    }

    /// Brings the index to the current snapshot and returns the layers that
    /// changed since the last call (all of them after a new game). Only
    /// these need `index_page` and a layer upload.
    #[func]
    fn index_dirty_pages(&mut self) -> PackedInt32Array {
        self.sync_map();
        self.map.as_mut().map_or_else(PackedInt32Array::new, |m| PackedInt32Array::from(m.take_dirty()))
    }

    /// One index page: slot + 1 per cell as an RF image (0 = no tile).
    #[func]
    fn index_page(&self, layer: i64) -> Option<Gd<Image>> {
        let m = self.map.as_ref()?;
        if layer < 0 || layer as usize >= m.layers() {
            return None;
        }
        let mut bytes = PackedByteArray::new();
        bytes.resize(PAGE * PAGE * 4);
        m.page_bytes(layer as usize, bytes.as_mut_slice());
        Image::create_from_data(PAGE as i32, PAGE as i32, false, Format::RF, &bytes)
    }

    /// Per slot (population, population per km²) as an RGF image,
    /// `VALUE_WIDTH` slots per row. Its height grows in steps, so the same
    /// texture can be updated in place for a long time.
    #[func]
    fn value_image(&mut self) -> Option<Gd<Image>> {
        self.sync_map();
        let snap = self.snap.as_ref()?;
        let m = self.map.as_ref()?;
        let h = m.slot_count().div_ceil(VALUE_WIDTH).max(1).next_multiple_of(VALUE_ROW_STEP);
        let mut bytes = PackedByteArray::new();
        bytes.resize(VALUE_WIDTH * h * 8);
        let out = bytes.as_mut_slice();
        for (t, &s) in snap.tiles.iter().zip(m.slot_of_tile()) {
            let d = if t.land_km2 > 0.0 { t.pop / t.land_km2 } else { 0.0 };
            let o = s as usize * 8;
            out[o..o + 4].copy_from_slice(&(t.pop as f32).to_le_bytes());
            out[o + 4..o + 8].copy_from_slice(&(d as f32).to_le_bytes());
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
        let (Some(snap), Some(m)) = (self.snap.as_ref(), self.map.as_ref()) else { return d };
        if m.structure != Some(snap.structure) {
            return d;
        }
        let (c0, r0, _, _) = m.grid;
        let (c, r) = ((x_m / cell_m()).floor() as i64 - c0, (z_m / cell_m()).floor() as i64 - r0);
        let Some(t) = m.tile_at_cell(c, r).and_then(|i| snap.tiles.get(i)) else { return d };
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

impl ApoleiaSim {
    /// Hands a game to a new sim thread (after stopping the old one).
    fn start(&mut self, mut sim: Sim) {
        let snap = sim.snapshot();
        self.map = Some(MapIndex::new(&snap));
        self.stop();
        let sim = Arc::new(Mutex::new(sim));
        let shared = Arc::new(Shared::default());
        let (s, sh) = (sim.clone(), shared.clone());
        self.worker = Some(std::thread::Builder::new().name("apoleia-sim".into()).spawn(move || run(s, sh)).expect("sim thread"));
        self.sim = Some(sim);
        self.shared = shared;
        self.snap = Some(snap);
    }

    fn sync_map(&mut self) {
        if let (Some(m), Some(snap)) = (self.map.as_mut(), self.snap.as_ref()) {
            m.sync(snap);
        }
    }

    fn stop(&mut self) {
        if let Some(w) = self.worker.take() {
            self.shared.queue.lock().unwrap().quit = true;
            self.shared.wake.notify_one();
            let _ = w.join();
        }
    }
}

impl Drop for ApoleiaSim {
    fn drop(&mut self) {
        self.stop();
    }
}
