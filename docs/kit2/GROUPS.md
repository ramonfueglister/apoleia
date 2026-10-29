# Kit 2 — Pops, Berufe und politische Gruppen

**Stand:** 27.10.2026 · Entscheidungen S61 und S77 · Code: `sim/src/groups.rs`,
Haken in `sim/src/people.rs` (Beruf, Gruppen, Startzuteilung, Monatszählung).

## Was gebaut ist (nur Entschiedenes)

- Jeder Mensch trägt seine Zugehörigkeiten selbst (S61):
  - **Pop:** 100-km-Region (Tile-Ebene 1), Stand, Kultur, Religion.
  - **Wirtschaftliche Gruppe:** sein Beruf (`Job`), einer der 13 Berufe aus S77.
  - **Politische Gruppen:** eine Bitmaske (`Faction`) über die 8 Gruppen aus S77,
    also eine oder mehrere.
- Gruppen speichern keine eigenen Menschen. Einmal im Monat zählt der Kern alle
  Menschen neu in ihre Pop, ihren Beruf und ihre politischen Gruppen. Niemand wird
  doppelt gezählt. Wer in zwei politischen Gruppen ist, zählt in jeder einmal.
- Wer Stand, Beruf oder Wohnort wechselt, steht bei der nächsten Zählung in der
  neuen Gruppe. Bei einem Berufswechsel wechselt er sofort auch die politische
  Gruppe des neuen Berufs.
- Was die Gruppen tun, ist offen (S61, S77) und nicht gebaut.

| Berufe (S77) | Politische Gruppen (S77) |
|---|---|
| Adel, Unternehmer, Geistliche, Offiziere, Händler, Beamte, Gelehrte, Handwerker, Bauern, Pächter, Tagelöhner, Soldaten, Unfreie | Grundbesitzer, Industrielle, Intelligenzija, Kleinbürgertum, Bauernschaft, Militär, Klerus, Arbeiterschaft |

## Berufe zum Start: Schätzung für 180 n. Chr. (Ramon, 27.10.2026)

Ramon: Beruf und Gruppe bleiben wie gebaut, die Anteile werden für die Römerzeit um
180 geschätzt, vorerst wechselt niemand den Beruf. Kinder übernehmen den Beruf des
Vaters (Platzhalter).

| Stand | Anteile (Promille) |
|---|---|
| Land | Bauern 453, Pächter 290, Tagelöhner 110, Unfreie 100, Handwerker 30, Händler 10, Soldaten 4, Geistliche 3 |
| Stadt | Handwerker 270, Tagelöhner 235, Bauern 150, Unfreie 150, Händler 130, Soldaten 15, Beamte 20, Unternehmer 10, Geistliche 10, Gelehrte 10 |
| Ritter | Adel 300, Beamte 250, Unternehmer 250, Offiziere 200 |
| Senatoren | Adel 1000 |

Ergibt beim Start im ganzen Reich: Landwirtschaft (Bauern, Pächter, Tagelöhner) rund
78 %, Unfreie 10,8 %, Handwerker 6,5 %, Händler 2,8 %, Soldaten 0,6 %.
Korrektur gegenüber der ersten Fassung: Die Sklavenquote stützt sich auf Scheidel
(1997), nicht auf Scheidel (2011); dieses Kapitel nennt keine Anteile. Für die
Verstädterung (Wilson, 2011) wurde keine Zahl bestätigt; sie ist entfernt. Der
Stadtanteil im Modell kommt aus den Startdaten (SCALE.md).

Woran sich die Schätzung hält (geprüft am 27.10.2026; wo nur eine Sekundärquelle
eingesehen wurde, steht es dabei):

| Grösse | Beleg | Modell beim Start |
|---|---|---|
| Landwirtschaft | „mindestens 80 %“ der Bewohner arbeiteten in der Landwirtschaft (Mattingly, 2006, S. 356; zitiert nach Wikipedia „Economics of the Roman army“, Buch nicht eingesehen) | Bauern, Pächter, Tagelöhner 78 %, mit den Unfreien auf dem Land ≈ 85 % |
| Unfreie | Scheidel (1997) rechnet reichsweit mit 10 % und nennt das eher eine Untergrenze; die ägyptischen Zensuslisten zeigen 11 % (118 von 1'084 Personen; Bagnall & Frier, 1994, nach Scheidel, 1997) | 10,8 % |
| Heer | etwa 438'000 Mann ohne Flotte gegen Ende des 2. Jahrhunderts (MacMullen, 1980; nach Wikipedia „Size of the Roman army“), bei rund 70 Mio. Einwohnern (Scheidel & Friesen, 2009) ≈ 0,6 % | 0,6 % |
| Oberschicht | Senatoren, Ritter und Dekurionen ≈ 1,5 % der Bevölkerung (Scheidel & Friesen, 2009) | kleiner: Senat und Ritter nach S58 (≈ 100 Personen), Dekurionen sind noch kein eigener Stand |
| Pächter neben freien Bauern, Handwerker, Händler, Beamte, Geistliche, Gelehrte | keine belastbaren Anteile gefunden | geschätzt |

Quellen (APA 7):

- Bagnall, R. S., & Frier, B. W. (1994). *The demography of Roman Egypt*. Cambridge
  University Press.
- MacMullen, R. (1980). How big was the Roman imperial army? *Klio, 62*(2), 451–460.
- Mattingly, D. (2006). *An imperial possession: Britain in the Roman Empire, 54 BC–AD 409*.
  Allen Lane.
- Scheidel, W. (1997). Quantifying the sources of slaves in the early Roman Empire.
  *Journal of Roman Studies, 87*, 156–169. https://doi.org/10.2307/301373
- Scheidel, W., & Friesen, S. J. (2009). The size of the economy and the distribution of
  income in the Roman Empire. *Journal of Roman Studies, 99*, 61–91.
  https://doi.org/10.3815/007543509789745223

## Platzhalter (im Code `PLACEHOLDER`)

| Frage | Platzhalter |
|---|---|
| Welcher Beruf gehört zu welcher politischen Gruppe? | Bleibt so (Ramon, 27.10.2026): die Gruppe, zu der der Beruf in Victoria 3 am stärksten neigt: Adel → Grundbesitzer, Unternehmer → Industrielle, Geistliche → Klerus, Offiziere und Soldaten → Militär, Händler und Beamte → Kleinbürgertum, Gelehrte → Intelligenzija, Handwerker und Tagelöhner → Arbeiterschaft, Bauern, Pächter und Unfreie → Bauernschaft. Je Mensch vorerst nur diese eine Gruppe. |
| Berufswechsel | Vorerst keiner (Ramon, 27.10.2026). |
| Beruf der Kinder | Wie Stand, Kultur und Religion vom Vater. |

## Messung (Cloud, 4 Kerne, 10 Jahre, Seed 1)

| Was | Wert |
|---|---|
| Pops | 2'338 für 124'377 Menschen |
| Monatszählung | über 10 Tage verteilt (`CENSUS_DAYS`), 0,3–0,7 ms pro Tag, 4,4 ms pro Monat |
| Fingerabdruck 1 und 4 Threads | gleich, und gleich wie vor der Verteilung |
| Nach 100 Jahren | 2'557 Pops für 149'620 Menschen |

Beim Start (Jahr 1, 115'077 Menschen): Bauern 46'486, Pächter 28'578, Tagelöhner 14'906,
Unfreie 12'425, Handwerker 7'497, Händler 3'249, Soldaten 674, Geistliche 426, Beamte 388,
Unternehmer 185, Gelehrte 185, Adel 66, Offiziere 12. Politische Gruppen: Bauernschaft
87'489, Arbeiterschaft 22'403, Kleinbürgertum 3'637, Militär 686, Klerus 426,
Industrielle 185, Intelligenzija 185, Grundbesitzer 66.

## Wie es gerechnet wird

Die Zählung macht zur Monatsmitte einen Schnappschuss: ein paralleler Durchgang
schreibt je Mensch Pop, Beruf und Gruppen in eine Liste. Die nächsten 10 Tage
zählen je ein Zehntel dieser Liste, dann wird nach Schlüssel sortiert und das
Ergebnis veröffentlicht. Alle Zahlen stammen aus demselben Schnappschuss, also wird
niemand doppelt gezählt, auch wenn jemand in diesen Tagen stirbt oder umzieht. Weil
nur ganze Zahlen addiert werden, ist das Ergebnis unabhängig von der Zahl der
Threads. Tests: `groups::tests::parallel_count_equals_plain_count`,
`groups::tests::census_counts_its_snapshot`.

## Monatstage glätten (27.10.2026)

Vorher kosteten der 1. jedes Monats und Neujahr rund das Dreifache eines normalen
Tages: Heiratsindex und Haushalte wurden neu gebaut, über Felder so gross wie alle
je Geborenen, und die Zählung lief an einem Tag. Jetzt:

- Index und Haushalte nehmen nur Lebende und sortieren mit einem stabilen
  Radix-Sort (11 Bit je Stelle) statt über Felder je Personennummer.
- Beide werden am Ende des Monatstags in einem Hintergrund-Thread gebaut und erst
  vor dem ersten Leser am nächsten Tag abgeholt (Index vor den Heiraten, Haushalte
  vor der Wanderung). Die Ergebnisse sind dieselben wie vorher.
- Die Zählung ist über 10 Tage verteilt (oben).

Messung über 100 Jahre (Cloud, 4 Kerne, Seed 1, Fingerabdruck vorher und nachher
`d5884e33b9f770f8`), Zeiten in µs:

| | Vorher | Nachher |
|---|---|---|
| Tag p50 / p95 / p99 | 2'526 / 7'525 / 10'363 | 2'753 / 4'925 / 7'632 |
| 1. des Monats p50 / max | 8'462 / 28'964 | 4'157 / 12'716 |
| Neujahr p50 / max | 8'960 / 17'794 | 4'708 / 8'845 |
| Index pro Monat | 11'777 | 7'315 |

Der höchste Einzeltag (39 ms nachher, 34 ms vorher) kommt aus dem Bedarfsteil,
nicht aus diesen Bauten. Offen: Am 2. des Monats wartet der Tag auf dieser
langsamen 4-Kern-Maschine noch rund 4 ms auf den Index. Ganz flach würde es nur,
wenn die Heiraten den Index vom Vortag nähmen; das ändert die Ergebnisse und ist
nicht gebaut.
