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
## About 16 x 13 m, 7.8 m tall with masts, origin at ground centre.

const V := 0.2
const A := 8.0              # outer half-axis along x, metres
const B := 6.6              # outer half-axis along z
const ROWS := 9             # voxel rows per arcade storey
const STOREYS := 3
const ARCADE_ROWS := ROWS * STOREYS
const ATTIC_ROWS := 6
const WALL_ROWS := ARCADE_ROWS + ATTIC_ROWS
const MAST_ROWS := 5
const P := 6                # facade columns per bay: pier, 4 arch, pier
const C0 := P / 2 - 1       # the two centre columns of a bay
const C1 := P / 2
const SHELL := 3            # wall thickness, voxels
const GALLERY := 5          # gallery depth behind the wall, voxels
const RIM := 2              # walkway behind the wall above the gallery
const ARENA_E := 0.5        # arena edge as a share of the radius
const SEAT_TOP_ROW := 27    # highest seat row, level with the attic base
const PODIUM_ROW := 15
const FLOOR_ROW := 12       # raised arena floor, so the sand shows from above
const LOD_FACTORS := [1, 2, 4]
const LOD_RANGES := [0.0, 50.0, 140.0, 320.0, 6000.0]
const CACHE := "user://colosseum_grid_v6_%d.res"

# Palette: Caesar III travertine and crowd, Urbek's clear part colours.
const PALETTE := [
	Color(0, 0, 0), Color("c9bca4"), Color("dcc39c"), Color("c8ad86"), Color("f2e6cc"),
	Color("3b2f2a"), Color("8a7360"), Color("2f2a33"), Color("d8c6a6"), Color("cdbb9a"),
	Color("d9b47a"), Color("cfa66a"), Color("efe3cc"), Color("6b4a32"), Color("c8372a"),
	Color("2e2420"), Color("9a4434"), Color("ecdcbc"), Color("eadcbf"), Color("b0802f"),
	Color("f4f1ea"), Color("9a8670"), Color("cdb28c"),
	Color("e8e0d0"), Color("c65a43"), Color("5f7fa6"), Color("d9b46a"), Color("7a5a44"),
	Color("b9b0a0"), Color("a39385"), Color("c9a888"),
	Color("bfa58a"), Color("b39a80"), Color("c7ae92"), Color("b47a62")]
enum { EMPTY, PAVE, STONE, STONE_MID, CORNICE, GALLERY_BACK, GALLERY_FLOOR, WINDOW, SEAT_STONE,
	WALKWAY, SAND, SAND_DARK, PODIUM, MAST, RED, VOMITORIUM, PODIUM_BAND, FRAME, COLUMN, BRONZE,
	STATUE, SILL, STONE_LOW, CROWD }
const CROWD_COUNT := 8
const CROWD_MUTED := CROWD + CROWD_COUNT
const CROWD_MUTED_COUNT := 4
# Top faces that differ from the sides: a sill is stone in front, but its top
# is the shaded arcade floor seen through the arch.
const TOP := {SILL: Color("9a8670")}
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
## The facade is built like an Urbek building: every bay is a straight,
## axis-aligned panel P voxels long, set at the ellipse at its middle.
## Where the ellipse curves, neighbouring panels step back, so the outline
## is a clean staircase of flat bays instead of a ragged curve. Bays on the
## long sides face x, the others face z; one quadrant is built and mirrored.
static func _columns(n: Vector3i, lo: Vector3) -> Dictionary:
	var av := A / V
	var bv := B / V
	var xp := PackedInt32Array()      # x-facing panels: facade x per band of z
	var zp := PackedInt32Array()      # z-facing panels: facade z per band of x
	while true:
		var z := xp.size() * P + P * 0.5
		var x := av * sqrt(maxf(0.0, 1.0 - (z / bv) ** 2))
		if x / (av * av) <= z / (bv * bv):
			break
		xp.append(roundi(x))
	while true:
		var x := zp.size() * P + P * 0.5
		var z := bv * sqrt(maxf(0.0, 1.0 - (x / av) ** 2))
		if z / (bv * bv) <= x / (av * av):
			break
		zp.append(roundi(z))
	var zc := xp.size() * P
	var xc := zp.size() * P
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
			var qx := ix if ix >= 0 else -ix - 1
			var qz := iz if iz >= 0 else -iz - 1
			var quadrant := int(ix < 0) + 2 * int(iz < 0)
			# Depth behind the x-facing and the z-facing panel of this column.
			# Beyond its last band a panel family has no face (-1000); in the
			# corner beyond both, the farther corner edge counts.
			var dx := xp[qz / P] - 1 - qx if qz < zc else -1000
			var dz := zp[qx / P] - 1 - qz if qx < xc else -1000
			var corner := qz >= zc and qx >= xc
			if corner:
				dx = xc - 1 - qx
				dz = zc - 1 - qz
			var face_x := dx <= dz if (dx >= 0 and dz >= 0) or corner else dx >= dz
			var c := x + z * n.x
			depth[c] = dx if face_x else dz
			sub[c] = (qz if face_x else qx) % P
			bay[c] = quadrant * 32 + int(face_x) * 16 + (qz if face_x else qx) / P
			var p := lo + Vector3(x + 0.5, 0, z + 0.5) * V
			var e := Vector2(p.x / A, p.z / B).length()
			var rr := Vector2(A * cos(atan2(p.z / B, p.x / A)), B * sin(atan2(p.z / B, p.x / A))).length()
			ellipse[c] = floori((1.0 - e) * rr / V)
			arena[c] = floori((1.0 - ARENA_E) * rr / V)
	return {"depth": depth, "sub": sub, "bay": bay, "ellipse": ellipse, "arena": arena}

## What fills one voxel: d = depth in voxels from the outer face, s = facade
## column in the bay (0..P-1, piers at P-1 and 0), b = bay, r = row, e = depth
## from the ellipse (for the seating).
static func _voxel(d: int, s: int, b: int, r: int, e: int, arena: int, seed: int) -> int:
	if d < -3:
		return EMPTY
	if r >= WALL_ROWS:
		return _mast(d, s, r - WALL_ROWS)
	if d < 0:
		return _outside(d, s, b, r)
	if d < SHELL:
		return _shell(d, s, b, r)
	if d < SHELL + GALLERY and r < ARCADE_ROWS:
		return _gallery(d, s, r)
	return _cavea(e, s, b, r, arena, seed)

static func _is_pier(s: int) -> bool:
	return s == 0 or s == P - 1

## Paving steps, plinth, half columns with capitals, storey cornices, attic
## pilasters, bronze shields and the heavy top cornice.
static func _outside(d: int, s: int, b: int, r: int) -> int:
	if r == 0:
		return PAVE
	if r == 1:
		return PAVE if d >= -2 else EMPTY
	if d < -1:
		return CORNICE if r == WALL_ROWS - 1 and d >= -2 else EMPTY
	if r == 2:
		return STONE_MID
	if r < ARCADE_ROWS:
		var lr := r % ROWS
		if lr == ROWS - 1:
			return CORNICE
		if _is_pier(s):
			return CORNICE if lr == ROWS - 2 else COLUMN
		return EMPTY
	var ar := r - ARCADE_ROWS
	if ar >= ATTIC_ROWS - 2:
		return CORNICE
	if _is_pier(s):
		return COLUMN
	if b % 2 == 1 and (s == C0 or s == C1) and (ar == 1 or ar == 2):
		return BRONZE
	return EMPTY

## Outer wall: three arcades of round-topped arches with light shoulders and
## statues in the upper ones, attic with small windows.
static func _shell(d: int, s: int, b: int, r: int) -> int:
	if r < ARCADE_ROWS:
		var k := r / ROWS
		var lr := r % ROWS
		var bottom := 3 if k == 0 else 1
		var wall := STONE_LOW if k == 0 else STONE
		if lr == 0 and k > 0:
			return SILL if s >= 1 and s <= P - 2 else wall
		var open := (s >= 1 and s <= P - 2 and lr >= bottom and lr <= 6) or ((s == C0 or s == C1) and lr == 7)
		if open:
			if k > 0 and d == SHELL - 1:
				return _statue(s, lr, b + k)
			return EMPTY
		if (s == 1 or s == P - 2) and lr == 7:
			return FRAME
		if r < 3:
			return STONE_MID
		return wall
	var ar := r - ARCADE_ROWS
	if b % 2 == 0 and (s == C0 or s == C1) and (ar == 1 or ar == 2):
		return EMPTY if d == 0 else WINDOW
	return STONE

## A statue in an upper arch: pedestal, body, head, one raised arm.
## Every third one is bronze.
static func _statue(s: int, lr: int, which: int) -> int:
	var material := BRONZE if which % 3 == 0 else STATUE
	if lr == 1:
		return STONE_MID if s == C0 or s == C1 else EMPTY
	if lr >= 2 and lr <= 4:
		if s == C0 or s == C1:
			return material
		return material if s == C1 + 1 and lr >= 3 else EMPTY
	if lr == 5:
		return material if s == C0 else EMPTY
	return EMPTY

## Ambulatory behind the arches: floors, radial walls at the piers, a dark
## back wall. This is what the eye sees through every arch.
static func _gallery(d: int, s: int, r: int) -> int:
	var k := r / ROWS
	var lr := r % ROWS
	if lr < (3 if k == 0 else 1):
		return GALLERY_FLOOR
	if d == SHELL + GALLERY - 1:
		return GALLERY_BACK
	if _is_pier(s):
		return STONE_MID
	return EMPTY

## Walkway behind the wall, stepped seating with a crowd, a middle walkway,
## entrances, podium and arena.
static func _cavea(d: int, s: int, b: int, r: int, arena: int, seed: int) -> int:
	if d >= arena:
		if r < FLOOR_ROW:
			return SEAT_STONE
		if r == FLOOR_ROW:
			return SAND_DARK if seed % 100 < 18 else SAND
		return EMPTY
	if d == arena - 1:
		if r < PODIUM_ROW:
			return PODIUM
		return PODIUM_BAND if r == PODIUM_ROW else EMPTY
	var first := SHELL + RIM
	if d < first:
		if r < SEAT_TOP_ROW - 1:
			return SEAT_STONE
		return WALKWAY if r == SEAT_TOP_ROW - 1 else EMPTY
	# One step per column of depth, evenly down to the podium.
	var depth := arena - 1 - first
	var j := d - first
	var top := SEAT_TOP_ROW - 1 - floori(float(j + 1) * (SEAT_TOP_ROW - 1 - PODIUM_ROW) / depth)
	if r > top:
		return EMPTY
	if r < top:
		return SEAT_STONE
	if j == depth / 3:
		return WALKWAY
	if b % 7 == 3 and (s == C0 or s == C1) and j > depth / 3:
		return VOMITORIUM
	if seed % 100 < 22:
		return SEAT_STONE
	return CROWD + (seed / 100) % CROWD_COUNT

## A mast with a red pennant above every pier of the rim.
static func _mast(d: int, s: int, mr: int) -> int:
	if d != 0 or mr >= 5:
		return EMPTY
	if s == P - 1:
		return MAST
	if (s == P - 2 and (mr == 3 or mr == 4)) or (s == P - 3 and mr == 4):
		return RED
	return EMPTY

## The LOD0 grid.
static func _fine() -> Dictionary:
	var n := _dims()
	var lo := _origin(n)
	var cols := _columns(n, lo)
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
				grid[x + n.x * (y + n.y * z)] = _voxel(depth[c], sub[c], bay[c], y, ellipse[c], arena[c], seed)
	return {"grid": grid, "n": n, "v": V, "lo": lo}

## Downsamples by f: weighted majority of the fine voxels (each layer up
## weighs double, so the visible top layer wins), red always wins, and a few
## crowd voxels make a calm, mixed crowd tone instead of confetti.
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
							solid += 1
							if s >= CROWD and s < CROWD + CROWD_COUNT:
								people += 1
								s = CROWD
							counts[s] += 1 << sy
				var c := EMPTY
				var muted := CROWD_MUTED + absi(hash(Vector3i(x, y, z))) % CROWD_MUTED_COUNT
				if counts[RED] > 0:
					c = RED
				elif solid * 8 >= f * f * f * 3 or people * 4 >= f * f:
					var best := 0
					for i in range(1, counts.size()):
						if counts[i] > counts[best]:
							best = i
					c = muted if best == CROWD else best
				grid[x + n.x * (y + n.y * z)] = c
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

## The far LOD, a 12-sided drum carrying the colour masses: arcade band,
## attic, the red crown of flags, crowd, sand.
static func drum() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var h_arcade := ARCADE_ROWS * V
	var h_wall := WALL_ROWS * V
	var h_seat := SEAT_TOP_ROW * V
	var h_podium := PODIUM_ROW * V
	var h_floor := (FLOOR_ROW + 1) * V
	var at := func(phi: float, share: float, y: float) -> Vector3:
		return Vector3(A * cos(phi) * share, y, B * sin(phi) * share)
	var arcade: Color = PALETTE[STONE].lerp(PALETTE[GALLERY_BACK], 0.35)
	for i in n:
		var p0 := TAU * i / n
		var p1 := TAU * (i + 1) / n
		var out: Vector3 = at.call((p0 + p1) * 0.5, 1.0, 0.0)
		var inner := 0.9
		var arena := ARENA_E
		_flat(st, [at.call(p0, 1.0, 0.0), at.call(p1, 1.0, 0.0), at.call(p1, 1.0, h_arcade), at.call(p0, 1.0, h_arcade)], arcade, out)
		_flat(st, [at.call(p0, 1.0, h_arcade), at.call(p1, 1.0, h_arcade), at.call(p1, 1.0, h_wall), at.call(p0, 1.0, h_wall)], PALETTE[STONE], out)
		_flat(st, [at.call(p0, 1.0, h_wall), at.call(p1, 1.0, h_wall), at.call(p1, inner, h_wall), at.call(p0, inner, h_wall)],
			PALETTE[CORNICE].lerp(PALETTE[RED], 0.55), Vector3.UP)
		_flat(st, [at.call(p0, inner, h_wall), at.call(p1, inner, h_wall), at.call(p1, inner, h_seat), at.call(p0, inner, h_seat)], PALETTE[STONE_MID], -out)
		_flat(st, [at.call(p0, inner, h_seat), at.call(p1, inner, h_seat), at.call(p1, arena, h_podium), at.call(p0, arena, h_podium)],
			PALETTE[CROWD_MUTED + 1], Vector3.UP)
		_flat(st, [at.call(p0, arena, h_podium), at.call(p1, arena, h_podium), at.call(p1, arena, h_floor), at.call(p0, arena, h_floor)], PALETTE[PODIUM], -out)
		var centre := Vector3(0, h_floor, 0)
		_flat(st, [centre, at.call(p0, arena, h_floor), at.call(p1, arena, h_floor), centre], PALETTE[SAND], Vector3.UP)
	return st.commit()

## A flat-coloured quad (or triangle, when the last corner repeats the first).
static func _flat(st: SurfaceTool, p: Array, colour: Color, out: Vector3) -> void:
	var corners: Array[Vector3] = [p[0], p[1], p[2], p[3]]
	if corners[3].is_equal_approx(corners[0]):
		corners = [p[0], p[1], p[2], p[2]]
	_emit(st, corners, [3, 3, 3, 3], colour, out, 1.0)

## All LODs, nearest first: the voxel grid at 20, 40 and 80 cm, then the
## drum. Built meshes are cached in user://; bump CACHE after changing the
## model.
static func lods() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	var fine := {}
	for f: int in LOD_FACTORS:
		var path := CACHE % f
		var mesh: ArrayMesh = load(path) if ResourceLoader.exists(path) else null
		if mesh == null:
			if fine.is_empty():
				fine = _fine()
			mesh = _mesh(fine if f == 1 else _coarse(fine, f))
			ResourceSaver.save(mesh, path)
		out.append(mesh)
	out.append(drum())
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
