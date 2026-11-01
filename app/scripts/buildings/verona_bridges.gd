extends Node3D
## Two local bridge assemblies; they never reserve Series plots or alter atlas.
## The bank-anchored deck profiles were measured against the actual GPU corner
## texture. Unequal-bank approaches are explicit pedestrian stairs, not cart ramps.
const Piece = preload("res://scripts/buildings/verona_bridge_piece.gd")
const UNIT := 0.0238
const NORTH_PROFILE := [0.90595, 0.86595, 0.82595, 0.80595, 0.60595]
const EAST_PROFILE := [0.45595, 0.45595, 0.53595, 0.61595, 0.61595]
var entries: Array[Dictionary] = []
var instances: Dictionary = {}
var load_status: Dictionary = {}
var active_groups: Dictionary = {}
var failures: Array[String] = []
var materials: Array[ShaderMaterial] = []
var replacement_mask := 0
var _loaded := {}
var _metadata := {}
var _ready := {}
var _blocked := {}
var _terrain

func setup(terrain) -> void:
	_terrain = terrain
	if terrain.plans == null or not terrain.plans.info.cities.has("verona"): return
	for i in range(4):
		_add("north_%d" % i, "verona_bridge_descent" if i == 3 else "verona_bridge_span", "north", Vector2i(18459, 6914 + i), 1, NORTH_PROFILE[i], NORTH_PROFILE[i + 1], i != 3, i == 3)
		_add("east_%d" % i, "verona_bridge_junction" if i == 0 else "verona_bridge_end" if i == 3 else "verona_bridge_span", "east", Vector2i(18460 + i, 6920), 0, EAST_PROFILE[i], EAST_PROFILE[i + 1], true, false)
	_add("east_stairs", "verona_bridge_stairs", "east", Vector2i(18460, 6920), 0, EAST_PROFILE[0], EAST_PROFILE[0], false, true)

func _add(id: String, asset: String, group: String, parcel: Vector2i, turns: int, start: float, end: float, graded: bool, pedestrian: bool) -> void:
	if _terrain.plans.texel(parcel).x != 10:
		failures.append("Bridge atlas parcel changed: " + str(parcel))
		_blocked[group] = true
		return
	entries.append({"id": id, "asset": asset, "group": group, "parcel": parcel, "rect": [parcel.x, parcel.y, 1, 1], "turns": turns, "deck_start": start, "deck_end": end, "graded": graded, "pedestrian_only": pedestrian})

func required_assets(group: String) -> Array[String]:
	var assets: Array[String] = []
	for spec in entries:
		if spec.group == group and not assets.has(spec.asset): assets.append(spec.asset)
	return assets

func group_loaded(group: String) -> bool:
	if _blocked.has(group) or required_assets(group).is_empty(): return false
	for asset in required_assets(group):
		if not _loaded.has(asset) or not _metadata.has(asset): return false
	return true

func _request(asset: String) -> void:
	if load_status.has(asset): return
	var path := "res://assets/buildings/%s/%s.glb" % [asset, asset]
	if not ResourceLoader.exists(path) or ResourceLoader.load_threaded_request(path) != OK:
		load_status[asset] = "failed"
		failures.append("Bridge asset unavailable: " + asset)
	else: load_status[asset] = "loading"

func _poll() -> void:
	for asset: String in load_status:
		if load_status[asset] != "loading": continue
		var path := "res://assets/buildings/%s/%s.glb" % [asset, asset]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/buildings/%s/model.json" % asset))
			if packed != null and metadata is Dictionary and metadata.get("lod_method", "") == "shape_preserving_v1":
				_loaded[asset] = packed
				_metadata[asset] = metadata
				load_status[asset] = "ready"
			else:
				load_status[asset] = "failed"
				failures.append("Bridge asset invalid: " + asset)
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			load_status[asset] = "failed"
			failures.append("Bridge asset failed to load: " + asset)

func _install_group(group: String) -> void:
	var staged := {}
	for spec in entries:
		if spec.group != group: continue
		var piece := Piece.new()
		piece.visible = false
		add_child(piece)
		staged[spec.id] = piece
		if not piece.setup(spec, _loaded[spec.asset], _metadata[spec.asset], _terrain):
			for node in staged.values(): node.queue_free()
			_blocked[group] = true
			failures.append("Bridge assembly invalid: " + group)
			return
	for id in staged:
		instances[id] = staged[id]
		materials.append_array(staged[id].materials)
	_ready[group] = true

func update_view(width: float, patch: Rect2) -> void:
	_poll()
	var mask := 0
	active_groups.clear()
	for group: String in ["north", "east"]:
		var near: bool = _terrain.sub_tiles and not _blocked.has(group)
		var rect := Rect2(_terrain.world_min + (Vector2(18459, 6914) if group == "north" else Vector2(18460, 6920)) * .25, Vector2(.25, 1.0) if group == "north" else Vector2(1.0, .25))
		near = near and patch.intersects(rect)
		if near:
			for asset in required_assets(group): _request(asset)
			if not _ready.has(group) and group_loaded(group): _install_group(group)
		var active: bool = near and _ready.has(group)
		if active:
			active_groups[group] = true
			mask |= 1 if group == "north" else 2
		for spec in entries:
			if spec.group != group or not instances.has(spec.id): continue
			var piece = instances[spec.id]
			piece.visible = active
			if active: piece.set_view(width)
	if mask != replacement_mask:
		replacement_mask = mask
		_terrain._terrain_material.set_shader_parameter("verona_bridge_groups", mask)
		for material in _terrain._prop_materials: material.set_shader_parameter("verona_bridge_groups", mask)
