//! TEST tool (local): zstd-packs each file named on the command line to file.zst (level 19).
fn main() {
    for f in std::env::args().skip(1) {
        let b = std::fs::read(&f).unwrap();
        let z = zstd::encode_all(b.as_slice(), 19).unwrap();
        std::fs::write(format!("{f}.zst"), z).unwrap();
    }
}
