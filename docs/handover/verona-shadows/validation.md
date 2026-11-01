# Nahansicht – Kanten und Schatten

Status: validiert am 1. November 2026; Godot 4.7.2 / Metal Forward+ auf Apple M3 Pro.

Die feinen Dächer und Steinfugen der neuen Modelle wirkten in der Nahansicht fleckig. Kontrollaufnahmen im tatsächlichen Spiel zeigen zwei getrennte Effekte: geometrische Kanten wurden zu grob abgetastet, während ein hoher Normalenversatz die geworfenen Schatten von kleinen Bauteilen wegschob.

## Änderung

`app/project.godot` aktiviert vierfaches MSAA für die 3D-Ansicht. Das vorhandene SMAA bleibt aktiv. `landscape.gd` setzt den Normalenversatz des Sonnenlichts von 28 auf 2. Tiefenversatz (0,1), Schattenauflösung (8192), 16-Bit-Schattenkarte, Filter, Lichtfarben, Umgebungslicht und Kontaktschatten bleiben erhalten. Gebäude, Materialien, Detailstufen, Gelände und Simulation werden nicht geändert.

MSAA glättet die Abdeckung feiner geometrischer Kanten. Der kleinere Normalenversatz verbessert die Lage der Schatten an Dachkanten und am Boden. Diese Wirkungen sind voneinander getrennt; der Normalenversatz war nicht die alleinige Ursache der Flecken. Die verbleibenden unterschiedlichen Steinfarben sind Materialgestaltung. [Godot: MSAA](https://docs.godotengine.org/en/4.5/tutorials/3d/3d_antialiasing.html#multisample-antialiasing-msaa), [Godot: Schattenversatz](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html#tweaking-shadow-bias).

## Diagnose

Alle Vergleiche verwenden dieselbe Kamera, 1440 × 1000 Pixel, pausierte Simulation und die tatsächlichen Spielassets. Pro Einstellung werden 60 Frames zum Einlaufen und 60 Messframes verwendet.

| Kontrolle | Beobachtung |
|---|---|
| Nur Normalenversatz 28 → 2 | Schattenlage ändert sich; feine Oberflächenflecken bleiben. |
| Nur Sonnenschatten aus | Flecken bleiben an Fugen und Ziegeln sichtbar. |
| Nur SSAO aus | Flecken bleiben ebenfalls sichtbar. |
| Sonnenschatten und SSAO aus | Bestätigt den Anteil der Oberflächendarstellung. |
| 32-Bit-Schattenkarte | Keine relevante Verbesserung der betreffenden Kanten; nicht übernommen. |
| Unbeleuchtetes Material | Bestätigt natürliche Stein-/Ziegelfarbvariation; starke feine Beleuchtungskontraste entfallen. |
| MSAA 4× | Deutlich ruhigere Dachziegel, Fugen und Fensterdetails bei erhaltener Form. |
| MSAA 4× und Normalenversatz 2 | Zusätzlich besser verbundene Schatten an Häusern und Toren. |

Ein unabhängiger visueller Review bestätigt die Verbesserung in der Nahansicht. In den sichtbaren Bereichen der ersten Verona-Vergleiche bei 1,5 / 5 / 12 / 24 km und in Rom bei 3 km wurden keine neuen Fehler an Durchgängen, Dachkanten oder Bodenkontakten beobachtet. Der erste 60-km-Vergleich war durch bewegte Wolken verdeckt; dieser Lauf wird nicht als Beleg für das dortige Gelände verwendet. Der abschliessende Vergleich schaltet das Wetter ausschliesslich im Prüfprogramm aus.

Der abschliessende Lauf mit ausgeschaltetem Wetter besteht mit **0 Fehlern**. Alle sechs alten/neuen Ansichtspaare wurden unabhängig geprüft, einschließlich des jetzt vollständig sichtbaren Geländes bei 60 km. Keine neuen streifigen Schatten auf sichtbaren Hängen, abgelösten Bodenkontakte oder Fehler an Toröffnungen, Dachkanten und Dächern beobachtet. Der Stadtatlas bleibt bytegleich; keine Ladefehler. Bericht: [clear-report.json](clear-report.json).

Bildpaare: [Verona vorher](images/baseline-1.5.png) / [nachher](images/final-1.5.png), [Übersicht vorher](images/baseline-5.0.png) / [nachher](images/final-5.0.png), [Gelände vorher](images/baseline-60.0.png) / [nachher](images/final-60.0.png), [Rom vorher](images/rome-baseline-3.0.png) / [nachher](images/rome-final-3.0.png). Die weiteren 12-/24-km-Ansichten stehen ebenfalls im Bilderordner.

## Grenzen der Messung

Die ersten Diagnoseläufe und Teile des ersten vollständigen Vergleichs überlappten mit fremden Godot-Tests auf demselben Rechner. Aus diesen Framezeiten wird keine prozentuale Geschwindigkeitsänderung abgeleitet. MSAA hat zusätzlichen Speicher- und Abtastaufwand. Die Screenshots und der statische Review belegen kein vollständiges Verschwinden von Flimmern bei Kamerabewegung.

Ein gesonderter Lauf verwendet tatsächliche `frame_post_draw`-Ereignisse, deaktiviertes VSync, ausgeschaltetes Wetter und keinen Bildexport. Jeder Messwert umfasst nachweislich genau ein gerendertes Bild. Ein vorausgehender Versuch mit reinen Prozess-Ticks wurde verworfen, weil Hintergrund-/Präsentationsverhalten die Tickrate von der Bildrate entkoppelte. Der gültige [Leistungsbericht](performance-report.json) enthält 720 gemessene Renderframes in A–B–B–A-Reihenfolge, jeweils 60 Einlauf- und 60 Messframes pro Abschnitt, ohne Testfehler.

| Breite | Vorher: zwei Mediane | Nachher: zwei Mediane |
|---|---|---|
| 1,5 km | 41,82 / 24,67 ms | 25,45 / 26,57 ms |
| 5 km | 29,32 / 31,45 ms | 32,67 / 34,51 ms |
| 60 km | 14,69 / 15,11 ms | 15,88 / 15,99 ms |

Der erste Nahabschnitt streut stark; daraus wird kein Geschwindigkeitsgewinn behauptet. Bei 5 und 60 km liegen die zusammengefassten Mediane nachher etwa 2,46 beziehungsweise 0,90 ms höher. Das ist ein beobachteter Qualitäts-/Leistungsabwägungspunkt dieses Rechners, kein garantierter Hardwarevergleich. Hintergrundarbeit und thermische Bedingungen waren nicht vollständig kontrolliert. GPU-Zeit wird nicht aus Prozess-Ticks abgeleitet.

## Reproduzieren

```sh
Godot --path app --script res://scripts/debug/verona_shadows_check.gd
Godot --path app --script res://scripts/debug/verona_shadows_check.gd -- --phase=surface
Godot --path app --script res://scripts/debug/verona_shadows_check.gd -- --phase=edges
Godot --path app --script res://scripts/debug/verona_shadows_check.gd -- --phase=clear --weather=off
Godot --path app --script res://scripts/debug/verona_shadows_check.gd -- --phase=perf --weather=off
```

`clear` prüft die eingestellten Produktionswerte und vergleicht alte/neue Konfiguration in A–B–B–A-Reihenfolge über fünf Verona-Zoomstufen. Anschliessend folgt Rom. `perf` misst drei repräsentative Zoomstufen ohne Bildexport. Der Test verändert keine gespeicherten Einstellungen. Alte und neue Varianten werden im selben Prozess geladen; die Modelle bleiben dabei identisch. Ergebnisbilder und Rohdaten entstehen unter `build/verona-shadows/<phase>/`.
