//! Facial measurements (Farkas landmarks, mm) over many
//! random founders, to compare the faces' spread with real people's.
//! usage: face_measure [n] [age] ; FEMALE=1 for women; prints mean, sd, cv
use apoleia_portrait::look::{default_life, Look, Mood, NG};
use apoleia_portrait::{morph_test, Head};
type V3 = [f32; 3];
fn around_middle(r: &mut apoleia_portrait::geo::Rng) -> f32 {
    let s: f32 = (0..4).map(|_| (r.next() * 256.0).floor().min(255.0)).sum();
    (128.0 + (s - 510.0) * 48.0 * 1.22 / 255.0).clamp(0.0, 255.0)
}
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let h = Head::load(&std::fs::read(root).unwrap()).unwrap();
    let args: Vec<String> = std::env::args().collect();
    let n: usize = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(400);
    let age: f32 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(35.0);
    let fem = std::env::var_os("FEMALE").is_some();
    let b = &h.base;
    let body: Vec<usize> = {
        let mut v: Vec<usize> = h.parts["body"][0].iter().map(|&i| i as usize).collect();
        v.sort();
        v.dedup();
        v
    };
    let pick = |f: &dyn Fn(&V3) -> bool, key: &dyn Fn(&V3) -> f32| -> usize {
        *body.iter().filter(|&&i| f(&b[i])).max_by(|&&a, &&c| key(&b[a]).partial_cmp(&key(&b[c])).unwrap()).unwrap()
    };
    let most_dx = |t: &str| -> usize {
        let t = &h.targets[t];
        let (j, _) = t.ids.iter().enumerate().filter(|(_, &i)| b[i as usize][0] > 0.0).max_by_key(|(j, _)| t.d[*j][0].abs() as i32).unwrap();
        t.ids[j] as usize
    };
    let prn = pick(&|v| v[0].abs() < 0.03 && v[1] > 6.5, &|v| v[2]);
    let nas = pick(&|v| v[0].abs() < 0.03 && v[1] > 7.1 && v[1] < 7.5 && v[2] > 1.1, &|v| -v[2]);
    let men = pick(&|v| v[0].abs() < 0.03 && v[2] > 0.8 && v[1] < 6.4 && v[1] > 5.9, &|v| -v[1]);
    let sn = pick(&|v| v[0].abs() < 0.03 && v[1] > 6.6 && v[1] < b[prn][1] && v[2] > 1.3, &|v| -v[2]);
    let pog = pick(&|v| v[0].abs() < 0.03 && v[1] > 6.1 && v[1] < 6.45 && v[2] > 1.0, &|v| v[2]);
    let al = most_dx("nose/nose-scale-horiz-incr");
    let ch = most_dx("mouth/mouth-scale-horiz-incr");
    let zy = pick(&|v| v[0] > 0.0 && v[1] > 6.95 && v[1] < 7.2 && v[2] > 0.85 && v[2] < 1.25, &|v| v[0]);
    let go = if std::env::var_os("GO_OLD").is_some() { pick(&|v| v[0] > 0.0 && v[1] > 6.3 && v[1] < 6.55 && v[2] > 0.3 && v[2] < 0.9, &|v| v[0]) } else { most_dx("chin/chin-bones-incr") };
    eprintln!("chin-width most dx {:?}", b[most_dx("chin/chin-width-incr")]);
    let mirror = |i: usize| -> usize {
        let t = [-b[i][0], b[i][1], b[i][2]];
        *body.iter().min_by(|&&a, &&c| {
            let da = (b[a][0] - t[0]).powi(2) + (b[a][1] - t[1]).powi(2) + (b[a][2] - t[2]).powi(2);
            let dc = (b[c][0] - t[0]).powi(2) + (b[c][1] - t[1]).powi(2) + (b[c][2] - t[2]).powi(2);
            da.partial_cmp(&dc).unwrap()
        }).unwrap()
    };
    let (al2, ch2, zy2, go2) = (mirror(al), mirror(ch), mirror(zy), mirror(go));
    let eye = |k: &str| -> Vec<usize> { let mut v: Vec<usize> = h.parts[k][0].iter().map(|&i| i as usize).collect(); v.sort(); v.dedup(); v };
    let (le, re) = (eye("leye"), eye("reye"));
    eprintln!("landmarks prn {:?} n {:?} me {:?} sn {:?} pog {:?} al {:?} ch {:?} zy {:?} go {:?}", b[prn], b[nas], b[men], b[sn], b[pog], b[al], b[ch], b[zy], b[go]);
    let names = ["zy-zy face width", "go-go jaw width", "n-me face height", "sn-me lower face", "al-al nose width", "n-sn nose height", "sn-prn nose tip", "ch-ch mouth width", "pupils", "pog-sn chin fwd"];
    let mut rows: Vec<Vec<f32>> = vec![Vec::new(); names.len()];
    let d = |p: &[V3], a: usize, c: usize| ((p[a][0] - p[c][0]).powi(2) + (p[a][1] - p[c][1]).powi(2) + (p[a][2] - p[c][2]).powi(2)).sqrt() * 100.0;
    let meas = |p: &[V3]| -> Vec<f32> {
        vec![d(p, zy, zy2), d(p, go, go2), d(p, nas, men), d(p, sn, men), d(p, al, al2), d(p, nas, sn), (p[prn][2] - p[sn][2]) * 100.0, d(p, ch, ch2)]
    };
    if let Ok(list) = std::env::var("SENS") {
        // change of each measure (mm) for weight 1 of each listed target
        let m0 = meas(b);
        for t in list.split(',') {
            let Some(tg) = h.targets.get(t) else { println!("{t} missing"); continue };
            let mut p = b.clone();
            for (j, &i) in tg.ids.iter().enumerate() {
                for a in 0..3 { p[i as usize][a] += tg.d[j][a] as f32 * apoleia_portrait::head::DELTA_SCALE; }
            }
            let m = meas(&p);
            println!("{t:40} {}", m.iter().zip(&m0).map(|(a, c)| format!("{:6.1}", a - c)).collect::<Vec<_>>().join(" "));
        }
        return;
    }
    // ORIGIN=0..6: founders of that origin (typA/B/C ranges as sim/src/dna.rs
    // RANGES), FACE_SHIFT="headW:10,noseW:-5" moves face genes as the
    // founders' shift table would
    let origin: Option<usize> = std::env::var("ORIGIN").ok().and_then(|v| v.parse().ok());
    const TYP: [[(f32, f32); 3]; 7] = [
        [(0.0, 50.0), (0.0, 40.0), (170.0, 255.0)],
        [(0.0, 20.0), (0.0, 30.0), (210.0, 255.0)],
        [(0.0, 15.0), (0.0, 30.0), (220.0, 255.0)],
        [(0.0, 50.0), (0.0, 50.0), (170.0, 255.0)],
        [(0.0, 60.0), (20.0, 100.0), (140.0, 230.0)],
        [(60.0, 170.0), (0.0, 60.0), (90.0, 200.0)],
        [(120.0, 255.0), (0.0, 30.0), (30.0, 140.0)],
    ];
    let shift: Vec<f32> = {
        let mut v = vec![0f32; NG];
        if let Ok(t) = std::env::var("FACE_SHIFT") {
            for kv in t.split(',').filter(|x| !x.is_empty()) {
                let (k, x) = kv.split_once(':').unwrap();
                let i = apoleia_portrait::GENES.iter().position(|g| *g == k).unwrap_or_else(|| panic!("gene {k}"));
                v[i] = x.parse().unwrap();
            }
        }
        v
    };
    if std::env::var_os("GENE_SENS").is_some() {
        // mm per allele unit (both alleles moved) of each face gene, around the middle
        let o = origin.unwrap_or(0);
        for k in 0..21 {
            let at = |x: f32| {
                let mut genes = [128.0f32; NG];
                for t in 0..3 {
                    genes[23 + t] = (TYP[o][t].0 + TYP[o][t].1) / 2.0;
                }
                genes[k] = 128.0 + x;
                let look = Look { genes, female: fem, age, stand: 1, east: false, seed: 1, mood: Mood::Neutral, life: default_life(1, age, 1), beard: None, hair: None, hat: None, jewel: None };
                meas(&morph_test(&h, &look))
            };
            let (a, c) = (at(-48.0), at(48.0));
            println!("{:8} {}", apoleia_portrait::GENES[k], a.iter().zip(&c).map(|(x, y)| format!("{:7.4}", (y - x) / 96.0)).collect::<Vec<_>>().join(" "));
        }
        return;
    }
    let mut r = apoleia_portrait::geo::Rng::new(4242);
    let d = |p: &[V3], a: usize, c: usize| ((p[a][0] - p[c][0]).powi(2) + (p[a][1] - p[c][1]).powi(2) + (p[a][2] - p[c][2]).powi(2)).sqrt() * 100.0;
    for k in 0..n {
        let mut genes = [128.0f32; NG];
        for (i, g) in genes.iter_mut().enumerate() {
            *g = match origin {
                Some(o) if (23..=25).contains(&i) => {
                    let (lo, hi) = TYP[o][i - 23];
                    (lo + r.next() * (hi - lo) + lo + r.next() * (hi - lo)) / 2.0
                }
                None if (23..=25).contains(&i) => [40.0, 20.0, 220.0][i - 23],
                _ => ((around_middle(&mut r) + shift[i]).clamp(0.0, 255.0) + (around_middle(&mut r) + shift[i]).clamp(0.0, 255.0)) / 2.0,
            };
        }
        let seed = 1000 + k as u32;
        let look = Look { genes, female: fem, age, stand: 1, east: false, seed, mood: Mood::Neutral, life: default_life(1, age, seed), beard: None, hair: None, hat: None, jewel: None };
        let p = morph_test(&h, &look);
        let c = |v: &[usize]| { let mut s = [0f32; 3]; for &i in v { for a in 0..3 { s[a] += p[i][a]; } } [s[0] / v.len() as f32, s[1] / v.len() as f32, s[2] / v.len() as f32] };
        let (lc, rc) = (c(&le), c(&re));
        let vals = [d(&p, zy, zy2), d(&p, go, go2), d(&p, nas, men), d(&p, sn, men), d(&p, al, al2), d(&p, nas, sn), (p[prn][2] - p[sn][2]) * 100.0, d(&p, ch, ch2),
            ((lc[0] - rc[0]).powi(2) + (lc[1] - rc[1]).powi(2) + (lc[2] - rc[2]).powi(2)).sqrt() * 100.0, (p[pog][2] - p[sn][2]) * 100.0];
        for (j, v) in vals.iter().enumerate() {
            rows[j].push(*v);
        }
    }
    let means: Vec<String> = rows.iter().map(|r| format!("{:.3}", r.iter().sum::<f32>() / n as f32)).collect();
    println!("MEANS {}", means.join(" "));
    for (j, nm) in names.iter().enumerate() {
        let m = rows[j].iter().sum::<f32>() / n as f32;
        let sd = (rows[j].iter().map(|v| (v - m).powi(2)).sum::<f32>() / (n as f32 - 1.0)).sqrt();
        println!("{nm:20} mean {m:6.1} mm  sd {sd:5.2}  cv {:4.1} %", 100.0 * sd / m.abs());
    }
}
