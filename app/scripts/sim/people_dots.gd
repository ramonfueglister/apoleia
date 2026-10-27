extends MultiMeshInstance3D
## Every simulated person as a black dot (Kit 2 people prototype). Godot holds
## no game state: ApoleiaPeople (Rust GDExtension, sim/godot) runs the people
## on its own thread and hands over the changed pages of its view; this node
## uploads them into one texture array. A 2D pass (people_dots_prep.gdshader)
## works out where each person stands on the terrain, one float pixel per
## person, and runs only when the people or the terrain view changed; all
## people are then drawn with a single MultiMesh whose instances never move
## on the CPU (people_dots.gdshader), two texel fetches per dot.
##
## Dots of people on the road (or on a ship) are dark red.
## Keys: P shows or hides the dots, [ and ] slow down or speed up the days.
## Command line (after --): --people-days=n days per second (default 10),
## --people-bench=path.json writes frame timings with dots on and off
## (relative paths start at the repository root).

const SHADER = preload("res://shaders/people_dots.gdshader")
const SHADER_ROUND = preload("res://shaders/people_dots_round.gdshader")
const ROUND_FROM_PX := 1.75 # below this the dots stay triangles (no discard)
const PREP_SHADER = preload("res://shaders/people_dots_prep.gdshader")
const TileTerrain = preload("res://scripts/tile_terrain.gd")
# terrain uniforms that move the dots; the placement pass reruns when they change
const PLACE_KEYS: Array[StringName] = [&"tile_km", &"relief_smooth", &"corner_origin", &"corner_size", &"m_per_level", &"height_lod", &"cells_size"]
const DOTS_PER_INSTANCE := 64 # people_dots.gdshaderinc, divides the page size
const BENCH_WARMUP := 90
const BENCH_FRAMES := 240

var people: RefCounted
var terrain: Node3D
var days_per_second := 10.0
var _material := ShaderMaterial.new()
var _prep_material := ShaderMaterial.new()
var _prep_view: SubViewport
var _prep_rect: ColorRect
var _place_key := []
var _prep_frames := 0
var prep_runs := 0
var _texture: Texture2DArray
var _shared_uniforms: Array[StringName] = []
var _day_debt := 0.0
var _bench_path := ""
var _bench_frame := 0
var _bench_last := 0
var _bench := {"on": [], "off": [], "on_gpu": [], "off_gpu": [], "sync_usec": [], "sync_layers": [], "prep": [], "process_on": [], "process_off": []}
var _bench_prep_last := 0

## Starts the people sim; false when the GDExtension is not built or the
## inputs are missing (then the caller frees this node).
func setup(tile_terrain: Node3D) -> bool:
	terrain = tile_terrain
	if not ClassDB.class_exists("ApoleiaPeople"):
		push_warning("ApoleiaPeople GDExtension not built (sim/godot/build.sh); people dots off")
		return false
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1) if "=" in arg else ""
		match key:
			"--people-days": days_per_second = float(value)
			"--people-bench": _bench_path = value if value.is_absolute_path() else TileTerrain.data_root().path_join(value)
	people = ClassDB.instantiate("ApoleiaPeople")
	var started := Time.get_ticks_usec()
	if not people.load(TileTerrain.data_root(), 1):
		return false
	print(JSON.stringify({"event": "people_loaded", "people": people.count(), "ms": (Time.get_ticks_usec() - started) / 1000.0}))
	name = "PeopleDots"
	_material.shader = SHADER
	_prep_material.shader = PREP_SHADER
	_prep_view = SubViewport.new()
	_prep_view.name = "PeoplePlaces"
	_prep_view.use_hdr_2d = true # RGBA16F
	_prep_view.transparent_bg = true
	_prep_view.disable_3d = true
	_prep_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_prep_rect = ColorRect.new()
	_prep_rect.material = _prep_material
	_prep_view.add_child(_prep_rect)
	add_child(_prep_view)
	for u in TileTerrain.TERRAIN_SHADER.get_shader_uniform_list():
		_shared_uniforms.append(StringName(u.name))
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	_rebuild()
	if _bench_path != "":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	return true

## Texture and instance count for the current number of pages.
func _rebuild() -> void:
	_texture = people.make_texture()
	var side: int = people.page_side()
	var size := Vector2i(side, side * _texture.get_layers())
	_prep_view.size = size
	_prep_rect.size = Vector2(size)
	for m in [_material, _prep_material]:
		m.set_shader_parameter("people_tex", _texture)
		m.set_shader_parameter("page_side", side)
	_material.set_shader_parameter("place_tex", _prep_view.get_texture())
	_prep_frames = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _dot_mesh()
	mm.instance_count = _texture.get_layers() * people.page_side() * people.page_side() / DOTS_PER_INSTANCE
	multimesh = mm

## DOTS_PER_INSTANCE triangles around the unit circle, z = dot number; the
## shader scales each to pixels and cuts the round dot out of it.
static func _dot_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	for i in DOTS_PER_INSTANCE:
		verts.append_array([Vector3(0, 2, i), Vector3(-1.7320508, -1, i), Vector3(1.7320508, -1, i)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P: visible = not visible
			KEY_BRACKETLEFT: days_per_second = maxf(days_per_second * 0.5, 0.0)
			KEY_BRACKETRIGHT: days_per_second = maxf(days_per_second * 2.0, 1.0)

func _process(delta: float) -> void:
	if people == null:
		return
	_day_debt += days_per_second * delta
	var whole := int(_day_debt)
	if whole > 0 and people.backlog() < 4:
		people.advance(whole)
	_day_debt -= whole
	var synced: int = people.sync(_texture)
	if synced < 0:
		_rebuild()
	# the dots stand on the terrain: same zoom level, relief blend and patch
	var source: ShaderMaterial = terrain._terrain_material
	for key in _shared_uniforms:
		var value = source.get_shader_parameter(key)
		_material.set_shader_parameter(key, value)
		_prep_material.set_shader_parameter(key, value)
	# floats rounded, so the camera settling by a hair does not rerun the pass
	var key_now := PLACE_KEYS.map(func(k):
		var v = source.get_shader_parameter(k)
		return snappedf(v, 0.001) if v is float else v)
	if synced > 0 or key_now != _place_key:
		_place_key = key_now
		_prep_frames = 2 # this frame and the next (the corner cache may lag a frame)
	if _prep_frames > 0 and visible:
		_prep_frames -= 1
		prep_runs += 1
		_prep_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	# 3.5 px up close, about 1.7 px at 360 km and 1 px over the whole sea, so
	# the dots stay single people instead of melting into black regions
	var view_km: float = get_parent().width if "width" in get_parent() else 360.0
	var px := clampf(3.5 - 0.5 * log(maxf(view_km, 1.0) / 30.0) / log(2.0), 1.0, 3.5)
	_material.set_shader_parameter("dot_px", px)
	var want_round := px >= ROUND_FROM_PX
	if want_round != (_material.shader == SHADER_ROUND):
		_material.shader = SHADER_ROUND if want_round else SHADER
		_material.set_shader_parameter("people_tex", _texture)
		_material.set_shader_parameter("page_side", people.page_side())
		_material.set_shader_parameter("place_tex", _prep_view.get_texture())
	if _bench_path != "":
		_bench_step()

func _bench_step() -> void:
	_bench_frame += 1
	var f := _bench_frame - BENCH_WARMUP
	if f < 0:
		return
	var vp := get_viewport().get_viewport_rid()
	var on := f < BENCH_FRAMES
	var tag := "on" if on else "off"
	var now := Time.get_ticks_usec()
	if _bench_last > 0:
		_bench[tag].append((now - _bench_last) / 1000.0) # whole frame, ms
	_bench_last = now
	_bench[tag + "_gpu"].append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if on:
		var t: Dictionary = people.timings()
		_bench.sync_usec.append(t.sync_usec)
		_bench.sync_layers.append(t.sync_layers)
		_bench.prep.append(float(prep_runs - _bench_prep_last))
		_bench.process_on.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	else:
		_bench.process_off.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_bench_prep_last = prep_runs
	if f == BENCH_FRAMES:
		visible = false
	if f == 2 * BENCH_FRAMES:
		var out := {"people": people.count(), "day": people.day(), "instances": multimesh.instance_count,
			"timings_last": people.timings(), "renderer": RenderingServer.get_video_adapter_name(),
			"tile_km": terrain.tile_km, "prep_share": _mean(_bench.prep)}
		for key in _bench:
			var v: Array = _bench[key].duplicate()
			v.sort()
			out[key + "_median"] = v[v.size() / 2] if v.size() > 0 else 0.0
			out[key + "_p95"] = v[int(v.size() * 0.95)] if v.size() > 0 else 0.0
		DirAccess.make_dir_recursive_absolute(_bench_path.get_base_dir())
		var file := FileAccess.open(_bench_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "  "))
		file.close()
		print(JSON.stringify({"event": "people_bench", "path": _bench_path}))
		visible = true

static func _mean(v: Array) -> float:
	var total := 0.0
	for x in v:
		total += x
	return total / maxf(v.size(), 1.0)
