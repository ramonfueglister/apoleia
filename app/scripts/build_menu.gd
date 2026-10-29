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
##   3  Strasse: drag from A to B; the road takes the easiest way between
##      (gentle slopes, round hills, never through water); a click on a
##      road takes that stretch back
##   Esc or a right click puts the tool away; a click on a farm of yours
##   takes it back. Middle and right drag still move the map.
##
## Water takes no order; the preview shows it red, and amber or grey where
## the sim says nobody would move in or what it does is not decided yet.
##
## The orders live in the sim (ApoleiaPeople.order_build, apoleia_sim::build),
## each at the middle of its lot in world metres, applied between two days;
## this node draws what build_orders() returns whenever its version changes.
## Without the GDExtension it keeps them itself. Farms are built by day
## labourers paid from the treasury (S113): a planned farm stands as a pale
## ghost that rises with the work done; a finished one is a farm of the
## view. Roads are drawn as a narrow track draped over the ground, smoothed
## through the lot middles.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const TileTerrain = preload("res://scripts/tile_terrain.gd")
const Farmhouse = preload("res://scripts/voxel/farmhouse.gd")
const LOT_KM := 0.5 # people_dots.gd LOT_KM, people_dots_common.gdshaderinc DOT_LOT_KM
const BUILD_MAX_KM := 30.0 # view width up to which the tools work (a lot about 24 px across)
const CLICK_PX := 4.0
const BUTTON_PX := 76.0 # tool button edge in points (44 was too small, Ramon 29.10.2026)
const LIFT := 0.006 # km above the ground
const FIELD_GRID := 2 # quads per lot side, so a field follows the terraces
const FIELD_MAX_SIDE := 24 # lots per side of one field rectangle (12 km)
const FIELD_INSET := 0.04 # of a lot left free round a field (the lane)
const ROAD_KM := 0.1 # width of a road: a cart track of about 4 m at the diorama scale
const ROAD_STEP_KM := 0.05 # draping: a road sample at least this often
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
## roof terracotta, ripe grain, stone: each stands off the green ground
const COLOURS: Array[Color] = [Color("b5552e"), Color("e0b83c"), Color("a9a296")]
const TRACK := Color("8a6a45") # a planned road: bare earth
const GOOD := Color(0.45, 0.85, 0.45, 0.55)
const BAD := Color(0.91, 0.42, 0.35, 0.6)
const NONE := -1
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var landscape: Node3D
var terrain: Node3D
var people: RefCounted # ApoleiaPeople, or null
var tool := NONE
var _orders := {} # lot (Vector2i) -> kind, as the sim last reported
var _progress := {} # lot -> share of the site built (0 … 1), where work began
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
var _ghost_mesh: Mesh
var _ghost: MeshInstance3D # the farmhouse under the cursor
var _ghost_material := StandardMaterial3D.new()
var _planned: Array[MeshInstance3D] = [] # planned farms, reused
var _planned_material := StandardMaterial3D.new()
var _heights := {} # lot -> ground height (m), for the road search
## The sim's answer to "can this be built?" (ask_build_check): status by
## lot (0 gets built, 1 nobody builds here, 2 not decided yet, 3 a farm
## nobody moves into today), the lots last asked, the text.
var _check := {}
var _check_key: Array[Vector2i] = []
var _asking := false
var _label: Label
const CHECK_COLOURS: Array[Color] = [Color(1, 1, 1, 0.45), Color(0.91, 0.52, 0.42, 0.6), Color(0.55, 0.55, 0.55, 0.55), Color(0.88, 0.63, 0.25, 0.6)]

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
	# the farmhouse ghost: the first build at its nearest detail
	_ghost_mesh = Farmhouse.lods(TileTerrain.HOUSE_M, 0)[0]
	for mat in [_ghost_material, _planned_material]:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_planned_material.albedo_color = Color(0.95, 0.92, 0.85, 0.55)
	_ghost = _house_instance(_ghost_material)
	_ghost.visible = false
	var hud := CanvasLayer.new()
	hud.layer = 3
	add_child(hud)
	var bar := VBoxContainer.new()
	# BUTTON_PX points; on a Retina screen a pixel is half a point
	var k := BUTTON_PX / ToolButton.SIZE.x * DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())
	bar.add_theme_constant_override("separation", roundi(8 * k))
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, roundi(14 * k))
	hud.add_child(bar)
	for kind in NAMES.size():
		var b := ToolButton.new()
		b.scale_k = k
		b.custom_minimum_size = ToolButton.SIZE * k
		b.kind = kind
		b.tooltip_text = "%s  (%d)" % [NAMES[kind], kind + 1]
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

func _house_instance(material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _ghost_mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _close() -> bool:
	return landscape.width <= BUILD_MAX_KM

func _choose(kind: int) -> void:
	tool = NONE if tool == kind or not _close() else kind
	_end_stroke(false)
	for b in _buttons:
		b.active = b.kind == tool
		b.queue_redraw()
	_dirty = true

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
		match event.keycode:
			KEY_1, KEY_2, KEY_3:
				_choose(event.keycode - KEY_1)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				if tool != NONE:
					_choose(tool)
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
			elif _buildable(l) and _check.get(l, 0) != 1 and _orders.get(l, NONE) != tool:
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
			b.tooltip_text = "%s  (%d)" % [NAMES[b.kind], b.kind + 1] if close else "%s: zum Bauen näher heranzoomen" % NAMES[b.kind]
			b.queue_redraw()
	if not close and tool != NONE:
		_choose(tool)
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
	var show := tool == FARM and _close() and not _stroke_erase and _orders.get(_hover, NONE) != FARM
	_ghost.visible = show
	if not show:
		return
	_ghost.transform = _house_transform(_hover, 1.0)
	var c := GOOD
	if not _buildable(_hover):
		c = BAD
	elif _check.get(_hover, 0) != 0:
		c = CHECK_COLOURS[_check[_hover]] if _check[_hover] < CHECK_COLOURS.size() else BAD
	_ghost_material.albedo_color = c

## A farmhouse on lot l at the diorama scale (people_houses.gdshader
## prop_scale), `rise` of its height built.
func _house_transform(l: Vector2i, rise: float) -> Transform3D:
	var c := lot_centre(l)
	var s := TileTerrain.HOUSE_M * TileTerrain.DIORAMA_KM_PER_M
	var basis := Basis.from_scale(Vector3(s, s * clampf(rise, 0.08, 1.0), s))
	return Transform3D(basis, Vector3(c.x, terrain.ground_y(c), c.y))

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
	# column, row, days done, days needed per order (S113); 0, 0 no site yet
	var done: PackedInt32Array = d.get("progress", PackedInt32Array())
	_progress.clear()
	for i in range(0, done.size(), 4):
		if done[i + 3] > 0 and done[i + 2] > 0:
			_progress[lot_at(Vector2(done[i], done[i + 1]) / 1000.0)] = minf(float(done[i + 2]) / done[i + 3], 1.0)
	_dirty = true

# --------------------------------------------------------------- drawing

## The orders around the view and the stroke under way: planned farms as
## pale houses that rise with the work, fields as lots draped over the
## ground, roads as a smoothed track.
func _draw_orders() -> void:
	_dirty = false
	_mesh.clear_surfaces()
	var reach: float = landscape.width * 1.2
	var centre: Vector2 = landscape.target
	var near := func(l: Vector2i) -> bool:
		var c := lot_centre(l)
		return absf(c.x - centre.x) < reach and absf(c.y - centre.y) < reach
	var farms: Array[Vector2i] = []
	var fields: Array[Vector2i] = []
	var chains := []
	if _close():
		for l: Vector2i in _orders:
			if near.call(l):
				match _orders[l]:
					FARM: farms.append(l)
					FIELD: fields.append(l)
		for chain in _chains():
			if near.call(chain[0]) or near.call(chain[-1]):
				chains.append(chain)
	var preview := _close() and (tool == FIELD or tool == ROAD)
	if not fields.is_empty() or not chains.is_empty() or preview:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for l in fields:
			_field(l, Color(COLOURS[FIELD], 0.5), _progress.get(l, 0.0))
		for chain in chains:
			_road(chain, Color(TRACK, 0.85))
		if preview and not _stroke.is_empty():
			match tool:
				FIELD:
					for l in _stroke:
						_field(l, _preview_colour(l, Color(COLOURS[FIELD].lightened(0.3), 0.75)), 0.0)
				ROAD:
					var ok := true
					for l in _stroke:
						ok = ok and _buildable(l) and _check.get(l, 0) != 1
					_road(_stroke, Color(0.1, 0.1, 0.1, 0.6) if _stroke_erase else (Color(COLOURS[ROAD].lightened(0.3), 0.9) if ok else BAD))
		elif preview:
			_field(_hover, _preview_colour(_hover, Color(1, 1, 1, 0.35)), 0.0)
		_mesh.surface_end()
	# planned farms: a pale house each, as high as it is built
	while _planned.size() < farms.size():
		_planned.append(_house_instance(_planned_material))
	for i in _planned.size():
		_planned[i].visible = i < farms.size()
		if i < farms.size():
			_planned[i].transform = _house_transform(farms[i], _progress.get(farms[i], 0.0))

## Preview colour of a lot: `ok` where it gets built, else by the sim's
## status (red nobody builds here, grey not decided yet, amber nobody
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
## kept) and draped as a ROAD_KM wide band.
func _road(lots: Array, colour: Color) -> void:
	if lots.size() < 2:
		return
	var pts := PackedVector2Array()
	for l: Vector2i in lots:
		pts.append(lot_centre(l))
	for _k in 2:
		pts = _chaikin(pts)
	# samples at most ROAD_STEP_KM apart, so the band follows the ground
	var line := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var n := maxi(1, ceili(pts[i - 1].distance_to(pts[i]) / ROAD_STEP_KM))
		for k in range(1, n + 1):
			line.append(pts[i - 1].lerp(pts[i], float(k) / n))
	_mesh.surface_set_color(colour)
	var half := ROAD_KM * 0.5
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in line.size():
		var dir := (line[mini(i + 1, line.size() - 1)] - line[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x) * half
		var l := _on_ground(line[i] + side)
		var r := _on_ground(line[i] - side)
		if i > 0:
			for v in [prev_l, prev_r, r, prev_l, r, l]:
				_mesh.surface_add_vertex(v)
		prev_l = l
		prev_r = r

static func _chaikin(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([p[0]])
	for i in p.size() - 1:
		out.append(p[i].lerp(p[i + 1], 0.25))
		out.append(p[i].lerp(p[i + 1], 0.75))
	out.append(p[p.size() - 1])
	return out

## The road orders as chains of lots between ends and crossings. Lots are
## joined to their eight neighbours, but not across a corner two straight
## steps already go round (no small triangles).
func _chains() -> Array:
	var roads := {}
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

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hover := get_global_rect().has_point(get_global_mouse_position())
		var back := SimTables.SELECTED if active or (hover and enabled) else SimTables.HEAD
		var edge := SimTables.GOLD if active else Color(SimTables.GOLD, 0.8 if hover and enabled else 0.45)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(back, 0.92)
		box.border_color = edge
		box.set_border_width_all(2 if active else 1)
		box.set_corner_radius_all(4)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_k, scale_k))
		draw_style_box(box, Rect2(Vector2.ZERO, SIZE))
		var ink := (SimTables.GOLD if active else SimTables.INK) * Color(1, 1, 1, 1.0 if enabled else 0.35)
		var c := SIZE * 0.5
		match kind:
			0: # Hof: walls and a roof
				draw_rect(Rect2(c + Vector2(-9, -2), Vector2(18, 12)), ink, false, 2.0)
				draw_polyline(PackedVector2Array([c + Vector2(-12, -1), c + Vector2(0, -12), c + Vector2(12, -1)]), ink, 2.0)
				draw_rect(Rect2(c + Vector2(-2, 4), Vector2(4, 6)), ink)
			1: # Feld: furrows in a plot
				draw_rect(Rect2(c - Vector2(12, 12), Vector2(24, 24)), ink, false, 2.0)
				for k in 3:
					var y := -6.0 + k * 6.0
					draw_line(c + Vector2(-8, y), c + Vector2(8, y), ink, 2.0)
			2: # Strasse: a road winding off into the distance
				draw_polyline(PackedVector2Array([c + Vector2(-9, 13), c + Vector2(-4, 4), c + Vector2(-6, -4), c + Vector2(-2, -12)]), ink, 2.0)
				draw_polyline(PackedVector2Array([c + Vector2(9, 13), c + Vector2(4, 4), c + Vector2(2, -4), c + Vector2(2, -12)]), ink, 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if enabled:
				chosen.emit()
			accept_event()
