extends CanvasLayer
## The in-game menu (Esc), as EU5's: the game stands still, the picture
## behind goes soft and dark, a small window in the middle offers
## Weiterspielen, Spiel speichern, Spiel laden, Einstellungen, Zum Hauptmenü
## and Spiel beenden. Esc opens it only when nothing else wanted the key
## (a window, a chosen person or a build tool close first): this node is
## the landscape's first child, so its _unhandled_input comes last.
##
## It also keeps the yearly autosave (ui/game_settings.gd). A save game
## chosen in the main menu plays again behind the loading screen
## (landscape.gd, SaveGames.pending).

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiWindow = preload("res://scripts/ui/ui_window.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const MenuPanel = preload("res://scripts/ui/menu_panel.gd")
const SaveList = preload("res://scripts/ui/save_list.gd")
const SaveGames = preload("res://scripts/ui/save_games.gd")
const GameSettings = preload("res://scripts/ui/game_settings.gd")
const SimTables = preload("res://scripts/sim/sim_tables.gd")
const MAIN_MENU := "res://main_menu.tscn"
const LAYER := 30 # over the windows (10) and tooltips (20)
const SETTINGS_PX := 640.0 # the settings' window: room for the notices' two controls
const BLUR := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 2.5).rgb;
	COLOR = vec4(mix(c * 0.85, vec3(0.04, 0.055, 0.075), 0.6), 1.0);
}
"""

var clock: Node # sim/game_clock.gd; null without the people's GDExtension
var people: RefCounted # ApoleiaPeople
var soundtrack: Node
var open := false
var _root: Control
var _panel: MenuPanel # the window shown now
var _main: MenuPanel # the pause menu itself, kept while a page is open
var _saves: SaveList
var _resume: Button
var _saving := {} # {path, name} while the sim writes a save
var _year := -1 # the game year last seen, for the autosave

func setup(game_clock: Node, music: Node) -> void:
	name = "PauseMenu"
	add_to_group("pause_menu")
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	clock = game_clock
	people = clock.people if clock != null else null
	soundtrack = music
	if is_instance_valid(soundtrack):
		soundtrack.process_mode = Node.PROCESS_MODE_ALWAYS # the music plays on in the menu
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UiStyle.theme()
	_root.visible = false
	add_child(_root)
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.04, 0.055, 0.075, 0.7)
	var shader := Shader.new()
	shader.code = BLUR
	var blur := ShaderMaterial.new()
	blur.shader = shader
	veil.material = blur
	_root.add_child(veil)
	var hint := Label.new()
	hint.text = "Esc schliesst · Das Spiel steht still, solange das Menü offen ist"
	hint.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL + 1)
	hint.add_theme_color_override("font_color", UiStyle.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(hint)

func show_menu() -> void:
	if open:
		return
	open = true
	get_tree().paused = true
	_root.visible = true
	_main = MenuPanel.new("Pause", 380.0)
	_main.closed.connect(hide_menu)
	if people != null:
		_main.set_subtitle(SimTables._date(people.day()))
	var b := _main.body
	_resume = MenuPanel.button("Weiterspielen", hide_menu, false, "play-button")
	b.add_child(_resume)
	MenuPanel.gap(b, 2)
	var can := clock != null
	for entry in [["Spiel speichern", _show_saves.bind(true), "save"], ["Spiel laden", _show_saves.bind(false), "open-book"]]:
		var e := MenuPanel.button(entry[0], entry[1], false, entry[2])
		e.disabled = not can
		b.add_child(e)
	b.add_child(MenuPanel.button("Einstellungen", _show_settings, false, "cog"))
	MenuPanel.gap(b, 18)
	b.add_child(MenuPanel.button("Zum Hauptmenü", _confirm.bind("Zum Hauptmenü?", "Zum Hauptmenü", _to_main_menu), true, "eagle-emblem"))
	b.add_child(MenuPanel.button("Spiel beenden", _confirm.bind("Spiel beenden?", "Beenden", get_tree().quit), true, "exit-door"))
	_show(_main)
	_resume.grab_focus.call_deferred()

func hide_menu() -> void:
	if not open:
		return
	open = false
	for p in [_panel, _main]:
		if is_instance_valid(p):
			p.queue_free()
	_panel = null
	_main = null
	_saves = null
	_root.visible = false
	get_tree().paused = false

## Shows one window, the pause menu hidden while a page lies over it.
func _show(panel: MenuPanel) -> void:
	if is_instance_valid(_panel) and _panel != _main:
		_panel.queue_free()
	if is_instance_valid(_main):
		_main.visible = panel == _main
	_panel = panel
	if panel.get_parent() == null:
		_root.add_child(panel)

func _back() -> void:
	_saves = null
	_show(_main)
	_resume.grab_focus.call_deferred()

func _page(title: String, width: float) -> MenuPanel:
	var panel := MenuPanel.new(title, width)
	panel.closed.connect(_back)
	return panel

func _show_saves(can_save: bool) -> void:
	var panel := _page("Spiel speichern" if can_save else "Spiel laden", 640.0)
	_saves = SaveList.new(can_save)
	_saves.load_chosen.connect(_load)
	_saves.save_asked.connect(_save)
	panel.body.add_child(_saves)
	_show(panel)
	_saves.first_focus().grab_focus.call_deferred()

## The settings at their tab `tab` (0 Allgemein, 1 Meldungen, 2 Tasten);
## the notices' settings button opens them from the game.
func show_settings(tab := 0) -> void:
	if not open:
		show_menu()
	_show_settings(tab)

func _show_settings(tab := 0) -> void:
	var panel := _page("Einstellungen", SETTINGS_PX)
	var settings := GameSettings.new(soundtrack, tab)
	panel.body.add_child(settings)
	MenuPanel.gap(panel.body, 8)
	panel.body.add_child(MenuPanel.button("Fertig", _back))
	_show(panel)
	settings.first_focus().grab_focus.call_deferred()

## Asks once before the game is left: what is not saved is lost.
func _confirm(question: String, yes: String, action: Callable) -> void:
	var panel := _page(question, 420.0)
	var text := Label.new()
	text.text = "Was seit dem letzten Speichern geschehen ist, geht verloren."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", UiStyle.TEXT)
	panel.body.add_child(text)
	MenuPanel.gap(panel.body, 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.body.add_child(row)
	var no := MenuPanel.button("Abbrechen", _back)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no)
	var go := MenuPanel.button(yes, action)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(go)
	_show(panel)
	no.grab_focus.call_deferred()

func _load(path: String) -> void:
	hide_menu()
	clock.load_game(path)

func _save(path: String, label: String) -> void:
	if not _saving.is_empty() or clock._saving or clock._loading:
		return
	_saving = {"path": path, "name": label}
	people.save_game(ProjectSettings.globalize_path(path))
	if is_instance_valid(_panel) and _panel != _main:
		_panel.set_subtitle("Wird gespeichert …")

func _to_main_menu() -> void:
	get_tree().paused = false
	# the windows and tooltips hang at the root and would outlive the game
	for layer in [UiWindow._shared, Tooltips._shared]:
		if is_instance_valid(layer):
			layer.queue_free()
	get_tree().change_scene_to_file(MAIN_MENU)

func _process(_delta: float) -> void:
	if people == null:
		return
	if not _saving.is_empty():
		var s: Dictionary = people.take_saved()
		if not s.is_empty():
			if s.ok:
				SaveGames.remember(_saving.path, _saving.name, int(s.day))
			var note: String = "Gespeichert: %s" % SimTables._date(int(s.day)) if s.ok else "Speichern ging nicht: %s" % s.error
			_saving = {}
			if is_instance_valid(_saves):
				_saves.refresh()
			if is_instance_valid(_panel) and _panel != _main:
				_panel.set_subtitle(note)
			elif not open:
				clock._tell(note)
	if open or clock._loading:
		_year = -1
		return
	var year: int = people.day() / SimTables.YEAR
	if _year >= 0 and year > _year and GameSettings.autosave_on() and _saving.is_empty() and not clock._saving:
		_save(SaveGames.path_for("Autosave"), "Autosave")
	_year = year

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if not open:
		show_menu()
	elif _panel != _main:
		_back()
	else:
		hide_menu()
	get_viewport().set_input_as_handled()
