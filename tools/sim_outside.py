#!/usr/bin/env python3
"""People and cropland beyond the map's edges (S121), from HYDE 3.3 (200 AD).

The map is the rectangle of data/region.json. Beyond each of its four edges
lies a band of OUT_KM (500 km, sim/src/grain.rs) where the markets beyond
the map stand. For each band this sums HYDE's population and cropland and
takes the population-weighted longitude and latitude (the market's place;
the latitude gives the harvest day), and prints
the rows of `OUTERS` in sim/src/grain/outside.rs:

    python3 tools/sim_outside.py

Corners belong to the north and south bands. Reads
data/hyde33/popc_200AD_crop.asc.gz and cropland_200AD_crop.asc.gz
(Klein Goldewijk, 2024; CC BY 4.0, data/hyde33/SOURCE.md).
"""
import gzip
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT_KM = 500.0
KM_PER_DEG = 111.32


def read_asc(path):
    with gzip.open(path, "rt") as f:
        head = {}
        for _ in range(6):
            k, v = f.readline().split()
            head[k.lower()] = float(v)
        data = np.loadtxt(f, dtype=np.float64)
    data[data == head["nodata_value"]] = 0.0
    return head, data


def main():
    ext = json.loads((ROOT / "data/region.json").read_text())["extent"]
    w, e, s, n = ext["west"], ext["east"], ext["south"], ext["north"]
    head, pop = read_asc(ROOT / "data/hyde33/popc_200AD_crop.asc.gz")
    _, crop = read_asc(ROOT / "data/hyde33/cropland_200AD_crop.asc.gz")
    rows, cols = pop.shape
    cs = head["cellsize"]
    lat = head["yllcorner"] + (rows - np.arange(rows) - 0.5) * cs
    lon = head["xllcorner"] + (np.arange(cols) + 0.5) * cs
    la, lo = np.meshgrid(lat, lon, indexing="ij")
    deg = OUT_KM / KM_PER_DEG
    km_lon = KM_PER_DEG * np.cos(np.radians(la))
    wide = ((w - lo) * km_lon <= OUT_KM) & ((lo - e) * km_lon <= OUT_KM)
    bands = {
        "EAST": (lo >= e) & ((lo - e) * km_lon <= OUT_KM) & (la >= s) & (la < n),
        "SOUTH": (la < s) & (la >= s - deg) & wide,
        "NORTH": (la >= n) & (la < n + deg) & wide,
        "WEST": (lo < w) & ((w - lo) * km_lon <= OUT_KM) & (la >= s) & (la < n),
    }
    for side, m in bands.items():
        people = pop[m].sum()
        lon_w = (pop[m] * lo[m]).sum() / max(people, 1.0)
        lat_w = (pop[m] * la[m]).sum() / max(people, 1.0)
        ha = crop[m].sum() * 100 / max(people, 1.0)
        print(f"    // {side}: {people / 1e6:.2f} M people, {ha:.2f} ha cropland a head, at {lon_w:.1f}° E {lat_w:.1f}° N")
        print(f"    ({side}, {people:.0f}, {lon_w * 10:.0f}, {lat_w * 10:.0f}),")
    inside = (lo >= w) & (lo < e) & (la >= s) & (la < n)
    print(f"    // map: {pop[inside].sum() / 1e6:.2f} M people, {crop[inside].sum() * 100 / pop[inside].sum():.2f} ha cropland a head")


if __name__ == "__main__":
    main()
