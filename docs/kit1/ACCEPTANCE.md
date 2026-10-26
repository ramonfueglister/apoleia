# Kit 1 — spätere Abnahme und Nachweise

**Referenzversion:** `kit1-landscape-v5` / `kit1-rendering-v4` · **Status:** Prüfplan `spezifiziert`,
Gesamtabnahmen A01–A16 `offen`. Aktuelle Teilbelege und ihren begrenzten
Aussageumfang hält der Abschnitt „Aktueller Laufzeit-Checkpoint“ fest.

## Prüfprinzip

Jeder Lauf nennt Kit-/Buildrevision, Datensatzversionen, Darstellungsparameter,
Hardware/OS/Auflösung, Startbefehl und Testkonfiguration. Festgehaltene geografische
Prüfpunkte und wiederholbare Kamera-/Zoompfade machen Aufnahmen vergleichbar.
Es werden **reale Laufzeitbilder und numerische Ergebnisse** gemeinsam geprüft.
Ein unabhängiger Prüfagent liest die Probes und betrachtet die Aufnahmen.

Geografische Quellpositionen und stilisierte Darstellungspositionen sind getrennt
zu erfassen. Gemessen wird gegen die dokumentierte Darstellungsabbildung, nicht
gegen eine fälschlich vorausgesetzte Eins-zu-eins-Skalierung. Quellen-, Modell-
und Renderraum werden getrennt gemessen. Kontrollierte Renderabflachung ist Teil
des Zoomprofils; willkürliche Überhöhung oder verschobene Quellgeografie sind es nicht.

## Abnahmematrix

| ID | Anforderung | Reproduzierbarer Nachweis / Beurteilung |
|---|---|---|
| A01 | Startbare erkundbare Anwendung | Dokumentierter Start auf tatsächlicher Testumgebung; Verschieben und Zoom durch reale Eingabe und Prüffahrt; keine bloße Bildserie |
| A02 | Gesamte Projektregion statt Regionaldemo | Gesamtübersicht, gebundenes region.json und coverage.json mit regionalem Bezugsraum, Land-/Ozeandomänen, Quellen-/Mappingrevision, Aggregationsbelegen, NoData-Behandlung sowie Kartenrändern/Küsten/Tile-Nähten; zusätzlich diverse geografische Prüfpunkte. A02 referenziert Coverage und Region; Reichsrahmen 117, gesamtes Mittelmeer sowie England+nördlicher Puffer müssen einzeln belegt sein |
| A03 | Gebundener flach-zu-Diorama Übergang | Flache 2D-Fernkarte, isometrischer räumlicher Nahendpunkt und beobachtete Zwischenzustände mit Kamera-/Projektions-/Reliefprofil belegen; keine freie Rotation oder manuell getrennten Ansichten |
| A04 | Stufenlos Gesamtübersicht → nah → Gesamtübersicht | Ununterbrochene Laufzeitaufnahme und Kamera-/Zoomverlauf; keine Umschaltung auf getrennte Welt-/Regional-/Stadtszenen oder andere Darstellungsmodi, keine Sprünge oder leeren Zwischenzustände |
| A05 | Gemeinsame Geografie | Identische Referenzpunkte über Zoomstufen und Hin-/Rückfahrt verfolgen; Quellenkoordinaten, Darstellungsabbildung und projizierte Lage in demselben gebundenen Kamera-/Viewport-/Transformzustand vergleichen; Fixture-Wegpunkte einschließlich Pan und Rückkehr tatsächlich nachweisen. Küsten, Flüsse und Relief behalten Zusammenhang |
| A06 | Verkleinerte datenbasierte Modellwelt | Gemeinsame dokumentierte Längen-/Höhenskalierung und getrennte Rendertransformation; keine willkürliche Überhöhung/Distanzverkürzung. Projektionsverzerrung quantifizieren. 500 m bleibt Arbeitswert |
| A07 | Nutzbare Nahansicht | Gelände/Wasser und einzelne stilisierte Bäume sind gut lesbar; Ausschnitt entspricht künftig mehreren Häusern samt Umfeld. Nachweis über Kameraausschnitt und dokumentierte Größenorientierung, ohne Städte als Kit-1-Feature zu bauen |
| A08 | Einheitlicher Stil nach der Nutzer-Primärreferenz | Feste Kameravergleiche gegen references/STYLE_GUIDE.md: zurückhaltende natürliche Palette, stilisierte facettierte Geometrie, ausreichende Landschaftsdetails und lesbare Waldgruppen; nicht fotorealistisch, nicht übermäßig bunt oder extrem low-poly/voxelartig/klotzig. Keine Terrain-Detailvorgabe aus nachrangigen Bildern ableiten; keine Polygonzahl oder Leistungsfähigkeit aus Stilbildern behaupten |
| A09 | Unauffällige Detailübergänge | Gleichen Zoompfad langsam, schnell sowie hin und zurück aufnehmen; Übergänge, Objektstabilität, Flackern, sichtbares Auftauchen, Risse und Wasser-/Terrainversatz beurteilen; kalten/warmen Cache, erste Material-/LOD-Varianten und spät gestreamte Kombinationen markieren und Pipeline-Erstellungen mit max/p95/p99-Framezeiten korrelieren |
| A10 | Nur natürliche Landschaft, keine GUI | Laufzeitbilder und Datenebeneninventar prüfen: keine heutigen/antiken Städte, Straßen, Gebäude, politischen Grenzen/Gebietsfarben oder eingebrannten entsprechenden Kartentexturen; kultivierte Felder, Plantagen und verwaltete Flächen anhand dokumentierter Klassenbehandlung maskieren/abstrahieren; auch danach keine sichtbaren Feldmuster, Plantagenreihen, Zäune oder Bewirtschaftungsstrukturen. A10 prüft den natürlichen sichtbaren Endzustand ohne GUI, Raster, Tile-Highlights, Themenfarben oder Modusbedienung |
| A11 | Fester Darstellungszustand | Sommer-/Lichtparameter und Vergleichsaufnahmen: keine Zeit-/Jahreszeitenwechsel; regional unterscheidbare Landschaften statt global identischer mediterraner Vegetation |
| A12 | Flüssigkeit auf Zielklasse messbar | Framezeiten einschließlich Verteilung/Spitzen, Speicher und Ladeunterbrechungen auf benannter Hardware, Auflösung und identischem Pfad erfassen; Request-Alter, sichtbare Verspätung und byte-/zeitbegrenzte Uploads erfassen sowie Forward+ und Mobile mit gleichem Terrain-/Streaming-/Material-Workload vergleichen; Mac-Befund nicht als Windows-/Linux-/iPad-Nachweis ausgeben; spätere Windows-/Linux-Ziele benötigen eigene gebundene Testumgebungen |
| A13 | Ehrliche geografische Herkunft | Versionierte Daten-/Lizenz-/Transformationsliste, bekannte Auflösungs- und Abdeckungslücken sowie gesonderte historische Korrekturliste; keine unbelegte 180er-Genauigkeit |
| A14 | Wiederholbarkeit | Gleiche Daten, Parameter und Pfade liefern gleiche geografische Anordnung; Abweichungen erklären. Keine zufällig neu angeordnete Landschaft beim erneuten Besuch |

| A15 | Unsichtbare quadratische Tile-Grundlage | Versionierte logische Rasterdefinition, kanonische IDs/Indizes und interne Runtimeprobes über unterschiedliche Zoomzustände, Pan/Rückkehr sowie Kartenränder/Küsten/Tile-Nähte. Quadratische logische Zellmaße, keine Bildschirmquadrat- oder physische Flächengleichheitsforderung. Kein sichtbares Raster, keine Tile-Auswahl oder zusätzliche Ansicht erforderlich/erlaubt; A15 referenziert tiles-Evidence |

## Aktueller Laufzeit-Checkpoint — SourceV2/V19 integrierter Stand

### Bindung und revisionsbezogene Belege

Die aktuelle [`renderer-binding.json`](../../app/renderer-binding.json) setzt
SourceV2 als Default und bindet V19 `source_grouped_crowns` sowie den
SourceV2/V19-Produktcache. Die Runtimebindung ist im geteilten Arbeitsbaum
geändert; dieser Dokumentcheckpoint nimmt keine Runtimeänderung auf. Handoffs:
[SourceV2 Runtime](../product-renderer/SOURCE_V2_RUNTIME_HANDOFF.md) und
[V19 Gruppierung](../product-style/V19_GROUPED_CROWNS_HANDOFF.md).

Der integrierte Lauf
[`source-v2-v19-product-cloud-r1`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-product-cloud-r1/)
ist Session 34031, Exit 0. Sein [`checkpoint.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-product-cloud-r1/checkpoint.json)
bindet Runtime-SHA `c3c42ef787e25b5b8af77847a90de7b67477dacfd9f52b02b5004a7fab67c6d9`,
Terrainshader-SHA `ca680ba278f5bbe1bf507ea3131624339245bb109604c50ee0355988abf64ff3`
und Produktbindung-SHA `b4dd913322583213ae66f76c4de0b08cb50154a6e6a39173e06744975be0fa57`.
Vier reale Fern-/Nahbilder mit Wolken aus/an und 90 Messframes nach 16 Warmups
pro Variante belegen nur diese bereit gerenderte Szene, keinen Start, Tour- oder
Gesamtpass.

### Landschaftsform und Stil

V19 ist als Gruppierungsänderung begrenzt CPU-validiert und als bessere
Gruppierung gegenüber dem Vorgänger unabhängig beurteilt; **A08 bleibt FAIL**.
Die normale Schärfung V20 wurde verworfen. V21 testete drei wirksame
Elternflächen-Zielpunkte, Session Exit 0, gebunden in
[`camera/source-v2-v21-parent-patches-r1`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v21-parent-patches-r1/).
Laut unabhängigem Astra-Review erzeugten sie harte helle Dreiecke ohne räumliche
Formgliederung; Kandidat verworfen, kein Produkt-/Stilpass. Der Reviewbefund ist
als Ownerbericht überliefert, nicht als verlinktes Reviewdokument. Der kontrollierte
[`source-v2-material-coast-r1`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-material-coast-r1/)
schaltete beide Übergangs-Uniforms gemeinsam von 0 auf 1; der unabhängige Vergleich
bestätigte weniger Materialtreppen und Doppelringe, aber weiche Flecken,
Inselhöfe und glatte Felsflanken bleiben. [`source-v2-canopy-ab-r1`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-canopy-ab-r1/control.json)
zeigt nur kleinen Ferngewinn; beide Befunde sind kein globaler Stilpass.

V22 ist ein lokaler numerischer Formkandidat, kein Produktwechsel. Der
[V22-Handoff](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v22-local-form-r1/HANDOFF.md)
bindet das lokale [`manifest.json`](../../artifacts/render-data/source-v2-local-form-r1/manifest.json),
SHA-256 `2ceaf2f5c413d97ca1e1a11b9ccb7be6ed9baa85c425526f09921295734a02e0`.
Mit 32 Stützen beträgt das Maximum im Gesamtkern 314,25 m und **verfehlt** das
ursprüngliche ≤250-m-Kriterium wegen sechs geschützter Nodes; 163 veränderbare
Nodes liegen bei höchstens 225,5 m. Profil: 670 m Absenkung/477,5 m Anhebung,
keine Schutz-/Randverletzungen, Source-Maximum 1224,020953 m unter dem
2500-m-Budget. Unabhängige Rekonstruktion von 529 Nodes: null Delta. Echte
Baseline-/Kandidatenbilder stehen in
[`source-v2-v22-local-form-capture-r1`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v22-local-form-capture-r1/).
Der gebundene Vergleich bestätigt gleiche Kamera, Materialien, Licht, Quelle und
Readiness sowie kohärente Höhenkonsumenten. Laut unabhängiger Astra-Sichtprüfung
verworfen: höher/steiler, weiterhin breite weiche beige Felsen. Kein
Produkt-/G-Weltwechsel; A08 bleibt **FAIL/offen**.

V25 ist ein lokaler Sicht-`keep` für den reparierten Geländeübergang; die
globale Landschaftsform verfehlt A08 weiterhin. Der unabhängige V25-Review
validiert nur Daten-/Geometrie-/Energie-/Bounds-/Fixityumfang, keine Bilder oder
Laufzeit. Siehe [V25-Handoff](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v25-bounded-transition-r1/HANDOFF.md)
und [Review](../../runs/kit1-gamegraphics-v2-2026-10-25/review/v25-bounded-transition-r1-independent/review.json).
V25 bleibt eine lokale Kandidatenstudie; kein Produktwechsel.

### Cache- und Tourbefunde

Der eng definierte Fern-/Mittel-/Nah-Produktcache enthält 352 Zellen, 61 leer,
264.164.536 Payloadbytes, Bake/Write 76.314 ms, Arrayfingerprints 352/352
identisch. Manifest-SHA `5bb618e402de7e8e0855be2ecf5d2a1273c07a837a08d46a9cdfe0f1a1b033d5`.
CPU-Standardstart: 352 Hits/0 Misses/0 Fallbacks. Der integrierte Lauf meldet
308 Hits/0 Misses/0 Fallbacks und 1.294,384 ms
kumulierte Meshloads. Kein Vollwelt-/Vollzoom-/GPU-Uploadnachweis. Cache und
Source-/Renderinputs sind lokal; dieser Dokumentcheckpoint veröffentlicht sie
nicht und begründet keine Remote-Reproduzierbarkeit.

Der Nichtflach-Tourcache
[`manifest.json`](../../artifacts/render-data/forest-cache-sourcev2-v19-tour-nonflat-r1/manifest.json)
hat SHA `9280e9cd0361909ee404ee267446f5e7b9c575cc9733fba6891e6c51e98c0285`:
2.924 Varianten (352 wiederverwendet, 2.572 neu), 1.210.154.764 Bytes und
326.679,81 ms Build+Write. Die gebundenen Meshprüfungen bestanden; neue echte
Cache-API-Probe 8 Hits/0 Misses. Das bleibt beobachtete Tourabdeckung, keine
Vollweltabdeckung. Belege: [`source-v2-v19-tour-cache-r1`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-tour-cache-r1/).

Tourlauf mit diesem Cache:
[`source-v2-v19-cloud-off-tour-cache-r2`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-cloud-off-tour-cache-r2/)
Exit 0, 923 Frames, ein ausgelassener Aufnahmeversuch, 459 Hits/16 Misses
(alles stride 0) und 2.574 ms Fallback. Frame-Wallzeiten p95 54,285 ms,
p99 89,497 ms, Maximum 350,187 ms. Erste Endpose nach 48,079 s: 155 Flussjobs
offen; zusätzlicher Hold 1,760 s/162 Frames bis Queue-Leerlauf. Keine vollständige
Videobetrachtung; keine Streaming-, Rückkehr- oder Performancefreigabe. Der
vorige r1-Lauf hatte p95 72,991/p99 159,616/Maximum 558,589 ms.

Der Fluss-Set-Cache ist implementiert. [`river-set-cache-r1/result.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/river-set-cache-r1/result.json)
belegt atomaren Tausch, stabile Zähler und Key-Abhängigkeiten an synthetischer
Zwei-Linien-CPU-Geometrie. 8 Sets/64 MiB ist nur das Raw-Mesh-Cachebudget;
aktiver Pin, Pending- und GPU-Daten kommen zusätzlich hinzu.

Der echte River-Endpunktlauf R4
([`summary.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-river-cache-tour-r4/summary.json))
hat Start, erste Endpose und Endhold pixelidentisch; an der ersten Endpose waren
0 Flussjobs aktiv. Unterwegs besteht aber eine Near-Regression: bei 1.777
Requests wurden nur 2 Sets fertig, weil exakte Width/Pitch-/Frustum-Keys laufende
Gesamtsets wiederholt abbrechen. R5 ohne Bildaufnahme
([`summary.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-river-cache-tour-no-capture-r5/summary.json))
meldet p50/p95/p99/max 9,274/41,402/68,035/308,703 ms und 2 Sets bei 2.126
Requests. Das sind nur diese Tour-/Aufnahmekonfigurationen, kein A12-Pass.

### Forest-Async, native Eingabe und AABB-Replay

Der Forest-Async-Pfad ist implementiert. CPU-Queue-P2 wird in
[`forest-async-queue-p2-r2/checkpoint.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/forest-async-queue-p2-r2/checkpoint.json)
als repariert mit fokussierter Regression Exit 0 gebunden; unabhängige Re-Review
steht aus. Die konkrete Source-Ownership im gemeinsamen Arbeitsbaum bestätigt
der Runtimeowner; sie ist nicht Bestandteil dieses Dokumentcheckpointes.

Native Probe R3:
[`summary.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-native-input-resize-async-r3/summary.json)
bindet reale Scroll-/Gegen-Scroll- und Resize-Rückkehr, Zoom 0→0,0469799 sowie
Viewport 1440×810→1154×670→1440×810; Gegen-Scroll/Rückübersicht pixelidentisch.
813 kalte Builds, 0 Cachehits, 0 Fehler, 1 Cancel, am Ende 0 Jobs/Leases.
Mainthread-Commit max. 1,376 ms; Forest-Mainfunktion max. 9,031 ms; Framezeiten
p50/p95/p99/max 10,341/14,187/15,278/165,845 ms einschließlich Diagnose-PNGs.
Das ist kein direkter Leistungsvergleich mit anderen Auflösungen und kein A12-
Pass. Wanted-Spitze 2.100, stabil 1.508→1.454; maximal 813 resident/511 sichtbar,
768 bleibt weiche Grenze. Die Waldfüllung ist damit nicht abgenommen. OS-Input-
OriginTimestamp fehlt, also keine OS-Eingabelatenzbehauptung. Die Cachekompatibilität
ist inzwischen ausschließlich durch das unten dokumentierte enge Refaktorgate
freigegeben; daraus entsteht keine zusätzliche Cacheabdeckung.

Das nach dem Min/Max-AABB-Fix gebundene Replay
[`aabb-reproduction.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/forest-async-array-split-r2/aabb-reproduction.json)
hat SHA-256 `bd49f6dd82cbc2512be495e87c895d677ddde1316e1b876f4316a32b3f84d340`,
acht Reports und `failures=[]`, einschließlich `(-2,2)`. Der unabhängige Review
bestätigt 8/8 exakte Fälle; Style-SHA `120436ea…0b335` entspricht Native R3.
Finale Cacheinputidentity laut Replay ist
`091c5a48c0d67411fe1c69a94b1a8617019fa515602191c249c59dd2b9aa232a` (nicht die
vorläufige Zwischenidentity). R1 bleibt historischer Fehlbefund. Alte
Cacheheader außerhalb des ausdrücklich gebundenen Producer/Consumer-Paars werden
weiter strikt abgewiesen.

### Enges Forest-Cache-Refaktorgate

Die normale Consumeridentity bindet jetzt auch den aktiven
`fixed_forest_build_context.gd` und lautet
`dffeea1d79afdfb773e8ac7b0633e83ba8426451ce0c4a7a756fa272dc1ef9c9`. Eine
gehashte Kompatibilitätsdefinition erlaubt ausschließlich Producer
`92a357fd9ecde784d0371b1221226b0fda66b30024627a10730016f28a4325f0` aus dem
unveränderten Originalmanifest mit SHA-256
`9280e9cd0361909ee404ee267446f5e7b9c575cc9733fba6891e6c51e98c0285`.
Definition [`compatibility.json`](../../artifacts/render-data/forest-cache-refactor-compatibility-r1/compatibility.json),
SHA-256 `91b4c10f97dba4eb08ffc0b771f49deb41df1d4f32ef151bea0998093e18547f`;
Producerheader und Payloads bleiben unverändert. Der unabhängige
[`review.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/review/forest-cache-context-gate-r2-independent/review.json)
hat SHA-256 `67295f9fb361d6fd37436ad072527445f9731bed1070574d579481c2b83f0578`,
20/20 Headlesschecks mit Exit 0, zwölf exakt passende Dateihashes und keine
P1/P2-Befunde. Umfang: Metadatensicherheit und ein echtes Payload. Keine native
Warmcacheprüfung, Vollabdeckung, GPU-/Leistungsabnahme oder A08/A12-Aussage.
Stride 0 bleibt Miss; sichtbarer Wald ist unvollständig. Flussverhalten während
der Fahrt bleibt offen.

### Compact-Forest-Integration R2

Historischer Compact-Integrationsstand; der Produktdefault Expanded und der
fehlende Warmcache-Pass in diesem Abschnitt wurden durch den späteren Layout-r3-
Default-/Nativcheckpoint ergänzt. R2-Reviewdetails gelten nur für ihren Scope.

Der eingefrorene [Laufcheckpoint](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/forest-compact-cell-capture-r2/checkpoint.json)
hat SHA-256 `0f6512706024905940c535f4bfc23d9bdc6598ec1167784a60b5a972364fd21e`.
Der unabhängige [Integrationsreview](../../runs/kit1-gamegraphics-v2-2026-10-25/review/forest-compact-integration-r2-independent/review.json)
hat SHA-256 `a9aa073a674fca273c886c3adf1568cd86bb1b569bb76571762e4197370d151e`,
bestätigt 48 Datei-/Checkpointbindungen, zehn synthetische Recordfälle,
sieben Compact-Queueprüfungen, acht Lifecyclegruppen, 20 aktive Identitychecks
und beurteilt neun bereits erfasste echte GPU-Zellpaare. Keine P1/P2-Befunde.
Der Reviewer hat selbst keine GPU oder native App gestartet.

Zum damaligen R2-Stand blieb Compact ein reversibler, explizit aktivierbarer Pfad;
Produktdefault war Expanded. Der alte Expandedcache wird wegen des neuen Style-/Context-Hashes
weiterhin strikt abgelehnt. CPU-Recordaufbau kostet für 191 Kronen
240,416–281,311 ms, also kein CPU-Speedup. Für die tatsächlich serialisierten
DTOs wurden höchstens 14.068 Bytes gegenüber 84.744 Bytes beim dichten
1369-Record-Fixture gemessen; dies belegt eine begrenzte Transport-/Speicher-
Reduktion, keinen Gesamtprozess- oder GPU-Speicherpass. Der Mainthreadpfad zur
Materialisierung ist geprüft. Native Warmcache-/Vollabdeckung, vollständige
sichtbare Waldfüllung, A08 und A12 bleiben offen. Die kleinen GPU-Paarabweichungen
werden berichtet; Pixelidentität oder eine vorab genehmigte Bildtoleranz wird
nicht behauptet.

### Ground-/Layout-Integration R2 und Grenzen der Abdeckung

Der eingefrorene [Ground-/Layout-Checkpoint](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-ground-layout-integration-r2/checkpoint.json)
hat SHA-256 `ff3a9b919a97b9911b3bff51adaa27f52dea7a4baeb7c868f494d850f23a6885`.
Der unabhängige [P2-Recheck](../../runs/kit1-gamegraphics-v2-2026-10-25/review/final-ground-layout-r2-p2-independent/REVIEW.md)
hat SHA-256 `95e094771b70fde8615b86913a2cb1936e386b11f3eccb958821b22dea0c0f4b`:
72 gezielte Checks bestanden; die aktive Geometry-/Shaderidentity-Lücke ist
geschlossen. Das geprüfte `river_g_snapshot.gd` wurde separat mit 181 Checks
reviewt ([Review](../../runs/kit1-gamegraphics-v2-2026-10-25/review/river-g-snapshot-r1-independent/review.json),
SHA-256 `be361908e20c009030835ec513f965ba710a5d9d68a2fb26cc8a01c6930bc7de`);
es liefert die Rendergeometriebindung und bedeutet keine fertige Riverintegration.

Die bestehenden r1-Befunde umfassen 11.220 Ground-, 60 Reader-, 41 Context-,
7 Container- und 10 Memo-Checks (jeweils PASS im ursprünglich geprüften Scope).
Die finale
Groundabbildung behebt im CPU-Trace den früheren maximalen Fehler von
38,1111154 Quellmetern gegenüber der tatsächlich gerenderten Fläche. Daraus
folgt keine pauschale GPU- oder Float64-Transportparität.

Der tatsächliche [Layoutprobe-r4](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-complete-layout-provider-r1/probe-r4/manifest.json)
hat Manifest-SHA-256 `de8e6d5eda2829d50dff97521c3ed018b55c8bb00557ac83035c170b831b60c7`
und Status `incomplete-probe`: acht tatsächlich besuchte Zellen mit 419
Records entsprechen r3 bei allen 419 Recordbytes und acht Layout64-/Ground0-
Metadatenströmen exakt. Die 3116-Zellen-Publikations-/Indexprüfung war
synthetisch; sie erzeugt keine echten Records oder Weltabdeckung. Ein
vollständiger SourceContext-Bake wurde nicht ausgeführt.

Die für das lokale Offline-Tool nötige Codecrelokation ist zusätzlich mit
[`codec-relocation-checkpoint.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-ground-layout-integration-r2/codec-relocation-checkpoint.json),
SHA-256 `07f318314d2348fec1f2144b3edbde12ff9dea5b6d246120ce4825a49355f5b6`,
gebunden. Der nach `tools/forest_layout_codec.py` kopierte Codec ist bytegleich
zum geprüften Researchcodec; nur der Compiler-Importlocator änderte sich. Der
begrenzte Smoke bestätigte Import, 128/128/64-Byteformate und exakten F64-
Roundtrip. Kein Source-Laden oder vollständiger Bake.

Der ältere Compact-Lauf mit 1077/1508 Wanted-Zellen nach Resize ist historisch
und wurde durch Layout-r2/r3-Nativläufe für deren getestete Posen abgelöst.
Aktueller Produktdefault ist Compact plus vollständiges Layout-r3 mit fail-closed
Manifest-/READY-Closure, aber noch kein neues Bundle gebaut. Die Projektregion
bleibt unabgedeckt; A08 **FAIL**, A12 **offen**. Region-r3 ist verworfen; der
aktuelle Strukturpfad hat kein READY und keinen Bildpass.

### Integrierter Fern-/Nahlauf, Wolken und Numerik

[`summary.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-product-cloud-r1/summary.json)
bindet 90 Messframes nach 16 Warmups je Variante. Wallmediane OFF/ON: Fern
29,670/63,4485 ms (p95 30,934/67,460), Nah 8,3235/10,340 ms (p95 8,779/10,446).
GPU-Zeit ist `null`; diese szenario-/revisionsgebundenen Renderwerte sind kein
A12-/Mobile-Forward+-Pass. Ziel/Breite/Basis/LOD-Signatur und projizierte Anker
blieben gleich (max. 0,000061 px), vollständige Kameraposition und Far Clip
variierten wolkenhöhenbedingt. Lugano-Nahprobe war wolkenfrei, daher keine
Nahwolken-Qualitätsaussage.

Cloud V10 ist in der Produkt-Hashliste. Laut Cloud-Owner bestehen zwölf
technische Bildprüfungen; visuelle Referenztreue und Leistung bleiben offen.
Der v7-Screenshot wurde laut Mitteilung des Cloud-Owners an den Hauptagenten
vom Nutzer ausdrücklich abgelehnt und gilt daher nicht als visueller Pass.
Die SourceV2-GPU-Probe r3 bleibt beim ursprünglichen RGBA-Grenzwert `0.0001`
FAIL. Die unabhängig begründete künftige Render-Toleranz `1/255` in
[`numeric-policy-r4/analysis.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-numeric-policy-r4/analysis.json)
ist keine globale Fehlergrenze und ändert r3 nicht rückwirkend.

### Tour, Paket und offene Abnahmen

Der gültige r3-Appkandidat wurde relocatiert gestartet: [`start-summary.json`](../product-renderer/package-evidence/source-v2-v19-candidate-r3/start-summary.json)
meldet Exit 0 und 15,608 s Launcher-Wallzeit. Die getrennten 1,815 s Runtimezeit
beginnen nach Engine-/Quellstart und Setup, also nicht beim Prozessstart. Laut
Cleanupbeleg [`record.json`](../product-renderer/package-evidence/scratch-cleanup-2026-10-26-r1/record.json)
wurden nur die fehlgeschlagenen r1-/r2-Kopien nach Hasharchiv entfernt; r3 blieb
erhalten. `Clouds OFF` ist noch nicht als Produktdefault neu verpackt. Kein
aktuelles Bundle ist auf der neuesten Runtimerevision gebaut.

- **A07 — nutzerseitig spezifiziert; Abnahme offen:** Die Breite eines späteren
  Hauses soll etwa einer einzelnen Baumkrone entsprechen, kompakt dargestellt
  (Nutzerantwort vom 26.10.2026, siehe [`decisions.md`](decisions.md#bestätigt-für-kit-1)).
  Der externe Größen-/Einzelkronenbeleg hat einen engen unabhängigen Teilreview
  bestanden; es fehlt weiterhin ein gebundener Kamera-/Ausschnittsnachweis mit mehreren künftigen Häusern,
  Umfeld und einzeln lesbaren stilisierten Bäumen. Keine Meterzahl ableiten;
  500 m bleibt ein Arbeitswert und der 240-km-Anker kein Pass. Gebäude bleiben
  in Kit 1 ausgeschlossen.
- **A01/A04/A09 — offen:** nativer Layout-r3-Lauf belegt vollständige
  Waldfüllung in geprüften Scroll-/Resize-Posen, Cold-Coverage 3,023 s sowie
  pixelgleiche Übersicht/kleines Resize/Rückkehr. Scrollpose alt/neu weicht an
  Pixel (768,234) ab, Ursache offen. River-Nahnavigation, Rand-/Roundtrip und
  durchgehende Tour vom readinessbereiten Start bleiben offen. Der ältere
  Tourpfad beginnt vor Readiness; Startadapter/Folgetour sind getrennt zu bewerten.
- **A08 — FAIL/offen:** Stilreferenzabnahme weiterhin nicht bestanden.
- **A12 — offen:** weder Produkt-OFF/ON-Einzelwerte noch die native R3-Frame-
  Verteilung sind Zielklassen-/Mobile-Forward+-Leistungsabnahmen.
- **Paket/Gesamtabnahme — offen:** Vollweltcache/-daten, frisches kohärentes Bundle,
  aktuelle App-/Belegsammlung und finale unabhängige A01–A16-Abnahmen fehlen.
  SourceV2/Runtimeänderungen im gemeinsamen Arbeitsbaum sind nicht Teil dieses
  Dokumentcommits und nicht unabhängig reviewt.

Kosten werden nur aus tatsächlich erhobenen Messwerten berichtet; Preise wurden
nicht erhoben.

### Historische V12- und V13-Aufnahmen

Der zuvor geprüfte V12-Frame bleibt ein historischer, visuell nicht bestandener
Zwischenstand. Seine Runtimebindung ist
[`frame_000329.png`](../../runs/kit1-gamegraphics-v2-2026-10-25/captures/italy-diorama-v12-retry-01/frame_000329.png);
die Metadatei ist
[`runtime.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/captures/italy-diorama-v12-retry-01/runtime.json).
Sie bindet `gameworld-v1`, `mapping-v1`,
`orthographic-diorama-display-v4`, Apple M3 Pro (Apple9), Mobile und
2952×524. Der Frame liegt bei 15.5°E/42°N, Quellbreite ca. 3.4 Mm, Pitch
35.264388°, Reliefgewicht 1 und `display_height_scale=12`; Wolken waren
ausgeschaltet. Unabhängige visuelle Prüfung: **FAIL**. Alpen und Apennin zeigen
kleinteilige Wald-/Zackenbänder statt breiter Flanken, das Meer wirkt nahezu
einfarbig mit harter Küstenkante, und das Framing weicht ab (Sizilien sichtbar).
Das ist ein aktueller Befund zur sichtbaren Aufnahme; daraus folgt kein Pass
für A03–A06 oder eine Gesamtabnahme.

Die zugehörige unabhängige Reviewbindung `v12_visual_review` steht im
[`v12-checkpoint.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/style/v12-checkpoint.json).

Der Faktor 12 ist eine explizite neue Darstellungsentscheidung. Er wurde nicht
aus der Stilreferenz gemessen und erfüllt nicht die frühere XYZ-
Displayisotropie-Annahme. Die mit dem Frame gebundene feste Makroableitung nutzt
24-km-Kontrollen und ein 2-km-Raster; das Source→Displaymodell-Maximum beträgt
2185.23 m gegen ein neu angesetztes 2500-m-Budget. Das belegt weder genauere
Quellen noch einen globalen theoretischen Fehlerdeckel.

Der aktuelle echte V13-Frame ist
[`frame_000328.png`](../../runs/kit1-gamegraphics-v2-2026-10-25/captures/italy-diorama-v13/frame_000328.png)
mit gebundener [`runtime.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/captures/italy-diorama-v13/runtime.json).
Sie bindet weiterhin `gameworld-v1`, `mapping-v1`,
`orthographic-diorama-display-v4`, Apple M3 Pro/Mobile, Viewport 2952×524,
Zentrum 15.5°E/42°N, Quellbreite ca. 3.4 Mm, Pitch 35.264388°,
Reliefgewicht 1 und Displayhöhe Y×12. Laut unabhängigem Sichtbefund: **FAIL**.
Die Felsflanken sind etwas freier, der Formblocker bleibt; der Küstensaum ist
weiter unzureichend, das Bildframing unverändert. **A08 bleibt offen.** Der
Reviewbefund ist als Meldung überliefert; ein unabhängiges Reviewdokument ist
hier nicht gebunden.

### Historische V13-Aufbauzeit, Messwerte und Tourstatus

`runtime.json` verzeichnet 91.866948 s Laufzeit bis Frame 328. Die Whole-Run-
Zusammenfassung ist p50 221.486 ms, p95 651.922 ms, p99 764.664 ms und Maximum
826.427 ms. Laut Runtimeowner enthält sie den Aufbau; sie ist keine
Stable-Frame-Verteilung und kein Performancepass. Der letzte Einzelwert von
25.189 ms belegt keine Verteilung oder dauerhafte Leistung.

Die separate
[`startup.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/v13-tour-normal-window/startup.json)
meldet acht stabile Frames bei leeren Terrain-/Feature-/Flussqueues, bevor die
bestehende 48-s-Tour beginnt. Das ist ein Readiness-Fensterbeleg, keine
bestätigte durchgehende Tour vom tatsächlichen Appstart bis zur Rückkehr. Der
Runtimeowner meldet, dass der alte Startpfad die Tour sofort vor Readiness
beginnt und ein externer Startadapter in Arbeit ist. A01/A04 bleiben offen.

### A07 — Nahansicht für spätere Häuser

**Nutzerseitige Größenorientierung: `spezifiziert`; A07-Abnahme: `offen`.**
Die direkte Nutzerantwort vom 26.10.2026 legt fest, dass ein späteres Haus
kompakt dargestellt etwa eine einzelne Baumkrone breit sein soll (siehe
[`decisions.md`](decisions.md#bestätigt-für-kit-1)). Das ist keine Meterzahl und
meint ausdrücklich eine einzelne Baumkrone, keinen Waldcluster. Externe
Größen-/Quellenorientierung und unabhängiger Teilreview sind PASS im engen
Umfang; Produkt-Screen-Bounds und Kameraausschnitt sind noch nicht belegt.

Maßgeblich ist ein Ausschnitt, in dem später mehrere Häuser samt Umfeld Platz
haben und einzelne stilisierte Bäume lesbar sind; Häuserassets bleiben in Kit 1
ausgeschlossen. Die 500-m-Angabe in
[`decisions.md`](decisions.md#maßstabswerte-orientierung-keine-starren-vorgaben)
ist nur ein Arbeitswert. Ein 240-km-Anker ist kein A07-Nachweis. Auch für den
aktuellen integrierten SourceV2/V19-Lauf und die Tourproben liegt kein gebundener
Kamera-/Ausschnittsnachweis vor, der mehrere künftige Häuser samt Umfeld belegt.
Keine frühere Capture-Revision als aktuellen A07-Pass übernehmen.

### Neuester Layout-/Bounds-/Default-Stand

Der Layout-r3-Bake umfasst 3.116 Zellen und 176.609 Records; alle Recordbytes
sind digestgleich zu r2, Container 14.197.868 B. Der deterministische Bake dauerte
378,467 s. Echter nativer Scroll-/Resize-Lauf erreichte vollständige Abdeckung
in den geprüften Posen; Cold-Coverage 3,023 s statt 9,278 s. Commitmaximum
0,369 ms. Frames p95/p99/max 19,296/22,349/173,273 ms, daher kein A12-Pass.
Übersicht, kleines Resize und Rückkehr sind pixelidentisch. Zwischen fertigen
alten/neuen Scrollposen besteht genau eine Pixelabweichung bei (768,234); Ursache
offen trotz gleicher Records, Kamera und Riverkey. Keine kausale Pixelparität
behaupten. [Native-Handoff](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-native-layout-bounds-r1/HANDOFF.md),
Checkpoint-SHA `9a81f0652b51a8957b9948739f608cf0d44bd2a5c78f91a6d6b10ee5e5db29d0`.

Analytic Bounds sind unabhängig reviewt; [vollständiger r3-Bake/Loader-Handoff](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-analytic-bounds-complete-r3/HANDOFF.md),
Checkpoint-SHA `58a626ecdb914ac9995294c85e9640fed8b9f95760c1970824f39ae163436732`.
Der ehemalige Layout-r2-Stand bleibt historisch und unverändert.

Produktdefault bindet nun Compact und relatives vollständiges Layout-r3 mit
exaktem Manifestpin. Closure enthält Manifest, Binding, Layout und READY,
14.206.103 B; falscher Pin und fehlender Pfad schlagen fail-closed fehl. Beleg:
[`checkpoint-final.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-complete-layout-default-r1/checkpoint-final.json),
SHA `47a9513dfb15c5e7fb3ac8875d9eadafd6e61ef5435c1b806bfc6ab79eadd91e`.
Dies belegt keine neue aktuelle Bundle-/Relocationerstellung; Cloudprodukt bleibt OFF.

Der externe A07-Einzelkronenbeleg samt unabhängigem Teilreview
([Review](../../runs/kit1-gamegraphics-v2-2026-10-25/review/a07-single-crown-r1-independent/REVIEW.md))
ist PASS in seinem Quellen-/Schemaumfang; tatsächliche Produkt-Screen-Bounds und
der Kameraausschnitt für mehrere Häuser fehlen. A07 bleibt offen.

### Historische V13-Statusgrenzen

- Die V2-Datenrevision ist fertig, jedoch nicht in diese aktuelle Runtime
  integriert. Siehe [`V2_RUNTIME_HANDOFF.md`](../product-gameworld/V2_RUNTIME_HANDOFF.md).
- Wald-/Shoremasken-A/B ist abgeschlossen: Session 70325, Exit 0 ohne Fehler
  (laut Laufabschlussmeldung). [`control.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/v12-forest-shore-ab/control.json)
  bindet vier echte GPU-Bilder derselben eingefrorenen V12-Szene; alle vier
  sind 2952×524. Die `forest_off.png`-Kontrolle zeigt breite Alpenflanken ohne
  Waldinstanzen. Im Shore-only-Vergleich wurde ein duplizierter `1-water`-
  Faktor entfernt; [`image-difference.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/v12-forest-shore-ab/image-difference.json)
  meldet 22.799 geänderte Pixel und maximale Kanaldifferenz 20 (mittlere
  absolute Kanaldifferenz 0,07064). Das belegt den kontrollierten A/B-Effekt,
  aber keine Stilverbesserung oder -abnahme; die Runtime- und Styleprüfung der
  Bilder bleibt ausstehend.
- Die frühere visuelle v7-Abnahme der Wolken ist widerrufen: Laut
  Cloud-Owner-Meldung an den Hauptagenten hat der Nutzer den v7-Screenshot
  ausdrücklich abgelehnt. Laut Cloud-Owner-Meldung nennt der neue Astro-Review Stempelformen, harte
  Silhouetten, uniforme Transparenz und Crossfade-Ghosting. Der frühere
  [`visual-review.md`](../../runs/clouds-2026-10-25/v7/visual-review.md) bleibt
  historische Dokumentation, kein gültiger visueller PASS. Frühere
  Capture-/Kamera-/Driftbelege bleiben nur in ihrem technischen Umfang
  nachvollziehbar. Die aktuelle Nutzerkorrektur verlangt, die Wolken zu
  verbessern und anschließend zu aktivieren; OFF bleibt Diagnosezustand. V16
  wurde in privater GPU-Kopie geprüft, ist aber keine Qualitäts- oder
  Leistungsfreigabe. Produktdefault bleibt bis zur Integration und Review OFF; Umschaltung,
  Referenztreue/Erscheinung und kombinierte Terrainintegration bleiben offen.
- V2-Datenrevision und sämtliche bisherigen finalen A01–A16-Abnahmen bleiben
  offen; V13 bindet weiterhin V1.
- Kamera-, Nah-, Rand-, Resize- und Roundtrip-Abnahmen sowie ein ungeschnittenes
  durchgehendes Video bleiben offen. Ebenso finale Mobile/Forward+-Performance,
  V2-Runtimeintegration, eine kohärente aktuelle App samt Belegsammlung und
  scoped Git-Abschluss. Kosten sind nur anhand tatsächlich erhobener Metriken
  zu berichten; ein Preis wurde hier nicht erhoben.

## Prüfkonfiguration vor späterer Umsetzung konkretisieren

Noch offen sind Referenzhardware, Bildauflösung, Mindestleistung, zulässige
Framezeit-/Ladespitzen, Speicherbudget sowie numerische Fehlertoleranzen für
Darstellungs-/Zoomstabilität. Der spätere Ausführer legt sie begründet fest und
kennzeichnet sie als technische Testentscheidung. Er darf sie nicht nach einem
schlechten Messergebnis stillschweigend lockern oder als Nutzerentscheidung ausgeben.
Ohne definierte Schwelle und Messung bleibt die entsprechende quantitative
Abnahme `offen`, auch wenn eine Aufnahme subjektiv flüssig wirkt.

[`RENDERING.md`](operations/RENDERING.md) schlägt für den ersten Mac-Prototyp
60 Hz bei 1920×1080 mit p95 ≤16,7 ms und p99 ≤33,3 ms sowie null sichtbare
Terrainlöcher auf der Prüftour vor. Diese Arbeitswerte sind `offen` bis Gerät,
OS, Build, thermischer Zustand und Szenario gebunden und tatsächlich gemessen;
sie sind keine Nutzerentscheidung und keine Zusage für iPad, Windows oder Linux. Zielbudgets ersetzen
keine Rohtelemetrie oder getrennte Qualitäts-/Speicherabnahme.

Die geografische Prüfauswahl muss verschiedene Landschaftsformen und Teilregionen
abdecken. Rom/Tiber/Ostia/Tibur kann ein gut nachvollziehbarer Konsistenzfall sein,
belegt aber weder die gesamte Projektregion noch die historische Landschaft von 180 n. Chr.
Eine Stichprobe ist als solche auszuweisen; Datenabdeckung und Anwendungspfad
müssen zusätzlich für das ganze Projektgebiet nachvollziehbar sein.

Für jeden Lauf mindestens erfassen: Anforderungs-ID, Revisionen, Ort/Quelle,
Kamera-/Darstellungsparameter, erwartetes Verhalten, Beobachtung/Messwert,
Bild-/Aufnahmepfad, Status und begründeter Befund. Maschinenlesbare Formate liegen unter `schemas/`, ausfüllbare Laufvorlagen unter
`templates/`. [Prüfablauf](operations/VERIFY_CAPTURE.md) und
[Adaptervertrag](operations/ADAPTER.md) sind vorbereitet; der Runtimeadapter und
die produktive Datenpipeline werden erst im späteren Produktauftrag implementiert.

## Abschluss

Jede Anforderung erhält einen tatsächlichen Befund, nicht nur ein Häkchen. Offene
Punkte bleiben sichtbar. Reale Zoomaufnahme und regionale Gesamtübersicht müssen aus
demselben geprüften Build stammen. Eine unabhängige technische Prüfung und eine
spätere Nutzerbewertung des Stils sind getrennt zu dokumentieren. Kein Agent
erklärt fehlende Nutzerbewertung eigenmächtig für erteilt.

Die einzige Ansicht zeigt natürliche Landschaftsfarben. Es gibt keine GUI,
Overlays für Raster/Themen/Tile-Auswahl, Menüs, Panels, Legenden oder Hilfetexte.
Pan/Zoom werden direkt bedient und extern dokumentiert. Die früher diskutierten
drei Darstellungsweisen sind spätere Ziele und keine aktuelle Abnahme.

## A16 — datenbasierte Ableitung, Fehlerbudgets und Feature-Schutz

A16 ist die neue Geoableitungsabnahme, **kein Darstellungsmodus**. Sie verknüpft
`derivation`-Evidence mit der vor Messung versionierten `geodata_policy.json`.
Erforderlich: Quellqualität/CRS/Höhendatum, Quell-/Modell-/Rendertransformation,
Skalenfaktor, Projektionsverzerrung, pro Generalisierungsniveau und Gültigkeitsraum
gebundene metrische Budgets, Rohwerte und Stichprobenplan. Gemessen werden Höhen-,
horizontale Gelände- und Küstenabweichung im Quellraum (Meter), Bildschirmfehler
und Übergangsresiduen (Pixel) sowie Projektionsmaßstabsabweichung (Verhältnis).

Der Kitprüfer berechnet **Stichprobenmaxima**, keine globale theoretische Schranke.
RMS oder Algorithmuskosten ersetzen diese Werte nicht. Untersuchte/ungeprüfte
Bereiche und Quelleigenfehler offenlegen. Für geschützte Küsten, Inseln,
Flussnetze, Kämme und Tile-Nähte sind unerwartete Änderungen zu melden;
beabsichtigte Detailauslassungen brauchen Quellen- und Regelbezug. Kein fehlender
Wert darf als Nullfehler erscheinen. Echte vollständige Zoomaufnahme und
unabhängige Daten-/Bildprüfung bleiben erforderlich: eine Messdatei beweist weder
Herkunftswahrheit noch den visuellen Übergang allein.

Nicht gerenderte Niveaus dürfen Bildschirm-/Übergangsmetriken als
`derivation.not_applicable` mit Pflichtbegründung und hashgebundenem Regelbezug
ausweisen; Quellraummetriken nie. NA ist kein Zahlenwert und kein Pass.

**Status A16-Werkzeugabnahme (26.10.2026):** NA-Vertrag im Kitchecker
`implementiert` und testseitig `validiert`. Release-v2: 14 anwendbare
Kombinationen innerhalb der Budgets (gemeldete Maxima, hashgeprüft), 4 NA mit
Regelbezug; Reviewer-Bindung im Bericht vorhanden. Formaler `report-check` über
`derivation-view.json` und unabhängige A16-Statusentscheidung `offen`. Details:
[A16_TOOL_ACCEPTANCE](evidence/A16_TOOL_ACCEPTANCE.md).

## Spätere Systemgrenzen-Abnahme (außerhalb der Kit-1-Laufmatrix)

Vor einer späteren Kopplung mit Grafik ist ein headlesser Rust-Smoke-Lauf ohne
Godot, Fenster oder Grafik-/Render-API erforderlich: validierte Commands
einreichen, Simulationsticks unabhängig von Frames ausführen und versionierte
Zustände/Snapshots ausgeben. Ein Boundary-Test prüft Snapshot-Unveränderlichkeit,
begrenztes Handoff mit neuestem vollständigem gültigem Stand, Delta-Lücken samt
Vollsynchronisierung und Simulationsfortschritt unter absichtlich langsamem
Renderer-/IO-/GPU-Konsumenten. Darstellungszustand darf keine kanonische
Wirtschafts-/Weltwahrheit schreiben. Diese künftige Abnahme ist nicht Teil der
Kit-1-Berichtsmatrix A01–A16; sie behauptet keine implementierten Tests oder
Leistungswerte.
