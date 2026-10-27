# Kit 2 — Massstab der Modellwelt

**Stand:** 27.10.2026 · **Status:** `entschieden` (Ramon, Projekt-Thread „Design a scaled-down diorama world“).
Konzeptseite mit Herleitung: Artifact „Diorama mit 50'000 Menschen“.
Werte mit „geschätzt“ sind eigene Annahmen.

## Grundregel

Die ganze Welt wird **in einem einzigen Massstab** verkleinert: Karte, Distanzen,
Städte, Bevölkerung und jede Bewegung. Jeder Einwohner wird **einzeln simuliert**,
mit Familie, Eigenschaften und Lebenslauf wie in Crusader Kings 3.

| Grösse | Faktor | Herleitung |
|---|---|---|
| Menschen, Häuser, Betriebe, Schiffe, Soldaten (Anzahl) | 1 : 1'133 | 56,65 Mio. im Spielgebiet (HYDE 3.3, 200 n. Chr.) → 50'000 |
| Fläche | 1 : 1'133 | gleiche Dichte wie damals |
| Länge, Distanz | 1 : 33,7 (gerundet 1 : 34) | √1'133 |
| Höhe | 1 : 33,7, danach 7,5-fach überhöht | SimCity 2000, PR #29 (K06) |
| Geschwindigkeit jeder Bewegung | 1 : 33,7 | damit jede Reise so lange dauert wie damals |
| Kalender, Lebensalter, Tageslänge | 1 : 1 | ein Spieljahr ist ein Jahr |

**Nicht verkleinert** wird der einzelne Mensch und was zu ihm gehört: Körper, Haus,
Hausrat, Wagen, Boot, Feld einer Familie. Weil Fläche und Menschen im selben
Verhältnis schrumpfen, hat jeder Mensch gleich viel Land wie damals; die Anteile
von Feld, Wald, Weide und Ödland bleiben gleich.

**Gemeinschaftsbauten** (Forum, Tempel, Thermen, Arena, Hafen, Lager) werden nach
ihrer Nutzerzahl bemessen, nicht nach ihrer echten Grösse. Das Kolosseum (50'000
Plätze) wird zu einer Arena mit etwa 45 Plätzen.

## Eckwerte

| Was | Damals | Im Diorama |
|---|---:|---:|
| Kartenausschnitt (`data/region.json`) | 4'900 × 4'100 km | 145 × 122 km |
| Landfläche (`data/gametiles/tiles.csv`) | 15,6 Mio. km² | 13'800 km² |
| Italien, Länge | ≈ 1'000 km | ≈ 30 km |
| Rom | ≈ 920'000 Einw., ≈ 20 km² | 813 Einw., ≈ 150 × 150 m, gut 100 Häuser |
| Städte ab 100 / 20 / 5 Einw. (Hanson 117, `places.csv`) | – | 7 / 100 / 360 |
| Landbevölkerung | ≈ 80 % | ≈ 41'200 |
| Häuser (≈ 6 Menschen je Haushalt, geschätzt) | – | ≈ 8'300 |
| Basis-Tile 25 km (K25) | 25 km | ≈ 740 m |
| Feinstes Tile Ebene 7 | 1,56 km | ≈ 46 m |
| Grafikkachel 0,5 / 16 km (PR #29) | 0,5 / 16 km | ≈ 15 m / 475 m |
| Höhenpunkt ETOPO 15″ | ≈ 460 m | ≈ 14 m |

## Koordinaten

- Geodaten, Tile-IDs (`eqc41-gt-v1`) und alle Kit-1-Daten bleiben in **echten Metern**.
  Nichts aus Kit 1 wird neu erzeugt.
- Weil Längen und Geschwindigkeiten mit demselben Faktor schrumpfen, rechnet die
  Simulation Wege und Reisezeiten direkt in echten Metern und echtem Tempo; das
  Ergebnis ist dasselbe.
- Die Konstante `DIORAMA_LAENGE = 1 / 33,66` rechnet echte Meter in Diorama-Meter um.
  Sie gilt für Darstellung und für alle Dinge in Menschengrösse (Haus, Feld, Figur),
  die in Diorama-Metern definiert sind und beim Platzieren umgerechnet werden.
- Dichten (Einw./km²) sind in Diorama-km² gleich wie damals. In echten Koordinaten
  gerechnet sind sie 1'133-mal kleiner. Die Schwellen S15 gelten in Diorama-km².

## Zeit und Bewegung

| Weg | Im Diorama | Dauer |
|---|---:|---:|
| Zu Fuss | ≈ 0,12 km/h | wie 4 km/h |
| Quer durch Rom | ≈ 150 m | ≈ 1 Stunde |
| Rom – Brundisium zu Fuss | ≈ 17 km | ≈ 2 Wochen |
| Rom – Alexandria per Schiff | ≈ 56 km | ≈ 2–3 Wochen |

- Reisen laufen wie in CK3 als Reise mit Ziel, Route und Dauer in Tagen.
- Der Alltag (Feld, Werkstatt, Markt) wird nicht als einzelner Gang simuliert. Man
  lebt, wo man arbeitet; Figuren dabei sind Animation.
- Wetter (Fronten, Wolken, Stürme) verkleinert sich in Grösse und Zuggeschwindigkeit
  im selben Massstab; ein Unwetter dauert so lange wie damals. Sonnenstand und
  Tageslänge bleiben echt.

## Folgen, die mitbedacht werden müssen

| Bereich | Folge des Massstabs | Vorschlag |
|---|---|---|
| Stände | Senat (600) ≈ 0,5 Personen, Ritter (≈ 20'000–30'000, geschätzt) ≈ 20–25, Dekurionen (≈ 100'000–150'000, geschätzt) ≈ 90–130, Sklaven (10–15 %, geschätzt) ≈ 5'000–7'500 | strikt verkleinern; der Senat ist eine Familie. Ob Ämter eine Mindestzahl bekommen, entscheidet Ramon. |
| Heer | Reichsheer ≈ 350'000 (geschätzt) → ≈ 300 Soldaten; eine Legion ≈ 5 Mann | Schlachten sind Gefechte weniger Personen; jeder Soldat ist ein Charakter. |
| Wirtschaft | Verbrauch und Leistung pro Kopf bleiben, Summen /1'133. Preise pro Stück bleiben, Staatshaushalt ≈ 900 Mio. Sesterzen → ≈ 0,8 Mio. (geschätzt) | Wirtschafts-Thread rechnet pro Kopf; aggregierte Mengen aus Quellen durch 1'133 teilen. |
| Flüsse und Strassen | Tiber ≈ 60 m → ≈ 2 m, aber Boote und Wagen bleiben in Menschengrösse | Wasserläufe und Strassen mit Verkehr bekommen mindestens die Breite ihres Verkehrsmittels. Abweichung offen ausweisen. |
| Kleine Orte | 133 Orte haben unter 1 Einwohner | als einzelner Hof oder weglassen, entscheidet Ramon. |
| Kleine Zahlen | Zufall wirkt stärker: Ein Hof kann aussterben, ein Dorf ohne Heiratspartner bleiben | Heiratskreis über die Reisedauer begrenzen; Verwandtschaftsgrad wie in CK3 führen. |
| Wachstum | 680 n. Chr. ≈ 73'000, Neuzeit mehrere 100'000 | ab etwa 200'000 Menschen den Faktor pro Epoche anheben (später entscheiden). |
| Kamera | nächster Zoom zeigt einzelne Häuser (≈ 10 m) | Ausschnittsbreiten aus Kit 1 („Stadt 5–10 km“, „500 m“) gelten in echten Metern; im Diorama ist Rom 150 m breit. |

## Was sich in Kit 2 ändert

- **S30 und S32 werden ersetzt** (siehe decisions.md S50–S56): Bevölkerung ist die
  Summe einzelner Menschen; Wachstum entsteht aus Geburten und Todesfällen.
- Kapazität K (S31, S35) bleibt und wirkt über Nahrung auf Gesundheit, Heirat und Kinderzahl.
- HYDE (S35) verteilt die 50'000 Menschen zum Start, deterministisch mit Seed.
- Tile-Raster, IDs, Teilen und Zusammenlegen (S10–S15) bleiben als Gliederung für
  Märkte, Provinzen und Kartenmodi.
- Rust-Kern, Befehle, Festkomma und Snapshots (S40–S48) bleiben; Menschen sind Entities.
