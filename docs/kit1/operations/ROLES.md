# Auftragskarten und Ressourcenbesitz

Referenz `kit1-landscape-v5`. Anbieterunabhängige Rollenpakete, keine automatisch
installierten Agenten/Skills. Aktuell günstigstes fachlich ausreichendes Modell
und Reasoning-Stufe; qualitätsbegründete Abweichung knapp dokumentieren.

| Rolle | Eigentum / erlaubte Arbeit | Lieferung und Prüfung |
|---|---|---|
| Koordinator | Aufträge, Status, Kommunikation; keine inhaltliche Umsetzung | Scope/Dateibesitz/Abhängigkeiten vergeben, Ergebnisse zusammenführen |
| Daten | Quellinventar, Datenaufbereitung, Abdeckung, historische Korrekturliste | Quellenmanifest + reproduzierbare Schritte + Datenprobes |
| Grafik/Integration | späterer Renderer und alleiniger Besitzer aktiver Editor-/App-Sitzung | kompletter Erkundungspfad + gebundener Adapter + tatsächliche Builds |
| Stil/Vegetation | abgegrenzte eigene Asset-/Materialdateien | integrierte Stilproben, Herkunft, Export-/Reimportbefund |
| Messung/Capture | Fixture/Telemetry/Runordner; Sitzung nur nach Übergabe | wiederholbare Bilder/Video und Rohmessungen, keine Selbstfreigabe |
| Unabhängige Prüfung | liest eingefrorenen Build/Report; keine gleichzeitigen Änderungen | Fehlerliste oder begründeter Befund pro A01–A16 |

Vor jeder Delegation `templates/ASSIGNMENT.md` ausfüllen: Eingaben, Ausgabe,
erlaubte Pfade, Ressourcenbesitz, aktueller Nutzerauftrag, Nachweis, Grenzen.
Parallelarbeit nur bei getrenntem Besitz. Gemeinsame Engine-/Editor-Sitzung hat
einen Driver; Übergabe nennt Projektpfad, Job-ID/PID, Zustand und offenen Vorgang.
Nur sinnvolle, unabhängige Aufgaben parallelisieren; zusammengehörige Arbeit
bündeln und passende vorhandene Worker wiederverwenden. Aufträge auf erforderlichen
Kontext und begrenzte Ausgabe zuschneiden. Parallelisierung kann Latenz senken,
garantiert aber keine Kostenersparnis. Keine Mikroschritt-Delegation zur Auslastung
von Agenten.

Kein Agent ändert während eines laufenden Tests das Harness, den Datensatz oder
die Fixtures. Vor Review Revision einfrieren; nach Fix betroffene Prüfungen mit
neuer Revision durchführen. Fremde Testprozesse nicht beenden, kein blanket kill.
Die aktuelle Aufgabe erstellt Kit-Unterlagen und Hilfswerkzeuge, keine Landschaft.

Die Datenrolle besitzt die unsichtbare Tile-Adressierung und Quellenzuordnung;
Grafik/Integration besitzt ausschließlich natürliche Landschaft, Pan und Zoom.
Messung bindet interne Tile-Probes an Fixture, ohne Raster/GUI/Tile-Auswahl.
Keine neue Rolle für Bauen, Themenansicht oder GUI aus dem Zukunftswunsch ableiten.

Weiterhin [GENERALIZATION](GENERALIZATION.md) beachten: flache Fernkarte → gebundene räumliche Nahansicht, echte Zwischenzustände und A16-Ableitungsbelege. Keine GUI oder umschaltbaren Modi.
