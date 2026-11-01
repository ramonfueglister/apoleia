# Verona – Wohnviertel und formbewahrende Detailstufen

Stand: validiert; Spielprüfung unter `docs/handover/verona-city/validation.md`.

Veronas acht Wohnparzellen verwenden jetzt ausschliesslich die eigenen römischen Modelle. Die akzeptierte Taverna sowie Bäckerei, Schmiede, Insula und Mühle bleiben erhalten; Hofhaus, Stadthaus mit Loggia und Haus mit Dachhof füllen die drei übrigen Parzellen. Die 23 zusätzlich auf Strassenparzellen dargestellten Häuser/Läden erhalten eigene kleine Modelle. Fahrbahnen, Wege, bestehende Höfe, Mauern, Tore, Forum und Gräber behalten ihre bisherigen Plätze und Funktionen. Die anschliessende Modellrunde für Mauern, Tore und Gräber ist separat unter [Veronas Befestigungen](VERONA_FORTIFICATIONS.md) dokumentiert.

Start: `scripts/play-verona`. Einzelne Wohnhäuser sind auch mit `scripts/play-roman-building verona_townhouse` usw. erreichbar.

## Modelle und Platzierung

| Modell | Grundfläche | Höhe | Verwendung |
|---|---|---|---|
| Hofhaus mit Laden | 9,2 × 9,2 m | 6,40 m | Wohnparzelle (18455, 6921), Zugang Norden |
| Stadthaus mit Loggia | 9,2 × 9,2 m | 8,71 m | Wohnparzelle (18460, 6918), Zugang Süden |
| Haus mit Dachhof | 9,2 × 9,2 m | 8,51 m | Wohnparzelle (18458, 6919), Zugang Süden |
| Kleines Strassenhaus | 2,8 × 2,8 m | 6,37 m | Bestehende mittlere/höhere Strassenstücke |
| Taberna am Strassenrand | 2,8 × 2,0 m | 3,65 m | Bestehende niedrige Strassenstücke |

Die neuen Häuser werden in diesen Grössen gezeichnet, ohne Achsenverzerrung oder Verkleinerung von Türen. Wohnparzellen folgen ihrem bisherigen Atlas-Zugang und bleiben unter der 9-m-Höhenbegrenzung. Die kleinen Strassenmodelle sind eigenständige Grundrisse und keine zusammengeschrumpften Wohnhäuser. Ihr Abstand zur breitesten Fahrbahn beträgt mindestens 0,79 m. Die Strassenstücke behalten die bisherigen Orientierungen und die Abstufung in niedrige Läden auf der Kameraseite bzw. höhere Häuser dahinter. Drei dezente Putzfarben vermeiden vollkommen identische Reihen.

Der Atlas bleibt unverändert. Die Strassenhäuser sind weiterhin grafische Ergänzungen, keine zusätzlichen Simulationshaushalte. `verona_residences.json` definiert die drei Wohnparzellen; die übrigen Stücke werden aus der bestehenden `_plan_street`-Auswahl abgeleitet. Ein altes Strassenstück wird erst nach erfolgreichem Laden seines konkreten Ersatzes entfernt. Fehlende Assets lassen die alte Darstellung verfügbar. Mehrere Instanzen desselben Assets teilen die geladenen Mesh-/Texturressourcen.

## Detailstufen

Die 19 bisherigen Serienmodelle und fünf neuen Varianten verwenden `shape_preserving_v1`: mittlere und ferne Geometrie werden aus einzelnen Bauteilen neu aufgebaut. Mauerkörper bleiben geschlossen, Rundprofile werden kontrolliert vereinfacht, Bögen und Öffnungen bleiben erhalten. Dachziegel und kleine Verzierungen entfallen erst über einer geschlossenen Dachfläche. Es gibt keine pauschale Decimation über zusammengefasste Materialgruppen mehr.

Die Laufzeit verwendet alle drei eigenen Stufen. Zusätzliche automatische Godot-Mesh-LODs sind für diese GLBs ausgeschaltet. Die Taverna behält ihre separate, bereits akzeptierte Aufbereitung. Gröbere Landschaftsstufen verwenden weiterhin den entfernten Stadt-Renderer. Bereits geladene Gebäude bleiben beim Stadtwechsel im Speicher.

## Reproduzieren

Neue Modelle: `tools/buildings/build_verona_residences.py` mit Blender `--background --factory-startup --python … -- --all`. Die vorhandenen drei Seriengeneratoren bauen ihre Modelle mit dem gemeinsamen `roman_asset_kit.py` ebenfalls in drei Stufen. Bearbeitbare Blender-Dateien liegen unter `build/roman-series/<slug>/`, Spielassets und Messdaten unter `app/assets/buildings/<slug>/`.

Spielprüfung: `Godot --path app --script res://scripts/debug/verona_city_check.gd -- --phase=final`. Der Test pausiert die Simulation und misst dieselben fünf Ansichten wie der vorherige Zustand. Zusätzlich bleibt der Rundgang durch alle 19 ursprünglichen Modelle als Regressionstest verfügbar.
