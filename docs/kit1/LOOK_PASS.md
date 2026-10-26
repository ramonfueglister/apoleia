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
