extends RefCounted
## Voxel colosseum in the style of Urbek City Builder, coloured after
## Caesar III. One bay of the arcade (facade along u, depth d inward, height
## y) is described as a solid in metres (`_sample`), voxelized at 12.5 cm,
## meshed (exposed faces only, coplanar faces of one colour merged where the
## voxel corner occlusion allows) and bent onto each of the BAYS segments of
## the ellipse. Straight bays keep arches, columns and seat rows clean, as
## Urbek's voxel buildings are; a curved wall in a world grid only gives
## stair-step noise. Four bay variants (windows, entrances, crowd) repeat
## around the ring. One shared material, no textures. About 16 x 13 m,
## 7.5 m tall with masts, origin at ground centre.

const A := 8.0              # outer half-axis along x
const B := 6.6              # outer half-axis along z
const R0 := 7.3             # nominal radius the bay template is drawn for
const TIER := 1.75          # height of one arcade storey
const WALL_TOP := TIER * 3.0 + 1.25
const BAYS := 28
const BAY_W := 46.06 / BAYS # bay width: perimeter split into equal arcs
const VARIANTS := 4
const PLINTH := 0.375
const SEAT_TOP := 6.0       # upper walkway and highest seat row
const PODIUM_TOP := 3.0
const ARENA_Y := 2.5
const ARENA_E := 0.5        # arena edge as a share of the radius
const ROW_D := 0.25         # seat row depth
const FINE := 0.125         # LOD0 voxel size; coarser LODs supersample at this step
const CACHE := "user://colosseum_v7_%s.res"
# Voxel sizes of the LODs, and the camera distances where each one shows.
const LOD_VOXELS := [0.125, 0.25, 0.5]
const LOD_RANGES := [0.0, 50.0, 140.0, 320.0, 6000.0]

# Palette: Caesar III travertine, crowd and sand, Urbek brightness. 0 is empty.
const PALETTE := [
	Color(0, 0, 0), Color("cfc3ab"), Color("eadbbd"), Color("d2c09e"), Color("f6eedc"),
	Color("4a3b30"), Color("3c3028"), Color("3a2c24"), Color("cdbd9f"), Color("ddd0b6"),
	Color("dcb87e"), Color("c9a26a"), Color("e2d4b8"), Color("7a5236"), Color("c8372a"),
	Color("3a2c24"), Color("d9a27a"), Color("4a3426"), Color("eadbbd"),
	Color("f2ebdd"), Color("d9c7a8"), Color("a5835f"), Color("b8483a"), Color("6f7f9a"),
	Color("c9a050"), Color("8a6a50"), Color("e6d8c0"), Color("9a4434"),
	Color("dccaa8"), Color("d1bd99"), Color("f1ece2"), Color("a8783a"), Color("efe6d2"),
	Color("c7ae92"), Color("b39a80"), Color("bfa58a"), Color("b47a62")]
enum { EMPTY, PAVE, STONE, STONE_MID, CORNICE, GALLERY, GALLERY_FLOOR, WINDOW, SEAT_STONE,
	WALKWAY, SAND, SAND_DARK, PODIUM, MAST, RED, VOMITORIUM, SKIN, HAIR, SILL, CROWD,
	PODIUM_BAND = 27, STONE_LOW, STONE_B, STATUE, BRONZE, COLUMN, CROWD_MUTED }
const CROWD_COUNT := 8
const CROWD_MUTED_COUNT := 4
# Ashlar variation is only worth its triangles at the nearest LOD.
static var _ashlar := true
# Top faces that differ from the sides: a sill is stone in front, but its top
# is the shaded arcade floor seen through the arch.
const TOP := {SILL: Color("8a7a66")}
# Corner occlusion: 0 = both sides blocked, 3 = open.
const AO := [0.5, 0.68, 0.85, 1.0]
# Arch geometry of one arcade storey, shared by the opening and its frame.
const ARCH_HALF := 0.47
const ARCH_SPRING := 0.7

## What fills a point of a bay of the given variant: u along the facade
## (0..BAY_W, piers at both ends), d inward from the outer face in metres
## for the nominal radius R0, y up.
static func _sample(u: float, d: float, y: float, variant: int) -> int:
	var pier := minf(u, BAY_W - u)
	var dx := u - 0.5 * BAY_W
	if y >= WALL_TOP:
		return _masts(d, y, u)
	if d < 0.0:
		return _outside(d, y, pier, dx)
	if d < 0.5:
		return _shell(d, y, dx, variant)
	if d < 1.5 and y < TIER * 3.0:
		return _gallery(d, y, pier)
	return _cavea(u, d, y, dx, variant)

## Plinth, stepped cornices, half columns with base and capital, arch frames
## with keystones, attic pilasters.
static func _outside(d: float, y: float, pier: float, dx: float) -> int:
	if y < 0.125:
		return PAVE if d >= -0.75 else EMPTY
	if y < 0.25:
		return PAVE if d >= -0.5 else EMPTY
	if y < PLINTH:
		return STONE_MID if d >= -0.25 else EMPTY
	if y >= WALL_TOP - 0.125:
		return CORNICE if d >= -0.375 else EMPTY
	if y >= WALL_TOP - 0.25:
		return CORNICE if d >= -0.25 else EMPTY
	if y >= WALL_TOP - 0.375:
		return CORNICE if d >= -0.125 else EMPTY
	if y >= TIER * 3.0:
		return COLUMN if pier < 0.16 and d >= -0.125 else EMPTY
	var k := int(y / TIER)
	var ly := y - k * TIER
	if ly >= TIER - 0.125:
		return CORNICE if d >= -0.25 else EMPTY
	if ly >= TIER - 0.25:
		return CORNICE if d >= -0.125 else EMPTY
	# Half column: round in plan, capital under the cornice, base on the floor.
	if ly >= TIER - 0.5 or ly < (0.125 if k > 0 else 0.0):
		if pier < 0.25 and d >= -0.25:
			return CORNICE
	elif pier < 0.19 and d >= -sqrt(maxf(0.0, 0.19 * 0.19 - pier * pier)) - 0.03:
		return COLUMN
	# Arch frame and keystone, one voxel proud of the wall.
	if d >= -0.125:
		var r := Vector2(dx, ly - ARCH_SPRING).length()
		if ly >= ARCH_SPRING and r >= ARCH_HALF and r < ARCH_HALF + 0.125:
			return CORNICE
		if absf(dx) < 0.07 and ly >= ARCH_SPRING + ARCH_HALF and ly < ARCH_SPRING + ARCH_HALF + 0.25:
			return CORNICE
	return EMPTY

## Outer wall: three arcades of round arches, attic with small windows.
static func _shell(d: float, y: float, dx: float, variant: int) -> int:
	if y < PLINTH:
		return SILL
	if y < TIER * 3.0:
		var k := int(y / TIER)
		var ly := y - k * TIER
		var floor_y := PLINTH if k == 0 else 0.125
		var top := ARCH_SPRING + sqrt(maxf(0.0, ARCH_HALF * ARCH_HALF - dx * dx))
		if absf(dx) < ARCH_HALF and ly >= floor_y and ly < top:
			if k > 0 and d >= 0.25:
				return _statue(dx, ly - floor_y, variant + k)
			return EMPTY
		return SILL if ly < floor_y else _ashlar_at(dx, y, variant, STONE_LOW if k == 0 else STONE)
	var ly := y - TIER * 3.0
	if variant % 2 == 0 and absf(dx) < 0.19 and ly >= 0.375 and ly < 0.75:
		return EMPTY if d < 0.125 else WINDOW
	# Bronze shields between the attic windows, one voxel proud.
	if variant % 2 == 1 and Vector2(dx, ly - 0.56).length() < 0.2:
		return BRONZE if d < 0.125 else STONE
	return _ashlar_at(dx, y, variant, STONE)

## Ashlar courses: a few blocks a shade darker, so the wall reads as stone.
static func _ashlar_at(dx: float, y: float, variant: int, base: int) -> int:
	if not _ashlar:
		return base
	var course := floori(y / 0.25)
	var block := floori((dx + 0.5 * BAY_W) / 0.5 + 0.5 * (course % 2))
	return STONE_B if absi(hash(Vector3i(variant, course, block))) % 100 < 28 else base

## A statue on a pedestal in an upper arch; every third one is bronze.
static func _statue(dx: float, h: float, which: int) -> int:
	var material := BRONZE if which % 3 == 0 else STATUE
	if h < 0.125:
		return STONE_MID if absf(dx) < 0.19 else EMPTY
	if h < 0.625:
		return material if absf(dx) < 0.125 else EMPTY
	if h < 0.75:
		return material if absf(dx) < 0.07 else EMPTY
	return EMPTY

## Ambulatory behind the arches: floors, radial walls at the piers, a dark
## back wall. This is what the eye sees through every arch.
static func _gallery(d: float, y: float, pier: float) -> int:
	var k := int(y / TIER)
	var ly := y - k * TIER
	if ly < (PLINTH if k == 0 else 0.125):
		return GALLERY_FLOOR
	if d >= 1.25:
		return GALLERY
	if pier < 0.25:
		return STONE_MID
	return EMPTY

## Rim walkway, seat rows with seated figures, a walkway ring, entrances,
## podium and arena.
static func _cavea(u: float, d: float, y: float, dx: float, variant: int) -> int:
	var arena := (1.0 - ARENA_E) * R0
	if d >= R0:
		return EMPTY
	if d >= arena:
		if y >= ARENA_Y:
			return EMPTY
		if y < ARENA_Y - 0.125:
			return SEAT_STONE
		return SAND_DARK if d < arena + 0.25 else SAND
	if d >= arena - 0.25:
		if y >= PODIUM_TOP + 0.25:
			return EMPTY
		return PODIUM_BAND if y >= PODIUM_TOP + 0.125 else PODIUM
	if d < 0.75:
		return STONE if y < WALL_TOP else EMPTY
	if d < 1.0:
		if y >= SEAT_TOP:
			return EMPTY
		return WALKWAY if y >= SEAT_TOP - 0.125 else SEAT_STONE
	var rows := floori((arena - 0.25 - 1.0) / ROW_D)
	var row := mini(floori((d - 1.0) / ROW_D), rows - 1)
	var seat := snappedf(SEAT_TOP - (SEAT_TOP - PODIUM_TOP) * float(row + 1) / rows, FINE)
	var walkway := row == 5 or row == rows - 1
	var entrance := variant == 0 and absf(dx) < 0.3 and row > 5
	if y < seat - 0.125:
		return SEAT_STONE
	if y < seat:
		if walkway:
			return WALKWAY
		return VOMITORIUM if entrance else SEAT_STONE
	if walkway or entrance:
		return EMPTY
	# A seated figure on every other voxel of the back half of the row:
	# a robe, then a head.
	var iu := floori(u / FINE)
	var back := d - 1.0 - row * ROW_D >= ROW_D * 0.5
	if not back or (iu + row) % 2 != 0:
		return EMPTY
	var h := absi(hash(Vector3i(variant, iu, row)))
	if y < seat + 0.125:
		return CROWD + h % CROWD_COUNT
	if y < seat + 0.25:
		return HAIR if h % 5 == 0 else SKIN
	return EMPTY

## A thin mast with a red pennant above every pier.
static func _masts(d: float, y: float, u: float) -> int:
	if d < 0.0 or d >= 0.125 or y >= WALL_TOP + 1.0:
		return EMPTY
	if u < 0.125:
		return MAST
	var ly := y - (WALL_TOP + 0.625)
	if ly >= 0.0 and u < 0.125 + 0.5 * (1.0 - absf(ly - 0.1875) / 0.25):
		return RED
	return EMPTY

# Ellipse angle at equal arc-length steps, so every bay has the same width.
static var _arc: PackedFloat32Array

static func _phi(bay: float) -> float:
	if _arc.is_empty():
		var steps := 4096
		var lengths := PackedFloat32Array()
		lengths.resize(steps + 1)
		var total := 0.0
		for i in steps:
			var a0 := TAU * i / steps
			var a1 := TAU * (i + 1) / steps
			total += Vector2(A * (cos(a1) - cos(a0)), B * (sin(a1) - sin(a0))).length()
			lengths[i + 1] = total
		_arc.resize(BAYS * 64 + 1)
		var j := 0
		for k in _arc.size():
			var target := total * k / (BAYS * 64)
			while j < steps - 1 and lengths[j + 1] < target:
				j += 1
			var t := (target - lengths[j]) / maxf(1e-6, lengths[j + 1] - lengths[j])
			_arc[k] = TAU * (j + clampf(t, 0.0, 1.0)) / steps
	var x := fposmod(bay, float(BAYS)) * 64.0
	var i := mini(int(x), _arc.size() - 2)
	return lerpf(_arc[i], _arc[i + 1], x - i) + (TAU if bay >= BAYS else 0.0)

static func _radius(phi: float) -> float:
	return Vector2(A * cos(phi), B * sin(phi)).length()

## Point at angle phi, `d` metres of template depth inside the outer face,
## height y. The facade zone keeps true metres; deeper in, the template's
## nominal radius is stretched to this angle's radius.
static func _onto(phi: float, d: float, y: float) -> Vector3:
	var r := _radius(phi)
	var depth := d if d <= 1.5 else 1.5 + (d - 1.5) * (r - 1.5) / (R0 - 1.5)
	var s := maxf(0.0, 1.0 - depth / r)
	return Vector3(A * cos(phi) * s, y, B * sin(phi) * s)

## Voxel grid of one bay variant at voxel size v. Coarse voxels take the
## weighted majority of FINE subsamples (each layer up weighs double, so the
## visible top layer wins, crowd colours vote together, red always wins,
## and a few figures are enough to make a crowd block).
static func _voxelize(variant: int, v: float) -> Dictionary:
	var n := Vector3i(roundi(BAY_W / v), ceili((WALL_TOP + 1.25) / v), ceili((R0 + 0.75) / v))
	var cu := BAY_W / n.x
	var ss := maxi(1, roundi(v / FINE))
	var fu := cu / ss
	var grid := PackedByteArray()
	grid.resize(n.x * n.y * n.z)
	var counts := PackedInt32Array()
	counts.resize(PALETTE.size())
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var c := EMPTY
				if ss == 1:
					c = _sample((x + 0.5) * cu, (z + 0.5) * v - 0.75, (y + 0.5) * v, variant)
				else:
					counts.fill(0)
					var solid := 0
					var people := 0
					for sz in ss:
						for sy in ss:
							for sx in ss:
								var s := _sample((x * ss + sx + 0.5) * fu, (z * ss + sz + 0.5) * FINE - 0.75, (y * ss + sy + 0.5) * FINE, variant)
								if s == EMPTY:
									continue
								solid += 1
								if s == SKIN or s == HAIR:
									people += 1
								if s >= CROWD and s < CROWD + CROWD_COUNT:
									people += 1
									s = CROWD
								counts[s] += 1 << sy
					if counts[RED] > 0:
						c = RED
					elif people * 16 >= ss * ss * ss:
						# Seated figures are thinner than a coarse voxel: they
						# become calm mixed crowd tones, not vanishing or confetti.
						c = CROWD_MUTED + absi(hash(Vector4i(variant, x, y, z))) % CROWD_MUTED_COUNT
					elif solid * 8 >= ss * ss * ss * 3:
						var best := 0
						for i in range(1, counts.size()):
							if counts[i] > counts[best]:
								best = i
						c = CROWD_MUTED + absi(hash(Vector4i(variant, x, y, z))) % CROWD_MUTED_COUNT if best == CROWD else best
				grid[x + n.x * (y + n.y * z)] = c
	return {"grid": grid, "n": n, "v": v}

## Cell lookup. Along u the grid wraps: the neighbouring bay is nearly the
## same, so faces between bays vanish and occlusion carries across.
static func _at(vox: Dictionary, c: Vector3i) -> int:
	var n: Vector3i = vox.n
	if c.y < 0 or c.z < 0 or c.y >= n.y or c.z >= n.z:
		return EMPTY
	return vox.grid[posmod(c.x, n.x) + n.x * (c.y + n.y * c.z)]

## Exposed faces of a voxel grid as quads in grid coordinates: corners,
## outward axis, colour and corner occlusion. Neighbouring faces of one
## colour merge wherever their corner shading allows it exactly. Downward
## faces are skipped: the city camera never looks up.
static func _faces(vox: Dictionary) -> Array:
	var quads := []
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
							corners.append(g)
						var col_id := key & 0xFF
						var colour: Color = TOP[col_id] if axis == 1 and TOP.has(col_id) else PALETTE[col_id]
						quads.append([corners, Vector3(nv), colour, ao4])
						a += wide
	return quads

## Bends one bay's quads (grid coordinates) onto its segment of the ring.
static func _bend_into(st: SurfaceTool, quads: Array, vox: Dictionary, bay: int) -> void:
	var n: Vector3i = vox.n
	var v: float = vox.v
	var bend := func(g: Vector3) -> Vector3:
		return _onto(_phi(bay + g.x / n.x), g.z * v - 0.75, g.y * v)
	for q in quads:
		var corners: Array[Vector3] = []
		var mid := Vector3.ZERO
		for g: Vector3 in q[0]:
			corners.append(bend.call(g))
			mid += g * 0.25
		var out: Vector3 = bend.call(mid + q[1] * 0.5) - bend.call(mid)
		var aos: Array[int] = []
		for k in 4:
			aos.append((q[3] >> (k * 2)) & 3)
		_emit(st, corners, aos, q[2], out)

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

## The ring at voxel size v: each variant is voxelized and meshed once, then
## bent onto every bay that uses it.
static func build(v: float) -> ArrayMesh:
	_ashlar = v <= FINE
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for variant in VARIANTS:
		var vox := _voxelize(variant, v)
		var quads := _faces(vox)
		for bay in range(variant, BAYS, VARIANTS):
			_bend_into(st, quads, vox, bay)
	return st.commit()

## The far LOD, 168 triangles: at that distance voxels are below a pixel, so
## a 12-sided drum carries the colour masses: arcade band, attic, the red
## crown of flags, crowd, sand.
static func drum() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var arcade: Color = PALETTE[STONE].lerp(PALETTE[GALLERY], 0.35)
	var arena := (1.0 - ARENA_E) * R0
	for i in n:
		var p0 := TAU * i / n
		var p1 := TAU * (i + 1) / n
		var out := _onto((p0 + p1) * 0.5, -1.0, 0.0) - _onto((p0 + p1) * 0.5, 0.0, 0.0)
		_flat(st, [_onto(p0, 0.0, 0.0), _onto(p1, 0.0, 0.0), _onto(p1, 0.0, TIER * 3.0), _onto(p0, 0.0, TIER * 3.0)], arcade, out)
		_flat(st, [_onto(p0, 0.0, TIER * 3.0), _onto(p1, 0.0, TIER * 3.0), _onto(p1, 0.0, WALL_TOP), _onto(p0, 0.0, WALL_TOP)], PALETTE[STONE], out)
		_flat(st, [_onto(p0, 0.0, WALL_TOP), _onto(p1, 0.0, WALL_TOP), _onto(p1, 0.75, WALL_TOP), _onto(p0, 0.75, WALL_TOP)],
			PALETTE[CORNICE].lerp(PALETTE[RED], 0.55), Vector3.UP)
		_flat(st, [_onto(p0, 1.0, SEAT_TOP), _onto(p1, 1.0, SEAT_TOP), _onto(p1, arena, PODIUM_TOP), _onto(p0, arena, PODIUM_TOP)],
			PALETTE[CROWD_MUTED + 1], Vector3.UP)
		_flat(st, [_onto(p0, 0.75, WALL_TOP), _onto(p1, 0.75, WALL_TOP), _onto(p1, 0.75, SEAT_TOP), _onto(p0, 0.75, SEAT_TOP)], PALETTE[STONE_MID], -out)
		_flat(st, [_onto(p0, arena, PODIUM_TOP), _onto(p1, arena, PODIUM_TOP), _onto(p1, arena, ARENA_Y), _onto(p0, arena, ARENA_Y)], PALETTE[PODIUM], -out)
		var centre := Vector3(0, ARENA_Y, 0)
		_flat(st, [centre, _onto(p0, arena, ARENA_Y), _onto(p1, arena, ARENA_Y), centre], PALETTE[SAND], Vector3.UP)
	return st.commit()

## A flat-coloured quad (or triangle, when the last corner repeats the first).
static func _flat(st: SurfaceTool, p: Array, colour: Color, out: Vector3) -> void:
	var corners: Array[Vector3] = [p[0], p[1], p[2], p[3]]
	if corners[3].is_equal_approx(corners[0]):
		corners = [p[0], p[1], p[2], p[2]]
	_emit(st, corners, [3, 3, 3, 3], colour, out)

## All LODs, nearest first: the voxel rings, then the drum. Built meshes are
## cached in user://; delete the files (or bump CACHE) after changing the model.
static func lods() -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	for v: float in LOD_VOXELS:
		var path := CACHE % str(v)
		var mesh: ArrayMesh = load(path) if ResourceLoader.exists(path) else null
		if mesh == null:
			mesh = build(v)
			ResourceSaver.save(mesh, path)
		out.append(mesh)
	out.append(drum())
	return out

static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	return m

static func triangles(mesh: ArrayMesh) -> int:
	return mesh.surface_get_array_len(0) / 3
