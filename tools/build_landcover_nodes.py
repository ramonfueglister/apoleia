#!/usr/bin/env python3
"""Land-cover class shares at the fixed 2 km display nodes (look pass).

Source: ESA WorldCover 2021 v200 (CC BY 4.0, (c) ESA WorldCover project /
contains modified Copernicus Sentinel data 2021), the frozen ~0.0053 degree
COG overviews in data/raw/worldcover (tools/data_worldcover.py). The VRT is
resampled (nearest) onto a 4x4 sub-grid per node on the eqc grid of
data/projection.json, then counted per node:

  gdalwarp -t_srs '+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m' \\
    -te <node-centred extent> -ts 4W 4H -r near -srcnodata 0 -dstnodata 0 \\
    data/derived/worldcover.vrt worldcover-500m.tif

Roman-era adjustment (117 AD, a declared display assumption, not data):
built-up land becomes cropland/grass, a quarter of today's cropland returns
to forest, the rest of cropland is split into grassland and dry fields.

Outputs (artifacts/render-data/landcover-node-2km):
  classes.u8   8 bytes per node, shares 0..255 (roman-adjusted):
               forest, shrub, grass, crop, bare, snow, wetland, water
  look.rgba8   RGBA per node for the land shader:
               R forest, G bare/snow, B dry/golden,
               A relief position h - mean(ring 4.5 km) of the display atlas,
                 128 + metres/3.2 (crest > 128 > valley), so the shader
                 needs no extra height fetches
  manifest.json
"""
import hashlib, json, pathlib
import numpy as np, rasterio

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/render-data/landcover-node-2km'
base = json.loads((ROOT / 'artifacts/render-data/fixed-source-v2-base-r1/surface.json').read_text())
W, H = base['width'], base['height']
with rasterio.open(OUT / 'worldcover-500m.tif') as src:
    wc = src.read(1)
if wc.shape != (4 * H, 4 * W):
    raise RuntimeError('sub-grid mismatch')
blocks = wc.reshape(H, 4, W, 4).transpose(0, 2, 1, 3).reshape(H, W, 16)
def share(*codes):
    return np.isin(blocks, codes).mean(-1).astype(np.float32)
forest, shrub, grass, crop = share(10), share(20), share(30), share(40)
built, bare, snow = share(50), share(60), share(70)
wetland, water = share(90, 95, 100), share(80)
# 117 AD display assumption.
forest_r = np.clip(forest + 0.25 * crop, 0, 1)
crop_r = 0.45 * crop + 0.5 * built
grass_r = grass + 0.30 * crop + 0.5 * built
classes = np.stack([forest_r, shrub, grass_r, crop_r, bare, snow, wetland, water], -1)
OUT.mkdir(parents=True, exist_ok=True)
np.rint(np.clip(classes, 0, 1) * 255).astype(np.uint8).tofile(OUT / 'classes.u8')
# Shader look: dry/golden = shrub/macchia, cereal fields and dry bare land.
dry = np.clip(shrub + 0.8 * crop_r + 0.5 * bare + 0.15 * grass_r, 0, 1)
ATLAS = ROOT / 'artifacts/render-data/fixed-source-v2-mountain-r6'
am = json.loads((ATLAS / 'surface.json').read_text())
q = np.fromfile(ATLAS / 'height.rg8', dtype=np.uint8).reshape(am['height'], am['width'], 2)
h = (q[..., 0].astype(np.float32) * 256 + q[..., 1]) * .25 - 8192
# Relief position in the land shader's reference metres: atlas r6 heights
# (global H0 800 compression) back to real, then the H0 1900 curve the
# shader thresholds are expressed in.
real_h = np.where(h > 0, 800.0 * np.expm1(np.maximum(h, 0) / 800.0), h)
h = np.where(real_h > 0, 1900.0 * np.log1p(np.maximum(real_h, 0) / 1900.0), real_h)
from scipy import ndimage
yy, xx = np.mgrid[-3:4, -3:4]
ring = ((np.hypot(yy, xx) > 1.6) & (np.hypot(yy, xx) < 2.9)).astype(np.float32)
around = ndimage.convolve(h, ring / ring.sum(), mode='nearest')
crest = np.clip(128 + (h - around) / 3.2, 0, 255) / 255
look = np.stack([forest_r, np.clip(bare + snow, 0, 1), dry, crest], -1)
np.rint(look * 255).astype(np.uint8).tofile(OUT / 'look.rgba8')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
manifest = {
    'revision': 'landcover-node-2km-r1', 'width': W, 'height': H,
    'world_min': base['world_min'], 'world_size': base['world_size'], 'grid': 'node centred, same as the fixed display atlas',
    'source': 'ESA WorldCover 2021 v200, CC BY 4.0, frozen COG overviews (data/raw/worldcover)',
    'roman_adjustment': 'built -> 0.5 crop + 0.5 grass; crop -> 0.25 forest + 0.30 grass + 0.45 crop',
    'classes': {'path': 'classes.u8', 'channels': ['forest', 'shrub', 'grass', 'crop', 'bare', 'snow', 'wetland', 'water'], 'sha256': sha(OUT / 'classes.u8')},
    'atlas_surface_sha256': sha(ATLAS / 'surface.json'),
    'look': {'path': 'look.rgba8', 'channels': ['forest', 'bare_or_snow', 'dry', 'relief_position (128 + (h - ring mean 4.5 km)/3.2 m)'], 'sha256': sha(OUT / 'look.rgba8')},
    'land_means': {k: float(v[water < 0.5].mean()) for k, v in zip(['forest', 'shrub', 'grass', 'crop', 'bare', 'snow'], [forest_r, shrub, grass_r, crop_r, bare, snow])},
}
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest['land_means']))
