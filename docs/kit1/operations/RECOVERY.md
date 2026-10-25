# Zustand, Wiederaufnahme und Fehlerbehandlung

Referenz `kit1-landscape-v5`. Ersatz für automatische Stop-/Resume-Hooks.

`STATUS.md` ist der aktuelle Einstieg; konkrete Arbeitsläufe verwenden
`PLAN.md`, append-only `PROGRESS.md`, `HANDOFF.md`, `DEFECT.md`, `REPORT.md` aus
`templates/`. Ein Status bezieht sich auf genau benannten Umfang/Revision:
`offen`, `erforscht`, `spezifiziert`, `implementiert`, `validiert`.

Nach Unterbrechung: STATUS → letzter Plan-/Progress-Eintrag → letzter Handoff →
Belegrevision lesen. Laufende Jobs anhand Kennung/Prozess/Providerstatus prüfen.
Erfolg nur bei beobachtetem Ergebnis/Exitcode; Timeout allein ist weder Fehler
noch Erlaubnis für erneute kostenpflichtige Einreichung. Fehler und Ressourcen
zuerst sichern, dann begründeten nächsten Versuch oder echte Blockade protokollieren.

Jeder Fortschrittseintrag enthält UTC-Zeit, Auftrag/Revision, Änderung, Test,
Beleg, nächster Schritt. Kosten/Zeiten unbekannt → `nicht erhoben`, nicht 0.
Keine Zugangsdaten/Token/komplette Umgebungsdump in Protokollen. Nicht während
eines aktiven Laufs seinen Code oder seine Konfig verändern. Dateien zunächst
temporär schreiben und erst nach vollständigem Abschluss als Ergebnis kennzeichnen.

Defekt: Reproschritte + Erwartung + Beobachtung + Build/Daten/Mapping/Fixture +
Bilder/Messwerte + Zuständigkeit. Unterschied zwischen Produktfehler, Datenlücke,
Werkzeugausfall und historischem Rückstand nennen. Historischer Rückstand darf
nicht als Laufzeitfehler verschwinden; Laufzeitfehler nicht als 'Stilisierung'.

Checkpoint bedeutet persistente Dateien und tatsächliche Revision/Hashes.
Git nur benutzen, wenn ein Repository existiert; keins heimlich voraussetzen.
Kein limitumgehender Restart, keine Stop-Blockierung, keine Endlosschleife und
keine automatisch geplante Fortsetzung. Nutzerstop hat Vorrang.
