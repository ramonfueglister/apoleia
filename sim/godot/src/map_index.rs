//! Tile index for the map modes, kept up to date incrementally.
//!
//! Every tile owns a stable slot: its row in the value texture. A split or
//! merge frees the slots of the removed tiles and gives the new tiles free
//! slots, so the other tiles keep their slot and their cells stay untouched.
//! The index (slot + 1 per finest cell, 0 = no tile) is cut into square
//! pages, one layer of a texture array each; after a structure change only
//! the pages under removed or added tiles are uploaded again, the page idea
//! of virtual texturing (Barrett, 2008; van Waveren, 2009).

use apoleia_sim::ecs::Snapshot;
use apoleia_sim::{Key, MAX_LEVEL};
use rustc_hash::FxHashMap;

/// Edge of one index page in cells (one texture array layer).
pub const PAGE: usize = 256;

pub struct MapIndex {
    /// Finest-level grid covering all tiles: origin column/row and size.
    pub grid: (i64, i64, usize, usize),
    pub pages_x: usize,
    pub pages_y: usize,
    /// Slot + 1 per grid cell, row-major (0 = no tile).
    cells: Vec<u32>,
    slots: FxHashMap<Key, u32>,
    free: Vec<u32>,
    slot_count: u32,
    /// Snapshot tile per slot (`u32::MAX` = free), and slot per snapshot tile.
    tile_of_slot: Vec<u32>,
    slot_of_tile: Vec<u32>,
    dirty: Vec<bool>,
    /// Snapshot structure the slots and cells belong to.
    pub structure: Option<u64>,
}

impl MapIndex {
    /// Sizes the grid to the tiles of the first snapshot of a game.
    pub fn new(snap: &Snapshot) -> Self {
        let (mut c0, mut r0, mut c1, mut r1) = (i64::MAX, i64::MAX, i64::MIN, i64::MIN);
        for t in &snap.tiles {
            let (c, r, s) = span(t.key);
            c0 = c0.min(c);
            r0 = r0.min(r);
            c1 = c1.max(c + s);
            r1 = r1.max(r + s);
        }
        if snap.tiles.is_empty() {
            (c0, r0, c1, r1) = (0, 0, 1, 1);
        }
        let (w, h) = ((c1 - c0) as usize, (r1 - r0) as usize);
        let (pages_x, pages_y) = (w.div_ceil(PAGE), h.div_ceil(PAGE));
        MapIndex {
            grid: (c0, r0, w, h),
            pages_x,
            pages_y,
            cells: vec![0; w * h],
            slots: FxHashMap::default(),
            free: Vec::new(),
            slot_count: 0,
            tile_of_slot: Vec::new(),
            slot_of_tile: Vec::new(),
            dirty: vec![false; pages_x * pages_y],
            structure: None,
        }
    }

    pub fn layers(&self) -> usize {
        self.pages_x * self.pages_y
    }

    pub fn slot_count(&self) -> usize {
        self.slot_count as usize
    }

    /// Brings slots and cells to the snapshot's structure (no-op otherwise).
    pub fn sync(&mut self, snap: &Snapshot) {
        if self.structure == Some(snap.structure) {
            return;
        }
        let mut alive = vec![false; self.slot_count as usize];
        let mut added = Vec::new();
        self.slot_of_tile.clear();
        for (i, t) in snap.tiles.iter().enumerate() {
            match self.slots.get(&t.key) {
                Some(&s) => {
                    alive[s as usize] = true;
                    self.slot_of_tile.push(s);
                }
                None => {
                    added.push(i);
                    self.slot_of_tile.push(u32::MAX);
                }
            }
        }
        // Clear removed tiles first: their area is not always covered again
        // (a child without land is never spawned), and a freed slot may go
        // to a tile elsewhere.
        let mut removed = Vec::new();
        self.slots.retain(|&k, &mut s| {
            let keep = alive[s as usize];
            if !keep {
                removed.push((k, s));
            }
            keep
        });
        for (k, s) in removed {
            self.paint(k, 0);
            self.free.push(s);
        }
        for i in added {
            let key = snap.tiles[i].key;
            let s = self.free.pop().unwrap_or_else(|| {
                self.slot_count += 1;
                self.slot_count - 1
            });
            self.slots.insert(key, s);
            self.slot_of_tile[i] = s;
            self.paint(key, s + 1);
        }
        self.tile_of_slot.clear();
        self.tile_of_slot.resize(self.slot_count as usize, u32::MAX);
        for (i, &s) in self.slot_of_tile.iter().enumerate() {
            self.tile_of_slot[s as usize] = i as u32;
        }
        self.structure = Some(snap.structure);
    }

    fn paint(&mut self, key: Key, v: u32) {
        let (c0, r0, w, h) = self.grid;
        let (c, r, s) = span(key);
        let (c, r) = (c - c0, r - r0);
        // Tiles outside the start grid (none today) are not shown.
        let (x0, x1) = (c.max(0) as usize, ((c + s).max(0) as usize).min(w));
        let (y0, y1) = (r.max(0) as usize, ((r + s).max(0) as usize).min(h));
        if x0 >= x1 || y0 >= y1 {
            return;
        }
        for y in y0..y1 {
            self.cells[y * w + x0..y * w + x1].fill(v);
        }
        for py in y0 / PAGE..=(y1 - 1) / PAGE {
            for px in x0 / PAGE..=(x1 - 1) / PAGE {
                self.dirty[py * self.pages_x + px] = true;
            }
        }
    }

    /// Pages changed since the last call; clears the list.
    pub fn take_dirty(&mut self) -> Vec<i32> {
        let out = (0..self.dirty.len()).filter(|&i| self.dirty[i]).map(|i| i as i32).collect();
        self.dirty.fill(false);
        out
    }

    /// One page as little-endian f32 values (exact up to 2^24 slots),
    /// zero-padded at the grid edge.
    pub fn page_bytes(&self, layer: usize, out: &mut [u8]) {
        let (_, _, w, h) = self.grid;
        let (px, py) = (layer % self.pages_x, layer / self.pages_x);
        out.fill(0);
        for y in 0..PAGE {
            let gy = py * PAGE + y;
            if gy >= h {
                break;
            }
            let gx0 = px * PAGE;
            let n = PAGE.min(w.saturating_sub(gx0));
            let row = &self.cells[gy * w + gx0..][..n];
            for (dst, &v) in out[y * PAGE * 4..].chunks_exact_mut(4).zip(row) {
                dst.copy_from_slice(&(v as f32).to_le_bytes());
            }
        }
    }

    /// Slot per snapshot tile (valid after `sync`).
    pub fn slot_of_tile(&self) -> &[u32] {
        &self.slot_of_tile
    }

    /// The snapshot tile at a grid cell, if any.
    pub fn tile_at_cell(&self, c: i64, r: i64) -> Option<usize> {
        let (_, _, w, h) = self.grid;
        if c < 0 || r < 0 || c as usize >= w || r as usize >= h {
            return None;
        }
        let s = self.cells[r as usize * w + c as usize].checked_sub(1)?;
        match self.tile_of_slot.get(s as usize) {
            Some(&t) if t != u32::MAX => Some(t as usize),
            _ => None,
        }
    }
}

/// A tile's cell column, row and edge length on the finest grid.
fn span(key: Key) -> (i64, i64, i64) {
    let s = 1i64 << (MAX_LEVEL - key.level);
    (key.col as i64 * s, key.row as i64 * s, s)
}

#[cfg(test)]
mod tests {
    use super::*;
    use apoleia_sim::ecs::TileView;

    fn snap(structure: u64, keys: &[Key]) -> Snapshot {
        Snapshot {
            month: 0,
            structure,
            tiles: keys.iter().map(|&key| TileView { key, pop: 0.0, cap: 0.0, land_km2: 1.0, moved: 0.0 }).collect(),
        }
    }

    /// The index after any sequence of syncs equals one built from scratch,
    /// and only pages under changed tiles are reported dirty.
    #[test]
    fn incremental_equals_rebuild_and_marks_only_changed_pages() {
        let top = MAX_LEVEL - 3; // 8 cells per tile edge, 4×4 tiles
        let level = |l: u8, r: i32, c: i32| Key::new(l, r, c);
        let start: Vec<Key> = (0..4).flat_map(|r| (0..4).map(move |c| level(top, r, c))).collect();
        let mut m = MapIndex::new(&snap(0, &start));
        m.sync(&snap(0, &start));
        assert_eq!(m.take_dirty(), vec![0], "one page holds the 32×32 grid");
        // Split tile (1,1) into four children; drop one child (no land).
        let mut next: Vec<Key> = start.iter().copied().filter(|&k| k != level(top, 1, 1)).collect();
        next.extend([level(top + 1, 2, 2), level(top + 1, 2, 3), level(top + 1, 3, 2)]);
        next.reverse(); // storage order changes too
        m.sync(&snap(1, &next));
        let mut fresh = MapIndex::new(&snap(0, &start));
        fresh.sync(&snap(1, &next));
        for r in 0..32 {
            for c in 0..32 {
                let a = m.tile_at_cell(c, r).map(|i| next[i]);
                let b = fresh.tile_at_cell(c, r).map(|i| next[i]);
                assert_eq!(a, b, "cell ({c},{r})");
            }
        }
        // The dropped child's cells are empty, the untouched tiles kept their slot.
        assert_eq!(m.tile_at_cell(12, 12), None);
        assert_eq!(m.slot_count(), 16 + 2, "freed slot reused");
        assert_eq!(m.take_dirty(), vec![0]);
        assert!(m.take_dirty().is_empty());
    }

    #[test]
    fn pages_cover_the_grid_and_pad_with_zero() {
        // Three roots of 128 cells in a row: 384×128 cells, 2×1 pages.
        let keys: Vec<Key> = (0..3).map(|c| Key::new(0, 0, c)).collect();
        let mut m = MapIndex::new(&snap(0, &keys));
        m.sync(&snap(0, &keys));
        assert_eq!((m.pages_x, m.pages_y, m.layers()), (2, 1, 2));
        let mut page = vec![0u8; PAGE * PAGE * 4];
        m.page_bytes(1, &mut page);
        let at = |x: usize, y: usize| f32::from_le_bytes(page[(y * PAGE + x) * 4..][..4].try_into().unwrap()) as u32;
        assert_eq!(at(0, 0), m.slot_of_tile()[2] + 1);
        assert_eq!(at(127, 127), m.slot_of_tile()[2] + 1);
        assert_eq!((at(128, 0), at(0, 128)), (0, 0), "padding outside the grid");
    }
}
