# Verona river corridor

Status: `validiert` for the bounded near-Verona reach. Enabled in the normal game;
`--legacy-verona-river` selects the unchanged baseline for comparison.
See [validation evidence](../handover/verona-river/validation.md).
The previous narrow vertical-bank prototype was rejected; its evidence remains in
`docs/handover/verona-river/prototype-rejected.png`.

## Observed defect and fixed geographic extent

The old blue river is painted onto terrain triangles and therefore inherits
longitudinal humps and cross-channel slope. The GPU audit preserves 47 connected
segments and 941 ordered stations through Verona. Downstream order is inferred
from the real Adige source geometry and baked topography, not supplied flow metadata.
No centreline coordinates, buildings, bridge decks or atlas cells are relocated.

The independent water ribbon retains a fixed lower-only conditioned profile.
This is a deliberate repair of the miniature terrain display, not a claim to
surveyed historical water elevations. The profile never changes with the camera.

The original audit sampled only 0.05 world km to either side, while water extends
0.075 world km. The actual GPU corner fixture therefore also constrains a
0.125-world-km apron: enough for the water miter and adjacent shore-grid vertices.
This prevents a low bank vertex from falling below the water. The cropped source
is `docs/handover/verona-river/gpu-corridor-corners.json`.

The builder then uses grid-aligned linear height spans and level buffers extending
at least 0.10 world km along either side of every bend, with a 0.25-world-km upstream
approach. Overlapping ribbon sections consequently agree in height. These are
conservative display-conditioning choices, not measured historical river pools.
All 941 geographic points and both endpoint heights (0.6 / 0.3 world km) remain
unchanged; every new water height is at or below the original running-minimum
profile. Maximum additional lowering is 0.107171 world km. The source constraint
check validates those properties independently of visual acceptance.

## Shared valley surface

The former 0.002-world-km bank strip was replaced by banks with variable widths.
`tools/build_verona_river_corridor.py` intersects each station's miter-normal rays
with the 98 protected nonbridge atlas parcels in `corridor-space.json`, expanded
by 0.015 world km. Both sides are independent. Widths can only shrink during a
conservative smoothing pass (gradient at most 0.65); their cap is 0.40 world km and
the current minimum radius is 0.1555635. Water retains its 0.075-world-km half-width.
These widths are a bounded design choice constrained by measured space.

A float profile texture stores water height and both bank radii at all stations.
Fifteen straight runs map a nearest point to the dense profile. Between water and
the outer bank, a smooth cubic blend joins the water level to the actual GPU terrain
height. Heights are only lowered. Beyond the measured radius the ground is unchanged.
The finite reach uses endpoint planes; its endpoint water levels match the old river.

The shore mesh is a 0.025-world-km regular grid aligned with the quarter terrain
(20,126 cells, four triangles from each cell's centre). Its centre fan exactly
represents either original quarter-tile diagonal. The shared `vr_corrected_height`
helper evaluates those same three fan vertices and interpolates their plane, so
bank props and vegetation roots follow the uploaded surface rather than a smooth
formula that differs between mesh vertices. Old terrain samples come from the
actual GPU corner texture. The CPU camera applies the same fan interpolation over
its existing bilinear terrain approximation; the audit supplies independently
sampled GPU triangle heights instead.

The terrain cutout uses a binary texture of the exact uploaded grid cells. The
outer row has unmodified heights, so interpolation joins the old surface along
whole grid edges. This avoids clipping a lowered triangle halfway across its
analytic-radius boundary. Protected atlas cells and their shared edges remain
uncut. Water uses its original ribbon geometry; the bank fragment excludes the
water strip. Numerical contact and boundary error still require measured evidence.

The replacement colour uses the same sRGB-to-linear palette conversion as the
existing terrain. Sloped banks have earth near the water and meadow farther up.
Geometry-derived slope shading preserves the low-poly relief. Water remains level
across the channel. The existing pilot gravel material is applied to the replacement bank surface.

## Reproduction

```sh
python3 tools/build_verona_river_profile.py docs/handover/verona-river/baseline-ordered-profile.json
python3 tools/tests/audit_verona_corridor_space.py
python3 tools/build_verona_river_corridor.py
python3 tools/tests/check_verona_corridor_clearance.py
python3 tools/tests/check_verona_river_profile.py
Godot --path app --script res://scripts/debug/verona_river_check.gd
```

Missing or malformed profile data leaves the original terrain active. Shader
parameters are bound once per material, with activation and current GPU cache
updated per view. Out-of-cache terrain lookups are rejected rather than clamped.

## Acceptance and limits

Require independent water triangle checks, protected-parcel footprint clearance,
actual bank contact errors, bridge pier support and bank landing continuity, and
near/city screenshots. A smooth river with floating plants or unsupported bridge
piers is not accepted. The 0.25-km terrain mode is the current extent; other rivers
and the farther colour-only map representation are not a global hydrology repair.
