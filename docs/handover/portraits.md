# Übergabe: Porträts (Stand 31.10.2026)

Diese Datei soll es einem neuen Claude ermöglichen, die Porträts ohne Vorwissen weiterzubauen, auch von einem anderen Account aus. Sie
fasst zusammen, was in main ist, wie die Pipeline läuft, was offen ist und welche Regeln Ramon gesetzt hat.

## 1. Ziel und Regeln von Ramon

- **Ziel:** realistische Porträts auf CK3/EU5-Niveau, am liebsten Victoria 3. Gebaut wird mit Blender und MakeHuman-Daten (CC0), nach
  Papers und bestehenden Lösungen. Asset-Packs kommen nicht in Frage («keine Asset-Packs»).
- **Arbeitsweise:** Zuerst ein Testbild zeigen (vorher/nachher, in Spielgrösse), Ramon entscheidet über eine Karte, erst dann kommt ein PR.
  Gemergt wird nur auf sein «mergen». Bisher hat er ohne Mac-Test mergen lassen.
- **Umfang:** nur ändern, was besprochen ist, also keine ungefragten Änderungen an Farben, Licht oder Stil.
- **Werte und Quellen:** Werte ohne Quelle als PLACEHOLDER markieren. Literatur in APA 7 angeben, mit «nicht online geprüft», wenn ungeprüft.
- **Zeitspanne:** Alles muss von Rom bis in die Neuzeit tragen. Das gilt auch für Kleider, Frisuren und Namen, damit es um 1900 und bis 2000 passt.
- **Sprache:** Ramon schreibt Schweizerdeutsch. Antworten auf Deutsch mit «ss», kurz, in ganzen Sätzen.

## 2. Was in main ist

| PR | Inhalt |
|----|--------|
| #85 | Gesichter überall (`app/scripts/ui/portrait_cache.gd`), Kinder, Trauer, Alterszeichen im einfachen Look |
| #124 | **Echte Porträts mit Schalter** (S135): Blender-Haar (8 Frisuren), Bärte, Kleider (Tunika, Toga, Palla, Schleier), weiche Haut mit Poren und Röte, Augäpfel mit Iris, Gesichtsgene als Gesichtsraum (um 1,6 überzeichnet, Ausreisser gedämpft), Herkunft aus Howells-Schädeldaten, sanftere Trauer und sanfteres Lächeln |
| #126 | **Alter:** Faltenkarten in 8-Jahres-Stufen, Absacken ab 38, dünneres Frauenhaar, Haarkappe verblasst beim Ergrauen |

- Der Schalter steht unter Einstellungen › Allgemein › «Echte Porträts» und ist standardmässig aus. Gespeichert wird er in
  `user://display.cfg` unter `[portraits] real`.
- Der echte Look geht nur, wenn das Spiel aus dem Quellordner läuft, nicht in einem Export, weil die Dateien über `globalize_path` gelesen werden.
- Weil der Code in Rust ist, braucht jede Änderung einen Neubau auf dem Mac mit `sim/godot/build.sh`.
- **Wichtige Dateien:**
  - `sim/portrait/src/build.rs`: der ganze Aufbau, mit `real_skin`, `mh_hair2`, `mh_cloth` und den Morphs in `morph()`.
  - `sim/portrait/src/real.rs`: Schalter, Dateizugriff, Zeilen-Cache und zstd.
  - `sim/portrait/src/look.rs`: Gene, Stand, Leben und `FACE_MOD`.
  - `sim/src/dna.rs`: `FACE_SHIFT` je Herkunft.
  - `sim/godot/src/portrait.rs`: Materialien und Textur-Cache.
  - `app/assets/portrait/real/`: 147 Dateien, etwa 20 MB, WebP und `.txt.zst`, mit `.gdignore`.
- **Doku:**
  - `docs/kit2/PORTRAITS.md`, Abschnitt «Echte Porträts», mit Literatur und Offenem.
  - `docs/kit2/decisions.md`: S135.
- **Tempo:** Ein einfaches Gesicht braucht 19 ms, ein echtes etwa 45 ms. Die erste Frisur braucht bis 0,4 s. `APOLEIA_TIME=1` druckt die Zeiten.

## 3. Pipeline (`tools/portrait-pipeline/`)

Bis zum 31.10. lag alles nur im Projektordner `/mnt/project-files/portraits/realismus-pipeline/`, der in einem anderen Account
nicht sichtbar ist. Deshalb liegt eine Kopie jetzt im Repo. `LIESMICH.md` dort beschreibt jedes Skript mit Aufruf und Parametern
(Haar, Bärte, Kleider, Haut, Augen, Gesichtsformen, Herkunft, Brauen, Lächeln, Alter).

### Einrichtung in der Cloud

1. **Blender:**
   - Installation: `python3.13 -m venv bpyenv/venv && bpyenv/venv/bin/pip install bpy==5.2.3`.
   - Das ist Blender 5.2.3 LTS als Python-Modul, headless. Ein Blender-MCP braucht es nicht.
   - Skripte mit `import bpy` laufen so: `bpyenv/venv/bin/python skript.py ...`.
2. **MakeHuman-Daten:**
   - Quelle: `git clone https://github.com/makehuman-js/makehuman-data` (CC0). Daraus kommt der Grundkopf `base.obj`
     (MakeHuman-Basismesh mit UVs, 1 Einheit = 10 cm).
   - `convert.py`, `tex.py` und `real_prep.py` machen daraus den Rohordner `mhreal` (etwa 270 MB, nicht im Repo).
   - `files.makehumancommunity.org` ist in der Cloud gesperrt. Dort gibt es nur Hauttexturen in 512 px über den Mirror.
3. **Ins Spiel bringen:**
   - `pack_real.py mhreal app/assets/portrait/real liste.txt` macht WebP-Dateien mit höchstens 1024 px.
   - Textdateien über 64 KB packt `rust-examples/zpack.rs`. Dazu das Beispiel nach `sim/portrait/examples/` kopieren und mit
     `cargo run --release -p apoleia-portrait --example zpack -- datei` ausführen.
4. **Rendern in der Cloud (Godot 4.7.2 Linux):**
   - Vorbereitung: `apt-get install -y --no-install-recommends mesa-vulkan-drivers libvulkan1 xvfb`.
   - Bibliothek bauen: `cargo build --release -p apoleia-godot` im Ordner `sim`, dann `target/release/libapoleia_godot.so` nach `app/bin/` kopieren.
   - Rendern mit `xvfb-run ... Godot --rendering-driver vulkan --path app --script godot-test/beard_compare.gd -- set.json out.png 0,1,...`.
   - Die Skripte `age.sh`, `beard.sh` und `face.sh` tun genau das.
   - Pfade für Ausgabebilder müssen absolut sein, sonst landen sie in `app/`.
   - Testpersonen (JSON) sind `men15.json` und `eyes_b.json`. `extreme_set.py` zieht die extremsten Gründer.
5. **Hartcodierte Pfade:**
   - Die Shell-Skripte erwarten `/home/claude/apoleia` (Repo), `/home/claude/work/mhreal` (Rohdaten) und
     `/home/claude/work/gdbin/Godot_v4.7.2-stable_linux.x86_64`. Das ggf. anpassen.
   - Heruntergeladene Daten gelten als nicht vertrauenswürdig: jeweils eigener Ordner, Python mit `-I`.
6. **Umgebungsvariablen für Tests:**
   - Ohne Schalter: `APOLEIA_REAL`, `APOLEIA_MH_DIR`, `APOLEIA_MH_AUTO`, `APOLEIA_MH_BEARD`, `APOLEIA_MH_CLOTHES`,
     `APOLEIA_REAL_NMAP`, `APOLEIA_REAL_BLEND`, `APOLEIA_REAL_ANISO`, alle mit dem Ordner `app/assets/portrait/real`.
   - Für einzelne Fälle: `APOLEIA_TEST_MOOD`, `APOLEIA_TEST_BEARDS`, `APOLEIA_TEST_VEIL`.
7. **Lokale Rust-Werkzeuge** in `rust-examples/` (bei Bedarf nach `sim/portrait/examples/` kopieren):
   - `target_list.rs`: alle 391 Morph-Ziele.
   - `mask_dump.rs`, `surf_dump.rs`: Masken und Flächen ausgeben.
   - `face_targets.rs`, `target_sym.rs`: Prüfwerkzeuge.
   - `face_measure` liegt schon im Repo.

### Fallstricke

- Haarkarten müssen von aussen gegen den Uhrzeigersinn laufen. Sonst sind sie von innen beleuchtet und es entsteht ein Helm-Glanz.
- Ein neues Material pro Gesicht lässt Godot die Shader neu kompilieren. Deshalb gibt es den Material-Cache mit dem Schlüssel aus Rauheit, Metall, beidseitig, Textur und Normal-Map.
- Feine Zeilenmuster in Stofftexturen flimmern im Porträt.
- Grosse Poren sehen aus wie Fell.
- Bei Männern mit kurzem Haar wirkt Ausdünnen über weggelassene Karten fleckig. Deshalb dünnt nur Frauenhaar aus.

## 4. Offene Liste (Ramons Wahl 17:56, Punkt a ist erledigt)

1. **Frauenfrisuren:** Frauen haben nur Knoten (bun) und Zopf (braid), Männer acht Frisuren. Vorschlag waren etwa vier neue, zum Beispiel
   Mittelscheitel mit Nackenknoten, Lockenkranz, offenes Haar bei Mädchen und Schleier über dem Knoten. Vorgehen wie bei `gen_bun.py` und
   `hairlib.py` + `styles.py`. Jede Frisur braucht `name.txt`, `name.png`, `_n`, `_cap`, `_scalp`.
2. **Kleiderfehler:** Die weisse Toga verschwindet auf der weissen Tunika, und die Tunika schaut am Palla-Arm durch.
3. **Kleider nach Epoche:** Bisher tragen alle römische Kleider. Damit das Spiel bis 2000 trägt, braucht es Mittelalter- und
   Neuzeit-Kleider. Zuerst recherchieren und planen, dann eine Karte für Ramon. Das ist die grösste Arbeit.
4. **Kleiner:**
   - Mehr Stimmungen im Ausdruck (bisher Trauer, zufrieden, grimmig, neutral).
   - Test unter Metal auf dem Mac (Anisotropie, Hautstreuung, Alpha-Vorpass sind ungeprüft).
   - Nur Germania und Aegyptus haben echte Howells-Daten, die übrigen Herkünfte sind PLACEHOLDER.
   - Bei alten Männern mit weissem Haar bleibt an der Stirn ein leichter heller Rand der Haarkappe.
5. **Namen:** Ramon verlangt ein dynamisches Namenssystem von etwa 300 bis in die Neuzeit, je nach Gruppe und Kultur
   verschieden und sich wandelnd (Ramon 30.10.2026: «das system muss namen erlauben bis neuzeit. namen sind für gruppen und kulturen
   unterschiedlich, verändern sich. schlag mir ein dynamisches system vor»). Der Vorschlag steht vollständig unten in Abschnitt 7.
   Gebaut ist noch nichts. Ramon muss zuerst Schritt 1 wählen und drei offene Fragen entscheiden.

## 5. Bekannte Grenzen

- Die MakeHuman-Community-Domain ist in der Cloud gesperrt. Grössere Hauttexturen müssten über Ramons Mac geholt werden; das hat
  er bisher so gemacht («das haben wir immer so gemacht»).
- Für echtes Victoria-3-Niveau (Haarsträhnen, Stoffe und Haut wie von Hand modelliert) braucht es ehrlich gesagt einen 3D-Artist.
  Unsere Pipeline erzeugt alles prozedural.
- Bilder sieht Ramon nur, wenn sie als Datei angehängt oder per Pfad verlinkt sind. Die Porträts erscheinen im Personenfenster
  nur mit 112 × 140 pt, das begrenzt sichtbare Details.

## 6. Bilder und Berichte

- Testbilder (nur im Projektordner des ersten Accounts): `/mnt/project-files/portraits/`, unter anderem frisuren-uebersicht,
  baerte-blender, kleider-test1..3, haut-test1, augen-test1, gesichtsformen-test1, herkunft-test1, brauen-ausreisser-test1,
  laecheln-test1, alter-test1.
- Die beiden Rechercheberichte waren Claude-Docs auf Ramons erstem Account (Porträt-Realismus WBXca5g8E1Yb94Tf1vftDX, Namen
  U712QGBqx82ovwuyFb4Eyd). Ihr Inhalt steht unten in Abschnitt 7 und 8, damit er ohne diese Links verfügbar ist.

## 7. Namensvorschlag (vollständig, Stand 30.10.2026, noch nicht entschieden)

**Kurz:** Namen werden ein eigenes kleines System, das wie die Wirtschaft aus der Simulation wächst. Eltern wählen Namen, Namen
kommen in Mode und vergehen, und auch die Bauart eines Namens ändert sich mit Staat, Religion, Kontakt und Dichte. Fünf Bausteine
tragen das von 300 bis heute ohne Sonderregeln je Epoche. Eine neue Epoche oder Kultur braucht neue Daten, keinen neuen Code.

**Befunde der Forschung** (verlinkte Quellen online geprüft, übrige aus dem Gedächtnis, nicht online geprüft):
- **Mode mit Bremse:** Seltene Namen wachsen, sehr häufige schrumpfen. Bei etwa 1 von 10'000 Geburten sind es rund +1,4 % im Jahr,
  über 1 von 100 rund −1,6 %. Biblische Namen haben bei jeder Häufigkeit einen Vorteil (Newberry & Plotkin, 2022,
  https://doi.org/10.1038/s41562-022-01342-6; Plotkin, 2025).
- **Zufälliges Abschauen** erklärt einen grossen Teil der Verteilung (Hahn & Bentley, 2003). Wo es nicht reicht, wirken Vorlieben
  (Acerbi & Bentley, 2014).
- **Prestige sickert nach unten:** Oben kommt ein Name auf, unten folgt man, oben wechselt man weiter (Lieberson, 2000).
- **Nachbenennung nach Verwandten** reagiert auf Ereignisse. Nach der Mobilmachung 1914 stieg die Weitergabe des Vatersnamens um
  rund die Hälfte. Starb der Vater in der Schwangerschaft, war sie 2,7-mal so häufig (Todd & Coulmont, 2021,
  https://doi.org/10.1162/jinh_a_01663). Das passt zur Trauer, die die Porträts schon zeigen.
- **Namen messen Bekehrung:** Der Anteil christlicher oder muslimischer Namen steigt in einer S-Kurve (Bagnall, 1982; Bulliet, 1979).
- **Zuwanderer passen Namen an**, je nach Kontakt und Bleibeabsicht (Abramitzky et al., 2020). Eigene Namen halten eine Gruppe
  zusammen (Fryer & Levitt, 2004).
- **Die Bauart ändert sich selbst:**
  - Aus drei römischen Namen werden Gentilname und Beiname; nach 212 heissen sehr viele Aurelius (Salway, 1994).
  - Im Frühmittelalter genügt ein Name. Im 11. bis 13. Jahrhundert kommen Beinamen und Heiligennamen auf, erblich zuerst bei Adel
    und in Städten (Bourin, 1989–2002; Mitterauer, 1993; Wilson, 1998).
  - Anderswo erst per Gesetz: Japan 1875, Türkei 1934. Island bleibt bei Vatersnamen.
- **Familiennamen sterben aus wie Linien:** Die meisten verschwinden, wenige werden sehr häufig (Galton & Watson, 1875).

**Die fünf Bausteine** (jeweils Daten plus eine kleine Regel, keine Namen von oben):

| Baustein | Was es ist | Um 300 | Um 1900 |
|---|---|---|---|
| 1. Namensgut | Stamm mit Formen je Sprache und Zeit, dazu Geschlecht, Herkunft, Religion | IOHANNES als Iohannes, Ioannes, Yohannan | Johannes, Hans, Jean, Giovanni, Iwan |
| 2. Namensordnung | Bauplan des vollen Namens je Kultur und Zeit, auch was die Frau bei Heirat trägt | Gentilname vom Vater + Beiname: Aurelius Victor | Vornamen + fester Familienname: Jean Faure |
| 3. Namenswahl | Bei Geburt aus gewichtetem Vorrat: Verwandte, Nachbarn (mit Häufigkeitsbremse), Prestige, Religion, eigene Gruppe, Neues | Sohn nach dem Grossvater | Modename, Heiligenname der Paten |
| 4. Beinamen aus dem Leben | aus Sim-Wissen: Beruf, Ort, Vater, Aussehen (Gene) | Rufus (rotes Haar), Faber (Schmied) | erblich geworden: Schmid, Faure, Rossi |
| 5. Linien und Familiennamen | jede Person in einer Linie (Vater oder Mutter je Regel), sichtbarer Name folgt der Namensordnung | Linie der Valerii | dieselbe Linie unter erblichem Beinamen |

- **Beispiel einer Linie** (erfunden): Aurelius Valerius Victor (um 300) → Victor (um 600) → Johannes, Sohn des Victor (um 1100) →
  Jean le Fèvre, der Schmied (um 1250) → Jean Faure (um 1900).
- **Teile der Namensordnung:** gewählter Name, ererbter Name, Name nach Vater oder Mutter (Ibn, -son, Genitiv), Beiname aus Beruf,
  Ort oder Aussehen, Ehrenname oder Titel. Daraus lassen sich arabische (Ism, Nasab, Kunya, Nisba), byzantinische, germanische und
  moderne Baupläne bauen.

**Wandel der Namensordnung:** Sie folgt keinem Kalender, sondern wechselt je Markt und Stand, wenn ein Druck aus sechs Auslösern hoch genug ist.
- Die Auslöser:
  - Verwaltung: Steuer und Pacht (S115, S116), später Zensus und Urkunden.
  - Erbe: wie oft ein Hof an ein Kind übergeht.
  - Dichte: der Anteil der Leute, die ihren Namen im Markt mit anderen teilen.
  - Religion: sobald die Simulation Bekehrung kennt.
  - Kontakt: Handel und Umzüge.
  - Gesetz: ein Erlass des Spielers oder ein Ereignis, etwa Japan 1875.
- Jeder Haushalt prüft jährlich den Druck und wie viele Nachbarn schon gewechselt haben. Das ist ein Schwellenmodell (Granovetter,
  1978) und ergibt eine S-Kurve. Oberschicht und Städte wechseln zuerst.
- Es geht auch zurück: Nach 212 zeigt der Gentilname nichts mehr an, und um 600 genügt ein Name.
- Die Gewichte sind PLACEHOLDER, geeicht an bekannten Wenden (erbliche Beinamen zuerst in Italien und Südfrankreich, Japan 1875,
  Türkei 1934).

**Sichtbar im Spiel:**
- voller Name im Personenfenster, mit einem Hinweis je Teil (zum Beispiel «Aurelius: vom Vater, seit 212»);
- Haushaltsliste und Stammbaum bis zum Gründer;
- Statistik «Namen» mit den häufigsten Namen je Markt und Jahrzehnt sowie der Namensvielfalt;
- Kartenart «häufigster Name» oder «Anteil christlicher Namen»;
- Ereignisse bei seltenen Wenden;
- Hinweise nennen Menschen beim Namen statt «Haushalt 7».

**Vergleich** (aus dem Gedächtnis): CK3 zieht Namen aus festen Listen je Kultur, mit einer Chance auf Namen von Vater oder Grosseltern.
EU5 und Victoria 3 vergeben Namen nur an Figuren aus Kulturlisten. Bei uns entstehen Häufigkeit und Bauart aus dem Spiel, für alle
Menschen.

**Leistung:** etwa 12 Bytes je Person (Name, Beiname, Linie), bei 200'000 Menschen rund 2,4 MB. Gewählt wird nur bei Geburt, Heirat
oder einer Wende. Jeder Markt führt eine Zählliste der Geburten der letzten Jahre. Die Namen ziehen aus einem eigenen Zufallsstrom,
damit die übrige Simulation gleich bleibt und ein Spielstand dieselben Namen ergibt.

**Datenquellen** (Lizenzen noch prüfen):
- Latein: Kajanto (1965), dazu Salway (1994) für die Bauart.
- Griechisch: Lexicon of Greek Personal Names.
- Ägypten: Trismegistos People.
- Gallien, Germanien, Donau: Onomasticon provinciarum Europae Latinarum, Förstemann (1900).
- Neuzeit: amtliche Vornamenstatistiken (Frankreich seit 1900, USA seit 1880).

**Bauschritte**, jeder mit Karte und einem Lauf über 100 Jahre:
1. Namensgut um 300 für die sieben Herkunftsgebiete, Linien und Namenswahl (Verwandte, Nachbarn mit Bremse, Prestige), sichtbar in
   Personenfenster, Haushaltsliste und Ereignissen.
2. Beinamen, Statistik und Kartenart.
3. Wandel der Namensordnung.
4. Spätere Epochen als Datenpakete.

**Offene Fragen an Ramon:**
1. Nur die Zeit um 300 (empfohlen) oder gleich ein zweites Zeitalter als Probe?
2. Schreibweise in der eigenen Sprache der Person mit lateinischer Form im Hinweis (empfohlen), oder einheitlich?
3. Vaterlinie als Regel mit Ausnahmen je Kultur (empfohlen), oder beide Eltern gleich gewichtet?

**Literatur** (APA 7, bis auf Newberry & Plotkin, Plotkin, Salway und Todd & Coulmont nicht online geprüft):
- Abramitzky, Boustan & Eriksson (2020), *AER: Insights, 2*(1), 125–141.
- Acerbi & Bentley (2014), *Evolution and Human Behavior, 35*(3), 228–236.
- Bagnall (1982), *Bulletin of the American Society of Papyrologists, 19*, 105–124.
- Bourin (Hrsg., 1989–2002), *Genèse médiévale de l'anthroponymie moderne*, Bde. 1–5.
- Bulliet (1979), *Conversion to Islam in the medieval period*. Harvard University Press.
- Förstemann (1900), *Altdeutsches Namenbuch, Bd. 1* (2. Aufl.).
- Fryer & Levitt (2004), *QJE, 119*(3), 767–805.
- Galton & Watson (1875), *J. Anthropological Institute, 4*, 138–144.
- Granovetter (1978), *American Journal of Sociology, 83*(6), 1420–1443.
- Hahn & Bentley (2003), *Proc. R. Soc. B, 270*(Suppl. 1), S120–S123.
- Kajanto (1965), *The Latin cognomina*.
- Lieberson (2000), *A matter of taste*. Yale University Press.
- Mitterauer (1993), *Ahnen und Heilige*. C. H. Beck.
- Newberry & Plotkin (2022), *Nature Human Behaviour, 6*(8), 1048–1055.
- Salway (1994), *Journal of Roman Studies, 84*, 124–145.
- Todd & Coulmont (2021), *Journal of Interdisciplinary History, 52*(1), 55–67.
- Wilson (1998), *The means of naming*. UCL Press.

## 8. Porträt-Recherche (Kernpunkte, Stand 31.10.2026)

- **Fazit:** CK3/EU5-nah ist in Spielgrösse mit Blender per Skript erreichbar. Gross betrachtet bleibt ein Abstand zu Paradox. Der
  Engpass ist die Gestaltung: Leitkurven und Formen setzt Claude, kein Künstler.
- **Haar-Pipeline (so gebaut):**
  1. 10 bis 30 Leitkurven bzw. ein Flussfeld je Frisur.
  2. Daraus wachsen 5'000 bis 20'000 Haare, gebündelt und mit Locken nach dem Gen CURL.
  3. Die Haare werden zu 100 bis 300 Karten zusammengefasst.
  4. Ein Strähnen-Atlas wird in Cycles gerendert.
  5. Die Karten werden an Bezugspunkte des Kopfs gebunden (wie MakeHuman .mhclo).
- **Papers und Werkzeuge** (online geprüft am 31.10.):
  - Blender Haar-Nodes (Blender Studio, 2023).
  - «Hair cards from curves» (Daniel Bystedt).
  - Strands2Cards (Tojo, Hu, Umetani & Li, 2025, SIGGRAPH Asia, https://doi.org/10.1145/3757377.3763864): Karten aus über 100'000 Haaren in unter 20 s.
  - Auto Hair Card Extraction (Zheng et al., 2025, ACM TOG 44(6), https://doi.org/10.1145/3763295): ein Atlas für alle Frisuren.
  - HAAR (Sklyarova et al., 2024, CVPR): Frisur aus Text, Lizenz unklar.
  - Der UE5 Hair Card Generator gilt nur für Unreal.
- **Glanz und Haut:**
  - Kajiya & Kay (1989) und Marschner et al. (2003): Glanz entlang der Haarrichtung, zwei Glanzlichter.
  - Scheuermann (2004): beides in Echtzeit auf Karten.
  - Jimenez et al. (2015): Hautstreuung als Bildfilter. Penner & Borshukov (2011): vorintegrierte Haut.
  - Godot hat Anisotropie mit Flussrichtung, Alpha-to-Coverage und Lichtstreuung im Haut-Modus eingebaut.
  - Leben im Gesicht (Hunger, Sonne, Narben, Falten) gehört in Texturen und Normal-Maps wie bei Paradox; für die Falten ist das seit #126 so.
- **Fertige Lösungen:**
  - MPFB 2 (MakeHuman für Blender, Code GPLv3, Assets CC0) passt zur selben Grundform, aber der Asset-Server ist in der Cloud gesperrt.
  - MakeHuman «Hair 01» (25 Frisuren, CC0) liegt auf demselben gesperrten Server.
  - MetaHuman ist seit Juni 2025 auch in Godot erlaubt (gratis unter 1 Mio. USD Umsatz). Es hat die beste Qualität, aber eine eigene
    Gesichtslogik statt unserer Gene, moderne Kleider, und es braucht Unreal.
  - Character Creator und Daz sind Asset-Packs, also nein.
  - Humanizer (MakeHuman in Godot) steht unter AGPL, also nein.
  - Für römische Kleider und Frisuren gibt es nirgends etwas Fertiges.
- **Blender MCP** (ahujasid) braucht ein laufendes Blender auf dem Mac. Für die Pipeline reicht bpy headless in der Cloud. MCP wäre
  nur nützlich, wenn Ramon selbst Leitkurven nachziehen will. Dessen Asset-Funktionen (Sketchfab, Poly Haven, Hyper3D) fallen wegen
  «keine Asset-Packs» weg.
