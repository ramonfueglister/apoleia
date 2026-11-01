# Verona als Referenz für S136

Stand: 31.10.2026. **Implementiert, nach Ramons Qualitätskritik gestalterisch überarbeitet**,
noch nicht von Ramon abgenommen. Begrenzte Referenzstadt, keine vollständige historische
Rekonstruktion und keine Umstellung aller Städte.

## Was umgesetzt ist

Sechs eigene Voxelmodelle in `app/scripts/voxel/verona_landmarks.gd`, am selben
Diorama-Massstab wie die Wohnhäuser. Die Fläche folgt
`100 * (Realfläche / 100)^(1/3)`; das Seitenverhältnis bleibt erhalten.
Höhen bis 16 m bleiben unverändert, darüber gilt `16 * (Realhöhe / 16)^(1/3)`.
Geometrie, Türen, Bogenöffnungen, Säulen und 0.5-m-Sitzstufen werden auf dem
0.25-m-Voxelraster neu gebaut. Kein gestrecktes Einparzellenmodell.

| Bau | Ausgangsmasse L × B × H (m) | Regelmodell L × B × H (m) | Evidenz / Ergänzung |
| --- | --- | --- | --- |
| Arena | 152.4 × 123.2 × 31 | 26.6 × 21.5 × 19.9 | Grundriss und rekonstruierte Höhe belegt; drei Arkadengeschosse. |
| Theater | 109 × 71 × 24 | 25.6 × 16.7 × 18.3 | Caveadurchmesser belegt, Tiefe aus Bauuntersuchung; **Höhe angenommen**. Zwei Galerien und obere Loggia. |
| Capitolium | 35 × 42.2 × 18 | 14.3 × 17.2 × 16.6 | Podiumabmessungen belegt; **Höhe angenommen**. Drei Cellae, Pronaos mit drei Reihen à sechs Säulen. |
| Forum | 56.5 × 168 × 4 | 12.4 × 36.8 × 4 | Platzmasse belegt; **Portikushöhe angenommen**. |
| Basilika | 27.5 × 78 × 20 | 9.9 × 28.1 × 17.2 | Belegtes Areal als Gebäudehülle angenähert; **Aufriss und Höhe angenommen**. |
| Therme | 70 × 55 × 16 | 20.7 × 16.3 × 16 | Baugattung in Hanson erfasst; **Lage, Masse und Form typologisch**, kein identifiziertes Bad rekonstruiert. |

Die Tabelle beschreibt die mathematische Hülle. Rasterrundung, Sockel und
Gesimse treten stellenweise bis etwa 0.75 m darüber hinaus. Die Parzellen
reservieren den ganzen Modellraum einschliesslich Rand, sodass der Renderer
kein Verona-Modell verkleinern muss. Die Arena wird vollständig für die
Spielzeit dargestellt, nicht als heutige Ruine. Circus und Odeum sind in
diesem Referenzschritt nicht gebaut; der Circus-Eintrag der Grunddaten wird
nicht ungeprüft als gesicherter Bau übernommen. Die Grunddaten selbst bleiben
unverändert.

## Stadtplan und Grenzen

`data/cities/plans/verona.json` übernimmt das bisherige **generierte**
Strassen- und Mauerschema. Es ist ausdrücklich kein vermessener Plan von 301.
Die näherungsweisen Anker der erhaltenen Monumente dienen der Platzsuche;
die grossen Blöcke dürfen wie bisher bis sechs Parzellen je Achse ausweichen.
Das neue, explizite `landmark_preserve_housing` hält den kleinen Wohnkern frei.
Wasser, Mauern, Tore und andere Bauten bleiben bei der Platzsuche gesperrt.

Das bewahrt acht Wohnparzellen und zeigt alle sechs öffentlichen Bauten,
verschiebt aber insbesondere Forum und Capitolium deutlich gegenüber der
historischen Lage. Die Flussseite und die räumliche Beziehung dieser Bauten
sind deshalb **nicht historisch validiert**. Vor einer historischen
Stadtrekonstruktion braucht es eine eigene, abgestimmte Lösung für den Konflikt
zwischen vergrösserten Wahrzeichen, Fluss und kleinem Wohnkern. Geodaten,
Flussverlauf und Gelände wurden für diese Referenz nicht verschoben.

Sitzplätze bleiben leer. Es gibt noch keine Anbindung der Gebäudebesuche an
die Bevölkerung; dekorative Figuren würden eine solche Anbindung vortäuschen.
Der Faktor 566.5 wird deshalb noch nicht zur Erzeugung eines Publikums benutzt.
Theaterterrassen, der Tempel auf dem Hügel und die genaue Gallienus-Mauer
sind ebenfalls nicht rekonstruiert.

## Technische Integration

- Stadtplan-Bake reserviert vollständige Mehrparzellenblöcke und schreibt
  explizite, nur für Verona zugelassene Modellnamen in die Metadaten.
- Meshcache und bestehende LODs werden weiterverwendet. Sechs zusätzliche
  MeshInstances für die Referenz; noch kein globales MultiMesh-System.
- Die acht Shaderplätze für abgeflachte Wahrzeichenblöcke werden aus den
  Blöcken innerhalb des aktuellen Geländeausschnitts gefüllt. Ein Wechsel
  Verona → Rom → Verona aktualisiert die Auswahl auch ohne LOD-Wechsel.
  Das Acht-Block-Limit bleibt bestehen und ist kein System für alle Städte.
- Andere Stadtdaten und das Simulationsmodell bleiben unverändert. Veronas
  Wohnplatzdatei wird zusammen mit dem Stadtatlas neu erzeugt.

## Quellen

Abgerufen am 31.10.2026; Befunde und eigene Modellannahmen oben getrennt.

- Regione del Veneto, Università di Padova & Soprintendenza per i Beni
  Archeologici del Veneto. (2010). *Anfiteatro romano “Arena” – Verona*.
  [ArcheoVeneto, 73](https://archeoveneto.beniculturali.unipd.it/stampe/stampa_scheda_estesa.php?recid=73).
- Dieselben. (2010). *Teatro romano – Verona*.
  [ArcheoVeneto, 69](https://archeoveneto.beniculturali.unipd.it/stampe/stampa_scheda_estesa.php?recid=69).
- Dieselben. (2010). *Capitolium presso il Ristorante “Maffei” – Verona*.
  [ArcheoVeneto, 74](https://archeoveneto.beniculturali.unipd.it/stampe/stampa_scheda_estesa.php?recid=74).
- Cavalieri Manasse, G. (1997). *Verona*. Enciclopedia dell’Arte Antica.
  [Treccani](https://www.treccani.it/enciclopedia/verona_%28Enciclopedia-dell%27-Arte-Antica%29/).
- Università degli Studi di Padova. (o. J.). *Identificazione strutturale del
  Teatro Romano di Verona mediante monitoraggio statico e dinamico*, S. 15.
  [Bauuntersuchung](https://files01.core.ac.uk/download/pdf/41985804.pdf).
  Autor/Jahr hier noch nicht bibliografisch geprüft; für 71 m Tiefe benutzt.
- Hanson, J. W. (2016). *An urban geography of the Roman world, 100 BC to
  AD 300*. Archaeopress. Projektimport `data/cities/facts.json`,
  `Hanson2016_1065` (Verona); keine neue Prüfung des gesamten Datenbankeintrags.

## Reproduzieren

Mit NumPy und Pillow in einer lokalen Python-Umgebung:

```sh
python tools/city_plans.py --scale 1 --bake artifacts/render-data/city-plans-r1
python -m unittest discover -s tools/tests -p test_verona.py
```

Reale Spielmeshes neben demselben 13.3 m hohen Wohnhaus, gemeinsame
orthografische Kamera mit 35° Neigung aus Nordosten:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path app --script res://scripts/debug/verona_preview.gd -- --out=/absolute/path/verona-models.png
```

Spielansicht: `--view=10.999,45.442,6`. Prüfprotokoll und Aufnahmen:
[Verona-Prüfung](../handover/verona/validation.md).

## Detailüberarbeitung nach Qualitätskritik

Der erste Stand (`026d3db`) wurde von Ramon als zu wenig detailliert
zurückgewiesen. Das vorangegangene interne «ship»-Urteil war keine
Nutzerabnahme und traf den geforderten gestalterischen Anspruch nicht.

Die Überarbeitung betrifft die sechs Modelle, nicht Stadtplan, Simulation,
Massstabsformel oder die Modelle anderer Städte:

- Arena: gleichmässige Bogenjoche entlang der Ellipse, Rundbögen mit
  Archivolten, kräftigere Pfeiler, Kämpfer und Gesimse, ringförmige
  Geschossdecken und auch innen klar gegliederte Galerien; Podium,
  Sitzreihen, Treppenstreifen, Umgang und überdeckte Hauptzugänge.
- Theater: ausgearbeitete Galerien und Loggia; zwei Säulenordnungen,
  Gesims und Nischen auf der bühnenzugewandten Wand; gegliederte Rückseite.
- Capitolium: gestufter Sockel, Basen/Kapitelle, Gebälk, rückseitige
  Cella-Gliederung, Giebelakzent, Dachrand und Antefixe.
- Forum: Plattenfugen, eingefasste Portiken mit Rückwänden und Sockelband;
  ausgearbeiteter Statuensockel.
- Basilika: Türrahmungen, gegliederte Stirnseiten, Fenster und Dachränder.
- Therme: gewölbter Hauptraum, niedrige Seitenflügel, thermale Fenster,
  Stützglieder und Gesimse, Wasserbecken und Umgang statt einer hohen
  leeren Halle mit Satteldach.

Farbwechsel und Ziegelrelief wurden bewusst beruhigt, damit Bauteile
ablesbar bleiben. Dekor, innere Verkehrsführung und der thermale Aufriss
sind eigene gestalterische Rekonstruktionen, keine neu belegten Details.
Die bestehende Palette und 0.25-m-Voxelsprache bleiben erhalten.

Die Vorschau unterstützt jetzt einen direkten Vergleich aus Nordost und
Südwest (35°) sowie eine höhere Kontrollansicht (55°). Der alte Code wird
nur als ausdrücklich übergebene lokale Vergleichsdatei geladen:

```sh
git show 026d3db:app/scripts/voxel/verona_landmarks.gd > /tmp/verona-before.gd
/Applications/Godot.app/Contents/MacOS/Godot --path app --script res://scripts/debug/verona_preview.gd -- --compare=theatre --before-code=/tmp/verona-before.gd --out=/absolute/path/theatre-compare.png
```
