# Verona – Prüfung der Befestigungen und Grabparzellen

Status: validiert am 1. November 2026 mit Godot 4.7.2 / Metal Forward+ auf Apple M3 Pro.

Die Wohnviertelrunde wurde mit PR [#140](https://github.com/ramonfueglister/apoleia/pull/140) in `main` übernommen. Diese Runde ergänzt sieben kombinierbare Befestigungsmodelle und drei Grabparzellen. Sie ersetzt Veronas vier Mauerparzellen, vier Tore und 23 Grabparzellen ohne Änderungen am Stadtatlas oder der Simulation.

## Ergebnis im Spiel

Der finale Lauf meldet **0 Fehler** nach 728 Spielframes. Alle vier Mauerparzellen, vier Torgruppen und 23 Grabparzellen sind geladen. 696 Strahlprüfungen bestätigen freie Durchgänge und geschlossene Anschlüsse in allen drei Detailstufen, einschließlich der tatsächlichen shaderseitigen Geländehöhen. 16 Beobachtungen während des Ladens bestätigen, dass unvollständige neue Tore unsichtbar bleiben; zusätzlich bestehen die isolierten Tests des Ersatzverhaltens.

Alle 35 bisherigen Serieninstanzen in Verona behalten ihre tatsächlichen Mesh-Grenzen. Stadtatlas und Seitentabelle sind bytegleich; es gibt keine Ladefehler. Alle fünf Spielansichten wurden mit pausierter Simulation bei 1440 × 1000 aufgenommen. Die Rohwerte stehen in [final-report.json](final-report.json).

Der anschliessende vollständige Rundgang durch die ursprünglichen 19 Modelle besteht ebenfalls mit **0 Fehlern** und normalem Prozessende: 1'175 Spielframes, 90 geladene Serieninstanzen, Stadtwechsel und Rückkehr, alle Detailstufen sowie die separate Taverna mit ihren bisherigen 30 Materialien und neun Texturen. Bericht: [series-regression.json](series-regression.json).

| Sichtbreite | Median Framezeit | Draw Calls | Primitive |
|---|---:|---:|---:|
| 1,5 km | 13,38 ms | 2'542 | 4'669'742 |
| 5 km | 15,95 ms | 3'218 | 6'475'526 |
| 12 km | 12,61 ms | 1'401 | 2'162'803 |
| 24 km | 14,38 ms | 1'301 | 3'337'201 |
| 60 km | 14,18 ms | 485 | 4'450'161 |

Die neuen Modelle erhöhen den Zeichenaufwand der nahen Stadtansichten. Rechnerauslastung und Messläufe sind nicht ausreichend kontrolliert für eine prozentuale FPS-Aussage; GPU-Zeit wird weiterhin als 0 gemeldet und nicht ausgewertet. Ab der gröberen Landschaftsdarstellung bleibt der vorhandene entfernte Stadtrenderer zuständig.

## Modellprüfung

- Alle zehn Modelle haben drei eigene, formbewahrende Detailstufen. Zusätzlich erzeugte Godot-LODs sind ausgeschaltet.
- Alle 30 Einzelansichten wurden aus den tatsächlichen GLBs gerendert und visuell geprüft. Kontaktübersichten und Beobachtungen stehen in [visual-review.md](visual-review.md).
- Der unabhängige GLB-Validator prüft sieben Befestigungsassets: gültige Indizes, endliche Geometrie, identische Ursprünge, feste Anschlusskoordinaten, 243 Strahlprüfungen der Endflächen und 270 freie Durchgangsstrahlen. Ergebnis: keine Fehler. [Maschinenlesbarer Bericht](asset-validation.json).
- Drei Grabvarianten passen in 9,2 × 9,2 m und bleiben unter 7 m Höhe. Ihre südliche Annäherung bleibt frei; die Laufzeit dreht sie zum vorhandenen Atlaszugang. Die Modelle haben 6'382–10'214 Dreiecke in der Nähe, 2'512–4'078 in mittlerer Entfernung und 1'330–2'340 in der Ferne.
- Import einschließlich der korrigierten Fundamente: keine Fehler oder Warnungen. Zehn bestehende Parzellenprüfungen bestanden; unabhängiger Code-Review fand keinen konkreten Fehler in Laden, Ersatzverhalten, Rotation oder Ursprungsbehandlung.

## Tatsächliches Gelände

Der Spieltest liest die gerenderte HDR-Höhentextur und berechnet daraus dieselbe maximale Terrassenhöhe je Parzelle wie der Gebäude-Shader. Er prüft die sieben Verbindungen sowohl lokal im Mesh als auch auf der unteren und oberen Geländehöhe. CPU-Positionen allein würden die shaderseitige Verschiebung nicht erfassen.

Dabei wurde eine reale Lücke zwischen der Mauer bei Verona-Offset (12,13) und dem Tor bei (12,14) gefunden: Die unveränderte Terrasse fällt um 0,15 Welt-km, entsprechend 6,30 Modellmetern. Der gerade Mauerarm erhielt deshalb einen geschlossenen Unterbau bis −6,5 m mit Überlappung zum bisherigen Sockel. Alle Dreiecke oberhalb Z=0 sind in allen drei Detailstufen exakt erhalten; die anderen sechs Befestigungs-GLBs blieben bytegleich. Es wurde weder das Gelände abgeflacht noch die ganze Wand gestreckt.

## Darstellung und Grenzen

Die Modelle verwenden eigene römische Bautypen. Sie behaupten keine Rekonstruktion einer bestimmten historischen Bauphase. Die bestehende Mauerlinie bleibt eine offene Kette; lediglich die vorhandene diagonale Verbindung zwischen zwei Torparzellen erhält passende Anschlussstücke.

In der sehr nahen Spielansicht bleiben fleckige Schatten auf feinen Stein- und Dachflächen sichtbar. Auch bestehende Häuser zeigen diese Artefakte der gemeinsamen Schatteneinstellungen. Diese Modellrunde verändert keine globale Beleuchtung. Die Isolationsansichten bestätigen geschlossene Geometrie; der Effekt wird nicht als Geometriefehler oder als beseitigt ausgegeben.

## Reproduzieren

```sh
Godot --headless --path app --editor --import
Godot --path app --script res://scripts/debug/verona_fortifications_check.gd
Godot --path app --script res://scripts/debug/roman_series_integration_check.gd
build/verona-venv/bin/python tools/tests/check_verona_fortification_assets.py
build/verona-venv/bin/python -m unittest discover -s tools/tests -p test_roman_series_placements.py
```

Der neue Spieltest liest den dauerhaft gesicherten `baseline-report.json` aus diesem Ordner. Generatoren, Skalierung und Ersatzlogik sind in [VERONA_FORTIFICATIONS.md](../../kit2/VERONA_FORTIFICATIONS.md) beschrieben.
