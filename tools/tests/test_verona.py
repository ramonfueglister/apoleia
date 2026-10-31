"""Reference-city invariants. Run with numpy/Pillow installed:
python -m unittest discover -s tools/tests -p test_verona.py
"""
import json
import math
from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import city_plans as cp


class VeronaPlan(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((cp.CITY_DIR / 'verona.json').read_text())
        cls.terrain = cp.Terrain()
        cls.g = cp.build(cls.data, 1, terrain=cls.terrain)
        cls.baked = json.loads((cp.ROOT / 'artifacts/render-data/city-plans-r1/city-plans-x1.json').read_text())['cities']['verona']

    def test_every_reference_model_has_one_complete_reserved_block(self):
        g = self.g
        self.assertEqual(len(self.baked['buildings']), 6)
        for k, b in enumerate(self.data['buildings']):
            cells = np.argwhere(g['building'] == k)
            self.assertGreater(len(cells), 0, b['name'])
            lo, hi = cells.min(0), cells.max(0)
            self.assertEqual(len(cells), int(np.prod(hi - lo + 1)), b['name'])
            expected = [int(g['i0'] + lo[1]), int(g['j0'] + lo[0]), int(hi[1] - lo[1] + 1), int(hi[0] - lo[0] + 1)]
            entry = next(e for e in self.baked['buildings'] if e['name'] == b['name'])
            self.assertEqual(entry['parcels'], expected)
            self.assertEqual(entry['landmark'], b['model'])
            # Both water categories and the original residential core stay clear.
            for r, q in cells:
                self.assertEqual(self.terrain.water(g['i0'] + q, g['j0'] + r), 0, b['name'])
                self.assertFalse(g['urban'][r, q], b['name'])
            self.assertNotIn(cp.K['water'], g['kind'][g['building'] == k])

    def test_rule_models_fit_without_downscaling(self):
        for b in self.data['buildings']:
            x, z = b['size_m']
            factor = (100 / (x * z)) ** (1 / 3)
            rule = (x * factor, z * factor)
            model = cp.USER_SIZED_M[b['model']]
            # Room for voxel rounding and plinth, not a scaled one-parcel toy.
            for actual, reserved in zip(rule, model):
                self.assertGreaterEqual(reserved, math.ceil(actual / .25) * .25 + 1)
            block = cp.parcel_size(self.g['plan'], b)
            for metres, km in zip(model, block):
                self.assertGreaterEqual(km * cp.LANDMARK_PLAN_REACH + 1e-9, metres * cp.DIORAMA_KM_PER_M)

    def test_housing_and_reproducibility(self):
        self.assertGreaterEqual(int(np.isin(self.g['kind'], [cp.K[k] for k in cp.DWELLING]).sum()), 8)
        again = cp.build(self.data, 1, terrain=self.terrain)
        for key in ('kind', 'building', 'rank', 'surface', 'links'):
            np.testing.assert_array_equal(self.g[key], again[key])

    def test_names_elsewhere_do_not_activate_verona_or_rome_models(self):
        other = cp.Plan({'id': 'carthage', 'centre': [10.3, 36.8]}, 1)
        for b in self.data['buildings']:
            self.assertIsNone(cp.ruled_model(other, b))
        self.assertIsNone(cp.ruled_model(other, {'name': 'Thermae Antoninianae'}))


if __name__ == '__main__':
    unittest.main()
