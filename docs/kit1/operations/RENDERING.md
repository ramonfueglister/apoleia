# Spätere Rendering-Implementierungsbasis

**Referenz:** `kit1-landscape-v5` / `kit1-rendering-v4` · **Status:** `spezifiziert` als Plan und Verträge; Renderer und Messwerte `offen`.

Dieses Dokument konkretisiert die spätere Implementierung auf Grundlage von
[`RENDERING_RESEARCH.md`](../RENDERING_RESEARCH.md). Es bindet weder Engine,
API, konkrete Datenquelle noch Produktplattform. „Ready“ bedeutet hier:
Arbeitsfolge, Daten-/Snapshot-Grenzen, Lebenszyklus, Vergleichsverfahren und
Abnahmekriterien sind für eine spätere technische Auswahl dokumentiert. Es
bedeutet nicht, dass ein Renderer gebaut, eine Implementierung validiert oder
Plattformleistung bestätigt wurde. Mac-Erstprüfung ist vorgesehen; iPad bleibt
optional. Windows und Linux sind gewünschte, deutlich spätere Desktop-Ziele und
gehören nicht zum aktuellen Auftrag. Der Rust-Kern soll plattformneutral bleiben;
Hostadapter und Renderer werden getrennt. Metal ist ein optionaler Apple-Pfad,
persistente Daten- und Renderer-Schnittstellen dürfen keine Metal-Typen voraussetzen.
GPU-Funktionen sind zur Laufzeit abzufragen und mit portablen Fallbacks zu versehen.
Godot ist die vom Nutzer genannte App-Engine. Die Rust-/Rendererintegration und
Runtime-Version sind offen; kein Projekt/keine Runtime liegt vor, und Windows- /
Linux-Verhalten wurde nicht geprüft.

## Datenpipeline und Artefakte

1. **Unveränderte Eingaben:** Quellenmanifest bindet Provider, Datensatzname,
   feste Version/Datum, Abruf-URL, Lizenz, CRS/Höhendatum, Auflösung,
   Abdeckung und SHA-256 jedes Originalobjekts. Veränderliche `latest/current`
   URLs allein sind keine Version.
2. **Kanonisches Geodatenprodukt:** Projektion/Modellraum, Einheiten,
   Geometrie- und Rasterrevision, regionale Maske, Höhen/Wasser/Landcover,
   NoData-Entscheidungen und Generalisierungspolitik sind reproduzierbar aus
   unveränderten Eingaben ableitbar. Jede Ableitung bindet Tool-/Formatversion,
   Parameter, Seed soweit vorhanden, Eingangs- und Ausgangshashes. Keine
   zoomabhängig neu erzeugte Geografie.
3. **Rendererpaket:** adressierbare räumliche Blöcke mit Metadatenmanifest,
   Quellen-/Mappingrevision, Bounds, Eltern-/Kindbeziehungen, pro-LOD
   Fehlerbeleg, Payloadtyp, Dimensionen, Kodierung und Prüfsumme. Gemeinsame
   Grenzen referenzieren identische kanonische Randdaten oder eine explizite
   Nahtregel. Paketformat/Kompression bleibt eine prototypisch zu messende
   technische Auswahl; Anbieter-Downloadkacheln werden nicht als logische
   Welt-Tiles übernommen.
4. **Schemaänderung:** manifeste und Payload-Schemata tragen `schema_version`
   und `dataset_revision`; Breaking Change erzeugt eine neue Schema-
  Hauptversion. Alte Läufe bleiben mit ihren Hashes lesbar. Ein Build bindet
   exakte Daten-, Mapping-, Kamera- und Rendererrevisionen.

Die Quelle→Modell→Render-Trennung und Fehlerbudgets folgen
[`GENERALIZATION.md`](GENERALIZATION.md); regionale Extents aus
[`REGION.md`](REGION.md); logische Tile-IDs aus [`TILES.md`](TILES.md).
Logische Tiles, Datenblöcke, LOD-Patches und GPU-/Sparse-Texture-Pages sind
unterschiedliche Adressräume. Eine versionierte Zuordnung verbindet sie,
ohne gleiche Größe, Form oder Lebensdauer zu erzwingen.

## LOD, Streaming und Kamera-Kontinuität

- Für die erste vergleichbare Implementierung ist ein **vorberechneter,
  hierarchischer räumlicher Blockbaum** mit groben Elternrepräsentationen die
  Baseline. Sichtbarkeit und Detail wählen nach gebundenem Bildschirmfehler
  und Sichtvolumen. Das ist ein eigener Implementierungsvorschlag, keine
  Paradox-Technikbehauptung.
- Clipmaps sind ein Kandidat für den nahen Höhenfeldbereich, falls die Messung
  bei kontinuierlicher Kamerabewegung zeigt, dass blockbasierte LOD zu viele
  Draw-/Nahtkosten hat. Kein Clipmap- oder Hybrid-Pflichtstack vor dem
  Vergleich.
- LOD-Nachbarn müssen kompatible Kantenstufen halten; Übergang/Geomorphing,
  Hysterese gegen Flattern und Nahtbehandlung sind Teil des Messprotokolls.
  Küsten, Wasserläufe und geschützte Reliefmerkmale werden gegen A16 geprüft.
- Far-/Near-Kamera und Zwischenzustände kommen aus demselben versionierten
  Zoomprofil aus `GENERALIZATION.md`. Sichtbare Features behalten kanonische
  Quell-/Feature-ID; Detailauslassung darf keine Positionsverschiebung oder
  neue Geografie erzeugen.
- Priorität: sichtbare Lücken nicht zeigen. Während höherer Detailstufe lädt,
  wird ein bereits verfügbarer Elternblock angezeigt; beim Fertigstellen wird
  am gebundenen Übergang ausgetauscht. Fehlender Elterndatensatz ist ein
  Laufzeitfehler, keine leere Fläche.

## Ressourcenlebenszyklus

Die spätere Runtime setzt einen festen Zustand je Block um:

`unbekannt → angefordert → gelesen → CPU-dekodiert → Upload vorgemerkt →
GPU-resident → ersetzbar → freigegeben`; Fehlerzustände gehen nach `fallback`
oder `quarantäne`.

Ein beschädigter Hash oder inkompatible Payload wandert blockweise in
`quarantäne`; ein gültiger Elternblock bleibt als Fallback renderbar, aber der
Lauf besteht die Integritätsabnahme nicht. Eine beschädigte Manifestwurzel
oder ein fehlender erforderlicher Fallback macht die Datasetrevision
nicht ladbar und den Lauf fatal. Ein transienter Lese-/Decodefehler darf
begrenzt wiederholt werden; Versuchszahl,
Wartezeit und Ergebnis werden protokolliert. Fehlender Kindblock mit gültigem
Elternblock bleibt sichtbar als `fallback` und wird erneut angefordert. Fehlt
auch der benötigte Wurzel-/Eltern-Fallback, ist das Gebiet beim Start nicht
vollständig darstellbar und der Lauf meldet einen fatalen Datenfehler statt
stilles NoData. Ein GPU-Uploadfehler lässt den CPU-Payload und Elternfallback
erhalten, setzt den Block zurück in Upload-Warteschlange; nach begrenzten
Fehlversuchen wird der Lauf mit sichtbarer Qualitätsdegradation beendet, ohne
die Revision als bestanden zu melden. Bei Cache-Druck bleiben aktuell
sichtbare Blöcke, Wurzel-/Eltern-Fallbacks und laufende GPU-Nutzung gepinnt;
älteste nicht sichtbare Detailblöcke werden nach GPU-Fence zuerst freigegeben.
Kameraänderung macht unbenutzte Requests abbrechbar. Dataset-/Mappingwechsel
startet einen getrennten Cachegeneration-Zweig; alte Handles werden erst nach
dem letzten Frame-Fence freigegeben. Reservierte Bytes/Handles werden auch in
Abbruch- und Fehlerpfaden freigegeben.

Der Kamera-Thread priorisiert Requests nach projiziertem Bildschirmfehler
(sichtbar zuerst, danach erwartete visuelle Fehlerreduktion und
Bewegungsrichtung/Vorhersage). Eine Aging-Komponente verhindert, dass
Requests verhungern; Request-Alter und sichtbare Verspätung werden gemessen.
Ein residenter Elternblock bleibt bis zur erfolgreichen Kind-Installation als
Fallback verfügbar. Worker lesen, verifizieren Hashes und dekodieren außerhalb
des Renderloops. Uploads werden asynchron und pro Frame/Zeitfenster byte- und
zeitbegrenzt geplant; konkrete Grenzwerte bleiben bis Messungen auf gebundener
Hardware `offen`. GPU-Handles werden
erst nach Abschluss der Nutzung freigegeben. Cache-Eviction berücksichtigt
Eltern/Fallbacks und aktuelle Frames; Rückfahrt/erneuter Besuch darf keine
Identitätsänderung bewirken. Messung erfasst Warteschlangenalter, Bytes,
Uploadgrenzen, Cache-Treffer, Evictions, Decode-/IO-Latenz und sichtbar
verspätete Blöcke.

Apple Metal bietet Sparse-Texture-Streaming und asynchrone Ladebeispiele, aber
Sparse Textures sind optional und müssen zur Laufzeit erkannt werden. Die
Apple Feature-Set-Tabelle vom 21.05.2026 weist Featureunterschiede nach
GPU-Familie aus; Metal 4-placement-sparse kann daher kein Basispfad für
unbekannte Apple-Zielgeräte sein. Gemeinsamer Fallback ist ein begrenzter
normaler Ressourcen-Cache mit grober Elternrepräsentation. `memoryless`/Tile
Memory bleibt kurzlebigem Renderpass-Zwischenspeicher vorbehalten, nie
persistenten Landschaftsdaten. Apple-Funktionen sind optionale Optimierungen,
kein plattformübergreifender Datenvertrag.

## Pipeline-Hitches und Godot-Vertikalpfad

Pipeline-/Shader-Kompilierung wird als mögliche Hitch-Quelle separat erfasst.
Vergleichsläufe unterscheiden kalten und warmen Treiber-/Enginecache und
markieren erstmals gezeichnete Material-/LOD-Varianten sowie spät gestreamte
Mesh-/Materialkombinationen. Pro Frame werden max, p95 und p99 der Framezeit
mit Pipeline-Erstellungsereignissen/-Zählern und Lade-/Uploadereignissen
zeitlich korreliert; Rohdaten und Cachezustand bleiben Teil des Berichts.
Godot dokumentiert für Forward+ und Mobile Pipeline-Vorkompilierung, weist
aber auf Fälle hin, in denen zur Laufzeit geladene Inhalte weiterhin
Kompilierung auslösen können. Vorwärmen benötigter Kombinationen und begrenzte
Material-/Shader-Varianten sind Prototypvorschläge, keine Garantie und kein
Versprechen, Treiber-Pipelines hardwareunabhängig vorab zu backen.

Godot ist Zielengine für den späteren App-Vertikalpfad; Runtime-Version und
Integrationsvertrag bleiben offen. Zuerst wird der engineeigene globale
Renderpfad mit Terrain-LOD, Streaming und einem Materialwechsel geprüft. Ein
lokaler `RenderingDevice`-Pfad ist eine separate Low-Level-Option mit eigener
Ressourcen-/Synchronisationsverantwortung; er ist nicht als Einhängen eigener
GPU-Arbeit in Godots globale Szenenpipeline anzunehmen. Die konkrete Eignung
ist mit der gebundenen Godot-Version zu prüfen.

Derselbe repräsentative Datensatz, Kamerapfad, Material-/LOD-Änderungen und
Upload-Last werden mindestens mit Forward+ und Mobile verglichen, soweit beide
auf der gebundenen Umgebung verfügbar sind. Bildqualität, Pipeline-Erstellungen,
Frame max/p95/p99, CPU/GPU-Zeit und Streaminglatenz werden gemeinsam
ausgewertet. iPad ist für diesen Meilenstein kein Pflichtgerät; Mac ist die
vorgesehene Erstprüfung, Windows/Linux bleiben spätere Ziele. GPU-driven
Sichtmengen-/Draw-Optimierungen folgen nur bei gemessenem CPU-Submission- oder
Sichtmengenengpass. Daraus folgt keine Zusage einer Mesh-Shader-API.

## Verbindliche Kern-/Grafikgrenze

Der spätere Wirtschaftskern ist ein headlesses, plattformneutrales Rust-Modul
und baut/läuft ohne Godot, Grafik- oder Render-API. Godot, Hostadapter und
Renderer erhalten keinen direkten mutierbaren Zugriff auf Simulationszustand.
Sie lesen ausschließlich vollständig veröffentlichte, versionierte und
unveränderliche Snapshots. Jede Wirkung auf die Simulation wird als expliziter,
typisierter Command über die definierte Adaptergrenze eingereicht und im Kern
validiert; Annahme/Ablehnung und Ergebnis sind nachvollziehbar. Renderloop,
Kamera, GPU- und Cachezustand sind keine alternative Wahrheit für Welt,
Wirtschaft oder Persistenz.

Simulations-Ticks werden unabhängig vom Renderframe-Takt vorangetrieben. Ein
Frame darf denselben Snapshot wiederverwenden oder neuere Ticks überspringen;
die Simulation tickt weder pro Frame noch wartet sie auf VSync, Renderer, Datei-
IO oder GPU.

## Simulation-/Renderer-Snapshotgrenze

Kit 1 enthält keine Simulation und fordert jetzt keine Wirtschaftscode- oder
FFI-Arbeit. Für spätere Kopplung gilt als Schnittstellenentwurf:

- Simulation veröffentlicht atomar einen unveränderlichen `RenderSnapshot`
  mit `schema_version`, `simulation_revision`, monotonem `tick_id`,
  `world_revision`, Renderrelevanten stabilen IDs/Komponenten und
  Änderungssatz oder Vollzustand. Asset-/Geodatenrevisionen sind separate
  Referenzen, nicht heimlich in der Tick-Version kodiert.
- `RenderSnapshot` enthält Header, stabile IDs und nur renderrelevante Werte:
  kanonische Region-/Tile-/Feature-ID, Featurezustand (z.B. Sichtbarkeit oder
  Stilklasse), Transform-/Kameraprofilreferenz und optionale Änderungsreferenz.
  Große Geometrie-/Texturpayloads bleiben im versionierten Datenpaket und
  werden per Hash-/Asset-ID referenziert, nicht pro Tick kopiert.
- Publisher baut einen vollständigen Snapshot abseits der Leseseite und
  veröffentlicht einen unveränderlichen Handle atomar erst nach Abschluss.
  Renderer hält den Handle bis zum Frameende; Publisher darf ihn nicht
  mutieren/freigeben. Es existiert stets ein vollständiger letzter Stand.
- Snapshots sind selbständig vollständig oder deklarieren `base_tick_id` und
  eine lückenlos anwendbare Änderungsfolge. Renderer darf Zwischenstände
  überspringen, wenn er einen vollständigen neueren Stand erhält; bei
  delta-only darf er keine Basissequenz überspringen und fordert bei Lücke
  eine Vollsynchronisierung an. Rückstau darf Publisher nicht am Simulations-
  tick blockieren; ältere noch nicht gelesene Vollsnapshots dürfen ersetzt
  werden. Tick- und Frame-Zeitlinien sowie übersprungene IDs werden gemessen.
- Übergabe und Delta-Puffer sind begrenzt. Der Renderer kann den neuesten
  vollständigen gültigen Snapshot übernehmen; noch nicht konsumierte ältere
  Vollsnapshots dürfen ersetzt werden. Falls Deltaübertragung genutzt wird,
  sind Basis, Reihenfolge und Sequenzlücken explizit. Bei fehlender Basis,
  Lücke oder Versions-/Hashkonflikt werden Deltas verworfen, der letzte gültige
  Snapshot bleibt darstellbar und eine Vollsynchronisierung wird angefordert.
  Es gibt keine partielle Anwendung auf eine falsche Basis. Queuegröße,
  Rückstau, Drops und Resync werden messbar protokolliert.
- Die konkrete bounded-queue/Repräsentation wird später nach Host-/Stackwahl
  festgelegt; ihre Semantik ist verbindlich: Publisher wartet nicht auf den
  Renderer und hält Simulations-Ticks auch bei langsamem Rendern/IO/GPU nicht
  an. Absolute Laufzeit- oder Framerategarantien folgen daraus nicht.
- Konkrete Rust-Referenzzählung, Speicherrepräsentation und Thread-/FFI-
  Übertragungsform bleiben an Host-/Stack-Auswahl gebunden; Vertrag verlangt
  atomare Publikation, stabile IDs, unveränderliche Lesesicht und
  reproduzierbare Snapshotzuordnung in Captures.
- Für die derzeitige Landschaft ohne Simulation wird ein äquivalenter
  versionierter `WorldRenderSnapshot` aus dem Datenpaket erzeugt. Das ist ein
  Read-only Renderinput und kein vorweggenommener Wirtschaftsstatusvertrag.

Spätere Abnahme verlangt einen headlessen Rust-Smoke-Lauf ohne Godot/Fenster/
Grafik-API mit Command-Eingabe, Tickfortschritt und reproduzierbarem
Zustands-/Snapshotoutput. Boundary-Checks belegen Command-Validierung,
Snapshot-Unveränderlichkeit, Delta-Lücken samt Vollsynchronisierung sowie
begrenzten Rückstau bei absichtlich langsamem Konsumenten. Dies sind zukünftige
Prüfkriterien, keine implementierten Tests oder Leistungszusage.

## Spätere Animationsverträge (v4)

Diese Verträge gelten für spätere animierte Inhalte und erweitern weder die
aktuelle statische Landschaft noch die laufende Wirtschaftsimplementierung.
Godot ist Zielengine; Mac ist die Erstprüfung, Windows/Linux sind spätere Ziele,
iPad bleibt optional. Daraus folgt keine Leistungszusage.

1. **Zeit und Interpolation.** Jeder Snapshot führt `tick_id`, kanonische
   Simulationszeit und Tickdauer; die Präsentation besitzt eine eigene monotone
   Visual Clock. Zwischen zwei empfangenen Snapshots darf nur innerhalb ihrer
   bekannten Simulationszeiten interpoliert werden. Bei Pause frieren
   simgebundene Animationen ein; UI und Kamera bleiben bedienbar. Zeitraffer
   beschleunigt Simulationszeit, nicht die Tickrate pro Frame. Übersprungene
   vollständige Snapshots werden übersprungen; Delta-Lücken erzwingen Resync.
   Ein Zeit-/Revisionssprung verwirft den Interpolationspuffer und zeigt den
   letzten gültigen Zustand bis zum Resync. Frames führen keine Wirtschaftslogik
   aus und Animation erfindet keine zukünftigen autoritativen Zustände.
   Dekorative Animationen (z.B. Wind/Wasser) folgen der Visual Clock, laufen
   während Simulationpause weiter und holen nach App-Suspend keinen Rückstand
   nach.
2. **Autorität und Effekte.** Simulationsgetriebene Darstellung (später etwa
   Baufortschritt) bildet ausschließlich kanonische Rust-Zustände ab. Wind,
   Wasser und Routenvisualisierung sind rein dekorativ, solange sie nicht als
   Snapshotzustand geliefert werden. Visuelle oder physikalische Effekte,
   Partikel und Scene-Objekte senden keine Commands und verändern weder
   Simulation noch kanonische Welt.
3. **Identität und Lebenszyklus.** Stateful Animation bindet stabile Entity-/
   Feature-ID plus Seed und Phase, unabhängig von LOD, Stream-Unload/Reload und
   Scene-Objektlebensdauer. Ressourcen werden nach bestehendem Block-/GPU-Fence-
   Lebenszyklus freigegeben. Scene-Objekte dürfen keinen kanonischen Zustand
   besitzen. Bei Entity-Revisionwechsel wird Zustand neu gebunden; bei Resync
   wird er aus dem Snapshot rekonstruiert, ungültiger Interpolations-/Effektzustand
   verworfen. Reset-/Resume-Regeln und abgeleitete Phasen werden im Laufbericht
   reproduzierbar gebunden.
4. **Animationsbudget und Messung.** Spätere Abnahme bindet LOD-, Update-,
   Offscreen-, Partikel- und Instanzbudgets sowie deren Degradationsreihenfolge.
   Numerische Grenzen bleiben `offen` bis zur Messung. Eine animierte Testregion
   wird kalt/warm, über Zoomstufen und mit Streaming geprüft; erfasst werden
   Framezeitverteilungen, Animations-/Updatezeit, aktive Instanzen/Partikel,
   Speicher, Pop-in und sichtbare Verspätung. Darstellungsqualität darf bei
   Budgetdruck reduziert werden, niemals Kernzustand oder Tickfortschritt.

## Prototypvergleich und Messplan

Baseline ist derselbe repräsentative Ausschnitt, Dataset-Hash, Kameraweg,
Viewport, Qualitätsprofil und Gerät. Verglichen werden mindestens:
hierarchische Blöcke; Clipmaps nur bei passendem Höhenfeld; optionale
GPU-indirekte Sichtmengen-/Draw-Erzeugung nur falls CPU-Submission als Engpass
gemessen wird. Vor Entscheidung werden Auflösung, OS, Build, GPU-Familien und
thermischer Zustand notiert. Metal-Funktionen werden über Laufzeit-Capability-Abfragen gewählt, nicht über
Gerätenamen. Andere Plattformadapter prüfen ihre Fähigkeiten ebenfalls zur
Laufzeit. GPU-driven Rendering ist
eine spätere Optimierungsoption, keine Voraussetzung für den ersten vertikalen
Pfad.

Messläufe übernehmen die Telemetrie aus `ADAPTER.md` und `ACCEPTANCE.md`:
Frame p50/p95/p99/max, GPU-/CPU-Zeiten nach Pass/Phase, Blocklatenz, sichtbare
Fallback-/Fehlstellen, Daten- und Uploadbytes pro Frame, Cache-Hit/Eviction,
Spitzen-RAM/GPU-Allokation, Kaltstart sowie Pan/Zoom/Rückfahrt. A/B-Läufe
nutzen gleiche Fixpunkte, Daten und Tour. Bericht enthält Rohmessungen,
Konfiguration, Hashes und bekannte Abdeckungslücken.

**Vorgeschlagene, noch nicht validierte Arbeitsziele für einen ersten Mac-
Prototyp:** 60 Hz Zielrate bei festgehaltener 1920×1080-Ausgabe (p95 Framezeit
≤16,7 ms; p99 ≤33,3 ms) und null sichtbar unbedeckte Terrainframes auf der
gebundenen Prüftour. Das sind technische Vorschläge für Vergleichbarkeit,
keine Nutzeranforderung oder Gerätegarantie. p95/p99, Qualität, GPU/RAM,
thermische Dauerlast und Datenpaketgröße werden auf konkreter Hardware erst
validiert. Diese Mac-Prototypwerte gelten nicht als Windows-, Linux- oder
iPad-Budget. Spätere Windows-/Linux-Versionen benötigen eigene Zielgeräte,
OS-Bindungen und Messbudgets.

## Etappen und Abnahmekriterien

| Etappe | Ergebnis | Abschlussbedingung |
|---|---|---|
| R0 Plattform-/Datenbindung | Kandidatenstack, Betriebssystem-/GPU-Familien, Datenrevisionen, Lizenz und Modell-/Render-Transform gebunden | Quellen- und Formatmanifest vollständig; offene Zielhardware ausdrücklich markiert |
| R1 Offline-Produkt | Regionale Höhen-/Wasser-/Landcoverableitung und versioniertes Block-/LOD-Inventar | reproduzierbare Ableitung, Hashes, Abdeckung, NoData- und Nahtprüfung; keine ungeklärten Lücken verschwiegen |
| R2 Sichtbarer Vertikalpfad | Godot-Renderpfad mit Terrain-LOD, Streaming, Materialwechsel, Pan und kontinuierlichem Zoom; Forward+/Mobile-Vergleich mit gleichem Workload | gesamter Erkundungspfad; gleiche Geografieanker; kein synchroner IO/Decode im Renderthread; keine sichtbaren Löcher auf Prüftour; dokumentierte Pipeline-/Framezeit-Korrelation |
| R3 Streaming-/Übergangshärtung | Cache, Bildschirmfehler-Priorisierung, Starvation-Schutz, Rückfahrt und LOD-Kanten geprüft | schnelle Zoom/Pan, kalter und warmer Start, spät gestreamte Varianten, Wiederbesuch, Kartenrand/Küste/Naht bestanden; Request-Alter, sichtbare Verspätung und Upload-Budgets gemessen; Grenzwerte bis Gerätemessung offen |
| R4 Vergleich/Abnahme | Baseline und notwendige Alternativen auf dokumentierter Hardware gemessen | Rohmessungen, p95/p99/max, Speicher, Ladeverzug und Bilder eingereicht; vorgeschlagene Ziele pro Zielplattform einzeln als bestanden/fehlend bewertet |

Unabhängige Dokument-/Implementierungsreview bleibt separate Prüfung gemäß
`WORKFLOW.md`. Das Planen/Abnehmen dieser Etappen ändert weder die aktuelle
Wirtschaftsphase noch startet es Kit 1.
