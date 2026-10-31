extends SceneTree
## Terrain bench (rounds M to Q, docs/handover/grafik.md): the real terrain
## data seen top-down through app/shaders/_bench_q.gdshader, made by
## tools/gfx_bench/mkbench.py from tile_terrain.gdshader plus a fragment of
## your own (fragment_water_q.glsl), so lavapipe can draw it. Copy this file
## to app/scripts/_bench_terrain.gd (git-excluded) and run
## xvfb-run -a godot --path app --script res://scripts/_bench_terrain.gd -- out_prefix lon lat level_view_km window_km [px_w px_h]
const TileTerrain = preload("res://scripts/tile_terrain.gd")

var terrain: Node3D
var args: PackedStringArray
var frames := -1
var loaded := false
var views: Array = []
var target: Vector2
var view_km: float
var window_km: float
var size_px := Vector2i(960, 540)

func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	view_km = float(args[3])
	window_km = float(args[4])
	if args.size() > 6:
		size_px = Vector2i(int(args[5]), int(args[6]))
	target = Vector2(6371.0088 * cos(deg_to_rad(41.0)) * deg_to_rad(float(args[1]) - 19.0), -6371.0088 * deg_to_rad(float(args[2]) - 41.0))
	var root3d := Node3D.new()
	root.add_child(root3d)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.current = true
	terrain = TileTerrain.new()
	root3d.add_child(terrain)
	_load.call_deferred()

func _load() -> void:
	var ok: bool = await terrain.load_data()
	printerr("terrain loaded ", ok)
	var plain := StandardMaterial3D.new()
	terrain._terrain.visible = false
	terrain._terrain.material_override = plain
	for node in terrain._props:
		node.visible = false
		node.material_override = plain
	for node in terrain._landmarks:
		node.visible = false
		node.material_override = plain
	terrain._coast.material_override = plain
	terrain._coast.visible = false
	terrain.update_view(target, view_km, view_km * 2.5, view_km * 2.0)
	for mode in ["old", "new"]:
		var vp := SubViewport.new()
		vp.size = size_px
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.transparent_bg = false
		var rect := ColorRect.new()
		rect.size = Vector2(size_px)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/_bench_q.gdshader")
		rect.material = mat
		vp.add_child(rect)
		root.add_child(vp)
		views.append([mode, vp, mat])
	loaded = true

func _process(_delta: float) -> bool:
	if not loaded:
		return false
	frames += 1
	if frames == 2:
		terrain.update_view(target, view_km, view_km * 2.5, view_km * 2.0)
	if frames == 4:
		var view_size := Vector2(window_km, window_km * size_px.y / size_px.x)
		for v in views:
			var mat: ShaderMaterial = v[2]
			for u in terrain._terrain_material.shader.get_shader_uniform_list():
				var val = terrain._terrain_material.get_shader_parameter(u.name)
				if val != null:
					mat.set_shader_parameter(u.name, val)
			mat.set_shader_parameter("view_min", target - view_size * 0.5)
			mat.set_shader_parameter("view_size", view_size)
			mat.set_shader_parameter("new_coast", v[0] == "new")
		printerr("level ", terrain.level, " tile_km ", terrain.tile_km)
	if frames == 8:
		var wl = terrain._water_lines
		if wl != null and terrain.level <= 1:
			var img: Image = wl.get_texture().get_image()
			var r: Rect2 = wl.rect
			var view_size := Vector2(window_km, window_km * size_px.y / size_px.x)
			var a := ((target - view_size * 0.5 - r.position) / r.size * img.get_width()).floor()
			var b := ((target + view_size * 0.5 - r.position) / r.size * img.get_width()).ceil()
			var crop := img.get_region(Rect2i(Vector2i(a), Vector2i(b - a)))
			crop.save_png("%s-win.png" % args[0])
			printerr("window ", r, " crop ", crop.get_size())
		for v in views:
			var img: Image = v[1].get_texture().get_image()
			var path: String = "%s-%s.png" % [args[0], v[0]]
			img.save_png(path)
			print("saved ", path)
		return true
	return false
