# Regionaler Umfang v5

**Stand:** 25.10.2026 · `kit1-landscape-v5` / `kit1-ops-v5`.
**Status:** spezifiziert und in Kitverträgen umgesetzt; unabhängig auf Kitkonsistenz validiert.
Keine Spielimplementierung.

## Ausschließlich geografische Änderung

Neuester Nutzerauftrag ersetzt die gesamte Erde und den kurz genannten Europa-
Ausschnitt durch den Raum der größten Ausdehnung des Römischen Reiches um 117,
den gesamten Mittelmeerraum sowie England und zusätzlichen nördlichen Kontext.
Das Gebiet bleibt zusammenhängend mit Meer-/Landpuffer; kein Imperial-Land-Clip.
Landschaftsreferenz 180, heutige Datenbasis, Maßstabs-/Generalisierungsregeln,
Karten-Diorama-Übergang, Stil, Sommer, unsichtbare quadratische Tiles und sämtliche
GUI-/Modusausschlüsse bleiben erhalten. Keine neue Tilegröße, Stadtzahl oder
Skala aus den Gesprächsrechnungen übernommen. Zukunftsabschnitt nicht neu entworfen.

## Konsequente Nachführung

- Auftrag, Entscheidungen, Startprompt, operative Daten-/Prüfabläufe auf Region
  umgestellt; [REGION](operations/REGION.md) ist der Gebietsbindungsprozess.
- `region.json` mit getrennten Jahresbezügen, Quell-/Masken-/Pufferbelegen; Konfig,
  Fixture, Coverage und Ableitung müssen dieselbe Region binden.
- A02 belegt alle drei Umfangskomponenten einschließlich England+nördlichem Raum.
- Regionale Ränder, Küsten und Tile-Nähte ersetzen globale Pol-/Datumsgrenzfälle.
- Bestehende Geometrie-, Kamera-, Quellen-/Rollen-, NoData-, Referenz-, Paket- und
  Generalisierungsprüfungen bleiben erhalten. Tests verwenden nur synthetische
  Verträge, keine behaupteten realen Grenzdaten.

## Ausstehend für spätere Umsetzung

Tatsächliche Grenzquellen/Konventionen, Maskenform, Randbreite, gebundenes Extent,
Projektion, Tilegröße, Maßstab und technische Messbudgets werden begründet gewählt.
Damit wird weder ein historisch exakter Grenzverlauf noch eine Laufzeit zugesagt.
Der vorbereitete Vertrag blockiert ohne tatsächliche Daten-/Werkzeugbindungen.

## Ergänzung zur modernen Gebietsauswahlhilfe (25.10.2026)

Der Nutzer bevorzugt geoBoundaries gbOpen ADM2 als moderne Orientierung für
Teilgebietsauswahl. Die Ergänzung präzisiert Auswahl und Herkunft, ändert aber
nicht den bestehenden Projektumfang, die drei Abdeckungskomponenten, deren
Maskenpflicht oder den Status der tatsächlichen Datenauswahl. ADM2-Auswahl ist
keine behauptete historische Grenze und keine sichtbare politische Grenze.
Die aktuelle GBR-ADM2-Metadatenprobe sowie ihre Lizenz-/Versionsgrenzen stehen
in [REFERENCES.md](REFERENCES.md); der spätere Dokumentationsablauf steht in
[operations/REGION.md](operations/REGION.md). Keine Features wurden geladen oder
ausgewählt; keine Geometrie, Pufferbreite oder Maske wurde erzeugt.

Der beauftragte Kurzreview fand keine Dokumentbefunde: ADM2 je Land, Trennung
Layer-ID/Feature-ID, Bindung von Lizenz und Datenrevision sowie Puffer-/Meer-
Ergänzung und die Abgrenzung zwischen modernem Auswahlanker und 117/180-Referenz
sind konsistent dokumentiert. Das validiert nur diese Dokumentanpassung, keine
konkreten Features, Geometrien, historischen Grenzen oder Produktfunktion.

## Prüfnachweise

Eigene aktuelle Befehle und Ergebnisse stehen in `evidence/kit-checks.json` unter
`region_scope_update`. Historische v2/v3/v4-Audits bleiben als damalige Nachweise
erhalten; sie gelten nicht automatisch für v5. Das portable ZIP wird erst nach
dem abgeschlossenen unabhängigen Review auf v5 aktualisiert.

## Gezielte Reviewkorrektur

Der erste Review fand fehlende maschinenlesbare Referenzgeometrien und eine
unzureichende Kreuzbindung der drei Coverage-Komponenten. v5 bindet deshalb
Quellartefakte, Feature-IDs, CRS, Referenzextents/-revisionen und Maskenrevision
ausdrücklich. Ein zu enger Kartenausschnitt und vertauschte Komponentenreferenzen
werden abgewiesen. 43 eigene Tests bestehen. Der unabhängige Retest bestätigte 43/43 Tests,
Selbstprüfung, beide Korrekturen und konsistente aktive Scope-Dokumente; keine
offenen Scopebefunde.
Dies prüft deklarierte Metadaten, keine historische oder geometrische Wahrheit.
