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

## Trauer, Geld, Kleidung und Alter (Runde 8, 30.10.2026)

Der zweite Punkt von „gerne alles“: mehr vom Leben im Gesicht, alles aus dem,
was die Simulation schon rechnet (nichts Neues in der Simulation).

- **Trauer**: stirbt jemand im Haushalt (Todesfall oder Hungertod in den
  Ereignissen der Simulation, `events::DEATH`, `events::HUNGER_DEATH`), trauern
  die anderen: trauriger Blick, Tränensäcke und gerötete Lider, dunkle
  Kleidung (*vestis pulla*), Frauen unter dem Schleier und ohne Schmuck,
  Männer unrasiert (Stoppeln statt glatt). 20 Tage voll, dann schwächer bis
  zum 60. Tag, so weit die Simulation ihre Ereignisse behält
  (`events::KEEP_DAYS`). Im Personenfenster steht „In Trauer: Todesfall im
  Haushalt vor N Tagen“. PLACEHOLDER: in Rom trauerte eine Witwe zehn Monate
  (Plutarch, *Numa* 12; Toynbee, 1971), länger als die Ereignisse
  zurückreichen. Wer beim Tod des Vaters einen eigenen Haushalt bekommt
  (Erbteilung, S83), trauert nicht mit, weil der Tod beim alten Haushalt steht.
- **Geld**: der Rang des Haushalts nach Geld je Kopf am Markt (sonst auf der
  Karte) färbt die Kleidung: die ärmsten 35 % tragen ausgebleichtes, graues
  Tuch, die reichsten 30 % kräftigere Farben. PLACEHOLDER (Augenmass).
- **Abgetragene Kleidung**: so weit dem Haushalt Kleidung fehlt
  (`clothes_pct` unter 100 %), ist das Tuch verblichen und geflickt (Flicken
  aus einem anderen Tuch des Standes). Viele Bauernhöfe haben in den ersten
  Jahren 0 % (sie bekamen beim Start keine Kleidung und weben selbst), sie
  sehen deshalb geflickt aus.
- **Alter**: Ohren und Nase wachsen ab 40 weiter, die Nasenspitze sinkt
  (Heathcote, 1995; Sforza et al., 2009, 2011); ab 50 Altersflecken auf Stirn,
  Schläfen und Wangen, mehr nach Jahren an der Sonne. PLACEHOLDER: die Stärken
  nach Augenmass.
- `ApoleiaPortrait.build` nimmt jetzt das ganze Wörterbuch von
  `take_person` (statt zehn einzelner Werte), damit auch andere Fenster ein
  Gesicht bauen können, mit dem, was sie wissen.

## Gesichter überall (Runde 8, 30.10.2026)

Der dritte Punkt von „gerne alles“.

- **Ein Speicher für alle Gesichter** (`app/scripts/ui/portrait_cache.gd`):
  eine kleine 3D-Welt rendert ein Gesicht pro Bild und behält es als Textur
  mit Mipmaps, die letzten 64. Das Personenfenster, die Haushaltsliste, die
  Ereignisfenster und die Hinweise zeichnen alle daraus
  (`portrait_view.gd` nur noch als Bogen mit Goldrand um die Textur). Der
  Schlüssel ist die Person mit allem, was ihr Gesicht ändert: Alter in
  Jahren, Trauer nach Wochen, Gewicht, Hunger, Kleidung und Rang in Stufen.
- **Haushaltsliste**: jedes Mitglied mit seinem Gesicht; ein Klick öffnet
  die Person (`member_chosen`). `take_person` gibt dafür jedem Mitglied seine
  Gene und Herkunft mit.
- **Ereignisfenster**: die Beteiligten bekommen das Gesicht ihres Haushalts
  über ihrem Namen (das Mitglied, das der Link öffnet); ein Klick darauf
  öffnet es. Neu: `ApoleiaPeople.ask_faces(households)` und `take_faces()`.
- **Hinweise**: eine Zeile für genau ein Ereignis eines Haushalts, den es
  danach noch gibt (Umzug, zu Verwandten, Diebstahl, Almosen, Zelt zieht um,
  Hof übernommen, Erbteil, ins Zelt, Lex Manciana), zeigt im Medaillon das
  Gesicht statt des Zeichens. Zeilen für mehrere Ereignisse, Hungertod und
  verlassene Höfe behalten das Zeichen.

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
| Trauer (Blick, Lider, dunkle Kleidung, Schleier, Stoppeln) | Tod im Haushalt in den letzten 60 Tagen | voll 20 Tage, aus bei 60 |
| Farbe der Kleidung | Rang nach Geld je Kopf (`rank_market`, sonst `rank_all`) | blass unter 35 %, kräftig über 70 % |
| Verblichen und geflickt | Kleidung des Haushalts (`clothes_pct`) | fehlender Anteil |

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

## Hüte, neu gebaut (31.10.2026)

Ramon, 31.10.2026, zum Personenfenster: „das sieht aus als hätte jemand einen
heiligenschein. kopfbedeckungen haare sind leider noch müll“. Der Strohhut war
eine flache, dünne Krempe ohne sichtbare Krone; von leicht oben gesehen
umrahmte sie den Kopf als heller Ring. Seither weicht Rust von der Werkstatt
ab:

- **Strohhut (Petasos):** runde Krone mit dunkler oder roter Kordel, Krempe
  mit Ober- und Unterseite und Rand, hinten tiefer hängend als vorne, Ringe aus
  hellem und dunklem Stroh.
- **Filzkappe (Pileus):** Rollrand und hohe, runde Kegelform, leicht nach
  hinten geneigt, in vier Filzfarben.
- **Pannonische Mütze:** 32 statt 16 Seiten, oben leicht weiter und gerundet,
  abgesetzter Rand.
- **Lorbeerkranz:** zwei Zweige von hinten zur Stirn, Blätter paarweise nach
  vorne, mit gefalteter Mittelrippe, auf dem Haar sitzend wie ein Hutband
  (vorher schwebte er hinten über dem Kopf).
- Unter Hut und Kappe wachsen keine Haarsträhnen mehr durch die Krone.

Schnellvorschau ohne Spiel:
`cargo run --release -p apoleia-portrait --example portrait_sheet -- out.json hats`
(auch `hair`, `men` und `kids`) schreibt Hüte und Frisuren als Dreiecke für
ein Kontaktblatt.

## Haare als geformte Masse (31.10.2026)

Ramon wählte am selben Morgen „Geformte Masse wie die Bärte“: Haar als
Volumen mit Dicke und geschnittenen Strähnen statt einzelner Stäbe. Seither
weicht Rust auch hier von der Werkstatt ab.

- **Männer und Knaben** (`cap_hair` in `sim/portrait/src/build.rs`): eine
  Haarkappe von 96 Spalten und 12 Ringen, die vom Wirbel am Hinterkopf zur
  Haarlinie läuft. Die Spalten sind zu Strähnen von drei bis sechs Spalten
  gebündelt; jede Strähne endet an der Stirn in einer Spitze, hat einen
  Grat in der Mitte und ein eigenes Licht. Die Haarlinie folgt einer Tabelle
  über den Winkel um den Kopf: Stirn, Geheimratsecken, Schläfe, Koteletten
  vor dem Ohr, Bogen über dem Ohr, Nacken. Sie wird aus dem gemessenen Ohr
  jedes Kopfes gesetzt.
- **Glatze und Locken** kommen aus den Genen `BALD` und `CURL`: die
  Geheimratsecken weichen zurück, ab etwa der Hälfte öffnet sich die Platte
  oben, bis ein Kranz bleibt; Haarinseln werden entfernt. Leichte Locken
  wellen die Strähnen, starke Locken werden zu einer dichten Masse aus kleinen
  Knoten. Kinder haben dünneres Haar.
- **Frauen:** Mittelscheitel, Strähnen in Bändern mit Grat und Licht, mehr
  Volumen über den Ohren, Wellen nach hinten; der Zopf liegt als
  Flechtenkamm sichtbar auf dem Scheitel. Die spätrömische „Helmfrisur“ ist
  absichtlich kappenförmig, wirkt aber noch zu glatt (offen).
- **Kopfhaut finden:** Der nächste Treffer eines Strahls vom Kopfmittelpunkt
  liegt oft innen (Augenhöhlen), darum lagen Schläfenhaare unter der Haut.
  `outer_skin` nimmt den äussersten Treffer, ausser er liegt weiter als
  1,2 Kopfgrössen draussen (Schulter).

Vorher und nachher in Godot: `/mnt/project-files/portraits/haare-vorher-nachher.png`.

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
- Namen um 300 gibt es (NAMES.md); Dynastien und Eigenschaften (CK3) noch
  nicht.
- Die Werkstatt hat weder die Kinder noch Trauer, Geld, Flicken,
  Altersflecken, die neuen Hüte und die geformten Haare.
- Frauenhaar: noch zu glatt und kappenförmig; der Knoten im Nacken ist von
  vorne nicht zu sehen.
- Die Gesichter der Hinweise sind klein (30 Pixel); ob sie dort helfen, muss
  sich im Spiel zeigen.

## Literatur

Zitate aus dem Gedächtnis, nicht online geprüft.

- Glocker, M. L., Langleben, D. D., Ruparel, K., Loughead, J. W., Gur, R. C.,
  & Sachser, N. (2009). Baby schema in infant faces induces cuteness
  perception and motivation for caretaking in adults. *Ethology, 115*(3),
  257–263. https://doi.org/10.1111/j.1439-0310.2008.01603.x
- Heathcote, J. A. (1995). Why do old men have big ears? *BMJ, 311*(7021),
  1668. https://doi.org/10.1136/bmj.311.7021.1668
- Juvenal. (2004). *Juvenal and Persius* (S. M. Braund, Ed. & Trans.; Loeb
  Classical Library 91). Harvard University Press.
- Lorenz, K. (1943). Die angeborenen Formen möglicher Erfahrung.
  *Zeitschrift für Tierpsychologie, 5*(2), 235–409.
  https://doi.org/10.1111/j.1439-0310.1943.tb00655.x
- Plutarch. (1914). *Lives, Volume I: Theseus and Romulus. Lycurgus and
  Numa. Solon and Publicola* (B. Perrin, Trans.; Loeb Classical Library 46).
  Harvard University Press.
- Sforza, C., Grandi, G., Binelli, M., Tommasi, D. G., Rosati, R., &
  Ferrario, V. F. (2009). Age- and sex-related changes in the normal human
  ear. *Forensic Science International, 187*(1–3), 110.e1–110.e7.
- Sforza, C., Grandi, G., De Menezes, M., Tartaglia, G. M., & Ferrario, V. F.
  (2011). Age- and sex-related changes in the normal human external nose.
  *Forensic Science International, 204*(1–3), 205.e1–205.e9.
- Soranus. (1956). *Soranus' gynecology* (O. Temkin, Trans.). Johns Hopkins
  University Press. (Original work published ca. 100 CE)
- Toynbee, J. M. C. (1971). *Death and burial in the Roman world*. Thames
  and Hudson.
