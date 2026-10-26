extends Control
## Apoleia's lightweight entry screen; no landscape data is loaded before Start.

const GAME_SCENE = "res://landscape.tscn"
const SETTINGS_PATH = "user://display.cfg"
const BACKGROUND = Color("13232b")
const INK = Color("edf0e8")
const SECONDARY = Color("aab9bc")
const AUTOMATION_FLAGS = ["--tour", "--snapshot", "--fixture", "--capture-dir", "--telemetry-dir", "--probe-anchor", "--diagnose-input"]

var settings_path := SETTINGS_PATH
var game_scene_path := GAME_SCENE
var home: VBoxContainer
var settings_page: VBoxContainer
var start_button: Button
var load_button: Button
var settings_button: Button
var quit_button: Button
var music_toggle: CheckButton
var fullscreen_toggle: CheckButton
var status: Label
var back_button: Button
var starting := false

func _ready() -> void:
	# Existing capture and measurement commands retain their direct landscape entry.
	for flag in AUTOMATION_FLAGS:
		if flag in OS.get_cmdline_user_args():
			_start_game()
			return
	var display_from_cli := false
	for argument in OS.get_cmdline_args():
		if argument in ["--windowed", "-w", "--fullscreen", "-f", "--resolution"] or argument.begins_with("--resolution="):
			display_from_cli = true
			break
	var config := ConfigFile.new()
	if not display_from_cli and config.load(settings_path) == OK and config.has_section_key("display", "fullscreen") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(config.get_value("display", "fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED)
	_build_ui()
	resized.connect(_resize_columns)
	_resize_columns()
	start_button.grab_focus()
	# Keep settings focus/navigation free of the landscape's music shortcuts.
	$Soundtrack.set_process_unhandled_key_input(false)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var pages := VBoxContainer.new()
	center.add_child(pages)
	home = _column(pages)
	var title := _label("Apoleia", 52, INK)
	home.add_child(title)
	_spacer(home, 28)
	start_button = _button("Spiel starten", home, _start_game)
	load_button = _button("Spielstand laden", home, Callable())
	load_button.disabled = true
	settings_button = _button("Einstellungen", home, _show_settings)
	quit_button = _button("Beenden", home, _quit_game)
	settings_page = _column(pages)
	settings_page.hide()
	settings_page.add_child(_label("Einstellungen", 30, INK))
	_spacer(settings_page, 28)
	music_toggle = _toggle("Musik", settings_page)
	var music_config := ConfigFile.new()
	var muted := false
	if music_config.load($Soundtrack.settings_path) == OK:
		muted = bool(music_config.get_value("music", "muted", false))
	if not is_instance_valid($Soundtrack.player):
		$Soundtrack.muted = muted
	music_toggle.set_pressed_no_signal(not muted)
	music_toggle.toggled.connect(_set_music_enabled)
	fullscreen_toggle = _toggle("Vollbild", settings_page)
	fullscreen_toggle.set_pressed_no_signal(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
	fullscreen_toggle.toggled.connect(_set_fullscreen)
	fullscreen_toggle.visible = not OS.has_feature("mobile")
	status = _label("", 14, SECONDARY)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_page.add_child(status)
	_spacer(settings_page, 20)
	back_button = _button("Zurück", settings_page, _show_home)

func _column(parent: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	return column

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _spacer(parent: Control, height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)

func _style_controls(control: Control) -> void:
	control.custom_minimum_size.y = 52
	control.add_theme_font_size_override("font_size", 20)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		control.add_theme_color_override(state, INK)
	control.add_theme_color_override("font_disabled_color", SECONDARY)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(INK, 0.07) if state in ["hover", "pressed"] else Color.TRANSPARENT
		if state == "focus":
			style.border_width_bottom = 2
			style.border_color = INK
		style.content_margin_left = 0
		style.content_margin_right = 0
		control.add_theme_stylebox_override(state, style)

func _button(text: String, parent: Control, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_controls(button)
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	return button

func _toggle(text: String, parent: Control) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = text
	_style_controls(toggle)
	parent.add_child(toggle)
	return toggle

func _resize_columns() -> void:
	var width := minf(360.0, maxf(0.0, size.x - 64.0))
	for column in [home, settings_page]:
		column.custom_minimum_size.x = width

func _show_settings() -> void:
	home.hide()
	settings_page.show()
	music_toggle.grab_focus()

func _show_home() -> void:
	settings_page.hide()
	home.show()
	settings_button.grab_focus()

func _set_music_enabled(enabled: bool) -> void:
	var music = $Soundtrack
	# Headless/--mute-music launches intentionally have no AudioStreamPlayer.
	var config := ConfigFile.new()
	config.set_value("music", "muted", not enabled)
	if config.save(music.settings_path) != OK:
		music_toggle.set_pressed_no_signal(not music.muted)
		status.text = "Musikeinstellung konnte nicht gespeichert werden. Bitte erneut versuchen."
		return
	status.text = ""
	if music.muted != not enabled and is_instance_valid(music.player):
		music.toggle_mute()
	else:
		music.muted = not enabled

func _set_fullscreen(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", enabled)
	if config.save(settings_path) != OK:
		fullscreen_toggle.set_pressed_no_signal(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
		status.text = "Anzeigeeinstellung konnte nicht gespeichert werden. Bitte erneut versuchen."
		return
	status.text = ""
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

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
		if is_instance_valid(start_button):
			start_button.disabled = false
			start_button.text = "Start fehlgeschlagen – erneut versuchen"
			start_button.grab_focus()
		push_error("Apoleia landscape could not be opened: " + error_string(error))

func _quit_game() -> void:
	get_tree().quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(settings_page) and settings_page.visible:
		_show_home()
		get_viewport().set_input_as_handled()
