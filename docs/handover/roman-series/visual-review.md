# Roman series visual review — 2026-11-01

> Historical review of the first export/integration. The rejected global-decimation LODs and temporary runtime fallback described below have since been replaced by visually approved `shape_preserving_v1` assets. See [Verona city visual QA](../verona-city/visual-review.md) for the current verdict. Medium/far screenshot paths below now contain the corrected native LODs; they are no longer evidence of the historical rejected export. Detail/front/rear findings remain applicable.

All 19 new GLBs were rendered in an isolated Godot 4.7.2 project at 900 × 900 pixels with an orthographic camera, warm neutral directional/ambient lighting, ground shadows and SSAO. Actual exported geometry and embedded materials were used; these are screenshots, not concept illustrations. Taverna was neither changed nor re-exported.

Every front detail image was inspected individually. Opposite rear detail views and medium views were inspected in six-image contact sheets. Corrected models were rendered and inspected again. All 19 preview GLB snapshots matched the corresponding application GLBs by SHA-256 at the end of this review.

## Evidence

Generated files are local build artifacts, not application resources:

- `build/roman-series-preview/renders/all-19.jpg`: final front detail gallery.
- `build/roman-series-preview/renders/all-19-rear.jpg`: final opposite rear gallery.
- `build/roman-series-preview/renders/all-19-medium.jpg`: medium comparison gallery, including known defects listed below.
- `build/roman-series-preview/renders/<slug>.png`: individual front detail image.
- `build/roman-series-preview/renders/<slug>-rear.png`: individual opposite rear detail image.
- `build/roman-series-preview/renders/<slug>-medium.png`: individual medium image.
- `build/roman-series-preview/renders/leuchtturm-far.png`: rejected far simplification evidence after the minimum-triangle retention fix.

`tools/buildings/preview_roman_series.gd` is the reproducible capture script. It loads copied GLBs directly with GLTFDocument, selects the requested LOD root, calculates camera framing from visible bounds, and captures after 20 frames. `tools/buildings/montage_roman_series.py` assembles the screenshots with Pillow. Preview project/assets are under `build/roman-series-preview`; this review did not import or start the main application.

Example from the repository root:

```sh
godot --path build/roman-series-preview --script "$PWD/tools/buildings/preview_roman_series.gd" -- curia stadttor
godot --path build/roman-series-preview --script "$PWD/tools/buildings/preview_roman_series.gd" -- --rear curia stadttor
godot --path build/roman-series-preview --script "$PWD/tools/buildings/preview_roman_series.gd" -- --medium curia stadttor
build/verona-venv/bin/python tools/buildings/montage_roman_series.py
```

## Findings and final model verdicts

“Medium at distance” means the overall silhouette remains coherent, but it is not a substitute for the detail mesh when viewed close up. The 900-pixel captures intentionally expose simplification artifacts more clearly than normal distant gameplay would.

| Model | Detail front/rear | Medium verdict |
|---|---|---|
| Domus | Reviewed; courtyards and rear elevations coherent | At distance only; paving triangulation and roof noise |
| Insula | Reviewed; balconies, shop arcades, courtyard coherent | At distance only; paving/roof noise and rough window trim |
| Villa rustica | Reviewed; courtyard, wings and rear house coherent | At distance only; paving and roof noise |
| Bäckerei | Reviewed; shop, bread and chimney distinguish use | At distance only; paving and roof noise |
| Töpferei | Reviewed; kiln and pottery work courtyard coherent | At distance only; paving and roof noise |
| Schmiede | Reviewed after hearth correction | At distance only; paving and roof noise |
| Mühle | Reviewed; waterwheel/channel remain clearly legible | At distance only; paving and roof noise |
| Curia | Reviewed after doorway and lintel corrections | Coherent at distance; coarse window trim |
| Macellum | Reviewed; open market court and central tholos | Coherent at distance; small stall details reduce |
| Horreum | Reviewed; loading ramp, buttresses and ventilation | Coherent at distance |
| Bibliothek | Reviewed after arched window and courtyard corrections | Coherent at distance; arch trim becomes coarse |
| Stadttor | Reviewed again after central road passage correction | Coherent at distance; coarse arch stones; centre stays open |
| Leuchtturm | Reviewed; tapered stages and lantern coherent | Coherent at distance; small window details reduce |
| Amphitheater | Reviewed; complete arcades and seating in detail | **Rejected:** arcades/seating break into fragmentary surfaces |
| Theater | Reviewed; stage facade, cavea and rear massing coherent | **Rejected:** outer arcades/seating fragment |
| Capitolium | Reviewed; podium, columns, pediment and rear panels | Coherent at distance; roof surface becomes coarse |
| Thermen | Reviewed after curved roof end closure | **Rejected:** dome/roof develops visible holes |
| Basilika | Reviewed; clerestory, porch and rear apse coherent | Coherent at distance; window/roof detail reduces |
| Rundtempel | Reviewed after continuous roof substrate addition | Coherent at distance; trim and steps become coarse |

## Corrections made from rendered evidence

- Curia: removed the horizontal cornice cutting through the bronze doorway; completed the door lintel and wall above it.
- Bibliothek: replaced rectangular dark window panels with true arched outlines, eliminating protruding black corners; kept the roof court open and connected courtyard columns with architraves.
- Leuchtturm: arched window recess outlines match their trim. Shared export cleanup now retains low-polygon structural material batches instead of collapsing entire tower walls to zero triangles.
- Schmiede: replaced a large flat orange hearth slab with a dark coal bed, separate glowing coals and small irregular flames.
- Thermen: closed front and rear gaps under the barrel roof with matching semicircular tympana and arched windows.
- Rundtempel: added a continuous terracotta cone beneath tile strips.
- Stadttor: replaced the centre pier and two lower openings with one genuine central barrel-vaulted opening, retaining both polygonal towers and the upper gallery. Clear source width is 10.5 m; paving depth remains 12 m. The placement agent separately verified road centre and both road edges against actual detail/medium triangles at hip and head height.

## Runtime LOD decision and limits

The aggressive 3.5% far geometry is **not visually approved**. The inspected lighthouse far model lost major plinth/column/paving volumes even after its tower-wall batches were protected. No blanket claim is made that every far model was individually inspected.

Integration policy agreed with root:

- Amphitheater, Theater and Thermen use detail geometry at every requested distance tier.
- The remaining 16 use detail nearby and medium at distance; requests for far reuse medium geometry.
- Far requests may still disable shadows without changing to the rejected far mesh.

This trades some distant rendering cost for reliable geometry. The policy is temporary until shape-preserving LOD assets are built and visually verified. Distant house/craft paving still has visible triangular surface patterns in enlarged medium captures; it is not a close-view quality target. Performance and actual scene placement are separate integration checks handled by root. This report does not claim a gameplay framerate or historic archaeological accuracy.

## Actual game integration screenshot review

All 19 individual captures under `build/roman-series/integration/<slug>.png` were subsequently opened and visually inspected, focusing on terrain seating, neighbouring structures and road relationships rather than studio presentation. These show the actual application scene and UI. The corresponding `report.json` records all 19 installed models, no loader failures, no integration failures, and an unchanged atlas hash; this visual review supplements those checks.

Observed outcome:

- No new obvious floating foundation, terrain penetration, or building-body intersection with a neighbouring structure was visible in the captures.
- Amphitheater, Theater, Capitolium, Basilika and Thermen sit coherently on their paved landmark plots. Detail-only exceptions remain visually intact in the actual scene.
- Curia, Bibliothek, Macellum and the house/craft models fit within the existing dense settlement layout in the visible portions of their plots.
- Stadttor has a visibly open central passage aligned with the paved road; its towers fit between the existing wall ends.
- Leuchtturm sits on the coastal retaining plinth. The initial top crop was resolved by widening capture/launcher framing; the updated image was inspected and shows the entire lantern roof and tower.
- Mild patterned shadow and roof-surface noise remains visible, particularly on the finer tiled roofs. No new material-loading failure or missing-material colour was seen.

Visibility limits: foreground houses and walls substantially obscure the foundations of Domus, Horreum, Insula, Töpferei and Rundtempel, and partially obscure Mühle. A single camera image cannot certify hidden contacts; the separate plot bounds and passage ray checks remain relevant. Existing tall walls/terrace retaining structures and foreground occlusion should not be mistaken for new model penetration. The screenshot review does not establish collision/navmesh behaviour or a performance target.
