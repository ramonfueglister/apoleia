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
## the terrain is close (TileTerrain.CLOSE_LEVEL: the quarter and 0.5 km tiles).
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
## black); a click on a dot or figure, or on a traveller on its way
## (carrier, trader, day labourer: people_trips.gd), shows that person and
## their household, for a traveller also what they are doing; Esc closes it.
## The grain economy (crate::grain, run beside the people) shows on the
## terrain: fields by season around the farms, footpaths to the markets,
## market squares, trade roads and sea lanes (sim_map.gdshaderinc, layers
## from ApoleiaPeople.map_window and road_map, rebuilt once a month).
## A click shows the household's kind, how much it ate and its money. T
## opens the simulation's tables (sim_tables.gd). Up close the trips to
## market and between markets walk the paths and roads (people_trips.gd).
## Keys: P shows or hides the dots (an overview, off by default), G the
## grain economy on the map (on by default). How many days a second run
## (`days_per_second`) is set by the game clock (game_clock.gd).
## Command line (after --): --people-days=n days per second (default 10),
## --people-bench=path.json writes frame timings with dots on and off
## (relative paths start at the repository root), --people-colour=n starts
## in colour mode n (MODES), --people-click=x,y clicks that pixel once,
## --people-dots starts with the dot overview on, --people-warm=n runs n
## days before the first frame (screenshots of a later year),
## --people-cost=path.json writes what each part of the people costs a frame
## (people_cost.gd; --people-cost-frames=n frames per phase, default 12).

const SHADER = preload("res://shaders/people_dots.gdshader")
const SHADER_ROUND = preload("res://shaders/people_dots_round.gdshader")
const ROUND_FROM_PX := 1.75 # below this the dots stay triangles (no discard)
const PREP_SHADER = preload("res://shaders/people_dots_prep.gdshader")
const HOUSE_SHADER = preload("res://shaders/people_houses.gdshader")
const FIGURE_SHADER = preload("res://shaders/people_figures.gdshader")
const FIGURE_SHADOW_SHADER = preload("res://shaders/people_figure_shadows.gdshader")
const CROP_SHADER = preload("res://shaders/people_crops.gdshader")
const PARCELS_SHADER = preload("res://shaders/people_parcels.gdshader")
const CROP_N := 40 # parcels per side of the square of crops around the ground in view
const CROP_ROWS := 8 # rows of crops or vines per parcel: clumps 8-10 px wide at 3 km, as Urbek's (r11: 12 rows read as dots)
const CROP_LUMPS := 6 # lumps a row can carry (round O, people_crops.gdshader CROP_LUMPS)
const FENCE_POSTS := 6 # posts per side of a fenced field (people_crops.gdshader)
const HEDGE_BLOCKS := 5 # blocks per side of a hedged field, about two metres each (people_crops.gdshader)
const FLOCK_MAX := 9 # sheep in the largest flock on a pasture parcel (a three by three grid, people_crops.gdshader)
const CROP_KM := 8.0 # view width up to which crops stand (sim_fields.gdshaderinc SIM_CROPS_KM)
const LOTS_SHADER = preload("res://shaders/people_lots.gdshader")
const LOT_KM := 0.5 # a village lot (people_dots_common.gdshaderinc DOT_LOT_KM)
const LOTS_N := 128 # lots per side of the lot mask around the camera (64 km: what the player built shows to FIELDS_KM)
const FIELDS_KM := 40.0 # view width up to which the terrain draws the fields (sim_fields.gdshaderinc SIM_FIELDS_KM)
const BUILT_COPY := "shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nvoid fragment() { COLOR = texture(TEXTURE, UV); }\n"
const FIGURE_KM := 10.0 # view width up to which people are figures, not dots
const FIGURE_M := 1.7 # figure height (the figure mesh is 1 unit tall)
const FIGURE_MAX := 16384 # most figures drawn at once (nearest first)
const LIST_W := 128 # width of the slot list texture
const ROAD_CODE := 8192.0 # record area codes (people_dots_common.gdshaderinc DOT_ROAD, DOT_AT_LOT)
const AT_LOT_CODE := 12288.0
const ROUTE_W := 32 # texels per figure in the field way texture: its count and length, then its points
const ROUTE_BUDGET_USEC := 2000 # time a frame may spend on new field ways (a search each); the rest follow next frame
const Farmhouse = preload("res://scripts/voxel/farmhouse.gd")
const VoxelMesh = preload("res://scripts/voxel/voxel_mesh.gd")
const SimTables = preload("res://scripts/sim/sim_tables.gd")
const PersonWindow = preload("res://scripts/sim/person_window.gd")
const DayClock = preload("res://scripts/sim/day_clock.gd")
const DayPlan = preload("res://scripts/sim/day_plan.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const ContextMenu = preload("res://scripts/ui/context_menu.gd")
const SimEvents = preload("res://scripts/sim/sim_events.gd")
const Keys = preload("res://scripts/ui/keys.gd")
const PeopleTrips = preload("res://scripts/sim/people_trips.gd")
const HouseLife = preload("res://scripts/sim/people_house_life.gd")
const PeopleFlows = preload("res://scripts/sim/people_flows.gd")
const PeopleCost = preload("res://scripts/sim/people_cost.gd")
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
const BENCH_WARMUP := 90
const BENCH_FRAMES := 240

var people: RefCounted
var terrain: Node3D
var days_per_second := 10.0
var shown := false # P key: the dots as an overview (map view), off by default
var drawn := true # false draws none of the people but keeps their work per frame (tour_bench.gd people-draw)
var colour_mode := 0 # C key, index into MODES
var selected := -1 # slot of the clicked person
var map_on := true # G key: the grain economy on the terrain
var _map_version := -1
var _map_at := Vector2.INF
var _map_tex: ImageTexture
var _way_tex: ImageTexture # the ways people wear (S127), the same window
var _road_tex: ImageTexture
var _region_tex: ImageTexture
var _waiting := false # asked the sim thread for the selected person
var _doing := "" # what the clicked traveller is doing (people_trips.gd pick), or ""
var _legend: Dictionary
var _hud: CanvasLayer
var _legend_label: RichTextLabel
var _person # person_window.gd
var _shown_pid := -1 # the person in its window, for the window's back button
var _back_pending := false # the back button asked for the person shown before
var _press_at := Vector2.INF
var _click_at := Vector2.INF # --people-click, for screenshots
var _frames := 0
var _material := ShaderMaterial.new()
var _prep_material := ShaderMaterial.new()
var _prep_view: SubViewport
var _prep_rect: ColorRect
var _prep_points: MultiMeshInstance2D # up close: a quad per listed figure (people_dots_prep.gdshader listed)
var _prep_listed := false
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
var _house_read_gen := -1 # people.house_gen() when the house placement last ran, read back the next frame
var _house_reads := 0
var _house_limits := PackedInt32Array() # houses each level of detail took in the list
var _figures: MultiMeshInstance3D
var _figure_material := ShaderMaterial.new()
var _figure_shadows: MultiMeshInstance3D # a strip of shade from each figure's feet (people_figure_shadows.gdshader)
var _figure_shadow_material := ShaderMaterial.new()
var _crops: MultiMeshInstance3D
var _trips: MultiMeshInstance3D # carriers and wagons on their way (people_trips.gd)
var _flows: MeshInstance3D # from further up: what went between the markets (people_flows.gd)
var _weather_was := -1 # the clouds before the map was muted (1 on, 0 off), -1 not muted
var _life: MultiMeshInstance3D # smoke, tents, sheaves and animals at the houses (people_house_life.gd)
var _person_looks: Image # each person's household as the sim has it (ApoleiaPeople.people_looks), for the figures
var _today_slot := -1 # the slot of the person asked for, whose day the window shows (day_plan.gd), -1 when asked by id
var _day_hour := -1.0 # the clock's hour at the slow speeds, -1 at the fast ones (set_day_time)
var _day_sun := Vector2(6.0, 18.0)
var _person_looks_tex: ImageTexture
var _person_looks_version := -1
var _person_fields: PackedFloat32Array # where each person's household works its fields (ApoleiaPeople.people_fields), world m
var _person_fields_img: Image
var _person_fields_tex: ImageTexture
var _person_fields_version := -1
var _away: Image # who is away from home today and when (people_trips.gd away), for the figures
var _away_tex: ImageTexture
var _away_version := -1
var _away_px: Array[Vector2i] = [] # the pixels written last, to clear
var _crop_material := ShaderMaterial.new()
var _lots_view: SubViewport # the lots that carry a house, so the crops leave them free, and what the player built
var _lots_dirty := true # the mask is drawn again only when its window, the houses or what the player built changed
var _built_bits := {} # lot -> what the player built there (build_menu.gd _built_bits)
var _built_dirty := false
var _built_image := Image.create_empty(LOTS_N, LOTS_N, false, Image.FORMAT_RGBA8)
var _built_tex := ImageTexture.create_from_image(_built_image)
var _lot0 := Vector2.INF
var _parcel_view: SubViewport # each parcel of the crop square worked out once (people_parcels.gdshader)
var _parcel_material := ShaderMaterial.new()
var _parcel_frames := 0
var _crop_box := Vector4.INF
var _crop_cell0 := Vector2.INF
var _ground_key := []
var _ground := Rect2()
var _lots: MultiMeshInstance2D
var _lots_material := ShaderMaterial.new()
var _list_image := Image.create_empty(LIST_W, FIGURE_MAX / LIST_W, false, Image.FORMAT_RF)
## the way of each figure to its household's field over the worn network
## (walk_route.gd field_route, people_field_route.gdshaderinc), one row of
## ROUTE_W texels per figure of the list: (count, km), then the points
## (world km); anew with the list, the fields and the ways
var _route_image := Image.create_empty(ROUTE_W, FIGURE_MAX, false, Image.FORMAT_RGF)
var _route_tex: ImageTexture
var _route_km := {} # slot -> the length of its field way from the village (for «Heute»)
var _figure_slots := PackedInt32Array() # the slots of the figure list
var _routes_dirty := false
var _route_rows := {} # slot -> its row (count, km, points; ROUTE_W * 2 floats) or the empty one, until the fields or the ways change
var _no_route := PackedFloat32Array() # the row of a figure without a field way (ROUTE_W * 2 zeros)
var _list_tex: ImageTexture
var _list_at := Vector3.INF # centre x, z and radius of the current list
var prep_runs := 0
var process_usec := 0 # this frame's work of the people on the main thread (people_cost.gd)
var trips_usec := 0 # of it the walkers' (people_trips.gd step)
var _texture: Texture2DArray
var _shared_uniforms: Array[StringName] = []
var _shared_values := {} # what each shared uniform was last copied as
var _shared_count := 0 # materials it was copied into
var _day_debt := 0.0
## The sim day and the share of the real time to the next one the clock has
## run (day_clock.gd: the hour at the slow speeds); never runs back while
## the next day is being computed.
var clock_day := 0.0
var _bench_path := ""
var _bench_frame := 0
var _bench_last := 0
var _bench := {"on": [], "off": [], "on_gpu": [], "off_gpu": [], "sync_usec": [], "sync_layers": [], "prep": [], "process_on": [], "process_off": []}
var _bench_prep_last := 0
var _cost_path := ""
var _cost_frames := 12

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
			"--people-cost": _cost_path = value if value.is_absolute_path() else TileTerrain.data_root().path_join(value)
			"--people-cost-frames": _cost_frames = int(value)
	people = ClassDB.instantiate("ApoleiaPeople")
	var started := Time.get_ticks_usec()
	if not people.load(TileTerrain.data_root(), 1):
		return false
	print(JSON.stringify({"event": "people_loaded", "people": people.count(), "ms": (Time.get_ticks_usec() - started) / 1000.0}))
	# farms being built as house records of their own (village code negated,
	# rec.w the built share): people_houses.gdshader draws them half built
	if people.has_method("show_site_houses"):
		people.show_site_houses(true)
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
	_prep_points = MultiMeshInstance2D.new()
	_prep_points.material = _prep_material
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_2D
	var unit := QuadMesh.new()
	unit.size = Vector2.ONE
	pm.mesh = unit
	pm.instance_count = FIGURE_MAX
	pm.visible_instance_count = 0
	_prep_points.multimesh = pm
	_prep_points.visible = false
	_prep_view.add_child(_prep_points)
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
			mm.mesh = _indexed(lods[lod])
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
	_route_tex = ImageTexture.create_from_image(_route_image)
	_figure_material.set_shader_parameter("field_route_tex", _route_tex)
	_prep_material.set_shader_parameter("list_tex", _list_tex)
	_prep_material.set_shader_parameter("list_w", LIST_W)
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
	for key in ["figure_scale", "list_w", "list_tex", "field_route_tex"]:
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
	cm.visible_instance_count = 0
	_crops.multimesh = cm
	_crops.visible = false
	add_child(_crops)
	_trips = PeopleTrips.new()
	_trips.setup(people, TileTerrain.DIORAMA_KM_PER_M)
	_trips.route.plans = terrain.plans # the town streets the travellers walk (walk_route.gd)
	add_child(_trips)
	_life = HouseLife.new()
	_life.setup(TileTerrain.DIORAMA_KM_PER_M, _house_list_tex, LIST_W) # the house mesh's metres
	add_child(_life)
	_flows = PeopleFlows.new()
	_flows.setup(people, terrain)
	get_parent().add_child.call_deferred(_flows) # beside the people: drawn where they are not
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
	# what the player built, copied into the mask as it is, under the houses
	var built := Sprite2D.new()
	built.centered = false
	built.texture = _built_tex
	built.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var copy := ShaderMaterial.new()
	copy.shader = Shader.new()
	copy.shader.code = BUILT_COPY
	built.material = copy
	_lots_view.add_child(built)
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
	# after the lots, whose mask it reads in the same frame (sibling viewports draw in order)
	_parcel_material.shader = PARCELS_SHADER
	var parcel_rect := ColorRect.new()
	parcel_rect.size = Vector2(CROP_N, CROP_N)
	_parcel_view = _make_prep("CropParcels", parcel_rect, _parcel_material)
	_parcel_view.size = Vector2i(CROP_N, CROP_N)
	# the tree slots too: no tree on a farmhouse's lot or a field (tile_props.gdshaderinc)
	for m: ShaderMaterial in [terrain._terrain_material, _crop_material, _prep_material, _parcel_material, terrain._place_material]:
		m.set_shader_parameter("sim_lot_tex", _lots_view.get_texture())
		m.set_shader_parameter("sim_lots_n", LOTS_N)
		m.set_shader_parameter("sim_lot_km", LOT_KM)
		m.set_shader_parameter("sim_parcel_n", CROP_N)
	for m: ShaderMaterial in [terrain._terrain_material, _crop_material]:
		m.set_shader_parameter("sim_parcel_tex", _parcel_view.get_texture())
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
	events.answered.connect(_trips.take_events) # the newest events as scenes on the way
	events.person_chosen.connect(_show_household) # a person named in an event window
	_rebuild()
	_rebuild_houses()
	if _cost_path != "":
		var cost := PeopleCost.new() # last child: hides its part after the others ran
		cost.setup(self, _cost_path, _cost_frames)
		add_child(cost)
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
	for m in _house_materials + [_house_prep_material, _lots_material, _life.material]:
		m.set_shader_parameter("people_tex", _house_texture)
		m.set_shader_parameter("page_side", side)
	for m in _house_materials + [_lots_material, _life.material]:
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

## The mesh with shared corners: each shaded once, not once per triangle.
static func _indexed(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count() != 1 or mesh.surface_get_array_index_len(0) > 0:
		return mesh
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.index()
	return st.commit()

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
	st.index() # each corner shaded once, not once per triangle
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
	st.index() # each corner shaded once, not once per triangle
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
## place across the parcel, UV.y their number) and CROP_LUMPS lumps on each
## (UV.y the row's number + 16 * (lump + 1), round O), the fence (UV.x = -2,
## UV.y side * 16 + post, 15 the rail), the hedge (UV.x = -4, UV.y side *
## 16 + block) and a flock for the pasture (UV.x = -3, UV.y sheep * 4 +
## body, legs or head), each a unit box (x, z
## -0.5..0.5, y 0..1, no bottom); people_crops.gdshader sizes and places
## them by crop and season. Flat faces: the sides a step darker in the vertex alpha.
static func _crop_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts: Array[Vector2] = [Vector2(-1.0, 0.0)]
	for i in CROP_ROWS:
		parts.append(Vector2((i + 0.5) / CROP_ROWS, i))
		for k in CROP_LUMPS:
			parts.append(Vector2((i + 0.5) / CROP_ROWS, i + 16 * (k + 1)))
	for side in 4:
		for k: int in range(FENCE_POSTS) + [15]:
			parts.append(Vector2(-2.0, side * 16 + k))
		for k in HEDGE_BLOCKS:
			parts.append(Vector2(-4.0, side * 16 + k))
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
	st.index() # each corner shaded once, not once per triangle
	return st.commit()

## The grain layers on the terrain material: the road map when a month is
## built, the fine window when the month changes or the camera leaves its
## middle half.
func _update_map() -> void:
	var mat: ShaderMaterial = terrain._terrain_material
	# the crops read the fine layer too, and the placement of the people for
	# the slabs they stand on
	# (the house places too: the houses keep off the ways, people_dots_common.gdshaderinc dot_lot_way_free)
	var mats: Array[ShaderMaterial] = [mat, _crop_material, _prep_material, _parcel_material, terrain._place_material, _house_prep_material]
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
		if win.has("ways"):
			if _way_tex == null:
				_way_tex = ImageTexture.create_from_image(win.ways)
			else:
				_way_tex.update(win.ways)
			# the travellers walk these ways and the town streets (walk_route.gd)
			_trips.route.set_ways(win.ways, win.origin, win.tile_km)
			_routes_dirty = true
			_route_rows.clear()
			_route_km.clear()
			_trips.route.plans = terrain.plans
		for m in mats:
			m.set_shader_parameter("sim_fine_tex", _map_tex)
			m.set_shader_parameter("sim_way_tex", _way_tex)
			m.set_shader_parameter("sim_fine_origin", win.origin)
			m.set_shader_parameter("sim_fine_km", win.tile_km)
			m.set_shader_parameter("sim_fine_n", MAP_N)
		_prep_frames = 2
		_house_prep_frames = 2
		_parcel_frames = 2
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

## The map greyed under a view of lines (ui/map_modes.gd «Handel»), the
## clouds away over it and back as they were after it.
func mute_map(on: bool) -> void:
	terrain._terrain_material.set_shader_parameter("sim_mute", 1.0 if on else 0.0)
	var weather: Node = get_parent().get("weather")
	if weather == null or not weather.has_method("set_enabled"):
		return
	if on and _weather_was < 0:
		_weather_was = 1 if weather.enabled else 0
		weather.set_enabled(false)
	elif not on and _weather_was >= 0:
		weather.set_enabled(_weather_was == 1)
		_weather_was = -1

## What went between the markets (the map mode «Handel» draws it).
func flows() -> MeshInstance3D:
	return _flows

## The people in view, as a slot list for the figure shader: those in the
## circle round the ground in view, nearest its middle first.
func _update_figures(view_km: float, synced: bool) -> void:
	var circle := _view_circle()
	if not synced and _still_listed(_list_at, circle):
		return
	_list_at = Vector3(circle.x, circle.y, circle.z * 1.15) # a little more, so the next small moves need no new list
	var centre := Vector2(_list_at.x, _list_at.y)
	var radius := _list_at.z
	var slots: PackedInt32Array = people.near(centre.x, centre.y, radius, FIGURE_MAX)
	if slots == _figure_slots:
		return # the same figures: no upload, and their field ways stand
	var values := PackedFloat32Array()
	values.resize(FIGURE_MAX)
	for i in slots.size():
		values[i] = float(slots[i])
	_list_image.set_data(LIST_W, FIGURE_MAX / LIST_W, false, Image.FORMAT_RF, values.to_byte_array())
	_list_tex.update(_list_image)
	_figures.multimesh.visible_instance_count = slots.size()
	_figure_slots = slots
	_routes_dirty = true
	_figure_shadows.multimesh.visible_instance_count = slots.size()
	_prep_points.multimesh.visible_instance_count = slots.size()
	_prep_frames = 2 # place the newly listed

## The square of parcels whose crops stand, round the ground in view; only
## up close and on the finest terrain tiles (the parcel is half a tile).
## Each parcel is worked out once (people_parcels.gdshader) when the square,
## the fields, the lots or the relief change; the crops are drawn only on the
## parcels in view, not on the whole square (Mac tour, 29.10.2026: the
## square's 1600 parcels, each working itself out for every vertex, were
## the dearest part of a frame up close).
func _update_crops(view_km: float) -> void:
	var tile_km: float = terrain._terrain_material.get_shader_parameter("tile_km")
	_crops.visible = map_on and view_km <= CROP_KM and tile_km <= 0.5
	if not _crops.visible:
		if _crop_box != Vector4.ZERO:
			_crop_box = Vector4.ZERO
			for m: ShaderMaterial in [terrain._terrain_material, _prep_material, _crop_material]:
				m.set_shader_parameter("sim_crop_box", _crop_box)
		_crop_cell0 = Vector2.INF
		# the fields the player built still lie on the terrain further out
		var landscape := get_parent()
		if map_on and view_km <= FIELDS_KM and "target" in landscape:
			var reach := Vector2.ONE * view_km * 0.6
			_place_lot_mask(landscape.target - reach, landscape.target + reach)
		return
	# a parcel is half a data tile: up close one quarter tile (sub_tiles);
	# parcels and lots on the terrain's tile grid, counted from world_min
	var size := tile_km * (1.0 if terrain.sub_tiles else 0.5)
	var world_min: Vector2 = terrain.world_min
	# the parcels in view and one more round them for their shadows
	var ground := _ground_rect()
	var lo := ((ground.position - world_min) / size).floor() - Vector2.ONE
	var hi := ((ground.end - world_min) / size).floor() + Vector2.ONE
	# the square stays put while the parcels in view lie in it, so panning
	# does not work out the parcels and place the people again at every step
	var last := Vector2(CROP_N - 1, CROP_N - 1)
	var cell0 := _crop_cell0
	if cell0 == Vector2.INF or lo.x < cell0.x or lo.y < cell0.y or hi.x > cell0.x + last.x or hi.y > cell0.y + last.y:
		cell0 = ((lo + hi) * 0.5).floor() - Vector2(CROP_N / 2, CROP_N / 2)
	_crop_cell0 = cell0
	lo = lo.clamp(cell0, cell0 + last)
	hi = hi.clamp(cell0, cell0 + last)
	var n := Vector2i(hi - lo) + Vector2i.ONE
	_crop_material.set_shader_parameter("crop_cell0", lo)
	_crop_material.set_shader_parameter("crop_nx", n.x)
	_crops.multimesh.visible_instance_count = n.x * n.y
	# where the crops stand the ground round their slabs is dirt (sim_map.gdshaderinc)
	var box_min: Vector2 = world_min + cell0 * size
	var box_max := box_min + Vector2(CROP_N, CROP_N) * size
	var box := Vector4(box_min.x, box_min.y, box_max.x, box_max.y)
	if box != _crop_box:
		_crop_box = box
		_prep_frames = 2 # the people on the slabs
		_parcel_frames = 2
		for m: ShaderMaterial in [terrain._terrain_material, _prep_material, _crop_material]:
			m.set_shader_parameter("sim_crop_box", box)
		_parcel_material.set_shader_parameter("parcel_cell0", cell0)
	_place_lot_mask(box_min, box_max)
	if _parcel_frames > 0:
		_parcel_frames -= 1
		_parcel_view.render_target_update_mode = SubViewport.UPDATE_ONCE

## The lot mask (people_lots.gdshader, the houses; _draw_built, what the
## player built) round the world rectangle lo..hi (km), moved only when the
## rectangle nears its edge, drawn again when it moved or changed.
func _place_lot_mask(lo: Vector2, hi: Vector2) -> void:
	var world_min: Vector2 = terrain.world_min
	var lots := Vector2(LOTS_N, LOTS_N)
	var lot_lo := (lo - world_min) / LOT_KM
	var lot_hi := (hi - world_min) / LOT_KM
	if _lot0 == Vector2.INF or lot_lo.x < _lot0.x + 1.0 or lot_lo.y < _lot0.y + 1.0 or lot_hi.x > _lot0.x + lots.x - 1.0 or lot_hi.y > _lot0.y + lots.y - 1.0:
		_lot0 = ((lot_lo + lot_hi) * 0.5).floor() - lots * 0.5
		_lots_material.set_shader_parameter("lot_origin", _lot0)
		_lots_material.set_shader_parameter("world_min", world_min)
		for m: ShaderMaterial in [terrain._terrain_material, _crop_material, _prep_material, _parcel_material, terrain._place_material]:
			m.set_shader_parameter("sim_lot_origin", _lot0)
		_built_dirty = true
	if _built_dirty:
		_built_dirty = false
		_draw_built()
		_lots_dirty = true
	if _lots_dirty:
		_lots_dirty = false
		_lots_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		_parcel_frames = 2

## What the player built (build_menu.gd _built_bits: lot -> bits), for the
## fields, the crops and the trees (sim_fields.gdshaderinc sim_built).
func set_built(bits: Dictionary) -> void:
	_built_bits = bits
	_built_dirty = true

## The lots of the mask's window with what the player built there, in R, G
## and B (alpha 0: no farmhouse).
func _draw_built() -> void:
	var bytes := PackedByteArray()
	bytes.resize(LOTS_N * LOTS_N * 4)
	var o := Vector2i(_lot0)
	for l: Vector2i in _built_bits:
		var p := l - o
		if p.x < 0 or p.y < 0 or p.x >= LOTS_N or p.y >= LOTS_N:
			continue
		var v: int = _built_bits[l]
		var i := (p.y * LOTS_N + p.x) * 4
		bytes[i] = v & 255
		bytes[i + 1] = (v >> 8) & 255
		bytes[i + 2] = (v >> 16) & 255
	_built_image.set_data(LOTS_N, LOTS_N, false, Image.FORMAT_RGBA8, bytes)
	_built_tex.update(_built_image)

## The ground in view (world km, x and z): the screen's corner rays down to
## the lowest and the highest ground under them, worked out again only when
## the camera moves.
func _ground_rect() -> Rect2:
	var landscape := get_parent()
	var camera: Camera3D = landscape.camera
	var size := get_viewport().get_visible_rect().size
	var key := [camera.global_transform, camera.fov, size]
	if key == _ground_key:
		return _ground
	_ground_key = key
	var focus: float = landscape._focus_y
	var target: Vector2 = landscape.target
	var reach := camera.global_position.distance_to(Vector3(target.x, focus, target.y)) * 3.0
	var rect := _corner_rect(camera, size, focus, focus, reach)
	var low := focus
	var high := focus
	for j in 5:
		for i in 5:
			var y: float = terrain.ground_y(rect.position + rect.size * Vector2(i, j) * 0.25)
			low = minf(low, y)
			high = maxf(high, y)
	var level: float = terrain.level_h
	_ground = _corner_rect(camera, size, low - level, high + level, reach)
	return _ground

static func _corner_rect(camera: Camera3D, size: Vector2, low: float, high: float, reach: float) -> Rect2:
	var a := Vector2(INF, INF)
	var b := -a
	for corner in [Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]:
		var origin := camera.project_ray_origin(corner)
		var ray := camera.project_ray_normal(corner)
		for y in [low, high]:
			var t := reach
			if ray.y < -0.001:
				t = clampf((y - origin.y) / ray.y, 0.0, reach)
			var p := origin + ray * t
			a = a.min(Vector2(p.x, p.z))
			b = b.max(Vector2(p.x, p.z))
	return Rect2(a, b - a)

## The circle round the ground in view (centre x, z and radius, km).
func _view_circle() -> Vector3:
	var ground := _ground_rect()
	var c := ground.get_center()
	return Vector3(c.x, c.y, ground.size.length() * 0.5)

## Whether the list made for the circle `listed` still holds the circle
## `need` and not much more.
static func _still_listed(listed: Vector3, need: Vector3) -> bool:
	var off := Vector2(listed.x, listed.y).distance_to(Vector2(need.x, need.y))
	return listed != Vector3.INF and off + need.z <= listed.z and listed.z < need.z * 1.6

## The houses near the camera, nearest first, split over the levels of
## detail: the nearest in the finest one the view width allows.
func _update_houses(view_km: float, synced: bool) -> void:
	var levels := HOUSE_LOD_MAX.size()
	var limits := PackedInt32Array()
	for lod in levels:
		limits.append(HOUSE_LOD_MAX[lod] if view_km <= HOUSE_LOD_KM[lod] else 0)
	var circle := _view_circle()
	if not synced and limits == _house_limits and _still_listed(_house_list_at, circle):
		return
	_house_limits = limits
	_house_list_at = Vector3(circle.x, circle.y, circle.z * 1.15)
	var centre := Vector2(_house_list_at.x, _house_list_at.y)
	var radius := _house_list_at.z
	# each build's MultiMesh gets the run of its own houses in each level,
	# once their builds are known (people.set_house_places); else every
	# build draws the whole level and its shader leaves out the others
	var slots: PackedInt32Array
	var blocks := PackedInt32Array()
	if people.has_method("houses_split"):
		var split: Dictionary = people.houses_split(centre.x, centre.y, radius, HOUSE_MAX, limits)
		slots = split.slots
		blocks = split.blocks
	else:
		slots = people.houses_near(centre.x, centre.y, radius, HOUSE_MAX)
		var start := 0
		for lod in levels:
			var n := mini(slots.size() - start, limits[lod])
			for variant in Farmhouse.VARIANTS:
				blocks.append_array([start, n])
			start += n
	var values := PackedFloat32Array()
	values.resize(HOUSE_MAX)
	for i in slots.size():
		values[i] = float(slots[i])
	_house_list_image.set_data(LIST_W, HOUSE_MAX / LIST_W, false, Image.FORMAT_RF, values.to_byte_array())
	_house_list_tex.update(_house_list_image)
	_lots_dirty = true
	for lod in levels:
		for variant in Farmhouse.VARIANTS:
			var i := variant * levels + lod
			var b := (lod * Farmhouse.VARIANTS + variant) * 2
			_house_materials[i].set_shader_parameter("list_offset", blocks[b])
			_houses[i].multimesh.visible_instance_count = blocks[b + 1]
			_houses[i].visible = blocks[b + 1] > 0 # an empty one still costs a draw in each pass
	_lots.multimesh.visible_instance_count = slots.size()
	_life.show_houses(slots.size(), view_km)

## Reads the house placement pass back from the GPU without waiting for it
## (RenderingDevice.texture_get_data_async), so each house's build is known
## on the CPU (people.set_house_places) and each build's MultiMesh draws
## only its own houses (a quarter of the vertices).
func _read_house_places(gen: int) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	var rid := RenderingServer.texture_get_rd_texture(_house_prep_view.get_texture().get_rid())
	if rid.is_valid():
		rd.texture_get_data_async(rid, 0, _on_house_places.bind(gen))

## `gen` is people.house_gen() when the pass ran: houses changed since stay
## unknown until a later pass is read.
func _on_house_places(data: PackedByteArray, gen: int) -> void:
	if people == null:
		return
	var changed: int = people.set_house_places(data, _house_prep_view.size.x, terrain.world_min, LOT_KM, gen)
	if changed > 0:
		_house_list_at = Vector3.INF # cut the list by the builds now known
	if _house_reads == 0:
		print(JSON.stringify({"event": "house_builds", "bytes": data.size(), "changed": changed}))
	_house_reads += 1

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
	_legend_label.offset_top += 56 # below the top bar (ui/top_bar.gd)
	_legend_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# the person clicked, in a window (person_window.gd) at the bottom left
	_person = PersonWindow.new(Engine.get_main_loop() as SceneTree)
	_person._win.closed.connect(func(): _shown_pid = -1)
	add_to_group("person_window") # call_group("person_window", "open_person", pid)
	_person.member_chosen.connect(func(pid: int): _show_household(pid, -1))

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

## Each person's household as the sim has it (fed, its farm at the harvest
## or sowing, its workshop), anew when the sim rebuilt it once a sim week or
## the people texture grew: the figures draw the hungry thin and send the
## grown-ups of a farm at work out on its fields (people_figures.gdshader),
## and the placement puts those of a workshop at it (people_dots_prep).
func _sync_person_looks() -> void:
	if not people.has_method("people_looks") or _texture == null:
		return
	var version: int = people.house_looks_version()
	var side: int = people.page_side()
	var h := side * maxi(_texture.get_layers(), 1)
	if version == _person_looks_version and _person_looks != null and _person_looks.get_height() == h:
		return
	_person_looks_version = version
	var bytes: PackedByteArray = people.people_looks()
	bytes.resize(side * h * 2) # people newer than the looks: nothing yet
	if _person_looks == null or _person_looks.get_height() != h:
		_person_looks = Image.create_from_data(side, h, false, Image.FORMAT_RG8, bytes)
		_person_looks_tex = ImageTexture.create_from_image(_person_looks)
		for m in [_figure_material, _figure_shadow_material, _prep_material]:
			m.set_shader_parameter("person_look_tex", _person_looks_tex)
			m.set_shader_parameter("has_person_looks", true)
	else:
		_person_looks.set_data(side, h, false, Image.FORMAT_RG8, bytes)
		_person_looks_tex.update(_person_looks)
	_prep_frames = 2 # a household took up or left a workshop

## Where each person's household works its fields (Bauplan B step 4),
## as the RGF texture of people_dots_common dot_field_way, anew with the
## household looks: the farmers walk out to that field at the diorama pace
## (people_day.gdshaderinc «Feld»). Without `people_fields` (an extension
## built before it) they keep the old spot beside the house.
func _sync_person_fields() -> void:
	if not people.has_method("people_fields") or _texture == null:
		return
	var version: int = people.house_looks_version()
	var side: int = people.page_side()
	var h := side * maxi(_texture.get_layers(), 1)
	if version == _person_fields_version and _person_fields_img != null and _person_fields_img.get_height() == h:
		return
	_person_fields_version = version
	_person_fields = people.people_fields()
	var floats := _person_fields.slice(0, side * h * 2)
	var tail := PackedFloat32Array()
	tail.resize(side * h * 2 - floats.size())
	tail.fill(-1.0) # people newer than the list: no field yet
	floats.append_array(tail)
	var bytes := floats.to_byte_array()
	if _person_fields_img == null or _person_fields_img.get_height() != h:
		_person_fields_img = Image.create_from_data(side, h, false, Image.FORMAT_RGF, bytes)
		_person_fields_tex = ImageTexture.create_from_image(_person_fields_img)
		for m in [_figure_material, _figure_shadow_material]:
			m.set_shader_parameter("person_field_tex", _person_fields_tex)
			m.set_shader_parameter("has_person_fields", true)
	else:
		_person_fields_img.set_data(side, h, false, Image.FORMAT_RGF, bytes)
		_person_fields_tex.update(_person_fields_img)
	_routes_dirty = true
	_route_rows.clear()
	_route_km.clear()

## The field ways of the figure list (ROUTE_W), when the list, the fields
## or the ways changed: for each figure whose household's field the sim
## tells, the way from its village over the worn network to the field
## (walk_route.gd field_route); the shader adds the part from the figure's
## spot round its house to the lanes and the last step into the field.
## Ways are kept per pair of tiles, so a list costs a few searches. The
## rows are kept at their full width and joined whole (a loop over every
## float of 16 384 figures took tens of ms on each new list); new ways get
## ROUTE_BUDGET_USEC a frame, so a new map window (all ways anew) does not
## stall one frame: the figures still without a way get it the next.
func _update_field_routes() -> void:
	if not _routes_dirty or _route_tex == null:
		return
	var start := Time.get_ticks_usec()
	var stride := ROUTE_W * 2
	if _no_route.size() != stride:
		_no_route.resize(stride)
		_no_route.fill(0.0)
	var floats := PackedFloat32Array()
	var lot_min: Vector2 = terrain.world_min
	var done := true
	for i in _figure_slots.size():
		var slot := _figure_slots[i]
		var row: PackedFloat32Array = _route_rows.get(slot, _no_route)
		if not _route_rows.has(slot):
			if Time.get_ticks_usec() - start < ROUTE_BUDGET_USEC:
				if _route_rows.size() > 60000:
					_route_rows.clear()
					_route_km.clear()
				row = _full_row(_field_route_row(slot, lot_min), stride)
				_route_rows[slot] = row
			else:
				done = false
		floats.append_array(row)
	_routes_dirty = not done
	floats.resize(stride * FIGURE_MAX) # past the list: never read
	_route_image.set_data(ROUTE_W, FIGURE_MAX, false, Image.FORMAT_RGF, floats.to_byte_array())
	_route_tex.update(_route_image)

## Who is away from home today and from when till when (people_trips.gd
## `away`, at «Alltag»), as the RGBA8 texture of people_dots_common
## dot_person_away, anew when the list changed: the figure at home is gone
## while it walks as a carrier or hired hand (people_day.gdshaderinc).
func _sync_away() -> void:
	if _texture == null or _trips.away_version == _away_version:
		return
	_away_version = _trips.away_version
	var side: int = people.page_side()
	var h := side * maxi(_texture.get_layers(), 1)
	var fresh := _away == null or _away.get_height() != h
	if fresh:
		_away = Image.create_empty(side, h, false, Image.FORMAT_RGBA8)
	else:
		for px in _away_px:
			_away.set_pixelv(px, Color(0, 0, 0, 0))
	_away_px.clear()
	var per := side * side
	for slot: int in _trips.away:
		var e: Dictionary = _trips.away[slot]
		var px := Vector2i((slot % per) % side, (slot / per) * side + (slot % per) / side)
		if px.y >= h:
			continue
		var a := clampi(int(round(float(e.leave) * 2048.0)), 0, 65535)
		var b := clampi(int(round(float(e.back) * 2048.0)), 0, 65535)
		_away.set_pixelv(px, Color8(a >> 8, a & 255, b >> 8, b & 255))
		_away_px.append(px)
	if fresh:
		_away_tex = ImageTexture.create_from_image(_away)
		for m in [_figure_material, _figure_shadow_material]:
			m.set_shader_parameter("person_away_tex", _away_tex)
	else:
		_away_tex.update(_away)
	for m in [_figure_material, _figure_shadow_material]:
		m.set_shader_parameter("has_person_away", not _away_px.is_empty())

## Palette entries as linear colour, as source_color uniforms arrive.
static func _linear(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)

## The person `pid` in their window, from anywhere (the outliner, a
## right-click menu: the group "person_window").
func open_person(pid: int) -> void:
	_show_household(pid, -1)

## Opens the person's window for a person by id, else a member of a
## household (an event window's people, sim_events.gd).
func _show_household(pid: int, household: int) -> void:
	_doing = ""
	_today_slot = -1
	if pid >= 0:
		people.ask_person_id(pid)
	elif household >= 0:
		people.ask_household_member(household)
	else:
		return
	_waiting = true
	_show_info(true)
	_person.wait()

## The person under `pixel`: a traveller on its way (people_trips.gd),
## else the nearest dot or figure, for which it reads the placement
## texture back (only on a click) and lets ApoleiaPeople find it on screen.
func _pick(pixel: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not visible:
		return
	# travellers walk over the people at home, so they come first
	var traveller: Dictionary = _trips.pick(cam, pixel, terrain.ground_y, FIGURE_M * TileTerrain.DIORAMA_KM_PER_M * 0.5, PICK_PX)
	if not traveller.is_empty():
		selected = -1
		for mat in [_material, _figure_material]:
			mat.set_shader_parameter("selected_slot", -1)
		print(JSON.stringify({"event": "people_pick", "pixel": [pixel.x, pixel.y], "pid": traveller.pid, "household": traveller.household}))
		_doing = traveller.what
		_show_info(true)
		if int(traveller.pid) < 0 and int(traveller.household) < 0:
			# a scene with nobody to look up (a funeral): only what happens
			_waiting = false
			_person.note("[color=#c9a45c]%s[/color]" % _doing)
			return
		_today_slot = int(traveller.get("slot", -1)) # looked up at «Alltag» (people_trips.gd ask_slots)
		if int(traveller.pid) >= 0:
			people.ask_person_id(traveller.pid)
		else:
			people.ask_household_member(traveller.household)
		_waiting = true
		_person.wait()
		return
	_doing = ""
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
	_show_info(_waiting)
	if _waiting:
		people.ask_person(selected)
		_today_slot = selected
		_person.wait()

## Opens or closes the person's window.
func _show_info(on: bool) -> void:
	if on:
		_person.open()
	else:
		_person.close()

## The person in its window. The one shown before stays one step back
## (the window's ←); the line under the title names their market, its →
## opens the market's window; a right click on the band gives the menu
## (their farm, their market, the outliner).
func _show_person(p: Dictionary) -> void:
	var win = _person._win
	if p.is_empty():
		win.set_subtitle("")
		win.context = Callable()
	else:
		var pid := int(p.pid)
		if _shown_pid >= 0 and pid != _shown_pid and not _back_pending:
			var before := _shown_pid
			win.remember(func():
				_back_pending = true
				_show_household(before, -1))
		_back_pending = false
		_shown_pid = pid
		var m := int(p.get("market", -1))
		win.set_subtitle("Am Markt %s" % p.market_name if m >= 0 else "",
			func(): get_tree().call_group("market_window", "open", m), "Den Markt öffnen")
		var who: String = p.get("name", p.job)
		var market_name: String = p.get("market_name", "")
		var farm := int(p.get("farm", -1))
		win.context = func() -> Dictionary:
			var entries := ContextMenu.entries(get_tree(), "person", pid, who, Callable(), true)
			if farm >= 0:
				entries.push_front({"text": "Hof öffnen", "icon": "field", "action": func(): get_tree().call_group("farm_window", "open", farm)})
			if m >= 0:
				entries.push_front({"text": "Markt %s öffnen" % market_name, "icon": "open-book",
					"action": func(): get_tree().call_group("market_window", "open", m)})
			return {"title": who, "kind": "Person", "entries": entries}
	if _today_slot >= 0 and not p.is_empty():
		var today := _today_of(_today_slot)
		if not today.is_empty():
			p.today = today
			p.today_hour = _day_hour
	_person.show_person(p, _doing)
	if not p.is_empty():
		print(JSON.stringify({"event": "people_person", "pid": p.pid}))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_at = event.position
		elif _press_at.distance_to(event.position) <= CLICK_PX:
			_pick(event.position)
	if event is InputEventKey and Keys.pressed(event, "apoleia_people"):
		shown = not shown
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				colour_mode = (colour_mode + 1) % MODES.size()
				_apply_colours()
			KEY_ESCAPE:
				if selected >= 0 or _person.is_open(): # the next Esc is the menu's
					get_viewport().set_input_as_handled()
				selected = -1
				_waiting = false
				for m in [_material, _figure_material]:
					m.set_shader_parameter("selected_slot", -1)
				_show_info(false)
			KEY_G:
				map_on = not map_on
				_map_version = -1

## The hour from the game clock at the slow speeds (day_clock.gd), -1 at
## the fast ones: the travellers walk at their real pace when a day lasts
## `day_s` real seconds (0: at a pace for the eye), stand while `frozen`
## (the game paused), the houses light their lamps and the figures keep
## their day (people_day.gdshaderinc).
func set_day_time(hour: float, sun: Vector2, day_s: float, frozen: bool) -> void:
	if _trips != null:
		_trips.set_day_time(hour, sun, day_s, frozen)
	if _life != null:
		_life.set_lamps(hour, sun)
	for m in [_figure_material, _figure_shadow_material]:
		m.set_shader_parameter("day_hour", hour)
		m.set_shader_parameter("day_sun", sun)
	_day_hour = hour
	if hour >= 0.0:
		_day_sun = sun
	if _person != null and _person.is_open():
		_person.today_now(hour)

## The day of the person in `slot` as its figure lives it (day_plan.gd),
## from its record (ApoleiaPeople.record), its household's flags and, at
## «Alltag», where it walks today (people_trips.gd away); [] for an empty
## slot or an extension built before `record`.
func _today_of(slot: int) -> Array:
	if slot < 0 or not people.has_method("record"):
		return []
	var rec: PackedFloat32Array = people.record(slot)
	if rec.size() < 4 or rec[2] == 0.0:
		return []
	var w := int(rec[3])
	var side: int = people.page_side()
	var per := side * side
	var layer := slot / per
	var x := (slot % per) % side
	var y := (slot % per) / side
	var flags := 0
	if _person_looks != null and layer * side + y < _person_looks.get_height():
		var g := int(_person_looks.get_pixel(x, layer * side + y).g * 255.0 + 0.5)
		flags = g if g & 128 else 0
	var sun := _day_sun
	if _day_hour < 0.0:
		var land := get_parent()
		sun = DayClock.daylight(int(people.day()), DayClock.latitude(land.target) if "target" in land else 41.9)
	# the walk to its field (dot_field_way): from the record's anchor, as
	# the house spot itself is placed on the GPU (a village tile off at most)
	var walk_h := -1.0
	if slot * 2 + 1 < _person_fields.size() and (_person_fields[slot * 2] != -1.0 or _person_fields[slot * 2 + 1] != -1.0):
		var field := Vector2(_person_fields[slot * 2], _person_fields[slot * 2 + 1]) * 0.001
		# over the worn network (_update_field_routes), as the figure walks it
		var km: float = _route_km.get(slot, field.distance_to(Vector2(rec[0], rec[1])))
		walk_h = maxf(km / DayPlan.FIELD_KMH, 1.0 / 60.0)
	return DayPlan.day(slot, (w >> 8) & 0x3fff, w & 3, (w >> 4) & 15, (w >> 22) & 1 == 1, (w >> 23) & 1 == 1, flags, sun, _trips.away.get(slot, {}), walk_h)

## The field way row of `slot` (_update_field_routes), empty without one;
## its whole length from the village for «Heute» into _route_km.
func _field_route_row(slot: int, lot_min: Vector2) -> PackedFloat32Array:
	if slot * 2 + 1 >= _person_fields.size() or (_person_fields[slot * 2] == -1.0 and _person_fields[slot * 2 + 1] == -1.0):
		return PackedFloat32Array()
	var rec: PackedFloat32Array = people.record(slot)
	if rec.size() < 4 or rec[2] <= 0.0 or (rec[2] >= ROAD_CODE and rec[2] < AT_LOT_CODE):
		return PackedFloat32Array() # a city or the road: no house on a lot
	var field := Vector2(_person_fields[slot * 2], _person_fields[slot * 2 + 1]) * 0.001
	var pts: PackedVector2Array = _trips.route.field_route(Vector2(rec[0], rec[1]), field, lot_min, LOT_KM, ROUTE_W - 1)
	var km := 0.0
	for k in range(1, pts.size()):
		km += pts[k].distance_to(pts[k - 1])
	var row := PackedFloat32Array([float(pts.size()), km])
	for p in pts:
		row.append(p.x)
		row.append(p.y)
	_route_km[slot] = km + Vector2(rec[0], rec[1]).distance_to(pts[0]) + pts[pts.size() - 1].distance_to(field)
	return row

## `row` (_field_route_row) at `stride` floats, zeros after it; the empty
## row for none.
func _full_row(row: PackedFloat32Array, stride: int) -> PackedFloat32Array:
	if row.is_empty():
		return _no_route
	var n := row.size()
	row.resize(stride)
	for k in range(n, stride):
		row[k] = 0.0
	return row

## A save game was loaded (game_clock.gd): a new sim thread, new people.
## Forget the person shown and the map layers; the textures follow on the
## next sync.
func restarted() -> void:
	selected = -1
	_waiting = false
	for m in [_material, _figure_material]:
		m.set_shader_parameter("selected_slot", -1)
	_show_info(false)
	_map_version = -1
	_day_debt = 0.0
	clock_day = 0.0

func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_frame(delta)
	process_usec = Time.get_ticks_usec() - start

func _frame(delta: float) -> void:
	if people == null or people.is_loading():
		return
	_day_debt += days_per_second * delta
	var whole := int(_day_debt)
	if whole > 0 and people.backlog() < 4:
		people.advance(whole)
	_day_debt -= whole
	clock_day = maxf(clock_day, float(people.day()) + minf(_day_debt, 0.999))
	_frames += 1
	if _frames == 20 and _click_at != Vector2.INF:
		_pick(_click_at)
	if _waiting:
		var p: Dictionary = people.take_person()
		if not p.is_empty():
			_waiting = false
			_show_person(p)
	_update_map()
	var close: bool = terrain.level <= TileTerrain.CLOSE_LEVEL
	visible = drawn and close
	var view_km: float = get_parent().width if "width" in get_parent() else 360.0
	# realistic by default: figures at their real size up close, houses in the
	# close LOD, no people from further up; P adds the dots as an overview
	var figures := view_km <= FIGURE_KM
	var dots := shown and not figures
	_hud.visible = visible and (figures or dots)
	var landscape := get_parent()
	var trips_start := Time.get_ticks_usec()
	_trips.step(delta, close and figures, landscape.target if "target" in landscape else Vector2.ZERO, view_km)
	trips_usec = Time.get_ticks_usec() - trips_start
	_flows.step(drawn and not figures, landscape.target if "target" in landscape else Vector2.ZERO, view_km)
	if not close:
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
	var looks: Texture2D = _life.sync(people, people.page_side(), _house_texture.get_layers())
	if looks != null:
		for m in _house_materials: # a tent household's house is its tent
			m.set_shader_parameter("look_tex", looks)
			m.set_shader_parameter("has_looks", true)
	_sync_person_looks()
	_sync_person_fields()
	_sync_away()
	# the dots stand on the terrain: same zoom level, relief blend and patch
	# only what changed: setting a texture rebuilds a material's uniform set,
	# for some 20 materials each frame (Mac tour, 29.10.2026)
	var source: ShaderMaterial = terrain._terrain_material
	var targets: Array = [_material, _prep_material, _house_prep_material, _figure_material, _figure_shadow_material, _crop_material, _parcel_material, _trips.material, _life.material] + _house_materials
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
		_parcel_frames = 2
	if synced > 0:
		_prep_frames = 2
	if synced_houses > 0:
		_house_prep_frames = 2
	# up close only the figures are placed, so their list first
	_figures.visible = figures
	if figures:
		_update_figures(view_km, synced > 0)
		_update_field_routes()
		_aim_figure_shadows()
	if figures != _prep_listed:
		_prep_listed = figures
		_prep_material.set_shader_parameter("listed", figures)
		_prep_rect.visible = not figures
		_prep_points.visible = figures
		_prep_frames = 2
	# the house placement of the last frame back to the CPU, before this
	# frame's pass draws over it
	if _house_read_gen >= 0:
		_read_house_places(_house_read_gen)
		_house_read_gen = -1
	if _house_prep_frames > 0:
		_house_prep_frames -= 1
		_house_prep_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		_lots_dirty = true # the farmhouses may stand on other lots
		if people.has_method("house_gen"):
			_house_read_gen = people.house_gen()
	if _prep_frames > 0 and (figures or dots):
		_prep_frames -= 1
		prep_runs += 1
		_prep_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	# 3.5 px up close, about 1.7 px at 360 km and 1 px over the whole sea, so
	# the dots stay single people instead of melting into black regions
	var px := clampf(3.5 - 0.5 * log(maxf(view_km, 1.0) / 30.0) / log(2.0), 1.0, 3.5)
	_update_houses(view_km, synced_houses != 0)
	_update_crops(view_km)
	multimesh.visible_instance_count = -1 if dots else 0
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
