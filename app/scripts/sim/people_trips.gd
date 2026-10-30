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
## A click on a traveller shows who it is and what they are doing (`pick`,
## people_dots.gd).
##
## The newest events of the simulation (sim/src/events.rs, handed over by
## sim_events.gd `answered`) become scenes on the way (Ramon, 30.10.2026:
## "Wuselfaktor", "alles aus der Simulation"): only what happened, where
## the sim has it. A household that moves or joins relatives pulls a
## handcart from the 25 km cell it left towards the one it goes to (the
## event knows only the cells, so the way runs from middle to middle); a
## household that goes to the tents, or a tent household that moves to
## another market, carries its bundles to the market square (where the
## tents are: the household's fine tile is the market's); alms are fetched
## with a bowl at the market square; a thief walks from the market square
## to the farm robbed (its farmstead is known) and back with a sack; a
## hunger death leaves the market square nearest its cell as a funeral, the
## dead on a bier, towards the graves outside the town (the event knows only
## the cell, not the house); a family takes over a free farm, an heir moves
## onto his share, a farm cleared under the Lex Manciana gets its clearer
## with an axe, and a family that gives up its farm leaves it with its cart.
## Scenes are made for events of the last SCENE_DAYS only, each once, at
## most SCENES_MAX walkers beside the trips; a click names the event.

const SHADER = preload("res://shaders/people_walkers.gdshader")
const SimTables = preload("res://scripts/sim/sim_tables.gd")
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
const WORK_NAMES: Array[String] = ["bei der Aussaat", "bei der Ernte", "über das Jahr", "aus einem Überschuss"] # likewise, for a click
const STALL := 256
const HANDCART := 512 # pulled behind the person, with the household's bundles
const BUNDLE := 1024 # a bundle or sack on the back
const BIER := 2048 # a bier on the shoulders, the dead under a shroud, a second bearer behind
const AXE := 4096 # on the shoulder
const BOWL := 8192 # in the left hand
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
const SCENES_MAX := 80 # walkers of event scenes at once, beyond MAX
const SCENE_DAYS := 2 # events this many days old or newer become scenes; older ones were over before the view came
const GAP_KM := 0.035 # between the members of a group along their way (a figure is 40 m at diorama scale)
const SQUARE_REACH_KM := 20.0 # the market square of a cell event: the nearest one this close to the cell's middle
const OUT_KM := 1.2 # how far from the farm or square a scene's way starts when nothing else says where
## event kinds (sim/src/events.rs)
const EV_HUNGER := 0
const EV_MOVED := 1
const EV_JOINED := 3
const EV_THEFT := 4
const EV_ALMS := 5
const EV_TENT_MOVED := 6
const EV_FARM_TAKEN := 7
const EV_HEIR := 8
const EV_TO_TENT := 9
const EV_MANCIANA := 10
const EV_FARM_LEFT := 11

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
var _scene_seen := {} # the events of the last SCENE_DAYS already played, so each plays once
var _scenes := 0 # walkers of scenes among _walkers
var _square_of := {} # market square (or INF) by 25 km cell of an event, for the scenes

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
	mm.instance_count = MAX + SCENES_MAX + SQUARES_MAX * STALLS.size()
	mm.visible_instance_count = 0
	multimesh = mm
	_buffer.resize((MAX + SCENES_MAX + SQUARES_MAX * STALLS.size()) * STRIDE)

## One frame: `on` while the figures are drawn, `centre` the ground in the
## middle of the view (world km), `view_km` its width.
func step(delta: float, on: bool, centre: Vector2, view_km: float) -> void:
	visible = on and _able
	if not visible:
		_walkers.clear()
		_listed.clear()
		_hired.clear()
		_scene_seen.clear()
		_scenes = 0
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
		if _listed.has(ids[i]) or _walkers.size() - _scenes >= MAX:
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
		if _hired.has(key) or _walkers.size() - _scenes >= MAX / 2 or from[i].distance_to(to[i]) < 0.05: # half stays for the trips
			continue
		var w := {
			"points": PackedVector2Array([from[i], to[i]]),
			"along": PackedFloat32Array([0.0, from[i].distance_to(to[i])]),
			"s": 0.0, "dir": 1.0, "turn": true, "cart": false, "cargo": false, "out": false,
			"phase": fposmod(float(worker[i]) * 0.618034, 1.0), "tint": int(worker[i] % 8),
			"side": (fposmod(float(worker[i]) * 0.377, 1.0) - 0.5) * LANE_KM,
			"tool": TOOLS[clampi(kind[i], 0, TOOLS.size() - 1)],
			# for a click (pick): who it is and what they do
			"worker": worker[i], "farm": h.farm_household[i], "days": h.days[i], "work": kind[i],
		}
		if not _window.has_point(from[i]):
			if not _window.has_point(to[i]):
				continue
			w.s = w.along[1] # seen at the farm, walking home
			w.dir = -1.0
			w.turn = false
		_add(w)
	_hired = hired

## The events of an answer (sim_events.gd `answered`, newest last): each of
## the last SCENE_DAYS not yet played becomes its scene, the newest first.
func take_events(e: Dictionary) -> void:
	if not visible or e.is_empty() or not e.has("day"):
		return
	var days: PackedInt64Array = e.day
	var kinds: PackedInt32Array = e.kind
	var households: PackedInt64Array = e.household
	var pids: PackedInt64Array = e.pid
	var today: int = people.day()
	var seen := {}
	var fresh: Array[int] = []
	for i in range(days.size() - 1, -1, -1):
		if days[i] < today - SCENE_DAYS:
			break
		var key := "%d:%d:%d:%d" % [days[i], kinds[i], households[i], pids[i]]
		seen[key] = true
		if not _scene_seen.has(key):
			fresh.append(i)
	_scene_seen = seen
	for i in fresh:
		if _scenes > SCENES_MAX - 4: # a scene has up to four walkers
			break
		_scene(e, i)

## The scene of event i (see the head of this file), when its way lies in
## the view.
func _scene(e: Dictionary, i: int) -> void:
	var kind: int = e.kind[i]
	var at: Vector2 = e.at[i]
	var to: Vector2 = e.to[i]
	var hh: int = e.household[i]
	var pid: int = e.pid[i]
	var amount: int = e.amount[i]
	var who := {"household": hh, "pid": pid}
	match kind:
		EV_MOVED, EV_JOINED:
			# from the cell left towards the cell moved to: only the stretch in view
			var way := _clip(at, to)
			if way.is_empty():
				return
			var n := clampi(amount, 1, 4)
			var what := "zieht mit %d Menschen in eine andere Gegend" % amount if kind == EV_MOVED \
				else "zieht mit %d Menschen zu Verwandten" % amount
			_group(way, n, HANDCART, BUNDLE, 0.0, false, 1.0, what, who)
		EV_TENT_MOVED, EV_TO_TENT:
			# to the tents at the market square: the new market's (its fine
			# tile is the event's place) or the one of the cell
			var square := at if kind == EV_TENT_MOVED else _square_near(at)
			if square.x == INF:
				return
			var from := square + _away(hh, at - square) * OUT_KM
			var what := "Zeltfamilie zieht an einen Markt mit mehr Arbeit und Almosen" if kind == EV_TENT_MOVED \
				else "ohne Arbeitskraft, zieht ins Zelt am Markt"
			_group(PackedVector2Array([from, square]), 2, BUNDLE, BUNDLE, 3.0, false, 0.9, what, who)
		EV_ALMS:
			var square := _square_near(at)
			if square.x == INF:
				return
			var from := square + _away(hh, at - square) * 0.3
			var w := _scene_walker(PackedVector2Array([from, square]), 0.0, BOWL, BOWL | BUNDLE, 5.0, true, 0.8, who)
			if not w.is_empty():
				w.what = "Zeltbewohner, holt Almosen am Markt"
				w.what_home = "Zeltbewohner, trägt %s kg Korn Almosen heim" % SimTables._int(amount)
				_add_scene(w)
		EV_THEFT:
			# from the tents at the market square (if near) to the farm robbed and back
			var square := _square_near(at)
			var from := square if square.x != INF and square.distance_to(at) <= 6.0 else at + _away(hh, Vector2.ZERO) * OUT_KM
			var w := _scene_walker(PackedVector2Array([from, at]), 0.0, 0, BUNDLE, 2.5, true, 1.3, who)
			if not w.is_empty():
				w.what = "Dieb aus dem Zelt, schleicht zu einem Hof"
				w.what_home = "Dieb, trägt %s kg gestohlenes Korn davon" % SimTables._int(amount)
				_add_scene(w)
		EV_HUNGER:
			# a funeral from the market square of the cell to the graves
			# outside the town; the dead person's house is not known
			var square := _square_near(at)
			if square.x == INF:
				return
			var graves := square + _away(hh, at - square) * 0.9
			_group(PackedVector2Array([square, graves]), 4, BIER, 0, 5.0, false, 0.55,
				"Trauerzug: ein Mensch aus dieser Gegend ist verhungert", {"household": -1, "pid": -1}, 6)
		EV_FARM_TAKEN, EV_HEIR:
			var from := at + _away(hh, Vector2.ZERO) * OUT_KM
			var what := "Familie übernimmt einen freien Hof" if kind == EV_FARM_TAKEN else "Sohn zieht auf seinen Erbteil vom Hof des Vaters"
			_group(PackedVector2Array([from, at]), 3 if kind == EV_FARM_TAKEN else 2, HANDCART, BUNDLE, 3.0, false, 1.0, what, who)
		EV_MANCIANA:
			var from := at + _away(hh, Vector2.ZERO) * OUT_KM
			_group(PackedVector2Array([from, at]), 2, AXE, AXE, 10.0, false, 1.0,
				"rodet Land nach der Lex Manciana für einen eigenen Hof", who)
		EV_FARM_LEFT:
			var off := at + _away(hh, Vector2.ZERO) * OUT_KM * 2.0
			_group(PackedVector2Array([at, off]), 3, HANDCART, BUNDLE, 0.0, false, 1.0, "gibt den Hof auf und zieht weg", who)

## A group of n on `way`, one behind the other: the first with `lead`, the
## others with `rest`; at the end each stays `stay` seconds (0: gone there).
## `tint` dresses all alike (a funeral in dark), -1 by household.
func _group(way: PackedVector2Array, n: int, lead: int, rest: int, stay: float, back: bool, pace: float, what: String, who: Dictionary, tint := -1) -> void:
	var length := way[0].distance_to(way[way.size() - 1])
	for k in n:
		var behind := minf(float(n - 1 - k) * GAP_KM, length * 0.5) # the first walks ahead
		var parts := lead if k == 0 else rest
		var w := _scene_walker(way, behind, parts, parts, stay, back, pace, who, k)
		if w.is_empty():
			return
		w.what = what
		if tint >= 0:
			w.tint = tint
		_add_scene(w)

## A scene's walker on `way` (world km), `ahead` km along it.
func _scene_walker(way: PackedVector2Array, ahead: float, parts: int, parts_home: int, stay: float, back: bool, pace: float, who: Dictionary, member := 0) -> Dictionary:
	var along := PackedFloat32Array([0.0])
	for k in range(1, way.size()):
		along.append(along[k - 1] + way[k].distance_to(way[k - 1]))
	var length := along[along.size() - 1]
	var inside := _window.grow(0.01) # a clipped way ends on the window's edge
	if length < 0.05 or not (inside.has_point(way[0]) or inside.has_point(way[way.size() - 1])):
		return {}
	var hh: int = who.household
	var seed := float(hh if hh >= 0 else int(way[0].x * 1000.0)) + member * 7.0
	return {
		"points": way, "along": along, "s": clampf(ahead, 0.0, length), "dir": 1.0, "turn": back,
		"cart": false, "cargo": false, "out": false,
		"phase": fposmod(seed * 0.618034, 1.0), "tint": int(absf(seed)) % 8,
		"side": (fposmod(seed * 0.377, 1.0) - 0.5) * LANE_KM * 0.4, # a group keeps together
		"parts": parts, "parts_home": parts_home, "stay": stay, "pace": pace,
		"household": hh if member == 0 else -1, "pid": int(who.pid) if member == 0 else -1,
	}

func _add_scene(w: Dictionary) -> void:
	_scenes += 1
	_add(w)

## The market square nearest the middle of the 25 km cell that `at` lies
## in, within SQUARE_REACH_KM; Vector2(INF, INF) if none.
func _square_near(at: Vector2) -> Vector2:
	var cell := Vector2i((at / 25.0).floor())
	if _square_of.has(cell):
		return _square_of[cell]
	var middle := (Vector2(cell) + Vector2(0.5, 0.5)) * 25.0
	var best := Vector2(INF, INF)
	var n := int(ceil(SQUARE_REACH_KM * 2.0 / 1.5625)) + 2 # fine tiles across
	for q in people.market_squares(middle.x, middle.y, n):
		if q.distance_to(middle) <= SQUARE_REACH_KM and (best.x == INF or q.distance_to(middle) < best.distance_to(middle)):
			best = q
	_square_of[cell] = best
	return best

## A way out of a farm or square: towards `hint` when it has a length (where
## the household came from), else a direction of its own by the household.
static func _away(hh: int, hint: Vector2) -> Vector2:
	if hint.length() > 0.2:
		return hint.normalized()
	var a := fposmod(float(hh) * 0.618034, 1.0) * TAU
	return Vector2(cos(a), sin(a))

## The stretch of the straight way a to b inside the view window, from where
## it comes in to where it leaves (or ends); empty if it misses the window.
func _clip(a: Vector2, b: Vector2) -> PackedVector2Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var lo := _window.position
	var hi := _window.end
	for axis in 2:
		if absf(d[axis]) < 1e-6:
			if a[axis] < lo[axis] or a[axis] > hi[axis]:
				return PackedVector2Array()
			continue
		var u := (lo[axis] - a[axis]) / d[axis]
		var v := (hi[axis] - a[axis]) / d[axis]
		t0 = maxf(t0, minf(u, v))
		t1 = minf(t1, maxf(u, v))
	if t1 - t0 <= 0.0:
		return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])

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
		# for a click (pick): who it is and what they do
		"pid": pid, "kind": kind, "cargo_kg": int(t.cargo_kg[i]),
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

## The traveller nearest to `pixel` on screen, within `max_px`: {"pid"
## (a trip; -1 for a hired hand), "household" (the hired hand's; -1),
## "what" (a line on what they are doing)}; {} if none. `ground(p)` is the
## ground's height at p (world km), `lift` how far above it to aim.
func pick(cam: Camera3D, pixel: Vector2, ground: Callable, lift: float, max_px: float) -> Dictionary:
	if not visible:
		return {}
	var best := {}
	var best_d := max_px * max_px
	for w in _walkers:
		# where people_walkers.gdshader draws it now
		var p: Vector2 = w.at + w.velocity * clampf(_clock - float(w.t0), 0.0, float(w.walk))
		var v := Vector3(p.x, float(ground.call(p)) + lift, p.y)
		if cam.is_position_behind(v):
			continue
		var d := cam.unproject_position(v).distance_squared_to(pixel)
		if d < best_d:
			best_d = d
			best = w
	if best.is_empty():
		return {}
	return {"pid": best.get("pid", -1), "household": best.get("worker", best.get("household", -1)), "what": _what(best)}


## What a traveller is doing, as a line for the person's info.
static func _what(w: Dictionary) -> String:
	var there: bool = w.dir > 0.0
	var staying: bool = w.wait > 0.0
	if w.has("what"): # a scene: its event
		return w.what if there or not w.has("what_home") else w.what_home
	if w.has("worker"):
		var at := "auf dem Hof von Haushalt %d" % w.farm if int(w.farm) >= 0 else "auf einem Hof"
		var doing := "arbeitet" if staying else ("geht zur Arbeit" if there else "kommt von der Arbeit")
		return "Tagelöhner, %s: %d Tage %s %s" % [doing, int(w.days), WORK_NAMES[clampi(int(w.work), 0, 3)], at]
	var kg := SimTables._int(int(w.cargo_kg))
	match int(w.kind):
		0: # a sale: the sacks on the way there
			return ("verkauft %s kg Korn am Markt" % kg) if staying else (("bringt %s kg Korn zum Markt" % kg) if there else "kommt vom Markt heim")
		1: # a purchase: the sacks on the way home
			return ("kauft Korn am Markt") if staying else (("geht auf den Markt, Korn kaufen") if there else ("trägt %s kg Korn vom Markt heim" % kg))
		2: # an export
			return ("Händler, liefert %s kg Korn an einem fremden Markt ab" % kg) if staying else (("Händler mit Ochsenkarren, fährt %s kg Korn zu einem anderen Markt" % kg) if there else "Händler, fährt leer zurück zu seinem Markt")
		_: # an import
			return ("Händler, lädt Korn an einem fremden Markt") if staying else (("Händler mit Ochsenkarren, fährt Korn holen") if there else ("Händler, bringt %s kg Korn an seinen Markt" % kg))

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
	var speed: float = (CART_KMPS if w.cart else WALK_KMPS) * float(w.get("pace", 1.0))
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
				var stay: float = w.get("stay", LINGER_S)
				if stay <= 0.0: # a scene that ends here: gone, or at once home again
					if w.turn:
						w.turn = false
						w.dir = -1.0
						_start(w, t)
					else:
						gone = true
					continue
				w.at = here + Vector2(-w.d.y, w.d.x) * float(w.side)
				w.velocity = Vector2.ZERO
				w.t0 = t
				w.walk = 0.0
				w.wait = stay
				w.until = t + stay
			elif w.dir < 0.0 and w.k <= 0:
				gone = true # home
			elif not _window.has_point(here):
				gone = true # out of view
			else:
				_start(w, t) # the next stretch (_start finds it from the end of this one)
		if gone:
			if w.has("what"):
				_scenes -= 1
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
	elif w.has("parts"): # a scene: what it carries there and on the way back
		parts = w.parts if w.dir > 0.0 else w.parts_home
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
## (9), standing alone, its counter to the front; or what the people of an
## event's scene carry (10-14, see the end).
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
	# the scenes of events: a handcart pulled behind the person by two shafts,
	# the household's bundles on it (10); a bundle on the back (11); a bier
	# on the shoulders with the dead under a linen shroud and a second
	# bearer behind (12); an axe on the shoulder (13); a bowl in the left
	# hand (14)
	o = Vector3(0.0, 0.0, -1.35)
	_box(st, o + Vector3(0.0, 0.62, 0.0), Vector3(0.42, 0.04, 0.5), wood, 10)
	for side in [-1.0, 1.0]:
		_box(st, o + Vector3(0.42 * side, 0.74, 0.0), Vector3(0.03, 0.1, 0.5), dark, 10)
		_box(st, o + Vector3(0.5 * side, 0.36, 0.0), Vector3(0.04, 0.34, 0.34), dark, 10)
		_box(st, Vector3(0.26 * side, 0.72, -0.5), Vector3(0.025, 0.025, 0.42), wood, 10)
	_box(st, o + Vector3(-0.15, 0.82, 0.18), Vector3(0.2, 0.16, 0.22), linen, 10)
	_box(st, o + Vector3(0.18, 0.8, -0.15), Vector3(0.18, 0.14, 0.2), sack, 10)
	_box(st, o + Vector3(0.05, 0.98, 0.02), Vector3(0.14, 0.08, 0.16), Color(0.55, 0.32, 0.2), 10)
	_box(st, Vector3(0.0, 0.66, -0.15) * f, Vector3(0.11, 0.14, 0.07) * f, sack, 11)
	_box(st, Vector3(0.0, 0.81, -0.15) * f, Vector3(0.04, 0.02, 0.04) * f, sack.darkened(0.3), 11)
	var shroud := Color(0.9, 0.87, 0.8)
	for side in [-1.0, 1.0]:
		_box(st, Vector3(0.2 * side, 0.83 * f, -1.25), Vector3(0.025, 0.025, 1.25), wood, 12)
	_box(st, Vector3(0.0, 0.83 * f, -1.25), Vector3(0.22, 0.03, 0.9), wood, 12)
	_box(st, Vector3(0.0, 0.83 * f + 0.1, -1.25), Vector3(0.17, 0.08, 0.8), shroud, 12)
	var mourning := Color(0.3, 0.24, 0.2)
	var b := Vector3(0.0, 0.0, -2.5)
	for side in [-1.0, 1.0]:
		_box(st, b + Vector3(0.075 * side, 0.02, 0.02) * f, Vector3(0.05, 0.02, 0.07) * f, sandal, 12, side, 0.48 * f)
		_box(st, b + Vector3(0.075 * side, 0.21, 0.0) * f, Vector3(0.05, 0.17, 0.05) * f, skin, 12, side, 0.48 * f)
		_box(st, b + Vector3(0.2 * side, 0.68, 0.06) * f, Vector3(0.05, 0.14, 0.05) * f, skin, 12)
	_box(st, b + Vector3(0.0, 0.59, 0.0) * f, Vector3(0.15, 0.21, 0.1) * f, mourning, 12)
	_box(st, b + Vector3(0.0, 0.9, 0.0) * f, Vector3(0.08, 0.08, 0.08) * f, skin, 12)
	_box(st, b + Vector3(0.0, 0.975, -0.01) * f, Vector3(0.088, 0.025, 0.088) * f, hair, 12)
	_box(st, Vector3(0.14, 0.83, -0.05) * f, Vector3(0.018, 0.018, 0.36) * f, wood, 13)
	_box(st, Vector3(0.14, 0.86, -0.4) * f, Vector3(0.015, 0.07, 0.045) * f, iron, 13)
	_box(st, Vector3(-0.24, 0.5, 0.08) * f, Vector3(0.065, 0.025, 0.065) * f, Color(0.66, 0.4, 0.26), 14, 0.6, 0.78 * f)
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
