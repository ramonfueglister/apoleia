# Paket, Vollständigkeit und Weitergabe

`REFERENCE_MAP.json` erfasst jeden Eintrag des Referenzarchivs mit SHA-256,
Größe, Entscheidung und Zielpfaden. `REFERENCE_MAP.md` erklärt Kategorien.
Keine Assets/Skripte des fremden MMO-Referenzarchivs werden kopiert. Die explizit
beauftragten sechs offiziellen Urbek-/Victoria-3-Screenshots sind getrennte
Referenzdateien mit Provenienz, keine Produktassets.

```sh
python3 tools/kit.py self-check
python3 tools/kit.py package ../../artifacts/kit1-build-kit.zip
python3 tools/kit.py verify-package ../../artifacts/kit1-build-kit.zip
```

`package` verweigert vorhandene Ziele und prüft vorher Kit-Konsistenz. Es nimmt
nur die dokumentierten Kit-Dateien, keine Laufordner/Geodaten, Secrets, fremden
Archive oder `__pycache__` auf. Das ZIP enthält `KIT_MANIFEST.json` mit SHA-256
und Größe jeder mitgelieferten Datei. Verpacken ist kein Installieren und startet
keine App. `verify-package` prüft Pfadsicherheit, Dubletten, Kitversion, Pflichtdateien,
Übereinstimmung mit dem eingepackten KIT_CONTENTS-Inventar und Dateihashes,
ohne Archive zu extrahieren. Ein unverändertes Manifest beweist Integrität,
nicht Herkunftsrechte oder Produktfunktion.

Empfänger entpackt in einen neuen Ordner und liest README. Die nutzerbereitgestellte
Primärreferenz und eine nachrangige Fernstilprobe sind im
[Landschafts-Stilguide](../references/STYLE_GUIDE.md) enthalten; die Fernprobe
belegt nicht die flache 2D-Kamera. Zusätzlich enthält [der Screenshotkatalog](../references/screenshots/README.md)
sechs unveränderte Drittspielaufnahmen mit Herkunft und konkreten
Übernahme-/Nichtübernahmehinweisen. Das erste abgelehnte Bild ist nicht
mitgeliefert. REFERENCES beschreibt Herkunft und Grenzen. Alle notwendigen Entscheidungen/Arbeitsprozesse und
Formate sind lokal vorhanden. Keine nicht vorhandenen Abbildungen als enthalten
bewerben. Laufdaten außerhalb des Kitordners ablegen; nur bewusst freigegebene
Artefakte weitergeben, keine Kontohistorie oder lokalen Credentials.

Vor dem Verpacken bindet `self-check` die lokalen Referenzbilder an die SHA-256-
Werte ihrer Provenienzmanifeste. Eine Bildänderung mit unveränderter Provenienz
blockiert damit die Paketerstellung. Ein leeres oder falsch versioniertes ZIP
besteht die Paketprüfung nicht mehr. Keiner dieser Tests ersetzt die Sichtprüfung.
