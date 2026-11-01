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

# Equal arc-length bays prevent narrow, uneven openings at the oval's ends.
static func _ellipse_arc(a: float, b: float) -> PackedFloat32Array:
	var arc := PackedFloat32Array([0.0])
	var last := Vector2(a, 0)
	for i in range(1, 1025):
		var t := TAU * i / 1024.0
		var point := Vector2(a * cos(t), b * sin(t))
		arc.append(arc[-1] + point.distance_to(last))
		last = point
	return arc

# Opening has a genuinely round head and visible voussoirs. Units are voxels.
static func _opening(u: float, y: int, spring: int, radius: float) -> bool:
	return y >= 1 and absf(u) < radius and (y <= spring or Vector2(u, y - spring).length() < radius)

static func _ashlar(bay: int, _u: float, y: int) -> int:
	# Broad, restrained courses; detail must not compete with the arcade rhythm.
	return Kit.TRAV_W if y % 8 == 0 and bay % 3 == 0 else Kit.TRAV

# A load-bearing arcade: broad piers, impost, round archivolt, entablature.
static func _arcade(g: Kit.Grid, x: int, z: int, d: float, phase: float, rows: int, orders: int, wall: int) -> void:
	var bay := floori(phase)
	var u := (fposmod(phase, 1.0) - 0.5) * 13.0
	for y in wall:
		var st := mini(y / rows, orders - 1)
		var lr := y - st * rows
		var cornice := lr >= rows - 3 or y >= wall - 2
		var pier := absf(u) >= 4.5
		var spring := rows - 11
		var opening := _opening(u, lr, spring, 4.0)
		var arch_ring := not opening and absf(u) <= 5.0 and lr >= spring and Vector2(u, lr - spring).length() < 5.5
		var face := d < 0.75
		if d < 0.0:
			if cornice or (pier and absf(u) > 5.4) or lr == spring and pier:
				g.put(x, GROUND + y, z, Kit.TRAV_L)
		elif face:
			if not opening:
				var c := Kit.TRAV_L if cornice or arch_ring or (lr == spring and pier) else _ashlar(bay, u, lr)
				g.put(x, GROUND + y, z, c)
		elif d < 2.0:
			# Substantial annular floors and vaults, not a paper-thin hollow shell.
			if lr <= 1 or lr >= rows - 4:
				g.put(x, GROUND + y, z, Kit.VAULT if lr < rows - 2 else Kit.TRAV_D)
		elif d < 2.5:
			if not _opening(u, lr, spring, 3.5):
				var inner := Kit.TRAV_L if cornice or lr == 2 else Kit.TRAV_W
				g.put(x, GROUND + y, z, inner)
		elif d < 2.75:
			# Gallery floor edges project into the bowl, separating all three
			# circulation levels on the inside as clearly as on the street face.
			if lr >= rows - 3 or lr <= 1 or y >= wall - 2:
				g.put(x, GROUND + y, z, Kit.TRAV_L if lr != 0 else Kit.TRAV_D)

static func _arena(g: Kit.Grid, s: Vector3) -> void:
	var a := s.x * 0.5
	var b := s.z * 0.5
	var aa := a * 75.68 / 152.4
	var bb := b * 44.43 / 123.2
	var wall := roundi(s.y / V)
	var rows := wall / 3
	var arc := _ellipse_arc(a, b)
	var bays := 24 # fewer full-size bays, all three real orders retained
	for z in g.n.z:
		for x in g.n.x:
			var px := (x + 0.5 - g.n.x * 0.5) * V
			var pz := (z + 0.5 - g.n.z * 0.5) * V
			var ring := Arena._ring(px, pz, a, b)
			var d := -ring.x
			if d < -0.25:
				continue
			var idx := clampi(roundi(fposmod(ring.y, TAU) / TAU * 1024.0), 0, 1024)
			var phase := arc[idx] / arc[-1] * bays + 0.5
			if d < 2.75:
				_arcade(g, x, z, d, phase, rows, 3, wall)
				continue
			var e := Arena._ring(px, pz, aa, bb).x
			var gate := absf(pz) < 1.0 and absf(px) > aa * 0.8
			if e <= 0.0 or gate:
				g.put(x, GROUND, z, Kit.SAND_D if Kit.chance(x / 3, 0, z / 3, 7, 16) else Kit.SAND)
				if gate and e > 0.5:
					# A covered radial access passage below the cavea.
					g.box(x, GROUND + 13, z, x + 1, GROUND + 15, z + 1, Kit.VAULT)
			elif e < 0.5:
				g.box(x, GROUND, z, x + 1, GROUND + 6, z + 1, Kit.PODIUM)
				g.put(x, GROUND + 6, z, Kit.TRAV_L)
				g.put(x, GROUND + 2, z, Kit.REDWASH)
			else:
				var step := maxi(0, floori((e - 0.5) / 0.5))
				var aisle := absf(sin(ring.y * 6.0)) < 0.10
				var promenade := step == 3
				var top := GROUND + 7 + step * 2
				if promenade:
					top -= 1
				if aisle:
					top -= int(fposmod(e - 0.5, 0.5) < 0.25)
				g.box(x, GROUND, z, x + 1, top, z + 1, Kit.TRAV_D)
				g.put(x, top, z, Kit.PINK if aisle else (Kit.PAVE_L if promenade else Kit.SEAT_HI))
				if not aisle and not promenade and posmod(x + z, 3) == 0:
					g.put(x, top, z, Kit.SEAT_MID)

static func _column(g: Kit.Grid, x: int, z: int, bottom: int, top: int) -> void:
	g.box(x - 1, bottom, z - 1, x + 3, bottom + 2, z + 3, Kit.TRAV_L)
	g.box(x, bottom + 2, z, x + 2, top - 3, z + 2, Kit.STUCCO)
	g.box(x - 1, top - 3, z - 1, x + 3, top - 2, z + 3, Kit.TRAV_W)
	g.box(x - 1, top - 2, z - 1, x + 3, top, z + 3, Kit.TRAV_L)

static func _roof(g: Kit.Grid, x0: int, x1: int, z0: int, z1: int, eave: int, ridge: int) -> void:
	var mid := (x0 + x1 - 1) * 0.5
	for x in range(x0, x1):
		var y := roundi(lerpf(float(ridge), float(eave), absf(x - mid) / maxf(mid - x0, 1.0)))
		g.box(x, eave, z0 + 1, x + 1, y, z0 + 2, Kit.CREAM)
		g.box(x, eave, z1 - 2, x + 1, y, z1 - 1, Kit.CREAM)
		for z in range(z0, z1):
			var tile := Kit.TILE_D if z % 4 == 0 else (Kit.TILE_L if x % 6 == 0 else Kit.TILE)
			g.put(x, y, z, Kit.RIDGE if absf(x - mid) < 1.0 else tile)
			if x == x0 or x == x1 - 1:
				g.put(x, y - 1, z, Kit.EAVE)

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
	# The rear expresses the three cellae instead of one blank slab.
	for x in [5, g.n.x / 3, 2 * g.n.x / 3, g.n.x - 6]:
		g.box(x - 1, pod, back - 1, x + 2, eave, back + 1, Kit.TRAV_W)
	for y in range(GROUND + 1, pod, 2):
		g.box(2, y, 2, g.n.x - 2, y + 1, 3, Kit.TRAV_W)
		g.box(2, y, 2, 3, y + 1, g.n.z - 10, Kit.TRAV_W)
		g.box(g.n.x - 3, y, 2, g.n.x - 2, y + 1, g.n.z - 10, Kit.TRAV_W)
	g.box(1, eave - 3, 2, g.n.x - 1, eave - 1, front, Kit.TRAV_W)
	g.box(1, eave - 1, 2, g.n.x - 1, eave, front, Kit.REDWASH)
	_roof(g, 1, g.n.x - 1, 2, front, eave, top - 1)
	# Small tympanum relief and terracotta antefixes; decorative interpretation.
	for z in [2, front - 2]:
		g.box(g.n.x / 2 - 2, eave + 2, z, g.n.x / 2 + 2, eave + 6, z + 1, Kit.BRONZE)
	for z in range(5, front - 2, 8):
		g.put(1, eave + 1, z, Kit.ANTEFIX)
		g.put(g.n.x - 2, eave + 1, z, Kit.ANTEFIX)

static func _forum(g: Kit.Grid) -> void:
	g.box(2, GROUND, 2, g.n.x - 2, GROUND + 1, g.n.z - 2, Kit.PAVE_L)
	for x in [3, g.n.x - 12]:
		g.box(x, GROUND + 1, 3, x + 9, GROUND + 2, g.n.z - 3, Kit.STEP)
		for z in range(6, g.n.z - 4, 10):
			_column(g, x + 4, z, GROUND + 2, GROUND + 13)
		_roof(g, x - 1, x + 10, 3, g.n.z - 3, GROUND + 13, GROUND + 16)
	for z in range(3, g.n.z - 3):
		for x in range(13, g.n.x - 13):
			if z % 4 == 0 or (x + 2 * (z / 4 % 2)) % 5 == 0:
				g.put(x, GROUND, z, Kit.PAVE_D)
	for x in [2, g.n.x - 4]:
		g.box(x, GROUND, 3, x + 2, GROUND + 9, g.n.z - 3, Kit.CREAM)
		g.box(x, GROUND + 2, 3, x + 2, GROUND + 4, g.n.z - 3, Kit.REDWASH)
	# An open square, no second temple duplicated inside it.
	g.box(g.n.x / 2 - 2, GROUND + 1, g.n.z / 2 - 2, g.n.x / 2 + 2, GROUND + 5, g.n.z / 2 + 2, Kit.MARBLE)
	g.box(g.n.x / 2 - 1, GROUND + 5, g.n.z / 2 - 1, g.n.x / 2 + 1, GROUND + 11, g.n.z / 2 + 1, Kit.BRONZE)
	g.box(g.n.x / 2 - 2, GROUND + 8, g.n.z / 2 - 1, g.n.x / 2 + 2, GROUND + 10, g.n.z / 2 + 1, Kit.BRONZE)
	g.put(g.n.x / 2, GROUND + 11, g.n.z / 2, Kit.BRONZE)

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
	for z in [z0, z1 - 1]:
		for x in range(x0 + 2, x1 - 1, 8):
			g.box(x, GROUND + 2, z, x + 2, eave, z + 1, Kit.TRAV_W)
			if x > x0 + 3 and x < x1 - 5:
				g.box(x + 2, eave - 13, z, x + 5, eave - 4, z + 1, Kit.DARK)
		for y in [GROUND + 3, eave - 2]:
			g.box(x0, y, z, x1, y + 1, z + 1, Kit.TRAV_L)
	g.box(cx - 4, GROUND, z1 - 1, cx - 3, GROUND + 14, z1, Kit.TRIM)
	g.box(cx + 3, GROUND, z1 - 1, cx + 4, GROUND + 14, z1, Kit.TRIM)
	g.box(cx - 4, GROUND + 13, z1 - 1, cx + 4, GROUND + 14, z1, Kit.TRIM)
	_roof(g, x0 - 1, x1 + 1, z0 - 1, z1 + 1, eave, top - 1)

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
	g.box(2, GROUND, 2, g.n.x - 2, GROUND + 1, g.n.z - 2, Kit.PAVE)
	# Lower service wings enclose the palaestra, with a raised central vaulted hall.
	_hall(g, 3, 22, 4, g.n.z - 4, GROUND + 20, GROUND + 27)
	_hall(g, g.n.x - 22, g.n.x - 3, 4, g.n.z - 4, GROUND + 20, GROUND + 27)
	var x0 := 23
	var x1 := g.n.x - 23
	var z0 := 4
	var z1 := g.n.z / 2 + 3
	var spring := top - 16
	g.box(x0, GROUND, z0, x1, spring, z1, Kit.BRICK)
	g.box(x0 + 2, GROUND + 1, z0 + 2, x1 - 2, spring, z1 - 2, Kit.EMPTY)
	var mid := (x0 + x1 - 1) * 0.5
	for x in range(x0 - 1, x1 + 1):
		var u := (x - mid) / (mid - x0 + 1)
		var y := spring + roundi(16.0 * sqrt(maxf(0.0, 1.0 - u * u)))
		g.box(x, spring, z0, x + 1, y, z0 + 2, Kit.BRICK)
		g.box(x, spring, z1 - 2, x + 1, y, z1, Kit.BRICK)
		for z in range(z0, z1):
			g.put(x, y, z, Kit.TILE_D if z % 4 == 0 else Kit.TILE)
	for z in [z0, z1 - 2]:
		for x in [x0, x0 + 9, x1 - 11, x1 - 2]:
			g.box(x, GROUND, z - 1, x + 2, spring - 2, z + 3, Kit.BRICKFACE)
		g.box(x0 - 1, GROUND + 2, z - 1, x1 + 1, GROUND + 5, z + 3, Kit.TRAV_W)
		g.box(x0 - 1, GROUND + 19, z - 1, x1 + 1, GROUND + 21, z + 3, Kit.TRAV_L)
	# Three arched thermal windows; transparent recess is real geometry.
	for z in [z0, z1 - 2]:
		for c in 3:
			var cx := roundi(mid) + (c - 1) * 10
			for x in range(cx - 3, cx + 4):
				for y in range(spring - 12, spring + 3):
					if _opening(x - cx, y - (spring - 12), 7, 3.0):
						g.box(x, y, z, x + 1, y + 1, z + 2, Kit.GLASS)
		g.box(x0 - 1, spring - 15, z, x1 + 1, spring - 13, z + 2, Kit.TRIM)
	g.box(roundi(mid) - 3, GROUND, z1 - 2, roundi(mid) + 3, GROUND + 12, z1, Kit.DOOR_D)
	# Marble pool rim, two descending steps and a tiled exercise court.
	var pz := g.n.z - 22
	g.box(28, GROUND + 1, pz, g.n.x - 28, GROUND + 3, g.n.z - 7, Kit.MARBLE)
	g.box(30, GROUND + 2, pz + 2, g.n.x - 30, GROUND + 3, g.n.z - 9, Kit.WATER_D)
	for x in range(26, g.n.x - 23, 8):
		_column(g, x, g.n.z - 4, GROUND + 1, GROUND + 16)
	g.box(23, GROUND + 16, g.n.z - 7, g.n.x - 23, GROUND + 18, g.n.z - 2, Kit.TILE)
	for x in [10, g.n.x - 12]:
		g.box(x, GROUND + 20, 8, x + 3, GROUND + 32, 11, Kit.BRICK)
		g.box(x - 1, GROUND + 32, 7, x + 4, GROUND + 33, 12, Kit.TRAV_W)

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
			if r > a - 2.75:
				var rows := (wall - 12) / 2
				var phase := angle * a / 3.25 + 0.5
				_arcade(g, x, z, a - r, phase, rows, 2, rows * 2)
				# Distinct open top loggia, with normal-size arches and a cornice.
				if a - r < 0.75:
					for y in range(rows * 2, wall):
						if not _opening((fposmod(phase, 1.0) - 0.5) * 13.0, y - rows * 2, 5, 3.0):
							g.put(x, GROUND + y, z, Kit.TRAV_L if y >= wall - 2 else Kit.TRAV)
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
	for x in range(5, g.n.x - 4, 14):
		g.box(x, GROUND + 4, g.n.z - 3, x + 3, GROUND + wall - 8, g.n.z - 2, Kit.TRAV_W)
	for y in [GROUND + 5, GROUND + wall / 2, GROUND + wall - 9]:
		g.box(4, y, g.n.z - 3, g.n.x - 4, y + 1, g.n.z - 2, Kit.TRAV_L)
	for x in range(10, g.n.x - 8, 14):
		for tier in 2:
			var y := GROUND + 18 + tier * 22
			g.box(x, y, g.n.z - 4, x + 6, y + 12, g.n.z - 2, Kit.TRAV_D)
			g.box(x + 2, y + 2, g.n.z - 3, x + 4, y + 9, g.n.z - 2, Kit.STATUE)
	for j in 3:
		var x := g.n.x / 2 + (j - 1) * (g.n.x / 4)
		g.box(x - 3, GROUND + 4, g.n.z - 5, x + 3, GROUND + 16, g.n.z - 3, Kit.EMPTY)
	var middle := GROUND + wall / 2
	for x in range(6, g.n.x - 5, 12):
		_column(g, x, g.n.z - 7, GROUND + 4, middle)
		_column(g, x, g.n.z - 7, middle + 3, GROUND + wall - 8)
		g.box(x + 3, middle + 5, g.n.z - 6, x + 8, middle + 16, g.n.z - 4, Kit.TRAV_D)
		g.box(x + 4, middle + 7, g.n.z - 7, x + 6, middle + 13, g.n.z - 5, Kit.STATUE)
	g.box(3, middle, g.n.z - 8, g.n.x - 3, middle + 3, g.n.z - 3, Kit.TRAV_L)
	g.box(3, GROUND + wall - 8, g.n.z - 8, g.n.x - 3, GROUND + wall - 6, g.n.z - 2, Kit.TRAV_L)
