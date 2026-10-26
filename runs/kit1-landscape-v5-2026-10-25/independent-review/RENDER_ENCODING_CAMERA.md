# Unabhängige Renderencoding- und Kameragegenprobe

25.10.2026; Kit-1-v5, Daten `landscape-v3`. Noch keine unabhängige
Anwendungssitzung bedient. Die folgenden tatsächlich geöffneten PNGs sind
Zwischenstände: `packed-near-check`, `near-material-fix`, `far-material-fix`,
`alpine-material-fix`, jeweils `artifacts/runtime/<name>/frame_000030.png`.

Die Bilder zeigen natürliche Farben, einzelne facettierte Bäume und keine
sichtbare GUI/Bebauung/Raster. Der gepackte Nahblick zeigt aber weitgehend
gleichförmigen grünen Boden und sich stark wiederholende freistehende Kronen,
während die Primärreferenz detailliertere natürliche Waldgruppen und
Boden-/Terrainübergänge zeigt. Dieser konkrete A08-Befund wurde gemeldet;
Grafikowner überarbeitet Waldgruppen/Kronenfamilien/Bodenwirkung. Keine
abschließende Stilbewertung aus diesen Zwischenständen. Die alte Fernprobe
hat ein Alpen-Kameraziel bei Zoom 0 und ist deshalb kein Beleg des korrekt
zentrierten Gesamtüberblicks.

## Signed RG8

Der produktive Encoder und beide Höhenshader wurden gelesen. Unveränderte
kanonische signed Float32-Höhen werden auf zwei lineare numerische Bytekanäle
abgebildet, Eingaberange -8192…8191.75 m, Schritt 0.25 m, gerundet durch
`floor((height+8192)*4+0.5)`. Rangefehler sind fatal, keine Vorflatteningoperation.
Vier Cornertexel werden diskret dekodiert und erst danach bilinear gewichtet.
Die diskrete Ozeanklassifizierung und Meeroberflächenbehandlung erfolgt erst
am Querypunkt nach Höheninterpolation. Der frühere interpolierte Wasserklassen-
Fehler wurde im Code behoben.

Eigene read-only Gegenprobe `encoding_check.py`/`encoding-check.json`:
8192 deterministische andere Bilinearqueries, 32768 Cornerzugriffe, **0
Byteabweichungen**, größter Texelfehler 0.125 m, größter Bilinearfehler
0.12290285495691933 m. Die zusätzliche vorab deklarierte Encodinggrenze
0.125 Quellmeter bleibt vom alten Source-/Generalisierungsbudget getrennt;
Modellscale 0.001 entspricht 0.000125 Modelleinheiten.

Der vollständige Packedhash ist
`500799c49ec324054206b40319a010a68a508728b226d73d7c3ec30a1c8cb9ae`;
Packedmanifest/Quellhash/v3-Manifestbindung stimmen. Die separate Gegenprobe des
Datenowners über alle 121478400 Texel wurde als zusätzlicher Beleg gelesen.
Eigene Stichprobe und statischer Shaderbefund beweisen keine tatsächliche
GPU-Arithmetik, gerenderten Morphflächen oder Bildschirmgenauigkeit.

## Tatsächlich gefundener und gezielt korrigierter Kamerafehler

Read-only Rawanalyse `artifacts/runtime/final-mobile-normal/runtime.json`
(noch vor Kamerakorrektur): Bei 46579.207 ms/Zoom 0.06413301736 waren alle
sichtbaren Anker einschließlich des Meerhöhenankers gegenüber dem protokollierten
Profil um etwa 2.014 px in y versetzt. Maximum 2.0141799 px lag über 2 px.
Diese 2 px stammen aus dem vor GPU-Prüfung gebundenen A16-
`screen_error_px`-Budget der Datenpolicy (policy-v2, SHA-256
`19be099d04d5b6e5520b94a84581ed79e729e21c56688ee1e378c5e543ad7dd1`,
in PRELIMINARY.md vor dem ersten GPU-Run erfasst; v3-Budgets unverändert).
Die Kamerakomponente ist Bestandteil dieses Source→Render-Screenfehlers.
**Die separate formale A05-Mappingresidualtoleranz im Operationsvertrag war
noch offen.** Sie wird dadurch nicht rückwirkend auf 2 px festgelegt und
dieser Befund vergibt keinen formalen A05-Grenzwertpass.
Aus neun echten `Camera3D.unproject_position`-Probes und tatsächlicher Kameraposition
rekonstruierte eine unabhängige lineare Gegenrechnung die tatsächliche Screen-up-
Achse annähernd [0,0,-1], also 90° Elevation statt protokollierter 89.9599313°.
Die Kameraposition war bereits geneigt versetzt; `look_at` hatte in dieser
Godot-Runtime den kleinen Pitch nicht bewahrt. Kein Terrainhöhenfehler.

Grafikowner ersetzte dies durch eine atomar gesetzte orthonormale Transformbasis
und exportiert nun tatsächlich gelesene Basis/Projektionsmatrix/Elevation.
Die reale gezielte GPU-Gegenprobe `artifacts/runtime/camera-pitch-fix/runtime.json`
wurde unabhängig mit `runtime_review.py` ausgewertet:
36 sichtbare Ankerprobes, größter Scalar-gegen-Camera3D-Projektionsrest
**0.000080768 px**, tatsächliche Elevation 89.9599312825° passend zum Profil.
Beleg `camera-pitch-fix-review.json`. Der konkrete Fehler ist in diesem Zustand
behoben; die vollständige finale Hin-/Rückfahrt muss weiterhin geprüft werden.

## Build-/Messgrenzen

`scripts/build-landscape` erzeugt die Renderrepräsentation und importiert/parst
das Godot-Projekt. Vorliegende Parseausgabe enthält keinen GDScriptfehler;
der Editorimport protokolliert eine fehlende Schreibberechtigung für globale
Editorpräferenzen im Benutzer-Library-Verzeichnis. Das ist keine erfolgreiche
globale Einstellungsänderung und kein Produktgeometrienachweis.

Der frühere normale 48.0035-s-Lauf enthält alle 5468 Frameintervalle, p95
9.027 ms, p99 24.438 ms, max 146.133 ms; Godot-GPUmonitor maximal 801538048 Byte,
externes `ps`-RSS maximal 1825947648 Byte. Das sind echte Befunde dieses
Vor-Kamerafix-Builds und kein automatisch auf spätere Builds übertragener Pass.
PNG-Readbackläufe sind separat als Capturelast zu beurteilen. Pipelinezähler
liegen vor; kalter/warm markierte Cachekontrolle und eine vollständige
Streaming-/Uploadlatenzmessung werden dadurch allein nicht bewiesen.
