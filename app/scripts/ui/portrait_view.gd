extends Control
## A person's portrait (docs/kit2/PORTRAITS.md): head and shoulders as
## portrait_cache.gd renders and keeps them, drawn under an arch with a
## gold rim, on the background of the person's stand. 112 x 140 at scale
## 1 (the person window); lists scale it down (`scale`) and thicken the rim
## (`rim`) to stay visible.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const PortraitCache = preload("res://scripts/ui/portrait_cache.gd")
const SIZE := Vector2(112, 140) # the Werkstatt's 4:5
const ARCH_STEPS := 24

var rim := 1.0 # the rim's width as a share of its width at scale 1
var _bg: Array = [Color("5d6440"), Color("2b2e1f")]
var _texture: Texture2D # the face, once rendered
var _want := "" # the face asked for last; an older one arriving late is dropped

func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## Shows the portrait of `p` (people_dots.rs take_person, or a face of
## take_faces): the arch at once, the face when it is rendered. False when
## there is none to show (no genes, no extension, no head file).
func show_person(p: Dictionary) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	_want = PortraitCache.key_of(p)
	_texture = null
	queue_redraw()
	return PortraitCache.of(tree).face(p, _got.bind(_want))

func _got(face: Dictionary, key: String) -> void:
	if key != _want:
		return
	_texture = face.texture
	_bg = face.bg
	queue_redraw()

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
	if _texture != null:
		var uvs := PackedVector2Array()
		for q in pts:
			uvs.append(q / SIZE)
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, _texture)
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, UiStyle.EDGE, 3.0 * rim, true)
	draw_polyline(ring, UiStyle.GOLD, 1.5 * rim, true)
