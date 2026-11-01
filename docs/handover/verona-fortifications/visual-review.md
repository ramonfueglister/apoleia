# Verona fortification visual review — 2026-11-01

Status: **all ten asset variants and five actual-city views validated**.

## Tomb models

`verona_tombs_altar`, `verona_tombs_shrine` and `verona_tombs_garden` were rendered from their actual GLBs in the isolated Godot preview at 900 × 900, using detail, medium and far roots. All nine images were opened and inspected individually.

All three variants are approved at all three tiers. The shrine retains closed roof planes, columns and open frontage. The round monument and garden exedra preserve their volumes. The flat ground base avoids the earlier architectural plinth appearance; the southern paved approach remains free. Fine inscriptions and trim intentionally disappear at distance; cypress crowns become coarser polygonal forms without losing their tall silhouette. No correction was requested.

Images are `build/roman-series-preview/renders/verona_tombs_{altar,shrine,garden}.png`, with `-medium` and `-far` suffixes for the other tiers. Reproduction uses `tools/buildings/preview_roman_series.gd` with `--medium` or `--far` and the three slugs. These are direct model renders, not generated concept images.

## Fortification models

The seven wall/gate variants were captured at detail, medium and far. Tower, gate and crossing detail views were inspected individually; all seven were then inspected across all three tiers in contact sheets. All are approved. Wall cores and coping remain closed and continuous. The tower and gate roof substrates remain intact when individual tiles disappear. Gate arches, four crossing piers and the two road axes retain their intended silhouette. Buried foundation geometry is deliberately visible in the studio previews. The refreshed cardinal wall-arm row includes the corrected 6.5 m foundation, making its standalone silhouette taller; its above-ground wall height remains 7.8 m and the extended portion sits below the upper terrace in the application.

Durable contact sheets: [walls and tower](asset-lods-1.jpg), [gate and crossing](asset-lods-2.jpg), [connectors](asset-lods-3.jpg), [tomb variants](asset-lods-4.jpg). Each row shows detail, medium and far. `tools/buildings/montage_verona_fortifications.py` assembles them from unchanged capture pixels.

## Runtime coverage

See [layout audit](layout-audit.md) for the unchanged atlas graph, intended port overlap and passage constraints. `app/scripts/debug/verona_fortifications_check.gd` retains the existing Verona residential/street audit and adds geometry-based passage/join checks, complete-group gate fallback, individual wall filtering and the unchanged baseline placement bounds. The final actual-game run passed all assertions with zero failures after the targeted foundation repair. All five final captures were opened and visually inspected again.


## Actual-city result and remaining rendering limitation

Durable actual application captures: [1.5 km](width-1.5.png), [5 km](width-5.0.png), [12 km](width-12.0.png), [24 km](width-24.0.png), [60 km](width-60.0.png). The corresponding [final report](final-report.json) records the geometry, atomic fallback, atlas and existing-placement checks.

The new walls, gates and tomb groups form a coherent set with the accepted houses and monuments. Visible gate passages follow the existing roads, including the S/W bend through the crossing gate. Tomb front paths face the roadside. No new missing wall, roof hole, floating base or road obstruction was seen in the reviewed views. The source-level and shader-ground triangle tests supplement the images: the problematic stepped join is substantially occluded in the standard camera, so the overview alone would not have reliably detected its insufficient original skirt.

At the closest 1.5 km view, pronounced mottled shadow/surface artifacts remain on the small ashlar and roof details. Similar artifacts occur on existing house geometry. This is a shared-rendering limitation; the existing landscape light uses `shadow_normal_bias = 28.0`. Global lighting/shadow settings were not changed in this asset task, and no causal claim is made that this setting alone explains every artifact. The noise is much less prominent at 5 km and wider. Visible contacts can be reviewed, but hidden geometry and collision/navmesh behaviour are not certified by screenshots.

All 30 standalone model/LOD views were inspected, with the corrected wall arm rendered again at all three tiers. There are no unresolved asset geometry or tested layout failures. Performance observations, including the cost of the added geometry/material instances, are recorded in the integration owner's [validation report](validation.md); these host runs are not a controlled percentage speedup comparison.
