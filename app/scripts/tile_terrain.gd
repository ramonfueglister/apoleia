extends Node3D
## Tile terrain (SimCity 2000 tiles at every zoom). Loads the baked tile data
## (artifacts/render-data/tile-terrain-r1, tools/build_tile_terrain.py), draws
## a patch of tiles around the view with one MultiMesh, and trees and houses
## with four more. All placement happens in the shaders; this script only picks
## the zoom level, moves the patches and answers ground height queries.

const DATA_DIR = "artifacts/render-data/tile-terrain-r1"
const TERRAIN_SHADER = preload("res://shaders/tile_terrain.gdshader")
const PROPS_SHADER = preload("res://shaders/tile_props.gdshader")
const CORNER_PREP_SHADER = preload("res://shaders/tile_corner_prep.gdshader")
const PROP_PREP_SHADER = preload("res://shaders/tile_prop_prep.gdshader")
const SUB_PREP_SHADER = preload("res://shaders/tile_sub_prep.gdshader")
const PropMeshes = preload("res://scripts/tile_prop_meshes.gd")
const LANDMARK_SHADER = preload("res://shaders/tile_landmark.gdshader")

# Zoom levels by tile size. SimCity 2000 tiles at every zoom, up to all of
# Europe. Up close a height level is relief_slope (m/km, from the bake) times
# the tile size, so a ramp rises one level per tile at most, as in SimCity
# 2000; the far levels read their corner levels from the bake (levels-L*.png,
# with their own metres per level, so ranges keep several steps on the world
# map). A level is LEVEL_HEIGHT of the tile on screen, the SimCity 2000 ratio
# (12 px per level on a 32 x 16 px tile); far out a step grows taller
# (LEVEL_HEIGHTS), so the stacked plateaus of the ranges still stand out when a
# tile is a few pixels wide.
const LEVELS := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
const LEVEL_HEIGHT := 0.6
const LEVEL_HEIGHTS := [0.6, 0.6, 0.6, 0.9, 1.2, 1.5]
const PATCH_N := 320 # tiles per side of the terrain patch
const PROP_N := 100 # most tiles per side of the tree and house patch
const PROP_SPAN := 1.7 # prop patch side in view widths (the trees beyond are specks)
const PROP_LOW_KM := 10.0 # from this view width: low-poly props without shadows
const PROP_SLOTS := [9, 0, 0, 0, 0, 0] # tree slots per tile and level (at 1 km tiles trees were a speckle over the relief)
const HOUSE_SLOTS := [4, 9, 9, 9, 0, 0] # house blocks per town tile and level
# Closest zoom (zoom -1): quarter tiles of the 0.5 km data tiles, one house
# (diorama size) per tile as in Urbek. Their cells and landscapes are their
# data tile's, their corners those of the data tiles and, between them, the
# higher one (tt_sub_corner), so the data ramps turn into terraces: a flat
# quarter on the upper step and a quarter ramp below it.
const SUB_KM := 0.25
# a level as high as on the 0.5 km tiles (the hills keep their height when
# the zoom changes; the quarter ramps are twice as steep)
const SUB_LEVEL_HEIGHT := 1.2
const SUB_TREE_SLOTS := 4
const SUB_HOUSE_SLOTS := 1
const SUB_WINDOW := 1024 # quarter tiles per side of sub_tex
const NO_WINDOW := Vector2i(-1048576, 0)
# Far out (2 and 4 km tiles) the houses grow with the tiles, as buildings do
# when SimCity 2000 zooms out: towns stay a mosaic of roofs instead of
# coloured squares. Beyond that towns are roof coloured tiles.
const HOUSE_GROW_FROM_KM := 1.0
# Kit 2 scale (docs/kit2/SCALE.md): lengths 1:23.8 against the real world, but
# houses and trees keep their real size. World units are real km, so a diorama
# metre is DIORAMA_KM_PER_M world units.
const DIORAMA_LAENGE := 1.0 / 23.80
const DIORAMA_KM_PER_M := 0.001 / DIORAMA_LAENGE
const HOUSE_M := 10.0 # house length (house mesh is 1 unit long)
const TREE_M := 8.0  # tree height (tree meshes are about 1.1 units tall; Urbek: 5-8 m, a house 6-12 m)
const PROP_KINDS := ["broadleaf", "conifer", "cypress", "house", "pine"]
# Rome's great buildings (tile_prop_meshes.gd) on blocks of city tiles, drawn
# while the houses are (the two nearest levels). Real shapes at LANDMARK_KM_PER_M
# (6 times their size: next to the 24-times houses they keep the city's tiles
# free for houses), a half higher again (LANDMARK_RISE), so the Colosseum and
# the temples stand above the insulae. Each block is snapped to the 0.5 km
# tiles around its place, the layout after the real city: the Capitol temple
# by the Tiber, the Forum east of it, the Colosseum beyond, the Pantheon in the
# north, the Circus Maximus south of the Palatine, two bridges over the Tiber.
const LANDMARK_KM_PER_M := 0.006
const LANDMARK_RISE := 1.5
const LANDMARK_TILE_KM := 0.5
const LANDMARKS := [
	# mesh, block centre (lon, lat), block size in tiles, free ground around
	# the building (km; a square around the Colosseum and the Circus)
	["temple", Vector2(12.4853, 41.8917), Vector2i(1, 1), 0.09],
	["forum", Vector2(12.4913, 41.8917), Vector2i(1, 1), 0.09],
	["colosseum", Vector2(12.5002, 41.8894), Vector2i(2, 2), 0.2],
	["pantheon", Vector2(12.4853, 41.9007), Vector2i(1, 1), 0.09],
	["circus", Vector2(12.4883, 41.8782), Vector2i(4, 1), 0.15],
	# two Tiber bridges on the river tiles by the Capitol and in the north
	["bridge", Vector2(12.4734, 41.8872), Vector2i(1, 1), 0.0],
	["bridge", Vector2(12.4734, 41.9142), Vector2i(1, 1), 0.0],
]

var manifest: Dictionary
var world_min := Vector2.ZERO
var world_size := Vector2.ONE
var grid_size := Vector2i.ZERO
var level := 2 # data level (LEVELS)
var zoom := 2  # level, or -1 for the quarter tiles of level 0
var sub_tiles := false
var tile_km := 2.0
var m_per_level := 110.0
var level_h := 0.6
var patch_origin := Vector2i.ZERO
var prop_origin := Vector2i.ZERO
var prop_n := PROP_N
var _props_low := false
var _meshes_full: Array = []
var _meshes_low: Array = []

var relief_slope := 80.0
var _heights: PackedFloat32Array
var _relief: PackedFloat32Array
var _cell_images: Array[Image] = []
var _cell_sizes: Array[Vector2i] = []
var _cell_textures: Array[ImageTexture] = []
var _level_images := {}   # zoom level -> baked corner levels (Image, R8)
var _level_textures := {} # far levels: the whole map
var _near_levels := {}    # zoom levels on the near scale (levels-L0/L1, too big for one texture)
# near levels: a LEVEL_WINDOW square of corners around the patch, cut from the
# image when the patch moves on
const LEVEL_WINDOW := 1024
var _level_window: ImageTexture
var _level_window_key := Vector3i(-1, 0, 0) # level, origin
var _landmark_rects := PackedVector4Array()
var _sub_material: ShaderMaterial # 2D pass: quarter tile data around the patch
var _sub_view: SubViewport
var _sub_origin := NO_WINDOW
var _ground_textures := {}  # zoom level -> landscape per tile (two per byte)
var _terrain_material: ShaderMaterial
var _corner_material: ShaderMaterial # 2D pass: corner levels of the patch tiles
var _corner_view: SubViewport
var _place_material: ShaderMaterial # 2D pass: where each tree and house slot stands
var _place_view: SubViewport
var _prop_materials: Array[ShaderMaterial] = []
var _terrain: MultiMeshInstance3D
var _props: Array[MultiMeshInstance3D] = []
var _landmarks: Array[MeshInstance3D] = []

static func data_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()

func load_data() -> bool:
	var dir := data_root().path_join(DATA_DIR)
	var text := FileAccess.get_file_as_string(dir.path_join("manifest.json"))
	if text == "":
		push_error("tile terrain data missing: %s (run tools/build_tile_terrain.py)" % dir)
		return false
	manifest = JSON.parse_string(text)
	var grid: Dictionary = manifest.node_grid
	world_min = Vector2(grid.world_min[0], grid.world_min[1])
	world_size = Vector2(grid.world_size[0], grid.world_size[1])
	grid_size = Vector2i(int(grid.width), int(grid.height))
	var raw := FileAccess.get_file_as_bytes(dir.path_join(manifest.height_half.path))
	var height_image := Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_RH, raw)
	var height_float := height_image.duplicate()
	height_float.convert(Image.FORMAT_RF)
	_heights = height_float.get_data().to_float32_array()
	height_image.generate_mipmaps()
	relief_slope = float(manifest.relief_half.slope_m_per_km)
	raw = FileAccess.get_file_as_bytes(dir.path_join(manifest.relief_half.path))
	var relief_image := Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_RH, raw)
	var relief_float := relief_image.duplicate()
	relief_float.convert(Image.FORMAT_RF)
	_relief = relief_float.get_data().to_float32_array()
	relief_image.generate_mipmaps()
	var shore_texture: ImageTexture = null
	if manifest.has("shore_half"):
		raw = FileAccess.get_file_as_bytes(dir.path_join(manifest.shore_half.path))
		shore_texture = ImageTexture.create_from_image(Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_RH, raw))
	var cover := Image.load_from_file(dir.path_join(manifest.cover.path))
	cover.generate_mipmaps()
	var aux := Image.load_from_file(dir.path_join(manifest.aux.path))
	for entry in manifest.cells:
		var image := Image.load_from_file(dir.path_join(entry.path))
		image.convert(Image.FORMAT_R8)
		_cell_images.append(image)
		_cell_sizes.append(Vector2i(int(entry.width), int(entry.height)))
		_cell_textures.append(ImageTexture.create_from_image(image))
	for entry in manifest.get("levels", []):
		var image := Image.load_from_file(dir.path_join(entry.path))
		image.convert(Image.FORMAT_R8)
		var key := int(entry.level)
		_level_images[key] = image
		if entry.get("scale", "far") == "near":
			_near_levels[key] = true
		else:
			_level_textures[key] = ImageTexture.create_from_image(image)
	for entry in manifest.get("ground", []):
		var image := Image.load_from_file(dir.path_join(entry.path))
		image.convert(Image.FORMAT_R8)
		_ground_textures[int(entry.level)] = ImageTexture.create_from_image(image)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TERRAIN_SHADER
	var shared := {
		"height_tex": ImageTexture.create_from_image(height_image),
		"relief_tex": ImageTexture.create_from_image(relief_image),
		"cover_tex": ImageTexture.create_from_image(cover),
		"aux_tex": ImageTexture.create_from_image(aux),
		"world_min": world_min,
		"world_size": world_size,
		"grid_size": Vector2(grid_size),
		"shore_tex": shore_texture,
		"shore_ready": shore_texture != null,
	}
	_corner_material = ShaderMaterial.new()
	_corner_material.shader = CORNER_PREP_SHADER
	_place_material = ShaderMaterial.new()
	_place_material.shader = PROP_PREP_SHADER
	_sub_material = ShaderMaterial.new()
	_sub_material.shader = SUB_PREP_SHADER
	for kind in PROP_KINDS.size():
		var material := ShaderMaterial.new()
		material.shader = PROPS_SHADER
		material.set_shader_parameter("prop_kind", kind)
		_prop_materials.append(material)
	for material in _all_materials():
		for key in shared:
			material.set_shader_parameter(key, shared[key])
	for key in shared:
		_sub_material.set_shader_parameter(key, shared[key])
	_build_nodes()
	_apply_level(zoom)
	return true

func _all_materials() -> Array[ShaderMaterial]:
	var list: Array[ShaderMaterial] = [_terrain_material, _corner_material, _place_material]
	list.append_array(_prop_materials)
	return list

func _build_nodes() -> void:
	# the quarter tiles' data (before the corner pass, which reads it)
	_sub_view = _prep_view("TileQuarters", Vector2i(SUB_WINDOW, SUB_WINDOW), _sub_material)
	_sub_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for material in _all_materials():
		material.set_shader_parameter("sub_tex", _sub_view.get_texture())
	# the corner levels of the patch (one margin tile for the walls), as
	# float pixels; redrawn every frame because zoom changes them smoothly
	_corner_view = _prep_view("TileCorners", Vector2i(PATCH_N + 2, PATCH_N + 2), _corner_material)
	_terrain_material.set_shader_parameter("corner_tex", _corner_view.get_texture())
	_terrain_material.set_shader_parameter("corner_size", _corner_view.size)
	# one float pixel per prop slot: 3 x 3 per tile, trees left, houses right
	_place_view = _prep_view("TilePropSlots", Vector2i(PROP_N * 6, PROP_N * 3), _place_material)
	_place_material.set_shader_parameter("tree_w", PROP_N * 3)
	var huge := AABB(Vector3(-20000, -100, -20000), Vector3(40000, 2000, 40000))
	_terrain = MultiMeshInstance3D.new()
	_terrain.name = "TileTerrain"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = PropMeshes.tile_template()
	mm.instance_count = PATCH_N * PATCH_N
	_terrain.multimesh = mm
	_terrain.material_override = _terrain_material
	_terrain.custom_aabb = huge
	_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_terrain)
	_terrain_material.set_shader_parameter("patch_n", PATCH_N)
	_meshes_full = [PropMeshes.broadleaf(), PropMeshes.conifer(), PropMeshes.cypress(), PropMeshes.house(), PropMeshes.umbrella_pine()]
	_meshes_low = [PropMeshes.broadleaf(true), PropMeshes.conifer(true), PropMeshes.cypress(true), _meshes_full[3], PropMeshes.umbrella_pine(true)]
	var meshes := _meshes_full
	for kind in PROP_KINDS.size():
		var node := MultiMeshInstance3D.new()
		node.name = "Tile" + PROP_KINDS[kind].capitalize()
		var pm := MultiMesh.new()
		pm.transform_format = MultiMesh.TRANSFORM_3D
		pm.mesh = meshes[kind]
		pm.instance_count = PROP_N * PROP_N * 9
		node.multimesh = pm
		node.material_override = _prop_materials[kind]
		_prop_materials[kind].set_shader_parameter("corner_tex", _corner_view.get_texture())
		_prop_materials[kind].set_shader_parameter("corner_size", _corner_view.size)
		_prop_materials[kind].set_shader_parameter("place_tex", _place_view.get_texture())
		_prop_materials[kind].set_shader_parameter("place_tree_w", PROP_N * 3)
		_prop_materials[kind].set_shader_parameter("place_ready", true)
		node.custom_aabb = huge
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		_props.append(node)
		_prop_materials[kind].set_shader_parameter("prop_n", PROP_N)
	_build_landmarks()

## Same as landscape.gd lonlat_to_world.
static func _lonlat_world(ll: Vector2) -> Vector2:
	return Vector2(6371.0088 * cos(deg_to_rad(41.0)) * deg_to_rad(ll.x - 19.0), -6371.0088 * deg_to_rad(ll.y - 41.0))

func _build_landmarks() -> void:
	var material := ShaderMaterial.new()
	material.shader = LANDMARK_SHADER
	var rects := PackedVector4Array()
	for entry in LANDMARKS:
		var size := Vector2(entry[2])
		var first := ((_lonlat_world(entry[1]) - world_min) / LANDMARK_TILE_KM - size * 0.5).round()
		var lo := world_min + first * LANDMARK_TILE_KM
		var hi := lo + size * LANDMARK_TILE_KM
		var node := MeshInstance3D.new()
		node.name = "Landmark" + String(entry[0]).capitalize()
		node.mesh = PropMeshes.landmark(entry[0])
		node.material_override = material
		node.scale = Vector3(1.0, LANDMARK_RISE, 1.0) * LANDMARK_KM_PER_M
		var centre := (lo + hi) * 0.5
		node.position = Vector3(centre.x, 0.0, centre.y)
		add_child(node)
		_landmarks.append(node)
		# no houses on the block, nor where the building reaches past it
		var reach := node.mesh.get_aabb()
		var a := centre + Vector2(reach.position.x, reach.position.z) * LANDMARK_KM_PER_M
		var b := centre + Vector2(reach.end.x, reach.end.z) * LANDMARK_KM_PER_M
		var free: float = entry[3]
		rects.append(Vector4(minf(lo.x, a.x - free), minf(lo.y, a.y - free), maxf(hi.x, b.x + free), maxf(hi.y, b.y + free)))
	_landmark_rects = rects
	for target in _all_materials() + [_sub_material]:
		target.set_shader_parameter("landmark_rects", rects)

## Up close each landmark block is flat at the middle level of its corners
## (the shader levels the corners in its rectangle); beyond the near levels
## the grown houses fill Rome.
func _place_landmarks() -> void:
	var near := level <= 1
	var levels := PackedFloat32Array()
	for k in _landmarks.size():
		var node := _landmarks[k]
		var r := _landmark_rects[k]
		var found: Array[float] = []
		var image: Image = _level_images.get(level)
		if near and image != null:
			var data_km: float = LEVELS[level]
			var c0 := ((Vector2(r.x, r.y) - world_min) / data_km).ceil()
			var c1 := ((Vector2(r.z, r.w) - world_min) / data_km).floor()
			for j in range(int(c0.y), int(c1.y) + 1):
				for i in range(int(c0.x), int(c1.x) + 1):
					found.append(round(image.get_pixel(i, j).r * 255.0))
		found.sort()
		var at := found[found.size() >> 1] if found.size() > 0 else \
			maxf(1.0, round(ground_y(Vector2(node.position.x, node.position.z)) / level_h))
		levels.append(at)
		node.visible = near
		node.position.y = at * level_h
	var count := _landmarks.size() if near else 0
	for material in _all_materials() + [_sub_material]:
		material.set_shader_parameter("landmark_levels", levels)
		material.set_shader_parameter("landmark_count", count)

## Hide the tree kinds that cannot grow anywhere in the prop patch (the shader
## rule: conifers above 700 m or north of 50°, stone pines and cypresses below
## 700 m south of 44.5°), so their slots cost no vertex work.
var _culled_origin := Vector2i(-1, -1)
func _cull_prop_kinds() -> void:
	if prop_origin == _culled_origin or (PROP_SLOTS[level] == 0 and not sub_tiles):
		return
	_culled_origin = prop_origin
	var lo := world_min + Vector2(prop_origin) * tile_km
	var span := float(prop_n) * tile_km
	var h_min := INF
	var h_max := -INF
	for j in 17:
		for i in 17:
			var h := height_m(lo + Vector2(i, j) / 16.0 * span)
			h_min = minf(h_min, h)
			h_max = maxf(h_max, h)
	var lat_south := 41.0 - rad_to_deg((lo.y + span) / 6371.0088)
	var lat_north := 41.0 - rad_to_deg(lo.y / 6371.0088)
	# a margin for the shader sampling heights at tile centres, not these points
	var conifer := h_max > 600.0 or lat_north > 49.8
	var south := lat_south < 44.7 and h_min < 800.0
	_props[1].visible = conifer
	_props[2].visible = south
	_props[4].visible = south

## A float viewport that redraws `material` over its full size every frame
## (the per-frame 2D passes for corner levels and prop slots).
func _prep_view(view_name: String, size: Vector2i, material: ShaderMaterial) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.size = size
	view.use_hdr_2d = true
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = material
	view.add_child(rect)
	add_child(view)
	return view

## Zoom for a visible ground width (km): about 50 tiles across up close,
## about 250 across the whole Mediterranean; -1 (quarter tiles) up to about
## 12 km.
static func level_for_width(width: float) -> int:
	var across := 50.0 * pow(maxf(width, 1.0) / 25.0, 0.317)
	var tile := width / across
	return clampi(int(round(log(tile / 0.5) / log(2.0) + 0.2)), -1, LEVELS.size() - 1)

func _apply_level(value: int) -> void:
	zoom = value
	level = maxi(value, 0)
	sub_tiles = value < 0
	tile_km = SUB_KM if sub_tiles else LEVELS[level]
	var baked := _level_images.has(level)
	var near_scale := _near_levels.has(level)
	if near_scale:
		_level_window_key = Vector3i(-1, 0, 0)
		_update_level_window()
	m_per_level = relief_slope * tile_km # near levels; far ones are baked (LEVEL_STEPS_M)
	level_h = tile_km * (SUB_LEVEL_HEIGHT if sub_tiles else LEVEL_HEIGHTS[level])
	var params := {
		"cells_tex": _cell_textures[level],
		"cells_size": _cell_sizes[level],
		"tile_km": tile_km,
		"level_h": level_h,
		"m_per_level": m_per_level,
		"height_lod": maxf(0.0, log(tile_km / 2.0) / log(2.0)),
		"levels_ready": baked,
		"levels_tex": _level_window if near_scale else _level_textures.get(level),
		"levels_origin": Vector2i(_level_window_key.y, _level_window_key.z) if near_scale else Vector2i.ZERO,
		"near_scale": near_scale,
		"ground_ready": _ground_textures.has(level),
		"ground_tex": _ground_textures.get(level),
		"sub_tiles": sub_tiles,
	}
	for material in _all_materials():
		for key in params:
			material.set_shader_parameter(key, params[key])
	# the quarter tile pass works on the data tiles
	params.tile_km = LEVELS[level]
	params.sub_tiles = false
	for key in params:
		_sub_material.set_shader_parameter(key, params[key])
	_sub_origin = NO_WINDOW # redrawn by the next update_view
	var slots: int = SUB_TREE_SLOTS if sub_tiles else PROP_SLOTS[level]
	var house_slots: int = SUB_HOUSE_SLOTS if sub_tiles else HOUSE_SLOTS[level]
	# no cast shadows from the tiles once the trees are gone: the shadow map is
	# coarse that far out and only draws streaks; the ramps carry the relief
	_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the slot pass only runs while props are drawn
	_place_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if slots + house_slots > 0 else SubViewport.UPDATE_DISABLED
	_terrain_material.set_shader_parameter("house_grid", int(ceil(sqrt(float(maxi(house_slots, 1))))))
	_terrain_material.set_shader_parameter("town_props", house_slots > 0)
	for kind in _props.size():
		var node := _props[kind]
		var house := kind == 3
		var n: int = house_slots if house else slots
		node.visible = n > 0
		_culled_origin = Vector2i(-1, -1) # _cull_prop_kinds runs again
		node.multimesh.visible_instance_count = prop_n * prop_n * maxi(n, 1)
		var material := _prop_materials[kind]
		material.set_shader_parameter("slots", maxi(n, 1))
		_place_material.set_shader_parameter("house_slots" if house else "tree_slots", n)
		var size_m := HOUSE_M * maxf(1.0, tile_km / HOUSE_GROW_FROM_KM) if house else TREE_M / 1.1
		material.set_shader_parameter("prop_scale", size_m * DIORAMA_KM_PER_M)
	_place_landmarks()

## Cut the near level window around the patch (snapped, so it moves on only
## every quarter window). True when it changed.
func _update_level_window() -> bool:
	var image: Image = _level_images[level]
	var centre := patch_origin + Vector2i(PATCH_N / 2, PATCH_N / 2)
	if sub_tiles:
		centre = Vector2i(centre.x >> 1, centre.y >> 1)
	var origin := ((Vector2(centre) - Vector2(LEVEL_WINDOW / 2, LEVEL_WINDOW / 2)) / float(LEVEL_WINDOW / 4)).floor() * float(LEVEL_WINDOW / 4)
	var o := Vector2i(clampi(int(origin.x), 0, image.get_width() - LEVEL_WINDOW), clampi(int(origin.y), 0, image.get_height() - LEVEL_WINDOW))
	var key := Vector3i(level, o.x, o.y)
	if key == _level_window_key:
		return false
	_level_window_key = key
	var part := image.get_region(Rect2i(o, Vector2i(LEVEL_WINDOW, LEVEL_WINDOW)))
	if _level_window == null:
		_level_window = ImageTexture.create_from_image(part)
	else:
		_level_window.update(part)
	return true

## Move the quarter tile window with the patch (snapped to a quarter window)
## and redraw it once.
func _update_sub_window() -> void:
	var centre := patch_origin + Vector2i(PATCH_N / 2, PATCH_N / 2)
	var step := SUB_WINDOW / 4
	var o := Vector2i(int(floor(float(centre.x - SUB_WINDOW / 2) / step)) * step, int(floor(float(centre.y - SUB_WINDOW / 2) / step)) * step)
	if o == _sub_origin:
		return
	_sub_origin = o
	_sub_material.set_shader_parameter("sub_window_origin", o)
	for material in _all_materials():
		material.set_shader_parameter("sub_origin", o)
	_sub_view.render_target_update_mode = SubViewport.UPDATE_ONCE

## Direction towards the sun (world), for the stylised slope shading.
func set_light_dir(dir: Vector3) -> void:
	_terrain_material.set_shader_parameter("light_dir", dir.normalized())

## Move the patches: `focus` is the ground point the camera looks at, `centre`
## the middle of the visible ground (further back in oblique views).
func update_view(focus: Vector2, centre: Vector2, width: float) -> void:
	var wanted := level_for_width(width)
	if wanted != zoom:
		_apply_level(wanted)
	var c := ((centre - world_min) / tile_km).floor()
	patch_origin = Vector2i(int(c.x) - PATCH_N / 2, int(c.y) - PATCH_N / 2)
	_terrain_material.set_shader_parameter("patch_origin", patch_origin)
	if _near_levels.has(level) and _update_level_window():
		for material in _all_materials() + [_sub_material]:
			material.set_shader_parameter("levels_origin", Vector2i(_level_window_key.y, _level_window_key.z))
		_sub_origin = NO_WINDOW # the quarter data comes from the new window
	var corner_origin := patch_origin - Vector2i.ONE
	for material in _all_materials():
		material.set_shader_parameter("corner_origin", corner_origin)
	# props only around the visible ground: every slot costs vertex work
	var wanted_n := clampi(int(ceil(PROP_SPAN * width / tile_km / 8.0)) * 8 + 4, 12, PROP_N)
	if wanted_n != prop_n:
		prop_n = wanted_n
		_apply_level(zoom)
	# far out the trees are a few pixels tall: low-poly and no shadows
	var low := width > PROP_LOW_KM
	if low != _props_low:
		_props_low = low
		for kind in _props.size():
			_props[kind].multimesh.mesh = (_meshes_low if low else _meshes_full)[kind]
			_props[kind].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if low else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var f := ((focus.lerp(centre, 0.35) - world_min) / tile_km).floor()
	prop_origin = Vector2i(int(f.x) - prop_n / 2, int(f.y) - prop_n / 2)
	for material in _prop_materials:
		material.set_shader_parameter("prop_origin", prop_origin)
		material.set_shader_parameter("prop_n", prop_n)
		material.set_shader_parameter("patch_origin", patch_origin)
	_place_material.set_shader_parameter("prop_origin", prop_origin)
	_place_material.set_shader_parameter("prop_n", prop_n)
	# beyond the prop patch towns are roof coloured tiles again
	_terrain_material.set_shader_parameter("prop_origin", prop_origin)
	_terrain_material.set_shader_parameter("prop_n", prop_n)
	_cull_prop_kinds()
	if sub_tiles:
		_update_sub_window()

# ------------------------------------------------------------- CPU mirror

func height_m(p: Vector2) -> float:
	return _sample(_heights, p)

func relief_m(p: Vector2) -> float:
	return _sample(_relief, p)

func _sample(field: PackedFloat32Array, p: Vector2) -> float:
	var g := (p - world_min) / world_size * Vector2(grid_size - Vector2i.ONE)
	g = g.clamp(Vector2.ZERO, Vector2(grid_size) - Vector2(1.001, 1.001))
	var i := int(g.x)
	var j := int(g.y)
	var f := g - Vector2(i, j)
	var w := grid_size.x
	var a := field[j * w + i]
	var b := field[j * w + i + 1]
	var c := field[(j + 1) * w + i]
	var d := field[(j + 1) * w + i + 1]
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

func water_at(p: Vector2) -> int:
	var data_km: float = LEVELS[level]
	var t := ((p - world_min) / data_km).floor()
	var size := _cell_sizes[level]
	if t.x < 0 or t.y < 0 or t.x >= size.x or t.y >= size.y: return 1
	var b := int(_cell_images[level].get_pixel(int(t.x) >> 1, int(t.y)).r * 255.0 + 0.5)
	var cell := (b & 15) if (int(t.x) & 1) == 0 else (b >> 4)
	return cell & 3

## Smooth display height of the ground (world y) at p, for the camera focus.
func ground_y(p: Vector2) -> float:
	if water_at(p) == 1: return 0.0
	if _level_images.has(level):
		# baked corner levels, bilinear between the four corners around p
		var image: Image = _level_images[level]
		var data_km: float = LEVELS[level]
		var g := ((p - world_min) / data_km).clamp(Vector2.ZERO, Vector2(image.get_size()) - Vector2(1.001, 1.001))
		var i := int(g.x)
		var j := int(g.y)
		var f := g - Vector2(i, j)
		var a := image.get_pixel(i, j).r
		var b := image.get_pixel(i + 1, j).r
		var c := image.get_pixel(i, j + 1).r
		var d := image.get_pixel(i + 1, j + 1).r
		return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y) * 255.0 * level_h
	return maxf(1.0, maxf(relief_m(p), 0.0) / m_per_level) * level_h

## Highest display height in a rectangle (coarse sampling), for the weather.
func max_y(rect: Rect2) -> float:
	var top := 0.0
	for j in 9:
		for i in 9:
			var p := rect.position + rect.size * Vector2(i / 8.0, j / 8.0)
			top = maxf(top, ground_y(p))
	return top + level_h
