# Kit 1 — bestätigter Entscheidungsstand

**Referenzversion:** `kit1-landscape-v5` · **Datum:** 25.10.2026.  
**Status:** folgende Nutzerentscheidungen `spezifiziert`; keine davon behauptet
eine implementierte oder validierte Grafik. Quelle ist das gemeinsame Interview.
Neuere ausdrückliche Entscheidungen ersetzen frühere widersprechende Vorschläge.

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

## Bestätigt für Kit 1

| ID | Entscheidung |
|---|---|
| K01 | Kit 1 umfasst ausschließlich die **natürliche Landschaft der gesamten Projektregion**, den Zoom und eine unsichtbare quadratische Tile-Grundlage in genau einer Landschaftsansicht. Historische Referenz bleibt **180 n. Chr.** |
| K02 | Ergebnis der späteren Umsetzung ist eine **startbare, durch Verschieben und Zoomen frei erkundbare Welt**. „Frei erkundbar“ bedeutet keine frei drehbare Kamera. |
| K03 | **Zoomgebundene Kamera:** flache 2D-Fernkarte → kontinuierlicher räumlicher Übergang → isometrische Diorama-Nahansicht. Keine freie Drehung/Neigung und keine manuelle Ansichtsumschaltung. |
| K04 | **Stufenloser Zoom** von Gesamtübersicht bis Nahansicht für mehrere spätere Häuser mit ihrer Umgebung. Keine sichtbaren Wechsel zwischen Welt-, Regions- und Stadtmodi. EU5/Victoria 3 dienen als Referenz für das Weltkarten- und Zoomgefühl. |
| K05 | Alle Ansichten entstehen aus **einer gemeinsamen geografischen Grundlage**. Küsten, Flüsse, Gebirge und räumliche Beziehungen dürfen nicht pro Zoomstufe neu erfunden werden. |
| K06 | **Tatsächlich verkleinerte, aus realen Geodaten abgeleitete Modellwelt.** Dokumentierte gemeinsame Skalierung und maßstabsabhängige Detailreduktion, keine frei erfundene Geografie, willkürliche Distanzverkürzung oder Geländeüberhöhung. Geografische Formen/Proportionen innerhalb offengelegter Projektions- und Fehlergrenzen erhalten. |
| K07 | **Heutige Geodaten als Basis.** Datensätze und Versionen sind noch nicht gewählt. Historische Korrekturen werden später ergänzt; heutige Daten sind keine historisch validierte 180er-Landschaft. |
| K08 | **Einheitliche stilisierte, natürliche Landschaftsgrafik** gemäß der Nutzer-Primärreferenz im [STYLE_GUIDE](references/STYLE_GUIDE.md): lesbare facettierte Geländeformen, natürliche Übergänge und detailreiche, übersichtliche Waldgruppen. Nicht fotorealistisch, nicht übermäßig low-poly, voxelartig oder würfelig-klotzig. Frühere Urbek-Bilder bleiben nachrangige Formkontexte, keine Terrain-Hauptvorgabe. |
| K09 | **Zurückhaltende, nicht zu bunte natürliche Palette** wie die Nutzer-Primärreferenz: gemäßigte Grünflächen, tiefes Blau und helleres Flachwasser sowie helle graubeige Felsgebirge. Die Primärreferenz bestimmt Palette, Materialwirkung und Detaildichte; sie begründet weder ein Polygonbudget noch eine Leistungszusage. |
| K10 | Wälder erscheinen im Nahzoom als **einzelne stilisierte Bäume** in derselben vereinfachten Formensprache. |
| K11 | **Natürliche Landschaftsfarben in der einzigen aktuellen Ansicht**, keine politischen Grenzen, Gebietsfarben oder Themenlayer. |
| K12 | **Sommer** als fester Darstellungszustand und **festes warmes Tageslicht**. Jahreszeitenwechsel und Tag/Nacht kommen später. |
| K13 | Keine modernen Städte, Straßen oder sonstigen modernen Bauwerke aus den Daten darstellen. Städte, Gebäude und Menschen kommen später; auch keine antiken Stadtmodelle in Kit 1. |
| K14 | **Historischer Gesprächsstand:** zunächst auf dem Mac erproben; als damalige Leistungsrichtung wurde ein flüssiger Mittelklasse-PC genannt, ohne Hardware/FPS/Auflösung. **Zwischenstand 25.10.2026:** Mac-only möglich, iPad optional; finale Plattform offen. **Neuere Nutzerentscheidung:** Windows- und Linux-Versionen sind gewünschte spätere Produktziele; Umsetzung deutlich später, nicht Teil des aktuellen Kit-1-Auftrags. Der historische PC-Leistungssatz bleibt davon getrennt und begründet keine Leistungszusage. Rust-Kern, Hostadapter und Renderer sollen portabel getrennt werden; Metal bleibt optionaler Apple-Pfad und Plattform-/GPU-Fähigkeiten sind zur Laufzeit zu prüfen. Godot ist die vom Nutzer genannte App-Engine; konkrete Integration und Runtime-Version sind offen, ein Godot-Projekt/Runtime liegt hier nicht vor. Referenzhardware, Engine und konkrete Plattformunterstützung bleiben offen. |
| K15 | **Gesamter Grafikauftrag in einem Durchlauf** als Ziel des Kits. Rom/Ostia/Tibur sind ein mögliches Prüfbeispiel, keine regionale Beschränkung des Ergebnisses. |
| K16 | Aktueller Auftrag ist **vollständige Kit-Anpassung einschließlich operativer Hilfsmittel, keine Spielimplementierung**. Bereits geklärte Fragen nicht erneut stellen. Technische Vorschläge aus Vorgaben ableiten, nicht alltägliche Details als neue Grundsatzfragen zurückgeben. |
| K17 | Für moderne Gebiets-Auswahlanker dient geoBoundaries **gbOpen ADM2 bevorzugt als Orientierung**. ADM2-Level und Features sind länderweise verschieden; sie behaupten keine antiken Grenzen, keine Simulationsregionen und schreiben keine politische Grenzvisualisierung oder harte finale Cutline vor. Exakte Features und Datensatzrevision bleiben offen, bis die konkrete Datenauswahl erfolgt. |

## Maßstabswerte: Orientierung, keine starren Vorgaben

Die Bezeichnungen sind Beobachtungsbereiche innerhalb desselben stufenlosen
Zooms, keine separaten Ansichtsmodi. Die Ausschnittsbreiten sind Arbeitswerte;
sie legen weder Projektion, Zoomfaktor noch Speichergröße fest.

| Bereich | Ungefähre Ausschnittsbreite als Arbeitswert |
|---|---:|
| Gesamtübersicht | gesamtes gebundenes Projektgebiet; keine feste Kilometerbreite |
| Kontinent/Region | 1.000–4.000 km |
| Großregion | 100 km |
| Stadt | 5–10 km |
| Stadtviertel / nächster Zoom | 500 m |

Maßgeblich ist die gewünschte Wirkung: von der gesamten Projektregion bis zu einem
Ausschnitt, in dem später mehrere Häuser samt Umgebung gut erkennbar sind.
Die Werte dürfen dieses Ziel nicht durch starre Realmaßstäbe unterlaufen.

## Historische Korrekturen — ausdrücklich für später offen

Die heutige Basis darf nicht als „100 % richtig für 180 n. Chr.“ ausgewiesen
werden. Historische Genauigkeit ist der Anspruch; globale Detailkenntnis ist
nicht gegeben. Beim späteren historischen Abgleich sind insbesondere zu prüfen:

- Küsten, Flussmündungen, Flussläufe und Deltas;
- moderne Stauseen, Kanäle, Entwässerung und Landgewinnung;
- historische Vegetation und Gletscher nach verfügbarer Quellenlage.

Die gewählte Datengrundlage muss bekannte Abweichungen kenntlich machen, damit
sie später korrigiert werden können. Das schreibt noch kein technisches
Korrekturformat vor. Moderne Bebauungs- und Verkehrsobjekte sind bereits jetzt
außerhalb des Darstellungsumfangs; eine vollständige Rückrekonstruktion aller
menschlich veränderten Geländeformen ist noch nicht beauftragt.

## Bestätigte Wünsche für spätere Kits, nicht in Kit 1 bauen

- Gesamtspiel mit Wirtschaftsaufbau und zusammenhängender Welt-, Regions- und
  Stadterfahrung. Der Staat kann gezielt Industrien und Verkehr bauen; private
  Unternehmen und Städte entwickeln sich auch selbstständig.
- Langfristig soll die Grafik sehr viele bis tausende Städte und Einheiten
  handhaben können. Das ist ein Skalierungsziel für spätere Ausbaustufen, keine
  bereits gemessene Leistung und kein Auftrag, sie jetzt in Kit 1 einzubauen.
- Staatliche Fabriken zahlen Gewinne in die Staatskasse und können privatisiert
  werden. Diese Wünsche definieren noch keine Wirtschaftsformeln.
- Historische Stadtform und wichtige Bauwerke erhalten; gewöhnliche Bebauung
  reduzieren. Städte sollen zusammenhängend und glaubwürdig wirken.
- Ein sichtbares Wohnblockmodell zeigt **mehrere Häuser**, nicht nur einen
  stellvertretenden Einzelbaukörper, und kann ein größeres Quartier repräsentieren.
  Wohlstand soll an den Vierteln erkennbar sein.
- Stadtgrößen unterscheiden sich durch Gebäudezahl, Dichte, Höhe und Fläche.
  Architektur variiert nach Kultur, Epoche und Entwicklung.
- Hauptstraßen, Eisenbahnen, Bahnhöfe/Häfen, große Industrien und öffentliche
  Schlüsselgebäude werden gezielt geplant; Nebenstraßen, Wohnviertel, gewöhnliche
  Geschäfte und kleine Werkstätten wachsen automatisch. **Eisenbahnen sind ein
  späteres, epochenabhängiges Konzept, kein Inhalt des Jahres 180 n. Chr.**
- Einzelne Menschen sollen sichtbar sein, mengenmäßig zum abstrahierten
  Stadtmaßstab passend; Verhaltensdetails sind später zu klären.
- Möglichst keine schwebenden Symbole über der Stadt. Gebäudearten sollen am
  Aussehen erkennbar sein; Details per Anklicken oder zuschaltbarer Kartenansicht.
- Politische Grenzen/Gebietsfarben, Tag/Nacht und Jahreszeitenwechsel später.

Rom mit **100 sichtbaren Wohnblockmodellen** und **800.000 Einwohnern** ist eine
grafische Arbeitsannahme bzw. historische Modellannahme aus dem Gespräch, keine
belegte exakte Bevölkerung und keine feste Abnahmezahl. Die älteren Größenideen
„30–70 Gebäude plus etwa 200 Wohnhäuser“ sind ebenfalls keine bindenden Werte.

## Technisch noch nicht entschieden

Datensätze/Versionen/Lizenzen, Projektion und Maßstabsabbildung, Grafikstack,
Detailstufenverfahren, Datenaufteilung, Speicher- und Ladeverfahren,
Referenzhardware, Auflösung und quantitative Leistungs-/Fehlergrenzen sind
`offen`. Auch Offlinebetrieb oder Nachladen wurde **nicht** entschieden.
Das sind später zu begründende technische Festlegungen, kein Anlass, das bereits
geklärte Grafikinterview neu aufzurollen. „Sommer“ legt noch kein globales Datum
oder eine saisonale Klimasimulation fest; regionale natürliche Unterschiede
dürfen nicht durch eine überall identische Vegetation ersetzt werden.

## Bestätigte Referenzerweiterung

Am 25.10.2026 hat der Nutzer die sechs einzeln gezeigten echten Urbek-/Victoria-3-
Referenzscreenshots samt ihrer Zuordnung akzeptiert. Am 26.10.2026 wurden die drei
Victoria-3-Bilder auf Nutzerwunsch entfernt; die drei Urbek-Bilder bleiben. [Der Katalog](references/screenshots/README.md)
bleibt dem Landschaftsauftrag untergeordnet; die sichtbaren modernen Gebäude,
Straßen, Kulturlandschaften, politischen Farben und UI-Elemente werden nicht zu
Kit-1-Features. Die Akzeptanz ist keine vorweggenommene Produktabnahme.

Am 25.10.2026 bestimmte der Nutzer ein bereitgestelltes Landschaftstriptychon
ausdrücklich als **primäre Stilreferenz**: „ich muss sagen das gefällt mir am
besten: wenn es so rauskommen würde wär wunderschön. nicht zu bunt aber dennoch
extrem wunderschön. das wär für mich die referenz. nicht zu low polig“.
Das ersetzt frühere, zu voxelartige Stilvorgaben. Palette, Materialwirkung und
Detaildichte sind damit `spezifiziert`; Polygonbudget und Laufzeit bleiben offen.
Zuordnung, eigene Sichtung und Ausschlüsse stehen im
[Landschafts-Stilguide](references/STYLE_GUIDE.md). Frühere eigene Generierungen
wurden aus dem aktiven Kit entfernt; sechs offizielle Screenshots bleiben als
nachrangiger Quellenkontext erhalten. Keine Bildquelle belegt Geografie, historische 117/180-
Formen oder gemeinsame Zoomszenen. Gesamtregion und ADM2-Auswahlmethode bleiben
unverändert.

Später akzeptierte der Nutzer eine auf dieser Primärreferenz basierende
weiträumige Bildprobe als ergänzende Stil-/Farbreferenz („doch weitsicht ist
okay“, „aber na gut“), wies aber darauf hin, dass die Weitsicht flach sein soll.
Sie ist daher ausdrücklich kein Beleg oder Ersatz für K03s flache 2D-Fernkamera.
Die dazu erzeugte Nahprobe wurde verworfen und nicht in das Kit aufgenommen.

## Tile-Entscheidung und neueste Scopekorrektur vom 25.10.2026

Der Nutzer bestätigte zunächst quadratische Tiles und drei Ansichten. Danach
präzisierte er ausdrücklich: **keinerlei GUI** und **keine unterschiedlichen
Darstellungsmodi in diesem Schritt**. Diese neuere Entscheidung hat Vorrang.

| ID | Aktueller verbindlicher Umfang |
|---|---|
| K17 | Quadratische **logische** Tiles bleiben als unsichtbare Datenstruktur/Basis. Natürliche Terrainformen, Küsten und Flüsse dürfen Tile-Grenzen schneiden. |
| K18 | Kit 1 zeigt **genau eine natürliche Landschaftsansicht** mit Schwenken und stufenlosem Zoom. Kein sichtbares Raster, keine Planungs-/Themenansicht, kein Moduswechsel. |
| K19 | **Keine GUI:** keine Menüs, Buttons, Toolbars, HUD, Infofenster, Statuspanels, Bildschirmlegenden oder Hilfetexte. Keine Tile-Auswahl oder Auswahlmarkierungen als aktive Funktion. Bedienhinweise gehören in die externe Startanleitung. |
| K20 | Kanonische Tile-Identität, Quellgeografie und Renderabbildung bleiben beim Pan/Zoom konsistent. Interne Datenprobes dürfen dies prüfen, ohne eine Anzeige, einen Klick oder einen zusätzlichen Modus einzuführen. |

**Für später vorgemerkt, jetzt nicht implementieren:** natürliche Normalansicht,
Bau-/Planungsansicht mit Raster und Auswahl sowie thematische Einfärbung etwa nach
Fruchtbarkeit/Bodenart. Die Quadratwahl bleibt bestehen. Diese drei späteren
Darstellungsweisen sind keine aktuellen Abnahmen oder technischen Startblocker.
Es gibt keine beschlossene Fruchtbarkeitsformel und keinen Themen-Datensatzauftrag.

Tilegröße, Adressierung, Projektion, regionale Aufteilung und LOD-Aggregation bleiben
technisch zu begründen. Quadratisch gilt im dokumentierten logischen Rasterraum;
isometrische Projektion und regionale Abbildung können Zellen verzerren. Keine
überall flächengleiche, verzerrungsfreie Quadratpflasterung der Kugel versprechen.
Kartenränder, Küstenübergänge und Aufteilungsnähte brauchen konsistente kanonische IDs. Weltweite Pol-/Datumsgrenzprüfungen sind nicht erforderlich.
Sichtbare Detailstufen dürfen Daten aggregieren, aber nicht deren Identität ändern.

## Präzisierung: verkleinerte datenbasierte Modellwelt (v4)

Der Nutzer bestätigte eine tatsächlich kleinere Modellwelt mit später weniger
Häusern/Menschen, nicht nur eine klein gerenderte vollständige Originalwelt.
Für Kit 1 betrifft das ausschließlich Landschaft und ihre Detailrepräsentation;
keine Bevölkerungsskalierung, Wirtschaftsformel oder historische Stadtfläche ist
hier festgelegt. Meshdichte ist keine Simulationsbevölkerungsformel.

Alle Landschaftseigenschaften müssen aus realen versionierten Daten abgeleitet
sein. Kleine Dinge dürfen nach dokumentierten Generalisierungsregeln entfallen.
„100 % akkurat“ wird prüfbar als vollständige Herkunft und kontrollierte
Abweichung umgesetzt, nicht als Fehlerfreiheit der Quellen oder Weltprojektion.
Kleine stilisierte Bäume können reale Landcoververteilung repräsentieren; sie sind
keine behaupteten Messpunkte jedes einzelnen Baums. Datenlücken offen führen,
keine frei erfundene Topografie oder rekonstruierte 180er-Vegetation ergänzen.

K03/K06 ersetzen die frühere durchgehend feste Isometrie sowie freie Überhöhung
und ungleichmäßige Verkürzung der Zwischenräume. Ein skalierter Modellraum
verwendet zunächst gleiche Längen-/Höhenskalierung; die erlaubte Abflachung des
Reliefs für die Fernkarte ist eine separat dokumentierte Rendertransformation.
Eine flache Erdprojektion kann nicht überall Form, Fläche und Länge gleichzeitig
erhalten. Ihre Verzerrung wird gemessen, nicht mit globaler Fehlerfreiheit beworben.

Die akzeptierten wissenschaftlichen Grundlagen stehen in
[GEODATA_METHODS](references/GEODATA_METHODS.md). Konkrete Algorithmen, Skalenfaktor,
Projektion, Stichproben und Toleranzen legt der spätere Ausführer begründet vor
Messung fest. Das ist keine neue Interviewrunde und keine Bibliotheksvorgabe.

## Geografische Scopekorrektur v5 (25.10.2026)

Die abschließende Nutzerentscheidung lautet Römisches Reich bei größter Ausdehnung
und Mittelmeerraum, ausdrücklich mit England und Raum nördlich davon. Sie ersetzt
den vorherigen Weltumfang und den unmittelbar zurückgenommenen Europa-Vorschlag.
K01/K15 beziehen sich jetzt auf die vollständige gebundene Projektregion.
Nur der geografische Umfang wird geändert. Die zuletzt durchgerechneten Skalen,
Tilegrößen, Stadtbudgets und 100×100-Beispiele sind keine neuen Kitvorgaben.
Die übrigen Vorgaben und der Abschnitt für spätere Kits bleiben unverändert.
