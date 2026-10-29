extends PanelContainer
## A fixed window in the middle of the screen for the menus (pause menu,
## save games, settings): the look of ui_window.gd (slate body, bronze
## frame, warm title bar with the title centred), but it does not move,
## since a menu stands alone in front of the dimmed game.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiWindow = preload("res://scripts/ui/ui_window.gd")

signal closed

var body: VBoxContainer
var _title: Label
var _sub: Label

## `width` in pixels; `closable` adds the round ✕ at the right of the bar.
func _init(title: String, width: float, closable := true) -> void:
	theme = UiStyle.theme()
	custom_minimum_size.x = width
	add_theme_stylebox_override("panel", UiStyle.frame())
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var bar := PanelContainer.new()
	var bar_box := UiStyle.box(UiStyle.HEADER, UiStyle.FRAME, 0, 4, 0)
	bar_box.border_width_bottom = 1
	bar_box.corner_radius_bottom_left = 0
	bar_box.corner_radius_bottom_right = 0
	bar_box.content_margin_top = 10
	bar_box.content_margin_bottom = 10
	bar_box.content_margin_left = 8
	bar_box.content_margin_right = 8
	bar.add_theme_stylebox_override("panel", bar_box)
	column.add_child(bar)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var left := Control.new() # as wide as the ✕, so the title stays centred
	left.custom_minimum_size.x = UiWindow.ROUND_PX
	row.add_child(left)
	var heads := VBoxContainer.new()
	heads.add_theme_constant_override("separation", 2)
	heads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heads)
	_title = Label.new()
	_title.text = title
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_TITLE)
	_title.add_theme_color_override("font_color", UiStyle.TITLE)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_y", 1)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heads.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL + 1)
	_sub.add_theme_color_override("font_color", UiStyle.CONCEPT)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.visible = false
	heads.add_child(_sub)
	if closable:
		var close := UiWindow.round_button("✕", "Schliessen  (Esc)", func(): closed.emit())
		close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(close)
	else:
		var right := Control.new()
		right.custom_minimum_size.x = UiWindow.ROUND_PX
		row.add_child(right)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 20)
	column.add_child(pad)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	pad.add_child(body)

func set_subtitle(text: String) -> void:
	_sub.text = text
	_sub.visible = text != ""

## A wide menu button in the bronze look of the theme; `quiet` ones (leave
## the game) are drawn without the warm fill.
static func button(text: String, action: Callable, quiet := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", UiStyle.SIZE_HEAD)
	if quiet:
		b.add_theme_stylebox_override("normal", UiStyle.box(Color.TRANSPARENT, Color(UiStyle.FRAME, 0.45), 1, 3, 6))
		b.add_theme_color_override("font_color", UiStyle.DIM)
	b.add_theme_stylebox_override("focus", UiStyle.box(Color.TRANSPARENT, UiStyle.FRAME_LIT, 1, 3, 6))
	b.pressed.connect(action)
	return b

static func gap(parent: Control, height: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = height
	parent.add_child(g)
