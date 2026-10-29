extends Node3D
## The build menu (S69, S70, S73): three tools at the left edge, as
## SimCity's toolbar but nothing else, for farms, fields and roads on the
## sim's fine tiles (1.5625 km, 16 per 25 km cell). Up close only: from
## BUILD_MAX_KM on the tools are dimmed and switched off.
##
##   1  Hof: a click orders a farm on the tile
##   2  Feld: drag paints fields; starting on a field takes them away
##   3  Strasse: drag a straight road from tile to tile
##   Esc or a right click puts the tool away; a click on an order of the
##   same kind takes it back. Middle and right drag still move the map.
##
## Water tiles (sea, lakes, rivers) take no order; the preview shows them
## red. What else makes a place "passend" (S69) is not decided.
##
## The orders live in the sim (ApoleiaPeople.order_build, apoleia_sim::build),
## applied between two days; this node draws what build_orders() returns
## whenever its version changes. Without the GDExtension it keeps them
## itself, so the menu can be tried on the bare landscape. Carrying the
## orders out (day labourers paid from the treasury, S102) is not built yet.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const FINE_KM := 25.0 / 16.0 # apoleia_sim::settle::FINE_KM
const BUILD_MAX_KM := 80.0 # view width up to which the tools work (a tile about 25 px across)
const CLICK_PX := 4.0
const LIFT := 0.02 # km above the ground; drawn without depth test anyway
const GRID := 4 # quads per tile side, so an order follows the terraces
const INSET := 0.06 # of a tile left free around an order
const FARM := 0
const FIELD := 1
const ROAD := 2
const NAMES := ["Hof", "Feld", "Strasse"]
const COLOURS: Array[Color] = [Color("c9a45c"), Color("9cc47e"), Color("b9b2a3")]
const NONE := -1

var landscape: Node3D
var terrain: Node3D
var people: RefCounted # ApoleiaPeople, or null
var tool := NONE
var _orders := {} # Vector2i(col, row) -> kind, as the sim last reported
var _version := -1
var _stroke: Array[Vector2i] = [] # tiles of the stroke under way
var _stroke_erase := false
var _stroke_from := Vector2i.ZERO
var _stroking := false
var _hover := Vector2i(1 << 30, 0)
var _right_at := Vector2.INF
var _buttons: Array[ToolButton] = []
var _mesh := ImmediateMesh.new()
var _drawn_at := Vector3.INF # centre and width the orders were last drawn for
var _dirty := true

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
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = 10
	view.material_override = m
	view.custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	add_child(view)
	var hud := CanvasLayer.new()
	hud.layer = 3
	add_child(hud)
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	hud.add_child(bar)
	for kind in NAMES.size():
		var b := ToolButton.new()
		b.kind = kind
		b.tooltip_text = "%s  (%d)" % [NAMES[kind], kind + 1]
		b.chosen.connect(_choose.bind(kind))
		bar.add_child(b)
		_buttons.append(b)

func _close() -> bool:
	return landscape.width <= BUILD_MAX_KM

func _choose(kind: int) -> void:
	tool = NONE if tool == kind or not _close() else kind
	_end_stroke(false)
	for b in _buttons:
		b.active = b.kind == tool
		b.queue_redraw()
	_dirty = true

static func tile_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / FINE_KM), floori(p.y / FINE_KM))

func _buildable(t: Vector2i) -> bool:
	return terrain.water_at((Vector2(t) + Vector2(0.5, 0.5)) * FINE_KM) == 0

## Tiles from a to b, each sharing a side with the one before (a road
## without diagonal gaps).
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var d := b - a
	var n := Vector2(absi(d.x), absi(d.y))
	var s := Vector2i(signi(d.x), signi(d.y))
	var p := a
	var i := Vector2.ZERO
	while i.x < n.x or i.y < n.y:
		var tx := (0.5 + i.x) / n.x if n.x > 0 else INF
		var ty := (0.5 + i.y) / n.y if n.y > 0 else INF
		if tx < ty:
			p.x += s.x
			i.x += 1
		else:
			p.y += s.y
			i.y += 1
		out.append(p)
	return out

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
		var t := tile_at(landscape._ground_under(event.position))
		if event.pressed:
			_stroking = true
			_stroke_from = t
			_stroke_erase = _orders.get(t, NONE) == tool
			_stroke = [t]
			_dirty = true
		elif _stroking:
			_end_stroke(true)
	elif event is InputEventMouseMotion:
		var t := tile_at(landscape._ground_under(event.position))
		if t != _hover:
			_hover = t
			_dirty = true
		if _stroking:
			get_viewport().set_input_as_handled()
			match tool:
				FIELD:
					if t != _stroke[-1]:
						for s in line(_stroke[-1], t).slice(1):
							if not s in _stroke:
								_stroke.append(s)
				ROAD:
					_stroke = line(_stroke_from, t)
			_dirty = true

## Sends the stroke as one command (or forgets it) and clears it.
func _end_stroke(send: bool) -> void:
	if send and not _stroke.is_empty():
		var tiles := PackedInt32Array()
		for t in _stroke:
			if _stroke_erase:
				if _orders.get(t, NONE) == tool:
					tiles.append_array([t.x, t.y])
			elif _buildable(t):
				tiles.append_array([t.x, t.y])
		if not tiles.is_empty():
			_send(tool, tiles, _stroke_erase)
	_stroking = false
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
		var t := Vector2i(tiles[i], tiles[i + 1])
		if erase:
			_orders.erase(t)
		else:
			_orders[t] = kind
	_dirty = true

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
	var at := Vector3(landscape.target.x, landscape.target.y, landscape.width)
	if _drawn_at.x == INF or Vector2(at.x, at.y).distance_to(Vector2(_drawn_at.x, _drawn_at.y)) > at.z * 0.2 \
			or absf(log(at.z / _drawn_at.z)) > 0.2:
		_dirty = true
	if _dirty:
		_drawn_at = at
		_draw_orders()

func _take_orders() -> void:
	var d: Dictionary = people.build_orders()
	var flat: PackedInt32Array = d.tiles
	_orders.clear()
	for i in range(0, flat.size(), 3):
		_orders[Vector2i(flat[i], flat[i + 1])] = flat[i + 2]
	_dirty = true

## The orders around the view, the stroke under way and the tile under the
## cursor, each as a translucent patch draped over the ground.
func _draw_orders() -> void:
	_dirty = false
	_mesh.clear_surfaces()
	var reach := landscape.width * 1.2
	var centre: Vector2 = landscape.target
	var quads := []
	if _close():
		for t: Vector2i in _orders:
			if absf((t.x + 0.5) * FINE_KM - centre.x) < reach and absf((t.y + 0.5) * FINE_KM - centre.y) < reach:
				quads.append([t, Color(COLOURS[_orders[t]], 0.55)])
		if tool != NONE:
			for t in _stroke:
				var ok := _orders.get(t, NONE) == tool if _stroke_erase else _buildable(t)
				var c := Color(0.1, 0.1, 0.1, 0.5) if _stroke_erase else Color(COLOURS[tool].lightened(0.35), 0.75)
				quads.append([t, c if ok else Color(SimTables.NEGATIVE, 0.6)])
			if _stroke.is_empty():
				quads.append([_hover, Color(1, 1, 1, 0.4) if _buildable(_hover) else Color(SimTables.NEGATIVE, 0.5)])
	if quads.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in quads:
		_patch(q[0], q[1])
	_mesh.surface_end()

func _patch(t: Vector2i, colour: Color) -> void:
	var lo := (Vector2(t) + Vector2(INSET, INSET)) * FINE_KM
	var step := FINE_KM * (1.0 - 2.0 * INSET) / GRID
	var p := []
	for j in GRID + 1:
		for i in GRID + 1:
			var g := lo + Vector2(i, j) * step
			p.append(Vector3(g.x, terrain.ground_y(g) + LIFT, g.y))
	_mesh.surface_set_color(colour)
	for j in GRID:
		for i in GRID:
			var a: Vector3 = p[j * (GRID + 1) + i]
			var b: Vector3 = p[j * (GRID + 1) + i + 1]
			var c: Vector3 = p[(j + 1) * (GRID + 1) + i]
			var d: Vector3 = p[(j + 1) * (GRID + 1) + i + 1]
			for v in [a, b, c, b, d, c]:
				_mesh.surface_add_vertex(v)

## A square button with a drawn sign: a house, furrows, a road.
class ToolButton extends Control:
	const SIZE := Vector2(44, 44)
	signal chosen
	var kind := 0
	var active := false
	var enabled := true

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
			2: # Strasse: two edges and a broken middle line
				draw_line(c + Vector2(-7, 12), c + Vector2(-3, -12), ink, 2.0)
				draw_line(c + Vector2(7, 12), c + Vector2(3, -12), ink, 2.0)
				for k in 3:
					var y := 9.0 - k * 8.0
					draw_line(c + Vector2(0, y), c + Vector2(0, y - 4), ink, 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if enabled:
				chosen.emit()
			accept_event()
