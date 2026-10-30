#!/usr/bin/env python3
"""Walking cost per fine tile for the footpaths of the grain economy (S127).

Ramon (30.10.2026): every way comes from people walking it, so the ways must
know the land they are walked over. This bakes, for every fine tile (16 x 16
per 25-km cell, 1562.5 m, the path grid of sim/src/grain.rs), how much longer
a walk across it takes than across flat open ground, from the terrain the
game draws (artifacts/render-data/tile-terrain-r1, all in Git), so the paths
keep to the valleys and fords the player sees:

- slope from the corner levels of the 0.5-km tiles (levels-L0.png, turned
  back into metres by the manifest's level_steps_m / beyond_m): per tile the
  steepest grade between its corners, as Tobler's hiking function (Tobler,
  1993): time factor exp(3.5 * grade) against flat ground (6 km/h at 0 %),
  the mean of uphill and downhill;
- ground from ground-L0.png as terrain coefficients (Soule & Goldman, 1972):
  meadow, dry grass, field 1.0 (the base is open ground), scrub 1.2 (light
  brush), forest and conifer 1.5 (heavy brush), wetland 1.8 (swamp), sand
  2.1 (loose sand), alpine 1.3, rock 1.6, snow 2.5 (PLACEHOLDER: the last
  three are frei gewählt between those values);
- water from cells-L0.png: a river tile is crossed at a ford, factor 3
  (PLACEHOLDER frei gewählt); sea and lake tiles are not walked.

A fine tile's factor is the mean over the 0.5-km tiles whose middle lies in
it (about ten), of slope factor x ground coefficient, water tiles left out;
a fine tile with no land tile is blocked. Stored as one byte, factor x 64
rounded, 64..255 (1.0 .. ~4.0, capped), 0 = blocked.

Output sim/inputs/ways-fine.bin.zst: for every cell of
sim/inputs/landcover25.csv, in its order, row and col (int32 little endian),
then 256 bytes (tile row * 16 + tile col), as landcover-fine.bin.zst.

References
Soule, R. G., & Goldman, R. F. (1972). Terrain coefficients for energy cost
  prediction. Journal of Applied Physiology, 32(5), 706-708.
Tobler, W. (1993). Three presentations on geographical analysis and modeling
  (Technical Report 93-1). NCGIA.

    python3 tools/sim_ways.py
"""
import csv, json, math, pathlib, struct
import numpy as np
import zstandard
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
TT = ROOT / "artifacts/render-data/tile-terrain-r1"
OUT = ROOT / "sim/inputs/ways-fine.bin.zst"
CELL_KM = 25.0
FINE_KM = CELL_KM / 16
GROUND_COEF = {"meadow": 1.0, "dry_grass": 1.0, "field": 1.0, "wetland": 1.8, "scrub": 1.2, "sand": 2.1,
               "forest": 1.5, "conifer": 1.5, "alpine": 1.3, "rock": 1.6, "snow": 2.5}
FORD = 3.0
SCALE = 64


def unpack(path):
    p = np.asarray(Image.open(path))
    a = np.empty((p.shape[0], p.shape[1] * 2), np.uint8)
    a[:, 0::2] = p & 15
    a[:, 1::2] = p >> 4
    return a


def main():
    Image.MAX_IMAGE_PIXELS = None
    man = json.loads((TT / "manifest.json").read_text())
    wmin = man["node_grid"]["world_min"]
    lv = [l for l in man["levels"] if l["level"] == 0][0]
    gr = [g for g in man["ground"] if g["level"] == 0][0]
    ce = [c for c in man["cells"] if c["level"] == 0][0]
    steps = lv["level_steps_m"]
    lut = np.array([steps[k] if k < len(steps) else steps[-1] + (k - len(steps) + 1) * lv["beyond_m"] for k in range(256)], np.float32)
    h = lut[np.asarray(Image.open(TT / lv["path"]))]  # corners, metres
    ground = unpack(TT / gr["path"])[:, : ce["width"]]
    water = unpack(TT / ce["path"])[:, : ce["width"]] & 3
    n_r, n_c = water.shape
    km = lv["cell_km"]
    # steepest grade between the four corners of each 0.5-km tile (edges and diagonals)
    a, b, c, d = h[:-1, :-1], h[:-1, 1:], h[1:, :-1], h[1:, 1:]
    rise = np.maximum.reduce([abs(a - b), abs(c - d), abs(a - c), abs(b - d), abs(a - d) / 1.414, abs(b - c) / 1.414])
    grade = rise[:n_r, :n_c] / (km * 1000.0)
    tob = 0.5 * (np.exp(3.5 * np.abs(grade + 0.05)) + np.exp(3.5 * np.abs(-grade + 0.05))) / math.exp(3.5 * 0.05)
    coef = np.ones(16, np.float32)
    for name, k in zip(gr["classes"], range(len(gr["classes"]))):
        coef[k] = GROUND_COEF.get(name, 1.0)
    f = tob * coef[ground]
    f = np.where(water == 3, np.maximum(f, FORD), f)
    land = (water == 0) | (water == 3)
    # 0.5-km tile middles in world km, then their fine tile (absolute)
    xs = wmin[0] + (np.arange(n_c) + 0.5) * km
    zs = wmin[1] + (np.arange(n_r) + 0.5) * km
    fc = np.floor(xs / FINE_KM).astype(np.int64)
    fr = np.floor(zs / FINE_KM).astype(np.int64)
    cells = []
    with open(ROOT / "sim/inputs/landcover25.csv") as fh:
        for row in csv.DictReader(fh):
            cells.append((int(row["row"]), int(row["col"])))
    r0 = min(r for r, _ in cells) * 16
    c0 = min(c for _, c in cells) * 16
    nr = (max(r for r, _ in cells) + 1) * 16 - r0
    nc = (max(c for _, c in cells) + 1) * 16 - c0
    FR, FC = np.meshgrid(fr - r0, fc - c0, indexing="ij")
    ok = land & (FR >= 0) & (FC >= 0) & (FR < nr) & (FC < nc)
    idx = (FR * nc + FC)[ok]
    tot = np.bincount(idx, weights=f[ok].astype(np.float64), minlength=nr * nc)
    cnt = np.bincount(idx, minlength=nr * nc)
    val = np.where(cnt > 0, np.clip(np.rint(tot / np.maximum(cnt, 1) * SCALE), 1, 255), 0).astype(np.uint8).reshape(nr, nc)
    out = bytearray()
    blocked = 0
    for (r, c) in cells:
        out += struct.pack("<ii", r, c)
        t = val[r * 16 - r0 : r * 16 - r0 + 16, c * 16 - c0 : c * 16 - c0 + 16]
        blocked += int((t == 0).sum())
        out += t.tobytes()
    OUT.write_bytes(zstandard.ZstdCompressor(level=19).compress(bytes(out)))
    print(f"{OUT}: {len(cells)} cells, {blocked} fine tiles without land, {OUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
