# Reale Pan-Diagnose

Status: beobachtet/validiert, Produktkorrektur offen. Keine Verhaltensänderung
durch den Prüfer. Grafikowner übergab nach Driver-Rückgabe einen log-only-Build:
Renderer SHA256 `8604aeb548015c99f68ce2542bee43956db6370ace50ed6a238cd70fe81dc40b`.
Tatsächlich gestartet mit eigenem Telemetrieordner:

```sh
'artifacts/Roma Aeterna Input Diagnostic.app/Contents/MacOS/RomaAeterna' --resolution 1440x810 -- --diagnose-input --telemetry-dir /Users/ramonfuglister/Coding/vic3-clone/runs/kit1-landscape-v5-2026-10-25/independent-review/interactive-diagnostic
```

Danach genau eine echte CUA-Drag-Aktion von[600,400] nach[900,600], anhand des
geöffneten Ausgangsscreenshots. Framebuffer danach unverändert. Kontrolliertes
Schließen via AX-Knopf, Prozess Exit0. Raw unverändert in
`interactive-diagnostic/runtime.json`; sämtliche Motionevents wurden nun
ungefiltert sowohl in `_input` als auch `_unhandled_input` erfasst.

| Sequenz | Ereignis | Frame | Position | event.button_mask | globalmask | relative |
|---|---|---:|---|---:|---:|---|
| 2 | Button1 pressed=true |1746|[800,448]|0|1|nicht anwendbar|
| 3 | MouseMotion |1746|[1200,714.6666870117188]|0|1|[0,0]|
| 4 | Button1 pressed=false |1746|[1200,714.6666870117188]|0|0|nicht anwendbar|

Der reine Diagnosetracker ist während Sequenz3 tatsächlich down1. Auch
screen_relative ist[0,0]. Die beiden Inputphasen bestätigen dieselben
Ereignisobjekte; die Quelle ist in dieser begrenzten Sitzung eindeutig unsere
eine CUA-Aktion. Ein tatsächlicher Positionsdelta kommt während gedrückter
Taste an, wird vom bisherigen Produktpfad wegen mask0/relative0 ignoriert.
Die früher gefilterte Telemetrie hätte diese Motionzeile verschwiegen.

Der Ursprungserzeugungszeitpunkt im OS wird von Godot nicht exponiert und ist
ehrlich null. Beobachtet wurden monotone Empfangszeiten, keine erfundenen
OS-Timestamps. Gleicher Prozessframe allein erklärt den Fehler nicht.

An Grafik/Koordinator gemeldeter minimaler Korrekturansatz: echten eigenen
Buttondown und letzte Ereignisposition verfolgen, Positionsdelta robust
verwenden, valide relative Bewegung dabei nicht doppelt addieren. Erst eine
erneute echte CUA-Dragaktion mit sichtbarer Verschiebung kann die Korrektur
abnehmen. Keine Funktionsfreigabe aufgrund der Diagnose allein.

Driver anschließend erneut explizit an Grafik/Koordinator zurückgegeben;
keine Prüfer-App aktiv. Keine neue Sitzung vor explizitem Fixhandoff.
