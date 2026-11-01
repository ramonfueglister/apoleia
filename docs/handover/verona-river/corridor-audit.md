# Verona corridor space and grounding audit

Status: **validiert** for the stated placement and contact checks; see the [final validation and images](validation.md).

The existing audited channel has 941 stations. The original near-water half-width
is 0.075 world-km. Conservative ray measurements against the existing atlas find
98 protected non-bridge parcels and eight separate bridge parcels. The tightest
centreline-to-protected-parcel clearance is approximately 0.1768 world-km, leaving
about 0.1018 world-km (4.28 model metres) beyond the water edge. Most tight urban
edges have 0.25 world-km centreline clearance. These figures describe available
space, not acceptable slope: terrain height differences still matter.

`audit_verona_corridor_space.py` preserves all ray samples in
[corridor-space.json](corridor-space.json). Direction signs are relative to the
source-ordered downstream tangent; bridges are reported separately because a
whole bridge parcel cannot be treated as solid land.

An actual normal-renderer survey at 5 km captured 80 instantiated building XZ
bounding boxes and nine bridge-piece boxes, retained in
[scene-footprints.json](scene-footprints.json). XZ bounds include the imported mesh
and scene transforms. Bridge Y bounds in this file are not rendered graded
heights and must not be used for foundation contact tests.

The independent `check_verona_corridor_clearance.py` clips each authored corridor-envelope quad against protected rectangles and actual building bounding boxes. The current rendered shore uses a regular grid clipped by a shared cell mask; the envelope check alone does not validate that mask. It uses
polygon intersections rather than repeating the generator's ray-box selection.
The current variable-radius profile has no overlaps against either 98 protected
parcels or 80 building bounds. Its smallest outer radius is 0.15556 world-km.
This does not by itself validate the shader's mask, actual shore height or bridges.

`verona_corridor_check.gd` evaluates those remaining contacts in the actual game:

- Actual imported bank contact vertices in all three native LODs against shore
  triangles, with spatial indexing instead of a full triangle scan per vertex.
- Actual GPU placement-texture roots affected by lowering, against the shared
  surface and the shore triangles.
- A 5×5 grid on each protected parcel checked against the active correction mask.
- Every exposed outer grid-cell edge sampled against original terrain height, and 628 inner shoreline stations checked against the water profile.
- Legacy house records checked for affected visible roots. Loaded bridge plinth records are excluded only when their atlas membership and every prop material’s replacement mask confirm that they are hidden.
- Bridge source vertices at the authored foundation base, transformed through
  `rendered_source_point`, compared with old and corrected ground. Only newly
  exposed feet are flagged; an existing baseline gap is not attributed to this
  change.

The shore vertices are reconstructed from the uploaded mesh plus the analytic CPU mirror of the vertex shader and independently sampled GPU terrain triangles. Contacts use the shared centre-fan interpolation function; independent barycentric intersections inspect the actual uploaded fan triangles. Subsequent
intersections use triangle barycentrics. This is not a GPU post-vertex-buffer
readback. Bank and boundary contact error is capped at 0.0005 world-km, about 2.1 model centimetres. Tree root records use an RGBA16F render target; their bound is one half-float ULP at each stored height plus 0.0001 world-km for float32 coordinate/algebra error. This per-root bound and actual physical error are reported, rather than silently relaxing the bank tolerance. Actual pictures must additionally show satisfactory contact.

Reproduction (normal renderer for GPU scripts):

```sh
build/verona-venv/bin/python tools/tests/audit_verona_corridor_space.py
Godot --path app --script res://scripts/debug/verona_corridor_space_check.gd -- --weather=off
build/verona-venv/bin/python tools/tests/check_verona_corridor_clearance.py
Godot --path app --script res://scripts/debug/verona_corridor_check.gd -- --weather=off
```
