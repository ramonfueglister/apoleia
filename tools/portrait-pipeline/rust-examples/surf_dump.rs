//! TEST (local only): list a man's surfaces (texture, vertices, bounds) and
//! write the textured ones as OBJ with uv.
use apoleia_portrait::look::{default_life, Hat, Look, Mood, NG};
use apoleia_portrait::{build, Head};
use std::fmt::Write;
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let head = Head::load(&std::fs::read(root).unwrap()).unwrap();
    let mut r = apoleia_portrait::geo::Rng::new(77);
    let genes: [f32; NG] = std::array::from_fn(|_| (r.next() * 255.0 + r.next() * 255.0) / 2.0);
    let fem = std::env::var_os("DUMP_FEMALE").is_some();
    let stand: usize = std::env::var("DUMP_STAND").ok().and_then(|s| s.parse().ok()).unwrap_or(2);
    let look = Look { genes, female: fem, age: 30.0, stand, east: false, seed: 77, mood: match std::env::var("DUMP_MOOD").as_deref() { Ok("sad") => Mood::Sad, Ok("grim") => Mood::Grim, Ok("content") => Mood::Content, _ => Mood::Neutral }, life: default_life(stand, 30.0, 77), beard: None, hair: if fem { Some(apoleia_portrait::look::Hair::Bun) } else { None }, hat: Some(Hat::None), jewel: None };
    let p = build(&head, &look, 3);
    let mut obj = String::new();
    let mut base = 1;
    for (i, s) in p.surfaces.iter().enumerate() {
        let (mut lo, mut hi) = ([f32::MAX; 3], [f32::MIN; 3]);
        for v in &s.pos { for a in 0..3 { lo[a] = lo[a].min(v[a]); hi[a] = hi[a].max(v[a]); } }
        eprintln!("{i}: tex={:?} n={} uv={} lo={lo:.2?} hi={hi:.2?}", s.tex, s.pos.len(), s.uv.len());
        let _ = writeln!(obj, "o s{i}");
        for v in &s.pos { let _ = writeln!(obj, "v {} {} {}", v[0], v[1], v[2]); }
        for t in 0..s.pos.len() / 3 { let _ = writeln!(obj, "f {} {} {}", base + 3 * t, base + 3 * t + 1, base + 3 * t + 2); }
        base += s.pos.len();
    }
    std::fs::write("/home/claude/work/blhair/dump.obj", obj).unwrap();
}
