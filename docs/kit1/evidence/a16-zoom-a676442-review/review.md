# A16 – unabhängige Bildprüfung der Zoomfolge Rom (a676442)

Geprüft: [`a16-zoom-a676442`](../a16-zoom-a676442/manifest.json), 17 Einzelbilder (640×360).
Die Folge besteht aus `rome-zoom-0.0` bis `1.0` und `rome-width-200km` bis `40km`. Laut Manifest
stammen die Bilder von Commit `1dd0cb14`. Das ist main `a676442` plus der Land-Cover-Fix
`--source-root`, der nicht auf main liegt; main steht inzwischen auf `e707db8`. Der Fix wirkt
laut Diff nur mit `--source-root`. Die Aufnahmekommandos setzen diesen Schalter nicht, deshalb
ist das Rendering a676442-äquivalent. Das ist nur aus dem Diff beurteilt, nicht nachgerendert.
Prüfer: independent-claude-subagent, 27.10.2026. Maschinenlesbar: [`review.json`](review.json).
Vergleichsbasis: [`a16-zoom-main`](../a16-zoom-main/manifest.json) mit
[Vorprüfung](../a16-zoom-independent-review/review.md) (FAIL).

**Urteil A16-Bildteil: FAIL.** Gegenüber der Vorprüfung ist die Folge deutlich verbessert, es
bleiben aber zwei P1 und mehrere P2.

## Hashes

Alle 17 PNG-Hashes und Bytegrößen stimmen mit dem Manifest überein (neu berechnet).

Vier Bilder sind palettenquantisiert:

- `rome-zoom-1.0`
- `rome-width-200km`
- `rome-width-160km`
- `rome-width-120km`

Damit ist der Vorbefund „1.0 weicher, nur 170 KB“ erklärt: Die kleinere Datei kommt von der
Quantisierung, nicht von Unschärfe.

## Gegenüber der Vorprüfung behoben bzw. verbessert

- **Rechteckige Domänen behoben.** Das helle Rechteck über Sahara/Arabien und der
  dunkelgrüne Block im Baltikum/Russland sind bei 0.0 und 0.1 verschwunden. Auch in keiner
  anderen Stufe gibt es neue achsparallele Säume.
- **Nahbereich jetzt erfasst.** Die Folge reicht von 7607 km bis 40 km. Die Breitenreihe von
  200 bis 40 km schließt ohne Lage- oder Merkmalssprung an 1.0 an.
- **Seen.** Von 0.6 bis 1.0 sind konsistent drei Seen westlich des Tibers zu sehen, vorher war
  es einer. Lage und Abfolge passen zu Trasimeno, Bolsena und Bracciano (bzw. Vico). Ohne
  Vektorüberlagerung ist das nur eine visuelle Zuordnung.
- **Relief.** Der Apennin ist ab 0.3 deutlich plastischer als in `f589e37`. Die Campagna bleibt
  bei 90 bis 40 km plausibel flach. Löcher oder Flachstellen gibt es nicht.
- **Tiber bei 0.3** ist jetzt durchgehend und nicht mehr segmentiert.

## Offene Befunde

- **P1 – Flussnetz, alle Stufen.** In Italien sind nur Tiber, Po und Ofanto sichtbar. Arno,
  Volturno und Liri-Garigliano fehlen durchgehend, ohne Quellen- oder Regelbezug. Das
  Supplement ist bekanntlich noch nicht auf main. A16 verlangt diesen Bezug für beabsichtigte
  Auslassungen.
- **P1 – Weltrand (0.0).** Die Zeilen 0 bis 44, also 12,5 % des Bildes, sind eine einheitlich
  graue Leerfläche (RGB 170,184,192). Darüber liegen Wolkenflocken, und bei y=45 verläuft eine
  harte gerade Geländekante. Der Befund ist bekannt, aber weiter sichtbar.
- **P2 – Tibermündung (200 bis 60 km).** Der Unterlauf besteht aus drei bis vier sich
  überlagernden und kreuzenden, halbtransparenten Bändern mit sichtbaren Überlappungsnähten.
  Ein heller gerader Balken liegt quer über der Mündung, am deutlichsten bei `rome-width-90km`
  und `rome-width-120km`. Real hat der Tiber zwei Ausmündungen. Das Bild wirkt wie doppelte
  bzw. überlappende Geometrie und ist eine unerwartete Änderung am geschützten Flussnetz. In
  der Vorfolge war das nicht sichtbar, weil sie bei 240 km endete.
- **P2 – Wolken (0.4).** Die Wolken erscheinen weiter als gepunktete Dither-Cluster, bei 0.3 und
  0.5 dagegen als weiche Flecken.
- **P2 – Küsten (0.0 bis 0.4).** Die Küsten bleiben treppenartig gerastert, etwa bei Marokko,
  Korsika, Sardinien, Sizilien und Dalmatien. Ab 0.5 sind sie glatt. Bei 120 km ist auch das
  Flachwasserband blockig.
- **P2 – Nahbereich (90 bis 40 km).** In der Bodenfarbe sind die Rasterzellen des Land-Cover-Gitters
  vergrößert sichtbar: Grün- und Tan-Flecken haben treppige Kanten.
- **P3 – Proportionen (40 km).**
  - Der Tiber ist dort etwa 1 km breit, rund achtmal so breit wie real.
  - Der Oberlauf ist bei 120 km gestrichelt.
  - Baumsprites sind maßstäblich sehr groß; das ist eine A08-Frage.
- **P3 – Wald (0.3 auf 0.4).** Der Wald springt abrupt von reiner Tönung zu Speckle.
- **P3 – Wolken (0.8 bis 1.0).** Wolken verdecken Teile des Apennins und der Küste.
  `cloud_layer_enabled` ist `false`, `weather_clouds` aber `on`. Eine wolkenfreie Kontrolle
  fehlt.

## Manifest

Deutlich verbessert. Das Manifest bindet jetzt:

- exaktes Kommando je Bild
- Kamera: Azimut, Elevation, FOV, Basis, Position
- Wetterzustand
- Renderer-, Renderer-Quell- und Dataset-Hashes
- Erklärung der Re-Encodierung
- Runtime-Auszüge mit `runtime_json_sha256`

Es fehlen:

- Der Hash von `geodata_policy.json`.
- Quellaufnahmen und runtime.json sind nicht getrackt.
- `last_clipmap_line` in den Auszügen zeigt `missing>0` bei 0.0 (11), 0.5 (1), 0.9 (8) und
  160 km (4). Die Aufnahmenotiz behauptet dagegen `missing==0` beim Snapshot. Der
  Snapshot-Zeitpunkt selbst ist nicht belegt.
- Ein Wolken-Seed.
- `excerpts/` enthält nur JSON, keine Bildausschnitte.

## Für PASS nötig

1. Fluss-Supplement auf main (Arno, Volturno, Liri-Garigliano) oder ein begründeter
   Regelbezug für die Auslassung, danach Neuaufnahme.
2. Überlappende Tiber-Bänder und den Mündungsbalken beheben.
3. Den grauen Streifen bei 0.0 beseitigen oder ihn als Weltrand mit Regelbezug dokumentieren,
   dann aber ohne Wolken über der Leerfläche.
4. Den Wolkenstil bei 0.4 vereinheitlichen oder ohne Wolken aufnehmen.
5. Die Rasterküsten bei 0.0 bis 0.4 glätten oder als Generalisierungsniveau mit Regelbezug
   begründen.
6. Den Hash von `geodata_policy.json` binden und den Clipmap-Zustand zum Snapshot-Zeitpunkt
   belegen.
7. Eine kontinuierliche Aufnahme bzw. dichte Stufenfolge für die Übergänge.
8. Eine Quellvektor-Überlagerung (Küste, Flüsse, Seen) für die Rom-Bilder.

## Grenzen

- Die Auflösung ist 640×360, und vier Bilder sind quantisiert.
- Es gibt nur Einzel-Snapshots, keinen Übergang.
- Es gibt nur einen Ort, und die Wolken sind an.
- Es gibt keine Vektorüberlagerung.
- Der Prüfer hat nicht nachgerendert.
