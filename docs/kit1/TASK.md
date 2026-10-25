# Kit 1 — vollständiger späterer Bauauftrag (WHAT)

**Referenzversion:** `kit1-landscape-v5` · **Status:** `spezifiziert`.  
**Ausführungsstand:** nicht gestartet. Diese Spezifikation ist kein Startsignal.

**Geografischer Umfang v5:** ein zusammenhängender Ausschnitt nach dem Bezugsrahmen
des Römischen Reiches bei seiner größten Ausdehnung unter Trajan um **117 n. Chr.**,
mit dem **gesamten Mittelmeerraum**, angrenzendem Land-/Meerkontext sowie ausdrücklich
**England und zusätzlichem Raum nördlich davon**. Die Kartenmaske endet nicht hart
an Reichsgrenzen. Britannien, Gallien, Iberien, Donauraum/Dakien, Nordafrika und die
östlichen Reichsgebiete sind nach der belegten Abgrenzung einzubeziehen; keine
bloße Mittelmeerküsten-Demo. Weder nur Europa/EU noch die gesamte Erde sind beauftragt.
Die Landschaftsreferenz bleibt **180 n. Chr.**, heutige Geodaten bleiben die Basis.
Der 117er Bezugsrahmen legt den Ausschnitt fest, keinen neuen Spielstartzeitpunkt.
Exakte Grenzen, Meerkontext und nördliche Pufferbreite werden vor Umsetzung aus
Quellen begründet und in `region.json` gebunden, nicht hier als Tilezahl/Skala erfunden.
Details: [REGION](operations/REGION.md).

## Ziel und sichtbarer Gesamtpfad

Baue nach dem späteren Nutzerstart eine lokal startbare Landschaftsansicht der
gesamten Projektregion. Die Welt ist eine durchgehend zusammenhängende, stilisierte
verkleinerte Modelllandschaft auf Grundlage realer Geodaten. Ganz herausgezoomt
erscheint sie als flache 2D-Karte; beim Zoomen geht sie kontinuierlich in eine
räumliche isometrische Diorama-Nahansicht über. Kamera, Projektion und Relief
folgen einem dokumentierten Zoomprofil, ohne freie Rotation, Umschalttaste oder
Szenenwechsel. Die Nahansicht kann später mehrere Häuser samt Umgebung zeigen;
die aktuelle Landschaft bleibt unbebaut.

Der vollständige prüfbare Pfad lautet:

1. Anwendung starten und die gesamte Projektregion überblicken.
2. Zu einem beliebigen Teil des Projektgebiets verschieben und kontinuierlich hineinzoomen.
3. Dieselben Küsten, Höhenzüge und Wasserläufe über alle Entfernungen verfolgen.
4. Im Nahbereich Gelände, Wasser und einzelne stilisierte Bäume erkennen.
5. Wieder herauszoomen, einen anderen Teil des Projektgebiets wählen und denselben Pfad nutzen.
6. Unsichtbare Tile-Zuordnung intern beim Pan/Zoom und erneuten Besuch prüfen;
   Kartenränder, Küsten und Tile-Nähte berücksichtigen. Dafür kein Raster anzeigen.

Eine Bildfolge, ein Video ohne erkundbare Anwendung, eine Demo nur um Rom oder
isolierte Regionalansichten sind kein abgeschlossenes Kit-1-Ergebnis. Interne
Tests dürfen selbstverständlich mit kleinen Ausschnitten beginnen.

## Umfang

| Enthalten | Später / ausgeschlossen |
|---|---|
| Gesamte regionale Landschaft: Land, Meere, Küsten, Höhenrelief, natürliche Gewässer und Vegetation | Städte, Gebäude, Menschen, eigene Tiersimulation, Wirtschaft oder Stadtwachstum |
| Eine natürliche Landschaftsansicht; unsichtbare quadratische logische Tile-Grundlage | GUI, sichtbares Raster, Tile-Auswahl/Highlights, Planungs-/Themenmodi, Politik und Wirtschaftsmechaniken |
| Gebundener flach-zu-isometrisch Kameraverlauf, Verschieben, stufenloser Zoom | Freies Drehen/Neigen, Egoperspektive, getrennte Welt-/Stadtmodi |
| Sommerlicher fester Darstellungszustand, festes warmes Tageslicht | Tagesablauf, Jahreszeitenwechsel, Wetter- oder Klimasimulation |
| Geografische Basis heutiger Daten und nachvollziehbare Herkunft | Behauptung einer vollständig rekonstruierten Landschaft von 180 n. Chr. |
| Reproduzierbarer Start, Prüffahrt und Mess-/Bildnachweise | Vollständige App, ungefragte Zusatzfunktionen oder das Spiel des Referenzkits |

Die Bedienung beschränkt sich auf Schwenken und Zoom, ohne GUI. Es gibt keine
Menüs, Buttons, Toolbars, HUD, Infofenster, Bildschirmlegenden oder Hilfetexte.
Die Tasten-/Mausbelegung steht in der externen Startanleitung. Teststeuerung und
interne Probes dürfen keine sichtbaren Debugoverlays als Produktfunktion erzwingen.

## Geografie und grafischer Maßstab

Alle Entfernungsbereiche verwenden dieselbe reale Quellgeografie. Daraus werden
ein tatsächlich verkleinerter Modellraum und eine separate zoomgebundene
Renderabbildung abgeleitet. Kleinere Details dürfen kontrolliert entfallen; die
Welt wird nicht mit jedem Zoom neu erzeugt. Quellen-/Modell-/Bildraum samt
Einheiten und Transformationen sind getrennt nachzuweisen.

**Kein Eins-zu-eins-Maßstab und keine beliebige Verzerrung:** Modelllängen und
Modellhöhen werden nachvollziehbar gemeinsam skaliert. Frei erfundene Berge,
verschobene Küsten, ortsabhängig zusammengeschobene Zwischenräume und freie
Höhenüberhöhung sind nicht autorisiert. Die Abflachung zur Fernkarte verändert
nur die gebundene Darstellung, nicht den kanonischen Modellraum. Projektions-
verzerrung und Generalisierungsfehler müssen getrennt beurteilt werden. Die
Arbeitswerte in [decisions.md](decisions.md) sind keine starren Maßstabsgrenzen.

[GENERALIZATION](operations/GENERALIZATION.md) definiert den Belegprozess für
Quellenqualität, Detailreduktion, Schutzregeln, Fehlerbudgets und LOD-Übergänge.

Die spätere technische Ausarbeitung muss eine nachvollziehbare Beziehung
zwischen geografischen Koordinaten und stilisierter Darstellung festlegen.
Damit müssen bekannte Punkte über den Zoom verfolgt und Fehler gemessen werden
können. Dieses Dokument bestimmt dafür weder Projektion noch Algorithmus.

Heutige Höhen-/Gewässer-/Landbedeckungsdaten sind eine mögliche Datengrundlage,
keine Lizenz zum Einblenden heutiger Siedlungen und Straßen. Kartentexturen mit
eingebrannten modernen Straßen, Ortsnamen, Gebäuden oder politischen Grenzen
sind für die normale Landschaftsdarstellung ungeeignet. Bekannte historische
Abweichungen der Daten werden verzeichnet; ihre spätere Korrektur bleibt offen.

## Verbindliche Bildsprache

Maßgeblich ist die vom Nutzer bestimmte **Primärreferenz** im
[Landschafts-Stilguide](references/STYLE_GUIDE.md). Sie zeigt eine stilisierte,
nicht fotorealistische Landschaft mit gemäßigten natürlichen Farben, lesbaren
facettierten Geländeformen, detaillierten Waldgruppen und natürlichen Übergängen.
Die Darstellung soll nicht zu bunt und nicht übermäßig low-poly, voxelartig,
würfelig oder klotzig wirken. Frühere Urbek-Beispiele sind nachrangig; sie dürfen
diese Nutzerreferenz nicht verdrängen. Eine vom Nutzer eingeschränkt akzeptierte
Fernstilprobe ist in STYLE_GUIDE dokumentiert; sie belegt ausdrücklich nicht die
geforderte flache 2D-Fernkamera.

- Die Primärreferenz setzt Palette, Materialwirkung und visuelle Detaildichte,
  aber keine technische Polygonzahl, FPS- oder Hardwarezusage.
- Stilistische Geländedetails und Waldgruppen bleiben aus gebundenen Quellklassen
  abgeleitet. Einzelne Bäume behaupten keine geodätisch gemessenen Baumstandorte.
- Regionale Landschaftsmerkmale bleiben erkennbar; eine gemäßigte Farbpalette
  vereinheitlicht nicht die ganze Projektregion zu einem Biom.
- Das nahe Terrain bleibt gut lesbar und Teil derselben quellengebundenen Welt.
  Die Detailstufen folgen dem später zu messenden Daten- und Darstellungsbudget,
  nicht der Forderung, Geometrie künstlich extrem zu vereinfachen.
- Die flache 2D-Fernkarte bleibt ein Endpunkt desselben kontinuierlichen
  zoomgebundenen Pfads; ihr Stil ist gegenüber der Nahansicht eine getrennte
  Darstellungsfrage, kein weiterer Modus.

Die frühere Bildauswahl wurde durch die Nutzer-Primärreferenz ersetzt. Ihre
aktuelle Rangfolge, eingeschränkte Fernstilreferenz und die verworfene Nahprobe
sind in [REFERENCES.md](REFERENCES.md) und dem Stilguide dokumentiert.

## Technischer Rahmen und verbleibende Ausarbeitung

Erstprüfung auf dem Mac ist vorgesehen. Der Nutzer wünscht zusätzlich
ausdrücklich spätere Versionen für Windows und Linux; diese Desktop-Portierungen
liegen deutlich später und erweitern den aktuellen Umsetzungsumfang nicht.
Eine spätere iPad-App bleibt optional. Rust-Kern, Hostadapter und Renderer sollen
so getrennt bleiben, dass diese Ziele nicht unnötig an Apple-spezifische APIs
gebunden werden. Metal ist ein optionaler Apple-Pfad; konkrete GPU-Funktionen
müssen zur Laufzeit geprüft und portable Alternativen vorgesehen werden.
Godot ist die vom Nutzer genannte App-Engine; konkrete Rust-/Rendererintegration
und Runtime-Version sind noch nicht spezifiziert oder geprüft. Ein Godot-Projekt
oder eine Runtime ist hier nicht vorhanden. Referenzhardware und endgültiger Plattformumfang
bleiben offen. Es gibt keine festgelegte Auflösung, FPS-, RAM-,
Download- oder Speichergrenze. Diese Werte sind vor belastbaren
Leistungsurteilen im späteren technischen Plan festzulegen und als technische
Festlegung zu kennzeichnen, nicht als nachträglich erfundener Nutzerwunsch.

Der Ausführer soll aus den bestätigten Anforderungen eine passende Technik
begründen: Datenquellen samt Version/Lizenz, Projektion und Maßstabsabbildung,
Darstellungs-/Detailverfahren, Kamera, Datenhaltung und Messverfahren. Er soll
keine bereits geklärten Gestaltungsfragen erneut stellen. Wesentliche neue
Zielkonflikte müssen benannt werden, statt den Scope stillschweigend auf einen
kleinen Teilbereich oder einen starren Realmaßstab zu reduzieren.

Die Rendering-Implementierungsbasis in
[`operations/RENDERING.md`](operations/RENDERING.md) bindet die spätere
Arbeitsfolge, ohne die offene Plattformentscheidung oder konkrete Technik
vorwegzunehmen. Der vorgeschlagene hierarchische Blockbaum ist eine messbare
Baseline, kein Nutzerentscheid und keine bestätigte SOTA-/Leistungsbehauptung.

Die bestehende Rust-/Swift-/iPad-Ausrichtung ist Projektkontext. Das Referenzkit
entscheidet **nicht** für Unity, Windows-only oder einen bestimmten Renderer.
Godot ist als Ziel-App-Engine benannt; die konkrete Integration ist hier nicht
ausgewählt.
Eine technische Auswahl ist in diesem Dokument nicht erfolgt. Es gibt keine
Leistungszusage für iPad und keinen Auftrag für eine Swift-Oberfläche in Kit 1.

## Spätere Lieferung

Nach tatsächlicher Umsetzung gehören zusammen:

1. Startbare Anwendung mit dem gesamten beschriebenen Erkundungspfad und
   reproduzierbarer Startanleitung für die tatsächlich geprüfte Umgebung.
2. Eigene Implementierung sowie dokumentierte Daten-/Asset-Herkunft und
   Versionen; keine übernommenen Spielassets oder Skripte aus dem Referenzkit.
3. Reproduzierbare Prüfkonfigurationen und reale Laufzeitergebnisse nach
   [ACCEPTANCE.md](ACCEPTANCE.md), ergänzt durch Bilder und eine Zoomaufnahme.
4. Ehrlicher Abschlussbericht: umgesetzt, geprüft, offene Fehler, historische
   Abweichungen, tatsächliche Hardware/Leistung und Grenzen der Abdeckung des gesamten Projektgebiets.

Heute wird das operative Build-Kit mit Vorlagen und lokalen Prüfwerkzeugen geliefert. Es enthält noch keine
Anwendung, keinen Datenbestand und keine bestanden behauptete Abnahme.

## Unsichtbare quadratische Tile-Grundlage

Die neueste Entscheidung K17–K20 begrenzt Kit 1 auf eine einzige Landschaftsansicht
ohne GUI oder weitere Darstellungsmodi. [TILES](operations/TILES.md) beschreibt die
unsichtbare logische Grundlage und ihren internen Belegvertrag. Keine Rasterlinien,
Tile-Auswahl, Planungs-/Themenfarben oder Modussteuerung implementieren.

Die Rasterdefinition benennt kanonische IDs und quadratische Zellen im logischen
Raum. Natürliche Geometrie muss nicht den Zellen folgen. Regionale Projektion,
Naht-/Kartenrandregeln und LOD-Zuordnung sind technische Ausarbeitung, keine Behauptung
überall im Projektgebiet gleich großer verzerrungsfreier Quadrate. Der interne Nachweis A15
verwendet Datenprobes, keine zusätzliche Bildschirmansicht. Die zuvor diskutierten
drei Modi und Themenanwendungen bleiben ausschließlich spätere Ziele.
