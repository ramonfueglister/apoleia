# A16 — formale Werkzeugabnahme (NA-Vertrag)

Referenz `kit1-landscape-v5` / `kit1-ops-v5`, Lauf `runs/kit1-landscape-v5-2026-10-25`,
Datenrevision `data-report-errata-release-v2`. Stand 26.10.2026.
Rohausgaben: [`a16-tool-acceptance.json`](a16-tool-acceptance.json), Nachrechnung:
[`a16_crosscheck.py`](a16_crosscheck.py).

**Status:** Werkzeugvertrag `implementiert` und durch Tests `validiert`.
Formale A16-Toolabnahme am echten Beleg **`offen`**: Der Kitchecker konnte in
diesem Checkout nicht über `derivation-view.json` laufen, weil die Datei (wie
Rohquellen und Runtime-Dumps) per `.gitignore` lokal-only ist. Keine A16-Freigabe.

## 1. Werkzeuglücke und Änderung

Bisher verlangte `derivation_check` für **jedes** Policy-Niveau alle sechs Metriken
als Zahlenwerte; ein ehrliches „nicht anwendbar“ war nicht darstellbar. Die vier
nicht gerenderten Offline-Kombinationen (overview/canonical × Bildschirm-/
Übergangsmetrik) erzeugten deshalb zwangsläufig `derivation level/metric coverage
incomplete`.

Additive Ergänzung (kein Versionssprung, bestehende Dateien bleiben gültig):

- `derivation.not_applicable[]` (optional): `level_id`, `metric`,
  `status: "not_applicable"`, Pflichtfeld `reason` und Pflicht-Regelbezug `rule`
  (`artifact_path` + `sha256`, hashgeprüft).
- Nur Renderraum-Metriken (`screen_error_px`, `transition_residual_px`) dürfen NA
  sein; Quellraum-/Projektionsmetriken bleiben stets messpflichtig.
- Gemessen ∪ NA muss exakt alle Niveau-/Metrikpaare der Policy abdecken; Überlappung,
  Duplikate und unbekannte Niveaus blockieren. Jede Metrik braucht mindestens ein
  gemessenes Niveau (keine vollständige Metrikbefreiung).
- NA erzeugt keinen Zahlenwert und keinen Pass; ohne `not_applicable` verhält sich
  der Prüfer unverändert.

Tests: 3 neue Fälle in `tests/test_kit.py`; 46 Tests, davon 42 OK. Die 4 ERROR sind
vorbestehend und A16-fremd (`references/screenshots/vic3-*.jpg` fehlen im Repository;
auf unveränderter Basis identisch).

## 2. Reviewer-Bindung

Kein Werkzeug-/Datenfehler mehr: `report.json` bindet `producer`, `reviewer`
(`independent_review`) und `review_ref` (`independent-review/FINAL_REVIEW.md`,
vorhanden, SHA `4aa83050…` stimmt). `report-check` meldet hier keine
Reviewer-Issues. Die Blockade-Aussage in `EVIDENCE_INDEX.json`/`ACCEPTANCE_DRAFT.md`
stammt aus dem Stand vor 17:02Z (siehe `PROGRESS.md`) und ist veraltet; eingefrorene
Laufdateien wurden nicht verändert. Der Checker prüft nur Ungleichheit der Namen,
nicht die tatsächliche Unabhängigkeit; die Reviewerin/der Reviewer selbst muss den
A16-Status im Bericht setzen. Das bleibt eine offene Personenentscheidung.

## 3. Ergebnis pro Kombination

Quelle: hashgeprüfte `applicable-evidence-check.json` (gebunden in `report.json`)
gegen die vorab gebundene Lauf-Policy `geodata_policy.json` (SHA `289fdb60…`).
Es sind **gemeldete Stichprobenmaxima**, nicht durch den Kitchecker aus Rohsamples
nachgerechnet.

| Niveau | Metrik | Status | Wert | Budget |
|---|---|---|---|---|
| overview | terrain_vertical_m | PASS | 1334.149 m | 2500 m |
| canonical | terrain_vertical_m | PASS | 1065.568 m | 1800 m |
| detail | terrain_vertical_m | PASS | 1e-9 m | 1000 m |
| overview | terrain_horizontal_m | PASS | 0.0 m | 0 m |
| canonical | terrain_horizontal_m | PASS | 0.0 m | 0 m |
| detail | terrain_horizontal_m | PASS | 0.0 m | 0 m |
| overview | coastline_displacement_m | PASS | 2040.133 m | 6000 m |
| canonical | coastline_displacement_m | PASS | 2797.253 m | 6000 m |
| detail | coastline_displacement_m | PASS | 2039.410 m | 6000 m |
| overview | projection_scale_error_ratio | PASS | 0.4242 | 0.5 |
| canonical | projection_scale_error_ratio | PASS | 0.4242 | 0.5 |
| detail | projection_scale_error_ratio | PASS | 0.4242 | 0.5 |
| detail | screen_error_px | PASS | 0.656 px | 2 px |
| detail | transition_residual_px | PASS | 0.0685 px | 1 px |
| overview | screen_error_px | NA | — | — |
| overview | transition_residual_px | NA | — | — |
| canonical | screen_error_px | NA | — | — |
| canonical | transition_residual_px | NA | — | — |

NA-Begründung: Offline-Niveau in keinem integritätsgültigen Lauf gerendert
(`rendered_in_valid_runs: false`). Regel: `data-report-errata/release-v2/policy-application-v1.json`
(SHA `e4f66e47…`, vor dem Endlauf fixiert); identisch mit `errata-binding.json.not_applicable`.
Abdeckung 14 gemessen + 4 NA = 18 = 3 Niveaus × 6 Metriken, ohne Überlappung;
jede Metrik hat ein gemessenes Niveau. Alle NA-Fälle erfüllen die neuen Checkerregeln.

Einschränkung: `terrain_horizontal_m` mit Budget 0 m — laut
[Datenübergabe](../../product-data/HANDOFF.md) sind numerische Roundtripreste
~1e-9 m nicht als exakt 0 zertifizierbar; der Wert 0.0 stammt aus der Zusammenfassung.

## 4. Offen für die formale Abnahme

1. Auf dem Owner-Mac (mit lokal-only Dateien) `derivation-view.json` als neue
   Revision um die vier `not_applicable`-Einträge mit obigem `rule`-Bezug ergänzen,
   Hash in `report.json` neu binden und `python3 docs/kit1/tools/kit.py report-check
   runs/kit1-landscape-v5-2026-10-25` ausführen. Erwartet wird dann kein
   `derivation level/metric coverage incomplete` mehr; das ist nicht verifiziert.
2. Der A16-Status in `report.json` bleibt `offen`, bis die unabhängige Prüfung ihn
   setzt; kein Agent setzt ihn eigenmächtig.
3. Runtime-, Bild- und Topologieprüfung sind nicht Teil dieser Werkzeugabnahme.
