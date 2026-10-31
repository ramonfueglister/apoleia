//! TEST (local only): lists the morph targets in head.bin with how many vertices each moves
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../app/assets/portrait/head.bin.zst");
    let h = apoleia_portrait::Head::load(&std::fs::read(root).unwrap()).unwrap();
    let mut v: Vec<(&String, usize)> = h.targets.iter().map(|(k, t)| (k, t.ids.len())).collect();
    v.sort();
    for (k, n) in v {
        println!("{k} {n}");
    }
}
