extends RefCounted
## Voxel colosseum in the style of Urbek City Builder, coloured after
## Caesar III. Each of the BAYS bays is a small voxel building in its own
## straight frame (facade along u, depth d inward, height y), voxelized at
## 25 cm, meshed (exposed faces only, coplanar faces of one colour merged,
## soft corner occlusion in the vertex colours) and then bent onto its
## segment of the ellipse. Straight bays keep every arch and step clean,
## as Urbek's voxel buildings are, instead of the stair-stepped noise a
## curved wall gets in a world-aligned grid. One shared material, no
## textures. Units: about 16 x 13 wide, 7.5 tall with masts, origin at
## ground centre.

const A := 8.0              # outer half-axis along x
const B := 6.6              # outer half-axis along z
const TIER := 1.75          # height of one arcade storey
const WALL_TOP := TIER * 3.0 + 1.25
const BAYS := 28
const BAY_W := 46.0 / BAYS  # nominal bay width (ellipse perimeter ~46)
const PLINTH := 0.5
const SEAT_TOP := 5.5       # upper walkway and highest seat row, just below the attic
const PODIUM_TOP := 3.0
const ARENA_Y := 2.5
const ARENA_E := 0.5        # arena edge as a share of the outer half-axes
const ROW_D := 0.25         # seat row depth: one voxel per row
const FINE := 0.25          # LOD0 voxel size

# Palette: Caesar III travertine, crowd and sand; index 0 is empty.
const PALETTE := [
	Color(0, 0, 0), Color("cbbfa8"), Color("e6d9bf"), Color("cdbb9c"), Color("f3ead6"),
	Color("4e3f34"), Color("3e3229"), Color("4a3a30"), Color("c9b89a"), Color("ddd0b6"),
	Color("d6b37a"), Color("c49e66"), Color("b9a588"), Color("6b4a32"), Color("c23b2c"),
	Color("3e3028"),
	Color("f1e9da"), Color("d9c7a8"), Color("9c7f62"), Color("b5523e"), Color("7d8597"),
	Color("c99a5a"), Color("6e5a48"), Color("e8dccb"), Color("e6d9bf")]
enum { EMPTY, PAVE, STONE, STONE_MID, CORNICE, GALLERY, GALLERY_FLOOR, WINDOW, SEAT_STONE,
	WALKWAY, SAND, SAND_DARK, PODIUM, MAST, RED, VOMITORIUM, CROWD, SILL = 24 }
# Top faces that differ from the sides: a sill is stone in front, but its top
# is the shaded arcade floor seen through the arch.
const TOP := {SILL: Color("7d6d5c")}
const CROWD_COUNT := 8
# Corner occlusion: 0 = both sides blocked, 3 = open.
const AO := [0.52, 0.7, 0.85, 1.0]

## What fills a point of one bay: u along the facade (0..BAY_W, piers at
## both ends), d inward from the outer face, y up. `rr` is the bay's radius
## (outer face to centre), `seed` varies the crowd and sand per voxel.
static func _sample(u: float, d: float, y: float, bay: int, rr: float, seed: int) -> int:
	var pier := minf(u, BAY_W - u)
	var dx := u - 0.5 * BAY_W
	if d < 0.0:
		return _outside(d, y, pier)
	if y >= WALL_TOP:
		return _masts(d, y, u)
	if d < 0.5:
		return _shell(d, y, bay, dx)
	if d < 1.5 and y < TIER * 3.0:
		return _gallery(d, y, pier)
	return _cavea(d, y, rr, bay, dx, seed)

## Plinth, storey cornices, engaged columns and attic pilasters.
static func _outside(d: float, y: float, pier: float) -> int:
	if y >= WALL_TOP:
		return EMPTY
	if y < 0.25:
		return PAVE if d >= -0.75 else EMPTY
	if y < PLINTH:
		return PAVE if d >= -0.5 else EMPTY
	for k in 3:
		var top := (k + 1) * TIER
		if y >= top - 0.25 and y < top and d >= -0.25:
			return CORNICE
	if y >= WALL_TOP - 0.25 and d >= -0.5:
		return CORNICE
	if y >= WALL_TOP - 0.5 and d >= -0.25:
		return CORNICE
	if pier < 0.25 and d >= -0.25:
		return STONE
	return EMPTY

## Outer wall: three arcades of round arches, attic with small windows.
static func _shell(d: float, y: float, bay: int, dx: float) -> int:
	if y < PLINTH:
		return STONE_MID
	if y < TIER * 3.0:
		var k := int(y / TIER)
		var ly := y - k * TIER
		var half := 0.5 * BAY_W - 0.32
		var spring := 0.65
		if absf(dx) < half and ly >= (PLINTH if k == 0 else 0.0) and ly < spring + sqrt(maxf(0.0, half * half - dx * dx)):
			return EMPTY
		return SILL if ly >= TIER - 0.25 or (k == 0 and ly < PLINTH) else STONE
	var ly := y - TIER * 3.0
	if bay % 2 == 0 and absf(dx) < 0.3 and ly >= 0.25 and ly < 0.75:
		return EMPTY if d < 0.25 else WINDOW
	return STONE

## Ambulatory behind the arches: floors, radial walls at the piers, a dark
## back wall. This is what the eye sees through every arch.
static func _gallery(d: float, y: float, pier: float) -> int:
	var k := int(y / TIER)
	var ly := y - k * TIER
	if ly < (PLINTH if k == 0 else 0.25):
		return GALLERY_FLOOR
	if d >= 1.25:
		return GALLERY
	if pier < 0.25:
		return STONE_MID
	return EMPTY

## Rim walkway, stepped seating with crowd, walkways, vomitoria, podium, arena.
static func _cavea(d: float, y: float, rr: float, bay: int, dx: float, seed: int) -> int:
	var arena := (1.0 - ARENA_E) * rr
	if d >= rr:
		return EMPTY
	if d >= arena:
		if y >= ARENA_Y:
			return EMPTY
		if y < ARENA_Y - 0.25:
			return SEAT_STONE
		return SAND
	if d >= arena - 0.25:
		return PODIUM if y < PODIUM_TOP + 0.25 else EMPTY
	if d < 0.75:
		return STONE if y < WALL_TOP else EMPTY
	if d < 1.5:
		# Upper walkway over the gallery roof.
		if y >= SEAT_TOP:
			return EMPTY
		return WALKWAY if y >= SEAT_TOP - 0.25 else SEAT_STONE
	var rows := floori((arena - 0.25 - 1.5) / ROW_D)
	var row := mini(floori((d - 1.5) / ROW_D), rows - 1)
	var seat := SEAT_TOP - (SEAT_TOP - PODIUM_TOP) * float(row) / maxf(1.0, rows - 1)
	seat = snappedf(seat, FINE)
	if y >= seat:
		return EMPTY
	if y < seat - 0.25:
		return SEAT_STONE
	if row == 4 or row == rows - 1:
		return WALKWAY
	if bay % 7 == 3 and absf(dx) < 0.4 and row > 4:
		return VOMITORIUM
	return CROWD + seed % CROWD_COUNT

## A red-flagged mast on every pier of the rim.
static func _masts(d: float, y: float, u: float) -> int:
	if d < 0.0 or d >= 0.25 or y >= WALL_TOP + 0.75:
		return EMPTY
	if u < 0.12:
		return MAST
	if u < 0.6 and y >= WALL_TOP + 0.25:
		return RED
	return EMPTY

static func _phi(bay: float) -> float:
	return TAU * bay / BAYS

static func _radius(phi: float) -> float:
	return Vector2(A * cos(phi), B * sin(phi)).length()

## Point at angle phi, depth d inside the outer face, height y.
static func _onto(phi: float, d: float, y: float) -> Vector3:
	var s := maxf(0.0, 1.0 - d / _radius(phi))   # bays meet at the centre, never cross it
	return Vector3(A * cos(phi) * s, y, B * sin(phi) * s)

## Voxel grid of one bay at voxel size v. Columns along u always divide the
## bay evenly, so the arch sits centred.
static func _voxelize(bay: int, v: float) -> Dictionary:
	var rr := _radius(_phi(bay + 0.5))
	var n := Vector3i(maxi(3, roundi(BAY_W / v)), ceili((WALL_TOP + 1.5) / v), ceili((rr + 0.75) / v))
	var cu := BAY_W / n.x
	var grid := PackedByteArray()
	grid.resize(n.x * n.y * n.z)
	var ss := maxi(1, roundi(v / FINE))
	var counts := PackedInt32Array()
	counts.resize(PALETTE.size())
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var c := EMPTY
				if ss == 1:
					var seed := absi(hash(Vector4i(bay, x, y, z)))
					c = _sample((x + 0.5) * cu, (z + 0.5) * v - 0.75, (y + 0.5) * v, bay, rr, seed)
				else:
					# Coarse voxels take the majority of FINE subsamples, upper
					# ones weighted more so the visible top layer (crowd,
					# sand) wins over the fill below it; red flags always win.
					counts.fill(0)
					var solid := 0
					var crowd := CROWD
					for sz in ss:
						for sy in ss:
							for sx in ss:
								var seed := absi(hash(Vector4i(bay, x * ss + sx, y * ss + sy, z * ss + sz)))
								var s := _sample((x + (sx + 0.5) / ss) * cu, (z * ss + sz + 0.5) * FINE - 0.75, (y * ss + sy + 0.5) * FINE, bay, rr, seed)
								if s >= CROWD and s < CROWD + CROWD_COUNT:
									# All crowd colours vote together, the first one seen paints.
									if counts[CROWD] == 0:
										crowd = s
									counts[CROWD] += 1 + sy
									solid += 1
								elif s != EMPTY:
									counts[s] += 1 + sy
									solid += 1
					if counts[RED] > 0:
						c = RED
					elif solid * 8 >= ss * ss * ss * 3:
						var best := 0
						for i in range(1, counts.size()):
							if counts[i] > counts[best]:
								best = i
						c = crowd if best == CROWD else best
				grid[x + n.x * (y + n.y * z)] = c
	return {"grid": grid, "n": n, "cu": cu, "v": v, "bay": bay}

## Cell lookup. Along u the grid wraps: the neighbouring bay is (nearly) the
## same, so faces between bays vanish and occlusion carries across.
static func _at(vox: Dictionary, c: Vector3i) -> int:
	var n: Vector3i = vox.n
	if c.y < 0 or c.z < 0 or c.y >= n.y or c.z >= n.z:
		return EMPTY
	return vox.grid[posmod(c.x, n.x) + n.x * (c.y + n.y * c.z)]

## From grid coordinates (x along u, y up, z inward) to the colosseum.
static func _bend(vox: Dictionary, g: Vector3) -> Vector3:
	var n: Vector3i = vox.n
	var v: float = vox.v
	var bay: int = vox.bay
	return _onto(_phi(bay + g.x / n.x), g.z * v - 0.75, g.y * v)

## Meshes the exposed faces of one bay into st. Neighbouring faces of one
## colour merge into larger quads wherever their corner shading allows it. Downward faces are skipped: the city camera
## never looks up.
static func _mesh(st: SurfaceTool, vox: Dictionary) -> void:
	var n: Vector3i = vox.n
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
							for s in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
								var s1 := int(_at(vox, o + eu * s.x) != EMPTY)
								var s2 := int(_at(vox, o + ew * s.y) != EMPTY)
								var cc := int(_at(vox, o + eu * s.x + ew * s.y) != EMPTY)
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
						# Merging is exact where the occlusion does not change
						# along the merge direction: corners 0,1 and 3,2 equal
						# along u, corners 0,3 and 1,2 equal along w.
						var ao4 := key >> 8
						var flat_u := (ao4 & 3) == ((ao4 >> 2) & 3) and ((ao4 >> 6) & 3) == ((ao4 >> 4) & 3)
						var flat_w := (ao4 & 3) == ((ao4 >> 6) & 3) and ((ao4 >> 2) & 3) == ((ao4 >> 4) & 3)
						if flat_u:
							while a + wide < du and mask[a + wide + b * du] == key:
								wide += 1
						if flat_w:
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
						var mid := Vector3.ZERO
						for q in [Vector2i(a, b), Vector2i(a + wide, b), Vector2i(a + wide, b + high), Vector2i(a, b + high)]:
							var g := Vector3.ZERO
							g[axis] = plane
							g[u] = q.x
							g[w] = q.y
							mid += g * 0.25
							corners.append(_bend(vox, g))
						# The outward direction, bent like the geometry.
						var out := _bend(vox, mid + Vector3(nv) * 0.5) - _bend(vox, mid)
						var aos: Array[int] = []
						for k in 4:
							aos.append((key >> (8 + k * 2)) & 3)
						var col_id := key & 0xFF
						var colour: Color = TOP[col_id] if axis == 1 and TOP.has(col_id) else PALETTE[col_id]
						_emit(st, corners, aos, colour, out)
						a += wide

static func _emit(st: SurfaceTool, p: Array[Vector3], ao: Array[int], colour: Color, out: Vector3) -> void:
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
		st.set_color(Color(colour.r * f, colour.g * f, colour.b * f))
		st.set_normal(normal)
		st.add_vertex(p[k])

static func build(v: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bay in BAYS:
		_mesh(st, _voxelize(bay, v))
	return st.commit()

## LOD0: 25 cm voxels, every arch, column, seat row and flag.
static func lod0() -> ArrayMesh:
	return build(FINE)

## LOD1: 50 cm voxels.
static func lod1() -> ArrayMesh:
	return build(0.5)

## LOD2, 96 triangles: at that distance voxels are below a pixel, so a
## 12-sided drum carries the colour masses: arcade band, attic, crowd, sand.
static func lod2() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var arcade: Color = PALETTE[STONE].lerp(PALETTE[GALLERY], 0.35)
	for i in n:
		var p0 := TAU * i / n
		var p1 := TAU * (i + 1) / n
		var out := _onto((p0 + p1) * 0.5, -1.0, 0.0) - _onto((p0 + p1) * 0.5, 0.0, 0.0)
		_flat(st, [_onto(p0, 0.0, 0.0), _onto(p1, 0.0, 0.0), _onto(p1, 0.0, TIER * 3.0), _onto(p0, 0.0, TIER * 3.0)], arcade, out)
		_flat(st, [_onto(p0, 0.0, TIER * 3.0), _onto(p1, 0.0, TIER * 3.0), _onto(p1, 0.0, WALL_TOP), _onto(p0, 0.0, WALL_TOP)], PALETTE[STONE], out)
		# The ring of red flags, seen from afar, is a reddish crown.
		_flat(st, [_onto(p0, 0.0, WALL_TOP), _onto(p1, 0.0, WALL_TOP), _onto(p1, 0.75, WALL_TOP), _onto(p0, 0.75, WALL_TOP)],
			PALETTE[CORNICE].lerp(PALETTE[RED], 0.55), Vector3.UP)
		var arena0 := (1.0 - ARENA_E) * _radius(p0)
		var arena1 := (1.0 - ARENA_E) * _radius(p1)
		_flat(st, [_onto(p0, 0.75, SEAT_TOP), _onto(p1, 0.75, SEAT_TOP), _onto(p1, arena1, PODIUM_TOP), _onto(p0, arena0, PODIUM_TOP)],
			PALETTE[CROWD + 1].lerp(PALETTE[CROWD + 2], 0.5), Vector3.UP)
		_flat(st, [_onto(p0, 0.75, WALL_TOP), _onto(p1, 0.75, WALL_TOP), _onto(p1, 0.75, SEAT_TOP), _onto(p0, 0.75, SEAT_TOP)], PALETTE[STONE_MID], -out)
		_flat(st, [_onto(p0, arena0, PODIUM_TOP), _onto(p1, arena1, PODIUM_TOP), _onto(p1, arena1, ARENA_Y), _onto(p0, arena0, ARENA_Y)], PALETTE[PODIUM], -out)
		var centre := Vector3(0, ARENA_Y, 0)
		_flat(st, [centre, _onto(p0, arena0, ARENA_Y), _onto(p1, arena1, ARENA_Y), centre], PALETTE[SAND], Vector3.UP)
	return st.commit()

## A flat-coloured quad (or triangle, when two corners coincide) facing `out`.
static func _flat(st: SurfaceTool, p: Array, colour: Color, out: Vector3) -> void:
	var corners: Array[Vector3] = [p[0], p[1], p[2], p[3]]
	if corners[3].is_equal_approx(corners[0]):
		corners = [p[0], p[1], p[2], p[2]]
	_emit(st, corners, [3, 3, 3, 3], colour, out)

static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	return m

static func triangles(mesh: ArrayMesh) -> int:
	return mesh.surface_get_array_len(0) / 3
