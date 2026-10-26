# Daten-Auftrag

- Ergebnis: reales, reproduzierbares Kit-1-Datenprodukt für die volle Region; `kit1-landscape-v5`, `kit1-ops-v5`, `kit1-rendering-v4`.
- Eingaben: AGENTS.md, START_PROMPT und Kit-Pflichtlektüre/REGION/DATA_PIPELINE/GENERALIZATION/TILES/RENDERING/GEODATA_METHODS gelesen. Ausdrücklicher Nutzerstart ersetzt alte Nichtstart-Statusangaben.
- Besitz: ausschließlich data/, tools/data*.py, docs/product-data/. Grafikowner besitzt App und Sitzung. Kein Kit wird verändert.
- Grenzen: keine erfundene Landschaft, keine Originalspiel-Parität, keine historischen 180er-Behauptungen. Keine globalen Installationen, keine Pushes.
- Übergabe: `data/derived/landscape.json`, Float32LE-Höhenmeter, WorldCover-Byteklassen, Byte-Wasser, separate Quellen/Masken/Projektion/Adressierung und Qualitätsnachweise.
- Prüfung: Quellhashes, tatsächliche Geometriecontainment, Raster-NoData/Inventar, deterministische Ableitung, gemessene Stichproben, unabhängige Prüfung durch anderen Owner.
- Modell: leistungsfähiges aktuelles Coding-Modell/high wegen regionaler GIS-/Provenienz-/Topologierisiken begründet; keine Preisaussage.
