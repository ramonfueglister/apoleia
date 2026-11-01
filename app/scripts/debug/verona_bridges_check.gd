extends "res://scripts/debug/verona_fortifications_check.gd"
## Actual game bridge views, unchanged-city regression and atlas checks.
## Godot --path app --script res://scripts/debug/verona_bridges_check.gd -- --phase=baseline --weather=off
var sample_target := TARGET
var bridge_faces: Dictionary = {}

func bridge_surface_height(b, lod_index: int, local: Vector3, expected: float) -> float:
	var key: String = b.entry.id + str(lod_index)
	if not bridge_faces.has(key):
		var triangles := PackedVector3Array()
		for mesh: MeshInstance3D in b.lods[lod_index].find_children("*", "MeshInstance3D", true, false):
			var relative: Transform3D = b.global_transform.affine_inverse() * mesh.global_transform
			for v: Vector3 in mesh.mesh.get_faces():
				# Independently apply the vertex shader's longitudinal shear before
				# the real imported mesh transform; do not use Piece's CPU helper.
				if b.entry.graded:
					v.y += (v.x / (0.25 / .0238) + .5) * (b.entry.deck_end - b.entry.deck_start) / .0238
				triangles.append(relative * v)
		bridge_faces[key] = triangles
	var triangles: PackedVector3Array = bridge_faces[key]
	# Work in model metres: tiny world-km triangles fall below Geometry3D's
	# fixed ray epsilon, especially in the densely tessellated detail tier.
	var local_height: float = (expected - b.position.y) / .0238
	var start := Vector3(local.x, local_height + .4, local.z)
	var end := Vector3(local.x, local_height - .4, local.z)
	var top := -INF
	for i in range(0, triangles.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(start, end, triangles[i], triangles[i + 1], triangles[i + 2])
		if hit != null: top = maxf(top, b.position.y + hit.y * .0238)
	return top

func bridge_port_audit() -> void:
	var rows: Array = []
	var rays := 0
	var half := .125 / .0238
	for spec: Dictionary in terrain._bridges.entries:
		if not terrain._bridges.instances.has(spec.id): continue
		var b = terrain._bridges.instances[spec.id]
		var ports: Array = []
		if spec.id == "east_stairs":
			ports = [{"point": Vector3(0, 0, -half + .005), "height": .60595, "axis": "z"}]
		else:
			ports.append({"point": Vector3(-half + .005, 0, 0), "height": float(spec.deck_start), "axis": "x"})
			if spec.id != "east_3":
				ports.append({"point": Vector3(half - .005, 0, 0), "height": float(spec.deck_end), "axis": "x"})
		for port in ports:
			for lod_index in range(3):
				for across in [-1.26, 0.0, 1.26]:
					var p: Vector3 = port.point
					if port.axis == "x": p.z = across
					else: p.x = across
					var y := bridge_surface_height(b, lod_index, p, port.height)
					check(is_finite(y) and absf(y - port.height) < .0238 * .025, "Bridge port gap: %s LOD%d lane%.2f expected%.5f actual%.5f" % [spec.id, lod_index, across, port.height, y])
					rays += 1
		rows.append({"id": spec.id, "ports_checked": ports.size()})
	# External joins use the actual GPU terrace elevations, not bridge constants.
	for pair in [["north_0", Vector2i(18459, 6913), "deck_start"], ["north_3", Vector2i(18459, 6918), "deck_end"], ["east_0", Vector2i(18459, 6920), "deck_start"]]:
		var c: Color = _corner_image.get_pixelv(pair[1] - _corner_origin)
		var ground: float = maxf(maxf(c.r, c.g), maxf(c.b, c.a)) * terrain.level_h + .25 * .0238
		check(absf(terrain._bridges.instances[pair[0]].entry[pair[2]] - ground) < .00001, "Bridge does not meet actual bank terrace: " + pair[0])
	report.bridge_ports = {"triangle_rays": rays, "modules": rows, "actual_bank_heights_checked": true}

func bridge_instance_audit() -> void:
	var bridges = terrain._bridges
	check(bridges.entries.size() == 9, "Eight bridge modules and the separate stair must be represented")
	check(bridges.instances.size() == 9, "All bridge modules must load")
	check(bridges.failures.is_empty(), "Bridge asset loader failed")
	check(bridges.active_groups.size() == 2, "Both complete bridge groups must be active nearby")
	var rows: Array = []
	var parcels: Dictionary = {}
	for spec: Dictionary in bridges.entries:
		parcels[spec.parcel] = true
		check(bridges.instances.has(spec.id), "Missing bridge instance: " + spec.id)
		if not bridges.instances.has(spec.id): continue
		var b = bridges.instances[spec.id]
		check(b.scale.is_equal_approx(Vector3.ONE * terrain.DIORAMA_KM_PER_M), "Bridge scale changed: " + spec.id)
		check(b.lods.size() == 3, "Bridge lacks three native LODs: " + spec.id)
		for lod in b.lods:
			check(lod.position.is_zero_approx(), "Bridge authored origin moved: " + spec.id)
		rows.append({"id": spec.id, "asset": spec.asset, "deck_start": spec.deck_start, "deck_end": spec.deck_end, "graded": spec.graded, "pedestrian_only": spec.pedestrian_only})
	check(parcels.size() == 8, "Bridge replacement must cover exactly eight parcels")
	report.bridge_instances = rows

func atlas_bridge_audit() -> void:
	var rows: Array = []
	for i in range(4):
		for p in [Vector2i(18459, 6914 + i), Vector2i(18460 + i, 6920)]:
			var t: Vector3i = terrain.plans.texel(p)
			var links := 5 if p.x == 18459 else 11 if i == 0 else 8 if i == 3 else 10
			check(t.x == 10 and (t.y >> 4) == links and ((t.y >> 2) & 3) == 1, "Bridge graph or road rank changed: " + str(p))
			rows.append({"parcel": [p.x, p.y], "links": t.y >> 4, "rank": (t.y >> 2) & 3, "surface": t.y & 3})
	check(terrain.plans.texel(Vector2i(18464, 6920)).x == 4, "Eastern dead end gained a road")
	report.bridge_atlas = rows

func view(width_km: float) -> void:
	game.target = sample_target
	game._goal_target = sample_target
	game.width = width_km
	game._goal_width = width_km
	game._focus_y = terrain.ground_y(sample_target)
	game._place_camera()

func capture(label: String, target_parcel: Vector2, width_km: float) -> void:
	sample_target = terrain.world_min + target_parcel * terrain.plans.parcel_km
	view(width_km)
	for i in range(45): await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Screenshot failed: " + path)
	var row := {"name": label, "width_km": width_km, "target": [sample_target.x, sample_target.y], "terrain_level": terrain.level, "screenshot": path}
	if phase != "baseline":
		row.native_lods = lod_audit()
		row.bridge_mask = terrain._bridges.replacement_mask
		row.bridge_lods = []
		if not terrain.sub_tiles: check(row.bridge_mask == 0, "Bridge terrain mask persists in distant view")
		for b in terrain._bridges.instances.values():
			var active: bool = terrain._bridges.active_groups.has(b.entry.group)
			check(b.visible == active, "Partial bridge group visibility: " + b.entry.id)
			if not active: continue
			var shown := 0
			for i in b.lods.size():
				if b.lods[i].visible:
					shown += 1
					check(i == b.active_lod and i == b.rendered_lod, "Wrong bridge LOD: " + b.entry.id)
			check(shown == 1, "Bridge must show exactly one native LOD: " + b.entry.id)
			row.bridge_lods.append({"id": b.entry.id, "lod": b.active_lod})
	report.views.append(row)
	save()
	print("VERONA_BRIDGE_VIEW ", label)

func run() -> void:
	phase = "baseline"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
	output = ProjectSettings.globalize_path("res://../build/verona-bridges/" + phase)
	DirAccess.make_dir_recursive_absolute(output)
	report.test = "verona_bridges_check"
	report.phase = phase
	root.size = Vector2i(1440, 1000)
	game = Landscape.instantiate()
	root.add_child(game)
	while game._frame < 5: await process_frame
	game.set_process_unhandled_input(false)
	terrain = game.terrain
	var clock = game.get_node_or_null("GameClock")
	check(clock != null, "Paused GameClock required")
	if clock:
		clock.paused = true
		clock._apply()
	report.renderer = RenderingServer.get_video_adapter_name()
	report.weather = game.weather.describe()
	report.atlas_before = digest(terrain.plans._atlas)
	report.pages_before = digest(terrain.plans._pages)
	atlas_bridge_audit()
	check(DisplayServer.get_name() != "headless", "Normal renderer required")
	check(root.msaa_3d == Viewport.MSAA_4X, "Production antialiasing changed")
	check(is_equal_approx(game.sun.shadow_normal_bias, 2.0), "Production shadow setting changed")
	view(5.0)
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var pending := false
		for spec in terrain._series.entries:
			if spec.city == "verona" and not terrain._series.instances.has(spec.id): pending = true
		if phase != "baseline" and terrain._bridges.instances.size() != 9: pending = true
		if not pending: break
	for i in range(30): await RenderingServer.frame_post_draw
	if phase != "baseline":
		_corner_image = terrain._corner_view.get_texture().get_image()
		_corner_origin = Vector2i(terrain._terrain_material.get_shader_parameter("corner_origin"))
		final_audit()
		bridge_instance_audit()
		bridge_port_audit()
	await capture("north-bridge", Vector2(18459.5, 6916.0), 1.8)
	await capture("east-bridge", Vector2(18462.0, 6920.5), 1.8)
	await capture("north-bank", Vector2(18459.5, 6914.0), .8)
	await capture("gate-junction", Vector2(18460.4, 6920.1), 1.0)
	await capture("east-end", Vector2(18463.5, 6920.5), .8)
	var city_parcel: Vector2 = (TARGET - terrain.world_min) / terrain.plans.parcel_km
	for width_km: float in WIDTHS:
		await capture("city-" + str(width_km), city_parcel, width_km)
	report.atlas_after = digest(terrain.plans._atlas)
	report.pages_after = digest(terrain.plans._pages)
	check(report.atlas_before == report.atlas_after and report.pages_before == report.pages_after, "Atlas or page mapping changed")
	check(terrain._series.failures.is_empty(), "Existing model loader failed")
	report.game_frames = game._frame
	save()
	print("VERONA_BRIDGES_DONE ", output, " failures=", report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
