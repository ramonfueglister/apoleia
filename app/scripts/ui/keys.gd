extends RefCounted
## The game's keys as InputMap actions, each with its key from the settings
## (ui/game_settings.gd «Tasten», Ramon 31.10.2026, as Victoria 3's input
## bindings): setup() puts them in place at start, the saved choices over
## the defaults; set_key() changes one and keeps it in user://keys.cfg. The
## scripts ask pressed(event, action) instead of a keycode. A key may serve one action only: giving it to another takes it
## from the first. Esc (menus, closing) and the arrow keys stay fixed.

const STORE := "user://keys.cfg"
## action, name, group, default key; further keys (keypad) stay fixed
const ACTIONS := [
	["apoleia_pause", "Pause / weiter", "Spiel", KEY_SPACE],
	["apoleia_slower", "Langsamer", "Spiel", KEY_BRACKETLEFT],
	["apoleia_faster", "Schneller", "Spiel", KEY_BRACKETRIGHT],
	["apoleia_quicksave", "Schnell speichern", "Spiel", KEY_F8],
	["apoleia_quickload", "Schnell laden", "Spiel", KEY_F9],
	["apoleia_tables", "Statistik", "Fenster", KEY_T],
	["apoleia_events", "Ereignisse", "Fenster", KEY_E],
	["apoleia_outliner", "Im Blick (Outliner)", "Fenster", KEY_O],
	["apoleia_up", "Karte nach oben", "Karte", KEY_W],
	["apoleia_down", "Karte nach unten", "Karte", KEY_S],
	["apoleia_left", "Karte nach links", "Karte", KEY_A],
	["apoleia_right", "Karte nach rechts", "Karte", KEY_D],
	["apoleia_zoom_in", "Näher heran", "Karte", KEY_PLUS],
	["apoleia_zoom_out", "Weiter weg", "Karte", KEY_MINUS],
	["apoleia_people", "Menschen als Punkte", "Karte", KEY_P],
	["apoleia_farm", "Hof bauen", "Bauen", KEY_1],
	["apoleia_field", "Feld anlegen", "Bauen", KEY_2],
	["apoleia_music", "Musik an / aus", "Musik", KEY_M],
	["apoleia_next_song", "Nächstes Stück", "Musik", KEY_N],
]
## keys that also do it and cannot be changed
const EXTRA := {"apoleia_zoom_in": [KEY_EQUAL, KEY_KP_ADD], "apoleia_zoom_out": [KEY_KP_SUBTRACT]}
const FIXED: Array[Key] = [KEY_ESCAPE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]

## The actions in place, the saved keys over the defaults. Safe to call
## more than once.
static func setup() -> void:
	var saved := ConfigFile.new()
	saved.load(STORE)
	for a in ACTIONS:
		var action: String = a[0]
		var key := int(saved.get_value("keys", action, a[3]))
		_bind(action, key)

## `event` presses the key of `action`, not held down; Shift and the like
## do not matter, as before the settings ("+" is Shift and = on many keyboards).
static func pressed(event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action):
		setup()
	return event.is_action_pressed(action)

## The key of `action` is held down now.
static func held(action: String) -> bool:
	if not InputMap.has_action(action):
		setup()
	return Input.is_action_pressed(action)

## The key of `action` now (KEY_NONE without one).
static func key_of(action: String) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return (e as InputEventKey).keycode
	return KEY_NONE

## Gives `key` to `action` and keeps it; the action that had it loses it.
## Returns the name of that action, "" if none.
static func set_key(action: String, key: Key) -> String:
	var taken := ""
	for a in ACTIONS:
		if a[0] != action and key_of(a[0]) == key:
			taken = a[1]
			_bind(a[0], KEY_NONE)
			_keep(a[0], KEY_NONE)
	_bind(action, key)
	_keep(action, key)
	return taken

## Every key back to its default.
static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	setup()

static func default_of(action: String) -> Key:
	for a in ACTIONS:
		if a[0] == action:
			return a[3]
	return KEY_NONE

## "Leertaste", "F8", "–" for none.
static func key_name(key: Key) -> String:
	match key:
		KEY_NONE: return "–"
		KEY_SPACE: return "Leertaste"
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_PLUS: return "+"
		KEY_MINUS: return "−"
	return OS.get_keycode_string(key)

static func can_take(key: Key) -> bool:
	return key != KEY_NONE and not key in FIXED

static func _bind(action: String, key: int) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	if key != KEY_NONE:
		InputMap.action_add_event(action, _event(key))
	for extra in EXTRA.get(action, []):
		InputMap.action_add_event(action, _event(extra))

static func _event(key: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = key as Key
	return e

static func _keep(action: String, key: int) -> void:
	var saved := ConfigFile.new()
	saved.load(STORE)
	saved.set_value("keys", action, key)
	saved.save(STORE)
