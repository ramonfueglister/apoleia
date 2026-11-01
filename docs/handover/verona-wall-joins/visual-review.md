# Unabhängiger Review der Mauer-/Turmanschlüsse

Stand: 1. November 2026. Separater QA-Agent; keine Produktionsänderungen
und kein eigener GPU-Lauf. Geprüft wurden die exportierten Dreiecke und
Roots echte Spielaufnahmen in `build/verona-wall-joins/{baseline,final}/`.

## Ergebnis

**Ship für die geometrische Korrektur und alle acht geprüften Knoten.**
Die ursprünglich in Turminnenräume laufenden Mauerarme und Torlinks sind
entfernt. Die neuen Endflächen schliessen an die vorgesehenen Fassaden an.
Es gibt in den geprüften Bildern keine neue sichtbare Anschlusslücke,
schwebende Mauer oder veränderte Turm-/Dachsilhouette. Die bestehenden
Torpassagen bleiben offen; Material und Massstab passen zum Bestand.

Die acht Knotenaufnahmen und die Übersicht wurden jeweils vor/nach dem
Fix verglichen. Besonders deutlich sind die bereinigten diagonalen
Anschlüsse bei 14,12 und 15,13 sowie die Turmanschlüsse bei 12,15 und
13,16. Die seitlichen Turmöffnungen enthalten dort keine durchlaufenden
Mauerflächen mehr. Die Übersicht zeigt die gleiche Stadtanordnung.

Die ursprüngliche Aufnahme `join-14-16.png` verdeckte den westlichen
Toranschluss durch die Arena. Diese Evidenzlücke ist mit der zusätzlichen
echten Spielaufnahme `final/join-14-16-reverse.png` geschlossen: Kamera
Yaw −135°, Pitch −65°, Breite 1.2 km, sämtliche Modelle weiterhin sichtbar.
Tor, kurzer Wandanschluss und benachbarter Turm sind darin frei einsehbar.
Der Anschluss ist geschlossen; kein durchlaufendes Stück im Turmfenster
und keine neue sichtbare Lücke. Der finale Report enthält zehn Ansichten.

## Unabhängiger Regressionstest

`tools/tests/check_verona_wall_tower_joins.py` verwendet den tatsächlich
installierten Graph aus dem Spielreport: 22 Instanzen, davon 14 Arme/Links
und acht Tower-/Gate-Kerne, über sieben unveränderte Kanten. Er prüft
vollständige Dreiecke gegen die reservierten Turm- und Pavilloninnenräume
mittels Triangle/AABB-Separating-Axis-Test; eine reine Prüfung der
Eckpunkte oder Kantenmitten würde nicht genügen.

Die Berechnung erfolgt in lokalen Modellmetern mit den tatsächlichen
HDR-Corner-Höhen des Spiels. Beide Geländeniveaus 0.60595 und 0.45595 km
und ihr Unterschied von 6.302521 m sind berücksichtigt. Zusätzlich
prüfen Querstrahlen die Graphanschlüsse auf beiden realen Geländehöhen.

- Archivierte Originalassets: **42 Innenraumbefunde**, alle 14 Arme/Links
  in allen drei LODs; derselbe Test reproduziert damit den gemeldeten Fehler.
- Finale Assets und finaler Spielreport: **588 Dreieck/Innenraum-Prüfungen
  und 48 Höhenanschluss-Rays, null Fehler**.
- Angepasster bestehender Fortifikationsvalidator: **acht Assets,
  495 Start-/Endflächen-Rays und 270 Torpassagen-Rays, null Fehler**.
  Die Schnittflächen werden pro Querposition aus den V-/Keilprofilen
  berechnet und weiterhin exakt geprüft. Nur die vorhandene 3-mm-Fase
  der äussersten V-Spitze erhält ein einseitiges Bounds-Spiel von 3.1 mm.

Berichte: `build/verona-wall-joins/baseline-join-validation.json`,
`build/verona-wall-joins/join-validation.json` und
`build/verona-fortifications/asset-validation.json`.

Einzelbilder belegen kein Verhalten in Bewegung und ersetzen keine
allgemeine Kollisions- oder Pfadfindungsprüfung. Verdeckte Innenräume
werden hier durch die Geometrieprüfung abgesichert. Der Review macht
keine Aussage über historische Rekonstruktion oder Bildratenänderungen.
