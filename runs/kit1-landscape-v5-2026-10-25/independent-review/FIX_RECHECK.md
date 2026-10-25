# Gezielte unabhängige Nachprüfung V01–V03

25.10.2026, `landscape-v3` unverändert. Keine App-/GPU-Sitzung bedient.
`COAST-SDF-CONTRACT.md`, `sdf-rg8-probe.json`, statischer Integrationsbeleg,
aktueller Terrain-/Flussshader und relevante Hostfunktionen gelesen.

Alle drei angeforderten Originalbilder tatsächlich vollständig geöffnet:

- `artifacts/runtime/lake-tree-regression/frame_000030.png`: exakt früherer
  V01-Kamerazustand. Die vorher im blauen See stehenden Bäume fehlen jetzt;
  Wald bleibt auf dem dargestellten Land. V01 in diesem gezielten Bild behoben.
- `artifacts/runtime/england-coast-regression/frame_000030.png`: frühere
  V02-Region. Die großen achsenparallelen Rastertreppen und gestuften
  Wasserfarbbänder fehlen. Die Kontur folgt nun einer zusammenhängenden
  glatten Quelleableitung. V02 in diesem gezielten Bild behoben.
- `artifacts/runtime/canonical-edge-regression/frame_000030.png`: der frühere
  Wald-Nahzustand. Die zuvor auffällige dünne senkrechte x≈536-Linie fehlt.
  V03 an diesem einzelnen Sichtpunkt behoben; dies ist kein vollständiger
  Beleg aller unterschiedlich detaillierten Nachbarkanten.

**Revisionsgrenze:** Die Lake-/Englandbilder nennen Renderer
`4d051bbca48b1f6b29a04b4ee2f4a4816a9c633d4a004d8a6d279ad7ed4e1aac`
und Terrainshader `38fd918c75b6162e27b5a286175cad5c9b60fa41548efe2ed630a2e1c410ab46`;
sie stammen vor der nachfolgenden RG8-SDF-Integration. Das Edge-Bild nennt
Renderer `d1584122a4da12837f04e069bafbfadecf6914dd68385421f99539927eaf596c`.
Die Bilder werden ausdrücklich nicht als bereits geprüfte finale RG8-GPU-
Aufnahme umetikettiert. Neuer gesamter Build-/Capturebeleg steht noch aus.

Im aktuellen Code sind die Ursachen gezielt behandelt:

- Bäume brauchen weiterhin echte Quelleklasse 10, zusätzlich diskrete
  Detailwasserart 0 und signed Renderwasserabstand kleiner -20 projizierte m.
  Es werden keine Baumstandorte als gemessen ausgegeben und keine Quelldaten
  umgeschrieben.
- Küstenabstand stammt aus unveränderten Quellsegmenten, künstliche regionale
  Clipsegmente sind ausgeschlossen. Source-/Modell-/Renderraum bleiben getrennt.
  RG8-Decoder liest vier Cornerwerte vor Bilinearfilterung; Range, Vorzeichen
  und Sättigung entsprechen dem gesonderten vorab gebundenen Vertrag.
- Patchpositionen werden aus gemeinsamen binären UV-Grenzen vor gemeinsamer
  Welttransformation erzeugt. Das beseitigt unterschiedliche schrittweise
  Weltkoordinatenadditionen an derselben Kante. Neue Paar-/Morphprobes und
  Bildfahrt bleiben für eine regionale Nahtabnahme notwendig.

Der Datenowner hat die neue SDF-Repräsentation unabhängig direkt gegen
46985 Quellsegmente geprüft: 962 Texelsamples ohne Codeabweichung, maximale
Texelabweichung 0.06248015 projizierte m, 585 gefundene Nullkurven mit
605.91351 m Stichprobenmaximum, fünf geschützte Inselinnenpunkte Land. Für
drei im früheren Englandframe sichtbare Konturpunkte ist ein planarer
Projektionsrest 0.02917341 px gemessen. Diese überprüften Methoden-/Rohbelege
sind keine globale Kleininsel-, Bildschirm- oder GPU-Topologiegarantie.

Aktuelle SDF-Repräsentation:
`ee41a6bd76f835106a64383b577edee142a27b54cdbb90ebf629c61200699e67`,
Policy `d19dde843c7161da718a716e29058f141311e2a41ff6ba56699c1c1bd48a813a`.
Ältere R8-v1-Befunde bleiben als ältere Befunde erhalten. Die bestehende
2-px-A16-/1-px-Transitionsgrenze wurde nicht gelockert.

Die genaue AWMC-Quelldatei-URL und der unveränderte Originalhash sind inzwischen
in `docs/product-data/AWMC-PROVENANCE-ADDENDUM.md` dokumentiert; die frühere
Reproduktionslücke einer bloßen Repository-Tree-URL ist damit behoben.

Für die abschließende A01–A16-Prüfung fehlen weiterhin der neue eingefrorene
Normal-/Forward+-/Capturebestand mit vorab eingefrorener Fixture und Methoden-
Bindung, tatsächliche Naht-/Morph-/Ridgeprobes und die ausdrücklich übergebene
Sitzung für unabhängige direkte Eingabe. Die Arbeitsmatrix bleibt bis dahin
offen, mit den oben präzisierten gezielten Fixbestätigungen.
