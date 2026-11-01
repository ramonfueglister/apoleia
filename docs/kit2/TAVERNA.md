# Taverna — erstes polygonales Einzelgebäude

Stand: 31.10.2026. **Implementiert** als editierbares Blender-Modell und GLB,
**validiert** für Import und drei gerenderte Ansichten in Godot 4.7.2 / Metal
auf diesem Mac. Ramon hat das Einzelmodell im Chat akzeptiert und die
Einbindung ins Spiel beauftragt.

Ausgangspunkt ist das in diesem Chat erzeugte Einzelbild `14-taverne.png`.
Die Formensprache ist eine eigene künstlerische Interpretation, keine belegte
Rekonstruktion eines historischen Thermopoliums. Alle Geometrien und
Materialtexturen werden im eigenen Blender-Skript erzeugt; keine fremden Assets.
Die Hausmasse sind in Metern angelegt, entsprechend der Menschengrössen-Ausnahme
in `SCALE.md`. Kein Landschaftsmassstab wurde geändert.

## Ansehen

Vom Repository aus:

```sh
./scripts/view-taverna
```

Linke Maustaste ziehen: drehen. Mausrad: zoomen. R: Ausgangsansicht. Esc: beenden.
Die Szene ist `app/scenes/showcase/taverna.tscn`. Sie benutzt den realen GLB-Import
und den Godot-Renderer mit orthografischer Kamera. Die Bilder sind
Laufzeitaufnahmen, keine generierten Konzeptbilder.

## Modell

Enthalten: Walmdach aus einzeln gewölbten Ziegeln, Firste und Traufen,
Fensteröffnungen mit Laibungen und Holzläden, offene Schankfront mit Regalen,
vier eingelassene Dolia mit Innenwand, gerahmte Wandfelder mit stilisierten
Lorbeerzweigen, Säulen, genähte Markise, Gewölbetür, Pergola, Ranken,
Amphoren, Bank, Pflaster sowie rückwärtige Lieferantentür und Fenster.

- Laufzeitdatei: `app/assets/buildings/taverna/taverna.glb` (eingebettete Texturen).
- Quelle: `tools/buildings/build_taverna.py`, deterministischer Seed 138.
- Editierbare Ausgabe: `build/taverna/taverna.blend`, Texturen eingepackt.
- 101 108 Quelldreiecke, 73 Mesh-Objekte, 30 Materialien.
- Laufzeitbilder: `docs/handover/taverna/front.png`, `rear.png`, `side.png`.

Neu erzeugen (lokal mit Blender 5.1.2 geprüft):

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/buildings/build_taverna.py
```

Die Generierung überschreibt ausschliesslich die eigenen Taverna-Ausgaben.
`--factory-startup` isoliert den Lauf von installierten Blender-Add-ons.

Reproduzierbare Aufnahme nach dem Godot-Import:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path app --editor --import
/Applications/Godot.app/Contents/MacOS/Godot --path app res://scenes/showcase/taverna.tscn -- --angle=42 --capture=/absolute/path/front.png
```

## Prüfung und Grenzen

Blender-Export, Godot-Import und drei Kameraansichten (42°, 105°, 222°) endeten
mit Exit 0; finale Logs ohne Fehler/Warnungen. Dachnormalen, Materialfarbraum,
Thekentiefe und überlagerte Eckflächen wurden anhand der Bilder korrigiert.
Python-Syntax, Shell-Syntax und Whitespace-Prüfung bestanden.

## Einbindung in Verona

**Implementiert und im laufenden Spiel geprüft:** Die Taverne ersetzt genau ein
Wohnhaus auf Parzelle (18455, 6919), relativ zum Verona-Plan (10, 13), an der
Südseite zur Strasse geöffnet. Zentrum: 10.979449737° E, 45.442881858° N.
Dies ist eine gestalterische Platzierung, kein archäologischer Standortnachweis.
Die Parzelle bleibt in Atlas und Simulation ein Wohn-/Geschäftshaus; es wurden
keine neuen Wirtschaftsregeln oder Einnahmen erfunden.

```sh
./scripts/play-taverna
```

Der Befehl startet `landscape.tscn` mit Simulation, Wetter und Spieloberfläche
bei der Taverne. `view-taverna` bleibt die separate Modellvorschau.

`city_taverna.gd` installiert das Modell nur, wenn der erwartete südorientierte
Wohnplatz im Plan existiert. Andernfalls bleibt die alte Darstellung erhalten.
Die bestehende Terrasse wird beibehalten und nur das alte Hausmesh unterdrückt.
`city_building.gdshader` liest dieselben gecachten Geländeecken wie die Häuser:
höchste Ecke, plus dieselbe 0,25-m-Stufe bei Viertelkacheln. Das Modell verwendet
die vorhandenen Spiellichter und seine neun eingebetteten Materialtexturen.

| Sichtbreite | Darstellung | Dreiecke |
|---|---|---:|
| bis 2,5 km | Detailmodell | 101 108 |
| bis 7,5 km | mittlere Stufe | 20 350 |
| darüber, auf nahen Geländekacheln | ferne Stufe, ohne Schatten | 4 432 |
| Geländestufe 1 und höher | bestehender ferner Stadtrenderer | bestehend |

Je Stufe sind die ursprünglich 73 Objekte in 30 Materialgruppen gebündelt.
Die Stufen teilen ShaderMaterial-Instanzen. Das Gebäude wird ausserhalb des
aktiven Häuserausschnitts ausgeblendet. Alle Masse bleiben unverzerrt; mit
9,20 × 7,00 m Grundfläche passt es auf eine 10,50-m-Parzelle.

Laufzeitasset nach Änderungen am Quellmodell neu erzeugen:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/buildings/prepare_taverna_runtime.py
```

Die Ausgabe ist `app/assets/buildings/taverna/taverna_runtime.glb`; Zählwerte
stehen in `runtime.json`. Vorher muss `build_taverna.py` gelaufen sein.

Integrationsprüfung gegen die echte Spielszene und den echten Stadtatlas:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path app --script res://scripts/debug/taverna_integration_check.gd -- --view=10.9794497369,45.4428818580,1.5
```

Ergebnis: Exit 0, keine fehlgeschlagenen Prüfungen. Geprüft wurden das Ersetzen
nur der vorgesehenen Parzelle, der erhaltene Nachbar, unveränderter Atlas,
Materialien/Texturen, Grundflächenpassung, sieben Zoomzustände von 1,5 bis
120 km, Übergabe an den fernen Stadtrenderer, Wegschwenken nach Rom und
Rückkehr sowie das Verhalten ohne Verona-Plan. Bericht und Spielaufnahme:
`docs/handover/taverna/integration.json`, `in-game.png`.

Offen bleiben wirtschaftliche Spezialfunktionen einer Taverne, Tür-/Innenraum-
Interaktion und Leistungsabnahme für eine grosse Anzahl solcher Gebäude.
Diese Einbindung betrifft ein Gebäude; die übrigen Häuser und Wahrzeichen
behalten ihre Modelle. Die bestehenden Verona-Änderungen bleiben erhalten.
