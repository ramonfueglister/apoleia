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
  manifest.json    grid definitions and hashes

    python3 tools/build_tile_terrain.py
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

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
RIVER_RANK = [10, 10, 7, 5, 3, 2]
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


def raster_rivers(feats, cell_km, n_x, n_y, max_rank, band_rows=2048):
    k = 4
    out = np.zeros((n_y, n_x), bool)
    lines = []
    for props, geoms in feats:
        rank = props.get("scalerank") or 10
        if rank > max_rank or props.get("featurecla", "River") not in ("River", None):
            continue
        width_km = 1.2 if rank <= 3 else 0.6 if rank <= 6 else 0.35
        wpx = max(width_km / cell_km, 1.0) * k
        for line, _ in geoms:
            px = (line[:, 0] - WORLD_MIN[0]) / cell_km * k
            pz = (line[:, 1] - WORLD_MIN[1]) / cell_km * k
            lines.append((px, pz, int(round(wpx)), pz.min(), pz.max()))
    for r0 in range(0, n_y, band_rows):
        r1 = min(n_y, r0 + band_rows)
        y0 = r0 * k
        img = Image.new("L", (n_x * k, (r1 - r0) * k), 0)
        dr = ImageDraw.Draw(img)
        for px, pz, w, zmin, zmax in lines:
            if zmax < y0 - 50 or zmin > r1 * k + 50:
                continue
            dr.line(list(zip(px.tolist(), (pz - y0).tolist())), fill=255, width=w, joint="curve")
        a = np.asarray(img, np.float32).reshape(r1 - r0, k, n_x, k).mean((1, 3)) / 255
        out[r0:r1] = a > 0.3
    return four_connect(out)


def four_connect(m):
    """Diagonal-only steps read as broken rivers on a tile grid; bridge them."""
    out = m.copy()
    dn = m[1:, 1:] & m[:-1, :-1] & ~m[:-1, 1:] & ~m[1:, :-1]
    out[:-1, 1:] |= dn
    ad = m[1:, :-1] & m[:-1, 1:] & ~m[:-1, :-1] & ~m[1:, 1:]
    out[:-1, :-1] |= ad
    return out


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
    for level in range(LEVELS):
        f = 2 ** level
        cell = BASE_CELL_KM * f
        lf = land_frac if f == 1 else block_mean(land_frac, f)
        kf = lake_frac if f == 1 else block_mean(lake_frac, f)
        ny, nx = lf.shape
        is_land = lf >= 0.5
        is_lake = is_land & (kf >= 0.5 * lf)
        river = raster_rivers(rivers, cell, nx, ny, RIVER_RANK[level]) & is_land & ~is_lake
        water = np.where(is_land, 0, 1).astype(np.uint8)
        water[is_lake] = 2
        if level == 0:
            lake_cells = is_lake
        water[river] = 3
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
    main()
