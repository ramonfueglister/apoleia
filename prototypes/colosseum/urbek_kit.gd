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
const AO := [0.6, 0.74, 0.87, 1.0]

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
	GRANITE, GRANITE_P, HORSE, HORSE_D, HORSE_W,
	OBELISK, GLYPH, ROOFB, ROOFB_D, PORCH, PORCH_D, ARCH_D,
	ROOFB_L, DOME, BAND,
	DOME_C, GRANITE_L, GRANITE_D, ARENA, ARENA_D, BRONZE_P,
	STUCCO, JOINT, TRAV_C, TRAV_CW, GILT_W,
}

## Side colour, and the top colour where it differs (sRGB). Caesar III's
## warm plaster, terracotta and marble, at Urbek's brightness.
const COLOURS := {
	CREAM: ["ecdfc3"], CREAM_W: ["cdbd9c"], OCHRE: ["e9c98b"], OCHRE_W: ["c6a66a"],
	PINK: ["dcb49a"], PINK_W: ["c49e86"], WHITE: ["f2eee6"], WHITE_W: ["d0c9bc"],
	REDWASH: ["b9543e"], REDWASH_W: ["a54a37"], BRICK: ["bf6b4b"], BRICK_W: ["a95b3f"],
	TRIM: ["f3ede1"], STONE: ["cfc4ae"], STONE_W: ["bcb099"], MARBLE: ["efe6d6"], MARBLE_W: ["ddd2bf"],
	STEP: ["e2dacb", "ece5d7"],
	TILE: ["d06a5c", "dc705f"], TILE_D: ["c66357", "d26a5a"], TILE_L: ["d67061", "e27765"],
	EAVE: ["b8604f", "dc705f"], RIDGE: ["bd6253", "cf6b5c"],
	TILE2: ["d67a68", "e2846f"], TILE2_D: ["ce7363", "da7d69"], TILE2_L: ["dc806e", "e88b75"],
	EAVE2: ["c06e5c", "e2846f"], RIDGE2: ["c87462", "d87e6a"],
	TILEB: ["3f5f8c", "5b80b0"], TILEB_D: ["37547d", "4f729f"], TILEB_L: ["4a6c99", "6a8fbd"],
	EAVEB: ["2f3d52", "5b80b0"], RIDGEB: ["33496b", "466892"],
	GLASS: ["3a4440"], DARK: ["4a3f38"], DOOR: ["7b5034"], DOOR_D: ["5d3b27"],
	SHUTTER_G: ["4f6a3b"], SHUTTER_B: ["7a4e2e"], SHUTTER_U: ["5e7c99"], WOOD: ["8a6040", "9c6e4a"], WOOD_D: ["5f4029"],
	CLOTH_R: ["b04a3c"], CLOTH_W: ["f1ebdf"], CLOTH_B: ["3f6ea6"], CLOTH_G: ["5c8c47"], CLOTH_Y: ["e3b24a"],
	POT: ["b3603f"], AMPHORA: ["8e4e2e", "b8693e"], FRUIT_R: ["d0402f"], FRUIT_Y: ["eec24a"], FRUIT_G: ["8cb84a"],
	BREAD: ["d6a35c"],
	LEAF: ["24552a", "317035"], LEAF_D: ["1f4b25", "2a632f"], LEAF_L: ["2b6030", "3a7c3c"],
	CYPRESS: ["213f22", "2b522b"], CYPRESS_D: ["1b361d", "244624"], PINE: ["2c5a2a", "3b7236"], PINE_D: ["244d24", "31632e"],
	TRUNK: ["6e4b33"], FLOWER_R: ["d8463a"], FLOWER_P: ["c45bb0"], FLOWER_Y: ["f0c64a"], HEDGE: ["4f8037", "5f923f"],
	GRASS: ["37782f", "3c8434"], GRASS_D: ["34722d", "397e32"], GRASS_L: ["3a7d32", "408a37"],
	EARTH: ["b59263", "c49f6e"], EARTH_D: ["a5845a", "b38f63"],
	PAVE: ["d2c6ae", "ddd2bb"], PAVE_D: ["cec2aa", "d9ceb7"], PAVE_L: ["d5c9b2", "e0d5bf"],
	BASALT: ["5a5c62", "64666c"], BASALT_D: ["585a60", "62646a"], BASALT_L: ["5c5e64", "66686e"],
	CURB: ["b9ad97", "c6bba5"],
	WATER: ["4a87a8", "4f8faf"], BRONZE: ["9c7438"], GOLD: ["dcae4c", "e8bf5c"],
	ROBE_W: ["e8e0d0"], ROBE_R: ["a8443a"], ROBE_B: ["5a6a80"], SKIN: ["d9a27a"], HAIR: ["4a3326"],
	TRAV: ["e2d3b5", "ebdec3"], TRAV_W: ["d3c3a2", "ddcfb1"], TRAV_D: ["c6b392", "d1c0a0"], TRAV_L: ["efe6d2", "f5eedd"],
	VAULT: ["585a6a", "6a6b78"], SEAT: ["bfae8f", "dccfb2"], SEAT_D: ["ad9b7c", "c9ba9a"],
	SAND: ["d6b179", "e0bd84"], SAND_D: ["c8a26b", "d2ad75"], PODIUM: ["ece4d3", "f3ecde"], FLAG: ["c0392b"],
	TILE3: ["bf5f53", "ca6457"], TILE3_D: ["b65a4f", "c15f53"], TILE3_L: ["c46457", "d0695b"], EAVE3: ["a85549", "ca6457"], RIDGE3: ["ae584c", "be5f52"],
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
	STATUE: ["e6dccb", "efe7d8"], STREAK: ["a99d88"], VIA_P: ["bfb19a", "cdbfa6"], VIA_PD: ["bcae97", "c9bba2"],
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
	OLIVE: ["5c6a4c", "6e7c5a"], OLIVE_D: ["4c583e", "5c684a"], PLANE: ["275a2c", "357538"], BARK_L: ["b8ab8c"],
	GILT: ["b8913c", "d9b45a"], GILT_D: ["a8822f", "c9a24a"], GILT_L: ["c49d48", "e3c06a"], EAVEG: ["7a5e2a", "d9b45a"], RIDGEG: ["9c7a34", "c49d48"],
	COCCIO: ["c9a490", "dbb8a2"], COCCIO_D: ["b8937f", "cba792"], COCCIO_L: ["d4b09c", "e3c3ae"], ANTEFIX: ["c46a44", "d47a52"], ROPE: ["5a4632"],
	# grey granite of Mons Claudianus and pink granite of Aswan (the
	# Pantheon's porch), race horses: bay, black, grey
	GRANITE: ["8e8a85", "9c9893"], GRANITE_P: ["b08a7c", "bf9a8b"], HORSE: ["7a4a2c"], HORSE_D: ["3a2c24"], HORSE_W: ["d6d0c4"],
	# polished Aswan granite and its cut signs, weathered bronze tiles, the
	# shade under a porch, the dark inside an arch
	OBELISK: ["a8665a", "b4705f"], GLYPH: ["7c4538"], ROOFB: ["54402a", "5e4830"], ROOFB_D: ["43321f", "4b3923"],
	PORCH: ["807870", "8a8279"], PORCH_D: ["6b655f", "756f68"], ARCH_D: ["4e4037"],
	# the bronze roof's ribs, the gilt dome (risers, treads), the shadow band
	# under a cornice
	ROOFB_L: ["66503a", "735a3f"], DOME: ["8f6b1e", "b8933c"], BAND: ["a39d95"],
	# the dome's cap (its steps only shaded by the light), the lit and the
	# shaded side of a granite shaft, the circus sand and its rake lines
	DOME_C: ["b8933c"], GRANITE_L: ["a9a39d"], GRANITE_D: ["74706b"], ARENA: ["b08a55", "b8925a"], ARENA_D: ["a07c4a", "a8844f"],
	BRONZE_P: ["58401f"],
	# a step below marble: stucco, the joints between marble slabs, the
	# circus's travertine and its pilasters
	STUCCO: ["d0c6b8"], JOINT: ["c2b9a9"], TRAV_C: ["c5b79c", "cfc2a7"], TRAV_CW: ["b8aa8e", "c2b499"],
	# gilt bronze roof tiles, toned so a sunlit roof stays below white marble
	GILT_W: ["7d6020", "9a7a2e"],
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

	## 1 for each row along x (index y + n.y * z) with anything in it.
	func rows() -> PackedByteArray:
		var out := PackedByteArray()
		out.resize(n.y * n.z)
		for z in n.z:
			for y in n.y:
				var i := n.x * (y + n.y * z)
				if g.slice(i, i + n.x).count(0) < n.x:
					out[y + n.y * z] = 1
		return out

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
	return mesh_from(mesh_arrays(g, lo, v))

## The mesh of surface arrays from mesh_arrays().
static func mesh_from(arrays: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	if arrays[Mesh.ARRAY_VERTEX].size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, material())
	return m

## The surface arrays of mesh(g, lo, v). They touch no rendering server,
## so worker threads can make them (fill the colour tables first:
## _colours()).
static func mesh_arrays(g: Grid, lo: Vector3, v := V) -> Array:
	_colours()
	var n := g.n
	var px := n.x + 2
	var py := n.y + 2
	# The grid with an empty voxel all round, so neighbours need no bounds.
	var occ := PackedByteArray()
	var empty_row := PackedByteArray()
	empty_row.resize(px)
	var empty_layer := PackedByteArray()
	empty_layer.resize(px * py)
	occ.append_array(empty_layer)
	for z in n.z:
		occ.append_array(empty_row)
		for y in n.y:
			var src := n.x * (y + n.y * z)
			occ.append(0)
			occ.append_array(g.g.slice(src, src + n.x))
			occ.append(0)
		occ.append_array(empty_row)
	occ.append_array(empty_layer)
	# Rows along x with anything in them: most of a grid is air.
	var rows := g.rows()
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
			# Zero between slices: the merging below clears what it takes.
			var mask := PackedInt32Array()
			mask.resize(du * dw)
			var da: int = dims[axis]
			for i in da:
				var base: int = (i + 1) * sa + su + sw
				if axis == 1:
					# u is z, w is x: skip the empty rows of layer i
					for a in du:
						if rows[i + n.y * a] == 0:
							continue
						for b in dw:
							var c: int = base + a * su + b * sw
							if occ[c] != 0 and occ[c + off] == 0:
								mask[a + b * du] = _face(occ, c, off, su, sw)
				elif axis == 2:
					# u is x, w is y: skip the empty rows of slice i
					for b in dw:
						if rows[b + n.y * i] == 0:
							continue
						var row: int = base + b * sw
						for a in du:
							var c: int = row + a * su
							if occ[c] != 0 and occ[c + off] == 0:
								mask[a + b * du] = _face(occ, c, off, su, sw)
				else:
					for b in dw:
						var row: int = base + b * sw
						for a in du:
							var c: int = row + a * su
							if occ[c] != 0 and occ[c + off] == 0:
								mask[a + b * du] = _face(occ, c, off, su, sw)
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
	return arrays

# A face's key: its colour and the occlusion at its four corners, from the
# eight voxels round the empty voxel it faces.
static func _face(occ: PackedByteArray, c: int, off: int, su: int, sw: int) -> int:
	var o: int = c + off
	var um := int(occ[o - su] != 0)
	var up := int(occ[o + su] != 0)
	var wm := int(occ[o - sw] != 0)
	var wp := int(occ[o + sw] != 0)
	var k0 := 0 if um + wm == 2 else 3 - um - wm - int(occ[o - su - sw] != 0)
	var k1 := 0 if up + wm == 2 else 3 - up - wm - int(occ[o + su - sw] != 0)
	var k2 := 0 if up + wp == 2 else 3 - up - wp - int(occ[o + su + sw] != 0)
	var k3 := 0 if um + wp == 2 else 3 - um - wp - int(occ[o - su + sw] != 0)
	return occ[c] | ((k0 | (k1 << 2) | (k2 << 4) | (k3 << 6)) << 8)

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
