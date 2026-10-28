# Tile-Gelände (SimCity 2000 meets EU5)

Status: `implementiert`, seit 27.10.2026 das einzige Gelände der App. Das Wetter
(`app/scripts/weather/`, `app/shaders/weather_*`, `cloud_layer`) ist davon
unabhängig und unverändert.

## Geländeregeln (SimCity 2000)

- Die Welt besteht aus quadratischen Kacheln. Jede **Ecke** hat eine Höhenstufe,
  benachbarte Kacheln teilen ihre Ecken. Dadurch ist das Land eine durchgehende
  Fläche aus flachen Kacheln und Rampen, wie in SimCity 2000 (XTER-Formen
  00–0D: jede Ecke liegt auf der Kachelhöhe oder eine Stufe darüber).
- Benachbarte Ecken liegen **höchstens eine Stufe** auseinander. Das sichert
  das gebackene Relief (`sc2k_relief`), das auf `RELIEF_SLOPE` m/km begrenzt ist.
- Eine Stufe ist **0,6 Kachelbreiten** hoch (SimCity 2000: 12 px Stufe auf einer
  32 × 16 px Kachel). Eine Stufe entspricht `RELIEF_SLOPE × Kachelbreite` echten Metern.
- Höhen sind weltweit **3,75-fach** überhöht (`HEIGHT_EXAGGERATION`, Kit 1 K06,
  geändert am 27.10.2026). Daraus folgt `RELIEF_SLOPE` = 160 m/km: wenige, lange
  Terrassen wie in SimCity 2000 statt vieler schmaler Streifen.
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
  ein fünftes Wandstück steht als Kante auf der Diagonale. Weit draußen
  verschwindet die Kante mit den Stufen, die Uferlinie folgt dann den Wasserknoten.
  Kacheln werden an der Diagonale geteilt, deren Ecken näher beieinander liegen
  (wie SimCity 2000): eine einzelne gehobene Ecke ergibt ein flaches und ein
  geneigtes Dreieck statt einer Falte. `MOUNTAIN_SLOPE` erlaubt im Hochgebirge
  (Mittel über 10 km ab 500 m, voll ab 1300 m) eine steilere Rampe, steht aber
  auf 1 × `RELIEF_SLOPE`: auch Gebirge folgen der Ein-Stufen-Regel.
  Im Land gibt es keine Klippen. Flüsse sind schmale Bänder in der Landkachel
  (mindestens Bootsbreite), Kurven schneiden die Ecke diagonal.
- Optik: Kacheln sind einfarbig ohne Muster, wie in SimCity 2000. Rampen haben
  zwei klare Töne (Sonnenseite hell, Schattenseite dunkel). Schaumlinie an der
  Küste, Fels ab etwa 1100 m und Schnee ab etwa 1600 m (geglättete Höhe),
  Städte mit Straßenraster und Mauer am Kern.

## Fernsicht (Reliefkarte, EU5)

Zwischen 20 und 45 km Sichtbreite blendet `relief_smooth` von den Kachelstufen
zu einer glatten Reliefkarte über: Ecken nicht mehr auf Stufen gerundet,
Normalen je Pixel, kein Kachelraster. Weil die Höhendaten nur ein 2-km-Raster
haben, legt der Shader in den Bergen Grate und Rinnen darunter, die hangabwärts
laufen (Phacelle-Rauschen, `alpine_detail`). Steile Bergflanken werden Fels,
die Schattierung hat warme Sonnen- und kühle Schattenseiten. Licht: wenig
Umgebungslicht und Filmic-Tonemapping, damit die Farben nicht auswaschen.

## Maßstab

Kit-2-Maßstab (`docs/kit2/SCALE.md`): Längen 1:23,8 gegenüber der echten Welt
(`DIORAMA_LAENGE`), Häuser und Bäume in echter Größe. Die Welteinheit bleibt der
echte Kilometer, ein Diorama-Meter sind also 0,0238 Welteinheiten.

| Größe | Wert |
|---|---|
| Fläche | 1 Welteinheit = 1 echter km = 42 m Diorama, mapping-v1 |
| Kachel je Zoomstufe | 0,5 / 1 / 2 / 4 / 8 / 16 km echt = 21 m … 670 m Diorama (`LEVELS`) |
| Höhe | 3,75-fach, eine Stufe = 80 / 160 / 320 / 640 / 1280 / 2560 m echt |
| Haus | 10 m Diorama (`HOUSE_M`), auf Stufe 0 und 1 gezeichnet |
| Baum | 12 m Diorama (`TREE_M`), auf Stufe 0 und 1; weiter draußen zeigt der Boden den Wald |
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
  Baumarten, die im Ausschnitt nicht wachsen können, werden ausgeblendet.
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
