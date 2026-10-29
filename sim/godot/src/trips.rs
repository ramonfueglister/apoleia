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
//! Events (`Grain::events_in`, `events_to_dict`): day, kind (names in
//! names, from apoleia_sim::events::NAMES), household, pid, other, amount,
//! at and to (world km).

use apoleia_sim::grain::{EventsView, TripsView, WorkView};
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
