# A16 – unabhängige Prüfung

Commit `2499b17` (main). Die NA-Revision `a16-na-r1` wurde über `git show 4a99fc7` gelesen,
denn auf main fehlt sie. Prüfer: independent-claude-subagent. Datum: 26.10.2026.
Maschinenlesbar: [`review.json`](review.json).

**Urteil: PARTIAL**, keine A16-Freigabe.

## Was trägt

- **14 anwendbare Kombinationen:** Alle liegen innerhalb der Budgets aus `geodata_policy.json`
  (policy-v3, SHA `289fdb60…`). Aus getrackten Rohdaten nachgerechnet:
  - Küste: 2040.13 / 2797.25 / 2039.41 m, Budget 6000 m
  - Projektion: 0.4242, Budget 0.5
  - detail-Bildschirmfehler: 0.656 px, Budget 2 px. Das Maximum gilt für die 2087 Samples im
    Viewport, die übrigen 6607 Samples liegen außerhalb des Bilds.
  - detail-Übergangsresiduum: 0.0685 px, Budget 1 px
- **4 NA (overview/canonical × screen/transition):** Sie entsprechen genau
  `policy-application-v1.json` (SHA `e4f66e47…` stimmt, `rendered_in_valid_runs: false`) und
  `errata-binding.json`. Keine Quellraummetrik ist NA. Es gibt keinen Hinweis darauf, dass NA
  einen Fehlwert verdeckt: Für diese Kombinationen existieren keine Messwerte, die
  Renderwerte sind in `derivation-measurements.json` als `null` geführt.
- **Hashes:** README, `report.json` (r1) und `apply_na.py` sind untereinander konsistent
  (70787790… → c1ea9d50…). Der Diff zum eingefrorenen `report.json` betrifft nur den
  derivation-Hash.

## Befunde

- **P1:** `docs/kit1/evidence/a16-na-r1/` liegt nicht auf main. Auf main bindet die
  report.json weiterhin die Fassung ohne NA. ACCEPTANCE.md nennt trotzdem „4 NA mit Regelbezug“.
- **P1:** `report-check.json` ist nicht reproduzierbar. `derivation-view.json` ist gitignoriert,
  und die Datei nennt weder Kommando noch Commit noch Eingabehashes.
- **P1:** Echte Zoomaufnahme und unabhängige Bildprüfung fehlen im Checkout. Der A16-Status
  ist `offen`.
- **P2:** `apply_na.py` prüft den Ergebnis-Hash nur als 12-stelliges Präfix. Ein vorhandenes
  `not_applicable` wird überschrieben. Der README-Aufruf schreibt über die Quelldatei.
  Die Logik selbst ist deterministisch.
- **P2:** `kit.py` prüft bei der NA-Regel nur Existenz und Hash, nicht ihren Inhalt
  (Niveau/Metrik, „nicht gerendert“).
- **P2:** Die NA-Anwendungsregel entstand nach den früheren Läufen. Sie ist also keine vor
  der Messung versionierte Regel.
- **P2:** Die Testangabe ist veraltet. Ist-Stand: 46 Tests, 1 FAIL und 2 ERROR wegen kaputter
  Links auf fehlende gamegraphics-Dateien. Das betrifft A16 nicht, die NA-Tests sind grün.
- **P2:** Die Höhen- und Horizontalmaxima stützen sich nur auf Zusammenfassungen, weil die
  Roh-CSVs gitignoriert sind. Auch `a16_crosscheck.py` rechnet nicht aus Rohsamples nach.
- **P3:** Mehrere kleinere Punkte:
  - Der A16-Befundtext in r1/report.json ist veraltet.
  - `applicable-evidence-check.json` bindet noch die alte derivation-Revision.
  - `terrain_horizontal_m` = 0 gilt per Konstruktion.
  - Der Viewport-Filter für die Bildschirmmaxima steht nicht in Policy oder Stichprobenplan.

## Nicht prüfbar (lokal-only)

- `derivation-view.json`, sowohl die Quelle als auch das Ergebnis
- `error-*.csv`, `horizontal-generalization.csv`
- Quellbindungen und die Topologieblöcke der derivation-view
- 268 Rohquellen
- Captures und Runtime-Dumps
- Ob die Policy vor der Messung entstand (ein gemeinsamer Commit)
- Ob die Reviewerperson tatsächlich unabhängig ist
