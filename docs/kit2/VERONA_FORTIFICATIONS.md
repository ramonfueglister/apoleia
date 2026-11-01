# Verona – Mauern, Tore und Grabparzellen

Stand: validiert; [Spielprüfung und Messwerte](../handover/verona-fortifications/validation.md).

Nach den Wohnvierteln erhalten Veronas vier Mauerparzellen, vier Tore und 23 Grabparzellen eigene Modelle. Sie verwenden dieselbe Materialfamilie und denselben einheitlichen Massstab wie die akzeptierten Häuser. Die Modelle sind eigene römische Bautypen, keine behaupteten archäologischen Rekonstruktionen. Stadtplan, Strassennetz, Fluss, Parzellen und Simulation werden nicht neu erzeugt.

## Modelle

Sieben Befestigungsbauteile bilden die vorhandene Mauerlinie: gerader Mauerarm, diagonaler Mauerarm, quadratischer Turm, zwei entsprechende Toranschlüsse, ein Tor mit zwei Seitenpavillons und ein vierseitiges Tor für die bestehende Strassenkurve. Kalkstein, verputzte Flächen, zurückhaltende rote Bänder, Zinnen, tiefe Fensteröffnungen und geschlossene Ziegeldächer verbinden sie mit den Wohnhäusern.

Die drei Grabparzellen kombinieren Altäre, einen kleinen Grabschrein oder ein Rundgrab mit Sitznische, jeweils mit wenigen Zypressen und einer ruhigen Bodenfläche. Sie sind 9,2 × 9,2 m gross, höchstens 6,68 m hoch und lassen an ihrer Vorderseite mindestens 1,15 m frei. Die Ausrichtung folgt dem vorhandenen Atlaszugang; die Variantenwahl ist deterministisch. Inschriften sind abstrakte Linien ohne erfundene historische Identitäten.

## Anschlüsse und Durchgänge

Die Mauer folgt dem bestehenden Graphen mit sieben Verbindungen, darunter drei diagonale Verbindungen. Der zuvor fehlende diagonale Anschluss zwischen zwei Torparzellen wird ebenfalls geschlossen. Die Linie bleibt an ihren vorhandenen Enden offen; es wird keine zusätzliche Ringmauer erfunden.

Mauer- und Torbauteile behalten ihren gezeichneten Ursprung am Parzellenmittelpunkt. Die Laufzeit rotiert sie um Vierteldrehungen beziehungsweise zusätzlich 45° und skaliert alle Achsen gemeinsam mit `DIORAMA_KM_PER_M = 0.0238`. Die sonst übliche Zentrierung und Einpassung eines Einzelhauses entfällt hier, damit Anschlusslängen exakt bleiben. Gerade Gegenstücke überlappen ungefähr 0,096 m, diagonale ungefähr 0,345 m. Diagonalstücke reichen absichtlich entlang des Verbindungskorridors über die quadratische Parzellengrenze hinaus.

Tore lassen 3,60 m Breite bis 4,10 m Höhe unter dem Bogen frei. Das vierseitige Tor lässt beide Achsen der bestehenden Strassenkurve offen. Es gibt keine Bodenplatte quer durch den Durchgang. Die Fundamente liegen nur unter festen Bauteilen und reichen normalerweise zwei Meter tief. Der gerade Mauerarm reicht bis −6,5 m, weil ein bestehender Anschluss eine Terrassenstufe von 6,30 Modellmetern überbrückt. Dieser zusätzliche Unterbau verändert keine Geometrie oberhalb des Ursprungs. Geländehöhen und Terrassen bleiben unverändert.

Ein komplettes Tor mit seinen Anschlüssen wird erst sichtbar, wenn alle Teile geladen sind; bis dahin bleibt das alte Tor erhalten. Mauerstücke werden einzeln nach erfolgreichem Laden ersetzt, Grabparzellen jeweils vollständig. Mehrere Instanzen teilen ihre geladenen Meshes und Texturen. Alle zehn Modelle haben eigene formbewahrende Detail-, Mittel- und Fernstufen; die zusätzliche automatische Godot-Vereinfachung wird ausgeschaltet.

## Reproduktion und Prüfung

Die Blender-Generatoren sind `tools/buildings/build_verona_fortifications.py` und `tools/buildings/build_verona_tombs.py`, jeweils mit `--background --factory-startup --python … -- --all`. Spielassets und Metadaten stehen unter `app/assets/buildings/verona_*/`; bearbeitbare Blender-Dateien werden unter `build/roman-series/<slug>/` erzeugt.

Start im Spiel: `scripts/play-verona`. Die Spielprüfung läuft mit `Godot --path app --script res://scripts/debug/verona_fortifications_check.gd`. Sie umfasst die unveränderten 35 bisherigen Gebäudeinstanzen, alle neuen Mauer-/Tor-/Grabparzellen, tatsächliche Mesh-Durchgänge und Anschlüsse in drei Detailstufen, das Verhalten bei unvollständigen Toren sowie Atlas-Prüfsummen. Visuelle Sichtkontrollen ergänzen die geometrischen Prüfungen, insbesondere für die shaderseitige Geländeanpassung.

Belege: [Grundriss und Anschlussgraph](../handover/verona-fortifications/layout-audit.md), [Sichtprüfung](../handover/verona-fortifications/visual-review.md).
