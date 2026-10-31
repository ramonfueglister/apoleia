extends SceneTree
## Real-look switch end to end: timings of the builder (simple vs real), then
## faces from the game's own PortraitCache with [portraits] real in display.cfg.
## Args after --: persons.json out.png on|off

var people: Array
var out := ""
var faces := {}
var cache
var frames := 0
var n := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	people = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	out = args[1]
	var on: bool = args[2] == "on"
	for p in people:
		p.dna = PackedByteArray(p.dna)
	var b = ClassDB.instantiate("ApoleiaPortrait")
	b.load(FileAccess.get_file_as_bytes("res://assets/portrait/head.bin.zst"))
	for mode in ["einfach", "echt", "echt (Bilder schon geladen)"]:
		if mode != "echt (Bilder schon geladen)":
			b.set_real("" if mode == "einfach" else ProjectSettings.globalize_path("res://assets/portrait/real"))
		var t0 := Time.get_ticks_usec()
		var tmax := 0
		for p in people:
			var t1 := Time.get_ticks_usec()
			b.build(p, 1)
			tmax = maxi(tmax, Time.get_ticks_usec() - t1)
		print("TIMING %s: %.1f ms je Gesicht, langsamstes %.1f ms" % [mode, (Time.get_ticks_usec() - t0) / 1000.0 / people.size(), tmax / 1000.0])
	b.set_real("")
	var config := ConfigFile.new()
	config.load("user://display.cfg")
	config.set_value("portraits", "real", on)
	config.save("user://display.cfg")
	cache = load("res://scripts/ui/portrait_cache.gd").of(self)
	n = mini(people.size(), 12)

func _process(_dt: float) -> bool:
	frames += 1
	if frames == 2:
		for i in n:
			cache.face(people[i], func(f): faces[i] = f)
	if faces.size() >= n or frames > 600:
		var img := Image.create(224 * 6, 280 * 2, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.1, 0.1, 0.1))
		for i in faces:
			var fi: Image = faces[i].texture.get_image()
			fi.clear_mipmaps()
			fi.convert(Image.FORMAT_RGBA8)
			img.blend_rect(fi, Rect2i(0, 0, 224, 280), Vector2i((i % 6) * 224, (i / 6) * 280))
		img.save_png(out)
		print("FACES ", faces.size())
		quit()
	return false
