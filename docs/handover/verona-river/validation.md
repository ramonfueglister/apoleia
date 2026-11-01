# Verona channel validation

Status: **erforscht**. The narrow replacement strip is an opt-in diagnostic
prototype, **rejected for production visual quality**: lowering water while
retaining the existing high terraces creates a deep vertical canyon. Default
rendering retains the original river. The physical uphill defect remains open.
A coherent valley-corridor correction needs broader terrain/shore design.

See [baseline-audit.md](baseline-audit.md) for observed defect, direction inference,
source limits and reproduction. The committed `baseline-report.json`,
`baseline-ordered-profile.json`, and `baseline.png` preserve the original
unmodified-water evidence even if the build directory is reused.

## Independent checks

`app/scripts/debug/river_mesh_audit.gd` intersects the actual uploaded water
triangles barycentrically. It does not call the runtime profile-height function.
`river_mesh_audit_check.gd` checks this inspector against downhill, uphill,
transverse-slope and missing-geometry fixtures at Verona's coordinate magnitude;
headless run passed on 2026-11-01.

`verona_river_check.gd` is the actual-renderer harness. It checks:

- Water vertex colour selects the shader branch without vertical displacement.
- Source-ordered centreline and interior cross-sections intersect uploaded water
  triangles without gaps, rising sections, cross tilt or overlap disagreement.
- All profile stations have geometry, including joins; finite endpoint masks stop at their planes and the cross-sections join the
  unchanged water surface.
- Terrain-cut activation agrees with channel visibility across 1.5/5/12/24-km views.

Numerical tolerance is 0.0001 world-km (approximately 4.2mm in model metres),
separate from the larger physical defect. The original measurement's successful
exit is not a water-correctness result. The helper fixture success is not an
actual-game result. This harness does not by itself establish bank closure,
bridge arch clearance, or visual quality; those need explicit checks and images.

Final output is separate: `build/verona-river/final`. Run with the normal renderer:

```sh
Godot --path app --script res://scripts/debug/verona_river_check.gd -- --verona-river-prototype
```

The initial GPU diagnostic had a harness bug: nonindexed SurfaceTool arrays
returned null indices, which aborted extraction and produced 1370 secondary gap
messages. This was fixed explicitly and the helper now tests extraction of a
real nonindexed SurfaceTool mesh. Those 1370 messages are not physical river
measurements. The corrected actual-renderer run completed with zero check failures. Its
[geometry report](prototype-geometry.json) and [rejected game view](prototype-rejected.png)
are preserved. The profile check covers 423 centreline stations across 47 segments;
no numeric pass overrides the visual rejection. Bank closure, bridge clearance
and a usable valley shape remain unvalidated.

## Default-game safeguard

The baseline harness was rerun without the prototype flag after the final changes.
It verified `terrain._river == null`, exited successfully, and all 47 GPU-derived
segment/sample records matched the preserved original baseline exactly. The normal
game therefore retains its previous river geometry; the uphill defect is still open.
