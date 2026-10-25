# Vorbereitung und Werkzeugbindung

Referenz: `kit1-landscape-v5`. Diese Vorbereitung installiert nichts. Das Kit
selbst benötigt Python 3.9+ und ausschließlich die Standardbibliothek. `python3`
ist die Schreibweise für macOS/Linux; auf Windows kann `py -3` verwendet werden.
Es gibt keine `pip`-Abhängigkeiten und keine erforderlichen API-Schlüssel.

## Sofort benutzbare Kit-Werkzeuge

Vom Kit-Verzeichnis aus:

```sh
python3 tools/kit.py self-check
python3 -m unittest discover -s tests -v
python3 tools/kit.py preflight templates/config.json
python3 tools/kit.py init-run /tmp/kit1-run-001
python3 tools/kit.py validate report /tmp/kit1-run-001/report.json
python3 tools/kit.py report-check /tmp/kit1-run-001
```

`self-check` prüft das Paket, nicht die Landschaft. `preflight` und
`report-check` liefern derzeit absichtlich Exitcode **2 (offen/blockiert)**:
Renderer, Daten und tatsächliche Laufzeitbelege existieren noch nicht.
Exitcode **1** bezeichnet einen Format-/Integritätsfehler, **0** eine erfolgreiche
jeweilige Kit-Prüfung. Kein Befehl startet einen Renderer oder lädt Daten herunter.
`init-run` erzeugt nur einen neuen Protokollordner und verweigert Überschreiben.

## Erst nach späterem Umsetzungsauftrag

1. Vorhandene Hostumgebung lesen und dokumentieren: OS/Architektur, Python,
   verfügbare Rust-Toolchain, Grafikfähigkeiten, Aufnahmeoptionen. Keine geheimen
   Umgebungsvariablen ausgeben; nichts automatisch installieren.
2. In `TECHNICAL_DECISION.md` Grafik-/Geodatenwerkzeuge anhand TASK vergleichen:
   Abdeckung des gesamten Projektgebiets, konsistente Projektion und Maßstabsabbildung, Zoompräzision,
   Detailwechsel, Datenlizenz, Mac-Erstprüfung und spätere Zielplattformen.
   Windows und Linux sind gewünschte spätere Desktop-Versionen, außerhalb
   dieses Schritts; iPad bleibt optional. Eine begründete
   Auswahl treffen, keine bereits beantworteten Gestaltungsfragen neu stellen.
3. `templates/config.json` in den Arbeitsbereich kopieren; gewählte Namen,
   Versionen, Argumentlisten und tatsächliche Arbeitsverzeichnisse eintragen.
   `null` bedeutet ungebunden, niemals einen impliziten Standard.
4. Datenmanifest und Fixture konkretisieren; technische Grenzwerte mit Begründung
   **vor** Messungen versionieren. Grenzwerte sind technische Entscheidungen,
   keine vom Nutzer vorgegebenen Zahlen.
5. Gebundene Werkzeuge einzeln anhand bestehender Berechtigungen prüfen. Falls
   eine notwendige neue Installation außerhalb der Autorisierung liegt, genau
   diese Abhängigkeit benennen. Keine globale pauschale neue Freigaberunde.
6. Preflight erneut ausführen, fehlende Bindungen bearbeiten. Den echten Build
   erst im späteren Produktauftrag implementieren; dieses Kit hat keinen Build.

| Oberfläche | Kit-Werkzeuge | Späterer Produktnachweis |
|---|---|---|
| macOS | Python-Standardbibliothek, hier tatsächlich geprüft | Erstprüfung auf benanntem Mac; Grafikadapter noch offen |
| Windows | Kit-Werkzeuge portabel vorgesehen, nicht hier OS-geprüft | spätere Produktversion gewünscht; Runtime, Hardware und Abnahmekriterien offen |
| Linux | portable Werkzeuge vorgesehen, nicht hier OS-geprüft | spätere Produktversion gewünscht; Runtime, Hardware und Abnahmekriterien offen |
| iPad/Swift | kein SDK/Setup Bestandteil dieses Kits | optionaler späterer Zielpfad, keine Kit-1-Leistungszusage |

Kein `.claude`-/MCP-Installationszwang. Rollen und Prozessrezepte funktionieren
anbieterunabhängig; konkrete Connectoren werden später im Adapterprotokoll
gebunden. Kein Stop-Hook, Permission-Bypass oder unbegrenzter Resume-Loop.

Die technische Auswahl bindet zusätzlich `config.tiles`: Raster-ID, Revision
und gehashtes Adressierungs-/Naht-/LOD-Verfahren. Diese Grundlage bleibt unsichtbar.
Keine GUI-Frameworkwahl, Modusumschaltung, Auswahl oder Themenquelle ist dafür
verlangt. Die noch ungebundene Rastergröße ist technische Ausarbeitung, kein
Grund für einen neuen Grundsatzfragenkatalog. Siehe [TILES](TILES.md).

Weiterhin [GENERALIZATION](GENERALIZATION.md) beachten: flache Fernkarte → gebundene räumliche Nahansicht, echte Zwischenzustände und A16-Ableitungsbelege. Keine GUI oder umschaltbaren Modi.

## Gebietsbindung v5

Vor Verarbeitung [REGION](REGION.md) lesen und `config.region_path` binden.
Die tatsächliche Regiondatei gehört gehasht zum Report; A02 verbindet sie mit
Coverage. Fixture und Ableitung referenzieren dieselbe Revision. Umfang ist
Reichsrahmen 117 + gesamter Mittelmeerraum + England/nördlicher Kontext, nicht
die gesamte Erde und nicht nur Europa. Landschaftsreferenz bleibt 180 n. Chr.
