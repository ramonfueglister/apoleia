# Übergabe: Performance (Laden, Zoom, Terrain-Shader)

**Stand:** 31. Oktober 2026, main `9084b18` · **Status:** Schritt 1 erledigt
(PR #123), Schritt 2 (Terrain-Shader) geplant, aber noch nicht angefangen.

Diese Datei ist die Übergabe des Performance-Threads. Wer weitermacht, soll
ohne Rückfrage anfangen können: Messwerte, was schon geändert ist, was als
Nächstes kommt und wie man auf Ramons Mac misst.

Ältere Analyse (30.10.2026, nur Befund, damals nichts geändert):
[Performance-Bericht](https://claude.ai/artifact/4QB26vgwW3FzgKZaoHwsWD),
mit den Abschnitten «Runde 2», «Ladezeit» und «Mac-Messung 31.10.».

## 1. Auftrag und Entscheide

- 30.10.: Ramon wollte nur eine Prüfung, ob Refactoring oder Optimierung
  nötig ist, ohne Codeänderung. Daraus entstand der Bericht oben.
- 31.10., 16:48: «massive performance probleme beim laden der app und beim
  zoom ALARM».
- Nach der Mac-Messung hat Ramon auf der Entscheidungskarte «Beides
  nacheinander» gewählt. Erst kommen die Ruckler beim Zoomen (Schritt 1),
  dann der Terrain-Shader (Schritt 2). Beide Schritte werden auf dem Mac
  vorher und nachher gemessen, und jeder bekommt einen eigenen PR.

## 2. Messwerte

Alle Messungen liefen auf Ramons MacBook Pro (M3 Pro, 120 Hz) mit Godot
4.7.2 und Metal Forward+, Fenster 1440×810, VSync an. Gemessen wurde mit der
Tour (`app/scripts/tour_bench.gd`, `--tour=… --tour-passes=2`).

### Laden

- Der Start mit 36.5 s am 31.10. (terrain 8.5 s, look 8.3 s, people 19.0 s)
  war ein **einmaliger Kaltstart** nach dem Update. Godot kompilierte die
  Shader neu, baute die römischen Gebäude neu (der Cache-Schlüssel ist der
  md5 des ganzen Quelltexts) und importierte neue Dateien.
- Die fünf Starts danach brauchten je **etwa 3.5 s**.
- Ein neues Spiel am 30.10. brauchte 10.3 s: terrain 1193, look 72, people
  8148, build 871, draw 53 ms. Die Rust-Seite von «people» braucht in der
  Cloud etwa 4 s (Data::read, People::new mit Flussfeldern, Grain, View).
  Der Rest ist vermutlich GDScript-Aufbau.
- Die Zeiten pro Ladeschritt stehen auf dem Mac in
  `~/Library/Application Support/Godot/app_userdata/Apoleia*/loading.cfg`.
- Verdächtige für lange Ladezeiten, noch nicht behoben (Bericht, Abschnitt
  «Ladezeit»):
  - Beim Laden eines Spielstands startet die Sim doppelt: erst ein frisches
    Spiel, dann `load_game`. Das kostet etwa 3 s.
  - Der Replay braucht etwa 2.2 s pro Spieljahr.
  - Der Cache-Schlüssel von `RomanBuildings` erzwingt nach jeder
    Quelltextänderung einen Rebake, und alle Checkouts unter `~/Coding` teilen
    sich `user://`.

### Zoom und Bildzeiten

- Tour auf main `94fdcde` vom 31.10., ca. 16:55, Durchgang 2: p50 11.6,
  p90 20, p99 28.8 ms. Ohne Terrain liegt p50 bei 8.6 ms, auf mehreren
  Zoomstufen bei 120 fps. **Der Terrain-Shader kostet also etwa 8–11 ms pro
  Bild**, konstant über alle Zoomstufen.
- Spitzen von 35–90 ms kamen beim Verschieben des Ausschnitts (Stadtliste,
  Küstenliste, Props neu) und von den Reisenden. Einmal hing ein Bild 1 s
  (Schatten an, Zoom 1).

Zeitstempel-Proben (Patch in `performance/probes-zeitstempel.patch`)
zeigten die Schuldigen:

| Probe (Spitze in ms) | vor #123 | nach #123 |
|---|---|---|
| Reisende `people_trips.step` gesamt | 42–55 | 10–16 |
| davon Taglöhner `_take_work` (Wegsuche) | bis 41 | 2-ms-Budget (überschiesst bis 8.7) |
| davon Händlerkarren `_take_goods` | bis 12 | 2-ms-Budget (überschiesst bis 7) |
| Küstenliste beim ersten Wechsel auf Zoom 0 | 17–19 | 3.5 |
| `update_view` (Terrain) | 21–22 | 11 |
| Feldwege der Figuren `_update_field_routes` | 4–8 | 4–5 |

| Tour (ms) | p50 | p99 | max | Bilder > 50 ms |
|---|---|---|---|---|
| vor #123, Durchgang 1 / 2 | 14.3 / 14.4 | 31.5 / 27.0 | 52.5 / 54.4 | 2 / 1 |
| nach #123, Durchgang 1 / 2 | 13.7 / 13.6 | 28.3 / 27.5 | 52.1 / 45.0 | 1 / 0 |

(Mit den Proben liegt p50 höher als ohne, weil die Proben selbst Zeit
kosten.)

### Die übrigen Spitzen von 35–45 ms

Sie kommen weiterhin vor, vor allem auf Zoom 0–6. In diesen Bildern zeigt
keine Probe Zeit an. Auch `render_cpu_ms` ist mit 0.3–0.7 ms normal, und es
gibt keine Shader-Kompilierung. Nur ein Bild pro erstem Durchgang hat 16
Kompilierungen. `process_ms` ist in Godot kein Wert pro Bild (er liegt
oft über der Bildzeit) und taugt nicht zur Unterscheidung. `gpu_ms` ist auf
Metal immer 0.

**Vermutung, nicht bewiesen:** Die Spitzen kommen von der GPU oder vom
Präsentieren des Bildes. Bei Zoom 1 und 6 laufen 4–7 Mio. Primitive pro
Bild bei 490–735 Draw Calls. Das ist aber auch in normalen Bildern so. Dazu
kommt: `window/stretch/mode="disabled"`, darum rendert 3D in der vollen
Pixelgrösse des Fensters, auf dem Retina-Bildschirm vermutlich 2880×1620
(nicht geprüft). SMAA (`screen_space_aa=2`) und ein 8192er-Schattenatlas
kosten zusätzlich GPU-Zeit.

## 3. Was PR #123 geändert hat (gemergt, nur GDScript)

1. **`app/scripts/sim/people_trips.gd`, Taglöhner und Karren:**
   - Jede Antwort mit neuen Taglöhnern suchte bisher alle Wege auf einmal
     (`route.between`, A* durch die Stadtstrassen), auch für Taglöhner, bei
     denen weder Haus noch Feld im Bild liegt.
   - Jetzt prüft der Code zuerst, ob ein Ende im Bild liegt.
     `_take_work_some` und `_take_goods_some` legen die Wege dann mit
     `EXTRA_USEC` = 2 ms pro Bild, der Rest folgt in den nächsten Bildern.
   - Was von einer Antwort noch nicht gelegt ist, wird aus
     `_hired`/`_goods_seen` wieder entfernt, wenn die nächste Antwort kommt.
     So übernimmt die nächste Antwort diese Leute, und niemand geht
     verloren.
   - Die Slot-Abfrage wartet, bis die Taglöhner gelegt sind
     (`_working.is_empty()`).
2. **`app/scripts/tile_terrain.gd`, Küstenscan:**
   - `_coast_block` legte pro Zelle und Seite ein neues Array an.
   - Jetzt liest er direkt aus den Zellen, über `_coast_wet_corner`, ohne
     `_coast_step`. Das Ergebnis ist gleich; das wurde mit einer
     Python-Nachbildung auf 400 Zufallskarten geprüft.
   - Neue Blöcke werden mit `COAST_USEC` = 3 ms pro Bild gescannt. Bis alle
     da sind, bleiben die alte Liste und das alte Fenster stehen.
   - Ab Zoom 1 gibt es nur ein leeres Fenster, damit die leere Liste nicht
     bei jedem Kachelschritt neu hochgeladen wird.
3. **`app/scripts/sim/people_dots.gd`, Feldwege der Figuren:**
   - Die Zeilen werden ganz angehängt statt Wert für Wert, mit
     `ROUTE_BUDGET_USEC` = 2 ms pro Bild.
   - Bei gleicher Figurenliste gibt es keinen neuen Upload.
   - Dieser Teil allein brachte messbar wenig.

### Restposten aus Schritt 1, nicht gemacht

- **Einzelne Wegsuchen** brauchen bis etwa 6 ms. Das Budget prüft nur
  zwischen zwei Suchen, darum überschiesst ein Bild bis 8.7 ms.
  Hebel: `app/scripts/sim/walk_route.gd` (A* durch die Stadtpläne)
  schneller machen oder in einen Thread verlegen.
- **`people_dots.gd`:** Bei einem Fensterwechsel (um Zeile 713) wirft
  `_route_rows.clear()` alle Feldwege weg, sodass alle neu gesucht werden.
- **`tile_terrain.gd`:** `_update_town_list` und `_list_plan_lots` laufen bei
  jedem Wechsel von `prop_origin` neu, je 1–3 ms.
- **`terrain.events`** wächst ausserhalb der Tour ohne Grenze. Das ist ein
  kleines Speicherleck.
- **Prep-Durchgänge mit `UPDATE_ALWAYS`:** Die Eckpunkt-Levels
  (`TileCorners`, 322×322) und die Prop-Slots werden jedes Bild neu
  gerendert, auch wenn sich nichts bewegt (`_prep_view`).

## 4. Schritt 2: Terrain-Shader (geplant, nicht angefangen)

Ziel: die konstanten 8–11 ms pro Bild des Terrains senken, **ohne dass sich
das Bild ändert**. Ramons Scope-Regel gilt: keine ungefragte Änderung am
Aussehen.

### Wo der Code steht

- `app/shaders/tile_terrain.gdshader`: `vertex()` ab Zeile 145,
  `fragment()` ab Zeile 645, `light()` ab Zeile 1060.
- `app/shaders/tile_terrain.gdshaderinc`: `tt_cell`, `tt_water`,
  `tt_corners`/`tt_corners_cached`, `tt_coast_cut`, `tt_lake_corner_cut` und
  weitere Hilfsfunktionen.
- Weitere Includes: `coast_steps.gdshaderinc` (`cs_steps`, `cs_quay`,
  `cs_headland`), `sim_map.gdshaderinc` und `sim_fields.gdshaderinc` (Wege
  und Felder der Sim, vom Grafik-Thread mit #127 zuletzt geändert),
  `city_plan.gdshaderinc`.
- `app/shaders/tile_corner_prep.gdshader` ist ein Prep-Durchgang mit einem
  Pixel pro Kachel. Er schreibt die vier Eckpunkt-Levels in eine Float-
  Textur (`_corner_view`, siehe `_prep_view` in `tile_terrain.gd`, ca. Zeile
  662). Terrain und Props lesen sie mit `tt_corners_cached`.

### Was man über die Last weiss

- Es gibt eine Instanz pro Kachel, bis `PATCH_N`² = 320² = 102 400 Instanzen.
  Jede Instanz hat 26 Eckpunkte und 12 Dreiecke: die Oberseite, vier Wände
  und die Kante eines Küstenschnitts.
- **Das Terrain wirft keine Schatten** (`cast_shadow = OFF`). Es gibt also
  keinen zweiten Vertex-Durchgang für den Schatten.
- **Vertex-Stufe:** Jeder der 26 Eckpunkte rechnet dieselben Kachelwerte
  neu:
  - Werte: `land_sides`/`shore_sides` samt `cs_steps`, `coast`,
    `side_bits`, `ground_bits`, `cut`, `lake_cut`, `shore_lake`.
  - Kosten: je nach Kachel etwa 20 (Binnenland) bis über 100 (Küste)
    Texel-Fetches pro Eckpunkt, zum Beispiel `lone_land`, `tt_coast_cut`
    und `tt_water` der Nachbarn und Diagonalen.
- **Pixel-Stufe:** Ab Kacheln von 2 km (`CONTOUR_KM`) ist sie schwer:
  - `contour_land_soft`: 4 `tt_noise` mit je 4 Hashes mit `sin`, 4
    `tt_ground`.
  - `contour_mountain`: Rauschen, Höhe, Bodenbedeckung, `fwidth`.
  - `river_distance`: 9 Fetches mit `cos`/`sin`.
  - `contour_relief`: 4 Fetches.
  - dazu `tt_sea_distance`, `tt_lake_distance`, `sim_ways`, `sim_lanes`.
- **Noch nicht gemessen ist, welche Stufe die 8–11 ms frisst.** Darum zuerst
  messen (unten), dann umbauen.

### Messung vor dem Umbau (vorbereitet, noch nicht gelaufen)

`performance/tour-gpu-schalter.patch` erweitert `--tour-hide` um
Mess-Schalter:

| Schalter | Wirkung |
|---|---|
| `novsync` | VSync aus, damit die Bildzeit die echte Arbeit zeigt und nicht auf 8.3-ms-Stufen springt |
| `flatfrag` | Pixel-Stufe des Terrains wird zu einer flachen Farbe |
| `flatvert` | Vertex-Stufe ohne Kachelwerte (Geometrie bleibt) |
| `flatboth` | beides |
| `half` | `scaling_3d_scale = 0.5` (halbe 3D-Auflösung) |

Vorgesehene Läufe, je etwa 2 Minuten bei 2 Durchgängen: `novsync`,
`novsync,flatfrag`, `novsync,flatvert`, `novsync,flatboth`,
`novsync,terrain`, `novsync,half`. Danach den p50 pro Zoomstufe aus
Durchgang 2 vergleichen.

- Fällt viel weg mit `flatvert`, lohnt Idee A.
- Fällt viel weg mit `flatfrag`, lohnt Idee B.
- Bringt `half` viel, ist die Füllrate der Engpass.

**Schnellster Weg:** im bestehenden Worktree `~/Coding/apoleia-perf/instr`
auf dem Mac messen. Dort liegt Stand `7159af3` mit dem Proben-Patch und den
#123-Fixes, ungestaged. Die passende Dylib ist schon kopiert und importiert.
Es braucht also keinen Rust-Build. Der Terrain-Shader dort ist derselbe wie
auf main `9084b18`; nur die Includes `sim_map`/`sim_fields` haben seither
die befestigten Wege von #127 bekommen.

1. Prüfen, dass kein Godot läuft (`pgrep -fl Godot`).
2. Den Patch auf den Mac bringen, zum Beispiel per gzip und base64 in den
   Anweisungen, als `~/Coding/apoleia-perf/p3.patch`.
3. Im Worktree anwenden: `cd ~/Coding/apoleia-perf/instr && git apply ../p3.patch`
4. Die fünf Läufe, je etwa 2 Minuten:
   ```
   G=/Applications/Godot.app/Contents/MacOS/Godot
   for v in novsync novsync,flatfrag novsync,flatvert novsync,flatboth novsync,terrain; do
     $G --path app -- --tour=$HOME/Coding/apoleia-perf/gpu-${v//,/-}.json --tour-passes=2 --tour-hide=$v > ../gpu-${v//,/-}.log 2>&1
   done
   ```
   Wahlweise `novsync,half` als sechster Lauf.
5. Pro Lauf aus Durchgang 2 den p50 und p90 je Zoomstufe vergleichen.
   - Basis `novsync` minus `novsync,terrain` ergibt die Kosten des
     Terrains.
   - `flatfrag` zeigt den Anteil der Pixel-Stufe, `flatvert` den Anteil
     der Kachelwerte in der Vertex-Stufe.
   - `flatboth` zeigt, was die Geometrie allein kostet.

Der Patch ist gegen `7159af3` mit den #123-Fixes und den Proben erstellt.
Er passt also genau auf `instr`. Auf neuerem main muss man ihn von Hand
nachziehen; es sind nur etwa 28 Zeilen.

### Ideen für den Umbau

- **A, Kachelwerte vorrechnen (Vertex):**
  - Ein zweiter Prep-Durchgang wie `tile_corner_prep` rechnet die
    Kachelwerte einmal pro Kachel statt 26 Mal pro Kachel und Bild.
  - Platz: Viewports sind RGBA16F (`use_hdr_2d`). Halbfloats speichern
    ganze Zahlen bis 2048 exakt, also 11 Bit pro Kanal und 44 Bit pro
    Pixel. Gebraucht werden etwa 59 Bit, also 2 Pixel pro Kachel
    (Viewport 2·(PATCH_N+2) breit) oder zwei Viewports.
  - Stolpersteine:
    - `ground_tip` und die Eckbits von `shore_sides` gelten nur für die
      Oberseite (`part == 0`). Wände lesen sie nicht, darum im Prep wie für
      `part == 0` rechnen.
    - `lake_cut` ersetzt die eigenen Ecken durch den Seepegel. Die
      Nachbarn lesen aber die rohen Ecken, darum nur das Flag speichern und
      `tt_lake_level` im Vertex rechnen, wenn es gesetzt ist (selten).
    - `cut_level` nur bei `cut >= 0` rechnen.
    - Die Uniforms des Prep-Durchgangs müssen dieselben sein wie beim
      Terrain (`_all_materials`).
- **B, Pixel-Stufe entlasten:**
  - Was pro Kachel gleich ist, aus dem Fragment holen, zum Beispiel
    `tt_town` der Nachbarn für die Kais oder die `tt_water`-Schleifen in
    `shore_foam` und beim See.
  - Bei den Karten-Zoomstufen das Rauschen von `contour_land_soft` und
    `contour_mountain` sparen, ohne dass sich das Bild ändert. Das ist
    schwer; Bildvergleich nötig.
- **C, Renderauflösung:** zum Beispiel `scaling_3d_scale` 0.75 mit FSR.
  Das ändert das Aussehen, darum nur mit Ramons Entscheid.
- **D:** Die Prep-Durchgänge nur rendern, wenn sich Kamera oder Zoom
  ändern (`UPDATE_ONCE` beim Wechsel statt `UPDATE_ALWAYS`).

### Fallen

- **Metal:** Kein `texelFetch` hinter einem frühen `return`. Das hat Apples
  Metal-Compiler zum Absturz gebracht (PR #51). Die Mess-Schalter benutzen
  darum `if/else` statt `return`.
- **Varyings:** Metal erlaubt 31 Varying-Komponenten insgesamt, darum teilen
  sich kleine Flags ein `int` (siehe Kommentar im Shader).
- **Bild prüfen:** Vorher und nachher auf dem Mac dieselben Ansichten
  aufnehmen (`--views=lon,lat,width;…` und `--snapshot=…`, siehe
  `landscape.gd`), zum Beispiel Rom nah, Küste bei Neapel, Alpen, Europa
  gesamt.

## 5. So misst man auf Ramons Mac

- **Zugang:** Remote Control über den Koordinator. Immer nur ein Thread
  zur Zeit; vorher anmelden und nachher melden, dass der Mac wieder frei
  ist. **Ramons Checkout `~/Coding/apoleia` nicht anfassen**, nur
  `git fetch`. Keine Pushes vom Mac.
- **Worktree anlegen:**
  `git -C ~/Coding/apoleia worktree add --detach ~/Coding/apoleia-perf/<name> origin/main`
- **Dylib:** Hat sich die Rust-Seite seit Ramons letztem Build nicht
  geändert, die Dylib von `~/Coding/apoleia/app/bin/libapoleia_godot.dylib`
  nach `app/bin/` kopieren. Sonst im Worktree bauen mit
  `sim/godot/build.sh` (gemeinsamer Cache `~/.cache/apoleia-target`, ein
  hängendes Lock `~/.cache/apoleia-target/.build-lock` darf man mit rmdir
  entfernen; Rust 1.99.1, Befehl im Projektgedächtnis).
  - Achtung: #121 und #127 haben Rust geändert. Für main `9084b18` braucht
    es also einen Build.
- **Einmal vorbereiten:**
  `echo 'res://apoleia.gdextension' > app/.godot/extension_list.cfg`, dann
  `/Applications/Godot.app/Contents/MacOS/Godot --headless --path app --import`
- **Tour:**
  `/Applications/Godot.app/Contents/MacOS/Godot --path app -- --tour=$HOME/Coding/apoleia-perf/x.json --tour-passes=2 [--tour-hide=…] > x.log 2>&1`
  Bei `SCRIPT ERROR` oder Parse-Fehlern im Log abbrechen.
- **Auswerten:** Das JSON hat pro Durchgang eine Zusammenfassung (p50, p90,
  p99, max, Werte pro Zoomstufe) und die 25 schlechtesten Bilder mit
  `events`, `process_ms`, `render_cpu_ms`, `compiles`, `draws` und `prims`.
  - Mit dem Proben-Patch stehen unter `result.probes` pro Probe
    `[Bilder, Summe ms, max ms]` über alle Bilder.
  - In `events` stehen Einträge `t:<name> <ms>` für jede Probe ab 1 ms.
- **Proben-Patch** (`performance/probes-zeitstempel.patch`, gegen
  `7159af3`, nie pushen):
  - `TileTerrain.probe(name, start_usec)` misst die Teile von `update_view`
    (Stadtliste, Stadtpläne, Küste, Level-Fenster, Props).
  - Dazu kommen people_dots (Frame, Sync, Figurenliste, Feldwege), die
    Teilschritte von `people_trips.step`, landscape (Spannen, Marker, Look,
    `_process` gesamt), das Wetter und `water_lines._draw_layer`.
- **Aufräumen:** `~/Coding/apoleia-perf` enthält den Worktree `instr`, die
  Logs, JSONs und Patches der Messungen vom 31.10. Den Ordner kann man
  löschen, sobald die Messung vor dem Umbau (Abschnitt 4) gelaufen ist. Wer
  ihn vorher löscht, legt für die Messung einen neuen Worktree an (oben).
  Befehl: `rm -rf ~/Coding/apoleia-perf && git -C ~/Coding/apoleia worktree prune`

## 6. Weitere Hebel aus dem Bericht vom 30.10. (nicht umgesetzt)

- **Wetter:** Das Schattenmasken-SubViewport rendert jedes Bild, aber kein
  Shader liest es (`weather_system.gd`, ca. Zeile 214).
- **Brücken:** Die Markierungen sind jedes Bild auf allen 29 Seiten «dirty».
- **Sim:** Ein Schnellpfad i64 statt i128 in pricing/freight spart 0.2 ms
  und gibt bitgleiche Ergebnisse. Der Grain-Tag läuft voll seriell (4 Kerne
  bringen nur 1.65×). `grain.rs` aufteilen; ein paralleler Grain-Tag für
  200k Leute wäre riskant.
- **App:** Bildrate kappen und drosseln, wenn das Fenster nicht im Fokus
  ist; bei Tempo 4 die Ansicht seltener neu aufbauen.
- **Möglicher Sim-Bug:** Die Saatreserve unterscheidet sich zwischen
  labour/goods_month und `seed_due()` beim Essen (`grain.rs` um 3005/3614).
  Das ist ein Fall für den Sim-Thread.

## 7. Links

- PR #123: https://github.com/ramonfueglister/apoleia/pull/123
- Performance-Bericht: https://claude.ai/artifact/4QB26vgwW3FzgKZaoHwsWD
- Patches in diesem Ordner: `performance/probes-zeitstempel.patch`,
  `performance/tour-gpu-schalter.patch`
