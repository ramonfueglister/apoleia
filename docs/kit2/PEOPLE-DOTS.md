# Bewohner als Punkte (Kit 2, Personen-Prototyp)

Status: **validiert** auf MacBook Pro M3 Pro (Godot 4.7.2, Forward+/Metal), 27.10.2026.

Jede simulierte Person (Prototyp `sim/src/people.rs`, rund 115 000 bis 150 000)
erscheint als schwarzer Punkt auf ihrem Tile der Tile-Terrain (SimCity-2000-Look).

## Datenfluss

```
Sim-Thread (ApoleiaPeople)                      Godot-Hauptthread
People::day()  ── bevy_ecs-Welt, deterministisch
PeopleView::update()  ── Query (Pid, Home, Stand, Option<Travel>)
   feste Slots pro Person, geänderte Seiten   ──►  Front-Puffer (Mutex, nur Kopie
                                                    der geänderten Seiten)
                                               sync(): geänderte Seiten →
                                                    Texture2DArray.update_layer
                                               ein MultiMesh-Draw, Position im
                                                    Vertex-Shader (people_dots.gdshader)
```

- **Eigener Thread, Doppelpuffer (S45):** Die Personen laufen wie `ApoleiaSim`
  auf einem eigenen Thread; `advance(n)` reiht Tage ein und kehrt sofort zurück.
  Der Frame wartet nie auf einen Tag. Nach jedem Tag kopiert der Sim-Thread nur
  die geänderten Seiten in den Front-Puffer; `sync()` holt sie ab.
- **Feste Slots, Seiten (wie S46):** Jede lebende Person hat einen festen Slot
  (`sim/src/view.rs`), frei gewordene Slots werden wiederverwendet. 4096 Slots
  bilden eine Seite = eine 64×64-Schicht einer RGBA32F-Texture-Array. Nur
  geänderte Seiten werden hochgeladen.
- **Ein Datensatz = 16 Byte:** Anker x, z (Welt-km, eqc41 wie tiles.csv und die
  Tile-Terrain), Streuradius (> 0 Quadrat = 25-km-Zelle, < 0 Kreis um eine Stadt,
  0 = leer) und `key·4 + Art` (Art: daheim, Stadt, unterwegs, wandert aus).
- **GPU-Platzierung:** Die Sim kennt nur die 25-km-Zelle (`Home`). Der
  Vertex-Shader würfelt aus dem Personen-Key bis zu 12 Stellen in der Zelle und
  nimmt die erste auf einem Land-Tile; Stadtbewohner liegen in einer Scheibe um
  ihre Stadt mit dem Radius, den auch die Stadt-Tiles verwenden
  (`0.6 km · sqrt(pop / 10 000)`, tools/build_tile_terrain.py). Die Höhe kommt
  aus `tt_corners` der Tile-Terrain, also steht jeder Punkt auf der Tile-Ebene
  bzw. Rampe der aktuellen Zoomstufe. Der Punkt bleibt fest, solange die Person
  bleibt (Hash, kein Zufall pro Frame).
- **Platzierung als 2D-Pass:** `people_dots_prep.gdshader` rechnet die Stelle
  jeder Person einmal in eine RGBA16F-Textur (Versatz zum Anker, Höhe), nur wenn
  sich die Personen oder die Terrain-Ansicht (Zoomstufe, Relief-Überblendung,
  Ecken-Ausschnitt) ändern.
- **Ein Draw Call:** ein MultiMesh mit 64 Dreiecken pro Instanz, dessen
  Transformationen nie geschrieben werden; der Vertex-Shader liest pro Punkt zwei
  Texel und zeichnet einen Punkt fester Pixelgröße (3,5 px nah, 1 px weit; ab
  1,75 px rund ausgeschnitten, darunter ohne `discard`).

## Gemessen (Linux-Container, 4 Kerne)

`cargo run --release --example view_bench` (360 Tage):

| Größe | Wert |
|---|---|
| Personen | 115 264 |
| Seiten (Schichten) | 29 |
| `PeopleView::update` pro Tag, Median / p95 | 1,2 ms / 1,6–2,1 ms (Sim-Thread, nicht im Frame) |
| geänderte Datensätze pro Tag, Median | 641 (Reisende, Geburten, Tode, Umzüge) |
| geänderte Seiten pro Tag | 29 von 29 |

Folge: Die 641 Änderungen verteilen sich über alle Seiten, also geht heute pro
Sim-Tag die ganze Textur (1,9 MB) hoch. Das ist bei 10 Tagen/s rund 19 MB/s.
Wenn die Messung auf dem Mac hier Kosten zeigt, folgt der nächste Schritt (siehe
unten).

Frame-Zeit auf dem Mac: `scripts/run-landscape -- --people-bench=artifacts/runtime/people-bench.json`
misst 240 Frames mit und 240 ohne Punkte (V-Sync aus) und schreibt Median und p95
von Frame-Zeit und GPU-Zeit sowie die Upload-Zeit von `sync`.

## Gemessen auf dem Mac (M3 Pro, 1440×810, V-Sync aus)

Frame-Zeit Median in ms, je 240 Frames mit und ohne Punkte (`--people-bench`),
Kosten der Punkte = mit minus ohne:

| Runde (Stand) | 360 km | 25 km | 1800 km |
|---|---|---|---|
| 1: Platzierung pro Vertex, große runde Punkte | +0,8 | +1,8 | +2,1 |
| 2: kleine Punkte weit weg, ohne `discard`, Cull | +0,04 | +0,8 | +1,1 |
| 4: neues Terrain (Ecken-Cache), Platzierung als 2D-Pass | +1,0 | +1,3 | +1,1 |
| 5: Sim pausiert (kein Upload, kein Pass) | +0,97 | | |
| **6: 64 Punkte pro Instanz** | **+0,17** | **+0,56** | **+0,10** |
| 6: Sim pausiert | +0,25 | | |

Ohne Punkte: 13,9 ms (360), 23,6 ms (25), 15,6 ms (1800) mit dem Ecken-Cache des
Terrains (vorher 143 ms bei 25 km). Runde 2 lag bei 360 km nur scheinbar tief: das
Terrain war damals so teuer, dass die Punkte im Schatten liefen.

Was zählte: Runde 5 zeigte, dass die ~1 ms auch ohne Upload und ohne Pass blieb,
also im Zeichnen selbst. 118 784 Instanzen mit je 3 Vertices füllen die
Vertex-SIMD-Gruppen der GPU kaum; mit 64 Punkten pro Instanz (1856 Instanzen)
fiel die Kosten auf 0,1–0,25 ms. Der Platzierungs-Pass (eine Float-Textur, ein
Pixel pro Person) läuft nur bei Änderungen (in 40–67 % der Frames bei 10 Tagen/s,
fast nie bei pausierter Sim). `sync` (alle 29 Seiten nach einem Sim-Tag)
0,2–0,5 ms im Frame nach dem Tag, sonst 0. GPU-Zeitstempel liefert Godot unter
Metal nicht (0,0), alle Werte sind ganze Frames.

Rom erscheint bei 360 km als schwarze Scheibe von etwa 50 px: rund 1800 simulierte
Personen in einer Scheibe von 6 km Radius (Stadtradius der Town-Tiles), das ist
die echte Dichte.

Runde 9 (Heim-Tiles, Farben, Klick; a928933), 60 km, Rom: ohne Punkte 26,6 ms,
mit Punkten +0,39 ms, schwarz und nach Gruppe gefärbt gleich teuer. Sim-Tag
0,6 ms, View 0,5 ms (Sim-Thread). Die Stadt-Tiles von Rom bleiben sichtbar.

## Wohnorte: Familien, Dörfer und Heim-Tiles

Jeder Haushalt hat in der Simulation ein festes Dorf und ein Haus-Tile
(`sim/src/settle.rs`). Das ist eine reine Funktion von Heimzelle, Haushalt und
Stand mit eigenen Salts: Der Sim-Zustand bleibt unberührt, der Fingerprint ist
gleich (Test `settle::tests`).

- **Feinraster:** dasselbe wie die Getreidewirtschaft (`grain.rs`), 16 × 16
  Tiles von 1,5625 km pro 25-km-Zelle, Index `fr · cols_f + fc`.
  `Settle::home_fine(cell, household, stand)` liefert das Tile, auf dem der Hof
  des Haushalts steht; `house_km` den Ort des Hauses in Welt-km.
- **Dorf:** Jede Zelle hat feste Dörfer, eines pro 25 simulierte Personen beim
  Start (mindestens 1), auf den Fein-Tiles mit dem meisten Ackerland
  (`FineCover`, landcover-fine aus der Getreidewirtschaft), keine zwei Dörfer
  auf Nachbar-Tiles. Bis diese Daten da sind, liegen die Dörfer auf gehashten
  Tiles der Zelle. Ein Haushalt gehört per Hash zu einem Dorf und behält es,
  solange er in der Zelle bleibt.
- **Anzeige:** Der Datensatz trägt die Mitte des Dorf-Tiles. Die GPU setzt das
  Dorf auf die beste von 16 Stellen des Tiles nach Ackerland und offenem Land
  (`cover_tex`), das Haus in 0,8 km Umkreis auf einer Hofparzelle eines
  Rasters von 0,5 km (2 × 2 Feldparzellen; Reihen statt Überlappung; zwei
  Häuser auf einer Parzelle sehen wie eines aus). Im Dorf steht ein Viertel
  der Familie im Vorhof, ein Drittel auf der Gasse um die Hofparzelle, der
  Rest draussen auf den Feldern; in der Stadt jede Person bis 35 m daneben.
  Hat das Tile kein Land (gehashtes Tile an der Küste), sucht sie Land in der
  ganzen Zelle.
- **Stadt:** Stadtbewohner haushaltsweise in der Scheibe ihrer Stadt; ihr
  Haus-Tile ist eine gehashte Stelle in dieser Scheibe.
- **Unterwegs:** irgendwo auf Land in der aktuellen Zelle, dunkelrot.

`PeopleView::update` rechnet eine Person nur neu, wenn sich Heimzelle,
Haushalt, Stand oder Reise geändert haben: 0,8 ms pro Tag (Median, Linux,
vorher 1,6 ms).

## Sichtbarkeit (LOD)

Die Punkte gehören zur Nahstufe: Sie erscheinen nur in den Zoomstufen, in denen
die Terrain Bäume und Häuser zeichnet (`TileTerrain.PROP_SLOTS > 0`, Tiles von
0,5 und 1 km, also bis etwa 110 km Ansichtsbreite). Weiter draußen sind sie aus,
und der Platzierungs-Pass läuft nicht. Die Messwerte bei 360 und 1800 km oben
stammen von vor dieser Regel.

## Figuren in echter Grösse (Ramon, 28.10.2026)

Realistisch statt Übersicht: Bis 10 km Bildbreite steht jede Person als kleine
Klötzchenfigur in echter Grösse auf ihrem Platz (1,7 m im Diorama-Massstab wie
Häuser und Bäume, also 1,7 m × 23,8 in Welt-km; `people_figures.gdshader`).
Füsse, Beine, Tunika, Arme, Kopf und Haar als Quader auf einem Raster von
7 cm im Voxel-Stil der Häuser (Urbek), mit der Eckschattierung der Voxel-Meshes
im Vertex-Alpha, jedes Teil ein eigener Block, damit es schwingen kann; Frauen tragen ein langes Kleid und ein Kopftuch, Kinder unter 14
sind kleiner (Geschlecht und Kind stehen im Datensatz, der Schlüssel hat dafür
14 statt 16 Bit). Kleider in Woll-, Leinen-, Krapp- und Waidfarben oder nach
Farbmodus. Reisende gehen mit schwingenden Beinen und Armen, die anderen
wiegen leicht und drehen sich ab und zu. Die Figuren werfen Schatten wie die
Bäume. Gezeichnet werden nur die Personen nahe
der Ansicht: `ApoleiaPeople.near` liefert ihre Slots (Rust, ein Durchlauf über
die Anker, nur wenn sich die Ansicht deutlich bewegt oder ein Tag kam), höchstens
16 384, als Liste in einer kleinen Textur; das MultiMesh zeichnet genau so viele.
Kleidung und Werkzeug zeigen Beruf und Stand (nur aus dem Datensatz, keine
neuen Sim-Daten): Bauern und Pächter mit Hacke, Soldaten mit Speer, Schild und
rotem Waffenrock, Offiziere mit Schild, Schwert und rotem Umhang, Geistliche im
weissen Gewand mit Stab, Gelehrte im langen grauen Gewand, Handwerker mit
Lederschürze, Händler, Tagelöhner und Unfreie mit Bündel, Unfreie barfuss in
grober Wolle. Senatoren und Adel tragen weisse Wolle mit breiten Purpurstreifen
(clavi) und Purpurumhang, Ritter und Beamte schmale Streifen; Wohlhabende und
Händler leuchtende Farben (Krapp, Waid, Safran). Die Teile stecken alle im
einen Figuren-Mesh (Teil-Nummer in UV.x), der Shader faltet weg, was die Person
nicht trägt. Kinder rennen ums Haus. Für alte Leute fehlt das Alter im
Datensatz, das wäre eine Sim-Änderung.

Weiter oben sieht man keine Menschen, nur Häuser, Felder und Städte. Die Kamera
kommt bis 1 km Bildbreite heran (`MIN_WIDTH` in `landscape.gd`, vorher 4 km):
dann sind die Figuren 40–50 px hoch und Kleid, Kopftuch und Beine erkennbar,
bei 2 km sieht man mehrere Höfe mit ihren Leuten. Die Punkte
sind nur noch eine Übersicht mit Taste `P` (aus beim Start, `--people-dots`).

## Häuser

Jeder Dorf-Haushalt hat ein Haus auf seinem Hausplatz: ein Bauernhaus (casa
rustica) im Voxel-Stil von Urbek wie das Kolosseum-Prototyp
(`scripts/voxel/farmhouse.gd`): verputzte Mauern auf Steinsockel mit
Steinecken, Balken unter der Traufe, Brettertür, kleine Fenster, Walmdach aus
Terrakotta mit dunkleren Ziegelreihen, helleren Trittflächen und Graten,
Schuppen mit Heu, Holzstoss, Busch, Gemüsebeet, Obstbaum, Zaun und ein Weg
durchs Tor bis zur Gasse; ausserhalb des Zauns auf der 21-m-Hofparzelle zwei
schlanke dunkle Zypressen in den vorderen Ecken (ein Sechstel so breit wie
hoch), ein Olivenbaum und ein Heuhaufen. Putz warm creme, Dach tiefes
Terrakotta: die Trittflächen sind dunkler angelegt, als sie erscheinen, da
Sonne und Tonemapping sie sonst nach Orange heben. Die Palette teilt es mit den Stadtgebäuden des
Kolosseum-Prototyps (Caesar III): `people_houses.gdshader` gibt jedem Hof
seinen Putz (creme, rosa, ocker) und seine Läden (grün, braun) über den
Palettenindex, den der Mesher in UV.y schreibt, dazu je Hof einen von vier
Dachtönen und nicht auf jedem Hof Zypressen, Olivenbaum und Heuhaufen (deren
Farben haben eigene Indizes), und spiegelt das Haus je
Parzelle (vier Drehungen, gespiegelt, Grösse ±10 %). Der Mesher (`scripts/voxel/voxel_mesh.gd`) ist allgemein: Modell als
Funktion, nur sichtbare Flächen, gleichfarbige Flächen zusammengefasst, wo die
eingebackene Eckschattierung (Voxel-AO) es erlaubt, keine Unterseiten, jede
Fläche um 1,2 cm in ihrer Ebene vergrössert gegen Pixelrisse an T-Stössen. Drei
Detailstufen mit 0,25, 0,5 und 1 m Voxeln (3584, 706 und 206 Dreiecke),
gebaut beim ersten Start (etwa 2 s) und in `user://farmhouse_v14_*.res`
gespeichert. `ApoleiaPeople.houses_near` liefert die Häuser nahe der Ansicht,
nächstes zuerst, als Liste in einer Textur; drei MultiMeshes zeichnen
aufeinanderfolgende Stücke davon: die nächsten 1024 fein (bis 5 km
Bildbreite), die nächsten 4096 mittel (bis 20 km), den Rest grob, zusammen
höchstens 16 384. Die View
führt dafür eine eigene Tabelle (`view::Houses`, ein Datensatz pro Haushalt
und Heimzelle, gezählt über die Mitglieder, Reisende eingeschlossen), in
festen Slots und Seiten wie die Personen: rund 25 600 Häuser in 7 Seiten, pro
Tag ändert meist 1 Seite. `people_houses.gdshader`
zeichnet sie, ein eigener Platzierungs-Pass (derselbe Shader mit `houses`)
läuft nur, wenn sich Häuser oder die Terrain-Ansicht ändern (auch das
nachgebackene Nahrelief, `levels_*`, `near_scale`, und das Fenster der
Viertelkacheln, `sub_*`). Ein Bauernhaus steht auf einer ebenen, offenen
Hofparzelle (kein Wald, Fels oder Schnee; bis etwa 12 km Sichtbreite 2 × 2
Viertelkacheln auf einer Höhe): auf seiner eigenen oder, liegt die auf
einer Rampe oder im Wald, auf der ersten passenden der acht
Nachbarparzellen (wie in SimCity 2000 wird am Hang nicht gebaut). Drehung, Grösse und Ton hängen an der Parzelle. Die Familie steht im Vorhof, auf der Gasse
oder auf den Feldern (siehe Wohnorte). Stadtbewohner haben kein eigenes Haus, sie
wohnen in den Stadt-Tiles.

## Getreidewirtschaft auf der Karte

Der Sim-Thread der GDExtension rechnet neben den Leuten auch die
Getreidewirtschaft (`grain::Grain`, S69–S87) mit denselben Vorgaben wie
`bin/grain.rs` (heutiges Ackerland rodbar, Felder auf den feinen Kacheln):
`people.day()`, dann `grain.day()`. Der Aufbau kostet beim Laden etwa 1,4 s.
Einmal im Monat baut `grain_map.rs` daraus zwei Kartenebenen, nur über die
lesenden Zugriffe von `grain.rs` (`for_each_plot`, `market_paths`,
`road_levels`, `household`; Fingerprint unverändert mit 1 und 4 Threads), in
etwa 25 ms:

- **Feine Ebene** (eine RGBA8-Kachel pro 1,5625 km): Anteil der Kachel unter
  Feldern, davon eingesät, Wachstum der Saat; Trampelpfade (Stufe und Richtung
  zum Markt) und Marktplätze. `people_dots.gd` lädt ein Fenster von 256 × 256
  Kacheln um die Kamera hoch, wenn ein Monat kommt oder die Kamera die Mitte
  verlässt.
- **Strassenebene** (eine RG8-Kachel pro 25-km-Zelle): Handelsweg (Stufe 1),
  Strasse (Stufe 2), auf See Seeweg, mit den Nachbarn, die sie verbindet.

`sim_map.gdshaderinc` zeichnet das in der Terrain: Parzellen von einer halben
Datenkachel (250 m, aus der Nähe genau eine Viertelkachel des Geländes) als Block um die Mitte jeder feinen
Kachel, so gross wie ihr Feldanteil; nur auf ebenen Kacheln, die Rampen
bleiben Wiese (wie in SimCity 2000; eine Feldfarbe, die die zwei Dreiecke
einer Rampe verschieden tönen, sah aus wie Glasscherben). Fern ist das
Ackerland ein Flickenteppich aus Blöcken von 2 × 2 Kacheln, jeder ganz
eine Frucht, Brache oder Weide (nach Feld- und Saatanteil seiner feinen
Kachel, Brache seltener als in der Sim) und etwas früher oder später gesät
als seine Nachbarn, leicht zur Wiese hin; nicht ihr Mittelwert, der alles
in ein Oliv tauchte; Brache als Trockengras; Pfade zum
Markt, Marktplatz mit Ständen, Dorfgassen zwischen benachbarten Höfen und an
der Seite, der jeder Hof zugewandt ist (dort trifft sein Torweg die Gasse), Handelswege
und Strassen als helles Pflaster mit dunklerem Rand, Seewege gestrichelt.
Taste `G` schaltet das aus und an. Was gezeigt wird, hängt an der
Sichtbreite (`sim_view_km`), nicht an der Pixelgrösse, damit kein Umschalten
als Naht durchs Bild läuft: einzelne Parzellen, Feldplatten und Dorfgassen
bis 8 km, ganze Feldblöcke je eine Frucht bis 40 km, Trampelpfade bis 10 km,
Handelswege und Strassen unter 100 km, Seewege bis 150 km.

Jede Parzelle trägt eine Frucht (`sim_crop_kind`, Hash der Parzelle; fern
je Feldblock): Weizen 40 %, Gerste 20 %, Gemüse und Bohnen 25 %, Reben 15 %.
Bis 8 km steht jede eingesäte Parzelle als erhöhte Feldplatte wie bei Urbek
(`people_crops.gdshader`, eine Instanz pro Parzelle in einem Quadrat von
40 × 40 um die Kamera), 2,5 % vom Parzellenrand eingerückt, damit schmale
Grasränder und Gassen dazwischen laufen. Zwei Bilder wie in Urbeks
Ackerland: dunkle braune Erde mit grünen Reihen, zwischen denen die Erde
sichtbar bleibt, und eine geschlossene strohgelbe Fläche. Weizen und Gerste
wachsen von nackter Erde über lockere Sprossen zu schmalen durchgehenden
Reihen, reifen zu einer strohgelben Fläche und werden zu Stoppeln; eine
brachliegende Parzelle ist eine niedrige Fläche aus trockenen Stoppeln.
Gemüse und Bohnen stehen in 12 Reihen einzelner Büschel hinter einem
Holzzaun auf drei oder vier Seiten, Reben als niedrige Hecken in jeder
zweiten Reihe. Büschelreihen laufen ost-west, damit ihre Vorderseiten zur
Kamera zeigen (die Lücken schneidet der Fragment-Shader); durchgehende
Reihen laufen nord-süd, von der Kamera weg, als Linien (ost-west lasen sich
ihre gestapelten Vorderseiten wie Jalousien). Nord-süd-Reihen werden
gedreht, nie gespiegelt (Spiegeln kehrt die Flächen nach innen). Auf gut der Hälfte der Weideparzellen (nicht bestellt,
offenes Land, kein Hof) steht eine kleine Schafherde, vier bis acht Tiere. Die Regel, welche Parzelle bestellt ist, liegt in
`sim_fields.gdshaderinc` und gilt für Bodenfarbe und Platten gleich. Eine
Maske von 64 × 64 Hofparzellen (`people_lots.gdshader`, ein Pixel pro
Hofparzelle mit Bauernhaus) hält Haus, Garten und Hof frei und legt die
Gassen; die Terrain malt Hofparzellen als Wiese.

Ein Klick auf eine Person zeigt auch die Art des Haushalts (Hof mit
Feldgrösse, Lohn, Zelt, Händler, Oberschicht), wie viel er im letzten Monat
gegessen hat und seinen Vorrat.

## Farben und Klick

- **Farben (Taste C):** schwarz, nach Beruf (13 Berufe von S77), nach
  politischer Gruppe (die Gruppe des Berufs, `groups::JOB_GROUP`) oder nach
  Stand (Landvolk, Stadtvolk, Ritter, Senatoren). Beruf und Stand stehen im
  letzten Feld des Datensatzes (`key << 8 | job << 4 | estate << 2 | kind`,
  Schlüssel 16 Bit), die Farbtabelle kommt als Uniform aus `people_dots.gd`.
  Rechts oben steht die Legende.
- **Klick auf einen Punkt:** `people_dots.gd` liest die Platzierungs-Textur
  einmal zurück, `ApoleiaPeople.pick` sucht in Rust den nächsten Punkt auf
  dem Bildschirm (bis 10 px), und der Sim-Thread liest die Person zwischen zwei
  Tagen aus der Welt (`PeopleView::person`): Geschlecht, Alter, Beruf, Stand,
  politische Gruppen, Haushalt mit Grösse, Ehe, Gewicht und BMI (S84), IQ, Kultur,
  Religion, unterwegs. Der Punkt wird gross und gelb, Esc schliesst.
  Kosten nur beim Klick, kein Aufwand pro Frame.

## Bedienung

`P` Punkte-Übersicht an/aus, `G` Getreidewirtschaft an/aus, `C` Farbe, Klick Person, `Esc` schliessen, `[` / `]` Tage pro Sekunde halbieren/verdoppeln.
Kommandozeile: `--people-days=n` (Standard 10), `--people-bench=pfad.json`,
`--people-colour=n` (0–3), `--people-click=x,y` (für Screenshots),
`--people-warm=n` (n Tage vor dem ersten Bild rechnen).
Ohne gebaute GDExtension (`sim/godot/build.sh`) bleiben die Punkte aus.

## Recherche (Stand Oktober 2026)

- **Persistenter GPU-Puffer, nur Änderungen hochladen:** Unitys
  BatchRendererGroup hält Instanzdaten in einem persistenten GPU-Puffer mit
  CPU-Schattenkopie und lädt nur belegte Fenster hoch
  ([Unity-Blog, BRG-Beispiel](https://unity.com/en/blog/engine-platform/batchrenderergroup-sample-high-frame-rate-on-budget-devices)).
  Bevy 0.16 (GPU-driven rendering, retained render world) vermeidet laut
  Release-Notes das Verarbeiten und Hochladen unveränderter Daten und meldet etwa
  3× weniger CPU-Renderzeit
  ([Bevy 0.16](https://bevy.org/news/bevy-0-16/)). Hier: Texture-Array mit festen
  Slots, Upload pro geänderter Seite.
- **Position im Shader aus Instanz-ID:** Godot-MultiMesh ist GPU-Instancing
  ([MultiMesh-Doku](https://docs.godotengine.org/en/latest/classes/class_multimesh.html));
  die Tile-Terrain dieses Projekts platziert Bäume und Häuser bereits so
  (`tile_props.gdshader`), die Punkte folgen demselben Muster.
- **Rust-Anbindung:** godot-rust/gdext 0.5.5 mit `api-4-7`
  ([docs.rs](https://docs.rs/godot/0.5.5)), wie die bestehende Brücke `ApoleiaSim`.

## Offene nächste Schritte

- **Streu-Update auf der GPU** statt ganzer Seiten: die rund 640 geänderten
  Datensätze (≈13 KB/Tag) als kleine Liste hochladen und mit einem Compute-Shader
  (RenderingDevice, Texture2DRD) in die Textur schreiben. Würde die 0,2–0,5-ms-Spitze
  im Frame nach einem Sim-Tag entfernen.
- Reisende (auch per Schiff) sind dunkelrot und dürfen auf See liegen.
  Daheim-Personen suchen 8 Stellen in ihrer Fläche und 8 in der doppelten, bevor
  ein Punkt auf Wasser fallen kann.

## Cloud-Renders mit Forward+

Ohne GPU rendert die Cloud mit Software-Vulkan (Mesa lavapipe) im gleichen
Renderer wie der Mac, also mit Filmic-Tonemapping und denselben Farben, nicht
mehr mit dem helleren und satteren `opengl3`:

    apt-get install -y mesa-vulkan-drivers
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a \
      godot --rendering-driver vulkan --path app landscape.tscn -- \
      --view=12.7534,41.9063,2 --people-warm=730 --snapshot=dorf.png
