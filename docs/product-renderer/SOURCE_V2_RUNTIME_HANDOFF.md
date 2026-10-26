# SourceV2 und fester Waldcache

Referenz: kit1-landscape-v5. Revision `source-v2-default-cache-r5`.
Status: Bindung und CPU-Cacheintegration **implementiert**, unten benannte enge
Prüfungen **validiert**. Bildreferenz A08, kontinuierliche Navigation/Leistung,
gebietsweite Cachedeckung und Paketstart bleiben **offen**.

## Automatischer Produktstart

`app/renderer-binding.json` ist die explizite Produktbindung. Ohne CLI konsumiert
`landscape.gd` SourceV2 und prüft deren SHA; fehlende oder falsche Quelle erzeugt
keinen V1-Fallback. `--dataset` bleibt ein ausdrücklicher Testoverride.
Die V2-Upload-, Atlas- und grafischen Küstenmanifestpfade und Hashes werden aus
dieser Bindung konsumiert. V1 ist ausschließlich ausdrücklich wählbare historische
Vergleichsquelle, seine Ableitungen wurden nicht verändert.

- Source: `data/gameworld-v2/landscape.json`, SHA `937f1737c819aa346425de026aef9690ad54c9616000d5b3e455b2056e0a1aeb`.
- Upload: `artifacts/render-data/source-v2-upload-r1/upload.json`, SHA `e1386da677c2adff466bcca75b019a07b2aa53afd56586afe559086b7a614446`.
- Atlas: `artifacts/render-data/fixed-source-v2-macro-r1/surface.json`, SHA `3bcb739078cc8a438cd21b8855a28ba47dc8aba78f67e600629a402d1ec0c4f3`.
- Grafische Küstendistanz: `artifacts/render-data/display-coast-source-v2-r1/manifest.json`, SHA `b8388888680009ead3b8809901c6796d51ff30e3b54fd0c2b7776de3f6319cab`.

## Kanonisches Sampling und Rendering

`canonical_domains_v2.gd` konsumiert Kontext/Fine/Local mit je Feld eigenem Raster
und Pixelzentrumvertrag. Höhe: Kontext→Fine, Produkt der vier C2-Smoothersteps.
RGBA und SDF danach zusätzlich lokaler C2-Kragen. Local hat keine eigene Höhe.
Gelieferte SDF-/Rollenfelder werden unverändert transportiert, nicht erneut aus
Vektoren berechnet. Finales SDF≤0 ist Land; sonst kommt die diskrete Rolle von
der feinsten gültigen Domäne mit positivem Gewicht, niemals aus Rollen-Lerp.
Diese Auswahl bei winzig positivem Gewicht ist eine dokumentierte eigene
Integrationsentscheidung. Binnenwasserrolle2 wird nicht zur Nullmeerfläche.

Kanonisches RGBA ist bilinear auf Basislevel und C2-komponiert. Der Produktshader
stellt dafür `source_surface_weights_base_at` bereit; der Felsvorrang verwendet
G daraus. Die sichtbare Materialfarbe verwendet weiterhin mip-/pixelgefilterte
RGBA als separate Renderableitung; sie wird nicht als statische Basisfeldparität
behauptet. `source_model_normal_at` differenziert die bereits komponierte Höhe,
inklusive des Übergangsgradienten. Feste Darstellungsnormalen bleiben davon
getrennt der Atlasgradient. DisplayY12 ist eine bewusste Darstellungsentscheidung,
kein Quellmaßstab und keine aus der Vorlage gemessene Originalkonstante.

## GPU-Proben und ehrliche Präzisionsgrenzen

Belege unter `runs/kit1-gamegraphics-v2-2026-10-25/camera/`:

- `source-v2-gpu-sampling-r2`: 50 Records/41 Positionen, Hmax0.011808m,
  SDFmax0.166016m, Rollen exakt. G nur Basislevel mit binären Werten; keine volle
  RGBA-/Normalenabnahme daraus. Eigener alter Shaderhash bleibt gebunden.
- `source-v2-gpu-sampling-r3`: 56 Records inklusive sechs fractional RGBA-Proben.
  Hmax0.017578m/SDFmax0.166016m/Rollen exakt/Quellnormalwinkel max0.027976°
  innerhalb der vorher gesetzten Grenzen0.5m/exakt/0.25°.
  RGBAmax0.000244096 und Gmax0.000366300 verletzen den damaligen Grenzwert0.0001:
  **r3 bleibt FAIL**. Die Failure-Liste kaskadiert zusätzlich wegen eines
  Harnessfehlers mit laufendem Max statt Rowfehler; Gesamtmax und FAIL sind korrekt.
- `source-v2-numeric-policy-r4/analysis.json`: unabhängig geprüfte künftige
  Engineering-Toleranz1/255 für GPU-RGBA. Bewusst gewählte Renderakzeptanz, kein
  nachgewiesenes globales Fehlermaximum und keine rückwirkende Umwertung vonr3.
  Andere Grenzen und bitidentischer Offline-SDF-Transport bleiben getrennt.

## Tatsächliche Bilder

Die ersten V2-Bilder liegen unter `captures/source-v2-v17-italy`,
`source-v2-v17-local-coast` und `source-v2-v17-north-halo`. Der Weitlauf hatte einen
belegten temporären Viewportwechsel3024×1898; sein finaler2952×524-Frame ist gültig,
seine Aufbauzeit aber kein kontrollierter V1/V2-Leistungsvergleich. Die lokalen
Kontrollen binden eine tatsächliche Binnenwasserrolle2 und den geklemmten Nordrand.

`camera/source-v2-canopy-ab-r1/{baseline,footprint_filter}.png` vergleichen allein
den gestagten Canopyfilter bei gleicher fester Welt, Kamera, Meshes und Schatten.
Filterwirkung klein; kein A08-Pass oder Produktfilter übernommen.

`captures/source-v2-v18-ostia/frame_000059.png`:1920×1080,240km, bestehender
Ostia-Anker12.239024/41.736274. Fenster vor Szene8 normale Postdrawframes
stabilisiert und während Planung bewacht. Queues leer,8stabile Renderframes,
Integrity true,1.606919s bis Frame59. `water-transect.json` bindet tatsächliche
Terrain-/Marineuniforms und257 Proben auf einer festen SW-Linie durch den Anker,
250m Schritte; das ist keine vermessene Küstennormale. Kleine Inselringe sichtbar.

## Cacheintegration und Lebenszyklus

`forest_mesh_cache_identity()` rekonstruiert die aktive Source-/Upload-/Atlas-,
Generator-/Mode-/Policy-, DisplayY-, Runtime-/Sampler-/Projection-/Codecrevision.
Die genaue Engineversion bindet der Codec zusätzlich. Reine Canopybeleuchtung ist
nicht Teil der Geometrieidentität. Native Integer werden vor Hashing durch einen
JSON-Roundtrip normalisiert, weil JSON-Manifeste Zahlen als Float zurücklesen.
Die frühen CPU-Läufe r1/r2 lehnten diese zuvor unnormalisierte Identität ab;
beide Artefakte bleiben erhalten. r3 bestätigte den engen Fix; r4 bindet den
anschließend manifestgesteuerten Pfad und eingefrorenen V19-Generator.

`build_fixed_forest_mesh(cell,stride)` erzeugt dieselbe feste Geometrie unabhängig
von vorhandenen Terrainnodes. Stride0 ist flache Stütze;1..128 dyadischer Stride
inklusive Named-Ankersterne, marines Wasser0, DisplayY enthalten, Relief nicht.
Der Generator bekommt dieselben Land-/Wald-/Felscallbacks und dieselbe feste Grid-API
wie zuvor. So ist die Geometrie nicht von zufälliger Node-Residency abhängig.

`renderer-binding.json:forest_cache` nimmt einen relativen Generationspfad und den
Manifest-SHA auf. Im R5-Test noch leer; seit der V19-Bildentscheidung real auf den352-Cell-Produktteilcache
gebunden. Dafür ist keinerlei Nutzer-CLI nötig.
`--forest-mesh-cache` ist ausschließlich Testoverride. Identität oder Payload
falsch/fehlend: Telemetriefehler und identischer Generatorfallback, niemals eine
andere Source-/Stride-/Modevariante. Geladene Meshes erhalten aktuelles
`canopy_material` und Instanzgewichte. Die bestehende768-Chunk-LRU/Eviction bleibt;
der Reader hält keine zweite Meshresidency. Kein Laufzeitcache wird geschrieben.

CPU `camera/source-v2-default-cache-r5/probe.gd`, Exit0:
automatische V2-Quelle, echter Alpenchunk, alle Arraybytes/AABB nach Load identisch,
falscher Mode abgelehnt, tatsächlicher Runtimepfad: ein Hit und ein Stride-Miss;
Fallbackarrays/AABB/Metadaten/Ressourcenname gegen ungecacheten Erwartungsmesh identisch,
automatische relative Manifestpfadwahl. Ein1,064,656Byte-Probecache, kein Weltbake,
kein Cold-FS-/GPU-Upload-/Frametime-/LRU-Lifecyclepass. `checkpoint.json` bindet
alle aktuellen Assets samt Probe/Result/Manifest/Payload. Die relative
automatische Pfadwahl wurde nur temporär im CPU-Test gesetzt; das echte
Produktmanifest hat noch keinen Cachepfad, daher noch kein Standardstart-Treffer.
V14-Caches sind historische Belege, keine Produktcachehits.

Die Gruppierungsdarstellung wurde nach V19-Vergleich beibehalten; der begrenzte
Bake dieser Source-/Atlas-/Generator-/Modeidentität ist inzwischen publiziert.
Eviction-/Rückkehrkontrollen und der endgültige Paketstart bleiben erforderlich.

R5 extrahiert ausschließlich den unveränderten Hit/Miss-/Fallbackpfad in
`load_or_build_fixed_forest_mesh`, damit genau der produktive Aufruf CPU-geprüft
wird. Der R4-Ausdruck `surface_count>=0` war als Fallbackbeleg zu schwach; er ist
durch tatsächliche Array-/Bounds-/Metadatenparität ersetzt. Alte R4-Evidenz bleibt.

## Geometrieidentity v2 nach V19-Bildentscheidung

V19-Gruppierung bleibt Produktmodus `source_grouped_crowns`. Für den begrenzten
352-Cell-Cache ist die endgültige Codebindung in
`camera/source-v2-default-cache-r6/geometry-code-freeze.json` festgelegt.
Die transitive lokale Callback-/Buildclosure wird automatisch aus den fünf
Build-/Sample-Wurzeln verfolgt (16 Funktionen, einschließlich konservativer
V1-Helfer), zusammen mit MODEL_SCALE/EARTH_RADIUS/MAPPING_REVISION und aktiven
Worldbounds. Externe Canonical-/Fixed-Sampler, Generator, Codec und Projection
sowie Source/Upload/Atlas/Mode/Policy/DisplayY bleiben vollständig gehasht.
Der pauschale landscape-Dateihash ist für Cacheidentität ersetzt; der Builder
kann ihn zusätzlich als unveränderliche Start/End-Wache verwenden.
Terrain-/Canopy-Materialshader, reine Uniform-, Telemetrie- und Loaderänderungen
invalidieren identische Geometrie absichtlich nicht. Quellmitgliedschaft,
G/Felspriorität, Höhenstütze oder Generatoränderungen invalidieren weiterhin.
Die konkrete Funktionsliste und Hashes stehen im Freeze. R5 ist der letzte
beobachtete tatsächliche CPU-Hit/Miss-PASS, v2-Identity-Nachprobe folgt nach dem
laufenden fremden GPU-Fenster. Keine neue GPU- oder Performancefreigabe daraus.

## Beobachteter aktueller Produktstandard

`camera/source-v2-v19-product-cloud-r1/checkpoint.json` bindet den tatsächlichen
kombinierten Stand und seinen Harness, Rohdaten sowie vier PNGs. Session34031
endete Exit0 ohne Fehler. Produktbindung SHA
`b4dd913322583213ae66f76c4de0b08cb50154a6e6a39173e06744975be0fa57`,
Runtime `c3c42ef787e25b5b8af77847a90de7b67477dacfd9f52b02b5004a7fab67c6d9`.
Kein Dataset-/Cache-CLIoverride: SourceV2 und aktueller Produktteilcache wurden
automatisch aus der Datei gelesen.

Cache `artifacts/render-data/forest-cache-sourcev2-v19-frusta-r1/manifest.json`,
SHA `5bb618e402de7e8e0855be2ecf5d2a1273c07a837a08d46a9cdfe0f1a1b033d5`:
352Stride1-Einträge inklusive61leerer,264164536Payloadbytes. Das ist genau die
Union der drei beobachteten Frusta, keine ganze Region und keine anderen Strides.
Der CPU-Bake brauchte76.314s inklusive Write; alle352Payloads hatten volle
Array-/AABB-/Metadatenparität. Der zusätzliche tatsächliche CPU-Runtime-APIcheck
nach Mutation der realen Produktbindung bestätigte352Hits/0Misses; seine Log- und
Resultdateien liegen unter `camera/source-v2-v19-frusta-cache-r1`.

Der echte GPU-Produktstart forderte308Cells an und meldete308Hits/0Misses,
0Fallback und1294.384ms kumulierte Ladezeit. Die Nahpose lag in deren bereits
residenter Teilmenge; sie erzeugte deshalb keine weiteren Requests. Keine zweite
LRU oder anderer Stride wurde als Ersatz verwendet. Dieser einzelne Start ist
kein Cold-FS-Benchmark, keine allgemeine Streaming-/Eviction-/Panabnahme.

`camera/source-v2-material-coast-r1` belegt die danach beibehaltene gemeinsame
Darstellungskorrektur: fester kompakter600m-Kernel für sichtbare RGBA-Gewichte,
kanonisches G/CPU-Felsvorrang unverändert; Kurz-SDF-Abstand plus nichtnegative
C1-Fortsetzung des langen grafischen Abstandes statt1–2km-Lerp. Physische Rollen,
Konturen, Atlas und Kronengeometrie bleiben unverändert. **Beide Uniforms wurden
in beiden Bildpaaren gemeinsam0→1 geschaltet**; die Verbesserung ist daher ein
kombinierter Beleg, kein vollständig isolierter Einzeleffekttest. Unabhängig
beobachtet: Materialtreppen und äußere Doppelringe reduziert, weiche Flecken,
Inselhöfe und glatte breite Felsflanken bleiben. A08 bleibt FAIL. Der gespeicherte
250m-Transect löst selbst keinen Umkehrfall auf und beweist keine Ringursache;
der alte skalare Mischoperator hat jedoch einen reproduzierbaren Gegenfall.

Aktuelle Cloudmodule entsprechen dem separat berichteten CloudV10-Stand. Ein
Prozess führte `far_off/on` bei2952×524/3.4Mm und `near_off/on` bei1920×1080/240km
aus. Fenster vor Planung stabilisiert; Queues vollständig0 und8stabile Frames,
danach Landschaftsprozess für die statischen Renderintervalle eingefroren.
Cloudzeit0 eingefroren; kein Drift-/Live-Animationsclaim aus dieser Serie.
Je Phase16normale Warmupframes und90Messframes ohne parallelen CPU-Bake.
OFF/ON behielt Waldstützstride und Wanted-Chunksignatur; beobachtete
Ankerprojektionsänderung höchstens0.000061px.

| Statische Phase | Wallmedian ms | Wallp95 ms | Readiness-Drawcalls |
|---|---:|---:|---:|
| Fern OFF |29.670|30.934|567|
| Fern ON |63.4485|67.460|568|
| Nah OFF |8.3235|8.779|36|
| Nah ON |10.340|10.446|37|

GPU-Zeitstempel waren nicht verfügbar (`null`, nicht0); Primitive wurden nicht
erfasst. Die Drawcalls stammen aus dem letzten passenden Readiness-Telemetrieframe,
nicht aus einer separat instrumentierten gesamten90-Frame-Phase. Der Provider
lieferte konservative globale `natural_max_y=82.211`, Cloudbottom83.311 und
Cloudtop121.311Godot-Y; keine erneute Quell-/Darstellungsskalierung.
Das sind beobachtete statische Renderwerte auf demM3Pro, kein Gesamtapp-/
Navigations-/iPad-/Leistungs-PASS. Der Runtime-Gesamtmax enthält absichtliche
Harnesspausen zwischen den eingefrorenen Phasen und ist kein Tourspikebeleg.

OFF/ON bedeutet denselben **projizierten Landschaftsausschnitt**, keine identische
vollständige Kamera-/Clipkonfiguration: Wolkenreserve verändert Kameraposition
entlang der Blickachse und FarClip. Target/Breite/Basis, Waldsignatur und die
beobachteten Ankerprojektionen bleiben gleich. `summary.json:camera_clip_pairs`
zeigt die tatsächlichen getrennten Werte. Die OFF/ON-Wallzeiten sind ein aktueller
Produktvergleich, kein isoliertes Material- oder Wolkenshaderprofil.


## 2026-10-26: echte Bedienung und begrenzte asynchrone Waldarbeit

Status **implementiert**, enger kalter OS-Scroll-/Resizepfad **validiert**;
volle Bildvollständigkeit, tiefe Navigation und A12 weiter **offen**.
Referenz ist SourceV2/V19/CloudOFF. V20/V21/V22 sind verworfene
Darstellungsversuche und kein Produktwechsel.

Der bisherige synchrone Generator blockierte die reale kleine Scrollaktion
bei 1440×810: 1508 Stride0-Zellen, 104 s Factoryarbeit nach 467 ausgeführten Misses.
Der neue Pfad benutzt einen unveränderlichen Source-/Atlas-Kontext, genau
einen Worker, volle Wantedmitgliedschaft bei 64 eingereihten Jobs, maximal
zwei CPU-Datenergebnisse/16 MiB und höchstens einen Mainthread-Meshcommit pro Frame.
Weiterhin benötigte Tuples bleiben bei Prioritäts-/View-Epochenwechsel erhalten.
Worker erzeugen weder SceneNodes noch Meshes/RIDs. Kronenarrays werden vorab
im Mainthread bereitgestellt; der Stylegenerator liefert PackedArrays/Metadaten.

CPU-Belege: `camera/forest-async-array-split-r2/` und
`camera/forest-async-queue-p2-r2/`. Alle getesteten Array-/Rohsurface-/AABB-/
Metadatenwerte stimmen mit dem eingefrorenen ursprünglichen Generator überein.
Die AABB-Berechnung verwendet einmalige Min-/Max-Reduktion statt akkumuliertem
AABB.expand; die frühere Ein-ULP-Abweichung bleibt im r1-Replay erhalten.
Der Queue-Fallback reserviert nach einem fehlerhaften kleinen Cacheeintrag
vor Generatorarbeit erneut volle Kapazität; fehlende Payloads führen nicht
zu einem falschen Oversizedabbruch. Beide konkreten Fehlerbelege bleiben erhalten.
Das nach dem Fix gebundene [`aabb-reproduction.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/forest-async-array-split-r2/aabb-reproduction.json)
(SHA-256 `bd49f6dd82cbc2512be495e87c895d677ddde1316e1b876f4316a32b3f84d340`)
enthält acht exakte Fälle ohne Fehler, einschließlich `(-2,2)`; unabhängiger
Review bestätigt 8/8. Finale Inputidentity ist `091c5a48c0d67411fe1c69a94b1a8617019fa515602191c249c59dd2b9aa232a`.
Der historische r1-Ein-ULP-Fehler bleibt abgegrenzt. Alte Cacheheader bleiben
strikt abgewiesen; dieser Replay erteilt keine Kompatibilitätsfreigabe.

Echte native Probe: `camera/source-v2-native-input-resize-async-r3/`.
Kleine Scrollaktion, tatsächlicher Fenstereckendrag 1440×810→1154×670→1440×810,
Gegen-Scroll und reguläres natives Schließen wurden verarbeitet; Exit 0.
813 kalte Builds/0 Fehler/1 Cancel, Spitzenrückstand 2100 fehlende sichtbare Zellen,
511 sichtbare Meshes; der Wald war während des Aufbaus nicht vollständig.
Commitmax 1.376 ms, gesamte Forest-Mainthreadfunktion max 9.031 ms; Gesamtframewerte
p50/p95/p99/max = 10.341/14.187/15.278/165.845 ms inklusive Diagnoseaufnahmen.
Keine daraus erfundene Leistungsgrenze oder allgemeine Bedienfreigabe.

Der damalige native Nachweis verwendete ausschließlich kalte Generatorarbeit;
die darin offene Kompatibilitätsentscheidung wurde inzwischen durch das unten
beschriebene enge Refaktorgate geschlossen. Die 768-Zellen-Residencygrenze ist bei
mehr vollständig Wanted-Zellen weiterhin weich. Alte Supportmeshes werden bis
zum passenden Zellnachfolger behalten; transiente staleSupporthöhen sind
protokolliert und nicht als Oberflächenparität abgenommen.

Der vollständige River-Set-LRU behebt die identische Übersichtsrückkehr
(Start/erste Endpose/Endhold in R4 pixelidentisch). Er behebt die Flüsse während
kontinuierlicher Navigation ausdrücklich noch nicht: exakte Breite/Pitch im
Baukey brechen laufende Gesamtsets ständig ab. `camera/river-set-cache-r1/real-tour-causal.json`
bindet diesen weiterhin offenen Regressionsbefund.

### Enges Refaktorgate nach der kalten R3-Probe

Status **validiert** im ausdrücklich begrenzten Metadaten-/Payloadumfang;
20 kleine CPU-Konfigurations-/Payloadprüfungen bestanden, unabhängiger Review
ohne P1/P2. Ein tatsächlicher neuer Appstart bleibt offen.
`forest_mesh_cache_identity()` bindet nun auch die aktive Datei
`fixed_forest_build_context.gd` regulär. Die neue Consumeridentity lautet
`dffeea1d79afdfb773e8ac7b0633e83ba8426451ce0c4a7a756fa272dc1ef9c9`.

Die Produktbindung verweist ausdrücklich auf die gehashte Definition
`artifacts/render-data/forest-cache-refactor-compatibility-r1/compatibility.json`,
SHA-256 `91b4c10f97dba4eb08ffc0b771f49deb41df1d4f32ef151bea0998093e18547f`.
Nur Producer `92a357fd9ecde784d0371b1221226b0fda66b30024627a10730016f28a4325f0`
aus dem unveränderten Manifest `9280e9cd0361909ee404ee267446f5e7b9c575cc9733fba6891e6c51e98c0285` ist damit
wiederverwendbar. Generator-/Codec-Refaktor und neu expliziter Context sind die
zulässigen Unterschiede; alle übrigen Source-/G-/Mode-/Policy-/Support-/
Projektionsabhängigkeiten müssen gleich sein. Aktive Codepins und Engine sind
zusätzlich exakt gebunden. Der unveränderte strenge Loader prüft weiterhin die
originalen Producerheader, der Scheduler verwendet die neue Consumeridentity.
Kein Header wurde umgeschrieben und kein neuer Cache gebacken.

Unabhängiger Review [`review.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/review/forest-cache-context-gate-r2-independent/review.json),
SHA-256 `67295f9fb361d6fd37436ad072527445f9731bed1070574d579481c2b83f0578`,
bestätigt 20/20 Headlesschecks (Exit 0), zwölf exakt passende Dateihashes und
keine P1/P2-Befunde.
Beleg `camera/forest-cache-context-gate-r2/`: Die Prüfung ruft den tatsächlichen
Runtime-Konfigurationspfad mit den vollständigen Identitätsmetadaten auf, ohne
Source-Raster zu laden. Ein echtes altes Payload wurde geprüft/materialisiert;
Stride0 bleibt ein Miss. Zukunftsänderungen, falsche Definition/Engine und ein
CLI-Verzeichnisoverride erhalten keine pauschale Ausnahme. Dieser CPU-Beleg
behauptet keinen vollständigen neuen Appstart oder Leistungspass. Die Definition
ist eine neue tatsächliche Laufzeitdatei und muss in künftigen Paketinventaren
enthalten sein; ihr Forschungsbeleg ist reine Herkunftsmetadaten. Der Gateumfang
ist Metadatensicherheit plus ein echtes Payload: keine native Warmcache- oder
Vollabdeckungsprüfung, kein GPU-/A12-/A08-Nachweis. Sichtbarer Wald bleibt
unvollständig, Flussverhalten während der Fahrt offen; V23-r2 externe Studie
verworfen.

## Ground- und Layoutprovider-Integration R2

Status **implementiert**, der gezielte Ground-/Layout- und aktive
Geometry-/Shaderidentity-P2 unabhängig **validiert/geschlossen**; keine
Vollweltabnahme. Der Runtimecheckpoint
[`v19-ground-layout-integration-r2/checkpoint.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-ground-layout-integration-r2/checkpoint.json)
hat SHA-256 `ff3a9b919a97b9911b3bff51adaa27f52dea7a4baeb7c868f494d850f23a6885`.
Der unabhängige [P2-Recheck](../../runs/kit1-gamegraphics-v2-2026-10-25/review/final-ground-layout-r2-p2-independent/REVIEW.md),
SHA-256 `95e094771b70fde8615b86913a2cb1936e386b11f3eccb958821b22dea0c0f4b`,
hat 72 gezielte Identity-/Bindingchecks bestanden und alle 19
Checkpointbindungen bestätigt.

Die Runtime-Whitelist dieses Checkpoints ist:
`app/scripts/landscape.gd`, `app/scripts/cache/fixed_forest_build_context.gd`,
`app/scripts/cache/fixed_forest_ground.gd`,
`app/scripts/cache/fixed_forest_layout.gd`,
`app/tools/build_complete_forest_layout.gd` und
`tools/compile_complete_forest_layout.py` sowie der exakt bytegleiche
Offlinecodec `tools/forest_layout_codec.py`. Der Compiler importiert nun diesen
lokalen Codec; gegenüber dem eingefrorenen Research-Tool wurde nur der
Importlocator geändert. Das Codec-/Import-/Format-/Float64-Roundtrip-Smoke ist
separat gebunden, ohne Source-, Godot-, GPU- oder Bake-Ausführung.
Die transitive Abhängigkeit
`app/scripts/river/river_g_snapshot.gd` wird von Layoutfactory und
Compactbinding für die reale `runtime_geometry_binding()` geladen. Ihr
separater [Review](../../runs/kit1-gamegraphics-v2-2026-10-25/review/river-g-snapshot-r1-independent/review.json)
mit SHA-256 `be361908e20c009030835ec513f965ba710a5d9d68a2fb26cc8a01c6930bc7de`
bestätigt 181 Checks. Das Modul ist eine benötigte Geometrybindung und keine
fertige Riverintegration.

Der notwendige Codec-Relokationsnachweis ist im
[`codec-relocation-checkpoint.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-ground-layout-integration-r2/codec-relocation-checkpoint.json)
mit SHA-256 `07f318314d2348fec1f2144b3edbde12ff9dea5b6d246120ce4825a49355f5b6`
gebunden. `tools/forest_layout_codec.py` entspricht bytegenau dem zuvor
geprüften Codec (SHA-256
`f9300a1efbefc89074bc62de27c5d9c764087fdcb604362d5a07ef4c3a0d216e`); der
geänderte Supervisor
`tools/compile_complete_forest_layout.py` hat SHA-256
`1193a9f12bb6c1d2e7542d2158b1f26c1f36cee8bc5dd0ef9d1f6b2a8b44b5e4`.
Der [Smokebericht](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-ground-layout-integration-r2/codec-relocation.json),
SHA-256 `523e7d6111496fa52fcee59e38c2bfb270c49abe446c5e0b974ea457268c7c28`,
bestätigt Import, 128/128/64-Bytecontainerformat und exakten F64-Roundtrip.
Der originale r2-Checkpoint bleibt byteunverändert. Der vollständige Compiler
ist damit als lokales Tool schlüssig, aber es wurde weiterhin kein vollständiger
SourceContext-Bake ausgeführt.

### Ground, Memoisierung und Layoutprobe

Die bisherigen r1-Belege bleiben klar begrenzt: 11.220 Groundchecks, 60
Reader-, 41 Context-, 7 Container- und 10 Memo-Checks. Der neue
Layoutfactoryvertrag bindet tatsächliche Runtime-G-Funktionen sowie Terrain-
und Samplingshader in die Layout- und Compactconsumeridentität. Änderungen
invalidieren alle neun Supportidentitäten; die alte Expandedcache-Kompatibilität
bleibt strikt und akzeptiert den neuen Style-/Context-/Ground-Code nicht.

Die finale Groundabbildung behebt im CPU-Trace den zuvor gefundenen Fehler von
maximal 38,1111154 Quellmetern zwischen altem Waldhelper und tatsächlicher
Terrainfläche. Das ist gezielte CPU-Consumerparität; keine pauschale GPU-Parität
oder allgemeine F64/F32-Toleranz. Die joblokale Memoisierung bleibt exakt und
quellgebunden.

Der finale [Layoutprobe-r4](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-complete-layout-provider-r1/probe-r4/manifest.json)
hat Manifest-SHA-256 `de8e6d5eda2829d50dff97521c3ed018b55c8bb00557ac83035c170b831b60c7`.
Acht tatsächliche Zellen mit 419 Quellenrecords und acht Layout64-/Ground0-
Metadatenströmen stimmen bytegenau mit r3 überein. Der Probeumfang bleibt
`incomplete-probe`; die synthetische 3116-Zellen-Index-/Publikationsprüfung
steht nicht für einen Quellenbake. Vollständiger SourceContext-Bake und
Weltabdeckung sind **nicht** erfolgt.

Compact bleibt **default OFF / Expanded**. Der bisherige native Compactlauf
fehlte nach Resize-Rückkehr 1077 von 1508 Wanted-Zellen; vollständige
Bereitschaft und Waldfüllung sind offen. A08 bleibt **FAIL**, A12 und
Vollabdeckung **offen**. Die regionale Sechsansichten-Diagnose ist angelaufen,
aber noch nicht stilistisch abgenommen. Bestehende Source-r3-Fails, A07,
Bundlegrenzen und Fluss-Nahnavigation bleiben offen.

### Vollständiger Layout-r3, native Abdeckung und Produktdefault

Der deterministische [Layout-r3-Neubake](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-analytic-bounds-complete-r3/HANDOFF.md)
ist nach unabhängig bestandenem Bounds-Integrationsreview atomar READY publiziert.
Checkpoint-SHA `58a626ecdb914ac9995294c85e9640fed8b9f95760c1970824f39ae163436732`.
Der r3-Bake hat wie r2 3.116 Zellen und 176.609 Records; der Container ist
14.197.868 B, alle Recordbytes behalten denselben Digest. Der Bake dauerte
378,467 s. Das ist vollständige Coverage des gebundenen Layoutkontexts, keine
Vollabdeckung der Projektregion.

Der echte [native Scroll-/Resize-Lauf](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-native-layout-bounds-r1/HANDOFF.md)
erreichte volle Waldabdeckung in geprüften Posen und Cold-Coverage 3.023,281 ms
statt 9.277,929 ms. Resize war vollständig; Commits max. 0,369 ms. Frames
p95/p99/max 19,296/22,349/173,273 ms; das ist kein A12-Pass. Übersicht, kleine
Resizeansicht und Rückkehr waren pixelidentisch. Fertige alte/neue Scrollposen
unterscheiden sich an genau einem Pixel (768,234), obwohl Records, Kamera und
Riverkey gleich sind; Ursache offen, keine kausale Pixelparität behaupten.
Checkpoint-SHA `9a81f0652b51a8957b9948739f608cf0d44bd2a5c78f91a6d6b10ee5e5db29d0`.

Der [Produktdefault-/Closure-Checkpoint](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v19-complete-layout-default-r1/HANDOFF.md)
hat finalen Checkpoint-SHA `47a9513dfb15c5e7fb3ac8875d9eadafd6e61ef5435c1b806bfc6ab79eadd91e`.
`renderer-binding.json` wählt Compact und das relative vollständige Layout-r3
mit exaktem Manifestpin; falscher Pin oder fehlender Pfad fail-closed. Die
gehashte Closure bindet Manifest, Binding, layout.bin und READY (14.206.103 B).
Das ist kein neuer App-Bundle-/Relocationbau. Cloud-Default bleibt getrennt OFF.

Die eingefrorene Snapshot-Copyinclude-Closure wurde durch
`tools/runtime_snapshot_preloads.py` ergänzt. Der unabhängige Regressionbeleg
[`COPY_INCLUDE_REGRESSION.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/cloud-current-layout-basis-r2/COPY_INCLUDE_REGRESSION.json),
SHA `a2c36dd4744d72a0ca0a0667507cbec9875ca9d0a104698b32634ba982331b61`, weist
nach, dass die alte unvollständige Kopie abgewiesen und genau das benötigte
`forest_residency_eviction.gd` hinzugefügt wird. Das Closure-Addendum
[`CLOSURE_ADDENDUM.json`](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/cloud-current-layout-basis-r2/CLOSURE_ADDENDUM.json),
SHA `76f00b83c204d633d30b49e47bfbda2f3fe1c4fdefde85b748dd60af5af87804`, bindet
die 2.001-Byte-Datei und die statische Closure aus 19 Modulen/18 Kanten ohne
Lücke. Paket-Inventarfunktion blieb unverändert. Die Regression lief im bereits
gebundenen Checkpoint; hier wurde kein neuer Test ausgeführt.

A07 bleibt offen: der externe Einzelkronen-/Größenbeleg hat einen engen
unabhängigen Quellen-/Schema-Teilreview ([Review](../../runs/kit1-gamegraphics-v2-2026-10-25/review/a07-single-crown-r1-independent/REVIEW.md))
bestanden. Produktkameraausschnitt und echte Screen-Bounds für eine Einzelkrone
sowie mehrere Hausbreiten samt Umfeld fehlen.

**Wiederaufnahme:** die ungeklärte Ein-Pixel-Abweichung (768,234) untersuchen,
ohne Ursache vorwegzunehmen; Framespitzen und LRU-Sortierrest getrennt prüfen.
Cloud-V16-Integration und Review abschließen; Produkt bleibt bis dahin OFF.
Regionale r3-Sechsansichten sind verworfen; Strukturpfad hat kein READY/Bildpass.
A07-Kameraausschnitt, A08 **FAIL**, A12, Projektregion-Vollabdeckung, aktuelles
Bundle und finale A01–A16 bleiben getrennte offene Punkte.

### Wolken — aktuelle Nutzerkorrektur

Der Nutzer hat via autorisiertem Cloudchat klargestellt: Wolken verbessern und
aktivieren; OFF dient nur der Diagnose. V16 wurde in privater GPU-Kopie geprüft,
ohne Qualitäts- oder Leistungsfreigabe. Produktdefault bleibt bis Integration
und Review OFF; Umschaltung und kombinierte Terrain-/Wolkenprüfung sind offen.
Die frühere v7-Ablehnung bleibt bestehen.

## Compact-Forest-Integration R2

Historischer R2-Stand; der folgende damalige Expanded-Default wurde durch den
späteren Layout-r3-Produktdefault unten im aktuellen Wiederaufnahmestand ersetzt.

Status **implementiert**, eng quellengebunden und unabhängig **validiert**;
Compactflag war in diesem Checkpoint inaktiv und Produktdefault **Expanded**. Der eingefrorene
[Zellcapture-Checkpoint](../../runs/kit1-gamegraphics-v2-2026-10-25/camera/forest-compact-cell-capture-r2/checkpoint.json)
hat SHA-256 `0f6512706024905940c535f4bfc23d9bdc6598ec1167784a60b5a972364fd21e`.
Der unabhängige [Integrationsreview](../../runs/kit1-gamegraphics-v2-2026-10-25/review/forest-compact-integration-r2-independent/review.json)
hat SHA-256 `a9aa073a674fca273c886c3adf1568cd86bb1b569bb76571762e4197370d151e`,
48/48 Datei-/Checkpointbindungen, zehn synthetische Recordfälle, sieben
Compact-Queueprüfungen, acht Lifecyclegruppen und 20 Identitychecks bestätigt;
keine P1/P2-Befunde. Er hat neun bereits erfasste GPU-Zellpaare geprüft, selbst
aber keinen GPU- oder nativen Appstart ausgeführt.

Der bestehende Expandedcache bleibt streng: der neue Style-/Context-Hash
invalidiert ihn; es gibt keinen warmen Expandedcache-Pass. Compact bleibt ein
reversibler expliziter Pfad. CPU-Recordaufbau für 191 Kronen dauert
240,416–281,311 ms; ein CPU-Speedup ist nicht belegt. Tatsächlich serialisierte
DTOs lagen bei höchstens 14.068 Bytes, gegenüber 84.744 Bytes für das dichte
1369-Record-Fixture. Das stützt nur eine begrenzte Transport-/Speicherreduktion;
kein Prozess-/GPU-Speicherpass. Mainthread-Materialisierung und Queue-/Lease-
Lebenszyklus sind im eingefrorenen Codepfad geprüft.

Die neun sichtgeprüften GPU-Paare sind nicht pixelidentisch: bei den nichtleeren
Fällen änderten sich 34–189 Pixel pro 1.166.400, mit maximal vier bis neun
RGB-Codes je Paar; leere Zellen waren identisch. Der Reviewer sah lokale
Kronen-/Facet-/Kanten-/Schattenpixelabweichungen, keine breitflächige
Materialverschiebung. Das ist keine genehmigte allgemeine Bildtoleranz und keine
globale visuelle Gleichwertigkeitsbehauptung. Keine Vollwelt-/Native-/A08-/A12-
Abnahme: sichtbare Waldfüllung, Warmcache-/Pan-/Zoom-/Resize-Rückkehr und
Leistung bleiben offen.

V25 ist ein lokaler Sicht-`keep` für den reparierten Landschaftsübergang; die
globale Form bleibt **A08 FAIL**. Der [V25-Handoff](../../runs/kit1-gamegraphics-v2-2026-10-25/geometry/v25-bounded-transition-r1/HANDOFF.md)
und [unabhängige Datenreview](../../runs/kit1-gamegraphics-v2-2026-10-25/review/v25-bounded-transition-r1-independent/review.json)
betreffen den lokalen Kandidaten, keine Produkt-/Runtimefreigabe. V23-r2 externe
Studie bleibt verworfen. Keine der V25-Artefakte ist Bestandteil dieses
Compact-Integrationscommits.
