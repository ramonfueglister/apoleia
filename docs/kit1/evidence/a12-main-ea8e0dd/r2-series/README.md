# A12 Serie r2 (27.10.2026)

Nachmessung zu den Lücken aus [a12-independent-review](../../a12-independent-review/). Nur Messung, keine Bewertung und keine Optimierung.

- **Stand:** gsv7uc e707fb31, also main ea8e0dd plus A12-Telemetrie.
- **Hardware:** Apple M3 Pro, 18 GB, macOS 26.5.
- **Fenster/Viewport:** 640x360.
- **Pfad:** Tour `runs/kit1-landscape-v5-2026-10-25/fixture.json`.

## Läufe

Reihenfolge abwechselnd F+, M, F+, M, F+, M jeweils mit `--disable-vsync`, danach F+ und M mit VSync. Vor und nach jedem Lauf wurde `pmset -g therm` aufgezeichnet; es gab in keinem Lauf eine Thermal- oder Performance-Warnung.

Befehl je Lauf:

```sh
godot --windowed --resolution 640x360 --position 0,0 --rendering-method <m> [--disable-vsync] --path app -- \
  --tour --fixture … --telemetry-dir …
```

## Dateien

- `a12-series.json` enthält die Aggregate pro Lauf:
  - Tour-Framezeiten p50/p95/p99/max, Spitzen, Frames über 8.3/16.7/33.3/50/100/250 ms
  - `render_timing` (viewport CPU/GPU, frame setup)
  - RSS, Static-, GPU-, Texture- und Buffer-Speicher
  - Clipmap: Limits, Kachel-Request→Load→Upload, Upload-Bytes und -ms pro Frame, Frames mit „sichtbar zu grob“ (missing oder refining > 0)
- `runs/*.runtime-trim.json.gz`: gekürzte runtime.json, aus denen sich die Aggregate nachrechnen lassen. Enthalten sind `frame_intervals_ms`, `clipmap_frames`, `clipmap_tile_timeline`, `tour_clock`, `pipeline_events` und reduzierte Samples. Die SHA der vollen Datei steht in `a12-series.json`.

## Befunde zur Messmethode

- **VSync:** `--disable-vsync` ändert die Verteilung praktisch nicht (p50 F+ 8.7–9.4 ms gegen 8.5 ms mit VSync; Mobile 8.4 gegen 8.4 ms; Anteil der Frames unter 8 ms 2–12 %). Ob der Schalter unter Metal die Präsentation wirklich entkoppelt, ist damit nicht nachgewiesen.
- **GPU-Zeit:** `viewport_get_measured_render_time_gpu` liefert in dieser Runtime unter Metal keinen Wert (null in allen Samples); die GPU-Framezeit bleibt nicht messbar. `viewport_cpu_ms` misst nur die Viewport-CPU-Zeit (p95 ~0.2–0.3 ms), nicht die gesamte Frame-CPU-Zeit.
- **Speicher-Unterlauf:** `gpu_texture_memory_bytes` meldete bei Mobile einen umgelaufenen Zählerwert (~2^64). Seit e707fb31 wird das als null ausgegeben; Mobile hatte je Lauf genau 1 solches Sample.
