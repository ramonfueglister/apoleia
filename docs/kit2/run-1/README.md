# Lauf 1 — HYDE 3.3 (200 n. Chr.), 180 bis 680

Daten: HYDE 3.3 Baseline, Bevölkerung (`popc`), Landbevölkerung (`rurc`),
Stadtbevölkerung (`urbc`) und Ackerland (`cropland`) für 200 n. Chr., zugeschnitten in `data/hyde33/` (CC BY 4.0, Quelle in
`data/hyde33/SOURCE.md`). Für den Startzeitpunkt 180 wird das Jahr 200 verwendet.

```
python3 tools/sim_inputs.py
python3 tools/sim_hyde.py        # pop200 56,65 Mio., davon ländlich 56,09 Mio.; Ackerland 600 099 km²
cd sim && cargo run --release -- --root .. --years 500 --out out
```

Kapazität: K pro 25-km-Zelle = HYDE-Landbevölkerung / 0,7 (Start bei 70 % von K),
dazu die Städte nach Hanson 117 in ihrem Teil-Tile. Start = HYDE-Landbevölkerung
+ Städte. HYDE führt für 200 n. Chr. im ganzen Zuschnitt nur 0,62 Mio. Stadtbewohner
(Roms Zelle hat rund 70 000 Menschen); die Städteliste ersetzt diesen Anteil.
Siehe ESTIMATES.md und decisions.md S35.

Ergebnis (adaptiv): `inputs=hyde33 years=500 leaves=41827 splits=9276 merges=0
population=88477762 balanced=true fingerprint=a73d06332834ff09 tick_us p50=365 p95=528`.
Ein zweiter Lauf ergibt denselben Fingerabdruck. Statisch: gleiche Summe
88 477 762, Tick p50 81 µs.

| Jahr | Bevölkerung | K | Blätter |
|---|---|---|---|
| 180 | 66,1 Mio. | 90,1 Mio. | 13 999 |
| 280 | 74,9 Mio. | 90,1 Mio. | 34 867 |
| 480 | 84,9 Mio. | 90,1 Mio. | 40 042 |
| 680 | 88,5 Mio. | 90,1 Mio. | 41 827 |

## Vergleich: K aus HYDE-Ackerland (`--k-from-cropland`, erster Stand ohne `rurc`)

K = Ackerland × 100 Menschen pro km² ergibt 70,0 Mio. Kapazität, aber 5 552
Tiles starten über K (zusammen rund 20 Mio. zu viel). Das Verhältnis Bevölkerung
zu Ackerland streut in HYDE pro Zelle stark (10 %-Quantil 29, Median 83,
90 %-Quantil 462 pro km²), am stärksten in Ägypten und Gallien. Folge: Einbruch
von 56,7 auf 47,9 Mio. in den ersten 100 Jahren, danach Erholung auf 63,9 Mio.
bis 680. Ohne Erträge pro Region (Klima, Boden, Bewässerung) passt eine
einzige Zahl pro km² Ackerland nicht.

## Grenzen

- B08: Tick p50 0,35 ms, p95 0,53 ms in der Cloud-Umgebung (nicht auf dem Mac
  gemessen). Monate mit Tausenden Teilungen (erster Monat) dauern bis 5 ms.
- 313 Land-Tiles bleiben leer, vor allem Wüste in Ägypten und kleine Inseln,
  für die HYDE keine Zelle hat.
- HYDE liegt für 200 n. Chr. eher tief (Spielgebiet 56,7 Mio., mit Städteliste 66,1 Mio.);
  ungeprüft gegen andere Schätzungen.
