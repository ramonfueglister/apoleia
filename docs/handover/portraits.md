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
5. **Namen:** Ramon verlangt ein dynamisches Namenssystem von etwa 300 bis in die Neuzeit, je nach Gruppe und Kultur verschieden und
   sich wandelnd. Der Vorschlag steht in https://claude.ai/artifact/U712QGBqx82ovwuyFb4Eyd (Namensgut, Namensordnung, Namenswahl,
   Beinamen, Linien). Gebaut ist noch nichts; Ramon muss Schritt 1 wählen. Das Artefakt gehört dem ersten Account. Ist es nicht
   erreichbar, muss Ramon es teilen oder den Inhalt mitgeben.

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
- Rechercheberichte: Porträt-Realismus https://claude.ai/artifact/WBXca5g8E1Yb94Tf1vftDX und Namen
  https://claude.ai/artifact/U712QGBqx82ovwuyFb4Eyd.
