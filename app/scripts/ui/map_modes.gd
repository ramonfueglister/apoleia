extends Control
## The map modes, as Victoria 3's: a row of medallions on a strip of
## leather at the foot of the screen, the mode shown lit in gold, its name
## at the left. Each mode colours the regions of the markets by one column
## of the markets table (sim_tables.gd, «Karte färben»), whose legend
## then sits above the strip; the landscape shows the map without colour. It only shows and tells: chosen(column)
## goes to the game clock (sim/game_clock.gd), which colours the map.

const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const NoticeList = preload("res://scripts/ui/notice_list.gd")
const SIZE_PX := 46.0
## room kept at the right for the notices (sim/sim_events.gd sets them 18
## from the edge)
const NOTICES_PX := NoticeList.WIDTH + 18.0 + 16.0
## column of the markets table ("" none), icon, name
const MODES := [
	["", "mountains", "Landschaft"],
	["persons", "family-house", "Menschen"],
	["price", "wheat", "Kornpreis"],
	["share_hungry", "knife-fork", "Hungernd"],
	["tent_persons", "camping-tent", "Im Zelt"],
	["store_kg", "granary", "Korn auf dem Markt"],
	["free_ha", "field", "Freies Land"],
	["money", "two-coins", "Geld der Händler"],
]

signal chosen(column: String)

var _buttons: Array = []
var _name: Label
var _row: HBoxContainer
var _shown := "-"

func _init() -> void:
	name = "MapModes"
	theme = Vic3.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_name = Vic3.label("", Vic3.TEXT, Vic3.SIZE_TEXT, Vic3.title_font())
	_name.custom_minimum_size.x = 170
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_name)
	for m in MODES:
		var b := Vic3.Medallion.new(m[1], "Karte: %s" % m[2], SIZE_PX)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var column: String = m[0]
		b.pressed.connect(func(): chosen.emit(column))
		_row.add_child(b)
		_buttons.append(b)
	_row.resized.connect(_fit)
	show_mode("")

func _fit() -> void:
	custom_minimum_size = _row.size + Vector2(36, 16)
	size = custom_minimum_size
	var screen := get_viewport_rect().size
	var x := minf((screen.x - size.x) * 0.5, screen.x - NOTICES_PX - size.x) # centred, clear of the notices
	position = Vector2(maxf(x, 12.0), screen.y - size.y - 10.0)
	_row.position = Vector2(18, 8)
	queue_redraw()

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

## The leather strip, rounded at its ends, in a gold rim.
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 4)
	box.set_corner_radius_all(int(size.y * 0.5))
	draw_style_box(box, r)
	var plain := StyleBoxFlat.new()
	plain.bg_color = Vic3.BAND
	plain.set_corner_radius_all(int(size.y * 0.5))
	plain.border_color = Vic3.GOLD
	plain.set_border_width_all(2)
	plain.anti_aliasing = true
	draw_style_box(plain, r)
	var inner := r.grow(-3.0)
	if Vic3.leather() != null:
		draw_texture_rect(Vic3.leather(), Rect2(inner.position + Vector2(inner.size.y * 0.5, 0), inner.size - Vector2(inner.size.y, 0)), true, Color(1, 1, 1, 0.9))
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(0, 0, 0, 0)
	ring.border_color = Vic3.RING
	ring.set_border_width_all(1)
	ring.set_corner_radius_all(int(size.y * 0.5) + 2)
	ring.anti_aliasing = true
	draw_style_box(ring, r.grow(2.0))

## Lights the mode of `column` ("" the landscape) and names it.
func show_mode(column: String) -> void:
	if column == _shown:
		return
	_shown = column
	var known := false
	for i in MODES.size():
		var b: Vic3.Medallion = _buttons[i]
		b.on = MODES[i][0] == column
		known = known or b.on
		b.queue_redraw()
	_name.text = "Karte: " + (MODES.filter(func(m): return m[0] == column)[0][2] if known else column)
