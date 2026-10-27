# Lauf 0 — Schätzwerte, 180 bis 680

Erzeugt mit:

```
python3 tools/sim_inputs.py
cd sim && cargo run --release -- --root .. --years 500 --out out
python3 tools/sim_render.py sim/out/leaves-680.csv docs/kit2/run-0/density-680.png --px-per-km 0.4
```

Ergebnis (adaptiv): `years=500 leaves=18184 splits=1395 merges=0
population=126904620 balanced=true fingerprint=872ccdcca5586e2d tick_us p50=231 p95=367 max=2763`.

Statisch (`--static`): gleiche Summe 126 904 620, 13 999 Blätter, Tick p50 68 µs.

| Jahr | Bevölkerung | K | Blätter |
|---|---|---|---|
| 180 | 93,6 Mio. | 129,4 Mio. | 13 999 |
| 280 | 106,7 Mio. | 129,4 Mio. | 18 184 |
| 480 | 121,5 Mio. | 129,4 Mio. | 18 184 |
| 680 | 126,9 Mio. | 129,4 Mio. | 18 184 |

Dichtekarten: `density-180.png`, `density-680.png` (Farbe = Menschen pro km² Land,
log; umrandete Felder = Tiles feiner als 25 km). Alle Werte sind Schätzungen,
siehe [ESTIMATES.md](../ESTIMATES.md).
