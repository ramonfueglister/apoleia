extends MultiMeshInstance3D
## Every simulated person as a black dot (Kit 2 people prototype). Godot holds
## no game state: ApoleiaPeople (Rust GDExtension, sim/godot) runs the people
## on its own thread and hands over the changed pages of its view; this node
## uploads them into one texture array. A 2D pass (people_dots_prep.gdshader)
## works out where each person stands on the terrain, one float pixel per
## person, and runs only when the people or the terrain view changed; all
## people are then drawn with a single MultiMesh whose instances never move
## on the CPU (people_dots.gdshader), two texel fetches per dot.
##
## The dots belong to the close LOD: they show only at the zoom levels where
## the terrain draws trees and houses (TileTerrain.PROP_SLOTS > 0).
## Every village household also gets a house at its house spot, from the
## house table of the view (sim/src/view.rs Houses): a voxel farmhouse in the
## Urbek style in one of four builds (scripts/voxel/farmhouse.gd), the nearest houses
## (ApoleiaPeople.houses_near) in up to three levels of detail by distance and
## view width (people_houses.gdshader), with their own placement pass; city
## people live in the town tiles.
## Up close (view width up to FIGURE_KM) people are small figures at their
## real size (1.7 m at diorama scale, people_figures.gdshader) instead of
## dots; only the people near the view are drawn (ApoleiaPeople.near).
## Dots of people on the road (or on a ship) are dark red.
## C colours the dots by occupation, political group or estate (and back to
## black); a click on a dot shows that person and their household, Esc
## closes it.
## The grain economy (crate::grain, run beside the people) shows on the
## terrain: fields by season around the farms, footpaths to the markets,
## market squares, trade roads and sea lanes (sim_map.gdshaderinc, layers
## from ApoleiaPeople.map_window and road_map, rebuilt once a month).
## A click shows the household's kind, how much it ate and its money. T
## opens the simulation's tables (sim_tables.gd). Up close the trips to
## market and between markets walk the paths and roads (people_trips.gd).
## Keys: P shows or hides the dots (an overview, off by default), G the
## grain economy on the map (on by default), [ and ] slow down or speed up the days.
## Command line (after --): --people-days=n days per second (default 10),
## --people-bench=path.json writes frame timings with dots on and off
## (relative paths start at the repository root), --people-colour=n starts
## in colour mode n (MODES), --people-click=x,y clicks that pixel once,
## --people-dots starts with the dot overview on, --people-warm=n runs n
## days before the first frame (screenshots of a later year).

const SHADER = preload("res://shaders/people_dots.gdshader")
const SHADER_ROUND = preload("res://shaders/people_dots_round.gdshader")
const ROUND_FROM_PX := 1.75 # below this the dots stay triangles (no discard)
const PREP_SHADER = preload("res://shaders/people_dots_prep.gdshader")
const HOUSE_SHADER = preload("res://shaders/people_houses.gdshader")
const FIGURE_SHADER = preload("res://shaders/people_figures.gdshader")
const FIGURE_SHADOW_SHADER = preload("res://shaders/people_figure_shadows.gdshader")
const CROP_SHADER = preload("res://shaders/people_crops.gdshader")
const CROP_N := 40 # parcels per side of the square of crops around the camera
const CROP_ROWS := 8 # rows of crops or vines per parcel: clumps 8-10 px wide at 3 km, as Urbek's (r11: 12 rows read as dots)
const FENCE_POSTS := 6 # posts per side of a fenced field (people_crops.gdshader)
const FLOCK_MAX := 9 # sheep in the largest flock on a pasture parcel (a three by three grid, people_crops.gdshader)
const CROP_KM := 8.0 # view width up to which crops stand (sim_fields.gdshaderinc SIM_CROPS_KM)
const LOTS_SHADER = preload("res://shaders/people_lots.gdshader")
const LOT_KM := 0.5 # a village lot (people_dots_common.gdshaderinc DOT_LOT_KM)
const LOTS_N := 64 # lots per side of the house-lot mask around the camera
const FIGURE_KM := 10.0 # view width up to which people are figures, not dots
const FIGURE_M := 1.7 # figure height (the figure mesh is 1 unit tall)
const FIGURE_MAX := 16384 # most figures drawn at once (nearest first)
const LIST_W := 128 # width of the slot list texture
const Farmhouse = preload("res://scripts/voxel/farmhouse.gd")
const VoxelMesh = preload("res://scripts/voxel/voxel_mesh.gd")
const SimTables = preload("res://scripts/sim/sim_tables.gd")
const SimEvents = preload("res://scripts/sim/sim_events.gd")
const PeopleTrips = preload("res://scripts/sim/people_trips.gd")
const HOUSE_MAX := 16384 # most houses drawn at once (nearest first)
# Levels of detail of the farmhouse (Farmhouse.LOD_VOXELS): how many of the
# nearest houses each may take and up to which view width (km) it is used;
# the finest only to 2 km, beyond it its rows of roof tiles shimmer (moiré).
const HOUSE_LOD_MAX := [256, 1024, 4096, HOUSE_MAX]
const HOUSE_LOD_KM := [2.0, 5.0, 20.0, INF]
const TileTerrain = preload("res://scripts/tile_terrain.gd")
# terrain uniforms that move the dots; the placement pass reruns when they change
# the uniforms the placement passes depend on; the near relief (levels_*,
# near_scale) is baked later and, like the quarter tiles (sub_*), moves its
# window with the camera
const PLACE_KEYS: Array[StringName] = [&"tile_km", &"corner_origin", &"corner_size", &"m_per_level", &"height_lod", &"cells_size",
	&"level_h", &"levels_ready", &"levels_origin", &"near_scale", &"ground_ready", &"sub_tiles", &"sub_origin"]
const DOTS_PER_INSTANCE := 64 # people_dots.gdshaderinc, divides the page size
const PICK_PX := 10.0 # a click finds the nearest dot within this many pixels
const CLICK_PX := 4.0 # a press and release further apart is a drag, not a click
const MODES := ["schwarz", "Beruf", "politische Gruppe", "Stand"]
const STANDS := ["Landvolk", "Stadtvolk", "Ritter", "Senatoren"]
# colours by occupation (crate::groups JOBS order), political group, estate
const JOB_COLOURS := [Color(0.55, 0.2, 0.75), Color(0.95, 0.75, 0.1), Color(0.97, 0.97, 0.97), Color(0.75, 0.05, 0.05),
	Color(1.0, 0.5, 0.1), Color(0.2, 0.4, 0.95), Color(0.2, 0.85, 0.9), Color(0.5, 0.3, 0.15),
	Color(0.04, 0.04, 0.04), Color(0.3, 0.3, 0.3), Color(0.62, 0.62, 0.62), Color(1.0, 0.15, 0.15), Color(0.95, 0.3, 0.7)]
const GROUP_COLOURS := [Color(0.55, 0.2, 0.75), Color(0.95, 0.75, 0.1), Color(0.2, 0.85, 0.9), Color(1.0, 0.5, 0.1),
	Color(0.04, 0.04, 0.04), Color(1.0, 0.15, 0.15), Color(0.97, 0.97, 0.97), Color(0.35, 0.45, 0.65)]
const STAND_COLOURS := [Color(0.04, 0.04, 0.04), Color(1.0, 0.5, 0.1), Color(0.2, 0.4, 0.95), Color(0.75, 0.15, 0.85)]
const MAP_N := 256 # fine tiles (1.5625 km) in the grain window around the camera
const KIND_NOTES := {"Zelt": "lebt im Zelt (landlos)", "Lohn": "lebt von Lohnarbeit", "Händler": "Händlerhaushalt", "Oberschicht": "Oberschicht", "Hof": "Hof"}
const BENCH_WARMUP := 90
const BENCH_FRAMES := 240

var people: RefCounted
var terrain: Node3D
var days_per_second := 10.0
var shown := false # P key: the dots as an overview (map view), off by default
var colour_mode := 0 # C key, index into MODES
var selected := -1 # slot of the clicked person
var map_on := true # G key: the grain economy on the terrain
var _map_version := -1
var _map_at := Vector2.INF
var _map_tex: ImageTexture
var _road_tex: ImageTexture
var _region_tex: ImageTexture
var _waiting := false # asked the sim thread for the selected person
var _legend: Dictionary
var _hud: CanvasLayer
var _legend_label: RichTextLabel
var _info_label: RichTextLabel
var _press_at := Vector2.INF
var _click_at := Vector2.INF # --people-click, for screenshots
var _frames := 0
var _material := ShaderMaterial.new()
var _prep_material := ShaderMaterial.new()
var _prep_view: SubViewport
var _prep_rect: ColorRect
var _place_key := []
var _prep_frames := 0
var _houses: Array[MultiMeshInstance3D] = []
var _house_materials: Array[ShaderMaterial] = []
var _house_list_image := Image.create_empty(LIST_W, HOUSE_MAX / LIST_W, false, Image.FORMAT_RF)
var _house_list_tex: ImageTexture
var _house_list_at := Vector3.INF
var _house_prep_material := ShaderMaterial.new()
var _house_prep_view: SubViewport
var _house_prep_rect: ColorRect
var _house_texture: Texture2DArray
var _house_prep_frames := 0
var _figures: MultiMeshInstance3D
var _figure_material := ShaderMaterial.new()
var _figure_shadows: MultiMeshInstance3D # a strip of shade from each figure's feet (people_figure_shadows.gdshader)
var _figure_shadow_material := ShaderMaterial.new()
var _crops: MultiMeshInstance3D
var _trips: MultiMeshInstance3D # carriers and wagons on their way (people_trips.gd)
var _crop_material := ShaderMaterial.new()
var _lots_view: SubViewport # the lots that carry a house, so the crops leave them free
var _lots: MultiMeshInstance2D
var _lots_material := ShaderMaterial.new()
var _list_image := Image.create_empty(LIST_W, FIGURE_MAX / LIST_W, false, Image.FORMAT_RF)
var _list_tex: ImageTexture
var _list_at := Vector3.INF # centre x, z and radius of the current list
var prep_runs := 0
var _texture: Texture2DArray
var _shared_uniforms: Array[StringName] = []
var _shared_values := {} # what each shared uniform was last copied as
var _shared_count := 0 # materials it was copied into
var _day_debt := 0.0
var _bench_path := ""
var _bench_frame := 0
var _bench_last := 0
var _bench := {"on": [], "off": [], "on_gpu": [], "off_gpu": [], "sync_usec": [], "sync_layers": [], "prep": [], "process_on": [], "process_off": []}
var _bench_prep_last := 0

## Starts the people sim; false when the GDExtension is not built or the
## inputs are missing (then the caller frees this node).
func setup(tile_terrain: Node3D) -> bool:
	terrain = tile_terrain
	if not ClassDB.class_exists("ApoleiaPeople"):
		push_warning("ApoleiaPeople GDExtension not built (sim/godot/build.sh); people dots off")
		return false
	var warm := 0
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1) if "=" in arg else ""
		match key:
			"--people-days": days_per_second = float(value)
			"--people-bench": _bench_path = value if value.is_absolute_path() else TileTerrain.data_root().path_join(value)
			"--people-colour": colour_mode = clampi(int(value), 0, MODES.size() - 1)
			"--people-dots": shown = true
			"--people-warm": warm = int(value)
			"--people-click": _click_at = Vector2(float(value.get_slice(",", 0)), float(value.get_slice(",", 1)))
	people = ClassDB.instantiate("ApoleiaPeople")
	var started := Time.get_ticks_usec()
	if not people.load(TileTerrain.data_root(), 1):
		return false
	print(JSON.stringify({"event": "people_loaded", "people": people.count(), "ms": (Time.get_ticks_usec() - started) / 1000.0}))
	if warm > 0:
		people.advance(warm)
		while people.backlog() > 0 or people.day() < warm:
			OS.delay_msec(50)
		print(JSON.stringify({"event": "people_warm", "day": people.day(), "ms": (Time.get_ticks_usec() - started) / 1000.0}))
	name = "PeopleDots"
	_material.shader = SHADER
	_prep_material.shader = PREP_SHADER
	_prep_material.set_shader_parameter("dot_km_per_m", TileTerrain.DIORAMA_KM_PER_M) # the family in the farmyard
	_prep_rect = ColorRect.new()
	_prep_view = _make_prep("PeoplePlaces", _prep_rect, _prep_material)
	_house_prep_material.shader = PREP_SHADER
	_house_prep_material.set_shader_parameter("houses", true)
	_house_prep_rect = ColorRect.new()
	_house_prep_view = _make_prep("HousePlaces", _house_prep_rect, _house_prep_material)
	_house_list_tex = ImageTexture.create_from_image(_house_list_image)
	# one MultiMesh per build and level of detail, build-major; each draws
	# the houses of its level and leaves out the lots of the other builds
	for variant in Farmhouse.VARIANTS:
		var lods := Farmhouse.lods(TileTerrain.HOUSE_M, variant)
		for lod in lods.size():
			var m := ShaderMaterial.new()
			m.shader = HOUSE_SHADER
			m.set_shader_parameter("prop_scale", TileTerrain.HOUSE_M * TileTerrain.DIORAMA_KM_PER_M)
			m.set_shader_parameter("list_tex", _house_list_tex)
			m.set_shader_parameter("list_w", LIST_W)
			m.set_shader_parameter("variant", variant)
			_house_materials.append(m)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "PeopleHouses%d_%d" % [variant, lod]
			mmi.material_override = m
			mmi.custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = lods[lod]
			mm.instance_count = HOUSE_LOD_MAX[lod]
			mm.visible_instance_count = 0
			mmi.multimesh = mm
			_houses.append(mmi)
			add_child(mmi)
	_figure_material.shader = FIGURE_SHADER
	_figure_material.set_shader_parameter("figure_scale", FIGURE_M * TileTerrain.DIORAMA_KM_PER_M)
	_figure_material.set_shader_parameter("list_w", LIST_W)
	_list_tex = ImageTexture.create_from_image(_list_image)
	_figure_material.set_shader_parameter("list_tex", _list_tex)
	_figures = MultiMeshInstance3D.new()
	_figures.name = "PeopleFigures"
	_figures.material_override = _figure_material
	_figures.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON # like the trees up close
	_figures.custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	var fm := MultiMesh.new()
	fm.transform_format = MultiMesh.TRANSFORM_3D
	fm.mesh = _figure_mesh()
	fm.instance_count = FIGURE_MAX
	fm.visible_instance_count = 0
	_figures.multimesh = fm
	add_child(_figures)
	_figure_shadow_material.shader = FIGURE_SHADOW_SHADER
	for key in ["figure_scale", "list_w", "list_tex"]:
		_figure_shadow_material.set_shader_parameter(key, _figure_material.get_shader_parameter(key))
	_figure_shadows = MultiMeshInstance3D.new()
	_figure_shadows.name = "PeopleFigureShadows"
	_figure_shadows.material_override = _figure_shadow_material
	_figure_shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_figure_shadows.custom_aabb = _figures.custom_aabb
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.mesh = _shadow_strip_mesh()
	sm.instance_count = FIGURE_MAX
	sm.visible_instance_count = 0
	_figure_shadows.multimesh = sm
	_figures.add_child(_figure_shadows) # shown with the figures
	_crop_material.shader = CROP_SHADER
	_crop_material.set_shader_parameter("crop_n", CROP_N)
	_crop_material.set_shader_parameter("crop_rows", float(CROP_ROWS))
	_crop_material.set_shader_parameter("km_per_m", TileTerrain.DIORAMA_KM_PER_M)
	_crops = MultiMeshInstance3D.new()
	_crops.name = "PeopleCrops"
	_crops.material_override = _crop_material
	_crops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON # slabs, fences and sheep stand in the light
	_crops.custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.mesh = _crop_mesh()
	cm.instance_count = CROP_N * CROP_N
	_crops.multimesh = cm
	_crops.visible = false
	add_child(_crops)
	_trips = PeopleTrips.new()
	_trips.setup(people, TileTerrain.DIORAMA_KM_PER_M)
	add_child(_trips)
	_lots_view = SubViewport.new()
	_lots_view.name = "HouseLots"
	_lots_view.size = Vector2i(LOTS_N, LOTS_N)
	_lots_view.transparent_bg = true
	_lots_view.disable_3d = true
	_lots_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_lots_material.shader = LOTS_SHADER
	_lots_material.set_shader_parameter("list_tex", _house_list_tex)
	_lots_material.set_shader_parameter("list_w", LIST_W)
	_lots_material.set_shader_parameter("lot_km", LOT_KM)
	_lots = MultiMeshInstance2D.new()
	_lots.material = _lots_material
	var lm := MultiMesh.new()
	lm.transform_format = MultiMesh.TRANSFORM_2D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	lm.mesh = quad
	lm.instance_count = HOUSE_MAX
	lm.visible_instance_count = 0
	_lots.multimesh = lm
	_lots_view.add_child(_lots)
	add_child(_lots_view)
	for m: ShaderMaterial in [terrain._terrain_material, _crop_material, _prep_material]:
		m.set_shader_parameter("sim_lot_tex", _lots_view.get_texture())
		m.set_shader_parameter("sim_lots_n", LOTS_N)
		m.set_shader_parameter("sim_lot_km", LOT_KM)
	for u in TileTerrain.TERRAIN_SHADER.get_shader_uniform_list():
		if not String(u.name).begins_with("sim_"): # the grain layers are the terrain's own
			_shared_uniforms.append(StringName(u.name))
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	_legend = people.legend()
	_build_hud()
	var tables := SimTables.new() # T: markets, population, farms, state and history as tables
	tables.setup(people, get_parent())
	add_child(tables)
	var events := SimEvents.new() # E: what happens, at the bottom right
	events.setup(people, get_parent())
	add_child(events)
	_rebuild()
	_rebuild_houses()
	if _bench_path != "":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	return true

## A float render target with one pixel per record, rendered on demand.
func _make_prep(view_name: String, rect: ColorRect, material: ShaderMaterial) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.use_hdr_2d = true # RGBA16F
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	rect.material = material
	view.add_child(rect)
	add_child(view)
	return view

## House texture for the current number of house pages.
func _rebuild_houses() -> void:
	_house_texture = people.make_house_texture()
	var side: int = people.page_side()
	var size := Vector2i(side, side * _house_texture.get_layers())
	_house_prep_view.size = size
	_house_prep_rect.size = Vector2(size)
	for m in _house_materials + [_house_prep_material, _lots_material]:
		m.set_shader_parameter("people_tex", _house_texture)
		m.set_shader_parameter("page_side", side)
	for m in _house_materials + [_lots_material]:
		m.set_shader_parameter("place_tex", _house_prep_view.get_texture())
	_house_prep_frames = 2
	_house_list_at = Vector3.INF

## Texture and instance count for the current number of pages.
func _rebuild() -> void:
	_texture = people.make_texture()
	var side: int = people.page_side()
	var size := Vector2i(side, side * _texture.get_layers())
	_prep_view.size = size
	_prep_rect.size = Vector2(size)
	for m in [_material, _prep_material]:
		m.set_shader_parameter("people_tex", _texture)
		m.set_shader_parameter("page_side", side)
	_material.set_shader_parameter("place_tex", _prep_view.get_texture())
	for m in [_figure_material, _figure_shadow_material]:
		m.set_shader_parameter("people_tex", _texture)
		m.set_shader_parameter("page_side", side)
		m.set_shader_parameter("place_tex", _prep_view.get_texture())
	_list_at = Vector3.INF
	_prep_frames = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _dot_mesh()
	mm.instance_count = _texture.get_layers() * people.page_side() * people.page_side() / DOTS_PER_INSTANCE
	multimesh = mm
	_apply_colours()

## A person 1 unit tall (1.7 m) of blocks, in the voxel style of the houses
## (Urbek): feet, legs, tunic, arms, head and hair as boxes on a grid of
## 0.04 units (7 cm), each part its own block so it can swing, plus the
## props of the trades (tool or spear, shield, sword, cloak, apron, bundle)
## that people_figures.gdshader shows by occupation and estate and folds
## away for everyone else. Vertex colours are sRGB with the corner shading
## of the voxel meshes (VoxelMesh.AO) in alpha; UV.x names the part (FIG_*).
const FIG_TUNIC := 0 # dyed, a long dress on women, a robe on clergy and scholars
const FIG_LEG_L := 1
const FIG_LEG_R := 2
const FIG_ARM_L := 3
const FIG_ARM_R := 4
const FIG_HAIR := 5 # a headscarf on women
const FIG_FIXED := 6
const FIG_SANDAL_L := 7 # bare feet on the unfree
const FIG_SANDAL_R := 8
const FIG_POLE := 9 # staff, hoe or spear shaft in the right hand
const FIG_HOE := 10
const FIG_SPEAR := 11
const FIG_SHIELD := 12
const FIG_SWORD := 13
const FIG_CLOAK := 14
const FIG_APRON := 15
const FIG_BUNDLE := 16

## The figures' shadows fall the way the scene's sun throws them.
func _aim_figure_shadows() -> void:
	var sun = get_parent().get("sun")
	if not sun is DirectionalLight3D:
		return
	var d: Vector3 = -(sun as DirectionalLight3D).global_transform.basis.z # the way the light travels
	if d.y > -0.05:
		return
	_figure_shadow_material.set_shader_parameter("shadow_dir", Vector2(d.x, d.z) / -d.y)

## One strip for a figure's shadow: UV.x along it (0 at the feet, 1 at the
## far end), UV.y across (-1, 1); people_figure_shadows.gdshader lays it out.
static func _shadow_strip_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		var c: Vector2 = corners[i]
		st.set_uv(c)
		st.add_vertex(Vector3(c.x, 0.0, c.y))
	return st.commit()

static func _figure_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.77, 0.55, 0.41)
	var hair := Color(0.26, 0.17, 0.1)
	var sandal := Color(0.36, 0.24, 0.15)
	var wood := Color(0.42, 0.3, 0.18)
	var iron := Color(0.55, 0.56, 0.58)
	# chunky like Urbek's people: legs and arms two blocks apart, a broad
	# tunic and a head a little big
	for side in [-1.0, 1.0]:
		var left: bool = side < 0.0
		_box(st, Vector3(0.075 * side, 0.02, 0.02), Vector3(0.05, 0.02, 0.07), sandal, FIG_SANDAL_L if left else FIG_SANDAL_R)
		_box(st, Vector3(0.075 * side, 0.26, 0.0), Vector3(0.05, 0.22, 0.05), skin, FIG_LEG_L if left else FIG_LEG_R)
		_box(st, Vector3(0.2 * side, 0.62, 0.0), Vector3(0.05, 0.16, 0.05), skin, FIG_ARM_L if left else FIG_ARM_R)
	# the tunic's hem stays the only geometry below 0.5 (the shader lets it
	# down into a long dress)
	_box(st, Vector3(0.0, 0.62, 0.0), Vector3(0.15, 0.18, 0.1), Color.WHITE, FIG_TUNIC)
	_box(st, Vector3(0.0, 0.9, 0.0), Vector3(0.08, 0.08, 0.08), skin, FIG_FIXED)
	_box(st, Vector3(0.0, 0.975, -0.01), Vector3(0.088, 0.025, 0.088), hair, FIG_HAIR)
	_box(st, Vector3(0.0, 0.9, -0.072), Vector3(0.088, 0.06, 0.025), hair, FIG_HAIR)
	# props
	_box(st, Vector3(0.25, 0.56, 0.06), Vector3(0.018, 0.56, 0.018), wood, FIG_POLE)
	_box(st, Vector3(0.25, 1.08, 0.12), Vector3(0.018, 0.04, 0.08), iron, FIG_HOE)
	_box(st, Vector3(0.25, 1.18, 0.06), Vector3(0.026, 0.06, 0.026), iron, FIG_SPEAR)
	_box(st, Vector3(-0.29, 0.56, 0.02), Vector3(0.02, 0.2, 0.12), Color(0.58, 0.16, 0.12), FIG_SHIELD)
	_box(st, Vector3(-0.314, 0.56, 0.02), Vector3(0.008, 0.04, 0.04), Color(0.78, 0.66, 0.34), FIG_SHIELD)
	_box(st, Vector3(-0.2, 0.36, 0.07), Vector3(0.012, 0.12, 0.02), iron, FIG_SWORD)
	_box(st, Vector3(-0.2, 0.5, 0.07), Vector3(0.02, 0.012, 0.036), wood, FIG_SWORD)
	_box(st, Vector3(0.0, 0.54, -0.115), Vector3(0.17, 0.26, 0.012), Color.WHITE, FIG_CLOAK)
	_box(st, Vector3(0.0, 0.5, 0.112), Vector3(0.12, 0.16, 0.012), Color(0.4, 0.27, 0.16), FIG_APRON)
	_box(st, Vector3(0.0, 0.66, -0.16), Vector3(0.09, 0.1, 0.06), Color(0.6, 0.5, 0.34), FIG_BUNDLE)
	return st.commit()

## An axis-aligned box around `centre` with half extents `half`. The side
## faces darken towards the bottom like a voxel model's corner shading
## (VoxelMesh.AO), kept in the vertex alpha.
static func _box(st: SurfaceTool, centre: Vector3, half: Vector3, colour: Color, part: int) -> void:
	var uv := Vector2(part, 0)
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = half[(axis + 1) % 3]
			var w := Vector3.ZERO
			w[(axis + 2) % 3] = half[(axis + 2) % 3]
			var c := centre + n * half[axis]
			var q := [c - u - w, c + u - w, c + u + w, c - u + w]
			var order := [0, 2, 1, 0, 3, 2] if sgn > 0.0 else [0, 1, 2, 0, 2, 3] # Godot fronts are clockwise
			for i in order:
				var v: Vector3 = q[i]
				var ao: float = VoxelMesh.AO[3]
				if axis != 1:
					ao = VoxelMesh.AO[2] if v.y < centre.y else VoxelMesh.AO[3]
				elif sgn < 0.0:
					ao = VoxelMesh.AO[1]
				st.set_color(Color(colour.r, colour.g, colour.b, ao)); st.set_uv(uv); st.set_normal(n); st.add_vertex(v)

## A parcel's field: the slab (UV.x = -1), CROP_ROWS rows (UV.x their
## place across the parcel, UV.y their number) and the fence (UV.x = -2,
## UV.y side * 16 + post, 15 the rail) and a flock for the pasture (UV.x =
## -3, UV.y sheep * 4 + body, legs or head), each a unit box (x, z
## -0.5..0.5, y 0..1, no bottom); people_crops.gdshader sizes and places
## them by crop and season. Flat faces: the sides a step darker in the vertex alpha.
static func _crop_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts: Array[Vector2] = [Vector2(-1.0, 0.0)]
	for i in CROP_ROWS:
		parts.append(Vector2((i + 0.5) / CROP_ROWS, i))
	for side in 4:
		for k: int in range(FENCE_POSTS) + [15]:
			parts.append(Vector2(-2.0, side * 16 + k))
	for k in FLOCK_MAX:
		for part in 3:
			parts.append(Vector2(-3.0, k * 4 + part))
	for uv in parts:
		for axis in 3:
			for sgn in [-1.0, 1.0]:
				if axis == 1 and sgn < 0.0:
					continue
				var n := Vector3.ZERO
				n[axis] = sgn
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 0.5
				var w := Vector3.ZERO
				w[(axis + 2) % 3] = 0.5
				var c := Vector3(0, 0.5, 0) + n * 0.5
				var q := [c - u - w, c + u - w, c + u + w, c - u + w]
				var order := [0, 2, 1, 0, 3, 2] if sgn > 0.0 else [0, 1, 2, 0, 2, 3] # Godot fronts are clockwise
				var shade := 1.0 if axis == 1 else 0.8
				for k in order:
					st.set_color(Color(1, 1, 1, shade)); st.set_uv(uv); st.set_normal(n); st.add_vertex(q[k])
	return st.commit()

## The grain layers on the terrain material: the road map when a month is
## built, the fine window when the month changes or the camera leaves its
## middle half.
func _update_map() -> void:
	var mat: ShaderMaterial = terrain._terrain_material
	# the crops read the fine layer too, and the placement of the people for
	# the slabs they stand on
	var mats: Array[ShaderMaterial] = [mat, _crop_material, _prep_material]
	for m in mats:
		m.set_shader_parameter("sim_map_on", map_on)
	if not map_on:
		return
	# the layers switch by view width, not by pixel size, so the switch never
	# runs as a seam across the screen
	for m in mats:
		m.set_shader_parameter("sim_view_km", get_parent().width if "width" in get_parent() else 360.0)
	var version: int = people.map_version()
	var centre: Vector2 = get_parent().target if "target" in get_parent() else Vector2.ZERO
	var moved := _map_at == Vector2.INF or _map_at.distance_to(centre) > MAP_N * 1.5625 * 0.25
	if version == _map_version and not moved:
		return
	if version != _map_version:
		var roads: Dictionary = people.road_map()
		if roads.has("image"):
			var img: Image = roads.image
			if _road_tex == null or _road_tex.get_size() != Vector2(img.get_size()):
				_road_tex = ImageTexture.create_from_image(img)
			else:
				_road_tex.update(img)
			mat.set_shader_parameter("sim_road_tex", _road_tex)
			mat.set_shader_parameter("sim_cell_origin", roads.origin)
			mat.set_shader_parameter("sim_cell_km", roads.cell_km)
			mat.set_shader_parameter("sim_cell_n", img.get_size())
	var win: Dictionary = people.map_window(centre.x, centre.y, MAP_N)
	if win.has("image"):
		if _map_tex == null:
			_map_tex = ImageTexture.create_from_image(win.image)
		else:
			_map_tex.update(win.image)
		for m in mats:
			m.set_shader_parameter("sim_fine_tex", _map_tex)
			m.set_shader_parameter("sim_fine_origin", win.origin)
			m.set_shader_parameter("sim_fine_km", win.tile_km)
			m.set_shader_parameter("sim_fine_n", MAP_N)
		_prep_frames = 2
	_map_version = version
	_map_at = centre

## The regions coloured by a column of the markets (sim_tables.gd), one
## texel per 25 km cell as sim_map.gdshaderinc sim_regions reads it; null
## clears them.
func paint_regions(img: Image, grid: Dictionary) -> void:
	var mat: ShaderMaterial = terrain._terrain_material
	if img == null:
		mat.set_shader_parameter("sim_regions_on", false)
		return
	if _region_tex == null or _region_tex.get_size() != Vector2(img.get_size()):
		_region_tex = ImageTexture.create_from_image(img)
	else:
		_region_tex.update(img)
	mat.set_shader_parameter("sim_region_tex", _region_tex)
	mat.set_shader_parameter("sim_cell_origin", grid.origin)
	mat.set_shader_parameter("sim_cell_km", grid.cell_km)
	mat.set_shader_parameter("sim_cell_n", img.get_size())
	mat.set_shader_parameter("sim_regions_on", true)

## The people near the view, as a slot list for the figure shader.
func _update_figures(view_km: float, synced: bool) -> void:
	var centre: Vector2 = get_parent().target if "target" in get_parent() else Vector2.ZERO
	var radius := view_km * 1.2 # the oblique view reaches further back than wide
	var moved := Vector2(_list_at.x, _list_at.y).distance_to(centre) > view_km * 0.2
	if not synced and not moved and absf(radius - _list_at.z) < radius * 0.2:
		return
	_list_at = Vector3(centre.x, centre.y, radius)
	var slots: PackedInt32Array = people.near(centre.x, centre.y, radius, FIGURE_MAX)
	var values := PackedFloat32Array()
	values.resize(FIGURE_MAX)
	for i in slots.size():
		values[i] = float(slots[i])
	_list_image.set_data(LIST_W, FIGURE_MAX / LIST_W, false, Image.FORMAT_RF, values.to_byte_array())
	_list_tex.update(_list_image)
	_figures.multimesh.visible_instance_count = slots.size()
	_figure_shadows.multimesh.visible_instance_count = slots.size()

## The square of parcels whose crops stand, around the camera; only up
## close and on the finest terrain tiles (the parcel is half a tile).
func _update_crops(view_km: float) -> void:
	var tile_km: float = terrain._terrain_material.get_shader_parameter("tile_km")
	_crops.visible = map_on and view_km <= CROP_KM and tile_km <= 0.5
	if not _crops.visible:
		for m: ShaderMaterial in [terrain._terrain_material, _prep_material]:
			m.set_shader_parameter("sim_crop_box", Vector4.ZERO)
		return
	var centre: Vector2 = get_parent().target if "target" in get_parent() else Vector2.ZERO
	# a parcel is half a data tile: up close one quarter tile (sub_tiles)
	var size := tile_km * (1.0 if terrain.sub_tiles else 0.5)
	# parcels and lots on the terrain's tile grid, counted from world_min
	var from: Vector2 = centre - terrain.world_min
	var cell0 := (from / size).floor() - Vector2(CROP_N / 2, CROP_N / 2)
	_crop_material.set_shader_parameter("crop_cell0", cell0)
	# where the crops stand the ground round their slabs is meadow (sim_map.gdshaderinc)
	var box_min: Vector2 = terrain.world_min + cell0 * size
	var box_max := box_min + Vector2(CROP_N, CROP_N) * size
	var box := Vector4(box_min.x, box_min.y, box_max.x, box_max.y)
	if box != terrain._terrain_material.get_shader_parameter("sim_crop_box"):
		_prep_frames = 2 # the people on the slabs
	for m: ShaderMaterial in [terrain._terrain_material, _prep_material]:
		m.set_shader_parameter("sim_crop_box", box)
	var lot0 := (from / LOT_KM).floor() - Vector2(LOTS_N / 2, LOTS_N / 2)
	_lots_material.set_shader_parameter("lot_origin", lot0)
	_lots_material.set_shader_parameter("world_min", terrain.world_min)
	for m: ShaderMaterial in [terrain._terrain_material, _crop_material, _prep_material]:
		m.set_shader_parameter("sim_lot_origin", lot0)
	_lots_view.render_target_update_mode = SubViewport.UPDATE_ONCE

## The houses near the camera, nearest first, split over the levels of
## detail: the nearest in the finest one the view width allows.
func _update_houses(view_km: float, synced: bool) -> void:
	var centre: Vector2 = get_parent().target if "target" in get_parent() else Vector2.ZERO
	var radius := view_km * 1.2
	var moved := Vector2(_house_list_at.x, _house_list_at.y).distance_to(centre) > view_km * 0.2
	if not synced and not moved and absf(radius - _house_list_at.z) < radius * 0.2:
		return
	_house_list_at = Vector3(centre.x, centre.y, radius)
	var slots: PackedInt32Array = people.houses_near(centre.x, centre.y, radius, HOUSE_MAX)
	var values := PackedFloat32Array()
	values.resize(HOUSE_MAX)
	for i in slots.size():
		values[i] = float(slots[i])
	_house_list_image.set_data(LIST_W, HOUSE_MAX / LIST_W, false, Image.FORMAT_RF, values.to_byte_array())
	_house_list_tex.update(_house_list_image)
	var start := 0
	var levels := HOUSE_LOD_MAX.size()
	for lod in levels:
		var n := 0
		if view_km <= HOUSE_LOD_KM[lod]:
			n = mini(slots.size() - start, HOUSE_LOD_MAX[lod])
		for variant in Farmhouse.VARIANTS:
			var i := variant * levels + lod
			_house_materials[i].set_shader_parameter("list_offset", start)
			_houses[i].multimesh.visible_instance_count = n
		start += n
	_lots.multimesh.visible_instance_count = slots.size()

## DOTS_PER_INSTANCE triangles around the unit circle, z = dot number; the
## shader scales each to pixels and cuts the round dot out of it.
static func _dot_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	for i in DOTS_PER_INSTANCE:
		verts.append_array([Vector3(0, 2, i), Vector3(-1.7320508, -1, i), Vector3(1.7320508, -1, i)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "PeopleHud"
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	_legend_label = _hud_label(root)
	_legend_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_legend_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_info_label = _hud_label(root)
	_info_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_info_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

static func _hud_label(parent: Node) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size = Vector2(220, 0)
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_font_size_override("bold_font_size", 13)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.07, 0.05, 0.75)
	box.set_content_margin_all(8)
	box.set_corner_radius_all(4)
	label.add_theme_stylebox_override("normal", box)
	label.visible = false
	parent.add_child(label)
	return label

## Palette by occupation (modes 1 and 2) or estate (mode 3), and the legend.
func _apply_colours() -> void:
	var palette := PackedVector3Array()
	palette.resize(16)
	var lines := []
	match colour_mode:
		1:
			for j in JOB_COLOURS.size():
				palette[j] = _linear(JOB_COLOURS[j])
				lines.append([JOB_COLOURS[j], _legend.jobs[j]])
		2:
			for j in _legend.job_group.size():
				palette[j] = _linear(GROUP_COLOURS[_legend.job_group[j]])
			for g in GROUP_COLOURS.size():
				lines.append([GROUP_COLOURS[g], _legend.groups[g]])
		3:
			for k in STAND_COLOURS.size():
				palette[k] = _linear(STAND_COLOURS[k])
				lines.append([STAND_COLOURS[k], STANDS[k]])
	for m in [_material, _figure_material]:
		m.set_shader_parameter("colour_mode", colour_mode)
		m.set_shader_parameter("palette", palette)
		m.set_shader_parameter("selected_slot", selected)
	var text := "[b]Bewohner: %s[/b]  (C)" % MODES[colour_mode]
	for line in lines:
		text += "\n[outline_size=3][outline_color=#ffffff90][color=#%s][font_size=17]●[/font_size][/color][/outline_color][/outline_size] %s" % [line[0].to_html(false), line[1]]
	_legend_label.text = text
	_legend_label.visible = colour_mode != 0

## Palette entries as linear colour, as source_color uniforms arrive.
static func _linear(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)

## The dot under `pixel`: reads the placement texture back (only on a
## click) and lets ApoleiaPeople find the nearest dot on screen.
func _pick(pixel: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not visible:
		return
	var vp := cam.get_camera_projection() * Projection(cam.get_camera_transform().affine_inverse())
	var m := PackedFloat32Array()
	for c in 4:
		var col: Vector4 = vp[c]
		m.append_array([col.x, col.y, col.z, col.w])
	var level_h: float = terrain._terrain_material.get_shader_parameter("level_h")
	# aim at a figure's middle, or at a dot (drawn 0.12 levels up)
	var lift := FIGURE_M * TileTerrain.DIORAMA_KM_PER_M * 0.5 if _figures.visible else 0.12 * level_h
	selected = people.pick(_prep_view.get_texture().get_image(), m, get_viewport().get_visible_rect().size, pixel, level_h, lift, PICK_PX)
	for mat in [_material, _figure_material]:
		mat.set_shader_parameter("selected_slot", selected)
	print(JSON.stringify({"event": "people_pick", "pixel": [pixel.x, pixel.y], "slot": selected}))
	_waiting = selected >= 0
	_info_label.visible = _waiting
	if _waiting:
		people.ask_person(selected)
		_info_label.text = "…"

func _show_person(p: Dictionary) -> void:
	if p.is_empty():
		_info_label.text = "[i]nicht mehr da[/i]"
		return
	var lines := PackedStringArray()
	lines.append("[b]%s, %d Jahre[/b]  #%d" % ["Frau" if p.female else "Mann", int(p.age), p.pid])
	lines.append("%s, %s" % [p.job, STANDS[clampi(p.stand, 0, 3)]])
	lines.append("Gruppe: %s" % (", ".join(p.factions) if p.factions.size() > 0 else p.group))
	lines.append("Haushalt %d: %d Personen" % [p.household, p.members])
	lines.append("verheiratet" if p.spouse >= 0 else ("Kind" if p.age < 14.0 else "ledig oder verwitwet"))
	# Health is body weight in per mille of normal weight (S84, 1000 = BMI 21)
	var health := "Gewicht %d %% (BMI %.1f)" % [int(p.health / 10.0), 21.0 * p.health / 1000.0]
	if p.iq >= 0.0:
		health += ", IQ %d" % roundi(p.iq)
	lines.append(health)
	lines.append("Kultur %d, Religion %d" % [p.culture, p.religion])
	if p.has("hh_kind"):
		# the household as the grain economy sees it (counted once a month)
		var kind: String = p.hh_kind
		var farm := ""
		if p.has("farm_kind"):
			farm = "%s, %.2f ha Feld" % [p.farm_kind, p.farm_ha]
		lines.append(farm if kind == "Hof" and farm != "" else KIND_NOTES.get(kind, kind))
		var fed: float = p.fed / 10.0
		var colour := "#e05040" if fed < 80.0 else ("#e0a040" if fed < 95.0 else "#80c060")
		lines.append("[color=%s]gegessen: %d %% des Bedarfs[/color], Vorrat %d kg" % [colour, int(fed), int(p.pantry_kg)])
		if p.has("money"):
			lines.append("Geld des Haushalts: %s Denar" % SimTables._int(roundi(p.money)))
	if p.travelling > 0:
		lines.append("[color=#e05040]%s[/color]" % ("wandert aus" if p.travelling == 2 else "unterwegs"))
	_info_label.text = "\n".join(lines)
	print(JSON.stringify({"event": "people_person", "pid": p.pid}))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
		elif _press_at.distance_to(event.position) <= CLICK_PX:
			_pick(event.position)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				colour_mode = (colour_mode + 1) % MODES.size()
				_apply_colours()
			KEY_ESCAPE:
				selected = -1
				_waiting = false
				for m in [_material, _figure_material]:
					m.set_shader_parameter("selected_slot", -1)
				_info_label.visible = false
			KEY_P: shown = not shown
			KEY_G:
				map_on = not map_on
				_map_version = -1
			KEY_BRACKETLEFT: days_per_second = maxf(days_per_second * 0.5, 0.0)
			KEY_BRACKETRIGHT: days_per_second = maxf(days_per_second * 2.0, 1.0)

func _process(delta: float) -> void:
	if people == null:
		return
	_day_debt += days_per_second * delta
	var whole := int(_day_debt)
	if whole > 0 and people.backlog() < 4:
		people.advance(whole)
	_day_debt -= whole
	_frames += 1
	if _frames == 20 and _click_at != Vector2.INF:
		_pick(_click_at)
	if _waiting:
		var p: Dictionary = people.take_person()
		if not p.is_empty():
			_waiting = false
			_show_person(p)
	_update_map()
	visible = TileTerrain.PROP_SLOTS[terrain.level] > 0
	var view_km: float = get_parent().width if "width" in get_parent() else 360.0
	# realistic by default: figures at their real size up close, houses in the
	# close LOD, no people from further up; P adds the dots as an overview
	var figures := view_km <= FIGURE_KM
	var dots := shown and not figures
	_hud.visible = visible and (figures or dots)
	var landscape := get_parent()
	_trips.step(delta, visible and figures, landscape.target if "target" in landscape else Vector2.ZERO, view_km)
	if not visible:
		# out of the close LOD the frame does nothing for the people: no
		# upload, no placement pass, no draw. The sim thread keeps running and
		# its front buffer collects the changed pages until they show again.
		if _bench_path != "":
			_bench_step()
		return
	var synced: int = people.sync(_texture)
	if synced < 0:
		_rebuild()
	var synced_houses: int = people.sync_houses(_house_texture)
	if synced_houses < 0:
		_rebuild_houses()
	# the dots stand on the terrain: same zoom level, relief blend and patch
	# only what changed: setting a texture rebuilds a material's uniform set,
	# for some 20 materials each frame (Mac tour, 29.10.2026)
	var source: ShaderMaterial = terrain._terrain_material
	var targets: Array = [_material, _prep_material, _house_prep_material, _figure_material, _figure_shadow_material, _crop_material, _trips.material] + _house_materials
	if targets.size() != _shared_count:
		_shared_values.clear() # new house materials get everything
		_shared_count = targets.size()
	for key in _shared_uniforms:
		var value = source.get_shader_parameter(key)
		if _shared_values.has(key) and typeof(_shared_values[key]) == typeof(value) and _shared_values[key] == value:
			continue
		_shared_values[key] = value
		for m in targets:
			m.set_shader_parameter(key, value)
	# floats rounded, so the camera settling by a hair does not rerun the pass
	var key_now := PLACE_KEYS.map(func(k):
		var v = source.get_shader_parameter(k)
		return snappedf(v, 0.001) if v is float else v)
	if key_now != _place_key:
		_place_key = key_now
		_prep_frames = 2 # this frame and the next (the corner cache may lag a frame)
		_house_prep_frames = 2
	if synced > 0:
		_prep_frames = 2
	if synced_houses > 0:
		_house_prep_frames = 2
	if _house_prep_frames > 0:
		_house_prep_frames -= 1
		_house_prep_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _prep_frames > 0 and (figures or dots):
		_prep_frames -= 1
		prep_runs += 1
		_prep_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	# 3.5 px up close, about 1.7 px at 360 km and 1 px over the whole sea, so
	# the dots stay single people instead of melting into black regions
	var px := clampf(3.5 - 0.5 * log(maxf(view_km, 1.0) / 30.0) / log(2.0), 1.0, 3.5)
	_update_houses(view_km, synced_houses != 0)
	_update_crops(view_km)
	_figures.visible = figures
	multimesh.visible_instance_count = -1 if dots else 0
	if figures:
		_update_figures(view_km, synced > 0)
		_aim_figure_shadows()
	_material.set_shader_parameter("dot_px", px)
	var want_round := px >= ROUND_FROM_PX
	if want_round != (_material.shader == SHADER_ROUND):
		_material.shader = SHADER_ROUND if want_round else SHADER
		_material.set_shader_parameter("people_tex", _texture)
		_material.set_shader_parameter("page_side", people.page_side())
		_material.set_shader_parameter("place_tex", _prep_view.get_texture())
		_apply_colours()
	if _bench_path != "":
		_bench_step()

func _bench_step() -> void:

	_bench_frame += 1
	var f := _bench_frame - BENCH_WARMUP
	if f < 0:
		return
	var vp := get_viewport().get_viewport_rid()
	var on := f < BENCH_FRAMES
	var tag := "on" if on else "off"
	var now := Time.get_ticks_usec()
	if _bench_last > 0:
		_bench[tag].append((now - _bench_last) / 1000.0) # whole frame, ms
	_bench_last = now
	_bench[tag + "_gpu"].append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if on:
		var t: Dictionary = people.timings()
		_bench.sync_usec.append(t.sync_usec)
		_bench.sync_layers.append(t.sync_layers)
		_bench.prep.append(float(prep_runs - _bench_prep_last))
		_bench.process_on.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	else:
		_bench.process_off.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_bench_prep_last = prep_runs
	if f == BENCH_FRAMES:
		shown = false
	if f == 2 * BENCH_FRAMES:
		var out := {"people": people.count(), "day": people.day(), "instances": multimesh.instance_count,
			"timings_last": people.timings(), "renderer": RenderingServer.get_video_adapter_name(),
			"tile_km": terrain.tile_km, "prep_share": _mean(_bench.prep)}
		for key in _bench:
			var v: Array = _bench[key].duplicate()
			v.sort()
			out[key + "_median"] = v[v.size() / 2] if v.size() > 0 else 0.0
			out[key + "_p95"] = v[int(v.size() * 0.95)] if v.size() > 0 else 0.0
		DirAccess.make_dir_recursive_absolute(_bench_path.get_base_dir())
		var file := FileAccess.open(_bench_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "  "))
		file.close()
		print(JSON.stringify({"event": "people_bench", "path": _bench_path}))
		shown = true

static func _mean(v: Array) -> float:
	var total := 0.0
	for x in v:
		total += x
	return total / maxf(v.size(), 1.0)
