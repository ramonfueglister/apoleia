extends PanelContainer
## A fixed window in the middle of the screen for the menus (pause menu,
## save games, settings), drawn as ui_window.gd draws EU5's windows: dark
## carved wood around a navy field, a bronze lattice title bar with the
## title large in the middle and EU5's round close button. It does not
## move, since a menu stands alone in front of the dimmed game.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiWindow = preload("res://scripts/ui/ui_window.gd")

signal closed

var body: VBoxContainer
var _title: Label
var _sub: Label
var _bar: Control

## `width` in pixels; `closable` adds the round ✕ at the right of the bar.
func _init(title: String, width: float, closable := true) -> void:
	theme = UiStyle.theme()
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
	_bar.custom_minimum_size.y = UiWindow.BAR_PX
	_bar.draw.connect(func(): UiStyle.draw_bar(_bar, Rect2(Vector2.ZERO, _bar.size)))
	column.add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(row)
	var left := Control.new() # as wide as the ✕, so the title stays centred
	left.custom_minimum_size.x = UiWindow.ROUND_PX
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	_title = UiStyle.label(title, UiStyle.TITLE, UiStyle.SIZE_TITLE)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.add_theme_constant_override("shadow_outline_size", 4)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_FILL
	row.add_child(_title)
	if closable:
		var close := UiWindow.round_button("close", "Schliessen  (Esc)", func(): closed.emit())
		close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(close)
	else:
		var right := Control.new()
		right.custom_minimum_size.x = UiWindow.ROUND_PX
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(right)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, UiWindow.SIDE_PX)
	pad.add_theme_constant_override("margin_top", 0)
	pad.add_theme_constant_override("margin_bottom", UiWindow.SIDE_PX + 2)
	column.add_child(pad)
	var field := PanelContainer.new()
	field.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, Color.TRANSPARENT, 0, 0, 20))
	pad.add_child(field)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	field.add_child(body)
	# the game date or a note, in the kind's blue under the bar (EU5 puts a
	# tooltip's kind there)
	_sub = UiStyle.label("", UiStyle.KIND, UiStyle.SIZE_SMALL, UiStyle.italic())
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.visible = false
	body.add_child(_sub)
	resized.connect(queue_redraw)

## The wood around the field and its shadow; the bar draws itself.
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var shadow := UiStyle.box(Color(0, 0, 0, 0.0), Color.TRANSPARENT, 0, 2, 0)
	shadow.shadow_color = Color(0, 0, 0, 0.55)
	shadow.shadow_size = 14
	shadow.shadow_offset = Vector2(0, 6)
	draw_style_box(shadow, r)
	var bar := UiWindow.BAR_PX
	var side := float(UiWindow.SIDE_PX)
	UiStyle.draw_wood(self, r, Rect2(side, bar, size.x - 2.0 * side, size.y - bar - side - 2.0))

func set_subtitle(text: String) -> void:
	_sub.text = text
	_sub.visible = text != ""

## A wide menu button in the theme's EU5 look (slate board, bronze frame);
## `quiet` ones (leave the game) are drawn without the fill.
static func button(text: String, action: Callable, quiet := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", UiStyle.SIZE_HEAD)
	if quiet:
		b.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.PANEL, 0.0), Color(UiStyle.GOLD, 0.5), 1, 4, 7))
		b.add_theme_color_override("font_color", UiStyle.DIM)
	b.add_theme_stylebox_override("focus", UiStyle.box(Color.TRANSPARENT, UiStyle.GOLD_LIT, 1, 4, 7))
	b.pressed.connect(action)
	return b

static func gap(parent: Control, height: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = height
	parent.add_child(g)
