//! TEST (local only): left/right symmetry of a target: the biggest moves on each side
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let h = apoleia_portrait::Head::load(&std::fs::read(root).unwrap()).unwrap();
    for name in std::env::args().skip(1) {
        let Some(t) = h.targets.get(&name) else { println!("{name}: none"); continue };
        let mut side = [(0f32, [0f32; 3], [0f32; 3]); 2];
        for (j, &i) in t.ids.iter().enumerate() {
            let d = t.d[j];
            let d = [d[0] as f32 / 3000.0, d[1] as f32 / 3000.0, d[2] as f32 / 3000.0];
            let m = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
            let b = h.base[i as usize];
            let s = if b[0] > 0.0 { 0 } else { 1 };
            if m > side[s].0 { side[s] = (m, d, b); }
        }
        println!("{name}: +x max {:.3} d={:.3?} at {:.2?} | -x max {:.3} d={:.3?} at {:.2?}", side[0].0, side[0].1, side[0].2, side[1].0, side[1].1, side[1].2);
    }
}
