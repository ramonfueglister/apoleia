extends MeshInstance3D
## From further up, where the people are no longer figures: what the dealers
## carried between the markets in the last 28 days (Ramon, 30.10.2026:
## "Wuselfaktor", "alles aus der Simulation"), one arc per pair of markets
## and kind, grain in gold and each craft good in the colour of its wares on
## the stalls (people_walkers.gdshader WARES), as wide as the root of what
## went along it and with dashes running from the market it came from to the
## one it went to. ApoleiaPeople.ask_goods "grain_moves" (S114, the dealers
## fetching grain) and "moves" (S111, craft goods), the same answer the
## carts up close come from (people_trips.gd); asked once a sim day while
## the figures are not drawn, so the two never ask at once.
## The arcs are built on the CPU (ground height from the terrain) only when
## the answer or the zoom changed, drawn by people_flows.gdshader.

const SHADER = preload("res://shaders/people_flows.gdshader")
const MOVE_STRIDE := 7 # from x, z, to x, z, good, units, day (trips.rs goods_to_dict)
const SEGMENTS := 16 # per arc
const PAIRS_MAX := 400 # arcs at most, the largest first
const LIFT := 0.12 # height of an arc's middle over the ground, of its length
const WIDTH_MIN := 0.0012 # of the view width, the thinnest arc
const WIDTH_MAX := 0.006 # and the widest
const VIEW_MAX_KM := 2000.0 # not drawn from further up
const GRAIN := 255 # the good of a grain move
const GOOD_NAMES: Array[String] = ["Wolle", "Eisen", "Kleidung", "Werkzeug", "Keramik", "Schweinefleisch"]
## sRGB, as people_walkers.gdshader WARES: the craft goods, then grain
const COLOURS: Array[Color] = [Color(0.9, 0.87, 0.78), Color(0.55, 0.57, 0.62), Color(0.72, 0.26, 0.2),
	Color(0.6, 0.45, 0.3), Color(0.8, 0.45, 0.28), Color(0.85, 0.5, 0.46), Color(0.92, 0.76, 0.36)]

var people: RefCounted
var terrain: Node3D
var material := ShaderMaterial.new()
var _asked := false
var _asked_day := -1
var _asked_at := Vector3.INF # centre x, z and view width of the last ask
var _flows: Array[Dictionary] = [] # {"from", "to", "good", "units"} summed over the 28 days, largest first
var _built_at := Vector3.INF # centre and width the arcs were last built for
var _built_h := 0.0 # the terrain's level height then
var _dirty := false

func setup(sim: RefCounted, tile_terrain: Node3D) -> void:
	people = sim
	terrain = tile_terrain
	name = "PeopleFlows"
	material.shader = SHADER
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	visible = false

## One frame: `on` while the people are not drawn as figures, `centre` the
## ground in the middle of the view (world km), `view_km` its width.
func step(on: bool, centre: Vector2, view_km: float) -> void:
	visible = on and view_km <= VIEW_MAX_KM and people.has_method("ask_goods") and not _flows.is_empty()
	if not on or view_km > VIEW_MAX_KM or not people.has_method("ask_goods"):
		_asked = false
		_asked_at = Vector3.INF
		return
	if _asked:
		var g: Dictionary = people.take_goods()
		if not g.is_empty():
			_asked = false
			_take(g)
	else:
		var day: int = people.day()
		var moved := _asked_at.x == INF or Vector2(_asked_at.x, _asked_at.y).distance_to(centre) > view_km * 0.25 \
			or absf(log(view_km / _asked_at.z)) > 0.3
		if day != _asked_day or moved:
			var half := view_km * 0.75
			people.ask_goods(centre.x - half, centre.y - half, centre.x + half, centre.y + half)
			_asked = true
			_asked_day = day
			_asked_at = Vector3(centre.x, centre.y, view_km)
	var h: float = terrain.level_h if "level_h" in terrain else 1.0
	var rezoom := _built_at.x == INF or absf(log(view_km / _built_at.z)) > 0.15 or absf(h - _built_h) > 0.05 * maxf(_built_h, 0.001)
	if _dirty or rezoom:
		_dirty = false
		_built_at = Vector3(centre.x, centre.y, view_km)
		_built_h = h
		_build(view_km)

## The moves of the answer summed by pair of markets and good, the largest
## first (by the root of their units: grain in kg, the crafts in pieces).
func _take(g: Dictionary) -> void:
	var by := {}
	for list in [g.get("grain_moves", PackedFloat32Array()), g.get("moves", PackedFloat32Array())]:
		var m: PackedFloat32Array = list
		for k in m.size() / MOVE_STRIDE:
			var o := k * MOVE_STRIDE
			var from := Vector2(m[o], m[o + 1])
			var to := Vector2(m[o + 2], m[o + 3])
			var good := int(m[o + 4])
			var key := "%d:%d:%d:%d:%d" % [int(from.x * 10.0), int(from.y * 10.0), int(to.x * 10.0), int(to.y * 10.0), good]
			if not by.has(key):
				by[key] = {"from": from, "to": to, "good": good, "units": 0.0}
			by[key].units += m[o + 5]
	var flows: Array[Dictionary] = []
	for f in by.values():
		if f.units > 0.0 and f.from.distance_to(f.to) > 0.5:
			flows.append(f)
	flows.sort_custom(func(a, b): return a.units > b.units if (a.good == GRAIN) == (b.good == GRAIN) else a.good == GRAIN)
	flows.resize(mini(flows.size(), PAIRS_MAX))
	if flows != _flows:
		_flows = flows
		_dirty = true

## The arcs as one mesh of flat ribbons: UV.x km along the arc (the dashes
## run with it), UV.y across; each ribbon a little to the right of its way,
## so the two ways between two markets lie side by side.
func _build(view_km: float) -> void:
	if _flows.is_empty():
		mesh = null
		return
	# grain and the crafts each against their own largest (kg and pieces)
	var most := {true: 0.0, false: 0.0}
	for f in _flows:
		most[f.good == GRAIN] = maxf(most[f.good == GRAIN], sqrt(f.units))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in _flows:
		var a: Vector2 = f.from
		var b: Vector2 = f.to
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var side := Vector2(-dir.y, dir.x)
		var share := sqrt(f.units) / maxf(most[f.good == GRAIN], 0.001)
		var w := view_km * lerpf(WIDTH_MIN, WIDTH_MAX, share)
		var colour: Color = COLOURS[6] if f.good == GRAIN else COLOURS[clampi(f.good, 0, 5)]
		var shift := side * w * 0.7 # right of the way
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for s in SEGMENTS + 1:
			var t := float(s) / SEGMENTS
			var p := a.lerp(b, t) + shift
			var y: float = terrain.ground_y(p) + length * LIFT * sin(t * PI)
			var l := Vector3(p.x - side.x * w * 0.5, y, p.y - side.y * w * 0.5)
			var r := Vector3(p.x + side.x * w * 0.5, y, p.y + side.y * w * 0.5)
			if s > 0:
				var t0 := float(s - 1) / SEGMENTS * length
				var t1 := t * length
				for q in [[prev_l, t0, -1.0], [prev_r, t0, 1.0], [r, t1, 1.0], [prev_l, t0, -1.0], [r, t1, 1.0], [l, t1, -1.0]]:
					st.set_color(colour)
					st.set_uv(Vector2(q[1], q[2]))
					st.add_vertex(q[0])
			prev_l = l
			prev_r = r
	mesh = st.commit()
	material.set_shader_parameter("dash_km", view_km * 0.03)
