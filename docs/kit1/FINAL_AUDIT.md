# Kit 1 — historischer Vollständigkeits- und Widerspruchsaudit (v2)

> Historischer Prüfstand. Aktueller geografischer Umfang: [REGION_SCOPE_UPDATE](REGION_SCOPE_UPDATE.md).

**Stand:** 25.10.2026 · **Kit:** `kit1-landscape-v2` · **Laufverträge:** `kit1-ops-v2`.  
**Status:** Alle fünf Befunde geschlossen; Korrekturen `implementiert`, eigene
gezielte Tests und unabhängige Wiederprüfung durch zwei getrennte Subagents
`validiert` (25.10.2026). Geltungsbereich: Kit-Verträge und Dokumentkonsistenz,
keine Produkt-, Geschichts- oder Leistungsvalidierung. Kein Produktcode.

Dieser abgeschlossene Audit gilt für den damaligen v2-Stand. Die spätere
Tile-Erweiterung v3 wird separat in [TILE_UPDATE.md](TILE_UPDATE.md) geprüft.

## Auftrag und Abdeckung

Geprüft wird das angepasste Kit gegen das Originalarchiv und die bestätigten
Interviewentscheidungen. Die 224 unveränderten Archivpfade mit Hash/Disposition
stehen in REFERENCE_MAP.json. Der neue Auftrag erweitert den Landschaftsscope
nicht: ganze Erde, natürliche Landschaft, erlaubte Maßstabsanpassung, feste
Isometrie, stufenloser Zoom, Urbek-Formen, natürliche warme Sommerdarstellung.
Historische Korrekturen bleiben offen. Referenzbilder und ihre Zuordnung wurden
vom Nutzer akzeptiert; die tatsächliche Produktgrafik wurde damit nicht abgenommen.

## Befunde und gezielte Korrekturen

| Befund | Korrektur | Eigene Prüfung |
|---|---|---|
| Bildresiduen ohne gebundenen Kamera-/Viewport-/Transformzustand; nur Zoomendpunkte statt tatsächlichem Weg | Fixture-View-Zustände, Pan-Ziel, Pixelraum, Transformhash/Sollmethode, stabile Waypoint-IDs, Reihenfolge/Timing/Fixpunktprobe; Rückkehr zum Anfangszustand | Positiver Mock-Vertrag; falsches Ziel/Viewport/State-ID, übersprungener Wegpunkt, Timing, Transform-/Methodenfehler und fehlender Pan werden abgewiesen |
| A02 akzeptierte beliebige Coverage-Datei ohne globalen Vertrag | coverage.schema.json mit globalem Bezugsraum, Land/Ozean mit Rollen→Quellenbindung und Kompositbelegen, NoData, Datumsgrenze/Polräumen, Aggregations-/Prüfbelegen und direkter A02-Verknüpfung | Offene NoData, unvollständige Abdeckung, fehlende/ungültige Polar-/Quellenbindung, Wasserquelle als falsche Landrolle, synthetische Coverage und fehlender A02-Link werden abgewiesen |
| Kultivierte/verwaltete Landcoverklassen nicht explizit ausgeschlossen | Datenprozess/A10 plus maschinenlesbare Klassenbehandlung für Felder, Plantagen, verwaltete Flächen, Bebauung und Verkehr; Maskierung/Abstraktion ohne sichtbare Feldmuster, Plantagenreihen, Zäune oder Bewirtschaftungsstrukturen; keine behauptete historische Renaturierung | Unaufgelöste/fehlende Klassenzuordnung und ungeklärter natürlicher Endzustand werden abgewiesen |
| Referenz-JPG oder eigene Bildprobe konnte von dokumentiertem Hash abweichen | self-check/package verifizieren alle lokalen Bild-Provenienzmanifeste | Beide Bildtypen in temporärer Kitkopie manipuliert: Selbstprüfung und Verpackung scheitern |
| verify-package akzeptierte Manifest-only/leeres/falsch versioniertes ZIP | Manifeststruktur, bekannte Version, Pflichtdateien und eingepacktes Inhaltsinventar gegen Paketmanifest prüfen | Leeres/falsches Manifest, Versionsfehler und Inventardrift trotz neu berechnetem Dateihash werden abgewiesen |

Die Tests verwenden ausdrücklich erfundene temporäre Mock-Belege. Sie prüfen,
dass der Vertrag akzeptiert oder blockiert, und werden nicht als echte
Landschafts-/Screenshot-/Leistungsnachweise ausgegeben. Eigener Teststand:
25 Unit-Tests erfolgreich; Befehle und tatsächliche Ausgaben in
[evidence/kit-checks.json](evidence/kit-checks.json).

## Was dieser Audit nicht behauptet

- Es existiert weiterhin kein Kit-1-Renderer, keine produktive Geodatenpipeline
  und kein tatsächlicher globaler Lauf. Adapter-/Prozessvorlagen sind vorbereitet.
- Ein korrekt ausgefülltes Coverage-Dokument beweist nicht selbst die geografische
  Wahrheit. Die referenzierten Inventare, Methoden und Aufnahmen müssen unabhängig
  geprüft werden; das Kit berechnet keine globalen Flächen aus Geodaten.
- Transformdateien werden gebunden/gehasht, nicht als Engineprojektion ausgeführt.
  Die unabhängige Prüfung muss Sollmethode, Originaldaten und reale Bildprobe
  zusammenführen. Erfundene als echt deklarierte Dateien bleiben semantisch
  nicht allein durch einen Strukturprüfer erkennbar.
- Screenshots sind Stil-/Kompositionsreferenzen, kein Beweis für kontinuierlichen
  Zoom, historische Genauigkeit, globale Abdeckung oder Leistungsfähigkeit.
- Datensatz, Engine, Mapping, Hardware und quantitative Schwellen bleiben vor
  Umsetzung zu begründen; bestehende Grafikentscheidungen werden nicht neu befragt.

## Abschließende unabhängige Wiederprüfung

Am 25.10.2026 prüften zwei unabhängig beauftragte Subagents die Korrekturen:
Kamera-/Waypoint-/Coverage-/Landcoververträge einerseits sowie Referenzhashbindung,
Paketprüfung, Evidence und Statuskonsistenz andererseits. Alle fünf Befunde sind
geschlossen; der aktuelle Werkzeugtestlauf umfasst 25 erfolgreiche Tests.
Keine offenen Korrekturbefunde aus diesem Audit. Die oben genannten Grenzen und
noch nicht implementierten Produktbestandteile bleiben ausdrücklich bestehen.
