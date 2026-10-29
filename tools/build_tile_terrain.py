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
  levels-L{n}.png  the height level of every tile corner (8 bit): far zoom levels
                   (n >= BAKED_FROM) from the terrain tiles' 2 km squares
                   (corner_levels, dem_node_heights), the near
                   ones (NEAR_LEVELS) from the terrain tiles (near_corner_levels,
                   downloaded once to DEM_DIR, not in Git)
  ground-L{n}.png  per zoom level: the landscape of every tile (GROUND, one colour
                   each), two tiles per byte like cells-L{n}.png; 15 = water
  manifest.json    grid definitions and hashes

    python3 tools/build_tile_terrain.py
    python3 tools/build_tile_terrain.py --levels-only   # only the far levels-L*.png, from the outputs above
    python3 tools/build_tile_terrain.py --near-only     # only levels-L0/L1.png (--level=N for one)
    python3 tools/build_tile_terrain.py --ground-only   # only ground-L*.png
    python3 tools/build_tile_terrain.py --towns-only    # only the settlements in cells-L*.png
    python3 tools/build_tile_terrain.py --cells-only    # only cells-L*.png (water, rivers, towns)
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
LEVELS = 7  # 0.5, 1, 2, 4, 8, 16, 32 km (32: the whole Kit 1 map in view)
# Natural Earth scalerank shown per level (more rivers up close)
RIVER_RANK = [10, 10, 8, 7, 6, 5, 4]
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
# 2, ... levels (LEVEL_BEYOND_M per level above the last), the land height
# blurred over CORNER_BLUR tiles first. Plains stay one flat level, hills get
# 2, the Apennines a ridge of 3 to 5 and the Alps 6 to 8 (equal steps either
# drew a maze of thin terraces in the hills or left the Apennines one flat
# step). Above 1000 m a level is 300 m, so the ranges rise to a crest instead
# of one wide table at 1400 to 1900 m (the Alps read as a mesa). The height
# is the terrain tiles' mean over the 2 km squares (dem_node_heights; on the
# smooth 2 km heights the Alps topped out at 1900 m and the ranges were wide
# flat tables, Kritik r9). It
# takes PEAK_SHARE of the highest point within a tile before the blur, so a
# narrow range (Apennines, Pyrenees) keeps its crest instead of melting into
# the plains; with the terrain tiles' heights half of it is enough (at 0.75
# the summits were wide mesas and the slopes thin stripes, Kritik r10, so the
# blur is a little wider too). The shader mirrors the scale (tt_far_level_x);
# the app draws far steps taller (LEVEL_HEIGHTS).
BAKED_FROM = 2
LEVEL_STEPS_M = [100.0, 250.0, 450.0, 700.0, 1000.0, 1300.0, 1600.0, 1900.0, 2200.0, 2500.0, 2900.0, 3400.0]
LEVEL_BEYOND_M = 600.0
CORNER_BLUR = 1.0
PEAK_SHARE = 0.5


def _steps_level_x(metres, steps, beyond):
    steps = np.array(steps, np.float64)
    m = np.asarray(metres, np.float64)
    x = np.interp(m, steps, np.arange(len(steps), dtype=np.float64))
    return np.where(m > steps[-1], len(steps) - 1 + (m - steps[-1]) / beyond, x)


def far_level_x(metres):
    """Height in far levels (unrounded) on the LEVEL_STEPS_M scale."""
    return _steps_level_x(metres, LEVEL_STEPS_M, LEVEL_BEYOND_M)


# The near levels (0.5 and 1 km tiles) are baked from a finer height model
# (terrain tiles, terrarium zoom DEM_ZOOM, about 450 m): on the 2 km nodes the
# hills of a few km are gone (Tivoli stood at 70 m instead of 235 m, Rome's
# hills were missing). Their scale is fine in the lowlands, so gentle land and
# Rome's hills show as SimCity 2000 terraces (NEAR_STEPS_M at 0.5 km tiles:
# 20 m levels up to 120 m, 50 m up to 420 m, NEAR_BEYOND_M above, so the
# mountains climb in many narrow steps instead of a few wide tables; twice the
# metres at 1 km tiles, and above 840 m 240 m levels there: with 120 m the
# 70 km view's slopes were 55 % ramps, corduroy, Kritik r10). At 0.5 km tiles the corners are blurred and cleaned
# at the scale of one tile (Rome's hills are a tile or two), at 1 km tiles as
# far out (a jumble of one tile bumps over the Apennines otherwise).
NEAR_LEVELS = (0, 1)
NEAR_STEPS_M = [0.0, 20.0, 40.0, 60.0, 80.0, 100.0, 120.0, 170.0, 220.0, 270.0, 320.0, 370.0, 420.0]
NEAR_BEYOND_M = [60.0, 120.0]  # per near level, in metres at 0.5 km tiles
NEAR_BLUR = [1.0, 1.2]  # tiles, per near level
NEAR_CLEAN = [3, 3]  # corner square of the cleaning, per near level
DEM_ZOOM = 8
DEM_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
DEM_DIR = RD / "terrarium-z8"  # download cache, not in Git


def near_level_x(metres, tile_km):
    """Height in near levels (unrounded) on the NEAR_STEPS_M scale of tile_km."""
    beyond = NEAR_BEYOND_M[0 if tile_km < 2 * BASE_CELL_KM else 1]
    return _steps_level_x(np.asarray(metres, np.float64) * (BASE_CELL_KM / tile_km), NEAR_STEPS_M, beyond)


def level_x(metres, tile_km):
    return near_level_x(metres, tile_km) if tile_km < BASE_CELL_KM * 2 ** BAKED_FROM else far_level_x(metres)
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
    """River centre lines, one cell wide (the shader draws the band itself).
    A named river takes the best rank of its parts, and its stretches through
    lakes (Lake Centerline) count too: where the lake is a reservoir the map
    does not have, the river ran on in pieces (Kritik r9: the Tagus ended
    inland at 4400 km); in a lake clean_rivers drops them."""
    best = {}
    for props, _ in feats:
        if props.get("name"):
            best[props["name"]] = min(best.get(props["name"], 10), props.get("scalerank") or 10)
    lines = []
    for props, geoms in feats:
        name = props.get("name")
        rank = min(best.get(name, props.get("scalerank") or 10), ROMAN_RIVER_RANK.get(name, 10))
        if rank > max_rank or props.get("featurecla", "River") not in ("River", "Lake Centerline", None):
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


TOWN_EXTRA_KM = 0.45
# Every place of the 117 AD list is a town (Hanson's urban sites), its radius
# at least TOWN_MIN_KM (built up within about nine tenths of it, so 3 x 3
# tiles of 0.5 km): Aricia (2600 people) was one tile of four lots, a
# farmstead in the woods (Kritik r8); the woods keep a tile away from the
# towns up close (TOWN_CLEARING).
TOWN_MIN_KM = 0.8
# Towns stand on land; from 4 km tiles also across the rivers, so a city
# astride a river stays one block (Kritik r9: Rome at 400 km was a bar of
# one tile column east of the Tiber).
TOWN_ON_RIVER_KM = 4.0


ISLET_KM = 8.0  # from these tiles islands of fewer than ISLET_TILES tiles go
ISLET_TILES = 2


def town_ground(water, cell_km):
    return (water == 0) | ((water == 3) & (cell_km >= TOWN_ON_RIVER_KM))


def settlements(cell_km, n_x, n_y):
    """0..3 density per cell from the 117 AD population (places.csv)."""
    out = np.zeros((n_y, n_x), np.float32)
    for row in csv.DictReader(open(ROOT / "data/gametiles/places.csv")):
        if not row["p117"]:
            continue
        pop = float(row["p117"])
        px, pz = lonlat_to_world(float(row["lon"]), float(row["lat"]))
        # the area of a place grows with its people; towns from 3000 to 7000
        # people up get a ring of up to TOWN_EXTRA_KM, else the diorama-sized
        # houses (a lot per 0.25 km) left a town of 7000 (Tibur) three houses;
        # villages keep their size
        r_km = 0.6 * math.sqrt(pop / 10000) + TOWN_EXTRA_KM * min(max((pop - 3000) / 4000, 0.0), 1.0)
        r_km = max(r_km, TOWN_MIN_KM)
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


def unit_envelope(a, lower=True):
    """np.minimum(a, min3(a) + 1) (lower) or np.maximum(a, max3(a) - 1)
    repeated until nothing changes: the result changes by at most one between
    any two 8-neighbours. Two raster sweeps (down and right, then up and left)
    give it exactly, instead of one pass over the whole map per level of
    relief."""
    src = np.asarray(a)
    sign = 1.0 if lower else -1.0
    out = np.empty_like(src)
    idx = np.arange(src.shape[1], dtype=np.float64)
    for back in (False, True):
        prev = None
        for j in range(src.shape[0] - 1, -1, -1) if back else range(src.shape[0]):
            row = sign * (out if back else src)[j].astype(np.float64)
            if prev is not None:
                row = np.minimum(row, prev + 1)
                row[1:] = np.minimum(row[1:], prev[:-1] + 1)
                row[:-1] = np.minimum(row[:-1], prev[1:] + 1)
            if back:
                row = np.minimum.accumulate((row + idx)[::-1])[::-1] - idx
            else:
                row = np.minimum.accumulate(row - idx) + idx
            out[j] = sign * row
            prev = row
    return out


def clean_levels(level, fixed, erode, dilate, block=1024, halo=4):
    """Every level set above the first opened and closed (erode, dilate: the
    corner square), the fixed corners (sea, lakes) only opened; the sum of
    the sets. In blocks, each only up to its own highest level (the halo
    covers the reach of the four steps)."""
    out = np.zeros(level.shape, np.uint8)
    ny, nx = level.shape
    for r0 in range(0, ny, block):
        for c0 in range(0, nx, block):
            a0, b0 = max(r0 - halo, 0), max(c0 - halo, 0)
            lv = level[a0:min(r0 + block + halo, ny), b0:min(c0 + block + halo, nx)]
            fx = fixed[a0:a0 + lv.shape[0], b0:b0 + lv.shape[1]]
            acc = np.zeros(lv.shape, np.uint8)
            for k in range(1, int(lv.max()) + 1):
                m = (lv >= k).view(np.uint8)
                if k > 1:
                    opened = dilate(erode(m))
                    m = np.where(fx, opened, erode(dilate(opened)))
                acc += m
            h, w = min(block, ny - r0), min(block, nx - c0)
            out[r0:r0 + h, c0:c0 + w] = acc[r0 - a0:r0 - a0 + h, c0 - b0:c0 - b0 + w]
    return out


# The cleaning cuts every summit narrower than 2 x 2 tiles, so the ranges
# ended in wide flat mesas (Kritik r10: 294 x 156 px at 70 km, 368 x 152 px
# at 120 km; a peak on each top alone did not break them up). Above
# PEAK_FROM_M a flat top of more than FLAT_MAX corners gets one level more on
# its highest PEAK_TOP_SHARE (by the real height, where that stands
# PEAK_ABOVE levels over the flat), and so on, up to PEAK_ROUNDS times, so a
# massif climbs in inset steps like the mountains of SimCity 2000 (a real high
# plain stays flat). Then a corner on a flat that is the highest point of its
# 3 x 3 corners and stands PEAK_ABOVE levels over it gets one more: a peak,
# four ramps up to one corner.
# On rock (above ROCK_M) a flat top steps up even where the land is not that
# high, by at most PEAK_OVER levels over it (with only the real height the
# largest rock tops stayed plates of 470 x 116 px at 1500 km, Kritik r11).
# Last, a pit in a top (a tile a level below all around it, left by the
# steps) is filled.
PEAK_FROM_M = 1000.0
PEAK_ABOVE = 0.5
PEAK_OVER = 1.0
FLAT_MAX = 16  # corners, a top of 3 x 3 tiles
PEAK_TOP_SHARE = 0.3
PEAK_ROUNDS = 4


def fill_pits(lv, high):
    """Every pit up to two corners wide in `high` land raised to the level
    around it (a per-level closing with the 3 x 3 corner square); in place."""
    filled = 0
    for k in range(int(lv[high].min(initial=0)) + 1, int(lv.max()) + 1):
        m = (lv >= k).view(np.uint8)
        pit = (min3(max3(m)) > m) & high
        lv[pit] = k
        filled += int(pit.sum())
    return filled


def restore_peaks(level, x, fixed, from_x, rock_x):
    lv = level.astype(np.int16)
    high = ~fixed & (x >= from_x)
    filled = fill_pits(lv, high)  # a pit in a top keeps its rim from stepping up (a ring round a hole)
    raised = 0
    for _ in range(PEAK_ROUNDS):
        # corners on a flat (all eight neighbours at least as high; two such
        # neighbours are on the same level)
        lab, n = ndimage.label((min3(lv) >= lv) & high, np.ones((3, 3), bool))
        idx = np.flatnonzero(lab)
        lab_i = lab.ravel()[idx]
        del lab
        size = np.bincount(lab_i, minlength=n + 1)
        big = size[lab_i] > FLAT_MAX
        idx, lab_i = idx[big], lab_i[big]
        if idx.size == 0:
            break
        order = np.lexsort((-x.ravel()[idx], lab_i))  # per flat, highest first
        ranked = lab_i[order]
        rank = np.empty(idx.size, np.int64)
        rank[order] = np.arange(idx.size) - np.searchsorted(ranked, ranked)
        up = rank < np.maximum(np.round(PEAK_TOP_SHARE * size[lab_i]), 1)
        xi, li = x.ravel()[idx], lv.ravel()[idx]
        up &= (xi >= li + PEAK_ABOVE) | ((xi >= rock_x) & (li + 1 <= xi + PEAK_OVER))
        lv.ravel()[idx[up]] += 1
        raised += int(up.sum())
    lv += (min3(lv) >= lv) & high & (x >= lv + PEAK_ABOVE) & (x >= max3(x))
    filled += fill_pits(lv, high)
    lv = unit_envelope(lv, True)
    return lv.astype(level.dtype), raised, filled


# Far out (1 to 4 km tiles, where the houses stand on whole tiles) a town
# (class 2 and up, the ones with houses) stands on a flat lot: the corners of
# its footprint at the lowest of them, the land around at most a level a tile
# higher, as SimCity 2000 levels the ground for building (on a ramp the
# houses stood on a podium a level tall, which drew stilts at 70 km and
# sugar cubes at 120 km, Kritik r10 and r11). Water corners keep their level.
TOWN_FLAT_KM = (1.0, 2.0, 4.0)


def flatten_towns(level, town, fixed):
    ny, nx = town.shape
    foot = np.zeros((ny + 1, nx + 1), bool)
    for dj in (0, 1):
        for di in (0, 1):
            foot[dj:dj + ny, di:di + nx] |= town >= 2
    foot &= ~fixed
    lab, n = ndimage.label(foot, np.ones((3, 3), bool))
    if n == 0:
        return level, 0
    low = np.concatenate(([np.inf], np.asarray(ndimage.minimum(level, lab, np.arange(1, n + 1)), np.float64)))
    cap = unit_envelope(np.where(foot, low[lab], np.inf), True)
    out = np.where(fixed, level, np.minimum(level, cap)).astype(level.dtype)
    return out, int((out != level).sum())




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
    level[jj, ii] = np.maximum(np.round(level_x(metres, tile_km)), 1)
    return level


def corner_levels(water, tile_km, height, lake_enc, shore, town=None):
    """SimCity 2000 terrain at a far zoom level: the height level of every tile
    corner ((ny + 1) x (nx + 1) for ny x nx tiles).

    The land height (PEAK_SHARE of it the highest point within a tile),
    blurred over CORNER_BLUR tiles, on the LEVEL_STEPS_M
    scale, is limited to one level
    per tile between all eight neighbours (mean of the lower and upper
    envelope, so peaks and valleys keep half their excess) and rounded.
    Corners at the sea sit at 0, corners at a lake at most at its level, land
    at least at 1. Then every level set is opened and closed with a 3 x 3
    corner square: lone hills, ridges and notches up to two tiles wide go, so
    the land shows clean terraces and whole massifs instead of boxes. The one
    level rule is enforced again at the end (only by lowering)."""
    ny, nx = water.shape
    h = np.maximum(height, 0).astype(np.float32)
    h = (1.0 - PEAK_SHARE) * h + PEAK_SHARE * ndimage.maximum_filter(h, size=max(int(round(tile_km / NODE_KM)), 1) + 1)
    h = gauss(h, CORNER_BLUR * tile_km / (WORLD_SIZE[0] / (GRID_W - 1)))
    px = WORLD_MIN[0] + np.arange(nx + 1, dtype=np.float64) * tile_km
    pz = WORLD_MIN[1] + np.arange(ny + 1, dtype=np.float64) * tile_km
    x = far_level_x(node_bilinear(h, px[None, :], pz[:, None]))
    level = np.round((unit_envelope(x, True) + unit_envelope(x, False)) * 0.5)
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
        return unit_envelope(np.where(sea, 0, np.minimum(np.maximum(lv, 1), cap)))

    level = settle(level)
    for _ in range(2):
        level = settle(clean_levels(level.astype(np.uint8), fixed, min3, max3))
    level, raised, filled = restore_peaks(level, x, fixed, float(far_level_x(np.float64(PEAK_FROM_M))),
                                          float(far_level_x(np.float64(ROCK_M[tile_km]))))
    print("tops", tile_km, "raised", raised, "pits filled", filled)
    if town is not None and tile_km in TOWN_FLAT_KM:
        level, flat = flatten_towns(level, town, fixed)
        print("town lots", tile_km, flat)
    return level.astype(np.uint8)


def dem_node_heights(height, dem):
    """Metres at the 2 km nodes from the terrain tiles (their mean over the
    node's square), the 2 km heights outside them. The 2 km heights are smooth
    (the Alps reach 1900 m on them, the 2 km squares of the terrain tiles
    4000 m), so the far ranges drew wide flat tables (Kritik r9)."""
    m = dem_tile_means(NODE_KM, GRID_W, GRID_H, dem, centred=True)
    return np.where(np.isfinite(m), m, height).astype(np.float32)


def bake_levels(manifest, cells, height, lake_enc, shore):
    manifest["levels"] = [e for e in manifest.get("levels", []) if e["level"] < BAKED_FROM]
    relief_h = dem_node_heights(height, dem_mosaic(cells[1] != 1))
    towns = {e["level"]: unpack_towns(e) for e in manifest["cells"]}
    for level in range(BAKED_FROM, LEVELS):
        tile = BASE_CELL_KM * 2 ** level
        lv = corner_levels(cells[level], tile, relief_h, lake_enc, shore, towns.get(level))
        path = OUT / f"levels-L{level}.png"
        Image.fromarray(lv, "L").save(path, optimize=True)
        manifest["levels"].append({"level": level, "cell_km": tile, "width": lv.shape[1], "height": lv.shape[0],
                                   "level_steps_m": LEVEL_STEPS_M,
                                   "blur_tiles": CORNER_BLUR, "peak_share": PEAK_SHARE,
                                   "beyond_m": LEVEL_BEYOND_M,
                                   "heights": {"url": DEM_URL, "zoom": DEM_ZOOM, "node_squares_km": NODE_KM},
                                   "path": path.name, "sha256": sha(path),
                                   "rule": "corner (i, j) at world_min + (i, j) * cell_km; one level per tile "
                                           "between all eight neighbours, sea corners 0, land >= 1"})
        print("levels", level, lv.shape, "max", int(lv.max()))
    manifest["levels"].sort(key=lambda e: e["level"])


def _merc_tile(lon, lat, z):
    """Fractional web mercator tile coordinates (x, y) at zoom z."""
    n = 2 ** z
    lat = np.radians(np.clip(lat, -85.0, 85.0))
    return ((np.asarray(lon, np.float64) + 180.0) / 360.0 * n,
            (1.0 - np.log(np.tan(lat) + 1.0 / np.cos(lat)) / math.pi) / 2.0 * n)


def dem_mosaic(land1):
    """Terrarium tiles (DEM_URL, zoom DEM_ZOOM) over the region rectangle
    (data/region.json) wherever the 1 km cells hold land, as one mosaic of
    metres (NaN where no tile was fetched). Returns (mosaic, first tile x, y).
    Tiles are cached in DEM_DIR."""
    import urllib.request
    from concurrent.futures import ThreadPoolExecutor
    region = json.loads((ROOT / "data/region.json").read_text())["extent"]
    z = DEM_ZOOM
    tx0, ty0 = (int(math.floor(v)) for v in _merc_tile(region["west"], region["north"], z))
    tx1, ty1 = (int(math.floor(v)) for v in _merc_tile(region["east"], region["south"], z))
    n = 2 ** z
    wanted = []
    for ty in range(ty0, ty1 + 1):
        lat_n = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * ty / n))))
        lat_s = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (ty + 1) / n))))
        for tx in range(tx0, tx1 + 1):
            lon_w, lon_e = tx / n * 360 - 180, (tx + 1) / n * 360 - 180
            x0, z0 = lonlat_to_world(lon_w, lat_n)
            x1, z1 = lonlat_to_world(lon_e, lat_s)
            i0, i1 = int((x0 - WORLD_MIN[0]) / 1.0), int(math.ceil((x1 - WORLD_MIN[0]) / 1.0))
            j0, j1 = int((z0 - WORLD_MIN[1]) / 1.0), int(math.ceil((z1 - WORLD_MIN[1]) / 1.0))
            if land1[max(j0, 0):max(j1, 0), max(i0, 0):max(i1, 0)].any():
                wanted.append((tx, ty))
    DEM_DIR.mkdir(parents=True, exist_ok=True)

    def fetch(t):
        path = DEM_DIR / f"{z}-{t[0]}-{t[1]}.png"
        if not path.exists():
            for attempt in range(5):
                try:
                    data = urllib.request.urlopen(DEM_URL.format(z=z, x=t[0], y=t[1]), timeout=60).read()
                    path.with_suffix(".part").write_bytes(data)
                    path.with_suffix(".part").rename(path)
                    break
                except OSError:
                    if attempt == 4:
                        raise
        return t, path

    mosaic = np.full(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256), np.nan, np.float32)
    with ThreadPoolExecutor(16) as pool:
        for (tx, ty), path in pool.map(fetch, wanted):
            rgb = np.array(Image.open(path).convert("RGB")).astype(np.float32)
            m = rgb[..., 0] * 256 + rgb[..., 1] + rgb[..., 2] / 256 - 32768
            mosaic[(ty - ty0) * 256:(ty - ty0 + 1) * 256, (tx - tx0) * 256:(tx - tx0 + 1) * 256] = m
    print("dem tiles", len(wanted), "of", (tx1 - tx0 + 1) * (ty1 - ty0 + 1))
    return mosaic, tx0, ty0


def near_heights(tile_km, height, dem):
    """Metres at the tile corners of a near level: the terrain tiles inside the
    region rectangle, the 2 km heights elsewhere (as the land rule there)."""
    mosaic, tx0, ty0 = dem
    region = json.loads((ROOT / "data/region.json").read_text())["extent"]
    rx0, rz0 = lonlat_to_world(region["west"], region["north"])
    rx1, rz1 = lonlat_to_world(region["east"], region["south"])
    nx = int(math.ceil(WORLD_SIZE[0] / tile_km)) + 1
    ny = int(math.ceil(WORLD_SIZE[1] / tile_km)) + 1
    px = WORLD_MIN[0] + np.arange(nx, dtype=np.float64) * tile_km
    lon = 19.0 + np.degrees(px / (R_KM * math.cos(math.radians(41))))
    out = np.empty((ny, nx), np.float32)
    mh, mw = mosaic.shape
    for j0 in range(0, ny, 256):
        pz = WORLD_MIN[1] + np.arange(j0, min(j0 + 256, ny), dtype=np.float64) * tile_km
        lat = 41.0 - np.degrees(pz / R_KM)
        fx, fy = _merc_tile(lon[None, :], lat[:, None], DEM_ZOOM)
        gx = (fx - tx0) * 256 - 0.5
        gy = (fy - ty0) * 256 - 0.5
        i = np.clip(np.floor(gx).astype(np.int64), 0, mw - 2)
        j = np.clip(np.floor(gy).astype(np.int64), 0, mh - 2)
        ax = np.clip(gx - i, 0, 1).astype(np.float32)
        ay = np.clip(gy - j, 0, 1).astype(np.float32)
        d = ((mosaic[j, i] * (1 - ax) + mosaic[j, i + 1] * ax) * (1 - ay)
             + (mosaic[j + 1, i] * (1 - ax) + mosaic[j + 1, i + 1] * ax) * ay)
        inside = (px[None, :] >= rx0) & (px[None, :] <= rx1) & (pz[:, None] >= rz0) & (pz[:, None] <= rz1)
        d = np.where(inside, d, np.nan)
        coarse = node_bilinear(height, np.broadcast_to(px[None, :], d.shape), np.broadcast_to(pz[:, None], d.shape))
        out[j0:j0 + d.shape[0]] = np.where(np.isfinite(d), d, coarse)
    return np.maximum(out, 0)


def _shifted2(a, back):
    """The four corners of the 2 x 2 squares at a (back: the squares ending at a)."""
    p = np.pad(a, ((1, 0), (1, 0)) if back else ((0, 1), (0, 1)), mode="edge")
    h, w = a.shape
    return [p[dy:dy + h, dx:dx + w] for dy in (0, 1) for dx in (0, 1)]


def near_corner_levels(water, tile_km, heights, lake_enc, shore, blur, clean, town=None):
    """SimCity 2000 terrain at a near zoom level, as corner_levels() far out,
    from the terrain tile heights on the NEAR_STEPS_M scale, blurred over `blur`
    tiles; level sets are opened and closed with a `clean` x `clean` corner
    square (2: lone corner bumps, pits and one corner ridges go while hills of
    a tile or two, Rome's, stay)."""
    ny, nx = water.shape
    x = near_level_x(gauss(heights, blur), tile_km).astype(np.float32)
    level = unit_envelope(x, True)
    level += unit_envelope(x, False)
    if tile_km < 1.0:
        del x  # (no peaks: nothing that high in the views at 0.5 km tiles, and 0.2 G corners)
    level = np.round(level * 0.5).astype(np.float32)
    wp = np.pad(water, 1, constant_values=1)
    lakes = np.pad(tile_lake_levels(water, tile_km, lake_enc, shore), 1, constant_values=np.inf)
    sea = np.zeros((ny + 1, nx + 1), bool)
    cap = np.full((ny + 1, nx + 1), np.inf, np.float32)
    for dj in (0, 1):
        for di in (0, 1):
            sea |= wp[dj:dj + ny + 1, di:di + nx + 1] == 1
            cap = np.minimum(cap, lakes[dj:dj + ny + 1, di:di + nx + 1])
    del wp, lakes
    fixed = sea | np.isfinite(cap)
    cap = np.minimum(cap, 255).astype(np.int16)

    def settle(lv):
        # in whole levels (int16): a quarter of the float work on 0.2 G corners
        return unit_envelope(np.where(sea, 0, np.minimum(np.maximum(lv, 1), cap)).astype(np.int16))

    def erode(m):
        return min3(m) if clean == 3 else np.minimum.reduce(_shifted2(m, False))

    def dilate(m):
        return max3(m) if clean == 3 else np.maximum.reduce(_shifted2(m, True))

    level = settle(np.minimum(level, 255)).astype(np.uint8)
    for _ in range(2):
        level = settle(clean_levels(level, fixed, erode, dilate)).astype(np.uint8)
    if tile_km >= 1.0:
        level, raised, filled = restore_peaks(level, x, fixed, float(near_level_x(PEAK_FROM_M, tile_km)),
                                              float(near_level_x(ROCK_M[tile_km], tile_km)))
        print("tops", tile_km, "raised", raised, "pits filled", filled)
    if town is not None and tile_km in TOWN_FLAT_KM:
        level, flat = flatten_towns(level, town, fixed)
        print("town lots", tile_km, flat)
    return level


def bake_near_levels(manifest, cells, height, lake_enc, shore, only=NEAR_LEVELS):
    dem = dem_mosaic(cells[1] != 1)
    town_cells = {e["level"]: e for e in manifest["cells"]}
    manifest["levels"] = [e for e in manifest.get("levels", []) if e["level"] not in only]
    for level in only:
        tile = BASE_CELL_KM * 2 ** level
        lv = near_corner_levels(cells[level], tile, near_heights(tile, height, dem), lake_enc, shore,
                                NEAR_BLUR[level], NEAR_CLEAN[level], unpack_towns(town_cells[level]))
        path = OUT / f"levels-L{level}.png"
        Image.fromarray(lv, "L").save(path, optimize=True)
        manifest["levels"].append({"level": level, "cell_km": tile, "width": lv.shape[1], "height": lv.shape[0],
                                   "scale": "near", "level_steps_m": [v * tile / BASE_CELL_KM for v in NEAR_STEPS_M],
                                   "beyond_m": NEAR_BEYOND_M[level] * tile / BASE_CELL_KM, "blur_tiles": NEAR_BLUR[level],
                                   "clean_corners": NEAR_CLEAN[level],
                                   "heights": {"url": DEM_URL, "zoom": DEM_ZOOM},
                                   "path": path.name, "sha256": sha(path),
                                   "rule": "corner (i, j) at world_min + (i, j) * cell_km; one level per tile "
                                           "between all eight neighbours, sea corners 0, land >= 1"})
        print("near levels", level, lv.shape, "max", int(lv.max()))
    manifest["levels"].sort(key=lambda e: e["level"])


def _hash01(i, j, seed):
    # in uint32: the products wrap at 2^32 by themselves
    h = (i.astype(np.uint32) * np.uint32(374761393) + j.astype(np.uint32) * np.uint32(668265263)
         + np.uint32(seed * 1442695041 & 0xFFFFFFFF))
    h = (h ^ (h >> np.uint32(13))) * np.uint32(1274126177)
    return ((h ^ (h >> np.uint32(16))) & np.uint32(0xFFFFFF)).astype(np.float32) / float(0x1000000)


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


# Least forest share of a tile for a wood, by tile size (km). Far out only the
# dense woods stay forest: the Roman cover holds woods on over half of Italy,
# which drew the far views as one dark olive camouflage; from the 1 km tiles a
# wood needs a denser cover (Italy about 40 % wood, Europe 12 % instead of 17 %);
# Kritik r7: at most a quarter of central Italy at 70 and 120 km (24 % each).
WOOD_MIN = {0.5: 0.45, 1.0: 0.80, 2.0: 0.92, 4.0: 0.80, 8.0: 0.70, 16.0: 0.66, 32.0: 0.62}


def ground_classes(water, tile_km, height, cover, metres, relief=None, band=1024):
    """The landscape of every tile at one zoom level, from the data at the
    tile centre (averaged over the tile when it is wider than the 2 km data).
    Land cover is a share per node; a little noise in km turns a share into
    patches of about that area. All fields live on the 2 km nodes and are
    read bilinearly at the tile centres, as the GPU would. `metres` is the
    real mean height of every tile (tile_metres): it places rock and snow and,
    from the 1 km tiles, the forest on the slopes of hilly land (`relief`: the
    height range around the tile, Kritik r8).

    Returns the open landscape (without woods, rock and snow) and the masks of
    wood, conifer wood, rock and snow; compose_ground binds them to the levels."""
    ny, nx = water.shape
    wood_out = np.zeros((ny, nx), bool)
    conifer_out = np.zeros((ny, nx), bool)
    rock_out = np.zeros((ny, nx), bool)
    snow_out = np.zeros((ny, nx), bool)
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
        wood_min = WOOD_MIN.get(tile_km, 0.65)
        m = metres[r0:r1]
        if relief is not None:
            # far out the woods draw the relief: in hilly land the valleys
            # stay open and the slopes carry the forest (the plains and
            # plateaus keep their woods)
            # (the valley floors are cleared in compose_ground, by level)
            hilly = relief[r0:r1] >= HILLY_M
            wood_min = wood_min - hilly * (m < TREELINE_M) * SLOPE_WOOD
        wood = (forest - 0.25 * farmed + 0.6 * n1 > wood_min) & (m + 100 * n3 < TREELINE_M)
        if tile_km <= 2.0:
            wood &= n4 < 0.12
        wood_out[r0:r1] = wood
        # conifers in the subalpine belt and the north (beech below)
        # (the latitude edge wanders by a few degrees at every zoom, else it ran
        # as a straight line through Russia on the map)
        hot = np.maximum(42 - lat, 0)
        conifer_out[r0:r1] = (m + 150 * n3 > CONIFER_M + 100 * hot) | (lat + 5.0 * n2_raw > 57.0)
        # rock and snow by the real height, a little higher in the dry south
        # (no bare rock on the Anatolian steppe, no snow on the Atlas)
        rock_out[r0:r1] = m > ROCK_M.get(tile_km, 1400.0) + 80 * hot
        snow_out[r0:r1] = m > SNOW_M.get(tile_km, 2200.0) + 100 * hot
        g[(water[r0:r1] & 3) % 3 != 0] = NO_GROUND  # sea and lakes; rivers run on land
        out[r0:r1] = g
    return out, wood_out, conifer_out, rock_out, snow_out


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


# Kritik r8: far out the land cover draws the relief. Bare rock on the crests
# of the high massifs and snow only on the summits, by the real height (the
# terrain tiles, mean over the tile: the far levels lie far below the peaks),
# so the rock no longer hangs on the levels around it (top two levels within
# 10 km left 0.2 % rock at 70 km). ROCK_M and SNOW_M fall a little far out,
# where a tile averages crests and valleys (rock about 10 % of the Abruzzo at
# 70 km, 4 % at 120 km). Kritik r9: snow only on the summits above 2500 m
# (about 1.5 % of the Alps at 1500 km, it was 5.6 %). From the 1 km tiles, in
# hilly land, the woods leave the valley floors (the lowest level around and
# VALLEY_LEVELS above it) and grow on the slopes up to TREELINE_M; plains and
# plateaus keep their woods. Wood,
# rock and snow are bound to the levels (level_snap):
# a tile takes them where most of its own level around it does, so they run
# in bands along the risers instead of blobs across them.
# Up close (0.5 km tiles, views of 5 to 30 km) bare rock only from 2000 m: from
# 1600 m the high pastures of the Abruzzo (Campo Imperatore, the Velino) lay
# as bare rock plateaus at 8 km, 18 to 30 % of each massif (Kritik r16); the
# tops above the tree line are alpine meadow up to there.
ROCK_M = {0.5: 2000.0, 1.0: 1600.0, 2.0: 1500.0, 4.0: 1350.0, 8.0: 1450.0, 16.0: 1300.0, 32.0: 1200.0}
SNOW_M = {0.5: 2600.0, 1.0: 2500.0, 2.0: 2500.0, 4.0: 2500.0, 8.0: 2500.0, 16.0: 2300.0, 32.0: 2100.0}
# levels above the valley floor that stay open in hilly land, per tile size;
# only up to 2 km tiles: on coarser ones every slope tile has a neighbour a
# level lower, so the rule cleared the woods off the flanks of every range
# (Kritik r10: Apennines 22.5 % -> 4.2 % forest at 400 km, Alps 20.5 -> 1.7 %).
# At 2 km tiles only the floor: with one level above it the forest was a
# thin worm (15 % at 120 km), without the rule one carpet (30 %, Kritik r11)
VALLEY_LEVELS = {0.5: 1, 1.0: 1, 2.0: 0}
TREELINE_M = 1700.0
CONIFER_M = 1450.0  # beech below (the Apennine woods), spruce and larch above
HILLY_M = 400.0  # height range within RELIEF_KM that makes land hilly
RELIEF_KM = 10.0
SLOPE_WOOD = 0.14  # less on the slopes
SNAP_TILES = 1.5


def dem_tile_means(tile_km, nx, ny, dem, centred=False):
    """Mean metres of the terrain tiles over every tile (NaN where none);
    `centred`: over the squares centred on the grid points instead."""
    mosaic, tx0, ty0 = dem
    mh, mw = mosaic.shape
    n = 2 ** DEM_ZOOM
    lon = (tx0 + (np.arange(mw) + 0.5) / 256) / n * 360 - 180
    lat = np.degrees(np.arctan(np.sinh(np.pi * (1 - 2 * (ty0 + (np.arange(mh) + 0.5) / 256) / n))))
    x, _ = lonlat_to_world(lon, 41.0)
    _, z = lonlat_to_world(19.0, lat)
    # the projection is separable: a mosaic column lies in one tile column
    shift = 0.5 if centred else 0.0
    ci = np.floor((x - WORLD_MIN[0]) / tile_km + shift).astype(np.int64)
    rj = np.floor((z - WORLD_MIN[1]) / tile_km + shift).astype(np.int64)
    okc, okr = (ci >= 0) & (ci < nx), (rj >= 0) & (rj < ny)
    m = mosaic[okr][:, okc]
    ci, rj = ci[okc], rj[okr]
    cs = np.flatnonzero(np.r_[True, np.diff(ci) != 0])
    rs = np.flatnonzero(np.r_[True, np.diff(rj) != 0])
    fin = np.isfinite(m)
    total = np.add.reduceat(np.add.reduceat(np.where(fin, np.maximum(m, 0), 0), rs, axis=0), cs, axis=1)
    count = np.add.reduceat(np.add.reduceat(fin.astype(np.float32), rs, axis=0), cs, axis=1)
    out = np.full((ny, nx), np.nan, np.float32)
    out[np.ix_(rj[rs], ci[cs])] = np.where(count > 0, total / np.maximum(count, 1), np.nan)
    return out


def tile_metres(tile_km, nx, ny, height, dem):
    """Real mean height of every tile: the near levels' corner heights (the
    terrain tiles, near_heights) averaged, far out the terrain tiles over the
    tile; the 2 km heights outside the terrain tiles."""
    if tile_km < BASE_CELL_KM * 2 ** BAKED_FROM:
        c = near_heights(tile_km, height, dem)
        return 0.25 * (c[:ny, :nx] + c[1:ny + 1, :nx] + c[:ny, 1:nx + 1] + c[1:ny + 1, 1:nx + 1])
    m = dem_tile_means(tile_km, nx, ny, dem)
    px = WORLD_MIN[0] + (np.arange(nx) + 0.5) * tile_km
    pz = WORLD_MIN[1] + (np.arange(ny) + 0.5) * tile_km
    coarse = node_bilinear(height, np.broadcast_to(px[None, :], m.shape), np.broadcast_to(pz[:, None], m.shape))
    return np.where(np.isfinite(m), m, np.maximum(coarse, 0)).astype(np.float32)


def tile_low_levels(level, ny, nx):
    """The lowest corner level of every tile (levels-L{level}.png)."""
    Image.MAX_IMAGE_PIXELS = None  # the near levels are 0.2 G corners
    c = np.array(Image.open(OUT / f"levels-L{level}.png"))
    return np.minimum(np.minimum(c[:ny, :nx], c[1:ny + 1, :nx]), np.minimum(c[:ny, 1:nx + 1], c[1:ny + 1, 1:nx + 1]))


def level_snap(mask, lv, sigma, block=2048):
    """`mask` bound to the levels: a tile takes it where most of its own level
    (lv) within about `sigma` tiles has it (normalised blur per level)."""
    out = np.zeros(mask.shape, bool)
    pad = int(4 * sigma) + 1
    ny, nx = mask.shape
    for r0 in range(0, ny, block):
        for c0 in range(0, nx, block):
            a0, b0 = max(r0 - pad, 0), max(c0 - pad, 0)
            a1, b1 = min(r0 + block + pad, ny), min(c0 + block + pad, nx)
            mk = mask[a0:a1, b0:b1]
            if not mk.any():
                continue
            lvb = lv[a0:a1, b0:b1]
            res = np.zeros(mk.shape, bool)
            for k in np.unique(lvb[mk]):
                same = lvb == k
                sel = mk & same
                rows, cols = np.flatnonzero(sel.any(1)), np.flatnonzero(sel.any(0))
                # the snap reaches pad tiles beyond the mask, its blur pad more
                y0, y1 = max(rows[0] - 2 * pad, 0), min(rows[-1] + 2 * pad + 1, mk.shape[0])
                x0, x1 = max(cols[0] - 2 * pad, 0), min(cols[-1] + 2 * pad + 1, mk.shape[1])
                s = same[y0:y1, x0:x1].astype(np.float32)
                f = mk[y0:y1, x0:x1].astype(np.float32)
                res[y0:y1, x0:x1] |= (s > 0) & (ndimage.gaussian_filter(f * s, sigma) > 0.5 * ndimage.gaussian_filter(s, sigma))
            h, w = min(block, ny - r0), min(block, nx - c0)
            out[r0:r0 + h, c0:c0 + w] = res[r0 - a0:r0 - a0 + h, c0 - b0:c0 - b0 + w]
    return out


TOWN_CLEARING = {0.5: 1, 1.0: 1}  # tiles of open land around the towns, per tile size


def compose_ground(open_g, wood, conifer, rock, snow, lv, tile_km, town=None, hilly=None):
    """The landscape with woods, rock and snow bound to the levels; snow in
    patches of at least 2 x 2 tiles; no wood next to a town up close. In
    `hilly` land the valley floors stay open: no wood on the lowest level
    around (within RELIEF_KM) nor on the VALLEY_LEVELS above it (Kritik r9:
    the woods filled the valleys and hid the steps)."""
    if hilly is not None:
        size = max(int(round(2 * RELIEF_KM / tile_km)) | 1, 3)
        wood &= ~(hilly & (lv.astype(np.int16) - ndimage.minimum_filter(lv, size) <= VALLEY_LEVELS[tile_km]))
    if tile_km >= 1.0:
        wood = level_snap(wood, lv, SNAP_TILES)
    if town is not None and tile_km in TOWN_CLEARING:
        wood &= ~ndimage.binary_dilation(town > 0, np.ones((3, 3), bool), iterations=TOWN_CLEARING[tile_km])
    rock = level_snap(rock, lv, SNAP_TILES)
    snow = ndimage.binary_opening(level_snap(snow, lv, 1.0), np.ones((2, 2), bool))
    land = open_g != NO_GROUND
    g = open_g.copy()
    g[wood & land] = G["forest"]
    g[wood & conifer & land] = G["conifer"]
    g[rock & land] = G["rock"]
    g[snow & land] = G["snow"]
    return g


def bake_ground(manifest, cells, height, cover, only=None):
    only = tuple(range(LEVELS)) if only is None else only
    manifest["ground"] = [e for e in manifest.get("ground", []) if e["level"] not in only]
    dem = dem_mosaic(cells[1] != 1)
    towns = {e["level"]: unpack_towns(e) for e in manifest["cells"] if e["cell_km"] in TOWN_CLEARING and e["level"] in only}
    for level in only:
        tile = BASE_CELL_KM * 2 ** level
        ny, nx = cells[level].shape
        metres = tile_metres(tile, nx, ny, height, dem)
        relief = hilly = None
        if tile >= 1.0:
            size = max(int(round(2 * RELIEF_KM / tile)) | 1, 3)
            relief = ndimage.maximum_filter(metres, size) - ndimage.minimum_filter(metres, size)
            hilly = relief >= HILLY_M
        parts = ground_classes(cells[level], tile, height, cover, metres, relief)
        del metres, relief
        g = compose_ground(*parts, tile_low_levels(level, ny, nx), tile, towns.get(level),
                           hilly if tile in VALLEY_LEVELS else None)
        del parts
        g = tidy_ground(g, passes=2 if tile <= 2.0 else 3)
        packed = pack_nibbles(g)
        path = OUT / f"ground-L{level}.png"
        Image.fromarray(packed, "L").save(path, optimize=True)
        manifest["ground"].append({"level": level, "cell_km": tile, "width": g.shape[1], "height": g.shape[0],
                                   "packed_width": packed.shape[1], "path": path.name, "sha256": sha(path),
                                   "classes": GROUND, "water": NO_GROUND,
                                   "relief_cover": {"rock_m": ROCK_M[tile], "snow_m": SNOW_M[tile],
                                                    "valley_levels": VALLEY_LEVELS.get(tile), "treeline_m": TREELINE_M,
                                                    "heights": {"url": DEM_URL, "zoom": DEM_ZOOM}}})
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
    only = tuple(int(a.split("=")[1]) for a in sys.argv if a.startswith("--level=")) or None
    bake_ground(manifest, cells, height, ground_cover(), only)
    manifest["ground"].sort(key=lambda e: e["level"])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


def towns_only():
    """Rebuild only the settlement bits of cells-L*.png (the water stays)."""
    manifest = json.loads((OUT / "manifest.json").read_text())
    for e in manifest["cells"]:
        water = unpack_cells(e)
        town = settlements(e["cell_km"], e["width"], e["height"]) * town_ground(water, e["cell_km"])
        path = OUT / e["path"]
        Image.fromarray(pack_nibbles(water | (town << 2)), "L").save(path, optimize=True)
        e["sha256"] = sha(path)
        write_town_list(e, town)
        print("towns", e["level"], int((town > 0).sum()))
    manifest["inputs"]["places"] = {"path": "data/gametiles/places.csv", "sha256": sha(ROOT / "data/gametiles/places.csv")}
    manifest["town_extra_km"] = TOWN_EXTRA_KM
    manifest["town_min_km"] = TOWN_MIN_KM
    manifest["town_on_river_km"] = TOWN_ON_RIVER_KM
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


def write_town_list(entry, town):
    """towns-L*.i32: the town tiles of a level as a sorted list, so the app
    draws houses only there (a prop patch of 100 x 100 tiles at 4 km held
    about 20 town tiles: its 90 000 house slots were nearly all empty)."""
    idx = np.flatnonzero(town)
    path = OUT / entry["path"].replace("cells-", "towns-").replace(".png", ".i32")
    (idx.astype(np.int64) * 4 + town.ravel()[idx]).astype("<i4").tofile(path)
    entry["towns"] = {"path": path.name, "count": int(idx.size), "sha256": sha(path),
                      "rule": "int32 (j * width + i) * 4 + town class, sorted"}


def town_lists():
    """Rebuild only towns-L*.i32 from cells-L*.png."""
    manifest = json.loads((OUT / "manifest.json").read_text())
    for e in manifest["cells"]:
        write_town_list(e, unpack_towns(e))
        print("town list", e["level"], e["towns"]["count"])
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


def unpack_towns(entry):
    packed = np.array(Image.open(OUT / entry["path"]).convert("L"))
    a = np.zeros((packed.shape[0], packed.shape[1] * 2), np.uint8)
    a[:, 0::2] = packed & 15
    a[:, 1::2] = packed >> 4
    return a[:, :entry["width"]] >> 2


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


def near_only():
    """Rebuild only the near levels (levels-L0/L1.png) from the outputs of a full bake."""
    manifest = json.loads((OUT / "manifest.json").read_text())
    height = np.fromfile(OUT / "height.r16f", "<f2").reshape(GRID_H, GRID_W).astype(np.float32)
    shore = np.fromfile(OUT / "shore.r16f", "<f2").reshape(GRID_H, GRID_W).astype(np.float32)
    aux = np.array(Image.open(OUT / "aux.png"))
    lake_enc = aux[..., 1].astype(np.uint16) * 256 + aux[..., 2]
    cells = {e["level"]: unpack_cells(e) for e in manifest["cells"] if e["level"] in NEAR_LEVELS}
    only = tuple(int(a.split("=")[1]) for a in sys.argv if a.startswith("--level=")) or NEAR_LEVELS
    bake_near_levels(manifest, cells, height, lake_enc, shore, only)
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def bake_cells(manifest, height, land, lakes, rivers):
    """cells-L*.png: sea, lakes, rivers and towns of every zoom level."""
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
    manifest["cells"] = []
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
        if cell >= ISLET_KM:
            # far out a one-tile island is a beige speck on the sea (Kritik:
            # the Greek and Dalmatian islets read as litter at 1500 and 4400 km)
            lab, _ = ndimage.label(is_land, np.ones((3, 3), bool))
            is_land &= np.bincount(lab.ravel())[lab] >= ISLET_TILES
        is_lake = is_land & (kf >= 0.5 * lf)
        river = clean_rivers(raster_rivers(rivers, cell, nx, ny, RIVER_RANK[level]),
                             is_land & ~is_lake, ~is_land | is_lake)
        water = np.where(is_land, 0, 1).astype(np.uint8)
        water[is_lake] = 2
        if level == 0:
            lake_cells = is_lake
        water[river] = 3
        water_by_level[level] = water & 3
        town = settlements(cell, nx, ny) * town_ground(water, cell)
        packed = pack_nibbles(water | (town << 2))
        path = OUT / f"cells-L{level}.png"
        Image.fromarray(packed, "L").save(path, optimize=True)
        manifest["cells"].append({"level": level, "cell_km": cell, "width": nx, "height": ny,
                                  "packed_width": packed.shape[1], "path": path.name, "sha256": sha(path),
                                  "river_max_scalerank": RIVER_RANK[level]})
        write_town_list(manifest["cells"][-1], town)
        print("level", level, cell, nx, ny, "land", is_land.mean().round(3), "river", int(river.sum()))
    return water_by_level, land_frac, lake_frac, lake_cells


def cells_only():
    """Rebuild only cells-L*.png (the water and the towns); the levels and the
    ground do not read the rivers or the towns' cells."""
    manifest = json.loads((OUT / "manifest.json").read_text())
    height = np.fromfile(OUT / "height.r16f", "<f2").reshape(GRID_H, GRID_W).astype(np.float32)
    land = load_features(ROOT / "data/derived/land.geojson")
    lakes = load_features(ROOT / "data/derived/lakes.geojson") + load_features(RD / "lakes-europe-supplement-r1/lakes.geojson")
    rivers = load_features(ROOT / "data/derived/rivers.geojson", lines=True) + load_features(
        RD / "rivers-europe-supplement-r1/rivers.geojson", lines=True)
    bake_cells(manifest, height, land, lakes, rivers)
    manifest["town_min_km"] = TOWN_MIN_KM
    manifest["town_on_river_km"] = TOWN_ON_RIVER_KM
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("done")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    raw = np.fromfile(RD / "fixed-source-v2-mountain-r7" / "height.rg8", np.uint8).reshape(GRID_H, GRID_W, 2)
    height = (raw[..., 0].astype(np.float32) * 256 + raw[..., 1]) * 0.25 - 8192
    classes = np.fromfile(RD / "landcover-node-2km" / "classes.u8", np.uint8).reshape(GRID_H, GRID_W, 8).astype(np.float32) / 255
    land = load_features(ROOT / "data/derived/land.geojson")
    lakes = load_features(ROOT / "data/derived/lakes.geojson") + load_features(RD / "lakes-europe-supplement-r1/lakes.geojson")
    rivers = load_features(ROOT / "data/derived/rivers.geojson", lines=True) + load_features(
        RD / "rivers-europe-supplement-r1/rivers.geojson", lines=True)

    manifest = {"revision": "tile-terrain-r1", "status": "implementiert",
                "node_grid": {"width": GRID_W, "height": GRID_H, "world_min": WORLD_MIN, "world_size": WORLD_SIZE,
                              "rule": "node i at world_min + i * world_size / (width - 1)"},
                "cells": [], "inputs": {}}
    water_by_level, land_frac, lake_frac, lake_cells = bake_cells(manifest, height, land, lakes, rivers)
    manifest["town_min_km"] = TOWN_MIN_KM
    manifest["town_on_river_km"] = TOWN_ON_RIVER_KM
    n0y, n0x = land_frac.shape

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
    print("near corner levels")
    bake_near_levels(manifest, water_by_level, height, lake_enc, water)
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
    elif "--near-only" in sys.argv:
        near_only()
    elif "--ground-only" in sys.argv:
        ground_only()
    elif "--towns-only" in sys.argv:
        towns_only()
    elif "--town-lists" in sys.argv:
        town_lists()
    elif "--cells-only" in sys.argv:
        cells_only()
    else:
        main()
