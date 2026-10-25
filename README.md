# vic3-clone

## Aktueller Auftrag: Build-Kit 1 vollständig umsetzen

Der aktuelle Nutzerauftrag vom 25.10.2026 ist das
[Build-Kit für Landschaft, stufenlosen Zoom und quadratische Tiles](docs/kit1/README.md):
verkleinerte Modelllandschaft des Reichsraums bei größter Ausdehnung um 117
und des gesamten Mittelmeerraums, ausdrücklich mit England und nördlichem Kontext; reale Geodaten mit kontrollierter Generalisierung,
flache Fernkarte → zoomgebundene isometrische Diorama-Nahansicht und
einheitliche kantige Bildsprache; unsichtbare quadratische Tile-Grundlage, ohne GUI oder weitere Darstellungsmodi. [Fertiger Startprompt](docs/kit1/START_PROMPT.md). Die aktuelle Arbeit umfasst Landschafts-App, geografische Datenpipeline, Renderer, lokale Paketierung, Laufzeitmessungen und unabhängige Kit-1-Abnahme. Die Implementierung befindet sich im laufenden Prüfstand; keine A01–A16-Abnahme oder Nutzerbewertung wird vorweggenommen. [Runstatus und Wiederaufnahme](runs/kit1-landscape-v5-2026-10-25/STATUS.md), [lokaler Start und Fresh-Clone-Schritte](runs/kit1-landscape-v5-2026-10-25/FRESH_CLONE_GUIDE.md), [gehashter Evidence-Index](runs/kit1-landscape-v5-2026-10-25/EVIDENCE_INDEX.json) und [Git-Handoff](runs/kit1-landscape-v5-2026-10-25/GIT_HANDOFF.md) dokumentieren den Stand. Historische Korrekturen für 180 n. Chr. bleiben für später festgehalten. [Entscheidungen](docs/kit1/decisions.md) und [Kit-Arbeitsstand](docs/kit1/STATUS.md) beschreiben den Vertrag.

Im aktuellen Checkout kann die Landschaft nach Daten-/Rendererbuild mit `./scripts/run-landscape` gestartet werden. Die finale lokale macOS-App [Roma Aeterna Final.app](<artifacts/Roma Aeterna Final.app>) wurde auf Release-v2 gebaut und als Paket gestartet; ein frischer Git-Clone enthält die großen Geodaten- und Renderpayloads nicht, ihre Reproduktion und Abhängigkeiten stehen in der Fresh-Clone-Anleitung. Die finale unabhängige Matrix ist qualifiziert abgeschlossen: A08 Nutzerstil bleibt offen, A12 GPU-/Per-Pass-Zeit fehlt, A16 enthält vier begründete NA, die der Kitchecker nicht darstellen kann. Die App wurde mit echten Eingaben geprüft; Paket-/Messbelege stehen im Runreport und Evidence-Index.

Projekt- und Kitdateien werden im privaten GitHub-Repository
[ramonfueglister/romaaeterna](https://github.com/ramonfueglister/romaaeterna)
versioniert.
Die maßgebliche Kit-Quelle ist [`docs/kit1/`](docs/kit1/); das fertige
Downloadpaket liegt unter [`artifacts/kit1-build-kit.zip`](artifacts/kit1-build-kit.zip).

Die folgende Wirtschaftsgrundlage bleibt für spätere Arbeiten erhalten. Ihre
frühere Phasenreihenfolge erweitert den aktuellen Landschaftsauftrag nicht.

## Bestehende Wirtschaftsgrundlage

Dieses Repository dokumentiert einen langfristigen, eigenständigen
Wirtschaftssimulationskern in Rust. Eine spätere iPad-Anbindung über Swift ist
vorgesehen; ein iPhone-Ziel ist für den aktuellen Auftrag ausdrücklich nicht
mehr maßgeblich. Die beschriebene Wirtschaftsphase baut keine vollständige App und keine
Politik-, Militär- oder UI-Schicht.

## Auftrag der Wirtschaftsphase

Für diese Phase soll eine **möglichst vollständige und messbar prüfbare
Wirtschaftssimulation** entstehen. „Perfekt“ bedeutet dabei nicht, fremden
Quellcode oder unbekannte Originalformeln zu rekonstruieren. Es bedeutet, dass
die wirtschaftlich relevanten Funktionen des eigenen Modells vollständig
beschrieben, bilanziert, deterministisch wiederholbar, mit Fehlergrenzen
versehen und auf einem später festzulegenden iPad-Leistungsziel messbar sind.

Jede Aussage wird getrennt gekennzeichnet:

- **Beobachtete Originalregel:** durch eine benannte, versionsbezogene Quelle
  oder einen reproduzierbaren Versuch belegt.
- **Abgeleitete Hypothese:** plausible Erklärung mit offener Unsicherheit und
  vorgeschlagenen Tests.
- **Eigenes Design:** bewusste Regel des neuen Kerns; keine Behauptung über das
  Vorbild.

Es gibt derzeit **keine bestätigte Engine, Formel oder Paritätszusage**.
Statuswerte sind `offen`, `erforscht`, `spezifiziert`, `implementiert` und
`validiert`. Ein Status gilt nur für den jeweils benannten Sachverhalt, nicht
für die gesamte Simulation.

Die vorliegenden Launcher-Metadaten deklarieren `rawVersion1.13.11` bzw.
`1.13.11 (Matcha)`. Das ist **kein Runtime-Nachweis** und keine Bestätigung
einer vollständigen Spiel- oder DLC-Version. Die zugehörigen Identitäts- und
Versionsbefunde stehen in
[`game-version-metadata.json`](docs/research/evidence/game-version-metadata.json)
und
[`artifact-identity-review.json`](docs/research/evidence/artifact-identity-review.json).

## Projektinventar (25.10.2026)

- `docs/kit1/` – operatives Build-Kit und Abnahmekriterien; Produktstatus und
  konkrete Runbindungen stehen unter `runs/kit1-landscape-v5-2026-10-25/`.
- `app/`, `data/`, `scripts/`, `tools/` – laufende Landschafts-App, Datenpipeline
  und lokale Start-/Buildwerkzeuge; große Roh- und abgeleitete Payloads können
  lokal erzeugt sein und sind nicht alle in Git enthalten.
- `scripts/rea` – vorhandener Wrapper für die lokale REA/Ghidra/Java-Umgebung.
- `docs/superpowers/specs/2026-10-24-simulation-engine-design.md` –
  überholter historischer Entwurf; nur der Hinweis am Anfang wurde ergänzt.
- `docs/economy/README.md` – Einstieg, Scope und Dokumentationsregeln dieser
  Wirtschaftsphase.
- `docs/economy/requirements.md` – ausführliche, noch nicht implementierte
  Anforderungen und Abnahmekriterien.
- `docs/economy/toolchain.md` – dokumentierte, projektlokale Rust-
  Buildgrundlage; noch kein Cargo-Projekt.
- `docs/research/ghidra-economy.md` – vorhandener REA/Ghidra-Bericht eines
  anderen Agents.
- `docs/research/public-economy-sources.md` – vorhandener Bericht öffentlicher
  Quellen eines anderen Agents.
- `docs/research/evidence-review.md` – unabhängige Evidenzprüfung.
- `docs/research/ghidra-recovery-options.md` – Optionen und Grenzen einer
  möglichen weiteren REA/Ghidra-Untersuchung.

Die laufende Landschafts-App und ihre Daten sind keine abgeschlossene
A01–A16-Abnahme; finale Start-/Capturebelege und unabhängige Prüfung stehen im
Runstatus. Kit-Hilfswerkzeuge und ihre eigenen Tests stehen unter
`docs/kit1/tools/` und `docs/kit1/tests/`.
Die isolierte Rust-Toolchain unter `.tooling/` ist eine vorbereitete
Buildgrundlage und kein Produktcode.

## Phasengrenzen der Wirtschaftssimulation

In dieser Phase gehören Kapital und Investitionen, Eigentum und Dividenden,
Beschäftigung, Einkommen, Wohlstand und Bedarf, Inputs und Produktion, Bau,
Handel und Transport sowie Staatsfinanzen und Kredit zum Wirtschaftsscope.
Politik, Militär und die komplette App liegen außerhalb der Phase. Ihre
späteren ökonomischen Wirkungen werden über definierbare Schnittstellen
angebunden, nicht stillschweigend in dieser Spezifikation erfunden.

Recherche, Dokumentation, Implementierung und Prüfung erfolgen ausschließlich
über klar abgegrenzte Subagent-Aufträge; der Hauptagent koordiniert und führt
die Ergebnisse zusammen. Geeignete kostengünstige Modelle sind der Standard;
höhere Kosten werden nur bei begründeter fachlicher Notwendigkeit eingesetzt.
Die REA/Ghidra-Methode ist die einzige angeforderte Skill-Methode; alte
Superpowers-Freigabegates werden nicht erneut angewandt. Herkunftsnachweise
und unabhängige Implementierung bleiben erforderlich. Der REA/Ghidra-
Arbeitsrahmen ist aber weder eine pauschale Rechtsfreigabe noch ein starrer
Cleanroom- oder Nutzungsfreibrief.

## Einstieg in die Wirtschaftsgrundlage

Lies zuerst [docs/economy/README.md](docs/economy/README.md) und danach
[docs/economy/requirements.md](docs/economy/requirements.md). Die projektlokale
Rust-Toolchain bleibt auf `1.99.1` gepinnt; iOS-/iPadOS-Targets sind nicht
getestet. Dynamische REA/Ghidra-Befunde werden ausschließlich im jeweils
aktuellen [Wirtschaftsbericht](docs/research/ghidra-economy.md) gepflegt.
