# Lauf „grain“: Höfe, Markt, Getreidehandel und Fusswege (S69–S76)

**Stand:** 27.10.2026 abends, Cloud-Container mit 4 Kernen · **Status:** `implementiert` (Prototyp). Die Messung auf dem Mac steht noch aus.

Die Getreidewirtschaft läuft neben dem Personen-Prototyp ([run-people](../run-people/README.md))
mit denselben rund 117'000 Menschen. Sie ersetzt die Nahrung K aus S35: Gesundheit,
Heirat und Wanderung hängen jetzt daran, was jeder Haushalt wirklich gegessen hat.
Plan und Zahlen: [GRAIN.md](../GRAIN.md), [GRAIN-NUMBERS.md](../GRAIN-NUMBERS.md).

```
cd sim && cargo run --release --bin grain -- --years 100 [--seed S] [--threads N] [--clear-pct P] [--clear-cover SPALTEN|usable]
GRAIN_DEBUG=1 …   # zusätzlich die grössten Märkte und Hofgrössen pro Jahr
```

Dateien: `sim/src/grain.rs` (alles), `sim/src/bin/grain.rs` (Lauf), Haken in
`sim/src/people.rs` (`Econ`: gegessen pro Haushalt, freies Land und Nahrung pro Kopf pro
Region). `run100.txt` ist die ganze Ausgabe des Standardlaufs (Saatgut, Brache,
Handelswege, Felder auf Kacheln, Personen mit S81 und S82), `run100-before-s73.txt` derselbe
ohne Kacheln, `run100-s71.txt` die Handelswege vor S81, `run100-before-s71.txt` auch ohne Handelswege,
`run100-seed-nofallow.txt` ohne Brache, `run100-before-s76.txt` ohne Saatgut und Brache;
`run60-noclear.txt`,
`run60-farm-grass.txt` und `run60-farm-grass-wood.txt` sind die Vergleiche zum rodbaren Land.
Rodbares Land pro Zelle und pro Kachel: `tools/sim_landcover.py` → `sim/inputs/landcover25.csv`
und `sim/inputs/landcover-fine.bin.zst`.

## Was gebaut ist

| Teil | Umsetzung | Entscheidung |
|---|---|---|
| **Höfe** | Ein Hof pro Bauernhaushalt beim Start: Familienhof (Bauern), Pachthof (Pächter, Pacht an einen Grundherrn) und Gutshof (Unfreie, alles gehört dem Grundherrn, einem Senator oder Ritter). Tagelöhner auf dem Land haben keinen Hof und leben im Zelt. Wird ein Hof frei (Familie ausgestorben oder weggezogen), zieht automatisch ein Haushalt aus den Zelten derselben Region ein. Neue Höfe baut nur der Spieler; den gibt es im Prototyp noch nicht. | S69 |
| **Felder** | Fläche pro Hof in echter Grösse (S51). Land pro 25-km-Zelle: HYDE-Ackerland 200 im Massstab 1 : 566,5, danach rodbares Land mit schlechterem Ertrag. Rodbar ist, was heute Acker oder Siedlung ist (ESA WorldCover 2021) und unter 16 % Hang liegt (Copernicus-DEM), abzüglich des HYDE-Ackers. Ein Hof bestellt, was seine Erwachsenen übers Jahr und alle Hände in der Ernte schaffen, mindestens aber, was den Haushalt ernährt. Wächst die Familie, nimmt sie bei der Aussaat freies Land und rodet dazu. Die Felder liegen auf Kacheln von 1,56 km um den Hofplatz, die nächsten freien zuerst (siehe unten). | S73 |
| **Ernte und Saisonarbeit** | Aussaat und Ernte sind Ereignisse pro Hof (Erntetag nach Breite, Höhe und Hof gestreut). Was die Familie im Fenster nicht schafft, sucht der Hof an der wöchentlichen Arbeitsbörse der Region: zuerst Leute aus den Zelten, dann Höfe mit freien Händen. Lohn in Getreide. Fehlen Hände, bleibt ein Teil der Ernte auf dem Feld oder ein Teil des Feldes ungesät. | S72 |
| **Saatgut und Brache** | Jeder Hof legt nach der Ernte das Saatgut fürs nächste Jahr zurück (130 kg/ha) und sät es im Herbst aus dem Hofspeicher; fehlt es, bleibt Feld ungesät. Die Ernte bringt brutto Saat mal Saatverhältnis. Zweifelderwirtschaft: Jedes Jahr liegt die Hälfte der Felder brach, ein Hof braucht also doppelt so viel Land. | S76 |
| **Speicher** | Getreide liegt im Hofspeicher, im Vorrat jedes Haushalts und im Lager jedes Markts, in ganzen kg. Steuer geht beim Ernten ab. Kein Verderb (keine Quelle). | S72 |
| **Markt** | Ein Markt pro 100-km-Region, am grössten Ort nach Hanson, sonst an der Zelle mit den meisten Menschen (1'783 Märkte). Lager, Bargeld der Händler am Markt und ein Preis, der jeden Tag gedämpft auf einen Zielpreis aus der Lagerreichweite zuläuft. Ankauf 10 % unter, Verkauf 10 % über dem Preis. Der Markt kauft nur, so weit sein Bargeld reicht; was er nicht nimmt, trägt der Bauer wieder heim. | S70, S22 |
| **Träger** | Jede Fahrt zum Markt ist eine echte Person des Haushalts (zuerst ein Mann 15–60) mit Last und Tempo nach ORBIS und Preisedikt: Familien- und Pachthof mit Esel (97 kg, 30 km/Tag), Gutshof mit Ochsenkarren (388 kg, 12 km/Tag), ohne Hof zu Fuss (30 kg pro Erwachsenem, 20 km/Tag). Die Reise ist ein Ereignis mit Ankunftstag, kein Schritt pro Tag. Wer im Marktort wohnt, kauft sofort. | S70, S76 |
| **Händler** | Erwachsene mit Beruf Händler. Sie kennen höchstens 32 Märkte (die billigsten Wege über Land mit Wagen, über See mit Schiff) mit Preisen, die so alt sind wie die Reise von dort. Einmal pro Woche: ausführen (hier kaufen, dort verkaufen) oder einführen (leer hin, dort kaufen, hier verkaufen), wenn die Marge nach Fracht über 10 % liegt. Fracht nach Preisedikt (Wagen 0,035 Denar pro kg·km) und ORBIS (See ≈ 0,001). Wo sie fahren, entstehen Handelswege: Jede 25-km-Zelle zählt die Fahrten, geglättet mit zwei Jahren Halbwertszeit; ab 100 Fahrten im Jahr wird sie Handelsweg, ab 400 Strasse (mit Hysterese). Der Wagen fährt dort 20 % bzw. 35 % billiger, und die Märkte in Reichweite suchen ihre Nachbarn neu. Seewege werden nur gezählt. | S71 |
| **Waisen und Alte** | Haushalte ohne jemanden von 15–60 ziehen einmal im Jahr zum nächsten Verwandten (S79, Personen-Prototyp). Wer keinen hat, geht ins Zelt: Der Hof wird frei (der Hofspeicher bleibt beim Hof), der Vorrat bleibt beim Haushalt. Ein Zelt ohne Erwachsene übernimmt keinen freien Hof. | S79 |
| **Hunger** | Jeder Haushalt isst einmal im Monat aus seinem Vorrat. Der Anteil, den er bekommt, treibt die Gesundheit (S64) und damit Tod und Geburt. Wer zu wenig hat, kauft; wer nichts hat, bettelt am Markt und stiehlt dann von einem Hof der Region. Haushalte, die weniger als 80 % bekommen, ziehen in die Nachbarregion mit der meisten Nahrung pro Kopf oder verlassen die Karte (S66). | S69, S71 |
| **Geld** | Der Staat hat unbegrenzt Geld (S76): Wer weder Bauer noch Händler ist, bekommt den Taglohn des Preisedikts (25 Denar) vom Staat. Bauern bekommen Geld nur für verkauftes Getreide. | S76 |
| **Fusswege** | Jeder Markt hat ein Wegfeld über seine Region auf dem Feinraster (Kachelebene 7, ≈ 1,56 km echt). Die Gänge zum Markt nutzen Zellen ab (Helbing 1997), die Abnutzung zerfällt mit einer Halbwertszeit von einem Jahr. Ab einer Schwelle wird eine Zelle Trampelpfad, dann Weg (mit Hysterese); beides macht das Gehen billiger, so dass die nächsten Gänge dem Pfad folgen. | S70 |

## Ergebnis mit Saatgut und Brache (100 Jahre, Seed 1, `run100-before-s71.txt`)

| Jahr | Menschen | Wachstum | Hungertote | ausgewandert | Höfe | Zelte / Menschen darin | Ernte brutto t | Ernte verloren t | verkauft t | Handel t | gegessen | Preis Rom (Denar/kg) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 114'870 | −1,66 % | 452 | 352 | 19'499 | 5'883 / 12'330 | 40'007 | 425 | 3'321 | 6'538 | 91 % | 28,1 |
| 2 | 113'948 | −0,80 % | 1'577 | 1'397 | 17'185 | 7'623 / 20'764 | 39'130 | 308 | 4'470 | 7'919 | 79 % | 21,2 |
| 5 | 105'556 | −1,91 % | 905 | 2'099 | 15'706 | 6'388 / 15'021 | 39'143 | 494 | 3'592 | 7'107 | 86 % | 7,8 |
| 10 | 99'803 | −0,61 % | 443 | 810 | 14'665 | 4'094 / 8'240 | 39'495 | 771 | 2'753 | 3'761 | 93 % | 4,5 |
| 20 | 97'735 | −0,21 % | 273 | 459 | 12'944 | 1'501 / 3'651 | 39'804 | 969 | 2'731 | 3'821 | 96 % | 9,8 |
| 30 | 98'636 | +0,21 % | 291 | 487 | 11'351 | 787 / 2'014 | 40'279 | 1'005 | 2'700 | 2'870 | 96 % | 28,7 |
| 50 | 107'345 | +0,36 % | 304 | 352 | 9'187 | 181 / 821 | 40'999 | 948 | 2'513 | 2'143 | 96 % | 60,8 |
| 70 | 119'046 | +0,50 % | 369 | 274 | 7'945 | 77 / 594 | 41'691 | 748 | 2'417 | 2'056 | 96 % | 45,7 |
| 100 | 136'942 | +0,41 % | 501 | 152 | 6'760 | 42 / 423 | 41'980 | 499 | 2'377 | 1'462 | 95 % | 28,2 |

**Jetzt bindet das Land.** Die Ernte bleibt über 100 Jahre fast gleich (39'000–42'000 t
brutto), weil die Höfe für dieselbe Getreidefläche doppelt so viel Land brauchen und das
rodbare Land (heutiges Ackerland unter 16 % Hang) in den dichten Zellen ausgeht. Die
Bevölkerung fällt in den ersten 20 Jahren von 117'000 auf 98'000 (Hunger in den Zelten,
Auswanderung) und wächst danach mit 0,2–0,5 % im Jahr auf 137'000. **Über 100 Jahre sind
das 0,16 % im Jahr**, nahe an den historischen 0,1 %. Gegessen wird im Mittel 95–96 % des
Bedarfs. Rom wird teuer (bis 61 Denar/kg nach 50 Jahren), weil die Überschüsse im Umland
kleiner werden; Händler bringen weniger.

Die weiche Obergrenze (S80: ab 90 % von CAP = 180'000 wandern Haushalte in Not eher aus)
greift mit Brache nicht; der Lauf ist mit und ohne S80 Bit für Bit gleich.

**Ohne Brache, nur mit Saatgut** (`--crop-pct 100`, `run100-seed-nofallow.txt`): 117'000 →
184'000, 0,46 % im Jahr; die Ernte wächst mit (54'000 → 73'000 t). Ab etwa Jahr 85 greift
S80: Das Wachstum fällt auf 0,2 % und die Auswanderung steigt (1'256 im Jahr 100).

Tempo mit Brache (100 Jahre, 2 Threads, gleichzeitig mit dem Vergleichslauf): Getreide
Median 1,02 ms, Mittel 1,21 ms, 99 % 3,5 ms; ganzer Tag 99 % 9,1 ms.

## Ergebnis ohne Saatgut und Brache (vorheriger Stand, `run100-before-s76.txt`)

Rodbar ist heutiges Ackerland unter 16 % Hang (Standard). Die Bevölkerungszahlen
des Personen-Prototyps sind die vom 27.10.2026 abends (Heirat ab 20 als Platzhalter, S79 Waisen; vor S80).

| Jahr | Menschen | Wachstum | Hungertote | ausgewandert | Höfe | Zelte / Menschen darin | Ernte t | Ernte verloren t | verkauft t | Handel t | Preis Rom (Denar/kg) | Trampelpfade / Wege (Zellen) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 114'970 | −1,57 % | 403 | 405 | 19'533 | 5'838 / 12'165 | 42'212 | 651 | 3'798 | 6'682 | 25,0 | 2'141 / 98 |
| 2 | 115'332 | +0,31 % | 1'019 | 930 | 18'307 | 6'599 / 16'031 | 43'892 | 738 | 5'460 | 8'127 | 25,6 | 8'684 / 529 |
| 10 | 113'523 | +0,11 % | 290 | 318 | 17'031 | 3'779 / 7'156 | 45'752 | 1'769 | 2'943 | 2'553 | 3,3 | 16'689 / 1'434 |
| 20 | 116'507 | +0,15 % | 217 | 277 | 15'649 | 1'488 / 3'694 | 47'246 | 1'811 | 3'139 | 2'582 | 4,6 | 17'792 / 1'524 |
| 30 | 121'894 | +0,61 % | 183 | 159 | 13'987 | 797 / 2'059 | 48'383 | 2'236 | 2'951 | 2'215 | 4,9 | 17'630 / 1'495 |
| 50 | 141'044 | +0,64 % | 229 | 111 | 11'623 | 175 / 809 | 51'491 | 2'033 | 3'402 | 2'354 | 5,7 | 16'705 / 1'456 |
| 70 | 164'219 | +0,75 % | 299 | 127 | 10'286 | 75 / 447 | 54'991 | 1'814 | 3'694 | 2'511 | 6,8 | 16'164 / 1'382 |
| 100 | 202'462 | +0,59 % | 421 | 364 | 9'070 | 36 / 359 | 59'548 | 1'266 | 4'040 | 1'961 | 16,7 | 15'428 / 1'298 |

**Was emergent passiert:**
- **Die ersten 20 Jahre wächst fast nichts (−0,1 bis +0,3 % im Jahr).** Im ersten Jahr
  gehen 5'244 Haushalte ohne Arbeitsfähige und ohne Verwandte ins Zelt (S79); ihre Höfe
  übernehmen Landlose. Zelte finden nur in Aussaat und Ernte Arbeit, essen im Mittel
  60–75 % ihres Bedarfs, werden krank, sterben oder wandern ab. Nach 30 Jahren leben noch
  2'000 Menschen in Zelten, nach 100 Jahren 360.
- **Danach wächst die Bevölkerung mit 0,6–0,75 % im Jahr**, über 100 Jahre 0,55 %
  (117'000 → 202'000). Getreide ist fast nirgends knapp, der Preis liegt meist am unteren
  Anschlag (2,2 Denar/kg). Brache und Missernten fehlen noch (S72, S76).
- **Rom wird über Händler versorgt.** Im ersten Jahr steht der Preis dort bei 25 Denar/kg,
  Händler bringen 6'700 t, nach zehn Jahren liegt er bei 3–5. Weil Rom stark wächst,
  steigt er nach 100 Jahren wieder auf 17. Eine Sonderregel für Rom gibt es nicht (S72).
- **Höfe werden weniger, aber grösser.** Haushalte teilen sich im Personen-Prototyp nie
  (Kinder bleiben, die Braut zieht ein), darum wachsen sie, und frei gewordene Höfe finden
  ohne Landlose keinen neuen Haushalt.
- **Fusswege:** Nach etwa 10 Jahren stehen rund 17'000 Feinraster-Zellen als Trampelpfad
  und 1'400 als Weg. Sie bündeln sich auf den Linien zu den Märkten und bleiben stabil.

**Rodbares Land aus Daten (S73, Ramon: erst Landbedeckung holen).** Für jede 25-km-Zelle
zählt `tools/sim_landcover.py` auf demselben Stichprobenraster wie Kit 1 (1/300 Grad)
ESA WorldCover 2021 nach Gruppen (Acker und Siedlung, Grasland, Wald und Busch, Rest)
und den Hang aus dem Copernicus-DEM (FAO-Klassen unter 8, 8–16, 16–30, über 30 %).
Rodbar ist immer nur, was über das HYDE-Ackerland von 200 hinausgeht. Über das ganze
Gebiet sind das 2,4 Mio. km² heutiges Ackerland unter 16 % Hang (HYDE-Acker 200:
0,6 Mio. km²), mit Grasland 4,3 Mio., mit Wald 6,7 Mio. 60 Jahre, Seed 1, vor S79:

| Rodbar | Menschen nach 20 / 60 Jahren | Wachstum Jahr 30–60 |
|---|---|---|
| nichts (nur HYDE-Acker) | 100'842 / 121'947 | 0,5 % |
| heutiges Ackerland, Hang < 16 % (Standard) | 116'163 / 152'666 | 0,8 % |
| plus Grasland | 122'630 / 167'608 | 0,8 % |
| plus Grasland und Wald | 125'256 / 172'780 | 0,9 % |
| alles nutzbare Land (alter Stand, `--clear-cover usable`) | 125'356 / 174'353 | 0,8 % |

**Antwort auf die Frage nach 0,1 % im Jahr:** Ohne Brache nur in den ersten 20 Jahren,
solange die Landlosen hungern; danach 0,6–0,9 % mit jeder Rodungsvariante. Mit Brache
(oben) bindet das Land, und es sind über 100 Jahre 0,16 % im Jahr.

## Handelswege (S71, 100 Jahre, vor S81, `run100-s71.txt`; ohne: `run100-before-s71.txt`)

| Jahr | Handelswege / Strassen / Seewege (Zellen) | Menschen | Preis Rom (Denar/kg) ohne → mit |
|---|---|---|---|
| 5 | 122 / 19 / 554 | | |
| 10 | 124 / 21 / 580 | 99'593 (ohne 99'803) | 4,52 → 4,58 |
| 50 | 57 / 7 / 263 | 107'395 (ohne 107'345) | 60,8 → 33,4 |
| 100 | 29 / 0 / 115 | 135'489 (ohne 136'942) | 28,2 → 30,6 |

Die Wege entstehen in den ersten Jahren, solange die Lager vom Start den Handel tragen,
und zerfallen danach mit dem Handel (Fahrten im Jahr 10: 277'000, im Jahr 100: 107'000).
Wo eine Strasse liegt, kommt Getreide billiger nach Rom; in Jahr 50 halbiert sich der
Preisausschlag dort. Auf Wachstum und Bevölkerung wirkt es kaum (0,16 %/Jahr wie vorher),
weil das Land bindet, nicht der Transport.

## Felder auf Kacheln (S73, 100 Jahre, `run100.txt`; ohne: `run100-before-s73.txt`)

Jede 25-km-Zelle hat 16 × 16 Kacheln zu 1,56 km (dasselbe Raster wie die Fusswege). Ihr
freies Land liegt auf ihren Kacheln nach dem Anteil heutigen Ackerlands (WorldCover) unter
16 % Hang, das gute HYDE-Land zuerst auf dem flachen (unter 8 %). Eine Kachel fasst höchstens
ihre Fläche. Ein Hof nimmt seine Felder auf den freien Kacheln, die seinem Hofplatz am
nächsten liegen: beim Start aus seiner Zelle, danach im Umkreis von 8 Kacheln, auch über die
Zellgrenze. Zuerst gutes Land, dann rodet er (S73). Gibt er Land ab, zuerst gerodetes, zuletzt
genommenes.

Beide Läufe auf dem Stand mit S81 (Haushalte teilen sich, wenn der Vater stirbt) und S82:

| Jahr | Menschen ohne → mit Kacheln | Wachstum ohne / mit | Preis Rom ohne → mit |
|---|---|---|---|
| 10 | 99'782 → 100'371 | −0,72 % / −0,60 % | 4,9 → 4,2 |
| 20 | 98'255 → 99'114 | −0,01 % / −0,07 % | |
| 50 | 104'708 → 105'607 | +0,20 % / +0,29 % | 24,0 → 15,0 |
| 100 | 108'327 → 108'900 | −0,00 % / −0,07 % | 20,8 → 23,6 |

Die Kacheln ändern wenig: etwas mehr Menschen, weil ein Hof am Rand seiner Zelle jetzt auch
freies Land der Nachbarzelle nimmt. **Auffällig ist der neue Stand der Personen:** Mit S81
wächst die Bevölkerung nach 50 Jahren nicht mehr, über 100 Jahre −0,07 % im Jahr (vor S81
+0,16 %). Es gibt mehr und kleinere Haushalte (9'900 Höfe im Jahr 100 statt 6'700).
Vergleich vor S81 (Handelswege, ohne → mit Kacheln, je 4 Threads allein): Jahr 100 135'489 →
137'827.

## Tempo und Speicher (4 Cloud-Kerne)

| Grösse | Wert |
|---|---|
| Aufbau Getreide | 0,42 s (Marktgraph mit 32 Nachbarn pro Markt, Land auf 4,9 Mio. Kacheln verteilen) |
| **Getreide pro Tag, Median / Mittel** | **1,41 ms / 1,63 ms** (ohne Kacheln 1,44 / 1,62; vor S81 1,09 / 1,23) (Ziel Mittel ≤ 1,5 ms) |
| Getreide pro Tag, 95 % / 99 % | 3,0 ms / 4,1 ms (Ziel Spitze ≤ 5 ms) |
| Ganzer Tag mit Menschen, Median / 95 % / 99 % | 4,1 / 6,5 / 8,3 ms (Ziel 99 % ≤ 12 ms) |
| Speicher nach 100 Jahren | 448 MB (ohne Kacheln 368 MB) |
| Determinismus | gleicher Fingerabdruck mit 1 und 4 Threads; Test `grain::tests::deterministic_fingerprint` |

**Das Mittel liegt jetzt über dem Ziel von 1,5 ms, mit und ohne Kacheln.** Grund sind die
vielen kleineren Haushalte seit S81: Essen, Arbeitsbörse und Reisen wachsen mit der Zahl der
Haushalte. Pro Tag im Mittel: Reisen (Ankunft, Rückkehr) 0,22 ms, Arbeitsbörse 0,17, Märkte
und Nachrichten 0,19, Essen und Kaufen 0,25, Händler mit Handelswegen 0,23, Fusswege 0,28,
Aussaat und Ernte mit Kachelsuche 0,07 (ohne 0,02), Haushaltszählung 0,20.

**Handelswege.** Ändert sich eine Zelle, sucht nur ein Markt neu, dessen Nachbarsuche diese
Zelle berührt hat (Rechteck um alle besuchten Zellen). Die betroffenen Märkte verteilen sich
über das Jahr und laufen parallel. Ohne diese Prüfung kostete es 0,54 ms pro Tag.

**Haushaltszählung über eine Woche verteilt.** Früher zählte die Getreidewirtschaft alle
Haushalte an einem Tag des Monats neu (15 ms, bei 250'000 Menschen 18 ms). Jetzt nimmt sie
an Tag 11 einen Schnappschuss der Lebenden (0,9 ms) und zählt ihn auf einem eigenen
Thread. Das Ergebnis übernimmt sie an Tag 14, verteilt freie Höfe an Tag 15, ordnet die
Tagesgruppen an Tag 16 neu und rechnet die Summen pro Markt an Tag 17, je etwa 1 ms. Ein
Haushalt, der dazwischen ausstirbt, wird übersprungen, ein neuer isst ein paar Tage später.
Beim Umzug auf einen freien Hof kommen die Mitglieder aus der Zählung; wer seither geboren
wurde oder eingeheiratet hat, bleibt zurück (wenige Fälle pro Jahrhundert).

**Fusswege.** Die Gänge fliessen einmal den Baum des Wegfelds hinab statt Weg für Weg,
die Märkte eines Tages laufen auf dem Task-Pool, und die Dial-Warteschlange läuft auf
einem Raster mit Rand ohne Bereichsprüfung (25 % schneller). Die Ergebnisse sind Bit für
Bit gleich.

**Der langsamste Tag (früher 114 ms an Tag 1'281) ist Rauschen der Cloud-Maschine.** Bei
gleichem Seed wandert er zwischen den Läufen (Tag 5'861, 2'791, 7'123 …) und trifft jedes
Mal einen anderen Teil (einmal Essen mit 64 ms, sonst 0,4 ms). Die Arbeit ist aber
deterministisch und jedes Mal dieselbe.

Wie das Budget gehalten wird: Reisen sind Ereignisse, Felder werden nur bei Aussaat und
Ernte angefasst, Essen läuft für 1/30 der Haushalte pro Tag, Händler für 1/7, Fusswege
werden für 1/90 der Märkte pro Tag abgelaufen; ein Wegfeld wird nur neu gerechnet, wenn
sich eine Pfadstufe geändert hat (Dial-Warteschlange über 64 × 64 Zellen). Haushalte liegen
in Arrays nach ID statt in Hashtabellen.

## Platzhalter (nicht entschieden)

| Wert | Platzhalter | Grundlage |
|---|---|---|
| Ertrag | 5,5 : 1 auf offenem Land, bis 3 : 1 mit Land über 1500 m; gerodetes Land 3 : 1 | Spurr über Devereaux; keine Bodendaten auf dem 25-km-Raster |
| Rodbares Land | heutiges Acker- und Siedlungsland (WorldCover) unter 16 % Hang, abzüglich HYDE-Acker; 0,5 ha pro Erwachsenem und Jahr | Daten: ESA WorldCover 2021 (CC BY 4.0), Copernicus DEM GLO-90; Auswahl der Gruppen und die Hanggrenze (FAO GAEZ) liegen bei Ramon |
| Hang | aus dem DEM-Überblick mit ≈ 370 m Abstand; unterschätzt kurze steile Hänge | Copernicus DEM GLO-90 |
| Arbeit in Aussaat / Ernte | 25 % / 30 % der 70 Tage pro ha, je in 40 Tagen; in den Spitzen arbeiten alle von 10–65 | GRAIN-NUMBERS: „Verteilung offen“ |
| Wer arbeitet | übers Jahr Erwachsene 15–60 | frei gewählt |
| Taglohn | 3 kg Getreide | Preisedikt VII.1a, 25 Denar mit Kost |
| Grundpreis | 8,75 Denar/kg | Preisedikt, modius castrensis 1,5–2 modii italici |
| Staatslohn für alle ausser Bauern und Händlern | 25 Denar pro Arbeitstag | S76 (Staat hat unbegrenzt Geld), Preisedikt |
| Steuer | 10 % der Ernte, verlässt vorerst das System | S70 offen; sizilischer Zehnt. **Hinweis:** Italien zahlte bis Diokletian keine Grundsteuer. |
| Pacht | ein Drittel der Ernte, bei Verkauf an den Grundherrn | S69 offen |
| Grundherr eines Pacht- oder Gutshofs | ein Senator oder Ritter per Zufall | S69 offen |
| Brache | Zweifelderwirtschaft: 50 % der Felder unter Getreide; Brache braucht keine Arbeit | GRAIN-NUMBERS 2; Pflügen der Brache nicht belegt |
| Steuer und Pacht mit Saatgut | auf die Ernte abzüglich der Saat | frei gewählt |
| Vorrat und Kauf | Höfe behalten Nahrung bis zur nächsten Ernte plus 60 Tage; andere kaufen unter 30 Tagen bis 60 Tage | frei gewählt |
| Esel pro Hof | jeder Familien- und Pachthof hat einen | GRAIN-NUMBERS-Vorschlag |
| Markt | Preis läuft 1/30 pro Tag auf Grundpreis × 90 Tage / Lagerreichweite (0,25–8-fach), Spanne ±10 %, Händlerbargeld zum Start für 60 Tage | frei gewählt, EU5-ähnlich |
| Händler | Marge über 10 %, Last 388 kg, Startgeld 5'000 Denar, Leerfahrt halbe Fracht | frei gewählt |
| Nachrichten | Preise anderer Märkte kommen mit der Reisezeit verspätet an | frei gewählt |
| Landlose | Almosen 30 % des Bedarfs vom Markt, Diebstahl mit 5/16 pro Monat (40 kg); zuerst eingestellt | S69 offen |
| Not (S66) | weniger als 80 % gegessen | frei gewählt |
| Handelswege | Halbwertszeit 2 Jahre, Handelsweg ab 100, Strasse ab 400 Fahrten im Jahr (zurück unter 50 / 200), Wagenfracht 80 % / 65 %; Seewege ohne Wirkung | Werte frei, wie Fusswege |
| Felder auf Kacheln | Umkreis 8 Kacheln um den Hofplatz; Hofplatz im Dorf des Haushalts (`settle.rs`: ein Dorf je 25 Menschen auf den Kacheln mit dem meisten flachen Ackerland, Platzhalter dort); was die 25-km-Daten mehr Land haben als die Kacheln fassen, liegt über (wenige Zellen) | Echte Feldgrösse (S51) auf einer Karte mit Wegen 1 : 23,8 (S50) hat keine natürliche Grenze für den Weg zum Feld |
| Fusswege | Halbwertszeit 360 Tage, Pfad ab ≈ 140, Weg ab ≈ 700 Gängen im Jahr, Kosten 80 % / 65 %; Ablauf alle 90 Tage | Helbing 1997, Werte frei |
| Startvorräte | Höfe bis zur Ernte + 60 Tage, Märkte 240 Tage ihrer Käufer, Haushalte 1 Monat, Zelte 3 Monate | damit der Start im Januar kein Artefakt ist |
| Erntetag | Mitte Juni bei Rom, 2 Tage später pro 100 km Nord, ± 7 Tage pro Hof; Aussaat Ende Oktober | frei gewählt |

## Nicht gebaut

- **Missernten, Verderb** (S72: vorerst keine Missernten).
- **Neue Höfe und Strassen durch den Spieler** (S69, S74): Landlose können nur frei
  gewordene Höfe übernehmen.
- **Neue Märkte, Verödung, Elendsviertel** (S75): Es gibt genau einen Markt pro Region.
- **Häfen und Flüsse**: Seewege werden gezählt, machen die Fahrt aber nicht billiger.
  Flüsse fehlen im Marktgraph.
- **Felder einzeichnen, Land sperren** (S73): Es gibt noch keinen Spieler. Hofplätze liegen
  jetzt in den Dörfern aus `settle.rs`, denselben, die die Punkte-Ansicht zeigt.

## Was auffällt und zu klären ist

- **Haushalte aus nur Kindern oder Alten** ziehen jetzt zu Verwandten oder gehen ins Zelt
  (S79). Was mit dem Vorrat eines Haushalts geschieht, der dabei leer wird, ist offen: Er
  verschwindet mit dem Haushalt. Der Hofspeicher bleibt beim Hof.
- **Arbeitslose Landlose.** Arbeit gibt es fast nur in Aussaat und Ernte, darum hungern
  die Zelte und verschwinden in 30 Jahren fast ganz. Ob das so gewollt ist, hängt an
  S69 (Arbeit, Betteln, Stehlen) und S74 (der Spieler baut Höfe).
- **Mit Brache bremst das Land** (0,16 % im Jahr über 100 Jahre). Wie stark, hängt am
  rodbaren Land und an der Brache; beides sind Platzhalter.
