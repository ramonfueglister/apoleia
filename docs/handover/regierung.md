# Übergabe: Regierungseinflüsse (Steuern, Ausgaben, Staatsschuld, leere Kasse)

Stand: 31.10.2026, 18:40. Geschrieben vom Planungs-Thread «Regierungseinflüsse nach Vic3-Vorbild planen», damit ein anderer Claude-Account ohne Rückfragen weitermachen kann. Der Planungs-Thread baut nichts. Er recherchiert, schlägt vor und lässt Ramon jeden Schritt auf einer Entscheidungskarte wählen. Gebaut hat jeweils der Simulations-Thread (Rust in `sim/`, Bridge in `sim/godot/`, Oberfläche in `app/`).

Massgeblich für alles Gebaute bleiben `docs/kit2/decisions.md` (S-Nummern) und `docs/kit2/run-grain/README.md` (Läufe, Platzhalter, Literatur). Diese Datei sagt, **was entschieden ist, warum, was gebaut ist und was offen ist**.

---

## 0 Arbeitsregeln (von Ramon, in diesem Thread gesetzt)

1. **Prinzip:** Ein Gesetz oder Erlass ändert nur die Regeln und Geldflüsse echter Haushalte, nie «+10 %»-Zuschläge. Die Wirkung (Preise, Hunger, Zins, Ruf) entsteht in der Simulation. Keine Preisregeln, kein Preisband, kein fester Lohn.
2. **Begriffe:** Im Spiel nur historisch belegte Begriffe, die von 300 bis 2000 tragen (Ramon 07:46, 07:54, 15:56). Erfundene Wörter lehnt er ab («Erntesteuer? häää… sowas gibt es sicher nicht»). Römische Namen erscheinen nur als Geschichte in den Entscheiden. Die Optionen müssen auch im Jahr 2000 passen, nicht nur um 1900 («im jahr 2000 ist soldrückstand nicht mehr so aktuell»).
3. **Realismus:** «möglichst realistisch emergent und für 2000 jahre geschichte möglich» (16:08). Gilt die Literatur, die Ramon will, als dünn, recherchiert man mehr («das recherchierst du mir doch noch etwas mehr»).
4. **Entscheiden:** Ramon wählt per Karte, eine Frage pro Karte, eine Option empfohlen. Danach wird die Machbarkeit mit dem Simulations-Thread geklärt und der Bauumfang übergeben. Ramon gibt Merges frei («mergen»).
5. **Technik:** Jede Spielerentscheidung ist ein `Command` im Befehlslog (`game.rs`), damit Speichern und Wiederholen gleich bleiben. Mit den Startwerten hat die Simulation denselben Fingerabdruck wie vorher. Jeder Baustein hat Schalter und wird über 100 Jahre mit zwei Seeds gerechnet.
6. **Literatur:** APA 7. Was nicht online geprüft wurde, wird gekennzeichnet.
7. **Umfang:** Nur bauen oder ändern, was besprochen ist; nichts nebenbei umgestalten.

## 1 Artefakte (Pläne mit allen Belegen)

Die Artefakte liegen **privat auf Ramons erstem Account**. Ein anderer Account kann sie nicht öffnen. Alles Wesentliche steht deshalb in dieser Datei.

| Artefakt | Link | Inhalt |
|---|---|---|
| Bericht | https://claude.ai/artifact/Xdao5AtgrU4LMsm5EwGxf3 | Victoria 3 im Detail und was wir übernehmen (Bausteine R1–R7) |
| Plan Steuern und Haushalt | https://claude.ai/artifact/12Sa2gxdKcWjYqJdMoSr8F | Begriffe, Steuerarten, D1–D3, Bauumfang S131, Ergebnisse |
| Plan Staatsausgaben | https://claude.ai/artifact/5gxoCKStw7cF3PVYMAiZMA | A1, A2, Bauumfang S133, Ergebnisse, «Leere Kasse: Wege 300–2000» |
| Plan Staatsschuld | https://claude.ai/artifact/3iFcWf8MZ51uC2YyTt539v | Geschichte 300–2000, B1–B4, Bauumfang S134 |
| Plan Leere Kasse | https://claude.ai/artifact/Q2LzT6aJfzvta8ppQmQby3 | Verkauf von Staatsland, Zahlungsrückstand, C1–C3, Bauumfang |

Quellkopie des Berichts (älterer Stand): `/mnt/project-files/regierung/bericht.html` (Projektordner, nur im Projekt sichtbar).

## 2 Vic3 als Vorbild (Bericht, Kurzfassung)

Victoria 3 hat Gesetzesgruppen mit je einem aktiven Gesetz, eine Einführung in drei Phasen mit Rückschlägen, Interessengruppen mit Einfluss und Zustimmung, Legitimität, Institutionen, ein wöchentliches Budget mit Goldreserve, Schuld, Kreditgrenze und Staatsbankrott, feste Steuerstufen, Erlasse sowie Autorität und Bürokratie.

Unsere Bausteine:
- R1 Haushaltsfenster
- R2 Steuergesetz
- R3 Ausgabengesetze
- R4 regionale Erlasse
- R5 Interessengruppen (aus echten Haushalten abgeleitet: Einfluss aus Geld, Land und Köpfen, Zustimmung aus den eigenen Konten)
- R6 Verwaltung und Eintreibung (eine Steuer bringt nur, soweit ihre Grundlage beobachtbar ist; Kleven et al., 2016; Besley & Persson, 2014)
- R7 Gesetzgebung je Regierungsform

**Ramon 07:46: Steuern und Haushalt zuerst.**

## 3 Steuern und Haushalt (R1, R2): gebaut

### Begriffe (geprüft, Ramon 07:50–07:54)
- **Steuerarten:**
  - Zehnt (Antike Sizilien, Kirchen- und Herrenzehnt bis ins 19. Jh., osmanischer Aşar 1/10–1/5 bis 1925)
  - Grundsteuer, Kopfsteuer
  - Einkommensteuer (Lohn, Gewinn, Pacht und Zins, nicht Umsatz)
  - Verbrauchsteuer (je Stück auf bestimmte Waren; historisch Akzise)
  - Umsatzsteuer (Augustus 1 %, Alcabala 1342–1845, Deutschland 1918)
  - Zoll
- **Andere Einnahmen:** Domänen, Heimfall, Geldschöpfung.
- **Ausgaben:** Besoldung, Sold, Öffentliche Bauten, Vorratshaltung, Armenpflege, Zinsen.
- **Fenster:** «Staatshaushalt» («Haushalt» heisst im Spiel die Familie).
- Zahllast und Traglast werden emergent gezeigt. Steuerarten werden nicht nach Epochen freigeschaltet; ihr Ertrag folgt daraus, wie gut die Grundlage beobachtbar ist.

### Entscheide
| Nr. | Zeit | Entscheid |
|---|---|---|
| D1 | 08:07 | Zuerst Zehnt, Grundsteuer, Kopfsteuer |
| D2 | 08:09 | Wer nicht zahlt: Steuerrückstand → Pfändung → Zwangsversteigerung → sonst Domäne (Heimfall an den Staat) |
| Bau | 08:14 | «Bauen nach #100» |
| D3 | 09:56 | Oberste Stufe = historisches Maximum: Zehnt und Grundsteuer 0/5/10/12/15/20 % |
| Kopfsteuer | 10:49 | 0/1/2/4/6/9 Taglöhne je Erwachsenen und Jahr (England 1377: 4 d ≈ 1⅓ Taglöhne; 1381: im Mittel 12 d ≈ 4, Bauernaufstand; Russland 1724: 74 Kopeken je männliche Seele ≈ 9 Taglöhne je Erwachsenen) |

### Gebaut
- **S131 Steuergesetz** (PR #109, Stufen #113, Kopfsteuer-Stufen #115), Code `sim/src/grain/taxes.rs`:
  - Pfändung lässt Essen bis zur Ernte und Saat.
  - Bei der Zwangsversteigerung bleibt die Familie Pächterin des Käufers.
  - Bodenpreis = Ertragswert, also Pacht / 12 % (S112), gedeckelt durch die Rodungskosten (Clark, 2002).
  - Ereignisse 15–17.
- **Ansicht «Staatshaushalt»** im Statistikfenster (#107, Thema Staat).
- **S132 Fuhrlohn** (#115): Die Fracht wird als Taglohn an Fuhrleute bezahlt.

### Ergebnisse S131 (100 Jahre)
- Zehnt 30 % bringt +13 % Hungertote.
- Die Grundsteuer kommt nur zu 42–52 % als Geld herein, der Rest als gepfändetes Korn (dünner Markt, passt zu Hopkins, 1980). Bei «mittel» werden 364 Höfe versteigert und 419 fallen an die Domäne, von rund 17'600.
- Die Kopfsteuer kommt zu 62–73 % als Geld herein.

### Nicht gebaut
Zoll, Verbrauchsteuer, Einkommensteuer, Umsatzsteuer, Vermögensabgabe (als einmalige Abgabe, Lastenausgleich 1952: 50 % in 30 Jahren). Der historische Grundsteuersatz ist noch nicht geprüft.

## 4 Staatsausgaben (R3): gebaut als S133 (PR #121, gemergt)

### Befund vorweg (Simulations-Thread, 12:25)
Die Kasse lebte heimlich vom Heimfall: 222–277 Mio. Denar in 100 Jahren, vor allem von neuen Haushalten mit 1 Mio. Denar Startgeld aus dem Nichts, die ohne Erben sterben (geschiedene Senatorenfrauen). Ohne diese Quelle ist die Kasse ab etwa Jahr 5 leer, der Staat schöpft Geld, und es gibt 22–40 % mehr Hungertote (`/mnt/project-files/sim-probes/geldkreislauf/BEFUND.md`). Ramon wählte «Fuhrlohn jetzt, Erbteil weiter prüfen». **Der Erbteil ist noch offen** (Simulations-Thread). Alle Ausgaben müssen auf Dauer aus Steuern bezahlt werden.

### Entscheide
| Nr. | Zeit | Entscheid |
|---|---|---|
| A1 | 11:00 | Die öffentliche Arbeit (S129) befestigt die meistbegangenen Wege zur Strasse (ändert «Steinstrassen später» aus S127) |
| A2 | 15:44 | «Ja, beide mit Wahl»: Vorratshaltung (Stufen keine / 1 / 3 / 12 Monate des Jahresabsatzes S125 als Kaufdeckel, Kauf nach derselben Regel wie private Lager S123, kein Verkauf unter Preis) und Armenpflege (keine / Notstandsarbeit / Spende an Bedürftige, Start «keine», damit S72 gilt) |

Historische Formen der Armenpflege (Ramon fragte 11:01 «was wäre realistisch?»): Vorratshaltung, Notstandsarbeit (Besley & Coate, 1992), Spende an Bedürftige, Spende an alle Bürger (das Korn für Rom, in S72 ausgeschlossen), Steuernachlass nach Missernten (gehört zu den Erlassen R4).

### Ergebnisse S133 (100 Jahre, Seeds 1 und 2)
- **Wege befestigen:** Nach 25 Jahren sind fast alle begangenen Wege befestigt (115'000–136'000 Feinkacheln, bis Jahr 100 155'000–170'000). Dabei gibt es +9–13 % Hungertote, weniger Einfuhr und einen höheren Kornpreis. **Die Ursache ist nicht untersucht.**
- **Notstandsarbeit:** −8–10 % Hungertote.
- **Spende an Bedürftige:** −54–63 % Hungertote ab Jahr 31 und +10 % Menschen im Jahr 100, für rund 110 t Korn im Jahr (sie kostet Zehntkorn, kein Bargeld).
- **Vorratshaltung** kauft auf keiner Stufe ein Kilo, weil die Staatsspeicher schon 36–43 kt halten, fast zwei Jahre Essen. Ramon wählte im Simulations-Thread (16:41) «Missernten planen»; der Simulations-Thread schrieb dazu einen Vorschlag.

## 5 Staatsschuld: gebaut als S134, PR #128 offen (nicht gemergt)

Ramon 16:02: «Staatsschuld zuerst planen» (vor den übrigen Wegen der leeren Kasse).

### Modell
- Der Staat leiht bei Haushalten mit Bargeld über ihrer Reserve, monatlich per Versteigerung. Jeder bietet einen Betrag und einen Mindestzins. Der Staat nimmt die günstigsten Gebote.
- Mindestzins = Alternativrendite + Risikoaufschlag + Laufzeitaufschlag.
- Den Ruf baut jeder Gläubiger selbst aus seiner Erfahrung auf (North & Weingast, 1989; Stasavage, 2011):
  - Jeder Gläubiger merkt sich seinen Verlust; die Erinnerung verblasst und stirbt mit der Person (Malmendier & Nagel, 2011).
  - Wer nichts erlebt hat, schaut, wie lange der letzte Staatsbankrott her ist.
  - Grössere Schuldenschnitte machen späteres Leihen teurer und schliessen länger vom Markt aus (Cruces & Trebesch, 2013: im Mittel 37 %; Meyer et al., 2022: Median unter 50 %).

### Entscheide
| Nr. | Zeit | Entscheid |
|---|---|---|
| B1 | 16:07 | Der Zins entsteht aus den Geboten der Gläubiger |
| B2 | 16:10 | Die Laufzeit wählt der Spieler im Gesetz: ohne (Rente, der Staat kann zurückkaufen) / 5 / 10 / 30 Jahre; der Zins jeder Laufzeit entsteht aus den Geboten |
| B3 | 16:17 | Gesetz «Wenn die Kasse Zins oder Tilgung nicht zahlen kann»: Geldschöpfung (Start, S95) / Staatsbankrott (anteilige Zahlung, der Rest verloren, der Schnitt entsteht aus der Lücke) / Umschuldung (der Rest wird eine neue Rente mit tieferem Zins, wie Kastilien 1577) |
| B4 | 16:38 | «Alle drei» Zusätze: Schuldengrenze (keine Schuld / 1 / 3 Jahreseinnahmen / ohne; Start keine Schuld; Preussen 1820: Schuld auf 180'091'720 Taler festgeschrieben, neue Anleihen nur mit den Reichsständen), Zwangsanleihe als Erlass (Venedig ab dem 12. Jh., Monte Vecchio 1262, 5 %; Deutsches Reich 1922), Zinsgesetz (frei / Höchstzins 12 % / 5 % / Zinsverbot; Start 12 %, Rom bis Justinian) |
| Bau | 16:48 | «Nach den Ausgabengesetzen» |
| C3 | 17:15 | **Zins-Korrektur:** «12 % für alle, Höchstzins nur privat». Alle Bieter rechnen mit dem Bodenzins aus S112 (12 %, Platzhalter), für Anleihen wie für Land. Der Höchstzins bindet den Staat nicht, das Zinsverbot erzwingt beim Staat weiter die Rente |

**Warum C3:**
- Der Probelauf zeigte: Mit 12 % für alle und dem Höchstzins 12 % hätte niemand geliehen.
- Mit 12 % für Grundherren (Pacht / Bodenwert ist wegen S112 immer 12 %) und 5 % für alle anderen hätten Landlose immer gewonnen.
- Historisch waren Staaten an ihre eigenen Zinsgrenzen nicht gebunden. England lieh 1694 bei der Bank von England zu 8 %, obwohl der Höchstzins 6 % betrug (Bank of England, 2020; Temin & Voth, 2008), und die Leibrente von 1693 zahlte 14 %.
- Das Zinsverbot bestimmte dagegen die Form: Die Rente war erlaubt, wenn der Käufer sie nicht zurückfordern konnte (Innozenz IV. um 1250; Munro).

### Bauumfang (umgesetzt in #128; Platzhalter laut Simulations-Thread)
- **Gesetz «Staatsschuld»** mit vier Werten. Start: keine Schuld, Rente, Geldschöpfung, 12 %. Fingerabdruck gleich wie main.
- **Wann geliehen wird:** Anleihe erst, wenn die Kasse unter die halbe Reserve nach S129 fällt. Rückkauf von Renten zum Nennwert erst über der ganzen Reserve, die teuersten zuerst. Ohne diese Hysterese lieh der Staat und kaufte nach zwei Monaten zurück.
- **Versteigerung:** Alle angenommenen Gebote erhalten den Grenzzins (Einheitspreis). Gebote betragen 50 % des freien Geldes.
- **Zins:** 12 % plus Last (Zinsen/Einnahmen × 10 Prozentpunkte), plus der grössere Wert aus eigener Verlust-Erinnerung × 20 Prozentpunkte und Hörensagen über den letzten Ausfall, plus 5 Basispunkte je Laufzeitjahr (die Rente zählt als 20 Jahre). Keine Gebote, wenn die Zinsen die Einnahmen erreichen.
- **Verlust-Erinnerung:** Zwei Zahlen je Haushalt, das Verblassen wird beim Lesen gerechnet. Stirbt das Oberhaupt (ältester Mann ab 15, sonst der Älteste), wird sie halbiert. Söhne mit eigenem Haushalt nehmen die Hälfte mit.
- **Anleihen** sind eine Liste je Haushalt und werden vererbt. Beim Heimfall erlischt die Schuld, bei Auswanderern verfällt sie.
- **Zwangsanleihe:** Erlass mit 10, 25 oder 50 % zu 5 %. Sie hält die Schuldengrenze ein.
- **Geldbuch:** eigener Posten, «nicht gebucht» bleibt 0.
- **Oberfläche, blind gebaut** (Koordinator 17:22): Gesetzesknöpfe für S133 und die Schuldgesetze, Zeile für die Zwangsanleihe, Gläubigerliste mit Gesichtern, drei Verlaufskarten, «Zinsen» im Budget.
- **Läufe:** mit und ohne Startgeld (Probe `--inherit-money --divorce-money`).

## 6 Leere Kasse: Verkauf von Staatsland und Zahlungsrückstand — geplant, NICHT gebaut

Ramon 16:55: «Rest der leeren Kasse». Die Vermögensabgabe gehört zu den Steuern (siehe 3). Die Geldschöpfung gibt es schon (S95).

### Entscheide
| Nr. | Zeit | Entscheid |
|---|---|---|
| C1/C2 | 18:34 | «Erlass und Gesetzeswahl»: Den Landverkauf befiehlt der Spieler als Erlass. Der Zahlungsrückstand wird eine Wahl im Gesetz «Wenn die Kasse leer ist» (Geldschöpfung als Start / Zahlungsrückstand) |
| C3 | 17:15 | 12 % für alle Bieter, gilt auch für den Landverkauf (siehe 5) |

### Belege
- **Landverkauf:**
  - Rom: ager quaestorius.
  - England ab 1536: Klöster; mehr Gentry, Erträge und Gewerbe (Heldring et al., 2021).
  - Frankreich ab 1789: Nationalgüter, gekauft von Bürgern und reichen Landwirten; die Produktivität stieg (Finley et al., 2021).
  - Spanien 1836: Desamortisation, Gewinner waren die Wohlhabenden.
  - Treuhand 1990–1994: 70 Mrd. DM Erlös, am Ende fast 260 Mrd. DM Defizit.
  - Massenverkäufe drücken den Preis, wenn den Käufern das Geld fehlt (Shleifer & Vishny, 1992).
- **Zahlungsrückstand:**
  - Flandern 1572–1609: 45 Meutereien, Antwerpen 1576.
  - Russland 1996: 62 % der Beschäftigten betroffen, im Mittel 1,7 Monatslöhne; gekündigt wurde nur, wo es andere Arbeit gab (Lehmann et al., 1999; Earle & Sabirianova Peter, 2002).
  - USA 2018/2019: 35 Tage ohne Haushalt, rund 800'000 Bundesangestellte ohne Lohn, Nachzahlung per Gesetz.

### Bauumfang (Vorgaben des Planungs-Threads, mit dem Simulations-Thread geprüft um 17:02)
1. **Erlass «Staatsland verkaufen»** für alle Domänen oder die Domänen im Gebiet eines Markts:
   - Versteigerung wie bei S131 zum Zweitgebot unter den Haushalten des Markts.
   - Ein Gebot beträgt höchstens das freie Bargeld und höchstens Pacht / 12 %.
   - Ohne Gebot bleibt der Hof Domäne.
   - Der Käufer wird Grundherr, die Familie bleibt Pächterin.
2. **Staatsfelder des Spielers** sind ein Flächenanteil in einem Hof, und ein Hof hat nur einen Grundherrn. Ohne Umbau kann sie darum nur der bebauende Hof ablösen, zum Ertragswert.
3. **Gesetz «Wenn die Kasse leer ist»** greift erst, wenn das Schuldgesetz kein Leihen mehr erlaubt, und gilt nicht für Zins und Tilgung (dort gilt B3). Bis es gebaut ist, wird der Sold nach S95 geschöpft.
4. **Zahlungsrückstand:**
   - Zuerst pausieren die öffentliche Arbeit, die Käufe für den Vorrat und die Bauaufträge.
   - Dann werden Besoldung und Sold anteilig bezahlt, der Rest wird je Haushalt als Rückstand gebucht.
   - Nachgezahlt wird zuerst das Älteste.
   - Der Rückstand wird mit dem Steuerrückstand desselben Haushalts verrechnet und erlischt beim Heimfall.
5. **Staatsdienst:** Heute behalten Soldaten, Offiziere und Beamte ihren Beruf, und der Staat wirbt niemanden an (S110). Vorgabe:
   - Ist der Rückstand älter als 3 Monate (Platzhalter), verlässt der Haushalt den Staatsdienst wie bei S87.
   - Ohne Rückstand wirbt der Staat unter den Arbeitsuchenden an, bis die Stärke vom Spielbeginn erreicht ist.
6. **Geldbuch:** Posten für den Erlös aus Landverkäufen und für Rückstände (entstanden, nachgezahlt, verrechnet, erloschen).
7. **Sichtbar:**
   - Meldungen je Verkauf und beim ersten Rückstand.
   - Im «Staatshaushalt»: Erlös, verlorene Pacht und Rückstand.
   - Im Personenfenster: «Sold seit … Monaten offen».
   - Im Hoffenster: der Eigentümer.
8. **Läufe:** 100 Jahre, 2 Seeds, mit leerer Kasse (zum Beispiel Zehnt 0): Geldschöpfung gegen Zahlungsrückstand, einmal ein Verkauf aller Domänen, mit und ohne Startgeld.

## 7 Offene Punkte (in dieser Reihenfolge sinnvoll)

1. **PR #128 (Staatsschuld S134)** wartet auf Ramons «mergen» und ist nicht auf dem Mac geprüft (Rust-Neubau nötig).
2. **Wann Landverkauf und Zahlungsrückstand gebaut werden.** Die Karte wurde um 18:36 zurückgezogen, weil die Threads geschlossen werden. Empfehlung: gleich nach #128, Bauumfang wie in Abschnitt 6.
3. **Erbteil / Startgeld** (Simulations-Thread, S132-Probe): Davon hängt ab, wie oft die Kasse leer ist.
4. **Ursache der +9–13 % Hungertote durch das Befestigen der Wege** (S133) ist unbekannt.
5. **Vorratshaltung kauft nichts**; Missernten (Ramon 16:41) sind im Simulations-Thread vorgeschlagen.
6. **Wer der Spieler ist** (Kaiser, Statthalter, Staat): bestimmt, wer Gesetze erlassen darf und wie sich das bis 2000 wandelt (R7).
7. **Preisedikt von 301** als Spielergesetz mit emergenten Folgen (Schwarzmarkt, Hortung).
8. **Interessengruppen** (R5), ob fest wie in Vic3 oder aus den Haushalten abgeleitet; echte Aufstände.
9. **Regionale Erlasse** (R4, zum Beispiel Steuernachlass nach Missernten) und **Verwaltung** (R6).
10. **Weitere Steuern**: Zoll, Verbrauchsteuer, Einkommensteuer, Umsatzsteuer, Vermögensabgabe; den historischen Grundsteuersatz prüfen.
11. **Der Satz von 12 %** ist ein Platzhalter (S112). Über die Jahrhunderte fiel der Zins (Schmelzing, 2020). Sobald es private Kredite gibt, wirkt auch der Höchstzins.

## 8 Literatur (Auswahl, APA 7)

- Bank of England. (2020). *Details of the Bank of England loan to the government in 1694*. https://www.bankofengland.co.uk/freedom-of-information/2020/details-of-the-bank-of-england-loan-to-the-government-in-1694
- Besley, T., & Coate, S. (1992). Workfare versus welfare. *American Economic Review, 82*(1), 249–261. [nicht online geprüft]
- Besley, T., & Persson, T. (2014). Why do developing countries tax so little? *Journal of Economic Perspectives, 28*(4), 99–120.
- Böick, M. (2022). Treuhandanstalt. In *Handwörterbuch des politischen Systems* (8. Aufl.). bpb.
- Clark, G. (2002). Land rental values and the agrarian economy: England and Wales, 1500–1914. *European Review of Economic History, 6*(3), 281–308.
- Cochrane, J. H. (2023). *The fiscal theory of the price level*. Princeton University Press.
- Cruces, J. J., & Trebesch, C. (2013). Sovereign defaults: The price of haircuts. *American Economic Journal: Macroeconomics, 5*(3), 85–117.
- Drelichman, M., & Voth, H.-J. (2007). *The sustainable debts of Philip II* [Entwurf].
- Earle, J. S., & Sabirianova Peter, K. (2002). How late to pay? Understanding wage arrears in Russia. *Journal of Labor Economics, 20*(3), 661–707.
- Eichengreen, B., El-Ganainy, A., Esteves, R., & Mitchener, K. J. (2021). *In defense of public debt*. Oxford University Press.
- Finley, T., Franck, R., & Johnson, N. D. (2021). The effects of land redistribution: Evidence from the French Revolution. *The Journal of Law and Economics, 64*(2), 233–267.
- Heldring, L., Robinson, J. A., & Vollmer, S. (2021). The long-run impact of the dissolution of the English monasteries. *The Quarterly Journal of Economics, 136*(4), 2093–2145.
- Hopkins, K. (1980). Taxes and trade in the Roman Empire. *The Journal of Roman Studies, 70*, 101–125.
- Kleven, H. J., Kreiner, C. T., & Saez, E. (2016). Why can modern governments tax so much? *Economica, 83*(330), 219–246.
- Lehmann, H., Wadsworth, J., & Acquisti, A. (1999). Grime and punishment. *Journal of Comparative Economics, 27*, 595–617.
- Malmendier, U., & Nagel, S. (2011). Depression babies. *The Quarterly Journal of Economics, 126*(1), 373–416. [nicht online geprüft]
- Meyer, J., Reinhart, C. M., & Trebesch, C. (2022). Sovereign bonds since Waterloo. *The Quarterly Journal of Economics, 137*(3), 1615–1680.
- Miranda, M. J., & Helmberger, P. G. (1988). The effects of commodity price stabilization programs. *American Economic Review, 78*(1), 46–58. [nicht online geprüft]
- North, D. C., & Weingast, B. R. (1989). Constitutions and commitment. *The Journal of Economic History, 49*(4), 803–832.
- Reinhart, C. M., & Sbrancia, M. B. (2011). *The liquidation of government debt* (NBER WP 16893).
- Schmelzing, P. (2020). *Eight centuries of global real interest rates, R-G, and the ‘suprasecular’ decline, 1311–2018* (BoE SWP 845).
- Shleifer, A., & Vishny, R. W. (1992). Liquidation values and debt capacity. *The Journal of Finance, 47*(4), 1343–1366. [nicht online geprüft]
- Stasavage, D. (2011). *States of credit*. Princeton University Press.
- Temin, P., & Voth, H.-J. (2008). Interest rate restrictions in a natural experiment. *The Economic Journal, 118*, 743–758.

Weitere Belege mit Links (HLS «Renten», Wikipedia «Wucher», Venedig, DIW «Zwangsanleihen», Preussische Verordnung 1820, Larousse, Smith 1875) stehen in den Artefakten. Fehlt der Zugang, findet man sie über die genannten Stichworte.
