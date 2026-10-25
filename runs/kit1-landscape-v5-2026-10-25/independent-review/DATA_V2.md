# Unabhängige Datenprüfung landscape-v2

Referenz `kit1-landscape-v5` / `kit1-ops-v5` / `kit1-rendering-v4`, 25.10.2026.
Prüfer `/root/independent_review`; Produktdateien unverändert. Keine Anwendung
gestartet, keine GPU-/Sitzungsbedienung. `docs/product-data/HANDOFF.md` und der
Operations-Exportstatus gelesen. Renderer war während dieser Prüfung noch in Arbeit.

## Tatsächlich unabhängig ausgeführt

```sh
PROJ_DATA=/opt/homebrew/share/proj /opt/homebrew/bin/python3.14 runs/kit1-landscape-v5-2026-10-25/independent-review/data_v2_check.py > runs/kit1-landscape-v5-2026-10-25/independent-review/data-v2-check.json
PROJ_DATA=/opt/homebrew/share/proj /opt/homebrew/bin/python3.14 runs/kit1-landscape-v5-2026-10-25/independent-review/v2_supplement.py > runs/kit1-landscape-v5-2026-10-25/independent-review/v2-supplement.json
```

Beide Skripte importieren weder Datenpipeline noch Renderer. Alle Messergebnisse
sind Offline-Datenbefunde und ersetzen keine tatsächliche Laufzeitprüfung.

- **271/271 gebundene Quelldateihashes stimmen**, einschließlich aller 15
  vollständig heruntergeladenen ETOPO-TIFFs und 249 eingefrorenen WorldCover-
  Overviewbeobachtungen. Für WorldCover bezieht sich der Hash ausdrücklich auf
  lokale Overviewbeobachtungen; der entfernte vollständige 10-m-COG ist nicht
  vollständig gehasht. Die tatsächliche gelieferte Auflösung wird korrekt als
  ungefähr 0.005338° statt 10 m beschrieben.
- **10/10 Manifest-Payloadhashes und Bytegrößen stimmen.** Die zehn Run-Exportdateien
  haben dieselben Hashes und sind in diesem Zustand dieselben Hardlink-Inodes.
  Hardlinks sind keine gegen spätere In-place-Schreibzugriffe isolierten Kopien;
  dieser Befund bindet deshalb die tatsächlich gemessenen Hashes, keine ewige
  Unveränderlichkeitsgarantie.
- **7.592.400 kanonische Zellen vollständig gezählt:** 0 nichtfinite Höhen,
  0 unbekannte Landcoverklassen auf der erklärten Landdomäne; 5.593.677 Landzellen,
  1.979.574 Ozeanzellen und 19.149 Binnensee-Zellen. **40.453 Landzellen haben
  negative Quellhöhen**; diese sind im v2-Payload erhalten.
- Eigene andere Stichprobe: **4.323 Original-TIFF-Pixel je Niveau**, alle 173
  Quellpixel plus die regionalen Höhenextrema je Quelldatei. Original-TIFFs direkt
  mit `ReadAsArray` gelesen, ohne Produkt-VRT, `Warp` oder Datumsumrechnung.
  Größte gemessene Abweichung: overview 1001.33417 m, canonical 683.57349 m,
  detail 4.62251e-10 m. Die TIFF-CRS-Metadaten nennen EGM2008; das Rezept verwendet
  explizit `-novshift`. Dies stützt die native Höhenbewahrung und erkennt keine
  verbleibende automatische Vertikalverschiebung im Detailpayload. Es ist keine
  Aussage über die ursprüngliche Messgenauigkeit von ETOPO.
- **168/168 tatsächlich gelieferte Flussgeometrien** sind topologisch gleich
  den unabhängig erneut aus Originalen geschnittenen Geometrien. Die Länge der
  symmetrischen Differenz ist bei allen exakt 0. Der Produktprüfer verwendet
  an dieser Stelle eine dimensionsfalsche Flächentoleranz für Linien; die
  unabhängige Längen-/Gleichheitsprüfung verhindert hier einen falschen Schluss.
- **Alle neun erwarteten Tile-IDs stimmen** mit der unabhängig berechneten
  sphärischen Projektion (Ursprung 19°E/41°N), `floor(z/1000), floor(x/1000)`
  und dem 1000-m-Quadratraster überein. Alle neun Landcoverklassen stimmen.
  Laufzeitidentität, Pan-/Rückkehr- und Randbeobachtung bleiben separat offen.
- Die 112 ursprünglichen AWMC-Geometrien bleiben am ursprünglichen Hash gebunden.
  Der separate Normalisierungsbestand wurde gegen erneutes `MakeValid` allein
  für ungültige Originalgeometrien geprüft. Ergebnisse stehen in
  `v2-supplement.json`; dies ist keine historische Korrektur.

## Tatsächlicher Budgetfehler

Die Rohdateien wurden selbst gelesen und die Maxima neu berechnet. Der jeweils
schlechteste Küstenpunkt wurde zusätzlich gegen die tatsächlichen Wasserraster
unabhängig erneut gemessen, mit derselben offen benannten lokalen Distanzmetrik.

| Niveau | Höhenmaximum aus 421.015 Rohsamples | Höhenbudget | Küstenmaximum aus 2.340 Rohsamples | Küstenbudget |
|---|---:|---:|---:|---:|
| overview | 1334.149432356 m | 2500 m | **6418.557150753 m** | **6000 m: verletzt** |
| canonical | 1065.568237305 m | 1800 m | 2797.252710681 m | 6000 m |
| detail | 1e-9 m nach CSV-Rundung | 1000 m | 2039.410125728 m | 6000 m |

Der overview-Fehler liegt bei **-5.459828°/57.099799°** im nördlichen Kontext.
Beleg: `data/derived/coast-overview.csv`, SHA-256
`646a97762de9adb47bd705d3021f703dd8a881a669d0428fdba7e1aac876b007`.
Das ist kein fehlender Laufzeitwert und keine historische Unsicherheit, sondern
ein tatsächlicher Verstoß der gelieferten Rasterableitung gegen ihr eigenes
vorab gebundenes Budget. Keine nachträgliche Budgetlockerung als Bestehen ausgeben.
Reparatur benötigt eine neue ausdrücklich benannte Datenrevision und erneute
betroffene Messung/Hashbindung, ohne die alte Ausgabe still zu überschreiben.

**Pfadabgrenzung:** Der aktuelle Renderer verwendet `water-detail.u8` bei allen
Zoomständen; `overview-water.u8` wird von diesem Renderer nicht geladen. Der
oben verletzte Budgetvergleich betrifft deshalb ein tatsächlich produziertes
und in A16 deklariertes Offline-Niveau, nicht einen nachgewiesenen sichtbaren
Küstenfehler der Anwendung. Für den aktuellen Renderwasserpfad ist der Detailwert
2039.410125728 m maßgeblich, der unter 6000 m liegt. Die sichtbare Shaderkante,
Filterung und ihre Bildschirmwirkung benötigen weiterhin Runtimeprüfung.

Das horizontale Budget ist genau 0 m; der tatsächliche numerische
Projektions-Roundtriprest beträgt 9.494415286548626e-10 m. Das ist erkennbare
Gleitkomma-Rundung, kein Hinweis auf beabsichtigte horizontale Geografieänderung.
Die gewählte numerische Messung kann den strikten Nullvergleich trotzdem nicht
als bestanden zertifizieren. Ein sauber getrennter numerischer Methodenvertrag
müsste vor einer neuen Messung festgelegt werden. Keine fehlende Dezimalstelle
oder gerundete Null als geometrischen Genauigkeitsnachweis verwenden.

Projektionsmaßstabsabweichung: größter deklarierter Stichprobenwert 0.42419729 bei
58°N (Ost-West-Faktor 1.42419729); unter dem vorab gesetzten Verhältnisbudget 0.5.
Die erhebliche Verzerrung ist dokumentiert, keine überall unverzerrte Karte.

## Metadatenkorrekturen und Wesentlichkeit

1. **`data/anchors.json`: `alpine-woodland-near.height_m` ist noch v1.** Deklariert
   633.613037109375 m; tatsächliches v2 `height.f32[719,1199]` ist
   **584.4168701171875 m**, Differenz 49.1961669921875 m. Die anderen acht
   gespeicherten kanonischen Ankerhöhen stimmen. Der Renderer sampelt aktuell
   reale Höhen und liest dieses Feld nicht als Geometrieinput; seine Landschaft
   wird dadurch nicht verändert. Das Feld darf aber nicht als v2-Sollhöhe oder
   Provenienzbeleg weiterverwendet werden. Gezielte nächste Datenkorrektur nötig.
2. **`data/transformations.json.revision` sagt `landscape-v1`.** Unabhängig sind
   alle **21 darin gebundenen Artefakthashes aktuell und korrekt**. Die falsche
   Revisionsbezeichnung ist eine Reproduktions-/Zuordnungslücke, kein Nachweis
   einer falschen Payloadableitung. Eine append-only Errata mit Dateihash,
   genauer Feldkorrektur und tatsächlich gemeinter v2-Ausgabe reicht zur
   vorläufigen Zuordnung; für neue Releases Rezept/Manifest gezielt korrigieren.
3. **`inventory.full_source_sha256` ist der VRT-Hash**, kein Hash sämtlicher
   zusammengefasster Original-TIFF-Bytes. Die 15 echten Originaldateihashes sind
   separat vorhanden und unabhängig bestätigt. Feld in append-only Errata als
   `source_vrt_sha256` identifizieren und auf das Quellinventar verweisen; im
   nächsten Release den Feldnamen korrigieren. Die aktuelle Bezeichnung darf
   nicht als Vollquellhash zitiert werden.

## Nachprüfung der frühen statischen Rendererbefunde

Die im JSON-Snapshot genannten Arbeitsdateihashes binden diese Quellprüfung;
sie sind noch kein final eingefrorener Rendererbuild.

- R01/R02/R03/R06: Code verwendet jetzt dieselbe projizierte 1000-m-Tileformel,
  Ursprung 19°E/41°N und `mapping-v1`; `target_height_model` wird exportiert;
  Coverindex ist `floor(u*width)` passend zur Pixelzentrumregistrierung.
- R09: Tatsächlich geladene Payloads haben Manifesthashes; `_read_relative`
  vergleicht vor Decode echte Dateihashes. Rootfehler führen zu fatalem Start;
  Detailfehler zu Quarantäne/Kanonikfallback und negativem Ergebnisstatus. Ein
  echter Fehlerpfadtest ist noch nicht ausgeführt.
- R05: Flusslade-/Meshcode existiert nun, quellgebunden und mit ausdrücklich
  symbolischer Breite. Sichtbare Lage, Kontinuität und Qualität bleiben Runtimeprüfung.
- R04: CPU erhält signierte Land-/Binnenhöhen. **Neuer Shaderfehler gemeldet:**
  `sample_height` rundete linear interpolierte Wasserklassen 0=Land, 1=Ozean,
  2=See. An einem Land-/Seerand entsteht dadurch scheinbar Klasse 1 und die
  Höhe wird auf Meeresspiegel 0 gesetzt. Semantische Klassifizierung muss
  diskret bleiben, getrennt vom geglätteten Wasserfarbverlauf. Owner behebt dies;
  unabhängiger Retest nach Freeze erforderlich.

## Verbleibende Abnahmegrenze

Quellenrollen, Lizenz-/Attributionsdeklarationen und getrennte historische
Korrekturen liegen vor; die lokale ODbL-Datei und geoBoundaries-Layermetadaten
passen zur deklarierten Herkunft. Dies ist keine pauschale Rechtsfreigabe.
Die fünf Schutzinseln besitzen belegte Innenpunktchecks; 168 kleine Komponenten
unter 10 km² sind als mögliche Rasterauslassungen konkret inventarisiert.
Das belegt nicht die vollständige Topologie aller Inselküsten. Ridge-/Nahtschutz
ist noch nicht durch vollständige gerenderte Geometrie-/Übergangsprobes geprüft.

A02 und A13 besitzen substanzielle unabhängige Offline-Teilbelege. **A16 bleibt
offen und hat zusätzlich den genannten tatsächlichen Küstenbudgetfehler.**
Fehlende Bildschirm-/Morph-/Übergangsmetriken werden nicht aus Rasterfehlern
erfunden. GPU-, Bild-, Stil-, Eingabe-, Zoomkontinuitäts- und Leistungsabnahme
stehen bis zur expliziten eingefrorenen Grafik-/Sitzungsübergabe aus.
