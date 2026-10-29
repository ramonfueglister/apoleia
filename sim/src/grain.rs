//! Grain economy: farms and fields, harvest and day labour, one market per
//! region, carriers and traders, hunger, landless people in tents and
//! footpaths from traffic (decisions S69–S76, plan docs/kit2/GRAIN.md,
//! numbers docs/kit2/GRAIN-NUMBERS.md, run docs/kit2/run-grain/).
//!
//! The module runs beside `People` and reads it; it writes back only what
//! people.rs asks for through `people::Econ`: how well each household ate
//! (health, S64/S65), whether a region has free land (marriage, S65) and
//! how much food a region offers per head (moving, S66).
//!
//! What the decisions fix is built as decided. Every number they leave
//! open is a named constant marked `PLACEHOLDER` with its source or "frei
//! gewählt". Seed grain, fallow and harvest failures are later systems
//! (S72, S76) and not built: the yield is net of seed.
//!
//! Performance (GRAIN.md): a trip is an event with an arrival day, not a
//! step per day; harvest and sowing are events per farm; consumption runs
//! for 1/30 of the households each day; traders decide on 1/7 each day;
//! paths are walked every 90 days per market and decay at the walk; a
//! market's path field is rebuilt only when a path level in its region
//! changed. The monthly household count is a snapshot counted on another
//! thread and taken over in steps on the following days. Stores, money and
//! wear are integers. Everything that changes shared state runs serially
//! in a fixed order (the walks of one day touch only their own market), so
//! the result does not depend on the thread count.

use crate::inputs::Inputs;
use crate::life::{self, YEAR};
use crate::tables::Table;
use crate::people::{Born, Clock, Econ, Household, Home, Job, Pid, People, Sex, Stand, Travel, CITY, NONE, RURAL};
use crate::groups::{BAUERN, HAENDLER, HANDWERKER, PAECHTER, TAGELOEHNER, UNFREIE};

use bevy_ecs::prelude::Without;
use rustc_hash::FxHashMap;
use std::cmp::Reverse;
use std::collections::BinaryHeap;
use xxhash_rust::xxh3::xxh3_64;

// ---------------------------------------------------------------------
// Numbers. Sources in docs/kit2/GRAIN-NUMBERS.md unless noted.

/// Wheat per adult and year, kg (GRAIN-NUMBERS 1: proposal 200, range
/// 175–250). Children under 10 eat half (proposal there).
pub(crate) const KG_PER_ADULT_YEAR: i64 = 200;
const CHILD_AGE: f64 = 10.0;
/// Seed per ha, kg (Columella 2.9 via Devereaux 2025).
const SEED_KG_HA: i64 = 130;
/// Yield ratio harvest : seed, tenths. PLACEHOLDER: no soil or slope data
/// on the 25 km grid yet, so 5.5 : 1 on open land (Spurr: flat arable
/// 5–6 : 1) falling to 3 : 1 (Spurr: hill country 3–4 : 1) with the share
/// of land above 1500 m.
const RATIO_PLAIN_X10: i64 = 55;
const RATIO_HILL_X10: i64 = 30;
/// S87 (Ramon, 28.10.2026): the Nile land of Egypt yields 10 : 1 ("normal"
/// yields at Oxyrhynchus about 1 : 10, Manning 2007; 10-12 artabas per
/// aroura sown with one, Hickey via Bransbourg 2016, Rowlandson 1999).
/// Grain still on half the fields (Manning: rotation with legumes).
const RATIO_NILE_X10: i64 = 100;
/// The Nile land: Delta to the First Cataract, as a box in degrees (west,
/// east, south, north). PLACEHOLDER until there are provinces.
const NILE_BOX: (f64, f64, f64, f64) = (29.0, 33.5, 24.0, 31.7);
/// S90 (Ramon, 28.10.2026): the field land of Egypt is Butzer's cultivable
/// land of about 150 BC (Early Hydraulic Civilization in Egypt, 1976,
/// table 4: valley 10,000, Faiyum 1,300, Delta 16,000 km², for 4.9
/// million people) instead of HYDE 3.3 (3,900 km² for 4.5 million), spread
/// over the clearable land of the Nile cells, none cleared on top.
const NILE_FIELDS_KM2: f64 = 27_300.0;

/// Longitude and latitude of a 25 km cell centre (data/projection.json:
/// eqc, lat_ts = lat_0 = 41, lon_0 = 19, R = 6,371,008.8 m).
/// Width of a market's region (S70: 100 km regions), for the game's camera.
const REGION_KM: f64 = 100.0;

fn cell_lon_lat(row: i32, col: i32) -> (f64, f64) {
    const R: f64 = 6_371_008.8;
    let (x, z) = (col as f64 * 25_000.0 + 12_500.0, row as f64 * 25_000.0 + 12_500.0);
    (19.0 + (x / (R * 41f64.to_radians().cos())).to_degrees(), 41.0 - (z / R).to_degrees())
}
/// Net kg per ha on cleared land (slopes, forest edge, S73): PLACEHOLDER
/// at 3 : 1 (Spurr: hill country 3–4 : 1).
const NET_POOR: i64 = (RATIO_HILL_X10 - 10) * SEED_KG_HA / 10;
/// PLACEHOLDER (S73 open): share of a cell's other usable land (not
/// HYDE cropland, not bare, snow or above 1500 m) that families can clear,
/// per cent, and how much an adult clears per year after the start, m².
pub const CLEAR_PCT: i64 = 100;
/// Which land families can clear (S73, Ramon 27.10.2026: from land cover):
/// what is farmland today (ESA WorldCover cropland and built-up) on slopes
/// below 16 %, less the HYDE cropland of 200. PLACEHOLDER choice of
/// columns: land that was farmed by today was clearable with Roman tools;
/// grassland and woodland are left out, steeper slopes too (FAO GAEZ class
/// limit). Alternatives and their growth: docs/kit2/run-grain/README.md.
pub const CLEAR_COVER: [&str; 2] = ["farm_8", "farm_16"];
const CLEAR_M2_ADULT_YEAR: i64 = 5_000;
/// Fields lie on fine tiles (S73) within this many tiles of the farmstead
/// (centre to centre). PLACEHOLDER: 8 tiles ≈ 12.5 km at movement scale,
/// about one 25 km cell around the farm; real-size fields (S51) on a map
/// with distances at 1 : 23.8 (S50) have no natural walking limit.
const FIELD_RADIUS: i32 = 8;
/// Share of a farm's fields under grain each year (S76, Brache):
/// PLACEHOLDER two-field rotation, every field fallow every other year
/// (GRAIN-NUMBERS 2: "mit Zweifelderwirtschaft doppelt so viel Land").
/// Fallow land needs no work here (PLACEHOLDER: Roman fallow was ploughed
/// too; the source gives only the yearly total per sown ha).
pub const CROP_PCT: i64 = 50;
/// Work per ha and year, days (Spurr, Rosenstein via Devereaux: 60–80);
/// working days per year (Columella: 290).
const DAYS_PER_HA: i64 = 70;
const WORK_DAYS_YEAR: i64 = 290;
/// PLACEHOLDER (GRAIN-NUMBERS: "Verteilung offen"): shares of the yearly
/// work that fall into sowing and harvest, and the length of each window.
/// The rest is spread over the year and done by the family.
const SOW_SHARE_PCT: i64 = 25;
const HARVEST_SHARE_PCT: i64 = 30;
const PEAK_DAYS: i64 = 40;
const OFF_SHARE_PCT: i64 = 100 - SOW_SHARE_PCT - HARVEST_SHARE_PCT;
const OFF_DAYS: i64 = YEAR - 2 * PEAK_DAYS;
/// PLACEHOLDER: who works. Off-peak the field area a family can till
/// follows the adults 15–60; in the peaks everybody 10–65 works every day.
const ADULT: (f64, f64) = (15.0, 60.0);
const PEAK_HANDS: (f64, f64) = (10.0, 65.0);
/// PLACEHOLDER: share of a week that a person in a tent can sell as day
/// labour, per cent. A farm outside its peak sells the adults' working
/// days its own fields do not need (`spare_week`).
const SPARE_TENT_PCT: i64 = 80;
/// Day wage in grain, kg. PLACEHOLDER from the price edict (VII.1a: farm
/// labourer 25 den. a day with keep) at the base price below: about 3 kg.
const WAGE_KG_DAY: i64 = 3;
/// Base price, milli-denarii per kg. Price edict: 100 den. per modius
/// castrensis; at 1.5–2 modii italici (6.55 kg each) about 7.6–10.2 den./kg.
/// PLACEHOLDER mid value. Money is the edict's denarius throughout.
const BASE_PRICE: i64 = 8_750;
/// PLACEHOLDER (S76: the state has unlimited money, money is a later
/// system): every worker 15–60 who neither farms nor trades (city people,
/// soldiers, clergy) is paid this much per working day by the state; the
/// edict's unskilled day wage, 25 den.
const STATE_WAGE: i64 = 25_000;
/// Loss of stored grain per year, per cent, taken monthly from every farm
/// store, pantry and market store (S72 Verderb). Wheat in farm storage:
/// 4 % (APHLIS 2011, via Stathers, FAO; FAO y4011e: up to 4 %). Ancient
/// granaries kept wheat for years when dry and aired (Varro RR 1.57,
/// Columella 1.6.9–17) but give no rate. PLACEHOLDER: one rate for all
/// stores and climates.
const SPOIL_PCT_YEAR: i64 = 4;
/// PLACEHOLDER: start money of a trader's household (about one cart load
/// at the base price) and of a senator's or eques' household.
const TRADER_MONEY: i64 = 5_000_000;
const ELITE_MONEY: i64 = 1_000_000_000;
/// Tax on the harvest of family and tenant farms, per cent. PLACEHOLDER
/// (S70: "Höhe der Steuer offen"); the Sicilian tithe (decuma) was 10 %.
/// Note for Ramon: Italian land paid no land tax until Diocletian.
const TAX_PCT: i64 = 10;
/// PLACEHOLDER (S69: Pacht offen): tenants give this share of the harvest
/// to the landlord (share-cropping, coloni partiarii).
const RENT_PCT: i64 = 33;
/// PLACEHOLDER: a farm keeps food until the next harvest plus this many
/// days and sells the rest; others buy when their store falls below
/// BUY_BELOW days and buy up to BUY_UP_TO days.
const RESERVE_DAYS: i64 = 60;
const BUY_BELOW: i64 = 30;
const BUY_UP_TO: i64 = 60;
/// Loads and speeds (GRAIN-NUMBERS 3, ORBIS, edict XVII). Family and
/// tenant farms carry with a donkey (PLACEHOLDER: every farm has one),
/// estates with an ox cart, buyers without a farm on foot, traders with a
/// mule wagon over land and by ship over sea.
const DONKEY: (i64, i64) = (97, 30);
const OX_CART: (i64, i64) = (388, 12);
const ON_FOOT: (i64, i64) = (30, 20);
const WAGON: (i64, i64) = (388, 30);
const SEA_KM_DAY: i64 = 100;
/// Freight, milli-denarii per kg and km: wagon 0.035 (edict XVII.3), sea
/// about 0.001 (ORBIS: about 0.1 den. per kg and day at about 100 km).
const WAGON_COST: i64 = 35;
const SEA_COST: i64 = 1;
/// Market (EU5-like, GRAIN.md): the price moves 1/PRICE_STEP of the way
/// to a target each day; the target is the base price × (TARGET_DAYS /
/// days of supply), clamped. Buy and sell price are the price ∓ SPREAD.
/// PLACEHOLDER all.
const PRICE_STEP: i64 = 30;
const TARGET_DAYS: i64 = 90;
const PRICE_MIN_PCT: i64 = 25;
const PRICE_MAX_PCT: i64 = 800;
const SPREAD_PCT: i64 = 10;
/// Traders: at most 32 markets known (GRAIN.md), go when the margin per
/// kg after freight is above this share of the price. PLACEHOLDER.
const KNOWN: usize = 32;
/// Trade roads and sea lanes from traffic (S71): each 25 km cell keeps a
/// smoothed count of trader trips per year (kept share per year in
/// 1/10000: half-life 2 years); a cell becomes a trade track, then a trade
/// road above the first number and falls back below the second (trips per
/// year). On land the wagon freight into the cell falls to
/// LEVEL_COST_PCT; sea lanes are counted but cost the same (ORBIS sea
/// cost is already low). PLACEHOLDER: all numbers frei gewählt.
const ROAD_KEEP: i64 = 7071;
const ROAD_LEVELS: [(i64, i64); 2] = [(100, 50), (400, 200)];
const TRADE_MARGIN_PCT: i64 = 10;
/// Landless (S69): PLACEHOLDER alms at the market, as a share of the
/// household's monthly need, and chance per month to steal from a farm
/// store in the region (and how much).
const ALMS_PCT: i64 = 30;
const STEAL_PER_16: u64 = 5;
const STEAL_KG: i64 = 40;
/// S91 (Ramon, 29.10.2026): a desert cell, whose people live from oasis
/// gardens and herds outside the grain economy: no field or clearable land
/// and more than this share of its land bare (ESA land cover), per cent.
/// PLACEHOLDER.
const DESERT_BARE_PCT: f64 = 50.0;
/// S92 (Ramon, 29.10.2026, Lex Manciana): the landless clear free land and
/// hold it as tenants of the state for a third of the crop; two years
/// without sowing and the land is lost. PLACEHOLDER: at least this much
/// free land in the cell, m².
const MANCIANA_MIN_M2: i64 = 10_000;
const MANCIANA_IDLE_YEARS: u8 = 2;
/// Hunger signal for moving (S66), permille eaten of need. PLACEHOLDER.
const NEED_FED: u16 = 800;
/// S75 (Ramon, 27.10.2026): the landless seek the place with the best
/// chances. Once a month a tent household that did not eat its fill
/// compares its market with the markets within TENT_REACH_DAYS (the market
/// graph's travel days) by what a tent person could get there in a month:
/// the wages paid to day labourers and the work left undone there last
/// month, plus alms from the market store, shared among the tent people
/// there and the newcomers. It moves when a place offers TENT_MOVE_PCT of
/// its own or more. PLACEHOLDER: reach, threshold, the move takes no time,
/// nearness to other tents counts only through the shared work.
const TENT_REACH_DAYS: i64 = 5;
const TENT_MOVE_PCT: i64 = 150;

// Footpaths (Helbing et al. 1997 as in GRAIN.md). Fine raster: tile level
// 7, 16 × 16 per 25 km cell (≈ 1.56 km real). PLACEHOLDER all: wear
// halves in PATH_HALF days; levels with hysteresis; cost factor per level.
const FINE: i32 = 16;
const FINE_STEP: i64 = 100;
const PATH_HALF: i64 = 360;
const WEAR_UNIT: i64 = 1000;
const LEVELS: [(i64, i64); 2] = [(200 * WEAR_UNIT, 100 * WEAR_UNIT), (1000 * WEAR_UNIT, 500 * WEAR_UNIT)];
const LEVEL_COST_PCT: [i64; 3] = [100, 80, 65];
/// Each market's trips are walked (and its field rebuilt if a level
/// changed) once in this many days, 1/WALK_DAYS of the markets a day.
/// PLACEHOLDER for performance; GRAIN.md planned monthly.
const WALK_DAYS: i64 = 90;

const MONTH: i64 = 30;

// Household kinds.
const FARM: u8 = 0;
const TENT: u8 = 1;
const WAGE: u8 = 2;
const TRADER: u8 = 3;
const ELITE: u8 = 4;

// Farm kinds (S69: both).
const FAMILY: u8 = 0;
const TENANT: u8 = 1;
const ESTATE: u8 = 2;

// Trip kinds and event kinds.
/// Kinds of hired work in the view (`work_in`): in the sowing or harvest
/// peak, outside the peaks on a farm with more fields than its family
/// works, from a farm's surplus (S84).
pub const WORK_SOW: u8 = 0;
pub const WORK_HARVEST: u8 = 1;
pub const WORK_OFF: u8 = 2;
pub const WORK_SURPLUS: u8 = 3;
const SELL: u8 = 0;
const BUY: u8 = 1;
const EXPORT: u8 = 2;
const IMPORT: u8 = 3;
const EV_ARRIVE: u8 = 0;
const EV_HOME: u8 = 1;
const EV_PEAK_END: u8 = 2;

fn rnd(seed: u64, a: u32, salt: u32, t: i64) -> u64 {
    let mut b = [0u8; 24];
    b[..8].copy_from_slice(&seed.to_le_bytes());
    b[8..12].copy_from_slice(&a.to_le_bytes());
    b[12..16].copy_from_slice(&salt.to_le_bytes());
    b[16..24].copy_from_slice(&t.to_le_bytes());
    xxh3_64(&b)
}

/// One household from the monthly count of the people.
#[derive(Clone, Copy, Default)]
struct HhInfo {
    home: u32,
    stand: u8,
    job: u8,
    size: u16,
    /// Need in tenths of an adult.
    need_w: u32,
    adults: u16,
    hands: u16,
    /// An adult who walks to the market (a man 15–60 first), NONE if none.
    carrier: u32,
    /// An adult trader of the household, NONE if none.
    trader: u32,
    /// First of the household's members in `Grain::members`.
    at: u32,
}

/// A living person in the monthly snapshot: (household, person, home, sex,
/// job, stand, born).
type Row = (u32, u32, u32, u8, u8, u8, i32);

/// What a household owns, kept between counts.
#[derive(Clone, Copy)]
struct HhState {
    kind: u8,
    pantry: i64,
    money: i64,
    farm: u32,
    /// Fine cell of the house (the farm's for farmers).
    fine: u32,
    fed: u16,
    /// The carrier is on the way; the trader is on the way.
    busy: bool,
    trading: bool,
    /// S91: formed in a desert cell, lives outside the grain economy.
    own_food: bool,
}

#[derive(Clone, Copy)]
struct Peak {
    harvest: bool,
    demand: i64,
    done: i64,
}

struct Farm {
    hh: u32,
    kind: u8,
    landlord: u32,
    cell: u32,
    fine: u32,
    market: u32,
    /// Field area in m² (real size, S51); `poor` of it is cleared land.
    area: i64,
    poor: i64,
    sown: i64,
    /// Net kg per ha.
    net_kg_ha: i64,
    store: i64,
    money: i64,
    harvest_doy: i64,
    sow_doy: i64,
    peak: Option<Peak>,
    to_sell: i64,
    /// Grain sold for the landlord before the farm's own.
    rent_due: i64,
    /// A load came back unsold: try again at the next meal count.
    retry: bool,
    /// Work outside the peaks since the last harvest: needed and done, days.
    off_need: i64,
    off_done: i64,
    /// The fine tiles its fields lie on (S73), in the order taken.
    plots: Vec<Plot>,
    /// S92: cleared under the Lex Manciana, and years in a row unsown.
    manciana: bool,
    idle: u8,
}

/// Part of a fine tile in a farm's fields, m².
#[derive(Clone, Copy)]
struct Plot {
    tile: u32,
    good: u32,
    poor: u32,
}

struct Neigh {
    m: u32,
    /// Freight per kg, milli-denarii.
    cost: i64,
    days: i64,
    route: Vec<u32>,
}

/// Path field of a market over its region: distance (fine steps × 100,
/// weighted by path level) and the direction of the next step.
struct Field {
    r0: i32,
    c0: i32,
    n: i32,
    dist: Vec<u32>,
    dir: Vec<u8>,
    /// Path level and wear per cell, the cells with wear, the day the
    /// wear was last brought up to date and the day the field was built.
    level: Vec<u8>,
    wear: Vec<u32>,
    worn: Vec<u16>,
    walked: i64,
    built: i64,
    /// Reachable cells by distance from the market, nearest first.
    order: Vec<u16>,
}

pub struct Market {
    /// The region's largest listed place (data/gametiles/places.csv), else
    /// "bei" the nearest one.
    pub name: String,
    pub region: u32,
    pub cell: u32,
    pub fine: u32,
    pub store: i64,
    pub money: i64,
    pub price: i64,
    last_week: i64,
    /// Smoothed sales per day, kg × 1000.
    demand: i64,
    sold_today: i64,
    /// Known prices: (market, price, day seen).
    board: Vec<(u32, i64, i64)>,
    neigh: Vec<Neigh>,
    /// Land cells the neighbour search reached, sorted; a road level
    /// change on one of them makes the search `stale`.
    reach: Vec<u32>,
    stale: bool,
    field: Option<Field>,
    dirty: bool,
    /// Trips per origin fine cell since the last walk.
    walked: FxHashMap<u32, i64>,
    /// Farms in a peak that still need hands, and farms with more fields
    /// than their family can work over the year.
    open: Vec<u32>,
    hirers: Vec<u32>,
    /// For the view only (`work_in`): the day of this week's labour
    /// exchange and who worked where: (worker household, farm, days, kind).
    work_day: i64,
    work: Vec<(u32, u32, i64, u8)>,
    pub people: u32,
    pub tents: u32,
    /// Grain in the region (farm stores, market, pantries), kg.
    pub grain: i64,
    pub free_area: i64,
    /// S75: day labour wages paid and work left undone (kg of wage) since
    /// the last count, and as of the last count; people in tents.
    work_acc: i64,
    work_month: i64,
    tent_people: u32,
    /// People in households without a farm that eat from the grain
    /// economy, who buy their food (S93).
    buyers: u32,
}

#[derive(Clone, Copy)]
struct Trip {
    kind: u8,
    pid: u32,
    hh: u32,
    farm: u32,
    market: u32,
    dest: u32,
    kg: i64,
    back_days: i64,
    /// For the view only (`trips_in`): day it left (-1 once home), the fine
    /// tile it left from and a number no other trip has.
    left: i64,
    from: u32,
    serial: u64,
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct GEv {
    kind: u8,
    id: u32,
}


/// Counters, reset by the caller for yearly figures.
#[derive(Default, Clone, Copy, Debug)]
pub struct GrainStats {
    pub harvest_kg: i64,
    pub harvest_lost_kg: i64,
    pub sow_short_m2: i64,
    /// Seed put in the ground, kg; area left unsown for want of seed, m².
    pub seed_kg: i64,
    pub seed_short_m2: i64,
    pub tax_kg: i64,
    pub rent_kg: i64,
    pub hired_days: i64,
    pub wage_kg: i64,
    pub eaten_kg: i64,
    pub need_kg: i64,
    /// Eaten and needed by household kind (farm, tent, wage, trader, elite).
    pub eaten_by: [i64; 5],
    pub need_by: [i64; 5],
    pub sold_kg: i64,
    pub bought_kg: i64,
    pub sell_trips: u64,
    pub buy_trips: u64,
    pub trade_trips: u64,
    pub traded_kg: i64,
    pub trade_profit: i64,
    pub alms_kg: i64,
    pub stolen_kg: i64,
    /// Lost in store (S72 Verderb).
    pub spoiled_kg: i64,
    pub thefts: u64,
    pub farms_taken: u64,
    /// S92: farms cleared under the Lex Manciana and lost after two
    /// years unsown.
    pub manciana_new: u64,
    pub manciana_lost: u64,
    /// S91: people of desert households fed outside the grain economy,
    /// summed over the meals (one per household and month).
    pub own_food_people: u64,
    pub farms_abandoned: u64,
    /// Households without workers or kin sent to the tents (S79).
    pub to_tents: u64,
    /// S75: tent households that moved to a market with better chances.
    pub tent_moves: u64,
    pub field_rebuilds: u64,
    /// Heirs' households given a share of the father's farm (INHERIT_EQUAL).
    pub heirs_given: u64,
    /// S87: farm households that start with a wage instead of a farm.
    pub start_by_wage: u64,
}

#[derive(Default, Clone, Copy, Debug)]
pub struct GrainTiming {
    pub events: f64,
    pub peaks: f64,
    pub labour: f64,
    pub markets: f64,
    pub eat: f64,
    pub traders: f64,
    pub paths: f64,
    pub rebuild: f64,
    pub first_build: f64,
    pub census: f64,
}

/// The money cycle (S94, step 1): where money comes from and where it goes,
/// in milli-denarii since the start. Booking only: nothing here changes
/// what households, farms or dealers do, and it is not in the fingerprint.
/// At every day's end: money held (households, farms, dealers) + the
/// treasury's cash = start + minted + endowed − freight − dissolved −
/// no_payee (`Grain::money_unbooked` is 0).
#[derive(Default, Clone, Copy, Debug)]
pub struct Money {
    /// Held by households, farms and dealers when the run starts (the
    /// PLACEHOLDER start stocks: TRADER_MONEY, ELITE_MONEY, the dealers'
    /// cash, the rent of last year's harvest).
    pub start: i64,
    /// State wages beyond the treasury's cash: the state mints what is
    /// missing (S95).
    pub minted: i64,
    /// Start money of trader and elite households formed after the start.
    pub endowed: i64,
    /// Freight paid by traders (cost per kg of the route); nobody in the
    /// simulation receives it.
    pub freight: i64,
    /// Money of households that died out or were joined to others.
    pub dissolved: i64,
    /// Payments whose receiver is gone: rent for a landlord who died or a
    /// farm without one, a load sold for a trader who died on the way.
    pub no_payee: i64,
}

/// The state's account (S94, step 1), since the start. In: the Manciana
/// third (S92), sold at market with the farm's grain, in money; the tax in
/// kind as grain. Out: the state wage (S76), from cash first, the rest
/// minted (`Money::minted`).
#[derive(Default, Clone, Copy, Debug)]
pub struct Treasury {
    pub cash: i64,
    pub wages: i64,
    pub rent: i64,
    /// Tax grain received, kg. It leaves the economy (no use yet, S76).
    pub grain_kg: i64,
}

/// The flows the history sums per month: births, deaths, hunger deaths,
/// people who left the map, people who moved, then kg harvested, sold,
/// traded, given as alms, stolen, eaten, needed, and days of hired work.
pub const FLOWS: [&str; 13] = ["births", "deaths", "hunger_deaths", "left", "moved", "harvest_kg", "sold_kg", "traded_kg", "alms_kg", "stolen_kg", "eaten_kg", "need_kg", "hired_days"];

/// One month of the history (`Grain::history`), taken after the monthly
/// count: the month's flows (FLOWS) and the levels on that day.
#[derive(Clone, Copy, Debug, Default)]
pub struct HistoryRow {
    pub day: i64,
    pub people: u32,
    pub flows: [i64; 13],
    /// Grain price min / median / max over the markets, by people (den./kg).
    pub price: (f64, f64, f64),
    pub money_held: i64,
    pub minted: i64,
    pub cash: i64,
    pub tax_grain_kg: i64,
    pub tent_people: u32,
    pub farms: usize,
    pub farm_store_kg: i64,
    pub market_store_kg: i64,
}

/// For the view only: the counters as of the end of the last day, the
/// flows since the last row, and the rows. The counters of `stats` may be
/// reset between two days (the yearly run does); a counter below its last
/// value was reset, and its value is then that day's flow.
#[derive(Default)]
struct History {
    last: [i64; 13],
    month: [i64; 13],
    rows: Vec<HistoryRow>,
}

pub struct Grain {
    seed: u64,
    farms: Vec<Farm>,
    pub markets: Vec<Market>,
    /// Market of each 25 km cell (NONE at sea).
    cell_market: Vec<u32>,
    hh: IdMap<HhState>,
    info: IdMap<HhInfo>,
    /// Household ids by day slice (id mod 30), from the last count.
    hh_slices: Vec<Vec<u32>>,
    /// Household ids by market (region), from the last count.
    market_hh: Vec<Vec<u32>>,
    trader_slices: Vec<Vec<u32>>,
    /// Field area in m² that can still be taken per 25 km cell, and the net
    /// yield there.
    free_m2: Vec<i64>,
    free_poor: Vec<i64>,
    net_kg_ha: Vec<i64>,
    /// S91: desert cells (DESERT_BARE_PCT).
    desert: Vec<bool>,
    /// The same free land per fine tile (S73): [good, clearable] m², in
    /// blocks of 256 per 25 km cell with land (`tile_base`, NONE without);
    /// `block_cell` is the cell of each block.
    tiles: Vec<[u16; 2]>,
    tile_base: Vec<u32>,
    block_cell: Vec<u32>,
    /// Fine offsets within a cell's reach, nearest first: (dr, dc, d²).
    offsets: Vec<(i32, i32, i32)>,
    rows_f: i32,
    /// Home spots: villages on the most farmland, listed places.
    settle: crate::settle::Settle,
    /// Farms by day of year of their sowing and harvest start.
    by_doy: Vec<Vec<u32>>,
    trips: Vec<Trip>,
    free_trips: Vec<u32>,
    trip_serial: u64,
    wheel: Vec<Vec<GEv>>,
    decay: std::sync::Arc<Vec<i64>>,
    /// Share of the fields under grain, per cent (`CROP_PCT`).
    crop_pct: i64,
    /// Reused buffer for the monthly count.
    scratch: Vec<Row>,
    /// Person ids grouped by household, from the last count.
    members: Vec<u32>,
    /// The monthly count, running on another thread.
    census_job: Option<std::thread::JoinHandle<(IdMap<HhInfo>, Vec<u32>, Vec<Row>)>>,
    /// Trader traffic per 25 km cell (roads and sea lanes, S71), counted.
    pub lanes: FxHashMap<u32, i64>,
    /// Per 25 km cell: trips this year, smoothed trips per year × 1000,
    /// trade road level (S71); generation bumped when a level changes.
    road_trips: Vec<i64>,
    road_rate: Vec<i64>,
    road_level: Vec<u8>,
    /// Market index at each 25 km cell (NONE elsewhere).
    market_at: Vec<u32>,
    /// The neighbour search's inputs, its thread and the markets it is
    /// searching for today.
    net: std::sync::Arc<Net>,
    road_worker: Option<RoadWorker>,
    road_todo: Vec<usize>,
    walk_worker: Option<WalkWorker>,
    walking: bool,
    cols_f: i32,
    pub stats: GrainStats,
    pub timing: GrainTiming,
    pub money: Money,
    pub treasury: Treasury,
    history: History,
}

fn doy(day: i64) -> i64 {
    day.rem_euclid(YEAR)
}

/// Clearable share of the land per 25 km cell (row, col), S73.
pub type Clearable = FxHashMap<(i32, i32), f64>;

/// Reads sim/inputs/landcover25.csv (tools/sim_landcover.py: ESA WorldCover
/// 2021 and Copernicus DEM per cell, as shares of land by cover group and
/// slope band) and sums the named columns, e.g. `farm_8`, `grass_16`.
pub fn clearable(root: &std::path::Path, columns: &[String]) -> Result<Clearable, String> {
    let path = root.join("sim/inputs/landcover25.csv");
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut lines = text.lines();
    let head: Vec<&str> = lines.next().unwrap_or("").split(',').collect();
    let pick: Vec<usize> = columns
        .iter()
        .map(|c| head.iter().position(|h| h == c).ok_or(format!("no column {c} in {}", path.display())))
        .collect::<Result<_, _>>()?;
    let mut out = Clearable::default();
    for l in lines {
        let v: Vec<&str> = l.split(',').collect();
        let num = |k: usize| v[k].parse::<f64>().map_err(|e| format!("{l}: {e}"));
        let (r, c) = (num(0)? as i32, num(1)? as i32);
        let mut share = 0.0;
        for &k in &pick {
            share += num(k)?;
        }
        out.insert((r, c), share);
    }
    Ok(out)
}

/// Land cover per fine tile (S73): land, farm_8 and farm_16 samples of
/// each of the 256 tiles of a 25 km cell (row, col), from
/// sim/inputs/landcover-fine.bin.zst (tools/sim_landcover.py). With
/// `farmland`, a cell's fields lie on its farmland tiles (the default
/// clearable columns); otherwise on all its land.
pub struct FineCover {
    data: Vec<u8>,
    cells: FxHashMap<(i32, i32), usize>,
    pub farmland: bool,
}

impl FineCover {
    /// The samples of a 25 km cell (absolute row, col) per tile: 768
    /// bytes, land [0..256], farm_8 [256..512], farm_16 [512..768], each
    /// row-major (tile row * 16 + tile col; fine index fr * cols_f + fc).
    pub fn get(&self, key: (i32, i32)) -> Option<&[u8]> {
        self.cells.get(&key).map(|&o| &self.data[o + 8..o + 8 + 3 * 256])
    }
}

/// body::work_factor of a share eaten (per mille), per mille, from a table.
fn work_of_fed(fed: u16) -> i64 {
    static TAB: std::sync::OnceLock<Vec<i64>> = std::sync::OnceLock::new();
    let tab = TAB.get_or_init(|| (0..=1000).map(|k| (crate::body::work_factor(k as f64 / 1000.0) * 1000.0).round() as i64).collect());
    tab[(fed as usize).min(1000)]
}

/// A farm's store and money on 1 January as last year's harvest left them
/// (S84 a), by the rules of a normal year: the crop of its fields under
/// grain, fully worked, less tax; the rent carried to market at the base
/// price (its money to the landlord); the surplus stays in the store, as
/// the dealers' cash does not buy it (it pays day labour, `labour`); then
/// the family's food from the harvest to the new year and the autumn's
/// seed. Returns (store, rent), kg.
fn last_harvest(f: &Farm, cropped: i64, need_day: i64) -> (i64, i64) {
    let sown = cropped;
    let poor = if f.area == 0 { 0 } else { sown * f.poor / f.area };
    let crop = ((sown - poor) * f.net_kg_ha + poor * NET_POOR + sown * SEED_KG_HA) / 10_000;
    let seed = sown * SEED_KG_HA / 10_000;
    let net = (crop - seed).max(0);
    let tax = net * TAX_PCT / 100;
    let rent = if f.kind == TENANT { net * RENT_PCT / 100 } else { 0 };
    let mut store = crop - tax - rent;
    // From the harvest to the new year: food, then the autumn's seed.
    store = (store - need_day * (YEAR - f.harvest_doy)).max(0);
    store = (store - seed).max(0);
    (store, rent)
}


pub fn fine_cover(root: &std::path::Path, farmland: bool) -> Result<FineCover, String> {
    let path = root.join("sim/inputs/landcover-fine.bin.zst");
    let raw = std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let b = zstd::decode_all(&raw[..]).map_err(|e| format!("{}: {e}", path.display()))?;
    const REC: usize = 8 + 3 * 256;
    if b.len() % REC != 0 {
        return Err(format!("{}: {} bytes", path.display(), b.len()));
    }
    let mut cells = FxHashMap::default();
    for (k, r) in b.chunks_exact(REC).enumerate() {
        let key = (i32::from_le_bytes(r[0..4].try_into().unwrap()), i32::from_le_bytes(r[4..8].try_into().unwrap()));
        cells.insert(key, k * REC);
    }
    Ok(FineCover { data: b, cells, farmland })
}

/// Splits `total` by `w` (all 1 if `w` sums to 0), whole m²: shares
/// rounded down, the rest one by one to the weighted tiles in order.
fn spread(total: i64, w: &[u64; 256]) -> [i64; 256] {
    let mut out = [0i64; 256];
    let ones = [1u64; 256];
    let w = if w.iter().sum::<u64>() == 0 { &ones } else { w };
    let sum: u64 = w.iter().sum();
    for (o, &x) in out.iter_mut().zip(w) {
        *o = (total as i128 * x as i128 / sum as i128) as i64;
    }
    let mut rest = total - out.iter().sum::<i64>();
    while rest > 0 {
        for (o, &x) in out.iter_mut().zip(w) {
            if rest > 0 && x > 0 {
                *o += 1;
                rest -= 1;
            }
        }
    }
    out
}

/// Days from `day` to the next day of year `target`.
fn doy_until(day: i64, target: i64) -> i64 {
    (target - doy(day)).rem_euclid(YEAR)
}

impl Grain {
    pub fn new(inp: &Inputs, p: &mut People) -> Grain {
        Self::with_clearing(inp, p, CLEAR_PCT, None, None, CROP_PCT)
    }

    /// As `new`, with the share of clearable land in per cent and, if
    /// given, the clearable share of each cell's land from land cover
    /// (`clearable`) instead of all usable land, and the share of the
    /// fields under grain each year (`CROP_PCT`; 100 = no fallow). The
    /// free land of a cell lies on its fine tiles by `fine` (S73), evenly
    /// without it.
    pub fn with_clearing(inp: &Inputs, p: &mut People, clear_pct: i64, cover: Option<&Clearable>, fine: Option<&FineCover>, crop_pct: i64) -> Grain {
        let seed = p.world.resource::<Clock>().seed;
        let g = &p.grid;
        let n = g.kind.len();
        let (rows_f, cols_f) = (g.rows * FINE, g.cols * FINE);
        // Field land per cell: the HYDE 3.3 cropland of 200 (real km²),
        // scaled by area 1 : 566.5 (S50) into real-size m² (S51).
        // PLACEHOLDER: S73 lets families clear slopes and forest edges
        // too; how much land that adds needs land cover data and is open.
        let mut free_m2 = vec![0i64; n];
        let mut free_poor = vec![0i64; n];
        let mut net = vec![0i64; n];
        let mut usable_m2 = vec![0i64; n];
        let mut desert = vec![false; n];
        let usable_km2 = |r: i32, c: i32, cell: &crate::Cell| match cover {
            Some(m) => cell.land_km2 * m.get(&(r, c)).copied().unwrap_or(0.0),
            None => cell.land_km2 * (1.0 - cell.frac_bare - cell.frac_snow - cell.frac_above_1500m).max(0.0),
        };
        let in_nile = |r: i32, c: i32| {
            let (lon, lat) = cell_lon_lat(r, c);
            (NILE_BOX.0..NILE_BOX.1).contains(&lon) && (NILE_BOX.2..NILE_BOX.3).contains(&lat)
        };
        // S90: Butzer's Egypt over the Nile cells' usable land (summed in
        // cell order, so the share is the same on every run).
        let nile_share = {
            let mut keys: Vec<&(i32, i32)> = inp.cells.keys().filter(|&&(r, c)| in_nile(r, c)).collect();
            keys.sort_unstable();
            let sum: f64 = keys.iter().map(|&&(r, c)| usable_km2(r, c, &inp.cells[&(r, c)])).sum();
            if sum > 0.0 { NILE_FIELDS_KM2 / sum } else { 0.0 }
        };
        for (&(r, c), cell) in &inp.cells {
            let Some(i) = g.index(r, c) else { continue };
            let crop = cell.hyde.as_ref().map_or(0.0, |h| h.crop_km2);
            free_m2[i as usize] = (crop * 1e6 / crate::people::PEOPLE_PER_PERSON) as i64;
            let usable = usable_km2(r, c, cell);
            free_poor[i as usize] = ((usable - crop).max(0.0) * 1e6 / crate::people::PEOPLE_PER_PERSON) as i64 * clear_pct / 100;
            usable_m2[i as usize] = (usable * 1e6 / crate::people::PEOPLE_PER_PERSON) as i64;
            let hill = (cell.frac_above_1500m * 2.0).clamp(0.0, 1.0);
            let nile = in_nile(r, c);
            if nile {
                free_m2[i as usize] = (usable * nile_share * 1e6 / crate::people::PEOPLE_PER_PERSON) as i64;
                free_poor[i as usize] = 0;
            }
            let ratio = if nile { RATIO_NILE_X10 as f64 } else { RATIO_PLAIN_X10 as f64 - hill * (RATIO_PLAIN_X10 - RATIO_HILL_X10) as f64 };
            net[i as usize] = ((ratio - 10.0) * SEED_KG_HA as f64 / 10.0) as i64;
            desert[i as usize] = free_m2[i as usize] + free_poor[i as usize] == 0 && cell.frac_bare * 100.0 > DESERT_BARE_PCT;
        }
        // Free land on fine tiles (S73). The cell's fields lie on its
        // farmland tiles (by farm_8 + farm_16 samples) up to the farmland
        // there, the rest (HYDE cropland beyond today's farmland) on its
        // land tiles; the good (HYDE) land first on the flat farmland
        // (farm_8), the rest of each tile is clearable.
        let mut tiles: Vec<[u16; 2]> = Vec::new();
        let mut tile_base = vec![NONE; n];
        let mut block_cell = Vec::new();
        for i in 0..n {
            let (good, poor) = (free_m2[i], free_poor[i]);
            if good + poor == 0 {
                continue;
            }
            let (r, c) = (i as i32 / g.cols + g.row0, i as i32 % g.cols + g.col0);
            let fc = fine.and_then(|f| f.get((r, c)).map(|t| (f.farmland, t)));
            let w = |k: usize| -> [u64; 256] { std::array::from_fn(|t| fc.map_or(0, |(_, x)| x[k * 256 + t] as u64)) };
            let (land, flat, steep) = (w(0), w(1), w(2));
            let farm: [u64; 256] = std::array::from_fn(|t| flat[t] + steep[t]);
            let on_farm = match fc {
                Some((true, _)) if farm.iter().sum::<u64>() > 0 => (good + poor).min(usable_m2[i].max(poor)),
                _ => 0,
            };
            let a = spread(on_farm, &farm);
            let b = spread(good + poor - on_farm, &land);
            let mut cap: [i64; 256] = std::array::from_fn(|t| a[t] + b[t]);
            // A tile holds no more than its area (eqc, data/projection.json:
            // true at 41° N, east-west by cos(lat) / cos(41°) elsewhere);
            // the rest goes to the cell's other land tiles with room, and
            // stays over if the cell is full (the 25 km land and cover
            // data do not quite agree).
            let room = tile_room_m2(r);
            let mut over = 0;
            for x in cap.iter_mut() {
                over += (*x - room).max(0);
                *x = (*x).min(room);
            }
            for t in 0..256 {
                if over > 0 && (fc.is_none() || land[t] > 0) {
                    let k = over.min(room - cap[t]).max(0);
                    cap[t] += k;
                    over -= k;
                }
            }
            if over > 0 {
                let more = spread(over, &land);
                for t in 0..256 {
                    cap[t] += more[t];
                }
            }
            let mut gd = spread(good, if flat.iter().sum::<u64>() > 0 { &flat } else { &farm });
            let mut left = good;
            for t in 0..256 {
                gd[t] = gd[t].min(cap[t]);
                left -= gd[t];
            }
            for t in 0..256 {
                let k = left.min(cap[t] - gd[t]);
                gd[t] += k;
                left -= k;
            }
            debug_assert_eq!(left, 0);
            tile_base[i] = tiles.len() as u32;
            block_cell.push(i as u32);
            tiles.extend((0..256).map(|t| [u16::try_from(gd[t]).expect("tile land"), u16::try_from(cap[t] - gd[t]).expect("tile land")]));
        }
        let mut offsets: Vec<(i32, i32, i32)> = Vec::new();
        for dr in -(FINE - 1)..FINE {
            for dc in -(FINE - 1)..FINE {
                offsets.push((dr, dc, dr * dr + dc * dc));
            }
        }
        offsets.sort_unstable_by_key(|&(dr, dc, d)| (d, dr, dc));
        // Markets: one per 100 km region with land (S70), at the largest
        // listed place (Hanson 117), else at the cell with most people.
        let mut place_pop: FxHashMap<u32, f64> = FxHashMap::default();
        let mut place_xz: FxHashMap<u32, (f64, f64)> = FxHashMap::default();
        // Largest listed place of each region, for the market's name.
        let mut region_place: FxHashMap<u32, (f64, usize)> = FxHashMap::default();
        for (ci, c) in inp.cities.iter().enumerate() {
            let (r, col) = ((c.z_m / 25_000.0).floor() as i32, (c.x_m / 25_000.0).floor() as i32);
            if let Some(i) = g.index(r, col) {
                let e = region_place.entry(g.region(i)).or_insert((-1.0, ci));
                if c.pop > e.0 {
                    *e = (c.pop, ci);
                }
                let e = place_pop.entry(i).or_default();
                if c.pop > *e {
                    place_xz.insert(i, (c.x_m, c.z_m));
                }
                *e += c.pop;
            }
        }
        let mut best: FxHashMap<u32, (i64, u32)> = FxHashMap::default();
        for i in 0..n as u32 {
            if g.kind[i as usize] == 0 {
                continue;
            }
            let score = place_pop.get(&i).map_or(0, |&v| 1_000_000_000 + v as i64) + p.pop[i as usize] as i64;
            let e = best.entry(g.region(i)).or_insert((-1, i));
            if score > e.0 || (score == e.0 && i < e.1) {
                *e = (score, i);
            }
        }
        let mut regions: Vec<(u32, u32)> = best.into_iter().map(|(k, (_, i))| (k, i)).collect();
        regions.sort_unstable();
        let fine_of = |i: u32, sub: u64| -> u32 {
            let (r, c) = (i as i32 / g.cols, i as i32 % g.cols);
            let (fr, fc) = (r * FINE + (sub % FINE as u64) as i32, c * FINE + ((sub >> 8) % FINE as u64) as i32);
            (fr * cols_f + fc) as u32
        };
        let mut markets = Vec::new();
        let mut market_of = FxHashMap::default();
        let city_name = |ci: usize| inp.city_names.get(ci).cloned().unwrap_or_default();
        for &(k, i) in &regions {
            // The region's largest listed place, else "bei" the nearest one.
            let name = match region_place.get(&k) {
                Some(&(_, ci)) => city_name(ci),
                None => {
                    let (x, z) = ((i as i32 % g.cols + g.col0) as f64 * 25_000.0 + 12_500.0, (i as i32 / g.cols + g.row0) as f64 * 25_000.0 + 12_500.0);
                    let near = inp.cities.iter().enumerate().min_by(|a, b| ((a.1.x_m - x).powi(2) + (a.1.z_m - z).powi(2)).total_cmp(&((b.1.x_m - x).powi(2) + (b.1.z_m - z).powi(2))).then(a.0.cmp(&b.0)));
                    near.map_or_else(|| format!("Region {}/{}", k >> 16, k & 0xffff), |(ci, _)| format!("bei {}", city_name(ci)))
                }
            };
            let fine = match place_xz.get(&i) {
                Some(&(x, z)) => {
                    let fr = (z / 1562.5).floor() as i32 - g.row0 * FINE;
                    let fc = (x / 1562.5).floor() as i32 - g.col0 * FINE;
                    (fr.clamp(0, rows_f - 1) * cols_f + fc.clamp(0, cols_f - 1)) as u32
                }
                None => fine_of(i, 8 | 8 << 8),
            };
            market_of.insert(k, markets.len() as u32);
            markets.push(Market {
                name,
                region: k,
                cell: i,
                fine,
                store: 0,
                money: 0,
                price: BASE_PRICE,
                last_week: BASE_PRICE,
                demand: 0,
                sold_today: 0,
                board: Vec::new(),
                neigh: Vec::new(),
                reach: Vec::new(),
                stale: false,
                field: None,
                work_acc: 0,
                work_month: 0,
                tent_people: 0,
                buyers: 0,
                dirty: true,
                walked: FxHashMap::default(),
                open: Vec::new(),
                hirers: Vec::new(),
                work_day: 0,
                work: Vec::new(),
                people: 0,
                tents: 0,
                grain: 0,
                free_area: 0,
            });
        }
        let cell_market: Vec<u32> = (0..n as u32).map(|i| if g.kind[i as usize] == 0 { NONE } else { market_of[&g.region(i)] }).collect();
        let mut gr = Grain {
            cell_market,
            seed,
            farms: Vec::new(),
            markets,
            hh: IdMap::default(),
            info: IdMap::default(),
            hh_slices: vec![Vec::new(); MONTH as usize],
            market_hh: Vec::new(),
            trader_slices: vec![Vec::new(); 7],
            free_m2,
            free_poor,
            net_kg_ha: net,
            desert,
            tiles,
            tile_base,
            block_cell,
            offsets,
            rows_f,
            settle: {
                // Seed 1 as in the people view (view.rs), so both show the
                // same spots.
                let lookup = |r: i32, c: i32| fine.and_then(|cv| cv.get((r, c)));
                crate::settle::Settle::new(&p.grid, &p.pop, &inp.cities, fine.map(|_| &lookup as crate::settle::CoverOf), 1)
            },
            by_doy: vec![Vec::new(); YEAR as usize],
            trips: Vec::new(),
            free_trips: Vec::new(),
            trip_serial: 0,
            wheel: vec![Vec::new(); 1024],
            decay: std::sync::Arc::new(decay_table()),
            crop_pct: crop_pct.clamp(1, 100),
            scratch: Vec::new(),
            members: Vec::new(),
            census_job: None,
            lanes: FxHashMap::default(),
            road_trips: vec![0; n],
            road_rate: vec![0; n],
            road_level: vec![0; n],
            market_at: Vec::new(),
            net: std::sync::Arc::new(Net { row0: 0, col0: 0, rows: 0, cols: 0, kind: Vec::new(), at: Vec::new(), level: Vec::new() }),
            road_worker: None,
            road_todo: Vec::new(),
            walk_worker: None,
            walking: false,
            cols_f,
            stats: GrainStats::default(),
            timing: GrainTiming::default(),
            money: Money::default(),
            treasury: Treasury::default(),
            history: History::default(),
        };
        gr.build_graph(p);
        gr.census(p, 0, true);
        // Start stocks: farms hold what last year's harvest left them
        // (`last_harvest`); PLACEHOLDER, so the first half year is not an
        // artefact of starting in January: markets the region's buyers'
        // need until midsummer plus the reserve, households without a farm
        // a month, the landless three.
        let mut demand = vec![0i64; gr.markets.len()];
        let mut lords: Vec<(u32, i64)> = Vec::new();
        let ids: Vec<u32> = sorted_keys(&gr.hh);
        for id in ids {
            let info = gr.info[&id];
            let need_day = info.need_w as i64 * KG_PER_ADULT_YEAR / 10 / YEAR;
            let s = gr.hh.get_mut(&id).unwrap();
            if s.kind == FARM {
                let k = s.farm as usize;
                let cropped = gr.cropped(gr.farms[k].area);
                let f = &mut gr.farms[k];
                // At least food to the harvest plus the reserve, so that no
                // farm starts empty (PLACEHOLDER for farms whose fields fed
                // them less last year: what they then lived on).
                let (store, rent) = last_harvest(f, cropped, need_day);
                f.store = store.max(need_day * (f.harvest_doy + RESERVE_DAYS));
                let lord = f.landlord;
                let to_lord = rent * BASE_PRICE;
                if to_lord > 0 && lord != NONE {
                    lords.push((lord, to_lord));
                }
            } else {
                s.pantry = need_day * if s.kind == TENT { 3 * MONTH } else { MONTH };
                let m = gr.cell_market[info.home as usize];
                demand[m as usize] += need_day;
            }
        }
        for (lord, pay) in lords {
            if let Some(h) = gr.hh.get_mut(&lord) {
                h.money += pay;
            }
        }
        // Dealers start with the cash for 60 days of their buyers' demand
        // at the base price, at least one donkey load (PLACEHOLDER).
        for (m, d) in gr.markets.iter_mut().zip(demand) {
            m.store = d * (180 + RESERVE_DAYS);
            m.demand = d * 1000;
            m.money = (d * 60).max(DONKEY.0) * BASE_PRICE;
        }
        // S92 at the start, after the stocks (the landless counted as the
        // market's buyers).
        let ids = sorted_keys(&gr.info);
        gr.manciana(p, &ids, true);
        gr.regroup();
        gr.sums();
        gr.export(p);
        gr.money.start = gr.money_held();
        gr
    }

    /// Market graph over the 25 km grid by freight cost (wagon over land,
    /// ship over sea, ports at coast cells): each market's 32 cheapest
    /// markets with cost, days and route. Built once at the start.
    fn build_graph(&mut self, p: &People) {
        let mut at = vec![NONE; p.grid.kind.len()];
        for (k, m) in self.markets.iter().enumerate() {
            at[m.cell as usize] = k as u32;
        }
        self.market_at = at;
        self.net = std::sync::Arc::new(Net { row0: p.grid.row0, col0: p.grid.col0, rows: p.grid.rows, cols: p.grid.cols, kind: p.grid.kind.clone(), at: self.market_at.clone(), level: self.road_level.clone() });
        let cells: Vec<u32> = self.markets.iter().map(|m| m.cell).collect();
        let net = &*self.net;
        let built: Vec<(Vec<Neigh>, Vec<u32>)> = bevy_tasks::ComputeTaskPool::get()
            .scope(|s| {
                for chunk in cells.chunks(cells.len().div_ceil(16).max(1)) {
                    s.spawn(async move { chunk.iter().map(|&c| neighbours(net, c)).collect::<Vec<_>>() });
                }
            })
            .into_iter()
            .flatten()
            .collect();
        for (m, (nb, reach)) in self.markets.iter_mut().zip(built) {
            m.board = nb.iter().map(|x| (x.m, BASE_PRICE, 0)).collect();
            m.neigh = nb;
            m.reach = reach;
        }
    }

    /// Trade roads (S71): once a year the year's trips per cell go into the
    /// smoothed rate and the levels; a market whose last neighbour search
    /// touched a land cell whose level changed searches again on its day
    /// (1/360 of the markets a day, on the task pool). Known prices are
    /// kept for markets still known.
    fn roads(&mut self, day: i64) {
        if doy(day) == 0 && day > 0 {
            let mut changed: Vec<u32> = Vec::new();
            for c in 0..self.road_rate.len() {
                let t = std::mem::take(&mut self.road_trips[c]);
                if t == 0 && self.road_rate[c] == 0 {
                    continue;
                }
                let r = (self.road_rate[c] * ROAD_KEEP + t * 1000 * (10_000 - ROAD_KEEP)) / 10_000;
                self.road_rate[c] = r;
                let old = self.road_level[c];
                let mut lv = old;
                while (lv as usize) < ROAD_LEVELS.len() && r >= ROAD_LEVELS[lv as usize].0 * 1000 {
                    lv += 1;
                }
                while lv > 0 && r < ROAD_LEVELS[lv as usize - 1].1 * 1000 {
                    lv -= 1;
                }
                if lv != old {
                    self.road_level[c] = lv;
                    if self.net.kind[c] != 0 {
                        changed.push(c as u32);
                    }
                }
            }
            for m in self.markets.iter_mut() {
                m.stale |= changed.iter().any(|c| m.reach.binary_search(c).is_ok());
            }
            if !changed.is_empty() {
                let net = &*self.net;
                self.net = std::sync::Arc::new(Net { row0: net.row0, col0: net.col0, rows: net.rows, cols: net.cols, kind: net.kind.clone(), at: net.at.clone(), level: self.road_level.clone() });
            }
        }
        let todo: Vec<usize> = (doy(day) as usize..self.markets.len()).step_by(YEAR as usize).filter(|&mi| self.markets[mi].stale).collect();
        if todo.is_empty() {
            return;
        }
        // Searched on the road thread while the day goes on; taken over at
        // the start of the next (`roads_done`), before the traders' news
        // read the neighbours again.
        let cells: Vec<u32> = todo.iter().map(|&mi| self.markets[mi].cell).collect();
        let w = self.road_worker.get_or_insert_with(RoadWorker::new);
        w.send.send((self.net.clone(), cells)).expect("road worker");
        self.road_todo = todo;
    }

    /// Takes over the neighbour searches started by `roads` the day before.
    fn roads_done(&mut self) {
        if self.road_todo.is_empty() {
            return;
        }
        let built = self.road_worker.as_ref().expect("road worker").recv.recv().expect("road worker");
        let todo = std::mem::take(&mut self.road_todo);
        for (mi, (nb, reach)) in todo.into_iter().zip(built) {
            let m = &mut self.markets[mi];
            let old = std::mem::take(&mut m.board);
            m.board = nb.iter().map(|x| old.iter().find(|o| o.0 == x.m).copied().unwrap_or((x.m, BASE_PRICE, 0))).collect();
            m.neigh = nb;
            m.reach = reach;
            m.stale = false;
        }
    }

    fn need_day(&self, id: u32) -> i64 {
        self.info.get(&id).map_or(0, |i| i.need_w as i64 * KG_PER_ADULT_YEAR / 10 / YEAR)
    }

    /// Snapshot of the living at home (one pass over the tables, in table
    /// order; `count_households` puts it in id order).
    fn snapshot(&mut self, p: &mut People) -> (Vec<Row>, u32) {
        let mut rows = std::mem::take(&mut self.scratch);
        rows.clear();
        let mut q = p.world.query_filtered::<(&Pid, &Household, &Home, &Born, &Sex, &Job, &Stand), Without<Travel>>();
        rows.extend(q.iter(&p.world).map(|(pid, hh, home, born, sex, job, stand)| (hh.0, pid.0, home.0, sex.0, job.0, stand.0, born.0)));
        (rows, p.next_pid())
    }

    /// Monthly count of the households, at once (start of the run).
    fn census(&mut self, p: &mut People, day: i64, start: bool) {
        let (rows, n) = self.snapshot(p);
        let (info, members, scratch) = count_households(rows, n, day);
        (self.info, self.members, self.scratch) = (info, members, scratch);
        self.reconcile(p, start);
        self.assign_free(p, start);
        self.regroup();
        self.sums();
    }

    /// The monthly count, spread over a week so no day carries more than
    /// about a millisecond of it (like the people's index): the snapshot
    /// is taken now and counted on another thread; `finish_census` takes
    /// the result over three days later (the thread has two full days),
    /// then free farms are given out, then `regroup`, then `sums`, a day
    /// each. The count is new to this core, so each pass over it is
    /// mostly cache misses.
    fn start_census(&mut self, p: &mut People, day: i64) {
        let (rows, n) = self.snapshot(p);
        self.census_job = Some(std::thread::spawn(move || count_households(rows, n, day)));
    }

    fn finish_census(&mut self, p: &mut People) {
        if let Some(job) = self.census_job.take() {
            let (info, members, scratch) = job.join().expect("census thread");
            (self.info, self.members, self.scratch) = (info, members, scratch);
            self.reconcile(p, false);
        }
    }

    /// After a count: new households get a kind; farms of households that
    /// moved away or died out are given to landless households of the same
    /// region (S69: a free farm is taken automatically).
    fn reconcile(&mut self, p: &mut People, start: bool) {
        if !start && p.inherit == crate::people::INHERIT_EQUAL {
            let log = std::mem::take(&mut p.split_log);
            self.inherit_equal(&log);
        }
        // Households gone or moved: free their farm.
        let ids = sorted_keys(&self.hh);
        for id in ids {
            let s = self.hh[&id];
            let gone = match self.info.get(&id) {
                None => true,
                Some(i) => s.farm != NONE && self.farms[s.farm as usize].cell != i.home,
            };
            if gone {
                if s.farm != NONE {
                    let f = &mut self.farms[s.farm as usize];
                    f.hh = NONE;
                    self.stats.farms_abandoned += 1;
                }
                if self.info.contains_key(&id) {
                    // Moved: landless in the new place.
                    let h = self.hh.get_mut(&id).unwrap();
                    h.farm = NONE;
                    h.kind = TENT;
                } else {
                    self.money.dissolved += s.money;
                    self.hh.remove(&id);
                }
            }
        }
        // S79: a household with nobody of working age and no relative to
        // join goes to the tents; its farm is free (the store stays with
        // the farm, the pantry with the household). Relatives are joined
        // by people.rs on the household's day in the year.
        if !start {
            let ids = sorted_keys(&self.info);
            for id in ids {
                let i = self.info[&id];
                let Some(s) = self.hh.get(&id).copied() else { continue };
                if i.adults > 0 || s.kind == TENT || !p.alone_without_workers(&self.members[i.at as usize..(i.at + i.size as u32) as usize]) {
                    continue;
                }
                if s.farm != NONE {
                    self.farms[s.farm as usize].hh = NONE;
                    self.stats.farms_abandoned += 1;
                }
                let h = self.hh.get_mut(&id).unwrap();
                h.farm = NONE;
                h.kind = TENT;
                self.stats.to_tents += 1;
            }
        }
        // New households.
        let ids = sorted_keys(&self.info);
        // S87 (Ramon, 28.10.2026): at the start, farm households beyond
        // what their cell's land can feed (lowest id first keeps a farm;
        // PLACEHOLDER order) live by a wage instead: they become
        // craftsmen (Handwerker, PLACEHOLDER) and buy their grain at the
        // market. Such places lived by crafts and imported grain (Attica,
        // Rome's hinterland, Phoenicia; Garnsey 1988).
        let mut by_wage: FxHashMap<u32, ()> = FxHashMap::default();
        if start {
            let mut used: FxHashMap<u32, i64> = FxHashMap::default();
            for &id in &ids {
                let i = self.info[&id];
                if i.stand > CITY || !matches!((i.stand, i.job), (_, BAUERN) | (RURAL, PAECHTER) | (RURAL, UNFREIE)) || self.desert[i.home as usize] {
                    continue;
                }
                let c = i.home as usize;
                let feed = i.need_w as i64 * KG_PER_ADULT_YEAR / 10 * 10_000 / self.net_kg_ha[c].max(1) * 100 / self.crop_pct;
                let u = used.entry(i.home).or_default();
                if *u + feed > self.free_m2[c] + self.free_poor[c] {
                    by_wage.insert(id, ());
                    for &m in &self.members[i.at as usize..(i.at + i.size as u32) as usize] {
                        if let Some(e) = p.alive_entity(m) {
                            let mut j = p.world.get_mut::<Job>(e).unwrap();
                            if matches!(j.0, BAUERN | PAECHTER | UNFREIE) {
                                j.0 = HANDWERKER;
                            }
                        }
                    }
                } else {
                    *u += feed;
                }
            }
            self.stats.start_by_wage = by_wage.len() as u64;
        }
        for &id in &ids {
            if self.hh.contains_key(&id) {
                continue;
            }
            let i = self.info[&id];
            let kind = match (i.stand, i.job) {
                (s, _) if s > CITY => ELITE,
                (_, BAUERN) | (RURAL, PAECHTER) | (RURAL, UNFREIE) => FARM,
                (RURAL, TAGELOEHNER) => TENT,
                _ if i.trader != NONE => TRADER,
                _ => WAGE,
            };
            // The farmstead (or house) stands at the household's village or
            // place (settle.rs, the same spots the people view shows).
            let fine = self.settle.home_fine(i.home, id, i.stand);
            let money = match kind {
                ELITE => ELITE_MONEY,
                TRADER => TRADER_MONEY,
                _ => 0,
            };
            // Start of the run: new farms. Later, households only arise by
            // the count after a birth into a new id, which does not happen
            // (children stay in the household); moved households are tents.
            let kind = if kind == FARM && !start { TENT } else { kind };
            let kind = if kind == FARM && by_wage.contains_key(&id) { WAGE } else { kind };
            // S91: a household formed in a desert cell feeds itself (oasis
            // gardens, dates, herds); a farmer there has no fields.
            let own_food = self.desert[i.home as usize];
            let kind = if own_food && kind == FARM { WAGE } else { kind };
            let farm = if kind == FARM { self.new_farm(p, id, &i, fine) } else { NONE };
            if !start {
                self.money.endowed += money;
            }
            self.hh.insert(id, HhState { kind, pantry: 0, money, farm, fine, fed: 1000, busy: false, trading: false, own_food });
        }
        if start {
            self.share_land(p);
        }
    }

    /// After a count: free farms go to landless households, and the
    /// workers are listed by market.
    fn assign_free(&mut self, p: &mut People, start: bool) {
        let ids = sorted_keys(&self.info);
        // Free farms go to landless households of the same cell first, then
        // of the region (lowest household id first). PLACEHOLDER order.
        let mut free: Vec<u32> = (0..self.farms.len() as u32).filter(|&f| self.farms[f as usize].hh == NONE && self.farms[f as usize].area > 0).collect();
        if !free.is_empty() {
            let mut tents: FxHashMap<u32, Vec<(u32, u32)>> = FxHashMap::default();
            for &id in &ids {
                // Someone must be able to work the farm (S79).
                if self.hh[&id].kind == TENT && self.info[&id].adults > 0 {
                    let home = self.info[&id].home;
                    tents.entry(self.cell_market[home as usize]).or_default().push((home, id));
                }
            }
            for f in free.drain(..) {
                let (cell, mk) = (self.farms[f as usize].cell, self.farms[f as usize].market);
                let Some(list) = tents.get_mut(&mk) else { continue };
                let pick = list.iter().position(|t| t.0 == cell).or(if list.is_empty() { None } else { Some(0) });
                if let Some(k) = pick {
                    let (_, id) = list.remove(k);
                    let home = self.info[&id].home;
                    if home != cell {
                        let i = self.info[&id];
                        p.relocate_household(id, &self.members[i.at as usize..(i.at + i.size as u32) as usize], cell);
                        self.info.get_mut(&id).unwrap().home = cell;
                    }
                    let fine = self.farms[f as usize].fine;
                    let h = self.hh.get_mut(&id).unwrap();
                    h.kind = FARM;
                    h.farm = f;
                    h.fine = fine;
                    h.own_food = false;
                    let fm = &mut self.farms[f as usize];
                    fm.hh = id;
                    fm.store += h.pantry;
                    h.pantry = 0;
                    self.stats.farms_taken += 1;
                }
            }
        }
        if !start {
            self.manciana(p, &ids, false);
        }
        // Workers offered at the market.
        self.market_hh = vec![Vec::new(); self.markets.len()];
        for &id in &ids {
            let mk = self.cell_market[self.info[&id].home as usize] as usize;
            self.market_hh[mk].push(id);
        }
    }

    /// S92 (Lex Manciana): tents with adults clear free land of their cell,
    /// else of the cell of their region with the most free land (with a
    /// village), and become tenants of the state. They take what they want
    /// to till (S73): free good land first, then as much as their adults
    /// clear in a year; the fields grow at each sowing as on every farm.
    /// At the start the law has long been in force: those fields are sown
    /// like the others (PLACEHOLDER, as the start stocks).
    fn manciana(&mut self, p: &mut People, ids: &[u32], start: bool) {
        let free = |g: &Self, c: usize| g.free_m2[c] + g.free_poor[c];
        let ok = |g: &Self, c: usize| free(g, c) >= MANCIANA_MIN_M2 && !g.settle.villages(c as u32).is_empty();
        let mut best: Vec<(i64, u32)> = vec![(0, NONE); self.markets.len()];
        for c in 0..self.free_m2.len() {
            let mk = self.cell_market[c];
            if mk != NONE && ok(self, c) && free(self, c) > best[mk as usize].0 {
                best[mk as usize] = (free(self, c), c as u32);
            }
        }
        for &id in ids {
            let Some(s) = self.hh.get(&id).copied() else { continue };
            let Some(i) = self.info.get(&id).copied() else { continue };
            if s.kind != TENT || i.adults == 0 || s.busy || s.own_food {
                continue;
            }
            let mk = self.cell_market[i.home as usize];
            let cell = if ok(self, i.home as usize) {
                i.home
            } else if mk != NONE && best[mk as usize].1 != NONE && ok(self, best[mk as usize].1 as usize) {
                best[mk as usize].1
            } else {
                continue;
            };
            if cell != i.home {
                p.relocate_household(id, &self.members[i.at as usize..(i.at + i.size as u32) as usize], cell);
                self.info.get_mut(&id).unwrap().home = cell;
            }
            let i = self.info[&id];
            let want = self.want_m2(id);
            let fine = self.settle.home_fine(cell, id, i.stand);
            let f = self.new_farm(p, id, &i, fine) as usize;
            self.farms[f].kind = TENANT;
            self.farms[f].manciana = true;
            let good = self.take_land(f, want, false, true);
            let clear = (want - good).min(i.adults as i64 * CLEAR_M2_ADULT_YEAR * self.work_x1000(id) / 1000).max(0);
            self.take_land(f, clear, true, true);
            if self.farms[f].area == 0 {
                // Nothing to till after all: an empty farm nobody takes.
                self.farms[f].hh = NONE;
                continue;
            }
            let h = self.hh.get_mut(&id).unwrap();
            h.kind = FARM;
            h.farm = f as u32;
            h.fine = fine;
            self.farms[f].store += h.pantry;
            h.pantry = 0;
            if start {
                // Sown last autumn, food to the harvest plus the reserve
                // like every farm at the start.
                let need_day = i.need_w as i64 * KG_PER_ADULT_YEAR / 10 / YEAR;
                let fm = &mut self.farms[f];
                fm.sown = fm.area * self.crop_pct / 100;
                fm.store = fm.store.max(need_day * (fm.harvest_doy + RESERVE_DAYS));
            }
            self.stats.manciana_new += 1;
        }
    }

    /// S92: a Manciana farm that sowed nothing for two years loses its
    /// land; the household goes back to the tent.
    fn manciana_lapse(&mut self, f: usize) {
        let area = self.farms[f].area;
        self.give_land(f, area);
        let id = self.farms[f].hh;
        self.farms[f].hh = NONE;
        let store = std::mem::take(&mut self.farms[f].store);
        if let Some(h) = self.hh.get_mut(&id) {
            h.kind = TENT;
            h.farm = NONE;
            h.pantry += store;
        }
        self.stats.manciana_lost += 1;
    }

    /// Slices for the staggered work and the farms that hire, from the
    /// last count. Until this runs, the old slices may name a household
    /// that is gone (skipped) or miss a new one (eats a few days later).
    fn regroup(&mut self) {
        // The count lists households in id order.
        let ids: Vec<u32> = self.info.iter().map(|(&id, _)| id).collect();
        for v in self.hh_slices.iter_mut() {
            v.clear();
        }
        for v in self.trader_slices.iter_mut() {
            v.clear();
        }
        for &id in &ids {
            self.hh_slices[(id % MONTH as u32) as usize].push(id);
            if self.hh[&id].kind == TRADER {
                self.trader_slices[(id % 7) as usize].push(id);
            }
        }
        for m in self.markets.iter_mut() {
            m.hirers.clear();
        }
        for (k, f) in self.farms.iter().enumerate() {
            if f.hh != NONE && self.cropped(f.area) > self.year_m2(f.hh) {
                self.markets[f.market as usize].hirers.push(k as u32);
            }
        }
    }

    /// People, landless, grain and free land per market, for the people's
    /// migration (`export`) and the reports.
    fn sums(&mut self) {
        for m in self.markets.iter_mut() {
            m.people = 0;
            m.tents = 0;
            m.tent_people = 0;
            m.buyers = 0;
            m.grain = m.store;
            m.free_area = 0;
            m.work_month = m.work_acc;
            m.work_acc = 0;
        }
        for (&id, i) in self.info.iter() {
            let mk = self.cell_market[i.home as usize] as usize;
            let s = self.hh[&id];
            let m = &mut self.markets[mk];
            m.people += i.size as u32;
            m.tents += u32::from(s.kind == TENT);
            if s.kind == TENT {
                m.tent_people += i.size as u32;
            }
            if s.farm == NONE && !s.own_food {
                m.buyers += i.size as u32;
            }
            m.grain += s.pantry;
            if s.farm != NONE {
                m.grain += self.farms[s.farm as usize].store;
            }
        }
        for (c, &a) in self.free_m2.iter().enumerate() {
            let (a, mk) = (a + self.free_poor[c], self.cell_market[c]);
            if a > 0 && mk != NONE {
                self.markets[mk as usize].free_area += a;
            }
        }
    }


    fn new_farm(&mut self, p: &People, id: u32, i: &HhInfo, fine: u32) -> u32 {
        let kind = match i.job {
            PAECHTER => TENANT,
            UNFREIE => ESTATE,
            _ => FAMILY,
        };
        let cell = i.home;
        let (_, z) = self.xz(p, cell);
        // Harvest from mid June at Rome's latitude, 2 days later per 100 km
        // north, plus up to a week by farm; sowing from late October.
        // PLACEHOLDER (Columella's calendar is not encoded yet).
        let jit = (rnd(self.seed, id, 0x4a77, 0) % 15) as i64 - 7;
        let harvest_doy = (165 + ((-99_842.0 - z) / 100_000.0 * 2.0) as i64 + jit).clamp(100, 230);
        let sow_doy = (295 - jit).clamp(260, 330);
        let f = Farm {
            hh: id,
            kind,
            landlord: NONE,
            cell,
            fine,
            market: self.cell_market[cell as usize],
            area: 0,
            poor: 0,
            sown: 0,
            net_kg_ha: self.net_kg_ha[cell as usize],
            store: 0,
            money: 0,
            harvest_doy,
            sow_doy,
            peak: None,
            to_sell: 0,
            rent_due: 0,
            retry: false,
            off_need: 0,
            off_done: 0,
            plots: Vec::new(),
            manciana: false,
            idle: 0,
        };
        let k = self.farms.len() as u32;
        self.by_doy[harvest_doy as usize].push(k);
        self.by_doy[sow_doy as usize].push(k);
        self.farms.push(f);
        k
    }

    /// INHERIT_EQUAL (S83): the family farm of a household whose
    /// married sons left at the father's death is shared in equal parts
    /// between the old household (if anyone is left in it) and the sons'
    /// households, fields, sown area and store alike. The fields stay on
    /// their tiles. If the old household is empty, the first son takes the
    /// farm itself. Tenancies and estates stay with the old household.
    fn inherit_equal(&mut self, log: &[(u32, u32)]) {
        let mut k = 0;
        while k < log.len() {
            let old = log[k].0;
            let n_log = log[k..].iter().take_while(|e| e.0 == old).count();
            let sons: Vec<u32> = log[k..k + n_log]
                .iter()
                .map(|e| e.1)
                .filter(|id| self.info.contains_key(id) && self.hh.get(id).is_none_or(|h| h.farm == NONE))
                .collect();
            k += n_log;
            let Some(s) = self.hh.get(&old).copied() else { continue };
            if s.farm == NONE || self.farms[s.farm as usize].kind != FAMILY || sons.is_empty() {
                continue;
            }
            let f = s.farm;
            let kept = self.info.contains_key(&old);
            let n = sons.len() as i64 + kept as i64;
            let (area, sown, store) = (self.farms[f as usize].area, self.farms[f as usize].sown, self.farms[f as usize].store);
            for (j, &id) in sons.iter().enumerate() {
                let i = self.info[&id];
                let fine = self.settle.home_fine(i.home, id, i.stand);
                let to = if j == 0 && !kept {
                    // The farm itself goes to the first son.
                    self.hh.get_mut(&old).unwrap().farm = NONE;
                    let fm = &mut self.farms[f as usize];
                    fm.hh = id;
                    fm.fine = fine;
                    f
                } else {
                    let t = self.new_farm_for_heir(id, &i, fine, f);
                    self.move_land(f as usize, t as usize, area / n);
                    let sh = (sown / n, store / n);
                    self.farms[f as usize].sown -= sh.0;
                    self.farms[f as usize].store -= sh.1;
                    self.farms[t as usize].sown = sh.0;
                    self.farms[t as usize].store = sh.1;
                    t
                };
                if !self.hh.contains_key(&id) {
                    self.hh.insert(id, HhState { kind: FARM, pantry: 0, money: 0, farm: NONE, fine, fed: 1000, busy: false, trading: false, own_food: false });
                }
                let h = self.hh.get_mut(&id).unwrap();
                h.kind = FARM;
                h.farm = to;
                h.fine = fine;
                self.stats.heirs_given += 1;
            }
        }
    }

    /// An heir's farm without fields, with the calendar of the father's
    /// farm `like` (the share is sown and harvested with it).
    fn new_farm_for_heir(&mut self, id: u32, i: &HhInfo, fine: u32, like: u32) -> u32 {
        let fm = &self.farms[like as usize];
        let f = Farm {
            hh: id,
            kind: FAMILY,
            landlord: NONE,
            cell: i.home,
            fine,
            market: fm.market,
            area: 0,
            poor: 0,
            sown: 0,
            net_kg_ha: fm.net_kg_ha,
            store: 0,
            money: 0,
            harvest_doy: fm.harvest_doy,
            sow_doy: fm.sow_doy,
            peak: None,
            to_sell: 0,
            rent_due: 0,
            retry: false,
            off_need: 0,
            off_done: 0,
            plots: Vec::new(),
            manciana: false,
            idle: 0,
        };
        let k = self.farms.len() as u32;
        self.by_doy[f.harvest_doy as usize].push(k);
        self.by_doy[f.sow_doy as usize].push(k);
        self.farms.push(f);
        k
    }

    /// Moves `n` m² of fields from farm `from` to farm `to` on the same
    /// tiles: cleared land first, the plots taken last first (as give_land).
    fn move_land(&mut self, from: usize, to: usize, n: i64) {
        let mut plots = std::mem::take(&mut self.farms[from].plots);
        let mut left = n;
        for poor in [true, false] {
            for pl in plots.iter_mut().rev() {
                let have = if poor { &mut pl.poor } else { &mut pl.good };
                let k = left.min(*have as i64);
                if k == 0 {
                    continue;
                }
                *have -= k as u32;
                left -= k;
                let tp = &mut self.farms[to].plots;
                let j = match tp.iter().position(|p| p.tile == pl.tile) {
                    Some(j) => j,
                    None => {
                        tp.push(Plot { tile: pl.tile, good: 0, poor: 0 });
                        tp.len() - 1
                    }
                };
                if poor {
                    tp[j].poor += k as u32;
                    self.farms[to].poor += k;
                    self.farms[from].poor -= k;
                } else {
                    tp[j].good += k as u32;
                }
                self.farms[to].area += k;
                self.farms[from].area -= k;
            }
        }
        plots.retain(|p| p.good + p.poor > 0);
        self.farms[from].plots = plots;
    }

    fn xz(&self, p: &People, cell: u32) -> (f64, f64) {
        let (r, c) = (cell as i32 / p.grid.cols + p.grid.row0, cell as i32 % p.grid.cols + p.grid.col0);
        (c as f64 * 25_000.0 + 12_500.0, r as f64 * 25_000.0 + 12_500.0)
    }

    /// Start: the cropland of each cell is shared among its farms by what
    /// their families can till (S73), all sown. Estates get a landlord: a
    /// senator or eques by hash (PLACEHOLDER).
    fn share_land(&mut self, p: &People) {
        let elites: Vec<u32> = sorted_keys(&self.hh).into_iter().filter(|id| self.hh[id].kind == ELITE).collect();
        let mut by_cell: FxHashMap<u32, Vec<u32>> = FxHashMap::default();
        for (k, f) in self.farms.iter().enumerate() {
            by_cell.entry(f.cell).or_default().push(k as u32);
        }
        let mut cells: Vec<u32> = by_cell.keys().copied().collect();
        cells.sort_unstable();
        for c in cells {
            let fs = &by_cell[&c];
            let want: Vec<i64> = fs.iter().map(|&f| self.want_m2(self.farms[f as usize].hh)).collect();
            let total: i64 = want.iter().sum();
            // Good land first, then land cleared before the start.
            let (good, poor) = (self.free_m2[c as usize], self.free_poor[c as usize]);
            let part = |land: i64, w: i64, total: i64| if total <= land { w } else { (w as i128 * land as i128 / total.max(1) as i128) as i64 };
            let rest_total = (total - good).max(0);
            for (&f, &w) in fs.iter().zip(&want) {
                let g = part(good, w, total);
                let pr = part(poor, w - g, rest_total).min(w - g);
                // From the cell's tiles nearest the farmstead.
                self.take_land(f as usize, g, false, true);
                self.take_land(f as usize, pr, true, true);
                let fm = &mut self.farms[f as usize];
                fm.sown = fm.area * self.crop_pct / 100;
                if fm.kind != FAMILY && !elites.is_empty() {
                    fm.landlord = elites[(rnd(self.seed, fm.hh, 0x1a4d, 0) % elites.len() as u64) as usize];
                }
            }
        }
        let _ = p;
    }

    /// Takes up to `want` m² of free good land (or clearable, `poor`) for
    /// farm `f` from the fine tiles nearest its farmstead (S73): within
    /// FIELD_RADIUS, or anywhere in its own 25 km cell (`own`, the start).
    fn take_land(&mut self, f: usize, want: i64, poor: bool, own: bool) -> i64 {
        let (fine, cell) = (self.farms[f].fine as i32, self.farms[f].cell);
        let (fr, fc) = (fine / self.cols_f, fine % self.cols_f);
        let cols = self.cols_f / FINE;
        let mut got = 0i64;
        for k in 0..self.offsets.len() {
            let (dr, dc, d2) = self.offsets[k];
            if got >= want || (!own && d2 > FIELD_RADIUS * FIELD_RADIUS) {
                break;
            }
            let (r, c) = (fr + dr, fc + dc);
            if r < 0 || c < 0 || r >= self.rows_f || c >= self.cols_f {
                continue;
            }
            let cl = ((r / FINE) * cols + c / FINE) as u32;
            let base = self.tile_base[cl as usize];
            let left = if poor { self.free_poor[cl as usize] } else { self.free_m2[cl as usize] };
            if base == NONE || left == 0 || (own && cl != cell) {
                continue;
            }
            let t = base + ((r % FINE) * FINE + c % FINE) as u32;
            let free = &mut self.tiles[t as usize][poor as usize];
            let n = (want - got).min(*free as i64);
            if n <= 0 {
                continue;
            }
            *free -= n as u16;
            got += n;
            if poor {
                self.free_poor[cl as usize] -= n;
            } else {
                self.free_m2[cl as usize] -= n;
            }
            let plots = &mut self.farms[f].plots;
            let pl = match plots.iter().position(|p| p.tile == t) {
                Some(j) => &mut plots[j],
                None => {
                    plots.push(Plot { tile: t, good: 0, poor: 0 });
                    plots.last_mut().unwrap()
                }
            };
            if poor {
                pl.poor += n as u32;
            } else {
                pl.good += n as u32;
            }
        }
        let fm = &mut self.farms[f];
        fm.area += got;
        if poor {
            fm.poor += got;
        }
        got
    }

    /// Gives `n` m² of farm `f`'s fields back to their tiles: cleared land
    /// first, the plots taken last first.
    fn give_land(&mut self, f: usize, n: i64) {
        let mut plots = std::mem::take(&mut self.farms[f].plots);
        let mut left = n;
        for poor in [true, false] {
            for pl in plots.iter_mut().rev() {
                let have = if poor { &mut pl.poor } else { &mut pl.good };
                let k = left.min(*have as i64);
                if k == 0 {
                    continue;
                }
                *have -= k as u32;
                left -= k;
                self.tiles[pl.tile as usize][poor as usize] += k as u16;
                let cl = self.block_cell[pl.tile as usize / 256] as usize;
                if poor {
                    self.free_poor[cl] += k;
                    self.farms[f].poor -= k;
                } else {
                    self.free_m2[cl] += k;
                }
            }
        }
        plots.retain(|p| p.good + p.poor > 0);
        let fm = &mut self.farms[f];
        fm.plots = plots;
        fm.area -= n - left;
    }

    /// Field area a household's adults can work over the year (290
    /// working days / 70 days per ha).
    fn year_m2(&self, id: u32) -> i64 {
        self.info.get(&id).map_or(0, |i| i.adults as i64) * WORK_DAYS_YEAR * 10_000 / DAYS_PER_HA * self.work_x1000(id) / 1000
    }

    /// Days a week a farm outside its peak can sell as day labour: its
    /// adults' working days (290 a year) less the off-peak work of its own
    /// fields, so a farm with little land works mostly for others (S84).
    fn spare_week(&self, i: &HhInfo, farm: u32) -> i64 {
        let own = self.cropped(self.farms[farm as usize].area) * DAYS_PER_HA * OFF_SHARE_PCT / 100 / 10_000 * 7 / OFF_DAYS;
        (i.adults as i64 * 7 * WORK_DAYS_YEAR / YEAR - own).max(0)
    }

    /// Share of normal physical work a household still does, per mille:
    /// hungry people lower their activity first (S84 b, body::work_factor
    /// of the share eaten last month).
    fn work_x1000(&self, id: u32) -> i64 {
        self.hh.get(&id).map_or(1000, |s| work_of_fed(s.fed))
    }

    /// Field area a farm wants (S73). A family farm: what its adults
    /// manage over the year and its hands bring in during the harvest
    /// window, whichever is less; an estate: what its adults manage over
    /// the year, the peaks done by day labourers. Either way at least the
    /// fields that feed the household (PLACEHOLDER: need + 25 % for tax and
    /// reserve, at the cell's yield); work the family cannot do is hired
    /// (S72).
    fn want_m2(&self, id: u32) -> i64 {
        let Some(i) = self.info.get(&id) else { return 0 };
        let year = self.year_m2(id);
        let peak = i.hands as i64 * PEAK_DAYS * 100 * 10_000 / (DAYS_PER_HA * HARVEST_SHARE_PCT);
        let s = &self.hh[&id];
        let (kind, net) = if s.farm != NONE {
            let f = &self.farms[s.farm as usize];
            (f.kind, f.net_kg_ha.max(1))
        } else {
            (FAMILY, NET_POOR)
        };
        let feed = i.need_w as i64 * KG_PER_ADULT_YEAR / 10 * 125 / 100 * 10_000 / net;
        let own = if kind == ESTATE { year } else { year.min(peak) };
        // That much under grain; the fallow half comes on top (S76).
        own.max(feed) * 100 / self.crop_pct
    }

    /// The part of a farm's fields under grain this year (S76).
    fn cropped(&self, area: i64) -> i64 {
        area * self.crop_pct / 100
    }

    /// One day, after `People::day`.
    pub fn day(&mut self, p: &mut People) {
        let day = p.world.resource::<Clock>().day;
        let slice = day.rem_euclid(MONTH);
        let t = std::time::Instant::now;
        let us = |t0: std::time::Instant| t0.elapsed().as_secs_f64() * 1e6;
        let t0 = t();
        self.walks_done();
        self.timing.paths += us(t0);
        let t0 = t();
        self.roads_done();
        self.timing.traders += us(t0);
        let t0 = t();
        self.events(p, day);
        self.timing.events += us(t0);
        let t0 = t();
        self.peaks(day);
        self.timing.peaks += us(t0);
        let t0 = t();
        self.labour(day);
        self.timing.labour += us(t0);
        let t0 = t();
        self.news(day);
        self.prices();
        // Verderb in the market stores (S72), each market once a month.
        for m in self.markets.iter_mut().skip(slice as usize).step_by(MONTH as usize) {
            let lost = m.store.max(0) * SPOIL_PCT_YEAR / 1200;
            m.store -= lost;
            self.stats.spoiled_kg += lost;
        }
        self.timing.markets += us(t0);
        let t0 = t();
        self.eat(p, day, slice as usize);
        self.timing.eat += us(t0);
        let t0 = t();
        self.traders(day);
        self.roads(day);
        self.timing.traders += us(t0);
        let t0 = t();
        self.paths(day);
        self.timing.paths += us(t0);
        let t0 = t();
        match slice {
            11 => self.start_census(p, day),
            14 => self.finish_census(p),
            15 => self.assign_free(p, false),
            16 => self.regroup(),
            17 => {
                self.sums();
                self.export(p);
            }
            _ => {}
        }
        self.track(p, day, slice == 17);
        self.timing.census += us(t0);
    }

    /// The history (read only for the simulation): the day's flows added
    /// to the month's, and a row after the monthly count.
    fn track(&mut self, p: &People, day: i64, row: bool) {
        let (ps, gs) = (&p.stats, &self.stats);
        let now = [
            ps.births as i64,
            ps.deaths.iter().sum::<u64>() as i64,
            ps.deaths[2] as i64,
            ps.left_people as i64,
            ps.moved_people as i64,
            gs.harvest_kg,
            gs.sold_kg,
            gs.traded_kg,
            gs.alms_kg,
            gs.stolen_kg,
            gs.eaten_kg,
            gs.need_kg,
            gs.hired_days,
        ];
        let h = &mut self.history;
        for k in 0..now.len() {
            h.month[k] += if now[k] < h.last[k] { now[k] } else { now[k] - h.last[k] };
        }
        h.last = now;
        if !row {
            return;
        }
        let (farms, _, _, tent_people, _, farm_t, market_t) = self.summary();
        let r = HistoryRow {
            day,
            people: p.count,
            flows: std::mem::take(&mut self.history.month),
            price: self.price_spread(),
            money_held: self.money_held(),
            minted: self.money.minted,
            cash: self.treasury.cash,
            tax_grain_kg: self.treasury.grain_kg,
            tent_people,
            farms,
            farm_store_kg: (farm_t * 1e3) as i64,
            market_store_kg: (market_t * 1e3) as i64,
        };
        self.history.rows.push(r);
    }

    /// One row per month since the start (`track`).
    pub fn history(&self) -> &[HistoryRow] {
        &self.history.rows
    }

    fn push(&mut self, day: i64, ev: GEv) {
        self.wheel[(day as usize) % 1024].push(ev);
    }

    fn new_trip(&mut self, mut t: Trip) -> u32 {
        t.serial = self.trip_serial;
        self.trip_serial += 1;
        match self.free_trips.pop() {
            Some(k) => {
                self.trips[k as usize] = t;
                k
            }
            None => {
                self.trips.push(t);
                self.trips.len() as u32 - 1
            }
        }
    }

    /// Distance from a fine cell to the market along its path field, km,
    /// and the field is built if needed.
    fn route_km(&mut self, p: &People, m: u32, from: u32) -> i64 {
        self.ensure_field(p, m);
        let f = self.markets[m as usize].field.as_ref().unwrap();
        let (r, c) = ((from as i32 / self.cols_f) - f.r0, (from as i32 % self.cols_f) - f.c0);
        let fine_km = 1.5625;
        if r < 0 || c < 0 || r >= f.n || c >= f.n || f.dist[(r * f.n + c) as usize] == u32::MAX {
            // Off the field (another region or cut off): straight line × 1.5.
            let to = self.markets[m as usize].fine as i32;
            let (dr, dc) = ((from as i32 / self.cols_f - to / self.cols_f) as f64, (from as i32 % self.cols_f - to % self.cols_f) as f64);
            return ((dr * dr + dc * dc).sqrt() * fine_km * 1.5) as i64;
        }
        (f.dist[(r * f.n + c) as usize] as f64 / FINE_STEP as f64 * fine_km) as i64
    }

    fn travel_days(km: i64, speed: i64) -> i64 {
        if km == 0 {
            0
        } else {
            ((km + speed - 1) / speed).max(1)
        }
    }

    /// Start a carrier trip of a household (sell from its farm, or buy).
    fn start_carry(&mut self, p: &People, day: i64, id: u32, kind: u8) {
        let Some(info) = self.info.get(&id).copied() else { return };
        let s = self.hh[&id];
        if s.busy || info.carrier == NONE {
            return;
        }
        let m = self.cell_market[info.home as usize];
        let km = self.route_km(p, m, s.fine);
        let (load, speed) = if s.farm != NONE {
            if self.farms[s.farm as usize].kind == ESTATE {
                OX_CART
            } else {
                DONKEY
            }
        } else {
            // PLACEHOLDER: without a donkey every adult carries.
            (ON_FOOT.0 * info.adults.max(1) as i64, ON_FOOT.1)
        };
        let (kg, farm) = if kind == SELL {
            let f = &mut self.farms[s.farm as usize];
            let kg = f.to_sell.min(load).min(f.store);
            if kg <= 0 {
                return;
            }
            f.to_sell -= kg;
            f.store -= kg;
            (kg, s.farm)
        } else {
            if self.markets[m as usize].store <= 0 {
                return;
            }
            (load, s.farm)
        };
        let d = Self::travel_days(km, speed);
        let t = self.new_trip(Trip { kind, pid: info.carrier, hh: id, farm, market: m, dest: m, kg, back_days: d, left: day, from: s.fine, serial: 0 });
        self.hh.get_mut(&id).unwrap().busy = true;
        if kind == SELL {
            self.stats.sell_trips += 1;
        } else {
            self.stats.buy_trips += 1;
        }
        *self.markets[m as usize].walked.entry(s.fine).or_default() += 1;
        if d == 0 {
            self.arrive(p, day, t);
        } else {
            self.push(day + d, GEv { kind: EV_ARRIVE, id: t });
        }
    }

    fn events(&mut self, p: &mut People, day: i64) {
        let mut evs = std::mem::take(&mut self.wheel[(day as usize) % 1024]);
        evs.sort_unstable();
        for ev in evs {
            match ev.kind {
                EV_ARRIVE => self.arrive(p, day, ev.id),
                EV_HOME => self.home(p, day, ev.id),
                EV_PEAK_END => self.peak_end(p, day, ev.id),
                _ => {}
            }
        }
    }

    fn sell_price(m: &Market) -> i64 {
        m.price * (100 + SPREAD_PCT) / 100
    }
    fn buy_price(m: &Market) -> i64 {
        m.price * (100 - SPREAD_PCT) / 100
    }

    /// A trip reaches its market: one sale or one purchase (GRAIN.md).
    fn arrive(&mut self, p: &People, day: i64, k: u32) {
        let mut t = self.trips[k as usize];
        let alive = p.is_alive(t.pid);
        let mi = t.dest as usize;
        match t.kind {
            SELL => {
                // The market's dealers buy as far as their cash goes; the
                // rest goes home again (PLACEHOLDER: a market is a body of
                // dealers with cash, not the state).
                let m = &mut self.markets[mi];
                let price = Self::buy_price(m);
                let kg = if alive { t.kg.min(m.money / price.max(1)).max(0) } else { 0 };
                let pay = kg * price;
                m.store += kg;
                m.money -= pay;
                self.stats.sold_kg += kg;
                let owner = &mut self.farms[t.farm as usize];
                let rent = kg.min(owner.rent_due);
                owner.rent_due -= rent;
                let to_lord = if owner.kind == ESTATE { pay } else { rent * price };
                owner.money += pay - to_lord;
                let (lord, manciana) = (owner.landlord, owner.manciana);
                if to_lord > 0 {
                    match self.hh.get_mut(&lord) {
                        Some(h) => h.money += to_lord,
                        None if manciana => {
                            self.treasury.cash += to_lord;
                            self.treasury.rent += to_lord;
                        }
                        None => self.money.no_payee += to_lord,
                    }
                }
                t.kg -= kg;
            }
            BUY => {
                let want = {
                    let need = self.need_day(t.hh);
                    let have = self.hh.get(&t.hh).map_or(0, |s| if s.farm != NONE { self.farms[s.farm as usize].store } else { s.pantry });
                    (need * BUY_UP_TO - have).max(0).min(t.kg)
                };
                let money = self.money_of(t.hh);
                let m = &mut self.markets[mi];
                let price = Self::sell_price(m);
                let kg = want.min(m.store).min(money / price.max(1));
                if alive && kg > 0 {
                    m.store -= kg;
                    m.money += kg * price;
                    m.sold_today += kg;
                    self.stats.bought_kg += kg;
                    self.pay(t.hh, kg * price);
                    t.kg = kg;
                } else {
                    t.kg = 0;
                }
            }
            EXPORT => {
                // Sell the load here, tell this market the prices known at
                // home, then go home empty.
                let m = &mut self.markets[mi];
                let pay = t.kg * Self::buy_price(m);
                m.store += t.kg;
                m.money -= pay;
                self.stats.traded_kg += t.kg;
                match self.hh.get_mut(&t.hh) {
                    Some(h) => h.money += pay,
                    None => self.money.no_payee += pay,
                }
                t.kg = 0;
                self.share_news(t.market, t.dest, day);
            }
            IMPORT => {
                let money = self.money_of(t.hh);
                let m = &mut self.markets[mi];
                let price = Self::sell_price(m);
                let kg = WAGON.0.min(m.store / 4).min(money / price.max(1));
                if kg > 0 {
                    m.store -= kg;
                    m.money += kg * price;
                    m.sold_today += kg;
                    self.pay(t.hh, kg * price);
                }
                t.kg = kg.max(0);
                self.share_news(t.market, t.dest, day);
            }
            _ => {}
        }
        self.trips[k as usize] = t;
        if t.back_days == 0 {
            self.home(p, day, k);
        } else {
            self.push(day + t.back_days, GEv { kind: EV_HOME, id: k });
        }
    }

    /// Prices known at two markets are merged when a trader comes from one
    /// to the other: the newer entry wins (GRAIN.md: stale knowledge).
    fn share_news(&mut self, a: u32, b: u32, day: i64) {
        let pa = (a, self.markets[a as usize].price, day);
        let pb = (b, self.markets[b as usize].price, day);
        let ba = self.markets[a as usize].board.clone();
        let bb = self.markets[b as usize].board.clone();
        let merge = |board: &mut Vec<(u32, i64, i64)>, other: &[(u32, i64, i64)], fresh: (u32, i64, i64)| {
            for e in board.iter_mut() {
                if e.0 == fresh.0 {
                    *e = fresh;
                } else if let Some(o) = other.iter().find(|o| o.0 == e.0) {
                    if o.2 > e.2 {
                        *e = *o;
                    }
                }
            }
        };
        merge(&mut self.markets[a as usize].board, &bb, pb);
        merge(&mut self.markets[b as usize].board, &ba, pa);
    }

    /// The state wage (S76), from the treasury's cash, the rest minted (S95).
    fn state_pays(&mut self, amount: i64) {
        let cash = amount.min(self.treasury.cash.max(0));
        self.treasury.cash -= cash;
        self.money.minted += amount - cash;
        self.treasury.wages += amount;
    }

    /// Money held by households (also the money a farm household had
    /// before its farm), farms and dealers, milli-denarii.
    pub fn money_held(&self) -> i64 {
        self.hh.values().map(|s| s.money).sum::<i64>() + self.farms.iter().map(|f| f.money).sum::<i64>() + self.markets.iter().map(|m| m.money).sum::<i64>()
    }

    /// Money that appeared or vanished without a booking (S94: 0).
    pub fn money_unbooked(&self) -> i64 {
        let m = self.money;
        self.money_held() + self.treasury.cash - (m.start + m.minted + m.endowed - m.freight - m.dissolved - m.no_payee)
    }

    fn money_of(&self, id: u32) -> i64 {
        match self.hh.get(&id) {
            Some(s) if s.farm != NONE => self.farms[s.farm as usize].money,
            Some(s) => s.money,
            None => 0,
        }
    }

    fn pay(&mut self, id: u32, amount: i64) {
        if let Some(s) = self.hh.get_mut(&id) {
            if s.farm != NONE {
                self.farms[s.farm as usize].money -= amount;
            } else {
                s.money -= amount;
            }
        }
    }

    /// Back home: bought grain goes into the store; the next load leaves
    /// the next day if there is more to sell.
    fn home(&mut self, p: &People, day: i64, k: u32) {
        let t = self.trips[k as usize];
        self.free_trips.push(k);
        self.trips[k as usize].left = -1;
        let Some(s) = self.hh.get_mut(&t.hh) else { return };
        if matches!(t.kind, EXPORT | IMPORT) {
            s.trading = false;
        } else {
            s.busy = false;
        }
        match t.kind {
            SELL if t.kg > 0 => {
                // Unsold: back into the store; tried again next month.
                let f = &mut self.farms[t.farm as usize];
                f.store += t.kg;
                f.to_sell = 0;
                f.retry = true;
            }
            BUY if t.kg > 0 => {
                if s.farm != NONE && self.farms[s.farm as usize].hh == t.hh {
                    self.farms[s.farm as usize].store += t.kg;
                } else {
                    s.pantry += t.kg;
                }
            }
            IMPORT if t.kg > 0 => {
                // Sell the load at home.
                let m = &mut self.markets[t.market as usize];
                let pay = t.kg * Self::buy_price(m);
                m.store += t.kg;
                m.money -= pay;
                s.money += pay;
                self.stats.traded_kg += t.kg;
            }
            _ => {}
        }
        if t.kind == SELL && s.farm != NONE && self.farms[s.farm as usize].to_sell > 0 {
            let id = t.hh;
            self.start_carry(p, day, id, SELL);
        }
        // A household that could not carry home what it buys for (it buys
        // when below BUY_BELOW days of food) goes again, as a farm with
        // more to sell does.
        if t.kind == BUY && t.kg > 0 {
            let id = t.hh;
            let h = self.hh[&id];
            let have = if h.farm != NONE { self.farms[h.farm as usize].store } else { h.pantry };
            if have < self.need_day(id) * BUY_BELOW {
                self.start_carry(p, day, id, BUY);
            }
        }
    }

    /// Sowing and harvest start on the farm's day: the work needed in the
    /// window is posted; what the family cannot do is asked for at the
    /// weekly labour exchange of the region (S72).
    fn peaks(&mut self, day: i64) {
        let list = std::mem::take(&mut self.by_doy[doy(day) as usize]);
        for &f in &list {
            let fm = &self.farms[f as usize];
            if fm.hh == NONE || fm.area == 0 {
                continue;
            }
            let harvest = doy(day) == fm.harvest_doy;
            // Fields grow to what the family can till at sowing (S73).
            if !harvest {
                let (want, area, hh) = (self.want_m2(fm.hh), fm.area, fm.hh);
                let f = f as usize;
                if want > area {
                    // Free good land on the nearest tiles first, then
                    // clearing (S73), as much as the adults clear in a year.
                    self.take_land(f, want - area, false, false);
                    let adults = self.info.get(&hh).map_or(0, |i| i.adults as i64);
                    let clear = (want - self.farms[f].area).min(adults * CLEAR_M2_ADULT_YEAR * self.work_x1000(hh) / 1000).max(0);
                    self.take_land(f, clear, true, false);
                } else if area > want * 3 / 2 {
                    self.give_land(f, area - want * 3 / 2);
                }
            }
            let fm = &self.farms[f as usize];
            let ha_x = if harvest { fm.sown } else { self.cropped(fm.area) };
            let share = if harvest { HARVEST_SHARE_PCT } else { SOW_SHARE_PCT };
            let demand = ha_x * DAYS_PER_HA * share / 100 / 10_000;
            let family = self.info.get(&fm.hh).map_or(0, |i| i.hands as i64) * PEAK_DAYS * self.work_x1000(fm.hh) / 1000;
            let fm = &mut self.farms[f as usize];
            fm.peak = Some(Peak { harvest, demand, done: family.min(demand) });
            if family < demand {
                self.markets[fm.market as usize].open.push(f);
            }
            self.push(day + PEAK_DAYS, GEv { kind: EV_PEAK_END, id: f });
        }
        self.by_doy[doy(day) as usize] = list;
    }

    /// Weekly labour exchange per region, staggered by market index: the
    /// landless and farms outside their peak offer days, farms in their
    /// peak take them in farm order and pay in grain (S72).
    fn labour(&mut self, day: i64) {
        let wd = day.rem_euclid(7) as usize;
        for mi in (wd..self.markets.len()).step_by(7) {
            // Supply: landless adults of the region and farms not in a peak.
            let region = self.markets[mi].region;
            let mut offers: Vec<(u32, i64)> = Vec::new();
            let mut farm_offers: Vec<(u32, i64)> = Vec::new();
            // Farms with a surplus beyond food to the next harvest, the
            // reserve and next year's seed, in household order: (id, days).
            let mut surplus: Vec<(u32, i64)> = Vec::new();
            let _ = region;
            let ids = std::mem::take(&mut self.market_hh[mi]);
            for &id in &ids {
                // Gone since the count (the lists follow a day later).
                let Some(&s) = self.hh.get(&id) else { continue };
                if s.kind != FARM && s.kind != TENT {
                    continue;
                }
                let Some(&i) = self.info.get(&id) else { continue };
                if s.kind == FARM {
                    let fm = &self.farms[s.farm as usize];
                    if fm.peak.is_none() {
                        let need_day = i.need_w as i64 * KG_PER_ADULT_YEAR / 10 / YEAR;
                        let keep = need_day * (doy_until(day, fm.harvest_doy) + RESERVE_DAYS) + self.cropped(fm.area) * SEED_KG_HA / 10_000;
                        let days = (fm.store - fm.to_sell - keep) / WAGE_KG_DAY;
                        if days > 0 {
                            surplus.push((id, days));
                        }
                    }
                }
                let days = match s.kind {
                    TENT => i.hands as i64 * 7 * SPARE_TENT_PCT / 100,
                    FARM if self.farms[s.farm as usize].peak.is_none() => self.spare_week(&i, s.farm),
                    _ => 0,
                } * work_of_fed(s.fed) / 1000;
                if days > 0 {
                    if s.kind == TENT {
                        offers.push((id, days));
                    } else {
                        farm_offers.push((id, days));
                    }
                }
            }
            self.market_hh[mi] = ids;
            self.markets[mi].work.clear();
            self.markets[mi].work_day = day;
            // PLACEHOLDER order: the landless are hired first, then farms
            // with spare hands, each in household order.
            offers.sort_unstable_by_key(|&(id, _)| id);
            farm_offers.sort_unstable_by_key(|&(id, _)| id);
            offers.append(&mut farm_offers);
            let open = std::mem::take(&mut self.markets[mi].open);
            let mut still = Vec::new();
            let mut o = 0;
            for f in open {
                let Some(mut pk) = self.farms[f as usize].peak else { continue };
                // Sowing is paid from the store, as far as it goes; the
                // harvest from the crop that comes.
                let cap = if pk.harvest { i64::MAX } else { self.farms[f as usize].store.max(0) / WAGE_KG_DAY };
                let mut paid = 0;
                while pk.done < pk.demand && o < offers.len() && paid < cap {
                    let take = (pk.demand - pk.done).min(offers[o].1).min(cap - paid);
                    paid += take;
                    offers[o].1 -= take;
                    pk.done += take;
                    let wage = take * WAGE_KG_DAY;
                    // Paid from the farm store (sowing) or the crop (at
                    // the end of the harvest, from the store now and the
                    // crop refills it).
                    let fm = &mut self.farms[f as usize];
                    fm.store -= wage;
                    self.stats.hired_days += take;
                    self.stats.wage_kg += wage;
                    self.markets[mi].work_acc += wage;
                    let w = offers[o].0;
                    self.markets[mi].work.push((w, f, take, if pk.harvest { WORK_HARVEST } else { WORK_SOW }));
                    let ws = self.hh.get_mut(&w).unwrap();
                    if ws.farm != NONE {
                        self.farms[ws.farm as usize].store += wage;
                    } else {
                        ws.pantry += wage;
                    }
                    if offers[o].1 == 0 {
                        o += 1;
                    }
                }
                self.farms[f as usize].peak = Some(pk);
                if pk.done < pk.demand {
                    still.push(f);
                }
            }
            self.markets[mi].open = still;
            // Outside the peaks: farms with more fields than their family
            // works over the year hire for the rest, as far as their store
            // pays the wage.
            let hirers = std::mem::take(&mut self.markets[mi].hirers);
            for &f in &hirers {
                let fm = &self.farms[f as usize];
                if fm.peak.is_some() || fm.hh == NONE {
                    continue;
                }
                let extra = (self.cropped(fm.area) - self.year_m2(fm.hh)).max(0);
                let need = extra * DAYS_PER_HA * OFF_SHARE_PCT / 100 / 10_000 * 7 / OFF_DAYS;
                let fm = &mut self.farms[f as usize];
                fm.off_need += need;
                let mut want = need.min(fm.store / WAGE_KG_DAY).max(0);
                while want > 0 && o < offers.len() {
                    let take = want.min(offers[o].1);
                    offers[o].1 -= take;
                    want -= take;
                    let wage = take * WAGE_KG_DAY;
                    let fm = &mut self.farms[f as usize];
                    fm.off_done += take;
                    fm.store -= wage;
                    self.stats.hired_days += take;
                    self.stats.wage_kg += wage;
                    self.markets[mi].work_acc += wage;
                    let w = offers[o].0;
                    self.markets[mi].work.push((w, f, take, WORK_OFF));
                    let ws = self.hh.get_mut(&w).unwrap();
                    if ws.farm != NONE {
                        self.farms[ws.farm as usize].store += wage;
                    } else {
                        ws.pantry += wage;
                    }
                    if offers[o].1 == 0 {
                        o += 1;
                    }
                }
            }
            self.markets[mi].hirers = hirers;
            // Farms with more in store than food to the next harvest, the
            // reserve and next year's seed pay day labour from the surplus,
            // in household order (S84; Erdkamp 2005: smallholders worked on
            // the estates). PLACEHOLDER: the work makes nothing yet (ditches,
            // buildings, gardens, clearing).
            for (id, mut want) in surplus {
                let farm = self.hh[&id].farm;
                while want > 0 && o < offers.len() {
                    if offers[o].0 == id {
                        o += 1;
                        continue;
                    }
                    let take = want.min(offers[o].1);
                    offers[o].1 -= take;
                    want -= take;
                    let wage = take * WAGE_KG_DAY;
                    self.farms[farm as usize].store -= wage;
                    self.stats.hired_days += take;
                    self.stats.wage_kg += wage;
                    self.markets[mi].work_acc += wage;
                    let w = offers[o].0;
                    self.markets[mi].work.push((w, farm, take, WORK_SURPLUS));
                    let ws = self.hh.get_mut(&w).unwrap();
                    if ws.farm != NONE {
                        self.farms[ws.farm as usize].store += wage;
                    } else {
                        ws.pantry += wage;
                    }
                    if offers[o].1 == 0 {
                        o += 1;
                    }
                }
            }
        }
    }

    /// End of sowing or harvest. Sowing: the area sown follows the work
    /// done. Harvest: the crop follows the work done, the rest stays on the
    /// field (S72); tax and rent come off; what is beyond the family's
    /// food until the next harvest plus the reserve is carried to market.
    fn peak_end(&mut self, p: &People, day: i64, f: u32) {
        let Some(pk) = self.farms[f as usize].peak.take() else { return };
        let cropped = self.cropped(self.farms[f as usize].area);
        let fm = &mut self.farms[f as usize];
        // S75: the hands that were missing, as wages a worker could have had.
        self.markets[fm.market as usize].work_acc += (pk.demand - pk.done).max(0) * WAGE_KG_DAY;
        let frac_x1000 = if pk.demand == 0 { 1000 } else { pk.done * 1000 / pk.demand };
        if !pk.harvest {
            let worked = cropped * frac_x1000 / 1000;
            self.stats.sow_short_m2 += cropped - worked;
            // Seed comes from the farm's store (S76); without it, less is sown.
            let sown = worked.min(fm.store.max(0) * 10_000 / SEED_KG_HA);
            self.stats.seed_short_m2 += worked - sown;
            let seed = sown * SEED_KG_HA / 10_000;
            fm.store -= seed;
            self.stats.seed_kg += seed;
            fm.sown = sown;
            if fm.manciana {
                fm.idle = if sown == 0 { fm.idle + 1 } else { 0 };
                if fm.idle >= MANCIANA_IDLE_YEARS {
                    self.manciana_lapse(f as usize);
                }
            }
            return;
        }
        let poor = if fm.area == 0 { 0 } else { fm.sown * fm.poor / fm.area };
        // Gross: the net yield plus the seed back (ratio × seed per ha).
        let full = ((fm.sown - poor) * fm.net_kg_ha + poor * NET_POOR + fm.sown * SEED_KG_HA) / 10_000;
        let seed_in = fm.sown * SEED_KG_HA / 10_000;
        // Work outside the peaks that was missing lowers the crop by its share.
        let off = if fm.off_need == 0 { 1000 } else { (fm.off_done * 1000 / fm.off_need).min(1000) };
        fm.off_need = 0;
        fm.off_done = 0;
        let crop = full * frac_x1000 / 1000 * (1000 - OFF_SHARE_PCT * (1000 - off) / 100) / 1000;
        self.stats.harvest_kg += crop;
        self.stats.harvest_lost_kg += full - crop;
        // Tax in kind leaves the economy for now (PLACEHOLDER: the state's
        // grain has no use until state, army and money are systems, S76).
        // Rent is carried to market with the farm's grain and its money
        // goes to the landlord (PLACEHOLDER: share-cropping paid on sale).
        // Tax and rent on the crop less the seed it took (PLACEHOLDER).
        let net = (crop - seed_in).max(0);
        // S92: on Manciana land the third (RENT_PCT) to the state is all.
        let tax = if fm.manciana { 0 } else { net * TAX_PCT / 100 };
        let rent = if fm.kind == TENANT { net * RENT_PCT / 100 } else { 0 };
        fm.store += crop - tax;
        fm.rent_due += rent;
        self.stats.tax_kg += tax;
        self.treasury.grain_kg += tax;
        self.stats.rent_kg += rent;
        let id = fm.hh;
        if id == NONE {
            return;
        }
        let need = self.need_day(id);
        // Food to the next harvest plus the reserve, and next year's seed.
        let keep = need * (YEAR + RESERVE_DAYS) + cropped * SEED_KG_HA / 10_000;
        let fm = &mut self.farms[f as usize];
        fm.to_sell = (fm.store - keep).max(0).max(fm.rent_due.min(fm.store));
        if fm.to_sell > 0 {
            self.start_carry(p, day, id, SELL);
        }
    }

    /// News: once a week (1/7 of the markets a day) a market hears the
    /// prices of its 32 known markets as they were when travellers left
    /// there, i.e. the travel time ago (PLACEHOLDER: travellers other than
    /// traders carry news; the price `days` ago is approximated by the
    /// price then recorded weekly).
    fn news(&mut self, day: i64) {
        let wd = day.rem_euclid(7) as usize;
        for mi in (wd..self.markets.len()).step_by(7) {
            for k in 0..self.markets[mi].neigh.len() {
                let (m, days) = (self.markets[mi].neigh[k].m, self.markets[mi].neigh[k].days);
                let seen = day - days;
                if self.markets[mi].board[k].2 < seen {
                    let old = &self.markets[m as usize];
                    // The price a week ago if the trip is longer than a week.
                    let price = if days >= 7 { old.last_week } else { old.price };
                    self.markets[mi].board[k] = (m, price, seen);
                }
            }
        }
        for m in (wd..self.markets.len()).step_by(7) {
            let mk = &mut self.markets[m];
            mk.last_week = mk.price;
        }
    }

    /// Daily price step per market towards its target (S22, EU5-like).
    fn prices(&mut self) {
        for m in self.markets.iter_mut() {
            m.demand += (m.sold_today * 1000 - m.demand) / MONTH;
            m.sold_today = 0;
            let per_day = (m.demand / 1000).max(1);
            let days = m.store / per_day;
            let target = (BASE_PRICE * TARGET_DAYS / days.max(1)).clamp(BASE_PRICE * PRICE_MIN_PCT / 100, BASE_PRICE * PRICE_MAX_PCT / 100);
            m.price += (target - m.price) / PRICE_STEP;
        }
    }

    /// Each household eats once a month (1/30 of them per day) from its
    /// farm store or pantry. Who is short buys at the market (a trip;
    /// city households in the market cell buy on the spot), the state wage
    /// is paid, the landless beg and steal (S69). How much was eaten sets
    /// `fed`, which drives health (S64, S65).
    fn eat(&mut self, p: &mut People, day: i64, slice: usize) {
        let ids = std::mem::take(&mut self.hh_slices[slice]);
        for &id in &ids {
            let Some(info) = self.info.get(&id).copied() else { continue };
            let Some(mut s) = self.hh.get(&id).copied() else { continue };
            // S91: oasis and desert households feed themselves.
            if s.own_food && self.desert[info.home as usize] {
                s.fed = 1000;
                self.hh.insert(id, s);
                self.stats.own_food_people += info.size as u64;
                if let Some(e) = p.econ.as_mut() {
                    if (id as usize) < e.fed.len() {
                        e.fed[id as usize] = 1000;
                    }
                }
                continue;
            }
            let need_day = info.need_w as i64 * KG_PER_ADULT_YEAR / 10 / YEAR;
            let need = need_day * MONTH;
            // Income: the state wage for workers outside farming (S76).
            if matches!(s.kind, WAGE | TRADER) {
                let wage = info.adults as i64 * STATE_WAGE * WORK_DAYS_YEAR / 12;
                s.money += wage;
                self.state_pays(wage);
            }
            let mk = self.cell_market[info.home as usize];
            // Verderb (S72): a twelfth of the year's loss.
            if s.farm != NONE {
                let f = &mut self.farms[s.farm as usize];
                let lost = f.store.max(0) * SPOIL_PCT_YEAR / 1200;
                f.store -= lost;
                self.stats.spoiled_kg += lost;
            } else {
                let lost = s.pantry.max(0) * SPOIL_PCT_YEAR / 1200;
                s.pantry -= lost;
                self.stats.spoiled_kg += lost;
            }
            let mut have = if s.farm != NONE { self.farms[s.farm as usize].store } else { s.pantry };
            // The landless beg at the market, then steal (S69).
            if s.kind == TENT && have < need {
                let m = &mut self.markets[mk as usize];
                let alms = (need * ALMS_PCT / 100).min(need - have).min(m.store);
                m.store -= alms;
                have += alms;
                self.stats.alms_kg += alms;
                if have < need && rnd(self.seed, id, 0x57ea, day) % 16 < STEAL_PER_16 {
                    if let Some(v) = self.victim(id, info.home, day) {
                        let take = STEAL_KG.min(self.farms[v as usize].store).max(0);
                        self.farms[v as usize].store -= take;
                        have += take;
                        self.stats.stolen_kg += take;
                        self.stats.thefts += 1;
                    }
                }
            }
            let eaten = have.clamp(0, need);
            have -= eaten;
            self.stats.eaten_kg += eaten;
            self.stats.need_kg += need;
            self.stats.eaten_by[s.kind as usize] += eaten;
            self.stats.need_by[s.kind as usize] += need;
            s.fed = if need == 0 { 1000 } else { (eaten * 1000 / need) as u16 };
            if s.farm != NONE {
                self.farms[s.farm as usize].store = have;
            } else {
                s.pantry = have;
            }
            self.hh.insert(id, s);
            if s.kind == TENT && s.fed < 1000 && !s.busy {
                self.tent_move(p, id, &info, mk);
            }
            if let Some(e) = p.econ.as_mut() {
                if (id as usize) < e.fed.len() {
                    e.fed[id as usize] = s.fed;
                }
            }
            // A farm whose load came back unsold tries again.
            if s.farm != NONE && self.farms[s.farm as usize].retry && !s.busy {
                let f = &mut self.farms[s.farm as usize];
                f.retry = false;
                let keep = need_day * (doy_until(day, f.harvest_doy) + RESERVE_DAYS);
                f.to_sell = (f.store - keep).max(0).max(f.rent_due.min(f.store));
                if f.to_sell > 0 {
                    self.start_carry(p, day, id, SELL);
                }
            }
            // Buy when the store runs low.
            let money = self.money_of(id);
            if have < need_day * BUY_BELOW && money > 0 && !s.busy {
                let m = &self.markets[mk as usize];
                if m.cell == info.home && s.farm == NONE {
                    // On the spot.
                    let price = Self::sell_price(m);
                    let kg = (need_day * BUY_UP_TO - have).min(m.store).min(money / price.max(1)).max(0);
                    if kg > 0 {
                        let m = &mut self.markets[mk as usize];
                        m.store -= kg;
                        m.money += kg * price;
                        m.sold_today += kg;
                        self.stats.bought_kg += kg;
                        self.pay(id, kg * price);
                        self.hh.get_mut(&id).unwrap().pantry += kg;
                    }
                } else {
                    self.start_carry(p, day, id, BUY);
                }
            }
        }
        self.hh_slices[slice] = ids;
    }

    /// S75: what a tent person can get in a month at market `m` with `add`
    /// more tent people there, kg.
    fn tent_chance(&self, m: usize, add: u32) -> i64 {
        let mk = &self.markets[m];
        let n = (mk.tent_people + add).max(1) as i64;
        let alms = (KG_PER_ADULT_YEAR / 12 * ALMS_PCT / 100).min(mk.store.max(0) / n);
        mk.work_month / n + alms
    }

    /// S75: a tent household moves to the market with the best chances
    /// within reach, if they are clearly better than at its own.
    fn tent_move(&mut self, p: &mut People, id: u32, info: &HhInfo, mk: u32) {
        if mk == NONE {
            return;
        }
        let n = info.size as u32;
        let own = self.tent_chance(mk as usize, 0);
        let mut best = (own * TENT_MOVE_PCT / 100, NONE);
        for nb in &self.markets[mk as usize].neigh {
            if nb.days > TENT_REACH_DAYS {
                continue;
            }
            let c = self.tent_chance(nb.m as usize, n);
            if c > best.0 {
                best = (c, nb.m);
            }
        }
        let to = best.1;
        if to == NONE {
            return;
        }
        let (cell, fine) = (self.markets[to as usize].cell, self.markets[to as usize].fine);
        p.relocate_household(id, &self.members[info.at as usize..(info.at + info.size as u32) as usize], cell);
        self.info.get_mut(&id).unwrap().home = cell;
        self.hh.get_mut(&id).unwrap().fine = fine;
        self.markets[mk as usize].tent_people = self.markets[mk as usize].tent_people.saturating_sub(n);
        self.markets[to as usize].tent_people += n;
        self.stats.tent_moves += 1;
    }

    /// A farm store in the cell (else the region) to steal from, by hash.
    fn victim(&self, id: u32, cell: u32, day: i64) -> Option<u32> {
        let mk = self.cell_market[cell as usize];
        let n = self.farms.len() as u64;
        if n == 0 {
            return None;
        }
        // A few draws over all farms, keep one of this market (cheap and
        // deterministic; PLACEHOLDER).
        for k in 0..8u32 {
            let f = (rnd(self.seed, id, 0x7a1 + k, day) % n) as u32;
            let fm = &self.farms[f as usize];
            if fm.market == mk && fm.store > 0 && fm.hh != id {
                return Some(f);
            }
        }
        None
    }

    /// Traders decide on their day of the week (S71, GRAIN.md): from the
    /// prices their home market knows (possibly old), the best trip after
    /// freight: export (buy here, sell there) or import (go there empty,
    /// buy, sell here). They go if the margin per kg is above the
    /// threshold.
    fn traders(&mut self, day: i64) {
        let wd = day.rem_euclid(7) as usize;
        let ids = std::mem::take(&mut self.trader_slices[wd]);
        for &id in &ids {
            let Some(info) = self.info.get(&id).copied() else { continue };
            let Some(s) = self.hh.get(&id).copied() else { continue };
            if s.trading || s.kind != TRADER || info.trader == NONE {
                continue;
            }
            let h = self.cell_market[info.home as usize] as usize;
            let home = &self.markets[h];
            let (hb, hs) = (Self::buy_price(home), Self::sell_price(home));
            let mut best: Option<(i64, u8, usize)> = None;
            for (k, nb) in home.neigh.iter().enumerate() {
                let (_, price, _) = home.board[k];
                let (ob, os) = (price * (100 - SPREAD_PCT) / 100, price * (100 + SPREAD_PCT) / 100);
                let export = ob - hs - nb.cost;
                // Import: loaded leg back, the empty leg at half the cost.
                let import = hb - os - nb.cost - nb.cost / 2;
                for (margin, kind) in [(export, EXPORT), (import, IMPORT)] {
                    if margin * 100 > hs * TRADE_MARGIN_PCT && best.is_none_or(|b| margin > b.0) {
                        best = Some((margin, kind, k));
                    }
                }
            }
            let Some((_, kind, k)) = best else { continue };
            let (dest, cost, days) = {
                let nb = &self.markets[h].neigh[k];
                (nb.m, nb.cost, nb.days)
            };
            let mut kg = 0;
            if kind == EXPORT {
                let m = &mut self.markets[h];
                let price = Self::sell_price(m);
                kg = WAGON.0.min(m.store / 4).min(s.money / (price + cost).max(1));
                if kg <= 0 {
                    continue;
                }
                m.store -= kg;
                m.money += kg * price;
                m.sold_today += kg;
                self.pay(id, kg * (price + cost));
                self.money.freight += kg * cost;
            } else {
                // Freight paid on the way back, at purchase.
                self.pay(id, WAGON.0 * cost);
                self.money.freight += WAGON.0 * cost;
            }
            for &c in &self.markets[h].neigh[k].route.clone() {
                *self.lanes.entry(c).or_default() += 1;
                self.road_trips[c as usize] += 1;
            }
            let t = self.new_trip(Trip { kind, pid: info.trader, hh: id, farm: NONE, market: h as u32, dest, kg, back_days: days, left: day, from: self.markets[h].fine, serial: 0 });
            self.hh.get_mut(&id).unwrap().trading = true;
            self.stats.trade_trips += 1;
            self.push(day + days, GEv { kind: EV_ARRIVE, id: t });
        }
        self.trader_slices[wd] = ids;
    }

    /// Footpaths (S70, Helbing 1997): once every WALK_DAYS per market
    /// (1/WALK_DAYS of the markets a day), every origin's trips since the
    /// last walk are walked along the market's path field and add wear to
    /// each fine cell; wear decays with half-life PATH_HALF. A level change
    /// marks the field for a rebuild, so later trips follow and deepen the
    /// path. The day's markets are independent, so they run on the task
    /// pool; the result does not depend on the number of threads.
    fn paths(&mut self, day: i64) {
        let q = day.rem_euclid(WALK_DAYS) as usize;
        let mut jobs: Vec<Walk> = Vec::new();
        for mi in (q..self.markets.len()).step_by(WALK_DAYS as usize) {
            let m = &mut self.markets[mi];
            if m.walked.is_empty() && !m.dirty {
                continue;
            }
            let mut origins: Vec<(u32, i64)> = m.walked.drain().collect();
            origins.sort_unstable();
            jobs.push(Walk { m: mi as u32, region: m.region, fine: m.fine, origins, field: m.field.take(), dirty: m.dirty, first_us: 0.0, rebuild_us: 0.0, rebuilt: false });
        }
        if jobs.is_empty() {
            return;
        }
        // The walks run on the path thread until the next day starts
        // (`walks_done`): nothing reads the fields or their wear before.
        let job = (self.net.clone(), self.decay.clone(), self.cols_f, jobs, day);
        self.walk_worker.get_or_insert_with(WalkWorker::new).send.send(job).expect("path worker");
        self.walking = true;
    }

    /// Takes over the walks started by `paths` (start of the next day, and
    /// before anything outside reads the fields).
    fn walks_done(&mut self) {
        if !self.walking {
            return;
        }
        self.walking = false;
        let jobs = self.walk_worker.as_ref().expect("path worker").recv.recv().expect("path worker");
        for w in jobs {
            let m = &mut self.markets[w.m as usize];
            m.field = w.field;
            m.dirty = w.dirty;
            self.stats.field_rebuilds += u64::from(w.rebuilt);
            self.timing.first_build += w.first_us;
            self.timing.rebuild += w.rebuild_us;
        }
    }

    fn ensure_field(&mut self, p: &People, m: u32) {
        let mk = &mut self.markets[m as usize];
        if mk.field.is_none() {
            let t0 = std::time::Instant::now();
            mk.field = Some(build_field(&self.net, self.cols_f, mk.region, mk.fine, None, p.world.resource::<Clock>().day));
            mk.dirty = false;
            self.timing.first_build += t0.elapsed().as_secs_f64() * 1e6;
        }
    }

    /// What people.rs reads: fed per household, and per region whether it
    /// has free land and how much grain (stores plus free land at its
    /// yield) it offers per head (S65, S66).
    fn export(&mut self, p: &mut People) {
        let n = p.next_pid() as usize;
        let mut fed = p.econ.take().map(|e| e.fed).unwrap_or_default();
        fed.resize(n.max(fed.len()), 1000);
        for (&id, s) in self.hh.iter() {
            if (id as usize) < fed.len() {
                fed[id as usize] = s.fed;
            }
        }
        let mut region = FxHashMap::default();
        for m in &self.markets {
            let food = m.grain + m.free_area * 400 / 10_000;
            // A cell with free land, else the market cell.
            region.insert(m.region, (food as f64, m.people, m.free_area > 0, m.cell));
        }
        for (c, &a) in self.free_m2.iter().enumerate() {
            let a = a + self.free_poor[c];
            if a > 10_000 {
                if let Some(e) = region.get_mut(&p.grid.region(c as u32)) {
                    if self.free_m2[e.3 as usize] + self.free_poor[e.3 as usize] < a {
                        e.3 = c as u32;
                    }
                }
            }
        }
        // S93: wage households check monthly against the market stores.
        let mut buyer = vec![false; fed.len()];
        for (&id, s) in self.hh.iter() {
            if (id as usize) < buyer.len() {
                buyer[id as usize] = s.kind == WAGE && s.farm == NONE && !s.own_food;
            }
        }
        let market = self.markets.iter().map(|m| (m.region, (m.store as f64, m.buyers, m.cell))).collect();
        p.econ = Some(Econ { fed, region, need_fed: NEED_FED, buyer, market, arriving: FxHashMap::default() });
    }

    // Reporting -----------------------------------------------------------

    /// (farms, family, tenant, estate, landless households, people in tents,
    /// field area in ha, farm stores t, market stores t).
    pub fn summary(&self) -> (usize, [usize; 3], usize, u32, f64, f64, f64) {
        let mut k = [0; 3];
        let (mut area, mut store) = (0i64, 0i64);
        let mut n = 0;
        for f in &self.farms {
            if f.hh != NONE {
                n += 1;
                k[f.kind as usize] += 1;
                area += f.area;
                store += f.store;
            }
        }
        let tents = self.hh.values().filter(|s| s.kind == TENT).count();
        let tent_people: u32 = self.hh.iter().filter(|(_, s)| s.kind == TENT).map(|(id, _)| self.info.get(id).map_or(0, |i| i.size as u32)).sum();
        let market: i64 = self.markets.iter().map(|m| m.store).sum();
        (n, k, tents, tent_people, area as f64 / 1e4, store as f64 / 1e3, market as f64 / 1e3)
    }

    /// Farms with a household: count, field ha at p10/p50/p90 and mean,
    /// and the share (%) whose fields at their yield, fallow included,
    /// cannot feed the household.
    pub fn land_report(&self) -> (usize, [f64; 4], f64) {
        let mut ha = Vec::new();
        let mut short = 0;
        for f in self.farms.iter().filter(|f| f.hh != NONE) {
            ha.push(f.area as f64 / 1e4);
            if let Some(i) = self.info.get(&f.hh) {
                let feed = i.need_w as i64 * KG_PER_ADULT_YEAR / 10 * 10_000 / f.net_kg_ha.max(1) * 100 / self.crop_pct;
                short += (f.area < feed) as usize;
            }
        }
        ha.sort_by(f64::total_cmp);
        let q = |x: f64| ha.get(((ha.len().max(1) - 1) as f64 * x) as usize).copied().unwrap_or(0.0);
        let mean = ha.iter().sum::<f64>() / ha.len().max(1) as f64;
        (ha.len(), [q(0.1), q(0.5), q(0.9), mean], 100.0 * short as f64 / ha.len().max(1) as f64)
    }

    /// Price of the market of the region of `cell`, denarii per kg.
    pub fn price_at(&self, cell: u32) -> f64 {
        self.markets[self.cell_market[cell as usize] as usize].price as f64 / 1000.0
    }

    /// Fine cells by path level (trail, path), as of the last walk.
    /// Trade tracks and roads on land, lanes at sea (cells, S71).
    pub fn road_cells(&self, p: &People) -> (usize, usize, usize) {
        let (mut a, mut b, mut sea) = (0, 0, 0);
        for (c, &l) in self.road_level.iter().enumerate() {
            match (p.grid.kind[c], l) {
                (_, 0) => {}
                (0, _) => sea += 1,
                (_, 1) => a += 1,
                _ => b += 1,
            }
        }
        (a, b, sea)
    }

    pub fn path_cells(&mut self) -> (usize, usize) {
        self.walks_done();
        let (mut a, mut b) = (0, 0);
        for f in self.markets.iter().filter_map(|m| m.field.as_ref()) {
            for &i in &f.worn {
                match f.level[i as usize] {
                    1 => a += 1,
                    2 => b += 1,
                    _ => {}
                }
            }
        }
        (a, b)
    }

    /// Prices of the markets with people: (min, median, max) den./kg,
    /// people-weighted.
    pub fn price_spread(&self) -> (f64, f64, f64) {
        let mut v: Vec<(i64, u32)> = self.markets.iter().filter(|m| m.people > 0).map(|m| (m.price, m.people)).collect();
        if v.is_empty() {
            return (0.0, 0.0, 0.0);
        }
        v.sort_unstable();
        let total: u32 = v.iter().map(|x| x.1).sum();
        let mut acc = 0;
        let mut med = v[0].0;
        for &(pr, n) in &v {
            acc += n;
            if acc * 2 >= total {
                med = pr;
                break;
            }
        }
        (v[0].0 as f64 / 1e3, med as f64 / 1e3, v[v.len() - 1].0 as f64 / 1e3)
    }

    /// Debug lines for the largest markets and the farms' land per head.
    pub fn debug(&self) -> String {
        let mut out = String::new();
        let mut ms: Vec<usize> = (0..self.markets.len()).collect();
        ms.sort_by_key(|&k| std::cmp::Reverse(self.markets[k].people));
        for &k in ms.iter().take(6) {
            let m = &self.markets[k];
            let mut kinds = [0; 5];
            for id in self.market_hh.get(k).into_iter().flatten() {
                kinds[self.hh[id].kind as usize] += 1;
            }
            let traders = format!("{kinds:?}");
            out += &format!("  market {k}: people {} tents {} store {} t demand {:.0} kg/d price {:.2} traders {} free_ha {:.0}\n", m.people, m.tents, m.store / 1000, m.demand as f64 / 1000.0, m.price as f64 / 1000.0, traders, m.free_area as f64 / 1e4);
        }
        let mut per: Vec<f64> = Vec::new();
        for f in &self.farms {
            if f.hh != NONE {
                let n = self.info.get(&f.hh).map_or(1, |i| i.size.max(1));
                per.push(f.area as f64 / 1e4 / n as f64);
            }
        }
        per.sort_by(f64::total_cmp);
        let q = |x: f64| per.get(((per.len() as f64 - 1.0) * x) as usize).copied().unwrap_or(0.0);
        let (mut nowant, mut noland) = (0, 0);
        for f in &self.farms {
            if f.hh != NONE && f.area == 0 {
                if self.want_m2(f.hh) == 0 {
                    nowant += 1;
                } else {
                    noland += 1;
                }
            }
        }
        let mut sizes = [0; 8];
        let mut nohands_sizes = [0; 8];
        for f in &self.farms {
            if f.hh != NONE {
                let i = self.info.get(&f.hh).copied().unwrap_or_default();
                sizes[(i.size as usize).min(7)] += 1;
                if self.want_m2(f.hh) == 0 {
                    nohands_sizes[(i.size as usize).min(7)] += 1;
                }
            }
        }
        let mut why = [0; 6];
        for (&id, st) in self.hh.iter() {
            if st.kind == WAGE && st.fed < 900 {
                let i = self.info[&id];
                let m = &self.markets[self.cell_market[i.home as usize] as usize];
                let k = if i.carrier == NONE { 0 } else if m.store <= 0 { 1 } else if st.money <= 0 { 2 } else if st.busy { 3 } else if m.cell == i.home { 4 } else { 5 };
                why[k] += 1;
            }
        }
        out += &format!("  hungry wage households: no carrier {}, empty market {}, no money {}, on the way {}, in market cell {}, other {}\n", why[0], why[1], why[2], why[3], why[4], why[5]);
        out += &format!("  zero-area farms: no hands {nowant}, no land {noland}; farm sizes {sizes:?}, without hands by size {nohands_sizes:?}\n");
        out += &format!("  farm ha per head: p10 {:.2} p25 {:.2} p50 {:.2} p75 {:.2} p90 {:.2}; zero {}\n", q(0.1), q(0.25), q(0.5), q(0.75), q(0.9), per.iter().filter(|&&x| x == 0.0).count());
        out
    }

    pub fn trips_waiting(&self) -> usize {
        self.wheel.iter().map(|v| v.len()).sum()
    }

    pub fn fingerprint(&mut self) -> u64 {
        self.walks_done();
        let mut b: Vec<u8> = Vec::new();
        for f in &self.farms {
            for x in [f.hh as i64, f.area, f.sown, f.store, f.money, f.to_sell] {
                b.extend_from_slice(&x.to_le_bytes());
            }
        }
        for m in &self.markets {
            for x in [m.store, m.money, m.price, m.demand] {
                b.extend_from_slice(&x.to_le_bytes());
            }
        }
        for id in sorted_keys(&self.hh) {
            let s = self.hh[&id];
            for x in [id as i64, s.kind as i64, s.pantry, s.money, s.farm as i64, s.fed as i64] {
                b.extend_from_slice(&x.to_le_bytes());
            }
        }
        b.extend_from_slice(&self.road_level);
        for f in self.markets.iter().filter_map(|m| m.field.as_ref()) {
            let mut w: Vec<u16> = f.worn.clone();
            w.sort_unstable();
            for i in w {
                b.extend_from_slice(&i.to_le_bytes());
                b.extend_from_slice(&f.wear[i as usize].to_le_bytes());
                b.push(f.level[i as usize]);
            }
        }
        xxh3_64(&b)
    }
}

/// Household kinds by name (`HouseholdLook::kind`).
pub const KIND_NAMES: [&str; 5] = ["Hof", "Zelt", "Lohn", "Händler", "Oberschicht"];
/// Farm kinds by name (`HouseholdLook::farm_kind`).
pub const FARM_KIND_NAMES: [&str; 3] = ["Familienhof", "Pachthof", "Gut"];

/// The trips under way in a box (`Grain::trips_in`), one entry per trip.
/// kind: 0 sale at the market, 1 purchase, 2 export, 3 import. Days with
/// fraction: out from depart to arrive, back from arrive to home; back is
/// true when it turns home the same day. The route of trip k is
/// points[first[k] .. first[k] + count[k]] in world km (x, z), from home
/// to the destination.
#[derive(Default, Clone, Debug)]
pub struct TripsView {
    pub day: i64,
    pub id: Vec<i64>,
    pub pid: Vec<i64>,
    pub kind: Vec<i32>,
    pub cargo_kg: Vec<i64>,
    pub depart: Vec<f64>,
    pub arrive: Vec<f64>,
    pub home: Vec<f64>,
    pub back: Vec<bool>,
    pub first: Vec<i32>,
    pub count: Vec<i32>,
    pub points: Vec<(f32, f32)>,
}

/// Hired work in a box (`Grain::work_in`), one entry per hire: worker
/// household, the farm's household (-1 if none), the exchange day, days of
/// work, kind (WORK_*), worker's home and farmstead in world km (x, z).
#[derive(Default, Clone, Debug)]
pub struct WorkView {
    pub worker: Vec<i64>,
    pub farm_household: Vec<i64>,
    pub day: Vec<i64>,
    pub days: Vec<i64>,
    pub kind: Vec<i32>,
    pub from: Vec<(f32, f32)>,
    pub to: Vec<(f32, f32)>,
}

/// What the game shows of a household (read only).
#[derive(Clone, Copy, Debug)]
pub struct HouseholdLook {
    /// Index into KIND_NAMES.
    pub kind: u8,
    /// Share of its need the household ate at the last meal count, ‰.
    pub fed: u16,
    pub pantry_kg: i64,
    /// Money, milli-denarii.
    pub money: i64,
    /// Its farm: kind (FARM_KIND_NAMES) and field area in m², if it has one.
    pub farm: Option<(u8, i64)>,
}

/// Read-only views of the grain economy for the game (presentation, S45):
/// nothing here changes the state or the fingerprint.
impl Grain {
    /// Calls `f(fine tile, field m², sown m², growth)` for each piece of a
    /// field of the farms with a household (S73 plots; a tile can come up
    /// more than once). Growth runs from 0 at sowing to 255 at the start of
    /// the farm's harvest, 0 outside.
    pub fn for_each_plot(&self, day: i64, mut f: impl FnMut(u32, u32, u32, u8)) {
        let cols = self.cols_f / FINE;
        let now = doy(day);
        for farm in self.farms.iter().filter(|x| x.hh != NONE && x.area > 0) {
            let len = (farm.harvest_doy - farm.sow_doy).rem_euclid(YEAR).max(1);
            let since = (now - farm.sow_doy).rem_euclid(YEAR);
            let growth = if farm.sown > 0 && since <= len { (since * 255 / len) as u8 } else { 0 };
            for pl in &farm.plots {
                let m2 = (pl.good + pl.poor) as i64;
                if m2 == 0 {
                    continue;
                }
                let cl = self.block_cell[pl.tile as usize / 256] as i32;
                let local = pl.tile as i32 % 256;
                let fine = ((cl / cols * FINE + local / FINE) * self.cols_f + cl % cols * FINE + local % FINE) as u32;
                f(fine, m2 as u32, (m2 * farm.sown / farm.area) as u32, growth);
            }
        }
    }

    /// Fine raster size: (rows, columns), 16 × 16 per 25 km cell.
    pub fn fine_size(&self) -> (i32, i32) {
        (self.rows_f, self.cols_f)
    }

    /// Footpaths of a market as of its last walk: (fine tile, level 1 trail
    /// or 2 path, direction of the next step towards the market as an index
    /// into the 8 neighbours row by row, 255 at the market). None while the
    /// market's walk is out on the path worker.
    /// The trips under way whose route touches the box (world km, as the
    /// people view), for the game to walk the carriers along their way.
    /// Read only. A market trip follows the market's path field tile by
    /// tile from the farmstead (as the footpaths are drawn); off the field
    /// it is a straight line. A trade trip runs through the centres of the
    /// 25 km cells of its route (as the trade roads are drawn). Out from
    /// `depart` to `arrive`, back the same way to `home`.
    pub fn trips_in(&mut self, p: &People, min: (f64, f64), max: (f64, f64)) -> TripsView {
        self.walks_done();
        let day = p.world.resource::<crate::people::Clock>().day;
        let mut v = TripsView { day, ..Default::default() };
        let cell_km = |c: u32| {
            let (r, col) = (c as i32 / p.grid.cols + p.grid.row0, c as i32 % p.grid.cols + p.grid.col0);
            (col as f64 * 25.0 + 12.5, r as f64 * 25.0 + 12.5)
        };
        let mut pts: Vec<(f64, f64)> = Vec::new();
        for t in self.trips.iter().filter(|t| t.left >= 0) {
            pts.clear();
            let m = &self.markets[t.market as usize];
            if matches!(t.kind, SELL | BUY) {
                pts.push(self.settle.fine_centre_km(t.from));
                if let Some(f) = m.field.as_ref() {
                    let (mut r, mut c) = (t.from as i32 / self.cols_f - f.r0, t.from as i32 % self.cols_f - f.c0);
                    let mut steps = 0;
                    while r >= 0 && c >= 0 && r < f.n && c < f.n && f.dist[(r * f.n + c) as usize] != u32::MAX && steps < f.n * f.n {
                        let d = f.dir[(r * f.n + c) as usize];
                        if d == 255 {
                            break;
                        }
                        r += DIRS[d as usize].0;
                        c += DIRS[d as usize].1;
                        steps += 1;
                        pts.push(self.settle.fine_centre_km(((f.r0 + r) * self.cols_f + f.c0 + c) as u32));
                    }
                }
                let end = self.settle.fine_centre_km(m.fine);
                if pts.last() != Some(&end) {
                    pts.push(end);
                }
            } else {
                pts.push(cell_km(m.cell));
                match m.neigh.iter().find(|nb| nb.m == t.dest) {
                    Some(nb) => pts.extend(nb.route.iter().map(|&c| cell_km(c))),
                    None => pts.push(cell_km(self.markets[t.dest as usize].cell)),
                }
            }
            if !pts.iter().any(|&(x, z)| x >= min.0 && x <= max.0 && z >= min.1 && z <= max.1) {
                continue;
            }
            let out = (t.back_days as f64).max(0.0);
            v.id.push(t.serial as i64);
            v.pid.push(t.pid as i64);
            v.kind.push(t.kind as i32);
            v.cargo_kg.push(t.kg);
            v.depart.push(t.left as f64);
            v.arrive.push(t.left as f64 + out);
            v.home.push(t.left as f64 + 2.0 * out);
            v.back.push(out == 0.0);
            v.first.push(v.points.len() as i32);
            v.count.push(pts.len() as i32);
            v.points.extend(pts.iter().map(|&(x, z)| (x as f32, z as f32)));
        }
        v
    }

    /// Who worked on whose farm at the last weekly labour exchange of each
    /// region (S72, S84), where the worker's home or the farm lies in the
    /// box (world km). Read only. One entry per hire: the worker's
    /// household and home, the farm's household and farmstead, the days of
    /// work bought that week from `day` on, and the kind (WORK_*).
    pub fn work_in(&self, min: (f64, f64), max: (f64, f64)) -> WorkView {
        let mut v = WorkView::default();
        let inside = |(x, z): (f64, f64)| x >= min.0 && x <= max.0 && z >= min.1 && z <= max.1;
        for m in &self.markets {
            for &(w, f, days, kind) in &m.work {
                let Some(ws) = self.hh.get(&w) else { continue };
                let fm = &self.farms[f as usize];
                let (a, b) = (self.settle.fine_centre_km(ws.fine), self.settle.fine_centre_km(fm.fine));
                if !inside(a) && !inside(b) {
                    continue;
                }
                v.worker.push(w as i64);
                v.farm_household.push(if fm.hh == NONE { -1 } else { fm.hh as i64 });
                v.day.push(m.work_day);
                v.days.push(days);
                v.kind.push(kind as i32);
                v.from.push((a.0 as f32, a.1 as f32));
                v.to.push((b.0 as f32, b.1 as f32));
            }
        }
        v
    }

    pub fn market_paths(&self, m: usize) -> Option<Vec<(u32, u8, u8)>> {
        let f = self.markets[m].field.as_ref()?;
        let mut v = Vec::with_capacity(f.worn.len());
        for &i in &f.worn {
            let level = f.level[i as usize];
            if level == 0 {
                continue;
            }
            let (r, c) = (f.r0 + i as i32 / f.n, f.c0 + i as i32 % f.n);
            v.push(((r * self.cols_f + c) as u32, level, f.dir[i as usize]));
        }
        v.sort_unstable();
        Some(v)
    }

    /// Market (region) of each 25 km cell, in the order of the road layer
    /// (people grid, row by row); NONE at sea. With the `markets` table
    /// (id = market index) the game colours regions by price or any other
    /// column.
    pub fn cell_markets(&self) -> &[u32] {
        &self.cell_market
    }

    /// Trade road level per 25 km cell (S71): 0 none, 1 track, 2 road on
    /// land; any level at sea is a sea lane.
    pub fn road_levels(&self) -> &[u8] {
        &self.road_level
    }

    /// Overview tables for the game (crate::tables): markets, people by
    /// region and job of the household, farms by region. Sums over the
    /// households of the last monthly count; rows sorted by region. Every
    /// table has a stable `id` per row and, for the camera, the longitude
    /// and latitude of the market and the width of its region.
    pub fn table(&self, p: &People, key: &str) -> Option<Table> {
        let day = p.world.resource::<crate::people::Clock>().day;
        match key {
            "markets" => Some(self.market_table(p, day)),
            "population" => Some(self.population_table(p, day)),
            "farms" => Some(self.farm_table(p, day)),
            "state" => Some(self.state_table(day)),
            "history" => Some(self.history_table(day)),
            _ => None,
        }
    }

    /// The history, one row per month (`track`): the month's flows and the
    /// levels after the monthly count.
    fn history_table(&self, day: i64) -> Table {
        let rows = &self.history.rows;
        let int = |f: &dyn Fn(&HistoryRow) -> i64| rows.iter().map(f).collect::<Vec<i64>>();
        let float = |f: &dyn Fn(&HistoryRow) -> f64| rows.iter().map(f).collect::<Vec<f64>>();
        let flow = |k: usize| int(&|r| r.flows[k]);
        let tonnes = |k: usize| float(&|r| r.flows[k] as f64 / 1000.0);
        let den = |f: &dyn Fn(&HistoryRow) -> i64| float(&|r| f(r) as f64 / 1000.0);
        let mut t = Table::new("history", "Verlauf", day);
        t.id((0..rows.len() as i64).collect());
        t.int("day", "Tag", "", int(&|r| r.day))
            .float("year", "Jahr", "", float(&|r| r.day as f64 / YEAR as f64))
            .int("persons", "Menschen", "", int(&|r| r.people as i64))
            .int("births", "Geburten im Monat", "", flow(0))
            .int("deaths", "Todesfälle im Monat", "", flow(1))
            .int("hunger_deaths", "Hungertote im Monat", "", flow(2))
            .int("left", "Verlassen die Karte", "", flow(3))
            .int("moved", "Umgezogen", "", flow(4))
            .float("harvest_t", "Ernte", "t", tonnes(5))
            .float("sold_t", "Verkauft", "t", tonnes(6))
            .float("traded_t", "Fernhandel", "t", tonnes(7))
            .float("alms_t", "Almosen", "t", tonnes(8))
            .float("stolen_t", "Gestohlen", "t", tonnes(9))
            .float("eaten", "Gegessen vom Bedarf", "%", float(&|r| if r.flows[11] == 0 { 1.0 } else { (r.flows[10] as f64 / r.flows[11] as f64).min(1.0) }))
            .int("hired_days", "Taglohn", "Tage", flow(12))
            .float("price_min", "Preis min", "Denar/kg", float(&|r| r.price.0))
            .float("price_median", "Preis Median", "Denar/kg", float(&|r| r.price.1))
            .float("price_max", "Preis max", "Denar/kg", float(&|r| r.price.2))
            .float("money_held", "Geld im Umlauf", "Denar", den(&|r| r.money_held))
            .float("minted", "Geprägt seit Start", "Denar", den(&|r| r.minted))
            .float("cash", "Staatskasse", "Denar", den(&|r| r.cash))
            .float("tax_grain_t", "Steuerkorn seit Start", "t", float(&|r| r.tax_grain_kg as f64 / 1000.0))
            .int("tent_persons", "Im Zelt", "", int(&|r| r.tent_people as i64))
            .int("farms", "Höfe", "", int(&|r| r.farms as i64))
            .float("farm_store_t", "Hoflager", "t", float(&|r| r.farm_store_kg as f64 / 1000.0))
            .float("market_store_t", "Marktlager", "t", float(&|r| r.market_store_kg as f64 / 1000.0));
        t
    }

    /// The treasury and the money cycle since the start (S94 step 1): one
    /// row, the state.
    fn state_table(&self, day: i64) -> Table {
        let (m, tr) = (self.money, self.treasury);
        let den = |x: i64| vec![x as f64 / 1000.0];
        let mut t = Table::new("state", "Staat", day);
        t.id(vec![0]);
        t.float("cash", "Staatskasse", "Denar", den(tr.cash))
            .float("wages", "Staatslohn", "Denar", den(tr.wages))
            .float("minted", "Neu geprägt", "Denar", den(m.minted))
            .float("rent", "Pacht Manciana", "Denar", den(tr.rent))
            .float("tax_grain_t", "Steuerkorn", "t", vec![tr.grain_kg as f64 / 1000.0])
            .float("held", "Geld im Umlauf", "Denar", den(self.money_held()))
            .float("start", "Geld am Anfang", "Denar", den(m.start))
            .float("endowed", "Startgeld neuer Haushalte", "Denar", den(m.endowed))
            .float("freight", "Fracht", "Denar", den(m.freight))
            .float("dissolved", "Geld aufgelöster Haushalte", "Denar", den(m.dissolved))
            .float("no_payee", "Ohne Empfänger", "Denar", den(m.no_payee))
            .float("unbooked", "Nicht gebucht", "Denar", den(self.money_unbooked()));
        t
    }

    /// Market of each region key.
    fn market_of_region(&self) -> FxHashMap<u32, usize> {
        self.markets.iter().enumerate().map(|(m, mk)| (mk.region, m)).collect()
    }

    /// Adds region name, longitude, latitude and width (km) for the
    /// markets `ms`, one per row.
    fn place_columns(&self, p: &People, t: &mut Table, ms: &[usize]) {
        let ll: Vec<(f64, f64)> = ms
            .iter()
            .map(|&m| {
                let c = self.markets[m].cell as i32;
                cell_lon_lat(c / p.grid.cols + p.grid.row0, c % p.grid.cols + p.grid.col0)
            })
            .collect();
        t.text("region", "Region", ms.iter().map(|&m| self.markets[m].name.clone()).collect())
            .hidden_float("lon", "°", ll.iter().map(|v| v.0).collect())
            .hidden_float("lat", "°", ll.iter().map(|v| v.1).collect())
            .hidden_float("extent_km", "km", vec![REGION_KM; ms.len()]);
    }

    fn market_table(&self, p: &People, day: i64) -> Table {
        let mut order: Vec<usize> = (0..self.markets.len()).collect();
        order.sort_unstable_by_key(|&m| self.markets[m].region);
        let (mut hungry, mut counted) = (vec![0i64; self.markets.len()], vec![0i64; self.markets.len()]);
        for (id, i) in self.info.iter() {
            let mk = self.cell_market[i.home as usize];
            let Some(s) = self.hh.get(id) else { continue };
            if mk == NONE || s.own_food {
                continue;
            }
            counted[mk as usize] += i.size as i64;
            if s.fed < NEED_FED {
                hungry[mk as usize] += i.size as i64;
            }
        }
        let int = |f: &dyn Fn(&Market) -> i64| order.iter().map(|&m| f(&self.markets[m])).collect::<Vec<i64>>();
        let float = |f: &dyn Fn(&Market) -> f64| order.iter().map(|&m| f(&self.markets[m])).collect::<Vec<f64>>();
        let mut t = Table::new("markets", "Märkte", day);
        t.id(order.iter().map(|&m| m as i64).collect());
        self.place_columns(p, &mut t, &order);
        t.float("price", "Preis", "Denar/kg", float(&|m| m.price as f64 / 1000.0))
            .int("store_kg", "Lager", "kg", int(&|m| m.store))
            .float("money", "Händlergeld", "Denar", float(&|m| m.money as f64 / 1000.0))
            .float("sales_day", "Verkauf", "kg/Tag", float(&|m| m.demand as f64 / 1000.0))
            .int("persons", "Menschen", "", int(&|m| m.people as i64))
            .int("buyers", "Käufer", "", int(&|m| m.buyers as i64))
            .int("tent_persons", "Im Zelt", "", int(&|m| m.tent_people as i64))
            .int("grain_kg", "Getreide der Region", "kg", int(&|m| m.grain))
            .float("free_ha", "Freies Land", "ha", float(&|m| m.free_area as f64 / 1e4))
            .float("share_hungry", "Hungernd", "%", order.iter().map(|&m| if counted[m] > 0 { hungry[m] as f64 / counted[m] as f64 } else { 0.0 }).collect());
        t
    }

    fn population_table(&self, p: &People, day: i64) -> Table {
        // (region, job) -> (households, people, fed people, money in milli-denarii)
        let mut sums: std::collections::BTreeMap<(u32, u8), (i64, i64, i64, i64)> = Default::default();
        for (id, i) in self.info.iter() {
            let mk = self.cell_market[i.home as usize];
            let Some(s) = self.hh.get(id) else { continue };
            if mk == NONE {
                continue;
            }
            let e = sums.entry((self.markets[mk as usize].region, i.job)).or_default();
            e.0 += 1;
            e.1 += i.size as i64;
            if s.own_food || s.fed >= NEED_FED {
                e.2 += i.size as i64;
            }
            e.3 += self.money_of(*id);
        }
        let of = self.market_of_region();
        let ms: Vec<usize> = sums.keys().map(|(k, _)| of[k]).collect();
        let mut t = Table::new("population", "Bevölkerung", day);
        t.id(sums.keys().map(|&(k, j)| (k as i64) << 4 | j as i64).collect());
        self.place_columns(p, &mut t, &ms);
        t.text("occupation", "Beruf", sums.keys().map(|&(_, j)| crate::groups::JOB_NAMES.get(j as usize).copied().unwrap_or("?").to_string()).collect())
            .int("households", "Haushalte", "", sums.values().map(|v| v.0).collect())
            .int("persons", "Menschen", "", sums.values().map(|v| v.1).collect())
            .float("share_fed", "Satt", "%", sums.values().map(|v| if v.1 > 0 { v.2 as f64 / v.1 as f64 } else { 0.0 }).collect())
            .float("money_mean", "Geld je Kopf", "Denar", sums.values().map(|v| v.3 as f64 / 1000.0 / v.1.max(1) as f64).collect());
        t
    }

    fn farm_table(&self, p: &People, day: i64) -> Table {
        // region -> (family, tenant, estate, manciana, area m², sown m², store kg, money)
        let mut sums: std::collections::BTreeMap<u32, [i64; 8]> = Default::default();
        for f in self.farms.iter().filter(|f| f.hh != NONE) {
            let e = sums.entry(self.markets[f.market as usize].region).or_default();
            e[f.kind as usize] += 1;
            e[3] += f.manciana as i64;
            e[4] += f.area;
            e[5] += f.sown;
            e[6] += f.store;
            e[7] += f.money;
        }
        let of = self.market_of_region();
        let ms: Vec<usize> = sums.keys().map(|k| of[k]).collect();
        let col = |k: usize| sums.values().map(|v| v[k]).collect::<Vec<i64>>();
        let mut t = Table::new("farms", "Höfe", day);
        t.id(sums.keys().map(|&k| k as i64).collect());
        self.place_columns(p, &mut t, &ms);
        t.int("family", "Familienhöfe", "", col(0))
            .int("tenant", "Pachthöfe", "", col(1))
            .int("estate", "Güter", "", col(2))
            .int("manciana", "davon Lex Manciana", "", col(3))
            .float("area_ha", "Felder", "ha", sums.values().map(|v| v[4] as f64 / 1e4).collect())
            .float("sown_ha", "Gesät", "ha", sums.values().map(|v| v[5] as f64 / 1e4).collect())
            .int("store_kg", "Hoflager", "kg", col(6))
            .float("money", "Geld der Höfe", "Denar", sums.values().map(|v| v[7] as f64 / 1000.0).collect());
        t
    }

    /// A household's kind, food, stores and farm, if the grain economy
    /// knows it (it counts the households once a month).
    pub fn household(&self, hh: u32) -> Option<HouseholdLook> {
        let s = self.hh.get(&hh)?;
        let farm = (s.farm != NONE).then(|| self.farms.get(s.farm as usize)).flatten().filter(|f| f.hh == hh).map(|f| (f.kind, f.area));
        Some(HouseholdLook { kind: s.kind, fed: s.fed, pantry_kg: s.pantry, money: s.money, farm })
    }
}

/// Most field m² a fine tile in absolute 25 km row `r` holds: its area
/// (eqc, data/projection.json: true at 41° N, east-west by cos(lat) /
/// cos(41°) elsewhere) per simulated person.
pub fn tile_room_m2(r: i32) -> i64 {
    let lat = (41.0 - (r as f64 * 25_000.0 + 12_500.0) / 6_371_008.8 * 180.0 / std::f64::consts::PI).to_radians();
    (1562.5 * 1562.5 * lat.cos() / 41f64.to_radians().cos() / crate::people::PEOPLE_PER_PERSON) as i64
}

const DIRS: [(i32, i32); 8] = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)];

/// Wear after `dt` days: whole half-lives as shifts, the rest from a table
/// of 2^(−d/PATH_HALF) × 2^16 (integers, so the same on every machine).
fn decay(tab: &[i64], w: i64, dt: i64) -> i64 {
    let halves = dt / PATH_HALF;
    if halves >= 40 {
        return 0;
    }
    (w >> halves) * tab[(dt % PATH_HALF) as usize] >> 16
}

fn decay_table() -> Vec<i64> {
    (0..PATH_HALF).map(|d| (65536.0 * life::exp_neg(std::f64::consts::LN_2 * d as f64 / PATH_HALF as f64)).round() as i64).collect()
}

fn sorted_keys<V>(m: &IdMap<V>) -> Vec<u32> {
    let mut v = m.ids.clone();
    v.sort_unstable();
    v
}

/// The KNOWN cheapest markets from the market at `src` by freight
/// (Dijkstra over 25 km cells: wagon over land, cheaper on trade roads;
/// ship at sea; no step between sea and blocked land).
/// Also returns the box of all cells it touched.
fn neighbours(net: &Net, src: u32) -> (Vec<Neigh>, Vec<u32>) {
    // Per-thread buffers over the whole grid, reset only where touched
    // (a fresh 25 km grid per search cost more than the search).
    thread_local! {
        static BUF: std::cell::RefCell<(Vec<i64>, Vec<i64>, Vec<u32>, Vec<u32>)> = const { std::cell::RefCell::new((Vec::new(), Vec::new(), Vec::new(), Vec::new())) };
    }
    BUF.with_borrow_mut(|(best, days, par, touched)| {
        let n = net.kind.len();
        if best.len() != n {
            *best = vec![i64::MAX; n];
            *days = vec![0; n];
            *par = vec![NONE; n];
        }
        touched.push(src);
        let out = search(net, src, best, days, par, touched);
        // The land cells the search reached: only a change of their trade
        // road level can change its result (a cell it never reached lies
        // behind its frontier, which is past the farthest neighbour).
        let mut reach: Vec<u32> = touched.iter().copied().filter(|&j| net.kind[j as usize] != 0).collect();
        reach.sort_unstable();
        for &j in touched.iter() {
            best[j as usize] = i64::MAX;
            days[j as usize] = 0;
            par[j as usize] = NONE;
        }
        touched.clear();
        (out, reach)
    })
}

fn search(net: &Net, src: u32, best: &mut [i64], days: &mut [i64], par: &mut [u32], touched: &mut Vec<u32>) -> Vec<Neigh> {
    let (rows, cols, kind, at, level) = (net.rows, net.cols, &net.kind, &net.at, &net.level);
    let mut open = BinaryHeap::new();
    best[src as usize] = 0;
    open.push(Reverse((0i64, src)));
    let mut out = Vec::new();
    while let Some(Reverse((c, i))) = open.pop() {
        if c > best[i as usize] {
            continue;
        }
        if i != src && at[i as usize] != NONE {
            let mut route = Vec::new();
            let mut j = i;
            while j != src {
                route.push(j);
                j = par[j as usize];
            }
            route.reverse();
            out.push(Neigh { m: at[i as usize], cost: c, days: ((days[i as usize] + 999) / 1000).max(1), route });
            if out.len() >= KNOWN {
                break;
            }
        }
        let (r, col) = (i as i32 / cols, i as i32 % cols);
        for dr in -1..=1 {
            for dc in -1..=1 {
                if dr == 0 && dc == 0 {
                    continue;
                }
                let (nr, nc) = (r + dr, col + dc);
                if nr < 0 || nc < 0 || nr >= rows || nc >= cols {
                    continue;
                }
                let j = (nr * cols + nc) as u32;
                let (ka, kb) = (kind[i as usize], kind[j as usize]);
                let km = if dr != 0 && dc != 0 { 35 } else { 25 };
                let (cost, d) = match (ka, kb) {
                    (0, 2) | (2, 0) => continue,
                    (0, _) | (_, 0) => (km * SEA_COST, km * 1000 / SEA_KM_DAY),
                    _ => (km * WAGON_COST * LEVEL_COST_PCT[level[j as usize] as usize] / 100, km * 1000 / WAGON.1),
                };
                let nc_ = c + cost;
                if nc_ < best[j as usize] {
                    if best[j as usize] == i64::MAX {
                        touched.push(j);
                    }
                    best[j as usize] = nc_;
                    days[j as usize] = days[i as usize] + d;
                    par[j as usize] = i;
                    open.push(Reverse((nc_, j)));
                }
            }
        }
    }
    out
}

/// What the neighbour search reads: the 25 km grid, the market at each
/// cell and the trade road levels. Shared with the road worker thread;
/// replaced when the levels change.
struct Net {
    row0: i32,
    col0: i32,
    rows: i32,
    cols: i32,
    kind: Vec<u8>,
    at: Vec<u32>,
    level: Vec<u8>,
}

type Searched = Vec<(Vec<Neigh>, Vec<u32>)>;

/// A thread that runs the neighbour searches of a day while the day goes
/// on (they are only used from the next day).
struct RoadWorker {
    send: std::sync::mpsc::Sender<(std::sync::Arc<Net>, Vec<u32>)>,
    recv: std::sync::mpsc::Receiver<Searched>,
}

impl RoadWorker {
    fn new() -> RoadWorker {
        let (send, jobs) = std::sync::mpsc::channel::<(std::sync::Arc<Net>, Vec<u32>)>();
        let (done, recv) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            for (net, cells) in jobs {
                if done.send(cells.iter().map(|&c| neighbours(&net, c)).collect::<Searched>()).is_err() {
                    break;
                }
            }
        });
        RoadWorker { send, recv }
    }
}

type WalkJob = (std::sync::Arc<Net>, std::sync::Arc<Vec<i64>>, i32, Vec<Walk>, i64);

/// A thread that runs a day's path walks (one task per market on the
/// task pool) while the rest of the day and the next people day go on.
struct WalkWorker {
    send: std::sync::mpsc::Sender<WalkJob>,
    recv: std::sync::mpsc::Receiver<Vec<Walk>>,
}

impl WalkWorker {
    fn new() -> WalkWorker {
        let (send, jobs) = std::sync::mpsc::channel::<WalkJob>();
        let (done, recv) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            for (net, tab, cols_f, mut walks, day) in jobs {
                let (net, tab) = (&*net, &tab[..]);
                // One task per market: rebuilds are few and uneven.
                bevy_tasks::ComputeTaskPool::get().scope(|s| {
                    for w in walks.iter_mut() {
                        s.spawn(async move { walk(net, cols_f, tab, w, day) });
                    }
                });
                if done.send(walks).is_err() {
                    break;
                }
            }
        });
        WalkWorker { send, recv }
    }
}

/// One market's walk on a path day (see `Grain::paths`).
struct Walk {
    m: u32,
    region: u32,
    fine: u32,
    origins: Vec<(u32, i64)>,
    field: Option<Field>,
    dirty: bool,
    first_us: f64,
    rebuild_us: f64,
    rebuilt: bool,
}

fn walk(grid: &Net, cols_f: i32, tab: &[i64], w: &mut Walk, day: i64) {
    if w.field.is_none() {
        let t0 = std::time::Instant::now();
        w.field = Some(build_field(grid, cols_f, w.region, w.fine, None, day));
        w.first_us = t0.elapsed().as_secs_f64() * 1e6;
    }
    let f = w.field.as_mut().unwrap();
    // Every route follows the field to the market; add up the trips per
    // cell, then wear each cell once. The trips flow down the field's tree
    // from the farthest cell to the market, so a stretch shared by many
    // routes is visited once.
    let mut acc = vec![0i64; (f.n * f.n) as usize];
    for &(o, k) in &w.origins {
        let (r, c) = ((o as i32 / cols_f) - f.r0, (o as i32 % cols_f) - f.c0);
        if r < 0 || c < 0 || r >= f.n || c >= f.n {
            continue;
        }
        let i = (r * f.n + c) as usize;
        if f.dist[i] == u32::MAX {
            continue;
        }
        acc[i] += k;
    }
    let mut cells: Vec<(u32, i64)> = Vec::new();
    for &i in f.order.iter().rev() {
        let k = acc[i as usize];
        if k == 0 {
            continue;
        }
        cells.push((i as u32, k));
        let d = f.dir[i as usize];
        if d == 255 {
            continue;
        }
        let (dr, dc) = DIRS[d as usize];
        let j = ((i as i32 / f.n + dr) * f.n + i as i32 % f.n + dc) as usize;
        acc[j] += k;
    }
    cells.sort_unstable();
    let mut changed = w.dirty;
    // Wear decays since the last walk, then this walk adds to it.
    let dt = day - f.walked;
    f.walked = day;
    for &i in &f.worn {
        f.wear[i as usize] = decay(tab, f.wear[i as usize] as i64, dt) as u32;
    }
    for &(i, k) in &cells {
        if f.wear[i as usize] == 0 {
            f.worn.push(i as u16);
        }
        f.wear[i as usize] = (f.wear[i as usize] as i64 + 2 * k * WEAR_UNIT).min(u32::MAX as i64) as u32;
    }
    let (wear, level) = (&f.wear, &mut f.level);
    f.worn.retain(|&i| {
        let w = wear[i as usize] as i64;
        let old = level[i as usize];
        let mut lv = old;
        while (lv as usize) < LEVELS.len() && w >= LEVELS[lv as usize].0 {
            lv += 1;
        }
        while lv > 0 && w < LEVELS[lv as usize - 1].1 {
            lv -= 1;
        }
        if lv != old {
            level[i as usize] = lv;
            changed = true;
        }
        w > 0
    });
    w.dirty = changed;
    if changed && day - f.built >= WALK_DAYS {
        let t0 = std::time::Instant::now();
        w.field = Some(build_field(grid, cols_f, w.region, w.fine, w.field.take(), day));
        w.dirty = false;
        w.rebuilt = true;
        w.rebuild_us = t0.elapsed().as_secs_f64() * 1e6;
    }
}

/// Dijkstra over the market's region (64 × 64 fine cells) from the
/// market, step cost by path level; sea cells (coarse) are blocked.
fn build_field(grid: &Net, cols_f: i32, key: u32, fine: u32, old: Option<Field>, day: i64) -> Field {
    let n = 4 * FINE;
    let (rr, rc) = ((key >> 16) as i32 - 64, (key & 0xffff) as i32 - 64);
    let (r0, c0) = ((rr * 4 - grid.row0) * FINE, (rc * 4 - grid.col0) * FINE);
    let size = (n * n) as usize;
    let mut dist = vec![u32::MAX; size];
    let mut dir = vec![255u8; size];
    let (mr, mc) = ((fine as i32 / cols_f) - r0, (fine as i32 % cols_f) - c0);
    // Wear and levels stay with the market's field across rebuilds.
    let (level, wear, worn, walked) = match old {
        Some(old) => (old.level, old.wear, old.worn, old.walked),
        None => (vec![0u8; size], vec![0u32; size], Vec::new(), day),
    };
    if mr < 0 || mc < 0 || mr >= n || mc >= n {
        return Field { r0, c0, n, dist, dir, level, wear, worn, walked, built: day, order: Vec::new() };
    }
    // Passable: the field covers 4 × 4 coarse cells; sea is blocked.
    let mut land = [false; 16];
    for (k, l) in land.iter_mut().enumerate() {
        let (cr, cc) = (r0 / FINE + k as i32 / 4, c0 / FINE + k as i32 % 4);
        *l = cr >= 0 && cc >= 0 && cr < grid.rows && cc < grid.cols && grid.kind[(cr * grid.cols + cc) as usize] != 0;
    }
    // Step costs into each cell (0: blocked) on a grid with a blocked
    // border, so a step needs no bounds check.
    let w = n + 2;
    let (mut ortho, mut diag) = (vec![0u32; (w * w) as usize], vec![0u32; (w * w) as usize]);
    for r in 0..n {
        for c in 0..n {
            if land[((r / FINE) * 4 + c / FINE) as usize] {
                let pct = LEVEL_COST_PCT[level[(r * n + c) as usize] as usize];
                let pj = ((r + 1) * w + c + 1) as usize;
                ortho[pj] = (FINE_STEP * pct / 100) as u32;
                diag[pj] = (141 * pct / 100) as u32;
            }
        }
    }
    let off = DIRS.map(|(dr, dc)| (dr * w + dc) as isize);
    let mut pd = vec![u32::MAX; (w * w) as usize];
    let mut pdir = vec![255u8; (w * w) as usize];
    // Dial's bucket queue (integer step costs below 256).
    let mut buckets: Vec<Vec<u32>> = vec![Vec::new(); 256];
    let start = ((mr + 1) * w + mc + 1) as u32;
    pd[start as usize] = 0;
    buckets[0].push(start);
    let (mut g, mut pending) = (0u32, 1usize);
    let mut settled: Vec<u32> = Vec::new();
    while pending > 0 {
        if buckets[(g & 255) as usize].is_empty() {
            g += 1;
            continue;
        }
        let mut b = std::mem::take(&mut buckets[(g & 255) as usize]);
        for &i in &b {
            pending -= 1;
            if pd[i as usize] != g {
                continue;
            }
            settled.push(i);
            for (d, &o) in off.iter().enumerate() {
                let j = (i as isize + o) as usize;
                let step = if d == 1 || d == 3 || d == 4 || d == 6 { ortho[j] } else { diag[j] };
                if step == 0 {
                    continue;
                }
                let ng = g + step;
                if ng < pd[j] {
                    pd[j] = ng;
                    pdir[j] = (7 - d) as u8;
                    buckets[(ng & 255) as usize].push(j as u32);
                    pending += 1;
                }
            }
        }
        b.clear();
        if buckets[(g & 255) as usize].is_empty() {
            buckets[(g & 255) as usize] = b;
        }
        g += 1;
    }
    for r in 0..n {
        for c in 0..n {
            let (i, pj) = ((r * n + c) as usize, ((r + 1) * w + c + 1) as usize);
            dist[i] = pd[pj];
            dir[i] = pdir[pj];
        }
    }
    let order = settled.iter().map(|&pj| ((pj as i32 / w - 1) * n + pj as i32 % w - 1) as u16).collect();
    Field { r0, c0, n, dist, dir, level, wear, worn, walked, built: day, order }
}

/// Groups a snapshot by household (counting sort, no comparison sort) and
/// counts each household: who lives where, needs how much, can work and
/// carry. Pure, so it can run on another thread. Returns the households,
/// the person ids grouped by household and the emptied buffer.
fn count_households(snap: Vec<Row>, n: u32, day: i64) -> (IdMap<HhInfo>, Vec<u32>, Vec<Row>) {
    // Person id order first, then grouped by household (stable).
    let n = n as usize;
    let mut by_pid = vec![(NONE, 0, 0, 0, 0, 0, 0); n];
    for r in &snap {
        by_pid[r.1 as usize] = *r;
    }
    let mut at = vec![0u32; n + 1];
    for r in &by_pid {
        if r.0 != NONE {
            at[r.0 as usize + 1] += 1;
        }
    }
    for k in 0..n {
        at[k + 1] += at[k];
    }
    let mut rows = vec![(0, 0, 0, 0, 0, 0, 0); at[n] as usize];
    for r in &by_pid {
        if r.0 != NONE {
            rows[at[r.0 as usize] as usize] = *r;
            at[r.0 as usize] += 1;
        }
    }
    let mut info = IdMap::default();
    let age = |b: i32| (day - b as i64) as f64 / YEAR as f64;
    let mut k = 0;
    while k < rows.len() {
        let id = rows[k].0;
        let mut e = k;
        while e < rows.len() && rows[e].0 == id {
            e += 1;
        }
        let m = &rows[k..e];
        // Head: the lowest person id among the adults, else the lowest.
        let head = m.iter().find(|r| age(r.6) >= ADULT.0).unwrap_or(&m[0]);
        let mut man = false;
        let mut spare = NONE;
        let mut inf = HhInfo { home: head.2, stand: head.5, job: head.4, carrier: NONE, trader: NONE, at: k as u32, ..Default::default() };
        for r in m {
            let a = age(r.6);
            inf.size += 1;
            inf.need_w += if a < CHILD_AGE { 5 } else { 10 };
            if (ADULT.0..ADULT.1).contains(&a) {
                inf.adults += 1;
                // The first man, else the first woman.
                if inf.carrier == NONE || (r.3 == 1 && !man) {
                    man = r.3 == 1;
                    inf.carrier = r.1;
                }
                if r.4 == HAENDLER && inf.trader == NONE {
                    inf.trader = r.1;
                }
            }
            if (PEAK_HANDS.0..PEAK_HANDS.1).contains(&a) {
                inf.hands += 1;
                // Without an adult, an older child or old person goes.
                if inf.carrier == NONE {
                    spare = r.1;
                }
            }
        }
        if inf.carrier == NONE {
            inf.carrier = spare;
        }
        info.insert(id, inf);
        k = e;
    }
    let members = rows.iter().map(|r| r.1).collect();
    let mut snap = snap;
    snap.clear();
    (info, members, snap)
}

/// A map from household id (a person id, dense and never reused) to a
/// value: a slot per id and the values packed, so a lookup is two array
/// reads. Iteration follows insertion and removal (deterministic, but not
/// sorted; `sorted_keys` sorts).
struct IdMap<V> {
    slot: Vec<u32>,
    ids: Vec<u32>,
    vals: Vec<V>,
}

impl<V> Default for IdMap<V> {
    fn default() -> Self {
        IdMap { slot: Vec::new(), ids: Vec::new(), vals: Vec::new() }
    }
}

impl<V> IdMap<V> {
    fn at(&self, id: u32) -> Option<usize> {
        self.slot.get(id as usize).copied().filter(|&k| k != NONE).map(|k| k as usize)
    }
    fn get(&self, id: &u32) -> Option<&V> {
        self.at(*id).map(|k| &self.vals[k])
    }
    fn get_mut(&mut self, id: &u32) -> Option<&mut V> {
        self.at(*id).map(|k| &mut self.vals[k])
    }
    fn contains_key(&self, id: &u32) -> bool {
        self.at(*id).is_some()
    }
    fn insert(&mut self, id: u32, v: V) {
        match self.at(id) {
            Some(k) => self.vals[k] = v,
            None => {
                if self.slot.len() <= id as usize {
                    self.slot.resize(id as usize + 1, NONE);
                }
                self.slot[id as usize] = self.ids.len() as u32;
                self.ids.push(id);
                self.vals.push(v);
            }
        }
    }
    fn remove(&mut self, id: &u32) {
        if let Some(k) = self.at(*id) {
            let last = *self.ids.last().unwrap();
            self.ids.swap_remove(k);
            self.vals.swap_remove(k);
            if last != *id {
                self.slot[last as usize] = k as u32;
            }
            self.slot[*id as usize] = NONE;
        }
    }
    #[cfg(test)]
    fn clear(&mut self) {
        for &id in &self.ids {
            self.slot[id as usize] = NONE;
        }
        self.ids.clear();
        self.vals.clear();
    }
    fn values(&self) -> std::slice::Iter<'_, V> {
        self.vals.iter()
    }
    fn iter(&self) -> impl Iterator<Item = (&u32, &V)> {
        self.ids.iter().zip(self.vals.iter())
    }
}

impl<V> std::ops::Index<&u32> for IdMap<V> {
    type Output = V;
    fn index(&self, id: &u32) -> &V {
        self.get(id).expect("household")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    /// Same seed, same grain state after 200 days (a harvest included).
    #[test]
    fn deterministic_fingerprint() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let run = || {
            let mut p = People::new(&inp, 3);
            let mut g = Grain::new(&inp, &mut p);
            for _ in 0..200 {
                p.day();
                g.day(&mut p);
                // S94 step 1: every denarius is booked.
                assert_eq!(g.money_unbooked(), 0);
            }
            assert!(g.stats.harvest_kg > 0 && g.stats.sold_kg > 0);
            assert!(g.money.minted > 0 && g.money.freight > 0 && g.treasury.wages >= g.money.minted);
            // The history adds up to the counters (none reset here).
            let h = g.history();
            assert!(h.len() >= 6);
            assert_eq!(h.iter().map(|r| r.flows[0]).sum::<i64>() + g.history.month[0], p.stats.births as i64);
            assert_eq!(h.iter().map(|r| r.flows[5]).sum::<i64>() + g.history.month[5], g.stats.harvest_kg);
            // The trips view is read only and every trip has a route.
            let before = g.fingerprint();
            let v = g.trips_in(&p, (-1e9, -1e9), (1e9, 1e9));
            assert!(!v.id.is_empty() && v.kind.contains(&(SELL as i32)) && v.kind.contains(&(EXPORT as i32)));
            assert!(v.count.iter().all(|&n| n >= 2) && v.count.iter().map(|&n| n as usize).sum::<usize>() == v.points.len());
            assert!(v.depart.iter().zip(&v.arrive).zip(&v.home).all(|((d, a), h)| d <= a && a <= h && *d <= v.day as f64 && v.day as f64 <= *h));
            let w = g.work_in((-1e9, -1e9), (1e9, 1e9));
            assert!(!w.worker.is_empty() && w.days.iter().all(|&d| d > 0) && w.from.len() == w.worker.len());
            assert_eq!(g.fingerprint(), before);
            (p.fingerprint(), g.fingerprint())
        };
        assert_eq!(run(), run());
    }

    /// S83: an heir's share moves on the same tiles: no land appears or
    /// vanishes, the tiles' free land is untouched, plots add up to area.
    #[test]
    fn inheritance_moves_land_on_the_same_tiles() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let mut p = People::new(&inp, 3);
        let mut g = Grain::new(&inp, &mut p);
        let f = (0..g.farms.len()).find(|&f| g.farms[f].hh != NONE && g.farms[f].area > 20_000 && g.farms[f].plots.len() > 1).unwrap();
        let free: (i64, i64) = (g.free_m2.iter().sum(), g.free_poor.iter().sum());
        let tiles: Vec<[u16; 2]> = g.tiles.clone();
        let (area, poor) = (g.farms[f].area, g.farms[f].poor);
        let i = g.info[&g.farms[f].hh];
        let t = g.new_farm_for_heir(u32::MAX - 1, &i, g.farms[f].fine, f as u32) as usize;
        g.move_land(f, t, area / 3);
        let sum = |fm: &Farm| fm.plots.iter().map(|p| (p.good + p.poor) as i64).sum::<i64>();
        let sum_poor = |fm: &Farm| fm.plots.iter().map(|p| p.poor as i64).sum::<i64>();
        assert_eq!(g.farms[t].area, area / 3);
        assert_eq!(g.farms[f].area + g.farms[t].area, area);
        assert_eq!(g.farms[f].poor + g.farms[t].poor, poor);
        for fm in [&g.farms[f], &g.farms[t]] {
            assert_eq!(sum(fm), fm.area);
            assert_eq!(sum_poor(fm), fm.poor);
        }
        assert_eq!((g.free_m2.iter().sum::<i64>(), g.free_poor.iter().sum::<i64>()), free);
        assert!(g.tiles == tiles);
        // The share keeps the father's calendar.
        assert_eq!((g.farms[t].harvest_doy, g.farms[t].sow_doy), (g.farms[f].harvest_doy, g.farms[f].sow_doy));
    }

    /// S92: the start makes Manciana farms of tents, sown, without tax;
    /// a lapsed one gives all its land back to the tiles and its household
    /// goes back to the tent with the store.
    #[test]
    fn manciana_land_comes_back() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let mut p = People::new(&inp, 3);
        let mut g = Grain::new(&inp, &mut p);
        assert!(g.stats.manciana_new > 0);
        let f = (0..g.farms.len()).find(|&f| g.farms[f].manciana && g.farms[f].hh != NONE).unwrap();
        assert_eq!(g.farms[f].kind, TENANT);
        assert!(g.farms[f].sown > 0);
        let (good, poor) = (g.free_m2.iter().sum::<i64>(), g.free_poor.iter().sum::<i64>());
        let (area, fpoor, store, id) = (g.farms[f].area, g.farms[f].poor, g.farms[f].store, g.farms[f].hh);
        let pantry = g.hh[&id].pantry;
        g.manciana_lapse(f);
        assert_eq!(g.farms[f].area, 0);
        assert!(g.farms[f].plots.is_empty());
        assert_eq!(g.free_m2.iter().sum::<i64>() + g.free_poor.iter().sum::<i64>(), good + poor + area);
        assert_eq!(g.free_poor.iter().sum::<i64>(), poor + fpoor);
        let h = g.hh[&id];
        assert_eq!((h.kind, h.farm, h.pantry), (TENT, NONE, pantry + store));
    }

    /// The game's tables: every column as long as the others, shares in
    /// 0..1, the people of all rows add up, and building them changes
    /// nothing in the state.
    #[test]
    fn tables_read_only() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
        let Ok(inp) = crate::inputs::load(&root, false) else {
            return;
        };
        let mut p = People::new(&inp, 3);
        let mut g = Grain::new(&inp, &mut p);
        let before = g.fingerprint();
        for key in crate::tables::TABLES {
            let t = g.table(&p, key).unwrap();
            assert!(t.rows() > 0 || key == "history", "{key}");
            assert!(t.columns.iter().all(|c| c.values.len() == t.rows()), "{key}");
            assert!(t.column("id").is_some_and(|c| c.hidden), "{key}");
            assert!(matches!(key, "state" | "history") || t.column("lon").is_some_and(|c| c.hidden), "{key}");
            for c in t.columns.iter().filter(|c| c.unit == "%") {
                let crate::tables::Values::Float(v) = &c.values else { panic!("{}", c.key) };
                assert!(v.iter().all(|x| (0.0..=1.0).contains(x)), "{key} {}", c.key);
            }
        }
        let persons = |key: &str| match &g.table(&p, key).unwrap().column("persons").unwrap().values {
            crate::tables::Values::Int(v) => v.iter().sum::<i64>(),
            _ => panic!(),
        };
        assert_eq!(persons("markets"), persons("population"));
        let names = g.table(&p, "markets").unwrap();
        let crate::tables::Values::Text(n) = &names.column("region").unwrap().values else { panic!() };
        assert!(n.iter().any(|x| x == "Rome (Roma)"), "{:?}", &n[..5]);
        assert!(g.table(&p, "nothing").is_none());
        assert_eq!(g.fingerprint(), before);
    }

    #[test]
    fn wear_halves() {
        let tab = decay_table();
        assert_eq!(decay(&tab, 1 << 20, 0), 1 << 20);
        assert_eq!(decay(&tab, 1 << 20, PATH_HALF), 1 << 19);
        let q = decay(&tab, 1 << 20, PATH_HALF / 2);
        assert!((q - 741_455).abs() < 2, "{q}");
    }

    #[test]
    fn id_map() {
        let mut m: IdMap<u8> = IdMap::default();
        m.insert(7, 1);
        m.insert(3, 2);
        m.insert(9, 3);
        m.remove(&3);
        assert_eq!(m.get(&9), Some(&3));
        assert_eq!(m.get(&3), None);
        assert_eq!(sorted_keys(&m), vec![7, 9]);
        m.clear();
        assert!(!m.contains_key(&7));
    }
}
