# EU5-Referenzkatalog und eigene Entsprechungen

Referenzversion: `eu5-correspondences-v2-2026-10-26` · Bezugsdatum: **26.10.2026**.
Katalogstatus: `erforscht`; eigener Kompositionsplan: `spezifiziert`.
Dies ist ein Recherche- und Designbericht. Der tatsächliche Generierungs- und
Dateistand steht im [Produktmanifest](../../app/assets/music/eu5-correspondences.json)
und im [Soundtrackbericht](README.md).

## Festgelegter Umfang

Der Nutzerauftrag verlangt eine Entsprechung für jeden EU5-Soundtracktitel.
Erfasst sind die **60 Albumpositionen der vier bis zum Bezugsdatum gefundenen,
öffentlich veröffentlichten offiziellen EU5-Soundtrackalben**. Das ist ein
versionsgebundener öffentlicher Albumkatalog, keine Behauptung, jede nur im
Spiel oder in Trailern vorkommende Audiodatei erfasst zu haben.

| Gruppe | Offizielle Veröffentlichung | Albumpositionen | Befund |
|---|---|---:|---|
| `base` | Hauptalbum, 19.06.2025 | 26 | `erforscht`; offizielle Kapitel-/Albumliste |
| `cultures` | Cultures of the World, 12.12.2025 | 21 | `erforscht`; offiziell veröffentlichte regionale Spielmusik |
| `phoenix` | Fate of the Phoenix, 30.04.2026 | 4 | `erforscht`; eigenes DLC-Soundtrack-EP |
| `pillars` | Across the Pillars, 24.10.2026 | 9 | `erforscht`; OST bereits veröffentlicht, obwohl das DLC selbst erst für 28.10. angekündigt ist |

Die vollständige geordnete Titelliste einschließlich Herkunft, eigener Titel,
eindeutiger IDs und Kompositionsbriefs steht in
[`eu5-catalog.json`](eu5-catalog.json). Die IDs bleiben über Generierung und
Paketprüfung stabil: `eu5-base-01` bis `eu5-base-26`,
`eu5-cultures-01` bis `eu5-cultures-21`, `eu5-phoenix-01` bis
`eu5-phoenix-04`, `eu5-pillars-01` bis `eu5-pillars-09`.

Nicht enthalten sind die EU4-Vorbesteller-Musiksammlung, Trailer-Audios ohne
eigenen belegten Albumtitel und nicht veröffentlichte künftige
Soundtrackalben. Für ein veröffentlichtes The-Auld-Alliance-Album wurde in
der Recherche kein Beleg gefunden; daraus wird keine Aussage über spätere
Veröffentlichungen abgeleitet. Die vorhandenen vier v1-Tracks bleiben
separate Bonusstücke; sie werden keiner der 60 Positionen nachträglich als
erfüllte Einzelentsprechung zugerechnet.

## Belegte Originalinformationen

- **Hauptalbum:** Der offizielle Europa-Universalis-Kanal veröffentlichte am
  19.06.2025 eine [durchgehende OST-Veröffentlichung mit 26 Kapiteln](https://www.youtube.com/watch?v=OLdEOqfEouw).
  Das [Spotify-Album von Håkan Glänte und Paradox Interactive](https://open.spotify.com/album/12tydVAV56ZREp85NsAAR5)
  belegt Reihenfolge und Einzeldauern. Schreibweise und Zeichensetzung im
  Katalog folgen der Albumliste; die Videokapitel haben kleine Titelvarianten.
- **Cultures:** Die [offizielle Steam-Ankündigung vom 12.12.2025](https://steamcommunity.com/games/3450310/announcements/detail/509599695238070467)
  beschreibt regionale Variationen bereits vorhandener Spielmusik.
  [Spotify](https://open.spotify.com/album/6YKneZskHvY9Kx10HXQatY) führt die 21 Titel
  in sieben Dreiergruppen; [Apple Music](https://music.apple.com/us/album/europa-universalis-v-cultures-of-the-world-official/1860646026)
  bestätigt Datum und Titelzahl. Es handelt sich nicht um einen angenommenen
  Bonus-DLC, sondern um ein separates offizielles Album regionaler Musik.
- **Phoenix:** Das [offizielle Künstler-/Paradox-Album auf Spotify](https://open.spotify.com/album/7mWyuTQM5AYCY6F2NS0zKE)
  belegt vier Titel und den 30.04.2026; die [offizielle Videoveröffentlichung](https://www.youtube.com/watch?v=HAIWhpHTVpI)
  ist über den Paradox-Kurzlink `https://pdxint.at/FOTP-OST` erreichbar.
- **Pillars:** Der [offizielle Europa-Universalis-Kanal](https://www.youtube.com/watch?v=NQSs664jH88)
  belegt neun Kapitel und die Veröffentlichung am 24.10.2026. Die
  [Paradox-Produktseite](https://www.paradoxinteractive.com/games/europa-universalis-v/add-ons/europa-universalis-v-across-the-pillars)
  beschreibt die sechs kastilischen und drei marokkanischen Musikstücke.
  Die einzelnen Angaben aus dem YouTube-Metadatenabruf sind im
  [kleinen Quellbeleg](eu5-pillars-source-metadata.json) festgehalten.
  Die Dauern des Katalogs für dieses Album sind aus Kapitelabständen
  abgeleitet und schließen mögliche Videoübergänge ein.

Alle Quellen wurden am 26.10.2026 öffentlich abgerufen. Zeitweise scheiterte
`web.open` bei YouTube an Drosselung. Für den Pillars-Beleg wurde deshalb das
öffentliche Watch-HTML per HTTPS mit `User-Agent: Mozilla/5.0` abgerufen und
`ytInitialPlayerResponse.videoDetails` sowie das Veröffentlichungsdatum aus
`microformat` gelesen. Es wurden weder Audio noch Video heruntergeladen.
Der Beleg nennt Kanal-ID, URL, Videolänge, Kapitel, Datum und einen SHA-256
über die Beschreibung, ohne ihre gesamte Prosa zu kopieren.

## Eigene musikalische Gestaltung

Der Plan enthält **36 Instrumental- und 24 Vokalentwürfe**. Jede Originalposition
erhält einen anderen eigenen Titel, eigenen Prompt und eine eigene
Generierungsidentität. Zwei Varianten eines einzigen Requests gelten nicht
als zwei unterschiedlich spezifizierte Originalpositionen. Die Datei darf
technisch länger oder kürzer als ihr Referenztitel sein; eine genaue
Längenparität ist keine Anforderung.

Belegte Metadaten sind ausschließlich Titel, Albumzuordnung, Reihenfolge,
Veröffentlichungsstand und näherungsweise Dauer. Die Rollen, BPM,
Instrumentierung, Dynamik und Vokalverteilung der JSON-Datei sind
**bewusste eigene Designentscheidungen**. Beispielsweise wird die abstrakte
Rolle einer Reiseouvertüre, höfischen Szene, Klage, Tanznummer oder
Friedensauflösung in eine neue Komposition übersetzt. Diese Rollenplanung
wird nicht als gemessene oder gehörte Eigenschaft der Originalaufnahme
ausgegeben.

Die Gesangstexte wurden für diese Entsprechungen neu verfasst: überwiegend
künstlerisches Latein, dazu eigene englische, spanische und portugiesische
Texte sowie ein Vokalisenentwurf. Das sind keine Originaltexte und keine
geprüften historischen Übersetzungen. Der Prompt für das Bach-bezogene
Referenzstück verlangt ausdrücklich eine neue Bass-/Arpeggiofigur statt
Übernahme der genannten Suite. Traditionelle Songtitel im Quellenkatalog
werden nicht als Freigabe ihrer Aufnahme, Melodie oder Texte verstanden.

Regionale Besetzungen sind eine eigene Klangfarbenentscheidung. Weder
sprachliche noch kulturgeschichtliche Authentizität wird versprochen.
Insbesondere sind die neuen englischen Gemeinschaftslieder und Vokalisen
fiktionale Spielmusik und werden nicht als indigene, religiöse oder
traditionell überlieferte Aufführungen bezeichnet.

## Grenzen und Abnahme

Eine subjektive Höranalyse der Originalaufnahmen wurde hier nicht
durchgeführt. Es wurde keine EU5-Aufnahme, Partitur oder Melodie an Suno
übergeben. Damit ist der Plan eine nachvollziehbare, einzeln zugeordnete
eigene Interpretation des Katalogs, keine musikalische Rekonstruktion.
Eine enge musikalische Entsprechung einzelner Originalaufnahmen bleibt
`offen`, bis die Stücke tatsächlich vergleichend angehört werden.

Für die Implementierung müssen alle 60 IDs genau eine vorhandene,
fehlerfrei decodierbare ausgewählte Audiodatei besitzen; zusätzliche
Anbietervarianten bleiben getrennt. Das Produktmanifest muss Hash,
Dateigröße, Dauer, Generierungsbeleg, Instrumental-/Vokalauftrag und
technischen Prüfstatus enthalten. Die Prüfung der tatsächlichen hörbaren
Stiltreue, des Gesangs, der Aussprache und der subjektiven Qualität ist von
Dateidecodierung und API-Status getrennt und darf ohne Hörabnahme nicht auf
`validiert` gesetzt werden.
