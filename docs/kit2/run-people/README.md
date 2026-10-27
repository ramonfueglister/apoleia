# Lauf „people“: Einzelpersonen mit Geburt, Ehe, Tod und Wanderung (S50–S67)

**Stand:** 27.10.2026, Cloud-Container mit 4 Kernen. Die Messung auf dem Mac steht noch aus.

Der Prototyp simuliert rund 117'000 Menschen einzeln als Entities im Rust-Kern
(`bevy_ecs` 0.20), jeden Tag über 100 Jahre. Geburt, Ehe, Tod, Gesundheit, Umzug und
Auswanderung folgen den Entscheidungen S62–S67. Was diese Entscheidungen offenlassen,
ist im Code als `PLACEHOLDER` markiert (siehe unten). Bedürfnisse, Bekanntschaften,
Reisen und Berufswahl bleiben Lastplatzhalter.

```
cd sim && cargo run --release --bin people -- --years 100 [--seed S] [--threads N]
```

Dateien: `sim/src/people.rs` (Menschen und Systeme), `sim/src/life.rs` (Sterbetafel,
Fruchtbarkeit, Wartezeiten, Kalender), `west3.py` (rechnet die Sterbetafel nach),
`run100.txt` (vollständige Ausgabe des Laufs unten).

## Wie es gebaut ist und warum

| Baustein | Umsetzung | Vorbild, Quelle |
|---|---|---|
| **Ereigniskalender statt Würfeln pro Tag** | Jeder Mensch zieht den Zeitpunkt seines Todes (verheiratete Frauen auch der nächsten Geburt) einmal aus einer stückweise konstanten Hazardrate (Umkehrung der kumulierten Rate, ein Zufallswert). Das Ereignis liegt in einem zweistufigen Timing-Wheel: 360 Tagesfächer plus ein Fach pro späteres Jahr, Einfügen und Entnehmen in O(1). Ein Tag fasst nur die Menschen an, die an diesem Tag ein Ereignis haben (≈ 40 pro Tag, 0,1 ms). Ändert sich etwas, das die Rate ändert (Gesundheitsband, Heirat, Verwitwung), wird das alte Ereignis über einen Generationszähler ungültig und neu gezogen. Weil die Raten gedächtnislos sind, ist das exakt. | Modgen/OpenM++ von Statistics Canada: Zeitfunktion pro Ereignis, Wartezeit −ln(U)/Hazard, automatische Neuplanung bei Zustandswechsel ([DYNAMIS-POP, Kap. 5](https://documentation.ihsn.org/dynamis/DYNAMIS-POP-MRT-2017_v01_05_Chapter5.html)); Timing Wheels (Varghese und Lauck 1987); Calendar Queue ([Brown 1988](https://cacm.acm.org/?p=10790)) |
| **Arbeit über die Tage verteilen** | Was pro Person monatlich (Gesundheit, Heiratssuche, Bekanntschaften, Reisestart) oder jährlich (Beruf, Umzug) läuft, erledigt jeder Tag nur für 1/30 bzw. 1/360 jeder Tabelle, und zwar als zusammenhängender Block, damit der Speicherzugriff linear bleibt. | CK2 2.6 verteilte den Jahreswechsel über das Jahr und kam damit 30–50 % weiter ([CK2 Dev Diary 18](https://admin-forum.paradoxplaza.com/forum/developer-diary/ck2-dev-diary-18-optimization-and-modding.962057/)); CK3 rechnet KI-Aufgaben monatlich statt täglich, also 1/30 der Kosten ([CK3 Dev Diary 36](https://admin-forum.paradoxplaza.com/forum/developer-diary/ck3-dev-diary-36-gotta-go-fast.1408620/page-6)) |
| **Parallel auf Systemebene, Strukturänderungen seriell** | Dichte Schleifen laufen parallel über Tabellen-Slices. Geburt, Tod, Heirat und Umzug laufen seriell in Personen-ID-Reihenfolge. Zufall ist ein Hash aus (Seed, Person, Zweck, Tag). Deshalb ergibt sich mit 1 und 4 Threads derselbe Fingerabdruck. | CK3 „von Objekt- zu Systemparallelität“ (DD 36); Victoria 3 mit Sortierschritt vor seriellen Änderungen ([DD 76](https://www.paradoxinteractive.com/games/victoria-3/news/dev-diary-76-performance)); S42 |
| **Kosten hängen an der Zahl der Objekte** | Pops sind nur eine abgeleitete Zählung (S61), keine eigenen Objekte. Personen-IDs werden nie wiederverwendet; die Tabellen sind bis zur Obergrenze von 200'000 (S59) vorab reserviert. | Victoria 3: „die Zahl der Pops ist der Schlüssel, nicht die Bevölkerung“ ([DD 105](https://admin-forum.paradoxplaza.com/forum/developer-diary/victoria-3-dev-diary-105-migration-in-1-6.1624226)) |
| **Sterbetafel** | Coale–Demeny Model West, Level 3, Frauen e0 = 25,0, Männer 22,9, Säuglingssterblichkeit 0,306 bzw. 0,352. Genau diese Tafel nimmt Frier für das Römische Reich. Nachgerechnet mit den Koeffizienten aus demogR `cdmltw` (Coale, Demeny und Vaughan 1983, mit Oeppens Korrekturen von 2018); die Werte für q0 stimmen mit der Literatur überein. | [Demography of the Roman Empire](https://en.wikipedia.org/wiki/Demography_of_the_Roman_Empire) (Frier 2000, Bagnall und Frier 1994, Scheidel 2001); [demogR](https://search.r-project.org/CRAN/refmans/demogR/html/cdmltw.html) |
| **Fruchtbarkeit in der Ehe** | Form der natürlichen Fruchtbarkeit nach Coale–Trussell, skaliert auf den Spitzenwert von 0,343 Geburten pro verheirateter Frau und Jahr im Alter von 20–24 Jahren, den die ägyptischen Zensuslisten zeigen. Nach einer Geburt folgen mindestens 15 Monate ohne neue Geburt; die Rate ist so angehoben, dass die Jahresrate gleich bleibt. Kinder nur von Paaren (S62). | Bagnall und Frier 1994 (über Wikipedia, im Buch zu prüfen) |
| **Heiratsmarkt** | Die Familie des Mannes sucht. Kandidatinnen sind Bekannte des Mannes und seines Vaters sowie ledige Frauen derselben Region und desselben Standes. Nach 6 Monaten ohne Erfolg kommen die acht Nachbarregionen dazu. Die Oberschicht sucht reichsweit und später auch eine Stufe tiefer. Gewertet wird wie in CK3 (Altersabstand, Stand, Kultur, Religion, Meinung, etwas Zufall). Die Braut zieht zum Mann. Kandidaten liegen monatlich in Listen nach (Region, Stand); es gibt keine Suche über alle. | S63; Wertung nach DYNASIM/APPSIM wie bei [Walker und Davis 2013](https://jasss.soc.surrey.ac.uk/16/1/6.html) |
| **Nahrung, Gesundheit, Wanderung** | Die Nahrung pro Kopf zählt pro 100-km-Region, weil die Region über ihren Markt teilt (S70). Die Gesundheit folgt ihr monatlich und ändert die Sterbe- und Geburtsrate (S64, S65). Ohne freies Land wartet die Familie mit der Heirat (S65). Haushalte in Not vergleichen jährlich die Nachbarregionen und ziehen um; ist keine besser, gehen sie zu Fuss oder per Schiff an den Kartenrand und verschwinden (S66). | S64–S66; Victoria 3: Wanderung nach Unterschieden der Attraktivität, ganze Pops bevorzugt (DD 105) |

## Ergebnis (100 Jahre, Seed 1, ganze Ausgabe in `run100.txt`)

| Jahr | Menschen | Geburten | Tote | davon < 1 Jahr | Ehen | Heiratsalter F / M | Frauen 15–49 verheiratet | ausgewandert |
|---|---|---|---|---|---|---|---|---|
| 1 | 115'264 | 2'620 | 4'148 | 884 | 1'589 | 22,1 / 35,7 | 87 % | 14 |
| 10 | 124'389 | 6'291 | 5'638 | 2'065 | 1'628 | 21,7 / 32,0 | 87 % | 8 |
| 30 | 133'952 | 6'293 | 5'682 | 2'018 | 2'002 | 21,5 / 32,0 | 74 % | 15 |
| 50 | 147'435 | 6'910 | 6'180 | 2'264 | 1'844 | 21,9 / 32,2 | 73 % | 165 |
| 70 | 150'973 | 7'208 | 6'442 | 2'394 | 2'049 | 22,0 / 32,0 | 73 % | 740 |
| 100 | 149'640 | 7'072 | 6'385 | 2'298 | 2'049 | 21,8 / 32,1 | 74 % | 751 |

**Was emergent passiert:** Die Bevölkerung wächst rund 50 Jahre lang mit etwa 0,5 % im
Jahr. Dann ist das Land voll (die Nahrung K liegt nach S35 bei Startbevölkerung / 0,7).
Ab dort halten sich Geburtenüberschuss und Auswanderung die Waage, bei etwa 150'000
Menschen. Es gibt keine Formel, die das Wachstum an K bindet: Es bremsen nur die
Regeln von S65 und S66 (warten mit der Heirat, Umzug, Auswanderung). Die Geburtenrate
liegt bei etwa 47 pro 1'000, die Sterberate bei 43 pro 1'000, und rund ein Drittel der
Säuglinge stirbt im ersten Jahr. Das passt zu einer Lebenserwartung um 25 Jahre. Im
ersten Jahr fehlen Geburten, weil die Startpaare erst schwanger werden.

**Was nicht passt (Platzhalter):**
- Männer heiraten mit 32 statt Ende 20, weil ihre Suche erst mit 25 beginnt und
  dauert.
- Das Wachstum ist mit 0,5 % pro Jahr höher als die historischen 0,1 % (Scheidel).
  Es fehlen noch Missernten, Seuchen, Krieg und Städte mit mehr Toten als Geburten.
- Hungertote gibt es kaum, weil die Menschen wandern, bevor sie hungern. Ob das so
  sein soll, entscheiden die Regeln zur Nahrung (S69–S76).

## Tempo und Speicher (4 Cloud-Kerne)

| Grösse | Wert |
|---|---|
| Laden | 1,4 s, davon 0,65 s für 724 Flussfelder |
| Tag, Median | **2,8 ms** (vorher ohne Geburt und Tod 0,74 ms, aber mit 15–25 ms an Monatstagen) |
| Tag, 95 % / 99 % | 7,0 ms / 10,4 ms |
| Monatsanfang, Median | 8,1 ms (Index neu bauen) |
| Langsamster Tag in 100 Jahren | 30,6 ms (Index an einem Monatsanfang) |
| Speicher | 155 MB beim Start, **184 MB** nach 100 Jahren, gleichbleibend |
| Ereignisse im Kalender | ≈ 300'000 |
| Determinismus | gleicher Fingerabdruck mit 1 und 4 Threads; Test `people::tests::deterministic_fingerprint` |

Pro Tag (Mittel): Ereignisse 0,10 ms, Bedürfnisse 0,61 ms, Reisen 0,26 ms, Gesundheit
0,14 ms, Heiratssuche 0,20 ms, Bekanntschaften 1,2 ms, Beruf 0,06 ms, Umzug 0,07 ms.
Pro Monat: Index 10,6 ms (bis 7 ms am Monatsanfang, der Rest am 10. für Haushalte),
Pops 2,2 ms.

Ein Spieltag kostet im Median also 2,8 ms. Das reicht für rund 350 Tage pro Sekunde,
wenn nichts anderes läuft.

**Behoben in diesem Schritt:**
- Ein Sprung von 80 ms kam vom Nachwachsen der ECS-Tabellen bei Geburten. Die Tabellen
  sind jetzt bis zur Obergrenze reserviert.
- Ein Speicherleck von 3 MB pro Jahr kam von nie geleerten Change-Trackern.
  `clear_trackers()` läuft jetzt jeden Tag.

**Nächste Schritte für mehr Tempo:**
- Den Monatsindex schrittweise statt auf einmal pflegen (bei Heirat, Tod und Geburtstag).
- Die Bekanntschaften (der grösste Posten) in Blöcken mit dichteren Personen-IDs rechnen.

## Platzhalter (nicht entschieden)

| Wert | Platzhalter | Grundlage |
|---|---|---|
| Heiratsalter, ab dem gesucht wird (F / M) | 15 / 25, Oberschicht 13 / 20 | Saller |
| Bevorzugter Altersabstand | 10 Jahre | Saller |
| Monate, bis die Suche weiter reicht | 6 | S63 „mehrere Monate“ |
| Heirat ohne freies Land | Chance 1/4 pro Monat | S65 |
| Mindestabstand zwischen zwei Geburten | 15 Monate | Schwangerschaft und Stillzeit |
| Tod der Mutter bei der Geburt | 1 % | vormoderne Grössenordnung, zu prüfen |
| Wirkung der Gesundheit | Tod × (1 + 2 · (1 − h)), Geburt × h | frei gewählt |
| Not, Reichweite, „besser“ (S66) | Nahrung pro Kopf < 1; die acht Nachbarregionen; mehr Nahrung pro Kopf | frei gewählt |
| Nahrung K | HYDE ländlich / 0,7 plus Städte, pro Region geteilt | S35, S70; ersetzt durch Höfe (S69–S76) |
| Senatoren und Ritter | 40 Männer in Rom, je 3 Ritter in den nächstgrösseren Orten | S58 |

Die Obergrenze S59 wurde nicht erreicht (Spitze 151'244); wie S67 sie auslöst, ist
noch offen.

## Startzahl 116'805 statt 100'000

S50 rechnet 56,65 Mio. (HYDE `pop200`) zu 100'000. Der Start nach S35 nimmt aber
die HYDE-Landbevölkerung (`rural200`, 56,09 Mio.) **plus** die Städte nach Hanson
(10,0 Mio.), zusammen 66,1 Mio. Daraus werden bei 1 : 566,5 rund 117'000 Personen
(dazu die Mindestzahl 2 pro Ort, S57). Entschieden (Ramon, 27.10.2026): Faktor bleibt,
Start mit rund 117'000.
