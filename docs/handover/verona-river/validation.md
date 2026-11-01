# Verona river correction

Status: **validiert** for the 47-segment near-Verona reach, enabled by default.
The rest of the world's rivers and farther map rendering are outside this fix.
`--legacy-verona-river` retains the previous renderer for reproducible comparisons.

## Result

The old fragment-coloured river inherited terrain humps and transverse slopes.
The replacement has a fixed downhill water surface and sloped banks, with the
same geographic centreline. Buildings, bridge decks and atlas cells stay in place.
Bank props and both native and legacy vegetation use the same bank triangles.
The camera uses the same correction with its existing approximate terrain sampler.
The previous narrow-wall experiment remains archived as `prototype-rejected.png`;
it is not the accepted scene.

The profile uses the preserved GPU terrain evidence across the full water apron,
then lower-only, grid-aligned conditioning and level bend buffers. This is an
explicit display repair, not a surveyed historical water level. Downstream order
is inferred from the Adige source geometry and baked topography. All 941 XZ
stations and both endpoint heights (0.6 / 0.3 world-km) are unchanged. Relative to
the first narrow-sample running minimum, conditioning lowers at most 0.107171
world-km (4.50 model metres); no water station is raised. This additional lowering
is localized around the previously sloping bends. See [implementation](../../kit2/VERONA_RIVER.md).

## Geometry and contact evidence

[Actual-game corridor audit](corridor-validation.json), zero failures:

- 628 inner shoreline samples: maximum water/bank join error 0.000774 model metres;
  no missing geometry or overlapping-water height disagreement.
- 4,548 outer cell-edge samples: maximum join error 1.05 model centimetres;
  no missing geometry. The cutout and replacement share the same cell mask.
- 12,491 bank contact vertices across all three LODs: maximum difference
  0.000111 model metres from the reconstructed rendered triangles.
- 30 affected tree roots: maximum difference 2.43 model centimetres, within the
  independently calculated precision bound of the actual RGBAH placement texture.
  Positions inside the corridor are explicitly quantized before their heights
  are sampled, so storing the position cannot subsequently move the root.
- 1,198 bridge foundation samples, 289 affected by the lowered ground: no newly
  exposed feet. No bridge mesh alteration was necessary.
- 98 protected atlas parcels and 80 instantiated building bounds are preserved.
  Five prepared legacy bridge-plinth records are confirmed hidden by the existing
  replacement masks; no visible legacy house is left over lowered ground.

The bank audit reconstructs shader-displaced vertices from actual GPU corner
readback and the shared height formula, then independently intersects triangles.
It is not direct GPU post-vertex-buffer readback. Screenshots and shader-error
log inspection complement the numerical checks. The final water regression also
checks its actual uploaded water mesh, endpoint cross-sections, four zoom widths
and return to close views. See `water-validation.json` and the game images.

## Appearance and scope

The accepted game views are `city.png`, `north-bridge.png` and `bank-closeup.png`.
The previous steep-wall prototype is retained only as diagnostic history.
Small support-triangle shading is smoothed using the underlying bank profile;
this changes lighting, not the geometry or its contact tests. Original gravel,
stones, reeds and grass remain integrated into the local bank pilot.

The channel is active in quarter-tile rendering. Farther map views retain their
existing simplified river representation. This is not a global hydrology bake
and does not claim to fix every river in the game. The near/far switch is retained
as an explicit scope boundary. There is no new periodic GPU readback in gameplay.

## Reproduction

```sh
build/verona-venv/bin/python tools/tests/check_verona_river_profile.py
build/verona-venv/bin/python tools/tests/check_verona_corridor_clearance.py
Godot --path app --script res://scripts/debug/verona_corridor_check.gd
Godot --path app --script res://scripts/debug/verona_river_check.gd
Godot --path app --script res://scripts/debug/verona_river_perf.gd
Godot --path app --script res://scripts/debug/verona_river_perf.gd -- --legacy-verona-river
Godot --path app --script res://scripts/debug/verona_river_profile_check.gd -- --legacy-verona-river
```

Source constraints, the cropped GPU corner fixture and both generators are in
the repository. `baseline-audit.md` and the original baseline JSON/images preserve
the defect evidence. Performance results are reported separately below; no speedup
is claimed.

The explicit legacy-mode run also passed and all 47 GPU-derived river segment
records matched the preserved original baseline exactly. Final GPU logs contained
no script or shader compilation errors.

## Paired rendering cost

Apple M3 Pro, Metal Forward+, 1440×1000, 120 actual rendered frames per width,
consecutive legacy/channel runs with warmed shaders. Values are wall-clock frame
times, not GPU timer measurements. Background load varies; this is no speedup claim.

| Width | Legacy median / p95 | Channel median / p95 |
|---|---|---|
| 5 km | 32.89 / 40.83 ms | 36.67 / 48.48 ms |
| 12 km | 27.28 / 37.04 ms | 33.06 / 44.43 ms |

[Legacy report](performance-legacy.json) · [Channel report](performance-channel.json).
The accepted correction adds approximately 4–6 ms to the median in this paired run.
