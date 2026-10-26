# Aktuelles Renderingbriefing – 26. Oktober 2026

Referenzversion: `rendering-diorama-2026-10-26`. Status: `implementiert` in Arbeit; visuelle Abnahme `offen`.

Ramon bestimmt Claude Opus 5.5 als fachlichen Lead; die Umsetzung folgt seinem konkreten Grafikbriefing. Priorität 1 ist das sichtbare Landschaftsergebnis. Der bestehende Worktree bleibt erhalten. Bisherige Wirtschaftsphasenregeln definieren keine Renderingabnahme.

Geodaten bestimmen, wo Wald, Fels und Wasser liegen. Shader bestimmen die Darstellung; prozedurale Variation innerhalb der Klassen ist ausdrücklich gewünscht. Maßgebliche Bildreferenz: [Nutzerreferenz](references/images/user-primary-landscape-style.png).

- Forward+ mit ACES/AgX, Sky-Ambient, SSAO, warmer Sonne, weichen und zoomabhängigen Schatten sowie leichter Luftperspektive. Bestehende Wolkenmaterialien bewahren.
- Meer, Seen und Flüsse teilen Wasserfarbe und Oberflächencharakter. Reale Bathymetrie steuert Navy `#0f3f78`, Blau `#1b5fa3`, Türkis `#3fa7b5`. Materialwellen, Fresnel, Sonnenglanz und dünne animierte Küsten-SDF-Schaumlinien; Fernkarte blendet Animation aus und behält den Tiefenverlauf.
- Gelbgrüne, olivfarbene und ockerfarbene Bodentöne mit Makrovariation um 20 km, Mesovariation um 2 km und feiner Nahvariation. Höhen-/Hangmischung, helle graubeige Felsfacetten, Schnee auf höchsten Gipfeln, helle Sandsäume und weiche Flussufer; Kavitäts-/Waldschatten.
- Laufzeit: feste Clipmap-/Geomipmapringe, Höhenverformung und Morph im Vertexshader, 256²-Tilepyramide für Höhe/Material/Wasser, asynchrones Laden mit LRU/Vorladen und residentem Groblevel, Wald-MultiMesh je Tile. Virtual Texturing ist optional Phase 2.
- Agent A besitzt Grafikshader, Wasserstil, Environmenthelper und project.godot. Agent B besitzt landscape.gd und Laufzeit/Streaming und integriert kleine Hooks.

Abnahme durch Ramon anhand von Fern-/Mittel-/Nah-Screenshots neben der Referenz unter `docs/kit1/screenshots/compare-*.png`. Dazu Britannien–Ägypten–Fern/Nah/Fern-Video mit Frametime. Kein automatisches Marketing-PASS; keine neue Review-JSON- oder Einpixelabweichungsarbeit, kein Waldcache-Refactoring als Vorbedingung. Kleine Commits nur aus eigener Whitelist.

Annahmen: Welt-XZ und Kamerabreite sind Modellkilometer; Quellhöhe, Küsten-SDF und positive Wassertiefe bleiben Meter. Materialvariation verändert keine geografische Klassenzuordnung. Vorhandene eigene r6-Wasserfunktionen werden als Ausgangspunkt weiterentwickelt.
