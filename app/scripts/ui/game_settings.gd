extends VBoxContainer
## The settings both menus show (main_menu.gd, pause_menu.gd), on three
## tabs as Victoria 3's (Ramon, 31.10.2026: "ich hätte gerne alles"):
## «Allgemein» full screen, the real portraits on or off, music on or off,
## its loudness and the yearly autosave; «Meldungen» for each kind of event whether it opens a window,
## is only a line in the notices or is not told, and whether the game
## pauses for it (ui/notice_settings.gd); «Tasten» the keys of the game,
## each changed by a click and the new key (ui/keys.gd). Each change is
## kept at once: the display and the autosave in user://display.cfg, the
## music where soundtrack.gd keeps it (user://soundtrack.cfg), the notices
## and the keys in their own files.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiTabs = preload("res://scripts/ui/ui_tabs.gd")
const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const Keys = preload("res://scripts/ui/keys.gd")
const NoticeSettings = preload("res://scripts/ui/notice_settings.gd")
const PortraitCache = preload("res://scripts/ui/portrait_cache.gd")
const STORE := "user://display.cfg"
const TABS: Array[String] = ["Allgemein", "Meldungen", "Tasten"]
const PAGE_PX := 430.0 # a page's height; longer ones scroll
const ICON_PX := 22.0
const WAITING := "Taste drücken …"

var soundtrack: Node # soundtrack.gd, the scene's own
var _tabs: UiTabs
var _pages: Array[ScrollContainer] = []
var _page: VBoxContainer # the page _head and _row fill
var _fullscreen: CheckButton
var _portraits: CheckButton
var _music: CheckButton
var _volume: HSlider
var _autosave: CheckButton
var _shows: Array[OptionButton] = []
var _pauses: Array[CheckButton] = []
var _keys := {} # action -> its Button
var _waiting := "" # the action whose new key is asked for
var _status: Label

## Puts the saved display, loudness and keys in place; the menu calls it on
## start. Command-line display arguments win over the saved ones.
static func apply_saved() -> void:
	Keys.setup()
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

func _init(music: Node, tab := 0) -> void:
	soundtrack = music
	add_theme_constant_override("separation", 10)
	_tabs = UiTabs.new()
	for t in TABS:
		_tabs.add_tab(t)
	add_child(_tabs)
	for t in TABS:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = PAGE_PX
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 0)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		add_child(scroll)
		_pages.append(scroll)
	_page = _pages[0].get_child(0)
	_fill_general()
	_page = _pages[1].get_child(0)
	_fill_notices()
	_page = _pages[2].get_child(0)
	_fill_keys()
	_status = Label.new()
	_status.add_theme_color_override("font_color", UiStyle.LOSS)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	add_child(_status)
	_tabs.tab_changed.connect(_on_tab)
	_tabs.current_tab = clampi(tab, 0, TABS.size() - 1)
	_on_tab(_tabs.current_tab)

func first_focus() -> Control:
	match _tabs.current_tab:
		1: return _shows[0]
		2: return _keys[Keys.ACTIONS[0][0]]
	return _fullscreen if _fullscreen.get_parent().get_parent().visible else _music

func _on_tab(index: int) -> void:
	_waiting = ""
	_show_keys()
	for i in _pages.size():
		_pages[i].visible = i == index
	_status.visible = false

# ------------------------------------------------------------------ Allgemein

func _fill_general() -> void:
	var config := ConfigFile.new()
	config.load(STORE)
	_head("Anzeige")
	_fullscreen = _switch("Vollbild")
	_fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
	_fullscreen.toggled.connect(_set_fullscreen)
	_fullscreen.get_parent().get_parent().visible = not OS.has_feature("mobile")
	_portraits = _switch("Echte Porträts")
	_portraits.set_pressed_no_signal(PortraitCache.real_on())
	_portraits.toggled.connect(_set_portraits)
	_portraits.tooltip_text = "Haut, Augen, Haar, Bärte und Kleider wie aus Blender statt einfacher Flächen. Neu gezeichnet werden die Gesichter, sobald ein Fenster sie wieder zeigt."
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

# ------------------------------------------------------------------ Meldungen

## Per kind: its icon and name, how it is told, and a switch for the pause.
func _fill_notices() -> void:
	_note("Fenster: ein Fenster geht auf, und die Meldung steht in der Liste. Meldung: nur eine Zeile in der Liste unten rechts und eine Nadel auf der Karte. Nichts: es wird nicht gemeldet. Pause: das Spiel hält an, wenn es auf der gezeigten Karte geschieht.")
	_head("Ereignisse")
	for k in NoticeSettings.KINDS.size():
		var how := OptionButton.new()
		for s in NoticeSettings.SHOW_NAMES:
			how.add_item(s)
		how.select(NoticeSettings.show_of(k))
		how.custom_minimum_size.x = 130
		how.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		how.item_selected.connect(_set_show.bind(k))
		var pause := CheckButton.new()
		pause.text = "Pause"
		pause.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pause.set_pressed_no_signal(NoticeSettings.pauses(k))
		pause.toggled.connect(_set_pause.bind(k))
		var both := HBoxContainer.new()
		both.add_theme_constant_override("separation", 12)
		both.add_child(how)
		both.add_child(pause)
		_row(NoticeSettings.KINDS[k], both, NoticeSettings.ICONS[k])
		_shows.append(how)
		_pauses.append(pause)
	_gap(12)
	var reset := Button.new()
	reset.text = "Alle zurücksetzen"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset.pressed.connect(_reset_notices)
	_page.add_child(reset)

func _set_show(index: int, kind: int) -> void:
	NoticeSettings.set_show(kind, index)

func _set_pause(on: bool, kind: int) -> void:
	NoticeSettings.set_pause(kind, on)

func _reset_notices() -> void:
	NoticeSettings.reset()
	for k in _shows.size():
		_shows[k].select(NoticeSettings.show_of(k))
		_pauses[k].set_pressed_no_signal(NoticeSettings.pauses(k))

# ------------------------------------------------------------------ Tasten

## The keys by group, each a button with its key: a click asks for the new.
func _fill_keys() -> void:
	if not InputMap.has_action(Keys.ACTIONS[0][0]):
		Keys.setup()
	_note("Auf eine Taste klicken, dann die neue drücken. Esc bricht ab. Esc und die Pfeiltasten bleiben fest.")
	var group := ""
	for a in Keys.ACTIONS:
		if a[2] != group:
			group = a[2]
			_head(group)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 34)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.toggle_mode = true
		b.pressed.connect(_ask_key.bind(a[0]))
		_row(a[1], b)
		_keys[a[0]] = b
	_gap(12)
	var reset := Button.new()
	reset.text = "Alle zurücksetzen"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset.pressed.connect(_reset_keys)
	_page.add_child(reset)
	_show_keys()

func _show_keys() -> void:
	for action in _keys:
		var b: Button = _keys[action]
		var waiting: bool = action == _waiting
		b.set_pressed_no_signal(waiting)
		b.text = WAITING if waiting else Keys.key_name(Keys.key_of(action))
		b.tooltip_text = "Vorgabe: %s" % Keys.key_name(Keys.default_of(action))

func _ask_key(action: String) -> void:
	_waiting = "" if _waiting == action else action
	_status.visible = false
	_show_keys()

## The key pressed while one is asked for: it goes to that action, unless
## it is Esc (cancels) or a fixed one; a click elsewhere cancels.
func _input(event: InputEvent) -> void:
	if _waiting == "" or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.pressed and not (_keys[_waiting] as Button).get_global_rect().has_point(event.position):
		_waiting = ""
		_show_keys()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var key: Key = (event as InputEventKey).keycode
	if key in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
		return # a modifier alone is not a key of the game
	var action := _waiting
	_waiting = ""
	if key != KEY_ESCAPE:
		if not Keys.can_take(key):
			_tell("%s bleibt fest und kann nicht belegt werden." % Keys.key_name(key))
		else:
			var taken := Keys.set_key(action, key)
			if taken != "":
				_tell("%s hatte «%s», jetzt ohne Taste." % [Keys.key_name(key), taken], UiStyle.DIM)
	_show_keys()

func _reset_keys() -> void:
	Keys.reset()
	_waiting = ""
	_status.visible = false
	_show_keys()

# ------------------------------------------------------------------ rows

func _head(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL + 1)
	l.add_theme_color_override("font_color", UiStyle.NAME)
	if _page.get_child_count() > 0:
		_gap(14)
	_page.add_child(l)

func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	l.add_theme_color_override("font_color", UiStyle.DIM)
	_page.add_child(l)

func _gap(height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	_page.add_child(gap)

## A row: the name at the left (after its icon, if any), the control at the
## right, a faint line below.
func _row(text: String, control: Control, icon_name := "") -> void:
	var row := PanelContainer.new()
	var line := UiStyle.box(Color.TRANSPARENT, Color(1, 1, 1, 0.06), 0, 0, 0)
	line.border_width_bottom = 1
	line.content_margin_left = 4
	line.content_margin_right = 4
	row.add_theme_stylebox_override("panel", line)
	row.custom_minimum_size.y = 48
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	row.add_child(box)
	var icon := Vic3.icon(icon_name) if icon_name != "" else null
	if icon != null:
		var r := TextureRect.new()
		r.texture = icon
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.modulate = UiStyle.KIND
		box.add_child(r)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiStyle.SIZE_HEAD)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(l)
	box.add_child(control)
	_page.add_child(row)

func _switch(text: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row(text, toggle)
	return toggle

# ------------------------------------------------------------------ changes

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

func _set_portraits(on: bool) -> void:
	if not _report(_keep("portraits", "real", on)):
		_portraits.set_pressed_no_signal(not on)
		return
	if get_tree().root.has_meta("portrait_cache"):
		var cache = get_tree().root.get_meta("portrait_cache")
		if is_instance_valid(cache):
			cache.set_real(on)

func _report(ok: bool) -> bool:
	if ok:
		_status.visible = false
	else:
		_tell("Die Einstellung konnte nicht gespeichert werden.")
	return ok

func _tell(text: String, colour := UiStyle.LOSS) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)
	_status.visible = true
