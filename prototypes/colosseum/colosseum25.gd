extends RefCounted
## The Colosseum in Urbek's craft on the town's 0.25 m voxels (urbek_kit.gd):
## 74 x 61 m, 21 m to the rim. The oval is a staircase of straight bays,
## 3 m each (Urbek draws curves as runs of flat panels): an arch 8 voxels
## wide with a stepped round head and a light archivolt, a pier with an
## engaged column, base and capital, a frieze and a cornice two voxels proud
## on every storey. Three arcades, upper arches with parapets; a closed attic
## with pilasters, windows and bronze shields in turn, corbels and masts with
## red flags. Inside: a portico round the top walkway, the cavea in treads of
## 4 x 2 voxels with low walls and entrances, a marble podium with a red
## band, and the sand. Rows 0 and 1 are left to the ground it stands on
## (plaza lots), as in every town lot.

const Kit := preload("res://urbek_kit.gd")
const V := 0.25
const A := 37.0
const B := 30.5
const P := 12                  # bay: pier 4 (column in the middle), arch 8
const GROUND := 2
const BASE := GROUND + 2       # two plinth steps
const ROWS := 22               # an arcade storey, 5.5 m
const ARCADE_TOP := BASE + ROWS * 3
const ATTIC := 16
const WALL := ARCADE_TOP + ATTIC
const MAST := 10
const SHELL := 10              # outer wall; arches open 8 deep onto the corridor
const RIM := 8                 # walkway under the portico
const ARENA_A := 18.5
const ARENA_B := 12.0
const SEAT_TOP := WALL - 8
const PODIUM := SEAT_TOP - 34
const FLOOR := PODIUM - 6
const PAVING := 4              # grid margin round the plinth, voxels
const HEAD := [2, 3, 4, 4, 4, 4, 3, 2]
const CACHE := "user://colosseum25_v5.res"
const AISLES := 40
const CROWD := [Kit.ROBE_W, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_B, Kit.CLOTH_Y, Kit.CLOTH_G, Kit.LINEN]

# --- plan -----------------------------------------------------------------

static func _band(i: int) -> int:
	return floori((i + P / 2) / float(P))

static func _band_sub(i: int) -> int:
	return posmod(i + P / 2, P)

## Facade position (voxels from the centre) of the run of bays `band` on an
## ellipse with half-axes `along` (the run's axis) and `across`.
static func _run_face(band: int, along: float, across: float) -> int:
	var b := minf(absf(band) * P, along - 1.0)
	return roundi(across * sqrt(maxf(0.0, 1.0 - (b / along) ** 2)))

## The stepped plan: [depth from the facade, column in the bay, bay id].
## Where the oval runs flatter than SLOPE the bays are runs facing south or
## north, else east or west. The game camera never turns and looks north,
## so the south-facing runs, which show their arches, reach far round.
const SLOPE := 1.6

static func _plan(ix: int, iz: int) -> Vector3i:
	var av := A / V
	var bv := B / V
	var x45 := av * av * SLOPE / sqrt(bv * bv + av * av * SLOPE * SLOPE)
	var z45 := bv * bv / sqrt(av * av * SLOPE * SLOPE + bv * bv)
	var qx := ix if ix >= 0 else -ix - 1
	var qz := iz if iz >= 0 else -iz - 1
	var bxn := _band(ix)
	var bzn := _band(iz)
	var zfam := absi(bxn) * P <= x45
	var xfam := absi(bzn) * P <= z45
	var dz := _run_face(bxn, av, bv) - 1 - qz
	var dx := _run_face(bzn, bv, av) - 1 - qx
	var use_z := true
	var d := 0
	if zfam and xfam:
		use_z = dz <= dx
		d = mini(dz, dx)
	elif zfam:
		d = dz
	elif xfam:
		use_z = false
		d = dx
	else:
		var xe := int(x45 / P + 1) * P
		var ze := int(z45 / P + 1) * P
		d = mini(xe - 1 - qx, ze - 1 - qz)
	if use_z:
		return Vector3i(d, _band_sub(ix), bxn + (1000 if iz < 0 else 0))
	return Vector3i(d, _band_sub(iz), bzn + 2000 + (1000 if ix < 0 else 0))

# --- facade ---------------------------------------------------------------

## Is (o, lr) inside an arch: o 0..7 across the opening, lr the row in the
## storey; rows 1 to 14 straight, then the stepped round head.
static func _open(o: int, lr: int) -> bool:
	return o >= 0 and o <= 7 and lr >= 1 and lr <= 14 + HEAD[o]

## The light ring round an arch head.
static func _ring(o: int, lr: int) -> bool:
	if lr < 12 or _open(o, lr):
		return false
	return _open(o - 1, lr) or _open(o + 1, lr) or _open(o, lr - 1)

## Ashlar: blocks three voxels long and two high, staggered, a few of them
## weathered darker.
static func _ashlar(s: int, b: int, r: int) -> int:
	var course := r / 2
	var block := (s + b * P + (course % 2) * 2) / 3
	return Kit.TRAV_W if Kit.rnd(block, course, b, 41) % 100 < 12 else Kit.TRAV

static func _shell(d: int, s: int, b: int, r: int) -> int:
	if r < GROUND:
		return Kit.EMPTY
	if r < BASE:
		return Kit.TRAV_D
	if r < ARCADE_TOP:
		var lr := (r - BASE) % ROWS
		var storey := (r - BASE) / ROWS
		var o := s - 2
		if _open(o, lr):
			if storey > 0 and lr <= 3 and d == 1:
				return Kit.TRAV_L
			# a statue in every other upper arch, behind the parapet
			if storey > 0 and posmod(b, 2) == 0 and d == 3 and (o == 3 or o == 4) and lr <= 10:
				return Kit.MARBLE
			if d < SHELL - 2:
				return Kit.EMPTY
			# the corridor wall in the half light, a smaller arch in it
			# leading on into the dark
			if o >= 2 and o <= 5 and lr <= 9 + (2 if o == 3 or o == 4 else 0):
				return Kit.DEEP
			return Kit.ARCADE
		if lr == 0 and o >= 0 and o <= 7 and d < SHELL - 2:
			return Kit.PAVE
		if d == 0 and _ring(o, lr):
			return Kit.TRAV_L
		if lr == 21:
			return Kit.TRAV_L
		if lr == 20:
			return Kit.TRAV
		return _ashlar(s, b, r)
	var ar := r - ARCADE_TOP
	if posmod(b, 2) == 0 and s >= 4 and s <= 7 and ar >= 5 and ar <= 9:
		return Kit.EMPTY if d == 0 else (Kit.VAULT if d == 1 else Kit.TRAV)
	if ar >= 14 or ar == 0:
		return Kit.TRAV_L
	return _ashlar(s, b, r)

static func _outside(d: int, s: int, b: int, r: int, x: int, z: int) -> int:
	if r < GROUND:
		return Kit.EMPTY
	if r < BASE:
		return Kit.TRAV_D if d >= -2 - (BASE - 1 - r) else Kit.EMPTY
	if d < -2:
		return Kit.EMPTY
	var col := s == P - 1 or s == 0
	var wide := s >= P - 2 or s <= 1
	if r < ARCADE_TOP:
		var lr := (r - BASE) % ROWS
		if lr == 21:
			return Kit.TRAV_L
		if d == -2:
			return Kit.EMPTY
		if lr == 20:
			return Kit.TRAV
		if wide and (lr == 1 or lr == 18):
			return Kit.TRAV_L
		if col and lr == 17:
			return Kit.TRAV_L
		if col and lr >= 1 and lr <= 19:
			return Kit.TRAV
		return Kit.EMPTY
	if r < WALL:
		var ar := r - ARCADE_TOP
		if ar == 15:
			return Kit.TRAV_L
		if d == -2:
			return Kit.EMPTY
		if ar == 14 or ar == 0:
			return Kit.TRAV_L
		if ar == 12 and s == 0:
			return Kit.TRAV_L
		if col and ar <= 13:
			return Kit.TRAV
		if posmod(b, 2) == 1 and s >= 5 and s <= 6 and ar >= 6 and ar <= 8:
			return Kit.BRONZE
		return Kit.EMPTY
	return Kit.EMPTY

## A mast on the attic of every second bay, a red flag on it.
static func _mast(d: int, s: int, b: int, mr: int) -> int:
	if d != 1 or posmod(b, 2) == 1 or mr >= MAST:
		return Kit.EMPTY
	if s == 0:
		return Kit.WOOD_D
	if (s == 1 or s == 2) and mr >= MAST - 4 and mr < MAST - 1:
		return Kit.FLAG
	return Kit.EMPTY

# --- inside ---------------------------------------------------------------

## e: depth from the oval in voxels, arena: e at the arena's edge.
static func _cavea(e: int, s: int, b: int, r: int, arena: int, x: int, z: int, t: float) -> int:
	if r < GROUND:
		return Kit.EMPTY
	if e >= arena:
		if r < FLOOR:
			return Kit.TRAV_D
		if r == FLOOR:
			return Kit.SAND_D if Kit.chance((x + (z / 6 % 2) * 3) / 6, 0, z / 6, 5, 14) else Kit.SAND
		return Kit.EMPTY
	if e >= arena - 2:
		if r < PODIUM:
			return Kit.PODIUM
		return Kit.REDWASH if r == PODIUM else Kit.EMPTY
	var first := SHELL + RIM
	if e < first:
		if r < SEAT_TOP - 1:
			return Kit.TRAV_D
		if r == SEAT_TOP - 1:
			return Kit.PAVE
		if r == WALL - 1 and e < SHELL + RIM / 2:
			return Kit.TILE
		if r == WALL - 2 and e >= SHELL + RIM / 2:
			return Kit.TILE
		if e == first - 1 and posmod(b * P + s, 5) < 2 and r < WALL - 1:
			return Kit.TRAV_L
		return Kit.EMPTY
	var j := e - first
	var step := j / 4
	var top := maxi(SEAT_TOP - 2 - 2 * step, PODIUM + 1)
	# radial stairways; spectators in groups on some treads
	var round := t * AISLES / TAU
	var aisle := fposmod(round, 1.0) < 0.07
	if r < top - 2:
		return Kit.TRAV_D
	if r < top:
		if aisle:
			return Kit.TRAV_L
		return Kit.SEAT_D if j % 4 == 0 else Kit.SEAT
	if not aisle and j % 4 == 2 and r <= top + 1 and (x + z) % 2 == 0:
		var group := Kit.rnd(floori(round * 3.0), step, 0, 3) % 100
		if group < 28:
			if r == top + 1:
				return Kit.SKIN
			return CROWD[Kit.rnd(x, z, 0, 4) % CROWD.size()]
	# low walls splitting the cavea into three bands, entrances in them
	if j % 4 == 3 and (step == 5 or step == 10) and r < top + 3:
		if posmod(b, 4) == 0 and s >= 3 and s <= 8:
			return Kit.EMPTY
		return Kit.PODIUM
	return Kit.EMPTY

# --- build ----------------------------------------------------------------

static func grid() -> Kit.Grid:
	var nx := ceili(2.0 * A / V) + 2 * (PAVING + 2)
	var nz := ceili(2.0 * B / V) + 2 * (PAVING + 2)
	var g := Kit.Grid.new(Vector3i(nx, WALL + MAST + 1, nz))
	var lo := Vector3(-nx * V * 0.5, 0.0, -nz * V * 0.5)
	for z in nz:
		for x in nx:
			var ix := x - nx / 2
			var iz := z - nz / 2
			var plan := _plan(ix, iz)
			var d := plan.x
			if d < -PAVING:
				continue
			var p := lo + Vector3(x + 0.5, 0, z + 0.5) * V
			var t := atan2(p.z / B, p.x / A)
			var e := floori((1.0 - Vector2(p.x / A, p.z / B).length()) * Vector2(A * cos(t), B * sin(t)).length() / V)
			var ta := atan2(p.z / ARENA_B, p.x / ARENA_A)
			var ea := Vector2(p.x / ARENA_A, p.z / ARENA_B).length()
			var arena := e + floori((ea - 1.0) * Vector2(ARENA_A * cos(ta), ARENA_B * sin(ta)).length() / V) + 1
			var row := x + nx * g.n.y * z
			for r in g.n.y:
				var c := Kit.EMPTY
				if d < 0:
					c = _outside(d, plan.y, plan.z, r, x, z)
				elif d < SHELL:
					c = _shell(d, plan.y, plan.z, r) if r < WALL else _mast(d, plan.y, plan.z, r - WALL)
				else:
					c = _cavea(e, plan.y, plan.z, r, arena, x, z, t)
				if c != Kit.EMPTY:
					g.g[row + nx * r] = c
	return g

## The full-detail mesh, centred on the arena, base at y = 0; cached.
static func mesh() -> ArrayMesh:
	if ResourceLoader.exists(CACHE):
		var cached: ArrayMesh = load(CACHE)
		if cached:
			cached.surface_set_material(0, Kit.material())
			return cached
	var g := grid()
	var m := Kit.mesh(g, Vector3(-g.n.x * V * 0.5, 0.0, -g.n.z * V * 0.5))
	ResourceSaver.save(m, CACHE)
	return m
