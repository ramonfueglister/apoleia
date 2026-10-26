# Adaptive Spiel-Tiles (K25–K29)

Status: `implementiert` (Daten und Selbstprüfungen); Laufzeit-Teilen und -Zusammenlegen ist Kit 2.
Betrifft nur die logischen Spiel-Tiles (K17), nicht die Grafik-Streamingkacheln. Kein Rendering, keine Anzeige.

## Bauen

```
python3 tools/gametiles_terrain.py   # Copernicus DEM GLO-90 + ESA WorldCover 2021 → data/gametiles/terrain-25km.csv (~0,5 GB Range-Reads, Cache in data/raw/)
python3 tools/gametiles_places.py    # Städte/Orte über alle Epochen → data/gametiles/places*.csv
python3 tools/gametiles_build.py     # Quadtree → tiles.csv, summary.json, debug-map.png; Exit 1, wenn eine Prüfung fehlschlägt
```

Nur numpy und Pillow (Debug-Karte). Alle Parameter stehen in `data/gametiles/rules.json`.

## Identität (K25, K28)

`eqc41-gt-v1:{Ebene}:{Zeile}:{Spalte}` mit Kantenlänge `200 km / 2^Ebene`, `Zeile = floor(z/Kante)`, `Spalte = floor(x/Kante)`
in den projizierten Metern von `data/projection.json`. Ebene 0 = 200 km, 3 = 25 km (genau 25 × 25 Zellen von
`eqc41-km-v1`), 5 = 6,25 km, 7 ≈ 1,56 km. Eltern = `(Ebene−1, Zeile>>1, Spalte>>1)`, Kinder = `(Ebene+1, 2·Zeile+i, 2·Spalte+j)`.
Eine ID hängt nur von der Geometrie ab: Zusammenfassen, späteres Teilen (auch zur Laufzeit) und neue Daten benennen
nichts um. Tiles unter 25 km sind nicht mehr bündig zum 1-km-Raster (12,5 km = 12½ Zellen); das ist bewusst so.

## Regeln (Designentscheidungen, Schwellen sind Startwerte)

| Klasse | Größe | Regel |
|---|---|---|
| Land | 25 km | jedes 25-km-Tile mit Land; Seen gehören zu Land (K27) |
| Küstenmeer | 50 km | 4 landfreie Kinder |
| Offenes Meer | 100 / 200 km | landfrei und kein Land im um 50 / 100 km erweiterten Quadrat |
| Hochgebirge, Wüste | 50 km | alle 4 Kinder ganz Land und Wüste (≥ 80 % kahl, WorldCover 60) oder Hochgebirge (≥ 50 % über 1500 m **und** ≥ 30 % über 2000 m) |
| Reine Wüste | bis 200 km | alle Kinder Wüste (K26 „gleichartig“) |
| Leeres Land | 50 km | kein Ort aus `places*.csv` in irgendeiner Epoche in einem der 4 Kinder |
| Dichte Regionen | 12,5 km | Wichtigkeit nach K29, absteigend bis zum Budget |
| Großstädte | 6,25 km | die 35 Städte mit dem besten Rang in irgendeinem Stichjahr; ihr ganzes 25-km-Tile |

Alle Regeln gelten überall gleich, im Reich und außerhalb (Ramon, 26.10.2026). Nach jedem Schritt gilt die 2:1-Regel
(Kantennachbarn höchstens eine Ebene Unterschied). Reihenfolge der Verfeinerung: Großstädte, Handliste
(`places-manual.csv`, Vorschlag), dann 25-km-Tiles nach Wichtigkeit; Abbruch vor Überschreiten des Budgets.

Wichtigkeit (K29) je 25-km-Tile und Stichjahr (117, 400, 1000, 1500, 1800, 1900, 2020): Summe der Stadtbevölkerung
geteilt durch das Mittel der 50 stärksten Tiles dieses Jahres (relativ zur Epoche), Maximum über alle Jahre, +0,05 für Häfen.

## Ergebnis (gametiles-v1)

Gemessen, siehe `data/gametiles/summary.json`:

- **Gesamt:** 13.999 Tiles bei Budget 14.000.
- **Vor der Stadtverfeinerung:** 11.631 Tiles.
- **Nach Größe:** 200 km 103 · 100 km 315 · 50 km 3.367 · 25 km 8.186 · 12,5 km 1.500 · 6,25 km 528.
- **Kontrollliste:** Die Top 50 je 117/1000/1500/2020 liegen alle (200/200) in 12,5- oder 6,25-km-Tiles.
- **Gegenprobe:** Jede 6,25-km-Stadt gehört in einem Stichjahr zu den Top 50.
- **Selbstprüfungen:** eindeutige IDs, ID↔Geometrie, lückenlose und überlappungsfreie Abdeckung der Region, 2:1-Regel, 25-km-Bündigkeit.

Die erste Schätzung in K25–K28 (10.000–11.000) rechnete nur das Reichsland; die Region ist zu 78 % Land.
Strikt nach K27 wären es rund 22.500 Tiles. Die Regeln für reine Wüste und leeres Land bringen es auf das Budget.

## Quellen und Vorbehalte

- **Gelände:**
  - Copernicus DEM GLO-90 (DLR/Airbus, Copernicus-Lizenz) und ESA WorldCover 2021 v200 (CC BY 4.0).
  - Gelesen werden die internen Übersichtsstufen (~1/300°); Details in `terrain-sources.json`.
  - Das DEM ist ein Oberflächenmodell.
- **Orte:**
  - Reba/Reitsma/Seto 2016 (Chandler, Modelski; CC BY 4.0).
  - Hanson 2016 Cities Database (Lizenz der Originaldaten vor Weitergabe prüfen).
  - Bosker/Buringh/van Zanden 2013 (CC0), Natural Earth (gemeinfrei), Pleiades (CC BY 3.0).
  - Details in `places-sources.json`.
- **Antike Einwohner:** Die Zahlen für 117 sind Modellschätzungen aus der Siedlungsfläche, keine Zählungen.
- **Lücken:** Für das Jahr 400 gibt es nur 18 Werte.
- **Verzerrung bei „leerem Land“:** Die antiken Listen decken nur das Reich ab. Draußen gilt Land deshalb eher als „leer“. Entsteht dort im Spiel eine Stadt, teilt die Laufzeit das Tile (Kit 2).

## Laufzeit (Kit 2)

Das Raster ist der Startzustand. Teilen bis Ebene 7, Zusammenlegen mit Hysterese, 2:1-Regel, festes Zellbudget,
deterministisch im Monatstakt in ID-Reihenfolge; die Summen bleiben erhalten. Abgestimmt in `kit2/entscheidungen.md`
(Projektordner) mit dem Simulations-Thread.
