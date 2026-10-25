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
