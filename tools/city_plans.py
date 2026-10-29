#!/usr/bin/env python3
"""City plans on the parcel grid (docs/kit2/CITY_PLANS.md).

Reads the reconstructed plans in data/cities/plans/<id>.json (walls, gates, river,
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
CITY_DIR = ROOT / "data" / "cities" / "plans"
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
# links to the four neighbours, a bit per direction (i: east, j: south);
# streets are 4-connected, so a street is drawn from Urbek's pieces
N, E, S, W = 1, 2, 4, 8
STEP = {(0, -1): N, (1, 0): E, (0, 1): S, (-1, 0): W}
OPPOSITE = {N: S, S: N, E: W, W: E}
# Streets drawn at a scale: the main streets always, the quarter streets from
# 2x, the lanes from 3x (below that a parcel stands for more than one real
# block, and the lesser streets fall away as details do with the scale).
RANK_FROM_SCALE = ((1.5, 1), (2.5, 2), (math.inf, 3))
# tombs along the main roads out of the gates, real km
TOMBS_KM = 1.5
# the first part of that stretch is suburb (houses), the rest tombs
SUBURB_SHARE = 0.5
# Every house touches a street, as in Urbek and as Roman houses opened onto
# one: where the plan's streets leave houses without one, lanes are cut
# through the quarter, rows of two houses between east-west lanes and
# north-south lanes every LANE_EVERY_Q parcels (an own rule, hypothesis:
# blocks of 2 x 6 houses).
LANE_EVERY_R = 3
LANE_EVERY_Q = 7
DWELLING = ("house", "insula", "domus")
ACCESS = ("street", "plaza", "gate", "bridge")
# Landmarks keep their real place but are drawn larger than their real
# footprint, so they stay readable where a parcel stands for a whole real
# block (Ramon's choice pending, plan doc): LANDMARK_GROW at scale 1, less
# at larger scales, for buildings of these kinds at least LANDMARK_FROM_M long.
LANDMARK_GROW = 2.5
LANDMARK_FROM_M = 100
LANDMARK_LONG_M = 500  # grown no longer than this (two parcels at scale 1)
LANDMARK_KINDS = {"amphitheatre", "circus", "baths", "palace", "theatre", "stadium", "temple", "forum", "market", "tomb"}
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


# buildings placed before the others where they compete for parcels
FAMOUS = {"Amphitheatrum Flavium", "Forum Romanum", "Circus Maximus", "Thermae Antoninianae", "Pantheon",
          "Thermae Diocletiani", "Palatium", "Forum Traiani", "Capitolium (Iuppiter Optimus Maximus)"}


def parcel_size(plan, b):
    """A building's extent in km along the parcel axes (grown if a
    landmark): its long side runs east-west unless turned more than 45
    degrees."""
    grow = 1.0
    if b.get("landmark", b["kind"] in LANDMARK_KINDS and max(b["size_m"]) >= LANDMARK_FROM_M):
        grow = max(1.0, min(LANDMARK_GROW / plan.scale, LANDMARK_LONG_M / (plan.scale * max(b["size_m"]))))
    lx, lz = (v * plan.scale * grow / 1000.0 for v in b["size_m"])
    if 45 < abs(b.get("angle_deg", 0.0)) % 180 < 135:
        lx, lz = lz, lx
    return lx, lz


def footprint(plan, b):
    """Corners of a building's footprint in km (rectangle, or an ellipse for
    arenas), scaled with the plan."""
    cx, cz = plan.km(b["centre"])
    grow = 1.0
    if b.get("landmark", b["kind"] in LANDMARK_KINDS and max(b["size_m"]) >= LANDMARK_FROM_M):
        grow = min(LANDMARK_GROW / plan.scale, max(1.0, LANDMARK_LONG_M / (plan.scale * max(b["size_m"]))))
        grow = max(grow, 1.0)
    lx, lz = (s * plan.scale * grow / 1000.0 for s in b["size_m"])
    a = math.radians(b.get("angle_deg", 0.0))
    if b["kind"] in ("amphitheatre", "theatre"):
        pts = [(lx / 2 * math.cos(t), lz / 2 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 24, endpoint=False)]
    else:
        pts = [(-lx / 2, -lz / 2), (lx / 2, -lz / 2), (lx / 2, lz / 2), (-lx / 2, lz / 2)]
    # angle: counter-clockwise on the map (north up), z points south
    return [(cx + x * math.cos(a) + z * math.sin(a), cz - x * math.sin(a) + z * math.cos(a)) for x, z in pts]


class Terrain:
    """Water of the tile terrain's 0.5 km cells (cells-L0.png: two cells a
    byte, bits 0-1: 0 land, 1 sea, 2 lake, 3 river)."""
    DIR = ROOT / "artifacts" / "render-data" / "tile-terrain-r1"

    def __init__(self):
        from PIL import Image
        Image.MAX_IMAGE_PIXELS = None
        e = json.loads((self.DIR / "manifest.json").read_text())["cells"][0]
        assert e["cell_km"] == 2 * PARCEL_KM
        self.packed = np.array(Image.open(self.DIR / e["path"]).convert("L"))
        self.width = e["width"]

    def water(self, i, j):
        """Water class under parcel (i, j)."""
        I, J = i // 2, j // 2
        if not (0 <= I < self.width and 0 <= J < self.packed.shape[0]):
            return 1
        b = int(self.packed[J, I // 2])
        return (b if I % 2 == 0 else b >> 4) & 3


def build(data, scale, margin=6, terrain=None, hook=None):
    """The parcel map of a plan. `terrain`: a Terrain, whose sea and lakes
    (and rivers, where the plan says `terrain_rivers`) become water;
    `hook(grid)`: called after the streets, before the houses (the
    generated plans place their buildings there)."""
    plan = Plan(data, scale)
    pts = [w for wall in data.get("walls", []) for w in wall["ring"]]
    pts += [p for ring in data.get("extent", []) for p in ring]
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
    polys += [[plan.km(p) for p in ring] for ring in data.get("extent", [])]
    for r in range(h):
        for q in range(w):
            x, z = centre(r, q)
            urban[r, q] = any(inside(p, x, z) for p in polys)
    if polys and not urban.any():  # a town smaller than a parcel: its parcel
        urban[at(plan.cell(data["centre"]))] = True

    # river (at least one parcel wide) and its island; streets cross rivers
    # on bridges, never the sea
    river = np.zeros((h, w), bool)
    for rv in data.get("rivers", []):
        half = max(rv["width_m"] * scale / 1000.0 / 2, 0.0)
        line = [plan.km(p) for p in rv["line"]]
        for c in path(plan, rv["line"]):
            if ok(c):
                river[at(c)] = True
        if half > PARCEL_KM / 2:
            for r in range(h):
                for q in range(w):
                    x, z = centre(r, q)
                    if seg_dist(line, x, z) <= half:
                        river[r, q] = True
    sea = np.zeros((h, w), bool)
    if terrain is not None:
        rivers = data.get("terrain_rivers", False)
        for r in range(h):
            for q in range(w):
                wc = terrain.water(q + i0, r + j0)
                if wc in (1, 2):
                    sea[r, q] = True
                elif wc == 3 and rivers:
                    river[r, q] = True
    kind[river | sea] = K["water"]
    water = kind == K["water"]
    urban &= ~water

    # walls round the town (the parcels just outside it), gates where the
    # plan has them and wherever a main street goes through
    if data.get("walls"):
        ring = np.zeros((h, w), bool)
        ring[1:, :] |= urban[:-1, :]
        ring[:-1, :] |= urban[1:, :]
        ring[:, 1:] |= urban[:, :-1]
        ring[:, :-1] |= urban[:, 1:]
        ring &= ~urban & ~water
        kind[ring] = K["wall"]
        wall_cells = np.argwhere(ring)
        for g in data.get("gates", []):
            q, r = plan.cell(g["at"])
            q, r = q - i0, r - j0
            if len(wall_cells):
                k = np.argmin((wall_cells[:, 0] - r) ** 2 + (wall_cells[:, 1] - q) ** 2)
                if (wall_cells[k, 0] - r) ** 2 + (wall_cells[k, 1] - q) ** 2 <= 4:
                    kind[tuple(wall_cells[k])] = K["gate"]

    # buildings as rectangles of parcels at their place, the landmarks and
    # the big ones first; one that finds its place taken moves to the
    # nearest free one within two parcels, or merges into its neighbour
    blocked = (K["water"], K["wall"], K["gate"], K["bridge"], K["building"], K["plaza"])

    def rect(b):
        x, z = plan.km(b["centre"])
        lx, lz = parcel_size(plan, b)
        a_, b_ = max(1, round(lx / PARCEL_KM)), max(1, round(lz / PARCEL_KM))
        q0 = math.floor((x - WORLD_MIN[0]) / PARCEL_KM - a_ / 2 + 0.5) - i0
        r0 = math.floor((z - WORLD_MIN[1]) / PARCEL_KM - b_ / 2 + 0.5) - j0
        return q0, r0, a_, b_

    def fits(q0, r0, a_, b_):
        if q0 < 0 or r0 < 0 or q0 + a_ > w or r0 + b_ > h:
            return False
        return not np.isin(kind[r0:r0 + b_, q0:q0 + a_], blocked).any()

    order = sorted(range(len(data.get("buildings", []))),
                   key=lambda k: (not data["buildings"][k].get("landmark", False) and data["buildings"][k]["name"] not in FAMOUS,
                                  -np.prod(data["buildings"][k]["size_m"])))
    for k in order:
        b = data["buildings"][k]
        q0, r0, a_, b_ = rect(b)
        spot = None
        for d in range(3):
            cands = [(q0 + dq, r0 + dr) for dq in range(-d, d + 1) for dr in range(-d, d + 1) if max(abs(dq), abs(dr)) == d]
            for q1, r1 in cands:
                if fits(q1, r1, a_, b_):
                    spot = (q1, r1)
                    break
            if spot:
                break
        if spot is None:
            continue
        kind[spot[1]:spot[1] + b_, spot[0]:spot[0] + a_] = K["plaza"] if b["kind"] in OPEN_BUILDINGS else K["building"]
        bld[spot[1]:spot[1] + b_, spot[0]:spot[0] + a_] = k

    # streets, main ones first; a street stops at a closed building and goes on
    # beyond it (people walk round the Colosseum)
    top = next(r for lim, r in RANK_FROM_SCALE if scale < lim)
    tomb_seed = []
    for s in sorted(data.get("streets", []), key=lambda s: RANKS.index(s["rank"])):
        if RANKS.index(s["rank"]) > top and not s.get("outside"):
            continue
        cs = path(plan, s["line"])
        if s.get("outside") and s["rank"] == "via":
            reach = TOMBS_KM * scale / PARCEL_KM
            tomb_seed += [(c, math.dist(c, cs[0]) / reach) for c in cs if math.dist(c, cs[0]) <= reach]
        prev = None
        for c in cs:
            if not ok(c):
                prev = None
                continue
            r, q = at(c)
            kd = kind[r, q]
            if kd == K["wall"] and s["rank"] == "via":
                kind[r, q] = kd = K["gate"]
            if kd == K["building"] or kd == K["wall"] or sea[r, q]:
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

    if hook is not None:
        hook({"plan": plan, "i0": i0, "j0": j0, "kind": kind, "building": bld, "rank": rank,
              "surface": surf, "urban": urban})

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
    connect(kind, rank, surf, SURFACES.index(data.get("lane_surface", "earth")))
    relink(kind, links)
    for c, f in tomb_seed:
        for dq, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c[0] + dq, c[1] + dr)
            if ok(n) and kind[at(n)] == K["none"] and not urban[at(n)]:
                kind[at(n)] = K["house" if f < SUBURB_SHARE else "tombs"]

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
            r2, q2 = r + dr, q + dq
            if 0 <= r2 < h and 0 <= q2 < w and road[r2, q2]:
                links[r, q] |= bit
                links[r2, q2] |= OPPOSITE[bit]


ROAD = ("street", "plaza", "gate", "bridge")
# what a joining lane may cut through, and at what cost
# (never across open land, water or buildings; through a wall only as a new gate)
CUT_COST = {"house": 1, "insula": 1, "domus": 1, "garden": 2, "park": 2, "tombs": 4, "wall": 12}


def components(road):
    h, w = road.shape
    comp = np.full((h, w), -1, np.int32)
    n = 0
    for r0, q0 in zip(*np.nonzero(road)):
        if comp[r0, q0] >= 0:
            continue
        stack = [(r0, q0)]
        comp[r0, q0] = n
        while stack:
            r, q = stack.pop()
            for dr, dq in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                r2, q2 = r + dr, q + dq
                if 0 <= r2 < h and 0 <= q2 < w and road[r2, q2] and comp[r2, q2] < 0:
                    comp[r2, q2] = n
                    stack.append((r2, q2))
        n += 1
    return comp, n


def connect(kind, rank, surf, surface):
    """Joins every piece of the street network to the rest with the
    cheapest lane (Dijkstra through houses and gardens, through a wall as a new
    gate, never across open land), so that one can
    walk from any street to any other, as the walkers will."""
    import heapq
    h, w = kind.shape
    cost = np.full((h, w), np.inf)
    for k, c in CUT_COST.items():
        cost[kind == K[k]] = c
    skip = np.zeros((h, w), bool)  # pieces that cannot be joined
    for _ in range(256):
        road = np.isin(kind, [K[k] for k in ROAD])
        comp, n = components(road & ~skip)
        if n <= 1:
            return
        sizes = np.bincount(comp[comp >= 0])
        main = int(np.argmax(sizes))
        # from the smallest piece to any other piece
        src = int(np.argmin(np.where(np.arange(n) == main, 1 << 30, sizes)))
        dist = np.full((h, w), np.inf)
        prev = {}
        heap = []
        for r, q in zip(*np.nonzero(comp == src)):
            dist[r, q] = 0
            heap.append((0.0, int(r), int(q)))
        heapq.heapify(heap)
        goal = None
        while heap:
            d, r, q = heapq.heappop(heap)
            if d > dist[r, q]:
                continue
            if road[r, q] and comp[r, q] != src and not skip[r, q]:
                goal = (r, q)
                break
            for dr, dq in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                r2, q2 = r + dr, q + dq
                if not (0 <= r2 < h and 0 <= q2 < w):
                    continue
                step = 0.0 if road[r2, q2] else cost[r2, q2]
                if d + step < dist[r2, q2]:
                    dist[r2, q2] = d + step
                    prev[(r2, q2)] = (r, q)
                    heapq.heappush(heap, (d + step, r2, q2))
        if goal is None:  # cut off behind water or walls: left as it is
            skip |= comp == src
            continue
        c = prev.get(goal)
        while c is not None and comp[c] != src:
            if kind[c] == K["wall"]:
                kind[c] = K["gate"]
            elif not road[c]:
                kind[c] = K["street"]
                rank[c] = RANKS.index("angiportus")
                surf[c] = surface
            c = prev.get(c)


def relink(kind, links):
    """Neighbouring street parcels join, as road tiles do in Urbek."""
    road = np.isin(kind, [K[k] for k in ROAD])
    links[:] = 0
    links[:-1, :] |= np.where(road[:-1, :] & road[1:, :], S, 0).astype(np.uint8)
    links[1:, :] |= np.where(road[1:, :] & road[:-1, :], N, 0).astype(np.uint8)
    links[:, :-1] |= np.where(road[:, :-1] & road[:, 1:], E, 0).astype(np.uint8)
    links[:, 1:] |= np.where(road[:, 1:] & road[:, :-1], W, 0).astype(np.uint8)


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
    d.text((10, 8), f"{data.get('name', '')}, Massstab {g['plan'].scale:g}x: {w} x {h} Parzellen", fill=(30, 30, 30), font=font)
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
    ap.add_argument("--bake", type=Path, help="write the parcel map of every city to this folder")
    ap.add_argument("--compare", help="scales side by side, e.g. 1,2,3 (with --preview)")
    a = ap.parse_args()
    ids = a.city or sorted(p.stem for p in CITY_DIR.glob("*.json"))
    if a.compare:
        a.preview.mkdir(parents=True, exist_ok=True)
        for cid in ids:
            data = json.loads((CITY_DIR / f"{cid}.json").read_text())
            compare(data, [float(v) for v in a.compare.split(",")], a.px, a.preview / f"{cid}-compare.png")
        return
    if a.bake:
        bake(a.scale, a.bake, ids if a.city else None)
        return
    for cid in ids:
        data = json.loads((CITY_DIR / f"{cid}.json").read_text())
        g = build(data, a.scale)
        print(cid, json.dumps(stats(g)))
        if a.preview:
            a.preview.mkdir(parents=True, exist_ok=True)
            preview(g, data, a.preview / f"{cid}-x{a.scale:g}.png", a.px)


# The baked parcel map (docs/kit2/CITY_PLANS.md, read by app/scripts/city_plans.gd):
# pages of PAGE x PAGE parcels aligned to world_min, those holding a city
# stored as slots of an RGB8 atlas, ATLAS_SLOTS slots a row.
PAGE = 64
ATLAS_SLOTS = 32
# R: what stands on the parcel (0: no plan, the tile terrain's own town rule)
CODES = ["none", "house", "insula", "domus", "building", "plaza", "garden", "street", "wall", "gate",
         "bridge", "tombs", "land", "water"]
C = {k: i for i, k in enumerate(CODES)}
KIND_CODE = {"none": "land", "house": "house", "insula": "insula", "domus": "domus", "garden": "garden",
             "park": "garden", "street": "street", "plaza": "plaza", "building": "building", "wall": "wall",
             "gate": "gate", "water": "water", "bridge": "bridge", "tombs": "tombs"}
# G bits 0-1: surface (earth, gravel, slabs, basalt)
SURFACE_BITS = {"": 0, "earth": 0, "gravel": 1, "slabs": 2, "basalt": 3}
# B bits 0-5 of a public building: its model (by kind), bits 6-7 the side its
# front faces (0 north, 1 east, 2 south, 3 west)
MODELS = ["", "amphitheatre", "forum", "baths", "temple", "circus", "theatre", "public", "market", "palace",
          "fort", "warehouse", "harbour", "tomb", "stadium", "portico", "agora", "spoil"]
# named buildings that are tile_terrain.gd LANDMARKS (their own models)
LANDMARK_MODELS = {"Amphitheatrum Flavium": "colosseum", "Forum Romanum": "forum", "Thermae Antoninianae": "baths",
                   "Pantheon": "pantheon", "Circus Maximus": "circus"}
# storeys of the houses (B bits 0-5), own rule: insulae 4-5, houses 2-3 in big
# cities, domus 1-2
STOREYS = {"insula": (4, 5), "house": (2, 3), "domus": (1, 2)}


def encode(cid, g, pop):
    """R, G, B of every parcel of a built plan."""
    kind = g["kind"]
    h, w = kind.shape
    rgb = np.zeros((h, w, 3), np.uint8)
    road = np.isin(kind, [K[k] for k in ("street", "plaza", "gate", "bridge")])
    data = g["plan"].data
    for r in range(h):
        for q in range(w):
            kd = KINDS[kind[r, q]]
            code = C[KIND_CODE[kd]]
            rk = int(g["rank"][r, q]) if kd in ("street", "gate", "bridge") else 0
            gch = SURFACE_BITS[SURFACES[g["surface"][r, q]]] | (rk << 2) | (int(g["links"][r, q]) << 4)
            face = 2
            for side, (dr, dq) in ((2, (1, 0)), (1, (0, 1)), (3, (0, -1)), (0, (-1, 0))):
                r2, q2 = r + dr, q + dq
                if 0 <= r2 < h and 0 <= q2 < w and road[r2, q2]:
                    face = side
                    break
            b = 0
            if kd in STOREYS:
                lo, hi = STOREYS[kd]
                if kd == "house" and pop < 100000:
                    hi = lo
                b = lo + (hash_cell(cid, r, q) % (hi - lo + 1))
            elif kd in ("building", "plaza") and g["building"][r, q] >= 0:
                bk = data["buildings"][g["building"][r, q]]["kind"]
                b = MODELS.index(bk) if bk in MODELS else MODELS.index("public")
            rgb[r, q] = (code, gch, b | (face << 6))
    return rgb


def hash_cell(cid, r, q):
    import zlib
    return zlib.crc32(f"{cid}:{r}:{q}".encode())


def bake(scale, out, only=None):
    """Every city: the reconstructed plan where there is one, else the
    generated one; bigger cities first where two overlap."""
    import city_generate
    from PIL import Image
    facts = json.loads((ROOT / "data" / "cities" / "facts.json").read_text())["cities"]
    terrain = Terrain()
    hand = {p.stem for p in CITY_DIR.glob("*.json")}
    order = sorted(facts, key=lambda c: -facts[c]["pop117"])
    if only:
        order = [c for c in order if c in only]
    pages = {}
    table = {}
    for cid in order:
        f = facts[cid]
        if cid in hand:
            data = json.loads((CITY_DIR / f"{cid}.json").read_text())
            g = build(data, scale, terrain=terrain)
        else:
            data, g = city_generate.build(cid, f, scale, terrain)
        rgb = encode(cid, g, f["pop117"])
        h, w = g["kind"].shape
        i0, j0 = g["i0"], g["j0"]
        for r in range(h):
            for q in range(w):
                code = rgb[r, q, 0]
                i, j = i0 + q, j0 + r
                key = (i // PAGE, j // PAGE)
                page = pages.get(key)
                if page is None:
                    if code in (C["land"], C["none"]):
                        continue
                    page = pages[key] = np.zeros((PAGE, PAGE, 3), np.uint8)
                old = page[j % PAGE, i % PAGE, 0]
                # a bigger city's parcels stay; plain land gives way
                if old in (C["none"], C["land"]) and not (code == C["land"] and old == C["land"]):
                    page[j % PAGE, i % PAGE] = rgb[r, q]
        bl = []
        for k, b in enumerate(data.get("buildings", [])):
            cells = np.argwhere(g["building"] == k)
            if len(cells) == 0:
                continue
            (r0, q0), (r1, q1) = cells.min(0), cells.max(0)
            e = {"name": b["name"], "kind": b["kind"], "parcels": [int(i0 + q0), int(j0 + r0), int(q1 - q0 + 1), int(r1 - r0 + 1)]}
            if b["name"] in LANDMARK_MODELS:
                e["landmark"] = LANDMARK_MODELS[b["name"]]
            bl.append(e)
        table[cid] = {"name": data.get("name", cid), "status": data.get("status", "generated"),
                      "origin": [int(i0), int(j0)], "size": [int(w), int(h)], "buildings": bl}
        print(cid, data.get("status"), json.dumps(stats(g)))
    keys = sorted(pages)
    rows = (len(keys) + ATLAS_SLOTS - 1) // ATLAS_SLOTS
    atlas = np.zeros((rows * PAGE, ATLAS_SLOTS * PAGE, 3), np.uint8)
    slots = []
    for n, key in enumerate(keys):
        sy, sx = divmod(n, ATLAS_SLOTS)
        atlas[sy * PAGE:(sy + 1) * PAGE, sx * PAGE:(sx + 1) * PAGE] = pages[key]
        slots.append([key[0], key[1], n])
    out.mkdir(parents=True, exist_ok=True)
    name = f"city-plans-x{scale:g}"
    Image.fromarray(atlas, "RGB").save(out / f"{name}.png", optimize=True)
    doc = {
        "generated_by": "tools/city_plans.py --bake", "scale": scale, "parcel_km": PARCEL_KM, "world_min": WORLD_MIN,
        "page_parcels": PAGE, "atlas": f"{name}.png", "atlas_slots_per_row": ATLAS_SLOTS,
        "pages": "[page_i, page_j, slot]: page (i // page_parcels, j // page_parcels) of parcel (i, j), "
                 "parcel i = floor((x_km - world_min.x) / parcel_km), j likewise from z",
        "page_slots": slots,
        "r": CODES, "g": "bits 0-1 surface (0 earth, 1 gravel, 2 limestone slabs, 3 basalt), bits 2-3 rank "
                         "(0 none, 1 via, 2 vicus, 3 lane), bits 4-7 links N=16 E=32 S=64 W=128",
        "b": "houses: bits 0-5 storeys; public buildings and squares: bits 0-5 model (models); bits 6-7 the side "
             "the front faces (0 north, 1 east, 2 south, 3 west)",
        "models": MODELS, "cities": table,
    }
    (out / f"{name}.json").write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")))
    print(len(table), "cities,", len(keys), "pages")


if __name__ == "__main__":
    main()
