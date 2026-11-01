# Unabhängiger Review: Zinnenabstand zu Turmfassaden

1. November 2026. Dieser Review bewertet ausschliesslich den geforderten
Zinnenrücksprung. Die vorherige Innenraumprüfung hatte den sichtbaren
Kontakt zwischen Zinnen und Turmfassaden nicht erfasst.

## Sichtbefund

Die echten Spielaufnahmen `merlons-gate-diagonal.png` und
`merlons-tower-diagonal.png` wurden zwischen
`build/verona-wall-joins/merlon-before/` und `merlon-after/` direkt
verglichen. Die Kamera fokussiert jeweils die Mauerkrone; Modelle wurden
für diese Prüfung nicht ausgeblendet.

Am diagonalen Toranschluss ist der vorher unmittelbar an der Fassade
liegende breite, angeschnittene Zinnenblock entfernt. Zwischen der
verbleibenden vollständigen Zinne und dem Pavillon ist jetzt ein klar
sichtbarer Abschnitt niedriger Brustwehr frei. Auch am diagonalen
Turmanschluss ist die hohe Zinne von der Fassade zurückgenommen; die
niedrige Brustwehr bleibt am Turm angeschlossen. In diesen Ausschnitten
ist keine neue Lücke im darunterliegenden Mauerkörper erkennbar.

**Ergebnis: Der geforderte sichtbare Zinnenrücksprung ist in den geprüften
Nahansichten belegt.** Dieses Urteil umfasst keine allgemeine Abnahme
der gesamten Turmarchitektur. Einzelbilder prüfen zudem kein Flimmern
in Bewegung.

## Geometrischer Nachweis

Der neue unabhängige Test
`tools/tests/check_verona_merlon_clearance.py` liest die tatsächlichen
GLB-Dreiecke aller acht Assets und drei LODs. Er rekonstruiert zusammenhängende
Körper und Kappen anhand ihrer realen Scheitelpunkte und Höhen. Dadurch
werden auch die direkt in den beiden Tor-GLBs modellierten Zinnen geprüft.
Metadaten über Zinnenabstände gelten nicht als Prüfergebnis.

Geprüft werden vollständige Körper/Kappen mit 0.66 × 0.34 m Grundfläche,
zusammengehörige Körper-/Kappenpaare und ungeschnittene Quader- bzw.
Fasengeometrie. Die tatsächlichen Dreiecke oberhalb 7.05 m müssen ausserhalb
der um 0.60 m erweiterten Turmaussenkörper liegen. Die Aussenkörper
schliessen das 0.07 m vorstehende Ecksteinrelief ein. Die Erweiterung ist
an diagonalen Ecken konservativ. Der aktuelle Spielreport liefert
Instanzen, Drehungen und die realen Geländeversätze.

Die archivierten Original-GLBs reproduzieren 18 Abstandsverletzungen:
sechs diagonale Instanzen in jeweils drei LODs. Zusätzlich erkennt der
Test angeschnittene Zinnengeometrie, darunter den verkürzten Körper und
Deckstein des normalen diagonalen Torlinks. Gate-eigene Zinnen bestehen
die Abstandsprüfung bereits im Originalbestand.

Die finale Geometrie besteht **546 Dreieck-/Abstandsvolumenprüfungen,
darunter 30 für gate-eigene Zinnen, ohne Fehler**. Die Vollständigkeits-
und Körper-/Kappenprüfungen bestehen ebenfalls. Der Bericht referenziert
den aktuellen `merlon-after/report.json` inklusive SHA256.

Nachweise: `build/verona-merlon-clearance/baseline-assets/sha256.json`,
`baseline-validation.json` und `merlon-validation.json` im selben
Verzeichnis. Der Reviewer änderte keine Produktionsdateien und führte
keinen GPU-Lauf aus.
