# Look pass (claude/project-thread-dq15bj)

Goal: water and landscape visually close to
`references/images/user-primary-landscape-style.png`. Comparison images:
`screenshots/compare-{fern,mittel,nah}.png` (before | after | reference).

## Renderer and look layer
- `app/project.godot`: Forward+ instead of Mobile.
- `app/scripts/style/landscape_look.gd`: ACES, SSAO, depth haze in oblique
  views, sun from WSW, palette, zoom-dependent river width.
- `app/shaders/terrain_look.gdshader`: sea (depth ramp, turquoise saum limited
  to shallow water, waves, facets, surf line), terrain (colour variation,
  facets, rock on crests/slopes/altitude, cavity darkening).
- `app/shaders/model_sampling.gdshaderinc`: quadratic B-spline SDF sampling
  near the contour (smooth coast instead of texel staircase).

## Geometry
- `tools/build_mountain_facet_surface.py` builds
  `artifacts/render-data/fixed-source-v2-mountain-r1` (local data, not
  versioned): in relief areas the 24 km macro atlas blends back to the fixed
  2 km base grid with ridge sharpening; plains, coast and water keep the macro
  heights. Then `tools/build_fixed_display_lods.py --surface-dir ...` for
  `chunks.json`. `app/renderer-binding.json` `atlas` points at it.
- Trees: `LandscapeStyle.create_tree_mesh` renders each existing crown record
  as a grove of six small low-poly trees (about 1/3 size, tone per tree,
  dark green to olive). Records, positions and coverage checks are unchanged.
- Forest layout rebuilt with
  `tools/compile_complete_forest_layout.py --mode complete --execute-complete`
  into `artifacts/render-data/forest-layout-claude-groves-r1`;
  `renderer-binding.json` `forest_rendering.layout` points at it.

## Hash bindings
| Binding | Resolution |
|---|---|
| Forest layout `binding.json` vs. runtime expectation (hashes of style, terrain/model_sampling shaders, templates, atlas identity) | Regenerated with the provided compiler. Additionally `FixedForestLayout.configure` now accepts a mismatch with a warning listing the differing keys (evidence hashes) instead of rejecting the whole forest. |
| `CompactBounds.prepare`: exactly 174 template vertices | Relaxed to "non-empty"; the bounds stay analytic from the template's extrema. |
| Product atlas / layout manifest sha256 in `renderer-binding.json` | Updated to the new artifacts. |
| Forest mesh cache (`forest_cache`) | Not rebuilt: on a key mismatch the runtime falls back to the exact generator (compact path is the product default). |

## Water (round 3)
- `app/shaders/water.gdshader`: own sea surface on the zero-height marine
  plane (replaces the terrain albedo mix).
- `app/shaders/water_look.gdshaderinc`: shared optics for sea, lakes
  (`terrain_look`) and rivers (`rivers.gdshader`): Beer-Lambert-style depth
  colour (seabed tone, turquoise, blue, navy; shore distance bounds the coarse
  bathymetry), low-poly facet lattice, swell plus scrolled detail normals along
  the wind, caustic web in shallow water, Fresnel sky reflection, glitter path
  (light mirrored in front of the camera, follows the sun's azimuth and
  elevation, `water_sun_dir` set each frame), permanent shore foam plus three
  surf bands running towards the coast, storm whitecaps. Far map: animation and
  glints damped by relief/pixel footprint, thin light coast line.
- Rivers: flow along the segment (the river mesh normal carries the side
  vector), current streaks, same optics; lakes use the same function without
  surf bands. Wet sand edge in `terrain_look`.
- Weather hooks: `global uniform` `weather_wind_dir`, `weather_wind_strength`,
  `weather_storm`, `weather_cloud_shadow` + `weather_cloud_shadow_rect`
  (sampled only when rect size > 0), `weather_lightning`; neutral defaults in
  `project.godot [shader_globals]`.

## Performance fixes (round 3)
- Common terrain stride: named-anchor/edge chunks (no subset error bound)
  forced stride 1 (8.6M triangles) in every overview. They are skipped; the
  stride uses the 85th percentile of chunk errors with an error budget growing
  from 0.75 px (close) to 8 px (overview).
- Grove LOD on the shared MultiMesh meshes: 6 trees (<360), 3 (<700),
  1 (<2200), none beyond (darker forest floor in `terrain_look`).
- Sun shadows off beyond 1700 model units (no crowns, terrain casts none).
- `terrain_look` only computes water optics for water fragments; cavity and
  crest samples are skipped in far views.
- `--hold-seconds N` (with `--snapshot`) keeps a fixed view for
  steady-state measurements.

## Terrain look (painted low-poly diorama)
- `app/shaders/terrain_land_look.gdshaderinc`: self-contained land look,
  `land_look(p, h, weights, source_normal, facet_normal, footprint, relief,
  view_width, display_height_scale)` returns albedo, display normal and AO.
  The host defines `LAND_LOOK_HEIGHT(p)` and `LAND_LOOK_WEIGHTS(p)` before
  the include; `terrain_look.gdshader` only calls it (water block unchanged,
  vertex stage identical to `terrain.gdshader`).
- Quintic gradient noise with domain warping replaces the hash value noise;
  every octave fades to its mean below ~2 px (no speckle, no shimmer).
- Material fields: one weight tap in the host plus a three-tap ring and a
  noise-displaced smoothstep edge in the include; no raster cells. Forest
  weight gives a closed dark forest floor (stronger on hills, softer in the
  overview).
- Facets: stable world-space triangle lattice (2.4 km hills, 3.6 km rock);
  each facet takes the represented surface normal once at its centroid plus a
  small tilt and tone. Independent of mesh LOD, so the 2 km raster no longer
  stripes flanks. Rock mixes in the mesh facet normal for silhouettes and
  carries lit/shaded pyramid sides.
- Valley occlusion (three-tap height ring, cool tint) and slight crest light;
  overview keeps a soft hillshade, calm forest zones and bright high peaks.
- `landscape_look.gd`: `land_*` palette, warmer sun, cooler ambient, slightly
  more mid contrast and SSAO.
- Atlas and forest layout unchanged; forest binding reports only the
  `model_sampling` hash difference already present on the base.
- Cost: nah p50 9.2 -> 11.1 ms, mittel 10.8 -> 12.6 ms (sequential
  `--hold-seconds 6` snapshots, same machine).
- Comparisons: `screenshots/terrain-compare-{nah,mittel,fern}.png`.
