//! TEST (local only): per head.bin vertex the base position and the lip and
//! nose masks; and the faceted beard of each style as OBJ (for the Blender
//! beards).
use apoleia_portrait::look::{default_life, Beard, Hat, Look, Mood, NG};
use apoleia_portrait::{build, Head};
use std::fmt::Write;
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let head = Head::load(&std::fs::read(root).unwrap()).unwrap();
    let mut s = String::new();
    for i in 0..head.n {
        let b = head.base[i];
        let _ = writeln!(s, "{} {} {} {} {}", b[0], b[1], b[2], head.lip[i], head.nose[i]);
    }
    std::fs::write("/home/claude/work/blhair/masks.txt", s).unwrap();
    let mut r = apoleia_portrait::geo::Rng::new(77);
    let genes: [f32; NG] = std::array::from_fn(|_| (r.next() * 255.0 + r.next() * 255.0) / 2.0);
    for (nm, bd) in [("short", Beard::Short), ("full", Beard::Full), ("phil", Beard::Philosopher), ("chin", Beard::Chin), ("shaven", Beard::Shaven)] {
        let look = Look { genes, female: false, age: 35.0, stand: 2, east: false, seed: 77, mood: Mood::Neutral, life: default_life(2, 35.0, 77), beard: Some(bd), hair: None, hat: Some(Hat::None), jewel: None };
        let p = build(&head, &look, 3);
        let mut obj = String::new();
        let mut base = 1;
        for (i, sf) in p.surfaces.iter().enumerate() {
            let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
            for v in &sf.pos { for a in 0..3 { lo[a] = lo[a].min(v[a]); hi[a] = hi[a].max(v[a]); } }
            eprintln!("{nm} {i}: tex={:?} n={} lo={lo:.2?} hi={hi:.2?}", sf.tex, sf.pos.len());
            let _ = writeln!(obj, "o s{i}");
            for v in &sf.pos { let _ = writeln!(obj, "v {} {} {}", v[0], v[1], v[2]); }
            for t in 0..sf.pos.len() / 3 { let _ = writeln!(obj, "f {} {} {}", base + 3 * t, base + 3 * t + 1, base + 3 * t + 2); }
            base += sf.pos.len();
        }
        std::fs::write(format!("/home/claude/work/blhair/beard_{nm}_dump.obj"), obj).unwrap();
    }
}
