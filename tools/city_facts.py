#!/usr/bin/env python3
"""Facts per city of the simulation for the city plans (tools/city_plans.py),
from Hanson's cities database (Hanson 2016, OxREP; the same mirror as
tools/gametiles_places.py): ancient name, area and what it rests on, civic
status, dates, and the monuments found (theatre, baths, urban grid, walls ...).

    python3 tools/city_facts.py                  # -> data/cities/facts.json

Each city of sim/inputs/cities.csv takes the Hanson site nearest to it
within MATCH_M (853 of 860 match at the time of writing).
"""
import csv
import json
import math
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
URL = "https://raw.githubusercontent.com/wccarleton/urbanscale/HEAD/Data/Hanson2016_CitiesDatabase_OxREP.xlsx"
SHA256 = "582e326ad1cb1525ba8f36c69c2ab2b43d8d3c3b82138f085df1c9b97bb7a078"
CACHE = Path.home() / ".cache" / "apoleia" / "Hanson2016_CitiesDatabase_OxREP.xlsx"
OUT = ROOT / "data" / "cities" / "facts.json"
MATCH_M = 5000
R_M = 6371008.8


def xy(lon, lat):
    return (R_M * math.cos(math.radians(41)) * math.radians(lon - 19), -R_M * math.radians(lat - 41))


def lonlat(x, z):
    return (19 + math.degrees(x / (R_M * math.cos(math.radians(41)))), 41 - math.degrees(z / R_M))


def fetch():
    import hashlib
    if not CACHE.exists():
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(URL, CACHE)
    got = hashlib.sha256(CACHE.read_bytes()).hexdigest()
    if got != SHA256:
        raise SystemExit(f"{CACHE}: sha256 {got}, expected {SHA256}")
    return CACHE


def main():
    import pandas as pd
    x = pd.read_excel(fetch(), sheet_name=None)
    cities, areas, mons, status = x["Cities"], x["Areas"], x["Monuments"], x["Civic Status"]
    area = {r["Primary Key"]: (float(r["Area"]), str(r["Estimate Basis"])) for _, r in areas.iterrows() if pd.notna(r["Area"])}
    mon = mons.groupby("Primary Key")["Structure"].apply(lambda s: sorted(str(v) for v in s if pd.notna(v))).to_dict()
    civ = status.groupby("Primary Key")["Civic Status"].apply(lambda s: sorted({str(v) for v in s if pd.notna(v)})).to_dict()
    sites = []
    for _, r in cities.iterrows():
        if pd.isna(r["Longitude (X)"]):
            continue
        sites.append((r, *xy(float(r["Longitude (X)"]), float(r["Latitude (Y)"]))))
    out = {}
    for c in csv.DictReader(open(ROOT / "sim" / "inputs" / "cities.csv")):
        X, Z = float(c["x_m"]), float(c["z_m"])
        r, hx, hz = min(sites, key=lambda s: (s[1] - X) ** 2 + (s[2] - Z) ** 2)
        lon, lat = lonlat(X, Z)
        e = {"lon": round(lon, 5), "lat": round(lat, 5), "pop117": int(c["pop117"])}
        if math.hypot(hx - X, hz - Z) <= MATCH_M:
            k = r["Primary Key"]
            e.update({
                "hanson": k, "ancient": str(r["Ancient Toponym"]), "province": str(r["Province"]),
                "start": None if pd.isna(r["Start Date"]) else int(r["Start Date"]),
                "end": None if pd.isna(r["End Date"]) else int(r["End Date"]),
                "monuments": mon.get(k, []), "civic": civ.get(k, []),
            })
            if k in area:
                e["area_ha"], e["area_basis"] = area[k]
        out[c["id"]] = e
    doc = {
        "source": "Hanson, J. W. (2016). An urban geography of the Roman world, 100 BC to AD 300. Archaeopress. "
                  "OxREP cities database, mirror " + URL,
        "rule": f"each city of sim/inputs/cities.csv takes the nearest Hanson site within {MATCH_M} m",
        "cities": out,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=0, sort_keys=True))
    print(len(out), "cities,", sum("hanson" in e for e in out.values()), "matched")


if __name__ == "__main__":
    main()
