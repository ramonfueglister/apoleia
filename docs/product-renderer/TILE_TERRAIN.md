# Tile-Gelände (SimCity 2000 auf jeder Zoomstufe)

Status: `implementiert`, seit 27.10.2026 das einzige Gelände der App. Das Wetter
(`app/scripts/weather/`, `app/shaders/weather_*`, `cloud_layer`) ist davon
unabhängig und unverändert.

## Geländeregeln (SimCity 2000)

- Die Welt besteht aus quadratischen Kacheln. Jede **Ecke** hat eine Höhenstufe,
  benachbarte Kacheln teilen ihre Ecken. Dadurch ist das Land eine durchgehende
  Fläche aus flachen Kacheln und Rampen, wie in SimCity 2000 (XTER-Formen
  00–0D: jede Ecke liegt auf der Kachelhöhe oder eine Stufe darüber).
- Benachbarte Ecken liegen bis zu 2-km-Kacheln **höchstens eine Stufe**
  auseinander. Das sichert das gebackene Relief (`sc2k_relief`), das auf
  `RELIEF_SLOPE` m/km begrenzt ist. Weiter draußen sind steilere Rampen erlaubt.
- Eine Stufe ist **0,6 Kachelbreiten** hoch (SimCity 2000: 12 px Stufe auf einer
  32 × 16 px Kachel). Bis 2-km-Kacheln entspricht eine Stufe `RELIEF_SLOPE ×
  Kachelbreite` echten Metern, darüber wächst sie nur mit (Kachel / 2 km)^0,4.
- Höhen sind bis 2-km-Kacheln **3,75-fach** überhöht (`HEIGHT_EXAGGERATION`,
  Kit 1 K06, geändert am 27.10.2026), weiter draußen stärker (bis 13-fach bei
  16-km-Kacheln), damit Gebirge auf der Europakarte mehrere Stufen behalten.
  Daraus folgt `RELIEF_SLOPE` = 160 m/km: wenige, lange Terrassen wie in
  SimCity 2000 statt vieler schmaler Streifen.
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
- Optik: Jede Kachel hat **eine Farbe**, wie in SimCity 2000, aus Bewuchs und
  Höhe in ihrer Mitte (Datenstufe passend zur Kachelgröße), mit einer kleinen
  Abweichung von Kachel zu Kachel. Rampen haben zwei klare Töne (Sonnenseite hell,
  Schattenseite dunkel). Fels ab etwa 1100 m, Schnee ab etwa 1600 m. Am Meer
  ein Sandsaum (ein Viertel Kachel) an den Wasserseiten und auf der Schnittdiagonale.
  Das Meer hat einen hellen Uferstreifen, der aus den Kachelecken entsteht (eine
  Kachel breit, folgt Treppe und Diagonalen genau), und wird weiter draußen nach
  Abstand in Kacheln dunkel. Städte mit Straßenraster und Mauer am Kern.

## Fernsicht (Kacheln bis Europa)

Ramon, 28.10.2026: „Kachel-Look konsequent bis immer“. Es gibt keine weiche
Reliefkarte mehr; auch ganz draußen (16-km-Kacheln, ganz Europa) gelten dieselben
Regeln wie nah. Wo keine Baum- und Hausmodelle mehr stehen (ab 2-km-Kacheln),
zeichnet der Shader Wald als runde Baumkronen im Raster und Städte als rote
Dächer mit Sonnen- und Schattenseite, so wie die Modelle nah. Werden diese Muster
kleiner als ein paar Pixel, gehen sie in ihre Mittelfarbe über. Damit Gebirge
draußen nicht zu einer Stufe zusammenfallen, wächst eine Stufe ab 2-km-Kacheln
langsamer als die Kachel (`FAR_POW`), und das Relief für die Eckhöhen wird
weniger weichgezeichnet (`RELIEF_BLUR`). Licht: wenig Umgebungslicht und
Filmic-Tonemapping, damit die Farben nicht auswaschen.

## Maßstab

Kit-2-Maßstab (`docs/kit2/SCALE.md`): Längen 1:23,8 gegenüber der echten Welt
(`DIORAMA_LAENGE`), Häuser und Bäume in echter Größe. Die Welteinheit bleibt der
echte Kilometer, ein Diorama-Meter sind also 0,0238 Welteinheiten.

| Größe | Wert |
|---|---|
| Fläche | 1 Welteinheit = 1 echter km = 42 m Diorama, mapping-v1 |
| Kachel je Zoomstufe | 0,5 / 1 / 2 / 4 / 8 / 16 km echt = 21 m … 670 m Diorama (`LEVELS`) |
| Höhe | eine Stufe = 80 / 160 / 320 / 422 / 557 / 735 m echt, 3,75- bis 13-fach überhöht |
| Haus | 10 m Diorama (`HOUSE_M`), auf Stufe 0 und 1 gezeichnet |
| Baum | 12 m Diorama (`TREE_M`), auf Stufe 0 und 1; weiter draußen zeichnet der Shader Baumkronen |
| Nächster Zoom | 4 km echt Sichtbreite, etwa 17 Häuser nebeneinander |

## Aufbau

- `tools/build_tile_terrain.py` backt `artifacts/render-data/tile-terrain-r1/`
  (etwa 6 Minuten): Bewuchs, Meeresabstand und Seespiegel (2-km-Knoten), Wasser-
  und Ortsklassen je Zoomstufe (`cells-L*.png`), Höhe und begrenztes Relief
  (`height.r16f`, `relief.r16f`) und die Wasserhülle (`shore.r16f`). Eingaben sind im Manifest mit Hash geführt.
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
- `app/scripts/tile_prop_meshes.gd` baut die Kachelvorlage, die facettierten
  Low-Poly-Bäume (flache Normalen, Farbverlauf nach oben) und die Häuser.
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
