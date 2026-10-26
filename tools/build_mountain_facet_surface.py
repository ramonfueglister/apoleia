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
parser.add_argument('--compress-m', type=float, default=1900.0)
parser.add_argument('--peak-spacing', type=float, default=3.5, help='grid nodes (2 km)')
parser.add_argument('--peak-height', type=float, default=780.0)
parser.add_argument('--hill-m', type=float, default=45.0)
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
# Fade out over 3..12 grid nodes (6..24 km) from water: no coastal walls.
water_distance = ndimage.distance_transform_edt(land)
mask = smooth(relief, 220, 900) * smooth(macro, 180, 700) * smooth(water_distance, 3, 12)
mask = ndimage.gaussian_filter(mask, 2.0) * (water_distance > 2)
# Ridge sharpening: boost the 6 km band-pass of the base grid, more on crests.
low = ndimage.gaussian_filter(base, 3.0)
detail = base - low
crest = np.where(detail > 0, detail * (1 + 0.5 * args.ridge_gain), detail * 0.8)
mountain = low + detail + args.ridge_gain * crest
# Logarithmic height compression in relief areas: the 12x display scale
# otherwise turns 2 km grid steps into near-vertical striped walls.
H0 = args.compress_m
mountain = H0 * np.log1p(np.maximum(mountain, 0) / H0)
# Chains of many small pyramid peaks on a jittered lattice, strongest on
# crests (positive band-pass), as in the reference.
rng = np.random.default_rng(20261026)
S = args.peak_spacing
h, w = base.shape
gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
cy, cx = np.floor(gy / S), np.floor(gx / S)
peaks = np.zeros_like(base)
for oy in (-1, 0, 1):
    for ox in (-1, 0, 1):
        ky, kx = cy + oy, cx + ox
        seed = (ky * 7919 + kx * 104729).astype(np.int64) % 1000003
        jy = (np.sin(seed * 12.9898) * 43758.5453) % 1.0
        jx = (np.sin(seed * 78.233) * 12345.6789) % 1.0
        amp = 0.6 + 0.4 * ((np.sin(seed * 3.7) * 9631.4) % 1.0)
        py, px = (ky + 0.2 + 0.6 * jy) * S, (kx + 0.2 + 0.6 * jx) * S
        cone = np.clip(1 - (np.abs(gy - py) + np.abs(gx - px)) / (0.8 * S), 0, 1) * amp
        peaks = np.maximum(peaks, cone)
crestness = smooth(detail, -60, 160)
mountain = mountain + args.peak_height * peaks * (0.35 + 0.65 * crestness) * smooth(mountain, 300, 900)
result = macro * (1 - mask) + mountain * mask
# Gentle low-poly hills on open land; flat areas (lakes, deltas) and the
# coast stay untouched.
flat = (ndimage.maximum_filter(macro, 3) - ndimage.minimum_filter(macro, 3)) < 0.5
hills = ndimage.gaussian_filter(rng.standard_normal(base.shape).astype(np.float32), 2.5)
hills = hills / max(float(hills.std()), 1e-6)
hill_mask = smooth(water_distance, 3, 10) * (1 - mask) * (~flat)
result = result + args.hill_m * hills * hill_mask
result = np.where(land, np.maximum(result, 1.0), macro)

OUT.mkdir(parents=True, exist_ok=False)
code = np.rint((result + 8192) / .25).astype(np.int64)
if code.min() < 0 or code.max() > 65535:
    raise RuntimeError('encoding overflow')
packed = np.stack([code // 256, code % 256], axis=-1).astype(np.uint8)
packed.tofile(OUT / 'height.rg8')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
policy = json.loads((MACRO / 'policy.json').read_text())
policy.update({'revision': 'fixed-diorama-mountain-facets-r2',
    'look_pass': 'relief areas blend the macro atlas back to the fixed 2km base grid with ridge sharpening; plains/coast/water keep macro heights',
    'ridge_gain': args.ridge_gain, 'compress_m': args.compress_m, 'peak_spacing_nodes': args.peak_spacing,
    'peak_height_m': args.peak_height, 'hill_m': args.hill_m, 'macro_surface_manifest_sha256': sha(MACRO / 'surface.json'),
    'base_surface_manifest_sha256': sha(BASE / 'surface.json'),
    'mountain_mask_mean': float(mask.mean()), 'height_range_source_equivalent_m': [float(result.min()), float(result.max())]})
(OUT / 'policy.json').write_text(json.dumps(policy, indent=2) + '\n')
m = dict(macro_m)
m.pop('chunks', None)
m['revision'] = 'fixed-diorama-mountain-facets-r2'
m['policy'] = {'path': 'policy.json', 'sha256': sha(OUT / 'policy.json')}
m['height_payload'] = {'path': 'height.rg8', 'sha256': sha(OUT / 'height.rg8'), 'bytes': (OUT / 'height.rg8').stat().st_size}
(OUT / 'surface.json').write_text(json.dumps(m, indent=2) + '\n')
print(json.dumps({'output': str(OUT), 'mask_mean': float(mask.mean()), 'max_change_m': float(np.abs(result - macro).max())}))
