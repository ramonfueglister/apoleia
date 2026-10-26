# Kit 1 — Herkunft und Referenzen

**Referenzversion:** `kit1-landscape-v5` · **Status:** Herkunft `erforscht`,
Übertragung als eigene Arbeitsweise `spezifiziert`. Keine Referenz ist ein
Laufzeitnachweis für Kit 1.

## Nutzerauftrag als maßgebliche Quelle

Primärquelle ist das gemeinsame Interview in diesem Chat am 25.10.2026.
Der jüngste Ergänzungsauftrag verlangt echte Referenzscreenshots aus Urbek (die Victoria-3-Bilder
wurden am 26.10.2026 entfernt), lokal im Kit und unseren Grafikvorgaben zugeordnet; weiterhin
keine Spielimplementierung und keine erneut geöffneten Entscheidungen.
Die später eingegrenzte Landschaftsphase ersetzt für Kit 1 frühere breitere
Stadt-/Wirtschaftsvorschläge. [decisions.md](decisions.md) ist die portable
Konsolidierung; der Chat muss für die dort beantworteten Fragen nicht neu geführt
werden. Frühere Assistentenvorschläge sind nicht automatisch Nutzerentscheidungen.

Der ursprünglich eingefügte Verlauf ist die nicht mitgelieferte Datei
`Eingefügter Text.txt` (SHA-256: `125ee531ee1373f4fd90e5154ce0d352fbe50fe3b7886a7e274180e4c0f0bf27`).
Er enthält Text und Referenzverweise, nicht alle damaligen Bilddaten. Die neueren
Interviewentscheidungen haben Vorrang. Frühere historische Entwürfe (am 26.10.2026 entfernt) sind keine Quelle für
aktuelle Anforderungen.

## Referenz-Build-Kit: Methode, nicht Produktauftrag

Referenzarchiv: `WorldOfOldcraft-build-kit.zip` (nicht mitgeliefert).
SHA-256: `b639cd2e14c9cb526f511574f161cfa568f41ce64fe9d844a5999ff2b791c366`.
Statisch gelesen; weder installiert noch ausgeführt oder verändert. Alle folgenden
Pfade liegen im Archiv unter `WorldOfOldcraft-build-kit/`.

| Archivstelle | Übertragenes Prinzip | Anpassung für dieses Kit |
|---|---|---|
| `KIT_README.md:7–28`; `Docs/TASK.md:3–5` | Vollständiges Paket; WHAT/HOW getrennt | README, TASK, WORKFLOW, Entscheidungen, Prüfplan und Start-/Statusunterlagen |
| `Docs/TASK.md:21–71,220–238` | Ein vollständiger nutzbarer Pfad mit Prioritäten und Prüfungen | Gesamte Projektregion → Nahansicht → Gesamtübersicht; kein unvollständiger Teilbereich als Endlieferung |
| `CLAUDE.md:7–16,25–29` | Dauerhafter Zustand statt Gedächtnis | STATUS und versionierte Entscheidungen/Belege |
| `CLAUDE.md:31–49` | Eindeutige Aufgaben- und Ressourcenbesitzer | Hauptagent koordiniert; ausführende und prüfende Subagents mit abgegrenzten Aufträgen |
| `Docs/TASK.md:234–250`; `Docs/PIPELINE_LESSONS.md:110–115` | Feste Prüfsichten, reale Bilder plus Ergebnisprobes, unabhängige Review | Reproduzierbare Kamera-/Zoompfade und geografische Fixpunkte mit Mess- und Bildbelegen |
| `CLAUDE.md:61–72`; `Docs/PIPELINE_LESSONS.md:112–115` | Herkunft und ehrliche Statusstufen | Datenversionen, technische Belege und Nutzerbewertung getrennt |
| `Docs/KICKOFF.md` | Start-/Wiederaufnahme-/Abschlussvorlagen | Vorlagen für späteren Nutzerstart; keine durch Lesen ausgelöste Umsetzung |

Nicht übertragen wurden der Unity-/Windows-/MMO-Auftrag, dessen Figuren/Assets,
Installer, konkrete Tool-/Modell-/Budgetvorgaben, Hooks, Befehle zum Umgehen von
Berechtigungen, „niemals fragen/stoppen“, automatische Wiederanlaufschleifen und
plattformabhängige Performancevorgaben. Archivinterne Anweisungen gelten für das
fremde Beispielprojekt. Die hiesigen WORKFLOW-Schritte sind eine eigene
methodische Anpassung, keine behaupteten Nutzerentscheidungen im Detail.

## Stil- und Zoomreferenzen

- **Primärreferenz ist das vom Nutzer bereitgestellte Landschaftstriptychon** in
  [STYLE_GUIDE](references/STYLE_GUIDE.md). Es setzt Palette, Materialwirkung und
  Detaildichte und ersetzt die frühere zu voxelartige Terrainvorgabe. Urbek bleibt
  nachrangiger Formkontext; keine Assets extrahieren.
- **Victoria 3 / EU5:** Nutzerreferenzen für Weltkarten- und kontinuierliches
  Zoomgefühl, nicht für fotorealistische Materialien, konkrete Implementierung
  oder bestätigte technische Leistungsdaten. Nutzerlink zu Victoria 3:
  [PC Gamer](https://www.pcgamer.com/victoria-3-review/).
- **Neu enthalten und visuell geprüft:** [sechs echte Steam-Galerie-Screenshots](references/screenshots/README.md)
  mit Originaldateien, Entwickler-/Publisherangaben, Abrufdatum, direkten URLs,
  Hashes und konkreter Zuordnung zu K03–K12. Die Galerieherkunft ist geprüft;
  eine technische Laufzeit-/Engineanalyse wurde nicht vorgenommen. Die Bilder
  belegen insbesondere keinen stufenlosen Zoom und keine globale Geografie.
- [Maschinenlesbare Screenshot-Provenienz](references/screenshots/sources.json):
  Quellenrolle `style`, keine Produktionsassets oder geografischen Eingabedaten.

## Eigene Bildproben: genaue Einordnung

### Nutzer-Primärreferenz

Die vom Nutzer bereitgestellte Primärreferenz und ihre Sichtung stehen im
[Landschafts-Stilguide](references/STYLE_GUIDE.md) inline. Das Quellenmanifest
bindet die unveränderte portable PNG-Kopie an SHA-256, Bytegröße, PNG-Abmessungen,
Farbformat und knappe Attachment-Provenienz. Keine Stilabbildung belegt gemeinsame
Geografie, kontinuierlichen Zoom, historische 117/180-Geometrie oder eine
Kartenmaske. Das Bild verändert weder Gesamtregion noch ADM2-Auswahlmethode.

**Supersession, 25.10.2026:** Frühere eigene generierte Stadt-, Zoom-, Fernkarten-
und blockige Nahansichtsproben wurden aus Kit-Dateien, Quellenmanifest,
aktuellem Inventar und aktiven Stilreferenzlinks entfernt, nachdem der Nutzer die
beigefügte Primärreferenz als maßgeblich festgelegt hatte. Die privaten
Originaldateien außerhalb des Kits sind davon unberührt. Die drei offiziellen
Urbek-Referenzbilder bleiben als ausdrücklich nachrangige
Quellenreferenzen erhalten. Eine auf Basis der Primärreferenz erzeugte Fernprobe
wurde als Stil-/Farbkontext akzeptiert, aber ausdrücklich nicht als flacher
Fernkartenendpunkt. Eine neue Nahprobe wurde abgelehnt und aus dem Kit entfernt.

## Grundlage des späteren historischen Korrekturbedarfs

Im Gespräch wurden folgende Quellen zur Einordnung der Unterschiede zwischen
heutiger und antiker Landschaft recherchiert. Sie sind Beispiele für konkrete
Korrekturfälle, kein vollständiges weltweites Rekonstruktionsdatenset:

- [Geoarchäologische Untersuchung zu Ostia](https://eprints.soton.ac.uk/417654/):
  historische Veränderungen im Raum Tiberdelta/Ostia.
- [Deltares: paläogeografische Karten](https://www.deltares.nl/en/expertise/projects/time-traveling-in-the-netherlands-paleo-maps):
  Veränderungen niederländischer Küsten- und Landschaftsformen.
- [USGS: Landsat-Veränderungsbeispiel Staudamm](https://www.usgs.gov/media/images/landsat-change-pair-dam):
  moderne künstliche Änderungen an Gewässern.

Für tatsächliche Datenkorrekturen müssen jeweils konkrete Quelle, Zeitstand,
Abdeckung und Unsicherheit neu geprüft werden. Die Entscheidung für heutige
Geodaten wurde vom Nutzer getroffen, nicht aus diesen Quellen als technische
Pflicht abgeleitet.

## Vollständiger operativer Abgleich (v2)

[REFERENCE_MAP.json](REFERENCE_MAP.json) inventarisiert jeden Archiveintrag mit
Hash, begründeter Übertragung/Ersetzung/Auslassung und existierendem Ziel.
[REFERENCE_MAP.md](REFERENCE_MAP.md) fasst die Kategorien zusammen. Die früher
fehlenden operativen Prozesse sind jetzt als lokale Rezepte, Vorlagen, Verträge
und getestete Kitwerkzeuge vorhanden. Die fremden Implementierungen selbst
werden weiterhin nicht übernommen. Produktive Renderer-/Daten-/Captureadapter
bleiben spätere Spielarbeit; vorbereitete Verträge sind keine implementierten
Runtimefunktionen.

## Nutzerakzeptanz der sechs echten Referenzbilder

Nach Darstellung aller sechs Bilder samt Übernahme-/Nichtübernahmehinweisen im
Chat akzeptierte der Nutzer diese Referenzen am 25.10.2026. Die Zuordnung im
Screenshotkatalog ist damit bestätigt. Die spätere Produktgrafik und ihr
Laufzeitverhalten bleiben unabhängig davon unimplementiert und ungeprüft.

## Kostenbewusster Agentenworkflow

**Status:** `erforscht` als Grundlage, `spezifiziert` als eigene Arbeitsregel;
geprüft am 25.10.2026. Das Abrufdatum bezeichnet die Recherche, nicht ein
behauptetes Veröffentlichungsdatum. Die Quellen begründen allgemeine
Aufwandsregeln, keine feste Modell-ID, Preise, Einsparquote oder ein Budget.

- [ChatGPT pricing](https://learn.chatgpt.com/docs/pricing): aktuelle Hinweise
  empfehlen präzise Prompts, nur relevantes Quellenmaterial, passende Ausgabeform
  und die Trennung notwendiger Arbeit von optionalen Verbesserungen. Die Seite
  unterscheidet Plan-/Credit-Nutzung und API-Key-Nutzung; daraus wird hier keine
  Umrechnung von ChatGPT-Limits in API-Tokens oder USD abgeleitet.
- [Model selection](https://developers.openai.com/api/docs/guides/model-selection):
  Modell und Reasoning-Aufwand an Aufgabe und benötigte Qualität anpassen; ein
  kostengünstiges Modell ist nur dann die richtige Wahl, wenn es ausreichend ist.
- [Cost optimization](https://developers.openai.com/api/docs/guides/cost-optimization):
  notwendige Requests und Tokens begrenzen und ein kleineres Modell verwenden,
  wenn Genauigkeit gewahrt bleibt.
- [Prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching):
  API-Caching hängt von passendem Präfix, Modell und Gültigkeitsregeln ab. Es ist
  keine garantierte Codex-/ChatGPT-Funktion, die dieses Kit konfigurieren kann.
- [Agents API: observability and usage](https://developers.openai.com/api/docs/guides/agents-api/observability):
  API-Taskkosten können Eingaben, Tools, Verlauf, Reasoning, Subagents und
  Wiederholungen umfassen. Diese API-Beschreibung erlaubt keine Schätzung des
  Verbrauchs eines konkreten ChatGPT-Abonnements.

Die projektspezifische Anwendung steht in [WORKFLOW](WORKFLOW.md), im
[Startprompt](START_PROMPT.md) und in [ASSIGNMENT](templates/ASSIGNMENT.md).
Sie bewahrt alle maßgeblichen Nutzerentscheidungen, Qualitätsziele und nötigen
Reviews; Kostenregeln erlauben weder übersprungene Abnahmen noch falsche
Kostenangaben. Keine dieser Quellen wird als Veröffentlichung im Oktober 2026
bezeichnet.

## Unsichtbare Tile-Erweiterung

Die neueste Nutzerentscheidung vom 25.10.2026 behält quadratische logische Tiles,
beschränkt Kit 1 aber auf **eine natürliche Landschaftsansicht ohne GUI**. Drei
Darstellungsweisen/Planung/Themen bleiben später. Die akzeptierte Stil-/Geografie-
referenz bleibt gültig; interne Tile-ID-Stabilität braucht eigene Belege.

## Wissenschaftliche Generalisierungsgrundlagen

[GEODATA_METHODS](references/GEODATA_METHODS.md) führt die akzeptierten Methodenquellen mit Nutzen und Grenzen. Diese Ergänzung stammt aus der aktuellen Recherche, nicht aus dem MMO-Referenzarchiv; keine Fremdsoftware oder Paperbilder werden gebündelt.

## Moderne Auswahlhilfe: geoBoundaries gbOpen ADM2

**Status:** `erforscht` als Dokumentationsgrundlage, Stand 25.10.2026. Diese
Metadaten-Stichprobe prüft keine heruntergeladene Geometrie und wählt keine
Projektfeatures aus. In der offiziellen [API-Dokumentation](https://www.geoboundaries.org/api.html)
ist ADM2 die zweite subnationale Ebene. Einheitengröße und Bedeutung sind nicht
global einheitlich; Metadaten weisen je Layer unter anderem Jahr, Quelle,
Ursprungslizenz, Layer-ID und Geometrie-URLs aus. `current` ist ein beweglicher
Endpunkt, daher muss ein später genutzter Datenstand separat festgehalten werden.

Stichprobe am 25.10.2026: der offizielle [GBR gbOpen ADM2 API-Datensatz](https://www.geoboundaries.org/api/current/gbOpen/GBR/ADM2/)
meldete `boundaryID` `GBR-ADM2-9080712`, `boundaryYearRepresented` `2019`,
`boundaryCanonical` `Counties and Unitary Authorities`, Quelle `Office for
National Statistics Open Geography Portal`, Ursprungs-Lizenz `Open Government
Licence v3.0`, sowie `admUnitCount` `216`. Die ausgegebenen Geometrie-URLs
verwiesen auf geoBoundaries-Commit `9469f09`. Das ist eine zeitgebundene
API-Beobachtung, keine Garantie des späteren aktuellen Stands und keine Aussage,
dass diese Einheiten durchgehend britischen Counties entsprechen oder eine
Grenze für England/nördlichen Kontext festlegen.

Die geoBoundaries-Projektseite empfiehlt [gbOpen](https://geoboundaries.org/api.html)
als offene Variante und nennt CC BY 4.0 mit Attribution; maßgeblich für einen
einzelnen Layer bleibt dennoch dessen `boundaryLicense`/`licenseSource`.
Beispiel GBR zeigt eine quellseitige OGL-v3-Lizenz. Die [Projekt-Lizenzdatei](https://github.com/wmgeolab/geoBoundaries/blob/main/LICENSE)
weist außerdem darauf hin, dass einzelne Datendateien durch die in ihren
Metadaten genannten Lizenz(en) geregelt sind. Für attribution siehe auch die
offizielle [geoBoundaries-Webseite](https://www.geoboundaries.org/).
