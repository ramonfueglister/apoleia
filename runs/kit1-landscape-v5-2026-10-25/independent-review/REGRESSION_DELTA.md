# Gezielte unabhängige Nachprüfung der drei Korrekturen

Referenz kit1-landscape-v5 / kit1-rendering-v4. Geprüfter Renderer SHA256
`06d97361665fca83eb65108cd241ca9356557b2d8744ad4bc873d121cc456fc5`.
Dieser Anhang ersetzt die zugehörigen offenen Befunde aus
`FINAL_REVIEW_WORKING.md` nur im hier tatsächlich geprüften Umfang.
Keine Produktdatei durch den Prüfer geändert.

## Echte Panregression

Das lokale Fix-Bundle wurde tatsächlich mit Metal/AppleM3Pro gestartet;
dieselbe problematische native CUA-Aktion[600,400]→[900,600] wurde erneut
ausgeführt. Der Framebuffer verschob sich sichtbar300/200 UI-Pixel. Das Ziel
änderte sich von17.500001907348633°E/39.5°N nach
-2.110191822052002°E/49.366668701171875°N. Der umgekehrte echte Drag führte
sichtbar und numerisch zum Ausgangsziel zurück. Anschließende einzelne
Wheel-Up-/Down-Aktionen funktionierten ebenfalls (Zoommaximum.0349952264).

Die ungefilterte Rawfolge bestätigt weiterhin relative0/event.mask0 bei
wirklicher Positionsänderung und gedrückter Taste; der neue operative
Downstate/Positionsfallback verarbeitet sie jetzt. Ein synthetischer Test
wurde nicht als Ersatz verwendet. App kontrolliert geschlossen, Exit0.
Rohbeleg: `pan-fix-regression/runtime.json`. A01 echte direkte Eingabe auf
dieser Revision **validiert**; A14 geografische Pan-Rückkehr ebenfalls.

## Zwischenmaterial A08

`artifacts/runtime/material-intermediate-regression/frame_000030.png`
wurde tatsächlich in1920×1080 geöffnet und gegen das frühere verlustfreie
Zwischenbild desselben Ziels/Zooms sowie die bereits betrachtete Primärreferenz
beurteilt. Die dominanten dunklen/hellen rechteckigen Coverkontraste sind
deutlich reduziert; eine ruhigere natürliche hellgrüne Bodenwirkung mit
subtiler Materialvariation bleibt. Subtile Quellrastergrobheit ist weiterhin
sichtbar. Sie wird weder als neue Quellauflösung noch als gemessener Bodendetail-
Gewinn ausgegeben. Höhen, Küsten, Baumaufnahmegates bleiben unverändert.

Der konkrete vorherige A08-Kontrastblockbefund ist damit gezielt verbessert
und technisch nachgeprüft. Endgültige Nutzerstilbewertung bleibt offen;
die finale komplette Tour dieser neuen Revision ist noch zu prüfen.

## Gebirgspositivkontrolle A16

Vorabplan `ridge-positive-plan.json` SHA256
`0be45505595a91fa42e505c0e5541d18b3abf7accbae0c1ea3a8fb94e701d913`
und quellenabhängige Auswahl wurden vor der Renderprobe gespeichert.
Der Prüfer startete selbst das Fix-Bundle mit:

```sh
'artifacts/Roma Aeterna Fix Regression.app/Contents/MacOS/RomaAeterna' --resolution 1920x1080 -- --snapshot --view 36.047916666666666 36.33958333333334 0.7 --probe-anchor independent-positive-ridge 36.047916666666666 36.33958333333334 --probe-plan /Users/ramonfuglister/Coding/vic3-clone/runs/kit1-landscape-v5-2026-10-25/independent-review/ridge-positive-plan.json --capture-dir /Users/ramonfuglister/Coding/vic3-clone/runs/kit1-landscape-v5-2026-10-25/independent-review/ridge-positive-runtime
```

Exit0; das echte PNG `ridge-positive-runtime/frame_000030.png` tatsächlich
geöffnet. Der gewählte positive Sourcepunkt ist Landkind0,1752.130859375m
native Höhe. Sein unveränderter Source-lon/lat wird vollständig exportiert;
die Float32-Weltquery der Anwendung liefert1752.0767150557367m. Dieser
numerische Samplingunterschied wird nicht verschwiegen. Effektive
Float32-Kameramitte36.047916412353516/36.33958435058594 ist separat vom
nominalen Sourcepunkt dokumentiert.

Bei Zoom.7/Relief.8113854595 misst die aktive Mesh-/Morphprobe
1.4163815187686293 Modelleinheiten Höhe. Gegen die unabhängig direkt
abgefragte native Quelle ergibt sich -6.497508264m Quellenhöhenäquivalent,
vertikaler Bildschirmrest.779290187px, damit unter dem vorab gebundenen
2px-Surfacebudget. Keine Punkte nach günstigem Screenfehler ausgewählt.
Original-Ozeananker protected-ridge-4 bleibt als Erratum erhalten.

`ridge-positive-review.json` bindet RawSHA
`144dd2f03e9cea8152b7c283fa8451ba07f8d652361feea572726d658431bdef`.
Der Befund ist eine lokale positive Massif-/Mesh-/Morphstichprobe mit echtem
Bild und CPU-Camera3D-Projektion; keine GPU-Vertexreadback- oder globale
Kammnetzbehauptung.

## Waldquellen-/Seed-Gegenprobe A09/A14

Die neue gezielte18–23s-Rawdatei des Owners wurde unabhängig gegen die
tatsächlichen Quellpayloads geprüft, nicht gegen fest im Logger gesetzte
cover10/water0-Labels. Sämtliche18459 akzeptierten Kandidaten:

- 18459 unterschiedliche globale18m-Zellen; unabhängig rekonstruierter
  Seed/Float32-XZ-Ort maximal0 Modelleinheiten Differenz,0Familienabweichungen.
- Kanonische Coverklasse10 und Detailwaterkind0 bei allen Kandidaten.
- Unabhängig RG8-dekodierte bilineare SDF-Distanz bei allen Kandidaten<-20m;
  maximale Differenz zur Runtime0m.
- Maximal400 Kandidatenqueries pro erzeugtem Chunk,1Chunk pro Frame;
  gemessene maximale Wald-CPU-Arbeit8.286ms.

Rohhash und alle Ergebnisse in `forest-source-regression.json`. Damit ist
die Quellen-/Seedbindung der neuen budgetierten Waldrepräsentation geprüft.
Die alte langsame Baumregeneration wird nicht auf diese neue Revision
übertragen. Ein vollständiger neuer Normalpaar-/Filmabschluss bleibt noch
ausstehend; daraus folgt hier noch kein uneingeschränkter A09-/A12-Pass.

Nach Pan/Ridge wurden sämtliche Prüfer-Appjobs beendet und der Driver
explizit zurückgegeben. Die leichte Quellengegenprobe wurde vor Freigabe
der neuen Benchmarks beendet; keine CPU-Analyse läuft parallel zu ihnen.
