#!/usr/bin/env python3
"""Create immutable-source, run-local report views of data manifests.

The adapter changes only byte-identical relative-path aliases and gives the
frozen data revision and renderer source a composite product-build identity.
It does not repair or fill any measurements, budgets, coverage, treatment, or
policy decisions. Original files and hashes are recorded in the binding.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path

RUN = Path(__file__).resolve().parents[1]

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def read(rel: str):
    return json.loads((RUN / rel).read_text())

def write(rel: str, value):
    path = RUN / rel
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    return path

def main() -> None:
    config = read("config.json")
    coverage = read("coverage.json")
    derivation = read("derivation.json")
    conversion = read("conversion-binding.json")
    original = {
        "coverage.json": sha(RUN / "coverage.json"),
        "derivation.json": sha(RUN / "derivation.json"),
        "config.json": sha(RUN / "config.json"),
        "region.json": sha(RUN / "region.json"),
        "data/region.json": sha(RUN / "data/region.json"),
        "geodata_policy.json": sha(RUN / "geodata_policy.json"),
        "data/geodata_policy.json": sha(RUN / "data/geodata_policy.json"),
        "conversion-binding.json": sha(RUN / "conversion-binding.json"),
    }
    if original["region.json"] != original["data/region.json"]:
        raise SystemExit("region aliases differ by content; refusing normalization")
    if original["geodata_policy.json"] != original["data/geodata_policy.json"]:
        raise SystemExit("policy aliases differ by content; refusing normalization")
    expected_region = {"artifact_path": config["region_path"], "sha256": original["region.json"]}
    expected_policy_path = config["geodata_policy_path"]
    if sha(RUN / expected_policy_path) != original["data/geodata_policy.json"]:
        raise SystemExit("config policy does not resolve to byte-identical policy")
    if coverage["region_definition"]["sha256"] != original["data/region.json"]:
        raise SystemExit("coverage region source hash mismatch; refusing normalization")
    if derivation["region_definition"]["sha256"] != original["data/region.json"]:
        raise SystemExit("derivation region source hash mismatch; refusing normalization")
    if derivation["policy"]["sha256"] != original["data/geodata_policy.json"]:
        raise SystemExit("derivation policy source hash mismatch; refusing normalization")

    coverage_view = dict(coverage)
    coverage_view["region_definition"] = expected_region
    derivation_view = dict(derivation)
    derivation_view["region_definition"] = expected_region
    derivation_view["policy"] = {"artifact_path": expected_policy_path, "sha256": original["geodata_policy.json"]}
    derivation_view["build_revision"] = conversion["build_revision"]

    coverage_out = write("report-coverage.json", coverage_view)
    derivation_out = write("report-derivation.json", derivation_view)
    binding = {
        "schema_version": "kit1-report-manifest-adapter-v1",
        "run_id": RUN.name,
        "build_revision": conversion["build_revision"],
        "build_revision_method": conversion["build_revision_method"],
        "source_manifests": {
            "coverage": {"path": "coverage.json", "sha256": original["coverage.json"], "revision": coverage["revision"]},
            "derivation": {"path": "derivation.json", "sha256": original["derivation.json"], "data_build_revision": derivation["build_revision"]},
        },
        "alias_normalizations": [
            {"field": "coverage.region_definition.artifact_path", "from": "data/region.json", "to": config["region_path"], "sha256_unchanged": original["region.json"]},
            {"field": "derivation.region_definition.artifact_path", "from": "data/region.json", "to": config["region_path"], "sha256_unchanged": original["region.json"]},
            {"field": "derivation.policy.artifact_path", "from": "data/geodata_policy.json", "to": expected_policy_path, "sha256_unchanged": original["geodata_policy.json"]},
            {"field": "derivation.build_revision", "from": derivation["build_revision"], "to": conversion["build_revision"], "basis": "composite run/product identity; original dataset revision retained above", "data_measurements_changed": False},
        ],
        "unchanged_inputs": original,
        "outputs": {
            "report-coverage.json": sha(coverage_out),
            "report-derivation.json": sha(derivation_out),
        },
        "limitations": [
            "No coverage result, source measurement, scope, sample, budget, topology result, or visible landcover treatment is changed or inferred.",
            "The adapter does not convert missing derivation metrics or incomplete topology classes into evidence.",
            "The source manifest remains the authoritative record; these copies exist only to express byte-identical aliases and the composite run build identity required by the report contract.",
        ],
    }
    path = write("report-manifest-binding.json", binding)
    print(json.dumps({"build_revision": binding["build_revision"], "outputs": binding["outputs"], "binding_sha256": sha(path)}, indent=2))

if __name__ == "__main__":
    main()
