# Lauf „grain“: Höfe, Markt, Getreidehandel und Fusswege (S69–S76)

**Stand:** 27.10.2026, Cloud-Container mit 4 Kernen · **Status:** `implementiert` (Prototyp). Die Messung auf dem Mac steht noch aus.

Die Getreidewirtschaft läuft neben dem Personen-Prototyp ([run-people](../run-people/README.md))
mit denselben rund 117'000 Menschen. Sie ersetzt die Nahrung K aus S35: Gesundheit,
Heirat und Wanderung hängen jetzt daran, was jeder Haushalt wirklich gegessen hat.
Plan und Zahlen: [GRAIN.md](../GRAIN.md), [GRAIN-NUMBERS.md](../GRAIN-NUMBERS.md).

```
cd sim && cargo run --release --bin grain -- --years 100 [--seed S] [--threads N] [--clear-pct P]
GRAIN_DEBUG=1 …   # zusätzlich die grössten Märkte und Hofgrössen pro Jahr
```

Dateien: `sim/src/grain.rs` (alles), `sim/src/bin/grain.rs` (Lauf), Haken in
`sim/src/people.rs` (`Econ`: gegessen pro Haushalt, freies Land und Nahrung pro Kopf pro
Region). `run100.txt` ist die ganze Ausgabe des Laufs unten, `run50-noclear.txt` der
Vergleich ohne Rodung.

## Was gebaut ist

| Teil | Umsetzung | Entscheidung |
|---|---|---|
| **Höfe** | Ein Hof pro Bauernhaushalt beim Start: Familienhof (Bauern), Pachthof (Pächter, Pacht an einen Grundherrn) und Gutshof (Unfreie, alles gehört dem Grundherrn, einem Senator oder Ritter). Tagelöhner auf dem Land haben keinen Hof und leben im Zelt. Wird ein Hof frei (Familie ausgestorben oder weggezogen), zieht automatisch ein Haushalt aus den Zelten derselben Region ein. Neue Höfe baut nur der Spieler; den gibt es im Prototyp noch nicht. | S69 |
| **Felder** | Fläche pro Hof in echter Grösse (S51). Land pro 25-km-Zelle: HYDE-Ackerland 200 im Massstab 1 : 566,5, danach rodbares Land mit schlechterem Ertrag. Ein Hof bestellt, was seine Erwachsenen übers Jahr und alle Hände in der Ernte schaffen, mindestens aber, was den Haushalt ernährt. Wächst die Familie, nimmt sie bei der Aussaat freies Land und rodet dazu. | S73 |
| **Ernte und Saisonarbeit** | Aussaat und Ernte sind Ereignisse pro Hof (Erntetag nach Breite, Höhe und Hof gestreut). Was die Familie im Fenster nicht schafft, sucht der Hof an der wöchentlichen Arbeitsbörse der Region: zuerst Leute aus den Zelten, dann Höfe mit freien Händen. Lohn in Getreide. Fehlen Hände, bleibt ein Teil der Ernte auf dem Feld oder ein Teil des Feldes ungesät. | S72 |
| **Speicher** | Getreide liegt im Hofspeicher, im Vorrat jedes Haushalts und im Lager jedes Markts, in ganzen kg. Steuer geht beim Ernten ab. Kein Verderb (keine Quelle). | S72 |
| **Markt** | Ein Markt pro 100-km-Region, am grössten Ort nach Hanson, sonst an der Zelle mit den meisten Menschen (1'783 Märkte). Lager, Bargeld der Händler am Markt und ein Preis, der jeden Tag gedämpft auf einen Zielpreis aus der Lagerreichweite zuläuft. Ankauf 10 % unter, Verkauf 10 % über dem Preis. Der Markt kauft nur, so weit sein Bargeld reicht; was er nicht nimmt, trägt der Bauer wieder heim. | S70, S22 |
| **Träger** | Jede Fahrt zum Markt ist eine echte Person des Haushalts (zuerst ein Mann 15–60) mit Last und Tempo nach ORBIS und Preisedikt: Familien- und Pachthof mit Esel (97 kg, 30 km/Tag), Gutshof mit Ochsenkarren (388 kg, 12 km/Tag), ohne Hof zu Fuss (30 kg pro Erwachsenem, 20 km/Tag). Die Reise ist ein Ereignis mit Ankunftstag, kein Schritt pro Tag. Wer im Marktort wohnt, kauft sofort. | S70, S76 |
| **Händler** | Erwachsene mit Beruf Händler. Sie kennen höchstens 32 Märkte (die billigsten Wege über Land mit Wagen, über See mit Schiff) mit Preisen, die so alt sind wie die Reise von dort. Einmal pro Woche: ausführen (hier kaufen, dort verkaufen) oder einführen (leer hin, dort kaufen, hier verkaufen), wenn die Marge nach Fracht über 10 % liegt. Fracht nach Preisedikt (Wagen 0,035 Denar pro kg·km) und ORBIS (See ≈ 0,001). Wo sie fahren, wird gezählt (Handelswege, Seewege). | S71 |
| **Hunger** | Jeder Haushalt isst einmal im Monat aus seinem Vorrat. Der Anteil, den er bekommt, treibt die Gesundheit (S64) und damit Tod und Geburt. Wer zu wenig hat, kauft; wer nichts hat, bettelt am Markt und stiehlt dann von einem Hof der Region. Haushalte, die weniger als 80 % bekommen, ziehen in die Nachbarregion mit der meisten Nahrung pro Kopf oder verlassen die Karte (S66). | S69, S71 |
| **Geld** | Der Staat hat unbegrenzt Geld (S76): Wer weder Bauer noch Händler ist, bekommt den Taglohn des Preisedikts (25 Denar) vom Staat. Bauern bekommen Geld nur für verkauftes Getreide. | S76 |
| **Fusswege** | Jeder Markt hat ein Wegfeld über seine Region auf dem Feinraster (Kachelebene 7, ≈ 1,56 km echt). Die Gänge zum Markt nutzen Zellen ab (Helbing 1997), die Abnutzung zerfällt mit einer Halbwertszeit von einem Jahr. Ab einer Schwelle wird eine Zelle Trampelpfad, dann Weg (mit Hysterese); beides macht das Gehen billiger, so dass die nächsten Gänge dem Pfad folgen. | S70 |

## Ergebnis (100 Jahre, Seed 1)

| Jahr | Menschen | Wachstum | Hungertote | ausgewandert | Höfe | in Zelten | Ernte t | Ernte verloren t | verkauft t | Handel t | Preis Rom (Denar/kg) | Trampelpfade / Wege (Zellen) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 115'095 | −1,46 % | 348 | 263 | 21'115 | 14'184 | 47'347 | 777 | 4'598 | 7'298 | 19,9 | 2'647 / 102 |
| 2 | 115'649 | +0,48 % | 669 | 976 | 20'719 | 13'886 | 47'345 | 865 | 5'555 | 8'470 | 18,5 | 9'760 / 658 |
| 10 | 114'762 | +0,07 % | 200 | 252 | 19'819 | 6'336 | 48'203 | 3'295 | 2'566 | 1'269 | 2,9 | 18'619 / 1'719 |
| 20 | 116'236 | +0,15 % | 116 | 103 | 18'404 | 2'885 | 50'977 | 3'595 | 2'943 | 1'357 | 3,1 | 19'780 / 1'864 |
| 30 | 117'524 | +0,20 % | 83 | 77 | 17'190 | 1'494 | 52'496 | 4'317 | 3'067 | 1'648 | 2,7 | 19'814 / 1'899 |
| 50 | 127'034 | +0,36 % | 76 | 61 | 15'044 | 385 | 55'236 | 4'672 | 3'069 | 1'471 | 3,7 | 19'513 / 1'932 |
| 70 | 135'657 | +0,42 % | 57 | 64 | 13'465 | 149 | 58'219 | 5'246 | 3'018 | 1'490 | 3,9 | 19'001 / 1'900 |
| 100 | 149'906 | +0,35 % | 63 | 60 | 11'690 | 30 | 62'706 | 5'350 | 2'961 | 1'369 | 3,8 | 17'964 / 1'825 |

**Was emergent passiert:**
- **Die ersten 30 Jahre wächst fast nichts (−0,1 bis +0,2 % im Jahr).** Es bremsen die
  Landlosen: Wer im Zelt lebt, findet nur in Aussaat und Ernte und auf Höfen mit zu wenig
  Händen Arbeit, bekommt im Mittel nur 60–75 % seiner Nahrung, wird krank, stirbt oder
  wandert ab. Von 14'000 Menschen in Zelten sind nach 30 Jahren 1'500 übrig.
- **Danach wächst die Bevölkerung wieder mit 0,3–0,5 % im Jahr**, wie ohne Getreide.
  Getreide ist dann nirgends knapp: Die Höfe ernten etwa doppelt so viel, wie gegessen
  wird, weil Brache und Missernten noch fehlen (S72, S76; der Ertrag ist schon ohne Saat
  gerechnet) und weil Familien Land roden können (S73). Der Preis liegt fast überall am unteren Anschlag (2,2 Denar/kg).
- **Rom wird über Händler versorgt.** Im ersten Jahr steht der Preis dort bei 20 Denar/kg
  (2,3 × Grundpreis), Händler bringen 7'000 t aus billigen Regionen, nach drei Jahren ist
  der Preis bei 7 und danach bei 3–4 Denar/kg. Eine Sonderregel für Rom gibt es nicht (S72).
- **Höfe werden weniger, aber grösser.** Haushalte teilen sich im Personen-Prototyp nie
  (Kinder bleiben, die Braut zieht ein), darum wachsen sie, und frei gewordene Höfe finden
  ohne Landlose keinen neuen Haushalt.
- **Fusswege:** Nach etwa 10 Jahren stehen rund 18'000 Feinraster-Zellen als Trampelpfad
  und 1'700 als Weg. Sie bündeln sich auf den Linien zu den Märkten und bleiben danach
  stabil.

**Ohne Rodung** (`--clear-pct 0`, nur HYDE-Ackerland, `run50-noclear.txt`) bindet das
Land: Die Bevölkerung fällt in 20 Jahren von 117'000 auf etwa 93'000 und bleibt dort
(−0,1 bis +0,2 % im Jahr), weil in vielen Zellen HYDE viel weniger Acker als Menschen
hat (Median 0,73 ha Acker pro Landbewohner, 25 % unter 0,18 ha).

**Antwort auf die Frage nach 0,1 % im Jahr:** Mit Rodung wird das Wachstum nur
vorübergehend gebremst; über 100 Jahre sind es 0,25 % im Jahr (117'000 → 150'000).
Ohne Rodung bleibt die Bevölkerung bei 0 %. Wie viel Land gerodet werden kann (S73),
entscheidet also über das Wachstum. Mit Brache (S76, später) stünde nur etwa die Hälfte
der Felder unter Getreide.

## Tempo und Speicher (4 Cloud-Kerne)

| Grösse | Wert |
|---|---|
| Aufbau Getreide | 70 ms (Marktgraph mit 32 Nachbarn pro Markt) |
| **Getreide pro Tag, Median / Mittel** | **1,44 ms / 2,0 ms** (Ziel 1,5 ms) |
| Getreide pro Tag, 95 % / 99 % | 2,8 ms / 18,9 ms |
| Ganzer Tag mit Menschen, Median / 95 % / 99 % | 4,6 / 11,8 / 22,3 ms |
| Speicher nach 100 Jahren | 337 MB (Menschen allein 184 MB) |
| Determinismus | gleicher Fingerabdruck mit 1 und 4 Threads; Test `grain::tests::deterministic_fingerprint` |

Pro Tag im Mittel: Reisen (Ankunft, Rückkehr) 0,24 ms, Arbeitsbörse 0,31, Märkte und
Nachrichten 0,21, Essen und Kaufen 0,34, Händler 0,06, Fusswege 0,34, Aussaat und Ernte
0,02. Einmal im Monat zählt die Getreidewirtschaft die Haushalte neu: 15 ms an einem Tag.
Dieser Tag macht das 99-%-Perzentil aus; er sollte als Nächstes über den Monat verteilt
werden. Der langsamste Tag (114 ms an Tag 1'281) ist noch nicht geklärt.

Wie das Budget gehalten wird: Reisen sind Ereignisse, Felder werden nur bei Aussaat und
Ernte angefasst, Essen läuft für 1/30 der Haushalte pro Tag, Händler für 1/7, Fusswege
werden für 1/90 der Märkte pro Tag abgelaufen; ein Wegfeld wird nur neu gerechnet, wenn
sich eine Pfadstufe geändert hat (Dial-Warteschlange über 64 × 64 Zellen). Haushalte liegen
in Arrays nach ID statt in Hashtabellen.

## Platzhalter (nicht entschieden)

| Wert | Platzhalter | Grundlage |
|---|---|---|
| Ertrag | 5,5 : 1 auf offenem Land, bis 3 : 1 mit Land über 1500 m; gerodetes Land 3 : 1 | Spurr über Devereaux; keine Boden- und Hangdaten auf dem 25-km-Raster |
| Rodbares Land | alles nutzbare Land ausser HYDE-Acker (nicht kahl, Schnee, über 1500 m), 0,5 ha pro Erwachsenem und Jahr | S73 offen; Landbedeckung fehlt |
| Arbeit in Aussaat / Ernte | 25 % / 30 % der 70 Tage pro ha, je in 40 Tagen; in den Spitzen arbeiten alle von 10–65 | GRAIN-NUMBERS: „Verteilung offen“ |
| Wer arbeitet | übers Jahr Erwachsene 15–60 | frei gewählt |
| Taglohn | 3 kg Getreide | Preisedikt VII.1a, 25 Denar mit Kost |
| Grundpreis | 8,75 Denar/kg | Preisedikt, modius castrensis 1,5–2 modii italici |
| Staatslohn für alle ausser Bauern und Händlern | 25 Denar pro Arbeitstag | S76 (Staat hat unbegrenzt Geld), Preisedikt |
| Steuer | 10 % der Ernte, verlässt vorerst das System | S70 offen; sizilischer Zehnt. **Hinweis:** Italien zahlte bis Diokletian keine Grundsteuer. |
| Pacht | ein Drittel der Ernte, bei Verkauf an den Grundherrn | S69 offen |
| Grundherr eines Pacht- oder Gutshofs | ein Senator oder Ritter per Zufall | S69 offen |
| Vorrat und Kauf | Höfe behalten Nahrung bis zur nächsten Ernte plus 60 Tage; andere kaufen unter 30 Tagen bis 60 Tage | frei gewählt |
| Esel pro Hof | jeder Familien- und Pachthof hat einen | GRAIN-NUMBERS-Vorschlag |
| Markt | Preis läuft 1/30 pro Tag auf Grundpreis × 90 Tage / Lagerreichweite (0,25–8-fach), Spanne ±10 %, Händlerbargeld zum Start für 60 Tage | frei gewählt, EU5-ähnlich |
| Händler | Marge über 10 %, Last 388 kg, Startgeld 5'000 Denar, Leerfahrt halbe Fracht | frei gewählt |
| Nachrichten | Preise anderer Märkte kommen mit der Reisezeit verspätet an | frei gewählt |
| Landlose | Almosen 30 % des Bedarfs vom Markt, Diebstahl mit 5/16 pro Monat (40 kg); zuerst eingestellt | S69 offen |
| Not (S66) | weniger als 80 % gegessen | frei gewählt |
| Fusswege | Halbwertszeit 360 Tage, Pfad ab ≈ 140, Weg ab ≈ 700 Gängen im Jahr, Kosten 80 % / 65 %; Ablauf alle 90 Tage | Helbing 1997, Werte frei |
| Startvorräte | Höfe bis zur Ernte + 60 Tage, Märkte 240 Tage ihrer Käufer, Haushalte 1 Monat, Zelte 3 Monate | damit der Start im Januar kein Artefakt ist |
| Erntetag | Mitte Juni bei Rom, 2 Tage später pro 100 km Nord, ± 7 Tage pro Hof; Aussaat Ende Oktober | frei gewählt |

## Nicht gebaut

- **Saatgut, Brache, Missernten, Verderb** (S72, S76: später).
- **Neue Höfe und Strassen durch den Spieler** (S69, S74): Landlose können nur frei
  gewordene Höfe übernehmen.
- **Neue Märkte, Verödung, Elendsviertel** (S75): Es gibt genau einen Markt pro Region.
- **Wirkung der Handelswege**: Der Verkehr der Händler wird pro 25-km-Zelle gezählt, macht
  die Fahrt aber noch nicht billiger. Flüsse fehlen im Marktgraph.
- **Felder als Kacheln**: Felder sind eine Fläche pro Hof, noch nicht auf dem Feinraster
  verteilt; dafür fehlen Boden und Hang pro Kachel.

## Was auffällt und zu klären ist

- **Haushalte aus nur Kindern oder Alten.** Etwa 17 % der Höfe haben beim Start niemanden
  zwischen 15 und 60, unter anderem weil die Starthaushalte Fünferblöcke aus der Zellenliste
  sind und Bräute wegziehen. Diese Höfe stellen jetzt Tagelöhner ein; im Personen-Prototyp sollten
  Waisen und Alte zu Verwandten ziehen.
- **Arbeitslose Landlose.** Arbeit gibt es fast nur in Aussaat und Ernte, darum hungern
  die Zelte und verschwinden in 30 Jahren fast ganz. Ob das so gewollt ist, hängt an
  S69 (Arbeit, Betteln, Stehlen) und S74 (der Spieler baut Höfe).
- **Rodung bestimmt das Wachstum.** Siehe oben.
