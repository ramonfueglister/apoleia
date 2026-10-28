extends Node
## A quarter of Caesar III's town in Urbek's voxel craft (roman_town.gd),
## rendered off screen with the game camera (north up, 30 degree tilt,
## nearly orthographic) and saved. Arguments after `--`:
##   --width=m   ground width across the picture (default 80)
##   --tx=m --tz=m   view centre;  --res=WxH (default 1920x1080)
##   --shot=path.png   save the frame and quit

const Kit := preload("res://urbek_kit.gd")
const Town := preload("res://roman_town.gd")
const Colosseum := preload("res://colosseum25.gd")
const LOT_M := 10.0

var args := {}
var vp: SubViewport
var frame := 0
var meshes := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var res: PackedStringArray = String(args.get("res", "1920x1080")).split("x")
	vp = SubViewport.new()
	vp.size = Vector2i(int(res[0]), int(res[1]))
	vp.msaa_3d = Viewport.MSAA_8X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var t0 := Time.get_ticks_msec()
	_environment()
	_layout()
	print("built in ", Time.get_ticks_msec() - t0, " ms")
	_camera(Vector3(float(args.get("tx", "0")), 2.0, float(args.get("tz", "-8"))), float(args.get("width", "80")))

func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9cc3e0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7d8cc0")
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.0
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# A low afternoon sun from the west-south-west: tops bright, fronts
	# lit at a slant so sills and cornices throw shadows, long shadows
	# across the north-south streets.
	sun.rotation_degrees = Vector3(-35, -65, 0)
	sun.light_energy = 1.2
	sun.light_color = Color("ffe6c4")
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.9
	sun.shadow_blur = 0.3
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	vp.add_child(sun)

func _mesh(key: String) -> ArrayMesh:
	if not meshes.has(key):
		var parts := key.split(":")
		var seed := int(parts[1])
		match parts[0]:
			"ew": meshes[key] = Town.street(false, seed)
			"ns": meshes[key] = Town.street(true, seed)
			"x": meshes[key] = Town.crossing(seed)
			"house": meshes[key] = Town.house_lot(seed)
			"domus": meshes[key] = Town.domus(seed)
			"insula": meshes[key] = Town.insula(seed)
			"temple": meshes[key] = Town.temple(seed)
			"garden": meshes[key] = Town.garden(seed)
			"market": meshes[key] = Town.market(seed)
			"plaza": meshes[key] = Town.plaza(seed)
			"via": meshes[key] = Town.via(seed, 0)
			"vias": meshes[key] = Town.via(seed, 1)
			"vx": meshes[key] = Town.via_crossing(seed, 0)
			"vxs": meshes[key] = Town.via_crossing(seed, 1)
			"rstrip": meshes[key] = Town.river_strip(seed, 7, RIVER_ROW, 7)
			"tombs": meshes[key] = Town.tombs(seed)
			"farm": meshes[key] = Town.farm(seed)
			"vineyard": meshes[key] = Town.vineyard(seed)
			"pasture": meshes[key] = Town.pasture(seed)
			"terrace": meshes[key] = Town.terrace(seed & 3, seed >> 2, seed >> 5)
			"h00": meshes[key] = Town.house_lot(seed, false, false)
			"h10": meshes[key] = Town.house_lot(seed, true, false)
			"h01": meshes[key] = Town.house_lot(seed, false, true)
			"h11": meshes[key] = Town.house_lot(seed, true, true)
			"hvia": meshes[key] = Town.house_lot(seed, true)
			"forum": meshes[key] = Town.forum(seed)
			"baths": meshes[key] = Town.baths(seed)
	return meshes[key]

## Puts lot model `key` (`size` lots) with its north-west corner on lot
## (lx, lz); `south` false turns it to face north.
func _put(key: String, lx: int, lz: int, south := true, size := Vector2i.ONE, y := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(key)
	var o := Vector3(lx * LOT_M, y, lz * LOT_M)
	if south:
		mi.transform = Transform3D(Basis.IDENTITY, o)
	else:
		mi.transform = Transform3D(Basis(Vector3.UP, PI), o + Vector3(size.x * LOT_M, 0.0, size.y * LOT_M))
	vp.add_child(mi)

## Streets run east-west on rows STREETS_EW and north-south on columns
## STREETS_NS; between them blocks two lots deep hold row houses facing
## the nearer street, with a forum (temple, market, gardens), atrium houses
## and apartment blocks placed first.
const STREETS_EW := [3, 0, -3, -6, -9, -12]
const RIVER_ROW := 4  # the river's models start on this row
const STREETS_NS := [-6, 0, 6]
const SPECIAL := [
	["forum:0", 1, -5, Vector2i(5, 5)], ["baths:0", -5, -2, Vector2i(3, 2)],
	["insula:2", 8, -1, Vector2i(2, 1)], ["insula:5", -2, -1, Vector2i(2, 1)],
	["insula:4", 10, -1, Vector2i(2, 1)], ["insula:8", -14, -1, Vector2i(2, 1)],
	["insula:7", 13, -1, Vector2i(2, 1)],
	["domus:1", -9, 10, Vector2i(2, 2)], ["domus:2", 7, 10, Vector2i(2, 2)],
	["domus:0", -11, -2, Vector2i(2, 2)], ["market:0", -9, -2, Vector2i(2, 2)],
	["temple:0", 7, -5, Vector2i(2, 2)], ["garden:2", -1, -4, Vector2i.ONE],
	["garden:3", 5, -7, Vector2i.ONE],
]

## The Colosseum on a paved square of COLOSSEUM lots.
const COLOSSEUM := Rect2i(-10, -12, 9, 8)

func _colosseum(taken: Dictionary) -> void:
	var c := (Vector2(COLOSSEUM.position) + Vector2(COLOSSEUM.size) * 0.5) * LOT_M
	for lz in range(COLOSSEUM.position.y, COLOSSEUM.end.y):
		for lx in range(COLOSSEUM.position.x, COLOSSEUM.end.x):
			taken[Vector2i(lx, lz)] = true
			var p := (Vector2(lx, lz) + Vector2(0.5, 0.5)) * LOT_M - c
			var under := (p.x / 42.0) ** 2 + (p.y / 36.0) ** 2 < 1.0
			if lx == COLOSSEUM.end.x - 1 and lz == COLOSSEUM.end.y - 1:
				_put("plaza:8", lx, lz)
				continue
			_put("plaza:%d" % (0 if under else 4 + ((lx * 3 + lz * 5) & 3) + 8 * ((lx + lz) & 1)), lx, lz)
	var t0 := Time.get_ticks_msec()
	var mi := MeshInstance3D.new()
	mi.mesh = Colosseum.mesh()
	mi.position = Vector3(c.x, 0.0, c.y)
	vp.add_child(mi)
	print("colosseum: ", Kit.triangles(mi.mesh), " triangles, ", Time.get_ticks_msec() - t0, " ms")

## A terraced hill: lots raised one to three terraces, rising to the
## north, on retaining walls where the ground drops; atrium houses, a
## temple on the top and gardens on them.
const HILL := Rect2i(8, -16, 6, 6)
const HILL_SPECIAL := [["domus:1", 8, -12], ["domus:2", 12, -14], ["temple:4", 10, -16], ["domus:0", 8, -14]]

func _hill_level(lx: int, lz: int) -> int:
	if not HILL.has_point(Vector2i(lx, lz)):
		return 0
	return 1 + (-11 - lz) / 2

func _hill(taken: Dictionary) -> void:
	var covered := {}
	for sp: Array in HILL_SPECIAL:
		var lvl := _hill_level(sp[1], sp[2])
		_put(sp[0], sp[1], sp[2], true, Vector2i(2, 2), lvl * Town.TERRACE * Kit.V)
		for dz in 2:
			for dx in 2:
				covered[Vector2i(sp[1] + dx, sp[2] + dz)] = true
	for lz in range(HILL.position.y, HILL.end.y):
		for lx in range(HILL.position.x, HILL.end.x):
			var lvl := _hill_level(lx, lz)
			var walls := 0
			if _hill_level(lx, lz + 1) < lvl:
				walls |= 1
			if _hill_level(lx - 1, lz) < lvl:
				walls |= 2
			if _hill_level(lx + 1, lz) < lvl:
				walls |= 4
			_put("terrace:%d" % (lvl | (walls << 2) | (((lx + lz) & 1) << 5)), lx, lz)
			taken[Vector2i(lx, lz)] = true
			if not covered.has(Vector2i(lx, lz)):
				_put("garden:%d" % ((lx * 3 + lz) & 3), lx, lz, true, Vector2i.ONE, lvl * Town.TERRACE * Kit.V)

## Blocks away from the forum: some get an atrium house, an apartment
## block, a temple, a market or a park, the rest row houses.
func _blocks(taken: Dictionary) -> void:
	for kz: int in [-9, -8, -7, -6, -5, -4, -3, -2, -1, 2]:
		for kx in range(-3, 3):
			var x0 := 6 * kx + 1
			var north := 3 * kz + 1
			var r := Kit.rnd(kx, kz, 0, 77) % 100
			var at := x0 + Kit.rnd(kx, kz, 1, 77) % 4
			var key := ""
			var size := Vector2i(2, 2)
			var z := north
			if r < 16:
				key = "domus:%d" % (Kit.rnd(kx, kz, 2, 77) % 3)
			elif r < 34:
				key = "insula:%d" % (Kit.rnd(kx, kz, 2, 77) % 4)
				size = Vector2i(2, 1)
				z = north + 1
			elif r < 39:
				key = "temple:%d" % (Kit.rnd(kx, kz, 2, 77) % 6)
			elif r < 44:
				key = "market:%d" % (Kit.rnd(kx, kz, 2, 77) % 4)
			if key.is_empty():
				continue
			var free := true
			for dz in size.y:
				for dx in size.x:
					if taken.has(Vector2i(at + dx, z + dz)):
						free = false
			if not free:
				continue
			for dz in size.y:
				for dx in size.x:
					taken[Vector2i(at + dx, z + dz)] = true
			_put(key, at, z, true, size)

func _layout() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("86ad52")
	gm.roughness = 1.0
	plane.material = gm
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(0, -1.6, 0)
	vp.add_child(ground)
	var taken := {}
	_colosseum(taken)
	_hill(taken)
	for sp: Array in SPECIAL:
		var size: Vector2i = sp[3]
		for dz in size.y:
			for dx in size.x:
				taken[Vector2i(sp[1] + dx, sp[2] + dz)] = true
		_put(sp[0], sp[1], sp[2], sp[4] if sp.size() > 4 else true, size)
	_blocks(taken)
	var n := 0
	for lx0: int in [-17, -10, -3, 4, 11]:
		_put("rstrip:%d" % lx0, lx0, RIVER_ROW)
	for lz in range(-26, 14):
		for lx in range(-17, 18):
			if taken.has(Vector2i(lx, lz)) or Town.is_river_lot(lx, lz):
				continue
			var ns: bool = posmod(lx, 6) == 0
			var h := (lx * 7 + lz * 13) & 15
			if lz == 0 or lz == 1:
				# the main street, two lots wide
				var half := "" if lz == 0 else "s"
				_put(("vx%s:%d" if ns else "via%s:%d") % [half, (lx * 5 + lz) & 7], lx, lz)
				continue
			var ew: bool = posmod(lz, 3) == 0
			if ew and ns:
				_put("x:%d" % h, lx, lz)
			elif ns:
				_put("ns:%d" % h, lx, lz)
			elif ew:
				_put("ew:%d" % ((lx * 5 + lz * 3) & 15), lx, lz)
			else:
				n += 1
				# face the main street or the river where they are next door,
				# else the street to the south, else the one to the north;
				# houses facing north stay low so the street shows
				var south: bool = posmod(lz + 1, 3) == 0 or lz == -1
				if lz == 2 or Town.is_river_lot(lx, lz - 1):
					south = false
				if Town.is_river_lot(lx, lz + 1):
					south = true
				if absi(lx) == 1 and lz >= 8:
					# tombs line the road out of town beyond the river
					_put("tombs:%d" % (h & 7), lx, lz)
				elif lz >= 7 and absi(lx) > 4:
					# beyond the river the country: gardens, vines, sheep
					var r := Kit.rnd(lx, lz, 0, 21) % 100
					var key := "farm" if r < 30 else ("vineyard" if r < 55 else ("pasture" if r < 75 else "garden"))
					_put("%s:%d" % [key, h & 7], lx, lz)
				elif ((lx * 11 + lz * 5) & 15) in [3, 9, 14]:
					_put("garden:%d" % (h & 3), lx, lz, south)
				else:
					var v := 1 if lz == -1 or lz == 2 else 0
					var l := 0 if south else 1
					_put("h%d%d:%d" % [v, l, (lx * 31 + lz * 17) & 31], lx, lz, south)
	var tris := 0
	for m: ArrayMesh in meshes.values():
		tris += Kit.triangles(m)
	print("lots: ", n, ", models: ", meshes.size(), ", triangles: ", tris)

## The game camera: north up, tilted 30 degrees, nearly orthographic;
## `width` metres of ground across the picture.
func _camera(target: Vector3, width: float, fov := 10.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	var distance := width / (2.0 * tan(deg_to_rad(fov) * 0.5))
	var dir := Basis.from_euler(Vector3(deg_to_rad(-30.0), 0.0, 0.0)).z
	cam.far = distance * 4.0
	# Near plane just before the ground keeps the shadow splits tight.
	cam.near = maxf(0.05, distance - width * 1.2)
	vp.add_child(cam)
	cam.look_at_from_position(target + dir * distance, target)
	var sun: DirectionalLight3D = vp.get_node("Sun")
	sun.directional_shadow_max_distance = distance + width * 1.2

func _process(_delta: float) -> void:
	frame += 1
	if frame == 14:
		var path: String = args.get("shot", "user://town.png")
		vp.get_texture().get_image().save_png(path)
		print("saved ", path)
		get_tree().quit()
