# Bewohner als Punkte (Kit 2, Personen-Prototyp)

Status: **implementiert** (Linux, Software-GPU geprüft); Messung auf dem Mac offen.

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
- **Ein Draw Call:** ein MultiMesh mit einem Dreieck pro Slot, dessen Transformationen
  nie geschrieben werden; der Shader liest den Datensatz über `INSTANCE_ID`,
  verwirft Punkte außerhalb des Bildes vor den Terrain-Abfragen und zeichnet einen
  runden Punkt fester Pixelgröße.

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

## Bedienung

`P` Punkte an/aus, `[` / `]` Tage pro Sekunde halbieren/verdoppeln.
Kommandozeile: `--people-days=n` (Standard 10), `--people-bench=pfad.json`.
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
  (RenderingDevice, Texture2DRD) in die Textur schreiben. Lohnt erst, wenn die
  Mac-Messung den Seiten-Upload sichtbar zeigt.
- Reisende per Schiff liegen heute auf See (gewollt); Zellen ganz ohne
  Land-Tile in 12 Versuchen ebenfalls.
