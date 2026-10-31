extends CanvasLayer
## A market's window (docs/kit1/REALTIME_GAMEPLAY.md phase 6): a click on a
## market square up close opens it at the right edge, as Cities: Skylines
## opens a building's info, in a window (ui/ui_window.gd) that can be
## moved, sized and folded. Three tabs, as the statistics' views:
## "Überblick", this market's figures, why its grain costs what it costs,
## what its numbers say (the Lage, a click on a line opens its chart) and
## who lives there with their money; "Diagramme", its charts over the
## months (grain price, hunger, store and sales, real wage, people, rich
## and poor, each good's price), two to a row (both sim_overview.gd pages);
## and "Alle Zahlen", the market's row of the markets table
## (apoleia_sim::grain, the same numbers as the T table), one line per
## column, so every column the economy adds there, the reasons for a price
## included, shows here too. While open it follows the sim once a week.
##
##   click on a market square   open its window
##   ← in its band              the market shown before
##   → under its title          the camera onto the market
##   right click on its band    its menu: on the map, in the outliner
##   Esc or ×                   close it
##
## In the group "market_window": call_group("market_window", "open", m)
## opens a market from anywhere (the outliner, a right-click menu).
##
## Clicks while a build tool is out belong to the build menu (added after
## this node, so it sees them first).

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const SimOverview = preload("res://scripts/sim/sim_overview.gd")
const UiWindow = preload("res://scripts/ui/ui_window.gd")
const UiTabs = preload("res://scripts/ui/ui_tabs.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const ContextMenu = preload("res://scripts/ui/context_menu.gd")
const CLICK_PX := 4.0
const MARKET_MAX_KM := 80.0 # view width up to which a click opens a market (build_menu.gd BUILD_MAX_KM)
const REFRESH_DAYS := 7
const PANEL_PX := 560.0
const LABEL_PX := 230.0

var landscape: Node3D
var people: RefCounted # ApoleiaPeople
var market := -1
var _press_at := Vector2.INF
var _waiting := false
var _asked_day := -1
var _win # ui_window.gd
var _overview # sim_overview.gd, page "market"
var _charts # sim_overview.gd, page "market_charts"
var _spans: HBoxContainer # the months the charts show, over them
var _numbers: ScrollContainer
var _when: Label
var _rows: GridContainer
var _notes: VBoxContainer
var _shown := {} # the market's row as last shown

func setup(scene: Node3D, sim: RefCounted) -> void:
	name = "MarketWindow"
	add_to_group("market_window")
	layer = 4
	landscape = scene
	people = sim
	# at the right edge, below the game clock; moved and sized as the player likes
	_win = UiWindow.make("market", "Markt", Rect2(-12, 64, PANEL_PX + 24.0, 780), Engine.get_main_loop() as SceneTree)
	_win.visible = false
	_win.closed.connect(func():
		if market >= 0:
			close_window())
	_win.context = func() -> Dictionary:
		if market < 0 or not _shown.has("region"):
			return {}
		var fly := _fly_to.bind(_shown) if _shown.has("lon") else Callable()
		return {"title": "Markt %s" % _shown.region[0], "kind": "Kornmarkt",
			"entries": ContextMenu.entries(get_tree(), "market", market, _shown.region[0], fly, true)}
	var tabs := UiTabs.new()
	for title in ["Überblick", "Diagramme", "Alle Zahlen"]:
		tabs.add_tab(title)
	_win.body.add_child(tabs)
	_overview = SimOverview.new(SimTables._date, "market")
	_overview.go.connect(func(_page: String): tabs.current_tab = 1)
	_win.body.add_child(_overview)
	_spans = SimOverview.span_buttons(func(months: int): _charts.set_span(months))
	_spans.alignment = BoxContainer.ALIGNMENT_END
	_spans.visible = false
	_win.body.add_child(_spans)
	_charts = SimOverview.new(SimTables._date, "market_charts")
	_charts.visible = false
	_win.body.add_child(_charts)
	_numbers = ScrollContainer.new()
	_numbers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_numbers.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_numbers.visible = false
	_win.body.add_child(_numbers)
	tabs.tab_changed.connect(func(i: int):
		_overview.visible = i == 0
		_spans.visible = i == 1
		_charts.visible = i == 1
		_numbers.visible = i == 2)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_numbers.add_child(box)
	_when = UiStyle.label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	box.add_child(_when)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 3)
	box.add_child(_rows)
	_notes = VBoxContainer.new()
	_notes.add_theme_constant_override("separation", 6)
	box.add_child(_notes)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _win.visible:
		close_window()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_at = event.position
		return
	if _press_at.distance_to(event.position) > CLICK_PX or landscape.width > MARKET_MAX_KM:
		return
	var at: Vector2 = landscape._ground_under(event.position)
	var m: int = people.market_at(at.x, at.y)
	if m >= 0:
		open(m)
		get_viewport().set_input_as_handled()

func open(m: int) -> void:
	if _win.visible and market >= 0 and m != market:
		var before := market
		_win.remember(func(): open(before))
	market = m
	_ask()
	if not _win.visible:
		_win.set_title("…")
		_when.text = ""
		_clear()
	_win.open()

## The camera onto the market's region, framed by its extent.
func _fly_to(data: Dictionary) -> void:
	if landscape == null or not "_goal_target" in landscape:
		return
	landscape._goal_target = landscape.lonlat_to_world(float(data.lon[0]), float(data.lat[0]))
	var reach := float(data.extent_km[0]) if data.has("extent_km") else 0.0
	landscape._goal_width = clampf(reach * SimTables.FLY_MARGIN, SimTables.FLY_MIN_KM, MARKET_MAX_KM)

func close_window() -> void:
	market = -1
	_waiting = false
	if _win.visible:
		_win.close()

func _ask() -> void:
	people.ask_market(market)
	_waiting = true
	_asked_day = people.day()

func _process(_delta: float) -> void:
	if market < 0:
		return
	if _waiting:
		var d: Dictionary = people.take_market()
		if not d.is_empty():
			_waiting = false
			if int(d.market) == market:
				_show(d)
	elif people.day() - _asked_day >= REFRESH_DAYS:
		_ask()

func _clear() -> void:
	for c in _rows.get_children() + _notes.get_children():
		c.queue_free()

## One line per shown column: the name, the value with its unit; text
## columns other than the name (reasons) as a sentence below.
func _show(d: Dictionary) -> void:
	_clear()
	if not d.has("data"):
		_shown = {}
		_win.set_title("Kein Markt")
		return
	var data: Dictionary = d.data
	_shown = data
	_win.set_title("Markt %s" % (data.region[0] if data.has("region") else str(market)))
	var persons := int(data.persons[0]) if data.has("persons") else 0
	_win.set_subtitle("Kornmarkt einer Region mit %s Menschen" % SimOverview._num(persons) if data.has("persons") else "Kornmarkt",
		_fly_to.bind(data) if data.has("lon") and data.has("lat") else Callable(), "Auf der Karte zeigen")
	_when.text = "Stand %d. %s" % [int(d.day) % SimTables.MONTH + 1, SimTables._date(int(d.day))]
	_overview.show_market(d)
	_charts.show_market(d)
	var columns: PackedStringArray = d.columns
	for i in columns.size():
		var key := columns[i]
		if key == "region":
			continue
		var v = data[key][0]
		var label := _label(d.labels[i], UiStyle.DIM)
		if v is String:
			var note := _label("%s: %s" % [d.labels[i], v], UiStyle.TEXT)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(PANEL_PX - 60.0, 0)
			_notes.add_child(note)
			label.queue_free()
			continue
		label.custom_minimum_size = Vector2(LABEL_PX, 0)
		_rows.add_child(label)
		var value := _label(_value(float(v), d.units[i]), UiStyle.LOSS if float(v) < 0.0 else UiStyle.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(value)

static func _label(text: String, colour: Color) -> Label:
	return UiStyle.label(text, colour, UiStyle.SIZE_TEXT)

static func _value(v: float, unit: String) -> String:
	if unit == "%":
		return "%d %%" % roundi(v * 100.0)
	var n := SimTables._number(v)
	return n if unit == "" else "%s %s" % [n, unit]
