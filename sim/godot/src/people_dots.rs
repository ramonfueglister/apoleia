//! Every simulated person as a dot (S45, S46): `ApoleiaPeople` runs the
//! people prototype (crate::people) on its own thread, one day at a time,
//! and keeps a presentation view (crate::view) beside it. After each day
//! the sim thread copies only the changed pages of the view into the front
//! buffer; the main thread takes those pages and uploads them as layers of
//! one RGBA32F texture array. The renderer draws all people with a single
//! instanced draw that reads its dot from that texture (people_dots.gdshader),
//! so the CPU never touches a per-dot transform.
//!
//! The frame never waits for a day: the sim thread holds the front buffer
//! only for the copy of the changed pages, and the main thread only for
//! taking them.

use crate::grain_map::{GrainMap, MapLayers, FINE};
use apoleia_sim::grain::{Grain, HouseholdLook, FARM_KIND_NAMES, KIND_NAMES};
use apoleia_sim::people::{Clock, People};
use apoleia_sim::groups::{JOB_GROUP, JOB_NAMES, POLITICAL_NAMES};
use apoleia_sim::view::{PeopleView, Person, PAGE, REC, ROAD};
use godot::classes::image::Format;
use godot::classes::{Image, Texture2DArray};
use godot::prelude::*;
use std::path::Path;
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::Instant;

/// Edge of one page in texels (PAGE = SIDE²).
const SIDE: usize = 64;

#[derive(Default)]
struct Front {
    data: Vec<f32>,
    dirty: Vec<bool>,
    day: i64,
    count: u32,
    day_usec: f64,
    view_usec: f64,
    /// The houses (view::Houses), same scheme.
    houses: Vec<f32>,
    house_dirty: Vec<bool>,
    house_count: u32,
    /// Answer to the last `ask_person`, with the household as the grain
    /// economy sees it.
    person: Option<(Person, Option<HouseholdLook>)>,
    grain_usec: f64,
    /// The grain economy's map layers as of the last month.
    map: MapLayers,
}

/// Work for the sim thread: days to run, stop, a slot whose person to look up.
#[derive(Default)]
struct Queue {
    days: u64,
    stop: bool,
    ask: Option<usize>,
}

#[derive(Default)]
struct Shared {
    queue: Mutex<Queue>,
    wake: Condvar,
    front: Mutex<Front>,
}

fn publish_houses(view: &mut PeopleView, f: &mut Front) {
    let pages = view.take_house_pages();
    let h = &view.houses;
    if f.houses.len() != h.data.len() {
        f.houses.resize(h.data.len(), 0.0);
        f.house_dirty.resize(h.pages(), false);
    }
    for pg in pages {
        let pg = pg as usize;
        f.houses[pg * PAGE * REC..(pg + 1) * PAGE * REC].copy_from_slice(h.page(pg));
        f.house_dirty[pg] = true;
    }
    f.house_count = h.count() as u32;
}

fn publish(view: &PeopleView, pages: &[u32], f: &mut Front) {
    if f.data.len() != view.data.len() {
        f.data.resize(view.data.len(), 0.0);
        f.dirty.resize(view.pages(), false);
    }
    for &pg in pages {
        let pg = pg as usize;
        f.data[pg * PAGE * REC..(pg + 1) * PAGE * REC].copy_from_slice(view.page(pg));
        f.dirty[pg] = true;
    }
}

/// Edge of a 25 km cell and of a fine tile, km.
const CELL_KM: f32 = 25.0;
const FINE_KM: f32 = CELL_KM / FINE as f32;

fn run(mut people: People, mut grain: Grain, mut map: GrainMap, mut view: PeopleView, shared: Arc<Shared>) {
    loop {
        let ask = {
            let mut q = shared.queue.lock().unwrap();
            while q.days == 0 && !q.stop && q.ask.is_none() {
                q = shared.wake.wait(q).unwrap();
            }
            if q.stop {
                return;
            }
            let ask = q.ask.take();
            if ask.is_none() {
                q.days -= 1;
            }
            ask
        };
        if let Some(slot) = ask {
            let who = view.pid_at(slot).and_then(|pid| PeopleView::person(&mut people, pid));
            let who = who.map(|p| {
                let hh = grain.household(p.household);
                (p, hh)
            });
            shared.front.lock().unwrap().person = who;
            continue;
        }
        let t0 = Instant::now();
        people.day();
        let day_usec = t0.elapsed().as_secs_f64() * 1e6;
        // the grain economy (S69–S87) on the same day, as bin/grain.rs
        let tg = Instant::now();
        grain.day(&mut people);
        let grain_usec = tg.elapsed().as_secs_f64() * 1e6;
        let today = people.world.resource::<Clock>().day;
        let month = today % 30 == 0;
        if month {
            map.build(&grain, today);
        }
        let t1 = Instant::now();
        let pages = view.update(&mut people);
        let view_usec = t1.elapsed().as_secs_f64() * 1e6;
        let mut f = shared.front.lock().unwrap();
        publish(&view, &pages, &mut f);
        publish_houses(&mut view, &mut f);
        f.day += 1;
        f.count = people.count;
        f.day_usec = day_usec;
        f.view_usec = view_usec;
        f.grain_usec = grain_usec;
        if month {
            f.map = map.layers.clone();
        }
    }
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct ApoleiaPeople {
    shared: Arc<Shared>,
    worker: Option<JoinHandle<()>>,
    /// Main-thread copy of the records (the back buffer of the GPU texture).
    data: Vec<f32>,
    pages: usize,
    /// Main-thread copy of the house records.
    houses: Vec<f32>,
    day: i64,
    count: u32,
    day_usec: f64,
    view_usec: f64,
    upload_usec: f64,
    uploaded_pages: i64,
    base: Base<RefCounted>,
}

#[godot_api]
impl ApoleiaPeople {
    /// Loads the inputs below `repo_root`, spawns the start population and
    /// starts the sim thread. Returns false when the inputs are missing.
    #[func]
    fn load(&mut self, repo_root: GString, seed: i64) -> bool {
        let inp = match apoleia_sim::inputs::load(Path::new(&repo_root.to_string()), false) {
            Ok(d) => d,
            Err(e) => {
                godot_error!("ApoleiaPeople.load: {e}");
                return false;
            }
        };
        self.stop();
        let mut people = People::new(&inp, seed as u64);
        // villages on the farmland of the fine tiles; without the file on
        // hashed tiles of each cell
        let root = repo_root.to_string();
        let cover = match apoleia_sim::grain::fine_cover(Path::new(&root), true) {
            Ok(c) => Some(c),
            Err(e) => {
                godot_warn!("ApoleiaPeople: no fine land cover ({e}), villages on hashed tiles");
                None
            }
        };
        // the grain economy with the defaults of bin/grain.rs: today's
        // farmland clearable, fields on the fine tiles
        let cols: Vec<String> = apoleia_sim::grain::CLEAR_COVER.iter().map(|c| c.to_string()).collect();
        let clear = match apoleia_sim::grain::clearable(Path::new(&root), &cols) {
            Ok(c) => Some(c),
            Err(e) => {
                godot_warn!("ApoleiaPeople: no landcover25.csv ({e}), all usable land clearable");
                None
            }
        };
        let tg = Instant::now();
        let grain = Grain::with_clearing(&inp, &mut people, apoleia_sim::grain::CLEAR_PCT, clear.as_ref(), cover.as_ref(), apoleia_sim::grain::CROP_PCT);
        let grain_ms = tg.elapsed().as_secs_f64() * 1e3;
        let mut map = GrainMap::new(&people);
        map.build(&grain, people.world.resource::<Clock>().day);
        let mut view = PeopleView::new(&people, &inp.cities, cover.as_ref());
        let pages = view.update(&mut people);
        let shared = Arc::new(Shared::default());
        {
            let mut f = shared.front.lock().unwrap();
            publish(&view, &pages, &mut f);
            publish_houses(&mut view, &mut f);
            f.count = people.count;
            f.map = map.layers.clone();
        }
        godot_print!("{{\"event\":\"grain_loaded\",\"ms\":{grain_ms:.0},\"markets\":{}}}", grain.markets.len());
        let sh = shared.clone();
        self.worker = Some(std::thread::Builder::new().name("apoleia-people".into()).spawn(move || run(people, grain, map, view, sh)).expect("people thread"));
        self.shared = shared;
        self.data.clear();
        self.houses.clear();
        self.pages = 0;
        true
    }

    /// Queues days for the sim thread and returns at once.
    #[func]
    fn advance(&mut self, days: i64) {
        if self.worker.is_none() || days <= 0 {
            return;
        }
        self.shared.queue.lock().unwrap().days += days as u64;
        self.shared.wake.notify_one();
    }

    /// Days queued but not yet computed.
    #[func]
    fn backlog(&self) -> i64 {
        self.shared.queue.lock().unwrap().days as i64
    }

    /// Layers the texture array needs (pages of 4096 people).
    #[func]
    fn layers(&self) -> i64 {
        self.shared.front.lock().unwrap().dirty.len().max(1) as i64
    }

    #[func]
    fn page_side(&self) -> i64 {
        SIDE as i64
    }

    /// Takes the changed pages from the sim thread and writes them into
    /// `texture`. Returns the number of layers uploaded, or -1 when the
    /// texture has the wrong layer count (then call `make_texture`).
    #[func]
    fn sync(&mut self, mut texture: Gd<Texture2DArray>) -> i64 {
        let t0 = Instant::now();
        let changed: Vec<usize> = {
            let mut f = self.shared.front.lock().unwrap();
            if f.dirty.len() != texture.get_layers() as usize {
                return -1;
            }
            self.day = f.day;
            self.count = f.count;
            self.day_usec = f.day_usec;
            self.view_usec = f.view_usec;
            if self.data.len() != f.data.len() {
                self.data.resize(f.data.len(), 0.0);
            }
            let mut out = Vec::new();
            for pg in 0..f.dirty.len() {
                if std::mem::take(&mut f.dirty[pg]) {
                    let r = pg * PAGE * REC..(pg + 1) * PAGE * REC;
                    self.data[r.clone()].copy_from_slice(&f.data[r]);
                    out.push(pg);
                }
            }
            out
        };
        for &pg in &changed {
            if let Some(img) = self.page_image(pg) {
                texture.update_layer(&img, pg as i32);
            }
        }
        self.upload_usec = t0.elapsed().as_secs_f64() * 1e6;
        self.uploaded_pages = changed.len() as i64;
        changed.len() as i64
    }

    /// A new texture array with all pages (after load or when the people
    /// outgrow the layers).
    #[func]
    fn make_texture(&mut self) -> Option<Gd<Texture2DArray>> {
        {
            let mut f = self.shared.front.lock().unwrap();
            self.data.clone_from(&f.data);
            f.dirty.fill(false);
            self.day = f.day;
            self.count = f.count;
        }
        self.pages = self.data.len() / (PAGE * REC);
        let mut images: Array<Gd<Image>> = Array::new();
        for pg in 0..self.pages.max(1) {
            images.push(&self.page_image(pg).unwrap_or_else(|| Image::create_empty(SIDE as i32, SIDE as i32, false, Format::RGBAF).unwrap()));
        }
        let mut tex = Texture2DArray::new_gd();
        tex.create_from_images(&images);
        Some(tex)
    }

    fn page_image(&self, pg: usize) -> Option<Gd<Image>> {
        page_image(&self.data, pg)
    }

    /// The slot of the dot nearest to `pixel` within `max_px`, or -1.
    /// `place` is the placement texture (people_dots_prep, RGBAH or RGBAF),
    /// `view_proj` the camera's projection × view matrix as 16 floats,
    /// column by column, `level_h` the terrain's height per level, `lift`
    /// how far above the ground the drawn person's middle is (world units).
    #[func]
    fn pick(&self, place: Gd<Image>, view_proj: PackedFloat32Array, viewport: Vector2, pixel: Vector2, level_h: f32, lift: f32, max_px: f32) -> i64 {
        let m = view_proj.as_slice();
        if m.len() != 16 {
            return -1;
        }
        let half = match place.get_format() {
            Format::RGBAH => true,
            Format::RGBAF => false,
            _ => return -1,
        };
        let bytes = place.get_data();
        let bytes = bytes.as_slice();
        let (w, h) = (place.get_width() as usize, place.get_height() as usize);
        let texel = |i: usize, c: usize| -> f32 {
            if half {
                let o = (i * 4 + c) * 2;
                f16_to_f32(u16::from_le_bytes([bytes[o], bytes[o + 1]]))
            } else {
                let o = (i * 4 + c) * 4;
                f32::from_le_bytes([bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]])
            }
        };
        let side = SIDE;
        let mut best = (-1i64, max_px * max_px);
        for slot in 0..self.data.len() / REC {
            let rec = &self.data[slot * REC..slot * REC + REC];
            if rec[2] == 0.0 {
                continue;
            }
            // slot → pixel of the placement texture, as in people_dots_prep
            let (layer, in_page) = (slot / PAGE, slot % PAGE);
            let (px, py) = (in_page % side, layer * side + in_page / side);
            if px >= w || py >= h {
                continue;
            }
            let i = py * w + px;
            if texel(i, 3) < 0.5 {
                continue;
            }
            let v = [rec[0] + texel(i, 0) - 32.0, texel(i, 2) * level_h + lift, rec[1] + texel(i, 1) - 32.0, 1.0];
            let row = |r: usize| m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] * v[3];
            let cw = row(3);
            if cw <= 0.0 {
                continue;
            }
            let sx = (row(0) / cw * 0.5 + 0.5) * viewport.x;
            let sy = (0.5 - row(1) / cw * 0.5) * viewport.y;
            let d = (sx - pixel.x).powi(2) + (sy - pixel.y).powi(2);
            if d < best.1 {
                best = (slot as i64, d);
            }
        }
        best.0
    }

    /// Slots of the people whose dot can lie within `radius` km of (x, z)
    /// (world km), at most `max`, nearest anchors first: the people drawn
    /// as figures up close. Anchors are the records' centres; the margin
    /// covers how far the placement pass moves a person from it (village
    /// tile and house, city disk, a traveller anywhere in the cell).
    #[func]
    fn near(&self, x: f32, z: f32, radius: f32, max: i64) -> PackedInt32Array {
        let mut hits: Vec<(f32, i32)> = Vec::new();
        for slot in 0..self.data.len() / REC {
            let rec = &self.data[slot * REC..slot * REC + REC];
            let area = rec[2];
            if area == 0.0 {
                continue;
            }
            let margin = if area < 0.0 { -area } else if area >= ROAD { 18.0 } else { 1.8 };
            let d2 = (rec[0] - x).powi(2) + (rec[1] - z).powi(2);
            let reach = radius + margin;
            if d2 <= reach * reach {
                hits.push((d2, slot as i32));
            }
        }
        if hits.len() > max.max(0) as usize {
            hits.select_nth_unstable_by(max as usize, |a, b| a.0.total_cmp(&b.0));
            hits.truncate(max as usize);
        }
        PackedInt32Array::from_iter(hits.into_iter().map(|h| h.1))
    }

    /// Slots of the houses within `radius` km of (x, z), nearest first, at
    /// most `max` (the houses drawn, nearest in the finest detail). A house
    /// stands within 1.8 km of its record's anchor (village tile).
    #[func]
    fn houses_near(&self, x: f32, z: f32, radius: f32, max: i64) -> PackedInt32Array {
        let mut hits: Vec<(f32, i32)> = Vec::new();
        let reach = radius + 1.8;
        for slot in 0..self.houses.len() / REC {
            let rec = &self.houses[slot * REC..slot * REC + REC];
            if rec[2] == 0.0 {
                continue;
            }
            let d2 = (rec[0] - x).powi(2) + (rec[1] - z).powi(2);
            if d2 <= reach * reach {
                hits.push((d2, slot as i32));
            }
        }
        let max = max.max(0) as usize;
        if hits.len() > max {
            hits.select_nth_unstable_by(max, |a, b| a.0.total_cmp(&b.0));
            hits.truncate(max);
        }
        hits.sort_unstable_by(|a, b| a.0.total_cmp(&b.0));
        PackedInt32Array::from_iter(hits.into_iter().map(|h| h.1))
    }

    /// Asks the sim thread for the person in `slot`; the answer comes with
    /// `take_person` (between two days, so within a frame or two).
    #[func]
    fn ask_person(&mut self, slot: i64) {
        if self.worker.is_none() || slot < 0 {
            return;
        }
        self.shared.front.lock().unwrap().person = None;
        self.shared.queue.lock().unwrap().ask = Some(slot as usize);
        self.shared.wake.notify_one();
    }

    /// The person asked for, once; empty until the sim thread answered.
    #[func]
    fn take_person(&mut self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some((p, hh)) = self.shared.front.lock().unwrap().person.take() else {
            return d;
        };
        if let Some(h) = hh {
            d.set("hh_kind", KIND_NAMES[h.kind as usize]);
            d.set("fed", h.fed as i64);
            d.set("pantry_kg", h.pantry_kg);
            if let Some((kind, m2)) = h.farm {
                d.set("farm_kind", FARM_KIND_NAMES[kind as usize]);
                // field m² are per simulated person (PEOPLE_PER_PERSON)
                d.set("farm_ha", m2 as f64 / 1e4);
            }
        }
        d.set("pid", p.pid as i64);
        d.set("age", p.age);
        d.set("female", p.female);
        d.set("household", p.household as i64);
        d.set("members", p.members as i64);
        d.set("home", p.home as i64);
        d.set("job", p.job);
        d.set("group", p.group);
        d.set("factions", &PackedStringArray::from_iter(p.factions.iter().map(|f| GString::from(*f))));
        d.set("stand", p.stand as i64);
        d.set("health", p.health as i64);
        d.set("culture", p.culture as i64);
        d.set("religion", p.religion as i64);
        d.set("iq", p.iq.unwrap_or(-1.0));
        d.set("spouse", p.spouse.map_or(-1, |s| s as i64));
        d.set("travelling", p.travelling.map_or(0, |leave| if leave { 2 } else { 1 }));
        d
    }

    /// Names for the colour legend: occupations, political groups and the
    /// political group of each occupation (crate::groups).
    #[func]
    fn legend(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        d.set("jobs", &PackedStringArray::from_iter(JOB_NAMES.iter().map(|s| GString::from(*s))));
        d.set("groups", &PackedStringArray::from_iter(POLITICAL_NAMES.iter().map(|s| GString::from(*s))));
        d.set("job_group", &PackedInt32Array::from_iter(JOB_GROUP.iter().map(|&g| g as i32)));
        d
    }

    /// Takes the changed house pages and writes them into `texture`, like
    /// `sync`. Returns the layers uploaded or -1 (then `make_house_texture`).
    #[func]
    fn sync_houses(&mut self, mut texture: Gd<Texture2DArray>) -> i64 {
        let changed: Vec<usize> = {
            let mut f = self.shared.front.lock().unwrap();
            if f.house_dirty.len().max(1) != texture.get_layers() as usize {
                return -1;
            }
            if self.houses.len() != f.houses.len() {
                self.houses.resize(f.houses.len(), 0.0);
            }
            let mut out = Vec::new();
            for pg in 0..f.house_dirty.len() {
                if std::mem::take(&mut f.house_dirty[pg]) {
                    let r = pg * PAGE * REC..(pg + 1) * PAGE * REC;
                    self.houses[r.clone()].copy_from_slice(&f.houses[r]);
                    out.push(pg);
                }
            }
            out
        };
        for &pg in &changed {
            if let Some(img) = page_image(&self.houses, pg) {
                texture.update_layer(&img, pg as i32);
            }
        }
        changed.len() as i64
    }

    /// A new texture array with all house pages.
    #[func]
    fn make_house_texture(&mut self) -> Option<Gd<Texture2DArray>> {
        {
            let mut f = self.shared.front.lock().unwrap();
            self.houses.clone_from(&f.houses);
            f.house_dirty.fill(false);
        }
        let pages = self.houses.len() / (PAGE * REC);
        let mut images: Array<Gd<Image>> = Array::new();
        for pg in 0..pages.max(1) {
            images.push(&page_image(&self.houses, pg).unwrap_or_else(|| Image::create_empty(SIDE as i32, SIDE as i32, false, Format::RGBAF).unwrap()));
        }
        let mut tex = Texture2DArray::new_gd();
        tex.create_from_images(&images);
        Some(tex)
    }

    /// Houses standing (one per village household).
    #[func]
    fn house_count(&self) -> i64 {
        self.shared.front.lock().unwrap().house_count as i64
    }

    /// Rebuild count of the grain map layers (once a month).
    #[func]
    fn map_version(&self) -> i64 {
        self.shared.front.lock().unwrap().map.version as i64
    }

    /// The fine grain layer (crate::grain_map) for `n` × `n` tiles of
    /// 1.5625 km around (x, z) world km: {"image": RGBA8 Image, "origin":
    /// world km of its first texel's corner, "tile_km"}.
    #[func]
    fn map_window(&self, x: f32, z: f32, n: i64) -> VarDictionary {
        let map = self.shared.front.lock().unwrap().map.clone();
        let n = n.clamp(1, 4096) as i32;
        let fr0 = (z / FINE_KM).floor() as i32 - map.row0 * FINE - n / 2;
        let fc0 = (x / FINE_KM).floor() as i32 - map.col0 * FINE - n / 2;
        let bytes = PackedByteArray::from(map.window(fr0, fc0, n));
        let mut d = VarDictionary::new();
        if let Some(img) = Image::create_from_data(n, n, false, Format::RGBA8, &bytes) {
            d.set("image", &img);
        }
        d.set("origin", Vector2::new((fc0 + map.col0 * FINE) as f32 * FINE_KM, (fr0 + map.row0 * FINE) as f32 * FINE_KM));
        d.set("tile_km", FINE_KM);
        d
    }

    /// The trade roads and sea lanes, one RG8 texel per 25 km cell:
    /// {"image", "origin" world km of the grid corner, "cell_km"}.
    #[func]
    fn road_map(&self) -> VarDictionary {
        let map = self.shared.front.lock().unwrap().map.clone();
        let mut d = VarDictionary::new();
        if map.roads.len() == (map.rows * map.cols * 2) as usize && map.rows > 0 {
            let bytes = PackedByteArray::from(map.roads.as_slice());
            if let Some(img) = Image::create_from_data(map.cols, map.rows, false, Format::RG8, &bytes) {
                d.set("image", &img);
            }
        }
        d.set("origin", Vector2::new(map.col0 as f32 * CELL_KM, map.row0 as f32 * CELL_KM));
        d.set("cell_km", CELL_KM);
        d
    }

    /// Simulated days so far (the sim thread's, also while no dots show).
    #[func]
    fn day(&self) -> i64 {
        self.shared.front.lock().unwrap().day
    }

    /// People alive after that day.
    #[func]
    fn count(&self) -> i64 {
        self.shared.front.lock().unwrap().count as i64
    }

    /// Timings in microseconds: the last sim day and view update (sim
    /// thread), the last `sync` (main thread) and the layers it uploaded.
    #[func]
    fn timings(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let f = self.shared.front.lock().unwrap();
        d.set("day_usec", f.day_usec);
        d.set("view_usec", f.view_usec);
        d.set("grain_usec", f.grain_usec);
        drop(f);
        d.set("sync_usec", self.upload_usec);
        d.set("sync_layers", self.uploaded_pages);
        d
    }
}

impl ApoleiaPeople {
    fn stop(&mut self) {
        if let Some(w) = self.worker.take() {
            self.shared.queue.lock().unwrap().stop = true;
            self.shared.wake.notify_one();
            let _ = w.join();
        }
    }
}

impl Drop for ApoleiaPeople {
    fn drop(&mut self) {
        self.stop();
    }
}

/// IEEE half to float (the placement texture is RGBA16F).
fn f16_to_f32(h: u16) -> f32 {
    let sign = ((h >> 15) as u32) << 31;
    let exp = ((h >> 10) & 0x1f) as u32;
    let man = (h & 0x3ff) as u32;
    let bits = match exp {
        0 if man == 0 => sign,
        0 => {
            // subnormal: normalise
            let mut e = 127 - 15 + 1;
            let mut m = man;
            while m & 0x400 == 0 {
                m <<= 1;
                e -= 1;
            }
            sign | (e as u32) << 23 | (m & 0x3ff) << 13
        }
        31 => sign | 0x7f80_0000 | man << 13,
        _ => sign | (exp + 127 - 15) << 23 | man << 13,
    };
    f32::from_bits(bits)
}

/// One page of records as an RGBAF image (64 × 64 texels).
fn page_image(data: &[f32], pg: usize) -> Option<Gd<Image>> {
    let src = data.get(pg * PAGE * REC..(pg + 1) * PAGE * REC)?;
    let mut bytes = PackedByteArray::new();
    bytes.resize(PAGE * REC * 4);
    // f32 records as little-endian bytes (RGBAF); every target we ship
    // is little-endian, so this is one memcpy.
    #[cfg(target_endian = "little")]
    bytes.as_mut_slice().copy_from_slice(unsafe { std::slice::from_raw_parts(src.as_ptr().cast::<u8>(), src.len() * 4) });
    #[cfg(target_endian = "big")]
    for (o, v) in bytes.as_mut_slice().chunks_exact_mut(4).zip(src) {
        o.copy_from_slice(&v.to_le_bytes());
    }
    Image::create_from_data(SIDE as i32, SIDE as i32, false, Format::RGBAF, &bytes)
}
