extends Node
## What each part of the people costs a frame (people_dots.gd,
## --people-cost=path.json): at the start view, after a warm-up, the frame is
## drawn with everything, then with one part left out at a time (the crops,
## the figures, the walkers, the houses, the shadows of all four, the grain
## economy on the terrain, the placement passes, all of the people) and the frame time, the GPU
## time, the people's own work on the main thread and the triangles and draw calls of the visible and the shadow passes
## are written to the JSON file per phase (medians), with the instances and
## mesh sizes of each part; then the app quits. Runs after PeopleDots in the
## frame (its last child), so the parts it hides stay hidden for that frame.

const WARMUP := 60 # frames before the first phase (pipelines, the placement passes)
const SETTLE := 3 # frames at the start of a phase that are not counted
const PHASES := ["all", "crops", "figures", "walkers", "houses", "shadows", "map", "passes", "people", "all"]

var path := ""
var frames := 12 # counted frames per phase
var _dots: MultiMeshInstance3D
var _frame := 0
var _last := 0
var _phase := 0
var _rows: Array[Dictionary] = []
var _out := {"phases": []}
var _shadows := {} # node -> its own shadow setting, while the shadows are off

func setup(dots: MultiMeshInstance3D, out_path: String, per_phase: int) -> void:
	_dots = dots
	path = out_path
	frames = per_phase
	process_priority = 1000

func _ready() -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last) / 1000.0 if _last > 0 else 0.0
	_last = now
	_frame += 1
	if _frame < WARMUP:
		return
	var f := _frame - WARMUP
	var at := f % (SETTLE + frames)
	if f > 0 and at == 0:
		_finish_phase()
		_phase += 1
		if _phase >= PHASES.size():
			_write()
			return
	if at >= SETTLE and f > 0:
		_rows.append(_measure(ms))
	_hide(PHASES[_phase])

func _hide(what: String) -> void:
	var d := _dots
	match what:
		"crops": d._crops.visible = false
		"figures": d._figures.visible = false
		"walkers": d._trips.visible = false
		"houses":
			for h: MultiMeshInstance3D in d._houses:
				h.visible = false
		"shadows":
			for n: GeometryInstance3D in _casters():
				if not _shadows.has(n):
					_shadows[n] = n.cast_shadow
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"map": d.terrain._terrain_material.set_shader_parameter("sim_map_on", false)
		"passes":
			for v: SubViewport in [d._prep_view, d._house_prep_view, d._lots_view, d._parcel_view]:
				v.render_target_update_mode = SubViewport.UPDATE_DISABLED
		"people": d.visible = false

func _casters() -> Array:
	var out: Array = [_dots._crops, _dots._figures, _dots._trips]
	out.append_array(_dots._houses)
	return out

func _measure(ms: float) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var rs := RenderingServer
	return {
		"ms": ms,
		"gpu": rs.viewport_get_measured_render_time_gpu(vp),
		"cpu": rs.viewport_get_measured_render_time_cpu(vp),
		"tris": rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"tris_shadow": rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		"draws": rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"draws_shadow": rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_SHADOW, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"prep": _dots.prep_runs,
		"figures_listed": _dots._figures.multimesh.visible_instance_count,
		"process": _dots.process_usec / 1000.0,
		"trips": _dots.trips_usec / 1000.0,
	}

func _finish_phase() -> void:
	var row := {"phase": PHASES[_phase]}
	for key in ["ms", "gpu", "cpu", "tris", "tris_shadow", "draws", "draws_shadow", "process", "trips"]:
		var v: Array = _rows.map(func(r: Dictionary) -> float: return float(r[key]))
		v.sort()
		row[key] = v[v.size() / 2] if v.size() > 0 else 0.0
	row["prep_runs"] = _rows[-1].prep - _rows[0].prep if _rows.size() > 1 else 0
	_out.phases.append(row)
	_rows.clear()
	# back as it was
	for n: GeometryInstance3D in _shadows:
		n.cast_shadow = _shadows[n]
	_shadows.clear()
	for h: MultiMeshInstance3D in _dots._houses:
		h.visible = h.multimesh.visible_instance_count != 0
	_dots.terrain._terrain_material.set_shader_parameter("sim_map_on", _dots.map_on)

## The instances and mesh sizes of each part, as drawn in the last frame.
func _parts() -> Dictionary:
	var d := _dots
	var out := {}
	out["crops"] = _part(d._crops)
	out["figures"] = _part(d._figures)
	out["figure_shadows"] = _part(d._figure_shadows)
	out["walkers"] = _part(d._trips)
	var houses := []
	for h: MultiMeshInstance3D in d._houses:
		houses.append(_part(h))
	out["houses"] = houses
	return out

static func _part(n: MultiMeshInstance3D) -> Dictionary:
	var mm := n.multimesh
	var mesh := mm.mesh
	var verts := 0
	var indices := 0
	for s in mesh.get_surface_count():
		verts += mesh.surface_get_array_len(s)
		indices += mesh.surface_get_array_index_len(s)
	var shown := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	return {"instances": shown, "verts": verts, "indices": indices, "shadow": n.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"vertex_runs": shown * (indices if indices > 0 else verts)}

func _write() -> void:
	var landscape := _dots.get_parent()
	_out["view_km"] = landscape.width if "width" in landscape else 0.0
	_out["target"] = [landscape.target.x, landscape.target.y] if "target" in landscape else []
	_out["renderer"] = RenderingServer.get_video_adapter_name()
	_out["size"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	_out["parts"] = _parts()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_out, "  "))
	file.close()
	print(JSON.stringify({"event": "people_cost", "path": path}))
	get_tree().quit()
