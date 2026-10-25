# Startprompt für einen neuen Chat

**Kit:** `kit1-landscape-v5` / `kit1-ops-v5`. Der Text startet die Umsetzung erst
bei bewusstem Absenden als Nutzerauftrag. Speichern oder Lesen führt ihn nicht aus.
Im Projekt `vic3-clone` verwenden; bei Weitergabe den entpackten Kitordner bereitstellen.

```text
Setze jetzt das vollständige Kit 1 um. Dies ist mein ausdrücklicher Startauftrag
für Implementierung, nicht nur für weitere Planung oder Dokumentation.

Arbeite im Projekt vic3-clone. Maßgeblich ist docs/kit1/README.md samt vollständigem
Kit. Das portable Ersatzpaket liegt unter artifacts/kit1-build-kit.zip. Falls nur
dieses vorliegt, prüfe es und entpacke in einen neuen Ordner, ohne bestehende Arbeit
zu überschreiben. Das ursprüngliche WorldOfOldcraft-Archiv ist Referenzmaterial;
führe dessen Installer und Befehle nicht aus.

Dieser Startauftrag ersetzt „Umsetzung nicht gestartet“ und „keine Spielimplementierung“
im Dokumentstatus. Die ältere Wirtschaftsphase in AGENTS.md ist nicht der aktuelle
Scope. Die übrigen Rollen-, Herkunfts- und Arbeitsregeln gelten weiter.

ZIEL UND JÜNGSTE SCOPEENTSCHEIDUNG
Geografischer Umfang: zusammenhängender Bezugsrahmen des Römischen Reiches bei
seiner größten Ausdehnung um 117 n. Chr., der gesamte Mittelmeerraum samt Land-/
Meerkontext und ausdrücklich England plus zusätzlicher Raum nördlich davon.
Nicht nur Europa/EU, nicht die ganze Erde, nicht nur Rom. Die Abdeckung enthält
auch Britannien/Gallien/Iberien, Donauraum/Dakien, Nordafrika und die östlichen
Reichsgebiete gemäß belegter Abgrenzung. Kein harter Clip an Imperialgrenzen.
Landschaftsreferenz bleibt 180 n. Chr.; Datenbasis bleibt heute. Binde die drei Quellgeometrien mit Extent, CRS, Feature-IDs und Revision;
Coverage muss dieselben Referenzen und Maskenrevision verwenden. Begründe vor
Verarbeitung die konkrete Abgrenzung, Quellen, Kartenmaske und Puffer in region.json
gemäß operations/REGION.md. Kein ungefragter Maßstab oder Städtemengenwechsel.

Orientiere die moderne Teilgebietsauswahl bevorzugt an geoBoundaries gbOpen ADM2.
ADM2 ist nicht länderübergreifend eine einheitliche Gebietsgröße und keine
historische Grenze. Dokumentiere pro gewähltem Feature dessen tatsächliche
Quell-ID und Namen getrennt von der Layer-`boundaryID`, außerdem ISO3, ADM-Level,
Quellenjahr/-quelle, Layer-ID, Lizenz/Attribution, festen Release-/Commitstand,
Datei-URL und SHA-256. Wähle Features erst bei der späteren Datenarbeit; vereinige
sie mit begründetem Land-/Nordpuffer und dem vollständigen Mittelmeer-Wasserraum
zur Projektmaske. Die ADM2-Auswahlhilfe erzwingt weder eine finale harte
Verwaltungsgrenze noch ganz Schottland für den nördlichen England-Kontext.

Liefere eine tatsächlich startbare natürliche Landschaft der gesamten Projektregion mit
flacher 2D-Fernkarte, Schwenken und stufenlosem, zoomgebundenem Übergang in die
isometrische 3D-Diorama-Nahansicht für später mehrere Häuser mit Umfeld. Keine einzelne Regionaldemo,
Rom-Demo oder Bildserie als Endergebnis.

Es gibt in diesem Schritt GENAU EINE Landschaftsansicht und KEINERLEI GUI:
keine Menüs, Buttons, Toolbars, HUD, Infofenster, Statuspanels, Legenden oder
Bildschirmhilfen; kein sichtbares Raster, keine Tile-Auswahl/Highlights, keine
Planungs-/Themenansicht und keine Modusumschaltung. Bedienhinweise gehören in die
externe Startanleitung. Pan/Zoom werden direkt bedient. Interne Teststeuerung
und Datenprobes bleiben unsichtbar und erzeugen keine zusätzlichen Ansichten.

Quadratische logische Tiles bleiben ausschließlich unsichtbare Datenstruktur/Basis.
Dokumentiere Rastergröße, Adressierung, Quellgeografiebezug, Projektion, Naht-/Kartenrandregeln
und LOD-Zuordnung begründet. IDs müssen beim Pan/Zoom stabil bleiben. Küsten, Flüsse
und Terrain müssen nicht Tilekanten folgen. Quadratisch gilt im logischen Raum,
nicht als unverzerrtes Bildschirmquadrat oder global gleich große Kugelfläche.
Drei Ansichten, Planung, Auswahl, Themenfarben und Fruchtbarkeits-/Bodenanwendungen
sind nur spätere Ziele: jetzt nicht bauen, auch nicht als versteckte Modi.

Heutige Geodaten bilden die Basis; historische Korrekturen für 180 n. Chr. werden
getrennt für später dokumentiert. Baue eine tatsächlich verkleinerte Modellwelt,
nicht bloß eine kleine Anzeige sämtlicher Originaldetails. Alle Landschaftsformen
werden aus realen versionierten Quellen abgeleitet. Kleine Details dürfen nach
dokumentierten Regeln entfallen; keine frei erfundene Geografie, willkürliche
Distanzverkürzung oder Höhenüberhöhung. Quellraum, gemeinsam skalierter Modellraum
und zoomgebundener Renderraum bleiben getrennt nachvollziehbar. Kamera/Projektion/
Relief dürfen dem festen Zoomprofil folgen; keine freie Kameradrehung. Flache Karte
und Diorama sind Endpunkte derselben Ansicht, keine umschaltbaren Modi.

Nutze die wissenschaftlichen Grundlagen aus references/GEODATA_METHODS.md und
operations/GENERALIZATION.md. Begründe Algorithmus-/Projektionswahl statt alle
Papers oder CGAL zwingend zu implementieren. Lege Skalenfaktor, Qualitätsbudgets,
Feature-Schutz und Stichproben vor Messung fest. Nachweisbare Herkunft bedeutet
keine fehlerfreien Messdaten oder überall unverzerrte flache Weltkarte. Unbekannte
Daten/Quellqualität offenlegen, nicht durch Fantasielandschaft auffüllen.

Stil: Maßgeblich ist die Nutzer-Primärreferenz in references/STYLE_GUIDE.md:
stilisierte nicht-fotorealistische Landschaft, zurückhaltende natürliche Farben,
lesbare facettierte Geländeformen, detaillierte Waldgruppen und natürliche
Übergänge. Nicht zu bunt, nicht übermäßig low-poly/voxelartig/klotzig. Betrachte
die Primärreferenz und ihre Abgrenzungen vor dem Rendering tatsächlich. Die
Fernstilprobe ist eine nachrangige Farbreferenz, kein Beleg für den flachen
2D-Endpunkt; die Nahprobe wurde vom Nutzer verworfen und ist nicht enthalten. Die
sechs offiziellen Screenshots bleiben Quellenkontext und dürfen
die Primärreferenz nicht überstimmen. Kein Stilbild belegt gemeinsame Geografie,
historische 117/180-Formen, kontinuierlichen Zoom oder Maskengeometrie. Victoria 3 dient geografischer Übersicht,
nicht als politische oder malerische Material-/UI-Vorlage. Städte, Gebäude, Menschen,
Straßen, Wirtschaft, politische Farben und sichtbare Bewirtschaftungsmuster bleiben
ausgeschlossen. Keine neuen Spielsysteme hinzufügen.

VORGEHEN
Der Hauptagent koordiniert und kommuniziert. Sämtliche inhaltliche Recherche,
Dokumentation, Änderungen, Implementierung und unabhängige Prüfung gehen an klar
beauftragte Subagents. Günstigstes fachlich ausreichendes verfügbares Modell,
mit der niedrigsten fachlich ausreichenden Reasoning-Stufe; Modell-IDs und Preise
nicht festschreiben. Größere oder kritische Aufgaben sowie wiederholte klare
Qualitätsfehler begründen eine rechtzeitige Eskalation, statt eine ungeeignete
Konfiguration in einer Wiederholungsschleife weiterzuverwenden. Delegation nur für
sinnvolle, voneinander unabhängige Teilaufgaben; Arbeit passend bündeln und
relevante Worker weiterverwenden. Aufträge und Übergaben enthalten nur nötigen
Kontext und ein begrenztes Ergebnisformat. Eindeutiger Dateibesitz und genau ein
Besitzer gemeinsam genutzter Anwendungssitzungen. Keine weiteren Nutzerchats anlegen.

Arbeite ressourcenschonend bei unveränderten Qualitäts- und Abnahmezielen: bereits
akzeptierte Daten- und Bildreferenzen wiederverwenden; keine ungefragten Varianten,
Zusatzrecherchen oder optionalen Feinschliff-Schleifen. Lies maßgebliche Anweisungen
immer und wiederhole keine ganze Kit-Lektüre. Nutze aktuelle Status-/Prüfbelege;
Kit-Integritäts- und Volltests einmal je Kitversion und Umgebung als Baseline,
später gezielt betroffene Prüfungen. Bei Code-/Vertragsänderung, unklarer
Abhängigkeit oder relevantem Risiko bleiben vollständiger Retest und unabhängige
Prüfung erforderlich. Keine Qualitätsgates aus Kostengründen streichen.

Lies AGENTS.md und je zuständigem Owner decisions, TASK, WORKFLOW, ACCEPTANCE
und STYLE_GUIDE einmal; danach relevante Rollenverträge und Änderungen.
Maßgebliche Anweisungen immer lesen. TILE_UPDATE ist historisch v3;
FINAL_AUDIT ist der historische v2-Audit. Führe self-check beim Start/Packen und
nach Kitdatei- oder Inventaränderung aus:
python3 tools/kit.py self-check

Führe die Volltests einmal pro Kitversion und Umgebung aus, wenn kein passender
Beleg vorliegt; nach Code-/Vertragsänderung oder relevanter Unsicherheit erneut:
python3 -m unittest discover -s tests -v

Führe Preflight bei erstmaliger Bindung oder Änderung der Konfiguration aus:
python3 tools/kit.py preflight templates/config.json

Lege gemäß Werkzeughilfe mit init-run einen neuen Laufordner außerhalb des Kits an.
Ein zunächst blockierter Preflight bedeutet ungebundene Technik, keine fehlende
Nutzerfreigabe für diesen Auftrag. Wähle Grafiktechnik, Daten, Mapping, internes
Raster und Testparameter aus den Anforderungen und dokumentiere Gründe/Grenzen.
Stelle bereits geklärte Fragen nicht erneut. Verwende vorhandene Werkzeuge und
notwendige projektlokale Abhängigkeiten innerhalb der Autorisierung. Keine
ungefragten globalen Installationen, SDK-Änderungen, kostenpflichtigen Dienste oder
Veröffentlichungen. Berechtigungsgrenzen respektieren.

Kit, Dokumentation, Tests und spätere Produktquellen werden im privaten GitHub-
Repository [ramonfueglister/romaaeterna](https://github.com/ramonfueglister/romaaeterna)
versioniert. Konto, Owner und private Sichtbarkeit sind geprüft. In diesem
Repository weiterarbeiten und keine zweite Ablage anlegen. Bei späterer Umsetzung Quellen,
reproduzierbare Konfiguration/Lockfiles, relevante Tests und freigegebene Referenzen
mit Provenienz einpflegen; Commits regelmäßig, klein und inhaltsklar. Pushes nur zum
bestätigten Ziel, nie zu fremden Remotes oder per Force-Push. Keine ungeprüften
Rohdaten-/Cache-/Build-/Tempbestände oder Secrets committen. Eine startbare App kann
bei passendem Auftrag als Release-Artefakt beigefügt werden; dieser Startauftrag
veröffentlicht kein Release.

Führe M0–M4 bis zum Gesamtergebnis durch. Interne Prototypen ersetzen die gesamte regionale
Lieferung nicht. Fortschritt und Wiederaufnahmepunkte festhalten; keine neuen
Freigabegates und kein Stopp nach einem bloßen Plan. Echte Blocker benennen, Erfolg
nicht vortäuschen, keine automatischen Endlosschleifen.

PRÜFUNG UND LIEFERUNG
Verwende kit1-ops-v5 und alle A01–A16. Belege gebietsweite Quellenrollen/NoData,
Kamera-/Viewport-/Mappingzustände, tatsächlich gefahrenen Pan/Zoom/Rückkehrpfad
und interne kanonische Tile-Zuordnung einschließlich Nähten/Kartenrändern. A16 liefert
quellengebundene Generalisierungs-Rohmesswerte, Budgets und Topologienachweise.
Die ungeschnittene Zoomfahrt muss flachen Fernzustand, tatsächliche Zwischenzustände
und räumlichen Nahzustand samt Rückkehr im selben Build zeigen.
Echte Laufzeitbilder und kontinuierliche Zoomaufnahme zeigen ausschließlich die
natürliche Landschaft ohne GUI/Overlays/andere Modi. Prüfdaten stehen extern.
Lass Bilder, Rohmessungen und Belege unabhängig prüfen und Fehler beheben.
A02 bindet region.json, die drei geografischen Abdeckungskomponenten und England
samt nördlichem Puffer. Weltweite Pol-/Datumsgrenzprüfungen sind keine Pflicht.
Kit-Tests, Referenzbilder und Mockdaten sind keine Produktnachweise.

Erstprüfung auf Mac; iPad bleibt optional. Windows- und Linux-Versionen sind
ausdrücklich gewünschte spätere Produktziele, aber nicht Teil dieses Auftrags.
Rust-Kern, Hostadapter und Renderer portabel trennen; Metal ist optionaler Apple-
Pfad und GPU-Fähigkeiten sind zur Laufzeit abzufragen. Die Integration in die
Nutzer-App auf Godot-Basis bleibt offen; kein Projekt/keine Runtime ist vorhanden.
Der frühere Mittelklasse-PC-Satz bleibt historischer Kontext ohne Leistungszusage.
Tatsächliche Testhardware und ungeprüfte Plattformen ehrlich
nennen. Liefere startbare Anwendung,
reproduzierbare Startbefehle/externe Bedienanleitung, Quellenmanifest, echte Bild-/
Videobelege, Messwerte und ehrliche Bewertung aller A01–A16. Beginne danach keine
weiteren Kits. Starte jetzt mit Kit 1.
```
