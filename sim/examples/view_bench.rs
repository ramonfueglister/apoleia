//! Cost of the dots view per sim day: cargo run --release --example view_bench
use apoleia_sim::{people::People, view::PeopleView};
use std::time::Instant;
fn main() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let inp = apoleia_sim::inputs::load(&root, false).unwrap();
    let mut p = People::new(&inp, 1);
    let mut v = PeopleView::new(&p, &inp.cities);
    v.update(&mut p);
    let (mut us, mut pages, mut w) = (Vec::new(), Vec::new(), Vec::new());
    for _ in 0..360 {
        p.day();
        let t = Instant::now();
        let d = v.update(&mut p);
        us.push(t.elapsed().as_secs_f64() * 1e6);
        pages.push(d.len()); w.push(v.last_writes);
    }
    us.sort_by(f64::total_cmp);
    pages.sort(); w.sort(); println!("writes median={} p95={}", w[180], w[342]);
    println!("people={} pages={} view_us median={:.0} p95={:.0} max={:.0} dirty_pages median={} p95={} max={}",
        p.count, v.pages(), us[180], us[342], us[359], pages[180], pages[342], pages[359]);
}
