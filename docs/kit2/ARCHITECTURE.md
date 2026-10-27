# Kit 2 — Architektur des Spielzustands (Vorschlag)

**Stand:** 26.10.2026 (Recherche Oktober 2026) · **Status:** `erforscht`, Vorschlag zur Entscheidung.

## Was die Vorbilder machen (belegt)

Quelle: Victoria 3, Dev Diary #76 „Performance“ (Paradox, Clausewitz/Jomini, dieselbe
Engine-Familie wie EU5): <https://www.paradoxinteractive.com/games/victoria-3/news/dev-diary-76-performance>

| Thema | Victoria 3 |
|---|---|
| Takt | Tick = 6 Stunden. Arbeit ist in **Tick-Tasks** zerlegt, jede mit Frequenz (täglich, wöchentlich, monatlich, jährlich) und Abhängigkeiten. Ein Wochen-Tick enthält auch die Tages-Tasks. |
| Threads | **Session-Thread** rechnet die Simulation und Spielerbefehle. **Task-Threads** (so viele wie Kerne) rechnen parallele Teile. Main- und Render-Thread zeichnen. |
| Lesen durch UI/Grafik | Der Zustand wird nur **zwischen Tick-Tasks** für Interface und Grafik freigegeben, damit die Daten konsistent sind. |
| Parallel und deterministisch | Teure Tasks laufen in einem parallelen Vorschritt und einem seriellen Schritt (Objekte anlegen/löschen). Ein **Sortierschritt** dazwischen verhindert Abweichungen zwischen Mehrspieler-Clients. |
| Lastverteilung | Tasks melden geschätzte Kosten; Ausreisser (grosse Länder) werden getrennt verteilt. |
| Abhängige Werte | Modifikatoren als **Abhängigkeitsgraph mit Dirty-Flags**; nur Betroffenes wird neu gerechnet, in parallelen Stapeln. |
| Speicher | Pool-Allokatoren und Objekt-„Datenbanken“ in der Engine; Umstieg auf mimalloc brachte rund 4 %. |
| Kosten | Hängen an der **Zahl der Objekte**, nicht an der Bevölkerung; deshalb werden kleine Pops zusammengelegt. |

EU5 selbst hat keine öffentliche Beschreibung seiner Zustandsspeicherung gefunden; die
Aussagen oben gelten für Victoria 3 und werden für EU5 nur vermutet.

## Stand der Technik, Oktober 2026 (belegt)

| Baustein | Stand | Was für uns zählt | Quelle |
|---|---|---|---|
| **Bevy ECS 0.20** | erschienen 8.10.2026 | Schwache Ordnung (`before_weak`/`after_weak`): nur Systeme mit Datenkonflikt werden geordnet, der Rest läuft parallel. Change-Ticks pro Spalte (`summary_tick`) überspringen unveränderte Spalten. `shuffle_seed` mischt die Systemreihenfolge, so lässt sich testen, ob das Ergebnis von der Reihenfolge abhängt. `despawn_all` für Massen-Löschen (1,3–1,7× schneller). | <https://bevy.org/news/bevy-0-20/> |
| Bevy ECS 0.19 | 19.6.2026 | `contiguous_iter(_mut)` liefert rohe Tabellen-Slices für dichte Schleifen (SIMD). Ressourcen sind Komponenten auf Singleton-Entities. Entity-IDs lassen sich von jedem Thread reservieren. | <https://bevy.org/news/bevy-0-19/> |
| flecs 4.1.6 | 29.6.2026, C/C++ | Starke Relationen und Abfragen, aber die Rust-Bindung wurde aus dem README entfernt (4.1.0). Damit ist flecs für einen Rust-Kern zweite Wahl. | <https://github.com/SanderMertens/flecs/releases> |
| **gdext 0.5.5** (godot-rust) | August 2026 | Unterstützt Godot 4.7 über `api-4-7`, passt also zu unserem Godot 4.7.2. Das ist die Brücke zwischen Rust-Kern und Godot. | <https://github.com/godot-rust/gdext/releases> |
| godot-bevy / bevy_godot4 | GDExtension-Projekte | Lassen Bevy-Systeme neben dem Godot-Szenenbaum laufen. Reife ist ungeprüft. | <https://gamefromscratch.com/bevy-ecs-in-godot-engine/> |
| Archon Engine (Unity, Grand Strategy) | Stresstest 4.2.2026 | Festkomma statt Float in der Simulation. Jede Zustandsänderung läuft als Befehl (Command Pattern), dazu Lockstep-Mehrspieler und Desync-Erkennung. Provinzen sind Texturpixel, die Karte ist **ein Draw Call**, Grenzen und Effekte rechnen GPU-Compute-Shader. Monats-Tick 1,8–2,8 ms bei 50 000 Provinzen. | <https://github.com/ForgottenHistory/Archon-Engine> |
| Lockstep-Determinismus | allgemein | Floats sind zwischen Plattformen nicht garantiert gleich, deshalb Festkomma oder Ganzzahlen für den gespeicherten Zustand. | <https://www.gamedeveloper.com/programming/cross-platform-rts-synchronization-and-floating-point-indeterminism> |

## Vorschlag für Apoleia

| ID | Entscheidung |
|---|---|
| S40 | **Ein Rust-Kern hält den einzigen gültigen Spielzustand.** Er läuft headless und deterministisch. Godot zeichnet nur und schickt Befehle; das passt zu `docs/product-renderer/TECHNICAL_DECISION.md` („Späterer Rust-Kern bleibt ausserhalb dieses Grafikprojekts“). |
| S41 | **Zustand als ECS mit `bevy_ecs` 0.20**, als eigenständige Bibliothek ohne Bevy-Renderer. Tiles, Städte und später Staaten und Gruppen sind Entities. Bevölkerung, Kapazität und Fläche sind Komponenten. Teilen und Zusammenlegen heisst Entities anlegen und löschen. Dichte Schleifen laufen über `contiguous_iter`. |
| S42 | **Tick-Tasks wie bei Victoria 3:** Jede Simulation ist ein System mit Frequenz und Abhängigkeiten, mit dem Monatstakt nach S21. Die Ordnung ergibt sich aus Datenkonflikten (`before_weak`/`after_weak`). Strukturänderungen laufen seriell und nach stabiler Tile-ID sortiert. Ein Test mit `shuffle_seed` muss denselben Fingerabdruck liefern. |
| S43 | **Alle Eingriffe als Befehle** (Spieler, KI, Werkzeuge auf der Karte). Sie werden pro Tick gesammelt, sortiert und angewendet. Das ist die Grundlage für Speicherstände, Wiederholung und Lockstep-Mehrspieler. |
| S44 | **Gespeicherter Zustand in Ganzzahl oder Festkomma**, z. B. Bevölkerung als ganze Zahl plus Bruchteil in Festkomma. Floats sind nur in Zwischenrechnungen innerhalb eines Ticks erlaubt, damit das Ergebnis auf Mac, Windows und Linux gleich bleibt. |
| S45 | **Lesen nur zwischen Ticks:** Nach jedem Tick entsteht ein unveränderlicher Snapshot (Doppelpuffer), den Godot über gdext (`api-4-7`) liest. |
| S46 | **Kartenmodi auf der GPU:** eine Tile-ID-Textur in Seiten (nach Teilen oder Zusammenlegen werden nur die betroffenen Seiten neu hochgeladen; jedes Tile behält seinen Slot) und pro Tick eine Wert-Textur pro Modus, eingefärbt im Shader als ein Draw Call. Grenzen und Streifen (über Kapazität) zeichnet ebenfalls der Shader. Tooltip und Panel lesen den Snapshot. |
| S47 | **Abgeleitete Werte über Change Detection** (`Changed<T>`, `summary_tick`): Nur geänderte Tiles werden neu gerechnet, wie die Dirty-Flags in Victoria 3. |
| S48 | **Keine SQL-Datenbank zur Laufzeit.** Der Spielstand ist eine versionierte Binärserialisierung des ECS plus Befehlsprotokoll. CSV- oder Parquet-Export gibt es nur zur Auswertung. Das Tile-Budget S12 (65 536) begrenzt die Zahl der Objekte; nach Victoria 3 hängen die Kosten an der Objektzahl. |

## Messung Schritt 1 (26.10.2026, Cloud-Container, 4 Kerne)

500 Jahre auf HYDE 3.3, 41 827 Tiles am Ende, 9276 Teilungen, beide Kerne mit
gleicher Tile-Zahl und Bevölkerung bis auf 19 Menschen (Rundung Festkomma).

| Kern | Tick p50 | Tick p95 |
|---|---|---|
| Referenz ohne ECS (`--reference`) | 0,34 ms | 0,46–0,58 ms |
| bevy_ecs, erster Port (i128-Division, `par_iter_mut`, zwei Durchläufe) | 0,60 ms | 0,80 ms |
| bevy_ecs, jetzt (Spalten-Slices parallel, ein Durchlauf, Sortierschritt) | 0,18–0,19 ms | 0,29–0,30 ms |

Was den Unterschied machte (callgrind): die 128-Bit-Division pro Tile, die
Software-Rundung `f64::round` (ohne SSE4.1), der Overhead pro Entity bei
`par_iter_mut` gegenüber `contiguous_par_iter_mut` und rund 60 µs Wake-up des
Multi-Thread-Executors bei einer reinen Kette. Die Messung auf dem Mac (B08) steht aus.

Schritt 2: Alle Eingriffe laufen als Befehl über `Sim::submit` und `Sim::step`
(sortiert nach Absender und Reihenfolge, mit Protokoll für Wiederholung). Der
Snapshot ist doppelt gepuffert (`Arc`), wird nur nach einem neuen Monat und nur auf
Anfrage gebaut und kostet 0,13–0,15 ms für 41 827 Tiles (Tabellenreihenfolge, nicht ID-Reihenfolge).

## Messung auf dem Mac (B08, 26.10.2026, Apple M3 Pro)

Gleicher Lauf, 500 Jahre HYDE 3.3, je zwei Läufe, gleiche Fingerabdrücke wie im Container.

| Kern | Tick p50 | Tick p95 | Snapshot p50 |
|---|---|---|---|
| Referenz ohne ECS | 0,106–0,108 ms | 0,13–0,14 ms | – |
| bevy_ecs | 0,059–0,062 ms | 0,085–0,090 ms | 0,046 ms |

In Godot 4.7.2 (Metal): Laden 71–156 ms, ein Monat im laufenden Spiel inklusive
Befehl und Snapshot 0,29–0,30 ms.

## Erster Schritt nach der Entscheidung

1. `sim/` auf `bevy_ecs` 0.20 umstellen. Komponenten: `TileKey`, `Population`
   (Festkomma), `Capacity`, `Land`. Systeme `capacity`, `growth`, `split` und `merge`
   werden Monats-Tick-Tasks. Prüfung: deterministischer Fingerabdruck, auch mit
   `shuffle_seed`.
2. Befehlsschnittstelle (vorerst nur „Tick ausführen“) und Snapshot pro Tick.
3. gdext-Brücke und Godot-Kartenmodus „Bevölkerung“ als Shader auf Tile-ID- und
   Wert-Textur, mit Tooltip und Panel aus dem Snapshot.
4. Messung der Tick-Zeit auf dem Mac (B08).
