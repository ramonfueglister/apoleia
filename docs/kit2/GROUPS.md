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

## Platzhalter (im Code `PLACEHOLDER`, offen für Ramon)

| Frage | Platzhalter |
|---|---|
| Welcher Beruf gehört zu welcher politischen Gruppe? | Die Gruppe, zu der der Beruf in Victoria 3 am stärksten neigt: Adel → Grundbesitzer, Unternehmer → Industrielle, Geistliche → Klerus, Offiziere und Soldaten → Militär, Händler und Beamte → Kleinbürgertum, Gelehrte → Intelligenzija, Handwerker und Tagelöhner → Arbeiterschaft, Bauern, Pächter und Unfreie → Bauernschaft. Je Mensch vorerst nur diese eine Gruppe. |
| Wer hat zum Start welchen Beruf? | Anteile nach Stand. Land: Bauern 45 %, Pächter 25 %, Tagelöhner 15 %, Unfreie 12 %, Soldaten 2 %, Geistliche 1 %. Stadt: Tagelöhner 27 %, Handwerker 25 %, Händler 15 %, Unfreie 15 %, Soldaten 8 %, Beamte 4 %, Geistliche 4 %, Gelehrte 2 %. Ritter: Unternehmer 40 %, Beamte 30 %, Offiziere 30 %. Senatoren: Adel. |
| Wie wechselt man den Beruf? | 10 % pro Jahr ziehen einen neuen Beruf aus den Anteilen ihres Standes, ohne Unfreie. Unfreie wechseln nicht. |
| Beruf der Kinder | Wie Stand, Kultur und Religion vom Vater. |

## Messung (Cloud, 4 Kerne, 10 Jahre, Seed 1)

| Was | Wert |
|---|---|
| Pops | 2'338 für 124'377 Menschen |
| Monatszählung | 1,6 ms an einem Tag pro Monat (1 Kern: 2,5 ms), im Mittel 0,05 ms pro Tag |
| Vorher (Zählung ohne Berufe je Pop, seriell) | 2,2 ms pro Monat |
| Fingerabdruck 1 und 4 Threads | gleich (`ea07aa650d300779`) |
| Nach 100 Jahren | 2'557 Pops für 149'620 Menschen, Zählung 2,1 ms pro Monat (0,07 ms pro Tag) |

Nach 10 Jahren: Bauern 47'493, Pächter 26'340, Tagelöhner 20'930, Unfreie 15'442,
Handwerker 4'654, Soldaten 3'592, Händler 2'794, Geistliche 1'794, Beamte 784,
Gelehrte 379, Adel 91, Offiziere 51, Unternehmer 33. Politische Gruppen: Bauernschaft
89'275, Arbeiterschaft 25'584, Militär 3'643, Kleinbürgertum 3'578, Klerus 1'794,
Intelligenzija 379, Grundbesitzer 91, Industrielle 33.

## Wie es gerechnet wird

Die Zählung läuft parallel über die Personentabellen. Jeder Thread zählt in seine
eigene Tabelle (Pop → Kopfzahl, Berufe, Gruppen), danach werden die Tabellen
addiert und nach Schlüssel sortiert. Weil nur ganze Zahlen addiert werden, ist das
Ergebnis unabhängig davon, wie die Menschen auf die Threads verteilt sind. Ein Test
vergleicht die parallele Zählung mit einer einfachen seriellen Zählung
(`groups::tests::parallel_count_equals_plain_count`).
