# Übergabe Grafik (Stand 31.10.2026, main 5b8167d)

Für die nächste Claude-Sitzung, die an der Grafik von Apoleia weiterarbeitet,
auch von einem anderen Konto aus. Alles hier steht im Repo; Projektdateien
und Projektgedächtnis des alten Kontos sind dort vielleicht nicht lesbar.

## Auftrag

Ramon (29.10.2026): Die Grafik soll auf das Niveau von **Urbek City Builder**
und **Islanders**. Seither ist sie in Runden gewachsen: Ramon entscheidet
jede Runde auf einer Entscheidungskarte. Gebaut wird dann in der Cloud,
gemerged auf sein Wort, geprüft auf seinem Mac. Ausführliche Beschreibung
jeder Runde mit Zahlen: `docs/product-renderer/TILE_TERRAIN.md`, vor allem
die Abschnitte «Bildstimmung (Urbek/Islanders, seit 29.10.2026)» und die
Absätze «Runde E» bis «Runde Q».

Es ist **keine** neue Runde beauftragt. Die nächste Sitzung schlägt
höchstens vor und baut erst nach Ramons Wahl.

## Was gebaut und gemerged ist

Zoomstufen zum Verständnis: Kachelgrössen 0,5 / 1 / 2 / 4 / 8 / 16 / 32 km.
Unter etwa 12 km Sichtbreite kommen Viertelkacheln (`sub_tiles`). Die 0,5-
und 1-km-Kacheln decken etwa 12–95 km ab. Ab den 2-km-Kacheln (`CONTOUR_KM`)
gilt die ferne Karte, Ansichten ab etwa 95 km.

| Runde | PR | Inhalt in Stichworten | Wichtigste Dateien |
|---|---|---|---|
| 1–5 | über #54 (29.10.) | Licht: kühle Schatten, SSAO mit dem Zoom, Vignette. Urbek-Kamera: nah 45° Nordost, 35° nach unten (`YAW_CLOSE`, `PITCH_CLOSE`). Felder als Äcker aus 3–5 × 1–2 Parzellen. Wiese mit Büscheln. Einzelbäume. Stadtgärten. Basaltfahrbahn. Werkstätten. Tilt-Shift nur angedeutet. | `app/scripts/landscape.gd`, `app/shaders/vignette.gdshader`, `tile_props.gdshader(inc)`, `people_parcels.gdshader`, `people_crops.gdshader`, `sim_map.gdshaderinc` |
| Stadtpläne | #63 | 860 Stadtpläne: Strassen, Mauern, Tore, öffentliche Bauten, Häuser zur Strasse. Rom, Ostia, Mailand, Trier, Alexandria, Karthago, Antiochia und Aquileia rekonstruiert. | `app/scripts/city_plans.gd`, `app/shaders/city_plan.gdshaderinc`, `tools/city_plans.py`, `tools/city_generate.py`, `data/cities/plans/`, `docs/kit2/CITY_PLANS.md` |
| A–D | #69 | Gebaute Felder als echte Felder, frei von Spielerstrassen. Mandelblüte in wenigen Büscheln. Ein Modell je öffentlichem Bau. Schatten tief wie Urbek: Umgebungslicht 0,42, Sonne 2,45. | `landscape.gd`, `people_crops.gdshader`, `people_lots.gdshader`, `sim_fields.gdshaderinc`, `voxel/roman_town.gd` |
| E | #74 | Küste in Voxelstufen: Sandbuchten, Sand am Fuss, gestuftes Flachwasser. Weiden dichter: dreimal so viele Einzelbäume, runde Büsche. | `tile_prop_meshes.gd`, `tile_props.gdshader(inc)`, `tile_terrain.gdshader` |
| F | #77 | Hecken an einem Viertel der Ackeraussenseiten, Grasrand an Dorf- und Feldwegen | `people_crops.gdshader`, `sim_map.gdshaderinc`, `people_dots.gd` |
| G | #82 | Koppeln: 2 × 2 Weideparzellen mit Hecke oder Trockenmauer und Tor | `people_crops.gdshader` |
| H | #84 | Ufer nah in Voxelstufen | `tile_coast_steps.gdshader`, `coast_steps.gdshaderinc`, `tile_prop_meshes.gd`, `tile_terrain.gd` (`_update_coast_list`) |
| I | #88 | Ruhigere Küste, Kais vor Städten, Bäume auch weiter draussen | `tile_terrain.gdshader`, `tile_props.gdshaderinc`, `coast_steps.gdshaderinc` |
| J | #92 | Ferne Felder (8–40 km) wie nahe: flach, mit Reihen und Grasrand (`sim_far_field`) | `sim_map.gdshaderinc`, `tile_terrain.gdshader` |
| K | #93 | Feine Strandkante bei 3 km, weiche Schatten auf dem Wasser | `tile_terrain.gdshader` |
| L | #96 | Ruhigere Hänge weit draussen | `tile_terrain.gdshader` |
| M | #99, #102 | Glatte Küsten auf der fernen Karte: Linie aus der Meeresdistanz in `aux.png` R, `CONTOUR_SD` 1 km. Meer auf Küstenhöhe, keine Uferstriche. | `tile_terrain.gdshader(inc)` |
| N | #111 | Ferne Flüsse nach ihren Linien (`rivers.png`, Bogendistanz). Berge nach den Höhen: `contour_relief`, `contour_mountain` mit Fels ab 1150 m und Schnee ab 1600 m. | `tools/build_tile_terrain.py`, `tile_terrain.gd`, `tile_terrain.gdshader`, `artifacts/render-data/tile-terrain-r1/rivers.png` |
| O | #116 | Bei 3 km: Reihen als Rippen mit Buckeln (`CROP_LUMPS`). Offenes Land als Weideblöcke mit Rain (`sim_pasture`, `SIM_P_FARMED`). | `people_crops.gdshader`, `people_parcels.gdshader`, `sim_fields.gdshaderinc`, `sim_map.gdshaderinc`, `people_dots.gd` |
| P | #119 | Ferne Karte: runde Seeufer (SDF in `aux.png` A, Bake `--lakes-only`), weiche Landschaftsgrenzen (`contour_land_soft`, `contour_ground_tone`) | `tools/build_tile_terrain.py`, `tile_terrain.gdshader(inc)`, `aux.png` |
| Q | #120 | Mittlere Zoomstufe (0,5- und 1-km-Kacheln): Flüsse und Seen nach ihren echten Linien, siehe unten | `app/scripts/water_lines.gd`, `tile_terrain.gd`, `tile_terrain.gdshader(inc)`, `tile_props.gdshaderinc`, `tools/build_tile_terrain.py`, `water-lines.bin` |
| Befestigte Wege | #127 | Look B (Ramon: «Kies, Breite nach Begängnis»), siehe unten | `sim_fields.gdshaderinc`, `sim_map.gdshaderinc`, `docs/kit2/SCALE.md`, `sim/godot/src/grain_map.rs` (eine Zeile) |

Alle Dateien ohne Pfad liegen in `app/shaders/` oder `app/scripts/`.

### Runde Q im Detail

- **Bake:** `python3 tools/build_tile_terrain.py --water-lines-only` schreibt
  `artifacts/render-data/tile-terrain-r1/water-lines.bin` (2,2 MB) und den
  Schlüssel `water_lines` in `manifest.json`. Inhalt: Natural-Earth-Flüsse bis
  Rang 10 und Seeringe, mit Catmull-Rom geglättet.
- **Format:** `b"WLN1"`, `uint32` Anzahl Linien. Dann je Linie: `int32 kind`
  (Flussrang, 100 = See, 101 = Insel), `int32 n`, `float32 bounds[4]`,
  `float32 xz[2n]`.
- **`water_lines.gd`:** ein SubViewport von 4096² Pixeln über dem gezeichneten
  Ausschnitt (Ausschnitt mal 1,3). Er zeichnet neu, wenn der Ausschnitt ihn
  verlässt. Kanäle: R Fluss, G See, B Ufer. Ebenen mit ADD/SUB-Blend; Inseln
  werden von den Seen abgezogen.
- **Shader:** `tt_water_lines()` liest das Bild linear und schärft bei 50 %
  Deckung mit `fwidth`. Seekacheln liegen auf Seehöhe, ohne Ecken- und
  Küstenschnitte. Das alte Kachelband bleibt in Städten ab Grösse 2, an Kais
  und auf bebauten Planparzellen (`plan_built`, nicht auf `CP_LAND`).
- **Bäume:** Ein Baumplatz fällt weg, wo Wasser oder Ufer ≥ 0,15 deckt.
- **Punkte der Leute:** Sie übernehmen jede Terrain-Uniform ohne `sim_`
  automatisch, also auch `water_lines`.

### Befestigte Wege (#127) im Detail

- **Wegebene RG8:** R = Verbindungen (Bit k = `DIRS[k]`); G = Stufe in den
  Bits 0–2, Bit 3 (8) = befestigt (S133). `walk_route.gd` prüft nur G > 0.
- **Rust (#127):** `grain_map.rs` setzt `|= 8`. Eine befestigte Kachel ohne
  Verbindung (R = 0) bekommt Verbindungen zu befestigten Nachbarn; das ist
  Commit 1a126ec des Sim-Threads.
- **Aussehen:** Kies (0,62 / 0,57 / 0,47) mit braunem Rand (0,44 / 0,38 /
  0,29), Füllanteil 0,78.
- **Breite:** halbe Breite = `max(SIM_WAY_KM[Stufe], 0,013 km)`; sichtbar bis
  40 km (`SIM_WAY_SHOW_KM[7]`).
- **Mac:** Braucht einen Rust-Neubau.

## Was auf dem Mac geprüft ist

| Runden | Shots auf Branch `gfx-shots` | Ergebnis |
|---|---|---|
| s1–s5 | `s1`, `s1-zoomsweep`, `r1`–`r3` | Grundlage aller späteren Runden |
| Stadtpläne #63 | `plans1`–`plans3` (168af1a) | drei Mac-Läufe, Fehler behoben |
| E–H | `rH` (eb08af5, main 7cab2df) | glatter Landanteil bei 3 km: v2 21 → 13 %, v1 28 → 23 % (Urbek 8 %) |
| I–J | `rIJ` (ac3f5a0, main 703ca1e) | kompiliert auf Metal |
| K–M | `rKLM` (368a9da) | kompiliert auf Metal |

**Nicht** auf dem Mac geprüft: N, O, P, Q und #127. Die Koppeln aus Runde G
waren auf keinem Mac-Shot zu sehen.

## Offene Lücken

1. **Pachtfeld unsichtbar.** Spielerfelder sind Staatsland und werden für ein
   Drittel verpachtet. Die Sim sagt der Ansicht aber nicht, welches Feld
   verpachtet ist, darum kann die Grafik es nicht zeigen. Zuerst braucht es
   ein Feld in der Sim-Ansicht (Sim-Bereich, `sim/`), dann eine Markierung im
   Shader.
2. **Mac-Prüfung N–Q und #127 fehlt.** Beim ersten Lauf das Log auf
   `SHADER ERROR` prüfen (Metal ist strenger als lavapipe). Dann Ansichten von
   12 bis 95 km anschauen: Flüsse (Tiber, Po), Seen (Garda, Bolsena),
   Stadtränder, die Europakarte und befestigte Wege bei 6 und 22 km.
3. **Koppeln (Runde G)** auf einem Mac-Shot suchen; vielleicht sind sie zu
   selten oder zu klein.
4. **Knick am Stadtrand:** Wo die glatte Flusslinie auf das alte Kachelband
   der Stadt trifft, springt der Fluss leicht.
5. **Wasserbild ohne Mipmaps:** Das 4096²-Bild von `water_lines.gd` kann beim
   Zoomen flimmern. Die Kosten des Neuzeichnens sind nicht gemessen.
6. **Leistung:** Der Performance-Thread hat das Terrain mit 8–11 ms je Frame
   gemessen. Sein Schritt 2 ist der Terrain-Shader (`tile_terrain.gdshader`,
   `tile_corner_prep`). Jede neue Grafikarbeit im Terrain-Shader kostet dort.
7. **Kein neuer Urbek-Vergleich:** Seit E–H ist nicht mehr gegen Urbek
   gemessen worden. Nach dem Mac-Lauf von N–Q neu messen.

## Weitere Ideen (nicht beauftragt, Ramon entscheidet)

- Pachtfelder sichtbar machen, sobald die Sim sie liefert: zum Beispiel ein
  Grenzstein oder eine andere Zaunart. Erst skizzieren.
- Mipmaps oder ein zweites, gröberes Wasserbild gegen Flimmern.
- Den Knick am Stadtrand glätten: die Linie bis an das Band führen.
- Urbek-Befunde, die noch offen sind: Wasser bei Urbek ist eine flache,
  hellblaue Fläche (etwa #6AA8D0) ohne Brandung. Das Ufer ist immer eine
  niedrige, senkrechte Stufe; zwischen Häusern und Wasser liegt immer ein
  Streifen (Weg, Kai, Steg).
- Weg-Look: Strassen ab 1900 (Asphalt) brauchen später einen eigenen Look;
  es gilt die Regel «jedes System von Rom bis heute».

## Kollisionsregeln mit anderen Bereichen

Diese Regeln gelten, wenn parallel andere Threads laufen. Vor einer Änderung
an einer fremden Datei: den zuständigen Thread oder den Koordinator fragen.

- **`app/scripts/city_markers.gd`** gehört der Kartenbeschriftung (#122:
  Platzierung, Ausblenden, Namen) und dem Massstab-Thread (#110:
  Voxel-Stadtmarken). Die Grafik fasst sie nicht an.
- **`app/scripts/tile_terrain.gd`** teilt sich die Grafik mit dem
  Massstab-Thread (Grössen, `docs/kit2/SCALE.md`):
  - Massstab besitzt ferne Geometrie, Relief (`NEAR_EXAGGERATION`), Häuser,
    Stadtsymbole, Landmarken (`voxel/roman_*.gd`, `roman_landmarks.gd`) und
    `SCALE.md`.
  - Grafik besitzt ferne Farbe und Schattierung, Wasser, Küste und den Look
    von Feldern und Wiesen.
  - Vertrag: Meer- und Küstenecken bleiben 0, Land ≥ 1.
  - Massstab-Regel: alles massstäblich; Ausnahmen fragt man vorher. Bäume
    nah 8 m (`TREE_M`).
- **Terrain-Shader** (`tile_terrain.gdshader`, `tile_corner_prep`): Der
  Performance-Thread arbeitet daran. Ändert die Grafik `sim_map.gdshaderinc`
  oder `sim_fields.gdshaderinc`, meldet sie es ihm.
- **`sim/`** gehört dem Sim-Thread. Die Grafik hat dort nur die eine
  abgesprochene Zeile in `grain_map.rs` geändert (#127).
- **`people_dots.gd` und `people_*.gdshader`** teilt sich die Grafik mit
  Tagesablauf und Wuselfaktor.
- **`walk_route.gd`** (Wegsuche) liest die Wegebene: Bit 3 darf G > 0 nicht
  brechen.
- **Konflikte in `docs/kit2/decisions.md`:** alle Zeilen behalten. Neue
  Arbeit zweigt immer von main ab. Vor dem Merge den aktuellen main
  hereinholen und die Shader auf Parse-Fehler prüfen (siehe Werkzeuge).

## Referenzen

- **Urbek im Repo:** `docs/kit1/references/screenshots/urbek-coast-city-overview.jpg`,
  `urbek-neighborhood.jpg`, `urbek-terrain-vegetation.jpg` (Quellen in
  `README.md` und `sources.json` daneben). Ackerland-Referenz ist
  `urbek-terrain-vegetation.jpg`: Sättigung 0,47, Helligkeit 0,48,
  σ 0,18, dunkler Anteil 26 %.
- **Weitere 15 Steam-Shots von Urbek** (App 1411740): Der Cloud-Proxy sperrt
  Steam, sie sind nur über Ramons Mac zu holen
  (`curl "https://store.steampowered.com/api/appdetails?appids=1411740"`,
  `path_full`). Sie sind urheberrechtlich geschützt: nur in einem
  Temp-Ordner auf dem Mac, **nie ins öffentliche Repo pushen**, danach
  löschen. Befunde vom 30.10.:
  - Küste ohne Brandung; Wasser flach hellblau.
  - Das Ufer ist eine niedrige Stufe aus Sand oder aus Weg mit Steinkante.
  - Schräge Küsten sind glatte Bögen aus kleinen Voxeln.
  - Urbek zoomt nie kartenartig hinaus; ferne Wälder bleiben Einzelbäume.
  - Glattes Grün 0–12 %.
- **Islanders:** Stilvorbild für ruhiges Low-Poly und eine sanfte Palette.
  Keine Bilder im Repo.
- **Ramons Landschaftsreferenz:**
  `docs/kit1/references/images/user-primary-landscape-style.png`, für die
  ferne Karte: runde Seen, weiche Flecken. Dazu `referenz-perspektive.png`.
- **Messmethode:**
  - Bild auf 960 × 540 skalieren. Glatter Anteil = Blöcke von 12 px mit
    σ < 2.
  - Farben: 320 × 180, Median-Cut auf 8 Farben, dunkel = HSV-Wert < 0,35.
  - Immer Bild neben Bild bei ähnlichem Zoom vergleichen. Ramon: «immer mit
    screenshots echt vergleichen».

## Arbeitsweise mit Ramon

- Er schreibt Schweizerdeutsch. Antworten auf Deutsch, kurz und im
  Gesprächston.
- «vor allem mit mir reden», «nicht einfach alles neu»: zuerst eine Skizze
  oder ein Prüfstandbild, dann eine Entscheidungskarte mit Empfehlung, dann
  bauen.
- **Umfangsregel:** nur, was besprochen ist. Keine ungefragten Farb- oder
  Look-Änderungen.
- Merge-Regel: «keine tests mergen comitten nach github und dann
  weiterarbeiten».
  - Gemerged wird auf sein Wort («mergen», «Mergen» auf der Karte).
  - Kein Warten auf einen Mac-Test.
  - Gemerged wird mit dem vollen Head-SHA.
- Nie ungemessene Zahlen als Tatsachen nennen.
- Keine Modellnamen in Commits, PRs oder Code.
- Grundsätze des Spiels:
  - Alles emergent und sichtbar.
  - Jedes System trägt von Rom bis heute.
  - Wege entstehen nur durch Begehen, es gibt keine Zufallsstrassen.

## Mac (Ramons Rechner) und Screenshots

- **Zugang:** Ramons MacBook (M3 Pro, Godot 4.7, Rust 1.99.1) über eine
  Remote-Control-Sitzung. Immer nur **ein** Thread zur Zeit; den Platz
  vergibt der Koordinator.
- **Ordner:**
  - Ein einziger Claude-Ordner unter `~/Coding`, danach löschen
    (`git worktree remove` + `prune`).
  - `~/Coding/apoleia` ist Ramons Checkout: nur einen Worktree davon
    anlegen, sonst nichts ändern.
  - Nicht anfassen: `apoleia-stats`, `apoleia-build`, `vic3-clone`,
    `~/.cache/apoleia-target`.
- **Godot:** nur ein selbst gestartetes Godot beenden.
- **Build:** nur über `sim/godot/build.sh`. Ramons Befehl:
  `cd <dir> && PATH="$HOME/.rustup/toolchains/1.99.1-aarch64-apple-darwin/bin:$PATH" sh sim/godot/build.sh && /Applications/Godot.app/Contents/MacOS/Godot --path app`.
- **Dylib:** Die GDExtension ist nicht in Git. Wenn sich `sim/` seit Ramons
  Build nicht geändert hat, seine `app/bin/libapoleia_godot.dylib` als neue
  Datei kopieren (cp nach `.tmp`, dann mv; überschreiben tötet sie wegen der
  Signatur). Ein frischer Worktree braucht `app/.godot/extension_list.cfg` mit
  `res://apoleia.gdextension`.
- **Shots:**
  `Godot --path app --windowed --resolution 1920x1080 --position 0,0 -- --views="12.40,41.80,3;12.62,41.78,3;12.80,41.96,3;12.49,41.89,3;14.25,40.83,3;12.49,41.89,8;12.5,41.9,22;13.2,42.2,70;14.0,44.0,1500" --snapshot=<dir> --snapshot-frames=60 --no-event-windows`.
  Format der Ansicht: Länge, Breite, Sichtbreite in km. Godot hängt oft nach
  dem letzten Bild; ein Wächter beendet es 30 s danach.
- **Branch `gfx-shots`:** ein verwaister Branch im öffentlichen Repo, nie
  mergen. Ein Ordner je Runde (`s0` … `rKLM`). Ein Push dorthin braucht
  Ramons eigenes, geschriebenes «push». So wird gepusht, ohne Checkout:
  1. Eine temporäre `GIT_INDEX_FILE` anlegen und `read-tree origin/gfx-shots`.
  2. `git --work-tree=shots add <runde>`.
  3. `write-tree`, dann `commit-tree -p origin/gfx-shots`.
  4. `push <commit>:refs/heads/gfx-shots`.

  Zum Messen in der Cloud: `git archive origin/gfx-shots <runde> | tar -x`.
- **Fallen:**
  - Metal-Shader-Absturz (#51) und SIGKILL der Dylib (#52).
  - Nie Lambdas in Statics speichern (#62).
  - Zeiten in `loading.cfg` unter `Application Support/Godot/app_userdata/Apoleia*`.

## Werkzeuge in der Cloud (`tools/gfx_bench/`)

Die Cloud hat keine GPU. Godot 4.4.1 läuft mit lavapipe. Herunterladen von
`https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip`.

Lavapipe kann das echte 3D-Terrain nicht zeichnen: Der Speicher reicht nicht
für alle Pipelines. Darum gibt es 2D-Prüfstände.

- **Parse-Check aller Shader** (findet Fehler mit Zeilennummer in
  Millisekunden, ist aber kein Metal-Test):
  ```
  cp tools/gfx_bench/shadercheck.gd app/scripts/_bench_check.gd
  xvfb-run -a env VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
    <godot> --headless --path app --script res://scripts/_bench_check.gd -- \
    res://shaders/tile_terrain.gdshader res://shaders/tile_props.gdshader ...
  ```
- **Prüfstand-Shader:** `python3 tools/gfx_bench/mkbench.py <fragment.glsl> <name>`
  nimmt `tile_terrain.gdshader` ohne `vertex()`, `fragment()` und `light()`,
  macht daraus `canvas_item` und hängt ein eigenes Draufsicht-Fragment an.
  Ergebnis: `app/shaders/<name>.gdshader`.
  - `fragment_water_q.glsl` → `_bench_q` für `terrain_bench.gd`: echte
    Terraindaten von oben, Runde Q.
  - `fragment_ways.glsl` → `_bench_paved` für `ways_bench.gd`: Wege über
    Wiese mit erfundener Wegtextur.
- **Prüfstand starten:** Skript nach `app/scripts/_bench_*.gd` kopieren und
  mit `xvfb-run -a -s "-screen 0 1600x900x24" env VK_ICD_FILENAMES=... <godot> --path app --script res://scripts/_bench_X.gd -- <args>`
  starten (ohne `--headless`, damit es rendert). Argumente siehe Kopf der
  Skripte.
- `_bench_*` nie committen. In `.git/info/exclude` gehören
  `app/shaders/_bench_*` und `app/scripts/_bench_*`.
- **3D-Prüfstand für neue Meshes** (so in Runde H): TileTerrain normal
  laden. Dann Terrain-, Prop- und Landmarkenknoten ein schlichtes
  `StandardMaterial3D` als `material_override` geben; der neue Shader
  rendert über einer Ersatzfläche.

## Stolperfallen (GLSL und Godot)

- Ein `out`-Parameter im selben Ausdruck, in dem er gelesen wird, liest
  einen uninitialisierten Wert.
- `fwidth` und `dFdx` sind in Zweigen undefiniert, die innerhalb einer Kachel
  wechseln. Ableitungen vor solchen Zweigen berechnen.
- Schwere Funktionen nicht mehrfach inline aufrufen (Metal-Risiko,
  Kompilierzeit).
- GDScript: Eine Variable mit dem Typ `SubViewport` kennt die Methoden des
  angehängten Skripts nicht. Mit dem vorgeladenen Skript typisieren
  (`var _water_lines: WaterLines`).
- Schnell lesen: `bytes_to_var` mit 8-Byte-Kopf
  (`TYPE_PACKED_VECTOR2_ARRAY`, n) plus Floats ergibt direkt ein
  `PackedVector2Array`.
- Godot 4.4 kompiliert die Pipelines jedes Materials im Szenenbaum, auch
  auf versteckten Knoten.

## Bilder der Runden

Skizzen, Prüfstandbilder und Mac-Vergleiche liegen im alten Projekt unter
`/mnt/project-files/grafik/` (`runde-e-…` bis `runde-q-…`,
`mac-check-e-bis-h.jpg`, `mac-check-i-j.jpg`, `mac-check-k-l-m.jpg`,
`befestigte-wege-skizze.jpg`, `befestigte-wege-pruefstand.jpg`,
`urbek-vs-apoleia.jpg`). Bilder mit Urbek-Ausschnitten gehören nicht ins
Repo. Die Mac-Shots selbst liegen öffentlich auf `gfx-shots`.
