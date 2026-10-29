extends Node
## Tour benchmark (landscape.gd --tour=result.json): flies a fixed path of
## zooms and pans over the Kit 1 map, set frame by frame (the same path on
## every machine, however fast it runs), and records each frame's time, what
## the terrain changed in it and the pipeline compilations, to find what makes
## the view stutter. The first pass shows first-use costs (shaders, meshes),
## the later ones (--tour-passes, default 2) the steady ones. Writes the
## numbers, the worst frames and their causes to the JSON file and quits.
## `hide` ("trees", "houses", "terrain", "landmarks", "people", "shadows")
## leaves those out, to weigh what each costs against a full tour;
## "people-draw" and "people-process" only draw the people or only stop their
## per-frame work.

# lon, lat, view width (km), frames to get there from the key before
const KEYS := [
	[12.49, 41.89, 3.0, 0],      # Rome up close (quarter tiles)
	[12.49, 41.89, 3.0, 60],
	[12.514, 41.89, 3.0, 120],   # a pan along the city
	[12.5, 41.89, 22.0, 120],    # out over the city
	[12.6, 41.9, 400.0, 240],    # the Tyrrhenian coast
	[17.5, 39.5, 8000.0, 300],   # the whole map
	[17.5, 39.5, 8000.0, 60],
	[29.9, 31.2, 1500.0, 240],   # in towards Alexandria
	[36.2, 36.2, 1500.0, 180],   # across to Antioch
	[36.2, 36.2, 70.0, 300],
	[35.5, 34.0, 70.0, 240],     # down the Levant coast
	[35.5, 34.0, 400.0, 150],
	[23.7, 38.0, 400.0, 300],    # across the sea to Athens
	[23.7, 38.0, 8.0, 300],
	[23.9, 38.1, 8.0, 180],      # over Attica up close
	[23.9, 38.1, 3.0, 90],
]
const COMPILE_MONITORS := [
	Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
	Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
	Performance.PIPELINE_COMPILATIONS_SPECIALIZATION,
]
const WORST := 25

var landscape: Node3D
var out_path := ""
var passes := 2
var warmup := 45
var hide := PackedStringArray()

var _frame := -1
var _pass := 0
var _last_usec := 0
var _total := 0
var _frames: Array[Dictionary] = []
var _results: Array[Dictionary] = []
var _compiles := 0

func _ready() -> void:
	for k in range(1, KEYS.size()):
		_total += int(KEYS[k][3])
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_compiles = _compile_count()

static func _compile_count() -> int:
	var n := 0
	for m in COMPILE_MONITORS:
		n += int(Performance.get_monitor(m))
	return n

## The view (lon, lat, width) at tour frame f.
static func view_at(f: int) -> Vector3:
	for k in range(1, KEYS.size()):
		var n := int(KEYS[k][3])
		if f <= n:
			var a: Array = KEYS[k - 1]
			var b: Array = KEYS[k]
			var t := float(f) / maxf(n, 1)
			return Vector3(lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), exp(lerpf(log(a[2]), log(b[2]), t)))
		f -= n
	var last: Array = KEYS[-1]
	return Vector3(last[0], last[1], last[2])

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var terrain = landscape.terrain
	var events: PackedStringArray = terrain.events.duplicate()
	terrain.events.clear()
	var compiles := _compile_count()
	_hide(terrain)
	_frame += 1
	if _frame >= warmup:
		var f := _frame - warmup
		if f > 0:
			var vp := get_viewport().get_viewport_rid()
			_frames.append({
				"f": f,
				"ms": (now - _last_usec) / 1000.0,
				"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(vp),
				"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(vp),
				"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				"compiles": compiles - _compiles,
				"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				"events": ",".join(events),
				"width": landscape.width,
				"zoom": terrain.zoom,
			})
		if f >= _total:
			_finish_pass()
		else:
			var v := view_at(f + 1)
			landscape._goal_target = landscape.lonlat_to_world(v.x, v.y)
			landscape._goal_width = v.z
	_compiles = compiles
	_last_usec = now

## After the landscape's update in the frame (it sets what is shown), before
## the frame is drawn.
func _hide(terrain: Node3D) -> void:
	if "terrain" in hide:
		terrain._terrain.visible = false
	for kind in terrain._props.size():
		if ("houses" if terrain._is_house(kind) else "trees") in hide:
			terrain._props[kind].visible = false
	if "landmarks" in hide:
		for node in terrain._landmarks:
			node.visible = false
	if landscape.people != null:
		if "people" in hide or "people-draw" in hide:
			landscape.people.visible = false
		if "people" in hide or "people-process" in hide:
			landscape.people.process_mode = Node.PROCESS_MODE_DISABLED # its per-frame work
	landscape.shadows = "shadows" not in hide

func _finish_pass() -> void:
	var result := _summary(_frames)
	result.pass = _pass + 1
	_results.append(result)
	print(JSON.stringify({"event": "tour_pass", "pass": _pass + 1, "p50_ms": result.p50_ms, "p95_ms": result.p95_ms,
		"p99_ms": result.p99_ms, "max_ms": result.max_ms, "over_33_ms": result.over_33_ms, "over_50_ms": result.over_50_ms}))
	_pass += 1
	_frames.clear()
	if _pass < passes:
		_frame = warmup - 30 # the next pass from the start view, half a second to settle there
		var v := view_at(0)
		landscape.target = landscape.lonlat_to_world(v.x, v.y)
		landscape._goal_target = landscape.target
		landscape.width = v.z
		landscape._goal_width = v.z
		return
	var out := {
		"renderer": RenderingServer.get_video_adapter_name(),
		"window": get_viewport().get_visible_rect().size,
		"refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"hidden": ",".join(hide),
		"passes": _results,
	}
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	print(JSON.stringify({"event": "tour_done", "path": ProjectSettings.globalize_path(out_path)}))
	get_tree().quit()

static func _pct(sorted: Array, q: float) -> float:
	return sorted[clampi(int(sorted.size() * q), 0, sorted.size() - 1)] if sorted.size() > 0 else 0.0

static func _summary(frames: Array[Dictionary]) -> Dictionary:
	var ms: Array = frames.map(func(r: Dictionary) -> float: return r.ms)
	ms.sort()
	var out := {
		"frames": frames.size(),
		"p50_ms": _pct(ms, 0.5), "p90_ms": _pct(ms, 0.9), "p95_ms": _pct(ms, 0.95),
		"p99_ms": _pct(ms, 0.99), "max_ms": ms[-1] if ms.size() > 0 else 0.0,
		"over_20_ms": ms.filter(func(x: float) -> bool: return x > 20.0).size(),
		"over_33_ms": ms.filter(func(x: float) -> bool: return x > 33.4).size(),
		"over_50_ms": ms.filter(func(x: float) -> bool: return x > 50.0).size(),
		"compiles": frames.reduce(func(n: int, r: Dictionary) -> int: return n + r.compiles, 0),
	}
	# steady cost per zoom level
	var levels := {}
	for r in frames:
		var key := str(r.zoom)
		if not levels.has(key):
			levels[key] = []
		levels[key].append(r)
	var per_level := {}
	for key in levels:
		var rows: Array = levels[key]
		var t: Array = rows.map(func(r: Dictionary) -> float: return r.ms)
		t.sort()
		var g: Array = rows.map(func(r: Dictionary) -> float: return r.gpu_ms)
		g.sort()
		var c: Array = rows.map(func(r: Dictionary) -> float: return r.process_ms)
		c.sort()
		var rc: Array = rows.map(func(r: Dictionary) -> float: return r.render_cpu_ms)
		rc.sort()
		per_level[key] = {
			"frames": rows.size(), "p50_ms": _pct(t, 0.5), "p95_ms": _pct(t, 0.95),
			"gpu_p50_ms": _pct(g, 0.5), "gpu_p95_ms": _pct(g, 0.95),
			"process_p50_ms": _pct(c, 0.5), "render_cpu_p50_ms": _pct(rc, 0.5),
			"draws": rows[rows.size() / 2].draws, "prims": rows[rows.size() / 2].prims,
		}
	out.per_level = per_level
	# the worst frames, each with what happened in it and the frame before
	var order := range(frames.size())
	order.sort_custom(func(a: int, b: int) -> bool: return frames[a].ms > frames[b].ms)
	var worst := []
	for i in order.slice(0, WORST):
		var r: Dictionary = frames[i].duplicate()
		r.events_before = frames[i - 1].events if i > 0 else ""
		r.compiles_before = frames[i - 1].compiles if i > 0 else 0
		worst.append(r)
	out.worst = worst
	# how slow the frames after each kind of change are
	var by_event := {}
	for i in frames.size():
		var names := {}
		for e in (frames[i].events + "," + (frames[i - 1].events if i > 0 else "")).split(",", false):
			names[e.get_slice(" ", 0)] = true
		for e in names:
			if not by_event.has(e):
				by_event[e] = []
			by_event[e].append(frames[i].ms)
	var events := {}
	for e in by_event:
		var t: Array = by_event[e]
		t.sort()
		events[e] = {"frames": t.size(), "p50_ms": _pct(t, 0.5), "max_ms": t[-1]}
	out.events = events
	return out
