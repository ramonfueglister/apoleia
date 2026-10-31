# Übergabe: Massstab und Wahrzeichen (Stand 31.10.2026, 18:40)

Für die nächste Claude-Sitzung, die am Thema «Grössenverhältnisse» weiterarbeitet.
Kurz: Die Diorama-Regel ist entschieden und für Rom gebaut (#125). Ramon hat
um 18:36 entschieden, dass **alle anderen Städte** ihre grossen Bauten ebenfalls
nach der Regel zeigen. Das ist noch nicht gebaut. Danach folgt Schritt 2 für Rom.

Verbindliche Detailquelle bleibt [`docs/kit2/SCALE.md`](../kit2/SCALE.md)
(Grundregel, Massstabstabelle, Abschnitt «Wahrzeichenregel (S136)»). Entscheide:
`docs/kit2/decisions.md` S51, S136. Stadtpläne: `docs/kit2/CITY_PLANS.md`.

## 1. Die Regel (S136, entschieden 31.10. 17:55, «finde ich gut»)

Das Spiel ist ein **Diorama**: «das riesige Rom in einer Mini-Variante, die
begreifbar ist, alles massstäblich angepasst, zugleich die Grössenverhältnisse
adaptiert wiedergeben» (Ramon 17:23).

- Weltkoordinaten sind echte Kilometer. Menschliches (Figuren, Häuser, Tiere)
  wird mit `DIORAMA_KM_PER_M` = 0,0238 gezeichnet (Faktor 23,8; `tile_terrain.gd`).
  Bevölkerung geteilt durch 566,5. Ein Hauslos = 10 m = 0,25 km Parzelle.
- **Echt gross bleiben:** Häuser (9 bis 16 m hoch, Los 100 m²), Menschen,
  Tiere, Türen, Bögen, Stufen, Sitze. Es gibt **weniger Häuser**, nicht kleinere.
- **Wahrzeichen werden verdichtet** (selektive Verdichtung wie im Modellbau und
  auf Touristenkarten; Literatur: https://claude.ai/artifact/1gWXz2MKsPEHxHTvaNSh3U):
  - Fläche = 100 m² × (A / 100 m²)^(1/3), Seitenverhältnis bleibt.
  - Höhe über 16 m = 16 m × (h / 16 m)^(1/3); was echt unter 16 m ist, bleibt echt.
  - Form, Geschosszahl, Bogenreihen bleiben vom echten Typ.
  - Auf den Rängen sitzen so viele Figuren, wie die Sim Nutzer schickt; der Rest bleibt leer.
- Ergebnis: Jedes grosse Wahrzeichen steht über dem höchsten Haus, und die echte
  Reihenfolge untereinander bleibt.

Abgelehnte Wege (nicht wieder vorschlagen): gemischte Regeln (16:33, 16:47);
Nutzerregel ÷566,5, Kolosseum kleiner als Haus (17:16: «das Kolosseum muss auch
in der Spielwelt massstäblich grösser sein als das Haus»); Holzarena 3,5 m (11:46).

## 2. Stand Rom (PR #125, gemergt 31.10. 18:27, main 47ee919)

| Bau | echt | im Spiel | Höhe echt → Spiel | Sitzende | Plan Rom |
|---|---|---|---|---|---|
| Kolosseum | 188 × 156 m (Oval) | 30,7 × 25,4 m | 48 → 23 m | 88 | 4 × 3 Parzellen |
| Caracalla-Thermen | 214 × 110 m | 34,7 × 17,5 m | Kuppel 38,5 → 21,4 m | 3 Badende | 4 × 2 |
| Marcellustheater | Ø 130 m | Ø 28 m, Bühne gegen Westen | 32,6 → 20,3 m | 26 | 3 × 4 |
| Circus Maximus | 621 × 118 m | 69 × 13 m, Obelisk 18 m | 28 → 19,3 m | 265 | 8 × 2 |

Code:
- `app/scripts/voxel/roman_arena.gd`: Kolosseum (Konstanten OUT_A/OUT_B, ROWS, STOREYS, SEATS).
- `app/scripts/voxel/roman_landmarks.gd`: `circus()`, `theatre()`, `baths()`.
- `app/scripts/voxel/roman_buildings.gd`: `LANDMARKS`, `DIORAMA`-Liste, `_code_arena`, `_landmark_grid`.
- `app/scripts/tile_terrain.gd`: `LANDMARKS` (kit:arena, kit:circus, kit:theatre),
  Zeichnen über `MeshInstance3D` je Eintrag, eingepasst mit `LANDMARK_PLAN_REACH`.
- `tools/city_plans.py`: `USER_SIZED_M` (Parzellenbedarf der vier Bauten),
  `ruled_model()` (gilt **nur für Rom**), Regel-Wahrzeichen zuerst mit Reichweite 6,
  verdrängte Bauten Reichweite 4. Roms Zentrum hat 66 statt 87 Wohnparzellen.
  Der Circus liegt 0,75 km östlich seines Tals (wegen des Tibers).
- Gebackene Pläne: `artifacts/render-data/city-plans-r1/` (nur Rom geändert).

Nichts davon ist auf dem Mac geprüft (GDScript und Daten: `git pull` genügt, kein Rust-Build).

## 3. Entschieden, noch nicht gebaut: andere Städte

**Entscheid 31.10. 18:36: «Alle nach der Regel».** Jede Stadt zeigt alle grossen
Bauten, die sie wirklich hatte, in Regelgrösse, auch wenn sie nur wenige Häuser hat.
(Die Alternative «Nur was hineinpasst» wurde nicht gewählt.)

### Das Problem, das gelöst werden muss
- 500 der 859 Städte haben weniger als 10 Menschen in der Sim; der Median liegt
  bei etwa 3,7 städtischen Parzellen. Regelgrosse Bauten sind grösser als die Stadt.
- Heute versteckt das Budget `MAX_PUBLIC_SHARE = 0.3` (`tools/city_generate.py`)
  viele Bauten. Beispiel Verona: hat Forum, Kapitol, Theater, Amphitheater, Thermen,
  Basilika, Circus, zeigt aber nur Forum und Kapitol.
- Das Zeichnen kann heute nur 1-Parzellen-Modelle, als Block 2×1, 1×2 oder 2×2
  gestreckt (`tile_terrain.gd` `LOT_KINDS`, `PLAN_MODEL_LOTS`, `PLAN_BLOCK_*`,
  `_plan_building_lots`). Der Shader erlaubt höchstens 8 Wahrzeichen-Rechtecke
  (`uniform vec4 landmark_rects[8]` in `app/shaders/tile_terrain.gdshaderinc`).
  Für Hunderte Städte reicht der Rom-Weg (ein MeshInstance3D je Bau) nicht.

### Regelgrössen je Bautyp
Aus den typischen echten Grössen in `city_generate.py KINDS` (Amphitheater als
Ellipse, Theater als Halbkreis gerechnet, sonst Rechteck). Parzellen =
ceil(m × 0,0238 / 0,9 / 0,25).

| Bau | echt (KINDS) | Regel | Parzellen |
|---|---|---|---|
| Kapitol | 40 × 30 m | 17,5 × 13,1 m | 2 × 2 |
| Tempel | 30 × 20 m | 16,5 × 11,0 m | 2 × 2 |
| Heiligtum | 60 × 40 m | 20,8 × 13,9 m | 3 × 2 |
| Theater | 90 × 75 m | 28,4 × 23,7 m | 4 × 3 |
| Odeum | 50 × 40 m | 23,4 × 18,7 m | 3 × 2 |
| Amphitheater | 110 × 85 m | 26,3 × 20,3 m | 3 × 3 |
| Circus | 400 × 80 m | 58,5 × 11,7 m | 7 × 2 |
| Stadion | 200 × 35 m | 48,5 × 8,5 m | 6 × 1 |
| Thermen | 70 × 55 m | 20,7 × 16,3 m | 3 × 2 |
| Basilika | 70 × 28 m | 26,0 × 10,4 m | 3 × 2 |
| Curia | 30 × 20 m | 16,5 × 11,0 m | 2 × 2 |
| Gymnasium | 80 × 80 m | 20,0 × 20,0 m | 3 × 3 |
| Macellum | 45 × 45 m | 16,5 × 16,5 m | 2 × 2 |
| Stoa | 100 × 20 m | 36,8 × 7,4 m | 4 × 1 |

Höhen: echt bis 16 m bleibt echt; z. B. 21 m → 17,5 m, 25 m → 18,6 m, 30 m → 19,7 m.
Ein Provinz-Amphitheater (echt etwa 21 m) wird 17,5 m hoch, ein Theater (20 m) 17,2 m.

Vorschaubild einer Provinzstadt nach der Regel (etwa wie Verona, rund 15 Menschen,
8 Häuser; Amphitheater und Circus vor der Stadt):
`/mnt/project-files/groessen/staedte/provinzstadt-nach-regel.png`
(Ramon hat es noch nicht gesehen; die Vorschau-Masse weichen leicht von der Tabelle
ab, z. B. Theater Ø 26,5 statt 28,4 m.)

### Vorgeschlagener Bauplan (noch nicht mit Ramon besprochen, erst vorschlagen)
1. **Modelle je Bautyp** in GDScript nach dem Muster von `roman_landmarks.gd`,
   parametrisch nach Regelgrösse: Amphitheater (aus `roman_arena.gd`), Theater,
   Odeum, Thermen, Circus, Stadion, Tempel/Kapitol, Basilika, Forum. Die
   Python-Zwillinge in `vd2.py` (siehe Abschnitt 5) zeigen Form und Masse.
2. **Stadtpläne:** `USER_SIZED_M` und `ruled_model()` für alle Städte
   verallgemeinern (Parzellen aus der Tabelle). Amphitheater, Circus und Stadion
   stehen schon heute vor der Mauer. Das Budget `MAX_PUBLIC_SHARE` darf die
   echten Bauten nicht mehr wegstreichen. Danach neu backen
   (`tools/city_plans.py`, Ausgabe `artifacts/render-data/city-plans-r1/`) und
   prüfen, dass Rom gleich bleibt.
3. **Zeichnen im Spiel:** neuer Weg für Modelle über mehrere Parzellen, z. B. ein
   MultiMesh je Regelmodell (ein Mesh je Bautyp und Grösse, Instanzen pro Stadt),
   Boden darunter eben. Das ist Gebiet des **Grafik-Threads** (`tile_terrain.gd`,
   `tile_props`); vorher abstimmen. Auf Ladezeit und Bildrate achten
   (Performance-Alarm vom 31.10.: Zoom 35 bis 45 ms je Bild).
4. SCALE.md, CITY_PLANS.md, decisions.md (neue S-Nummer) nachführen, PR öffnen,
   mergen erst auf Ramons «mergen».

## 4. Schritt 2 für Rom (offen)

Gleiche Regel, noch nicht umgesetzt (siehe SCALE.md, Massstabstabelle):
- **Forum Romanum**, **Pantheon** und **Tempel**: heute ältere Kit-Modelle
  (`voxel/roman_town.gd`), auf den Planblock geschrumpft; der Stadtplan gibt
  ihnen bis 2,5-fache echte Grundfläche (`LANDMARK_GROW` in `city_plans.py`).
- **Brücken** (heute 6× echte Grösse, `LANDMARK_KM_PER_M = 0.006`).
- **Ferne Bäume** (heute 1,8×, `TREE_FAR_GROW` in `tile_terrain.gd`).
- **Szenenwege** (`OUT_KM`) und **Wetter**.

## 5. Werkzeuge (Cloud hat kein Godot)

- **GDScript → Python:** `/mnt/project-files/groessen/gd2py/` (`gd2py.py`,
  `kitmock.py`, `run_new.py`, README). Führt die Voxelskripte ohne Godot aus und
  vergleicht sie Voxel für Voxel mit den Vorschau-Zwillingen. Braucht
  `pip install gdtoolkit lark numpy`. Stand: Circus, Theater, Thermen gleich;
  Kolosseum gleich bis auf einen bekannten Fehler im Zwilling (Gesims Geschoss 3).
- **Vorschau-Zwillinge und Renderer:** `/mnt/project-files/groessen/ein-massstab/vorschau-code/`
  (`arena.py`, `stone.py`, `lmk.py`, `vd.py`, `vd2.py` für Provinzbauten,
  `render_vd.py`, `render_town.py`, `label_lm.py` für Beschriftung).
  Rendern mit Blender als Python-Modul: `pip install bpy` (5.2.3), dann z. B.
  `SAMPLES=32 python3 render_town.py town /tmp/town.png`. Die Skripte erwarten
  ihre Nachbarn unter `/tmp/arena/vox` (Pfad in `sys.path` anpassen).
- **Bericht** der ganzen Grössenfrage: https://claude.ai/artifact/KPif3omWvqyqQJLK2MwSvJ,
  Bilder unter `/mnt/project-files/groessen/`.

## 6. Wie Ramon arbeitet (für dieses Thema)

- Deutsch; vorschlagen, dann entscheidet er (Entscheidungskarten). Mergen nur auf «mergen».
- **Eine** durchgehende Regel, keine Mischungen. Nur bauen, was besprochen ist.
- Vorschaubilder immer aus der Spielkamera (35° Neigung, Blick aus Nordosten,
  orthografisch) und mit den **echten Spielhäusern** daneben; zuerst die Höhe
  gegen die Häuser zeigen.
- Mac nur über den Koordinator; GDScript-Änderungen brauchen auf dem Mac nur `git pull`.
