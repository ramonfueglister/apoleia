extends Node
## The faces of the people (docs/kit2/PORTRAITS.md), rendered once and
## kept, for the person window, the household list, event windows and
## notices (portrait_view.gd draws them under their arch). Head and
## shoulders are built in Rust from the person's genes and life
## (ApoleiaPortrait, sim/godot/src/portrait.rs) and lit in a small 3D world
## of its own as in the Portrait-Werkstatt: a warm key light with shadows
## from the upper left, a cool rim light from behind on the right, a weak
## warm fill, sky above and earth below. One face a frame; each is kept as
## a texture with mipmaps (sharp at a third of its size too), the last
## KEEP of them.
##
##   PortraitCache.of(tree).face(person, callable)  # callable(face) once,
##   # face = {"texture": Texture2D, "bg": [inner, outer]}; false: no face
##
## Two looks (settings «Echte Porträts», ui/game_settings.gd): the simple
## one, and the real one with skin, eyes, hair, beards and clothes from the
## realism pipeline (files in REAL_DIR, apoleia_portrait::real). The files
## are read straight from the project folder, so the real look needs the
## game started from its sources (as now), not an exported build.

const HEAD_FILE := "res://assets/portrait/head.bin.zst"
const SIZE := Vector2i(224, 280) # portrait_view.gd's 112 x 140, twice for clean edges
const TURN := -0.35 # turned a little to the left, as in the Werkstatt
const LOD := 1 # about 3000 triangles of skin: plenty at this size
const KEEP := 64
const REAL_DIR := "res://assets/portrait/real"
const STORE := "user://display.cfg" # [portraits] real, as game_settings.gd keeps it

var _builder # ApoleiaPortrait, while the extension is there
var _vp: SubViewport
var _pivot: Node3D
var _mesh: MeshInstance3D
var _cam: Camera3D
var _key: DirectionalLight3D
var _rim: DirectionalLight3D
var _fill: DirectionalLight3D
var _faces := {} # key -> face
var _order: Array[String] = [] # keys, the last used last
var _queue: Array[Dictionary] = [] # {key, person, done: Array[Callable]}
var _jobs := {} # key -> its job, queued or rendering
var _busy := {} # the job rendering now

## The cache of the running game (made on first use, under the root).
static func of(tree: SceneTree) -> Node:
	var c = tree.root.get_meta("portrait_cache") if tree.root.has_meta("portrait_cache") else null
	if not is_instance_valid(c):
		c = load("res://scripts/ui/portrait_cache.gd").new()
		c.name = "PortraitCache"
		tree.root.set_meta("portrait_cache", c)
		tree.root.add_child.call_deferred(c)
	return c

## What changes a face: the person and their look, age in years, mourning
## by weeks, food, clothing and wealth by steps.
static func key_of(p: Dictionary) -> String:
	return "%d|%s|%d|%d|%d|%d|%d|%d|%d" % [int(p.get("pid", -1)), str(p.get("job", "")), int(p.get("stand", 0)),
		int(float(p.get("age", 0.0))), int(p.get("loss_days", -7)) / 7, int(p.get("health", 1000)) / 25,
		1 if int(p.get("fed", 1000)) < 900 else 0, mini(int(p.get("clothes_pct", 100)), 100) / 10,
		int(float(p.get("rank_market", p.get("rank_all", 0.5))) * 10.0)]

## Calls `done` with the face of `p` (people_dots.rs take_person, or a
## face of take_faces): at once if it is kept, else once it is rendered.
## False when there is none to show (no genes, no extension, no head file).
func face(p: Dictionary, done: Callable) -> bool:
	if not p.has("dna") or not _ready_to_build():
		return false
	var key := key_of(p)
	if _faces.has(key):
		_order.erase(key)
		_order.append(key)
		done.call(_faces[key])
		return true
	if _jobs.has(key):
		_jobs[key].done.append(done)
		return true
	var job := {"key": key, "person": p, "done": [done]}
	_jobs[key] = job
	_queue.append(job)
	return true

## Whether the real look is chosen (off until switched on).
static func real_on() -> bool:
	var config := ConfigFile.new()
	return config.load(STORE) == OK and bool(config.get_value("portraits", "real", false))

## Switches the real look on or off: the faces kept are dropped and drawn
## anew when they are next asked for.
func set_real(on: bool) -> void:
	if _builder != null:
		_tell_look(on)
	_faces.clear()
	_order.clear()

func _tell_look(on: bool) -> void:
	# (an extension built before the real look has no set_real)
	if _builder.has_method("set_real"):
		_builder.set_real(ProjectSettings.globalize_path(REAL_DIR) if on and DirAccess.dir_exists_absolute(REAL_DIR) else "")

func _ready_to_build() -> bool:
	if not ClassDB.class_exists("ApoleiaPortrait"):
		return false
	if _builder == null:
		_builder = ClassDB.instantiate("ApoleiaPortrait")
		_tell_look(real_on())
	if not _builder.is_loaded():
		var bytes := FileAccess.get_file_as_bytes(HEAD_FILE)
		if bytes.is_empty() or not _builder.load(bytes):
			return false
	return true

func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = SIZE
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

## The next face in the queue: built, framed and rendered this frame,
## taken after it is drawn (`_grab`).
func _process(_dt: float) -> void:
	while _busy.is_empty() and not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var d: Dictionary = _builder.build(job.person, LOD)
		if d.is_empty():
			_jobs.erase(job.key)
			continue
		_mesh.mesh = d.mesh
		job.bg = d.bg
		_frame(d)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_busy = job
		RenderingServer.frame_post_draw.connect(_grab, CONNECT_ONE_SHOT)

func _grab() -> void:
	var job := _busy
	_busy = {}
	_jobs.erase(job.key)
	var img := _vp.get_texture().get_image()
	img.generate_mipmaps()
	var face := {"texture": ImageTexture.create_from_image(img), "bg": job.bg}
	_faces[job.key] = face
	_order.append(job.key)
	while _order.size() > KEEP:
		_faces.erase(_order.pop_front())
	for done: Callable in job.done:
		if done.is_valid():
			done.call(face)

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
