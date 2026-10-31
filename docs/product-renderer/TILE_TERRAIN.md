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
  Plateaus“). Eine Stufe ist dort so hoch wie bei 0,5 km (`NEAR_EXAGGERATION`), damit
  die Hügel beim Zoomen ihre Höhe behalten. Ein
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
  darüber 60 m, so steigen die Berge in vielen schmalen Stufen statt weniger
  breiter Tafeln an (Kritik r9); bei 1-km-Kacheln die doppelten Meter, über
  840 m aber 240 m je Stufe: Mit 120 m zogen sich die Hänge des Apennins bei
  70 km als Cord aus 55 % Rampen hin, Kritik r10; der Shader spiegelt sie
  in `tt_near_level_x` und `tt_near_beyond_m`): Roms Gianicolo, Quirinal und Esquilin stehen ein bis
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
  Alpen als ein breiter Tafelberg). Die Höhe ist das Mittel der Terrain Tiles
  über die 2-km-Quadrate der Knoten (`dem_node_heights`): Auf den glatten
  2-km-Höhen endeten die Alpen bei 1900 m und die Gebirge waren breite flache
  Tafeln (Kritik r9), jetzt haben die Alpen bei 8-km-Kacheln zehn statt sechs
  Stufen. Eine Stufe ist fern auf jeder Kachelgrösse
  0,6 km hoch (`FAR_LEVEL_KM`, Ramon 31.10.2026, Bauplan B Schritt 2), die
  Alpen also rund 6 km wie auf den 1-km-Kacheln davor; die Gebirge liest man
  an ihrer Schattierung (Grafikrunde N). Vorher war eine Stufe 0,6 / 0,9 /
  1,2 / 1,5 Kachelbreiten hoch (`LEVEL_HEIGHTS`), auf den 32-km-Kacheln 48 km:
  derselbe Berg stand je nach Zoom 2,4- bis 320-fach überhöht. Die Höhe nimmt vorher zur Hälfte den höchsten Punkt
  innerhalb einer Kachel (`PEAK_SHARE`) und wird über eine Kachel
  weichgezeichnet, so behalten schmale Gebirge wie Apennin und Pyrenäen ihren
  Grat, statt in der Ebene zu zerfließen (mit drei Vierteln und 0,7 Kacheln
  waren die Gipfel breite Tafelberge und die Hänge dünne Streifen, Kritik r10); danach räumt der Bake je Stufe auf (Öffnen und
  Schließen mit 3 × 3 Ecken): einzelne Buckel, Löcher und eine Kachel breite
  Stege verschwinden, Gebirge bleiben als zusammenhängende Massive stehen.
  Weil das Aufräumen jeden Gipfel schmaler als 2 × 2 Kacheln kappt, endeten
  die Gebirge in breiten Tafelbergen (Kritik r10: 294 × 156 px bei 70 km).
  Über 1000 m steigt darum eine flache Kuppe von mehr als 3 × 3 Kacheln auf
  ihrem höchsten Drittel (nach der echten Höhe, wo diese mindestens eine
  halbe Stufe über der Fläche liegt) eine Stufe weiter an, bis zu viermal
  (`restore_peaks`, auch auf den 1-km-Kacheln), so steigt ein Massiv in
  eingerückten Stufen an wie die Berge in SimCity 2000, eine echte
  Hochfläche bleibt flach. Auf Fels (über `ROCK_M`) steigt eine Kuppe auch
  dort, wo die echte Höhe die halbe Stufe nicht erreicht, höchstens eine
  Stufe über die echte Höhe (`PEAK_OVER`; nur nach der echten Höhe blieben
  die größten Felskuppen Platten von 470 × 116 px bei 1500 km, Kritik r11).
  Danach bekommt eine Ecke auf einer Fläche, die
  der höchste Punkt ihrer 3 × 3 Ecken ist und eine halbe Stufe darüber
  liegt, eine Stufe mehr: eine Spitze, vier Rampen zu einer Ecke. Vorher und
  nachher füllt `fill_pits` jedes Loch bis zwei Ecken breit in einer Kuppe
  (eine Kachel eine Stufe tiefer als ringsum, von den Stufen übrig: sein
  Rand stieg sonst als Ring um ein Loch).
- Weit draußen (1- bis 4-km-Kacheln, wo die Häuser auf ganzen Kacheln
  stehen) steht eine Stadt mit Häusern (Klasse 2 und mehr) auf ebenem Grund
  (`flatten_towns`): die Ecken ihrer Fläche auf der tiefsten von ihnen, das
  Land ringsum höchstens eine Stufe je Kachel höher, wie SimCity 2000 den
  Boden zum Bauen einebnet. Am Hang standen die Häuser sonst auf einem
  Sockel eine Stufe hoch, das zeichnete bei 70 km Stelzen und bei 120 km
  Zuckerwürfel (Kritik r10 und r11). Wasserecken behalten ihre Stufe.
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
  Flussarme um größere Inseln bleiben als Schlaufe erhalten. Ab 8-km-Kacheln
  fallen Inseln aus einer einzelnen Kachel weg (`ISLET_KM`, `ISLET_TILES`): Die
  griechischen und dalmatinischen Inselchen lagen bei 1500 und 4400 km als
  beige Krümel auf dem Meer. Ein Fluss mit
  Namen nimmt den besten Rang seiner Teile, und seine Strecken durch Seen
  (`Lake Centerline`) zählen mit: Wo der See ein Stausee ist, den die Karte
  nicht hat, lief der Fluss sonst in Stücken (Kritik r9: der Tajo endete bei
  4400 km im Land); in einem See der Karte fallen sie weg.
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
  30 km Sichtbreite, mit dem Wechsel der Kachelgröße) geht sie in eine
  eigene Fernpalette über, im selben satten Urbek-Grün wie nah, nur einen
  Hauch kühler (`GROUND_FAR` im Shader; am Bildschirm Wiese #70a860 wie
  Urbeks Gras, Felder eine Stufe heller und wärmer #98b860, Wald #407838;
  gelbe Felder #bcb868 ließen Ebenen und Steppen wie eine vergilbte Karte
  lesen, Kritik r11, mit Blau #84b474 wurde das Land minzig, Kritik r14), tiefes
  Meer #19588c mit Flachwasser #24689e; Seen wie die Flüsse im
  Flachwasserton. Der olive Ton der gemalten Fernsicht (Tiefland #9aa35a,
  Wald #56683c) ließ Europa wie eine vergilbte Karte aussehen; Urbek bleibt
  auch weit draußen grün (Ramon: „Referenz Urbek“). Offenes Land bekommt dort zusätzlich eine flache Farbe
  je Höhenstufe (Hügel #557841, Bergweide #5c7046; das Höhenband zählt in
  fernen Stufen, auch auf den nahen Kacheln), so lesen
  Hügel und Gebirge als Flächen und nicht nur über ihre Rampen; Wald auf
  Hügeln und Bergen ist dort dunkler (Nadelwaldton). Fern zeichnet die
  Bodenbedeckung das Relief (Kritik r8): nackter Fels (#a89c78 wie die
  gemalten Grate) auf den Kämmen der hohen Massive und Schnee (#e8e4dc statt
  Watteweiß, auch nah: im Watteweiß kappte die Tonkurve die Stufen, eine
  Stirnseite lag 2 % unter der Fläche und der Schatten fiel lila, Kritik r15
  am Mont Blanc bei 8 km) nur auf den Gipfeln, nach der echten mittleren Höhe der Kachel
  aus den Terrain Tiles (`tile_metres`, `ROCK_M` und `SNOW_M` je
  Kachelgröße, etwas höher im trockenen Süden): etwa 11 % Fels im
  70-km-Bild der Abruzzen, 4 % bei 120 km, die Alpen bei 1500 km ein
  Felsgrat, die Pyrenäen auf der Europakarte. Nah (0,5-km-Kacheln) Fels erst
  ab 2000 m, darunter Bergweide (Kritik r16: ab 1600 m lagen die Hochweiden
  der Abruzzen bei 8 km als graue Felsplatten da, 18 bis 30 % jedes Massivs,
  jetzt 2 bis 13 %); der Fels ist nah so hell wie fern (#c4b290). Schnee nur über 2500 m
  (16-km-Kacheln 2300 m), etwa 1,5 % der Alpen bei 1500 km (Kritik r9: 5,6 %
  in flachen weißen Flecken). Auf den
  Kacheln bis 2 km (`VALLEY_LEVELS` je Kachelgröße: auf gröberen Kacheln
  räumte die Regel die Flanken jedes Gebirges ab, Kritik r10) weicht der
  Wald in hügeligem Land (400 m Höhenunterschied in 10 km) aus den
  Talböden, bis 1 km der tiefsten Stufe ringsum und der Stufe darüber
  (Kritik r9: der Wald füllte die Täler und verbarg die Stufen), bei 2 km nur
  der tiefsten (mit der Stufe darüber war der Wald bei 120 km ein dünner
  Wurm, 15 %, ohne die Regel ein Teppich, 30 %, Kritik r11), und wächst an
  den Hängen bis 1700 m;
  Ebenen und Hochflächen behalten ihre Wälder. Wald, Fels und Schnee sind an
  die Stufen gebunden (`level_snap`: eine Kachel nimmt sie an, wo der größere
  Teil ihrer eigenen Stufe ringsum sie trägt), so laufen sie als Bänder
  entlang der Stufen statt als Flecken über sie hinweg; Schnee in Flecken
  von mindestens 2 × 2 Kacheln. (Vorher: Fels nur auf den obersten zwei
  Stufen im Umkreis von 10 km ließ bei 70 km 0,2 % Fels und graue Platten
  wie Löcher.) Nadelwald erst ab 1450 m, darunter Buchenwald wie im Apennin.
  Rampen haben einen festen Ton je Seite wie in SimCity 2000, passend zur
  Sonne aus Westsüdwest: nach Westen +12 %, nach Osten −15 %, nach Süden
  (die Stufen, die die Kamera von vorn sieht) −10 %, nach Norden −18 %; eine
  Eckfacette nimmt die dunklere ihrer zwei Seiten (Südwest −10 %, Südost
  −15 %). Ab 1-km-Kacheln ist die Schattenkarte aus und diese Töne sind das
  ganze Relief: dort sind sie 1,6-mal so stark (West +19 %, Ost −24 %,
  Stufen −16 %; Kritik r9 und Personen-Kritik r16: bei 70 km verschwanden
  die Stufen, hell zu dunkel nur 1,05 bis 1,2). Kritik r7: Mit den Stufen zur Kamera +5 % heller verschwanden
  sie; mit West +18 % und sonst nichts lasen Hänge als gestreifter Rasen.
  Runde L (31.10.2026): Ab den 0,5-km-Kacheln ist jede Rampe eine ganze
  Kachel und eine Stufe hoch, also überall gleich steil; mit den vollen Tönen
  lagen die Hügel bei 22 bis 70 km als grosse helle und dunkle Dreiecke da,
  die Sonnenseite +22 % wie Glasscherben (Ramon). Urbek hat kaum Hänge, und
  die Landschaftsreferenz macht Hänge nur leicht heller oder dunkler. Darum
  behält die Sonnenseite dort ein Drittel ihres Tons (`FAR_SUN_TONE`), die
  Schattenseiten zwei Drittel (`FAR_SHADE_TONE`): Die Stufen bleiben als
  dunklere Bänder lesbar. Skizze vorher/nachher:
  `/mnt/project-files/grafik/runde-l-haenge-skizze.jpg`. Rampen, die von der Kamera weg zeigen (auch nach
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
  einer Kachel, sonst liegt ein heller Kasten um einen Punkt Land). Bis
  1-km-Kacheln kommt die Küste in Voxelstufen wie bei Urbek (Runde E,
  30.10.2026): Sandsaum, Sand am Fuss der Böschung und Flachwasser sind
  Zellen von 31 m (1,3 Diorama-Meter), jede ganz oder gar nicht, nach dem
  Abstand ihrer Mitte vom Ufer gegen eine Breite, die der Küste entlang
  wandert (`coast_wander`, Buchten von etwa 150 m). So hat die Wasserlinie
  Buchten mit breitem Sand und kahle Landspitzen, und die Brandung bricht am
  Sand. Kein Sand am Fuss von Küstenschnitten, Flussmündungen und
  Stadtkaien; das Flachwasser ist ein gestuftes Band statt der ganzen
  Kachel. Nah (0,5-km- und Viertelkacheln) kommt seit Runde H (30.10.2026)
  auch die Böschung selbst in Stufen (`coast_steps.gdshaderinc`,
  `tile_coast_steps.gdshader`): Vor offenem Land (kein Ort, kein Schnitt,
  keine Einzelkachel) stehen auf der Seekachel Voxelklötze in 16 Spalten je
  Kachelseite. Wo die Küste wenig wandert, ragt eine Felsnase auf Landhöhe
  bis drei Zellen hinaus; davor liegt überall ein Sandabsatz auf halber Höhe
  zum Wasser, ein bis drei Zellen tief, am tiefsten in den Buchten. Auf
  einem Küstenschnitt füllt eine Treppe die halben Zellen der Diagonale, so
  wird die 45-Grad-Küste zur Voxeltreppe, mit Felsnasen und Absatz davor; sie
  läuft über die Kachelgrenzen weiter. Wo ein Uferstück endet, laufen die
  Stufen in einer 45-Grad-Treppe aus. `TileTerrain._update_coast_list` legt
  die Seiten und Schnitte im Requisitenfenster als Instanzen an (dieselben
  Regeln auf der CPU, in Blöcken von 32 Kacheln gelesen und behalten); die
  Kacheln legen Fusssand, Brandung und Flachwasser vor die Stufenfront und
  keinen Sandsaum hinter eine Felsnase. Weiter draussen keine Stufen.
  Runde I (30.10.2026, nach allen 15 Urbek-Shopbildern: Urbek hat keine
  Brandung, ruhiges Wasser, feine Küstenbögen und immer einen Streifen
  zwischen Haus und Wasser): Die Grenze des Sandsaums zum Gras liegt nah in
  Zellen eines Viertels (8 m), ausgefranst und mit einem blassen Rand (halb
  Sand), statt als Treppe ganzer Zellen, die auf der 45-Grad-Diagonale am
  Bildschirm als Zahnreihe stand. Vor einem Ort (Klasse 2 und 3, nie
  geschnitten) steht statt der Stufen ein Kai: zwei Zellen tief, ein heller
  Weg etwas unter dem Ort auf einer grauen Steinkante bis ins Wasser, auch um
  die Ecken der Stadt herum; die Uferwand des Orts darüber ist Stein, kein
  Sand am Fuss. Die Brandung ist nur noch eine dünne Linie (die zweite, die
  hinauslief, ist weg), das Flachwasser ein weicher Saum, der ins Meer
  ausläuft (Ramon: «Dezenter»).
  Runde K (31.10.2026, nach dem Mac-Check von I und J): Die feinen Zellen
  der Sandkante kamen bei 3 km nie zum Zug (die Länge von fwidth gegen 0,35
  war unter der schrägen Kamera zu streng), der Sägezahn blieb. Jetzt gilt
  die grössere Pixelseite gegen 0,6 (eine feine Zelle mindestens etwa
  1,7 Pixel); sind die Zellen kleiner, ist die Kante eine glatte, weich
  ausgefranste Linie statt ganzer Zellen, und auch die Breite des Sandes
  wandert mit den feinen Zellen statt in Sprüngen ganzer Zellen. Schatten
  auf dem Wasser behalten nur 35 % ihrer Tiefe (`light()`, sonst Lambert wie
  `diffuse_lambert`): Unter dem blauen Umgebungslicht lag der Schatten einer
  Mauer fast schwarzblau auf dem Meer, bei Urbek dunkelt er das Hellblau nur
  leicht ab.
  Runde M (31.10.2026): Ab den 2-km-Kacheln (Ansichten ab etwa 95 km) ist
  die Küste nicht mehr die Kachelkante, sondern eine Linie durch die
  2-km-Meeresdistanz (`aux.png` R, bilinear, die Linie bei 1 km zwischen
  einem Landknoten und dem Meerknoten daneben). Auf der Europakarte standen
  die Küsten als Treppen aus 8-km-Kacheln da, Flachwasser und Sandsaum je
  ganze Kachel; Ramons Landschaftsreferenz zeichnet sie glatt. Das Meer
  wird an der Linie zum Flachwasser und auf einer Kachel Breite wieder
  tief; Land, das die Linie über eine Meerkachel legt, nimmt die Landschaft
  der nächsten Landkachel; auf der Landseite ein Sandsaum von etwa einem
  Pixel (höchstens 0,5 km, sonst wären Inselchen aus ein, zwei Knoten wieder
  beige Flecken wie die Ein-Kachel-Inseln). Weil die Ecken am Meer auf 0
  und das Land ab 1 liegen, ist jede Küstenkachel eine Rampe vom Meer
  hinauf: Die Linie legt das Meer nur auf ihre untere Hälfte, nie auf einen
  Hang, und der Rampenton läuft am Fuss der Rampe aus, damit das Land auf
  der Meerkachel ohne Kante anschliesst. Küstenschnitte (die nasse
  Halbkachel) gibt es dort keine mehr. Skizze:
  `/mnt/project-files/grafik/runde-m-kuesten-skizze.jpg`.
  Dort liegt auch das Meer auf 0, der Höhe der Küstenecken (`tt_corners`,
  `CONTOUR_KM` in `tile_terrain.gdshaderinc`): Um `water_drop` abgesenkt
  stand es eine Uferwand tiefer als das Land, und diese Wände an den
  Kachelkanten liefen auf dem Mac als kurze beige Striche neben der glatten
  Linie, im Land oder draussen auf dem Wasser (Mac-Check K + L + M).
  Runde N (31.10.2026, Flüsse und Berge der Europakarte), ebenfalls ab den
  2-km-Kacheln: Die Flüsse liefen als Treppe aus Kachelbändern (die
  4-verbundenen Flusszellen) über die Karte; Ramons Referenz lässt sie
  mäandern. Jetzt zeichnet der Shader die Natural-Earth-Linien selbst:
  `rivers.png` (`build_tile_terrain.py --rivers-only`, `river_line_field`)
  hält an jedem 2-km-Knoten im Umkreis von zwei Knoten den nächsten Punkt
  der nächsten Flusslinie, ihre Richtung und ihre Krümmung dort, dazu den
  Rang (scalerank). Die Linien sind vorher gleichmässig neu abgetastet und
  über 0,7 Knoten geglättet (Zacken unter einem Knoten kann die Karte nicht
  zeigen). Jeder der 3 × 3 Knoten um ein Pixel zeichnet einen kurzen Bogen
  durch seinen Punkt (`river_distance`); gerade Stücke standen als Sporne
  aus jeder Biegung. Welche Flüsse, bestimmt wie bisher `RIVER_RANK` (Rang
  bis 8 auf den 2-km-Kacheln, je Zoomstufe einer weniger). Die Breite ist
  mindestens anderthalb Pixel, die grossen Flüsse so breit wie die
  Kachelbänder; am Meer endet der Fluss an der Küstenlinie, in den Seen an
  der Seekachel. Die Berge waren ganze beige Felskacheln mit wenigen
  Terrassen (eine Rampe je Kachel, Runde L ruhig getönt). Jetzt kommt das
  Relief aus den 2-km-Höhen: ein Ton je Knotendreieck, geteilt an der
  Diagonale mit den näheren Höhen wie die Kacheln (`contour_relief`,
  Kunstlicht, `RELIEF_EXAG` 1,875, Ton −30 bis +20 %), statt der Rampentöne
  der Kacheln. Fels ab 1150, Schnee ab 1600 Diorama-Metern Knotenhöhe
  (Mont Blancs Knoten 1673, Gran Sassos 1291), leicht ausgefranst; eine
  Bergkachel (Alpweide, Fels, Schnee) darunter ist Wald, wo die Landbedeckung
  bewaldet ist, sonst Alpweide (`contour_mountain`). Skizze:
  `/mnt/project-files/grafik/runde-n-fluesse-berge-skizze.jpg`.
  Flüsse und Seen sind
  dunkler als dieses Flachwasser. Eine Seekachel an einer Ecke ihres Sees
  (Land auf zwei Nachbarseiten und der Diagonale dazwischen) ist zur Hälfte
  Land auf Uferhöhe, wie der Küstenschnitt umgekehrt (`tt_lake_corner_cut`):
  Ein See aus wenigen Kacheln hat 45-Grad-Ecken statt der Umrisse einer Kiste
  (nicht, wo die Landkacheln daneben selbst geschnitten sind). Bäume stehen nah genau auf den
  Waldkacheln (und Waldhälften), auf den Vierteln so dicht wie auf den
  0,5-km-Kacheln (gut zwei der vier Plätze, der Waldboden zeigt sich
  zwischen den Kronen), dazu kleine Gruppen von drei bis sieben Bäumen auf
  offenem Grasland und an Feldern (keine Einzelbäume, sie lasen als Tischchen);
  seit Runde I auf den 0,5-km-Kacheln (12 bis 35 km) auf gut jeder fünften
  offenen Kachel und jeder achten Weide der Höfe (nie auf gesäten oder
  brachen Parzellen), und auf den 1-km-Kacheln (35 bis 90 km) stehen die
  Wälder weiter als Einzelbäume, neun je Kachel und 1,8-mal so gross
  (`TREE_FAR_GROW`), wie Urbek seine fernen Wälder als dicht gepackte kleine
  Bäume zeigt. Die Einzelbäume der Weiden bleiben bis zu den Viertelkacheln
  (12 km) stehen, nur die Büsche gehen jenseits der Feldfrüchte (8 km). Auch dichter Wald öffnet sich alle paar
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
  laufen ab 0,5-km-Kacheln Straßen zwischen den Häuserblöcken, auf dem Raster der
  Hausplätze; die Häuser lassen dafür Platz (ein Grundstück füllt 0,92 seines
  Platzes, `LOT_SHARE`). Ringdörfer zeigen dort keine Häuser mehr (Kritik
  r8: einzelne Häuser auf dem Weizen um Rom bei 22 km). Ab 1-km-Kacheln
  stehen alle Häuser einer Stadtkachel auf deren höchster Ecke, ein Sockel je
  Kachel (Kritik r9: jedes Haus auf eigener Stufe zeichnete eine Stadt am Hang
  bei 70 km als schrägen Strichcode). Die Terrasse füllt dort den ganzen
  Hausplatz, nicht nur das Grundstück, so schließen die Terrassen einer
  Stadtkachel am Hang zu einem Block zusammen (Kritik r10: unter jedem Haus
  ein eigener Sockel, dazwischen die Rampe, las bei 70 und 120 km als Stelzen). Ab 4-km-Kacheln stehen Städte auch über
  Flusskacheln (`TOWN_ON_RIVER_KM`), so bleibt eine Stadt am Fluss ein Block
  (Kritik r9: Rom war bei 400 km ein Balken östlich des Tibers). Städte sind voll bebaut, ein
  Grundstück auf jedem Viertel (Kritik r7: keine nackte Wiese in der Stadt);
  gepflastert sind die Höfe unter den Häusern und im Stadtkern die leeren
  ebenen Plätze, Dörfer bleiben Land. Ein Haus steht immer waagrecht auf dem
  höchsten Boden unter ihm, auf einer Terrasse (`PropMeshes.plinth`,
  Prop-Art 5), so steigt ein Ort am Hang in Terrassen an wie Tivoli (vorher
  kippten die Häuser mit der Rampe und lasen bei 22 km als schräge Karten).
  Auf den Viertelkacheln ist die Terrasse so groß wie die Kachel, so stehen
  die Häuser einer Stufe auf einer durchgehenden Stützmauer ohne Schlitze
  (Kritik r8), auf ebenem Boden als niedrige Stufe von 0,25 m. Ihre Mauern
  haben einen Ton je Seite (Süd #bab09a, dunkler als die Hauswände, West
  #d8d0bc, Ost #a39a86), eine Mauerkrone #ece6d8 und einen Sockel #9e947e,
  die ihre Höhe behalten. Oben liegt vor jedem Haus (Süden, die Seite mit
  der Tür) eine Straße #c0b490 mit Bordstein #a89c7c, das Grundstück steht
  dafür 0,9 so tief an der Nordseite. Bei 30 Grad Neigung verdecken die
  Häuser diesen Streifen hinter sich (Kritik r9), darum ist jede dritte Reihe
  und jede fünfte Spalte einer Stadt eine Gasse eine ganze Viertelkachel
  breit, wo auf beiden Seiten Häuser stehen (`tt_sub_street`; am Stadtrand
  wäre sie ein leerer Platz): Die Terrasse bleibt, gepflastert, ohne Haus.
  Rom zeigt bei 8 km so ein Straßenraster aus Blöcken statt eines
  Dachteppichs. Der Boden südlich eines Hauses liegt an der gemeinsamen Kante
  auf der tiefsten Ecke des Hauses (`tt_corners`), so zeigt die Stützmauer
  der Kamera ein ganzes Rechteck; wo der Boden seitlich fiel, war sie ein
  Dreieck (Kritik r9). In Dörfern stehen die Häuser nur auf flachen
  Vierteln. Am Fluss in einer Stadt ist das Ufer ein gepflasterter Kai
  (vorher Weizen mitten in Rom). Orte wachsen mit ihren Einwohnern (Fläche
  wie bei 9000 Menschen je km²); Städte ab 3000 Einwohnern bekommen einen
  Ring dazu, bis 0,45 km ab 7000 (`TOWN_EXTRA_KM`), sonst blieben dem
  diorama-großen Haus (ein Grundstück je 0,25 km) in Tibur drei Häuser.
  Jeder Ort der Liste von 117 n. Chr. ist eine Stadt (Hansons Stadtorte) mit
  mindestens 0,8 km Radius (`TOWN_MIN_KM`, bebaut auf etwa neun Zehnteln,
  also 3 × 3 Kacheln zu 0,5 km; Aricia mit 2600 Einwohnern war eine Kachel
  mit vier Häusern im Wald), und auf den 0,5- und 1-km-Kacheln
  bleibt der Wald eine Kachel von den Orten weg (`TOWN_CLEARING`). Im warmen
  Süden (unter 44,5° und 700 m) stehen dort von nah Olivenhaine in Reihen,
  auf jeder Rampe und jeder zweiten flachen 0,5-km-Kachel bis zwei Kacheln
  um eine Stadt (`tt_olive_grove`, kleine Laubbäume mit graugrüner Krone;
  Kritik r9: der Ring war zu einem Drittel bis zur Hälfte nackter Rasen). Die Häuser sind die Grundstücke der
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
  stehen, solange die Häuser gezeichnet werden. Mit den Stadtplänen stehen die
  fünf Bauten auf ihrem Bau im Plan, verkleinert, bis sie in seine Parzellen
  passen (`LANDMARK_PLAN_REACH`), und die Brücken entfallen.
- Die 860 Städte mit Stadtplan (docs/kit2/CITY_PLANS.md, `city_plan.gdshaderinc`,
  `_plan_lots_of`) folgen nah (Viertel- und 0,5-km-Kacheln) ihrem Plan statt der
  Ortsregel: Strassen nach Belag und Rang mit Häuserzeilen, Häuser nach
  Stockwerken zur Strasse gedreht, Plätze, Gärten, Mauern mit Toren und Türmen,
  Gräber und die öffentlichen Bauten als Modelle auf einer Parzelle
  (`voxel/roman_city.gd`).

## Bildstimmung (Urbek/Islanders, seit 29.10.2026)

Status: `implementiert`, Runden 1 bis 5. Ramon, 29.10.2026: Die Grafik soll auf das
Niveau von Urbek und Islanders. Runde 1 änderte nur Licht und Nachbearbeitung
(`landscape.gd`):

- Schatten kühl blau statt blassgrau: Umgebungslicht #b0bff5 mit 0,62 statt
  #ccccf2 mit 0,85, Sonne 2,35 statt 2,05. Besonnter Boden bleibt etwa im Ton
  der Palette, Schatten fallen auf etwa ein Fünftel statt ein Drittel davon.
  Sättigung 1,06.
- Kontaktschatten (SSAO) mit dem Zoom: Radius 2 % der Sichtbreite (0,03 bis
  0,6 km) statt fest 0,6 km, Stärke 1,1.
- Tilt-Shift wie ein Modellfoto: ein scharfes Band um den Fokus, Unschärfe zum
  oberen und unteren Bildrand (`TILT_*`), voll bis 6 km Sichtbreite, weg ab 40 km
  (seit Runde 3 nur noch schwach).
- Vignette unter der Benutzeroberfläche (`shaders/vignette.gdshader`).
- Brandung an der Meeresküste bis 2-km-Kacheln (`shore_foam` in
  `tile_terrain.gdshader`): ein weisses Band am Land, eine zweite Linie läuft
  hinaus und verblasst.
- Quadermauerwerk auf den Terrassenmauern unter den Häusern (`masonry` in
  `tile_props.gdshader`), 1 × 0,5 Diorama-Meter, blendet aus, bevor die Steine
  kleiner als einige Pixel werden.

Runde 2 und 3 (Ramon, 29.10.2026: „das sieht überhaupt nicht aus danach“,
„perspektive stimmt nicht“, „gleiche höhe der häuser“, „felder etc. alles“,
„immer mit screenshots echt vergleichen“). Jede Runde wird neben den
Urbek-Screenshots in `docs/kit1/references/screenshots/` gerendert und
gemessen (Helligkeit, Kontrast, Anteil dunkler Grüntöne). Gemessen vor Runde 3:
Urbek-Ackerland hat etwa 25 % dunkle Töne (Baumschatten, Reihen, Hecken), wir
fast keine, und ein Drittel unseres Bildes war ein einziges helles Wiesengrün.

- Kamera wie Urbek (`landscape.gd`): nah schaut sie nach Nordosten die
  Kacheldiagonale entlang (`YAW_CLOSE` 45°) und 35° nach unten
  (`PITCH_CLOSE`); bis 700 km Sichtbreite dreht sie zurück nach Norden und
  wird steiler. Die Sonne dreht mit.
- Relief nah fest 7,5-fach (`TileTerrain.NEAR_EXAGGERATION`, Ramon 31.10.2026,
  Bauplan B Schritt 1): Auf Viertel-, 0,5- und 1-km-Kacheln ist eine Stufe
  7,5-mal ihr erster Stufenschritt aus dem Bake (20 m bzw. 40 m), also 0,15 km
  bzw. 0,3 km, bei jeder Sichtbreite. Vorher war sie 0,6 Kachelbreiten und
  schrumpfte unter 16 km bis auf 40 % (`relief_for_width`): 6- bis 15-fach je
  nach Zoom. Stufen über 120 m sind 50 m (100 m) hoch und stehen darum etwa
  3-fach. Flache Rampen bekommen nah einen schwächeren Seitenton.
- Skyline (`_lot_weights` in `tile_terrain.gd`): Die hohen Lose (bis vier
  Geschosse) sammeln sich in den Stadtkernen, die niedrigen in den Dörfern.
- Grauer Steinbelag statt Creme (`C_PAVED`, `C_PLAZA`, `tt_paving`) und weiche
  Schattenkanten.
- Felder (`sim_strip`, `people_parcels.gdshader`, `people_crops.gdshader`):
  Die Parzellen wachsen zu Äckern von 3–5 × 1–2 Parzellen zusammen, Ramon zu
  Runde 3: „die felder sehn extrem müllig aus“. Ein Acker hat eine Frucht und
  ist ganz gesät oder ganz brach. Seine Platten laufen ohne Fuge durch; die
  Seiten, an denen sie das tun, liegen im B-Kanal der Parzellentextur. Die
  Reihen laufen längs des Ackers als kräftige Striche mit Höhe. Gepflügte
  Felder zeigen Furchen. Zäune stehen nur am Rand eines Ackers, und dort nur
  manchmal; beim Hof immer. Seit Runde F (30.10.2026) trägt ein weiteres
  Viertel der Ackerränder eine geschnittene Hecke aus Blöcken von etwa 2 m,
  jeder etwas höher oder tiefer als der nächste (Varro, rust. 1,14, nennt
  Hecke, Holzzaun, Graben und Mauer als römische Feldgrenzen). Die Dorfwege
  und Feldwege haben einen Rand aus hellerem Gras, ein Drittel so breit wie
  der Weg, wie die Strassen bei Urbek. Runde G: Ein Block aus 2 × 2
  Weideparzellen ist zu 45 % eine Koppel, halb mit Hecke, halb mit
  Trockenmauer (maceria) ringsum und einem Block als Tor; die Schafe weiden
  drinnen und draussen wie bisher. Die Strohplatten sind dünner und haben eine
  feine Körnung. 3–6 × 2–3 Parzellen (Runde 4) machten Bäume und Häuser
  winzig. Runde J (30.10.2026): Jenseits der Feldfrüchte (8 bis 40 km)
  liegen dieselben Äcker flach im Gelände (`sim_far_field`): die Brache als
  Strohfläche, ein gesäter Acker mit seiner Frucht und Reife in den Farben
  der Platten von nah, drei Reihen je Parzelle längs des Ackers, solange sie
  mindestens 2–4 Pixel auseinander liegen (darunter die Mischfarbe), und ein
  Grasrand von `SLAB_GAP` je Seite, mindestens ein halbes Pixel. Vorher nahm
  ein Quadrat aus 3 × 3 Parzellen eine eigene flache Farbe, die Brache war
  Wiese: Beim Herauszoomen über 8 km mischten sich die Felder neu, und
  Nachbarn flossen zu Flecken zusammen. Runde O (31.10.2026, Ramon:
  «Beides: Reihen und Weiden»): Die Pflanzen standen als grosse, glatte
  Klötze in einem regelmässigen Raster, wie Ziegelsteine; bei 3 km war das
  Bild zu 53 % hellgrün (Urbek 21 %) und zeigte 6 % Erde (Urbek 18 %). Eine
  Reihe ist jetzt eine niedrige, schmale Rippe über die ganze Feldlänge,
  ihre Voxel (`VOX_M` 0,35 m) in zwei Tönen und hie und da einer weg, mit
  bis zu sechs Buckeln je Reihe (`CROP_LUMPS`) aus zwei bis vier Voxeln,
  breiter und doppelt so hoch, je nach Stand der Frucht (Keimling 35 %,
  grün 50 %, reif 50 %, Bohnen 65 %). Die Reben bleiben, wie sie sind.
  Das Netz der Felder hat 57 % mehr Ecken (2640 statt 1680 je Parzelle).
- Weiden (Runde O, `sim_pasture`): Das offene Land, das die Höfe auf ihren
  Feinkacheln frei lassen (Parzelle ohne Feld, `SIM_P_OPEN` und
  `SIM_P_FARMED`), liegt in Weideblöcken wie die Felder in Äckern
  (`sim_strip`, verbunden in `people_parcels.gdshader`): kurz abgeweidet
  (etwas heller), Heuwiese mit Mähstreifen längs des Blocks (Cato, agr. 1,7,
  nennt das pratum an zweiter Stelle der Bodennutzungen) oder raue Weide
  (dunkler, mit Büscheln). Um jeden Block läuft ein Rain aus höherem,
  dunklerem Gras von der Parzellenlinie 0,6 m nach innen, auf den
  `people_crops.gdshader` niedrige Blöcke und hie und da einen Busch setzt;
  zwei Blöcke nebeneinander teilen sich ihren Rain. Die Koppeln aus Runde G
  bleiben und haben keinen Rain. Vorher war das eine glatte Wiese, 40 % des
  3-km-Bilds glatt (Urbek 15 %). Die Sim kennt keine Weide: Es ist das Land
  ohne Feld, gezeichnet als Gemeinweide des Dorfs wie schon die Schafe.
- Feldwege (`sim_track_between`): Durchs Ackerland läuft auf jeder dritten
  Loslinie (alle 1,5 km) ein brauner Feldweg, mit Lücken. Die Äcker halten
  Abstand wie bei den Dorfwegen.
- Wiese (`tt_grass`): nah ein dunkleres, nicht satteres Grün mit dunklen
  Grasbüscheln und vereinzelten Blumen. Flecken wirkten weich wie eine Textur
  (Runde 3) und kantig wie Tarnmuster (Runde 4). Das Muster blendet aus,
  bevor es flimmern würde.
- Einzelbäume (`tt_scatter_free` in `tile_props.gdshaderinc`) auf Rampen und
  auf den Parzellen, die die Höfe als Weide liegen lassen, nie auf Feldern
  oder Hoflosen. Sie sind etwa so hoch wie ein eingeschossiges Haus und alle
  Bäume fast gleich gross wie bei Urbek. Kleine Büsche lasen sich als
  Setzlinge. Dafür setzt `people_dots.gd` die Feld- und Losdaten
  auch auf den Platzierungsdurchgang.
- Städte: Ein Stadtviertel ohne Los (an den Landmarken, die kleinen Plätze im
  Kern) ist ein Garten mit Rasen, Schnitthecke, Zypressen, Pinien und
  Laubbäumen (`tt_sub_garden`) statt einer leeren Pflasterfläche.
  Strassenblöcke haben eine dunkle Basaltfahrbahn zwischen Gehsteigen aus
  Travertin mit Bordstein.
- Tilt-Shift nur noch angedeutet, denn Urbek hat praktisch keinen.
- Werkstätten (Ramon: „alles sichtbar grafisch“): Ein Dorfhaus eines
  Handwerkerhaushalts zeigt seine Werkstatt ausserhalb des Zauns
  (`_workshop` in `scripts/voxel/farmhouse.gd`, `people_houses.gdshader`).
  Der Schmied hat einen Unterstand mit Esse, glühender Kohle, Kamin, Amboss
  und Werkzeugbank, der Töpfer einen Brennofen und Krüge, der Weber einen
  Webstuhl, eine Wäscheleine mit Tüchern und Wollballen. Je mehr Ware die
  Händler abnehmen (`busy`), desto mehr Werkzeug, Krüge, Tücher und Wolle
  stehen herum. Die Daten stehen im Hausdatensatz (`rec.w`: craft << 22 |
  key << 8 | busy, aus PR #49). Ohne sie bleibt die Werkstatt verborgen.
- Höfe im Bau: Ein bestellter Hof ist ein eigener Hausdatensatz mit
  negiertem Dorfcode (`rec.z < 0`) und dem gebauten Anteil in `rec.w & 255`
  (PR #49, eingeschaltet mit `people.show_site_houses(true)` in
  `people_dots.gd`). `people_houses.gdshader` zeichnet das Haus bis zur
  gebauten Höhe, ohne Dach, Bäume, Werkstatt und Heuhaufen, mit einem Gerüst
  aus Stangen und Brettern (`_scaffold` in `farmhouse.gd`). Platziert wird er
  wie das spätere Haus (`dot_place`), sein Los bleibt frei von Feldern.
- Bauen mit Anno-Gefühl (Ramon: „Strassen werden riesig“): Die gebauten
  Strassen sind schmale Kiesbänder im Massstab der Häuser, vier Diorama-Meter
  breit statt einer ganzen Sim-Kachel (`scripts/road_view.gd`,
  `shaders/road.gdshaderinc`). Das Baumenü findet den Weg und glättet ihn; der
  Knoten zeichnet ihn nur (`set_road(id, punkte, fortschritt, vorschau,
  gesperrt)`, `remove_road(id)`). Jede Strasse liegt zweimal: der Rand in
  Feldweg-Braun und darüber die etwas schmalere Fahrbahn mit zwei Spurrillen.
  An Kreuzungen deckt so jede Fahrbahn die Ränder der anderen. Der
  ungebaute Teil ist abgesteckte Erde mit Pflöcken, an der Arbeitsstelle
  frisch umgegraben. Die Vorschau ist durchsichtig grün oder rot. Das Band
  liegt im Vertex-Shader auf dem Gelände, wie das Gelände es zeichnet
  (`dot_ground_level`), und rückt ein paar Meter zur Kamera, damit es auf
  Rampen nicht einsinkt.
- Hof-Geist (`scripts/voxel/farmhouse_ghost.gd`): Am Cursor steht genau das
  Hofhaus, das auf diesem Los entstehen wird. Es hat dieselbe Bauform,
  Drehung, Spiegelung und Grösse wie in `people_houses.gdshader`
  (dieselben Hashes über das Los). Es ist durchsichtig und grün oder rot
  getönt, ohne Bäume, Heuhaufen, Werkstatt und Gerüst.
- Gebaute Höfe an der gewählten Stelle: Ein Hausdatensatz mit dem Code
  `DOT_AT_LOT` (12288, beim Bauplatz negativ) steht genau auf dem Los unter
  `rec.xy` (`dot_place`), statt sich im Dorf einen Platz zu suchen. Die Sim
  setzt den Code, sobald sie die Stelle aus dem Auftrag kennt.

## Fernsicht (Kacheln bis zur ganzen Karte)

Ramon, 28.10.2026: „Kachel-Look konsequent bis immer“. Es gibt keine weiche
Reliefkarte mehr; auch ganz draußen (32-km-Kacheln, die ganze Kit-1-Karte) gelten dieselben
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
| Kachel je Zoomstufe | 0,25 (Viertel, `SUB_KM`) / 0,5 / 1 / 2 / 4 / 8 / 16 / 32 km echt = 10,5 m … 1340 m Diorama (`LEVELS`) |
| Höhe | nah eine Stufe = 20 / 50 / 60 m echt (Tiefland, Hügel, Gebirge; bei 1-km-Kacheln das Doppelte), weiter draußen die steigende Skala `LEVEL_STEPS_M` (150 bis 600 m je Stufe) |
| Haus | ein römisches Grundstück von 10 × 10 m Diorama (`HOUSE_M`, 238 m Welt), eins je Viertelkachel, vier je 0,5-km-Kachel; gezeichnet bis 4-km-Kacheln |
| Wahrzeichen Roms | Modelle der römischen Stadt im Diorama-Maßstab wie die Häuser (Kolosseum 8 × 7 Grundstücke auf 4 × 4 Blöcken von 0,5 km) |
| Baum | 8 m Diorama (`TREE_M`, Urbek: 5–8 m, so hoch wie ein zweistöckiges Haus), nur auf Stufe 0 auf den Waldkacheln (auf Stufe 1 waren sie ein Sprenkel über dem Relief); weiter draußen sind Waldkacheln dunkelgrün. Laubbäume mit runder Voxelkrone (Kern, Gürtel auf vier Seiten, flache Kappe), dunkler und satter als die Wiese wie bei Urbek gemessen (Oberseite etwa #458d33, Seiten #29521f); Zypressen #2f5a2c wie an den Höfen |
| Nächster Zoom | 4 km echt Sichtbreite, etwa 17 Häuser nebeneinander |

## Aufbau

- `tools/build_tile_terrain.py` backt `artifacts/render-data/tile-terrain-r1/`
  (etwa 6 Minuten): Bewuchs, Meeresabstand und Seespiegel (2-km-Knoten), Wasser-
  und Ortsklassen je Zoomstufe (`cells-L*.png`, Flüsse bereinigt; allein neu
  mit `--cells-only`, die Orte allein mit `--towns-only`, etwa 20 Sekunden), Höhe und
  begrenztes Relief (`height.r16f`, `relief.r16f`), die Wasserhülle
  (`shore.r16f`), die Eckstufen der fernen Zoomstufen (`levels-L*.png`;
  allein neu mit `--levels-only`, etwa 1 Minute), die der nahen aus den
  Terrain Tiles (`levels-L0.png`, `levels-L1.png`; allein neu mit
  `--near-only`, einzeln mit `--level=0` oder `--level=1`, etwa 7 Minuten
  für beide, der erste Lauf lädt 1298 Kacheln, 93 MB; die Stufenregel, eine
  Stufe je Kachel zu allen acht Nachbarn, rechnet `unit_envelope` in zwei
  Durchläufen über die Karte statt in einem je Reliefstufe, und das Öffnen und
  Schließen der Stufen läuft blockweise nur bis zur höchsten Stufe des Blocks)
  und die Landschaft jeder Kachel
  je Zoomstufe (`ground-L*.png`, `ground_classes`: Bodenbedeckung und Höhe an
  der Kachelmitte, ein wenig Rauschen in km macht aus Anteilen Flecken dieser
  Größe, einzelne Kacheln werden ihren Nachbarn angeglichen; weiter draußen
  sind die Daten stärker weichgezeichnet und das Rauschen schwächer, und
  Lichtungen gibt es nur bis 2-km-Kacheln, so stehen auf der Europakarte
  ruhige große Landschaften statt Flecken; fern bleibt nur dichter Wald
  Wald (`WOOD_MIN`: ab 1-km-Kacheln braucht ein Wald 0,66 bis 0,92
  Waldanteil statt 0,45; die römische Bedeckung trägt Wald auf über der
  Hälfte Italiens, fern las das als dunkle Tarnfarbe; in hügeligem Land
  verschiebt die Höhe der Kachel die Schwelle, siehe oben: Mittelitalien hat
  bei 70 km etwa 38 % Wald an den Hängen, bei 120 km 30 %), so
  liest das Land hell mit dunklen Wäldern wie die gemalte Karte, und
  die Grenze zum Nadelwald im Norden wandert um einige Breitengrade statt
  als Gerade durch Russland zu laufen; allein neu mit
  `--ground-only`, etwa 11 Minuten und 5 GB Speicher, davon 6 für die 0,5-km-Kacheln; die
  Höhen für Fels, Schnee und Wald kommen aus denselben Terrain Tiles wie
  die nahen Stufen). Braucht numpy, Pillow und scipy. Eingaben sind im Manifest mit Hash geführt.
- `app/scripts/tile_terrain.gd` lädt die Daten, wählt die Zoomstufe und
  verschiebt die Patches. Ein MultiMesh mit bis zu 320 × 320 Kacheln, davon
  gezeichnet nur die um die Sicht (`draw_n`: die sichtbare Fläche mal 1,25 und
  so weit darüber hinaus, wie hohes Land noch ins Bild ragen oder Schatten
  hineinwerfen kann); ganz nah sind das ein paar Tausend statt 100 000
  Kacheln. Die Eckstufen rechnet der 2D-Pass weiter für den ganzen Patch vor.
  Weit draussen ist die Stufe mindestens so grob, dass der Patch den oberen
  Bildrand überspannt (1,1 Sichtbreiten auf der geneigten Karte), darum
  kommen die 32-km-Kacheln ab etwa 4500 km. Ein MultiMesh für die Bäume
  aller Arten und eines je Hausmodell (bis 100 × 100 Kacheln);
  ändert sich beim Zoomen nur ihre Zahl, stellt `_apply_prop_count` nur die
  Zahlen um (vorher baute jede Änderung die ganze Stufe neu, mit 1 MB
  Stufenfenster und dem Viertelpass: beim Zoomen ruckelte es).
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
- Leistung: Der Prop-Patch ist nur so groß wie der sichtbare Boden, dazu hohes
  Land wie beim Gelände und je Seite zweimal die höchste Figur (ein hohes Haus
  knapp unter dem Bildrand ragt im 30-Grad-Blick 1,7-mal seine Höhe ins Bild,
  sein Schatten ähnlich weit), höchstens `PROP_SPAN` Sichtbreiten, und liegt in
  seiner Mitte. Jede Instanz kostet Vertex-Arbeit, ob sie etwas zeigt oder
  nicht, und das für jede Baumart; bis 29.10. war er bis 2,5-mal so groß wie
  der sichtbare Boden. Alle Baum- und Hausmodelle sind indiziert (jede Ecke
  einer Fläche wird einmal gerechnet statt zweimal für zwei ihrer Ecken), ein
  Drittel weniger Eckpunkte bei gleichen Dreiecken. Die Hausmodelle laufen nur
  über die Stadtkacheln des Patches: `towns-L*.i32` aus dem Bake listet die
  Stadtkacheln jeder Stufe (nach Zeile sortiert, `(j · breite + i) · 4 + Klasse`),
  `_update_town_list` sucht bei jedem Schritt des Patches die darin liegenden
  heraus und legt sie in `town_tex`. Vorher lief jedes der 16 Hausmodelle und die
  Terrasse über alle 100 × 100 Kacheln mit neun Plätzen, also 90 000 Häuser für
  ein paar Dutzend Stadtkacheln: auf einem M3 Pro 18 Bilder pro Sekunde zwischen
  70 und 700 km (Messtour 29.10.2026). Ein leerer Platz rechnet im Vertex-Shader
  nur noch, ob er etwas zeigt. Ab
  10 km Sichtbreite gibt es Low-Poly-Bäume und grobe Häuser ohne Schatten
  (`PROP_LOW_KM`), volle Hausmodelle nur bis 5 km (`PROP_DETAIL_KM`). Die
  Bäume aller Arten sind ein einziges Mesh aus Einheitsblöcken
  (`tree_template`), das der Shader je Platz nach der Blocktabelle seiner Art
  streckt und färbt (`tree_table`: Laubbaum, Nadelbaum, Zypresse, Pinie, je
  bis fünf Blöcke, der erste der Stamm ohne Deckel): ein Platz rechnet seine
  Eckpunkte einmal statt einmal je Art. Vorher lief jede der vier Arten als
  eigenes MultiMesh über alle Plätze, und die Bäume waren zwischen 5 und 30 km
  über die Hälfte eines Bildes (Messtour 29.10.: 19 ms mit, 9,4 ms ohne
  Bäume). Die
  Kacheln werfen keine Schatten, nur Häuser, Bäume und Bauwerke: die Seitentöne
  tragen das Relief wie in SimCity 2000. Eine steile Viertelrampe, die von der
  Sonne weg schaut, beschattete sich selbst und teilte ihre Kachel in einen
  hellen Streifen und ein fast schwarzes Dreieck (Kritik r16: #3b3741 am Fels,
  lila am Schnee); fern zeichnete die grobe Schattenkarte nur Striche an den
  Stufen.
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
nie (Ramon, 28.10.2026: „kein rotieren“). Ganz draussen (8000 km) steht sie fast senkrecht
über der ganzen Kit-1-Karte (`data/region.json`: −11 bis 46° Ost, 21 bis 58° Nord,
von Irland bis zum Kaspischen Meer und von der Ostsee bis Oberägypten); die
Kamera bleibt auf dieser Karte und rückt sie ganz draussen in die Mitte
(bis 29.10. hielt sie die Sicht auf Europa, 34 bis 60° Nord, und schnitt
Afrika, Ägypten und die Levante ab). Das Bild bleibt immer auf den
Geländedaten (18 bis 61° Nord): `_reach` rechnet aus Neigung und Bildwinkel,
wie weit der sichtbare Boden nach oben und unten reicht, und `max_width`
hält die Sicht so schmal, dass sie von oben bis unten auf die Daten passt,
etwa 7800 km im 16:9-Fenster, 7000 km bei 16:10 (sonst lief der Datenrand
als gerader Schnitt durch Skandinavien). F5–F7 steuern das Wetter. Startoptionen:
`--view=lon,lat,breite_km`, `--snapshot=pfad.png`, `--snapshot-frames=n`,
`--views=lon,lat,breite;…` mit `--snapshot=ordner` (ein Bild je Ansicht),
`--bench=n` (misst n Bilder nach dem Vorlauf und gibt die mittlere Bildzeit aus),
`--tour=ergebnis.json` (`tour_bench.gd`: fliegt Bild für Bild denselben Weg,
Rom nah, die ganze Karte, Alexandria, Antiochia, die Levante, Athen, und
schreibt Bildzeiten, die schlimmsten Bilder mit dem, was das Gelände in ihnen
änderte, und die Pipeline-Kompilierungen; `--tour-passes=n`, Vorgabe 2;
`--tour-hide=trees,houses,terrain,landmarks,people,shadows` lässt das weg,
um zu sehen, was es kostet; `people-draw` zeichnet die Menschen nicht,
`people-process` hält nur ihre Arbeit pro Bild an).

## Offen

- macOS-Paketierung des Tile-Geländes.
- Leistungsmessung auf dem Mac nach dem Umbau (vorher 142 ms bei 25 km Sichtbreite).
- Straßen außerhalb der Städte (die Stadtmauern zeichnen jetzt die Stadtpläne).
