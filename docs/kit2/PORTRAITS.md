# Portraits der Menschen (Kit 2)

Status: **implementiert** (Rust geprüft, Godot-Fenster in der Cloud mit
Forward+ und Compatibility gerendert, noch nicht auf dem Mac gespielt),
30.10.2026.

Ramon, 29./30.10.2026: „könntest du einen minimalistischen ck3 style
charakterportrait generator machen mit mir“, „die bestmögliche poly grafik
wollen wir“. Entworfen in der Portrait-Werkstatt im Browser
(https://claude.ai/artifact/JebbURXz29FK155RntzXLL, Runden 1–7); Ramon wählte
am 30.10.2026 auf der Karte „weitere Ideen“ alle vier Punkte (a–d), d heisst:
Gene in die Simulation, Portrait im Personenfenster.

## Was gebaut ist

- **Gene** (`sim/src/dna.rs`): jede Person trägt 34 Gene mit je zwei Allelen
  zu einem Byte (68 Bytes, Komponente `Dna`). Sichtbar ist der Mittelwert. Ein
  Kind nimmt je Gen ein Allel vom Vater und eines von der Mutter, jedes um eine
  kleine Mutation verschoben (Mittel ±5, höchstens ±15), wie in der Werkstatt.
  Gründer (Start) ziehen Haut, Haar, Augen, Locken und Grundtyp aus Spannen
  ihrer Herkunft (Italia, Gallia, Germania, Graecia, Syria, Aegyptus, Africa),
  die übrigen Gene um die Mitte. Die Herkunft folgt dem Wohnort (Längen- und
  Breitengrad der Zelle). Die Gene sind eine Gestaltungsentscheidung (die
  Morph-Ziele des Grundmodells), kein Modell der menschlichen Genetik: keine
  Dominanz, keine Kopplung. Die Simulation tut sonst nichts mit ihnen; sie
  hängen nur am Zufall `rnd(seed, pid, …)`, Spielstände (Befehlsprotokoll)
  ergeben dieselben Gene.
- **Portraitbau** (`sim/portrait`, Crate `apoleia-portrait`): die Werkstatt
  nach Rust übertragen. Kopf und Schultern des MakeHuman-Grundmodells (CC0,
  `app/assets/portrait/`), gemorpht nach Genen, Alter, Stimmung und Leben;
  Haut mit Lippen, Brauen, Stoppeln, Falten und Narben; Augen; Männerhaar als
  Strähnen mit Wuchsrichtung; Bärte als geformte Masse im Zylinderraster;
  Frauenhaar als gewellte Strähnenbänder vom Mittelscheitel zu Nackenknoten,
  Scheitelzopf oder Schleier (Palla); Kleidung als Schalen; Kopfbedeckung und
  Schmuck nach Stand. Rund 7'000–11'500 Dreiecke, 5–7 ms pro Portrait (Cloud,
  Release).
- **Brücke** (`sim/godot/src/portrait.rs`): `take_person` liefert zusätzlich
  `dna` (68 Bytes) und `origin`. Die Klasse `ApoleiaPortrait` lädt den Kopf
  einmal und baut daraus ein `ArrayMesh` mit einem Material pro Oberfläche.
- **Fenster** (`app/scripts/ui/portrait_view.gd`, `person_window.gd`): das
  Portrait in einem eigenen kleinen 3D-Raum mit dem Licht der Werkstatt
  (Führungslicht mit Schatten von links oben, kühles Gegenlicht, warmes
  Fülllicht, Himmel und Erde), 112 × 140 Punkte unter einem Bogen mit Goldrand,
  der Hintergrund nach Stand, die Medaille der Schicht auf der Ecke. Ohne Gene
  (oder ohne Erweiterung) bleibt die Medaille wie bisher.

## Kinder (Runde 8, 30.10.2026)

Ramon, 30.10.2026: auf der Karte „nächste Runde“ alle vier Punkte („gerne
alles“), zuerst echte Kindergesichter. Vorher sahen Kinder wie kleine
Erwachsene aus.

- **Form**: MakeHumans Baby (ein Jahr) und Kind (elf Jahre) gemischt, das Baby
  höchstens zu zwei Dritteln (mehr gibt dem Gesicht eine Schnauze und faltet
  die Arme in die Brust). Dazu das Kindchenschema (Lorenz, 1943; Glocker et
  al., 2009) als Verschiebung der Gesichtsgene (`look::KID`): runder Kopf, hohe
  Stirn, kleines Kinn, kleine Nase und kleiner Mund, volle Wangen, grosse und
  offene Augen, kurzer Hals; die eigenen Gene zeigen sich gedämpft. Beides
  wächst sich aus bis 15 (Mädchen) oder 17 (Knaben), `Look::grown`.
  PLACEHOLDER: die Stärken sind nach Augenmass gesetzt.
- **Gesicht**: feinere und hellere Brauen, Iris und Pupille füllen mehr vom
  Auge, ein leichtes Lächeln statt der Schmollmund der Vorlage.
- **Haar**: unter drei Jahren kurzes, feines Haar, auch bei Mädchen.
- **Wickelbänder**: im ersten Jahr ist das Kind bis zum Hals in Leinenbänder
  gewickelt (*fasciae*; Soranus, *Gynaecology* 2.14–15).
- **Bulla und Lunula**: freie Kinder ab anderthalb Jahren tragen ein Amulett
  an einer Schnur, Knaben die runde Bulla bis 16 (bis zur Männertoga),
  Mädchen die mondförmige Lunula bis 13; Gold im Dekurionen- und
  Senatorenstand, Bronze bei Handwerkern und Händlern, Leder bei den Armen
  („nodus tantum et signum de paupere loro“, Juvenal, *Satiren* 5.165).
  Kinder von Unfreien tragen keines. Mädchen unter 13 tragen sonst keinen
  Schmuck.
- `app/assets/portrait/head.bin.zst` enthält dafür die Baby-Ziele von
  MakeHuman (391 statt 369 Ziele, 1,1 MB). Die Werkstatt im Browser hat das
  alles noch nicht.

## Was aus der Simulation kommt

| Im Gesicht | Aus der Simulation | Regel |
|---|---|---|
| Gesicht, Haut, Haar, Augen, Glatze, Ergrauen, Bartwuchs | Gene (`Dna`) | Mittel der Allele |
| Alter (Kindergesicht, Falten, dünnere Lippen) | Geburtstag | wie Werkstatt |
| Hunger (hohle Wangen, fahle Haut, schmaler Hals), Körperfülle | Gewicht in ‰ (S84) | Ernährung = 0,55 + (Gewicht − 1000) / 500; sichtbar ab rund 935 ‰ |
| grimmiger Blick | Haushalt isst unter 90 % des Bedarfs (`fed`) | sonst ruhig, jede dritte Person zufrieden |
| Bräune, Falten durch Sonne | Beruf | Anteil draussen je Beruf (PLACEHOLDER) |
| Kleidung, Hut, Schmuck, Bartmode | Stand und Beruf | siehe unten |
| Bartmode häufiger voll | Herkunft Graecia, Syria, Aegyptus | wie Werkstatt |

Stand und Beruf auf die sieben Bilder der Werkstatt (PLACEHOLDER): Senatoren →
Senator, Ritter → Dekurio (schmaler Purpurstreifen), Unfreie → Sklave, Bauern
und Pächter → Bauer, Tagelöhner auf dem Land → Bauer, in der Stadt →
Handwerker, Handwerker, Soldaten und Offiziere → Handwerker (bis es Rüstungen
gibt), Händler, Unternehmer, Beamte, Gelehrte, Geistliche und Adel → Händler.

PLACEHOLDER (unbelegt): die Spannen der Herkunft, die Grenzen der Herkunftsgebiete,
der Anteil draussen je Beruf, Narben per Zufall je Beruf (die Simulation kennt
keine Verletzungen), keine Krankheit (die Simulation kennt keine).

## Daten und Lizenz

`app/assets/portrait/head.bin.zst` (1,0 MB) entsteht mit
`tools/portrait/build_head.js` aus dem MakeHuman-Grundmodell und seinen
Morph-Zielen (CC0, `app/assets/portrait/LICENSE.md`). Es ist dasselbe wie die
Datei der Werkstatt, dazu seit Runde 8 die Baby-Ziele: 7'001 Punkte, Körper
in vier Stufen (1'400, 3'000, 6'000, 11'160 Dreiecke), 391 Morph-Ziele.

## Mit der Werkstatt vergleichen

`cargo run --release -p apoleia-portrait --example portrait_dump -- out.json`
schreibt acht Testpersonen mit ihren Dreiecken. Eine Kopie der Werkstatt, die
eine Person von aussen setzen und fremde Dreiecke zeichnen kann, zeigt beide
nebeneinander: am 30.10.2026 gleich, mit derselben Zahl Dreiecke (ausser dem
Lorbeerkranz, den die Werkstatt mit 26 statt 25 Blättern zählt).

## Licht in Godot

Am 30.10.2026 mit Godot 4.7.2 in der Cloud geprüft (Forward+ über Mesas
Software-Vulkan, dazu Compatibility über OpenGL): dieselben Dreiecke in Godot
und in der Werkstatt nebeneinander.

- Die Vertexfarben gehen in sRGB nach Godot, mit `SRGB_VERTEX_COLOR`. Lineare
  Farben ohne die Fahne zeichnet Forward+ richtig, Compatibility aber viel zu
  dunkel und rot, weil es sie wie sRGB behandelt.
- Tonemapping: Godots ACES ist dieselbe Kurve wie die von three.js r128, aber
  mit Belichtung × 1,8 statt ÷ 0,6 und geteilt durch den Wert des Weisspunkts.
  `portrait_view.gd` setzt darum die Belichtung auf 0,92 / 0,6 / 1,8 und den
  Weisspunkt auf 14,26 (dort ist sein Wert 1). Damit decken sich Forward+ und
  Werkstatt; Compatibility bleibt etwas satter.

## Offen

- Im Spiel auf dem Mac ansehen (Metal statt Vulkan).
- Werkstatt und Rust-Code sind zwei Kopien; Änderungen am Aussehen zuerst in
  Rust, die Werkstatt dann nachziehen (oder später die Werkstatt aus Rust über
  WebAssembly bauen).
- Namen, Dynastien, Eigenschaften (CK3) gibt es noch nicht.

## Literatur

Zitate aus dem Gedächtnis, nicht online geprüft.

- Glocker, M. L., Langleben, D. D., Ruparel, K., Loughead, J. W., Gur, R. C.,
  & Sachser, N. (2009). Baby schema in infant faces induces cuteness
  perception and motivation for caretaking in adults. *Ethology, 115*(3),
  257–263. https://doi.org/10.1111/j.1439-0310.2008.01603.x
- Juvenal. (2004). *Juvenal and Persius* (S. M. Braund, Ed. & Trans.; Loeb
  Classical Library 91). Harvard University Press.
- Lorenz, K. (1943). Die angeborenen Formen möglicher Erfahrung.
  *Zeitschrift für Tierpsychologie, 5*(2), 235–409.
  https://doi.org/10.1111/j.1439-0310.1943.tb00655.x
- Soranus. (1956). *Soranus' gynecology* (O. Temkin, Trans.). Johns Hopkins
  University Press. (Original work published ca. 100 CE)
