extends Node3D
## The roads the player builds, as narrow gravel bands on the ground
## (shaders/road.gdshaderinc). build_menu.gd decides where a road runs: it
## finds the way through the terrain, smooths it and hands each stretch
## between two crossings or ends over as points; this node only draws them.
##
##   set_road(id, points, progress, preview, blocked)  add or replace one
##   remove_road(id)                                   take it away
##
## `points` are world km (x, z) along the road's middle, already smooth;
## they are cut into steps of STEP_KM here so the band follows the ramps.
## `progress` 0..1 is the share built from the first point on; the rest
## shows as staked-out earth with pegs. A preview is drawn see-through,
## green, or red when `blocked`. Each road is one MeshInstance3D; the built
## ones share two materials (casing and fill, see road.gdshaderinc), the
## previews a third. They stand on the ground as the terrain draws it, so
## the terrain's uniforms are copied into them whenever they change.

const TileTerrain = preload("res://scripts/tile_terrain.gd")
const ROAD_SHADER = preload("res://shaders/road.gdshader")
const PREVIEW_SHADER = preload("res://shaders/road_preview.gdshader")
const ROAD_KM := 4.0 * TileTerrain.DIORAMA_KM_PER_M # a country road four diorama metres wide, half a farmhouse front
const STEP_KM := 0.02 # the band's step along the road (a quarter tile is 0.39 km, its ramps need several)
const CAP_SIDES := 8 # segments of the round cap at each end
const MIN_PX := 1.5 # half width on screen at least, so a road far out stays a line

var terrain: Node3D
var landscape: Node3D
var _roads := {} # id -> MeshInstance3D
var _casing := ShaderMaterial.new()
var _fill := ShaderMaterial.new()
var _preview := ShaderMaterial.new()
var _shared: Array[StringName] = []
var _shared_values := {}

func setup(landscape_node: Node3D, terrain_node: Node3D) -> void:
	landscape = landscape_node
	terrain = terrain_node
	for u in TileTerrain.TERRAIN_SHADER.get_shader_uniform_list():
		if not String(u.name).begins_with("sim_"):
			_shared.append(StringName(u.name))
	_casing.shader = ROAD_SHADER
	_casing.set_shader_parameter("layer", 0)
	_fill.shader = ROAD_SHADER
	_fill.set_shader_parameter("layer", 1)
	_casing.next_pass = _fill # the fill drawn after the casing of the same road
	_preview.shader = PREVIEW_SHADER
	_preview.set_shader_parameter("layer", 0)
	for m in [_casing, _fill, _preview]:
		m.set_shader_parameter("half_km", ROAD_KM * 0.5)
		m.set_shader_parameter("km_per_m", TileTerrain.DIORAMA_KM_PER_M)

## Adds the road `id` or replaces it.
func set_road(id: Variant, points: PackedVector2Array, progress := 1.0, preview := false, blocked := false) -> void:
	var view: MeshInstance3D = _roads.get(id)
	if view == null:
		view = MeshInstance3D.new()
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.custom_aabb = AABB(Vector3(-20000, -100, -20000), Vector3(40000, 4000, 40000))
		add_child(view)
		_roads[id] = view
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i].distance_to(points[i - 1])
	view.mesh = _band(points)
	view.material_override = _preview if preview else _casing
	view.set_instance_shader_parameter("built_km", 1.0e6 if preview else clampf(progress, 0.0, 1.0) * length)
	view.set_instance_shader_parameter("state", (2.0 if blocked else 1.0) if preview else 0.0)
	view.set_instance_shader_parameter("order", float(absi(hash(id)) % 1000) / 1000.0)

func remove_road(id: Variant) -> void:
	var view: MeshInstance3D = _roads.get(id)
	if view != null:
		view.queue_free()
		_roads.erase(id)

func _process(_delta: float) -> void:
	if _roads.is_empty():
		return
	# the terrain's zoom level, relief and patch, only what changed
	var source: ShaderMaterial = terrain._terrain_material
	for key in _shared:
		var value = source.get_shader_parameter(key)
		if _shared_values.has(key) and typeof(_shared_values[key]) == typeof(value) and _shared_values[key] == value:
			continue
		_shared_values[key] = value
		for m in [_casing, _fill, _preview]:
			m.set_shader_parameter(key, value)
	var px_km: float = landscape.width / maxf(get_viewport().get_visible_rect().size.x, 1.0)
	for m in [_casing, _fill, _preview]:
		m.set_shader_parameter("min_half_km", px_km * MIN_PX)

## The band along `points`: per step a pair of vertices on the middle line
## with the way to either edge (UV2), mitred at the bends, and a round cap
## at each end. See road.gdshaderinc for the layout.
static func _band(points: PackedVector2Array) -> ArrayMesh:
	var line := PackedVector2Array()
	for i in points.size():
		if i == 0:
			line.append(points[0])
			continue
		var a := points[i - 1]
		var b := points[i]
		var n := maxi(1, ceili(a.distance_to(b) / STEP_KM))
		for k in range(1, n + 1):
			line.append(a.lerp(b, float(k) / n))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if line.size() < 2:
		return st.commit()
	var along := PackedFloat32Array([0.0])
	for i in range(1, line.size()):
		along.append(along[i - 1] + line[i].distance_to(line[i - 1]))
	var sides := PackedVector2Array()
	for i in line.size():
		var d0 := (line[i] - line[maxi(i - 1, 0)]).normalized()
		var d1 := (line[mini(i + 1, line.size() - 1)] - line[i]).normalized()
		var d := (d0 + d1).normalized() if (d0 + d1).length_squared() > 1e-8 else d1
		var side := Vector2(-d.y, d.x)
		# mitre: wider at a bend so the band keeps its width, at most twice
		var c := side.dot(Vector2(-d1.y, d1.x)) if i < line.size() - 1 else 1.0
		sides.append(side / clampf(c, 0.5, 1.0))
	for i in range(line.size() - 1):
		var quad := [[i, -1.0], [i, 1.0], [i + 1, 1.0], [i, -1.0], [i + 1, 1.0], [i + 1, -1.0]]
		for q in quad:
			_vertex(st, line[q[0]], sides[q[0]] * q[1], along[q[0]], q[1])
	# round caps: a fan from the end point, out along the road
	for end in [0, line.size() - 1]:
		var out := (line[0] - line[1]).normalized() if end == 0 else (line[end] - line[end - 1]).normalized()
		var side := Vector2(-out.y, out.x)
		for k in CAP_SIDES:
			var a0 := PI * float(k) / CAP_SIDES
			var a1 := PI * float(k + 1) / CAP_SIDES
			var e0 := side * cos(a0) + out * sin(a0)
			var e1 := side * cos(a1) + out * sin(a1)
			_vertex(st, line[end], Vector2.ZERO, along[end], 0.0)
			_vertex(st, line[end], e0, along[end], 1.0)
			_vertex(st, line[end], e1, along[end], 1.0)
	return st.commit()

static func _vertex(st: SurfaceTool, at: Vector2, edge: Vector2, along: float, across: float) -> void:
	st.set_uv(Vector2(along, across))
	st.set_uv2(edge)
	st.add_vertex(Vector3(at.x, 0.0, at.y))
