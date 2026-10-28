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
## of the height). 1 unit = HOUSE_M.
static func house() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := Color(0.93, 0.88, 0.77)
	var roof := Color(0.74, 0.37, 0.23)
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
	# roof: eaves, then layers stepping in towards the ridge
	var layers := [[0.48, 0.07], [0.36, 0.07], [0.24, 0.07], [0.12, 0.06]]
	var y := h
	for k in layers.size():
		var half_z: float = layers[k][0]
		var dy: float = layers[k][1]
		var shade := roof.darkened(0.04 * k)
		_box(st, Vector3(-hx - 0.04, y, -half_z), Vector3(hx + 0.04, y + dy, half_z), shade.lightened(0.05), shade)
		y += dy
	return st.commit()
