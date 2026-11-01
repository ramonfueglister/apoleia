# Verona river height repair

Status: `offen` for a visually acceptable fix; `implementiert` experimental
geometry, **not enabled in the normal game and not ready to merge**.

The existing river is painted onto ordinary terrain triangles. Consequently its
water inherits both longitudinal bumps and cross-channel slope. This is a real
geometry defect, not merely an animation direction issue. The GPU baseline audit
is in `docs/handover/verona-river/`.

## Explicit prototype

Launch with `-- --verona-river-prototype` to create `terrain._river`. Without this
argument there is no channel node, profile file read, mesh creation or update.
The terrain shader's replacement branch remains disabled. Existing terrain,
bridges and bank assets are unchanged by default.

`tools/build_verona_river_profile.py` consumes the ordered GPU baseline and freezes
a lower-only running minimum across 941 centre/transverse samples of one unbranched
47-segment Verona reach. It does not claim surveyed water elevations. Downstream
order is inferred from the source Adige line's alpine and sea endpoints; the input
GeoJSON has no explicit flow metadata. The generated profile is fixed and does not
change with camera movement.

The prototype draws an independent water ribbon and narrow shore faces. Its
terrain cutout and ribbon share miter joins and longitudinal endpoint planes.
Water vertices are static; outer shore vertices sample the same cached terrain
triangles used by the existing scene. Missing cache samples are rejected, not
clamped into false heights. The bridge deck and dry ground are not repositioned.

## Why this cannot be accepted as the fix

Lowering only water beneath the existing artificial terrace bumps produces very
high, nearly vertical bank faces. The first real screenshot shows a canyon around
the northern bend. Correcting numerical downstream slope does not make this a
satisfactory game scene. Initial corner slit defects were corrected by matching
miter geometry and the cutout; this still requires final image and mesh review.
The narrow-shore solution must not be enabled by default on the strength of a
monotonicity test alone.

This scope also excludes the rest of the world's rivers and the transition from
quarter-tile geometry into the farther colour-only river rendering. It must not be
reported as a general hydrology fix. Endpoint continuity, actual bank closure,
cache boundaries, bridge clearance and adjacent prop grounding all need evidence.

## Coherent next implementation

Condition the whole local valley corridor around a connected, downstream profile,
with sloped or deliberately terraced shores. Keep the existing river's geographic
centreline, but derive water, banks and nearby ground from one shared surface.
Before choosing corridor width, measure the affected city parcels rather than
moving landmarks to make space.

Dependencies that must be updated and checked together:

- `verona_bank.gd` / `verona_bank_props.gdshader`: stones, grass and reeds currently
  follow the old terrain. Their dry-margin checks must use the corrected shore.
- `verona_vegetation.gd` / `verona_vegetation.gdshader`: existing placement texture
  root heights must agree with any corrected bank surface.
- `verona_bridges.gd` and bridge shaders: preserve or deliberately rebuild all deck,
  stair and bank landing joins against the corrected terrain; verify arch clearance.
- Terrain cache, visible terrain, camera height sampling and any affected building
  terraces must agree. A fragment cutout alone cannot provide this shared surface.

Acceptance requires GPU geometry checks plus actual near and city-view screenshots,
including pan, zoom and fallback. A smooth profile with floating props, exposed
holes or excessive retaining cliffs is a failed result.
