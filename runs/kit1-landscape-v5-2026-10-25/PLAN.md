# Plan

Umfang/Referenzversion: Kit 1 / `kit1-landscape-v5` / `kit1-ops-v5`, Rendering-Vertrag `kit1-rendering-v4`
Nutzerauftrag: ausdrücklicher Implementierungsstart in `docs/kit1/START_PROMPT.md`
Aktueller interner Schritt: M0 technische Bindung / Operations; Umsetzung begonnen, Produktlaufzeit offen

| Schritt | Besitzer | Eingabe | Lieferung | Prüfbeleg | Status |
|---|---|---|---|---|---|
| M0 technische Ausarbeitung | Hauptagent + Daten-/Grafikowner; Operations koordiniert | Bestätigte Entscheidungen, aktueller Host/Toolchain, Daten- und Grafikentscheidungen | begründete Stack-/Daten-/Mapping-/Tile-/Testkonfiguration, Versionen und Abhängigkeiten | technische Entscheidungsnotiz, `config.json`, gehashtes region/sources/policy/grid | in Arbeit; Owner-Bindungen offen |
| M1 vollständiger Erkundungspfad | Grafikowner (einziger App-/Editor-Driver) + Datenowner | M0-Bindung, Region/Mask/coverage, renderable Daten | gesamte Projektregion, Pan, zoomgebundener flach-zu-isometrisch-Pfad, versteckte Tiles; zunächst einfache natürliche Darstellung | reale overview→near→overview Tour, camera/mapping/tile probes | offen; M0/Data bindet vor Pfad |
| M2 einheitliche Landschaft | Grafik-/Stilowner; Datenowner für Klassen/Provenienz | M1 gemeinsamer Pfad und Datenrevision, Primärreferenz | Terrain/Wasser/regionale natürliche Palette/Vegetation/LOD auf ganzer Region | echte feste Kameraaufnahmen, A08/A10, Geografie-/LOD-Probes | offen; nach M1 |
| M3 Robustheit und Leistung | Grafikowner + Captureowner | integrierter Build + gebundene Fixture/thresholds | Naht-/Küsten-/Rand-/Streaming-/Cache-/Rückfahrtfehler bearbeiten; messen | reproduzierbare Rohtelemetrie und Fehlerbelege | offen; nach integriertem Build und vorab gebundenen Grenzwerten |
| M4 Gesamtergebnis und Review | Hauptagent koordiniert; Captureowner liefert; unabhängiger Reviewer prüft | eingefrorener vollständiger Build/Daten/Mapping/Fixture | startbare App, externe Anleitung, Quellenmanifest, Video/Bilder, Messwerte, A01–A16-Befunde | Kit `report-check` + unabhängiger Daten-/Bildreview; Revision nach Fix erneut einfrieren | offen; danach Ende Kit 1 |

Keine zusätzlichen Produktanforderungen aus dieser Vorlage ableiten.
