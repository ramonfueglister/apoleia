# A12 unabhängiger Review (Stand c2c0015)

**Verdikt: PARTIAL.** Geprüft wurde `a12-main-ea8e0dd` (Messbuild f8ce8aed, Apple M3 Pro, macOS 26.5, Godot 4.7.2 Metal, 640x360, Tour `runs/kit1-landscape-v5-2026-10-25/fixture.json`, je zwei Läufe Forward+ und Mobile).

## Ziel
Es gibt keine gebundene Zielklasse. ACCEPTANCE.md lässt Referenzhardware, Auflösung, Spitzen- und Speicherbudget `offen`. RENDERING.md schlägt nur vor: „60 Hz Zielrate bei festgehaltener 1920×1080-Ausgabe (p95 ≤16,7 ms; p99 ≤33,3 ms) und null sichtbar unbedeckte Terrainframes“.
Gegen diese Arbeitswerte liegt Forward+ im Tourteil knapp darüber (p95 16,77/16,765 ms). Mobile liegt darunter (p95 11,8/11,9 ms, p99 ≈20 ms). Beides gilt aber nur für 640x360, also etwa 1/9 der Zielpixel auf einem Retina-Display. Über die Zielauflösung sagt das weder ein Bestehen noch ein Scheitern aus.

## Erfasst / fehlt
- Framezeiten mit Verteilung, Spitzen und Schwellenzählern: **erfasst**. p50 ≈8,4 ms passt allerdings zu 120-Hz-VSync (ProMotion). Die Werte geben also den Display-Takt wieder, nicht die Renderkosten. CPU-/GPU-Zeit fehlt.
- Speicher: **teilweise**. Mobile `gpu_texture_memory_bytes_max` = 2^64 ist ein Unterlauf und damit ungültig. Ein Budget fehlt.
- Ladeunterbrechungen: **teilweise**. Startwartezeit und Startspitzen sind erfasst, die Spitzen in der Tour sind nicht zugeordnet.
- Request-Alter: **teilweise**. `terrain_streaming` meldet in 3 von 4 Läufen 0,0. Der aktive Clipmap-Pfad ist offenbar nicht instrumentiert.
- Sichtbare Verspätung: **fehlt**. Es gibt nur `missing_max` 76–100 ohne Angabe, ob die Kacheln sichtbar fehlen.
- Byte-/zeitbegrenzte Uploads: **teilweise**. Es sind nur Upload-ms-Maxima gemessen, keine Bytes pro Frame und keine konfigurierte Grenze.
- Forward+ gegenüber Mobile: **teilweise**. Tour und Binary sind gleich, die Material-/Featureparität ist aber nicht belegt. Es gibt nur einen Lauf je Bedingung, Forward+ lief immer zuerst, und die Framezahlen weichen ab.
- Hardware, Auflösung und Pfad sind benannt. Die Auflösung entspricht aber nicht dem Ziel, und die Rohdaten (`runtime.json`) liegen nur lokal.
- Keine plattformübergreifende Behauptung: **erfüllt**.

## Konsistenz
Perzentile und Zähler stimmen zusammen: Forward+ hat 5,2 % > 16,7 ms und ein p95 von 16,77 ms, Mobile hat 2,1 % und ein p95 von 11,8 ms. Die Zahl der Frames > 100 ms deckt sich mit den gelisteten Spitzen. Alle Sekundenspitzen liegen vor dem Tourstart. Kalt- und Warmlauf sind im Tourteil praktisch gleich. Ungeklärt bleiben: der warme Forward+-Lauf hat mehr RSS (1,54 GB gegenüber 1,30 GB), der kalte Mobile-Lauf hat zu wenige RSS-Samples, und es ist nur derselbe Pfad belegt, nicht ein identischer Workload.

## Für PASS nötig
1. Zielklasse als Testentscheidung binden: Gerät, Displayrate, Auflösung, p95/p99/max-, Spitzen- und Speicherbudget. Dazu gehört die Owner-Freigabe der Fenstergröße.
2. Bei Zielauflösung neu messen, mit angegebenem VSync-Modus und CPU-/GPU-Zeiten.
3. Sichtbare Verspätung pro Frame messen (unbedeckte Frames, Zeit bis sichtbar).
4. Request-Alter und Upload-Bytes/-ms pro Frame auf dem Clipmap-Pfad messen und gegen konfigurierte Grenzen prüfen.
5. Den Mobile-Speicher-Unterlauf beheben.
6. Forward+ und Mobile mit belegter Parität vergleichen, mit mindestens 3 Läufen je Renderer, wechselnder Reihenfolge und erfasstem thermischem Zustand.
7. Rohdaten archivieren und danach erneut unabhängig reviewen.
