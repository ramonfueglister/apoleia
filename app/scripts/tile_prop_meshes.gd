extends RefCounted
## Procedural meshes of the tile terrain: the tile template (top and four
## walls, positioned by tile_terrain.gdshader) and low-poly trees and houses
## with vertex colours. Units: a prop is about 1 unit tall, origin on the ground.

static func tile_template() -> ArrayMesh:
	# VERTEX.x = part (0 top, 1..4 walls N, E, S, W), VERTEX.y = corner or role
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for part in 5:
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

static func _icosphere(subdivisions: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = []
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		v.append(p.normalized())
	var f: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4],
		[11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in subdivisions:
		var cache := {}
		var nf: Array = []
		for tri in f:
			var m: Array[int] = []
			for k in 3:
				var a: int = tri[k]
				var b: int = tri[(k + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not cache.has(key):
					cache[key] = v.size()
					v.append(((v[a] + v[b]) * 0.5).normalized())
				m.append(cache[key])
			nf.append([tri[0], m[0], m[2]])
			nf.append([tri[1], m[1], m[0]])
			nf.append([tri[2], m[2], m[1]])
			nf.append([m[0], m[1], m[2]])
		f = nf
	return [v, f]

## Faceted crown: an icosphere scaled to `radius`, every face flat with its own
## normal (Dorfromantik / Islanders style), dark below and light on top.
static func _crown(st: SurfaceTool, centre: Vector3, radius: Vector3, low: Color, high: Color, detail := 1) -> void:
	var ico := _icosphere(detail)
	var v: Array[Vector3] = ico[0]
	for tri in ico[1]:
		var p: Array[Vector3] = []
		for k in [0, 2, 1]:
			p.append(centre + v[tri[k]] * radius)
		var n := (p[1] - p[0]).cross(p[2] - p[0]).normalized()
		var mid := (p[0] + p[1] + p[2]) / 3.0
		var t := clampf((mid.y - (centre.y - radius.y)) / (2.0 * radius.y), 0.0, 1.0)
		var colour := low.lerp(high, t)
		for q in p:
			st.set_color(colour); st.set_normal(n); st.add_vertex(q)

## Faceted cone, flat sides.
static func _cone(st: SurfaceTool, base_y: float, top_y: float, radius: float, sides: int, low: Color, high: Color) -> void:
	var top := Vector3(0, top_y, 0)
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var p0 := Vector3(cos(a0) * radius, base_y, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, base_y, sin(a1) * radius)
		var n := (top - p0).cross(p1 - p0).normalized()
		if n.y < 0: n = -n
		var lit := low.lerp(high, 0.35 + 0.3 * float(s % 2))
		st.set_color(low); st.set_normal(n); st.add_vertex(p0)
		st.set_color(lit); st.set_normal(n); st.add_vertex(top)
		st.set_color(low); st.set_normal(n); st.add_vertex(p1)
		# underside, so the cone does not look hollow from steep cameras
		st.set_color(low.darkened(0.3)); st.set_normal(Vector3.DOWN); st.add_vertex(p0)
		st.set_normal(Vector3.DOWN); st.add_vertex(p1)
		st.set_normal(Vector3.DOWN); st.add_vertex(Vector3(0, base_y, 0))

static func _trunk(st: SurfaceTool, height: float, radius: float, colour: Color) -> void:
	var sides := 5
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var b0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var n := Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5))
		var up := Vector3(0, height, 0)
		for p in [b0, b0 + up, b1, b1, b0 + up, b1 + up]:
			st.set_color(colour); st.set_normal(n); st.add_vertex(p)

## Deciduous tree (oak, beech): one faceted crown on a short trunk.
static func broadleaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, 0.42, 0.05, Color(0.40, 0.28, 0.18))
	_crown(st, Vector3(0, 0.70, 0), Vector3(0.36, 0.32, 0.36), Color(0.20, 0.36, 0.15), Color(0.47, 0.64, 0.25))
	return st.commit()

## Conifer (fir, spruce): three stacked flat-sided cones.
static func conifer() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, 0.2, 0.04, Color(0.36, 0.25, 0.16))
	var low := Color(0.22, 0.42, 0.25)
	var high := Color(0.46, 0.68, 0.38)
	_cone(st, 0.14, 0.66, 0.30, 7, low, high)
	_cone(st, 0.42, 0.92, 0.23, 7, low, high)
	_cone(st, 0.68, 1.14, 0.15, 6, low, high)
	return st.commit()

## Mediterranean cypress: a slim faceted column.
static func cypress() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, 0.1, 0.03, Color(0.36, 0.25, 0.16))
	_crown(st, Vector3(0, 0.62, 0), Vector3(0.12, 0.54, 0.12), Color(0.14, 0.30, 0.15), Color(0.32, 0.50, 0.23), 0)
	return st.commit()

## Stone pine (Pinus pinea), the Roman umbrella pine: a flat parasol crown on a
## tall bare trunk.
static func umbrella_pine() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trunk(st, 0.82, 0.04, Color(0.45, 0.30, 0.20))
	_crown(st, Vector3(0, 0.92, 0), Vector3(0.46, 0.13, 0.46), Color(0.16, 0.32, 0.15), Color(0.40, 0.56, 0.24))
	return st.commit()

static func house() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Color(0.93, 0.88, 0.77)
	var roof := Color(0.74, 0.37, 0.23)
	var hx := 0.5
	var hz := 0.38
	var h := 0.42
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var n := (a + b).normalized()
		n = Vector3(signf(n.x) if absf(n.x) > absf(n.z) else 0.0, 0, signf(n.z) if absf(n.z) >= absf(n.x) else 0.0)
		var up := Vector3(0, h, 0)
		for p in [a, b, b + up, a, b + up, a + up]:
			st.set_color(wall); st.set_normal(n); st.add_vertex(p)
	# hip roof with eaves
	var e := 1.12
	var top_a := Vector3(-hx * 0.45, h + 0.3, 0)
	var top_b := Vector3(hx * 0.45, h + 0.3, 0)
	var r := [Vector3(-hx * e, h, -hz * e), Vector3(hx * e, h, -hz * e), Vector3(hx * e, h, hz * e), Vector3(-hx * e, h, hz * e)]
	var faces := [[r[0], r[1], top_b, top_a], [r[1], r[2], top_b], [r[2], r[3], top_a, top_b], [r[3], r[0], top_a]]
	for face in faces:
		var n: Vector3 = (face[1] - face[0]).cross(face[2] - face[0]).normalized()
		if n.y < 0: n = -n
		var tris := [[0, 1, 2]] if face.size() == 3 else [[0, 1, 2], [0, 2, 3]]
		for tri in tris:
			for k in tri:
				st.set_color(roof); st.set_normal(n); st.add_vertex(face[k])
	return st.commit()
