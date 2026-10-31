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
const COAST_STEPS_SHADER = preload("res://shaders/tile_coast_steps.gdshader")
const PropMeshes = preload("res://scripts/tile_prop_meshes.gd")
const RomanBuildings = preload("res://scripts/voxel/roman_buildings.gd")
const LANDMARK_SHADER = preload("res://shaders/tile_landmark.gdshader")
const CityPlans = preload("res://scripts/city_plans.gd")
const RomanCity = preload("res://scripts/voxel/roman_city.gd")

# Zoom levels by tile size. SimCity 2000 tiles at every zoom, up to the whole
# Kit 1 map (32 km tiles: about 150 across it). Up close a height level is relief_slope (m/km, from the bake) times
# the tile size, so a ramp rises one level per tile at most, as in SimCity
# 2000; the far levels read their corner levels from the bake (levels-L*.png,
# with their own metres per level, so ranges keep several steps on the world
# map). A level is LEVEL_HEIGHT of the tile on screen, the SimCity 2000 ratio
# (12 px per level on a 32 x 16 px tile); far out a step grows taller
# (LEVEL_HEIGHTS), so the stacked plateaus of the ranges still stand out when a
# tile is a few pixels wide.
const LEVELS := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]
const LEVEL_HEIGHT := 0.6
const LEVEL_HEIGHTS := [0.6, 0.6, 0.6, 0.9, 1.2, 1.5, 1.5]
const PATCH_N := 320 # tiles per side of the terrain patch (most drawn, and the corner cache)
const DRAW_MIN := 32 # fewest tiles per side drawn
const PROP_N := 100 # most tiles per side of the tree and house patch
const PROP_SPAN := 1.7 # prop patch side in view widths (the trees beyond are specks)
const PROP_LOW_KM := 10.0 # from this view width: low-poly props without shadows
const PROP_DETAIL_KM := 5.0 # up to this view width: the lots and landmarks in full detail
# tree slots per tile and level: on the 1 km tiles (35 to 90 km views) the
# woods stay single trees, grown TREE_FAR_GROW times so they read as trees
# and not a speckle over the relief (Ramon 30.10.2026, round c: Urbek's
# furthest shot keeps its woods as small trees densely packed)
const PROP_SLOTS := [9, 9, 0, 0, 0, 0, 0]
const TREE_FAR_GROW := 1.8
const CLOSE_LEVEL := 0 # the last level of the close LOD: people, crops, lots (people_dots.gd)
const HOUSE_SLOTS := [4, 9, 9, 9, 0, 0, 0] # house blocks per town tile and level
# Closest zoom (zoom -1): quarter tiles of the 0.5 km data tiles, one house
# (diorama size) per tile as in Urbek. Their cells and landscapes are their
# data tile's, their corners those of the data tiles and, between them, the
# higher one (tt_sub_corner), so the data ramps turn into terraces: a flat
# quarter on the upper step and a quarter ramp below it.
const SUB_KM := 0.25
# a level as high as on the 0.5 km tiles (the hills keep their height when
# the zoom changes; the quarter ramps are twice as steep)
const SUB_LEVEL_HEIGHT := 1.2
# Up close the steps are drawn lower: a level of 0.3 km stood above the 0.24
# km of a house lot, so the terrace walls were twice as tall as the houses on
# them. Below RELIEF_FLAT_TO km view width the levels shrink to RELIEF_FLAT of
# their height at RELIEF_FLAT_FROM; the quarter and the 0.5 km tiles share 0.3
# km a level, so the switch between them (at about 12 km) does not jump.
const RELIEF_FLAT := 0.4
const RELIEF_FLAT_FROM := 4.0
const RELIEF_FLAT_TO := 16.0
const SUB_TREE_SLOTS := 4
const SUB_HOUSE_SLOTS := 1
const SUB_WINDOW := 1024 # quarter tiles per side of sub_tex
const NO_WINDOW := Vector2i(-1048576, 0)
# Steps of the shore up close (coast_steps.gdshaderinc): columns per data
# tile side (CS_CELLS), the data tiles scanned at once, and the most sides
# drawn (a 100 x 100 window round Venice holds about 520)
const COAST_CELLS := 16
const COAST_BLOCK := 32
const COAST_MAX := 2048
# Far out (2 and 4 km tiles) the houses grow with the tiles, as buildings do
# when SimCity 2000 zooms out: towns stay a mosaic of roofs instead of
# coloured squares. Beyond that towns are roof coloured tiles.
const HOUSE_GROW_FROM_KM := 1.0
# Kit 2 scale (docs/kit2/SCALE.md): lengths 1:23.8 against the real world, but
# houses and trees keep their real size. World units are real km, so a diorama
# metre is DIORAMA_KM_PER_M world units.
const DIORAMA_LAENGE := 1.0 / 23.80
const DIORAMA_KM_PER_M := 0.001 / DIORAMA_LAENGE
const HOUSE_M := 10.0 # a house lot (voxel/roman_buildings.gd), before the diorama scale
const TREE_M := 8.0  # tree height (tree meshes are about 1.1 units tall; Urbek: 5-8 m, a house 6-12 m)
## A grid of half floats (metres) as an image with mipmaps, and as floats
## for the lookups on the CPU. On a worker thread.
static func _half_floats(path: String, size: Vector2i) -> Array:
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RH, FileAccess.get_file_as_bytes(path))
	var floats: Image = image.duplicate()
	floats.convert(Image.FORMAT_RF)
	var values := floats.get_data().to_float32_array()
	image.generate_mipmaps()
	return [image, values]

## A PNG, converted to `format` (-1 keeps it) and with mipmaps if asked. On
## a worker thread.
static func _png(path: String, format: int, mipmaps: bool) -> Image:
	var image := Image.load_from_file(path)
	if format >= 0:
		image.convert(format)
	if mipmaps:
		image.generate_mipmaps()
	return image

## Prop kinds: the trees of every kind in one MultiMesh (tile_prop_meshes.gd
## tree_template), then the houses.
const PROP_KINDS := ["trees", "house"]
const HOUSE_KIND := 1
# The houses are the Roman town's lot models (voxel/roman_buildings.gd, from
# the Colosseum prototype: Urbek's 40 voxels to a 10 m lot), at the diorama
# scale a lot to a quarter tile. One MultiMesh per model; each draws every
# LOT_KINDS.size()-th house slot (tile_props.gdshader lot_variant), so the
# models together cost what one house mesh did. Up to PROP_DETAIL_KM the full
# models (level 0, 0.25 m voxels, about 5000 triangles a lot: the 1 m voxels
# of level 1 read as mushrooms at 3 km), then level 1 (a few hundred
# triangles), from PROP_LOW_KM level 2.
const LOT_KINDS := [
	["house", 0], ["house", 2], ["house", 4], ["house", 6], ["house", 8], ["house", 10], ["house", 12],
	["house", 14], ["house", 16], ["house", 18], ["house", 20], ["house", 22], ["house", 24], ["house", 26],
	["garden", 0], ["garden", 2],
	# the city plans' lots (_plan_lot): squares and a market, tombs, the
	# wall's pieces and gates, the public buildings (voxel/roman_city.gd)
	["plaza", 0], ["plaza", 4], ["plaza", 5], ["plaza", 7], ["tombs", 0], ["tombs", 3],
	["plan_wall", 0], ["plan_wall", 1], ["plan_wall", 2], ["plan_gate", 0], ["plan_gate", 1], ["plan_temple", 0], ["plan_temple", 1],
	["plan_theatre", 0], ["plan_amphitheatre", 0], ["plan_baths", 0], ["plan_basilica", 0],
	["plan_basilica", 1], ["plan_basilica", 2], ["plan_horrea", 0], ["plan_circus", 0], ["plan_circus", 1],
	["plan_forum", 0], ["plan_forum", 1],
	# the houses along the plans' streets (_plan_street)
	["street_row", 0], ["street_row", 1], ["street_row", 2], ["street_row", 3], ["street_row", 4], ["street_row", 5], ["street_row", 6], ["street_row", 7],
	["street_corner_w", 0], ["street_corner_w", 1], ["street_corner_w", 2], ["street_corner_w", 3], ["street_corner_w", 4], ["street_corner_w", 5],
	["street_corner_e", 0], ["street_corner_e", 1], ["street_corner_e", 2], ["street_corner_e", 3], ["street_corner_e", 4], ["street_corner_e", 5],
	["street_court", 0], ["street_court", 1],
]
const TOWN_LOTS := 16 # the first LOT_KINDS: the old town rule's (_pick_lot)
const PLAN_LOT_CAP := 2048 # instances of a plan lot model (a patch of Rome holds a few hundred lots)
# A plan's public building (city_plans.gd info.models) -> its lot archetype
const PLAN_MODEL_LOTS := {
	"amphitheatre": "plan_amphitheatre", "forum": "plan_forum", "baths": "plan_baths",
	"temple": "plan_temple", "circus": "plan_circus", "theatre": "plan_theatre", "public": "plan_basilica",
	"market": "plaza", "palace": "plan_basilica", "fort": "plan_basilica", "warehouse": "plan_horrea",
	"harbour": "plan_horrea", "tomb": "tombs", "stadium": "plan_circus", "portico": "plan_forum",
	"agora": "plan_forum", "spoil": "garden",
}
# Buildings over several parcels (_plan_building_lots): these go on parcel
# by parcel, their pieces join (a circus's track, a forum's porticoes).
const PLAN_RUN_ON := ["circus", "stadium", "forum", "portico", "agora", "market", "warehouse", "harbour"]
# A lot's block in its turns (turns + 8 * block; tile_props.gdshader): one
# model from the north-west parcel over two parcels east (drawn longer that
# way), two south, or four (twice the size).
const PLAN_BLOCK_2X1 := 1
const PLAN_BLOCK_1X2 := 2
const PLAN_BLOCK_2X2 := 3
# Height of a house by its storeys in the plan (metres, the lot models'
# own: 6.5 to 16 m); one facing north or east, its street behind it as the
# camera sees it, keeps to two storeys so the street stays in view.
const PLAN_STOREY_M := [6.5, 6.5, 9.0, 12.0, 14.5, 16.0]
const PLAN_LOW_M := 9.0
# Rome's landmarks stand on their buildings in the plan, fitted into its
# parcels (the plan already draws them up to 2.5 times their real size:
# docs/kit2/CITY_PLANS.md). At 1.5 times the block they cleared the temples,
# fora and the Ludus round them off the plan (Mac r1); filling it they touched
# the houses beside it (Mac r2), so a strip of the block stays free round
# them. Before the plans they stood on blocks of 0.5 km tiles at three times
# the city.
const LANDMARK_PLAN_REACH := 0.9
# Plan kinds beside a street that its houses stand against (houses, public
# buildings, gardens, streets); not squares, walls, tombs or open land.
const PLAN_STREET_TOWN := [1, 2, 3, 4, 6, 7]
const LOT_SHARE := 0.92 # of the slot a lot fills; the rest is street
# Rome's great buildings on blocks of city tiles, drawn while the houses are
# (the two nearest levels). The Colosseum, the Forum (with the Capitolium),
# the baths, the Pantheon and the Circus Maximus are the Roman town's models
# ("kit:", voxel/roman_buildings.gd) at the houses' diorama scale, so their
# voxels match the lots: the Colosseum is eight lots long, about 1.8 km. That
# is three times the real city, so the blocks keep the order of the real one
# but not its distances: the Forum west of the Colosseum, the baths on the
# hill north of it, the Circus Maximus to the south, the Pantheon in the
# Campus Martius by the river. Other shapes (the bridges, tile_prop_meshes.gd)
# stand at LANDMARK_KM_PER_M (6 times their real size) and a half higher
# again (LANDMARK_RISE). Each block is snapped to the 0.5 km tiles around its
# place.
const LANDMARK_KM_PER_M := 0.006
const LANDMARK_RISE := 1.5
const LANDMARK_TILE_KM := 0.5
const LANDMARKS := [
	# mesh, block centre (lon, lat), block size in tiles, free ground around
	# the building (km)
	["kit:colosseum", Vector2(12.5065, 41.8894), Vector2i(4, 4), 0.05],
	["kit:forum", Vector2(12.4854, 41.8917), Vector2i(3, 3), 0.05],
	["kit:baths", Vector2(12.5065, 41.9010), Vector2i(2, 1), 0.05],
	["kit:pantheon", Vector2(12.4810, 41.9060), Vector2i(2, 2), 0.05],
	["kit:circus", Vector2(12.4870, 41.8745), Vector2i(4, 2), 0.05],
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
var _level_h_full := 0.6 # level_h before relief_for_width
var _view_width := 25.0
var patch_origin := Vector2i.ZERO
var draw_n := PATCH_N # tiles per side drawn, around the middle of the patch
var prop_origin := Vector2i.ZERO
var prop_n := PROP_N
## The tallest prop drawn now (km, trees grown, lots on their plinths), for
## how far beyond the visible ground the prop patch must reach (landscape.gd).
var prop_height_km := 0.0
var _props_tier := 1 # 0 full detail, 1 light, 2 low (PROP_DETAIL_KM, PROP_LOW_KM)
var _meshes_detail: Array = []
var _meshes_full: Array = []
var _meshes_low: Array = []

var relief_slope := 80.0
var _heights: PackedFloat32Array
var _relief: PackedFloat32Array
var _cell_images: Array[Image] = []
var _cell_sizes: Array[Vector2i] = []
var _cell_textures: Array[ImageTexture] = []
# town tiles per level, (j * width + i) * 4 + town class, sorted (towns-L*.i32)
var _town_lists := {}
var _landmark_parcels := {} # Rome's landmark blocks' parcels (_before_landmark)
# the prop patch's town tiles (local index), then each lot model's slots on
# them (local index * 512 + block * 128 + turns * 16 + slot), _update_town_list
var _town_image: Image
const TOWN_TEX := Vector2i(256, 128)
var _town_texture: ImageTexture
var _town_key := Vector4i(-1, 0, 0, 0)
## Cumulative pick weights of the lot models per town class (0 none, 1
## village, 2 town, 3 city core): _lot_weights, from the models' heights.
var _lot_pick: Array[PackedFloat32Array] = []
var town_count := 0
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
var _coast_material: ShaderMaterial # the steps of the shore
var _coast: MultiMeshInstance3D
var _coast_blocks := {} # COAST_BLOCK square of data tiles -> its open shore sides (_coast_block)
var _coast_key := Vector4i(0, 0, 0, -9) # the data tiles listed (_update_coast_list)
var _place_view: SubViewport
var _prop_materials: Array[ShaderMaterial] = []
var _terrain: MultiMeshInstance3D
var _props: Array[MultiMeshInstance3D] = []
var _landmarks: Array[MeshInstance3D] = []
var _landmark_levels := PackedFloat32Array() # _place_landmarks
var _landmark_names: Array[String] = [] # LANDMARKS mesh of each in _landmarks
var plans: CityPlans # the city plans (docs/kit2/CITY_PLANS.md), null without them
var _plan_lots := {} # parcel -> _plan_lots_of
var _plan_house_lots := {} # metres -> house lots nearest that height (_lot_weights)
## What changed in this frame's update_view (level, props, tier, windows), for
## the tour benchmark (landscape.gd --tour); whoever reads it clears it.
var events := PackedStringArray()

static func data_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()

## Loads the terrain data. A coroutine (await it): the images are decoded
## on worker threads, all at once (PNG and the half floats were most of the
## start, about 12 s one after another), while the frames go on for the
## loading screen; `progress` gets the share decoded (0..1).
func load_data(progress := Callable()) -> bool:
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
	var size := grid_size
	var jobs: Array[Callable] = [
		func() -> Variant: return _half_floats(dir.path_join(manifest.height_half.path), size),
		func() -> Variant: return _half_floats(dir.path_join(manifest.relief_half.path), size),
		func() -> Variant: return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RH, FileAccess.get_file_as_bytes(dir.path_join(manifest.shore_half.path))) if manifest.has("shore_half") else null,
		func() -> Variant: return _png(dir.path_join(manifest.cover.path), -1, true),
		func() -> Variant: return _png(dir.path_join(manifest.aux.path), -1, false),
	]
	var plan_job := jobs.size()
	var plan_size := world_size
	jobs.append(func() -> Variant:
		var p := CityPlans.new()
		if not p.read(data_root(), 1.0, plan_size):
			return null
		p.scan()
		return p)
	var lists := ["cells", "levels", "ground"]
	for list in lists:
		for entry in manifest.get(list, []):
			var path := dir.path_join(entry.path)
			jobs.append(func() -> Variant: return _png(path, Image.FORMAT_R8, false))
	var done: Array = []
	done.resize(jobs.size())
	var lock := Mutex.new()
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void:
		var result: Variant = jobs[i].call()
		lock.lock()
		done[i] = result
		lock.unlock(), jobs.size(), -1, true, "terrain data")
	while not WorkerThreadPool.is_group_task_completed(task):
		if progress.is_valid():
			progress.call(float(WorkerThreadPool.get_group_processed_element_count(task)) / jobs.size())
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(task)
	var height_image: Image = done[0][0]
	_heights = done[0][1]
	relief_slope = float(manifest.relief_half.slope_m_per_km)
	var relief_image: Image = done[1][0]
	_relief = done[1][1]
	var shore_texture: ImageTexture = ImageTexture.create_from_image(done[2]) if done[2] != null else null
	var cover: Image = done[3]
	var aux: Image = done[4]
	plans = done[plan_job]
	if plans != null:
		plans.make_textures()
	var next := plan_job + 1
	for entry in manifest.cells:
		var image: Image = done[next]
		next += 1
		var town_list := PackedInt32Array()
		if entry.has("towns"):
			town_list = FileAccess.get_file_as_bytes(dir.path_join(entry.towns.path)).to_int32_array()
		if plans != null and int(entry.level) == 0:
			town_list = _apply_plans(image, int(entry.width), town_list)
		_cell_images.append(image)
		_cell_sizes.append(Vector2i(int(entry.width), int(entry.height)))
		_cell_textures.append(ImageTexture.create_from_image(image))
		if entry.has("towns"):
			_town_lists[int(entry.level)] = town_list
	for entry in manifest.get("levels", []):
		var image: Image = done[next]
		next += 1
		var key := int(entry.level)
		_level_images[key] = image
		if entry.get("scale", "far") == "near":
			_near_levels[key] = true
		else:
			_level_textures[key] = ImageTexture.create_from_image(image)
	for entry in manifest.get("ground", []):
		var image: Image = done[next]
		next += 1
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
	_coast_material = ShaderMaterial.new()
	_coast_material.shader = COAST_STEPS_SHADER
	for kind in _prop_count():
		var material := ShaderMaterial.new()
		material.shader = PROPS_SHADER
		material.set_shader_parameter("prop_kind", 3 if _lot_of(kind) >= 0 else 5 if kind == _plinth_kind() else kind)
		material.set_shader_parameter("lot_variant", _lot_of(kind))
		material.set_shader_parameter("lot_variants", TOWN_LOTS)
		_prop_materials.append(material)
	if plans != null:
		shared.merge(plans.uniforms())
		shared["city_plans_on"] = true
	for material in _all_materials():
		for key in shared:
			material.set_shader_parameter(key, shared[key])
	for key in shared:
		_sub_material.set_shader_parameter(key, shared[key])
	_build_nodes()
	_apply_level(zoom)
	return true

## Prop kinds: PROP_KINDS, with the house replaced by the first lot model,
## the other lot models after them and last the terraces under lots on ramps.
func _prop_count() -> int:
	return PROP_KINDS.size() + LOT_KINDS.size()

func _plinth_kind() -> int:
	return PROP_KINDS.size() + LOT_KINDS.size() - 1

## Kinds on the house slots: the lot models and the terraces.
func _is_house(kind: int) -> bool:
	return _lot_of(kind) >= 0 or kind == _plinth_kind()

## The lot model (LOT_KINDS) a prop kind draws, or -1 for the trees.
func _lot_of(kind: int) -> int:
	if kind == HOUSE_KIND:
		return 0
	return kind - PROP_KINDS.size() + 1 if kind >= PROP_KINDS.size() and kind < _plinth_kind() else -1

func _all_materials() -> Array[ShaderMaterial]:
	var list: Array[ShaderMaterial] = [_terrain_material, _corner_material, _place_material, _coast_material]
	list.append_array(_prop_materials)
	return list

func _build_nodes() -> void:
	# the Roman models baked at once (in parallel) instead of one by one below
	RomanBuildings.prepare(LOT_KINDS, LANDMARKS.filter(func(e: Array) -> bool: return String(e[0]).begins_with("kit:")).map(func(e: Array) -> String: return String(e[0]).trim_prefix("kit:")))
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
	_town_image = Image.create(TOWN_TEX.x, TOWN_TEX.y, false, Image.FORMAT_RF)
	_town_texture = ImageTexture.create_from_image(_town_image)
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
	# the tiles cast no shadows: the side tones carry the relief, as in
	# SimCity 2000. A steep quarter ramp turned from the sun shadowed itself
	# and split its tile into a lit strip and a near black triangle (Kritik
	# r16: #3b3741 on the rock, lavender on the snow); far out the coarse map
	# only drew streaks at the steps. Houses, trees and landmarks still do.
	_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_terrain)
	_terrain_material.set_shader_parameter("patch_n", PATCH_N)
	# the steps of the shore: one instance per listed side (_update_coast_list),
	# no shadows, as the tiles
	_coast = MultiMeshInstance3D.new()
	_coast.name = "CoastSteps"
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.use_custom_data = true
	cm.mesh = PropMeshes.coast_steps_template(COAST_CELLS)
	cm.instance_count = COAST_MAX
	cm.visible_instance_count = 0
	_coast.multimesh = cm
	_coast.material_override = _coast_material
	_coast.custom_aabb = huge
	_coast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_coast)
	_meshes_full = [PropMeshes.tree_template(), null]
	_meshes_low = [PropMeshes.tree_template(PropMeshes.TREE_BLOCKS - 1), null]
	_meshes_detail = _meshes_full.duplicate()
	for kind in _prop_count():
		var lot := _lot_of(kind)
		if kind == _plinth_kind():
			var plinth := PropMeshes.plinth()
			_meshes_detail.append(plinth)
			_meshes_full.append(plinth)
			_meshes_low.append(plinth)
		if lot < 0:
			continue
		var detail: ArrayMesh = RomanBuildings.lot_mesh(LOT_KINDS[lot][0], LOT_KINDS[lot][1], 0)
		var full: ArrayMesh = RomanBuildings.lot_mesh(LOT_KINDS[lot][0], LOT_KINDS[lot][1], 1)
		var low: ArrayMesh = RomanBuildings.lot_mesh(LOT_KINDS[lot][0], LOT_KINDS[lot][1], 2)
		_lot_heights[lot] = detail.get_aabb().size.y if detail else 10.0
		if kind < _meshes_full.size():
			_meshes_detail[kind] = detail
			_meshes_full[kind] = full
			_meshes_low[kind] = low
		else:
			_meshes_detail.append(detail)
			_meshes_full.append(full)
			_meshes_low.append(low)
	_lot_weights()
	var meshes := _meshes_full
	for kind in _prop_count():
		var lot := _lot_of(kind)
		var node := MultiMeshInstance3D.new()
		node.name = "TilePlinth" if kind == _plinth_kind() else "Tile" + (PROP_KINDS[kind].capitalize() if lot < 0 else "Lot%d" % lot)
		var pm := MultiMesh.new()
		pm.transform_format = MultiMesh.TRANSFORM_3D
		pm.mesh = meshes[kind]
		pm.instance_count = PLAN_LOT_CAP if lot >= TOWN_LOTS else PROP_N * PROP_N * 9 / (TOWN_LOTS if lot >= 0 else 1)
		if lot >= TOWN_LOTS:
			pm.visible_instance_count = 0 # only from the town list
		node.multimesh = pm
		node.material_override = _prop_materials[kind]
		_prop_materials[kind].set_shader_parameter("corner_tex", _corner_view.get_texture())
		_prop_materials[kind].set_shader_parameter("corner_size", _corner_view.size)
		_prop_materials[kind].set_shader_parameter("place_tex", _place_view.get_texture())
		_prop_materials[kind].set_shader_parameter("place_tree_w", PROP_N * 3)
		_prop_materials[kind].set_shader_parameter("place_ready", true)
		_prop_materials[kind].set_shader_parameter("town_tex", _town_texture)
		_prop_materials[kind].set_shader_parameter("town_w", TOWN_TEX.x)
		node.custom_aabb = huge
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		_props.append(node)
		_prop_materials[kind].set_shader_parameter("prop_n", PROP_N)
	_set_tree_table(_props_tier == 2)
	_build_landmarks()

## Same as landscape.gd lonlat_to_world.
static func _lonlat_world(ll: Vector2) -> Vector2:
	return Vector2(6371.0088 * cos(deg_to_rad(41.0)) * deg_to_rad(ll.x - 19.0), -6371.0088 * deg_to_rad(ll.y - 41.0))

func _build_landmarks() -> void:
	var material := ShaderMaterial.new()
	material.shader = LANDMARK_SHADER
	var rects := PackedVector4Array()
	var placed := _plan_landmarks()
	for entry in LANDMARKS:
		var size := Vector2(entry[2])
		var first := ((_lonlat_world(entry[1]) - world_min) / LANDMARK_TILE_KM - size * 0.5).round()
		var lo := world_min + first * LANDMARK_TILE_KM
		var hi := lo + size * LANDMARK_TILE_KM
		var kit := String(entry[0]).begins_with("kit:")
		var which := String(entry[0]).trim_prefix("kit:")
		if plans != null and not kit:
			continue # the plan's bridges are streets on their terraces
		var km_per_m := DIORAMA_KM_PER_M if kit else LANDMARK_KM_PER_M
		var node := MeshInstance3D.new()
		node.name = "Landmark" + which.capitalize()
		node.mesh = RomanBuildings.landmark_mesh(which, 0 if _props_tier < 2 else 1) if kit else PropMeshes.landmark(which)
		if kit:
			RomanBuildings.landmark_mesh(which, 1) # loaded now, not on the first zoom past PROP_LOW_KM
		var reach := node.mesh.get_aabb()
		var free: float = entry[3]
		if placed.has(which):
			# on its building in the plan, shrunk to fit it; its neighbours
			# in the plan stay
			var block: Rect2 = placed[which]
			lo = block.position
			hi = block.end
			var fit := minf(block.size.x / (reach.size.x * km_per_m), block.size.y / (reach.size.z * km_per_m))
			km_per_m *= minf(1.0, LANDMARK_PLAN_REACH * fit)
			free = 0.0
		node.material_override = material
		node.scale = Vector3(1.0, 1.0 if kit else LANDMARK_RISE, 1.0) * km_per_m
		var centre := (lo + hi) * 0.5
		node.position = Vector3(centre.x, 0.0, centre.y)
		add_child(node)
		_landmarks.append(node)
		_landmark_names.append(String(entry[0]))
		# no houses on the block, nor where the building reaches past it
		var a := centre + Vector2(reach.position.x, reach.position.z) * km_per_m
		var b := centre + Vector2(reach.end.x, reach.end.z) * km_per_m
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
	_landmark_levels = levels
	var count := _landmarks.size() if near else 0
	for material in _all_materials() + [_sub_material]:
		material.set_shader_parameter("landmark_levels", levels)
		material.set_shader_parameter("landmark_count", count)

## The blocks of every tree kind into the trees' material (the far ones
## with the low-poly template).
func _set_tree_table(low: bool) -> void:
	var table := PropMeshes.tree_table(low)
	for key in table:
		_prop_materials[0].set_shader_parameter(key, table[key])

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
## 12 km. Far out at least a level whose patch spans the top edge of the
## picture (1.1 view widths on the tilted map view).
static func level_for_width(width: float) -> int:
	var across := 50.0 * pow(maxf(width, 1.0) / 25.0, 0.317)
	var tile := width / across
	var wanted := int(round(log(tile / 0.5) / log(2.0) + 0.2))
	var spans := int(ceil(log(width * 1.15 / PATCH_N / 0.5) / log(2.0)))
	return clampi(maxi(wanted, spans), -1, LEVELS.size() - 1)

## How much of a level's height is drawn at a view `width` km wide
## (RELIEF_FLAT up close, all of it from RELIEF_FLAT_TO).
static func relief_for_width(width: float) -> float:
	var t := clampf(log(maxf(width, 0.01) / RELIEF_FLAT_FROM) / log(RELIEF_FLAT_TO / RELIEF_FLAT_FROM), 0.0, 1.0)
	return lerpf(RELIEF_FLAT, 1.0, t * t * (3.0 - 2.0 * t))

## A new step height while zooming (same level): the shaders, and the
## landmarks on their blocks.
func _set_level_h(h: float) -> void:
	level_h = h
	for material in _all_materials() + [_sub_material]:
		material.set_shader_parameter("level_h", h)
	if level <= 1:
		for k in mini(_landmarks.size(), _landmark_levels.size()):
			_landmarks[k].position.y = _landmark_levels[k] * h

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
	_level_h_full = tile_km * (SUB_LEVEL_HEIGHT if sub_tiles else LEVEL_HEIGHTS[level])
	level_h = _level_h_full * relief_for_width(_view_width)
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
	# the slot pass only runs while props are drawn
	_place_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if slots + house_slots > 0 else SubViewport.UPDATE_DISABLED
	_terrain_material.set_shader_parameter("house_grid", int(ceil(sqrt(float(maxi(house_slots, 1))))))
	_terrain_material.set_shader_parameter("town_props", house_slots > 0)
	_apply_prop_count()
	_place_landmarks()
	events.append("level %d" % value)

## Slots and instance counts of the prop patch. Only these change with
## prop_n, every few frames while zooming: the level's windows and passes
## stay (redoing them all on each change, a 1 MB window cut and the quarter
## tile pass, made zooming stutter).
func _apply_prop_count() -> void:
	var slots: int = SUB_TREE_SLOTS if sub_tiles else PROP_SLOTS[level]
	var house_slots: int = SUB_HOUSE_SLOTS if sub_tiles else HOUSE_SLOTS[level]
	prop_height_km = 0.0
	for kind in _props.size():
		var node := _props[kind]
		var house := _is_house(kind)
		var n: int = house_slots if house else slots
		node.visible = n > 0
		if not house:
			node.multimesh.visible_instance_count = prop_n * prop_n * maxi(n, 1)
		var material := _prop_materials[kind]
		material.set_shader_parameter("slots", maxi(n, 1))
		_place_material.set_shader_parameter("house_slots" if house else "tree_slots", n)
		# lot models are in metres, the tree meshes about 1.1 units tall
		var size_m := LOT_SHARE * maxf(1.0, tile_km / HOUSE_GROW_FROM_KM) if house else TREE_M / 1.1 * (TREE_FAR_GROW if tile_km >= 1.0 else 1.0)
		material.set_shader_parameter("prop_scale", size_m * DIORAMA_KM_PER_M)
		if n > 0:
			# trees grow to 1.25 times (tile_props.gdshader)
			var top: float = _meshes_detail[kind].get_aabb().end.y if house else PropMeshes.tree_height() * 1.25
			prop_height_km = maxf(prop_height_km, top * size_m * DIORAMA_KM_PER_M)
	_town_key = Vector4i(-1, 0, 0, 0) # the house counts: _update_town_list

## A skyline instead of one even roof line (Ramon 29.10.2026: every house the
## same height): the tall lot models (up to 16 m, four storeys) gather in the
## city cores, the low ones (6.5 to 9 m) in the villages, a town takes them
## as they come. Weight (height / mean)^SKYLINE_POWER per class; the gardens
## keep their even share everywhere.
const SKYLINE_POWER := [0.0, -3.0, 0.0, 3.0]
var _lot_heights := {}

func _lot_weights() -> void:
	var mean := 0.0
	var houses := 0
	for lot in LOT_KINDS.size():
		if LOT_KINDS[lot][0] == "house":
			mean += _lot_heights.get(lot, 10.0)
			houses += 1
	mean /= maxf(houses, 1)
	_lot_pick.clear()
	for town_class in 4:
		var sum := 0.0
		var cumulative := PackedFloat32Array()
		for lot in LOT_KINDS.size():
			var w := 1.0 if lot < TOWN_LOTS else 0.0
			if LOT_KINDS[lot][0] == "house":
				w = pow(_lot_heights.get(lot, mean) / mean, SKYLINE_POWER[town_class])
			sum += w
			cumulative.append(sum)
		for k in cumulative.size():
			cumulative[k] /= sum
		_lot_pick.append(cumulative)
	# the plan's houses: for each height the three house lots nearest it
	_plan_house_lots.clear()
	for m: float in PLAN_STOREY_M + [PLAN_LOW_M]:
		var near: Array = range(TOWN_LOTS).filter(func(lot: int) -> bool: return LOT_KINDS[lot][0] == "house")
		near.sort_custom(func(x: int, y: int) -> bool: return absf(_lot_heights.get(x, 10.0) - m) < absf(_lot_heights.get(y, 10.0) - m))
		_plan_house_lots[m] = near.slice(0, 3)

## The lot model of slot `slot` on quarter tile t of town class `town_class`.
func _pick_lot(t: Vector2i, slot: int, town_class: int) -> int:
	var r := float(absi(hash(Vector3i(t.x, t.y, slot * 7 + zoom))) % 100003) / 100003.0
	var cumulative: PackedFloat32Array = _lot_pick[clampi(town_class, 0, 3)] if _lot_pick.size() == 4 else PackedFloat32Array()
	if cumulative.is_empty():
		return absi(hash(Vector3i(t.x, t.y, slot * 7 + zoom))) % LOT_KINDS.size()
	return mini(cumulative.bsearch(r), LOT_KINDS.size() - 1)

## The town tiles of the prop patch (towns-L*.i32) into town_tex, so the
## house kinds draw instances for them only: a patch of 100 x 100 tiles at 1
## to 4 km holds a few dozen town tiles, and its 90 000 house slots ran the
## vertex shader of the lot models for nothing (18 fps from 70 to 700 km on
## an M3 Pro). Up close every quarter of a town tile; further out the tiles
## of town class 2 and up (tt_prop_place). Each slot's lot model comes from
## its place in the world, so a house keeps its model when the patch moves.
func _update_town_list() -> void:
	var house_slots: int = SUB_HOUSE_SLOTS if sub_tiles else HOUSE_SLOTS[level]
	var key := Vector4i(prop_origin.x, prop_origin.y, prop_n, zoom)
	if key == _town_key or house_slots == 0:
		return
	_town_key = key
	var list: PackedInt32Array = _town_lists.get(level, PackedInt32Array())
	var size: Vector2i = _cell_sizes[level]
	var q := 2 if sub_tiles else 1 # quarter tiles per data tile side
	var min_class := 1 if sub_tiles else 2
	var lo := Vector2i(floori(prop_origin.x / float(q)), floori(prop_origin.y / float(q))).max(Vector2i.ZERO)
	var hi := Vector2i(floori((prop_origin.x + prop_n - 1) / float(q)), floori((prop_origin.y + prop_n - 1) / float(q))).min(size - Vector2i.ONE)
	var tiles := PackedFloat32Array()
	var lots: Array[PackedFloat32Array] = []
	lots.resize(LOT_KINDS.size())
	var room := TOWN_TEX.x * TOWN_TEX.y / (house_slots + 1)
	for j in range(lo.y, hi.y + 1):
		var k := list.bsearch((j * size.x + lo.x) * 4)
		var end := list.bsearch((j * size.x + hi.x + 1) * 4)
		while k < end and tiles.size() < room:
			var v := list[k]
			k += 1
			if (v & 3) < min_class:
				continue
			var i := (v >> 2) - j * size.x
			for part in q * q:
				var at := Vector2i(i * q + part % q, j * q + part / q) - prop_origin
				if at.x >= 0 and at.y >= 0 and at.x < prop_n and at.y < prop_n:
					var local := at.y * prop_n + at.x
					tiles.append(local)
					var t := at + prop_origin
					for slot in house_slots:
						lots[_pick_lot(t, slot, v & 3)].append(local * 512 + slot)
	if plans != null and (sub_tiles or level == 0):
		_list_plan_lots(tiles, lots, room)
	town_count = tiles.size()
	var data := tiles.duplicate()
	var starts := PackedInt32Array()
	for lot in lots:
		starts.append(data.size())
		data.append_array(lot)
	data.resize(TOWN_TEX.x * TOWN_TEX.y)
	_town_image.set_data(TOWN_TEX.x, TOWN_TEX.y, false, Image.FORMAT_RF, data.to_byte_array())
	_town_texture.update(_town_image)
	for kind in _props.size():
		if not _is_house(kind):
			continue
		var lot := _lot_of(kind)
		var material := _prop_materials[kind]
		material.set_shader_parameter("town_count", town_count)
		if lot >= 0:
			material.set_shader_parameter("lot_start", starts[lot])
			material.set_shader_parameter("lot_count", lots[lot].size())
			_props[kind].multimesh.visible_instance_count = mini(lots[lot].size(), _props[kind].multimesh.instance_count)
		else:
			_props[kind].multimesh.visible_instance_count = town_count * house_slots
	events.append("towns")

# ------------------------------------------------------- steps of the shore

## Up close (0.5 km and quarter tiles) the sides of the sea tiles in front of
## open land and the coast cuts under the prop patch, one instance each, for
## the steps of the shore (coast_steps.gdshaderinc); the shaders get the
## same window, so the tiles lay their sand and surf where the steps stand.
## Further out none.
func _update_coast_list() -> void:
	var q := 2 if sub_tiles else 1 # quarter tiles per data tile side
	var lo := Vector2i(floori(prop_origin.x / float(q)), floori(prop_origin.y / float(q)))
	var hi := Vector2i(floori((prop_origin.x + prop_n - 1) / float(q)), floori((prop_origin.y + prop_n - 1) / float(q)))
	if zoom > 0:
		hi = lo - Vector2i.ONE
	var key := Vector4i(lo.x, lo.y, hi.x, hi.y)
	if key == _coast_key:
		return
	_coast_key = key
	for material in [_terrain_material, _coast_material]:
		material.set_shader_parameter("steps_lo", lo)
		material.set_shader_parameter("steps_hi", hi)
	var sides := PackedInt32Array()
	if zoom <= 0:
		for bj in range(lo.y / COAST_BLOCK, hi.y / COAST_BLOCK + 1):
			for bi in range(lo.x / COAST_BLOCK, hi.x / COAST_BLOCK + 1):
				var block := _coast_block(Vector2i(bi, bj))
				for k in range(0, block.size(), 3):
					if block[k] >= lo.x and block[k] <= hi.x and block[k + 1] >= lo.y and block[k + 1] <= hi.y:
						sides.append_array(block.slice(k, k + 3))
	var count := mini(sides.size() / 3, COAST_MAX)
	# per instance a transform (unused: the shader places the blocks) and
	# the custom data: data tile x, y, side (4 + tip on a cut)
	var buffer := PackedFloat32Array()
	buffer.resize(COAST_MAX * 16)
	for k in count:
		var o := k * 16
		buffer[o] = 1.0
		buffer[o + 5] = 1.0
		buffer[o + 10] = 1.0
		buffer[o + 12] = sides[k * 3]
		buffer[o + 13] = sides[k * 3 + 1]
		buffer[o + 14] = sides[k * 3 + 2]
	_coast.multimesh.buffer = buffer
	_coast.multimesh.visible_instance_count = count
	events.append("coast %d" % count)

## The shore sides with steps of a COAST_BLOCK square of data tiles (block
## b), as (x, y, side) of the sea tile: the sea tiles with open land or a
## town (its quay) across that side (cs_shore); and its coast cuts towards
## the sea as (x, y, 4 + the corner of the wet half) (cs_cut_tip). Scanned
## once and kept.
func _coast_block(b: Vector2i) -> PackedInt32Array:
	if _coast_blocks.has(b):
		return _coast_blocks[b]
	var image: Image = _cell_images[0]
	# the block and three tiles round it on whole bytes (two cells a byte)
	var rect := Rect2i(b.x * COAST_BLOCK / 2 - 2, b.y * COAST_BLOCK - 3, COAST_BLOCK / 2 + 4, COAST_BLOCK + 6)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var bytes := image.get_region(rect).get_data() if rect.has_area() else PackedByteArray()
	var cells := PackedByteArray()
	var w := (COAST_BLOCK + 8) # unpacked, from x0
	var h := COAST_BLOCK + 6
	var x0 := b.x * COAST_BLOCK - 4
	var y0 := b.y * COAST_BLOCK - 3
	cells.resize(w * h)
	cells.fill(1) # beyond the map: sea
	for j in rect.size.y:
		for i in rect.size.x:
			var v := bytes[j * rect.size.x + i]
			var at := (rect.position.y + j - y0) * w + (rect.position.x + i) * 2 - x0
			cells[at] = v & 15
			cells[at + 1] = v >> 4
	var sides := PackedInt32Array()
	for j in COAST_BLOCK:
		for i in COAST_BLOCK:
			var at := (j + 3) * w + i + 4
			if (cells[at] & 3) != 1:
				var tip := _coast_cut_tip(cells, at, w)
				if tip >= 0:
					sides.append_array([x0 + i + 4, y0 + j + 3, 4 + tip])
				continue
			for k in 4:
				var n := at + _coast_step(k, w)
				if _coast_shore(cells, n, w, cells[n] >= 8):
					sides.append_array([x0 + i + 4, y0 + j + 3, k])
	_coast_blocks[b] = sides
	return sides

## Offset of the neighbour across side k (N, E, S, W) in a row of `w` cells.
static func _coast_step(k: int, w: int) -> int:
	return [-w, 1, w, -1][k]

## cs_shore (coast_steps.gdshaderinc) on the unpacked cells: land, a town
## or not as `town` says, not a coast cut (towns never are), not a lone tile
## in the sea.
static func _coast_shore(cells: PackedByteArray, at: int, w: int, town: bool) -> bool:
	var cell := cells[at]
	if (cell & 3) != 0 or (cell >= 8) != town:
		return false
	var nb := PackedInt32Array([cells[at - w] & 3, cells[at + 1] & 3, cells[at + w] & 3, cells[at - 1] & 3])
	if nb[0] == 1 and nb[1] == 1 and nb[2] == 1 and nb[3] == 1:
		return false
	if town:
		return true
	for k in 4:
		var a := nb[k]
		var wet := (a == 1 or a == 2) and nb[(k + 1) & 3] == a
		var rest_dry := nb[(k + 2) & 3] != a and nb[(k + 3) & 3] != a
		if wet and rest_dry and (cells[at + _coast_step(k, w) + _coast_step((k + 1) & 3, w)] & 3) == a:
			return false
	return true

## cs_cut_tip (coast_steps.gdshaderinc) on the unpacked cells: the corner of
## the wet half of a coast cut towards the sea of open land, or -1.
static func _coast_cut_tip(cells: PackedByteArray, at: int, w: int) -> int:
	var cell := cells[at]
	if (cell & 3) != 0 or cell >= 8:
		return -1
	var nb := PackedInt32Array([cells[at - w] & 3, cells[at + 1] & 3, cells[at + w] & 3, cells[at - 1] & 3])
	for k in 4:
		var wet := nb[k] == 1 and nb[(k + 1) & 3] == 1
		var rest_dry := nb[(k + 2) & 3] != 1 and nb[(k + 3) & 3] != 1
		if wet and rest_dry and (cells[at + _coast_step(k, w) + _coast_step((k + 1) & 3, w)] & 3) == 1:
			return (k + 1) & 3
	return -1

# ------------------------------------------------------------ city plans

## The city plans on the 0.5 km data: the town class of every tile a plan
## covers into its cell (built up 3, else 0: the plan's open land is
## country) and those tiles out of the old town list (`towns`, sorted tile
## * 4 + class); returns the new list. The plan's lots come from
## _list_plan_lots.
func _apply_plans(image: Image, width: int, towns: PackedInt32Array) -> PackedInt32Array:
	for tile: Vector2i in plans.data_towns:
		var x := tile.x >> 1
		var b := roundi(image.get_pixel(x, tile.y).r * 255.0)
		var shift := 4 * (tile.x & 1)
		var cell := (b >> shift) & 15
		var town: int = plans.data_towns[tile]
		if cell >> 2 == town:
			continue
		b = (b & ~(15 << shift)) | (((cell & 3) | (town << 2)) << shift)
		image.set_pixel(x, tile.y, Color(b / 255.0, 0.0, 0.0))
	var kept := PackedInt32Array()
	for v in towns:
		var t := v >> 2
		if not plans.data_towns.has(Vector2i(t % width, t / width)):
			kept.append(v)
	return kept

## The plan's parcels in the prop patch into the town list: each tile once
## in `tiles` (its terrace), each lot as tile * 512 + turns * 16 + slot in
## `lots` of its model (turns 8 and up carry a building's block).
func _list_plan_lots(tiles: PackedFloat32Array, lots: Array[PackedFloat32Array], room: int) -> void:
	var q := 1 if sub_tiles else 2 # parcels a tile side
	var lo := prop_origin * q
	var hi := (prop_origin + Vector2i(prop_n, prop_n)) * q
	var pp: int = plans.page_parcels
	var listed := {}
	for pj in range(floori(lo.y / float(pp)), floori((hi.y - 1) / float(pp)) + 1):
		for pi in range(floori(lo.x / float(pp)), floori((hi.x - 1) / float(pp)) + 1):
			var list: PackedInt32Array = plans.built.get(Vector2i(pi, pj), PackedInt32Array())
			for k in range(0, list.size(), 3):
				var i := list[k]
				var j := list[k + 1]
				if i < lo.x or j < lo.y or i >= hi.x or j >= hi.y:
					continue
				var at := Vector2i(i / q, j / q) - prop_origin
				var local := at.y * prop_n + at.x
				if not listed.has(local):
					if tiles.size() >= room:
						return
					listed[local] = true
					tiles.append(local)
				for lot: Vector2i in _plan_lots_of(i, j, list[k + 2]):
					lots[lot.x].append(local * 512 + lot.y * 16 + (0 if sub_tiles else (i & 1) + 2 * (j & 1)))

## The lot models of plan parcel (i, j) with texel v (R | G << 8 | B << 16),
## each as Vector2i(LOT_KINDS index, turns that face it to its street): one,
## a wall's or a street's pieces, a building's share of its block, or none
## for bridges (their terraces).
## Turns 0..3 bring a model's side d to d + turns (0 N, 1 E, 2 S, 3 W);
## four more turn it an eighth further (tile_props.gdshader).
func _plan_lots_of(i: int, j: int, v: int) -> Array:
	var key := Vector2i(i, j)
	if not _plan_lots.has(key):
		var kind := v & 255
		match kind:
			8:
				_plan_lots[key] = _plan_wall(key, absi(hash(key)))
			7:
				_plan_lots[key] = _plan_street(key, (v >> 8) & 255)
			4:
				_plan_lots[key] = _plan_building_lots(key, v)
			10:
				_plan_lots[key] = []
			_:
				_plan_lots[key] = [_plan_lot(key, v)]
	return _plan_lots[key]

func _plan_lot(key: Vector2i, v: int) -> Vector2i:
	var kind := v & 255
	var street := (v >> 8) & 255
	var b := v >> 16
	var front := b >> 6
	var h := absi(hash(key))
	var facing := posmod(front - 2, 4) # a model's front is its south side
	var out := Vector2i(-1, 0)
	match kind:
		1, 2, 3:
			var m: float = PLAN_STOREY_M[clampi(b & 63, 0, PLAN_STOREY_M.size() - 1)]
			if front <= 1:
				m = minf(m, PLAN_LOW_M)
			if _before_landmark(key):
				m = PLAN_STOREY_M[0]
			var near: Array = _plan_house_lots.get(m, [0])
			out = Vector2i(near[h % near.size()], facing)
		5:
			# a square: its portico at the back unless the square goes on there
			var behind := _plan_kind(key - _side(front))
			out = Vector2i(_lot_index("plaza", [0, 4, 5][h % 3]) if behind == 5 else _lot_index("plan_forum", h % 2), facing)
		6:
			out = Vector2i(_lot_index("garden", [0, 2][h % 2]), facing)
		9:
			# the street through it north and south, or turned
			out = Vector2i(_lot_index("plan_gate", h % 2), 0 if (street >> 4) & 5 != 0 else 1)
		11:
			out = Vector2i(_lot_index("tombs", [0, 3][h % 2]), posmod(front - 1, 4)) # their road is east
	return out

## A public building's lots: its model on each of its parcels, except a
## building over two parcels draws its arena once across both (drawn longer)
## or its hall on the far parcel and its court (palaestra, peristyle garden,
## precinct) on the one nearer the camera (west or south), so the hall stays
## in view; over four parcels one model twice the size stands on their middle.
## Circuses, fora, markets and stores go on parcel by parcel, their pieces
## join. Lots carry the block in their turns (PLAN_BLOCK_*).
func _plan_building_lots(key: Vector2i, v: int) -> Array:
	var b := v >> 16
	var model := b & 63
	var facing := posmod((b >> 6) - 2, 4) # a model's front is its south side
	var h := absi(hash(key))
	var lot := _plan_building(key, model, facing, h)
	var name := _plan_model_name(model)
	var same := func(d: Vector2i) -> bool:
		var t := plans.texel(key + d)
		return t.x == 4 and t.z & 63 == model
	var e: bool = same.call(Vector2i(1, 0))
	var w: bool = same.call(Vector2i(-1, 0))
	var s: bool = same.call(Vector2i(0, 1))
	var n: bool = same.call(Vector2i(0, -1))
	if not (e or w or s or n) or name in PLAN_RUN_ON:
		return [lot]
	var first := not w and not n # the block's north-west parcel carries it
	if (e or w) and (n or s):
		return [Vector2i(lot.x, lot.y + 8 * PLAN_BLOCK_2X2)] if first else []
	var along_x := e or w
	if name == "amphitheatre" or name == "theatre":
		return [Vector2i(lot.x, lot.y + 8 * (PLAN_BLOCK_2X1 if along_x else PLAN_BLOCK_1X2))] if first else []
	if e if along_x else n:
		var court: Vector2i
		match name:
			"baths":
				court = Vector2i(_lot_index("plan_forum", h % 2), facing)
			"temple":
				court = Vector2i(_lot_index("plaza", 0), facing)
			_:
				court = Vector2i(_lot_index("garden", [0, 2][h % 2]), facing)
		return [court]
	return [lot]

func _plan_model_name(model: int) -> String:
	var models: Array = plans.info.get("models", [])
	return models[model] if model < models.size() else "public"

func _plan_building(key: Vector2i, model: int, facing: int, h: int) -> Vector2i:
	var name := _plan_model_name(model)
	var archetype: String = PLAN_MODEL_LOTS.get(name, "plan_basilica")
	if name == "market":
		return Vector2i(_lot_index("plaza", 7), facing)
	if archetype == "plan_circus":
		# the track along the building's length
		var along_x := _plan_kind(key + Vector2i(1, 0)) == 4 or _plan_kind(key - Vector2i(1, 0)) == 4
		return Vector2i(_lot_index(archetype, h % 2), 0 if along_x else 1)
	var variants: int = RomanBuildings.ARCHETYPES[archetype][0]
	var lot := _lot_index(archetype, h % variants)
	if lot < 0:
		lot = _lot_index(archetype, 0)
	if archetype == "tombs":
		return Vector2i(lot, posmod(facing + 1, 4))
	return Vector2i(lot, facing)

## A wall parcel's pieces (voxel/roman_city.gd wall): an arm to each
## neighbour on the wall or at a gate, straight or (where the wall steps
## diagonally) to the corner, and a tower where it turns or ends, now and
## then on a straight run.
func _plan_wall(key: Vector2i, h: int) -> Array:
	var on := func(d: Vector2i) -> bool:
		var k := _plan_kind(key + d)
		return k == 8 or k == 9
	var out := []
	var dirs: Array[int] = [] # the arms, 0..7 from north clockwise
	var sides := 0
	for d in 4:
		if on.call(_side(d)):
			sides |= 1 << d
			dirs.append(2 * d)
			out.append(Vector2i(_lot_index("plan_wall", 0), posmod(d - 1, 4))) # the arm runs east
	for c in 4:
		# the corner between sides c and c + 1, unless the wall goes round it
		var e := (c + 1) % 4
		if sides & ((1 << c) | (1 << e)) == 0 and on.call(_side(c) + _side(e)):
			dirs.append(2 * c + 1)
			# the long arm east, turned an eighth further to the south-east
			# (a voxel staircase read as a fence of white bars, Mac r1)
			out.append(Vector2i(_lot_index("plan_wall", 1), posmod(c - 1, 4) + 4))
	var straight := dirs.size() == 2 and absi(dirs[0] - dirs[1]) == 4
	if not straight or h % 3 == 0:
		out.append(Vector2i(_lot_index("plan_wall", 2), 0))
	return out

## A street parcel's houses (voxel/roman_city.gd street_*): a row house on
## each side the street does not run out at, where the town goes on beyond
## it; a corner house beside an arm where the town goes on behind it; a
## court in a corner between two rows. Nothing along a road out through the
## fields or the tombs, nor before a square or a wall, nor beside an arm
## that runs on to a gate. Houses that turn
## their backs to the camera (facing north or east) are one-storey shops,
## so the street stays in view; the others are as tall as the town's.
func _plan_street(key: Vector2i, street: int) -> Array:
	var links := street >> 4
	var out := []
	if links == 0:
		return out
	var urban: Array[bool] = []
	var to_gate: Array[bool] = [] # the arm runs on to a gate or the wall
	var tall := false
	for d in 4:
		var v := plans.texel(key + _side(d))
		urban.append(v.x in PLAN_STREET_TOWN)
		to_gate.append(v.x == 8 or v.x == 9)
		tall = tall or (v.x >= 1 and v.x <= 3 and (v.z & 63) >= 3)
	var low := _before_landmark(key)
	var pick := func(kind: String, bands: Array, front: int, k: int) -> int:
		var band := 2 if front < 2 or low else 0 if tall else 1
		var h := absi(hash(Vector3i(key.x, key.y, k)))
		return _lot_index(kind, bands[band] + h % (bands[band + 1] - bands[band]))
	for s in 4:
		if links & (1 << s) == 0 and urban[s]:
			# the row stands north facing south: turned to side s
			out.append(Vector2i(pick.call("street_row", RomanCity.ROW_BANDS, (s + 2) % 4, s), s))
	for c in 4:
		# corner c between sides a and b; its house faces arm a (then its
		# front is c + 3) or arm b (front c + 2), whichever the camera sees
		var a := c
		var b := (c + 1) % 4
		var arm_a := links & (1 << a) != 0
		var arm_b := links & (1 << b) != 0
		# (none at an arm to a gate: the street opens before it, Mac r1)
		var by_a := arm_a and urban[b] and not to_gate[a]
		var by_b := arm_b and urban[a] and not to_gate[b]
		if by_a and (not by_b or (c + 3) % 4 >= 2):
			out.append(Vector2i(pick.call("street_corner_w", RomanCity.CORNER_BANDS, (c + 3) % 4, 4 + c), b))
		elif by_b:
			out.append(Vector2i(pick.call("street_corner_e", RomanCity.CORNER_BANDS, (c + 2) % 4, 4 + c), c))
		elif not arm_a and not arm_b and urban[a] and urban[b]:
			out.append(Vector2i(_lot_index("street_court", absi(hash(key)) % RomanCity.COURT_VARIANTS), b))
	return out

func _plan_kind(parcel: Vector2i) -> int:
	return plans.texel(parcel).x

static func _side(d: int) -> Vector2i:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][d]

static func _lot_index(kind: String, variant: int) -> int:
	return LOT_KINDS.find([kind, variant])

## Whether a landmark's block lies just behind parcel `key` as the camera
## sees it (north, north-east or east): its houses keep to one storey there,
## or they hid the landmark's near side (the Circus Maximus's south stand
## behind the houses before it, Mac r3).
func _before_landmark(key: Vector2i) -> bool:
	if _landmark_parcels.is_empty() and plans != null:
		_landmark_parcels[Vector2i(-1, -1)] = true # looked
		for id: String in plans.info.cities:
			for building: Dictionary in plans.info.cities[id].get("buildings", []):
				if building.has("landmark") and id == "rome":
					var r: Array = building.parcels
					for j in int(r[3]):
						for i in int(r[2]):
							_landmark_parcels[Vector2i(int(r[0]) + i, int(r[1]) + j)] = true
	for d: Vector2i in [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)]:
		if _landmark_parcels.has(key + d):
			return true
	return false

## The plan's buildings that have a landmark model (Rome's), as world
## rectangles by the model's name.
func _plan_landmarks() -> Dictionary:
	var out := {}
	if plans == null:
		return out
	for id: String in plans.info.cities:
		for building: Dictionary in plans.info.cities[id].get("buildings", []):
			if building.has("landmark") and id == "rome":
				var r: Array = building.parcels
				out[building.landmark] = Rect2(world_min + Vector2(r[0], r[1]) * plans.parcel_km, Vector2(r[2], r[3]) * plans.parcel_km)
	return out

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
	events.append("level_window")
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
	events.append("sub_window")

## Direction towards the sun (world), for the stylised slope shading.
func set_light_dir(dir: Vector3) -> void:
	_terrain_material.set_shader_parameter("light_dir", dir.normalized())

## Move the patches around `centre`, the middle of the visible ground;
## `span` is the ground (km) the drawn tiles must cover around it.
## Draws the patch around `centre` for a view `width` km wide: the terrain
## `span` km across, the trees and houses `prop_span` km (at most PROP_SPAN
## view widths).
func update_view(centre: Vector2, width: float, span := INF, prop_span := INF) -> void:
	_view_width = width
	var wanted := level_for_width(width)
	if wanted != zoom:
		_apply_level(wanted)
	var h := _level_h_full * relief_for_width(width)
	if h != level_h:
		_set_level_h(h)
	var c := ((centre - world_min) / tile_km).floor()
	patch_origin = Vector2i(int(c.x) - PATCH_N / 2, int(c.y) - PATCH_N / 2)
	# only the tiles around the view are drawn: each costs vertex work (and
	# again for the shadow map), and up close the near-orthographic view
	# sees a few dozen tiles across of the 320 (100 000 tiles a frame)
	var n := clampi(int(ceil(span / tile_km / 8.0)) * 8 + 8, DRAW_MIN, PATCH_N) if is_finite(span) else PATCH_N
	if n != draw_n:
		draw_n = n
		_terrain.multimesh.visible_instance_count = n * n
		_terrain_material.set_shader_parameter("patch_n", n)
	_terrain_material.set_shader_parameter("patch_origin", Vector2i(int(c.x) - draw_n / 2, int(c.y) - draw_n / 2))
	if _near_levels.has(level) and _update_level_window():
		for material in _all_materials() + [_sub_material]:
			material.set_shader_parameter("levels_origin", Vector2i(_level_window_key.y, _level_window_key.z))
		_sub_origin = NO_WINDOW # the quarter data comes from the new window
	var corner_origin := patch_origin - Vector2i.ONE
	for material in _all_materials():
		material.set_shader_parameter("corner_origin", corner_origin)
	# props only around the visible ground (at most PROP_SPAN view widths):
	# every slot costs vertex work, the trees' for each kind; one tile more
	# each side, as the patch snaps to whole tiles
	var wanted_n := clampi(int(ceil(minf(PROP_SPAN * width, minf(span, prop_span)) / tile_km / 2.0)) * 2 + 2, 12, PROP_N)
	if wanted_n != prop_n:
		prop_n = wanted_n
		_apply_prop_count()
		events.append("props")
	# far out the trees are a few pixels tall: low-poly and no shadows; up
	# close the lots and landmarks in full detail
	var tier := 2 if width > PROP_LOW_KM else 0 if width <= PROP_DETAIL_KM else 1
	if tier != _props_tier:
		_props_tier = tier
		events.append("tier %d" % tier)
		for kind in _props.size():
			_props[kind].multimesh.mesh = [_meshes_detail, _meshes_full, _meshes_low][tier][kind]
			_props[kind].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tier == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_set_tree_table(tier == 2)
		for k in _landmarks.size():
			var which := _landmark_names[k]
			if which.begins_with("kit:"):
				_landmarks[k].mesh = RomanBuildings.landmark_mesh(which.trim_prefix("kit:"), 0 if tier < 2 else 1)
	var f := ((centre - world_min) / tile_km).floor()
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
	_update_town_list()
	_update_coast_list()
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
