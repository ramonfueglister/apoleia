extends Control
## Apoleia's main menu, the start scene, in the Victoria 3 look of
## ui/vic3_style.gd: a soft still of Rome, at the left a framed slate card
## with the laurel, the name and the entries, at the right our own
## buildings as a small scene. Nothing of the landscape is
## loaded before «Neues Spiel» or a save game is chosen; that comes behind
## the landscape's own loading screen. Captures and benchmarks
## (AUTOMATION_FLAGS) go straight into the landscape.

const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const MenuPanel = preload("res://scripts/ui/menu_panel.gd")
const SaveList = preload("res://scripts/ui/save_list.gd")
const SaveGames = preload("res://scripts/ui/save_games.gd")
const GameSettings = preload("res://scripts/ui/game_settings.gd")
const GAME_SCENE = "res://landscape.tscn"
const BACKGROUND_IMAGE = "res://assets/menu/rom_weich.jpg"
const AUTOMATION_FLAGS = ["--tour", "--snapshot", "--fixture", "--capture-dir", "--telemetry-dir", "--probe-anchor", "--diagnose-input", "--bench", "--views"]
const COLUMN_LEFT := 96.0
const COLUMN_PX := 400.0

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
	theme = Vic3.theme()
	var background := ColorRect.new()
	background.color = Color("1a1718")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	if ResourceLoader.exists(BACKGROUND_IMAGE):
		var still := TextureRect.new()
		still.texture = load(BACKGROUND_IMAGE)
		still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		still.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		still.modulate = Color(0.46, 0.41, 0.37)
		still.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(still)
	var veil := TextureRect.new() # dark at the left behind the column, light to the right
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.4, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(0.06, 0.045, 0.05, 0.9), Color(0.06, 0.045, 0.05, 0.5), Color(0.06, 0.045, 0.05, 0.2), Color(0.06, 0.045, 0.05, 0.6)])
	var fade_tex := GradientTexture2D.new()
	fade_tex.gradient = fade
	veil.texture = fade_tex
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	var diorama := Diorama.new()
	diorama.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diorama.offset_left = COLUMN_LEFT + COLUMN_PX + 40.0
	add_child(diorama)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.offset_left = COLUMN_LEFT + COLUMN_PX
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	# the column: a framed slate card, as Victoria 3's main menu
	var column := PanelContainer.new()
	column.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.draw.connect(func(): Vic3.draw_panel(column, Rect2(Vector2.ZERO, column.size)))
	column.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = COLUMN_LEFT
	column.offset_right = COLUMN_LEFT + COLUMN_PX
	column.offset_top = 64
	column.offset_bottom = -64
	add_child(column)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 32)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 24)
	column.add_child(pad)
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 10)
	pad.add_child(items)
	var laurel := TextureRect.new()
	laurel.texture = Vic3.icon("laurel-crown")
	laurel.modulate = Vic3.GOLD
	laurel.custom_minimum_size = Vector2(64, 64)
	laurel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	laurel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	items.add_child(laurel)
	var title := Vic3.title_label("Apoleia", 58)
	title.add_theme_color_override("default_color", Color("e6cdbd"))
	items.add_child(title)
	var sub := Vic3.label("Imperium Romanum · Ianuarius, Jahr 1", Vic3.GOLD, Vic3.SIZE_SMALL + 1, Vic3.italic())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items.add_child(sub)
	MenuPanel.gap(items, 28)
	var single := Vic3.label("Einzelspiel", Vic3.DIM, Vic3.SIZE_SMALL + 1, Vic3.italic())
	items.add_child(single)
	start_button = _item("Neues Spiel", "scroll-unfurled", items, _start_game, true)
	load_button = _item("Spiel laden", "open-book", items, _show_load)
	MenuPanel.gap(items, 22)
	settings_button = _item("Einstellungen", "cog", items, _show_settings)
	var rest := Control.new()
	rest.size_flags_vertical = Control.SIZE_EXPAND_FILL
	items.add_child(rest)
	quit_button = Vic3.button("Spiel beenden", "exit-door", true)
	quit_button.pressed.connect(_quit_game)
	items.add_child(quit_button)
	var round_row := HBoxContainer.new()
	round_row.alignment = BoxContainer.ALIGNMENT_CENTER
	round_row.add_theme_constant_override("separation", 22)
	items.add_child(round_row)
	var music := Vic3.Medallion.new("musical-notes", "Musik ein/aus  (M)", 46.0)
	music.pressed.connect(func(): $Soundtrack.toggle_mute())
	round_row.add_child(music)
	var version := Vic3.label("Prototyp · Kit 2", Vic3.DIM, Vic3.SIZE_SMALL)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	items.add_child(version)

func _item(text: String, icon_name: String, parent: Control, action: Callable, first := false) -> Button:
	var b := Vic3.button(text, icon_name, false, first)
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
	var panel := MenuPanel.new("Einstellungen", 640.0)
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

## Our own buildings, rendered once from the game's voxel models
## (assets/menu/diorama), standing as a small scene right of the column in
## place of Victoria 3's painted key art. Positions are fractions of the
## space, so it fits any window.
class Diorama extends Control:
	const PIECES := [
		["colosseum", Vector2(0.52, 0.42), 0.40],
		["temple", Vector2(0.18, 0.60), 0.23],
		["insula", Vector2(0.86, 0.52), 0.18],
		["domus", Vector2(0.60, 0.80), 0.22],
		["farm", Vector2(0.22, 0.86), 0.16],
	]
	var _tex := {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for p in PIECES:
			var path := "res://assets/menu/diorama/%s.png" % p[0]
			if ResourceLoader.exists(path):
				_tex[p[0]] = load(path)
		resized.connect(queue_redraw)

	func _draw() -> void:
		# a soft warm light on the ground under the scene
		var c := Vector2(size.x * 0.52, size.y * 0.66)
		for i in 10:
			var k := 1.0 - i / 10.0
			draw_set_transform(c, 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, size.x * 0.48 * k, Color(0.55, 0.48, 0.34, 0.035))
		draw_set_transform(Vector2.ZERO)
		for p in PIECES:
			var tex: Texture2D = _tex.get(p[0])
			if tex == null:
				continue
			var w: float = size.x * p[2]
			var h := w * tex.get_height() / tex.get_width()
			var at: Vector2 = Vector2(size.x * p[1].x, size.y * p[1].y)
			draw_set_transform(at + Vector2(0, h * 0.42), 0.0, Vector2(1.0, 0.28))
			draw_circle(Vector2.ZERO, w * 0.45, Color(0, 0, 0, 0.35))
			draw_set_transform(Vector2.ZERO)
			draw_texture_rect(tex, Rect2(at - Vector2(w, h) * 0.5, Vector2(w, h)), false)
