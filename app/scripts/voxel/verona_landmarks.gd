extends RefCounted
## Verona reference, S136. Geometry is rebuilt at 0.25 m; no mesh stretching.
## Measured envelopes and explicit assumptions: data/cities/plans/verona.json,
## docs/kit2/VERONA.md. No decorative crowd: occupancy awaits simulation visits.
const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Arena := preload("res://scripts/voxel/roman_arena.gd")
const V := 0.25
const GROUND := 2
const REAL := {
	"arena": Vector3(152.4, 31.0, 123.2),
	"theatre": Vector3(109.0, 24.0, 71.0),
	"capitolium": Vector3(35.0, 18.0, 42.2),
	"forum": Vector3(56.5, 4.0, 168.0),
	"basilica": Vector3(27.5, 20.0, 78.0),
	"baths": Vector3(70.0, 16.0, 55.0),
}

static func size_m(kind: String) -> Vector3:
	var r: Vector3 = REAL[kind]
	var k := pow(100.0 / (r.x * r.z), 1.0 / 3.0)
	return Vector3(r.x * k, r.y if r.y <= 16.0 else 16.0 * pow(r.y / 16.0, 1.0 / 3.0), r.z * k)

static func grid(kind: String) -> Kit.Grid:
	var s := size_m(kind)
	var g := Kit.Grid.new(Vector3i(ceili(s.x / V) + 4, ceili(s.y / V) + GROUND + 2, ceili(s.z / V) + 4))
	match kind:
		"arena": _arena(g, s)
		"theatre": _theatre(g, s)
		"capitolium": _temple(g, s)
		"forum": _forum(g)
		"basilica": _basilica(g, s)
		"baths": _baths(g, s)
	return g

# A fixed 1.5 m opening with a stepped round head, independent of footprint.
static func _arch(o: int, row: int, height: int) -> bool:
	return o >= 2 and o <= 7 and row >= 1 and row <= mini(height - 7, 12) + int(Arena.HEAD[o - 2])

static func _arena(g: Kit.Grid, s: Vector3) -> void:
	var a := s.x * 0.5
	var b := s.z * 0.5
	# Same aspect as the real sand (75.68 x 44.43 m), with room for true-size seats.
	var aa := a * 75.68 / 152.4
	var bb := b * 44.43 / 123.2
	var wall := roundi(s.y / V)
	var rows := (wall - 2) / 3
	var bays := roundi(PI * (3.0 * (a + b) - sqrt((3.0 * a + b) * (a + 3.0 * b))) / 2.5)
	for z in g.n.z:
		for x in g.n.x:
			var px := (x + 0.5 - g.n.x * 0.5) * V
			var pz := (z + 0.5 - g.n.z * 0.5) * V
			var ring := Arena._ring(px, pz, a, b)
			var d := -ring.x
			if d < -0.25:
				continue
			var phase := fposmod(ring.y / TAU, 1.0) * bays
			var o := floori(fposmod(phase, 1.0) * 10.0)
			var stone := Kit.PINK if (floori(phase) + z / 4) % 7 == 0 else Kit.TRAV
			if d < 1.25:
				for y in wall:
					var lr := y % rows
					var edge := d < 0.5 or d > 1.0
					if y >= rows * 3 or lr >= rows - 2:
						g.put(x, GROUND + y, z, Kit.TRAV_L)
					elif edge and not _arch(o, lr, rows):
						g.put(x, GROUND + y, z, stone)
				continue
			var e := Arena._ring(px, pz, aa, bb).x
			var gate := absf(pz) < 1.0 and absf(px) > aa * 0.65
			if e <= 0.0 or gate:
				g.put(x, GROUND, z, Kit.SAND if not gate else Kit.PAVE)
			else:
				var step := maxi(0, floori((e - 0.5) / 0.5))
				var top := GROUND + 6 + step * 2
				g.box(x, GROUND, z, x + 1, top, z + 1, Kit.TRAV_D)
				var aisle := floori(phase) % 6 == 0 and o >= 4 and o <= 5
				g.put(x, top, z, Kit.PINK if aisle else Kit.SEAT_HI)

static func _column(g: Kit.Grid, x: int, z: int, bottom: int, top: int) -> void:
	g.box(x - 1, bottom, z - 1, x + 3, bottom + 1, z + 3, Kit.TRAV_L)
	g.box(x, bottom + 1, z, x + 2, top - 1, z + 2, Kit.STUCCO)
	g.box(x - 1, top - 1, z - 1, x + 3, top, z + 3, Kit.TRAV_L)

static func _roof(g: Kit.Grid, x0: int, x1: int, z0: int, z1: int, eave: int, ridge: int) -> void:
	var mid := (x0 + x1 - 1) * 0.5
	for x in range(x0, x1):
		var y := roundi(lerpf(float(ridge), float(eave), absf(x - mid) / maxf(mid - x0, 1.0)))
		g.box(x, eave, z0 + 1, x + 1, y, z0 + 2, Kit.CREAM)
		g.box(x, eave, z1 - 2, x + 1, y, z1 - 1, Kit.CREAM)
		for z in range(z0, z1):
			g.put(x, y, z, Kit.RIDGE if absf(x - mid) < 1.0 else (Kit.TILE_D if z % 4 == 0 else Kit.TILE))

static func _temple(g: Kit.Grid, s: Vector3) -> void:
	var top := GROUND + roundi(s.y / V) - 1
	var pod := GROUND + 8
	var eave := top - 12
	var back := 4
	var front := g.n.z - 12
	g.box(2, GROUND, 2, g.n.x - 2, pod, g.n.z - 10, Kit.TRAV_D)
	# Steps and three deep cellae; doors stay 1.25 x 2.5 m.
	for j in 8:
		g.box(g.n.x / 2 - 10, GROUND, front + j - 1, g.n.x / 2 + 10, pod - j, front + j, Kit.STEP)
	var cell_end := g.n.z / 2
	g.box(5, pod, back, g.n.x - 5, eave, cell_end, Kit.STUCCO)
	for c in 3:
		var x0 := 6 + c * (g.n.x - 12) / 3
		var x1 := 6 + (c + 1) * (g.n.x - 12) / 3
		g.box(x0 + 1, pod, back + 2, x1 - 1, eave - 1, cell_end - 1, Kit.EMPTY)
		var x := (x0 + x1) / 2
		g.box(x - 2, pod, cell_end - 2, x + 3, pod + 10, cell_end + 1, Kit.EMPTY)
	for row in 3:
		var z := cell_end + 3 + row * 8
		for col in 6:
			_column(g, 6 + col * (g.n.x - 13) / 5, z, pod, eave)
	# Lateral porticoes; the rear has no colonnade (sine postico).
	for z in range(back + 3, cell_end, 8):
		_column(g, 3, z, pod, eave)
		_column(g, g.n.x - 4, z, pod, eave)
	_roof(g, 1, g.n.x - 1, 2, front, eave, top)

static func _forum(g: Kit.Grid) -> void:
	g.box(2, GROUND, 2, g.n.x - 2, GROUND + 1, g.n.z - 2, Kit.PAVE_L)
	for x in [3, g.n.x - 12]:
		g.box(x, GROUND + 1, 3, x + 9, GROUND + 2, g.n.z - 3, Kit.STEP)
		for z in range(6, g.n.z - 4, 10):
			_column(g, x + 4, z, GROUND + 2, GROUND + 13)
		_roof(g, x - 1, x + 10, 3, g.n.z - 3, GROUND + 13, GROUND + 16)
	# An open square, no second temple duplicated inside it.
	g.box(g.n.x / 2 - 2, GROUND + 1, g.n.z / 2 - 2, g.n.x / 2 + 2, GROUND + 5, g.n.z / 2 + 2, Kit.MARBLE)
	g.box(g.n.x / 2 - 1, GROUND + 5, g.n.z / 2 - 1, g.n.x / 2 + 1, GROUND + 11, g.n.z / 2 + 1, Kit.BRONZE)

static func _hall(g: Kit.Grid, x0: int, x1: int, z0: int, z1: int, eave: int, top: int) -> void:
	g.box(x0, GROUND, z0, x1, eave, z1, Kit.CREAM)
	g.box(x0 + 2, GROUND + 1, z0 + 2, x1 - 2, eave, z1 - 2, Kit.EMPTY)
	# Regular pilasters, a plinth and cornice articulate the long walls.
	for z in range(z0 + 2, z1 - 1, 10):
		g.box(x0 - 1, GROUND, z, x0 + 1, eave, z + 2, Kit.TRAV_W)
		g.box(x1 - 1, GROUND, z, x1 + 1, eave, z + 2, Kit.TRAV_W)
	for y in [GROUND + 2, eave - 2]:
		g.box(x0 - 1, y, z0, x0 + 1, y + 1, z1, Kit.TRAV_L)
		g.box(x1 - 1, y, z0, x1 + 1, y + 1, z1, Kit.TRAV_L)
	var cx := (x0 + x1) / 2
	g.box(cx - 3, GROUND, z1 - 2, cx + 3, GROUND + 12, z1, Kit.DOOR_D)
	for z in range(z0 + 5, z1 - 4, 10):
		for x in [x0, x1 - 1]:
			g.box(x, eave - 9, z, x + 1, eave - 3, z + 3, Kit.DARK)
	_roof(g, x0 - 1, x1 + 1, z0 - 1, z1 + 1, eave, top)

static func _basilica(g: Kit.Grid, s: Vector3) -> void:
	var top := GROUND + roundi(s.y / V) - 1
	# High nave, lower side aisles and clerestory. Unknown elevation is explicit.
	_hall(g, 3, g.n.x - 3, 3, g.n.z - 3, GROUND + 27, GROUND + 35)
	_hall(g, 11, g.n.x - 11, 4, g.n.z - 4, top - 8, top)
	for z in range(9, g.n.z - 6, 10):
		_column(g, 6, z, GROUND, GROUND + 27)
		_column(g, g.n.x - 7, z, GROUND, GROUND + 27)

static func _baths(g: Kit.Grid, s: Vector3) -> void:
	var top := GROUND + roundi(s.y / V) - 1
	# Typological thermal suite and open palaestra, not Caracalla transplanted.
	g.box(2, GROUND, 2, g.n.x - 2, GROUND + 1, g.n.z - 2, Kit.PAVE)
	_hall(g, 4, g.n.x - 4, 3, g.n.z / 2, top - 10, top)
	_hall(g, 4, g.n.x / 3, g.n.z / 2, g.n.z - 4, GROUND + 22, GROUND + 30)
	g.box(g.n.x / 2, GROUND + 1, g.n.z / 2 + 4, g.n.x - 8, GROUND + 2, g.n.z - 8, Kit.MARBLE)
	g.box(g.n.x / 2 + 2, GROUND + 2, g.n.z / 2 + 6, g.n.x - 10, GROUND + 3, g.n.z - 10, Kit.POOL)
	for x in range(g.n.x / 3 + 5, g.n.x - 4, 10):
		_column(g, x, g.n.z - 4, GROUND + 1, GROUND + 15)
	g.box(g.n.x / 3 + 2, GROUND + 15, g.n.z - 6, g.n.x - 2, GROUND + 17, g.n.z - 2, Kit.TILE)

static func _theatre(g: Kit.Grid, s: Vector3) -> void:
	var a := s.x * 0.5
	var depth := s.z - 4.0
	var centre_z := g.n.z - 18
	var orch := s.x * 30.0 / 109.0 * 0.5
	var wall := roundi(s.y / V)
	for z in range(2, centre_z + 1):
		for x in g.n.x:
			var px := (x + 0.5 - g.n.x * 0.5) * V
			var pz := (centre_z - z) * V
			var r := Vector2(px, pz * a / depth).length()
			if r > a:
				continue
			var angle := atan2(pz * a / depth, px)
			var o := floori(fposmod(angle * a / 2.5, 1.0) * 10.0)
			if r > a - 1.0:
				# Two galleries and a small arched loggia, without Marcellus's attic.
				var rows := (wall - 12) / 2
				for y in wall:
					var local := y % rows if y < rows * 2 else y - rows * 2
					var h := rows if y < rows * 2 else 12
					if not _arch(o, local, h) or local >= h - 2:
						g.put(x, GROUND + y, z, Kit.TRAV)
			elif r < orch:
				g.put(x, GROUND, z, Kit.MARBLE)
			else:
				var step := floori((r - orch) / 0.5)
				var top := GROUND + 3 + step * 2
				g.box(x, GROUND, z, x + 1, top, z + 1, Kit.TRAV_D)
				var aisle := absf(sin(angle * 6.0)) < 0.12
				g.put(x, top, z, Kit.PINK if aisle else Kit.SEAT_HI)
	# Stage on the river side with three normal-size entrances.
	g.box(4, GROUND, centre_z, g.n.x - 4, GROUND + 4, g.n.z - 3, Kit.WOOD)
	g.box(4, GROUND, g.n.z - 5, g.n.x - 4, GROUND + wall - 8, g.n.z - 3, Kit.CREAM)
	for x in range(5, g.n.x - 4, 10):
		g.box(x, GROUND + 4, g.n.z - 3, x + 2, GROUND + wall - 8, g.n.z - 2, Kit.TRAV_W)
	for y in [GROUND + 5, GROUND + wall / 2, GROUND + wall - 9]:
		g.box(4, y, g.n.z - 3, g.n.x - 4, y + 1, g.n.z - 2, Kit.TRAV_L)
	for j in 3:
		var x := g.n.x / 2 + (j - 1) * (g.n.x / 4)
		g.box(x - 3, GROUND + 4, g.n.z - 5, x + 3, GROUND + 16, g.n.z - 3, Kit.EMPTY)
	for x in range(6, g.n.x - 5, 9):
		_column(g, x, g.n.z - 6, GROUND + 4, GROUND + wall - 8)
	g.box(3, GROUND + wall - 8, g.n.z - 7, g.n.x - 3, GROUND + wall - 6, g.n.z - 2, Kit.TRAV_L)
