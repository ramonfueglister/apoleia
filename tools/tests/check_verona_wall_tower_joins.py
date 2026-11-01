"""Check real wall/link triangles against tower interiors at rendered elevations.

Run after the real-game capture (no renderer is started by this script):
  build/verona-venv/bin/python tools/tests/check_verona_wall_tower_joins.py

The runtime report supplies the installed instance graph and GPU-corner-derived
ground elevations. A --runtime-report and --asset-root pair can also reproduce
the pre-fix failure from archived GLBs. Coordinates used for intersections are
local authored metres, never large world-km coordinates.
"""

import argparse
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

import numpy as np

from check_verona_bridge_assets import Geometry, lod_triangles, read_glb, require

ROOT = Path(__file__).resolve().parents[2]
UNIT = .0238
PARCEL = .25 / UNIT
TAGS = ("detail", "medium", "far")
CORES = {"verona_wall_tower", "verona_gate", "verona_gate_crossing"}
GRAPH_EDGES = {frozenset(pair) for pair in (
    ((13, 12), (14, 12)), ((13, 12), (12, 13)), ((12, 13), (12, 14)),
    ((12, 14), (12, 15)), ((12, 15), (13, 16)), ((13, 16), (14, 16)),
    ((14, 12), (15, 13)))}
CITY_ORIGIN = (18445, 6906)
# Reserve the entire hollow body above the base and below the roof. The
# pavilion's own upper floor is allowed; foreign wall/link geometry is not.
INTERIOR_BOTTOM = .53
INTERIOR_TOP = 7.79
TOLERANCE = .005


def basis(instance):
    """Blender X east/Y north/Z up -> grid X east/Y south/Z up.

    Mirrors roman_series_building.gd's -quarter-turn/-eighth-turn Y rotation,
    including glTF's conversion from Blender Z-up to Godot Y-up.
    """
    theta = (instance["turns"] + (.5 if instance["diagonal"] else 0)) * math.pi / 2
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[c, s, 0], [s, -c, 0], [0, 0, 1.]])


def triangles_in_core_frame(triangles, arm, core):
    offset = np.array([(arm["rect"][0] - core["rect"][0]) * PARCEL,
                       (arm["rect"][1] - core["rect"][1]) * PARCEL,
                       (arm["ground"] - core["ground"]) / UNIT])
    return (triangles @ basis(arm).T + offset) @ basis(core)


def interior_boxes(asset):
    if asset == "verona_wall_tower":
        centres, half = [(0., 0.)], (1.53, 1.53)
    elif asset == "verona_gate":
        centres, half = [(-3.55, 0.), (3.55, 0.)], (1.03, 2.13)
    else:
        centres, half = [(x, y) for x in [-3.55, 3.55] for y in [-3.55, 3.55]], (1.03, 1.03)
    for x, y in centres:
        yield ([x - half[0] + TOLERANCE, y - half[1] + TOLERANCE, INTERIOR_BOTTOM],
               [x + half[0] - TOLERANCE, y + half[1] - TOLERANCE, INTERIOR_TOP])


def algorithm_checks():
    """Guard against vertex-only, AABB-only and wrong-rotation regressions."""
    crossing = np.array([[[-2., 0, 1], [2, 0, 1], [0, 2, 1]]])
    require(Geometry(crossing).intersects_box([-.1, -.1, .9], [.1, .1, 1.1]),
            "Triangle crossing volume with all vertices outside was missed")
    corner = np.array([[[0., 2, 1], [2, 0, 1], [2, 2, 1]]])
    require(not Geometry(corner).intersects_box([-.1, -.1, .9], [.1, .1, 1.1]),
            "Triangle AABB overlap mistaken for real triangle intrusion")
    test = {"turns": 0, "diagonal": True, "rect": [0, 0, 1, 1], "ground": .15}
    core = {"turns": 0, "diagonal": False, "rect": [0, 0, 1, 1], "ground": 0.}
    point = triangles_in_core_frame(np.array([1., 0, 0]), test, core)
    require(np.allclose(point, [math.sqrt(.5), -math.sqrt(.5), .15 / UNIT]),
            "Runtime rotation/ground transform is incorrect")


def inspect_graph(instances):
    require(len({i["id"] for i in instances}) == len(instances), "Duplicate instance id")
    cores = [i for i in instances if i["asset"] in CORES]
    arms = [i for i in instances if i["asset"] not in CORES]
    require(Counter(i["asset"] for i in cores) == {
        "verona_wall_tower": 4, "verona_gate": 3, "verona_gate_crossing": 1},
        "Expected four towers, three ordinary gates and one crossing gate")
    require(len(arms) == 14, "Expected two directed arms for each of seven graph edges")
    by_parcel = {tuple(i["rect"][:2]): i for i in cores}
    require(len(by_parcel) == 8, "Two cores occupy one parcel")
    edges = Counter()
    for instance in instances:
        require(instance["rect"][2:] == [1, 1], "Unexpected multi-parcel instance")
        require(instance["turns"] in range(4), "Invalid quarter-turn")
        require(isinstance(instance["diagonal"], bool), "Missing diagonal flag")
        require(np.isfinite(instance["ground"]), "Missing real rendered ground elevation")
    for arm in arms:
        parcel = tuple(arm["rect"][:2])
        require(parcel in by_parcel, f"Arm has no owning tower/gate: {arm['id']}")
        direction = np.rint(basis(arm)[:2, 0] * (math.sqrt(2) if arm["diagonal"] else 1)).astype(int)
        target = tuple(np.asarray(parcel) + direction)
        require(target in by_parcel, f"Arm does not point at a graph neighbour: {arm['id']}")
        relative = [tuple(np.asarray(p) - CITY_ORIGIN) for p in (parcel, target)]
        edges[frozenset(relative)] += 1
    require(set(edges) == GRAPH_EDGES and all(n == 2 for n in edges.values()),
            "The seven accepted graph edges or their directed arms changed")
    return cores, arms, by_parcel


def run(args):
    algorithm_checks()
    raw = args.runtime_report.read_bytes()
    capture = json.loads(raw)
    require(capture.get("test") == "verona_wall_joins_check", "Wrong runtime capture report")
    instances = capture["wall_instances"]
    cores, arms, by_parcel = inspect_graph(instances)
    report = {"scope": "Actual exported arm/link triangles against all tower/pavilion interiors",
              "coordinate_system": "Local authored metres; actual GPU-corner ground offsets applied",
              "runtime_report": str(args.runtime_report),
              "runtime_report_sha256": hashlib.sha256(raw).hexdigest(),
              "runtime_phase": capture.get("phase"), "asset_sha256": {},
              "interior_margin_m": TOLERANCE, "instances": len(instances),
              "directed_arms": len(arms), "cores": len(cores), "graph_edges": 7,
              "lods": list(TAGS), "triangle_box_checks": 0,
              "rendered_height_join_rays": 0, "failures": [],
              "ground_levels_km": sorted({i["ground"] for i in instances}),
              "checked_pairs": [], "terrain_joins": []}
    geometry = {}
    for slug in sorted({a["asset"] for a in arms}):
        path = args.asset_root / slug / (slug + ".glb")
        document, binary = read_glb(path)
        report["asset_sha256"][slug] = hashlib.sha256(path.read_bytes()).hexdigest()
        geometry[slug] = {tag: lod_triangles(document, binary, tag) for tag in TAGS}
    for arm in arms:
        parcel = tuple(arm["rect"][:2])
        direction = np.rint(basis(arm)[:2, 0] * (math.sqrt(2) if arm["diagonal"] else 1)).astype(int)
        neighbour = by_parcel[tuple(np.asarray(parcel) + direction)]
        require(abs(arm["ground"] - by_parcel[parcel]["ground"]) < 1e-8,
                "Wall arm and its own tower use different rendered ground levels")
        midpoint = PARCEL * .5 * (math.sqrt(2) if arm["diagonal"] else 1)
        elevations = sorted({arm["ground"], neighbour["ground"]})
        report["terrain_joins"].append({"arm": arm["id"], "neighbour": neighbour["id"],
                                       "rendered_grounds_km": elevations,
                                       "step_m": abs(arm["ground"] - neighbour["ground"]) / UNIT})
        # Check both arms separately at their common graph midpoint, at each
        # actual terrace's height. The 6.30m step needs the deep foundation;
        # a source-only origin ray would silently miss this rendered gap.
        for tag in TAGS:
            query = Geometry(geometry[arm["asset"]][tag])
            for elevation in elevations:
                height = (elevation - arm["ground"]) / UNIT + .35
                hits = query.ray((midpoint, -2., height), 1, 1, 4.)
                report["rendered_height_join_rays"] += 1
                if not len(hits):
                    report["failures"].append(
                        f"{arm['id']}/{tag}: open graph midpoint at actual terrace "
                        f"{elevation:.6f}km (source height {height:.6f}m)")
        for core in cores:
            delta = (arm["ground"] - core["ground"]) / UNIT
            pair = {"arm": arm["id"], "core": core["id"], "ground_delta_m": delta,
                    "same_parcel": arm["rect"] == core["rect"], "lod_checks": {}}
            for tag in TAGS:
                transformed = triangles_in_core_frame(geometry[arm["asset"]][tag], arm, core)
                query = Geometry(transformed)
                overlaps = []
                for index, (low, high) in enumerate(interior_boxes(core["asset"])):
                    if query.intersects_box(low, high):
                        overlaps.append(index)
                        report["failures"].append(
                            f"{arm['id']} ({arm['asset']})/{tag} intrudes into "
                            f"{core['id']} interior {index}; ground delta {delta:.6f}m")
                report["triangle_box_checks"] += query.volumes
                pair["lod_checks"][tag] = {"triangles": len(transformed), "intruded_interiors": overlaps}
            report["checked_pairs"].append(pair)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-report", type=Path,
                        default=ROOT / "build/verona-wall-joins/final/report.json")
    parser.add_argument("--asset-root", type=Path, default=ROOT / "app/assets/buildings")
    parser.add_argument("--report", type=Path,
                        default=ROOT / "build/verona-wall-joins/join-validation.json")
    args = parser.parse_args()
    try:
        report = run(args)
    except (AssertionError, OSError, KeyError, ValueError) as exc:
        report = {"failures": [str(exc)]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"triangle_box_checks": report.get("triangle_box_checks", 0),
                      "rendered_height_join_rays": report.get("rendered_height_join_rays", 0),
                      "failures": len(report["failures"]), "report": str(args.report)}))
    for error in report["failures"]:
        print(error)
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
