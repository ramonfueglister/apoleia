# Vegetation in Verona – Validierung

Status: validiert für die lokale Verona-Nahansicht. Eigene Blender-Modelle, keine historischen Habitatbehauptungen. Die [Konzeptbilder](concepts/vegetation-sheet.png) wurden zuerst angenommen; [Blender-Modelle](blender-models.png) und [echte Spielaufnahme](verona-overview.png) sind getrennte Artefakte.

## Ergebnis

Acht Modelle mit je drei eigenen Detailstufen: Laubbaum, Strauch, Zypresse, Pinie, Olive, Weide, Röhricht und Terrakotta-Pflanzgefäss. Der geprüfte 5-km-Ausschnitt enthält 1657 aktuell gültige native Instanzen: 1111 Laubbäume, 420 Sträucher, 47 Zypressen, 12 Oliven, 10 Pinien, 9 Weiden, 31 Röhrichtgruppen und 17 Pflanzgefässe. Die gebündelte Liste enthält zusätzlich 12 inzwischen ungültige Plätze; beide Shader blenden diese anhand der aktuellen GPU-Platzdaten aus, bis die periodische Liste erneuert wird. Auf die gelistete Instanzzahl allein darf deshalb nicht als sichtbare Anzahl geschlossen werden.

Die Bildprüfung zeigt unterscheidbare Kronenformen und beseitigt die auffälligen alten Würfelgruppen im zentralen Ausschnitt. Die [Pinien-/Oliven-Nahaufnahme](pine-olive-closeup.png) zeigt die tatsächlich verwendeten Spielmodelle. [Pflanzgefässe](planting-closeup.png) stehen an bestehenden freien Pflanzpunkten neben Stadtbauten, nicht in neu angelegten Innenhöfen. Gebäude und Flussgeometrie stammen unverändert aus dem bisherigen Spiel.

## Prüfungen

- [Assetprüfung](asset-validation.json): 8 GLBs, 24 native Meshstufen, ein opakes Material je Mesh, Vertexfarben, Normalen, Bodenkontakt, Dreiecksbudget und Silhouetten über drei Projektionsachsen. Alle bestanden. Bei Röhricht werden im Fernmodell die Halme vereinfacht; die gesamte Pflanzfläche bleibt erhalten.
- [Spielprüfung](game-validation.json): 830 Frames, Sichtbreiten 1.5/5/12/24/60 km, Kamera hinaus und zurück, Abschaltung/Wiederkehr, drei gezielte Nahaufnahmen. Kein Prüffehler. Geprüft werden tatsächlicher Instanzpuffer, Ersatzmaske, aktuelle GPU-Pflanzpunkte, einheitlicher Massstab, native LOD-Auswahl und die importierten, gedrehten Meshpunkte gegen die Stadtparzellen.
- [Ausfallprüfung](fallback-validation.json): acht fehlende Assetzustände mit je vier Aktivierungszuständen; 32 Fälle und 578 Assertions ohne Fehler. Dies ist eine gezielte Zustandsinjektion, kein Netzwerk-/Dateisystemfehlertest des Godot-Loaders.
- [Unverändertheitsprüfung](unchanged-buildings-terrain.json): 78 vorhandene Gebäude-/Geländeartefakte bytegleich; Stadtatlas und Page-Mapping im Spiel ebenfalls unverändert.
- `git diff --check` und Godot-Parserprüfung ohne Fehler.

Die Spielprüfung berechnet sichtbare Positionen aus dem aktuellen GPU-Slot und unterscheidet sie von veralteten CPU-Listenständen. Ein ursprünglicher Test hatte diese Unterscheidung nicht getroffen; seine falschen Meldungen über ausgeblendete Plätze wurden vor dem endgültigen Lauf behoben. Die gelisteten Puffer und ihre Sichtbarkeitsbedingungen bleiben separat geprüft.

## Grenzen

Der Austausch ist auf Verona (64 × 64 Viertelparzellen) und bis 12 km Sichtbreite begrenzt. Am Rand ist bei weiter Übersicht der Übergang zur bisherigen Vegetation erkennbar. In der Ferne und bei nicht verfügbarer Modellfamilie bleibt die ursprüngliche Darstellung erhalten. Keine weltweite Waldumstellung und keine Änderung der bisherigen Fernvergrösserung.

Die Kronenprüfung deckt die Gebäude-/Strassen-/Wasserparzellen des Stadtatlas ab. Die vorhandenen GPU-Regeln bestimmen weiterhin Wurzelplätze gegenüber Feldern und simulierten Wegen; eine geometrische Prüfung jedes einzelnen landwirtschaftlichen Objekts ausserhalb des Stadtatlas ist damit nicht behauptet. Die Weidennahaufnahme zeigt eine dichte Baumgruppe, keinen neu gestalteten durchgehenden Flussrand.

## Reproduktion

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/buildings/build_verona_vegetation.py -- --render
build/verona-venv/bin/python tools/tests/check_verona_vegetation_assets.py
/Applications/Godot.app/Contents/MacOS/Godot --headless --path app --editor --import
/Applications/Godot.app/Contents/MacOS/Godot --path app --script res://scripts/debug/verona_vegetation_check.gd -- --phase=validated --weather=off
/Applications/Godot.app/Contents/MacOS/Godot --headless --path app --script res://scripts/debug/verona_vegetation_fallback_check.gd
/Applications/Godot.app/Contents/MacOS/Godot --path app --script res://scripts/debug/verona_vegetation_perf.gd -- --weather=off
```

Die Blender-Dateien werden reproduzierbar unter `build/verona-vegetation/` erzeugt und liegen für den Nutzer zusätzlich unter `romeprojekt/output/verona-vegetation/blender/`. Automatische Godot-Mesh-LODs sind in allen acht Importdateien deaktiviert.

## Gemessener Laufzeitaufwand

[Direkter Vergleich](performance.json) im selben pausierten Spiel, Apple M3 Pro, Metal Forward+, 1440 × 1000, jeweils mindestens 3.2 Sekunden und 120 tatsächlich gerenderte Frames. Damit sind die periodischen GPU-Auslesevorgänge eingeschlossen.

| Sichtbreite | Bisher median / p95 | Native Vegetation median / p95 |
|---|---|---|
| 5 km | 16.52 / 16.88 ms | 18.25 / 19.00 ms |
| 12 km | 29.44 / 38.74 ms | 35.66 / 47.38 ms |

Die detaillierteren Kronen kosten in dieser Messung zusätzliche Renderzeit. Die unveränderten Pflanzdaten verursachten während der Messfenster keine erneuten Listenaufbauten (3 beziehungsweise 2 periodische Auslesungen beobachtet). Das ist keine Beschleunigungsbehauptung und kein allgemeiner FPS-Nachweis. Die GPU-Zeitabfrage liefert auf diesem Backend 0; dargestellt werden Zeitabstände tatsächlich gerenderter Frames inklusive Host-Scheduling. Frühere kurze Stichproben sind nicht mit diesem gepaarten Lauf gleichzusetzen.
