# Verona fortification layout audit — 2026-11-01

Status: **layout, native LODs, terrain-aware joins and actual-city views validated**.

The existing reference-status Verona atlas remains authoritative for placement. This work changes rendering assets, not atlas cells, road links, terrain heights or city geography. The stylised gate/tower design is an original design choice, not a claim that the resulting geometry reconstructs a specific historical phase of Verona.

## Existing topology

Verona origin is (18445, 6906), size 28 × 29 parcels. Coordinates below are offsets from that origin. There are four wall parcels, four gate parcels and 23 tomb parcels. Independent atlas decoding confirms seven undirected links:

| From | To | Direction |
|---|---|---|
| Wall (13,12) | Gate (14,12) | Cardinal |
| Wall (13,12) | Wall (12,13) | Diagonal |
| Wall (12,13) | Gate (12,14) | Cardinal |
| Gate (12,14) | Wall (12,15) | Cardinal |
| Wall (12,15) | Wall (13,16) | Diagonal |
| Wall (13,16) | Gate (14,16) | Cardinal |
| Gate (14,12) | Gate (15,13) | Diagonal |

This forms a connected **open chain**, not an enclosing ring. The gate-to-gate diagonal is supported by the existing atlas but lacked explicit connectors in the old rendering. The new renderer supplies both connector halves without adding an atlas edge. No missing edge is inferred to close the wall.

Gate road links are N/S at (14,12), E/W at (12,14), N at (14,16), and S/W at (15,13). The final gate therefore requires a crossing pavilion with both axes open; a rotated straight gate would block one road arm.

## Ports and clearances

A parcel spans 0.25 world-km, or 10.5042 model-metres using `DIORAMA_KM_PER_M = 0.0238`. With unchanged authoring origin and uniform unit scale:

- Cardinal arms ending at 5.3 m from each parcel centre overlap by 0.0958 m.
- Diagonal arms ending at 7.6 m overlap by 0.3448 m.
- Wall arms begin at -1.15 m; gate connectors begin at +3.5 m to avoid the passage.
- Connector half-width 1.15 m puts its nearest diagonal starting corner 1.6617 m from a road axis, outside the driving half-width 1.26 m.
- Straight gate pavilions at x = ±3.55 m, width 2.8 m, leave the central strip clear to ±2.15 m. The arch's requested clear opening is 3.6 m.
- Crossing corner piers at (±3.55, ±3.55) leave both central axes open. Basal trim and buried skirts must stay out of these openings.

These dimensions establish feasibility, not final mesh correctness. The runtime audit tests actual triangles at connected road lanes and across every joining arm endpoint at all three native LODs. Joining arms intentionally extend slightly beyond parcel boundaries; ordinary building footprint containment is not the appropriate test for these pieces. Tomb models remain subject to ordinary plot containment and a 7 m height cap.

## Regression evidence

Accepted pre-fortification city captures and report are preserved in `build/verona-fortifications/baseline/`, copied from `build/verona-city/final/`. `capture-provenance.json` records their SHA-256 hashes. Durable copies of the report and provenance are saved alongside this document as `baseline-report.json` and `baseline-provenance.json`; the test reads the durable report so it also works after a fresh checkout. The reproducible actual-game check is `app/scripts/debug/verona_fortifications_check.gd`; it extends the accepted city check, compares all 35 existing series placements with that baseline, and tests unchanged atlas/page hashes. It also tests isolated incomplete gate groups and partially loaded wall pieces without changing live game state.

Terrain-aware joins additionally read the actual rendered HDR corner-cache texture, reproduce the building shader's terrace-top offset, and query mesh cross-sections at both adjacent ground heights plus 0.35 m. CPU camera-focus `ground_y` is not treated as the rendered terrace top. The first run found a 6.302521 m step between wall (12,13) and gate (12,14), at shader ground elevations 0.60595 and 0.45595 world-km. Its 2 m skirt failed the lower-ground sample in all three LODs. Only the cardinal wall-arm foundation was extended to 6.5 m; geometry at and above source z=0, all port lengths and the other six fortification assets remained unchanged. The final run passed all seven joins, with the same measured terrain step. Other fortification foundations remain 2 m deep.

## Final outcome

[Final report](final-report.json): zero failures; four wall parcels, four atomic gate groups and 23 tomb parcels; 696 actual triangle ray checks across native detail/medium/far. Sixteen partial-group loading observations also confirmed that incomplete new gates remain invisible while the original remains present. The eight residential cells, 23 street replacements and all 35 pre-existing series placement bounds are unchanged. Atlas/page hash checks passed. The [first-pass report](first-pass-report.json) preserves the three failures that led to the targeted foundation correction.
