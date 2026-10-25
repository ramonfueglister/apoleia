# Unabhängiger Paketstart und reale Eingabe

Referenz: kit1-landscape-v5 / kit1-rendering-v4. Status: Teilprüfungen validiert,
Panprüfung offen. Geprüftes Bundle: `artifacts/Roma Aeterna.app`, Rendererquelle
`59a926c8e09fdc0a391a829cf727003834c421ee1b79ff884d07735e0a31fe70`.
Kein Produktedit durch den Prüfer.

Das Bundle wurde zweimal über die native CUA-Appauswahl tatsächlich gestartet.
Es zeigt eine Metal-Landschaft in einem 1440×810-Inhaltsviewport. Ein zusätzlich
installiertes Godot/Python wurde für diese Starts nicht aufgerufen. Das Fenster
wurde jeweils mit seinem echten AX-Schließenknopf kontrolliert geschlossen;
die Anwendung schrieb ihre tatsächliche Runtime-Telemetrie. Die Rohdateien
bleiben unter `interactive-first/runtime.json` und
`interactive-wheel/runtime.json` erhalten.

In Sitzung 2 wurden explizit 30 native CUA-Wheel-Up- und anschließend 30
Wheel-Down-Aktionen ausgeführt. Der Framebuffer zeigte erst die Übersicht,
dann den Nahblick auf das Meer am unveränderten Standardziel und danach wieder
die Übersicht. Die Telemetrie enthält 120 MouseButton-Ereignisse. Beobachteter
Zoom: 0 → 0.9999999999999997 → 2.3059374371264266e-57; Ziel unverändert
17.500001907348633°E / 39.5°N. Das ist ein realer Zoom-/Rückkehrnachweis,
keine automatisierte Prüftour.

Pan ist damit **nicht** unabhängig abgenommen. Zwei native CUA-Drags in Sitzung
1 führten zu keiner sichtbar zugeordneten Verschiebung; ihre Press-/Releasepaare
lagen jeweils im selben Prozessframe. Die dokumentierte CUA-Drag-API bietet
keine Haltedauer. Horizontale Scroll-right/left-Aktionen in Sitzung 2 erzeugten
ebenfalls keinen sichtbaren Pan. Der alte Produktlogger zeichnete MouseMotion
nur bei button_mask!=0 auf. Fehlende Motionzeilen sind deshalb kein Nachweis
fehlender MouseMotion. Der Produktcode ist auf maskierte Bewegung angewiesen;
ob Toolereignisfolge oder Produktbehandlung ursächlich ist, bleibt bis zur
vollständigen Diagnostik offen.

In Sitzung 1 existieren außerdem 214 PanGesture- und 196 MagnifyGesture-
Ereignisse vor den expliziten CUA-Drags. Deren Ursprung ist nicht nachgewiesen.
Sie werden keinem Tool, Menschen oder automatischen Pfad zugeschrieben und
ersetzen den fehlenden unabhängigen Panbeleg nicht.

Nach Sitzung 2 wurde der alleinige Driver explizit an Koordinator/Grafikowner
zurückgegeben. Beide Prüfer-Appinstanzen sind geschlossen. Angefordert wurde
gezielte Diagnose aller Motionmasken/relative sowie Buttonindex/pressed,
keine ungeprüfte Produktänderung.

Das 76-Dateien-Inventar aus `docs/product-renderer/package-evidence/` wurde
gegen das tatsächlich gestartete Bundle erneut gehasht: 0 Abweichungen. Darin
sind Enginebinary, Engine-Lizenz/Notices (112876 Bytes), Quellenmanifest,
abgeleitete Daten, AWMC-Dateipfadaddendum, Skalierungs-/Genauigkeitsgrenzen und
Startanleitung enthalten. Das Paket ist als lokaler unsignierter Mac-Build
bezeichnet; daraus folgt kein Windows-/Linux-/iPad- oder Verteilungsnachweis.
