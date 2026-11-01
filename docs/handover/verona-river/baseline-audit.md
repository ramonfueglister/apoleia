# Verona river baseline

Status: **erforscht**. This is defect evidence, not a passing water regression.

The near river is a fragment colour over the ordinary terrain triangles
(`tt_corners` explicitly retains land shape for river tiles). Consequently it
inherits both longitudinal terrain humps and transverse bank slopes. The previous
bank-detail QA verified prop contact and unchanged terrain, not physical water.

## Reproduction

Run the real renderer (not headless):

```sh
Godot --path app --script res://scripts/debug/verona_river_profile_check.gd
python tools/tests/analyze_verona_river_profile.py
```

The GPU script reads actual corner and river-mask textures after settling the
camera. It evaluates the chosen triangle planes barycentrically, rather than
using the camera's bilinear `ground_y`. Its 47 river segments form one connected,
unbranched path. The report and screenshot go to `build/verona-river/baseline`.
The successful process exit means the measurement harness worked, **not** that
the river was physically valid.

Observed on 2026-11-01: 941 ordered centreline samples, 120 rising intervals and
140 falling intervals (1e-5 world-km numerical threshold). The pilot rises from
0.6 to 0.75 world-km and the northbridge reach subsequently reaches 0.9 before
dropping to 0.6. Maximum sampled cross-channel height difference is
0.0849609375 world-km: 3.57 model metres across a 4.20-model-metre section.

## Direction evidence and limits

Local `data/derived/rivers.geojson`, main Adige `source_id=1217`, has XY only:
no flow direction or water elevation attribute. Its first coordinate is
(10.710948,46.827175), last (12.321462,45.164903). Nearest samples from the
existing `height.r16f` are 1692m and 0m respectively. Its Verona coordinate
order runs northwest to southeast; nearby coarse heights descend 35.5,30.5,
27.75m. Downstream order is therefore an **inference from source geometry and
baked topography**, not a supplied hydrology guarantee. The supplement's second
Adige feature is a different upstream branch; name matching is insufficient.
The far river field stores direction modulo pi and cannot recover flow sign.

## Required correction checks

A replacement must measure its actual rendered water geometry, with level
cross-sections and no downstream rises through joins. Check both endpoints,
mask boundaries, shore closure, bridge clearance, cache/LOD transitions and
camera return. A monotone array alone does not establish that the rendered water
or its transition to unchanged river is correct. Lowering water beneath unchanged
terraces can create tall bank faces; actual screenshots must judge those too.
