extends Node3D
## Authored buildings placed on validated existing parcels. Resources load only
## near their city; failed or pending loads retain the original building.
const Building = preload("res://scripts/buildings/roman_series_building.gd")
const MANIFEST := "res://assets/buildings/roman_series_placements.json"
var materials: Array[ShaderMaterial] = []
var entries: Array[Dictionary] = []
var instances: Dictionary = {}
var reserved: Dictionary = {}
var failures: Array[String] = []
var _pending := {}
var _rects := {}
var _active := {}
var _terrain

func setup(terrain) -> void:
	_terrain = terrain
	if terrain.plans == null or not FileAccess.file_exists(MANIFEST):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not data is Dictionary:
		return
	for spec: Dictionary in data.get("entries", []):
		if not _valid_site(spec):
			failures.append("Invalid placement: " + String(spec.id))
			push_warning(failures[-1])
			continue
		entries.append(spec)
		var r: Array = spec.rect
		_rects[spec.id] = Rect2(terrain.world_min + Vector2(r[0], r[1]) * terrain.plans.parcel_km, Vector2(r[2], r[3]) * terrain.plans.parcel_km)

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

func _request(spec: Dictionary) -> void:
	if instances.has(spec.id) or _pending.has(spec.id):
		return
	var path := "res://assets/buildings/%s/%s.glb" % [spec.id, spec.id]
	if not ResourceLoader.exists(path):
		failures.append("Missing model: " + path)
		_pending[spec.id] = ""
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_pending[spec.id] = path

func _install(spec: Dictionary, packed: PackedScene) -> void:
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/buildings/%s/model.json" % spec.id))
	if not meta is Dictionary or packed == null:
		failures.append("Invalid asset: " + String(spec.id))
		return
	var building := Building.new()
	add_child(building)
	if not building.setup(spec, packed, meta, _terrain):
		failures.append("Could not instantiate: " + String(spec.id))
		building.queue_free()
		return
	building.visible = false
	instances[spec.id] = building
	if not spec.has("landmark"):
		var r: Array = spec.rect
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				reserved[Vector2i(x, y)] = spec.id
		_terrain._town_key = Vector4i(-1, 0, 0, 0)

func update_view(width: float, patch: Rect2) -> void:
	materials.clear()
	for spec in entries:
		var rect: Rect2 = _rects[spec.id]
		var near: bool = _terrain.level <= (1 if spec.has("landmark") else 0)
		var visible_here := near and patch.intersects(rect)
		if visible_here:
			_request(spec)
		if _pending.has(spec.id) and _pending[spec.id] != "" and not instances.has(spec.id):
			var path: String = _pending[spec.id]
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_install(spec, ResourceLoader.load_threaded_get(path) as PackedScene)
				_pending[spec.id] = ""
			elif status == ResourceLoader.THREAD_LOAD_FAILED:
				failures.append("Load failed: " + path)
				_pending[spec.id] = ""
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
