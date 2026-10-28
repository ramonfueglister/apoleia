# Kolosseum-Prototyp: Urbek-Formen, Caesar-III-Farben, viele Instanzen

Status: `implementiert` (Prototyp, eigenständiges Godot-4.7.2-Projekt, nicht in `app/` eingebunden).

## Was es ist

- `colosseum_mesh.gd` baut das Kolosseum als Voxel-Modell nach den Regeln von
  Urbek City Builder (abgelesen an 38 Steam-Store- und 90 Steam-Community-
  Screenshots): 0,5-m-Voxel auf festem Weltraster (ein Urbek-Stockwerk sind
  6 Voxel), 74 × 61 m, 21,5 m bis zum Rand, also rund 7 Urbek-Häuser lang.
  Die Rundung ist sichtbar getreppt: jede Achse ist ein gerader Lauf von
  6 Voxeln (Pfeiler 2, Bogen 4); wo das Oval flacher als 45° läuft, schauen
  die Läufe nach Süden/Norden, sonst nach Osten/Westen, so zeigen auch
  gedrehte Instanzen Bögen. Fassade: drei Arkaden mit eingetieften
  Rundbögen, Archivolte, Halbsäulen mit Kapitell, Gesimse mit Schattenlinie,
  geschlossene Attika mit Fenstern und Bronzeschilden, Fahnenmasten auf jeder
  zweiten Achse. Innen: Säulengang am oberen Umgang, Sitzstufen mit
  Reihenstreifen, zwei Umgangsmauern mit Eingängen, Zuschauer in kurzen
  Gruppen (10 %), längliche Arena 37 × 24 m mit rotem Podium.
- Meshing: nur sichtbare Flächen, gleichfarbige Flächen verschmolzen, wo die
  Voxel-Eckverschattung es erlaubt, keine Unterseiten. Ein Shader-Material:
  Vertex-Farben plus leichtes Farbrauschen pro Voxel, keine Texturen.
- Detailstufen (im Cache unter `user://`, Erstaufbau ca. 5 s):

  | Stufe | Voxel | Dreiecke | sichtbar bis Bildbreite |
  |---|---:|---:|---:|
  | LOD0 | 0,5 m | 70 000 | ca. 130 m |
  | LOD1 | 1 m, Fassade nach Bogenregeln | 25 000 | 350 m |
  | LOD2 | 2 m, glattes Oval | 4 000 | 800 m |
  | LOD3 | 4 m, glattes Oval | 1 200 | 1,75 km |
  | LOD4 | Trommel | 192 | darüber |

- `main.gd`: Testszenen mit der Spielkamera (Norden oben, 30° Neigung, FOV 10°)
  und Umgebung in Urbek-Proportionen (Häuser mit 2 bis 4 Stockwerken à 3 m,
  Bäume 5 bis 8 m, Menschen 1,8 m). `--scene=hero|lods|bench`, `--width=m`.

## Stilvorlage und Gauntlet-Loop

Referenzen: Steam-Screenshots von Urbek City Builder (App 1411740 und DLCs)
und Caesar 3 (App 517790), lokal angesehen, nicht im Repo.

Gauntlet-Loop am 2026-10-28 mit einem festen Kritiker und fester Rubrik
(Voxel-Sprache, Form, Proportion, Farbe/Licht, Lesbarkeit):

| Runde | Voxel | Form | Proportion | Farbe | Lesbarkeit |
|---|---:|---:|---:|---:|---:|
| 1 | 5 | 4 | 5 | 5 | 5 |
| 2 | 7 | 7 | 6 | 7 | 6 |
| 3 | 7 | 7 | 8 | 7 | 7 |
| 4 | 8 | 8 | 8 | 8 | 7 |
| 5 | 8 | 8 | 8 | 8 | 7 |
| 6 | 8 | 8 | 8 | 8 | 8 |

Offen (Kritiker, Politur): Rücksprünge der Treppung, die quer zur Kamera
liegen, könnten schräg gesehene Bögen zeigen statt heller Pfeilerfläche.

## Messung (M3 Pro, Metal, 1280×720, Schatten über die ganze Sicht, Netzteil)

Parallel lief eine zweite apoleia-Godot-Instanz einer anderen Sitzung; das
Display deckelt bei 120 Hz (8,3 ms), Werte darunter heißen nur „unter
8,3 ms“. Primitive ohne Schattenpass.

| Fall | Primitive | Bildzeit | Render-CPU | Draw Calls | Speicher |
|---|---:|---:|---:|---:|---:|
| 10 000, Stadtzoom, Chunks + LOD | 4,8 Mio. | ≤ 8,3 ms | 0,2 ms | 15 | 82 MB |
| 10 000, ganze Karte, Chunks + LOD | 1,9 Mio. | ≤ 8,3 ms | 0,7 ms | 678 | 83 MB |
| 10 000, ganze Karte, LOD je Node | 1,9 Mio. | ≤ 8,3 ms | 2,2 ms | 3 | 299 MB |
| 50 000, ganze Karte, Chunks + LOD | 9,6 Mio. | 22 ms | 2,4 ms | 3 138 | 225 MB |
| 1 000, ganze Karte, volles Detail | 140 Mio. | – | – | 6 | 51 MB |

Ohne Detailstufen ist das Voxel-Modell nicht tragbar (70 000 Dreiecke je
Bau). 50 000 auf einmal im Bild bräuchten noch eine Stufe über der Trommel
(z. B. ein zusammengefasstes Mesh je Chunk).

## Frühere Messungen (Low-Poly-Version, gleiches Gerüst)

Nach dem Gauntlet-Loop (LOD0 1940 / LOD1 504 / LOD2 90, LOD-Grenzen
200/600, auf Akku, Bildzeit deshalb bei 8,3 ms gedeckelt), ganze Karte:

| Fall | Primitive | Render-CPU | Speicher | Aufbau |
|---|---:|---:|---:|---:|
| 10 000 naiv | 17,5 Mio. | 0,55 ms (Bild 30 ms) | 95 MB | 31 ms |
| 10 000 Chunks + LOD | 0,83 Mio. | 0,67 ms | 68 MB | 26 ms |
| 50 000 LOD je Node | 2,1 Mio. | 6,1 ms | 804 MB | 330 ms |
| 50 000 Chunks + LOD | 2,15 Mio. | 1,0 ms | 156 MB | 90 ms |

Erste Messung mit dem einfacheren Modell (1412/276/40):

Zählwerte aus `RenderingServer.get_rendering_info` (Primitive inklusive
Schattenpässe). Gemessen mit LOD0 = 1412 Dreiecken (vor dem
Farbdurchgang mit dichteren Wimpeln). `Bildzeit` = Median über 120 Bilder ohne VSync, am Netzteil,
mit den damaligen LOD-Grenzen 140/420. Der Code steht jetzt auf 200/600
(weniger sichtbares Umspringen); ein zweiter Lauf damit lief auf Akku, blieb
bei 120 Hz (8,3 ms) gedeckelt und zeigte etwa 60 % mehr Primitive in der
Nahsicht, sonst gleiche Verhältnisse.

| Fall (ganze Karte im Bild) | Primitive | Bildzeit | Render-CPU | Nodes | Speicher | Aufbau |
|---|---:|---:|---:|---:|---:|---:|
| 10 000 naiv | 12,8 Mio. | 21,3 ms | 0,45 ms | 10 006 | 95 MB | 25 ms |
| 10 000 ein MultiMesh | 14,1 Mio. | 24,3 ms | 0,03 ms | 7 | 48 MB | 8 ms |
| 10 000 LOD je Node | 0,36 Mio. | 2,1 ms | 1,12 ms | 30 006 | 196 MB | 62 ms |
| 10 000 Chunks + LOD | 0,37 Mio. | 2,5 ms | 0,35 ms | 2 034 | 68 MB | 24 ms |
| 50 000 LOD je Node | 0,94 Mio. | 5,1 ms | 4,91 ms | 150 006 | 804 MB | 308 ms |
| 50 000 Chunks + LOD | 0,96 Mio. | 4,3 ms | 0,65 ms | 9 414 | 156 MB | 84 ms |

Befunde:

- Godot 4.7 Forward+ instanziert gleiche Mesh/Material-Paare schon selbst:
  auch die naive Variante braucht nur 3–23 Draw Calls. Draw Calls sind hier
  nicht der Engpass, die Dreiecksmenge ist es.
- Ohne LOD kostet die ganze Karte bei 10 000 Kolosseen 21–24 ms, mit drei
  LODs 2–2,5 ms.
- Ab zehntausenden Gebäuden gewinnen die Chunks gegenüber LOD-je-Node bei
  Speicher (5×), Render-CPU (7,5×) und Aufbauzeit (308 → 84 ms).
- Offen: bei weiter Sicht 1501 Draw Calls durch viele kleine LOD2-Chunks;
  größere Chunks nur für LOD2 würden das senken.
