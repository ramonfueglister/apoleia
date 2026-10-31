extends RefCounted
## Rome's arena at the diorama scale (Ramon 31.10.2026, rule A: «wir sind
## ein Diorama, alles muss geschrumpft sein»). A building the people share is
## sized for the people who use it in the simulation, not for its real size
## (docs/kit2/SCALE.md S51): the Colosseum seated about 50'000 of Rome's
## 920'000, so in the sim's Rome of 1'626 it seats SEATS = 50'000 / 566.5.
## Built in true human proportions on the town's 0.25 m voxels
## (roman_kit.gd), so the spectators are as tall as the figures in the
## street: an oval of sand 18 x 11 m, a painted timber podium fence, one row
## of benches on a timber deck with a rail behind, a grassed earth bank
## outside, gates with timber towers at both ends, the editor's box under a
## tiled roof on the north side, stairs up the bank on the south. That is
## how the first amphitheatres were built before stone ones (timber stands
## on earth banks; Welch, 2007, The Roman Amphitheatre). 25 x 18 m in all,
## a 0.6 x 0.43 km block of the city plan (tools/city_plans.py
## USER_SIZED_M, keep in step). Models face +z (south, to the camera).

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Colosseum := preload("res://scripts/voxel/roman_colosseum.gd")
const V := 0.25
const GROUND := 2
const SEATS := 88 # 50'000 / 566.5 (SCALE.md)
const BOX_SEATS := 6 # in the editor's box
const SEAT_W := 0.45 # a place on the bench (the Colosseum's were about 0.4 m)
# metres from the middle and outward from the sand's edge
const ARENA_A := 9.0
const ARENA_B := 5.5
const FENCE := 0.5
const DECK := 1.25 # the bench and the walk behind it
const RAIL := 0.25
const BANK := 1.25
const GATE_HALF := 1.25 # half the gate's width
const BOX_HALF := 1.75 # half the editor's box
const STAIRS_X := 4.5 # the stairs up the bank on the south side, either way from the middle
const PAD := 1 # voxels round the bank
# layers above the ground
const FENCE_TOP := 6 # the fence's cap, the deck at the same height (1.75 m)
const BENCH := 8 # the bench's seat
const RAIL_TOP := 10
const POST_TOP := 13
const BOX_DECK := 9
const ROOF := 18
const TOWER_TOP := 16
const HEIGHT := 22

static func _outer_a() -> float:
	return ARENA_A + FENCE + DECK + RAIL + BANK

static func _outer_b() -> float:
	return ARENA_B + FENCE + DECK + RAIL + BANK

## Metres outward from the sand's edge along the ray from the middle
## (negative on the sand), and the ray's angle.
static func _dist(px: float, pz: float) -> Vector2:
	var u := Vector2(px / ARENA_A, pz / ARENA_B)
	var t := atan2(u.y, u.x)
	return Vector2((u.length() - 1.0) * Vector2(ARENA_A * cos(t), ARENA_B * sin(t)).length(), t)

static func _in_gate(px: float, pz: float) -> bool:
	return absf(pz) < GATE_HALF and absf(px) > ARENA_A * 0.7

static func _in_box(px: float, pz: float) -> bool:
	return pz < 0.0 and absf(px) < BOX_HALF

static func grid() -> Kit.Grid:
	var nx := ceili(2.0 * _outer_a() / V) + 2 * PAD
	var nz := ceili(2.0 * _outer_b() / V) + 2 * PAD
	var g := Kit.Grid.new(Vector3i(nx, GROUND + HEIGHT, nz))
	var y0 := GROUND
	for z in nz:
		for x in nx:
			var px := (x + 0.5 - nx * 0.5) * V
			var pz := (z + 0.5 - nz * 0.5) * V
			var dt := _dist(px, pz)
			var d := dt.x
			var t := dt.y
			# posts about every 2 m round the oval (24 of them, a voxel wide)
			var post := posmod(int(floor(t / TAU * 192.0)), 8) == 0
			if d < 0.0 or (_in_gate(px, pz) and d < FENCE + DECK + RAIL + BANK):
				# the sand, raked in bands; the gate ways trodden
				var c := Kit.SAND_D if Kit.chance(x / 4, 0, z / 3, 7, 22) else Kit.SAND
				if d >= 0.0:
					c = Kit.PATH
				g.put(x, y0, z, c)
				continue
			if d < FENCE:
				# the podium fence: planks, a red band, a cap; posts above it
				g.box(x, y0, z, x + 1, y0 + FENCE_TOP, z + 1, Kit.TIMBER)
				g.box(x, y0 + 3, z, x + 1, y0 + 5, z + 1, Kit.REDWASH)
				g.put(x, y0 + FENCE_TOP, z, Kit.WOOD)
				if _in_box(px, pz):
					g.box(x, y0 + 2, z, x + 1, y0 + FENCE_TOP, z + 1, Kit.CLOTH_R) # a cloth over the fence below the box
				continue
			if d < FENCE + DECK:
				var deck := y0 + (BOX_DECK if _in_box(px, pz) else FENCE_TOP)
				g.box(x, y0, z, x + 1, deck, z + 1, Kit.TIMBER_W)
				g.put(x, deck, z, Kit.WOOD)
				var e := d - FENCE
				if not _in_box(px, pz) and e >= 0.1 and e < 0.6:
					g.box(x, y0 + FENCE_TOP + 1, z, x + 1, y0 + BENCH + 1, z + 1, Kit.SEAT_WOOD)
				continue
			if d < FENCE + DECK + RAIL:
				# the rail behind the walk, its posts higher
				var top := y0 + (POST_TOP if post else RAIL_TOP)
				if _in_box(px, pz):
					top = y0 + BOX_DECK + 4
				g.box(x, y0, z, x + 1, top + 1, z + 1, Kit.TIMBER)
				if post:
					g.put(x, top, z, Kit.TIMBER_W)
				continue
			if d < FENCE + DECK + RAIL + BANK:
				# the earth bank, grassed, down to the ground; timber stairs on the south
				var b := (d - FENCE - DECK - RAIL) / BANK
				var h := maxi(int(round((1.0 - b) * FENCE_TOP)), 0)
				var stairs := pz > 0.0 and absf(absf(px) - STAIRS_X) < 0.5
				for y in h:
					g.put(x, y0 + y, z, Kit.EARTH)
				if stairs:
					g.put(x, y0 + h, z, Kit.WOOD)
				else:
					g.put(x, y0 + h, z, Kit.GRASS_L if Kit.chance(x, z, 0, 9, 30) else Kit.GRASS)
	_gates(g, nx, nz, y0)
	_box(g, nx, nz, y0)
	_crowd(g, nx, nz, y0)
	# two pairs of fighters on the sand and the umpire in white
	var cx := nx / 2
	var cz := nz / 2
	var k := 0
	for p: Vector2i in [Vector2i(-12, -4), Vector2i(-6, -4), Vector2i(6, 5), Vector2i(12, 5)]:
		Colosseum._gladiator(g, cx + p.x, y0 + 1, cz + p.y, 1 if k % 2 == 0 else -1, k)
		k += 1
	_figure(g, cx, y0 + 1, cz + 1, Kit.ROBE_W, true)
	return g

## The two gates at the ends of the long axis: a timber tower each side,
## a beam across, red pennants on top.
static func _gates(g: Kit.Grid, nx: int, nz: int, y0: int) -> void:
	var cz := nz / 2
	var half := int(GATE_HALF / V)
	for side: int in [-1, 1]:
		var inner := nx / 2 + side * int(ARENA_A / V)
		var outer := nx / 2 + side * int((ARENA_A + FENCE + DECK + RAIL) / V)
		for gx: int in [inner, outer]:
			for gz: int in [cz - half - 2, cz + half]:
				g.box(gx - 1, y0, gz, gx + 1, y0 + TOWER_TOP, gz + 2, Kit.TIMBER)
				g.box(gx - 1, y0 + TOWER_TOP, gz, gx + 1, y0 + TOWER_TOP + 1, gz + 2, Kit.WOOD)
				g.box(gx, y0 + TOWER_TOP + 1, gz, gx + 1, y0 + TOWER_TOP + 4, gz + 1, Kit.TIMBER_W)
				g.box(gx + side, y0 + TOWER_TOP + 2, gz, gx + side + 1, y0 + TOWER_TOP + 4, gz + 1, Kit.FLAG)
			g.box(gx - 1, y0 + TOWER_TOP - 2, cz - half, gx + 1, y0 + TOWER_TOP, cz + half, Kit.TIMBER_W)

## The editor's box on the north side: posts, a little tiled roof, the
## editor in red among his guests in white.
static func _box(g: Kit.Grid, nx: int, nz: int, y0: int) -> void:
	var cx := nx / 2
	var half := int(BOX_HALF / V)
	var front := nz / 2 - int((ARENA_B + FENCE) / V)
	var back := nz / 2 - int((ARENA_B + FENCE + DECK + RAIL) / V)
	for bx: int in [cx - half, cx + half - 1]:
		for bz: int in [front - 1, back]:
			g.box(bx, y0 + BOX_DECK, bz, bx + 1, y0 + ROOF, bz + 1, Kit.TIMBER)
	g.box(cx - half - 1, y0 + ROOF, back - 1, cx + half + 1, y0 + ROOF + 1, front + 1, Kit.EAVE)
	g.box(cx - half, y0 + ROOF + 1, back, cx + half, y0 + ROOF + 2, front, Kit.TILE)
	g.box(cx - half + 1, y0 + ROOF + 2, back + 1, cx + half - 1, y0 + ROOF + 3, front - 1, Kit.RIDGE)
	for k in BOX_SEATS:
		var x := cx - half + 1 + k * 2
		_seated(g, x, y0 + BOX_DECK + 1, front - 3, true, Kit.ROBE_R if k == BOX_SEATS / 2 else Kit.ROBE_W, k)

## The spectators shoulder to shoulder on the bench: SEATS less the box,
## spread evenly over the places on it.
static func _crowd(g: Kit.Grid, nx: int, nz: int, y0: int) -> void:
	var a := ARENA_A + FENCE + 0.35
	var b := ARENA_B + FENCE + 0.35
	var places: Array[Vector3] = [] # x, z, along x (1) or z (0)
	var steps := 2000
	var walked := 0.0
	var last := Vector2(a, 0.0)
	for i in steps:
		var t := TAU * float(i) / float(steps)
		var p := Vector2(a * cos(t), b * sin(t))
		walked += p.distance_to(last)
		last = p
		if walked < SEAT_W:
			continue
		walked = 0.0
		var by_gate := absf(p.y) < GATE_HALF + 0.5 and absf(p.x) > ARENA_A * 0.7
		var by_box := p.y < 0.0 and absf(p.x) < BOX_HALF + 0.25
		if by_gate or by_box:
			continue
		places.append(Vector3(p.x, p.y, 1.0 if absf(sin(t)) > 0.6 else 0.0))
	var want := mini(SEATS - BOX_SEATS, places.size())
	for k in want:
		var at: Vector3 = places[int(float(k) * places.size() / want)]
		var x := int(floor(at.x / V + nx * 0.5))
		var z := int(floor(at.y / V + nz * 0.5))
		var tunic: int = [Kit.ROBE_W, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_O, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_B][Kit.rnd(k, 0, 0, 9) % 8]
		_seated(g, x, y0 + BENCH + 1, z, at.z > 0.5, tunic, k)

## A person sitting on the bench (the seat at y - 1): body, face, hair.
static func _seated(g: Kit.Grid, x: int, y: int, z: int, along_x: bool, tunic: int, seed: int) -> void:
	var x1 := x + (2 if along_x else 1)
	var z1 := z + (1 if along_x else 2)
	g.box(x, y, z, x1, y + 3, z1, tunic)
	g.box(x, y + 3, z, x1, y + 4, z1, Kit.SKIN)
	g.box(x, y + 4, z, x1, y + 5, z1, Kit.HAIR if seed % 5 != 0 else Kit.SKIN)

## A person standing (7 voxels, 1.75 m), as Town._person.
static func _figure(g: Kit.Grid, x: int, y: int, z: int, tunic: int, staff: bool) -> void:
	g.box(x, y, z, x + 2, y + 2, z + 1, Kit.SKIN)
	g.box(x, y + 2, z, x + 2, y + 5, z + 1, tunic)
	g.box(x, y + 5, z, x + 2, y + 6, z + 1, Kit.SKIN)
	g.box(x, y + 6, z, x + 2, y + 7, z + 1, Kit.HAIR)
	if staff:
		g.box(x + 2, y, z, x + 3, y + 8, z + 1, Kit.WOOD_D)
