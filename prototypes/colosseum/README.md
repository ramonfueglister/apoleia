# Kolosseum-Prototyp: Urbek-Formen, Caesar-III-Farben, viele Instanzen

Status: `implementiert` (Prototyp, eigenständiges Godot-4.7.2-Projekt, nicht in `app/` eingebunden).

## Was es ist

- `colosseum_mesh.gd` baut das Kolosseum prozedural in drei Detailstufen:
  LOD0 1440, LOD1 276, LOD2 40 Dreiecke. Nur Vertex-Farben und flache
  Normalen, ein gemeinsames `StandardMaterial3D`, keine Texturen.
- `main.gd` zeigt es (`--scene=hero`, `--scene=lods`) oder misst
  (`--scene=bench`) mit vier Varianten:
  - `naive`: ein `MeshInstance3D` je Kolosseum, volles Detail
  - `nodes_lod`: drei `MeshInstance3D` je Kolosseum mit Visibility Ranges
  - `multimesh`: ein `MultiMesh` mit allen Kolosseen, volles Detail
  - `chunked`: `MultiMesh`-Chunks zu 4×4 Kolosseen, je Chunk drei LODs
    über Visibility Ranges (0–200, 200–600, 600–6000), LOD2 ohne Schatten

```sh
godot --path prototypes/colosseum --windowed --resolution 1280x720 -- \
  --scene=bench --mode=chunked --count=10000 --view=far --out=bench.jsonl
```

## Stilvorlage (beobachtet, nicht kopiert)

Verglichen mit Steam-Store-Screenshots von Urbek City Builder (App 1411740)
und Caesar 3 (App 517790), lokal angesehen, nicht im Repo.

- Urbek: kompakte, klotzige Volumen, flache Facetten, weiches Licht.
  Übernommen als Idee: flache Normalen, dicke Kranzgesims-Kante, eingebackene
  Bodenverdunkelung (AO) in den Vertex-Farben.
- Caesar III: Palette aus Ausschnitten von Kolosseum, Wiese und Dächern
  quantisiert: warmes, eher graues Travertin (`d8cbb6`/`a08a70`), tiefe
  Bogenschatten (`2e2419`), olivgrüne Wiese (`56692f`), braunes Sandfeld,
  dichter Kranz roter Wimpel. Dazu warmes, kontrastreiches Licht mit wenig
  Umgebungslicht. Die Tribünen-„Menge“ ist ein Farbrauschen je Segment, ohne
  zusätzliche Dreiecke.

## Messung (M3 Pro, Metal, 1280×720, Schatten an)

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
