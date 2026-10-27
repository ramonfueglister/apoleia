#!/usr/bin/env python3
"""Aggregate HYDE 3.3 (200 AD) population and cropland onto the 25 km cells.

Reads data/hyde33/popc_200AD_crop.asc.gz, cropland_200AD_crop.asc.gz and, if
present, rurc_200AD_crop.asc.gz (ESRI ASCII grids, 1/12 degree, people per cell
and km² per cell) and writes sim/inputs/hyde25.csv (row, col, crop_km2, pop200
[, rural200]) for every 25 km cell with land in sim/inputs/cells25.csv.

Each HYDE cell is split into 4×4 sub-points that are projected and binned, so
values follow the cell boundaries closely. Values that land on a cell without
land (coast mismatch between HYDE and our land mask) move to the nearest land
cell within 4 cells; anything further is dropped and reported.
"""
import csv
import gzip
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
R = 6371008.8
LAT0, LON0 = 41.0, 19.0
CELL_M = 25000.0
SUB = 4
SEARCH = 4


def read_asc(path):
    with gzip.open(path, "rt") as f:
        head = {}
        for _ in range(6):
            k, v = f.readline().split()
            head[k.lower()] = float(v)
        data = np.loadtxt(f, dtype=np.float64)
    data[data == head["nodata_value"]] = 0.0
    return head, data


def bin_grid(head, data, land, domain):
    ncols, nrows = int(head["ncols"]), int(head["nrows"])
    cs = head["cellsize"]
    west, north = head["xllcorner"], head["yllcorner"] + nrows * cs
    off = (np.arange(SUB) + 0.5) / SUB * cs
    out = {}
    lost = 0.0
    rows, cols = np.nonzero(data > 0)
    for i, j in zip(rows, cols):
        v = data[i, j] / (SUB * SUB)
        lons = west + j * cs + off
        lats = north - i * cs - off
        xs = R * math.cos(math.radians(LAT0)) * np.radians(lons - LON0)
        zs = -R * np.radians(lats - LAT0)
        for z in zs:
            r = math.floor(z / CELL_M)
            for x in xs:
                key = (r, math.floor(x / CELL_M))
                out[key] = out.get(key, 0.0) + v
    moved = {}
    for key, v in out.items():
        if key in land:
            moved[key] = moved.get(key, 0.0) + v
            continue
        if key not in domain:
            lost += v
            continue
        best = None
        for d in range(1, SEARCH + 1):
            ring = [(key[0] + a, key[1] + b) for a in range(-d, d + 1) for b in range(-d, d + 1)
                    if max(abs(a), abs(b)) == d and (key[0] + a, key[1] + b) in land]
            if ring:
                best = min(ring, key=lambda k: ((k[0] - key[0]) ** 2 + (k[1] - key[1]) ** 2, k))
                break
        if best is None:
            # Far out at sea.
            lost += v
        else:
            moved[best] = moved.get(best, 0.0) + v
    return moved, lost


def main():
    land = set()
    with open(ROOT / "data/gametiles/terrain-25km.csv") as f:
        domain = {(int(r["row"]), int(r["col"])) for r in csv.DictReader(f)}
    with open(ROOT / "sim/inputs/cells25.csv") as f:
        for r in csv.DictReader(f):
            land.add((int(r["row"]), int(r["col"])))
    hyde = ROOT / "data/hyde33"
    pop, pop_lost = bin_grid(*read_asc(hyde / "popc_200AD_crop.asc.gz"), land, domain)
    crop, crop_lost = bin_grid(*read_asc(hyde / "cropland_200AD_crop.asc.gz"), land, domain)
    rural = None
    if (hyde / "rurc_200AD_crop.asc.gz").exists():
        rural, rural_lost = bin_grid(*read_asc(hyde / "rurc_200AD_crop.asc.gz"), land, domain)
        print(f"rural200 in game area: {sum(rural.values()):,.0f} (outside/unplaced: {rural_lost:,.0f})")
    with open(ROOT / "sim/inputs/hyde25.csv", "w", newline="") as g:
        w = csv.writer(g)
        w.writerow(["row", "col", "crop_km2", "pop200"] + (["rural200"] if rural else []))
        for key in sorted(land):
            row = [key[0], key[1], round(crop.get(key, 0.0), 3), round(pop.get(key, 0.0), 1)]
            if rural:
                row.append(round(rural.get(key, 0.0), 1))
            w.writerow(row)
    print(f"pop200 in game area: {sum(pop.values()):,.0f} (outside/unplaced: {pop_lost:,.0f})")
    print(f"cropland in game area: {sum(crop.values()):,.0f} km² (outside/unplaced: {crop_lost:,.0f})")


if __name__ == "__main__":
    main()
