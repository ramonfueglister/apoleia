# Datenreport-Errata release-v2 — Übergabe

Status: implementiert, eigene Offline-Nachrechnung strukturell validiert; unabhängige Gesamtentscheidung steht im gebundenen `evidence/independent-review-snapshot.md` (Snapshot von `independent-review/FINAL_REVIEW.md`). Keine Quellen-, Policy-, Produkt-, App-, Runtime- oder Configdatei geändert. Historische v1-Ausgaben bleiben bytegleich.

## Tatsächliche Eingaben und Anwendung

Runtime: `evidence/runtime/release-v2-mobile-normal/runtime.json`, SHA256 `b89c11e0621012e6202dd5abc68af597cfce99affd3f1a27a6b7600717afeaa8`; Renderer `32692e62a00683419f562793b506e7199f871e782cc2ecf7dc07afc7f34d97a5`. Native Quellenrevision landscape-v3, Manifest `edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a`. Aktuelle unabhängige `release-v2-lod-ridge.json`/CSV sind hashgebunden und gegen die gleiche Runtime geprüft. Kein Umhängen alter 59a926-Rohsamples.

Die vorab fixierte `policy-application-v1.json` ist bytegleich übernommen (SHA `e4f66e47c36a608e30b8d39584e4cb83702a7a07537d5da6202dcb78208b0e56`). Pixelbudgets unverändert 2px/1px, gesamte Geografie unverändert. Zwölf Scope-Aliase betreffen dieselbe region-v1-Maske und dieselben Originalsamples/Samplingpläne. Vier Kombinationen sind explizit NA: screen/transition für die tatsächlich nicht gerenderten Offline-Ausgaben overview/canonical. Detaildaten werden für alle beobachteten Render-LOD 1–14 verwendet. Keine verdreifachten Runtimewerte, keine Nullersatzwerte. Der originale Kitchecker kann NA nicht darstellen und darf weiterhin die entsprechend begrenzte Vertragslücke melden.

## Neu berechnete, begrenzte Belege

- 8694 Ankerproben, davon 2087 sichtbar: Source-Float32-Raster direkt per mmap und unabhängige skalare Kameraprojektion, Screenmaximum 0.6560332070186663px. Der separate Reviewerwert 0.6559894858261045px bleibt als andere numerische Methode erhalten.
- 5609 aufeinanderfolgende sichtbare Bewegungsproben: legitime Kamerabewegung abgezogen, Maximum 0.06846778276470257px. Reviewer separat 0.06846767644383916px. Tatsächliche Camera3D-/aktiveMesh-CPUprobes, keine GPU-Readbacks oder Framebuffermerkmalsuche.
- 26 tatsächliche LOD-Inventare, 57617 sichtbare Randvertex-/Midpointqueries ohne Skirts, 1131 unterschiedliche beobachtete Patch-ID-Nachbarpaare, Maximum 0px. Das ist kein globaler Rissfreiheitsnachweis und keine vollständige Prüfung aller logischen 1000m-Tilekanten.
- Fünf positive Original-Ridgeanker: 1105 sichtbare Proben, max 0.28388363432610986px. Marineanker protected-ridge-4 ausdrücklich ausgeschlossen und im Original erhalten. Zusätzliche vorab ausgewählte Gebirgspositivkontrolle ist separat über ridge-positive-review.json, REGRESSION_DELTA.md und den finalen Reviewerbericht gebunden: eigene Rendererrevision 06d973…, kein heimliches Zusammenlegen mit den aktuellen Laufzahlen. Der Reviewer dokumentiert die reine verlustfreie Bytezugriffsänderung zur finalen Revision. Kein globales Kammnetz behauptet.
- Coverage-/Landcoverformulierungen beziehen sich jetzt auf den finalen unabhängigen Review im dort genannten Regional-, Bild- und Inventarumfang. Nutzerstilbewertung bleibt separat.

Beide Views bestehen unveränderte Kit-Schemavalidierung. Vierzehn anwendbare Metriken liegen innerhalb unveränderter Originalbudgets; vier NA bleiben offen als Toolvertragsgrenze. Dies ist keine neue unabhängige Abnahme durch den Datenowner.

## Einbindung und Reproduktion

Arbeitsverzeichnis `/Users/ramonfuglister/Coding/vic3-clone`:

```sh
sh runs/kit1-landscape-v5-2026-10-25/data-report-errata/release-v2/reproduce.sh
```

Nur Python-Standardbibliothek; kein Renderer, keine Rasteraufbereitung, keine Downloads. Parametrisierter Converter `tools/data_report_errata.py`, Eingabepfade und erwartete Runtime-/Rendererhashes stehen im Script. `errata-binding.json` hält Originalhashes, Operations-Compositerevision, Scopeänderungen und Inputauswahl. `applicable-evidence-check.json.outputs` enthält den endgültigen SHA-Satz. Operations kann ausschließlich die neuen Views/Belege in den aktuellen Reportadapter übernehmen; eingefrorene Originalmanifeste bleiben unverändert. Nach Operationsbindung muss dessen eigener Reportcheck entscheiden, die bekannte NA-Vertragslücke bleibt transparent.
