extends HBoxContainer
## Tabs as EU5 sets them under a window's title: boards of dark wood of
## equal width across the whole window, black gaps between them, the
## chosen one lighter and taller with its top rolled like a scroll. Takes
## the place of a TabBar: add_tab(), current_tab, tab_changed.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const HEIGHT := 46.0
const RISE := 6.0 # the chosen tab stands this much higher

signal tab_changed(index: int)

var _titles: Array[String] = []

var current_tab := 0:
	set(i):
		if i == current_tab or i < 0 or i >= get_child_count():
			return
		current_tab = i
		for c in get_children():
			c.queue_redraw()
		tab_changed.emit(i)

func _init() -> void:
	add_theme_constant_override("separation", 4)
	custom_minimum_size = Vector2(0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_share_width)

func add_tab(title: String) -> void:
	var i := get_child_count()
	_titles.append(title)
	var tab := Button.new()
	tab.focus_mode = Control.FOCUS_NONE
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.custom_minimum_size = Vector2(0, HEIGHT)
	tab.clip_text = true
	for state in ["normal", "hover", "pressed", "focus"]:
		tab.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	tab.draw.connect(func(): _draw_tab(tab, title, i == current_tab, tab.is_hovered(), _font_size()))
	tab.mouse_entered.connect(tab.queue_redraw)
	tab.mouse_exited.connect(tab.queue_redraw)
	tab.pressed.connect(func(): current_tab = i)
	add_child(tab)

## Boards of equal width while every name fits at the text size; with many
## tabs in a narrow window each board gets the width of its name instead.
func _share_width() -> void:
	var f := UiStyle.bold()
	var gaps := get_theme_constant("separation") * maxi(0, _titles.size() - 1)
	var equal := (size.x - gaps) / maxf(1.0, _titles.size())
	var fits := _titles.all(func(t): return f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x <= equal - 10.0)
	for k in get_child_count():
		(get_child(k) as Control).size_flags_stretch_ratio = 1.0 if fits else f.get_string_size(_titles[k], HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x + 16.0

## One size for all tabs: the largest at which the longest title fits its
## board, so many tabs in a narrow window shrink their names, not clip them.
func _font_size() -> int:
	var f := UiStyle.bold()
	for font_size in range(UiStyle.SIZE_HEAD + 2, UiStyle.SIZE_SMALL - 1, -1):
		var fits := true
		for k in get_child_count():
			var w := (get_child(k) as Control).size.x
			if f.get_string_size(_titles[k], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > w - 10.0:
				fits = false
		if fits:
			return font_size
	return UiStyle.SIZE_SMALL

static func _draw_tab(tab: Button, title: String, on: bool, hover: bool, font_size: int) -> void:
	var r := Rect2(Vector2(0, 0 if on else RISE), tab.size - Vector2(0, 0 if on else RISE))
	var wood := UiStyle.TAB_WOOD_ON if on else (UiStyle.TAB_WOOD_HOVER if hover else UiStyle.TAB_WOOD)
	tab.draw_rect(r, UiStyle.EDGE)
	var inner := r.grow(-2.0)
	tab.draw_rect(inner, wood)
	for k in 5: # a faint grain along the board
		var y := inner.position.y + inner.size.y * (0.18 + 0.17 * k)
		tab.draw_line(Vector2(inner.position.x + 6.0, y), Vector2(inner.end.x - 6.0, y + (k % 2) * 2.0), Color(0, 0, 0, 0.08), 1.0)
	tab.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 2)), Color(1, 1, 1, 0.07))
	if on:
		# the rolled top: a darker curl over the left of the board
		var curl := PackedVector2Array()
		for k in 17:
			var t := k / 16.0
			curl.append(Vector2(inner.position.x + t * inner.size.x, inner.position.y + 9.0 - 7.0 * sin(t * PI * 0.5) + 2.0 * t))
		tab.draw_polyline(curl, Color(0, 0, 0, 0.55), 3.0, true)
		tab.draw_polyline(curl, Color(1, 1, 1, 0.08), 1.0, true)
		tab.draw_circle(Vector2(inner.position.x + 5.0, inner.position.y + 9.0), 4.0, Color(0, 0, 0, 0.5))
	var f := UiStyle.bold()
	var y := r.position.y + r.size.y * 0.5 + font_size * 0.35
	UiStyle.text_at(tab, Vector2(r.position.x, y), title, Color.WHITE if hover and not on else UiStyle.TEXT,
		font_size, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, f)
