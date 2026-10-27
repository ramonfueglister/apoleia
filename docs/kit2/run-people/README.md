# Lauf „people“ — Lastprobe mit Einzelpersonen (S50–S61)

**Stand:** 27.10.2026 · Cloud-Container, 4 Kerne. Die Messung auf dem Mac steht aus.

Die Probe prüft, ob rund 100'000 einzeln simulierte Menschen als Entities im
Rust-Kern (`bevy_ecs` 0.20) ins Zeitbudget passen. Die Regeln sind **Platzhalter,
die Last erzeugen**, keine Spielregeln. Geburt, Heirat und Tod gibt es nicht
(S54, S59 offen), und Kultur, Religion und politische Gruppe sind Platzhalter-IDs.

```
cd sim && cargo run --release --bin people -- --years 10 [--seed S] [--threads N]
```

## Was eine Person hat

`Pid`, `Born`, `Sex`, `Household`, `Home` (25-km-Zelle), `Job`, `Traits` (32 Bit),
`Health`, `Stand`, `Needs` (4 Werte), `Relations` (bis 30 Personen mit Meinung),
`Culture`, `Religion`, `Faction`; unterwegs zusätzlich `Travel` (Ziel, km auf dem
aktuellen Abschnitt, Hin- oder Rückweg).

| Takt | Teil (Platzhalter) |
|---|---|
| täglich | Bedürfnisse und Gesundheit (parallel); Reisende ziehen weiter |
| monatlich | Index Zelle → Personen; Meinungen zu allen Bekannten anpassen und eine neue Bekanntschaft in der Zelle; 0,3 % starten eine Reise zu einem der 860 Orte und wieder zurück; Pops (pro 100-km-Region) und Gruppen aus den Personen neu zählen (S61) |
| jährlich | Berufswahl aus 12 Kandidaten |

**Wege:** Pro Zielort ein Flussfeld (Dijkstra über das 25-km-Raster, 165 × 192
Zellen, Land 30 km/Tag, See 100 km/Tag). Es wird einmal beim Laden gebaut und dient
jeder Reise zu diesem Ort; eine Reise folgt dann nur noch Richtungs-Bytes.

## Ergebnis (10 Jahre, Seed 1)

| Grösse | Wert |
|---|---|
| Personen zum Start | **116'805** (siehe unten) |
| Laden | 0,8 s, davon 0,7 s für 724 Flussfelder |
| Speicher | 73 MB gesamt, davon ≈ 36 MB für Personen und Flussfelder |
| Gewöhnlicher Tag | p50 0,74 ms, p95 1,1 ms |
| Tag mit Monatsteil | p50 15 ms, p95 21 ms, max 25 ms |
| Tag mit Jahresteil | p50 17 ms, max 28 ms |
| Pops (100-km-Region, Stand, Kultur, Religion) | 2'049 (mit 25-km-Zellen wären es 32'341) |
| Unterwegs | ≈ 840 Personen (Hin- und Rückweg) |

Pro Teil: Bedürfnisse 0,61 ms/Tag, Reisen 0,18 ms/Tag; pro Monat Index 5,3 ms,
Beziehungen 6,4 ms, Reisestart 1,5 ms, Pops 1,9 ms; pro Jahr Berufswahl 2,3 ms.

**Determinismus:** gleicher Fingerabdruck `6cca8fd260bc15c3` in zwei Läufen und
mit `--threads 1`. Test `people::tests::deterministic_fingerprint`.

**Einordnung:** Bei einem Spieltag pro Sekunde wären 15–27 ms an einzelnen Tagen
unkritisch. Bei schneller Spielgeschwindigkeit (z. B. 30 Tage pro Sekunde) wird der
Monatsteil spürbar und sollte über die Tage des Monats verteilt werden.

## Startzahl 116'805 statt 100'000

S50 rechnet 56,65 Mio. (HYDE `pop200`) zu 100'000. Der Start nach S35 nimmt aber
die HYDE-Landbevölkerung (`rural200`, 56,09 Mio.) **plus** die Städte nach Hanson
(10,0 Mio.), zusammen 66,1 Mio. Daraus werden bei 1 : 566,5 rund 117'000 Personen
(dazu die Mindestzahl 2 pro Ort, S57). Für genau 100'000 müsste der Faktor bei
diesen Startdaten 1 : 661 sein. Entschieden (Ramon, 27.10.2026): Faktor bleibt, Start mit rund 117'000.
