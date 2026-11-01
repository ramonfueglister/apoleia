# Verona – Steinbrücken und Uferanschlüsse

Status: validiert. [Prüfberichte und Spielbilder](../handover/verona-bridges/validation.md). Eigene römische Bautypen, keine archäologische Rekonstruktion.

## Beobachteter Stadtplan

Die acht vorhandenen Brückenparzellen bilden zwei Gruppen. Der nördliche Übergang liegt auf `(18459,6914..6917)` und verbindet die Strasse im Norden mit dem Tor im Süden. Der östliche Übergang liegt auf `(18460..18463,6920)`. Seine westliche Parzelle hat Verbindungen nach Westen, Norden und Osten; die nördliche Verbindung führt zum bestehenden Kreuzungstor. Die östlichste Parzelle hat nur eine Verbindung nach Westen. Sie endet vor einer Gebäudeparzelle. Es wird kein neuer Strassenausgang erfunden.

Alle acht Parzellen haben Strassenrang 1. Die bestehende Fahrbahn ist `2 × 0.12 × 0.25 / 0.0238 = 2.521008` Modellmeter breit. Eine Parzelle entspricht 10.504202 Modellmetern. Diese Werte stammen aus dem bestehenden Stadtatlas und Renderer. Längen und Höhen der neuen Bauteile verwenden gemeinsam `DIORAMA_KM_PER_M = 0.0238`.

## Ausgangsdarstellung

`CP_BRIDGE` zählte bisher zu den bebauten Terrassen. Der Renderer zeichnete einen massiven Gelände- und Terrassenkörper mit einer Strasse darauf, ohne eigenes Brückenmesh. Ein Bogenmodell allein würde deshalb keine freien Öffnungen ergeben. Die neue Darstellung muss die alten Körper ausschliesslich an den erfolgreich ersetzten Brücken entfernen und den Fluss darunter sichtbar halten. Atlas, Parzellencodes, Nachbarschaft und Simulation bleiben unverändert.

## Eigene Gestaltung

Steinbögen, Pfeiler, Brüstungen und Anschlüsse gehören zur bestehenden Materialfamilie der Häuser und Befestigungen. Öffnungen und Fahrbahn müssen in allen drei eigenen Detailstufen erhalten bleiben. Die T-Abzweigung und das geschlossene östliche Ende folgen dem vorhandenen Weggraphen.

## Gemessene Höhen und Zugänge

Die HDR-Eckentextur des laufenden Spiels ergibt bei `tile_km = 0.25` und `level_h = 0.15` am nördlichen Strassenanschluss eine Terrassenoberkante von 0.90595 Welt-km, am südlichen Tor 0.60595. Die vier bisherigen Brückenplatten liegen überwiegend auf 0.75595. Am östlichen Übergang liegen die westliche Strasse auf 0.45595 und das nördliche Tor auf 0.60595. Der vollständige Befund steht in [terrain-heights.json](../handover/verona-bridges/terrain-heights.json).

Diese Differenzen sind bereits im bisherigen Gelände vorhanden; eine Stufe von 0.15 Welt-km entspricht 6.302521 Modellmetern. Die neue Gestaltung muss deshalb Brückendeck und Zugänge anpassen. Sie darf keine durchgehend ebene Wagenfahrbahn behaupten: Insbesondere der südliche Abstieg der Nordbrücke und der nördliche Zugang am T-Abzweig benötigen Treppen. Dies sind grafische Fusszugänge; die Änderung definiert keine neue Verkehrssimulation. Fluss- und Geländehöhen werden dafür nicht abgesenkt oder abgeflacht.

## Umsetzung

Fünf Assets bilden neun Instanzen auf den acht Parzellen: `verona_bridge_span`, `verona_bridge_junction`, `verona_bridge_end`, `verona_bridge_stairs` und `verona_bridge_descent`. Der Generator `tools/buildings/build_verona_bridges.py` verwendet das unveränderte gemeinsame Asset-Kit. Jede GLB enthält drei eigene formbewahrende Detailstufen; zusätzliche automatische Godot-LODs sind deaktiviert. Die Metadaten beschreiben Ursprung, Achsen, Anschlussflächen und Stufenmasse.

Die normalen Abschnitte sind 10.504202 m lang und 4.4 m breit. Zwischen den Brüstungen bleiben 3.8 m frei, die bestehende Fahrbahn benötigt 2.521008 m. Eine Bogenöffnung hat 8.2 m Spannweite; ihre Krone liegt 1.1 m unter dem Deck. Die Pfeiler besitzen dreieckige Strombrecher. Die tatsächlich sichtbare lichte Höhe hängt vom unveränderten Gelände und Wasser ab; der niedrige T-Abzweig ist ein ufernahes Widerlager und keine freie Bootsdurchfahrt.

Die Laufzeitklasse `verona_bridges.gd` hält die Brücken getrennt von der bisherigen Gebäudeserie. Eine Gruppe wird erst nach vollständigem Laden und erfolgreicher Instanziierung aktiviert. In der nahen Darstellung entfällt dann ausschliesslich deren bisheriger Terrassenblock; auf der darunterliegenden unveränderten Geländeoberfläche gilt dieselbe Wasser-/Uferdarstellung wie bei den angrenzenden Wasserparzellen. Bei fehlenden Assets oder in der Ferne bleibt die alte Darstellung aktiv. Atlas, Höhentexturen und Simulation werden nicht beschrieben.

Die geneigten Abschnitte erhalten einen linearen Höhenversatz entlang ihrer Längsachse; Querschnitt und einheitlicher Massstab bleiben erhalten. Der Shader transformiert auch die Normalen passend zur Neigung. Die Treppen sind bereits mit waagerechten Tritten modelliert und erhalten keinen zusätzlichen Neigungsversatz. Die Brückendecks folgen diesen Anschlussprofilen in Welt-km:

| Gruppe | Anschlussgrenzen von Nord nach Süd bzw. West nach Ost |
|---|---|
| Nord | 0.90595, 0.86595, 0.82595, 0.80595, 0.60595 |
| Ost | 0.45595, 0.45595, 0.53595, 0.61595, 0.61595 |

Der nördliche Treppenzugang der Ostbrücke überwindet 6.302521 m mit 32 Steigungen und 33 Tritten. Die Auftritte sind wegen des vorhandenen kurzen Anschlusses nur rund 0.12 m tief: ausdrücklich ein sehr steiler Fusszugang. Der südliche Abstieg der Nordbrücke überwindet 8.403361 m mit 43 Steigungen und 44 Tritten von rund 0.239 m Tiefe. Beide behalten ihre Stufen in allen Detailstufen. Der östliche Abschluss besitzt eine querlaufende Brüstung, entsprechend dem fehlenden Ausgang im Atlas.
