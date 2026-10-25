# Unabhängige A01–A16-Prüfung — aktueller Abschlussstand

Referenz kit1-landscape-v5 / kit1-rendering-v4, 25.10.2026. Dieser Bericht ist
eine echte unabhängige Teilabnahme, keine vollständige Freigabe. Daten:
landscape-v3, Manifest SHA256
`edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a`.
Kanonische Normalmessungen und gestartetes Paket: Renderer
`59a926c8e09fdc0a391a829cf727003834c421ee1b79ff884d07735e0a31fe70`.
Spätere Diagnostik-/Korrekturbauten sind davon zu trennen.

## Geprüfte Laufzeitbelege

`warmed-mobile-normal/runtime.json` SHA256
`da55c44e28848b1f4536ffd8221bb4e2f917ee76af99134fc897ce8821366c39`,
`warmed-forward-plus-normal/runtime.json` SHA256
`2c248b3e63b1d941062f745b17abbcec2a615baf13c4c138d254ea35eedeb675`.
Die unabhängigen Nachrechnungen liegen in `warmed-*-normal-review.json`.

| Tatsächlich erhoben | Mobile | Forward+ |
|---|---:|---:|
| Frame p95 / p99 | 9.010 / 26.832 ms | 9.343 / 27.863 ms |
| Größter echter Wall-Frame | 171.538 ms | 279.208 ms |
| Spitzen-Prozess-RSS | 1897054208 B | 2134310912 B |
| Prozess-RSS in MiB | 1809.171875 | 2035.4375 |
| Größte Godot-GPU-Allokationsanzeige | 903086080 B | 974618624 B |
| Sichtbarer Source→Render-Probenrest | 0.655989486 px | 0.655989486 px |
| Pro-Frame Bewegungsresidual, legitime Bewegung abgezogen | 0.071383545 px | 0.065467176 px |

Beide erfüllen die **vorab gebundenen** p95≤16.7/p99≤33.3 ms,
RSS≤2048 MiB und GPUmonitor≤1024 MiB auf dem bezeichneten Mac M3 Pro bei
1920×1080. Forward+ liegt nur 12.5625 MiB unter der RSS-Grenze. 2048 MiB ist
2147483648 B; die ungenaue Bezeichnung „2 GB“ darf weder eine still strengere
Dezimalgrenze noch eine nachträgliche Lockerung ersetzen. GPUmonitor ist eine
Engine-Allokationsanzeige, kein Beleg vollständiger physischer GPU-Residency.

Die größten Werte liegen bei Startup/Pipeline Frame2; Pipelinezähler steigen
danach nicht mehr. Dennoch bestehen deutliche CPU-Unterbrechungen beim ersten
Wald: Mobile Frames2419–2429 dauern direkt aufeinander
114.796/94.904/86.115/81.523/71.943/67.097/64.431/61.263/58.312/55.207/50.563 ms
(rund806 ms für elf Frames). Forward+ zeigt entsprechend130.919→52.619 ms.
Das ist ein A09-Befund trotz bestandener Perzentilziele. Kein nachträglicher
numerischer Maximalgrenzwert wird erfunden. Pipelineprewarm löst diese
CPU-Regeneration nicht.

Viewport-CPU-/Frame-Setupzeiten sind echte Enginewerte. GPU-Zeit ist null,
weil der API-Wert ungültig0 war. Per-Pass-Zeiten sind nicht erhoben. Der
vollresident geladene Pfad hat keine laufenden Block-Request-/IO-/Uploadqueues;
deren Streamingmetriken sind hier nicht anwendbar, keine gemessenen Nullwerte.
Kein Windows-/Linux-/iPad-Leistungsnachweis.

## Bild-/Filmprüfung

`accepted-mobile-capture/zoom-tour.mp4` SHA256
`2e2273f8242b4baa3b1cbd183516086f31d4ec97994c520ff80d6547c1556c12`.
1025 tatsächliche unretuschierte Captureframes, streng steigende Rohzeitpunkte,
48.012335 s Laufzeit. ffprobe bestätigt1025 Filmframes; Zeitquantisierung der
VFR-Ausgabe gegenüber den relativen Rohzeitpunkten maximal19.996 ms. Das
verlustbehaftete MP4 ersetzt nicht die Original-JPEGs/PNG-Schlüsselframes.

Tatsächlich geöffnet: 49 zeitlich verteilte Originalframes in vier Kontaktseiten
unter `final-contact/`, verlustfreie1920×1080 Zwischen-/Nahbilder und zuvor
gezielte V01/V02/V03-Regressionsbilder. Keine synthetischen Zwischenbilder.
Der Film stammt vom vorangegangenen Renderer9478a78e…; die13 gezeigten
Geometrie-/Kamerafunktionen und3 Shader sind laut gebundenem Warmupdelta
bytegleich, die Normalmessungen stammen vom neueren59a926…-Build. Capturelast
ist getrennt; eine unabhängige CPU-Analyse überlappte circa15:35:27–15:35:34 UTC
mit einem Teil dieses Captures, nicht mit beiden Normalbenchmarks.

Nahbild: lesbare Einzelbäume mit drei facettierten Kronenfamilien und Gruppen,
natürliche Palette. Neuer Bildsatz zeigt die früheren V01-Wasserbäume,
V02-Treppenküste und V03-vertikale Patchlinie nicht erneut. Einschränkung A08:
`lossless_intermediate.png`,12.220867 s,zoom0.4519771203 zeigt deutlich große
rechtwinklige/verschwommene Coverklassenblöcke. Die eingefrorene WorldCover-
Overviewauflösung~300–594 m erklärt die Herkunft, erfüllt aber allein keine
unauffällige natürliche Materialdarstellung. Nicht als gelöste Stilabnahme
deklarieren. Primärreferenz wurde tatsächlich betrachtet; Nutzerstilbewertung
bleibt separat offen.

Die letzte exakte numerische Fixturebeobachtung liegt bei48.012335 s,
zoom0/17.5°E/39.5°N. Das letzte Filmframe bei47.995883 s ist minimal davor,
zoom2.77985e-7. `lossless_overview_return.png` ist bereits47.229424 s/zoom.009116,
also kein exakt gleicher Kamerazustand für einen Pixelidentitätsvergleich.
Die geografische Anordnung kehrt sichtbar zurück; Pixelidentität wird nicht
behauptet.

## Matrix

| ID | Tatsächlicher Status | Befund und Grenze |
|---|---|---|
| A01 | implementiert, teilweise validiert, Pan offen | Bundle zweimal selbst gestartet und geschlossen; echte30Up/30Down-Wheeleingaben beweisen Zoom/Rückkehr. Ein präziser weiterer Diagnose-Drag beweist Positionsdelta bei Buttondown, aber mask0/relative0; aktueller Renderer ignoriert ihn. Korrektur und echte Regression fehlen. `BUNDLE_INPUT.md`, `interactive-*/runtime.json`. |
| A02 | validiert im dokumentierten Regional-/Quellumfang | Echte Gesamtübersicht; unabhängige OGR-Containment-/Maskenprüfung für AWMC117, gesamtes NE-Mittelmeer, England mit2.188835° Nordpuffer; ganze Region heutebasiert und ohne NoData auf geprüftem Land. Quellenqualität bleibt begrenzt. `reference-check.json`, `DATA_V2.md`. |
| A03 | validiert auf gebundener Tour | Eine Ansicht, Fern90°/Relief0, Nah35.264391°/Relief1, beobachtete Zwischenstände. Atomare Kamerabasis beseitigt früheren Pitch-Sprung; tatsächliche Matrix/Basis exportiert. |
| A04 | implementiert, visuelle Tourteilprüfung validiert | Vollständige1025-Frame-Tour Übersicht→nah→Übersicht ohne Szenenwechsel/Leerframe in betrachteter Auswahl. Flüssigkeit/A09 bleibt eingeschränkt. |
| A05 | numerische Stichproben validiert | Prospektive Fixture39e82d…,Controls527992…,Threshold7cd761…,Config3fd2… vor neuen Normalruns;8/8 exakte Zustände,0 Tilemismatch. Maxsichtbar.655989px<1px. CPU-Camera3D/aktiveTriangelprobes, keine Framebuffermerkmalerkennung. |
| A06 | validiert im dokumentierten Modell | Uniform0.001 Länge/Höhe, EGM2008/-novshift signed Quellen, gesonderte Relieftransition. Projektionsskalierung geprüft, maximal.42419729<.5; keine Flächentreue behauptet. |
| A07 | validiert als Arbeitsmaßstab | Nahbreite500m, Gelände und Einzelbäume lesbar; keine500m-Quelldetailgenauigkeit, Quelle~463mN/S. Keine Häuser gebaut. |
| A08 | implementiert, offen | Kronenfamilien/Gruppen und Palette verbessert; sichtbare Zwischenzoom-Coverblöcke bleiben konkreter Befund. Nutzerbewertung nicht erteilt. |
| A09 | offen | Alte Wasser-/Nahtfehler gezielt behoben; Materialpipelineprewarm verifiziert. CPU-Waldframes~0.8s bei11–20fps bleiben. Expliziter schneller gleicher Landpfad/Kaltcacheteil nicht unabhängig vollständig belegt. |
| A10 | validiert im betrachteten Bild-/Inventarumfang | Keine GUI, Städte, Straßen, Gebäude, politischen Farben, sichtbares Hilfsraster oder Feldreihen. Verwaltete/kultivierte Klassen abstrakt; WorldCover kann nicht jede Plantage von Naturwald trennen. |
| A11 | validiert im betrachteten Regionalumfang | Feste Sommer-/Lichtparameter; Alpen, grüne europäische Regionen, trockener Süden und Wasser unterscheidbar. Kein historischer Vegetationsnachweis. |
| A12 | teilweise validiert, offen | Gleicher finaler Normalpfad auf Mobile/Forward+; vorab Frame-/RAM-/GPUallokationsziele erfüllt. Rohspitzen/Startup/CPU-Waldkosten behalten. GPU-/Per-Pass-Zeiten nicht erhoben; kein Vollpass. |
| A13 | validiert als Herkunfts-/Grenzendokumentation |271Quellhashes,10Payloadhashes,Original-AWMC mit separatem MakeValid, präzises Abrufpfadaddendum, Attribution/Version/Genauigkeit/Historikbacklog.76Dateien im tatsächlich gestarteten Bundle erneut0Hashabweichungen. Keine180er-/Rechtsgarantie. |
| A14 | geografische Wiederkehr validiert, enger Pixelvergleich offen | Deterministische Quelle/Seed/Adressierung; visuelle Wiederkehr und numerisch exakte Fixtureendzustände. Keine zufällig neue Landschaft gesehen. End-PNG nicht exaktstategleich, daher kein Pixelhashvergleich ausgegeben. |
| A15 | validiert in gebundenen Runtimeproben | eqc41-km-v1 quadratische1000m-Projektionszellen,floor row/column;9 unabhängige Sollanker,0 Runtime-ID-Abweichungen auf Tour inklPan/Rückkehr/Rand/Küste/Naht. Keine physischen flächengleichen Bildschirmquadrate behauptet. |
| A16 | umfangreiche Teilprüfungen validiert, Gesamtstatus offen | v3Küsten-/Höhen-/Projektions-/Quelltopologie-/RG8prüfungen gebunden; aktuellerMesh/Morph-Seam-/Motiontest innerhalbPixelbudgets. Fünf positive Ridgeanker plus irrtümlicher Ozeananker: zusätzliche quellengewählte Positivkontrolle noch ausstehend. Kein globalerGPU-/Kammnetztopologiebeweis. |

## A16-Rohumfang

`warmed-mobile-lod-ridge.json` mit RohCSV misst26 tatsächliche LOD-Inventare,
56995 sichtbare korrespondierende Edgevertex-/Midpointqueries beider Nachbarn:
maximal0 px Höhennaht ohne Skirts. 5478 Ridgeprobes,1184 sichtbar, maximal
0.283883635 px Quellen-/Packed-/Meshrest. Das sind unabhängige Float64-
Auswertungen des tatsächlichen UV/Morph-/Patchinventars; keine GPU-Readbackwerte.
Per-Frame-Bewegungsproben ziehen legitime Kamerabewegung ab; max.071384px.

Original `protected-ridge-4`35.8°E/36.7°N ist waterkind1/0m und kann keine
Gebirgspositivkontrolle sein. Erratum bleibt erhalten. Eine zusätzliche feste
quellenbasierte Auswahl ist vor Renderbeobachtung spezifiziert und gehasht:
`ridge-positive-plan.json` SHA0be45505595a91fa42e505c0e5541d18b3abf7accbae0c1ea3a8fb94e701d913.
Alle57600 native Sourcezellzentren im festgelegten1°-Fenster untersucht;
1810Landzellen≥1000m; Maximalquelle als vorab festgelegte Regel gewählt:
36.047916666666666°E/36.33958333333334°N,1752.130859375m,Row5198/Col11291.
Kein Renderfehler/Screenwert wurde zur Punktwahl herangezogen. Renderprobe
steht aus; Produktdaten/Schutzregel wurden nicht verändert.

Offlinemetriken, Bildbeobachtungen und Kitformatprüfungen bleiben getrennt.
Die noch offenen Punkte sind reale fehlende Ergebnisse/Produktbefunde;
kein Kitcheckergebnis wird als Produktfunktion ausgegeben.
