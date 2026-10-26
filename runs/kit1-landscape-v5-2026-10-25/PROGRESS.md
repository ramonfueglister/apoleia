# Fortschritt (append-only)

Noch keine Produktarbeit oder Laufzeitprüfung. Neue Einträge nicht rückwirkend als frühere Ereignisse ausgeben.

## 2026-10-25T14:10:52Z — Operations-Run initialisiert

- Auftrag/Revision/Agent: Nutzer-Startauftrag Kit 1; `kit1-landscape-v5` / `kit1-ops-v5` / `kit1-rendering-v4`; Operations owner `/root/kit_intake`.
- Kit-/Build-/Daten-/Mappingrevision: base Git revision `01c48ad`; product build/data/mapping noch ungebunden.
- Tatsächliche Änderung und Pfade: `tools/kit.py init-run runs/kit1-landscape-v5-2026-10-25` angelegt; Operationsdokumente folgen innerhalb dieses Run-Ordners. Keine App-/Datenänderung.
- Ausgeführter Befehl / Ergebnis / Beleg: `python3 docs/kit1/tools/kit.py init-run runs/kit1-landscape-v5-2026-10-25` → exit 0, `runtime_executed:false`. `python3 docs/kit1/tools/kit.py preflight docs/kit1/templates/config.json` → exit 2, `status:blocked`, alle Produktbindungen erwartungsgemäß offen; keine Nutzerfreigabe fehlt.
- Offener Fehler / Jobkennung / nächster Schritt: kein Runtimefehler. Hostinventar steht in `ENVIRONMENT.md`; Daten-/Grafikowner-Bindungen und deren Auftragskarten erforderlich, bevor `config.json` angepasst wird.
- Kosten/Zeit: Kosten `nicht erhoben`; Zeit nicht erhoben.
- Prüfstatus: vorhandene passende v5 Baseline in `docs/kit1/evidence/kit-checks.json` bestätigt Kit `self-check`, 43 Tests und unabhängigen Kitvertragsscope auf Darwin arm64/Python 3.15.0. Kein unnötiger Retest; keine Produkt-/Geografieprüfung behauptet.

## 2026-10-25T14:17:26Z — Owner-Bindungen und Wiederaufnahmepunkt

- Auftrag/Revision/Agent: Operations-Dokumentation des gestarteten Kit 1; ops v5 / renderer v4; `/root/kit_intake`.
- Kit-/Build-/Daten-/Mappingrevision: base Git `01c48ad`; config records Godot `4.7.2.stable.custom_build.ed1daf0bf`; mapping `equirectangular-model-v1` / `mapping-v1`; Mobile capture profile 1920×1080; p95 16.7 ms and process RAM 2048 MiB as premeasurement targets. Data owner reports region-v1/mask-v1/eqc41-km-v1/policy-v1, but those are not yet in the run manifests.
- Tatsächliche Änderung und Pfade: run-level `README.md`, `PLAN.md` M0–M4, `ENVIRONMENT.md`, `OWNER_BINDINGS.md`, `START_AND_CONTROLS.md`, `ACCEPTANCE_DRAFT.md`, `MANIFEST_INDEX.md`, own `ASSIGNMENT.md`, `thresholds.md`, `HANDOFF.md`, partial `config.json`. External guide records source-read input mapping and owner-supplied capture command, both explicitly unverified.
- Ausgeführter Befehl / Ergebnis / Beleg: `python3 docs/kit1/tools/kit.py preflight runs/kit1-landscape-v5-2026-10-25/config.json` → exit 2, `blocked`, `runtime_executed:false`. Remaining issues: mapping residual pixel bound, data-processing tool, region refs, sources, fixture, camera transition, source-accuracy/model-render/protection references, and tile grid/probes. No app build or product runtime was run by operations.
- Offener Fehler / Jobkennung / nächster Schritt: Data owner reports ETOPO download job `15288` still running, coverage/payload incomplete and schema corrections underway; run-local hardlink export script planned but not yet delivered. Wait for owner handoff; verify source origins/hashes and export relation, then bind run-local config paths and run preflight against that concrete revision. Graphics owner reports no successful GPU start yet.
- Kosten/Zeit: actual token/USD and run costs `nicht erhoben`.

## 2026-10-25T14:24:56Z — Operations fortgesetzt, v2-Export noch offen

- Auftrag/Revision/Agent: Run-local Hash-/Manifest-/Config-Bindung für Data v2; `/root/kit_intake`, Referenz `kit1-landscape-v5` / `kit1-ops-v5`.
- Basis-/Datenrevisionen: Run base HEAD `01c48ad`; Data owner meldet `landscape-v2`, `region-v1`, `mask-v1`, `coverage-v2`, `sources-v1`, `policy-v2`, `mapping-v1`, `tile-grid-v1`; diese Ownerangaben sind noch nicht als Run-Manifest eingefroren.
- Gelesene Vorprüfung: `independent-review/PRELIMINARY.md`, Basis-HEAD `01c48ad`. Sie enthält echte Referenzgeometrie-Containmentprüfung, A02-Teilbefund und offene R01–R09; sie ist keine Produktabnahme. V1-Vertikalmesswerte sind wegen GDAL-Auto-Vertical-Transformation verworfen; nicht übernehmen. A04/A09/A15/A16-Runtime bleibt offen.
- Aktuelle Handoffs: Data owner bestätigt Runroot-Manifeste (`sources.json`, `region.json`, `coverage.json`, `geodata_policy.json`, `derivation.json`) mit run-relativen `data/...` Artefakten. `camera-profile.json` muss ebenfalls run-lokal eingebunden werden. Runtime-`tiles.json`/Fixtureprobes gehören Capture/Graphics, `data/tile-grid.json` liefert nur die normative Definition. Data v2-Eingabe ist noch nicht eingefroren; Owner erwartet AWMC-Normalisierungsbeleg, Derivation-Schema und Exporterrevision.
- Ausgeführte Prüfung/Ergebnis: Read-only parsed die vorhandenen v2 Manifestkopien und gemeldete Messdateien; `data/derived/landscape.json` nennt `landscape-v2`, Payloadhashes und 15s ETOPO/WC source claims; `data/geodata_policy.json` enthält drei Niveaus und fünf Schutzklassen, Runtime screen/transition Werte sind explizit null. `tools/data_export_run.py` kopiert/hardlinkt nur `data/`, deshalb wartet Operations auf vereinbarten vollständigen Export.
- Nächster Schritt: Nach Data-owner Freeze zuerst kompletter Run-export, root-level manifest linking, Herkunft-/Hash-Prüfung; dann config root paths (`sources.json`, `region.json`, `geodata_policy.json`), coverage/derivation evidence, tile-grid ID/Revision/Definition binden und einmal Preflight/gezielte Strukturvalidierungen ausführen. Keine Runtime-Capture, keine unabhängige Selbstabnahme.
- Kosten/Zeit: Token/USD und tatsächliche Ausführungskosten `nicht erhoben`.

## Vorlage für nächsten Eintrag
- UTC-Zeit / Auftrag / Agent:
- Kit-/Build-/Daten-/Mappingrevision:
- Tatsächliche Änderung und Pfade:
- Ausgeführter Befehl / Ergebnis / Beleg:
- Offener Fehler / Jobkennung / nächster Schritt:
- Kosten/Zeit: nicht erhoben, sofern nicht gemessen

## 2026-10-25T14:30Z — Data v2 Runexport gebunden; Übergabe an Capture/Review

- Auftrag / Agent: Run-lokale Datenbindung und Operationscheckpoint für Kit 1; `/root/kit_intake`. Scope weiter auf Runroot/Operations beschränkt.
- Revisionen: Basis HEAD `01c48ad`; Owner-Datenstände `landscape-v2`, `region-v1`, `mask-v1`, `coverage-v2`, `sources-v1`, `policy-v2`, `mapping-v1`, `tile-grid-v1`; Renderer `equirectangular-model-v1` / `orthographic-relief-v1`. Kamera-Profil bleibt Graphics-editierbar.
- Tatsächliche Änderung: `tools/data_export_run.py runs/kit1-landscape-v5-2026-10-25` ausgeführt; Runroot enthält Hardlinkexport unter `data/` und die fünf root manifests `sources.json`, `region.json`, `coverage.json`, `geodata_policy.json`, `derivation.json`. `config.json` erhielt Datenprozessierungs-Runtime Python 3.14.8/GDAL 3.13.3/NumPy 2.5.4 und Tile-Grid `eqc41-km-v1` / `tile-grid-v1` mit `data/tile-grid.json` SHA-256 `8c2acb50000fea5186f8b2a4a6d2f5c62de00c27dc09bca2465a1e2de3cbc67d`.
- Nachweise: Run- und Datenowner-Manifeste wurden als Struktur-only geprüft; alle fünf Validatorläufe meldeten exit 0, `scope: structure-only`. Runroot manifest files stimmen per Hardlink/gleichem Inhalt mit exportiertem `data/` überein. Ein einzelner kohärenter `kit.py preflight .../config.json` endete exit 2 (`blocked`, runtime false). Offen sind mapping residual, fixture/Region-/Mapping-Übereinstimmung, Kameraübergang, Waypointtiming/Positionsmethode sowie Tile-Probeabdeckung/-Navigation. Keine Runtime-Capture und keine Selbstabnahme.
- Externe Vorprüfung: `independent-review/PRELIMINARY.md` gelesen. Root meldet konkreten Data-v2-Budgetfehler: Overview-Küstenmaximum `6418.56 m` überschreitet gebundene `6000 m`; Data owner muss Revision liefern. Zwei Metadatenhinweise: `data/transformations.json` trägt historisches Label `landscape-v1`, während tatsächliche Output-/Inventar-/Derivationrevision `landscape-v2` ist; `data/derived/inventory.json.full_source_sha256` bezeichnet den vollständigen Quell-VRT-Hash, nicht einen einzelnen Quelldatensatz (Einzeltile-TIFF-Hashes stehen im Inventory/Sources). Außerdem `coverage.landcover_treatments.visible_result` bleibt ungelöst bis Bildprüfung. `data/jobs.json` meldet NOAA 60s Job `15288` noch laufend; dieser ist nicht als fertige Quelle zu behandeln.
- Nächster Schritt: warten auf vom Data owner korrigierte/freigegebene Revision; danach Änderungen kontrolliert erneut exportieren und hashes/config binden. Graphics/Capture liefert echte `tiles.json`, Fixture, Bild-/Übergangsevidenz und Runtime. Unabhängige Abnahme bleibt ausdrücklich offen; keine Capture gestartet.
- Kosten: Token/USD und tatsächliche Ausführungskosten nicht erhoben. Kein Push/Commit.

## Datenowner — gezielter v3Checkpoint

- Frühere v2Daten inklusive fehlgeschlagener Küstenmessung sind unter `data-revisions/landscape-v2/` erhalten; keine neue Quelldatenbeschaffung.
- Produkt `landscape-v3` / Policy-v3 / Anchor-v3: Nur offlinevorbereitete Wasserübersicht auf4096×3072 verbessert; neue Küstenmaxima auf denselben2340Punkten overview2040.133m/canonical2797.253m/detail2039.410m bei unverändertem6000mBudget. TatsächlicheGPUküste verwendet weiterhin bei jedemZoom identische8192×6144Detailmaske.
- Unverändert: nativeHöhen, Cover, canonical-/Detailwasser, physischeFlüsse/Seen/Land. Korrigiert:Alpenanker584.416870m, Journalrevision/VRT-Hashlabel,60sDownloadterminal/ungenutzt vomv3Export ausgeschlossen.
- Horizontalmetrikspezifikation vor Neumessung: tatsächlicherVersatz durch höhenbasierteGeneralisierung an identischenSourcequerykoordinaten0m, unabhängiger bitweiserIdentitätsvergleich; numerischerProjektionsroundtrip9.494415e-10m wird separat und ungeändert berichtet. Keine Rundung/Budgetlockerung. RuntimeMesh-/Morph-/Float32-Projektionsfehler weiterhin eigeneMessung.
- LineStringtopologie prüft jetzt symmetrischeDifferenzLÄNGE, nicht Fläche;168Features unverändert,0fehlend/unerwartet. Kitmanifest-Strukturprüfungen erneut bestanden; kein automatischesA16Gesamtbestehen.
- Runexport explizit `tools/data_export_run.py runs/kit1-landscape-v5-2026-10-25 --update-v3`, root-levelManifeste/dataSubtree/Profile weiterhin runlokal gebunden. Graphics besitzt laufendeGPUtests; Datenowner startet keineRuntime.

## 2026-10-25T14:35Z — v3 Manifestbindung und finaler Operations-Preflight

- Auftrag / Agent: Run-local Data-v3 binding and operations handoff; `/root/kit_intake`. No app/data changes.
- Revisionen: run base HEAD `01c48ad`; Data owner froze `landscape-v3` / `coverage-v3` / `policy-v3`, with `sources-v1`, `region-v1`, `mapping-v1`, and existing `tile-grid-v1`. Root-level config paths for sources, region, and policy already pointed at the run-local manifests; no unsupported config keys were added for coverage/derivation.
- Provenance/hash check: Operations read each root manifest and counterpart under `data/`; bytes matched. SHA-256: `sources.json` `9881be75f5cc3c4adf0c7b348cb4b7d0c34a42ee67a868606531796d1321793f`; `region.json` `adaa308c83b03f3e4288ab0c81a91e835e8a5a88e0191162362b5481d86acc8a`; `coverage.json` `a6bd882e9baabad8ca2700595c19ec5805d3d61273a21ab51c3a036ba174cfad`; `geodata_policy.json` `289fdb60188aa7fcf86ef6168c1f0b8bb6b53be0721ebdb4acd726fd63d12d28`; `derivation.json` `fb5f3ee3310b7164d46be69b043944663baf86013b6404968da98ff51a8dcc10`. Horizontal metric spec `data/horizontal-metric.json`: `horizontal-identity-v1`, SHA-256 `ed79059bcca8321296768c7f9d7713e1e4b326d0fe215fe214932015287edfbb`. Tile grid unchanged: SHA-256 `8c2acb50000fea5186f8b2a4a6d2f5c62de00c27dc09bca2465a1e2de3cbc67d`.
- Owner-reported v3 corrections: 4096×3072 overview water; repeated 2340-sample coastal maximum 2040.133 m (under unchanged 6000 m budget); canonical/detail water, rendered terrain, detail water, rivers/flows reported unchanged. Historical v2 kept under `data-revisions/landscape-v2/`. Complete/unused 60s download is excluded from v3. Horizontal source-query identity (`0 m`) is separately defined from projection round-trip (`9.494415e-10 m`); neither is a pixel residual measurement. Coverage still says `landcover_treatments[].visible_result: unresolved`; six screen/morph runtime metric combinations are outstanding. These are explicit owner report values, not independent validation.
- Executed check: one `python3 docs/kit1/tools/kit.py preflight runs/kit1-landscape-v5-2026-10-25/config.json` → exit 2, `status: blocked`, `scope: binding-readiness`, `runtime_executed:false`. Only remaining issues: `mapping_residual_px`; fixture/complete-region-review/region+mapping fixture binding; camera transition and definition binding/match; waypoint timing and expected-position method; tile probe coverage and navigation case. No runtime, image capture, build, or acceptance was performed.
- Operations docs updated: `OWNER_BINDINGS.md`, `MANIFEST_INDEX.md`, `START_AND_CONTROLS.md`, `HANDOFF.md`; earlier v2 statements are retained as history and superseded by the v3 section. Graphics’ runtime measurement/encode/analyze commands and package flag are documented as owner-supplied and unverified.
- Next: Graphics/Capture binds camera/build/mapping residual/fixture/tiles and runs the intended capture only after confirming frozen v3 and fixture; then independent reviewer performs acceptance. Operations does not re-run this preflight absent relevant binding changes. No commit/push. Costs: actual token/USD and runtime costs not measured.

## 2026-10-25T14:41Z — Renderer-Vorlauf ausdrücklich nicht final

- Auftrag / Agent: Operations checkpoint; `/root/kit_intake`.
- Statusquelle: Koordinator bestätigt `artifacts/runtime/v3-mobile-normal/` ist ausdrücklich kein finaler Datensatz. Ich habe nur die vorhandenen Dateien/Metadaten gelesen; nichts aus diesem Vorlauf ist in Config oder Kitreport gebunden.
- Nächster Schritt laut Grafik/Koordinator: RF32→RG8 mit vorab spezifiziertem 0,125-m-Encodingbudget und zusätzlicher GPU-Allokationsoptimierung; danach neue Messung. Vorlauf hatte laut Koordinator Ressourcenbudgetüberschreitungen. Keine Messwerte aus ihm als Abnahme verwenden.
- Offen: finale Build-/Mapping-/Camera-/Fixture-/Tile-/Telemetrie-Bindungen sowie finale PNG/Video. Keine erneute Preflightprüfung bis zum kohärenten Messhandoff. Kein Build/Capture durch Operations, keine Selbstabnahme, kein Commit/Push.

## 2026-10-25T14:42Z — Packed-height Capture läuft

- Grafikowner bestätigt kanonischen Erfassungsbefehl `python3 app/scripts/measure_runtime.py --out <absolute-run> --renderer mobile --duration 48 --capture`. Messausgabe soll alle Frame-Rohdaten plus Capture enthalten; Owner meldet denselben eingefrorenen Lauf für Telemetrie.
- Geänderte Rendertransportrevision `signed-rg8-quarter-metre-v1`: Owner stellt `artifacts/render-data/height-packing.json` und `height-rg8.bin` bereit; ursprüngliche Datenrevision `landscape-v3` bleibt unverändert. Ein GPU-Snapshot von 797294592 Bytes ist nur Zwischenstand, kein finales Capture-/A12-Ergebnis.
- Grafikowner führt nun finalen Normalpfad+Capture durch. Finale Hashliste/Fixture-/Runtimeevidenz fehlt noch; Operations hat noch nichts davon in Config/Report gebunden. Keine weitere Prüfung bis zum kohärenten Handoff. Anleitung in `START_AND_CONTROLS.md` auf den bestätigten Capture-Befehl aktualisiert.

## 2026-10-25T14:43Z — Kamera korrigiert; A08-Iteration offen

- Graphics bestätigt `artifacts/runtime/final-mobile-normal/` ist noch vor der Kamera-Korrektur und daher nicht final. Ziel-/Ist-Abweichung im near camera state wurde durch atomare Basis statt `look_at` korrigiert; tatsächliche Basis/Projektionsmatrix wird exportiert. Gezielter Exaktzustandstest: GPU exit 0, max Residuum `0.00008096 px` in `artifacts/runtime/camera-pitch-fix/` (Owner-Angabe). Kamera-ID und Profilhash bleiben gleich; Build-/Renderer-Codehash ändert sich.
- Graphics arbeitet noch an der vom Reviewer geforderten A08 Wald-/Boden-Wiederholung. Der finale 48-s-Capture wurde noch nicht gestartet; aktuell laut Graphics kein Job aktiv. Kein früherer Output in config/report gebunden.
- Nächster Schritt: vollständigen A08-Fix und kohärente finale Messfahrt samt Capture/Hashes/Fixture/Tileprobes abwarten; dann sofort config/report an finale Buildrevision binden. Bis dahin keine Preflight- oder Report-Checks.

## 2026-10-25T14:48Z — Finales Capture aktiv

- Koordinator meldet A08 `forest-detail-fix` Bilditeration geprüft. Finale Capture-Session `59614` läuft in `artifacts/runtime/final-mobile-capture/`; Code und Daten sind für diese Session eingefroren.
- Graphics liest Capture-Bilder/Video und wiederholt die betroffene Normalmessung. Noch kein vollständiger finaler Hash-/Fixture-/Runtime-Handoff an Operations erhalten; nichts gebunden und keine Prüfung gestartet.

## 2026-10-25T14:56Z — Prospektive A05-Bindung

- Nach Koordinator-/Reviewerabstimmung Operations hat eine eigenständige A05-Grenze gebunden: `max_visible_anchor_screen_residual_px ≤ 1.0` im top-left Viewport. Der Grenzwert basiert auf dem Anzeigenpixel-Kriterium (max. 1 px) und wird ausdrücklich nicht als bereits vor früheren Capture-Versuchen spezifiziert dargestellt. Er bleibt getrennt von A16 `screen_error_px=2` / `transition_residual_px=1`.
- Metrik: Maximum der euklidischen 2D-Abstände für alle gehashten v3-Quellanker über alle sichtbaren Samples/Zeiten des vollständigen 48-s-Fixturepfads; pro Probe Sichtbarkeit, Quelle, erwartete/observed Pixelkoordinaten, viewport/DPR, tatsächliche Camera3D-Basis/Projektion und aktive Terraintriangle CPU-Probe speichern. Keine RMS, Rundung oder nachträgliche Toleranzanpassung; Offscreen-Proben bleiben roh erhalten. Expected projection ist unabhängige skalare Orthoprojektion.
- Hashbindung: `thresholds.md` SHA-256 `7cd7613eaa9f29c125c0792d1631f3296ab62f609b615ed80b4d2d03f7287ee8`; `config.json` SHA-256 `ad37ef252b3a804b8af6339bc5b131b8a9a8ca9337dad958e7fdaae30d9f14e2`; run `data/anchors.json` SHA-256 `2e026e903e89b1df7cf5209167874e4e2739077c78fe0f3555541dcdefeaea6d`. Current method source hashes: `expected_projection.py` `3fcbb9ce80704885971b8fec13c7622aac199eb50e8cad60159269ae74c04b2d`; `analyze_runtime.py` `965dc2eadf6a5697367bd7a18fcb892cd31923d37108f38267c8032f0a54e8d5`; Kit needs run-local method copies in final frozen fixture.
- Existing/active captures sind vor Thresholdbindung gestartet und können A05 nicht bestehen. Fixture bleibt derzeit `unbound`; Graphics soll `fixture.json` und `expected_position_method` artifact mit Pfad/Zeitpunkten/Viewport/Anker-/Sichtbarkeitsprobes vor einem frischen A05-Normal-/Forward+-Lauf frieren. Noch kein Preflight.

## 2026-10-25T15:00Z — A05 Fixture und Methodensnapshot gebunden

- Graphics owner hat die konkrete 48-s-Routenkoordinaten/-zeiten und State-Ansprüche geliefert. Operations erstellte die runlokale `fixture.json` mit 9 hashgebundenen Datenankern plus Grafik-owner Overviewkamera-Wegpunkt, 8 fixen Wegpunkten (0, 6000, 14000, 24000, 27000, 34000, 40000, 48000 ms), 6 Kamera/Viewstates bei 1920×1080/DPR1/top-left, 4 Tilecase-Kategorien und Pan/Zoom/Return-Navigation.
- `fixture.json` SHA-256 `c9dab8a7255d4745c7b617084ed0dbe5dad31d5a0604a3d26a0e6365d37912ff`. Overview camera point 17.5°E/39.5°N binds `etopo15-7` (N45E015), checked by `gdalinfo` corner coordinates; not N30E015. `docs/product-renderer/expected-position-method.json` SHA-256 `51eb54980e7c99556e232cbbd1a139a9a42130853cd0120dd53e27149530f191`; runlokale helper copies hashidentisch zu finalen aktuellen Quellskripten `expected_projection.py` `3fcbb9ce80704885971b8fec13c7622aac199eb50e8cad60159269ae74c04b2d`, `analyze_runtime.py` `965dc2eadf6a5697367bd7a18fcb892cd31923d37108f38267c8032f0a54e8d5`.
- Methodik/threshold hashes: `thresholds.md` `7cd7613eaa9f29c125c0792d1631f3296ab62f609b615ed80b4d2d03f7287ee8`; config with A05 ≤1.0 px `ad37ef252b3a804b8af6339bc5b131b8a9a8ca9337dad958e7fdaae30d9f14e2`; source anchors `2e026e903e89b1df7cf5209167874e4e2739077c78fe0f3555541dcdefeaea6d`.
- Graphics owner has been asked to verify route/state correspondence and frozen hashes before any new A05 run. This binding postdates earlier captures; they remain A05-ineligible. No preflight/test was run. Await owner confirmation or correction before new Normal/Forward+ measurement.


## 2026-10-25T15:25Z — Nominal controls / effektive Fixturestates vor Fullrun gebunden

- Auftrag / Owner: Runlokale Operationsfixture, method binding, config, Status und Resume weiterführen; `/root/kit_intake`. Keine App-/Datenänderung, keine Selbstabnahme.
- Kit-/Produktrevision: Kit `kit1-landscape-v5` / ops `kit1-ops-v5`; Daten `landscape-v3`, Mapping `mapping-v1`, Rendererprofil `orthographic-relief-v1`. A05-Limit max. 1,0 px ist prospektiv gebunden und von A16 2px/1px getrennt.
- Tatsächliche Runänderung: `fixture.json` auf Revision `landscape-route-v2-effective-float-state` gebunden; nominale Routewerte separat in `docs/product-renderer/fixture-controls.json`; `docs/product-renderer/expected-position-method.json` erklärt nominal/effective semantics, volle Float-Serialisierung, A05 max-Residual-Methode und Nicht-A05-Kalibrierungsbeleg. Der 2-s-Controllerregressionsbeleg wurde runlokal unter `docs/product-renderer/calibration/fixture-controller-regression.json` kopiert. `config.json` capture command auf den von Graphics kanonisch bestätigten Messskriptpfad gesetzt. Der Report enthält weiterhin keine Runtime-Messwerte.
- Hashes: Fixture `39e82d6ace00a399740cab5487634b857f47ddb1db3b37c5662211a9f48b327f`; Controls `527992f720becdef0ad016c1d37860138f78c8f62ad48fb890c5bc0315adf085`; Methode `4d1143bb872d4fe7d4c934066500962e12c970a109f8ebf2cb14c68247d24385`; Config `3fd2a2e630bde7cc80c09db3160b36423ff9d1a994802f968307e9428be95ceb`; calibration `c58ce8c6cc84f7b52b25bac1f05284106caf17926fa8ea47f4a1db155f434d6c`; thresholds `7cd7613eaa9f29c125c0792d1631f3296ab62f609b615ed80b4d2d03f7287ee8`; sources `9881be75f5cc3c4adf0c7b348cb4b7d0c34a42ee67a868606531796d1321793f`; anchors `2e026e903e89b1df7cf5209167874e4e2739077c78fe0f3555541dcdefeaea6d`; projection `498ce60c41eb8272afe982b7a632d554e400841fce7f953df6fe3ac97c51b2d9`; camera profile `dc3520f2088757b577556d766d914d30f69385014292414d7fdc900552a3d4d7`.
- Operationsprüfung: manueller JSON-Vergleich bestätigte alle acht gebundenen Fixture-`view_state`-Objekte gleich den acht vollständigen Controller-Wegpunktzuständen. Ein weiterer Vergleich bestätigte 387 Probezeilen über zehn Fixture-Anker mit exakt gleichen Quell-Lon/Lat-Werten. Diese Checks binden den deterministischen Controller, liefern aber keinen A05-Score. Kein Preflight oder vollständige Laufzeitabnahme ausgeführt.
- Nächster Schritt / Owner: Graphics führt einen kurzen finalen Harness-/Fixtureabgleich aus, danach frische 48-s Mobile- und Forward+-Messungen sowie finale Captureauswertung auf eingefrorenem Build. Operations aktualisiert Reportbelege und führt genau einen kohärenten Kit-Check aus, wenn alle Hashes/Bindungen vorliegen. Unabhängige Prüfung bewertet A01–A16.
- Kosten: Token/USD, lokale Compute- und Zeitkosten nicht gemessen; bleiben `nicht erhoben`.


## 2026-10-25T15:27Z — Fixture v2 vor Messung exakt bestätigt; finale Läufe aktiv

- Graphics bestätigte vor Runstart die eingefrorenen Bindungen: fixture `39e82d6ace00a399740cab5487634b857f47ddb1db3b37c5662211a9f48b327f`; nominal controls `527992f720becdef0ad016c1d37860138f78c8f62ad48fb890c5bc0315adf085`; method descriptor `4d1143bb872d4fe7d4c934066500962e12c970a109f8ebf2cb14c68247d24385`; thresholds `7cd7613eaa9f29c125c0792d1631f3296ab62f609b615ed80b4d2d03f7287ee8`; config `3fd2a2e630bde7cc80c09db3160b36423ff9d1a994802f968307e9428be95ceb`.
- Owner-geführter Final-Exact-Match-Controllercheck: `artifacts/runtime/fixture-effective-controller-check/runtime.json`, SHA-256 `b2278c6ad8fd2694e4849e31efa0f319b7c81f68d0c6dba957ab10b9a5662b81`; identische Run-Kopie unter `docs/product-renderer/calibration/fixture-effective-controller-check.json`. Graphics meldet 8/8 `view_state` Dictionaries exakt gleich, genau eine Observation pro ID und unveränderte Anchor-Quellpräzision. Dieser Controllercheck hat keinen A05-Pixel-Score und ist keine Abnahme.
- Graphics hat unmittelbar danach finale 48-s Mobile-, Forward+- und Capture-Läufe mit `--fixture` gestartet; Controls und Daten/Renderpayload sind laut Owner eingefroren. Noch kein Laufzeit-/Video-/Messungs-Hashsatz an Operations übergeben. Keine weitere Config-/Fixtureänderung oder Kitprüfung während der Runs.
- Nächster Schritt: auf kohärenten finalen Handoff warten; dann Outputs gegen den oben gebundenen Hashsatz prüfen, config/report mit finalen Messwerten/Evidence ergänzen und genau eine passende Kitprüfung ausführen. Review A01–A16 bleibt unabhängig. Token/USD, Laufzeit- und Speicher-/Compute-Kosten sind nicht erhoben.


## 2026-10-25T15:28Z — Frischer Mobile-Normalpfad abgeschlossen, Restläufe aktiv

- Graphics meldet `artifacts/runtime/accepted-mobile-normal/` exit 0, 48.004 s, 5,458 Frames, Fixture v2 + eingefrorene Controls/Thresholds, exakte Viewstategleichheit an 8/8 Wegpunkten. Build/Data/Mapping-IDs sind im `runtime.json` Header gebunden.
- Rohwerte aus gelesenen Laufdateien: Frame-p50/p95/p99 8.326/9.044/26.854 ms; peak process RSS 1,827,684,352 B; GPU allocation 908,427,264 B. `anchor-analysis.json`: 8,253 Samples, 2,024 sichtbare Samples, max. sichtbares Source→Render-Residuum 0.6560332068414252 px, max. Source-Read-Höhendifferenz 0.05066228657960892 m, 0 Tile-ID-Abweichungen. `lod-motion-analysis.json`: 71,433 Seamprobe-Paare, 10,626 sichtbar, sichtbarer Seam-Gap max 0 px, 5,458 Motionframes, 5,311 sichtbare Transitionproben, Transitionmaximum 0.06465598951246901 px; diese Methoden beschreiben Stichproben und sind kein globaler Topologiebeweis.
- Toolgelesene Belegsha: runtime `062bc041a5960ec6c3abedc246c87d2911acdc0be28740c7bf72bf25bff85dbf`, anchor analysis `e4247f30b72389064c0949fecc0b5232dceeb6a1474cb8b746bfdb52d96dd812`, LOD/motion `2f4374dd0b1ec4a2fe34be2f9104e0c15dede268d7b1496362c000f350a8061b`, RSS `ea11b0f8a7519754960ec5ced6812d9e54d48462e8761e19479a1955bdab25ec`. Rohartefakte bleiben im lokalen `artifacts/`-Verzeichnis; keine Produktläufe oder großen Payloads nach Git kopieren.
- Grenzvergleich: die numerischen Owner-/Dateiwerte unterschreiten die gebundenen A05/A12-A16-Pixel-/Speicher-/GPU-Arbeitsziele, ersetzen nicht Bildsichtung, alle Kit-Pflichtbindungen oder unabhängige Prüfung. Es wird keine Anforderung als angenommen/validiert markiert.
- Nächster Owner-Schritt: Forward+ ist aktiv; danach finaler Capture-/Video-/App-Package-Handoff. Operations wartet auf einen kohärenten vollständigen Hashsatz und bindet erst dann report.json/Kitcheck. Kosten nicht gemessen.


## 2026-10-25T15:29Z — Unabhängige Rohdatenanalyse ergänzt

- Reviewer hat beide vollständigen Normalpfade unabhängig aus den Rohdateien ausgewertet; autoritative JSONs: `independent-review/accepted-mobile-normal-review.json` und `independent-review/accepted-forward-plus-normal-review.json`. Beide bestätigen dieselbe Dataset-/Renderer-/Profil-/Packingrevision und gebundene Fixture, 8.253/7.992 Tile-/Ankerbeobachtungen ohne Tile-ID-Mismatch sowie max. Source→Render-Residual 0.6559894858261045 px.
- Performancewerte strikt trennen: Mobile p95/p99 9.044/26.854 ms, RSS 1,827,684,352 B, GPU 908,427,264 B; initial 150 ms engine-delta-Wert ist kein normaler Wallclock-Frameabstand, späterer gemessener Wall-Hitch 129.652 ms korreliert mit Surface/Specialization-Pipelinekompilierungen. Forward+ p95/p99 9.253/27.132 ms, RSS 1,688,403,968 B, GPU 980,041,728 B; Maximum 1,294.81 ms mit 376.38 ms Pipelinehitch. Beide laufen mit niedrigen p95/p99, aber A12 ist nicht als spitzenfrei zu berichten; Forward+ zeigt einen deutlichen Pipelinehitch.
- A05 max sichtbares Residuum des unabhängigen Reviewers `0.6559894858261045 px` unterschreitet prospective `1.0 px`; Operations-separater analyzer meldet `0.6560332068414252 px`, Unterschiede stammen aus verschiedenen Source-/Screen-Projektionstatistiken und werden nicht geglättet/vermischt. Rohreport bleibt Entscheidungsgrundlage.
- Reviewer prüft separat LOD/Ridge-Stichproben: aus Root übermittelter Stand 26 Snapshots/57,812 sichtbare Edge-/Midpointproben ohne sichtbare Seam-Lücken; sechs Ridgeanker mit 5,502 Proben / 1,214 sichtbare und sichtbares Maximum 0.283884 px. Rohpfad für Ridge-Analyse liegt unter `independent-review/accepted-mobile-lod-ridge.*`; keine globale Topologiegarantie daraus ableiten.
- Capture läuft separat und hat bekanntes 7-s-CPU-Reviewintervall (UTC 15:35:27–15:35:34) als Interferenz. Performance-Messung und Capture werden im Report getrennt gehalten; Video nicht als unbeeinflusste A12-Messfahrt ausweisen. Noch keine finale A01–A16 Abnahme.


## 2026-10-25T15:50Z — A12-Grenzen der Messung dokumentiert

- Reviewer stuft A12 nur teilweise als validiert ein. API-/Per-pass-GPU-Timing ist mit der vorhandenen Godot-/Metal-Umgebung nicht verfügbar; kein Profiler oder SDK wurde installiert. Engine meldet GPU-Allokation, nicht vollständige physische Residency. Die 0.3-ms-Viewportzahl ist keine vollständige Frame-/GPU-Zeit. CPU-Runtime-Framezeiten, Funktionalität, GPU-Memory-Schätzung und nicht verfügbare GPU-Zeit getrennt ausweisen.
- Mobile- und Forward+-Normalpfade haben unabhängige per-frame Wall-Messungen; hohe Pipelinehitches (Mobile 129.652 ms spät, Forward+ 1294.81 ms und 376.38 ms) bleiben berichtspflichtig. Capture-Videotiming ist ein separater Beleg und kann durch das dokumentierte Reviewer-CPU-Fenster gestört sein. Nicht als „spike-free“ oder vollständige GPU-Performancevalidierung deklarieren.
- Diese Grenzen sind keine fehlenden Produktfunktionen. A12 darf im Report entsprechend begrenzt stehen; vollständige GPU-Per-Pass-Performance bleibt offen.


## 2026-10-25T16:20Z — Run-Bericht und Kit-Nachweise gebunden

- `report.json` bindet 23 hashgeprüfte Artefakte, echte revisionsgebundene Mobile-Telemetrie und gemessene Tiles. A01–A16 bleiben absichtlich `offen`; unabhängiger Reviewer und Review-Referenz sind nicht gesetzt. `EVIDENCE_INDEX.json` wurde mit Report, Telemetrie, Tiles, Conversion-Binding, Video und Bildbelegen aktualisiert.
- Runlokaler Converter-Coalescingfehler korrigiert: native Rohdatei hat 913 Records, wobei Index 912 ein späterer generischer Record mit derselben Zeit wie der vorherige Rückkehr-Waypoint (48000.237 ms) ist. Der Adapter behält den Waypoint und lässt nur diesen späteren generischen Record weg; 912 Kit-Samples, Original-Runtime unverändert. Index/Grund/Recordzahlen und Eingabe-SHA sind im `conversion-binding.json` notiert. Der vollständige All-frame-Lauf und seine Performancezahlen bleiben unberührt.
- Genau ein kohärenter aktueller `preflight config.json` lief exit 0, `runtime_executed:false`. Genau ein `report-check` lief exit 2, `blocked`/`visual_truth_checked:false`. Offen: fehlende Reviewerbindung; Coverage-/Derivation-Regionpfade weichen von der Config ab; Derivation-Buildrevision, Policy-/Sampling-Bindungen und offene sichtbare Coverage-/Landcover-Felder. Keine Daten-/App-/Runtimeänderungen vorgenommen.
- Empirische Berichtsmetriken aus runlokaler Kit-Telemetrie: 912 Samples, p95 8.959 ms; peak RSS 1809.171875 MiB; sichtbare Mappingabweichung max 0.6560332068414252 px. Diese Kit-Sample-p95-Zahl ist von der unabhängigen All-frame-Normalpfad-p95 zu unterscheiden.
- Nächster Schritt: Reviewer prüft unabhängige Rohpfade/Video/Bundle, klärt A01/Pan/A09 sowie aktuelle A01–A16, und entscheidet, ob die echten Coverage-/Derivation-Referenzkonflikte durch Eigentümerrevision behoben werden müssen. Operations hat keine Abnahme erklärt.


## 2026-10-25T16:24Z — Report-Adapter blockiert nur echte offene Reviewpunkte

- Alias-/Revisionanpassung wird nur in `report-coverage.json`, `report-derivation.json` und `report-manifest-binding.json` abgebildet. Pfade `region.json` ↔ `data/region.json` und `geodata_policy.json` ↔ `data/geodata_policy.json` wurden nur bei identischem SHA normalisiert. Gemeinsame Produktrevision `product-build-sha256:db07883625eda9d35db98a71436194866c80a306ce237a3839e3d7dc3eeee59a` bindet Datenrevision `landscape-v3`, Datenmanifest SHA `edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a` und Renderer Source SHA `59a926c8e09fdc0a391a829cf727003834c421ee1b79ff884d07735e0a31fe70`. Original Coverage-/Derivationdateien sind nicht verändert.
- Neuer `report-check` reduziert die vorherigen reinen Alias-/Build-/Policypfadfehler. Ergebnis bleibt `blocked` (Exit 2; `visual_truth_checked:false`): fehlender Reviewer/Review-Ref; `region_boundary`, `coastal_interfaces`, `tile_seams` ungelöst; fünf Landcover-`visible_result`s ungelöst; Derivation hat die zwei vorabgebundenen screen/transition-Metriken nicht in den offline Levels, 12 Sampling-`scope`-Strings passen nicht zur Policy, zwei Topologieklassen (`ridges`, `tile_seams`) fehlen. Kein künstliches Messdatum, keine Budgetänderung.
- Ownern/Reviewer wurden die aktuellen Hash-/Fehlerdetails übergeben. Nächster Schritt ist unabhängiger Prüfentscheid und ggf. Datenowner-Errata, nicht eine erneute Runtimefahrt.


## 2026-10-25T16:27Z — Buildrevision als Assembly-Fingerprint präzisiert

- Nach Graphics-Klärung ist `landscape-v3` ausdrücklich Dataset-Generation, nicht Rendererbuild. Das report build ID ist `product-build-sha256:a676717e43146bb2d62f222065cb7c4d6624022ac4812d453367fcbb2990d30b`, SHA-256 über kanonisches JSON mit Dataset-/Sources-Manifestrevisionen+Hashes, Mapping, Kamera/Profil, Renderer Source+Asset-Hashes, Packing-/Water-Manifesten, Anchors, Fixture/Controls/Thresholds. Keine Umetikettierung des Raw data build. Komponenten siehe `conversion-binding.json`; Quelle Runtime-Header unverändert.
- Aktuelle report-check-Hashes werden in `EVIDENCE_INDEX.json` erneuert. Reportblocker bleiben nur unabhängige Reviewerbindung plus Coverage-/Landcover-Sichtbefunde, unvollständige offline Screen-/Transitionmetriken, 12 Sampling-Scope-Mismatches und zwei fehlende Topologieklassen.


## 2026-10-25T16:42Z — Datareport-Errata v1 eingebunden

- Dataowner-Handoff `data-report-errata/HANDOFF.md` übernommen. Runlokale Coverage-/Derivation-Views und policy application wurden als zusätzliche hashgebundene Reportevidence eingebunden; eingefrorene `coverage.json`, `derivation.json`, Region-/Policy-/Quellenmanifeste und Runtime-Rohdateien bleiben unverändert. Hashes und Outputbindung sind in `data-report-errata/errata-binding.json` und `EVIDENCE_INDEX.json`.
- Es gibt 14 anwendbare Level/Metrikkombinationen innerhalb der unveränderten Originalbudgets und vier begründete NA-Paare für nicht gerenderte `overview`/`canonical` screen-/transition-Kombinationen. `kit1-ops-v5` kann NA nicht ausdrücken; report-check bleibt deshalb ehrlich `blocked` mit genau dieser Derivation-coverage-Lücke sowie fehlendem unabhängigen Reviewer/Review-Ref. Kein falsches Grün.
- Ergänzende, begrenzte native-detail Metriken für die **vor Pan-/Material-/Waldfix** gemessene warmed Mobilerevision: Screen max 0.6560332070186663 px; Transition max 0.07138421867018982 px; fünf positive Ridgeanker (Marineanker ausgeschlossen), 1123 beobachtete Seam-Nachbarpaare / 56,995 sichtbare Konturqueries / 26 LOD-Inventare. Das ist kein globaler Topologiebeweis und keine aktuelle Fixrevision-Abnahme.
- Neuer Report-SHA: `9845b0360f82ae8162ed25125db5a30a9bc36079fa4102d7bd507173d65e04eb`; 35 Evidenzreferenzen. `report-check`: exit 2, `blocked`, `visual_truth_checked:false`; verbleibend Reviewer-/Review-Ref und vier NA-Level/Metrik-Fälle, alle A01–A16 offen. Keine erneute Runtime- oder Preflightausführung.


## 2026-10-25T17:02Z — Finale unabhängige Matrix und release-v2 Errata gebunden

- `report.json` bindet den finalen unabhängigen Reviewer `independent_review` unter `independent-review/FINAL_REVIEW.md` plus `final-review-binding.json`, und verwendet ausschließlich die finale `data-report-errata/release-v2/` Coverage-/Derivation-Views. Hashes wurden lokal aus den gelesenen Dateien berechnet.
- Finale Ergebnisgrenzen: A01–A07, A09–A11, A13–A15 validiert im unabhängigen Bericht beschriebenen Umfang; A08 Nutzerstilbewertung offen; A12 teilweise validiert/offen (GPU-Zeit-API 0 gültige Samples/null, keine Per-Pass-Zeit); A16 14 anwendbare Werte innerhalb Originalbudgets und 4 explizite NA; Kitchecker kann NA nicht darstellen.
- Release-v2 Errata bezieht sich auf Runtime SHA `b89c11e0621012e6202dd5abc68af597cfce99affd3f1a27a6b7600717afeaa8`, Renderer SHA `32692e62a00683419f562793b506e7199f871e782cc2ecf7dc07afc7f34d97a5`, Dataset manifest SHA `edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a`. Offline reproduction: `sh runs/kit1-landscape-v5-2026-10-25/data-report-errata/release-v2/reproduce.sh`.
- Normale Benchmarks getrennt vom Capture berichtet. Mobile max 141.976667 ms; Forward+ Pipeline-Maximum 1224.069 ms. Capture 1031 Frames / 0 Drops / 47.96 s, erster Startup-gap 514.182 ms. Keine Messgrenze als Nullpass ausgegeben.
- Operations führt jetzt genau einen finalen `report-check` aus; erwartete offene A08/A12/A16-Punkte bleiben sichtbar. Danach Git-Audit und inhaltlich getrennte Commits; kein Push ohne freigegebenen Zielbranchcheck. Kosten Token/USD nicht erhoben.
- Einziger finaler `report-check`: exit 2 / `blocked`, `scope=evidence-contract-only`, `visual_truth_checked=false`; Issues ausschließlich `derivation level/metric coverage incomplete` (Kitchecker kann die 4 NA nicht modellieren), A08 offen (Nutzerstil), A12 offen (GPU-/Per-Pass-Zeit), A16 offen (formale NA-Lücke). Keine weitere Runtimeprüfung impliziert.


## 2026-10-25T17:12Z — Git-Lieferung abgeschlossen

- Commitgruppen: `2742741` Datenreport-Errata, `bec000e` Renderer/App/Packaging, `9e860ab` finaler Operations-/Reviewreport, `a27569d` lokale Reviewartefakt-Ignoregrenzen; drei frühere Datencommits `3cecd01`, `d9d955c`, `6ecfcce` blieben unverändert.
- Ziel `origin` wurde read-only als `https://github.com/ramonfueglister/romaaeterna.git` geprüft; Branch zuvor nicht vorhanden. Normaler nicht-forced push auf `codex/kit1-landscape` erfolgreich, Upstream eingerichtet. Keine PR oder Releaseveröffentlichung.
- Lokal-only: `.app`, kompletter MP4-Film, große Raw-/Derived-Raster, rohe runtime dumps und superseded reviewer working artifacts bleiben ausgeschlossen; Hash/Produktion stehen in Runmanifesten. Vier finale PNG-Ansichten und zwei Kontaktseiten sind repräsentativ versioniert.
