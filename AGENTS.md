# Dauerhafte Arbeitsregeln für `vic3-clone`

## Auftrag und Rollen

- Fokus dieser Phase ist ausschließlich eine möglichst vollständige,
  messbare Wirtschaftssimulation.
- Zielplattform für die spätere App ist iPad; der Kern bleibt Rust mit späterer
  Swift-Anbindung.
- Der Hauptagent koordiniert und kommuniziert. Sämtliche inhaltliche
  Recherche, Dokumentation, Dateiänderungen, Implementierung und unabhängige
  Prüfung werden ausschließlich klar beauftragten Subagents zugewiesen.
- Das jeweils günstigste fachlich ausreichende verfügbare Modell ist Standard.
  Teurere oder leistungsstärkere Modelle werden nur bei begründetem Bedarf
  eingesetzt; keine starren oder veralteten Modellnamen vorgeben.

## Evidenz und Herkunft

- REA/Ghidra ist die einzige angeforderte Reverse-Engineering-/Skill-Methode.
  Keine ungefragten Superpowers-Freigabegates oder anderen Workflows einführen.
- Keine unbewiesenen Originalformeln, Mechaniken oder Paritätsbehauptungen.
  Aussagen brauchen benannte Quellen, reproduzierbare Beobachtungen oder eine
  ausdrücklich als Hypothese markierte Herleitung.
- Beobachtete Originalregeln, abgeleitete Hypothesen und bewusste eigene
  Designentscheidungen strikt trennen.
- Ergebnisse mit Status `offen`, `erforscht`, `spezifiziert`, `implementiert`
  oder `validiert` und mit Referenzversion dokumentieren.
- Kein Paradox-Code, keine kopierten Skripte und keine Assets in Produktcode.
  Forschungsmaterial und eigene Implementierung getrennt halten; keine
  pauschale rechtliche Zusage oder Cleanroombehauptung formulieren.

## Umfang und Arbeitsweise

- Wirtschaft umfasst mindestens Kapital/Investitionen, Eigentum/Dividenden,
  Beschäftigung, Einkommen/Wohlstand/Bedarf, Inputs/Produktion, Bau,
  Handel/Transport sowie Staatsfinanzen/Kredit.
- Politik, Militär und vollständige App liegen außerhalb dieser Phase; spätere
  ökonomische Wirkungen werden über definierte Schnittstellen angebunden.
- Jede Bilanz benennt Quellen und Senken ausdrücklich. Keine starre
  Geldmengenerhaltung ohne Begründung durch das eigene Modell verlangen.
- Keine Engine, keine bestätigte Formel und keine iPad-Leistungszusage ohne
  entsprechende Spezifikation und Prüfung.
- Bestehende Nutzerautorisierung gilt fort. Keine neuen Genehmigungsanforderungen
  erfinden; keine Pakete, SDKs oder globalen Umgebungsänderungen außerhalb des
  ausdrücklich beauftragten Umfangs.

## Maßgebliche Dokumente

- [`README.md`](README.md)
- [`docs/economy/README.md`](docs/economy/README.md)
- [`docs/economy/requirements.md`](docs/economy/requirements.md)
- [`docs/economy/toolchain.md`](docs/economy/toolchain.md)

Der historische Entwurf unter `docs/superpowers/specs/` ist durch den neuen
Wirtschafts-/iPad-Auftrag überholt; seine alten Ideen sind keine Evidenz.
