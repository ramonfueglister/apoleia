# Kit 1 — Arbeitsweise (HOW)

**Referenzversion:** `kit1-landscape-v5` · **Status:** `spezifiziert`.  
Diese Arbeitsweise ist aus dem Referenzkit angepasst, kein Auftrag zur sofortigen
Umsetzung. Die Herkunft und die nicht übernommenen Regeln stehen in
[REFERENCES.md](REFERENCES.md).

## Rollen und Autorisierung

- Der Hauptagent koordiniert und kommuniziert. Inhaltliche Recherche,
  Dokumentation, Dateiänderungen, Implementierung und unabhängige Prüfung werden
  ausschließlich klar beauftragten Subagents zugewiesen.
- Jeder Auftrag nennt Ergebnis, erlaubte Dateien/Ressourcen, Prüfschritt und
  Grenzen. Für eine gemeinsam geöffnete Editor-/Renderer-Sitzung gibt es jeweils
  genau einen zuständigen ausführenden Subagent; keine konkurrierenden Änderungen.
- Kostenbewusstes Arbeiten ist verbindlich, bei unveränderten Qualitäts- und
  Abnahmezielen: das aktuell günstigste fachlich ausreichende verfügbare Modell
  und die niedrigste ausreichende Reasoning-Stufe wählen. Modell-IDs und Preise
  nicht festschreiben. Komplexität, Kritikalität oder wiederholte klare
  Qualitätsfehler rechtfertigen eine rechtzeitige Eskalation mit Grund; ungeeignete
  Konfigurationen nicht durch blinde Wiederholungen weiterverwenden.
- Entscheidungen aus [decisions.md](decisions.md) nicht erneut abfragen.
  Ausführungsdetails innerhalb des Auftrags begründet lösen. Neue wesentliche
  Zielkonflikte offen benennen; nicht eigenmächtig Scope oder Nutzerpräferenzen
  ersetzen. Keine ungefragten Superpowers-Workflows oder Freigabegates.
- Aktuell Kit-Dokumente, Vorlagen, Verträge und lokale Kit-Prüfwerkzeuge bearbeiten; keinen Spiel-/Renderer-Code. Nach einem späteren Umsetzungsstart gelten
  dessen Umfang und bestehende Autorisierungen. Keine Pakete, SDKs, globalen
  Änderungen, kostenpflichtigen Dienste oder weiteren Plattformziele aus dem
  fremden Kit als bereits genehmigt behandeln.

## Übernommenes Arbeitsprinzip

Zuerst den vollständigen Erkundungspfad zum Laufen bringen, dann seine grafische
Qualität erhöhen. Einzelne schön gerenderte Ausschnitte ersetzen diesen Pfad
nicht. Jeder Arbeitsschritt liefert etwas konkret Prüfbares, visuell und durch
Messwerte. Ein unabhängiger Prüfagent beurteilt die Belege; der Ersteller allein
vergibt keine unabhängige Bestätigung.

## Ressourcenschonende Ausführung

- Hauptagent bleibt Koordinator; inhaltliche Arbeit und unabhängige Prüfung werden
  wie festgelegt an Subagents vergeben. Delegiere begründete, unabhängige
  Teilaufgaben und bündele zusammengehörige Arbeit, statt jeden Mikroschritt als
  eigenen Auftrag oder Agentenlauf anzulegen. Parallelisierung kann Latenz senken,
  garantiert aber keine geringeren Modellkosten. Vorhandene passende Worker mit
  relevantem Kontext weiterverwenden.
- Jeder Auftrag nennt knapp Ziel, relevante Entscheidungen/Dateien, Pfade,
  Ressourcenbesitz, Grenzen, Prüfschritt und erwartetes Ergebnis. Gib nur
  erforderlichen Kontext weiter; auf unterstützten Hosts kann ein neuer Worker
  ohne vollständige Verlaufskopie starten. Ergebnisse sollen gezielt auf Dateien,
  Zeilen und konkrete Befunde verweisen, nicht umfangreiche Logs oder das ganze
  Kit duplizieren. Maßgebliche Anweisungen und einschlägige Belege bleiben Pflicht.
- Pro verantwortlichem Owner die maßgeblichen Entscheidungen, TASK, WORKFLOW,
  ACCEPTANCE und STYLE_GUIDE einmal lesen; danach nur benötigte Rollenverträge und
  den Delta seit dem letzten gültigen Stand. STATUS und geprüfte Artefakte zur
  Wiederaufnahme nutzen. Akzeptierte Bild-/Datenreferenzen wiederverwenden; keine
  ungefragten Bildvarianten, Zusatzrecherchen oder optionalen Polish-Schleifen.
- Kit-Integrität und Volltests einmal pro Kitversion/Umgebung als dokumentierte
  Baseline ausführen. Danach Umfang und Abhängigkeiten der Änderung prüfen und
  angepasste Zieltests wählen. Bei Code-/Vertragsänderungen, unklarer Abdeckung
  oder relevantem Risiko vollständige nötige Tests und unabhängige Prüfung
  durchführen; klare Fehler und fehlende Abnahmebelege gezielt beheben. Kosten
  rechtfertigen nie das Streichen notwendiger Qualitäts- oder Abnahmeprüfungen.
- Toolaufrufe auf den benötigten Befehl begrenzen und unabhängige Lese-/Prüfschritte
  parallel ausführen, wenn das praktisch hilft; dies ist eine Latenzentscheidung,
  keine garantierte Kostensenkung. API-Prompt-Caching nur dort annehmen, wo die
  eigene API-Nutzung es tatsächlich steuert. Keine Caching-, Batch- oder Flex-
  Verfügbarkeit für Codex/ChatGPT behaupten oder Einstellungen ändern, um sie
  zu erzwingen. Abonnementsverbrauch und API-Abrechnung getrennt behandeln:
  keine Umrechnung, Prozentersparnis, Credits, Limits oder USD-Beträge erfinden.
  Kosten nur mit verfügbarer Messung dokumentieren; sonst `nicht erhoben`.

## GitHub und reproduzierbare Versionen

- GitHub ist der Versions- und Ablageort für Kit, Dokumentation, Tests und spätere
  Produktquellen. Das gebundene Ziel ist das private Repository
  [`ramonfueglister/romaaeterna`](https://github.com/ramonfueglister/romaaeterna);
  Login, Owner, Existenz und private Sichtbarkeit wurden geprüft. Nur dieses
  Repository verwenden. Vor jedem Push Ziel und Branch prüfen; nie zu fremden
  Remotes oder per Force-Push schreiben.
- Im gebundenen Repository Versionen, benötigte Dependency-Manifeste und
  Lockfiles, nicht geheimhaltungsbedürftige Beispielkonfiguration, Start-/Build-/
  Prüfkommandos, Quellenmanifeste und geprüfte Dokumentation einchecken. IDs und
  Versionen der tatsächlich verwendeten Tools, Dependencies und Daten reproduzierbar
  festhalten; Konfigurationsvorlagen ohne Zugangsdaten halten. Keine Secrets,
  temporären Logs, Caches oder unaufgeforderten Build-Ausgaben einchecken.
- Große Rohdatensätze nur nach notwendiger Bindung an Projektumfang, Lizenzmetadaten
  und praktikable Repositorygröße aufnehmen. Wenn sie das Repository unnötig
  aufblähen, stattdessen reproduzierbare Quellen-/Versions-/URL-/Hash-/Transformations-
  manifestdateien ablegen und Daten im Setup abrufen. Akzeptierte Referenzen nur
  samt Provenienz und den für die Veröffentlichung nötigen Lizenzmetadaten führen;
  vor Veröffentlichung technisch auf Quelle, Metadaten, Scope und Paketinhalt prüfen.
  Das ist eine technische Prüfung, keine Rechtsfreigabe.
- Während der Umsetzung regelmäßig kleine, inhaltsklare Commits mit passenden
  Prüfbelegen vorbereiten. Push nur zum ausdrücklich gebundenen Ziel-Repository;
  nie zu fremden Remotes und nie per Force-Push. Ein App-/Kit-Archiv kann als
  Release-Artefakt passen; erstelle oder veröffentliche kein Release ohne konkreten
  Auftrag. Lokale GitHub-Prüfungen, Commits oder Uploads nicht als erledigt melden,
  wenn sie nicht tatsächlich ausgeführt wurden.

## Interne Schritte des späteren Gesamtauftrags

Diese Schritte sind eine Arbeitsgliederung, keine neuen Nutzerfreigaben und kein
Vorschlag, nur einen regionalen Prototyp zu liefern.

| Schritt | Ergebnis | Nachweis vor dem nächsten größeren Ausbau |
|---|---|---|
| M0 Technische Ausarbeitung | Vorhandene Umgebung prüfen; Datensatz-/Versions-/Lizenzwahl, Maßstabsabbildung, unsichtbare quadratische Tile-Adressierung, Stack, Detail-/Ladeverfahren und reproduzierbare Testkonfiguration begründen. [`RENDERING`](operations/RENDERING.md) konkretisieren; dortige Zielbudgets sind Vorschläge, bis Hardware und Szenario gebunden sind. | Entscheidungen und Risiken nachvollziehbar dokumentiert, kein behaupteter Testlauf ohne Laufzeit |
| M1 Gesamter Erkundungspfad | Gesamte Projektregion zusammenhängend, gebundener flach-zu-Diorama Übergang, Verschieben und kontinuierlicher Zoom bis Nahbereich; gemeinsame unsichtbare Tile-Grundlage, keine GUI oder zusätzlichen Modi; zunächst einfache Darstellung möglich | Echte Prüffahrt Gesamtübersicht → nah → Gesamtübersicht, eindeutige geografische Bezugspunkte, Abdeckung belegt |
| M2 Einheitliche Landschaft | Terrain, Gewässer, regionale natürliche Farben und Vegetation nach Nutzer-Primärreferenz; facettierte, ausreichend detaillierte Landschaft statt extremer Low-Poly-/Voxeloptik; Detailübergänge | Vergleichbare Aufnahmen plus Geografie-/Zoom-/internen Tileprobes aus derselben Daten- und Darstellungsrevision |
| M3 Robustheit und Leistung | Fehler der Übergänge, räumliche Instabilität, Datenlücken und Leistungsprobleme bearbeiten | Reproduzierte Grenzfälle und reale Messungen auf dokumentierter Umgebung; unabhängige Prüfung |
| M4 Gesamtergebnis | Startbare Lieferung, Startanleitung, vollständige Prüffahrt, Quellenmanifest und Abschlussbericht | ACCEPTANCE vollständig bewertet; offene Punkte und nicht geprüfte Plattformen klar genannt |

Der Pfad bleibt nach Integration prüfbar. Fehler am Kernpfad haben Vorrang vor
zusätzlicher Dekoration. Das fertige Ergebnis endet bei Kit 1; nicht automatisch
Städte, Spielsysteme oder weitere Kits beginnen.

## Dauerhafter Stand und Wiederaufnahme

[STATUS.md](STATUS.md) bleibt die knappe Einstiegsseite: Referenzversion, aktuelle
Arbeit, erledigte Ergebnisse, offene Defekte, Belegpfade und nächster Schritt.
Bei späterer Umsetzung werden technische Entscheidungen mit Datum/Begründung,
Datensatzversionen und die Prüfläufe dort verlinkt; umfangreiche Messdaten dürfen
in getrennten Ergebnisdateien liegen. Keine widersprüchlichen parallelen TODOs.

Nach Unterbrechung maßgebliche Anweisungen sowie STATUS und letzte relevante Belege
lesen. Laufende Jobs anhand ihrer Kennung prüfen; ein Timeout ist kein Beweis für
einen fehlgeschlagenen Job. Keine blinden Wiederholungen, automatischen
Endlosschleifen oder Manipulation von Limits. Bevor ein Ergebnis als aktuell gilt,
Daten-/Buildversion und mögliche Änderungen seit dem letzten Test prüfen.

Statuswerte gemäß Projekt: `offen`, `erforscht`, `spezifiziert`, `implementiert`,
`validiert`. Ein Status gilt nur für benannten Umfang und Referenzversion.
Eine bestandene technische Prüfung ist keine Nutzerfreigabe der visuellen
Gestaltung; diese wird nur aus tatsächlichem Nutzerfeedback übernommen.

## Herkunft, Daten und Nachweise

- Nutzerentscheidungen, eigene technische Festlegungen, Quellenbefunde und
  Hypothesen getrennt kennzeichnen. Keine fremden Spielmechaniken behaupten.
- Für jeden verwendeten Datensatz Quelle, Version/Stand, Abdeckung, Auflösung,
  Lizenz/Nutzungsbedingungen, Transformationen und bekannte Lücken dokumentieren.
- Bei Datenaufbereitung moderne Gebäude-/Straßen-/Politikdarstellungen ausschließen.
  Historische Geländeabweichungen separat als späteren Korrekturbedarf erfassen.
- Kein Paradox-Code, keine kopierten Spielskripte oder Assets in Produktcode.
  Das Referenzkit wird nicht ausgeführt oder als Lizenz-/Assetfreigabe behandelt.
- Nur tatsächlich geöffnete Laufzeitbilder beurteilen. Konzeptbilder belegen Stil,
  keine geografische Korrektheit, Zoomfunktion oder Leistung.
- Kosten, Zeit und Leistung nur nennen, wenn gemessen; fehlende Messung heißt
  „nicht erhoben“, nicht null. Keine erfundenen Benchmarks oder globalen Genauigkeitswerte.
