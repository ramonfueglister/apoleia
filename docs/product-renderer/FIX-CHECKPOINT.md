# Concrete review fixes — checkpoint

Status: implemented; targeted verification, independent input/image review pending. Reference landscape-v3 source unchanged.

- Pan: explicit operational press state and last event position; absolute delta only when relative is zero, never added to valid relative; release/focus reset. Real CUA diagnostic previously proved absolute movement with zero relative/mask. `app/scripts/input_regression.gd` exercises the actual helper for this sequence, ordinary relative, release and focus reset.
- Forest: former continuous radius/18m key rebuilt the entire population in consecutive frames. Global 18m seeded candidates are now partitioned into 20×20 candidate (360m) render chunks. Each frame builds at most one chunk; three family arrays upload via MultiMesh.buffer. Prefetch begins at zoom .78, visibility .86, readiness fades .3s. LRU retains up to192 chunks; active wanted chunks are never evicted. Raw per-frame CPU/queue/readiness and accepted global candidate cells, masks and transforms are retained. This is bounded resident scene preparation, not geographic IO streaming. Rapid jumps may temporarily have incomplete readiness; telemetry exposes it.
- Ground: below the cover raster scale, mapped class contrast blends to3.5% of its old amplitude against the existing latitude base; continuous broad reflectance variation changes albedo only. Height, coastline, cover/vegetation gates, candidate seeds and meshes remain source-identical.
- Additional ridge probe: `--probe-anchor id lon lat --probe-plan absolute.json` adds a separate read-only anchor. Original ridge4 ocean point remains recorded, without a massif claim.

Targeted GPU route18–23s completed with frame p95/p99 9.461/17.193ms. Forest generation max8.286ms; first visible queue empty. Raw startup max555.075ms retained. `artifacts/runtime/chunk-encounter-regression/summary.json` binds details.

Actual intermediate PNG viewed at `artifacts/runtime/material-intermediate-regression/frame_000030.png`. Independent reviewer owns the regression bundle session. No full new acceptance claim.
