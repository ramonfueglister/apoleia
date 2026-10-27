# A08 – unabhängige Bildprüfung, Capture-Set main a676442

Geprüft: [`a08-a676442`](../a08-a676442/manifest.json), 11 Einzelbilder (640×360) von Commit
`1dd0cb1`. Das ist main `a676442` plus der Landcover-Source-Root-Fix. Der Diff ändert nur die
Pfadauflösung (`data_root()`). Ohne `--source-root`, das kein Capture-Befehl setzt, ist er
renderäquivalent. Verglichen wurde gegen die Nutzer-Primärreferenz
`references/images/user-primary-landscape-style.png` und, nur für Farbe und Fernstil, gegen
`landscape-far-revised.png`. Urbek wurde gemäß STYLE_GUIDE nicht für Terraindetail
herangezogen. Prüfer: independent-claude-subagent, 27.10.2026.
Maschinenlesbar: [`review.json`](review.json).

**Urteil A08: FAIL.** Palette und fehlende Facettierung im Fern- und Mittelbereich sind schon
bei 640×360 eindeutig. Die Auflösungsentscheidung ändert daran nichts.

## Hashes und Manifest

- Alle 11 PNG-sha256 stimmen mit dem Manifest überein (`sha256sum` und hashlib).
- `alps-mid`, `alps-near` und `rome-near` sind palettenquantisiert.
- Kamera, Befehl und Bindungshashes sind vollständig.
- **Widerspruch:** Laut Manifest wurde bei `missing==0` und `refining==0` aufgenommen. Die
  Excerpts zeigen aber in 9 von 11 Bildern `refining` 1–6 und in `rome-far` `missing=11`.
- `excerpts/` enthält JSON-Telemetrie, keine Bildausschnitte. Vergleichscrops zur Referenz
  fehlen.
- `rome-far` hat dieselbe Kameraposition wie `overview`. Nur 995 Pixel weichen ab
  (Wolkenflocken). Es ist also keine eigene Rom-Fernpose.

## Kriterien

| Teilkriterium | Urteil | Bei 640×360 beurteilbar |
|---|---|---|
| Zurückhaltende natürliche Palette | PARTIAL | ja |
| Stilisierte facettierte Geometrie | **FAIL** | Makroform ja, Feinfacetten fern/mittel nein |
| Ausreichende Landschaftsdetails | PARTIAL | teilweise; feine Küsten-/Fluss-/Lagunendetails NOT_JUDGEABLE |
| Lesbare Waldgruppen | PARTIAL | nah ja, mittel NOT_JUDGEABLE |
| Nicht fotorealistisch | PASS | ja |
| Nicht übermäßig bunt | PASS | ja |
| Nicht extrem low-poly/voxel/klotzig | PARTIAL | Geometrie ja, Küstentreppen teilweise NOT_JUDGEABLE |
| Keine Ableitung aus nachrangigen Bildern, keine Polygon-/Leistungsbehauptung | PASS | ja |
| Feste Kameravergleiche | PARTIAL | ja |

## Befunde

- **P1 (Facettierung):** Betroffen sind `overview`, `rome-far`, `alps-012`, `alps-out`,
  `england-mid`, `rome-mid`, `alps-mid`, `rome-near` und `alps-near`.
  - Das Relief ist eine weiche Schummerung ohne stilisierte Facetten.
  - Die hellen graubeigen Facettengebirge der Referenz fehlen; die Alpen erscheinen als weiße
    Sprenkel auf Dunkelgrün.
  - Nur `alps-40km` zeigt klare Dreiecksfacetten.
- **P1 (Palette):** Betroffen sind `overview`, `alps-012`, `england-mid`, `rome-mid`,
  `rome-near` und `rome-40km`. Das Land ist ocker- bis olivgelb statt gemäßigt frischgrün wie
  in der Referenz. Flachwasser erscheint nur als schmaler heller Saum.
- **P1 (Material):** In `rome-40km`, `alps-near` und `alps-40km` sind vergrößerte
  Texel-Treppen zu sehen. Hinzu kommt gestreckte, streifige Hangtextur. Die 40-km-Ebene ist
  eine leere Ockerfläche.
- **P2:** In den Fern- und Mittelansichten sind alle Flüsse gleich dicke hellblaue Linien.
  Das wirkt unruhig. Der Flusszusatz ist noch nicht auf main (bekannt).
- **P2:** Bei Zoom 0.0 liegt oben ein grauer Streifen über ~46 von 360 Zeilen (`overview`,
  `rome-far`; bekannt).
- **P2:** Wolken sind an. Opake Wolkenballen und abgelöste dunkle Schatten verdecken Gelände
  (`rome-near`, `alps-near`, `alps-out`, `alps-mid`). Ein wolkenfreier Kontrolllauf fehlt.
- **P2:** `rome-far` ist ein Duplikat von `overview`. Dazu kommt der Refining-/Missing-
  Widerspruch zwischen Manifest und Excerpts.
- **Positiv:**
  - `rome-40km` und `alps-40km` zeigen facettierte Nadelbaumkegel in lesbaren Gruppen, nahe am
    unteren Referenzpanel.
  - `rome-near` zeigt Tiberlauf, drei Kraterseen und Waldcluster lesbar.
  - Kein Bild ist fotorealistisch, grell oder voxelartig.

## Bei 640×360 nicht beurteilbar

- Ob die Wald-Sprenkel in den Mittelansichten (`rome-mid`, `alps-mid`) zu Gruppen werden
- Feinfacetten unterhalb der Pixelgröße
- Feine Küsten- und Flussdichte, und ob Küstentreppen aus den Daten stammen oder
  Bildschirm-Aliasing sind
- Exakte Farbwerte der drei quantisierten Bilder

## Für PASS nötig

1. Facettiertes Relief im Fern-, Mittel- und 240-km-Bereich mit hellen graubeigen
   Facettengebirgen.
2. Landpalette Richtung gemäßigtes Frischgrün, dabei zurückhaltend bleiben. Breitere helle
   Flachwasserzonen.
3. Keine Texel-Treppen und keine gestreckte Hangtextur mehr. Bodenvariation bei 40 km.
4. Ruhigere Flüsse in Fern- und Mittelansichten mit Breitenhierarchie. Den Flusszusatz auf
   main bringen.
5. Grauen Randstreifen bei Zoom 0.0 beheben.
6. Neu aufnehmen in der vom Owner entschiedenen Auflösung:
   - mit echter Rom-Fernpose
   - mit wolkenfreier Kontrolle
   - mit Referenz-Vergleichscrops je Panel (fern, mittel, nah)
7. Den Refining-/Missing-Widerspruch klären.
