# Tile-Gelände (SimCity 2000 auf jeder Zoomstufe)

Status: `implementiert`, seit 27.10.2026 das einzige Gelände der App. Das Wetter
(`app/scripts/weather/`, `app/shaders/weather_*`, `cloud_layer`) ist davon
unabhängig und unverändert.

## Geländeregeln (SimCity 2000)

- Die Welt besteht aus quadratischen Kacheln. Jede **Ecke** hat eine Höhenstufe,
  benachbarte Kacheln teilen ihre Ecken. Dadurch ist das Land eine durchgehende
  Fläche aus flachen Kacheln und Rampen, wie in SimCity 2000 (XTER-Formen
  00–0D: jede Ecke liegt auf der Kachelhöhe oder eine Stufe darüber).
- Benachbarte Ecken liegen **höchstens eine Stufe** auseinander (zwischen
  allen acht Nachbarn, im Bake gesichert).
- Eine Stufe ist **0,6 Kachelbreiten** hoch (SimCity 2000: 12 px Stufe auf einer
  32 × 16 px Kachel).
- Ganz nah (bis etwa 12 km Sichtbreite) sind die Kacheln **Viertel der
  0,5-km-Kacheln** (250 m, `SUB_KM`): eine Kachel trägt ein Haus wie in Urbek
  (Haus und Feldparzelle sind 250 m groß), bei 3 km Sichtbreite stehen 12
  statt 6 Kacheln nebeneinander. Zellen und Landschaften sind die ihrer
  0,5-km-Kachel; die Viertel an der Spitze eines Küsten- oder
  Landschaftsschnitts nehmen das Wasser bzw. die andere Landschaft an, so
  bleibt der Schnitt eine Diagonale. Die Ecken der 0,5-km-Kacheln behalten ihre
  Stufe, eine Ecke dazwischen nimmt die höhere ihrer Nachbarn (am Wasser die
  tiefere, so bleibt das Ufer auf dem Wasserspiegel): Aus jeder 0,5-km-Rampe
  wird ein flaches Viertel auf der oberen Terrasse und eine Viertelrampe
  darunter, drei Viertel der Kacheln sind flach statt knapp die Hälfte, und
  die Hänge stehen als gestapelte Plateaus (Kritik r4: „glatte Dreiecke statt
  Plateaus“). Eine Stufe ist dort so hoch wie bei 0,5 km (`SUB_LEVEL_HEIGHT`,
  1,2 Viertelbreiten), damit die Hügel beim Zoomen ihre Höhe behalten. Ein
  kleiner 2D-Pass (`tile_sub_prep.gdshader`) schneidet Zellen, Landschaften
  und Eckstufen der Viertel einmal je Fensterwechsel in eine Textur
  (`sub_tex`, 1024 × 1024 Viertel um den Ausschnitt).
- Nah (0,5- und 1-km-Kacheln) kommen die Eckstufen aus einem feineren
  Höhenmodell (Terrain Tiles, terrarium Zoom 8, etwa 450 m; `DEM_URL`, im Bake
  zwischengespeichert in `artifacts/render-data/terrarium-z8/`, nicht in Git;
  außerhalb des Regionsrechtecks die 2-km-Höhen): auf den 2-km-Knoten fehlten
  die Hügel weniger Kilometer (Tivoli stand auf 70 statt 235 m, Roms Hügel
  fehlten, das Nahrelief war flach). Die Skala ist im Tiefland fein
  (`NEAR_STEPS_M` bei 0,5-km-Kacheln: 20 m je Stufe bis 120 m, 50 m bis 420 m,
  darüber 120 m; bei 1-km-Kacheln die doppelten Meter; der Shader spiegelt sie
  in `tt_near_level_x`): Roms Gianicolo, Quirinal und Esquilin stehen ein bis
  zwei Stufen über dem Tibertal, Tivoli liegt am Hang über der Campagna, das
  Land um Rom zeigt Terrassen und Rampen wie SimCity 2000. Der Bake
  (`near_corner_levels`) folgt denselben Regeln wie fern, zeichnet aber bei
  0,5 km nur über 1,0 Kacheln weich (bei 1 km wie fern über 1,2 Kacheln) und
  räumt mit 3 × 3 Ecken auf, sonst zerfällt das Land in lose einzelne Rampen
  (bei 22 km) und der Apennin bei 70 km in ein Gewirr einzelner Buckel. Die 0,5-km-Stufen
  sind für eine Textur zu groß (20646 Ecken breit): das Skript schneidet ein
  Fenster von 1024 × 1024 Ecken um den gezeichneten Ausschnitt heraus
  (`_update_level_window`, `levels_origin`).
- Fern (ab 2-km-Kacheln) kommen die Eckstufen aus dem Bake (`levels-L*.png`,
  `corner_levels`) auf einer steigenden Skala (`LEVEL_STEPS_M`: 0, 1, 2, …
  Stufen bei 100 / 250 / 450 / 700 / 1000 / 1300 / 1600 / 1900 / 2200 /
  2500 / 2900 / 3400 m, darüber 600 m je Stufe; der Shader spiegelt sie in
  `tt_far_level_x`): Tiefland eine Stufe, Hügel zwei, der Apennin ein Rücken
  aus drei bis fünf Stufen, die Alpen sechs bis acht (gleiche Stufen
  zeichneten in den Hügeln ein Labyrinth dünner Terrassen oder ließen den
  Apennin eine flache Stufe; mit 400 bis 500 m je Stufe über 1000 m lasen die
  Alpen als ein breiter Tafelberg).
  Eine Stufe ist weit draußen höher gezeichnet
  (`LEVEL_HEIGHTS` in tile_terrain.gd: 0,6 / 0,9 / 1,2 / 1,5 Kachelbreiten bei
  2 / 4 / 8 / 16 km), so stehen die gestapelten Plateaus der Gebirge auch auf
  der Europakarte. Die Höhe nimmt vorher zu drei Vierteln den höchsten Punkt
  innerhalb einer Kachel (`PEAK_SHARE`) und wird über 0,7 Kacheln
  weichgezeichnet, so behalten schmale Gebirge wie Apennin und Pyrenäen ihren
  Grat, statt in der Ebene zu zerfließen; danach räumt der Bake je Stufe auf (Öffnen und
  Schließen mit 3 × 3 Ecken): einzelne Buckel, Löcher und eine Kachel breite
  Stege verschwinden, Gebirge bleiben als zusammenhängende Massive stehen.
- Ecken am Meer liegen auf Meereshöhe, die Küste läuft also als Rampe ins Wasser.
  Ecken an einem See liegen auf dem Seespiegel, auch das Seeufer ist eine Rampe.
  Das weichgezeichnete Relief wird an den Ufern durch die scharfe Wasserhülle
  (`shore.r16f`) begrenzt: Sie steigt von jedem Ufer um eine Stufe pro Kachel. Der
  Bake setzt dafür jeden Knoten unter einer 0,5-km-Seezelle auf den Seespiegel,
  so entstehen keine Kraterwände am Seeufer. (Das Relief aus `relief.r16f`
  baut nur noch die Ecken, wenn die gebackenen Stufen fehlen.)
- Ufer wie in SimCity 2000: Meer und Seen liegen um `water_drop` (0,3 Stufen)
  tiefer als das Land, das Land endet also mit einer kleinen Erdkante am Wasser.
  Hat eine Landkachel auf zwei benachbarten Seiten und der Diagonale dazwischen
  Wasser, ist die Hälfte zu dieser Ecke hin ebenfalls Wasser, geschnitten an der
  Kacheldiagonale (`tt_coast_cut`). So läuft eine Treppe aus Wasserkacheln als
  45-Grad-Küste. Die Kachel ist dafür aus zwei getrennten Dreiecken gebaut, und
  ein fünftes Wandstück steht als Kante auf der Diagonale.
  Kacheln werden an der Diagonale geteilt, deren Ecken näher beieinander liegen
  (wie SimCity 2000): eine einzelne gehobene Ecke ergibt ein flaches und ein
  geneigtes Dreieck statt einer Falte. `MOUNTAIN_SLOPE` erlaubt im Hochgebirge
  (Mittel über 10 km ab 500 m, voll ab 1300 m) eine steilere Rampe, steht aber
  auf 1 × `RELIEF_SLOPE`: auch Gebirge folgen der Ein-Stufen-Regel.
  Im Land gibt es keine Klippen. Flüsse sind schmale Bänder in der Landkachel
  (mindestens Bootsbreite), Kurven schneiden die Ecke diagonal.
- Flüsse sind je Zoomstufe **eine saubere Linie aus Kacheln**: Der Bake zeichnet
  die Mittellinie jedes Flusses (eine Kachel breit), verbindet reine
  Diagonalschritte über eine Landkachel, füllt Schlaufen um bis zu 4 Kacheln,
  dünnt doppelte Läufe auf eine Kachel aus (4-einfache Zellen, Ränder und Enden
  bleiben) und kappt Seitenstummel bis 3 Kacheln Länge sowie einzelne Zellen
  (`clean_rivers`). Mündungen am Meer und an Seen bleiben stehen. Echte
  Flussarme um größere Inseln bleiben als Schlaufe erhalten.
- Optik nach Urbek (Ramon, 28.10.2026: „einzelne Tiles eine Farbe, resp. 2 Farben
  wenn Terrain übereinander fließt“, „Referenz Urbek“): **jede Kachel hat eine
  flache Farbe** nach ihrer Landschaft (`ground-L*.png`): Wiese (der Grundton, wie
  Urbek), trockenes Gras (nur auf trockenem Land und im tiefen Süden), Feld, Feuchtgebiet, Gestrüpp, Sand, Laubwald, Nadelwald, Alm,
  Fels, Schnee. Keine Rauschränder, keine Muster, keine Überblendungen, kein
  Farbzittern, keine Gitterlinien. Wo zwei Landschaften aneinanderstoßen, gilt
  die Küstenregel: Haben beide Seiten an einer Ecke und die Kachel über Eck eine
  stärkere Landschaft (Schnee vor Fels vor Wald vor offenem Land), nimmt die
  Hälfte zu dieser Ecke hin sie an, geschnitten an der Diagonale. So laufen
  Waldränder als 45-Grad-Linien statt als Treppe, und eine Kachel hat höchstens
  zwei Farben. Die Palette ist aus Urbek-Screenshots gemessen und auf diese
  Töne am Bildschirm abgestimmt (Wiese #73af5f, trockenes Gras #9baf5f,
  Weizen #cdc373, Waldboden zwischen den Kronen #2c5e26, Wasser #6db3df,
  Flachwasser #8ccbef, Flüsse und Seen #5ea8da). Ab 1-km-Kacheln (etwa ab
  30 km Sichtbreite, mit dem Wechsel der Kachelgröße) geht sie in die Palette der gemalten Fernsicht
  über (Gauntlet-Referenz gemalt-weit-mittel-nah.png): olives Tiefland
  #9aa35a, olivgrüner Wald #56683c (nicht #4f7b36, das sprang nach dem
  olivfarbenen 70-km-Bild zurück ins Grün), Fels, tiefes Meer #19588c mit
  Flachwasser #24689e; Seen wie die Flüsse im Flachwasserton. Offenes Land bekommt dort zusätzlich eine flache Farbe
  je Höhenstufe (Hügel #849252, Bergweide #7c8550 statt Khaki #958e6c, das den
  Apennin zum Steinbruch machte, hoher Fels warm #9a9488,
  nicht lila; das Höhenband zählt in fernen Stufen, auch auf den nahen Kacheln), so lesen
  Hügel und Gebirge als Flächen und nicht nur über ihre Rampen; Wald auf
  Hügeln und Bergen ist dort dunkler (Nadelwaldton), Fels ab der dritten
  Stufe hell, nackter Fels nur auf den obersten zwei Stufen im Umkreis von
  10 km und Schnee nur auf der obersten (`peaks_only` im Bake; vorher lagen
  Felsflächen über dem ganzen Apennin und Schneeflecken halb am Hang), und die Schneelinie sinkt weit draußen um 180 m je Zoomstufe,
  so tragen die Alpen, Pyrenäen und Karpaten auf der Europakarte Schneekappen.
  Rampen haben einen festen Ton je Seite wie in SimCity 2000, passend zur
  Sonne aus Westsüdwest: nach Westen +12 %, nach Osten −15 %, nach Süden
  (die Stufen, die die Kamera von vorn sieht) −10 %, nach Norden −18 %; eine
  Eckfacette nimmt die dunklere ihrer zwei Seiten (Südwest −10 %, Südost
  −15 %). Kritik r7: Mit den Stufen zur Kamera +5 % heller verschwanden
  sie; mit West +18 % und sonst nichts lasen Hänge als gestreifter Rasen. Rampen, die von der Kamera weg zeigen (auch nach
  Nordost und Nordwest), sieht man nur als Kante; sie bleiben im flachen Ton
  (die diagonalen zogen bei 70 km Haarlinien durchs Land), sonst zeichnet eine lange Stufe
  einen dunklen Strich durchs Land (die „Naht“ bei 120 km). Die Töne kommen von einem festen
  SimCity-Licht von links und hinter der Kamera (`tt_art_light`, aus der
  Kameralage), nicht von der Sonne des Wetters: So sind die der Kamera
  zugewandten Rampen und Wände bei jedem Kamerawinkel hell wie in SimCity 2000
  und Urbek (bei Blick nach Norden kommt es aus Südwesten). Das Licht sieht jede Oberseite und
  Wand als flach, damit Rampen weder glasig noch schwarz werden; Bäume und
  Häuser sind auf ihren Süd- und Westseiten etwas heller getönt.
  Wände sind ein dunklerer Erdton ohne Schichtlinien, nach Osten gewandt
  dunkler. Am Meer ein Sandsaum an
  den Wasserseiten und auf der Schnittdiagonale. Meer: je Kachel eine Farbe,
  ein tiefes Blau, heller, wo die Kachel Land berührt (nicht um Inseln aus
  einer Kachel, sonst liegt ein heller Kasten um einen Punkt Land); Flüsse und Seen sind
  dunkler als dieses Flachwasser. Eine Seekachel an einer Ecke ihres Sees
  (Land auf zwei Nachbarseiten und der Diagonale dazwischen) ist zur Hälfte
  Land auf Uferhöhe, wie der Küstenschnitt umgekehrt (`tt_lake_corner_cut`):
  Ein See aus wenigen Kacheln hat 45-Grad-Ecken statt der Umrisse einer Kiste
  (nicht, wo die Landkacheln daneben selbst geschnitten sind). Bäume stehen nah genau auf den
  Waldkacheln (und Waldhälften), auf den Vierteln so dicht wie auf den
  0,5-km-Kacheln (gut zwei der vier Plätze, der Waldboden zeigt sich
  zwischen den Kronen), dazu kleine Gruppen von drei bis sieben Bäumen auf
  offenem Grasland und an Feldern (keine Einzelbäume, sie lasen als Tischchen). Auch dichter Wald öffnet sich alle paar
  Kilometer zu Lichtungen. Flüsse sind auch weit draußen mindestens anderthalb
  Pixel breit. Natural Earth scalerank je Ebene: bis 10 bei 0,5 und 1 km,
  8 bei 2 km, 7 bei 4 km, 6 bei 8 km und 5 auf der Europakarte (16 km). Tiber
  (Rang 5) und Arno (Rang 7) zählen als Flüsse Roms höher, als Natural Earth
  sie für heutige Karten einstuft. Städte
  sind gepflastert mit Häusern, bis zu 4-km-Kacheln: weiter draußen wachsen
  die Häuser mit der Kachel (bei 2 km doppelt, bei 4 km vierfach so groß), wie
  Gebäude in SimCity 2000 beim Herauszoomen, so bleiben Städte ein Mosaik aus
  Dächern statt Farbflächen. Jenseits des Hausbereichs sind Städte ganze
  Kacheln in Terrakotta (keine Mischfarben), bis 4-km-Kacheln; auf 8- und
  16-km-Kacheln lasen sie als rote Markierungen und gehen wie die Dörfer im
  Land auf. In Städten (ab Ortsklasse 2)
  laufen graue Basaltstraßen zwischen den Häuserblöcken, auf dem Raster der
  Hausplätze; die Häuser lassen dafür Platz (ein Grundstück füllt 0,92 seines
  Platzes, `LOT_SHARE`). Städte sind voll bebaut, ein
  Grundstück auf jedem Viertel (Kritik r7: keine nackte Wiese in der Stadt);
  gepflastert sind die Höfe unter den Häusern und im Stadtkern die leeren
  ebenen Plätze, Dörfer bleiben Land. Ein Haus steht immer waagrecht auf dem
  höchsten Boden unter ihm; auf einer Rampe füllt eine Terrasse aus
  Travertin (#cec2a1 oben, Mauer #b8ae96, `PropMeshes.plinth`, Prop-Art 5)
  den Raum bis zum tiefsten Boden, so steigt ein Ort am Hang in Terrassen an
  wie Tivoli (vorher kippten die Häuser mit der Rampe und lasen bei 22 km als
  schräge Karten, noch früher standen sie nur auf flachen Vierteln und
  ließen leere Hänge). In Dörfern stehen die Häuser nur auf flachen
  Vierteln. Am Fluss in einer Stadt ist das Ufer ein gepflasterter Kai
  (vorher Weizen mitten in Rom). Orte wachsen mit ihren Einwohnern (Fläche
  wie bei 9000 Menschen je km²); Städte ab 3000 Einwohnern bekommen einen
  Ring dazu, bis 0,45 km ab 7000 (`TOWN_EXTRA_KM`), sonst blieben dem
  diorama-großen Haus (ein Grundstück je 0,25 km) in Tibur drei Häuser;
  Dörfer behalten ihre Größe. Die Häuser sind die Grundstücke der
  römischen Stadt aus dem Kolosseum-Prototyp (`voxel/roman_buildings.gd`, eine
  Kopie aus PR #45, 40 Voxel auf 10 m wie Urbek): 14 Hausvarianten (Domus mit
  Atrium, Insulae mit Läden, Werkstätten, Putz in Creme, Ocker und Kalkweiß,
  Terrakottadächer mit Dachgärten) und zwei Gärten, ein Grundstück je
  Viertelkachel (`LOT_KINDS`). Jedes Modell ist eine eigene MultiMesh und
  zeichnet jeden 16. Hausplatz, in jedem Block von 16 Plätzen einen anderen,
  so kosten alle Modelle zusammen so viel wie vorher ein Haus. Bis 5 km
  Sichtbreite die vollen Modelle (Stufe 0, 0,25-m-Voxel, etwa 5000 Dreiecke
  je Grundstück, `PROP_DETAIL_KM`; die 1-m-Voxel der Stufe 1 lasen bei 3 km
  als Pilze), bis 10 km Stufe 1 (einige hundert Dreiecke), ab `PROP_LOW_KM`
  Stufe 2. Die Wahrzeichen bis 10 km in voller Stufe. Ein Grundstück zeigt der
  Kamera immer seine Vorderseite mit der Tür (Kritik r7: gedrehte
  Grundstücke zeigten fensterlose Seitenwände). Häuser halten mit
  ihrer ganzen Grundfläche Abstand zu den Wahrzeichen, und jedes 16.
  Kernhaus fehlt als Hof.
- Rom hat seine großen Bauten, jedes auf einem Block von Stadtkacheln, auf
  dem keine Häuser stehen (`LANDMARKS` in tile_terrain.gd). Kolosseum (4 × 4
  Viertel), Forum Romanum mit dem Kapitol und seinem goldenen Jupitertempel
  (3 × 3), die Thermen (2 × 1), das Pantheon (2 × 2) und der Circus Maximus
  (4 × 2, Blöcke von 0,5 km) sind die Modelle der römischen Stadt
  (`kit:`), im selben Maßstab wie die Häuser (1:23,8 in der Fläche, Häuser
  und Bauten in echter Größe), so passen sie Voxel für Voxel zu den
  Grundstücken; dazu zwei Tiberbrücken als einfache Formen (6-mal echt in
  der Fläche, 9-mal in der Höhe, `LANDMARK_KM_PER_M`, `LANDMARK_RISE`). Die
  Blöcke liegen als offene Plätze in Travertin #e6dfcf ohne Straßenraster.
  Nah ist jeder Block eben, auf der mittleren Stufe seiner Ecken
  (`landmark_levels`, der Shader setzt die Ecken im Block darauf). Sie
  stehen, solange die Häuser gezeichnet werden.

## Fernsicht (Kacheln bis Europa)

Ramon, 28.10.2026: „Kachel-Look konsequent bis immer“. Es gibt keine weiche
Reliefkarte mehr; auch ganz draußen (16-km-Kacheln, ganz Europa) gelten dieselben
Regeln wie nah: eine Farbe pro Kachel aus der Landschaft dieser Zoomstufe. Damit Gebirge
draußen nicht zu einer Stufe zusammenfallen und das Flachland ruhig bleibt,
kommen die Eckstufen ab 2-km-Kacheln aus dem Bake (siehe Geländeregeln). Ohne
Modelle werfen die Kacheln keine Schatten. Licht: wenig Umgebungslicht und
Filmic-Tonemapping, damit die Farben nicht auswaschen.

## Maßstab

Kit-2-Maßstab (`docs/kit2/SCALE.md`): Längen 1:23,8 gegenüber der echten Welt
(`DIORAMA_LAENGE`), Häuser und Bäume in echter Größe. Die Welteinheit bleibt der
echte Kilometer, ein Diorama-Meter sind also 0,0238 Welteinheiten.

| Größe | Wert |
|---|---|
| Fläche | 1 Welteinheit = 1 echter km = 42 m Diorama, mapping-v1 |
| Kachel je Zoomstufe | 0,25 (Viertel, `SUB_KM`) / 0,5 / 1 / 2 / 4 / 8 / 16 km echt = 10,5 m … 670 m Diorama (`LEVELS`) |
| Höhe | nah eine Stufe = 20 / 50 / 120 m echt (Tiefland, Hügel, Gebirge; bei 1-km-Kacheln das Doppelte), weiter draußen die steigende Skala `LEVEL_STEPS_M` (150 bis 600 m je Stufe) |
| Haus | ein römisches Grundstück von 10 × 10 m Diorama (`HOUSE_M`, 238 m Welt), eins je Viertelkachel, vier je 0,5-km-Kachel; gezeichnet bis 4-km-Kacheln |
| Wahrzeichen Roms | Modelle der römischen Stadt im Diorama-Maßstab wie die Häuser (Kolosseum 8 × 7 Grundstücke auf 4 × 4 Blöcken von 0,5 km) |
| Baum | 8 m Diorama (`TREE_M`, Urbek: 5–8 m, so hoch wie ein zweistöckiges Haus), nur auf Stufe 0 auf den Waldkacheln (auf Stufe 1 waren sie ein Sprenkel über dem Relief); weiter draußen sind Waldkacheln dunkelgrün. Laubbäume mit runder Voxelkrone (Kern, Gürtel auf vier Seiten, flache Kappe), dunkler und satter als die Wiese wie bei Urbek gemessen (Oberseite etwa #458d33, Seiten #29521f); Zypressen #2f5a2c wie an den Höfen |
| Nächster Zoom | 4 km echt Sichtbreite, etwa 17 Häuser nebeneinander |

## Aufbau

- `tools/build_tile_terrain.py` backt `artifacts/render-data/tile-terrain-r1/`
  (etwa 6 Minuten): Bewuchs, Meeresabstand und Seespiegel (2-km-Knoten), Wasser-
  und Ortsklassen je Zoomstufe (`cells-L*.png`, Flüsse bereinigt; die Orte
  allein neu mit `--towns-only`, etwa 20 Sekunden), Höhe und
  begrenztes Relief (`height.r16f`, `relief.r16f`), die Wasserhülle
  (`shore.r16f`), die Eckstufen der fernen Zoomstufen (`levels-L*.png`;
  allein neu mit `--levels-only`, etwa 1 Minute), die der nahen aus den
  Terrain Tiles (`levels-L0.png`, `levels-L1.png`; allein neu mit
  `--near-only`, einzeln mit `--level=0` oder `--level=1`, etwa 35 Minuten
  und 12 GB Speicher für beide, der erste Lauf lädt 1298 Kacheln, 93 MB) und die Landschaft jeder Kachel
  je Zoomstufe (`ground-L*.png`, `ground_classes`: Bodenbedeckung und Höhe an
  der Kachelmitte, ein wenig Rauschen in km macht aus Anteilen Flecken dieser
  Größe, einzelne Kacheln werden ihren Nachbarn angeglichen; weiter draußen
  sind die Daten stärker weichgezeichnet und das Rauschen schwächer, und
  Lichtungen gibt es nur bis 2-km-Kacheln, so stehen auf der Europakarte
  ruhige große Landschaften statt Flecken; fern bleibt nur dichter Wald
  Wald (`WOOD_MIN`: ab 1-km-Kacheln braucht ein Wald 0,66 bis 0,92
  Waldanteil statt 0,45; die römische Bedeckung trägt Wald auf über der
  Hälfte Italiens, fern las das als dunkle Tarnfarbe; Mittelitalien hat bei
  70 und 120 km je 24 % Wald, bei 400 km 19 %), so
  liest das Land hell mit dunklen Wäldern wie die gemalte Karte, und
  die Grenze zum Nadelwald im Norden wandert um einige Breitengrade statt
  als Gerade durch Russland zu laufen; allein neu mit
  `--ground-only`, etwa 8 Minuten). Braucht numpy, Pillow und scipy. Eingaben sind im Manifest mit Hash geführt.
- `app/scripts/tile_terrain.gd` lädt die Daten, wählt die Zoomstufe und
  verschiebt die Patches. Ein MultiMesh mit 320 × 320 Kacheln, fünf MultiMeshes
  für Laubbäume, Nadelbäume, Zypressen, Pinien und Häuser (100 × 100 Kacheln).
- `app/shaders/tile_terrain.gdshaderinc` enthält die Kachelregeln, die
  `tile_terrain.gdshader` (Oberseite und Wände) und `tile_props.gdshader`
  (Platzierung der Bäume und Häuser) gemeinsam nutzen. Die gesamte Geometrie
  entsteht im Vertex-Shader; die CPU spiegelt nur die Bodenhöhe für Kamera und Wetter.
- Zwei kleine 2D-Pässe pro Bild (Float-Viewports) rechnen vor, was sonst jeder
  Vertex selbst rechnen müsste: `tile_corner_prep.gdshader` die Eckhöhen jeder
  Kachel im Patch, `tile_prop_prep.gdshader` (mit `tile_props.gdshaderinc`) Ort,
  Art und Größe jedes Baum- und Hausplatzes. Gelände und Props lesen nur noch
  einen Texel. Auf den Vierteln kommt `tile_sub_prep.gdshader` dazu, nur wenn
  sein Fenster weiterrückt.
- Leistung: Der Prop-Patch ist nur so groß wie die Sicht (`PROP_SPAN`), ab
  10 km Sichtbreite gibt es Low-Poly-Bäume und grobe Häuser ohne Schatten
  (`PROP_LOW_KM`), volle Hausmodelle nur bis 5 km (`PROP_DETAIL_KM`), und
  Baumarten, die im Ausschnitt nicht wachsen können, werden ausgeblendet. Ab
  1-km-Kacheln werfen die Kacheln keine Schatten mehr (die grobe Schattenkarte
  zeichnete dort nur dunkle Striche an den Stufen).
- `app/scripts/tile_prop_meshes.gd` baut die Kachelvorlage, die Voxel-Bäume
  nach Urbek (achsparallele Blöcke, helle Oberseite, dunklere Seiten, nur in
  Vierteldrehungen gedreht, also am Kachelraster ausgerichtet) und die
  Tiberbrücken, die `tile_landmark.gdshader` beleuchtet, und die Terrassen
  unter Häusern am Hang; Häuser und Wahrzeichen kommen aus
  `app/scripts/voxel/roman_buildings.gd`.
  Pinien stehen nur im Süden (unter 44,5° Breite, unter 700 m), Bäume enden
  bei 1400 m.
- `app/scripts/landscape.gd` enthält Kamera, Eingabe, Licht und Wetteranbindung.

## Bedienung

Mausrad oder Pinch zoomt hinein zum Cursor und hinaus um die Bildmitte, Ziehen oder
WASD/Pfeile verschiebt, +/− zoomt. Die Ansicht schaut immer nach Norden und dreht sich
nie (Ramon, 28.10.2026: „kein rotieren“). Ganz draussen (4400 km) steht sie fast senkrecht
über ganz Europa. F5–F7 steuern das Wetter. Startoptionen:
`--view=lon,lat,breite_km`, `--snapshot=pfad.png`, `--snapshot-frames=n`,
`--bench=n` (misst n Bilder nach dem Vorlauf und gibt die mittlere Bildzeit aus).

## Offen

- macOS-Paketierung des Tile-Geländes.
- Leistungsmessung auf dem Mac nach dem Umbau (vorher 142 ms bei 25 km Sichtbreite).
- Straßen außerhalb der Städte, Stadtmauer als echte Geometrie.
