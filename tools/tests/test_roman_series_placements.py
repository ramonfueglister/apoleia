"""Read-only contract checks for the 19 authored Roman building placements.

Uses the existing numpy/Pillow tooling environment, e.g.:
build/verona-venv/bin/python -m unittest discover -s tools/tests -p test_roman_series_placements.py
No plan rebake, atlas writes, simulation edits or Godot import is performed.
"""
import json
from pathlib import Path
import struct
import unittest

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
PLAN_DIR = ROOT / "artifacts/render-data/city-plans-r1"
MODEL_DIR = ROOT / "app/assets/buildings"
EXPECTED_MODELS = {
    "amphitheater", "theater", "capitolium", "thermen", "basilika",
    "domus", "insula", "villa_rustica", "baeckerei", "toepferei",
    "schmiede", "muehle", "curia", "bibliothek", "horreum", "macellum",
    "leuchtturm", "rundtempel", "stadttor",
}
VERONA_REPLACEMENTS = {
    "amphitheater": "verona_arena", "theater": "verona_theatre",
    "capitolium": "verona_capitolium", "thermen": "verona_baths",
    "basilika": "verona_basilica",
}


def cells(rect):
    x, y, w, h = rect
    return {(x + dx, y + dy) for dy in range(h) for dx in range(w)}


class RomanSeriesPlacements(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = json.loads((PLAN_DIR / "city-plans-x1.json").read_text())
        cls.atlas = Image.open(PLAN_DIR / cls.plan["atlas"]).convert("RGB")
        cls.slots = {(x, y): slot for x, y, slot in cls.plan["page_slots"]}
        cls.entries = json.loads((MODEL_DIR / "roman_series_placements.json").read_text())["entries"]
        cls.by_id = {entry["id"]: entry for entry in cls.entries}

    @classmethod
    def texel(cls, x, y):
        size = cls.plan["page_parcels"]
        slot = cls.slots.get((x // size, y // size))
        if slot is None:
            return (0, 0, 0)
        per_row = cls.plan["atlas_slots_per_row"]
        return cls.atlas.getpixel(((slot % per_row) * size + x % size,
                                  (slot // per_row) * size + y % size))

    def test_exactly_nineteen_distinct_models_and_complete_schema(self):
        self.assertEqual(len(self.entries), 19)
        self.assertEqual(set(self.by_id), EXPECTED_MODELS)
        for entry in self.entries:
            with self.subTest(model=entry["id"]):
                self.assertIn(entry["city"], self.plan["cities"])
                self.assertTrue(entry["label"])
                self.assertTrue(entry["notes"])
                self.assertEqual(len(entry["rect"]), 4)
                self.assertTrue(all(type(value) is int for value in entry["rect"]))
                self.assertGreater(entry["rect"][2], 0)
                self.assertGreater(entry["rect"][3], 0)
                self.assertIn(entry["turns"], range(4))
                self.assertTrue(entry["expected_kinds"])
                self.assertEqual(len(set(entry["expected_kinds"])), len(entry["expected_kinds"]))

    def test_every_reserved_cell_matches_current_atlas(self):
        for entry in self.entries:
            with self.subTest(model=entry["id"]):
                city = self.plan["cities"][entry["city"]]
                ox, oy = city["origin"]
                w, h = city["size"]
                occupied = cells(entry["rect"])
                self.assertTrue(all(ox <= x < ox + w and oy <= y < oy + h for x, y in occupied))
                actual = {self.texel(x, y)[0] for x, y in occupied}
                self.assertEqual(actual, set(entry["expected_kinds"]))
                # No unspecified, open-land, water, street, bridge or tomb cells.
                self.assertFalse(actual & {0, 7, 10, 11, 12, 13})
                if entry["id"] != "stadttor":
                    self.assertFalse(actual & {8, 9})

    def test_placements_never_overlap_each_other(self):
        for i, entry in enumerate(self.entries):
            occupied = cells(entry["rect"])
            for other in self.entries[i + 1:]:
                self.assertFalse(occupied & cells(other["rect"]), (entry["id"], other["id"]))

    def test_five_verona_models_use_exact_existing_landmark_rectangles(self):
        actual = {e["id"]: e["landmark"] for e in self.entries if "landmark" in e}
        self.assertEqual(actual, VERONA_REPLACEMENTS)
        buildings = self.plan["cities"]["verona"]["buildings"]
        for model, landmark in VERONA_REPLACEMENTS.items():
            entry = self.by_id[model]
            original = next(b for b in buildings if b.get("landmark") == landmark)
            self.assertEqual(entry["city"], "verona")
            self.assertEqual(entry["rect"], original["parcels"])

    def test_known_buildings_and_unselected_landmarks_stay_untouched(self):
        # Only these two non-landmark named footprints are intentionally reused.
        named_reuse = {
            "horreum": ("rome", "Porticus Aemilia (horrea)"),
            "leuchtturm": ("alexandria", "Pharos"),
        }
        for entry in self.entries:
            occupied = cells(entry["rect"])
            for city_id, city in self.plan["cities"].items():
                for building in city.get("buildings", []):
                    if not occupied & cells(building["parcels"]):
                        continue
                    if entry.get("landmark") and entry["landmark"] == building.get("landmark"):
                        self.assertEqual(city_id, entry["city"])
                    else:
                        self.assertEqual(named_reuse.get(entry["id"]), (city_id, building["name"]),
                                         (entry["id"], city_id, building["name"]))
                    self.assertEqual(entry["rect"], building["parcels"])

    def test_accepted_taverna_and_forum_remain_reserved(self):
        taverna = (18455, 6919)
        self.assertEqual(self.plan["cities"]["verona"]["origin"], [18445, 6906])
        self.assertEqual(self.texel(*taverna)[0], 1)
        self.assertEqual(self.texel(*taverna)[2] >> 6, 2)
        forum = next(b for b in self.plan["cities"]["verona"]["buildings"]
                     if b.get("landmark") == "verona_forum")
        for entry in self.entries:
            self.assertNotIn(taverna, cells(entry["rect"]))
            self.assertFalse(cells(forum["parcels"]) & cells(entry["rect"]))

    def test_verona_workshop_fronts_follow_existing_access(self):
        directions = [(0, -1), (1, 0), (0, 1), (-1, 0)]
        for model in ["baeckerei", "schmiede", "insula", "muehle"]:
            entry = self.by_id[model]
            x, y, w, h = entry["rect"]
            self.assertEqual((w, h), (1, 1))
            front = self.texel(x, y)[2] >> 6
            self.assertEqual(entry["turns"], (front - 2) % 4)
            dx, dy = directions[front]
            self.assertIn(self.texel(x + dx, y + dy)[0], [5, 7, 9, 10])

    def test_gate_spans_only_wall_gate_wall_and_preserves_road_axis(self):
        entry = self.by_id["stadttor"]
        x, y, w, h = entry["rect"]
        self.assertEqual((w, h), (3, 1))
        self.assertEqual([self.texel(x + i, y)[0] for i in range(3)], [8, 9, 8])
        self.assertIn(entry["turns"], [0, 2])
        gate = self.texel(x + 1, y)
        self.assertEqual((gate[1] >> 4) & 5, 5)  # Road links north and south.
        self.assertIn(self.texel(x + 1, y - 1)[0], [7, 9, 10])
        self.assertIn(self.texel(x + 1, y + 1)[0], [7, 9, 10])

    def test_assets_exist_and_can_fit_with_uniform_scaling(self):
        parcel_m = self.plan["parcel_km"] / 0.0238
        for entry in self.entries:
            model = entry["id"]
            with self.subTest(model=model):
                self.assertTrue((MODEL_DIR / model / (model + ".glb")).is_file())
                metadata = json.loads((MODEL_DIR / model / "model.json").read_text())
                self.assertTrue(metadata["metres"])
                lo, hi = metadata["source_bounds_xyz"]
                width, depth = hi[0] - lo[0], hi[1] - lo[1]
                self.assertGreater(width, 0)
                self.assertGreater(depth, 0)
                if entry["turns"] % 2:
                    width, depth = depth, width
                reserved_w = entry["rect"][2] * parcel_m * 0.9
                reserved_d = entry["rect"][3] * parcel_m * 0.9
                factor = min(1.0, reserved_w / width, reserved_d / depth)
                self.assertGreater(factor, 0)
                self.assertLessEqual(width * factor, reserved_w + 1e-8)
                self.assertLessEqual(depth * factor, reserved_d + 1e-8)
                # Human-scale homes/shops do not need any arbitrary shrinkage.
                if model in {"domus", "insula", "villa_rustica", "baeckerei", "toepferei", "schmiede", "muehle"}:
                    self.assertEqual(factor, 1.0)

    def test_gate_mesh_really_leaves_the_existing_carriageway_open(self):
        # Test actual exported triangles, not just a declared portal or atlas kind.
        # glTF coordinates are X east, Y up, Z south; all exporter node transforms
        # are identity. A north-south ray intersects a triangle iff the sampled
        # (X, Y) lies inside its non-degenerate projection onto the X/Y plane.
        blob = (MODEL_DIR / "stadttor/stadttor.glb").read_bytes()
        json_size = struct.unpack_from("<I", blob, 12)[0]
        gltf = json.loads(blob[20:20 + json_size])
        binary = memoryview(blob)[28 + json_size:]

        def read_accessor(index):
            accessor = gltf["accessors"][index]
            view = gltf["bufferViews"][accessor["bufferView"]]
            dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[accessor["componentType"]]
            components = {"SCALAR": 1, "VEC3": 3}[accessor["type"]]
            itemsize = np.dtype(dtype).itemsize
            return np.ndarray((accessor["count"], components), dtype=dtype, buffer=binary,
                              offset=view.get("byteOffset", 0) + accessor.get("byteOffset", 0),
                              strides=(view.get("byteStride", components * itemsize), itemsize))

        entry = self.by_id["stadttor"]
        metadata = json.loads((MODEL_DIR / "stadttor/model.json").read_text())
        lo, hi = metadata["source_bounds_xyz"]
        parcel_m = self.plan["parcel_km"] / 0.0238
        fit = min(1.0, entry["rect"][2] * parcel_m * .9 / (hi[0] - lo[0]),
                  entry["rect"][3] * parcel_m * .9 / (hi[1] - lo[1]))
        x, y, _, _ = entry["rect"]
        rank = (self.texel(x + 1, y)[1] >> 2) & 3
        half_road = [.1, .12, .09, .06][rank] * parcel_m
        centre_x = (lo[0] + hi[0]) / 2
        for tag in ["detail", "medium"]:
            root = next(n for n in gltf["nodes"] if n.get("name") == "Model_" + tag)
            triangles = []
            for child in root["children"]:
                node = gltf["nodes"][child]
                self.assertFalse(set(node) & {"matrix", "translation", "rotation", "scale"})
                for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
                    positions = read_accessor(primitive["attributes"]["POSITION"])
                    indices = read_accessor(primitive["indices"]).ravel()
                    triangles.append(positions[indices].reshape(-1, 3, 3))
            projected = np.concatenate(triangles)[:, :, :2]
            a, b, c = projected[:, 0], projected[:, 1], projected[:, 2]
            v0, v1 = b - a, c - a
            determinant = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
            useful = np.abs(determinant) > 1e-8
            a, v0, v1, determinant = a[useful], v0[useful], v1[useful], determinant[useful]
            # Sample centre plus both carriageway sides, at waist and head height.
            for road_x in [-half_road * .8, 0, half_road * .8]:
                for height in [.9, 1.8]:
                    point = np.array([centre_x + road_x / fit, lo[2] + height / fit])
                    rel = point - a
                    u = (rel[:, 0] * v1[:, 1] - v1[:, 0] * rel[:, 1]) / determinant
                    v = (v0[:, 0] * rel[:, 1] - rel[:, 0] * v0[:, 1]) / determinant
                    blocked = (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6)
                    self.assertFalse(bool(blocked.any()),
                                     f"Gate {tag} obstructs road at x={road_x:.2f}m, height={height:.2f}m")


if __name__ == "__main__":
    unittest.main()
