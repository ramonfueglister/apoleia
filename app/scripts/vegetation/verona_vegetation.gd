extends Node3D
## Original Blender plants on Verona's existing GPU tree slots. Readback only
## builds compact instance lists; each vertex rechecks the live slot, so fields,
## roads, pan and terrain height never rely on a stale CPU placement mirror.
const SURFACE = preload("res://shaders/verona_vegetation.gdshader")
const UNIT := .0238
const ORIGIN := Vector2i(18425, 6888)
const SIZE := 64
const ASSETS := ["oak", "shrub", "cypress", "stone_pine", "olive", "willow", "reeds", "courtyard_planter"]
const TREES := ASSETS
var enabled := false
var active_lod := 0
var load_status := {}
var failures: Array[String] = []
var meshes := {}
var batches := {}
var materials := {}
var records: Array[Dictionary] = []
var _terrain
var _mask: Image
var _mask_texture: ImageTexture
var _blocked := false
var _pending := false
var _last_refresh := -1000
var _last_origin := Vector2i(-1, -1)
var _last_n := 0
var refresh_count := 0
var rebuild_count := 0
var refresh_ms := 0.0
var max_refresh_ms := 0.0
var rejected_counts := {}
var fallback_counts := {}
var _last_pixels := PackedByteArray()
var _kind_cache := {}
var _asset_radius := {}

func setup(terrain) -> void:
	_terrain = terrain
	_blocked = terrain.plans == null or not terrain.plans.info.cities.has("verona")
	_mask = Image.create(SIZE * 3, SIZE * 3, false, Image.FORMAT_RG8)
	_mask.fill(Color.BLACK)
	_mask_texture = ImageTexture.create_from_image(_mask)
	var legacy: ShaderMaterial = terrain._prop_materials[0]
	legacy.set_shader_parameter("verona_vegetation_mask", _mask_texture)
	legacy.set_shader_parameter("verona_vegetation_origin", ORIGIN)
	legacy.set_shader_parameter("verona_vegetation_size", SIZE)

func _request() -> void:
	for asset: String in ASSETS:
		if load_status.has(asset): continue
		var path := "res://assets/vegetation/%s/%s.glb" % [asset, asset]
		if not ResourceLoader.exists(path) or ResourceLoader.load_threaded_request(path) != OK:
			load_status[asset] = "failed"
			failures.append("Vegetation unavailable: " + asset)
		else: load_status[asset] = "loading"

func _poll() -> void:
	for asset: String in load_status:
		if load_status[asset] != "loading": continue
		var path := "res://assets/vegetation/%s/%s.glb" % [asset, asset]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			load_status[asset] = "failed"
			failures.append("Vegetation failed to load: " + asset)
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			if packed == null:
				load_status[asset] = "failed"
				continue
			var scene := packed.instantiate()
			var lods: Array[Mesh] = []
			for tag in ["detail", "medium", "far"]:
				var root := scene.find_child("Model_" + tag, true, false)
				var candidates: Array[Node] = []
				if root is MeshInstance3D: candidates.append(root)
				elif root != null: candidates = root.find_children("*", "MeshInstance3D", true, false)
				if candidates.size() == 1:
					var mesh: Mesh = candidates[0].mesh
					if mesh != null and mesh.get_surface_count() > 0: lods.append(mesh)
			scene.free()
			if lods.size() != 3:
				load_status[asset] = "failed"
				failures.append("Vegetation requires three single-mesh native LODs: " + asset)
				continue
			meshes[asset] = lods
			var radius := 0.0
			for mesh in lods:
				for surface in mesh.get_surface_count():
					var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex in vertices: radius = maxf(radius, Vector2(vertex.x, vertex.z).length())
			_asset_radius[asset] = radius
			load_status[asset] = "ready"
			if asset in TREES: _make_batch(asset)

func _make_batch(asset: String) -> void:
	var node := MultiMeshInstance3D.new()
	node.name = asset.capitalize()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_custom_data = true
	node.multimesh.mesh = meshes[asset][active_lod]
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("olive_model", asset == "olive")
	node.material_override = material
	# Vertices are positioned in world space by the shader, not this node.
	var lo: Vector2 = _terrain.world_min + Vector2(ORIGIN) * .25
	node.custom_aabb = AABB(Vector3(lo.x - 1.0, -1.0, lo.y - 1.0), Vector3(SIZE * .25 + 2.0, 20.0, SIZE * .25 + 2.0))
	add_child(node)
	batches[asset] = node
	materials[asset] = material

func update_view(width: float) -> void:
	var region := Rect2(_terrain.world_min + Vector2(ORIGIN) * .25, Vector2.ONE * SIZE * .25)
	var patch := Rect2(_terrain.world_min + Vector2(_terrain.prop_origin) * _terrain.tile_km, Vector2.ONE * _terrain.prop_n * _terrain.tile_km)
	var near: bool = _terrain.sub_tiles and width <= 12.0 and region.intersects(patch) and not _blocked
	if near: _request()
	_poll()
	enabled = near
	for asset in TREES:
		if not meshes.has(asset): enabled = false
	active_lod = 0 if width <= 2.5 else 1 if width <= 7.5 else 2
	_terrain._prop_materials[0].set_shader_parameter("verona_vegetation_active", enabled)
	for asset: String in batches:
		var node: MultiMeshInstance3D = batches[asset]
		node.visible = enabled
		node.multimesh.mesh = meshes[asset][active_lod]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if active_lod == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var material: ShaderMaterial = materials[asset]
		material.set_shader_parameter("native_active", enabled)
		material.set_shader_parameter("place_tex", _terrain._place_view.get_texture())
		material.set_shader_parameter("prop_origin", _terrain.prop_origin)
		material.set_shader_parameter("prop_n", _terrain.prop_n)
		material.set_shader_parameter("world_min", _terrain.world_min)
		material.set_shader_parameter("tile_km", _terrain.tile_km)
		material.set_shader_parameter("level_h", _terrain.level_h)
	if enabled and not _pending and (Time.get_ticks_msec() - _last_refresh >= (2000 if width > 7.5 else 1000) or _last_origin != _terrain.prop_origin or _last_n != _terrain.prop_n):
		_refresh()

func _refresh() -> void:
	_pending = true
	var origin: Vector2i = _terrain.prop_origin
	var n: int = _terrain.prop_n
	await RenderingServer.frame_post_draw
	if not is_inside_tree(): return
	if not enabled or origin != _terrain.prop_origin or n != _terrain.prop_n:
		_pending = false
		return
	var started := Time.get_ticks_usec()
	var image: Image = _terrain._place_view.get_texture().get_image()
	var pixels := image.get_data()
	if pixels == _last_pixels and origin == _last_origin and n == _last_n:
		_finish_refresh(started)
		return
	_last_pixels = pixels
	rebuild_count += 1
	rejected_counts.clear()
	fallback_counts.clear()
	var lists := {}
	for asset in TREES: lists[asset] = []
	var next: Array[Dictionary] = []
	_mask.fill(Color.BLACK)
	var first := origin.max(ORIGIN)
	var end := (origin + Vector2i(n, n)).min(ORIGIN + Vector2i(SIZE, SIZE))
	for y in range(first.y, end.y):
		for x in range(first.x, end.x):
			var tile := Vector2i(x, y)
			var local := tile - origin
			for slot in 4:
				var d := image.get_pixel(local.x * 3 + slot % 3, local.y * 3 + slot / 3)
				if d.a < 0.0: continue
				var code := floori(d.a)
				var edge := fposmod(d.a, 1.0) * 4.0
				var asset := ""
				match code:
					0: asset = "olive" if absf(edge - .6) < .03 else "oak"
					2: asset = "cypress"
					4: asset = "stone_pine"
					5: asset = "shrub"
				if asset == "": continue # keep native conifer habitat on legacy mesh
				var at: Vector2 = _terrain.world_min + (Vector2(tile) + Vector2(d.r, d.g)) * .25
				var bank := _near_bank(tile)
				var civic := _near_civic(tile)
				# Deliberate local garden design: only already-valid tree/shrub
				# slots on open plan land next to the civic fabric. Woodlands
				# elsewhere retain their broadleaf habitat.
				if asset == "oak" and bank and posmod(x * 13 + y * 7 + slot, 3) == 0:
					asset = "willow"
				elif asset == "oak" and civic and posmod(x + y + slot, 3) == 0:
					asset = ["cypress", "stone_pine", "olive"][posmod(x * 7 + y * 2 + slot * 5, 3)]
				elif asset == "shrub" and bank:
					asset = "reeds"
				elif asset == "shrub" and civic and posmod(x + y + slot, 2) == 0:
					asset = "courtyard_planter"
				var size := UNIT * (1.0 if asset == "olive" else edge)
				var radius: float = _asset_radius[asset] * size
				if not _clear_of_built(at, radius + .015):
					# Authored broad crowns do not fit every old voxel tree slot.
					# A narrow civic cypress or low native understory at the SAME
					# valid root is deliberate pruning, never scale-to-fit.
					var original := asset
					asset = "cypress" if civic and code != 5 else "shrub"
					size = UNIT * edge
					if not _clear_of_built(at, float(_asset_radius[asset]) * size + .015):
						asset = "shrub"
					if not _clear_of_built(at, float(_asset_radius[asset]) * size + .015):
						rejected_counts[original] = rejected_counts.get(original, 0) + 1
						continue
					fallback_counts[asset] = fallback_counts.get(asset, 0) + 1
				var yaw := float(posmod(x * 17 + y * 31 + slot * 7, 97)) / 97.0 * TAU
				var record := {"asset": asset, "tile": tile, "slot": slot, "source_code": code, "point": Vector3(at.x, d.b * _terrain.level_h, at.y), "scale": size, "yaw": yaw}
				lists[asset].append(record)
				next.append(record)
				var mask_at := (tile - ORIGIN) * 3 + Vector2i(slot % 3, slot / 3)
				_mask.set_pixelv(mask_at, Color(1.0, float(code + 1) / 255.0, 0.0, 1.0))
	# Lists and mask swap in the same main-thread turn; no frame with hidden
	# voxel trees and absent native counterparts. Global tile IDs survive pan.
	for asset: String in lists:
		var mm: MultiMesh = batches[asset].multimesh
		mm.instance_count = lists[asset].size()
		for i in lists[asset].size():
			var spec: Dictionary = lists[asset][i]
			mm.set_instance_transform(i, Transform3D.IDENTITY)
			mm.set_instance_custom_data(i, Color(spec.tile.x, spec.tile.y, spec.slot + spec.source_code * 8, spec.yaw))
	records = next
	_mask_texture.update(_mask)
	_last_origin = origin
	_last_n = n
	_finish_refresh(started)

func _finish_refresh(started: int) -> void:
	refresh_ms = float(Time.get_ticks_usec() - started) / 1000.0
	max_refresh_ms = maxf(max_refresh_ms, refresh_ms)
	_last_refresh = Time.get_ticks_msec()
	refresh_count += 1
	_pending = false

func _near_bank(tile: Vector2i) -> bool:
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _kind(tile + dir) == 13: return true
	return false

func _near_civic(tile: Vector2i) -> bool:
	if _kind(tile) != 12: return false
	for y in range(-2, 3):
		for x in range(-2, 3):
			if _kind(tile + Vector2i(x, y)) in [1, 2, 3, 5, 6, 7, 11]: return true
	return false

func _clear_of_built(at: Vector2, radius: float) -> bool:
	var lo: Vector2i = _terrain.plans.parcel_at(at.x - radius, at.y - radius)
	var hi: Vector2i = _terrain.plans.parcel_at(at.x + radius, at.y + radius)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if _kind(Vector2i(x, y)) not in [0, 12]: return false
	return true

func _kind(tile: Vector2i) -> int:
	if not _kind_cache.has(tile): _kind_cache[tile] = _terrain.plans.texel(tile).x
	return _kind_cache[tile]
