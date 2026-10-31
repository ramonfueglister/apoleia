# Namen der Menschen (Kit 2)

Status: **Schritt 1 implementiert** (Rust geprüft, 100 Jahre gelaufen,
Godot-Fenster in der Cloud gerendert, noch nicht auf dem Mac gespielt),
30.10.2026.

Ramon, 30.10.2026: „wichtig das system muss namen erlauben bis neuzeit. namen
sind für gruppen und kulture unterschiedlich verändern sich. schlag mir ein
dynamisches system vor“. Vorschlag mit fünf Bausteinen (Namensgut,
Namensordnung, Namenswahl, Beinamen aus dem Leben, Linien mit Familiennamen):
https://claude.ai/artifact/U712QGBqx82ovwuyFb4Eyd. Ramon wählte am selben Tag
auf der Karte „Womit sollen wir bei den Namen anfangen?“ die Option „Schritt 1:
Namen um 300“: Namensgut, Namenswahl und Linien für die sieben
Herkunftsgebiete um 300, sichtbar im Personenfenster, in der Haushaltsliste,
in Ereignissen und Hinweisen (S128).

Die Paradox-Spiele ziehen Namen aus festen Listen je Kultur (CK3 mit einer
Chance auf den Namen von Vater oder Grosseltern; EU5 und Victoria 3 nur für
Figuren, nicht für Pops; aus dem Gedächtnis, nicht online geprüft). Bei uns hat
jeder der rund 117'000 Menschen einen Namen, und Häufigkeit und Mode entstehen
aus den Entscheidungen der Eltern.

## Was gebaut ist

- **Namensgut** (`sim/data/names/c0300.tsv`, 360 Zeilen): 279 Rufnamen
  (lateinisch, griechisch, aramäisch, ägyptisch, keltisch, germanisch,
  punisch, libysch, thrakisch, illyrisch), 25 germanische Namenglieder, aus denen beim Laden
  zweigliedrige Namen werden (Theude- + -mer), 29 Familiennamen (Gentilnamen,
  mit griechischer Form), 14 Familiennamen von Senatoren- und Rittergeschlechtern,
  8 Vornamen (Praenomina). Jeder Name trägt seine Glieder, die er mit
  verwandten Namen teilt (Victor, Victorinus, Victoria teilen VICT), und ein
  Gewicht je Herkunft (Italia, Gallia, Germania, Graecia, Syria, Aegyptus,
  Africa wie `crate::dna::ORIGINS`). Eine neue Epoche oder Kultur ist eine neue
  Datei, kein neuer Code.
- **Namensordnung** (Zeile `order` der Datei): welche Teile ein voller Name hat.
  Lateinischer Westen und Africa `P?NG`: Vorname nur bei Senatoren und Rittern,
  Familienname vom Vater, Rufname (Aurelia Sabina, Marcus Aurelius Victor).
  Graecia und Aegyptus `HGF`: Familienname in griechischer Form, Rufname,
  Vatersname im Genitiv (Aurelios Dionysios Apolloniou). Syria `HGB`: dazu
  „bar/bat“ und Vatersname (Aurelia Martha bat Malku). Nach der Constitutio
  Antoniniana (212) tragen viele Neubürger den Familiennamen Aurelius; die
  Bauart folgt Salway (1994).
- **Linien** (`Names::lines`): Jede Person gehört zur Linie ihres Vaters und
  trägt deren Familiennamen; eine Frau behält ihren bei der Heirat (Salway,
  1994). In der Startbevölkerung ist jeder Haushalt eine Linie (30'865
  Linien), Senatoren und Ritter bekommen den Namen eines grossen Geschlechts
  und einen Vornamen. Eine Linie stirbt aus, wenn kein Mann sie weitergibt
  (Galton & Watson, 1875).
- **Namenswahl bei jeder Geburt** (`Names::birth`). Die Eltern wählen der Reihe
  nach, mit Anteilen je Herkunft aus der Datei (`param`, PLATZHALTER):
  1. *Verwandte* (`kin`, 20 bis 45 %): ein Sohn nach dem Grossvater väterlich,
     dem Vater oder dem Grossvater mütterlich (Gewichte 3, 2, 1), eine Tochter
     nach der Grossmutter väterlich, der Mutter oder der Grossmutter mütterlich.
     Nachbenennung nach dem Grossvater (Papponymie) ist im Osten häufiger.
     Ein Verwandter, der in den letzten drei Jahren starb, zählt 2,7-mal: so
     oft gaben französische Eltern dem Sohn den Namen des Vaters, wenn dieser
     in der Schwangerschaft gefallen war (Todd & Coulmont, 2021). Ein Name des
     anderen Geschlechts wird zur passenden Form desselben Stamms (Victor gibt
     Victoria).
  2. *Abgeleitet* (`var`, 5 bis 25 %): ein Name, der ein Glied mit dem eines
     Verwandten teilt: Victorinus nach Victor, wie die abgeleiteten
     lateinischen Beinamen (Kajanto, 1965), Theudericus nach Theudemer, wie
     die germanische Variation (Mitterauer, 1993).
  3. *Abgeschaut*: sonst ein Name, den andere in den letzten Jahren gaben,
     zur Hälfte aus der eigenen Region (die letzten 48 Geburten),
     sonst aus der ganzen Kultur (Geburten der letzten rund zehn Jahre,
     jedes Jahr um den Faktor 1/e pro zehn Jahre vergessen). Zufälliges
     Abschauen erklärt schon viel von der Verteilung der Namen (Hahn &
     Bentley, 2003). Jede Geburt zählt nach dem Stand des Vaters (Land 1,
     Stadt 2, Ritter 6, Senator 12): was oben gegeben wird, sickert nach unten
     (Lieberson, 2000). Seltene Namen gewinnen, häufige verlieren: die
     Selektion je Jahr ist s = −0,015 · (log10 Anteil + 3), begrenzt auf
     ±3 %, das gibt um 1 von 10'000 rund +1,5 % und über 1 von 100 rund
     −1,5 % (Newberry & Plotkin, 2022, gemessen +1,4 % und −1,6 %); im Pool
     von zehn Jahren wird daraus das Gewicht 1 + 10 · s.
  4. *Selten alt* (`innov`, 2 %): ein Name aus dem Namensgut nach seinem
     Gewicht, auch einer, den gerade niemand gibt.

  Kein lebendes Geschwister bekommt denselben Namen. Mit einer Chance von
  25 % (PLATZHALTER) wählen die Eltern aus der Kultur der Mutter; die Linie
  bleibt die des Vaters. So mischen sich Namen, wo Herkunftsgebiete
  aneinanderstossen.
- **Anzeige.** Personenfenster: voller Name als Titel, darunter eine Karte
  „Name“ mit jedem Teil und seiner Herkunft („Rufname, nach dem Grossvater
  väterlicherseits, verstorben“, „Familienname der Linie, vom Vater geerbt“)
  und der Linie („Linie der Aurelii, 12 leben“, mit Gründer und Jahr im
  Hinweis). Haushaltsliste: Name und darunter Rolle, Alter und Beruf.
  Ereignisfenster, Hinweise und die Szenen auf der Karte nennen die Menschen
  beim Namen („Trauerzug für Aurelius Felix, 64 Jahre alt“, „Hochzeitszug:
  Valeria Prima zieht ins Haus des Iulius Secundus“). Rust:
  `view::Person::shown`, Godot: `take_person` mit `name`, `name_parts`,
  `line`, `line_members`, `line_since`.
- **Bestimmtheit und Kosten.** Namen ziehen aus eigenen Zufallszahlen
  (`NAME_SALT`), die übrige Simulation läuft gleich: die Fingerabdrücke nach
  10 Jahren sind dieselben wie ohne Namen. Ein geladener Spielstand
  (Befehlsprotokoll) ergibt dieselben Namen. Start 17 ms für 116'805
  Menschen (Cloud, Release), eine Wahl je Geburt (rund 14 am Tag), kein
  messbarer Tagesaufwand. Je Person 20 Bytes.

## Lauf über 100 Jahre

`cargo run --release --example names_run -- --years 100 --csv names.csv`
(Seed 1, Cloud, Stand mit S127):

509'170 Geburten in 100 Jahren. Die Wahl bleibt über die 100 Jahre fast gleich:
Verwandte 30 %, abgeleitet 8 %, Nachbarschaft 31 %, Kultur 31 %, selten alt
1 %.

Häufigste Namen im zehnten Jahrzehnt (Anteil an den Geburten der Herkunft):

| Herkunft | Männer | Frauen |
|---|---|---|
| Italia | Primus 3,1 %, Felix 2,9 %, Primitivus 2,8 % | Victoria 3,8 %, Prima 3,3 %, Paulina 3,3 % |
| Gallia | Secundus 3,3 %, Primitivus 3,2 %, Secundinus 2,9 % | Secundina 4,4 %, Victorina 4,2 %, Secunda 4,0 % |
| Germania | Secundus 3,5 %, Maximinus 3,2 %, Victorinus 3,2 % | Secunda 4,0 %, Prima 3,4 %, Secundina 3,3 % |
| Graecia | Hermes 4,7 %, Apollonios 4,7 %, Dionysios 4,5 % | Ammia 7,2 %, Eirene 7,1 %, Aphrodisia 5,8 % |
| Syria | Zabdibol 4,5 %, Malku 4,2 %, Iarhibola 4,2 % | Martha 10,0 %, Aqmat 6,9 %, Miryam 6,5 % |
| Aegyptus | Horion 5,9 %, Sarapion 5,7 %, Ammonios 5,4 % | Tapsais 7,3 %, Apollonia 6,5 %, Taesis 6,2 % |
| Africa | Saturninus 5,7 %, Victor 3,6 %, Saturus 3,1 % | Felicitas 4,5 %, Felicula 3,9 %, Victoria 3,7 % |

- **Mode wandert langsam.** Von den fünf häufigsten Namen des ersten
  Jahrzehnts sind nach 90 Jahren im Mittel drei noch unter den ersten fünf,
  von den ersten zehn knapp sieben. In Syria fällt Malku von 6,3 % auf den
  zweiten Platz, in Graecia steigt Hermes an die Spitze, in Aegyptus
  Tapsais. Die Nachbenennung nach den Grosseltern hält Namen in der Familie,
  die Bremse hält jeden Namen unter rund 12 % (am höchsten Martha in Syria,
  12,2 % im ersten Jahrzehnt, 10,0 % im letzten).
- **Vielfalt wächst.** Italia gibt Männern im ersten Jahrzehnt 95
  verschiedene Namen, im letzten 128; Graecia 71 und 122, Syria den Frauen 30
  und 48. Das kommt aus den seltenen alten Namen (2 %) und der Bremse, die
  Seltenes bevorzugt. Ob das zu viel ist, zeigt erst ein Vergleich mit
  Zählungen (Trismegistos, LGPN).
- **Linien sterben aus.** 30'865 Linien am Start, 28'578 nach 10 Jahren,
  13'089 nach 100 (42 %); die grösste hat 78 Lebende. Neue Linien entstehen
  noch nicht (siehe unten).
- Beispiele aus dem Lauf: Caecilia Monnica (Africa, nach der verstorbenen
  Grossmutter), Caecilia Victorina (Germania, abgeleitet vom Namen der
  Grossmutter Aurelia Victoria), Iulius Maximus (Gallia, abgeleitet vom Vater
  Iulius Maximinus), Aurelios Hermogenes Theodorou (Graecia, nach dem
  verstorbenen Grossvater), Klaudia Domna bat Yohanan (Syria), Aurelios
  Zosimos Sarapionos (Aegyptus, in Mode).

## Platzhalter

- Die Gewichte im Namensgut sind Häufigkeitsklassen 1, 2, 4, 8 aus dem
  Gedächtnis nach Kajanto (1965), Salway (1994), dem Lexicon of Greek Personal
  Names und Trismegistos People; noch nicht an Zählungen geeicht.
- Anteile der Wahl je Herkunft (`kin`, `var`, `local`, `innov`), die
  Gewichte der Verwandten (3, 2, 1), das Prestige je Stand (1, 2, 6, 12),
  die Gedächtnisdauer des Pools (zehn Jahre), die Kultur der Mutter (25 %).
- Gemessen und übernommen: 2,7 für einen kürzlich verstorbenen Verwandten
  (Todd & Coulmont, 2021) und die Stärke der Bremse (Newberry & Plotkin, 2022),
  beide aus der Neuzeit auf die Antike übertragen.

## Was noch fehlt

- **Neue Linien.** Linien entstehen nur am Start; Zuwanderer, Freigelassene
  und Kinder ohne bekannten Vater gründen noch keine. Darum sterben Linien nur
  aus.
- **Schritt 2:** Beinamen aus dem Leben (Beruf, Ort, Vater, Aussehen aus den
  Genen), Statistik „Namen“ und eine Kartenart.
- **Schritt 3:** Wandel der Namensordnung aus einem Druck je Markt und Stand
  (Verwaltung, Erbe, Namensdichte, Religion, Kontakt, Gesetz), als
  Schwellenmodell (Granovetter, 1978); auch der Zerfall der drei Namen nach
  212.
- **Schritt 4:** spätere Epochen als Datenpakete (Frühmittelalter,
  Hochmittelalter, Neuzeit).
- Biblische und christliche Namen haben bei Newberry und Plotkin (2022) einen
  eigenen Vorteil; bei uns erst, wenn die Simulation Glauben kennt.

## Literatur

Die mit Link sind online geprüft, die übrigen aus dem Gedächtnis und nicht
online geprüft.

- Galton, F., & Watson, H. W. (1875). On the probability of the extinction of
  families. *The Journal of the Anthropological Institute of Great Britain and
  Ireland, 4*, 138–144.
- Granovetter, M. (1978). Threshold models of collective behavior. *American
  Journal of Sociology, 83*(6), 1420–1443.
- Hahn, M. W., & Bentley, R. A. (2003). Drift as a mechanism for cultural
  change: An example from baby names. *Proceedings of the Royal Society B:
  Biological Sciences, 270*(Suppl. 1), S120–S123.
- Kajanto, I. (1965). *The Latin cognomina*. Societas Scientiarum Fennica.
- Lexicon of Greek Personal Names. (o. J.). University of Oxford.
- Lieberson, S. (2000). *A matter of taste: How names, fashions, and culture
  change*. Yale University Press.
- Mitterauer, M. (1993). *Ahnen und Heilige: Namengebung in der europäischen
  Geschichte*. C. H. Beck.
- Newberry, M. G., & Plotkin, J. B. (2022). Measuring frequency-dependent
  selection in culture. *Nature Human Behaviour, 6*(8), 1048–1055.
  https://doi.org/10.1038/s41562-022-01342-6
- Salway, B. (1994). What's in a name? A survey of Roman onomastic practice
  from c. 700 B.C. to A.D. 700. *The Journal of Roman Studies, 84*, 124–145.
  https://www.cambridge.org/core/journals/journal-of-roman-studies/article/abs/whats-in-a-name-a-survey-of-roman-onomastic-practice-from-c-700-bc-to-ad-700/E2F5DF37FD63B897098C26A32C7A1738
- Todd, N., & Coulmont, B. (2021). Naming for kin during World War I: Baby
  names as markers for war. *Journal of Interdisciplinary History, 52*(1),
  55–67. https://doi.org/10.1162/jinh_a_01663
- Trismegistos People. (o. J.). KU Leuven.
