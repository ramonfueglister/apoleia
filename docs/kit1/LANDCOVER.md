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
