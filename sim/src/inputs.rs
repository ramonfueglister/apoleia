//! Reads the start grid and the per-cell inputs from the repository
//! (data/gametiles/tiles.csv, sim/inputs/*.csv from tools/sim_inputs.py and
//! tools/sim_hyde.py). Shared by the command-line runner and the Godot bridge.

use crate::{Cell, City, Hyde, Key};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

pub struct Inputs {
    pub start: Vec<Key>,
    pub cells: HashMap<(i32, i32), Cell>,
    pub cities: Vec<City>,
    /// Display name of each city (data/gametiles/places.csv), by index.
    pub city_names: Vec<String>,
    /// True when HYDE 3.3 values were found and used.
    pub hyde: bool,
}

fn read_csv(path: &Path) -> Result<Vec<HashMap<String, String>>, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut lines = text.lines();
    let header: Vec<String> = lines.next().unwrap_or("").split(',').map(str::to_owned).collect();
    Ok(lines
        .filter(|l| !l.is_empty())
        .map(|l| header.iter().cloned().zip(l.split(',').map(str::to_owned)).collect())
        .collect())
}

fn num(row: &HashMap<String, String>, key: &str) -> f64 {
    row.get(key).and_then(|v| v.parse().ok()).unwrap_or(0.0)
}

/// Loads everything below `root` (the repository root). With `estimates`,
/// hyde25.csv is ignored even if present.
pub fn load(root: &Path, estimates: bool) -> Result<Inputs, String> {
    let start = read_csv(&root.join("data/gametiles/tiles.csv"))?
        .iter()
        .map(|r| Key::parse(&r["id"]).ok_or_else(|| format!("bad tile id {}", r["id"])))
        .collect::<Result<Vec<Key>, String>>()?;
    let mut cells: HashMap<(i32, i32), Cell> = read_csv(&root.join("sim/inputs/cells25.csv"))?
        .iter()
        .map(|r| {
            let rc = (num(r, "row") as i32, num(r, "col") as i32);
            let cell = Cell {
                land_km2: num(r, "land_km2"),
                frac_bare: num(r, "frac_bare"),
                frac_snow: num(r, "frac_snow"),
                frac_above_1500m: num(r, "frac_above_1500m"),
                hyde: None,
            };
            (rc, cell)
        })
        .collect();
    // Real data replaces the estimates when tools/sim_hyde.py has been run.
    let hyde_path = root.join("sim/inputs/hyde25.csv");
    let hyde = hyde_path.exists() && !estimates;
    if hyde {
        for r in read_csv(&hyde_path)? {
            let rc = (num(&r, "row") as i32, num(&r, "col") as i32);
            if let Some(cell) = cells.get_mut(&rc) {
                let rural = r.get("rural200").and_then(|v| v.parse().ok());
                cell.hyde = Some(Hyde { crop_km2: num(&r, "crop_km2"), pop: num(&r, "pop200"), rural });
            }
        }
    }
    let rows = read_csv(&root.join("sim/inputs/cities.csv"))?;
    let cities = rows.iter().map(|r| City { x_m: num(r, "x_m"), z_m: num(r, "z_m"), pop: num(r, "pop117") }).collect();
    let names = place_names(&root.join("data/gametiles/places.csv"));
    let city_names = rows.iter().map(|r| r.get("id").map(|id| names.get(id).cloned().unwrap_or_else(|| id.clone())).unwrap_or_default()).collect();
    Ok(Inputs { start, cells, cities, city_names, hyde })
}

/// id → name from places.csv (the name may be quoted and hold commas).
/// Missing file: no names.
fn place_names(path: &Path) -> HashMap<String, String> {
    let Ok(text) = fs::read_to_string(path) else { return HashMap::new() };
    text.lines()
        .skip(1)
        .filter_map(|l| {
            let (id, rest) = l.split_once(',')?;
            let name = match rest.strip_prefix('"') {
                Some(q) => q.split_once('"')?.0,
                None => rest.split(',').next()?,
            };
            Some((id.to_owned(), name.to_owned()))
        })
        .collect()
}
