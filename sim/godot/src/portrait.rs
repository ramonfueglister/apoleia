//! Portraits for the person window (docs/kit2/PORTRAITS.md): the genes of a
//! person (apoleia_sim::dna) and what the simulation knows of their life
//! become a Look, apoleia_portrait builds its triangles, and this class
//! hands them to Godot as an ArrayMesh with one material per surface.
//! app/scripts/ui/portrait_view.gd lights and frames it.

use apoleia_portrait::look::{Look, Mood, BAUER, DECURIO, HAENDLER, HANDWERKER, SENATOR, SKLAVE, STANDS};
use apoleia_portrait::geo::srgb;
use apoleia_portrait::{build, Head, Life, NG};
use apoleia_sim::dna::{self, ORIGINS};
use apoleia_sim::events::{DEATH, HUNGER_DEATH, KEEP_DAYS};
use apoleia_sim::people::People;
use apoleia_sim::view::Person;
use godot::classes::base_material_3d::{CullMode, Flags};
use godot::classes::mesh::{ArrayType, PrimitiveType};
use godot::classes::{ArrayMesh, StandardMaterial3D};
use godot::prelude::*;
use std::sync::OnceLock;
use xxhash_rust::xxh3::xxh3_64;

/// The head, loaded once per run (app/assets/portrait/head.bin.zst).
static HEAD: OnceLock<Head> = OnceLock::new();

/// Which of the Werkstatt's seven looks a person of the simulation wears:
/// the upper stands by stand, everyone else by occupation. PLACEHOLDER
/// (open): soldiers and officers dress as craftsmen until there is armour,
/// clerks, scholars, priests and nobles below the upper stands as traders.
pub fn look_stand(stand: u8, job: &str) -> usize {
    match (stand, job) {
        (3, _) => SENATOR,
        (2, _) => DECURIO,
        (_, "Unfreie") => SKLAVE,
        (_, "Bauern" | "Pächter") => BAUER,
        (0, "Tagelöhner") => BAUER,
        (_, "Tagelöhner" | "Handwerker" | "Soldaten" | "Offiziere") => HANDWERKER,
        (_, "Händler" | "Unternehmer" | "Beamte" | "Gelehrte" | "Geistliche" | "Adel") => HAENDLER,
        (0, _) => BAUER,
        _ => HANDWERKER,
    }
}

/// Share of the working day spent outdoors by occupation (tan and
/// wrinkles). PLACEHOLDER (unsourced).
fn outdoors(job: &str) -> f32 {
    match job {
        "Bauern" | "Pächter" => 0.85,
        "Tagelöhner" | "Unfreie" => 0.8,
        "Soldaten" => 0.75,
        "Offiziere" => 0.5,
        "Handwerker" => 0.45,
        "Händler" => 0.4,
        "Unternehmer" | "Adel" => 0.3,
        "Beamte" | "Geistliche" => 0.2,
        "Gelehrte" => 0.15,
        _ => 0.4,
    }
}

/// Chance of one or two scars after 16. PLACEHOLDER (unsourced; the
/// simulation has no injuries).
fn scar_chance(job: &str) -> f32 {
    match job {
        "Soldaten" => 0.5,
        "Unfreie" => 0.45,
        "Offiziere" => 0.4,
        "Handwerker" => 0.35,
        "Bauern" | "Pächter" | "Tagelöhner" => 0.3,
        _ => 0.12,
    }
}

/// Days of full mourning after a death in the household; it fades out by
/// KEEP_DAYS, the days the simulation keeps its events. PLACEHOLDER: Roman
/// custom kept mourning for up to ten months for a husband or a parent
/// (Plutarch, Numa 12), longer than the events reach back.
const MOURN_FULL_DAYS: f32 = 20.0;

/// What the simulation knows of a person's days beyond body and job: days
/// since the last death in the household (None without one in KEEP_DAYS),
/// the share of the people around with less money per head (0..1, None
/// without a household), clothing held of the need in per cent.
#[derive(Clone, Copy, Default)]
pub struct Lived {
    pub loss_days: Option<f32>,
    pub rank: Option<f32>,
    pub clothes_pct: Option<f32>,
}

/// The face's life from the simulation: food from body weight (S84: 1000 ‰
/// is normal, hunger starts to show below about 935 ‰), the share outdoors
/// from the occupation, scars by chance per occupation, no illness (the
/// simulation has none yet); mourning after a death in the household,
/// wealth as the rank by money, clothes worn out as far as the household
/// lacks clothing.
fn life_of(job: &str, age: f32, weight_permille: f32, seed: u32, lived: Lived) -> Life {
    let mut r = apoleia_portrait::geo::Rng::new(seed ^ 0x27d4_eb2f);
    let food = (0.55 + (weight_permille - 1000.0) / 500.0).clamp(0.0, 1.0);
    let sun = (outdoors(job) + (r.next() - 0.5) * 0.3).clamp(0.0, 1.0) * if age < 8.0 { 0.4 } else { 1.0 };
    let scars = if age > 16.0 && r.next() < scar_chance(job) { 1 + (r.next() * 2.0) as u32 } else { 0 };
    let mourn = lived.loss_days.map_or(0.0, |d| ((KEEP_DAYS as f32 - d) / (KEEP_DAYS as f32 - MOURN_FULL_DAYS)).clamp(0.0, 1.0));
    let wealth = lived.rank.unwrap_or(0.5).clamp(0.0, 1.0);
    let worn = lived.clothes_pct.map_or(0.0, |c| (1.0 - c / 100.0).clamp(0.0, 1.0));
    Life { food, sun, scars, ill: 0.0, mourn, wealth, worn }
}

/// The Look of a person of the simulation.
#[allow(clippy::too_many_arguments)]
pub fn look_of(genes: &[u8], female: bool, age: f32, stand: u8, job: &str, weight: f32, fed: f32, pid: u32, origin: &str, lived: Lived) -> Look {
    let seed = (xxh3_64(&pid.to_le_bytes()) & 0x3fff_ffff) as u32;
    let g: [f32; NG] = std::array::from_fn(|i| (genes[i] as f32 + genes[NG + i] as f32) / 2.0);
    let st = look_stand(stand, job);
    let life = life_of(job, age, weight, seed, lived);
    // mourners look sad, hungry households grim; otherwise most look calm,
    // some content
    let mood = if life.mourn > 0.3 {
        Mood::Sad
    } else if fed < 900.0 {
        Mood::Grim
    } else if seed % 3 == 0 {
        Mood::Content
    } else {
        Mood::Neutral
    };
    Look {
        genes: g,
        female,
        age,
        stand: st,
        east: matches!(origin, "Graecia" | "Syria" | "Aegyptus"),
        seed,
        mood,
        life,
        beard: None,
        hair: None,
        hat: None,
        jewel: None,
    }
}

/// The colours go to Godot in sRGB with SRGB_VERTEX_COLOR set: linear
/// vertex colours come out darker and redder in the Compatibility renderer
/// (it does not convert them, Forward+ does), and sRGB keeps the dark tones
/// apart in the eight bits per channel Godot stores.
fn material(m: apoleia_portrait::Mat) -> Gd<StandardMaterial3D> {
    let mut s = StandardMaterial3D::new_gd();
    s.set_flag(Flags::ALBEDO_FROM_VERTEX_COLOR, true);
    s.set_flag(Flags::SRGB_VERTEX_COLOR, true);
    s.set_roughness(m.rough);
    s.set_metallic(m.metal);
    if m.double {
        s.set_cull_mode(CullMode::DISABLED);
    }
    s
}

#[derive(GodotClass)]
#[class(init, base = RefCounted)]
pub struct ApoleiaPortrait {}

#[godot_api]
impl ApoleiaPortrait {
    /// Loads the head from the bytes of head.bin.zst, once per run; true
    /// when it is ready.
    #[func]
    fn load(&mut self, packed: PackedByteArray) -> bool {
        if HEAD.get().is_some() {
            return true;
        }
        match Head::load(packed.as_slice()) {
            Ok(h) => {
                let _ = HEAD.set(h);
                true
            }
            Err(e) => {
                godot_error!("portrait: {}", e.0);
                false
            }
        }
    }

    #[func]
    fn is_loaded(&self) -> bool {
        HEAD.get().is_some()
    }

    /// The portrait of a person as take_person describes them ("dna",
    /// "female", "age", "stand", "job", "health", "pid", and when known
    /// "fed", "origin", "loss_days", "rank_market" or "rank_all",
    /// "clothes_pct"): {"mesh": ArrayMesh, "top", "chin", "cx", "cz",
    /// "fill" (the frame), "tris", "bg": [inner, outer] background colours
    /// of the look's stand, "look": the stand's name}; empty without genes
    /// or head. `lod` 0..3.
    #[func]
    fn build(&self, person: VarDictionary, lod: i64) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(head) = HEAD.get() else { return d };
        let Some(dna) = person.get("dna").and_then(|v| v.try_to::<PackedByteArray>().ok()) else { return d };
        let genes = dna.as_slice();
        if genes.len() != 2 * NG {
            return d;
        }
        let num = |k: &str| person.get(k).and_then(|v| v.try_to_relaxed::<f64>().ok());
        let text = |k: &str| person.get(k).and_then(|v| v.try_to::<GString>().ok()).map_or(String::new(), |s| s.to_string());
        let female = person.get("female").and_then(|v| v.try_to_relaxed::<bool>().ok()).unwrap_or(false);
        let lived = Lived {
            loss_days: num("loss_days").map(|v| v as f32),
            rank: if person.contains_key("market") { num("rank_market") } else { num("rank_all") }.map(|v| v as f32),
            clothes_pct: num("clothes_pct").map(|v| v as f32),
        };
        let stand = num("stand").unwrap_or(0.0).clamp(0.0, 3.0) as u8;
        let look = look_of(genes, female, num("age").unwrap_or(30.0) as f32, stand, &text("job"), num("health").unwrap_or(1000.0) as f32, num("fed").unwrap_or(1000.0) as f32, num("pid").unwrap_or(0.0) as u32, &text("origin"), lived);
        let p = build(head, &look, lod.clamp(0, 3) as usize);
        let mut mesh = ArrayMesh::new_gd();
        for s in &p.surfaces {
            // Godot's front faces wind clockwise: swap each triangle's last two
            let n = s.pos.len();
            let mut verts = Vec::with_capacity(n);
            let mut norms = Vec::with_capacity(n);
            let mut cols = Vec::with_capacity(n);
            for t in (0..n).step_by(3) {
                let (a, b, c) = (s.pos[t], s.pos[t + 1], s.pos[t + 2]);
                let u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
                let v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
                let nn = Vector3::new(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]).normalized_or_zero();
                for k in [0, 2, 1] {
                    let q = s.pos[t + k];
                    let col = srgb(s.col[t + k]);
                    verts.push(Vector3::new(q[0], q[1], q[2]));
                    norms.push(nn);
                    cols.push(Color::from_rgb(col[0], col[1], col[2]));
                }
            }
            let mut arrays = VarArray::new();
            arrays.resize(ArrayType::MAX.ord() as usize, &Variant::nil());
            arrays.set(ArrayType::VERTEX.ord() as usize, &PackedVector3Array::from(verts.as_slice()).to_variant());
            arrays.set(ArrayType::NORMAL.ord() as usize, &PackedVector3Array::from(norms.as_slice()).to_variant());
            arrays.set(ArrayType::COLOR.ord() as usize, &PackedColorArray::from(cols.as_slice()).to_variant());
            mesh.add_surface_from_arrays(PrimitiveType::TRIANGLES, &arrays);
            let i = mesh.get_surface_count() - 1;
            mesh.surface_set_material(i, &material(s.mat));
        }
        let st = &STANDS[look.stand];
        d.set("mesh", &mesh);
        d.set("top", p.top);
        d.set("chin", p.chin);
        d.set("cx", p.cx);
        d.set("cz", p.cz);
        d.set("fill", p.fill);
        d.set("tris", p.tris as i64);
        let bg: VarArray = st
            .bg
            .iter()
            .map(|h| {
                let c = apoleia_portrait::geo::hex(h);
                Color::from_rgb(c[0], c[1], c[2]).to_variant()
            })
            .collect();
        d.set("bg", &bg);
        d.set("look", st.key);
        d
    }
}

/// What take_person tells of a person for the portrait, read on the sim
/// thread: the genes with the origin (crate::dna::ORIGINS) by the home cell,
/// and the last death in the household the events still know: (days ago,
/// of hunger, age in years; 0 for hunger deaths).
#[derive(Default)]
pub struct Face {
    pub genes: Option<(dna::Dna, u8)>,
    pub loss: Option<(i64, bool, i64)>,
}

impl Face {
    pub fn of(people: &People, p: &Person, today: i64) -> Face {
        let genes = people.dna(p.pid).map(|g| {
            let (lon, lat) = dna::lon_lat_of(&people.grid, p.home);
            (g, dna::origin(lon, lat))
        });
        let loss = people
            .events
            .iter()
            .rev()
            .find(|e| e.household == p.household && e.pid != p.pid && (e.kind == DEATH || e.kind == HUNGER_DEATH))
            .map(|e| (today - e.day, e.kind == HUNGER_DEATH, e.amount));
        Face { genes, loss }
    }

    /// Into take_person's answer: "dna" (68 bytes), "origin", and with a
    /// death "loss_days", "loss_hunger", "loss_age".
    pub fn put(&self, d: &mut VarDictionary) {
        if let Some((g, origin)) = self.genes {
            d.set("dna", &PackedByteArray::from(&g.bytes()[..]));
            d.set("origin", ORIGINS[origin as usize]);
        }
        if let Some((days, hunger, age)) = self.loss {
            d.set("loss_days", days);
            d.set("loss_hunger", hunger);
            d.set("loss_age", age);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_gene_lists_agree() {
        assert_eq!(apoleia_portrait::GENES, dna::GENES);
        assert_eq!(apoleia_portrait::NG, dna::NG);
    }

    #[test]
    fn every_job_has_a_look() {
        for job in apoleia_sim::groups::JOB_NAMES {
            for stand in 0..4 {
                assert!(look_stand(stand, job) < STANDS.len());
            }
        }
        assert_eq!(look_stand(0, "Unfreie"), SKLAVE);
        assert_eq!(look_stand(3, "Adel"), SENATOR);
    }
}
