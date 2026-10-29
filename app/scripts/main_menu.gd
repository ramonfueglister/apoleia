extends Control
## Apoleia's main menu, the start scene: a still of Rome under a dark veil,
## at the left a slate column in a bronze edge with the name and four
## entries (the EU5 look of ui/ui_style.gd). Nothing of the landscape is
## loaded before «Neues Spiel» or a save game is chosen; that comes behind
## the landscape's own loading screen. Captures and benchmarks
## (AUTOMATION_FLAGS) go straight into the landscape.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const MenuPanel = preload("res://scripts/ui/menu_panel.gd")
const SaveList = preload("res://scripts/ui/save_list.gd")
const SaveGames = preload("res://scripts/ui/save_games.gd")
const GameSettings = preload("res://scripts/ui/game_settings.gd")
const GAME_SCENE = "res://landscape.tscn"
const BACKGROUND_IMAGE = "res://assets/menu/rom.jpg"
const AUTOMATION_FLAGS = ["--tour", "--snapshot", "--fixture", "--capture-dir", "--telemetry-dir", "--probe-anchor", "--diagnose-input", "--bench", "--views"]
const COLUMN_PX := 420.0

var game_scene_path := GAME_SCENE
var start_button: Button
var load_button: Button
var settings_button: Button
var quit_button: Button
var _stage: Control # the room right of the column, where the windows open
var _open: MenuPanel
var starting := false

func _ready() -> void:
	for flag in AUTOMATION_FLAGS:
		for argument in OS.get_cmdline_user_args():
			if argument == flag or argument.begins_with(flag + "="):
				_start_game()
				return
	GameSettings.apply_saved()
	_build_ui()
	start_button.grab_focus()
	# Keep settings focus/navigation free of the landscape's music shortcuts.
	$Soundtrack.set_process_unhandled_key_input(false)

func _build_ui() -> void:
	theme = UiStyle.theme()
	var background := ColorRect.new()
	background.color = UiStyle.INSET
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var image := Image.load_from_file(BACKGROUND_IMAGE)
	if image != null and not image.is_empty():
		var still := TextureRect.new()
		still.texture = ImageTexture.create_from_image(image)
		still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(still)
	var veil := ColorRect.new()
	veil.color = Color(0.04, 0.055, 0.075, 0.55)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.offset_left = COLUMN_PX
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	# the column
	var column := PanelContainer.new()
	var edge := UiStyle.box(Color(UiStyle.PANEL, 0.94), UiStyle.FRAME, 0, 0, 0)
	edge.border_width_right = 1
	edge.shadow_color = Color(0, 0, 0, 0.45)
	edge.shadow_size = 18
	edge.content_margin_left = 72
	edge.content_margin_right = 56
	edge.content_margin_top = 96
	edge.content_margin_bottom = 40
	column.add_theme_stylebox_override("panel", edge)
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.offset_right = COLUMN_PX
	add_child(column)
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 6)
	column.add_child(items)
	var title := Label.new()
	title.text = "APOLEIA"
	var wide := FontVariation.new()
	wide.base_font = UiStyle.serif()
	wide.spacing_glyph = 10
	title.add_theme_font_override("font", wide)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", UiStyle.TITLE)
	items.add_child(title)
	items.add_child(Ornament.new())
	var sub := Label.new()
	sub.text = "Imperium Romanum · Ianuarius, Jahr 1"
	var italic := SystemFont.new()
	italic.font_names = UiStyle.serif().font_names
	italic.font_italic = true
	sub.add_theme_font_override("font", italic)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", UiStyle.DIM)
	items.add_child(sub)
	MenuPanel.gap(items, 64)
	start_button = _item("Neues Spiel", items, _start_game)
	load_button = _item("Spiel laden", items, _show_load)
	settings_button = _item("Einstellungen", items, _show_settings)
	MenuPanel.gap(items, 18)
	quit_button = _item("Spiel beenden", items, _quit_game)
	quit_button.add_theme_color_override("font_color", UiStyle.DIM)
	var rest := Control.new()
	rest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.add_child(rest)
	var version := Label.new()
	version.text = "Prototyp · Kit 1"
	version.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	version.add_theme_color_override("font_color", UiStyle.DIM)
	items.add_child(version)

func _item(text: String, parent: Control, action: Callable) -> Button:
	var b := MenuItem.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b

## Opens one window right of the column (save games or settings), closing
## the one open before.
func _show(panel: MenuPanel, focus: Control) -> void:
	_close()
	_open = panel
	panel.closed.connect(_close)
	_stage.add_child(panel)
	focus.grab_focus.call_deferred()

func _close() -> void:
	if is_instance_valid(_open):
		_open.queue_free()
	_open = null

func _show_load() -> void:
	var panel := MenuPanel.new("Spiel laden", 640.0)
	var list := SaveList.new(false)
	list.load_chosen.connect(_load_game)
	panel.body.add_child(list)
	_show(panel, list.first_focus())

func _show_settings() -> void:
	var panel := MenuPanel.new("Einstellungen", 520.0)
	var settings := GameSettings.new($Soundtrack)
	panel.body.add_child(settings)
	MenuPanel.gap(panel.body, 8)
	panel.body.add_child(MenuPanel.button("Fertig", _close))
	_show(panel, settings.first_focus())

func _load_game(path: String) -> void:
	SaveGames.pending = path
	_start_game()

func _start_game() -> void:
	if starting:
		return
	starting = true
	if is_instance_valid(start_button):
		start_button.text = "Wird gestartet …"
		start_button.disabled = true
	_start_scene.call_deferred()

func _start_scene() -> void:
	if DisplayServer.get_name() != "headless" and is_instance_valid(start_button):
		await RenderingServer.frame_post_draw
	var error := get_tree().change_scene_to_file(game_scene_path)
	if error != OK:
		starting = false
		SaveGames.pending = ""
		if is_instance_valid(start_button):
			start_button.disabled = false
			start_button.text = "Start fehlgeschlagen – erneut versuchen"
			start_button.grab_focus()
		push_error("Apoleia landscape could not be opened: " + error_string(error))

func _quit_game() -> void:
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_open):
		_close()
		start_button.grab_focus()
		get_viewport().set_input_as_handled()

## An entry of the column: cream serif text, a small bronze diamond before
## it that fills with gold under the mouse or the keyboard focus.
class MenuItem extends Button:
	func _init() -> void:
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		custom_minimum_size.y = 48
		add_theme_font_size_override("font_size", 22)
		add_theme_color_override("font_color", UiStyle.TEXT)
		for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			add_theme_color_override(state, UiStyle.NAME)
		add_theme_color_override("font_disabled_color", UiStyle.DIM)
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			var style := StyleBoxEmpty.new()
			style.content_margin_left = 26
			add_theme_stylebox_override(state, style)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var lit := is_hovered() or has_focus()
		var c := Vector2(8, size.y * 0.5)
		var r := 4.5
		var gem := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		if lit and not disabled:
			draw_colored_polygon(gem, UiStyle.FRAME_LIT)
		gem.append(gem[0])
		draw_polyline(gem, UiStyle.FRAME_LIT if lit else UiStyle.FRAME, 1.0, true)

## The rule under the name: a bronze line, a gold diamond, a bronze line.
class Ornament extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(130, 14)

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(0, y), Vector2(56, y), UiStyle.FRAME, 1.0)
		draw_line(Vector2(74, y), Vector2(130, y), UiStyle.FRAME, 1.0)
		var c := Vector2(65, y)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), UiStyle.FRAME_LIT)
