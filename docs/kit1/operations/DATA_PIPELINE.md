# Datenprozess: reale Grundlage → stilisierte gemeinsame Projektregion

Referenz `kit1-landscape-v5`. Ausführungsrezept für später; kein Datenbestand
heruntergeladen, kein Anbieter ausgewählt. Zuständig: Daten-Subagent.

0. **Gebiet binden:** [REGION](REGION.md) ausführen; zusammenhängende Kartenmaske,
   Reichsrahmen 117, gesamtes Mittelmeer und England+nördlicher Kontext belegen.
   Alle Prozentwerte beziehen sich auf diese Maske, nicht auf die Welt oder nur
   auf das trockene historische Reichsland.
1. **Inventar:** Für Höhenrelief, Küsten/Gewässer und Landbedeckung Kandidaten
   erfassen: Originalquelle, Version/Datum, globale und regionale Abdeckung,
   Auflösung, CRS/Höhendatum, Nutzungsbedingungen, Format/Größe. In
   `templates/sources.json` führen. Keine Quelle ohne geprüfte Rechte übernehmen.
2. **Auswahl:** Eignung für natürlichen Landschaftslook prüfen. Straßen, Gebäude,
   Beschriftungen, politische Flächen und entsprechende eingebrannte Texturen
   ausschließen. Kultivierte Felder, Plantagen und sonstige verwaltete Flächen
   dürfen nicht als natürliche Vegetation durchgereicht werden. Datensatzklassen
   explizit auf Maskierung, neutrale grafische Abstraktion oder belegt nicht
   vorhandene Klasse abbilden. Auch bei `abstract` gilt als Endzustand: keine
   sichtbaren Feldmuster, Plantagenreihen, Zäune oder sonstigen Bewirtschaftungs-
   und Bebauungsstrukturen; nur vereinfachte natürliche Oberflächen. Unklare/
   unbehandelte Klassen als Lücke führen.
   Quellenklassen, Methode und Unsicherheit in `coverage.landcover_treatments`
   und im Ableitungsprotokoll festhalten. Eine neutrale Abstraktion behauptet
   keine rekonstruierte natürliche Vegetation von 180 n. Chr. Auswahl begründen.
3. **Erwerb im autorisierten Umfang:** Quell-URL, Abrufzeit, exakte Version,
   Originaldateihash und Kosten (nur tatsächlich angefallen) sichern. Abgebrochene
   Downloads über Jobkennung/Dateistatus prüfen; keinen Auftrag blind wiederholen.
4. **Unveränderte Quellen trennen:** Originaldaten und Ableitungen separat halten.
   Transformationsrezept mit Eingangs-/Ausgangshashes, Werkzeugversion, CRS,
   Auflösung, NoData-Regeln, Parametern und Seed protokollieren. Keine Originale
   überschreiben. Verarbeitung an kleinem Ausschnitt prüfen, dann auf das gesamte Projektgebiet anwenden.
5. **Abdeckung:** `coverage.json` gemäß `schemas/coverage.schema.json` liefern.
   Gebundenen regionalen Bezugsraum, Quellenrevision, Aggregationsverfahren und gehashte
   Inventar-/Flächennachweise dokumentieren; Land und Ozean getrennt bilanzieren.
   Jede Domäne benötigt vollständige repräsentierte Abdeckung und null
   **unaufgelöste** NoData-Anteile. Bekannte Lücken samt tatsächlicher Behandlung
   aufführen; bloßes Verschweigen oder Umbenennen in Wasser ist keine Behandlung.
   Nicht jeder Eingabelayer muss das ganze Projektgebiet abdecken: Ozean kann eine dokumentierte
   Wasserflächen-Darstellung verwenden, ohne ungefragte Bathymetriepflicht.
   `reference_components` muss die Reichsreferenz, das gesamte Mittelmeer und
   England+nördlichen Kontext vollständig mit gehashten Belegen abdecken.
   Land braucht passende Höhen-/Landcoverdaten: `role_bindings` verknüpft jede
   Rolle mit tatsächlich so klassifizierten Quellen aus sources.json. Ozean
   braucht die Wasserrolle. Die Abdeckung bindet zusammen alle in der Konfig
   erforderlichen Rollen; reine Wasserquellen belegen kein Landrelief/Landcover.
   Komposite dürfen Ursprungsquellen je Rolle und gemeinsame Ableitungsbelege
   referenzieren. Spezialregionen benennen betroffene Domänen und deren Rollen.
   Kein einzelner Layer muss deshalb überall im Gebiet oder über Meeresflächen vorliegen.
   Zusammensetzung und Domänengrenzen bestimmt das belegte Aggregationsverfahren.
   Regionalen Kartenrand, Küstenübergänge und Tile-Nähte mit Grenzen, Quellen und
   Belegen prüfen; keine weltweite Pol-/Datumsgrenzpflicht.
   Kachelränder, Küsten und unterschiedliche Quelldatendatierungen prüfen.
   Kleine Auflösung wird nicht als gemessenes Nahdetail ausgegeben.
6. **Darstellung:** Eine gemeinsame Quellgeografie mit separater versionierter
   Modell- und Renderabbildung verwenden. Einheitliche Verkleinerung und
   kontrollierte Detailreduktion nach [GENERALIZATION](GENERALIZATION.md),
   keine willkürliche Distanzverkürzung oder Höhenüberhöhung.
   Identität/Topologie, Projektionsverzerrung und Übergänge nachweisen.
   Keine pro Kamera neu generierten Geografien.
7. **Historischer Rückstand:** `historical_corrections` im Quellenmanifest pflegen:
   betroffene Region/Feature, heutiger Befund, mögliche historische Abweichung,
   Beleg, Unsicherheit, Status und spätere Aufgabe. Küsten/Flüsse, Stauseen,
   Kanäle/Landgewinnung sowie Vegetation/Gletscher nach Quellenlage. Keine
   vollständige Rückrekonstruktion im aktuellen Kit behaupten.
8. **Prüfung:** Quell- und Renderfixpunkte anhand ausgewählter Datensätze binden,
   Stichproben mehrerer Landschafts-/Teilregionen plus projektweites Inventar prüfen.
   Quellen-/Lizenz-/Hashnachweise sind Voraussetzung der Datenlieferung, keine
   Aussage über 100-%-Genauigkeit für 180 n. Chr.

Lieferung: ausgefülltes Quellenmanifest, Transformationsjournal, Abdeckungsbericht,
Korrektur-Backlog und reproduzierbare tatsächliche Aufbereitungsbefehle. Konkrete
Werkzeuge/Befehle kommen nach Auswahl in den Adapter; keine Platzhalter als
bereits existierende Tools präsentieren.

## Unsichtbare Tile-Grundlage

Die gemeinsame Geografie erhält eine versionierte quadratische logische
Adressierung. Tilegröße, regionale Rasterräume, Naht-/Kartenrandbehandlung, Ursprung,
Indexachsen und LOD-Aggregation im gehashten Adressierungsvertrag dokumentieren.
Datenkacheln eines Anbieters sind nicht automatisch die logischen Spieltiles.
Die aktuelle Aufgabe benötigt keine Themenlayer-/Fruchtbarkeitsableitung und
keine GUI-Legende. Solche Tile-Eigenschaften sind spätere Erweiterungen.

## Renderer-Ausgabe und Versionierung

Die Rendererableitung folgt [`RENDERING.md`](RENDERING.md). Unveränderte
Quellen, kanonische Geodaten und daraus gebaute Renderblöcke werden getrennt
abgelegt. Das versionierte Manifest bindet Dataset-/Schema-Revisionen,
CRS/Einheiten, regionalen Extent, Quellen- und Mappingrevision,
Block-IDs/Bounds, Eltern-Kind-LOD, Payloadtyp/-größe/-Kodierung,
Generalisierungsfehlerbeleg und Hash je Payload. Ein gebundener Build darf
keine `current/latest`-Quelle ohne aufgelöste Versionskennung verwenden.
Breaking Changes erhöhen die Schema-Hauptversion; alte Berichte bleiben über
Revision und Hash reproduzierbar. Das Kit bestimmt absichtlich noch kein
GIS-/Mesh-Binärformat, Kompressionsverfahren oder GPU-Cacheformat: diese Wahl
wird bei R0/R1 anhand der Quelldaten, Zielplattformen und gemessenen
IO-/Speicherwerte begründet.

## Vollständige Datenherkunft statt erfundener Ersatzlandschaft

Auch neutrale Darstellung kultivierter/unbekannter Klassen bleibt an reale
Quellklassen gebunden. Keine vermeintlich ursprünglichen Wälder/Biome erfinden,
um Lücken oder Felder zu verdecken. Datenbasierte Grobrepräsentation bzw.
Auslassung mit erklärter Lücke ist eine kartographische Darstellung, keine
rekonstruierte Natur von 180 n. Chr. Repräsentative Einzelbäume werden aus
Landcover samt Ableitungsregel platziert und nicht als erfasste Einzelbaumstandorte
behauptet. Für tatsächliche NoData muss eine belegte Quelle/Kompositbehandlung
gefunden oder die Abnahme offen gelassen werden. Herkunft jeder Ableitung,
Quelldatengenauigkeit (auch ausdrücklich unbekannt), Skalen und Fehlerprüfung
werden unter A16 gebunden. Sommergestaltung erfindet keine gemessene Phänologie.
