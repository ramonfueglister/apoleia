# v4: datenbasierte Modellwelt und Karten-Diorama-Übergang

> Historischer Prüfstand. Aktueller geografischer Umfang: [REGION_SCOPE_UPDATE](REGION_SCOPE_UPDATE.md).

25.10.2026 · `kit1-landscape-v4` / `kit1-ops-v4`.
Status: Anforderungen und Belegverträge `spezifiziert`; Kitänderungen implementiert,
unabhängige Wiederprüfung abgeschlossen. Keine Produktimplementierung.

Die jüngste Nutzerentscheidung präzisiert drei bisher unvollständig erfasste Punkte:

1. Flache 2D-Fernkarte → kontinuierliche gebundene räumliche Nahansicht; keine
   durchgehend konstante Kameraelevation, freie Drehung, Modi oder GUI.
2. Tatsächlich verkleinerte realdatenbasierte Modellwelt mit weniger Kleindetails;
   gemeinsame Skalierung, keine willkürliche Überhöhung/Distanzverkürzung.
3. Wissenschaftliche Generalisierung mit Quellenqualitätsnachweis, Fehlerbudgets,
   geschützten geografischen Strukturen und ehrlicher Begrenzung von Genauigkeit.

Neu: Methodenreferenzen, operativer Generalisierungsprozess, `geodata_policy` und
`derivation`, aktualisierte Kamera-/Fixture-/Telemetrieverträge und A16. A16 ist
Geoableitung, kein reaktivierter Themenmodus. Alle alten No-GUI-/unsichtbaren
Tile-Grenzen bleiben erhalten. Die ältere v3-Tileprüfung ist historisch unter
[TILE_UPDATE](TILE_UPDATE.md) dokumentiert und validiert nicht automatisch v4.

Automatische Kitprüfungen bewerten Belegverträge/Hashes und berichtete Zahlen,
nicht die Wahrheit der Quelldaten, den historischen Zustand von 180 n. Chr. oder
visuelle Produktqualität. Konkrete Technik, Datenbestände, Skalen und Toleranzen
sind noch ungebunden und Teil des späteren Umsetzungsauftrags.

Eigene Prüfung: 38/38 Kit-Tests und sieben CLI-Läufe mit erwarteten Exitcodes
(siehe evidence/kit-checks.json → geodata_update). Preflight und ungestarteter
Report bleiben mangels tatsächlicher Runtime-/Datenbindungen blockiert. Die
unabhängige Wiederprüfung ist abgeschlossen; das finale Paket wird anschließend
mit Manifestprüfung und separatem Bytevergleich zum Arbeitsstand erzeugt.

Unabhängiger Abschlussreview: keine offenen Befunde; 38/38 Tests, Selbstprüfung,
Nullbestand-Topologietest und vollständiges 70-Dateien-Inventar bestätigt.
Der Befund gilt ausschließlich für Kitverträge und Dokumentkonsistenz. Er
bestätigt keine reale Geoableitung, Runtime-Darstellung oder historische Genauigkeit.
