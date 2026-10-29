#!/usr/bin/env python3
"""Plans for the cities that are not reconstructed by hand (docs/kit2/CITY_PLANS.md).

From the facts of each city (data/cities/facts.json, Hanson 2016): its
area, walls, whether an orthogonal grid was found, forum or agora, and the
monuments. The plan is a dict in the format of data/cities/plans/*.json
(walls, gates, streets, extent) that tools/city_plans.py lays onto the
parcels; the buildings are placed on the parcels themselves (place()),
after the streets, by rules of where they stood in Roman towns.

Rules, sources and what is assumption are in docs/kit2/CITY_PLANS.md.
Everything is a pure function of the city's id: the same plan every time.
"""
import hashlib
import math

import numpy as np

import city_plans as cp

R_M = 6371008.8
# Hanson & Ortman (2017) as fitted in tools/gametiles_places.py: N = d * A^p (A in ha)
HO_D, HO_P = 42.08, 1.335
MIN_HA = 4.0  # the smallest town still has a street, a forum and a few houses

# Monument names of Hanson's database -> building kind and real size (m,
# long x short). Sizes: typical values of the kind, own estimate (marked
# so in the doc); the kind decides where it stands.
KINDS = [
    ("Forum", "forum", None), ("Agora", "agora", None),
    ("Capitolium", "temple", (40, 30)), ("Temple ('capitolium')", "temple", (40, 30)),
    ("Theatre", "theatre", (90, 75)), ("Odeum", "theatre", (50, 40)),
    ("Amphitheatre", "amphitheatre", (110, 85)),
    ("Circus", "circus", (400, 80)), ("Hippodrome", "circus", (400, 80)), ("Stadium", "stadium", (200, 35)),
    ("Baths", "baths", (70, 55)),
    ("Basilica", "public", (70, 28)), ("Curia", "public", (30, 20)), ("Bouleuterion", "public", (35, 30)),
    ("Gymnasium", "public", (80, 80)), ("Palaestra", "public", (50, 50)), ("Library", "public", (30, 25)),
    ("Macellum", "market", (45, 45)), ("Market", "market", (45, 45)),
    ("Stoa", "portico", (100, 20)),
    ("Temple", "temple", (30, 20)), ("Sanctuary", "temple", (60, 40)),
    ("Harbour", "harbour", (200, 60)),
    ("Fort", "fort", (180, 140)),
]
# how many of a kind a town gets (Ostia has 20 baths in the database; on
# parcels that would be the whole town): the first, and one more per this
# many hectares
ONE_MORE_PER_HA = {"baths": 80, "temple": 60, "public": 120, "market": 200, "theatre": 400}
# placing order: what matters most first
ORDER = ["forum", "agora", "temple_cap", "theatre", "amphitheatre", "baths", "public", "temple",
         "market", "circus", "stadium", "portico", "harbour", "fort"]
# public buildings take at most this share of the parcels in the town
MAX_PUBLIC_SHARE = 0.3


def h(cid, salt, n=1 << 30):
    return int(hashlib.sha256(f"{cid}:{salt}".encode()).hexdigest()[:12], 16) % n


def offset(lon, lat, dx_m, dz_m):
    """(lon, lat) moved dx_m east and dz_m south."""
    return (lon + math.degrees(dx_m / (R_M * math.cos(math.radians(41)))), lat - math.degrees(dz_m / R_M))


def area_ha(f):
    if "area_ha" in f:
        return max(f["area_ha"], MIN_HA)
    return max((max(f["pop117"], 1) / HO_D) ** (1 / HO_P), MIN_HA)


def region(f):
    """Surfaces by region (doc: Strassentypen)."""
    lon, lat = f["lon"], f["lat"]
    big = f["pop117"] >= 20000
    if 40.0 <= lat <= 43.0 and 11.0 <= lon <= 16.5:  # Latium, Campania: basalt
        return {"via": "basalt", "vicus": "basalt", "lane": "basalt" if big else "earth", "out": "basalt"}
    if lon >= 19.5 or lat <= 37.5:  # Greek east, Africa: limestone slabs
        return {"via": "slabs", "vicus": "slabs" if big else "gravel", "lane": "earth", "out": "gravel"}
    return {"via": "slabs" if big else "gravel", "vicus": "gravel", "lane": "earth", "out": "gravel"}


def wanted(f):
    """[(kind, size_m)] of the town's monuments, after the caps."""
    ha = area_ha(f)
    count = {}
    for m in f.get("monuments", []):
        if "?" in m:
            continue
        for name, kind, size in KINDS:
            if m.startswith(name):
                key = "temple_cap" if kind == "temple" and size == (40, 30) else kind
                count.setdefault(key, [kind, size, 0])[2] += 1
                break
    out = []
    for key in ORDER:
        if key not in count:
            continue
        kind, size, n = count[key]
        n = min(n, 1 + int(ha / ONE_MORE_PER_HA[kind])) if kind in ONE_MORE_PER_HA else 1
        out += [(key, kind, size)] * n
    if not any(k in ("forum", "agora") for k, _, _ in out):
        out.insert(0, ("forum", "forum", None))  # every town had a square
    return out


def on_land(lon, lat, terrain, reach_km=4.0):
    """The centre moved to the nearest parcel on land, when the terrain has
    water under it (coastal and island towns at the 0.5 km water cells, and
    towns under modern reservoirs such as Samosata)."""
    if terrain is None:
        return lon, lat
    x, z = cp.world_km(lon, lat)
    i0 = math.floor((x - cp.WORLD_MIN[0]) / cp.PARCEL_KM)
    j0 = math.floor((z - cp.WORLD_MIN[1]) / cp.PARCEL_KM)
    if terrain.water(i0, j0) == 0:
        return lon, lat
    n = int(reach_km / cp.PARCEL_KM)
    best = None
    for dj in range(-n, n + 1):
        for di in range(-n, n + 1):
            d = di * di + dj * dj
            if (best is None or d < best[0]) and terrain.water(i0 + di, j0 + dj) == 0:
                best = (d, di, dj)
    if best is None:
        return lon, lat
    return offset(lon, lat, best[1] * cp.PARCEL_KM * 1000, best[2] * cp.PARCEL_KM * 1000)


def plan(cid, f, scale, terrain=None):
    """The street plan of a city (format of data/cities/plans/*.json)."""
    lon, lat = on_land(f["lon"], f["lat"], terrain)
    ha = area_ha(f)
    mons = f.get("monuments", [])
    grid = any(m.startswith("Urban grid") and "?" not in m for m in mons)
    walls = any(m.startswith("Walls") and "?" not in m for m in mons) or "Walls" in f.get("area_basis", "")
    sf = region(f)
    r = math.sqrt(ha * 1e4 / math.pi)  # radius of the town (m)
    ring = []
    if grid:
        # an orthogonal town: a square with rounded corners on the parcel axes
        # (own simplification: real grids have their own orientation)
        half = math.sqrt(ha * 1e4) / 2
        for k in range(16):
            t = 2 * math.pi * k / 16
            c, s = math.cos(t), math.sin(t)
            p = 6.0  # superellipse: nearly square
            x = half * math.copysign(abs(c) ** (2 / p), c)
            z = half * math.copysign(abs(s) ** (2 / p), s)
            ring.append(offset(lon, lat, x, z))
    else:
        for k in range(14):
            t = 2 * math.pi * k / 14
            rr = r * (0.82 + 0.36 * h(cid, f"ring{k}", 1000) / 1000)
            ring.append(offset(lon, lat, rr * math.cos(t), rr * math.sin(t)))
    data = {"id": cid, "name": f.get("ancient", cid), "year": 301, "status": "generated",
            "centre": [lon, lat], "lane_surface": sf["lane"], "terrain_rivers": True, "streets": [], "gates": []}
    if walls:
        data["walls"] = [{"name": "Murus", "ring": ring + [ring[0]]}]
    else:
        data["extent"] = [ring]
    out_m = cp.TOMBS_KM * 1000 + r
    if grid:
        half = math.sqrt(ha * 1e4) / 2
        for name, (dx, dz) in (("cardo", (0, 1)), ("decumanus", (1, 0))):
            a = offset(lon, lat, -dx * half, -dz * half)
            b = offset(lon, lat, dx * half, dz * half)
            data["streets"].append({"name": f"{name} maximus", "rank": "via", "surface": sf["via"], "line": [a, b]})
            for sgn in (-1, 1):
                g = offset(lon, lat, sgn * dx * half, sgn * dz * half)
                data["gates"].append({"name": f"porta ({name})", "at": g})
                data["streets"].append({"name": "via", "rank": "via", "surface": sf["out"], "outside": True,
                                        "line": [g, offset(lon, lat, sgn * dx * out_m, sgn * dz * out_m)]})
        # the quarter streets of the grid: every 2 actus (71 m, Roman colonies,
        # own reading of the textbook value), shown from scale 2 (city_plans
        # RANK_FROM_SCALE)
        step = 71.0
        n = int(half // step)
        for k in range(-n, n + 1):
            if k == 0:
                continue
            for dx, dz in ((0, 1), (1, 0)):
                ox, oz = (k * step, 0) if dx == 0 else (0, k * step)
                a = offset(lon, lat, ox - dx * half, oz - dz * half)
                b = offset(lon, lat, ox + dx * half, oz + dz * half)
                data["streets"].append({"name": "vicus", "rank": "vicus", "surface": sf["vicus"], "line": [a, b]})
    else:
        # roads from the gates to the middle, bent a little (organic towns);
        # three or four of them, in hashed directions
        n = 3 + h(cid, "roads", 2)
        t0 = 2 * math.pi * h(cid, "t0", 1000) / 1000
        for k in range(n):
            t = t0 + 2 * math.pi * k / n + 0.5 * (h(cid, f"t{k}", 1000) / 1000 - 0.5)
            rr = r
            g = offset(lon, lat, rr * math.cos(t), rr * math.sin(t))
            bend = 0.25 * (h(cid, f"b{k}", 1000) / 1000 - 0.5)
            mid = offset(lon, lat, 0.5 * rr * math.cos(t + bend), 0.5 * rr * math.sin(t + bend))
            data["streets"].append({"name": "via", "rank": "via", "surface": sf["via"], "line": [[lon, lat], mid, g]})
            data["gates"].append({"name": "porta", "at": g})
            data["streets"].append({"name": "via", "rank": "via", "surface": sf["out"], "outside": True,
                                    "line": [g, offset(lon, lat, out_m * math.cos(t), out_m * math.sin(t))]})
    if not walls:
        data["gates"] = []
    return data


def place(cid, f, scale):
    """The hook for city_plans.build(): puts the town's buildings on free
    parcels by the rules of where they stood."""
    items = wanted(f)

    def run(g):
        kind, bld, urban = g["kind"], g["building"], g["urban"]
        h_, w_ = kind.shape
        plan_ = g["plan"]
        cq, cr = plan_.cell(plan_.data["centre"])
        cq, cr = cq - g["i0"], cr - g["j0"]
        inside = urban & (kind == cp.K["none"])
        budget = int(MAX_PUBLIC_SHARE * urban.sum()) + 1
        r_cells = math.sqrt(urban.sum() / math.pi) + 0.5
        g["buildings"] = []

        def parcels(size, kd):
            if size is None:  # the square grows with the town
                n = max(1, round(0.12 * math.sqrt(urban.sum())))
                return n, n
            grow = 1.0
            if kd in cp.LANDMARK_KINDS and max(size) >= cp.LANDMARK_FROM_M:
                grow = max(1.0, min(cp.LANDMARK_GROW / scale, cp.LANDMARK_LONG_M / (scale * max(size))))
            a = max(1, round(size[0] * scale * grow / (cp.PARCEL_KM * 1000)))
            b = max(1, round(size[1] * scale * grow / (cp.PARCEL_KM * 1000)))
            return a, b

        def free(q, r, a, b, outside):
            if q < 0 or r < 0 or q + a > w_ or r + b > h_:
                return False
            box = kind[r:r + b, q:q + a]
            if outside:
                return bool((box == cp.K["none"]).all() and not urban[r:r + b, q:q + a].any())
            return bool((box == cp.K["none"]).all() and urban[r:r + b, q:q + a].all())

        def spot(tq, tr, a, b, outside=False, reach=None):
            reach = reach or max(h_, w_)
            best = None
            for rr in range(max(0, int(tr) - reach), min(h_, int(tr) + reach + 1)):
                for qq in range(max(0, int(tq) - reach), min(w_, int(tq) + reach + 1)):
                    if free(qq, rr, a, b, outside):
                        d = (qq + a / 2 - tq) ** 2 + (rr + b / 2 - tr) ** 2
                        if best is None or d < best[0]:
                            best = (d, qq, rr)
            return best

        def put(name, kd, q, r, a, b):
            k = len(g["buildings"])
            g["buildings"].append({"name": name, "kind": kd})
            kind[r:r + b, q:q + a] = cp.K["plaza"] if kd in ("forum", "agora") else cp.K["building"]
            bld[r:r + b, q:q + a] = k

        used = 0
        for n, (key, kd, size) in enumerate(items):
            a, b = parcels(size, kd)
            if h(cid, f"rot{n}", 2):
                a, b = b, a
            if used + a * b > budget and kd not in ("forum", "agora"):
                continue
            t = 2 * math.pi * h(cid, f"dir{n}", 1000) / 1000
            if kd in ("forum", "agora"):
                # a village-sized town: its square beside the crossroads
                s = spot(cq + 0.5, cr + 0.5, a, b) or spot(cq + 0.5, cr + 0.5, a, b, outside=True, reach=2)
            elif kd in ("temple", "public", "market"):
                s = spot(cq + 0.5, cr + 0.5, a, b)  # round the square
            elif kd == "baths":
                s = spot(cq + 0.4 * r_cells * math.cos(t), cr + 0.4 * r_cells * math.sin(t), a, b)
            elif kd == "theatre":
                s = spot(cq + 0.6 * r_cells * math.cos(t), cr + 0.6 * r_cells * math.sin(t), a, b)
            elif kd in ("amphitheatre", "circus", "stadium"):
                # at the edge or before the walls
                s = spot(cq + (r_cells + 1.5) * math.cos(t), cr + (r_cells + 1.5) * math.sin(t), a, b, outside=True, reach=4)
                s = s or spot(cq + 0.8 * r_cells * math.cos(t), cr + 0.8 * r_cells * math.sin(t), a, b)
            elif kd == "harbour":
                water = np.argwhere(kind == cp.K["water"])
                if len(water) == 0:
                    continue
                wr, wq = water[np.argmin((water[:, 0] - cr) ** 2 + (water[:, 1] - cq) ** 2)]
                s = spot(wq, wr, a, b) or spot(wq, wr, a, b, outside=True, reach=3)
            else:
                s = spot(cq + 0.5 * r_cells * math.cos(t), cr + 0.5 * r_cells * math.sin(t), a, b)
            if s is None:
                continue
            put(key, kd, s[1], s[2], a, b)
            used += a * b
        del inside

    return run


def build(cid, f, scale, terrain):
    data = plan(cid, f, scale, terrain)
    hook = place(cid, f, scale)
    holder = {}

    def run(g):
        hook(g)
        holder["buildings"] = g["buildings"]

    grid = cp.build(data, scale, terrain=terrain, hook=run)
    data["buildings"] = holder.get("buildings", [])
    grid["plan"].data = data
    return data, grid
