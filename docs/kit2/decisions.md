# Kit 2 — Entscheidungen

**Stand:** 26.10.2026 · Quelle: Brainstorming mit Ramon im Projekt-Thread.
Neuere ausdrückliche Entscheidungen ersetzen ältere. Werte mit „Startwert“ sind
eigene Annahmen und werden kalibriert.

## Grundsätze

| ID | Entscheidung |
|---|---|
| S01 | **Eine Welt, eine Simulation.** Keine separate Stadtsimulation. |
| S02 | **Emergenz:** Geschichte, Städte, Wege und Staaten entstehen aus der Simulation, nicht aus Skripten. |
| S03 | **Zeichnen auf der Karte** wie in SimCity 4: Strassen, Felder, Siedlungen, Häfen u. a. werden als Geometrie gezeichnet. Spieler und KI nutzen dieselben Werkzeuge und Kosten. |
| S04 | **Ein Subsystem nach dem anderen.** Pro Subsystem zuerst Vorbilder prüfen, dann eigenes Design, dann Prototyp. |
| S05 | **Start 180 n. Chr.** Endpunkt offen (Kandidaten 1453, 1806, 1914 als harte Obergrenze). Ende eher zustandsbasiert, da die Geschichte emergent verläuft. |
| S06 | **Deterministisch:** gleicher Seed und gleiche Eingaben ergeben denselben Lauf; feste Rechenreihenfolge. |
| S07 | **Eigene Formeln.** Andere Spiele dienen als Vorbild über öffentliche Quellen; kein fremder Code, keine dekompilierten Inhalte. |

## Raum

| ID | Entscheidung |
|---|---|
| S10 | **Startraster** aus Kit 1: Land 25 km, dünne Gebiete gröber, dichte Regionen und Grossstädte feiner, etwa 15.000 Tiles. |
| S11 | **IDs** `eqc41-gt-v1:Ebene:Zeile:Spalte`, Kantenlänge 200 km / 2^Ebene (Ebene 3 = 25 km, Ebene 7 ≈ 1,56 km). Eltern/Kinder rechnerisch. |
| S12 | **Adaptiv zur Laufzeit:** Tiles teilen (Quadtree) und zusammenlegen, nach Dichte, für Spieler und KI gleich. 2:1-Regel zwischen Nachbarn, festes Zellbudget (Startwert 65.536 Zellen; das Startraster belegt rund 14.000), höchstens Ebene 7. |
| S13 | **Teilen/Zusammenlegen** nur im Monatstakt, in fester ID-Reihenfolge. Summen bleiben erhalten. Zusammenlegen mit Hysterese und Mindestdauer. |
| S14 | **Feine Geometrie** liegt in Weltkoordinaten, nicht an Tiles gebunden. Flächenwerte (Acker, Zonen, Strassen) berechnet jedes Tile selbst daraus; nur Bestandsgrössen werden beim Teilen verteilt. |
| S15 | **Startschwellen:** teilen bei > 200 Einw./km² oder feinerer gezeichneter Geometrie; zusammenlegen, wenn alle 4 Kinder < 100 Einw./km² und keine feinere Geometrie haben, 12 Monate in Folge. |

## Zeit

| ID | Entscheidung |
|---|---|
| S20 | **Takte:** täglich Armeen, Kämpfe, Warenströme; monatlich Wirtschaft, Preise, Bevölkerung, Tile-Struktur; jährlich langsame Grössen und KI-Bauplanung. |
| S21 | **Reihenfolge im Monatstakt:** 1) Kapazität K, 2) Bevölkerungswachstum, 3) Teilen/Zusammenlegen, 4) Aggregation auf Märkte. |
| S22 | **Preise** (späteres Subsystem) laufen gedämpft über mehrere Monate auf einen Zielpreis zu, nicht sprunghaft. |

## Subsystem 1: Bevölkerung

| ID | Entscheidung |
|---|---|
| S30 | **Ersetzt durch S53 (27.10.2026).** Bisher: Eine Zahl pro Tile. Gespeichert als Liste von Gruppen mit zunächst einer Gruppe, damit ein späterer Ausbau auf Vic3-Niveau eine Erweiterung ist. |
| S31 | **Kapazität aus Nahrung:** K = Nahrung / Bedarf pro Kopf. Nahrung = Ackerfläche × Boden × Klima (+ Importe, sobald Handel existiert). Keine feste Tabelle wie in EU5. |
| S32 | **Ersetzt durch S54 (27.10.2026).** Bisher: Wachstum logistisch: dP = r × P × (1 − P/K) pro Monat, r je Epoche, Modifikatoren nur als Faktoren. P ist eine Kommazahl. Liegt P über K, schrumpft P über dieselbe Formel. |
| S33 | **Teilen:** P_kind = P × K_kind / ΣK_kinder (sonst nach Landfläche; ohne Land kein Teilen wegen Bevölkerung). Rest exakt auf das letzte Kind in ID-Reihenfolge. So behalten alle Kinder dasselbe P/K. Zusammenlegen: P = ΣP. |
| S34 | **Performance:** Werte als Arrays pro Tile, nur aktive Tiles (kein Meer/Ödland ohne Bevölkerung) werden gerechnet. |
| S35 | **Übergang bis zum Landwirtschafts-Subsystem (Ramon, 26.10.2026):** K pro 25-km-Zelle = HYDE-3.3-Landbevölkerung (`rurc`) 200 n. Chr. / 0,7, Städte (Hanson 117) zusätzlich; Start = Landbevölkerung + Städte (HYDE kennt fast keine Stadtbevölkerung). S31 (K aus Ackerland × Ertrag) gilt weiter als Ziel und folgt, sobald es regionale Erträge gibt. Begründung: Mit einer Einheitszahl pro km² Ackerland starten 5 552 Tiles über K (run-1). |

## Massstab und Einzelpersonen (27.10.2026)

Nutzerentscheidung im Projekt-Thread „Design a scaled-down diorama world“. Details und Eckwerte: [SCALE.md](SCALE.md).

| ID | Entscheidung |
|---|---|
| S50 | **Ein Massstab für alles:** Anzahl Menschen und Fläche 1 : 566,5 (56,65 Mio. → 100'000), Längen, Distanzen und jede Bewegung 1 : 23,8. Kalender und Lebensalter echt. Höhe zusätzlich 7,5-fach überhöht (K06 nach PR #29). Mit dem Start nach S35 (HYDE-Land plus Städte nach Hanson, 66,1 Mio.) ergibt der Faktor rund **117'000 Personen**; so bestätigt (Ramon, 27.10.2026). |
| S51 | **Der einzelne Mensch wird nicht verkleinert:** Körper, Haus, Wagen, Boot und Feld einer Familie in echter Grösse. Gemeinschaftsbauten nach Nutzerzahl. |
| S52 | **Koordinaten:** Geodaten und Tile-IDs bleiben in echten Metern; `DIORAMA_LAENGE = 1/23,80` rechnet in Diorama-Meter um. Dichteschwellen (S15) gelten in Diorama-km². |
| S53 | **Jeder Einwohner ist ein eigener Charakter** (CK3-Stil): Name, Alter, Geschlecht, Familie und Dynastie, Eigenschaften, Fähigkeiten, Gesundheit, Kultur, Religion, Stand, Wohnhaus, Arbeit, Besitz, Beziehungen zu einem begrenzten Kreis (Startwert höchstens 30). Ersetzt S30. |
| S54 | **Die Bevölkerung ist die Summe der einzelnen Menschen.** Ersetzt S32. Wie sie wächst und schrumpft, ist offen und wird ein eigenes Subsystem. |
| S55 | **Reisen** laufen als Reise mit Route und Dauer in Tagen; Alltag am Wohn-/Arbeitsort wird nicht als Weg simuliert. |
| S56 | **Takte für Personen:** Routine täglich, Bedürfnisse und Beziehungen monatlich, Beruf und Umzug jährlich (Startwerte). Wenige wichtige Personen mit voller Planungs-KI, alle übrigen mit einfachen Bewertungsregeln. |
| S57 | **Jeder Ort aus `places.csv` bekommt mindestens 2 Einwohner** (ein Paar als Familie), auch wenn er nach Massstab darunter liegt (133 Orte, zusammen rund +125 Personen). So bleiben spätere Städte wie Toledo, Siena oder Eleusis auf der Karte und können wachsen. |
| S58 | **Ämter nach Aufgabe, nicht nach Massstab:** Senat 40 Senatoren (≈ 30 senatorische Statthalter, 2 Konsuln, Legaten, ≈ 10 in Rom für Fraktionen und Erbfolge), mit Familien ≈ 150 Personen. Jede Provinz einen Statthalter, jede Legion einen Legaten, Ritterstand ≈ 60 Personen für die Prokuratoren. Alle übrigen Zahlen im Massstab (S50). |
| S59 | **Feste Obergrenze für die Bevölkerung**, Startwert 200'000 Personen (nach dem Prototyp zu prüfen). Kein Wechsel des Massstabs. Wie die Grenze eingehalten wird, ist offen. |
| S60 | **Richtung für später (Ramon, 27.10.2026), noch ohne Regeln:** Nahrung und Lebensraum sollen das Wachstum der Bevölkerung begrenzen. Menschen können auswandern: Sie verlassen die Karte und damit das System. Wie das genau funktioniert, ist offen. |
| S61 | **Zugehörigkeiten (Ramon, 27.10.2026):** Jeder Einwohner gehört einer Pop an (Region, Stand, Kultur, Religion; Region vorerst ≈ 100 km, d. h. Tile-Ebene 1, später die Provinz, so bestätigt von Ramon; ≈ 2'000 Pops mit je 40–100 Menschen statt 32'000 bei 25-km-Zellen), einer wirtschaftlichen Gruppe und einer oder mehreren politischen Gruppen. Die Zugehörigkeit ist ein Merkmal des einzelnen Menschen; Gruppen werden aus ihren Mitgliedern berechnet und zählen niemanden doppelt. Wer Stand, Beruf oder Wohnort wechselt, wechselt die Gruppe. Offen: welche Gruppen es gibt, ihre Werte und Regeln. |
| S62 | **Kinder entstehen nur aus Paaren**, wie in CK3 (Ramon, 27.10.2026). Jedes Kind hat Mutter und Vater; Familien und Dynastien entstehen daraus. Chance, Alter und Fruchtbarkeit: offen. |
| S63 | **Ehe durch die Familie, Suchradius nach Stand** (Ramon, 27.10.2026). Das Familienoberhaupt sucht monatlich Partner für ledige Kinder im heiratsfähigen Alter; das Paar stimmt zu. Gemeine suchen unter den Bekannten der Familie und den Ledigen derselben Region und desselben Standes. Oberschicht (Senatoren, Ritter, Dekurionen) sucht reichsweit unter ihresgleichen und bewertet nach Rang, Bündnis und Vermögen wie CK3. Findet eine Familie mehrere Monate niemanden, wächst der Suchradius auf die Nachbarregionen. Die Braut zieht in den Haushalt des Mannes. Historische Orientierung (Saller, Shaw, aus dem Gedächtnis, zu prüfen): Erstheirat Frauen ≈ 15–20, Männer Ende 20, Senatoren früher; Sklaven nur *contubernium*, Kinder bleiben Sklaven; Soldaten ohne Ehe bis 197. Offen: genaue Alter, Zustimmung, Scheidung und Wiederheirat. |
| S64 | **Tod: Sterbetafel plus Gesundheit** (Ramon, 27.10.2026). Grundchance pro Monat nach Alter und Geschlecht aus einer historischen Modell-Sterbetafel (Frier, Scheidel; Lebenserwartung bei Geburt ≈ 25 Jahre, aus dem Gedächtnis, Tafel beim Bau festlegen). Der Gesundheitswert jedes Menschen (gesenkt durch Hunger, Krankheit, Verletzung) hebt oder senkt diese Chance. Eigene, benannte Todesursachen wie in CK3: Geburt, Krieg, Unfall, Mord, später Seuchen. Offen: die Tafel, die Stärke der Gesundheit, die Ursachen im Einzelnen. |
| S65 | **Nahrung und Lebensraum bremsen emergent, über die Menschen** (Ramon, 27.10.2026; konkretisiert S60). Wenig Nahrung im Haushalt senkt Gesundheit (→ S64) und Fruchtbarkeit (→ S62). Fehlen freies Haus oder Land, wird später geheiratet (→ S63). Keine Formel, die das Wachstum direkt an K bindet; K aus Ackerland, Boden und Klima bleibt die Quelle der Nahrung. Offen: wie Nahrung auf Haushalte verteilt wird, was als Lebensraum zählt, die Stärke der Effekte. |
| S66 | **Umzug und Auswanderung: der Haushalt entscheidet nach Lage** (Ramon, 27.10.2026; konkretisiert S60). Haushalte in Not (nicht Einzelne) vergleichen etwa einmal im Jahr ihre Lage mit erreichbaren Orten und ziehen um, wenn ein Ort besser ist. Ist kein erreichbarer Ort besser, verlassen sie die Karte am nächsten Rand und damit das System. Keine feste Rate; Wanderung entsteht aus der Lage der Menschen. Offen: was als Not zählt, wie weit gesucht wird, was als besser gilt. |
| S67 | **An der Obergrenze: mehr Auswanderung** (Ramon, 27.10.2026; konkretisiert S59). Erreicht die Bevölkerung 200'000, wandern mehr Haushalte aus (→ S66). Niemand stirbt durch eine Regel. Offen: wie das ausgelöst wird. |

Offen: Wachstum und Rückgang der Bevölkerung (S54), Flussbreite gegenüber Bootsgrösse, Rolle des Spielers (Familie wie in CK3?).

## Ausdrücklich später (je eigenes Subsystem)

Hunger-Sterblichkeit, Seuchen, Migration, Regeln der Bevölkerungsgruppen (Struktur steht in S61), Handel und
Importe, Preise, emergente Wege, gezieltes Bauen der KI, Staaten, Krieg, Technik,
Umwelt. Bisherige Ideen dazu (nicht entschieden): Wege entstehen emergent aus
Verkehr und werden gezielt ausgebaut; die KI plant Bauprojekte zielbasiert etwa
jährlich (Ziele → Kandidaten per Pfadsuche → Nutzen/Kosten → Vorlagen).

## Offen

- Rolle des Spielers (Staat, Dynastie, …).
- Endpunkt der Simulation.
- Datensatz für Startbevölkerung, Ackerland, Boden und Klima um 180 n. Chr. (Kandidat: HYDE 3.3, Lizenz prüfen).
- Wert von r je Epoche und Nahrungsbedarf pro Kopf.
