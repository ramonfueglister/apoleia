# A16 NA-Revision r1 (26.10.2026)

Umsetzung von Punkt 4.1 aus [A16_TOOL_ACCEPTANCE.md](../A16_TOOL_ACCEPTANCE.md) für
`runs/kit1-landscape-v5-2026-10-25`. Die eingefrorenen Laufdateien bleiben unverändert;
diese Revision liegt daneben.

- `derivation-view.json` ist lokal-only (40 MB, gitignored). Committet sind nur die vier
  Einträge [`not-applicable.json`](not-applicable.json) und [`apply_na.py`](apply_na.py),
  das sie deterministisch in eine lokale Kopie einsetzt.
  - Quelle `data-report-errata/release-v2/derivation-view.json`: SHA `70787790435205de0cb678cbcbb609df10d4d694809473214b766e2d6c96cc88`
  - Ergebnis: SHA `c1ea9d503f38c15240b60ad5b4f119f91f188c91705d612dedc93b652db240b5`
- NA: overview und canonical × `screen_error_px`, `transition_residual_px`; Regel
  `data-report-errata/release-v2/policy-application-v1.json` (SHA `e4f66e47c36a…`).
- [`report.json`](report.json): Laufbericht mit neu gebundenem `derivation`-Hash; sonst unverändert.
- [`report-check.json`](report-check.json): `kit.py report-check` auf einer lokalen Kopie des
  Laufs mit beiden Dateien. Vorher: `derivation level/metric coverage incomplete` und
  A08/A12/A16 `not evidenced/validated`. Nachher: nur noch A08/A12/A16
  `not evidenced/validated`; diese Status setzt die unabhängige Prüfung, kein Agent.

Nachprüfen (lokale Kopie des Laufs nötig):

```sh
cp -cR <checkout-mit-lauf>/runs/kit1-landscape-v5-2026-10-25 /tmp/a16-run
python3 docs/kit1/evidence/a16-na-r1/apply_na.py /tmp/a16-run /tmp/a16-na
cp /tmp/a16-na/derivation-view.json /tmp/a16-run/data-report-errata/release-v2/derivation-view.json
cp docs/kit1/evidence/a16-na-r1/report.json /tmp/a16-run/report.json
python3 docs/kit1/tools/kit.py report-check /tmp/a16-run
```
