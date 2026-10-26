# Vollständige Übertragung des Referenzarchivs

`REFERENCE_MAP.json` ist das vollständige Dateiinventar des unverändert statisch
gelesenen Archivs (224 Einträge). Jeder Eintrag besitzt eine begründete Disposition
und existierende Zielpfade. 'Ersetzt' bedeutet eigene passende Umsetzung des
Arbeitszwecks, nicht Portierung fremden Codes oder automatische Produktfreigabe.

| Referenzgruppe | Angepasster Ersatz |
|---|---|
| WHAT/HOW/Kickoff/Lessons | TASK, WORKFLOW, KICKOFF, operations und Vorlagen |
| Durable state/Compact-Hook | STATUS plus PLAN/PROGRESS/HANDOFF; manuelle belegte Wiederaufnahme |
| Stop-Hook/Permission-/Autonomieeinstellungen | bewusst ausgelassen; keine neuen Stop- oder Berechtigungsregeln |
| Skill-/Toolrouting | ROLES, SETUP, ADAPTER; aufgabenspezifische Daten-/Stilrezepte, keine installierten Skills |
| Bild-/3D-Produktion | STYLE_PIPELINE, Quellen-/Assetprovenienz; keine Charakter-/Animationsassets |
| Historische Projekterfahrungen | VERIFY_CAPTURE, RECOVERY, isolierter Reimport; keine Unity-spezifischen Behauptungen |
| Installer/MCP/env/Abhängigkeiten | portable stdlib-Kitwerkzeuge, explizite später zu bindende Konfig; keine Installation |
| Capture/Timelapse | reproduzierbarer Echtzeit-Capturevertrag, Report-/Telemetrieformat, Evidence-Hashprüfung |
| Assets/Concepts/MMO-Referenzen | fremde Inhalte nicht übernommen; ergänzt durch [echte Urbek-Quellenreferenzen](references/screenshots/README.md) sowie Nutzer-Primärreferenz und eingeschränkte Fernstilprobe |
| Projekt-Handoffs | eigene Handoff-/Review-/Defekt-/Abschlussvorlagen |
| Inhaltsinventar | vollständige REFERENCE_MAP und selbst erzeugtes Paketmanifest |

Operativ geliefert werden Kitprüfwerkzeuge und konkrete Verträge/Vorlagen.
Renderer, Datenkonverter und Runtime-Captureadapter sind absichtlich **nicht**
implementiert: das wäre Produktarbeit. Ihre erforderlichen Ein-/Ausgaben und
Bindungsschritte sind vollständig vorbereitet; fehlende Bindungen bleiben im
Preflight sichtbar blockiert. Das Kit ist kein bereits startbares Landschaftsprodukt.

Die unsichtbare Tile-Erweiterung v3 ist eine neue Nutzerentscheidung, keine unentdeckte
Originalkit-Anweisung. [TILES](operations/TILES.md), der zusätzliche Belegvertrag
und [START_PROMPT](START_PROMPT.md) konkretisieren den eigenen Arbeitsauftrag;
die 224 Originaleinträge und Quellenhashes bleiben unverändert.

## Stilreferenz-Ergänzung

Die nutzerbereitgestellte Primärreferenz ist eine Kit-Ergänzung, kein Eintrag des
Originalarchivs. Ihre Rangfolge, Provenienz und Ausschlüsse stehen im
[STYLE_GUIDE](references/STYLE_GUIDE.md) und `references/images/sources.json`;
Originalarchiv-Inventar und -Hashes bleiben unverändert. Frühere eigene
Generierungen sind aus Kitdateien, Quellenmanifest, aktuellem Inventar und aktiven
Bildlinks entfernt; private Originale außerhalb des Kits bleiben unberührt. Eine
aus der Primärreferenz abgeleitete Fernstilprobe ist mit eingeschränkter
Nutzerakzeptanz aufgenommen; die abgeleitete Nahprobe wurde verworfen und entfernt.

## Ergänzung v4

[Geoableitung](operations/GENERALIZATION.md), Methodenquellen und deren Policy-/Belegverträge erweitern Daten-/Prüfprozesse für die aktuelle Nutzerentscheidung. Sie sind eigene Kitbestandteile und keine zusätzlichen Einträge des unveränderten Originalarchivs.

Die v5-Gebietspräzisierung ergänzt [REGION](operations/REGION.md) samt gebundenem
Regionvertrag. Es handelt sich um die Anpassung desselben WHAT-/Coverage-Pfads,
nicht um zusätzliche Dateien des unveränderten Referenzarchivs.
