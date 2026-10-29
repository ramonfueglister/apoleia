extends Control
## A window in the manner of EU5: a title bar to drag it by, a grip at the
## bottom right to size it, – to fold it to its bar and ✕ to close it. All
## windows share one CanvasLayer (WINDOW_LAYER) above the rest of the HUD
## (game clock, build menu, events), so none of them covers a window; the
## one clicked last lies on top. Each remembers where it stood and how big
## it was (user://ui_windows.cfg, by its key), across closing and games.
##
##   drag the title bar     move
##   drag the grip          size
##   double click the bar   fold or unfold
##
## The content goes into `body` (a VBoxContainer that fills the window);
## `bar_extra` takes controls left of the title (EU5 puts back and settings there).

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const WINDOW_LAYER := 10 # over the game clock and market (4) and the build menu (3)
const BAR_PX := 44.0
const ROUND_PX := 28.0
const GRIP_PX := 16.0
const KEEP_PX := 48.0 # this much of a window stays on screen
const STORE := "user://ui_windows.cfg"

signal closed

static var _shared: CanvasLayer

var key := ""
var min_size := Vector2(320, 200)
var body: VBoxContainer
var bar_extra: HBoxContainer
var folded := false
var _title: Label
var _frame: PanelContainer
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
	_frame = PanelContainer.new()
	_frame.add_theme_stylebox_override("panel", UiStyle.frame())
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_frame.add_child(column)
	# the title bar: warm brown, the title in the middle as EU5 sets it,
	# round buttons at the right
	var bar := PanelContainer.new()
	var bar_box := UiStyle.box(UiStyle.HEADER, UiStyle.FRAME, 0, 4, 0)
	bar_box.border_width_bottom = 1
	bar_box.corner_radius_bottom_left = 0
	bar_box.corner_radius_bottom_right = 0
	bar_box.content_margin_left = 6
	bar_box.content_margin_right = 6
	bar.add_theme_stylebox_override("panel", bar_box)
	bar.custom_minimum_size = Vector2(0, BAR_PX)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_bar_input)
	column.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	bar_extra = HBoxContainer.new() # left of the title, like EU5's back and settings
	bar_extra.add_theme_constant_override("separation", 6)
	bar_extra.custom_minimum_size = Vector2(2 * ROUND_PX + 6, 0)
	row.add_child(bar_extra)
	_title = Label.new()
	_title.text = title
	_title.add_theme_font_override("font", UiStyle.serif())
	_title.add_theme_font_size_override("font_size", UiStyle.SIZE_TITLE)
	_title.add_theme_color_override("font_color", UiStyle.TITLE)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_y", 1)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_title)
	for b in [["–", "Einklappen", toggle_fold], ["✕", "Schliessen  (Esc)", close]]:
		row.add_child(round_button(b[0], b[1], b[2]))
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pad)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	pad.add_child(body)
	_grip = Control.new()
	_grip.custom_minimum_size = Vector2(GRIP_PX, GRIP_PX)
	_grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.gui_input.connect(_on_grip_input)
	_grip.draw.connect(func():
		for k in 3: # three short strokes in the corner
			var o := 4.0 + k * 4.0
			_grip.draw_line(Vector2(GRIP_PX - 2.0, o), Vector2(o, GRIP_PX - 2.0), Color(UiStyle.FRAME_LIT, 0.6), 1.0))
	add_child(_grip)
	gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			raise())

## A round button in a bronze ring, as EU5's close and back buttons.
static func round_button(text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(ROUND_PX, ROUND_PX)
	button.add_theme_font_size_override("font_size", 15)
	var r := int(ROUND_PX / 2.0)
	button.add_theme_stylebox_override("normal", UiStyle.box(Color("141a21"), UiStyle.FRAME, 2, r, 0))
	button.add_theme_stylebox_override("hover", UiStyle.box(UiStyle.SELECTED, UiStyle.FRAME_LIT, 2, r, 0))
	button.add_theme_stylebox_override("pressed", UiStyle.box(UiStyle.SELECTED, UiStyle.FRAME_LIT, 2, r, 0))
	button.pressed.connect(action)
	return button

func set_title(text: String) -> void:
	_title.text = text

func open() -> void:
	visible = true
	raise()

func close() -> void:
	visible = false
	closed.emit()

func raise() -> void:
	if get_parent() != null:
		get_parent().move_child(self, -1)

func toggle_fold() -> void:
	folded = not folded
	if folded:
		_open_size = size
		size = Vector2(size.x, BAR_PX + 2.0)
	else:
		size = _open_size
	_frame.get_child(0).get_child(1).visible = not folded
	_grip.visible = not folded
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
