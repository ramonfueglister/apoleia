# Verona – Vegetation

Status: validiert für die lokale Nahansicht; [Prüfbericht und Grenzen](../handover/verona-vegetation/validation.md). Eigene Gestaltung auf Grundlage der vom Nutzer angenommenen [Modellstudie](../handover/verona-vegetation/concepts/vegetation-sheet.png) und [Stilstudie](../handover/verona-vegetation/concepts/courtyard-style.png). Diese Bilder sind generierte Entwürfe, keine Spielaufnahmen und keine archäologische Rekonstruktion.

## Beobachtung und Gestaltung

Die bisherige Landschaft verwendet blockförmige Bäume aus einem gemeinsamen GPU-Platzierungspass. Dieser berücksichtigt Bodenbedeckung, Gelände, bebaute Flächen, Wege und Wasser. Verona liegt nördlich der bisherigen 44.5°-Grenze für südliche Wildvegetation; seine Laubwälder dürfen deshalb nicht pauschal durch Olivenbäume ersetzt werden.

Die neue Modellfamilie umfasst Zypresse, Schirmpinie, Olive, Uferweide, Röhricht und einen bepflanzten Terrakottatopf. Ein zusätzlicher Laubbaum und niedriger Strauch übernehmen die bestehenden Wald- und Gebüschstandorte. Artenwahl und lokale Schmuckpflanzungen sind bewusste gestalterische Entscheidungen, keine historischen Habitatnachweise.

Die angenommenen Bildentwürfe geben Silhouetten, Farben und Materialwirkung vor. Einzelne feine Blätter werden in den Spielmodellen zu kantigen Laubgruppen zusammengefasst. Die Stilstudie ersetzt weder den vorhandenen Stadtplan noch Gebäude, Brücken oder Gelände.

## Modellmassstab

Alle Modelle werden in Blender in Metern angelegt und mit demselben Faktor `DIORAMA_KM_PER_M = 0.0238` wie die Gebäude dargestellt. Grundpunkt ist die Stammwurzel beziehungsweise die Unterkante des Pflanzgefässes. Jede Art besitzt drei eigens gebaute Detailstufen mit erhaltenem Stamm- und Kronencharakter. Es gibt keine nachträgliche automatische Dezimierung. Opaque Flächen und eine gemeinsame Oberfläche mit Vertexfarben ermöglichen gebündeltes Zeichnen ohne Blatt-Transparenzsortierung.

## Reproduktion

Generator: `tools/buildings/build_verona_vegetation.py`. Laufzeitmodelle: `app/assets/vegetation/`. Blender-Dateien und Vorschauen entstehen unter `build/verona-vegetation/`. Die generierten Konzeptbilder wurden mit dem eingebauten Imagegen-Werkzeug erstellt und dienen ausschliesslich als eigene gestalterische Referenz.

Prüfbericht und echte Spielbilder werden nach dem Integrationslauf unter `docs/handover/verona-vegetation/` abgelegt.

## Laufzeit und Rückfall

`verona_vegetation.gd` begrenzt den Austausch auf einen 64 × 64 Parzellen grossen Bereich um Verona und Sichtbreiten bis 12 Welt-km. Die acht Modelle müssen vollständig geladen sein. Erst dann aktiviert die Laufzeit eine Maske für tatsächlich installierte Ersatzinstanzen. Passt eine ausgewachsene Krone nicht, wird am selben bestehenden Pflanzpunkt eine schmale Zypresse im Stadtumfeld oder ein niedriger Strauch verwendet. Das ist eine bewusste Gestaltung als Randbepflanzung, keine Veränderung des Massstabs oder des Standortes. Nur wenn auch der Strauch nicht passt, bleibt die bisherige Darstellung erhalten. Bestehende Nadelbaumarten ausserhalb der neuen Familie behalten ebenfalls ihr bisheriges Modell.

Die bestehenden GPU-Pflanzplätze werden in kompakte Listen je Art eingelesen. Der neue Shader liest für jede Instanz weiterhin den aktuellen Pflanzplatz: Höhe, Sichtbarkeit und Position stammen damit aus derselben Quelle wie zuvor. Ein Wechsel des ursprünglichen Pflanzentyps aktiviert unmittelbar die bisherige Darstellung, bis die Ersatzliste erneuert ist. Kamerawechsel und Simulation können keine veraltete Höhe festschreiben. Die Listen werden gebündelt als MultiMeshes gezeichnet; es entstehen keine einzelnen Szenenknoten je Baum.

Vor der Platzierung prüft die Laufzeit den maximalen horizontalen Abstand der tatsächlichen Meshpunkte über alle drei Detailstufen gegen bebaute, Strassen- und Wasserparzellen. In unbebautem Land neben dem vorhandenen Stadtgefüge können bestehende Baumplätze gezielt Zypressen, Pinien und Oliven tragen; bestehende kleine Strauchplätze können Pflanzgefässe aufnehmen. Weiden und Röhricht nutzen bestehende Plätze neben Wasserparzellen. Es werden keine neuen Flussläufe, Terrassen oder Häuser angelegt.

Die Grenzen der Detailstufen liegen bei 2.5 und 7.5 Welt-km Sichtbreite. Oberhalb 12 km sowie ausserhalb des Bereichs bleibt die bisherige Vegetation aktiv. Deren bestehende Fernvergrösserung wird in dieser lokalen Runde nicht verändert; die neuen Modelle verwenden sie nicht.

Die kompakte Instanzliste wird bei Kameraänderungen erneuert und sonst höchstens einmal pro Sekunde geprüft (fern alle zwei Sekunden). Unveränderte GPU-Pflanzdaten lösen keinen erneuten Listenaufbau aus. Höhe und Sichtbarkeit werden unabhängig davon in jedem gerenderten Bild aus der aktuellen GPU-Textur gelesen.
