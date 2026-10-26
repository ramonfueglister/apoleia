# Kit 2 — Architektur des Spielzustands (Vorschlag)

**Stand:** 26.10.2026 · **Status:** `erforscht`, Vorschlag zur Entscheidung.

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

Stand der Technik ausserhalb Paradox: Entity-Component-System mit Archetyp-Speicher
(Bevy ECS, flecs). Für Godot gibt es die GDExtension-Brücken `godot-bevy` und
`bevy_godot4`, die Bevy-Systeme neben dem Godot-Szenenbaum laufen lassen
(<https://gamefromscratch.com/bevy-ecs-in-godot-engine/>).

## Vorschlag für Apoleia

| ID | Entscheidung |
|---|---|
| S40 | **Ein Rust-Kern hält den einzigen gültigen Spielzustand** (headless, deterministisch). Godot zeichnet nur und schickt Befehle (passt zu `docs/product-renderer/TECHNICAL_DECISION.md`: „Späterer Rust-Kern bleibt ausserhalb dieses Grafikprojekts“). |
| S41 | **Zustand als ECS** (`bevy_ecs` als eigenständige Bibliothek, ohne Bevy-Renderer). Tiles, Städte, später Staaten und Gruppen sind Entities; Bevölkerung, Kapazität, Fläche sind Komponenten. Teilen/Zusammenlegen = Entities anlegen/löschen. Alternative: eigene Tabellen pro Typ (wie Paradox-„Datenbanken“). |
| S42 | **Tick-Tasks nach Victoria 3:** jede Simulation ist ein System mit Frequenz und Abhängigkeiten; Monatstakt nach S21. Parallel nur in Vorschritten; Änderungen an der Struktur seriell und nach stabiler Tile-ID sortiert (Determinismus, Fingerabdruck wie jetzt). |
| S43 | **Lesen nur zwischen Ticks:** nach jedem Tick entsteht ein unveränderlicher Snapshot (Doppelpuffer), den Godot über GDExtension liest. Kartenmodi, Tooltip und Panel lesen nur diesen Snapshot. |
| S44 | **Abgeleitete Werte mit Dirty-Flags** (Kapazität, später Modifikatoren): nur geänderte Tiles neu rechnen. |
| S45 | **Keine SQL-Datenbank zur Laufzeit.** Speicherstand = versionierte Binärserialisierung des ECS-Zustands; Export als CSV/Parquet nur für Auswertung. |
| S46 | **Objektbudget statt Bevölkerungsbudget:** Kosten hängen an der Zahl der Entities (Vic3); das Tile-Budget S12 (65 536) bleibt die Obergrenze. |

## Erster Schritt nach der Entscheidung

1. `sim/` auf `bevy_ecs` umstellen: Komponenten `TileKey`, `Population`, `Capacity`,
   `Land`; Systeme `capacity`, `growth`, `split`, `merge` als Monats-Tick-Tasks.
   Gleicher Fingerabdruck wie heute als Prüfung.
2. Snapshot-Export pro Tick (Binärformat) und eine Godot-Kartenmodus-Szene
   „Bevölkerung“, die diesen Snapshot liest.
3. Messung Tick-Zeit auf dem Mac (B08).
