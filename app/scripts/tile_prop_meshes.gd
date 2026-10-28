extends RefCounted
## Procedural meshes of the tile terrain: the tile template (top and four
## walls, positioned by tile_terrain.gdshader), voxel trees after Urbek and
## low-poly houses with vertex colours. Units: a prop is about 1 unit tall, origin on the ground.

static func tile_template() -> ArrayMesh:
	# VERTEX.x = part (0 top, 1..4 walls N, E, S, W, 5 coast edge along the
	# diagonal), VERTEX.y = corner or role. The top is two separate triangles
	# (roles 0..2, 3..5), so a coast cut can lower one of them.
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for role in 6:
		verts.append(Vector3(0, role, 0))
		index.append(role)
	for part in range(1, 6):
		var base := verts.size()
		for role in 4:
			verts.append(Vector3(part, role, 0))
		index.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## One block of a voxel prop (Urbek style): flat faces, light top, darker
## sides and underside (the sides are mostly in shade, so not by much). `caps`: also draw the top and bottom.
static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, top: Color, side: Color, caps := true) -> void:
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	var faces := [[[4, 5, 6, 7], Vector3.UP, top], [[0, 1, 5, 4], Vector3.FORWARD, side], [[1, 2, 6, 5], Vector3.RIGHT, side],
		[[2, 3, 7, 6], Vector3.BACK, side], [[3, 0, 4, 7], Vector3.LEFT, side], [[0, 3, 2, 1], Vector3.DOWN, side.darkened(0.4)]]
	for face in faces:
		var n: Vector3 = face[1]
		if not caps and absf(n.y) > 0.5:
			continue
		var q: Array = face[0]
		var a: Vector3 = c[q[0]]
		var b: Vector3 = c[q[1]]
		var d: Vector3 = c[q[3]]
		# Godot draws clockwise faces, seen from outside
		if (b - a).cross(c[q[2]] - a).dot(n) > 0.0:
			var t: Vector3 = b; b = d; d = t
		for p in [a, b, c[q[2]], a, c[q[2]], d]:
			st.set_color(face[2]); st.set_normal(n); st.add_vertex(p)

## Deciduous tree (oak, beech): a blocky crown of stacked voxels on a short
## trunk, Urbek's bright top and dark sides. `low`: the far version (two
## blocks, for trees a few pixels tall).
static func broadleaf(low := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Color(0.29, 0.54, 0.28)
	var side := Color(0.25, 0.47, 0.24)
	_box(st, Vector3(-0.06, 0, -0.06), Vector3(0.06, 0.42, 0.06), Color(0.42, 0.29, 0.18), Color(0.42, 0.29, 0.18), false)
	_box(st, Vector3(-0.32, 0.36, -0.32), Vector3(0.32, 0.86, 0.32), top, side)
	_box(st, Vector3(-0.20, 0.86, -0.20), Vector3(0.16, 1.04, 0.18), top.lightened(0.06), side)
	if not low:
		_box(st, Vector3(0.18, 0.46, -0.22), Vector3(0.42, 0.76, 0.10), top.darkened(0.06), side.darkened(0.06))
		_box(st, Vector3(-0.24, 0.42, 0.16), Vector3(0.06, 0.70, 0.42), top, side)
	return st.commit()

## Conifer (fir, spruce): stacked voxel tiers getting smaller to the tip.
static func conifer(far := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Color(0.22, 0.43, 0.28)
	var side := Color(0.17, 0.35, 0.23)
	_box(st, Vector3(-0.05, 0, -0.05), Vector3(0.05, 0.2, 0.05), Color(0.36, 0.25, 0.16), Color(0.36, 0.25, 0.16), false)
	if far:
		_box(st, Vector3(-0.28, 0.14, -0.28), Vector3(0.28, 0.55, 0.28), top, side)
		_box(st, Vector3(-0.15, 0.55, -0.15), Vector3(0.15, 1.12, 0.15), top, side)
	else:
		_box(st, Vector3(-0.30, 0.14, -0.30), Vector3(0.30, 0.40, 0.30), top, side)
		_box(st, Vector3(-0.22, 0.40, -0.22), Vector3(0.22, 0.66, 0.22), top, side)
		_box(st, Vector3(-0.14, 0.66, -0.14), Vector3(0.14, 0.92, 0.14), top, side)
		_box(st, Vector3(-0.06, 0.92, -0.06), Vector3(0.06, 1.14, 0.06), top, side)
	return st.commit()

## Mediterranean cypress: a slim voxel column.
static func cypress(low := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Color(0.25, 0.47, 0.26)
	var side := Color(0.21, 0.41, 0.22)
	_box(st, Vector3(-0.03, 0, -0.03), Vector3(0.03, 0.1, 0.03), Color(0.36, 0.25, 0.16), Color(0.36, 0.25, 0.16), false)
	_box(st, Vector3(-0.12, 0.08, -0.12), Vector3(0.12, 0.98, 0.12), top, side)
	if not low:
		_box(st, Vector3(-0.07, 0.98, -0.07), Vector3(0.07, 1.16, 0.07), top, side)
	return st.commit()

## Stone pine (Pinus pinea), the Roman umbrella pine: a flat voxel parasol on a
## tall bare trunk.
static func umbrella_pine(low := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Color(0.29, 0.52, 0.26)
	var side := Color(0.23, 0.43, 0.21)
	_box(st, Vector3(-0.04, 0, -0.04), Vector3(0.04, 0.86, 0.04), Color(0.45, 0.30, 0.20), Color(0.45, 0.30, 0.20), false)
	_box(st, Vector3(-0.44, 0.82, -0.40), Vector3(0.44, 0.98, 0.40), top, side)
	if not low:
		_box(st, Vector3(-0.26, 0.98, -0.24), Vector3(0.24, 1.06, 0.26), top.lightened(0.05), side)
	return st.commit()

## A flat quad on a wall (window, door), a hair in front of it.
static func _pane(st: SurfaceTool, centre: Vector3, n: Vector3, w: float, h: float, colour: Color) -> void:
	var t := Vector3(-n.z, 0, n.x) * (w * 0.5)
	var up := Vector3(0, h * 0.5, 0)
	var c := centre + n * 0.004
	var q := [c - t - up, c + t - up, c + t + up, c - t + up]
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var d: Vector3 = q[3]
	if (b - a).cross(q[2] - a).dot(n) > 0.0:
		var x: Vector3 = b; b = d; d = x
	for v in [a, b, q[2], a, q[2], d]:
		st.set_color(colour); st.set_normal(n); st.add_vertex(v)

## Town house after Urbek: 10 x 8.5 m, two storeys of cream plaster with
## windows and a door, under a stepped terracotta roof (voxel layers, a third
## of the height). 1 unit = HOUSE_M. The plaster has alpha 0.5, so
## tile_props.gdshader can give every house its own plaster tone.
static func house() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Color(0.95, 0.87, 0.72, 0.5)
	var roof := Color(0.72, 0.32, 0.21)
	var window := Color(0.28, 0.27, 0.30)
	var door := Color(0.45, 0.30, 0.20)
	var hx := 0.5
	var hz := 0.42
	var h := 0.6
	_box(st, Vector3(-hx, 0, -hz), Vector3(hx, h, hz), wall, wall)
	# windows: three per floor on the long sides, one on the short ones; a door
	# in the middle of the south side
	for floor_y in [0.18, 0.44]:
		for x in [-0.3, 0.0, 0.3]:
			if floor_y < 0.3 and x == 0.0:
				_pane(st, Vector3(0, 0.12, hz), Vector3.BACK, 0.1, 0.24, door)
			else:
				_pane(st, Vector3(x, floor_y, hz), Vector3.BACK, 0.09, 0.11, window)
			_pane(st, Vector3(x, floor_y, -hz), Vector3.FORWARD, 0.09, 0.11, window)
		_pane(st, Vector3(hx, floor_y, 0), Vector3.RIGHT, 0.09, 0.11, window)
		_pane(st, Vector3(-hx, floor_y, 0), Vector3.LEFT, 0.09, 0.11, window)
	# roof: eaves, then layers stepping in towards the ridge; the risers a
	# little lighter than the treads, so the steps do not stripe the town
	var layers := [[0.48, 0.07], [0.36, 0.07], [0.24, 0.07], [0.12, 0.06]]
	var y := h
	for k in layers.size():
		var half_z: float = layers[k][0]
		var dy: float = layers[k][1]
		_box(st, Vector3(-hx - 0.04, y, -half_z), Vector3(hx + 0.04, y + dy, half_z), roof, roof.lightened(0.08))
		y += dy
	return st.commit()

# ------------------------------------------------------------ landmarks
# Rome's great buildings after Urbek and Caesar III: voxel blocks in
# travertine, marble and terracotta. 1 unit = 1 m of the building (the
# terrain scales them, see tile_terrain.gd LANDMARK_SCALE).

## The landmark mesh by name (tile_terrain.gd LANDMARKS).
static func landmark(which: String) -> ArrayMesh:
	match which:
		"colosseum": return colosseum()
		"circus": return circus()
		"forum": return forum()
		"temple": return temple()
		"pantheon": return pantheon()
	return null

## A flat quad with outward normal n (winding fixed for Godot).
static func _quad(st: SurfaceTool, q: Array, n: Vector3, colour: Color) -> void:
	var a: Vector3 = q[0]
	var b: Vector3 = q[1]
	var c: Vector3 = q[2]
	var d: Vector3 = q[3]
	if (b - a).cross(c - a).dot(n) > 0.0:
		var x := b; b = d; d = x
	for v in [a, b, c, a, c, d]:
		st.set_color(colour); st.set_normal(n); st.add_vertex(v)

## A block turned to the tangent t (horizontal, unit) with outward normal n:
## half length hx along t, half depth hz along n, from y0 to y1.
static func _obox(st: SurfaceTool, centre: Vector3, t: Vector3, n: Vector3, hx: float, hz: float, y0: float, y1: float, top: Color, side: Color) -> void:
	var c := []
	for k in 8:
		var sx := -1.0 if (k & 1) == 0 else 1.0
		var sz := -1.0 if (k & 2) == 0 else 1.0
		var y := y0 if k < 4 else y1
		c.append(centre + t * (sx * hx) + n * (sz * hz) + Vector3(0, y, 0))
	_quad(st, [c[4], c[5], c[7], c[6]], Vector3.UP, top)
	_quad(st, [c[2], c[3], c[7], c[6]], n, side)
	_quad(st, [c[0], c[1], c[5], c[4]], -n, side)
	_quad(st, [c[1], c[3], c[7], c[5]], t, side)
	_quad(st, [c[0], c[2], c[6], c[4]], -t, side)

## An n-sided prism around centre (radius r, from y0 to y1) with its top.
static func _prism(st: SurfaceTool, centre: Vector3, r: float, y0: float, y1: float, sides: int, top: Color, side: Color) -> void:
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := centre + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := centre + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		_quad(st, [p0 + Vector3(0, y0, 0), p1 + Vector3(0, y0, 0), p1 + Vector3(0, y1, 0), p0 + Vector3(0, y1, 0)], n, side)
		var cy := centre + Vector3(0, y1, 0)
		var tri := [cy, p0 + Vector3(0, y1, 0), p1 + Vector3(0, y1, 0)]
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(Vector3.UP) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for v in tri:
			st.set_color(top); st.set_normal(Vector3.UP); st.add_vertex(v)

## Point and outward normal on an ellipse (half axes a along x, b along z).
static func _ellipse(a: float, b: float, angle: float) -> Array:
	var p := Vector3(a * cos(angle), 0, b * sin(angle))
	var n := Vector3(cos(angle) / a, 0, sin(angle) / b).normalized()
	return [p, n]

## The Colosseum (188 x 156 m, 48 m): three storeys of arches with cornices
## and the attic outside; stepped seating down to the sand of the arena.
static func colosseum() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.86, 0.80, 0.68)
	var cornice := Color(0.93, 0.88, 0.78)
	var arch := Color(0.30, 0.27, 0.25)
	var sand := Color(0.86, 0.75, 0.53)
	var seats := [Color(0.80, 0.74, 0.63), Color(0.72, 0.66, 0.57), Color(0.80, 0.74, 0.63)]
	var a := 94.0
	var b := 78.0
	var n := 32
	for k in n:
		var e0: Array = _ellipse(a, b, TAU * k / n)
		var e1: Array = _ellipse(a, b, TAU * (k + 1) / n)
		var p0: Vector3 = e0[0]
		var p1: Vector3 = e1[0]
		var mid := (p0 + p1) * 0.5
		var t := (p1 - p0).normalized()
		var nn := (e0[1] + e1[1]).normalized() as Vector3
		var half := (p1 - p0).length() * 0.5 + 0.3
		_obox(st, mid - nn * 3.0, t, nn, half, 3.0, 0.0, 48.0, stone, stone)
		for y in [13.0, 25.0, 37.0]:
			_obox(st, mid + nn * 0.5, t, nn, half, 0.7, y, y + 1.6, cornice, cornice)
		for y in [7.5, 19.5, 31.0]:
			_pane(st, mid + Vector3(0, y, 0), nn, half * 1.1, 8.0, arch)
		_pane(st, mid + Vector3(0, 43.0, 0), nn, half * 0.4, 2.5, arch)
	# seating: three tiers stepping down to the arena wall, then the sand
	var tiers := [[0.94, 0.78, 40.0], [0.78, 0.63, 30.0], [0.63, 0.50, 19.0]]
	for i in tiers.size():
		var s0: float = tiers[i][0]
		var s1: float = tiers[i][1]
		var h: float = tiers[i][2]
		var below: float = tiers[i + 1][2] if i + 1 < tiers.size() else 2.0
		for k in n:
			var o0: Vector3 = _ellipse(a * s0, b * s0, TAU * k / n)[0]
			var o1: Vector3 = _ellipse(a * s0, b * s0, TAU * (k + 1) / n)[0]
			var i0: Vector3 = _ellipse(a * s1, b * s1, TAU * k / n)[0]
			var i1: Vector3 = _ellipse(a * s1, b * s1, TAU * (k + 1) / n)[0]
			var up := Vector3(0, h, 0)
			_quad(st, [o0 + up, o1 + up, i1 + up, i0 + up], Vector3.UP, seats[i] if k % 4 != 0 else arch)
			var inward := -((_ellipse(a, b, TAU * (k + 0.5) / n)[1]) as Vector3)
			_quad(st, [i0 + Vector3(0, below, 0), i1 + Vector3(0, below, 0), i1 + up, i0 + up], inward, stone)
	for k in n:
		var q0: Vector3 = _ellipse(a * 0.5, b * 0.5, TAU * k / n)[0]
		var q1: Vector3 = _ellipse(a * 0.5, b * 0.5, TAU * (k + 1) / n)[0]
		var tri := [Vector3(0, 2, 0), q0 + Vector3(0, 2, 0), q1 + Vector3(0, 2, 0)]
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(Vector3.UP) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for v in tri:
			st.set_color(sand); st.set_normal(Vector3.UP); st.add_vertex(v)
	return st.commit()

## The Circus Maximus, shortened for the map (330 x 100 m): stepped stands
## with arches on the long sides and around the curve in the east, the
## starting gates in the west, the spina with its obelisk on the sand.
static func circus() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.86, 0.80, 0.68)
	var seat := Color(0.80, 0.74, 0.63)
	var seat_low := Color(0.72, 0.66, 0.57)
	var arch := Color(0.30, 0.27, 0.25)
	var sand := Color(0.86, 0.75, 0.53)
	var roof := Color(0.72, 0.32, 0.21)
	_box(st, Vector3(-150, 0, -32), Vector3(115, 1.0, 32), sand, sand)
	for z in [-1.0, 1.0]:
		# outer stands high, inner low, the arches on the outer wall
		_box(st, Vector3(-150, 0, minf(40.0 * z, 50.0 * z)), Vector3(115, 20, maxf(40.0 * z, 50.0 * z)), seat, stone)
		_box(st, Vector3(-150, 0, minf(32.0 * z, 40.0 * z)), Vector3(115, 11, maxf(32.0 * z, 40.0 * z)), seat_low, stone)
		for x in range(-140, 111, 12):
			_pane(st, Vector3(x, 7, 50.0 * z), Vector3(0, 0, z), 6.0, 8.0, arch)
			_pane(st, Vector3(x, 15.5, 50.0 * z), Vector3(0, 0, z), 6.0, 4.0, arch)
	for k in 12:
		var a0 := -PI * 0.5 + PI * k / 12.0
		var a1 := -PI * 0.5 + PI * (k + 1) / 12.0
		var am := (a0 + a1) * 0.5
		var nn := Vector3(cos(am), 0, sin(am))
		var t := Vector3(-sin(am), 0, cos(am))
		var centre := Vector3(115, 0, 0)
		_obox(st, centre + nn * 45.0, t, nn, 50.0 * PI / 24.0 + 0.8, 5.0, 0.0, 20.0, seat, stone)
		_obox(st, centre + nn * 36.0, t, nn, 40.0 * PI / 24.0 + 0.8, 4.0, 0.0, 11.0, seat_low, stone)
		_pane(st, centre + nn * 50.0 + Vector3(0, 7, 0), nn, 6.0, 8.0, arch)
		var q0 := centre + Vector3(cos(a0), 0, sin(a0)) * 32.0
		var q1 := centre + Vector3(cos(a1), 0, sin(a1)) * 32.0
		var tri := [centre + Vector3(0, 1, 0), q0 + Vector3(0, 1, 0), q1 + Vector3(0, 1, 0)]
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(Vector3.UP) > 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for v in tri:
			st.set_color(sand); st.set_normal(Vector3.UP); st.add_vertex(v)
	# the carceres: a row of gates under a terracotta roof
	_box(st, Vector3(-165, 0, -50), Vector3(-150, 16, 50), stone, stone)
	for w in [[0.0, 7.5], [2.5, 5.0]]:
		_box(st, Vector3(-165 + w[0], 16 + w[0], -50 + w[0]), Vector3(-150 - w[0], 16 + w[0] + 2.5, 50 - w[0]), roof, roof.lightened(0.08))
	for z in range(-40, 41, 10):
		_pane(st, Vector3(-150, 6, z), Vector3.RIGHT, 6.0, 9.0, arch)
	_pane(st, Vector3(-157.5, 8, 50), Vector3.BACK, 10.0, 10.0, arch)
	# the spina down the middle, the obelisk of Augustus and the turning posts
	_box(st, Vector3(-95, 1, -3), Vector3(80, 4, 3), stone, stone)
	# the obelisk: red granite on a pedestal, tapering to a pyramid tip
	var granite := Color(0.74, 0.58, 0.49)
	var granite_side := Color(0.66, 0.50, 0.42)
	_box(st, Vector3(-12, 4, -4), Vector3(-4, 9, 4), stone, stone)
	_box(st, Vector3(-10.5, 9, -2.5), Vector3(-5.5, 32, 2.5), granite, granite_side)
	_box(st, Vector3(-9.8, 32, -1.8), Vector3(-6.2, 40, 1.8), granite, granite_side)
	_box(st, Vector3(-8.8, 40, -0.8), Vector3(-7.2, 43, 0.8), Color(0.88, 0.74, 0.40), Color(0.78, 0.64, 0.34))
	# the turning posts: three gilded cones on a half-round base at each end
	var gold := Color(0.88, 0.74, 0.40)
	var gold_side := Color(0.78, 0.64, 0.34)
	for x in [-99.0, 84.0]:
		_box(st, Vector3(x - 4, 1, -4), Vector3(x + 4, 4, 4), stone, stone)
		for z in [-2.4, 0.0, 2.4]:
			_prism(st, Vector3(x, 0, z), 1.2, 4.0, 11.0, 6, gold, gold_side)
			_prism(st, Vector3(x, 0, z), 0.6, 11.0, 13.5, 6, gold, gold_side)
	return st.commit()

## The Forum Romanum on one city tile (84 x 84 m): travertine paving, the
## Basilica Julia along the south, a temple in the east, the round temple of
## Vesta, the brick Curia and a row of honorary columns.
static func forum() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var paving := Color(0.91, 0.88, 0.81)
	var stone := Color(0.86, 0.80, 0.68)
	var marble := Color(0.93, 0.91, 0.86)
	var brick := Color(0.72, 0.50, 0.38)
	var roof := Color(0.72, 0.32, 0.21)
	var arch := Color(0.30, 0.27, 0.25)
	_box(st, Vector3(-42, 0, -42), Vector3(42, 0.8, 42), paving, stone)
	# Basilica Julia: two storeys of arches under a low roof
	_box(st, Vector3(-38, 0.8, 18), Vector3(14, 13, 36), stone, stone)
	for x in range(-34, 13, 6):
		_pane(st, Vector3(x, 4.5, 36), Vector3.BACK, 3.6, 6.0, arch)
		_pane(st, Vector3(x, 10.0, 36), Vector3.BACK, 3.6, 4.0, arch)
	_box(st, Vector3(-39, 13, 17), Vector3(15, 14.5, 37), roof, roof.lightened(0.08))
	_box(st, Vector3(-36, 14.5, 20), Vector3(12, 16, 34), roof, roof.lightened(0.08))
	# its colonnade along the square
	for x in range(-36, 15, 5):
		_box(st, Vector3(x - 0.8, 0.8, 14.5), Vector3(x + 0.8, 12, 16.1), marble, marble)
	_box(st, Vector3(-38, 12, 14), Vector3(14, 13.2, 18), marble, marble)
	# a temple in the east (Castor and Pollux), facing the square
	_box(st, Vector3(22, 0.8, -6), Vector3(38, 6, 26), stone, stone)
	_box(st, Vector3(24, 6, -4), Vector3(36, 17, 12), marble, marble)
	for x in [24.5, 28.5, 31.5, 35.5]:
		_box(st, Vector3(x - 1, 6, 21), Vector3(x + 1, 17, 23), marble, marble)
	for w in [[0.0, 2.0], [3.0, 2.0], [5.5, 1.5]]:
		_box(st, Vector3(23 + w[0], 17 + w[0] * 0.66, -5), Vector3(37 - w[0], 17 + w[0] * 0.66 + w[1], 24), roof, roof.lightened(0.08))
	# the round temple of Vesta: a ring of columns around the cella
	var vesta := Vector3(-10, 0, -22)
	_prism(st, vesta, 7.5, 0.8, 2.5, 12, stone, stone)
	_prism(st, vesta, 4.2, 2.5, 9.0, 12, Color(0.80, 0.76, 0.68), Color(0.80, 0.76, 0.68))
	for k in 10:
		var a := TAU * k / 10.0
		var q := vesta + Vector3(cos(a), 0, sin(a)) * 6.3
		_box(st, q + Vector3(-0.6, 2.5, -0.6), q + Vector3(0.6, 9.0, 0.6), marble, marble)
	_prism(st, vesta, 7.3, 9.0, 10.2, 12, roof, roof.lightened(0.08))
	_prism(st, vesta, 4.0, 10.2, 11.8, 12, roof, roof.lightened(0.08))
	# the Curia, tall brick with a terracotta roof
	_box(st, Vector3(-38, 0.8, -38), Vector3(-24, 18, -22), brick, brick)
	_pane(st, Vector3(-31, 6, -22), Vector3.BACK, 4.0, 7.0, arch)
	_box(st, Vector3(-39, 18, -39), Vector3(-23, 20, -21), roof, roof.lightened(0.08))
	_box(st, Vector3(-35, 20, -39), Vector3(-27, 21.5, -21), roof, roof.lightened(0.08))
	# honorary columns along the square
	for x in range(-18, 16, 8):
		_box(st, Vector3(x - 1.2, 0.8, 2), Vector3(x + 1.2, 15, 4.4), marble, marble)
	return st.commit()

## The temple of Jupiter on the Capitol (60 x 54 m): a high podium with
## stairs in the south, six columns across the front, the cella behind them
## and a terracotta roof in voxel steps.
static func temple() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var marble := Color(0.95, 0.93, 0.88)
	var stone := Color(0.87, 0.83, 0.73)
	var roof := Color(0.72, 0.32, 0.21)
	var shadow := Color(0.40, 0.37, 0.34)
	_box(st, Vector3(-27, 0, -30), Vector3(27, 8, 24), stone, stone)
	for k in 3:
		_box(st, Vector3(-14, 0, 24), Vector3(14, 6.0 - 2.0 * k, 26.0 + 2.0 * k + 2.0), stone, stone)
	_box(st, Vector3(-20, 8, -26), Vector3(20, 30, 2), marble, marble)
	# the shaded porch behind the columns, so they read one by one
	_pane(st, Vector3(0, 18, 2), Vector3.BACK, 40, 20, shadow)
	for k in 6:
		var x := -20.0 + 8.0 * k
		for z in [9.0, 18.0]:
			_box(st, Vector3(x - 1.4, 8, z - 1.4), Vector3(x + 1.4, 28, z + 1.4), marble, marble)
	# architrave, then the stepped roof with a white gable at the front
	_box(st, Vector3(-22, 28, -27), Vector3(22, 30, 20), marble, marble)
	var layers := [[24.0, 2.5], [17.0, 2.5], [10.0, 2.5], [4.0, 2.0]]
	var y := 30.0
	for layer in layers:
		_box(st, Vector3(-layer[0], y, -28), Vector3(layer[0], y + layer[1], 19), roof, roof.lightened(0.08))
		_box(st, Vector3(-layer[0], y, 19), Vector3(layer[0], y + layer[1], 21), marble, marble)
		y += layer[1]
	return st.commit()

## The Pantheon (rotunda 44 m across under a stepped dome, portico in the
## north with eight columns).
static func pantheon() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.84, 0.78, 0.67)
	var dome := Color(0.66, 0.64, 0.61)
	var marble := Color(0.93, 0.91, 0.86)
	var roof := Color(0.72, 0.32, 0.21)
	_prism(st, Vector3.ZERO, 24.0, 0.0, 30.0, 20, stone, stone)
	var rings := [[22.0, 30.0, 34.0], [18.0, 34.0, 38.0], [13.0, 38.0, 41.0], [7.0, 41.0, 43.0]]
	for r in rings:
		_prism(st, Vector3.ZERO, r[0], r[1], r[2], 20, dome, dome.darkened(0.08))
	_box(st, Vector3(-17, 0, -40), Vector3(17, 3, -20), stone, stone)
	_box(st, Vector3(-14, 3, -30), Vector3(14, 22, -20), stone, stone)
	for k in 8:
		var x := -14.0 + 4.0 * k
		_box(st, Vector3(x - 1.0, 3, -39), Vector3(x + 1.0, 19, -37), marble, marble)
	var y := 19.0
	for w in [17.0, 12.0, 7.0, 2.5]:
		_box(st, Vector3(-w, y, -40), Vector3(w, y + 2.0, -20), roof, roof.lightened(0.08))
		y += 2.0
	return st.commit()
