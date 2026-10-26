# Grafik-/Integrationsauftrag

Referenz: kit1-landscape-v5 / kit1-ops-v5 / kit1-rendering-v4. Status: implementiert (Auftragsbindung), Produktprüfung offen.

Owner: graphics_owner, alleiniger App-/Renderer-Sitzungsdriver bis ausdrücklicher Übergabe. Autorisierung: vollständiger Kit-1-Startauftrag über Koordinator. Besitz: app/, scripts/run-landscape, scripts/build-landscape, docs/product-renderer/. Keine Datenpipelineänderungen. Eingaben: Kit-Pflichtlektüre, tatsächlich gesichtete Primärreferenz, versioniertes Paket des data_owner. Ausgaben: startbare Godot-Anwendung mit einer natürlichen Landschaftsansicht, Pan/Zoom, versionierte Projektion/Kamera, externe Runtimeprobes/Frame-Captures, reproduzierbare Befehle. Keine GUI, Raster, zusätzlichen Modi, Städte, Rotation oder Wirtschaft. Prüfung: echte Runtime, Gesamtübersicht-Nah-Rückfahrt, Forward+/Mobile und unabhängige Bild-/Datenprüfung nach eingefrorenem Build.

Technik: vorhandene Godot 4.7.2.stable.custom_build.ed1daf0bf. Erhöhte Bearbeitungstiefe für kritische Renderer-/Daten-/Captureintegration begründet; kein Modellpreis behauptet. Kosten: nicht erhoben.
