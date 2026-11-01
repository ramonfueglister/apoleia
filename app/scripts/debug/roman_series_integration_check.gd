extends SceneTree
## Real Landscape integration tour; run with the normal renderer, not headless:
## godot --path app --script res://scripts/debug/roman_series_integration_check.gd
## Never drives the series loader directly: loading progresses on game frames.
const Landscape = preload("res://landscape.tscn")
const MANIFEST := "res://assets/buildings/roman_series_placements.json"
const OUTPUT := "res://../build/roman-series/integration"
const LOAD_TIMEOUT_MS := 60000
const DETAIL_ONLY := ["amphitheater", "theater", "thermen"]
var failures: Array[String] = []
var report: Dictionary = {"test": "roman_series_landscape_integration", "models": [], "taverna": {}}
var game
var terrain
var series
var output_dir := ""
var parcel_snapshot: Dictionary = {}
var atlas_before := ""
var pages_before := ""
var started_ms := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func _digest(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()

func _packed(texel: Vector3i) -> int:
	return texel.x | texel.y << 8 | texel.z << 16

func _rect(spec: Dictionary) -> Rect2:
	var r: Array = spec.rect
	return Rect2(terrain.world_min + Vector2(r[0], r[1]) * terrain.plans.parcel_km, Vector2(r[2], r[3]) * terrain.plans.parcel_km)

func _cells(spec: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var r: Array = spec.rect
	for y in range(int(r[1]), int(r[1]) + int(r[3])):
		for x in range(int(r[0]), int(r[0]) + int(r[2])):
			result.append(Vector2i(x, y))
	return result

func _save_report() -> void:
	report["failures"] = failures
	report["elapsed_seconds"] = (Time.get_ticks_msec() - started_ms) / 1000.0
	report["game_frames"] = game._frame if is_instance_valid(game) else 0
	var file := FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	else:
		push_error("Cannot write integration report: " + output_dir)

func _settle(frames: int = 12) -> void:
	var before: int = game._frame
	for i in frames:
		await process_frame
	check(game._frame > before, "Landscape game frames must advance during the tour")

func _view(centre: Vector2, width: float) -> void:
	game.target = centre
	game._goal_target = centre
	game.width = width
	game._goal_width = width
	game._focus_y = terrain.ground_y(centre)
	game._place_camera()

func _capture(id: String) -> String:
	var path := output_dir.path_join(id + ".png")
	if DisplayServer.get_name() == "headless":
		check(false, id + ": screenshots require the normal rendered game")
		return ""
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), id + ": viewport screenshot must contain pixels")
	if image == null or image.is_empty():
		return ""
	check(image.save_png(path) == OK, id + ": screenshot could not be saved")
	return path

func _bounds(lod: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in lod.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _atlas_cells_unchanged(context: String) -> void:
	for parcel: Vector2i in parcel_snapshot:
		check(terrain.plans.texel(parcel) == parcel_snapshot[parcel], context + ": simulation parcel changed at " + str(parcel))

func _suppression(spec: Dictionary, building) -> void:
	var id := String(spec.id)
	if spec.has("landmark"):
		check(is_instance_valid(building.source_landmark), id + ": original landmark node must remain available")
		if is_instance_valid(building.source_landmark) and building.visible:
			check(not building.source_landmark.visible, id + ": old landmark must be hidden beneath the authored building")
	else:
		for parcel: Vector2i in _cells(spec):
			check(series.replaces(parcel) and series.reserved.get(parcel, "") == id, id + ": replacement reservation missing at " + str(parcel))
			check(terrain._plan_lots_of(parcel.x, parcel.y, _packed(terrain.plans.texel(parcel))).is_empty(), id + ": original lot still renders at " + str(parcel))

func _lod_sample(spec: Dictionary, building, width: float) -> Dictionary:
	var id := String(spec.id)
	var shown: Array[int] = []
	for i in building.lods.size():
		if building.lods[i].visible:
			shown.append(i)
	check(shown.size() == 1, id + ": exactly one LOD child must be enabled at width " + str(width))
	var active: int = building.active_lod
	var rendered: int = building.rendered_lod
	check(active in [0, 1, 2], id + ": invalid logical LOD")
	var expected_rendered := active if building.native_lods else (0 if id in DETAIL_ONLY else mini(active, 1))
	check(rendered == expected_rendered, id + ": runtime fallback must use the visually approved LOD")
	check(shown.size() == 1 and shown[0] == rendered, id + ": visible child disagrees with rendered_lod")
	var patch := Rect2(terrain.world_min + Vector2(terrain.prop_origin) * terrain.tile_km, Vector2.ONE * terrain.prop_n * terrain.tile_km)
	var expected_visible: bool = terrain.level <= (1 if spec.has("landmark") else 0) and patch.intersects(building.rect)
	check(building.visible == expected_visible, id + ": wrong close/coarse renderer handoff at width " + str(width))
	if building.visible:
		var multiplier: float = maxf(1.0, maxf(building.dimensions_m.x, building.dimensions_m.z) * building.fit / 10.0)
		var expected := 0 if width <= 2.5 * multiplier else 1 if width <= 7.5 * multiplier else 2
		check(active == expected, id + ": logical LOD threshold mismatch at width " + str(width))
	_suppression(spec, building)
	return {"width_km": width, "terrain_level": terrain.level, "logical_lod": active, "rendered_lod": rendered, "visible_children": shown, "visible": building.visible}

func _materials(spec: Dictionary, building) -> Dictionary:
	var id := String(spec.id)
	var source_names := {}
	var textured := {}
	var checked_surfaces := 0
	for lod: Node3D in building.lods:
		for mesh: MeshInstance3D in lod.find_children("*", "MeshInstance3D", true, false):
			check(mesh.mesh != null and mesh.mesh.get_surface_count() > 0, id + ": empty imported mesh")
			if mesh.mesh == null:
				continue
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				var material := mesh.get_surface_override_material(surface) as ShaderMaterial
				check(source != null and material != null, id + ": source or terrain material missing")
				if source == null or material == null:
					continue
				checked_surfaces += 1
				var key: String = source.resource_name
				source_names[key] = true
				var colour: Color = material.get_shader_parameter("base_colour")
				check(colour.is_equal_approx(source.albedo_color), id + ": material colour changed: " + key)
				check(bool(material.get_shader_parameter("has_texture")) == (source.albedo_texture != null), id + ": texture flag lost: " + key)
				check(material.get_shader_parameter("base_texture") == source.albedo_texture, id + ": embedded texture lost: " + key)
				check(is_equal_approx(float(material.get_shader_parameter("material_roughness")), source.roughness), id + ": roughness changed: " + key)
				check(is_equal_approx(float(material.get_shader_parameter("material_metallic")), source.metallic), id + ": metallic changed: " + key)
				var emission: Color = material.get_shader_parameter("emission_colour")
				check(emission.is_equal_approx(source.emission if source.emission_enabled else Color.BLACK), id + ": emission colour changed: " + key)
				if source.albedo_texture != null:
					textured[key] = true
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/buildings/%s/model.json" % id))
	check(source_names.size() == int(meta.lods.detail.material_batches), id + ": authored material batch count changed")
	check(building.materials.size() >= source_names.size() and building.materials.size() <= source_names.size() + 1, id + ": materials must be shared across LODs, plus optional foundation")
	return {"authored_batches": source_names.size(), "runtime_materials": building.materials.size(), "textured_batches": textured.size(), "checked_surfaces": checked_surfaces}

func _visit(spec: Dictionary) -> void:
	var id := String(spec.id)
	var rect := _rect(spec)
	var centre := rect.get_center()
	var close_width := maxf(2.3 if id == "leuchtturm" else 1.5, maxf(rect.size.x, rect.size.y) * 2.4)
	var started: int = Time.get_ticks_msec()
	var frame_before: int = game._frame
	_view(centre, close_width)
	while not series.instances.has(id) and Time.get_ticks_msec() - started < LOAD_TIMEOUT_MS:
		await process_frame
	check(series.instances.has(id), id + ": threaded model failed to install within 60 seconds")
	if not series.instances.has(id):
		report.models.append({"id": id, "load_failed": true})
		_save_report()
		return
	await _settle()
	var loaded_ms: int = Time.get_ticks_msec() - started
	var building = series.instances[id]
	check(game._frame > frame_before, id + ": integration must progress during real game frames")
	check(building.visible and building.is_visible_in_tree(), id + ": model must be visible when visiting its centre")
	check(building.lods.size() == 3, id + ": all three authored LOD roots must survive import")
	if building.lods.size() != 3:
		return
	check(is_equal_approx(building.scale.x, building.scale.y) and is_equal_approx(building.scale.x, building.scale.z), id + ": scale must stay uniform on all axes")
	check(building.fit > 0.0 and building.fit <= 1.0, id + ": invalid uniform parcel fit")
	var bounds := _bounds(building.lods[0])
	var footprint := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
	check(bounds.size.x > 0 and bounds.size.y > 0 and bounds.size.z > 0, id + ": model bounds must be nonempty")
	check(rect.grow(0.001).encloses(footprint), id + ": authored paving/props exceed their allocated parcel rectangle")
	var material_report := _materials(spec, building)
	_suppression(spec, building)
	_atlas_cells_unchanged(id + " installed")
	var image_path: String = await _capture(id)
	var samples: Array = [_lod_sample(spec, building, close_width)]
	var multiplier: float = maxf(1.0, maxf(building.dimensions_m.x, building.dimensions_m.z) * building.fit / 10.0)
	for width: float in [3.5 * multiplier, 8.5 * multiplier, 60.0, 120.0, close_width]:
		_view(centre, width)
		await _settle(6)
		samples.append(_lod_sample(spec, building, width))
		if width >= 120:
			check(not building.visible, id + ": coarse city renderer must take over")
	# A distinct city or distant open terrain guarantees a genuine offscreen move.
	var away: Vector2 = game.lonlat_to_world(-3.0, 38.0)
	_view(away, close_width)
	await _settle(6)
	check(not building.visible, id + ": building must hide after panning away")
	_view(centre, close_width)
	await _settle(8)
	check(series.instances.get(id) == building and building.visible, id + ": same installed model must recover on return")
	_suppression(spec, building)
	_atlas_cells_unchanged(id + " returned")
	report.models.append({"id": id, "city": spec.city, "load_and_settle_ms": loaded_ms, "visit_ms": Time.get_ticks_msec() - started, "start_frame": frame_before, "end_frame": game._frame, "fit": building.fit, "bounds_km": [bounds.size.x, bounds.size.y, bounds.size.z], "rect_km": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "materials": material_report, "zoom_samples": samples, "screenshot": image_path, "away_return": true})
	_save_report()
	print("ROMAN_SERIES_SITE ", id, " frame=", game._frame, " failures=", failures.size())

func _taverna_regression() -> void:
	var tavern = terrain._taverna
	check(tavern != null, "Taverna must still be installed")
	if tavern == null:
		return
	check(tavern.materials.size() == 30, "Taverna must retain all 30 authored materials")
	var textured := 0
	for material: ShaderMaterial in tavern.materials:
		if material.get_shader_parameter("has_texture"):
			textured += 1
	check(textured == 9, "Taverna must retain all 9 embedded surface textures")
	var parcel: Vector2i = tavern.parcel
	var neighbour := parcel + Vector2i(1, 0)
	check(terrain.plans.texel(parcel).x == 1, "Taverna residential simulation parcel must remain intact")
	check(terrain._plan_lots_of(parcel.x, parcel.y, _packed(terrain.plans.texel(parcel))).is_empty(), "Taverna's original house must remain suppressed")
	check(series.reserved.get(neighbour, "") == "baeckerei", "Taverna's adjacent parcel must now contain the accepted bakery")
	check(terrain._plan_lots_of(neighbour.x, neighbour.y, _packed(terrain.plans.texel(neighbour))).is_empty(), "Old house beneath adjacent bakery must be suppressed")
	var samples: Array = []
	for width: float in [1.5, 3.0, 8.0, 18.0, 60.0, 120.0, 1.5]:
		_view(tavern.centre, width)
		await _settle(6)
		var expected := 0 if width <= 2.5 else 1 if width <= 7.5 else 2
		check(tavern.active_lod == expected, "Taverna LOD regression at width " + str(width))
		var shown := 0
		for lod: Node3D in tavern._lods:
			if lod.visible:
				shown += 1
		check(shown == 1, "Taverna must show exactly one LOD")
		check(tavern.visible == (terrain.level == 0), "Taverna coarse renderer handoff regressed")
		samples.append({"width_km": width, "lod": tavern.active_lod, "visible": tavern.visible, "terrain_level": terrain.level})
	var bounds := _bounds(tavern._lods[0])
	check(bounds.size.x <= terrain.plans.parcel_km and bounds.size.z <= terrain.plans.parcel_km, "Taverna must still fit one parcel")
	var capture: String = await _capture("taverna-regression")
	_view(game.lonlat_to_world(-3.0, 38.0), 1.5)
	await _settle(6)
	check(not tavern.visible, "Taverna must hide offscreen")
	_view(tavern.centre, 1.5)
	await _settle(8)
	check(tavern.visible, "Taverna must return after panning back")
	var missing_plans = terrain.plans.get_script().new()
	missing_plans.info = {"cities": {}}
	var missing = tavern.get_script().new()
	check(not missing.setup(missing_plans, terrain._terrain_material, terrain.DIORAMA_KM_PER_M), "Taverna must decline installation when its city is missing")
	missing.free()
	report.taverna = {"materials": tavern.materials.size(), "textures": textured, "adjacent_model": series.reserved.get(neighbour, ""), "bounds_km": [bounds.size.x, bounds.size.y, bounds.size.z], "zoom_samples": samples, "screenshot": capture}

func run() -> void:
	started_ms = Time.get_ticks_msec()
	output_dir = ProjectSettings.globalize_path(OUTPUT)
	check(DirAccess.make_dir_recursive_absolute(output_dir) == OK, "Integration output directory must be writable")
	root.size = Vector2i(1440, 1000)
	game = Landscape.instantiate()
	root.add_child(game)
	while game._frame < 5:
		await process_frame
	terrain = game.terrain
	series = terrain._series
	check(series != null and terrain.plans != null, "Real terrain must install city plans and the Roman series manager")
	if series == null or terrain.plans == null:
		_save_report()
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var entries: Array = manifest.get("entries", [])
	check(entries.size() == 19 and series.entries.size() >= 19, "All 19 existing models must have validated placements")
	atlas_before = _digest(terrain.plans._atlas)
	pages_before = _digest(terrain.plans._pages)
	# Preserve both occupied cells and the complete ring of surrounding parcels.
	for spec: Dictionary in entries:
		var r: Array = spec.rect
		for y in range(int(r[1]) - 1, int(r[1]) + int(r[3]) + 1):
			for x in range(int(r[0]) - 1, int(r[0]) + int(r[2]) + 1):
				var parcel := Vector2i(x, y)
				parcel_snapshot[parcel] = terrain.plans.texel(parcel)
	if terrain._taverna != null:
		parcel_snapshot[terrain._taverna.parcel] = terrain.plans.texel(terrain._taverna.parcel)
	report["atlas_sha256_before"] = atlas_before
	report["pages_sha256_before"] = pages_before
	report["parcels_checked"] = parcel_snapshot.size()
	_save_report()
	for spec: Dictionary in entries:
		await _visit(spec)
	await _taverna_regression()
	_atlas_cells_unchanged("final")
	var atlas_after := _digest(terrain.plans._atlas)
	var pages_after := _digest(terrain.plans._pages)
	check(atlas_after == atlas_before and pages_after == pages_before, "Complete city atlas and page mapping must remain byte-for-byte unchanged")
	check(series.failures.is_empty(), "Series loader failures: " + str(series.failures))
	for spec: Dictionary in entries:
		check(series.instances.has(spec.id), "Base model missing after tour: " + String(spec.id))
	report["atlas_sha256_after"] = atlas_after
	report["pages_sha256_after"] = pages_after
	report["installed_models"] = series.instances.keys()
	report["loader_failures"] = series.failures
	_save_report()
	print("ROMAN_SERIES_INTEGRATION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
