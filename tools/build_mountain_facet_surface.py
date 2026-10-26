#!/usr/bin/env python3
"""Display atlas with geographically real low-poly relief (look pass).

The product macro atlas interpolates 24 km control addresses and the fixed
2 km base grid is a 4 km Gaussian of the source, which blurs real valleys
and crests. r4 resamples the 2 km nodes from ETOPO 2022 15 arc-second (area
mean per node, see --real-nodes), keeps macro heights on flat plains, the
coastal strip and water, sharpens real crests in relief areas, lightly
emphasises the real 2-6 km band-pass in hill country and flattens real
valley floors into broad settleable U-valleys. Same grid, chunks and strides
as before; no synthetic peaks or noise. A step limiter trims near-vertical
2 km walls. Run build_fixed_display_lods.py on the output afterwards.

Real nodes (node centred pixels, eqc of data/projection.json):
  gdalbuildvrt etopo15.vrt data/raw/etopo15/*.tif
  gdalwarp -t_srs '+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m' \
    -te <(wx-1)*1000> <-(wz+2*(H-1)+1)*1000> <(wx+2*(W-1)+1)*1000> <-(wz-1)*1000> \
    -ts W H -r average -srcnodata -99999 -dstnodata -99999 -ot Float32 etopo15.vrt nodes.tif
  with wx, wz, W, H from the base surface.json.
"""
import argparse, hashlib, json, pathlib
import numpy as np
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--macro-dir', default='artifacts/render-data/fixed-source-v2-macro-r1')
parser.add_argument('--base-dir', default='artifacts/render-data/fixed-source-v2-base-r1')
parser.add_argument('--output', default='artifacts/render-data/fixed-source-v2-mountain-r5')
parser.add_argument('--ridge-gain', type=float, default=0.7)
parser.add_argument('--compress-m', type=float, default=1900.0)
parser.add_argument('--real-nodes', default='artifacts/render-data/etopo15-node-2km/nodes.tif', help='ETOPO 15s area mean at the 2 km nodes')
parser.add_argument('--hill-gain', type=float, default=0.0, help='emphasis of the real 2-6 km band-pass in hill country')
parser.add_argument('--valley-floor', type=float, default=0.22, help='share of local relief flattened into the valley floor')
parser.add_argument('--valley-radius', type=int, default=7, help='grid nodes (2 km) for the local relief window')
parser.add_argument('--wall-step-m', type=float, default=520.0, help='largest height step between neighbouring nodes')
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

# r4: geographically real relief. Grid nodes are resampled from ETOPO 2022
# 15 arc-second (area mean per 2 km node, tools: gdalwarp -r average onto the
# fixed eqc grid); the base grid's 4 km Gaussian blurred real valleys and
# crests away. Stylisation only emphasises existing forms: crest sharpening
# of the real band-pass and flattening of real valley floors. No synthetic
# peaks or noise hills.
real = base.copy()
if args.real_nodes:
    import rasterio
    with rasterio.open(ROOT / args.real_nodes) as src:
        etopo = src.read(1).astype(np.float32)
    if etopo.shape != base.shape:
        raise RuntimeError('real node grid mismatch')
    real = np.where(etopo > -9000, etopo, base)
land = macro > 0.5
water_distance = ndimage.distance_transform_edt(land)
coast_fade = smooth(water_distance, 3, 12) * (water_distance > 2)
# Relief areas (14 km range) take the real grid with crest sharpening;
# gentle hill country takes the real grid unsharpened; flat plains and the
# coastal strip keep the macro heights.
relief = ndimage.maximum_filter(real, 7) - ndimage.minimum_filter(real, 7)
mask = ndimage.gaussian_filter(smooth(relief, 220, 800) * smooth(real, 150, 650), 1.5) * coast_fade
# r5: crest sharpening only in high mountains (> ~1500 m real); hill and
# low mountain country keeps its real rounded form.
alpine = ndimage.gaussian_filter(smooth(real, 1300, 1900), 2.0)
hill_mask = ndimage.gaussian_filter(smooth(relief, 30, 220), 1.5) * coast_fade
low = ndimage.gaussian_filter(real, 3.0)
detail = real - low
# Sharpen crests only; valley floors keep their real height.
crest = np.where(detail > 0, detail * (1 + 0.5 * args.ridge_gain), 0.0)
mountain = low + detail + args.ridge_gain * crest * alpine
H0 = args.compress_m
mountain = H0 * np.log1p(np.maximum(mountain, 0) / H0)
# Real fine roughness in hill country (2-6 km band-pass of ETOPO), lightly
# emphasised so existing small hills and ridges read as facets.
fine = real - ndimage.gaussian_filter(real, 1.2)
hills = real + args.hill_gain * np.where(fine > 0, fine, 0.4 * fine)
result = macro * (1 - hill_mask) + hills * hill_mask
result = result * (1 - mask) + mountain * mask
# Settleable valleys: within relief areas, the lowest share of the real
# local relief becomes a broad flat floor (where the DEM has a valley floor),
# flanks rise and crests stay narrow. Valleys stay where they are.
V = args.valley_radius
lmin = ndimage.gaussian_filter(ndimage.minimum_filter(result, 2 * V + 1), V * 0.4)
lmax = ndimage.gaussian_filter(ndimage.maximum_filter(result, 2 * V + 1), V * 0.4)
span = np.maximum(lmax - lmin, 1.0)
t = np.clip((result - lmin) / span, 0, 1)
f0 = args.valley_floor
u = np.clip((t - f0) / (1 - f0), 0, 1)
valley_mask = smooth(span, 350, 1100) * coast_fade
result = result * (1 - valley_mask) + (lmin + span * u ** 1.25) * valley_mask
result = np.where(land, np.maximum(result, 1.0), macro)
# Step limiter: no node more than wall-step above its lowest neighbour.
T = args.wall_step_m
for _ in range(10):
    result = np.where(land, np.minimum(result, ndimage.minimum_filter(result, 3) + T), result)
valley_floor_share = float(((t < f0) & (valley_mask > 0.5)).sum() / max((valley_mask > 0.5).sum(), 1))

OUT.mkdir(parents=True, exist_ok=False)
code = np.rint((result + 8192) / .25).astype(np.int64)
if code.min() < 0 or code.max() > 65535:
    raise RuntimeError('encoding overflow')
packed = np.stack([code // 256, code % 256], axis=-1).astype(np.uint8)
packed.tofile(OUT / 'height.rg8')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
policy = json.loads((MACRO / 'policy.json').read_text())
policy.update({'revision': 'fixed-diorama-mountain-facets-r5', 'valley_floor': args.valley_floor, 'valley_radius_nodes': args.valley_radius, 'real_nodes': args.real_nodes, 'real_source': 'ETOPO 2022 v1 15 arc-second surface (NOAA NCEI), area mean per 2 km node', 'hill_gain': args.hill_gain, 'wall_step_m': args.wall_step_m, 'valley_floor_share': valley_floor_share,
    'look_pass': 'relief areas blend the macro atlas back to the fixed 2km base grid with ridge sharpening; plains/coast/water keep macro heights',
    'ridge_gain': args.ridge_gain, 'compress_m': args.compress_m, 'macro_surface_manifest_sha256': sha(MACRO / 'surface.json'),
    'base_surface_manifest_sha256': sha(BASE / 'surface.json'),
    'mountain_mask_mean': float(mask.mean()), 'height_range_source_equivalent_m': [float(result.min()), float(result.max())]})
(OUT / 'policy.json').write_text(json.dumps(policy, indent=2) + '\n')
m = dict(macro_m)
m.pop('chunks', None)
m['revision'] = 'fixed-diorama-mountain-facets-r5'
m['policy'] = {'path': 'policy.json', 'sha256': sha(OUT / 'policy.json')}
m['height_payload'] = {'path': 'height.rg8', 'sha256': sha(OUT / 'height.rg8'), 'bytes': (OUT / 'height.rg8').stat().st_size}
(OUT / 'surface.json').write_text(json.dumps(m, indent=2) + '\n')
print(json.dumps({'output': str(OUT), 'mask_mean': float(mask.mean()), 'max_change_m': float(np.abs(result - macro).max())}))
