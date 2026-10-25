# Beratender Vertrag für die Küsten-SDF-Darstellung

Stand25.10.2026, Quelle `landscape-v3` bleibt unverändert. EigeneRenderableitung, keine historischeRekonstruktion oder neueLand-/Meerwahrheit. Grafikowner besitzt SDFerzeugung/Upload/Shader; Datenowner besitzt read-onlyGegenprobe und dieseDokumentation. Umsetzung/GPUprüfung zum Vertragszeitpunkt offen.

## Vorab gebundene Methodik und Grenzen

1. Eingaben sind die unveränderten NaturalEarthv5.1.2Land-/Seenpolygone samt vollständigenQuell-/Maskenhashes. SDFnull beschreibt die Grenze von Land minus Seen. Quellkonturen bleiben erhalten; keine freieKonturverschiebung, keinFractalnoise. An der regionalenRechteckkante durchClipping erzeugteSegmente sind keine natürlichenKüsten und dürfen nicht in dieDistanzbasis gelangen. TatsächlicheInsel-/Polygonringe und Lochgrenzen werden erhalten.
2. Berechnung im bestehenden `mapping-v1` mit demselben Projektionsradius/Standardparallel/Ursprung und Modellscale0.001. Definition derDistanzeinheit ist ausdrücklich **projizierteMeter**, keineBehauptung überall gleicherGeodätik. BestehendeLängen-/Höhenskalierung bleibt gleich.
3. Ausgabe auf dem8192×6144Pixelcentergrid. Vorzeichen amTexelcenter muss mit der tatsächlichenPolygonklassifikation `land minus lakes` übereinstimmen; unveränderteDetailkindmaske ist nur insoweit äquivalent, wie sie genau dieselbe Punktklassifikation repräsentiert. KeineVorzeichenbildung aus bilinear gemischtenKindcodes.
4. ErwarteterWert: exakte nächsteSegmentdistanz aus den Quellkonturen, imBand±3000projizierteMeter. Eine räumlicheKandidatensuche ist zulässig, wenn sie alleSegmente innerhalb diesesBandes erfasst. Außerhalb desBandes darf bewusst gesättigt werden. Ungeprüftfehlende Kandidaten dürfen nicht als korrekteSättigung ausgegeben werden. Quellsegmentberechnungsresidual vorQuantisierung: vorab0.01projizierteMeter in derGegenprobe; keineGPUpositionbehauptung.
5. R8unsignedQuantisierung von[-3000,+3000] ergibt Schritt6000/255=23.5294117647projizierteMeter und maximal11.7647058824projizierteMeter nearest-Rundung. VorabBudget **12projizierteMeter**. Die0-ISO liegt zwischen den beiden mittlerenCodes; nicht einenCode eigenmächtig zu einer Null-Sonderform machen. Kanal ist lineare numerischeDatenrepräsentation ohne sRGB.
6. Nach bilinearerInterpolation können Kontur-/Gradientenfehler größer als dieTexelquantisierung sein. Deshalb zusätzlich Null-ISO-Versatz gegen die ursprünglichenQuellsegmente nach inverseProjection inQuellkoordinaten/geodätischenMetern prüfen; vorbestehendesKüstenbudget6000m bleibt unverändert. Bestehende2pxScreen-/1pxTransitionbudgets gelten weiter. Die±3000Meterrange oder12Meternzahl sind keinBeweis für dieseMetriken.
7. Featureprüfung umfasst dieselben geschütztenInseln und zusätzlich engeBuchten/Halbinseln, Seen, regionaleKüstenränder sowie den tatsächlich beanstandetenEngland-/Schottlandabschnitt desFilmpfads. Ein600mSDFgrid kann bei kleinenFeatures topologisch falscheNullkonturen erzeugen; das muss als Defekt erkannt werden. Wasser-/Baumklassifikation bleibt sourcegebunden; Fragmentglättung darf keineVegetation auf sichtbaremWasser erzeugen.

DieR8Quantisierung ist nur eine neueDarstellungsrepräsentation. Bei21°N können11.7647projizierteOstWestmeter etwa14.55geodätischenMetern entsprechen; der Manifestbeleg muss dies sprachlich und numerisch trennen. Meeres-/Binnenwasserhöhen und negativeLandhöhen folgen weiterhin unverändert demSignedHeightvertrag.

## Gegenprobe

Nach Lieferung werden Manifest/Payloadhashes und dimensionsgebundeneDecodierung geprüft, ausgewählteTexelcenter gegen eine unabhängige direkteNearestSegmentrechnung, anschließend Quellkonturpunkte gegen bilinear dekodierteNull-ISO (einschließlich desFilmabschnitts). VollständigeGPUbilder und zeitlicheMorph-/Materialbelege bleiben unabhängig erforderlich. KeinSDFbestehen allein aus demR8Wertebereich behaupten. FaintLODPatchlinien und Ridge-/Nahtnachweise gehören den Renderer-/Captureprüfungen und werden durch dieKüstenableitung nicht ersetzt.

## Tatsächlicher R8-v1-Prüfbefund

Quelle und Renderpayload bleiben getrennt. Der untersuchte R8-Payload hat SHA256 `a08b15ad169dc6a628e1d1ee37eb3e1906f5461e7a26d207012884ae554ff1b2`, PolicySHA256 `c922becee3e8c495785b0765ad75524069b0569ea2b34eaedb7192828257fb49`.

Die unabhängigeProbe berechnet direkteNearestSegmentdistanzen gegen alle46985Quellsegmente statt des räumlich eingeschränktenRendererbuilders.962Texel liefern0Codeabweichungen, maximal11.755335projizierteMeter Abstand der dekodiertenZahl zur gekappten signedQuelldistanz.30künstlicheRegionclipsegmente sind ausgeschlossen.585räumlich verteilteQuellküstenproben besitzen jeweils eine rekonstruierte tatsächlichebilineareNullkurve; größter gemessenergeodätischerVersatz608.38155m,0fehlendeNullkurven. Alle5geschütztenInselinnenpunkte bleibenLand. Das ist eine begrenzteQuell-/Encoding-/Konturprüfung, keine globaleTopologiegarantie für kleineInseln oder alleBuchten. [Rohbeleg](sdf-probe.json).

Am tatsächlich beanstandetenFilmzentrum1.0968509912/51.0591201782 wurden zusätzlich64dichteQuellsegmentmittelpunkte geprüft. Nach verfeinerterNullkurvensuche mit2049Werten jeZellachse liegt der regionaleMaximalversatz37.02303m. Drei dieserQuellpunkte liegen bei angenommenerNullhöhe im exaktenFrame334-Viewport; ihr maximaler planarerProjektionsversatz ist1.297935px. Die anfängliche33-Punkte-Kurvenabtastung war hierfür zu grob und wurde ausdrücklich verfeinert; keinMesswert wurde zumBestehen gerundet. Das ist keine tatsächlicheGPUfragmentedge-Messung und keine globale2pxFreigabe.

Eine weitere direkteFloat64-Gegenprobe rekonstruiert die unquantisierteQuelldistanz an141relevantenTexelcentern. Mit4097Kurvenwerten jeAchse ergibt sich für dieselben3sichtbarenQuellpunkte nur0.0227–0.0508mQuellversatz beziehungsweise maximal0.013566px planarerVersatz. In diesem konkretenFall dominiert daher dieR8Quantisierung denRest gegenüber der bilinearenQuellkrümmung. [Floatgegenprobe](sdf-float-probe.json).

Für den500mNahzoom kann ein12mR8Quantisierungsrest trotzdem vielePixel betragen. Grafikowner erstellt deshalb eine **separateprospektiveRG8-v2-Darstellungsrevision**: SignedRange[-4096,4095.875]projizierteMeter,Step0.125m,Quantisierungsbudget0.0625projizierteMeter,vierCornerdecodes vorBilinear wie beimHeightpacking. Der SourceSDF-Abstand und die3000mSättigung bleibengleich. KeineSource-/Geodaten-/6000m-/2px-/1pxBudgetänderung. Diese neueEncodingrevision muss vor eigener tatsächlicherByte-/Nullkurven-/GPUprüfung gebunden werden; dieR8-Prüfung wird nicht als RG8-Bestehen ausgegeben.

## Tatsächliche RG8-v2-Gegenprobe und Integration

Payload `artifacts/render-data/water-distance-rg8.bin`, SHA256 `ee41a6bd76f835106a64383b577edee142a27b54cdbb90ebf629c61200699e67`; vorabPolicySHA256 `d19dde843c7161da718a716e29058f141311e2a41ff6ba56699c1c1bd48a813a`.

Die gezielte unabhängigeGegenprobe gegen dieselben46985Quellsegmente ergibt auf962Texeln **0Codeabweichungen** und maximal0.06248015projizierteMeter Gesamtresiduum zur direkten signedQuelle. Auf denselben585globalenQuellpunkten werden alleNullkurven gefunden; Stichprobenmaximum605.91351geodätischeMeter unter dem unveränderten6000mBudget. Alle5geschütztenInselinnenpunkte bleibenLand. Die64dichtenFilmquellpunkte zeigen maximal33.49948mgeodätischenVersatz; bei denselben3imFrame334sichtbarenNullhöhenpunkten beträgt der planarePixelrest maximal0.02917341px. [RG8-Rohbeleg](sdf-rg8-probe.json). Keine globaleKontur-/Kleininsel-/2px-/1pxGarantie; tatsächlicheGPUkante/Morph und neueAufnahme müssen unabhängig beurteilt werden.

Nach Abschluss der Grafikownerintegration wurden die tatsächlichenDateien erneut statisch gelesen: neuev2Pfade, `Image.FORMAT_RG8`, CPUzweibyteDecodierung `*.125-4096` vorBilinear, identischevier`texelFetch`-Cornerdecodes inTerrain-/Flussshader. Die vorher vorläufig festgestellteR8-Integration ist damit behoben. Baumzulassung nutzt Detailwasserart0 und negativeSDFdistanz<-20projizierteMeter. [Hashgebundener statischerPrüfstand](sdf-static-integration-check.json). Dies ist die fachlicheTeilfreigabe der beobachteten Datenrepräsentation/Integration für die folgendeGPU-/Videoprüfung, keine abschließende Gesamtabnahme.

Reproduzierbare read-onlyGegenprobe:

```sh
/opt/homebrew/bin/python3.14 tools/data_sdf_probe.py --manifest artifacts/render-data/water-distance-rg8.json --payload artifacts/render-data/water-distance-rg8.bin --rg8
```

Source-/Höhen-/Modellabbildung sowie `landscape-v3` bleiben eingefroren. Keine weiterenGeodatenvarianten oder neuenBudgets wurden eingeführt. Grafikowner besitzt Runtime/Capture, der unabhängigeReviewer entscheidet den neuen tatsächlichenBild-/Zeitbefund.
