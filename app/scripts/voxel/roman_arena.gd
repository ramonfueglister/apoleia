extends RefCounted
## Rome's amphitheatre at the diorama scale (Ramon 31.10.2026: «wir sind ein
## Diorama, alles muss geschrumpft sein», and the Colosseum must still stand
## above the houses). Its ground is sized for the people who use it in the
## simulation (docs/kit2/SCALE.md S51): the Colosseum seated about 50'000
## of Rome's 920'000, so in the sim's Rome of 1'626 SEATS = 50'000 / 566.5
## sit in it. Built in the Colosseum's form and in true human proportions
## on the town's 0.25 m voxels (roman_kit.gd): an oval 24 x 17.5 m of
## travertine with three arcades of 4 m storeys and an attic, 15 m high
## (a two-storey house is 9 m), arches 1.5 m wide, the corridor behind
## them, inner arches onto the seats, a marble podium, treads 0.5 m deep
## and high, the sand, gates at both ends, the editor's box on the north
## side, masts with pennants on the attic. SEATS spectators as tall as the
## figures in the street fill the lowest treads, the rest stay empty. A
## 0.6 x 0.44 km block of the city plan (tools/city_plans.py USER_SIZED_M,
## keep in step). Models face +z (south, to the camera). A twin in Python
## for previews without Godot: /mnt/project-files/groessen/arena-vorschau.

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Colosseum := preload("res://scripts/voxel/roman_colosseum.gd")
const V := 0.25
const GROUND := 2
const SEATS := 88 # 50'000 / 566.5 (SCALE.md)
const BOX_SEATS := 4 # in the editor's box
const SEAT_W := 0.45 # a place on a tread (the Colosseum's were about 0.4 m)
# metres
const OUT_A := 12.0 # the outer wall's half axes
const OUT_B := 8.75
const ARENA_A := 6.5 # the sand's
const ARENA_B := 3.75
const SHELL := 1.5 # outer wall and corridor
const PODIUM_W := 0.5
const TREAD := 0.5
const GATE_HALF := 0.75
# voxels
const BAYS := 26 # round the oval, 2.5 m each: pier 4 with a column, arch 6
const ROWS := 16 # a storey, 4 m
const BASE := 2
const STOREYS := 3
const ARCADE_TOP := BASE + ROWS * STOREYS
const ATTIC := 10
const WALL := ARCADE_TOP + ATTIC # 15 m
const MAST := 4
const PODIUM_TOP := 6 # 1.5 m
const PAD := 2
const HEIGHT := WALL + MAST + 2
const HEAD := [1, 2, 2, 2, 2, 1] # the arch's stepped round head
const ARC_N := 4096

## The arc length along the outer oval at ARC_N + 1 angles from 0 to TAU
## (built per grid: the models are baked on several threads at once).
static func _arc_table() -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(ARC_N + 1)
	var last := Vector2(OUT_A, 0.0)
	for i in range(1, ARC_N + 1):
		var a := TAU * float(i) / float(ARC_N)
		var p := Vector2(OUT_A * cos(a), OUT_B * sin(a))
		s[i] = s[i - 1] + p.distance_to(last)
		last = p
	return s

## Arc length along the outer oval from angle 0.
static func _arc_at(arc: PackedFloat32Array, t: float) -> float:
	var f := fposmod(t, TAU) / TAU * ARC_N
	var i := mini(int(f), ARC_N - 1)
	return arc[i] + (arc[i + 1] - arc[i]) * (f - i)

## Metres outward from the oval with half axes a, b along the ray from the
## middle (negative inside), and the ray's angle.
static func _ring(px: float, pz: float, a: float, b: float) -> Vector2:
	var u := Vector2(px / a, pz / b)
	var t := atan2(u.y, u.x)
	return Vector2((u.length() - 1.0) * Vector2(a * cos(t), b * sin(t)).length(), t)

static func _open(o: int, lr: int) -> bool:
	return o >= 2 and o <= 7 and lr >= 1 and lr <= 9 + int(HEAD[o - 2])

## The outer wall at row r: o the column in the bay (0..9), b the bay,
## layer 0 the face, 1 behind it.
static func _facade(o: int, b: int, r: int, layer: int) -> int:
	if r < GROUND:
		return Kit.EMPTY
	if r < GROUND + BASE:
		return Kit.TRAV_D
	if r < GROUND + ARCADE_TOP:
		var rr := r - GROUND - BASE
		var lr := rr % ROWS
		if lr >= ROWS - 2:
			return Kit.TRAV_L if lr == ROWS - 1 else Kit.TRAV_W # the cornice
		if _open(o, lr):
			if rr / ROWS > 0 and lr <= 2 and layer == 0:
				return Kit.TRAV_L # the parapet in the upper arches
			return Kit.EMPTY
		return Kit.TRAV_W if Kit.chance(b * 10 + o, r / 2, 0, 41, 12) else Kit.TRAV
	var ar := r - GROUND - ARCADE_TOP
	if ar >= ATTIC - 1:
		return Kit.TRAV_L
	if b % 2 == 0 and o >= 4 and o <= 5 and ar >= 3 and ar <= 5 and layer == 0:
		return Kit.EMPTY # a small window every other bay
	return Kit.TRAV

static func grid() -> Kit.Grid:
	var nx := ceili(2.0 * OUT_A / V) + 2 * PAD
	var nz := ceili(2.0 * OUT_B / V) + 2 * PAD
	var g := Kit.Grid.new(Vector3i(nx, GROUND + HEIGHT, nz))
	var y0 := GROUND
	var arc := _arc_table()
	var perim := arc[ARC_N]
	for z in nz:
		for x in nx:
			var px := (x + 0.5 - nx * 0.5) * V
			var pz := (z + 0.5 - nz * 0.5) * V
			var outer := _ring(px, pz, OUT_A, OUT_B)
			var d := -outer.x # metres in from the outer face
			var t := outer.y
			var e := _ring(px, pz, ARENA_A, ARENA_B).x # metres out from the sand
			var s := _arc_at(arc, t) / perim * BAYS
			var b := floori(s)
			var o := int((s - b) * 10.0)
			var gate := absf(pz) < GATE_HALF and absf(px) > ARENA_A * 0.6
			if d < -0.5:
				continue
			if d < 0.0:
				# the plinth round it; engaged columns and cornices proud of the face
				g.put(x, y0, z, Kit.TRAV_D)
				if d >= -0.25 and (o == 0 or o == 9):
					for r in range(y0 + BASE, y0 + ARCADE_TOP):
						var lr := (r - y0 - BASE) % ROWS
						g.put(x, r, z, Kit.TRAV_L if lr >= ROWS - 2 or lr == 0 else Kit.TRAV_W)
				elif d >= -0.25:
					for st in STOREYS:
						g.put(x, y0 + BASE + st * ROWS + ROWS - 1, z, Kit.TRAV_L)
				continue
			if d < 0.5:
				var layer := 0 if d < 0.25 else 1
				for r in range(y0, y0 + WALL):
					var c := _facade(o, b, r, layer)
					if c != Kit.EMPTY:
						g.put(x, r, z, c)
				# masts for the awning on the attic, red pennants
				if layer == 0 and b % 2 == 1 and o == 5:
					g.box(x, y0 + WALL, z, x + 1, y0 + WALL + MAST, z + 1, Kit.WOOD_D)
					g.put(x, y0 + WALL + MAST - 1, z, Kit.FLAG)
				continue
			if d < SHELL - 0.25:
				# the corridor behind the arches: a floor and a dark vault each storey
				for st in STOREYS:
					g.put(x, y0 + BASE + st * ROWS - 1 if st > 0 else y0, z, Kit.TRAV_D)
					g.put(x, y0 + BASE + st * ROWS + ROWS - 2, z, Kit.VAULT)
				g.box(x, y0 + ARCADE_TOP, z, x + 1, y0 + WALL - 1, z + 1, Kit.TRAV)
				continue
			if d < SHELL:
				# the inner wall, arched onto the seats from the second storey
				for r in range(y0, y0 + WALL - 1):
					var rr := r - y0 - BASE
					var st := rr / ROWS
					if st >= 1 and st < STOREYS and _open(o, rr % ROWS):
						continue
					g.put(x, r, z, Kit.TRAV_D if r < y0 + ARCADE_TOP else Kit.TRAV)
				continue
			# inside: the gate passages, the sand, the podium, the treads
			if e < 0.0 or gate:
				var c := Kit.SAND_D if Kit.chance(x / 4, 0, z / 3, 7, 22) else Kit.SAND
				if e >= 0.0:
					c = Kit.PAVE
				g.put(x, y0, z, c)
				continue
			if e < PODIUM_W:
				g.box(x, y0, z, x + 1, y0 + PODIUM_TOP, z + 1, Kit.PODIUM)
				g.put(x, y0 + PODIUM_TOP - 2, z, Kit.REDWASH)
				g.put(x, y0 + PODIUM_TOP, z, Kit.TRAV_L)
				continue
			var j := int((e - PODIUM_W) / TREAD)
			var top := mini(y0 + PODIUM_TOP + 2 * (j + 1), y0 + BASE + ROWS)
			var aisle := posmod(floori(s * 10.0), 30) == 5
			g.box(x, y0, z, x + 1, top - 1, z + 1, Kit.TRAV_D)
			g.put(x, top - 1, z, Kit.TRAV_L if aisle else (Kit.SEAT_HI if j < 3 else Kit.SEAT_MID))
			if aisle and int((e - PODIUM_W) / TREAD * 2.0) % 2 == 1:
				g.put(x, top, z, Kit.TRAV_L) # the half steps of the stairway
	_crowd(g, nx, nz, y0)
	# the editor's box on the north side, a red cloth over its front
	var cx := nx / 2
	var cz := nz / 2
	var bz := cz - int((ARENA_B + PODIUM_W) / V) - 6
	g.box(cx - 6, y0, bz, cx + 6, y0 + PODIUM_TOP + 4, bz + 6, Kit.MARBLE)
	g.box(cx - 6, y0 + 2, bz + 6, cx + 6, y0 + PODIUM_TOP + 2, bz + 7, Kit.CLOTH_R)
	for k in BOX_SEATS:
		_seated(g, cx - 5 + k * 3, y0 + PODIUM_TOP + 5, bz + 2, true, Kit.ROBE_R if k == 1 else Kit.ROBE_W, k)
	# two pairs of fighters on the sand and the umpire in white
	var n := 0
	for p: Vector2i in [Vector2i(-9, -2), Vector2i(-4, -2), Vector2i(4, 3), Vector2i(9, 3)]:
		Colosseum._gladiator(g, cx + p.x, y0 + 1, cz + p.y, 1 if n % 2 == 0 else -1, n)
		n += 1
	_figure(g, cx, y0 + 1, cz + 1, Kit.ROBE_W)
	return g

## SEATS less the box on the three lowest treads, spread round them, the
## gates, the box and the stairways left free.
static func _crowd(g: Kit.Grid, nx: int, nz: int, y0: int) -> void:
	var places: Array[Vector4] = [] # x, z (m), along x (1) or z (0), tread
	for j in 3:
		var e := PODIUM_W + TREAD * (j + 0.5)
		var a := ARENA_A + e
		var b := ARENA_B + e
		var walked := 0.0
		var last := Vector2(a, 0.0)
		for i in 2400:
			var t := TAU * float(i) / 2400.0
			var p := Vector2(a * cos(t), b * sin(t))
			walked += p.distance_to(last)
			last = p
			if walked < SEAT_W:
				continue
			walked = 0.0
			if absf(p.y) < GATE_HALF + 0.5 and absf(p.x) > ARENA_A * 0.6:
				continue
			if p.y < 0.0 and absf(p.x) < 1.75 and j < 2:
				continue
			places.append(Vector4(p.x, p.y, 1.0 if absf(sin(t)) > 0.6 else 0.0, j))
	places.sort_custom(func(l: Vector4, r: Vector4) -> bool: return l.w < r.w or (l.w == r.w and l.y < r.y))
	var want := mini(SEATS - BOX_SEATS, places.size())
	if want <= 0:
		return
	var step := float(places.size()) / float(want)
	for k in want:
		var p: Vector4 = places[int(k * step)]
		var x := int(floor(p.x / V + nx * 0.5))
		var z := int(floor(p.y / V + nz * 0.5))
		var tunic: int = [Kit.ROBE_W, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_O, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_B][Kit.rnd(k, 0, 0, 9) % 8]
		_seated(g, x, y0 + PODIUM_TOP + 2 * (int(p.w) + 1), z, p.z > 0.5, tunic, k)

## A person sitting on a tread (the seat at y - 1): body, face, hair.
static func _seated(g: Kit.Grid, x: int, y: int, z: int, along_x: bool, tunic: int, seed: int) -> void:
	var x1 := x + (2 if along_x else 1)
	var z1 := z + (1 if along_x else 2)
	g.box(x, y, z, x1, y + 3, z1, tunic)
	g.box(x, y + 3, z, x1, y + 4, z1, Kit.SKIN)
	g.box(x, y + 4, z, x1, y + 5, z1, Kit.HAIR if seed % 5 != 0 else Kit.SKIN)

## The umpire standing with his staff (7 voxels, 1.75 m, as Town._person).
static func _figure(g: Kit.Grid, x: int, y: int, z: int, tunic: int) -> void:
	g.box(x, y, z, x + 2, y + 2, z + 1, Kit.SKIN)
	g.box(x, y + 2, z, x + 2, y + 5, z + 1, tunic)
	g.box(x, y + 5, z, x + 2, y + 6, z + 1, Kit.SKIN)
	g.box(x, y + 6, z, x + 2, y + 7, z + 1, Kit.HAIR)
	g.box(x + 2, y, z, x + 3, y + 8, z + 1, Kit.WOOD_D)
