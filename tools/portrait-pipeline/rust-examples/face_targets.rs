//! TEST (local only): print the face-space target sums of one person.
//! GENES="68 alleles comma separated", FEMALE=1, AGE=32
use apoleia_portrait::look::{default_life, Hat, Look, Mood, NG};
use apoleia_portrait::{morph_test, Head};
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let head = Head::load(&std::fs::read(root).unwrap()).unwrap();
    let a: Vec<f32> = std::env::var("GENES").unwrap().split(',').map(|t| t.trim().parse().unwrap()).collect();
    let genes: [f32; NG] = std::array::from_fn(|i| (a[i] + a[NG + i]) / 2.0);
    let fem = std::env::var_os("FEMALE").is_some();
    let age: f32 = std::env::var("AGE").ok().and_then(|v| v.parse().ok()).unwrap_or(32.0);
    let look = Look { genes, female: fem, age, stand: 1, east: false, seed: 1, mood: Mood::Neutral, life: default_life(1, age, 1), beard: None, hair: None, hat: Some(Hat::None), jewel: None };
    let _ = morph_test(&head, &look);
}
