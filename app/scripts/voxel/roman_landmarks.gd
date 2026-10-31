extends RefCounted
## Rome's circus, theatre and baths at the diorama scale, by the landmark
## rule of the arena (roman_arena.gd, docs/kit2/SCALE.md): against a house
## (a 10 m lot, the tallest house 16 m) a landmark's footprint grows with
## the cube root of its real area and its height with the cube root above
## 16 m, its own shape kept; people, horses, doors and seats stay true size.
##   Circus Maximus 621 × 118 m, 28 m: 69 × 13 m, 19.25 m, the obelisk 18 m
##   Theatre of Marcellus Ø 130 m, 32.6 m: Ø 28 m, 20.25 m
##   Baths of Caracalla 214 × 110 m, 38.5 m: 34.7 × 18.6 m, the dome 21.4 m
## So all stand above every house and keep the real order: the Colosseum
## (23 m), the baths, the theatre, the circus. Each holds the people the
## simulation sends (real seats or bathers / 566.5, S51): 265 in the
## circus, 26 in the theatre, 3 bathers; the rest of the seats stay empty.
## The same craft as the arena: 0.25 m voxels (roman_kit.gd), travertine
## arcades with arches 1.5 m wide, treads 0.5 m deep and high, people 7
## voxels. Each is a block of the city plan (tools/city_plans.py
## USER_SIZED_M, keep in step). Models face +z (south, to the camera); the
## theatre's stage stands on the west side, the circus's starting gates at
## the west end, as in Rome. Twins in Python for previews without Godot:
## /mnt/project-files/groessen/ein-massstab/vorschau-code (vd.py, lmk.py).

const Kit := preload("res://scripts/voxel/roman_kit.gd")
const Arena := preload("res://scripts/voxel/roman_arena.gd")
const V := 0.25
const GROUND := 2
const BASE := 2 # the plinth under the arcades, voxels
const BAY_M := 2.5 # an arcade bay along a wall: pier 4 tenths, arch 6
const HEAD := [1, 2, 2, 2, 2, 1] # the arch's stepped round head
const TUNICS := [Kit.ROBE_W, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_R, Kit.ROBE_O, Kit.ROBE_N, Kit.ROBE_W, Kit.ROBE_B]
const SEAT_W := 0.45

# Circus Maximus
const CIRCUS_L := 69.0
const CIRCUS_W := 13.0
const CIRCUS_ROWS := 24 # a storey, 6 m
const CIRCUS_STOREYS := 3
const CIRCUS_ATTIC := 3 # the wall 19.25 m
const CIRCUS_SEATS := 265 # 150'000 / 566.5
const TRACK_HALF := 4.0
const CARCERES := 3.0 # the starting gates' building
const CIRCUS_PODIUM := 6
const OBELISK := 73 # 23.7 m by the rule: 18.25 m
# Theatre of Marcellus
const THEATRE_R := 14.0 # the cavea's outer radius
const THEATRE_ROWS := 28 # a storey, 7 m
const THEATRE_STOREYS := 2
const THEATRE_ATTIC := 23 # the wall 20.25 m
const THEATRE_SEATS := 26 # 15'000 / 566.5
const STAGE := 4.0 # pulpitum, stage front and the stage building behind the diameter
const ORCH := 3.75
const THEATRE_PODIUM := 4
# Baths of Caracalla: laid out on a 27 m plan, stretched by BATHS_K to the
# rule's 34.7 m, the halls' heights by BATHS_HS
const BATHS_W := 27.0
const BATHS_D := 11.0
const BATHS_K := 34.7 / 27.0
const BATHS_HS := 1.9
const BATHS_STOREY := 24
const BATHS_WIN_H := 11
const BATHS_ROWS := 24
const BATHS_RC := 4.0 # the caldarium's radius on the plan
const BATHS_DRUM := 15.8 # metres: the dome's top 21.4 m

## Column in the bay (0..9) and the bay, s metres along a wall.
static func _bay(s: float) -> Vector2i:
	var q := s / BAY_M
	var b := floori(q)
	return Vector2i(int((q - b) * 10.0), b)

static func _arch(o: int, lr: int, rows: int) -> bool:
	return o >= 2 and o <= 7 and lr >= 1 and lr <= rows - 7 + int(HEAD[o - 2])

## The outer wall at row rr above the floor: arcades of `rows` voxels and an
## attic; layer 0 the face, 1 behind it.
static func _facade(o: int, b: int, rr: int, layer: int, storeys: int, attic: int, rows: int) -> int:
	if rr < BASE:
		return Kit.TRAV_D
	var top := BASE + rows * storeys
	if rr < top:
		var r := rr - BASE
		var lr := r % rows
		if lr >= rows - 2:
			return Kit.TRAV_L if lr == rows - 1 else Kit.TRAV_W # the cornice
		if _arch(o, lr, rows):
			if r / rows > 0 and lr <= 2 and layer == 0:
				return Kit.TRAV_L # the parapet in the upper arches
			return Kit.EMPTY
		return Kit.TRAV_W if Kit.chance(b * 10 + o, r / 2, 0, 41, 12) else Kit.TRAV
	var ar := rr - top
	if ar >= attic:
		return Kit.EMPTY
	if ar >= attic - 1:
		return Kit.TRAV_L
	if b % 2 == 0 and o >= 4 and o <= 5 and ar >= 3 and ar <= 5 and layer == 0:
		return Kit.EMPTY # a small window every other bay
	return Kit.TRAV

## Outer wall, corridor and inner wall of a cavea, d metres in from the
## outer face, s metres along it; the inner wall from row inner_from, its
## arches onto the seats from the second storey.
static func _shell(g: Kit.Grid, x: int, z: int, d: float, s: float, storeys: int, attic: int, rows: int, inner_from: int) -> void:
	var y0 := GROUND
	var ob := _bay(s)
	var wall := BASE + rows * storeys + attic
	if d < 0.5:
		var layer := 0 if d < 0.25 else 1
		for rr in wall:
			var c := _facade(ob.x, ob.y, rr, layer, storeys, attic, rows)
			if c != Kit.EMPTY:
				g.put(x, y0 + rr, z, c)
		return
	if d < 1.25:
		# the corridor: a floor each storey and the vault's dark ceiling
		for st in storeys:
			g.put(x, y0 + (BASE + st * rows - 1 if st > 0 else 0), z, Kit.TRAV_D)
			g.put(x, y0 + BASE + st * rows + rows - 2, z, Kit.VAULT)
		if attic > 0:
			g.box(x, y0 + BASE + rows * storeys, z, x + 1, y0 + wall - 1, z + 1, Kit.TRAV)
		return
	for rr in range(inner_from, wall - 1):
		var r := rr - BASE
		var st := r / rows
		if st >= 1 and st < storeys and _arch(ob.x, r % rows, rows):
			continue
		g.put(x, y0 + rr, z, Kit.TRAV_D if rr < BASE + rows * storeys else Kit.TRAV)

## A person standing (7 voxels, 1.75 m), without the arena umpire's staff.
static func _person(g: Kit.Grid, x: int, y: int, z: int, tunic: int) -> void:
	g.box(x, y, z, x + 2, y + 2, z + 1, Kit.SKIN)
	g.box(x, y + 2, z, x + 2, y + 5, z + 1, tunic)
	g.box(x, y + 5, z, x + 2, y + 6, z + 1, Kit.SKIN)
	g.box(x, y + 6, z, x + 2, y + 7, z + 1, Kit.HAIR)

# ---------------------------------------------------------------- circus

## The Circus Maximus: the straight stands along the track, the curved end
## in the east with its gate, the starting gates between two towers in the
## west, the spina with its water basins, the obelisk, the turning posts
## and the lap counters, the emperor's box on the north side, four
## two-horse chariots, one for each faction.
static func circus() -> Kit.Grid:
	var l := CIRCUS_L
	var half := CIRCUS_W / 2.0
	var xw := -l / 2.0 # the flat west end
	var xc := l / 2.0 - half # the curved east end's centre
	var pad := 2
	var nx := int(l / V) + 2 * pad
	var nz := int(CIRCUS_W / V) + 2 * pad
	var rows := CIRCUS_ROWS
	var storeys := CIRCUS_STOREYS
	var attic := CIRCUS_ATTIC
	var wall := BASE + rows * storeys + attic
	var tower := wall
	var g := Kit.Grid.new(Vector3i(nx, GROUND + wall + 12, nz))
	var y0 := GROUND
	var pt := CIRCUS_PODIUM
	for z in nz:
		for x in nx:
			var px := (x + 0.5 - nx * 0.5) * V
			var pz := (z + 0.5 - nz * 0.5) * V
			var d := 0.0 # metres in from the outer face
			var s := 0.0 # metres along it
			var e := 0.0 # metres out from the track
			if px <= xc:
				d = minf(half - absf(pz), px - xw)
				s = px - xw if pz > 0.0 else l - (px - xw)
				e = absf(pz) - TRACK_HALF
			else:
				var rr := Vector2(px - xc, pz).length()
				d = half - rr
				s = (xc - xw) + half * (atan2(pz, px - xc) + PI)
				e = rr - TRACK_HALF
			if d < -0.5:
				continue
			if d < 0.0:
				g.put(x, y0, z, Kit.TRAV_D)
				continue
			if px - xw < CARCERES:
				_carceres(g, x, z, y0, px - xw, pz, d, tower)
				continue
			if e < 0.0:
				g.put(x, y0, z, Kit.SAND_D if Kit.chance(x / 4, 0, z / 3, 7, 22) else Kit.SAND)
				continue
			if px > xc + 1.0 and absf(pz) < 0.75:
				# the gate in the curved end
				g.put(x, y0, z, Kit.PAVE)
				if d < 1.5:
					g.put(x, y0 + 14, z, Kit.TRAV_L)
					g.box(x, y0 + 15, z, x + 1, y0 + wall + 2, z + 1, Kit.TRAV)
					g.put(x, y0 + wall + 2, z, Kit.TRAV_L)
				continue
			if d < 1.5:
				_shell(g, x, z, d, s, storeys, attic, rows, pt + 6)
				continue
			if e < 0.5:
				g.box(x, y0, z, x + 1, y0 + pt, z + 1, Kit.PODIUM)
				g.put(x, y0 + pt - 2, z, Kit.REDWASH)
				g.put(x, y0 + pt, z, Kit.TRAV_L)
				continue
			var j := mini(int((e - 0.5) / 0.5), 2)
			var top := y0 + pt + 2 * (j + 1)
			g.box(x, y0, z, x + 1, top - 1, z + 1, Kit.TRAV_D)
			var aisle := int(s / BAY_M * 10.0) % 30 == 5
			g.put(x, top - 1, z, Kit.TRAV_L if aisle else (Kit.SEAT_HI if j == 0 else Kit.SEAT_MID))
	var cz := nz / 2
	# the spina: a low wall with water basins, the obelisk, the turning posts, the lap counters
	var sa := xw + CARCERES + 0.15 * l
	var sb := xc - 3.5
	var smid := (sa + sb) / 2.0
	var sx0 := _at(sa, nx)
	var sx1 := _at(sb, nx)
	g.box(sx0, y0, cz - 2, sx1, y0 + 3, cz + 2, Kit.TRAV)
	g.box(sx0 + 1, y0 + 3, cz - 2, sx1 - 1, y0 + 4, cz + 2, Kit.TRAV_L)
	g.box(sx0 + 6, y0 + 3, cz - 1, _at(smid - 3.0, nx), y0 + 4, cz + 1, Kit.WATER)
	g.box(_at(smid + 3.0, nx), y0 + 3, cz - 1, sx1 - 6, y0 + 4, cz + 1, Kit.WATER)
	var ox := _at(smid, nx)
	g.box(ox - 3, y0 + 3, cz - 3, ox + 3, y0 + 7, cz + 3, Kit.MARBLE)
	for k in OBELISK - 8:
		var f := float(k) / float(OBELISK - 8)
		var hw := 3 if f < 0.35 else (2 if f < 0.8 else 1)
		g.box(ox - hw, y0 + 7 + k, cz - hw, ox + hw, y0 + 8 + k, cz + hw, Kit.OBELISK)
	g.box(ox - 1, y0 + OBELISK - 1, cz - 1, ox + 1, y0 + OBELISK, cz + 1, Kit.GILT)
	for mx: int in [sx0 - 3, sx1 + 2]:
		g.box(mx - 2, y0, cz - 2, mx + 2, y0 + 2, cz + 2, Kit.MARBLE)
		for dz in range(-1, 2):
			g.box(mx, y0 + 2, cz + dz, mx + 1, y0 + 8 - absi(dz), cz + dz + 1, Kit.GILT)
	var ex := _at(sa + 2.0, nx)
	for lx in range(ex, ex + 14, 2):
		g.put(lx, y0 + 4, cz, Kit.BRONZE)
		g.put(lx, y0 + 5, cz, Kit.STATUE) # the eggs
	ex = _at(sb - 5.5, nx)
	for lx in range(ex, ex + 14, 2):
		g.put(lx, y0 + 4, cz, Kit.BRONZE)
		g.put(lx, y0 + 5, cz, Kit.WATER_D) # the dolphins
	# the emperor's box (pulvinar) on the north side
	var bx := _at(smid + 1.0, nx)
	var bz := _at(-(TRACK_HALF + 0.5), nz) - 1
	g.box(bx - 10, y0, bz - 6, bx + 10, y0 + pt + 6, bz + 1, Kit.MARBLE)
	for k in 5:
		g.box(bx - 10 + k * 5, y0 + pt + 6, bz, bx - 9 + k * 5, y0 + pt + 18, bz + 1, Kit.STATUE)
	g.box(bx - 11, y0 + pt + 18, bz - 6, bx + 11, y0 + pt + 20, bz + 2, Kit.TILE)
	g.box(bx - 10, y0 + 3, bz + 1, bx + 10, y0 + pt + 4, bz + 2, Kit.CLOTH_R)
	Arena._seated(g, bx - 1, y0 + pt + 6, bz - 3, true, Kit.DADO, 1) # the emperor in purple
	var n := 2
	for dx: int in [-7, -4, 3, 6]:
		Arena._seated(g, bx + dx, y0 + pt + 6, bz - 3, true, Kit.ROBE_W, n)
		n += 1
	_circus_crowd(g, nx, nz, y0, xw, xc, smid)
	# four two-horse chariots racing anticlockwise
	var k := 0
	for c: Vector3 in [Vector3(smid + 8.0, 1, Kit.ROBE_R), Vector3(smid + 4.5, 1, Kit.CLOTH_G), Vector3(smid - 7.0, -1, Kit.ROBE_W), Vector3(smid - 11.5, -1, Kit.ROBE_B)]:
		_biga(g, _at(c.x, nx), y0 + 1, _at(c.y * 2.4, nz), int(c.y), int(c.z), k)
		k += 1
	return g

## Voxel of m metres from the middle of a grid n voxels wide.
static func _at(m: float, n: int) -> int:
	return floori(m / V + n * 0.5)

## The starting gates across the west end, k metres from it: four gates
## between piers, a gallery above, a tower at each end.
static func _carceres(g: Kit.Grid, x: int, z: int, y0: int, k: float, pz: float, d: float, tower: int) -> void:
	if absf(pz) > TRACK_HALF:
		if d < 0.5 or k < 0.5 or k > CARCERES - 0.5 or absf(pz) < TRACK_HALF + 0.5:
			g.box(x, y0, z, x + 1, y0 + tower, z + 1, Kit.TRAV)
			g.put(x, y0 + tower, z, Kit.TRAV_L)
		else:
			g.put(x, y0 + tower - 1, z, Kit.TILE)
		return
	var u := (pz + TRACK_HALF) / (TRACK_HALF / 2.0)
	var pier := u - floorf(u) < 0.2 or u - floorf(u) > 0.95
	if k > CARCERES - 0.5:
		# the front onto the track: piers of marble, the gates, a gallery above
		var top := 26
		for rr in top:
			if not pier and rr < 12:
				if rr == 0:
					g.put(x, y0, z, Kit.PAVE)
				continue
			if rr >= 16 and rr < 22 and not pier:
				continue
			var band := rr == 12 or rr == 15 or rr == 22 or rr == top - 1
			g.put(x, y0 + rr, z, Kit.TRAV_L if band else (Kit.MARBLE if pier else Kit.TRAV))
		return
	if k < 0.5:
		for rr in 26:
			g.put(x, y0 + rr, z, Kit.TRAV_W if rr % 8 == 0 else Kit.TRAV)
		return
	g.put(x, y0, z, Kit.PAVE)
	g.put(x, y0 + 12, z, Kit.TRAV_D)
	g.put(x, y0 + 25, z, Kit.TILE)

## CIRCUS_SEATS less the emperor's box on the front tread, both sides and
## the curve, the box left free.
static func _circus_crowd(g: Kit.Grid, nx: int, nz: int, y0: int, xw: float, xc: float, smid: float) -> void:
	var first: Array[Vector3] = [] # x, z (m), along x (1) or not (0)
	var second: Array[Vector3] = []
	for j in 2:
		var e := 0.5 + 0.5 * (j + 0.5)
		var row: Array[Vector3] = first if j == 0 else second
		for side: float in [-1.0, 1.0]:
			var m := xw + CARCERES + 0.6
			while m < xc:
				if not (side < 0.0 and absf(m - (smid + 1.0)) < 3.0):
					row.append(Vector3(m, side * (TRACK_HALF + e), 1.0))
				m += SEAT_W
		var rad := TRACK_HALF + e
		var n := int(PI * rad / SEAT_W)
		for i in range(1, n):
			var t := -PI / 2.0 + PI * i / n
			var p := Vector2(xc + rad * cos(t), rad * sin(t))
			if absf(p.y) < 1.2:
				continue
			row.append(Vector3(p.x, p.y, 1.0 if absf(sin(t)) > 0.6 else 0.0))
	var want := CIRCUS_SEATS - 5
	var chosen: Array[Vector3] = []
	var treads: Array[int] = []
	if want <= first.size():
		var step := maxi(1, first.size() / want)
		for k in want:
			chosen.append(first[k * step])
			treads.append(0)
	else:
		var step := maxi(1, second.size() / (want - first.size()))
		for p in first:
			chosen.append(p)
			treads.append(0)
		for k in mini(want - first.size(), (second.size() + step - 1) / step):
			chosen.append(second[k * step])
			treads.append(1)
	for k in chosen.size():
		var p := chosen[k]
		var tunic: int = TUNICS[Kit.rnd(k, 0, 0, 9) % 8]
		if Kit.rnd(k, 1, 0, 9) % 6 == 0:
			tunic = [Kit.ROBE_R, Kit.ROBE_W, Kit.CLOTH_G, Kit.ROBE_B][Kit.rnd(k, 2, 0, 9) % 4]
		Arena._seated(g, _at(p.x, nx), y0 + CIRCUS_PODIUM + 2 * (treads[k] + 1), _at(p.y, nz), p.z > 0.5, tunic, k)

## A two-horse chariot driving along x (face 1 east, -1 west) and its driver.
static func _biga(g: Kit.Grid, x: int, y: int, z: int, face: int, colour: int, seed: int) -> void:
	var hx := x + (2 if face > 0 else -11)
	var k := 0
	for hz: int in [z - 3, z + 1]:
		var hc := Kit.HORSE_W if seed == 2 else (Kit.HORSE_D if k > 0 else Kit.HORSE)
		g.box(hx, y + 3, hz, hx + 9, y + 6, hz + 2, hc) # body
		for lx: int in [hx + 1, hx + 7]:
			g.box(lx, y, hz, lx + 1, y + 3, hz + 2, hc) # legs
		var head := hx + 8 if face > 0 else hx
		g.box(head, y + 5, hz, head + 1, y + 8, hz + 2, hc) # neck and head
		g.put(head + (1 if face > 0 else -1), y + 7, hz, hc)
		k += 1
	var cx := x - (2 if face > 0 else -2)
	g.box(cx - 1, y, z - 2, cx + 2, y + 4, z + 2, Kit.WOOD)
	g.box(cx, y, z - 3, cx + 1, y + 3, z - 2, Kit.WOOD_D)
	g.box(cx, y, z + 2, cx + 1, y + 3, z + 3, Kit.WOOD_D)
	g.box(cx, y + 4, z - 1, cx + 2, y + 6, z + 1, colour)
	g.box(cx, y + 6, z - 1, cx + 2, y + 7, z + 1, Kit.SKIN)
	g.box(cx, y + 7, z - 1, cx + 2, y + 8, z + 1, Kit.BRONZE)

# ---------------------------------------------------------------- theatre

## The Theatre of Marcellus: the cavea in two arcades and an attic, the
## orchestra, the treads, the stage, its front in two orders with three
## doors, and the stage building behind with an open arcade below and blind
## arcades above; three actors in masks. Built with the stage to the north,
## then turned so it stands on the west side.
static func theatre() -> Kit.Grid:
	var outer := THEATRE_R
	var pad := 2
	var nx := int(2.0 * outer / V) + 2 * pad
	var nz := int((outer + STAGE) / V) + 2 * pad
	var rows := THEATRE_ROWS
	var storeys := THEATRE_STOREYS
	var attic := THEATRE_ATTIC
	var wall := BASE + rows * storeys + attic
	var g := Kit.Grid.new(Vector3i(nx, GROUND + wall + 8, nz))
	var y0 := GROUND
	var z_d := pad + int(STAGE / V) # the diameter's row
	var pt := THEATRE_PODIUM
	var ntread := int((outer - 1.5 - ORCH - 0.5) / 0.5)
	var mid := 4 + (wall - 4) / 2
	for z in nz:
		for x in nx:
			var px := (x + 0.5 - nx * 0.5) * V
			var pz := (z + 0.5 - z_d) * V
			if pz >= 0.0:
				var r := Vector2(px, pz).length()
				var d := outer - r
				if d < -0.5:
					continue
				if d < 0.0:
					g.put(x, y0, z, Kit.TRAV_D)
					continue
				var t := atan2(pz, px)
				if d < 1.5:
					_shell(g, x, z, d, outer * t, storeys, attic, rows, pt + 10)
					continue
				if r < ORCH:
					g.put(x, y0, z, Kit.MARBLE if int(r / 0.5) % 2 == 0 else Kit.PODIUM)
					continue
				if r < ORCH + 0.5:
					g.box(x, y0, z, x + 1, y0 + pt, z + 1, Kit.PODIUM)
					g.put(x, y0 + pt, z, Kit.TRAV_L)
					continue
				var j := mini(int((r - ORCH - 0.5) / 0.5), ntread - 1)
				var top := y0 + pt + 2 * (j + 1)
				var w := t / PI * 6.0
				var aisle := absf(w - roundf(w)) < 0.04
				g.box(x, y0, z, x + 1, top - 1, z + 1, Kit.TRAV_D)
				g.put(x, top - 1, z, Kit.TRAV_L if aisle else (Kit.SEAT_HI if j < 2 else Kit.SEAT_MID))
				continue
			# behind the diameter: the stage, its front, the stage building
			if absf(px) > outer:
				continue
			var k := -pz
			if k > STAGE:
				if k < STAGE + 0.5:
					g.put(x, y0, z, Kit.TRAV_D)
				continue
			if absf(px) > outer - 1.5 and k < 1.5:
				# the side halls joining cavea and stage
				var hh := wall - 4
				g.box(x, y0, z, x + 1, y0 + hh, z + 1, Kit.TRAV)
				g.put(x, y0 + hh, z, Kit.TRAV_L)
				continue
			if k < 1.5:
				# the pulpitum, 1 m high, its front with niches
				var front := Kit.REDWASH if int(px / 0.5) % 3 == 0 else Kit.MARBLE
				g.box(x, y0, z, x + 1, y0 + 4, z + 1, Kit.PODIUM if k > 0.25 else front)
				g.put(x, y0 + 4, z, Kit.WOOD)
				continue
			if k < 2.5:
				_stage_front(g, x, z, y0, px, k, wall, mid)
				continue
			# the stage building's outer wall: an open arcade below, blind arcades above (as at Orange)
			if k > STAGE - 0.5 or absf(px) > outer - 0.5:
				var ob := _bay(px + outer if k > STAGE - 0.5 else k + 50.0)
				var layer := 0 if (k > STAGE - 0.25 or absf(px) > outer - 0.25) else 1
				for rr in wall:
					var c := _facade(ob.x, ob.y, rr, layer, storeys, attic, rows)
					if c == Kit.EMPTY and rr >= BASE + rows and layer == 1:
						c = Kit.TRAV_D
					if c != Kit.EMPTY:
						g.put(x, y0 + rr, z, c)
				continue
			g.put(x, y0 + wall - 1, z, Kit.TILE)
	# THEATRE_SEATS spread along the front tread, the aisles left free
	var first: Array[Vector3] = [] # x, z (m), angle
	var rad := ORCH + 0.5 + 0.5 * 0.4
	var n := int(PI * rad / SEAT_W)
	for i in range(1, n):
		var t := PI * i / n
		var w := t / PI * 6.0
		if absf(w - roundf(w)) < 0.08:
			continue
		first.append(Vector3(rad * cos(t), rad * sin(t), t))
	var want := mini(THEATRE_SEATS, first.size())
	for k in want:
		var p := first[k * first.size() / want]
		var tunic: int = TUNICS[Kit.rnd(k, 0, 0, 5) % 8]
		Arena._seated(g, _at(p.x, nx), y0 + pt + 2, floori(p.y / V + z_d), absf(sin(p.z)) > 0.6, tunic, k)
	# three actors in masks on the stage
	var a := 0
	for dx: float in [-2.0, 0.5, 2.5]:
		var x := _at(dx, nx)
		var z := floori(-0.9 / V + z_d)
		_person(g, x, y0 + 5, z, [Kit.ROBE_O, Kit.ROBE_B, Kit.ROBE_R][a])
		g.box(x, y0 + 10, z + 1, x + 2, y0 + 12, z + 2, Kit.LINEN)
		a += 1
	return _turned(g)

## The stage front (scaenae frons), k metres behind the diameter: three
## doors, two orders of columns before a wall with statues and red panels.
static func _stage_front(g: Kit.Grid, x: int, z: int, y0: int, px: float, k: float, frons: int, mid: int) -> void:
	var door := absf(px) < 0.75 or absf(absf(px) - 3.5) < 0.5
	var hdoor := 14 if absf(px) < 0.75 else 10
	var columns := k < 1.75
	var bands := [mid - 1, mid, frons - 2, frons - 1]
	for rr in frons:
		if door and rr < 4 + hdoor and k <= 2.25:
			continue
		if columns:
			var colx := roundi(px) % 2 == 0 and absf(px - roundf(px)) < 0.15
			if rr <= 4 or (not colx and rr not in bands):
				continue
			g.put(x, y0 + rr, z, Kit.TRAV_L if rr in bands else Kit.MARBLE)
			continue
		var c := Kit.TRAV if rr < frons - 1 else Kit.TRAV_L
		if rr == mid - 1 or rr == mid:
			c = Kit.TRAV_L
		var even := px - roundf(px / 2.0) * 2.0
		if mid + 2 < rr and rr < frons - 4 and absf(even) < 0.4 and not door:
			c = Kit.STATUE
		if 6 < rr and rr < mid - 3 and not door and absf(even - 1.0) < 0.3:
			c = Kit.REDWASH
		g.put(x, y0 + rr, z, c)
	if k >= 1.75:
		g.put(x, y0 + frons, z, Kit.TRAV_L)

## The grid turned a quarter counter-clockwise seen from above: what faced
## north faces west.
static func _turned(g: Kit.Grid) -> Kit.Grid:
	var out := Kit.Grid.new(Vector3i(g.n.z, g.n.y, g.n.x))
	var plane := g.n.x * g.n.y
	var plane_out := out.n.x * out.n.y
	for z in g.n.z:
		for y in g.n.y:
			var row := g.n.x * y + plane * z
			for x in g.n.x:
				var c := g.g[row + x]
				if c != 0:
					out.g[z + out.n.x * y + plane_out * (g.n.x - 1 - x)] = c
	return out

# ---------------------------------------------------------------- baths

## The Baths of Caracalla: the main block with two courts of sand in
## porticoes at its ends, halls of brick under tiled roofs, the open pool
## behind its high screen with statues in niches, the great cold hall with
## three thermal windows each side, the hot room as a rotunda standing out
## of the south front under a lead dome; one swimmer, a ball player, one
## walking in.
static func baths() -> Kit.Grid:
	var w := BATHS_W
	var pad := 8
	var nx := int(w * BATHS_K / V) + 2 * pad
	var nz := int((BATHS_D + 3.5) * BATHS_K / V) + 2 * pad
	var g := Kit.Grid.new(Vector3i(nx, GROUND + 90, nz))
	var y0 := GROUND
	# the courts at both ends: sand, an outer wall, porticoes round it
	var wall_top := int(18 * BATHS_HS)
	var portico := int(15 * BATHS_HS)
	for xa: float in [-w / 2.0, w / 2.0 - 6.5]:
		var x0 := _bx(xa, nx)
		var x1 := _bx(xa + 6.5, nx)
		var z0 := _bz(1.5, pad)
		var z1 := _bz(8.5, pad)
		g.box(x0, y0, z0, x1, y0 + 1, z1, Kit.SAND)
		for x in range(x0, x1):
			for z in range(z0, z1):
				var edge := x == x0 or x == x1 - 1 or z == z0 or z == z1 - 1
				var ring := x - x0 < 6 or x1 - x < 7 or z - z0 < 6 or z1 - z < 7
				if edge:
					g.box(x, y0, z, x + 1, y0 + wall_top, z + 1, Kit.BRICK)
					g.put(x, y0 + wall_top, z, Kit.TRAV_L)
				elif ring:
					var inner := x - x0 == 5 or x1 - x == 6 or z - z0 == 5 or z1 - z == 6
					if inner and (x + z) % 6 == 0:
						g.box(x, y0, z, x + 1, y0 + portico, z + 1, Kit.MARBLE)
					g.put(x, y0 + portico, z, Kit.TILE)
					g.put(x, y0 + portico + 1, z, Kit.TILE_D)
		for k in 4:
			g.box(x0 + 8 + k * 4, y0 + 1, z0 + 10, x0 + 9 + k * 4, y0 + 2, z0 + 11, Kit.TRAV_L)
	# the north wing: halls each side of the open pool, the pool's high screen
	_hall(g, nx, pad, -w / 2.0, -4.5, 0.0, 1.5, 7.0)
	_hall(g, nx, pad, 4.5, w / 2.0, 0.0, 1.5, 7.0)
	var x0 := _bx(-4.5, nx)
	var x1 := _bx(4.5, nx)
	var screen := int(32 * BATHS_HS)
	var zs := _bz(0.5, pad)
	g.box(x0, y0, _bz(0.0, pad), x1, y0 + screen, zs, Kit.BRICK)
	for k in 5:
		var nk := x0 + 3 + k * 7
		g.box(nk, y0 + 4, zs - 1, nk + 3, y0 + 14, zs, Kit.TRAV_D)
		g.box(nk, y0 + 18, zs - 1, nk + 3, y0 + 28, zs, Kit.TRAV_D)
		g.put(nk + 1, y0 + 4, zs, Kit.STATUE)
		g.box(nk + 1, y0 + 4, zs - 1, nk + 2, y0 + 11, zs, Kit.STATUE)
	g.box(x0, y0 + screen, _bz(0.0, pad), x1, y0 + screen + 1, zs, Kit.TRAV_L)
	# the natatio, an open pool
	g.box(x0, y0, zs, x1, y0 + 2, _bz(3.5, pad), Kit.MARBLE)
	g.box(x0 + 2, y0 + 1, zs + 1, x1 - 2, y0 + 2, _bz(3.5, pad) - 2, Kit.WATER)
	for x in range(x0 + 2, x1 - 2):
		if Kit.chance(x / 2, 0, 0, 3, 30):
			g.put(x, y0 + 1, _bz(2.0, pad) + x % 3, Kit.WATER_D)
	# the frigidarium: the great hall with its three thermal windows each side
	var fz0 := _bz(3.5, pad)
	var fz1 := _bz(7.0, pad)
	var top := y0 + int(42 * BATHS_HS)
	g.box(x0, y0, fz0, x1, top, fz1, Kit.BRICK)
	for k in 3:
		var ck := x0 + 6 + k * 12
		for zf: int in [fz0, fz1 - 1]:
			for dx in range(-5, 6):
				var hg := int(sqrt(maxf(0.0, 30.0 - dx * dx)))
				g.box(ck + dx, top - 12, zf, ck + dx + 1, top - 12 + hg, zf + 1, Kit.GLASS)
			for dx: int in [-2, 0, 2]:
				g.box(ck + dx, top - 12, zf, ck + dx + 1, top - 7, zf + 1, Kit.TRAV_L)
	g.box(x0, top, fz0, x1, top + 1, fz1, Kit.TRAV_L)
	for k in 3:
		var ck := x0 + 6 + k * 12
		for dz in fz1 - fz0:
			var hh := int(3.0 * sin(PI * (dz + 0.5) / (fz1 - fz0)))
			g.box(ck - 5, top + 1, fz0 + dz, ck + 6, top + 1 + hh, fz0 + dz + 1, Kit.LEAD)
	# the side halls between the great hall and the courts, two storeys
	_hall(g, nx, pad, -w / 2.0 + 6.5, -4.5, 1.5, 9.0, 8.0)
	_hall(g, nx, pad, 4.5, w / 2.0 - 6.5, 1.5, 9.0, 8.0)
	# the warm rooms along the south front, beside the hot room
	_hall(g, nx, pad, -w / 2.0, -3.25, 8.5, 11.0, 6.5)
	_hall(g, nx, pad, 3.25, w / 2.0, 8.5, 11.0, 6.5)
	_hall(g, nx, pad, -3.25, 3.25, 7.0, 9.5, 7.5)
	_caldarium(g, nx, pad, y0)
	# bathers: one swimming, one at ball play in the west court, one walking in
	var sx := _bx(-1.0, nx)
	var sz := _bz(2.0, pad)
	g.box(sx, y0 + 2, sz, sx + 2, y0 + 3, sz + 1, Kit.SKIN)
	g.box(sx, y0 + 3, sz, sx + 2, y0 + 4, sz + 1, Kit.HAIR)
	_person(g, _bx(-w / 2.0 + 3.0, nx), y0 + 1, _bz(5.0, pad), Kit.ROBE_W)
	g.put(_bx(-w / 2.0 + 3.0, nx) + 3, y0 + 5, _bz(5.0, pad), Kit.ROBE_R)
	_person(g, _bx(5.0, nx), y0, _bz(12.0, pad), Kit.ROBE_N)
	return g

## Voxel column of m plan metres east of the baths' middle.
static func _bx(m: float, nx: int) -> int:
	return floori(m * BATHS_K / V + nx * 0.5)

## Voxel row of m plan metres south of the baths' north face.
static func _bz(m: float, pad: int) -> int:
	return floori(m * BATHS_K / V) + pad

## A hall of brick on the baths' plan (metres), eaves `eave` plan metres
## high: weathered bricks, a cornice, rows of arched windows on both long
## sides, a tiled roof.
static func _hall(g: Kit.Grid, nx: int, pad: int, x0m: float, x1m: float, z0m: float, z1m: float, eave: float) -> void:
	var y0 := GROUND
	var x0 := _bx(x0m, nx)
	var x1 := _bx(x1m, nx)
	var z0 := _bz(z0m, pad)
	var z1 := _bz(z1m, pad)
	var top := y0 + int(eave * BATHS_HS / V)
	g.box(x0, y0, z0, x1, top, z1, Kit.BRICK)
	for x in range(x0, x1):
		for z: int in [z0, z1 - 1]:
			for y in range(y0, top):
				if Kit.chance(x / 3, y, z, 5, 10):
					g.put(x, y, z, Kit.BRICK_W)
	g.box(x0, top - 1, z0, x1, top, z1, Kit.TRAV_L)
	var storeys := maxi(1, (top - y0) / BATHS_STOREY)
	for st in storeys:
		var wy := y0 + st * BATHS_STOREY + 5
		if wy + BATHS_WIN_H + 1 > top - 2:
			break
		for wx in range(x0 + 3, x1 - 5, 8):
			for zf: int in [z1 - 1, z0]:
				g.box(wx, wy, zf, wx + 4, wy + BATHS_WIN_H, zf + 1, Kit.GLASS)
				g.box(wx + 1, wy + BATHS_WIN_H, zf, wx + 3, wy + BATHS_WIN_H + 1, zf + 1, Kit.GLASS)
				g.box(wx - 1, wy - 1, zf, wx + 5, wy, zf + 1, Kit.TRAV_L)
	var depth := z1 - z0
	for k in depth / 2 + 1:
		var yy := top + k / 2
		g.box(x0 - 1, yy, z0 - 1 + k, x1 + 1, yy + 1, z1 + 1 - k, Kit.TILE if k % 2 == 0 else Kit.TILE_D)

## The caldarium: a rotunda of brick with arched windows on its south side
## and a ribbed lead dome.
static func _caldarium(g: Kit.Grid, nx: int, pad: int, y0: int) -> void:
	var rc := BATHS_RC
	var ccz := 9.5
	var drum := int(BATHS_DRUM / V)
	for z in range(_bz(ccz - rc - 1.0, pad), _bz(ccz + rc + 1.0, pad)):
		for x in range(_bx(-rc - 1.0, nx), _bx(rc + 1.0, nx)):
			var px := (x + 0.5 - nx * 0.5) * V / BATHS_K
			var pz := (z - pad + 0.5) * V / BATHS_K
			var r := Vector2(px, pz - ccz).length()
			if r > rc:
				continue
			var t := atan2(pz - ccz, px)
			if r > rc - 0.5:
				var ob := _bay(rc * BATHS_K * (t + PI))
				for rr in drum:
					var lr := rr % BATHS_ROWS
					var win := ob.x >= 2 and ob.x <= 7 and lr >= 3 and lr <= 13 and rr / BATHS_ROWS >= 1 and pz > ccz - 1.0
					if win:
						g.put(x, y0 + rr, z, Kit.GLASS if r > rc - 0.25 else Kit.BRICKFACE_W)
						continue
					var brick := Kit.BRICK_W if Kit.chance(x / 3, rr, z, 7, 12) else Kit.BRICK
					g.put(x, y0 + rr, z, Kit.TRAV_L if lr == 0 or lr == 15 else brick)
			else:
				g.put(x, y0, z, Kit.MARBLE)
			var hv := int(sqrt(maxf(0.0, rc * rc - r * r)) * BATHS_K / V)
			if hv > 0:
				var rib := int((t + PI) / (PI / 8.0)) % 2 == 0
				g.box(x, y0 + drum, z, x + 1, y0 + drum + hv, z + 1, Kit.LEAD if rib else Kit.LEAD_D)
			g.put(x, y0 + drum, z, Kit.TRAV_L)
	var lantern := y0 + drum + int(rc * BATHS_K / V)
	var cz := _bz(ccz, pad)
	g.box(_bx(-0.25, nx), lantern, cz - 1, _bx(0.25, nx), lantern + 2, cz + 1, Kit.TRAV_L)
