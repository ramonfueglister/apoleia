#!/usr/bin/env python3
"""Fine relief detail (0.5 km) for the near clipmap levels (look pass).

Real ETOPO 2022 15 arc-second relief at a 0.5 km node grid (4x the display
atlas nodes; gdalwarp -r average onto the eqc grid of data/projection.json),
minus its own 2 km node values bilinearly upsampled: the sub-2 km relief the
display atlas cannot carry. The detail is scaled by the derivative of the
atlas log height compression (H0 1900 m), faded out on water, the coastal
strip and flat plains (so plains and settleable valley floors stay calm),
and stored as float16 metres on the 0.5 km grid. build_clipmap_tiles.py adds
it to levels 0 and 1 on top of the display atlas; coarser levels stay pure
atlas, so the pyramid stays continuous.
"""
import json, pathlib
import numpy as np, rasterio
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/render-data/fine-relief-detail-500m'
ATLAS = ROOT / 'artifacts/render-data/fixed-source-v2-mountain-r5'
H0 = 1900.0
m = json.loads((ATLAS / 'surface.json').read_text())
W, H = m['width'], m['height']
q = np.fromfile(ATLAS / 'height.rg8', dtype=np.uint8).reshape(H, W, 2)
atlas = (q[..., 0].astype(np.float32) * 256 + q[..., 1]) * .25 - 8192
with rasterio.open(ROOT / 'artifacts/render-data/etopo15-node-500m/nodes.tif') as src:
    fine = src.read(1)
with rasterio.open(ROOT / 'artifacts/render-data/etopo15-node-2km/nodes.tif') as src:
    coarse = src.read(1)
if fine.shape != (4 * (H - 1) + 1, 4 * (W - 1) + 1):
    raise RuntimeError('fine grid mismatch')
coarse = np.where(coarse > -9000, coarse, 0).astype(np.float32)
SHAPE = fine.shape
def up(a):  # bilinear 2 km nodes -> 0.5 km nodes (shared corner nodes)
    return ndimage.zoom(a, (SHAPE[0] / a.shape[0], SHAPE[1] / a.shape[1]), order=1, grid_mode=False)
detail = np.where(fine > -9000, fine, 0) - up(coarse)
del fine
# Masks on the 2 km nodes, upsampled.
land = atlas > 0.5
water_distance = ndimage.distance_transform_edt(land)
def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1); return t * t * (3 - 2 * t)
relief = ndimage.maximum_filter(atlas, 3) - ndimage.minimum_filter(atlas, 3)
mask = smooth(water_distance, 2, 6) * smooth(relief, 40, 260)
gain = 1.0 / (1.0 + np.maximum(coarse, 0) / H0)
scale = up((mask * gain).astype(np.float32))
del coarse
detail = np.clip(detail * scale, -400, 400).astype(np.float16)
OUT.mkdir(parents=True, exist_ok=True)
detail.tofile(OUT / 'detail.f16')
manifest = {'revision': 'fine-relief-detail-500m-r1', 'width': int(detail.shape[1]), 'height': int(detail.shape[0]),
            'world_min': m['world_min'], 'spacing': 0.5, 'dtype': 'float16 metres, node centred',
            'source': 'ETOPO 2022 v1 15 arc-second (NOAA NCEI), sub-2 km band, log-compression derivative (H0 1900 m)',
            'atlas': 'fixed-source-v2-mountain-r5', 'abs_p99_m': float(np.percentile(np.abs(detail[detail != 0]), 99))}
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest))
