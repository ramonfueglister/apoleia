# Reproduzierbarer Prüf- und Aufnahmeablauf

Referenz `kit1-landscape-v5`. Ergänzt A01–A16 aus ACCEPTANCE um konkrete Formate.

## Vor der ersten echten Prüffahrt

- Neuen Laufordner mit `tools/kit.py init-run <neuer-ordner>` anlegen. Vorlage
  enthält keine Messwerte; alle Abnahmen stehen `offen`.
- Konfig, Quellenmanifest und Fixture in den Laufordner übernehmen/konkretisieren.
  Build-/Datensatz-/Mapping-/Kitrevision, OS/GPU/RAM/Auflösung, Seed und
  Capturemethode angeben. `preflight <config>` muss für die gewählte Bindung
  bereit sein, bevor ein tatsächlicher Lauf so bezeichnet wird.
- Technische Leistungs-/Geometrietoleranzen vor dem Lauf in der versionierten
  Konfig festlegen. Beispiele enthalten **keine vorgeschlagenen Leistungsziele**.
- Prüfauswahl: mehrere Kontinente/Breiten, Küste, Binnenland, Gebirge, Wald,
  trockene Landschaft, Kartenrand/Küstenübergang/Kachelrand. Eine Fixture enthält
  konkret gebundene Punkte; bloße Regionennamen/erfundene Koordinaten reichen nicht.

## Lauf in einer gebundenen Anwendung

1. Build starten, Projekt-/Revisionsidentität verifizieren; Laufkennung speichern.
2. Gesamtübersicht aufnehmen; regionales Dateninventar mit bekannten Lücken sichern.
3. Feste Fixture abfahren: Gesamtübersicht → Region → Nah → Gesamtübersicht; langsam/schnell,
   vorwärts/rückwärts, erneuter Besuch, wechselnde Regionen. Übergänge kontinuierlich
   aufzeichnen, keine Schnitte über Ladefehler. Eine Bildreihe ersetzt das Video nicht.
4. Rohtelemetrie und feste Standbilder aus demselben Build exportieren.
   Quellfixpunkte und erwartete Positionen aus dem versionierten Mapping gegen
   tatsächlich projizierte Positionen vergleichen. Kameraausrichtung mitmessen.
5. Framezeiten/Spitzen/Speicher und Ladepausen nach dokumentiertem Sampling/Warmup
   auswerten. Messungen mit Einheiten und vorher festgelegten Grenzwerten zuordnen.
6. Alle Dateien im Laufordner halten und SHA-256 in `report.json` erfassen.
   Nachträgliche Konvertierungen erhalten neue Hashes, Originalbezug und Rezept;
   keine Aufnahme wiederholt verlustbehaftet transkodieren oder Rohbelege löschen.
7. `python3 tools/kit.py validate telemetry <lauf>/telemetry.json` und
   `python3 tools/kit.py report-check <lauf>` ausführen. Exit 0 bedeutet nur
   strukturell vollständige belegte Reportangaben, kein automatisches visuelles
   oder wissenschaftliches Wahrheitsurteil.
8. Unabhängiger Agent öffnet tatsächliche Bilder/Video und prüft Rohdaten gegen
   A01–A16. Ersteller und Prüfer benennen, Defekte reproduzierbar erfassen.
   'valide JSON' allein darf niemals die Anwendung als abgenommen markieren.

## Ergebnisformat

`schemas/report.schema.json` bindet alle A01–A16 an Status/Befund/Evidence-IDs.
`evidence` referenziert echte relative Dateien mit Hashes, Art und Herkunft
(`runtime`, `data` oder `synthetic`). Synthetische Beispiele sind für Formatchecks,
nie Runtimeabnahme. `report-check` verweigert vollständige Produktnachweise bei
synthetischer Herkunft, fehlenden Checks, nicht validierten Punkten, fehlender
unabhängiger Review oder fehlenden Referenz-/Dateinachweisen.

Roh- und Ergebniswerte werden nicht aus Konzeptbildern abgeleitet. Eine projektweite
Abdeckungsbehauptung braucht Dateninventar plus diverse Stichproben; eine einzelne
Tiberfahrt beweist nicht das ganze Projektgebiet. Noch nicht prüfbare Punkte bleiben `offen`.

## Pflichtbindungen des vollständigen Pfads

- Fixture und Telemetrie verwenden `kit1-ops-v5`. Geografisches Kameraziel,
  Viewport und gehashter Mapping-/Projektionszustand gehören zu jedem Sample.
  Alle Wegpunkte einschließlich Pan und Rückkehr müssen mit ihrer ID tatsächlich
  erscheinen; gleiches Start-/Endzoom allein besteht den Vertrag nicht.
- `coverage.json` separat validieren und als Evidence-Art `coverage` mit Hash in
  den Report aufnehmen. A02 referenziert diese und die gebundene region-Evidence ausdrücklich. Bericht
  und Coverage teilen Run-, Quellen- und Mappingrevision.
- Abdeckung des gesamten Projektgebiets ist eine belegte Zusammenfassung über Land und Ozean sowie
  Kartenränder/Küsten/Tile-Nähte, keine Forderung, jeder einzelne Eingabelayer müsse überall
  Daten enthalten. Aggregationsmethode und Belegdateien werden mitgehasht.
- Offene NoData-Fälle, fehlende Domänen-/Randprüfungen oder ungeklärte kultivierte
  Landcoverklassen blockieren den vollständigen Evidenzvertrag. Maskierung und
  neutrale Abstraktion müssen erklärt sein, nicht als antike Renaturierung gelten.

```sh
python3 tools/kit.py validate coverage <lauf>/coverage.json
```

Die synthetische Coveragevorlage enthält bewusst offene Werte und kann keine
Abdeckung bestätigen. Ein Strukturcheck prüft das Dateiformat; `report-check`
prüft erst die Bindungen und Vollständigkeit der abgegebenen Erklärungen/Belege.
Auch ein erfolgreicher Vertrag rechnet keine tatsächliche regionale Geodatenabdeckung nach.

## Zusätzliche interne Tileprobes, keine weitere Ansicht

[TILES](TILES.md) und `fixture.tile_cases` vorbereiten. Interne Datenabfragen für
jeden Quellanker in mindestens zwei Zoomzuständen ausführen, mit tatsächlichem
Kamera-/Viewport-/Transformzustand und kanonischer Tile-ID/Index/Zellmaßen. Die
bestehende Pan-/Rückkehrfahrt bleibt bestehen; Kartenränder/Küsten/Tile-Nähte gesondert
prüfen. Dafür weder Raster noch Tile-Auswahl oder GUI einbauen.

`tiles.json` separat validieren, als Evidence-Art `tiles` mit Herkunft `runtime`
hashen und mit A15 verknüpfen. Die normalen Laufzeitbilder müssen die natürliche
Landschaft **ohne** GUI/Raster/Themen-/Auswahlmarkierungen zeigen. Interne Prüfwerte
stehen in externen Belegen; Hashes ersetzen keine unabhängige Sichtprüfung.

```sh
python3 tools/kit.py validate tiles <lauf>/tiles.json
```

Weiterhin [GENERALIZATION](GENERALIZATION.md) beachten: flache Fernkarte → gebundene räumliche Nahansicht, echte Zwischenzustände und A16-Ableitungsbelege. Keine GUI oder umschaltbaren Modi.

## Gebietsbindung v5

Vor Verarbeitung [REGION](REGION.md) lesen und `config.region_path` binden.
Die tatsächliche Regiondatei gehört gehasht zum Report; A02 verbindet sie mit
Coverage. Fixture und Ableitung referenzieren dieselbe Revision. Umfang ist
Reichsrahmen 117 + gesamter Mittelmeerraum + England/nördlicher Kontext, nicht
die gesamte Erde und nicht nur Europa. Landschaftsreferenz bleibt 180 n. Chr.
