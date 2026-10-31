extends Node3D
## The build menu (S69, S70, S73, S113): three tools at the left edge and
## nothing else, built like Anno (Ramon 29.10.2026): on the village lots
## (0.5 km, the lots the view puts farmhouses on, aligned to the terrain's
## world_min), with the real farmhouse as a ghost under the cursor and roads
## that find their own way through the land. Up close only: from
## BUILD_MAX_KM on the tools are dimmed and switched off.
##
##   1  Hof: the farmhouse follows the cursor, a click orders it
##   2  Feld: drag a rectangle of field lots, like a zone in Cities
##      Skylines (one lot holds little field, a farm tills some 160);
##      starting on a field takes the fields in the rectangle away
##   3  Strasse (put away for now, TOOLS): drag from A to B; the road takes
##      the easiest way between (gentle slopes, round hills, never through
##      water); a click on a road takes that stretch back
##   Esc or a right click puts the tool away; a click on a farm of yours
##   takes it back. Middle and right drag still move the map.
##
## The strip stands at the bottom left, under the round buttons of the main
## windows (ui/main_buttons.gd). A chosen tool opens «Wo bauen» beside it
## (ui/build_sites.gd, as Victoria 3's construction list): the markets with
## people in tents, free land, hunger and the grain price; a click there
## flies close and the tool stays in hand. Chosen from too far out, the
## tool waits until the view is close (a row of the list, or zooming in),
## and zooming out puts it back to waiting. The keys are the player's
## (ui/keys.gd).
##
## Water takes no order; the preview shows it red, and amber or grey where
## the sim says nobody would move in or what it does is not decided yet.
##
## The orders live in the sim (ApoleiaPeople.order_build, apoleia_sim::build),
## each at the middle of its lot in world metres, applied between two days;
## this node draws what build_orders() returns whenever its version changes.
## Without the GDExtension it keeps them itself. Farms are built by day
## labourers paid from the treasury (S113): the view shows a farm being
## built as its house inside a scaffold on the order's lot, a finished one
## as a farm. Roads are smoothed through the lot middles and drawn by
## road_view.gd; the farmhouse under the cursor is farmhouse_ghost.gd. A
## finished field the terrain and the crops draw as a field, and they keep
## clear of the roads (people_dots.gd set_built, _built_bits).

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const Keys = preload("res://scripts/ui/keys.gd")
const BuildSites = preload("res://scripts/ui/build_sites.gd")
const RoadView = preload("res://scripts/road_view.gd")
const FarmhouseGhost = preload("res://scripts/voxel/farmhouse_ghost.gd")
const LOT_KM := 0.5 # people_dots.gd LOT_KM, people_dots_common.gdshaderinc DOT_LOT_KM
const BUILD_MAX_KM := 30.0 # view width up to which the tools work (a lot about 24 px across)
const CLICK_PX := 4.0
const BUTTON_PX := 76.0 # tool button edge in points (44 was too small, Ramon 29.10.2026)
const LIFT := 0.006 # km above the ground
const FIELD_GRID := 2 # quads per lot side, so a field follows the terraces
const FIELD_MAX_SIDE := 24 # lots per side of one field rectangle (12 km)
const FIELD_INSET := 0.04 # of a lot left free round a field (the lane)
## Road search: a step costs its length times 1 + (grade / ROAD_GRADE)²,
## so a road keeps to about this grade where it can (Roman roads: up to
## 8–10 %); it looks at most this many lots beyond A and B.
const ROAD_GRADE := 0.06
const ROAD_MARGIN := 12
const ROAD_MAX_LOTS := 160 # longest stroke, lots (80 km)
const FARM := 0
const FIELD := 1
const ROAD := 2
const NAMES := ["Hof", "Feld", "Strasse"]
## The tools on the strip. The road is put away for now (S127, Ramon
## 30.10.2026: the ways come from people walking them, "noch keine
## Steinstrassen"); roads ordered before are still built and drawn.
const TOOLS := [FARM, FIELD]
const ICONS := ["house", "plow", "horizon-road"] # assets/ui/icons
const ACTIONS := ["apoleia_farm", "apoleia_field", ""] # their keys (ui/keys.gd)
## roof terracotta, ripe grain, stone: each stands off the green ground
const COLOURS: Array[Color] = [Color("b5552e"), Color("e0b83c"), Color("a9a296")]
const BAD := Color(0.91, 0.42, 0.35, 0.6)
const NONE := -1
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var landscape: Node3D
var terrain: Node3D
var people: RefCounted # ApoleiaPeople, or null
var tool := NONE
var _wanted := NONE # a tool chosen too far out: it comes into hand once the view is close
var _sites: BuildSites # «Wo bauen»
var _orders := {} # lot (Vector2i) -> kind, as the sim last reported
var _progress := {} # lot -> share of the site built (0 … 1), where work began
var _built_roads := {} # lot -> true: finished road lots (build_orders "roads")
var _built_fields := {} # lot -> true: finished field lots, state land (build_orders "fields", S116)
var _version := -1
var _stroke: Array[Vector2i] = [] # lots of the stroke under way
var _stroke_erase := false
var _stroke_from := Vector2i.ZERO
var _stroking := false
var _hover := Vector2i(1 << 30, 0)
var _right_at := Vector2.INF
var _buttons: Array[ToolButton] = []
var _mesh := ImmediateMesh.new()
var _drawn_at := Vector3.INF # centre and width the orders were last drawn for
var _dirty := true
var _ghost: FarmhouseGhost # the farmhouse under the cursor
var _roads: RoadView
var _road_ids := {} # ids of the roads handed to _roads
var _heights := {} # lot -> ground height (m), for the road search
## The sim's answer to "can this be built?" (ask_build_check): status by
## lot (0 gets built, 1 nobody builds here, 2 not built, 3 a farm nobody
## moves into today, 4 no free land to plough or clear), the lots last
## asked, the text.
var _check := {}
var _check_key: Array[Vector2i] = []
var _asking := false
var _label: Label
const CHECK_COLOURS: Array[Color] = [Color(1, 1, 1, 0.45), Color(0.91, 0.52, 0.42, 0.6), Color(0.55, 0.55, 0.55, 0.55), Color(0.88, 0.63, 0.25, 0.6), Color(0.8, 0.45, 0.3, 0.6)]

func setup(scene: Node3D, sim: RefCounted) -> void:
	name = "BuildMenu"
	landscape = scene
	terrain = scene.terrain
	people = sim
	var view := MeshInstance3D.new()
	view.mesh = _mesh
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10
	view.material_override = m
	view.custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	add_child(view)
	_ghost = FarmhouseGhost.new()
	add_child(_ghost)
	_ghost.setup(terrain)
	_roads = RoadView.new()
	add_child(_roads)
	_roads.setup(landscape, terrain)
	var hud := CanvasLayer.new()
	hud.layer = 3
	add_child(hud)
	var bar := VBoxContainer.new()
	# BUTTON_PX points; on a Retina screen a pixel is half a point
	var k := BUTTON_PX / ToolButton.SIZE.x * DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())
	bar.add_theme_constant_override("separation", roundi(8 * k))
	# at the bottom left, clear of the main windows' buttons above (ui/main_buttons.gd)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, roundi(14 * k))
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.theme = Vic3.theme() # the tooltips
	# the medallions on a strip of leather, as the map modes at the foot (ui/map_modes.gd)
	bar.draw.connect(func(): Vic3.draw_strip(bar, Rect2(Vector2.ZERO, bar.size).grow(5.0 * k)))
	hud.add_child(bar)
	for kind in TOOLS:
		var b := ToolButton.new()
		b.scale_k = k
		b.custom_minimum_size = ToolButton.SIZE * k
		b.kind = kind
		b.mouse_entered.connect(_tip.bind(b))
		b.chosen.connect(_choose.bind(kind))
		bar.add_child(b)
		_buttons.append(b)
	# beside the cursor: what the lot under it would cost, or why not
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", roundi(9 * k))
	_label.add_theme_color_override("font_color", SimTables.INK)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SimTables.BACKGROUND, 0.85)
	box.set_corner_radius_all(roundi(3 * k))
	box.set_content_margin_all(roundi(4 * k))
	_label.add_theme_stylebox_override("normal", box)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	hud.add_child(_label)
	_sites = BuildSites.new()
	_sites.landscape = scene
	if "people" in scene and scene.people != null:
		for c in scene.people.get_children():
			if c.get_script() == SimTables:
				_sites.tables = c
	_sites.closed.connect(_sites_closed)
	add_child(_sites)

func _close() -> bool:
	return landscape.width <= BUILD_MAX_KM

## What is being built, for the outliner (ui/outliner.gd): each order as
## {kind, at (world km), share built (0 before work began)}.
func sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Vector2i in _orders:
		out.append({"kind": _orders[l], "at": lot_centre(l), "share": _progress.get(l, 0.0)})
	return out

## A tool's button or key: the tool in hand, or put away when it was; too
## far out it waits for the view to come close.
func _choose(kind: int) -> void:
	var was := tool if tool != NONE else _wanted
	_put(NONE if was == kind else kind)
	var now := tool if tool != NONE else _wanted
	_sites.show_for(now, NAMES[now] if now != NONE else "")

## `kind` in hand, or waiting when the view is too far out (NONE: neither).
func _put(kind: int) -> void:
	tool = kind if _close() else NONE
	_wanted = NONE if _close() else kind
	_end_stroke(false)
	for b in _buttons:
		b.active = b.kind == kind
		b.queue_redraw()
	_dirty = true

## «Wo bauen» closed with its ✕: a waiting tool waits no more; one in hand stays.
func _sites_closed() -> void:
	if _wanted != NONE:
		_put(NONE)

func _tip(b: ToolButton) -> void:
	var key := Keys.key_of(ACTIONS[b.kind]) if ACTIONS[b.kind] != "" else KEY_NONE
	var label: String = NAMES[b.kind] if key == KEY_NONE else "%s  (%s)" % [NAMES[b.kind], Keys.key_name(key)]
	b.tooltip_text = label if b.enabled else "%s\nZu weit weg zum Bauen: einen Ort wählen oder näher heranzoomen" % label

# ---------------------------------------------------------------- the lots

func lot_at(p: Vector2) -> Vector2i:
	var o: Vector2 = terrain.world_min
	return Vector2i(((p - o) / LOT_KM).floor())

func lot_centre(l: Vector2i) -> Vector2:
	var o: Vector2 = terrain.world_min
	return o + (Vector2(l) + Vector2(0.5, 0.5)) * LOT_KM

## The order's spot as the sim keeps it: the lot's middle in world metres.
func spot(l: Vector2i) -> Vector2i:
	var c := lot_centre(l) * 1000.0
	return Vector2i(roundi(c.x), roundi(c.y))

func _buildable(l: Vector2i) -> bool:
	return terrain.water_at(lot_centre(l)) == 0

func _height(l: Vector2i) -> float:
	if not _heights.has(l):
		if _heights.size() > 200000:
			_heights.clear()
		_heights[l] = terrain.height_m(lot_centre(l))
	return _heights[l]

## The easiest way from lot a to lot b (A*, eight neighbours): each step
## costs its length times 1 + (grade / ROAD_GRADE)²; water is not crossed.
## Empty if there is none within ROAD_MARGIN lots of the two.
func route(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if a == b:
		out.append(a)
		return out
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y)) - Vector2i(ROAD_MARGIN, ROAD_MARGIN)
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) + Vector2i(ROAD_MARGIN, ROAD_MARGIN)
	var w := hi.x - lo.x + 1
	var cost := {a: 0.0} # by lot
	var came := {}
	var heap := Heap.new()
	heap.push(_dist(a, b), a)
	while not heap.empty():
		var n: Vector2i = heap.pop()
		if n == b:
			var at := b
			while at != a:
				out.append(at)
				at = came[at]
			out.append(a)
			out.reverse()
			return out
		var here: float = cost[n]
		for d in DIRS:
			var m := n + d
			if m.x < lo.x or m.y < lo.y or m.x > hi.x or m.y > hi.y or not _buildable(m):
				continue
			var run := Vector2(d).length() * LOT_KM * 1000.0
			var grade := absf(_height(m) - _height(n)) / run
			var c := here + Vector2(d).length() * (1.0 + pow(grade / ROAD_GRADE, 2.0))
			if c < cost.get(m, INF):
				cost[m] = c
				came[m] = n
				heap.push(c + _dist(m, b), m)
		if cost.size() > w * (hi.y - lo.y + 1):
			break
	return out

static func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

# ----------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if Keys.pressed(event, "apoleia_farm") or Keys.pressed(event, "apoleia_field"):
			_choose(FARM if Keys.pressed(event, "apoleia_farm") else FIELD)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and (tool != NONE or _wanted != NONE):
			_choose(tool if tool != NONE else _wanted)
			get_viewport().set_input_as_handled()
		return
	if tool == NONE:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# a right click puts the tool away, a right drag still moves the map
			if event.pressed:
				_right_at = event.position
			elif _right_at.distance_to(event.position) <= CLICK_PX:
				_choose(tool)
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		get_viewport().set_input_as_handled()
		var l := lot_at(landscape._ground_under(event.position))
		if event.pressed:
			_stroking = true
			_stroke_from = l
			_stroke_erase = _orders.get(l, NONE) == tool
			_stroke = [l]
			if _stroke_erase and tool == ROAD:
				_stroke = _chain_of(l)
			_dirty = true
		elif _stroking:
			_end_stroke(true)
	elif event is InputEventMouseMotion:
		var l := lot_at(landscape._ground_under(event.position))
		if l != _hover:
			_hover = l
			_dirty = true
		if _stroking:
			get_viewport().set_input_as_handled()
			if l == _stroke[-1] or _stroke_erase and tool == ROAD:
				return
			match tool:
				FIELD:
					_stroke = _rect(_stroke_from, l)
				ROAD:
					if _dist(_stroke_from, l) <= ROAD_MAX_LOTS:
						var r := route(_stroke_from, l)
						if not r.is_empty():
							_stroke = r
			_dirty = true

## The lots of the rectangle from a towards b, at most FIELD_MAX_SIDE a side.
static func _rect(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var d := (b - a).clamp(-Vector2i.ONE * (FIELD_MAX_SIDE - 1), Vector2i.ONE * (FIELD_MAX_SIDE - 1))
	var out: Array[Vector2i] = []
	for j in range(mini(0, d.y), maxi(0, d.y) + 1):
		for i in range(mini(0, d.x), maxi(0, d.x) + 1):
			out.append(a + Vector2i(i, j))
	return out

## Sends the stroke as one command (or forgets it) and clears it.
func _end_stroke(send: bool) -> void:
	if send and not _stroke.is_empty():
		var tiles := PackedInt32Array()
		for l in _stroke:
			if _stroke_erase:
				if _orders.get(l, NONE) == tool:
					var s := spot(l)
					tiles.append_array([s.x, s.y])
			elif _buildable(l) and _check.get(l, 0) != 1 and _check.get(l, 0) != 4 and _orders.get(l, NONE) != tool \
					and not (tool == ROAD and _built_roads.has(l)) and not (tool == FIELD and _built_fields.has(l)):
				var s := spot(l)
				tiles.append_array([s.x, s.y])
		if not tiles.is_empty():
			_send(tool, tiles, _stroke_erase)
	_stroking = false
	_stroke_erase = false
	_stroke.clear()
	_dirty = true

func _send(kind: int, tiles: PackedInt32Array, erase: bool) -> void:
	if people != null:
		if erase:
			people.cancel_build(tiles)
		else:
			people.order_build(kind, tiles)
		return
	for i in range(0, tiles.size(), 2):
		var l := lot_at(Vector2(tiles[i], tiles[i + 1]) / 1000.0)
		if erase:
			_orders.erase(l)
		else:
			_orders[l] = kind
	_dirty = true

# ------------------------------------------------------------ each frame

func _process(_delta: float) -> void:
	var close := _close()
	for b in _buttons:
		if b.enabled != close:
			b.enabled = close
			_tip(b)
			b.queue_redraw()
	if (not close and tool != NONE) or (close and _wanted != NONE):
		_put(tool if tool != NONE else _wanted) # in hand when close, waiting when far
	if people != null:
		var v: int = people.build_version()
		if v != _version:
			_version = v
			_take_orders()
	_update_check()
	_place_ghost()
	var at := Vector3(landscape.target.x, landscape.target.y, landscape.width)
	if _drawn_at.x == INF or Vector2(at.x, at.y).distance_to(Vector2(_drawn_at.x, _drawn_at.y)) > at.z * 0.2 \
			or absf(log(at.z / _drawn_at.z)) > 0.2:
		_dirty = true
	if _dirty:
		_drawn_at = at
		_draw_orders()

## The farmhouse under the cursor while the Hof tool is out: green where
## it gets built, red where not, amber where nobody would move in today.
func _place_ghost() -> void:
	var show: bool = tool == FARM and _close() and not _stroke_erase and _orders.get(_hover, NONE) != FARM
	if not show:
		_ghost.visible = false
		return
	var status: int = _check.get(_hover, 0)
	var ok: bool = _buildable(_hover) and (status == 0 or status == 3)
	_ghost.show_at(lot_centre(_hover), ok)
	if ok and status == 3:
		# amber: gets built, but nobody moves in nearby today
		var c: Color = CHECK_COLOURS[status]
		(_ghost.material_override as ShaderMaterial).set_shader_parameter("tint", Vector3(c.r, c.g, c.b))

## Asks the sim about the lots under the cursor or the stroke whenever
## they change (one question at a time) and shows its answer.
func _update_check() -> void:
	var wanted: Array[Vector2i] = []
	if tool != NONE and _close() and not _stroke_erase:
		if _stroke.is_empty():
			wanted.append(_hover)
		else:
			wanted.append_array(_stroke)
	_label.visible = not wanted.is_empty() and _label.text != ""
	_label.position = get_viewport().get_mouse_position() + Vector2(18, 18) * _buttons[0].scale_k / 2.0
	if people == null:
		return
	if _asking:
		var a: Dictionary = people.take_build_check()
		if a.is_empty():
			return
		_asking = false
		_take_check(a)
	if wanted.is_empty() or wanted == _check_key:
		return
	var tiles := PackedInt32Array()
	for l in wanted:
		var s := spot(l)
		tiles.append_array([s.x, s.y])
	people.ask_build_check(tool, tiles)
	_check_key = wanted
	_asking = true

func _take_check(a: Dictionary) -> void:
	if tool == NONE:
		return
	var flat: PackedInt32Array = a.tiles
	var states: PackedStringArray = a.states
	_check.clear()
	var bad := -1
	for i in range(0, flat.size(), 3):
		_check[lot_at(Vector2(flat[i], flat[i + 1]) / 1000.0)] = flat[i + 2]
		if flat[i + 2] != 0 and bad < 0:
			bad = flat[i + 2]
	var n := flat.size() / 3
	var what: String = NAMES[tool]
	if n > 1:
		what = "%s, %s km" % [NAMES[tool], String.num(n * LOT_KM, 1)] if tool == ROAD else "Feld, %d Parzellen" % n
	if bad < 0:
		_label.text = "%s · %s Tage · %s Denar" % [what, SimTables._int(int(a.days)), SimTables._int(roundi(a.cost))]
	else:
		_label.text = "%s · %s" % [what, states[bad]] if bad < states.size() else what
	_dirty = true

func _take_orders() -> void:
	var d: Dictionary = people.build_orders()
	var flat: PackedInt32Array = d.tiles
	_orders.clear()
	for i in range(0, flat.size(), 3):
		_orders[lot_at(Vector2(flat[i], flat[i + 1]) / 1000.0)] = flat[i + 2]
	# finished road lots stay roads once their orders are gone: x, z metres
	var built: PackedInt32Array = d.get("roads", PackedInt32Array())
	_built_roads.clear()
	for i in range(0, built.size(), 2):
		_built_roads[lot_at(Vector2(built[i], built[i + 1]) / 1000.0)] = true
	# finished field lots: state land until a farm leases it, x, z metres
	var ploughed: PackedInt32Array = d.get("fields", PackedInt32Array())
	_built_fields.clear()
	for i in range(0, ploughed.size(), 2):
		_built_fields[lot_at(Vector2(ploughed[i], ploughed[i + 1]) / 1000.0)] = true
	if landscape.people != null:
		landscape.people.set_built(_built_bits())
	# column, row, days done, days needed per order (S113); 0, 0 no site yet
	var done: PackedInt32Array = d.get("progress", PackedInt32Array())
	_progress.clear()
	for i in range(0, done.size(), 4):
		if done[i + 3] > 0 and done[i + 2] > 0:
			_progress[lot_at(Vector2(done[i], done[i + 1]) / 1000.0)] = minf(float(done[i + 2]) / done[i + 3], 1.0)
	_dirty = true

# --------------------------------------------------------------- drawing

## The orders around the view and the stroke under way: fields as lots
## draped over the ground, roads handed to road_view.gd (farms being built
## the view shows itself, as scaffolds; finished fields the terrain and the
## crops, sim_fields.gdshaderinc sim_built).
func _draw_orders() -> void:
	_dirty = false
	_mesh.clear_surfaces()
	var reach: float = landscape.width * 1.2
	var centre: Vector2 = landscape.target
	var near := func(l: Vector2i) -> bool:
		var c := lot_centre(l)
		return absf(c.x - centre.x) < reach and absf(c.y - centre.y) < reach
	var fields: Array[Vector2i] = []
	var chains := []
	if _close():
		for l: Vector2i in _orders:
			if near.call(l):
				if _orders[l] == FIELD:
					fields.append(l)
		for chain in _chains():
			if near.call(chain[0]) or near.call(chain[-1]):
				chains.append(chain)
	var preview := _close() and (tool == FIELD or tool == ROAD)
	# the road being drawn, else the lot under the cursor
	var road_preview := preview and tool == ROAD and _stroke.size() >= 2
	var lots_preview := preview and not road_preview
	if not fields.is_empty() or lots_preview:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for l in fields:
			_field(l, Color(COLOURS[FIELD], 0.5), _progress.get(l, 0.0))
		if lots_preview and tool == FIELD and not _stroke.is_empty():
			for l in _stroke:
				_field(l, _preview_colour(l, Color(COLOURS[FIELD].lightened(0.3), 0.75)), 0.0)
		elif lots_preview:
			var at: Vector2i = _stroke[0] if not _stroke.is_empty() else _hover
			_field(at, _preview_colour(at, Color(1, 1, 1, 0.35)), 0.0)
		_mesh.surface_end()
	# roads: each chain built from its first lot as far as its lots are
	var ids := {}
	for chain in chains:
		var built := 0.0
		for l: Vector2i in chain:
			built += 1.0 if _built_roads.has(l) else float(_progress.get(l, 0.0))
		var id := "%s>%s:%d" % [chain[0], chain[-1], chain.size()]
		_roads.set_road(id, _smooth(chain), built / chain.size())
		ids[id] = true
	if road_preview:
		var ok := not _stroke_erase
		for l in _stroke:
			ok = ok and _buildable(l) and _check.get(l, 0) != 1
		_roads.set_road("preview", _smooth(_stroke), 0.0, true, not ok)
		ids["preview"] = true
	for id in _road_ids:
		if not ids.has(id):
			_roads.remove_road(id)
	_road_ids = ids

## Preview colour of a lot: `ok` where it gets built, else by the sim's
## status (red nobody builds here or no free land, grey not built, amber nobody
## moves in).
func _preview_colour(l: Vector2i, ok: Color) -> Color:
	if _stroke_erase:
		return Color(0.1, 0.1, 0.1, 0.5) if _orders.get(l, NONE) == tool else BAD
	if not _buildable(l):
		return BAD
	var status: int = _check.get(l, 0)
	if status <= 0 or status >= CHECK_COLOURS.size():
		return ok
	return CHECK_COLOURS[status]

## A field lot draped over the ground, with furrows; `done` of it (from the
## west) a shade darker.
func _field(l: Vector2i, colour: Color, done: float) -> void:
	var o: Vector2 = terrain.world_min
	var lo := o + (Vector2(l) + Vector2(FIELD_INSET, FIELD_INSET)) * LOT_KM
	var step := LOT_KM * (1.0 - 2.0 * FIELD_INSET) / FIELD_GRID
	for j in FIELD_GRID:
		for i in FIELD_GRID:
			var c := colour
			if (j % 2) == 1:
				c = c.darkened(0.12) # furrows, east to west
			if done > 0.0 and (i + 0.5) / FIELD_GRID <= done:
				c = c.darkened(0.25)
			_quad(lo + Vector2(i, j) * step, step, c)

func _quad(p: Vector2, s: float, c: Color) -> void:
	var a := _on_ground(p)
	var b := _on_ground(p + Vector2(s, 0))
	var d := _on_ground(p + Vector2(s, s))
	var e := _on_ground(p + Vector2(0, s))
	_mesh.surface_set_color(c)
	for v in [a, b, d, a, d, e]:
		_mesh.surface_add_vertex(v)

func _on_ground(p: Vector2) -> Vector3:
	return Vector3(p.x, terrain.ground_y(p) + LIFT, p.y)

## A road through the middles of `lots`, smoothed (Chaikin, twice, ends
## kept), in world km.
func _smooth(lots: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for l: Vector2i in lots:
		pts.append(lot_centre(l))
	for _k in 2:
		pts = _chaikin(pts)
	return pts

static func _chaikin(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([p[0]])
	for i in p.size() - 1:
		out.append(p[i].lerp(p[i + 1], 0.25))
		out.append(p[i].lerp(p[i + 1], 0.75))
	out.append(p[p.size() - 1])
	return out

## The road lots, ordered and finished, each with the lots it is joined
## to: its eight neighbours, but not across a corner two straight steps
## already go round (no small triangles).
func _road_links() -> Dictionary:
	var roads := _built_roads.duplicate()
	for l: Vector2i in _orders:
		if _orders[l] == ROAD:
			roads[l] = true
	var links := {}
	for l: Vector2i in roads:
		var ns: Array[Vector2i] = []
		for d in DIRS:
			var m := l + d
			if not roads.has(m):
				continue
			if d.x != 0 and d.y != 0 and (roads.has(l + Vector2i(d.x, 0)) or roads.has(l + Vector2i(0, d.y))):
				continue
			ns.append(m)
		links[l] = ns
	return links

## What the player built, by lot (Vector2i -> int), for the terrain, the
## crops and the trees (sim_fields.gdshaderinc sim_built): bit 0 a finished
## field; then five bits for each of the lot's four parcels (from 1 + 5 k,
## k = x + 2 y of its quarter): a road crosses it, a road runs along its
## side -x, -y, +x, +y. The roads run through the lot middles, the corners
## of their parcels: a straight step runs between two parcels, a diagonal
## one across a parcel and past the corners of the parcels beside it, and
## the smoothing (_smooth) cuts across the parcel inside a right-angled
## bend (about 90 m in from the lot middle, the road 95 m wide).
func _built_bits() -> Dictionary:
	var bits := {}
	for l: Vector2i in _built_fields:
		bits[l] = 1
	var links := _road_links()
	for l: Vector2i in links:
		var dirs := {}
		for m: Vector2i in links[l]:
			dirs[m - l] = true
		for d: Vector2i in dirs:
			if d.x == 0 or d.y == 0:
				var e := Vector2i(absi(d.y), absi(d.x)) # across the step
				_mark(bits, l, d + e, -e)
				_mark(bits, l, d - e, e)
			else:
				_mark(bits, l, d, Vector2i.ZERO)
				_mark(bits, l, Vector2i(d.x, -d.y), Vector2i(0, d.y))
				_mark(bits, l, Vector2i(-d.x, d.y), Vector2i(d.x, 0))
				_mark(bits, l + Vector2i(d.x, 0), Vector2i(-d.x, d.y), Vector2i(-d.x, 0))
				_mark(bits, l + Vector2i(0, d.y), Vector2i(d.x, -d.y), Vector2i(0, -d.y))
		# a bend, not a crossing (the chains end at a crossing, unsmoothed)
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				if dirs.size() == 2 and dirs.has(Vector2i(sx, 0)) and dirs.has(Vector2i(0, sy)):
					_mark(bits, l, Vector2i(sx, sy), Vector2i.ZERO)
	return bits

## Marks on the parcel in `quarter` (x and y -1 or 1) of lot `l` the road
## along its side `side` (a unit step), or with ZERO the road across it.
static func _mark(bits: Dictionary, l: Vector2i, quarter: Vector2i, side: Vector2i) -> void:
	var k := (1 if quarter.x > 0 else 0) + (2 if quarter.y > 0 else 0)
	var bit := 0
	if side != Vector2i.ZERO:
		bit = 1 + (2 if side.x + side.y > 0 else 0) + (1 if side.y != 0 else 0)
	bits[l] = bits.get(l, 0) | (1 << (1 + 5 * k + bit))

## The roads, ordered and finished, as chains of lots between ends and
## crossings (_road_links).
func _chains() -> Array:
	var links := _road_links()
	var out := []
	var used := {} # edges walked, both ways
	for start: Vector2i in links:
		if links[start].size() == 2:
			continue
		for nxt: Vector2i in links[start]:
			if used.has(Vector4i(start.x, start.y, nxt.x, nxt.y)):
				continue
			out.append(_walk(start, nxt, links, used))
	# rings without an end
	for start: Vector2i in links:
		for nxt: Vector2i in links[start]:
			if not used.has(Vector4i(start.x, start.y, nxt.x, nxt.y)):
				out.append(_walk(start, nxt, links, used))
	return out

func _walk(start: Vector2i, nxt: Vector2i, links: Dictionary, used: Dictionary) -> Array:
	var chain := [start]
	var at := start
	var to := nxt
	while true:
		used[Vector4i(at.x, at.y, to.x, to.y)] = true
		used[Vector4i(to.x, to.y, at.x, at.y)] = true
		chain.append(to)
		if links[to].size() != 2 or to == start:
			break
		var further: Vector2i = links[to][0] if links[to][0] != at else links[to][1]
		at = to
		to = further
		if used.has(Vector4i(at.x, at.y, to.x, to.y)):
			break
	return chain

## The chain of road lots through l (a click on a road takes it back).
func _chain_of(l: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for chain in _chains():
		if l in chain:
			for m: Vector2i in chain:
				out.append(m)
			return out
	out.append(l)
	return out

## A small binary heap of (priority, lot) for the road search.
class Heap:
	var keys: Array[float] = []
	var vals: Array[Vector2i] = []

	func empty() -> bool:
		return keys.is_empty()

	func push(k: float, v: Vector2i) -> void:
		keys.append(k)
		vals.append(v)
		var i := keys.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> Vector2i:
		var top := vals[0]
		var last := keys.size() - 1
		_swap(0, last)
		keys.pop_back()
		vals.pop_back()
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < keys.size() and keys[l] < keys[m]:
				m = l
			if r < keys.size() and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var v := vals[a]
		vals[a] = vals[b]
		vals[b] = v

## A square button with a drawn sign: a house, furrows, a road.
class ToolButton extends Control:
	const SIZE := Vector2(44, 44) # drawing units, scaled by scale_k
	signal chosen
	var kind := 0
	var active := false
	var enabled := true
	var scale_k := 1.0
	var _icon: Texture2D

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	## A Victoria 3 medallion with the tool's icon: lit while chosen (also
	## while it waits for the view to come close) or under the mouse, dimmed
	## when the view is too far out to build.
	func _draw() -> void:
		var hover := get_global_rect().has_point(get_global_mouse_position())
		if _icon == null:
			_icon = Vic3.icon(ICONS[kind])
		Vic3.draw_medallion(self, size * 0.5, minf(size.x, size.y) * 0.5 - 2.0 * scale_k, _icon,
			active or (enabled and hover), false, not enabled) # a waiting tool stays lit

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit() # too far out the tool waits, and «Wo bauen» shows where
			accept_event()
