# Manifest and evidence index

The following files were initialized by `tools/kit.py init-run`; values remain unbound until their named owners provide real inputs. This index is a pointer list, not a claim that manifests are populated or validated. Owner-reported values and the partial config binding are in [OWNER_BINDINGS.md](OWNER_BINDINGS.md).

| File | Binds | Current state / owner |
|---|---|---|
| `config.json` | engine/adapter, commands, mapping, host/thresholds, required tools/sources, grid and policy/region paths | Partial binding: Godot/host/commands/capture profile/model mapping/1920×1080 and declared p95/RAM thresholds. Metric residual, processing tool, sources/region/policy/grid are open. |
| `region.json` | regional scope, three reference geometries, extent, mask and mask revision | Template, open. Data owner. |
| `sources.json` | versioned sources, licenses, URLs, hashes, transformations and historical correction items | Template, open. Data owner. |
| `coverage.json` | regional land/ocean coverage, role bindings, NoData treatment and reference components | Template, open. Data owner. |
| `geodata_policy.json` | transformations, scale, projection, predeclared generalization budgets and protected features | Template, open. Data owner with rendering measurements inputs. |
| `derivation.json` | processing inputs/outputs, hashes, raw sampled errors and topology evidence | Template, open. Data owner. |
| `tiles.json` | hidden logical square grid and runtime probes | Template, open. Data owner defines addressing; graphics exposes runtime samples; capture owner binds them. |
| `fixture.json` | geographic anchors, camera/viewport states, pan/return route and tile cases | Template, open. Data + graphics owners; capture owner binds measured route. |
| `report.json` | A01–A16 findings and evidence IDs | Template, open. Operations owner assembles; independent reviewer assesses frozen run. |
| `telemetry.json` | frame/resource/streaming/camera/tile measurements | Runtime artifact not initialized by the kit template set; add only from actual capture with schema-compliant values. |
| `thresholds.md` | Premeasurement p95, p99, process RAM/GPU memory and zero-visible-hole targets | Operations snapshot of graphics owner's technical decision; residual pixel tolerance remains open. |
| Run-local data export | Kit paths and nested source references must resolve inside this run folder; `confined()` rejects `..` and out-of-run symlinks. | Data owner is preparing a hardlink export of frozen files preserving origin/SHA; do not bind current `data/` paths directly or copy raw data independently. |
| `START_AND_CONTROLS.md` | external start/use directions | Draft; graphics owner must confirm actual controls and commands. |
| `ACCEPTANCE_DRAFT.md` | human-readable A01–A16 report outline | Open checklist. |

## Source documents

- Order/scope: [`../../docs/kit1/START_PROMPT.md`](../../docs/kit1/START_PROMPT.md)
- Contracts: [`../../docs/kit1/ACCEPTANCE.md`](../../docs/kit1/ACCEPTANCE.md), [`../../docs/kit1/operations/VERIFY_CAPTURE.md`](../../docs/kit1/operations/VERIFY_CAPTURE.md), [`../../docs/kit1/schemas/README.md`](../../docs/kit1/schemas/README.md)
- Region/generalization/tiles: [`../../docs/kit1/operations/REGION.md`](../../docs/kit1/operations/REGION.md), [`../../docs/kit1/operations/GENERALIZATION.md`](../../docs/kit1/operations/GENERALIZATION.md), [`../../docs/kit1/operations/TILES.md`](../../docs/kit1/operations/TILES.md)
- Data/rendering: [`../../docs/kit1/operations/DATA_PIPELINE.md`](../../docs/kit1/operations/DATA_PIPELINE.md), [`../../docs/kit1/operations/RENDERING.md`](../../docs/kit1/operations/RENDERING.md)
- Visual reference: [`../../docs/kit1/references/STYLE_GUIDE.md`](../../docs/kit1/references/STYLE_GUIDE.md), [primary image](../../docs/kit1/references/images/user-primary-landscape-style.png)

## Frozen Data v3 status (supersedes the initial-state table above)

Data owner reports v3 frozen and exported. Root manifests and run-local `data/` counterparts are byte-identical; structural checks were performed by the data owner. Operations has bound the existing schema-supported paths (`sources.json`, `region.json`, `geodata_policy.json`) and the tile-grid definition in `config.json`; there is no schema field for directly binding `coverage.json` or `derivation.json`, so they remain indexed as evidence rather than added as unsupported config properties. Hashes and reported v3 changes are in [OWNER_BINDINGS.md](OWNER_BINDINGS.md).

Coverage field `landcover_treatments[].visible_result` remains unresolved pending image review. Six screen/morph runtime combinations remain unmeasured. V3's offline coastline budget is reported below 6000 m by the data owner; this does not establish rendered or runtime acceptance. The one post-v3 config preflight returned `blocked` (see [PROGRESS.md](PROGRESS.md)); no runtime was executed.
