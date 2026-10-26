# Grafik-/Integrationsübergabe

Referenz kit1-landscape-v5 / ops-v5 / rendering-v4. Status: implementiert und auf Mac mit Metal/AppleM3Pro tatsächlich gestartet. Unabhängige Schlussabnahme des finalen Belegsatzes steht aus; keine Selbstfreigabe aller A01–A16.

Finales eigenständig startbares Paket: `artifacts/Roma Aeterna Final.app`. Doppelklick oder `Contents/MacOS/RomaAeterna`. Binary, Engine-Lizenz/Notices, Quellenattribution, benötigte abgeleitete Daten und eigene GPU-Uploadrepräsentationen eingebettet; kein externes Python/Godot nötig. Lokal, unsigniert/nicht notarisiert, kein Release veröffentlicht. Keine Rohdaten/Spielassets/Stilbilder/Editorcaches gebündelt.

Build: `python3 app/scripts/package_macos.py --output "/Users/ramonfuglister/Coding/vic3-clone/artifacts/Roma Aeterna Final.app"`, Exit0. Bundle selbst mit `--resolution 1920x1080 -- --snapshot --view 17.5 39.5 0 --capture-dir <external output>` tatsächlich gestartet und beendet, Exit0; vollständiges PNG geöffnet. Inventar79Dateien,0SHA-/Größenabweichungen, SHA21f9e5a4ceabe3ee7fc146fdb1ad4474879de451250b2bab685441191c3391d3. Notices: `Contents/Resources/GODOT-LICENSE-AND-NOTICES.txt`; Attribution `Contents/Resources/world/data/sources.json`. Keine pauschale Rechtszusicherung.

Renderer Source32692e62a00683419f562793b506e7199f871e782cc2ecf7dc07afc7f34d97a5. Dataset landscape-v3 unverändert; prospektive Fixture/Controls/Threshold unverändert. Vollständige Hash-/Start-/Messbindung: `artifacts/runtime/release-v2-handoff.json`; Freeze `release-freeze-v2.json`. Alle früheren Outputs bleiben unverändert, einschließlich des ersten Final-RSS-Fehllaufs.

| Normaler48s-Pfad | p95/p99 ms | RSSPeak Bytes | GPU-MonitorPeak Bytes |
|---|---:|---:|---:|
| release-v2-mobile-normal | 9.078 /9.515 | 1,859,371,008 | 916,914,176 |
| release-v2-forward-plus-normal | 9.386 /10.189 | 1,831,600,128 | 972,734,464 |

Vorabziele p95≤16.7ms,p99≤33.3ms,RSS≤2048MiB,GPU≤1024MiB. Beide Normalpfade innerhalb dieser Grenzen; rohe Startupmaxima141.9767/1224.069ms nicht entfernt. Mobile Standard. Separate native Viewport-CPU-Zeit erhoben; GPU-Zeit-API liefert keine validen Werte, per-pass API nicht verfügbar. Unbekannte Werte null/nicht-erhoben, nicht0ms und nicht aus Framezeiten erfunden. Prozesswall enthält Laden/Startup/Teardown.

Die konkrete Waldregenerationskaskade ist behoben: globale18m-Kandidaten bleiben identisch,360m-Renderchunks erzeugen höchstens400Kandidaten/Frame, bulk-MM-Uploads, LRU und Readinessfade. Unabhängig18459Kandidaten exakt gegengeprüft: Seedposition/Familie/Sourcecover10/detailwater0/SDF<-20m korrekt, keine Doppelzellen. Im Finalpfad ForestCPUmax8.163/7.533ms; Pipelinevorwärmung unverändert. Gesamte Geodatenresident vor Exploration, keine behauptete IO-Streamingengine. Native Höhenbytes werden exaktFloat32LE dekodiert, ohne zweite vollständigeFloat32Array-Konvertierung;4099Extrema/negative/bilineare Vergleichsabfragen bitgenau.

A05sichtbare Ankerreste beiderNormalpfade max0.6560332068414252px, TileMismatch0; vollständige tatsächlicheBasis-/Projektions-/Anker-/LOD-/Morph-/Motionprobes liegen roh vor. Vier nicht tatsächlich gerenderte Derivat-/Levelkombinationen bleiben NA, keine dreifach kopierte Freigabe. Original protected-ridge-4 liegt im Meer und bleibt unverändert als ungeeigneterpositiverAnker dokumentiert; unabhängig prospektiv gewählter Zusatzpunkt36.0479167/36.3395833 hat native1752m/kind0 und separat echten GPU-/Meshbeleg.

Pan: echter unabhängigerCUADrag undRückdrag/Wheel bestätigt. OperationalerPressstate undPositionsdelta nurbei fehlendemrelative; gültigesrelative nie doppelt. A08Mittelfarbenblöcke kosmetisch entkräftet, tatsächliches PNG unabhängig geöffnet. Höhen/Küsten/Vegetationsmasken unverändert. RepräsentativeBäume, keine vermessenenEinzelorte, keine historische180erGenauigkeit.

Finaler ungeschnittener Film desselbenRendererbuilds: `artifacts/runtime/release-v2-mobile-capture/zoom-tour.mp4`,1920×1080,1031Framebufferframes,0QueueDrops, tatsächliche Zeitstempel. Runtime48.006078s, MP447.96s ab erstemCapture; Startupframegap514.182ms roh enthalten, danachmax58.295ms. Keine bewusst parallel eingeplanteAnalyse während Aufnahme. Vier losslessPNGs tatsächlich geöffnet; vollständige Region→Mitte→Nahwald→Rückfahrt.

Session: alle eigenenGPU-/Encode-/Packagejobs beendet; Driver für unabhängige Schlussprüfung verfügbar. Keine Windows/Linux/iPad-Leistungszusage.
