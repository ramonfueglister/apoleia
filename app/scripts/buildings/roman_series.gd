extends Node3D
## Authored buildings on validated parcels. Shared assets load once; originals
## remain until each replacement is installed, including individual street pieces.
const Building = preload("res://scripts/buildings/roman_series_building.gd")
const MANIFEST := "res://assets/buildings/roman_series_placements.json"
const VERONA := "res://assets/buildings/verona_residences.json"
var materials: Array[ShaderMaterial] = []
var entries: Array[Dictionary] = []
var instances: Dictionary = {}
var reserved: Dictionary = {}
var street_reserved: Dictionary = {}
var failures: Array[String] = []
var _pending := {}
var _loaded := {}
var _metadata := {}
var _rects := {}
var _active := {}
var _terrain

func setup(terrain) -> void:
	_terrain = terrain
	if terrain.plans == null:
		return
	for manifest in [MANIFEST, VERONA]:
		if not FileAccess.file_exists(manifest):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if data is Dictionary:
			for spec: Dictionary in data.get("entries", []):
				_register(spec)
	_add_verona_streets()

func _register(spec: Dictionary) -> void:
	if _rects.has(spec.id) or not _valid_site(spec):
		failures.append("Invalid placement: " + String(spec.id))
		push_warning(failures[-1])
		return
	entries.append(spec)
	var r: Array = spec.rect
	_rects[spec.id] = Rect2(_terrain.world_min + Vector2(r[0], r[1]) * _terrain.plans.parcel_km, Vector2(r[2], r[3]) * _terrain.plans.parcel_km)

func _add_verona_streets() -> void:
	if not _terrain.plans.info.cities.has("verona"):
		return
	var city: Dictionary = _terrain.plans.info.cities.verona
	for y in range(int(city.origin[1]), int(city.origin[1] + city.size[1])):
		for x in range(int(city.origin[0]), int(city.origin[0] + city.size[0])):
			var parcel := Vector2i(x, y)
			var texel: Vector3i = _terrain.plans.texel(parcel)
			if texel.x != 7:
				continue
			var pieces: Array = _terrain._plan_street(parcel, texel.y)
			for i in pieces.size():
				var piece: Vector2i = pieces[i]
				var kind: String = _terrain.LOT_KINDS[piece.x][0]
				if kind not in ["street_row", "street_corner_w", "street_corner_e"]:
					continue
				var variant: int = _terrain.LOT_KINDS[piece.x][1]
				var low := variant >= (5 if kind == "street_row" else 4)
				# Original street pieces occupy three cells along the north edge.
				# Keep their placement and rotation; the central road stays clear.
				var offset := Vector2(0 if kind == "street_row" else -3.45 if kind == "street_corner_w" else 3.45, -3.45)
				offset = offset.rotated(piece.y * PI * 0.5)
				_register({"id": "verona_street_%d_%d_%d" % [x, y, i], "asset": "verona_street_shop" if low else "verona_street_house", "city": "verona", "label": "Taberna" if low else "Strassenhaus", "rect": [x, y, 1, 1], "expected_kinds": [7], "turns": piece.y, "street_piece": piece, "offset_m": [offset.x, offset.y], "facade_tint": ["ffffff", "ead9b5", "f1e5d2"][(x * 31 + y * 17 + i) % 3]})

func _valid_site(spec: Dictionary) -> bool:
	if not _terrain.plans.info.cities.has(spec.city):
		return false
	var r: Array = spec.rect
	var allowed := PackedInt32Array(spec.expected_kinds)
	for y in range(int(r[1]), int(r[1]) + int(r[3])):
		for x in range(int(r[0]), int(r[0]) + int(r[2])):
			if _terrain.plans.texel(Vector2i(x, y)).x not in allowed:
				return false
	return true

func replaces(parcel: Vector2i) -> bool:
	return reserved.has(parcel)

func filter_street_lots(parcel: Vector2i, original: Array) -> Array:
	if not street_reserved.has(parcel):
		return original
	return original.filter(func(piece: Vector2i) -> bool: return not street_reserved[parcel].has(piece))

func _asset(spec: Dictionary) -> String:
	return String(spec.get("asset", spec.id))

func _request(spec: Dictionary) -> void:
	var asset := _asset(spec)
	if _loaded.has(asset) or _pending.has(asset):
		return
	var path := "res://assets/buildings/%s/%s.glb" % [asset, asset]
	if not ResourceLoader.exists(path):
		failures.append("Missing model: " + path)
		_pending[asset] = ""
		return
	var error := ResourceLoader.load_threaded_request(path)
	_pending[asset] = path if error == OK else ""
	if error != OK:
		failures.append("Could not request model: " + path)

func _poll_resources() -> void:
	for asset: String in _pending:
		var path: String = _pending[asset]
		if path.is_empty():
			continue
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/buildings/%s/model.json" % asset))
			if packed != null and meta is Dictionary:
				_loaded[asset] = packed
				_metadata[asset] = meta
			else:
				failures.append("Invalid asset: " + asset)
			_pending[asset] = ""
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			failures.append("Load failed: " + path)
			_pending[asset] = ""

func _install(spec: Dictionary) -> void:
	var asset := _asset(spec)
	var building := Building.new()
	add_child(building)
	if not building.setup(spec, _loaded[asset], _metadata[asset], _terrain):
		failures.append("Could not instantiate: " + String(spec.id))
		building.queue_free()
		return
	building.visible = false
	instances[spec.id] = building
	var r: Array = spec.rect
	if spec.has("street_piece"):
		var parcel := Vector2i(r[0], r[1])
		if not street_reserved.has(parcel):
			street_reserved[parcel] = {}
		street_reserved[parcel][spec.street_piece] = spec.id
	elif not spec.has("landmark"):
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				reserved[Vector2i(x, y)] = spec.id
	_terrain._town_key = Vector4i(-1, 0, 0, 0)

func update_view(width: float, patch: Rect2) -> void:
	materials.clear()
	_poll_resources()
	for spec in entries:
		var rect: Rect2 = _rects[spec.id]
		var near: bool = _terrain.level <= (1 if spec.has("landmark") else 0)
		var visible_here := near and patch.intersects(rect)
		if visible_here:
			_request(spec)
			if not instances.has(spec.id) and _loaded.has(_asset(spec)):
				_install(spec)
		if not instances.has(spec.id):
			continue
		var building = instances[spec.id]
		if visible_here and not _active.get(spec.id, false):
			building.sync_uniforms(_terrain._terrain_material)
		_active[spec.id] = visible_here
		building.visible = visible_here
		if building.source_landmark != null:
			var terrain_patch := Rect2(_terrain.world_min + Vector2(_terrain.patch_origin) * _terrain.tile_km, Vector2.ONE * _terrain.PATCH_N * _terrain.tile_km)
			building.source_landmark.visible = _terrain.level <= 1 and terrain_patch.intersects(rect) and not visible_here
		if visible_here:
			building.set_view(width, _terrain.ground_y(building.centre))
			materials.append_array(building.materials)
