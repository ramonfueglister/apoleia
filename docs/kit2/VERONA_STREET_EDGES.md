# Verona – Strassenrand-Pilot

Stand: 1. November 2026. Status: **spezifiziert**, noch nicht implementiert oder im Spiel validiert. Diese Vorbereitung ist unabhängig von der laufenden Flusshöhenkorrektur. Sie verändert keine Laufzeitdateien.

## Grundlage und gestalterische Entscheidung

Die bereits angenommene Bildstudie `output/verona-ground-concepts/Strassenrand.png` im Projektordner zeigt dunkle unregelmässige Pflastersteine, niedrige helle Randsteine, einen schmalen staubigen Saum und sparsame Gräser. Das Bild ist ein Stilentwurf, keine Spielaufnahme und keine historische Quelle. Mauer, Topf und Zypresse sind dort Kontext; der erste Pilot ergänzt keine neuen Gebäude oder Bäume.

Beobachtet im vorhandenen Code und Atlas:

- `city_plan.gdshaderinc::cp_street` zeichnet Fahrbahn und Seitenflächen anhand derselben Verknüpfungsbits. `CP_HALF[1] = 0.12`; bei 0.25 Welt-km pro Parzelle und 0.0238 Welt-km pro Modellmeter ist eine Via **2.521008 m** breit. Diese Breite bleibt erhalten. Die vier Meter der separaten Landstrassen in `road_view.gd` dürfen hier nicht übernommen werden.
- Der gebackene Atlas `artifacts/render-data/city-plans-r1/city-plans-x1.png` enthält auf Veronas westlicher Zufahrt Kies, kein Basalt: RGB `(7, 165, 64)`, also Strasse, Oberfläche 1, Rang 1 und Ost-West-Verbindung 10. Auch der Quellplan `data/cities/plans/verona.json` nennt Kies.
- Die gerade Folge **(18452,6920), (18453,6920), (18454,6920)** ist ein geeigneter Kandidat. Nord- und Südnachbarn sind bestehende Grabanlagen (Typ 11), keine freie Dekorationsfläche. Ihre B-Bytes 128/0 richten ihre Zugänge zur Strasse. Der Torbereich beginnt erst weiter östlich; (18455,6920) und folgende bleiben ausgenommen.
- `roman_series.gd` setzt die drei bestehenden Grabanlagenvarianten aus `build_verona_tombs.py` ein. Ihre Modellmetadaten nennen einen freien Frontweg von 1.15 m. Dieser darf nicht durch neue Steine oder Gras verengt werden.

**Eigene Designentscheidung für die erste Umsetzung:** Kiesfahrbahn erhalten; helle niedrige Randsteine und staubige Übergänge übernehmen. Eine Umstellung auf Basalt wäre eine zusätzliche, ausdrücklich dokumentierte Materialentscheidung und gehört nicht zu diesem Pilot. Die vorgeschlagenen Parzellen sind anhand des Atlas geprüft, ihre Höhen und Sichtbarkeit noch nicht im Spiel.

## Begrenzte Modellfamilie

Originale Blender-Geometrie in Metern, gemeinsame Skalierung 0.0238, Identitätstransformationen, opake Vertexfarben und eigene `Model_detail`, `Model_medium`, `Model_far`. Kein automatisches Godot-Decimating.

| Teil | Vorgeschlagene Abmessung | Zweck |
|---|---|---|
| `street_kerb` | 0.70 m lang, 0.28 m breit, 0.16 m hoch | Einzelner warmer Kalkstein mit kleinen abgeschrägten Kanten, keine durchgehende starre Leiste |
| `street_kerb_end` | 0.70 × 0.28 m; von 0.16 auf 0.02 m auslaufend | Enden neben Zugängen ohne hohe Stolperkante |
| Gras | Vorhandenes `bank_grass`, gleiche Grösse | Höchstens wenige Büschel ausserhalb des Geh- und Zugangsbereichs; keine neue Artenfamilie |

Alle LODs erhalten dieselbe belegte Grundfläche und die Zugangsabstände. Kantenfasen dürfen vereinfacht werden; kein Verschwinden ganzer Zugangslücken. Kies und Staub sind ein Bodenmaterial, keine vielen lose schwebenden Steinmeshes. Farbziele: bestehendes `CP_GRAVEL` und warme Kalksteintöne, keine weisse Umrandung.

## Konkreter Platzierungsentwurf

Erster Einbau nur auf der mittleren Parzelle **(18453,6920)**; beide Nachbarparzellen dienen zum Prüfen der Übergänge. Eine Parzelle misst 10.504202 Modellmeter. Lokale X-Achse folgt der Strasse, lokale Z-Achse quer dazu; Ursprung im Parzellenzentrum.

- Unveränderte Fahrbahn: `abs(z) <= 1.260504 m`.
- Randstein-Mittellinien: `z = ±1.50 m`. Bei 0.28 m Breite liegt ihre Innenkante bei 1.36 m und lässt knapp 0.10 m Abstand zur Fahrbahn.
- Mittiger Zugang auf beiden Seiten: `abs(x) <= 1.0 m` vollständig ohne Randsteine, Gras oder erhöhte Dekoration. Diese **2 m** sind eine konservative eigene Gestaltung, keine Behauptung über den exakten vorhandenen Türstandort. Vor Einbau mit transformierter Geometrie aller tatsächlich gewählten Grabanlagen und ihrem Zugang abgleichen; bei Abweichung Lücke versetzen oder vergrössern.
- Zwei kurze Randabschnitte je Seite, vorläufig `x = [-4.2,-1.0]` und `[1.0,4.2]`, einschliesslich auslaufender Endstücke. Enden bleiben innerhalb der Parzelle. Endgültige Stücklängen ergeben sich aus ganzzahligen Einzelsteinen und schmalen Fugen; keine gestreckten Steine.
- Staubiger Saum nur zwischen Fahrbahnaussenkante und Randsteinen beziehungsweise in deren unmittelbarer Umgebung. Vorhandenen Kies durch leicht unterschiedliche Körnung anschliessen; keine scharfe zweite Pflasterfläche.
- Keine Vegetation im 2 m breiten Querkorridor, auf der Fahrbahn oder in Nachbarparzellen. Im ersten Bildvergleich darf Gras vollständig entfallen, wenn es die Zugänge unruhig oder eng macht.

Der Entwurf ist nur zulässig, wenn die echten GPU-Geländedreiecke dort ausreichend gleichmässig sind. Einzelsteine als starre Körper auf dem tatsächlichen Untergrund ausrichten und die Kontaktabweichung messen. Keine lange Leiste über eine Geländestufe spannen und keine Quader pro Vertex beliebig verbiegen. Bei einer Stufe Standort verkürzen oder ein anderes geprüftes gerades Stück wählen; das Gelände nicht zur Dekoration begradigen.

## Integration und Abnahme

1. Blender-Generator `tools/buildings/build_verona_street_edges.py` und Assets unter `app/assets/environment/` erstellen. Erst Modelle und lokale Mass-/LOD-Prüfung fertigstellen.
2. Separates `app/scripts/environment/verona_street_edges.gd` mit expliziter Parzellenliste, Atlasprüfung `(7,165,64)`, deterministischen Positionen und wenigen MultiMesh-Gruppen. Fehlende Assets oder geänderter Atlas deaktivieren den gesamten Pilot; ursprüngliche Strasse bleibt sichtbar.
3. Materialergänzung in einer eigenen Shader-Include auf genau diese Parzelle begrenzen. Der Hook in `cp_street` kommt erst nach Abschluss der parallelen Terrain-Arbeit. Keine Atlasänderung, kein globaler Oberflächenwechsel und kein Eingriff in Fluss-/Brückenprofile.
4. Sichtbarkeit bis 7.5 km; native Detailwechsel zunächst 1.5 und 4 km wie beim Uferpilot. Erst nach Bildprüfung übernehmen. Terrainabdeckung vollständig prüfen; keine GPU-Textur an ihren Rändern clampen, um fehlende Höhen zu kaschieren. Statische Positionen benötigen keine periodische GPU-Auslesung.
5. Prüfen: unveränderte Fahrbahnbreite und Verbindungen; sämtliche Meshvertices ausserhalb der Fahrbahn; Zugangskorridore frei; keine Überschneidung mit Grabanlagen, Mauern oder Gebäude-Sockeln in allen drei LODs. Die GPU-Dreieckshöhe prüfen, nicht die bilineare Kamera-Hilfsfunktion `ground_y`.
6. Echte Vorher-/Nachher-Aufnahmen aus identischer Kamera bei 0.65, 1.5, 3, 5 und 7.5 km; besonders beide Zugänge und die Enden betrachten. Hinaus-/Hineinpan, fehlendes Asset und geänderte Atlaszelle prüfen. Erst danach auf die zwei Nachbarparzellen erweitern.

Offen: endgültige Kontaktpunkte und Geländeneigung, tatsächliche Sichtbarkeit der Randsteine, genaue Zugangsgeometrie und Laufzeitkosten. Die Atlasanalyse allein validiert diese Punkte nicht. Nächster ausführbarer Schritt ist die Zwei-Teil-Blenderfamilie plus Höhen-/Zugangsprüfung der mittleren Parzelle.

## Vorbereitete Assets (1. November 2026)

Status der Modelle: **implementiert und geometrisch geprüft**, weiterhin **nicht im Spiel eingebaut oder validiert**. `tools/buildings/build_verona_street_edges.py` erstellt `street_kerb` und `street_kerb_end` unter `app/assets/environment/`. Beide besitzen 44/28/12 Dreiecke in ihren drei nativen LODs, eine opake Vertexfarben-Oberfläche und unveränderte 0.70 × 0.28 m Grundfläche. Der Randstein ist 0.16 m hoch; das Endstück fällt entlang seiner lokalen +X-Richtung auf 0.02 m ab.

`tools/tests/check_verona_street_edge_assets.py` prüft die exportierten GLB-Buffer unabhängig vom Generator: Dimensionen, Bodenberührung, nicht entartete Dreiecke, nach Verschweissen der Normalen-/Farbseams geschlossene Flächen, positives Volumen, Rampenhüllkurve, native LOD-Kosten und deaktivierte automatische LOD-Erzeugung. Ergebnis: zwei Assets, sechs LODs, keine Fehler. Bericht: `docs/handover/verona-street-edges/asset-validation.json`.

Editierbare Blenderdateien und die als Modellstudie beschriftete CPU-gerenderte Vorschau liegen im Projektordner `output/verona-street-edges/`. Die Vorschau zeigt die beiden Einzelteile, keine Platzierung im Spiel. Als nächster Schritt bleiben tatsächliche Höhen-/Zugangsprüfung und der oben beschriebene lokale Einbau.
