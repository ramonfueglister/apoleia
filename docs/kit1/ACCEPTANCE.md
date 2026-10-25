# Kit 1 — spätere Abnahme und Nachweise

**Referenzversion:** `kit1-landscape-v5` / `kit1-rendering-v4` · **Status:** Prüfplan `spezifiziert`,
alle Laufzeitprüfungen `offen`. Diese Datei enthält keine Testergebnisse.

## Prüfprinzip

Jeder Lauf nennt Kit-/Buildrevision, Datensatzversionen, Darstellungsparameter,
Hardware/OS/Auflösung, Startbefehl und Testkonfiguration. Festgehaltene geografische
Prüfpunkte und wiederholbare Kamera-/Zoompfade machen Aufnahmen vergleichbar.
Es werden **reale Laufzeitbilder und numerische Ergebnisse** gemeinsam geprüft.
Ein unabhängiger Prüfagent liest die Probes und betrachtet die Aufnahmen.

Geografische Quellpositionen und stilisierte Darstellungspositionen sind getrennt
zu erfassen. Gemessen wird gegen die dokumentierte Darstellungsabbildung, nicht
gegen eine fälschlich vorausgesetzte Eins-zu-eins-Skalierung. Quellen-, Modell-
und Renderraum werden getrennt gemessen. Kontrollierte Renderabflachung ist Teil
des Zoomprofils; willkürliche Überhöhung oder verschobene Quellgeografie sind es nicht.

## Abnahmematrix

| ID | Anforderung | Reproduzierbarer Nachweis / Beurteilung |
|---|---|---|
| A01 | Startbare erkundbare Anwendung | Dokumentierter Start auf tatsächlicher Testumgebung; Verschieben und Zoom durch reale Eingabe und Prüffahrt; keine bloße Bildserie |
| A02 | Gesamte Projektregion statt Regionaldemo | Gesamtübersicht, gebundenes region.json und coverage.json mit regionalem Bezugsraum, Land-/Ozeandomänen, Quellen-/Mappingrevision, Aggregationsbelegen, NoData-Behandlung sowie Kartenrändern/Küsten/Tile-Nähten; zusätzlich diverse geografische Prüfpunkte. A02 referenziert Coverage und Region; Reichsrahmen 117, gesamtes Mittelmeer sowie England+nördlicher Puffer müssen einzeln belegt sein |
| A03 | Gebundener flach-zu-Diorama Übergang | Flache 2D-Fernkarte, isometrischer räumlicher Nahendpunkt und beobachtete Zwischenzustände mit Kamera-/Projektions-/Reliefprofil belegen; keine freie Rotation oder manuell getrennten Ansichten |
| A04 | Stufenlos Gesamtübersicht → nah → Gesamtübersicht | Ununterbrochene Laufzeitaufnahme und Kamera-/Zoomverlauf; keine Umschaltung auf getrennte Welt-/Regional-/Stadtszenen oder andere Darstellungsmodi, keine Sprünge oder leeren Zwischenzustände |
| A05 | Gemeinsame Geografie | Identische Referenzpunkte über Zoomstufen und Hin-/Rückfahrt verfolgen; Quellenkoordinaten, Darstellungsabbildung und projizierte Lage in demselben gebundenen Kamera-/Viewport-/Transformzustand vergleichen; Fixture-Wegpunkte einschließlich Pan und Rückkehr tatsächlich nachweisen. Küsten, Flüsse und Relief behalten Zusammenhang |
| A06 | Verkleinerte datenbasierte Modellwelt | Gemeinsame dokumentierte Längen-/Höhenskalierung und getrennte Rendertransformation; keine willkürliche Überhöhung/Distanzverkürzung. Projektionsverzerrung quantifizieren. 500 m bleibt Arbeitswert |
| A07 | Nutzbare Nahansicht | Gelände/Wasser und einzelne stilisierte Bäume sind gut lesbar; Ausschnitt entspricht künftig mehreren Häusern samt Umfeld. Nachweis über Kameraausschnitt und dokumentierte Größenorientierung, ohne Städte als Kit-1-Feature zu bauen |
| A08 | Einheitlicher Stil nach der Nutzer-Primärreferenz | Feste Kameravergleiche gegen references/STYLE_GUIDE.md: zurückhaltende natürliche Palette, stilisierte facettierte Geometrie, ausreichende Landschaftsdetails und lesbare Waldgruppen; nicht fotorealistisch, nicht übermäßig bunt oder extrem low-poly/voxelartig/klotzig. Keine Terrain-Detailvorgabe aus nachrangigen Bildern ableiten; keine Polygonzahl oder Leistungsfähigkeit aus Stilbildern behaupten |
| A09 | Unauffällige Detailübergänge | Gleichen Zoompfad langsam, schnell sowie hin und zurück aufnehmen; Übergänge, Objektstabilität, Flackern, sichtbares Auftauchen, Risse und Wasser-/Terrainversatz beurteilen; kalten/warmen Cache, erste Material-/LOD-Varianten und spät gestreamte Kombinationen markieren und Pipeline-Erstellungen mit max/p95/p99-Framezeiten korrelieren |
| A10 | Nur natürliche Landschaft, keine GUI | Laufzeitbilder und Datenebeneninventar prüfen: keine heutigen/antiken Städte, Straßen, Gebäude, politischen Grenzen/Gebietsfarben oder eingebrannten entsprechenden Kartentexturen; kultivierte Felder, Plantagen und verwaltete Flächen anhand dokumentierter Klassenbehandlung maskieren/abstrahieren; auch danach keine sichtbaren Feldmuster, Plantagenreihen, Zäune oder Bewirtschaftungsstrukturen. A10 prüft den natürlichen sichtbaren Endzustand ohne GUI, Raster, Tile-Highlights, Themenfarben oder Modusbedienung |
| A11 | Fester Darstellungszustand | Sommer-/Lichtparameter und Vergleichsaufnahmen: keine Zeit-/Jahreszeitenwechsel; regional unterscheidbare Landschaften statt global identischer mediterraner Vegetation |
| A12 | Flüssigkeit auf Zielklasse messbar | Framezeiten einschließlich Verteilung/Spitzen, Speicher und Ladeunterbrechungen auf benannter Hardware, Auflösung und identischem Pfad erfassen; Request-Alter, sichtbare Verspätung und byte-/zeitbegrenzte Uploads erfassen sowie Forward+ und Mobile mit gleichem Terrain-/Streaming-/Material-Workload vergleichen; Mac-Befund nicht als Windows-/Linux-/iPad-Nachweis ausgeben; spätere Windows-/Linux-Ziele benötigen eigene gebundene Testumgebungen |
| A13 | Ehrliche geografische Herkunft | Versionierte Daten-/Lizenz-/Transformationsliste, bekannte Auflösungs- und Abdeckungslücken sowie gesonderte historische Korrekturliste; keine unbelegte 180er-Genauigkeit |
| A14 | Wiederholbarkeit | Gleiche Daten, Parameter und Pfade liefern gleiche geografische Anordnung; Abweichungen erklären. Keine zufällig neu angeordnete Landschaft beim erneuten Besuch |

| A15 | Unsichtbare quadratische Tile-Grundlage | Versionierte logische Rasterdefinition, kanonische IDs/Indizes und interne Runtimeprobes über unterschiedliche Zoomzustände, Pan/Rückkehr sowie Kartenränder/Küsten/Tile-Nähte. Quadratische logische Zellmaße, keine Bildschirmquadrat- oder physische Flächengleichheitsforderung. Kein sichtbares Raster, keine Tile-Auswahl oder zusätzliche Ansicht erforderlich/erlaubt; A15 referenziert tiles-Evidence |

## Prüfkonfiguration vor späterer Umsetzung konkretisieren

Noch offen sind Referenzhardware, Bildauflösung, Mindestleistung, zulässige
Framezeit-/Ladespitzen, Speicherbudget sowie numerische Fehlertoleranzen für
Darstellungs-/Zoomstabilität. Der spätere Ausführer legt sie begründet fest und
kennzeichnet sie als technische Testentscheidung. Er darf sie nicht nach einem
schlechten Messergebnis stillschweigend lockern oder als Nutzerentscheidung ausgeben.
Ohne definierte Schwelle und Messung bleibt die entsprechende quantitative
Abnahme `offen`, auch wenn eine Aufnahme subjektiv flüssig wirkt.

[`RENDERING.md`](operations/RENDERING.md) schlägt für den ersten Mac-Prototyp
60 Hz bei 1920×1080 mit p95 ≤16,7 ms und p99 ≤33,3 ms sowie null sichtbare
Terrainlöcher auf der Prüftour vor. Diese Arbeitswerte sind `offen` bis Gerät,
OS, Build, thermischer Zustand und Szenario gebunden und tatsächlich gemessen;
sie sind keine Nutzerentscheidung und keine Zusage für iPad, Windows oder Linux. Zielbudgets ersetzen
keine Rohtelemetrie oder getrennte Qualitäts-/Speicherabnahme.

Die geografische Prüfauswahl muss verschiedene Landschaftsformen und Teilregionen
abdecken. Rom/Tiber/Ostia/Tibur kann ein gut nachvollziehbarer Konsistenzfall sein,
belegt aber weder die gesamte Projektregion noch die historische Landschaft von 180 n. Chr.
Eine Stichprobe ist als solche auszuweisen; Datenabdeckung und Anwendungspfad
müssen zusätzlich für das ganze Projektgebiet nachvollziehbar sein.

Für jeden Lauf mindestens erfassen: Anforderungs-ID, Revisionen, Ort/Quelle,
Kamera-/Darstellungsparameter, erwartetes Verhalten, Beobachtung/Messwert,
Bild-/Aufnahmepfad, Status und begründeter Befund. Maschinenlesbare Formate liegen unter `schemas/`, ausfüllbare Laufvorlagen unter
`templates/`. [Prüfablauf](operations/VERIFY_CAPTURE.md) und
[Adaptervertrag](operations/ADAPTER.md) sind vorbereitet; der Runtimeadapter und
die produktive Datenpipeline werden erst im späteren Produktauftrag implementiert.

## Abschluss

Jede Anforderung erhält einen tatsächlichen Befund, nicht nur ein Häkchen. Offene
Punkte bleiben sichtbar. Reale Zoomaufnahme und regionale Gesamtübersicht müssen aus
demselben geprüften Build stammen. Eine unabhängige technische Prüfung und eine
spätere Nutzerbewertung des Stils sind getrennt zu dokumentieren. Kein Agent
erklärt fehlende Nutzerbewertung eigenmächtig für erteilt.

Die einzige Ansicht zeigt natürliche Landschaftsfarben. Es gibt keine GUI,
Overlays für Raster/Themen/Tile-Auswahl, Menüs, Panels, Legenden oder Hilfetexte.
Pan/Zoom werden direkt bedient und extern dokumentiert. Die früher diskutierten
drei Darstellungsweisen sind spätere Ziele und keine aktuelle Abnahme.

## A16 — datenbasierte Ableitung, Fehlerbudgets und Feature-Schutz

A16 ist die neue Geoableitungsabnahme, **kein Darstellungsmodus**. Sie verknüpft
`derivation`-Evidence mit der vor Messung versionierten `geodata_policy.json`.
Erforderlich: Quellqualität/CRS/Höhendatum, Quell-/Modell-/Rendertransformation,
Skalenfaktor, Projektionsverzerrung, pro Generalisierungsniveau und Gültigkeitsraum
gebundene metrische Budgets, Rohwerte und Stichprobenplan. Gemessen werden Höhen-,
horizontale Gelände- und Küstenabweichung im Quellraum (Meter), Bildschirmfehler
und Übergangsresiduen (Pixel) sowie Projektionsmaßstabsabweichung (Verhältnis).

Der Kitprüfer berechnet **Stichprobenmaxima**, keine globale theoretische Schranke.
RMS oder Algorithmuskosten ersetzen diese Werte nicht. Untersuchte/ungeprüfte
Bereiche und Quelleigenfehler offenlegen. Für geschützte Küsten, Inseln,
Flussnetze, Kämme und Tile-Nähte sind unerwartete Änderungen zu melden;
beabsichtigte Detailauslassungen brauchen Quellen- und Regelbezug. Kein fehlender
Wert darf als Nullfehler erscheinen. Echte vollständige Zoomaufnahme und
unabhängige Daten-/Bildprüfung bleiben erforderlich: eine Messdatei beweist weder
Herkunftswahrheit noch den visuellen Übergang allein.

## Spätere Systemgrenzen-Abnahme (außerhalb der Kit-1-Laufmatrix)

Vor einer späteren Kopplung mit Grafik ist ein headlesser Rust-Smoke-Lauf ohne
Godot, Fenster oder Grafik-/Render-API erforderlich: validierte Commands
einreichen, Simulationsticks unabhängig von Frames ausführen und versionierte
Zustände/Snapshots ausgeben. Ein Boundary-Test prüft Snapshot-Unveränderlichkeit,
begrenztes Handoff mit neuestem vollständigem gültigem Stand, Delta-Lücken samt
Vollsynchronisierung und Simulationsfortschritt unter absichtlich langsamem
Renderer-/IO-/GPU-Konsumenten. Darstellungszustand darf keine kanonische
Wirtschafts-/Weltwahrheit schreiben. Diese künftige Abnahme ist nicht Teil der
Kit-1-Berichtsmatrix A01–A16; sie behauptet keine implementierten Tests oder
Leistungswerte.
