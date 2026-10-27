# Kit 2 — Abnahme Subsystem 1

**Status:** Prüfplan `spezifiziert`, alle Prüfungen `offen`.

| ID | Anforderung | Nachweis |
|---|---|---|
| B01 | Erhaltung beim Teilen/Zusammenlegen | Gesamtbevölkerung vor und nach jedem Teilen/Zusammenlegen identisch (Toleranz Gleitkomma) |
| B02 | Kein Sprung durch Teilen | Gesamtkurve eines Laufs mit und ohne adaptive Tiles weicht nur gering ab |
| B03 | Determinismus | Zwei Läufe mit gleichem Seed ergeben bitgleiche Ergebnisse |
| B04 | Stabilität | Keine negativen oder unendlichen Werte; P nähert sich K ohne Schwingen |
| B05 | Plausible Dichten | Startdichten und Dichten nach 100/500 Jahren liegen in historisch belegten Grössenordnungen (Quelle nennen) |
| B06 | Kein Flattern | Kein Tile teilt und legt sich innerhalb der Mindestdauer wiederholt zusammen |
| B07 | Zellbudget | Anzahl Zellen überschreitet das Budget nie |
| B08 | Performance | Ein Monatstakt über alle aktiven Tiles dauert auf dem Mac deutlich unter 1 ms; Messung mit Hardwareangabe |
