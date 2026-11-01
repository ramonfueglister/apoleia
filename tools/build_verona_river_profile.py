#!/usr/bin/env python3
"""Freeze an audited near-Verona profile; this is not a global hydrology bake.

Input is actual GPU terrain samples ordered using independently inferred Adige
flow direction (tools/tests/analyze_verona_river_profile.py). Lower-only running
minimum is a deliberate display repair, not a surveyed historical water level.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = (-676.959516530886, -498.1516046706583)

def build(report):
    points = []
    height = float("inf")
    for sample in report["samples"]:
        # Samples are twentieths of the 0.25 km segment grid. Snap removes GPU
        # world-position float32 noise without moving the underlying tile path.
        xy = [round((sample["xz"][i] - ORIGIN[i]) * 80) / 80 for i in (0, 1)]
        height = min(height, sample["height"], sample["left_height"], sample["right_height"])
        if not points or xy != points[-1][:2]:
            points.append(xy + [height])
    return {"origin": ORIGIN, "direction": report["direction"],
            "source": "GPU actual terrain baseline, lower-only running minimum of center and both transverse samples; bounded Verona repair",
            "points": points}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "app/assets/environment/verona_river/profile.json")
    args = parser.parse_args()
    args.output.write_text(json.dumps(build(json.loads(args.input.read_text())), indent=2))
