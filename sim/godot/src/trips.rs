//! The trips under way (apoleia_sim::grain::TripsView) as a Godot
//! dictionary, for the carriers and wagons walking on the map. Built on the
//! sim thread between two days (`Grain::trips_in`), handed over like
//! `take_person`.
//!
//! Dictionary: day, and one entry per trip in id (stable while the trip
//! lasts), pid, kind (0 sale, 1 purchase, 2 export, 3 import), cargo_kg,
//! depart, arrive, home (days), back (turns home the same day), first and
//! count (its route in points), points (world km, home to destination).

use apoleia_sim::grain::TripsView;
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
