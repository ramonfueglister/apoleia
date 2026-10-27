# A12 Rohmessung, main ea8e0dd (27.10.2026)

Nur Messung, keine Optimierung und keine A12-Bewertung.

- **Stand:** gsv7uc f8ce8aed, das ist main ea8e0dd plus Startup-Telemetrie.
- **Hardware:** Apple M3 Pro (11 CPU-, 14 GPU-Kerne), 18 GB RAM, macOS 26.5, eingebautes Liquid-Retina-XDR-Display.
- **Engine:** Godot 4.7.2.stable.custom_build.ed1daf0bf, Metal.
- **Auflösung:** Fenster 640x360. `viewport` in runtime.json meldet 640x360 als Renderauflösung. Grössere Fenster sind bis zur Entscheidung des Owners nicht freigegeben.
- **Pfad:** identische Tour `runs/kit1-landscape-v5-2026-10-25/fixture.json` (48 s) über den Clipmap-Streaming-Pfad.

Befehl je Lauf (mit Perf-Lock, RSS per `ps` alle 0.5 s):

```sh
godot --windowed --resolution 640x360 --position 0,0 --rendering-method <forward_plus|mobile> --path app -- \
  --tour --fixture runs/kit1-landscape-v5-2026-10-25/fixture.json --telemetry-dir <out>
```

Pro Renderer gibt es zwei Läufe hintereinander. Der jeweils erste Lauf hat einen kalten Godot- bzw. Metal-Cache für diese Variante: Wartezeit vor dem Tourstart ~26.8 s, Startframes bis 14.4 s. Der zweite Lauf ist warm: ~7.1 s Wartezeit.

In `a12-raw.json` stehen pro Lauf:
- Framezeiten über alles und nur über den Tourteil (ab `tour_clock.start_frame`)
- die acht grössten Spitzen
- die Zahl der Frames über 16.7/33.3/50/100/250 ms als Mass für Ladeunterbrechungen
- RSS sowie Engine- und GPU-Speicher
- Request-Alter und Upload-Zeiten aus `terrain_streaming` bzw. den CLIPMAP-Zeilen (Tile-IO, pending, Upload-ms)
- SHA-256 des jeweiligen runtime.json (lokal-only)

Gilt nur für diesen Mac. Daraus folgt kein Windows-, Linux- oder iPad-Nachweis.
