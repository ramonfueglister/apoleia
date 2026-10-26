# Camera-centred clipmap streaming

Reference: rendering-diorama-2026-10-26. Status: implemented; visual acceptance and smooth-transition acceptance remain open.

The active `renderer-binding.json` selects `clipmap-tiles-r3`. Each terrain tile shares a permanent 65×65 vertex grid. The vertex shader reads height and morphs border vertices to its coarser parent. Tile loading runs in one CPU WorkerThreadPool job; GPU textures, meshes and MultiMeshes are created on the main thread. A resident root provides complete geographic fallback while finer sibling groups load. Completed siblings replace their parent together, with a 0.22-second height morph. CPU tile images have a 64 MiB LRU; GPU texture payload admission has a 192 MiB limit. These are payload counters, not measured driver-allocation guarantees.

The pyramid contains 4,187 addressed tiles, with 256×256 samples and a one-texel halo. Height stores the existing render G field; marine bathymetry is separate, from existing SourceH, in water.A. Material and associated water roles remain separate from geometry. Rectangles describe first and last texel centres. Terrain, forest and river geometry share tile lifetime and the same height textures. Forest levels 0/1 retain existing source records; level 2 uses a stable quarter-density subset. More distant vegetation remains in the ground material.

Rebuild the existing source-derived pyramid and its small shore sidecars:

```sh
/opt/anaconda3/bin/python tools/build_clipmap_tiles.py
/opt/anaconda3/bin/python tools/build_clipmap_shores.py
```

Region coverage (A02) of the bound pyramid, forest layout, atlas, upload, coast field and rivers is checked headlessly per sub-region (Reich 117, Mittelmeer, England + Nordpuffer):

```sh
python3 tools/region_coverage_check.py --data-root . --json /tmp/region-coverage.json
```

It lists every missing base tile per level and exits 1 on a gap, 3 if a bound file is absent. `READY` must read `complete`; `--focus`, `--radius-tiles`, `--max-tiles` or the 512 MiB disk-reserve stop leave a partial pyramid, which the runtime now reports as a warning instead of silently drawing coarse parents.

The second command writes marine SDF-zero contour segments only. Their side faces close the gap between elevated land and sea level without changing source heights or horizontal coastline position. Picking evaluates the visible 65-grid triangle with the actual parent/family/edge morph, rather than an unrelated finest cached image.

The previous terrain module remains as metadata/bootstrap and an explicit compatibility path; active camera updates use the clipmap controller. The current packaged scene still includes those modules. Full source raster arrays are not loaded by the clipmap path.

The real 72-second Britain→Egypt journey is under `docs/kit1/screenshots/britain-egypt/`: `journey.mp4`, `journey.gif`, `frametime.csv` and `frametime.png`. Video and raw frames remain local generated artifacts. The source harness is `app/scripts/clipmap/clipmap_journey.gd`; `tools/finish_clipmap_journey.py` encodes its actual frame timestamps. Capture readback/JPEG/keyframe-save time is recorded separately.

Observed frame intervals, Apple M3 Pro / Forward+ / Metal, during that recording:

| Recorded intervals | Median | p95 | Maximum |
| --- | ---: | ---: | ---: |
| All frames, including capture effects | 19.93 ms | 50.68 ms | 420.61 ms |
| No preceding framebuffer capture | 19.20 ms | 28.12 ms | 43.63 ms |

The second row is not pure GPU time or a separate capture-free benchmark. Capture work itself had a 25.68 ms median and 402.01 ms maximum. These numbers do not establish stable 60 fps.

The sampled route shows continuous terrain coverage, source forests and rivers. River support still used continuous texture height while the terrain draws grid triangles; the resulting broken river segments are a concrete remaining defect, addressed separately in the shared shader support sampler. Texture/material LOD transitions and full popping freedom remain open. The screenshots and runnable bundle are implementation progress, not a complete Kit acceptance.
