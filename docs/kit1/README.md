# Kit 1 — Reichsraum und Mittelmeer: Landschaft, stufenloser Zoom und unsichtbare Tiles

**Referenzversion:** `kit1-landscape-v5`, Stand 25.10.2026.  
**Status:** Auftrag und Arbeitsweise `spezifiziert`; Umsetzung und Laufzeitprüfung `offen`.

Dieses Build-Kit beschreibt einen zusammenhängenden späteren Umsetzungsauftrag:
eine startbare, realdatenbasierte verkleinerte regionale Landschaft mit flacher Fernkarte
und kontinuierlichem zoomgebundenem Übergang zur isometrischen Diorama-Nahansicht, unsichtbaren quadratischen logischen Tiles, ohne GUI oder weitere Darstellungsmodi. Es enthält ausführbare lokale **Kit-Prüfwerkzeuge**, konkrete Vorlagen und
Adapterverträge, aber keine Spiel-/Rendererimplementierung. Sein Lesen startet
keine Produktumsetzung.

Der aktuelle Nutzerauftrag ergänzt die quadratische Tile-Grundlage und präzisiert:
**keine GUI und keine unterschiedlichen Darstellungsmodi in diesem Schritt**.
Die jüngste Präzisierung ergänzt den Karten-Diorama-Übergang und datenbasierte
Generalisierung mit kontrollierten Fehlern; keine Spielimplementierung wird hier gestartet.
Erst ein späterer Nutzerstart beginnt die Umsetzung.
[START_PROMPT.md](START_PROMPT.md) ist der vollständige kopierbare Auftrag;
[KICKOFF.md](KICKOFF.md) enthält Wiederaufnahme-/Abschlussvorlagen.

## Versionierung und GitHub

Das Kit und die spätere Umsetzung liegen im privaten GitHub-Repository
[`ramonfueglister/romaaeterna`](https://github.com/ramonfueglister/romaaeterna).
Konto, Owner, Zielname und private Sichtbarkeit wurden geprüft; die erste Ablage
dieses Projektstands ist bereits auf `origin/main` abgelegt: Commit
[`60ff002`](https://github.com/ramonfueglister/romaaeterna/commit/60ff002563e73555ea53abb44a4195cea1f15872).
Details zu Quellen,
Abhängigkeiten und Commits stehen in [WORKFLOW.md](WORKFLOW.md).

**Geografischer Umfang v5:** ein zusammenhängender Ausschnitt nach dem Bezugsrahmen
des Römischen Reiches bei seiner größten Ausdehnung unter Trajan um **117 n. Chr.**,
mit dem **gesamten Mittelmeerraum**, angrenzendem Land-/Meerkontext sowie ausdrücklich
**England und zusätzlichem Raum nördlich davon**. Die Kartenmaske endet nicht hart
an Reichsgrenzen. Britannien, Gallien, Iberien, Donauraum/Dakien, Nordafrika und die
östlichen Reichsgebiete sind nach der belegten Abgrenzung einzubeziehen; keine
bloße Mittelmeerküsten-Demo. Weder nur Europa/EU noch die gesamte Erde sind beauftragt.
Die Landschaftsreferenz bleibt **180 n. Chr.**, heutige Geodaten bleiben die Basis.
Der 117er Bezugsrahmen legt den Ausschnitt fest, keinen neuen Spielstartzeitpunkt.
Exakte Grenzen, Meerkontext und nördliche Pufferbreite werden vor Umsetzung aus
Quellen begründet und in `region.json` gebunden, nicht hier als Tilezahl/Skala erfunden.
Für moderne Gebietsauswahlanker dient geoBoundaries gbOpen ADM2 bevorzugt als
Orientierung; es setzt keine historischen Grenzen oder finale politische Cutline.
Details: [REGION](operations/REGION.md).

## Lesen und benutzen

| Datei | Zweck |
|---|---|
| [decisions.md](decisions.md) | Bestätigte Entscheidungen, Arbeitswerte und zurückgestellte Themen; maßgeblicher Interviewstand |
| [TASK.md](TASK.md) | **Was** später gebaut wird: gesamter Pfad, Grafik, Geografie, Maßstab und Lieferumfang |
| [WORKFLOW.md](WORKFLOW.md) | **Wie** Agents arbeiten: Rollen, interne Schritte, Herkunft und Prüfung |
| [ACCEPTANCE.md](ACCEPTANCE.md) | Prüfplan mit visuellen und numerischen Nachweisen; noch keine bestandenen Tests |
| [START_PROMPT.md](START_PROMPT.md), [KICKOFF.md](KICKOFF.md) | Fertiger Startauftrag und ergänzende Wiederaufnahme-/Abschlussvorlagen |
| [STATUS.md](STATUS.md) | Dauerhafter tatsächlicher Stand und nächster zulässiger Schritt |
| [REFERENCES.md](REFERENCES.md) | Herkunft, Referenzkit-Übertragung und Einordnung der Stilbilder |
| [Landschafts-Stilguide](references/STYLE_GUIDE.md) | Nutzer-Primärreferenz, eingeschränkte Fernstilreferenz, Provenienz und Geografie-Ausschlüsse |
| [RENDERING_RESEARCH.md](RENDERING_RESEARCH.md) | Gezielter Quellenabgleich bis 25.10.2026, Evidenzlücken und begründete Verfahrenswahl |
| [RENDERING](operations/RENDERING.md) | Rendering-v4-Plan für Daten-/LOD-/Cache-/Snapshotverträge, Hitch-/Streaming-/Animationsverträge, Godot-Vertikalpfad und harte headless-Simulationsgrenze; Spezifikation, kein Renderer |
| [Echte Spiel-Screenshots](references/screenshots/README.md) | Sechs lokale Urbek-/Victoria-3-Referenzen mit sichtbarer Zuordnung und Ausschlüssen |

## Verhältnis zum bestehenden Projekt

Die ältere Wirtschaftsphase unter `docs/economy/` bleibt erhalten. Für **diesen
Kit-1-Auftrag** hat die neuere ausdrückliche Nutzerentscheidung Vorrang: zuerst
Landschaftsgrafik und Zoom, nicht Wirtschaft, Städte oder das vollständige Spiel.
Das langfristige Gesamtspiel bleibt der Rahmen für spätere Kits. Die allgemeinen
Rollen- und Evidenzregeln aus `AGENTS.md` gelten weiter; dessen frühere
Phasenbeschreibung ist keine Erlaubnis, Kit 1 um Wirtschaftscode zu erweitern.

Rust-Kern, spätere Swift-Anbindung und iPad sind bestehender Projektkontext.
Zusätzlich sind Windows- und Linux-Versionen ausdrücklich als spätere
Produktziele gewünscht; ihre Umsetzung liegt deutlich nach dem aktuellen Kit-1-
Umfang. Mac-Erstprüfung bleibt vorgesehen, iPad optional. Die vom Nutzer genannte Godot-App ist die Zielengine; dieses Kit legt ihre
Integration jedoch nicht fest. Plattformneutraler Rust-Kern,
Hostadapter und Renderer sollen getrennt bleiben; Metal ist ein optionaler
Apple-Pfad, und geräteabhängige Funktionen müssen zur Laufzeit geprüft werden.
Ein Godot-Projekt und eine Runtime-Version sind hier nicht vorhanden;
Windows-/Linux-Verhalten ist ungeprüft. Referenzhardware und Leistungswerte bleiben
offen; es gibt noch keine Produktimplementierung oder Plattformzusage.

## Bedeutung von „Oneshot“

Ein vollständiger Auftrag soll zum gesamten erkundbaren Ergebnis führen. Interne
Arbeitsschritte, Tests, Korrekturen und Wiederaufnahme nach Unterbrechungen gehören
dazu. Ein isolierter Teil der Projektregion, eine Bildserie oder ein isolierter Zoom-Prototyp
erfüllt den Auftrag nicht. „Oneshot“ ist weder eine Erfolgsgarantie noch eine
Erlaubnis für unbegrenzte Laufzeit, fremde Umgebungsänderungen oder das Umgehen
von Werkzeug- und Berechtigungsgrenzen.

## Operativ verwenden

Im Kitordner beginnen:

```sh
python3 tools/kit.py self-check
python3 -m unittest discover -s tests -v
python3 tools/kit.py preflight templates/config.json
```

Der erste Befehl prüft Kit-Integrität, der zweite die Hilfswerkzeuge. Der dritte
meldet erwartungsgemäß `blocked` (Exit 2), weil Datensätze, Renderer und technische
Testparameter noch ungebunden sind. Das ist keine defekte Kitinstallation und
kein bestandener Produkttest. Es wird nichts installiert oder heruntergeladen.

| Operativer Bestandteil | Einstieg |
|---|---|
| Wissenschaftliche Methoden / Ableitungs- und Fehlertoleranzprozess | [Methoden](references/GEODATA_METHODS.md), [GENERALIZATION](operations/GENERALIZATION.md) |
| Regionaler Gebietsrahmen und Quellen-/Maskenbindung | [REGION](operations/REGION.md), [Gebietsvorlage](templates/region.json) |
| Vorbereitung, OS-/Abhängigkeitsmatrix, konkrete Befehle | [SETUP](operations/SETUP.md) |
| Unsichtbare quadratische Tile-Grundlage und interne Probes | [TILES](operations/TILES.md), [Tile-Beleg](templates/tiles.json) |
| Expliziter späterer Daten-/Renderer-/Capturevertrag | [ADAPTER](operations/ADAPTER.md), [Konfigvorlage](templates/config.json) |
| Datenwahl, Herkunft, Transformation, regionaler Abdeckungs- und Korrekturprozess | [DATA_PIPELINE](operations/DATA_PIPELINE.md), [Quellenmanifest](templates/sources.json) |
| Offline-Renderpaket, hierarchische LOD-Blöcke, Streaming-/Fallback-Lifecycle, Render-Snapshot und Messplan | [RENDERING](operations/RENDERING.md) |
| Einheitliche Terrain-/Vegetationsproduktion und Importprüfung | [STYLE_PIPELINE](operations/STYLE_PIPELINE.md) |
| Rollen, Dateibesitz und Auftragskarten | [ROLES](operations/ROLES.md), [ASSIGNMENT](templates/ASSIGNMENT.md) |
| Prüfungen, Standbilder, kontinuierliche Aufnahmen, Rohmessungen | [VERIFY_CAPTURE](operations/VERIFY_CAPTURE.md), [Fixture](templates/fixture.json), [Report](templates/report.json) |
| Persistenter Plan, Journal, Handoff, Fehler- und Abschlussbericht | [RECOVERY](operations/RECOVERY.md), [PLAN](templates/PLAN.md), [PROGRESS](templates/PROGRESS.md), [HANDOFF](templates/HANDOFF.md), [DEFECT](templates/DEFECT.md), [REVIEW](templates/REVIEW.md), [REPORT](templates/REPORT.md) |
| Technische Auswahl ohne erneut geführtes Grafikinterview | [Entscheidungsvorlage](templates/TECHNICAL_DECISION.md) |
| Datenverträge und genaue Validatorgrenze | [Schemas](schemas/README.md) |
| Vollständiger Archivabgleich | [Übertragungsmatrix](REFERENCE_MAP.md), [alle 224 Einträge](REFERENCE_MAP.json) |
| Portables Paket ohne Installationswirkung | [PACKAGING](operations/PACKAGING.md), [Dateiinventar](KIT_CONTENTS.json) |

`tools/kit.py init-run <neuer-ordner>` erzeugt einen vollständigen leeren
Arbeitslauf mit JSON- und Markdownvorlagen. Keine Messwerte werden erfunden.
Weitere Befehle: `validate`, `report-check`, `package`, `verify-package`; Details
in SETUP und PACKAGING. Laufdaten außerhalb dieses Kitordners halten.

Das komplette Kit ist ohne Originalarchiv lesbar und prüfbar. Schriftliche
Stilvorgaben und eine vom Nutzer bereitgestellte primäre Landschaftsreferenz sind
enthalten; sie ist weder Geodaten noch Laufzeitbeleg. Frühere eigene generierte
Stilproben wurden aus dem aktuellen Kit entfernt. Eine neue Fernstilprobe ist
mit dem Hinweis enthalten, dass sie den geforderten flachen 2D-Fernendpunkt nicht
belegt. Die neue Nahprobe wurde verworfen und entfernt. Keine Stilprobe ist ein
Spielasset.
Zusätzlich sind sechs echte offizielle Urbek-/Victoria-3-Screenshots als getrennt
zugeordnete Referenzen enthalten. Sie sind kein Produktmaterial und keine
Kit-1-Laufzeitbelege. Assets aus dem fremden MMO-Kit und das erste abgelehnte
Bild sind **nicht mitgeliefert**.

## Vollständigkeits- und Widerspruchsaudit

[FINAL_AUDIT.md](FINAL_AUDIT.md) hält den historischen v2-Prüfumfang, konkrete Befunde,
Korrekturen und Grenzen fest. Die aktuellen Verträge verwenden `kit1-ops-v5`; die Kitwerkzeuge bleiben reine Beleg-/Paketprüfer.
Die sechs echten Referenzbilder wurden inzwischen vom Nutzer akzeptiert.

Die historische Tile-Erweiterung ist in [TILE_UPDATE.md](TILE_UPDATE.md)
protokolliert. Die historische Geoänderung steht in [GEODATA_UPDATE.md](GEODATA_UPDATE.md);
der aktuelle Gebietsumfang in [REGION_SCOPE_UPDATE.md](REGION_SCOPE_UPDATE.md).
Historische v2-/v3-Prüfungen gelten nicht automatisch für v5. Die Umsetzung der Landschaft bleibt ungestartet.
