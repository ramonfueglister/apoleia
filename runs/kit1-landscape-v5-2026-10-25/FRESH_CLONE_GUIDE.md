# Fresh-Clone- und Startanleitung (Stand Kit 1)

**Ziel:** einen reviewed Repositorystand neu klonen, die v3-Daten lokal reproduzieren und die Landschaft auf macOS starten bzw. als lokale `.app` verpacken.
**Status:** Dokumentierter Build/Start wurde auf dem bestehenden Checkout und finalen macOS-Bundle ausgeführt. Ein leerer Fresh Clone wurde nicht getestet; keine plattformübergreifende Buildzusage. Finale unabhängige Prüfung und Grenzen stehen in [STATUS.md](STATUS.md).

## Repo und Git-Inhalt

Das Zielrepo ist privat: `https://github.com/ramonfueglister/romaaeterna.git`. Nach Push des reviewed Branches kann der bereitgestellte Branch geklont werden:

```sh
git clone --branch codex/kit1-landscape https://github.com/ramonfueglister/romaaeterna.git
cd romaaeterna
```

Der reviewed Branch `codex/kit1-landscape` ist nach `origin` gepusht. Die Root-/Data-Gitignore-Regeln schließen Quellraster, große abgeleitete Float-/Byte-Raster, gerenderte Pack-Payloads, Caches und temporäre Captureframes aus. Kleine Quellen-/Policymanifeste, Generatoren und Offline-Mess-CSV bleiben versionierbar. Daher enthält ein Git Clone **noch keine fertigen Landschafts-Payloads**. Deren erwartete Versionen und SHA-256-Werte stehen in `data/sources.json`, `data/derived/landscape.json` und `data/derived/inventory.json`; große Outputs bleiben lokal oder in einem separat gebundenen Paket.

## Abhängigkeiten und öffentlicher Quellenzugriff

Die dokumentierte Reproduzierbarkeit ist derzeit an die verifizierte macOS-Toolchain gebunden:

- Python 3.14.8 mit NumPy 2.5.4 und Python-GDAL-Bindings (`osgeo`), GDAL 3.13.3.
- PROJ-Datenbank aus der zur GDAL-Installation passenden Installation; auf dem geprüften Host `/opt/homebrew/share/proj`.
- `curl` für öffentliche Quellabfragen. ETOPO wird aus NOAA heruntergeladen; WorldCover-COG-Overviews werden direkt aus den öffentlichen ESA-S3-URLs gelesen; Natural-Earth-/geoBoundary-/AWMC-Quellmetadaten und Lizenztexte sind in den Manifesten dokumentiert.
- Godot `4.7.2.stable.custom_build.ed1daf0bf` für Build/Start aus dem Repo. Ein fertiges lokales `.app` bündelt den Engine-Binary und benötigt beim Start kein Python oder separat installiertes Godot.

Es gibt keine vollständige plattformunabhängige GDAL/Godot-Lockdatei; `app/requirements-render-data.txt` nennt NumPy, die GDAL-Bindings müssen zur gewählten GDAL-Installation passen. Die Repo- und Paketbefehle installieren keine globalen Pakete, SDKs oder Engine-Templates. Für andere Betriebssysteme/Chips ist dieser Daten- und Grafikpfad nicht validiert.

Alle Datenquellen sind öffentlich und benötigen nach aktuellem Vertrag keine Konten oder kostenpflichtigen Dienste. Für den Build werden lokal etwa 2 GB Quell-/Zwischendaten plus weitere abgeleitete Renderpayloads benötigt; Capture/Runs brauchen zusätzlichen Speicher. Nicht ausreichend Speicher führt zu einem fehlgeschlagenen Build, nicht zu Ersatzdaten.

## Daten und Renderpayloads reproduzieren

Vom Repositoryroot mit verfügbarer, versionspassender Toolchain ausführen. Diese Schritte können öffentliche Daten herunterladen und große lokale Dateien anlegen; sie wurden in diesem Turn nicht erneut ausgeführt.

```sh
export PROJ_DATA=/opt/homebrew/share/proj
/opt/homebrew/bin/python3.14 tools/data_bind.py
/opt/homebrew/bin/python3.14 tools/data_fetch_refs.py
/opt/homebrew/bin/python3.14 tools/data_dem15.py
/opt/homebrew/bin/python3.14 tools/data_worldcover.py
/opt/homebrew/bin/python3.14 tools/data_build.py
/opt/homebrew/bin/python3.14 tools/data_source_quality.py
/opt/homebrew/bin/python3.14 tools/data_anchors.py
/opt/homebrew/bin/python3.14 tools/data_tiles.py
/opt/homebrew/bin/python3.14 tools/data_measure.py
/opt/homebrew/bin/python3.14 tools/data_topology.py
/opt/homebrew/bin/python3.14 tools/data_manifest.py
/opt/homebrew/bin/python3.14 tools/data_coverage.py
/opt/homebrew/bin/python3.14 tools/data_derivation.py
```

Die aktuellen Generatoren bauen `landscape-v3` direkt. `tools/data_revise_v3.py` ist eine einmalige v2→v3-Migration für einen bereits vorhandenen v2-Datensatz; sie ist kein Schritt für einen leeren Fresh Clone und soll nicht auf einen bestehenden eingefrorenen Run angewandt werden. Der dokumentierte Pipelinepfad lädt 15 regionale ETOPO-15-arcsecond-TIFFs und liest native WorldCover-COG-Overviews; vollständige 10-m-COGs werden nicht als heruntergeladene/gespeicherte Quelle behauptet.

Danach das lokale Native-Rendering-Paket erzeugen. Build/Startskripte rufen diese Generatoren selbst erneut auf; hashidentische Dateien werden validiert und wiederverwendet.

```sh
./scripts/build-landscape
```

`build-landscape` führt `app/scripts/pack_height.py` und `pack_water_distance.py` aus und prüft dann Godot-Import und GDScript-Parse. Sie benötigen unter anderem `data/derived/height-detail.f32`, `land.geojson`, `lakes.geojson`, `water-detail.u8` und `landscape.json`. Der Upload wird in `artifacts/render-data/` erzeugt; dessen `.bin`/`.u8` Dateien sind abgeleitete, ignorierte Dateien und keine Rohdatenquelle. Die ausführlichen Quelldateien, Provenienz und Lizenzgrenzen stehen in `docs/product-data/README.md`.

## Lokal starten oder eine Mac-App bündeln

Für den direkten Projektstart mit der vorhandenen Godot-Runtime:

```sh
./scripts/run-landscape
```

Die externe Bedienanleitung und der gesonderte Capturebefehl stehen in [START_AND_CONTROLS.md](START_AND_CONTROLS.md). Direkte Steuerung erfolgt über Maus/Trackpad; im Landschaftsfenster gibt es keine GUI.

Um die lokalen Laufzeitdaten und den Engine-Binary in eine macOS-App zu bündeln:

```sh
./scripts/build-landscape --package
```

Graphics-Owner hat `artifacts/Roma Aeterna Final.app` auf Release-v2 gebaut; unabhängiger Reviewer startete das exakte Bundle und führte echte Pan-/Rückfahrt-/Wheel-Eingaben aus. Smoke exit 0, 30 Frames, 1920×1080. Das Bundle enthält die manifestierten Daten-/Renderpayloads, Godot-Lizenz/Notices und Quellenattribution. Das Paketmanifest listet 79 Dateien; unabhängige Prüfung ergab null Hashabweichungen. Das Manifest ist separat gehasht. Finalbelege und Metadaten sind unter `docs/product-renderer/package-evidence/release-v2/` und `EVIDENCE_INDEX.json` gebunden. Das Paket ist lokal, unsigniert und nicht notarisiert; es wird nicht veröffentlicht. Ein aktueller `.app`-Start benötigt weder Python noch separat installiertes Godot. Ein frischer Clone kann das Paket erst nach erfolgreicher Daten-/Renderpayload-Reproduktion erzeugen. Der `--package`-Befehl und Startsmoke belegen keine A01–A16-Abnahme; A08-Nutzerstilbewertung sowie A12- und A16-Grenzen bleiben offen; siehe finalen Report.

`python3 docs/kit1/tools/kit.py package ...` verpackt ausschließlich das **Kit-Dokumentations-/Referenzpaket**, nicht die Produkt-App und nicht die Geodaten. Dieses ZIP ersetzt die `.app` nicht.

## Grenzen und Wiederaufnahme

- Git allein reicht derzeit nicht zum Appstart: der Clone muss die echten Datenquellen lokal beschaffen und die v3-Payloads reproduzieren; andernfalls fehlende Payloads ehrlich melden.
- Keine Ersatzlandschaft oder erfundenen Messwerte verwenden.
- Quellenbeschaffung, Quelldatensätze, lokale Generated Inputs und Render-Uploads sind durch getrennte Manifest-/Hashbeziehungen gebunden. Große Payloads lokal behalten oder als gesondertes Hash-geprüftes Paket bereitstellen; nicht ungeprüft in Git aufnehmen.
- Dieses Dokument wurde aus vorhandenen Skripten und Ownerangaben erstellt. Es ist noch kein erfolgreicher Fresh-Clone-Lauf oder sauberer Build aus leerem Downloadcache.
