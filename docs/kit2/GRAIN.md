# Kit 2: Getreidewirtschaft, Handel und Wege (Vorschlag für S69–S76)

**Stand:** 27.10.2026 · **Status:** `erforscht`, Vorschlag. Nichts davon ist entschieden.

Grundlage ist der Recherchebericht „Getreidewirtschaft für 117'000 Menschen“ mit allen
Quellen und Belegstufen: <https://claude.ai/artifact/BnGFRobdpM8Z4PhG99HPcL>, als Datei
in den Projektdateien unter `romaaeterna/research/getreidewirtschaft-2026.html`. Der
Bericht baut auf dem Personen-Prototyp auf ([run-people](run-people/README.md)).
Hier steht nur der Plan, damit die Simulation flüssig bleibt (S71).

## Grundsätze

| Grundsatz | Warum | Vorbild |
|---|---|---|
| Eine Reise ist ein Ereignis, kein Schritt pro Tag. Beim Aufbruch werden Route und Ankunftstag in den Ereigniskalender gelegt; dazwischen rechnet die Simulation nichts. Die Grafik setzt Figuren nur im sichtbaren Ausschnitt aus Route und Uhrzeit. | Kosten hängen an der Zahl der Dinge, die man pro Tag anfasst. | Prototyp (Geburt und Tod), Cities: Skylines |
| Keine Pfadsuche pro Person. Jeder Markt hat ein Wegfeld, jeder Hof eine gespeicherte Route zu seinem Markt. Neu gerechnet wird nur, wenn sich Wege oder Höfe ändern. Vor jeder Suche prüft eine Nummer pro Zelle, ob ein Weg überhaupt existiert (Zusammenhangskomponente). | Ziele (Märkte) und Starts (Höfe) sind wenige und fest. | Flussfelder (Supreme Commander 2), Dwarf Fortress, RimWorld, Caesar 3 |
| Der Markt ist ein Lager mit Ankaufs- und Verkaufspreis. Der Preis läuft gedämpft auf einen Zielpreis zu, der von der Lagerreichweite abhängt. Jede Ankunft ist genau ein Kauf oder Verkauf. Es gibt kein Gleichgewicht und keine Auktion. | Einfache Händler reichen für effiziente Märkte. | EU5 (gedämpfter Zielpreis), Gode und Sunder 1993 |
| Händler sind echte Menschen mit veraltetem Wissen über höchstens 32 Märkte. Sie fahren, wenn Ankaufspreis am Ziel − Verkaufspreis am Start − Transport > Schwelle. So gleichen sich die Preise bis auf die Transportkosten aus. | Das räumliche Preisgleichgewicht entsteht, ohne dass ein Gleichungssystem gelöst wird. | MERCURY (Brughmans und Poblome 2016), ORBIS (Scheidel 2015), EU5 |
| Trampelpfade entstehen aus einer Abnutzungskarte nach Helbing et al. (1997). Jede Reise zählt einen Zähler an ihrer Route hoch, einmal im Monat wird die Route abgelaufen. Der Zerfall wird erst beim Lesen nachgeholt (Tag der letzten Änderung). Die Stufen haben Schwellen mit Hysterese, damit Pfade nicht flackern. | Unbenutzte Zellen kosten nichts. | Helbing 1997, Tero et al. 2010 (Netze aus Verkehr) |
| Wegfelder werden im Hintergrund neu gebaut: Start an Tag d, Übernahme immer an Tag d + 7. | Das Ergebnis hängt nicht vom Rechner ab und bleibt deterministisch. | OpenTTD (Cargodist) |
| Parallel nur lesen und Absichten sammeln, dann seriell nach (Markt-ID, Personen-ID) anwenden. Lager, Geld und Abnutzung sind Ganzzahlen. | Gleiches Ergebnis mit 1 und 4 Threads. | Victoria 3, CK3, S42, S44 |

## Takt

| Takt | Teile |
|---|---|
| Ereignis | Aussaat und Ernte pro Feld (Tag aus Klima und Breite, so verteilt sich die Ernte über Wochen), Ankunft einer Reise, Bauphase fertig |
| täglich | Preisschritt pro Markt, Kauf und Verkauf bei Ankunft, Reisestarts |
| wöchentlich, gestaffelt (Region-ID mod 7) | Arbeitsbörse pro Region (Tagelöhner, S72), Händlerentscheide |
| monatlich, gestaffelt (1/30 pro Tag) | Verzehr aus dem Hofspeicher, Kaufentscheid, Hunger, Pfadabnutzung, Zeltplatz, Entstehung und Verödung von Märkten (S75) |
| jährlich, gestaffelt | Umzug und Auswanderung (S66), Rodung neuer Felder (S73) |

## Daten

- **Grobraster 25 km:** Händler, Schiffe, Auswanderung, Marktgraph (wie im Prototyp).
- **Feinraster für Felder und Pfade:** Annahme Kachelebene 7, also 1,56 km echt und im
  Diorama etwa 66 m. Gespeichert wird nur in Chunks von 32 × 32 Zellen, die genutzt
  werden. Pro Zelle sind das etwa 6–8 Byte (Boden, Besitz, Abnutzung, letzter
  Änderungstag).
- **Hof:** eine Entity mit Besitzform (S69), Speicher in kg, Händen pro Jahresphase und
  Route zum Markt.
- **Felder:** keine Entities, sondern eine dichte Tabelle. Ein Feld wird nur bei
  Aussaat und Ernte angefasst.
- **Käufer:** gehen erst los, wenn ihr Vorrat unter eine Schwelle fällt (wie in
  Cities: Skylines II). Das hält die Zahl der Reisen klein.

## Budget (4 Kerne, Schätzung, muss gemessen werden)

| Teil | Ø ms/Tag | Spitze ms |
|---|---|---|
| Felder (Aussaat, Ernte) | 0,05 | 1,0 |
| Höfe (Verzehr, Speicher, Verkauf) | 0,1 | 0,3 |
| Arbeitsbörse | 0,2 | 1,0 |
| Reisen (Start, Ankunft) | 0,3 | 0,8 |
| Märkte | 0,05 | 0,1 |
| Händler | 0,1 | 0,3 |
| Trampelpfade | 0,2 | 0,5 |
| Zelte, Betteln, Marktentstehung | 0,1 | 0,3 |
| **Getreidewirtschaft gesamt** | **≈ 1,1 (Ziel ≤ 1,5)** | **Ziel ≤ 5** |

Ziel für die ganze Simulation mit Menschen: Ø ≤ 5 ms und p99 ≤ 12 ms pro Spieltag,
also über 200 Spieltage pro Sekunde ohne Grafik. Der kritische Fall ist die
Erntespitze, wenn Ernte, Tagelöhner und Verkaufsreisen in dieselben Wochen fallen. Sie
wird gezielt mit einem Lauf gemessen, bei dem alle Felder in derselben Woche reif sind.

**Nicht bauen:**
- Figuren, die jeden Tag eine Zelle weiterziehen.
- A* pro Reise.
- Eine Auktion oder ein Gleichgewicht pro Markttag.
- Handelsrouten als Objekte, deren Zahl wächst (Victoria 3 vor 1.9).
- Eine tägliche Schleife über alle Felder oder alle Zellen.
- Float im gespeicherten Zustand.

## Offen

- Alle Zahlen von S72: Verzehr pro Kopf, Ertrag, Hände pro Hof, Last pro Gang (Rücken,
  Esel, Karren) und Verderb. Sie bestimmen die Zahl der Reisen und damit das Budget am
  stärksten.
- Die Feinheit des Pfadrasters.
- Die Zahl der Märkte.
- Der Regler κ (Abnutzung × Haltbarkeit / Sichtweite²). Er entscheidet zwischen „jeder
  Hof hat einen eigenen Pfad“ und „ein Hauptweg mit Abzweigen“ und wird im Prototyp
  eingestellt.
