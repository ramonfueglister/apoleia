#!/usr/bin/env python3
"""Convert a frozen native runtime run into Kit 1 telemetry and tile evidence.

No values are simulated. Geographic pixels come from the independently generated
anchor-projection.csv; observed camera/probe values come from runtime.json; RAM
comes from process-rss.json. The binding file records all source and output hashes.
"""
from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import importlib.util
import json
import math
import re
import time
from pathlib import Path


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", type=Path, help="Frozen runtime output directory")
    ap.add_argument("--run-root", type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument("--run-id", default=None)
    args = ap.parse_args()
    run = args.run_root.resolve()
    source = args.source.resolve()
    runtime_path = source / "runtime.json"
    rss_path = source / "process-rss.json"
    projection_path = source / "anchor-projection.csv"
    runtime = load(runtime_path)
    rss = load(rss_path)
    fixture = load(run / "fixture.json")
    config = load(run / "config.json")
    sources = load(run / "sources.json")
    grid = load(run / "data/tile-grid.json")
    anchors_path = run / "data/anchors.json"
    dataset_manifest_path = run / "data/derived/landscape.json"
    thresholds_path = run / "thresholds.md"

    expected_fixture_sha = sha(run / "fixture.json")
    expected_thresholds_sha = sha(thresholds_path)
    if runtime.get("fixture_sha256") != expected_fixture_sha:
        raise SystemExit("runtime fixture hash differs from frozen run fixture")
    if runtime.get("validation_thresholds_sha256") != expected_thresholds_sha:
        raise SystemExit("runtime threshold hash differs from frozen run thresholds")
    if runtime.get("manifest_sha256") != sha(run / "data/derived/landscape.json"):
        raise SystemExit("runtime dataset manifest hash differs from run manifest")
    if runtime.get("anchors_sha256") != sha(anchors_path):
        raise SystemExit("runtime anchor hash differs from run anchors")
    if runtime.get("mapping_revision") != fixture.get("mapping_version"):
        raise SystemExit("runtime mapping revision differs from fixture")

    point_map = {p["id"]: p for p in fixture["points"]}
    projection_spec = importlib.util.spec_from_file_location(
        "expected_projection", run / "docs/product-renderer/method/expected_projection.py"
    )
    projection_module = importlib.util.module_from_spec(projection_spec)
    projection_spec.loader.exec_module(projection_module)
    region = load(run / "region.json")
    csv_rows = {}
    with projection_path.open(newline="") as f:
        for row in csv.DictReader(f):
            csv_rows[(float(row["t_ms"]), row["anchor"])] = row
    rss_samples = sorted(rss["samples"], key=lambda x: x["t_ms"])
    rss_times = [x["t_ms"] for x in rss_samples]
    raw_samples = runtime["samples"]
    intervals = runtime["frame_intervals_ms"]
    telemetry_samples = []
    duplicate_timestamp_drops = []
    previous_raw = None
    closest_rss_delta_ms = 0.0
    peak_rss_bytes = int(rss["peak_rss_bytes"])
    peak_rss_time = max(rss_samples, key=lambda x: x["rss_bytes"])["t_ms"]
    nearest_index_to_peak = None
    for sample_index, sample in enumerate(raw_samples):
        if previous_raw is not None and float(sample["t_ms"]) <= float(previous_raw["t_ms"]):
            # The native logger can emit the final waypoint record and a regular
            # frame record at the same timestamp. Keep the waypoint record (which
            # carries the required return-state observation) and omit only the
            # later generic duplicate from this strictly ordered Kit adapter.
            if (float(sample["t_ms"]) == float(previous_raw["t_ms"])
                    and previous_raw.get("waypoint_id") is not None
                    and sample.get("waypoint_id") is None):
                duplicate_timestamp_drops.append({
                    "kept_sample_index": sample_index - 1,
                    "t_ms": float(sample["t_ms"]),
                    "kept_frame": previous_raw.get("frame"),
                    "kept_waypoint_id": previous_raw.get("waypoint_id"),
                    "dropped_sample_index": sample_index,
                    "dropped_frame": sample.get("frame"),
                    "reason": "later generic sample duplicates final waypoint timestamp",
                })
                previous_raw = sample
                continue
            raise SystemExit(
                f"runtime samples are not strictly increasing at index {sample_index}: "
                f"{previous_raw['t_ms']} then {sample['t_ms']}"
            )
        previous_raw = sample
        frame_index = int(sample["frame"]) - 1
        if frame_index < 0 or frame_index >= len(intervals):
            raise SystemExit(f"runtime frame index out of interval range: {sample['frame']}")
        frame_ms = float(intervals[frame_index])
        # Native sampled record must retain the per-frame timing at its recorded frame.
        if not math.isclose(frame_ms, float(sample["frame_ms"]), rel_tol=0, abs_tol=1e-9):
            raise SystemExit(f"sample/frame interval disagreement at frame {sample['frame']}")

        pos = bisect.bisect_left(rss_times, sample["t_ms"])
        candidates = [i for i in (pos - 1, pos) if 0 <= i < len(rss_samples)]
        rss_index = min(candidates, key=lambda i: abs(rss_times[i] - sample["t_ms"]))
        delta = abs(rss_times[rss_index] - sample["t_ms"])
        closest_rss_delta_ms = max(closest_rss_delta_ms, delta)
        if rss_index == max(range(len(rss_samples)), key=lambda i: rss_samples[i]["rss_bytes"]):
            nearest_index_to_peak = sample_index

        observations = []
        for probe in sample["anchor_probes"]:
            point = point_map.get(probe["anchor_id"])
            if point is None or not probe["in_viewport"]:
                continue
            if point["source_position"] != {
                "longitude": probe["source_lon"],
                "latitude": probe["source_lat"],
            }:
                raise SystemExit(f"source anchor identity differs: {probe['anchor_id']}")
            row = csv_rows.get((float(sample["t_ms"]), probe["anchor_id"]))
            if row is None:
                raise SystemExit(f"missing independent projected row: {sample['t_ms']} {probe['anchor_id']}")
            observations.append({
                "point_id": probe["anchor_id"],
                "source_position": point["source_position"],
                "expected_screen_xy": [float(row["expected_x_px"]), float(row["expected_y_px"])],
                "actual_screen_xy": [float(row["observed_x_px"]), float(row["observed_y_px"])],
            })

        # Kit's fixture schema also requires the overview camera-control point to
        # appear on its two endpoint waypoints. The renderer does not emit that
        # point as a triangle probe. Record it separately as the camera focus
        # projected to the viewport center; it is not one of the nine A05 anchors.
        if sample.get("waypoint_id") in {"wp-overview-start", "wp-overview-return"}:
            target = point_map["overview-target"]["source_position"]
            expected_center = projection_module.expected_pixel(
                target["longitude"], target["latitude"], 0.0, sample,
                region["extent"], 0,
            )
            actual_center = [
                sample["view_state"]["viewport"]["width_px"] / 2,
                sample["view_state"]["viewport"]["height_px"] / 2,
            ]
            observations.append({
                "point_id": "overview-target",
                "source_position": target,
                "expected_screen_xy": expected_center,
                "actual_screen_xy": actual_center,
            })

        telemetry_samples.append({
            "t_ms": float(sample["t_ms"]),
            "zoom_normalized": float(sample["zoom"]),
            "azimuth_degrees": float(sample["azimuth_degrees"]),
            "elevation_degrees": float(sample["elevation_degrees"]),
            "frame_ms": frame_ms,
            "memory_mb": rss_samples[rss_index]["rss_bytes"] / (1024 * 1024),
            "observations": observations,
            "waypoint_id": sample.get("waypoint_id"),
            "view_state": sample["view_state"],
        })

    # Ensure the sampled Kit stream includes the actual measured run peak. If the
    # 100 ms RSS sampling instant falls between renderer samples, attach that exact
    # measured peak to its nearest renderer sample; keep the source timestamp below.
    nearest_index_to_peak = min(
        range(len(raw_samples)),
        key=lambda i: abs(raw_samples[i]["t_ms"] - peak_rss_time),
    )
    telemetry_samples[nearest_index_to_peak]["memory_mb"] = peak_rss_bytes / (1024 * 1024)
    if max(x["memory_mb"] for x in telemetry_samples) != peak_rss_bytes / (1024 * 1024):
        raise SystemExit("converted telemetry does not retain measured peak process RSS")

    dataset_manifest = load(dataset_manifest_path)
    dataset_manifest_sha256 = sha(dataset_manifest_path)
    sources_manifest_sha256 = sha(run / "sources.json")
    product_build_components = {
        "schema_version": "kit1-product-build-components-v1",
        "dataset_revision": dataset_manifest.get("revision"),
        "dataset_manifest_sha256": dataset_manifest_sha256,
        "sources_revision": sources["revision"],
        "sources_manifest_sha256": sources_manifest_sha256,
        "mapping_revision": runtime["mapping_revision"],
        "camera_revision": runtime["camera_revision"],
        "profile_sha256": runtime["profile_sha256"],
        "renderer_source_sha256": runtime["renderer_source_sha256"],
        "renderer_asset_sha256": runtime["renderer_asset_sha256"],
        "packing_manifest_sha256": runtime["packing_manifest_sha256"],
        "water_distance_manifest_sha256": runtime["water_distance_manifest_sha256"],
        "anchors_sha256": runtime["anchors_sha256"],
        "fixture_sha256": runtime["fixture_sha256"],
        "fixture_controls_sha256": runtime["fixture_controls_sha256"],
        "validation_thresholds_sha256": runtime["validation_thresholds_sha256"],
    }
    product_revision_material = json.dumps(product_build_components, sort_keys=True, separators=(",", ":"))
    product_revision_sha256 = hashlib.sha256(product_revision_material.encode("utf-8")).hexdigest()
    build_revision = "product-build-sha256:" + product_revision_sha256
    run_id = args.run_id or source.name
    telemetry = {
        "schema_version": "kit1-ops-v5",
        "kind": "telemetry",
        "synthetic": False,
        "run_id": run_id,
        "build_revision": build_revision,
        "mapping_revision": runtime["mapping_revision"],
        "sampling_method": (
            "Native runtime samples only; frame_ms is the matching raw frame interval at each emitted sample. "
            "Visible fixture-anchor observations join the independent mmap/scalar projection CSV by exact sample time and anchor ID. "
            "Off-screen/raw probes remain in the source runtime and projection CSV. The two overview-target waypoint observations "
            "are a separate derived camera-focus-to-viewport-center control point; the runtime emits no triangle probe for it, "
            "and it is not one of the nine hashed A05 data anchors. A later generic raw record at the exact final-waypoint timestamp "
            "is omitted from this ordered adapter; the original raw record remains intact and the decision is listed in conversion-binding.json."
        ),
        "warmup_description": (
            "Keep startup and prewarm frames in the sample stream. memory_mb uses the nearest observed process RSS sample; "
            "the exact run peak is attached to its nearest renderer sample if sampling instants differ. See conversion-binding.json."
        ),
        "samples": telemetry_samples,
        "source_crs": "EPSG:4326",
    }

    states = {x["id"]: x for x in fixture["view_states"]}
    cases = {x["id"]: x for x in fixture["tile_cases"]}
    by_state = {}
    for sample in raw_samples:
        by_state.setdefault(sample["view_state_id"], []).append(sample)

    def choose_sample(state_id: str, last: bool = False):
        candidates = by_state.get(state_id, [])
        if not candidates:
            raise SystemExit(f"runtime has no sample for fixture state {state_id}")
        return candidates[-1] if last else candidates[0]

    tile_probes = []
    probe_index = {}
    for case_id, case in cases.items():
        point_id = case["point_id"]
        for state_id in case["view_state_ids"]:
            sample = choose_sample(state_id)
            hit = next((x for x in sample["anchor_probes"] if x["anchor_id"] == point_id), None)
            if hit is None:
                raise SystemExit(f"runtime sample lacks tile anchor {point_id} at {state_id}")
            parts = hit["tile_id"].split(":")
            if len(parts) != 3:
                raise SystemExit(f"unexpected observed tile id: {hit['tile_id']}")
            row, column = int(parts[1]), int(parts[2])
            ident = f"tileprobe-{case_id}-{state_id}"
            probe = {
                "case_id": case_id,
                "view_state_id": state_id,
                "view_state": sample["view_state"],
                "t_ms": float(sample["t_ms"]),
                "canonical_tile_id": hit["tile_id"],
                "logical_index": {"region": case["logical_index"]["region"], "row": row, "column": column},
                "logical_cell_width": grid["cell_size_m"],
                "logical_cell_height": grid["cell_size_m"],
                "id": ident,
            }
            tile_probes.append(probe)
            probe_index[(case_id, state_id, False)] = ident

    navigation_ids = []
    nav = fixture["tile_navigation"]
    for i, state_id in enumerate(nav["view_state_sequence"]):
        last = i == len(nav["view_state_sequence"]) - 1 and state_id == nav["view_state_sequence"][0]
        probe_id = probe_index.get((nav["case_id"], state_id, last))
        if probe_id is None and last:
            # Create an explicitly later second overview probe from the return waypoint.
            sample = choose_sample(state_id, last=True)
            case = cases[nav["case_id"]]
            hit = next(x for x in sample["anchor_probes"] if x["anchor_id"] == case["point_id"])
            parts = hit["tile_id"].split(":")
            ident = f"tileprobe-{nav['case_id']}-{state_id}-return"
            tile_probes.append({
                "case_id": nav["case_id"],
                "view_state_id": state_id,
                "view_state": sample["view_state"],
                "t_ms": float(sample["t_ms"]),
                "canonical_tile_id": hit["tile_id"],
                "logical_index": {"region": case["logical_index"]["region"], "row": int(parts[1]), "column": int(parts[2])},
                "logical_cell_width": grid["cell_size_m"],
                "logical_cell_height": grid["cell_size_m"],
                "id": ident,
            })
            probe_id = ident
        if probe_id is None:
            raise SystemExit(f"navigation probe missing {nav['case_id']} {state_id}")
        navigation_ids.append(probe_id)

    tiles = {
        "schema_version": "kit1-ops-v5",
        "kind": "tiles",
        "synthetic": False,
        "run_id": run_id,
        "build_revision": build_revision,
        "sources_revision": sources["revision"],
        "mapping_revision": runtime["mapping_revision"],
        "fixture_revision": fixture["revision"],
        "grid_id": config["tiles"]["grid_id"],
        "grid_revision": config["tiles"]["grid_revision"],
        "logical_shape": "square",
        "grid_definition": config["tiles"]["definition"],
        "presentation": "natural_landscape_only",
        "gui_visible": False,
        "grid_visible": False,
        "selection_highlight_visible": False,
        "probes": tile_probes,
        "navigation_probe_ids": navigation_ids,
    }

    telemetry_path = run / "telemetry.json"
    tiles_path = run / "tiles.json"
    telemetry_path.write_text(json.dumps(telemetry, ensure_ascii=False, indent=2) + "\n")
    tiles_path.write_text(json.dumps(tiles, ensure_ascii=False, indent=2) + "\n")

    inputs = [runtime_path, rss_path, projection_path, run / "fixture.json", run / "config.json", run / "sources.json", anchors_path, run / "data/projection.json", run / "data/tile-grid.json", dataset_manifest_path, thresholds_path, Path(__file__), run / "docs/product-renderer/method/expected_projection.py", run / "docs/product-renderer/method/analyze_runtime.py"]
    binding = {
        "schema_version": "kit1-runtime-conversion-binding-v1",
        "run_id": run_id,
        "build_revision": build_revision,
        "renderer_source_sha256": runtime["renderer_source_sha256"],
        "renderer_source_revision": "renderer-source-sha256:" + runtime["renderer_source_sha256"],
        "dataset_revision": dataset_manifest.get("revision"),
        "dataset_manifest_sha256": dataset_manifest_sha256,
        "product_build_components": product_build_components,
        "build_revision_method": "SHA-256 of canonical JSON (sorted keys, compact separators) in product_build_components; this is a run assembly fingerprint, not a claim about a compiled binary hash",
        "runtime_file_mtime_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(runtime_path.stat().st_mtime)),
        "timestamp_semantics": "runtime.json filesystem mtime; native runtime file does not contain wall-clock start UTC",
        "rss_peak_source_t_ms": peak_rss_time,
        "rss_peak_nearest_runtime_t_ms": raw_samples[nearest_index_to_peak]["t_ms"],
        "rss_peak_nearest_runtime_delta_ms": abs(peak_rss_time - raw_samples[nearest_index_to_peak]["t_ms"]),
        "max_nearest_rss_sample_delta_ms": closest_rss_delta_ms,
        "frame_percentile_note": "Kit telemetry frame_p95_ms is computed over the native emitted sample records; independent all-frame distribution remains in the source runtime/reviewer JSON.",
        "memory_note": "memory_mb uses MiB values from process RSS bytes because the predeclared memory limit is explicitly 2048 MiB; no decimal-GB conversion.",
        "tile_note": "Observed canonical tile IDs are copied from runtime anchor_probes; row/column are parsed from the observed id format and checked against fixture cases. Cell size comes from the bound tile-grid manifest.",
        "overview_target_note": "The fixture requires the overview-target point at start/return. It is derived from the commanded camera focus and viewport center because runtime anchor_probes contains only the nine hashed data anchors; do not interpret it as an observed active-terrain-triangle probe or an A05 anchor.",
        "duplicate_timestamp_note": "The Kit adapter requires strictly increasing sample times. Only an immediately later generic raw sample sharing the exact final waypoint timestamp is dropped; the waypoint record is retained. Native runtime.json is unchanged.",
        "raw_sample_record_count": len(raw_samples),
        "kit_sample_record_count": len(telemetry_samples),
        "dropped_raw_sample_indices": [x["dropped_sample_index"] for x in duplicate_timestamp_drops],
        "duplicate_timestamp_drops": duplicate_timestamp_drops,
        "inputs": [{"path": str(p.relative_to(run)) if p.is_relative_to(run) else str(p), "sha256": sha(p)} for p in inputs],
        "outputs": {
            "telemetry.json": sha(telemetry_path),
            "tiles.json": sha(tiles_path),
        },
    }
    binding_path = run / "conversion-binding.json"
    binding_path.write_text(json.dumps(binding, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({
        "run_id": run_id,
        "build_revision": build_revision,
        "telemetry_samples": len(telemetry_samples),
        "telemetry_peak_rss_mib": max(x["memory_mb"] for x in telemetry_samples),
        "telemetry_peak_frame_p95_ms": sorted(x["frame_ms"] for x in telemetry_samples)[math.ceil(.95 * len(telemetry_samples)) - 1],
        "tile_probes": len(tile_probes),
        "navigation_probe_ids": navigation_ids,
        "telemetry_sha256": sha(telemetry_path),
        "tiles_sha256": sha(tiles_path),
        "binding_sha256": sha(binding_path),
    }, indent=2))


if __name__ == "__main__":
    main()
