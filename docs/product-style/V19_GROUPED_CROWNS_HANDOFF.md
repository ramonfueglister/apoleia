# V19: lokale quellengebundene Kronengruppen

Referenz `kit1-landscape-v5`, Revision
`game-graphics-style-v19-source-grouped-crowns-r1`. Status `implementiert`,
begrenzte CPU-Verifikation `validiert`; sichtbare Referenznähe weiterhin `offen`.
Keine neue A07-/A08-, Leistungs- oder Gesamtabnahme.

Die echten SourceV2-Fernbilder `camera/source-v2-canopy-ab-r1/baseline.png`
und `footprint_filter.png` wurden zusammen mit `control.json`, den Originalen
`weit.png`/`mittel.png` und dem Primärtriptychon angesehen. Native Ausschnitte
liegen im neuen Evidenzordner. Der Filter mildert Facettenkontrast, ändert jedoch
nicht die vielen einzeln stehenden Spitzen und den durchscheinenden Boden.
Die Vorlage zeigt zuerst dunkle zusammenhängende Waldgruppen, danach Kronen.
Dies begründet die gezielte Änderung ihrer Überdeckung, nicht einen neuen
Baumtyp oder eine neue Wald-/Terrainquelle.

## Einziger Geometrieeingriff

`app/scripts/style/landscape_style.gd` behält den vorhandenen Kronenmesh,
Kandidatenabstand 5.2, neun Quellenproben je Kandidatenzelle, Seeds,
Höhenziehung, Palette und die bestehende Felspriorität. Der neue Default
`source_grouped_crowns` bündelt diese Kandidaten innerhalb weltfester Gruppen
von 3×3 Kandidatenzellen (15.6 Modelleinheiten; keine vermessene Waldgröße).
Der deterministisch gejitterte Gruppenanker muss in der Waldquelle liegen
und darf keinen dominanten Fels tragen. An Waldkanten wird der nächste geeignete
von neun festen Quellenproben gewählt. Gibt es keinen Anker, bleibt die
vorhandene Wurzel unverändert.

Eine Wurzel nähert sich dem Anker mit Restabstand 0.46. Sechs Proben entlang
dieser beschränkten Bewegung müssen Wald/Land bestätigen und dürfen den
bestehenden Felsvorrang nicht umgehen. Nur bei bestandener Verschiebung wird
die vorhandene Krone horizontal um 1.18 verbreitert; Höhe und Kronenfamilie
bleiben gleich. Die ursprüngliche und die neue Fels-Sichtbarkeit werden durch
`min` verknüpft, damit kein ursprünglich unterdrückter Felsbaum durch Umsetzen
sichtbar wird. Vorhandene Land-/Wasserprüfung bleibt erhalten, bei breiteren
Gruppen kommen diagonale Randproben hinzu. Es entstehen ausschließlich echte
Kronenmeshes, keine Hüllkörper, Bodenplatten oder Zusatzbäume.

3, 0.46 und 1.18 sind bewusst eigene referenzgeführte Umsetzungswerte, keine
präzisen Originalmessungen. Die Quelle wird nicht als Einzelbauminventar
umgedeutet. Lokale Verteilung und Überdeckung ändern sich ausdrücklich;
der Waldquellenlayer und seine Rollen bleiben unverändert.

Die Gruppenzellen hängen nicht von Kamera, Zoom, Render-LOD oder Chunkgrenzen
ab. Chunks besitzen Wurzeln anhand ihrer endgültigen X/Z-Position und prüfen
ausreichend Kandidaten außerhalb ihrer Grenzen. Die Grundhöhe kommt weiterhin
vom Runtime-Surfacecallback. `placement_sha256` enthält X/Z, Höhe, Phase und
Breite, jedoch nicht die LOD-abhängige Bodenhöhe. Der Quellenwurzeldigest bindet
weiterhin den tatsächlich gebauten Stand einschließlich Bodenhöhe.

## Kontrolle und Identität

- Produktmode: `source_grouped_crowns`.
- Kontrollmode: `all_source_crowns`, Arrays und Wurzeldigest zur eingefrorenen
  V16-Baseline CPU-geprüft unverändert. `current_body` bleibt nur historisch.
- Geometrieidentity: `pointed-crown-v8-cluster3-contract046-width118-r1`.
- Generator-SHA256: `2073e20ad6e2ed828bc238ee14d411ddaf67a974adb8c196aada9bd17cff0c33`.
- Policy führt Mode, Identity und Revision ausdrücklich. Runtime muss diese
  zusammen mit Generatorhash und vorhandener Source-/Atlas-/Stridebindung
  im Cachekey führen. Alte V16-/V14-Caches sind nicht austauschbar.

Die Kontrolle läuft über den vorhandenen sechsten `surface_grid`-Parameter:
`{"forest_geometry_mode":"all_source_crowns"}` beziehungsweise
`{"forest_geometry_mode":"source_grouped_crowns"}`. Kein neuer Nutzer-Modus
oder CLI-Schalter wurde in die App eingebaut. Runtime verwendet seinen externen
Kontrollwrapper und gibt den Mode ausdrücklich weiter. Optionales
`record_forest_geometry:true` liefert nur CPU-Diagnosemetadaten; der normale
Aufruf trägt diese großen Einzelwurzelarrays nicht im Cache.

## Tatsächliche CPU-Prüfung

Runtime führte den eingefrorenen Stand mit Godot 4.7.2 headless aus, Exit 0,
keine fehlgeschlagene Prüfung. Befehl aus dem Repo:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path app --script /Users/ramonfuglister/Coding/vic3-clone/runs/kit1-gamegraphics-v2-2026-10-25/style/v19-grouped-crowns/verify_groups.gd
```

Der Test prüft wiederholte vollständige Mesharrays; eine absichtlich nicht
am Raster liegende Chunkzerlegung; unveränderte horizontale Platzierung bei
veränderter Bodenhöhe; Wald-, Wasser- und Felsausschlüsse an 485 gezeichneten
Testkronen; sowie vollständige Baselinearrays und den alten Wurzeldigest.

Zusammenhang wird nicht aus Sollradien behauptet: Die tatsächlichen
Kronendreiecke werden in 1.5 Modelleinheiten Höhe über ebenem Boden geschnitten
und die Schnittpolygone auf Überschneidung geprüft. Isolierte Kronen fallen von
58.15 % auf 0.81 %, Kronen in Komponenten ab drei Kronen steigen von 13.88 %
auf 98.73 %. In dem begrenzten Rechteck liegen 908 Baseline- und 864 gruppierte
Kronen; diese lokale Zähldifferenz folgt der neuen Grenzzuordnung nach Verschiebung,
nicht einer behaupteten globalen Baumreduktion. Der CPU-Test belegt räumliche
Überdeckung und Invarianten, keine visuelle Abnahme und keinen Gebietsvolltest.

Evidenz: `runs/kit1-gamegraphics-v2-2026-10-25/style/v19-grouped-crowns/` mit
`verify_groups.gd`, `cpu-verification.json`, `cpu-verification.log`,
`checkpoint.json`, neuer physischer Quellkopie und separat erhaltener Baseline.
Alte V16-Digests, Bilder und Snapshots wurden nicht verändert.

Runtime übernimmt nach diesem Freeze genau das vereinbarte Fern-/Mittel-/
Nahvergleichsfenster. Ein Weltcachebake wartet auf die tatsächliche Geometrie-
und Bildprüfung. Canopy-/Terrain-/Wassershader wurden bei dieser Änderung nicht
angefasst; Materialpixel, Inselringe und übrige Formabweichungen bleiben offen.
