# Kamera-/Integrationsauftrag

Referenz `kit1-landscape-v5`, korrigierter `astra-replan-v2`, 2026-10-25.
Status `implementiert` als laufender Entwicklungsstand; Laufzeitabnahme offen.
Owner `/root/camera_integration_v2`: `app/project.godot`, zentrale Scene,
`app/scripts/landscape.gd`, `landscape_camera.gd`, Kamera-/Runtime-/Pakettools.
Alleiniger GPU-/UI-Driver; andere Owner bearbeiten Modell und Stil separat.

Vertrag: eqc41-Projektion/Skalierung unverändert, Kern [-11,21,46,58].
Finaler Kontextbedarf [-44,18,79,61], reale Quellen erforderlich. Ganze Kernregion
bei fernster Kamera mit 4% Reserve; Panfreiheit öffnet sich mit 1-width/far_width.
Viewport füllt native Fensterfläche. Zielklammer enthält gesamten konservativen
Bodenfootprint über [-1000,9000] Quellmeter, keine geografische Füllfläche.
Logarithmische Breitenanker: 1500km/90°, 200km/65°,20km/45°,5km/35.2643897°.
Relief unabhängig 0/.45/.88/1; C1-smoothstep in Logbreite; kanonische Höhen fest.
Rad Faktor1.18, kritisch gedämpft95%/250ms. Bodenanker folgt Renderterrain;
Randklammer darf Anker lösen und wird extern protokolliert. Keine Drehung/GUI.

Nächster Meilenstein: Mathematik-/Ereignistests, Kontext-/Modellformathandshake,
echte Stilfensterbilder und Kamera-/Aspectfahrt in derselben App.

2026-10-25 Implementierungscheckpoint: Kameramodul und Integration geschrieben.
Godot4.7.2 headless echte Camera3D-Projektions-/Rayprüfung:96 Fälle über4 Aspects,
8 Breiten und3 Bodenanker, schwieriger realer Modellkoordinatenbereich(2265,2223).
Maximal0.614367px Anker-/0.509461px Pickingrest, <1px vorab geforderte Grenze.
Dämpfung nach250ms0.9500004, variable Zeitschritte äquivalent.10.001 Profilproben
monoton. Das ist Kameramathematikprüfung mit Testheightfield, kein Bild-/Stilpass.
Alter Positionsfallbacktest bestanden. Keine GPU-Appinstanz war gestartet
(Prozessprüfung); daher keine Nutzerinstanz geschlossen. Neue Nutzeranlage
betrachtet, SHA256 bf91d62e914b57d526aa5e49543495464d8f3ae75ef344033ff54d7dafd8e5ea,
byteidentisch zur Kit-Primärreferenz. Voller Kontext und neue Modellprodukte
stehen noch aus; Legacydaten werden ausdrücklich als unzureichend telemetriert.
