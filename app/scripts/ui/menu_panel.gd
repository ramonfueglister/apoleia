extends PanelContainer
## A fixed window in the middle of the screen for the menus (pause menu,
## save games, settings), in the Victoria 3 look of ui/vic3_style.gd: a
## grained slate field in a gold rim, the title in small caps with large
## gold initials on a band of wine-red leather, a red medallion with a cross
## at its right. It does not move, since a menu stands alone in front of
## the dimmed game.

const Vic3 = preload("res://scripts/ui/vic3_style.gd")

const BAND_PX := 66.0
const PAD_PX := 26

signal closed

var body: VBoxContainer
var _sub: Label
var _bar: Control

## `width` in pixels; `closable` adds the red medallion at the right of the band.
func _init(title: String, width: float, closable := true) -> void:
	theme = Vic3.theme()
	custom_minimum_size.x = width
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	_bar = Control.new()
	_bar.custom_minimum_size.y = BAND_PX
	_bar.draw.connect(_draw_band)
	column.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(row)
	var left := Control.new() # as wide as the medallion, so the title stays centred
	left.custom_minimum_size.x = 42
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var title_box := CenterContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title_box)
	var heading := Vic3.title_label(title)
	heading.custom_minimum_size.x = width - 2.0 * 42 - 40
	title_box.add_child(heading)
	if closable:
		var close := Vic3.Medallion.new("", "Schliessen  (Esc)", 42.0, true)
		close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		close.pressed.connect(func(): closed.emit())
		row.add_child(close)
	else:
		var right := Control.new()
		right.custom_minimum_size.x = 42
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(right)
	var pad := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, PAD_PX)
	pad.add_theme_constant_override("margin_top", 18)
	column.add_child(pad)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	pad.add_child(body)
	# the game date or a note, in italics under the band
	_sub = Vic3.label("", Vic3.DIM, Vic3.SIZE_SMALL + 1, Vic3.italic())
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.visible = false
	body.add_child(_sub)
	resized.connect(queue_redraw)

func _draw() -> void:
	Vic3.draw_panel(self, Rect2(Vector2.ZERO, size))

func _draw_band() -> void:
	Vic3.draw_band(_bar, Rect2(Vector2(2, 2), _bar.size - Vector2(4, 2)))

func set_subtitle(text: String) -> void:
	_sub.text = text
	_sub.visible = text != ""

## A wide menu button with a gold icon; `quiet` ones (leave the game) are
## wine red.
static func button(text: String, action: Callable, quiet := false, icon_name := "") -> Button:
	var b := Vic3.button(text, icon_name, quiet)
	b.pressed.connect(action)
	return b

## The space between two groups of buttons, with a gold rule in it.
static func gap(parent: Control, height: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = height
	if height >= 12.0:
		g.draw.connect(func(): Vic3.draw_rule(g, Vector2(g.size.x * 0.15, g.size.y * 0.5), Vector2(g.size.x * 0.85, g.size.y * 0.5)))
	parent.add_child(g)
