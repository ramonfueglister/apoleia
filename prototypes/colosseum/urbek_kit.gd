extends RefCounted
## Voxel kit in the craft of Urbek City Builder, for Caesar III's town.
## Urbek's own models (MagicaVoxel, Urbek modding guide) are 40 voxels to a
## lot, the first two layers ground. Here a lot is 10 m, so a voxel is
## 0.25 m and a storey 12 to 14 voxels: the scale of the farm houses
## (app/scripts/voxel/farmhouse.gd). Flat colours per part, tops in their
## own colour where the material has grain (tile treads), corner occlusion
## baked into the vertex colours, no textures. Models face +z (south,
## towards the game camera).

const V := 0.25
const LOT := 40
const GROUND := 2
const AO := [0.5, 0.66, 0.82, 1.0]

enum { EMPTY,
	CREAM, CREAM_W, OCHRE, OCHRE_W, PINK, PINK_W, WHITE, WHITE_W, REDWASH, REDWASH_W, BRICK, BRICK_W,
	TRIM, STONE, STONE_W, MARBLE, MARBLE_W, STEP,
	TILE, TILE_D, TILE_L, EAVE, RIDGE, TILE2, TILE2_D, TILE2_L, EAVE2, RIDGE2,
	TILEB, TILEB_D, TILEB_L, EAVEB, RIDGEB,
	GLASS, DARK, DOOR, DOOR_D, SHUTTER_G, SHUTTER_B, SHUTTER_U, WOOD, WOOD_D,
	CLOTH_R, CLOTH_W, CLOTH_B, CLOTH_G, CLOTH_Y, POT, AMPHORA, FRUIT_R, FRUIT_Y, FRUIT_G, BREAD,
	LEAF, LEAF_D, LEAF_L, CYPRESS, CYPRESS_D, PINE, PINE_D, TRUNK, FLOWER_R, FLOWER_P, FLOWER_Y, HEDGE,
	GRASS, GRASS_D, GRASS_L, EARTH, EARTH_D, PAVE, PAVE_D, PAVE_L, BASALT, BASALT_D, BASALT_L, CURB,
	WATER, BRONZE, GOLD, ROBE_W, ROBE_R, ROBE_B, SKIN, HAIR,
	TRAV, TRAV_W, TRAV_D, TRAV_L, VAULT, SEAT, SEAT_D, SAND, SAND_D, PODIUM, FLAG,
	TILE3, TILE3_D, TILE3_L, EAVE3, RIDGE3, TILE4, TILE4_D, TILE4_L, EAVE4, RIDGE4,
	LEAD, LEAD_D, LEAD_L, EAVEL, RIDGEL, SHUTTER_O, MULE, LINEN, VAULT_L,
	TILE5, TILE5_D, TILE5_L, EAVE5, RIDGE5, VERGE, ARCADE, DEEP,
	POMPEII, POMPEII_W, DOCHRE, DOCHRE_W, BRICKFACE, BRICKFACE_W, TIMBER, TIMBER_W, MORTAR, DADO,
	PAVE_J, BORDER, YARD, SEAT_HI, SEAT_MID, SEAT_WOOD, STATUE, STREAK, VIA_P, VIA_PD, WATER_D, SAIL,
	POOL, WATER_L, REED, REED_D, MUD, HELMET, SHIELD, MILL,
	MUD_D, SACK, SOIL, VINE, WOOL, PATH, FLOWER_W, COURSE, COURSE_J, SMOKE, LAVA,
	SMOKE_D, SMOKE_L, WET, ALGAE, GRAVEL, LETTER,
	FLOWER_M1, FLOWER_M2, FLOWER_M3, FLOWER_M4, BRONZE_D, PANEL, BLOSSOM_P, BLOSSOM_W, BLOSSOM_O, BOX,
	ROBE_N, ROBE_O, IRON,
	LIME, LIME_W, SOCLE_R, SOCLE_B, RUBBLE, RUBBLE_D, TUFF, TUFF_D, OLIVE, OLIVE_D, PLANE, BARK_L,
	GILT, GILT_D, GILT_L, EAVEG, RIDGEG, COCCIO, COCCIO_D, COCCIO_L, ANTEFIX, ROPE,
}

## Side colour, and the top colour where it differs (sRGB). Caesar III's
## warm plaster, terracotta and marble, at Urbek's brightness.
const COLOURS := {
	CREAM: ["ecdfc3"], CREAM_W: ["cdbd9c"], OCHRE: ["e9c98b"], OCHRE_W: ["c6a66a"],
	PINK: ["dcb49a"], PINK_W: ["c49e86"], WHITE: ["f2eee6"], WHITE_W: ["d0c9bc"],
	REDWASH: ["b9543e"], REDWASH_W: ["a54a37"], BRICK: ["bf6b4b"], BRICK_W: ["a95b3f"],
	TRIM: ["f3ede1"], STONE: ["cfc4ae"], STONE_W: ["bcb099"], MARBLE: ["efe6d6"], MARBLE_W: ["ddd2bf"],
	STEP: ["e2dacb", "ece5d7"],
	TILE: ["9d5536", "c46a44"], TILE_D: ["954d33", "b96140"], TILE_L: ["a45d3e", "cc7550"],
	EAVE: ["4a2e24", "c46a44"], RIDGE: ["8a4330", "a9573f"],
	TILE2: ["ad7253", "d88e68"], TILE2_D: ["a66b4d", "cf8661"], TILE2_L: ["b4785a", "e0976f"],
	EAVE2: ["5a3a2c", "d88e68"], RIDGE2: ["9a5e45", "bf7a58"],
	TILEB: ["3f5f8c", "5b80b0"], TILEB_D: ["37547d", "4f729f"], TILEB_L: ["4a6c99", "6a8fbd"],
	EAVEB: ["2f3d52", "5b80b0"], RIDGEB: ["33496b", "466892"],
	GLASS: ["3a4440"], DARK: ["4a3f38"], DOOR: ["7b5034"], DOOR_D: ["5d3b27"],
	SHUTTER_G: ["4f6a3b"], SHUTTER_B: ["7a4e2e"], SHUTTER_U: ["5e7c99"], WOOD: ["8a6040", "9c6e4a"], WOOD_D: ["5f4029"],
	CLOTH_R: ["b04a3c"], CLOTH_W: ["f1ebdf"], CLOTH_B: ["3f6ea6"], CLOTH_G: ["5c8c47"], CLOTH_Y: ["e3b24a"],
	POT: ["b3603f"], AMPHORA: ["8e4e2e", "b8693e"], FRUIT_R: ["d0402f"], FRUIT_Y: ["eec24a"], FRUIT_G: ["8cb84a"],
	BREAD: ["d6a35c"],
	LEAF: ["5e8538", "86a84e"], LEAF_D: ["4f7530", "769a45"], LEAF_L: ["6c9440", "93b65a"],
	CYPRESS: ["3d6233", "4b733c"], CYPRESS_D: ["324f2b", "3f6233"], PINE: ["557a34", "6e9a44"], PINE_D: ["466a2c", "5a8238"],
	TRUNK: ["6e4b33"], FLOWER_R: ["d8463a"], FLOWER_P: ["c45bb0"], FLOWER_Y: ["f0c64a"], HEDGE: ["4f8037", "5f923f"],
	GRASS: ["648f40", "6fa048"], GRASS_D: ["557f36", "5e8f3c"], GRASS_L: ["76a24b", "84b556"],
	EARTH: ["b59263", "c49f6e"], EARTH_D: ["a5845a", "b38f63"],
	PAVE: ["d2c6ae", "ddd2bb"], PAVE_D: ["cbbfa7", "d6cab3"], PAVE_L: ["d8cdb6", "e3d8c3"],
	BASALT: ["5a5c62", "64666c"], BASALT_D: ["50525a", "5a5c62"], BASALT_L: ["63656b", "6e7076"],
	CURB: ["b9ad97", "c6bba5"],
	WATER: ["4a87a8", "4f8faf"], BRONZE: ["9c7438"], GOLD: ["dcae4c", "e8bf5c"],
	ROBE_W: ["e8e0d0"], ROBE_R: ["a8443a"], ROBE_B: ["5a6a80"], SKIN: ["d9a27a"], HAIR: ["4a3326"],
	TRAV: ["e2d3b5", "ebdec3"], TRAV_W: ["d3c3a2", "ddcfb1"], TRAV_D: ["c6b392", "d1c0a0"], TRAV_L: ["efe6d2", "f5eedd"],
	VAULT: ["585a6a", "6a6b78"], SEAT: ["bfae8f", "dccfb2"], SEAT_D: ["ad9b7c", "c9ba9a"],
	SAND: ["d6b179", "e0bd84"], SAND_D: ["c8a26b", "d2ad75"], PODIUM: ["ece4d3", "f3ecde"], FLAG: ["c0392b"],
	TILE3: ["874030", "a9503a"], TILE3_D: ["80392b", "a04a35"], TILE3_L: ["8e4634", "b2573f"], EAVE3: ["3e2620", "a9503a"], RIDGE3: ["773528", "924535"],
	TILE4: ["704839", "8c5a47"], TILE4_D: ["6a4436", "845443"], TILE4_L: ["764c3c", "94604c"], EAVE4: ["3e2a22", "8c5a47"], RIDGE4: ["62402f", "7a4e3d"],
	LEAD: ["5f6672", "7d8592"], LEAD_D: ["59606b", "757d8a"], LEAD_L: ["666d79", "858d9a"], EAVEL: ["3b4048", "7d8592"], RIDGEL: ["505762", "6a717d"],
	SHUTTER_O: ["a08c5e"], MULE: ["7a6656"], LINEN: ["f4efe4"], VAULT_L: ["6e6f7c", "7d7e8a"],
	TILE5: ["7d6f66", "9c8b80"], TILE5_D: ["766960", "948377"], TILE5_L: ["84766c", "a69488"], EAVE5: ["4a3e36", "9c8b80"], RIDGE5: ["6e625a", "877a70"],
	VERGE: ["7e3a2a", "9a4a35"], ARCADE: ["9a8e7e", "a99d8c"], DEEP: ["2e2824"],
	POMPEII: ["a4433a"], POMPEII_W: ["8f3a32"], DOCHRE: ["c99542"], DOCHRE_W: ["b3843a"],
	BRICKFACE: ["a65a40"], BRICKFACE_W: ["924f38"], TIMBER: ["6e4c34"], TIMBER_W: ["5e412d"],
	MORTAR: ["c4b49b"], DADO: ["8c2e22"],
	PAVE_J: ["c2b69e", "cbbfa7"], BORDER: ["a99c84", "b5a88f"], YARD: ["cdb98f", "d8c49a"],
	SEAT_HI: ["d3ccbf", "e6dfd2"], SEAT_MID: ["b9ad99", "cfc3ae"], SEAT_WOOD: ["7a6853", "8e7a62"],
	STATUE: ["e6dccb", "efe7d8"], STREAK: ["a99d88"], VIA_P: ["bfb19a", "cdbfa6"], VIA_PD: ["b8aa92", "c4b69d"],
	WATER_D: ["477fa4", "4a85a6"], SAIL: ["eee6d4"],
	POOL: ["5f9fc8", "6fb0d8"], WATER_L: ["5a97b8", "62a0c0"], REED: ["8e9a4e", "8e9a4e"], REED_D: ["a9a15e", "a9a15e"],
	MUD: ["6e5a48", "7a6450"], HELMET: ["c9c9c4"], SHIELD: ["a8392e"], MILL: ["8c8880", "9a968e"],
	MUD_D: ["52443a", "5a4a3e"], SACK: ["b8a47c", "c8b48a"], SOIL: ["6e5a48", "7a6450"], VINE: ["5a7f34", "6c9440"],
	WOOL: ["e8e2d4", "f2ede2"], PATH: ["a89272", "b8a07a"], FLOWER_W: ["f2f2f2"],
	COURSE: ["a89a84", "b6a890"], COURSE_J: ["968872", "a4967e"], SMOKE: ["aaa69f", "b4b0a9"], LAVA: ["4a4644", "56524f"],
	SMOKE_D: ["8e8a84", "96928b"], SMOKE_L: ["c9c5bd", "d3cfc8"], WET: ["6a6658"], ALGAE: ["5e6e44"],
	GRAVEL: ["c7bca6", "cfc3a8"], LETTER: ["a8392e"],
	FLOWER_M1: ["b8504a"], FLOWER_M2: ["8e6aa0"], FLOWER_M3: ["e6ded0"], FLOWER_M4: ["c9a84a"],
	BRONZE_D: ["6e5a3a", "7c6744"], PANEL: ["3a3530"], BLOSSOM_P: ["c07890", "e7a0b4"], BLOSSOM_W: ["d8ccd0", "efe6ea"],
	BLOSSOM_O: ["b85f28", "d9772e"], BOX: ["44702e", "4e7a34"],
	ROBE_N: ["8a6e52"], ROBE_O: ["c49a52"], IRON: ["34302c"],
	LIME: ["e6dcc6"], LIME_W: ["d0c4aa"], SOCLE_R: ["8c2e22"], SOCLE_B: ["2e2a28"],
	RUBBLE: ["a29a8c", "aca496"], RUBBLE_D: ["8c8478", "968e82"], TUFF: ["c2a77c", "cdb388"], TUFF_D: ["a98f66", "b39a70"],
	OLIVE: ["7e8c66", "93a07a"], OLIVE_D: ["66724f", "77845e"], PLANE: ["5a8a3a", "6e9e46"], BARK_L: ["b8ab8c"],
	GILT: ["b8913c", "d9b45a"], GILT_D: ["a8822f", "c9a24a"], GILT_L: ["c49d48", "e3c06a"], EAVEG: ["7a5e2a", "d9b45a"], RIDGEG: ["9c7a34", "c49d48"],
	COCCIO: ["c9a490", "dbb8a2"], COCCIO_D: ["b8937f", "cba792"], COCCIO_L: ["d4b09c", "e3c3ae"], ANTEFIX: ["c46a44", "d47a52"], ROPE: ["5a4632"],
}

static var _side := PackedColorArray()
static var _top := PackedColorArray()

static func _colours() -> void:
	if not _side.is_empty():
		return
	_side.resize(256)
	_top.resize(256)
	for k: int in COLOURS:
		var c: Array = COLOURS[k]
		_side[k] = Color(c[0])
		_top[k] = Color(c[1] if c.size() > 1 else c[0])

## A deterministic hash, 0..65535.
static func rnd(x: int, y: int, z: int, s: int) -> int:
	var h := x * 374761393 + y * 668265263 + z * 1442695041 + s * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0xffff

static func chance(x: int, y: int, z: int, s: int, percent: int) -> bool:
	return rnd(x, y, z, s) % 100 < percent

## A box of voxels with drawing operations; x right, y up, z towards the
## viewer.
class Grid:
	var n: Vector3i
	var g := PackedByteArray()

	func _init(size: Vector3i) -> void:
		n = size
		g.resize(n.x * n.y * n.z)

	func at(x: int, y: int, z: int) -> int:
		if x < 0 or y < 0 or z < 0 or x >= n.x or y >= n.y or z >= n.z:
			return 0
		return g[x + n.x * (y + n.y * z)]

	func put(x: int, y: int, z: int, c: int) -> void:
		if x >= 0 and y >= 0 and z >= 0 and x < n.x and y < n.y and z < n.z:
			g[x + n.x * (y + n.y * z)] = c

	## Fills [x0, x1) x [y0, y1) x [z0, z1), clipped to the grid.
	func box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, c: int) -> void:
		for z in range(maxi(z0, 0), mini(z1, n.z)):
			for y in range(maxi(y0, 0), mini(y1, n.y)):
				var row := n.x * (y + n.y * z)
				for x in range(maxi(x0, 0), mini(x1, n.x)):
					g[row + x] = c

	## Recolours the solid voxels of a box.
	func paint(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, c: int) -> void:
		for z in range(maxi(z0, 0), mini(z1, n.z)):
			for y in range(maxi(y0, 0), mini(y1, n.y)):
				var row := n.x * (y + n.y * z)
				for x in range(maxi(x0, 0), mini(x1, n.x)):
					if g[row + x] != 0:
						g[row + x] = c

	## Fills only the empty voxels of a box.
	func add(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, c: int) -> void:
		for z in range(maxi(z0, 0), mini(z1, n.z)):
			for y in range(maxi(y0, 0), mini(y1, n.y)):
				var row := n.x * (y + n.y * z)
				for x in range(maxi(x0, 0), mini(x1, n.x)):
					if g[row + x] == 0:
						g[row + x] = c

	## Recolours voxels of colour `from` in a box.
	func swap(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, from: int, c: int) -> void:
		for z in range(maxi(z0, 0), mini(z1, n.z)):
			for y in range(maxi(y0, 0), mini(y1, n.y)):
				var row := n.x * (y + n.y * z)
				for x in range(maxi(x0, 0), mini(x1, n.x)):
					if g[row + x] == from:
						g[row + x] = c

	## Top solid voxel of a column, -1 if none.
	func top(x: int, z: int) -> int:
		for y in range(n.y - 1, -1, -1):
			if at(x, y, z) != 0:
				return y
		return -1

## Meshes the exposed faces of a grid (none facing down: the game camera
## never looks up). Faces of one colour merge where their corner occlusion
## allows it exactly. `lo` is the grid's corner in metres.
static func mesh(g: Grid, lo: Vector3, v := V) -> ArrayMesh:
	_colours()
	var n := g.n
	var px := n.x + 2
	var py := n.y + 2
	var occ := PackedByteArray()
	occ.resize(px * py * (n.z + 2))
	for z in n.z:
		for y in n.y:
			var src := n.x * (y + n.y * z)
			var dst := 1 + px * ((y + 1) + py * (z + 1))
			for x in n.x:
				occ[dst + x] = g.g[src + x]
	var strides: Array[int] = [1, px, px * py]
	var dims: Array[int] = [n.x, n.y, n.z]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var grow := 0.04 * v
	for axis in 3:
		var u := (axis + 1) % 3
		var w := (axis + 2) % 3
		var sa: int = strides[axis]
		var su: int = strides[u]
		var sw: int = strides[w]
		var du: int = dims[u]
		var dw: int = dims[w]
		for dir: int in [-1, 1]:
			if axis == 1 and dir == -1:
				continue
			var off := sa * dir
			var normal := Vector3.ZERO
			normal[axis] = dir
			var palette := _top if axis == 1 else _side
			var mask := PackedInt32Array()
			mask.resize(du * dw)
			var da: int = dims[axis]
			for i in da:
				var base: int = (i + 1) * sa + su + sw
				for b in dw:
					var row: int = base + b * sw
					for a in du:
						var c: int = row + a * su
						var col := occ[c]
						var key := 0
						if col != 0 and occ[c + off] == 0:
							var o: int = c + off
							var um := int(occ[o - su] != 0)
							var up := int(occ[o + su] != 0)
							var wm := int(occ[o - sw] != 0)
							var wp := int(occ[o + sw] != 0)
							var k0 := 0 if um + wm == 2 else 3 - um - wm - int(occ[o - su - sw] != 0)
							var k1 := 0 if up + wm == 2 else 3 - up - wm - int(occ[o + su - sw] != 0)
							var k2 := 0 if up + wp == 2 else 3 - up - wp - int(occ[o + su + sw] != 0)
							var k3 := 0 if um + wp == 2 else 3 - um - wp - int(occ[o - su + sw] != 0)
							key = col | ((k0 | (k1 << 2) | (k2 << 4) | (k3 << 6)) << 8)
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
						var ao4 := key >> 8
						if (ao4 & 3) == ((ao4 >> 2) & 3) and ((ao4 >> 6) & 3) == ((ao4 >> 4) & 3):
							while a + wide < du and mask[a + wide + b * du] == key:
								wide += 1
						if (ao4 & 3) == ((ao4 >> 6) & 3) and ((ao4 >> 2) & 3) == ((ao4 >> 4) & 3):
							var more := true
							while more and b + high < dw:
								for k in wide:
									if mask[a + k + (b + high) * du] != key:
										more = false
										break
								if more:
									high += 1
						for hb in high:
							for ka in wide:
								mask[a + ka + (b + hb) * du] = 0
						var plane := float(i + (1 if dir > 0 else 0))
						var p: Array[Vector3] = []
						for q: Vector2i in [Vector2i(a, b), Vector2i(a + wide, b), Vector2i(a + wide, b + high), Vector2i(a, b + high)]:
							var gp := Vector3.ZERO
							gp[axis] = plane
							gp[u] = q.x
							gp[w] = q.y
							p.append(lo + gp * v)
						var centre := (p[0] + p[2]) * 0.5
						for k in 4:
							p[k] += (p[k] - centre).normalized() * grow
						var aos := [ao4 & 3, (ao4 >> 2) & 3, (ao4 >> 4) & 3, (ao4 >> 6) & 3]
						# Counter-clockwise seen from outside when the normal is
						# u x w; Godot fronts are clockwise.
						var ccw := normal.dot(Vector3(p[1] - p[0]).cross(p[2] - p[0])) > 0.0
						var order: Array = [0, 2, 1, 0, 3, 2] if aos[0] + aos[2] >= aos[1] + aos[3] else [0, 3, 1, 1, 3, 2]
						if not ccw:
							order = [0, 1, 2, 0, 2, 3] if aos[0] + aos[2] >= aos[1] + aos[3] else [0, 1, 3, 1, 2, 3]
						var base_col: Color = palette[key & 0xFF]
						for k: int in order:
							var f: float = AO[aos[k]]
							verts.append(p[k])
							norms.append(normal)
							cols.append(Color(base_col.r * f, base_col.g * f, base_col.b * f))
						a += wide
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	if verts.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, material())
	return m

static var _material: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 1.0
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _material

static func triangles(m: ArrayMesh) -> int:
	return 0 if m.get_surface_count() == 0 else m.surface_get_array_len(0) / 3
