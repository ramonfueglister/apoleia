# Unabhängige Vorprüfung — Kit 1

Stand: 25.10.2026, Referenz `kit1-landscape-v5` / `kit1-ops-v5` / `kit1-rendering-v4`.
Prüfer: `/root/independent_review`. Basis-HEAD `01c48ad3635856233349adec9a583bd97241b440`.
Produktdateien sind uncommittierte, gleichzeitig von ihren Ownern bearbeitete Arbeitsstände.
Diese Vorprüfung bestätigt keine Produktabnahme und startet keine Anwendungssitzung.

AGENTS, START_PROMPT vollständig, README, decisions, TASK, WORKFLOW, ACCEPTANCE,
STYLE_GUIDE, REGION, TILES, VERIFY_CAPTURE, ADAPTER, GENERALIZATION, DATA_PIPELINE
und RENDERING gelesen. Nutzer-Primärreferenz, ergänzende Fernprobe und alle sechs
offiziellen Screenshotreferenzen tatsächlich geöffnet. Die Primärreferenz zeigt
zusammenhängende facettierte Naturformen, mäßige Farben, natürliche Waldgruppen
und lesbare Ufer; sie bleibt maßgeblich. Kein Referenzbild ist Produktbeleg.

## Reale unabhängige Datenprüfung

`reference_check.py` importiert keinerlei Produktpipeline-Code. Ausführung:

```sh
PROJ_DATA=/opt/homebrew/share/proj /opt/homebrew/bin/python3.14 runs/kit1-landscape-v5-2026-10-25/independent-review/reference_check.py > runs/kit1-landscape-v5-2026-10-25/independent-review/reference-check.json
```

Ergebnis in `reference-check.json`: Die tatsächlichen drei Referenzdateihashes
passen zur Regionbindung. Ihre tatsächlichen Extents passen exakt zu den
Metadaten. 112 Reichsreferenzfeatures, 11 Mittelmeer-Scopefeatures und das
Englandfeature liegen vollständig innerhalb der gültigen zusammenhängenden
Rechteckmaske. England-Nordgrenze 55.81116499966504°, Kontext bis 58°:
2.1888350003349615°; entspricht der Bindung. Dies bestätigt Geometriecontainment
dieser ausgewählten Quellen, keine historische Grenzwahrheit oder vollständige
gerenderte Abdeckung. Eine AWMC-Quellgeometrie ist ungültig (OGR meldet
Ring-Selbstschnitt bei 29.50792/40.74137); Original unverändert lassen, Quellproblem
im Qualitätsbeleg nennen und bei späteren Topologieoperationen behandeln.

## Konkrete frühe Befunde

Die folgenden Befunde wurden den zuständigen Ownern und dem Hauptagenten gemeldet.
Bereits gemeldete Korrekturen sind erst nach explizitem eingefrorenem Handoff
unabhängig neu zu prüfen.

| ID | Befund und Wirkung | Stand |
|---|---|---|
| R01 | `_tile_id` in geprüftem Renderer verwendete 0.25°/`geo-v1`; der Datenvertrag definiert projizierte 1000-m-Quadrate/`eqc41-km-v1`. A15 konnte damit keine kanonische Tileidentität nachweisen. | Grafikowner meldet behoben, unabhängiger Retest offen. |
| R02 | Renderer benutzte Boundsmittelpunkt, Datenmapping Ursprung 19°E/41°N. Die Renderdokumentation bezeichnete dies als reine Translation, daher kein Beleg für verfälschte relative Geografie; die gehashte Transformationsbindung musste dennoch eindeutig werden. | Owner meldet gemeinsame Ursprungsbindung korrigiert; Retest offen. |
| R03 | `expected_projection.py` verlangte `sample['target_height_model']`, `_record_sample` exportierte das Feld nicht. Sollprojektion war mit echten Samples nicht ausführbar. | Owner meldet Export ergänzt; Retest offen. |
| R04 | `_height` und Terrainshader verwendeten `max(height,0)` auch für Land. Reale negative Landdepressionen werden angehoben, obwohl der Vertrag nur Ozeanoberfläche/zoomgebundene Abflachung erklärt. Offline-Rasterfehler messen diese Renderänderung nicht. | Grafikowner gemeldet, offen. |
| R05 | Datenmanifest enthielt `rivers_path`, Renderer lud/zeichnete die erhaltenen 168 Flussfeatures nicht. Vektorerhalt auf Platte belegt den sichtbaren Gewässer-/gemeinsamen Geografiepfad nicht. | Flussrenderer laut Hauptagent in Arbeit; offen. |
| R06 | `_sample_index` benutzte `int(u*(width-1))`, der Shader sampelt Pixelzentrum-Texturen. Baumfreigabe kann gegenüber dem sichtbaren Landcover fast eine Rasterzelle versetzt sein. | Grafikowner gemeldet, offen. |
| R07 | Datenmessung verglich bilinear resampelte Höhenraster; tatsächliche Patchtriangeln/Morphflächen wurden dadurch nicht gemessen. `horizontal_terrain.sample_max_m` war eine Konstante ohne Rohdaten. Küsten-/Schutz-/Topologienachweise und Runtime-Pixelresiduen fehlten. | Datenowner erstellt echte Roundtrip-/Küsten-/Topologierohwerte; Rastermessung bleibt ausdrücklich offline. A16 offen. |
| R08 | `detail-rules` nannte nur overview/canonical, Policy und tatsächliche Ausgaben zusätzlich detail; policy-decision nannte andere Detaildimensionen als das Manifest. | Datenowner korrigiert vor Freeze; offen. |
| R09 | Das Manifest hashte nur drei Basispayloads; tatsächlich geladene Detailhöhe/Detailwasser waren dort nicht gehasht. Runtime prüfte keine Payloadhashes, nur Dimensionen. Gleiche Dimensionen trotz manipuliertem Payload bleiben unerkannt. | Vor Freeze vollständiges Payloadinventar und Integritäts-/Fehlerpfad erforderlich; offen. |

Die erste Datenausgabe `landscape-v1` wurde vom Datenowner ausdrücklich wegen
GDAL-Auto-Vertikaltransformation verworfen. Die ursprünglichen Höhenfehlermesswerte
sind daher kein Beleg für die angekündigte `v2`-Ausgabe. Kein v1-Wert wird auf v2
übertragen. Die neue Ausgabe mit `-novshift` ist nach ihrer Übergabe zu prüfen.

Frühe Hashbindung der befundtragenden Arbeitsdateien:

| Datei | SHA-256 |
|---|---|
| app/scripts/landscape.gd | a59e5e894b2caa68ac73df98b966453355e90724faf1efb8628ab25e647b4c25 |
| app/scripts/expected_projection.py | 59b1c101b8be605243e84abc5cb72ebae9c6f2d681e0c0cbef8764d16b395080 |
| app/shaders/terrain.gdshader | d11f46f585dc6899cc8de9cc3330d97d9f0f64e92fe9686228ddf6ed8343331d |
| data/geodata_policy.json | 19be099d04d5b6e5520b94a84581ed79e729e21c56688ee1e378c5e543ad7dd1 |
| data/tile-grid.json | 8c2acb50000fea5186f8b2a4a6d2f5c62de00c27dc09bca2465a1e2de3cbc67d |
| data/derived/landscape.json | b8d91341add5d4ffe350b142273aff2995915466353edaef38b9a060dbf89fdc |
| tools/data_build.py | 6c049dad9535d2900f0d693ed8ab5a73e911d8a0a468fee65469b70652642dcc |
| tools/data_measure.py | cfd53d8ed2ae0482d3112f71c526d37626a06d0b3b079e123e1dbdeafdbed737 |

## Für die vollständige unabhängige Abnahme erforderlich

- Eingefrorene Build-/Daten-/Mapping-/Kamera-/Fixture-/Policyhashes und explizite
  Sitzungseigentumsübergabe, vor unabhängiger Runtimebedienung.
- Konkrete bereite Run-Konfiguration samt lokal gebundener vollständiger
  Quellen-/Coverage-/Derivationdateien; Kitchecks bleiben Vertragschecks.
- Echte direkte Pan-/Zoomeingabe, Gesamtüberblick, beobachtete Zwischenzustände,
  Nahansicht, zweite Region und identische Rückkehr; ungeschnittene Fahrt desselben Builds.
- Runtime-Geografieanker mit unabhängiger Sollprojektion und tatsächlichen
  `Camera3D`-Projektionen; Tilefälle Binnenland/Küste/Rand/Naht in mehreren
  Zuständen samt Pan/Rückkehr und zeitlich neuen Rückkehrprobes.
- Langsame/schnelle Hin-/Rückfahrt und Kalt-/Warmcache mit Bildprüfung auf
  Terrainlöcher, LOD-Pop-ins, Vegetationsstabilität und Wasser-/Terrainversatz.
- Vergleich Mobile/Forward+ bei gleichem Workload und Viewport. Frame-p95/p99/max,
  Prozess-RAM (Godot `OS.get_static_memory_usage` allein ist kein Prozess-RSS),
  GPU-Messbarkeit, Pipeline-/IO-/Uploadkorrelation bzw. explizite Messlücke.
- A16 Rohwerte gegen vorab gebundene Budgets für alle tatsächlich produzierten
  Niveaus sowie nichtleere Schutzinventare. Keine Rasterresamplingmessung als
  Beleg für die komplette tatsächlich gerenderte Morphgeometrie ausgeben.

## A01–A16 zum Zeitpunkt dieser Vorprüfung

Alle Produktabnahmen bleiben `offen`, solange eingefrorene Runtimebelege fehlen.
A02 besitzt zusätzlich den oben unabhängig geprüften Referenzcontainment-Teilbeleg;
A13 besitzt reale Quellenmanifeste, deren finale Revision/Hashes noch einfrieren
müssen. A03–A12 und A14–A16 sind durch Quellcode/Kitchecks allein nicht validiert.
A08 technische Stilprüfung und spätere Nutzerbewertung bleiben getrennt.
