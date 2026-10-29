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
Bäume; da die Schattenkarte für so schmale Körper zu grob ist, legt
`people_figure_shadows.gdshader` zusätzlich unter jede Figur einen flachen
Schattenstreifen von den Füssen weg von der Sonne (Richtung und Länge aus der
Sonne der Szene), der den Boden darunter multiplikativ so dunkel macht wie
ein Hausschatten (Runde 13: Figurenschatten nur 6 % dunkler als das Gras,
die Leute wirkten aufgeklebt). Gezeichnet werden nur die Personen nahe
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
Steinecken, Balken unter der Traufe, Brettertür (seit Runde 21 auch eine in jeder Schmalseite, damit keine Hauswand blind bleibt), Fenster mit Läden und steinerner Sohlbank (vier an der Front, zwei an jeder Schmalseite; Runde 18 breiter und höher, vorher lasen sich die Fassaden als leere Flächen),
Dach aus Terrakotta mit dunkleren Ziegelreihen, helleren Trittflächen und
Graten (die Firste ein helles Rot, #c4664c; dunkel lasen sie sich als Loch, Runde 19, mittel noch als Naht, Runde 20). Vier Bauformen, damit ein Dorf nicht ein Haus in Wiederholung ist,
eine je Parzelle: Walmdachhaus mit Schuppen voll Heu an der Seite, hinter dem Fenster der Schmalseite zurückgesetzt, damit er keines verdeckt; Langhaus
unter Satteldach mit verputzten Giebeln, vier Fenstern und einem Säulengang
(Porticus) über die Front; Walmdachhaus mit einer Bretterscheune als Flügel
vor dem Haus, durch deren offenes Tor unten das Heu und darüber das dunkle Innere zu sehen ist (bis Runde 18 eine helle Strohfläche); seit Runde 20 ein zweistöckiges Haus unter Walmdach, steinernes Gesims zwischen den Geschossen, eine Aussentreppe aus Stein an der Front hinauf zur oberen Tür mit einer dunklen Kellertür unter dem Absatz, und eine Weinpergola (vier Pfosten, ein Blätterdach mit Lücken) im Hof daneben, damit das Dorf in der Höhe wechselt. Dazu Holzstoss (Scheite in Reihen mit dunklen Fugen, seit Runde 21 an der Rückseite des Hofs statt vor der Tür),
Kohlbeet (dunkle runde Köpfe in Reihen, braune Erde dazwischen), Obstbaum,
Zaun und ein Weg durchs Tor bis zur Gasse; im Zaun
gepflegtes Gras in einem satten Grün (#4a8c3a; Runde 18 lag es gleich wie die Weide, Runde 20 bleichte es zu Mint aus), neben dem Weg ein
Vorplatz aus gestampfter Erde (Dreschplatz) mit einem Brunnen (niedrige
Steinfassung, dunkles Wasser, zwei Pfosten und ein Ziegeldächlein); ausserhalb des Zauns auf der 21-m-Hofparzelle zwei
schlanke dunkle Zypressen in den vorderen Ecken (ein Sechstel so breit wie
hoch), ein dunkler Olivenbaum (Runde 18 so hell wie die Wiese, ein Geist) und ein Heuhaufen. Putz warm creme, 4,75 m hohe Wände (Runde 18; vorher war das Haus von oben zu 60 % Dach)
unter einem flachen Walmdach (23°), damit das Dach das Haus von oben nicht
verschluckt; Dach tiefes, nicht grelles Terrakotta: die Trittflächen sind
dunkler angelegt, als sie erscheinen, da Sonne und Tonemapping sie sonst
nach Orange heben. Die Palette teilt es mit den Stadtgebäuden des
Kolosseum-Prototyps (Caesar III): `people_houses.gdshader` gibt jedem Hof
seinen Putz (creme, rosa, ocker) und seine Läden (grün, braun) über den
Palettenindex, den der Mesher in UV.y schreibt, dazu je Hof einen von vier
Dachtönen und nicht auf jedem Hof Zypressen, Olivenbaum und Heuhaufen (deren
Farben haben eigene Indizes). Jede Dachfläche ist als eine Ebene nach ihrer
Neigung beleuchtet (Tritt- und Stossflächen der Ziegelreihen bekommen die
Normale der Dachfläche, die Stossflächen eine Stufe dunkler), so ist die
Seite zum Licht hell, die abgewandte als Ganzes im Schatten, ohne fast
schwarze Ziegelstreifen (Runde 16). Das Licht auf den Häusern steht so hoch
wie das SimCity-Licht der Terrain (Dächer und Hof passen zum Boden), kommt
aber aus der Richtung der Sonne (Westsüdwest): die Westwände hell, die
Fronten eine Stufe dunkler, die Ostwände im Schatten, passend zu den
Schatten der Häuser (Runde 18: Front und Westwand gleich hell, die Häuser
wirkten flach). Das Haus steht je
Parzelle anders (Front mit Tür und Weg zur Kamera auf der Hälfte der Parzellen,
sonst eine Flanke, nie die Rückseite; gespiegelt, Grösse ±10 %). Der Mesher (`scripts/voxel/voxel_mesh.gd`) ist allgemein: Modell als
Funktion, nur sichtbare Flächen, gleichfarbige Flächen zusammengefasst, wo die
eingebackene Eckschattierung (Voxel-AO) es erlaubt, keine Unterseiten, jede
Fläche um 1,2 cm in ihrer Ebene vergrössert gegen Pixelrisse an T-Stössen. Drei
Detailstufen mit 0,125, 0,25, 0,5 und 1 m Voxeln (die feinste für die
nächsten 256 Häuser bis 2 km Bildbreite, damit die Dachstufen klein
bleiben; weiter draussen flimmern ihre Ziegelreihen als Moiré), für jede Bauform gebaut beim ersten Start und in
`user://farmhouse_v34_*.res` gespeichert. Unter der Traufe liegt ein
eingebackenes Schattenband auf dem Putz, der Heuhaufen ist golden mit
dunklerem Band und Fuss, der Zaun dunkelbraun, damit beide sich vom Weizen
lösen. `ApoleiaPeople.houses_near` liefert die Häuser nahe der Ansicht,
nächstes zuerst, als Liste in einer Textur; drei MultiMeshes je Bauform
zeichnen aufeinanderfolgende Stücke davon (jedes lässt die Parzellen der
anderen Bauformen aus): die nächsten 1024 fein (bis 5 km
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
Kachel, so gross wie ihr Feldanteil; nur auf ebenen Kacheln (nach den
Ecken, wie sie sind: gerundet galt eine Kachel unter einer Rampe über mehrere
Kacheln als eben, Runde 18), die Rampen
bleiben Wiese (wie in SimCity 2000; eine Feldfarbe, die die zwei Dreiecke
einer Rampe verschieden tönen, sah aus wie Glasscherben). Ab 8 km
Bildbreite liegt das Ackerland in quadratischen Feldern: in jedem Hofblock (der
feinen Kachel, deren Feldblock höchstens 55 % der Kachel deckt, damit Weide zwischen
den Höfen bleibt: Runde 17 liefen volle Blöcke zu einer Steppdecke zusammen) bilden je 3 × 3 Parzellen von 250 m ein Feld
in einer flachen Farbe: Urbeks Weizengelb oder das Grün wachsenden
Getreides (#82b85a; dunkler las es sich wie der Schatten einer Rampe, Runde 19, gelber als Giftgrün, Runde 20), selten gepflügtes Braun; die Brache ist
beweidetes Gras, so liegen die Felder in ruhigen Gruppen auf Grün (gut die
Hälfte bleibt Weide) und bleiben leiser als die Stadt; nur auf ebenen
Kacheln. Runden 12 bis 18: einzelne Parzellen, Flecken von 2 × 2 km,
Streifen, ein Saatgrün zu nah an der Wiese oder vier Töne mit Ocker lasen
sich als Tarnmuster, Konfetti oder Strichcode.
Zwischen den Feldplatten liegt Erde in Urbeks Feldweg-Farbe #888068 statt
Wiese, und die Platten stehen 4 % statt 2,5 % vom Parzellenrand weg: so
laufen etwa 12 px breite Feldwege zwischen den Feldern (r11: auf Wiese lagen
die Felder wie Teppiche ohne Weg dazu).
Die Feldplatten bekommen einen hellen Rand von 1-2 px wie Urbeks Platten
und bleiben flach (Büschel darauf lasen sich als dunkle Striche, Runde 16,
helle Garben als Nieten, Runde 18); auf allem reifen Korn stehen
helle Ährenbüschel in dichten Reihen (Runde 21; nackte Platten lasen sich als leere Tabletts). Keine Platte steht am Fuss einer Rampe
direkt vor ihr (nach Süden, zur Kamera): die Rampe verdeckte einen Teil, das
Feld sah abgeschnitten aus (Runde 18; auch die Seiten und Diagonalen zu
prüfen leerte ganze Hänge). Gassen und Feldwege halten
die Platten frei (`crop_box`), und eine Dorfgasse läuft als Feldweg eine
Hofbreite weiter zwischen die Felder, statt am Dorfrand vor einer Platte zu
enden (Runde 17),
und wer in einem Feld arbeitet, steht auf der Platte statt hüfttief darin
(`people_crop_slab.gdshaderinc`, geteilt vom Feld- und vom
Platzierungs-Shader).
Ausserhalb des Quadrats der Feldplatten tragen auch die nahen Parzellen
diese Farben. Pfade zum
Markt, Marktplatz mit Ständen, Dorfgassen (34 m breit) zwischen benachbarten Höfen und an
der Seite, der jeder Hof zugewandt ist (dort trifft sein Torweg die Gasse), Handelswege
und Strassen als helles Pflaster mit dunklerem Rand, Seewege gestrichelt.
Taste `G` schaltet das aus und an. Was gezeigt wird, hängt an der
Sichtbreite (`sim_view_km`), nicht an der Pixelgrösse, damit kein Umschalten
als Naht durchs Bild läuft: einzelne Parzellen, Feldplatten und Dorfgassen
bis 8 km, ganze Feldblöcke je eine Frucht bis 40 km, Trampelpfade bis 10 km,
Handelswege und Strassen unter 40 km (weiter draussen lasen sie sich als Kratzer), Seewege bis 150 km.

Jede Parzelle trägt eine Frucht (`sim_crop_kind`, Hash der Parzelle; fern
je Feldblock): Weizen 40 %, Gerste 20 %, Gemüse und Bohnen 25 %, Reben 15 %.
Bis 8 km steht jede eingesäte Parzelle als erhöhte Feldplatte wie bei Urbek
(`people_crops.gdshader`, eine Instanz pro Parzelle in einem Quadrat von
40 × 40 um die Kamera), 2,5 % vom Parzellenrand eingerückt, damit schmale
Grasränder und Gassen dazwischen laufen. Zwei Bilder wie in Urbeks
Ackerland: dunkle braune Erde mit grünen Reihen, zwischen denen die Erde
sichtbar bleibt, und eine geschlossene strohgelbe Fläche. Weizen und Gerste
wachsen von nackter Erde über lockere Sprossen zu schmalen, buckligen
Reihen, reifen zu einer strohgelben, 1,2 m hohen Platte und werden zu
Stoppeln; eine brachliegende Parzelle ist eine 0,8 m hohe Platte aus
trockenen Stoppeln im Weizengelb. Unter bestellten und brachen Parzellen
malt die Terrain Wiese, so steht jede Platte mit sichtbarer Kante in
einem Grasrand.
Gemüse und Bohnen stehen in 8 Reihen einzelner Büschel (12 lasen sich aus 3 km als Punkte, Runde 22), mindestens 8 px breit, Reben als
niedrige Hecken in jeder zweiten Reihe; die Felder neben einem Hof sind
ringsum eingezäunt, weiter draussen keines. Die Grüntöne liegen dunkler als
die Wiese daneben, wie bei Urbek. Büschelreihen laufen ost-west, damit ihre Vorderseiten zur
Kamera zeigen (die Lücken schneidet der Fragment-Shader); die Reihen des
Getreides laufen nord-süd, von der Kamera weg, als Linien (ost-west lasen
sich ihre gestapelten Vorderseiten wie Jalousien). Nord-süd-Reihen werden
gedreht, nie gespiegelt (Spiegeln kehrt die Flächen nach innen). Auf gut der Hälfte der Weideparzellen (offenes Land,
kein Hof) steht eine kleine Schafherde (lange, niedrige Körper in hellem
Wollweiss #e4dccc auf dunklen Beinen, die Längsseite zur Kamera), sechs bis
zehn Tiere auf einem Raster von 3 × 3 Plätzen, damit keine zwei ineinander
stehen (Runde 22). Die Regel, welche Parzelle bestellt ist, liegt in
`sim_fields.gdshaderinc` und gilt für Bodenfarbe und Platten gleich. Eine
Kein Feld liegt unter Bäumen oder in der Stadt (`sim_no_field`, Runde 22):
nicht auf Datenkacheln mit Wald oder Siedlung in der Nachbarschaft, im Süden
unter 700 m und mit Ölbäumen zwei Kacheln weit; gepflügte Erde ist
Urbeks #8c5c3c. Trampelpfade und Marktplätze enden am Stadtrand, statt über
das Pflaster zu laufen. Eine
Maske von 64 × 64 Hofparzellen (`people_lots.gdshader`, ein Pixel pro
Hofparzelle mit Bauernhaus) hält Haus, Garten und Hof frei und legt die
Gassen; die Terrain malt Hofparzellen als Wiese.

Ein Klick auf eine Person zeigt auch die Art des Haushalts (Hof mit
Feldgrösse, Lohn, Zelt, Händler, Oberschicht), wie viel er im letzten Monat
gegessen hat und seinen Vorrat.

## Unterwegs: Träger und Wagen (Ramon, 29.10.2026)

Die Leute, die man aus der Nähe laufen sieht, gehen dorthin, wohin die
Wirtschaft sie schickt (`scripts/sim/people_trips.gd`,
`shaders/people_walkers.gdshader`). `ask_trips(min_x, min_z, max_x, max_z)`
bittet den Sim-Thread zwischen zwei Tagen um alle Fahrten, deren Weg das
Fenster berührt (`Grain::trips_in`, Simulations-Thread, etwa 4500 auf der
ganzen Karte, 2,5–6 ms); `take_trips()` bringt sie als Packed-Arrays
(`sim/godot/src/trips.rs`): Art (Verkauf, Einkauf, Ausfuhr, Einfuhr),
Ladung in kg, Abreise, Ankunft und Heimkehr in Tagen und den Weg in Welt-km.
Marktgänge folgen dem Trampelpfad Kachel für Kachel, Handelsfahrten den
Zellmitten der Handelswege, genau dort, wo die Strassen gezeichnet sind.

- Bauern gehen mit einem Esel zum Markt, mit Säcken auf dem Weg, auf dem sie
  Korn tragen (beim Verkauf hin, beim Einkauf zurück). Händler fahren einen
  Ochsenkarren, beladen auf der Ausfuhr hin, auf der Einfuhr zurück.
- Jede neue Fahrt wird ein Läufer, der seinen Weg in lesbarem Tempo geht,
  egal wie viele Tage pro Sekunde laufen: er beginnt dort, wo ihn die
  Simulation gerade hat, tritt ein langer Weg erst im Bild auf, tritt er dort
  ein, und geht bis ans Ende seines Wegs oder aus dem Bild. Kehrt er am selben
  Tag heim, dreht er am Ziel um.
- Höchstens 300 gleichzeitig; gefragt wird einmal pro Sim-Tag und wenn die
  Kamera weiterzieht. Gezeichnet nur aus der Nähe, mit den Figuren.
- Tuniken in den acht Farben der Figuren (Wolle und Leinen, Krapprot,
  Waidblau, Brauntöne, Blattgrün; in Brauntönen allein wirkten die ersten
  Läufer nackt); Beine und Arme schwingen beim Gehen.
- Wer denselben Weg am selben Tag geht, geht nicht im Gänsemarsch
  ineinander: jeder hat seine Spur quer zum Weg (bis 90 m bei Diorama-Grösse)
  und einen Versatz längs (bis 200 m). Über Wasser (Meer, See, das Band
  eines Flusses mit seinem Ufer) sind sie nicht zu sehen: sie nehmen Brücke
  oder Fähre (die ersten liefen über den Tiber; die ganze Flusskachel
  auszublenden versteckte auch die Stände eines Markts am Ufer).
- Am Ende des Wegs bleiben sie 6 s stehen, am Markt zwischen den Ständen,
  am Hof bei der Arbeit, dann gehen sie heim.
- **Marktstände:** auf jedem Marktplatz, den die Terrain zeichnet
  (`ApoleiaPeople.market_squares`, Bit 6 der feinen Ebene), stehen bis 10 km
  Sichtbreite sieben Stände mit Tresen, vier Pfosten und rot-weiss
  gestreiftem Dach (#d46048, Rahmen #804c28, wie die Stände am Forum), Ware
  darauf, der Tresen zur Mitte (r11: der Platz war nur ein flaches Muster).
- **Erntehelfer:** `ask_work(Fenster)` liefert, wer bei der letzten
  Wochenbörse jeder Region auf welchem Hof arbeitet (`Grain::work_in`,
  `trips::work_to_dict`). Jede neue Anstellung schickt den Arbeiter von
  seinem Haus geradeaus zum Hof und zurück: mit Saatkorb zur Saat, mit
  Sichel zur Ernte, sonst mit der Hacke auf der Schulter. Höchstens die
  Hälfte der 300 Läufer sind Helfer, der Rest bleibt den Fahrten.

Ein Klick auf eine Person zeigt jetzt auch das Geld ihres Haushalts in
Denar (`HouseholdLook.money`, so wie es ist, auch unter null: Händler zahlen
Aus- und Einfuhr auch mit leerer Kasse).

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

## Tabellen im Stil von EU5 (Ramon, 29.10.2026)

Taste `T` (oder der Knopf links oben) öffnet links ein Panel mit fünf
Tabellen: Märkte, Bevölkerung nach Region und Beruf, Höfe nach Region und
Staat (Kasse und Geldkreislauf seit Spielstart, S94; eine Zeile ohne Ort,
darum als Liste aus Posten und Betrag gezeigt) und Verlauf (eine Zeile pro Monat, unten) (`scripts/sim/sim_tables.gd`). Die Daten liefert die Simulation
(`sim/src/tables.rs`, `Grain::table`; Simulations-Thread): `ask_table(kind)`
bittet den Sim-Thread darum, zwischen zwei Tagen gebaut kommt die Tabelle mit
`take_table()` als Spalten in Packed-Arrays, mit Spaltenköpfen und Einheiten
(`sim/godot/src/tables.rs`). Das Panel fragt neu, sobald die nächste
Monatszählung fertig ist (Tag 17 eines Monats), sonst nie.

- Klick auf einen Spaltenkopf sortiert (nochmals: umgekehrt), Zahlen grösste
  zuerst, Namen A bis Z.
- Suchfeld über alle Textspalten; Textspalten mit höchstens 64 Werten
  (Beruf) bekommen ein Auswahlmenü. Beim Tippen steht die Kamera still.
- "nach Beruf zusammenfassen" klappt die Zeilen in Gruppen mit Summen;
  Anteile (Einheit `%`, als Prozent mit goldenem Balken), Mittelwerte
  (`mean` im Schlüssel) und Werte je Menge (`Denar/kg`) nach Menschen
  gewichtet, Werte je Zeit (`kg/Tag`) summiert. Die erste Zeile ist immer
  die Summe der gefilterten Zeilen.
- Klick auf eine Zeile fliegt die Kamera zum Ort (`lon`, `lat`, Breite aus
  `extent_km`), in die Mitte des freien Teils neben dem Panel.
- Je Ebene höchstens 300 Zeilen (1783 Märkte, über 20 000 Zeilen
  Bevölkerung), der Rest als Zahl in einer letzten Zeile; Suchen oder Filtern
  holt jede Zeile. Gruppen bauen ihre Zeilen erst beim Aufklappen.
- Farben des Hauptmenüs (dunkles Petrol, helle Schrift) mit Gold für Köpfe,
  Linien und Balken; Zahlen mit Hochkomma (116’805), Datum im römischen
  Kalender ("Martius, Jahr 3").

### Verlauf und Karte färben

- **Verlauf** (fünfter Reiter, Tabelle `history`, eine Zeile pro Monat):
  jede Reihe mit dem letzten und dem vorletzten Monat und der Veränderung;
  ein Klick auf eine Reihe zeichnet sie oben als Kurve über die Monate,
  Jahre an der Grundlinie. Bei den Preisen liegt die Spanne von min bis max
  als Band um den Median.
- **Karte färben** (bei den Märkten): färbt jede Region nach der Spalte,
  nach der sortiert ist, in fünf Klassen mit gleich vielen Regionen, von
  Strohgelb bis Krapprot, mit dunkler Grenze zwischen den Regionen, wie
  EU5s Kartenmodi. Die Zuordnung Zelle → Markt liefert
  `ApoleiaPeople.region_map()` (`Grain::cell_markets`, monatlich mit der
  Kartenebene); `people_dots.gd paint_regions` legt sie als Textur auf das
  Terrain, `sim_regions` in `sim_map.gdshaderinc` (im bestehenden Aufruf
  von `sim_ways`, kein neuer Haken im Terrain-Shader) malt sie über das
  Land, das Meer bleibt frei. Die Farben bleiben, wenn das Panel zugeht (es
  deckt den grössten Teil der Karte), mit ihrer Legende unten links; deren ✕
  schaltet sie ab. `--tables-map=price` färbt ohne offenes Panel.

## Ereignisse (Taste E)

Unten rechts listet `scripts/sim/sim_events.gd` die letzten Ereignisse im
Bild und rundherum (mindestens 30 km um die Mitte, weil Umzüge in der Mitte ihrer 25-km-Zelle liegen), neueste zuerst, eine Zeile pro Tag und Art mit Anzahl
und Menge: Hungertod, Umzug, Verlässt die Karte, Zieht zu Verwandten,
Diebstahl (kg), Almosen (kg), Zelt zieht um, Hof übernommen, Erbteil, Ins
Zelt, Hof nach Lex Manciana, Hof verlassen (`sim/src/events.rs`, 60 Tage
gehalten). `ask_events(seit, Fenster)` fragt einmal pro Sim-Tag, höchstens
einmal pro Sekunde (`Grain::events_in`, `trips::events_to_dict`). Ein Klick
auf eine Zeile fliegt die Kamera dorthin. Hungertod rot, Diebstahl und
Verlust orange, Almosen gold, Höfe grün.

Die Ereignisse der letzten 15 Tage stehen auch als Nadeln auf der Karte:
eine Scheibe in der Farbe der Art auf einem kurzen Stiel, mehrere einer Art
nah beieinander (ein Vierzehntel der Sichtbreite) als eine Nadel mit ihrer
Zahl. Zeigen nennt sie, ein Klick fliegt hin. Hof-Ereignisse (Diebstahl,
Hof übernommen, Erbteil, Lex Manciana, Hof verlassen, Zelt zieht um) stehen
am Hofplatz, die übrigen in der Mitte ihrer 25-km-Zelle. Mit `E` gehen Liste
und Nadeln weg.

## Bedienung

`P` Punkte-Übersicht an/aus, `G` Getreidewirtschaft an/aus, `C` Farbe, `T` Tabellen, `E` Ereignisse, Klick Person, `Esc` schliessen, `[` / `]` Tage pro Sekunde halbieren/verdoppeln.
Kommandozeile: `--people-days=n` (Standard 10), `--people-bench=pfad.json`,
`--people-colour=n` (0–3), `--people-click=x,y` (für Screenshots),
`--people-warm=n` (n Tage vor dem ersten Bild rechnen),
`--tables=markets|population|farms|state|history` (Panel offen auf dieser Tabelle),
`--tables-map=spalte` (Karte nach dieser Spalte der Märkte färben), `--no-events`.
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
