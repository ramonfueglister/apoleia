#!/usr/bin/env python3
"""City plans on the parcel grid (docs/kit2/CITY_PLANS.md).

Reads the reconstructed plans in data/cities/<id>.json (walls, gates, river,
streets with rank and surface, buildings, quarters; real lon/lat) and lays
each onto the 0.25 km parcel grid of the tile terrain (one house lot per
parcel, aligned to its world_min). A city is drawn `scale` times its real
size about its centre (1 = the diorama scale of docs/kit2/SCALE.md).

    python3 tools/city_plans.py --scale 1 --preview out/      # PNG per city
    python3 tools/city_plans.py --scale 1 --out artifacts/render-data/city-plans-r1

Every parcel gets a kind (KINDS), the building it belongs to, and for
streets the rank, the surface and the links to its four neighbours, so a
street can be drawn from pieces (straight, bend, T, cross) as in Urbek.
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
CITY_DIR = ROOT / "data" / "cities"
# tools/build_tile_terrain.py: world km of the terrain grid
WORLD_MIN = (-5286.959516530886, -2223.9016046706583)
PARCEL_KM = 0.25
R_M = 6371008.8
LAT0, LON0 = 41.0, 19.0

KINDS = ["none", "house", "insula", "domus", "garden", "park", "street", "plaza",
         "building", "wall", "gate", "water", "bridge", "tombs"]
K = {k: i for i, k in enumerate(KINDS)}
RANKS = ["", "via", "vicus", "angiportus"]
SURFACES = ["", "basalt", "slabs", "gravel", "earth"]
# links to the eight neighbours, a bit per direction (i: east, j: south)
N, NE, E, SE, S, SW, W, NW = (1 << k for k in range(8))
STEP = {(0, -1): N, (1, -1): NE, (1, 0): E, (1, 1): SE, (0, 1): S, (-1, 1): SW, (-1, 0): W, (-1, -1): NW}
OPPOSITE = {N: S, NE: SW, E: W, SE: NW, S: N, SW: NE, W: E, NW: SE}
# Streets drawn at a scale: the main streets always, the quarter streets from
# 2x, the lanes from 3x (below that a parcel stands for more than one real
# block, and the lesser streets fall away as details do with the scale).
RANK_FROM_SCALE = ((1.5, 1), (2.5, 2), (math.inf, 3))
# tombs along the main roads out of the gates, real km
TOMBS_KM = 1.5
# Every house touches a street, as in Urbek and as Roman houses opened onto
# one: where the plan's streets leave houses without one, lanes are cut
# through the quarter, rows of two houses between east-west lanes and
# north-south lanes every LANE_EVERY_Q parcels (an own rule, hypothesis:
# blocks of 2 x 6 houses).
LANE_EVERY_R = 3
LANE_EVERY_Q = 7
DWELLING = ("house", "insula", "domus")
ACCESS = ("street", "plaza", "gate", "bridge")
# building kinds that streets may cross (open squares)
OPEN_BUILDINGS = {"forum", "plaza"}


def world_km(lon, lat):
    """data/projection.json: eqc, lat_ts = lat_0 = 41, lon_0 = 19, in km."""
    x = R_M * math.cos(math.radians(LAT0)) * math.radians(lon - LON0) / 1000.0
    z = -R_M * math.radians(lat - LAT0) / 1000.0
    return x, z


class Plan:
    def __init__(self, data, scale):
        self.data = data
        self.scale = scale
        self.cx, self.cz = world_km(*data["centre"])

    def km(self, p):
        """Plan point (lon, lat) -> world km, scaled about the centre."""
        x, z = world_km(p[0], p[1])
        return self.cx + self.scale * (x - self.cx), self.cz + self.scale * (z - self.cz)

    def cell(self, p):
        x, z = self.km(p)
        return (math.floor((x - WORLD_MIN[0]) / PARCEL_KM), math.floor((z - WORLD_MIN[1]) / PARCEL_KM))

    def cell_centre(self, i, j):
        return WORLD_MIN[0] + (i + 0.5) * PARCEL_KM, WORLD_MIN[1] + (j + 0.5) * PARCEL_KM


def walk(a, b):
    """4-connected cells from a to b (supercover of the segment between the
    cell centres), without a."""
    (i0, j0), (i1, j1) = a, b
    di, dj = i1 - i0, j1 - j0
    n = abs(di) + abs(dj)
    out = []
    i, j = i0, j0
    si, sj = (1 if di > 0 else -1), (1 if dj > 0 else -1)
    ei = ej = 0
    for _ in range(n):
        # step along the axis whose next crossing comes first
        ti = (ei + 0.5) / abs(di) if di else math.inf
        tj = (ej + 0.5) / abs(dj) if dj else math.inf
        if ti < tj:
            i += si
            ei += 1
        else:
            j += sj
            ej += 1
        out.append((i, j))
    return out


def walk8(a, b):
    """8-connected cells from a to b (Bresenham), without a."""
    (i0, j0), (i1, j1) = a, b
    di, dj = abs(i1 - i0), -abs(j1 - j0)
    si, sj = (1 if i1 > i0 else -1), (1 if j1 > j0 else -1)
    err = di + dj
    out = []
    i, j = i0, j0
    while (i, j) != (i1, j1):
        e2 = 2 * err
        if e2 >= dj:
            err += dj
            i += si
        if e2 <= di:
            err += di
            j += sj
        out.append((i, j))
    return out


def path(plan, line, step=walk):
    cells = [plan.cell(line[0])]
    for p in line[1:]:
        cells += step(cells[-1], plan.cell(p))
    return cells


def inside(poly, x, z):
    hit = False
    n = len(poly)
    for k in range(n):
        (x0, z0), (x1, z1) = poly[k], poly[(k + 1) % n]
        if (z0 > z) != (z1 > z) and x < x0 + (z - z0) * (x1 - x0) / (z1 - z0):
            hit = not hit
    return hit


def ring_polygon(plan, wall):
    """The wall ring in km, closed along the river where `closed_by` says so."""
    ring = [plan.km(p) for p in wall["ring"]]
    if wall.get("closed_by") == "river" and plan.data.get("rivers"):
        river = [plan.km(p) for p in plan.data["rivers"][0]["line"]]

        def nearest(q):
            return min(range(len(river)), key=lambda k: (river[k][0] - q[0]) ** 2 + (river[k][1] - q[1]) ** 2)

        a, b = nearest(ring[-1]), nearest(ring[0])
        step = 1 if b >= a else -1
        ring += [river[k] for k in range(a, b + step, step)]
    return ring


def footprint(plan, b):
    """Corners of a building's footprint in km (rectangle, or an ellipse for
    arenas), scaled with the plan."""
    cx, cz = plan.km(b["centre"])
    lx, lz = (s * plan.scale / 1000.0 for s in b["size_m"])
    a = math.radians(b.get("angle_deg", 0.0))
    if b["kind"] in ("amphitheatre", "theatre"):
        pts = [(lx / 2 * math.cos(t), lz / 2 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 24, endpoint=False)]
    else:
        pts = [(-lx / 2, -lz / 2), (lx / 2, -lz / 2), (lx / 2, lz / 2), (-lx / 2, lz / 2)]
    # angle: counter-clockwise on the map (north up), z points south
    return [(cx + x * math.cos(a) + z * math.sin(a), cz - x * math.sin(a) + z * math.cos(a)) for x, z in pts]


def build(data, scale, margin=6):
    plan = Plan(data, scale)
    pts = [w for wall in data.get("walls", []) for w in wall["ring"]]
    pts += [p for s in data.get("streets", []) for p in s["line"]]
    cells = [plan.cell(p) for p in pts]
    i0 = min(c[0] for c in cells) - margin
    j0 = min(c[1] for c in cells) - margin
    w = max(c[0] for c in cells) - i0 + 1 + margin
    h = max(c[1] for c in cells) - j0 + 1 + margin
    kind = np.zeros((h, w), np.uint8)
    bld = np.full((h, w), -1, np.int16)
    rank = np.zeros((h, w), np.uint8)
    surf = np.zeros((h, w), np.uint8)
    links = np.zeros((h, w), np.uint8)
    urban = np.zeros((h, w), bool)

    def ok(c):
        return 0 <= c[0] - i0 < w and 0 <= c[1] - j0 < h

    def at(c):
        return c[1] - j0, c[0] - i0

    def centre(r, q):
        return plan.cell_centre(q + i0, r + j0)

    # inside the walls
    polys = [ring_polygon(plan, wall) for wall in data.get("walls", [])]
    for r in range(h):
        for q in range(w):
            x, z = centre(r, q)
            urban[r, q] = any(inside(p, x, z) for p in polys)

    # river (at least one parcel wide) and its island
    for river in data.get("rivers", []):
        half = max(river["width_m"] * scale / 1000.0 / 2, 0.0)
        line = [plan.km(p) for p in river["line"]]
        for c in path(plan, river["line"]):
            if ok(c):
                kind[at(c)] = K["water"]
        if half > PARCEL_KM / 2:
            for r in range(h):
                for q in range(w):
                    x, z = centre(r, q)
                    if seg_dist(line, x, z) <= half:
                        kind[r, q] = K["water"]
    water = kind == K["water"]
    urban &= ~water

    # walls and gates
    for wall in data.get("walls", []):
        for c in path(plan, wall["ring"], walk8):
            if ok(c) and kind[at(c)] != K["water"]:
                kind[at(c)] = K["wall"]
    for g in data.get("gates", []):
        c = plan.cell(g["at"])
        if ok(c):
            kind[at(c)] = K["gate"]

    # buildings, largest first so a small one inside a big one stays seen
    order = sorted(range(len(data.get("buildings", []))), key=lambda k: -np.prod(data["buildings"][k]["size_m"]))
    for k in order:
        b = data["buildings"][k]
        poly = footprint(plan, b)
        xs, zs = [p[0] for p in poly], [p[1] for p in poly]
        hit = []
        for r in range(h):
            for q in range(w):
                x, z = centre(r, q)
                if min(xs) <= x <= max(xs) and min(zs) <= z <= max(zs) and inside(poly, x, z):
                    hit.append((r, q))
        if not hit:  # smaller than a parcel: the parcel under its centre
            c = plan.cell(b["centre"])
            hit = [at(c)] if ok(c) else []
        for r, q in hit:
            if kind[r, q] in (K["water"], K["wall"], K["gate"]):
                continue
            kind[r, q] = K["plaza"] if b["kind"] in OPEN_BUILDINGS else K["building"]
            bld[r, q] = k

    # streets, main ones first; a street ends at a closed building
    top = next(r for lim, r in RANK_FROM_SCALE if scale < lim)
    tomb_seed = []
    for s in sorted(data.get("streets", []), key=lambda s: RANKS.index(s["rank"])):
        if RANKS.index(s["rank"]) > top and not s.get("outside"):
            continue
        cs = path(plan, s["line"], walk8)
        if s.get("outside") and s["rank"] == "via":
            reach = TOMBS_KM * scale / PARCEL_KM
            tomb_seed += [c for c in cs if math.dist(c, cs[0]) <= reach]
        prev = None
        for c in cs:
            if not ok(c):
                prev = None
                continue
            r, q = at(c)
            kd = kind[r, q]
            if kd == K["building"] or kd == K["wall"]:
                prev = None
                continue
            if kd == K["water"]:
                kind[r, q] = K["bridge"]
            elif kd not in (K["gate"], K["plaza"], K["bridge"]):
                kind[r, q] = K["street"]
            if rank[r, q] == 0 or RANKS.index(s["rank"]) < rank[r, q]:
                rank[r, q] = RANKS.index(s["rank"])
                surf[r, q] = SURFACES.index(s["surface"])
            if prev is not None:
                d = STEP[(c[0] - prev[0], c[1] - prev[1])]
                links[at(prev)] |= d
                links[r, q] |= OPPOSITE[d]
            prev = c

    # houses inside the walls by quarter, tombs along the roads outside
    areas = data.get("areas", [])
    for r in range(h):
        for q in range(w):
            if kind[r, q] != K["none"]:
                continue
            x, z = centre(r, q)
            if urban[r, q]:
                kd = "house"
                best = math.inf
                for a in areas:
                    ax, az = plan.km(a["centre"])
                    d = math.hypot(x - ax, z - az) / (a["radius_m"] * scale / 1000.0)
                    if d < 1.0 and d < best:
                        best, kd = d, a["kind"]
                kind[r, q] = K["insula" if kd == "insulae" else kd]
    lanes(kind, rank, surf, links, SURFACES.index(data.get("lane_surface", "earth")))
    for c in tomb_seed:
        for dq, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + dq, c[1] + dr)
            if ok(n) and kind[at(n)] == K["none"] and not urban[at(n)]:
                kind[at(n)] = K["tombs"]

    return {"plan": plan, "i0": i0, "j0": j0, "kind": kind, "building": bld, "rank": rank,
            "surface": surf, "links": links, "urban": urban}


def lanes(kind, rank, surf, links, surface):
    """Cuts lanes so that every dwelling has a street on one of its four
    sides; picks the phase of the lane grid that cuts the fewest."""
    h, w = kind.shape
    dwell = np.isin(kind, [K[k] for k in DWELLING])
    access = np.isin(kind, [K[k] for k in ACCESS])

    def has_access(acc):
        out = np.zeros_like(acc)
        out[1:, :] |= acc[:-1, :]
        out[:-1, :] |= acc[1:, :]
        out[:, 1:] |= acc[:, :-1]
        out[:, :-1] |= acc[:, 1:]
        return out

    need = dwell & ~has_access(access)
    best = None
    rr, qq = np.mgrid[0:h, 0:w]
    for pr in range(LANE_EVERY_R):
        for pq in range(LANE_EVERY_Q):
            cut = dwell & (((rr - pr) % LANE_EVERY_R == 0) | ((qq - pq) % LANE_EVERY_Q == 0))
            # keep only cuts next to a house that lacks a street
            served = has_access(need & ~cut) & cut
            acc = access | served
            missing = int((dwell & ~served & ~has_access(acc)).sum())
            score = (missing, int(served.sum()))
            if best is None or score < best[0]:
                best = (score, served)
    lane = best[1]
    kind[lane] = K["street"]
    rank[lane] = RANKS.index("angiportus")
    surf[lane] = surface
    road = np.isin(kind, [K[k] for k in ACCESS])
    for r, q in zip(*np.nonzero(lane)):
        for (dq, dr), bit in STEP.items():
            if abs(dq) + abs(dr) != 1:
                continue
            r2, q2 = r + dr, q + dq
            if 0 <= r2 < h and 0 <= q2 < w and road[r2, q2]:
                links[r, q] |= bit
                links[r2, q2] |= OPPOSITE[bit]


def seg_dist(line, x, z):
    best = math.inf
    for (x0, z0), (x1, z1) in zip(line, line[1:]):
        dx, dz = x1 - x0, z1 - z0
        t = max(0.0, min(1.0, ((x - x0) * dx + (z - z0) * dz) / (dx * dx + dz * dz or 1)))
        best = min(best, math.hypot(x - x0 - t * dx, z - z0 - t * dz))
    return best


def stats(g):
    kind = g["kind"]
    out = {k: int((kind == K[k]).sum()) for k in KINDS[1:]}
    out["inside_walls"] = int(g["urban"].sum())
    return out


COLOURS = {
    "none": (226, 222, 196), "house": (214, 160, 120), "insula": (196, 120, 86), "domus": (232, 196, 150),
    "garden": (140, 176, 96), "park": (170, 196, 120), "street": (120, 120, 128), "plaza": (236, 228, 206),
    "building": (250, 246, 236), "wall": (150, 110, 80), "gate": (110, 70, 50), "water": (96, 150, 196),
    "bridge": (180, 170, 150), "tombs": (200, 196, 176),
}
SURFACE_COLOURS = {"basalt": (70, 74, 88), "slabs": (214, 206, 186), "gravel": (176, 160, 128), "earth": (150, 112, 76)}


def preview(g, data, path_png, px=20):
    from PIL import Image, ImageDraw, ImageFont
    kind = g["kind"]
    h, w = kind.shape
    head = 64
    img = Image.new("RGB", (w * px, h * px + head), (245, 242, 232))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 15)
        small = ImageFont.truetype("DejaVuSans.ttf", 11)
    except OSError:
        font = small = ImageFont.load_default()
    for r in range(h):
        for q in range(w):
            x, y = q * px, r * px + head
            kd = KINDS[kind[r, q]]
            col = COLOURS[kd]
            if kd in ("street", "bridge", "gate", "plaza") and g["links"][r, q]:
                base = COLOURS["none"] if not g["urban"][r, q] else COLOURS["house"]
                if kd == "plaza":
                    base = COLOURS["plaza"]
                if kd == "bridge":
                    base = COLOURS["water"]
                d.rectangle([x, y, x + px - 1, y + px - 1], fill=base)
                sc = SURFACE_COLOURS.get(SURFACES[g["surface"][r, q]], (90, 90, 90))
                wd = {1: px * 0.55, 2: px * 0.4, 3: px * 0.25}.get(int(g["rank"][r, q]), px * 0.4)
                m = px / 2
                lk = g["links"][r, q]
                d.ellipse([x + m - wd / 2, y + m - wd / 2, x + m + wd / 2, y + m + wd / 2], fill=sc)
                for (dq, dr), bit in STEP.items():
                    if lk & bit:
                        d.line([x + m, y + m, x + m + dq * m, y + m + dr * m], fill=sc, width=max(int(wd), 1))
                if kd == "gate":
                    d.rectangle([x + 2, y + 2, x + px - 3, y + px - 3], outline=COLOURS["gate"], width=3)
            else:
                d.rectangle([x, y, x + px - 1, y + px - 1], fill=col)
                if kd in ("house", "insula", "domus"):
                    d.rectangle([x + 2, y + 2, x + px - 3, y + px - 3], outline=tuple(int(c * 0.8) for c in col))
                if kd == "building":
                    d.rectangle([x, y, x + px - 1, y + px - 1], outline=(170, 160, 140))
    # numbers of the buildings at the middle of their parcels (names in the legend)
    labels = {}
    for r in range(h):
        for q in range(w):
            b = g["building"][r, q]
            if b >= 0:
                labels.setdefault(int(b), []).append((q, r))
    for b, cs in labels.items():
        q = sum(c[0] for c in cs) / len(cs) * px + px / 2
        r = sum(c[1] for c in cs) / len(cs) * px + head + px / 2
        rad = 8
        d.ellipse([q - rad, r - rad, q + rad, r + rad], fill=(255, 255, 255), outline=(60, 50, 40))
        d.text((q, r), str(b + 1), fill=(30, 20, 10), font=small, anchor="mm")
    st = stats(g)
    d.text((10, 8), f"Massstab {g['plan'].scale:g}x: {w} x {h} Parzellen", fill=(30, 30, 30), font=font)
    d.text((10, 32), f"in der Mauer {st['inside_walls']}: Wohnen {st['house'] + st['insula'] + st['domus']}, "
           f"Strassen {st['street'] + st['bridge']}, Bauten {st['building'] + st['plaza']}",
           fill=(60, 60, 60), font=small)
    if path_png:
        img.save(path_png)
    return img


def compare(data, scales, px, path_png):
    """The plans at several scales side by side, a parcel as big in each (a
    house is a house), with one legend of the buildings."""
    from PIL import Image, ImageDraw, ImageFont
    maps = [preview(build(data, sc), data, None, px) for sc in scales]
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 22)
        small = ImageFont.truetype("DejaVuSans.ttf", 13)
    except OSError:
        font = small = ImageFont.load_default()
    names = [b["name"] for b in data.get("buildings", [])]
    leg_w = 330
    gap = 24
    W = sum(m.width for m in maps) + gap * (len(maps) + 1) + leg_w
    H = max(max(m.height for m in maps), 60 + 18 * len(names) + 200) + 70
    img = Image.new("RGB", (W, H), (245, 242, 232))
    d = ImageDraw.Draw(img)
    d.text((gap, 18), f"{data['name']} {data['year']} n. Chr.: derselbe Plan in drei Massstäben, eine Parzelle (ein Haus, 10 m) überall gleich gross",
           fill=(30, 30, 30), font=font)
    x = gap
    for m in maps:
        img.paste(m, (x, 64))
        x += m.width + gap
    y = 70
    d.text((x, y), "Bauten", fill=(30, 30, 30), font=font)
    y += 34
    for k, n in enumerate(names):
        d.text((x, y), f"{k + 1:>2}  {n}", fill=(50, 40, 30), font=small)
        y += 18
    y += 16
    for kd in ("insula", "house", "domus", "garden", "building", "plaza", "wall", "water", "tombs"):
        d.rectangle([x, y, x + 14, y + 14], fill=COLOURS[kd], outline=(120, 110, 100))
        d.text((x + 22, y), {"insula": "Insulae (dicht)", "house": "Wohnhaus", "domus": "Domus", "garden": "Gärten",
                             "building": "öffentlicher Bau", "plaza": "Forum, Platz", "wall": "Mauer", "water": "Tiber",
                             "tombs": "Gräber an den Ausfallstrassen"}[kd], fill=(50, 40, 30), font=small)
        y += 20
    for sf, col in SURFACE_COLOURS.items():
        d.line([x, y + 7, x + 14, y + 7], fill=col, width=6)
        d.text((x + 22, y), {"basalt": "Basaltpflaster", "slabs": "Kalksteinplatten", "gravel": "Kies", "earth": "Erde"}[sf],
               fill=(50, 40, 30), font=small)
        y += 20
    img.save(path_png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--city", action="append")
    ap.add_argument("--preview", type=Path)
    ap.add_argument("--px", type=int, default=20)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--compare", help="scales side by side, e.g. 1,2,3 (with --preview)")
    a = ap.parse_args()
    ids = a.city or sorted(p.stem for p in CITY_DIR.glob("*.json"))
    if a.compare:
        a.preview.mkdir(parents=True, exist_ok=True)
        for cid in ids:
            data = json.loads((CITY_DIR / f"{cid}.json").read_text())
            compare(data, [float(v) for v in a.compare.split(",")], a.px, a.preview / f"{cid}-compare.png")
        return
    plans = {}
    for cid in ids:
        data = json.loads((CITY_DIR / f"{cid}.json").read_text())
        g = build(data, a.scale)
        print(cid, json.dumps(stats(g)))
        if a.preview:
            a.preview.mkdir(parents=True, exist_ok=True)
            preview(g, data, a.preview / f"{cid}-x{a.scale:g}.png", a.px)
        plans[cid] = g
    if a.out:
        write(plans, a.scale, a.out)


def write(plans, scale, out):
    out.mkdir(parents=True, exist_ok=True)
    doc = {"parcel_km": PARCEL_KM, "world_min": WORLD_MIN, "scale": scale, "kinds": KINDS, "ranks": RANKS,
           "surfaces": SURFACES, "links": "bits N=1 NE=2 E=4 SE=8 S=16 SW=32 W=64 NW=128; i east, j south", "cities": {}}
    for cid, g in plans.items():
        h, w = g["kind"].shape
        doc["cities"][cid] = {
            "origin": [int(g["i0"]), int(g["j0"])], "size": [int(w), int(h)],
            "buildings": [{"name": b["name"], "kind": b["kind"]} for b in g["plan"].data.get("buildings", [])],
            "kind": g["kind"].flatten().tolist(), "building": g["building"].flatten().tolist(),
            "rank": g["rank"].flatten().tolist(), "surface": g["surface"].flatten().tolist(),
            "links": g["links"].flatten().tolist(),
        }
    (out / f"plans-x{scale:g}.json").write_text(json.dumps(doc, separators=(",", ":")))


if __name__ == "__main__":
    main()
