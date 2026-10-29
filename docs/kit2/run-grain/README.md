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
| **Ernte und Saisonarbeit** | Aussaat und Ernte sind Ereignisse pro Hof (Erntetag nach Breite, Höhe und Hof gestreut). Was die Familie im Fenster nicht schafft, sucht der Hof an der wöchentlichen Arbeitsbörse der Region: zuerst Leute aus den Zelten, dann Höfe mit freien Händen. Lohn in Getreide. Fehlen Hände, bleibt ein Teil der Ernte auf dem Feld oder ein Teil des Feldes ungesät. Danach stellt jeder Hof, der mehr im Speicher hat als Nahrung bis zur nächsten Ernte, Reserve und Saatgut, mit diesem Überschuss Tagelöhner an, jede Woche. Ein Hof bietet die Arbeitstage seiner Erwachsenen an, die seine eigenen Felder nicht brauchen; wer kaum Land hat, arbeitet fast ganz für andere. Wer hungert, arbeitet weniger (S84 b). | S72, S84 |
| **Saatgut und Brache** | Jeder Hof legt nach der Ernte das Saatgut fürs nächste Jahr zurück (130 kg/ha) und sät es im Herbst aus dem Hofspeicher; fehlt es, bleibt Feld ungesät. Die Ernte bringt brutto Saat mal Saatverhältnis. Zweifelderwirtschaft: Jedes Jahr liegt die Hälfte der Felder brach, ein Hof braucht also doppelt so viel Land. | S76 |
| **Speicher** | Getreide liegt im Hofspeicher, im Vorrat jedes Haushalts und im Lager jedes Markts, in ganzen kg. Steuer geht beim Ernten ab. Verderb: 4 % im Jahr, jeden Monat ein Zwölftel davon, in jedem Speicher. | S72 |
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

## Erbe (S83, 100 Jahre, Seed 1, `run100-inherit-equal.txt`, `-now`, `-one`)

Stirbt der Vater, gründen die verheirateten Söhne eigene Haushalte (S81). Wer den Hof
bekommt, war offen; drei Regeln im Vergleich (`grain --inherit equal|now|one`):

- **equal** (Standard, S83): Felder, gesäte Fläche und Vorrat zu gleichen Teilen an alten
  Haushalt und Söhne; die Felder bleiben auf ihren Kacheln (römisches Erbrecht ohne Testament).
- **now**: der Hof bleibt beim alten Haushalt, die Söhne beginnen ohne Land (Tagelöhner).
- **one**: der älteste verheiratete Sohn bleibt mit Mutter und Ledigen auf dem Hof, die
  anderen beginnen ohne Land.

| Jahr 100 | now | equal | one |
|---|---|---|---|
| Menschen (Wachstum) | 110'089 (−0,02 %) | 122'646 (+0,13 %) | 133'823 (+0,46 %) |
| Zelte: Haushalte / Menschen | 1'064 / 3'850 | 153 / 420 | 374 / 1'656 |
| Höfe; Fläche p10 / Median / p90 ha | 10'284; 4,0 / 11,4 / 32,9 | 15'007; 1,9 / 6,5 / 22,0 | 9'399; 4,9 / 14,4 / 37,7 |
| Höfe, die ihren Haushalt nicht ernähren | 9,6 % | 21,7 % | 13,2 % |
| Ernte t | 39'446 | 35'265 | 41'858 |
| Hungertote / Abgewanderte pro Jahr | 265 / 672 | 317 / 810 | 419 / 412 |
| Grain ms pro Tag (Mittel) | 1,78 | 1,86 | 1,66 |

Gleiche Teile beenden fast alle Landlosigkeit, zersplittern aber die Höfe: jeder fünfte
ernährt seine Familie nicht mehr, die Ernte sinkt. Ein Erbe hält die Höfe gross und die
Bevölkerung wächst weiter, dafür mehr Hungertote unter den landlosen Brüdern. Ohne Teilung der
Haushalte (vor S81) waren es 136'500. Fingerprint gleich mit 1 und 4 Threads (30 Jahre).

## Gesundheit als Körpergewicht (S84, 100 Jahre, Seed 1, `run100-s84.txt`; vorher: `run100-inherit-equal.txt`)

Hunger senkt das Gewicht nach Hall et al. 2011, das Sterberisiko folgt dem BMI, die
Fruchtbarkeit dem Essensanteil (`sim/src/body.rs`). Beide Läufe mit Erbe zu gleichen Teilen
(S83); S84 zusätzlich mit IQ-Partnerwahl (S82):

| Jahr | Menschen vorher → S84 | Hungertote vorher → S84 | Abgewandert vorher → S84 |
|---|---|---|---|
| 2 | 113'853 → 100'114 | 1'597 → 15'466 | 1'358 → 503 |
| 5 | 105'558 → 92'825 | 847 → 1'240 | 2'279 → 107 |
| 50 | 109'073 → 99'754 | 233 → 348 | 394 → 56 |
| 100 | 122'646 → 107'903 | 317 → 743 | 810 → 204 |

**Hungersnot zu Beginn:** In den ersten zwei Jahren essen die Zelte 40–53 % ihres Bedarfs.
Bei so wenig Essen sinkt das Gewicht nach Hall innert gut eines Jahres gegen die Grenze des
Überlebens. Früher wanderten diese Menschen ab, jetzt sterben sie vorher (Jahr 2: 15'466
Hungertote, −12 %). Ohne Getreidewirtschaft ändert S84 fast nichts (Jahr 100: 152'384 statt
152'465), weil wer genug isst die Sterbetafel behält. Fingerprint gleich mit 1 und 4 Threads.
Grain im Mittel 1,44 ms pro Tag.

## Hungersnot zu Beginn behoben (S84 a und b, 100 Jahre, Seed 1, `run100-s84-work.txt`; vorher: `run100-s84.txt`)

Ramon: „mach a und b“, dann Arbeit aus dem Überschuss. Die Hungersnot kam nicht von zu wenig
Getreide: Die Höfe horteten jedes Jahr rund 13'000 t mehr, weil die Händler nicht genug
Bargeld hatten, um den Überschuss zu kaufen. Gehungert haben die Zelte und etwa 3'500 Höfe mit
kaum Land (im Mittel 0,24 ha pro Kopf; mit Brache braucht ein Mensch etwa 1,2 ha). Sie
hatten kein Geld und nur in Aussaat und Ernte Arbeit. Historisch arbeiteten solche
Kleinbauern als Tagelöhner auf den Gütern (Erdkamp 2005, Cato, Varro).

- **(a) Startvorräte:** Ein Hof startet mit dem, was die letzte Ernte nach den Regeln eines
  normalen Jahrs übrig lässt: Ernte seiner Felder minus Steuer und Pacht, minus Essen seit der
  Ernte und Herbstsaat. Den Überschuss hat er nicht verkauft (den Händlern fehlt das Geld),
  er liegt im Speicher. Mindestens hat jeder Hof Nahrung bis zur Ernte plus 60 Tage.
- **(b) Weniger Arbeit bei Hunger:** Die Hände in Aussaat und Ernte, die Arbeit übers Jahr,
  die Rodung und die angebotenen Taglohntage folgen `body::work_factor` des gegessenen Anteils
  (1 satt, 0,6 bei PAL 1,45).
- **Arbeit aus dem Überschuss:** Jede Woche stellt jeder Hof mit Überschuss Tagelöhner an,
  zuerst aus den Zelten, dann Bauern mit freier Zeit, 3 kg Getreide pro Tag.
- **Freie Zeit eines Hofs:** die Arbeitstage seiner Erwachsenen (290 im Jahr) minus die
  Arbeit seiner eigenen Felder ausserhalb der Spitzen. Das ersetzt den Platzhalter 30 %; für
  einen voll bestellten Hof kommt etwa dasselbe heraus.

| Jahr | Menschen vorher → jetzt | Hungertote vorher → jetzt | Abgewandert vorher → jetzt |
|---|---|---|---|
| 1 | 113'661 → 115'003 | 1'644 → 337 | 367 → 64 |
| 2 | 100'114 → 113'393 | 15'466 → 4'168 | 503 → 129 |
| 5 | 92'825 → 112'424 | 1'240 → 681 | 107 → 96 |
| 50 | 99'754 → 143'382 | 348 → 446 | 56 → 78 |
| 100 | 107'903 → 181'410 | 743 → 906 | 204 → 932 |

Die Zelte essen ab Jahr 3 über 90 % ihres Bedarfs (vorher 58–88 %). **Wachstum:** 0,44 % im
Jahr über 100 Jahre, historisch etwa 0,1 %. Im Jahr 100 ist das Land knapp: 42,7 % der Höfe
sind zu klein für ihren Haushalt, Hungertote und Abwanderung steigen wieder. Taglohn wird viel
bezahlt (14 Mio. Tage im Jahr 100). Die Arbeit selbst bringt noch nichts hervor
(Platzhalter). Fingerprint gleich mit 1 und 4 Threads (10 Jahre).

## Ehe nach dem Zensus (S86, 100 Jahre, Seed 1, `run100-s86.txt`; vorher: `run100-s84-work.txt`)

Ramon: „Alle drei belegten Wege“. 20 % der Frauen heiraten nie, 10 % der Ehen enden pro
Jahr durch Scheidung (nach S87 auf 7 % nachgestellt, siehe unten), Frauen werden nur bis 35 gesucht (alles PLACEHOLDER, auf die
Gesamtzahlen des Zensus eingestellt; siehe run-people).

| Jahr | Menschen vorher → jetzt | Geburten pro 1'000 | Hungertote vorher → jetzt | Frauen 15–49 verheiratet |
|---|---|---|---|---|
| 2 | 113'393 → 111'030 | 46 | 4'168 → 3'508 | 55 % |
| 10 | 115'265 → 106'130 | 45 | 284 → 213 | 62 % |
| 50 | 143'382 → 104'090 | 46 | 446 → 137 | 65 % |
| 100 | 181'410 → 110'673 | 47 | 906 → 125 | 65 % |

Von Jahr 10 bis 100 wächst die Bevölkerung um 0,05 % im Jahr (Ziel 0,1–0,2 %), gegen
Ende schneller (0,37 % im Jahr 100). Die Hungersnot der ersten zwei Jahre (S84 a) drückt
den Start von 116'805 auf 106'000. Fingerprint gleich mit 1 und 4 Threads (10 Jahre).
Tempo auf einer ruhigen Maschine (100 Jahre): Grain im Mittel 1,28 ms pro Tag, 99 % 4,0 ms;
ganzer Tag Median 4,7 ms, 99 % 9,5 ms. (`run100-s86.txt` selbst lief neben einem zweiten
Lauf und zeigt darum 1,75 ms.)

## Hungersnot zu Beginn: Nil 10 : 1 und Lohnarbeit statt Hof (S87, 100 Jahre, Seed 1, `run100-s87.txt`; vorher: `run100-s86.txt`)

Ramon: „okay fixe ägypten. lohnarbeit statt hof macht sinn“. Gefunden: Die Hungernden
lebten in Zellen, deren Ackerland nicht für ihre Bauern reicht (Niltal und Delta, Küste
Phöniziens, Attika, Umland Roms und Neapels), und auch die Nachbarzellen bis 50 km haben
dort kein Land. Getestet (10 Jahre, Hungertote im Jahr 2, vorher 3'508): Felder über die
Zellgrenze bis 12,5 km 3'334, Umsiedeln beim Start bis 50 km 3'386, hungernde Höfe bleiben
statt umzuziehen 4'016, Nil 10 : 1 allein 3'064, Lohnarbeit allein 1'970, beides 1'828.
64 % der Hungertoten im Jahr 2 waren Haushalte, die schon umgezogen waren; sie kamen aus
diesen Zellen.

- **Nil 10 : 1:** Die Felder vom Delta bis zum ersten Katarakt tragen 10 : 1 (Manning 2007:
  „normal“ in Oxyrhynchos 1 : 10; Hickey: 10–12 Artaben pro Arure bei 1 Artabe Saat).
  Getreide weiter auf der Hälfte der Felder.
- **Lohnarbeit statt Hof:** Beim Start behalten in jeder Zelle die Bauernhaushalte (kleinste
  ID zuerst) einen Hof, solange das Ackerland der Zelle sie ernährt; die übrigen 3'641
  Haushalte werden Handwerker mit Staatslohn (S76) und kaufen am Markt.
- Die Scheidungsrate von S86 ist danach von 10 % auf 7 % im Jahr nachgestellt, damit das
  Wachstum wieder bei 0,1 % liegt.

| Jahr | Menschen S86 → S87 | Hungertote S86 → S87 | Geburten / Tote pro 1'000 | Frauen 15–49 verheiratet |
|---|---|---|---|---|
| 2 | 111'030 → 112'828 | 3'508 → 1'888 | 47 / 58 | 55 % |
| 3 | 108'298 → 111'339 | 2'771 → 1'588 | 44 / 57 | 56 % |
| 10 | 106'130 → 109'524 | 213 → 254 | 46 / 46 | 63 % |
| 50 | 104'090 → 107'740 | 137 → 231 | 47 / 44 | 67 % |
| 100 | 110'673 → 117'906 | 125 → 210 | 47 / 45 | 67 % |

Von Jahr 10 bis 100 wächst die Bevölkerung um 0,08 % im Jahr. Die Hungertoten in Jahr 2 und
3 sind vor allem Tagelöhner in Zelten ohne Geld und Höfe in knappen Zellen. Fingerprint
gleich mit 1 und 4 Threads (10 Jahre). Tempo auf einer ruhigen Maschine: Grain im Mittel
1,24 ms pro Tag (99 % 3,9 ms), ganzer Tag Median 4,6 ms, 99 % 9,5 ms, 433 MB. **Offen (Ramon: später):** Der Lohn kommt vom Staat
mit unbegrenztem Geld; historisch verdienten diese Leute an Handwerk, Wein, Öl und Gärten.

## Verderb im Lager (S72, 100 Jahre, Seed 1, `run100-verderb.txt`; vorher: `run100-s87.txt`)

Ramon: „Verderb ja“. Gelagertes Getreide verliert 4 % im Jahr: im Hofspeicher, im Vorrat der
Haushalte und im Marktlager, jeden Monat ein Zwölftel davon. Die Zahl ist der Lagerverlust von
Weizen im bäuerlichen Lager (APHLIS 2011, nach Stathers für die FAO; FAO y4011e: bis 4 %).
Antike Quellen sagen nur, dass Weizen in trockenen, gelüfteten Speichern oder Erdgruben jahrelang
hielt (Varro RR 1.57, Columella 1.6.9–17), nennen aber keine Rate.

| Jahr | Menschen vorher → jetzt | Hungertote vorher → jetzt | Verderb t |
|---|---|---|---|
| 2 | 112'828 → 112'817 | 1'888 → 1'930 | 1'684 |
| 50 | 107'740 → 106'429 | 231 → 226 | 9'797 |
| 100 | 117'906 → 110'617 | 210 → 343 | 7'391 |

Die Höfe horten weniger, darum zahlen sie weniger Taglohn aus dem Überschuss. Die Bevölkerung
bleibt fast gleich (−0,05 % im Jahr über 100 Jahre, historisch etwa +0,1 %). Fingerprint gleich
mit 1 und 4 Threads (10 Jahre). Grain im Mittel 1,41 ms pro Tag (99 % 4,1 ms), ganzer Tag
99 % 9,9 ms.

## Hungertote aus der Sterbetafel (S89, 100 Jahre, Seed 1, `run100-s89.txt`; vorher: `run100-verderb.txt`)

Ramon: „Hungertote aus der Sterbetafel nehmen“. Die Sterbetafel (West 3) enthält die
Hungertoten schon; die Simulation lässt zusätzlich verhungern, darum sinkt die
Sterblichkeit der Tafel um 5 % (PLACEHOLDER, Anteil der Hungertoten in normalen Jahren).
Probeläufe mit 3 %, 5 % und 7 % gaben 0,09 %, 0,17 % und 0,21 % Wachstum im Jahr.

| Grösse | vorher (Verderb) | jetzt | Quellen |
|---|---|---|---|
| Menschen im Jahr 100 | 110'617 | 129'207 | – |
| Wachstum Jahr 10 bis 100 | 0,01 % im Jahr | 0,17 % im Jahr | 0,1–0,2 % (Frier 2000, Scheidel 2007, Harper 2017) |
| Geburten pro 1'000 (Jahr 100) | 47,8 | 47,0 | etwa 45 (Bagnall und Frier 1994) |
| Tote pro 1'000 (Jahr 100) | 47,2 | 43,6 | – |
| Frauen 15–49 verheiratet | 66,6 % | 67,1 % | etwa 65 % |
| Hungertote Jahr 2 / Jahr 100 | 1'930 / 343 | 1'919 / 368 | – |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 6dc338f1747decce,
grain b1841fc00f4cd0a3), 53 Tests grün. Tempo auf dem ruhigen Rechner wie vorher:
Getreide im Mittel 1,57 ms pro Tag (p99 3,9), ganzer Tag p50 4,8 ms, p99 9,0 ms.

## Fehler behoben: Wanderung zählt die Ankommenden (S66, 100 Jahre, Seed 1, `run100-migration-fix.txt`; vorher: `run100-s89.txt`)

S66 sagt: besser ist eine Region mit mehr Nahrung pro Kopf *nach* dem Umzug. Mit der
Getreidewirtschaft verglich die Wanderung aber die Nahrung pro Kopf vor dem Umzug und
zählte weder den eigenen Haushalt noch die anderen, die im selben Durchgang dorthin
ziehen. Fast leere Regionen (kleine Inseln, Wüstenränder) sahen darum reich aus, und alle
Hungernden der Umgebung zogen gleichzeitig hin. Jetzt zählen beide mit.

| Grösse | vorher | jetzt |
|---|---|---|
| Hungertote Jahr 2 | 1'919 | 1'820 |
| Hungertote pro Jahr, Jahr 11 bis 100 | 314 | 285 |
| Menschen im Jahr 100 | 129'207 | 129'583 |
| Wachstum Jahr 10 bis 100 | 0,17 % | 0,18 % |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 0e18f2cf1303bdcd,
grain 2618ab53b25545a4), 53 Tests grün.

## Ägyptens Ackerland nach Butzer (S90, 100 Jahre, Seed 1, `run100-s90.txt`; vorher: `run100-migration-fix.txt`)

Ramon: „Butzer: 27'300 km²“. HYDE 3.3 gab dem Niltal und dem Delta 3'900 km² Acker für
4,5 Mio. Menschen; jetzt sind es Butzers 27'300 km² (1976, Tabelle 4), verteilt auf das
heutige Ackerland der Nilzellen (Anteil 0,79), 10 : 1, ohne zusätzliche Rodung.

| Grösse | vorher | jetzt |
|---|---|---|
| Hungertote Jahr 2 | 1'820 | 1'068 |
| davon in Ägypten (Probelauf) | 678 | 18 |
| Hungertote pro Jahr, Jahr 11 bis 100 | 285 | 228 |
| Menschen im Jahr 100 | 129'583 | 138'384 |
| Wachstum Jahr 10 bis 100 | 0,18 % | 0,21 % |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 619df6385640848d,
grain 858ecccb8e7678ba), 53 Tests grün. Der Anteil der Hungertoten an allen Todesfällen
liegt jetzt bei 4,3 % statt bei den 5 %, die S89 von der Sterbetafel abzieht.

## Zelte suchen den Ort mit den besten Chancen (S75, 100 Jahre, Seed 1, `run100-s75-tents.txt`; vorher: `run100-s90.txt`)

S75 (Ramon, 27.10.2026) war entschieden, aber nicht gebaut: Ein Zelt zog nur um, wenn in
seiner Region ein Hof frei wurde, oder einmal im Jahr bei der Wanderung (S66, erst unter
80 % gegessen). Jetzt vergleicht jeder Zelthaushalt, der nicht satt wurde, einmal im Monat
seinen Markt mit den Märkten bis 5 Reisetage weit: Was bekäme eine Person dort im Monat
aus Taglohn (bezahlte Löhne und liegengebliebene Arbeit des letzten Monats) und Almosen
aus dem Marktvorrat, geteilt durch die Zeltleute dort und die Neuen? Bietet ein Ort
mindestens das 1,5-Fache, zieht der Haushalt hin (sofort). Zur Erntezeit ziehen Zelte so
zu den Höfen, die Hände brauchen.

| Grösse | vorher | jetzt |
|---|---|---|
| Hungertote Jahr 2 / Jahr 3 | 1'068 / 644 | 671 / 448 |
| Zelte essen (Jahr 1 / 2) | 91 % / 90 % | 96 % / 98 % |
| Umzüge von Zelten (Jahr 1 / 2 / 6) | – | 736 / 298 / 64 |
| Hungertote pro Jahr, Jahr 11 bis 100 | 228 | 223 |
| Menschen im Jahr 100 | 138'384 | 139'419 |
| Wachstum Jahr 10 bis 100 | 0,21 % | 0,21 % |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 5e2e78adb0f54db3,
grain 9f839fc3b75fef97), 53 Tests grün. Tempo gleich wie ohne (auf demselben Rechner
gemessen: Getreide im Mittel 1,79 statt 1,76 ms pro Tag).

## Fehler behoben: Einkaufen, bis der Vorrat reicht (100 Jahre, Seed 1, `run100-buy-again.txt`; vorher: `run100-s75-tents.txt`)

Ein Haushalt ohne Hof kauft, wenn sein Vorrat unter 30 Tage fällt, für bis zu 60 Tage ein,
trägt aber nur 30 kg pro Erwachsenen. Bei vielen Kindern reichte das nicht für einen Monat,
und der nächste Einkauf kam erst einen Monat später. Jetzt geht er gleich nochmals, solange
er unter 30 Tagen bleibt, wie ein Hof, der noch mehr zu verkaufen hat.

| Grösse | vorher | jetzt |
|---|---|---|
| Hungertote Jahr 2 / Jahr 3 | 671 / 448 | 590 / 376 |
| Hungertote pro Jahr, Jahr 11 bis 100 | 223 | 254 |
| Menschen im Jahr 100 | 139'419 | 142'911 |
| Wachstum Jahr 10 bis 100 | 0,21 % | 0,24 % |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 0df6a9cf176aaeb1,
grain 4c87aa8d380d9cd3), 53 Tests grün. Mehr Menschen im Jahr 100 heisst mehr Hungertote
dann, wenn das Land voll wird.

## Platzhalter nachgestimmt: 22 % Ledige, 3,5 % Hungertote in der Tafel (S86, S89, 100 Jahre, Seed 1, `run100-retune.txt`; vorher: `run100-buy-again.txt`)

Nach S90, S75 für die Zelte und dem Einkauf-Fix wuchs die Bevölkerung um 0,24 % im Jahr,
über dem Ziel von S86 (0,1–0,2 %), und die Hungertote machten noch 3,4–3,7 % aller
Todesfälle aus statt 5 %. Beide Platzhalter sind so definiert, dass sie diesen Zahlen
folgen; neu nachgestimmt nach je zwei 100-Jahre-Läufen (200, 220 und 240 ‰ Ledige, mit
5 % und 3,7 % Hungeranteil). Keine neue Regel.

| Grösse | vorher | jetzt |
|---|---|---|
| Frauen, die nie heiraten | 20 % | 22 % |
| Hungertote in der Sterbetafel | 5 % | 3,5 % |
| Geburten pro 1'000, Jahr 11 bis 100 | 46,2 | 45,3 |
| Todesfälle pro 1'000 | 43,0 | 43,1 |
| Hungertote pro Jahr / Anteil an allen Toten | 254 / 4,6 % | 190 / 3,6 % |
| Hungertote Jahr 2 / Jahr 3 | 590 / 376 | 588 / 386 |
| Verheiratete Frauen 15–49 im Jahr 100 | 67 % | 66 % |
| Menschen im Jahr 100 | 142'911 | 129'799 |
| **Wachstum Jahr 10 bis 100** | **0,24 %** | **0,14 %** |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people d92e779e135480e4,
grain 4802e747a932ce6f), 53 Tests grün. Getreide pro Tag im Mittel 2,1 ms auf der
heute langsameren Cloud-Maschine (vorher 2,0 ms im selben Zustand).

**Händler geprüft.** Die Preise reichen bis zur Obergrenze (das 8-Fache), aber das sind
fast leere Märkte am Kartenrand (Schottland, Nordrussland) mit 0–30 Menschen, die kein
Händler auf seiner Liste hat. Im Jahr 10 hungern im ganzen Reich nur 56 Lohnhaushalte,
davon 5 an solchen Märkten. Die Händler sind also nicht der Grund für die übrigen
Hungertoten.

## Wüste versorgt sich selbst, Landlose roden nach der Lex Manciana (S91, S92, 100 Jahre, Seed 1, `run100-s91-s92.txt`; vorher: `run100-retune.txt`)

**S91.** Haushalte, die in einer Wüstenzelle entstehen (kein Feld- und kein Rodland, mehr als
die Hälfte der Landfläche kahl), essen ausserhalb der Getreidewirtschaft und sind satt. Das
sind beim Start etwa 190 Personen in den Sahara-Oasen, der Syrischen Wüste und an den
Wüstenrändern des Nils. Zellen ohne Land, die nicht kahl sind (Galicien, Alpen, Westirland,
Nordanatolien, etwa 50'000 echte Menschen), gehören nicht dazu; dort kaufen die Menschen am
Markt wie bisher.

**S92.** Zeltleute mit Erwachsenen roden freies Land ihrer Zelle, sonst der Zelle ihrer
Region mit dem meisten freien Land, und werden Pachthof des Staates: ein Drittel der Ernte
nach der Saat, keine Steuer. Wer zwei Jahre nichts sät, verliert das Land. Beim Start ist das
Gesetz schon lange in Kraft: 2'003 Zelthaushalte haben dann Felder, gesät wie die anderen
Höfe, mit Vorrat bis zur Ernte. Die Startvorräte der Märkte werden vorher gerechnet (die
Landlosen zählen als Käufer); sonst haben die Märkte 20 % weniger und im Jahr 2 verhungern 709
statt 588. Danach entstehen etwa 100 Höfe im Jahr, gegen Ende 15; 320 fallen in 100 Jahren
zurück.

| Grösse | vorher | jetzt |
|---|---|---|
| Zelthaushalte beim Start / Jahr 10 / Jahr 100 | 2'878 / 4'203 / – | 875 / 2'586 / 466 |
| Hungertote Jahr 2 / Jahr 3 | 588 / 386 | 567 / 405 |
| Hungertote pro Jahr, Jahr 11 bis 100 / Anteil | 190 / 3,6 % | 189 / 3,6 % |
| Ernte Jahr 2 | 43'955 t | 45'594 t |
| Menschen im Jahr 100 | 129'799 | 127'386 |
| Wachstum Jahr 10 bis 100 | 0,14 % | 0,12 % |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 7ed8f3b44270d75d, grain
a1af7e4043e81953), 54 Tests grün. Getreide pro Tag im Mittel 2,3 ms (vorher 2,1 ms; 10 %
mehr Höfe).

**Auffällig:** Die Wüstenhaushalte schrumpfen von 186 auf 67 Personen. Sie hungern nicht,
heiraten aber nicht, weil ihre Region kein freies Land hat (S65). Ramon: so lassen, bis
andere Nahrung (Datteln, Gärten, Herden) gebaut ist.

## Lohnhaushalte suchen jeden Monat einen besseren Markt (S93, 100 Jahre, Seed 1, `run100-s93.txt`; vorher: `run100-s91-s92.txt`)

Die erste Fassung von S93 liess alle Haushalte in Not jeden Monat die Regionen rundum nach
Getreide pro Kopf vergleichen, Vorräte plus freies Land. Im 10-Jahre-Lauf stieg die Zahl
der Hungertoten auf 250–320 im Jahr (statt 120–150): Wer zieht, kommt landlos an, das freie
Land nützt ihm nichts, und viele ziehen gleichzeitig. Darum blieb sie aus.

Jetzt prüfen monatlich nur die Lohnhaushalte, die ihr Essen am Markt kaufen. Sie
vergleichen das Getreide im Lager des eigenen Markts pro Käufer mit dem der Märkte rundum,
zählen alle mit, die im selben Monat schon dorthin ziehen, und ziehen ab dem 1,5-Fachen
(wie die Zelte, S75) in die Marktzelle. Die Karte verlassen sie nur bei der jährlichen
Prüfung (S66). Zelte suchen weiter monatlich nach Arbeit und Almosen (S75), Bauern prüfen
einmal im Jahr. Etwa 1'100 Menschen im Jahr ziehen so monatlich um (im ersten Jahr 10'000,
gegen Ende wieder mehr, weil das Land knapp wird), 400–500 jährlich.

Weil weniger verhungern, ist der Anteil der Hungertoten in der Sterbetafel (S89) von 3,5 %
auf 2,9 % nachgestellt, den Anteil dieses Laufs.

| Grösse | vorher | jetzt |
|---|---|---|
| Hungertote Jahr 2 / Jahr 3 | 567 / 405 | 387 / 265 |
| Hungertote pro Jahr, Jahr 11 bis 100 / Anteil | 189 / 3,6 % | 151 / 2,9 % |
| Verlassen die Karte, Jahr 11 bis 100, pro Jahr | 87 | 54 |
| Geburten / Todesfälle pro 1'000, Jahr 11 bis 100 | 45,2 / 43,2 | 45,0 / 43,0 |
| Menschen im Jahr 10 / Jahr 100 | 114'198 / 127'386 | 114'480 / 131'781 |
| Wachstum Jahr 10 bis 100 | 0,12 % | 0,16 % |

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 78eeb63edba0467e, grain
d2967522adc83ce9), 54 Tests grün. Ohne Getreidewirtschaft (`people`) ändert sich nichts.

## Geldkreislauf und Staatskasse (S94 Schritt 1, nur Buchung, 10 Jahre, Seed 1)

Jeder Denar, der entsteht oder verschwindet, ist jetzt gebucht (`Money` und `Treasury` in
`grain.rs`). Das Verhalten ist unverändert: gleicher Fingerabdruck wie S93. Gesucht wurden
alle Stellen, an denen sich Geld ändert. Fast alle sind Zahlungen von einem an einen
anderen (Verkauf, Kauf, Pacht, Händler). Übrig bleiben diese Quellen und Senken:

| Posten | Art | Herkunft im Code |
|---|---|---|
| Geld am Anfang | Quelle | Startgeld der Händler und Senatoren/Ritter, Bargeld der Marktleute, Pacht der letzten Ernte (Platzhalter) |
| Staatslohn | Quelle | S76: 25 Denar pro Arbeitstag an alle ausser Bauern; zuerst aus der Kasse, der Rest ist neu geprägt |
| Startgeld neuer Haushalte | Quelle | Händler- und Senatorenhaushalte, die nach dem Start entstehen, bekommen das Startgeld |
| Fracht | Senke | Händler zahlen die Fracht; niemand in der Simulation bekommt sie |
| Geld aufgelöster Haushalte | Senke | ausgestorben oder zu Verwandten gezogen (S79): das Geld verschwindet mit dem Haushalt |
| Ohne Empfänger | Senke | Pacht für einen verstorbenen Grundherrn, Ladung eines unterwegs verstorbenen Händlers |

Die Staatskasse nimmt das Manciana-Drittel (S92) in Geld ein, wenn der Hof es verkauft,
und die Steuer als Korn (bleibt liegen, S76). Sie zahlt daraus den Staatslohn; was fehlt,
prägt der Staat. Jeden Tag gilt: Geld bei Haushalten, Höfen und Marktleuten plus Kasse =
Anfang + geprägt + Startgeld neuer Haushalte − Fracht − aufgelöst − ohne Empfänger. Der
Test `deterministic_fingerprint` prüft das an jedem der 200 Tage, der Lauf jedes Jahr
(Zeile `money den (S94)`). Die Tabelle `state` liefert die Posten fürs Spiel.

| Posten, Denar | Jahr 1 | Jahr 10 (Summe seit Start) |
|---|---|---|
| Geld am Anfang | 84,8 Mio. | 84,8 Mio. |
| Staatslohn | 137,7 Mio. | 1'343 Mio. |
| davon neu geprägt | 133,7 Mio. | 1'329 Mio. |
| Manciana-Pacht in die Kasse | 4,0 Mio. | 13,9 Mio. |
| Startgeld neuer Haushalte | 0,1 Mio. | 23,3 Mio. |
| Fracht | 23,1 Mio. | 122,5 Mio. |
| Geld aufgelöster Haushalte | 0,7 Mio. | 64,4 Mio. |
| Ohne Empfänger | 0,06 Mio. | 0,4 Mio. |
| Geld im Umlauf am Jahresende | 194,8 Mio. | 1'250 Mio. |
| Nicht gebucht | 0 | 0 |
| Steuerkorn | 3'248 t | 32'550 t |

Über 100 Jahre (`run100-s94-money.txt`, gleicher Fingerabdruck wie `run100-s93.txt`):
Staatslohn 12'908 Mio., davon 12'749 Mio. geprägt; Geld im Umlauf im Jahr 50 4'380 Mio.,
im Jahr 100 5'868 Mio.; mit aufgelösten Haushalten verschwunden 6'351 Mio., also die
Hälfte des geprägten Geldes; Fracht 766 Mio.; nicht gebucht 0.

Die Geldmenge wächst um gut 110 Mio. Denar im Jahr, weil der Staat jeden Monat Lohn prägt
und nichts davon als Steuer zurückholt. Auf die Preise wirkt das nicht: Der Marktpreis
hängt nur an Lager und Nachfrage. Das ist der Stand, auf dem Steuer in Geld und Sold aus
der Kasse aufbauen (S94 Schritt 1, nach Ramons Entscheid).

Gleicher Fingerabdruck mit 1 und 4 Threads über 10 Jahre (people 78eeb63edba0467e, grain
d2967522adc83ce9), 55 Tests grün.

## Fernhändler verkaufen nur gegen Bargeld (S96, 10 Jahre, Seed 1, `run10-s96-trader-cash.txt`)

Vorher bezahlten die Marktleute jede Händlerladung voll, auch aus leerer Kasse. Nach zwei
Jahren lag das Händlergeld zusammen bei -250 Mio. Denar, ein Kredit, den niemand beschlossen
hatte. Jetzt kaufen sie wie bei den Bauern nur, soweit ihr Bargeld reicht. Der Rest geht
zurück an den Heimatmarkt, und was auch dort niemand kaufen kann, kommt in die
Vorratskammer des Händlers.

| Grösse, Jahr 10 | vorher | jetzt |
|---|---|---|
| Märkte mit negativem Händlergeld (Jahr 5) | 708 | 0 |
| Fernhandel | 3'414 t | 3'256 t |
| Hungertote | 97 | 125 |
| Getreidepreis Rom | 4,37 Denar/kg | 24,17 Denar/kg |
| Menschen | 114'480 | 114'094 |

Rom bekommt weniger Einfuhr, weil seine Marktleute nicht mehr auf Pump kaufen. Gleicher
Fingerabdruck mit 1 und 4 Threads (people e96a6d3747c2f174, grain 39efd3bb9f66f013), die
Geldbilanz geht auf, 55 Tests grün.

## Was die Simulation dem Spiel liefert (S94, nur lesen, Fingerabdruck gleich)

Ramon (29.10.2026): alles zeigen, was die Simulation rechnet. Die Simulation liefert, der
Personen-Thread zeichnet (`sim/godot/src/tables.rs`, `trips.rs`).

| Was | Aufruf | Inhalt |
|---|---|---|
| Tabellen | `Grain::table(key)`, `TABLES` | Märkte, Bevölkerung, Höfe, Staat, Verlauf (eine Zeile pro Monat: Geburten, Tote, Hungertote, Umzüge, Ernte, Verkauf, Fernhandel, Almosen, Diebstahl, Anteil gegessen, Taglohn, Preise, Geld, Kasse, Zelte, Höfe, Lager) |
| Fahrten | `Grain::trips_in(box)` | Marktgänge und Händlerwagen mit Route (Pfadfeld Kachel für Kachel, Handelsroute über die 25-km-Zellen), Ladung, Tage hin und zurück |
| Erntearbeit | `Grain::work_in(box)` | wer bei der letzten Wochenbörse auf welchem Hof arbeitet: Saat, Ernte, übers Jahr, aus dem Überschuss (S84) |
| Ereignisse | `Grain::events_in(since, box)` | Hungertod, Umzug, Verlässt die Karte, Zieht zu Verwandten, Diebstahl, Almosen, Zelt zieht um, Hof übernommen, Erbteil, Ins Zelt, Hof nach Lex Manciana, Hof verlassen; 60 Tage zurück (`crate::events`) |
| Preise auf der Karte | `Grain::cell_markets()` | Region jeder 25-km-Zelle, mit der Tabelle `markets` einzufärben |
| Haushalt | `Grain::household(id)` | Art, satt, Vorrat, Geld, Hof |

Der Verlauf summiert die Zähler Tag für Tag und stimmt auch dann genau, wenn der Lauf sie
jährlich zurücksetzt (geprüft über drei Jahre: Geburten und Ernte gleich). Alles ist nur
gelesen: gleicher Fingerabdruck mit 1 und 4 Threads (grain d2967522adc83ce9, people allein
3f6cf7db2bc31a0c), gleiches Tempo.

## Tempo und Speicher (4 Cloud-Kerne, Standard mit S83, S82, S84 und Arbeit aus dem Überschuss, `run100-timing.txt`)

| Grösse | Wert |
|---|---|
| Aufbau Getreide | 0,42 s (Marktgraph mit 32 Nachbarn pro Markt, Land auf 4,9 Mio. Kacheln verteilen) |
| **Getreide pro Tag, Median / Mittel** | **0,93 ms / 1,24 ms** (Ziel Mittel ≤ 1,5 ms; ohne Arbeit aus dem Überschuss 0,66 / 0,93 bei 108'000 Menschen) |
| Getreide pro Tag, 95 % / 99 % | 3,0 ms / 4,9 ms (Ziel Spitze ≤ 5 ms) |
| Ganzer Tag mit Menschen, Median / 95 % / 99 % | 3,7 / 6,8 / 9,0 ms (Ziel 99 % ≤ 12 ms) |
| Speicher nach 100 Jahren | 465 MB bei 181'000 Menschen |
| Determinismus | gleicher Fingerabdruck mit 1 und 4 Threads; Test `grain::tests::deterministic_fingerprint` |

Pro Tag im Mittel auf dem Hauptthread: Reisen (Ankunft, Rückkehr) 0,17 ms, Arbeitsbörse 0,33
(jede Region jede Woche, alle Höfe und Zelte), Märkte und Nachrichten 0,13, Essen und Kaufen
0,18, Händler mit Handelswegen 0,06, Fusswege 0,03 (Warten auf den Fussweg-Thread), Aussaat
und Ernte mit Kachelsuche 0,11, Haushaltszählung 0,22.

**Fusswege und Nachbarsuche auf eigenen Threads.** Die Gänge eines Tages (Wegfelder ablaufen,
neu rechnen) und die neuen Nachbarsuchen der Märkte laufen am Ende des Getreidetags auf je
einem eigenen Thread los und werden am Anfang des nächsten Getreidetags übernommen; dazwischen
liest niemand Wegfelder oder Nachbarn. Sie laufen also neben dem Tag der Menschen. Das Ergebnis
ist Bit für Bit gleich (gleicher Fingerabdruck nach 100 Jahren).

**Handelswege.** Ändert sich eine Zelle, sucht nur ein Markt neu, dessen Nachbarsuche diese
Zelle erreicht hat (die Liste der erreichten Landzellen; was die Suche nie erreicht hat, liegt
hinter ihrem Rand und kann das Ergebnis nicht ändern). Die Suche verwendet ihre Puffer über das
ganze Raster wieder.

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
| Ertrag | 5,5 : 1 auf offenem Land, bis 3 : 1 mit Land über 1500 m; gerodetes Land 3 : 1; Nil 10 : 1 (S87) | Spurr über Devereaux; keine Bodendaten auf dem 25-km-Raster; Nil: Manning 2007, Hickey |
| Nilland | Kasten 29–33,5° O, 24–31,7° N (Delta bis erster Katarakt) | S87, bis es Provinzen gibt |
| Wer beim Start den Hof behält (S87) | kleinste Haushalts-ID zuerst, die übrigen werden Handwerker | S87 |
| Rodbares Land | heutiges Acker- und Siedlungsland (WorldCover) unter 16 % Hang, abzüglich HYDE-Acker; 0,5 ha pro Erwachsenem und Jahr | Daten: ESA WorldCover 2021 (CC BY 4.0), Copernicus DEM GLO-90; Auswahl der Gruppen und die Hanggrenze (FAO GAEZ) liegen bei Ramon |
| Hang | aus dem DEM-Überblick mit ≈ 370 m Abstand; unterschätzt kurze steile Hänge | Copernicus DEM GLO-90 |
| Arbeit in Aussaat / Ernte | 25 % / 30 % der 70 Tage pro ha, je in 40 Tagen; in den Spitzen arbeiten alle von 10–65 | GRAIN-NUMBERS: „Verteilung offen“ |
| Wer arbeitet | übers Jahr Erwachsene 15–60 | frei gewählt |
| Taglohn | 3 kg Getreide | Preisedikt VII.1a, 25 Denar mit Kost |
| Grundpreis | 8,75 Denar/kg | Preisedikt, modius castrensis 1,5–2 modii italici |
| Staatslohn für alle ausser Bauern und Händlern | 25 Denar pro Arbeitstag | S76 (Staat hat unbegrenzt Geld), Preisedikt |
| Staatslohn aus der Kasse (S94) | zuerst aus dem Bargeld der Kasse, der Rest neu geprägt | S95 (leere Kasse: nachprägen); Preise folgen der Geldmenge noch nicht |
| Steuer | 10 % der Ernte, als Korn in die Staatskasse, dort ohne Nutzen (S94) | S70 offen; sizilischer Zehnt. **Hinweis:** Italien zahlte bis Diokletian keine Grundsteuer. |
| Pacht | ein Drittel der Ernte, bei Verkauf an den Grundherrn | S69 offen |
| Grundherr eines Pacht- oder Gutshofs | ein Senator oder Ritter per Zufall | S69 offen |
| Brache | Zweifelderwirtschaft: 50 % der Felder unter Getreide; Brache braucht keine Arbeit | GRAIN-NUMBERS 2; Pflügen der Brache nicht belegt |
| Steuer und Pacht mit Saatgut | auf die Ernte abzüglich der Saat | frei gewählt |
| Vorrat und Kauf | Höfe behalten Nahrung bis zur nächsten Ernte plus 60 Tage; andere kaufen unter 30 Tagen bis 60 Tage | frei gewählt |
| Esel pro Hof | jeder Familien- und Pachthof hat einen | GRAIN-NUMBERS-Vorschlag |
| Markt | Preis läuft 1/30 pro Tag auf Grundpreis × 90 Tage / Lagerreichweite (0,25–8-fach), Spanne ±10 %, Händlerbargeld zum Start für 60 Tage | frei gewählt, EU5-ähnlich |
| Händler | Marge über 10 %, Last 388 kg, Startgeld 5'000 Denar, Leerfahrt halbe Fracht; Unverkauftes in die eigene Vorratskammer (S96) | frei gewählt |
| Nachrichten | Preise anderer Märkte kommen mit der Reisezeit verspätet an | frei gewählt |
| Landlose | Almosen 30 % des Bedarfs vom Markt, Diebstahl mit 5/16 pro Monat (40 kg); zuerst eingestellt | S69 offen |
| Not (S66) | weniger als 80 % gegessen | frei gewählt |
| Handelswege | Halbwertszeit 2 Jahre, Handelsweg ab 100, Strasse ab 400 Fahrten im Jahr (zurück unter 50 / 200), Wagenfracht 80 % / 65 %; Seewege ohne Wirkung | Werte frei, wie Fusswege |
| Felder auf Kacheln | Umkreis 8 Kacheln um den Hofplatz; Hofplatz im Dorf des Haushalts (`settle.rs`: ein Dorf je 25 Menschen auf den Kacheln mit dem meisten flachen Ackerland, Platzhalter dort); was die 25-km-Daten mehr Land haben als die Kacheln fassen, liegt über (wenige Zellen) | Echte Feldgrösse (S51) auf einer Karte mit Wegen 1 : 23,8 (S50) hat keine natürliche Grenze für den Weg zum Feld |
| Fusswege | Halbwertszeit 360 Tage, Pfad ab ≈ 140, Weg ab ≈ 700 Gängen im Jahr, Kosten 80 % / 65 %; Ablauf alle 90 Tage | Helbing 1997, Werte frei |
| Startvorräte | Höfe: was die letzte Ernte übrig lässt (S84 a), mindestens bis zur Ernte + 60 Tage; Märkte 240 Tage ihrer Käufer, Haushalte 1 Monat, Zelte 3 Monate | damit der Start im Januar kein Artefakt ist |
| Verderb | 4 % im Jahr in allen Speichern, für jedes Klima gleich | APHLIS 2011 (Weizen im Hoflager), FAO |
| Wüste (S91) | kein Feld- und kein Rodland und mehr als 50 % der Landfläche kahl (ESA-Landbedeckung); wer zuzieht, gehört nicht dazu | frei gewählt |
| Lex Manciana (S92) | bei der monatlichen Zählung alle zugleich, mindestens 1 ha frei in der Zelle, nur Zellen mit Dorf; gutes Land bis zum Wunsch, dann Rodung wie S73 im ersten Jahr; beim Start gesät und mit Vorrat wie die anderen Höfe | frei gewählt; Drittel und zwei Jahre aus der Lex Manciana |
| Zelte ziehen um (S75) | einmal im Monat, wenn nicht satt; Märkte bis 5 Reisetage; ab dem 1,5-Fachen an Lohn und Almosen pro Zeltperson; Umzug sofort; Nähe zu anderen Zelten zählt nur über die geteilte Arbeit | frei gewählt |
| Hungertote in der Sterbetafel (S89) | 2,9 % aller Todesfälle, für alle Alter und Orte gleich | Anteil der Hungertoten in den Jahren 11–100 dieses Laufs (2,9 %; vor S93 3,4–3,7 %, mit dem Verderb allein 5–7 %) |
| Monatlich wandern (S93) | nur Lohnhaushalte in Not; Getreide im Marktlager pro Käufer; ab dem 1,5-Fachen des eigenen Markts; die acht Nachbarregionen; Ziel ist die Marktzelle; wer im selben Monat schon unterwegs ist, zählt mit | frei gewählt, Schwelle wie S75 |
| Arbeit aus dem Überschuss | bringt nichts hervor (Gräben, Bauten, Gärten, Rodung fehlen); Reihenfolge der Höfe nach Haushalt | S84, Erdkamp 2005 |
| Freie Zeit in den Zelten | 80 % der Woche | frei gewählt |
| Erntetag | Mitte Juni bei Rom, 2 Tage später pro 100 km Nord, ± 7 Tage pro Hof; Aussaat Ende Oktober | frei gewählt |

## Nicht gebaut

- **Missernten** (S72: vorerst keine).
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
- **Wachstum** mit Heirat nach Zensus (S86), Lohn statt Hof (S87), Verderb (S88) und
  ohne die doppelt gezählten Hungertoten (S89): 0,17 % im Jahr von Jahr 10 bis 100,
  historisch 0,1–0,2 %. Mit S91–S93 jetzt 0,16 % (`run100-s93.txt`).
- **Die Geldmenge wächst** um gut 110 Mio. Denar im Jahr (S94 Schritt 1): Staatslohn wird
  geprägt, keine Steuer in Geld holt ihn zurück. Ohne Wirkung auf die Preise. Über 100
  Jahre verschwindet die Hälfte des geprägten Geldes mit Haushalten, die aussterben oder zu
  Verwandten ziehen: Geld wird nicht vererbt und nicht mitgenommen (wie der Vorrat, S79).
- **Mit Brache bremst das Land** (0,16 % im Jahr über 100 Jahre). Wie stark, hängt am
  rodbaren Land und an der Brache; beides sind Platzhalter.
