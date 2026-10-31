//! Time of build() in the simple and the real look (app/assets/portrait/real):
//! `cargo run --release --example real_time` (MODES=einfach,echt picks).
use apoleia_portrait::look::{default_life, Hat, Look, Mood, NG};
use apoleia_portrait::{build, Head};
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let head = Head::load(&std::fs::read(root).unwrap()).unwrap();
    let real = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/real").canonicalize().unwrap();
    let looks: Vec<Look> = (0..16u32)
        .map(|i| {
            let mut r = apoleia_portrait::geo::Rng::new(100 + i);
            let genes: [f32; NG] = std::array::from_fn(|_| (r.next() * 255.0 + r.next() * 255.0) / 2.0);
            let fem = i % 2 == 1;
            let age = [8.0, 25.0, 40.0, 62.0][(i / 2 % 4) as usize];
            let stand = (i % 4) as usize;
            Look { genes, female: fem, age, stand, east: false, seed: i * 7919, mood: Mood::Neutral, life: default_life(stand, age, i), beard: None, hair: None, hat: Some(Hat::None), jewel: None }
        })
        .collect();
    let modes: Vec<String> = std::env::var("MODES").map(|m| m.split(",").map(String::from).collect()).unwrap_or(vec!["einfach".into(), "echt".into(), "echt 2".into()]);
    for mode in modes.iter().map(|s| s.as_str()) {
        apoleia_portrait::real::set_real(if mode == "einfach" { None } else { Some(real.to_string_lossy().into()) });
        let t = std::time::Instant::now();
        for l in &looks {
            let _ = build(&head, l, 1);
        }
        println!("{mode}: {:.1} ms je Gesicht", t.elapsed().as_secs_f64() * 1000.0 / looks.len() as f64);
    }
}
