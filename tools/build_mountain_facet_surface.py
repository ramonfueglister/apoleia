#!/usr/bin/env python3
"""Display atlas with faceted low-poly mountains (look pass).

The product macro atlas interpolates 24 km control addresses, which turns
mountain ranges into a few large planar blocks. In relief areas this blends
back to the fixed 2 km base grid and sharpens its ridges; plains, coast and
water keep the macro heights exactly. Run build_fixed_display_lods.py on the
output afterwards to derive chunks.json.
"""
import argparse, hashlib, json, pathlib
import numpy as np
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--macro-dir', default='artifacts/render-data/fixed-source-v2-macro-r1')
parser.add_argument('--base-dir', default='artifacts/render-data/fixed-source-v2-base-r1')
parser.add_argument('--output', default='artifacts/render-data/fixed-source-v2-mountain-r1')
parser.add_argument('--ridge-gain', type=float, default=0.7)
args = parser.parse_args()
MACRO, BASE, OUT = ROOT / args.macro_dir, ROOT / args.base_dir, ROOT / args.output

def load(folder):
    m = json.loads((folder / 'surface.json').read_text())
    q = np.fromfile(folder / 'height.rg8', dtype=np.uint8).reshape(m['height'], m['width'], 2)
    return m, (q[..., 0].astype(np.float32) * 256 + q[..., 1]) * .25 - 8192

def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)

macro_m, macro = load(MACRO)
base_m, base = load(BASE)
if (macro_m['width'], macro_m['height'], macro_m['world_min']) != (base_m['width'], base_m['height'], base_m['world_min']):
    raise RuntimeError('macro/base grid mismatch')

# Relief mask: local 14 km range and elevation; zero on and near water.
relief = ndimage.maximum_filter(base, 7) - ndimage.minimum_filter(base, 7)
land = macro > 0.5
near_water = ndimage.binary_dilation(~land, iterations=3)
mask = smooth(relief, 300, 1100) * smooth(macro, 250, 900) * (~near_water)
mask = ndimage.gaussian_filter(mask, 1.5)
# Ridge sharpening: boost the 6 km band-pass of the base grid, more on crests.
low = ndimage.gaussian_filter(base, 3.0)
detail = base - low
crest = np.where(detail > 0, detail * (1 + 0.5 * args.ridge_gain), detail * 0.8)
mountain = low + detail + args.ridge_gain * crest
result = macro * (1 - mask) + mountain * mask
result = np.where(land, np.maximum(result, 1.0), macro)

OUT.mkdir(parents=True, exist_ok=False)
code = np.rint((result + 8192) / .25).astype(np.int64)
if code.min() < 0 or code.max() > 65535:
    raise RuntimeError('encoding overflow')
packed = np.stack([code // 256, code % 256], axis=-1).astype(np.uint8)
packed.tofile(OUT / 'height.rg8')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
policy = json.loads((MACRO / 'policy.json').read_text())
policy.update({'revision': 'fixed-diorama-mountain-facets-r1',
    'look_pass': 'relief areas blend the macro atlas back to the fixed 2km base grid with ridge sharpening; plains/coast/water keep macro heights',
    'ridge_gain': args.ridge_gain, 'macro_surface_manifest_sha256': sha(MACRO / 'surface.json'),
    'base_surface_manifest_sha256': sha(BASE / 'surface.json'),
    'mountain_mask_mean': float(mask.mean()), 'height_range_source_equivalent_m': [float(result.min()), float(result.max())]})
(OUT / 'policy.json').write_text(json.dumps(policy, indent=2) + '\n')
m = dict(macro_m)
m.pop('chunks', None)
m['revision'] = 'fixed-diorama-mountain-facets-r1'
m['policy'] = {'path': 'policy.json', 'sha256': sha(OUT / 'policy.json')}
m['height_payload'] = {'path': 'height.rg8', 'sha256': sha(OUT / 'height.rg8'), 'bytes': (OUT / 'height.rg8').stat().st_size}
(OUT / 'surface.json').write_text(json.dumps(m, indent=2) + '\n')
print(json.dumps({'output': str(OUT), 'mask_mean': float(mask.mean()), 'max_change_m': float(np.abs(result - macro).max())}))
