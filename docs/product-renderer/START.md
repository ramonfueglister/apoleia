# Landschaft lokal starten

Referenz: kit1-landscape-v5 / kit1-rendering-v4. Implementiert und auf Mac mit Godot4.7.2, Metal, AppleM3Pro geprüft. Kanonische Quelle landscape-v3: heutiges ETOPO2022v1-15s, ESAWorldCover2021v200, NaturalEarthv5.1.2; keine historische180er-Rekonstruktion. CPU-/GPU- und Geografiegrenzen stehen im Daten-/Prüfbericht.

Vom Repository aus:

```sh
./scripts/build-landscape
./scripts/run-landscape
```

Die Quellen-/Datenaufbereitung steht in docs/product-data/README.md; Daten fehlen in einem frischen Clone bis zu deren reproduzierbarer Ableitung. Repo-Build/Start benötigen vorhandenes Godot4.7.2 und Python mit NumPy2.5.4. Keine automatische Installation, SDK-Änderung oder Veröffentlichung. Die Startskripte validieren/generieren ausschließlich die eigenen quellgebundenen GPU-Uploadrepräsentationen; eine fehlende oder korrupte Basis wird verweigert. Es entsteht keine Ersatzlandschaft.

Ein lokales Mac-App-Paket einschließlich vorhandener Godot-Binary, Engine-Lizenz/Notices, eigener Quellen, benötigter abgeleiteter Daten und Quellenattribution entsteht mit:

```sh
./scripts/build-landscape --package
```

Erstbau-Ergebnis: artifacts/Roma Aeterna.app. Das abschließend geprüfte Paket dieser Revision steht unter artifacts/Roma Aeterna Final.app. Bestehende Pakete werden nicht überschrieben; eine neue lokale Revision kann nach dem Build mit `python3 app/scripts/package_macos.py --output "/absolute/path/New Name.app"` getrennt assembliert werden. Das fertige Paket enthält seine Runtime und Startdaten; ein separat installiertes Python/Godot ist dafür nicht erforderlich. Keine Rohdaten, fremden Stil-/Spielbilder oder Editorcaches werden hineinkopiert. Das Paket ist lokal, unsigniert und nicht notarisiert; kein Release wird veröffentlicht. Konkreter Build-/Startbeleg und Inventarhash stehen im Handoff.

Mausrad oder Trackpad-Pinch zoomt kontinuierlich. Linke, mittlere oder rechte Maustaste gedrückt halten und ziehen verschiebt. Trackpad mit zwei Fingern verschiebt ebenfalls. Fenster schließen beendet die Anwendung und schreibt die tatsächlichen Interaktions-/Kameraprobes extern. Es gibt keine sichtbaren Bedienhilfen, GUI, Raster oder umschaltbaren Ansichten. Die Kamera dreht sich nicht frei.

Kanonischer normaler Prüfpfad mit vorab gehashtem Fixture und unabhängiger Prozess-RSS-Messung:

```sh
python3 app/scripts/measure_runtime.py --out /absolute/run --renderer mobile --duration 48 --fixture /absolute/path/to/fixture.json
```

Zusätzlich `--capture` erzeugt echte Framebuffer-JPEGs mit Originalzeitstempeln und verlustfreie PNGs derselben Schlüsselframes. Die begrenzte Encoderqueue hat maximal zwei Jobs; Queuepeaks und ausgelassene Aufnahmeversuche bleiben im Rawreport. Die Messung mit Capturelast ist getrennt vom normalen Benchmark. `encode_capture.py /absolute/run` schreibt daraus eine ungeschnittene VFR-MP4 ohne Retusche oder synthetische Zwischenbilder. `analyze_runtime.py` und `analyze_lod_motion.py` liefern unabhängige Quell-/Projektions-, Randpaar- und Bewegungsstichproben. Rawstates sind volle IEEE64-Werte; Camera3D-Basis und -Projektionsmatrix werden gelesen. Solche Probes ersetzen keine Bildmerkmalserkennung oder unabhängige visuelle Prüfung.

Derselbe Pfad mit `--renderer forward_plus` ist der gebundene Backendvergleich. Beide Backends sind tatsächlich auf dem Mac gelaufen. Eine unsichtbare Startup-Vorwärmung zeichnet dieselben Mesh-/Material-/Shadowvarianten mit Alpha0 in der vorhandenen Ansicht; tatsächliche Pipelinezähler prüfen, ob beim ersten Baum-LOD keine neuen Varianten entstehen. Startupkosten bleiben im Prozess-/Rohframebericht.

Die kompakte gesamte Region wird vor Erkundung resident geladen. Das native Höhenraster bleibt als ein Float32LE-Bytepuffer resident; vier unveränderte Quelldekodierungen geschehen vor bilinearer Interpolation. Bäume behalten globale18m-Kandidaten und Source-Masken; vorbereitete360m-Renderchunks werden in höchstens400 Kandidaten pro Frame aufgebaut und mit begrenztem LRU-Cache wiederverwendet. Readiness und Kosten bleiben roh messbar. Es gibt keine behauptete laufende IO-/Request-/Upload-Streamingengine. Separate Viewport-CPU-Zeit wird über die native Godot-Mess-API erhoben. Diese Runtime liefert bislang keine validen GPU-Zeitwerte; unbekannte Messungen sind null/nicht-erhoben, keine0ms. Per-Pass-Zeiten werden nicht aus Frameintervallen erfunden. Windows/Linux/iPad sind ungeprüft.
