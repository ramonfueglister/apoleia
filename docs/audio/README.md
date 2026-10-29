# Apoleia: eigener Soundtrack

Referenzversion: `soundtrack-eu5-correspondences-v1-2026-10-26` · Status:
`validiert` für Zuordnung, lokale MP3-Dateien und die beschriebenen technischen
Prüfungen. Die subjektive Hörabnahme bleibt `offen`.

Eigene Designentscheidung zum Nutzerauftrag vom 26.10.2026: historische
Grand-Strategy-Atmosphäre mit Renaissance-/Barockinstrumenten, ruhiger
Entwicklung, Orchester und Gesang. Die 64 Stücke wurden für dieses Projekt
über sunoapi.org erzeugt. Es wurden keine EU4-/EU5-Aufnahmen, Melodien,
Paradox-Assets oder fremden Liedtexte als Vorlage hochgeladen.
Keine Behauptung musikalischer Parität oder pauschaler Rechtefreigabe.

## Stücke und Herkunft

Die EU5-Erweiterung enthält **60 eigenständige Gegenstücke**, jeweils eine
eindeutige eigene Audiodatei pro veröffentlichtem Originaltitel: Basisalbum 26,
Cultures of the World 21, Fate of the Phoenix 4 und Across the Pillars 9.
**24 Gesangsstücke mit eigenen Texten und 36 Instrumentalstücke wurden beauftragt.**
Die Hauptstücke dauern zusammen **2:59:27**, mit den vier erhaltenen bisherigen
Stücken umfasst die Playlist **3:11:26**.

- [Vollständige Originaltitel → eigenes Stück → MP3-Zuordnung](soundtrack-expansion-tracks.md)
- [Recherche, Albumumfang und Quellen](eu5-research.md)
- [Eigene musikalische Entwürfe und Liedtexte](eu5-catalog.json)
- [Dateien, Hashes, technische Metadaten und Task-Herkunft](../../app/assets/music/eu5-correspondences.json)
- [Prüfbericht](soundtrack-expansion-verification.json)

Originaltitel, Reihenfolge und Metadaten sind belegt. Rollen, Tempo, Besetzung,
Liedtexte und neue Kompositionen sind eigene Designentscheidungen. Die
Originalaufnahmen wurden nicht musikalisch abgehört oder als Referenzaudio
hochgeladen; eine klangliche Gleichheit wird nicht behauptet.

Pro Originaltitel wurde gezielt ein eigenständiger Generierungsauftrag erzeugt;
jeweils die erste fertige Variante bildet das eindeutige Gegenstück. Zweite
Varianten bleiben ausschließlich im lokalen Runtimearchiv und zählen nicht als
weitere Zuordnung oder Produktdatei. Ein Auftrag für Pillars01 wurde automatisch
vom Providertextfilter abgewiesen, ohne fertiges Audio. Das ist keine Evidenz
einer tatsächlichen Textübernahme. Ein neuer eigens verfasster spanischer Text
führte zum erfolgreichen gezielten Ersatzlauf. Alter Task und negativer Status
bleiben im Manifest nachvollziehbar. Beobachteter Nettoverbrauch der Erweiterung:
**720 Credits**, Saldo **7560 → 6840**, ohne Creditkauf.

Die bisherigen vier Stücke bleiben als zusätzliche eigene Musik erhalten:

- **The Cartographers Dawn**, zwei Instrumentalvarianten, je knapp drei Minuten.
- **Mare et Terra**, zwei als Gesang beauftragte Varianten mit eigenem
  lateinischem Text über Meer, Land, Arbeit und Eintracht, je knapp drei Minuten.

Die Prompts und der eigens verfasste Liedtext stehen vollständig in
[generation-requests.json](generation-requests.json). Die Latinisierung ist
künstlerischer eigener Text, keine historische Quelle oder geprüfte Übersetzung.
Die [Assetliste](../../app/assets/music/manifest.json) enthält Task-/Audio-IDs,
Dauer, Dateigröße, SHA-256 und technische Prüfergebnisse. Beide API-Tasks
meldeten `SUCCESS`. Angefragt wurde `V6`, jeweils 180 Sekunden. Die zwei
angenommenen Aufträge verbrauchten beobachtet zusammen 24 Credits
(7584 → 7560); es wurden keine Credits gekauft.

## Verwendung im Spiel

Die aktuelle Godot-Landschaftsszene bindet einen separaten Soundtracknode ein.
Die lokale Playlist enthält 64 eindeutige Dateien, läuft zyklisch und spielt
mit zurückhaltender Lautstärke und sanftem Einblenden. Auf ausdrücklichen
Nutzerwunsch startet sie mit **Mare et Terra, Variante 2**. Danach folgen die
60 Gegenstücke in Albumreihenfolge und die übrigen drei bisherigen Stücke.
Eine gespeicherte Stummschaltung bleibt erhalten; das erste Einschalten nach
stummem Start beginnt ebenfalls exakt mit Variante 2.

- **M**: Musik stummschalten/einschalten; Einstellung bleibt lokal gespeichert.
- **N**: nächstes Stück.
- `./scripts/run-landscape -- --mute-music`: ohne Musik starten.
- Headless-Läufe bleiben automatisch ohne Audioarbeit.

Fehlende Dateien werden übersprungen. Für Wiedergabe sind weder Netzwerk
noch API-Schlüssel nötig. Der Schlüssel liegt nicht in diesen Dateien.
Das Paketierungswerkzeug erkennt alle 64 expliziten Ressourcenpfade im
Playlist-Script und das Zuordnungsmanifest.
Der dokumentiert aktuelle lokale Kandidat **Roma Aeterna Candidate 0.19.2.app**
wurde eng um diese Audiodateien, das Script und den Szenenanschluss ergänzt;
Renderpayloads blieben unverändert.
[Erweiterungspatch und Backup](soundtrack-expansion-bundle.json),
[Startliedbeleg](startup-track.json); der [erste Patch](bundle-patch.json)
bleibt als historischer Beleg erhalten.
Das historische **Roma Aeterna Final.app** wurde nicht verändert.
Rust-Wirtschaftskern und spätere Swift-/iPad-Anbindung werden nicht verändert.

## Prüfstand und Grenzen

Alle 60 neuen vollständigen MP3s wurden mit lokalem ffmpeg fehlerfrei decodiert;
ffprobe-Metadaten sind im Manifest festgehalten. Eindeutige Zuordnung und
Dateien/Hashes wurden unabhängig geprüft. Die Godot-Regression umfasst alle 64
Dateien, Playlistumlauf, M/N, Stummschaltung und exakte Startliedbytes.
[Aktuelle Prüfung](soundtrack-expansion-verification.json),
[historischer Vierstücke-Prüfstand](verification.json).
Eine technische Decodierung bestätigt weder die künstlerische Qualität noch
die tatsächliche Verständlichkeit oder Ausführung des Gesangs. Eine subjektive
Hörabnahme bleibt `offen`. iPad-Wiedergabe bleibt `offen`.
Der aktuelle macOS-Kandidat bestand die vollständige Inventarprüfung und
einen Headlessstart mit Exit 0. Ein kurzer nativer Launcherstart bestätigte
die Metal-Laufzeit ohne Scriptfehler; daraus folgt keine neue Bild-/Performanceabnahme.

## Reproduktion

Der Generierungsrunner `app/scripts/generate_soundtrack.py` liest den Schlüssel
ausschließlich aus `SUNO_API_KEY`. Der gespeicherte Taskzustand erlaubt Resume;
eine unklare Submission wird ausdrücklich nicht blind kostenpflichtig wiederholt.
Der Finalizer `app/scripts/finalize_soundtrack.py` verlangt alle 60 fertigen,
eindeutigen Dateien und prüft jede vollständig, bevor er Manifest und Playlist
schreibt. Er erhält die Startliedpräferenz Mare2. Der lokale Bundlepatch
`app/scripts/patch_soundtrack_bundle.py` prüft das vorhandene Inventar, legt ein
Backup an und ändert ausschließlich Audioressourcen und ihre Inventare.

## API-Referenzen

Abgerufen am 26.10.2026:
[Generierung](https://docs.sunoapi.org/suno-api/generate-music),
[Taskstatus](https://docs.sunoapi.org/suno-api/get-music-generation-details),
[Credits](https://docs.sunoapi.org/suno-api/get-remaining-credits).
Die Ergebnisse wurden per Polling abgeholt und lokal gesichert. Das API verlangt
eine Callback-URL; dafür wurde bewusst eine reservierte `.invalid`-Adresse
verwendet. Es wurde kein fremder Callbackempfänger eingerichtet. Ein vorab
ohne Callback abgewiesener Request erzeugte keinen Task.
