# Realdaten → verkleinerte Modellwelt → kontinuierliche Darstellung

`kit1-landscape-v5` / `kit1-ops-v5`; `spezifiziert`, keine GIS-/Rendererimplementation.
Methodenquellen: [GEODATA_METHODS](../references/GEODATA_METHODS.md). Die Verfahren
sind Auswahlgrundlagen, keine vorgeschriebene Engine oder Bibliothek.

## Drei nachweisbare Räume

1. **Quellraum:** originale Geokoordinaten, Höhen, Landcoverklassen, Auflösung,
   Erfassungsdatum, CRS/Höhendatum und bekannte oder ausdrücklich unbekannte
   Genauigkeit. Rohdateien unverändert aufbewahren.
2. **Modellraum:** eine tatsächlich verkleinerte Welt mit weniger repräsentierten
   Kleindetails. Eine dokumentierte gemeinsame Längenskalierung kleiner als eins
   gilt auch für Höhen. Geometrievereinfachung folgt aus Quelldaten,
   Generalisierungsbudgets und Schutzregeln; eine extreme Low-Poly-Optik ist keine
   Vorgabe der aktuellen Nutzer-Primärreferenz.
   Terrain wird nicht frei überhöht oder zwischen Orten beliebig zusammengeschoben.
   Spätere kleinere Modellbevölkerungen/-städte sind damit nicht numerisch bestimmt.
3. **Renderraum:** dieselbe Modellgeografie wird zoomgebunden von flacher Karte
   zur räumlichen isometrischen Nahansicht dargestellt. Kamera/Projektion und
   Reliefgewicht folgen einem versionierten kontinuierlichen Profil. Endpunkte
   `relief_weight=0` bzw. 1 beschreiben die Renderabflachung, nicht neue Modelldaten.
   Es gibt keine Umschaltung von Szenen, GUI-Modi oder frei drehbare Kamera.

Eine flache Projektion ist nicht global verzerrungsfrei. Projektionswirkung,
Modelleinheit/Skalierung und Vereinfachungsfehler getrennt messen. Die Quellgeografie
bleibt geodätische Referenz, nicht das bereits verzerrte Ergebnis seiner selbst.

## Vor Verarbeitung und Messung festlegen

`templates/geodata_policy.json` ausfüllen, hashen und versionieren:

- Skalenfaktor, gleiche Höhen-/Längenskalierung; Modell-/Rendertransformationen,
  Projektionsdefinition und echte Quelldatenqualitätsbewertung als Artefakte.
- Generalisierungsniveaus mit IDs, Gültigkeitsgebiet und Stichprobenplan. Alle
  produzierten Niveaus im abgeleiteten Inventar führen, nicht nur erfolgreiche
  Niveaus nachträglich auswählen. Räumliche und zeitliche Stichprobenbereiche,
  Abstand/Dichte, schwierige Fälle, nicht untersuchte Bereiche dokumentieren.
- Budgets pro Niveau: Höhen- und horizontale Geländeabweichung sowie Küsten-
  versatz in **Quellmetern**, Screen-Space-Fehler und Übergangsresiduum in **Pixeln**,
  Projektionsmaßstabsabweichung als dimensionsloses Verhältnis. Meterfehler sind
  gegen Quellgeometrie nach Rücktransformation zu messen, nicht gegen scheinbar
  kleine Modellkoordinaten. Pixelwerte binden Viewport, Kamera und Zoomzustand.
- Methodenbeschreibung definiert die metrische Distanz (z. B. vertikal,
  geodätisch/gerichtet), die Stichprobengrundlage und wie Projektionsverzerrung
  ermittelt wird. `projection_scale_error_ratio` bezeichnet den Betrag der
  relativen lokalen Längenmaßstabsabweichung, nicht ein Winkel- oder Flächenmaß.
  Weitere notwendige Flächen-/Winkelanalysen als Methodenbeleg beilegen.
- Schutzregeln für Küsten, Inseln, Flussnetzverbindungen, Gebirgskämme und
  Tile-Nähte. Konkrete Schutzobjekte/Regionen in gehashten Regeln/Inventaren
  identifizieren; Topologie umfasst bei Bedarf Komponenten, Verschachtelung,
  Schnittfreiheit und Netzkonnektivität. Nicht pauschal behaupten, ein
  LOD-Algorithmus garantiere diese Eigenschaften.
- Detailauslassungsregeln: welche kleinen Elemente wann entfallen dürfen und
  welche unbedingt erhalten bleiben. Bei Schutzobjekten darf die Auslassungsregel
  nicht als Hintertür dienen. Widersprüche vor Verarbeitung lösen und dokumentieren.

Budgets sind begründete technische Festlegungen, keine bereits gewählten Zahlen
und keine nachträgliche Lockerung, um Messwerte passend zu machen. Die Transformation
und Algorithmen müssen zum Quelldatentyp passen; Heightfields allein stellen etwa
nicht beliebige überhängende Oberflächen dar. Kein Raten bei fehlenden Quelldaten.

## Ableitung und Nachweise

- Verarbeitungstools, Versionen, Parameter, Eingangs-/Ausgangshashes dokumentieren;
  projektweite Ableitung/LOD-Inventar sowie Nähte/Kartenränder und geodätische Fixpunkte
  prüfen. Reale Quellenqualität begrenzt jede Aussage über Genauigkeit.
- `derivation.json` bindet diese Policy, alle verwendeten Höhen-/Wasser-/Landcover-
  Quellen, deren Qualitätsbelege und abgeleitete Ausgaben. Repräsentative Bäume
  sind datenbasierte Landcoverrepräsentation, keine Einzelbaummessung. Kultivierte
  oder unbekannte Klassen nicht in erfundene ursprüngliche Vegetation verwandeln.
- Pro Policy-Niveau und Metrik Rohstichproben, Scope, Sampling- und Abdeckungsbeleg
  sowie berichtetes Stichprobenmaximum liefern. Der Hilfsprüfer berechnet dieses
  Maximum erneut und vergleicht mit dem vorab gebundenen Budget. **Das ist keine
  globale mathematische Fehlerschranke.** RMS/Heuristikwerte dürfen nicht als
  Maximum eingetragen werden. Zusätzliche streng bewiesene Grenzen separat belegen.
- Topologie-/Featureprüfung pro Klasse mit Schutzumfang, gemeldeten unerwarteten
  Änderungen und gehashten Prüfbelegen. Unerwartete Änderungen müssen null sein;
  geplante Auslassungen brauchen konkrete Quellfeature-IDs, Regel und Nachweis.
- Laufzeittelemetrie enthält tatsächliche Zwischenzustände. Das Übergangsresiduum
  vergleicht die erwartete kontinuierliche Bewegung mit der beobachteten Position,
  nicht die legitime Kamerabewegung selbst. LOD-Geomorphing und Kameramorphing sind
  getrennte Ursachen und zusammen mit ungeschnittenem Video zu prüfen.

## Grenzen der Kitprüfung

`preflight` blockiert ohne Policy, Budgets, Schutz-/Quellen-/Transformbelege.
`report-check` verlangt A16 und prüft Struktur, Revisionen/Hashes, vollständige
**deklarierte** Niveau-/Metrikkombinationen, Rohwertmaximum, Budget und gemeldete
Topologieabweichungen. Es führt keine Geoverarbeitung aus, liest keine Koordinaten-
geometrie zur unabhängigen Wahrheitsermittlung und erkennt kein gefälschtes
Laufzeitprotokoll. Ein Reviewer muss Quellenqualität, Vollständigkeit aller
produzierten Levels, Metrikimplementation, Schutzregeln, Sampling und Video
unabhängig beurteilen. Ein leeres geschütztes Inventar oder nur leichte Testorte
sind keine pauschale Weltgenauigkeit. Die projektweite Gesamtprüfung verlangt für jede
Schutzklasse einen tatsächlich nichtleeren Schutzbestand. Ein lokaler Ausschnitt
ohne Inseln darf im regionalen Methodenbeleg als nicht anwendbar mit Regions-
und Quellenbeleg stehen; er ersetzt aber keinen projektweiten Inselnachweis. Null
geprüfte Schutzobjekte können keinen erfolgreichen projektweiten Erhaltungsbefund ergeben.
