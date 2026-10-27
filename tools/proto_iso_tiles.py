#!/usr/bin/env python3
"""Prototype: tile-based isometric look ("SimCity 2000 meets EU5") for the Kit 1 map.

Status: Prototyp (nur Offline-Render, kein Godot-Pfad). Reads the fixed 2 km
display grid (height + WorldCover landcover) and the Natural Earth coast, lake
and river layers that are already in the repo, puts them on a square tile grid
per zoom level, quantizes the terrain into SC2000-style height levels with
shared corner heights (slopes, cliffs, coast walls) and paints it with the
reference palette (romaaeterna/terrain/PALETTE.md). Everything is drawn with
PIL polygons and small procedural tree sprites; nothing is copied from any game.

    python3 tools/proto_iso_tiles.py --out runs/proto-iso-tiles-r1
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
RD = ROOT / "artifacts" / "render-data"
GRID_W, GRID_H = 5163, 2392
WORLD_MIN = (-5286.959516530886, -2223.9016046706583)
WORLD_SIZE = (10322.15905608411, 4781.388450041915)
R_KM = 6371.0088
SS = 2  # supersampling factor for every render

# Reference palette (sRGB screen colours from PALETTE.md, used as albedo at flat light).
PAL = {
    "plain": (155, 154, 85),
    "grass": (128, 138, 76),
    "dry": (177, 164, 97),
    "hill": (97, 115, 69),
    "forest_floor": (78, 102, 60),
    "sand": (216, 192, 140),
    "sand_dark": (197, 177, 119),
    "rock": (141, 141, 116),
    "peak": (219, 199, 162),
    "snow": (240, 240, 232),
    "wetland": (104, 128, 86),
    "crop": (186, 170, 98),
    "crop_dark": (160, 150, 84),
    "earth": (150, 118, 80),
    "earth_dark": (112, 88, 62),
    "cliff_rock": (128, 122, 104),
    "water_deep": (24, 72, 128),
    "water_mid": (34, 98, 156),
    "water_shallow": (52, 140, 172),
    "water_lagoon": (84, 168, 176),
    "foam": (214, 232, 224),
}


# ---------------------------------------------------------------- data access

def lonlat_to_world(lon, lat):
    lon = np.asarray(lon, float)
    lat = np.asarray(lat, float)
    x = R_KM * math.cos(math.radians(41)) * np.radians(lon - 19)
    z = -R_KM * np.radians(lat - 41)
    return x, z


class Data:
    def __init__(self):
        raw = np.fromfile(RD / "fixed-source-v2-mountain-r7" / "height.rg8", np.uint8).reshape(GRID_H, GRID_W, 2)
        self.height = (raw[..., 0].astype(np.float32) * 256 + raw[..., 1]) * 0.25 - 8192
        self.classes = np.fromfile(RD / "landcover-node-2km" / "classes.u8", np.uint8).reshape(GRID_H, GRID_W, 8)
        self.land = self._features(ROOT / "data/derived/land.geojson")
        self.lakes = self._features(ROOT / "data/derived/lakes.geojson") + self._features(
            RD / "lakes-europe-supplement-r1/lakes.geojson")
        self.rivers = self._features(ROOT / "data/derived/rivers.geojson", lines=True) + self._features(
            RD / "rivers-europe-supplement-r1/rivers.geojson", lines=True)

    @staticmethod
    def _features(path, lines=False):
        """Return a list of (props, [rings or lines in world km])."""
        out = []
        for f in json.loads(Path(path).read_text())["features"]:
            g = f["geometry"]
            if g is None:
                continue
            if lines:
                parts = [g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]
            else:
                polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
                parts = [ring for poly in polys for ring in poly]
                # keep ring role: first ring of each polygon is the exterior
                roles = [k == 0 for poly in polys for k, _ in enumerate(poly)]
            world = []
            for p in parts:
                a = np.asarray(p, float)[:, :2]
                if np.abs(a).max() > 400:  # already model world km
                    world.append(a)
                else:
                    x, z = lonlat_to_world(a[:, 0], a[:, 1])
                    world.append(np.stack([x, z], 1))
            out.append((f["properties"], world if lines else list(zip(world, roles))))
        return out

    def sample(self, arr, x, z):
        """Bilinear sample of a grid field at world km positions."""
        u = (x - WORLD_MIN[0]) / WORLD_SIZE[0] * (GRID_W - 1)
        v = (z - WORLD_MIN[1]) / WORLD_SIZE[1] * (GRID_H - 1)
        u = np.clip(u, 0, GRID_W - 1.001)
        v = np.clip(v, 0, GRID_H - 1.001)
        i0 = np.floor(u).astype(int)
        j0 = np.floor(v).astype(int)
        fu = u - i0
        fv = v - j0
        if arr.ndim == 3:
            fu = fu[..., None]
            fv = fv[..., None]
        a = arr[j0, i0].astype(np.float32)
        b = arr[j0, i0 + 1].astype(np.float32)
        c = arr[j0 + 1, i0].astype(np.float32)
        d = arr[j0 + 1, i0 + 1].astype(np.float32)
        return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv


def value_noise(x, z, scale, seed=0):
    """World-anchored smooth value noise in [0, 1]."""
    gx = x / scale + seed * 17.13
    gz = z / scale - seed * 9.71
    ix = np.floor(gx)
    iz = np.floor(gz)
    fx = gx - ix
    fz = gz - iz
    fx = fx * fx * (3 - 2 * fx)
    fz = fz * fz * (3 - 2 * fz)

    def h(a, b):
        return np.modf(np.abs(np.sin(a * 127.1 + b * 311.7 + seed * 74.7) * 43758.5453))[0]

    return (h(ix, iz) * (1 - fx) + h(ix + 1, iz) * fx) * (1 - fz) + (h(ix, iz + 1) * (1 - fx) + h(ix + 1, iz + 1) * fx) * fz


def fbm(x, z, scale, seed=0, octaves=3):
    total = 0.0
    amp = 0.5
    norm = 0.0
    for o in range(octaves):
        total = total + amp * value_noise(x, z, scale / (2 ** o), seed + o)
        norm += amp
        amp *= 0.5
    return total / norm


# ---------------------------------------------------------------- tile fields

class TileGrid:
    """Square tiles of `tile_km`, i grows east, j grows south. Origin = NW corner."""

    def __init__(self, data: Data, x0, z0, ni, nj, tile_km, m_per_level, rivers_rank=10, seed=1):
        self.ni, self.nj, self.s = ni, nj, tile_km
        self.x0, self.z0 = x0, z0
        ii, jj = np.meshgrid(np.arange(ni) + 0.5, np.arange(nj) + 0.5)
        self.cx = x0 + ii * tile_km
        self.cz = z0 + jj * tile_km
        ci, cj = np.meshgrid(np.arange(ni + 1), np.arange(nj + 1))
        kx = x0 + ci * tile_km
        kz = z0 + cj * tile_km

        land_frac = self._raster_polys(data.land, fill_holes=True)
        lake_frac = self._raster_polys(data.lakes, fill_holes=True)
        river = self._raster_rivers(data.rivers, rivers_rank)
        self.land = (land_frac > 0.5) & (lake_frac < 0.5)
        self.lake = (land_frac > 0.5) & (lake_frac >= 0.5)
        self.river = river & self.land
        self.river = self._four_connect(self.river) & self.land
        self.sea = ~(self.land | self.lake)

        cls = data.sample(data.classes, self.cx, self.cz) / 255.0
        self.forest, self.shrub, self.grass, self.crop, self.bare, self.snow, self.wet, _ = np.moveaxis(cls, -1, 0)
        self.lat = 41 - np.degrees(-self.cz / R_KM) * -1  # approx latitude
        self.lat = 41 - np.degrees(self.cz / R_KM)

        # corner heights: 2 km field plus relief-scaled detail for zooms finer than the grid
        hc = data.sample(data.height, kx, kz)
        if tile_km < 2.0:
            detail = fbm(kx, kz, 3.0, seed=5) - 0.5
            hc = hc + detail * np.clip(hc * 0.12, 0, 90)
        self.h_corner = hc
        self.level_corner = np.maximum(1, np.round(np.maximum(hc, 0) / m_per_level)).astype(np.int32)
        self.m_per_level = m_per_level
        self.h_center = data.sample(data.height, self.cx, self.cz)

        # distance (in tiles) from water/land for shading
        self.sea_dist = self._dist(~self.sea)  # for sea tiles: tiles to nearest land
        self.coast_dist = self._dist(self.sea)  # for land tiles: tiles to nearest sea
        self.city = np.zeros((nj, ni), np.float32)
        for row in csv.DictReader(open(ROOT / "data/gametiles/places.csv")):
            if not row["p117"]:
                continue
            px, pz = lonlat_to_world(float(row["lon"]), float(row["lat"]))
            r_km = max(0.6 * math.sqrt(float(row["p117"]) / 10000), 0.6 * tile_km)
            if not (x0 - r_km < px < x0 + ni * tile_km + r_km and z0 - r_km < pz < z0 + nj * tile_km + r_km):
                continue
            d = np.hypot(self.cx - px, self.cz - pz) / r_km
            self.city = np.maximum(self.city, np.clip(1.15 - d, 0, 1) * (d < 1))
        self.city *= self.land & ~self.river
        self.rng = np.random.default_rng(seed)
        self.nx = fbm(self.cx, self.cz, 6.0 * max(tile_km, 0.5), seed=2)
        self.nx2 = fbm(self.cx, self.cz, 1.5 * max(tile_km, 0.5), seed=3)

    def _to_px(self, pts, k):
        return np.stack([(pts[:, 0] - self.x0) / self.s * k, (pts[:, 1] - self.z0) / self.s * k], 1)

    def _raster_polys(self, feats, fill_holes):
        k = 4
        img = Image.new("L", (self.ni * k, self.nj * k), 0)
        dr = ImageDraw.Draw(img)
        xmin, xmax = self.x0 - 50, self.x0 + self.ni * self.s + 50
        zmin, zmax = self.z0 - 50, self.z0 + self.nj * self.s + 50
        for _, rings in feats:
            for ring, exterior in rings:
                if ring[:, 0].max() < xmin or ring[:, 0].min() > xmax or ring[:, 1].max() < zmin or ring[:, 1].min() > zmax:
                    continue
                p = self._to_px(ring, k)
                dr.polygon([tuple(q) for q in p], fill=255 if exterior else 0)
        a = np.asarray(img, np.float32).reshape(self.nj, k, self.ni, k).mean((1, 3)) / 255
        return a

    def _raster_rivers(self, feats, max_rank):
        k = 4
        img = Image.new("L", (self.ni * k, self.nj * k), 0)
        dr = ImageDraw.Draw(img)
        for props, lines in feats:
            rank = props.get("scalerank") or 10
            if rank > max_rank or props.get("featurecla", "River") not in ("River", None):
                continue
            width_km = 1.2 if rank <= 3 else 0.6 if rank <= 6 else 0.35
            wpx = max(width_km / self.s, 1.0) * k
            for line in lines:
                p = self._to_px(line, k)
                if (p[:, 0].max() < -10 or p[:, 1].max() < -10 or p[:, 0].min() > self.ni * k + 10
                        or p[:, 1].min() > self.nj * k + 10):
                    continue
                dr.line([tuple(q) for q in p], fill=255, width=int(round(wpx)), joint="curve")
        a = np.asarray(img, np.float32).reshape(self.nj, k, self.ni, k).mean((1, 3)) / 255
        return a > 0.3

    @staticmethod
    def _four_connect(m):
        """Diagonal-only neighbours read as broken rivers in iso; bridge them."""
        out = m.copy()
        dn = np.zeros_like(m)
        dn[1:, 1:] = m[1:, 1:] & m[:-1, :-1] & ~m[:-1, 1:] & ~m[1:, :-1]
        out[:-1, 1:] |= dn[1:, 1:]
        ad = np.zeros_like(m)
        ad[1:, :-1] = m[1:, :-1] & m[:-1, 1:] & ~m[:-1, :-1] & ~m[1:, 1:]
        out[:-1, :-1] |= ad[1:, :-1]
        return out

    @staticmethod
    def _dist(src, n=40):
        d = np.where(src, 0, n).astype(np.float32)
        for _ in range(n):
            e = d.copy()
            e[1:] = np.minimum(e[1:], d[:-1] + 1)
            e[:-1] = np.minimum(e[:-1], d[1:] + 1)
            e[:, 1:] = np.minimum(e[:, 1:], d[:, :-1] + 1)
            e[:, :-1] = np.minimum(e[:, :-1], d[:, 1:] + 1)
            e[1:, 1:] = np.minimum(e[1:, 1:], d[:-1, :-1] + 1.4)
            e[:-1, :-1] = np.minimum(e[:-1, :-1], d[1:, 1:] + 1.4)
            e[1:, :-1] = np.minimum(e[1:, :-1], d[:-1, 1:] + 1.4)
            e[:-1, 1:] = np.minimum(e[:-1, 1:], d[1:, :-1] + 1.4)
            if np.array_equal(e, d):
                break
            d = e
        return d


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def tree_density(g, j, i):
    """Clumped woods: WorldCover forest share pushed through a noisy threshold."""
    return float(smoothstep(0.5, 0.95, g.forest[j, i] + (g.nx[j, i] - 0.5) * 0.5))


FIELD_COLOURS = [(190, 174, 98), (162, 162, 86), (178, 160, 104), (146, 152, 80), (198, 182, 108)]


def field_type(g, j, i):
    """Roman farmland patchwork on open, low, flat land; (colour, stripe axis) or None."""
    open_land = g.crop[j, i] + 0.6 * g.grass[j, i] + 0.3 * g.shrub[j, i]
    if (open_land < 0.3 or tree_density(g, j, i) > 0.05 or g.h_center[j, i] > 700 or g.coast_dist[j, i] <= 2
            or g.wet[j, i] > 0.3 or g.lat[j, i] < 33):
        return None
    # fields come in blocks of 2x2 tiles, anchored to world coordinates
    bx = np.floor(g.cx[j, i] / (2 * g.s))
    bz = np.floor(g.cz[j, i] / (2 * g.s))
    hsh = math.modf(abs(math.sin(bx * 12.9898 + bz * 78.233) * 43758.5453))[0]
    farm = smoothstep(0.25, 0.6, g.crop[j, i] * 1.5 + 0.4 * g.nx[j, i])
    if hsh > farm * 0.65:
        return None
    k = int(hsh * 997) % len(FIELD_COLOURS)
    return FIELD_COLOURS[k], (int(hsh * 7919) % 2 == 0)


def mix(a, b, t):
    t = np.clip(t, 0, 1)
    return tuple(a[k] * (1 - t) + b[k] * t for k in range(3))


def shade(c, f):
    return tuple(int(max(0, min(255, round(v * f)))) for v in c)


def ground_colour(g: TileGrid, j, i, level):
    """Albedo of a land tile from landcover fractions, altitude and coast."""
    n = g.nx[j, i]
    n2 = g.nx2[j, i]
    grass = mix(PAL["plain"], PAL["grass"], 0.35 + 0.65 * n)
    c = grass
    dry = g.bare[j, i] + 0.6 * g.shrub[j, i]
    lat = g.lat[j, i]
    if lat < 37.5:  # North African / Levantine steppe and desert lean golden-sand
        c = mix(c, PAL["dry"], min(1, dry * 1.2))
        c = mix(c, PAL["sand_dark"], max(0, (dry - 0.6) * 2.0))
    else:
        c = mix(c, PAL["dry"], min(0.85, dry * 1.1))
    c = mix(c, PAL["crop"], min(0.6, g.crop[j, i] * 1.4) * (0.6 + 0.4 * n2))
    c = mix(c, PAL["forest_floor"], 0.15 * g.forest[j, i] + 0.75 * tree_density(g, j, i))
    c = mix(c, PAL["wetland"], min(0.8, g.wet[j, i] * 2))
    h = g.h_center[j, i]
    c = mix(c, PAL["hill"], (h - 500) / 900 * (1 - dry))
    c = mix(c, PAL["rock"], (h - 1300) / 500)
    c = mix(c, PAL["peak"], (h - 1800) / 300)
    c = mix(c, PAL["snow"], g.snow[j, i] * 2.5 + (h - 2050) / 150)
    cd = g.coast_dist[j, i]
    if cd <= 1.0 and level <= 2:
        c = mix(c, PAL["sand"], 0.8)
    elif cd <= 2.0 and level <= 2:
        c = mix(c, PAL["sand"], 0.3)
    jit = 0.96 + 0.08 * n2
    return tuple(v * jit for v in c)


def water_colour(g: TileGrid, j, i):
    if g.river[j, i] or g.lake[j, i]:
        return mix(PAL["water_shallow"], PAL["water_mid"], 0.35)
    d_km = g.sea_dist[j, i] * g.s
    if d_km <= 1.2:
        c = mix(PAL["water_lagoon"], PAL["water_shallow"], d_km / 1.2)
    elif d_km <= 8:
        c = mix(PAL["water_shallow"], PAL["water_mid"], (d_km - 1.2) / 6.8)
    else:
        c = mix(PAL["water_mid"], PAL["water_deep"], (d_km - 8) / 40)
    jit = 0.985 + 0.03 * g.nx2[j, i]
    return tuple(v * jit for v in c)


# ---------------------------------------------------------------- sprites

def make_tree(kind, size, variant, rng):
    """Procedural tree sprite (RGBA) with ground anchor at the bottom centre."""
    w = int(size * 1.4)
    h = int(size * 1.6)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    cx = w / 2
    base = h - size * 0.12
    # soft contact shadow to the lower right
    dr.ellipse([cx - size * 0.28, base - size * 0.10, cx + size * 0.52, base + size * 0.10], fill=(30, 40, 20, 70))
    v = variant
    if kind == "conifer":
        dark = (34 + 4 * v, 60 + 6 * v, 42)
        mid = (50 + 5 * v, 82 + 6 * v, 52)
        lite = (82 + 5 * v, 114 + 5 * v, 66)
        dr.rectangle([cx - size * 0.05, base - size * 0.22, cx + size * 0.05, base], fill=(86, 62, 40, 255))
        for k, (y0, wid) in enumerate([(0.18, 0.42), (0.42, 0.34), (0.64, 0.24)]):
            top = base - size * (y0 + 0.42)
            bot = base - size * y0
            dr.polygon([(cx, top), (cx - size * wid, bot), (cx + size * wid, bot)], fill=dark)
            dr.polygon([(cx, top), (cx - size * wid, bot), (cx + size * wid * 0.1, bot)], fill=mid)
            dr.polygon([(cx, top), (cx - size * wid * 0.75, bot - size * 0.06), (cx - size * wid * 0.25, bot - size * 0.04)], fill=lite)
    elif kind == "cypress":
        dark = (38, 66 + 6 * v, 42)
        lite = (70, 104 + 6 * v, 60)
        dr.rectangle([cx - size * 0.04, base - size * 0.12, cx + size * 0.04, base], fill=(86, 62, 40, 255))
        dr.ellipse([cx - size * 0.14, base - size * 1.05, cx + size * 0.14, base - size * 0.08], fill=dark)
        dr.ellipse([cx - size * 0.12, base - size * 0.98, cx + size * 0.02, base - size * 0.2], fill=lite)
    else:  # broadleaf / oak, cozy round crown
        dark = (44 + 5 * v, 70 + 6 * v, 40)
        mid = (66 + 6 * v, 98 + 6 * v, 50)
        lite = (102 + 6 * v, 130 + 5 * v, 66)
        dr.rectangle([cx - size * 0.06, base - size * 0.34, cx + size * 0.06, base], fill=(96, 70, 44, 255))
        r = size * 0.36
        cy = base - size * 0.62
        dr.ellipse([cx - r, cy - r * 0.95, cx + r, cy + r * 0.95], fill=dark)
        dr.ellipse([cx - r * 0.92, cy - r * 1.0, cx + r * 0.6, cy + r * 0.62], fill=mid)
        dr.ellipse([cx - r * 0.7, cy - r * 0.86, cx + r * 0.05, cy - r * 0.1], fill=lite)
    return im


def make_house(size, variant):
    """Small Roman house: cream walls, terracotta hip roof. Anchor = bottom centre."""
    a = size * (0.5 + 0.12 * (variant % 2))
    hw = size * (0.32 + 0.14 * (variant // 2))
    hr = size * 0.3
    w = int(a * 2 + 4)
    h = int(a + hw + hr + 6)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    cx, base = w / 2, h - 2
    front, left, right = (cx, base), (cx - a, base - a / 2), (cx + a, base - a / 2)
    up = lambda p, d: (p[0], p[1] - d)
    dr.polygon([(cx + a * 0.15, base + 1), (cx + a * 1.1, base - a * 0.45), (cx + a, base - a / 2), front], fill=(40, 46, 30, 80))
    wall_l = (236, 224, 196) if variant != 3 else (226, 206, 172)
    dr.polygon([front, left, up(left, hw), up(front, hw)], fill=wall_l)
    dr.polygon([front, right, up(right, hw), up(front, hw)], fill=shade(wall_l, 0.78))
    apex = (cx, base - a / 2 - hw - hr)
    roof = (192, 98, 62) if variant % 3 else (178, 88, 58)
    dr.polygon([up(front, hw), up(left, hw), apex], fill=shade(roof, 1.08))
    dr.polygon([up(front, hw), up(right, hw), apex], fill=shade(roof, 0.82))
    dr.line([up(front, hw), apex], fill=shade(roof, 0.7), width=1)
    # a door / window dot
    dr.rectangle([cx - a * 0.45, base - a * 0.22 - hw * 0.55, cx - a * 0.32, base - a * 0.15 - hw * 0.2], fill=(96, 70, 52))
    return im


class Sprites:
    def __init__(self, size, seed=3):
        rng = np.random.default_rng(seed)
        self.size = size
        self.kinds = {k: [make_tree(k, size * (0.9 + 0.1 * v), v, rng) for v in range(4)]
                      for k in ("conifer", "broadleaf", "cypress")}
        self.kinds["house"] = [make_house(size * 0.9, v) for v in range(4)]

    def pick(self, kind, rng):
        return self.kinds[kind][rng.integers(0, 4)]


# ---------------------------------------------------------------- iso renderer

LIGHT = np.array([-0.62, -0.25, 0.75])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def tri_shade(p0, p1, p2, zscale):
    a = np.array([p1[0] - p0[0], p1[1] - p0[1], (p1[2] - p0[2]) * zscale])
    b = np.array([p2[0] - p0[0], p2[1] - p0[1], (p2[2] - p0[2]) * zscale])
    n = np.cross(a, b)
    if n[2] < 0:
        n = -n
    n = n / (np.linalg.norm(n) + 1e-9)
    d = float(n @ LIGHT)
    flat = LIGHT[2]
    return (0.45 + 0.62 * max(d, 0)) / (0.45 + 0.62 * flat)


def render_iso(data, view, size):
    W, H = size[0] * SS, size[1] * SS
    Wt = view["tile_px"] * SS
    Hs = Wt * view.get("level_px", 0.2)
    s = view["tile_km"]
    cx, cz = lonlat_to_world(*view["center"])
    cx, cz = float(cx), float(cz)
    span = int((W / (Wt / 2) + H / (Wt / 4)) / 2) + 8
    extra = int(40 * Hs / (Wt / 4))  # tall mountains below the frame
    ni = nj = span + extra
    # centre tile of the grid sits at the screen centre
    ci = cj = span / 2
    x0 = cx - ci * s
    z0 = cz - cj * s
    g = TileGrid(data, x0, z0, ni, nj, s, view["m_per_level"], rivers_rank=view.get("rivers_rank", 10))
    ox = W / 2 - (ci - cj) * Wt / 2
    oy = H / 2 - (ci + cj) * Wt / 4

    def P(gi, gj, lv):
        return (ox + (gi - gj) * Wt / 2, oy + (gi + gj) * Wt / 4 - lv * Hs)

    # per-tile corner levels (c00, c10, c11, c01)
    L = g.level_corner
    T = np.stack([L[:-1, :-1], L[:-1, 1:], L[1:, 1:], L[1:, :-1]], -1).astype(float)
    # SC2000-style terraces: a tile sits on its own level and may only ramp one
    # level up towards higher ground; larger jumps become cliff walls.
    hs = g.h_center.copy()
    pad = np.pad(hs, 1, mode="edge")
    hs = sum(pad[1 + dj:1 + dj + hs.shape[0], 1 + di:1 + di + hs.shape[1]] for dj in (-1, 0, 1) for di in (-1, 0, 1)) / 9
    Lt = np.maximum(1, np.round(np.maximum(hs, 0) / g.m_per_level))[..., None]
    T = np.clip(T, Lt, Lt + 1)
    water = ~g.land | g.river
    T[g.sea] = 0
    inland = g.river | g.lake
    if inland.any():
        lvl = np.maximum(T[inland].min(-1) - 1, 0) + 0.15
        T[inland] = lvl[:, None]
        # one flat surface per lake: spread the lowest level through each lake
        lk = np.where(g.lake, T[..., 0], np.inf)
        for _ in range(60):
            m = lk.copy()
            m[1:] = np.minimum(m[1:], lk[:-1])
            m[:-1] = np.minimum(m[:-1], lk[1:])
            m[:, 1:] = np.minimum(m[:, 1:], lk[:, :-1])
            m[:, :-1] = np.minimum(m[:, :-1], lk[:, 1:])
            m = np.where(g.lake, m, np.inf)
            if np.array_equal(m, lk):
                break
            lk = m
        T[g.lake] = lk[g.lake][:, None]
    # every land tile next to a lower water surface keeps at least one level above it
    img = Image.new("RGB", (W, H), PAL["water_deep"])
    dr = ImageDraw.Draw(img)
    sprites = Sprites(Wt * view.get("tree_size", 0.42))
    rng = np.random.default_rng(7)
    zscale = Hs / (Wt * 0.5)
    tree_max = view.get("trees_per_tile", 4)

    for d in range(ni + nj - 1):
        i_lo = max(0, d - nj + 1)
        i_hi = min(ni - 1, d)
        for i in range(i_lo, i_hi + 1):
            j = d - i
            t = T[j, i]
            pts = [P(i, j, t[0]), P(i + 1, j, t[1]), P(i + 1, j + 1, t[2]), P(i, j + 1, t[3])]
            xs = [p[0] for p in pts]
            if max(xs) < -Wt or min(xs) > W + Wt:
                continue
            ys = [p[1] for p in pts]
            if min(ys) > H + Wt or max(ys) < -Wt * 3:
                continue
            is_water = water[j, i]
            field = None
            if is_water:
                top = water_colour(g, j, i)
            else:
                top = ground_colour(g, j, i, t.max())
                if g.city[j, i] > 0:
                    top = mix(top, (198, 186, 152), 0.75)
                elif view.get("fields", True) and s <= 1.0 and np.ptp(t) == 0:
                    field = field_type(g, j, i)
                    if field is not None:
                        top = field[0]
            # front walls: east edge (c10-c11) and south edge (c01-c11)
            for (ka, kb), (ni_, nj_), fshade in (((1, 2), (i + 1, j), 0.66), ((3, 2), (i, j + 1), 0.84)):
                if ni_ < ni and nj_ < nj:
                    tn = T[nj_, ni_]
                    if ni_ == i + 1:
                        ba, bb = tn[0], tn[3]
                    else:
                        ba, bb = tn[0], tn[1]
                else:
                    ba = bb = -2
                if t[ka] <= ba and t[kb] <= bb:
                    continue
                ea = (i + 1, j) if ka == 1 else (i, j + 1)
                eb = (i + 1, j + 1)
                quad = [P(*ea, t[ka]), P(*eb, t[kb]), P(*eb, min(bb, t[kb])), P(*ea, min(ba, t[ka]))]
                if is_water:
                    wc = shade(top, fshade * 0.9)
                else:
                    hm = max(t[ka], t[kb]) * g.m_per_level
                    base = PAL["sand_dark"] if (g.coast_dist[j, i] <= 2 and hm < 3 * g.m_per_level) else PAL["earth"]
                    if hm > 1200:
                        base = PAL["cliff_rock"]
                    wc = shade(base, fshade)
                dr.polygon(quad, fill=wc)
                # strata line halfway down taller walls
                if not is_water and max(t[ka] - ba, t[kb] - bb) >= 2:
                    for k in range(1, int(max(t[ka] - ba, t[kb] - bb))):
                        la = P(*ea, t[ka] - k)
                        lb = P(*eb, t[kb] - k)
                        dr.line([la, lb], fill=shade(wc, 0.88), width=max(1, SS // 2))
                # surf line where land meets the sea
                if not is_water and ba <= 0.2 and bb <= 0.2 and g.sea[min(nj_, nj - 1), min(ni_, ni - 1)]:
                    dr.line([P(*ea, 0), P(*eb, 0)], fill=PAL["foam"], width=SS)
            # top surface as two triangles
            tri = [((0, 1, 2), None), ((0, 2, 3), None)]
            for idx, _ in tri:
                q = [pts[k] for k in idx]
                if is_water:
                    f = 1.0
                else:
                    corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
                    p3 = [(corners[k][0], corners[k][1], t[k]) for k in idx]
                    f = tri_shade(*p3, zscale)
                dr.polygon(q, fill=shade(top, f))
            if not is_water:
                dr.line(pts + [pts[0]], fill=shade(top, 0.86 if np.ptp(t) == 0 else 0.9), width=1)
                if field is not None:
                    colour, along_i = field[0], field[1]
                    n_str = 3 if Wt >= 40 * SS else 2
                    for k in range(1, n_str + 1):
                        u = k / (n_str + 1)
                        a, b = ((i + u, j), (i + u, j + 1)) if along_i else ((i, j + u), (i + 1, j + u))
                        dr.line([P(*a, t[0]), P(*b, t[0])], fill=shade(colour, 0.86), width=max(1, SS))
            else:
                # sparkles on open water
                if g.sea[j, i] and rng.random() < 0.18:
                    u, v = rng.random(2) * 0.7 + 0.15
                    a = P(i + u, j + v, t[0])
                    dr.line([a, (a[0] + Wt * 0.12, a[1])], fill=shade(top, 1.25), width=max(1, SS))
                elif g.sea[j, i] and g.sea_dist[j, i] <= 1.0 and rng.random() < 0.6:
                    u, v = rng.random(2) * 0.6 + 0.2
                    a = P(i + u, j + v, t[0])
                    dr.line([a, (a[0] + Wt * 0.16, a[1])], fill=PAL["foam"], width=max(1, SS))
            # houses
            if not is_water and g.city[j, i] > 0:
                n = int(1 + g.city[j, i] * view.get("houses_per_tile", 4) + rng.random())
                spots = sorted((rng.random(2) * 0.7 + 0.15 for _ in range(n)), key=lambda q: q[0] + q[1])
                for u, v in spots:
                    lv = (t[0] * (1 - u) * (1 - v) + t[1] * u * (1 - v) + t[2] * u * v + t[3] * (1 - u) * v)
                    sx, sy = P(i + u, j + v, lv)
                    sp = sprites.pick("house", rng)
                    img.paste(sp, (int(sx - sp.width / 2), int(sy - sp.height + 2)), sp)
            # trees
            elif not is_water and np.ptp(t) <= 2:
                fr = tree_density(g, j, i)
                lone = 0.06 * g.grass[j, i] + 0.10 * g.shrub[j, i] + 0.04 * g.crop[j, i]
                n = int(fr * tree_max + rng.random() * 0.8) + (1 if rng.random() < lone * tree_max else 0)
                h_m = g.h_center[j, i]
                lat = g.lat[j, i]
                if g.snow[j, i] > 0.3 or h_m > 1900 or g.bare[j, i] > 0.7:
                    n = 0
                spots = sorted((rng.random(2) * 0.8 + 0.1 for _ in range(n)), key=lambda q: q[0] + q[1])
                for u, v in spots:
                    lv = (t[0] * (1 - u) * (1 - v) + t[1] * u * (1 - v) + t[2] * u * v + t[3] * (1 - u) * v)
                    sx, sy = P(i + u, j + v, lv)
                    conifer_p = np.clip((h_m - 700) / 700, 0, 1) + np.clip((lat - 50) / 4, 0, 1)
                    r = rng.random()
                    if r < conifer_p:
                        kind = "conifer"
                    elif lat < 44.5 and r < conifer_p + 0.08:
                        kind = "cypress"
                    else:
                        kind = "broadleaf"
                    sp = sprites.pick(kind, rng)
                    img.paste(sp, (int(sx - sp.width / 2), int(sy - sp.height + sprites.size * 0.12)), sp)
    return img.resize(size, Image.LANCZOS)


# ---------------------------------------------------------------- world map (top-down oblique)

def render_world(data, view, size):
    W, H = size[0] * SS, size[1] * SS
    s = view["tile_km"]
    px = view["tile_px"] * SS
    py = px * 0.8
    Hs = px * 0.5
    cx, cz = lonlat_to_world(*view["center"])
    ni = int(W / px) + 4
    nj = int(H / py) + 14
    x0 = float(cx) - ni / 2 * s
    z0 = float(cz) - (nj - 10) / 2 * s
    g = TileGrid(data, x0, z0, ni, nj, s, view["m_per_level"], rivers_rank=view.get("rivers_rank", 4))
    lv = np.where(g.land, np.maximum(1, np.round(np.maximum(g.h_center, 0) / view["m_per_level"])), 0)
    lv = np.where(g.lake | g.river, np.maximum(lv - 1, 0), lv)
    img = Image.new("RGB", (W, H), PAL["water_deep"])
    dr = ImageDraw.Draw(img)
    rng = np.random.default_rng(11)
    ox = W / 2 - ni / 2 * px
    oy = H / 2 - (nj - 10) / 2 * py
    tree = Sprites(px * 1.1)
    for j in range(nj):
        for i in range(ni):
            x = ox + i * px
            y = oy + j * py - lv[j, i] * Hs
            if not g.land[j, i] or g.river[j, i] or g.lake[j, i]:
                c = shade(water_colour(g, j, i), 1.0)
                if g.sea[j, i] and rng.random() < 0.05:
                    dr.rectangle([x, y, x + px, y + py], fill=c)
                    dr.line([(x + px * 0.2, y + py * 0.5), (x + px * 0.8, y + py * 0.5)], fill=shade(c, 1.2), width=1)
                    continue
                dr.rectangle([x, y, x + px, y + py], fill=c)
                continue
            c = ground_colour(g, j, i, lv[j, i])
            # light from the west/north: compare with the tile left and above
            dl = lv[j, i] - (lv[j, i - 1] if i else lv[j, i])
            du = lv[j, i] - (lv[j - 1, i] if j else lv[j, i])
            f = 1.0 + 0.06 * np.clip(dl + du, -2, 2)
            dr.rectangle([x, y, x + px, y + py], fill=shade(c, f))
            # front wall down to the next row
            nxt = lv[j + 1, i] if j + 1 < nj else 0
            if lv[j, i] > nxt:
                dr.rectangle([x, y + py, x + px, y + py + (lv[j, i] - nxt) * Hs],
                             fill=shade(PAL["sand_dark"] if nxt == 0 else PAL["earth"], 0.78))
            if g.city[j, i] > 0:
                dr.rectangle([x + px * 0.15, y + py * 0.1, x + px * 0.85, y + py * 0.8], fill=(186, 92, 60))
            elif rng.random() < tree_density(g, j, i) * 0.9:
                sp = tree.pick("conifer" if g.h_center[j, i] > 800 or g.lat[j, i] > 50 else "broadleaf", rng)
                img.paste(sp, (int(x + px / 2 - sp.width / 2), int(y + py * 0.8 - sp.height + tree.size * 0.12)), sp)
    return img.resize(size, Image.LANCZOS)


# ---------------------------------------------------------------- views and composite

VIEWS = {
    "weltkarte": dict(kind="world", center=(14.5, 42.3), tile_km=9.0, tile_px=4.0, m_per_level=350, rivers_rank=3),
    "region": dict(kind="iso", center=(12.70, 41.95), tile_km=2.0, tile_px=26, m_per_level=110, rivers_rank=7, level_px=0.26, houses_per_tile=5,
                   trees_per_tile=2, tree_size=0.36),
    "kueste": dict(kind="iso", center=(12.40, 41.80), tile_km=1.0, tile_px=40, m_per_level=70, houses_per_tile=3,
                   trees_per_tile=4, tree_size=0.40),
    "nah": dict(kind="iso", center=(12.262, 41.758), tile_km=0.5, tile_px=62, m_per_level=35,
                trees_per_tile=4, tree_size=0.38),
}
LABELS = {"weltkarte": "Weltkarte", "region": "Region", "kueste": "Küste", "nah": "Ganz nah"}
# strip bands of Ramon's reference sheet (1774 x 887)
REF_BANDS = {"weltkarte": (0, 216), "region": (219, 466), "kueste": (469, 663), "nah": (666, 887)}


def label(img, text, sub=None):
    dr = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 18)
        small = ImageFont.truetype("DejaVuSans.ttf", 13)
    except OSError:
        font = small = ImageFont.load_default()
    dr.text((14, 10), text, fill=(250, 248, 240), font=font, stroke_width=3, stroke_fill=(30, 36, 30))
    if sub:
        dr.text((14, 34), sub, fill=(240, 238, 228), font=small, stroke_width=2, stroke_fill=(30, 36, 30))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "runs" / "proto-iso-tiles-r1"))
    ap.add_argument("--reference", help="Ramon's 4-strip reference sheet for the side-by-side")
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--full", default="1600x900")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    data = Data()
    fw, fh = map(int, args.full.split("x"))
    strips = {}
    for name, view in VIEWS.items():
        if args.only and name not in args.only:
            continue
        fn = render_world if view["kind"] == "world" else render_iso
        b0, b1 = REF_BANDS[name]
        strips[name] = fn(data, view, (1774, b1 - b0))
        strips[name].save(out / f"strip-{name}.png")
        full = fn(data, view, (fw, fh))
        full.save(out / f"full-{name}.png")
        print("rendered", name)
    if args.reference and not args.only:
        ref = Image.open(args.reference).convert("RGB")
        rows = []
        for name in VIEWS:
            b0, b1 = REF_BANDS[name]
            a = ref.crop((0, b0, 1774, b1))
            b = strips[name].copy()
            label(b, f"{LABELS[name]} · Prototyp", "Rom / Tibermündung, 117 n. Chr." if name != "weltkarte" else "Mittelmeer, 117 n. Chr.")
            rows += [a, b]
        gap = 6
        sheet = Image.new("RGB", (1774, sum(r.height for r in rows) + gap * (len(rows) - 1) + 3 * gap), (238, 240, 236))
        y = 0
        for k, r in enumerate(rows):
            sheet.paste(r, (0, y))
            y += r.height + (gap if k % 2 == 0 else gap * 2)
        sheet.save(out / "vergleich-referenz-vs-prototyp.png")


if __name__ == "__main__":
    main()
