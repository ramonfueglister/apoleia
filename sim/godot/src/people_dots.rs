//! Every simulated person as a dot (S45, S46): `ApoleiaPeople` runs the
//! people prototype (crate::people) on its own thread, one day at a time,
//! and keeps a presentation view (crate::view) beside it. After each day
//! the sim thread copies only the changed pages of the view into the front
//! buffer; the main thread takes those pages and uploads them as layers of
//! one RGBA32F texture array. The renderer draws all people with a single
//! instanced draw that reads its dot from that texture (people_dots.gdshader),
//! so the CPU never touches a per-dot transform.
//!
//! The sim thread owns one apoleia_sim::game::Game: the people, the grain
//! economy and the build orders. Commands from the build menu and save games
//! go through the same queue as the days and are handled between two days;
//! loading a save plays it again on a new sim thread (docs/kit1/
//! REALTIME_GAMEPLAY.md phase 4).
//!
//! The frame never waits for a day: the sim thread holds the front buffer
//! only for the copy of the changed pages, and the main thread only for
//! taking them.

use crate::grain_map::{GrainMap, MapJob, MapLayers, MapThread, FINE, MARKET_BIT};
use crate::{tables, trips};
use apoleia_sim::build::{self, Command, Orders};
use apoleia_sim::game::{Game, Loaded, Start};
use apoleia_sim::grain::{Clearable, CraftsView, EventsView, FineCover, GoodsMovesView, HouseholdLook, TripsView, WorkView, FARM_KIND_NAMES, GOODS, KIND_NAMES};
use apoleia_sim::groups::{JOB_GROUP, JOB_NAMES, POLITICAL_NAMES};
use apoleia_sim::tables::{Table, Values};
use apoleia_sim::view::{PeopleView, Person, PAGE, REC, ROAD};
use godot::classes::image::Format;
use godot::classes::{Image, Texture2DArray};
use godot::prelude::*;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

/// Edge of one page in texels (PAGE = SIDE²).
const SIDE: usize = 64;
/// Farmhouse builds (scripts/voxel/farmhouse.gd VARIANTS).
const HOUSE_VARIANTS: u8 = 4;
/// A house the placement pass did not place: never drawn.
const HOUSE_UNPLACED: u8 = 254;
/// A house newer than the last placement read back.
const HOUSE_UNKNOWN: u8 = 255;
/// How often a second the view is updated at most while the sim runs
/// behind the days asked for.
const VIEW_HZ: f64 = 30.0;

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
    /// Answer to the last `ask_table` (built between two days).
    table: Option<Table>,
    /// Answer to the last `ask_trips` (built between two days).
    trips: Option<TripsView>,
    /// Answer to the last `ask_work`.
    work: Option<WorkView>,
    /// Answer to the last `ask_events`.
    events: Option<EventsView>,
    /// Answer to the last `ask_goods`: workshops, markets' goods, goods
    /// moves (trips::goods_to_dict).
    goods: Option<(CraftsView, Vec<((f32, f32), [(f32, f32); GOODS])>, GoodsMovesView)>,
    grain_usec: f64,
    /// The grain economy's map layers as of the last month.
    map: MapLayers,
    /// The player's build orders, as of the last command applied.
    orders: Orders,
    /// How far each order's building site is (S113), in the orders' tile
    /// order: column, row, work days done, work days needed (0, 0 while
    /// it has no site or nobody builds it).
    progress: Vec<i32>,
    /// The finished roads (S113), x and z of each lot in world metres; their
    /// orders are gone, so the map draws them from here.
    roads: Vec<i32>,
    /// The finished fields (S116), x and z of each lot in world metres:
    /// state land, drawn as fields once a farm leases it.
    fields: Vec<i32>,
    /// Bumped whenever `orders` or `progress` go out; carried over to the
    /// game a save starts, so the build menu never misses a change.
    built: u64,
    /// Answer to the last `ask_build_check`.
    check: Option<BuildCheck>,
    /// Answer to the last `ask_sites`: x, z, kind, progress, width, depth.
    sites: Option<Vec<f32>>,
    /// Answer to the last `ask_market`: the market and its row of the
    /// markets table (None when there is no such market).
    market: Option<(usize, Option<Table>)>,
    /// While a save game plays again: the day reached and the day saved.
    loading: Option<(i64, i64)>,
    /// How the last save game played again, once.
    loaded: Option<Loaded>,
    /// Answer to the last `save_game`: the day saved, or what went wrong.
    saved: Option<Result<i64, String>>,
    /// The treasury's cash after the last day, milli-denarii.
    cash: i64,
    /// Milliseconds the sim thread spent on its days so far: the day
    /// itself, orders and map layers, the view, handing over; and the days.
    spent: [f64; 4],
    spent_days: u64,
}

/// Whom `ask_person` and its kin look up: the person in a view slot (a
/// dot or figure clicked), a person by id (a carrier or trader on the
/// road), or a member of a household (a day labourer on the way to work).
#[derive(Clone, Copy)]
enum Who {
    Slot(usize),
    Pid(u32),
    Household(u32),
}

/// Work for the sim thread: days to run, stop, whose person to look up, a table to build (apoleia_sim::tables), a window (world km, min x,
/// min z, max x, max z) whose trips under way to list.
#[derive(Default)]
struct Queue {
    days: u64,
    stop: bool,
    ask: Option<Who>,
    table: Option<String>,
    trips: Option<[f64; 4]>,
    work: Option<[f64; 4]>,
    /// The day after which, and the window.
    events: Option<(i64, [f64; 4])>,
    /// Build menu commands (apoleia_sim::build), applied in order.
    commands: Vec<Command>,
    /// Where to write a save game, between two days.
    save: Option<String>,
    /// Orders to check before they are placed: kind and tiles.
    check: Option<(u8, Vec<build::Tile>)>,
    /// A window (world km) whose workshops, market goods and goods moves to list.
    goods: Option<[f64; 4]>,
    /// A window (world km) whose building sites to list.
    sites: Option<[f64; 4]>,
    /// A market whose row of the markets table to give.
    market: Option<usize>,
}

impl Queue {
    fn asked(&self) -> bool {
        !self.commands.is_empty() || self.save.is_some() || self.check.is_some() || self.ask.is_some() || self.table.is_some() || self.trips.is_some() || self.work.is_some() || self.events.is_some() || self.goods.is_some() || self.sites.is_some() || self.market.is_some()
    }
}

#[derive(Default)]
struct Shared {
    queue: Mutex<Queue>,
    wake: Condvar,
    front: Mutex<Front>,
    /// The farms' building sites go into the house records
    /// (`show_site_houses`; off until the house shader draws them).
    site_houses: AtomicBool,
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

/// (column, row) pairs from Godot as (row, column) tiles; an odd last
/// number is dropped.
fn pairs(a: &PackedInt32Array) -> Vec<build::Tile> {
    a.as_slice().chunks_exact(2).map(|p| (p[1], p[0])).collect()
}

/// Edge of a 25 km cell and of a fine tile, km.
const CELL_KM: f32 = 25.0;
const FINE_KM: f32 = CELL_KM / FINE as f32;
/// A village lot, the grid build orders sit on (app/scripts/sim/people_dots.gd
/// LOT_KM, build::Tile).
const LOT_KM: f32 = 0.5;

/// What a game starts from besides its seed (apoleia_sim::game::Start),
/// read from below the repository root.
struct Data {
    inputs: apoleia_sim::inputs::Inputs,
    clear: Option<Clearable>,
    cover: Option<FineCover>,
}

impl Data {
    fn read(root: &str) -> Result<Data, String> {
        let inputs = apoleia_sim::inputs::load(Path::new(root), false)?;
        // villages on the farmland of the fine tiles; without the file on
        // hashed tiles of each cell
        let cover = match apoleia_sim::grain::fine_cover(Path::new(root), true) {
            Ok(c) => Some(c),
            Err(e) => {
                godot_warn!("ApoleiaPeople: no fine land cover ({e}), villages on hashed tiles");
                None
            }
        };
        // the grain economy with the defaults of bin/grain.rs: today's
        // farmland clearable, fields on the fine tiles
        let cols: Vec<String> = apoleia_sim::grain::CLEAR_COVER.iter().map(|c| c.to_string()).collect();
        let clear = match apoleia_sim::grain::clearable(Path::new(root), &cols) {
            Ok(c) => Some(c),
            Err(e) => {
                godot_warn!("ApoleiaPeople: no landcover25.csv ({e}), all usable land clearable");
                None
            }
        };
        Ok(Data { inputs, clear, cover })
    }

    fn start(&self) -> Start<'_> {
        Start { inputs: &self.inputs, clear: self.clear.as_ref(), cover: self.cover.as_ref() }
    }
}

/// The map layers and the view of a game that is about to run, published
/// as its first day.
fn begin(game: &mut Game, data: &Data, shared: &Shared) -> (GrainMap, PeopleView) {
    let today = game.today();
    let mut map = GrainMap::new(&game.people);
    map.build(&game.grain, today);
    let mut view = PeopleView::new(&game.people, &data.inputs.cities, data.cover.as_ref());
    mark_work(game, &mut view, shared.site_houses.load(Ordering::Relaxed));
    let pages = view.update(&mut game.people);
    let mut f = shared.front.lock().unwrap();
    publish(&view, &pages, &mut f);
    publish_houses(&mut view, &mut f);
    f.day = today;
    f.count = game.people.count;
    f.cash = game.grain.treasury.cash;
    f.map = map.layers.clone();
    publish_orders(game, &mut f);
    (map, view)
}

/// The statuses of `take_build_check` (apoleia_sim::grain::CHECK_*).
const CHECK_STATES: [&str; 5] = ["wird gebaut", "hier baut niemand: kein Markt, Meer oder ausserhalb der Karte", "wird nicht gebaut", "wird gebaut, aber in der Gegend zieht heute niemand ein", "kein freies Land zum Pflügen oder Roden"];

/// What orders would come to before they are placed (`ask_build_check`).
struct BuildCheck {
    /// Column, row and status (apoleia_sim::grain::CHECK_*) of each tile.
    tiles: Vec<i32>,
    /// Work days and their cost at today's day wages, milli-denarii.
    need: i64,
    cost: i64,
    /// The market of the first tile that has one, its day wage, and how
    /// many markets the tiles lie in.
    market: String,
    wage: i64,
    markets: usize,
    /// The treasury's cash now, milli-denarii.
    cash: i64,
}

fn build_check(game: &Game, kind: u8, tiles: &[build::Tile]) -> BuildCheck {
    let mut c = BuildCheck { tiles: Vec::with_capacity(tiles.len() * 3), need: 0, cost: 0, market: String::new(), wage: 0, markets: 0, cash: game.grain.treasury.cash };
    let mut seen = Vec::new();
    for &t in tiles {
        let s = game.grain.site_check(&game.people, kind, t);
        c.tiles.extend_from_slice(&[t.1, t.0, s.status as i32]);
        c.need += s.need;
        c.cost += s.cost;
        if s.market != apoleia_sim::people::NONE && !seen.contains(&s.market) {
            if seen.is_empty() {
                c.market = game.grain.markets[s.market as usize].name.clone();
                c.wage = game.grain.day_wage(s.market);
            }
            seen.push(s.market);
        }
    }
    c.markets = seen.len();
    c
}

/// The row of a table whose id is `id`, as a table of one row.
fn row_of(mut t: Table, id: i64) -> Option<Table> {
    let i = t.columns.iter().find(|c| c.key == "id").and_then(|c| match &c.values {
        Values::Int(v) => v.iter().position(|&x| x == id),
        _ => None,
    })?;
    for c in t.columns.iter_mut() {
        c.values = match &c.values {
            Values::Int(v) => Values::Int(vec![v[i]]),
            Values::Float(v) => Values::Float(vec![v[i]]),
            Values::Text(v) => Values::Text(vec![v[i].clone()]),
        };
    }
    Some(t)
}

/// Each craft household's workshop onto its house record (view.rs Houses),
/// the families whose farm is not in their village onto its tile, on the
/// order's spot for a farm built from one (Grain::homes_moved: farms built
/// from orders, heirs), and with `sites` each farm's building site as a
/// house record on its spot, where the farm will stand.
fn mark_work(game: &Game, view: &mut PeopleView, sites: bool) {
    view.set_homes(&game.grain.homes_moved());
    let farms: Vec<(build::Tile, u32, u8)> = if sites {
        game.grain.sites().filter(|(_, s)| s.kind == build::FARM && s.need > 0).map(|(t, s)| (t, s.fine, (s.done * 255 / s.need).clamp(0, 255) as u8)).collect()
    } else {
        Vec::new()
    };
    view.set_sites(&farms);
    let c = game.grain.crafts_in((f64::MIN, f64::MIN), (f64::MAX, f64::MAX));
    view.houses.set_work(c.household.iter().zip(&c.craft).zip(&c.util).map(|((&h, &craft), &busy)| (h as u32, craft, busy)));
}

/// The building sites in the window (world km, min x, min z, max x, max
/// z): x and z of the order's spot (the middle of its village lot), kind
/// (build::KIND_NAMES), share built (0 while nobody builds it), and the
/// lot's width and depth in world km.
fn sites_in(game: &Game, [x0, z0, x1, z1]: [f64; 4]) -> Vec<f32> {
    let mut out = Vec::new();
    for ((z, x), s) in game.grain.sites() {
        let (x, z) = (x as f64 / 1000.0, z as f64 / 1000.0);
        if x < x0 || x > x1 || z < z0 || z > z1 {
            continue;
        }
        let built = if s.need > 0 { s.done as f32 / s.need as f32 } else { 0.0 };
        out.extend_from_slice(&[x as f32, z as f32, s.kind as f32, built, LOT_KM, LOT_KM]);
    }
    out
}

/// The build orders and how far their sites are, to the front.
fn publish_orders(game: &Game, f: &mut Front) {
    f.orders = game.orders.clone();
    f.progress = progress(game);
    f.roads = game.grain.road_lots().flat_map(|(z, x)| [x, z]).collect();
    f.fields = game.grain.field_lots().flat_map(|(z, x)| [x, z]).collect();
    f.built += 1;
}

/// Column, row, work days done and needed for each order, in tile order
/// (0, 0 without a site).
fn progress(game: &Game) -> Vec<i32> {
    let mut sites = game.grain.sites().peekable();
    let mut out = Vec::with_capacity(game.orders.len() * 4);
    for (t, _) in game.orders.iter() {
        while sites.next_if(|(s, _)| *s < t).is_some() {}
        let (done, need) = sites.next_if(|(s, _)| *s == t).map_or((0, 0), |(_, s)| (s.done, s.need));
        out.extend_from_slice(&[t.1, t.0, done as i32, need as i32]);
    }
    out
}

fn run(mut game: Game, map: GrainMap, mut view: PeopleView, shared: Arc<Shared>) {
    let map = {
        let sh = shared.clone();
        MapThread::start(map, move |layers| sh.front.lock().unwrap().map = layers)
    };
    let mut shown = Instant::now();
    let mut sites_were = shared.site_houses.load(Ordering::Relaxed);
    loop {
        // commands and questions from the game first, between two days; then a day
        let (commands, save, check, ask, table, trips, work, events, goods, sites, market) = {
            let mut q = shared.queue.lock().unwrap();
            while q.days == 0 && !q.stop && !q.asked() {
                q = shared.wake.wait(q).unwrap();
            }
            if q.stop {
                return;
            }
            let asked = q.asked();
            if !asked {
                q.days -= 1;
            }
            (std::mem::take(&mut q.commands), q.save.take(), q.check.take(), q.ask.take(), q.table.take(), q.trips.take(), q.work.take(), q.events.take(), q.goods.take(), q.sites.take(), q.market.take())
        };
        if !commands.is_empty() {
            let mut changed = 0;
            for c in &commands {
                changed += game.command(c);
            }
            if changed > 0 {
                publish_orders(&game, &mut shared.front.lock().unwrap());
            }
        }
        if let Some(path) = &save {
            let r = game.save_to(Path::new(path)).map(|()| game.today()).map_err(|e| e.to_string());
            shared.front.lock().unwrap().saved = Some(r);
        }
        if let Some((kind, tiles)) = &check {
            let c = build_check(&game, *kind, tiles);
            shared.front.lock().unwrap().check = Some(c);
        }
        if let Some(window) = sites {
            let v = sites_in(&game, window);
            shared.front.lock().unwrap().sites = Some(v);
        }
        if let Some(m) = market {
            let row = game.grain.table(&game.people, "markets").and_then(|t| row_of(t, m as i64));
            shared.front.lock().unwrap().market = Some((m, row));
        }
        let Game { people, grain, .. } = &mut game;
        if let Some(key) = &table {
            let t = grain.table(people, key);
            shared.front.lock().unwrap().table = t;
        }
        if let Some([x0, z0, x1, z1]) = trips {
            let v = grain.trips_in(people, (x0, z0), (x1, z1));
            shared.front.lock().unwrap().trips = Some(v);
        }
        if let Some([x0, z0, x1, z1]) = work {
            let v = grain.work_in((x0, z0), (x1, z1));
            shared.front.lock().unwrap().work = Some(v);
        }
        if let Some((since, [x0, z0, x1, z1])) = events {
            let v = grain.events_in(people, since, (x0, z0), (x1, z1));
            shared.front.lock().unwrap().events = Some(v);
        }
        if let Some([x0, z0, x1, z1]) = goods {
            let v = (grain.crafts_in((x0, z0), (x1, z1)), grain.market_goods(), grain.goods_moves_in((x0, z0), (x1, z1)));
            shared.front.lock().unwrap().goods = Some(v);
        }
        if let Some(who) = ask {
            let pid = match who {
                Who::Slot(slot) => view.pid_at(slot),
                Who::Pid(pid) => Some(pid),
                Who::Household(h) => PeopleView::member_of(people, h),
            };
            let who = pid.and_then(|pid| PeopleView::person(people, pid));
            let who = who.map(|p| {
                let hh = grain.household(p.household);
                (p, hh)
            });
            shared.front.lock().unwrap().person = who;
        }
        if !commands.is_empty() || save.is_some() || check.is_some() || ask.is_some() || table.is_some() || trips.is_some() || work.is_some() || events.is_some() || goods.is_some() || sites.is_some() || market.is_some() {
            continue;
        }
        // the people, the grain economy (S69–S112) and the building sites
        // (S113) on the same day, as bin/grain.rs
        let t0 = Instant::now();
        let [day_usec, grain_usec] = game.day();
        let today = game.today();
        let t_map = Instant::now();
        // a site finished (its order is gone): its farm and fields show at
        // once, not at the next month's map; how far the sites are goes out
        // once a week (REALTIME_GAMEPLAY.md phase 3)
        let finished = game.orders.version != shared.front.lock().unwrap().orders.version;
        if finished || (today % 7 == 0 && progress(&game) != shared.front.lock().unwrap().progress) {
            publish_orders(&game, &mut shared.front.lock().unwrap());
        }
        let remap = today % 30 == 0 || finished;
        // the workshops at the houses (S105; the graphics put them there),
        // once a week as the crafts sell by the week; a farm just taken
        // shows its family on its tile at once
        let sites_on = shared.site_houses.load(Ordering::Relaxed);
        if today % 7 == 0 || finished || sites_on != sites_were {
            mark_work(&game, &mut view, sites_on);
            sites_were = sites_on;
        }
        if remap {
            map.draw(MapJob::take(&game.grain, today));
        }
        // the view at most VIEW_HZ times a second while days are queued:
        // the screen shows one state a frame, so at 100 days a second most
        // days would never be seen (REALTIME_GAMEPLAY.md phase 8)
        let t1 = Instant::now();
        let behind = shared.queue.lock().unwrap().days > 0;
        let show = !behind || t1 - shown >= Duration::from_secs_f64(1.0 / VIEW_HZ);
        let pages = if show {
            shown = t1;
            view.update(&mut game.people)
        } else {
            Vec::new()
        };
        let view_usec = t1.elapsed().as_secs_f64() * 1e6;
        let t_publish = Instant::now();
        let mut f = shared.front.lock().unwrap();
        if show {
            publish(&view, &pages, &mut f);
            publish_houses(&mut view, &mut f);
            f.view_usec = view_usec;
        }
        let ms = |a: Instant, b: Instant| (b - a).as_secs_f64() * 1e3;
        let end = Instant::now();
        for (k, v) in [ms(t0, t_map), ms(t_map, t1), ms(t1, t_publish), ms(t_publish, end)].into_iter().enumerate() {
            f.spent[k] += v;
        }
        f.spent_days += 1;
        f.day = today;
        f.count = game.people.count;
        f.cash = game.grain.treasury.cash;
        f.day_usec = day_usec;
        f.grain_usec = grain_usec;
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
    /// Build of each house (people_houses.gdshader `variant`) as the last
    /// placement pass read back put it (`set_house_places`).
    house_variant: Vec<u8>,
    /// Counts the house syncs that changed a record; `house_changed` holds
    /// the count at each house's last change and `house_forgot` the count
    /// when all builds were last forgotten (a new house texture), so a
    /// placement read back knows which houses it already saw.
    house_gen: i64,
    house_changed: Vec<i64>,
    house_forgot: i64,
    day: i64,
    count: u32,
    day_usec: f64,
    view_usec: f64,
    upload_usec: f64,
    uploaded_pages: i64,
    /// Repository root the inputs were loaded from (needed to load saves).
    root: String,
    base: Base<RefCounted>,
}

#[godot_api]
impl ApoleiaPeople {
    /// Loads the inputs below `repo_root`, spawns the start population and
    /// starts the sim thread. Returns false when the inputs are missing.
    #[func]
    fn load(&mut self, repo_root: GString, seed: i64) -> bool {
        self.root = repo_root.to_string();
        let data = match Data::read(&self.root) {
            Ok(d) => d,
            Err(e) => {
                godot_error!("ApoleiaPeople.load: {e}");
                return false;
            }
        };
        self.stop();
        let tg = Instant::now();
        let mut game = Game::new(data.start(), seed as u64);
        let grain_ms = tg.elapsed().as_secs_f64() * 1e3;
        let shared = Arc::new(Shared::default());
        let (map, view) = begin(&mut game, &data, &shared);
        godot_print!("{{\"event\":\"grain_loaded\",\"ms\":{grain_ms:.0},\"markets\":{}}}", game.grain.markets.len());
        let sh = shared.clone();
        self.worker = Some(std::thread::Builder::new().name("apoleia-people".into()).spawn(move || run(game, map, view, sh)).expect("people thread"));
        self.restart(shared);
        true
    }

    /// Writes a save game (absolute path) between two days; the answer
    /// comes with `take_saved`. A save holds the seed and the commands
    /// (apoleia_sim::game), a few hundred bytes.
    #[func]
    fn save_game(&mut self, path: GString) {
        if self.worker.is_none() {
            return;
        }
        self.shared.queue.lock().unwrap().save = Some(path.to_string());
        self.shared.wake.notify_one();
    }

    /// The answer to the last `save_game`, once: {"ok", "day" or "error"};
    /// empty while it is not written yet.
    #[func]
    fn take_saved(&mut self) -> VarDictionary {
        let mut d = VarDictionary::new();
        match self.shared.front.lock().unwrap().saved.take() {
            Some(Ok(day)) => {
                d.set("ok", true);
                d.set("day", day);
            }
            Some(Err(e)) => {
                d.set("ok", false);
                d.set("error", e.as_str());
            }
            None => {}
        }
        d
    }

    /// Replaces the running game with a save game (absolute path). The file
    /// is checked first; a bad one leaves the game running and returns
    /// false. Otherwise the save plays again on a new sim thread
    /// (`loading`), then runs on from its day.
    #[func]
    fn load_game(&mut self, path: GString) -> bool {
        let data = match Data::read(&self.root) {
            Ok(d) => d,
            Err(e) => {
                godot_error!("ApoleiaPeople.load_game: {e}");
                return false;
            }
        };
        let replay = match std::fs::read(path.to_string()).map_err(|e| e.to_string()).and_then(|b| Game::check(data.start(), &b).map_err(|e| e.to_string())) {
            Ok(r) => r,
            Err(e) => {
                godot_error!("ApoleiaPeople.load_game: {e}");
                return false;
            }
        };
        let built = self.shared.front.lock().unwrap().built;
        self.stop();
        let shared = Arc::new(Shared::default());
        shared.site_houses.store(self.shared.site_houses.load(Ordering::Relaxed), Ordering::Relaxed);
        {
            let mut f = shared.front.lock().unwrap();
            f.loading = Some((0, replay.day()));
            f.built = built;
        }
        let sh = shared.clone();
        self.worker = Some(
            std::thread::Builder::new()
                .name("apoleia-people".into())
                .spawn(move || {
                    let (mut game, info) = replay.run(data.start(), |d, of| sh.front.lock().unwrap().loading = Some((d, of)));
                    let (map, view) = begin(&mut game, &data, &sh);
                    {
                        let mut f = sh.front.lock().unwrap();
                        f.loading = None;
                        f.loaded = Some(info);
                    }
                    drop(data);
                    run(game, map, view, sh)
                })
                .expect("people thread"),
        );
        self.restart(shared);
        true
    }

    /// The treasury's cash after the last day, in denarii (S94, S95).
    #[func]
    fn cash(&self) -> f64 {
        self.shared.front.lock().unwrap().cash as f64 / 1000.0
    }

    /// A save game is playing again: no days, no dots until it has.
    #[func]
    fn is_loading(&self) -> bool {
        self.shared.front.lock().unwrap().loading.is_some()
    }

    /// While a save game plays again: {"day", "of"}; empty otherwise.
    #[func]
    fn loading(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        if let Some((day, of)) = self.shared.front.lock().unwrap().loading {
            d.set("day", day);
            d.set("of", of);
        }
        d
    }

    /// How the last save game played again, once: {"day", "commands",
    /// "identical" (the same world as saved; false when the sim changed
    /// since)}; empty until it has.
    #[func]
    fn take_loaded(&mut self) -> VarDictionary {
        let mut d = VarDictionary::new();
        if let Some(l) = self.shared.front.lock().unwrap().loaded.take() {
            d.set("day", l.day);
            d.set("commands", l.commands as i64);
            d.set("identical", l.identical);
        }
        d
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

    /// Orders `kind` (apoleia_sim::build: 0 farm, 1 field, 2 road) on the
    /// fine tiles `tiles` (column, row pairs, absolute: floor(x / 1.5625),
    /// floor(z / 1.5625) world km). Applied between two days; `build_orders`
    /// shows it a frame or two later.
    #[func]
    fn order_build(&mut self, kind: i64, tiles: PackedInt32Array) {
        if self.worker.is_none() || !(0..build::KIND_NAMES.len() as i64).contains(&kind) {
            return;
        }
        let tiles = pairs(&tiles);
        if tiles.is_empty() {
            return;
        }
        self.shared.queue.lock().unwrap().commands.push(Command::Place { kind: kind as u8, tiles });
        self.shared.wake.notify_one();
    }

    /// Takes back the orders on `tiles` (as `order_build`).
    #[func]
    fn cancel_build(&mut self, tiles: PackedInt32Array) {
        let tiles = pairs(&tiles);
        if self.worker.is_none() || tiles.is_empty() {
            return;
        }
        self.shared.queue.lock().unwrap().commands.push(Command::Cancel { tiles });
        self.shared.wake.notify_one();
    }

    /// The build orders: {"version": bumped on every change, "tiles":
    /// column, row, kind for each, "progress": column, row, work days done,
    /// work days needed for each, in the same order (0, 0 while it has no
    /// building site or nobody builds it yet; once a week), "roads": x, z
    /// of each finished road lot (world metres; built roads stay after
    /// their orders are gone), "fields": the same for finished field lots
    /// (state land, S116), "names": the kinds}.
    #[func]
    fn build_orders(&self) -> VarDictionary {
        let f = self.shared.front.lock().unwrap();
        let mut flat = Vec::with_capacity(f.orders.len() * 3);
        for ((row, col), o) in f.orders.iter() {
            flat.extend_from_slice(&[col, row, o.kind as i32]);
        }
        let mut d = VarDictionary::new();
        d.set("version", f.built as i64);
        d.set("tiles", &PackedInt32Array::from(flat.as_slice()));
        d.set("progress", &PackedInt32Array::from(f.progress.as_slice()));
        d.set("roads", &PackedInt32Array::from(f.roads.as_slice()));
        d.set("fields", &PackedInt32Array::from(f.fields.as_slice()));
        d.set("names", &PackedStringArray::from_iter(build::KIND_NAMES.iter().map(|n| GString::from(*n))));
        d
    }

    /// Asks what orders of `kind` on `tiles` (as `order_build`) would come
    /// to, without placing them; the answer comes with `take_build_check`,
    /// also while paused.
    #[func]
    fn ask_build_check(&mut self, kind: i64, tiles: PackedInt32Array) {
        let tiles = pairs(&tiles);
        if self.worker.is_none() || tiles.is_empty() || !(0..build::KIND_NAMES.len() as i64).contains(&kind) {
            return;
        }
        self.shared.front.lock().unwrap().check = None;
        self.shared.queue.lock().unwrap().check = Some((kind as u8, tiles));
        self.shared.wake.notify_one();
    }

    /// The answer to `ask_build_check`, once; empty until the sim thread
    /// gave it. {"tiles": column, row, status for each (0 gets built, 1
    /// nobody builds here: no market, the sea or off the map, 2 fields and
    /// roads nobody builds yet, 3 gets built but nobody of the region could
    /// move in today), "states": what each status means, "days": work days,
    /// "cost": denarii at today's day wages from the treasury, "market" and
    /// "wage": the first tile's market and its day wage in denarii,
    /// "markets": how many markets, "cash": the treasury's denarii now}.
    #[func]
    fn take_build_check(&mut self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(c) = self.shared.front.lock().unwrap().check.take() else { return d };
        d.set("tiles", &PackedInt32Array::from(c.tiles.as_slice()));
        d.set("states", &PackedStringArray::from_iter(CHECK_STATES.iter().map(|n| GString::from(*n))));
        d.set("days", c.need);
        d.set("cost", c.cost as f64 / 1000.0);
        d.set("market", c.market.as_str());
        d.set("wage", c.wage as f64 / 1000.0);
        d.set("markets", c.markets as i64);
        d.set("cash", c.cash as f64 / 1000.0);
        d
    }

    /// Puts each farm's building site (S113) into the house records, as a
    /// house where the farm will stand: [x, z, -village code, site key <<
    /// 8 | share built × 255] (sim/src/view.rs Houses). Off by default,
    /// since a house shader that does not know the negative village code
    /// would misplace them; kept across loads.
    #[func]
    fn show_site_houses(&mut self, on: bool) {
        self.shared.site_houses.store(on, Ordering::Relaxed);
        self.shared.wake.notify_one();
    }

    /// Asks the sim thread for the building sites in the window (world km);
    /// the answer comes with `take_sites`, also while paused.
    #[func]
    fn ask_sites(&mut self, min_x: f64, min_z: f64, max_x: f64, max_z: f64) {
        if self.worker.is_none() {
            return;
        }
        self.shared.front.lock().unwrap().sites = None;
        self.shared.queue.lock().unwrap().sites = Some([min_x, min_z, max_x, max_z]);
        self.shared.wake.notify_one();
    }

    /// The sites asked for, once: six floats each, x and z of the order's
    /// spot (world km, the middle of its village lot), kind (0 farm, 1
    /// field, 2 road), share built 0–1 (0 while nobody builds it), width
    /// and depth (world km, the lot); None (an empty Variant) until the sim
    /// thread answered.
    #[func]
    fn take_sites(&mut self) -> Variant {
        match self.shared.front.lock().unwrap().sites.take() {
            Some(v) => PackedFloat32Array::from(v.as_slice()).to_variant(),
            None => Variant::nil(),
        }
    }

    /// The market whose square is on the fine tile under (x, z) world km or
    /// next to it, -1 if none (from the map layers, at once).
    #[func]
    fn market_at(&self, x: f32, z: f32) -> i64 {
        let map = self.shared.front.lock().unwrap().map.clone();
        let (rf, cf) = map.fine_size();
        if map.fine.len() != (rf * cf * 4) as usize {
            return -1;
        }
        let (fr, fc) = ((z / FINE_KM).floor() as i32 - map.row0 * FINE, (x / FINE_KM).floor() as i32 - map.col0 * FINE);
        for (dr, dc) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)] {
            let (r, c) = (fr + dr, fc + dc);
            if r < 0 || c < 0 || r >= rf || c >= cf || map.fine[((r * cf + c) * 4 + 3) as usize] & MARKET_BIT == 0 {
                continue;
            }
            let cell = ((r / FINE) * map.cols + c / FINE) as usize;
            return map.regions.get(cell).map_or(-1, |&m| if m == u32::MAX { -1 } else { m as i64 });
        }
        -1
    }

    /// Asks the sim thread for one market's row of the markets table
    /// (apoleia_sim::grain, `table("markets")`); the answer comes with
    /// `take_market`, also while paused.
    #[func]
    fn ask_market(&mut self, market: i64) {
        if self.worker.is_none() || market < 0 {
            return;
        }
        self.shared.front.lock().unwrap().market = None;
        self.shared.queue.lock().unwrap().market = Some(market as usize);
        self.shared.wake.notify_one();
    }

    /// The market asked for, once: {"market", and when it exists the row
    /// as tables::to_dict with one row ("name", "day", "columns", "labels",
    /// "units", "data")}; empty until the sim thread answered.
    #[func]
    fn take_market(&mut self) -> VarDictionary {
        let Some((m, row)) = self.shared.front.lock().unwrap().market.take() else { return VarDictionary::new() };
        let mut d = row.as_ref().map_or_else(VarDictionary::new, tables::to_dict);
        d.set("market", m as i64);
        d
    }

    /// Build orders version only, to poll each frame.
    #[func]
    fn build_version(&self) -> i64 {
        self.shared.front.lock().unwrap().built as i64
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

    /// Takes the house placement pass as read back from the GPU (RGBA16F,
    /// `width` texels a row, people_dots_prep.gdshader with `houses`) and
    /// works out each house's build as people_houses.gdshader does: by the
    /// lot (`lot_km` from `world_min`) it stands on. `gen` is `house_gen` when
    /// the pass ran: a house changed since keeps its build unknown until a
    /// later pass is read. Returns how many houses changed their build.
    #[func]
    fn set_house_places(&mut self, place: PackedByteArray, width: i64, world_min: Vector2, lot_km: f32, gen: i64) -> i64 {
        if gen < self.house_forgot {
            return 0;
        }
        let bytes = place.as_slice();
        let w = width.max(1) as usize;
        let h = bytes.len() / (w * 8);
        let n = self.houses.len() / REC;
        self.house_variant.resize(n, HOUSE_UNKNOWN);
        let mut changed = 0;
        for slot in 0..n {
            if self.house_changed.get(slot).copied().unwrap_or(0) > gen {
                continue;
            }
            let rec = &self.houses[slot * REC..slot * REC + REC];
            let (layer, in_page) = (slot / PAGE, slot % PAGE);
            let (px, py) = (in_page % SIDE, layer * SIDE + in_page / SIDE);
            if px >= w || py >= h {
                continue;
            }
            let o = (py * w + px) * 8;
            let half = |c: usize| f16_to_f32(u16::from_le_bytes([bytes[o + c * 2], bytes[o + c * 2 + 1]]));
            let build = if rec[2] == 0.0 || half(3) <= 0.5 {
                HOUSE_UNPLACED
            } else {
                let px_km = rec[0] + half(0) - 32.0;
                let pz_km = rec[1] + half(1) - 32.0;
                let lot_x = ((px_km - world_min.x) / lot_km).floor() as i32;
                let lot_z = ((pz_km - world_min.y) / lot_km).floor() as i32;
                let key = dot_hash((lot_x as u32).wrapping_mul(0x2545f491) ^ (lot_z as u32).wrapping_mul(0x9e3779b9));
                ((key >> 12) % HOUSE_VARIANTS as u32) as u8
            };
            if self.house_variant[slot] != build {
                self.house_variant[slot] = build;
                changed += 1;
            }
        }
        changed
    }

    /// The count of house syncs that changed a record (`set_house_places`).
    #[func]
    fn house_gen(&self) -> i64 {
        self.house_gen
    }

    /// The houses within `radius` km of (x, z), nearest first, at most
    /// `max`, cut into the levels of detail (`limits`: the most houses each
    /// takes, 0 when it is not used) and each level into the builds, so each
    /// build's MultiMesh draws only its own houses instead of all of them
    /// (people_dots.gd _update_houses): `slots` the list, `blocks` per level
    /// and build the offset and count of its run. A level with a house of
    /// unknown build is not cut: each build draws all of it and the shader
    /// leaves out the others; unplaced houses are left out once known.
    #[func]
    fn houses_split(&self, x: f32, z: f32, radius: f32, max: i64, limits: PackedInt32Array) -> VarDictionary {
        let near = self.houses_near(x, z, radius, max);
        let near = near.as_slice();
        let mut slots: Vec<i32> = Vec::with_capacity(near.len());
        let mut blocks: Vec<i32> = Vec::new();
        let mut start = 0usize;
        for &limit in limits.as_slice() {
            let n = (limit.max(0) as usize).min(near.len() - start);
            let level = &near[start..start + n];
            start += n;
            let build = |s: i32| self.house_variant.get(s as usize).copied().unwrap_or(HOUSE_UNKNOWN);
            if level.iter().all(|&s| build(s) != HOUSE_UNKNOWN) {
                for v in 0..HOUSE_VARIANTS {
                    let off = slots.len() as i32;
                    slots.extend(level.iter().copied().filter(|&s| build(s) == v));
                    blocks.extend([off, slots.len() as i32 - off]);
                }
            } else {
                let off = slots.len() as i32;
                slots.extend_from_slice(level);
                for _ in 0..HOUSE_VARIANTS {
                    blocks.extend([off, n as i32]);
                }
            }
        }
        let mut d = VarDictionary::new();
        d.set("slots", &PackedInt32Array::from(slots.as_slice()));
        d.set("blocks", &PackedInt32Array::from(blocks.as_slice()));
        d
    }

    /// Asks the sim thread for the person in `slot`; the answer comes with
    /// `take_person` (between two days, so within a frame or two).
    #[func]
    fn ask_person(&mut self, slot: i64) {
        if self.worker.is_none() || slot < 0 {
            return;
        }
        self.ask(Who::Slot(slot as usize));
    }

    /// As `ask_person`, for a person by id (the pid of a trip under way).
    #[func]
    fn ask_person_id(&mut self, pid: i64) {
        if (0..u32::MAX as i64).contains(&pid) {
            self.ask(Who::Pid(pid as u32));
        }
    }

    /// As `ask_person`, for a member of a household (a hired worker of
    /// `ask_work`): the one with the lowest id.
    #[func]
    fn ask_household_member(&mut self, household: i64) {
        if (0..u32::MAX as i64).contains(&household) {
            self.ask(Who::Household(household as u32));
        }
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
            d.set("money", h.money as f64 / 1000.0); // denarii
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

    /// Asks the sim thread for a table ("markets", "population", "farms");
    /// the answer comes with `take_table`, between two days.
    #[func]
    fn ask_table(&mut self, kind: GString) {
        if self.worker.is_none() {
            return;
        }
        self.shared.front.lock().unwrap().table = None;
        self.shared.queue.lock().unwrap().table = Some(kind.to_string());
        self.shared.wake.notify_one();
    }

    /// The table asked for, once, as tables::to_dict; empty until the sim
    /// thread answered.
    #[func]
    fn take_table(&mut self) -> VarDictionary {
        match self.shared.front.lock().unwrap().table.take() {
            Some(t) => tables::to_dict(&t),
            None => VarDictionary::new(),
        }
    }

    /// Asks the sim thread for the trips under way whose route touches the
    /// window (world km); the answer comes with `take_trips`, between two
    /// days.
    #[func]
    fn ask_trips(&mut self, min_x: f64, min_z: f64, max_x: f64, max_z: f64) {
        if self.worker.is_none() {
            return;
        }
        self.shared.front.lock().unwrap().trips = None;
        self.shared.queue.lock().unwrap().trips = Some([min_x, min_z, max_x, max_z]);
        self.shared.wake.notify_one();
    }

    /// The trips asked for, once, as trips::to_dict; empty until the sim
    /// thread answered.
    #[func]
    fn take_trips(&mut self) -> VarDictionary {
        match self.shared.front.lock().unwrap().trips.take() {
            Some(v) => trips::to_dict(&v),
            None => VarDictionary::new(),
        }
    }

    /// Asks the sim thread who works on whose farm (the last weekly labour
    /// exchange of each region) where the worker's home or the farm lies
    /// in the window (world km); the answer comes with `take_work`.
    #[func]
    fn ask_work(&mut self, min_x: f64, min_z: f64, max_x: f64, max_z: f64) {
        if self.worker.is_none() {
            return;
        }
        self.shared.front.lock().unwrap().work = None;
        self.shared.queue.lock().unwrap().work = Some([min_x, min_z, max_x, max_z]);
        self.shared.wake.notify_one();
    }

    /// The hires asked for, once, as trips::work_to_dict; empty until the
    /// sim thread answered.
    #[func]
    fn take_work(&mut self) -> VarDictionary {
        match self.shared.front.lock().unwrap().work.take() {
            Some(v) => trips::work_to_dict(&v),
            None => VarDictionary::new(),
        }
    }

    /// Asks the sim thread for the craft goods (S105–S111): the workshops
    /// and the goods moved between markets in the window (world km), and
    /// every market's goods; the answer comes with `take_goods`.
    #[func]
    fn ask_goods(&mut self, min_x: f64, min_z: f64, max_x: f64, max_z: f64) {
        if self.worker.is_none() {
            return;
        }
        self.shared.front.lock().unwrap().goods = None;
        self.shared.queue.lock().unwrap().goods = Some([min_x, min_z, max_x, max_z]);
        self.shared.wake.notify_one();
    }

    /// The goods asked for, once, as trips::goods_to_dict; empty until the
    /// sim thread answered.
    #[func]
    fn take_goods(&mut self) -> VarDictionary {
        match self.shared.front.lock().unwrap().goods.take() {
            Some((c, m, mv)) => trips::goods_to_dict(&c, &m, &mv),
            None => VarDictionary::new(),
        }
    }

    /// Asks the sim thread for the events after day `since` in the window
    /// (world km); the answer comes with `take_events`.
    #[func]
    fn ask_events(&mut self, since: i64, min_x: f64, min_z: f64, max_x: f64, max_z: f64) {
        if self.worker.is_none() {
            return;
        }
        self.shared.front.lock().unwrap().events = None;
        self.shared.queue.lock().unwrap().events = Some((since, [min_x, min_z, max_x, max_z]));
        self.shared.wake.notify_one();
    }

    /// The events asked for, once, as trips::events_to_dict; empty until
    /// the sim thread answered.
    #[func]
    fn take_events(&mut self) -> VarDictionary {
        match self.shared.front.lock().unwrap().events.take() {
            Some(v) => trips::events_to_dict(&v),
            None => VarDictionary::new(),
        }
    }

    /// The market (region) of each 25 km cell as of the last month, row by
    /// row, -1 at sea: {"cells", "rows", "cols", "origin" world km of the
    /// grid corner, "cell_km"}. With the `markets` table (id = market
    /// index) the game colours the regions by any column.
    #[func]
    fn region_map(&self) -> VarDictionary {
        let map = self.shared.front.lock().unwrap().map.clone();
        let mut d = VarDictionary::new();
        d.set("cells", &PackedInt32Array::from_iter(map.regions.iter().map(|&m| if m == u32::MAX { -1 } else { m as i32 })));
        d.set("rows", map.rows);
        d.set("cols", map.cols);
        d.set("origin", Vector2::new(map.col0 as f32 * CELL_KM, map.row0 as f32 * CELL_KM));
        d.set("cell_km", CELL_KM);
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
            if f.house_dirty.contains(&true) {
                self.house_gen += 1;
            }
            self.house_changed.resize(self.houses.len() / REC, self.house_gen);
            let mut out = Vec::new();
            for pg in 0..f.house_dirty.len() {
                if std::mem::take(&mut f.house_dirty[pg]) {
                    // a house whose record changed may stand on another lot:
                    // its build is known again once a placement after this
                    // change is read back
                    for slot in pg * PAGE..((pg + 1) * PAGE).min(self.house_changed.len()) {
                        let r = slot * REC..slot * REC + REC;
                        if self.houses[r.clone()] != f.houses[r] {
                            if let Some(v) = self.house_variant.get_mut(slot) {
                                *v = HOUSE_UNKNOWN;
                            }
                            self.house_changed[slot] = self.house_gen;
                        }
                    }
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
        self.house_gen += 1;
        self.house_forgot = self.house_gen;
        self.house_variant.clear();
        self.house_changed.clear();
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

    /// Centres (world km) of the market squares among the `n` × `n` fine
    /// tiles around (x, z), as the terrain draws them (sim_map.gdshaderinc
    /// sim_paths), for the stalls that stand on them.
    #[func]
    fn market_squares(&self, x: f32, z: f32, n: i64) -> PackedVector2Array {
        let map = self.shared.front.lock().unwrap().map.clone();
        let n = n.clamp(1, 1024) as i32;
        let fr0 = (z / FINE_KM).floor() as i32 - map.row0 * FINE - n / 2;
        let fc0 = (x / FINE_KM).floor() as i32 - map.col0 * FINE - n / 2;
        let win = map.window(fr0, fc0, n);
        let mut out = PackedVector2Array::new();
        for (i, px) in win.chunks_exact(4).enumerate() {
            if px[3] & MARKET_BIT != 0 {
                let (r, c) = (fr0 + map.row0 * FINE + i as i32 / n, fc0 + map.col0 * FINE + i as i32 % n);
                out.push(Vector2::new((c as f32 + 0.5) * FINE_KM, (r as f32 + 0.5) * FINE_KM));
            }
        }
        out
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
    /// thread), the last `sync` (main thread) and the layers it uploaded;
    /// and the sim thread's mean per day in ms, by part.
    #[func]
    fn timings(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let f = self.shared.front.lock().unwrap();
        d.set("day_usec", f.day_usec);
        d.set("view_usec", f.view_usec);
        d.set("grain_usec", f.grain_usec);
        // means over all days so far, ms (REALTIME_GAMEPLAY.md phase 8)
        let n = f.spent_days.max(1) as f64;
        for (k, key) in ["mean_day_ms", "mean_map_ms", "mean_view_ms", "mean_publish_ms"].iter().enumerate() {
            d.set(*key, f.spent[k] / n);
        }
        d.set("days_measured", f.spent_days as i64);
        drop(f);
        d.set("sync_usec", self.upload_usec);
        d.set("sync_layers", self.uploaded_pages);
        d
    }
}

impl ApoleiaPeople {
    fn ask(&mut self, who: Who) {
        if self.worker.is_none() {
            return;
        }
        self.shared.front.lock().unwrap().person = None;
        self.shared.queue.lock().unwrap().ask = Some(who);
        self.shared.wake.notify_one();
    }

    /// Takes over the shared state of a new sim thread; the main-thread
    /// copies start empty, so the next sync builds new textures.
    fn restart(&mut self, shared: Arc<Shared>) {
        self.shared = shared;
        self.data.clear();
        self.houses.clear();
        self.pages = 0;
    }

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

/// The hash of people_dots_common.gdshaderinc dot_hash.
fn dot_hash(mut x: u32) -> u32 {
    x ^= x >> 16;
    x = x.wrapping_mul(0x7feb352d);
    x ^= x >> 15;
    x = x.wrapping_mul(0x846ca68b);
    x ^= x >> 16;
    x
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
