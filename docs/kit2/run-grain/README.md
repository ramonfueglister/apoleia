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
| Mit Auswanderern fort | Senke | S97: Haushalte, die die Karte verlassen, nehmen ihr Geld mit (vor S97: jedes Geld aufgelöster Haushalte verschwand) |
| Ohne Empfänger | Senke | Pacht für einen verstorbenen Grundherrn, Ladung eines unterwegs verstorbenen Händlers (seit S102 entfallen) |

Die Staatskasse nimmt das Manciana-Drittel (S92) in Geld ein, wenn der Hof es verkauft,
seit S97 den erblosen Nachlass ausgestorbener Haushalte, und die Steuer als Korn (bleibt liegen, S76). Sie zahlt daraus den Staatslohn; was fehlt,
prägt der Staat. Jeden Tag gilt: Geld bei Haushalten, Höfen und Marktleuten plus Kasse =
Anfang + geprägt + Startgeld neuer Haushalte − Fracht − mit Auswanderern fort − ohne Empfänger
(vor S97: − aufgelöst). Der
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

## Geld aufgelöster Haushalte: mitnehmen, sonst an den Staat (S97, 10 Jahre, Seed 1, `run10-s97-estates.txt`)

Vorher verschwand das Geld eines Haushalts, der sich auflöste, über 100 Jahre die Hälfte
des geprägten Geldes. Jetzt nimmt es mit, wer zu Verwandten zieht (S79, auch über eine
Kette von Zuzügen im selben Monat), wer die Karte verlässt, nimmt es mit hinaus, und ohne
Erben fällt es an die Staatskasse (bona vacantia). Die Kasse zahlt daraus zuerst den
Staatslohn, es wird also weniger geprägt.

| Grösse, Summe Jahr 1 bis 10 | vorher (S96) | jetzt |
|---|---|---|
| Verschwunden mit aufgelösten Haushalten | 64,4 Mio. Denar | 0 |
| Erbloser Nachlass in die Kasse | 0 | 32,9 Mio. Denar |
| Mit Auswanderern fort | 0 | 1,9 Mio. Denar |
| Neu geprägt | 1'329 Mio. Denar | 1'292 Mio. Denar |
| Geld im Umlauf, Jahr 10 | 1'250 Mio. Denar | 1'280 Mio. Denar |
| Nicht gebucht | 0 | 0 |

Der Rest der früheren Senke geht an Verwandte. Gleicher Fingerabdruck mit 1 und 4 Threads
(people 1047146168fd41e0, grain dd0699dc38689749), 55 Tests grün. In der Tabelle `state` ersetzen `estates`
(erbloser Nachlass) und `left_map` die Spalte `dissolved`.

## Märkte ausserhalb der Karte (S98, 10 Jahre, Seed 1, `run10-s98-outside.txt`)

209 Märkte sind Tore nach draussen: Häfen mit Seeweg zum Kartenrand (Atlantik, Nordsee,
Rotes Meer) und Regionen, die den Rand über Land erreichen. Sie verkaufen nach draussen,
wenn sich das nach Fracht lohnt, und kaufen ein, wenn draussen billiger ist. Über Land
lohnt es sich praktisch nie (500 km Wagen kosten 17,5 Denar/kg), über See fast immer.

| Grösse | Jahr 1 | Jahr 5 | Jahr 10 |
|---|---|---|---|
| Ausfuhr nach draussen | 336 t | 218 t | 215 t |
| Einfuhr von draussen | 9 t | 20 t | 13 t |
| Hoflager | 46'066 t | 111'731 t | 182'484 t |
| Marktlager | 3'944 t | 6'682 t | 10'065 t |
| Menschen in Märkten am Mindestpreis | 50'175 | 86'575 | 98'426 |

Die Ausfuhr bleibt klein, weil das Korn auf den Höfen liegt: Höfe verkaufen nur an den
eigenen Markt, soweit dessen Bargeld reicht, und Fernhändler fahren je 388 kg. Der
Überschuss von rund 14'000 t im Jahr kommt so nicht zum Tor. Gleicher Fingerabdruck mit
1 und 4 Threads (people b977f0990b749f21, grain 3e4d918d99a43cad), Geldbilanz geht auf.

## Säen nach Preis und Lagergrenze der Marktleute (S99, S100, 10 Jahre, Seed 1, `run10-s100-market.txt`; vorher: `run10-s98-outside.txt`)

Höfe säen zuerst den eigenen Bedarf plus ein Viertel Reserve, den Rest ihrer Felder nach
dem Preis, zu dem der Markt ihnen abkauft (S99). Die Marktleute kaufen nur, bis ihr
Lager 180 Tage Absatz deckt (S100). Jahr 10, vorher → nachher:

| Grösse | S98 | S99 + S100 |
|---|---|---|
| Ernte | 46'307 t | 31'414 t |
| Median-Preis | 2,22 Denar/kg (Minimum) | 3,95 Denar/kg |
| Menschen in Märkten am Mindestpreis | 98'426 | 16'962 |
| Hoflager | 182'484 t | 103'172 t |
| Marktlager | 10'065 t | 3'251 t |
| Verdorben im Jahr | 5'924 t | 3'195 t |
| Ausfuhr / Einfuhr nach draussen | 215 / 13 t | 94 / 7 t |
| Hungertote | 106 | 175 |
| Wachstum | 0,09 % | 0,02 % |

Der Preis löst sich vom Minimum. Die Hoflager wachsen aber weiter, rund 5'000 t im Jahr
statt 14'000 t, weil jeder Hof seine Reserve jedes Jahr neu sät, auch wenn sein Speicher
schon für Jahre reicht. Mehr Hungertote: Die Höfe säen weniger und stellen weniger
Taglöhner ein (7,1 statt 7,6 Mio. Taglohntage), und wer in Korn bezahlt wird, hat weniger
(Vermutung aus den Zahlen, nicht einzeln nachgewiesen). Gleicher Fingerabdruck mit 1 und
4 Threads (people e449122c9fd055ef, grain b08e0d2faa6e749a), Geldbilanz geht auf.

100 Jahre (`run100-s100-market.txt`; vorher `run100-s94-money.txt`): Der späte Einbruch
bleibt, mit mehr Hungertoten. Jahr 100: 115'625 statt 131'781 Menschen, Hungertote 879 statt
645, Wachstum −0,29 statt −0,36 %, Median-Preis 8,65 statt 6,27 Denar/kg. Ab Jahr 75 fallen
Ernte (27'248 → 25'270 t) und Taglohntage (6,2 → 4,8 Mio.), die Höfe von 19'172 (Jahr 10)
auf 14'464, und 20,9 % der Höfe sind zu klein für ihren Haushalt. Die Ursache ist nicht
nachgewiesen; Kandidat ist die Teilung durch gleiches Erbe. Auffällig ausserdem: 526 Mio.
Denar „no payee“ in 100 Jahren (Jahr 10: 798), Geld ohne Empfänger, das aus dem Kreislauf
fällt; noch nicht untersucht.

## Einbruch und Geldkreislauf behoben (S102–S104, 100 Jahre, Seed 1, `run100-s102-fixes.txt`; vorher: `run100-before-s102.txt`)

Ramon (29.10.2026): „fixe mir 1. und 2“. Drei Fehler und die Steuer in Geld:

- **Einbruch ab Jahr 75 (S103).** Höfe ohne Haushalt behielten ihre Felder. Übernehmen
  konnten sie nur Zeltleute derselben Region, und die wurden selten (Jahr 100: 384
  Zelte). Die Zahl der leeren Höfe stieg von 3'251 (Jahr 10) auf 17'133 mit 79'291 ha,
  ein Drittel aller Felder. Die übrigen Höfe fanden kein freies Land mehr, die Ernte fiel,
  der Preis stieg auf 8,65 Denar/kg, die Hungertoten auf 879 im Jahr. Jetzt gibt ein Hof
  nach zwei Aussaaten ohne Haushalt seine Felder frei (rund 300 im Jahr); leer stehen nur
  noch etwa 650 Höfe mit 2'500–3'000 ha.
- **Geld ohne Empfänger (S102).** Die Grundherrschaft wurde nur beim Start vergeben.
  Starb der Grundherr aus, ging seine Pacht ins Leere, 526 Mio. Denar in 100 Jahren.
  Jetzt erbt sie ein Verwandter oder Sohn, sonst der Staat. Der Posten „Ohne Empfänger“
  entfällt.
- **Wachsende Hoflager (S103).** Höfe säten ihren Eigenbedarf jedes Jahr neu, auch mit
  vollem Speicher. Jetzt nur, soweit der Speicher nach der nächsten Ernte fehlt. Die
  Ernte liegt dadurch niedriger (Jahr 10: 26'700 statt 31'400 t), verdorben wird weniger.
- **Steuer in Geld (S104).** Das Steuerkorn wird mit dem Getreide des Hofs verkauft, das
  Geld geht in die Kasse.

| Grösse | vorher | jetzt |
|---|---|---|
| Menschen im Jahr 100 | 115'625 | 124'388 |
| Wachstum, Mittel Jahr 11–100 | 0,02 % | 0,10 % |
| Hungertote Jahr 11–100 / im Jahr 100 | 33'309 / 879 | 23'003 / 461 |
| Höfe mit Haushalt im Jahr 100 | 14'464 | 15'048 |
| Leere Höfe im Jahr 100 | 17'133 (79'291 ha) | 694 (2'959 ha) |
| Median-Preis im Jahr 100 | 8,65 Denar/kg | 4,62 Denar/kg |
| Ohne Empfänger, 100 Jahre | 526 Mio. Denar | 0 |
| Steuer in Geld, 100 Jahre | 0 | 789 Mio. Denar |
| Pacht an den Staat, 100 Jahre | 461 Mio. Denar | 725 Mio. Denar |
| Neu geprägt, 100 Jahre | 9'727 Mio. Denar | 9'307 Mio. Denar |
| Nicht gebucht | 0 | 0 |

Der Staat prägt weiter rund 95 Mio. Denar im Jahr, weil Handwerker und Lohnarbeiter
Staatslohn bekommen (S76); die Steuer deckt etwa 6 % davon. Eine Regel, nach der die Preise
der Geldmenge folgen, hat Ramon abgelehnt (S95): Preise sollen emergent entstehen. Der
nächste Schritt sind Waren der Handwerker (S94 Schritt 3). Der Lauf ohne die Fixes zeigt
zusätzlich die Zeile „households“ (nur gelesen, gleicher Fingerabdruck wie
`run100-s100-market.txt`). Tempo gleich (5 Jahre mit beiden Ständen auf derselben Maschine:
Getreide pro Tag Mittel 3,9 / 3,8 ms). 55 Tests grün.

## Handwerkswaren, Staatslohn nur für Staatsdiener, Reiche stellen ein (S105–S111, 100 Jahre, Seed 1, `run100-s105-crafts.txt`; Vergleich mit Staatslohn für alle: `run100-s105-crafts-wage-all.txt`; vorher: `run100-s102-fixes.txt`)

Ramon (29.10.2026): „Kleidung, Werkzeug, Keramik“, „okay finde ich gut dein vorschlag“ und
Karte „Reiche stellen Leute ein“. Wolle, Eisen, Kleidung, Werkzeug und Keramik haben auf
jedem Markt Lager und Preis (S105). Höfe scheren Schafe (S106), Lohn- und Händlerhaushalte
wählen jeden Monat Weber, Schmied, Töpfer oder Taglohn nach Erlös, Haushalte machen Kleidung
selbst, wenn das billiger ist (S107). Werkzeug macht Höfe schneller (S108), Fässer schützen
das Korn (S109). Staatslohn nur noch für Soldaten, Offiziere und Beamte (S110). Wer mehr
Geld hat als Vorrat und Ersparnis, stellt Leute ein (S111). Die Zeile „goods“ im Lauf
zeigt Preise, Lager und Mengen pro Ware.

| Grösse | vorher | jetzt | Vergleich: Staatslohn für alle |
|---|---|---|---|
| Menschen im Jahr 100 | 124'388 | 109'276 | 125'043 |
| Wachstum, Mittel Jahr 11–100 | 0,10 % | 0,00 % | 0,11 % |
| Hungertote Jahr 1–10 / 11–100 | 2'620 / 23'003 | 6'712 / 29'066 | 2'746 / 18'127 |
| Neu geprägt, 100 Jahre | 9'307 Mio. Denar | 3 Mio. Denar | 9'503 Mio. Denar |
| Staatslohn / Steuer, 100 Jahre | 12'800 / 789 Mio. | 204 / 161 Mio. | 12'983 / 1'106 Mio. |
| Geld gehalten im Jahr 100 (ohne Kasse) | 8'767 Mio. Denar | 119 Mio. Denar | 8'314 Mio. Denar |
| Median-Preis Korn im Jahr 100 | 4,62 Denar/kg | 2,90 Denar/kg | 4,41 Denar/kg |
| Median-Preis Kleidung / Werkzeug im Jahr 100 | – | 449 / 274 Denar | 1'469 / 227 Denar |
| Kleidung unter dem Bedarf im Jahr 100 | – | 72 % | 36 % |
| Monate im Jahr 100: Taglohn / Weber / Schmied / Töpfer | – | 28'741 / 6'467 / 525 / 638 | 39'041 / 18'460 / 625 / 1'103 |
| Für Geld eingestellte Tage im Jahr 100 (davon von Marktleuten bezahlt) | – | 614'083 (1,6 Mio. Denar von 6,2) | 8,4 Mio. |
| Nicht gebucht | 0 | 0 | 0 |

Was auffällt:

- **Der Staat prägt fast nichts mehr.** Steuer und Pacht an den Staat übersteigen den Lohn
  der Staatsdiener; die Kasse sammelt 222 Mio. Denar an und gibt sie nicht aus.
- **Der Übergang kostet.** In den ersten fünf Jahren sinkt die Bevölkerung um 4 %, weil
  über 20'000 Menschen den Staatslohn verlieren und erst Arbeit finden müssen. Danach bleibt
  sie gleich, mit etwas mehr Hungertoten als vorher.
- **Mit wenig Geld bleiben die Preise niedrig, mit geprägtem Geld steigen sie.** Ohne
  Staatslohn liegt Korn fast überall am unteren Rand des Preisbands (25 % des Grundpreises).
  Mit Staatslohn für alle steigt Kleidung auf 1'469 Denar und Wolle auf 583 Denar/kg, ohne
  Preisregel: Das neue Geld trifft auf dieselben Waren (S95).
- **Die Reichen geben ihr Geld aus.** Die Oberschicht hält im Jahr 100 noch 2,6 Mio. Denar;
  ohne das Einstellen waren es nach einem Jahr 68 Mio. Die Höfe halten jetzt am meisten (39 Mio.).
- **Kleidung fehlt.** Höfe ohne Schafe und ohne Geld können weder kaufen noch selber machen.
  Fehlende Kleidung wirkt noch nicht auf die Gesundheit.
- **Eisen ist im Binnenland teuer** (Median 139 Denar/kg), weil es nur über die Tormärkte
  kommt und die Marktleute es von Markt zu Markt weitergeben. Deshalb gibt es wenige
  Schmiede, und das Werkzeug der Höfe nimmt ab.
- Tempo: Getreide pro Tag 5,3 ms im Mittel. Beide Läufe liefen gleichzeitig auf derselben
  Maschine, deshalb ist das nicht direkt mit den 4,0 ms von vorher vergleichbar. Gleicher
  Fingerabdruck mit 1 und 4 Threads; 55 Tests grün.

## Preise aus Lager und Händlern, Lohn in Denar, Steuer und Pacht in Getreide (S112, S114, S115, 100 Jahre, Seed 1, `run100-s112-s115.txt` mit `PRICE_DEBUG=1`; vorher: `run100-s105-crafts.txt`, main gibt dasselbe)

Ramon (29.10.2026): „okay dann setz es um. sota 2026 oktober performancemonster“ zum Vorschlag
„Ökonomische Modelle für die Simulation“ (Schritte 1 und 2) und Karte „In Getreide, wie 301“.
Preise kommen aus dem Lager der Marktleute und dem Lagerpfad übers Jahr, ohne Grundpreis und
ohne Band (S112). Der Taglohn ist in Denar und folgt offenen gegen liegen gebliebene Tage;
Fracht folgt dem Lohn, und die Marktleute holen Getreide beim billigeren Nachbarn (S114).
Steuer und Pacht gehen als Korn in Staats- und Herrenspeicher, die nur zum üblichen Preis
verkaufen (S115). Neue Zeilen im Lauf: „prices“ (Lager, Speicher, üblicher Preis, nach Absatz
gewichtet) und „in t“ (Zufluss, Lohn, Reallohn, offene und leere Tage, die sechs grössten Märkte).

| Grösse | vorher (Band) | jetzt |
|---|---|---|
| Menschen im Jahr 10 / 30 / 100 | 109'535 / 107'911 / 109'276 | 111'400 / 107'239 / 87'799 |
| Wachstum, Mittel Jahr 11–100 | 0,00 % | −0,26 % |
| Hungertote Jahr 11–30 / 31–100 | 5'579 / 23'487 | 6'945 / 48'294 |
| Ernte im Jahr 10 / 100 | 23'623 / 23'838 t | 29'866 / 17'646 t |
| Höfe mit Haushalt im Jahr 100 | 14'993 | 10'641 |
| Median-Preis Korn im Jahr 10 / 100 | 2,27 / 2,90 Denar/kg | 0,94 / 0,31 Denar/kg |
| Üblicher Preis Korn, nach Absatz gewichtet, Jahr 1 / 10 / 100 | – | 7,03 / 0,29 / 0,20 Denar/kg |
| Reallohn, Median, Jahr 1 / 10 / 100 | – | 1,7 / 3,3 / 4,7 kg pro Tag |
| Werkzeug auf den Höfen im Jahr 100 | 25'975 kg | 2'696 kg |
| Eisen / Werkzeug, Median-Preis im Jahr 100 | 139 / 274 Denar/kg | 680 / 1'037 Denar/kg |
| Schmiede-Monate im Jahr 100 | 525 | 26 |
| Staats- und Herrenspeicher im Jahr 100 | – | 29'604 / 5'711 t |
| Steuer / Staatslohn, 100 Jahre | 161 / 204 Mio. Denar | 137 / 225 Mio. Denar |
| Neu geprägt, 100 Jahre | 3,3 Mio. Denar | 0,02 Mio. Denar |
| Nicht gebucht | 0 | 0 |
| Getreide pro Tag, Median | 4,3 ms | 5,4 ms |

Was auffällt:

- **Die ersten 30 Jahre tragen.** Der Preis steigt übers Erntejahr und fällt bei der Ernte,
  der Reallohn liegt bei 2–4 kg Korn pro Tag (Edikt: etwa 3 kg mit Kost; Allen, 2009), der
  Staat prägt fast nichts, und die Menschenzahl liegt wie vorher bei 107'000–111'000.
- **Danach bricht es ein.** Ohne Band fällt der Getreidepreis, wo Getreide viel ist, immer
  weiter: nach Absatz gewichtet von 7 auf 0,2 Denar/kg in zehn Jahren. Getreide ist im
  Überschuss (jedes Jahr verderben 2'800–5'900 t), und niemand isst mehr, wenn es billig ist.
  Wo die Marktleute an ihrer Lagergrenze sitzen, sinkt der übliche Preis jeden Tag um 1/365.
- **Der tiefe Preis wird real, weil Eisen von aussen kommt.** Eisen gibt es nur an den
  Tormärkten zum festen Preis draussen (S98, S108). Im Jahr 100 kostet 1 kg Werkzeug so viel
  wie 3'300 kg Korn (vorher 94 kg). Die Höfe können kein Werkzeug mehr kaufen, arbeiten mit
  70 % (S108), die Ernte sinkt, und Hunger und Abwanderung vom Hof steigen.
- **Steuer und Pacht in Getreide wirken.** Zwangsverkäufe gibt es nicht mehr; die Speicher
  halten das Korn, solange der Preis tief ist (bis 41'000 t beim Staat), und verderben 4 % im
  Jahr.
- **Versucht und verworfen:** Der übliche Preis sinkt an der Lagergrenze nur, wenn die
  Marktleute wirklich Verkäufer abweisen. Das bremst den Fall (Jahr 15: 1,60 statt
  0,18 Denar/kg nach Absatz), stoppt ihn aber nicht; das Korn liegt dann in Speichern und
  Höfen (15 Jahre, nicht eingecheckt).
- **Folgerung:** Die Preisregel allein kann den Überschuss nicht auflösen. Es fehlt die
  Nachfrage, die auf den Preis reagiert (Schritt 3 des Vorschlags: Konsum mit Puffer-Ersparnis,
  mehr Korn für Menschen und Tiere, wenn es billig ist). Ausserdem ist der Preis draussen der
  einzige feste Preis in Denar; Eisen aus dem Reich (Bergbau) fehlt.
- **Entscheid:** Ramon, 29.10.2026, Karte „Wie gehen wir den fallenden Getreidepreis an?“,
  Option „Jetzt mergen, Konsum danach“.
- Tempo: Getreide pro Tag 5,4 statt 4,3 ms im Median (Märkte, Arbeitsbörse, Speicher). Beide
  Läufe liefen teils gleichzeitig auf derselben Maschine. Gleicher Fingerabdruck mit 1 und 4
  Threads; 70 Tests grün.

### Quellen zu S112, S114, S115 (APA 7)

- Allen, R. C. (2009). How prosperous were the Romans? Evidence from Diocletian's price edict (AD 301). In A. Bowman & A. Wilson (Eds.), *Quantifying the Roman economy: Methods and problems* (pp. 327–345). Oxford University Press.
- Avellaneda, M., & Stoikov, S. (2008). High-frequency trading in a limit order book. *Quantitative Finance, 8*(3), 217–224. https://doi.org/10.1080/14697680701381228
- Axtell, R. L., & Farmer, J. D. (2025). Agent-based modeling in economics and finance: Past, present, and future. *Journal of Economic Literature, 63*(1), 197–287. https://doi.org/10.1257/jel.20221319
- Cafiero, C., Bobenrieth, E. S. A., Bobenrieth, J. R. A., & Wright, B. D. (2011). The empirical relevance of the competitive storage model. *Journal of Econometrics, 162*(1), 44–54. https://doi.org/10.1016/j.jeconom.2009.10.008
- Deaton, A., & Laroque, G. (1992). On the behaviour of commodity prices. *The Review of Economic Studies, 59*(1), 1–23. https://doi.org/10.2307/2297923
- Dosi, G., Pereira, M. C., Roventini, A., & Virgillito, M. E. (2017). When more flexibility yields more fragility: The microfoundations of Keynesian aggregate unemployment. *Journal of Economic Dynamics and Control, 81*, 162–186. https://doi.org/10.1016/j.jedc.2017.02.005
- Erdkamp, P. (2005). *The grain market in the Roman Empire: A social, political and economic study*. Cambridge University Press.
- Ho, T., & Stoll, H. R. (1981). Optimal dealer pricing under transactions and return uncertainty. *Journal of Financial Economics, 9*(1), 47–73. https://doi.org/10.1016/0304-405X(81)90020-9
- Jones, A. H. M. (1964). *The later Roman Empire, 284–602: A social, economic, and administrative survey*. Blackwell.
- Lengnick, M. (2013). Agent-based macroeconomics: A baseline model. *Journal of Economic Behavior & Organization, 86*, 102–120. https://doi.org/10.1016/j.jebo.2012.12.021
- Lewis, W. A. (1954). Economic development with unlimited supplies of labour. *The Manchester School, 22*(2), 139–191. https://doi.org/10.1111/j.1467-9957.1954.tb00021.x
- Mortensen, D. T., & Pissarides, C. A. (1994). Job creation and job destruction in the theory of unemployment. *The Review of Economic Studies, 61*(3), 397–415. https://doi.org/10.2307/2297896
- Rathbone, D. (1991). *Economic rationalism and rural society in third-century A.D. Egypt: The Heroninos archive and the Appianus estate*. Cambridge University Press.
- Samuelson, P. A. (1952). Spatial price equilibrium and linear programming. *The American Economic Review, 42*(3), 283–303.
- Takayama, T., & Judge, G. G. (1971). *Spatial and temporal price and allocation models*. North-Holland.
- Williams, J. C., & Wright, B. D. (1991). *Storage and commodity markets*. Cambridge University Press.

## Konsum mit Puffersparen, Schweinefleisch, Staatskorn (S117, S118, S119, 100 Jahre, Seed 1, `run100-s117-s119.txt` mit `PRICE_DEBUG=1 GOODS_DEBUG=1`; vorher: `run100-s112-s115.txt`)

Ramon (29.10.2026), Karte „Was soll ich für Schritt 3 Konsum bauen?“, Option „Alles, mit
Staatskorn“. Haushalte geben nach der Konsumfunktion des Puffersparens aus (S117): zuerst
Werkzeug und Fässer der Höfe, einfache Kleidung und Geschirr, der Rest für Schweinefleisch,
mehr Kleidung und Dienste. Höfe mästen Schweine mit Getreide, solange Fleisch mehr bringt als
das Korn im Lager wert ist (S118). Staatsdiener bekommen ihren Monatsbedarf aus dem
Staatsspeicher, vom Lohn abgezogen (S119). Neue Werte im Lauf: Ausgaben der Haushalte,
Schweine im Jahr, verfüttertes Korn, Rationen; in den Tabellen Staats- und Herrenspeicher pro
Markt und Schweinefleisch als Ware.

| Grösse | main (Band) | S112–S115 | jetzt |
|---|---|---|---|
| Menschen im Jahr 10 / 30 / 100 | 109'535 / 107'911 / 109'276 | 111'400 / 107'239 / 87'799 | 109'643 / 106'081 / 84'343 |
| Wachstum, Mittel Jahr 11–100 | 0,00 % | −0,26 % | −0,29 % |
| Hungertote Jahr 1–10 / 11–30 / 31–100 | 6'712 / 5'579 / 23'487 | 5'061 / 6'945 / 48'294 | 6'815 / 6'351 / 49'097 |
| Ernte im Jahr 10 / 100 | 23'623 / 23'838 t | 29'866 / 17'646 t | 31'450 / 18'050 t |
| Höfe mit Haushalt im Jahr 100 | 14'993 | 10'641 | 10'375 |
| Üblicher Preis Korn, nach Absatz gewichtet, Jahr 1 / 10 / 100 | – | 7,03 / 0,29 / 0,20 Denar/kg | 7,04 / 0,34 / 0,37 Denar/kg |
| Üblicher Preis Korn, Median der Märkte, Jahr 100 | – | 1,40 Denar/kg | 1,55 Denar/kg |
| Reallohn p10 / p50, Jahr 100 | – | 1,2 / 4,7 kg | 1,2 / 4,9 kg |
| Werkzeug auf den Höfen im Jahr 100 | 25'975 kg | 2'696 kg | 4'371 kg |
| Ausgaben der Haushalte, Jahr 1 / 10 / 100 | – | – | 104 / 34 / 71 Mio. Denar |
| Korn an Schweine, Jahr 1 / 10 / 50 / 100 | – | – | 2'830 / 2'117 / 455 / 318 t |
| Rationen an Staatsdiener, Jahr 1 / 10 / 100 | – | – | 90 / 51 / 17 t |
| Staats- und Herrenspeicher im Jahr 100 | – | 29'604 / 5'711 t | 26'798 / 7'224 t |
| Nicht gebucht | 0 | 0 | 0 |
| Getreide pro Tag, Median | 4,3 ms | 5,4 ms | 5,5 ms |

Was auffällt:

- **Der Konsum läuft wie im Modell.** Im ersten Jahr bauen die Haushalte ihr Startgeld über
  dem Puffer ab (104 Mio. Denar Ausgaben), danach 34–71 Mio. im Jahr. Wer wenig verdient,
  kauft nur den Grundbedarf.
- **Die Schweinemast kostet anfangs Menschen.** Im Jahr 2 sterben 3'730 Menschen an Hunger,
  gegen 2'772 mit S112–S115. Gegenprobe ohne Mast (3 Jahre, nicht eingecheckt): 2'946. Die
  Höfe verfüttern das Korn, das sie sonst bis zum Frühjahr gehalten und verkauft hätten; den
  Lohnhaushalten fehlt es dann (gegessen 85 statt 88 %). Das ist der bekannte Wettbewerb
  zwischen Futter und Brot. Zwei Korrekturen sind schon drin: das übliche Einkommen kommt aus
  dem wirklich Verdienten (vorher zu hoch geschätzt), und das Korn im Lager zählt beim Füttern
  mit dem üblichen Preis, nicht mit dem tiefen Tagespreis. Beide ändern den Hunger im Jahr 2
  kaum.
- **Staatskorn ist zu klein, um zu wirken.** Es gibt rund 180 Haushalte von Staatsdienern;
  ihre Rationen sind 17–90 t im Jahr gegen 27'000 t im Staatsspeicher.
- **Der Getreidepreis fällt weiter.** Nach Absatz gewichtet 0,34 Denar/kg im Jahr 10 statt
  0,29, im Jahr 100 0,37 statt 0,20. Die Mast nimmt im Jahr 1 bis 10 nur 2'000–3'000 t im Jahr
  ab, später weniger, weil es weniger Höfe mit Überschuss gibt. Die billigsten grossen Märkte
  liegen im Nildelta (Benha 0,01, Tell el-Balamun 0,04 Denar/kg im Jahr 100), Rom zahlt 5,37.
  Der Überschuss kommt dort nicht weg: Die Marktleute holen nur, was ihr eigener Absatz für
  eine Woche braucht (S114), und niemand bringt Korn aus vollen Märkten zu teureren oder
  hinaus.
- **Folgerung:** Mehr Nachfrage allein hält den Preis nicht. Es fehlt der Handel, der
  Überschuss dorthin bringt, wo er mehr wert ist (räumliches Gleichgewicht: Samuelson, 1952;
  Takayama & Judge, 1971), dazu Eisen aus dem Reich und Missernten (S101), damit Lagern sich
  lohnt.
- **Entscheid:** Ramon, 30.10.2026, Karte „Wie machen wir nach Schritt 3 weiter?“, Option
  „Mergen, dann Überschuss-Handel“.
- Gleicher Fingerabdruck mit 1 und 4 Threads (2 Jahre); 70 Tests grün.

### Quellen zu S117, S118, S119 (APA 7)

- Allen, R. C. (2009). How prosperous were the Romans? Evidence from Diocletian's price edict (AD 301). In A. Bowman & A. Wilson (Eds.), *Quantifying the Roman economy: Methods and problems* (pp. 327–345). Oxford University Press.
- Barquín, R. (2005). The demand elasticity for wheat in the 14th to 18th centuries. *Revista de Historia Económica, 23*(2), 241–267.
- Bartnik, A. (2023). Żywienie trzody chlewnej w starożytnym Rzymie [Pig feeding in ancient Rome]. *Zeszyty Wiejskie, 29*, 139–153. https://doi.org/10.18778/1506-6541.29.07
- Carroll, C. D. (1997). Buffer-stock saving and the life cycle/permanent income hypothesis. *The Quarterly Journal of Economics, 112*(1), 1–55. https://doi.org/10.1162/003355397555109
- Carroll, C. D. (2006). The method of endogenous gridpoints for solving dynamic stochastic optimization problems. *Economics Letters, 91*(3), 312–320. https://doi.org/10.1016/j.econlet.2005.09.013
- Comin, D., Lashkari, D., & Mestieri, M. (2021). Structural change with long-run income and price effects. *Econometrica, 89*(1), 311–374. https://doi.org/10.3982/ECTA16317
- Fagereng, A., Holm, M. B., & Natvik, G. J. (2021). MPC heterogeneity and household balance sheets. *American Economic Journal: Macroeconomics, 13*(4), 1–54. https://doi.org/10.1257/mac.20190211
- Friedman, M. (1957). *A theory of the consumption function*. Princeton University Press.
- Jones, A. H. M. (1964). *The later Roman Empire, 284–602: A social, economic, and administrative survey*. Blackwell.
- Persson, K. G. (1999). *Grain markets in Europe, 1500–1900: Integration and deregulation*. Cambridge University Press.

## Überschuss-Handel (S120, 100 Jahre, Seed 1, `run100-s120.txt` mit `PRICE_DEBUG=1 GOODS_DEBUG=1`; vorher: `run100-s117-s119.txt`)

Ramon (30.10.2026), Karte „Wie machen wir nach Schritt 3 weiter?“, Option „Mergen, dann
Überschuss-Handel“. Marktleute mit mehr als ihrem geplanten Lager schicken Korn zum bekannten
Markt, der nach Fracht am meisten zahlt (S120). Neu im Lauf: „fetched/sent by dealers“ und
„out/in beyond the map“ (Korn, das die Karte über die Tormärkte verlässt oder hereinkommt).

| Grösse | main (Band) | S117–S119 | jetzt |
|---|---|---|---|
| Menschen im Jahr 10 / 30 / 100 | 109'535 / 107'911 / 109'276 | 109'643 / 106'081 / 84'343 | 106'788 / 98'482 / 73'659 |
| Wachstum, Mittel Jahr 11–100 | 0,00 % | −0,29 % | −0,41 % |
| Hungertote Jahr 1–10 / 11–30 / 31–100 | 6'712 / 5'579 / 23'487 | 6'815 / 6'351 / 49'097 | 8'844 / 9'049 / 45'819 |
| Verlassen die Karte, 100 Jahre | 8'700 | 18'284 | 25'128 |
| Ernte im Jahr 10 / 100 | 23'623 / 23'838 t | 31'450 / 18'050 t | 33'996 / 16'187 t |
| Üblicher Preis Korn, nach Absatz gewichtet, Jahr 10 / 30 / 100 | – | 0,34 / 0,26 / 0,37 Denar/kg | 1,28 / 1,10 / 1,63 Denar/kg |
| Median-Preis Korn im Jahr 100 | 2,90 Denar/kg | 0,46 Denar/kg | 1,14 Denar/kg |
| Korn zu anderen Märkten geschickt, Jahr 10 / 100 (höchstens) | – | – | 22'223 / 5'179 t (28'295 t) |
| Korn hinaus über die Tormärkte, Jahr 10 / 100, 100 Jahre | – | – | 6'390 / 1'406 t, 169'751 t |
| Reallohn p10 / p50, Jahr 100 | – | 1,2 / 4,9 kg | 1,3 / 3,8 kg |
| Liegen gebliebene / offene Arbeitstage pro Woche, Jahr 100 | – | 44'491 / 38'713 | 46'772 / 21'019 |
| Staats- und Herrenspeicher im Jahr 100 | – | 26'798 / 7'224 t | 10'529 / 2'313 t |
| Nicht gebucht | 0 | 0 | 0 |
| Getreide pro Tag, Median | 4,3 ms | 5,5 ms | 5,2 ms |

Was auffällt:

- **Der Preis hält besser.** Nach Absatz gewichtet bleibt der übliche Preis bei 1,1–1,6 statt
  0,3 Denar/kg. In den ersten zehn Jahren wandern bis 28'000 t im Jahr von vollen zu teureren
  Märkten; die Speicher verkaufen mehr (Steuer 384 statt 134 Mio. Denar in 100 Jahren).
- **Aber es sterben mehr Menschen.** Im Jahr 100 leben 73'659 statt 84'343. In den Jahren
  1–30 gibt es 17'900 statt 13'200 Hungertote, und mehr Menschen verlassen die Karte; danach
  fehlen die Geburten.
- **Viel Korn verlässt die Karte.** Über die Tormärkte gehen in den Jahren 5–11 jedes Jahr
  3'000–6'400 t hinaus, bis zu einem Fünftel der Ernte, in 100 Jahren 170'000 t. Die Märkte
  draussen kaufen zum festen Preis jede Menge (S98, frei gewählt); so wird das Korn dorthin
  verkauft, wo es Geld bringt, während Arme drinnen es sich nicht leisten können.
- **Der Hunger kommt vom Einkommen.** Der Reallohn der ärmsten zehn Prozent liegt bei
  0,8–1,4 kg Korn pro Tag, eine Familie braucht etwa 2,5 kg. Jede Woche bleiben mehr
  Arbeitstage liegen, als gesucht werden. Ein höherer Kornpreis trifft genau diese Haushalte.
- **Entscheid:** Ramon, 30.10.2026, Karte „Was machen wir mit dem Überschuss-Handel (PR #61)?“,
  Option „Jetzt mergen“.
- Gleicher Fingerabdruck mit 1 und 4 Threads (2 Jahre); 70 Tests grün.

### Quellen zu S120 (APA 7)

- Kessler, D., & Temin, P. (2007). The organization of the grain trade in the early Roman Empire. *The Economic History Review, 60*(2), 313–332.
- Samuelson, P. A. (1952). Spatial price equilibrium and linear programming. *The American Economic Review, 42*(3), 283–303.
- Takayama, T., & Judge, G. G. (1971). *Spatial and temporal price and allocation models*. North-Holland.

## Märkte draussen und Saatgut (S121, S122, 100 Jahre, Seed 1, `run100-s121-s122.txt` mit `PRICE_DEBUG=1 GOODS_DEBUG=1`; vorher: `run100-s120.txt`)

Ramon (30.10.2026): „ja und draussen märkte müssen auch angebot und nachfrage folgen natürlich“,
dann Karte „Wie bauen wir Märkte draussen und den Hunger-Fix?“, Option „Märkte draussen plus
Saatgut“, zum Befund https://claude.ai/artifact/DvWYeGWVBj2fR2XTCuYvXC. Vier Märkte jenseits der
Karte mit Ernte, Lager und Nachfrage nach HYDE (S121) statt des festen Preises für jede Menge
(S98); Höfe behalten das Saatgut und kaufen ihr Essen vor der Saat (S122). Jede Hälfte allein
gemessen (je ein Lauf mit nur S122 und mit nur S121, 1 Thread). Neu im Lauf: die Zeile
„beyond the map (S121)“ mit Preis, Lager, Ernte und Handel jedes Markts draussen. Grafiken:
https://claude.ai/artifact/1LQYuTH5ugLE9tsGkKF5NK

| Grösse | main (S120) | nur S122 | nur S121 | beide |
|---|---|---|---|---|
| Menschen im Jahr 10 / 30 / 100 | 106'788 / 98'482 / 73'659 | 108'210 / 105'385 / 104'913 | 109'250 / 104'856 / 77'600 | 109'527 / 109'680 / 115'843 |
| Wachstum, Mittel Jahr 11–100 | −0,41 % | −0,03 % | −0,38 % | +0,06 % |
| Hungertote Jahr 1–10 / 11–30 / 31–100 | 8'844 / 9'049 / 45'819 | 7'834 / 4'953 / 22'731 | 7'027 / 5'842 / 50'688 | 6'814 / 2'944 / 21'514 |
| Verlassen die Karte, 100 Jahre | 25'128 | 16'636 | 22'219 | 14'609 |
| Ernte im Jahr 10 / 100 | 33'996 / 16'187 t | 34'664 / 24'433 t | 31'104 / 14'669 t | 29'218 / 23'799 t |
| Üblicher Preis Korn, nach Absatz gewichtet, Jahr 10 / 100 | 1,28 / 1,63 Denar/kg | 1,12 / 1,79 | 0,19 / 0,31 | 0,10 / 0,15 |
| Median-Preis Korn / Rom im Jahr 100 | 1,14 / 4,59 Denar/kg | 0,48 / 4,10 | 0,28 / 3,10 | 0,12 / 2,13 |
| Korn hinaus / herein über die Tormärkte, 100 Jahre | 169'751 / 0 t | 323'382 / 3 t | 3'692 / 628 t | 5'474 / 1'241 t |
| Reallohn p10 / p50, Jahr 100 | 1,3 / 3,8 kg | 1,7 / 4,4 kg | 1,5 / 6,2 kg | 1,5 / 7,8 kg |
| Steuer, 100 Jahre / Staatskasse im Jahr 100 | 384 / 448 Mio. Denar | 565 / 610 | 58 / 19 | 59 / 54 |
| Staats- und Herrenspeicher im Jahr 100 | 10'529 / 2'313 t | 5'381 / 1'022 t | 14'552 / 3'283 t | 16'882 / 3'616 t |
| Liegen gebliebene / offene Arbeitstage pro Woche, Jahr 100 | 46'772 / 21'019 | 74'803 / 25'467 | 44'657 / 23'156 | 78'450 / 26'177 |
| Nicht gebucht | 0 | 0 | 0 | 0 |
| Tag gesamt, Mittel (1 Thread, 4 Läufe gleichzeitig) | 20,0 ms | 22,2 ms | 20,9 ms | 22,9 ms |

Märkte draussen im Lauf „beide“, Jahr 100:

| Markt | Menschen (Massstab) | Preis | Lager Händler / Bauern | Kommende Ernte | Von uns gekauft / an uns verkauft im Jahr |
|---|---|---|---|---|---|
| Jenseits des Zagros | 6'158 | 5,49 Denar/kg | 436 / 640 t | 1'101 t | 73 / 0 t |
| Nubien und Arabien | 1'286 | 0,13 | 56 / 41 t | 231 t | 4 / 8 t |
| Skandinavien und Nordrussland | 710 | 0,07 | 31 / 42 t | 127 t | 0 / 4 t |
| Atlantikküste | 71 | 0,20 | 3 / 3 t | 12 t | 2 / 0 t |

Was auffällt:

- **Das Saatgut ist der grosse Hebel.** S122 allein bringt im Jahr 100 31'000 Menschen mehr und
  halbiert die Hungertote der Jahre 31–100. Mit beiden wächst die Bevölkerung leicht
  (115'843 im Jahr 100), der Reallohn in der Mitte verdoppelt sich.
- **Kaum noch Korn verlässt die Karte.** Die Märkte draussen essen, was sie ernten, und kaufen
  nur, wenn es nach Fracht billiger ist als ihr eigenes Korn: 5'474 t in 100 Jahren statt
  169'751 t. Ihre Preise folgen den Tormärkten, mit denen sie handeln; jenseits des Zagros bleibt
  das Korn teuer, weil 500 km über Land viel kosten.
- **Aber der Getreidepreis fällt auf 0,10–0,15 Denar pro kg.** Die Karte erntet mehr, als ihre
  Menschen essen: Jeder Hof sät seinen Bedarf mit einem Viertel Reserve, Steuer und Pacht
  kommen als Korn in die Speicher. Bisher kaufte draussen jemand jede Menge zum festen Preis
  (S98), das hielt den Preis. Jetzt bleibt ein Drittel der Felder ungesät, weil sich Korn für
  den Markt nicht lohnt (S99), und doch bleibt Überschuss.
- **Die Staatskasse leidet.** Die Steuer kommt als Korn und bringt beim tiefen Preis nur
  59 statt 384 Mio. Denar in 100 Jahren; die Kasse wächst trotzdem leicht (54 Mio. im Jahr 100).
- **S121 allein hilft wenig.** Ohne S122 sterben in den Jahren 31–100 mehr Menschen als auf main:
  Wer sein Saatgut verkauft, hungert auch bei billigem Korn.
- **Entscheid:** Ramon, 30.10.2026, Karte „Wie machen wir mit PR #64 und dem Preisfall weiter?“,
  Option „Mergen, dann Preisfall angehen“.
- Gleicher Fingerabdruck mit 1 und 4 Threads (2 Jahre); 73 + 2 Tests grün, auch im Debug-Build
  (dafür prüft bevy_ecs dort nicht mehr die Länge der Teilstücke, siehe `sim/Cargo.toml`).

### Quellen zu S121, S122 (APA 7)

- Klein Goldewijk, K. (2024). *HYDE 3.3: History database of the global environment* [Data set]. Utrecht University. https://doi.org/10.24416/UU01-94FNH0
- Makki, S. S., Tweeten, L. G., & Miranda, M. J. (2001). Storage–trade interactions under uncertainty: Implications for food security. *Journal of Policy Modeling, 23*(2), 127–140. https://doi.org/10.1016/S0161-8938(00)00059-9
- Roberts, M. J., & Schlenker, W. (2013). Identifying supply and demand elasticities of agricultural commodities: Implications for the US ethanol mandate. *American Economic Review, 103*(6), 2265–2295. https://doi.org/10.1257/aer.103.6.2265
- Samuelson, P. A. (1952). Spatial price equilibrium and linear programming. *The American Economic Review, 42*(3), 283–303.
- Takayama, T., & Judge, G. G. (1971). *Spatial and temporal price and allocation models*. North-Holland.
- Williams, J. C., & Wright, B. D. (1991). *Storage and commodity markets*. Cambridge University Press.

## Lagerboden und Saat nach Preis (S123, S124, 100 Jahre, Seed 1, `run100-s123-s124.txt` mit `PRICE_DEBUG=1 GOODS_DEBUG=1`; vorher: `run100-s121-s122.txt`)

Ramon (30.10.2026), Karte „Wie gehen wir den Preisfall beim Korn an?“, Option „Lagerboden und
Saat nach Preis“, zum Vorschlag https://claude.ai/artifact/9WAqjJvXyaj9H8HRpzxQZN. Wer Korn lagert,
verkauft nur zum erwarteten Preis und nur so viel, wie die Marktleute dazu nehmen; deren Preis fällt
nicht unter die Erwartung abzüglich Zins und Verderb eines Jahres (S123). Höfe säen weniger für den
Eigenbedarf, wenn Kaufen billiger ist als die eigenen Arbeitstage und der Markt verlässlich Korn hat
(S124). Jede Hälfte allein gemessen (`--no-floor`, `--no-sow-price`; je 1 Thread). Der Lauf mit
beiden ausgeschaltet gibt dieselben Zahlen wie main. Neu im Lauf: „expected by sales“ und „at
floor“ in der Preiszeile, „own need sown … cut …“ in der Lohnzeile. Grafiken:
https://claude.ai/artifact/1LQYuTH5ugLE9tsGkKF5NK

| Grösse | main (S121, S122) | nur Boden (S123) | nur Saat (S124) | beide |
|---|---|---|---|---|
| Menschen im Jahr 10 / 40 / 100 | 109'527 / 109'789 / 115'843 | 108'266 / 111'514 / 122'080 | 109'476 / 105'051 / 98'072 | 108'178 / 110'787 / 123'079 |
| Wachstum, Mittel Jahr 11–100 | +0,06 % | +0,13 % | −0,12 % | +0,14 % |
| Hungertote Jahr 1–10 / 11–30 / 31–100 | 6'814 / 2'944 / 21'514 | 7'978 / 1'880 / 12'445 | 6'806 / 5'251 / 28'194 | 8'073 / 1'825 / 11'841 |
| Verlassen die Karte, 100 Jahre | 14'609 | 4'114 | 19'017 | 4'010 |
| Ernte im Jahr 10 / 100 | 29'218 / 23'799 t | 37'663 / 34'682 t | 28'727 / 19'825 t | 37'370 / 34'612 t |
| Preis Korn nach Absatz, Jahr 1 / 10 / 40 / 100 | 6,8 / 0,10 / 0,09 / 0,15 Denar/kg | 8,44 / 6,0 / 2,73 / 0,91 | 6,8 / 0,09 / 0,13 / 0,15 | 8,44 / 5,91 / 2,77 / 1,05 |
| Median-Preis Korn / Rom im Jahr 100 | 0,12 / 2,13 Denar/kg | 1,04 / 4,21 | 0,16 / 3,21 | 1,15 / 4,55 |
| Taglohn p50, Jahr 1 / 40 / 100 | 11,56 / 6,38 / 2,50 Denar | 13,19 / 9,77 / 4,88 | 11,56 / 5,73 / 2,11 | 13,19 / 9,75 / 4,70 |
| Reallohn p10 / p50, Jahr 100 | 1,5 / 7,8 kg | 1,2 / 2,8 kg | 1,5 / 5,8 kg | 1,2 / 2,7 kg |
| Höfe, die weniger Eigenbedarf säen, Jahr 40 / 100 | – | – | 3'789 / 2'062 | 1'136 / 795 |
| Staats- und Herrenspeicher im Jahr 100 | 16'882 / 3'616 t | 74'956 / 27'562 t | 13'980 / 2'393 t | 73'677 / 24'947 t |
| Steuer, 100 Jahre / Staatskasse im Jahr 100 | 59 / 54 Mio. Denar | 140 / 204 | 71 / 60 | 153 / 217 |
| Korn hinaus / herein über die Tormärkte, 100 Jahre | 5'474 / 1'241 t | 3'946 / 1'256 t | 4'934 / 1'529 t | 4'526 / 1'921 t |
| Liegen gebliebene / offene Arbeitstage pro Woche, Jahr 100 | 78'450 / 26'177 | 50'738 / 65'898 | 60'120 / 28'361 | 54'316 / 62'301 |
| Nicht gebucht | 0 | 0 | 0 | 0 |
| Tag gesamt, Mittel (1 Thread, 4 Läufe gleichzeitig) | 22,4 ms | 22,4 ms | 21,1 ms | 22,4 ms |

Was auffällt:

- **Der Boden ist der grosse Hebel.** Mit S123 fällt der Preis nicht mehr in zehn Jahren auf
  ein Zehntel Denar, sondern langsam: 5,9 im Jahr 10, 2,8 im Jahr 40, 1,05 im Jahr 100. Im Jahr 100
  leben 6'000–7'000 Menschen mehr, die Hungertote ab Jahr 31 sinken um 42–45 %, und viel weniger
  Menschen verlassen die Karte. Den Boden selbst (Erwartung minus 16 %) erreichen kaum Märkte
  (höchstens 15); es wirkt vor allem, dass Höfe und Speicher nicht mehr unter dem erwarteten Preis
  und nicht über das Planlager hinaus verkaufen.
- **Lohn und Preis sinken zusammen.** Der Taglohn fällt mit dem Preis von 13,2 auf 4,7 Denar; der
  Reallohn in der Mitte bleibt bei 2,7–3,3 kg Korn am Tag statt auf 7,8 kg zu steigen. Das
  Preisniveau in Denar hat keinen Anker: Die Nachfrage nach Korn ist in kg, nicht in Denar.
- **Die Speicher horten.** Staat und Herren halten im Jahr 100 rund 100 kt, drei Jahresernten. Sie
  verkaufen nicht unter dem erwarteten Preis, und der Staat braucht sein Korn kaum (S119). Erst der
  Verderb von 4 % im Jahr gleicht ab etwa Jahr 60 den Zufluss aus Steuer und Pacht aus. Dafür bringt
  die Steuer 153 statt 59 Mio. Denar.
- **Am Anfang hungern die Ärmsten mehr.** In den Jahren 1–10 sterben 8'073 statt 6'814 Menschen
  an Hunger: Der Preis bleibt beim Startpreis nach dem Edikt, und Lohnhaushalte können ihn nicht
  zahlen (Reallohn p10 0,76 kg). Auf main hielt das billige Korn sie am Leben.
- **Saat nach Preis hilft nur mit Boden.** Zusammen säen 800–2'000 von rund 17'000 Höfen weniger,
  und es bringt 1'000 Menschen und 600 Hungertote weniger als der Boden allein. Allein schadet S124:
  Beim zusammengebrochenen Preis wirkt Kaufen billig, bis 3'800 Höfe verlassen sich auf Märkte,
  die dann nicht liefern (Käufer finden 1–2,5 t am Tag nichts), und im Jahr 100 leben 98'072
  Menschen.
- **Die Fläche antwortet wie in der Literatur.** Im Lauf „beide“ antwortet die gesäte Fläche auf den
  Kornpreis gegen den Lohn mit 0,09 (Jahre 1–40) und 0,22 (Jahre 1–10); Roberts & Schlenker (2013)
  messen 0,08–0,13, Haile u. a. (2016) 0,05–0,40.
- **Warum der Preis noch sinkt (Messsonde, nicht eingebaut, 40 Jahre, beide an).** Die Marktleute
  messen ihr Lager am Absatz des letzten Monats. Nach der Ernte essen die Höfe ihr eigenes Korn, der
  Absatz bricht ein, das Lager reicht plötzlich weit über 180 Tage, und der übliche Preis sinkt;
  steigen kann er erst unter 30 Tagen. Gemessen am Absatz eines Jahres hält der Preis: 6,8 Denar/kg im
  Jahr 40 bei einer Erwartung von 6,6, Taglohn 16 Denar. Dafür sterben im Jahr 2 6'211 statt 5'019
  Menschen an Hunger, und die Speicher wachsen weiter (113 kt im Jahr 40). Das ist eine Änderung an
  S112 und braucht Ramons Entscheid.
- Gleicher Fingerabdruck mit 1 und 4 Threads (5 Jahre); 75 Tests grün, 1 ausgelassen.
- Entscheid: Ramon (30.10.2026), Karte „Wie machen wir mit PR #67 und dem restlichen Preisfall
  weiter?“, Option „Mergen, dann Lager am Jahresabsatz“: S123 und S124 kommen so auf main, als
  Nächstes folgt der Vorschlag zum Lager am Jahresabsatz.

### Quellen zu S123, S124 (APA 7)

- Deaton, A., & Laroque, G. (1992). On the behaviour of commodity prices. *The Review of Economic Studies, 59*(1), 1–23. https://doi.org/10.2307/2297923
- Fafchamps, M. (1992). Cash crop production, food price volatility, and rural market integration in the Third World. *American Journal of Agricultural Economics, 74*(1), 90–99. https://doi.org/10.2307/1242993
- Gouel, C., & Legrand, N. (2025). The role of storage in commodity markets: Indirect inference based on grain data. *Quantitative Economics, 16*(2), 705–747. https://doi.org/10.3982/QE2329
- Haile, M. G., Kalkuhl, M., & von Braun, J. (2016). Worldwide acreage and yield response to international price change and volatility: A dynamic panel data analysis for wheat, rice, corn, and soybeans. *American Journal of Agricultural Economics, 98*(1), 172–190. https://doi.org/10.1093/ajae/aav013
- Ho, T., & Stoll, H. R. (1981). Optimal dealer pricing under transactions and return uncertainty. *Journal of Financial Economics, 9*(1), 47–73. https://doi.org/10.1016/0304-405X(81)90020-9
- LaFave, D., & Thomas, D. (2016). Farms, families, and markets: New evidence on completeness of markets in agricultural settings. *Econometrica, 84*(5), 1917–1960. https://doi.org/10.3982/ECTA12987
- Nerlove, M. (1958). Adaptive expectations and cobweb phenomena. *The Quarterly Journal of Economics, 72*(2), 227–240.
- Roberts, M. J., & Schlenker, W. (2013). Identifying supply and demand elasticities of agricultural commodities: Implications for the US ethanol mandate. *American Economic Review, 103*(6), 2265–2295. https://doi.org/10.1257/aer.103.6.2265
- Williams, J. C., & Wright, B. D. (1991). *Storage and commodity markets*. Cambridge University Press.

## Lager am Jahresabsatz und Speicher-Übertrag (S125, S126, 100 Jahre, Seed 1, `run100-s125-s126.txt` mit `PRICE_DEBUG=1 GOODS_DEBUG=1`; vorher: `run100-s123-s124.txt`)

Ramon (30.10.2026), Karte „Was soll ich für Speicher und Jahresabsatz bauen?“, Option „Jahresabsatz
und Speicher-Übertrag“. Vorschläge: https://claude.ai/artifact/5kRZ2PkMXgx9rYhKf7VsgE
(Jahresabsatz) und https://claude.ai/artifact/XQbRSppNrZaXz6HzuGUk25 (Speicher). Die Marktleute messen
ihr Lager am Absatz eines Jahres statt eines Monats (S125). Was in den Speichern von Staat und Herren
über einem Jahresabsatz ihres Markts liegt, verkaufen die Verwalter bis hinunter zum Lagerboden
(S126). Jede Hälfte allein gemessen (`--sales-month`, `--no-carry-sale`; je 1 Thread). Der Lauf mit
beiden ausgeschaltet gibt denselben Fingerabdruck wie main, der Lauf „nur S125“ denselben wie die
Sonde A im Vorschlag. Neu im Lauf: „carry-over sold t“ in der Preiszeile. Grafiken:
https://claude.ai/artifact/1LQYuTH5ugLE9tsGkKF5NK

| Grösse | main (S123, S124) | nur Jahresabsatz (S125) | nur Speicher-Übertrag (S126) | beide |
|---|---|---|---|---|
| Menschen im Jahr 10 / 40 / 100 | 108'178 / 110'787 / 123'079 | 106'881 / 110'157 / 123'304 | 108'747 / 111'674 / 124'214 | 107'899 / 110'855 / 124'520 |
| Wachstum, Mittel Jahr 11–100 | +0,14 % | +0,16 % | +0,15 % | +0,16 % |
| Hungertote Jahr 1–10 / 11–30 / 31–100 | 8'073 / 1'825 / 11'841 | 9'679 / 1'767 / 13'216 | 7'516 / 1'775 / 11'500 | 8'395 / 1'543 / 10'615 |
| Verlassen die Karte, 100 Jahre | 4'010 | 2'892 | 3'894 | 3'395 |
| Ernte im Jahr 10 / 100 | 37'370 / 34'612 t | 37'452 / 37'723 t | 38'196 / 31'435 t | 38'212 / 32'888 t |
| Preis Korn nach Absatz, Jahr 10 / 40 / 100 | 5,91 / 2,77 / 1,05 Denar/kg | 8,75 / 6,24 / 4,48 | 4,93 / 1,14 / 0,52 | 6,54 / 1,58 / 0,48 |
| Median-Preis Korn / Rom im Jahr 100 | 1,15 / 4,55 Denar/kg | 4,53 / 14,82 | 0,63 / 3,97 | 1,05 / 7,81 |
| Taglohn p50, Jahr 1 / 40 / 100 | 13,19 / 9,75 / 4,70 Denar | 13,51 / 16,16 / 10,31 | 13,10 / 9,36 / 5,41 | 13,19 / 11,48 / 6,96 |
| Reallohn p10 / p50, Jahr 100 | 1,2 / 2,7 kg | 1,2 / 2,4 kg | 1,3 / 3,2 kg | 1,2 / 3,0 kg |
| Staats- und Herrenspeicher im Jahr 100 | 73'677 / 24'947 t | 109'299 / 36'086 t | 44'190 / 13'583 t | 56'511 / 19'628 t |
| Übertrag verkauft, Jahr 40 / 100 | – | – | 1'423 / 734 t | 1'274 / 902 t |
| Verdorben im Jahr 100, Anteil der Ernte | 19 % | 25 % | 16 % | 19 % |
| Steuer, 100 Jahre / Staatskasse im Jahr 100 | 153 / 217 Mio. Denar | 114 / 154 | 131 / 159 | 119 / 166 |
| Nicht gebucht | 0 | 0 | 0 | 0 |
| Tag gesamt, Mittel (1 Thread, 4 Läufe gleichzeitig) | 19,8 ms | 19,7 ms | 20,3 ms | 19,8 ms |

Was auffällt:

- **Der Speicher-Übertrag ist der Hebel.** Mit S126 verkaufen die Speicher jedes Jahr 500–1'400 t,
  die sonst liegen blieben. Im Jahr 100 leben 1'100–1'400 Menschen mehr als auf main, ab Jahr 31
  sterben 3–10 % weniger an Hunger, und die Speicher halten 58–76 kt statt 99 kt. Weniger verdirbt.
- **Der Jahresabsatz hält den Preis, allein kostet er Menschen.** Mit S125 allein bleibt der Preis
  18 Jahre beim Startpreis und liegt im Jahr 100 bei 4,48 Denar/kg. Dafür horten die Speicher 145 kt,
  ein Viertel der Ernte verdirbt, und es sterben mehr an Hunger (Jahre 1–10 +20 %, ab Jahr 31 +12 %).
- **Zusammen leben die meisten, und ab Jahr 31 hungern die wenigsten.** 124'520 Menschen im Jahr 100,
  10'615 Hungertote in den Jahren 31–100. In den Jahren 1–10 sterben mit beiden 879 mehr als mit S126
  allein: Der Jahresabsatz hält den Preis in den ersten zwei Jahren beim Startpreis.
- **Der Preis fällt, bis die Höfe weniger säen, und hält dann.** Mit beiden sinkt er bis etwa Jahr 80
  auf 0,43–0,49 Denar/kg und bleibt dort. Die Ernte sinkt von 38 auf 33 kt. Der Lohn fällt weniger als
  der Preis, der Reallohn in der Mitte steigt auf 3,0 kg. Das ist der Überschuss, den die Karte erntet:
  Die Nachfrage nach Korn ist in kg, nicht in Denar, und die Felder tragen nur Getreide (S72).
- **Rom bleibt teurer.** Mit beiden kostet Korn in Rom im Jahr 100 7,81 Denar/kg, über siebenmal so
  viel wie im Median. Warum, ist noch nicht untersucht.
- **Geprüft und verworfen (Sonden mit S125, nicht eingebaut).** Steuer in Geld über die Rationen
  hinaus (adaeratio) änderte wenig: Die Höfe haben bei der Ernte meist zu wenig Bargeld. Saat nur
  für den Teil, der nicht noch unverkauft auf Lager liegt, schadete: 110'301 Menschen im Jahr 100,
  18'949 Hungertote in den Jahren 31–100.
- Gleicher Fingerabdruck mit 1 und 3 Threads (5 Jahre); 77 Tests grün, 1 ausgelassen.

### Quellen zu S125, S126 (APA 7)

- Assenza, T., Delli Gatti, D., & Grazzini, J. (2015). Emergent dynamics of a macroeconomic agent based model with capital and credit. *Journal of Economic Dynamics and Control, 50*, 5–28.
- Blinder, A. S., & Maccini, L. J. (1991). Taking stock: A critical assessment of recent research on inventories. *Journal of Economic Perspectives, 5*(1), 73–96. https://doi.org/10.1257/jep.5.1.73
- Bobenrieth, E. S. A., Wright, B. D., & Zeng, D. (2013). Stocks-to-use ratios and prices as indicators of vulnerability to spikes in global cereal markets. *Agricultural Economics, 44*(1), 43–52. https://doi.org/10.1111/agec.12049
- Burke, M., Bergquist, L. F., & Miguel, E. (2019). Sell low and buy high: Arbitrage and local price effects in Kenyan markets. *The Quarterly Journal of Economics, 134*(2), 785–842. https://doi.org/10.1093/qje/qjy034
- Deaton, A., & Laroque, G. (1992). On the behaviour of commodity prices. *The Review of Economic Studies, 59*(1), 1–23. https://doi.org/10.2307/2297923
- Gouel, C., & Legrand, N. (2025). The role of storage in commodity markets: Indirect inference based on grain data. *Quantitative Economics, 16*(2), 705–747. https://doi.org/10.3982/QE2329
- Kryvtsov, O., & Midrigan, V. (2013). Inventories, markups, and real rigidities in menu cost models. *The Review of Economic Studies, 80*(1), 249–276.
- Miranda, M. J., & Helmberger, P. G. (1988). The effects of commodity price stabilization programs. *The American Economic Review, 78*(1), 46–58.
- Treadgold, W. (2014). Paying the army in the Theodosian period. In I. Jacobs (Hrsg.), *Production and prosperity in the Theodosian period*. Peeters.
- Williams, J. C., & Wright, B. D. (1991). *Storage and commodity markets*. Cambridge University Press.

## Kasse gibt Überschuss aus, Jahresplan der Höfe (S129, S130, 100 Jahre, Seeds 1 und 2, `run100-s129-s130.txt` mit `PRICE_DEBUG=1 GOODS_DEBUG=1`; vorher: main mit S127)

Ramon (31.10.2026): „gerne“ zur Karte „Soll ich Kasse und Jahresplan jetzt als S128 und S129 bauen?“,
Option „Beide bauen“ (die Namen haben inzwischen S128, darum S129 und S130). Vorschlag mit allen
Sonden: https://claude.ai/artifact/AEAe6gsk7cHjNNEo7i6TzQ. Die Staatskasse behält den Staatslohn des
letzten Jahres und die Restkosten offener Bauaufträge und zahlt, was darüber liegt, als öffentliche
Arbeit zum Taglohn aus, ein 52stel pro Woche, nach den Menschen der Märkte (S129). Höfe halten das
Geld für ihr Korn bis zur nächsten Ernte und für die Saat zurück, bevor sie Waren kaufen (S130).
Mit `--no-state-spend --no-food-plan` gleicher Fingerabdruck wie main (8 Jahre). Neu im Lauf:
„public works (S129)“ in der Geldzeile. Die vier Läufe liefen gleichzeitig mit je 1 Thread; die
Lauf-Datei ist Seed 1, danach mit 4 Threads und dem eingemischten main neu gerechnet (gleicher
Fingerabdruck).

| Grösse | main, Seed 1 | S129 + S130, Seed 1 | main, Seed 2 | S129 + S130, Seed 2 |
|---|---|---|---|---|
| Menschen im Jahr 10 / 40 / 100 | 107'966 / 112'119 / 127'073 | 108'222 / 111'830 / 129'908 | 108'015 / 111'944 / 126'609 | 108'815 / 113'008 / 132'885 |
| Wachstum, Mittel Jahr 11–100 | +0,18 % | +0,20 % | +0,18 % | +0,22 % |
| Hungertote Jahr 1–10 / 11–30 / 31–100 | 8'373 / 1'442 / 11'620 | 8'148 / 1'456 / 7'449 | 8'254 / 1'397 / 10'081 | 7'548 / 1'571 / 6'651 |
| Verlassen die Karte, 100 Jahre | 3'632 | 3'037 | 3'098 | 2'939 |
| Ernte im Jahr 10 / 100 | 38'329 / 32'591 t | 37'377 / 31'448 t | 38'315 / 33'165 t | 36'682 / 30'114 t |
| Gesät von der möglichen Fläche, Jahr 100 | 85 % | 79 % | 87 % | 75 % |
| Preis Korn nach Absatz, Jahr 10 / 40 / 100 | 6,54 / 1,55 / 0,45 Denar/kg | 6,59 / 1,52 / 0,89 | 6,52 / 1,52 / 0,32 | 6,67 / 1,53 / 1,10 |
| Preis nach Absatz, Jahre 61–100 tiefster / höchster | 0,40 / 0,69 | 0,72 / 0,89 | 0,31 / 0,65 | 0,82 / 1,10 |
| Median-Preis Korn / Rom im Jahr 100 | 0,13 / 2,71 Denar/kg | 0,12 / 6,66 | 0,08 / 2,27 | 0,15 / 4,86 |
| Taglohn p50, Jahr 1 / 40 / 100 | 13,37 / 11,46 / 6,59 Denar | 13,27 / 10,25 / 4,61 | 12,91 / 12,02 / 6,59 | 12,97 / 10,15 / 4,61 |
| Reallohn p10 / p50, Jahr 100 | 1,2 / 3,1 kg | 1,7 / 3,9 kg | 1,2 / 3,0 kg | 1,9 / 3,9 kg |
| Staats- und Herrenspeicher im Jahr 100 | 56'565 / 18'373 t | 28'890 / 8'262 t | 65'937 / 16'916 t | 19'301 / 4'514 t |
| Verdorben im Jahr 100, Anteil der Ernte | 19 % | 11 % | 20 % | 8 % |
| Kleidung fehlt im Jahr 100 / Preis Kleid | 64 % / 440 Denar | 55 % / 571 | 65 % / 338 | 52 % / 604 |
| Staatskasse im Jahr 100 | 161 Mio. Denar | 7,5 Mio. | 182 Mio. | 9,1 Mio. |
| Steuer / Staatslohn, 100 Jahre | 115 / 222 Mio. Denar | 196 / 198 | 97 / 153 | 263 / 131 |
| Öffentliche Arbeit, 100 Jahre (im Jahr 100) | – | 264 Mio. Denar, 58,6 Mio. Tage (4,6 Mio., 1,41 Mio. Tage) | – | 461 Mio., 90,6 Mio. Tage (6,8 Mio., 1,72 Mio. Tage) |
| Geld im Umlauf im Jahr 100 (davon Höfe / Marktleute) | 230 (89 / 74) Mio. Denar | 354 (169 / 80) | 190 (70 / 57) | 411 (187 / 101) |
| Neu geprägt / nicht gebucht | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| Tag gesamt, Mittel (1 Thread, 4 Läufe gleichzeitig) | 16,0 ms | 16,4 ms | 16,1 ms | 16,7 ms |

Was auffällt:

- **Weniger Hunger, mit beiden Seeds.** Ab Jahr 31 sterben 36 % (Seed 1) und 34 % (Seed 2) weniger an
  Hunger, in den Jahren 1–10 schon 3 % und 9 % weniger, weil der Jahresplan von Anfang an wirkt (die
  Kasse gibt erst ab dem zweiten Jahr aus). Im Jahr 100 leben 2,2 % und 5,0 % mehr Menschen.
- **Der Kornpreis bekommt einen Boden, ohne Preisregel.** Mit der öffentlichen Arbeit finden mehr
  angebotene Tage Arbeit, ein eigener Tag auf dem Feld kostet mehr, und die Höfe säen 79 % und 75 %
  statt 85 % und 87 % ihrer möglichen Fläche (S124). Es liegt und verdirbt weniger (Speicher von Staat
  und Herren 24–37 statt 75–83 kt, Verderb 8–11 % statt 19–20 % der Ernte), und der Preis nach Absatz hält in den Jahren 61–100
  zwischen 0,72 und 1,10 Denar/kg statt auf 0,31–0,45 zu fallen.
- **Die Kasse bleibt bei ihrer Reserve.** Statt 161–182 Mio. liegen im Jahr 100 7,5–9,1 Mio. in der
  Kasse; geprägt wird nichts. Das Geld wandert zu den Höfen (169–187 statt 70–89 Mio.), die es als
  Jahresvorrat für Korn halten. Die Steuer bringt mehr, weil das Steuerkorn teurer verkauft wird.
- **Weniger fehlende Kleidung, teurere Kleider.** Es fehlen 52–55 % statt 64–65 % der Kleidung; ein Kleid
  kostet im Jahr 100 571–604 statt 338–440 Denar.
- **Taglohn tiefer, Reallohn höher.** Der Taglohn in der Mitte liegt im Jahr 100 bei 4,61 statt
  6,59 Denar, der Reallohn in der Mitte bei 3,9 statt 3,0–3,1 kg, im ärmsten Zehntel bei 1,7–1,9 statt
  1,2 kg.
- **Rom wird teurer.** Korn kostet in Rom im Jahr 100 4,86–6,66 statt 2,27–2,71 Denar/kg; noch nicht
  untersucht (wie bei S125, S126).
- **Anders als die Sonde.** In der Sonde zählte die öffentliche Arbeit zum Staatslohn und damit zur
  Reserve des nächsten Jahres. Gebaut ist sie getrennt gebucht (die Statistik zeigt Sold und
  öffentliche Arbeit einzeln), die Reserve ist kleiner, und die Kasse gibt mehr aus: Seed 1 hat
  129'908 statt 132'250 Menschen, 7'449 statt 7'341 Hungertote ab Jahr 31 und einen Preis von 0,89
  statt 1,11 Denar/kg im Jahr 100.
- Gleicher Fingerabdruck mit 1 und 3 Threads (5 Jahre); 90 Tests grün, 1 ausgelassen (neu:
  `public_works_from_surplus`).

### Quellen zu S129, S130 (APA 7)

- Carroll, C. D. (1997). Buffer-stock saving and the life cycle/permanent income hypothesis. *The Quarterly Journal of Economics, 112*(1), 1–55. https://doi.org/10.1162/003355397555109
- Cato. (1934). *On agriculture* (W. D. Hooper & H. B. Ash, Übers.). Harvard University Press. (Original um 160 v. Chr.; Kap. 136 zum Erntelohn als Anteil am Korn)
- Comin, D., Lashkari, D., & Mestieri, M. (2021). Structural change with long-run income and price effects. *Econometrica, 89*(1), 311–374. https://doi.org/10.3982/ECTA16317
- Duncan-Jones, R. (1994). *Money and government in the Roman Empire*. Cambridge University Press.
- Erdkamp, P. (2005). *The grain market in the Roman Empire: A social, political and economic study*. Cambridge University Press.
- Foellmi, R., & Zweimüller, J. (2006). Income distribution and demand-induced innovations. *The Review of Economic Studies, 73*(4), 941–960.
- Hopkins, K. (1980). Taxes and trade in the Roman Empire (200 B.C.–A.D. 400). *The Journal of Roman Studies, 70*, 101–125. https://doi.org/10.2307/299558

## Steuergesetz Schritt 1: Zehnt, Grundsteuer, Kopfsteuer (S131, 100 Jahre, 14 Läufe, Seeds 1 und 2, `run100-s131-summary.txt` und `run100-s131-land-tax.txt` mit `PRICE_DEBUG=1 GOODS_DEBUG=1 FIELD_DEBUG=1`; vorher: main mit S129, S130)

Ramon (31.10.2026, Planungs-Thread „Regierungseinflüsse nach Vic3-Vorbild“): „steuern und haushalt
zuerst“, Karten D1 „Zehnt, Grundsteuer, Kopfsteuer“, D2 „Rückstand → Pfändung → Versteigerung“ und
„Bauen nach #100“; Plan https://claude.ai/artifact/12Sa2gxdKcWjYqJdMoSr8F, Abschnitt 4b. Je Steuer
sechs Stufen; Regeln in S131. Mit Zehnt „niedrig“ (10 %), ohne Geldsteuern und `--lord-money-old`
gleicher Fingerabdruck wie main (8 Jahre); gleicher Fingerabdruck mit 1 und 3 Threads (Grundsteuer
und Kopfsteuer „hoch“, 3 Jahre). Je Lauf eine Stufe einer Steuer, die anderen wie heute (Zehnt
niedrig, keine Geldsteuer); von den fünf Stufen ausser „niedrig“ beim Zehnt bzw. „keine“ bei den
Geldsteuern liefen „sehr niedrig“, „mittel“ und „sehr hoch“, mit Seed 2 nur „mittel“. Die Läufe
liefen zu viert gleichzeitig mit je 1 Thread. Neu im Lauf: Zeile „taxes (S131)“ (Summen seit Beginn).
„Geldsteuer bezahlt“ ist Grund- und Kopfsteuer in Geld, auch aus Pfändung und Versteigerung;
„gepfändet“ ist Geld und Korn zum Ankaufspreis (das Korn wird erst beim Verkauf aus dem Staatsspeicher
zu Geld); beides 100 Jahre, Denar.

**Stufen seit D3** (Ramon, 31.10.2026 09:56: „Oberste Stufe = historisch“): Zehnt und Grundsteuer 0 / 5 / 10 / 12 / 15 / 20 %. Die Läufe unten liefen noch mit den Platzhaltern davor (0 / 5 / 10 / 15 / 20 / 30 %): „mittel“ war 15 statt 12 %, „sehr hoch“ 30 statt 20 %. Ein Fünftel ist der höchste belegte Zehnt (osmanischer Zehnt, je nach Frucht ein Zehntel bis ein Fünftel; Wikipedia, 2026); „Zehnt hoch“ heute (15 %) entspricht dem Lauf „mittel“ unten, „Grundsteuer hoch“ dem Lauf „Grundsteuer mittel“.

| Lauf | Menschen J. 100 | Hungertote J. 31–100 | Höfe J. 100 | Preis J. 100 (Denar/kg) | gesät J. 100 | Geldsteuer bezahlt | gepfändet (Korn) | Versteigert / Domäne | abgeschrieben |
|---|---|---|---|---|---|---|---|---|---|
| Seed 1: Zehnt niedrig (10 %), wie heute | 129'969 | 7'792 | 17'616 | 0,84 | 81 % | 0 Mio. | 0 Mio. (0,0 kt) | 0 / 0 | 0,0 Mio. |
| Seed 1: Zehnt keine | 130'247 | 7'645 | 17'518 | 1,25 | 84 % | 0 Mio. | 0 Mio. (0,0 kt) | 0 / 0 | 0,0 Mio. |
| Seed 1: Zehnt mittel (15 %) | 127'654 | 8'269 | 17'295 | 0,97 | 74 % | 0 Mio. | 0 Mio. (0,0 kt) | 0 / 0 | 0,0 Mio. |
| Seed 1: Zehnt sehr hoch (30 %) | 121'015 | 8'791 | 16'287 | 0,55 | 70 % | 0 Mio. | 0 Mio. (0,0 kt) | 0 / 0 | 0,0 Mio. |
| Seed 1: Grundsteuer sehr niedrig (5 %) | 126'813 | 8'127 | 17'021 | 0,90 | 79 % | 200 Mio. | 207 Mio. (52,5 kt) | 82 / 139 | 2,2 Mio. |
| Seed 1: Grundsteuer mittel (15 %) | 126'720 | 8'768 | 16'769 | 0,87 | 75 % | 436 Mio. | 492 Mio. (134,5 kt) | 364 / 419 | 56,9 Mio. |
| Seed 1: Grundsteuer sehr hoch (30 %) | 120'397 | 9'489 | 15'908 | 0,79 | 70 % | 603 Mio. | 819 Mio. (241,0 kt) | 1239 / 1233 | 199,1 Mio. |
| Seed 1: Kopfsteuer sehr niedrig (2 Taglöhne) | 126'425 | 7'580 | 16'982 | 0,90 | 77 % | 97 Mio. | 52 Mio. (13,2 kt) | 28 / 66 | 0,9 Mio. |
| Seed 1: Kopfsteuer mittel (10 Taglöhne) | 128'300 | 8'088 | 17'386 | 0,87 | 76 % | 431 Mio. | 259 Mio. (68,1 kt) | 96 / 153 | 6,3 Mio. |
| Seed 1: Kopfsteuer sehr hoch (20 Taglöhne) | 122'957 | 8'273 | 16'547 | 1,31 | 72 % | 908 Mio. | 376 Mio. (99,2 kt) | 143 / 221 | 23,5 Mio. |
| Seed 2: Zehnt niedrig, wie heute | 133'573 | 7'145 | 18'034 | 1,02 | 77 % | 0 Mio. | 0 Mio. (0,0 kt) | 0 / 0 | 0,0 Mio. |
| Seed 2: Zehnt mittel | 132'226 | 7'333 | 17'916 | 0,86 | 76 % | 0 Mio. | 0 Mio. (0,0 kt) | 0 / 0 | 0,0 Mio. |
| Seed 2: Grundsteuer mittel | 126'845 | 8'869 | 16'956 | 0,97 | 72 % | 472 Mio. | 427 Mio. (117,3 kt) | 373 / 358 | 45,0 Mio. |
| Seed 2: Kopfsteuer mittel | 129'731 | 8'465 | 17'395 | 1,17 | 75 % | 493 Mio. | 181 Mio. (46,4 kt) | 73 / 94 | 6,5 Mio. |

Was auffällt:

- **Der Zehnt wirkt wie erwartet.** Ohne Zehnt 2 % weniger Hungertote ab Jahr 31, mit 15 % 6 % mehr
  (Seed 2: 3 %), mit 30 % 13 % mehr und 7 % weniger Menschen im Jahr 100; in den Jahren 1–10 sterben bei
  30 % 58 % mehr an Hunger. Ohne Zehnt verkauft der Staat weniger Korn, und der Preis im Jahr 100 liegt
  bei 1,25 statt 0,84 Denar/kg; bei 30 % säen die Höfe 70 statt 81 % ihrer Fläche.
- **Geldsteuern auf Höfe kommen zur Hälfte als Korn herein.** Bei der Grundsteuer zahlen die Höfe nur
  42–52 % in Geld, den Rest holt die Pfändung als Korn (52–241 kt in 100 Jahren). Der Grund ist der dünne
  Markt: Die Händler kaufen im Jahr nur einen kleinen Teil der Ernte, und die Höfe halten kaum Geld (im
  Jahr 2 zusammen rund 2 Mio. Denar, die Grundsteuer „mittel“ verlangt im ersten Jahr rund 37 Mio.).
  Was der Hof für die Steuer verkaufen will, findet am Markt keinen Käufer. Das passt zur Geschichte: Ein
  Staat mit wenig Geld im Umlauf zieht Steuern in Korn ein; Diokletians Steuer wurde in Naturalien
  erhoben (Jones, 1964), und Steuern in Geld setzen einen Markt voraus, der das Korn abnimmt (Hopkins, 1980).
- **Die Kopfsteuer trifft weniger hart.** Sie kommt zu 62–73 % in Geld herein, weil Lohn-, Händler- und
  reiche Haushalte Geld haben; Hungertote ab Jahr 31 −3 / +4 / +6 % bei 2 / 10 / 20 Taglöhnen (Seed 2
  bei 10: +18 %). Bei 20 Taglöhnen steigt der Kornpreis im Jahr 100 auf 1,31 Denar/kg.
- **Höfe wechseln den Besitzer.** Bei der Grundsteuer „sehr niedrig / mittel / sehr hoch“ werden in 100
  Jahren 82 / 364 / 1'239 Höfe versteigert und 139 / 419 / 1'233 fallen an die Domäne, von rund 17'600
  (1,3 / 4,4 / 14 %). Bei gut der Hälfte bietet niemand genug: In vielen Märkten hat kein Haushalt über
  ein Jahr Essen hinaus das Geld für Land. Ersteigert wird Boden im Mittel für 640–750 Denar je ha; den
  Deckel setzen meist die Rodungskosten, wo freies Land da ist.
- **Mehr Hunger mit jeder Steuer, aber nicht linear.** Grundsteuer: +4 / +13 / +22 % Hungertote ab Jahr
  31 (Seed 2 bei „mittel“: +24 %). Die Menschen im Jahr 100 streuen von Lauf zu Lauf um einige Tausend
  (Seed 1 und 2 ohne Änderung: 129'969 und 133'573), Unterschiede unter rund 2 % sind nicht sicher.
- **Alles gebucht.** Nicht gebucht 0 in allen Läufen; die Kasse gibt den Mehrertrag als öffentliche
  Arbeit (S129) wieder aus (im Jahr 100 7–20 Mio. Denar in der Kasse).
- **Pacht an Grundherren mit Hof.** Neu geht sie ins Hofgeld (`to_lord`). Gegenüber main (S129 + S130):
  Seed 1 129'969 statt 129'908 Menschen und 7'792 statt 7'449 Hungertote ab Jahr 31, Seed 2 133'573 statt
  132'885 und 7'145 statt 6'651. Mit `--lord-money-old` wie main.
- **Feldabstände (für die Zoomstufen, nur gelesen):** Im Jahr 100 liegen vom Feld 1,4 % auf der Hofkachel,
  7 % eine, 8 % zwei, 24 % 3–4, 26 % 5–6, 20 % 7–8 und 13 % mehr als 8 Kacheln weit; Median 8,4 km
  (Welt), 85 % der Höfe haben Felder 7 oder mehr Kacheln weg (`Grain::field_report`, `FIELD_DEBUG=1`).
- 91 Tests grün, 1 ausgelassen (neu: `taxes_arrears_seizure_auction`; `commands_read_back` und
  `save_plays_again` mit dem Gesetz-Befehl).

### Quellen zu S131 (APA 7)

- Besley, T., & Persson, T. (2014). Why do developing countries tax so little? *Journal of Economic Perspectives, 28*(4), 99–120. https://doi.org/10.1257/jep.28.4.99
- Clark, G. (2002). Land rental values and the agrarian economy: England and Wales, 1500–1914. *European Review of Economic History, 6*(3), 281–308. https://doi.org/10.1017/S1361491602000138
- Fullerton, D., & Metcalf, G. E. (2002). Tax incidence. In A. J. Auerbach & M. Feldstein (Hrsg.), *Handbook of public economics* (Bd. 4, S. 1787–1872). Elsevier. https://doi.org/10.1016/S1573-4420(02)80009-4
- Gesetz über die Zwangsversteigerung und die Zwangsverwaltung (ZVG) vom 24. März 1897, § 85a (Deutschland). https://www.gesetze-im-internet.de/zvg/__85a.html
- Hopkins, K. (1980). Taxes and trade in the Roman Empire (200 B.C.–A.D. 400). *The Journal of Roman Studies, 70*, 101–125. https://doi.org/10.2307/299558
- Jones, A. H. M. (1964). *The later Roman Empire, 284–602: A social, economic and administrative survey*. Blackwell.
- Wikipedia. (2026). *Ashar*. Abgerufen am 31. Oktober 2026, von https://en.wikipedia.org/wiki/Ashar

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
| Nächstes Feld | `Grain::near_field(hh)`, Godot `house_fields()` | Mitte der Feinkachel mit eigenem oder gepachtetem Feld des Hofs, die der Hofkachel am nächsten liegt (Welt-m je Hausplatz, −1 ohne Feld); für den Weg Haus → Feld (Bauplan B Schritt 4, Ramon 31.10.2026 „Felder bleiben, Weg schneller“; Sonde `/mnt/project-files/sim-probes/naehere-felder/BEFUND.md`: nähere Felder lassen die Menschen verhungern, weil Felder 23,8-fach vergrössert sind) |

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
| Taglohn (S114) | am ersten Tag 3 kg Getreide zum Startpreis, in Denar; bewegt sich jede Woche um den Anteil offener gegen liegen gebliebene Tage, höchstens 1/20; niemand arbeitet unter dem Essen seines Haushalts bei 290 Arbeitstagen; Höfe planen mit dem Lohn, über 52 Wochen geglättet | Preisedikt VII.1a, 25 Denar mit Kost; Mortensen & Pissarides 1994, Lewis 1954; Zahlen frei |
| Startpreis (S112: kein Grundpreis mehr) | 8,75 Denar/kg am ersten Tag, auch draussen (S121) | Preisedikt, modius castrensis 1,5–2 modii italici |
| Staatslohn nur für Soldaten, Offiziere, Beamte (S110) | 25 Denar pro Arbeitstag für alle Erwachsenen des Haushalts | S76, Preisedikt |
| Waren (S105) | Grundpreise Eisen 20, Werkzeug 60 Denar/kg; Marktleute holen jede Woche beim günstigsten Nachbarn, Ware kommt am selben Tag an | frei gewählt; Wolle, Kleidung, Keramik nach Edikt |
| Schafe (S106) | 1 pro ha Weide, Weide = Grasland/Ackerland der Zelle mal Feldfläche, höchstens 5 pro Kopf, 1 kg Wolle, Schur Tag 135 | Treacher, Sierra Mágina; Rest frei |
| Handwerk (S107) | Weber 1 Stück in 30 Tagen aus 1 kg Wolle, Schmied 1,5 kg aus 1,25 kg Eisen, Töpfer 15 kg pro Tag; Wechsel ab 10 % mehr Erlös; Start mit 60 Tagen Staatslohn als Geld | Spinnzeit nach Tools and Textiles, Töpferlohn Edikt VII.29; Rest frei |
| Kleidung (S107) | 1,5 Stück pro Kopf im Jahr, Kind halb; Ziel 1 Stück pro Kopf, bis dreifach für Reiche; selbst gemacht bis zur Hälfte der Arbeitstage | Cato 59; Rest frei |
| Werkzeug (S108) | 2 kg pro ha unter Getreide, 10 % Verschleiss im Jahr, ohne Werkzeug 70 % Arbeit | frei gewählt |
| Keramik (S109) | 5 kg Geschirr pro Haushalt, 100 % Verschleiss; Fässer 1 kg Ton für 3 kg Getreide, 4 % Verschleiss; ohne Fass 12 % Verderb | Peña 2007 (Lebensdauer dolium); Rest frei |
| Leute einstellen (S111, S117) | Haushalte: 30 % des Budgets über dem Grundbedarf (S117) für Arbeit zum Taglohn; Marktleute 2 % im Monat ihres Bargelds über 180 Tagen Getreide und 90 Tagen Waren | frei gewählt |
| Konsumfunktion (S117) | Tabelle nach Carroll (1997), gelöst mit endogenen Gitterpunkten (Carroll, 2006): Risikoaversion 2, Geduld 0,85 im Jahr, dauernde Schocks 10 % im Jahr, vorübergehende 30 % im Monat, ein Monat ohne Einkommen 1 in 200, kein Zins; übliches Einkommen über 12 Monate geglättet; Essensgeld für 60 Tage bleibt | Geduld so, dass ein Geschenk von drei Monatseinkommen zur Hälfte im Jahr ausgegeben ist (Fagereng u. a., 2021); Rest frei |
| Budget über dem Grundbedarf (S117) | 50 % Schweinefleisch (höchstens 20 kg pro Erwachsenen im Jahr), 20 % mehr Kleidung (bis dreifach), 30 % Dienste | frei gewählt; mit dem Einkommen wandernde Anteile (Comin u. a., 2021) brauchen antike Werte |
| Schweinemast (S118) | 5 kg Getreide pro kg Fleisch, höchstens 60 kg Fleisch pro Kopf des Hofs im Jahr, 60 kg pro Schwein; Fleisch ersetzt kein Getreide in der Nahrung | Startpreis Edikt IV.1a; Futter frei (Bartnik, 2023: keine Zahl) |
| Staatskorn (S119) | Monatsbedarf der Staatsdiener aus dem Staatsspeicher ihres Markts, zum Ankaufspreis vom Lohn abgezogen | Jones 1964 (annona militaris); Rest frei |
| Staatslohn aus der Kasse (S94) | zuerst aus dem Bargeld der Kasse, der Rest neu geprägt | S95 (leere Kasse: nachprägen); Preise folgen der Geldmenge noch nicht |
| Steuer | 10 % der Ernte, als Korn in den Staatsspeicher beim Markt; verkauft nur zum üblichen Preis, das Geld in die Staatskasse (S115) | S70 offen; sizilischer Zehnt. **Hinweis:** Italien zahlte bis Diokletian keine Grundsteuer. |
| Pacht | ein Drittel der Ernte, als Korn in den Speicher des Grundherrn beim Markt; verkauft nur zum üblichen Preis (S115) | S69 offen |
| Grundherr eines Pacht- oder Gutshofs | ein Senator oder Ritter per Zufall | S69 offen |
| Brache | Zweifelderwirtschaft: 50 % der Felder unter Getreide; Brache braucht keine Arbeit | GRAIN-NUMBERS 2; Pflügen der Brache nicht belegt |
| Steuer und Pacht mit Saatgut | auf die Ernte abzüglich der Saat | frei gewählt |
| Vorrat und Kauf | Höfe behalten Nahrung bis zur nächsten Ernte plus 60 Tage; andere kaufen unter 30 Tagen bis 60 Tage | frei gewählt |
| Esel pro Hof | jeder Familien- und Pachthof hat einen | GRAIN-NUMBERS-Vorschlag |
| Markt (S112) | Preis läuft 1/30 pro Tag auf üblichen Preis × Lagerpfad (Zins 12 % + Verderb 4 % im Jahr) × Wurzel aus (90 + 7) / (Lagertage + 7); der übliche Preis steigt unter 30 Tagen Lager und sinkt ab 180 Tagen, höchstens 1/365 am Tag; Spanne ±10 %, Händlerbargeld zum Start für 60 Tage | Lagermodell (Williams & Wright 1991), Händler mit Lager (Ho & Stoll 1981), Band wie Lengnick 2013; Zahlen frei, Zins aus dem Gedächtnis (Quelle prüfen) |
| Märkte ausserhalb (S98) | Preis draussen = Startpreis ± 10 %, fest, 500 km hinter dem Rand; pro Woche ein Viertel des Lagers hinaus oder eine Woche Verkauf herein; an Tormärkten ist der übliche Preis mindestens der Preis draussen minus Fracht (S114) | frei gewählt; der einzige feste Preis in Denar |
| Verlassene Höfe (S103) | Felder nach zwei Aussaaten ohne Haushalt zurück ins freie Land; Vorrat bleibt beim Hof | frei gewählt, zwei Jahre wie Lex Manciana |
| Grundherrschaft (S102) | an die Verwandten, zu denen die Leute zogen, sonst an den ersten abgeteilten Sohn, sonst (auch beim Verlassen der Karte) an den Staat | frei gewählt; bona vacantia |
| Säen nach Preis (S99, S114) | eigener Bedarf plus 25 % Reserve, soweit der Speicher ihn nach der nächsten Ernte nicht deckt (S103); der Rest voll, wenn der Erlös pro Hektar die Lohnkosten deckt (geglätteter Lohn mal Anteil eingestellter Tage), sonst nicht | frei gewählt |
| Lagergrenze der Marktleute (S100) | kaufen nur bis 180 Tage Absatz im Lager | frei gewählt |
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
| Märkte draussen (S121) | eine normale Ernte ernährt genau die Menschen draussen (mit dem Verderb des halben Jahres); kein Wetter; sie säen nicht mehr für den Markt, wenn das Korn teuer ist; Nachfrage linear, Elastizität −0,065, zwischen halbem und anderthalbfachem Bedarf; Marktleute draussen ohne Geldgrenze; Waren weiter zum festen Preis (S98) | HYDE 3.3 für die Menschen; Roberts & Schlenker 2013 für die Elastizität; Rest frei gewählt |
| Lagerboden (S123) | Erwartung aus dem Preis der letzten drei Jahre, ohne Jahreszeit; Boden = Erwartung minus Zins und Verderb eines Jahres (16 %); nur Getreide | Nerlove 1958 für die Form; Gedächtnis frei gewählt; Zins wie S112 |
| Saat nach Preis (S124) | mindestens die Hälfte des Eigenbedarfs; Markt verlässlich, wenn Käufer an höchstens 5 % der Tage nichts fanden; der Weg zum Markt kostet nichts | frei gewählt |
| Lager am Jahresabsatz (S125) | Absatz über ein Jahr geglättet (vorher 30 Tage) | frei gewählt nach dem Lagermodell, das in Jahren rechnet (Gouel & Legrand 2025) |
| Speicher-Übertrag (S126) | Übertrag ist, was in den Speichern eines Markts über dessen Absatz eines Jahres liegt; verkauft bis zum Lagerboden (S123) | frei gewählt nach dem Lagermodell (ein Lager trägt zum erwarteten Preis nur bis zur nächsten Ernte) |
| Kasse gibt aus (S129) | Reserve = Staatslohn des letzten vollen Jahres (Sold und Bauplätze, einmal im Jahr gezählt) plus Restkosten der offenen Bauaufträge zum heutigen Taglohn; vom Rest ein 52stel pro Woche; verteilt nach den Menschen der Märkte; erst ab dem zweiten Jahr; die Arbeit baut nichts | frei gewählt; dass der Staat fast alles ausgab: Hopkins 1980, Duncan-Jones 1994 |
| Jahresplan der Höfe (S130) | nur Höfe; Korn bis zur nächsten Ernte plus RESERVE_DAYS und die noch zu säende Saat, zum Verkaufspreis der Marktleute | frei gewählt nach Erdkamp 2005 und Carroll 1997 |
| Steuergesetz (S131) | Kopfsteuer 0/2/5/10/15/20 Taglöhne je Erwachsenen (Zehnt und Grundsteuer 0/5/10/12/15/20 % sind entschieden, D3); Kopfsteuer ohne Hof am 1. Januar; Pfändung nach einem Jahr und einem Monat, Versteigerung oder Abschreibung nach zwei Jahren und einem Monat; Mindestgebot halber Wert; 12 % Zins; Bieter behalten ein Jahr Essen; Pfändung bis zum ganzen Rückstand; Steuer vor Korngeld, Familie bleibt als Pächterin | Stufen der Kopfsteuer noch offen (Vorschlag des Planungs-Threads 0/1/2/4/6/9 nach England 1377/1381 und Russland); Mindestgebot nach § 85a ZVG; Ertragswert nach Clark 2002; die übrigen frei gewählt bzw. Vorschläge des Planungs-Threads |

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
- **Die Geldmenge wuchs** bis S110 um rund 95 Mio. Denar im Jahr (S94 Schritt 1): Staatslohn wurde
  geprägt, die Steuer in Geld (S104) holte nur etwa 6 % zurück. Seit S110 prägt der Staat
  fast nichts mehr, und seine Kasse wächst. Ohne Wirkung auf die
  Preise; eine Preisregel gibt es nach S95 nicht. Über 100
  Jahre verschwand vor S97 die Hälfte des geprägten Geldes mit aufgelösten Haushalten; seit
  S97 geht es an Verwandte oder die Staatskasse.
- **Mit Brache bremst das Land** (0,16 % im Jahr über 100 Jahre). Wie stark, hängt am
  rodbaren Land und an der Brache; beides sind Platzhalter.
