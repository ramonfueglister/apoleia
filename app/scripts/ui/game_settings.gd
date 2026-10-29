extends VBoxContainer
## The settings both menus show (main_menu.gd, pause_menu.gd): full screen,
## music on or off, its loudness and the yearly autosave. Each change is
## kept at once: the display and the autosave in user://display.cfg, the
## music where soundtrack.gd keeps it (user://soundtrack.cfg).

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const STORE := "user://display.cfg"

var soundtrack: Node # soundtrack.gd, the scene's own
var _fullscreen: CheckButton
var _music: CheckButton
var _volume: HSlider
var _autosave: CheckButton
var _status: Label

## Puts the saved display and loudness in place; the menu calls it on start.
## Command-line display arguments win over the saved ones.
static func apply_saved() -> void:
	var config := ConfigFile.new()
	if config.load(STORE) != OK:
		return
	AudioServer.set_bus_volume_db(0, linear_to_db(float(config.get_value("audio", "volume", 1.0))))
	for argument in OS.get_cmdline_args():
		if argument in ["--windowed", "-w", "--fullscreen", "-f", "--resolution"] or argument.begins_with("--resolution="):
			return
	if config.has_section_key("display", "fullscreen") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(config.get_value("display", "fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED)

static func autosave_on() -> bool:
	var config := ConfigFile.new()
	return config.load(STORE) != OK or bool(config.get_value("game", "autosave", true))

static func _keep(section: String, key: String, value: Variant) -> bool:
	var config := ConfigFile.new()
	config.load(STORE)
	config.set_value(section, key, value)
	return config.save(STORE) == OK

func _init(music: Node) -> void:
	soundtrack = music
	add_theme_constant_override("separation", 0)
	var config := ConfigFile.new()
	config.load(STORE)
	_head("Anzeige")
	_fullscreen = _switch("Vollbild")
	_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
	_fullscreen.toggled.connect(_set_fullscreen)
	_fullscreen.get_parent().get_parent().visible = not OS.has_feature("mobile")
	_head("Ton")
	_music = _switch("Musik")
	_music.set_pressed_no_signal(not _muted())
	_music.toggled.connect(_set_music)
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.custom_minimum_size = Vector2(200, 24)
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.add_theme_stylebox_override("slider", UiStyle.box(UiStyle.INSET, Color(UiStyle.FRAME, 0.6), 1, 3, 3))
	_volume.add_theme_stylebox_override("grabber_area", UiStyle.box(Color(UiStyle.FRAME, 0.8), Color.TRANSPARENT, 0, 3, 3))
	_volume.add_theme_stylebox_override("grabber_area_highlight", UiStyle.box(UiStyle.FRAME_LIT, Color.TRANSPARENT, 0, 3, 3))
	_volume.set_value_no_signal(float(config.get_value("audio", "volume", 1.0)))
	_volume.value_changed.connect(_set_volume)
	_row("Lautstärke", _volume)
	_head("Spiel")
	_autosave = _switch("Jedes Jahr automatisch speichern")
	_autosave.set_pressed_no_signal(autosave_on())
	_autosave.toggled.connect(func(on: bool): _report(_keep("game", "autosave", on)))
	_status = Label.new()
	_status.add_theme_color_override("font_color", UiStyle.LOSS)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	add_child(_status)

func first_focus() -> Control:
	return _fullscreen if _fullscreen.get_parent().get_parent().visible else _music

func _head(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL + 1)
	l.add_theme_color_override("font_color", UiStyle.NAME)
	if get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.y = 14
		add_child(gap)
	add_child(l)

## A row: the name at the left, the control at the right, a faint line below.
func _row(text: String, control: Control) -> void:
	var row := PanelContainer.new()
	var line := UiStyle.box(Color.TRANSPARENT, Color(1, 1, 1, 0.06), 0, 0, 0)
	line.border_width_bottom = 1
	line.content_margin_left = 4
	line.content_margin_right = 4
	row.add_theme_stylebox_override("panel", line)
	row.custom_minimum_size.y = 48
	var box := HBoxContainer.new()
	row.add_child(box)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiStyle.SIZE_HEAD)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	box.add_child(control)
	add_child(row)

func _switch(text: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row(text, toggle)
	return toggle

func _muted() -> bool:
	if is_instance_valid(soundtrack):
		return soundtrack.muted
	var config := ConfigFile.new()
	return config.load("user://soundtrack.cfg") == OK and bool(config.get_value("music", "muted", false))

func _set_fullscreen(on: bool) -> void:
	if not _report(_keep("display", "fullscreen", on)):
		_fullscreen.set_pressed_no_signal(not on)
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

func _set_music(on: bool) -> void:
	if not is_instance_valid(soundtrack):
		return
	# headless and --mute-music launches have no player: only note the choice
	if is_instance_valid(soundtrack.player):
		if soundtrack.muted == on:
			soundtrack.toggle_mute()
		return
	var config := ConfigFile.new()
	config.set_value("music", "muted", not on)
	if _report(config.save(soundtrack.settings_path) == OK):
		soundtrack.muted = not on
	else:
		_music.set_pressed_no_signal(not on)

func _set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(v))
	_report(_keep("audio", "volume", v))

func _report(ok: bool) -> bool:
	_status.text = "" if ok else "Die Einstellung konnte nicht gespeichert werden."
	_status.visible = not ok
	return ok
