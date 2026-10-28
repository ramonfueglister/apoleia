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
	var top := Color(0.36, 0.62, 0.22)
	var side := Color(0.30, 0.54, 0.19)
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
	var top := Color(0.27, 0.50, 0.28)
	var side := Color(0.21, 0.42, 0.23)
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
	var top := Color(0.30, 0.52, 0.24)
	var side := Color(0.27, 0.49, 0.22)
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
	var top := Color(0.33, 0.54, 0.22)
	var side := Color(0.26, 0.46, 0.19)
	_box(st, Vector3(-0.04, 0, -0.04), Vector3(0.04, 0.86, 0.04), Color(0.45, 0.30, 0.20), Color(0.45, 0.30, 0.20), false)
	_box(st, Vector3(-0.44, 0.82, -0.40), Vector3(0.44, 0.98, 0.40), top, side)
	if not low:
		_box(st, Vector3(-0.26, 0.98, -0.24), Vector3(0.24, 1.06, 0.26), top.lightened(0.05), side)
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
