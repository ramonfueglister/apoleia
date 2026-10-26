# Owner-provided bindings and unresolved handoffs

This file separates owner-reported values from config bindings and independent verification. Reported decisions are not product-validation evidence.

## Graphics owner (2026-10-25)

- Godot `4.7.2.stable.custom_build.ed1daf0bf`; installed binary `/Users/ramonfuglister/.local/bin/godot`.
- App project `app/`; intended native Godot 3D renderer with Mobile first and Forward+ comparison.
- `scripts/build-landscape` and `scripts/run-landscape` exist and are executable. Operations inspected their source; neither has been run by operations.
- Geospatial model mapping: `equirectangular-model-v1`; data mapping revision `mapping-v1`. Camera profile: `orthographic-relief-v1`; normal zoom z∈[0,1], orthographic, north-up, 90°→35.2643897°, smoothstep relief 0→1, near width 500 source m, far width entire data extent plus 8% margin, common scale .001. The technical decision is in `docs/product-renderer/TECHNICAL_DECISION.md`.
- Internal capture invocation supplied: `./scripts/run-landscape --rendering-method mobile --resolution 1920x1080 -- --tour --duration 48 --capture-dir <absolute-run>/captures/mobile`; same tour with `forward_plus` for comparison. Native framebuffer PNG every 0.1s plus `runtime.json`; all unverified because no successful GPU start and no data payload yet.
- Direct input mapping read from `app/scripts/landscape.gd`: drag with left/middle/right button and trackpad PanGesture for panning; mouse wheel and magnify gesture for zoom. Code-inspected, runtime behavior still open.
- Proposed premeasurement objectives: 1920×1080; frame p95≤16.7 ms, p99≤33.3 ms; ≤2 GB RAM, ≤1 GB GPU memory; zero visible holes. These are technical targets, not observations or user guarantees. Mapping-residual pixel tolerance remains unbound; kit config schema has no GPU-memory threshold field, so preserve that target separately in the human report/telemetry.

## Data owner (2026-10-25)

- `data/region.json`: `region-v1`, `mask-v1`, EPSG:4326 extent `[-11,46] × [21,58]`; AWMC117, NE-v5.1.2 Mediterranean/subbasins and gbOpen commit `9469f09` England inputs, features and hashes reported there. Completeness evidence is `data/reference/completeness.json`; owner reports no polygon outside the mask. England north `55.811165°`; north context `2.188835°`.
- `data/projection.json`: `mapping-v1`, regional equidistant cylindrical mapping centered at 41°N/19°E, radius 6371008.8 m, common model scale .001 and vertical scale 1.
- `data/tile-grid.json`: `eqc41-km-v1`, 1000 m square cells, `tile-grid-v1`.
- `data/geodata_policy.json`: `policy-v1`; predeclared budgets. Source accuracy, model/render transition, and protected-feature references remain open until processing/renderer integration.
- NOAA ETOPO 2022 v1 60s full download was reported in progress under job `15288`, without completion/hash at this checkpoint. WorldCover 2021 v200 COG was reported available; regional subsets in progress. Full source/coverage result not reported yet.
- Data owner is preparing `tools/data_export_run.py RUNROOT`, which will make a run-local `data/` subtree with hardlinks to frozen inputs/artifacts (no symlinks; same content hashes). Operations must wait for the script/output and record source path/hash/export relation. Do not independently copy or edit data-owner files. Large raster handoff remains subject to that export and its provenance record.

## Current config binding

`config.json` binds installed Godot name/version and renderer/capture executable paths, repo-root working directory, build/start/Mobile-capture command definitions, observed Mac hardware, `equirectangular-model-v1` / `mapping-v1`, intended target output 1920×1080, and premeasurement p95/RAM thresholds. Commands are defined, not executed. The project sets logical viewport 1920×1080 and window override 1440×810, but captured runtime resolution remains unverified.

The kit's `confined()` requires config and nested artifact paths under the run folder; it rejects `..` and symlink targets outside that folder. Therefore current references under repo `data/` cannot be named directly by this run's config. Wait for the promised run-local export. Still open in config: mapping-residual tolerance, data processing tool, all region/source/coverage/policy/fixture/grid bindings. p99/GPU-memory/zero-hole targets remain in `thresholds.md`; config has no p99 or GPU-memory field.

## Data v3 frozen export (2026-10-25)

Data owner reports `landscape-v3` frozen and exported to this run, with the five Kit manifests structurally validated by the owner. Operations checked the root manifests against their run-local `data/` counterparts: bytes match for all five. SHA-256:

| Run manifest | Revision | SHA-256 |
|---|---|---|
| `sources.json` | `sources-v1` | `9881be75f5cc3c4adf0c7b348cb4b7d0c34a42ee67a868606531796d1321793f` |
| `region.json` | `region-v1` | `adaa308c83b03f3e4288ab0c81a91e835e8a5a88e0191162362b5481d86acc8a` |
| `coverage.json` | `coverage-v3` | `a6bd882e9baabad8ca2700595c19ec5805d3d61273a21ab51c3a036ba174cfad` |
| `geodata_policy.json` | `policy-v3` | `289fdb60188aa7fcf86ef6168c1f0b8bb6b53be0721ebdb4acd726fd63d12d28` |
| `derivation.json` | `build_revision: landscape-v3` | `fb5f3ee3310b7164d46be69b043944663baf86013b6404968da98ff51a8dcc10` |

Additional evidence artifact `data/horizontal-metric.json` is `horizontal-identity-v1`, SHA-256 `ed79059bcca8321296768c7f9d7713e1e4b326d0fe215fe214932015287edfbb`. Its exact-coordinate identity definition and projection roundtrip measurement are distinct quantities; neither supplies a renderer pixel residual threshold. The normative tile definition remains `data/tile-grid.json`, `eqc41-km-v1` / `tile-grid-v1`, SHA-256 `8c2acb50000fea5186f8b2a4a6d2f5c62de00c27dc09bca2465a1e2de3cbc67d`.

Owner-reported v3 corrections: overview-water raster is 4096×3072 and the repeated 2340-point overview coastal sample has maximum 2040.133 m, within the existing 6000 m budget; canonical/detail masks and terrain/flow content are reported unchanged. The legacy 60s NOAA download is complete but unused and excluded from v3 source/export. V2 snapshot remains under `data-revisions/landscape-v2/`. These are owner data claims, not independent acceptance. Coverage still has `landcover_treatments[].visible_result: unresolved`; six screen/morph runtime combinations remain unmeasured. Runtime camera, mapping residual, fixture, tiles and captures are still open for Graphics/Capture. Do not update `thresholds.mapping_residual_px` from the meter-valued horizontal metric.

This table supersedes the earlier v2/unbound statements above. The config's schema supports `sources_path`, `region_path`, and `geodata_policy_path`; coverage and derivation remain linked via manifest evidence and are not invented as unsupported config fields.
