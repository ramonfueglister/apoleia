//! Builds a few test people and writes them as JSON, each with its person
//! (genes, sex, age, stand, …, in the Portrait-Werkstatt's terms) and its
//! portrait's triangles, so that a page with the Werkstatt can draw both
//! side by side (docs/kit2/PORTRAITS.md, "Compare with the Werkstatt").
//!
//!   cargo run --release -p apoleia-portrait --example portrait_dump -- out.json [lod] [kids]
//!
//! With `kids`, children from half a year to fourteen instead, as boy and
//! girl, under the stands' own choices of hair, clothes and jewellery.

use apoleia_portrait::look::{Beard, Hair, Hat, Jewel, Life, Look, Mood, NG, STANDS};
use apoleia_portrait::{build, Head};
use std::fmt::Write;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let out = args.get(1).cloned().unwrap_or_else(|| "portraits.json".into());
    let lod: usize = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1);
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let head = Head::load(&std::fs::read(root).expect("head file")).expect("head");
    use Beard::*;
    #[rustfmt::skip]
    let people: Vec<(bool, f32, usize, Option<Beard>, Option<Hair>, Option<Hat>, Option<Jewel>, Life, Mood, bool)> = vec![
        (false, 48.0, 1, Some(Full), None, Some(Hat::Petasos), None, Life { food: 0.3, sun: 0.9, scars: 1, ill: 0.0, ..Life::default() }, Mood::Grim, false),
        (false, 62.0, 5, Some(Philosopher), None, Some(Hat::None), None, Life { food: 0.7, sun: 0.1, scars: 0, ill: 0.0, ..Life::default() }, Mood::Neutral, true),
        (true, 32.0, 4, None, Some(Hair::Braid), Some(Hat::None), Some(Jewel::Chain), Life { food: 0.65, sun: 0.2, scars: 0, ill: 0.0, ..Life::default() }, Mood::Content, false),
        (true, 26.0, 3, None, Some(Hair::Veil), Some(Hat::None), Some(Jewel::Earrings), Life { food: 0.6, sun: 0.4, scars: 0, ill: 0.5, ..Life::default() }, Mood::Neutral, true),
        (false, 35.0, 6, Some(Short), None, None, None, Life { food: 0.75, sun: 0.1, scars: 0, ill: 0.0, ..Life::default() }, Mood::Neutral, false),
        (true, 9.0, 1, None, Some(Hair::Bun), None, None, Life { food: 0.5, sun: 0.4, scars: 0, ill: 0.0, ..Life::default() }, Mood::Content, false),
        (false, 22.0, 2, Some(Chin), None, Some(Hat::Pileus), None, Life { food: 0.55, sun: 0.45, scars: 2, ill: 0.0, ..Life::default() }, Mood::Neutral, false),
        (false, 40.0, 0, Some(Stubble), None, Some(Hat::Cap), None, Life { food: 0.35, sun: 0.8, scars: 1, ill: 0.0, ..Life::default() }, Mood::Sad, false),
    ];
    let kids = args.get(3).is_some_and(|a| a == "kids");
    let people = if !kids {
        people
    } else {
        let life = Life { food: 0.6, sun: 0.3, scars: 0, ill: 0.0, ..Life::default() };
        [0.5, 1.5, 3.0, 5.0, 8.0, 11.0, 14.0]
            .iter()
            .enumerate()
            .flat_map(|(k, &age)| [false, true].map(|female| (female, age, [1, 2, 4, 1, 5, 2, 3][k], None, None, None, None, life, if k % 3 == 0 { Mood::Content } else { Mood::Neutral }, k == 4)))
            .collect()
    };
    let mut js = String::from("[");
    for (k, &(female, age, stand, beard, hair, hat, jewel, life, mood, east)) in people.iter().enumerate() {
        let seed = 7919 * (k as u32 + 1) + 13;
        let mut r = apoleia_portrait::geo::Rng::new(seed);
        let (mut a, mut b) = ([0u8; NG], [0u8; NG]);
        for i in 0..NG {
            a[i] = (r.next() * 255.0) as u8;
            b[i] = (r.next() * 255.0) as u8;
        }
        let genes = std::array::from_fn(|i| (a[i] as f32 + b[i] as f32) / 2.0);
        let look = Look { genes, female, age, stand, east, seed, mood, life, beard, hair, hat, jewel };
        let t0 = std::time::Instant::now();
        let p = build(&head, &look, lod);
        let ms = t0.elapsed().as_secs_f64() * 1e3;
        eprintln!("person {k}: {} triangles, {} targets, {ms:.1} ms", p.tris, p.targets);
        let name = |v: &str| format!("\"{v}\"");
        let beard_s = beard.map_or("null".into(), |b| name(match b { Shaven => "glatt", Stubble => "stoppeln", Short => "kurz", Full => "voll", Philosopher => "philosoph", Chin => "kinnbart" }));
        let hair_s = hair.map_or("null".into(), |h| name(match h { Hair::Braid => "zopf", Hair::Bun => "knoten", Hair::Veil => "schleier" }));
        let hat_s = hat.map_or("null".into(), |h| name(match h { Hat::None => "keine", Hat::Cap => "kappe", Hat::Pileus => "pileus", Hat::Petasos => "petasos", Hat::Wreath => "kranz", Hat::Diadem => "diadem" }));
        let jw_s = jewel.map_or("null".into(), |j| name(match j { Jewel::None => "keiner", Jewel::Earrings => "ohrringe", Jewel::Chain => "kette", Jewel::Pearls => "perlen" }));
        let mood_s = match mood { Mood::Neutral => "neutral", Mood::Content => "zufrieden", Mood::Grim => "grimmig", Mood::Sad => "traurig" };
        let _ = write!(
            js,
            "{}{{\"person\":{{\"a\":{:?},\"b\":{:?},\"sex\":\"{}\",\"age\":{age},\"stand\":\"{}\",\"region\":\"{}\",\"seed\":{seed},\"mood\":\"{mood_s}\",\"life\":{{\"food\":{},\"sun\":{},\"scars\":{},\"ill\":{}}},\"beard\":{beard_s},\"hair\":{hair_s},\"hw\":{hat_s},\"jw\":{jw_s}}},",
            if k > 0 { "," } else { "" },
            a,
            b,
            if female { "w" } else { "m" },
            STANDS[stand].key,
            if east { "Syria" } else { "Italia" },
            life.food,
            life.sun,
            life.scars,
            life.ill
        );
        let _ = write!(js, "\"top\":{},\"chin\":{},\"cx\":{},\"cz\":{},\"fill\":{},\"tris\":{},\"ms\":{ms:.1},\"surfaces\":[", p.top, p.chin, p.cx, p.cz, p.fill, p.tris);
        for (i, s) in p.surfaces.iter().enumerate() {
            let _ = write!(js, "{}{{\"rough\":{},\"metal\":{},\"double\":{},\"pos\":[", if i > 0 { "," } else { "" }, s.mat.rough, s.mat.metal, s.mat.double);
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
}
