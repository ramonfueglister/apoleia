# Kit 2 — Schätzwerte für den Prototyp Subsystem 1

**Stand:** 26.10.2026.

**Mit HYDE 3.3 (Standard seit Lauf 1):** Startbevölkerung pro 25-km-Zelle aus
HYDE 3.3 für 200 n. Chr. (`data/hyde33/`, CC BY 4.0). K pro Zelle = HYDE-Landbevölkerung
/ `start_fill` (0,7), Städte wie unten; Start = Landbevölkerung + Städte. Geschätzt bleiben r, `start_fill` und
der Städteplatzhalter; Ackeranteil, Hochland und Menschen pro km² Ackerland
werden in diesem Modus nicht gebraucht. Begründung und Vergleich mit K aus
HYDE-Ackerland: [run-1](run-1/README.md).

**Ohne HYDE (`--estimates`, Lauf 0):** alle Werte `geschätzt` (eigene Designannahmen,
keine belegten Daten):

| Wert | Schätzung | Code (`sim/src/lib.rs`, `Params`) | Herleitung / Grenze |
|---|---|---|---|
| Wachstumsrate r | 0,6 %/Jahr | `r_per_year` | Hypothese: vormoderne Wachstumsraten weit unter 1 %/Jahr; ohne Hunger/Seuchen ist r nur die Annäherungsgeschwindigkeit an K |
| Ackeranteil an Landfläche | 15 % | `cropland_share` | **kalibriert**, damit die Startsumme bei rund 94 Mio. liegt; einheitlich für alle Tiles |
| Menschen pro km² Ackerland | 100 | `people_per_cropland_km2` | Hypothese für Getreideversorgung ohne Importe |
| Abzug Hochland (> 1500 m) | 80 % | `highland_penalty` | Anteil > 1500 m trägt nur 20 % |
| Kahl/Schnee | trägt 0 | — | aus `terrain-25km.csv` (`frac_bare`, `frac_snow`) |
| Klima/Boden | **nicht modelliert** | — | fehlt; deshalb hat Germanien dieselbe Dichte wie Italien |
| Startfüllung | 70 % von K | `start_fill` | Platzhalter für die fehlende Startbevölkerung 180 |
| Städte | K += Einwohner 117 (Hanson) | `cities.csv` | Platzhalter für Importe (S33): Stadt trägt sich selbst, wächst nicht |
| Teilen / Zusammenlegen | > 200 / < 100 Menschen pro km² Land, 12 Monate | `split_density`, `merge_density`, `merge_months` | wie in decisions.md S13 |
| Zellbudget | 65 536 Blätter | `budget` | S12 |

## Bekannte Folgen der Schätzung

- Die Fläche ausserhalb der Wüsten ist fast einheitlich dicht, weil Ackeranteil
  und Klima nicht variieren. Unterschiede kommen nur aus Hochland, Wüste und Städten.
- Städte teilen ihre Tiles bereits im ersten Jahrzehnt; danach ändert sich die
  Struktur nicht mehr (keine Migration, kein Wachstum von K).
- Die Gesamtsumme 180 (93,6 Mio.) ist deshalb ein gesetztes Ziel, kein Ergebnis.
