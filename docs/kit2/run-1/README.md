# Lauf 1 — HYDE 3.3 (200 n. Chr.), 180 bis 680

Daten: HYDE 3.3 Baseline, Bevölkerung (`popc`) und Ackerland (`cropland`) für
200 n. Chr., zugeschnitten in `data/hyde33/` (CC BY 4.0, Quelle in
`data/hyde33/SOURCE.md`). Für den Startzeitpunkt 180 wird das Jahr 200 verwendet.

```
python3 tools/sim_inputs.py
python3 tools/sim_hyde.py        # pop200 im Spielgebiet 56,65 Mio., Ackerland 600 099 km²
cd sim && cargo run --release -- --root .. --years 500 --out out
```

Kapazität: K pro 25-km-Zelle = HYDE-Bevölkerung / 0,7 (Start bei 70 % von K),
Städte nach Hanson 117 wie bisher in ihrem Teil-Tile. Siehe ESTIMATES.md.

Ergebnis (adaptiv): `inputs=hyde33 years=500 leaves=39940 splits=8647 merges=0
population=82391504 balanced=true fingerprint=97d08bf626f04ae6 tick_us p50=320 p95=473 max=5153`
(nach der Optimierung vom 26.10.2026; vorher p50 590, p95 1865 µs bei identischem Ergebnis).
Ein zweiter Lauf ergibt denselben Fingerabdruck. Statisch: gleiche Summe
82 391 504, Tick p50 77 µs.

| Jahr | Bevölkerung | K | Blätter |
|---|---|---|---|
| 180 | 56,7 Mio. | 86,0 Mio. | 13 999 |
| 280 | 65,9 Mio. | 86,0 Mio. | 30 670 |
| 480 | 77,3 Mio. | 86,0 Mio. | 37 096 |
| 680 | 82,4 Mio. | 86,0 Mio. | 39 940 |

## Vergleich: K aus HYDE-Ackerland (`--k-from-cropland`)

K = Ackerland × 100 Menschen pro km² ergibt 70,0 Mio. Kapazität, aber 5 552
Tiles starten über K (zusammen rund 20 Mio. zu viel). Das Verhältnis Bevölkerung
zu Ackerland streut in HYDE pro Zelle stark (10 %-Quantil 29, Median 83,
90 %-Quantil 462 pro km²), am stärksten in Ägypten und Gallien. Folge: Einbruch
von 56,7 auf 47,9 Mio. in den ersten 100 Jahren, danach Erholung auf 63,9 Mio.
bis 680. Ohne Erträge pro Region (Klima, Boden, Bewässerung) passt eine
einzige Zahl pro km² Ackerland nicht.

## Grenzen

- B08: Tick p50 0,32 ms, p95 0,47–0,55 ms in der Cloud-Umgebung (nicht auf dem
  Mac gemessen). Einzelne Monate mit vielen Teilungen (erster Monat: 4 429) dauern
  bis 6 ms; in 6 von 500 Jahren liegt das Jahresmaximum über 1 ms. Auch der
  statische Lauf zeigt Ausreisser bis 1 ms (Messrauschen der Umgebung).
- HYDE liegt für 200 n. Chr. eher tief (Spielgebiet 56,7 Mio.); Wert ist ungeprüft
  gegen andere Schätzungen.
