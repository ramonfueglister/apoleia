# Kit 2 — Wanderung (Recherche und Vorschlag)

**Stand:** 27.10.2026 · **Status:** `erforscht`, Vorschlag zur Entscheidung.

## Wie die Vorbilder es lösen (belegt)

| Thema | EU5 | Victoria 3 |
|---|---|---|
| Ziel | Jeden Monat ziehen Pops zu einem Ort im Markt mit einer der höchsten Migrations-Attraktivitäten; **nähere Orte werden bei ähnlicher Attraktivität bevorzugt**. Mit „Closed Borders“ nur innerhalb des Landes. | Binnenwanderung nur innerhalb des Markts, zu den Staaten nahe der höchsten Attraktivität, verteilt nach Attraktivität und Aufnahmefähigkeit. |
| Was zählt | Nur Orte, die weit genug vom **Durchschnitt** des Markts abweichen, haben Wanderung. Über der Bevölkerungskapazität: kein Wachstum, Menschen ziehen weg. | Nur der **Unterschied** der Attraktivität zählt. Attraktivität aus Lebensstandard, Arbeit, Dichte im Verhältnis zum Ackerland. Wer viele Zuzüger bekommt, verliert Attraktivität. |
| Menge | Basis „1 pro 10 000 Menschen“ eines Pops pro Monat, mal Modifikatoren; mindestens 1 Person. | Pro Woche begrenzt durch Infrastruktur und Marktzugang. Obergrenzen pro Staat für Weg- und Zuzug. |
| Wer | Bauern dürfen jeden Monat, höhere Schichten seltener. | Ärmere ziehen eher; Wohlhabende kaum. |
| Fernwanderung | über den Markt, mit Distanz-Präferenz | eigene „Massenwanderung“ bei kultureller Unruhe, gewichteter Zufall |
| Leistung | – | Kosten hängen an der Zahl der Pops, nicht an der Bevölkerung. |

Quellen: [EU5 Wiki, Population](https://eu5.paradoxwikis.com/Population) (Stand vor Release),
[Victoria 3 Dev Diary #17 Migration](https://admin-forum.paradoxplaza.com/forum/developer-diary/victoria-3-dev-diary-17-migration.1492928),
[Victoria 3 Dev Diary #105 Migration in 1.6](https://admin-forum.paradoxplaza.com/forum/developer-diary/victoria-3-dev-diary-105-migration-in-1-6.1624226).
Eine genaue Attraktivitätsformel veröffentlicht keins der beiden Spiele.

## Was davon zu Apoleia passt

Wir haben heute nur Tiles mit Bevölkerung P und Tragfähigkeit K, keine Märkte, Kulturen,
Schichten oder Jobs. Übertragbar ist der Kern, den beide teilen:

1. **Attraktivität pro Tile** aus dem, was wir haben: freie Tragfähigkeit `A = (K − P) / K`
   (Victoria 3: Dichte im Verhältnis zum Ackerland; EU5: über der Kapazität zieht man weg).
2. **Nur der Unterschied zählt**, Wanderung nur bei genügend Abstand zum Umfeld.
3. **Nähe vor Ferne:** pro Monat nur zu Kanten-Nachbarn (Quadtree, auch über Ebenen);
   weitere Wege entstehen über Monate.
4. **Kleine Rate mit Obergrenzen:** Anteil pro Monat proportional zum Unterschied, gedeckelt
   für Weg- und Zuzug, damit sich nichts aufschaukelt.
5. **Deterministisch nach S42:** Ströme parallel aus dem alten Zustand berechnen, dann in einem
   sortierten seriellen Schritt anwenden; Summe exakt erhalten (Festkomma).

Bewusst **nicht** in v1: Städte als eigener Sog, Fernwanderung, Kultur, Schichten. Städte
brauchen zuerst städtische Sterblichkeit (sonst wachsen sie unbegrenzt) und kommen als eigener
Schritt.

## Prüfung

- Bevölkerung bleibt bei Wanderung exakt erhalten (Festkomma-Summe).
- Shuffle-Test und Fingerabdruck wie bisher.
- Kein Tile über K durch Zuzug; volle Tiles geben an freie Nachbarn ab.
- Tick-Zeit gemessen gegen heute (0,18 ms Container, 0,06 ms Mac).
- Kartenmodus zeigt die Ströme (später eigener Modus „Wanderung“).

## Umsetzung v1 und Ergebnis (27.10.2026)

Gebaut wie oben: Tick-Task `migrate` vor `growth`, Attraktivität `1 − P/K` (begrenzt auf
−1…1), Schwelle 0,05, Rate 0,02 pro Monat und Einheit Unterschied, Kantengewicht
geteilte Kante / eigener Umfang. Nachbarlisten liegen inline im Tile (max. 8) und werden nur
bei Teilung/Zusammenlegung neu gebaut. Der Zustand vom Monatsanfang wird in ein dichtes Feld
kopiert, dann rechnet jedes Tile parallel seinen Saldo; beide Seiten einer Kante rechnen
denselben Betrag, die Summe bleibt exakt erhalten (Test).

Lauf 500 Jahre HYDE 3.3 (Container, 4 vCPU):

| Jahr | Wanderer im Dezember |
|---|---|
| 181 | 2 372 |
| 190 | 1 073 |
| 280 | 7 |
| 680 | 0 |

Tick p50 0,8–0,9 ms statt 0,18 ms ohne Wanderung (rund 190 000 Kantenauswertungen pro Monat).

**Befund:** Nach S35 startet jedes Tile mit derselben Füllung (Landbevölkerung / 0,7), und K
ist statisch. Damit gibt es fast keinen Attraktivitätsunterschied; die Wanderung gleicht nur
die Startunterschiede um die Städte aus und kommt dann zum Stillstand. Sie wird erst wirksam,
wenn sich K oder P örtlich ändern: Ernten/Hunger, Verwüstung, oder Städte mit eigener
Sterblichkeit, die laufend Zuzug brauchen.
