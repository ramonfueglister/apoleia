# Kit 2 — Stadtpläne

**Stand:** 29.10.2026 · **Status:** `implementiert` (Daten, Werkzeug, Lader), `offen` (Darstellung im Spiel, Massstabsentscheid).
Plandokument mit Herleitung: Claude Doc „Echte antike Städte: Plan“ (https://claude.ai/artifact/UF6d4LMncaFN6ntKhLrSqq).

## Was es ist

Jede der 860 Städte der Simulation (`sim/inputs/cities.csv`) hat einen Stadtplan auf dem
Parzellenraster der Kachelgrafik: 0,25 km echte Länge, ein Hauslos (10 Diorama-m) je Parzelle,
ausgerichtet an `world_min` von `tools/build_tile_terrain.py`. Jede Parzelle trägt eine Art (Haus,
Insula, Domus, öffentlicher Bau, Platz, Garten, Strasse, Mauer, Tor, Brücke, Gräber, Land, Wasser),
bei Strassen den Rang, den Belag und die Anschlüsse nach N/O/S/W, bei Häusern die Stockwerke, bei
öffentlichen Bauten das Modell und die Seite der Front.

- **Rekonstruiert** (`data/cities/plans/<id>.json`), Lage aus modernen Entsprechungen geschätzt,
  zu prüfen an den in jeder Datei genannten Quellen:
  - Rom, Stand 301 (Aurelianische Mauer, 15 Tore, Tiber mit Insel und 7 Brücken, 38 Strassen,
    34 Bauten, 10 Quartiere), ±50 m.
  - Ostia (sullanische Mauer, Decumanus und Cardo, Forum, Capitolium, Theater, Thermen, Horrea), ±75 m.
  - Mailand, Residenz Maximians (maximianische Mauer, sechs Tore, Palast, Circus, Herkulesthermen,
    Säulenstrasse vor der Porta Romana), ±75 m.
  - Trier, Residenz des Constantius (Mauer, Porta Nigra, Römerbrücke, Kaiserthermen und Palastaula
    im Bau, Barbarathermen, Amphitheater, Circus), ±75 m.
- **Generiert** (`tools/city_generate.py`): die übrigen 856 Städte aus Hansons Datenbank
  (`data/cities/facts.json`, 853 von 860 zugeordnet; `tools/city_facts.py`).
- **Gebacken** (`tools/city_plans.py --bake`): `artifacts/render-data/city-plans-r1/city-plans-x1.{png,json}`.
- **Lader** (`app/scripts/city_plans.gd`): baut `city_page_tex` und `city_atlas_tex` für die Shader
  und beantwortet Abfragen je Parzelle (Klick, Simulation).

Aufteilung: dieser Teil liefert Pläne und Format; Aussehen (Materialien, Strassenstücke, Modelle,
Shader) liegt beim Grafik-Thread; gebaute Strassen beim Bau-Thread mit denselben Belägen.

## Massstab

Gebacken ist Massstab 1 (Diorama-Massstab, [SCALE.md](SCALE.md)). Rom hat dann 203 Parzellen
innerhalb der Mauer. Grössere Massstäbe (`--scale 2`) sind möglich, passen aber nicht zum Gelände:
Tiber, Küsten und Hügel bleiben am echten Ort, die Stadt wächst um ihre Mitte, und bei 2× läuft der
Tiber des Geländes durch das Forum. Entscheid bei Ramon (Karte vom 29.10.2026, Empfehlung 1× mit
Wahrzeichen, die grösser gezeichnet werden).

**Wahrzeichen** (Amphitheater, Circus, Thermen, Paläste, Theater, Stadien, Tempel, Fora ab 100 m)
stehen am echten Ort, werden aber bis 2,5-fach vergrössert, höchstens auf 500 m (zwei Parzellen).
Eigene Designentscheidung, damit sie lesbar bleiben; offen ausgewiesen.

## Strassen

| Belag | G-Bits | Wo (Regel für generierte Städte) |
|---|---|---|
| Erde (*via terrena*) | 0 | Gassen kleiner Städte, Vorstädte |
| Kies (*glarea strata*) | 1 | Fernstrassen ausserhalb Mittelitaliens, Haupt- und Quartierstrassen kleiner Städte im Westen und Norden |
| Kalksteinplatten | 2 | Hauptstrassen im Osten, in Afrika und in grossen Städten des Westens |
| Basalt (*silice strata*) | 3 | Latium und Kampanien (40–43° N, 11–16,5° O), Rom überall |

Rang: Hauptstrasse (*via*, zu den Toren, Wagen), Quartierstrasse (*vicus*), Gasse (*angiportus*).
Benannte Quartierstrassen erscheinen ab Massstab 2, Gassen ab 3; darunter fallen sie weg, weil eine
Parzelle mehr als einen echten Block darstellt (Details entfallen maßstabsabhängig, AGENTS.md).

Zwei eigene Regeln (Hypothesen, nicht aus der Literatur):

1. **Jedes Haus liegt an einer Strasse**, wie in Urbek und wie römische Häuser sich zur Strasse
   öffneten. Fehlt eine, werden Gassen geschnitten: Reihen zu zwei Häusern zwischen Ost-West-Gassen,
   Nord-Süd-Gassen alle sieben Parzellen; gewählt wird die Lage des Gassenrasters mit den wenigsten
   Schnitten.
2. **Das Netz hängt zusammen**: Getrennte Stücke werden mit der billigsten Gasse verbunden (durch
   Häuser billig, durch Gärten teurer, über Land teuer, nie durch Wasser, Mauern oder Bauten), damit
   die Fussgänger jede Strasse erreichen.

Benachbarte Strassenparzellen verbinden sich wie Strassenkacheln in Urbek.

## Regeln für generierte Städte

| Merkmal | Quelle | Regel |
|---|---|---|
| Fläche | Hanson (2016), sonst aus der Einwohnerzahl nach Hanson & Ortman (2017), mindestens 4 ha | Kreis oder (bei Raster) fast quadratische Form um den Ort |
| Rasterplan | „Urban grid“ bei 427 der 860 Städte | Cardo und Decumanus als Hauptstrassen über das Zentrum zu vier Toren, Quartierstrassen alle 2 actus (71 m; Lehrbuchwert, nicht geprüft). Achsen auf das Parzellenraster gelegt (Vereinfachung: echte Raster haben eigene Ausrichtungen) |
| ohne Raster | – | drei bis vier leicht gebogene Hauptstrassen von den Toren zur Mitte |
| Mauer | „Walls“ in den Bauten oder in der Flächenangabe | Mauer auf den Parzellen rund um die Stadt, Tore wo Hauptstrassen durchgehen |
| Platz | Forum oder Agora; jede Stadt hat einen | in der Mitte, Seitenlänge 0,12 × √(Parzellen der Stadt) |
| Bauten | Bauten-Liste (ohne „?“) | Tempel, Basilika, Curia, Markt um den Platz; Thermen auf 0,4 des Radius; Theater auf 0,6; Amphitheater, Circus, Stadion vor der Mauer oder am Rand; Hafen am nächsten Wasser. Je Art eine, mehr erst ab 60–400 ha (Ostia hat 20 Thermen in der Datenbank). Höchstens 30 % der Parzellen öffentlich |
| Gräber | – | an den Hauptstrassen vor den Toren 1,5 km weit, die erste Hälfte Vorstadt mit Häusern |
| Wasser | Kachelgelände (`cells-L0.png`) | Meer, Seen und Flüsse sind Wasser; Strassen queren Flüsse auf Brücken, nie das Meer. Liegt der Ort auf Wasser (Küste bei 0,5 km, moderne Stauseen wie bei Samosata), rückt die Mitte auf das nächste Land |

Alles hängt nur von der Stadt-ID ab: gleicher Plan bei jedem Lauf.

**Späte Mauern in Gallien und Germanien:** Von der zweiten Hälfte des 3. Jahrhunderts bis etwa 370
wurden die Städte dort neu ummauert, aber nur um einen kleinen Kern; die alte Stadt draussen blieb
offen und teils verlassen ([Urban enclosures in Roman Gaul](https://en.wikipedia.org/wiki/Urban_enclosures_in_Roman_Gaul);
Esmonde Cleary, 2013). Regel für die Provinzen Lugdunensis, Aquitania, Belgica und die beiden
Germanien (Städte ab 5'000 Einwohnern, Kolonien, Civitas-Hauptorte): Mauer um ein Fünftel der alten
Fläche, 6 bis 40 ha (eigene Schätzung; Tours und Paris etwa 9 ha, Bordeaux etwa 32 ha, aus dem
Gedächtnis, nicht geprüft), die Hälfte der Häuser draussen wird Garten. Ein Kern unter 25 ha
(Massstab 1: vier Parzellen) hat keinen Platz für eine Mauer und fällt weg; bei Massstab 1 betrifft
die Regel darum nur neun Städte.

Bekannte Lücken: Höhen und Hänge (Theater am Hang, Akropolis) fehlen.
Capua (170'000) und S. Maria Capua Vetere sind derselbe Ort doppelt in `cities.csv`.

## Format der gebackenen Karte

Seiten zu 64 × 64 Parzellen (16 km), an `world_min` ausgerichtet; Seiten mit Stadt liegen als Felder
in einem RGB8-Atlas (32 Felder je Reihe). `page_slots` in der JSON: `[seite_i, seite_j, feld]`.
Bei Überlappung gewinnt die grössere Stadt.

| Kanal | Inhalt |
|---|---|
| R | Art: 0 kein Plan (alte Stadtregel), 1 Haus, 2 Insula, 3 Domus, 4 öffentlicher Bau, 5 Platz, 6 Garten, 7 Strasse, 8 Mauer, 9 Tor, 10 Brücke, 11 Gräber, 12 Land (im Plan, aber keine Stadt), 13 Wasser |
| G | Bits 0–1 Belag, 2–3 Rang (0 keiner, 1 via, 2 vicus, 3 Gasse), 4–7 Anschlüsse N=16, O=32, S=64, W=128 |
| B | Häuser: Bits 0–5 Stockwerke (Insula 4–5, Haus 2, in Städten ab 100'000 2–3, Domus 1–2; eigene Regel); Bauten und Plätze: Bits 0–5 Modell (`models`); Bits 6–7 Seite der Front (0 N, 1 O, 2 S, 3 W), zur nächsten Strasse |

Je Stadt nennt die JSON Namen, Status, Rechteck und die Bauten mit ihrem Parzellenrechteck; die
fünf Bauten mit eigenem Landmarkenmodell in `tile_terrain.gd` (Kolosseum, Forum, Thermen, Pantheon,
Circus) tragen `landmark`, damit nichts doppelt gezeichnet wird.

## Werkzeuge

```
python3 tools/city_facts.py                                    # Hanson-Fakten je Stadt
python3 tools/city_plans.py --scale 1 --bake artifacts/render-data/city-plans-r1
python3 tools/city_plans.py --compare 1,2,3 --preview out/     # Rom in drei Massstäben
python3 tools/city_plans.py --scale 1 --preview out/ --px 26   # Vorschaubild je Plan
```

## Quellen

- Carandini, A. (Ed.). (2017). *The atlas of ancient Rome: Biography and portraits of the city*. Princeton University Press. (nicht online geprüft)
- Coarelli, F. (2014). *Rome and environs: An archaeological guide* (Updated ed.). University of California Press. (nicht online geprüft)
- de Soto, P., Pažout, A., Brughmans, T., et al. (2025). Itiner-e: A high-resolution dataset of roads of the Roman Empire. *Scientific Data, 12*, 1731. https://doi.org/10.1038/s41597-025-06140-z
- Esmonde Cleary, S. (2013). *The Roman West, AD 200–500: An archaeological study*. Cambridge University Press. (nicht online geprüft)
- Greaves, S., & Wallace-Hadrill, A. (Eds.). (2022). *Rome and the colonial city: Rethinking the grid*. Oxbow Books. https://library.oapen.org/handle/20.500.12657/54092
- Hanson, J. W. (2016). *An urban geography of the Roman world, 100 BC to AD 300*. Archaeopress. (Datenbank: OxREP, Spiegel github.com/wccarleton/urbanscale)
- Hanson, J. W., & Ortman, S. G. (2017). A systematic method for estimating the populations of Greek and Roman settlements. *Journal of Roman Archaeology, 30*, 301–324. (Band und Seiten nicht online geprüft)
- Kaiser, A. (2011). *Roman urban street networks*. Routledge.
- Poehler, E. E. (2017). *The traffic systems of Pompeii*. Oxford University Press.
- Richardson, L. (1992). *A new topographical dictionary of ancient Rome*. Johns Hopkins University Press. (nicht online geprüft)
- Ulpian, *Digesta* 43.11.1.2 (viae terrenae, glarea stratae, silice stratae). (Wortlaut nicht online geprüft)
