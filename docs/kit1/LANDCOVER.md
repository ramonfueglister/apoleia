# Real terrain data for the land look

## Relief (atlas r4)
- Source: ETOPO 2022 v1, 15 arc-second surface (NOAA NCEI, public domain),
  local tiles `data/raw/etopo15/`.
- 2 km display nodes = area mean of ETOPO 15" per node (`gdalwarp -r average`
  onto the eqc grid of `data/projection.json`), see
  `tools/build_mountain_facet_surface.py` (docstring has the exact command).
- Stylisation only emphasises real forms: crest sharpening of the real
  band-pass (valleys keep their real height), light emphasis of the real
  2-6 km roughness in hill country, flattening of real valley floors into
  broad U-valleys, a 520 m step limiter, log height compression (H0 1900 m).
  No synthetic peaks or noise hills.
- Output: `artifacts/render-data/fixed-source-v2-mountain-r4/`.

## Land cover
- Source: ESA WorldCover 2021 v200, licence CC BY 4.0.
  Attribution: "© ESA WorldCover project 2021 / Contains modified Copernicus
  Sentinel data (2021) processed by ESA WorldCover consortium".
  Local frozen COG overviews (~0.0053°) in `data/raw/worldcover/`
  (`tools/data_worldcover.py`).
- `tools/build_landcover_nodes.py` resamples onto a 4x4 sub-grid per 2 km
  node and counts class shares per node.
- 117 AD display assumption (not data): built-up land -> half cropland, half
  grassland; today's cropland -> 25 % forest, 30 % grassland, 45 % cropland.
- Output: `artifacts/render-data/landcover-node-2km/`
  - `classes.u8`: 8 bytes per node (forest, shrub, grass, crop, bare, snow,
    wetland, water), shares 0..255, same node grid as the atlas. The forest
    channel can drive tree placement.
  - `look.rgba8`: R forest, G bare, B dry/golden, A snow for
    `terrain_land_look.gdshaderinc` (loaded by `landscape_look.gd`).
- Not used yet: a climate layer (Köppen-Geiger) for dry vs. humid; the dry
  channel is currently derived from shrub, cropland and bare land.

## Near clipmap levels with fine real relief (clipmap-tiles-r5-etopo15)
- Levels 0 and 1 (0.5 / 1 km samples) = display atlas r5 plus the real
  sub-2 km relief band of ETOPO 2022 v1 15 arc-second (NOAA NCEI, public
  domain); coarser levels are pure atlas r5. Material and water tiles are
  copied unchanged from clipmap-tiles-r4-mountain-r4.
- Format unchanged (RGBA8 PNG, 258², height code*0.25-8192), 4187 tiles,
  273 MB; manifest sha256 87324484f9319b48b25c90ee7030df86b045e7541843c90ec2f6675b6eb6c705.
  Tile data is not in Git (`.gitignore`); `scripts/link-render-data` links it
  from a checkout that holds it (it follows `renderer-binding.json`).
- Build:
  ```
  # 0.5 km ETOPO nodes (eqc of data/projection.json, node-centred, 4x atlas nodes)
  gdalwarp -t_srs '+proj=eqc +lat_ts=41 +lat_0=41 +lon_0=19 +R=6371008.8 +units=m' \
    -te <(wx-0.25)*1000> <-(wz+2*(H-1)+0.25)*1000> <(wx+2*(W-1)+0.25)*1000> <-(wz-0.25)*1000> \
    -ts 4(W-1)+1 4(H-1)+1 -r average -srcnodata -99999 -dstnodata -99999 -ot Float32 \
    artifacts/render-data/etopo15-node-2km/etopo15.vrt artifacts/render-data/etopo15-node-500m/nodes.tif
  python3 tools/build_fine_relief_detail.py
  python3 tools/build_clipmap_tiles.py --output artifacts/render-data/clipmap-tiles-r5-etopo15 \
    --surface artifacts/render-data/fixed-source-v2-mountain-r5/surface.json \
    --fine-detail artifacts/render-data/fine-relief-detail-500m \
    --reuse-from artifacts/render-data/clipmap-tiles-r4-mountain-r4
  ```
- The forest layout binds the atlas (r4), not the tiles; crowns read their
  ground height from the tiles, so they follow the new relief.
