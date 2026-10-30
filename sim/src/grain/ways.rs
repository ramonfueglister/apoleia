//! S127 (Ramon, 30.10.2026: „jede Strasse entsteht emergent durch das
//! Durchlaufen von Leuten“): the traders' wagons wear the ways too. A
//! wagon's route runs over the 25 km grid (`search`); on land it is laid
//! here on the fine tiles once, the cheapest way for a walker through the
//! route's cells (the land's cost from `Net::walk`), and every trip adds its
//! fine tiles to the `passed` count of the region each lies in, which that
//! market's next walk turns into wear like its farmers' trips (`walk`).
//! So the ways between the markets come from the same wear as those to
//! them, and widen where both go.

use super::*;

impl Grain {
    /// Counts a wagon of market `h` to its neighbour `k` on the fine tiles
    /// of its way over land (see the module).
    pub(super) fn wagon_wear(&mut self, h: usize, k: usize) {
        if self.region_market.len() != self.markets.len() {
            self.region_market = self.markets.iter().enumerate().map(|(m, mk)| (mk.region, m as u32)).collect();
        }
        if self.markets[h].neigh[k].fine.is_none() {
            let to = self.markets.get(self.markets[h].neigh[k].m as usize).map(|m| m.fine);
            let fine = fine_route(&self.net, self.cols_f, self.markets[h].cell, self.markets[h].fine, &self.markets[h].neigh[k].route, to, &|t| self.way_level(t));
            self.markets[h].neigh[k].fine = Some(fine);
        }
        let net = self.net.clone();
        let cols_f = self.cols_f;
        let fine = self.markets[h].neigh[k].fine.take().unwrap();
        // the neighbour a tile joins, as a bit of DIRS (none across the sea)
        let join = |a: u32, b: u32| {
            let (dr, dc) = (b as i32 / cols_f - a as i32 / cols_f, b as i32 % cols_f - a as i32 % cols_f);
            DIRS.iter().position(|&d| d == (dr, dc)).map_or(0u8, |k| 1 << k)
        };
        for (n, &t) in fine.iter().enumerate() {
            let mut joins = 0;
            if n > 0 {
                joins |= join(t, fine[n - 1]);
            }
            if n + 1 < fine.len() {
                joins |= join(t, fine[n + 1]);
            }
            let (r, c) = ((t as i32 / cols_f) / FINE + net.row0, (t as i32 % cols_f) / FINE + net.col0);
            let key = ((r.div_euclid(4) + 64) as u32) << 16 | (c.div_euclid(4) + 64) as u32;
            if let Some(&m) = self.region_market.get(&key) {
                let e = self.markets[m as usize].passed.entry(t).or_default();
                e.0 += 1;
                e.1 |= joins;
            }
        }
        self.markets[h].neigh[k].fine = Some(fine);
    }
}

impl Grain {
    /// The way level of fine tile `t` as its region's field had it at the
    /// last walk; 0 while that field is out on the path worker.
    fn way_level(&self, t: u32) -> u8 {
        let (r, c) = (t as i32 / self.cols_f, t as i32 % self.cols_f);
        let key = (((r / FINE + self.net.row0).div_euclid(4) + 64) as u32) << 16 | ((c / FINE + self.net.col0).div_euclid(4) + 64) as u32;
        let Some(f) = self.region_market.get(&key).and_then(|&m| self.markets[m as usize].field.as_ref()) else { return 0 };
        let (lr, lc) = (r - f.r0, c - f.c0);
        if lr < 0 || lc < 0 || lr >= f.n || lc >= f.n {
            return 0;
        }
        f.level[(lr * f.n + lc) as usize]
    }
}

/// The fine tiles of a wagon route over land: from the market's square
/// `from` in cell `src` through the cells of `route` (the 25 km route
/// without `src`), each stretch of land walked by the cheapest way over the
/// fine tiles of its cells only; a stretch starts and ends at a market
/// square (`to` at the route's end) or, by the sea, in the middle of its
/// port cell. The tiles in walking order, without repeats at the joins.
fn fine_route(net: &Net, cols_f: i32, src: u32, from: u32, route: &[u32], to: Option<u32>, level: &dyn Fn(u32) -> u8) -> Vec<u32> {
    let mut cells = Vec::with_capacity(route.len() + 1);
    cells.push(src);
    cells.extend_from_slice(route);
    let centre = |c: u32| ((c as i32 / net.cols * FINE + FINE / 2) * cols_f + c as i32 % net.cols * FINE + FINE / 2) as u32;
    let mut out = Vec::new();
    let mut i = 0;
    while i < cells.len() {
        if net.kind[cells[i] as usize] == 0 {
            i += 1;
            continue;
        }
        let mut j = i;
        while j + 1 < cells.len() && net.kind[cells[j + 1] as usize] != 0 {
            j += 1;
        }
        let a = if i == 0 { from } else { centre(cells[i]) };
        let b = match to {
            Some(t) if j + 1 == cells.len() => t,
            _ => centre(cells[j]),
        };
        if j > i || a != b {
            let run: Vec<u32> = cells[i..=j].to_vec();
            out.extend(walk_between(net, cols_f, &run, a, b, level));
        }
        i = j + 1;
    }
    out
}

/// The cheapest walk from fine tile `a` to `b` over the fine tiles of the
/// 25 km cells `run` (Dijkstra, eight neighbours, the land's walking cost,
/// quicker on a way already worn, `level`, as the farmers' walks);
/// empty if `b` cannot be reached.
fn walk_between(net: &Net, cols_f: i32, run: &[u32], a: u32, b: u32, level: &dyn Fn(u32) -> u8) -> Vec<u32> {
    let inside = |t: u32| {
        let c = ((t as i32 / cols_f) / FINE * net.cols + (t as i32 % cols_f) / FINE) as u32;
        run.contains(&c)
    };
    let ground = |t: u32| net.walk.get(t as usize).map_or(WALK_ONE, |&g| g as i64);
    let mut best: FxHashMap<u32, (i64, u32)> = FxHashMap::default();
    let mut open = BinaryHeap::new();
    best.insert(a, (0, a));
    open.push(Reverse((0i64, a)));
    while let Some(Reverse((d, t))) = open.pop() {
        if d > best[&t].0 {
            continue;
        }
        if t == b {
            break;
        }
        let (r, c) = (t as i32 / cols_f, t as i32 % cols_f);
        for (dr, dc) in DIRS {
            let (nr, nc) = (r + dr, c + dc);
            if nr < 0 || nc < 0 || nc >= cols_f || nr >= net.rows * FINE {
                continue;
            }
            let n = (nr * cols_f + nc) as u32;
            if !inside(n) {
                continue;
            }
            let g = ground(n);
            if g == 0 && n != b {
                continue;
            }
            let step = if dr != 0 && dc != 0 { 141 } else { FINE_STEP } * g.max(1) * PATH_COST_PCT[level(n).min(7) as usize] / WALK_ONE / 100;
            let nd = d + step.max(1);
            if best.get(&n).is_none_or(|&(old, _)| nd < old) {
                best.insert(n, (nd, t));
                open.push(Reverse((nd, n)));
            }
        }
    }
    if !best.contains_key(&b) {
        return Vec::new();
    }
    let mut path = vec![b];
    let mut t = b;
    while t != a {
        t = best[&t].1;
        path.push(t);
    }
    path.reverse();
    path
}
