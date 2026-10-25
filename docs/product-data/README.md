# Reproduzierbare Kit1-Geodaten

Referenz `kit1-landscape-v5` / `kit1-ops-v5`, Produktrevision `landscape-v3`, Stand25.10.2026. Status: Pipeline implementiert; offline gemessene Teilprüfungen validiert; vollständige A16-/Sichtabnahme offen. [Übergabe](HANDOFF.md) trennt Grenzen und Ergebnisse.

Die geografischen Referenzen sind vor dem Terrainprozess in `data/region.json` gebunden. Echte Quellpolygone bestimmen den Rahmen: AWMC117, NaturalEarthMittelmeer mit Unterbecken, geoBoundariesEngland und positiver Nordkontext. Die zusammenhängende Rechteckmaske erlaubt Land-/Meerkontext jenseits historischer Grenzen. Die modernen ADM2-Anker sind Auswahlhilfe mit eigenen Feature-IDs und schichtbezogenen Lizenzen. Das Produkt zeigt keine politischen Geometrien.

Quellen:

- [NOAA ETOPO2022](https://www.ncei.noaa.gov/products/etopo-global-relief-model), v1, native15arcsec, EGM2008-Höhen, CC0-1.0.15Quelltiffdateien vollständig heruntergeladen und SHA256-gebunden. Auflösung463m nord-süd,245–433m ost-west im Gebiet; Auflösung ist keine Messgenauigkeit.
- [ESA WorldCover](https://esa-worldcover.org/en/data-access),2021v200,CC-BY4.0; ESAWorldCoverproject2021/ContainsmodifiedCopernicusSentineldata2021processedbyESAWorldCoverconsortium.249nativeCOG-Overviewbeobachtungen eingefroren, letzteOverview562×562je3°. Quelle10m, hier gelieferte Coverauflösung~300–594m. Hashes beziehen sich ausdrücklich auf die verlustfreien heruntergeladenen Overviewbeobachtungen; Voll-COG-Hashes der entfernten10mOriginale sind nicht bekannt. Original-URL/Version/Metadaten stehen jeFenster imInventar. Kein Vollquellhash wird erfunden.
- [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/),v5.1.2,publicdomain,physische Land-/See-/Flussgeometrien1:10million. `10m` imNamen bedeutet10million, keine10Meter. Vollständige ursprünglicheDateien gehasht. Keine Straßen/Bauten/Labels gerendert.
- [AWMC](https://github.com/AWMC/geodata/tree/7ecf8bc),ODbL1.0,UNCChapelHill,abgeleitet ausBarringtonAtlas/OpenStreetMap. Nur historischeScope-Referenz; kein exakter117erGrenzanspruch.1von112Polygonen ist ungültig; unveränderteQuelle bleibt erhalten und ein separatesMakeValid-Auditartefakt dokumentiert den Befund.
- [geoBoundaries](https://www.geoboundaries.org/),Commit9469f09,EnglandADM1ausEurostatCC-BY4.0;GBRADM2ausONS,OpenGovernmentLicencev3.0. LayerboundaryID und tatsächlicheFeature-shapeID sind getrennt. Attribution:geoBoundaries,Runfolaetal.2020.

Befehle vom Repositoryroot, vorhandenes GDAL3.13.3 und Python3.14+numpy verwenden, keine Installation:

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

`data_bind` rekonstruiert Region/Projektion/Tiledefinition; versionierte Policy-/Schutz-/Detail-/Genauigkeitsdateien sind feste Eingaben und werden nicht überschrieben. Kamera-Profil ist eine separate Grafikownerdatei; deren Hash muss vor neuem Lauf zur Policy passen. Geänderte Eingaben erzeugen eine neue Datenrevision; bestehende Runartefakte nicht überschreiben. Erzeugte große Payloads und Rohquellbestände sind Git-ignoriert und werden aus den Rezepten rekonstruiert; die überschaubaren Offline-Rohmessungs-CSV werden für die Prüfbarkeit versioniert. Quellenreferenzen und kleine Qualitäts-/Inventarartefakte werden versioniert. Remoteabfragen benötigen Netzzugriff, keine Konten oder kostenpflichtigenDienste.

`data_export_run.py /absoluter/runroot` friert Daten perHardlink (oderKopie) innerhalb des Runs ein, niemals perSymlink. Es erzeugt root-level Kitmanifeste mit `data/...`Artefaktpfaden und kopiert das camera-profile unter demselben relativenPfad. Bereits anders vorhandeneDateien sind ein Fehler; eingefroreneHardlinks danach nicht mutieren. `tiles.json` ist echteRuntimeprobe und wird vom Capture-/Grafikowner produziert, `expected-tiles.json` ist nur unabhängige Offlineerwartung.

Alle Geodaten sind heutebasiert. Küsten/Deltas/Flüsse, Stauseen/Kanäle/Landgewinnung,Vegetation/Gletscher180n.Chr. bleiben ein separat dokumentierter historischerKorrekturbacklog. RepräsentativeBäume zeigen Coverklassen und behaupten keine gemessenenEinzelbaumstandorte. Kultivierte/verwaltete/bebaute Klassen werden ohne Felder,Plantagenreihen oder Bauobjekte abstrakt dargestellt; WorldCover trennt nicht jede Plantage/natürlichenWald oder Verkehrsfläche.

Revision3 verbessert ausschließlich die vorbereitete Offline-Wasserübersicht auf4096×3072 (6000mKüstenbudget bleibt), korrigiert Anchorhöhen/Journal-/VRT-Bezeichnung und trennt vor Neumessung horizontaleSourcequeryidentität von numerischemProjektionsroundtrip. Der alte v2-Fehler6418.557m bleibt im Run unter data-revisions/landscape-v2 erhalten; v3Max2040.133m auf denselben2340Quellpunkten. TatsächlicheRuntime nutzt dieselbe8192×6144Detailwassermaske bei allenZooms. Ein v2→v3Runexport benötigt bewusst `--update-v3`; der Exporter prüft die gespeicherte v2Revision vorher. Die ungenutzte60sVorläuferquelle wird von v3Exports ausgeschlossen.
