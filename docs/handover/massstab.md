# Übergabe: Massstab und Wahrzeichen (Stand 31.10.2026, 18:40)

Für die nächste Claude-Sitzung, die am Thema «Grössenverhältnisse» weiterarbeitet.
claude.ai-Links sind privat auf Ramons erstem Account; ihr Inhalt steht in Abschnitt 7 und 8.
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

## 7. Kernpunkte des Grössen-Reports (31.10.2026)

Die claude.ai-Links in dieser Datei sind privat auf Ramons erstem Account. Was
daraus zählt, steht hier. Bilder des Reports liegen unter `/mnt/project-files/groessen/`
(`rom-3km.jpg`, `rom-8km.jpg`, `kolosseum-1km.jpg`, `felder-3km.jpg`,
`land-34km.jpg`, `europa-1500km.jpg`), die Seite selbst als `index.html` daneben.

**Befund (Stand main a5705d1, vor den Umbauten):** Im Spiel galten etwa zehn
verschiedene Vergrösserungsfaktoren. Die Grundregel (Geografie 1 : 23,8, Mensch
und Haus echt gross; Anzahl und Fläche 1 : 566,5, S50–S52) war für Flächen und
Anzahlen sauber, aber für Höhen, Wege und Zeit, Wahrzeichen und alles ab etwa
35 km Sichtbreite nie zu Ende gedacht. Kern: zwei Längenmassstäbe (Geografie und
Mensch), aber nur ein Tempo und eine Höhe.

| Ding | Diorama-Mass | in der Welt (echte km) |
|---|---|---|
| Mensch (Figur) | 1,7 m | 40 m |
| Hauslos | 10 m | 238 m (Viertelkachel 250 m) |
| Baum | 8 m | 190 m |
| Rom in der Mauer | ≈ 190 × 190 m, 203 Parzellen | ≈ 13 km² (echt 13,7 km²) |
| Feldlos der Sim | 441 m² | 0,5 × 0,5 km |
| Gehtempo | 0,19 km/h | 4,5 km/h |

Was schon stimmte: Fläche pro Mensch (ein Hof mit 3 ha belegt gut 300 Hauslose,
dasselbe Verhältnis wie damals); Rom nah (203 Parzellen, 1626 Menschen, etwa
270 Haushalte); Reisen zwischen Orten (Märkte 25 km auseinander, 4,5 km/h).

Die sechs Widersprüche und was daraus wurde:
1. Häuser so hoch wie die Hügel (Relief nah nur 2,4- bis 6-fach) → **#105**, Relief
   nah fest 7,5-fach (`NEAR_EXAGGERATION`).
2. Ein Tempo für zwei Längen (Weg zum Feld im Client 150–220 m, die Sim legt Felder
   bis 12,5 km weit) → **#114**, Figuren gehen zum echten nächsten Feld des Hofs im
   Diorama-Tempo 4,5 km/h ÷ 0,0238. Nähere Felder liessen in der Sim Leute verhungern,
   darum «Felder bleiben, Weg schneller».
3. Drei Regeln für Wahrzeichen (S51 Nutzer, CITY_PLANS bis 2,5-fach, Kit-Modelle in
   Hausgrösse, Brücken 6-fach) → **S136**, siehe oben.
4. Städte springen beim Herauszoomen (Bake-Scheibe für Rom 121 km² statt 13 km²,
   Häuser fern 2,5- und 5-fach) → **#110**, echte Planfläche auf jeder Stufe,
   Voxel-Stadtmarken ab etwa 90 km (`city_markers.gd`).
5. Berge fern bis 320-fach überhöht → **#112**, fern eine feste Stufe 0,6 km
   (`FAR_LEVEL_KM`).
6. Dokument und Code widersprachen sich (Höhe, Wetter, Strassen, Tempo) →
   SCALE.md hat jetzt eine Massstabstabelle mit Spalte «stimmt / weicht ab».

**Grundsatzentscheid 31.10. 08:24: Bauplan B** = strenges Diorama nah, Karte mit
Zeichen fern, wie EU5 und Victoria 3 (Alternativen waren A «ein Massstab überall»
wie Urbek, C «SimCity-Wachstum mit Gesetz»). Einzelfragen: D1a Höhe nah fest 7,5
(gebaut), D3a Weg zum Feld aus der Sim (gebaut), D4 SCALE.md nachführen (gebaut),
D2 Wahrzeichen → nach mehreren Runden S136.

Vergleich mit anderen Spielen (aus dem Report): EU5 zeichnet Städte als 3D-Marken,
Spieler kritisierten zu grosse Städte, danach kleiner gezeichnet; Victoria 3 hat
«Hubs», die in Schwellen wachsen, fern eine eigene Papierkarte, bewusst keine
Einzelmenschen, Grösse als Zeichen der Wichtigkeit; Urbek und Islanders bleiben
bei einem Massstab, weil sie nie auf Kontinentgrösse zoomen; SimCity 2000 lässt
Kacheln samt Häusern wachsen (Darstellungsregel, kein Massstab).

Quellen des Reports (APA 7):
- Bederson, B. B., & Hollan, J. D. (1994). Pad++: A zooming graphical interface for exploring alternate interface physics. In *Proceedings of the 7th Annual ACM Symposium on User Interface Software and Technology* (pp. 17–26). ACM. https://doi.org/10.1145/192426.192435
- Luebke, D., Reddy, M., Cohen, J. D., Varshney, A., Watson, B., & Huebner, R. (2003). *Level of detail for 3D graphics*. Morgan Kaufmann.
- Paradox Interactive. (2022). *Victoria 3 dev diary #49: Graphics overview*. paradoxinteractive.com
- Paradox Interactive. (2022). *Victoria 3 dev diary #50: Living map*. forum.paradoxplaza.com
- Perlin, K., & Fox, D. (1993). Pad: An alternative approach to the computer interface. In *Proceedings of SIGGRAPH '93* (pp. 57–64). ACM. https://doi.org/10.1145/166117.166125
- r/EU5. (2025). *Cities evolving over time on the map* [Discussion]. Reddit.
- Töpfer, F., & Pillewizer, W. (1966). The principles of selection. *The Cartographic Journal, 3*(1), 10–16. https://doi.org/10.1179/caj.1966.3.1.10

## 8. Literatur und Verfahren zur Diorama-Regel

Grundlage für S136 (Doc «Rom als Diorama: Literatur und Verfahren für
Grössenverhältnisse», 31.10.2026). Die Kartografie nennt es **Generalisierung**,
der Modellbau **selektive Verdichtung**. Alle Verfahren machen dasselbe in vier
Schritten:
1. Viel weniger gewöhnliche Bauten zeigen (Rom: 250 statt rund 46 000 Häuser).
2. Menschen, Türen, Fenster und Sitze in echter Grösse lassen.
3. Wichtige Bauten weniger stark verkleinern als gewöhnliche, damit man sie erkennt.
4. Die Reihenfolge der Grössen erhalten.

Eine feste Formel für Schritt 3 gibt die Literatur **nicht** vor; die Kubikwurzel
ist eine Gestaltungswahl für Apoleia.

- **Kartografische Generalisierung** (McMaster & Shea, 1992): Auswahl (nur so viele
  Häuser wie Haushalte), Typisierung (250 Häuser stehen für 46 000), Übertreibung
  (Wahrzeichen grösser als ihr Flächenanteil), Verdrängung (Häuser rücken zur Seite).
  Töpfers Wurzelgesetz N_d = N_s · √(M_s / M_d) beschreibt, wie viele Objekte bei
  einer Verkleinerung bleiben (Töpfer & Pillewizer, 1966; Jiang et al., 2013); es
  gilt für Kartenzeichen, das Prinzip «weglassen und Stellvertreter» ist anerkannt.
- **Touristenkarten und 3D-Stadtmodelle:** Grabler et al. (2008) bauen Touristenkarten
  automatisch: «Mapmakers often increase the size of important landmarks while
  decreasing the size of less relevant buildings»; ihr System bestraft starke
  Verkleinerung wichtiger Bauten. Glander & Döllner (2008) fassen gewöhnliche Häuser
  zu Blöcken, Wahrzeichen bleiben «as they represent essential orientation marks»,
  die wichtigsten vergrössert, Nachbarblöcke beschnitten; Glander (2013) skaliert sie
  nach Kameraabstand.
- **Panoramakarten nach Berann:** übertriebene Berge, breitere Täler (Patterson, 2000),
  aber die Reihenfolge der Höhen bleibt (Brown & Samavati, 2017). Für Apoleia:
  Kolosseum, Thermen, Theater, Circus, dann Insula und Haus.
- **Modellbahn:** selektive Verdichtung (Verducci, 2010): Tiefe und Länge kürzen
  «without losing the flavor of the building», Wand zwischen Öffnungen weglassen,
  obere Geschosse niedriger, aber «make the ground-floor doors and windows to the
  correct scale». Für Apoleia: Grundfläche stark verdichten, Höhe weniger, Türen,
  Bögen, Sitze und Menschen echt.
- **Disneyland Main Street:** Erdgeschoss etwa 90 %, zweites 80 %, drittes weniger
  (Gennawey, 2008, «forced perspective»): Höhe und Fläche dürfen verschieden stark
  schrumpfen, solange unten alles echt gross ist.
- **Wahrnehmung:** empfundene Fläche wächst mit Exponent 0,7, Länge mit 1,0
  (Stevens, 1957): 10-mal mehr Fläche wirkt nur etwa 5-mal so gross; Höhe und
  Silhouette tragen viel vom Eindruck «riesig». Geringe Schärfentiefe lässt Städte
  wie Miniaturen wirken (Held et al., 2010; Look, nicht Grösse, eigenes Thema).
- **Gegenbeispiel:** Gismondis Plastico di Roma imperiale, einheitlich 1 : 250, füllt
  einen Saal; mit 250 Häusern für Rom nicht möglich.
- **Warum Kubik- statt Quadratwurzel:** Mit der Quadratwurzel würde der Circus
  119 × 23 m, das Kolosseum 48 × 40 m; Rom ist im Spiel nur 160–190 m breit.
  Die Circus-Breite 13,1 m nach der Regel ist zugleich das Minimum für Bahn mit Spina,
  zwei Gespanne nebeneinander und eine Sitzreihe.
- Nicht gefunden: eine wissenschaftliche Arbeit zu Massstäben in Aufbauspielen
  (EU5, Anno); dort Studiopraxis, unveröffentlicht.

Literatur (APA 7; online geöffnet am 31.10.2026, ausser wo «nicht geprüft» steht):
- Brown, S. A., & Samavati, F. (2017). Real-time panorama maps. In *Proceedings of the Symposium on Non-Photorealistic Animation and Rendering (NPAR '17)*. ACM. https://doi.org/10.1145/3092919.3092922
- Gennawey, S. (2008, November 13). *An urban designer looks at Main Street*. TouringPlans. https://touringplans.com/blog/an-urban-designer-looks-at-main-street/
- Glander, T. (2013). *Multi-scale representations of virtual 3D city models* [Doctoral dissertation, Universität Potsdam]. https://publishup.uni-potsdam.de/opus4-ubp/files/6201/glander_diss.pdf
- Glander, T., & Döllner, J. (2008). *Automated cell-based generalization of virtual 3D city models with dynamic landmark highlighting* [Workshop paper]. ICA Workshop on Generalisation and Multiple Representation. https://kartographie.geo.tu-dresden.de/downloads/ica-gen/workshop2008/29_Glander_Dollner.pdf
- Grabler, F., Agrawala, M., Sumner, R. W., & Pauly, M. (2008). Automatic generation of tourist maps. *ACM Transactions on Graphics, 27*(3), 1–11. https://doi.org/10.1145/1360612.1360699
- Held, R. T., Cooper, E. A., O'Brien, J. F., & Banks, M. S. (2010). Using blur to affect perceived distance and size. *ACM Transactions on Graphics, 29*(2), Article 19. https://doi.org/10.1145/1731047.1731057
- Jiang, B., Liu, X., & Jia, T. (2013). *Scaling of geographic space as a universal rule for map generalization* [Preprint]. arXiv. https://arxiv.org/abs/1102.1561 (Zeitschriftenangaben nicht geprüft)
- McMaster, R. B., & Shea, K. S. (1992). *Generalization in digital cartography*. Association of American Geographers. (nicht geprüft)
- Museo della Civiltà Romana. (o. J.). *Plastico di Roma imperiale: Veduta generale*. https://www.museociviltaromana.it/en/collezioni/percorsi_per_sale/plastico_di_roma_imperiale/plastico_di_roma_imperiale_veduta_generale
- Patterson, T. (2000). A view from on high: Heinrich Berann's panoramas and landscape visualization techniques for the U.S. National Park Service. *Cartographic Perspectives, 36*, 38–65. https://doi.org/10.14714/CP36.824
- Stevens, S. S. (1957). On the psychophysical law. *Psychological Review, 64*(3), 153–181. (nicht geprüft)
- Töpfer, F., & Pillewizer, W. (1966). The principles of selection. *The Cartographic Journal, 3*(1), 10–16. (nicht geprüft)
- Verducci, J. (2010, Februar). Structures: Selective compression. *Garden Railways*. https://www.trains.com/wp-content/uploads/2020/10/selective_compression.pdf

## Verona-Referenz, 31.10.2026 (Codex, nach PR #138)

Sechs lokale Referenzmodelle nach S136 umgesetzt. [Umfang, Quellen und Grenzen](../kit2/VERONA.md), [Prüfung](verona/validation.md). Nur Verona geändert; noch keine globale Umstellung. Der Wohnkern bleibt frei, öffentliche Blöcke weichen auf dem generierten Plan aus. Historische Lagebeziehungen nicht validiert; Therme und unbekannte Höhen als Annahmen markiert. Sitzplätze leer bis zur Anbindung echter Simulationsbesuche. Noch nicht von Ramon abgenommen.
