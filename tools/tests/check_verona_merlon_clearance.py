"""Independent exported-triangle checks for visible Verona merlon setbacks.

Includes the battlements authored inside gate GLBs, not only separate wall
arms. No Blender, Godot renderer, or GPU is started. The previous wall-interior
test cannot establish this visible exterior clearance.
"""

import argparse
import hashlib
import json
import itertools
from pathlib import Path

import numpy as np

from check_verona_bridge_assets import Geometry, lod_triangles, read_glb, require
from check_verona_wall_tower_joins import inspect_graph, triangles_in_core_frame, UNIT

ROOT = Path(__file__).resolve().parents[2]
TAGS = ("detail", "medium", "far")
CLEARANCE = .60
HEIGHT_CUTOFF = 7.05
GEOMETRY_TOLERANCE = .0001


def components(triangles):
    """Recover physical connected surfaces across GLB material batches.

    Normals/UVs duplicate vertices in glTF. Weld only coincident positions,
    at 10-micrometre precision, to reconnect each actual closed primitive.
    """
    _, indices = np.unique(np.round(triangles.reshape(-1, 3), 5), axis=0, return_inverse=True)
    faces = indices.reshape(-1, 3)
    parents = np.arange(indices.max() + 1)

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for a, b, c in faces:
        root = find(a)
        parents[find(b)] = root
        parents[find(c)] = root
    roots = np.asarray([find(a) for a in faces[:, 0]])
    for root in np.unique(roots):
        yield triangles[roots == root]


def merlon_components(triangles):
    """Select physical bodies/caps by their fixed authored height extents.

    Ordinary tower walls, windows and cornices occupy the same height band,
    but have different component extrema. Far LOD body/cap surfaces may
    share coincident edges and thus form one component.
    """
    found = []
    for component in components(triangles):
        low, high = component.min(axis=(0, 1)), component.max(axis=(0, 1))
        if any(np.allclose([low[2], high[2]], interval, atol=GEOMETRY_TOLERANCE, rtol=0)
               for interval in [(6.98, 7.69), (7.69, 7.80), (6.98, 7.80)]):
            found.append((component, low, high))
    return found


def whole_block_vertices(low, high, tag):
    """Expected intact cuboid/chamfer vertices, independently of mesh indices."""
    half = (high[:2] - low[:2]) * .5
    intervals = []
    if abs(low[2] - 6.98) < GEOMETRY_TOLERANCE:
        intervals.append((6.98, 7.69, .024))
    if abs(high[2] - 7.80) < GEOMETRY_TOLERANCE:
        intervals.append((7.69, 7.80, .015))
    expected = []
    for bottom, top, bevel in intervals:
        size = np.array([*half, (top - bottom) * .5])
        centre = np.array([0., 0., (bottom + top) * .5])
        if tag != "detail":
            expected.extend(centre + np.array(signs) * size
                            for signs in itertools.product([-1, 1], repeat=3))
        else:
            for axis in range(3):
                extent = size - bevel
                extent[axis] = size[axis]
                expected.extend(centre + np.array(signs) * extent
                                for signs in itertools.product([-1, 1], repeat=3))
    return np.unique(np.round(expected, 4), axis=0)


def exterior_boxes(asset):
    # Include the actual outer corner dressings, not only the plaster body:
    # body faces 1.83/1.33/2.43 plus their 0.07m external relief.
    if asset == "verona_wall_tower":
        centres, half = [(0., 0.)], (1.90, 1.90)
    elif asset == "verona_gate":
        centres, half = [(-3.55, 0.), (3.55, 0.)], (1.40, 2.50)
    else:
        centres, half = [(x, y) for x in [-3.55, 3.55] for y in [-3.55, 3.55]], (1.40, 1.40)
    for x, y in centres:
        # A square expansion is deliberately conservative at diagonal corners.
        # Passing it also guarantees at least .60m Euclidean clearance.
        hx, hy = half[0] + CLEARANCE - GEOMETRY_TOLERANCE, half[1] + CLEARANCE - GEOMETRY_TOLERANCE
        yield [x - hx, y - hy, .53], [x + hx, y + hy, 7.95]


def above_plane(triangles, height):
    """Clip actual triangles to Z>=height, including crossing side faces."""
    result = []
    for triangle in triangles:
        polygon = []
        for a, b in zip(triangle, np.roll(triangle, -1, axis=0)):
            da, db = a[2] - height, b[2] - height
            if da >= 0:
                polygon.append(a)
            if (da < 0 < db) or (db < 0 < da):
                polygon.append(a + (b - a) * da / (da - db))
        for index in range(1, len(polygon) - 1):
            result.append([polygon[0], polygon[index], polygon[index + 1]])
    return np.asarray(result, dtype=float).reshape(-1, 3, 3)


def run(args):
    raw = args.runtime_report.read_bytes()
    capture = json.loads(raw)
    instances = capture["wall_instances"]
    cores, _, _ = inspect_graph(instances)
    report = {"scope": "Whole merlons and actual >7.05m triangles versus expanded exterior tower bodies",
              "clearance_m": CLEARANCE, "exterior_includes_quoins": True,
              "runtime_report": str(args.runtime_report),
              "runtime_report_sha256": hashlib.sha256(raw).hexdigest(),
              "asset_sha256": {}, "assets": {}, "triangle_box_checks": 0,
              "gate_own_merlon_checks": 0, "failures": []}
    meshes = {}
    for slug in sorted({i["asset"] for i in instances}):
        path = args.asset_root / slug / (slug + ".glb")
        document, binary = read_glb(path)
        report["asset_sha256"][slug] = hashlib.sha256(path.read_bytes()).hexdigest()
        meshes[slug] = {}
        report["assets"][slug] = {}
        for tag in TAGS:
            merlons = merlon_components(lod_triangles(document, binary, tag))
            if slug in ["verona_gate", "verona_gate_crossing", "verona_wall_arm", "verona_wall_diagonal"]:
                require(bool(merlons), f"No merlons identified for {slug}/{tag}; cannot claim clearance")
            rows = []
            footprints = {}
            for index, (triangles, low, high) in enumerate(merlons):
                size = np.sort((high - low)[:2])
                if not np.allclose(size, [.34, .66], atol=GEOMETRY_TOLERANCE, rtol=0):
                    report["failures"].append(
                        f"{slug}/{tag} component {index}: partial merlon footprint {size.tolist()}")
                actual = triangles.reshape(-1, 3).copy()
                actual[:, :2] -= (low[:2] + high[:2]) * .5
                actual = np.unique(np.round(actual, 4), axis=0)
                expected = whole_block_vertices(low, high, tag)
                if actual.shape != expected.shape or not np.allclose(actual, expected, atol=GEOMETRY_TOLERANCE, rtol=0):
                    report["failures"].append(
                        f"{slug}/{tag} component {index}: clipped or incomplete merlon shape")
                key = tuple(np.round(np.concatenate((low[:2], high[:2])), 4))
                footprints.setdefault(key, []).append((round(low[2], 2), round(high[2], 2)))
                rows.append({"bounds_xyz": [low.tolist(), high.tolist()], "triangles": len(triangles)})
            for footprint, intervals in footprints.items():
                if sorted(intervals) not in [[(6.98, 7.69), (7.69, 7.8)], [(6.98, 7.8)]]:
                    report["failures"].append(
                        f"{slug}/{tag}: body/cap are not a complete pair at {footprint}")
            if slug not in ["verona_wall_tower", "verona_gate", "verona_gate_crossing"]:
                all_triangles = lod_triangles(document, binary, tag)
                high_vertices = np.unique(np.round(all_triangles.reshape(-1, 3)[all_triangles.reshape(-1, 3)[:, 2] > HEIGHT_CUTOFF], 5), axis=0)
                selected = (np.concatenate([m[0] for m in merlons]).reshape(-1, 3)
                            if merlons else np.empty((0, 3)))
                selected = np.unique(np.round(selected[selected[:, 2] > HEIGHT_CUTOFF], 5), axis=0)
                require(np.array_equal(high_vertices, selected),
                        f"{slug}/{tag}: unclassified geometry above merlon cutoff")
            report["assets"][slug][tag] = rows
            meshes[slug][tag] = (above_plane(np.concatenate([m[0] for m in merlons]), HEIGHT_CUTOFF)
                                if merlons else np.empty((0, 3, 3)))
    for instance in instances:
        for tag in TAGS:
            triangles = meshes[instance["asset"]][tag]
            if not len(triangles):
                continue
            for core in cores:
                transformed = triangles_in_core_frame(triangles, instance, core)
                query = Geometry(transformed)
                for index, (low, high) in enumerate(exterior_boxes(core["asset"])):
                    if query.intersects_box(low, high):
                        report["failures"].append(
                            f"{instance['id']} ({instance['asset']})/{tag}: merlon enters .60m "
                            f"exterior clearance of {core['id']} pavilion {index}; "
                            f"ground delta {(instance['ground'] - core['ground']) / UNIT:.6f}m")
                report["triangle_box_checks"] += query.volumes
                if instance["id"] == core["id"]:
                    report["gate_own_merlon_checks"] += query.volumes
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-report", type=Path, default=ROOT / "build/verona-wall-joins/merlon-after/report.json")
    parser.add_argument("--asset-root", type=Path, default=ROOT / "app/assets/buildings")
    parser.add_argument("--report", type=Path, default=ROOT / "build/verona-merlon-clearance/merlon-validation.json")
    args = parser.parse_args()
    try:
        report = run(args)
    except (AssertionError, OSError, KeyError, ValueError) as exc:
        report = {"failures": [str(exc)]}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"assets": len(report.get("assets", {})),
                      "triangle_box_checks": report.get("triangle_box_checks", 0),
                      "gate_own_merlon_checks": report.get("gate_own_merlon_checks", 0),
                      "failures": len(report["failures"]), "report": str(args.report)}))
    for failure in report["failures"]:
        print(failure)
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
