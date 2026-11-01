# Verona – erster Uferabschnitt

Status: validiert für den lokalen Pilot; [Prüfbericht und Spielaufnahmen](../handover/verona-bank/validation.md). Der Pilot setzt die angenommene [Uferstudie](../handover/verona-bank/riverbank-concept.png) an einem kurzen Abschnitt südwestlich der Nordbrücke um. Die Strassen- und Platzstudien gehören noch nicht zu dieser Umsetzung.

## Beobachtete Grundlage

Die blaue Flussfläche folgt im nahen Renderer einer Bandfunktion über den vorhandenen Geländedreiecken. Die sichtbare trockene Uferseite stimmt daher nicht überall mit der Grenze zwischen Land- und Wasserparzellen des Stadtatlas überein. Die bestehenden Höhen und Wasserbandbreiten müssen erhalten bleiben. Parzellen mit Strassen, Brücken, Mauern oder Gebäuden sind keine freie Gestaltungsfläche.

## Eigene Gestaltung

Ein schmaler, unregelmässiger Kiesstreifen, einzelne kleine helle Flusssteine sowie sparsame Gras- und Schilfgruppen verbinden die bestehenden Grünflächen mit dem Wasser. Die Umsetzung orientiert sich an Farben und Materialübergängen des Konzeptes; sie ist keine historische Rekonstruktion und verändert keine geografischen Daten. Es entsteht weder eine neue flache Plattform noch ein neu verlegter Flusslauf.

Die Stein- und Grasmodelle stammen aus `tools/buildings/build_verona_bank.py`. Sie werden in Blender in Metern erstellt und mit dem gemeinsamen Faktor `0.0238` dargestellt. Jede GLB enthält drei eigene Detailstufen mit einer opaken Vertexfarben-Oberfläche. Bereits vorhandenes Röhricht kann innerhalb derselben Materialfamilie verwendet werden.

Prüfergebnisse und echte Spielaufnahmen liegen unter `docs/handover/verona-bank/`.

## Umsetzung

Die lokale Kiesfarbe wird ausschliesslich im bestehenden Flussband-Zweig des Terrain-Fragments ergänzt. Ihre Distanz verwendet dieselbe Flussberechnung; die Wasserfläche und die Vertices des Geländes bleiben unverändert. Der Streifen liegt auf der trockenen Seite südwestlich der Nordbrücke, zwischen ungefähr den Viertelparzellen-X-Werten 18455.08 und 18457.85. Die Enden laufen weich aus. Die Kiesstruktur verwendet lokale Koordinaten und wird bei grossem Pixelabstand vereinfacht.

`verona_bank.gd` lädt zwei neue GLBs sowie das vorhandene Röhricht. Erst eine vollständige Modellfamilie aktiviert die Materialänderung und die drei MultiMesh-Gruppen. Die Positionen werden einmal deterministisch gewählt, gegen die trockene Uferseite und bebaute Parzellen geprüft und gegeneinander auf Abstand gehalten. Wenige Schilfgruppen bekommen zuerst Platz; kleine Steine und Gras füllen die verbleibenden Lücken.

Die Höhen werden pro Meshpunkt aus der aktuellen GPU-Eckentextur und derselben Geländediagonale wie beim Boden berechnet. Das ist eine vertikale Anpassung an den vorhandenen Untergrund; die Flusssteine bekommen keine separate ebene Basis. Die Normalen berücksichtigen diese Anpassung. Alle Achsen der Ausgangsmodelle verwenden den gemeinsamen Metermassstab.

Detailstufen wechseln bei 1.5 und 4 km Sichtbreite. Über 7.5 km, ausserhalb des Pilotbereichs, bei fehlenden Modellen oder unvollständiger Geländeabdeckung ist die Ergänzung deaktiviert. Es wird nichts aus dem ursprünglichen Gelände entfernt. Es gibt keine periodischen GPU-Auslesevorgänge für diese statischen Uferdetails.
