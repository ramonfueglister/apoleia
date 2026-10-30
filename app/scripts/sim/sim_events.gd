extends CanvasLayer
## What happens in the simulation, as EU5's notices: a list at the bottom
## right of the latest events in view (hunger deaths, moves, thefts, alms,
## farms taken over or handed to heirs; sim/src/events.rs), newest first,
## one line per day and kind with how often and how much. A click on a line
## flies the camera to where it happened. E shows and hides the list.
##
## The events of the last PIN_DAYS also stand on the map as pins in the
## colour of their kind, those of one kind close together (a fourteenth of
## the view) as one pin with their number; pointing at a pin names them, a
## click flies there. Farm events stand at the farmstead, the others at the
## middle of their 25 km cell.
##
## ApoleiaPeople.ask_events(since, window) asks the sim thread between two
## days; take_events() returns {} until the answer is there, then one
## packed array per field (day, kind, household, pid, other, amount, at,
## to) and the names of the kinds (sim/godot/src/trips.rs events_to_dict).
## The list is asked again once a sim day or when the view moves, at most
## once a second, for the
## days the simulation keeps (KEEP_DAYS) in the view and around it, at
## least REACH_MIN_KM around (from a village there was nothing to list).
##
## The list is asked for while it is hidden too: every answer goes out with
## `answered`, and people_trips.gd plays the newest events as scenes on the
## map (a family moving with its handcart, a thief, a funeral).
##
## Command line (after --): --no-events starts with the list hidden.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const NoticeList = preload("res://scripts/ui/notice_list.gd")
const KEEP_DAYS := 60 # apoleia_sim::events::KEEP_DAYS
const LINES := 8
const ASK_SECONDS := 1.0
const MARGIN := 0.5 # the window asked for reaches this share of the view width beyond it
const REACH_MIN_KM := 30.0 # and at least this far from the middle: moves are placed at the 25 km cell's centre
const FLY_KM := 6.0 # a farmstead's width on screen; a 25 km cell gets its own
## by kind (sim/src/events.rs): hunger death, moved, left the map, joined
## relatives, theft, alms, tent moved, farm taken, heir, to the tents,
## Lex Manciana, farm left
const KIND_COLOURS: Array[Color] = [SimTables.NEGATIVE, SimTables.SECONDARY, SimTables.SECONDARY, SimTables.SECONDARY,
	Color("e0a060"), SimTables.GOLD, SimTables.SECONDARY, Color("9cc47e"), Color("9cc47e"), Color("e0a060"),
	Color("9cc47e"), Color("e0a060")]
## each kind's icon in res://assets/ui/icons/, in the order above
const KIND_ICONS: Array[String] = ["death-skull", "walking-boot", "exit-door", "family-house", "robber-hand", "bread",
	"camping-tent", "barn", "family-tree", "camping-tent", "scroll-quill", "exit-door"]
const PIN_DAYS := 15
const PINS_MAX := 40
const PIN_GRID := 14.0 # pins closer than the view width over this merge
const THEFT := 4
const ALMS := 5
const MOVED := 1

## Every answer of the sim thread, also while the list is hidden.
signal answered(events: Dictionary)

var people: RefCounted
var landscape: Node3D
var open := true
var _asked := false
var _asked_day := -1
var _asked_msec := -100000
var _asked_at := Vector3.INF # centre and view width of the last ask
var _entries: Array[Dictionary] = []
var _panel: NoticeList
var _list: VBoxContainer
var _stand: Label
var _open_button: Button
var _last := {} # the last answer, for the pins
var _pins: Array[Dictionary] = [] # at (world km) and the pin
var _pins_root: Control
var _pins_width := 0.0 # view width the pins were merged for

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
	if people == null:
		return
	if _asked:
		var answer: Dictionary = people.take_events()
		if not answer.is_empty():
			_asked = false
			_last = answer
			if open:
				_refresh()
			answered.emit(answer)
	if open:
		_place_pins()
	if _asked:
		return
	var day: int = people.day()
	var centre: Vector2 = landscape.target if "target" in landscape else Vector2.ZERO
	var width: float = landscape.width if "width" in landscape else 360.0
	var moved := _asked_at.x == INF or Vector2(_asked_at.x, _asked_at.y).distance_to(centre) > width * 0.3 \
		or absf(log(width / _asked_at.z)) > 0.3
	if (day == _asked_day and not moved) or Time.get_ticks_msec() - _asked_msec < ASK_SECONDS * 1000.0:
		return
	_asked_at = Vector3(centre.x, centre.y, width)
	var half := maxf(width * (0.5 + MARGIN), REACH_MIN_KM)
	people.ask_events(day - KEEP_DAYS, centre.x - half, centre.y - half, centre.x + half, centre.y + half)
	_asked = true
	_asked_day = day
	_asked_msec = Time.get_ticks_msec()

## The list and the pins from the last answer.
func _refresh() -> void:
	if _last.is_empty():
		return
	_group(_last)
	_fill()
	_make_pins()

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

## Pins for the events of the last PIN_DAYS: one per kind and patch of the
## view (its width over PIN_GRID), newest first, at most PINS_MAX.
func _make_pins() -> void:
	for pin in _pins:
		pin.node.queue_free()
	_pins.clear()
	if _last.is_empty():
		return
	var width: float = landscape.width if "width" in landscape else 360.0
	_pins_width = width
	var grid := maxf(width / PIN_GRID, 0.3)
	var days: PackedInt64Array = _last.day
	var kinds: PackedInt32Array = _last.kind
	var at: PackedVector2Array = _last.at
	var names: PackedStringArray = _last.names
	var today: int = people.day()
	var by := {}
	var order: Array[Vector3i] = []
	for i in range(days.size() - 1, -1, -1):
		if days[i] < today - PIN_DAYS:
			break
		var cell := (at[i] / grid).floor()
		var key := Vector3i(int(cell.x), int(cell.y), kinds[i])
		if not by.has(key):
			if order.size() >= PINS_MAX:
				continue
			by[key] = {"kind": kinds[i], "n": 0, "sum": Vector2.ZERO, "day": int(days[i]),
				"name": names[kinds[i]] if kinds[i] < names.size() else "?"}
			order.append(key)
		by[key].n += 1
		by[key].sum += at[i]
	for key in order:
		var g: Dictionary = by[key]
		var pin := Pin.new()
		pin.colour = KIND_COLOURS[g.kind] if g.kind < KIND_COLOURS.size() else SimTables.INK
		pin.count = g.n
		pin.tooltip_text = "%s%s, zuletzt %s" % [g.name, " ×%d" % g.n if g.n > 1 else "", _day(g.day)]
		var place: Vector2 = g.sum / float(g.n)
		pin.chosen.connect(_fly.bind({"lo": place, "hi": place}))
		_pins_root.add_child(pin)
		_pins.append({"at": place, "node": pin})

## Each pin's stem on its place on the screen; merged anew when the view
## width changed by a third.
func _place_pins() -> void:
	var width: float = landscape.width if "width" in landscape else 360.0
	if not _pins.is_empty() and absf(log(width / maxf(_pins_width, 0.001))) > 0.3:
		_make_pins()
	var camera: Camera3D = landscape.camera if "camera" in landscape else null
	var terrain = landscape.terrain if "terrain" in landscape else null
	if camera == null or terrain == null:
		return
	var screen := get_viewport().get_visible_rect()
	for pin in _pins:
		var at: Vector2 = pin.at
		var p := Vector3(at.x, terrain.ground_y(at), at.y)
		var node: Control = pin.node
		var tip := camera.unproject_position(p)
		node.visible = not camera.is_position_behind(p) and screen.grow(-4.0).has_point(tip)
		node.position = tip - Vector2(Pin.SIZE.x * 0.5, Pin.SIZE.y)

func _fill() -> void:
	_place.call_deferred() # as tall as the new lines
	if _entries.is_empty():
		_panel.show_quiet("Hier ist in den letzten %d Tagen nichts geschehen." % KEEP_DAYS)
		return
	var rows := []
	for g in _entries:
		rows.append({"day": _day(g.day), "text": _text(g), "entry": g,
			"colour": KIND_COLOURS[g.kind] if g.kind < KIND_COLOURS.size() else SimTables.INK,
			"icon": KIND_ICONS[g.kind] if g.kind < KIND_ICONS.size() else ""})
	_panel.show_rows(rows)

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
	_pins_root.visible = on
	_open_button.visible = not on
	if on:
		_refresh() # the answers that came while it was hidden

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_show(not open)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = SimTables._theme()
	add_child(root)
	_pins_root = Control.new()
	_pins_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pins_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pins_root)
	_open_button = NoticeList.open_button()
	_open_button.pressed.connect(func(): _show(true))
	root.add_child(_open_button)
	_panel = NoticeList.new()
	_panel.chosen.connect(_fly)
	_panel.closing.connect(func(): _show(false))
	root.add_child(_panel)
	_stand = _panel.stand
	_list = _panel.list
	_fill()

func _ready() -> void:
	get_viewport().size_changed.connect(_place)
	_place()

## Bottom right, as tall as its lines.
func _place() -> void:
	if not is_inside_tree():
		return
	var screen := get_viewport().get_visible_rect().size
	_panel.size = Vector2(NoticeList.WIDTH, 0)
	_panel.position = screen - _panel.get_combined_minimum_size() - Vector2(18, 18) # room for the rim
	_open_button.position = screen - _open_button.get_combined_minimum_size() - Vector2(12, 12)

## A pin on the map: a disc in the colour of its kind on a short stem, with
## the number of events it stands for.
class Pin extends Control:
	const SIZE := Vector2(22, 30)
	signal chosen
	var colour := Color.WHITE
	var count := 1

	func _init() -> void:
		size = SIZE
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var c := Vector2(SIZE.x * 0.5, 11.0)
		draw_line(Vector2(c.x, 18.0), Vector2(c.x, SIZE.y), SimTables.BACKGROUND, 2.0)
		draw_circle(c, 10.0, SimTables.BACKGROUND)
		draw_circle(c, 8.0, colour)
		if count > 1:
			var label := str(count) if count < 100 else "99+"
			draw_string(get_theme_default_font(), Vector2(0.0, 15.0), label, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 11, SimTables.BACKGROUND)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit()
			accept_event()
