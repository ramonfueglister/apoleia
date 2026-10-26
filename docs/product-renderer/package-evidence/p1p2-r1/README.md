# Packaging-P1/P2 — korrigierter V16-Transport

Status `implementiert`; genannte CPU-/Filesystemfälle `validiert`.
Referenz `kit1-landscape-v5`, unveränderter V16-V1-Freeze. Unabhängige Nachprüfung,
finale Renderer-/Cloud-/Cacheinputs und echter Appstart bleiben `offen`.

P1: Typisierte Closure für ausgewählte Render-Meshmanifeste. Datasetfelder, die
im gebundenen Runtimecode als `manifest.<meshkey>`/`get`/`has` referenziert werden,
müssen in `dataset.asset_keys` stehen. V16 verlangt den Feature/Corepfad; der
Contextpfad ist vorhanden, wird aber von dieser Runtime nicht gelesen. Je Block
werden ausschließlich vertices, indices, feature_inventory, picking offsets und
face_ids gehasht/inventarisiert. Die Produktions-Sourcegrids/-heights bleiben draußen.

P2: `safe_relative` blockiert case-insensitive `runs` und typische Secrets in
Transportdestinationen. Tests prüfen auch gehashte `repository_ref`-Eingaben aus
Forschungsruns. Eingefrorene Quell-App-/Binding-Locators bleiben lesbare Inputs;
keine ganze Runablage wird dadurch ins Worldinventar übernommen.

Aktueller Dryrun: **9.504 Dateien / 2.925.580.324 Bytes**. Gegenüber der historischen
unvollständigen Probe fehlen nun keine Coreblöcke: hinzugekommen sind das
7.146.847-Byte-Coremanifest plus 1.890×5 Runtimepayloads mit 829.106.587 Bytes.
Acht Tests bestehen, darunter richtige typed Closure, explizit fehlende irrelevante
Sourcegrids, corrupt/missing Runtimeblock, verweigerter ausgelassener Meshkey und
verweigerte Run-/Secretpfade. Die bestehenden Resource-/Water-/Launcher-/Relocation-
Prüfungen laufen mit.

```sh
python3 app/scripts/package_macos_test.py
python3 app/scripts/package_macos.py \
  --spec docs/product-renderer/package-evidence/p1p2-r1/v16-transport-spec.json \
  --dry-run
```

`cpu-tests.log`, `v16-dry-run.json`, `negative-cases.json` und `checkpoint.json`
binden die Ergebnisse. `old-inventory-refusal.log` belegt Exitcode2 der alten
unvollständigen 53-Dateien-Spec; `final-input-refusal.log` belegt Exitcode2 wegen
weiterhin fehlender finaler renderer/cloud/forest_cache-Inputs. Kein Bundle wurde
gebaut, kein GPU-/Appstart vorgenommen. Der ältere Ordner `current-pipeline/`
bleibt unverändert als historische Evidenz erhalten.
