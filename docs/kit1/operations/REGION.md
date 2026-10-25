# Projektgebiet: Reichsrahmen, Mittelmeer und nördlicher England-Kontext

`kit1-landscape-v5` / `kit1-ops-v5`. Nur die geografische Begrenzung ändert sich.
Keine Spiel-/GIS-Implementation und keine neue Tilegröße, Skalierung oder Stadtzahl.

## Moderne Gebietsauswahlhilfe

Für die Auswahl moderner Teilgebiete ist geoBoundaries **gbOpen ADM2** die
bevorzugte, reproduzierbar bindbare Orientierung. ADM2 bezeichnet laut
geoBoundaries die zweite subnationale Ebene. Das ist keine weltweit einheitliche
Gebietsgröße oder Rechts-/Verwaltungskategorie: Zuschnitt, Benennung, Anzahl,
Quellenjahr und Lizenz sind je Layer zu prüfen. ADM2-Polygone helfen bei der
Auswahl einer modernen räumlichen Hülle; sie behaupten weder historische Grenzen
von 117 oder 180 n. Chr. noch Simulationsregionen. Sie sind keine Pflicht zu
einer scharf an Verwaltungsgrenzen endenden finalen Cutline.

Für einen späteren Lauf können ausgewählte ADM2-Features als Auswahlanker
dokumentiert, vereinigt/aufgelöst und mit begründetem Land-/Nordpuffer sowie dem
gesamten Mittelmeer-Wasserraum zur Projektmaske ergänzt werden. Die genaue
Featureauswahl, Pufferbreite, Meeresbehandlung und endgültige Maske bleiben
offen, bis die Daten konkret gewählt und geprüft sind. Insbesondere lässt sich
„England plus nördlicher Kontext“ durch die Auswahl und einen begründeten Puffer
abbilden; eine Auswahl ganz Schottlands ist daraus nicht automatisch abzuleiten.
Die Projektregion bleibt der verbindliche Scope aus diesem Dokument. ADM2-Grenzen
werden nicht als politische Darstellung in der Landschaft gezeichnet und
definieren keine Tilegrenzen.

Bei der Bindung Herkunft und Auswahl auseinanderhalten:

- `boundaryID` bezeichnet den geoBoundaries-Layer, nicht ein ausgewähltes
  Teilgebiet. Für jedes tatsächlich gewählte Feature dessen im Quelldatensatz
  vorhandenen Identifier **und** Namen genau so erfassen, wie die Quelldatei sie
  ausweist; keinen globalen Feldnamen für Feature-IDs voraussetzen.
- Zusammen mit dem Feature-Identifier erfassen: Feature-Name, ISO3,
  `boundaryID`, ADM-Level, `boundaryYearRepresented`, `boundarySource`,
  `boundaryLicense`, `licenseSource`, Release/API-Abfrage, zugrunde liegenden
  Git-Commit oder andere festgelegte Quelldatenrevision, Quelldatei-URL,
  heruntergeladene Datei-SHA-256 und Attribution. `gbOpen`-Projektlizenzangabe
  allein ersetzt nicht die pro Layer ausgewiesene Ursprungs-Lizenzprüfung.
- Einen beweglichen `current`-API-Endpunkt nicht als eingefrorene Datenausgabe
  behandeln: spätere Datenarbeit muss konkreten Datenstand/Commit und Geometrie-
  Hash binden. Der gehashte Auswahl-/Maskenstand gehört anschließend in die
  vorhandene `region.json`-Quellen- und Maskenbindung.

Die ausfüllbare [Auswahlnotiz](../templates/REGION_SELECTION.md) ist eine
Arbeitsvorlage ohne Schemaänderung oder zusätzliche Validatorpflicht. Eine
offizielle API-Stichprobe und ihre Grenzen sind in [REFERENCES](../REFERENCES.md)
festgehalten.

## Verbindlicher Umfang

- Geografischer Bezugsrahmen ist die größte Ausdehnung des Römischen Reiches
  unter Trajan um **117 n. Chr.**, einschließlich seiner nördlichen, westlichen
  und östlichen Gebiete; keine reine Mittelmeerküstenkarte.
- **Der gesamte Mittelmeerraum** mit Wasserflächen, Inseln, Küsten und verbundenem
  Land-/Meerkontext gehört dazu. Nordafrika und die östlichen Reichsgebiete dürfen
  nicht durch eine Europa-/EU-Begrenzung verloren gehen.
- **England vollständig und zusätzlicher Raum nördlich davon** gehören ausdrücklich
  dazu. Nicht am römischen Britannienrand abschneiden. Die Breite des nördlichen
  Puffers ist vor Datenverarbeitung begründet festzulegen; kein ungefragter Auftrag
  für ganz Skandinavien oder eine bestimmte zusätzliche Inselgruppe.
- Ergebnis ist eine **zusammenhängende** erkundbare Karte mit räumlichem Kontext
  über Reichsgrenzen hinaus. Das historische Reichspolygon ist Referenz, keine
  harte Ausschneidemaske von Land ohne Meeresverbindungen.
- Landschaftsreferenz bleibt **180 n. Chr.**; heutige Geodaten bleiben die Basis.
  Der 117er Gebietsrahmen ändert nicht den Spielzeitpunkt und beweist keine
  historisch exakte Landschaft. Keine politische Grenzvisualisierung hinzufügen.

Der zwischenzeitlich genannte Europa-Umfang wurde vom Nutzer ausdrücklich ersetzt.
Ebenso gilt die vorherige gesamte Erde nicht mehr. Ein isoliertes Rom-/Italien-
oder Teilmittelmeer-Demo ist keine vollständige Lieferung.

## Vor Verarbeitung binden

`config.region_path` zeigt auf `region.json`. Dies enthält:

- feste Scope-ID, 117er Bezugsjahr und getrenntes Landschaftsreferenzjahr 180;
- Revision, CRS EPSG:4326 und erst aus der Datenwahl abgeleitetes begrenztes Extent;
- gehashte Quellen zur maximalen Reichsabgrenzung und zum gesamten Mittelmeer;
- gehashte England-Abgrenzung; deren belegte Nordgrenze und einen positiven,
  begründeten nördlichen Kontextabstand;
- gehashte zusammenhängende Kartenmaske mit `mask_revision` und Vollständigkeitsbeleg;
- je Referenzkomponente `reference_geometries`: ID, Quellen-ID und identischer
  Quellenhash, Geometrierevision, EPSG:4326-Extent sowie tatsächliche Feature-IDs;
- gewählte Grenzkonventionen/Unsicherheiten sowie Meeres- und Randkontextpolitik.

Extent ist nur die Hülle. Die tatsächliche Kartenmaske und ihre Kontextregeln
müssen das geforderte Gebiet abdecken. Ein Rechteckname oder ein bestandener
Schemascheck beweist weder historischen Grenzverlauf noch Vollständigkeit.
Reichsgebiete und Mittelmeer nach derselben dokumentierten Quellkonvention
vergleichen; strittige Grenzen kennzeichnen. Kein vorab erfundener Kartenzuschnitt.
Die Größenrechnung von rund fünf Millionen km² Reichsland ist **keine** Vorgabe
für die Kartenfläche: Meer, Zwischenräume und Puffer kommen hinzu.

Als historischer Überblick nennt die [National Library of Australia](https://www.library.gov.au/learn/digital-classroom/medium-aevum-middle-age/imperium-romanum-roman-empire)
117 n. Chr. und rund fünf Millionen km². Diese gerundete Angabe ersetzt keine
Grenzgeometrie und wird nicht zur Tile-/Maßstabsregel. Einzelne spätere Grenzbauten
sind kein Beleg für den exakten Zustand von 117.

## Coverage, Zoom und interne Tiles

- Coverage bindet exakt die Regiondatei/Revision/Extent. `reference_components`
  belegt separat `imperial_maximum_extent`, `entire_mediterranean` und
  `england_and_northern_context`. Jeder Eintrag benötigt vollständige deklarierte
  Repräsentation und tatsächliche gehashte Abdeckungsbelege. Komponente, Quellen-ID,
  Quellenartefakt, Referenzrevision und Maskenrevision müssen exakt zur Regiondatei
  passen. Der Kartenextent muss alle drei quellabgeleiteten Referenzextents enthalten;
  die England-Nordkoordinate muss mit dem England-Referenzextent übereinstimmen.
  Für England beschreibt das Referenzextent England selbst; der zusätzliche
  Nordpuffer wird anschließend aus `north_context_degrees` geprüft.
- Land- und Meeresdomänen, ihre Quellenrollen sowie NoData-Behandlung gelten
  innerhalb der Kartenmaske. Jeder Quelllayer muss nicht überall vorliegen;
  bestehende Regeln für Komposite und natürliche Landbedeckung bleiben erhalten.
- Regionale Kartenränder, Küsten-/Land-Wasser-Übergänge und interne Tile-/Datenblatt-
  nähte ersetzen die früheren weltweiten Pol-/Datumsgrenzpflichten. Prüfanker
  innerhalb des gebundenen Extents mit Quelle/Feature-ID dokumentieren.
- Fixture und Ableitung sind an dieselbe Regionrevision gebunden. Bei Ausschnitts-
  änderung Belege neu erzeugen; keine alten Weltbelege als regional bestanden
  umbenennen. A02 referenziert Region und Coverage.
- Überblick → Nahansicht → Überblick bleibt ein kontinuierlicher, gebundener
  Kamerapfad ohne GUI, Rasteranzeige oder weitere Darstellungsmodi.

Die Kitwerkzeuge prüfen Struktur, Zahlen-/Hash-/Revisionsbindungen und deklarierte
Abdeckung. Sie lesen keine historischen Grenzpolygone aus und validieren nicht
selbst, dass jeder verlangte Küstenabschnitt enthalten ist. Die unabhängige
Daten-/Bildprüfung muss tatsächliche Quellgeometrie, Masken und Vollständigkeit
kontrollieren. Die Vorlage bleibt ungebunden; kein Datenbestand wird vorgetäuscht.

Die Referenzextents sind Metadaten der gewählten Quellfeatures, keine hier
vorgegebenen historischen Koordinaten. Ein Zahlenvergleich erkennt eine zu enge
Kartenhülle bei korrekt gebundenen Metadaten; falsche Metadaten oder Löcher im
Maskeninneren erkennt erst die unabhängige Geometrieprüfung.
