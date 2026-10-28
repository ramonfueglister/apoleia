extends RefCounted
## Voxel meshing in the style of Urbek City Builder, the same rules as the
## colosseum prototype (prototypes/colosseum/colosseum_mesh.gd): a model is a
## solid sampled on a grid of cubes, only exposed faces are meshed, faces of
## one colour merge where the baked corner shading (voxel ambient occlusion
## in the vertex colours) allows it exactly, and downward faces are left out
## (the camera never looks up). One material, no textures.
##
## A model is a Callable `sample(p: Vector3) -> int` in metres (x right, y
## up, z towards the viewer) that returns a palette index, 0 for empty.
## Coarser levels of detail take the weighted majority of fine subsamples,
## so thin details turn into a block of their colour instead of vanishing.

# Corner occlusion: 0 = both sides blocked, 3 = open.
const AO := [0.55, 0.72, 0.87, 1.0]

## Samples `model` on a grid of cubes of edge `v` metres over the box from
## `lo` to `hi`. `fine` is the step of the subsamples for coarse grids
## (each layer up weighs double, so the visible top wins).
static func voxelize(model: Callable, lo: Vector3, hi: Vector3, v: float, fine: float, colours: int) -> Dictionary:
	var n := Vector3i(ceili((hi.x - lo.x) / v), ceili((hi.y - lo.y) / v), ceili((hi.z - lo.z) / v))
	var ss := maxi(1, roundi(v / fine))
	var f := v / ss
	var grid := PackedByteArray()
	grid.resize(n.x * n.y * n.z)
	var counts := PackedInt32Array()
	counts.resize(colours)
	for z in n.z:
		for y in n.y:
			for x in n.x:
				var c := 0
				if ss == 1:
					c = model.call(lo + Vector3(x + 0.5, y + 0.5, z + 0.5) * v)
				else:
					counts.fill(0)
					var solid := 0
					for sz in ss:
						for sy in ss:
							for sx in ss:
								var s: int = model.call(lo + Vector3(x * v + (sx + 0.5) * f, y * v + (sy + 0.5) * f, z * v + (sz + 0.5) * f))
								if s != 0:
									solid += 1
									counts[s] += 1 << sy
					if solid * 8 >= ss * ss * ss * 3:
						var best := 1
						for i in range(1, colours):
							if counts[i] > counts[best]:
								best = i
						c = best
				grid[x + n.x * (y + n.y * z)] = c
	return {"grid": grid, "n": n, "v": v, "lo": lo}

static func _at(vox: Dictionary, c: Vector3i) -> int:
	var n: Vector3i = vox.n
	if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= n.x or c.y >= n.y or c.z >= n.z:
		return 0
	return vox.grid[c.x + n.x * (c.y + n.y * c.z)]

## Exposed faces as merged quads: [corners in grid units, normal, palette
## index, corner occlusion (2 bits per corner)].
static func faces(vox: Dictionary) -> Array:
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
						if col != 0 and _at(vox, c + nv) == 0:
							var o := c + nv
							var ao := 0
							var corner := 0
							for s in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
								var s1 := int(_at(vox, o + eu * s.x) != 0)
								var s2 := int(_at(vox, o + ew * s.y) != 0)
								var cc := int(_at(vox, o + eu * s.x + ew * s.y) != 0)
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
						# exact where the occlusion does not change along the merge
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
						quads.append([corners, Vector3(nv), key & 0xFF, ao4])
						a += wide
	return quads

## Appends the quads to `st`: corners scaled from grid units to metres,
## then by `scale`, vertex colours from `palette` (sRGB) times the corner
## occlusion, UV.x = `part` (for shaders that move parts), UV.y the palette
## index (for shaders that recolour, e.g. walls per house).
static func emit(st: SurfaceTool, vox: Dictionary, quads: Array, palette: Array, scale: float, part := 0, tops := {}) -> void:
	var v: float = vox.v
	var lo: Vector3 = vox.lo
	for q in quads:
		var p: Array[Vector3] = []
		for g: Vector3 in q[0]:
			p.append((lo + g * v) * scale)
		var nv: Vector3 = q[1]
		var colour: Color = tops[q[2]] if nv.y > 0.5 and tops.has(q[2]) else palette[q[2]]
		var ao: Array[int] = []
		for k in 4:
			ao.append((q[3] >> (k * 2)) & 3)
		var normal := (p[1] - p[0]).cross(p[2] - p[0])
		if normal.dot(nv) < 0.0:
			p = [p[0], p[3], p[2], p[1]]
			ao = [ao[0], ao[3], ao[2], ao[1]]
		# grow each quad by a hair (1.2 cm) within its plane: merged quads
		# meet smaller neighbours at T-junctions, whose rasterisation leaves
		# pin-hole cracks (as prototypes/colosseum/colosseum_mesh.gd _emit)
		var centre := (p[0] + p[1] + p[2] + p[3]) * 0.25
		for k in 4:
			var dir := p[k] - centre
			if dir.length_squared() > 1e-12:
				p[k] += dir.normalized() * 0.012 * scale
		# Godot fronts are clockwise; the diagonal follows the occlusion so
		# corner shading does not streak across the quad.
		var order := [0, 2, 1, 0, 3, 2] if ao[0] + ao[2] >= ao[1] + ao[3] else [0, 3, 1, 1, 3, 2]
		for k in order:
			var f: float = AO[ao[k]]
			st.set_color(Color(colour.r * f, colour.g * f, colour.b * f))
			st.set_uv(Vector2(part, q[2]))
			st.set_normal(nv)
			st.add_vertex(p[k])

## One model as a mesh at voxel size `v`.
static func build(model: Callable, lo: Vector3, hi: Vector3, v: float, fine: float, palette: Array, scale := 1.0, tops := {}) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vox := voxelize(model, lo, hi, v, fine, palette.size())
	emit(st, vox, faces(vox), palette, scale, 0, tops)
	return st.commit()

static func triangles(mesh: ArrayMesh) -> int:
	return mesh.surface_get_array_len(0) / 3 if mesh.get_surface_count() > 0 else 0
