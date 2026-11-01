"""Validate authored fortification GLBs without Godot imports or GPU rendering.

Run from any directory with the project's NumPy environment:
    build/verona-venv/bin/python tools/tests/check_verona_fortification_assets.py

The report is written to build/verona-fortifications/asset-validation.json.
The Blender export log is optional; absent logs are reported as not checked.
"""

import json
import math
import struct
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = ROOT / "build/verona-fortifications"
EXPORT_LOG = ROOT / "build/verona-fortifications-assets.log"
SLUGS = [
    "verona_wall_arm",
    "verona_wall_diagonal",
    "verona_wall_tower",
    "verona_gate_link",
    "verona_gate_diagonal_link",
    "verona_gate_crossing_diagonal_link",
    "verona_gate",
    "verona_gate_crossing",
]
PORTS = {
    "verona_wall_arm": 5.30,
    "verona_wall_diagonal": 7.60,
    "verona_gate_link": 5.30,
    "verona_gate_diagonal_link": 7.60,
    "verona_gate_crossing_diagonal_link": 7.60,
}
GATES = {"verona_gate", "verona_gate_crossing"}
EXPECTED_FOUNDATION_DEPTHS = {
    "verona_wall_arm": 6.5,
    "verona_wall_diagonal": 2.0,
    "verona_wall_tower": 2.0,
    "verona_gate_link": 2.0,
    "verona_gate_diagonal_link": 2.0,
    "verona_gate_crossing_diagonal_link": 2.0,
    "verona_gate": 2.0,
    "verona_gate_crossing": 2.0,
}


def hit_distances(triangles, origin, direction):
    """Return positive, two-sided ray intersections with actual mesh triangles."""
    edge1 = triangles[:, 1] - triangles[:, 0]
    edge2 = triangles[:, 2] - triangles[:, 0]
    direction = np.asarray(direction)
    origin = np.asarray(origin)

    h = np.cross(np.broadcast_to(direction, edge2.shape), edge2)
    determinant = np.einsum("ij,ij->i", edge1, h)
    nonparallel = np.abs(determinant) > 1e-10
    inverse = np.zeros_like(determinant)
    inverse[nonparallel] = 1 / determinant[nonparallel]

    offset = origin - triangles[:, 0]
    u = inverse * np.einsum("ij,ij->i", offset, h)
    q = np.cross(offset, edge1)
    v = inverse * np.einsum("j,ij->i", direction, q)
    distance = inverse * np.einsum("ij,ij->i", edge2, q)
    valid = (
        nonparallel
        & (u >= -1e-7)
        & (v >= -1e-7)
        & (u + v <= 1 + 1e-7)
        & (distance > 1e-6)
    )
    return distance[valid]


def read_glb(path):
    raw = path.read_bytes()
    assert struct.unpack_from("<III", raw) == (0x46546C67, 2, len(raw))
    json_size = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20 : 20 + json_size])
    binary_offset = 20 + json_size
    binary_size = struct.unpack_from("<I", raw, binary_offset)[0]
    binary = raw[binary_offset + 8 : binary_offset + 8 + binary_size]
    return document, binary


def read_accessor(document, binary, accessor_index):
    accessor = document["accessors"][accessor_index]
    buffer_view = document["bufferViews"][accessor["bufferView"]]
    dtype = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[
        accessor["componentType"]
    ]
    dimensions = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[
        accessor["type"]
    ]
    values = np.frombuffer(
        binary,
        dtype=dtype,
        count=accessor["count"] * dimensions,
        offset=buffer_view.get("byteOffset", 0) + accessor.get("byteOffset", 0),
    ).reshape(-1, dimensions)
    assert np.isfinite(values).all()
    return values


def mesh_primitives(document, node):
    assert not any(
        key in node for key in ["matrix", "translation", "rotation", "scale"]
    ), "Authored origin must remain identity"
    if "mesh" in node:
        yield from document["meshes"][node["mesh"]]["primitives"]
    for child_index in node.get("children", []):
        yield from mesh_primitives(document, document["nodes"][child_index])


def port_start(slug, transverse):
    """Independent exterior-plane contract, in authored Blender X/Y metres."""
    if slug == "verona_wall_arm":
        return 1.83
    if slug == "verona_gate_link":
        return 4.88
    if slug == "verona_wall_diagonal":
        return math.sqrt(2) * 1.83 - abs(transverse)
    if slug == "verona_gate_crossing_diagonal_link":
        return math.sqrt(2) * 4.88 - abs(transverse)
    # Ordinary gate's SE link meets both the pavilion's south exterior
    # and its east-side inner edge, preserving the adjacent road passage.
    return max(transverse + math.sqrt(2) * 2.43,
               -transverse + math.sqrt(2) * 2.22)


def check_ports(slug, tag, triangles, low, high, result):
    end = PORTS[slug]
    # Include the two-plane profile's crease when calculating its exact
    # minimum; merely testing a declared bounding box misses the old overlap.
    crease = math.sqrt(2) * (2.22 - 2.43) / 2
    start_min = min(port_start(slug, y) for y in [-1.15, 0, 1.15, crease])
    # The existing 3mm edge bevel trims the outermost V-profile tip. This
    # permits only an inward bound offset; the sampled closed endfaces below
    # must still lie exactly on the analytic clipping plane.
    tip_bevel = .0031 if slug in {"verona_wall_diagonal", "verona_gate_crossing_diagonal_link"} else 1e-5
    assert -1e-5 < low[0] - start_min < tip_bevel, (slug, tag, "profile bounds", low[0], start_min)
    assert abs(high[0] - end) < 1e-5
    assert abs(low[1] + 1.15) < 1e-5
    assert abs(high[1] - 1.15) < 1e-5
    heights = [-1.5, 0.1, 0.8, 3.0, 5.5, 6.3]
    if slug == "verona_wall_arm":
        heights = [-6.3, -4.0, -2.5] + heights
    for y in [-0.9, -0.45, 0, 0.45, 0.9]:
        start = port_start(slug, y)
        for z in heights:
            hits = hit_distances(triangles, (start - 1, y, z), (1, 0, 0))
            result["port_rays"] += 1
            assert np.any(np.abs(hits - 1) < 1e-4) and np.any(
                np.abs(hits - (end - start + 1)) < 1e-4
            ), (slug, tag, y, z, "profile start or unchanged far endface missing")
            assert not np.any(hits < 1 - 1e-4), (
                slug, tag, y, z, "geometry protrudes inside the exterior-plane profile")


def check_road_clearance(slug, tag, triangles, result):
    axes = [1] if slug == "verona_gate" else [0, 1]
    for axis in axes:
        for lane in [-1.79, -1.26, 0, 1.26, 1.79]:
            for z in [-1.5, 0.05, 0.35, 1.7, 3.0, 4.0]:
                origin = [0.0, 0.0, z]
                direction = [0.0, 0.0, 0.0]
                origin[axis] = -6
                origin[1 - axis] = lane
                direction[axis] = 1
                hits = hit_distances(triangles, origin, direction)
                result["road_clearance_rays"] += 1
                assert not np.any(hits < 12), (
                    slug,
                    tag,
                    axis,
                    lane,
                    z,
                    "blocked road corridor",
                )


def check_asset(slug):
    path = ROOT / "app/assets/buildings" / slug / (slug + ".glb")
    document, binary = read_glb(path)
    metadata = json.loads(path.with_name("model.json").read_text())
    result = {
        "metadata_bounds_xyz": metadata["source_bounds_xyz"],
        "foundation_depth_m": metadata["foundation_depth_m"],
        "lods": {},
    }
    assert metadata["lod_method"] == "shape_preserving_v1"
    assert metadata["authored_origin_xyz"] == [0, 0, 0]
    assert metadata["foundation_depth_m"] == EXPECTED_FOUNDATION_DEPTHS[slug]
    assert metadata["origin_policy"] == "authored"

    for tag in ["detail", "medium", "far"]:
        lod_root = next(
            node
            for node in document["nodes"]
            if node.get("name") == "Model_" + tag
        )
        meshes = []
        for primitive in mesh_primitives(document, lod_root):
            vertices = read_accessor(
                document, binary, primitive["attributes"]["POSITION"]
            ).astype(float)
            indices = read_accessor(document, binary, primitive["indices"]).ravel()
            assert len(indices) % 3 == 0 and indices.max() < len(vertices)
            if "NORMAL" in primitive["attributes"]:
                read_accessor(document, binary, primitive["attributes"]["NORMAL"])
            # glTF is Y up; restore the documented authoring coordinates.
            source = np.column_stack(
                (vertices[:, 0], -vertices[:, 2], vertices[:, 1])
            )
            meshes.append(source[indices].reshape(-1, 3, 3))

        triangles = np.concatenate(meshes)
        count = len(triangles)
        assert count == metadata["lods"][tag]["triangles"]
        low = triangles.min(axis=(0, 1))
        high = triangles.max(axis=(0, 1))
        assert abs(low[2] + EXPECTED_FOUNDATION_DEPTHS[slug]) < 1e-5
        lod_result = {
            "triangles": count,
            "bounds_xyz": [low.tolist(), high.tolist()],
            "valid_indices_finite_vertices_normals": True,
            "origin_identity": True,
            "port_rays": 0,
            "road_clearance_rays": 0,
        }
        result["lods"][tag] = lod_result
        if slug in PORTS:
            check_ports(slug, tag, triangles, low, high, lod_result)
        if slug in GATES:
            check_road_clearance(slug, tag, triangles, lod_result)
        if slug == "verona_wall_tower":
            assert max(high[:2] - low[:2]) < 3.82 and high[2] < 9.8
        if slug in GATES:
            # Accepted tile-trim tolerance; every model fits its 10.504 m parcel.
            assert high[0] - low[0] < 9.953 and high[2] < 9.8
    return result


def main():
    report = {
        "assets": {},
        "failures": [],
        "coordinate_system": "Authored Blender metres, Z up, origin unchanged",
        "expected_foundation_depth_m": EXPECTED_FOUNDATION_DEPTHS,
    }
    for slug in SLUGS:
        report["assets"][slug] = check_asset(slug)

    if EXPORT_LOG.is_file():
        report["export_warnings"] = sum(
            "WARNING" in line or "Traceback" in line
            for line in EXPORT_LOG.read_text().splitlines()
        )
        report["export_log_status"] = "checked"
    else:
        report["export_warnings"] = None
        report["export_log_status"] = "not_checked"
    report["port_ray_checks"] = sum(
        lod["port_rays"]
        for asset in report["assets"].values()
        for lod in asset["lods"].values()
    )
    report["road_ray_checks"] = sum(
        lod["road_clearance_rays"]
        for asset in report["assets"].values()
        for lod in asset["lods"].values()
    )
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / "asset-validation.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(
        json.dumps(
            {
                "assets": len(report["assets"]),
                "port_ray_checks": report["port_ray_checks"],
                "road_ray_checks": report["road_ray_checks"],
                "export_warnings": report["export_warnings"],
                "export_log_status": report["export_log_status"],
                "failures": report["failures"],
            }
        )
    )


if __name__ == "__main__":
    main()
