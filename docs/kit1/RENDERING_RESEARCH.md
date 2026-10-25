# Grafik-/Streaming-Recherche für Kit 1

**Stand:** 25. Oktober 2026 · **Kit-Referenz:** `kit1-landscape-v5`  
**Dokumentstatus:** Recherche `erforscht`; Implementierungsbasis
[`operations/RENDERING.md`](operations/RENDERING.md) `spezifiziert`; konkreter
Stack, Datenformat und Plattformumsetzung `offen`.  
**Implementierungs-/Validierungsstand:** kein Renderer implementiert, kein
Gerät gemessen. Keine Engine-, Plattform- oder Leistungszusage.

## Zweck und Geltungsbereich

Dieses Dokument ergänzt das Build-Kit für die zusammenhängende, verkleinerte
Landschaftsregion mit flacher Fernkarte, kontinuierlichem Übergang zur
isometrischen Nahansicht und unsichtbaren quadratischen logischen Tiles. Es
beantwortet die technische Recherchefrage, wie eine spätere Darstellung Daten
für unterschiedliche Zoomstufen organisieren und nachladen könnte. Es startet
keine Umsetzung und ändert keine Nutzerentscheidung aus
[`TASK.md`](TASK.md), [`TILES.md`](operations/TILES.md) oder
[`decisions.md`](decisions.md).

**Plattformstand der damaligen Recherche:** Mac oder später iPad waren offen.
Neuere Nutzerentscheidung ergänzt Windows/Linux als deutlich spätere Ziele; die
Recherche belegt keine Portierbarkeit oder Plattformleistung. Godot ist die vom
Nutzer genannte App-Basis; Integration und Runtime-Version sind offen. Apple Silicon ist eine plausible, ausdrücklich noch
nicht beschlossene Prototypbasis. Ein iPad-Modell, Intel-Mac-Support,
Auflösung, Bildrate, Speicherlimit und Auslieferungsgröße sind nicht festgelegt.
Der bestehende Projektkontext nennt Rust-Wirtschaftskern und spätere Swift-
Anbindung; daraus folgt noch keine Renderer- oder Plattformentscheidung.

## Was die Paradox-Quellen tatsächlich belegen

### Beobachtungen

- **Victoria 3, offizielles Performance-Tagebuch #76 (2023):** Paradox
  beschreibt getrennte Session-, Aufgaben-, Haupt- und Render-Threads. Die
  Grafikaktualisierung kann Spielzustandszugriffe blockieren; das Team
  begrenzte solche Übergaben auf konsistente Tick-Grenzen. Es berichtet auch,
  dass ein Kartenupdate im späteren Spiel teuer werden konnte und dadurch die
  Simulation auf die Grafik warten musste. Optimierungen betrafen unter
  anderem Threading von Kartennamen und die Suche nach Gebäude-Positionen.
  Das ist ein konkreter Beleg dafür, Grafikaktualisierung und Simulation
  voneinander zu entkoppeln und beides getrennt zu profilieren. Es ist **kein**
  Beleg für einen bestimmten Welt-Streaming- oder Terrain-LOD-Algorithmus.
- **Victoria 3, offizielles „Living Map“-Tagebuch #50 (2022):** Beschreibt
  sichtbare, durch Simulationszustände veränderte Hubs, Vegetation,
  Landwirtschaft, Bergbau, Verschmutzung und Kriegszerstörung. Es belegt eine
  Kopplung von Simulationsdaten an Kartenerscheinung, veröffentlicht aber
  keine Geometrie-Streaming-Architektur.
- **Victoria 3, offizieller Grafiküberblick #49 (2022):** Beschreibt eine
  visuelle Hierarchie für Kartenobjekte, eine Papermap-Fernansicht und
  technische Lösungen wie shaderbasierte Wellen, Wolken und Grenzdarstellung.
  Auch hier sind das Gestaltungs- und Featureaussagen, keine Beschreibung des
  Terrain-Streamings.
- **Imperator: Rome, Intel-Engineering-Fallstudie mit Paradox (2020):** Die
  öffentlich dokumentierte Optimierung einer Grenz-Gradientenfunktion nutzt
  Textur-Lookups, einen GPU-Jump-Flooding-Schritt und bei kleinen Änderungen
  begrenzte Aktualisierungsregionen; beim Profiling waren periodische
  Frame-Spikes aussagekräftiger als die durchschnittliche Bildrate. Dies ist
  ein konkreter Rendering-/Profiling-Fall für *Imperator*, aber kein
  allgemeiner Clausewitz/Jomini-Vertrag und kein Nachweis für EU4, EU5 oder
  Victoria 3.
- **EU4/EU5:** In den ausgewerteten offiziellen, öffentlich zugänglichen
  Unterlagen fand sich keine hinreichend detaillierte Beschreibung des
  Renderers, des Nachladens von Geodaten oder des LOD-/Chunk-Verfahrens. EU5
  als visuelle Referenz für Zoomgefühl zu verwenden ist eine Kitentscheidung;
  daraus lässt sich seine interne Technik nicht ableiten.

### Grenze der Paradox-Evidenz

Es gibt hier **keine bestätigte Aussage**, dass EU4, EU5 oder Victoria 3
Terrain per Chunk-Streaming, Clipmaps, Virtual Texturing oder einem bestimmten
LOD-Baum laden. Ebenso wird keine Engine-Interna-Parität behauptet. Für den
konkreten Paradox-Bezug sind die belastbaren technischen Materialien die
genannten Victoria-3-Entwicklertagebücher und die Imperator/Intel-Fallstudie;
für EU5 wurde keine passende Primärquelle gefunden.

## Übertragbare Forschung und Herstellerdokumentation

Diese Quellen beschreiben allgemeine Verfahren, nicht die Implementation eines
Paradox-Spiels:

- **Geometry Clipmaps (Asirvatham & Hoppe, GPU Gems 2, 2005):** verschachtelte
  regelmäßige Raster um den Betrachter werden schrittweise verschoben und als
  Geometriecache genutzt. Die Arbeit erklärt glatte LOD-Übergänge,
  gleichmäßiges Rendering und GPU-seitige Verarbeitung großer Höhenfelder.
  Sie demonstriert historische Werte auf damaliger NVIDIA-Hardware; diese
  Werte sind keine heutige Leistungsprognose.
- **Ellipsoidal Clipmaps (Dimitrijević & Rančić, 2015):** erweitert Clipmaps
  für planetare Geometrie, Datenpartitionen und Textur-Streaming. Unser
  Kit-Gebiet ist ein regionaler Modellraum, keine geforderte Globusdarstellung;
  die Arbeit ist daher konzeptionell nützlich, aber keine direkte
  Geometrievorgabe.
- **High-performance Ellipsoidal Clipmaps (2023):** beschreibt LOD-Reduktion,
  geografisches Block-Culling und feinere GPU-Pipelines für große
  geodätische Szenen. Deren globale Präzisions-/Durchsatzwerte sind nicht auf
  unseren Regionalausschnitt oder Apple-Hardware übertragbar.
- **GPU-basierte Geometriekompression für DEMs (Dick, Schneider & Westermann,
  2009):** zeigt, wie komprimierte, adaptiv triangulierte Höhenmodelle beim
  Laden aus großen Datenbeständen Bandbreite sparen können. Das motiviert
  komprimierte Pakete und asynchrones Nachladen; ein bestimmtes Format ist
  damit nicht vorentschieden.
- **Apple Metal-Dokumentation:** Apple-GPUs verwenden tile-based deferred
  rendering (TBDR); Metal beschreibt Tile-Speicher, Render-Pass-Last-/Store-
  Aktionen und `memoryless`-Ressourcen für temporäre Renderziele. Das ist für
  temporäre GPU-Zwischenpuffer relevant. Diese GPU-Screen-Tiles sind **nicht**
  dasselbe wie die quadratischen logischen Welttiles des Kits.

### Quellenabgleich bis 25.10.2026

Die bisherige Liste war kein laufend aktualisierter SOTA-Abgleich. Der folgende
gezielte Nachtrag prüft für diese Aufgabe Quellenfamilien zu Multi-LOD-/Out-of-
Core-Terrain, Texturstreaming, LOD-Übergängen, GPU-driven Sichtmengen sowie
Apple-Metal-Fähigkeiten. Recherchiert wurde mit Kombinationen der Begriffe
`terrain rendering`, `multiresolution`, `out-of-core`, `streaming`, `virtual
texturing`, `LOD transition`, `geomorphing`, `GPU-driven`, `indirect rendering`,
`Metal sparse texture`, `feature set` und `mesh shading`, eingeschränkt auf
Eurographics/ACM/HPG-Publikationsseiten, Autoren-/Universitätsseiten und
Apple Developer-Dokumentation. Suchmaschinenabdeckung ist keine systematische
Bibliometrie und kein Vollständigkeitsbeweis für alle Veröffentlichungen oder
Preprints.

**Zusätzliche direkt oder methodisch relevante Evidenz:**

- **Terrender / RASTeR (Croci, Amirghdam, Pajarola; Web3D 2022):** direkt
  einschlägig zu out-of-core multiresolution terrain, adaptiver Triangulation,
  Kamerabewegung und niedrigen Übergangsartefakten; die Arbeit enthält
  vergleichende Kamerafahrten. Sie ist eine passendere Baseline als globale
  Planet-Clipmaps, aber Web-/Testdaten und Plattformwerte sind nicht als
  Mac-/iPad-Benchmark übertragbar.
- **A Texture Streaming Pipeline for Real-Time GPU Ray Tracing (Lee,
  Zeichner, Li; SIGGRAPH 2025 Talks):** berichtete große Ptex-Quelldaten bei
  kleinem GPU-Cache, asynchroner Versorgung und LRU-Eviction ohne beobachtete
  Stalls in ihrer Disney-Szene. Nützlich für Cache-/Upload-/Stall-Metriken und
  Fallback-/Residency-Lebenszyklus; Ptex-Raytracing ist kein Terrain-LOD-
  Verfahren und die berichteten 1.5 TB / 2 GB / >95 % gelten nur für dieses
  Szenario.
- **LidarScout (Erler et al.; HPG 2025):** out-of-core Visualisierung
  landesweiter LiDAR-Punktwolken mit sofortiger Grobübersicht und
  prioritätsgesteuerter höherer Qualität. Übertragbar ist die sichtbare
  Grob-Fallback- und Blickrichtungspriorisierung. Datenstruktur und
  Oberflächenrekonstruktion für Punktwolken sind keine fertige Lösung für
  unser aus DEM-/Landcoverdaten abgeleitetes Terrain mit stilisierten Facetten;
  die Detaildichte folgt der Nutzer-Primärreferenz und wird nicht durch eine
  extreme Low-Poly-Optik vorgegeben.
- **Apple Sparse-Texture-Beispiel:** zeigt expliziten Detail-/MIP-Residency-
  Zustand, Zugriffszähler, asynchrone Updates, Parent-Mipmap-Abhängigkeiten
  und LRU-Cache. Das stützt einen optionalen Texture-Cache-Pfad und benennt
  notwendige Lebenszyklusfragen; Sparse Texture bleibt optionale
  Implementationstechnik.
- **Apple GPU-Feature-Set-Tabelle (PDF-Impressum: 21.05.2026):** nennt
  Mindestfamilien und Laufzeitabfragen. Mesh Shading beginnt bei Apple7.
  Placement Sparse (Metal 4) ist allgemein ab Apple8 gelistet; Fußnote 9
  nennt Apple7-Ausnahmen, darunter Apple7-macOS-Geräte. `supportsPlacementSparse`
  muss die tatsächliche Gerätefähigkeit entscheiden. Sparse Color Textures
  (Metal 3/4) sind ab Apple6 mit Einschränkungen gelistet. Keines davon ist
  ohne Zielgerät als gemeinsamer Basispfad vorauszusetzen. Metal empfiehlt
  Capability-Abfragen statt Gerätenamen. Die Tabelle ist zeitgebunden; vor
  Stackwahl erneut prüfen.

**2024–2026-Abgleich und Evidenzlücke:** In der gezielten Suche nach
begutachteten, direkt auf große geodatenbasierte Terrain-LOD-/Streaming-
Renderer passenden Veröffentlichungen für 2026 wurde bis zum Stichtag keine
verifizierte Arbeit in Proceedings/Journalseite gefunden, die einen
Implementierungswechsel für diesen regionalen Maßstab rechtfertigt. Ein
2026er Hochschultext zu GPU-driven Terrain wurde als Abschlussarbeit
identifiziert, nicht als begutachteter Proceedings-/Journalbeleg; er wurde
nicht zur tragenden Architekturgrundlage gemacht. 2024er Arbeiten zu
prozeduraler Terrainanreicherung und Multi-Scale-Erosion wurden ebenfalls
gefunden, aber für diesen Auftrag ausgeschlossen: sie synthetisieren neue
Detailformen und helfen nicht beim treuen Streaming derselben
quellengebundenen Modellgeografie. Diese gezielte Negativsuche beweist nicht,
dass es keine anderen 2026-Papers oder relevanten Preprints gibt.

**Verfahrensentscheidung aus der Evidenz:** zuerst einen hierarchischen
vorberechneten Blockbaum mit Elternfallback implementieren und gegen die
bestehenden A16-/Kamerafahrten messen. Das ist aufgrund der direkten
Terrender-Einschlägigkeit und der einfacheren Prüfbarkeit die geeignete
Baseline, nicht eine Behauptung, dass sie SOTA oder schneller als Clipmaps
sei. Clipmaps bleiben ein gezielter zweiter Versuch für Nah-Höhenfelder.
Texturvirtualisierung und GPU-generierte Sichtmengen erst dann hinzufügen,
wenn die getrennte Messung einen GPU-Texturcache- beziehungsweise
CPU-Submission-Engpass belegt. Die Implementierungs- und Abnahmefolge steht
in [`operations/RENDERING.md`](operations/RENDERING.md).

**Gezielte Ergänzung, 25.10.2026 (`kit1-rendering-v3`):** Godots
[Pipeline-Kompilierungsdokumentation](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html)
beschreibt Cache-/Erstnutzungs-Hitches und verfügbare Pipeline-Monitore; die
[interne Rendererarchitektur](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html)
unterscheidet Forward+ und Mobile und dokumentiert Godots RenderingDevice-
Abstraktion. Das begründet den geplanten Mess-/Vergleichsaufbau, keine Aussage
über unsere Laufzeit oder feste Eignung einer Godot-Version. UltraMeshRenderer
(2025, [ACM DOI](https://doi.org/10.1145/3731186)) wird hier nur als Hinweis
auf Speicher- und Kohärenzgrenzen bei LOD-Streaming herangezogen; die Übertragung
auf unsere Terrainpipeline ist eine eigene Designentscheidung und liefert keine
Leistungszahl für dieses Projekt. Siehe Messplan und Planstatus in
[`operations/RENDERING.md`](operations/RENDERING.md).

## Architekturrahmen als spätere, eigene Umsetzung

**Schichtentrennung:** Die spätere Renderstrecke hält folgende fünf Bereiche
getrennt. Die konkrete Umsetzung und Abnahmereihenfolge stehen in
[`operations/RENDERING.md`](operations/RENDERING.md):

1. **Kanonische Geodaten:** Quellen, Projektion/Modellraum, Höhen, Küsten,
   Gewässer und Vegetationsklassen mit gebundener Revision und Fehlerbudget.
2. **Vorbereitete Multi-LOD-Darstellung:** vorab erzeugte, zusammenhängende
   Geometrie-/Texturblöcke aus derselben kanonischen Geografie. LOD wählt
   vereinfachte Repräsentationen nach projiziertem Bildschirmfehler; es erfindet
   keine neue Küste pro Zoomstufe.
3. **Kamera und Sichtmengenwahl:** die gebundene Zoomkurve kontrolliert
   Projektion/Reliefübergang. Ein hierarchischer Raumindex wählt sichtbare
   Datenblöcke; nahe Detail- und Fernübersicht verwenden dieselben Anker und
   geprüfte Übergänge.
4. **Asynchrones Ressourcenmanagement:** I/O und CPU-Dekompression laufen
   außerhalb des Renderloops. Sichtbare und bald sichtbare Blöcke erhalten
   Priorität; GPU-Ressourcen werden über einen begrenzten Cache resident
   gehalten und bei Bedarf ersetzt. Ein sichtbarer Block darf nicht erst durch
   synchrones Lesen/Erzeugen verfügbar werden müssen.
5. **Plattformadapter und Anzeige:** erst nach Prototypvergleich festlegen,
   ob ein nativer Metal-Renderer mit Swift-Host, Rust-Renderer mit
   Metal-Backend oder eine gemeinsame Renderer-Abstraktion den geringsten
   Pflegeaufwand unter Berücksichtigung der später gewünschten Windows-/Linux-
Versionen sowie optionalem iPad ergibt. Der Rust-Wirtschaftskern
   veröffentlicht unveränderliche, versionierte Render-Snapshots; Renderer
   liest sie ohne den Simulationstick zu blockieren. Simulation und Grafik
   erhalten getrennte Threads, Zeitbudgets und Profilspuren.

Die Quadratkacheln aus `TILES.md` bleiben eine **logische Geografie-/Adressbasis**.
Sie müssen nicht dieselbe Größe, Form oder Identität wie Renderblöcke,
Geometrie-LOD-Patches, GPU-Tiles oder Datendateien haben. Ein Mapping
`logische Tile-ID → kanonischer Raumbereich → LOD-Blöcke` hält ihre Identität
beim Pan/Zoom stabil, ohne natürliche Küsten an Rasterkanten zu zwingen.

Der im Implementierungsplan spezifizierte Vorschlag lautet: hierarchischer
Blockbaum zuerst; Clipmaps nur als Messvergleich für Nah-Höhenfelder. Das ist
noch nicht durch Produktmessung validiert. Ein hybrider Ansatz bleibt Hypothese.

Wenn die spätere Produktplattform Apple-only wird, ist Metal ein naheliegender
Prototypkandidat; die konkrete Bindung bleibt offen. Das belegt keine
Überlegenheit einer konkreten Engine. `memoryless` eignet
sich nur für temporäre Renderziele, die nicht zwischen Renderpasses erhalten
bleiben müssen; persistente Terrain-/LOD-Daten gehören in normale, explizit
verwaltete Ressourcen. Windows und Linux sind gewünschte spätere Ziele; iPad bleibt optional. Die
konkrete Unterstützung und Leistung auf diesen Plattformen ist offen.

## Prototyp und messbare Abnahmekriterien

Vor einer Leistungsbehauptung werden konkrete Testgeräte, Auflösung,
Bildwiederholrate, thermischer Zustand und App-/OS-Build festgehalten. Mac-Erstprüfung ist vorgesehen; Windows und Linux sind gewünschte spätere
Ziele und iPad bleibt optional. Apple-Silicon-Hardware ist zunächst ein zu
prüfendes Prototypziel, kein bereits bestätigtes Nutzergerät.

Der minimale Datensatz enthält mindestens einen Küsten-, Gebirgs-, Wald-,
Binnenland- und Kartenrandbereich. Dieselben geografischen Kontrollanker
werden in Fern-, Übergangs- und Nahansicht sowie nach Pan/Zurückfahrt geprüft.
Messläufe zeichnen auf:

- Framezeit p50/p95/p99 und längste Ausreißer pro Zoom-/Pan-Szenario;
- CPU-Zeit nach Renderthread, Datenvorbereitung und Simulation; GPU-Zeit je
  Renderpass;
- Zeit von Sichtmengenänderung bis zum verfügbaren Block, Zahl sichtbarer
  fehlender/zu spät geladener Blöcke sowie Anzahl/Größe von Uploads pro Frame;
- Spitzen-RAM, GPU-Ressourcenbedarf, Cache-Trefferrate und Anzahl von
  Evictions/Neuladevorgängen;
- Bildvergleich für Küsten-/Flussanker, Höhenkontur und Vegetationsdichte über
  LOD-Übergänge; Tile-Probes nach dem bestehenden A15-Vertrag;
- Verhalten bei kaltem Start, wiederholter Kamerafahrt, Rückkehr in bereits
  besuchte Gebiete und App-Hintergrund/Vordergrund-Wechsel.

Ein Prototyp gilt für die nächste Architekturentscheidung als **messbar
vergleichbar**, wenn zwei Kandidaten denselben Datensatz, dieselbe Kamera- und
Szenariofolge, dieselben Qualitätsgrenzen und dasselbe Gerät verwenden. Die
konkreten akzeptablen Bildraten-, Speicher- und Fehlerbudgets werden erst
festgelegt, sobald Produktplattform und Referenzgeräte gewählt sind. Harte
technische Mindestchecks für jeden Kandidaten: keine synchronen Datei-/Decode-
Operationen im Renderloop, keine sichtbaren Löcher während normaler Navigation,
geprüfte Tile-ID-Stabilität und keine Geografieverschiebung außerhalb des
später festgelegten Projektions-/Generalisierungsbudgets.

## Offene Entscheidungen

- Referenzgeräte und konkrete OS-/GPU-Abdeckung je Zielplattform, einschließlich
  späterer Windows-/Linux-Versionen sowie optionalem iPad.
- Native Metal-/Swift-Renderstrecke versus Rust-Renderer mit Metal-Backend
  beziehungsweise portable Abstraktion.
- Quellen, Projektion, regionale Blockstruktur, Geometrie-/Texturformate und
  Offline-/Paketgrenzen.
- Vorberechneter LOD-Baum gegen Clipmaps/Hybrid; geeignete Fehlermaße und
  Übergangsverfahren für die flache-zu-isometrische Kamera.
- Referenzauflösung, Bildwiederholrate, thermisches Szenario, RAM-/GPU-Cache-
  und Installationsgröße.
- Messbare Toleranzen für Naht, Küste, Fluss, LOD-Popping und Generalisierung.

## Quellen

Primärquellen und technische Publikationen, Abruf 25.10.2026:

1. Paradox Interactive, [Victoria 3 Dev Diary #76: Performance](https://www.paradoxinteractive.com/games/victoria-3/news/dev-diary-76-performance), 22.02.2023.
2. Paradox Interactive/Steam, [Victoria 3 Dev Diary #50: Living Map](https://store.steampowered.com/news/posts/?enddate=1655395263&feed=steam_community_announcements), 16.06.2022.
3. Paradox Interactive, [Victoria 3 Dev Diary #49: Graphic Overview](https://www.paradoxinteractive.com/games/victoria-3/news/dev-diary-49-graphic-overview), 08.06.2022.
4. Intel, [Optimized Gradient Border Rendering in Imperator: Rome](https://www.intel.com/content/www/us/en/developer/articles/technical/optimized-gradient-border-rendering-in-imperator-rome.html), 03.01.2020, Paradox-Kooperation. Spiel- und Hardwarebezug wie im Artikel beschrieben.
5. Asirvatham & Hoppe, [Terrain Rendering Using GPU-Based Geometry Clipmaps](https://hhoppe.com/proj/gpugcm/), *GPU Gems 2*, 2005; dort liegen Paper, Talk und Demo.
6. Clasen & Hege, [Terrain Rendering using Spherical Clipmaps](https://doi.org/10.2312/VisSym/EuroVis06/091-098), EuroVis 2006.
7. Dimitrijević & Rančić, [Ellipsoidal Clipmaps – A planet-sized terrain rendering algorithm](https://doi.org/10.1016/j.cag.2015.06.006), 2015.
8. Dimitrijević & Rančić, [High-performance Ellipsoidal Clipmaps](https://doi.org/10.1016/j.gmod.2023.101209), *Graphical Models*, 2023.
9. Dick, Schneider & Westermann, [Efficient Geometry Compression for GPU-based Decoding in Realtime Terrain Rendering](https://doi.org/10.1111/j.1467-8659.2008.01298.x), *Computer Graphics Forum*, 2009.
10. Apple, [Tailor your apps for Apple GPUs and tile-based deferred rendering](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering).
11. Apple, [`MTLStorageMode.memoryless`](https://developer.apple.com/documentation/metal/mtlstoragemode/memoryless).
12. Croci, Amirghdam & Pajarola, [Terrender: A Web-Based Multi-Resolution Terrain Rendering Framework](https://doi.org/10.1145/3564533.3564567), Web3D 2022, Autoren-/Institutionsseite mit Paper.
13. Lee, Zeichner & Li, [A Texture Streaming Pipeline for Real-Time GPU Ray Tracing](https://doi.org/10.1145/3721239.3734098), SIGGRAPH 2025 Talks; Autoren-Publikationsseite/Paper.
14. Erler et al., [LidarScout: Direct Out-of-Core Rendering of Massive Point Clouds](https://doi.org/10.2312/hpg.20251170), High-Performance Graphics 2025; Institutsseite mit Paper.
15. Apple, [Metal Feature Set Tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf), Tabelle datiert 21.05.2026.
16. Apple, [Detecting GPU features and Metal software versions](https://developer.apple.com/documentation/metal/detecting-gpu-features-and-metal-software-versions).
17. Apple, [Managing sparse texture memory](https://developer.apple.com/documentation/metal/managing-sparse-texture-memory) und [Streaming large images with Metal sparse textures](https://developer.apple.com/documentation/metal/streaming-large-images-with-metal-sparse-textures).
18. Apple, [Indirect command encoding](https://developer.apple.com/documentation/metal/indirect-command-encoding); capability- und workloadabhängige Option, keine Kit-Baseline.
19. Grenier et al., [Real-time Terrain Enhancement with Controlled Procedural Patterns](https://doi.org/10.1111/cgf.14992), *Computer Graphics Forum* 43(1), 2024; für quellgebundene Geografie ausgeschlossen, weil es neue kontrollierte Reliefdetails synthetisiert.
20. Schott et al., [Terrain Amplification using Multi-scale Erosion](https://research.adobe.com/publication/terrain-amplification-using-multi-scale-erosion/), SIGGRAPH 2024; gleiche Ausschlussbegründung.
21. [Entwurf einer GPU-Driven Terrain-Rendering-Methode](https://elib.spbstu.ru/dl/3/2026/vr/vr26-1679.pdf/info), Abschlussarbeit/Thesis-Seite der SPbPU, 2026; Suchhinweis, kein begutachteter Proceedings-/Journalbeleg für diesen Entscheid.

Die Leistungswerte in historischen Papers und Herstellerbeispielen beschreiben
deren jeweilige Testhardware und Szene. Sie sind keine Zielwerte oder
Leistungsversprechen für dieses Projekt.
