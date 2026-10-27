#!/usr/bin/env python3
"""Build the inputs for the Kit 2 population prototype from data/gametiles.

Writes sim/inputs/cells25.csv (one row per 25 km terrain cell with land) and
sim/inputs/cities.csv (cities with a population estimate for 117 AD, in model
metres). Values are derived only; estimation parameters live in the Rust code.
"""
import csv
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
R = 6371008.8
LAT0, LON0 = 41.0, 19.0
# Terrain samples lie on a 1/300 degree grid; in this projection every sample
# covers the same area (constant x and z spacing).
STEP = math.pi / 180 / 300
SAMPLE_KM2 = (R * math.cos(math.radians(LAT0)) * STEP) * (R * STEP) / 1e6


def project(lon, lat):
    x = R * math.cos(math.radians(LAT0)) * math.radians(lon - LON0)
    z = -R * math.radians(lat - LAT0)
    return x, z


def main():
    out = ROOT / "sim" / "inputs"
    out.mkdir(parents=True, exist_ok=True)
    with open(ROOT / "data/gametiles/terrain-25km.csv") as f, open(out / "cells25.csv", "w", newline="") as g:
        w = csv.writer(g)
        w.writerow(["row", "col", "land_km2", "frac_bare", "frac_snow", "frac_above_1500m"])
        for r in csv.DictReader(f):
            land = int(r["land_samples"])
            if land == 0:
                continue
            w.writerow([r["row"], r["col"], round(land * SAMPLE_KM2, 4),
                        r["frac_land_bare"] or 0, r["frac_land_snow"] or 0,
                        r["frac_land_above_1500m"] or 0])
    with open(ROOT / "data/gametiles/places.csv") as f, open(out / "cities.csv", "w", newline="") as g:
        w = csv.writer(g)
        w.writerow(["id", "x_m", "z_m", "pop117"])
        for r in csv.DictReader(f):
            if not r["p117"]:
                continue
            x, z = project(float(r["lon"]), float(r["lat"]))
            w.writerow([r["id"], round(x, 1), round(z, 1), int(float(r["p117"]))])


if __name__ == "__main__":
    main()
