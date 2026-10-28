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
| **Ehe nach dem Zensus** | 20 % der Frauen heiraten nie (eine Ziehung pro Frau). Jede Ehe endet mit 10 % im Jahr durch Scheidung; die Frau geht in den Haushalt ihres Vaters zurück, sonst gründet sie einen eigenen, die Kinder bleiben beim Vater. Frauen werden nur bis 35 gesucht, ältere Witwen und Geschiedene heiraten also nicht mehr. Die Raten sind so eingestellt, dass die Gesamtzahlen des Zensus stimmen. | S86; Bagnall und Frier 1994, Huebner 2019, Ziel 0,1–0,2 % Wachstum (Frier 2000, Scheidel 2007) |
| **Heiratsmarkt** | Die Familie des Mannes sucht. Kandidatinnen sind Bekannte des Mannes und seines Vaters sowie ledige Frauen derselben Region und desselben Standes. Nach 6 Monaten ohne Erfolg kommen die acht Nachbarregionen dazu. Die Oberschicht sucht reichsweit und später auch eine Stufe tiefer. Gewertet wird wie in CK3 (Altersabstand, Stand, Kultur, Religion, Meinung, etwas Zufall). Die Braut zieht zum Mann. Kandidaten liegen monatlich in Listen nach (Region, Stand); es gibt keine Suche über alle. | S63; Wertung nach DYNASIM/APPSIM wie bei [Walker und Davis 2013](https://jasss.soc.surrey.ac.uk/16/1/6.html) |
| **Nahrung, Gesundheit, Wanderung** | Die Nahrung pro Kopf zählt pro 100-km-Region, weil die Region über ihren Markt teilt (S70). Das Körpergewicht folgt ihr monatlich (Hall et al. 2011) und ändert die Sterberate, der Essensanteil die Geburtsrate (S64, S65, S84). Ohne freies Land wartet die Familie mit der Heirat (S65). Haushalte in Not vergleichen jährlich die Nachbarregionen und ziehen um; ist keine besser, gehen sie zu Fuss oder per Schiff an den Kartenrand und verschwinden (S66). | S64–S66; Victoria 3: Wanderung nach Unterschieden der Attraktivität, ganze Pops bevorzugt (DD 105) |
| **Haushaltsteilung (S81)** | Stirbt ein Mann, wird er vorgemerkt. Einmal im Monat, am Tag mit frischen Haushaltslisten, gründet jeder seiner verheirateten Söhne im Haushalt einen eigenen: der Sohn, seine Frau, alle, deren Vater zur Gruppe gehört, und deren Frauen. Witwe, Ledige und alle anderen bleiben. Der neue Haushalt bekommt die ID des Sohnes und bleibt in derselben Zelle. | S81; patria potestas bis zum Tod des Vaters; Bagnall und Frier 1994 |
| **Intelligenz (S82)** | Jeder Mensch trägt einen genetischen Wert und einen Umweltwert, beide standardnormal (Ganzzahl in Schritten von 1/4096, Ziehung deterministisch über die Quantilfunktion nach Acklam). IQ = 100 + 15 · (√h² · Gen + √(1 − h²) · Umwelt), mit h² nach Alter: 0,2 bei Geburt, 0,41 mit 9, 0,55 mit 12, 0,66 mit 17, 0,8 ab 20, linear dazwischen. Die Streuung bleibt so in jedem Alter 15. Das Kind erbt (Gen Vater + Gen Mutter) / 2 plus Zufall mit Varianz 1/2, damit die Streuung über die Generationen gleich bleibt. Wirkt auf nichts. Nach 30 Jahren: Erwachsene Mittel 100,0, Streuung 15,0, 2,3 % unter 70, 2,3 % ab 130. | [Haworth et al. 2010](https://research.gold.ac.uk/id/eprint/5349) (Molecular Psychiatry, ≈ 11'000 Zwillingspaare); [Bouchard 2013](https://www.cambridge.org/core/journals/twin-research-and-human-genetics/article/wilson-effect-the-increase-in-heritability-of-iq-with-age/FF406CC4CF286D78AF72C9E7EF9B5E3F) (Wilson-Effekt); Partnerkorrelation 0,44: [Horwitz et al. 2023](https://ideas.repec.org/a/nat/nathum/v7y2023i9d10.1038_s41562-023-01672-z.html) (nicht gebaut) |
| **Waisen und Alte (S79)** | Einmal im Jahr prüft jeder Haushalt, ob noch jemand zwischen 15 und 60 lebt. Wenn nicht, zieht der ganze Haushalt zum nächsten Verwandten im arbeitsfähigen Alter: zuerst Vater oder Mutter, dann ein Kind, ein Geschwister, dann Onkel oder Tante. Eltern werden auch für Tote gemerkt (8 Byte pro Person), Kinder liegen in einer monatlichen Liste nach Elternteil, die im Hintergrund an einem eigenen Tag gebaut wird. Wer niemanden findet, bleibt; ins Zelt schickt ihn erst die Getreidewirtschaft. | S79; römische Vormundschaft (tutela) und Alte bei den Kindern (Saller 1994) |

## Ergebnis (100 Jahre, Seed 1, ganze Ausgabe in `run100.txt`)

| Jahr | Menschen | Geburten | Tote | davon < 1 Jahr | Ehen | Heiratsalter F / M | Frauen 15–49 verheiratet | ausgewandert |
|---|---|---|---|---|---|---|---|---|
| 1 | 115'364 | 2'712 | 4'141 | 878 | 1'892 | 22,5 / 37,1 | 91 % | 16 |
| 10 | 127'339 | 7'101 | 5'971 | 2'320 | 1'848 | 21,1 / 30,0 | 98 % | 20 |
| 30 | 147'890 | 8'039 | 6'557 | 2'576 | 2'340 | 20,4 / 28,1 | 88 % | 480 |
| 50 | 152'889 | 8'183 | 6'730 | 2'673 | 2'249 | 20,6 / 27,5 | 84 % | 1'408 |
| 70 | 152'643 | 8'372 | 6'788 | 2'724 | 2'321 | 21,0 / 27,8 | 85 % | 1'494 |
| 100 | 152'465 | 8'135 | 6'791 | 2'765 | 2'320 | 21,0 / 27,7 | 85 % | 1'205 |

Haushalte ohne jemanden zwischen 15 und 60: beim Start 17,6 % (zufällige Fünfergruppen
ohne bekannte Verwandtschaft), nach 30 Jahren 3,3 % (ohne S79 wären es 7,7 %), nach
100 Jahren 1,3 %.

Haushaltsteilung (S81): Die ersten Teilungen kommen nach etwa 20 Jahren, weil die
Startbevölkerung keine bekannten Eltern hat. Ab Jahr 50 entstehen rund 460 neue Haushalte
pro Jahr mit zusammen 1'600 Menschen. Nach 100 Jahren gibt es 23'243 Haushalte mit im
Mittel 6,6 Menschen (vorher 8'622 mit 17). Pro Jahr ziehen 60–380 Menschen zu Verwandten, anfangs mehr, weil
die Startbevölkerung keine bekannten Eltern hat.

**Was emergent passiert:** Die Bevölkerung wächst rund 40 Jahre lang mit etwa 0,7 % im
Jahr. Dann ist das Land voll (die Nahrung K liegt nach S35 bei Startbevölkerung / 0,7).
Ab dort halten sich Geburtenüberschuss und Auswanderung die Waage, bei etwa 150'000
Menschen. Es gibt keine Formel, die das Wachstum an K bindet: Es bremsen nur die
Regeln von S65 und S66 (warten mit der Heirat, Umzug, Auswanderung). Die Geburtenrate
liegt bei etwa 54 pro 1'000, die Sterberate bei 44 pro 1'000, ab Jahr 50 wandern rund
10 pro 1'000 aus, und rund ein Drittel der
Säuglinge stirbt im ersten Jahr. Das passt zu einer Lebenserwartung um 25 Jahre. Im
ersten Jahr fehlen Geburten, weil die Startpaare erst schwanger werden.

**Was nicht passt (Platzhalter):**
- Das Heiratsalter der Männer ist jetzt an Saller angeglichen: Die Suche der Gemeinen
  beginnt mit 20 statt 25, das mittlere Alter bei der ersten Ehe liegt bei 28 (vorher
  32). Mit Suchbeginn 22 lag es bei 30. Weil mehr Frauen verheiratet sind (84 % statt
  74 %), gibt es mehr Geburten und mehr Auswanderung; das Plateau bleibt bei 150'000.
- Das Wachstum war mit 0,7 % pro Jahr höher als die historischen 0,1 % (Scheidel).
  Behoben mit S86 (siehe unten): Es lag an zu vielen verheirateten Frauen.
- Hungertote gibt es kaum, weil die Menschen wandern, bevor sie hungern. Ob das so
  sein soll, entscheiden die Regeln zur Nahrung (S69–S76).
- Wer bei einer Teilung Hof und Vorrat erbt, ist offen (S81). Die neuen Haushalte
  bleiben in derselben Zelle.

## Ehe nach dem Zensus (S86, 100 Jahre, Seed 1, `run100-s86.txt`; vorher: `run100.txt`)

Ramon: „Alle drei belegten Wege“ (Dokument „Wachstum: Zahlen mit Quellen“). Ohne
Getreidewirtschaft:

| Grösse | vorher | jetzt | Zensus und Forschung |
|---|---|---|---|
| Frauen 15–49 verheiratet | 85 % | 64,8 % | etwa die Hälfte der Erwachsenen ledig (Huebner 2019) |
| Geburten pro 1'000 und Jahr | 54 | 46 | etwa 45 (Bagnall und Frier 1994) |
| Tote pro 1'000 und Jahr | 44 | 43 | knapp über 40 |
| Menschen im Jahr 100 | 152'465 | 130'805 | – |
| Wachstum über 100 Jahre | 0,7 % bis das Land voll ist | 0,13 % | 0,1–0,2 % |

Rund 1'900 Scheidungen und 3'400 Ehen pro Jahr. Die Bevölkerung erreicht die Grenze des
Landes nicht mehr, darum gibt es kaum Auswanderung.

## Tempo und Speicher (4 Cloud-Kerne)

| Grösse | Wert |
|---|---|
| Laden | 1,4 s, davon 0,65 s für 724 Flussfelder |
| Tag, Median | **3,1 ms** (vorher ohne Geburt und Tod 0,74 ms, aber mit 15–25 ms an Monatstagen) |
| Tag, 95 % / 99 % | 5,5 ms / 7,1 ms (vorher 7,5 / 10,6) |
| Monatsanfang, Median | 4,6 ms, höchstens 10 ms (vorher 8,4 und 29 ms) |
| Langsamster Tag in 100 Jahren | 41–95 ms, je Lauf an einem anderen Tag und in einem anderen Teil (Bedürfnisse, Bekanntschaften, Reisen), bei gleichem Ergebnis. Die Arbeit ist also dieselbe, und der Ausreisser kommt von der geteilten Cloud-Maschine (ein Thread wird verdrängt). Ohne solche Ausreisser ist der langsamste Tag ein Monatsanfang mit rund 15 ms. Die Messung auf dem Mac steht noch aus. |
| Speicher | 155 MB beim Start, **202 MB** nach 100 Jahren (mehr Menschen im Kalender, Eltern aller je Geborenen), ab Jahr 60 wächst er um rund 0,15 MB pro Jahr |
| Ereignisse im Kalender | ≈ 380'000 |
| Determinismus | gleicher Fingerabdruck mit 1 und 4 Threads; Test `people::tests::deterministic_fingerprint` |

Pro Tag (Mittel): Ereignisse 0,10 ms, Bedürfnisse 0,59 ms, Reisen 0,25 ms, Gesundheit
0,13 ms, Heiratssuche 0,26 ms, Bekanntschaften 1,2 ms, Umzug 0,07 ms (Berufswechsel gibt
es nicht mehr, S77). Pro Monat: Index, Haushalte und Kinderliste 6,4 ms, Pops 3,8 ms.

Jeder Tag soll ungefähr gleich viel kosten. Deshalb arbeiten Index und Haushalte nur
noch über die Lebenden (Radix-Sort statt Felder über alle je vergebenen IDs, die über
700 Jahre auf Millionen wachsen würden). Am Monatstag wird nur ein Schnappschuss
gemacht; gebaut wird auf einem Hintergrund-Thread und übernommen, bevor am nächsten
Tag der erste Leser kommt. Die Pops werden aus einem Schnappschuss zur Monatsmitte über
10 Tage gezählt. Die Ergebnisse sind gleich geblieben (gleicher Fingerabdruck).
Am 2. des Monats wartet die Heiratssuche auf 4 Kernen noch rund 4 ms auf den Index.

Ein Spieltag kostet im Median also 2,8 ms. Das reicht für rund 350 Tage pro Sekunde,
wenn nichts anderes läuft.

**Behoben in diesem Schritt:**
- Ein Sprung von 80 ms kam vom Nachwachsen der ECS-Tabellen bei Geburten. Die Tabellen
  sind jetzt bis zur Obergrenze reserviert.
- Ein Speicherleck von 3 MB pro Jahr kam von nie geleerten Change-Trackern.
  `clear_trackers()` läuft jetzt jeden Tag.

**Nächste Schritte für mehr Tempo:**
- Die Bekanntschaften (der grösste Posten) in Blöcken mit dichteren Personen-IDs rechnen.

## Platzhalter (nicht entschieden)

| Wert | Platzhalter | Grundlage |
|---|---|---|
| Heiratsalter, ab dem gesucht wird (F / M) | 15 / 20, Oberschicht 13 / 20 | Saller: erste Ehe bei Frauen Ende Teens, bei Männern Ende 20; Oberschicht früher. Ergibt im Mittel 21 / 28 |
| Bevorzugter Altersabstand | 10 Jahre | Saller |
| Monate, bis die Suche weiter reicht | 6 | S63 „mehrere Monate“ |
| Heirat ohne freies Land | Chance 1/4 pro Monat | S65 |
| Stärke der Auswanderung an der Obergrenze | linear von 0 bei 90 % bis 3 % der Haushalte pro Jahr bei 100 %, die am schlechtesten versorgten zuerst | S80 (90 % aus der Entscheidung) |
| Arbeitsfähiges Alter, Reihenfolge der Verwandten | 15–60; Vater oder Mutter, Kind, Geschwister, Onkel oder Tante, je die kleinste ID | S79 (Beispiele aus der Entscheidung) |
| Mindestabstand zwischen zwei Geburten | 15 Monate | Schwangerschaft und Stillzeit |
| Tod der Mutter bei der Geburt | 1 % | vormoderne Grössenordnung, zu prüfen |
| Wirkung der Gesundheit | ersetzt durch S84 (Körpergewicht, `sim/src/body.rs`): Normal-BMI 21, Bedarf pro kg bei Kindern, Kinder 5–19 nach der Erwachsenentabelle, Schwelle der Fruchtbarkeit 65 % | Platzhalter in S84 |
| Not, Reichweite, „besser“ (S66) | Nahrung pro Kopf < 1; die acht Nachbarregionen; mehr Nahrung pro Kopf | frei gewählt |
| Nahrung K | HYDE ländlich / 0,7 plus Städte, pro Region geteilt | S35, S70; ersetzt durch Höfe (S69–S76) |
| Senatoren und Ritter | 40 Männer in Rom, je 3 Ritter in den nächstgrösseren Orten | S58 |

Die Obergrenze S59 wird in diesem Lauf nicht erreicht (Spitze rund 153'000). Mit der
Getreidewirtschaft schon: Dort greift S80. Ab 90 % der Grenze ziehen Haushalte in Not
eher weg als um, und ein Teil der übrigen wandert aus, die am schlechtesten versorgten
zuerst. Ohne Brache bleibt die Bevölkerung so bei rund 185'000 stehen (92 % der Grenze),
statt auf 202'000 zu steigen. Mit Brache (S76, Standard) wächst sie nur auf 137'000, und
S80 greift in 100 Jahren nicht ([run-grain](../run-grain/README.md)).

## Startzahl 116'805 statt 100'000

S50 rechnet 56,65 Mio. (HYDE `pop200`) zu 100'000. Der Start nach S35 nimmt aber
die HYDE-Landbevölkerung (`rural200`, 56,09 Mio.) **plus** die Städte nach Hanson
(10,0 Mio.), zusammen 66,1 Mio. Daraus werden bei 1 : 566,5 rund 117'000 Personen
(dazu die Mindestzahl 2 pro Ort, S57). Entschieden (Ramon, 27.10.2026): Faktor bleibt,
Start mit rund 117'000.
