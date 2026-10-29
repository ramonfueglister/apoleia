# Dauerhafte Arbeitsregeln für `romaaeterna`

## Auftrag

- Maßgeblich ist der aktuelle Auftrag im [`README.md`](README.md) und das
  [Build-Kit 1](docs/kit1/README.md) mit [Entscheidungen](docs/kit1/decisions.md)
  und [Arbeitsstand](docs/kit1/STATUS.md).

## Maßstab (vom Nutzer oft wiederholt, vor jeder Grafikarbeit lesen)

- **Kein Eins-zu-eins-Maßstab und keine beliebige Verzerrung.** Die Welt ist
  eine tatsächlich verkleinerte, aus realen Geodaten abgeleitete Modellwelt;
  Längen und Höhen werden gemeinsam skaliert ([K06](docs/kit1/decisions.md),
  [TASK.md](docs/kit1/TASK.md#geografie-und-grafischer-maßstab)).
- Keine erfundenen Berge, verschobenen Küsten, zusammengeschobenen Abstände oder
  Höhenüberhöhung. Details dürfen nur maßstabsabhängig kontrolliert entfallen.
- Die Kilometerbreiten pro Zoombereich sind Orientierung, keine starren
  Realmaßstäbe ([Maßstabswerte](docs/kit1/decisions.md#maßstabswerte-orientierung-keine-starren-vorgaben)).
- Fremde Vorbilder (z. B. Minecraft „1 Block = 1 m“) nie mit ihrem eigenen
  Maßstab übernehmen; Block-, Tile- und Objektgrößen leiten sich aus unserem
  gemeinsamen Modellmaßstab ab.

## Evidenz und Herkunft

- Keine unbewiesenen Formeln, Mechaniken oder Paritätsbehauptungen über andere
  Spiele. Aussagen brauchen benannte Quellen, reproduzierbare Beobachtungen oder
  eine ausdrücklich als Hypothese markierte Herleitung.
- Beobachtete Regeln, abgeleitete Hypothesen und bewusste eigene
  Designentscheidungen strikt trennen.
- Kein fremder Spielcode, keine kopierten Skripte, keine dekompilierten oder
  reverse-engineerten Inhalte und keine fremden Assets im Projekt.
- Ergebnisse mit Status `offen`, `erforscht`, `spezifiziert`, `implementiert`
  oder `validiert` dokumentieren.

## Arbeitsweise

- Bestehende Nutzerautorisierung gilt fort. Keine neuen Genehmigungsanforderungen
  erfinden; keine Pakete, SDKs oder globalen Umgebungsänderungen außerhalb des
  ausdrücklich beauftragten Umfangs.
