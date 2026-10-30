extends Control
## A person's portrait (docs/kit2/PORTRAITS.md): head and shoulders built in
## Rust from the person's genes and life (ApoleiaPortrait,
## sim/godot/src/portrait.rs), lit in a small 3D world of its own as in the
## Portrait-Werkstatt: a warm key light with shadows from the upper left, a
## cool rim light from behind on the right, a weak warm fill, sky above and
## earth below. Drawn under an arch with a gold rim, on the background of
## the person's stand.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HEAD_FILE := "res://assets/portrait/head.bin.zst"
const SIZE := Vector2(112, 140) # the Werkstatt's 4:5
const SUPER := 2 # rendered at twice the size, for clean edges
const TURN := -0.35 # turned a little to the left, as in the Werkstatt
const LOD := 1 # about 3000 triangles of skin: plenty at this size
const ARCH_STEPS := 24

var _builder # ApoleiaPortrait, while the extension is there
var _vp: SubViewport
var _pivot: Node3D
var _mesh: MeshInstance3D
var _cam: Camera3D
var _key: DirectionalLight3D
var _rim: DirectionalLight3D
var _fill: DirectionalLight3D
var _bg: Array = [Color("5d6440"), Color("2b2e1f")]

func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE) * SUPER
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("e6ecff")
	sky_mat.sky_horizon_color = Color("e6ecff").lerp(Color("5a3d2a"), 0.5)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color("5a3d2a")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	# the Werkstatt's ACES (three.js r128: exposure 0.92 / 0.6, no white
	# point) in Godot's (exposure x 1.8, divided by the white point's value;
	# that value is 1 at a white of 14.26)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92 / 0.6 / 1.8
	env.tonemap_white = 14.26
	var world := WorldEnvironment.new()
	world.environment = env
	_vp.add_child(world)
	_key = _light(Color("fff0dc"), 2.0)
	_key.shadow_enabled = true
	_key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_key.directional_shadow_max_distance = 30.0
	_rim = _light(Color("bcd0ff"), 1.4)
	_fill = _light(Color("ffe2c8"), 0.35)
	_cam = Camera3D.new()
	_cam.fov = 22.0
	_cam.near = 0.1
	_cam.far = 100.0
	_vp.add_child(_cam)
	_cam.current = true
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_mesh = MeshInstance3D.new()
	_pivot.add_child(_mesh)

func _light(colour: Color, energy: float) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.light_color = colour
	l.light_energy = energy
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_vp.add_child(l)
	return l

## Builds and shows the portrait of `p` (people_dots.rs take_person); false
## when there is none to show (no genes, no extension, no head file).
func show_person(p: Dictionary) -> bool:
	if not p.has("dna") or not ClassDB.class_exists("ApoleiaPortrait"):
		return false
	if _builder == null:
		_builder = ClassDB.instantiate("ApoleiaPortrait")
	if not _builder.is_loaded():
		var bytes := FileAccess.get_file_as_bytes(HEAD_FILE)
		if bytes.is_empty() or not _builder.load(bytes):
			return false
	var d: Dictionary = _builder.build(p.dna, bool(p.female), float(p.age), int(p.stand), str(p.job), int(p.health), int(p.get("fed", 1000)), int(p.pid), str(p.get("origin", "")), LOD)
	if d.is_empty():
		return false
	_mesh.mesh = d.mesh
	_bg = d.bg
	_frame(d)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()
	return true

## The Werkstatt's framing: the head from the chin to above the crown (or
## hat) fills about half the height (`fill`, more for a small child), the
## eyes a little above the middle.
func _frame(d: Dictionary) -> void:
	var cx: float = d.cx
	var cz: float = d.cz
	var h := maxf(0.8, float(d.top) - float(d.chin))
	var hv := h / float(d.get("fill", 0.53))
	var cy: float = float(d.top) - 0.36 * hv
	var dist := (hv * 0.5) / tan(deg_to_rad(11.0))
	_pivot.position = Vector3(cx, 0.0, cz)
	_pivot.rotation.y = TURN
	_mesh.position = Vector3(-cx, 0.0, -cz)
	var at := Vector3(cx, cy, cz)
	_aim(_cam, Vector3(cx, cy + 0.08 * hv, cz + dist), at)
	_aim(_key, at + Vector3(-3.5, 4.5, 5.0), at)
	_aim(_rim, at + Vector3(3.5, 2.5, -4.0), at)
	_aim(_fill, at + Vector3(3.0, -1.0, 5.0), at)

## Puts `node` (a child of the viewport, so local is global) at `from`,
## looking (-Z) at `to`.
static func _aim(node: Node3D, from: Vector3, to: Vector3) -> void:
	node.transform = Transform3D(Basis.looking_at(to - from, Vector3.UP), from)

## The arch: straight sides, a half circle on top.
func _outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := SIZE.x * 0.5
	pts.append(Vector2(0.0, SIZE.y))
	pts.append(Vector2(SIZE.x, SIZE.y))
	for k in ARCH_STEPS + 1:
		var a := PI * float(k) / ARCH_STEPS
		pts.append(Vector2(r + r * cos(a), r - r * sin(a)))
	return pts

func _draw() -> void:
	var pts := _outline()
	# the stand's background, lighter around the head (the Werkstatt's
	# radial gradient as a fan)
	var centre := Vector2(SIZE.x * 0.5, SIZE.y * 0.35)
	var reach := SIZE.y * 0.8
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var ca: Color = _bg[0].lerp(_bg[1], clampf(a.distance_to(centre) / reach, 0.0, 1.0))
		var cb: Color = _bg[0].lerp(_bg[1], clampf(b.distance_to(centre) / reach, 0.0, 1.0))
		draw_polygon(PackedVector2Array([centre, a, b]), PackedColorArray([_bg[0], ca, cb]))
	# the portrait, cut to the arch
	var uvs := PackedVector2Array()
	for q in pts:
		uvs.append(q / SIZE)
	draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, _vp.get_texture())
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, UiStyle.EDGE, 3.0, true)
	draw_polyline(ring, UiStyle.GOLD, 1.5, true)

