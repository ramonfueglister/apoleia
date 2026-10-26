# Romaaeterna

## Aktueller Auftrag: vollständiges Build-Kit 1 vorbereiten

Der aktuelle Nutzerauftrag vom 25.10.2026 ist das
[Build-Kit für Landschaft, stufenlosen Zoom und quadratische Tiles](docs/kit1/README.md):
verkleinerte Modelllandschaft des Reichsraums bei größter Ausdehnung um 117
und des gesamten Mittelmeerraums, ausdrücklich mit England und nördlichem Kontext; reale Geodaten mit kontrollierter Generalisierung,
flache Fernkarte → zoomgebundene isometrische Diorama-Nahansicht und
einheitliche kantige Bildsprache; unsichtbare quadratische Tile-Grundlage, ohne GUI oder weitere Darstellungsmodi. [Fertiger Startprompt](docs/kit1/START_PROMPT.md). **Aktuell Kit-Dokumente, operative Vorlagen und lokale Kit-Prüfwerkzeuge,
keine Spielimplementierung.** Historische Korrekturen für 180 n. Chr. bleiben für später
festgehalten. [Entscheidungen](docs/kit1/decisions.md) und
[Arbeitsstand](docs/kit1/STATUS.md) sind der Einstieg für diese Aufgabe.

Projekt- und Kitdateien werden im privaten GitHub-Repository
[ramonfueglister/romaaeterna](https://github.com/ramonfueglister/romaaeterna)
versioniert.
Die maßgebliche Kit-Quelle ist [`docs/kit1/`](docs/kit1/); das fertige
Downloadpaket liegt unter [`artifacts/kit1-build-kit.zip`](artifacts/kit1-build-kit.zip).

## Projektinventar (26.10.2026)

- `docs/kit1/` – operatives Build-Kit für die gebundene Reichs-/Mittelmeerlandschaft und stufenlosen
  Zoom: Arbeitsrezepte, Verträge, Vorlagen und geprüfte lokale Hilfswerkzeuge;
  noch keine Grafikimplementierung. Kit-Hilfswerkzeuge und ihre eigenen Tests
  stehen unter `docs/kit1/tools/` und `docs/kit1/tests/`.
- `docs/toolchain.md` – dokumentierte, projektlokale Rust-Buildgrundlage
  (`scripts/cargo`, `rust-toolchain.toml`); noch kein Cargo-Projekt. Die
  isolierte Toolchain unter `.tooling/` ist kein Produktcode.

Die frühere Victoria-3-Wirtschaftsrecherche (REA/Ghidra-Berichte,
Konfigurationsbeobachtungen, Anforderungen und Entwurf) wurde am 26.10.2026
entfernt. Ein eigenes Wirtschaftssystem wird später als eigenständiges Kit
geplant.
