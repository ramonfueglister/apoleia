extends RefCounted
## Procedural colosseum in three detail levels: Urbek-like chunky shapes,
## Caesar III-like palette (warm travertine, dark arches, sand arena, red
## pennants). Vertex colours only, flat normals, one shared material.
## Units: about 16 x 13 wide and 5.4 tall, origin at ground centre.

const A := 8.0              # outer half-axis along x
const B := 6.6              # outer half-axis along z
const TIER := 1.4           # height of one arcade storey
const ATTIC := 1.2          # solid top storey
const H := TIER * 3.0 + ATTIC
const RIM := 1.0            # wall thickness at the top
const SEAT_TOP := 4.0       # seating starts below the rim
const ARENA := 0.45         # arena half-axes as a share of the outer ones
const PODIUM := 0.55        # wall between arena and lowest seats

# Palette sampled from Caesar III screenshots (quantized crops of the
# colosseum, grass and roofs): warm, darker midtones, deep arch shadows.
const STONE := Color("d8cbb6")        # lit travertine
const STONE_DARK := Color("a08a70")   # cornice, shadowed stone
const ARCH := Color("2e2419")         # arch openings
const REVEAL := Color("6b5644")       # arch side walls
const SEATS_A := Color("b7a28d")
const SEATS_B := Color("8d7a62")
const SAND := Color("b09070")
const RED := Color("a8302a")
const CROWD := [Color("6f6a62"), Color("dfcfbc"), Color("5b4839"), Color("b05e3a"), Color("9a9177")]

## Emits a flat quad. `out` is a rough direction the visible side faces.
static func _quad(st: SurfaceTool, p: Array, colour: Color, out: Vector3) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	if n.dot(out) < 0.0:
		p = [p[0], p[3], p[2], p[1]]
		n = -n
	for k in [0, 2, 1, 0, 3, 2]:  # Godot: clockwise is the front
		# Baked ambient occlusion: stone darkens towards the ground.
		var q: Vector3 = p[k]
		var ao := lerpf(0.62, 1.0, clampf(q.y / 0.9, 0.0, 1.0))
		st.set_color(Color(colour.r * ao, colour.g * ao, colour.b * ao))
		st.set_normal(n)
		st.add_vertex(q)

static func _tri(st: SurfaceTool, p: Array, colour: Color, out: Vector3) -> void:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
	if n.dot(out) < 0.0:
		p = [p[0], p[2], p[1]]
		n = -n
	for k in [0, 2, 1]:
		st.set_color(colour); st.set_normal(n); st.add_vertex(p[k])

static func _ring(t: float, scale := 1.0, y := 0.0) -> Vector3:
	return Vector3(cos(t) * A * scale, y, sin(t) * B * scale)

static func _outward(t: float) -> Vector3:
	return Vector3(cos(t) / A, 0.0, sin(t) / B).normalized()

## Top cap, inner wall, stepped seating, podium and arena: shared by LOD0/1.
static func _bowl(st: SurfaceTool, n: int, steps: int) -> void:
	var inner := 1.0 - RIM / A
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var mid := (t0 + t1) * 0.5
		st_quad_ring(st, t0, t1, 1.0, inner, H, H, STONE, Vector3.UP)
		_quad(st, [_ring(t0, inner, H), _ring(t1, inner, H), _ring(t1, inner, SEAT_TOP), _ring(t0, inner, SEAT_TOP)],
			STONE_DARK, -_outward(mid))
		# Seats step down from the inner wall to the podium.
		for s in steps:
			var r0 := lerpf(inner, ARENA, float(s) / steps)
			var r1 := lerpf(inner, ARENA, float(s + 1) / steps)
			var y0 := lerpf(SEAT_TOP, PODIUM, float(s) / steps)
			var y1 := lerpf(SEAT_TOP, PODIUM, float(s + 1) / steps)
			var c := SEATS_A if s % 2 == 0 else SEATS_B
			# Crowd: a cheap per-segment speckle, no extra triangles.
			c = c.lerp(CROWD[(i * 7 + s * 3) % CROWD.size()], 0.3 if steps > 1 else 0.0)
			if steps > 1:
				_quad(st, [_ring(t0, r0, y1), _ring(t1, r0, y1), _ring(t1, r0, y0), _ring(t0, r0, y0)], c.darkened(0.12), -_outward(mid))
				st_quad_ring(st, t0, t1, r0, r1, y1, y1, c, Vector3.UP)
			else:
				st_quad_ring(st, t0, t1, r0, r1, y0, y1, c, Vector3.UP)
		_quad(st, [_ring(t0, ARENA, PODIUM), _ring(t1, ARENA, PODIUM), _ring(t1, ARENA, 0.1), _ring(t0, ARENA, 0.1)],
			STONE_DARK, -_outward(mid))
		# Arena floor as a fan, one triangle per segment.
		var nn := Vector3.UP
		var tri := [Vector3(0, 0.1, 0), _ring(t0, ARENA, 0.1), _ring(t1, ARENA, 0.1)]
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(nn) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for q in tri:
			st.set_color(SAND); st.set_normal(nn); st.add_vertex(q)

static func st_quad_ring(st: SurfaceTool, t0: float, t1: float, r0: float, r1: float, y0: float, y1: float, colour: Color, out: Vector3) -> void:
	_quad(st, [_ring(t0, r0, y0), _ring(t1, r0, y0), _ring(t1, r1, y1), _ring(t0, r1, y1)], colour, out)

## Red pennants on the rim, two-sided (both windings) so one material does.
static func _pennants(st: SurfaceTool, count: int) -> void:
	for i in count:
		var t := TAU * (i + 0.5) / count
		var base := _ring(t, 1.0 - 0.5 * RIM / A, H)
		var side := _outward(t).cross(Vector3.UP) * 0.35
		var p := [base, base + side, base + side + Vector3(0, 0.9, 0), base + Vector3(0, 0.9, 0)]
		_quad(st, p, RED, _outward(t))
		_quad(st, p, RED, -_outward(t))

## LOD0, about 1.3k triangles: every bay has a round arch with depth.
static func lod0() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 16
	var pier := 0.2
	var depth := 0.3
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
			var crown := y0 + TIER * 0.78
			var u0 := pier
			var u1 := 1.0 - pier
			var band := STONE_DARK if tier < 2 else STONE
			_quad(st, [at.call(0.0, y0), at.call(u0, y0), at.call(u0, y1), at.call(0.0, y1)], STONE, out)
			_quad(st, [at.call(u1, y0), at.call(1.0, y0), at.call(1.0, y1), at.call(u1, y1)], STONE, out)
			# Round arch as a four-sided polygon: spring, shoulder, crown.
			var arc := [Vector2(u0, spring), Vector2(lerpf(u0, 0.5, 0.35), lerpf(spring, crown, 0.8)), Vector2(0.5, crown),
				Vector2(lerpf(u1, 0.5, 0.35), lerpf(spring, crown, 0.8)), Vector2(u1, spring)]
			for k in 4:
				var p: Vector2 = arc[k]
				var q: Vector2 = arc[k + 1]
				_quad(st, [at.call(p.x, p.y), at.call(q.x, q.y), at.call(q.x, y1), at.call(p.x, y1)], band, out)
			# Back of the opening and its side reveals; the top reveals face
			# down and are never seen from the city camera, so they are left out.
			_quad(st, [at.call(u0, y0, depth), at.call(u1, y0, depth), at.call(u1, spring, depth), at.call(u0, spring, depth)], ARCH, out)
			var o: Vector2 = arc[0]
			for k in [1, 2, 3]:
				var p: Vector2 = arc[k]
				var q: Vector2 = arc[k + 1]
				_tri(st, [at.call(o.x, o.y, depth), at.call(p.x, p.y, depth), at.call(q.x, q.y, depth)], ARCH, out)
			_quad(st, [at.call(u0, y0), at.call(u0, y0, depth), at.call(u0, spring, depth), at.call(u0, spring)], REVEAL, b - a)
			_quad(st, [at.call(u1, y0), at.call(u1, y0, depth), at.call(u1, spring, depth), at.call(u1, spring)], REVEAL, a - b)
		# Solid attic, then a chunky projecting cornice under the rim.
		var lip := H - 0.28
		_quad(st, [at.call(0.0, TIER * 3), at.call(1.0, TIER * 3), at.call(1.0, lip), at.call(0.0, lip)], STONE, out)
		_quad(st, [at.call(0.0, lip), at.call(1.0, lip), at.call(1.0, lip, -0.22), at.call(0.0, lip, -0.22)], STONE_DARK.darkened(0.15), Vector3.DOWN)
		_quad(st, [at.call(0.0, lip, -0.22), at.call(1.0, lip, -0.22), at.call(1.0, H, -0.22), at.call(0.0, H, -0.22)], STONE, out)
		_quad(st, [at.call(0.0, H, -0.22), at.call(1.0, H, -0.22), at.call(1.0, H), at.call(0.0, H)], STONE, Vector3.UP)
	_bowl(st, n, 2)
	_pennants(st, 16)
	return st.commit()

## LOD1, about 200 triangles: arches become a dark band per storey.
static func lod1() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var out := _outward((t0 + t1) * 0.5)
		for tier in 3:
			var y0 := tier * TIER
			var top := y0 + TIER * 0.72
			_quad(st, [_ring(t0, 1.0, y0), _ring(t1, 1.0, y0), _ring(t1, 1.0, top), _ring(t0, 1.0, top)], STONE.lerp(ARCH, 0.5), out)
			_quad(st, [_ring(t0, 1.0, top), _ring(t1, 1.0, top), _ring(t1, 1.0, y0 + TIER), _ring(t0, 1.0, y0 + TIER)], STONE, out)
		_quad(st, [_ring(t0, 1.0, TIER * 3), _ring(t1, 1.0, TIER * 3), _ring(t1, 1.0, H), _ring(t0, 1.0, H)], STONE, out)
	_bowl(st, n, 1)
	return st.commit()

## LOD2, 40 triangles: a stone ring around a sand floor.
static func lod2() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 8
	var facade := STONE.lerp(ARCH, 0.3)
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var out := _outward((t0 + t1) * 0.5)
		_quad(st, [_ring(t0), _ring(t1), _ring(t1, 1.0, H), _ring(t0, 1.0, H)], facade, out)
		st_quad_ring(st, t0, t1, 1.0, ARENA, H, PODIUM, SEATS_A, Vector3.UP)
		var tri := [Vector3(0, PODIUM, 0), _ring(t0, ARENA, PODIUM), _ring(t1, ARENA, PODIUM)]
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).y > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for q in tri:
			st.set_color(SAND); st.set_normal(Vector3.UP); st.add_vertex(q)
	return st.commit()

static func material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	return m

static func triangles(mesh: ArrayMesh) -> int:
	return mesh.surface_get_array_len(0) / 3
