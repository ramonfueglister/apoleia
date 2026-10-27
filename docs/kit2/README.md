# Kit 2 — Simulation

**Stand:** 26.10.2026 · **Status:** Grundsätze und Subsystem 1 `spezifiziert`; Umsetzung `offen`.

Kit 2 beschreibt die Simulation des Spiels: eine einzige Welt, aus der Geschichte
emergent entsteht. Vorbild ist eine Mischung aus EU5 (Reiche, Märkte, Bevölkerung
über Jahrhunderte) und SimCity 4 (Werkzeuge, mit denen direkt auf die Karte
gezeichnet wird). Die Simulation läuft headless hinter der Grenze, die Kit 1
vorsieht. Sie braucht keinen Renderer und lässt sich ohne Grafik testen.

**Arbeitsweise:** ein Subsystem nach dem anderen. Pro Thema zuerst prüfen, wie
andere Spiele es lösen (mit Quellen), dann eigenes Design festlegen, dann einen
headless Prototyp bauen und messen. Keine Subsysteme vorwegnehmen.

| Datei | Zweck |
|---|---|
| [decisions.md](decisions.md) | Bestätigte Entscheidungen (S-IDs), offene Punkte |
| [SCALE.md](SCALE.md) | Massstab der Modellwelt: 100'000 Einzelpersonen, alles 1:24 |
| [GROUPS.md](GROUPS.md) | Pops, 13 Berufe und 8 politische Gruppen (S61, S77), gebaut im Prototyp |
| [GRAIN.md](GRAIN.md) | Vorschlag: Getreidewirtschaft, Handel und Wege flüssig bauen (S69–S76), mit Leistungsbudget |
| [TASK.md](TASK.md) | Aktueller Bauauftrag: Subsystem 1 Bevölkerung |
| [ACCEPTANCE.md](ACCEPTANCE.md) | Abnahme für Subsystem 1 |
| [REFERENCES.md](REFERENCES.md) | Wie andere Spiele es lösen, mit Quellen |
| [STATUS.md](STATUS.md) | Tatsächlicher Stand |

Bezug zu Kit 1: Raster und Tile-IDs stammen aus dem Spiel-Tile-Raster
(`data/gametiles/`, `docs/kit1/GAMETILES.md`). Kit 2 ändert Kit 1 nicht.
