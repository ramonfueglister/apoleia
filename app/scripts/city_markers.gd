extends Node3D
## Town markers on the far map (Ramon 31.10.2026, Bauplan B step 3: "kleine
## Voxel-Stadtmarke"). From the 2 km tiles on (about 90 km view width) the
## terrain draws no houses any more and a town is only its roof coloured
## tiles at its real area (tools/build_tile_terrain.py settlements), so each
## of the 860 towns of the 117 AD list gets a small cluster of the town's own
## lot models instead: one to five houses by its people, a temple from
## TEMPLE_FROM people, a gate with two towers where Hanson's database lists
## walls. A marker keeps its size on screen (MARKER_PX a 10 m lot, as EU5's
## town models), so it is a sign for a town, not a building to scale; the
## larger towns carry their name. Zoomed further out only the larger towns
## keep their marker (min_people), so Italy does not turn into a carpet of
## them. Names are the ancient ones of the database (117 AD); later epochs
## will need their own (the naming plan).
##
## Names give way to each other as on a printed map (Ramon 31.10.2026:
## "städte regionsnamen überdecken sich gegenseitig"): on every camera move
## the names are placed largest town first, and a name whose box on screen
## would touch one already placed stays hidden (greedy label placement by
## rank, Imhof 1975; Christensen, Marks & Shieber 1995). Names fade in and
## out instead of popping. The database's province notes in brackets, as in
## "Apamea (Syria) (1)", are left off the sign.

const RomanBuildings = preload("res://scripts/voxel/roman_buildings.gd")
const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const FACTS := "data/cities/facts.json"
const LOT_M := 10.0 # a lot model's side (voxel/roman_buildings.gd)
const MARKER_PX := 9.0 # pixels a 10 m lot spans on screen
const FROM_LEVEL := 2 # terrain zoom level (TileTerrain.LEVELS) from which the markers stand
## people (117 AD, Hanson) from which a town has 2, 3, 4, 5 houses
const HOUSE_STEPS: Array[float] = [3000.0, 10000.0, 30000.0, 100000.0]
const TEMPLE_FROM := 30000.0
const NAME_FROM := 20000.0 # people from which a town shows its name
## the fewest people a town needs to keep its marker at a view width (km):
## all of them up to ALL_KM, then rising with the width
const ALL_KM := 300.0
const PEOPLE_AT_ALL := 1000.0
const PEOPLE_PER_KM := 25.0
const LABEL_GAP_PX := 6.0 # free room kept around each name on screen
const FADE_S := 0.25 # seconds a name takes to fade in or out
## where the houses of a cluster stand (lot sides, x and z from its middle),
## the first n for n houses; the temple and the gate take the slots after
const SPOTS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.05, 0.15), Vector2(-0.9, 0.55), Vector2(0.35, -1.0),
	Vector2(-0.7, -0.75)]
const TEMPLE_SPOT := Vector2(0.15, 1.15)
const GATE_SPOT := Vector2(0.0, 2.0)

var terrain: Node3D
var _towns: Array[Dictionary] = [] # pos (world km), people, kind, name; largest first
var _sets: Dictionary = {} # kind -> {node: MultiMeshInstance3D, towns: Array[int]}
var _labels: Array[Label3D] = []
var _label_px: Array[Vector2] = [] # each name's box in font pixels (with its outline)
var _label_want: PackedFloat32Array = [] # 1 where the name is placed, 0 where it gives way
var _label_alpha: PackedFloat32Array = []
var _level := -99
var _shown := -1.0

## Reads the towns (data/cities/facts.json) and builds a mesh per kind of
## marker; false without the facts.
func setup(tile_terrain: Node3D, root: String) -> bool:
	terrain = tile_terrain
	var text := FileAccess.get_file_as_string(root.path_join(FACTS))
	if text == "":
		push_warning("town markers: %s missing" % FACTS)
		return false
	var cities: Dictionary = JSON.parse_string(text).cities
	for id: String in cities:
		var c: Dictionary = cities[id]
		var people := float(c.pop117) if c.get("pop117") != null else 0.0
		var houses := 1
		for step in HOUSE_STEPS:
			if people >= step:
				houses += 1
		var walls := false
		for m: String in c.get("monuments", []):
			if m.begins_with("Walls") and not m.ends_with("?"):
				walls = true
		var kind := houses * 4 + (2 if people >= TEMPLE_FROM else 0) + (1 if walls else 0)
		_towns.append({"pos": _world(float(c.lon), float(c.lat)), "people": people, "kind": kind,
			"name": str(c.ancient) if c.get("ancient") != null else id})
	_towns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.people > b.people)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	for k in _towns.size():
		var kind: int = _towns[k].kind
		if not _sets.has(kind):
			var node := MultiMeshInstance3D.new()
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.mesh = _marker_mesh(kind)
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			_sets[kind] = {"node": node, "towns": []}
		_sets[kind].towns.append(k)
	for kind in _sets:
		var node: MultiMeshInstance3D = _sets[kind].node
		node.multimesh.instance_count = _sets[kind].towns.size()
	var font := Vic3.title_font()
	for t in _towns:
		if t.people < NAME_FROM:
			break
		var label := Label3D.new()
		label.text = _sign_name(t.name)
		label.font = font
		label.font_size = 40 if t.people >= 100000.0 else 30
		label.pixel_size = 0.0005
		label.fixed_size = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color(0.98, 0.95, 0.86)
		label.outline_modulate = Color(0.16, 0.11, 0.08)
		label.outline_size = 10
		label.visible = false
		add_child(label)
		_labels.append(label)
		_label_px.append(font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
			+ Vector2.ONE * label.outline_size)
	_label_want.resize(_labels.size())
	_label_alpha.resize(_labels.size())
	_label_want.fill(0.0)
	_label_alpha.fill(0.0)
	set_process(false)
	visible = false
	return true

## A town's name as its sign shows it: without the database's notes in
## brackets ("Vindobriga (Gallia Aquitania) (1)" -> "Vindobriga"), with a
## capital first letter.
static func _sign_name(raw: String) -> String:
	var cut := raw.find(" (")
	if cut > 0:
		raw = raw.substr(0, cut)
	raw = raw.strip_edges()
	return raw.left(1).to_upper() + raw.substr(1)

static func _world(lon: float, lat: float) -> Vector2:
	return Vector2(6371.0088 * cos(deg_to_rad(41.0)) * deg_to_rad(lon - 19.0), -6371.0088 * deg_to_rad(lat - 41.0))

## One marker of `kind` (houses * 4 + 2 with a temple + 1 with walls) from
## the town's lot models at their lowest detail, in metres, its middle at
## the origin, standing on y = 0.
func _marker_mesh(kind: int) -> ArrayMesh:
	var parts: Array = []
	for n in kind >> 2:
		parts.append(["house", (n * 6) % 28, SPOTS[n]])
	if kind & 2:
		parts.append(["plan_temple", 0, TEMPLE_SPOT])
	if kind & 1:
		parts.append(["plan_gate", 0, GATE_SPOT])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Array in parts:
		var mesh: ArrayMesh = RomanBuildings.lot_mesh(p[0], p[1], 2)
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		var centre := box.position + box.size * 0.5
		var spot: Vector2 = p[2] * LOT_M
		var xf := Transform3D(Basis.IDENTITY, Vector3(spot.x - centre.x, -box.position.y, spot.y - centre.z))
		for s in mesh.get_surface_count():
			st.append_from(mesh, s, xf)
	return st.commit()

## The fewest people a town needs for its marker at a view `width` km wide.
static func min_people(width: float) -> float:
	return PEOPLE_AT_ALL if width <= ALL_KM else PEOPLE_AT_ALL + (width - ALL_KM) * PEOPLE_PER_KM

## Shows the markers from FROM_LEVEL, sized for a view `width` km wide on a
## viewport `pixels` wide; puts them on the ground when the zoom level
## changed.
func update_view(width: float, pixels: float) -> void:
	var level: int = terrain.level
	var on := level >= FROM_LEVEL
	visible = on
	if not on:
		_level = level
		return
	var km_per_m := width / maxf(pixels, 1.0) * MARKER_PX / LOT_M
	if level == _level and is_equal_approx(km_per_m, _shown):
		_place_labels(min_people(width)) # panned or turned: names move on screen
		return
	var regrounded := level != _level
	_level = level
	_shown = km_per_m
	var least := min_people(width)
	var scale := Basis.IDENTITY.scaled(Vector3.ONE * km_per_m)
	for kind in _sets:
		var group: Dictionary = _sets[kind]
		var mm: MultiMesh = group.node.multimesh
		var shown := 0
		for k: int in group.towns:
			var t: Dictionary = _towns[k]
			if regrounded or not t.has("y"):
				t.y = terrain.ground_y(t.pos)
			if t.people < least:
				continue
			mm.set_instance_transform(shown, Transform3D(scale, Vector3(t.pos.x, t.y, t.pos.y)))
			shown += 1
		mm.visible_instance_count = shown
	for k in _labels.size():
		var t: Dictionary = _towns[k]
		_labels[k].position = Vector3(t.pos.x, t.y + km_per_m * LOT_M * 1.6, t.pos.y + km_per_m * LOT_M * 1.8)
	_place_labels(least)

## Decides which names show: largest town first, each name only where its
## box on screen keeps LABEL_GAP_PX from every name already placed. Called on
## every camera move (update_view); the fading runs in _process.
func _place_labels(least: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen := get_viewport().get_visible_rect()
	# a fixed_size Label3D in a perspective view is as large on screen as a
	# label of pixel_size world units at 1 unit before the camera
	var px_per_font_px := screen.size.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var placed: Array[Rect2] = []
	for k in _labels.size():
		var label := _labels[k]
		var want := 0.0
		if _towns[k].people >= least and not camera.is_position_behind(label.global_position):
			var size := _label_px[k] * label.pixel_size * px_per_font_px
			var box := Rect2(camera.unproject_position(label.global_position) - size * 0.5, size)
			if screen.intersects(box):
				var padded := box.grow(LABEL_GAP_PX)
				want = 1.0
				for other in placed:
					if padded.intersects(other):
						want = 0.0
						break
				if want > 0.0:
					placed.append(box)
		_label_want[k] = want
	set_process(true)

## Fades each name toward shown or hidden; stops once all have arrived.
func _process(delta: float) -> void:
	var step := delta / FADE_S
	var moving := false
	for k in _labels.size():
		var a := move_toward(_label_alpha[k], _label_want[k], step)
		_label_alpha[k] = a
		moving = moving or a != _label_want[k]
		var label := _labels[k]
		label.visible = a > 0.0
		label.modulate.a = a
		label.outline_modulate.a = a
	if not moving:
		set_process(false)
