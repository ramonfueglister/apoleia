# Terrain-Schritt 2: Kachelwerte vorberechnen

Stand: 31.10.2026. Ausgangscode: `677b8bbae0`. Status: lokal implementiert und
auf dem M3 Pro unter Metal validiert; noch nicht auf `main`.

## Änderung

`tile_flags_prep.gdshader` berechnet die Kachelwerte für Küsten, Landschaft,
Stadtränder und Flussanschlüsse in einem vorgeschalteten Renderdurchgang.
Der Terrain-Vertexshader liest sie anschliessend aus einer Textur. Bisher
wurde dieselbe Regel für jeden der 26 Eckpunkte einer Kachel erneut ausgewertet.
Nun geschieht das zweimal pro Kachel (zwei Texel), danach folgen zwei
Texturzugriffe je Eckpunkt. Die Regeln und die eigentliche Geometrieberechnung
bleiben gleich.

Die zwei RGBA16F-Texel speichern ausschliesslich ganze Zahlen bis 2047;
damit gehen beim Packen der Flags keine Bits durch Halbfloat-Rundung verloren.
Wand-Eckpunkte entfernen die nur für Oberseiten geltenden Landschaftsdiagonalen
und Küstenstufen. Die Roh-Ecken der Nachbarn und die Behandlung von See-Ecken
bleiben erhalten. Die neue Materialinstanz erhält dieselben Daten und
Küstenfenster wie das Terrain. Sie liest die Viertelkacheln erst nach deren
Vorbereitung. Ausserhalb des tatsächlich gezeichneten Ausschnitts werden die
Kachelabfragen übersprungen.

Der zusätzliche Render-Target ist 640 × 320 × RGBA16F (1,56 MiB pro Bildpuffer).
Er wird weiterhin jedes Bild berechnet; eine bedarfsgesteuerte Aktualisierung
ist ein gesonderter möglicher Folgeschritt.

## Messung

Apple M3 Pro, macOS 26.5, Godot 4.7.2, Metal Forward+, Fenster 1440 × 810.
Reihenfolge: Ausgangscode, Cache, Cache, Ausgangscode. Jeder Start fährt zwei
Touren mit je 2880 Bildern. Ausgewertet wird nur Durchgang 2. Die Zahlen unten
sind der Mittelwert der beiden jeweiligen Perzentile, kein zusammengelegtes
Perzentil über alle Bilder.

Die Simulation ist mit `--people-days=0` pausiert, Ereignisfenster sind aus,
die Wetterzeit steht. `--fixed-fps 60` setzt das gleiche Simulationsdelta für
die Kamera; gemessen wird die tatsächliche Bilddauer mit VSync aus. So ändern
Popups, Simulationsfortschritt und unterschiedliche Kameraglättung nicht die
Vergleichsszene. Die ersten explorativen Läufe mit laufender Simulation hatten
unterschiedliche Ereignisfenster; sie dienen nicht als Leistungsnachweis.

| Bilddauer | Ausgangscode | Cache | Verringerung |
|---|---:|---:|---:|
| p50 | 13,702 ms | 10,877 ms | 20,6 % |
| p95 | 19,666 ms | 16,712 ms | 15,0 % |
| p99 | 21,818 ms | 18,889 ms | 13,4 % |

| Zoom | p50 vorher | p50 nachher | Verringerung |
|---|---:|---:|---:|
| −1 | 14,724 ms | 14,441 ms | 1,9 % |
| 0 | 14,443 ms | 13,750 ms | 4,8 % |
| 1 | 15,580 ms | 13,852 ms | 11,1 % |
| 2 | 9,395 ms | 8,393 ms | 10,7 % |
| 3 | 9,149 ms | 8,348 ms | 8,7 % |
| 4 | 15,501 ms | 9,973 ms | 35,7 % |
| 5 | 15,934 ms | 10,904 ms | 31,6 % |
| 6 | 18,020 ms | 12,437 ms | 31,0 % |

Kein ausgewerteter Durchgang hatte Bilder über 33,4 ms. Die Nahansicht gewinnt
wenig; der deutliche Gewinn liegt bei den grösseren Kachelmengen der Fernansicht.
Der Metal-Build liefert für `viewport_get_measured_render_time_gpu` nur 0;
deshalb sind dies Bildzeiten, keine isolierten GPU-Zeiten. Der Vergleich belegt
den Renderer mit pausierter Simulation, keine pauschale Beschleunigung der
Wirtschaftssimulation oder eine garantierte Bildrate auf anderen Geräten.

## Bildprüfung

Sieben Ansichten vor/nach der Änderung: Rom 3 und 22 km, Neapel 3 und 12 km,
Gardasee 60 km, Alpen 400 km und Gesamtkarte 8000 km. Gleicher Ausgangsstand,
60 feste Frames je Ansicht, pausierte Simulation und Wetterzeit.

- Gardasee und Alpen sind vollständig pixelgleich.
- In Rom (beide Ansichten) unterscheidet sich nur der Hover des Feldbauknopfs.
- Für den gesonderten Landschaftsvergleich wurde dessen UI-Rechteck
  `(30, 600, 190, 195)` ausgeschlossen; die unmaskierten Werte sind ebenfalls
  in der JSON-Datei enthalten.
- Ausserhalb dieses UI-Rechtecks sind vier Ansichten pixelgleich. Bei Neapel
  und der Gesamtkarte unterscheiden sich höchstens 0,067 % aller Bildpixel;
  der grösste RGB-Kanalunterschied beträgt 5 von 255. Das ist keine Behauptung
  vollständiger Pixelidentität aller Ansichten.
- Keine Script- oder Shaderfehler in den Vergleichsläufen. Die bestehende
  Meldung zu zwei beim Beenden verbliebenen ObjectDB-Instanzen tritt bereits
  beim Ausgangscode auf und wurde hier nicht geändert.

[Messdaten und Bild-Hashes](terrain-cache-2026-10-31.json). Die lokalen Rohdaten,
Logs und PNGs liegen unter `build/terrain-perf/` der Mess-Arbeitskopie und sind
nicht in Git. Die temporären Diagnose-Schalter wurden aus dem Produktcode
wieder entfernt.

## Wiederholen

Auf dem jeweiligen Stand mit der passenden, über `sim/godot/build.sh` gebauten
GDExtension und importierten Godot-Ressourcen:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path app \
  --audio-driver Dummy --fixed-fps 60 --disable-vsync -- \
  --tour=/tmp/apoleia-terrain-tour.json --tour-passes=2 \
  --weather-timescale=0 --people-days=0 --no-event-windows
```

Bildfolge:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path app \
  --audio-driver Dummy --fixed-fps 60 --disable-vsync -- \
  --views='12.49,41.89,3;14.27,40.83,12;10.65,45.63,60;7.0,46.1,400;17.5,39.5,8000;12.49,41.89,22;14.27,40.83,3' \
  --snapshot=/tmp/apoleia-terrain-shots --snapshot-frames=60 \
  --weather-timescale=0 --people-days=0 --no-event-windows
```

Die restlichen Punkte der historischen Performance-Übergabe (Wegsuche,
doppelter Simulationsstart beim Laden, unbegrenzte Eventliste, weitere
Prep-Durchgänge) bleiben eigene Aufgaben.
