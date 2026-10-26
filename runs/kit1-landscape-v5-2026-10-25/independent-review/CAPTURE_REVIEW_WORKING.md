# Unabhängiger Videobefund und verbleibende Abnahme

25.10.2026; Prüfer `/root/independent_review`. Referenz Kit-1-v5, Daten
`landscape-v3`, Manifest `edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a`.
Keine eigene Anwendungssitzung gestartet oder bedient. Dieser Bericht ist ein
Arbeitsbefund vor den angeforderten Korrekturen, keine abschließende Freigabe.

## Tatsächlich betrachteter Aufnahmebestand

`artifacts/runtime/final-mobile-capture/zoom-tour.mp4` mit ffprobe vollständig
demuxt: 1920×1080, **241 dekodierbare Frames, 47.92 s**, reale variable
Capturezeitpunkte. Alle 241 Videoframes als neun externe Kontaktseiten unter
`capture-contact/` betrachtet; zusätzlich zahlreiche Original-PNGs bei voller
Auflösung und zwei separat aus dem Film dekodierte Frames geöffnet.
Rezept für die reine externe Kontaktansicht:

```sh
ffmpeg -hide_banner -loglevel error -i artifacts/runtime/final-mobile-capture/zoom-tour.mp4 -vf 'scale=320:180,tile=6x5' -fps_mode vfr runs/kit1-landscape-v5-2026-10-25/independent-review/capture-contact/contact-%02d.png
```

Das ist eine dichte statische Prüfung sämtlicher Filmframes samt Zeit-/Rohdaten,
kein vorgetäuschtes direktes Live-Erlebnis sämtlicher gerenderter GPU-Frames.
Der Film zeigt flachen Gesamtüberblick, wirkliche Zwischenzustände, eine räumliche
Wald-Nahansicht, England-Pan und Rückfahrt. Keine sichtbare GUI, Gebäude, Straßen,
politischen Flächen oder Auswahl-/Themenansicht wurden in diesem Bestand erkannt.
Kein leerer schwarzer Anwendungsframe wurde erkannt. Die schwarzen Restfelder
der letzten Kontaktseite sind ausschließlich unbesetzte Kontaktbogenplätze.

Der Readback/PNG-Encoder auf dem Hauptthread belastet diesen Capturelauf stark:
eigene Berechnung aus sämtlichen Rohintervallen p95 **428.132 ms**, p99
**501.556 ms**, max **620.46 ms**. Der Film ist dadurch sichtbar grob zeitlich
abgetastet. Diese Werte sind Capturelast, keine normale App-Leistung. Umgekehrt
dürfen bessere ältere normale Werte nicht als Leistung dieses endgültigen
Capturebuilds ausgegeben werden. Grafikowner erstellt einen begrenzten
Worker-Capturepfad und neue normale Vergleichsläufe.

Unabhängige Rawanalyse `final-mobile-capture-review.json`:

- 972 Anker-/Tilebeobachtungen, 0 Tile-ID-Abweichungen.
- Sichtbarer Scalar-gegen-Camera3D-Projektionsrest maximal **0.538048 px**.
- Source→Render-Screenrest gegen unabhängig direkt gesampeltes signed
  Detailhöhenfeld maximal **0.655989 px**; unter dem vorab gebundenen A16-
  Screenbudget 2 px in dieser begrenzten Stichprobe.
- Bewegung-bereinigte Änderung des beobachtet-minus-erwartet-Residuums maximal
  **0.513992 px** in aufeinanderfolgenden sichtbaren Telemetriesamples. Größter
  zugehöriger Sampleabstand 2582 ms: kein vollständiger Frame-/LOD-Nachweis.
- Godot-GPUmonitor maximal **799244288 Byte**; externes `ps`-RSS maximal
  **1964654592 Byte**. Integritätsstatus true. Dies sind tatsächlich erhobene
  Monitor-/Stichprobenwerte, keine globale Speicherspitzenobergrenze.
- Anfang und letzter Telemetriezustand: Zoom 0, Zentrum 17.5000019°/39.5°,
  Relief 0, Viewport 1920×1080. Letztes aufgenommenes PNG liegt noch bei
  Zoom 0.003887; ein expliziter finaler Frame des exakten Rückkehrzustands wäre
  der stärkere A04/A14-Bildbeleg.

**Formale A05-Grenze:** Die frühere Konfiguration ließ Mappingtoleranz offen.
Die neuen vor einem künftigen Run prospektiv gebundenen 1 px sind separat von
A16 zu behandeln und gelten nicht rückwirkend für diesen Film. Aktuelle
Thresholddatei laut Operations SHA-256
`7cd7613eaa9f29c125c0792d1631f3296ab62f609b615ed80b4d2d03f7287ee8`,
Konfig `ad37ef252b3a804b8af6339bc5b131b8a9a8ca9337dad958e7fdaae30d9f14e2`.
Fixture-/Wegpunkt-/Sollmethodenhash müssen vor dem neuen Run hinzukommen.

## Konkrete echte Bildfehler — Owner informiert

**V01 — Bäume stehen im dargestellten See.** Original
`artifacts/runtime/final-mobile-capture/frame_000229.png`, **28.026542 s**, Zoom
0.9649188421, Kamerazentrum **8.8012456894°/46.1301574707°**. Das voll geöffnete
1920×1080-PNG zeigt im oberen/rechten blauen Seebereich zahlreiche deutlich
freistehende Baumstämme/-kronen. Der Code gibt Bäume anhand des gröberen
kanonischen `waters[index]` frei, während die sichtbare Wasserfläche aus der
feineren Maske stammt. A07/A08/A09: Wasser und Vegetation widersprechen sich
sichtbar in derselben Szene. Gezielter Fix: Baumkandidaten zusätzlich nur bei
diskreter tatsächlicher Detailwasserart 0 zulassen. Keine Änderung der
kanonischen Geografie erforderlich. Exakt diese Position danach erneut prüfen.

**V02 — grobe Rastertreppen und Farbbänder an der Küste.** Original
`frame_000334.png`, **32.731156 s**, Zoom 0.7173075789, Zentrum
**1.0968509912°/51.0591201782°**. Die tatsächliche England-Küstenaufnahme zeigt
lange achsenparallele Treppenabschnitte mit mehreren diskreten Wasserfarbbändern
über große Bildschirmflächen. Das ist eine sichtbare Repräsentation der
ungefähr 600-m-Wasserrasterzellen und keine natürliche facettierte Küstenkontur
gemäß Primärreferenz. A08/A09 bleiben damit in diesem Pfad nicht bestanden.
Der Daten-Küstenfehler unter 6000 m ist keine automatische Erlaubnis für einen
beliebig großen Bildschirmfehler im Nah-/Zwischenzoom. Grafikowner untersucht
eine quellsegmentgebundene Distanzdarstellung; unabhängige neue Geometrie-/
Encoding-/Bildgegenprobe erforderlich, keine erfundene Küstenform.

**V03 — sichtbare Patchlinien.** `frame_000205.png`, `frame_000206.png` und
`frame_000231.png` bei voller Auflösung zeigen lange dünne achsenparallele
Linien beziehungsweise Helligkeitsstufen im Terrain. Die erste Nah-Stilprobe
zeigte bereits eine Linie um x=536. A09 verlangt unauffällige Nähte; dies ist
kein behauptetes logisches Tile-Overlay, aber ein sichtbares Darstellungsproblem.
Ursache vor Reparatur im tatsächlichen Patch-/Skirt-/Normalpfad eingrenzen.
Eine reine Farbpräferenz ist dieser Befund nicht.

Keine weiteren Stilvarianten sind verlangt. Die neue Baumfamilien-/Gruppenwirkung
ist sichtbar verbessert; die oben genannten Wasser-/Nahtfehler verhindern den
vollständigen A08/A09-Pass dieses Builds.

## A01–A16: aktueller ehrlicher Einzelstand

| ID | Stand dieses Prüfzeitpunkts | Konkreter verbleibender Beleg |
|---|---|---|
| A01 | Anwendung real gestartet, GPU-/Tourläufe vorhanden; unabhängige direkte Eingabe offen | Nach expliziter Sitzungseigentumsübergabe selbst starten, tatsächlich ziehen/zoomen, Eingabelog und Framebuffer sichern. |
| A02 | Unabhängige Referenz-/Masken-/Quellen-/Coverage-Teilprüfung validiert; echte gesamte Übersicht betrachtet | Finales Paket/Runbindung und gezielte regionale Rand-/Küstenbeobachtungen derselben Revision bestätigen. Keine weltweite Prüfung nötig. |
| A03 | Tatsächlicher 90°/Relief-0-Fernpunkt, Zwischenzustände und 35.264°/Relief-1-Nahpunkt beobachtet; Kamerafehler gezielt behoben | Aktuelle finale Basis-/Profilbindung im neuen vollständigen Run erneut prüfen. |
| A04 | Ungeschnittener 47.92-s-Film zeigt vollständigen Weg, zeitliche Capturelast erheblich | Neuer flüssigerer Capture mit korrekten Originalzeitpunkten und explizitem exaktem Rückkehrframe. |
| A05 | Gute numerische Teilbefunde, formale prospektive 1-px-Abnahme noch offen | Vorab gefrorene Fixture/Wegpunkte/Sollmethode/Viewport/Kamera und neuer Run; kein rückwirkender Grenzwertpass. |
| A06 | Gemeinsamer Scale 0.001, signed Höhen, Projektion und zusätzlicher RG8-Fehler unabhängig geprüft | Finale zusätzliche Rendertransformationen (neue Küste) separat binden; keine Höhenerfindung. |
| A07 | 500-m-Nahausschnitt, einzelne Bäume und Gelände lesbar; Wasserfall V01 fehlerhaft | V01 an exakter Position reparieren und tatsächlich betrachten. |
| A08 | Waldgruppen/Kronen verbessert; V01/V02/V03 verhindern vollständigen Pass | Gezielte neue Originalbilder dieser Fehlerzustände und abschließender Vergleich gegen Primärreferenz. Nutzerstilbewertung bleibt getrennt. |
| A09 | Kein leerer Aufnahmeframe erkannt; unauffällige Übergänge nicht vollständig belegt, echte sichtbare Fehler | V01/V02/V03 beheben; gleiche Tour langsam/schnell/hin/zurück, Cachezustand ehrlich markieren, Pipeline-/Frame-/Capturekorrelation. |
| A10 | Geöffnete normalen Bilder ohne GUI/Städte/Straßen/Politik/Rastermodus; Klassenbehandlung dokumentiert | Finalen korrigierten Bildsatz prüfen; kein sichtbares Hilfsraster zur Abnahme hinzufügen. |
| A11 | Sommer-/Lichtparameter fest; grüne, trockene und Gebirgsregionen unterscheidbar | Finale Revision/vergleichbare regionale Bilder binden; keine historische Vegetationsgenauigkeit behaupten. |
| A12 | Frühere normale Tour gut, dieser Capture stark belastet; finaler gleicher Buildvergleich offen | Mobile und Forward+ gleicher neuer Build/Daten/Route/Viewport ohne PNG, externes RSS und GPUmonitor, alle Intervalle; Cache-/Upload-/GPUzeitlücken explizit. |
| A13 | Reale versionierte Quellen/Hashes/Attributions-/Genauigkeitsangaben weitgehend geprüft | AWMC genauer Originaldatei-Abrufpfad in Reproduktionsnotiz ergänzen; keine bloße Repository-Tree-URL als Dateirezept ausgeben. |
| A14 | Deterministischer Seed/Quelle/Adressierung implementiert; gleicher Überblickszustand numerisch erreicht | Neues tatsächliches Wiederbesuchs-/Rückkehrbild bei exakt gleichem Zustand vergleichen; Originale behalten. |
| A15 | Neun unabhängige Soll-IDs und 972 übereinstimmende echte Runtimebeobachtungen | Formale Fixture mit Binnen/Küste/Rand/Naht und zeitlich neuen Pan-/Rückkehrprobes binden; tatsächliche Zellmaße/Indizes vollständig exportieren. |
| A16 | Umfangreiche unabhängige Offlineprüfung und RG8-Gegenprobe; v2-Fehler gezielt in v3 behoben, aktuelle Samples begrenzt | Neue Küstenableitung plus echte Mesh-/Morph-/Ridge-/Seam- und Zwischenframebelege; kein Gesamtnachweis durch Rasterfehler oder Camera3D-CPUprobes allein. |

## Konkrete noch notwendige Prüfaufträge

1. **Grafikowner:** V01/V02/V03 mit denselben geografischen Zuständen beheben.
   Quell- und Renderrepräsentationsrevisionen/hashgebundene zusätzliche Budgets
   vor neuer Messung festlegen; Datenowner prüft neue Küstendarstellung gegen
   tatsächliche Quellsegmente. Aufnahmen nicht überschreiben.
2. **Grafik/Capture:** finalen Build einfrieren und Kamera-/Viewport-/Mapping-/
   Renderencoding-/Fixturehashes vor neuen Läufen sichern. Normal Mobile und
   Forward+, Capturelast separat, kurze schnelle Hin-/Rückfahrt sowie ein
   Wiederbesuch. Warm/Kalt nur behaupten, wenn Cachezustand tatsächlich
   kontrolliert/benannt wurde; OS-/Treiber-Caches sonst als unbekannt markieren.
3. **A16 Ridge:** die sechs bereits quellgebundenen Ridge-/Massifanker als
   nichtleeren Bestand wirklich prüfen: Quellfenster/Höhenextrema, zugehörige
   tatsächlich erzeugte Mesh-/Morphhöhe und Pixelrest in mehreren Zoomständen,
   beabsichtigte Reduktion/unerwarteten Verlust einzeln melden. Das ist keine
   zertifizierte globale Kammnetz-Topologie; den beschränkten Umfang benennen.
4. **A16 Nähte:** an vorher gewählten tatsächlichen Patchnachbarn mit
   unterschiedlichen Detailstufen korrespondierende Randpositionen/Höhen und
   Morphgewichte paarweise messen. Erwartete gemeinsame Quelladresse,
   tatsächliche Abweichung, Zoom, Kamera und betroffene Patch-IDs protokollieren;
   danach wirkliche Bilder auf Risse/Skirtlinien prüfen. Die Existenz nur eines
   globalen Quellrasters beweist keine rissfreie gerenderte Naht.
5. **Übergangsresiduen:** erwartete kontinuierliche Bewegung abziehen, keine
   legitime Kamerabewegung als Sprung zählen. Bisherige mehrere Sekunden
   auseinanderliegende Captureprobes reichen für schnelle Wechsel nicht;
   gezielte dichtere Rohbeobachtung an LOD-/Wald-/Küstenübergängen verwenden.
6. **Unabhängiger Prüfer nach Sitzungshandoff:** echte Eingabe und gezielte
   Rand/Küste/Naht-/Wiederbesuchsproben selbst fahren, aktuelle Bilder/Movie
   öffnen, Rohwerte/Hashes erneut gegen den eingefrorenen Stand bewerten und
   die Matrix erst dann abschließend aktualisieren.
