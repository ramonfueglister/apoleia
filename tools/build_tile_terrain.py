#!/usr/bin/env python3
"""Bake the data textures of the tile terrain (SimCity 2000 meets EU5 look).

Status: implementiert. Inputs (all in Git): the fixed 2 km height grid
(fixed-source-v2-mountain-r7), WorldCover land cover at the same nodes, the
Natural Earth coast/lake/river layers plus the Europe supplements and the
117 AD places. Output: artifacts/render-data/tile-terrain-r1/

  cover.png        RGBA8 at the 2 km nodes: forest, dry (bare + shrub), crop, wetland
  aux.png          RGBA8 at the 2 km nodes: sea distance (2 km steps), lake level
                   (uint16 metres + 1000 in G/B), A unused
  cells-L{n}.png   per zoom level n (cell = 0.5 km * 2^n): two cells per byte,
                   each nibble = water class (bits 0-1: 0 land, 1 sea, 2 lake,
                   3 river) | settlement density (bits 2-3: 0 none .. 3 core)
  height.r16f      little-endian float16 metres at the 2 km nodes (Godot FORMAT_RH)
  relief.r16f      the same heights, slope limited to RELIEF_SLOPE m/km (SimCity 2000
                   rule, see sc2k_relief); the terrain shape is built from this
  shore.r16f       highest the land may stand next to the water (sea 0 m, lakes at
                   their level, same slope); caps the blurred relief at the shores
  levels-L{n}.png  for the far zoom levels (n >= BAKED_FROM): the height level of
                   every tile corner (8 bit), built by corner_levels(); up close the
                   shader builds the corners from relief.r16f itself
  ground-L{n}.png  per zoom level: the landscape of every tile (GROUND, one colour
                   each), two tiles per byte like cells-L{n}.png; 15 = water
  manifest.json    grid definitions and hashes

    python3 tools/build_tile_terrain.py
    python3 tools/build_tile_terrain.py --levels-only   # only levels-L*.png, from the outputs above
    python3 tools/build_tile_terrain.py --ground-only   # only ground-L*.png
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
RD = ROOT / "artifacts" / "render-data"
OUT = RD / "tile-terrain-r1"
GRID_W, GRID_H = 5163, 2392
WORLD_MIN = (-5286.959516530886, -2223.9016046706583)
WORLD_SIZE = (10322.15905608411, 4781.388450041915)
R_KM = 6371.0088
BASE_CELL_KM = 0.5
LEVELS = 6  # 0.5, 1, 2, 4, 8, 16 km
# Natural Earth scalerank shown per level (more rivers up close)
RIVER_RANK = [10, 10, 8, 7, 6, 5]
# Natural Earth ranks rivers for today's maps; the rivers of Rome rank higher
ROMAN_RIVER_RANK = {"Tevere": 5, "Arno": 7}
SS = 2  # supersampling of the polygon raster
# Diorama heights: one documented factor for the whole world, SimCity 2000
# style (Kit 1 K06 as changed 27.10.2026). A height level is
# LEVEL_HEIGHT of the tile on screen (SimCity 2000 ratio, app/scripts/
# tile_terrain.gd), so it stands for RELIEF_SLOPE * tile_km real metres, and the
# relief is limited to that slope: neighbouring tile corners never differ by
# more than one level.
HEIGHT_EXAGGERATION = 3.75
LEVEL_HEIGHT = 0.6
RELIEF_SLOPE = 1000.0 * LEVEL_HEIGHT / HEIGHT_EXAGGERATION  # m per km
# Optional steeper slope in high mountains (blended in between these heights
# of the 10 km mean). Kept at the one-level rule (SimCity 2000, Kit 1 K06).
MOUNTAIN_SLOPE = 1.0 * RELIEF_SLOPE
MOUNTAIN_FROM_M = 500.0
MOUNTAIN_TO_M = 1300.0
# Far zoom levels (2 km tiles and up) get their corner levels from the bake
# (corner_levels), so the tiles follow SimCity 2000 rules there too, on a
# rising scale: LEVEL_STEPS_M are the heights where the count reaches 0, 1,
# 2, ... levels (800 m per level above the last), the land height blurred
# over CORNER_BLUR tiles first. Plains stay one flat level, hills get 2, the
# Apennines a ridge of 3 to 4 and the Alps 5 to 7 (equal steps either drew a
# maze of thin terraces in the hills or left the Apennines one flat step).
# The shader mirrors the scale (tt_far_level_x); the app draws far steps
# taller (LEVEL_HEIGHTS).
BAKED_FROM = 2
LEVEL_STEPS_M = [100.0, 250.0, 450.0, 700.0, 1000.0, 1400.0, 1900.0, 2500.0, 3200.0]
CORNER_BLUR = 1.2


def far_level_x(metres):
    """Height in far levels (unrounded) on the LEVEL_STEPS_M scale."""
    steps = np.array(LEVEL_STEPS_M)
    m = np.asarray(metres, np.float64)
    x = np.interp(m, steps, np.arange(len(steps), dtype=np.float64))
    return np.where(m > steps[-1], len(steps) - 1 + (m - steps[-1]) / 800.0, x)
# Landscape of a tile, one colour each (Ramon, 28.10.2026: one colour per
# tile, two where landscapes meet; the shader splits those at the diagonal).
GROUND = ["meadow", "dry_grass", "field", "wetland", "scrub", "sand", "forest", "conifer",
          "alpine", "rock", "snow"]
G = {name: k for k, name in enumerate(GROUND)}
NO_GROUND = 15  # sea and lakes
NODE_KM = WORLD_SIZE[0] / (GRID_W - 1)


def lonlat_to_world(lon, lat):
    x = R_KM * math.cos(math.radians(41)) * np.radians(np.asarray(lon, float) - 19)
    z = -R_KM * np.radians(np.asarray(lat, float) - 41)
    return x, z


def load_features(path, lines=False):
    out = []
    for f in json.loads(Path(path).read_text())["features"]:
        g = f["geometry"]
        if g is None:
            continue
        if lines:
            parts = [(p, True) for p in ([g["coordinates"]] if g["type"] == "LineString" else g["coordinates"])]
        else:
            polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
            parts = [(ring, k == 0) for poly in polys for k, ring in enumerate(poly)]
        geoms = []
        for coords, exterior in parts:
            a = np.asarray(coords, float)[:, :2]
            if np.abs(a).max() <= 400:
                x, z = lonlat_to_world(a[:, 0], a[:, 1])
                a = np.stack([x, z], 1)
            geoms.append((a, exterior))
        out.append((f["properties"], geoms))
    return out


def raster_polygons(feats, cell_km, n_x, n_y, band_rows=1024):
    """Coverage count 0..SS*SS per cell (exterior rings fill, holes clear)."""
    out = np.zeros((n_y, n_x), np.uint8)
    prepared = []
    for _, geoms in feats:
        for ring, exterior in geoms:
            px = (ring[:, 0] - WORLD_MIN[0]) / cell_km * SS
            pz = (ring[:, 1] - WORLD_MIN[1]) / cell_km * SS
            prepared.append((px, pz, exterior, pz.min(), pz.max()))
    for r0 in range(0, n_y, band_rows):
        r1 = min(n_y, r0 + band_rows)
        y0 = r0 * SS
        img = Image.new("L", (n_x * SS, (r1 - r0) * SS), 0)
        dr = ImageDraw.Draw(img)
        for px, pz, exterior, zmin, zmax in prepared:
            if zmax < y0 - 2 or zmin > r1 * SS + 2:
                continue
            dr.polygon(list(zip(px.tolist(), (pz - y0).tolist())), fill=1 if exterior else 0)
        a = np.asarray(img, np.uint8).reshape(r1 - r0, SS, n_x, SS).sum((1, 3))
        out[r0:r1] = a
    return out


def raster_rivers(feats, cell_km, n_x, n_y, max_rank, band_rows=4096):
    """River centre lines, one cell wide (the shader draws the band itself)."""
    lines = []
    for props, geoms in feats:
        rank = min(props.get("scalerank") or 10, ROMAN_RIVER_RANK.get(props.get("name"), 10))
        if rank > max_rank or props.get("featurecla", "River") not in ("River", None):
            continue
        for line, _ in geoms:
            px = (line[:, 0] - WORLD_MIN[0]) / cell_km
            pz = (line[:, 1] - WORLD_MIN[1]) / cell_km
            lines.append((px, pz))
    out = np.zeros((n_y, n_x), bool)
    for r0 in range(0, n_y, band_rows):
        r1 = min(n_y, r0 + band_rows)
        img = Image.new("L", (n_x, r1 - r0), 0)
        dr = ImageDraw.Draw(img)
        for px, pz in lines:
            if pz.max() < r0 - 1 or pz.min() > r1 + 1:
                continue
            # PIL truncates the coordinates, i.e. the cell under each point
            dr.line(list(zip(px.tolist(), (pz - r0).tolist())), fill=255, width=1)
        out[r0:r1] = np.asarray(img) > 0
    return out


def four_connect(m, allowed):
    """Diagonal-only steps read as broken rivers on a tile grid; bridge them
    through a cell that may hold a river."""
    out = m.copy()
    dn = m[1:, 1:] & m[:-1, :-1] & ~m[:-1, 1:] & ~m[1:, :-1]
    a = dn & allowed[:-1, 1:]
    out[:-1, 1:] |= a
    out[1:, :-1] |= dn & ~a & allowed[1:, :-1]
    ad = m[1:, :-1] & m[:-1, 1:] & ~m[:-1, :-1] & ~m[1:, 1:]
    a = ad & allowed[:-1, :-1]
    out[:-1, :-1] |= a
    out[1:, 1:] |= ad & ~a & allowed[1:, 1:]
    return out


# 8-neighbourhood in turning order (E, NE, N, NW, W, SW, S, SE) as (row, col)
RING = [(0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1), (1, 0), (1, 1)]


def _thin_lut():
    """Cells a river may lose without breaking or merging anything: 4-simple
    (Yokoi connectivity number 1) and not the end of a river."""
    lut = np.zeros(256, bool)
    for code in range(256):
        x = [(code >> k) & 1 for k in range(8)]
        c4 = sum(x[k] - x[k] * x[(k + 1) % 8] * x[(k + 2) % 8] for k in (0, 2, 4, 6))
        lut[code] = c4 == 1 and x[0] + x[2] + x[4] + x[6] >= 2
    return lut


THIN_LUT = _thin_lut()


def _count4(m):
    n = np.zeros(m.shape, np.uint8)
    n[1:] += m[:-1]
    n[:-1] += m[1:]
    n[:, 1:] += m[:, :-1]
    n[:, :-1] += m[:, 1:]
    return n


def prune_land_spurs(land, passes=2):
    """Far out a land tile with only one land neighbour (side by side) is an
    arm one tile wide; the coast rule cuts it down to a thin strip, so small
    islands read as crosses. Such arms go under water; a lone tile stays a
    square island."""
    land = land.copy()
    for _ in range(passes):
        land &= ~(land & (_count4(land) == 1))
    return land


def clean_rivers(river, land, water, holes=4, spur=3):
    """One clean line per river, as SimCity 2000 draws it: fill small loops,
    thin double runs to one cell, cut short side stubs and lone cells.
    land: cells that may hold a river; water: sea and lake cells."""
    river = four_connect(river & land, land)
    # loops around a few dry cells become solid first, thinning then leaves one line
    lab, _ = ndimage.label(~river, structure=np.ones((3, 3), bool))
    size = np.bincount(lab.ravel())
    wet = np.bincount(lab.ravel(), weights=(~land).ravel()) > 0
    fill = (size <= holes) & ~wet
    fill[0] = False
    river |= fill[lab]
    del lab
    # thinning: border cells from each side in turn, in four interleaved
    # subgrids so that cells removed together never touch
    h, w = river.shape
    m = np.zeros((h + 2, w + 2), bool)
    m[1:-1, 1:-1] = river
    flat = m.ravel()
    offs = np.array([dr * (w + 2) + dc for dr, dc in RING])
    sides = [offs[2], offs[0], offs[6], offs[4]]  # N, E, S, W
    idx = np.flatnonzero(flat)
    while True:
        changed = 0
        for side in sides:
            for par in range(4):
                r, c = np.divmod(idx, w + 2)
                cand = idx[((r & 1) * 2 + (c & 1) == par) & ~flat[idx + side]]
                if cand.size == 0:
                    continue
                code = np.zeros(cand.size, np.uint8)
                for k, o in enumerate(offs):
                    code |= flat[cand + o].astype(np.uint8) << k
                gone = cand[THIN_LUT[code]]
                flat[gone] = False
                changed += gone.size
            idx = np.flatnonzero(flat)
        if changed == 0:
            break
    river = m[1:-1, 1:-1].copy()
    # stubs: peel the ends `spur` times, then let the ends that are left grow
    # back; a side branch that short has no end left to grow back from.
    # Cells at the sea or a lake are mouths and stay.
    at_water = _count4(water) > 0
    keep = river.copy()
    for _ in range(spur):
        keep &= ~((_count4(keep) <= 1) & ~at_water)
    removed = river & ~keep
    grow = keep & (_count4(keep) <= 1)
    for _ in range(spur):
        grow = (_count4(grow) > 0) & removed
        keep |= grow
        removed &= ~grow
    return keep & (_count4(keep) > 0)


def block_mean(a, f):
    h, w = a.shape
    H, W = -(-h // f) * f, -(-w // f) * f
    p = np.zeros((H, W), np.float32)
    p[:h, :w] = a
    return p.reshape(H // f, f, W // f, f).mean((1, 3))


def settlements(cell_km, n_x, n_y):
    """0..3 density per cell from the 117 AD population (places.csv)."""
    out = np.zeros((n_y, n_x), np.float32)
    for row in csv.DictReader(open(ROOT / "data/gametiles/places.csv")):
        if not row["p117"]:
            continue
        pop = float(row["p117"])
        px, pz = lonlat_to_world(float(row["lon"]), float(row["lat"]))
        r_km = 0.6 * math.sqrt(pop / 10000)
        ci = (float(px) - WORLD_MIN[0]) / cell_km
        cj = (float(pz) - WORLD_MIN[1]) / cell_km
        rc = max(r_km / cell_km, 0.0)
        i0, i1 = int(math.floor(ci - rc - 1)), int(math.ceil(ci + rc + 1))
        j0, j1 = int(math.floor(cj - rc - 1)), int(math.ceil(cj + rc + 1))
        i0, j0 = max(i0, 0), max(j0, 0)
        i1, j1 = min(i1, n_x - 1), min(j1, n_y - 1)
        if i1 < i0 or j1 < j0:
            continue
        ii, jj = np.meshgrid(np.arange(i0, i1 + 1) + 0.5, np.arange(j0, j1 + 1) + 0.5)
        d = np.hypot(ii - ci, jj - cj) * cell_km
        dens = np.where(d < r_km, np.clip(1.25 - d / max(r_km, 1e-6), 0, 1), 0)
        # every place owns at least the cell it sits in, if the cell is not too coarse
        if cell_km <= 2.0 and 0 <= int(ci) < n_x and 0 <= int(cj) < n_y:
            core = min(1.0, 0.34 + 0.2 * math.log10(max(pop, 1000) / 1000))
            dens[int(cj) - j0, int(ci) - i0] = max(dens[int(cj) - j0, int(ci) - i0], core)
        out[j0:j1 + 1, i0:i1 + 1] = np.maximum(out[j0:j1 + 1, i0:i1 + 1], dens)
    return np.clip(np.ceil(out * 3 - 0.01), 0, 3).astype(np.uint8)


def pack_nibbles(a):
    h, w = a.shape
    if w % 2:
        a = np.concatenate([a, np.zeros((h, 1), a.dtype)], 1)
    return (a[:, 0::2] | (a[:, 1::2] << 4)).astype(np.uint8)


def chamfer(src, limit):
    """Chamfer distance in cells from True cells, capped at `limit`."""
    d = np.where(src, 0, limit).astype(np.float32)
    for _ in range(limit * 2):
        e = d.copy()
        e[1:] = np.minimum(e[1:], d[:-1] + 1)
        e[:-1] = np.minimum(e[:-1], d[1:] + 1)
        e[:, 1:] = np.minimum(e[:, 1:], d[:, :-1] + 1)
        e[:, :-1] = np.minimum(e[:, :-1], d[:, 1:] + 1)
        e[1:, 1:] = np.minimum(e[1:, 1:], d[:-1, :-1] + 1.41)
        e[:-1, :-1] = np.minimum(e[:-1, :-1], d[1:, 1:] + 1.41)
        e[1:, :-1] = np.minimum(e[1:, :-1], d[:-1, 1:] + 1.41)
        e[:-1, 1:] = np.minimum(e[:-1, 1:], d[1:, :-1] + 1.41)
        if np.array_equal(e, d):
            break
        d = e
    return d


def lake_levels(lake, height):
    """Flat surface per connected lake: lowest node height of the lake (metres)."""
    lab = np.where(lake, np.arange(lake.size, dtype=np.int64).reshape(lake.shape), np.iinfo(np.int64).max)
    big = np.iinfo(np.int64).max
    for _ in range(3000):
        m = lab.copy()
        m[1:] = np.minimum(m[1:], lab[:-1])
        m[:-1] = np.minimum(m[:-1], lab[1:])
        m[:, 1:] = np.minimum(m[:, 1:], lab[:, :-1])
        m[:, :-1] = np.minimum(m[:, :-1], lab[:, 1:])
        m = np.where(lake, m, big)
        if np.array_equal(m, lab):
            break
        lab = m
    level = np.zeros(lake.shape, np.float32)
    ids = lab[lake]
    hs = height[lake]
    order = np.argsort(ids)
    ids_s, hs_s = ids[order], hs[order]
    starts = np.r_[0, np.flatnonzero(np.diff(ids_s)) + 1]
    mins = np.minimum.reduceat(hs_s, starts)
    lut = dict(zip(ids_s[starts].tolist(), mins.tolist()))
    level[lake] = np.vectorize(lut.get)(ids)
    return np.maximum(level, 0)


def _envelope(a, step, lower):
    """Min-plus (lower) or max-minus (upper) envelope with a Chebyshev slope of
    `step` per node (a number, or an array: the step allowed into each node):
    the result changes by at most `step` between any two 8-neighbours."""
    a = a.copy()
    pick = np.minimum if lower else np.maximum
    step = np.asarray(step, np.float32)
    d = step if lower else -step
    for _ in range(10000):
        e = a.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                ys = slice(max(dy, 0), a.shape[0] + min(dy, 0))
                yd = slice(max(-dy, 0), a.shape[0] + min(-dy, 0))
                xs = slice(max(dx, 0), a.shape[1] + min(dx, 0))
                xd = slice(max(-dx, 0), a.shape[1] + min(-dx, 0))
                e[yd, xd] = pick(e[yd, xd], a[ys, xs] + (d[yd, xd] if d.ndim else d))
        if np.array_equal(e, a):
            return e
        a = e
    return a


def lake_cell_seed(lake_cells, lake_enc, height):
    """Lake level (metres) at the 2 km nodes under the 0.5 km lake cells.

    The shader draws a lake cell at the lowest lake level found on the nearest
    node of its centre and of four points 1 km around it (tt_lake_level), and
    reads the relief bilinearly from the four nodes around a point. Every node
    that carries a lake cell is pinned at that cell's level, so the land
    around a lake comes down to the water line instead of ending in a wall.
    Lake cells with no lake node close by (small lakes) take the lowest height
    of their four nodes; the shader falls back to that value too."""
    seed = np.full((GRID_H, GRID_W), np.inf, np.float32)
    cj, ci = np.nonzero(lake_cells)
    px = WORLD_MIN[0] + (ci + 0.5) * BASE_CELL_KM
    pz = WORLD_MIN[1] + (cj + 0.5) * BASE_CELL_KM
    sx = (GRID_W - 1) / WORLD_SIZE[0]
    sz = (GRID_H - 1) / WORLD_SIZE[1]
    level = np.full(px.shape, np.inf, np.float32)
    for ox, oz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        ni = np.clip(np.floor((px + ox - WORLD_MIN[0]) * sx + 0.5).astype(int), 0, GRID_W - 1)
        nj = np.clip(np.floor((pz + oz - WORLD_MIN[1]) * sz + 0.5).astype(int), 0, GRID_H - 1)
        e = lake_enc[nj, ni]
        level = np.where(e > 0, np.minimum(level, e.astype(np.float32) - 1000), level)
    gx = (px - WORLD_MIN[0]) * sx
    gz = (pz - WORLD_MIN[1]) * sz
    i0 = np.clip(np.floor(gx).astype(int), 0, GRID_W - 2)
    j0 = np.clip(np.floor(gz).astype(int), 0, GRID_H - 2)
    low = np.minimum(np.minimum(height[j0, i0], height[j0, i0 + 1]), np.minimum(height[j0 + 1, i0], height[j0 + 1, i0 + 1]))
    level = np.maximum(np.where(np.isfinite(level), level, low), 0).astype(np.float32)
    for dj in (0, 1):
        for di in (0, 1):
            np.minimum.at(seed, (j0 + dj, i0 + di), level)
    return np.where(np.isfinite(seed), seed, np.nan).astype(np.float32)


def relief_step(height):
    """Allowed rise per node (metres): RELIEF_SLOPE in the lowlands, so
    plains and hills keep SimCity 2000 terraces of one level per tile, up to
    MOUNTAIN_SLOPE in high mountains, so ranges stand up as steep diorama
    massifs (up to three levels per tile) instead of being shaved into mounds."""
    node_km = WORLD_SIZE[0] / (GRID_W - 1)
    h = np.maximum(height, 0).astype(np.float32)
    # 5 x 5 node mean, so single peaks do not decide the slope of their range
    pad = np.pad(h, 2, mode="edge")
    c = pad.cumsum(0).cumsum(1)
    c = np.pad(c, ((1, 0), (1, 0)))
    box = (c[5:, 5:] - c[:-5, 5:] - c[5:, :-5] + c[:-5, :-5]) / 25.0
    t = np.clip((box - MOUNTAIN_FROM_M) / (MOUNTAIN_TO_M - MOUNTAIN_FROM_M), 0, 1)
    t = t * t * (3 - 2 * t)
    return ((RELIEF_SLOPE + (MOUNTAIN_SLOPE - RELIEF_SLOPE) * t) * node_km).astype(np.float32)


def water_envelope(node_land, lake_level, step):
    """Highest the land may stand next to the water: 0 m at the sea nodes, the
    water level at the lake nodes (`lake_level`, metres, NaN elsewhere), rising
    `step` per node away from them (relief_step). The shader caps its blurred
    relief with this sharp field, so shores keep the level rule up close."""
    seed = np.where(node_land, np.float32(9000), np.float32(0))
    if lake_level is not None:
        seed = np.where(np.isfinite(lake_level), np.minimum(np.maximum(lake_level, 0), seed), seed).astype(np.float32)
    return _envelope(seed, step, True)


def sc2k_relief(height, node_land, water, step):
    """SimCity 2000 terrain rule: a tile corner is at most one level above or
    below its neighbours, so the land is one surface of flat tiles and one-level
    ramps, with no cliffs inside the land. Here the 2 km heights are limited to
    `step` per node (relief_step: RELIEF_SLOPE m/km, steeper in high mountains;
    mean of the lower and upper envelope, so peaks and valleys both keep half
    their excess) and capped by the water envelope, so coasts and lake shores
    ramp down to the water instead of ending in a wall."""
    h = np.where(node_land, np.maximum(height, 0), 0).astype(np.float32)
    low = _envelope(h, step, True)
    high = _envelope(h, step, False)
    return np.minimum((low + high) * 0.5, water)


def _shifted(a):
    """The eight neighbours and the cell itself (edges repeat)."""
    p = np.pad(a, 1, mode="edge")
    h, w = a.shape
    return [p[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] for dy in (-1, 0, 1) for dx in (-1, 0, 1)]


def min3(a):
    return np.minimum.reduce(_shifted(a))


def max3(a):
    return np.maximum.reduce(_shifted(a))


def gauss(a, sigma):
    """Gaussian blur (sigma in cells) as three box passes."""
    r = int(round(math.sqrt(sigma * sigma * 4 / 3 + 0.25) - 0.5))
    if r < 1:
        return a
    for _ in range(3):
        for ax in (0, 1):
            pad = [(r + 1, r) if k == ax else (0, 0) for k in (0, 1)]
            c = np.cumsum(np.pad(a, pad, mode="edge"), axis=ax, dtype=np.float64)
            n = a.shape[ax]
            a = ((np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=ax) - np.take(c, np.arange(n), axis=ax))
                 / (2 * r + 1)).astype(np.float32)
    return a


def node_bilinear(field, px, pz):
    """Bilinear sample of a node-grid field at world points (as the GPU does)."""
    gx = (px - WORLD_MIN[0]) / WORLD_SIZE[0] * (GRID_W - 1)
    gz = (pz - WORLD_MIN[1]) / WORLD_SIZE[1] * (GRID_H - 1)
    i = np.clip(np.floor(gx).astype(int), 0, GRID_W - 2)
    j = np.clip(np.floor(gz).astype(int), 0, GRID_H - 2)
    fx = np.clip(gx - i, 0, 1).astype(np.float32)
    fz = np.clip(gz - j, 0, 1).astype(np.float32)
    return ((field[j, i] * (1 - fx) + field[j, i + 1] * fx) * (1 - fz)
            + (field[j + 1, i] * (1 - fx) + field[j + 1, i + 1] * fx) * fz)


def tile_lake_levels(water, tile_km, lake_enc, shore):
    """Water level of every lake tile in levels, by the shader rule
    (tt_lake_level): the lowest lake level on the nearest node of the tile
    centre and of four points 1 km around it, else the shore field there;
    on the far level scale like the land."""
    jj, ii = np.nonzero(water == 2)
    cx = WORLD_MIN[0] + (ii + 0.5) * tile_km
    cz = WORLD_MIN[1] + (jj + 0.5) * tile_km
    metres = np.full(cx.shape, np.nan)
    for ox, oz in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        ni = np.clip(np.floor((cx + ox - WORLD_MIN[0]) / WORLD_SIZE[0] * (GRID_W - 1) + 0.5).astype(int), 0, GRID_W - 1)
        nj = np.clip(np.floor((cz + oz - WORLD_MIN[1]) / WORLD_SIZE[1] * (GRID_H - 1) + 0.5).astype(int), 0, GRID_H - 1)
        e = lake_enc[nj, ni].astype(np.float64)
        metres = np.where(e > 0, np.fmin(metres, e - 1000), metres)
    metres = np.where(np.isnan(metres), node_bilinear(shore, cx, cz), metres)
    level = np.full(water.shape, np.inf, np.float32)
    level[jj, ii] = np.maximum(np.round(far_level_x(metres)), 1)
    return level


def corner_levels(water, tile_km, height, lake_enc, shore):
    """SimCity 2000 terrain at a far zoom level: the height level of every tile
    corner ((ny + 1) x (nx + 1) for ny x nx tiles).

    The land height, blurred over CORNER_BLUR tiles, on the LEVEL_STEPS_M
    scale, is limited to one level
    per tile between all eight neighbours (mean of the lower and upper
    envelope, so peaks and valleys keep half their excess) and rounded.
    Corners at the sea sit at 0, corners at a lake at most at its level, land
    at least at 1. Then every level set is opened and closed with a 3 x 3
    corner square: lone hills, ridges and notches up to two tiles wide go, so
    the land shows clean terraces and whole massifs instead of boxes. The one
    level rule is enforced again at the end (only by lowering)."""
    ny, nx = water.shape
    h = gauss(np.maximum(height, 0).astype(np.float32), CORNER_BLUR * tile_km / (WORLD_SIZE[0] / (GRID_W - 1)))
    px = WORLD_MIN[0] + np.arange(nx + 1, dtype=np.float64) * tile_km
    pz = WORLD_MIN[1] + np.arange(ny + 1, dtype=np.float64) * tile_km
    x = far_level_x(node_bilinear(h, px[None, :], pz[:, None]))
    low, high = x.copy(), x.copy()
    while True:
        low2 = np.minimum(low, min3(low) + 1)
        high2 = np.maximum(high, max3(high) - 1)
        if np.array_equal(low2, low) and np.array_equal(high2, high):
            break
        low, high = low2, high2
    level = np.round((low + high) * 0.5)
    # the four tiles around each corner (outside the map is sea, as in tt_cell)
    wp = np.pad(water, 1, constant_values=1)
    lakes = np.pad(tile_lake_levels(water, tile_km, lake_enc, shore), 1, constant_values=np.inf)
    sea = np.zeros((ny + 1, nx + 1), bool)
    cap = np.full((ny + 1, nx + 1), np.inf, np.float32)
    for dj in (0, 1):
        for di in (0, 1):
            sea |= wp[dj:dj + ny + 1, di:di + nx + 1] == 1
            cap = np.minimum(cap, lakes[dj:dj + ny + 1, di:di + nx + 1])
    fixed = sea | np.isfinite(cap)

    def settle(lv):
        lv = np.where(sea, 0, np.minimum(np.maximum(lv, 1), cap))
        while True:
            lv2 = np.minimum(lv, min3(lv) + 1)
            if np.array_equal(lv2, lv):
                return lv
            lv = lv2

    level = settle(level)
    for _ in range(2):
        cleaned = np.zeros_like(level)
        for k in range(1, int(level.max()) + 1):
            m = level >= k
            if k > 1:
                m = max3(min3(m.astype(np.uint8))).astype(bool)
                m = (min3(max3(m.astype(np.uint8))).astype(bool) & ~fixed) | m
            cleaned += m
        level = settle(cleaned)
    return level.astype(np.uint8)


def bake_levels(manifest, cells, height, lake_enc, shore):
    manifest["levels"] = []
    for level in range(BAKED_FROM, LEVELS):
        tile = BASE_CELL_KM * 2 ** level
        lv = corner_levels(cells[level], tile, height, lake_enc, shore)
        path = OUT / f"levels-L{level}.png"
        Image.fromarray(lv, "L").save(path, optimize=True)
        manifest["levels"].append({"level": level, "cell_km": tile, "width": lv.shape[1], "height": lv.shape[0],
                                   "level_steps_m": LEVEL_STEPS_M,
                                   "blur_tiles": CORNER_BLUR,
                                   "path": path.name, "sha256": sha(path),
                                   "rule": "corner (i, j) at world_min + (i, j) * cell_km; one level per tile "
                                           "between all eight neighbours, sea corners 0, land >= 1"})
        print("levels", level, lv.shape, "max", int(lv.max()))


def _hash01(i, j, seed):
    h = (i * 374761393 + j * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF).astype(np.float32) / float(0x1000000)


def value_noise(x, z, seed):
    i = np.floor(x).astype(np.int64)
    j = np.floor(z).astype(np.int64)
    fx = (x - i).astype(np.float32)
    fz = (z - j).astype(np.float32)
    fx = fx * fx * (3 - 2 * fx)
    fz = fz * fz * (3 - 2 * fz)
    a = _hash01(i, j, seed) * (1 - fx) + _hash01(i + 1, j, seed) * fx
    b = _hash01(i, j + 1, seed) * (1 - fx) + _hash01(i + 1, j + 1, seed) * fx
    return a * (1 - fz) + b * fz


def fbm(x, z, seed):
    """Three octaves of value noise, -0.5 .. 0.5 around 0."""
    return (0.5 * value_noise(x, z, seed) + 0.3 * value_noise(2.03 * x, 2.03 * z, seed + 7)
            + 0.2 * value_noise(4.11 * x, 4.11 * z, seed + 13)) - 0.5


_NOISE = {}


def _node_noise(scale_km, seed):
    """fbm at the 2 km nodes, `scale_km` per noise cell (cached per scale)."""
    key = (scale_km, seed)
    if key not in _NOISE:
        xs = (WORLD_MIN[0] + np.arange(GRID_W) * NODE_KM)[None, :]
        zs = (WORLD_MIN[1] + np.arange(GRID_H) * WORLD_SIZE[1] / (GRID_H - 1))[:, None]
        _NOISE[key] = fbm(xs / scale_km, zs / scale_km, seed)
    return _NOISE[key]


def ground_classes(water, tile_km, height, cover, band=1024):
    """The landscape of every tile at one zoom level, from the data at the
    tile centre (averaged over the tile when it is wider than the 2 km data).
    Land cover is a share per node; a little noise in km turns a share into
    patches of about that area. Rock and snow by height (lower far out, where
    the mean is below the peaks; snow climbs to the south and on dry land),
    mapped glaciers are snow too. All fields live on the 2 km nodes and are
    read bilinearly at the tile centres, as the GPU would."""
    ny, nx = water.shape
    lod = max(math.log2(tile_km / 2.0), 0.0)
    # far out the landscapes form wide calm regions: the data is blurred over
    # more tiles and the noise that breaks shares into patches fades
    sigma = (0.5 + 0.4 * lod) * tile_km / NODE_KM if tile_km > 2.0 else 0.0
    amp = 1.0 / (1.0 + 0.6 * lod)
    scale = max(6.0, 2.5 * tile_km)
    fine = max(3.0, tile_km)
    glade = max(5.0, 2.0 * tile_km)
    noise = [_node_noise(scale, 1), _node_noise(scale, 2), _node_noise(fine, 3), _node_noise(glade, 4)]
    fields = [gauss(a, sigma) for a in [height] + [cover[..., k] for k in range(cover.shape[-1])]] + noise
    out = np.full((ny, nx), NO_GROUND, np.uint8)
    gx = (np.arange(nx) + 0.5) * tile_km / NODE_KM
    i = np.clip(np.floor(gx).astype(int), 0, GRID_W - 2)
    fx = np.clip(gx - i, 0, 1).astype(np.float32)[None, :]
    for r0 in range(0, ny, band):
        r1 = min(ny, r0 + band)
        z = WORLD_MIN[1] + (np.arange(r0, r1) + 0.5) * tile_km
        gz = (z - WORLD_MIN[1]) / WORLD_SIZE[1] * (GRID_H - 1)
        j = np.clip(np.floor(gz).astype(int), 0, GRID_H - 2)
        fz = np.clip(gz - j, 0, 1).astype(np.float32)[:, None]
        jj = j[:, None]

        def at(f):
            return ((f[jj, i] * (1 - fx) + f[jj, i + 1] * fx) * (1 - fz)
                    + (f[jj + 1, i] * (1 - fx) + f[jj + 1, i + 1] * fx) * fz)

        h, forest, dry, crop, wet, glacier, n1, n2, n3, n4 = (at(f) for f in fields)
        n2_raw = n2
        n1, n2, n3 = n1 * amp, n2 * amp, n3 * amp
        lat = (41.0 - np.degrees(z / R_KM)).astype(np.float32)[:, None]
        g = np.full(h.shape, G["meadow"], np.uint8)
        # Urbek's green meadow is the ground; dry grass only on dry land and in
        # the far south
        g[(lat + 4.0 * n2 < 39.0) | (dry + 0.5 * n2 > 0.4)] = G["dry_grass"]
        # mountain belts climb to the south (no bare rock on the Anatolian steppe)
        south = np.maximum(45 - lat, 0) * 60
        g[h + 200 * n3 > 1000 - 60 * lod + south] = G["alpine"]
        scrub = dry + 0.5 * n1 > 0.62
        g[scrub] = G["scrub"]
        g[scrub & (lat < 37.5)] = G["sand"]
        # the cover carries a Roman adjustment (landcover manifest): cropland
        # counts 0.45 crop + 0.25 forest + 0.30 grass, so undo it for the shares
        farmed = np.clip(crop / 0.45, 0, 1)
        g[farmed + 0.6 * n2 > 0.6] = G["field"]
        g[wet + 0.5 * n2 > 0.45] = G["wetland"]
        # clearings: even a dense wood opens into meadows every few km
        # (only up close: far out the glades are noise); far out only the
        # dense woods stay forest, so the land reads light with dark woods as
        # in the painted map instead of one dark green
        wood_min = 0.45 + 0.05 * max(math.log2(tile_km), 0.0)
        wood = (forest - 0.25 * farmed + 0.6 * n1 > wood_min) & (h + 100 * n3 < 1400)
        if tile_km <= 2.0:
            wood &= n4 < 0.12
        g[wood] = G["forest"]
        # conifers in the subalpine belt and the north (beech below)
        # (the latitude edge wanders by a few degrees at every zoom, else it ran
        # as a straight line through Russia on the map)
        g[wood & ((h + 150 * n3 > 1050) | (lat + 5.0 * n2_raw > 57.0))] = G["conifer"]
        g[h + 220 * n3 > 1150 - 60 * lod + south] = G["rock"]
        # far out the mean height is far below the peaks: the snow line drops
        # faster than the rock line, so ranges keep white caps on the map
        snow_line = 1600 - 180 * lod + np.maximum(45 - lat, 0) * 70 + 500 * dry
        g[(h + 160 * n3 > snow_line) | (glacier + 0.5 * n3 > 0.5)] = G["snow"]
        g[(water[r0:r1] & 3) % 3 != 0] = NO_GROUND  # sea and lakes; rivers run on land
        out[r0:r1] = g
    return out


def tidy_ground(g, passes=2):
    """No lone tiles: a tile whose landscape has fewer than two of its eight
    neighbours takes the landscape most of them have."""
    for _ in range(passes):
        best = np.zeros(g.shape, np.uint8)
        best_n = np.zeros(g.shape, np.uint8)
        own_n = np.zeros(g.shape, np.uint8)
        for k in range(len(GROUND)):
            m = (g == k).astype(np.uint8)
            n = np.add.reduce(_shifted(m), dtype=np.uint8)
            more = n > best_n
            best[more] = k
            best_n[more] = n[more]
            own_n[g == k] = n[g == k]
            del m, n, more
        lone = (g != NO_GROUND) & (own_n < 3)
        g = np.where(lone, best, g)
    return g


def bake_ground(manifest, cells, height, cover):
    manifest["ground"] = []
    for level in range(LEVELS):
        tile = BASE_CELL_KM * 2 ** level
        g = tidy_ground(ground_classes(cells[level], tile, height, cover), passes=2 if tile <= 2.0 else 3)
        packed = pack_nibbles(g)
        path = OUT / f"ground-L{level}.png"
        Image.fromarray(packed, "L").save(path, optimize=True)
        manifest["ground"].append({"level": level, "cell_km": tile, "width": g.shape[1], "height": g.shape[0],
                                   "packed_width": packed.shape[1], "path": path.name, "sha256": sha(path),
                                   "classes": GROUND, "water": NO_GROUND})
        land = g[g != NO_GROUND]
        share = np.bincount(land, minlength=len(GROUND)) / max(land.size, 1)  # whole map, deserts included
        print("ground", level, g.shape, " ".join(f"{n} {v:.2f}" for n, v in zip(GROUND, share)))


def ground_cover():
    """forest, dry (bare + 0.6 shrub), crop, wetland, glacier at the 2 km nodes."""
    classes = np.fromfile(RD / "landcover-node-2km" / "classes.u8", np.uint8).reshape(GRID_H, GRID_W, 8).astype(np.float32) / 255
    forest, shrub, grass, crop, bare, snow, wet, _ = np.moveaxis(classes, -1, 0)
    return np.stack([forest, np.clip(bare + 0.6 * shrub, 0, 1), crop, wet, snow], -1)


def ground_only():
    """Rebuild only ground-L*.png from the outputs of a full bake."""
    manifest = json.loads((OUT / "manifest.json").read_text())
    height = np.fromfile(OUT / "height.r16f", "<f2").reshape(GRID_H, GRID_W).astype(np.float32)
    cells = {e["level"]: unpack_cells(e) for e in manifest["cells"]}
    bake_ground(manifest, cells, height, ground_cover())
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


def unpack_cells(entry):
    packed = np.array(Image.open(OUT / entry["path"]).convert("L"))
    a = np.zeros((packed.shape[0], packed.shape[1] * 2), np.uint8)
    a[:, 0::2] = packed & 15
    a[:, 1::2] = packed >> 4
    return a[:, :entry["width"]] & 3


def levels_only():
    """Rebuild only levels-L*.png from the outputs of a full bake."""
    manifest = json.loads((OUT / "manifest.json").read_text())
    height = np.fromfile(OUT / "height.r16f", "<f2").reshape(GRID_H, GRID_W).astype(np.float32)
    shore = np.fromfile(OUT / "shore.r16f", "<f2").reshape(GRID_H, GRID_W).astype(np.float32)
    aux = np.array(Image.open(OUT / "aux.png"))
    lake_enc = aux[..., 1].astype(np.uint16) * 256 + aux[..., 2]
    cells = {e["level"]: unpack_cells(e) for e in manifest["cells"]}
    bake_levels(manifest, cells, height, lake_enc, shore)
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    raw = np.fromfile(RD / "fixed-source-v2-mountain-r7" / "height.rg8", np.uint8).reshape(GRID_H, GRID_W, 2)
    height = (raw[..., 0].astype(np.float32) * 256 + raw[..., 1]) * 0.25 - 8192
    classes = np.fromfile(RD / "landcover-node-2km" / "classes.u8", np.uint8).reshape(GRID_H, GRID_W, 8).astype(np.float32) / 255
    land = load_features(ROOT / "data/derived/land.geojson")
    lakes = load_features(ROOT / "data/derived/lakes.geojson") + load_features(RD / "lakes-europe-supplement-r1/lakes.geojson")
    rivers = load_features(ROOT / "data/derived/rivers.geojson", lines=True) + load_features(
        RD / "rivers-europe-supplement-r1/rivers.geojson", lines=True)

    n0x = int(math.ceil(WORLD_SIZE[0] / BASE_CELL_KM))
    n0y = int(math.ceil(WORLD_SIZE[1] / BASE_CELL_KM))
    print("raster land", n0x, n0y)
    land_frac = raster_polygons(land, BASE_CELL_KM, n0x, n0y).astype(np.float32) / (SS * SS)
    # The coast layers are clipped to the region rectangle (data/region.json);
    # outside it the 2 km height decides land (height > 0), as in the atlas.
    region = json.loads((ROOT / "data/region.json").read_text())["extent"]
    rx0, rz0 = lonlat_to_world(region["west"], region["north"])
    rx1, rz1 = lonlat_to_world(region["east"], region["south"])
    cx = WORLD_MIN[0] + (np.arange(n0x) + 0.5) * BASE_CELL_KM
    cz = WORLD_MIN[1] + (np.arange(n0y) + 0.5) * BASE_CELL_KM
    out_x = (cx < rx0) | (cx > rx1)
    out_z = (cz < rz0) | (cz > rz1)
    ni = np.clip(np.round((cx - WORLD_MIN[0]) / WORLD_SIZE[0] * (GRID_W - 1)).astype(int), 0, GRID_W - 1)
    nj = np.clip(np.round((cz - WORLD_MIN[1]) / WORLD_SIZE[1] * (GRID_H - 1)).astype(int), 0, GRID_H - 1)
    for j in range(n0y):
        cols = np.flatnonzero(out_x) if not out_z[j] else np.arange(n0x)
        if cols.size:
            land_frac[j, cols] = (height[nj[j], ni[cols]] > 0).astype(np.float32)
    print("raster lakes")
    lake_frac = raster_polygons(lakes, BASE_CELL_KM, n0x, n0y).astype(np.float32) / (SS * SS)
    lake_frac = np.minimum(lake_frac, land_frac)

    manifest = {"revision": "tile-terrain-r1", "status": "implementiert",
                "node_grid": {"width": GRID_W, "height": GRID_H, "world_min": WORLD_MIN, "world_size": WORLD_SIZE,
                              "rule": "node i at world_min + i * world_size / (width - 1)"},
                "cells": [], "inputs": {}}
    water_by_level = {}
    for level in range(LEVELS):
        f = 2 ** level
        cell = BASE_CELL_KM * f
        lf = land_frac if f == 1 else block_mean(land_frac, f)
        kf = lake_frac if f == 1 else block_mean(lake_frac, f)
        ny, nx = lf.shape
        is_land = lf >= 0.5
        if level >= BAKED_FROM:
            is_land = prune_land_spurs(is_land)
        is_lake = is_land & (kf >= 0.5 * lf)
        river = clean_rivers(raster_rivers(rivers, cell, nx, ny, RIVER_RANK[level]),
                             is_land & ~is_lake, ~is_land | is_lake)
        water = np.where(is_land, 0, 1).astype(np.uint8)
        water[is_lake] = 2
        if level == 0:
            lake_cells = is_lake
        water[river] = 3
        water_by_level[level] = water & 3
        town = settlements(cell, nx, ny) * (water == 0)
        packed = pack_nibbles(water | (town << 2))
        path = OUT / f"cells-L{level}.png"
        Image.fromarray(packed, "L").save(path, optimize=True)
        manifest["cells"].append({"level": level, "cell_km": cell, "width": nx, "height": ny,
                                  "packed_width": packed.shape[1], "path": path.name, "sha256": sha(path),
                                  "river_max_scalerank": RIVER_RANK[level]})
        print("level", level, cell, nx, ny, "land", is_land.mean().round(3), "river", int(river.sum()))

    # node-grid products
    xs = WORLD_MIN[0] + np.arange(GRID_W) * WORLD_SIZE[0] / (GRID_W - 1)
    zs = WORLD_MIN[1] + np.arange(GRID_H) * WORLD_SIZE[1] / (GRID_H - 1)
    ci = np.clip(((xs - WORLD_MIN[0]) / BASE_CELL_KM).astype(int), 0, n0x - 1)
    cj = np.clip(((zs - WORLD_MIN[1]) / BASE_CELL_KM).astype(int), 0, n0y - 1)
    l2 = block_mean(land_frac, 4)
    k2 = block_mean(lake_frac, 4)
    li = np.clip(ci // 4, 0, l2.shape[1] - 1)
    lj = np.clip(cj // 4, 0, l2.shape[0] - 1)
    node_land = l2[np.ix_(lj, li)] >= 0.5
    node_lake = node_land & (k2[np.ix_(lj, li)] >= 0.5 * l2[np.ix_(lj, li)])
    print("sea distance")
    sea_dist = chamfer(node_land, 255)
    print("lake levels")
    lake_lv = lake_levels(node_lake, height)
    lake_enc = np.where(node_lake, np.clip(lake_lv + 1000, 0, 65535), 0).astype(np.uint16)
    aux = np.zeros((GRID_H, GRID_W, 4), np.uint8)
    aux[..., 0] = np.clip(np.round(sea_dist), 0, 255)
    aux[..., 1] = lake_enc >> 8
    aux[..., 2] = lake_enc & 255
    Image.fromarray(aux, "RGBA").save(OUT / "aux.png", optimize=True)

    height.astype("<f2").tofile(OUT / "height.r16f")
    print("relief")
    lake_seed = np.fmin(np.where(node_lake, lake_lv, np.nan), lake_cell_seed(lake_cells, lake_enc, height))
    step = relief_step(height)
    water = water_envelope(node_land, lake_seed, step)
    water.astype("<f2").tofile(OUT / "shore.r16f")
    sc2k_relief(height, node_land, water, step).astype("<f2").tofile(OUT / "relief.r16f")
    manifest["relief_half"] = {"path": "relief.r16f", "sha256": sha(OUT / "relief.r16f"),
                               "format": "float16 LE, metres", "slope_m_per_km": RELIEF_SLOPE,
                               "mountain_slope_m_per_km": MOUNTAIN_SLOPE,
                               "mountain_from_to_m": [MOUNTAIN_FROM_M, MOUNTAIN_TO_M],
                               "height_exaggeration": HEIGHT_EXAGGERATION}
    manifest["shore_half"] = {"path": "shore.r16f", "sha256": sha(OUT / "shore.r16f"),
                              "format": "float16 LE, metres",
                              "rule": "highest land next to the water: sea 0 m, lakes at their level, rising slope_m_per_km"}
    manifest["height_half"] = {"path": "height.r16f", "sha256": sha(OUT / "height.r16f"), "format": "float16 LE, metres"}
    print("corner levels")
    bake_levels(manifest, water_by_level, height, lake_enc, water)
    print("ground")
    bake_ground(manifest, water_by_level, height, ground_cover())
    forest, shrub, grass, crop, bare, snow, wet, _ = np.moveaxis(classes, -1, 0)
    cover = np.stack([forest, np.clip(bare + 0.6 * shrub, 0, 1), crop, wet], -1)
    Image.fromarray(np.round(cover * 255).astype(np.uint8), "RGBA").save(OUT / "cover.png", optimize=True)

    manifest["cover"] = {"path": "cover.png", "sha256": sha(OUT / "cover.png"),
                         "channels": ["forest", "dry = bare + 0.6 shrub", "crop", "wetland"]}
    manifest["aux"] = {"path": "aux.png", "sha256": sha(OUT / "aux.png"),
                       "channels": ["sea distance in node steps (2 km), capped 255", "lake level hi", "lake level lo (uint16 m + 1000; 0 = no lake)", "unused"]}
    manifest["height"] = {"path": "../fixed-source-v2-mountain-r7/height.rg8",
                          "sha256": sha(RD / "fixed-source-v2-mountain-r7/height.rg8"),
                          "encoding": "RG8 high/low byte, 0.25 m steps, -8192 m offset"}
    for name, p in [("land", ROOT / "data/derived/land.geojson"), ("lakes", ROOT / "data/derived/lakes.geojson"),
                    ("rivers", ROOT / "data/derived/rivers.geojson"),
                    ("lakes_supplement", RD / "lakes-europe-supplement-r1/lakes.geojson"),
                    ("rivers_supplement", RD / "rivers-europe-supplement-r1/rivers.geojson"),
                    ("landcover", RD / "landcover-node-2km/classes.u8"), ("places", ROOT / "data/gametiles/places.csv")]:
        manifest["inputs"][name] = {"path": str(p.relative_to(ROOT)), "sha256": sha(p)}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


if __name__ == "__main__":
    if "--levels-only" in sys.argv:
        levels_only()
    elif "--ground-only" in sys.argv:
        ground_only()
    else:
        main()
