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

use apoleia_sim::people::People;
use apoleia_sim::view::{PeopleView, PAGE, REC};
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
}

#[derive(Default)]
struct Shared {
    queue: Mutex<(u64, bool)>,
    wake: Condvar,
    front: Mutex<Front>,
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

fn run(mut people: People, mut view: PeopleView, shared: Arc<Shared>) {
    loop {
        {
            let mut q = shared.queue.lock().unwrap();
            while q.0 == 0 && !q.1 {
                q = shared.wake.wait(q).unwrap();
            }
            if q.1 {
                return;
            }
            q.0 -= 1;
        }
        let t0 = Instant::now();
        people.day();
        let day_usec = t0.elapsed().as_secs_f64() * 1e6;
        let t1 = Instant::now();
        let pages = view.update(&mut people);
        let view_usec = t1.elapsed().as_secs_f64() * 1e6;
        let mut f = shared.front.lock().unwrap();
        publish(&view, &pages, &mut f);
        f.day += 1;
        f.count = people.count;
        f.day_usec = day_usec;
        f.view_usec = view_usec;
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
        let mut view = PeopleView::new(&people, &inp.cities);
        let pages = view.update(&mut people);
        let shared = Arc::new(Shared::default());
        {
            let mut f = shared.front.lock().unwrap();
            publish(&view, &pages, &mut f);
            f.count = people.count;
        }
        let sh = shared.clone();
        self.worker = Some(std::thread::Builder::new().name("apoleia-people".into()).spawn(move || run(people, view, sh)).expect("people thread"));
        self.shared = shared;
        self.data.clear();
        self.pages = 0;
        true
    }

    /// Queues days for the sim thread and returns at once.
    #[func]
    fn advance(&mut self, days: i64) {
        if self.worker.is_none() || days <= 0 {
            return;
        }
        self.shared.queue.lock().unwrap().0 += days as u64;
        self.shared.wake.notify_one();
    }

    /// Days queued but not yet computed.
    #[func]
    fn backlog(&self) -> i64 {
        self.shared.queue.lock().unwrap().0 as i64
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
        let src = self.data.get(pg * PAGE * REC..(pg + 1) * PAGE * REC)?;
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
        drop(f);
        d.set("sync_usec", self.upload_usec);
        d.set("sync_layers", self.uploaded_pages);
        d
    }
}

impl ApoleiaPeople {
    fn stop(&mut self) {
        if let Some(w) = self.worker.take() {
            self.shared.queue.lock().unwrap().1 = true;
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
