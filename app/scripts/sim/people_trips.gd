extends MultiMeshInstance3D
## Carriers and wagons on their way (Ramon, 29.10.2026: people about the
## map, driven by the economy). ApoleiaPeople.ask_trips(window) lists the
## trips under way whose route touches the view (sim/godot/src/trips.rs):
## farm folk with a donkey to the market and home again (kind 0 a sale, the
## sacks on the way there; 1 a purchase, the sacks on the way home) and
## traders with an ox cart between markets (2 export, loaded on the way
## out; 3 import, loaded on the way home), each with its route in world km
## (the footpath tile by tile, the trade road from cell to cell).
##
## Hired hands (ApoleiaPeople.ask_work, the last weekly labour exchange of
## each region) walk from their home to the farm they work on and back,
## with a sickle at the harvest, a seed basket at the sowing and a hoe
## through the year.
##
## At the end of the way they stay a while (LINGER_S): at the market among
## the stalls, at the farm at work. The market squares get standing stalls
## (ApoleiaPeople.market_squares, the squares the terrain draws), STALLS
## each, turned towards the middle (r11: the square was a flat decal).
##
## A trip new to the list becomes a traveller that walks its route at a
## pace the eye can follow, whatever the days per second (at ten days a
## second a walk to market lasts a tenth of a second): it starts where the
## sim has it now, comes into view where a long road enters it, and walks
## on until its route ends or it leaves the view. At most MAX at once; the
## list is asked for once a sim day and again when the view moves away.
## Drawn up close, with the figures (people_dots.gd FIGURE_KM), by
## people_walkers.gdshader, which walks each one along the stretch of its
## route it is on: a traveller is written to the MultiMesh only when it
## starts a stretch, stops or turns, not every frame (Mac tour, 29.10.2026:
## moving 300 of them each frame in GDScript took a millisecond or more).

const SHADER = preload("res://shaders/people_walkers.gdshader")
const VoxelMesh = preload("res://scripts/voxel/voxel_mesh.gd")
const MAX := 300 # travellers at once
const WALK_KMPS := 0.05 # on screen, world km a second: a body height (40 m at diorama scale) and a quarter
const CART_KMPS := 0.04
const MARGIN := 0.3 # the window asked for reaches this share of the view width beyond it
const FIGURE_M := 1.7 # the person, as people_dots.gd FIGURE_M
const LANE_KM := 0.09 # travellers on one route keep apart sideways within this width (a figure is 40 m at diorama scale)
const STAGGER_KM := 0.2 # and along it, as many leave on the same day
## parts beyond the person (bits of INSTANCE_CUSTOM.r, people_walkers.gdshader)
const DONKEY := 1
const SACKS := 2
const CART := 4
const OX := 8
const LOAD := 16
const SICKLE := 32
const BASKET := 64
const HOE := 128
const TOOLS: Array[int] = [BASKET, SICKLE, HOE, HOE] # by kind of work: sowing, harvest, through the year, from a surplus
const STALL := 256
const STRIDE := 16 # floats per instance in the MultiMesh buffer: a 3 x 4 transform, then the custom data
const LINGER_S := 6.0 # seconds a traveller stays at the end of its way
## how an instance moves (INSTANCE_CUSTOM.a): walking, standing, a stall
const WALKING := 0.0
const STANDING := 1.0
const STANDS := 2.0
const SQUARES_MAX := 40
## stalls round a market square (km from its middle; the square is 0.32 km)
const STALLS: Array[Vector2] = [Vector2(-0.085, -0.07), Vector2(0.0, -0.095), Vector2(0.085, -0.07),
	Vector2(-0.095, 0.03), Vector2(0.095, 0.03), Vector2(-0.04, 0.095), Vector2(0.05, 0.095)]
const SQUARES_KM := 10.0 # stalls only in views up to this width, as the squares

var people: RefCounted
var _able := false # an older build of the GDExtension has no trips
var material := ShaderMaterial.new()
var _walkers: Array[Dictionary] = []
var _listed := {} # ids of the trips in the last list, so a trip is walked once
var _hired := {} # worker and exchange day of the hires in the last list, likewise
var _asked := false
var _asked_work := false
var _asked_day := -1
var _asked_at := Vector3.INF # centre x, z and view width of the last ask
var _window := Rect2()
var _squares := PackedVector2Array() # market squares in and around the view
var _buffer := PackedFloat32Array() # the stalls first, then the travellers in the order of _walkers
var _clock := 0.0 # seconds walked (people_walkers.gdshader walk_clock)
var _next := INF # clock time of the next stop or turn of any traveller
var _dirty := false # _buffer changed since it was last handed over

func setup(sim: RefCounted, km_per_m: float) -> void:
	people = sim
	_able = sim.has_method("ask_trips")
	name = "PeopleTrips"
	material.shader = SHADER
	material.set_shader_parameter("km_per_m", km_per_m)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON # like the figures
	custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh()
	mm.instance_count = MAX + SQUARES_MAX * STALLS.size()
	mm.visible_instance_count = 0
	multimesh = mm
	_buffer.resize((MAX + SQUARES_MAX * STALLS.size()) * STRIDE)

## One frame: `on` while the figures are drawn, `centre` the ground in the
## middle of the view (world km), `view_km` its width.
func step(delta: float, on: bool, centre: Vector2, view_km: float) -> void:
	visible = on and _able
	if not visible:
		_walkers.clear()
		_listed.clear()
		_hired.clear()
		_asked_at = Vector3.INF
		_next = INF
		return
	_clock += delta
	var half := view_km * (0.5 + MARGIN)
	_window = Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0)
	if _asked_work:
		var hires: Dictionary = people.take_work()
		if not hires.is_empty():
			_asked_work = false
			_take_work(hires)
	if _asked:
		var answer: Dictionary = people.take_trips()
		if not answer.is_empty():
			_asked = false
			_take(answer)
	elif not _asked_work:
		var day: int = people.day()
		var moved := _asked_at.x == INF or Vector2(_asked_at.x, _asked_at.y).distance_to(centre) > view_km * 0.25 \
			or absf(log(view_km / _asked_at.z)) > 0.3
		if day != _asked_day or moved:
			people.ask_trips(_window.position.x, _window.position.y, _window.end.x, _window.end.y)
			people.ask_work(_window.position.x, _window.position.y, _window.end.x, _window.end.y)
			_asked = true
			_asked_work = true
			_asked_day = day
			_asked_at = Vector3(centre.x, centre.y, view_km)
			var squares := PackedVector2Array()
			if view_km <= SQUARES_KM:
				var n := int(ceil(_window.size.x / 1.5625)) + 2 # fine tiles across the window
				for q in people.market_squares(centre.x, centre.y, n):
					if _window.has_point(q) and squares.size() < SQUARES_MAX:
						squares.append(q)
			if squares != _squares:
				_squares = squares
				_write_all() # the travellers move up or down behind the stalls
	if _clock >= _next:
		_events()
	material.set_shader_parameter("walk_clock", _clock)
	if _dirty:
		_dirty = false
		multimesh.buffer = _buffer
		multimesh.visible_instance_count = _squares.size() * STALLS.size() + _walkers.size()

func _take(t: Dictionary) -> void:
	var ids: PackedInt64Array = t.id
	var listed := {}
	for i in ids.size():
		listed[ids[i]] = true
		if _listed.has(ids[i]) or _walkers.size() >= MAX:
			continue
		var w := _traveller(t, i)
		if not w.is_empty():
			_add(w)
	_listed = listed

## Each hire new to the list sends its worker from home to the farm and
## back, in a straight line (both are fine tiles, a few km apart at most).
func _take_work(h: Dictionary) -> void:
	var worker: PackedInt64Array = h.worker
	var day: PackedInt64Array = h.day
	var kind: PackedInt32Array = h.kind
	var from: PackedVector2Array = h.from
	var to: PackedVector2Array = h.to
	var hired := {}
	for i in worker.size():
		var key := Vector2i(worker[i], day[i])
		hired[key] = true
		if _hired.has(key) or _walkers.size() >= MAX / 2 or from[i].distance_to(to[i]) < 0.05: # half stays for the trips
			continue
		var w := {
			"points": PackedVector2Array([from[i], to[i]]),
			"along": PackedFloat32Array([0.0, from[i].distance_to(to[i])]),
			"s": 0.0, "dir": 1.0, "turn": true, "cart": false, "cargo": false, "out": false,
			"phase": fposmod(float(worker[i]) * 0.618034, 1.0), "tint": int(worker[i] % 8),
			"side": (fposmod(float(worker[i]) * 0.377, 1.0) - 0.5) * LANE_KM,
			"tool": TOOLS[clampi(kind[i], 0, TOOLS.size() - 1)],
		}
		if not _window.has_point(from[i]):
			if not _window.has_point(to[i]):
				continue
			w.s = w.along[1] # seen at the farm, walking home
			w.dir = -1.0
			w.turn = false
		_add(w)
	_hired = hired

## Trip i of the list as a traveller, placed where the sim has it today, or
## {} when no part of its way lies in the view.
func _traveller(t: Dictionary, i: int) -> Dictionary:
	var first: int = t.first[i]
	var count: int = t.count[i]
	if count < 2:
		return {}
	var points: PackedVector2Array = t.points.slice(first, first + count)
	var along := PackedFloat32Array([0.0])
	for k in range(1, count):
		along.append(along[k - 1] + points[k].distance_to(points[k - 1]))
	var length := along[count - 1]
	if length <= 0.0:
		return {}
	var day := float(t.day)
	var depart: float = t.depart[i]
	var arrive: float = t.arrive[i]
	var home: float = t.home[i]
	var returns: bool = home > arrive or bool(t.back[i])
	var homeward := day >= arrive and returns
	var share := clampf((day - arrive) / maxf(home - arrive, 0.001), 0.0, 1.0) if homeward \
		else clampf((day - depart) / maxf(arrive - depart, 0.001), 0.0, 1.0)
	var kind: int = t.kind[i]
	var pid: int = t.pid[i]
	var w := {
		"points": points, "along": along,
		"s": length * (1.0 - share if homeward else share),
		"dir": -1.0 if homeward else 1.0,
		"turn": returns and not homeward, # walks home at the end of the way there
		"cart": kind >= 2,
		"cargo": int(t.cargo_kg[i]) > 0,
		"out": kind == 0 or kind == 2, # loaded on the way there (a sale, an export), else on the way home
		"phase": fposmod(float(pid) * 0.618034, 1.0),
		"tint": pid % 8,
		"side": (fposmod(float(pid) * 0.377, 1.0) - 0.5) * LANE_KM,
	}
	w.s = clampf(w.s + (fposmod(float(pid) * 0.123, 1.0) - 0.5) * STAGGER_KM, 0.0, length)
	# a long road comes into view somewhere along it: start there
	if not _window.has_point(_at(w)[0]):
		var k := along.bsearch(w.s)
		var step := 1 if w.dir > 0.0 else -1
		var entry := -1
		while k >= 0 and k < count:
			if _window.has_point(points[k]):
				entry = k
				break
			k += step
		if entry < 0:
			return {}
		w.s = along[entry]
	return w

## Where traveller w is (world km) and which way it faces.
static func _at(w: Dictionary) -> Array:
	var along: PackedFloat32Array = w.along
	var points: PackedVector2Array = w.points
	var k := clampi(along.bsearch(w.s) - 1, 0, along.size() - 2)
	var seg := along[k + 1] - along[k]
	var f := clampf((w.s - along[k]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
	var d: Vector2 = (points[k + 1] - points[k]) * w.dir
	return [points[k].lerp(points[k + 1], f), d.normalized() if d.length() > 0.0 else Vector2(0.0, 1.0)]

## A new traveller on the stretch of its route where it is.
func _add(w: Dictionary) -> void:
	_walkers.append(w)
	_start(w, _clock)
	_write(_walkers.size() - 1)
	_next = minf(_next, w.until)

## Sets w walking from w.s on the stretch it is on, from clock time t.
func _start(w: Dictionary, t: float) -> void:
	var along: PackedFloat32Array = w.along
	var points: PackedVector2Array = w.points
	var last := along.size() - 2
	var k := clampi(along.bsearch(w.s, w.dir < 0.0) - 1, 0, last)
	var a := points[k]
	var b := points[k + 1]
	var seg := along[k + 1] - along[k]
	var f := clampf((w.s - along[k]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
	var d: Vector2 = (b - a) * w.dir
	d = d.normalized() if d.length() > 0.0 else w.get("d", Vector2(0.0, 1.0))
	var left: float = along[k + 1] - w.s if w.dir > 0.0 else w.s - along[k]
	var speed: float = CART_KMPS if w.cart else WALK_KMPS
	w.k = k
	w.d = d
	w.at = a.lerp(b, f) + Vector2(-d.y, d.x) * float(w.side) # its own lane
	w.velocity = d * speed
	w.t0 = t
	w.walk = maxf(left, 0.0) / speed
	w.until = t + w.walk
	w.wait = 0.0

## Lets every traveller whose stretch or stay has ended go on: the next
## stretch, a stay at the end of the way, the way home, or gone.
func _events() -> void:
	_next = INF
	var i := 0
	while i < _walkers.size():
		var w := _walkers[i]
		var changed := false
		var gone := false
		while w.until <= _clock and not gone:
			changed = true
			var t: float = w.until
			if w.wait > 0.0: # the stay is over: home again, or gone
				if w.turn:
					w.turn = false
					w.dir = -1.0
					_start(w, t)
				else:
					gone = true
				continue
			var along: PackedFloat32Array = w.along
			w.s = along[w.k + 1] if w.dir > 0.0 else along[w.k]
			var points: PackedVector2Array = w.points
			var here: Vector2 = points[w.k + 1] if w.dir > 0.0 else points[w.k]
			if w.dir > 0.0 and w.k + 1 >= along.size() - 1:
				# at the market or at work: it stays a while
				w.at = here + Vector2(-w.d.y, w.d.x) * float(w.side)
				w.velocity = Vector2.ZERO
				w.t0 = t
				w.walk = 0.0
				w.wait = LINGER_S
				w.until = t + LINGER_S
			elif w.dir < 0.0 and w.k <= 0:
				gone = true # home
			elif not _window.has_point(here):
				gone = true # out of view
			else:
				_start(w, t) # the next stretch (_start finds it from the end of this one)
		if gone:
			var last: Dictionary = _walkers[_walkers.size() - 1]
			_walkers[i] = last
			_walkers.pop_back()
			if i < _walkers.size():
				_write(i)
			_dirty = true
			continue
		if changed:
			_write(i)
		_next = minf(_next, w.until)
		i += 1

## Traveller i into the buffer, behind the stalls.
func _write(i: int) -> void:
	var w := _walkers[i]
	var d: Vector2 = w.d
	var p: Vector2 = w.at
	var v: Vector2 = w.velocity
	var loaded: bool = w.cargo and (w.out == (w.dir > 0.0))
	var parts: int = (CART | OX | (LOAD if loaded else 0)) if w.cart else (DONKEY | (SACKS if loaded else 0))
	if w.has("tool"):
		parts = w.tool
	# turned about y so the model's front (+z) faces d; the velocity and
	# start time ride in the middle row (people_walkers.gdshader)
	var o := (_squares.size() * STALLS.size() + i) * STRIDE
	_buffer[o] = d.y; _buffer[o + 1] = 0.0; _buffer[o + 2] = d.x; _buffer[o + 3] = p.x
	_buffer[o + 4] = v.x; _buffer[o + 5] = 1.0; _buffer[o + 6] = v.y; _buffer[o + 7] = w.t0
	_buffer[o + 8] = -d.x; _buffer[o + 9] = 0.0; _buffer[o + 10] = d.y; _buffer[o + 11] = p.y
	_buffer[o + 12] = float(parts); _buffer[o + 13] = w.walk; _buffer[o + 14] = float(w.tint) + w.phase * 0.999
	_buffer[o + 15] = STANDING if w.wait > 0.0 else WALKING
	_dirty = true

## The stalls and then every traveller, when the squares changed.
func _write_all() -> void:
	var n := 0
	for q in _squares:
		for k in STALLS.size():
			var at: Vector2 = q + STALLS[k]
			var d := -STALLS[k].normalized() # the counter towards the middle
			var o := n * STRIDE
			_buffer[o] = d.y; _buffer[o + 1] = 0.0; _buffer[o + 2] = d.x; _buffer[o + 3] = at.x
			_buffer[o + 4] = 0.0; _buffer[o + 5] = 1.0; _buffer[o + 6] = 0.0; _buffer[o + 7] = 0.0
			_buffer[o + 8] = -d.x; _buffer[o + 9] = 0.0; _buffer[o + 10] = d.y; _buffer[o + 11] = at.y
			_buffer[o + 12] = float(STALL); _buffer[o + 13] = 0.0; _buffer[o + 14] = float(k); _buffer[o + 15] = STANDS
			n += 1
	for i in _walkers.size():
		_write(i)
	_dirty = true

# ------------------------------------------------------------------ mesh

## Everyone who travels in one mesh, in metres, the model's front +z: the
## person (part 0) at the origin, a donkey beside them (1) with its sacks
## (2), or an ox (4) in front of a cart (3) with its load (5) on their right;
## or the tool of a hired hand: a sickle in the right hand (6), a seed
## basket in the left (7), a hoe on the shoulder (8); or a market stall
## (9), standing alone, its counter to the front.
static func _mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.77, 0.55, 0.41)
	var hair := Color(0.26, 0.17, 0.1)
	var sandal := Color(0.36, 0.24, 0.15)
	var f := FIGURE_M
	# the person, as people_dots.gd draws the figures, walking: a tunic to
	# the knee with short sleeves (with bare legs and arms to the shoulder
	# the first walkers read as naked from 1 km)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(0.075 * side, 0.02, 0.02) * f, Vector3(0.05, 0.02, 0.07) * f, sandal, 0, side, 0.48 * f)
		_box(st, Vector3(0.075 * side, 0.21, 0.0) * f, Vector3(0.05, 0.17, 0.05) * f, skin, 0, side, 0.48 * f)
		_box(st, Vector3(0.2 * side, 0.55, 0.0) * f, Vector3(0.05, 0.09, 0.05) * f, skin, 0, -side * 0.6, 0.78 * f)
		_box(st, Vector3(0.2 * side, 0.71, 0.0) * f, Vector3(0.055, 0.07, 0.055) * f, Color.WHITE, 0, -side * 0.6, 0.78 * f)
	_box(st, Vector3(0.0, 0.59, 0.0) * f, Vector3(0.15, 0.21, 0.1) * f, Color.WHITE, 0)
	_box(st, Vector3(0.0, 0.9, 0.0) * f, Vector3(0.08, 0.08, 0.08) * f, skin, 0)
	_box(st, Vector3(0.0, 0.975, -0.01) * f, Vector3(0.088, 0.025, 0.088) * f, hair, 0)
	_box(st, Vector3(0.0, 0.9, -0.072) * f, Vector3(0.088, 0.06, 0.025) * f, hair, 0)
	# a donkey on the person's right, a little ahead
	var grey := Color(0.5, 0.45, 0.4)
	var pale := Color(0.74, 0.7, 0.64)
	var o := Vector3(0.8, 0.0, 0.35)
	_box(st, o + Vector3(0.0, 0.85, 0.0), Vector3(0.18, 0.2, 0.5), grey, 1)
	for leg in [Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, -1)]:
		_box(st, o + Vector3(0.12 * leg.x, 0.33, 0.38 * leg.z), Vector3(0.06, 0.33, 0.06), grey, 1, leg.x * leg.z, 0.66)
	_box(st, o + Vector3(0.0, 1.08, 0.5), Vector3(0.1, 0.18, 0.12), grey, 1)
	_box(st, o + Vector3(0.0, 1.15, 0.72), Vector3(0.1, 0.1, 0.18), grey, 1)
	_box(st, o + Vector3(0.0, 1.08, 0.88), Vector3(0.09, 0.07, 0.06), pale, 1)
	for side in [-1.0, 1.0]:
		_box(st, o + Vector3(0.06 * side, 1.38, 0.62), Vector3(0.03, 0.12, 0.03), grey, 1)
	_box(st, o + Vector3(0.0, 0.85, -0.55), Vector3(0.03, 0.15, 0.03), hair, 1)
	var sack := Color(0.76, 0.67, 0.48)
	for side in [-1.0, 1.0]:
		_box(st, o + Vector3(0.27 * side, 0.95, 0.0), Vector3(0.1, 0.17, 0.25), sack, 2)
	_box(st, o + Vector3(0.0, 1.12, 0.0), Vector3(0.16, 0.08, 0.2), sack, 2)
	# a pale ox in front of a cart, the person walking at its head
	var ox := Color(0.8, 0.75, 0.66)
	var horn := Color(0.88, 0.85, 0.74)
	o = Vector3(1.0, 0.0, 0.9)
	_box(st, o + Vector3(0.0, 1.0, 0.0), Vector3(0.32, 0.32, 0.75), ox, 4)
	for leg in [Vector3(-1, 0, 1), Vector3(1, 0, 1), Vector3(-1, 0, -1), Vector3(1, 0, -1)]:
		_box(st, o + Vector3(0.2 * leg.x, 0.38, 0.55 * leg.z), Vector3(0.08, 0.38, 0.08), ox, 4, leg.x * leg.z, 0.76)
	_box(st, o + Vector3(0.0, 1.05, 0.9), Vector3(0.17, 0.17, 0.2), ox, 4)
	for side in [-1.0, 1.0]:
		_box(st, o + Vector3(0.25 * side, 1.25, 0.85), Vector3(0.12, 0.03, 0.03), horn, 4)
	var wood := Color(0.5, 0.36, 0.22)
	var dark := Color(0.32, 0.23, 0.15)
	o = Vector3(1.0, 0.0, -1.7)
	_box(st, o + Vector3(0.0, 0.75, 0.0), Vector3(0.6, 0.06, 1.0), wood, 3)
	for side in [-1.0, 1.0]:
		_box(st, o + Vector3(0.6 * side, 0.95, 0.0), Vector3(0.04, 0.16, 1.0), dark, 3)
		_box(st, o + Vector3(0.0, 0.95, 1.0 * side), Vector3(0.6, 0.16, 0.04), dark, 3)
		_box(st, o + Vector3(0.68 * side, 0.45, -0.1), Vector3(0.05, 0.45, 0.45), dark, 3)
	_box(st, o + Vector3(0.0, 0.8, 1.55), Vector3(0.04, 0.04, 0.55), wood, 3)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			_box(st, o + Vector3(0.28 * side, 1.02, 0.45 * end), Vector3(0.22, 0.2, 0.3), sack, 5)
	# the tools swing with the arm that holds them
	var iron := Color(0.62, 0.62, 0.6)
	_box(st, Vector3(0.2, 0.43, 0.03) * f, Vector3(0.02, 0.05, 0.02) * f, wood, 6, -0.6, 0.78 * f)
	_box(st, Vector3(0.2, 0.37, 0.1) * f, Vector3(0.015, 0.018, 0.07) * f, iron, 6, -0.6, 0.78 * f)
	_box(st, Vector3(0.2, 0.42, 0.16) * f, Vector3(0.015, 0.05, 0.015) * f, iron, 6, -0.6, 0.78 * f)
	_box(st, Vector3(-0.24, 0.5, 0.06) * f, Vector3(0.08, 0.06, 0.08) * f, Color(0.66, 0.52, 0.3), 7, 0.6, 0.78 * f)
	_box(st, Vector3(-0.24, 0.565, 0.06) * f, Vector3(0.065, 0.01, 0.065) * f, Color(0.84, 0.76, 0.52), 7, 0.6, 0.78 * f)
	_box(st, Vector3(0.14, 0.83, -0.1) * f, Vector3(0.018, 0.018, 0.45) * f, wood, 8)
	_box(st, Vector3(0.14, 0.77, -0.54) * f, Vector3(0.05, 0.06, 0.015) * f, iron, 8)
	# a stall: a counter under a striped awning on four posts, wares on it
	# (the Forum's stalls: awning #d46048, frame #804c28)
	var frame := Color("804c28")
	var awning := Color("d46048")
	var linen := Color(0.94, 0.9, 0.82)
	_box(st, Vector3(0.0, 0.5, 0.45), Vector3(1.25, 0.5, 0.35), frame, 9)
	for x in [-1.2, 1.2]:
		for z in [-0.75, 0.75]:
			_box(st, Vector3(x, 1.15, z), Vector3(0.07, 1.15, 0.07), frame.darkened(0.25), 9)
	for k in 4:
		_box(st, Vector3(-0.96 + k * 0.64, 2.36, 0.0), Vector3(0.32, 0.07, 1.0), awning if k % 2 == 0 else linen, 9)
	_box(st, Vector3(-0.7, 1.12, 0.45), Vector3(0.24, 0.12, 0.22), Color(0.76, 0.67, 0.48), 9)
	_box(st, Vector3(0.0, 1.14, 0.45), Vector3(0.14, 0.14, 0.14), Color(0.7, 0.42, 0.28), 9)
	_box(st, Vector3(0.65, 1.08, 0.45), Vector3(0.3, 0.08, 0.22), Color(0.4, 0.55, 0.24), 9)
	st.index() # each corner shaded once, not once per triangle
	return st.commit()

## An axis-aligned box around `centre` with half extents `half` (m) of `part`
## (UV.x); a leg also gets its side (UV2.x, the swing's sign and share) and
## hip height (UV2.y). The side faces darken towards the bottom like a voxel
## model's corner shading (VoxelMesh.AO), kept in the vertex alpha.
static func _box(st: SurfaceTool, centre: Vector3, half: Vector3, colour: Color, part: int, swing := 0.0, hip := 0.0) -> void:
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
				st.set_color(Color(colour.r, colour.g, colour.b, ao))
				st.set_uv(Vector2(part, 0))
				st.set_uv2(Vector2(swing, hip))
				st.set_normal(n)
				st.add_vertex(v)
