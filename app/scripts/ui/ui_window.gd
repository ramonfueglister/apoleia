extends Control
## A window in the look of the menus (after Victoria 3): grained slate in a
## gold rim, the title in small caps on a band of leather to drag it by, a
## grip at the bottom right to size it, round medallions – to fold it to its
## band and ✕ to close it. All
## windows share one CanvasLayer (WINDOW_LAYER) above the rest of the HUD
## (game clock, build menu, events), so none of them covers a window; the
## one clicked last lies on top. Each remembers where it stood and how big
## it was (user://ui_windows.cfg, by its key), across closing and games.
##
##   drag the title bar     move
##   drag the grip          size
##   double click the bar   fold or unfold
##   ← at the left          back to what it showed before (remember)
##
## The content goes into `body` (a VBoxContainer that fills the window);
## `bar_extra` takes controls left of the title (back and settings go there).
## As Victoria 3's, the band can carry a line under the title
## (set_subtitle), with a round → that leads to what it names.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Vic3Style = preload("res://scripts/ui/vic3_style.gd")
const WINDOW_LAYER := 10 # over the game clock and market (4) and the build menu (3)
const BAR_PX := 56.0
const ROUND_PX := 38.0
const SIDE_PX := 8 # the slate between the rim and the field
const TITLE_PX := 26
const GRIP_PX := 16.0
const KEEP_PX := 48.0 # this much of a window stays on screen
const LINK_PX := 22.0 # the round → after the subtitle
const SUB_PX := 18.0 # the band grows by this with a subtitle
const BACK_MAX := 24 # steps the back button remembers
const STORE := "user://ui_windows.cfg"

signal closed

static var _shared: CanvasLayer

var key := ""
var min_size := Vector2(320, 200)
var body: VBoxContainer
var bar_extra: HBoxContainer
var folded := false
var _bar: Control
var _title: RichTextLabel
var _subtitle: Label
var _link: Button
var _link_action := Callable()
var _back: Button
var _history: Array[Callable] = [] # each shows again what the window showed before
var _going_back := false
var _frame: PanelContainer
var _field: PanelContainer
var _grip: Control
var _drag := Vector2.INF # mouse minus position while dragging the bar
var _size_from := Vector2.INF # mouse minus size while dragging the grip
var _open_size := Vector2.ZERO
var _start := Rect2(80, 64, 600, 480)

## A window named `title`, remembered by `id`, first at `rect` (in pixels;
## a negative x or y counts from the right or bottom edge).
static func make(id: String, title: String, rect: Rect2, tree: SceneTree) -> Control:
	var w = load("res://scripts/ui/ui_window.gd").new()
	w.key = id
	w._build(title)
	w._start = rect
	_layer(tree).add_child(w)
	return w

## The shared layer of all windows, made on first use.
static func _layer(tree: SceneTree) -> CanvasLayer:
	if is_instance_valid(_shared):
		return _shared
	var layer := CanvasLayer.new()
	layer.name = "UiWindows"
	layer.layer = WINDOW_LAYER
	tree.root.add_child.call_deferred(layer) # the root is busy while the scene sets up
	_shared = layer
	return layer

func _ready() -> void:
	_restore(_start)
	get_viewport().size_changed.connect(func(): position = _kept(position, size))

func _build(title: String) -> void:
	name = "Window_" + key
	theme = UiStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# the slate in its rim, drawn by the window itself (see _draw), the
	# leather band across its top, the field inside
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_frame.add_child(column)
	# the band: leather, the title in the middle in small caps with large
	# gold initials, round medallions at both ends
	var bar := Control.new()
	_bar = bar
	bar.custom_minimum_size = Vector2(0, BAR_PX)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_bar_input)
	bar.draw.connect(func(): UiStyle.draw_bar(bar, Rect2(Vector2.ZERO, bar.size)))
	column.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	bar_extra = HBoxContainer.new() # left of the title: back and settings
	bar_extra.add_theme_constant_override("separation", 6)
	bar_extra.custom_minimum_size = Vector2(2 * ROUND_PX + 6, 0)
	bar_extra.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(bar_extra)
	_back = round_button("back", "Zurück", go_back)
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back.visible = false
	bar_extra.add_child(_back)
	var heads := VBoxContainer.new() # the title, under it the subtitle
	heads.add_theme_constant_override("separation", -4)
	heads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heads.alignment = BoxContainer.ALIGNMENT_CENTER
	heads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(heads)
	_title = Vic3Style.title_label(title, TITLE_PX)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_contents = true
	heads.add_child(_title)
	var sub_row := HBoxContainer.new()
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_row.add_theme_constant_override("separation", 6)
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_row.visible = false
	heads.add_child(sub_row)
	_subtitle = UiStyle.label("", UiStyle.TEXT, UiStyle.SIZE_TEXT)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_row.add_child(_subtitle)
	_link = round_button("forward", "", func():
		if _link_action.is_valid():
			_link_action.call())
	_link.custom_minimum_size = Vector2(LINK_PX, LINK_PX)
	_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub_row.add_child(_link)
	for b in [["fold", "Einklappen", toggle_fold], ["close", "Schliessen  (Esc)", close]]:
		var button := round_button(b[0], b[1], b[2])
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, SIDE_PX)
	pad.add_theme_constant_override("margin_top", 0)
	pad.add_theme_constant_override("margin_bottom", SIDE_PX + 2)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pad)
	_field = PanelContainer.new() # the slate shows through
	_field.add_theme_stylebox_override("panel", UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 10))
	pad.add_child(_field)
	# what is wider than the window scrolls sideways instead of widening it
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_field.add_child(scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_grip = Control.new()
	_grip.custom_minimum_size = Vector2(GRIP_PX, GRIP_PX)
	_grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.gui_input.connect(_on_grip_input)
	_grip.draw.connect(func():
		for k in 3: # three short strokes in the corner
			var o := 4.0 + k * 4.0
			_grip.draw_line(Vector2(GRIP_PX - 2.0, o), Vector2(o, GRIP_PX - 2.0), Color(UiStyle.GOLD, 0.8), 1.0))
	add_child(_grip)
	gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			raise())
	resized.connect(queue_redraw)

## The slate in its rims and its shadow; the band draws itself.
func _draw() -> void:
	UiStyle.draw_window(self, Rect2(Vector2.ZERO, size))

## A round medallion as the menus' close and back buttons; `glyph` is
## "close", "fold", "back" or a letter.
static func round_button(glyph: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(ROUND_PX, ROUND_PX)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.draw.connect(func():
		var hover := button.is_hovered()
		UiStyle.draw_round(button, button.size / 2.0, minf(button.size.x, button.size.y) / 2.0, glyph, hover, button.is_pressed()))
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	button.button_down.connect(button.queue_redraw)
	button.button_up.connect(button.queue_redraw)
	button.pressed.connect(action)
	return button

func set_title(text: String) -> void:
	_title.text = Vic3Style.caps(text, TITLE_PX)

## The line under the title ("" hides it), as Victoria 3's "Company in
## Great Britain →": `link`, when given, is the round → after it, `tip`
## its tooltip.
func set_subtitle(text: String, link := Callable(), tip := "") -> void:
	_subtitle.text = text
	_subtitle.get_parent().visible = text != ""
	_bar.custom_minimum_size.y = BAR_PX + (SUB_PX if text != "" else 0.0)
	_link_action = link
	_link.visible = link.is_valid()
	_link.tooltip_text = tip

## Before the window shows something else: `show_again` brings back what
## it shows now, for the back button. Going back remembers nothing.
func remember(show_again: Callable) -> void:
	if _going_back:
		return
	_history.append(show_again)
	if _history.size() > BACK_MAX:
		_history.pop_front()
	_back.visible = true

func go_back() -> void:
	if _history.is_empty():
		return
	var show_again: Callable = _history.pop_back()
	_back.visible = not _history.is_empty()
	_going_back = true
	show_again.call()
	_going_back = false

## Forgets the steps back (the window shows something new from elsewhere).
func forget() -> void:
	_history.clear()
	_back.visible = false

func open() -> void:
	visible = true
	raise()

func close() -> void:
	visible = false
	forget()
	closed.emit()

func raise() -> void:
	if get_parent() != null:
		get_parent().move_child(self, -1)

func toggle_fold() -> void:
	folded = not folded
	if folded:
		_open_size = size
		size = Vector2(size.x, _bar.custom_minimum_size.y + 2.0)
	else:
		size = _open_size
	_frame.get_child(0).get_child(1).visible = not folded
	_grip.visible = not folded
	queue_redraw()
	_save()

func _on_bar_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.double_click:
			toggle_fold()
		elif e.pressed:
			raise()
			_drag = get_global_mouse_position() - position
		else:
			_drag = Vector2.INF
			_save()
		accept_event()
	elif e is InputEventMouseMotion and _drag != Vector2.INF:
		position = _kept(get_global_mouse_position() - _drag, size)
		accept_event()

func _on_grip_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			raise()
			_size_from = get_global_mouse_position() - size
		else:
			_size_from = Vector2.INF
			_save()
		accept_event()
	elif e is InputEventMouseMotion and _size_from != Vector2.INF:
		var screen := get_viewport_rect().size
		size = (get_global_mouse_position() - _size_from).max(min_size).min(screen - position)
		accept_event()

## Where a window may stand: at least KEEP_PX of it on screen, its bar
## never above the top.
func _kept(at: Vector2, extent: Vector2) -> Vector2:
	var screen := get_viewport_rect().size
	return Vector2(clampf(at.x, KEEP_PX - extent.x, screen.x - KEEP_PX), clampf(at.y, 0.0, screen.y - BAR_PX))

func _restore(rect: Rect2) -> void:
	var screen := get_viewport_rect().size
	var at := rect.position
	if at.x < 0.0:
		at.x += screen.x - rect.size.x
	if at.y < 0.0:
		at.y += screen.y - rect.size.y
	var extent := rect.size
	var cfg := ConfigFile.new()
	if cfg.load(STORE) == OK and cfg.has_section(key):
		at = cfg.get_value(key, "position", at)
		extent = cfg.get_value(key, "size", extent)
	extent = extent.max(min_size).min(screen)
	size = extent
	position = _kept(at, extent)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(STORE)
	cfg.set_value(key, "position", position)
	cfg.set_value(key, "size", _open_size if folded else size)
	cfg.save(STORE)
