//! The overview tables (apoleia_sim::tables) as Godot dictionaries, for the
//! EU5-style lists in the game. Built on the sim thread between two days
//! (`Grain::table`), handed over like `take_person`.
//!
//! Dictionary: kind, name, day (simulation day of the build), columns
//! (keys of the shown columns, in order), labels and units (one per shown
//! column; "%" = share 0..1, a key with "mean" = mean per person), and data
//! (key → PackedInt64Array, PackedFloat64Array or PackedStringArray) with
//! every column, the hidden ones (id, lon, lat, extent_km) included.

use apoleia_sim::tables::{Table, Values};
use godot::prelude::*;

pub fn to_dict(t: &Table) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("kind", t.key);
    d.set("name", t.name);
    d.set("day", t.day);
    let shown: Vec<_> = t.columns.iter().filter(|c| !c.hidden).collect();
    d.set("columns", &PackedStringArray::from_iter(shown.iter().map(|c| GString::from(c.key))));
    d.set("labels", &PackedStringArray::from_iter(shown.iter().map(|c| GString::from(c.name))));
    d.set("units", &PackedStringArray::from_iter(shown.iter().map(|c| GString::from(c.unit))));
    let mut data = VarDictionary::new();
    for c in &t.columns {
        match &c.values {
            Values::Int(v) => data.set(c.key, &PackedInt64Array::from(v.as_slice())),
            Values::Float(v) => data.set(c.key, &PackedFloat64Array::from(v.as_slice())),
            Values::Text(v) => data.set(c.key, &PackedStringArray::from_iter(v.iter().map(GString::from))),
        }
    }
    d.set("data", &data);
    d
}
