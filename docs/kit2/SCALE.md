# Kit 2 — Massstab der Modellwelt

**Stand:** 27.10.2026 (umgestellt von 50'000 auf 100'000 Personen) · **Status:** `entschieden` (Ramon, Projekt-Thread „Design a scaled-down diorama world“).
Konzeptseite mit Herleitung: Artifact „Diorama mit 100'000 Menschen“.
Werte mit „geschätzt“ sind eigene Annahmen.

## Grundregel

Die ganze Welt wird **in einem einzigen Massstab** verkleinert: Karte, Distanzen,
Städte, Bevölkerung und jede Bewegung. Jeder Einwohner wird **einzeln simuliert**,
mit Familie, Eigenschaften und Lebenslauf wie in Crusader Kings 3.

| Grösse | Faktor | Herleitung |
|---|---|---|
| Menschen, Häuser, Betriebe, Schiffe, Soldaten (Anzahl) | 1 : 566,5 | 56,65 Mio. im Spielgebiet (HYDE 3.3, 200 n. Chr.) → 100'000 |
| Fläche | 1 : 566,5 | gleiche Dichte wie damals |
| Länge, Distanz | 1 : 23,8 (gerundet 1 : 24) | √566,5 |
| Höhe | 1 : 23,8, danach 7,5-fach überhöht | SimCity 2000, PR #29 (K06) |
| Geschwindigkeit jeder Bewegung | 1 : 23,8 | damit jede Reise so lange dauert wie damals |
| Kalender, Lebensalter, Tageslänge | 1 : 1 | ein Spieljahr ist ein Jahr |

**Nicht verkleinert** wird der einzelne Mensch und was zu ihm gehört: Körper, Haus,
Hausrat, Wagen, Boot, Feld einer Familie. Weil Fläche und Menschen im selben
Verhältnis schrumpfen, hat jeder Mensch gleich viel Land wie damals; die Anteile
von Feld, Wald, Weide und Ödland bleiben gleich.

**Gemeinschaftsbauten** (Forum, Tempel, Thermen, Arena, Hafen, Lager) werden nach
ihrer Nutzerzahl bemessen, nicht nach ihrer echten Grösse. Das Kolosseum (50'000
Plätze) wird zu einer Arena mit etwa 90 Plätzen.

## Eckwerte

| Was | Damals | Im Diorama |
|---|---:|---:|
| Kartenausschnitt (`data/region.json`) | 4'900 × 4'100 km | 206 × 173 km |
| Landfläche (`data/gametiles/tiles.csv`) | 15,6 Mio. km² | 27'600 km² |
| Italien, Länge | ≈ 1'000 km | ≈ 42 km |
| Rom | ≈ 920'000 Einw., ≈ 20 km² | 1'626 Einw., ≈ 190 × 190 m, gut 250 Häuser |
| Städte ab 100 / 20 / 5 Einw. (Hanson 117, `places.csv`) | – | 19 / 203 / 537 |
| Landbevölkerung | ≈ 80 % | ≈ 82'300 |
| Häuser (≈ 6 Menschen je Haushalt, geschätzt) | – | ≈ 16'700 |
| Basis-Tile 25 km (K25) | 25 km | ≈ 1'050 m |
| Feinstes Tile Ebene 7 | 1,56 km | ≈ 66 m |
| Grafikkachel 0,5 / 16 km (PR #29) | 0,5 / 16 km | ≈ 21 m / 670 m |
| Höhenpunkt ETOPO 15″ | ≈ 460 m | ≈ 19 m |

## Koordinaten

- Geodaten, Tile-IDs (`eqc41-gt-v1`) und alle Kit-1-Daten bleiben in **echten Metern**.
  Nichts aus Kit 1 wird neu erzeugt.
- Weil Längen und Geschwindigkeiten mit demselben Faktor schrumpfen, rechnet die
  Simulation Wege und Reisezeiten direkt in echten Metern und echtem Tempo; das
  Ergebnis ist dasselbe.
- Die Konstante `DIORAMA_LAENGE = 1 / 23,80` rechnet echte Meter in Diorama-Meter um.
  Sie gilt für Darstellung und für alle Dinge in Menschengrösse (Haus, Feld, Figur),
  die in Diorama-Metern definiert sind und beim Platzieren umgerechnet werden.
- Dichten (Einw./km²) sind in Diorama-km² gleich wie damals. In echten Koordinaten
  gerechnet sind sie 566,5-mal kleiner. Die Schwellen S15 gelten in Diorama-km².

## Zeit und Bewegung

| Weg | Im Diorama | Dauer |
|---|---:|---:|
| Zu Fuss | ≈ 0,17 km/h | wie 4 km/h |
| Quer durch Rom | ≈ 190 m | ≈ 1 Stunde |
| Rom – Brundisium zu Fuss | ≈ 24 km | ≈ 2 Wochen |
| Rom – Alexandria per Schiff | ≈ 80 km | ≈ 2–3 Wochen |

- Reisen laufen wie in CK3 als Reise mit Ziel, Route und Dauer in Tagen.
- Der Alltag (Feld, Werkstatt, Markt) wird nicht als einzelner Gang simuliert. Man
  lebt, wo man arbeitet; Figuren dabei sind Animation.
- Wetter (Fronten, Wolken, Stürme) verkleinert sich in Grösse und Zuggeschwindigkeit
  im selben Massstab; ein Unwetter dauert so lange wie damals. Sonnenstand und
  Tageslänge bleiben echt.

## Folgen, die mitbedacht werden müssen

| Bereich | Folge des Massstabs | Vorschlag |
|---|---|---|
| Stände | Senat (600) ≈ 1 Senator, Ritter (≈ 20'000–30'000, geschätzt) ≈ 35–55, Dekurionen (≈ 100'000–150'000, geschätzt) ≈ 175–265, Sklaven (10–15 %, geschätzt) ≈ 10'000–15'000 | **entschieden (S58):** Ämter nach Aufgabe statt nach Massstab. Senat **40 Senatoren** (≈ 30 Statthalter, 2 Konsuln, Legaten, ≈ 10 in Rom), mit Familien ≈ 150 Personen. Jede Provinz hat einen Statthalter, jede Legion einen Legaten, Ritter ≈ 60 (Prokuratoren). Übrige Stände im Massstab. |
| Heer | Reichsheer ≈ 350'000 (geschätzt) → ≈ 620 Soldaten; eine Legion ≈ 10 Mann | Schlachten sind Gefechte weniger Personen; jeder Soldat ist ein Charakter. |
| Wirtschaft | Verbrauch und Leistung pro Kopf bleiben, Summen /566,5. Preise pro Stück bleiben, Staatshaushalt ≈ 900 Mio. Sesterzen → ≈ 1,6 Mio. (geschätzt) | Wirtschafts-Thread rechnet pro Kopf; aggregierte Mengen aus Quellen durch 566,5 teilen. |
| Flüsse und Strassen | Tiber ≈ 60 m → ≈ 2,5 m, aber Boote und Wagen bleiben in Menschengrösse | Wasserläufe und Strassen mit Verkehr bekommen mindestens die Breite ihres Verkehrsmittels. Abweichung offen ausweisen. |
| Kleine Orte | 133 Orte liegen unter 2 Einwohnern, 66 davon sogar unter 1 (z. B. Toledo, Siena, Eleusis, Carcassonne) | **entschieden (S57):** jeder Ort bekommt mindestens 2 Einwohner, ein Paar als Familie (zusammen rund +125 Personen). |
| Kleine Zahlen | Zufall wirkt stärker: Ein Hof kann aussterben | offen |
| Wachstum | 680 n. Chr. ≈ 145'000; 200'000 sind bei ≈ 113 Mio. echten Menschen erreicht (Mittelalter) | **entschieden (S59):** feste Obergrenze, Startwert 200'000 Personen. Der Massstab bleibt 1:566,5 für alle Epochen. |
| Kamera | nächster Zoom zeigt einzelne Häuser (≈ 10 m) | Ausschnittsbreiten aus Kit 1 („Stadt 5–10 km“, „500 m“) gelten in echten Metern; im Diorama ist Rom 190 m breit. |

## Was sich in Kit 2 ändert

- **S30 und S32 werden ersetzt** (siehe decisions.md S50–S56): Bevölkerung ist die
  Summe einzelner Menschen. Wie sie wächst und schrumpft, ist noch offen.
- Kapazität K (S31, S35) bleibt; wie sie auf die einzelnen Menschen wirkt, ist offen.
- HYDE (S35) verteilt die 100'000 Menschen zum Start, deterministisch mit Seed.
- Tile-Raster, IDs, Teilen und Zusammenlegen (S10–S15) bleiben als Gliederung für
  Märkte, Provinzen und Kartenmodi.
- Rust-Kern, Befehle, Festkomma und Snapshots (S40–S48) bleiben; Menschen sind Entities.
