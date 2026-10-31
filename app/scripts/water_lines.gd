extends SubViewport
## Rivers and lakes of the 0.5 and 1 km tiles by their real lines (graphics
## round Q). There a river was a band from tile centre to tile centre, cut
## straight across each bend, and a lake a staircase of whole tiles. The
## smoothed Natural Earth lines (tools/build_tile_terrain.py, water-lines.bin)
## are drawn into this picture of the drawn patch instead, once whenever the
## patch leaves it: R river water, G lake water, B the river's bank. The
## terrain and the tree slots read it (tile_terrain.gdshaderinc,
## tt_water_lines); towns keep the river on its tiles, where their bridges
## and quays stand.

const SIZE := 4096 # pixels a side (about 15 m each at the 0.5 km tiles, 60-100 m at the 1 km tiles)
const MARGIN := 0.15 # the picture reaches this share of the patch beyond each side
const LAKE := 100 # line kinds (build_tile_terrain.py WATER_LAKE, WATER_ISLAND); a river: its rank
const ISLAND := 101
const BANK_KM := 0.015 # the bank's seam beside the water

## The ground the picture covers now (world km).
var rect := Rect2()

var _kinds := PackedInt32Array()
var _bounds: Array[Rect2] = []
var _points: Array[PackedVector2Array] = []
var _triangles := {} # lake or island line -> its triangles (indices into its points)
var _layers: Array[Node2D] = []

## Reads water-lines.bin (an older bake without it: false, the tile bands
## stay) and cuts the lakes into triangles (about 0.15 s; on a worker thread
## while the terrain loads).
func read(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8 or bytes.slice(0, 4).get_string_from_ascii() != "WLN1":
		return false
	var count := bytes.decode_u32(4)
	var at := 8
	for i in count:
		var n := bytes.decode_s32(at + 4)
		_kinds.append(bytes.decode_s32(at))
		var lo := Vector2(bytes.decode_float(at + 8), bytes.decode_float(at + 12))
		_bounds.append(Rect2(lo, Vector2(bytes.decode_float(at + 16), bytes.decode_float(at + 20)) - lo))
		_points.append(_vectors(bytes.slice(at + 24, at + 24 + 8 * n), n))
		if _kinds[i] >= LAKE:
			# (a ring it cannot cut, a few tiny ones, is drawn as its outline)
			_triangles[i] = Geometry2D.triangulate_polygon(_points[i])
		at += 24 + 8 * n
	return at == bytes.size()

## n float32 pairs as a PackedVector2Array: decoded as a whole by the engine
## (a Variant header before the floats), else one by one.
static func _vectors(floats: PackedByteArray, n: int) -> PackedVector2Array:
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, TYPE_PACKED_VECTOR2_ARRAY)
	head.encode_u32(4, n)
	var v: Variant = bytes_to_var(head + floats)
	if v is PackedVector2Array and v.size() == n:
		return v
	var out := PackedVector2Array()
	out.resize(n)
	for k in n:
		out[k] = Vector2(floats.decode_float(8 * k), floats.decode_float(8 * k + 4))
	return out

func _ready() -> void:
	size = Vector2i(SIZE, SIZE)
	transparent_bg = true
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	# one layer per channel, added up (an island's taken off the lakes')
	for blend in [CanvasItemMaterial.BLEND_MODE_ADD, CanvasItemMaterial.BLEND_MODE_SUB, CanvasItemMaterial.BLEND_MODE_ADD, CanvasItemMaterial.BLEND_MODE_ADD]:
		var layer := Node2D.new()
		var material := CanvasItemMaterial.new()
		material.blend_mode = blend
		layer.material = material
		layer.draw.connect(_draw_layer.bind(_layers.size()))
		add_child(layer)
		_layers.append(layer)

## Redraws the picture when `patch` (world km) leaves it, or when it is more
## than twice as large as the patch (zoomed in); true if it did.
func cover(patch: Rect2) -> bool:
	var side := maxf(patch.size.x, patch.size.y) * (1.0 + 2.0 * MARGIN)
	if rect.has_area() and rect.encloses(patch) and rect.size.x <= 2.0 * side:
		return false
	rect = Rect2(patch.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	for layer in _layers:
		layer.queue_redraw()
	render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

## Layers: 0 lakes, 1 their islands, 2 the river banks, 3 the rivers.
func _draw_layer(which: int) -> void:
	var layer := _layers[which]
	var s := float(SIZE) / rect.size.x # pixels per km
	var to_px := Transform2D(0.0, Vector2(s, s), 0.0, -rect.position * s)
	var seen := rect.grow(0.5)
	for i in _kinds.size():
		var kind := _kinds[i]
		var lake := kind >= LAKE
		if lake != (which <= 1) or (which == 0 and kind != LAKE) or (which == 1 and kind != ISLAND):
			continue
		if not seen.intersects(_bounds[i]):
			continue
		var px := to_px * _points[i]
		if lake:
			var colour := Color(0.0, 1.0, 0.0)
			var tris: PackedInt32Array = _triangles[i]
			if tris.size() > 0:
				RenderingServer.canvas_item_add_triangle_array(layer.get_canvas_item(), tris, px, PackedColorArray([colour]))
			# the outline antialiased (and a ring the triangulation could not take at least as its outline)
			px.append(px[0])
			layer.draw_polyline(px, colour, 1.0, true)
			continue
		# a boat wide or more, the big rivers wider, and at least two pixels
		var half := maxf((0.10 if kind <= 4 else 0.075 if kind <= 8 else 0.055) * s, 1.0)
		if which == 2:
			half += maxf(BANK_KM * s, 0.75)
		var colour := Color(1.0, 0.0, 0.0) if which == 3 else Color(0.0, 0.0, 1.0)
		layer.draw_polyline(px, colour, 2.0 * half, true)
		# round ends
		layer.draw_circle(px[0], half, colour, true, -1.0, true)
		layer.draw_circle(px[px.size() - 1], half, colour, true, -1.0, true)
