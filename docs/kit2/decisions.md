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
| S30 | **Eine Zahl pro Tile.** Gespeichert als Liste von Gruppen mit zunächst einer Gruppe, damit ein späterer Ausbau auf Vic3-Niveau eine Erweiterung ist. |
| S31 | **Kapazität aus Nahrung:** K = Nahrung / Bedarf pro Kopf. Nahrung = Ackerfläche × Boden × Klima (+ Importe, sobald Handel existiert). Keine feste Tabelle wie in EU5. |
| S32 | **Wachstum logistisch:** dP = r × P × (1 − P/K) pro Monat, r je Epoche, Modifikatoren nur als Faktoren. P ist eine Kommazahl. Liegt P über K, schrumpft P über dieselbe Formel. |
| S33 | **Teilen:** P_kind = P × K_kind / ΣK_kinder (sonst nach Landfläche; ohne Land kein Teilen wegen Bevölkerung). Rest exakt auf das letzte Kind in ID-Reihenfolge. So behalten alle Kinder dasselbe P/K. Zusammenlegen: P = ΣP. |
| S34 | **Performance:** Werte als Arrays pro Tile, nur aktive Tiles (kein Meer/Ödland ohne Bevölkerung) werden gerechnet. |

## Ausdrücklich später (je eigenes Subsystem)

Hunger-Sterblichkeit, Seuchen, Migration, Bevölkerungsgruppen, Handel und
Importe, Preise, emergente Wege, gezieltes Bauen der KI, Staaten, Krieg, Technik,
Umwelt. Bisherige Ideen dazu (nicht entschieden): Wege entstehen emergent aus
Verkehr und werden gezielt ausgebaut; die KI plant Bauprojekte zielbasiert etwa
jährlich (Ziele → Kandidaten per Pfadsuche → Nutzen/Kosten → Vorlagen).

## Offen

- Rolle des Spielers (Staat, Dynastie, …).
- Endpunkt der Simulation.
- Datensatz für Startbevölkerung, Ackerland, Boden und Klima um 180 n. Chr. (Kandidat: HYDE 3.3, Lizenz prüfen).
- Wert von r je Epoche und Nahrungsbedarf pro Kopf.
