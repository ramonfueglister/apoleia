# Landschafts- und Vegetationsproduktion

Referenz `kit1-landscape-v5`. Dieses Rezept ersetzt Charakter-/Animations- und
Unity-Assetrezepte des Beispiels. Es produziert heute keine Modelle oder Bilder.

## Fester Stilanker

Maßgeblich ist die Nutzer-Primärreferenz in [STYLE_GUIDE](../references/STYLE_GUIDE.md):
stilisierte, nicht fotorealistische Landschaft; zurückhaltende natürliche Palette;
lesbare facettierte Formen, genügend Terrain- und Walddetail, natürliche Übergänge.
Nicht übermäßig bunt, extrem low-poly, voxelartig oder klotzig. Keine politische
Farbfläche oder globale mediterrane Vegetation. Sommer und Tageslicht bleiben fest.
Die ergänzende Fernstilprobe ist nachrangig zur Nutzerreferenz und kein Beleg für
den flachen 2D-Fernkartenendpunkt. Die neue Nahprobe wurde verworfen; die
Primärreferenz bleibt maßgeblich für den Nahstil.
Vor jeder späteren Stilprüfung
[den lokalen Screenshotkatalog](../references/screenshots/README.md) betrachten:
U01–U03 zeigen übertragbare Urbek-Formen.
Die jeweiligen Ausschlüsse mitlesen. Diese Spielbilder sind Referenzen, keine
Kit-1-Produktassets, Geodaten oder vollständigen Landschaftsvorlagen. Frühere
eigene generierte Stilproben sind aus dem Kit entfernt; die Nutzer-Primärreferenz
bestimmt den aktuellen Terrainstil.

## Späterer Durchlauf

1. Einen **geografisch gebundenen** Ausschnitt im tatsächlichen gebundenen
   flach-zu-Diorama Kameraverlauf prüfen: Gelände, Wasser, Vegetation. Vollständige regionale Zielabdeckung bleibt
   bestehen; Ausschnitt ist nur ein früher Integrationscheck.
2. Terrain auf klare Formen reduzieren. Vereinfachung gegen Quellgeografie prüfen;
   vereinfachte Kanten dürfen nicht unerklärt Küsten/Flussidentität verschieben.
3. Kleine eigene Baum-/Felsfamilien nach regionalem Erscheinungsbild definieren.
   Nah erkennbare Einzelbäume, weit ruhigere Flächen. Einheitliche Formensprache
   über alle Entfernungen; reale Größen und sichtbare Größen getrennt führen.
4. Vor Variantenserie eine repräsentative Form durch den tatsächlichen späteren
   Export-/Importpfad führen. Pivot, Achsen, Einheiten, Materialanzahl, Texturpfade
   und Silhouette prüfen. Kein besonderes Modellformat/Tool wird hier vorgegeben.
5. Reimport aus kopiertem isolierten Ordner prüfen, damit fehlende Materialien
   nicht durch alte absolute Pfade versteckt werden. Eingangs-/Ausgangshashes und
   Exportversion festhalten; Datenquelle ≠ erzeugtes Asset.
6. In echten Laufzeitbildern Gesamtübersicht/Mittel/Nah vergleichen. Material-/LOD-/Dichte-
   Budgets anhand Messung festlegen, nicht aus dem fremden MMO übernehmen.
7. Unabhängige Review anhand `templates/REVIEW.md`. Nutzerrückmeldung bleibt
   getrennt; kein Agent setzt selbst 'vom Nutzer bestätigt'.

## Optionaler späterer Bild-/Assetdienst

Nur wenn ein im gültigen Auftrag erlaubter Dienst konkret nützt. Prompt nennt
isometrischen Nahendpunkt des gebundenen Zoomprofils, stilisierte, ausreichend
detaillierte facettierte Landschaftsformen gemäß der Primärreferenz und **keine
neue Geografie**. Jede Ausgabe erhält Anbieter/Modellversion,
Prompt, Job-ID, Original-/gespeicherten Hash, Kosten soweit erhoben und Status.
Timeout → vorhandenen Job prüfen. Keine massenhaften Varianten oder stillen
Marktplatzimporte. Generierte Konzeptbilder sind keine Laufzeit-/Geografienachweise.

## Eine natürliche Ansicht, keine GUI

Kit 1 zeigt ausschließlich natürliche Landschaft ohne Rasterlinien, Tile-Highlights,
Themenfarben, Panels oder Bildschirmhilfen. Die unsichtbare quadratische Datenbasis
prägt nicht zwingend die Geländegeometrie. Die akzeptierten Bilder bleiben
Stilreferenzen; sie belegen weder reale Geografie, historische Geometrie, interne
Tile-Adressierung noch GUI-Funktionen. Eine echte Zoomkontinuität muss später durch
Laufzeitaufnahmen desselben Builds geprüft werden.

Facettierte Terrainformen werden aus realen Landschaftsdaten generalisiert.
Ihre Detaildichte folgt der Primärreferenz und ist kein Polygon-/Leistungsbudget. Vegetations-
modelle repräsentieren belegte Klassen/Verteilungen; ihre Einzelplatzierung ist
nicht als Einzelbaummessung auszugeben. Kein generativer Dienst liefert die
geografische Wahrheit. Feature-Schutz und Fehlerbudgets nach GENERALIZATION
haben Vorrang vor einer bloß attraktiven Silhouette.
