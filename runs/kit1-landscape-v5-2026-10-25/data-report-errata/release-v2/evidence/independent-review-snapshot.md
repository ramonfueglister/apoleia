# Unabhängiger Schlussbefund Kit1

Referenz `kit1-landscape-v5` / `kit1-rendering-v4`,25.10.2026. Produkt und echte
Laufzeitbelege wurden unabhängig geprüft. Eine uneingeschränkte Vollabnahme
wird wegen der ausdrücklich unten genannten Mess-/Bewertungsgrenzen nicht
erteilt. Dieser Bericht ersetzt die älteren Arbeitsmatrizen für die finale
Revision; alte Fehler, Rohdateien und fehlgeschlagene Zwischenstände bleiben
unverändert erhalten.

## Finale Bindung und tatsächlich ausgeführte Prüfung

- Renderer SHA256 `32692e62a00683419f562793b506e7199f871e782cc2ecf7dc07afc7f34d97a5`.
- Daten `landscape-v3`, Manifest SHA256 `edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a`.
- Finale Anwendung `artifacts/Roma Aeterna Final.app`; Inventar79Dateien,
  SHA256 `21f9e5a4ceabe3ee7fc146fdb1ad4474879de451250b2bab685441191c3391d3`.
  Alle79Dateien gegen das tatsächlich gestartete Bundle erneut gehasht:
  **0Abweichungen**. Kein älteres gleichnamiges Paket als Ersatz geprüft.
- Handoff SHA256 `520bbbb688948ac293ee6f74603710204e67b6173d9acdb2868c03b4da9eab5b`;
  sämtliche darin gebundenen Dateien unabhängig nachgehasht:0Abweichungen.
- Prospektive Fixture `39e82d6ace00a399740cab5487634b857f47ddb1db3b37c5662211a9f48b327f`,
  Threshold `7cd7613eaa9f29c125c0792d1631f3296ab62f609b615ed80b4d2d03f7287ee8`.

Das **finale** Bundle wurde selbst über CUA gestartet. Echter Drag
[600,400]→[750,500] verschob den Framebuffer sichtbar150/100UI-Pixel und das
Ziel17.500001907348633°E/39.5°N nach7.694904804229736°E/44.43333435058594°N.
Echter Rückdrag führte zum Ausgangsziel zurück. Wheel-Up/Down änderte Zoom
0→.035→nahe0. Native Ausgangs-/Pan-/Zoomscreenshots tatsächlich angesehen;
kontrolliertes Schließen sicherte `final-bundle-input/runtime.json` mit exakt
derselben finalen RendererSHA. Die kleineren1440×810Bildinhalte im UI-Screenshot
sind skalierte Fensterdarstellung; der exportierte Renderviewport ist1920×1080.
Frühere Formulierungen „1440×810Viewport“ sind insoweit berichtigt.

Die letzte Codeänderung zum bereits real pan-geprüften06d973…-Build besteht
laut unabhängig gelesenem Diff ausschließlich aus unveränderten Float32LE-
Höhenbytes statt zweitem vollständigem Float32Array und einer Zelllesehilfe.
Pan, Seedregeln und3Shader bleiben gleich. Die im finalen Bundle vorhandene
4099-Abfragen-Regressionsprobe wurde unabhängig headless ausgeführt: Exit0,
bitgleiche Source-/Packed-Bilinearabfragen einschließlich1117negativer Werte.
Ein macOS-CA-Zertifikatsdiagnostikeintrag blieb roh erhalten; kein Assertion-
oder Datenfehler. `source-bytes-independent.log`.

## Finale Normalmessungen

Mac/AppleM3Pro, Metal, Godot4.7.2,1920×1080; jeweils48s gleiche Fixture, ohne
Capture. `release-v2-mobile-review.json`, `release-v2-forward-review.json` und
`release-v2-state-timing.json` enthalten eigene Nachrechnungen der Rohdateien.

| Messung | Mobile | Forward+ |
|---|---:|---:|
| p95 / p99 |9.078 /9.515ms|9.386 /10.189ms|
| Peak Prozess-RSS |1859371008B /1773.234375MiB|1831600128B /1746.75MiB|
| Peak Godot GPU-Allokationsanzeige |874.4375MiB|927.671875MiB|
| Größter gemessener Inter-Frame-Wallwert, erster Engine-Delta-Ersatz ausgeschlossen |18.629ms|1224.069ms|
| Roher Maxwert inklusive erstem Delta-Ersatz |141.976667ms|1224.069ms|
| Viewport-CPU Median / Maximum |.188 /.659ms|.175 /1.016ms|
| Frame-Setup-CPU Median / Maximum |.067 /.206ms|.063 /.177ms|
| Maximale Wald-CPU-Arbeit |8.163ms|7.533ms|

Beide erfüllen die vorab gebundenen Ziele p95≤16.7ms,p99≤33.3ms,
RSS≤2048MiB,GPUmonitor≤1024MiB. Der Forward+-Startup-Pipelinespike1.224069s
bleibt ein realer Befund; ein p99-Pass bedeutet keinen Maximalzeitpass. Danach
keine späten Pipelinezähleranstiege. Die alte806ms/11Frames-Waldkaskade ist im
neuen Normalpfad behoben. Bereits beim ersten Zoom>.86 sind in beiden Runs
134/134gewünschteChunks bereit,Queue0; maximal1Chunk/400Kandidaten pro Frame.

GPU-Zeit-API liefert keine validen Messwerte:0gültigeSamples,**null**, nicht0ms.
Per-Pass-Zeiten sind nicht erhoben. GPUmonitor misst Engineallokation, keine
vollständige physische Residency. Gesamte regionale Geodaten sind vor
Erkundung resident; keine laufende Request-/IO-/Blockupload-Streamingengine.
Deren Queue-/Uploadmetriken sind nicht anwendbar, keine gemessenen Nullwerte.
OS-/GPU-Caches wurden nicht global gelöscht; frische Prozesse und tatsächliche
Pipelineereignisse sind belegt, ein universeller „ColdGPU“-Zustand nicht.
Keine Windows-/Linux-/iPad-Leistungszusage.

## Bild-, Geografie- und Übergangsbelege

Finaler Film gleicher Rendererrevision:
`artifacts/runtime/release-v2-mobile-capture/zoom-tour.mp4`, SHA256
`ee4d780e7867dd06833f4bc41732a5fbed9bd169a0961e5a2dd8a593ac9c13e0`.
1031Originalframes/1031Filmframes, Rohdauer48.006078s, keine Queue-Drops;
Rohzeitpunkte streng monoton. VFR-Zeitquantisierung maximal19.612ms.
Startup-Capturegap514.182ms bleibt sichtbar/roh; nach1s maximal58.295ms.
Keine Parallelmessung durch den Prüfer während dieses finalen Captures.

Tatsächlich betrachtet:70Originalbilder in5Kontaktseiten
`release-v2-contact/`, darunter21Bilder in100ms-Schritten am ersten Wald,
sowie verlustfreie1920×1080Zwischen-/Nah-/Rückkehrbilder. Das ist eine
ausdrücklich **stichprobenartige Film-/Originalbildprüfung**, keine Behauptung
kontinuierlicher menschlicher Betrachtung sämtlicher Pixel allerFrames.
`release-v2-film-review.json` bindet Auswahl, Zeitprüfung und Grenzen.

Die frühere dominante rechtwinklige Coverkontraststruktur ist stark reduziert;
natürliche Palette, facettierte Kronenfamilien, Einzelbäume und Gruppen sind
lesbar. Subtile Quellrastergrobheit bleibt. Kein neuer Quelldetailgewinn wird
behauptet. Im dichten Waldübergang gleichmäßiges Einblenden statt eingefrorener
Regenerationsfolge; in betrachteten Frames keine leeren Landschaftsframes,
neuen Risse, Wasserbäume oder alten Küstenstufen. Dünne Flussdarstellung und
native Grobquellen begrenzen die lokale Nahgenauigkeit. Nutzerstilbewertung
bleibt separat und wurde vom Prüfer nicht erteilt.

Neue Normaldaten bestätigen unabhängig8/8exakte Fixture-Viewstates mit einer
Beobachtung je Waypoint; keine Source-/Tile-ID-Abweichungen. Sichtbarer
Source→Render-Ankerrest maximal.655989486px<prospektiv1px; Ownermethode
.656033207px ist separat erhalten, nicht gerundet gleichgesetzt. Unterschied
entsteht durch Floatrepräsentation/Projektionsmethode. Camera3D-/aktiveMesh-
Probes sind CPU-Projektionen, keine Framebuffer-Featureerkennung.

`release-v2-lod-ridge.json` und RohCSV:26tatsächlicheLOD-Inventare,
57617sichtbare korrespondierende Randvertex-/Midpointqueries ohne Skirts,
max0pxNaht;1225sichtbareRidgeprobes,max.283883635pxQuell-/Meshrest.
ProFrame-Bewegungsresiduen mit legitimer Kamerabewegung abgezogen:
.068467677pxMobile/.063923719pxForward<1px. KeinGPU-Vertexreadback und kein
globaler Kammnetzbeweis. Originalfehler protected-ridge-4Ozean bleibt Erratum.
Die vorab quellengewählte separate Positivkontrolle hat1752mLandquelle und
.779290187pxRest<2px; `REGRESSION_DELTA.md` bindet deren echtenGPU-Start/PNG
und beschränkte Morph-/Meshprüfung. Die finale Byteänderung erhält diese Werte.

Alle18459Waldkandidaten beider finaler Normalruns sind in sämtlichen exportierten
Datensatzfeldern exakt gleich zur bereits unabhängig direkt gegen Coverklasse10,
Detailwater0,decodedSDF<-20m,Global18m-Seed/Position/Familie geprüften Regression.
`release-v2-forest-identity.json` und `forest-source-regression.json`.
Keine gemessenen Einzelbaumstandorte oder botanischen Arten behauptet.

## Abschließende A01–A16-Matrix

„Validiert“ bedeutet den jeweils explizit genannten Stichproben-/Plattformumfang,
keine unbegrenzte Welt-/GPU-/Historikgarantie.

| ID | Schlussstatus | Befund |
|---|---|---|
| A01 | validiert | Exaktes finales eigenständig startendes Bundle, echte Pan-/Rückfahrt-/Wheeleingaben und gesicherte Runtime. |
| A02 | validiert | Gesamte Rechteckregion, tatsächliche Übersicht; unabhängige Containmentprüfung AWMC117/Mittelmeer/England+Nordpuffer, Quellen-/Masken-/Coveragebindung. |
| A03 | validiert | Ein Kamerapfad90°/Relief0→35.264391°/Relief1; tatsächliche Basis/Matrix/Zwischenstände; kein freier Moduswechsel. |
| A04 | validiert im aufgezeichneten Pfad |1031realeFrames Übersicht→nah→Übersicht; keine getrennten Szenen oder Leerframes in Bildstichprobe; Startupgap ausdrücklich erhalten. |
| A05 | validiert im gebundenen Probenumfang |8/8Viewstates einschließlich Pan/Rückkehr, sichtbarerRest<1px,0TileMismatch; CPU-Probegrenze explizit. |
| A06 | validiert | Uniform.001Längen-/Höhenskalierung, signedEGM2008/-novshift, getrennte Relief-/RG8-Rendertransformation; Projektionsmaßstabsfehler quantifiziert. |
| A07 | validiert als Arbeitsmaßstab |500mNahbreite, Einzelbäume/Gelände/Wasser lesbar; native~463mRasterquelle bleibt Genauigkeitsgrenze. |
| A08 | technisch nachgeprüft; Nutzerbewertung offen | Primärreferenz tatsächlich betrachtet, natürliche Palette/facettierte Familien/Gruppen; konkrete Wasser-/Materialfehler nachgeprüft. Keine erteilte Nutzerstilfreigabe. |
| A09 | validiert für aufgezeichneten Übergang; Cacheumfang begrenzt | LangsamererHin-/schnellererRückzoom und dichter Waldabschnitt beurteilt,CPU-Kaskade behoben,Seeds stabil,keine späten Pipelines. FrischeProzesse belegt,OS-/GPU-Caches unbekannt; kein beliebiger Kamerapfad zertifiziert. |
| A10 | validiert im Bild-/Inventarumfang | Keine GUI/Städte/Straßen/Gebäude/Grenzfarben/Raster/Feldreihen; kultivierte/verwalteteKlassen abstrakt. Quelldaten unterscheiden nicht jede Plantage/Naturwald. |
| A11 | validiert im Regionalumfang | FesteSommer-/Lichtparameter; grüne/trockene/Gebirgsregionen unterscheidbar; keine historische Vegetationsparität. |
| A12 | teilweise validiert, offen | NormalesFrame-/RSS-/GPUallokationsbudget beiderBackends erfüllt; echteCPUzeiten/Startupspitzen. GPU-/Per-Pass-Zeiten fehlen, deshalb keine volleA12-Abnahme. |
| A13 | validiert als Herkunftsdokumentation | Versionen/Lizenzen/Attributionen/Auflösungen/Transformationen/Historikbacklog; unveränderteOriginale/Hashes/separatesMakeValid,AWMCDateipfadaddendum imBundle. Keine Rechts-/180erGenauigkeitsgarantie. |
| A14 | geografische Wiederkehr validiert | DeterministischeKandidaten/Daten,gleiche finaleQuell-/Rendererbindung,echtePan-Rückkehr;keine neue Zufallsanordnung. Endbild nicht exakt zeitgleich zur letztenWP,keine Pixelidentität behauptet. |
| A15 | validiert im Probenumfang | eqc41-km-v1quadratische1000mProjektionszellen,floorrow/column;RuntimePan/Rückkehr/Küste/Rand/Naht mit0Abweichungen;kein sichtbaresRaster. |
| A16 | anwendbare Stichproben validiert; formale Toolabnahme offen | Quellen-/Modell-/Renderbudgets und Fehlerrevisionen getrennt,quellengebundeneKüsten/Flüsse/Inseln/Ridges/Nähte,neueMorph/Motionproben.14anwendbareLevel/Metrikkombinationen bestehen;4nichtgerenderteKombinationen sindNA,Kitchecker besitzt keinNA-Feld. Kein erfundenerNullwert/Vollpass. |

## Vier NA-Fälle und erhaltene Einschränkungen

`data-report-errata/HANDOFF.md` und `policy-application-v1.json` erklären die
vorab gebundene Anwendung: erzeugte overview/canonicalRaster sind regulär
keine RenderLOD; alle tatsächlichenZoom-/PatchLOD nutzen nativeDetailquelle.
Deshalb sind deren jeweils2Pixel-/TransitionmetrikenNA. Die2px/1pxBudgets
bleiben für **alle tatsächlich gerenderten** LOD unverändert. Alte warmed-
Runtimewerte in Errataviews gelten weiterhin nur für deren59a926…-Revision;
die neue finaleA05-/A16Runtimeevidence steht in diesem Prüfpfad. Historische
Errataviews nicht still auf die finaleRevision umetikettieren.

Die unabhängigen Datenbefunde bleiben in `DATA_V2.md`, `DATA_V3_DELTA.md`,
`RENDER_ENCODING_CAMERA.md` und ihren Rohdateien erhalten. Der v2Küstenfehler
wurde nicht weggerundet; v3nutzt denselbenStichprobenplan und unverändertes
6000mBudget. SDF/RG8 besitzen gesonderte vorab gebundene Zusatzbudgets.
Projektion, nativeQuelleigenfehler und repräsentativeVegetation begrenzen den
Anspruch. Die vierNA-Fälle sind eine Toolvertragslücke, kein Produktvollpass.

Nach dem finalen Smoke wurden alle Prüfer-App-/GPU-/Encodejobs beendet und der
Driver ausdrücklich zurückgegeben. Kein Userpreview offen gelassen, damit
die echte Smoke-Telemetrie nach kontrolliertem Schließen vollständig vorliegt.
Keine weiteren Produktänderungen oder Varianten werden aus dieser Prüfung
angefordert. Die verbleibenden offenen Punkte sind transparent ausgewiesen.
