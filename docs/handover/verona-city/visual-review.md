# Verona city visual QA — 2026-11-01

Status: **native asset LODs and actual-city final audit validated**. This report supersedes the earlier Roman-series medium/far rejection and temporary detail/medium runtime fallback. Taverna remains unchanged.

## Reviewed assets and evidence

All 19 original series GLBs were reviewed with the new `shape_preserving_v1` medium and far geometry in the isolated Godot preview project. The six monument pilot models were inspected individually at both tiers; the other thirteen were inspected in six-model contact sheets at both tiers. The existing detail/front/rear review remains applicable; the exporter owner separately verifies accepted detail geometry identity.

The preview uses actual GLB geometry/materials, a bounds-fitted orthographic camera, 900 × 900 pixels, neutral warm illumination, ground shadows and SSAO. These are rendered model screenshots, not concept art. Enlarged far screenshots expose simplification more strongly than distant gameplay does.

| Asset group | Models | Medium | Far |
|---|---|---|---|
| Houses/crafts | Domus, Insula, Villa rustica, Bäckerei, Töpferei, Schmiede, Mühle | Approved | Approved |
| Civic | Curia, Macellum, Horreum, Bibliothek, Stadttor, Leuchtturm | Approved | Approved |
| Monuments | Amphitheater, Theater, Capitolium, Thermen, Basilika, Rundtempel | Approved | Approved |

The corrected amphitheater and theater preserve continuous arcades, seating and wall masses. Thermen retains closed dome and barrel-roof surfaces. Roof substrates stay closed when fine tile geometry is removed. Courtyard holes, column spacing, door openings, tower walls and the gate's central passage remain legible. No missing structural wall, new roof hole or fragmentary facade was found in the reviewed views. Reduced tile/ornament density at distance is intentional.

Five new Verona models were inspected individually at detail and far:

| Asset | Reviewed features | Verdict |
|---|---|---|
| `verona_courtyard_house` | Open courtyard, connected roof wings, small entrance/shop | Approved |
| `verona_townhouse` | Ground arcade, upper loggia and roof closure | Approved |
| `verona_terrace_house` | Terrace, pergola supports and rear house mass | Approved |
| `verona_street_house` | Compact multistorey facade, roof and entrance | Approved |
| `verona_street_shop` | Small canopy/shop entrance and closed roof | Approved |

Evidence in `build/roman-series-preview/renders/`:

- `all-19-medium.jpg`, `all-19-far.jpg` and `gallery-medium-1.jpg` through `gallery-medium-4.jpg`, plus equivalent `gallery-far-*`.
- `<slug>-medium.png` and `<slug>-far.png` for original 19.
- `verona_<variant>.png` and `verona_<variant>-far.png` for the five new assets.
- Original `all-19.jpg` and `all-19-rear.jpg` document accepted detail front/rear geometry.

Capture/montage reproduction uses `tools/buildings/preview_roman_series.gd` and `tools/buildings/montage_roman_series.py`, documented in the [original review](../roman-series/visual-review.md). Runtime may now use native requested detail/medium/far tiers for assets marked `shape_preserving_v1`; no model-specific detail-only exception is required by this visual review.

## Verona scope and constraints

The unchanged Verona atlas has eight residential parcels, sixteen street parcels, four wall parcels, four gates, twenty-three tomb parcels and ten plaza parcels. Five residential parcels already used authored buildings; the remaining three receive the new courtyard/townhouse/terrace variants. Atlas residential caps are 9 m; the courtyard replacement deliberately stays within 6.5 m.

The principal residual house-style mismatch came from **23 houses generated inside street parcels**, outside the eight residential parcel count: nine street rows, seven west corners and seven east corners. These receive the compact street house/shop variants, with individual old-piece filtering only after successful installation. Existing walls, gates, plazas, tombs, streets and terrain remain intentional infrastructure. This work does not change atlas cells or road links.

Source limits are 2.8 × 2.8 m / 6.5 m height for the street house and 2.8 × 2.0 m / 3.7 m height for the street shop. Fit is uniform; height is not independently stretched. Road checks use the connected central driving bands with 1.26 m half-width in the common diorama scale.

## Actual-game audit and performance protocol

`app/scripts/debug/verona_city_check.gd` captures the actual application at 1440 × 1000, target (-672, -494), widths 1.5, 5, 12, 24 and 60 km. It pauses GameClock, warms up each view for 60 frames, then records 60 samples of frame interval, process time, renderer CPU/GPU time, draw calls and primitives. Baseline output is `build/verona-city/baseline/report.json` and five width screenshots. Final output uses the same protocol under `build/verona-city/final/`.

The baseline completed with zero reported failures. Median frame intervals were 19.197 / 25.200 / 13.715 / 16.728 / 16.748 ms across the five widths; median draw calls were 908 / 942 / 731 / 649 / 503. Host contention produced noisy p95 values, so this baseline alone does not justify a precise speedup claim.

Final-mode assertions cover:

- Eight residential atlas cells with no legacy residential mesh parts.
- Twenty-three individually installed street replacements, without suppressing entire street parcels.
- Actual transformed detail mesh bounds inside assigned plots and outside connected driving bands.
- Height caps and shared mesh resource identity for repeated assets.
- Native requested/rendered LOD equality with exactly one visible root per visible building.
- Atlas/page hashes unchanged and no loader failures.
- Isolated unloaded and partially installed filter tests preserve old pieces until replacement exists.

The final actual-game run completed with **zero failures**, 35 Verona series replacements installed, and all 23 street pieces replaced individually. All assertions listed above passed. Its five saved screenshots were opened and visually inspected at every capture width.

Visible new residential and street buildings sit coherently on their paved plots. Visible storefront and door approaches remain open; the central road bands remain clear. No visibly floating foundation, new roof hole or fragmented wall was found. The existing tall walls and foreground buildings obscure some lower door/foundation contacts, so visual inspection cannot certify hidden areas; the passing actual-bounds checks provide additional evidence. Fine roof tiles still show patterned shadow/surface noise at the closest view. Existing infrastructure retains its previous style.

This does not establish collision/navmesh behaviour or a controlled framerate improvement. The final benchmark has more near geometry and draw calls because 26 additional residential/street instances replace simpler procedural pieces. Primitive totals at the three wider views are lower despite those additions. Shared asset mesh resources were verified, but repeated instances still incur draw calls; resource sharing does not imply automatic instancing of every material batch.


| Width km | Baseline/final median frame ms | Baseline/final draw calls | Baseline/final primitives |
|---|---:|---:|---:|
| 1.5 | 19.197 / 9.427 | 908 / 1,932 | 2,420,360 / 3,254,040 |
| 5 | 25.200 / 14.152 | 942 / 1,972 | 6,059,048 / 6,307,526 |
| 12 | 13.715 / 10.556 | 731 / 916 | 2,403,508 / 2,100,047 |
| 24 | 16.728 / 13.493 | 649 / 816 | 3,345,279 / 3,274,445 |
| 60 | 16.748 / 13.481 | 503 / 485 | 4,523,163 / 4,450,161 |

These are observed host runs, not a causal percentage speedup measurement. The noisier baseline and changing content limit direct timing comparison. Native LOD correctness and reduced wider-view primitive load are established separately from timing.
