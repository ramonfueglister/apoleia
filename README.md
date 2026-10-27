# Romaaeterna

## Aktueller Auftrag: Build-Kit 1 vollständig umsetzen

Der aktuelle Nutzerauftrag vom 25.10.2026 ist das
[Build-Kit für Landschaft, stufenlosen Zoom und quadratische Tiles](docs/kit1/README.md):
verkleinerte Modelllandschaft des Reichsraums bei größter Ausdehnung um 117
und des gesamten Mittelmeerraums, ausdrücklich mit England und nördlichem Kontext; reale Geodaten mit kontrollierter Generalisierung,
flache Fernkarte → zoomgebundene isometrische Diorama-Nahansicht und
einheitliche kantige Bildsprache; unsichtbare quadratische Tile-Grundlage, ohne GUI oder weitere Darstellungsmodi. [Fertiger Startprompt](docs/kit1/START_PROMPT.md). Die aktuelle Arbeit umfasst Landschafts-App, geografische Datenpipeline, Renderer, lokale Paketierung, Laufzeitmessungen und unabhängige Kit-1-Abnahme. Die Implementierung befindet sich im laufenden Prüfstand; keine A01–A16-Abnahme oder Nutzerbewertung wird vorweggenommen. [Runstatus und Wiederaufnahme](runs/kit1-landscape-v5-2026-10-25/STATUS.md), [lokaler Start und Fresh-Clone-Schritte](runs/kit1-landscape-v5-2026-10-25/FRESH_CLONE_GUIDE.md), [gehashter Evidence-Index](runs/kit1-landscape-v5-2026-10-25/EVIDENCE_INDEX.json) und [Git-Handoff](runs/kit1-landscape-v5-2026-10-25/GIT_HANDOFF.md) dokumentieren den Stand. Historische Korrekturen für 180 n. Chr. bleiben für später festgehalten. [Entscheidungen](docs/kit1/decisions.md) und [Kit-Arbeitsstand](docs/kit1/STATUS.md) beschreiben den Vertrag.

Im aktuellen Checkout startet die Landschaft mit `./scripts/run-landscape`. Die frühere macOS-App (Release-v2) gehört zur gelöschten Diorama-Grafik; eine Paketierung des Tile-Geländes steht noch aus. Die finale unabhängige Matrix ist qualifiziert abgeschlossen: A08 Nutzerstil bleibt offen, A12 GPU-/Per-Pass-Zeit fehlt, A16 enthält vier begründete NA, die der Kitchecker nicht darstellen kann. Die App wurde mit echten Eingaben geprüft; Paket-/Messbelege stehen im Runreport und Evidence-Index.

### Gelände: Tile-Look (seit 27.10.2026)

Die Landschaft zeigt ein Kachelgelände im Stil „SimCity 2000 trifft EU5“:
quadratische Kacheln mit Höhenstufen, Rampen und Klippen, Küsten mit Strand,
Flüsse und Seen als Wasserkacheln, Felder, 3D-Bäume und römische Häuser, in sechs
Zoomstufen von 0,5 km bis 16 km pro Kachel. Alle Daten dafür liegen in Git
(`artifacts/render-data/tile-terrain-r1`, rund 35 MB), ein frischer Clone startet
direkt mit `./scripts/run-landscape`. Aufbau, Daten und Steuerung:
[docs/product-renderer/TILE_TERRAIN.md](docs/product-renderer/TILE_TERRAIN.md).
Die frühere Diorama-, Clipmap-, Wald- und Flussgrafik ist gelöscht; das Wetter
(`app/scripts/weather/`) ist unverändert.

Projekt- und Kitdateien werden im privaten GitHub-Repository
[ramonfueglister/romaaeterna](https://github.com/ramonfueglister/romaaeterna)
versioniert.
Die maßgebliche Kit-Quelle ist [`docs/kit1/`](docs/kit1/); das fertige
Downloadpaket liegt unter [`artifacts/kit1-build-kit.zip`](artifacts/kit1-build-kit.zip).

## Projektinventar (26.10.2026)

- `docs/kit1/` – operatives Build-Kit für die gebundene Reichs-/Mittelmeerlandschaft und stufenlosen
  Zoom: Arbeitsrezepte, Verträge, Vorlagen und geprüfte lokale Hilfswerkzeuge.
  Produktstatus und Runbindungen stehen unter `runs/`. Kit-Hilfswerkzeuge und ihre eigenen Tests
  stehen unter `docs/kit1/tools/` und `docs/kit1/tests/`.
- `app/`, `data/`, `scripts/`, `tools/` – laufende Landschafts-App (Godot,
  Tile-Gelände, Wetter), Datenpipeline und lokale Start-/Buildwerkzeuge;
  große Roh- und abgeleitete Payloads werden lokal erzeugt und liegen nicht in Git.
  Die App ist noch keine abgeschlossene A01–A16-Abnahme.
- `docs/toolchain.md` – dokumentierte, projektlokale Rust-Buildgrundlage
  (`scripts/cargo`, `rust-toolchain.toml`); noch kein Cargo-Projekt. Die
  isolierte Toolchain unter `.tooling/` ist kein Produktcode.

Die frühere Victoria-3-Wirtschaftsrecherche (REA/Ghidra-Berichte,
Konfigurationsbeobachtungen, Anforderungen und Entwurf) wurde am 26.10.2026
entfernt. Ein eigenes Wirtschaftssystem wird später als eigenständiges Kit
geplant.
