# vic3-clone

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

- `docs/kit1/` – operatives Build-Kit für die gebundene Reichs-/Mittelmeerlandschaft und stufenlosen
  Zoom: Arbeitsrezepte, Verträge, Vorlagen und geprüfte lokale Hilfswerkzeuge;
  noch keine Grafikimplementierung.
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

Noch nicht vorhanden und ausdrücklich nicht vorweggenommen sind Engine-Code,
Produkt-Laufzeittests, bestätigte Geodatenbestände oder eine Produktimplementierung.
Kit-Hilfswerkzeuge und ihre eigenen Tests stehen unter
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
