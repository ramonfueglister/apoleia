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
## How each kind is told the player sets in the settings (Ramon,
## 31.10.2026, as Victoria 3's messages; ui/notice_settings.gd): as a
## window, only as a line and a pin, or not at all, and whether the game
## pauses. By default the rare ones (theft, a farm taken, cleared under the
## Lex Manciana or given up) open an event window in the Victoria 3 look
## (ui/event_window.gd) while the list is shown: only events of the last
## WINDOW_DAYS, each once, at most one window at a time and one every
## WINDOW_GAP_S seconds, so a fast game is not buried in windows. Its
## people open the person's window (person_chosen, people_dots.gd). A kind
## set to pause asks the game clock to stop (pause_asked) when one of the
## last WINDOW_DAYS happens in view, each once. A line's star pins it in
## the outliner (ui/outliner.gd).
##
## Command line (after --): --no-events starts with the list hidden,
## --no-event-windows opens no event windows.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const NoticeList = preload("res://scripts/ui/notice_list.gd")
const EventWindow = preload("res://scripts/ui/event_window.gd")
const Keys = preload("res://scripts/ui/keys.gd")
const NoticeSettings = preload("res://scripts/ui/notice_settings.gd")
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
const HUNGER_DEATH := 0
const MOVED := 1
const LEFT_MAP := 2
const JOINED := 3
const TENT_MOVED := 6
const HEIR := 8
const TO_TENT := 9
const FARM_TAKEN := 7
const MANCIANA := 10
const FARM_LEFT := 11
## births, weddings and deaths of old age or illness: daily all over, so
## only scenes on the map (people_trips.gd), not lines or pins
const FAMILY_FROM := 12
const WINDOW_DAYS := 2
const WINDOW_GAP_S := 30.0

## Every answer of the sim thread, also while the list is hidden.
signal answered(events: Dictionary)
## A person named in an event window was chosen.
signal person_chosen(pid: int, household: int)
## An event of a kind set to pause happened in view (sim/game_clock.gd stops).
signal pause_asked(text: String)

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
var _windows := true
var _window: Control # the event window open now, if any
var _window_msec := -1000000
var _window_seen := {} # rare events of the last WINDOW_DAYS already shown or passed over
var _pause_seen := {} # events of the last WINDOW_DAYS that paused or would have

## `sim` is ApoleiaPeople, `scene` the landscape whose camera a line moves.
func setup(sim: RefCounted, scene: Node3D) -> void:
	people = sim
	landscape = scene
	name = "SimEvents"
	layer = 2
	if "--no-events" in OS.get_cmdline_user_args():
		open = false
	if "--no-event-windows" in OS.get_cmdline_user_args():
		_windows = false
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
				_window_for(answer)
			_pause_for(answer)
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
		if kinds[i] >= FAMILY_FROM or NoticeSettings.show_of(kinds[i]) == NoticeSettings.NOTHING:
			continue
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
		if kinds[i] >= FAMILY_FROM or NoticeSettings.show_of(kinds[i]) == NoticeSettings.NOTHING:
			continue
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

## A line pinned in the outliner (ui/outliner.gd): its text and day, and
## where it happened.
func _pin(g: Dictionary) -> void:
	var at: Vector2 = ((g.lo as Vector2) + (g.hi as Vector2)) * 0.5
	get_tree().call_group("outliner", "pin", "event", hash([g.day, g.kind, at]), "%s, %s" % [_text(g), _day(g.day)], at)

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

## An event window for the newest event in view of a kind told as a window
## (ui/notice_settings.gd) not yet shown, if no window is open and the last
## one is WINDOW_GAP_S old. The others of the same answer are passed over:
## they stay in the list.
func _window_for(e: Dictionary) -> void:
	if not _windows or not e.has("day"):
		return
	var days: PackedInt64Array = e.day
	var kinds: PackedInt32Array = e.kind
	var at: PackedVector2Array = e.at
	var today: int = people.day()
	var centre: Vector2 = landscape.target if "target" in landscape else Vector2.ZERO
	var width: float = landscape.width if "width" in landscape else 360.0
	var view := Rect2(centre - Vector2(width, width) * 0.5, Vector2(width, width))
	var free := not is_instance_valid(_window) and Time.get_ticks_msec() - _window_msec >= WINDOW_GAP_S * 1000.0
	var seen := {}
	for i in range(days.size() - 1, -1, -1):
		if days[i] < today - WINDOW_DAYS:
			break
		if kinds[i] >= FAMILY_FROM or NoticeSettings.show_of(kinds[i]) != NoticeSettings.WINDOW or not view.has_point(at[i]):
			continue
		var key := "%d:%d:%d" % [days[i], kinds[i], e.household[i]]
		seen[key] = true
		if _window_seen.has(key) or not free:
			continue
		free = false
		_open_window(e, i)
	_window_seen = seen

## Asks the clock to pause for the newest event in view of a kind set to
## pause that it has not paused for yet; the others of the answer count as
## seen, so one pause covers them.
func _pause_for(e: Dictionary) -> void:
	if not e.has("day"):
		return
	var days: PackedInt64Array = e.day
	var kinds: PackedInt32Array = e.kind
	var at: PackedVector2Array = e.at
	var today: int = people.day()
	var centre: Vector2 = landscape.target if "target" in landscape else Vector2.ZERO
	var width: float = landscape.width if "width" in landscape else 360.0
	var view := Rect2(centre - Vector2(width, width) * 0.5, Vector2(width, width))
	var seen := {}
	var newest := -1
	for i in range(days.size() - 1, -1, -1):
		if days[i] < today - WINDOW_DAYS:
			break
		if kinds[i] >= FAMILY_FROM or not NoticeSettings.pauses(kinds[i]) or not view.has_point(at[i]):
			continue
		var key := "%d:%d:%d" % [days[i], kinds[i], e.household[i]]
		seen[key] = true
		if newest < 0 and not _pause_seen.has(key):
			newest = i
	_pause_seen = seen
	if newest >= 0:
		var k: int = kinds[newest]
		pause_asked.emit("%s, %s" % [e.names[k] if k < e.names.size() else "Ereignis", _day(int(days[newest]))])

## The window for event i: what the sim knows of it, the households as links.
func _open_window(e: Dictionary, i: int) -> void:
	var kind: int = e.kind[i]
	var day: int = e.day[i]
	var hh: int = e.household[i]
	var other: int = e.other[i]
	var amount: int = e.amount[i]
	var d := {
		"kind": e.names[kind] if kind < e.names.size() else "Ereignis",
		"icon": KIND_ICONS[kind] if kind < KIND_ICONS.size() else "",
		"date": "%s, %s" % [_day(day), SimTables._date(day)],
		"at": e.at[i],
		"people": [{"pid": -1, "household": hh, "label": "Haushalt %d" % hh}],
	}
	match kind:
		HUNGER_DEATH:
			d.title = "Ein Mensch ist verhungert"
			d.text = "In diesem Haushalt ist ein Mensch verhungert: der Haushalt hatte zu lange nicht genug zu essen."
		MOVED:
			d.title = "Ein Haushalt zieht weiter"
			d.text = "Ein Haushalt verlässt seine Gegend und zieht dorthin, wo er sich ein besseres Auskommen erhofft."
			if amount > 0:
				d.figures = [{"label": "Menschen", "value": SimTables._int(amount)}]
		LEFT_MAP:
			d.title = "Ein Haushalt verlässt die Karte"
			d.text = "Ein Haushalt zieht über den Rand der Karte fort und ist aus dem Spiel."
		JOINED:
			d.title = "Ein Haushalt zieht zu Verwandten"
			d.text = "In diesem Haushalt ist niemand mehr im arbeitsfähigen Alter. Er zieht zu Verwandten und lebt fortan bei ihnen."
		ALMS:
			d.title = "Almosen für einen Haushalt in Not"
			d.text = "Ein Haushalt, der nicht genug zu essen hatte, hat Almosen erhalten."
			d.figures = [{"label": "Erhalten", "value": "%s kg Korn" % SimTables._int(amount)}]
		TENT_MOVED:
			d.title = "Ein Zelt zieht um"
			d.text = "Ein Haushalt aus dem Zelt zieht zu einem Markt, wo es mehr Arbeit und Almosen gibt."
		HEIR:
			d.title = "Ein Erbteil wird übergeben"
			d.text = "Ein Sohn hat seinen Anteil am Hof des Vaters erhalten und bewirtschaftet ihn jetzt mit seinem eigenen Haushalt."
			d.people[0].label = "Haushalt %d (Erbe)" % hh
			if other >= 0:
				d.people.append({"pid": -1, "household": other, "label": "Haushalt %d (Vater)" % other})
		TO_TENT:
			d.title = "Ein Haushalt muss ins Zelt"
			d.text = "In diesem Haushalt arbeitet niemand mehr. Er hat sein Zuhause verlassen und lebt jetzt im Zelt am Markt."
		THEFT:
			d.title = "Diebstahl auf einem Hof"
			d.text = "Ein Haushalt aus dem Zelt fand nicht genug zu essen und stahl in der Not Korn aus dem Speicher eines Hofs."
			d.figures = [{"label": "Gestohlen", "value": "%s kg Korn" % SimTables._int(amount)}]
			d.people[0].label = "Haushalt %d (Dieb)" % hh
			if other >= 0:
				d.people.append({"pid": -1, "household": other, "label": "Haushalt %d (bestohlen)" % other})
		FARM_TAKEN:
			d.title = "Ein freier Hof ist wieder bewirtschaftet"
			d.text = "Ein Haushalt ohne eigenes Land hat einen freien Hof übernommen und lebt jetzt von dessen Ernte."
		MANCIANA:
			d.title = "Neuland nach der Lex Manciana"
			d.text = "Ein landloser Haushalt aus dem Zelt rodet freies Land. Nach der Lex Manciana darf er es bebauen; ein Drittel der Ernte geht an den Staat, und wer zwei Jahre nichts sät, verliert das Land wieder."
		FARM_LEFT:
			d.title = "Ein Hof steht leer"
			d.text = "Der Haushalt dieses Hofs ist weggezogen oder ausgestorben. Übernimmt ihn nach zwei Aussaaten niemand, fallen seine Felder an das freie Land zurück."
			d.erase("people") # the household may be gone
	_window = EventWindow.open(get_tree(), d)
	_window_msec = Time.get_ticks_msec()
	_window.fly_to.connect(func(p: Vector2): _fly({"lo": p, "hi": p}))
	_window.person.connect(func(pid: int, household: int): person_chosen.emit(pid, household))

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
	if event is InputEventKey and Keys.pressed(event, "apoleia_events"):
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
	_panel.pin_asked.connect(_pin)
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
