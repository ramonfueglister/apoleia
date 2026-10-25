# Git handoff — Kit 1 branch

**Status:** branch prepared; no commits or pushes.
**Remote:** `origin` = `https://github.com/ramonfueglister/romaaeterna.git` (private; `gh repo view` confirmed read access).
**Base:** `01c48ad` / `origin/main` at branch preparation.
**Local branch:** `codex/kit1-landscape`.
**Remote branch check:** read-only `git ls-remote --heads origin refs/heads/codex/kit1-landscape` against the authorized private remote returned no matching ref. Exact destination verified; branch has not been pushed. No force operation was used.

The working directory already held authorized implementation/data/run changes when the branch was created. `git switch -c codex/kit1-landscape` preserved them; nothing was reset or staged. Do not stage the whole tree: generated/raw payload directories are large and some are intentionally excluded from Git.

## Ignore boundary

Root `.gitignore` now excludes generated runtime captures, packed render payloads (`.bin` / `.u8`), run-local raw rasters and bulky derived raster surfaces, app/build caches, logs and environment secrets. `data/.gitignore` continues to exclude raw source files and derived raster binaries, but no longer ignores derived CSV measurements so those remain auditable/versionable. Small manifests, pipeline recipes, policy docs, raw measurement CSV, reports and independent review notes stay visible to Git.

Local volume inventory at the audit point:

| Area | Local size | Git handling |
|---|---:|---|
| `data/` | 1.7 GB (about 931 MB raw, 738 MB derived, 40 MB derivation samples) | Raw source and derived raster payloads excluded; small manifests/measurement CSV retained. |
| `runs/` | 1.7 GB including v2 snapshot and run-local hardlinks | Hardlinked raw rasters and bulky derived surfaces excluded; run docs/manifests/CSV/reviews retained. |
| `artifacts/` | 1.3 GB | Runtime captures excluded; small render-data JSON retained; height/water upload payloads excluded. |
| `app/` | about 152 KB plus ignored `.godot/` cache | Source, project, scripts, shaders retained. |

Largest individual excluded payloads observed: source TIFF 444 MB, derived height-detail Float32 463 MB, packed height RG8 232 MB, plus runtime films (including one 121 MB). Keep complete local evidence. For files excluded from Git, record SHA-256, local path, producing command, and matching source/build revision in the final run report; choose a release/archive or another controlled artifact channel if distribution is required. Do not add >100 MB films/binaries to regular Git history.

No secret-like filenames (`.env`, PEM/P12/private-key patterns, credentials files) were found in the scanned worktree paths. Root ignore patterns exclude `.env` files; `.env.example` is exempted for safe templates.

## Proposed reviewable commit groups

Stage each group explicitly after the final capture/report handoff; review its staged paths and size before creating the commit. No commit or push is authorized by this file.

1. **Data pipeline and contracts:** `tools/data_*.py`, compact `data/*.json` manifests/policies, `data/reference` small geometries, eligible `data/derived/*.csv` measurement evidence, `docs/product-data/**`, and the raw/derived-data ignore policy. Exclude `data/raw/**` and ignored raster payloads. Preserve v2 negative evidence in run metadata; do not accidentally stage duplicate run hardlinks.
2. **Renderer and local launch:** `app/project.godot`, scene, scripts, shaders, safe engine-license metadata, `scripts/build-landscape`, `scripts/run-landscape`, `docs/product-renderer/**`, renderer upload JSON policies. Exclude `.godot`, app bundles, render-data binary payloads and runtime captures.
3. **Operations and report:** root `README.md` current Kit-1 entry/start path; `runs/kit1-landscape-v5-2026-10-25` small operational docs, frozen config/fixture/report/manifests, `EVIDENCE_INDEX.json`, raw measurement CSV, independent-review notes and compact machine-readable evidence. Exclude ignored raw/large raster/run payloads; retain a local inventory of their hashes and generation commands.

Use separate content-focused commits for those groups. Stage only reviewed paths; capture final `git status`, `git diff --cached --stat`, and per-file sizes before commit. Final A01–A16 statuses and evidence hashes must reflect the final immutable run and independent reviewer, not these interim materials.

## Clean-clone startability/reproducibility boundary

`scripts/build-landscape` and `scripts/run-landscape` run `app/scripts/pack_height.py` and `pack_water_distance.py` before launching Godot. Those encoders need local `data/derived/height-detail.f32`, `landscape.json`, `land.geojson`, `lakes.geojson`, and `water-detail.u8`. These source/derived inputs are not carried as Git binaries. The documented `tools/data_*.py` pipeline reconstructs/downloads them using Python 3.14, NumPy 2.5.4 and GDAL 3.13.3 on the current host; a clean clone therefore needs those inputs produced or supplied separately before the app starts. Do not claim Git-alone, cross-platform, or iPad standalone packaging until the owner verifies a clean-clone procedure and actual local package launch. Graphics still needs to finish the local `.app` package smoke and provide its hash/launch evidence.

## Daten-Commitcheckpoint — 2026-10-25

Auf `codex/kit1-landscape` wurden nach der lokalen Pfad-/Größenprüfung drei getrennte, lokale Commits erstellt:

- `3cecd01` — `data: add reproducible landscape pipeline` (18 `tools/data_*.py`-Dateien).
- `d9d955c` — `data: bind landscape v3 provenance and samples` (45 `data/`-Dateien, 12,363,222 B; keine Roh-TIFFs, Raster, Logs oder großen generierten Fehler-/Horizontal-CSV).
- `6ecfcce` — `docs: bind landscape data policy and probes` (13 `docs/product-data/`-Dateien).

Kein App-, Run-, Abschlussbericht- oder Reviewerartefakt ist in diesen Commits. Die beiden unveränderten importierten Dateien `data/reference/AWMC-LICENSE.txt` und `data/reference/roman-117.geojson` enthalten upstream trailing whitespace; alle übrigen Dateien bestanden `git diff --cached --check`, Dokumentation vollständig. `data/.gitignore` hält große abgeleitete Messserien aus Git.

Die lokale Branch hat keinen Upstream und keinen gecachten Remote-Ref. `git ls-remote` scheiterte aktuell an DNS; der GitHub-Branch-Suchconnector meldete `unknown tool`. Es gab keine Remote-Mutation. Vor dem später autorisierten Push im zulässigen Netzwerkmodus die Branch `codex/kit1-landscape` gegen `https://github.com/ramonfueglister/romaaeterna.git` erneut verifizieren. Sonstige Renderer-/Run-/App-/Root-README-Änderungen sind weiterhin nicht gestaged.

## Finaler Release-v2 / Review-Handoff — 2026-10-25

Die finale unabhängige Reviewmatrix liegt unter `independent-review/FINAL_REVIEW.md` (SHA-256 `4aa830507d0dcb75fbbc859b711fde173e01794a1d177bb4ea21451b46350c0a`) und ist in `report.json` gebunden. Der Bericht kennzeichnet A08 Nutzerstil, A12 nicht verfügbare GPU-/Per-Pass-Zeit und A16 vier nicht anwendbare Offline-Metrikkombinationen ehrlich als offen. Finale Release-v2-Daten-Errata und reproduzierbarer Converter liegen unter `data-report-errata/release-v2/`.

Datencommits sind `3cecd01`, `d9d955c`, `6ecfcce`. Nach Abschluss der Operationsbindung wurden Renderer/Startskripte, Operationsdokumente und kleine Belege separat auditiert und committed; keine `.app`, keine großen Raw-/Render-Payloads, keine Runtime-Caches und kein vollständiger Film werden in regulärem Git verteilt. Finales Bundle und vollständiger Film bleiben lokal, sind aber im Report mit Hash und Erzeugungs-/Startpfad gebunden. Prüfe die darunter dokumentierte Commitliste sowie den exakten `origin`-Branch vor Push. Kein Force-Push, keine Releasepublikation, kein zweites Repo.
