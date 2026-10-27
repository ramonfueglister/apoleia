extends Node3D
## Tile terrain (SimCity 2000 meets EU5). Loads the baked tile data
## (artifacts/render-data/tile-terrain-r1, tools/build_tile_terrain.py), draws
## a patch of tiles around the view with one MultiMesh, and trees and houses
## with four more. All placement happens in the shaders; this script only picks
## the zoom level, moves the patches and answers ground height queries.

const DATA_DIR = "artifacts/render-data/tile-terrain-r1"
const TERRAIN_SHADER = preload("res://shaders/tile_terrain.gdshader")
const PROPS_SHADER = preload("res://shaders/tile_props.gdshader")
const CORNER_PREP_SHADER = preload("res://shaders/tile_corner_prep.gdshader")
const PROP_PREP_SHADER = preload("res://shaders/tile_prop_prep.gdshader")
const PropMeshes = preload("res://scripts/tile_prop_meshes.gd")

# Zoom levels by tile size. A height level is relief_slope (m/km, from the
# bake) times the tile size, so a ramp rises one level per tile at most, as in
# SimCity 2000. Its height on screen is LEVEL_HEIGHT of the tile, the SimCity
# 2000 ratio (12 px per level on a 32 x 16 px tile).
const LEVELS := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
const LEVEL_HEIGHT := 0.6
const SMOOTH_FROM_KM := 20.0 # view width where the tile steps start to melt
const SMOOTH_TO_KM := 45.0   # view width from where the relief is fully smooth
const PATCH_N := 320 # tiles per side of the terrain patch
const PROP_N := 100 # most tiles per side of the tree and house patch
const PROP_SPAN := 1.7 # prop patch side in view widths (the trees beyond are specks)
const PROP_LOW_KM := 10.0 # from this view width: low-poly props without shadows
const PROP_SLOTS := [9, 9, 0, 0, 0, 0] # tree slots per tile and level
const HOUSE_SLOTS := [4, 9, 0, 0, 0, 0] # house blocks per town tile and level
# Kit 2 scale (docs/kit2/SCALE.md): lengths 1:23.8 against the real world, but
# houses and trees keep their real size. World units are real km, so a diorama
# metre is DIORAMA_KM_PER_M world units.
const DIORAMA_LAENGE := 1.0 / 23.80
const DIORAMA_KM_PER_M := 0.001 / DIORAMA_LAENGE
const HOUSE_M := 10.0 # house length (house mesh is 1 unit long)
const TREE_M := 12.0  # tree height (tree meshes are about 1.1 units tall)
const PROP_KINDS := ["broadleaf", "conifer", "cypress", "house", "pine"]

var manifest: Dictionary
var world_min := Vector2.ZERO
var world_size := Vector2.ONE
var grid_size := Vector2i.ZERO
var level := 2
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
var _terrain_material: ShaderMaterial
var _corner_material: ShaderMaterial # 2D pass: corner levels of the patch tiles
var _corner_view: SubViewport
var _place_material: ShaderMaterial # 2D pass: where each tree and house slot stands
var _place_view: SubViewport
var _prop_materials: Array[ShaderMaterial] = []
var _terrain: MultiMeshInstance3D
var _props: Array[MultiMeshInstance3D] = []

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
	for kind in PROP_KINDS.size():
		var material := ShaderMaterial.new()
		material.shader = PROPS_SHADER
		material.set_shader_parameter("prop_kind", kind)
		_prop_materials.append(material)
	for material in _all_materials():
		for key in shared:
			material.set_shader_parameter(key, shared[key])
	_build_nodes()
	_apply_level(level)
	return true

func _all_materials() -> Array[ShaderMaterial]:
	var list: Array[ShaderMaterial] = [_terrain_material, _corner_material, _place_material]
	list.append_array(_prop_materials)
	return list

func _build_nodes() -> void:
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

## Hide the tree kinds that cannot grow anywhere in the prop patch (the shader
## rule: conifers above 700 m or north of 50°, stone pines and cypresses below
## 700 m south of 44.5°), so their slots cost no vertex work.
var _culled_origin := Vector2i(-1, -1)
func _cull_prop_kinds() -> void:
	if prop_origin == _culled_origin or PROP_SLOTS[level] == 0:
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

## Level for a visible ground width (km): about 50 tiles across up close,
## about 250 across the whole Mediterranean.
static func level_for_width(width: float) -> int:
	var across := 50.0 * pow(maxf(width, 1.0) / 25.0, 0.317)
	var tile := width / across
	return clampi(int(round(log(tile / 0.5) / log(2.0))), 0, LEVELS.size() - 1)

func _apply_level(value: int) -> void:
	level = value
	tile_km = LEVELS[level]
	m_per_level = relief_slope * tile_km
	level_h = tile_km * LEVEL_HEIGHT
	var params := {
		"cells_tex": _cell_textures[level],
		"cells_size": _cell_sizes[level],
		"tile_km": tile_km,
		"level_h": level_h,
		"m_per_level": m_per_level,
		"height_lod": maxf(0.0, log(tile_km / 2.0) / log(2.0)),
	}
	for material in _all_materials():
		for key in params:
			material.set_shader_parameter(key, params[key])
	var slots: int = PROP_SLOTS[level]
	var house_slots: int = HOUSE_SLOTS[level]
	# the slot pass only runs while props are drawn
	_place_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if slots + house_slots > 0 else SubViewport.UPDATE_DISABLED
	_terrain_material.set_shader_parameter("house_grid", int(ceil(sqrt(float(maxi(house_slots, 1))))))
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
		var size_m := HOUSE_M if house else TREE_M / 1.1
		material.set_shader_parameter("prop_scale", size_m * DIORAMA_KM_PER_M)

## Direction towards the sun (world), for the stylised slope shading.
func set_light_dir(dir: Vector3) -> void:
	_terrain_material.set_shader_parameter("light_dir", dir.normalized())

## Move the patches: `focus` is the ground point the camera looks at, `centre`
## the middle of the visible ground (further back in oblique views).
func update_view(focus: Vector2, centre: Vector2, width: float) -> void:
	var wanted := level_for_width(width)
	if wanted != level:
		_apply_level(wanted)
	# SimCity 2000 tiles up close, EU5-style smooth relief map from far away
	# TT_SMOOTH=1: smooth relief at every zoom (look comparison)
	var smooth_relief := 1.0 if OS.get_environment("TT_SMOOTH") == "1" else smoothstep(SMOOTH_FROM_KM, SMOOTH_TO_KM, width)
	for material in _all_materials():
		material.set_shader_parameter("relief_smooth", smooth_relief)
	var c := ((centre - world_min) / tile_km).floor()
	patch_origin = Vector2i(int(c.x) - PATCH_N / 2, int(c.y) - PATCH_N / 2)
	_terrain_material.set_shader_parameter("patch_origin", patch_origin)
	var corner_origin := patch_origin - Vector2i.ONE
	for material in _all_materials():
		material.set_shader_parameter("corner_origin", corner_origin)
	# props only around the visible ground: every slot costs vertex work
	var wanted_n := clampi(int(ceil(PROP_SPAN * width / tile_km / 8.0)) * 8 + 4, 12, PROP_N)
	if wanted_n != prop_n:
		prop_n = wanted_n
		_apply_level(level)
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
	_cull_prop_kinds()

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
	var t := ((p - world_min) / tile_km).floor()
	var size := _cell_sizes[level]
	if t.x < 0 or t.y < 0 or t.x >= size.x or t.y >= size.y: return 1
	var b := int(_cell_images[level].get_pixel(int(t.x) >> 1, int(t.y)).r * 255.0 + 0.5)
	var cell := (b & 15) if (int(t.x) & 1) == 0 else (b >> 4)
	return cell & 3

## Smooth display height of the ground (world y) at p, for the camera focus.
func ground_y(p: Vector2) -> float:
	if water_at(p) == 1: return 0.0
	return maxf(1.0, maxf(relief_m(p), 0.0) / m_per_level) * level_h

## Highest display height in a rectangle (coarse sampling), for the weather.
func max_y(rect: Rect2) -> float:
	var top := 0.0
	for j in 9:
		for i in 9:
			var p := rect.position + rect.size * Vector2(i / 8.0, j / 8.0)
			top = maxf(top, ground_y(p))
	return top + level_h
