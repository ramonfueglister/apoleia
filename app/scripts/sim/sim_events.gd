extends CanvasLayer
## What happens in the simulation, as EU5's notices: a list at the bottom
## right of the latest events in view (hunger deaths, moves, thefts, alms,
## farms taken over or handed to heirs; sim/src/events.rs), newest first,
## one line per day and kind with how often and how much. A click on a line
## flies the camera to where it happened. E shows and hides the list.
##
## ApoleiaPeople.ask_events(since, window) asks the sim thread between two
## days; take_events() returns {} until the answer is there, then one
## packed array per field (day, kind, household, pid, other, amount, at,
## to) and the names of the kinds (sim/godot/src/trips.rs events_to_dict).
## The list is asked again once a sim day, at most once a second, for the
## days the simulation keeps (KEEP_DAYS) in the view and around it.
##
## Command line (after --): --no-events starts with the list hidden.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const KEEP_DAYS := 60 # apoleia_sim::events::KEEP_DAYS
const LINES := 8
const ASK_SECONDS := 1.0
const MARGIN := 0.5 # the window asked for reaches this share of the view width beyond it
const FLY_KM := 6.0 # a farmstead's width on screen; a 25 km cell gets its own
## by kind (sim/src/events.rs): hunger death, moved, left the map, joined
## relatives, theft, alms, tent moved, farm taken, heir, to the tents,
## Lex Manciana, farm left
const KIND_COLOURS: Array[Color] = [SimTables.NEGATIVE, SimTables.SECONDARY, SimTables.SECONDARY, SimTables.SECONDARY,
	Color("e0a060"), SimTables.GOLD, SimTables.SECONDARY, Color("9cc47e"), Color("9cc47e"), Color("e0a060"),
	Color("9cc47e"), Color("e0a060")]
const THEFT := 4
const ALMS := 5
const MOVED := 1

var people: RefCounted
var landscape: Node3D
var open := true
var _asked := false
var _asked_day := -1
var _asked_msec := -100000
var _entries: Array[Dictionary] = []
var _panel: PanelContainer
var _list: VBoxContainer
var _stand: Label
var _open_button: Button

## `sim` is ApoleiaPeople, `scene` the landscape whose camera a line moves.
func setup(sim: RefCounted, scene: Node3D) -> void:
	people = sim
	landscape = scene
	name = "SimEvents"
	layer = 2
	if "--no-events" in OS.get_cmdline_user_args():
		open = false
	_build()
	_show(open)

func _process(_delta: float) -> void:
	if not open or people == null:
		return
	if _asked:
		var answer: Dictionary = people.take_events()
		if answer.is_empty():
			return
		_asked = false
		_group(answer)
		_fill()
		return
	var day: int = people.day()
	if day == _asked_day or Time.get_ticks_msec() - _asked_msec < ASK_SECONDS * 1000.0:
		return
	var centre: Vector2 = landscape.target if "target" in landscape else Vector2.ZERO
	var width: float = landscape.width if "width" in landscape else 360.0
	var half := width * (0.5 + MARGIN)
	people.ask_events(day - KEEP_DAYS, centre.x - half, centre.y - half, centre.x + half, centre.y + half)
	_asked = true
	_asked_day = day
	_asked_msec = Time.get_ticks_msec()

## One entry per day and kind, newest first, at most LINES.
func _group(e: Dictionary) -> void:
	var days: PackedInt64Array = e.day
	var kinds: PackedInt32Array = e.kind
	var amounts: PackedInt64Array = e.amount
	var at: PackedVector2Array = e.at
	var names: PackedStringArray = e.names
	var by := {}
	var order: Array[Vector2i] = []
	for i in range(days.size() - 1, -1, -1):
		var key := Vector2i(days[i], kinds[i])
		if not by.has(key):
			if order.size() >= LINES:
				continue
			by[key] = {"day": int(days[i]), "kind": kinds[i], "name": names[kinds[i]] if kinds[i] < names.size() else "?",
				"n": 0, "amount": 0, "lo": at[i], "hi": at[i]}
			order.append(key)
		var g: Dictionary = by[key]
		g.n += 1
		g.amount += amounts[i]
		g.lo = (g.lo as Vector2).min(at[i])
		g.hi = (g.hi as Vector2).max(at[i])
	_entries.clear()
	for key in order:
		_entries.append(by[key])
	_stand.text = SimTables._date(int(people.day()))

func _fill() -> void:
	for child in _list.get_children():
		child.free()
	_place.call_deferred() # as tall as the new lines
	if _entries.is_empty():
		var quiet := Label.new()
		quiet.text = "Hier ist in den letzten %d Tagen nichts geschehen." % KEEP_DAYS
		quiet.add_theme_color_override("font_color", SimTables.SECONDARY)
		quiet.add_theme_font_size_override("font_size", 13)
		_list.add_child(quiet)
		return
	for g in _entries:
		var line := Button.new()
		line.flat = true
		line.alignment = HORIZONTAL_ALIGNMENT_LEFT
		line.focus_mode = Control.FOCUS_NONE
		line.text = "%s   %s" % [_day(g.day), _text(g)]
		line.add_theme_font_size_override("font_size", 13)
		var colour: Color = KIND_COLOURS[g.kind] if g.kind < KIND_COLOURS.size() else SimTables.INK
		line.add_theme_color_override("font_color", colour)
		line.add_theme_color_override("font_hover_color", Color.WHITE)
		line.pressed.connect(_fly.bind(g))
		_list.add_child(line)

## "Hungertod ×3", "Diebstahl ×2, 140 kg", "Umzug ×4, 19 Menschen".
static func _text(g: Dictionary) -> String:
	var text: String = g.name
	if g.n > 1:
		text += " ×%d" % g.n
	if g.kind == THEFT or g.kind == ALMS:
		text += ", %s kg" % SimTables._int(g.amount)
	elif g.kind == MOVED and g.amount > 0:
		text += ", %s Menschen" % SimTables._int(g.amount)
	return text

## "12. Mar.": the day of the month.
static func _day(day: int) -> String:
	return "%d. %s." % [day % SimTables.MONTH + 1, SimTables.MONTHS[(day % SimTables.YEAR) / SimTables.MONTH].left(3)]

func _fly(g: Dictionary) -> void:
	if landscape == null or not "_goal_target" in landscape:
		return
	var lo: Vector2 = g.lo
	var hi: Vector2 = g.hi
	landscape._goal_target = (lo + hi) * 0.5
	landscape._goal_width = clampf(maxf(hi.x - lo.x, hi.y - lo.y) * 1.6, FLY_KM, SimTables.FLY_MAX_KM)

func _show(on: bool) -> void:
	open = on
	_panel.visible = on
	_open_button.visible = not on

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_show(not open)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = SimTables._theme()
	add_child(root)
	_open_button = Button.new()
	_open_button.text = "Ereignisse  (E)"
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.pressed.connect(func(): _show(true))
	root.add_child(_open_button)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", SimTables._box(Color(SimTables.BACKGROUND, 0.92), Color(SimTables.GOLD, 0.8), 2, 4, 10))
	root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Ereignisse"
	title.add_theme_font_override("font", SimTables._serif())
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", SimTables.GOLD)
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_stand = Label.new()
	_stand.add_theme_color_override("font_color", SimTables.SECONDARY)
	_stand.add_theme_font_size_override("font_size", 12)
	head.add_child(_stand)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): _show(false))
	head.add_child(close)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	column.add_child(_list)
	_fill()

func _ready() -> void:
	get_viewport().size_changed.connect(_place)
	_place()

## Bottom right, as tall as its lines.
func _place() -> void:
	if not is_inside_tree():
		return
	var screen := get_viewport().get_visible_rect().size
	_panel.size = Vector2(380, 0)
	_panel.position = screen - _panel.get_combined_minimum_size().max(Vector2(380, 0)) - Vector2(12, 12)
	_open_button.position = screen - _open_button.get_combined_minimum_size() - Vector2(12, 12)
