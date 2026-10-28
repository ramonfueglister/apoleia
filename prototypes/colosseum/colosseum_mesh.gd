extends RefCounted
## Procedural colosseum in three detail levels: Urbek-like chunky shapes,
## Caesar III-like palette (warm grey-beige travertine, dark arches, sand
## arena, ring of red pennants). Vertex colours only, flat normals, one
## shared material. Units: about 16 x 13 wide and 6.5 tall, origin at ground
## centre.

const A := 8.0              # outer half-axis along x
const B := 6.6              # outer half-axis along z
const TIER := 1.9           # height of one arcade storey
const ATTIC := 1.1          # solid top storey with small windows
const H := TIER * 3.0 + ATTIC
const BAND := 0.12          # how far storey cornices project
const RIM := 0.6            # wall thickness at the top
const SEAT_TOP := 5.6       # seating starts below the rim
const ARENA := 0.5          # arena half-axes as a share of the outer ones
const PODIUM := 2.9         # lowest seats, above the raised arena
const FLOOR := 2.5          # raised arena floor, so the sand shows from the city camera

# Palette sampled from Caesar III screenshots (quantized crops of the
# colosseum, grass and roofs): warm grey-beige, deep arch shadows.
const STONE := Color("b9ab95")        # lit travertine, grey beige
const STONE_MID := Color("a2937b")    # spandrels, pilaster edges
const STONE_SHADE := Color("5c4d4b")  # cornice soffits, near the ground
const LEDGE := Color("dfcfc9")        # top of cornices, catches the sun
const RIM_TOP := Color("c9b39a")
const ARCH := Color("4a3c32")         # arch openings and windows, bottom
const ARCH_TOP := Color("6e5d4c")     # arch openings, top: depth, not holes
const REVEAL := Color("6b5843")       # arch side walls
const TERRACOTTA := Color("9a5a45")   # crown band, Caesar III's red ring
const WALKWAY := Color("5a4a3c")
const WALKWAY_LIP := Color("d8c8b0")
const PODIUM_STONE := Color("73684f")
const PODIUM_TOP := Color("a2937b")
const SAND := Color("a0874a")
const SAND_EDGE := Color("8c7040")
const POLE := Color("864534")
const RED := Color("b8433a")
const RED_UNDER := Color("864534")
# Crowd: grey-brown base tone (LOD1 and LOD2 slopes).
const CROWD_BASE := Color("a2937b")
const AISLE := Color("2b1f19")              # vomitoria: dark entrance wedges

## Emits a flat quad. `out` is a rough direction the visible side faces.
## `colour` is a Color for the whole quad, an Array of four corner colours
## in the order of `p` (they blend across the quad: pilaster edges, occlusion
## under ledges), or an Array of two, one flat colour per triangle (crowd).
static func _quad(st: SurfaceTool, p: Array, colour: Variant, out: Vector3) -> void:
	var c: Array = colour if colour is Array else [colour, colour, colour, colour]
	var per_tri: bool = c.size() == 2
	var tri_colours := c.duplicate()
	if per_tri:
		c = [c[0], c[0], c[0], c[0]]
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	if n.dot(out) < 0.0:
		p = [p[0], p[3], p[2], p[1]]
		c = [c[0], c[3], c[2], c[1]]
		n = -n
	var order := [0, 2, 1, 0, 3, 2]  # Godot: clockwise is the front
	for j in 6:
		var k: int = order[j]
		var q: Vector3 = p[k]
		var col: Color = c[k]
		if per_tri:
			col = tri_colours[0] if j < 3 else tri_colours[1]
		# Baked ambient occlusion: the lowest metre darkens towards the ground.
		var ao := lerpf(0.66, 1.0, clampf(q.y / 1.0, 0.0, 1.0))
		st.set_color(Color(col.r * ao, col.g * ao, col.b * ao))
		st.set_normal(n)
		st.add_vertex(q)

## Vertical gradient: bottom corners `lo`, top corners `hi` (p = bl, br, tr, tl).
static func _grad(lo: Color, hi: Color) -> Array:
	return [lo, lo, hi, hi]

static func _tri(st: SurfaceTool, p: Array, colours: Array, out: Vector3) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	if n.dot(out) < 0.0:
		p = [p[0], p[2], p[1]]
		colours = [colours[0], colours[2], colours[1]]
		n = -n
	for k in [0, 2, 1]:
		st.set_color(colours[k]); st.set_normal(n); st.add_vertex(p[k])

## Point on the ellipse. `grow` pushes it outward by a fixed distance, so
## projecting bands share their corners with the neighbours (no notches).
static func _ring(t: float, scale := 1.0, y := 0.0, grow := 0.0) -> Vector3:
	return Vector3(cos(t) * (A * scale + grow), y, sin(t) * (B * scale + grow))

static func _outward(t: float) -> Vector3:
	return Vector3(cos(t) / A, 0.0, sin(t) / B).normalized()

static func _ring_quad(st: SurfaceTool, t0: float, t1: float, r0: float, r1: float, y0: float, y1: float, colour: Variant, out: Vector3) -> void:
	_quad(st, [_ring(t0, r0, y0), _ring(t1, r0, y0), _ring(t1, r1, y1), _ring(t0, r1, y1)], colour, out)

## A square cornice ledge at height y: flat front, bright top.
static func _cornice(st: SurfaceTool, t0: float, t1: float, y: float, height: float, depth := BAND, front := STONE_MID) -> void:
	var out := _outward((t0 + t1) * 0.5)
	_quad(st, [_ring(t0, 1.0, y - height, depth), _ring(t1, 1.0, y - height, depth), _ring(t1, 1.0, y, depth), _ring(t0, 1.0, y, depth)],
		front, out)
	_quad(st, [_ring(t0, 1.0, y), _ring(t1, 1.0, y), _ring(t1, 1.0, y, depth), _ring(t0, 1.0, y, depth)], LEDGE, Vector3.UP)

## Crowd colour of one tread segment: a regular pattern per segment and
## tier, every fifth segment a red robe group, four dark entrance wedges
## (vomitoria). Calm and ordered, never split across a quad diagonal.
static func _crowd(i: int, tier: int) -> Color:
	if i % 10 == 0:
		return AISLE
	if (i + tier * 2) % 5 == 0:
		return Color("9a5040")
	return Color("b3a28c") if (i + tier) % 2 == 0 else Color("8a7462")

## Rim cap, inner wall, stepped seating with a crowd, podium and arena.
static func _bowl(st: SurfaceTool, n: int, steps: int) -> void:
	var inner := 1.0 - RIM / A
	var top := ARENA + 0.05
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var mid := (t0 + t1) * 0.5
		_ring_quad(st, t0, t1, 1.0, inner, H, H, RIM_TOP, Vector3.UP)
		_quad(st, [_ring(t0, inner, H), _ring(t1, inner, H), _ring(t1, inner, SEAT_TOP), _ring(t0, inner, SEAT_TOP)],
			_grad(STONE_MID, STONE), -_outward(mid))
		for s in steps:
			var r0 := lerpf(inner, top, float(s) / steps)
			var r1 := lerpf(inner, top, float(s + 1) / steps)
			var y0 := lerpf(SEAT_TOP, PODIUM, float(s) / steps)
			var y1 := lerpf(SEAT_TOP, PODIUM, float(s + 1) / steps)
			if steps > 1:
				# Short walkway wall with a lit lip, then a tread sloping down to
				# the next one, so the crowd fills most of the bowl.
				var lip := lerpf(y0, y1, 0.25)
				_quad(st, [_ring(t0, r0, lip), _ring(t1, r0, lip), _ring(t1, r0, y0), _ring(t0, r0, y0)],
					[WALKWAY_LIP, WALKWAY_LIP, WALKWAY, WALKWAY], -_outward(mid))
				_ring_quad(st, t0, t1, r0, r1, lip, y1, _crowd(i, s), Vector3.UP)
			else:
				_ring_quad(st, t0, t1, r0, r1, y0, y1, _grad(CROWD_BASE, CROWD_BASE.lerp(LEDGE, 0.3)), Vector3.UP)
		# Podium: a pale cap on a darker wall around the arena.
		_ring_quad(st, t0, t1, top, ARENA, PODIUM, PODIUM, PODIUM_TOP, Vector3.UP)
		_quad(st, [_ring(t0, ARENA, PODIUM), _ring(t1, ARENA, PODIUM), _ring(t1, ARENA, FLOOR), _ring(t0, ARENA, FLOOR)],
			_grad(PODIUM_STONE.darkened(0.2), PODIUM_STONE), -_outward(mid))
		_tri(st, [Vector3(0, FLOOR, 0), _ring(t0, ARENA, FLOOR), _ring(t1, ARENA, FLOOR)], [SAND, SAND_EDGE, SAND_EDGE], Vector3.UP)

## Red pennants on masts along the outer rim, one per bay. The mast is a
## closed three-sided prism; the flag has both windings and an upward-leaning
## normal so its back is lit like the front.
static func _pennants(st: SurfaceTool, count: int, every := 1) -> void:
	for i in range(0, count, every):
		var t := TAU * i / count
		var base := _ring(t, 1.0, H, BAND * 0.3)
		var along := _outward(t).cross(Vector3.UP)
		var o := _outward(t)
		var nrm := (Vector3.UP + o).normalized()
		var r := 0.07
		var feet := [base + o * r, base + along * r * 0.87 - o * r * 0.5, base - along * r * 0.87 - o * r * 0.5]
		for k in 3:
			var f0: Vector3 = feet[k]
			var f1: Vector3 = feet[(k + 1) % 3]
			var side := (f0 + f1) * 0.5 - base
			_quad(st, [f0, f1, f1 + Vector3(0, 1.05, 0), f0 + Vector3(0, 1.05, 0)], POLE, side)
		var flag := [base + Vector3(0, 1.05, 0), base + Vector3(0, 0.55, 0), base + along * 0.65 + Vector3(0, 0.8, 0)]
		var fc := [RED, RED_UNDER, RED]
		for k in [0, 1, 2, 0, 2, 1]:
			st.set_color(fc[k]); st.set_normal(nrm); st.add_vertex(flag[k])

## LOD0, about 2k triangles: 20 bays with chamfered round arches, square
## storey cornices, attic with windows and pilaster shading, three seat rings with
## a crowd mosaic.
static func lod0() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	var pier := 0.2
	var depth := 0.38
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var out := _outward((t0 + t1) * 0.5)
		var a := _ring(t0)
		var b := _ring(t1)
		var at := func(u: float, y: float, inset := 0.0) -> Vector3:
			return a.lerp(b, u) + Vector3(0, y, 0) - out * inset
		for tier in 3:
			var y0 := tier * TIER
			var y1 := y0 + TIER
			var spring := y0 + TIER * 0.5
			var crown := y0 + TIER * 0.72
			var u0 := pier
			var u1 := 1.0 - pier
			# Piers darken towards the cornice above: baked occlusion.
			_quad(st, [at.call(0.0, y0), at.call(u0, y0), at.call(u0, y1), at.call(0.0, y1)], _grad(STONE, STONE_MID.lerp(STONE_SHADE, 0.4)), out)
			_quad(st, [at.call(u1, y0), at.call(1.0, y0), at.call(1.0, y1), at.call(u1, y1)], _grad(STONE, STONE_MID.lerp(STONE_SHADE, 0.4)), out)
			# Chamfered round arch: spring, shoulder, shoulder, spring.
			var arc := [Vector2(u0, spring), Vector2(lerpf(u0, 0.5, 0.45), crown), Vector2(lerpf(u1, 0.5, 0.45), crown), Vector2(u1, spring)]
			for k in 3:
				var p: Vector2 = arc[k]
				var q: Vector2 = arc[k + 1]
				_quad(st, [at.call(p.x, p.y), at.call(q.x, q.y), at.call(q.x, y1), at.call(p.x, y1)],
					_grad(STONE_MID, STONE_MID.lerp(STONE_SHADE, 0.5)), out)
			# The dark gallery ring behind the arcades closes every opening; the
			# top reveals face down and are never seen from the city camera.
			# Side reveals run up to the crown so the chamfers show no gap.
			_quad(st, [at.call(u0, y0), at.call(u0, y0, depth), at.call(u0, crown, depth), at.call(u0, crown)], REVEAL, b - a)
			_quad(st, [at.call(u1, y0), at.call(u1, y0, depth), at.call(u1, crown, depth), at.call(u1, crown)], REVEAL, a - b)
			# Square cornice on top of every storey: the crisp Urbek shadow line.
			_cornice(st, t0, t1, y1, 0.2)
		# Gallery: one dark ring behind all three arcades, 2 triangles per bay.
		_quad(st, [_ring(t0, 1.0, 0.0, -0.4), _ring(t1, 1.0, 0.0, -0.4), _ring(t1, 1.0, TIER * 3, -0.4), _ring(t0, 1.0, TIER * 3, -0.4)],
			_grad(ARCH, ARCH_TOP), out)
		# Attic: pilaster shading at the bay edges, one small window, heavy cornice.
		_quad(st, [at.call(0.0, TIER * 3), at.call(1.0, TIER * 3), at.call(1.0, H), at.call(0.0, H)],
			[STONE_MID, STONE, STONE.lerp(STONE_SHADE, 0.3), STONE_MID.lerp(STONE_SHADE, 0.5)], out)
		var wy := TIER * 3 + ATTIC * 0.3
		_quad(st, [at.call(0.38, wy, -0.01), at.call(0.62, wy, -0.01), at.call(0.62, wy + ATTIC * 0.32, -0.01), at.call(0.38, wy + ATTIC * 0.32, -0.01)], ARCH, out)
		_cornice(st, t0, t1, H, 0.3, BAND * 1.5, TERRACOTTA)
	_bowl(st, n, 4)
	_pennants(st, n)
	return st.commit()

## LOD1, about 450 triangles: the drum with a dark pentagon arch per bay
## and storey, terracotta crown, the bowl as one shaded slope, every
## third mast of LOD0.
static func lod1() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var out := _outward((t0 + t1) * 0.5)
		var a := _ring(t0)
		var b := _ring(t1)
		for tier in 3:
			# One quad per storey, lighter at the top: the cornice lines of LOD0.
			_quad(st, [_ring(t0, 1.0, tier * TIER), _ring(t1, 1.0, tier * TIER), _ring(t1, 1.0, (tier + 1) * TIER), _ring(t0, 1.0, (tier + 1) * TIER)],
				_grad(STONE_MID, LEDGE), out)
		_quad(st, [_ring(t0, 1.0, TIER * 3), _ring(t1, 1.0, TIER * 3), _ring(t1, 1.0, H), _ring(t0, 1.0, H)], _grad(STONE_MID, TERRACOTTA), out)
		for tier in 3:
			var y0 := tier * TIER
			var at := func(u: float, y: float) -> Vector3:
				return a.lerp(b, u) + Vector3(0, y, 0) + out * 0.03
			var p := [at.call(0.25, y0), at.call(0.75, y0), at.call(0.75, y0 + TIER * 0.5), at.call(0.5, y0 + TIER * 0.72), at.call(0.25, y0 + TIER * 0.5)]
			_tri(st, [p[0], p[1], p[2]], [ARCH, ARCH, ARCH_TOP], out)
			_tri(st, [p[0], p[2], p[4]], [ARCH, ARCH_TOP, ARCH_TOP], out)
			_tri(st, [p[4], p[2], p[3]], [ARCH_TOP, ARCH_TOP, ARCH_TOP], out)
	_bowl(st, n, 1)
	_pennants(st, 21, 3)
	return st.commit()

## LOD2, 90 triangles: same footprint and height as LOD0, a dark
## arcade band, terracotta crown, crowd slope to a sand floor.
static func lod2() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var band := 1.0 - 0.5 * RIM / A
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var out := _outward((t0 + t1) * 0.5)
		_quad(st, [_ring(t0), _ring(t1), _ring(t1, 1.0, TIER * 3), _ring(t0, 1.0, TIER * 3)], _grad(STONE_MID.lerp(ARCH, 0.45), STONE_MID.lerp(ARCH, 0.25)), out)
		_quad(st, [_ring(t0, 1.0, TIER * 3), _ring(t1, 1.0, TIER * 3), _ring(t1, 1.0, H), _ring(t0, 1.0, H)], _grad(STONE, TERRACOTTA), out)
		_ring_quad(st, t0, t1, 1.0, band, H, H, RIM_TOP, Vector3.UP)
		_ring_quad(st, t0, t1, band, ARENA, H, PODIUM, _grad(CROWD_BASE, CROWD_BASE.lerp(LEDGE, 0.3)), Vector3.UP)
		_tri(st, [Vector3(0, PODIUM, 0), _ring(t0, ARENA, PODIUM), _ring(t1, ARENA, PODIUM)], [SAND, SAND_EDGE, SAND_EDGE], Vector3.UP)
	return st.commit()

static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	return m

static func triangles(mesh: ArrayMesh) -> int:
	return mesh.surface_get_array_len(0) / 3
