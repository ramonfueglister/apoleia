//! The real look (Ramon, 31.10.2026: "ins Spiel bringen, mit Schalter"):
//! hair, beards and clothes draped in Blender, textured skin and eyes,
//! the face space with its origin shifts. On when `set_real` names the
//! folder of its files (app/assets/portrait/real, built by the realism
//! pipeline, /mnt/project-files/portraits/realismus-pipeline); off, the
//! portraits stay as they were. For test renders each part can still be
//! switched on alone by its environment variable (APOLEIA_REAL,
//! APOLEIA_MH_DIR, APOLEIA_FACE_MODULES, ...), which wins.
//!
//! Images are WebP (or PNG), the bigger data files zstd-packed (.txt.zst).

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

static REAL: RwLock<Option<String>> = RwLock::new(None);

/// Switches the real look on (the folder of its files) or off (None).
pub fn set_real(dir: Option<String>) {
    if let Ok(mut r) = REAL.write() {
        *r = dir.filter(|d| !d.is_empty());
    }
    if let Ok(mut t) = ROWS.write() {
        *t = None;
    }
}

/// The folder of the real look's files, when it is on.
pub fn folder() -> Option<String> {
    REAL.read().ok().and_then(|r| r.clone())
}

/// A folder setting: its environment variable, else the real look's folder.
pub fn dir(var: &str) -> Option<String> {
    std::env::var(var).ok().or_else(folder)
}

/// A switch: its environment variable, else whether the real look is on.
pub fn on(var: &str) -> bool {
    std::env::var_os(var).is_some() || folder().is_some()
}

/// A data file as text, packed (path.zst) or not.
pub fn read_text(path: &str) -> Option<String> {
    std::fs::read_to_string(path).ok().or_else(|| {
        let bytes = std::fs::read(format!("{path}.zst")).ok()?;
        String::from_utf8(zstd::decode_all(bytes.as_slice()).ok()?).ok()
    })
}

/// The data files parsed so far: each line its numbers (a token that is no
/// number reads 0), kept so that a face does not read, unpack and parse
/// them again; dropped when the look is switched.
static ROWS: RwLock<Option<HashMap<String, Option<Arc<Vec<Vec<f32>>>>>>> = RwLock::new(None);

/// Each line of a data file as numbers, parsed once and kept.
pub fn rows(path: &str) -> Option<Arc<Vec<Vec<f32>>>> {
    if let Some(r) = ROWS.read().ok().and_then(|m| m.as_ref().and_then(|m| m.get(path).cloned())) {
        return r;
    }
    let r = read_text(path).map(|t| Arc::new(t.lines().map(|l| l.split_whitespace().map(|x| x.parse().unwrap_or(0.0)).collect()).collect::<Vec<Vec<f32>>>()));
    if let Ok(mut m) = ROWS.write() {
        m.get_or_insert_with(HashMap::new).insert(path.to_string(), r.clone());
    }
    r
}

/// A data file of one number a line (`default` where a line has none).
pub fn column(path: &str, default: f32) -> Vec<f32> {
    rows(path).map(|r| r.iter().map(|l| l.first().copied().unwrap_or(default)).collect()).unwrap_or_default()
}

/// Whether a data file is there, packed or not.
pub fn exists(path: &str) -> bool {
    std::path::Path::new(path).exists() || std::path::Path::new(&format!("{path}.zst")).exists()
}

/// The image `name` in `dir`: WebP if there is one, else PNG.
pub fn image(dir: &str, name: &str) -> String {
    let webp = format!("{dir}/{name}.webp");
    if std::path::Path::new(&webp).exists() {
        webp
    } else {
        format!("{dir}/{name}.png")
    }
}

/// The normal map beside an image (name_n), if there is one.
pub fn normal_map(image: &str) -> Option<String> {
    let (stem, ext) = image.rsplit_once('.')?;
    let n = format!("{stem}_n.{ext}");
    std::path::Path::new(&n).exists().then_some(n)
}
