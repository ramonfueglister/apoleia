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
`docs/handover/sim-geldkreislauf/probe-on-s134.patch` passt auf main `5b8167d`. Es fügt
`--inherit-money --divorce-money` hinzu.

Alle Läufe von S134 mit Auswertung (`tab2.py`) liegen in `/mnt/project-files/sim-probes/geldkreislauf/runs-s134/`.
Der Befund der Sonde steht in `docs/handover/sim-geldkreislauf/BEFUND.md`.

## Offene Punkte (nach Wichtigkeit)

1. **Umschuldungs-Spirale (S134).**
   - **Befund:** Mit dem Gesetz «Umschuldung» wird jeder unbezahlte Zins jedes Jahr zu einer neuen Rente. Im Lauf ohne Startgeld, Seed 1, stieg die Schuld so bis Jahr 100 auf 62 Mio. Denar, das 33-Fache der Jahreseinnahme. Die Schuldengrenze begrenzt nur neue Anleihen.
   - **Vorschlag:** Umschulden nur bis zur Grenze; der Rest fällt wie beim Staatsbankrott aus. Die Karte dazu wurde zurückgezogen, weil die Threads geschlossen wurden; **Ramon hat noch nicht entschieden.**
   - **Bereit:** Das Patch `docs/handover/sim-geldkreislauf/s134-umschuldung-bis-grenze.patch` passt auf main. Die Tests in `debt.rs` sind damit grün; ein 100-Jahr-Lauf damit fehlt noch.
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

## Anhang: Inhalt der verlinkten Dokumente

Die Links auf claude.ai sind privat auf Ramons erstem Account. Darum steht hier das Wesentliche. Bereits
in `docs/kit2/decisions.md` festgehalten sind die Pläne zu Steuern (S131), Staatsausgaben (S133) und Staatsschuld (S134).

### A. Missernten: Vorschlag (31.10.2026; Karte an Ramon offen)

**Ausgangslage:** Ramon hat am 29.10. S101 gewählt, dann aber zurückgestellt: echtes Wetter, dazu lokaler Zufall. Gebaut ist nichts, weil die Daten in der Cloud gesperrt sind. Die Missernte ändert nur den Ertrag eines Jahres. Preis, Handel, Staatsspeicher, Armenpflege, Hunger und Wanderung folgen aus den Regeln, die schon gebaut sind (S112, S123, S71, S115, S133, S75, S89, S93).

**Vorschlag:** S101 erweitern. Die Entscheide E1 bis E5 waren je mit einer Empfehlung versehen.

- **E1 Daten: OWDA und PHYDA.**
  - Der Old World Drought Atlas (OWDA; Cook u. a., 2015) liefert die Sommertrockenheit (scPDSI Juni bis August):
    - Raster 0,5°, Jahre 0–2012, Gebiet 27–71° N und 12° W bis 45° O,
    - aus 106 Baumring-Chronologien,
    - keine Kälte.
  - PHYDA (Steiger u. a., 2018) liefert PDSI, SPEI und Temperatur:
    - Raster ≈ 2°, Jahre 1–2000, ganze Welt.
    - PHYDA deckt Mesopotamien östlich von 45° und Oberägypten ab und liefert überall die Sommertemperatur.
  - Ziel ist eine kleine Datei: je Region und Jahr ein Byte Trockenheit und ein Byte Temperatur. Für 1'783 Regionen und 1'820 Jahre sind das etwa 6,5 MB.
  - Das Spiel läuft von 180 bis höchstens 1914 (S05). Für jedes Spieljahr gibt es also echte Daten.
- **E2 Was den Ertrag senkt:** Dürre, Nässe und Kälte, nicht nur Dürre.
  - Formel: `Ertrag = Normalertrag × (1 − Dürre − Nässe − Kälte) × Zufall des Hofs`
  - **Dürre:** wächst unter einem Sommerwert von −1, im trockenen Süden stärker.
  - **Nässe:** erst ab +3, vor allem im Norden (Fäulnis, Rost; Beispiel 1315–1317).
  - **Kälte:** ein Sommer mehr als 1 °C unter dem Üblichen, vor allem im Norden und im Gebirge (Beispiel 536–545; Büntgen u. a., 2016: in den 540er Jahren in den Alpen 1,9 °C kälter).
  - Die Steigungen sind PLATZHALTER. Ziel: Ein Hof schwankt im Mittel um 15–20 %, und das Wetter erklärt etwa ein Drittel davon.
- **E3 Zufall nach Grösse des Ereignisses:**
  - Hagel je Hof: etwa 2 % der Höfe im Jahr, Verlust 30–70 % der Ernte.
  - Schädlinge und Rost je Region: hängen an der Nässe aus den Klimadaten, dazu ein kleiner Zufall pro Region.
  - Heuschrecken nur in Nordafrika, Ägypten und dem Nahen Osten, selten in Südosteuropa: ein Zug alle 10–15 Jahre, 1–3 Jahre lang, Verlust je Region 20–80 %.
  - Alle Zahlen sind PLATZHALTER.
- **E4 Wetter je Spiel:** Standard ist das echte Wetter jedes Jahres. Ein Schalter beim Spielstart mischt stattdessen echte Jahre, in Blöcken von zehn Jahren, damit mehrjährige Dürren und das Muster über die Karte erhalten bleiben.
- **E5 Daten:** in einer kurzen Mac-Sitzung holen, nicht über eine Freigabe in der Cloud. Gesperrt sind ncei.noaa.gov, paleo.ltrr.arizona.edu und zenodo.org.

**Nil:** eigene Reihe aus den Wasserständen des Nilometers auf Roda, 622–1922 (Kondrashov u. a., 2005).

- Gerechnet wird mit der Abweichung vom Mittel der Jahrzehnte davor, weil sich das Flussbett hob.
- Vor 622 und in Lücken werden Jahre aus der Verteilung des Nilometers gezogen.
- Nach grossen Vulkanausbrüchen (536, 540, 547 und andere) fällt die Flut niedrig aus (Manning u. a., 2017).
- Die Flut bestimmt die bewässerte und gesäte Fläche: zu niedrig heisst weniger Fläche, zu hoch heisst gebrochene Dämme.

**Sichtbar machen:** eine Kartenansicht «Ernte» (Ertrag gegen normal je Region), Meldungen («Dürre in Apulien», «Hagel auf dem Hof von …», «Niedrige Nilflut») und eine Spalte im Verlauf. Das kostet ein Nachschlagen je Region und Jahr, also kaum Rechenzeit.

**Prüfung, nicht Eichung.** Nach 100 Jahren mit zwei Seeds und einem Lauf über die bekannten Krisenjahre (nur mit echtem Wetter) soll herauskommen:

| Was | Ziel | Quelle |
|---|---|---|
| Schwankung des Ertrags je Hof (Variationskoeffizient) | 13–20 % | Salter, 2023; Campbell & Ó Gráda, 2011 |
| Anteil des Wetters daran | etwa ein Drittel | Ray u. a., 2015 |
| Schlechte Weizenjahre in Attika | etwa 1 von 4 | Garnsey, 1988, nicht selbst nachgelesen |
| Bekannte Krisen | sichtbar: 536–545 kalt, 1315–1317 nass im Norden, 1540 trocken in Mitteleuropa, 1740–1741 Irland | |
| Preis | steigt in schlechten Jahren deutlich und fällt danach wieder, ohne Preisregel | |

**Vergleich mit anderen Spielen:** Victoria 3 würfelt «Erntebedingungen» je Region, EU5 lässt Wetterfronten ziehen. Mit echtem Wetter je Jahr und Region wäre Apoleia einzigartig.

**Quellen** (APA 7, wie im Vorschlag):

- Büntgen, U., et al. (2016). Cooling and societal change during the Late Antique Little Ice Age from 536 to around 660 AD. *Nature Geoscience, 9*, 231–236. https://doi.org/10.1038/ngeo2652
- Campbell, B. M. S., & Ó Gráda, C. (2011). Harvest shortfalls, grain prices, and famines in preindustrial England. *The Journal of Economic History, 71*(4), 859–886. (nur die Zusammenfassung gelesen)
- Cook, E. R., et al. (2015). Old World megadroughts and pluvials during the Common Era. *Science Advances, 1*(10), e1500561. https://doi.org/10.1126/sciadv.1500561
- Kondrashov, D., Feliks, Y., & Ghil, M. (2005). Oscillatory modes of extended Nile River records (A.D. 622–1922). *Geophysical Research Letters, 32*(10), L10702.
- Manning, J. G., et al. (2017). Volcanic suppression of Nile summer flooding triggers revolt and constrains interstate conflict in ancient Egypt. *Nature Communications, 8*, 900.
- Peña-Gallardo, M., et al. (2019). The impact of drought on the productivity of two rainfed crops in Spain. *Natural Hazards and Earth System Sciences, 19*, 1215–1234.
- Ray, D. K., Gerber, J. S., MacDonald, G. K., & West, P. C. (2015). Climate variation explains a third of global crop yield variability. *Nature Communications, 6*, 5989.
- Salter, G. (2023, 27. Oktober). *Risk management in the 14th century* [Blogbeitrag]. LSE Economic History Blog.
- Steiger, N. J., Smerdon, J. E., Cook, E. R., & Cook, B. I. (2018). A reconstruction of global hydroclimate and dynamical variables over the Common Era. *Scientific Data, 5*, 180086.

### B. Angebot und Nachfrage in Apoleia (Prüfung vom 30.10.2026, Stand main d7fa795, vor S129)

Es gibt keinen Auktionator und keinen Grundpreis.

**Wie der Kornpreis entsteht:**

- Jeder der rund 860 Märkte hat Marktleute mit Lager und Bargeld. Sie kaufen zum Preis −10 % und verkaufen zum Preis +10 %.
- Jeden Tag läuft der Preis 1/30 des Wegs zum Angebot:
  `Angebot = üblicher Preis × Jahreszeit × √((90 + 7) / (Lagertage + 7))` (S112, `pricing::quote`).
- **Lagertage** = Lager geteilt durch den Absatz pro Tag (30-Tage-Mittel aus verkauft plus gesucht und nicht gefunden).
- **Jahreszeit** = Lagerpfad aus Zins 12 % plus Verderb 4 %: von −8 % nach der Ernte bis +8 % davor (Williams & Wright, 1991).
- **Üblicher Preis** = das Gedächtnis des Markts. Er steigt unter 30 Tagen Lager und fällt ab 180 Tagen, höchstens um 1/365 pro Tag (nach Lengnick, 2013).

**Angebot:**

- Höfe behalten Essen bis zur Ernte plus 60 Tage und die Saat. Den Rest verkaufen sie nur zum üblichen Ankaufspreis der Jahreszeit oder darüber.
- Staats- und Grundherrenspeicher verkaufen wöchentlich nach derselben Regel.
- Marktleute kaufen höchstens bis 180 Tage Absatz.
- Höfe säen Eigenbedarf × 1,25 und den Rest ihrer Felder nur, wenn der Erlös die Lohnkosten deckt.

**Nachfrage:**

- Haushalte ohne Korn kaufen unter 30 Tagen Vorrat bis 60 Tage, soweit das Geld reicht.
- Höfe kaufen, wenn ihr Speicher knapp wird.
- Die Schweinemast füttert 5 kg Korn für 1 kg Fleisch, wenn es sich lohnt.
- Die vier Märkte draussen reagieren mit einer Elastizität von −0,065.

**Handel:**

- Jeder Markt kennt 32 Märkte, mit Preisen so alt wie die Reisezeit der Nachrichten.
- Holen (wöchentlich, S114) und Schicken (über 90 Tage Lager, S120) folgen dem Preisabstand minus Fracht (Samuelson, 1952; Takayama & Judge, 1971).
- Die Fracht ist vor allem Lohn (Edikt XVII.3) und halbiert sich auf Strassen.

**Lohn:**

- Wöchentliche Arbeitsbörse je Markt. Der Lohn bewegt sich mit dem Anteil offener gegen liegen gebliebene Tage, höchstens 1/20 pro Woche.
- Untergrenze: Niemand bietet Tage an, wenn 290 Tage Lohn sein Essen nicht decken.
- Obergrenze: Höfe stellen nur ein, solange ein Tag mehr Korn bringt, als er kostet.

**Urteil:**

- **Korrekt:** Handel nach Preisabstand minus Fracht, Halten nach dem Lagerpfad, Puffersparen (Carroll, 1997), Einstellen bis zum Grenzprodukt.
- **Vertretbar** (Zahlen frei gewählt): die Kaufregel der Haushalte; der Preis der Marktleute gegen ihr Lager (ihr «üblicher Preis» hat keinen festen Anker); die Lohnregel (einfacher als Mortensen & Pissarides); die Platzhalter ±10 %, 12 %, 90 und 180 Tage.
- **Fraglich:**
  1. **Nachfrage in Kilogramm statt in Denar.** Mehr Geld erhöht die Nachfrage nicht, darum ist das Preisniveau in Denar unbestimmt. Ohne diese Verbindung gibt es keine Inflation durch Münzverschlechterung und keine Preisrevolution.
  2. **Keine anderen Kulturen.** Bei Überschuss kann das Angebot nicht auf Wein, Öl, Hülsenfrüchte oder Weide ausweichen.
  3. **Staatsspeicher verkaufen wie private Händler.** Historisch ging das Steuerkorn an Heer und Städte.
  4. **Feste Konsumanteile.** Es fehlt das Engelsche Gesetz und damit der Strukturwandel.

**Damaliger Befund:** Der Kornpreis fiel auf 0,10–0,15 Denar/kg. Seit S129/S130 (Kasse gibt aus, Jahresplan der Höfe) liegt er bei etwa 0,7–1,3 Denar/kg. Die Punkte 1, 2 und 4 sind weiter offen.

### C. Leere Kasse: Verkauf von Staatsland und Zahlungsrückstand (Planungs-Thread; Karte offen)

- **Verkauf von Staatsland:**
  - Domänen werden versteigert: die Höfe aus S131 ohne Bieter und die Staatsfelder, die der Spieler gebaut hat.
  - Ein Gebot ist die Pacht geteilt durch die eigene Rendite (12 %), höchstens das freie Bargeld. Es gilt das Zweitgebot. Die Familie bleibt als Pächterin.
  - Belege: England 1536, die biens nationaux in Frankreich, die Desamortización 1836 in Spanien, die Treuhand.
  - Staatsfelder in einem Hof könnten nur vom bebauenden Hof abgelöst werden.
- **Zahlungsrückstand** als Wahl im Gesetz «Wenn die Kasse leer ist» (neben der Geldschöpfung):
  - Zuerst ruhen öffentliche Arbeit, Vorratskäufe und Bau.
  - Dann werden die Löhne anteilig gezahlt; der Rückstand je Haushalt wird später gezahlt, der älteste zuerst.
  - Staatsdiener gehen nach N Monaten Rückstand (PLATZHALTER).
  - Lohnrückstand wird mit Steuerrückstand verrechnet.
  - Belege: die Meutereien in Flandern 1572–1609, Russland 1996.
- Empfohlen war: Landverkauf als Erlass des Spielers, Rückstand als Wahl im Gesetz. **Nicht entschieden.**
