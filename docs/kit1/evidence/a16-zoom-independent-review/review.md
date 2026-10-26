# A16 – unabhängige Bildprüfung der Zoomfolge Rom

Geprüft: [`a16-zoom-main`](../a16-zoom-main/manifest.json), 11 Einzelbilder (640×360) von
Commit `f589e37`. Das ist main `ea8e0dd` plus Startup-Telemetrie, der Diff ist laut
`git diff` reine Telemetrie. Prüfer: independent-claude-subagent, 26.10.2026.
Maschinenlesbar: [`review.json`](review.json).

**Urteil A16-Bildteil: FAIL.** Rund um Rom ist die Folge plausibel, die Gesamtfolge aber nicht.

## Was trägt

- **Hashes:** Alle 11 PNG-Hashes stimmen mit dem Manifest überein.
- **Rom-Region (0.2–1.0):** Die Schritte lesen sich als Verfeinerung. Lage und Form bleiben
  konsistent für:
  - Tiberlauf und -mündung
  - tyrrhenische Küste
  - Korsika und Sardinien
  - toskanische und pontinische Inseln
  - Apenninkämme

  In der Rom-Region sind keine Löcher, Tile-Nähte oder Flachstellen zu sehen. Das Relief ist
  plausibel zurückhaltend.

## Befunde

- **P1 (0.0, 0.1):** Über Sahara und Arabien liegt ein harter, achsparalleles helles Rechteck.
  Ab 0.2 ist es verschwunden: Eine Domänen- bzw. Landcover-Grenze ist als Naht sichtbar, und
  die Oberfläche bleibt nicht konsistent.
- **P1 (0.0, 0.1):** Im Nordosten (Baltikum/Russland) liegt ein rechteckiger dunkelgrüner
  Landcover-Block mit geraden Kanten.
- **P1 (Ende):** `legacy_zoom` 1.0 entspricht Zoom 0.6586 bei 240 km Sichtbreite. Der nahe
  Diorama-Bereich fehlt, „Übersicht bis Detail“ ist nur teilweise belegt.
- **P2 (0.4):** Wolken erscheinen als gepunktete Dither-Muster, bei 0.3 und 0.5 dagegen als
  weiche Flecken. Der Stilwechsel zwischen Nachbarstufen ist ein Popping-Verdacht.
- **P2 (0.4–1.0):** In Mittelitalien ist nur ein größerer See erkennbar. Trasimeno und ein
  zweiter der Seen Bolsena/Bracciano fehlen sichtbar. Die Darstellung ist über alle Stufen
  konsistent, doch die Auslassung ist nicht begründet. Bei 640×360 ist das unsicher, ein
  Datenabgleich ist nötig.
- **P2 (0.3–1.0):** Das Flussnetz ist dünn:
  - Sichtbar sind nur Tiber, Ofanto und Po.
  - Arno, Volturno und Liri-Garigliano fehlen.
  - Bei 0.3 ist der Tiber in Segmente zerrissen.
  - Für die Auslassungen fehlt der Quellen- und Regelbezug.
- **P2 (0.0, 0.1):** Treppenartige Rasterküsten, weiße Wolken-„Flocken“ als Rauschen und ein
  grauer Weltrand oben.
- **P3:**
  - Wald springt von 0.3 auf 0.4 abrupt von Farbton zu Punkt-Speckle. Ab 0.8 erscheinen
    Baumsprites.
  - Bei 1.0 ist die Bodentextur weicher als bei 0.9 (Datei 170 KB statt etwa 300 KB).
  - Wolken verdecken bei 0.8–1.0 Teile des Apennins.

## Manifest

Das Manifest bindet:

- Commit
- Pose: lon/lat, Zoom, Sichtbreite, Elevationswinkel
- Auflösung, Abdeckung und Hashes je Bild
- Hardware

Es fehlen:

- Die Transformation von `source_capture_sha256` zu `sha256` ist nicht erklärt, die
  Quellaufnahmen sind nicht getrackt.
- `coverage: complete` ist eine Selbstauskunft ohne getrackte runtime.json bzw. Log.
- Kameraausrichtung, FOV, Wolkenschalter und -seed sowie das Aufnahmekommando.
- Dataset-, Renderer- und Policy-Hashes.

## Grenzen

- 640×360: Feine Küsten, Flüsse und Seen sowie Waldgruppen sind nicht sicher beurteilbar.
- Je Stufe gibt es einen Einzel-Snapshot nach eigenem Start, keine kontinuierliche Aufnahme.
  Popping und Übergangsresiduen sind daher nicht beobachtbar.
- Es gibt nur einen Ort, die Nahstufe fehlt, Wolken sind aktiv, und es fehlt eine
  Quellvektor-Überlagerung.

## A08 – vorläufig (nur Hinweis, 640×360 reicht nicht)

**Vorläufig FAIL.**

- **Palette:** zurückhaltend und nicht zu bunt. Positiv, aber deutlich ocker- und olivlastiger
  als die Primärreferenz. Frisches Grün und abgestufte Flachwasserzonen fehlen weitgehend.
- **Geometrie:** glatt schattiertes Relief ohne erkennbare stilisierte Facettierung. Die
  facettierten graubeigen Gebirge der Referenz fehlen. Nicht klotzig oder voxelartig und nicht
  fotorealistisch, das ist positiv.
- **Wald:** lesbare Waldgruppen im Sinne der Referenz erscheinen erst bei 1.0 und nur
  andeutungsweise, davor nur Speckle.
- **Landschaftsdetail:** Die Dioramadichte der Referenz wird im erfassten Bereich nicht
  erreicht.

Für eine A08-Entscheidung sind feste Kameravergleiche in höherer Auflösung inklusive Nahstufe
erforderlich.
