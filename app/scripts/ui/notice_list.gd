extends PanelContainer
## The list of notices at the bottom right, in the Victoria 3 look of
## ui/vic3_style.gd: a slate panel in a gold rim under a band of wine-red
## leather with the title, the game date and a red medallion that folds
## it away. Each notice is a dark green row: a small medallion with the
## icon of its kind in the kind's colour, the day, the text, lit gold
## under the mouse; its star at the right asks to pin it in the outliner
## (ui/outliner.gd). The cog in the band opens the settings at «Meldungen»
## (ui/pause_menu.gd show_settings). It only shows rows; what they are and
## what a click does is up to its owner (sim/sim_events.gd).

const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const WIDTH := 400.0
const BAND_PX := 40.0

signal chosen(entry: Dictionary)
signal pin_asked(entry: Dictionary)
signal closing

var stand: Label # the game date, at the right of the band
var list: VBoxContainer
var _bar: Control

func _init() -> void:
	add_to_group("notice_list") # the outliner above keeps clear of it
	theme = Vic3.theme()
	custom_minimum_size.x = WIDTH
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_bar = Control.new()
	_bar.custom_minimum_size.y = BAND_PX
	_bar.draw.connect(_draw_band)
	column.add_child(_bar)
	var head := HBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_FULL_RECT)
	head.offset_left = 14
	head.offset_right = -8
	head.add_theme_constant_override("separation", 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(head)
	var title := Vic3.title_label("Ereignisse", 22)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.text = title.text.replace("[center]", "").replace("[/center]", "")
	title.custom_minimum_size.x = 150 # fit_content alone leaves it no width in a row
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	stand = Vic3.label("", Vic3.DIM, Vic3.SIZE_SMALL, Vic3.italic())
	stand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(stand)
	# which kinds open a window, stay a line or pause: the settings' page «Meldungen»
	var cog := Vic3.Medallion.new("cog", "Meldungen einstellen", 28.0)
	cog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cog.pressed.connect(func(): get_tree().call_group("pause_menu", "show_settings", 1))
	head.add_child(cog)
	var close := Vic3.Medallion.new("", "Ausblenden  (E)", 28.0, true)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): closing.emit())
	head.add_child(close)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	column.add_child(pad)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	pad.add_child(list)
	resized.connect(queue_redraw)

func _draw() -> void:
	Vic3.draw_panel(self, Rect2(Vector2.ZERO, size))

func _draw_band() -> void:
	Vic3.draw_band(_bar, Rect2(Vector2(2, 2), _bar.size - Vector2(4, 2)))

## The rows, newest first: each {day, text, colour, icon, entry}; a click
## on one emits chosen(entry).
func show_rows(rows: Array) -> void:
	_clear()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var row := Row.new(r.get("day", ""), r.get("text", ""), r.get("colour", Vic3.TEXT), r.get("icon", ""), i % 2 == 1)
		var entry: Dictionary = r.get("entry", {})
		row.pressed.connect(func(): pin_asked.emit(entry) if row.on_star() else chosen.emit(entry))
		list.add_child(row)

## No rows: one quiet line instead.
func show_quiet(text: String) -> void:
	_clear()
	var quiet := Vic3.label(text, Vic3.DIM, Vic3.SIZE_SMALL + 1, Vic3.italic())
	quiet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiet.custom_minimum_size.x = WIDTH - 20.0 # wraps at its width at once, not a letter a line until laid out
	list.add_child(quiet)

func _clear() -> void:
	for child in list.get_children():
		child.free()

## The small button that brings the list back: the scroll in gold.
static func open_button() -> Button:
	var b := Vic3.button("Ereignisse  (E)", "scroll-unfurled")
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.theme = Vic3.theme()
	return b

## One notice: a dark green row, the kind's medallion, the day and the text.
class Row extends Button:
	const V = preload("res://scripts/ui/vic3_style.gd")
	const STAR_W := 30.0
	var _colour: Color
	var _press_x := -1.0
	var _icon: Texture2D
	var _day: String
	var _text: String
	var _odd := false

	func _init(day: String, text: String, colour: Color, icon_name: String, odd: bool) -> void:
		_day = day
		_text = text
		_colour = colour
		_odd = odd
		if icon_name != "":
			_icon = V.icon(icon_name)
		custom_minimum_size.y = 36.0
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tooltip_text = "Hinfliegen  ·  Stern: im Outliner anheften"
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var lit := is_hovered()
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, V.OLIVE_HOVER if lit else (Color("1c2724") if _odd else V.LEAF))
		if lit:
			draw_rect(r.grow(-0.5), V.GOLD_LIT, false, 1.0)
		# the medallion: dark ring, gold ring, dark boss, the icon in the kind's colour
		var c := Vector2(size.y * 0.5 + 2.0, size.y * 0.5)
		var rad := size.y * 0.5 - 3.0
		draw_circle(c, rad + 1.0, V.RING)
		draw_circle(c, rad, V.GOLD_LIT if lit else V.GOLD)
		draw_circle(c, rad - 2.0, Color("121a16"))
		draw_circle(c + Vector2(0, -rad * 0.2), rad * 0.62, Color(_colour, 0.18))
		if _icon != null:
			var s := rad * 1.25
			draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, _colour.lightened(0.15))
		else:
			draw_circle(c, rad * 0.45, _colour)
		var x := c.x + rad + 10.0
		var base := size.y * 0.5 + 5.0
		var italic := V.italic()
		draw_string(italic, Vector2(x, base), _day, HORIZONTAL_ALIGNMENT_LEFT, 64.0, V.SIZE_SMALL, V.DIM)
		x += 66.0
		draw_string(V.serif(), Vector2(x, base), _text, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - STAR_W, V.SIZE_TEXT - 1,
			Color.WHITE if lit else V.TEXT)
		if lit: # the star that pins it in the outliner
			var sc := Vector2(size.x - STAR_W * 0.5, size.y * 0.5)
			var pts := PackedVector2Array()
			for k in 11:
				var a := -PI * 0.5 + k * PI / 5.0
				pts.append(sc + Vector2(cos(a), sin(a)) * (8.0 if k % 2 == 0 else 3.6))
			draw_polyline(pts, V.GOLD_LIT, 1.5, true)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_press_x = event.position.x

	## The last click fell on the star.
	func on_star() -> bool:
		return _press_x > size.x - STAR_W
