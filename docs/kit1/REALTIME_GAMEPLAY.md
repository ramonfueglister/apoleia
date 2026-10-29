# Echtzeit-Gameplay wie Cities Skylines — Ziel, Stand der Technik 2026 und Plan

**Stand:** 29.10.2026 · **Status:** Ziel `bestätigt` (Ramon, 29.10.2026), Plan `bestätigt`
(„implementiere vollständig“), Umsetzung `teilweise` (siehe [Umsetzungsstand](#umsetzungsstand)).
Gehört zu den Wünschen für spätere Kits ([decisions.md](decisions.md)); gebaut wird es in der
Simulation (Kit 2, `sim/`) und im Client (`app/`), nicht in Kit 1.

## Ziel

Der Spieler baut Höfe, Felder und Strassen, während die Welt weiterläuft, und sieht die
Folgen sofort, wie in Cities Skylines. Der Anspruch ist der Stand der Technik 2026: In
Simulationstiefe, ökonomischer Korrektheit, Determinismus und Leistung soll Apoleia
besser sein als Cities: Skylines II. Dabei gilt Ramons Grundsatz: alles emergent, keine
Preis- oder Lohnformel von oben ([Kit 2 decisions.md](../kit2/decisions.md), S94–S100).

## Ausgangslage (29.10.2026, vor der Umsetzung)

- **Die Sim tickte schon live.** `ApoleiaPeople` (`sim/godot/src/people_dots.rs`) rechnet
  Menschen und Getreidewirtschaft Tag für Tag auf einem eigenen Thread; das Bild wartet
  nie. Standard 10 Tage pro Sekunde, `[` und `]` halbierten oder verdoppelten das Tempo,
  eine Pause gab es nicht.
- **Leistung:** ganzer Tag mit 100'000 Menschen und Getreide Median 3,7 ms, 99 % 9 ms
  ([run-grain](../kit2/run-grain/README.md)); auf der 4-Kern-Cloud-Maschine dieses Threads
  7,9 ms und 17 ms (`sim/examples/game_bench.rs`). Mac-Messung (B08) offen.
- **Befehle:** Der Thread „Minimalistisches Baumenü“ (PR #47) baute den Befehlsweg:
  `Queue.commands` → `apoleia_sim::build::Orders` mit Protokoll (Sim-Tag, Befehl).
- **Monats-Sim:** `ApoleiaSim` (Bevölkerung pro Tile, Pause, F5/F9) ist seit S50 durch
  einzelne Menschen fachlich ersetzt. Korrektur zur ersten Fassung dieses Plans: Sie läuft
  im Spiel **nicht** mit; `population_map_mode.gd` wird von `landscape.gd` nicht geladen.
  Im Spiel gibt es also schon nur eine Sim und eine Uhr.
- **Kulisse:** Stadt und Kolosseum (`app/scripts/voxel/`) sind fest gebaut, nicht aus der Sim.

## Stand der Technik 2026

### Was die Vorbilder machen

| Vorbild | Was es gut macht | Was schiefging oder fehlt | Was wir übernehmen |
|---|---|---|---|
| **Cities: Skylines II** (2023, Unity ECS) | Jeder Bürger einzeln mit Lebenslauf, Haushalt, Tagesablauf; kein festes Agentenlimit, nur die Hardware begrenzt [1][2] | Wirtschaft nach eigener Aussage „nicht auf dem Qualitätsstandard“: Bodenwert und Mieten fehlerhaft, Finanzanzeige falsch, Firmengewinne unklar [3]. Leistung: Studio verliess sich auf unfertige Engine-Technik (ECS mit langen Jobs, HDRP) und musste viel selbst bauen [4] | Einzelne Menschen, Tagesablauf. Nicht übernehmen: Abhängigkeit von unfertiger Engine-Technik, Wirtschaft ohne prüfbare Bilanz |
| **Victoria 3 / EU5** (Paradox, Jomini) | Sim-Thread rechnet seriell Spielzustand und Befehle; Tick-Tasks mit Frequenz und Abhängigkeiten, parallele Vorschritte plus Sortierschritt für Mehrspieler; Dirty Flags; Kosten hängen an der Zahl der Objekte, nicht an der Bevölkerung [5] | Spätspiel langsam, gelöst u. a. durch Zusammenlegen kleiner Pops [5] | Steht schon in S42–S47; gilt jetzt auch für die Tages-Sim |
| **Factorio** | Nur Spieleraktionen werden übertragen, jede Instanz rechnet deterministisch dieselbe Welt (Lockstep); ein Puffer verdeckt die Latenz; Abweichungen heissen Desync [6] | – | Befehlsprotokoll als einzige Eingabe, Fingerabdruck als Desync-Prüfung, Wiederholung und Mehrspieler aus demselben Mechanismus |
| **Workers & Resources: Soviet Republic** | Jede Strasse und jedes Gebäude wird aus Material und mit Arbeitern gebaut; man zahlt entweder ausländische Firmen oder lässt eigene Bauleute auf die Baustelle fahren [7] | – | Entspricht S74 (Tagelöhner mit Marktlohn): Bauen kostet echte Arbeit und echtes Material |
| **Anno 117: Pax Romana** (Nov. 2025) | Römisches Setting, Produktionsketten über Inseln, Bedürfnisstufen; erfolgreichstes Anno [8] | Wirtschaft ist Produktionskette mit festen Raten, keine Preise | Lesbarkeit der Ketten im Interface; nicht das feste Ratenmodell |

### Was die Forschung beiträgt

- **Fester Takt, gleitende Darstellung** (Gaffer on Games [9]): Die Sim rechnet in festen
  Schritten, die Darstellung interpoliert zwischen den letzten zwei Zuständen. So bleibt die
  Bewegung bei jedem Tempo flüssig, ohne dass die Sim schneller rechnen muss.
- **Wahrnehmungsgesteuerte Simulation** (Sunshine-Hill und Badler, AIIDE 2010 [10]): Nur der
  sichtbare Teil der Welt wird fein simuliert, der Rest mit günstigen Näherungen, die
  statistisch nicht vom Original zu unterscheiden sind. **Für uns nur in der Darstellung:**
  Der massgebliche Zustand darf nie von der Kamera abhängen, sonst ist er nicht mehr
  deterministisch. Feine Details wie Gehbewegungen, Gesichter oder Gespräche entstehen
  in der Darstellung aus dem Sim-Zustand.
- **Agenten auf der GPU** (FLAME GPU 2, 2023 [11]: bis 16 Mio. Agenten; LPSim, Berkeley 2024 [12]: 9 Mio. Fahrten im
  Bay-Area-Netz in etwa 2,4 Minuten auf zwei A100, rund 113-mal schneller als auf der CPU):
  Nützlich, falls Verkehr später teuer wird. Gleitkomma auf GPUs verschiedener Hersteller
  ist nicht bitgleich, darum bleibt der massgebliche Zustand auf der CPU in Festkomma (S44);
  die GPU rechnet nur Darstellung oder Vorschläge, die der Sim-Thread prüft.
- **Sprachmodell-Agenten** (Project Sid 2024 [13], über 1000 Agenten in Minecraft; CitySim,
  2025 [14], Zehntausende Agenten mit Tagesplänen): zeigen glaubwürdiges Verhalten, sind aber
  zu teuer und nicht deterministisch für den Tagestakt. Möglicher Platz später: Texte und
  Geschichten aus dem Ereignisprotokoll, ausserhalb der Sim.
- **Werkzeuge:** Godot 4.6 (Januar 2026) kann externe Profiler wie Tracy und Perfetto auch für
  GDExtensions anbinden [15]; damit messen wir Sim, Übergabe und Zeichnen in einem Bild.

## Wo wir besser sein wollen als Cities: Skylines II

Ehrlich eingeschätzt: In Inhalt und Breite (Verkehrsarten, Dienste, Zonen, Modding, Menge
an Grafik) holen wir ein Studio nicht ein. Besser sein können wir dort, wo CS2 Schwächen
zugegeben hat oder bewusst vereinfacht:

1. **Ökonomisch korrekt und prüfbar.** Jeder Denar ist gebucht; Geldmenge = geprägt −
   vernichtet wird jeden Tag als Test geprüft. Preise entstehen aus Handel, nicht aus Formeln.
2. **Erklärbar.** Zu jedem Preis, Lohn und Hof zeigt das Spiel, wer kauft, wer verkauft und
   warum. CS2 musste nachträglich versprechen, verständlich zu machen, woher hohe Mieten
   kommen [3]; bei uns gehört das zur Abnahme.
3. **Deterministisch.** Gleiches Befehlsprotokoll ergibt bitgleich dieselbe Welt: Speichern,
   Wiederholen, Fehler nachstellen und später Mehrspieler aus einem Mechanismus.
4. **Leistung durch Architektur statt Hoffnung.** Eigener Rust-Kern, keine Abhängigkeit von
   unfertiger Engine-Technik; Zielwerte pro Tempostufe werden gemessen, nicht geschätzt.
5. **Bauen mit echter Arbeit.** Baustellen brauchen Tagelöhner und Material aus der
   Wirtschaft (S74), wie bei Workers & Resources, statt Geld gegen sofortige Fertigstellung.

## Grundsätze für die Umsetzung

- **Eine Spiel-Sim:** die Tages-Sim aus Menschen und Getreide. Godot hält keinen
  Spielzustand; alles, was der Spieler tut, ist ein Befehl, alles, was er sieht, kommt aus dem
  veröffentlichten Zustand zurück (S40, S43, S45).
- **Befehle** werden am Anfang eines Tages angewendet, vor `people.day()` und `grain.day()`,
  sortiert nach Tag und Eingangsnummer, und mit dem Anwendungstag protokolliert. Der Sim-Thread
  darf ein paar Tage vor dem Bild sein; das ist unser Latenzpuffer wie bei Factorio.
- **Hintergrundarbeiten** (Strassen-, Weg- und Zählarbeiter in `grain.rs`) sehen Änderungen
  erst ab ihrem nächsten Lauf, damit das Ergebnis nicht vom Thread-Timing abhängt.
- **Kamera beeinflusst nie den Spielzustand**, nur die Darstellung.
- **Festkomma im Zustand**, Gleitkomma nur innerhalb eines Schritts (S44).

## Phasen

| # | Was | Grösse | Hängt ab von | Abnahme |
|---|---|---|---|---|
| 1 | **Befehlsweg** (läuft im Baumenü-Thread) | mittel | – | Hof per Klick gesetzt, wird gebaut und bezogen; gleiches Protokoll = gleicher Fingerabdruck mit 1 und 4 Threads |
| 2 | **Zeitsteuerung:** echte Pause, Stufen 1–4 = 2 / 10 / 30 / 100 Tage pro Sekunde, Uhr mit Datum und Tempo; Bauen auch in der Pause | klein | – | Pause ohne Ruckeln; Stufe 3 hält auf dem Mac 60 Bilder/s, sonst zeigt die Uhr, dass die Sim nicht nachkommt |
| 3 | **Sofortige Rückmeldung:** Vorschau beim Platzieren (Sim beantwortet „geht das hier?“), nur betroffene Kacheln der Feld- und Strassenschicht neu statt alle 30 Tage, Baustelle mit Fortschritt; Bewegung zwischen zwei Tagen interpoliert | mittel | 1 | Klick bis sichtbare Baustelle ≤ 1 Sim-Tag |
| 4 | **Speicherstand der Tages-Sim** mit Befehlsprotokoll, nach dem Muster von `sim/src/save.rs` | gross | 1 | Laden und weiterlaufen ist bitgleich zu einem Lauf ohne Speichern |
| 5 | **Eine Sim, eine Uhr:** `ApoleiaSim` rechnet nicht mehr, die Bevölkerungskarte wird aus den Menschen gezählt | mittel | 2, 4 | ein Sim-Thread; Karte stimmt mit der Personenzahl |
| 6 | **Infos und Erklärungen:** Kasse, Einnahmen und Ausgaben, Vorräte, Preise; Fenster pro Hof und Markt mit „wer kauft, wer verkauft, warum“; Warnungen; Baukosten vor dem Bauen | mittel | Wirtschafts-Fixes | Zu jedem angezeigten Preis lässt sich die Ursache aufklappen |
| 7 | **Gebäude aus dem Spielzustand:** Märkte, Orte, später Werkstätten wachsen aus der Sim statt fester Kulisse | gross | Grafik-Look, 5 | Kein Gebäude ohne Gegenstück in der Sim |
| 8 | **Leistung:** Zielwerte pro Tempostufe, Mac-Messung mit Tracy/Perfetto, Spitzen an Monatsgrenzen glätten | laufend | – | Stufe 4 ohne verpasste Bilder auf dem Referenz-Mac |
| 9 | **Wirtschaftsprüfung als Test:** Geldmenge und Gütermengen jeden Tag bilanziert, Lauf bricht bei Lücke ab | klein | – | 100-Jahres-Lauf ohne ungebuchten Denar |

Nach Phase 3 ist es zum ersten Mal spielbar: bauen, zusehen, wie Tagelöhner den Hof bauen und
eine Familie einzieht, Tempo regeln. Phasen 4 und 5 machen es stabil, 6 und 7 machen es zum Spiel.
Phase 2 und 9 können sofort parallel laufen.

## Umsetzungsstand

| # | Stand | Was gebaut ist, Nachweis |
|---|---|---|
| 1 | `implementiert` (PR #47) | Befehle über die Queue, angewendet zwischen zwei Tagen, mit Sim-Tag protokolliert. Ausführung durch Tagelöhner (S113) baut der Baumenü-Thread. |
| 2 | `implementiert` | `app/scripts/sim/game_clock.gd`: Leiste oben Mitte mit Pause, Tempo 1–4 (2, 10, 30, 100 Tage/s), Datum, Menschen, Staatskasse; Leertaste, `[` `]`. Fällt die Sim unter 80 % des Tempos, sagt die Leiste, wie viele Tage/s sie schafft. In Godot 4.7.2 (headless) mit simulierten Tasten geprüft: Pause hält den Tag an, Tempo 4 setzt 100 Tage/s. |
| 3 | `teilweise` | Aufträge erscheinen im nächsten Bild (PR #47). Wird eine Baustelle fertig, baut der Sim-Thread die Feld- und Strassenschicht sofort neu statt zum Monatswechsel, der Hof mit seinen Feldern ist also am selben Tag zu sehen. Baufortschritt: `build_orders()` liefert je Auftrag geleistete und nötige Arbeitstage (wöchentlich), das Baumenü zeichnet den gebauten Anteil; ein Bautrupp hat höchstens vier Leute (S113), ein Hof steht nach rund sieben Wochen. Vorschau: `Grain::site_check` sagt vor dem Setzen, ob gebaut wird (kein Markt, Meer, Felder und Strassen noch offen, niemand zieht ein), wie viele Arbeitstage und was es zum heutigen Tageslohn kostet; die Brücke beantwortet `ask_build_check` zwischen zwei Tagen, auch in der Pause (rund 1 ms). Bewegung: Träger, Karren und Tagelöhner gehen ihre Wege in einem Tempo fürs Auge, unabhängig von den Tagen pro Sekunde (`people_trips.gd`); wer zu Hause bleibt, bewegt sich nicht. Offen: Vorschau im Baumenü zeichnen (Baumenü-Thread); Umzüge springen noch von Zelle zu Zelle. |
| 4 | `implementiert` (Wiederabspielen) | `sim/src/game.rs`: Spielstand = Seed, Hash der Eingaben, Tag, Befehlsprotokoll, Fingerabdrücke (wenige hundert Byte). Laden spielt die Tage mit den Befehlen erneut ab, wie Factorio-Replays. F8 speichert, F9 lädt (`user://quicksave.apgame`); ein falscher Spielstand wird geprüft und abgelehnt, bevor das laufende Spiel stoppt. Tests `game::tests` (ein Hof wird bestellt und gebaut, speichern, laden, 30 Tage weiter = gleicher Fingerabdruck, gleiche Kasse; kaputte und fremde Spielstände abgelehnt) und in Godot: Tag 365 gespeichert, geladen in 11,6 s, Fingerabdruck gleich. Die Bau-Ausführung (S113) läuft in `Game::day` und ist damit im Spielstand. **Grenze:** Laden dauert rund 3,7 s pro Spieljahr plus 3,5 s Start (4 Kerne). Ein Speicherstand des ganzen Zustands (Phase 4b) ist bewusst zurückgestellt: er müsste die ECS-Welt der Menschen, rund 60 Felder der Getreidewirtschaft und die Aufträge dreier Hintergrund-Threads bitgleich sichern, und jedes neue Feld der Wirtschaft müsste mit. Solange Spiele wenige Jahre dauern und die Wirtschaft sich jede Woche ändert, ist das Wiederabspielen robuster (Spielstände bleiben über Code-Änderungen ladbar, die Aufträge kommen mit). Er lohnt sich, sobald Spielstände über etwa drei Jahre üblich werden. |
| 5 | `erledigt` | Im Spiel läuft nur die Tages-Sim (siehe Ausgangslage). Eine Bevölkerungskarte aus den Menschen statt aus `ApoleiaSim` ist nicht gebaut. |
| 6 | `teilweise` | Staatskasse in der Leiste (bei leerer Kasse „Kasse leer“, der Staat prägt nach S95). Baukosten vor dem Bauen aus `site_check` (Arbeitstage × Tageslohn des Markts). Marktfenster (`app/scripts/sim/market_window.gd`): Klick auf einen Marktplatz öffnet rechts die Zeile dieses Markts aus der Markttabelle (`market_at`, `ask_market`), wöchentlich nachgeführt; jede Spalte, die die Wirtschaft dort ergänzt, erscheint mit, Textspalten als Satz darunter. Die Gründe für Preise („warum“) baut der Wirtschafts-Thread als `Grain::market_look` und Tabellenspalten; Warnungen folgen. |
| 7 | `teilweise` | Daten für den Grafik-Thread: Jedes Haus trägt das Handwerk seines Haushalts und wie ausgelastet die Werkstatt ist (`craft << 22 | key << 8 | busy` im Hausdatensatz, wöchentlich aus `Grain::crafts_in`), damit Esse, Töpferofen oder Webstuhl genau am Haus stehen. Baustellen pro Ausschnitt mit `ask_sites`/`take_sites` (Mitte der Kachel, Art, gebauter Anteil, Breite, Tiefe). Marktstände aus `ask_goods` (Wirtschafts-Thread). Der Grafik-Thread zeichnet Schmiede, Töpferei und Weberei am Dorfhaus, mehr Ware bei höherer Auslastung (PR #50). Baugerüste noch nicht: die Sim kennt nur die Kachel (1,5625 km), kein Los; offen, bis eine Baustelle einen Punkt hat. |
| 8 | `teilweise` | `sim/examples/game_bench.rs` misst einen Tag gegen das Budget jeder Tempostufe, die Teile von `people.day()` und der Getreidewirtschaft, die langsamsten Tage und die Ladezeit; `ApoleiaPeople.timings()` gibt im Spiel den Mittelwert pro Tag nach Teilen (Tag, Karte, Ansicht, Übergabe). Verbessert: Die Brautwahl rechnet jeder Bräutigam gegen den Stand am Morgen auf allen Kernen; nur wer seine Braut an einen früheren verliert, sucht nochmals (bitgleich, gleicher Fingerabdruck), Heirat 1,5 → 0,9 ms pro Tag. Die Karte wird auf einem eigenen Thread gezeichnet, die 1,7 Millionen Feldstücke sammelt `Grain::plot_lists` auf allen Kernen: Monatsspitze im Sim-Thread 70 → 12 ms. Läuft die Sim hinter den bestellten Tagen her, rechnet sie die Ansicht höchstens 30-mal pro Sekunde statt jeden Tag (der Bildschirm zeigt ohnehin einen Stand pro Bild). Cloud, 4 Kerne, 2 Jahre: Tag p50 7,6 ms, p95 11,9, p99 14,3; Menschen 3,8 ms, Getreide und Waren 4,4 ms (Arbeit 1,1, Essen 1,0, Neuaufbau 1,1). Durch die Brücke in Godot: 85–98 Tage/s statt 60–75. Tempo 1–3 halten, Tempo 4 (10 ms) knapp nicht. Mac-Messung offen. |
| 9 | `implementiert` (S94, Wirtschafts-Thread) | `Grain::money_unbooked()` muss jeden Tag 0 sein; der Test `deterministic_fingerprint` prüft es. |

## Wie die laufenden Arbeiten dazu passen

- **Baumenü** (Höfe, Felder, Strassen): ist Phase 1 und der Spieler-Teil von Phase 3. Die
  Ausführung (S113) kommt in `Game::day` direkt nach `grain.day`.
- **Wirtschafts-Fixes** (Geldkreislauf, Handwerker verkaufen Waren): Voraussetzung für Phase 6
  und den vollen Speicherstand (Phase 4) und Grundlage für Punkt 1 unter „besser als CS2“.
- **Grafik auf Urbek/Islanders-Niveau:** unabhängig bis Phase 7.

## Offene Punkte

- Abreissen: Wer bekommt das Land zurück, und was passiert mit den Bewohnern? Braucht einen
  eigenen Entscheid, bevor es ins Baumenü kommt.
- Referenz-Mac und Zielwerte für Phase 8 festlegen.

## Quellen

1. Paradox Interactive, Cities: Skylines II, „Citizen Simulation & Lifepath“:
   <https://www.paradoxinteractive.com/games/cities-skylines-ii/features/citizen-simulation-lifepath>
2. 80.lv, „Cities: Skylines 2 Doesn't Have Limit for People It Can Track“:
   <https://80.lv/articles/cities-skylines-2-doesn-t-have-limit-for-people-it-can-track>
3. PCGamesN, „The Cities Skylines 2 economy was not up to standard, developer admits“:
   <https://www.pcgamesn.com/cities-skylines-2/broken-economy>
4. AUTOMATON, 19.3.2026, Colossal-Order-CEO über Unity-Technik (nach PC Gamer):
   <https://automaton-media.com/articles/newsjp/20260319-430623/>
5. Victoria 3 Dev Diary #76, Performance:
   <https://www.paradoxinteractive.com/games/victoria-3/news/dev-diary-76-performance>
6. Factorio Friday Facts #76, „MP inside out“: <https://factorio.com/blog/post/fff-76>
7. Workers & Resources: Soviet Republic, Steam-Seite:
   <https://store.steampowered.com/app/784150/Workers__Resources_Soviet_Republic/>
8. Anno 117: Pax Romana, Wikipedia: <https://en.wikipedia.org/wiki/Anno_117>
9. Glenn Fiedler, „Fix Your Timestep!“: <https://gafferongames.com/post/fix_your_timestep/>
10. Sunshine-Hill, Badler, „Perceptually Realistic Behavior through Alibi Generation“, AIIDE 2010:
    <https://ojs.aaai.org/index.php/AIIDE/article/view/12389>
11. Richmond et al., „FLAME GPU 2: a framework for flexible and performant agent based simulation
    on GPUs“, Software: Practice and Experience 53(8), 2023: <https://eprints.whiterose.ac.uk/199416/>
12. Jiang, Sengupta, Demmel, Williams, „Large Scale Multi-GPU Based Parallel Traffic Simulation“
    (LPSim), arXiv 2406.08496: <https://arxiv.org/html/2406.08496v2>
13. Altera.AL, „Project Sid: Many-agent simulations toward AI civilization“, arXiv 2411.00114:
    <https://arxiv.org/abs/2411.00114>
14. Bougie, Watanabe, „CitySim: Modeling Urban Behaviors and City Dynamics with Large-Scale
    LLM-Driven Agent Simulation“, arXiv 2506.21805: <https://arxiv.org/abs/2506.21805>
15. GameFromScratch, „Godot 4.6 Released“ (26.1.2026): <https://gamefromscratch.com/godot-4-6-released/>
