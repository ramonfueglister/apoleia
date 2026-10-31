extends RefCounted
## The ways the travellers of people_trips.gd walk, so they keep to the
## ways and streets and do not cut through the houses (Ramon, 31.10.2026:
## „Personen laufen quer durch Gebäude bei den Animationen. Wegfindung?“).
## Only the drawing: the sim's routes and times stay as they are.
##
## Out in the country a traveller walks the worn ways as the terrain draws
## them (sim_fields.gdshaderinc sim_way_main: per 1.5625 km tile the
## neighbours its way leads to; with two ends the way bends from the middle
## of the one edge over the tile's middle to the other as a quadratic
## curve, else each end runs straight to the middle). The farmhouses keep
## off exactly those curves (people_dots_common.gdshaderinc
## dot_lot_way_free, #87), so on them nobody walks through a house. A trip
## of the sim comes as its tiles (trips.rs: the footpath tile by tile,
## through the tiles' middles); `on_ways` lays it on the curves. A way the
## sim keeps no route for (a hired hand from home to the farm, a goods
## cart, an event's scene) is looked for on the worn network between its
## two ends (`between`, a breadth-first search over the tiles' links near
## the two ends); where there is none it stays straight as before.
##
## In a city with a plan (city_plans.gd: 0.25 km parcels, each a house, a
## street, a square, the wall, a gate ...) the way through the town is
## looked for on the parcels one can walk (streets, squares, gates,
## bridges, open land, outside the plan) with A*, from where the way comes
## to the first parcel of the town to where it leaves it or ends, so the
## travellers walk the streets and through the gates and not over the
## insulae. A way that ends on a built parcel (a market whose tile middle
## lies in a block) ends on the walkable parcel nearest to it.

## (x = col, y = row) steps as sim_fields.gdshaderinc SIM_DIRS (grain.rs DIRS)
const DIRS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const CURVE_STEPS := 6 # as sim_fields.gdshaderinc sim_curve samples it
const SEARCH_MARGIN := 6 # tiles beyond the box of the two ends the way search may go
const SNAP_RINGS := 1 # how far (tiles) an end may lie from the worn network
## city_plans.gd CODES one can walk: none (outside a plan), plaza, street, gate, bridge, land
const WALKABLE: Array[int] = [0, 5, 7, 9, 10, 12]
const CITY_STEP_KM := 0.06 # samples along a way when looking for the city parcels it crosses
const CITY_MARGIN := 12 # parcels beyond the box of the two ends the street search may go
const CITY_NODES_MAX := 60000 # the street search gives up beyond this many parcels
const END_RINGS := 8 # parcels round a built end searched for a walkable one

var plans: RefCounted = null # city_plans.gd, null without plans
var _ways := PackedByteArray() # RG8: links, level, per tile of the window
var _n := 0 # tiles per side of the window
var _origin := Vector2.ZERO # world km of the window's corner
var _tile_km := 1.5625
var fails := 0 # street searches that found no way (for the tests)
var _streets_cache := {} # Vector4i(from, to) -> the street search's corners
var _city_cache := {} # parcel -> its kind, filled as asked
## where the streets are looked for (people_trips.gd: the window around the
## view); outside it the travellers are out of sight
var area := Rect2(-1e9, -1e9, 2e9, 2e9):
	set(value):
		if value != area:
			_city_cache.clear()
			_streets_cache.clear()
		area = value

## The worn network of the window around the camera (people_dots.gd
## map_window "ways", "origin", "tile_km").
func set_ways(img: Image, origin: Vector2, tile_km: float) -> void:
	if img == null:
		_n = 0
		_ways = PackedByteArray()
		return
	_n = img.get_width()
	_ways = img.get_data()
	_origin = origin
	_tile_km = tile_km

func has_ways() -> bool:
	return _n > 0

## The window tile under p (world km).
func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(((p - _origin) / _tile_km).floor())

func _mid(t: Vector2i) -> Vector2:
	return _origin + (Vector2(t) + Vector2(0.5, 0.5)) * _tile_km

## Links and level of window tile t, (0, 0) outside the window.
func _way(t: Vector2i) -> Vector2i:
	if _n == 0 or t.x < 0 or t.y < 0 or t.x >= _n or t.y >= _n:
		return Vector2i.ZERO
	var o := (t.y * _n + t.x) * 2
	return Vector2i(_ways[o], _ways[o + 1])

## The links of tile t when a way is drawn there, else 0.
func _links(t: Vector2i) -> int:
	var w := _way(t)
	return w.x if w.y > 0 else 0

static func _dir(d: Vector2i) -> int:
	return DIRS.find(d)

static func _count(bits: int) -> int:
	var c := 0
	while bits != 0:
		c += bits & 1
		bits >>= 1
	return c

## Where the way of tile t passes its middle (sim_fields.gdshaderinc
## sim_way_hub), world km.
func hub(t: Vector2i) -> Vector2:
	var links := _links(t)
	var mid := _mid(t)
	if _count(links) != 2:
		return mid
	var ends: Array[int] = []
	for k in 8:
		if links & (1 << k):
			ends.append(k)
	var a := mid + Vector2(DIRS[ends[0]]) * 0.5 * _tile_km
	var c := mid + Vector2(DIRS[ends[1]]) * 0.5 * _tile_km
	return 0.25 * (a + c) + 0.5 * mid

## The points of the way through tile t, coming in from neighbour
## direction `inn` and going on towards `out` (-1: it starts or ends in
## the tile, at its hub), as the terrain draws it there; appended to `pts`
## (the first point left out when `pts` already ends there).
func _through(t: Vector2i, inn: int, out: int, pts: PackedVector2Array) -> void:
	var mid := _mid(t)
	var links := _links(t)
	var curve := _count(links) == 2 and (inn < 0 or links & (1 << inn)) and (out < 0 or links & (1 << out))
	var from := 0.0 if inn >= 0 else 0.5
	var to := 1.0 if out >= 0 else 0.5
	if curve:
		# the tile's two ends in the order walked
		var ends: Array[int] = []
		for k in 8:
			if links & (1 << k):
				ends.append(k)
		var first := inn if inn >= 0 else (ends[0] if ends[1] == out else ends[1])
		var last := out if out >= 0 else (ends[0] if ends[1] == first else ends[1])
		var a := mid + Vector2(DIRS[first]) * 0.5 * _tile_km
		var c := mid + Vector2(DIRS[last]) * 0.5 * _tile_km
		for k in CURVE_STEPS + 1:
			var u := float(k) / CURVE_STEPS
			if u < from - 1e-4 or u > to + 1e-4:
				continue
			_push(pts, a.lerp(mid, u).lerp(mid.lerp(c, u), u))
		return
	if inn >= 0:
		_push(pts, mid + Vector2(DIRS[inn]) * 0.5 * _tile_km)
	_push(pts, mid)
	if out >= 0:
		_push(pts, mid + Vector2(DIRS[out]) * 0.5 * _tile_km)

static func _push(pts: PackedVector2Array, p: Vector2) -> void:
	if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(p) > 1e-8:
		pts.append(p)

## A route of tile middles (trips.rs, world km, each tile next to the one
## before) laid on the curves of the worn network; the end (the market's
## square) kept where it lies off the last tile's hub. Unchanged without
## the network.
func on_ways(route: PackedVector2Array) -> PackedVector2Array:
	if _n == 0 or route.size() < 2:
		return route
	var tiles: Array[Vector2i] = []
	for p in route:
		var t := tile_of(p)
		if tiles.is_empty() or tiles[tiles.size() - 1] != t:
			tiles.append(t)
	if tiles.size() < 2:
		return route
	var pts := _along(tiles)
	if pts.is_empty():
		return route
	_push(pts, route[route.size() - 1])
	return pts

## The points of the way along `tiles` (each next to the one before; a
## jump runs straight from middle to middle), from the first tile's hub to
## the last one's; empty when two tiles are not neighbours and nothing is
## known.
func _along(tiles: Array[Vector2i]) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in tiles.size():
		var inn := _dir(tiles[i - 1] - tiles[i]) if i > 0 else -1
		var out := _dir(tiles[i + 1] - tiles[i]) if i < tiles.size() - 1 else -1
		if i > 0 and inn < 0:
			_push(pts, _mid(tiles[i])) # not neighbours: straight on
			continue
		_through(tiles[i], inn, out, pts)
	return pts

## The way from a to b (world km) on the worn network when the two lie on
## or next to it, else the straight line; through a town on its streets.
func between(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := _between_ways(a, b)
	return through_towns(pts)

func _between_ways(a: Vector2, b: Vector2) -> PackedVector2Array:
	var straight := PackedVector2Array([a, b])
	if _n == 0:
		return straight
	var ta := _snap(tile_of(a))
	var tb := _snap(tile_of(b))
	if ta.x == -9999 or tb.x == -9999:
		return straight
	if ta == tb:
		return straight
	var tiles := _search(ta, tb)
	if tiles.is_empty():
		return straight
	var pts := PackedVector2Array()
	if ta != tile_of(a):
		pts.append(a) # beside the network: straight to it
	pts.append_array(_along(tiles))
	if tb != tile_of(b):
		_push(pts, b)
	return pts

## Tile t when a way is drawn there, else the nearest such tile within
## SNAP_RINGS; x = -9999 if none.
func _snap(t: Vector2i) -> Vector2i:
	if _links(t) != 0:
		return t
	for r in range(1, SNAP_RINGS + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and _links(t + Vector2i(dx, dy)) != 0:
					return t + Vector2i(dx, dy)
	return Vector2i(-9999, -9999)

## The tiles from a to b over the links of the worn network, fewest steps
## (a diagonal step a little dearer), within the box of the two and
## SEARCH_MARGIN; empty if they are not joined there.
func _search(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y)) - Vector2i(SEARCH_MARGIN, SEARCH_MARGIN)
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) + Vector2i(SEARCH_MARGIN, SEARCH_MARGIN)
	var came := {a: a}
	var cost := {a: 0.0}
	var heap := _Heap.new()
	heap.push(0.0, a)
	while not heap.empty():
		var cur: Vector2i = heap.pop()
		if cur == b:
			break
		var c: float = cost[cur]
		var links := _links(cur)
		for k in 8:
			if not links & (1 << k):
				continue
			var nb := cur + DIRS[k]
			if nb.x < lo.x or nb.y < lo.y or nb.x > hi.x or nb.y > hi.y or _links(nb) == 0:
				continue
			var nc := c + (1.4142 if DIRS[k].x != 0 and DIRS[k].y != 0 else 1.0)
			if not cost.has(nb) or nc < float(cost[nb]) - 1e-6:
				cost[nb] = nc
				came[nb] = cur
				heap.push(nc, nb)
	if not came.has(b):
		return []
	var out: Array[Vector2i] = [b]
	while out[out.size() - 1] != a:
		out.append(came[out[out.size() - 1]])
	out.reverse()
	return out

# ------------------------------------------------------------------ towns

## The plan's kind of a parcel (city_plans.gd CODES, 0 outside a plan and
## outside `area`), cached.
func _kind(parcel: Vector2i) -> int:
	if _city_cache.has(parcel):
		return _city_cache[parcel]
	var k := 0
	if area.has_point(_parcel_mid(parcel)):
		k = plans.texel(parcel).x
	if _city_cache.size() > 200000:
		_city_cache.clear()
	_city_cache[parcel] = k
	return k

func _walkable(parcel: Vector2i) -> bool:
	return WALKABLE.has(_kind(parcel))

func _in_plan(parcel: Vector2i) -> bool:
	return _kind(parcel) != 0

func _parcel_mid(p: Vector2i) -> Vector2:
	return plans.world_min + (Vector2(p) + Vector2(0.5, 0.5)) * plans.parcel_km

## `pts` with every stretch through a town's houses replaced by a way on its
## streets: from the last walkable spot before the town's first built
## parcel to the first walkable spot after its last one (or the walkable
## parcel nearest the end). Unchanged without plans or where the streets
## give no way.
func through_towns(pts: PackedVector2Array) -> PackedVector2Array:
	if plans == null or pts.size() < 2 or not _near_plan(pts):
		return pts
	# samples along the way inside the area: point, parcel, index of the
	# stretch (outside it a parcel that counts as open land)
	var samples: Array = []
	var off := Vector2i(-1000000000, -1000000000)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / CITY_STEP_KM))
		if not area.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(0.01)):
			samples.append([a, off, i]) # the whole stretch out of the area
			continue
		for k in n:
			var p := a.lerp(b, float(k) / n)
			samples.append([p, plans.parcel_at(p.x, p.y) if area.has_point(p) else off, i])
	var last := pts[pts.size() - 1]
	samples.append([last, plans.parcel_at(last.x, last.y) if area.has_point(last) else off, pts.size() - 1])
	var out := PackedVector2Array()
	var i := 0
	var next_pt := 0 # the next point of pts not yet in out
	while i < samples.size():
		var parcel: Vector2i = samples[i][1]
		if _walkable(parcel) or not _in_plan(parcel):
			i += 1
			continue
		# a built parcel: the town's stretch runs from the sample before the
		# first parcel of the town to the first sample after its last one
		var s := i
		while s > 0 and _in_plan(samples[s - 1][1]) and _in_plan(samples[s][1]):
			s -= 1
		s = maxi(s - 1, 0)
		var e := i
		var k := i
		while k < samples.size():
			if _in_plan(samples[k][1]):
				if not _walkable(samples[k][1]):
					e = k
				k += 1
			elif k - e > int(1.0 / CITY_STEP_KM): # a kilometre out of the town: past it
				break
			else:
				k += 1
		var end_idx := mini(e + 1, samples.size() - 1)
		# not from or to a sample out of the area (its parcel stands for open land far off)
		while s < i and samples[s][1] == off:
			s += 1
		while end_idx > e and samples[end_idx][1] == off:
			end_idx -= 1
		var from: Vector2i = samples[s][1]
		var to: Vector2i = samples[end_idx][1]
		var ends_inside := (end_idx == samples.size() - 1 or end_idx == e) and not _walkable(to)
		# a start or an end in a house: out of its door onto the street next
		# to it (the search may leave and enter those two), else from or to
		# the walkable parcel nearest it
		var street := _streets(from, to)
		var moved_start := false # walled in at the start: the way begins on the street nearest it
		if street.is_empty() and (not _walkable(from) or not _walkable(to)):
			moved_start = not _walkable(from)
			from = from if _walkable(from) else _nearest_walkable(from)
			to = to if _walkable(to) else _nearest_walkable(to)
			if from.x != -99999 and to.x != -99999:
				street = _streets(from, to)
		if street.is_empty():
			fails += 1
			i = end_idx + 1
			continue
		# the points of pts up to the start, then the start sample, the streets, the end sample
		var start_seg: int = samples[s][2]
		if moved_start and out.is_empty():
			next_pt = start_seg + 1
		while next_pt <= start_seg:
			_push(out, pts[next_pt])
			next_pt += 1
		if not (moved_start and out.is_empty()):
			_push(out, samples[s][0])
		for p in street:
			_push(out, p)
		if not ends_inside:
			_push(out, samples[end_idx][0])
		var end_seg: int = samples[end_idx][2]
		next_pt = maxi(next_pt, end_seg + 1)
		i = end_idx + 1
		if ends_inside:
			return out
	while next_pt < pts.size():
		_push(out, pts[next_pt])
		next_pt += 1
	return out

## Whether a page of the plans (city_plans.gd, 16 km a side) with a town
## lies under the box of `pts` within the area; else no town is near.
func _near_plan(pts: PackedVector2Array) -> bool:
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	box = box.intersection(area)
	if box.size.x < 0.0 or box.size.y < 0.0 or (box.size == Vector2.ZERO and not area.has_point(box.position)):
		return false
	var pp: int = plans.page_parcels
	var lo: Vector2i = plans.parcel_at(box.position.x, box.position.y)
	var hi: Vector2i = plans.parcel_at(box.end.x, box.end.y)
	lo = Vector2i(floori(float(lo.x) / pp), floori(float(lo.y) / pp))
	hi = Vector2i(floori(float(hi.x) / pp), floori(float(hi.y) / pp))
	if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) > 400:
		return true # a long way: look along it
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			if plans.texel(Vector2i(i, j) * pp + Vector2i(pp / 2, pp / 2)) != Vector3i.ZERO or _page_has_plan(Vector2i(i, j)):
				return true
	return false

func _page_has_plan(page: Vector2i) -> bool:
	if page.x < 0 or page.y < 0 or page.x >= plans.page_size.x or page.y >= plans.page_size.y:
		return false
	var c: Color = plans._pages.get_pixelv(page)
	return c.r > 0.0 or c.g > 0.0

## The walkable parcel nearest to p within END_RINGS, x = -99999 if none.
func _nearest_walkable(p: Vector2i) -> Vector2i:
	if _walkable(p):
		return p
	for r in range(1, END_RINGS + 1):
		var best := Vector2i(-99999, -99999)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				var d := float(dx * dx + dy * dy)
				if d < best_d and _walkable(q):
					best = q
					best_d = d
		if best.x != -99999:
			return best
	return Vector2i(-99999, -99999)

## A* over the walkable parcels from a to b (4 neighbours; a diagonal
## where both its sides are walkable too, so no corner of a house is cut),
## the path's corners only, in world km; empty if none within the box.
func _streets(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	if a == b:
		return PackedVector2Array([_parcel_mid(a)])
	var key := Vector4i(a.x, a.y, b.x, b.y)
	if _streets_cache.has(key):
		return _streets_cache[key]
	var found := _search_streets(a, b)
	if _streets_cache.size() > 4000:
		_streets_cache.clear()
	_streets_cache[key] = found
	return found

func _search_streets(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y)) - Vector2i(CITY_MARGIN, CITY_MARGIN)
	var size := Vector2i(absi(a.x - b.x), absi(a.y - b.y)) + Vector2i(CITY_MARGIN, CITY_MARGIN) * 2 + Vector2i.ONE
	var cells := size.x * size.y
	if cells > CITY_NODES_MAX:
		return PackedVector2Array()
	# per parcel of the box: 0 not yet asked, 1 walkable, 2 not
	var walk := PackedByteArray()
	walk.resize(cells)
	var cost := PackedFloat32Array()
	cost.resize(cells)
	cost.fill(INF)
	var came := PackedInt32Array()
	came.resize(cells)
	came.fill(-1)
	var ia := (a.y - lo.y) * size.x + a.x - lo.x
	var ib := (b.y - lo.y) * size.x + b.x - lo.x
	cost[ia] = 0.0
	came[ia] = ia
	walk[ia] = 1 # out of a house at the start, into one at the end
	walk[ib] = 1
	var heap := _Heap.new()
	heap.push(Vector2(b - a).length(), a)
	while not heap.empty():
		var cur: Vector2i = heap.pop()
		var ic := (cur.y - lo.y) * size.x + cur.x - lo.x
		if ic == ib:
			break
		var c := cost[ic]
		for k in 8:
			var d := DIRS[k]
			var nb := cur + d
			var lx := nb.x - lo.x
			var ly := nb.y - lo.y
			if lx < 0 or ly < 0 or lx >= size.x or ly >= size.y:
				continue
			var inb := ly * size.x + lx
			if not _walk_at(walk, inb, nb):
				continue
			var diag := d.x != 0 and d.y != 0
			if diag:
				# both its sides walkable too, so no corner of a house is cut
				if not _walk_at(walk, ic + d.x, cur + Vector2i(d.x, 0)) or not _walk_at(walk, ic + d.y * size.x, cur + Vector2i(0, d.y)):
					continue
			var nc := c + (1.4142 if diag else 1.0)
			if nc < cost[inb] - 1e-4:
				cost[inb] = nc
				came[inb] = ic
				heap.push(nc + Vector2(b - nb).length(), nb)
	if came[ib] < 0:
		return PackedVector2Array()
	var path: Array[Vector2i] = []
	var i := ib
	while true:
		path.append(lo + Vector2i(i % size.x, i / size.x))
		if i == ia:
			break
		i = came[i]
	path.reverse()
	# the corners only: where the step changes
	var out := PackedVector2Array([_parcel_mid(path[0])])
	for j in range(1, path.size() - 1):
		if path[j] - path[j - 1] != path[j + 1] - path[j]:
			out.append(_parcel_mid(path[j]))
	out.append(_parcel_mid(path[path.size() - 1]))
	return out

## Whether parcel p (index i in the box's `walk`) can be walked, asked once.
func _walk_at(walk: PackedByteArray, i: int, p: Vector2i) -> bool:
	if walk[i] == 0:
		walk[i] = 1 if _walkable(p) else 2
	return walk[i] == 1

## A binary min-heap of (priority, cell) for the street search.
class _Heap:
	var keys := PackedFloat32Array()
	var cells: Array[Vector2i] = []

	func empty() -> bool:
		return cells.is_empty()

	func push(key: float, cell: Vector2i) -> void:
		keys.append(key)
		cells.append(cell)
		var i := cells.size() - 1
		while i > 0:
			var up := (i - 1) / 2
			if keys[up] <= keys[i]:
				break
			_swap(i, up)
			i = up

	func pop() -> Vector2i:
		var top := cells[0]
		var n := cells.size() - 1
		keys[0] = keys[n]
		cells[0] = cells[n]
		keys.resize(n)
		cells.pop_back()
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < n and keys[l] < keys[m]:
				m = l
			if r < n and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(i: int, j: int) -> void:
		var k := keys[i]
		keys[i] = keys[j]
		keys[j] = k
		var c := cells[i]
		cells[i] = cells[j]
		cells[j] = c
