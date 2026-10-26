# Kit 1 acceptance report — evidence checklist

**Run:** `kit1-landscape-v5-2026-10-25` · **Kit:** `kit1-landscape-v5` / `kit1-ops-v5` · **A01–A16 final acceptance:** all `offen`, pending independent reviewer.
Run-local data-v3 manifests, warmed Mobile/Forward+ normal paths, the Mobile capture/video, schema-bound mobile telemetry/tiles, and a locally smoke-started macOS bundle are now bound in [report.json](report.json) and [EVIDENCE_INDEX.json](EVIDENCE_INDEX.json). They are evidence inputs, not acceptance claims. `report-check` remains blocked on missing independent reviewer binding and genuine data-manifest/policy/coverage inconsistencies; see the current `PROGRESS.md` checkpoint.

| ID | Status | Evidence needed / current binding |
|---|---|---|
| A01 | offen | Verified start on named host; real pan/zoom user input and reproducible tour; no image-series substitute. |
| A02 | offen | Run-local region/coverage v3 manifests are bound; independent preliminary geometry containment is a subcheck. Full visual regional coverage, source roles, NoData, edges/coasts/seams and their acceptance review remain open. |
| A03 | offen | Same-view flat 2D far endpoint, isometric near endpoint, actual intermediate camera/projection/relief states. |
| A04 | offen | Uncut runtime video of overview → pan/zoom → near view → return and another region, no gaps/switches; same build as overview captures. |
| A05 | offen | Stable geographic anchors and measured positions through zoom/pan/return with bound viewport/camera/mapping states. |
| A06 | offen | Hashed source→model→render transforms, common sub-unity length/height scale, projection distortion and sampled geographic errors; no invented shortening/exaggeration. |
| A07 | offen | Measured/documented useful near framing for multiple future houses and readable terrain/water/individual stylized trees; no houses required in Kit 1. |
| A08 | offen | Real fixed-camera images reviewed against `references/STYLE_GUIDE.md` primary image; restrained palette, faceted natural forms, detailed forest groups. |
| A09 | offen | Slow/fast/forward/reverse zoom footage; cache cold/warm, first/late LOD/material loads, pipeline events and max/p95/p99 frame-time telemetry. |
| A10 | offen | Runtime images + layer/class inventory show natural landscape only, with no GUI, built/managed features, political lines, grid, highlights, topics, or visible field/plantation/fence patterns. |
| A11 | offen | Bound summer and fixed warm-light settings; evidence of distinct regional natural landscapes and no time/season cycle. |
| A12 | offen | Frame/CPU/GPU/memory/load/upload/request-age metrics on named hardware, resolution and fixed tour; available Forward+/Mobile comparison. Mac evidence must not claim Windows/Linux/iPad results. |
| A13 | offen | Versioned source/layer/license/URL/hash/CRS/height datum/transform manifest exists in `sources.json` and `data/transformations.json`; reviewer must confirm completeness and explain remaining gaps/correction backlog against final app usage. |
| A14 | offen | Same data/config/path repeatability and explained deviations. |
| A15 | offen | Hashed square logical-grid definition and runtime tile probes across zoom, pan/return, coast, interior, regional edge and seam; stable canonical IDs; visible view contains no grid. |
| A16 | offen | Data-v3 delta reviewer independently verified corrected offline overview coast samples and unchanged data payloads. Full height/horizontal/coast budgets, screen/transition pixels, scale ratios, protected features/topology and runtime seam evidence still need one coherent build/render review. |

## Evidence register

The run-local `report.json` now references real evidence files with SHA-256, origin, build/data/mapping/fixture revisions and producer. The independent reviewer and review reference remain unbound, so no check is marked validated. Synthetic fixtures and Kit tests cannot satisfy product acceptance. `report-check` establishes declared structural bindings only; reviewers must assess geodata, metrics, screenshots/video and actual user-visible behavior.
