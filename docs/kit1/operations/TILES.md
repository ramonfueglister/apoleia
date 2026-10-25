# Unsichtbare quadratische Tile-Grundlage

Referenz `kit1-landscape-v5`, Vertrag `kit1-ops-v5`. Kit 1 zeigt nach der neuesten
Nutzerkorrektur **genau eine natürliche Landschaftsansicht**, nur Pan und
stufenlosen Zoom. Keine GUI, sichtbaren Rasterlinien, Planung, Themenansicht,
Tile-Auswahl, Highlights oder verborgenen vorbereiteten Anzeige-Modi implementieren.
Quadratische Tiles bleiben ausschließlich eine interne räumliche Datenbasis.

## Technische Definition

`config.tiles` bindet Raster-ID, Revision und ein gehashtes `definition`-Artefakt.
Es dokumentiert logischen Quadrat-Rasterraum, Ursprung/Indexachsen, Größe/Einheiten,
kanonisches ID-Schema, regionale Teilräume, Quellgeografiebezug, Naht-/Kartenrandregeln, Randzuordnung und LOD-Aggregation. Tilegröße und Projektion sind keine
schon beschlossenen Nutzerwerte. Verfahren aus dem Auftrag begründen, keine
Wiederholung der Quadrat-/GUI-/Modusfragen.

Quadratisch gilt im logischen Raum. Regionale Abbildung und Isometrie können Flächen
verzerren; keine global gleich großen unverzerrten Quadrate auf einer Kugel
versprechen. An einer Naht dürfen Aliasadressen vorkommen, aber eine Fläche hat
eine nachvollziehbare kanonische ID. LOD darf Daten aggregieren, nicht deren
Identität ersetzen. Küsten und Flüsse dürfen Tilegrenzen frei schneiden; keine
Rasterstufen allein zur Sichtbarmachung dieser internen Struktur erzwingen.
Quell-Datenkacheln und logische Tiles sind nicht automatisch dasselbe.

## Interne Belege ohne GUI

`fixture.tile_cases` bindet vorhandene geografische Anker an erwartete kanonische
Tile-IDs/Indizes `(region,row,column)` und mindestens zwei View-Zustände mit
unterschiedlichen Zoomwerten. Erwartete Zuordnung unabhängig anhand der gehashten
Adressierungsdefinition ableiten. Fälle umfassen Binnenfläche, Küste, regionalen Kartenrand und Tile-Naht; konkrete Koordinaten kommen aus den tatsächlich gewählten Daten.
Die vorhandene Fixture prüft Pan und Rückkehr. Zusätzlich bindet
`fixture.tile_navigation` einen der Tile-Fälle an eine geplante View-State-Folge
mit mindestens zwei geografischen Kamerazielen und Zoomwerten sowie Rückkehr zum
identischen Anfangszustand. Dieser verbindliche Tile-Abdeckungspfad genügt; nicht
jeder einzelne Rand-/Nahtfall braucht eine eigene zusätzliche Panfahrt.

`fixture.project_extent` und `region_revision` binden alle Anker an `region.json`.
Anker müssen innerhalb des gebundenen Projekt-Extents liegen. `interior` liegt
außerhalb des Randbands, `region_edge` innerhalb des Randbands;
`edge_max_distance_degrees` ist ein vorab festgelegter technischer Prüfparameter
(bis maximal 1°, Vorlage 0,25°), keine geografische Gebietsentscheidung.
`coast` benötigt einen als Küste aus realer Quelle belegten Anker, `tile_seam`
einen entsprechend belegten Nahtanker. Küsten-/Nahtwahrheit und die echte Maske
sind zusätzlich unabhängig anhand Quell-/Adressierungsbelegen zu prüfen; der
Hilfsprüfer berechnet keine Küsten oder Rastergeometrie. Weder weltweite Pole
noch die Datumsgrenze werden für dieses regionale Kit verlangt. Zusätzliche
Projektions- oder Datenblattnähte innerhalb des Projektgebiets gesondert prüfen.


`tiles.json` enthält tatsächliche interne Probes desselben Runs/Builds. Jeder
Probe nennt Fall, tatsächlichen Kamera-/Viewport-/Transformzustand, Laufzeit,
kanonische Tile-ID, logischen Index und logische Zellbreite/-höhe. Die Maße sind
positiv und gleich, innerhalb desselben kanonischen Tiles über Zoomzustände stabil;
sie legen keine reale Metergröße oder physische Flächengleichheit fest. Jeder
geplante Fall-/View-Zustand muss auftreten. Jede Probe besitzt eine eigene ID.
`tiles.navigation_probe_ids` referenziert tatsächlich beobachtete Probes genau
in der geplanten Navigationsfolge, mit passenden Zuständen/Fall und streng
steigenden Zeiten. Rückkehr benötigt eine neue Probe, nicht Wiederverwendung
der Anfangs-ID. Ein separat bestandener A05-Pan ohne Tilebeobachtung genügt nicht. Probes können während einer separaten
internen Prüffahrt entstehen; ihre Zeiten beziehen sich auf deren protokollierten
Start. Sie sind keine Pixel-/Farbmessung und keine Auswahlaktion.

`tiles.json` wird als Runtime-Evidence referenziert und mit A15 verknüpft. Der
Vertrag erlaubt nur `presentation: natural_landscape_only`, keine GUI, kein
sichtbares Raster und kein Auswahlhighlight. Die tatsächlich geöffneten normalen
Runtimebilder müssen dies bestätigen. Externe Logs/Belegdateien ersetzen Onscreen-
Debuganzeigen; keine zusätzliche Darstellungsfunktion zur Abnahme einbauen.

## Grenzen und spätere Erweiterung

Der Kitprüfer prüft Verträge, Revisionen, Transform-/Methodenhashes und Konsistenz,
nicht einen Tilealgorithmus oder wissenschaftliche Geodatengenauigkeit. Echte
Quellenzuordnung und Quadratdefinition unabhängig prüfen; deklarierte Werte allein
beweisen keine Implementation. Noch wird kein Tile-/Renderer-/Pickingcode erstellt.

Drei Ansichten (natürlich, Planung mit Raster/Auswahl, thematische Tilefarben),
Eigenschaften wie Fruchtbarkeit/Boden und deren Legenden bleiben ausschließlich
spätere Ziele. Keine aktuellen Planungs-/Themenabnahmen, keine Themenquelle oder Modusfolge als
Readiness-Bedingung und kein GUI-Framework als Pflichtabhängigkeit.
