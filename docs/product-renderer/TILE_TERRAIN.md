# Tile-Gelände (SimCity 2000 auf jeder Zoomstufe)

Status: `implementiert`, seit 27.10.2026 das einzige Gelände der App. Das Wetter
(`app/scripts/weather/`, `app/shaders/weather_*`, `cloud_layer`) ist davon
unabhängig und unverändert.

## Geländeregeln (SimCity 2000)

- Die Welt besteht aus quadratischen Kacheln. Jede **Ecke** hat eine Höhenstufe,
  benachbarte Kacheln teilen ihre Ecken. Dadurch ist das Land eine durchgehende
  Fläche aus flachen Kacheln und Rampen, wie in SimCity 2000 (XTER-Formen
  00–0D: jede Ecke liegt auf der Kachelhöhe oder eine Stufe darüber).
- Benachbarte Ecken liegen bei 0,5- und 1-km-Kacheln **höchstens eine Stufe**
  auseinander. Das sichert das gebackene Relief (`sc2k_relief`), das auf
  `RELIEF_SLOPE` m/km begrenzt ist. Weiter draußen sind steilere Rampen erlaubt.
- Eine Stufe ist **0,6 Kachelbreiten** hoch (SimCity 2000: 12 px Stufe auf einer
  32 × 16 px Kachel). Bei 0,5- und 1-km-Kacheln entspricht eine Stufe
  `RELIEF_SLOPE × Kachelbreite` echten Metern, also 3,75-fach überhöht
  (`HEIGHT_EXAGGERATION`, Kit 1 K06, geändert am 27.10.2026). Daraus folgt
  `RELIEF_SLOPE` = 160 m/km: wenige, lange Terrassen wie in SimCity 2000 statt
  vieler schmaler Streifen.
- Ab 2-km-Kacheln kommen die Eckstufen aus dem Bake (`levels-L*.png`,
  `corner_levels`): eine Stufe sind 200 / 280 / 360 / 440 m echt
  (`LEVEL_METRES`, 2 / 4 / 8 / 16-km-Kacheln), gezählt ab 150 m
  (`LEVEL_FLOOR_M`), also weiter draußen gröber: Tiefland 0, Hügel 1 bis 2,
  Gebirge 3 bis 5 Stufen (feinere Stufen zeichneten ein Labyrinth dünner
  Terrassenlinien). Dafür ist eine Stufe weit draußen höher gezeichnet
  (`LEVEL_HEIGHTS` in tile_terrain.gd: 0,6 / 0,9 / 1,2 / 1,5 Kachelbreiten bei
  2 / 4 / 8 / 16 km), so stehen die gestapelten Plateaus der Gebirge auch auf
  der Europakarte. Die Höhe wird vorher über
  1,2 Kacheln weichgezeichnet, danach räumt der Bake je Stufe auf (Öffnen und
  Schließen mit 3 × 3 Ecken): einzelne Buckel, Löcher und eine Kachel breite
  Stege verschwinden, Gebirge bleiben als zusammenhängende Massive stehen.
- Ecken am Meer liegen auf Meereshöhe, die Küste läuft also als Rampe ins Wasser.
  Ecken an einem See liegen auf dem Seespiegel, auch das Seeufer ist eine Rampe.
  Das weichgezeichnete Relief wird an den Ufern durch die scharfe Wasserhülle
  (`shore.r16f`) begrenzt: Sie steigt von jedem Ufer um eine Stufe pro Kachel. Der
  Bake setzt dafür jeden Knoten unter einer 0,5-km-Seezelle auf den Seespiegel,
  so entstehen keine Kraterwände am Seeufer.
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
  flache Farbe** nach ihrer Landschaft (`ground-L*.png`): Wiese, trockenes Gras
  (Mittelmeer), Feld, Feuchtgebiet, Gestrüpp, Sand, Laubwald, Nadelwald, Alm,
  Fels, Schnee. Keine Rauschränder, keine Muster, keine Überblendungen, kein
  Farbzittern, keine Gitterlinien. Wo zwei Landschaften aneinanderstoßen, gilt
  die Küstenregel: Haben beide Seiten an einer Ecke und die Kachel über Eck eine
  stärkere Landschaft (Schnee vor Fels vor Wald vor offenem Land), nimmt die
  Hälfte zu dieser Ecke hin sie an, geschnitten an der Diagonale. So laufen
  Waldränder als 45-Grad-Linien statt als Treppe, und eine Kachel hat höchstens
  zwei Farben. Die Palette ist aus Urbek-Screenshots gemessen und auf diese
  Töne am Bildschirm abgestimmt (Wiese #73af5f, trockenes Gras #9baf5f,
  Weizen #cdc373, Wald als Kronendach von oben #3c7440, Wasser #6db3df,
  Flachwasser #8ccbef, Flüsse und Seen #5ea8da). Weit draußen (ab
  2-km-Kacheln, voll bei 4 km) geht sie in die Palette der gemalten Fernsicht
  über (Gauntlet-Referenz gemalt-weit-mittel-nah.png): olives Tiefland
  #9aa35a, dunkelgrüner Wald #4f7a35, Fels, tiefes Meer #1d5e93 mit
  Flachwasser #2f7db5. Offenes Land bekommt dort zusätzlich eine flache Farbe
  je Höhenstufe (Hügel #849252, Gebirge #958e6c, hoher Fels #b3aba0), so lesen
  Hügel und Gebirge als Flächen und nicht nur über ihre Rampen; Wald auf
  Hügeln und Bergen ist dort dunkler (Nadelwaldton), Fels ab der dritten
  Stufe hell, und die Schneelinie sinkt weit draußen um 180 m je Zoomstufe,
  so tragen die Alpen, Pyrenäen und Karpaten auf der Europakarte Schneekappen.
  Rampen haben drei feste Töne wie in SimCity 2000 (Lichtseite 1,12,
  Seite 0,90, Schattenseite 0,72), kräftig genug, dass die gestapelten Rampen
  bis zur Europakarte lesbar bleiben. Die Töne kommen von einem festen
  SimCity-Licht von links und hinter der Kamera (`tt_art_light`, aus der
  Kameralage), nicht von der Sonne des Wetters: So sind die der Kamera
  zugewandten Rampen und Wände bei jedem Kamerawinkel hell wie in SimCity 2000
  und Urbek (bei Blick nach Norden kommt es aus Südwesten). Das Licht sieht jede Oberseite und
  Wand als flach, damit Rampen weder glasig noch schwarz werden; Bäume und
  Häuser sind auf ihren Süd- und Westseiten etwas heller getönt.
  Wände sind ein dunklerer Erdton ohne Schichtlinien, nach Osten gewandt
  dunkler. Am Meer ein Sandsaum an
  den Wasserseiten und auf der Schnittdiagonale. Meer: je Kachel eine Farbe,
  ein tiefes Blau, heller, wo die Kachel Land berührt; Flüsse und Seen sind
  dunkler als dieses Flachwasser. Städte sind weit draußen Kacheln in
  Terrakotta. Bäume stehen nah genau auf den
  Waldkacheln (und Waldhälften), dazu einzelne Bäume und kleine Baumgruppen
  auf offenem Grasland und an Feldern. Auch dichter Wald öffnet sich alle paar
  Kilometer zu Lichtungen. Flüsse sind auch weit draußen mindestens anderthalb
  Pixel breit. Natural Earth scalerank je Ebene: bis 10 bei 0,5 und 1 km,
  8 bei 2 km, 7 bei 4 km, 6 bei 8 km und 5 auf der Europakarte (16 km). Tiber
  (Rang 5) und Arno (Rang 7) zählen als Flüsse Roms höher, als Natural Earth
  sie für heutige Karten einstuft. Städte
  nah gepflastert mit Häusern, weit draußen Kacheln in Dachfarbe; Dörfer gehen
  weit draußen im Land auf. In Städten (ab Ortsklasse 2) laufen nah
  graue Basaltstraßen zwischen den Häuserblöcken, auf dem Raster der
  Hausplätze; die Häuser lassen dafür Platz (Grundfläche 0,62 bis 0,74 der
  Hauslänge). Im Stadtkern stehen Insulae bis doppelt so hoch, in Städten
  anderthalbfach.
- Rom hat seine großen Bauten als Voxel-Modelle nach Urbek und Caesar III
  (Travertin, Marmor, Terrakotta), jedes auf einem Block von Stadtkacheln, auf
  dem keine Häuser stehen: der Jupitertempel auf dem Kapitol am Tiber, östlich
  davon das Forum Romanum (Basilica Julia, Dioskurentempel, Vestatempel,
  Curia, Ehrensäulen), das Kolosseum auf 2 × 2 Kacheln, das Pantheon im
  Norden und südlich des Palatins der Circus Maximus auf 4 × 1 Kacheln
  (`LANDMARKS` in tile_terrain.gd). Sie sind 6-mal so groß wie in echt, nicht
  24-mal wie die Häuser, damit die Stadt ihre Kacheln behält, und noch einmal
  um die Hälfte höher, damit Kolosseum und Tempel über die Insulae ragen. Sie
  stehen, solange die Häuser gezeichnet werden (0,5- und 1-km-Kacheln).

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
| Kachel je Zoomstufe | 0,5 / 1 / 2 / 4 / 8 / 16 km echt = 21 m … 670 m Diorama (`LEVELS`) |
| Höhe | eine Stufe = 80 / 160 m echt (3,75-fach überhöht), weiter draußen 170 / 190 / 210 / 230 m ab 100 m |
| Haus | 10 × 8,5 m Diorama (`HOUSE_M`), zwei Stockwerke (6 m Wand) unter einem gestuften Dach von einem Drittel der Höhe (Urbek), auf Stufe 0 und 1 gezeichnet |
| Wahrzeichen Roms | 6-mal echt in der Fläche, 9-mal in der Höhe (`LANDMARK_KM_PER_M`, `LANDMARK_RISE`): Kolosseum 1,1 × 0,9 km Welt, Circus Maximus (gekürzt auf 330 m) 2 × 0,6 km |
| Baum | 8 m Diorama (`TREE_M`, Urbek: 5–8 m, so hoch wie ein zweistöckiges Haus), nur auf Stufe 0 auf den Waldkacheln (auf Stufe 1 waren sie ein Sprenkel über dem Relief); weiter draußen sind Waldkacheln dunkelgrün |
| Nächster Zoom | 4 km echt Sichtbreite, etwa 17 Häuser nebeneinander |

## Aufbau

- `tools/build_tile_terrain.py` backt `artifacts/render-data/tile-terrain-r1/`
  (etwa 6 Minuten): Bewuchs, Meeresabstand und Seespiegel (2-km-Knoten), Wasser-
  und Ortsklassen je Zoomstufe (`cells-L*.png`, Flüsse bereinigt), Höhe und
  begrenztes Relief (`height.r16f`, `relief.r16f`), die Wasserhülle
  (`shore.r16f`), die Eckstufen der fernen Zoomstufen (`levels-L*.png`;
  allein neu mit `--levels-only`, etwa 1 Minute) und die Landschaft jeder Kachel
  je Zoomstufe (`ground-L*.png`, `ground_classes`: Bodenbedeckung und Höhe an
  der Kachelmitte, ein wenig Rauschen in km macht aus Anteilen Flecken dieser
  Größe, einzelne Kacheln werden ihren Nachbarn angeglichen; weiter draußen
  sind die Daten stärker weichgezeichnet und das Rauschen schwächer, und
  Lichtungen gibt es nur bis 2-km-Kacheln, so stehen auf der Europakarte
  ruhige große Landschaften statt Flecken; allein neu mit
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
  einen Texel.
- Leistung: Der Prop-Patch ist nur so groß wie die Sicht (`PROP_SPAN`), ab
  10 km Sichtbreite gibt es Low-Poly-Bäume ohne Schatten (`PROP_LOW_KM`), und
  Baumarten, die im Ausschnitt nicht wachsen können, werden ausgeblendet. Ab
  2-km-Kacheln werfen die Kacheln keine Schatten mehr (die grobe Schattenkarte
  zeichnete dort nur Streifen).
- `app/scripts/tile_prop_meshes.gd` baut die Kachelvorlage, die Voxel-Bäume
  nach Urbek (achsparallele Blöcke, helle Oberseite, dunklere Seiten, nur in
  Vierteldrehungen gedreht, also am Kachelraster ausgerichtet) und die
  Stadthäuser nach Urbek (Putzkasten mit Fenstern und Tür, Dach aus
  Voxel-Stufen in Terrakotta) und die Wahrzeichen Roms (`landmark`), die
  `tile_landmark.gdshader` wie die Häuser beleuchtet.
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
