# Befund: Geldkreislauf schliessen (Sonde S132)

Stand 31.10.2026. Sonde zu S94, nach Ramons «weiter» vom 10:48.

## Was die Sonde prüft

Heute entsteht Geld aus dem Nichts, und Geld verschwindet ins Nichts. Die Sonde hat zwei Schalter. Ohne Schalter läuft die Sim wie auf main; der Fingerabdruck ist gleich.

- **Erbteil** (`--inherit-money`): Ein Sohn, der seinen eigenen Haushalt gründet, bekommt den gleichen Anteil am Geld des Vaters wie seine Brüder. Der Vaterhaushalt behält einen Anteil, wenn er weiterbesteht. Neue Händler- und Senatorenhaushalte bekommen kein Startgeld mehr (bisher 5'000 bzw. 1'000'000 Denar aus dem Nichts).
- **Fuhrlohn** (`--freight-wage`): Die Fracht, die Händler zahlen, geht nicht mehr verloren. Sie wird am Startmarkt als Taglohn an Fuhrleute ausbezahlt. Das sind Landlose und Bauern mit freien Händen, beim gleichen Markttaglohn und auf derselben Arbeitsbörse wie die übrige Lohnarbeit.

Die Buchhaltung geht jeden Tag auf (nicht gebucht = 0). Das prüft der Test `money_loop_probe_books_everything`.

## Ergebnis, 100 Jahre

Geldbeträge in Millionen Denar, aufsummiert über 100 Jahre. Hunger = Hungertote der Jahre 31–100.

| Lauf | Leute J. 100 | Hunger | Geld im Umlauf J. 100 | aus dem Nichts | Fracht verschwunden | Staat prägt | öffentliche Arbeit |
|---|---|---|---|---|---|---|---|
| ohne (Seed 1) | 129'969 | 7'792 | 297 | 254 | 96 | 0 | 206 |
| Fuhrlohn | 128'104 | 7'732 | 450 | 324 | 0 | 0 | 315 |
| Erbteil | 125'942 | 10'860 | 171 | 0 | 56 | 92 | 0,3 |
| beide | 126'360 | 9'892 | 197 | 0 | 0 | 64 | 2,7 |
| ohne (Seed 2) | 133'573 | 7'145 | 354 | 334 | 110 | 0 | 385 |
| Fuhrlohn | 133'118 | 7'033 | 467 | 342 | 0 | 0 | 405 |
| Erbteil | 127'795 | 9'963 | 130 | 0 | 47 | 40 | 9,8 |
| beide | 127'222 | 8'748 | 165 | 0 | 0 | 27 | 22 |

Ein paar Einzelheiten zu den Läufen:

- Mit Fuhrlohn erhalten Fuhrleute etwa 0,5–1,7 Mio Denar im Jahr, für 30'000–320'000 Tage Arbeit. Im ersten Jahr sind es 2,6–2,7 Mio, weil am Anfang viel Korn umverteilt wird.
- Was am Jahresende noch auf Fuhrleute wartet, sind nur etwa 20'000 Denar.
- Der Erbteil setzt erst nach etwa 25 Jahren ein. Grund: Die Startbevölkerung hat keine Eltern-Verknüpfung, deshalb gibt es vorher keine Haushaltsteilungen nach dem Tod des Vaters (S81). Bis Jahr 100 gehen 28–39 Mio Denar als Erbteil vom Vater auf die Söhne über.
- Der Kornpreis fällt in allen Läufen von 7,1 auf etwa 0,5–1,3 Denar/kg. Das liegt nicht an der Geldmenge. Der Preis fällt auch dort, wo die Geldmenge auf 450 Mio steigt. Das passt zur bekannten Schwäche: Korn wird in kg statt in Denar gekauft.

## Wichtigster Befund: Woher das Geld aus dem Nichts kommt

Ich habe im Lauf ohne Schalter (Seed 1) jeden neuen Haushalt mit Startgeld gezählt:

- 237 neue Senatorenhaushalte zu je 1 Mio Denar, zusammen 237 Mio.
- 3'430 neue Händlerhaushalte zu je 5'000 Denar, zusammen 17 Mio.
- **Nur 25 der 237 Senatorenhaushalte sind Söhne.** Die übrigen 212 sind Einzelpersonen: geschiedene Frauen, die einen eigenen Haushalt gründen, weil ihr Vater nicht mehr lebt (S86). Sie behalten den Stand ihres Mannes und bekommen deshalb 1 Mio Denar aus dem Nichts. Bei den Händlern ist es gleich: 2'955 von 3'430 sind solche Einzelpersonen.
- Diese Frauen sterben allein. Ihr Geld fällt als Heimfall an den Staat: 222 Mio in Seed 1, 277 Mio in Seed 2.
- Damit bezahlt die Staatskasse die öffentliche Arbeit: 206 bzw. 385 Mio.

**Das Startgeld aus dem Nichts finanziert also heimlich den Staat.**

Wird es abgestellt (Erbteil), fehlt der Heimfall:

- Die Staatskasse ist ab etwa Jahr 5 leer.
- Die Staatslöhne (158–233 Mio) übersteigen die Einnahmen aus Steuern und Heimfall. Der Staat prägt deshalb 27–92 Mio Denar.
- Die öffentliche Arbeit fällt fast ganz weg.
- Den Landlosen fehlt dieser Lohn: Es gibt 22–40 % mehr Hungertote, und in Jahr 100 leben 2–5 % weniger Leute.

## Was das heisst

1. **Fuhrlohn** ist unbedenklich. Er schliesst ein Loch, Hunger und Bevölkerung bleiben gleich oder werden leicht besser. Solange das Startgeld weiterläuft, wächst aber die Geldmenge noch schneller.
2. **Erbteil** macht den Kreislauf ehrlich, deckt aber zwei offene Fragen auf:
   - **Scheidung:** Was nimmt eine geschiedene Frau mit? Heute nichts. Mit Erbteil hat eine geschiedene Senatorenfrau 0 Denar. Historisch zu prüfen ist die Rückgabe der Mitgift. Das Wort «Mitgift» trägt von Rom bis 1900. Ein einfacher, neutraler Vorschlag für die nächste Sonde: Sie nimmt ihren Kopfanteil am Geld des Haushalts mit, wie beim Erbteil.
   - **Staatshaushalt:** Ohne den heimlichen Heimfall reicht der niedrige Zehnt nicht für die Staatslöhne. Dann muss der Staat prägen, höhere Steuern erheben oder weniger ausgeben. Das gehört zur Planung der Staatsausgaben im Regierungs-Thread.

## Nachtrag: Scheidung mit Kopfanteil (Sonde `--divorce-money`)

Die geschiedene Frau nimmt ihren Anteil am Geld des Haushalts ihres Mannes mit, und zwar als eine seiner Erwachsenen: Geld des Haushalts geteilt durch (Erwachsene + 1). Das gilt, ob sie zum Vater zurückgeht oder einen eigenen Haushalt gründet. Gemessen wurde zusammen mit Erbteil und Fuhrlohn, also ganz ohne Geld aus dem Nichts.

| Lauf | Leute J. 100 | Hunger | Geld im Umlauf | Staat prägt | Heimfall | öffentliche Arbeit | bei Scheidung mitgenommen |
|---|---|---|---|---|---|---|---|
| alles (Seed 1) | 128'011 | 9'388 (+20 %) | 151 | 10 | 93 | 24 | 105 |
| alles (Seed 2) | 129'866 | 8'742 (+22 %) | 150 | 0 | 96 | 77 | 104 |

Verglichen mit «beide» ohne Scheidungsanteil:

- Der Staat prägt kaum noch: 0–10 statt 27–64 Mio.
- Der Heimfall ist wieder grösser (93–96 Mio), weil geschiedene Frauen jetzt eigenes Geld haben, das nach ihrem Tod an den Staat fällt.
- Es gibt deutlich mehr öffentliche Arbeit.
- Beim Hunger ändert sich wenig: Es bleiben 20–22 % mehr Hungertote als heute. Das ist der ehrliche Preis dafür, dass die heimlichen 250–330 Mio aus dem Nichts fehlen. Die Lücke schliessen höhere Steuern oder andere Staatsausgaben (Regierungs-Thread).

## Dateien

- `probe.patch`: der Sondencode gegen main. Darin ist Fuhrlohn schon Standard (`--no-freight-wage` schaltet ihn ab), Erbteil und Scheidungsanteil sind Schalter.
- `runs/*.txt.gz`: die zehn 100-Jahr-Läufe (`all-*` = mit Scheidungsanteil).

Aufruf:

```
grain --years 100 --seed S [--inherit-money] [--divorce-money] [--no-freight-wage]
```

PLATZHALTER: ein Fuhrmann-Tag je Taglohn Fracht; die Fracht wird am Startmarkt ausbezahlt.
