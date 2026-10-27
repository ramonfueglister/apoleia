#!/usr/bin/env python3
"""Forest density mask at the fixed 2 km display nodes (Paradox-style).

EU5 / Victoria 3 / CK3 place trees from a grayscale density mask per tree
type: the mask value drives placement probability (density curve) and
crown size (scale curve), and the same mask paints the forest floor at every
distance. This tool builds that mask for the whole atlas from real data:

  forest share   ESA WorldCover forest + half shrub, 117 AD adjusted
                 (artifacts/render-data/landcover-node-2km/classes.u8),
                 lightly blurred (2 km) plus a regional term (7 km), so
                 forests close into masses instead of single-node speckle;
  relief         slope and height of the display atlas (forest on hills and
                 flanks) and the relief position of the land look (valley
                 floors and flat lowlands stay open as Roman farmland);
  composition    a coarse 24 km and an 8 km hash noise shape the outlines;
  copses         round 3-6 km spots of light forest on open land, mostly
                 within ~10 km of a forest edge, never uniform scatter.

The core is a short smoothstep around the threshold, so masses have clean
edges (mask 1 inside, 0 outside, a ~2 km ramp). Copses carry 0.42 (light
forest: fewer, smaller trees). Sea and lakes are 0.

Output (artifacts/render-data/forest-mask-r1):
  mask.u8        one byte per node, 0..255, same node-centred grid as
                 landcover-node-2km (identical world_min/world_size/size),
                 so the land shader samples it with the land-cover UV
  manifest.json
"""
import hashlib, json, pathlib
import numpy as np
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parents[1]
LC = ROOT / 'artifacts/render-data/landcover-node-2km'
ATLAS = ROOT / 'artifacts/render-data/fixed-source-v2-mountain-r7'
OUT = ROOT / 'artifacts/render-data/forest-mask-r1'
REVISION = 'forest-mask-r1'
PARAMS = {
    'threshold': 0.50, 'edge_half_width': 0.05,
    'share_blur_nodes': 1.0, 'regional_blur_nodes': 3.5, 'share_weight': 0.6,
    'hill_weight': 0.25, 'valley_weight': 0.25, 'plain_weight': 0.15,
    'noise_coarse_km': 24.0, 'noise_coarse_weight': 0.12,
    'noise_mid_km': 8.0, 'noise_mid_weight': 0.06,
    'copse_threshold': 2.0, 'copse_value': 0.42, 'copse_edge_bias': 1.2,
}

lc = json.loads((LC / 'manifest.json').read_text())
am = json.loads((ATLAS / 'surface.json').read_text())
W, H = lc['width'], lc['height']
if (am['width'], am['height']) != (W, H) or am['world_min'] != lc['world_min'] or am['world_size'] != lc['world_size']:
    raise RuntimeError('atlas and land cover grids differ')
cls = np.fromfile(LC / 'classes.u8', dtype=np.uint8).reshape(H, W, 8)
look = np.fromfile(LC / 'look.rgba8', dtype=np.uint8).reshape(H, W, 4)
q = np.fromfile(ATLAS / 'height.rg8', dtype=np.uint8).reshape(H, W, 2)
height = (q[..., 0].astype(np.float32) * 256 + q[..., 1]) * 0.25 - 8192

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def chash(x, z, group):
    # Same integer hash as LandscapeStyle._composition_hash.
    h = np.mod(np.bitwise_xor(np.bitwise_xor(x.astype(np.int64) * 73856093, z.astype(np.int64) * 19349663), np.int64(group * 83492791)), 2147483647)
    return (h % 104729).astype(np.float64) / 104728.0

def cnoise(px, pz, group):
    # Same value noise as LandscapeStyle._composition_noise.
    cx = np.floor(px); cz = np.floor(pz); fx = px - cx; fz = pz - cz
    fx = fx * fx * (3 - 2 * fx); fz = fz * fz * (3 - 2 * fz)
    cx = cx.astype(np.int64); cz = cz.astype(np.int64)
    a = chash(cx, cz, group); b = chash(cx + 1, cz, group)
    c = chash(cx, cz + 1, group); d = chash(cx + 1, cz + 1, group)
    top = a + (b - a) * fx
    return top + ((c + (d - c) * fx) - top) * fz

P = PARAMS
land = ((height > 0.0) & (cls[..., 7] < 128)).astype(np.float32)
forest = np.clip((cls[..., 0].astype(np.float32) + 0.5 * cls[..., 1]) / 255, 0, 1) * land
open_land = np.clip((cls[..., 2].astype(np.float32) + cls[..., 3]) / 255, 0, 1)
share = ndimage.gaussian_filter(forest, P['share_blur_nodes'])
regional = ndimage.gaussian_filter(forest, P['regional_blur_nodes'])
h = np.maximum(height, 0)
gz, gx = np.gradient(ndimage.gaussian_filter(h, 1.0), 2000.0)
slope = np.hypot(gx, gz)
crest = (look[..., 3].astype(np.float32) - 128) * 3.2
hill = np.clip(smoothstep(0.02, 0.08, slope) * 0.7 + smoothstep(200, 700, h) * 0.3 + smoothstep(20, 160, crest) * 0.2, 0, 1)
valley = smoothstep(30, 140, -crest) * (1 - smoothstep(0.03, 0.08, slope))
plain = (1 - smoothstep(0.01, 0.04, slope)) * (1 - smoothstep(150, 400, h))
spacing = np.array(lc['world_size']) / (np.array([W, H]) - 1)
ii, jj = np.meshgrid(np.arange(H), np.arange(W), indexing='ij')
wx = lc['world_min'][0] + jj * spacing[0]
wz = lc['world_min'][1] + ii * spacing[1]
coarse = cnoise(wx / P['noise_coarse_km'], wz / P['noise_coarse_km'], 52361)
mid = cnoise(wx / P['noise_mid_km'], wz / P['noise_mid_km'], 52363)
score = (P['share_weight'] * share + (1 - P['share_weight']) * regional
         + P['hill_weight'] * (hill - 0.5) - P['valley_weight'] * valley - P['plain_weight'] * plain
         + P['noise_coarse_weight'] * (coarse - 0.5) + P['noise_mid_weight'] * (mid - 0.5))
core = smoothstep(P['threshold'] - P['edge_half_width'], P['threshold'] + P['edge_half_width'], score)
# Copses: round blobs of blurred node hash, biased towards forest edges.
blob = ndimage.gaussian_filter(chash(jj, ii, 52367).astype(np.float32), 1.3)
blob = (blob - blob.mean()) / blob.std()
near_edge = ndimage.gaussian_filter(core, 5.0)
copse = (smoothstep(P['copse_threshold'], P['copse_threshold'] + 0.5, blob + P['copse_edge_bias'] * near_edge)
         * smoothstep(0.3, 0.6, open_land + 0.5 * share) * smoothstep(0.04, 0.12, share) * (1 - valley * 0.7))
mask = np.maximum(core, copse * P['copse_value']) * land

OUT.mkdir(parents=True, exist_ok=True)
np.rint(np.clip(mask, 0, 1) * 255).astype(np.uint8).tofile(OUT / 'mask.u8')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
on_land = land > 0.5
manifest = {
    'revision': REVISION, 'width': W, 'height': H,
    'world_min': lc['world_min'], 'world_size': lc['world_size'],
    'grid': 'node centred, same as landcover-node-2km and the fixed display atlas',
    'model': 'Paradox-style grayscale forest density mask: density_curve and scale_curve in LandscapeStyle read it; the land shader paints the forest floor from it',
    'mask': {'path': 'mask.u8', 'format': 'u8 0..255 = 0..1', 'sha256': sha(OUT / 'mask.u8')},
    'inputs': {'landcover_classes_sha256': lc['classes']['sha256'], 'landcover_look_sha256': lc['look']['sha256'],
               'atlas_height_sha256': am['height_payload']['sha256']},
    'params': PARAMS,
    'land_share': {'core_over_half': float((mask[on_land] > 0.5).mean()), 'light_0.1_to_0.5': float(((mask[on_land] > 0.1) & (mask[on_land] <= 0.5)).mean())},
}
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest['land_share']))
