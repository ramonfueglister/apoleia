# Recherche: Open-Source-Terrain und Voxel-Vorbilder

**Stand:** 29.10.2026. **Status:** erforscht. Reine Recherche, keine Codeänderung.

Interaktive Fassungen: [Terrain-Bibliotheken für Apoleia](https://claude.ai/artifact/52pT8LKSvicfMNcQJ216jf),
[Voxel-Spiele als Vorbild](https://claude.ai/artifact/ByK6r65RRBujcp3Z4eAyBq).

## Empfehlung

Eigenes Clipmap-Terrain behalten, keine Bibliothek übernehmen. Keine
Open-Source-Lösung deckt 4.400 km bis 1 km in einem Stil ab. Die Schwäche bei
70 km (Gauntlet Runde 12: Note 3) ist geometrisch: die feine Stufung wird zu
Treppenrauschen. Drei Techniken gezielt übernehmen:

1. **Rampenmodell wie SimCity 2000 / OpenTTD:** Höhen nur an Kachelecken,
   Nachbarecken höchstens eine Stufe auseinander (OpenTTD: 19 Hangformen),
   steilere Hänge als Klippe.
2. **Stufenhöhe pro LOD-Ebene mitwachsen lassen** (Prinzip Distant Horizons):
   jede LOD-Ebene quantisiert Höhe und Landbedeckung neu und gröber
   (Mehrheitsfilter statt Mittelwert).
3. **Dual Grid für Landbedeckung** (Townscaper): Klassen an Ecken, 16
   Übergangsformen pro Zelle, gegen das Tarnmuster bei 22 km.

Arbeitsvorschlag: 1 km und 1.500 km einfrieren, nächste Runden nur an 22 km
und 70 km gegen ein festes Referenzbild messen.

## Kandidaten

| Projekt | Lizenz | Godot | Kontinent + LOD | Urteil |
|---|---|---|---|---|
| [Voxel Tools](https://github.com/Zylann/godot_voxel) (Zylann) | MIT | nativ, v1.7 (Aug 2026) | nein, Blocky-LOD nur basic | für begehbare Minecraft-Welten |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) | MIT | nativ | nein, max. 65,5 × 65,5 km | realistisch, keine Kacheln |
| [Distant Horizons](https://gitlab.com/dosaki/distant-horizons) | LGPL-3 | Java-Mod | ja | nur Technik |
| Veloren | GPL-3 | Rust/wgpu | teils | nur lernen (GPL) |
| [Terra](https://zff.dev/fintelia/terra) | siehe Repo | Rust/wgpu | ja, CDLOD | realistisch, WIP |
| [Aokana](https://arxiv.org/html/2505.02017v1) | kein Code | Unity | ja (SVDAG) | Forschung |
| [OpenTTD](https://www.openttd.org/about.html) | GPL-2 | C++ 2D | Karte | Rampenmodell als Referenz |
| [Blocks (Manifold)](https://blocks.manifold3d.ch) | kostenpflichtig, Code nicht offen | Minecraft Java + Cubic Chunks | Schweiz 1:1, 24 GB | falscher Massstab für uns |

GPL-Code darf nicht übernommen werden (AGENTS.md: kein fremder Code).

## Eigenbau-Option (grobe Schätzung)

| Variante | Aufwand | Risiko |
|---|---|---|
| Prototyp Region Rom im Rampenmodell aus bestehender Heightmap | 2–4 Tage | gering |
| Rampenmodell + LOD-Quantisierung im Clipmap-Terrain | 2–4 Wochen | mittel |
| Neubau als 3D-Voxelwelt | 2–3 Monate | hoch |

Prototyp nicht gestartet, Ramon entscheidet.

## Spiele als Stilvorbild

Nutzerurteil 29.10.2026: **Urbek ja (Hauptvorbild), Timberborn okay, Voxel
Tycoon hässlich.** Weitere Kandidaten in Urbek-Nähe, nicht neu recherchiert:
Bad North, Islanders, Before We Leave, Summerhouse, Isle of Arrows, Fabledom,
Kingdoms and Castles, MagicaVoxel-Dioramen auf ArtStation/Sketchfab.

Folgerung: Boden wie bei Urbek, also flache ruhige Kachelflächen, wenige klare
Höhenstufen; Detail in Gebäuden und Bäumen, nicht im Gelände.
