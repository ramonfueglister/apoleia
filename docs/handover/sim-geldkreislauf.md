# Übergabe: Simulations-Thread «Geldkreislauf» (Stand 31.10.2026, 18:45)

Für die nächste Claude-Sitzung, die an der Wirtschaftssimulation weiterarbeitet. Alles hier stimmt für main
`5b8167d` (Merge von PR #128). Massgeblich bleiben `docs/kit2/decisions.md` (S-Nummern, Regeln, Befunde) und
`docs/kit2/run-grain/README.md` (Läufe, Tabellen, Platzhalter, Quellen in APA 7).

## Arbeitsweise mit Ramon

- **Sprache:** Deutsch, mit «ss» statt «ß». Kurze Antworten in ganzen Sätzen.
- **Entscheide:** Ramon entscheidet jeden Schritt mit einer Karte. Vorschlagen und fragen, dann bauen.
- **Scope:** Gebaut wird nur, was besprochen ist. Kein Restyling, das nicht verlangt ist.
- **Ökonomie:**
  - Alles ergibt sich aus der Simulation: keine Preisregel, kein Band, kein fester Lohn.
  - Jede Regel muss von Rom bis etwa 2000 tragen.
  - Begriffe im Spiel müssen historisch belegt sein. Das Geld bleibt der Denar.
  - Quellen nach APA 7. Was nicht selbst nachgelesen ist, wird so markiert. Zahlen ohne Beleg heissen PLATZHALTER.
- **Mergen:**
  - Merge ohne Mac-Test anbieten; Ramon schreibt «mergen».
  - Rust-Änderungen brauchen auf dem Mac einen Neubau mit `sim/godot/build.sh`. GDScript braucht nur `git pull`.
- **Neue S-Nummer:** Vor dem Vergeben auf `origin/main` prüfen, ob sie frei ist; mehrere Threads vergeben Nummern. Zuletzt vergeben: S136.
- **Konflikte in `decisions.md`:** Immer alle Zeilen behalten.

## Was dieser Thread gebaut hat (alles gemergt)

| S | Was | PR | Code |
|---|---|---|---|
| S129 | Die Kasse gibt den Überschuss über der Reserve als öffentliche Arbeit aus | #100 | `sim/src/grain.rs` |
| S130 | Jahresplan der Höfe: zuerst Geld für Korn bis zur Ernte und die Saat | #100 | `sim/src/grain.rs` |
| S131 | Steuergesetz (Zehnt, Grundsteuer, Kopfsteuer) mit Rückstand, Pfändung und Zwangsversteigerung | #109, #113, #115 | `sim/src/grain/taxes.rs` |
| S132 | Fuhrlohn: die Fracht wird als Taglohn an Fuhrleute bezahlt | #115 | `sim/src/grain.rs` |
| S133 | Staatsausgaben: öffentliche Arbeit befestigt Wege; Gesetze Vorratshaltung und Armenpflege | #121 | `sim/src/grain/spend.rs`, `sim/src/grain/ways.rs` |
| S134 | Staatsschuld: Anleihen nach Geboten, Zins nach Ruf, vier Schuldgesetze, Zwangsanleihe; UI im Haushalt | #128 | `sim/src/grain/debt.rs` |

**Oberfläche (S133, S134).** In Staat › Haushalt gibt es seit #128:

- Knöpfe für die Ausgaben- und Schuldgesetze,
- die Zeile für die Zwangsanleihe,
- die Gläubigerliste mit Gesichtern,
- drei Verlaufskarten,
- den Posten «Zinsen».

Diese Teile wurden blind gebaut und sind **auf dem Mac nie getestet** worden. Beim ersten Test darauf achten. Die Dateien:

- `app/scripts/sim/sim_overview.gd`
- `app/scripts/sim/sim_tables.gd`
- `app/scripts/sim/sim_events.gd`
- `app/scripts/sim/people_dots.gd`

**Brücke** (`sim/godot/src/people_dots.rs`): `set_tax`, `tax_law`, `set_spend`, `spend_law`, `set_debt`, `forced_loan`, `debt_law`. Das Haushalts-Dictionary enthält ausserdem `bonds` und `loss_memory`.

**Befehle im Spielstand** (`sim/src/build.rs`): Law = Tag 2, Spend = Tag 3, Debt = Tag 4, ForcedLoan = Tag 5. Jede Entscheidung des Spielers muss ein Befehl sein, sonst stimmt das Abspielen beim Laden nicht.

## Dateien, die dieser Thread «besitzt»

Andere Threads sprechen sich mit diesem Thread ab, bevor sie diese Dateien ändern:

- **Ganz:**
  - `sim/src/grain/taxes.rs`, `spend.rs`, `debt.rs`
  - die Treasury- und Money-Buchhaltung in `sim/src/grain.rs` («nicht gebucht» muss 0 bleiben)
- **Teilweise:**
  - `sim/src/bin/grain.rs` (Zeilen und Schalter für S129–S134)
  - in `app/scripts/sim/sim_overview.gd` die Haushaltsseite (`budget_charts`, `_choices_card`, `_creditors_card`)
- **Geteilt:** Die Wegebene ist mit dem Grafik-Thread geteilt. Eine befestigte Kachel ist heute Stufe G = 7; das eigene Bit kommt mit dem PR des Grafik-Threads für befestigte Wege.

## Wie man die 100-Jahr-Läufe startet

```sh
cd sim
cargo build --release
./target/release/grain --years 100 --seed 1 > /tmp/run.txt   # Standard
```

Läufe dauern etwa 9 Minuten.

**Speicher:** Ein Lauf braucht etwa 0,5 GB. In der Cloud höchstens zwei oder drei Läufe gleichzeitig, und **nicht bauen, während Läufe laufen**: Zwei Läufe wurden einmal mitten im Bau beendet («Killed»).

Jedes Jahr schreibt eine Tabellenzeile mit Jahr, Menschen, …, Hungertoten (Spalte 6) und dazu Zeilen pro Thema:

- «money den (S94)»
- «spending (S133)»
- «debt (S134)»

**Schalter für diese Systeme:**

- Steuern: `--tithe 0-5`, `--land-tax 0-5`, `--head-tax 0-5`, `--no-seizure`, `--no-auction`
- Ausgaben: `--no-paving`, `--stock 0-3`, `--relief 0-2`
- Schuld: `--debt-limit 0-3`, `--debt-term 0-3`, `--debt-short 0-2`, `--usury 0-3`, `--forced-loan JAHR,ANTEIL,ZINS`
- Zum Vergleich ausschalten: `--no-freight-wage`, `--no-state-spend`, `--no-food-plan`

**Fingerabdruck:** Mit den Standardgesetzen muss er gleich bleiben wie vor einer Änderung. Am Ende jedes Laufs steht die Zeile «fingerprint people=… grain=…»; zum Vergleich genügen 5 Jahre mit Seed 1.

**Tests:**

- `cargo test --release` in `sim/` (97 grün, 1 ausgelassen)
- `cargo check` in `sim/godot/`
- GDScript mit gdtoolkit prüfen: `pip install gdtoolkit==4.*`, dann `gdparse datei.gd`. Godot selbst lässt sich in der Cloud nicht laden.

**Ohne Startgeld** (Sonde Erbteil und Scheidungsgeld): Das Patch
`/mnt/project-files/sim-probes/geldkreislauf/probe-on-s134.patch` passt auf main `5b8167d`. Es fügt
`--inherit-money --divorce-money` hinzu.

Alle Läufe von S134 mit Auswertung (`tab2.py`) liegen in `/mnt/project-files/sim-probes/geldkreislauf/runs-s134/`.
Der Befund der Sonde steht in `/mnt/project-files/sim-probes/geldkreislauf/BEFUND.md`.

## Offene Punkte (nach Wichtigkeit)

1. **Umschuldungs-Spirale (S134).**
   - **Befund:** Mit dem Gesetz «Umschuldung» wird jeder unbezahlte Zins jedes Jahr zu einer neuen Rente. Im Lauf ohne Startgeld, Seed 1, stieg die Schuld so bis Jahr 100 auf 62 Mio. Denar, das 33-Fache der Jahreseinnahme. Die Schuldengrenze begrenzt nur neue Anleihen.
   - **Vorschlag:** Umschulden nur bis zur Grenze; der Rest fällt wie beim Staatsbankrott aus. Die Karte dazu wurde zurückgezogen, weil die Threads geschlossen wurden; **Ramon hat noch nicht entschieden.**
   - **Bereit:** Das Patch `/mnt/project-files/sim-probes/geldkreislauf/s134-umschuldung-bis-grenze.patch` passt auf main. Die Tests in `debt.rs` sind damit grün; ein 100-Jahr-Lauf damit fehlt noch.
2. **Missernten (S101, wiederbelebt).**
   - **Vorschlag:** echtes Wetter aus OWDA und PHYDA, Hagel und Schädlinge je Hof, Nil nach dem Nilometer. Doc: https://claude.ai/artifact/RaX42TN33ymdDhj7fBj1aL
   - **Karte:** Ramons Karte zu den Missernten ist offen. Die Empfehlung war, sie nach der Staatsschuld zu bauen, und die ist jetzt gemergt.
   - **Daten:** In der Cloud sind die Quellen gesperrt (ncei.noaa.gov, paleo.ltrr.arizona.edu, zenodo.org). Sie müssen in einer kurzen Mac-Sitzung geholt werden, nicht über eine Freigabe in der Cloud.
3. **Mehr Hungertote mit befestigten Wegen (S133).**
   - **Befund:** Seit die öffentliche Arbeit Wege befestigt, sterben ab Jahr 31 9–13 % mehr Menschen an Hunger. Dazu kommen weniger Einfuhr über die Kartengrenze (28–40 statt 51–52 Mio.) und ein höherer Kornpreis.
   - **Ursache:** nicht untersucht.
   - **Verdacht:** Billigere Fracht zieht Korn aus den Höfen in die Märkte und zur Ausfuhr. Prüfen mit `--no-paving` und `PRICE_DEBUG=1 GOODS_DEBUG=1`.
4. **Erbteil statt Startgeld (S94, S132).**
   - **Befund:** Neue Haushalte von Senatoren und Händlern bekommen heute Geld aus dem Nichts (1 Mio. bzw. 5'000 Denar). 89 % davon gehen an geschiedene Frauen (S86). Ihr Nachlass fliesst als Heimfall in die Kasse und bezahlt heimlich die öffentliche Arbeit.
   - **Sonde:** `--inherit-money` (Söhne teilen das Geld des Vaters) und `--divorce-money` (die Frau nimmt ihren Anteil). Damit gibt es ohne Startgeld +20–22 % Hungertote, und die Kasse prägt.
   - **Stand:** Ramon wählte um 15:43 «Fuhrlohn jetzt, Erbteil weiter prüfen». Das ist der nächste Bauschritt des Geldkreislaufs, als eigene Karte an Ramon.
5. **Geldleck.** Das Startgeld neuer Haushalte (siehe 4) ist die letzte Geldquelle aus dem Nichts. Ausserdem prägt die Kasse bei leerer Kasse (S95, «Geldschöpfung»): ohne Startgeld in Seed 1 42 Mio. in 100 Jahren.
6. **Vorratshaltung kauft nie (S133).** Ramon entschied um 16:41 «So lassen». Die Staatsspeicher sind aus dem Zehnt schon voll. Das ändert sich erst, wenn Missernten kommen.
7. **Aus dem Planungs-Thread «Regierungseinflüsse»** (Pläne verlinkt in S131–S134):
   - Verkauf von Staatsland und Zahlungsrückstand (Plan https://claude.ai/artifact/Q2LzT6aJfzvta8ppQmQby3; die Karte zu Landverkauf und Rückstand ist offen).
   - Später Zoll, Verbrauch-, Einkommen- und Umsatzsteuer.
   - Offene Frage: Wer ist der Spieler?
8. **Kleine Platzhalter**, alle in den S-Zeilen aufgezählt: 12 % Bodenzins (S112), die Aufschläge der Schuld, `PAVE_DAYS` = 9, die Schwelle der Zwangsanleihe von 10 Jahreslöhnen.

## Was als Nächstes ansteht

1. Ramon fragen:
   - Umschuldung bis zur Grenze (Patch bereit)?
   - Missernten bauen (Daten über den Mac holen)?
2. Danach Erbteil (Punkt 4), dann die Ursache der Hungertote mit Wegen (Punkt 3).
3. Den Rust-Neubau auf dem Mac abwarten und die blind gebaute Oberfläche von S133/S134 prüfen lassen.

## Zahlen zur Orientierung (main, Seed 1, 100 Jahre, Standard)

- Im Jahr 100 leben etwa 129'000 Menschen.
- Hungertote: etwa 9'200 in den Jahren 1–30 und 8'700 in den Jahren 31–100.
- Ein Tag der Simulation kostet etwa 3,7 ms; die Obergrenze liegt bei 200'000 Menschen.
- Mit Startgeld leiht der Staat bei keiner Schuldengrenze; die Kasse lebt vom Heimfall.
