# Kit 2 — Prüf-Orakel, Spielstand, Skalierung

Stand 27.10.2026. Behebt die zwei technischen Lücken aus der Bewertung vom 27.10.:
(1) kein unabhängiges Prüf-Orakel mehr, (2) kein Spielstand. Dazu der Nachweis, dass der
Kern in EU5/Victoria-3-Grösse trägt.

## 1. Prüf-Orakel

**Problem:** Der Referenzkern (`crate::World`) rechnete Wanderung, Stadtzug und
Sterbeüberschuss nicht mit. Ab fb6af30 prüften sich die neuen Mechaniken nur noch an
eigenen Tests. Das ist das Orakel-Problem (Barr et al., 2015).

**Lösung, drei Schichten:**

1. **Differenzielles Testen** (McKeeman, 1998). Der Referenzkern rechnet jetzt alle
   Mechaniken: Wanderung, Stadtzug, Sterbeüberschuss, Jahrestakt. Er ist bewusst anders
   gebaut als der ECS-Kern: f64 statt Festkomma, BTreeMap statt Spalten, sequenziell statt
   parallel, `log10` aus der Standardbibliothek statt eigener Reihe, Nachbarn geometrisch statt
   aus Listen. Verglichen wird Monat für Monat, Tile für Tile.
   - `matches_the_reference_month_by_month`: jede Mechanik einzeln und alle zusammen,
     50 Jahre. Gleiche Tiles, Abweichung < 1e-5 (relativ, Boden 1000 Menschen).
   - `apoleia-sim --compare --years N`: dasselbe auf der ganzen Karte (HYDE 3.3). In
     100 Jahren identische Tile-Struktur; grösste Abweichung 2e-3 an einzelnen Tiles, wo eine
     Wanderungsschwelle (0,05) um ~1e-6 knapp über- oder unterschritten wird.
   - **Erster Fund:** Der Stadtanteil `u` lag in Q16. In einer Stadt-Tile ist der Landanteil
     1 − u winzig (Rom: 4e-5), und Q16 traf ihn um 13 % falsch. Jetzt Q32.
2. **Eigenschaftsbasiertes Testen** (Claessen & Hughes, 2000; Goldstein et al., 2024) mit
   `proptest`, fester Seed, je 32 zufällige Fälle (Raten, Schwellen, Städte):
   - Wanderung und Stadtzug erhalten die Menschenzahl exakt (Σ Saldo = 0).
   - Keine negativen Werte, 2:1-Regel und Budget halten, Snapshot gleich Index.
   - Differenzieller Vergleich wie oben, bei zufälligen Raten 20 Jahre.
3. **Charakterisierungstest** (Feathers, 2004): `pinned_fingerprint` hält den Fingerprint der
   Testwelt nach 20 Jahren fest (`41e5847821cf0fe2`). Jede Änderung am Ergebnis muss diese
   Zahl bewusst ändern. Weil die Rechnung plattformunabhängig ist (Monniaux, 2008: nur
   korrekt gerundete IEEE-Operationen, kein FMA, kein libm), muss derselbe Wert auf Linux x86
   und macOS ARM herauskommen. Der Test prüft das bei jedem Lauf auf jeder Maschine.

Weitere metamorphe Relationen (Chen et al., 2018) prüfen schon bestehende Tests: zufällige
Systemreihenfolge, Replay aus dem Befehlslog, Speichern und Laden (unten).

## 2. Spielstand

**Regel:** Speichern, beenden und laden darf nichts Beobachtbares ändern (Wube Software,
2018). Erst das macht Replays, das Beitreten zu laufenden Mehrspieler-Partien und
Desync-Suche möglich (Bettner & Terrano, 2001; Chen et al., 2015).

**Format** (`sim/src/save.rs`, Version 1):

```text
"APOLSAVE" | Version u32 | Eingaben-Hash u64 | Rohlänge u64 | gepackte Länge u64 | xxh3-64
zstd( Abschnitte: Kennung[4] | Länge u64 | Inhalt )
  META  Monat, Teilungen, Zusammenlegungen, Befehlszähler, Wurzelraster
  TILE  alle Komponenten, spaltenweise, in Tabellenreihenfolge
  TREE  innere Knoten, geteilte Knoten, offene Zusammenlegungen (sortiert)
  CMDS  Befehlslog und offene Befehle
```

- **Nur der Zustand,** keine Eingaben. Parameter und Eingabedaten stehen als Hash im Kopf;
  ein Stand lädt nur in dieselben (Fehler `Inputs` statt stiller Abweichung).
- **Tabellenreihenfolge** wird mitgespeichert und beim Laden wiederhergestellt. Die
  Gleitkomma-Summen des Stadtzugs laufen in dieser Reihenfolge; nur so rechnet der geladene
  Stand bitgleich weiter.
- **Abgeleitete Daten** (Nachbarlisten) werden neu gebaut, nicht gespeichert.
- **Spalten statt Zeilen,** dann zstd Stufe 3 (Collet & Kucherawy, 2021); grosse Stände
  komprimieren auf mehreren Kernen. Abschnitte tragen ihre Länge, unbekannte werden
  übersprungen (vorwärtskompatibel); die Version steigt nur, wenn sich ein bestehender
  Abschnitt ändert.
- **Prüfsumme** xxh3-64 über Kopf und Inhalt: jeder gekippte Bit wird erkannt (Test).
- **Absturzsicher:** temporäre Datei, `fsync`, `rename`, Verzeichnis `fsync` (Pillai et al.,
  2014). Ein Absturz hinterlässt den alten oder den neuen Stand, nie einen halben.
- **Im Spiel:** F5 speichert, F9 lädt (`user://quicksave.apsave`).

**Tests:** geladener Stand gleich ungespeichertem, Monat für Monat, für Speichermonate im
Wanderungsmonat, direkt danach und mitten im Jahr; dazu eigenschaftsbasiert für beliebige
Monate und Raten; Wiederspeichern ergibt dieselben Bytes; beschädigte, fremde, neuere und
abgeschnittene Dateien werden abgelehnt; Schreiben auf die Platte ohne Reste.

## 3. Skalierung

Zum Vergleich: EU5 hat rund 30 000 Locations, jede mit mehreren Pops (Paradox Interactive,
o. J.). `apoleia-sim --synthetic N` baut eine Karte aus N Zellen à 25 km mit Städten und misst
Tick, Snapshot, Speichern und Laden. Das Budget wächst mit (4 × N).

Für diese Grösse geändert:

- **Index in Hashtabellen** (FxHash) statt B-Bäumen: O(1) statt ~20 Vergleiche pro Suche bei
  einer Million Tiles. Keine Entscheidung iteriert über sie; wo Reihenfolge zählt
  (Fingerprint, Spielstand), wird sortiert. Ergebnis bitgleich (Fingerprint unverändert).
- **Nachbarsuche ohne Heap:** feste Liste mit 8 Plätzen; ein geteilter Nachbar beendet die
  Suche sofort, statt alle groberen Ebenen abzufragen.
- **Startwelt und geladene Stände in einem Rutsch erzeugt** (`spawn_batch`).
- **Eingaben-Hash binär** statt über Text und nur einmal pro Laden: Laden bei 1,5 Mio. Tiles
  6,5 s → 4,1 s im Container.

Messung auf dem Mac (Apple M3 Pro, 27.10.2026, 36 Monate ab Start):

| Zellen | Tiles | Monat p50 | Monat p95 | Monat Mittel | Snapshot | Speichern | Grösse | Laden | gleich nach Laden | RAM |
|---|---|---|---|---|---|---|---|---|---|---|
| 30 000 | 44 505 | 0,10 ms | 2,4 ms | 0,52 ms | 0,06 ms | 7 ms | 0,6 MB | 12 ms | ja | 65 MB |
| 100 000 | 147 295 | 0,19 ms | 9,7 ms | 1,9 ms | 0,3 ms | 23 ms | 1,9 MB | 48 ms | ja | 206 MB |
| 300 000 | 443 466 | 0,45 ms | 38 ms | 6,8 ms | 0,9 ms | 40 ms | 5,6 MB | 208 ms | ja | 584 MB |
| 1 000 000 | 1 500 532 | 2,0 ms | 130 ms | 26 ms | 2,3 ms | 103 ms | 19 MB | 721 ms | ja | 2,1 GB |

Plattformgleichheit: 500 Jahre auf der echten Karte ergeben auf Linux x86 und macOS ARM
denselben Fingerprint `65b033b310548070`; `pinned_fingerprint` ist auf beiden grün.
`--compare` auf dem Mac: 100 Jahre gleiche Tiles, grösste Abweichung 2,0e-3 (wie Linux).
Im Spiel (echte Karte, Jahr 300): F5 19 ms, Datei 0,33 MB; F9 87 ms, danach läuft das
Spiel nahtlos weiter.

### Nachtrag: Jahresschritt und Teilen parallel (92dc699)

- Wanderungsfeld parallel gefüllt (jede Tile schreibt nur ihren eigenen Platz).
- Stadtzug in zwei parallelen Durchläufen; die Summen pro Region sind Festkomma-Ganzzahlen,
  daher ist das Ergebnis unabhängig davon, wie die Tiles auf Threads verteilt werden.
- Nachbarlisten nach Teilungen parallel gebaut.
- Plattformgleich: 500 Jahre echte Karte ergeben auf Linux und Mac `7766c98c5a6211a0`.

Mac, 1,5 Mio. Tiles, 72 Monate (`--per-month`):

| Abschnitt | Zeit pro Monat |
|---|---|
| Normaler Monat (Median) | 1,5 ms |
| Januar (Wanderung, Stadtzug) | 13 ms (vorher ~25 ms) |
| Ein Jahr gesamt | ~29 ms → Tempo 5 (100 Monate/s) braucht ~24 % eines Kerns |
| Anlauf: Teilungsschub Monate 0–5 | 75–176 ms (einmalig, ~0,6 s für die ersten 16 Monate) |

Mittel über die ersten 36 Monate: 100 000 Zellen 1,5 ms (vorher 1,9), 300 000 Zellen 4,9 ms
(6,8), 1 000 000 Zellen 19,8 ms (25,5).

**Grenzen, ehrlich:**

- Teuer sind die Januare (Wanderung und Stadtzug) und die ersten Monate nach dem Start, in
  denen sich die Karte massenhaft teilt (p95). Bei EU5-Grösse (30 000–150 000 Tiles) bleibt
  das im Mittel bei 0,5–1,9 ms pro Monat auf dem eigenen Sim-Thread, ohne Wirkung auf die
  Bildrate.
- Bei 1,5 Mio. Tiles (50-fache EU5-Grösse) kostet ein Monat im Mittel 26 ms; Tempo 5
  (100 Monate/s) schafft dann nur ~40 Monate/s. Ursache: Teile des Jahresschritts
  (Wanderungsfeld füllen, Stadtzug) und der Teilungsschritt laufen auf einem Kern. Das ist
  der nächste Hebel, falls die Karte so gross wird.
- Ein Szenario kann als bereits verfeinerter Spielstand ausgeliefert werden; dann fällt der
  Teilungsschub nach dem Start weg.

## Quellen (APA 7)

Barr, E. T., Harman, M., McMinn, P., Shahbaz, M., & Yoo, S. (2015). The oracle problem in
software testing: A survey. *IEEE Transactions on Software Engineering, 41*(5), 507–525.
https://doi.org/10.1109/TSE.2014.2372785

Bettner, P., & Terrano, M. (2001). *1500 archers on a 28.8: Network programming in Age of
Empires and beyond* [Conference presentation]. Game Developers Conference, San Jose, CA,
United States.

Chen, T. Y., Kuo, F.-C., Liu, H., Poon, P.-L., Towey, D., Tse, T. H., & Zhou, Z. Q. (2018).
Metamorphic testing: A review of challenges and opportunities. *ACM Computing Surveys, 51*(1),
Article 4. https://doi.org/10.1145/3143561

Chen, Y., Zhang, S., Guo, Q., Li, L., Wu, R., & Chen, T. (2015). Deterministic replay: A survey.
*ACM Computing Surveys, 48*(2), Article 17. https://doi.org/10.1145/2790077

Claessen, K., & Hughes, J. (2000). QuickCheck: A lightweight tool for random testing of Haskell
programs. In *Proceedings of the Fifth ACM SIGPLAN International Conference on Functional
Programming* (pp. 268–279). ACM. https://doi.org/10.1145/351240.351266

Collet, Y., & Kucherawy, M. (2021). *Zstandard compression and the 'application/zstd' media
type* (RFC 8878). Internet Engineering Task Force. https://doi.org/10.17487/RFC8878

Feathers, M. C. (2004). *Working effectively with legacy code*. Prentice Hall.

Goldstein, H., Cutler, J. W., Dickstein, D., Pierce, B. C., & Head, A. (2024). Property-based
testing in practice. In *Proceedings of the IEEE/ACM 46th International Conference on Software
Engineering*. ACM. https://doi.org/10.1145/3597503.3639581

McKeeman, W. M. (1998). Differential testing for software. *Digital Technical Journal, 10*(1),
100–107.

Monniaux, D. (2008). The pitfalls of verifying floating-point computations. *ACM Transactions
on Programming Languages and Systems, 30*(3), Article 12. https://doi.org/10.1145/1353445.1353446

Paradox Interactive. (o. J.). *Developer diary 1: Population and living world* [Forumsbeitrag].
Paradox Interactive Forums. Abgerufen am 27.10.2026 von
https://forum.paradoxplaza.com/forum/developer-diary/developer-diary-1-population-and-living-world.1857075

Pillai, T. S., Chidambaram, V., Alagappan, R., Al-Kiswany, S., Arpaci-Dusseau, A. C., &
Arpaci-Dusseau, R. H. (2014). All file systems are not created equal: On the complexity of
crafting crash-consistent applications. In *11th USENIX Symposium on Operating Systems Design
and Implementation (OSDI 14)* (pp. 433–448). USENIX Association.

Wube Software. (2018, 23. November). *Friday Facts #270 – HR substation & save/load overview*.
https://factorio.com/blog/post/fff-270
