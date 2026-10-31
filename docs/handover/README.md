# Übergabe Apoleia: Einstieg (Stand 31.10.2026, 19:00)

Ramon hat das Projekt auf seinem ersten claude.ai-Konto geschlossen und macht mit
einem zweiten Konto weiter. **Alles Nötige steht in diesem Repo auf `main`.**
claude.ai-Links (`https://claude.ai/artifact/…`), Threads und Pfade unter
`/mnt/project-files/` gehören zum alten Konto und sind vom neuen Konto aus
**nicht** erreichbar. Wo ihr Inhalt wichtig ist, steht er in den Übergabedateien
selbst oder ist ins Repo kopiert.

## Stand

- Alle PRs sind gemergt, keiner ist offen (letzter: #137). `main` vor dieser Datei:
  `1488d66`. Geschlossen ohne Merge: #53, #56, #95.
- Der letzte Mac-Build war PR #120. **Ein Neubau auf dem Mac deckt alles seither ab
  (#121–#137)**; darin steckt Rust (S133, S134, S135), also braucht es den vollen Befehl unten.
- Blind gebaut und nie auf dem Mac geprüft: Oberfläche zu S133/S134 (Staat ›
  Haushalt), Grafikrunden N–Q und #127 (befestigte Wege), echte Porträts unter Metal.

## Die sechs Übergabedateien

| Bereich | Datei | Kurz |
|---|---|---|
| Wirtschaftssimulation, Geldkreislauf | [sim-geldkreislauf.md](sim-geldkreislauf.md) + [Patches und Befund](sim-geldkreislauf/) | S129–S134 gebaut; Läufe, offene Punkte, nächste Schritte |
| Regierung (Steuern, Ausgaben, Schuld, leere Kasse) | [regierung.md](regierung.md) | Plan nach Vic3-Vorbild; Landverkauf/Zahlungsrückstand geplant, nicht gebaut. Abschnitt 5 «PR #128 offen» ist überholt: #128 ist gemergt. |
| Massstab und Wahrzeichen | [massstab.md](massstab.md) | Diorama-Regel S136, Rom gebaut (#125); andere Städte entschieden, nicht gebaut |
| Porträts | [portraits.md](portraits.md) + [`tools/portrait-pipeline/`](../../tools/portrait-pipeline/) (LIESMICH.md) | Blender/MakeHuman-Pipeline, S135 mit Schalter; offene Liste |
| Grafik (Terrain, Wasser, Wege) | [grafik.md](grafik.md) + [`tools/gfx_bench/`](../../tools/gfx_bench/) | Runden A–Q und #127; offene Lücken |
| Performance | [performance.md](performance.md) + [Patches](performance/) | Schritt 1 (#123) erledigt; Schritt 2 Terrain-Shader geplant, nicht angefangen |

Massgebliche Dauerquellen: [`docs/kit2/decisions.md`](../kit2/decisions.md)
(S-Nummern), [`docs/kit2/SCALE.md`](../kit2/SCALE.md) (Massstab),
[`docs/kit2/run-grain/README.md`](../kit2/run-grain/README.md) (Läufe),
[`docs/kit2/PORTRAITS.md`](../kit2/PORTRAITS.md), [`AGENTS.md`](../../AGENTS.md).

## Wie Ramon arbeitet

- Schreibt Schweizerdeutsch; **auf Deutsch antworten** (mit «ss» statt «ß»), kurz, in ganzen Sätzen.
- Vorschlagen, fragen, dann bauen: Ramon entscheidet jeden Schritt (Entscheidungskarte
  mit Empfehlung). **Nur bauen, was besprochen ist**, kein ungefragtes Restyling.
  Wer gemeinsame Systeme anfasst, stimmt sich zuerst ab.
- Modus **«keine Tests, mergen, weiterarbeiten»**: PRs zum Merge anbieten, ohne auf
  einen Mac-Test zu warten. **«mergen» / «alles mergen»** ist die Freigabe, alle offenen
  PRs zu mergen.
- Ökonomie auf dem Stand der Literatur (APA 7), alles emergent und sichtbar, keine
  Preise oder Löhne von oben. Jedes System muss von Rom bis etwa 2000 tragen; im Spiel
  nur historisch belegte Begriffe. Geld bleibt der Denar. Wirkt eine Liste dünn, will er
  mehr Recherche.
- Massstab: Das Spiel ist ein **Diorama** (Land 1:23,8, Menschen ÷566,5). Ausnahmen
  zuerst fragen. Vorschaubilder mit echten Stadthäusern.
- Gesperrte Downloads in der Cloud: kurze Mac-Sitzung zum Holen, keine Freigabe von Cloud-Domains.

## Repo und Mac

- `sim/` = Rust (bevy_ecs) als GDExtension-Bibliothek; `app/` = Godot 4.7, GDScript.
  Rust-Änderungen brauchen einen Neubau auf dem Mac, reine GDScript-Änderungen nur `git pull`.
- Bauen nur über `sim/godot/build.sh`. Gemeinsamer Cache `~/.cache/apoleia-target`
  (eine hängende `.build-lock` nach einem abgebrochenen Build darf mit `rmdir` weg).
- Ramons Befehl (Pull, Neubau, Start):

  ```
  cd ~/Coding/apoleia && git pull && PATH="$HOME/.rustup/toolchains/1.99.1-aarch64-apple-darwin/bin:$PATH" sh sim/godot/build.sh && /Applications/Godot.app/Contents/MacOS/Godot --path app
  ```

- Mac-Sitzungen (Remote Control): **immer nur eine gleichzeitig**, Arbeit unter
  `~/Coding` in einem Ordner, danach löschen. **Kein `git push` vom Mac durch Claude
  ohne Ramons ausdrückliches «push».** Fremden frischen Code baut und startet Ramon im
  eigenen Terminal.
- Die Cloud kann Godot nicht laden; headless Renders mit lavapipe gehen (siehe grafik.md, massstab.md).
- Stolperfallen: Metal-Shader-Absturz (#51), dylib-SIGKILL nach `cp` (#52, Kopie + `mv`),
  nie Lambdas in Statics (#62). Ein frischer Klon braucht `app/.godot/extension_list.cfg`
  mit der Zeile `res://apoleia.gdextension`. Nach Abstürzen hilft
  `-ApplePersistenceIgnoreState YES`. Ladezeiten in `loading.cfg` unter
  Application Support/Godot/app_userdata/Apoleia*.

## Entscheide (S-Nummern)

S133 Staatsausgaben (#121), S134 Staatsschuld (#128), S135 echte Porträts (#124),
S136 Wahrzeichenregel (#125). **Die nächste freie Nummer ist S137.** Bei Konflikten in
`decisions.md` immer alle Zeilen behalten.

## Offene Entscheide und nächste Schritte

1. **Andere Städte nach der Wahrzeichenregel**: Ramon hat «alle nach der Regel»
   entschieden, gebaut ist nichts ([massstab.md §3](massstab.md)).
2. **Rom Schritt 2**: Forum, Pantheon, Tempel, Brücken, ferne Bäume, Szenenwege, Wetter ([massstab.md §4](massstab.md)).
3. **Umschuldungs-Spirale** (Schuld bis 33× Jahreseinnahme): Vorschlag «nur bis zur
   Grenze umschulden», Patch [sim-geldkreislauf/s134-umschuldung-bis-grenze.patch](sim-geldkreislauf/s134-umschuldung-bis-grenze.patch)
   passt auf main; Ramon hat nicht entschieden ([sim-geldkreislauf.md](sim-geldkreislauf.md)).
4. **Missernten** (S101): Vorschlag mit echtem Wetter, Karte nie beantwortet; Daten nur über den Mac holbar.
5. **Zinskarte** (C3) und **wann Landverkauf/Zahlungsrückstand gebaut werden** ([regierung.md §6–7](regierung.md)); auch: wer ist der Spieler.
6. Sim: Erbteil statt Startgeld, Ursache der +9–13 % Hungertote mit befestigten Wegen, Geldleck.
7. **Porträts**: Frauenfrisuren, Kleiderfehler, Kleider nach Epoche, Ausdrücke, Metal-Test, Namenssystem ([portraits.md §4](portraits.md)).
8. **Performance Schritt 2**: Kachelwerte im Terrain-Shader auf Branch `codex/terrain-performance` vorbereitet und unter Metal verglichen; p50 −20,6 % in der Tour mit pausierter Simulation. Noch nicht auf `main`. [Messbericht und Bildprüfung](performance/terrain-cache-2026-10-31.md). Der ursprüngliche Plan steht in [performance.md §4](performance.md).
9. **Grafik**: Pachtfeld unsichtbar (braucht zuerst ein Feld in der Sim-Ansicht),
   N–Q und #127 auf dem Mac ungeprüft, weitere Lücken in [grafik.md](grafik.md).

## Aufräumen auf Ramons Mac (darf er löschen)

`apoleia-crash-logs`, `apoleia-build`, `apoleia-gfx-shots`, `/tmp/apoleia-kit1`,
`~/Coding/howells-tmp`, `~/Coding/apoleia-perf`.
