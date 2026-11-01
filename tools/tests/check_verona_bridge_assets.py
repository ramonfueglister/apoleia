"""Independent CPU checks of the exported Verona bridge triangles.

Run with build/verona-venv/bin/python tools/tests/check_verona_bridge_assets.py.
No Blender, Godot import, renderer, or GPU is used. Coordinates below are
authored metres with Blender Z up; exported glTF node transforms must be identity.
"""

import argparse
import json
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MODEL_DIR = ROOT / "app/assets/buildings"
DEFAULT_REPORT = ROOT / "build/verona-bridges/asset-validation.json"
UNIT = 0.0238
PARCEL_M = 0.25 / UNIT
ROAD_WIDTH_M = PARCEL_M * 0.24
TAGS = ("detail", "medium", "far")
SLUGS = ("verona_bridge_span", "verona_bridge_junction", "verona_bridge_end",
         "verona_bridge_stairs", "verona_bridge_descent")
STAIR_RISE = .15 / UNIT
DESCENT_DROP = .20 / UNIT


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def read_glb(path):
    raw = path.read_bytes()
    require(len(raw) >= 20, f"Truncated GLB: {path}")
    require(struct.unpack_from("<III", raw) == (0x46546C67, 2, len(raw)),
            f"Invalid GLB header: {path}")
    chunks = {}
    cursor = 12
    while cursor < len(raw):
        size, kind = struct.unpack_from("<II", raw, cursor)
        cursor += 8
        require(cursor + size <= len(raw), f"Truncated GLB chunk: {path}")
        require(kind not in chunks, f"Duplicate GLB chunk: {path}")
        chunks[kind] = raw[cursor:cursor + size]
        cursor += size
    return json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]


def accessor(document, binary, index):
    item = document["accessors"][index]
    require("sparse" not in item, "Sparse accessors are unsupported by this export contract")
    view = document["bufferViews"][item["bufferView"]]
    require(view.get("buffer", 0) == 0, "External GLB buffer")
    dtype = np.dtype({5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[item["componentType"]])
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[item["type"]]
    stride = view.get("byteStride", components * dtype.itemsize)
    values = np.ndarray((item["count"], components), dtype=dtype,
                        buffer=binary,
                        offset=view.get("byteOffset", 0) + item.get("byteOffset", 0),
                        strides=(stride, dtype.itemsize))
    require(np.isfinite(values).all(), f"Nonfinite accessor {index}")
    return values


def primitives(document, index):
    node = document["nodes"][index]
    identity = (np.allclose(node.get("translation", [0, 0, 0]), [0, 0, 0])
                and np.allclose(node.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1])
                and np.allclose(node.get("scale", [1, 1, 1]), [1, 1, 1])
                and np.allclose(node.get("matrix", np.eye(4).ravel()), np.eye(4).ravel()))
    require(identity, f"Nonidentity authored node: {node.get('name', index)}")
    if "mesh" in node:
        yield from document["meshes"][node["mesh"]]["primitives"]
    for child in node.get("children", []):
        yield from primitives(document, child)


def lod_triangles(document, binary, tag):
    roots = [i for i, node in enumerate(document["nodes"])
             if node.get("name") == "Model_" + tag]
    require(len(roots) == 1, f"Expected exactly one Model_{tag}")
    meshes = []
    for primitive in primitives(document, roots[0]):
        require(primitive.get("mode", 4) == 4, "Nontriangle primitive")
        vertices = accessor(document, binary, primitive["attributes"]["POSITION"]).astype(float)
        indices = accessor(document, binary, primitive["indices"]).ravel()
        require(len(indices) % 3 == 0 and len(indices) > 0, "Invalid triangle indices")
        require(indices.max() < len(vertices), "Index beyond vertex array")
        require("NORMAL" in primitive["attributes"], "Missing exported normals")
        normals = accessor(document, binary, primitive["attributes"]["NORMAL"])
        require(len(normals) == len(vertices), "Normal/vertex count differs")
        require(np.all(np.linalg.norm(normals, axis=1) > .5), "Zero exported normal")
        source = np.column_stack((vertices[:, 0], -vertices[:, 2], vertices[:, 1]))
        meshes.append(source[indices].reshape(-1, 3, 3))
    require(bool(meshes), f"Empty Model_{tag}")
    return np.concatenate(meshes)


class Geometry:
    """Actual triangle queries, independent of declared mesh bounds or metadata."""

    def __init__(self, triangles):
        self.triangles = triangles
        self.low = triangles.min(axis=1)
        self.high = triangles.max(axis=1)
        self.rays = 0
        self.volumes = 0

    def ray(self, origin, axis, sign=1, reach=np.inf):
        self.rays += 1
        origin = np.asarray(origin, dtype=float)
        other = [i for i in range(3) if i != axis]
        selected = np.all((self.low[:, other] <= origin[other] + 1e-7)
                          & (self.high[:, other] >= origin[other] - 1e-7), axis=1)
        triangles = self.triangles[selected]
        direction = np.zeros(3)
        direction[axis] = sign
        e1 = triangles[:, 1] - triangles[:, 0]
        e2 = triangles[:, 2] - triangles[:, 0]
        h = np.cross(np.broadcast_to(direction, e2.shape), e2)
        det = np.einsum("ij,ij->i", e1, h)
        useful = np.abs(det) > 1e-10
        inv = np.zeros_like(det)
        inv[useful] = 1 / det[useful]
        offset = origin - triangles[:, 0]
        u = inv * np.einsum("ij,ij->i", offset, h)
        q = np.cross(offset, e1)
        v = inv * (q @ direction)
        distance = inv * np.einsum("ij,ij->i", e2, q)
        valid = (useful & (u >= -1e-7) & (v >= -1e-7) & (u + v <= 1 + 1e-7)
                 & (distance > 1e-6) & (distance < reach + 1e-7))
        return distance[valid]

    def intersects_box(self, low, high):
        """Triangle/AABB separating-axis test, including thin and angled faces."""
        self.volumes += 1
        low, high = np.asarray(low, dtype=float), np.asarray(high, dtype=float)
        selected = np.all((self.high >= low) & (self.low <= high), axis=1)
        triangles = self.triangles[selected] - (low + high) * .5
        if not len(triangles):
            return False
        half = (high - low) * .5
        edges = np.stack((triangles[:, 1] - triangles[:, 0],
                          triangles[:, 2] - triangles[:, 1],
                          triangles[:, 0] - triangles[:, 2]), axis=1)
        axes = [np.cross(edges[:, 0], edges[:, 1])]
        for direction in np.eye(3):
            for edge in range(3):
                axes.append(np.cross(edges[:, edge], direction))
        overlaps = np.ones(len(triangles), dtype=bool)
        for axis in axes:
            projections = np.einsum("tvi,ti->tv", triangles, axis)
            radius = np.abs(axis) @ half
            overlaps &= ((projections.min(axis=1) <= radius + 1e-9)
                         & (projections.max(axis=1) >= -radius - 1e-9))
        return bool(overlaps.any())


def check_deck(geometry, half_length, end_limit, junction, result):
    """Sample the whole traffic band and every open end, not just its centre."""
    half_road = ROAD_WIDTH_M * .5
    points = [(x, y) for x in np.linspace(-half_length + .002, end_limit, 35)
              for y in np.linspace(-half_road, half_road, 9)]
    if junction:
        points += [(x, y) for x in np.linspace(-half_road, half_road, 9)
                   for y in np.linspace(0, half_length - .002, 23)]
    for x, y in points:
        hits = geometry.ray((x, y, .25), 2, -1, 1)
        require(len(hits) > 0, f"Deck hole at ({x:.5f}, {y:.5f})")
        # The running plane is Z=0; tiny surface relief may be carved below it.
        require(abs(float(hits.min()) - .25) < .0061,
                f"Deck is not flush with Z=0 at ({x:.5f}, {y:.5f}): {hits.min()}")
    result["deck_samples"] = len(points)


def check_corridors(geometry, half_length, end_limit, junction, result):
    """Clear the full 3.8m architectural band, including the 2.521m road."""
    # Include the exterior port in the volume: even a solid enveloping the
    # entire internal corridor must intersect the volume at the port face.
    boxes = [([-half_length - .05, -1.9 + .002, .015],
              [end_limit, 1.9 - .002, 2.2])]
    if junction:
        boxes.append(([-1.9 + .002, 0, .015],
                      [1.9 - .002, half_length + .05, 2.2]))
    for low, high in boxes:
        require(not geometry.intersects_box(low, high),
                f"Triangle intrudes into walking/driving corridor {low}..{high}")
    result["clearance_volumes"] = len(boxes)


def check_parapets(geometry, half_length, junction, end_barrier_start, result):
    """Verify solid side protection, open junction mouth and the closed end."""
    sections = []
    for x in np.linspace(-half_length + .04, half_length - .04, 13):
        sections.append(((x, -2.5, .55), 1, 1, .8))
        if not junction or abs(x) > 2.25:
            sections.append(((x, 2.5, .55), 1, -1, .8))
    if junction:
        for y in np.linspace(2.3, half_length - .04, 7):
            sections += [((-2.5, y, .55), 0, 1, .8),
                         ((2.5, y, .55), 0, -1, .8)]
    if end_barrier_start is not None:
        for y in np.linspace(-1.85, 1.85, 11):
            sections.append(((half_length + .1, y, .55), 0, -1,
                             half_length - end_barrier_start + .2))
    for origin, axis, sign, reach in sections:
        require(len(geometry.ray(origin, axis, sign, reach)) > 0,
                f"Missing parapet/end barrier at {origin}")
    result["parapet_samples"] = len(sections)


def check_arch(geometry, result):
    samples = 0
    for x in np.linspace(-3.8, 3.8, 17):
        intrados = -4.6 + 3.5 * np.sqrt(1 - (x / 4.1) ** 2)
        for height in [-7.0, -5.0, intrados - .12]:
            hits = geometry.ray((x, -3.2, height), 1, 1, 6.4)
            require(not len(hits), f"Blocked arch aperture at x={x:.3f}, z={height:.3f}")
            samples += 1
        for y in [-1.4, 0, 1.4]:
            hits = geometry.ray((x, y, intrados - .25), 2, 1, .5)
            require(len(hits) > 0 and abs(hits.min() - .25) < .20,
                    f"Missing arch barrel near x={x:.3f}, y={y}")
            samples += 1
    require(not geometry.intersects_box([-2.5, -3.2, -7.0], [2.5, 3.2, -2.05]),
            "Solid triangle inside central under-bridge opening")
    result["arch_samples"] = samples


def check_steps(slug, geometry, result):
    stairs = slug == "verona_bridge_stairs"
    axis, cross_axis = (1, 0) if stairs else (0, 1)
    start, end = (1.30, PARCEL_M * .5) if stairs else (-PARCEL_M * .5, PARCEL_M * .5)
    target = STAIR_RISE if stairs else -DESCENT_DROP
    sign = 1 if stairs else -1
    high_z = STAIR_RISE + 2 if stairs else 2
    clearance = ROAD_WIDTH_M if stairs else 3.8
    triangles = geometry.triangles
    normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    lengths = np.linalg.norm(normals, axis=1)
    flat = Geometry(triangles[(lengths > 1e-10) & (np.abs(normals[:, 2]) >= lengths * .999999)])
    centre_heights = []
    for lane in [-clearance * .5 + .005, 0, clearance * .5 - .005]:
        heights = []
        for along in np.linspace(start + .004, end - .004, 401):
            origin = np.zeros(3)
            origin[axis], origin[cross_axis], origin[2] = along, lane, high_z
            hits = geometry.ray(origin, 2, -1, high_z + DESCENT_DROP + 2)
            flats = flat.ray(origin, 2, -1, high_z + DESCENT_DROP + 2)
            require(len(hits) > 0 and len(flats) > 0, f"Missing horizontal tread at {origin}")
            require(abs(hits.min() - flats.min()) < .001,
                    f"Top walking surface slopes or is obstructed at {origin}")
            heights.append(high_z - float(hits.min()))
        heights = np.asarray(heights)
        changes = sign * np.diff(heights)
        require(changes.min() >= -.007, f"Steps reverse direction in lane {lane}")
        require(changes.max() <= .251, f"Step exceeds .25m in lane {lane}: {changes.max()}")
        require(abs(heights[0]) <= .251, f"First step no longer meets Z=0: {heights[0]}")
        require(abs(heights[-1] - target) <= .251,
                f"Last step fails target elevation {target}: {heights[-1]}")
        require(np.count_nonzero(changes > .01) >= 20, "Stairs collapsed into a ramp/platform")
        if lane == 0:
            centre_heights = heights.tolist()
    result["tread_samples"] = 1203
    result["horizontal_surface_ray_checks"] = flat.rays
    result["walking_end_heights_m"] = [centre_heights[0], centre_heights[-1]]


def check_junction_stairs(stairs, tag, result):
    """The shared landing belongs to the junction, not two coplanar meshes."""
    folder = MODEL_DIR / "verona_bridge_junction"
    document, binary = read_glb(folder / "verona_bridge_junction.glb")
    junction = Geometry(lod_triangles(document, binary, tag))
    landing_end = 1.30 + (PARCEL_M * .5 - 1.30) / 33
    half_road = ROAD_WIDTH_M * .5
    require(not stairs.intersects_box([-half_road, 1.304, -.001],
                                     [half_road, landing_end - .004, .001]),
            "Stair mesh overlaps the junction-owned Z=0 landing")
    for x in np.linspace(-half_road, half_road, 7):
        for y in np.linspace(1.304, landing_end - .004, 7):
            hits = junction.ray((x, y, .25), 2, -1, .5)
            require(len(hits) > 0 and abs(hits.min() - .25) < .001,
                    f"Junction fails to support lower stair landing at ({x}, {y})")
    combined = Geometry(np.concatenate((stairs.triangles, junction.triangles)))
    require(not combined.intersects_box([-PARCEL_M * .5 - .05, -half_road, .015],
                                       [PARCEL_M * .5 + .05, half_road, 2.2]),
            "Combined T-junction/stairs obstructs the active EW road")
    check_steps("verona_bridge_stairs", combined, result)
    result["junction_landing_samples"] = junction.rays
    result["combined_road_clearance_volumes"] = combined.volumes
    result["combined_triangle_ray_checks"] = combined.rays


def check_asset(slug):
    folder = MODEL_DIR / slug
    metadata = json.loads((folder / "model.json").read_text())
    document, binary = read_glb(folder / (slug + ".glb"))
    require(metadata["metres"] is True, "Asset does not declare metres")
    require(metadata["lod_method"] == "shape_preserving_v1", "Missing native LOD contract")
    require(metadata["origin_policy"] == "authored", "Origin must be preserved")
    require(metadata["authored_origin_xyz"] == [0, 0, 0], "Unexpected authored origin")
    require(abs(metadata["parcel_length_m"] - PARCEL_M) < 1e-8,
            "Asset uses a different parcel scale")
    require(abs(metadata["road_width_m"] - ROAD_WIDTH_M) < 1e-8,
            "Asset uses a different active road width")
    # Check every ancestor too: looking only below Model_detail could silently
    # miss a scaled or translated export scene root.
    for root in document["scenes"][document.get("scene", 0)]["nodes"]:
        list(primitives(document, root))
    result = {"lods": {}, "uniform_world_units_per_metre": UNIT,
              "authored_origin_identity": True}
    counts = []
    for tag in TAGS:
        triangles = lod_triangles(document, binary, tag)
        low, high = triangles.min(axis=(0, 1)), triangles.max(axis=(0, 1))
        require(len(triangles) == metadata["lods"][tag]["triangles"],
                f"{tag}: metadata triangle count differs from actual mesh")
        if tag == "detail":
            require(np.allclose([low, high], metadata["source_bounds_xyz"], atol=1e-5),
                    "Declared bounds differ from actual detail triangles")
        geometry = Geometry(triangles)
        checked = {"triangles": len(triangles), "bounds_xyz": [low.tolist(), high.tolist()]}
        try:
            if slug in SLUGS[:3]:
                half = PARCEL_M * .5
                require(abs(low[0] + half) < .035 and abs(high[0] - half) < .035,
                        "Bridge ends do not reach the shared parcel ports")
                require(abs(low[2] + 10) < .01, "End piers no longer reach Z=-10m")
                require(abs(high[2] - 1.10) < .01, "Parapet top differs from Z=1.10m")
                require(low[1] >= -3.001 and high[1] <= (half + .01 if slug == SLUGS[1] else 3.001),
                        "Cutwater or junction extends beyond agreed bounds")
                junction = slug == SLUGS[1]
                endcap = 4.60 if slug == SLUGS[2] else None
                check_deck(geometry, half, endcap - .01 if endcap else half - .002, junction, checked)
                check_corridors(geometry, half, endcap - .002 if endcap else half + .05, junction, checked)
                check_parapets(geometry, half, junction, endcap, checked)
                check_arch(geometry, checked)
            elif slug == "verona_bridge_stairs":
                check_junction_stairs(geometry, tag, checked)
            else:
                check_steps(slug, geometry, checked)
                # The descent barrel is statically graded in its source mesh.
                # Undo that affine grade to compare the same genuine opening.
                level = triangles.copy()
                level[:, :, 2] += (level[:, :, 0] + PARCEL_M * .5) * DESCENT_DROP / PARCEL_M
                arch = Geometry(level)
                check_arch(arch, checked)
                checked["descent_arch_ray_checks"] = arch.rays
                checked["descent_arch_box_checks"] = arch.volumes
                require(abs(low[2] + 10 + DESCENT_DROP) < .01,
                        "Descent piers no longer reach 10m below their local deck")
        except AssertionError as exc:
            raise AssertionError(f"{slug}/{tag}: {exc}") from exc
        checked["triangle_ray_checks"] = (geometry.rays + checked.get("horizontal_surface_ray_checks", 0)
                                          + checked.get("combined_triangle_ray_checks", 0)
                                          + checked.get("junction_landing_samples", 0)
                                          + checked.get("descent_arch_ray_checks", 0))
        checked["triangle_box_checks"] = (geometry.volumes + checked.get("combined_road_clearance_volumes", 0)
                                          + checked.get("descent_arch_box_checks", 0))
        result["lods"][tag] = checked
        counts.append(len(triangles))
    require(counts[0] > counts[1] > counts[2] > 0, "LOD complexity does not decrease")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    report = {"coordinate_system": "Authored metres, Z up, identity transforms",
              "parcel_metres": PARCEL_M, "active_road_width_metres": ROAD_WIDTH_M,
              "scope": "Exported mesh geometry; runtime seating and visual craft require separate checks",
              "assets": {}, "failures": []}
    for slug in SLUGS:
        try:
            report["assets"][slug] = check_asset(slug)
        except (AssertionError, OSError, KeyError, ValueError, StopIteration) as exc:
            report["failures"].append(f"{slug}: {exc}")
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"assets_checked": len(report["assets"]),
                      "lods_checked": sum(len(a["lods"]) for a in report["assets"].values()),
                      "failures": report["failures"], "report": str(args.report)}))
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
