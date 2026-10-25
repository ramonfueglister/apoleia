# Pre-measurement runtime thresholds

**Status:** technical comparison targets recorded before product runtime measurement; no observed values or passing result. Source decision: [`docs/product-renderer/TECHNICAL_DECISION.md`](../../docs/product-renderer/TECHNICAL_DECISION.md), SHA-256 at binding `1c9d181ba257c2fd37cf41e27a400677e4f798e126557668bf9edb9577447de0`.

- Output target: 1920×1080.
- Frame-time targets: p95 ≤16.7 ms and p99 ≤33.3 ms.
- Peak process memory target: ≤2048 MiB.
- GPU memory target: ≤1024 MiB; kit config schema has no dedicated field, so report and measure separately in raw runtime telemetry when available.
- Visible terrain holes on the bound tour: zero.
- **A05 mapping-residual target (Operations decision bound 2026-10-25, before the next normal/Forward+ run):** maximum visible-anchor screen-space Euclidean residual ≤ **1.0 px** in the recorded top-left-origin viewport. The rationale is a direct display-coordinate limit: an anchor must map within one screen pixel, a distinct precision target from A16's surface/generalization budgets. This new A05 target is not claimed to have been specified before the earlier captures and is not derived from their results.

  **Metric/method:** use all hashed source anchor probes from `data/anchors.json` (SHA-256 `2e026e903e89b1df7cf5209167874e4e2739077c78fe0f3555541dcdefeaea6d`) across the complete fixture's timed 48-second overview → begin/pan → near → return route. Freeze every waypoint ID and time, anchor ID, viewport size/origin and device-pixel ratio in `fixture.json` before the run; do not select or move waypoint times after seeing favorable measurements. For every fixture time sample, report each anchor's visibility, source coordinate, expected/observed screen coordinates, and actual camera state. Compare the independent scalar projection with `Camera3D.unproject_position` of the active terrain triangle, using the actual runtime Camera3D basis/projection; retain off-screen values raw but apply the 1.0-px limit only to visible probes. Compute the maximum 2D Euclidean distance without RMS aggregation or rounding. Do not substitute the theoretical camera preset, metre-valued raster-height error, or image-feature recognition. Raw coordinate pairs and exact method/source hashes must ship with the run.

  Current helper source hashes (must be checked/rebound to the frozen final code before measurement): `app/scripts/expected_projection.py` SHA-256 `3fcbb9ce80704885971b8fec13c7622aac199eb50e8cad60159269ae74c04b2d`; `app/scripts/analyze_runtime.py` SHA-256 `965dc2eadf6a5697367bd7a18fcb892cd31923d37108f38267c8032f0a54e8d5`. Expected projection uses independent scalar orthographic projection; analysis compares against runtime camera basis/projection and active terrain-triangle CPU probe. These current source paths are for identity evidence; final Kit references must be run-local copies with matching SHA-256.

  This binding applies only to a normal or Forward+ measurement begun after this threshold and method were saved. Existing `v3-mobile-normal`, `final-mobile-normal`, `camera-pitch-fix`, and the active capture cannot satisfy A05. They may supply evidence for other requirements if their final hash set is intact.

These are technical working targets, not user guarantees. Retain raw measurements and assess each item separately. If the host cannot expose a measurement, report `offen`.
