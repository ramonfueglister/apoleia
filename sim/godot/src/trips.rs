//! The trips under way (apoleia_sim::grain::TripsView) as a Godot
//! dictionary, for the carriers and wagons walking on the map. Built on the
//! sim thread between two days (`Grain::trips_in`), handed over like
//! `take_person`.
//!
//! Dictionary: day, and one entry per trip in id (stable while the trip
//! lasts), pid, kind (0 sale, 1 purchase, 2 export, 3 import), cargo_kg,
//! depart, arrive, home (days), back (turns home the same day), first and
//! count (its route in points), points (world km, home to destination).
//!
//! Hired work (`Grain::work_in`, `work_to_dict`): worker (household),
//! farm_household (-1 if none), day (the week's labour exchange), days,
//! kind (0 sowing, 1 harvest, 2 outside the peaks, 3 from a surplus), from
//! (worker's home) and to (farmstead) in world km.

//!
//! Craft goods (`goods_to_dict`), flat arrays: crafts [x, z, craft
//! (1 weaver, 2 smith, 3 potter), util 0–255] per workshop; markets [x, z,
//! store × 6, price × 6 (wool, iron, cloth, tools, pottery, pork; units and
//! denarii)] per market; moves [from x, from z, to x, to z, good, units,
//! day] per goods move of the last 28 days. Places in world km.
//!
//! Events (`Grain::events_in`, `events_to_dict`): day, kind (names in
//! names, from apoleia_sim::events::NAMES), household, pid, other, amount,
//! at and to (world km).

use apoleia_sim::grain::{CraftsView, EventsView, GoodsMovesView, TripsView, WorkView, GOODS};
use godot::prelude::*;

pub fn to_dict(v: &TripsView) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("day", v.day);
    d.set("id", &PackedInt64Array::from(v.id.as_slice()));
    d.set("pid", &PackedInt64Array::from(v.pid.as_slice()));
    d.set("kind", &PackedInt32Array::from(v.kind.as_slice()));
    d.set("cargo_kg", &PackedInt64Array::from(v.cargo_kg.as_slice()));
    d.set("depart", &PackedFloat64Array::from(v.depart.as_slice()));
    d.set("arrive", &PackedFloat64Array::from(v.arrive.as_slice()));
    d.set("home", &PackedFloat64Array::from(v.home.as_slice()));
    let mut back = VarArray::new();
    for &b in &v.back {
        back.push(b);
    }
    d.set("back", &back);
    d.set("first", &PackedInt32Array::from(v.first.as_slice()));
    d.set("count", &PackedInt32Array::from(v.count.as_slice()));
    d.set("points", &PackedVector2Array::from_iter(v.points.iter().map(|&(x, z)| Vector2::new(x, z))));
    d
}

pub fn work_to_dict(v: &WorkView) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("worker", &PackedInt64Array::from(v.worker.as_slice()));
    d.set("farm_household", &PackedInt64Array::from(v.farm_household.as_slice()));
    d.set("day", &PackedInt64Array::from(v.day.as_slice()));
    d.set("days", &PackedInt64Array::from(v.days.as_slice()));
    d.set("kind", &PackedInt32Array::from(v.kind.as_slice()));
    d.set("from", &PackedVector2Array::from_iter(v.from.iter().map(|&(x, z)| Vector2::new(x, z))));
    d.set("to", &PackedVector2Array::from_iter(v.to.iter().map(|&(x, z)| Vector2::new(x, z))));
    d
}

pub fn events_to_dict(v: &EventsView) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("day", &PackedInt64Array::from(v.day.as_slice()));
    d.set("kind", &PackedInt32Array::from(v.kind.as_slice()));
    d.set("names", &PackedStringArray::from_iter(apoleia_sim::events::NAMES.iter().map(|n| GString::from(*n))));
    d.set("household", &PackedInt64Array::from(v.household.as_slice()));
    d.set("pid", &PackedInt64Array::from(v.pid.as_slice()));
    d.set("other", &PackedInt64Array::from(v.other.as_slice()));
    d.set("amount", &PackedInt64Array::from(v.amount.as_slice()));
    d.set("at", &PackedVector2Array::from_iter(v.at.iter().map(|&(x, z)| Vector2::new(x, z))));
    d.set("to", &PackedVector2Array::from_iter(v.to.iter().map(|&(x, z)| Vector2::new(x, z))));
    d
}

pub fn goods_to_dict(c: &CraftsView, markets: &[((f32, f32), [(f32, f32); GOODS])], m: &GoodsMovesView) -> VarDictionary {
    let mut d = VarDictionary::new();
    let mut crafts = Vec::with_capacity(c.craft.len() * 4);
    for k in 0..c.craft.len() {
        crafts.extend_from_slice(&[c.at[k].0, c.at[k].1, c.craft[k] as f32, c.util[k] as f32]);
    }
    let mut mk = Vec::with_capacity(markets.len() * (2 + 2 * GOODS));
    for ((x, z), goods) in markets {
        mk.extend_from_slice(&[*x, *z]);
        mk.extend(goods.iter().map(|g| g.0));
        mk.extend(goods.iter().map(|g| g.1));
    }
    let mut moves = Vec::with_capacity(m.day.len() * 7);
    for k in 0..m.day.len() {
        moves.extend_from_slice(&[m.from[k].0, m.from[k].1, m.to[k].0, m.to[k].1, m.good[k] as f32, m.units[k], m.day[k] as f32]);
    }
    d.set("crafts", &PackedFloat32Array::from(crafts.as_slice()));
    d.set("markets", &PackedFloat32Array::from(mk.as_slice()));
    d.set("moves", &PackedFloat32Array::from(moves.as_slice()));
    d
}
