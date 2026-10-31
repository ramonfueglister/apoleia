//! A contact sheet of headwear and hair: the same few people under every
//! hat, every women's hairstyle, and men's hair from straight to curly and
//! bald, written as JSON (label, frame and triangles per portrait) for a
//! quick look without the game.
//!
//!   cargo run --release -p apoleia-portrait --example portrait_sheet -- out.json [hats|hair|men|kids] [lod]

use apoleia_portrait::look::{default_life, Beard, Hair, Hat, Look, Mood, BALD, CURL, NG};
use apoleia_portrait::{build, Head};
use std::fmt::Write;

fn genes(seed: u32) -> [f32; NG] {
    let mut r = apoleia_portrait::geo::Rng::new(seed);
    std::array::from_fn(|_| (r.next() * 255.0 + r.next() * 255.0) / 2.0)
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let out = args.get(1).cloned().unwrap_or_else(|| "sheet.json".into());
    let set = args.get(2).map_or("hats", |s| s.as_str());
    let lod = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(1);
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let head = Head::load(&std::fs::read(root).expect("head file")).expect("head");
    let person = |female: bool, age: f32, stand: usize, seed: u32| Look {
        genes: genes(seed),
        female,
        age,
        stand,
        east: false,
        seed,
        mood: Mood::Neutral,
        life: default_life(stand, age, seed),
        beard: None,
        hair: None,
        hat: Some(Hat::None),
        jewel: None,
    };
    let mut looks: Vec<(String, Look)> = Vec::new();
    match set {
        "hats" => {
            for (k, hat) in [Hat::Petasos, Hat::Pileus, Hat::Cap, Hat::Wreath].into_iter().enumerate() {
                for (j, (age, beard)) in [(28.0, Beard::Short), (55.0, Beard::Full), (65.0, Beard::Shaven)].into_iter().enumerate() {
                    let mut p = person(false, age, [1, 0, 4, 6][k], 101 + 17 * (k * 3 + j) as u32);
                    p.hat = Some(hat);
                    p.beard = Some(beard);
                    looks.push((format!("{hat:?} {age}"), p));
                }
            }
            for (j, hair) in [Hair::Bun, Hair::Braid, Hair::Veil].into_iter().enumerate() {
                let mut p = person(true, 30.0, 6, 501 + 13 * j as u32);
                p.hat = Some(Hat::Diadem);
                p.hair = Some(hair);
                looks.push((format!("Diadem {hair:?}"), p));
            }
        }
        "hair" => {
            for (k, hair) in [Hair::Bun, Hair::Braid, Hair::Veil].into_iter().enumerate() {
                for (j, age) in [18.0, 35.0, 60.0].into_iter().enumerate() {
                    let mut p = person(true, age, [2, 4, 1][j], 701 + 19 * (k * 3 + j) as u32);
                    p.hair = Some(hair);
                    looks.push((format!("{hair:?} {age}"), p));
                }
            }
        }
        "kids" => {
            for (k, age) in [0.5, 1.5, 3.0, 5.0, 8.0, 11.0, 14.0].into_iter().enumerate() {
                for female in [false, true] {
                    let p = person(female, age, [1, 2, 4, 1, 5, 2, 3][k], 1201 + 29 * k as u32 + female as u32);
                    looks.push((format!("{} {age}", if female { "girl" } else { "boy" }), p));
                }
            }
        }
        _ => {
            for (k, (curl, bald)) in [(10.0, 0.0), (120.0, 0.0), (230.0, 0.0), (60.0, 170.0), (60.0, 250.0)].into_iter().enumerate() {
                for (j, (age, beard)) in [(20.0, Beard::Shaven), (40.0, Beard::Short), (62.0, Beard::Full)].into_iter().enumerate() {
                    let mut p = person(false, age, 2, 901 + 23 * (k * 3 + j) as u32);
                    p.genes[CURL] = curl;
                    p.genes[BALD] = bald;
                    p.beard = Some(beard);
                    looks.push((format!("curl {curl} bald {bald} {age}"), p));
                }
            }
        }
    }
    let mut js = String::from("[");
    for (k, (label, look)) in looks.iter().enumerate() {
        let p = build(&head, look, lod);
        let _ = write!(js, "{}{{\"label\":\"{label}\",\"top\":{},\"chin\":{},\"cx\":{},\"cz\":{},\"fill\":{},\"tris\":{},\"surfaces\":[", if k > 0 { "," } else { "" }, p.top, p.chin, p.cx, p.cz, p.fill, p.tris);
        for (i, s) in p.surfaces.iter().enumerate() {
            let _ = write!(js, "{}{{\"double\":{},\"metal\":{},\"pos\":[", if i > 0 { "," } else { "" }, s.mat.double, s.mat.metal);
            for (j, v) in s.pos.iter().enumerate() {
                let _ = write!(js, "{}{:.4},{:.4},{:.4}", if j > 0 { "," } else { "" }, v[0], v[1], v[2]);
            }
            js.push_str("],\"col\":[");
            for (j, c) in s.col.iter().enumerate() {
                let _ = write!(js, "{}{:.4},{:.4},{:.4}", if j > 0 { "," } else { "" }, c[0], c[1], c[2]);
            }
            js.push_str("]}");
        }
        js.push_str("]}");
    }
    js.push(']');
    std::fs::write(&out, js).expect("write");
    eprintln!("{} portraits -> {out}", looks.len());
}
