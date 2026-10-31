# Porträt-Pipeline (Blender, MakeHuman, Tests). Übergabe und Einrichtung: docs/handover/portraits.md

- (Früher: `realismus-test.patch` mit dem Testcode; der Code ist seit #124 und #126 in main, das Patch ist überholt und nicht mehr dabei.)
  (APOLEIA_REAL, APOLEIA_MH_DIR, APOLEIA_MH_MEN/WOMEN, APOLEIA_REAL_SCALP, APOLEIA_REAL_BLEND, APOLEIA_REAL_NMAP,
  APOLEIA_REAL_ANISO, APOLEIA_TEST_BARE). Siehe `rhair.sh` für einen Godot-Render.
- MakeHuman-Daten: git clone makehuman-js/makehuman-data (CC0-Assets), `convert.py` (Kleider/Haare -> txt),
  `tex.py` (Textur mit Alpha), `real_prep.py` (Haut-UV + Hauttexturen).
- Blender-Haar (bpy 5.2 per pip, headless): `gen_hair.py` (Flussfeld -> 9'000 Haare -> 300 Strähnen-Karten +
  Kopfhaut-Schicht mit 60'000 gemalten Haaren, gebunden an head.bin-Vertices), `tiles.py` (Strähnen-Atlas in Cycles),
  `post.py`, `nmap.py` (Normalenkarten), `view_cards.py` / `view_dump.py` (Kontrollbilder in Blender).
- `gen_bun.py`: römischer Frauenknoten (Mittelscheitel, Wellen, Haar über die Ohren, Knoten als gedrehte Spirale).
  Textur: bun01.png = Atlas aus tiles.py (Kacheln 0-3), Normalenkarten mit nmap.py (Karten: `nmap.py tex.png tex_n.png 8`).
- Wichtig: Kartendreiecke müssen von aussen gegen den Uhrzeigersinn laufen, sonst sind sie von innen beleuchtet (dunkel, Helm-Glanz).
- `hairlib.py` + `styles.py STYLE NAME`: crop, bald, receding, curly (Kacheln mit CURLY=1 tiles.py), sidepart (um 1900), braid (Zopfkranz).
  Rust: APOLEIA_MH_AUTO=1 wählt die Frisur nach Glatzen-Gen + Alter, Locken-Gen, Stand, Haartracht; APOLEIA_ERA=1900 für Seitenscheitel.
  Jede Frisur braucht name.txt, name.png (+ _n.png), name_cap.txt/.png (+ _cap_n.png), name_scalp.txt.
- Ergebnisbilder: ../realismus-test1.png, ../realismus-test2.png, ../haar-runde2.png, ../frisuren-uebersicht.png
- Bärte: `beards.py base.obj outdir STIL NAME` mit STIL stubble, short, full, phil, chin (`region` = Kontrollbild der Bartzone).
  Bartzone = Rusts in_beard plus Schnurrbart-Band, Mund als Ellipse frei, Koteletten bis zum Haar; Wuchs nach unten, Schnurrbart nach aussen-unten,
  unter dem Kinn zum Hals. Stoppeln und kurzer Bart nur gemalt (Kappe), Voll-, Philosophen- und Kinnbart zusätzlich Karten, die frei unter dem Kinn
  hängen (vor Hals und Brust gehalten). Schnurrbart immer gemalt (kurze Karten sahen aus wie Zähne). Atlas: `BEARD=1 tiles.py` -> post.py -> beard01.png,
  kopiert als beard_<stil>.png (+ _n.png); Kappen-Normalen mit nmap.py. Rust: APOLEIA_MH_BEARD=Ordner lädt beard_<stil> und lässt den Facetten-Bart weg;
  APOLEIA_TEST_BEARDS="pid=stil,..." für Renders (`beard.sh`, `beard_compare.gd`). `mask_dump.rs` schreibt Lippen-/Nasenmasken und die Facetten-Bärte.
- Ergebnisbild Bärte: ../baerte-blender.png
- Kleider (Test 1, Tunika): `tunic_sim.py base.obj out.obj 80` (bpy, Stoffsimulation: weiter Schlauch aus MakeHumans Tights-Helfer,
  fällt auf den Körper, Gürtel zieht unten zusammen; Umgebungsvariablen WIDE, BEND, LOOSE; Test-Bild mit WIDE=0.45 BEND=4 LOOSE=0.45),
  `view_cloth.py` (Cycles-Ansichten), `tunic_bind.py base.obj tunic.obj mhreal cloth_tunic` (Taubin-Glättung, Bindung an head.bin mit
  Versatz im Dreiecks-Rahmen, uv um den Körper, Woll-Textur). Rust: APOLEIA_MH_CLOTHES=Ordner ersetzt die Facetten-Tunika (mh_cloth,
  glatte Normalen, Farbe je Dreieck, Flicken als ganze Stücke). Godot: Pfad mit /cloth_ = matter Stoff, beidseitig.
  Achtung: feine Zeilenmuster in der Textur flimmern im Porträt als Streifen. Ergebnisbild: ../kleider-test1.png
- Kleider (Test 2): `FRIC=0.5 WIDE=0.9 BEND=1.0 LOOSE=0.9 tunic_sim.py base.obj tunic_h.obj 100` (Ärmel aus den Armlöchern extrudiert,
  weniger Reibung, damit der Stoff rutscht und Falten wirft; ca. 35 s). `AO=6 tunic_bind.py ...`: Halssaum als gerollter Schlauch, Schnittkante
  entlang der Kette geglättet (HEMSMOOTH), Faltenschatten je Ecke = Tiefe unter der geglätteten Fläche (name_ao.txt). Rust mh_cloth: Dreiecke an
  Zellgrenzen und Flicken-Rändern geschnitten (CLOTH_CUTS), Zellen von vorne gesehen (x, y; ein Raster um die Körperachse fächert auf),
  Flicken je Person verschieden (Seed), Nachbarn verschmelzen zu grösseren Stücken, dunklere Naht am Rand. APOLEIA_DEBUG_CELLS zeigt das Raster.
  Ergebnisbild: ../kleider-test2.png
- Kleider (Test 3, Toga/Palla/Schleier): `drape_sim.py base.obj tunic_h.obj toga|palla|veil out.obj 90` (bpy). Kollision mit Körper und Tunika;
  Start ausserhalb der Tunika (Strahl entlang der Normalen), nach der Simulation dort abgehoben, wo die Tunika noch durchsticht. Nur der im Porträt
  sichtbare Teil (YMIN=3.6, unterster Ring gehalten). Toga: `YMIN=3.6 LOOSE=0.4 SGATHER=0.7` (über der linken Schulter gerafft, Band quer über die
  Brust). Palla: `YMIN=3.6 OPEN=0.3 LOOSE=0.6` (über beiden Schultern, vorne offen, ohne Arme). Schleier: regelmässiges Netz aus Strahlen vom
  Kopfmittelpunkt (die Kopfgeometrie mit Ohren riss den Stoff in Zacken), Gesicht frei, unten ein Rock (SKIRT=9), der auf die Schultern fällt.
  Binden: `HEM=all R_HEM=0.035 TAUBIN=10 AO=6 tunic_bind.py ... cloth_toga` (Schleier mit HEAD=1). Rust: cloth_toga, cloth_palla, cloth_veil
  ersetzen die Facetten, wenn vorhanden. APOLEIA_TEST_VEIL="pid,..." setzt Frauen unter den Schleier. Ergebnisbild: ../kleider-test3.png
- Haut (Test 1): `bpyenv/venv/bin/python skin_ao.py base.obj mhreal/skin_ao.txt` (Verdeckung je Kopf-Ecke, 96 Strahlen, 3.5 cm),
  `python3 skin_red.py base.obj mhreal/skin_red.txt` (Rötungszonen Nase, Wangen, Ohren, Kinn), `python3 skin_nmap.py
  mhreal/skin_<alter>_<geschlecht>_n.png 2048 <poren_px> <tiefe> 0.12 <linien> 7` (Poren und feine Hautlinien als Normal-Map über den ganzen
  Haut-Atlas; jung 1.6/0.35/0, mittel 1.8/0.4/0.08, alt 2.0/0.45/0.18, Frauen Poren x0.85; grössere Poren und Rauschen sahen aus wie Fell).
  Rust real_skin: APOLEIA_SKIN_SOFT (2, Glättung der Facettenfarben), APOLEIA_SKIN_AO (0.7), APOLEIA_SKIN_RED (0.6, auf dunkler Haut schwächer,
  bei alten Männern stärker); Lippen im Real-Modus nur wenig röter als die Haut; Narben nur leicht blasser und flacher. Godot lädt die
  Normal-Map neben der Haut-Textur, wenn APOLEIA_REAL_NMAP gesetzt ist. Vorher/Nachher: `face.sh out.png`. Ergebnisbild: ../haut-test1.png

- Augen (Test 1): `python3 eye_tex.py mhreal/eyeball.png 512` (Atlas 4x4, je Zelle eine Irisfarbe entlang der Augenfarben aus look.rs;
  ganzer Augapfel um die Blickachse abgebildet: Pupille, Iris mit Fasern, hellerem Kranz und dunklem Rand, Augenweiss gebrochen weiss,
  zu den Winkeln rötlicher). skin_ao.py rechnet jetzt auch die Augäpfel (Schatten der Lider). Rust: im Real-Modus bekommt jedes Auge
  uv in seiner Zelle (Zelle aus dem Augen-Gen), Kinder mit grösserer Iris, Alte mit leicht gelblichem Weiss; Wimpern in einem sehr
  dunklen Ton der Brauenfarbe. Godot: Pfad mit /eyeball = nass glänzend. Test mit allen Augenfarben: `PJ=eyes_b.json face.sh out.png`.
  Ergebnisbild: ../augen-test1.png. Beobachtung: die dunklen «Lidstriche» bei Frauen sind vor allem die Brauenkarte, deren Ende bis
  zum Augenwinkel herunterläuft, nicht die Wimpern.

- Gesichtsformen (Test 1): `cargo run --release -p apoleia-portrait --example face_measure -- 400 35` misst an 400 Zufallsgründern
  Gesichtsbreite (zy-zy), Kieferbreite (go-go), Gesichtshöhe (n-me), Untergesicht (sn-me), Nasenbreite (al-al), Nasenhöhe (n-sn),
  Nasenspitze (sn-prn), Mundbreite (ch-ch) und Pupillenabstand (FEMALE=1 für Frauen; SENS=ziel,... zeigt, wie stark ein Morph-Ziel
  jedes Mass verschiebt). Vergleich mit Farkas-Normen (Nordamerika weiss, über Kenia-Studie 2019) und Kenia-Werten.
  Ergebnis heute: Variationskoeffizienten 3 bis 6 %, fast wie echt, nur Kiefer und Nase zu wenig; aber Brauenwulst, Augentiefe,
  Nasenprofil, Wangen und Kieferwinkel bewegte kein Gen. Neu (APOLEIA_FACE_MODULES=1): FACE_MOD in look.rs, jedes der 21 Gene bewegt
  eine Partie mit mehreren Zielen; Kinder behalten ihre Einzelziele (KID). APOLEIA_FACE_GAIN überzeichnet (1.6 im Bild).
  15 Gründer aus Italia: men15.json. Ergebnisbild: ../gesichtsformen-test1.png

- Herkunft (Test 1): Howells-Schädeldaten (Howells 1973, 1989, 1995; Howell.csv über die Internet-Archive-Kopie von
  web.utk.edu/~auerbach/Howell.csv, Stand 2024-11-18, auf Ramons Mac zusammengefasst). howells/summary4.csv = Mittelwerte und sd
  je Geschlecht für NORSE, ZALAVAR, BERG, EGYPT. `python3 -I howells/face_shift.py howells/summary4.csv howells/baseline.txt`
  rechnet je Herkunft z-Werte (Germania = NORSE+BERG, Aegyptus = EGYPT, übrige PLATZHALTER nach Breitengrad zwischen BERG und
  EGYPT) und löst headW/headH/noseW gemeinsam über gene_sens.txt (face_measure GENE_SENS) gegen das, was die Grundtypen schon tun;
  noseL/eyeS/eyeD direkt z x 24. Ergebnis als FACE_SHIFT in sim/src/dna.rs (nur Aussehen). Kontrolle: face_measure ORIGIN=o
  FACE_SHIFT=... trifft die z-Werte auf 0.1 sd. Ergebnisbild: ../herkunft-test1.png

## Brauen und Ausreisser (31.10., brauen-ausreisser-test1.png)

- Trauer kippte die Braue mit eyebrows-angle-up 0.9 (mal 1.7) so stark, dass das Brauenende bis unter den Augenwinkel fiel. Neu: angle-up 0.35 plus eyebrows-trans-up 0.5, das Ende bleibt über dem Auge (gemessen mit brow_shape.py auf surf_dump, DUMP_MOOD=sad).
- Gesichtsgene weich begrenzt: c·tanh(x/c) mit c 0.35 (APOLEIA_FACE_SOFT, PLATZHALTER): 1 Streuung -9 %, 2 Streuungen -27 %, 3 Streuungen -43 %.
- Die Teile aller Gene werden pro Ziel zuerst summiert und dann weich bei 1 begrenzt (APOLEIA_FACE_LIM, PLATZHALTER). APOLEIA_FACE_DEBUG zeigt Summen über 0.6 (Beispiel face_targets).
- extreme_set.py zieht 120 Zufallsgründer und wählt die 12 extremsten.

## Lächeln (31.10., laecheln-test1.png)

- Zufriedene Stimmung (jeder Dritte) hob die Mundwinkel mit mouth-angles-up 0.9 (mal 1.7) rein senkrecht, das las sich als schiefes Grinsen. Neu: Mundwinkel 0.45, Mund 0.1 breiter, Wangen 0.3 statt 0.4, Brauenwinkel 0.1 statt 0.25.
- APOLEIA_TEST_MOOD=content|sad|grim|neutral setzt beim Test alle auf eine Stimmung (sim/godot/src/portrait.rs).

## Alter (31.10., alter-test1.png, #126)

- `python3 -I uvpos.py base.obj 1024 pos.npy`: zu jedem Texel des Haut-Atlas der Punkt auf dem Grundkopf.
- `python3 -I wrinkle_bake.py pos.npy base.obj app/assets/portrait/real out`: Faltenlinien (Tabelle G im Skript: Stirn, Zornesfalte,
  Krähenfüsse, Lid, Tränenrinne, Nasolabial, Marionette, Lippen, Hals, Wange; Beginn, Dauer, Tiefe Mann/Frau, Schatten) als
  Normal-Maps skin_<gruppe>_<geschlecht>_w<E>_n.webp (E 38..86 in 8er-Schritten, mit den Poren gemischt), wrinkle_fold.txt
  (Schatten je Ecke, danach mit rust-examples/zpack.rs packen) und wrinkle_lines.txt. Rust real_skin wählt die Stufe nach dem
  Faltenalter (Alter + 14 x (Sonne - 0.5) +- 4 Jahre).
- Absacken (Morphs ab 38) und dünneres Frauenhaar (Karten weggelassen) stehen direkt in build.rs.
- Test: `age.sh set.json out.png` (Altersreihe 20 bis 82, Reihe 1 Mann, Reihe 2 Frau).
