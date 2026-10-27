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
- Höhen sind weltweit **7,5-fach** überhöht (`HEIGHT_EXAGGERATION`, Kit 1 K06,
  geändert am 27.10.2026). Daraus folgt `RELIEF_SLOPE` = 80 m/km.
- Ecken am Meer liegen auf Meereshöhe, die Küste läuft also als Rampe ins Wasser.
  Ecken an einem See liegen auf dem Seespiegel, auch das Seeufer ist eine Rampe.
  Im Land gibt es keine Klippen. Flüsse sind schmale Bänder in der Landkachel
  (mindestens Bootsbreite), Kurven schneiden die Ecke diagonal.
- Optik: Kacheln sind einfarbig ohne Muster, wie in SimCity 2000. Rampen haben
  zwei klare Töne (Sonnenseite hell, Schattenseite dunkel). Schaumlinie an der
  Küste, Fels ab etwa 1100 m und Schnee ab etwa 1600 m (geglättete Höhe),
  Städte mit Straßenraster und Mauer am Kern.

## Fernsicht (Reliefkarte, EU5)

Zwischen 25 und 55 km Sichtbreite blendet `relief_smooth` von den Kachelstufen
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
| Höhe | 7,5-fach, eine Stufe = 40 / 80 / 160 / 320 / 640 / 1280 m echt |
| Haus | 10 m Diorama (`HOUSE_M`), auf Stufe 0 und 1 gezeichnet |
| Baum | 12 m Diorama (`TREE_M`), auf Stufe 0 und 1; weiter draußen zeigt der Boden den Wald |
| Nächster Zoom | 4 km echt Sichtbreite, etwa 17 Häuser nebeneinander |

## Aufbau

- `tools/build_tile_terrain.py` backt `artifacts/render-data/tile-terrain-r1/`
  (etwa 6 Minuten): Bewuchs, Meeresabstand und Seespiegel (2-km-Knoten), Wasser-
  und Ortsklassen je Zoomstufe (`cells-L*.png`), Höhe und begrenztes Relief
  (`height.r16f`, `relief.r16f`). Eingaben sind im Manifest mit Hash geführt.
- `app/scripts/tile_terrain.gd` lädt die Daten, wählt die Zoomstufe und
  verschiebt die Patches. Ein MultiMesh mit 320 × 320 Kacheln, fünf MultiMeshes
  für Laubbäume, Nadelbäume, Zypressen, Pinien und Häuser (100 × 100 Kacheln).
- `app/shaders/tile_terrain.gdshaderinc` enthält die Kachelregeln, die
  `tile_terrain.gdshader` (Oberseite und Wände) und `tile_props.gdshader`
  (Platzierung der Bäume und Häuser) gemeinsam nutzen. Die gesamte Geometrie
  entsteht im Vertex-Shader; die CPU spiegelt nur die Bodenhöhe für Kamera und Wetter.
- `app/scripts/tile_prop_meshes.gd` baut die Kachelvorlage, die facettierten
  Low-Poly-Bäume (flache Normalen, Farbverlauf nach oben) und die Häuser.
  Pinien stehen nur im Süden (unter 44,5° Breite, unter 700 m), Bäume enden
  bei 1400 m.
- `app/scripts/landscape.gd` enthält Kamera, Eingabe, Licht und Wetteranbindung.

## Bedienung

Mausrad oder Pinch zoomt zum Cursor, Ziehen oder WASD/Pfeile verschiebt, Q/E dreht
um 90°, +/− zoomt. F5–F7 steuern das Wetter. Startoptionen:
`--view=lon,lat,breite_km[,drehungen]`, `--snapshot=pfad.png`, `--snapshot-frames=n`.

## Offen

- macOS-Paketierung des Tile-Geländes.
- Leistungsmessung auf dem Mac (Patch 320² Kacheln, fünf Prop-MultiMeshes mit je 90.000 Slots).
- Küsten und Seeufer bleiben in der Fernsicht Kacheltreppen.
- Straßen außerhalb der Städte, Stadtmauer als echte Geometrie.
