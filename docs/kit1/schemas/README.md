# Maschinelle Verträge und Validatorgrenze

Die zehn `.schema.json`-Dateien sind JSON-Schema-Dokumente für Draft 2020-12.
Der mitgelieferte stdlib-Prüfer ist **kein allgemeiner JSON-Schema-Validator**.
Er prüft das hier verwendete geschlossene Profil: `type`, `properties`,
`required`, `additionalProperties: false`, `items`, `minItems`, `minLength`,
`minimum`, `maximum`, `enum`, `const`, `pattern`, `anyOf` sowie Metadaten
`$schema`/`title`. Andere Keywords werden beim Laden abgewiesen. In diesen
Schemas sind damit alle verwendeten Strukturbedingungen abgedeckt. Boolesche
Werte zählen nicht als Zahlen; NaN/Infinity werden beim JSON-Lesen abgewiesen.

Zusätzlich geprüft: eindeutige IDs, genau A01–A16, monotone Zeitpunkte, gültige
Evidence-/Fixture-Verweise und zweidimensionale Bildkoordinaten. Preflight prüft
Bindungen und Quellenartefakte; Reportprüfung prüft Dateihashes, Revisionen,
synthetische Herkunft, unabhängige Prüferangabe, Rohtelemetrie und Grenzwerte.
Der Prüfer kann weder Bildinhalt verstehen noch eine als echt deklarierte
Messung als tatsächlich echt beweisen. Dafür ist unabhängiges Öffnen der
Laufzeitbelege und Nachvollziehen des Laufs weiterhin nötig. Exit 0 bei
`report-check` bedeutet nur bestandener **Evidenzvertrag**, keine eigenständige
Produktfreigabe. Nutzerbewertung bleibt separat.

Laufkonfig/Manifestpfade relativ zum jeweiligen Konfigordner, Evidencepfade
relativ zum Laufordner. Absolute, aufsteigende und per Symlink ausbrechende
Artefaktpfade werden zurückgewiesen. Das tatsächliche Adapter-Arbeitsverzeichnis
ist separat angegeben und wird nie durch das Kit ausgeführt.

`report.created_utc` ist in einer ungestarteten Vorlage `null`. Ein akzeptierter
Report benötigt einen kalendarisch gültigen UTC-Zeitstempel mit `Z`-Suffix
(`YYYY-MM-DDTHH:MM:SS[.ffffff]Z`). Platzhalter und lokale Zeitstempel werden
abgewiesen; `init-run` trägt den tatsächlichen UTC-Erstellzeitpunkt ein.

## Weitergeführte Auditverträge aus ops-v2

Die damalige Auditkorrektur ergänzte Kamera-/Coverage- und Integritätsverträge.
Sie wurden in ops-v3 um Tile-Felder erweitert und bleiben mit regionaler Gebietsbindung in ops-v5 erhalten.
Alte Laufdateien gelten nicht automatisch als Abnahme der aktuellen Revision.

- `fixture`/`telemetry`: gebundene View-Zustände, Viewport/Pixelraum, Pan-Ziel,
  Transformdatei+Hash, Sollpositionsmethode und tatsächlich erreichte Wegpunkte.
- `coverage`: gebundener regionaler EPSG:4326-Bezugsraum, getrennte Land-/Ozeandomänen,
  Quellen-/Mappingbindung, NoData- und Landcoverbehandlung, Kartenränder/Küsten/Tile-Nähte
  sowie gehashte Aggregations-/Prüfbelege. Leere Templates bleiben strukturell
  gültig, bestehen aber nicht die vollständige Evidenzprüfung.
- `self-check` bindet alle lokalen `references/**/sources.json` an ihre tatsächlichen
  Bilddateien. Fremde Screenshots und eigene generierte Probe werden gleich geprüft.
- `verify-package` prüft bekannte Kitversion, nichtleeres Manifest, Pflichtdateien
  und Übereinstimmung mit dem **eingepackten** KIT_CONTENTS-Inventar zusätzlich zu
  Dateihashes. Das beweist Integrität/Konsistenz, nicht Echtheit des Urhebers.

Coverage-Rollen sind je Domäne an konkrete IDs und Rollen aus sources.json
gebunden: Land braucht elevation/landcover, Ozean water; Spezialregionen binden
Rollen ihrer deklarierten Domänen. Ein gemeinsamer Kompositbeleg ist möglich,
aber eine Wasserquelle kann nicht als Höhen-/Landcoverquelle ausgegeben werden.
`visible_result` muss für mask/abstract/not_present den natürlichen Endzustand
ohne Kultivierungs-/Bebauungsmuster erklären; die Erklärung ersetzt die visuelle
A10-Prüfung nicht. Datensatzklassen und Behandlung bleiben belegt nachzuvollziehen.

## Aktuelle Vertragsrevision `kit1-ops-v5` / Kit `kit1-landscape-v5`

Zehn Schemas einschließlich `region`, `tiles`, `geodata_policy` und `derivation`; alle A01–A16 sind erforderlich. Die
v2-Auditverträge bleiben erhalten. V3 ergänzt nur die **unsichtbare** quadratische
Tile-Grundlage, keine Ansichten-/Themen-/Picking-/GUI-Verträge.

`config.tiles` bindet Raster-ID/Revision/Adressierungsartefakt; `fixture.tile_cases`
legt kanonische IDs, Indizes und mehrere View-Zustände fest. `tiles.json` bindet
interne tatsächliche Probes an diese Zustände und prüft ID-/Index-/Größenstabilität
sowie quadratische logische Zellmaße. Deklarationen erlauben nur eine natürliche
Ansicht ohne GUI, sichtbares Raster und Auswahlhighlight. Aktuelle Prüfungen haben
keine Modusfolge, Legende oder Themenquelle als Eingabe oder Startblocker.

Die Zahlen sind logische Einheiten, keine feste Metergröße oder globale
Flächengleichheitsgarantie. Der Prüfer implementiert keinen Tilealgorithmus.
Korrekte IDs/Probes sind Belegverträge; Adressierungsverfahren, Originaldaten und
tatsächliche Bild-/Laufdaten müssen unabhängig geprüft werden. Details: [TILES](../operations/TILES.md).

`fixture.project_extent`/`region_revision` binden den Gebietsvertrag; interne
Tilefälle prüfen Binnenfläche, Küste, Kartenrand und Tile-Naht. Randnähe wird
gegen das regionale Extent geprüft, Küsten-/Nahtlabel brauchen unabhängige
Quell-/Rasterbelege. Weltweite Pol-/Datumsgrenzfälle sind nicht erforderlich.

## Ops-v4: Kamera und datenbasierte Ableitung

Breaking change: die konstante Kameraelevation aus ops-v3 wird durch gehashte
Zoomprofilbindung mit Far/Near-Endwerten und tatsächlichen Zuständen ersetzt.
Alte Laufdateien dürfen nicht nur umbenannt werden; echte Zwischenzustände und
Ableitungsdaten fehlen dort. A16 ist **Geoableitung**, kein wieder eingeführter
Themen-/GUI-Modus. `geodata_policy` wird vor Verarbeitung/Messung festgelegt;
`derivation` hält die dazugehörigen Rohwerte und Quellen-/Ausgangsartefakte fest.
Toleranzen sind noch offen, Vorlagen bewirken keinen Preflight-Erfolg.

Die festen Metriknamen unterscheiden Meter im Quellraum, Bildschirm-Pixel und
Projektionsverhältnis. Automatisch berechnet wird ausschließlich das Maximum der
mitgelieferten nichtnegativen Stichprobenwerte, kein RMS und keine mathematisch
bewiesene globale Fehlerschranke. Reale Vollständigkeit/Methodenqualität muss ein
unabhängiger Reviewer an Rohdaten, Samplingbelegen und Bildern prüfen.

Optional `derivation.not_applicable[]` (`level_id`, `metric`, `status:
"not_applicable"`, Pflicht `reason`, Pflicht `rule` mit Pfad+SHA-256): nur
`screen_error_px`/`transition_residual_px` für nicht gerenderte Niveaus. Gemessen
und NA zusammen müssen alle Niveau-/Metrikpaare exakt abdecken, ohne Überlappung;
jede Metrik braucht mindestens ein gemessenes Niveau. NA ist kein Nullwert.

## Regionaler Umfang v5

`region` bindet das Projektgebiet nach [REGION](../operations/REGION.md). Konfig,
Fixture, Coverage und Ableitung müssen dieselbe Revision/Datei samt Hash verwenden.
A02 referenziert region-Evidence. Begrenzung und nördlicher England-Puffer sind
vor Messung belegt festzulegen. Vollständigkeit der Referenzpolygone prüft ein
Reviewer anhand der Quellen; Metadaten allein beweisen keine historische Grenze.

Regionale Referenzgeometrien tragen Extent, CRS, Feature-IDs, Quellenartefakt und
Revision. Coverage bindet jede Komponente an genau diese Metadaten sowie die
Maskenrevision; die Hülle muss die Referenzextents einschließen. Das ersetzt keine
unabhängige Prüfung tatsächlicher Quellgeometrie und Maskeninnenflächen.
