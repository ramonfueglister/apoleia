extends RefCounted
## Voxel colosseum after Urbek City Builder, coloured after Caesar III.
## Built strictly on a world grid of 20 cm voxels, as Urbek's buildings are:
## the ellipse is stair-stepped and every facade element is a whole number
## of voxels. The facade is laid out along the ring of outermost columns
## (P columns per bay), so arches stay clean even where the wall runs
## diagonally across the grid. Meshing keeps exposed faces only, merges
## coplanar faces of one colour where the baked corner occlusion allows,
## and skips downward faces. Coarser LODs downsample the same grid. One
## shared shader material adds Urbek's faint per-voxel colour noise.
## In Urbek's proportions: 74 x 61 m and 21.5 m to the rim (three arcades of
## 5.5 m and the attic), about 7 Urbek houses long; origin at ground centre.

const V := 0.5             # voxel edge, metres: an Urbek storey is 6 voxels
const A := 37.0             # outer half-axis along x, metres
const B := 30.5             # outer half-axis along z
const PLINTH_ROWS := 2      # stepped plinth under the arcades
const ROWS := 11            # voxel rows per arcade storey (5.5 m)
const STOREYS := 3
const ARCADE_TOP := PLINTH_ROWS + ROWS * STOREYS
const ATTIC_ROWS := 8
const WALL_ROWS := ARCADE_TOP + ATTIC_ROWS  # 43 rows, 21.5 m to the rim
const MAST_ROWS := 4
const P := 6                # facade columns per bay: pier (2, shared), 4 opening
const SHELL := 3            # wall thickness, voxels; arches are recessed 2
const RIM := 3              # top walkway behind the attic
const ARENA_A := 18.5       # arena half-axes, metres: elongated, so the
const ARENA_B := 12.0       # cavea is about as wide all round
const SEAT_TOP_ROW := WALL_ROWS - 4  # walkway level, 2 m under the rim
const BALTEUS := [5, 10]    # steps after which a low wall splits the cavea
const PODIUM_ROW := SEAT_TOP_ROW - 18
const FLOOR_ROW := PODIUM_ROW - 3    # raised arena floor, so the sand shows from above
const LOD_FACTORS := [1, 2, 4, 8]
# Camera distances for the near-orthographic Urbek camera (FOV 10): LOD0
# while the view is under about 260 m wide, LOD1 to 700 m, LOD2 to 1.6 km.
const LOD_RANGES := [0.0, 1500.0, 4000.0, 9000.0, 400000.0]
const CACHE := "user://colosseum_urbek_v9_%d.res"

# Palette: Caesar III travertine within Urbek's soft light. 0 is empty.
const PALETTE := [
	Color(0, 0, 0), Color("c9bca4"), Color("e3d5ba"), Color("cdb894"), Color("f4ecd8"),
	Color("7e7064"), Color("e8dcc2"), Color("4a3c30"), Color("b5a184"), Color("c9b898"),
	Color("d4aa6c"), Color("c49a5c"), Color("d8ccb0"), Color("6b4a32"), Color("c0392b"),
	Color("5a4a3c"), Color("a8402c"), Color("e6dac2"), Color("b0802f"), Color("f4ecd8"),
	Color("a89a88"), Color("b0574a"), Color("7a8796"),
	Color("a89a88"), Color("b0574a"), Color("7a8796"), Color("c2b49c"),
	Color("66594f"), Color("c8b99c"), Color("cdbb9c"), Color("a8977c"), Color("bca98a"),
	Color("a89886")]
enum { EMPTY, PAVE, STONE, STONE_MID, CORNICE, ARCH_BACK, COLUMN, WINDOW, TREAD,
	WALKWAY, SAND, SAND_DARK, PODIUM, MAST, RED, VOMITORIUM, PODIUM_BAND, BALTEUS_WALL, BRONZE,
	RED_BAND, CROWD, ARCH_HEAD = 27, SHADOW_LINE, PORTICO, RIM_SHADOW, TREAD_BACK, FACADE_MID }
const CROWD_COUNT := 3
const CROWD_MUTED := CROWD + CROWD_COUNT
const CROWD_MUTED_COUNT := 4
# Top faces that differ from the sides: a tread is light on top and darker
# on its riser; the arch floor is shaded.
const TOP := {TREAD: Color("d6c6a8"), TREAD_BACK: Color("bca98a"), ARCH_BACK: Color("7e7064"),
	BALTEUS_WALL: Color("efe5d0"), RED_BAND: Color("b8402f")}
# Corner occlusion: 0 = both sides blocked, 3 = open.
const AO := [0.5, 0.68, 0.85, 1.0]

## Grid size, a multiple of the coarsest LOD factor in every direction.
static func _dims() -> Vector3i:
	var f: int = LOD_FACTORS[-1]
	var nx := ceili((2.0 * A + 2.0) / V / f) * f
	var nz := ceili((2.0 * B + 2.0) / V / f) * f
	var ny := ceili(float(WALL_ROWS + MAST_ROWS + 1) / f) * f
	return Vector3i(nx, ny, nz)

static func _origin(n: Vector3i) -> Vector3:
	return Vector3(-n.x * V * 0.5, 0.0, -n.z * V * 0.5)

## Per grid column: depth in voxels from the facade (negative outside), the
## facade column within its bay, the bay, and the depth from the ellipse
## with the arena edge, which shape the seating.
##
## The facade is built like an Urbek building for the north-up camera: every
## bay is a straight run of P voxels facing south (or north), set at the
## ellipse at its middle. Neighbouring bays step back, so the curve reads as
## a staircase of flat bays with arches all round; the steps' side walls face
## east and west and are edge-on to the camera. Bay 0 is centred on x = 0.
## With `smooth`, the facade follows the oval itself (for the far LODs).
static func _columns(n: Vector3i, lo: Vector3, smooth := false) -> Dictionary:
	var av := A / V
	var bv := B / V
	var count := n.x * n.z
	var depth := PackedInt32Array()
	var sub := PackedInt32Array()
	var bay := PackedInt32Array()
	var ellipse := PackedInt32Array()
	var arena := PackedInt32Array()
	for arr in [depth, sub, bay, ellipse, arena]:
		arr.resize(count)
	for z in n.z:
		for x in n.x:
			var ix := x - n.x / 2
			var iz := z - n.z / 2
			var qz := iz if iz >= 0 else -iz - 1
			var band := floori((ix + P * 0.5) / P)
			var bx := minf(absf(band) * P, av - 1.0)
			var face := roundi(bv * sqrt(maxf(0.0, 1.0 - (bx / av) ** 2)))
			var c := x + z * n.x
			depth[c] = face - 1 - qz if absf(band) * P - P * 0.5 < av else -1000
			sub[c] = posmod(ix + P / 2, P)
			bay[c] = band + (1000 if iz < 0 else 0)
			var p := lo + Vector3(x + 0.5, 0, z + 0.5) * V
			var e := Vector2(p.x / A, p.z / B).length()
			var rr := Vector2(A * cos(atan2(p.z / B, p.x / A)), B * sin(atan2(p.z / B, p.x / A))).length()
			ellipse[c] = floori((1.0 - e) * rr / V)
			# Arena edge depth: this column's ellipse depth plus its distance
			# outside the arena ellipse (inside it, e >= arena).
			var ea := Vector2(p.x / ARENA_A, p.z / ARENA_B).length()
			var ra := Vector2(ARENA_A * cos(atan2(p.z / ARENA_B, p.x / ARENA_A)), ARENA_B * sin(atan2(p.z / ARENA_B, p.x / ARENA_A))).length()
			arena[c] = ellipse[c] + floori((ea - 1.0) * ra / V) + 1
			# Far LODs follow the smooth oval: per-bay steps are finer than
			# their voxels and would only leave single protruding blocks.
			if smooth:
				depth[c] = ellipse[c] - 2
	return {"depth": depth, "sub": sub, "bay": bay, "ellipse": ellipse, "arena": arena}

## What fills one voxel: d = depth in voxels from the outer face, s = facade
## column in the bay (0..P-1, the pier is P-1 and 0), b = bay, r = row,
## e = depth from the ellipse (for the seating).
static func _voxel(d: int, s: int, b: int, r: int, e: int, arena: int, seed: int) -> int:
	if d < -3:
		return EMPTY
	if r >= WALL_ROWS:
		return _mast(d, s, b, r - WALL_ROWS)
	if d < 0:
		return _outside(d, s, b, r)
	if d < SHELL:
		return _shell(d, s, b, r)
	return _cavea(e, s, b, r, arena, seed)

static func _is_pier(s: int) -> bool:
	return s == 0 or s == P - 1

## Paving, stepped plinth, engaged columns with capitals, a cornice one voxel
## proud on every storey, attic pilasters, bronze shields, heavy top cornice.
static func _outside(d: int, s: int, b: int, r: int) -> int:
	if r == 0:
		return PAVE if d >= -3 else EMPTY
	if r < PLINTH_ROWS:
		return STONE_MID if d >= -2 else EMPTY
	if d < -1:
		return CORNICE if r == WALL_ROWS - 1 and d == -2 else EMPTY
	if r < ARCADE_TOP:
		var lr := (r - PLINTH_ROWS) % ROWS
		if lr == ROWS - 1:
			return CORNICE
		if _is_pier(s):
			return CORNICE if lr == ROWS - 2 or lr == 0 else COLUMN
		return EMPTY
	var ar := r - ARCADE_TOP
	if ar >= ATTIC_ROWS - 2 or ar == 0:
		return CORNICE
	if _is_pier(s):
		return COLUMN
	if posmod(b, 2) == 1 and (s == 2 or s == 3) and (ar == 3 or ar == 4):
		return BRONZE
	return EMPTY

## Outer wall: three arcades of round-headed arches recessed two voxels into
## a shaded back wall; a closed attic with a window in every second bay.
static func _shell(d: int, s: int, b: int, r: int) -> int:
	if r < PLINTH_ROWS:
		return STONE_MID
	if r < ARCADE_TOP:
		var lr := (r - PLINTH_ROWS) % ROWS
		var open := (s >= 1 and s <= P - 2 and lr >= 1 and lr <= 7) or ((s == 2 or s == 3) and lr == 8)
		if open:
			if d < SHELL - 1:
				return EMPTY
			return ARCH_HEAD if lr == 8 else ARCH_BACK
		if lr == 0 and s >= 1 and s <= P - 2 and d < SHELL - 1:
			return ARCH_BACK
		# Archivolt round the head, in cornice white; a shadow line under
		# the cornice everywhere else.
		if d == 0 and ((lr == 8 and (s == 1 or s == 4)) or (lr == 9 and (s == 2 or s == 3))):
			return CORNICE
		if lr == 9:
			return SHADOW_LINE
		return STONE
	var ar := r - ARCADE_TOP
	if posmod(b, 2) == 0 and (s == 2 or s == 3) and (ar == 3 or ar == 4):
		return EMPTY if d == 0 else WINDOW
	return SHADOW_LINE if ar == ATTIC_ROWS - 3 else STONE

## Top walkway under a portico, then the cavea: 1-voxel risers and 2-voxel
## treads, two low walls splitting it into three bands, entrances in them,
## a sparse muted crowd, podium and arena.
static func _cavea(e: int, s: int, b: int, r: int, arena: int, seed: int) -> int:
	if e >= arena:
		if r < FLOOR_ROW:
			return TREAD
		if r == FLOOR_ROW:
			return SAND_DARK if seed % 100 < 18 else SAND
		return EMPTY
	if e == arena - 1:
		if r < PODIUM_ROW:
			return PODIUM
		return PODIUM_BAND if r == PODIUM_ROW else EMPTY
	var first := SHELL + RIM
	if e < first:
		if r < SEAT_TOP_ROW - 1:
			return TREAD
		if r == SEAT_TOP_ROW - 1:
			return WALKWAY
		# Portico over the walkway: a roof level with the rim, a step darker,
		# on columns along its inner edge.
		if r == WALL_ROWS - 1:
			return PORTICO
		if e == first - 1 and posmod(b * P + s, 3) == 0:
			return COLUMN
		return EMPTY
	var j := e - first
	var step := j / 2
	var top := maxi(SEAT_TOP_ROW - 2 - step, PODIUM_ROW + 1)
	if r < top:
		return TREAD
	if r == top:
		# A shadow row under the portico sets the rim off from the seats.
		if j == 0:
			return RIM_SHADOW
		# Each tread: a darker strip against the riser behind, a light edge;
		# spectators sit in short runs on the edge.
		if j % 2 == 0:
			return TREAD_BACK
		var run := floori((b * P + s) / 3.0)
		var h := absi(hash(Vector2i(run, step)))
		if h % 100 < 10:
			return CROWD + (h / 100) % CROWD_COUNT
		return TREAD
	# Low wall at the start of a band, with entrances every eight bays.
	if j % 2 == 0 and step in BALTEUS and r <= top + 2:
		if posmod(b, 8) == 0 and (s == 2 or s == 3):
			return VOMITORIUM
		return BALTEUS_WALL
	return EMPTY

## A mast with a red flag on the pier of every second bay.
static func _mast(d: int, s: int, b: int, mr: int) -> int:
	if d != 0 or mr >= MAST_ROWS or posmod(b, 2) == 1:
		return EMPTY
	if s == 0:
		return MAST
	if s == 1 and mr >= MAST_ROWS - 2:
		return RED
	return EMPTY

## The kind of facade row a fine row is, for the LOD1 grammar.
enum { K_PLINTH, K_WALL, K_OPEN, K_HEAD, K_SHADOW, K_CORNICE, K_ATTIC, K_WINDOW }
static func _row_kind(fr: int) -> int:
	if fr < PLINTH_ROWS:
		return K_PLINTH
	if fr < ARCADE_TOP:
		var lr := (fr - PLINTH_ROWS) % ROWS
		if lr == ROWS - 1:
			return K_CORNICE
		if lr == ROWS - 2:
			return K_SHADOW
		if lr == ROWS - 3:
			return K_HEAD
		return K_OPEN if lr >= 1 else K_WALL
	var ar := fr - ARCADE_TOP
	if ar >= ATTIC_ROWS - 2 or ar == 0:
		return K_CORNICE
	if ar == ATTIC_ROWS - 3:
		return K_SHADOW
	return K_WINDOW if ar == 3 or ar == 4 else K_ATTIC

## LOD1 facade by rule instead of by downsampling: 1 m voxels, bays of 3
## (pier 1, opening 2) phase-locked to LOD0's bays, the same per-bay plan
## steps, arch rows where both fine rows are open, light cornice rows. The
## seating, arena and masts keep their downsampled voxels.
static func _facade_lod1(vox: Dictionary) -> void:
	var n: Vector3i = vox.n
	var grid: PackedByteArray = vox.grid
	var kinds := []
	for y in n.y:
		var k0 := _row_kind(2 * y)
		var k1 := _row_kind(2 * y + 1)
		var k := K_WALL
		if 2 * y >= WALL_ROWS:
			k = -1
		elif K_CORNICE in [k0, k1]:
			k = K_CORNICE
		elif k0 in [K_OPEN, K_HEAD] and k1 in [K_OPEN, K_HEAD]:
			k = K_HEAD if k1 == K_HEAD else K_OPEN
		elif K_SHADOW in [k0, k1]:
			k = K_SHADOW
		elif K_WINDOW in [k0, k1]:
			k = K_WINDOW
		elif K_PLINTH in [k0, k1]:
			k = K_PLINTH
		elif K_ATTIC in [k0, k1]:
			k = K_ATTIC
		kinds.append(k)
	for z in n.z:
		for x in n.x:
			var ix := x - n.x / 2
			var iz := z - n.z / 2
			var qz := iz if iz >= 0 else -iz - 1
			var band := floori((ix + 1) / 3.0)
			if absf(band) * 3.0 - 1.5 >= A:
				continue
			var bx := minf(absf(band) * 3.0, A - V)
			var face := roundi(B * sqrt(maxf(0.0, 1.0 - (bx / A) ** 2)))
			var d := face - 1 - qz
			if d < -2 or d > 1:
				continue
			var s1 := posmod(ix - 1, 3)
			var pier := s1 == 0
			var b := band + (1000 if iz < 0 else 0)
			for y in n.y:
				var k: int = kinds[y]
				var c := EMPTY
				if k == -1:
					if d < 0:
						grid[x + n.x * (y + n.y * z)] = EMPTY
					continue
				match k:
					K_PLINTH:
						c = PAVE if d == -2 else STONE_MID
					K_CORNICE:
						c = CORNICE if d >= -1 else EMPTY
					K_OPEN, K_HEAD:
						if d == -2:
							c = EMPTY
						elif pier:
							c = COLUMN if d == -1 else STONE
						elif d == 1:
							c = ARCH_HEAD if k == K_HEAD else ARCH_BACK
					K_SHADOW:
						c = (COLUMN if pier else EMPTY) if d == -1 else (EMPTY if d == -2 else SHADOW_LINE)
					K_WINDOW:
						if d == -1:
							c = COLUMN if pier else EMPTY
						elif d >= 0:
							c = WINDOW if not pier and posmod(b, 2) == 0 and d == 1 else (EMPTY if not pier and posmod(b, 2) == 0 else STONE)
					_:
						if d == -1:
							c = COLUMN if pier else EMPTY
						elif d >= 0:
							c = STONE
				grid[x + n.x * (y + n.y * z)] = c

## The grid at the finest voxel size; `smooth` for the far LODs.
static func _fine(smooth := false) -> Dictionary:
	var n := _dims()
	var lo := _origin(n)
	var cols := _columns(n, lo, smooth)
	var depth: PackedInt32Array = cols.depth
	var sub: PackedInt32Array = cols.sub
	var bay: PackedInt32Array = cols.bay
	var arena: PackedInt32Array = cols.arena
	var ellipse: PackedInt32Array = cols.ellipse
	var grid := PackedByteArray()
	grid.resize(n.x * n.y * n.z)
	for z in n.z:
		for x in n.x:
			var c := x + z * n.x
			if depth[c] < -3:
				continue
			for y in n.y:
				var seed := absi(hash(Vector3i(x, y, z)))
				# The far LODs leave out everything in front of the wall
				# (columns, cornices, paving): thinner than their voxels, it only
				# made single protruding blocks.
				if smooth and depth[c] < 0:
					continue
				grid[x + n.x * (y + n.y * z)] = _voxel(depth[c], sub[c], bay[c], y, ellipse[c], arena[c], seed)
	return {"grid": grid, "n": n, "v": V, "lo": lo}

## Downsamples by f: weighted majority of the fine voxels (each layer up
## weighs double, so the visible top layer wins), red flags always win up
## close and become a red band on the cornice far away, and a few crowd
## voxels make a calm, mixed crowd tone instead of confetti.
static func _coarse(fine: Dictionary, f: int) -> Dictionary:
	var fn: Vector3i = fine.n
	var fg: PackedByteArray = fine.grid
	var n := fn / f
	var grid := PackedByteArray()
	grid.resize(n.x * n.y * n.z)
	var counts := PackedInt32Array()
	counts.resize(PALETTE.size())
	for z in n.z:
		for y in n.y:
			for x in n.x:
				counts.fill(0)
				var solid := 0
				var people := 0
				for sz in f:
					for sy in f:
						for sx in f:
							var s: int = fg[x * f + sx + fn.x * (y * f + sy + fn.y * (z * f + sz))]
							if s == EMPTY:
								continue
							if f >= 4:
								if s == MAST or s == RED:
									continue
								if s == PODIUM_BAND:
									s = PODIUM
							solid += 1
							if s >= CROWD and s < CROWD + CROWD_COUNT:
								people += 1
								s = CROWD
							counts[s] += 1 << sy
				var c := EMPTY
				var muted := CROWD_MUTED + absi(hash(Vector3i(x, y, z))) % CROWD_MUTED_COUNT
				var sand := counts[SAND] + counts[SAND_DARK]
				var rim := y * f <= WALL_ROWS - 1 and WALL_ROWS - 1 < (y + 1) * f
				if counts[RED] > 0:
					c = RED
				elif f >= 4 and rim and counts[STONE] + counts[CORNICE] + counts[PORTICO] > 0:
					# Far away the flags become one continuous red band on
					# the top cornice.
					c = RED_BAND
				elif sand > 0:
					# The one-voxel sand layer must not vanish under the
					# fill below it, or the arena gets holes and shrinks.
					c = SAND
				elif solid * 8 >= f * f * f * 3 or people * 4 >= f * f:
					var best := 0
					for i in range(1, counts.size()):
						if counts[i] > counts[best]:
							best = i
					c = muted if best == CROWD else best
					# Far away the arcade keeps its value: at 2 m it alternates
					# dark and light, at 4 m the whole arcade is
					# the average of pier and arch; the attic stays light.
					var arch := counts[ARCH_BACK] + counts[ARCH_HEAD]
					var arcade := y * f < ARCADE_TOP and best in [STONE, SHADOW_LINE, COLUMN, ARCH_BACK, ARCH_HEAD]
					if f == 4 and arcade:
						# Bays and 2 m blocks cannot line up, so the rhythm is a
						# regular alternation instead of a sampled one.
						c = ARCH_BACK if posmod(x + z, 2) == 0 else STONE
					elif f >= 8 and arcade:
						c = FACADE_MID
				grid[x + n.x * (y + n.y * z)] = c
	# The red band keeps to the outer edge: one block wide, not the whole rim.
	if f >= 4:
		var yr := (WALL_ROWS - 1) / f
		for z in n.z:
			for x in n.x:
				var i := x + n.x * (yr + n.y * z)
				if grid[i] != RED_BAND:
					continue
				var ox := x + (1 if x >= n.x / 2 else -1)
				var oz := z + (1 if z >= n.z / 2 else -1)
				var outer := ox < 0 or ox >= n.x or oz < 0 or oz >= n.z \
					or grid[ox + n.x * (yr + n.y * z)] == EMPTY or grid[x + n.x * (yr + n.y * oz)] == EMPTY
				if not outer:
					grid[i] = CORNICE
	return {"grid": grid, "n": n, "v": V * f, "lo": fine.lo}

static func _at(vox: Dictionary, c: Vector3i) -> int:
	var n: Vector3i = vox.n
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= n.x or c.y >= n.y or c.z >= n.z:
		return EMPTY
	return vox.grid[c.x + n.x * (c.y + n.y * c.z)]

## Meshes the exposed faces. Neighbouring faces of one colour merge wherever
## their corner shading allows it exactly. Downward faces are skipped: the
## city camera never looks up.
static func _mesh(vox: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: Vector3i = vox.n
	var v: float = vox.v
	var lo: Vector3 = vox.lo
	var dims := [n.x, n.y, n.z]
	for axis in 3:
		var u := (axis + 1) % 3
		var w := (axis + 2) % 3
		var du: int = dims[u]
		var dw: int = dims[w]
		for dir in [-1, 1]:
			if axis == 1 and dir == -1:
				continue
			var nv := Vector3i.ZERO
			nv[axis] = dir
			var eu := Vector3i.ZERO
			eu[u] = 1
			var ew := Vector3i.ZERO
			ew[w] = 1
			var mask := PackedInt32Array()
			mask.resize(du * dw)
			for i in dims[axis]:
				for b in dw:
					for a in du:
						var c := Vector3i.ZERO
						c[axis] = i
						c[u] = a
						c[w] = b
						var col := _at(vox, c)
						var key := 0
						if col != EMPTY and _at(vox, c + nv) == EMPTY:
							var o := c + nv
							var ao := 0
							var corner := 0
							for sg in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
								var s1 := int(_at(vox, o + eu * sg.x) != EMPTY)
								var s2 := int(_at(vox, o + ew * sg.y) != EMPTY)
								var cc := int(_at(vox, o + eu * sg.x + ew * sg.y) != EMPTY)
								var level := 0 if s1 + s2 == 2 else 3 - s1 - s2 - cc
								ao |= level << (corner * 2)
								corner += 1
							key = col | (ao << 8)
						mask[a + b * du] = key
				for b in dw:
					var a := 0
					while a < du:
						var key := mask[a + b * du]
						if key == 0:
							a += 1
							continue
						var wide := 1
						var high := 1
						# Exact where the occlusion does not change along the
						# merge direction: corners 0,1 and 3,2 equal along u,
						# corners 0,3 and 1,2 equal along w.
						var ao4 := key >> 8
						if (ao4 & 3) == ((ao4 >> 2) & 3) and ((ao4 >> 6) & 3) == ((ao4 >> 4) & 3):
							while a + wide < du and mask[a + wide + b * du] == key:
								wide += 1
						if (ao4 & 3) == ((ao4 >> 6) & 3) and ((ao4 >> 2) & 3) == ((ao4 >> 4) & 3):
							var grow := true
							while grow and b + high < dw:
								for k in wide:
									if mask[a + k + (b + high) * du] != key:
										grow = false
										break
								if grow:
									high += 1
						for hb in high:
							for ka in wide:
								mask[a + ka + (b + hb) * du] = 0
						var plane: int = i + (1 if dir > 0 else 0)
						var corners: Array[Vector3] = []
						for q in [Vector2i(a, b), Vector2i(a + wide, b), Vector2i(a + wide, b + high), Vector2i(a, b + high)]:
							var g := Vector3.ZERO
							g[axis] = plane
							g[u] = q.x
							g[w] = q.y
							corners.append(lo + g * v)
						var aos: Array[int] = []
						for k in 4:
							aos.append((ao4 >> (k * 2)) & 3)
						var col_id := key & 0xFF
						var colour: Color = TOP[col_id] if axis == 1 and TOP.has(col_id) else PALETTE[col_id]
						_emit(st, corners, aos, colour, Vector3(nv), v)
						a += wide
	return st.commit()

## One quad. The voxel size goes into the vertex alpha, so the shader can
## find each voxel for its colour noise.
static func _emit(st: SurfaceTool, p: Array[Vector3], ao: Array[int], colour: Color, out: Vector3, v: float) -> void:
	var normal := (p[1] - p[0]).cross(p[2] - p[0])
	if normal.length_squared() < 1e-12:
		normal = (p[2] - p[0]).cross(p[3] - p[0])
	if normal.dot(out) < 0.0:
		p = [p[0], p[3], p[2], p[1]]
		ao = [ao[0], ao[3], ao[2], ao[1]]
		normal = -normal
	normal = normal.normalized()
	# Godot fronts are clockwise; the diagonal follows the occlusion so
	# corner shading does not streak across the quad.
	var order := [0, 2, 1, 0, 3, 2] if ao[0] + ao[2] >= ao[1] + ao[3] else [0, 3, 1, 1, 3, 2]
	for k in order:
		var f: float = AO[ao[k]]
		st.set_color(Color(colour.r * f, colour.g * f, colour.b * f, v))
		st.set_normal(normal)
		st.add_vertex(p[k])

## All LODs, nearest first: the voxel grid at 0.5, 1, 2 and 4 m. Built
## meshes are cached in user://; bump CACHE after changing the model.
static func lods() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	var stepped := {}
	var smooth := {}
	for f: int in LOD_FACTORS:
		var path := CACHE % f
		var mesh: ArrayMesh = load(path) if ResourceLoader.exists(path) else null
		if mesh == null:
			var fine := stepped
			if f >= 4:
				if smooth.is_empty():
					smooth = _fine(true)
				fine = smooth
			elif stepped.is_empty():
				stepped = _fine()
				fine = stepped
			var vox := fine if f == 1 else _coarse(fine, f)
			if f == 2:
				_facade_lod1(vox)
			mesh = _mesh(vox)
			ResourceSaver.save(mesh, path)
		out.append(mesh)
	return out

## Vertex colours (sRGB, baked occlusion) with a faint per-voxel brightness
## noise, as on Urbek's walls. The voxel is found from the model-space
## position half a voxel behind the face; its size comes from vertex alpha.
const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
varying vec3 voxel_pos;
varying float voxel_size;

void vertex() {
	voxel_size = COLOR.a;
	voxel_pos = VERTEX - NORMAL * COLOR.a * 0.5;
}

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 cell = floor(voxel_pos / voxel_size + 0.001);
	float h = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	ALBEDO = to_linear(COLOR.rgb) * (0.965 + 0.07 * h);
	ROUGHNESS = 1.0;
}
"""

static func material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	return m

static func triangles(mesh: ArrayMesh) -> int:
	return mesh.surface_get_array_len(0) / 3
