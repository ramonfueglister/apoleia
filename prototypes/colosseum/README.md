# Kolosseum-Prototyp: Urbek-Formen, Caesar-III-Farben, viele Instanzen

Status: `implementiert` (Prototyp, eigenständiges Godot-4.7.2-Projekt, nicht in `app/` eingebunden).

## Was es ist

- `colosseum_mesh.gd` baut das Kolosseum als Voxel-Modell im Stil von Urbek:
  Eine Achse der Arkade ist als Körper in Metern beschrieben, wird mit
  12,5-cm-Blöcken voxelisiert und auf jedes der 28 gleich langen
  Ellipsenstücke gebogen (vier Varianten: Fenster, Eingänge, Menge). So
  bleiben Bögen, Säulen und Sitzreihen sauber statt treppig wie in einem
  weltachsigen Gitter. Gemeshed werden nur sichtbare Flächen; gleichfarbige
  Flächen verschmelzen, wo die Ecken-Schattierung (Voxel-AO in den
  Vertex-Farben) es zulässt; Unterseiten entfallen. Ein Material, keine
  Texturen. Details: Rundbögen mit Rahmen und Schlussstein, Halbsäulen mit
  Basis und Kapitell, getreppte Gesimse, Attika mit Fenstern, Galerie hinter
  den Bögen, Sitzreihen mit sitzenden Figuren, Eingänge, Podium mit rotem
  Band, Sandarena, Wimpel an dünnen Masten.
  - LOD 12,5 cm: ca. 64 000 Dreiecke (bis 50 m Kameradistanz)
  - LOD 25 cm: ca. 21 500 (50–140 m)
  - LOD 50 cm: ca. 6 000 (140–320 m); dünne Figuren werden zu Mengenblöcken
  - Ring: 168 Dreiecke (ab 320 m)
  - Die Voxel-LODs werden beim ersten Start gebaut (ca. 1 s) und in
    `user://` zwischengespeichert.
- `main.gd` zeigt es (`--scene=hero` mit Platz und Zypressen,
  `--scene=lods`, `--elev` für die Seitenansicht) oder misst
  (`--scene=bench`) wie unten beschrieben.
- Licht nach Urbek: kühles Himmelslicht in den Schatten, SSAO, weiche
  Sonnenschatten, linearer Tonemapper mit leicht erhöhter Sättigung.
- Varianten der Messung:
  - `naive`: ein `MeshInstance3D` je Kolosseum, volles Detail
  - `nodes_lod`: drei `MeshInstance3D` je Kolosseum mit Visibility Ranges
  - `multimesh`: ein `MultiMesh` mit allen Kolosseen, volles Detail
  - `chunked`: `MultiMesh`-Chunks zu 4×4 Kolosseen, je Chunk drei LODs
    über Visibility Ranges, LOD2 ohne Schatten

```sh
godot --path prototypes/colosseum --windowed --resolution 1280x720 -- \
  --scene=bench --mode=chunked --count=10000 --view=far --out=bench.jsonl
```

## Stilvorlage (beobachtet, nicht kopiert)

Verglichen mit Steam-Store-Screenshots von Urbek City Builder (App 1411740)
und Caesar 3 (App 517790), lokal angesehen, nicht im Repo.

- Urbek: kompakte Volumen, flache Facetten, kantige Gesimse, weiches Licht,
  eingebackene Bodenverdunkelung in den Vertex-Farben.
- Caesar III: Palette aus Ausschnitten von Kolosseum, Wiese und Dächern
  gemessen: graubeiges Travertin, warme dunkle Bögen, Terrakotta-Kranz,
  Sandarena, roter Fahnenkranz. Die Menge auf den Rängen ist ein geordnetes
  Farbmuster je Segment und Rang, mit vier dunklen Eingängen (Vomitorien),
  ohne zusätzliche Dreiecke.
- Gauntlet-Loop (2026-10-28): sechs Runden mit je einem frischen, unabhängigen
  Kritiker gegen die Screenshots. Noten (Form/Farbe/Handwerk/Lesbarkeit/
  Gesamt) von 5/5/4/5/5 auf 6/6/5/6/6; das Ziel ≥ 8 ist nicht erreicht. Die
  Kritiker widersprechen sich von Runde zu Runde (z. B. Stein heller vs.
  dunkler, Gesimse tiefer vs. flacher, Menge gesprenkelt vs. geordnet).

## Messung Voxel-Modell (M3 Pro, Metal, 1280×720, Schatten an)

Auf Akku gemessen, Bildzeit deshalb bei 120 Hz (8,3 ms) gedeckelt;
Primitive inklusive Schattenpässe.

| Fall | Primitive | Bildzeit | Render-CPU | Speicher |
|---|---:|---:|---:|---:|
| 10 000 naiv (volles Detail), ganze Karte | 578 Mio. | 792 ms | 0,6 ms | 95 MB |
| 10 000 LOD je Node, ganze Karte | 1,5 Mio. | ≤ 8,3 ms | 2,4 ms | 246 MB |
| 10 000 Chunks + LOD, Stadtzoom | 5,3 Mio. | ≤ 8,3 ms | 0,1 ms | 74 MB |
| 10 000 Chunks + LOD, ganze Karte | 1,6 Mio. | ≤ 8,3 ms | 0,7 ms | 75 MB |
| 50 000 Chunks + LOD, ganze Karte | 4,0 Mio. | 11,5 ms | 1,2 ms | 191 MB |

Ohne Detailstufen ist das Voxel-Modell bei tausenden Instanzen unbrauchbar
(792 ms); mit Chunks und LOD bleibt es im 120-Hz-Rahmen bis 10 000 und bei
50 000 knapp darüber.

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
