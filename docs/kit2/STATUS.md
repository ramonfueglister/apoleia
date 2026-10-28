# Kit 2 — Stand

**Stand:** 26.10.2026

| Bereich | Status | Nachweis / Grenze |
|---|---|---|
| Grundsätze, Raum, Zeit (S01–S22) | `spezifiziert` | decisions.md, Brainstorming 26.10.2026 |
| Subsystem 1 Bevölkerung (S30–S34) | `spezifiziert` | decisions.md, TASK.md |
| Vorbilder Bevölkerung und Preise | `erforscht` | REFERENCES.md |
| Startraster und IDs | `implementiert` (Kit 1) | `data/gametiles/`, `docs/kit1/GAMETILES.md` (Branch des Tile-Threads) |
| Prototyp Subsystem 1 | `implementiert` | `sim/`, 7 Tests; [Lauf 0](run-0/README.md) Schätzwerte, [Lauf 1](run-1/README.md) HYDE: 500 Jahre deterministisch, 2:1-balanciert, adaptiv = statisch |
| Eingabewerte Subsystem 1 | Startbevölkerung `belegt` (HYDE 3.3), K und r `geschätzt` | [ESTIMATES.md](ESTIMATES.md) |
| B08 Performance | `implementiert`, Mac-Messung `offen` | Tick p50 0,35 ms, p95 ~0,53 ms (Cloud); Spitzen bis 5 ms nur in Monaten mit Tausenden Teilungen |
| Datensatz Startbevölkerung 180 n. Chr. | `implementiert` | HYDE 3.3 Baseline 200 n. Chr. (popc, rurc, urbc, cropland), CC BY 4.0, `data/hyde33/`, `tools/sim_hyde.py` |
| Massstab und Einzelpersonen (S50–S87) | `entschieden` (27.10.2026), Umsetzung `offen` | [SCALE.md](SCALE.md); Prototyp mit Geburt, Ehe, Tod und Wanderung über 100 Jahre: [run-people](run-people/README.md); Getreidewirtschaft (S69–S76) als Prototyp: [run-grain](run-grain/README.md) |
