extends Control
## The bar along the top of the game, as Victoria 3's: a band of grained
## green slate with a gold edge below, at its left a large red seal
## (SPQR) that opens the statistics, beside it the figures of the realm,
## each a small gem with its icon, the value large and its name below, at
## the right a plate of leather with the date, the speed as pips and the
## round pause button, quick save and load. It only shows what it is
## told; the game clock (sim/game_clock.gd) fills it and acts on its signals.

const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const HEIGHT := 54.0
const SEAL_PX := 78.0
const GEM_PX := 34.0
const TEXTURE := "res://assets/ui/leiste.png"

signal seal_pressed
signal speed_chosen(kind: int) # 0 pause or run on, 1-4 a speed
signal save_pressed
signal load_pressed

var _figures: HBoxContainer
var _cells := {} # key -> {value: Label, caption: Label, cell: Control}
var _plate: HBoxContainer
var _date: Label
var _pips: Pips
var _pause: Vic3.Medallion
var _texture: Texture2D

func _init() -> void:
	name = "TopBar"
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size.y = HEIGHT
	offset_bottom = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP # the map below takes no clicks through the bar
	theme = Vic3.theme()
	if ResourceLoader.exists(TEXTURE):
		_texture = load(TEXTURE)
	_figures = HBoxContainer.new()
	_figures.add_theme_constant_override("separation", 22)
	_figures.set_anchors_preset(Control.PRESET_FULL_RECT)
	_figures.offset_left = 12 + SEAL_PX + 22
	_figures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_figures)
	_plate = HBoxContainer.new()
	_plate.add_theme_constant_override("separation", 10)
	_plate.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_plate.alignment = BoxContainer.ALIGNMENT_END
	_plate.offset_right = -12
	_plate.resized.connect(queue_redraw)
	add_child(_plate)
	var when := VBoxContainer.new()
	when.alignment = BoxContainer.ALIGNMENT_CENTER
	when.add_theme_constant_override("separation", 3)
	_plate.add_child(when)
	_date = Vic3.label("", Vic3.TEXT, Vic3.SIZE_TEXT)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_date.custom_minimum_size.x = 200
	when.add_child(_date)
	_pips = Pips.new()
	_pips.size_flags_horizontal = Control.SIZE_SHRINK_END
	_pips.chosen.connect(func(k: int): speed_chosen.emit(k))
	when.add_child(_pips)
	_pause = Vic3.Medallion.new("pause-button", "Pause  (Leertaste)", 42.0)
	_pause.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pause.pressed.connect(func(): speed_chosen.emit(0))
	_plate.add_child(_pause)
	var save := Vic3.Medallion.new("save", "Schnell speichern  (F8)", 32.0)
	save.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save.pressed.connect(func(): save_pressed.emit())
	_plate.add_child(save)
	var open := Vic3.Medallion.new("open-book", "Schnell laden  (F9)", 32.0)
	open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open.pressed.connect(func(): load_pressed.emit())
	_plate.add_child(open)
	var seal := Seal.new()
	seal.position = Vector2(12, 3)
	seal.pressed.connect(func(): seal_pressed.emit())
	add_child(seal)
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(size.x, HEIGHT))
	# a soft shadow on the map below
	for k in 6:
		draw_rect(Rect2(0, HEIGHT + k * 2.0, size.x, 2.0), Color(0, 0, 0, 0.3 - k * 0.05))
	if _texture != null:
		draw_texture_rect(_texture, r, true)
	else:
		draw_rect(r, Color("3a4243"))
	Vic3._sheen(self, r, 0.10, 0.30)
	# the leather plate behind the date
	var plate := Rect2(_plate.position.x - 18.0, 0, size.x - _plate.position.x + 18.0, HEIGHT)
	Vic3._tiled(self, plate, Vic3.leather(), Vic3.BAND)
	Vic3._sheen(self, plate, 0.10, 0.35)
	draw_line(plate.position, Vector2(plate.position.x, HEIGHT), Vic3.GOLD, 2.0)
	draw_line(Vector2(0, HEIGHT - 1), Vector2(size.x, HEIGHT - 1), Vic3.GOLD, 2.0)
	draw_line(Vector2(0, HEIGHT + 1), Vector2(size.x, HEIGHT + 1), Vic3.RING, 1.0)

## One figure: `key` names it, `icon` from assets/ui/icons, `value` large,
## `caption` small below; `colour` for the value (gains, losses), `tip` on hover.
func set_figure(key: String, icon_name: String, value: String, caption: String, colour := Vic3.TEXT, tip := "") -> void:
	if not _cells.has(key):
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var gem := Gem.new(icon_name)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(gem)
		var lines := VBoxContainer.new()
		lines.alignment = BoxContainer.ALIGNMENT_CENTER
		lines.add_theme_constant_override("separation", -4)
		lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(lines)
		var v := Vic3.label("", Vic3.TEXT, Vic3.SIZE_TEXT + 2, Vic3.bold())
		var c := Vic3.label("", Vic3.DIM, Vic3.SIZE_SMALL - 1, Vic3.italic())
		lines.add_child(v)
		lines.add_child(c)
		_figures.add_child(cell)
		_cells[key] = {"value": v, "caption": c, "cell": cell}
	var e: Dictionary = _cells[key]
	(e.value as Label).text = value
	(e.value as Label).add_theme_color_override("font_color", colour)
	(e.caption as Label).text = caption
	(e.cell as Control).tooltip_text = tip

## The date, the speed lit (1-4) and whether the game stands; `warn` gilds
## the date when the sim falls behind.
func set_clock(date: String, paused: bool, speed: int, warn := false) -> void:
	_date.text = date
	_date.add_theme_color_override("font_color", Vic3.GOLD_LIT if warn else Vic3.TEXT)
	_pips.lit = 0 if paused else speed
	_pips.queue_redraw()
	var pause_tip := "Weiter  (Leertaste)" if paused else "Pause  (Leertaste)"
	if _pause.tooltip_text != pause_tip:
		_pause.tooltip_text = pause_tip
		_pause._icon = Vic3.icon("play-button" if paused else "pause-button")
		_pause.queue_redraw()

## The large red seal at the left, overhanging the bar.
class Seal extends Button:
	const V = preload("res://scripts/ui/vic3_style.gd")
	var _icon: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(78, 78)
		size = custom_minimum_size
		tooltip_text = "Statistik  (T)"
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		_icon = V.icon("eagle-emblem")
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var lit := is_hovered()
		var c := size * 0.5
		var r := size.x * 0.5 - 3.0
		draw_circle(c + Vector2(0, 3), r + 2.0, Color(0, 0, 0, 0.45))
		if lit:
			for i in 4:
				draw_circle(c, r + 2.0 + i * 1.5, Color(1.0, 0.84, 0.56, 0.10 - i * 0.02))
		draw_circle(c, r + 2.0, V.RING)
		draw_circle(c, r, V.GOLD_LIT if lit else V.GOLD)
		draw_circle(c, r - 4.0, V.RING)
		var dark := Color("1c0c0f")
		var light := Color("7a3440")
		draw_circle(c, r - 5.0, dark)
		draw_circle(c + Vector2(0, -r * 0.2), (r - 5.0) * 0.8, dark.lerp(light, 0.45))
		draw_circle(c + Vector2(0, -r * 0.33), (r - 5.0) * 0.5, dark.lerp(light, 0.8))
		draw_arc(c, r - 7.0, PI * 1.1, PI * 1.9, 32, Color(1, 1, 1, 0.18), 2.0, true)
		var ink := Color("fff1c8") if lit else Color("ecdcae")
		if _icon != null:
			var s := r * 0.95
			draw_texture_rect(_icon, Rect2(c - Vector2(s * 0.5, s * 0.62), Vector2(s, s)), false, ink)
		var f := V.title_font()
		draw_string(f, Vector2(0, c.y + r * 0.62), "SPQR", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, ink)

## A small dark gem with an icon in gold, before a figure.
class Gem extends Control:
	const V = preload("res://scripts/ui/vic3_style.gd")
	var _icon: Texture2D

	func _init(icon_name: String) -> void:
		custom_minimum_size = Vector2(34, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon = V.icon(icon_name)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, V.RING)
		draw_circle(c, r - 1.0, V.GOLD_DIM)
		draw_circle(c, r - 2.0, Color("1c1b18"))
		draw_circle(c + Vector2(0, -r * 0.25), r * 0.6, Color("3a372f"))
		if _icon != null:
			var s := r * 1.25
			draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, V.GOLD_LIT)

## The speeds as four pips, lit up to the one running; a click on a pip
## chooses its speed.
class Pips extends Control:
	const V = preload("res://scripts/ui/vic3_style.gd")
	const N := 4
	const W := 14.0
	const H := 7.0
	const GAP := 4.0
	signal chosen(kind: int)
	var lit := 0

	func _init() -> void:
		custom_minimum_size = Vector2(N * W + (N - 1) * GAP, H + 2.0)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Tempo  ([ ])"

	func _draw() -> void:
		for k in N:
			var r := Rect2(k * (W + GAP), 1.0, W, H)
			draw_rect(r.grow(1.0), V.RING)
			draw_rect(r, V.GOLD_LIT if k < lit else Color("4a4a40"))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(clampi(int(event.position.x / (W + GAP)) + 1, 1, N))
			accept_event()
