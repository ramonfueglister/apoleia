# Unabhängige Prüfung der Verona-Brücken

Stand: 2026-11-01. Prüfung durch separaten QA-Agenten; keine Modell- oder
Runtime-Änderungen durch den Reviewer, kein eigener GPU-Lauf.

## Sichtprüfung

Geprüft wurden die zehn echten Spielaufnahmen in
`build/verona-bridges/final/`: Nordbrücke, nördlicher Uferanschluss,
Ostbrücke, Tor/T-Abzweig, Ostende und Stadtansichten bei 1.5, 5, 12, 24
und 60 km Kamerabreite.

In diesen Ansichten sind keine neuen sichtbaren Anschlusslücken,
schwebenden Pfeiler oder versehentlich verschlossenen Bögen erkennbar.
Brücken und Treppen passen hinsichtlich Steinpalette, Kantenbehandlung
und Maßstab zum bestehenden Stadtbild. Nordufer, modulare Brückenstücke
und Toranschluss bilden zusammenhängende Silhouetten. Die Brüstung am
Ostende schließt den laut Atlas nur westlich angeschlossenen Endpunkt
sichtbar ab; sie ist kein versehentlich blockierter Durchgang.

Die Ansichten bei 1.5 und 5 km zeigen die Bauteile und Kontakte ausreichend
groß. Bei 12 km bleiben die Brücken als zusammenhängende Formen lesbar.
24 und 60 km erlauben nur ein Urteil über Gesamtbild und Distanzdarstellung,
keine zuverlässige Prüfung einzelner Kontakte oder Trittflächen.

## Reale Geometrie und Runtime

`tools/tests/check_verona_bridge_assets.py` besteht für fünf GLBs und alle
15 nativen LODs ohne Fehler. Der CPU-Test liest tatsächliche exportierte
Dreiecke: Deckabdeckung, offene Bogenkanäle und Barrel, Durchgangsvolumen,
Brüstungen und Endbarriere, horizontale Trittfolgen, identische Ursprünge
und gemeinsamer Maßstab. Der statisch geneigte Bogen des Abstiegs wird für
den Öffnungstest mathematisch entzerrt.

Dabei wurden zwei konkrete Geometriefehler gefunden und durch den
Modellautor behoben: Ein schräger Treppenunterzug ragte durch die unteren
Tritte; außerdem lag der erste Treppenblock koplanar auf dem T-Deck.
Die finale Treppe hat 3764/756/468 Dreiecke. Der kombinierte Test von
Junction und Treppe bestätigt den eindeutig vom Junction-Deck getragenen
Z=0-Antritt, freie aktive EW-Fahrbahn von 2.521008 m und horizontale
Trittoberflächen in allen drei LODs. Bericht:
`build/verona-bridges/asset-validation.json`.

Beim Read-only-Review von Bridge-Manager, Piece, Bridge-Shader und den
lokalen Terrain-/Plinth-Masken wurden keine weiteren konkreten Fehler
gefunden. Das ist keine Laufzeitgarantie; atomare Aktivierung, Fallbacks
und tatsächliche Uferhöhen benötigen die separaten Runtime-Tests.

## Disposition und Grenzen

**Ship im geprüften Umfang; kein weiterer visueller Fixbedarf.** Nach dem
finalen Reimport wurden `gate-junction.png` und `north-bridge.png` erneut
geöffnet. Die finale T-Treppe steht zusammenhängend auf dem Junction-Deck;
am unteren Antritt ist kein zusätzlicher Block oder sichtbarer Spalt
erkennbar. Die Trittfolge und die seitlichen Einfassungen bleiben klar
lesbar. Der nördliche Abstieg, die offenen Bögen und sein Uferanschluss
zeigen ebenfalls keine neue sichtbare Regression. Die vier anderen
Assets waren gegenüber der zuerst geprüften Serie bytegleich.

Einzelbilder belegen kein flimmerfreies Verhalten in Bewegung, keine
Kollisions-/Pfadfindungsfunktion und keine Bildratenänderung. Die Prüfung
bewertet die vereinbarte Brückentypologie und bestehende Geländeform;
sie stellt keine archäologische Rekonstruktion fest.
