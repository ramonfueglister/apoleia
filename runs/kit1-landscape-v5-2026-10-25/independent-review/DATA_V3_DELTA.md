# Unabhängige Delta-Prüfung landscape-v3

25.10.2026, `kit1-landscape-v5` / `kit1-ops-v5`; Prüfer `/root/independent_review`.
Keine Produktdateien geändert; keine GPU-/Anwendungssitzung gestartet.
Gezielter Delta gegenüber unabhängig geprüfter v2-Ausgabe, keine wiederholte
Quelldownloadprüfung. Ausführbares Rezept `data_v3_delta.py`, Rohbefunde
`data-v3-delta.json` im selben Ordner.

Geprüfter Manifesthash:
`edf5f18e00376c4b5545e27ec5ec8b4ecf8eb1e0ede53d938d77f50d695c562a`.

- Zehn Payloadhashes stimmen mit Manifest und Run-Export überein. Exakt ein
  Payload änderte sich gegenüber den tatsächlichen v2-Hashes:
  `overview-water.u8`, jetzt 4096×3072. Die neun anderen Payloads sind bytegleich.
  Insbesondere blieb die bei sämtlichen Zoomständen geladene 8192×6144-
  Detailwassermaske unverändert. Deren bisheriger Offline-Stichprobenbefund gilt
  deshalb weiter; neue sichtbare Küstenqualität wird dadurch nicht behauptet.
- Sämtliche Generalisierungsbudgets sind unverändert. Dieselben **2340
  Küstenkoordinaten in derselben Reihenfolge** wurden verwendet. Alle 2340
  Distanzen unabhängig gegen die tatsächliche neue Overviewmaske erneut
  berechnet: Maximum **2040.1333575209435 m**, 0 fehlende Werte, alle unter
  6000 m. Größte Differenz zur gerundeten Rohdatei 5e-10 m. Der frühere
  v2-Budgetfehler ist damit für diese neue Ausgabe behoben; v2 bleibt ein
  archivierter negativer Befund.
- Die neue explizite horizontale Metrik misst ausschließlich Positionsänderung
  durch die höhenbasierte Rastergeneralisierung. Die übergebenen Querykoordinaten
  ändern sich nicht; die 421.015 Rohpaare sind auch nach unabhängigem CSV-Lesen
  bitgleich, 0 nichtnullige Verschiebungen, Maximum ungerundet 0 m. Der Code
  resampelt nur die Höhenfunktion an den übergebenen Positionen und besitzt hier
  keinen horizontalen Verschiebungsoperator. Dies ist eine eng begrenzte
  Identitätseigenschaft, keine Messung tatsächlicher Meshvertex-, Float32-,
  Projektions- oder Bildschirmgenauigkeit. Der frühere Projektions-Roundtriprest
  bleibt mit unverändertem CSV-Hash separat erhalten und wird nicht in einen
  rückwirkenden v2-Pass umgedeutet.
- Die Alpen-Ankerhöhe passt nun exakt zum wirklichen kanonischen Payload:
  **584.4168701171875 m**. Journalrevision lautet `landscape-v3`; das irreführende
  `full_source_sha256`-Feld wurde entfernt. Der als `source_vrt_sha256`
  bezeichnete Wert stimmt tatsächlich mit dem VRT-Descriptor überein.

Die gezielten v2-Datenbefunde sind für v3 in diesem beschriebenen Umfang
**validiert behoben**. Quellen-/Daten-/Rasterbelege aus v2 dürfen nur für die
nachweislich unveränderten Bestandteile weitergelten. Gesamtes A16 bleibt bis
zu echten Screen-/Morph-/Übergangs- und Feature-/Nahtprobes **offen**; dieser
Bericht vergibt weder eine Runtime-, Leistungs-, Stil- noch Produktabnahme.
