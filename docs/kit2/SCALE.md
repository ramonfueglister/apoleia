# Kit 2 — Massstab der Modellwelt

**Stand:** 27.10.2026 (umgestellt von 50'000 auf 100'000 Personen) · **Status:** `entschieden` (Ramon, Projekt-Thread „Design a scaled-down diorama world“).
Konzeptseite mit Herleitung: Artifact „Diorama mit 100'000 Menschen“.
Werte mit „geschätzt“ sind eigene Annahmen.

## Grundregel

Die ganze Welt wird **in einem einzigen Massstab** verkleinert: Karte, Distanzen,
Städte, Bevölkerung und jede Bewegung. Jeder Einwohner wird **einzeln simuliert**,
mit Familie, Eigenschaften und Lebenslauf wie in Crusader Kings 3.

| Grösse | Faktor | Herleitung |
|---|---|---|
| Menschen, Häuser, Betriebe, Schiffe, Soldaten (Anzahl) | 1 : 566,5 | 56,65 Mio. im Spielgebiet (HYDE 3.3, 200 n. Chr.) → 100'000 |
| Fläche | 1 : 566,5 | gleiche Dichte wie damals |
| Länge, Distanz | 1 : 23,8 (gerundet 1 : 24) | √566,5 |
| Höhe | 1 : 23,8, danach 7,5-fach überhöht | SimCity 2000, PR #29 (K06); nah im Spiel fest 7,5-fach je erstem Stufenschritt (20 m), seit 31.10.2026 bei jeder Sichtbreite (`NEAR_EXAGGERATION`) |
| Geschwindigkeit jeder Bewegung | 1 : 23,8 | damit jede Reise so lange dauert wie damals |
| Kalender, Lebensalter, Tageslänge | 1 : 1 | ein Spieljahr ist ein Jahr |

**Nicht verkleinert** wird der einzelne Mensch und was zu ihm gehört: Körper, Haus,
Hausrat, Wagen, Boot, Feld einer Familie. Weil Fläche und Menschen im selben
Verhältnis schrumpfen, hat jeder Mensch gleich viel Land wie damals; die Anteile
von Feld, Wald, Weide und Ödland bleiben gleich.

**Gemeinschaftsbauten** (Forum, Tempel, Thermen, Arena, Hafen, Lager) haben so
viele Nutzer, wie die Sim schickt: Im Kolosseum (50'000 Plätze) sitzen etwa 90.
Ihre **Grösse** folgt bei Wahrzeichen der Wahrzeichenregel (S136, unten): selektiv
verdichtet, grösser als jedes Haus, in der echten Reihenfolge; leere Plätze bleiben leer.

## Eckwerte

| Was | Damals | Im Diorama |
|---|---:|---:|
| Kartenausschnitt (`data/region.json`) | 4'900 × 4'100 km | 206 × 173 km |
| Landfläche (`data/gametiles/tiles.csv`) | 15,6 Mio. km² | 27'600 km² |
| Italien, Länge | ≈ 1'000 km | ≈ 42 km |
| Rom | ≈ 920'000 Einw., ≈ 20 km² | 1'626 Einw., ≈ 190 × 190 m, gut 250 Häuser |
| Städte ab 100 / 20 / 5 Einw. (Hanson 117, `places.csv`) | – | 19 / 203 / 537 |
| Landbevölkerung | ≈ 80 % | ≈ 82'300 |
| Häuser (≈ 6 Menschen je Haushalt, geschätzt) | – | ≈ 16'700 |
| Basis-Tile 25 km (K25) | 25 km | ≈ 1'050 m |
| Feinstes Tile Ebene 7 | 1,56 km | ≈ 66 m |
| Grafikkachel 0,5 / 16 km (PR #29) | 0,5 / 16 km | ≈ 21 m / 670 m |
| Höhenpunkt ETOPO 15″ | ≈ 460 m | ≈ 19 m |

## Koordinaten

- Geodaten, Tile-IDs (`eqc41-gt-v1`) und alle Kit-1-Daten bleiben in **echten Metern**.
  Nichts aus Kit 1 wird neu erzeugt.
- Weil Längen und Geschwindigkeiten mit demselben Faktor schrumpfen, rechnet die
  Simulation Wege und Reisezeiten direkt in echten Metern und echtem Tempo; das
  Ergebnis ist dasselbe.
- Die Konstante `DIORAMA_LAENGE = 1 / 23,80` rechnet echte Meter in Diorama-Meter um.
  Sie gilt für Darstellung und für alle Dinge in Menschengrösse (Haus, Feld, Figur),
  die in Diorama-Metern definiert sind und beim Platzieren umgerechnet werden.
- Dichten (Einw./km²) sind in Diorama-km² gleich wie damals. In echten Koordinaten
  gerechnet sind sie 566,5-mal kleiner. Die Schwellen S15 gelten in Diorama-km².

## Zeit und Bewegung

| Weg | Im Diorama | Dauer |
|---|---:|---:|
| Zu Fuss | ≈ 0,17 km/h | wie 4 km/h |
| Quer durch Rom | ≈ 190 m | ≈ 1 Stunde |
| Rom – Brundisium zu Fuss | ≈ 24 km | ≈ 2 Wochen |
| Rom – Alexandria per Schiff | ≈ 80 km | ≈ 2–3 Wochen |

- Reisen laufen wie in CK3 als Reise mit Ziel, Route und Dauer in Tagen.
- Der Alltag (Feld, Werkstatt, Markt) wird nicht als einzelner Gang simuliert. Man
  lebt, wo man arbeitet; Figuren dabei sind Animation.
- Wetter (Fronten, Wolken, Stürme) verkleinert sich in Grösse und Zuggeschwindigkeit
  im selben Massstab; ein Unwetter dauert so lange wie damals. Sonnenstand und
  Tageslänge bleiben echt.

## Folgen, die mitbedacht werden müssen

| Bereich | Folge des Massstabs | Vorschlag |
|---|---|---|
| Stände | Senat (600) ≈ 1 Senator, Ritter (≈ 20'000–30'000, geschätzt) ≈ 35–55, Dekurionen (≈ 100'000–150'000, geschätzt) ≈ 175–265, Sklaven (10–15 %, geschätzt) ≈ 10'000–15'000 | **entschieden (S58):** Ämter nach Aufgabe statt nach Massstab. Senat **40 Senatoren** (≈ 30 Statthalter, 2 Konsuln, Legaten, ≈ 10 in Rom), mit Familien ≈ 150 Personen. Jede Provinz hat einen Statthalter, jede Legion einen Legaten, Ritter ≈ 60 (Prokuratoren). Übrige Stände im Massstab. |
| Heer | Reichsheer ≈ 350'000 (geschätzt) → ≈ 620 Soldaten; eine Legion ≈ 10 Mann | Schlachten sind Gefechte weniger Personen; jeder Soldat ist ein Charakter. |
| Wirtschaft | Verbrauch und Leistung pro Kopf bleiben, Summen /566,5. Preise pro Stück bleiben, Staatshaushalt ≈ 900 Mio. Sesterzen → ≈ 1,6 Mio. (geschätzt) | Wirtschafts-Thread rechnet pro Kopf; aggregierte Mengen aus Quellen durch 566,5 teilen. |
| Flüsse und Strassen | Tiber ≈ 60 m → ≈ 2,5 m, aber Boote und Wagen bleiben in Menschengrösse | Wasserläufe und Strassen mit Verkehr bekommen mindestens die Breite ihres Verkehrsmittels. Abweichung offen ausweisen. |
| Kleine Orte | 133 Orte liegen unter 2 Einwohnern, 66 davon sogar unter 1 (z. B. Toledo, Siena, Eleusis, Carcassonne) | **entschieden (S57):** jeder Ort bekommt mindestens 2 Einwohner, ein Paar als Familie (zusammen rund +125 Personen). |
| Kleine Zahlen | Zufall wirkt stärker: Ein Hof kann aussterben | offen |
| Wachstum | 680 n. Chr. ≈ 145'000; 200'000 sind bei ≈ 113 Mio. echten Menschen erreicht (Mittelalter) | **entschieden (S59):** feste Obergrenze, Startwert 200'000 Personen. Der Massstab bleibt 1:566,5 für alle Epochen. |
| Kamera | nächster Zoom zeigt einzelne Häuser (≈ 10 m) | Ausschnittsbreiten aus Kit 1 („Stadt 5–10 km“, „500 m“) gelten in echten Metern; im Diorama ist Rom 190 m breit. |

## Was sich in Kit 2 ändert

- **S30 und S32 werden ersetzt** (siehe decisions.md S50–S56): Bevölkerung ist die
  Summe einzelner Menschen. Wie sie wächst und schrumpft, ist noch offen.
- Kapazität K (S31, S35) bleibt; wie sie auf die einzelnen Menschen wirkt, ist offen.
- HYDE (S35) verteilt die 100'000 Menschen zum Start, deterministisch mit Seed.
- Tile-Raster, IDs, Teilen und Zusammenlegen (S10–S15) bleiben als Gliederung für
  Märkte, Provinzen und Kartenmodi.
- Rust-Kern, Befehle, Festkomma und Snapshots (S40–S48) bleiben; Menschen sind Entities.

## Massstabstabelle (Ramon 31.10.2026: «wir sind ein Diorama, alles muss geschrumpft sein»)

Jedes sichtbare Ding steht hier mit seiner Regel. Geschrumpft wird alles ausser
dem einzelnen Menschen und dem, was ihm gehört (S51). Eine neue Grafik- oder
Sim-Runde prüft gegen diese Tabelle. Jede Ausnahme entscheidet Ramon vorher.
Weltkoordinaten im Code sind echte km; «Diorama-m» = Welt-m × 0,0238
(`DIORAMA_KM_PER_M`).

| Ding | Regel | Zahl | Quelle (Sim / Daten) | Code | Stand |
|---|---|---|---|---|---|
| Karte, Distanzen | 1 : 23,8 | Italien ≈ 42 km Diorama | Geodaten in echten m | Weltkoordinaten = echte km | stimmt |
| Menschen (Anzahl) | 1 : 566,5 | 100'000–200'000 | `sim` Personen | – | stimmt |
| Figur | nicht verkleinert | 1,7 m | Person | `people_dots.gd FIGURE_M` | stimmt |
| Bauernhaus, Stadthaus | nicht verkleinert | Hof 15 m, Los 10 m | Haushalt | `HOUSE_M`, `voxel/farmhouse.gd` | stimmt |
| Feld einer Familie | nicht verkleinert | Median 8,4 Welt-km vom Hof ≈ 350 m Diorama | `Grain::near_field` | `people_fields`, `sim_fields` | stimmt (Sonde 31.10.) |
| Baum | nicht verkleinert (Urbek 5–8 m) | 8 m | Bodenbedeckung | `TREE_M` | nah stimmt; ab 1-km-Kacheln 1,8-fach (`TREE_FAR_GROW`), **offen** |
| Höhe | 1 : 23,8, nah 7,5-fach, fern Stufe 0,6 km | Alpen ≈ 6 km Welt | ETOPO | `NEAR_EXAGGERATION`, `FAR_LEVEL_KM` | stimmt (#105, #112) |
| Stadtfläche | Fläche 1 : 566,5 wie Menschen | Rom ≈ 13 km² Welt, ≈ 250 Häuser | Stadtplan `area_ha`, Sim-Einwohner | `build_tile_terrain.py settlements` | stimmt (#110) |
| Stadtzeichen fern | Zeichen, kein Massstab | ein Hauslos 9 px | Einwohner 117 | `city_markers.gd` | so entschieden (Bauplan B) |
| Wahrzeichen (Arena, Thermen, Circus, Theater) | Wahrzeichenregel (S136): Fläche und Höhe gegen das Haus mit der Kubikwurzel verdichtet, Form, Türen, Sitze, Menschen echt; Nutzer aus der Sim | Kolosseum 30,7 × 25,4 m, 23 m; 88 Zuschauer | Sim-Einwohner der Stadt | `voxel/roman_arena.gd`, `voxel/roman_landmarks.gd`, `city_plans.py USER_SIZED_M` | **stimmt für Rom:** Kolosseum, Caracalla-Thermen, Marcellustheater, Circus Maximus (Tabelle unten). **Weichen noch ab:** Amphitheater, Theater, Thermen und Circus anderer Städte (`plan_*`, ein Los), Schritt 2 |
| Tempel, Forum, Pantheon | Wahrzeichenregel (S136) | – | – | `voxel/roman_town.gd`, `city_plans.py` | **weicht ab:** ältere Kit-Modelle, auf den Planblock geschrumpft (Stadtplan echte Grundfläche ×2,5, `LANDMARK_GROW`), Schritt 2 |
| Brücke ohne Stadtplan | Breite ihres Verkehrs | – | – | `LANDMARK_KM_PER_M` 6-fach | **weicht ab**, nur ohne Stadtpläne sichtbar |
| Landstrasse | Breite ihres Verkehrsmittels | 4 m | Strassen-Lose (S116) | `road_view.gd ROAD_KM` | stimmt |
| Trampelpfad | aus dem Gehen, 8 Stufen | bis 0,042 Welt-km | Wegabnutzung (S70) | `sim_fields SIM_WAY_KM` | stimmt |
| Befestigter Weg | Kies, so breit wie seine Abnutzung, mindestens Stufe 3 (Ramon 31.10.: B) | 0,013–0,042 Welt-km | öffentliche Arbeit (S133) | `sim_fields sim_way_half` | stimmt |
| Reise zwischen Orten | Tempo 1 : 23,8 = Dauer wie damals | 4,5 km/h in Welt-km | Reisen der Sim | `day_clock.gd WALK_KMH` | stimmt |
| Weg zum eigenen Feld | im eigenen (unverkleinerten) Land Menschentempo | 4,5 km/h ÷ 0,0238 | `people_fields` | `dot_field_way` | stimmt (#114) |
| Szenenwege (Markt, Besuch) | aus der Sim | 1,2 Welt-km Start | – | `people_trips.gd OUT_KM` | **weicht ab:** eigene Zahl der Ansicht |
| Marktstände | Menschengrösse um den Platz | 85–95 Welt-m vom Platzmittel ≈ 4 m Diorama | Marktplatz der Sim | `people_trips.gd STALLS` | stimmt |
| Wetter | Grösse und Zug 1 : 23,8, Dauer echt | – | – | `weather/` | **weicht ab** laut Bericht 31.10. (nicht verkleinert), prüfen |
| Kalender, Tag, Sonne | 1 : 1 | – | – | `day_clock.gd` | stimmt |

## Wahrzeichenregel (S136, Ramon 31.10.2026)

Ramon: «das Kolosseum muss auch in der Spielwelt massstäblich grösser sein als das
Haus» und «das riesige Rom in einer Mini-Variante, die begreifbar ist, … zugleich
die Grössenverhältnisse adaptiert wiedergeben». Mit Häusern in echter Grösse und
Roms Fläche 1 : 566,5 passt ein Kolosseum im echten Verhältnis (19 Häuser lang)
nicht in die Stadt, eines nach Nutzern (88 Plätze) wäre kleiner als ein Haus.
Darum **selektive Verdichtung**, wie Modellbahnen (Verducci 2010), Touristenkarten
(Grabler et al. 2008) und Stadtmodelle (Glander & Döllner 2008) sie machen
(Literatur: https://claude.ai/artifact/1gWXz2MKsPEHxHTvaNSh3U):

- Häuser, Menschen, Tiere, Türen, Bögen, Stufen und Sitze bleiben **echt gross**.
- Ein Wahrzeichen behält **seine Form** (Seitenverhältnis, Geschosse, Bauteile).
- Gegen das Haus (Los 10 m = 100 m², höchstes Haus 16 m):
  Fläche = 100 m² × (echte Fläche / 100 m²)^(1/3),
  Höhe = 16 m × (echte Höhe / 16 m)^(1/3), sobald die echte Höhe über 16 m liegt.
- Auf den Rängen sitzen so viele, wie die Sim schickt (echte Plätze ÷ 566,5);
  die übrigen Plätze bleiben leer.

Damit stehen alle Wahrzeichen über dem höchsten Haus, und ihre Reihenfolge stimmt.
Längenverhältnis Kolosseum zu Haus: echt 19, im Spiel 3; Höhe echt 3, im Spiel 1,4.

| Bau | echt | im Spiel | Höhe echt → Spiel | in der Sim | Plan Rom | Code |
|---|---|---|---|---|---|---|
| Kolosseum | 188 × 156 m (Oval) | 30,7 × 25,4 m, Arena 13,5 × 7,8 m, drei Bogengeschosse zu 5,5 m, Attika 6 m | 48 → 23 m | 88 Zuschauer | 4 × 3 Parzellen | `roman_arena.gd` |
| Thermen des Caracalla | 214 × 110 m | 34,7 × 17,5 m, Frigidarium 19,9 m | Kuppel 38,5 → 21,4 m | 3 Badende | 4 × 2 | `roman_landmarks.gd baths` |
| Marcellustheater | Ø 130 m | Ø 28 m, zwei Bogengeschosse zu 7 m und Attika, Bühne im Westen | 32,6 → 20,3 m | 26 Zuschauer, 3 Schauspieler | 3 × 4 | `roman_landmarks.gd theatre` |
| Circus Maximus | 621 × 118 m | 69 × 13 m, drei Bogengeschosse zu 6 m, Obelisk 18 m | 28 → 19,3 m | 265 Zuschauer, 4 Gespanne | 8 × 2 | `roman_landmarks.gd circus` |
| höchstes Haus (Insula) | – | Los 10 m | 16 m | ein Haushalt je Geschoss | 1 | `roman_town.gd` |

Der Stadtplan setzt diese vier zuerst und schiebt sie bis 6 Parzellen von ihrem
echten Ort, wenn dort Wasser oder Mauer ist (der Circus liegt darum 0,75 km östlich
seines Tals); Bauten, deren Platz sie nehmen, weichen bis 4 Parzellen aus. Roms
Mitte trägt damit mehr Wahrzeichen und weniger Häuser (Wohnparzellen 87 → 66).
Vorschaubilder: `/mnt/project-files/groessen/ein-massstab/diorama-uebersicht.jpg`,
`diorama-nah.jpg`, Zwillinge in Python `vorschau-code/` (vd.py).

**Schritt 2 (offen):** Forum, Pantheon, Tempel, Brücken (`LANDMARK_KM_PER_M`),
Amphitheater, Theater, Thermen und Circus anderer Städte nach derselben Regel.

## Zoom (Bauplan B, Ramon 31.10.2026)

Nah ein strenges Diorama, fern eine Karte mit Zeichen. Bericht mit Herleitung:
Artifact «Grössen über die Zoomstufen».

| Was | Regel |
|---|---|
| Relief nah (Viertel-, 0,5- und 1-km-Kacheln) | fest 7,5-fach je erstem Stufenschritt des Bakes, bei jeder Sichtbreite (`NEAR_EXAGGERATION`) |
| Relief fern (ab 2-km-Kacheln) | eine Stufe fest 0,6 km auf jeder Kachelgrösse (`FAR_LEVEL_KM`), Alpen ≈ 6 km wie nah; vorher bis 320-fach |
| Stadtfläche | auf jeder Zoomstufe die echte Fläche aus dem Stadtplan (`area_ha`, mindestens 4 ha), nicht mehr eine Scheibe nach Einwohnern |
| Häuser | wachsen nie; bis zu den 1-km-Kacheln in Diorama-Grösse, ab den 2-km-Kacheln nur noch Dachfarbe der Stadtfläche |
| Stadtmarken | ab den 2-km-Kacheln (≈ 90 km) eine kleine Voxel-Marke je Stadt aus ihren Hausmodellen: 1–5 Häuser nach Einwohnern, Tempel ab 30'000, Tor mit Türmen bei Mauern; feste Bildschirmgrösse (ein Hauslos 9 px), Name ab 20'000 Einwohnern; weiter draussen nur noch grössere Städte (`app/scripts/city_markers.gd`). Ein Zeichen, kein Massstab |
| Feldweg | Felder sind wie Häuser im Diorama-Mass gezeichnet: die Sim legt sie im Median 8,4 Welt-km vom Hof (≈ 350 m im Diorama-Mass); nähere Felder liessen die Leute verhungern (Sonde 31.10.). Die Bauern gehen darum zum nächsten eigenen oder gepachteten Feld des Hofs (`people_fields`, `Grain::near_field`) im Diorama-Tempo, 4,5 km/h ÷ 0,0238 (`dot_field_way`), also einige Minuten. Wege zwischen Orten (Markt, Arbeit, Reisen) bleiben in echter Zeit |

