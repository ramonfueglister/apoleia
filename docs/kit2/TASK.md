# Kit 2 — Auftrag Subsystem 1: Bevölkerung

**Status:** Prototyp `implementiert` mit Schätzwerten ([ESTIMATES.md](ESTIMATES.md)); Schritt 1 (belegter Datensatz) `offen`.

## Ziel

Ein headless Prototyp (Rust, ohne Grafik), der die Bevölkerung aller Tiles ab
180 n. Chr. nach S30–S34 simuliert, einschliesslich Teilen und Zusammenlegen
nach S12–S15. Er zeigt, ob die Grundformel glaubwürdige Dichten erzeugt, stabil
bleibt und schnell genug ist.

## Umfang

| Enthalten | Nicht enthalten |
|---|---|
| Startraster und IDs aus `data/gametiles/` laden | Hunger, Seuchen, Migration, Gruppen |
| K pro Tile aus Ackeranteil × Boden × Klima | Importe, Handel, Preise |
| Startbevölkerung 180 n. Chr. aus belegtem Datensatz | Gezeichnete Geometrie (Platzhalter: Ackeranteil aus Daten) |
| Monatliches logistisches Wachstum | Staaten, Krieg, KI |
| Teilen/Zusammenlegen mit Erhaltung der Summen | Grafik, Godot-Anbindung |
| Ausgabe: Kurven (Gesamt, Regionen), Dichtekarte, Zeitmessung | |

## Ablauf

1. Datensatz für Startbevölkerung und Ackerland wählen, Lizenz und Version dokumentieren.
2. Datenmodell: Arrays pro Tile, Gruppenliste mit einer Gruppe, aktive Liste.
3. Monatstakt nach S21 (ohne Schritt 4, solange es keine Märkte gibt).
4. Läufe über 500 Jahre mit festem Seed; Ergebnisse und Messungen in STATUS.md.
