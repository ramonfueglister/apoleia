extends MultiMeshInstance3D
## What the simulation has at each village house, drawn beside the house
## (Ramon, 30.10.2026: "Wuselfaktor", "alles aus der Simulation"): smoke
## from the roof where the household has food to cook (its pantry, or a
## farm's store; a hungry house stays cold), a tent in place of the
## farmhouse for a tent household, sheaves in the yard while its farm's
## harvest still wants hands and seed sacks while its sowing does, its
## farm's sheep (up to eight) round the yard and the pigs it fattens in a
## pen. At the slow speeds (game_clock.gd) a house that cooks lights its
## lamp at dusk, behind the two front windows, and puts it out an hour to
## three later, and again before sunrise (`set_lamps`); what the house
## burns is not counted, it is the household that has food to cook.
## ApoleiaPeople.house_looks gives 4 bytes per house slot, once a
## sim week (sim/godot/src/people_dots.rs publish_house_looks,
## Grain::house_look); people_dots.gd uploads them as `look_tex` and lets
## this MultiMesh draw the nearest houses of the house list
## (people_house_life.gdshader), up close only (LIFE_KM).

const SHADER = preload("res://shaders/people_house_life.gdshader")
const PeopleTrips = preload("res://scripts/sim/people_trips.gd")
const LIFE_MAX := 1024 # houses with their life at once (the house list's second level of detail)
const LIFE_KM := 5.0 # view width up to which it is drawn

var material := ShaderMaterial.new()
var _image: Image
var _texture: ImageTexture
var _version := -1
var _size := Vector2i.ZERO
var _listed := 0
var _view_km := INF
var _lamps := Vector2(-1.0, -1.0) # hours since sunset and to sunrise in the shader, -1 by day

func setup(km_per_m: float, list_tex: Texture2D, list_w: int) -> void:
	name = "PeopleHouseLife"
	material.shader = SHADER
	material.set_shader_parameter("km_per_m", km_per_m)
	material.set_shader_parameter("list_tex", list_tex)
	material.set_shader_parameter("list_w", list_w)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh()
	mm.instance_count = LIFE_MAX
	mm.visible_instance_count = 0
	multimesh = mm

## The looks of the houses anew when the sim has new ones (or the house
## texture has `layers` pages of `side`² houses now); returns the texture
## when it changed (for the house materials, which leave out tent houses),
## else null.
func sync(people: RefCounted, side: int, layers: int) -> Texture2D:
	if not people.has_method("house_looks"):
		return null
	var version: int = people.house_looks_version()
	var size := Vector2i(side, side * maxi(layers, 1))
	if version == _version and size == _size:
		return null
	_version = version
	var bytes: PackedByteArray = people.house_looks()
	bytes.resize(size.x * size.y * 4) # houses newer than the looks: nothing yet
	if size != _size or _image == null:
		_size = size
		_image = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
		_texture = ImageTexture.create_from_image(_image)
	else:
		_image.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
		_texture.update(_image)
	material.set_shader_parameter("look_tex", _texture)
	show_houses(_listed, _view_km)
	return _texture

## How many houses of the list (nearest first) get their life drawn.
func show_houses(listed: int, view_km: float) -> void:
	_listed = listed
	_view_km = view_km
	multimesh.visible_instance_count = mini(listed, LIFE_MAX) if view_km <= LIFE_KM and _version >= 0 else 0
	visible = multimesh.visible_instance_count > 0

## The lamps by the hour (day_clock.gd; `hour` < 0 at the fast speeds
## puts them out): hours since sunset and hours to sunrise, -1 by day.
func set_lamps(hour: float, sun: Vector2) -> void:
	var lamps := Vector2(-1.0, -1.0)
	if hour >= sun.y:
		lamps.x = hour - sun.y
	elif hour >= 0.0 and hour < sun.x:
		lamps = Vector2(hour + 24.0 - sun.y, sun.x - hour)
	lamps = (lamps * 100.0).round() / 100.0 # a new uniform only every 36 s of the clock
	if lamps != _lamps:
		_lamps = lamps
		material.set_shader_parameter("since_sunset", lamps.x)
		material.set_shader_parameter("to_sunrise", lamps.y)

## The parts in metres about the house's middle, its front +z (UV.x the
## part, people_house_life.gdshader): three smoke puffs at the origin (the
## shader puts them over the roof), eight sheep, three pigs and their pen,
## a tent, sheaves and seed sacks, the light in two front windows.
static func _mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := Callable(PeopleTrips, "_box")
	for k in 3:
		box.call(st, Vector3.ZERO, Vector3(0.5, 0.45, 0.5), Color(0.86, 0.85, 0.82), k)
		box.call(st, Vector3(0.35, 0.25, 0.2), Vector3(0.35, 0.3, 0.35), Color(0.78, 0.77, 0.75), k)
	var wool := Color(0.93, 0.91, 0.84)
	var face := Color(0.25, 0.2, 0.17)
	for k in 8: # a sheep: a woolly body, dark head and legs, the head to +z
		var part := 3 + k
		box.call(st, Vector3(0.0, 0.62, 0.0), Vector3(0.32, 0.27, 0.5), wool, part)
		box.call(st, Vector3(0.0, 0.75, 0.62), Vector3(0.13, 0.14, 0.17), face, part)
		for leg in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			box.call(st, Vector3(0.18 * leg.x, 0.18, 0.32 * leg.y), Vector3(0.05, 0.18, 0.05), face, part)
	var pink := Color(0.86, 0.6, 0.55)
	for k in 3: # a pig
		var part := 11 + k
		box.call(st, Vector3(0.0, 0.42, 0.0), Vector3(0.3, 0.26, 0.55), pink, part)
		box.call(st, Vector3(0.0, 0.42, 0.62), Vector3(0.14, 0.12, 0.08), pink.darkened(0.15), part)
		for leg in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			box.call(st, Vector3(0.18 * leg.x, 0.1, 0.35 * leg.y), Vector3(0.06, 0.1, 0.06), pink.darkened(0.2), part)
	var wood := Color(0.5, 0.36, 0.22)
	var pen := Vector3(-8.0, 0.0, -6.8) # the pen behind the house, where the pigs root
	for side in [-1.0, 1.0]:
		box.call(st, pen + Vector3(0.0, 0.55, 2.0 * side), Vector3(3.2, 0.06, 0.05), wood, 14)
		box.call(st, pen + Vector3(3.2 * side, 0.55, 0.0), Vector3(0.05, 0.06, 2.0), wood, 14)
		for end in [-1.0, 1.0]:
			box.call(st, pen + Vector3(3.2 * side, 0.4, 2.0 * end), Vector3(0.08, 0.4, 0.08), wood.darkened(0.2), 14)
	var linen := Color(0.86, 0.8, 0.68)
	var patch := Color(0.7, 0.6, 0.46)
	# a tent of patched linen on a ridge pole, its two slopes as stepped boxes
	for k in 5:
		var y := 0.3 + k * 0.5
		var half_x := 2.2 - k * 0.42
		box.call(st, Vector3(0.0, y, 0.0), Vector3(half_x, 0.25, 2.6), linen if k % 2 == 0 else patch, 15)
	box.call(st, Vector3(0.0, 2.75, 0.0), Vector3(0.06, 0.06, 2.9), wood, 15)
	box.call(st, Vector3(0.0, 0.9, 2.62), Vector3(0.7, 0.9, 0.04), Color(0.2, 0.16, 0.12), 15) # the dark door
	var straw := Color(0.86, 0.72, 0.38)
	for k in 3: # sheaves stood up in stooks in the yard
		var at := Vector3(4.5 + k * 1.6, 0.0, 5.0 - k * 0.7)
		box.call(st, at + Vector3(0.0, 0.6, 0.0), Vector3(0.35, 0.6, 0.35), straw, 16)
		box.call(st, at + Vector3(0.0, 1.3, 0.0), Vector3(0.22, 0.12, 0.22), straw.darkened(0.15), 16)
	var sack := Color(0.76, 0.67, 0.48)
	for k in 3: # seed sacks by the door
		box.call(st, Vector3(-2.0 + k * 0.8, 0.4, 4.6), Vector3(0.3, 0.4, 0.25), sack, 17)
	for side in [-1.0, 1.0]: # lamplight in the front windows (farmhouse.gd WINS_HOUSE, the wall at HALF_Z)
		box.call(st, Vector3(1.625 * side, 2.1, 3.3), Vector3(0.3, 0.38, 0.04), Color(1.0, 0.72, 0.36), 18)
	st.index()
	return st.commit()
