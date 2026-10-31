extends MeshInstance3D
## The map mode «Handel» (ui/map_modes.gd): what the dealers carried between
## the markets in the last 28 days (Ramon, 30.10.2026: "Wuselfaktor", "alles
## aus der Simulation"; 21:28 "da müsste eine extra ansicht sein und schön").
## Only in that mode, over a greyed map (people_dots.gd mute_map), one good
## at a time (grain first), only the largest flows, as calm arcs after the
## rules of origin-destination flow maps (Jenny et al., 2018): all bowed the
## same way, so the two ways between two markets part; as wide as the root
## of what went along; an arrowhead at the market it went to; the small ones
## over the large, each in a dark casing; the markets at the ends as dots as
## large as the root of what went through them. ApoleiaPeople.ask_goods
## "grain_moves" (S114, kg) and "moves" (S111, craft goods in pieces), the
## same answer the carts up close come from (people_trips.gd); asked once a
## sim day while the figures are not drawn, so the two never ask at once
## (take_goods hands the answer to one of them). Built on the CPU only when
## the answer, the good or the zoom changed, drawn by people_flows.gdshader.
##
## Jenny, B., Stephen, D. M., Muehlenhaus, I., Marston, B. E., Sharma, R.,
## Zhang, E., & Jenny, H. (2018). Design principles for origin-destination
## flow maps. Cartography and Geographic Information Science, 45(1), 62–75.
## https://doi.org/10.1080/15230406.2016.1262280

const SHADER = preload("res://shaders/people_flows.gdshader")
const MOVE_STRIDE := 7 # from x, z, to x, z, good, units, day (trips.rs goods_to_dict)
const SEGMENTS := 24 # per arc
const SHOWN_MAX := 40 # arcs drawn, the largest of the good chosen
const BOW := 0.16 # sideways bow of an arc's middle, of its length (to the right of its way)
const WIDTH_MIN := 0.0015 # of the view width, the thinnest arc
const WIDTH_MAX := 0.007 # and the widest
const CASING := 0.0006 # of the view width, the dark rim round each arc and dot
const ARROW_LONG := 2.6 # arrowhead length, in widths of its arc
const ARROW_WIDE := 2.1 # and its width
const DOT_MIN := 0.0022 # of the view width, a market's dot
const DOT_MAX := 0.0055
const LIFT_KM := 0.002 # of the view width above the ground (the shader draws over it anyway)
const VIEW_MAX_KM := 2000.0 # not drawn from further up
const GRAIN := 255 # the good of a grain move
const GOODS: Array[int] = [255, 0, 1, 2, 3, 4, 5] # as the legend lists them: grain, then the crafts
const GOOD_NAMES := {255: "Korn", 0: "Wolle", 1: "Eisen", 2: "Kleidung", 3: "Werkzeug", 4: "Keramik", 5: "Schweinefleisch"}
const GOOD_ICONS := {255: "wheat", 0: "wool", 1: "metal-bar", 2: "roman-toga", 3: "anvil", 4: "painted-pottery", 5: "ham-shank"}
## sRGB, as people_walkers.gdshader WARES
const COLOURS := {255: Color(0.92, 0.76, 0.36), 0: Color(0.9, 0.87, 0.78), 1: Color(0.62, 0.66, 0.74), 2: Color(0.78, 0.36, 0.3),
	3: Color(0.72, 0.55, 0.36), 4: Color(0.86, 0.52, 0.32), 5: Color(0.88, 0.56, 0.52)}
const INK := Color(0.06, 0.05, 0.04, 0.7) # the casings
const DOT := Color(0.95, 0.91, 0.8) # a market, parchment

signal changed # the flows shown or their scale on the screen, for the legend's key (ui/trade_legend.gd)

var people: RefCounted
var terrain: Node3D
var material := ShaderMaterial.new()
var shown := false # the map mode «Handel» is on
var good := GRAIN
var _asked := false
var _asked_day := -1
var _asked_at := Vector3.INF # centre x, z and view width of the last ask
var _all: Array[Dictionary] = [] # {"from", "to", "good", "units"} summed over the 28 days
var _flows: Array[Dictionary] = [] # those of `good` shown, largest first
var _built_at := Vector3.INF # centre and width the arcs were last built for
var _built_h := 0.0 # the terrain's level height then
var _dirty := false
var _px_per_km := 0.0 # on the screen, in the middle of the view, when the arcs were built

func setup(sim: RefCounted, tile_terrain: Node3D) -> void:
	people = sim
	terrain = tile_terrain
	name = "PeopleFlows"
	material.shader = SHADER
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	visible = false

## The map mode «Handel» on or off.
func show_mode(on: bool) -> void:
	shown = on

## The good whose flows are shown (GOODS).
func choose_good(g: int) -> void:
	if g != good:
		good = g
		_pick()

## The units of the largest flow shown (kg of grain, pieces of a craft
## good), 0 for none.
func largest() -> float:
	return _flows[0].units if not _flows.is_empty() else 0.0

## How wide on the screen (px) an arc is that carried `share` of the
## largest, as last built; 0 before.
func width_px(share: float) -> float:
	return _px_per_km * _built_at.z * lerpf(WIDTH_MIN, WIDTH_MAX, sqrt(share)) if _built_at.z != INF else 0.0

## The width of the arcs' dark casing on the screen (px).
func casing_px() -> float:
	return _px_per_km * _built_at.z * CASING if _built_at.z != INF else 0.0

## One frame: `on` while the people are not drawn as figures, `centre` the
## ground in the middle of the view (world km), `view_km` its width.
func step(on: bool, centre: Vector2, view_km: float) -> void:
	var can := people.has_method("ask_goods")
	visible = shown and can and view_km <= VIEW_MAX_KM and not _flows.is_empty()
	if shown and on and can and view_km <= VIEW_MAX_KM:
		_ask(centre, view_km)
	else:
		_asked = false
		_asked_at = Vector3.INF
	if not visible:
		return
	var h: float = terrain.level_h if "level_h" in terrain else 1.0
	var rezoom := _built_at.x == INF or absf(log(view_km / _built_at.z)) > 0.15 or absf(h - _built_h) > 0.05 * maxf(_built_h, 0.001)
	if _dirty or rezoom:
		_dirty = false
		_built_at = Vector3(centre.x, centre.y, view_km)
		_built_h = h
		_build(view_km)
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var at := _at(centre, view_km)
			_px_per_km = camera.unproject_position(at - Vector3(0.5, 0.0, 0.0)).distance_to(camera.unproject_position(at + Vector3(0.5, 0.0, 0.0)))
		changed.emit()

func _ask(centre: Vector2, view_km: float) -> void:
	if _asked:
		var g: Dictionary = people.take_goods()
		if not g.is_empty():
			_asked = false
			_take(g)
		return
	var day: int = people.day()
	var moved := _asked_at.x == INF or Vector2(_asked_at.x, _asked_at.y).distance_to(centre) > view_km * 0.25 \
		or absf(log(view_km / _asked_at.z)) > 0.3
	if day != _asked_day or moved:
		var half := view_km * 0.75
		people.ask_goods(centre.x - half, centre.y - half, centre.x + half, centre.y + half)
		_asked = true
		_asked_day = day
		_asked_at = Vector3(centre.x, centre.y, view_km)

## The moves of the answer summed by pair of markets and good.
func _take(g: Dictionary) -> void:
	var by := {}
	for list in [g.get("grain_moves", PackedFloat32Array()), g.get("moves", PackedFloat32Array())]:
		var m: PackedFloat32Array = list
		for k in m.size() / MOVE_STRIDE:
			var o := k * MOVE_STRIDE
			var from := Vector2(m[o], m[o + 1])
			var to := Vector2(m[o + 2], m[o + 3])
			var kind := int(m[o + 4])
			var key := "%d:%d:%d:%d:%d" % [int(from.x * 10.0), int(from.y * 10.0), int(to.x * 10.0), int(to.y * 10.0), kind]
			if not by.has(key):
				by[key] = {"from": from, "to": to, "good": kind, "units": 0.0}
			by[key].units += m[o + 5]
	_all.clear()
	for f in by.values():
		if f.units > 0.0 and f.from.distance_to(f.to) > 0.5:
			_all.append(f)
	_pick()

## The largest flows of the good chosen.
func _pick() -> void:
	var flows: Array[Dictionary] = []
	for f in _all:
		if f.good == good:
			flows.append(f)
	flows.sort_custom(func(a, b): return a.units > b.units)
	flows.resize(mini(flows.size(), SHOWN_MAX))
	if flows != _flows:
		_flows = flows
		_dirty = true
		changed.emit()

## The arcs and dots as one mesh, the largest arc first so the small lie
## over it, each in its casing; the dots last. UV.y runs across an arc
## (-1 … 1) for its soft edge; arrowheads and dots fill to it.
func _build(view_km: float) -> void:
	if _flows.is_empty():
		mesh = null
		return
	var most := sqrt(_flows[0].units)
	var through := {} # market -> units through it
	for f in _flows:
		through[f.from] = through.get(f.from, 0.0) + f.units
		through[f.to] = through.get(f.to, 0.0) + f.units
	var busiest := 0.0
	for p in through:
		busiest = maxf(busiest, sqrt(through[p]))
	var radius := func(p: Vector2) -> float: return view_km * lerpf(DOT_MIN, DOT_MAX, sqrt(through[p]) / maxf(busiest, 0.001))
	var colour: Color = COLOURS.get(good, COLOURS[GRAIN])
	var rim := view_km * CASING
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in _flows:
		var w := view_km * lerpf(WIDTH_MIN, WIDTH_MAX, sqrt(f.units) / most)
		var gap_a: float = radius.call(f.from)
		var gap_b: float = radius.call(f.to)
		_arc(st, f.from, f.to, w + rim * 2.0, gap_a, gap_b, INK, view_km, w + rim * 2.0 - w)
		_arc(st, f.from, f.to, w, gap_a, gap_b, colour, view_km, 0.0)
	for p in through:
		var r: float = radius.call(p)
		_dot(st, p, r + rim, INK, view_km)
		_dot(st, p, r, DOT, view_km)
		_dot(st, p, r * 0.45, colour.darkened(0.25), view_km)
	mesh = st.commit()

## One arc from the dot at `a` to the dot at `b` (`gap_a`, `gap_b` their
## radii): a ribbon `w` wide along a curve bowed to the right of the way,
## ending in an arrowhead at `b`; `grow` widens the arrowhead for a casing.
func _arc(st: SurfaceTool, a: Vector2, b: Vector2, w: float, gap_a: float, gap_b: float, colour: Color, view_km: float, grow: float) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var bow := a.lerp(b, 0.5) + Vector2(-dir.y, dir.x) * length * BOW
	var head := (w - grow) * ARROW_LONG + grow
	var t0 := clampf(gap_a / length, 0.0, 0.3)
	var t1 := clampf(1.0 - (gap_b + head) / length, t0 + 0.1, 1.0)
	var tip_t := clampf(1.0 - gap_b / length, t1, 1.0)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for s in SEGMENTS + 1:
		var t := lerpf(t0, t1, float(s) / SEGMENTS)
		var p := _bezier(a, bow, b, t)
		var n := _side(a, bow, b, t)
		var l := _at(p - n * w * 0.5, view_km)
		var r := _at(p + n * w * 0.5, view_km)
		if s > 0:
			for q in [[prev_l, -1.0], [prev_r, 1.0], [r, 1.0], [prev_l, -1.0], [r, 1.0], [l, -1.0]]:
				_vertex(st, q[0], q[1], colour)
		prev_l = l
		prev_r = r
	# the arrowhead, from the end of the ribbon to just before the dot
	var base := _bezier(a, bow, b, t1)
	var n1 := _side(a, bow, b, t1)
	var half := (w - grow) * ARROW_WIDE * 0.5 + grow * 0.5
	var tip := _bezier(a, bow, b, tip_t)
	for q in [base - n1 * half, base + n1 * half, tip]:
		_vertex(st, _at(q, view_km), 0.0, colour)

## A flat dot of radius `r` at `p`.
func _dot(st: SurfaceTool, p: Vector2, r: float, colour: Color, view_km: float) -> void:
	var centre := _at(p, view_km)
	var n := 20
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		_vertex(st, centre, 0.0, colour)
		_vertex(st, _at(p + Vector2(cos(a0), sin(a0)) * r, view_km), 0.0, colour)
		_vertex(st, _at(p + Vector2(cos(a1), sin(a1)) * r, view_km), 0.0, colour)

func _vertex(st: SurfaceTool, v: Vector3, across: float, colour: Color) -> void:
	st.set_color(colour)
	st.set_uv(Vector2(0.0, across))
	st.add_vertex(v)

func _at(p: Vector2, view_km: float) -> Vector3:
	return Vector3(p.x, terrain.ground_y(p) + view_km * LIFT_KM, p.y)

static func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a * (1.0 - t) * (1.0 - t) + c * 2.0 * (1.0 - t) * t + b * t * t

## The unit normal of the curve at `t`.
static func _side(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var d := (c - a) * 2.0 * (1.0 - t) + (b - c) * 2.0 * t
	d = d.normalized()
	return Vector2(-d.y, d.x)
