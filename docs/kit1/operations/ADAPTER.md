# Vertrag für den späteren Grafik-/Datenadapter

Referenz: `kit1-landscape-v5`, `spezifiziert`, **Adapter nicht implementiert**.
`templates/config.json` ist eine konkrete Bindungsvorlage, kein ausführbarer
Renderer. Die Kit-Werkzeuge lesen sie, führen ihre Befehle aber nicht aus.

## Eingaben und Ausgaben

| Vorgang | Eingabe | geforderte spätere Ausgabe |
|---|---|---|
| Datenaufbereitung | `sources.json`, dokumentierte Parameter/Quellhashes | versioniertes abgeleitetes Manifest, Kachel-/Abdeckungsinventar, Ausschlussbericht |
| Build | festgehaltene Produktrevision + gebundener Stack | startbares Artefakt, tatsächlicher Buildbefehl/Exitcode/Log |
| Start | Buildrevision + Konfig + Seed + feste Licht-/Stilparameter | erkundbare Welt; kein autonomes Umschalten auf ein anderes Projekt |
| Prüffahrt/Capture | `fixture.json`, Build- und Datenrevision | kontinuierliche Aufnahme, Standbilder, `telemetry.json`, `report.json` |

Befehle werden als Argumentlisten gespeichert, nicht als Shell-Zeichenketten.
Der zuständige Agent setzt sie nach späterer Autorisierung mit dem passenden
Werkzeug um, prüft Working Directory/Projektidentität und erhält Job-ID/Exitcode.
Keine API-Schlüssel in Argumenten, Logs oder Konfigdateien. Geheimnisse gehören
nur in vorhandene sichere Kontobindungen; das Kit kopiert keine Zugangsdaten.

## Geografischer Vertrag

Jeder Fixpunkt besitzt stabile ID, Quelle/Version und geodätische Position.
Die Datenaufbereitung dokumentiert CRS, Achsenreihenfolge, Höhendatum, Einheiten
und Transformation. Die Renderabbildung besitzt eigene ID/Version und Parameter.
Eine Probe enthält geografische Quellposition, Zoomposition, erwartete Position
**laut dieser Abbildung** und tatsächlich projizierte Position. Residuen werden
in dokumentierten Bild-/Render-Einheiten gemessen. Reale Kilometer dürfen nicht
stillschweigend als Renderkilometer vorausgesetzt werden.

Fixpunkte bleiben dieselben, auch wenn LOD, gebundene Renderabflachung oder Detaildichte
wechseln. Der Adapter exportiert Quellidentität und Mappingrevision für jeden
Capture. Er behandelt Kartenrand/Kartenränder/Küsten/Tile-Nähte explizit, ohne dass dieses
Kit schon eine Projektion auswählt. Rückfahrt und Wiederbesuch verwenden dieselben
Daten-/Seed-/Mappingrevisionen. LOD-Schwellen sind keine neuen Ansichtsmodi.

## Telemetrievertrag

`schemas/telemetry.schema.json` beschreibt die Datenausgabe: Zeit relativ zum
Lauf, Zoomposition, Kameraausrichtung, Framezeit, Speicher, Fixpunktbeobachtungen.
`t_ms` ist monoton; Zoom liegt auf einer dokumentierten normalisierten Skala von
0 (Gesamtübersicht) bis 1 (Nahziel). Diese Skala schreibt keinen physischen Maßstab vor.
Leistungsaufnahmen erfassen Samplingmethode und Warmup im Laufprotokoll. Rohwerte
bleiben erhalten; Perzentile, Spitzen und Ladepausen werden daraus abgeleitet.

Der Fixture-Adapter muss Kameraeinstellungen tatsächlich lesen; eine nur in der
Konfig behauptete Kamerafahrt genügt nicht. Captures stammen aus dem echten
Anwendungsframebuffer inklusive sichtbarer Fehler, nicht aus Ersatzrenders.
Form-/Dateiprüfungen des Kits ersetzen weder einen echten Adapter noch visuelle
Prüfung. Keine Dummy-Ausgabe darf Produktabnahme bestehen.

## Reproduzierbarer Bildraumvertrag (`kit1-ops-v5`)

Fixture-Koordinaten sind explizit EPSG:4326 in Längen-/Breitengraden; originale
Quell-CRS bleiben im Quellenmanifest und ihre Normalisierung wird protokolliert.
`view_states` definiert kanonische Sollzustände mit ID, Mappingrevision,
geografischem Kameraziel (Pan), normalisiertem Zoom, Viewportbreite/-höhe in
Bildpixeln, Pixeldichtefaktor und Ursprung links oben. Dazu gehört ein gehashtes
`transform`-Artefakt mit tatsächlichen Projektions-/Mapping-/Reliefübergangsparametern.
Das Format dieses Artefakts bestimmt der später gebundene Adapter; der Kitprüfer
implementiert oder interpretiert keine Engineprojektion.

`expected_position_method` bindet eine gehashte Beschreibung/Implementierungs-
referenz der Sollprojektion. Sie muss Ableitung und Version nennen; Sollwerte
nicht einfach aus den beobachteten Rendererwerten kopieren. Pixelresiduen gelten
nur für denselben dokumentierten Bildraum, nicht als Abstand in realen Kilometern.

Jeder Fixture-Wegpunkt hat stabile ID, Zeit, Fixpunkt-ID und `view_state_id`.
Die Route enthält Gesamtübersicht → nah → Gesamtübersicht, mindestens zwei geografische Kameraziele
und Rückkehr zum identischen Anfangszustand. Timingtoleranz wird vor dem Lauf
gebunden. Telemetrie exportiert tatsächlichen `view_state` und `waypoint_id` bei
jedem erreichten Wegpunkt. Zusätzliche kontinuierliche Samples tragen
`waypoint_id: null`, aber ebenfalls den vollständigen Zustand samt Transformhash.
Der Prüfer kontrolliert alle vorgesehenen Wegpunkte in Reihenfolge, Zeitfenster,
Zustandsidentität und Fixpunktbeobachtung; Endzoom und Laufdauer allein reichen
nicht. Er prüft auch die tatsächlichen Transformdateien und die Sollmethoden-Datei.
Zwischenschritte und visuelle Kontinuität bleiben zusätzlich im Video zu prüfen.

Die Viewport-/Transformfelder sind **Belegverträge**, keine neue Wahl von Engine,
Projektion oder Eins-zu-eins-Maßstab. Die erlaubte zoomabhängige Darstellung bleibt
bestehen. Erfundenes JSON kann weiterhin nicht automatisch als echt erkannt
werden; unabhängige Prüfung muss Zustandsdaten und Aufnahme miteinander abgleichen.

## Interner Tilevertrag (ops-v5)

Der spätere Adapter liest `config.tiles` und exportiert interne `tiles.json`-Probes
gemäß [TILES](TILES.md). Ein Probe verknüpft tatsächlichen Kamera-/Viewport-/
Transformzustand, Quellanker, kanonische Tile-ID, logischen Index und Zellmaße.
Keine Modusfolge, Themenquelle, Picking-, Auswahl- oder GUI-Funktion gehört zum
aktuellen Adapterauftrag. Ausgaben sind externe Belegdateien, keine Overlays.

## Zoomgebundene Kamera und Geoableitung (ops-v5)

`fixture.camera` bindet feste Azimutrichtung, Fern-/Nahelevation und ein gehashtes
kontinuierliches Übergangsprofil; freie Rotation bleibt ausgeschlossen. Jeder
`view_state`/Sample liefert tatsächliche Elevation, Azimut, `relief_weight` und
Profilreferenz. Fernendpunkt hat `relief_weight=0`, Nahendpunkt 1; Zwischenzustände
und Kameraneigung folgen dem begründeten Profil. Ein Gewicht ist keine freie
Höhenüberhöhung des kanonischen Modells. Die Fixture muss mindestens einen
Zwischenzoom beobachten; für visuelle Abnahme werden kontinuierliche Samples
und ein ungeschnittenes Video benötigt, nicht nur drei Standbilder.

`config.geodata_policy_path` bindet den vor der Prüfung festgelegten Policyvertrag.
`derivation.json` enthält die tatsächlichen Ableitungsbelege für A16. Siehe
[GENERALIZATION](GENERALIZATION.md). Der Kitprüfer wendet keine Projektion,
Meshvereinfachung oder Geländeinterpolation an. Er prüft Hashes, Bindungen,
Abdeckung deklarierter Messreihen, Stichprobenmaxima gegen Budgets und gemeldete
unerwartete Topologieänderungen. Geometrische Wahrheit bleibt unabhängig zu prüfen.

## Read-only Snapshotgrenze

Die spätere Simulations-/Renderkopplung und der Kit-1-Stand ohne Simulation
sind in [`RENDERING.md`](RENDERING.md) konkretisiert. Der Adapter bindet
`schema_version`, `simulation_revision`, monotonen `tick_id`,
`world_revision` und Daten-/Mappingrevision getrennt. Er liefert für einen
Capture die vollständige Snapshotrevision und den LOD-/Blockbestand mit aus.
Renderer liest ausschließlich einen atomar veröffentlichten unveränderlichen
Snapshot und blockiert keinen Simulationstick. Kit 1 erzeugt bis dahin einen
versionierten read-only `WorldRenderSnapshot` aus seinem Datenpaket; dies
fordert keine Simulation oder FFI-Implementation.

## Gebietsbindung v5

Vor Verarbeitung [REGION](REGION.md) lesen und `config.region_path` binden.
Die tatsächliche Regiondatei gehört gehasht zum Report; A02 verbindet sie mit
Coverage. Fixture und Ableitung referenzieren dieselbe Revision. Umfang ist
Reichsrahmen 117 + gesamter Mittelmeerraum + England/nördlicher Kontext, nicht
die gesamte Erde und nicht nur Europa. Landschaftsreferenz bleibt 180 n. Chr.
