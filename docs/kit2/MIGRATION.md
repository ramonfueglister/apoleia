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

## Mechanik 2: Städte mit Sterbeüberschuss (27.10.2026)

Vorbild: Wrigley 1967 (London braucht laufend Zuzug, Sterbeüberschuss rund 1 %/Jahr) und
de Vries 1984 (das Land schickt seinen Geburtenüberschuss in die Städte).

- **Sterbeüberschuss:** Der Stadtanteil `u` eines Tiles (aus `cities.csv`) verliert jeden Monat
  `urban_excess_death = 1 %/Jahr`. Ohne Zuzug schrumpft jede Stadt.
- **Sog:** Jede Stadt fragt `city_pull_rate · u · (K − P)` Menschen pro Monat nach (freie
  Plätze: Arbeit und Brot). Die Nachfrage wird auf das Land der 3×3 umliegenden
  200-km-Wurzelquadrate verteilt.
- **Nur der Überschuss geht:** Ein Land-Tile gibt höchstens seinen eigenen logistischen
  Monatszuwachs ab (die landlosen Kinder). Ein ausgedünntes Umland schickt also weniger,
  statt leerzulaufen. Ohne diese Grenze (erster Versuch, Obergrenze 0,2 %/Monat) fiel die
  Gesamtbevölkerung in 1600 Jahren von 66 auf 34 Mio., weil die Städte mehr verlangten, als
  das Land nachwachsen lassen kann.
- Verteilt wird in ID-Reihenfolge, die letzte Stadt bekommt den Rest; die Summe bleibt exakt.

Lauf 1600 Jahre HYDE 3.3 (Container):

| Jahr | Gesamt | Rom (K 921 K) | Umland Rom < 300 km, Füllung |
|---|---|---|---|
| 180 | 66,1 Mio. | 925 K | 0,77–0,88 |
| 580 | 70,2 Mio. | 790 K | 0,81–0,84 |
| 1780 | 71,4 Mio. | 781 K | 0,81–0,83 |

Ergebnis: stabiles Gleichgewicht. Rom hält sich bei rund 85 % seiner Kapazität, das Umland
bleibt voll, die Gesamtzahl nähert sich K von unten. Tick p50 1,8 ms im Container
(Mac-Messung folgt).

### Nachtrag: Sterbeüberschuss nach Stadtgrösse

Davenport (2020) zeigt, dass die Sterblichkeit mit der Stadtgrösse stieg. Im 18. Jahrhundert
lag die Säuglingssterblichkeit in London bei 300–400 auf 1000 Geburten, in Marktstädten mit
2000–3000 Einwohnern bei 209–270 und in abgelegenen Dörfern unter 100. Darum gilt jetzt die
einfachste Formel mit zwei Ankern:

    Sterbeüberschuss pro Jahr = 0,5 % · log10(Stadtgrösse / 5000), unter 5000 null

| Stadt | Sterbeüberschuss pro Jahr |
|---|---|
| 5 000 | 0 |
| 50 000 | 0,5 % |
| 500 000 (London, Wrigley 1967) | 1,0 % |
| 1 000 000 (Rom) | 1,15 % |

log10 ist ohne libm gerechnet (nur + − × ÷, Test gegen libm < 1e-6), damit es auf jeder
Plattform dieselben Bits ergibt.

Lauf 1600 Jahre: Gesamt 66,1 → 81,7 Mio. (stabil ab ~1000), Rom 925 K → 869 K (580) → 830 K
(1780), Alexandria 412 K → 375 K. Kleinstädte verlieren nichts mehr, daher wächst das Land
näher an K. Tick p50 2,0 ms im Container.

### Nachtrag: Tempo, Wanderung einmal im Jahr

Nach den Städten kostete ein Monat auf dem Mac 0,57 ms statt 0,06 ms (Container: Wanderung
~0,7 ms, Stadtzug ~1,1 ms, Wachstum ~0,3 ms). Zwei Schritte:

1. **Stadtzug ohne Zufallszugriffe:** ein Durchlauf über die Spalten; dann nur noch die
   gebenden Tiles und die Städte, zurückgeschrieben in Tabellenreihenfolge statt per
   `Query::get` und HashMap. Bitgleiches Ergebnis (gleicher Fingerprint), 1,15 → 0,48 ms.
2. **Wanderung und Stadtzug laufen einmal im Jahr (Januar)** mit Jahresraten
   (`migration_rate` 0,24, `city_pull_rate` 0,6, `city_draw_cap` 0,024, Überschuss = logistischer
   Jahreszuwachs). Die Ströme sind langsam, HYDE und die Quellen sind jährlich. Die übrigen elf
   Monate rechnen nur Wachstum und Sterben.

Ergebnis 1600 Jahre: Gesamt 81,72 Mio. (monatlich 81,69), Rom 823 K (monatlich 830 K).
Container: Tick p50 2,0 ms → 0,21 ms, Mittel pro Monat ~1,5 ms → ~0,3 ms. Die Spalte
`migrants_year` in `series.csv` ist jetzt der Jahresstrom.
