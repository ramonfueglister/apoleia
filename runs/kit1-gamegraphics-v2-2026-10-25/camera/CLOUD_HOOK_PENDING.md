# Separater späterer Wolkenhook

Status `spezifiziert`, nicht in aktuelle Basiscaptures integriert.
Die Dateien `app/scripts/weather/cloud_layer.gd` und zugehöriger Shader gehören
dem autorisierten separaten Wolkenauftrag. Kein paralleler GPU-Driver.

Spätere minimale Einhängung nach Environment/Sun/Camera-Aufbau:

```gdscript
var cloud_layer=preload("res://scripts/weather/cloud_layer.gd").new()
add_child(cloud_layer)
cloud_layer.configure(Rect2(world_min,world_size),camera,{"sun_light":sun_light})
cloud_layer.enabled=false
```

Basiscaptures bleiben explizit deaktiviert; Wolkenprüfung separat. Alte
Altitude-/Opacitydefaults nicht übernehmen. Kein zusätzlicherprocessHook.
