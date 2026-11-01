extends SceneTree
## Run against the real game, its city atlas, terrain caches and renderer.
const Landscape = preload("res://landscape.tscn")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = Landscape.instantiate()
	root.add_child(game)
	while game._frame < 5:
		await process_frame
	var terrain = game.terrain
	var tavern = terrain._taverna
	check(tavern != null, "Taverna must be installed in the actual terrain")
	if tavern == null:
		quit(1)
		return
	var parcel: Vector2i = tavern.parcel
	var before: Vector3i = terrain.plans.texel(parcel)
	check(before.x == 1, "The original residential parcel must remain intact")
	check(terrain._plan_lots_of(parcel.x, parcel.y, before.x | before.y << 8 | before.z << 16).is_empty(), "Old house must not render on the tavern parcel")
	var neighbour: Vector2i = parcel + Vector2i(1, 0)
	var n: Vector3i = terrain.plans.texel(neighbour)
	check(not terrain._plan_lots_of(neighbour.x, neighbour.y, n.x | n.y << 8 | n.z << 16).is_empty() or terrain._series.reserved.get(neighbour, "") == "baeckerei", "Adjacent parcel must retain a house or the authored bakery")
	check(tavern.materials.size() == 30, "The 30 authored materials must survive import and batching")
	var textured := 0
	for material in tavern.materials:
		if material.get_shader_parameter("has_texture"):
			textured += 1
	check(textured == 9, "All 9 embedded surface textures must survive integration")
	var bounds := AABB()
	var first := true
	for mesh in tavern._lods[0].find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	check(bounds.size.x <= terrain.plans.parcel_km and bounds.size.z <= terrain.plans.parcel_km, "Whole building, props and paving must fit a single parcel")
	var samples := []
	for width in [1.5, 3.0, 8.0, 18.0, 60.0, 120.0, 1.5]:
		game.target = tavern.centre
		game._goal_target = tavern.centre
		game.width = width
		game._goal_width = width
		game._place_camera()
		for i in 12:
			await process_frame
		var expected := 0 if width <= 2.5 else 1 if width <= 7.5 else 2
		check(tavern.active_lod == expected, "Wrong LOD at width %s" % width)
		var shown := 0
		for lod in tavern._lods:
			if lod.visible: shown += 1
		check(shown == 1, "Exactly one LOD must be enabled")
		check(tavern.visible == (terrain.level == 0), "Incorrect handoff to distant town renderer")
		check(terrain.plans.texel(parcel) == before, "Zoom must not mutate the simulation parcel")
		samples.append({"width_km": width, "terrain_level": terrain.level, "sub_tiles": terrain.sub_tiles, "lod": tavern.active_lod, "visible": tavern.visible})
	# Pan away without changing zoom, then return: visibility and replacement recover.
	game.target = game.lonlat_to_world(12.5, 41.9)
	game._goal_target = game.target
	game._place_camera()
	check(not tavern.visible, "Offscreen Verona model must be hidden in Rome")
	game.target = tavern.centre
	game._goal_target = game.target
	game._place_camera()
	check(tavern.visible, "Taverna must reappear when returning to Verona")
	# Changed/missing plans must leave the original house renderer available.
	var missing_plans = terrain.plans.get_script().new()
	missing_plans.info = {"cities": {}}
	var missing = tavern.get_script().new()
	check(not missing.setup(missing_plans, terrain._terrain_material, terrain.DIORAMA_KM_PER_M), "Missing city must decline installation")
	missing.free()
	var report := {"failures": failures, "parcel": [parcel.x, parcel.y], "bounds_km": [bounds.size.x, bounds.size.y, bounds.size.z], "materials": tavern.materials.size(), "textures": textured, "zoom_samples": samples}
	var file := FileAccess.open("user://taverna-integration.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("TAVERNA_INTEGRATION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
