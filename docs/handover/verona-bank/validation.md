# Nordbrücken-Ufer – erster Pilot

Status: Uferdetails für diesen kurzen Abschnitt validiert; physikalischer Flussverlauf offen (Nutzerbefund vom 01.11.2026). Die [angenommene Bildstudie](riverbank-concept.png) ist von den [Blender-Modellen](blender-models.png) und den echten Spielaufnahmen getrennt.

## Ergebnis

Ein schmaler Kies-/Erdstreifen südwestlich der Nordbrücke, fünf Gruppen kleiner Flusssteine, fünf Schilfgruppen und 22 Grasbüschel. Zwei neue Blender-Assets ergänzen das bestehende Röhricht. Gebäude, Brücke, Flussband und Geländehöhen bleiben unverändert.

[Vorher](bank-before.png) · [Nachher](bank-detail.png) · [Nahaufnahme](bank-closeup.png) · [Übersicht mit Nordbrücke](bank-overview.png)

Die Bildprüfung zeigt kleine einzelne Kieskörner auf unterbrochenen Erdflächen; es gibt kein durchgehendes Pflasterfugenmuster. Die Modelle folgen den sichtbaren Schrägen. In den geprüften Ansichten sind keine schwebenden Pflanzen oder Überschneidungen mit Brücke, Gebäuden oder Wasser erkennbar. Bei weiterer Entfernung wird das feine Kiesmuster zu einer ruhigen Grundfarbe vereinfacht.

## Nachweise

- [Assetprüfung](asset-validation.json): zwei GLBs / sechs native Detailstufen, opake Vertexfarben, ein Material je Mesh, Bodenkontakt, Normalen, tatsächliche Ausmasse und Dreiecksbudgets bestanden. Steine 532/364/182 Dreiecke, Gras 224/168/112; automatische Godot-LODs deaktiviert.
- [Spielprüfung](game-validation.json): 583 Frames, 1,389,887 einzelne Prüfungen, kein Fehler. Ansichten mit .65/1.5/3/5/7.5/12 km Sichtbreite, Kamerafahrt aus dem Gebiet und zurück, drei injizierte fehlende Assetzustände mit atomarer Abschaltung und Wiederherstellung.
- Die unabhängige Platzprüfung liest die tatsächlichen GPU-Flussflags und prüft die importierten Meshpunkte aller Detailstufen gegen das bestehende Wasserband und bebaute Parzellen. Kleinster Abstand zum Wasser: 0.006543 Welt-km, rund 0.275 Modellmeter.
- Die pro Punkt angepasste Bodenhöhe wird gegen eine unabhängige baryzentrische Berechnung der tatsächlichen GPU-Geländedreiecke geprüft. Keine gemessene Abweichung in der Berechnung; pro Nahansicht sind darunter 8664 Kontaktpunkte auf geneigten Flächen. Dies ist eine Prüfung von Shaderberechnung, Datenbindung und Instanzpuffer, kein direktes Auslesen von GPU-Vertices nach dem Vertexshader. Die Spielbilder ergänzen die Prüfung.
- Beim Vergleich einer CPU-Mittellinie in grossen Weltkoordinaten mit den GPU-Flussflags gilt eine Toleranz von 0.00025 Welt-km (rund 1 cm Modellmass); eine reproduzierte Float32-Abweichung betrug 0.000173 Welt-km. Die tatsächliche Mindestdistanz zur Wasserfläche wird unabhängig und strenger als diese Mittellinienübereinstimmung geprüft.
- [89 bestehende Artefakte](unchanged-artifacts.json) für Gebäude, Vegetation, Stadtplan und Gelände sind bytegleich. Stadtatlas, Page-Mapping und GPU-Eckentextur sind im Spiel vor und nach dem Kameratest unverändert. Die Terrain-Shaderänderung fügt nur einen lokalen Farbauftrag im Fragment hinzu.
- Godot-Parserprüfung und `git diff --check` ohne Fehler.

## Umfang und Grenzen

Es bleibt ein einzelner lokaler Pilot. Strassenränder, Plätze, das andere Ufer und weitere Flussabschnitte wurden nicht umgestaltet. Die bestehende, nur farblich auf Geländedreiecke gelegte Wasserdarstellung bleibt sichtbar. Sie kann quer zum Fluss geneigt sein und in Längsrichtung ansteigen. Die obigen Prüfungen decken dieses Problem nicht ab; unveränderte Geländedaten sind kein Nachweis eines korrekten Flussgefälles. Über 7.5 km Sichtbreite, ausserhalb des Bereichs oder ohne vollständige Modelle bleibt die ursprüngliche Uferdarstellung aktiv. Es werden keine FPS-Verbesserungen behauptet; die statischen Instanzlisten benötigen keinen periodischen GPU-Readback.

## Reproduktion

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/buildings/build_verona_bank.py -- --render
build/verona-venv/bin/python tools/tests/check_verona_bank_assets.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path app --editor --import
/Applications/Godot.app/Contents/MacOS/Godot --path app --script res://scripts/debug/verona_bank_check.gd -- --phase=validated --weather=off
```

Für den Ausgangsvergleich setzt `--phase=baseline` den Pilot auf inaktiv. Editierbare Blender-Dateien entstehen in `build/verona-bank/` und wurden zusätzlich unter `romeprojekt/output/verona-bank-pilot/blender/` gesichert.
