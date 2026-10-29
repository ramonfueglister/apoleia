extends CanvasLayer
## A market's window (docs/kit1/REALTIME_GAMEPLAY.md phase 6): a click on a
## market square up close opens it at the right edge, as Cities: Skylines
## opens a building's info. It shows the market's row of the markets table
## (apoleia_sim::grain, the same numbers as the T table), one line per
## column, so every column the economy adds there, the reasons for a price
## included, shows here too. While open it follows the sim once a week.
##
##   click on a market square   open its window
##   Esc or ×                   close it
##
## Clicks while a build tool is out belong to the build menu (added after
## this node, so it sees them first).

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const CLICK_PX := 4.0
const MARKET_MAX_KM := 80.0 # view width up to which a click opens a market (build_menu.gd BUILD_MAX_KM)
const REFRESH_DAYS := 7
const PANEL_PX := 340.0
const LABEL_PX := 170.0

var landscape: Node3D
var people: RefCounted # ApoleiaPeople
var market := -1
var _press_at := Vector2.INF
var _waiting := false
var _asked_day := -1
var _panel: PanelContainer
var _title: Label
var _when: Label
var _rows: GridContainer
var _notes: VBoxContainer

func setup(scene: Node3D, sim: RefCounted) -> void:
	name = "MarketWindow"
	layer = 4
	landscape = scene
	people = sim
	_panel = PanelContainer.new()
	_panel.theme = SimTables._theme()
	_panel.add_theme_stylebox_override("panel", SimTables._box(Color(SimTables.BACKGROUND, 0.94), Color(SimTables.GOLD, 0.6), 1, 4, 12))
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = 64.0 # below the game clock
	_panel.custom_minimum_size = Vector2(PANEL_PX, 0)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = Label.new()
	_title.add_theme_font_override("font", SimTables._serif())
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", SimTables.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Schliessen  (Esc)"
	close.pressed.connect(close_window)
	head.add_child(close)
	_when = Label.new()
	_when.add_theme_color_override("font_color", SimTables.SECONDARY)
	_when.add_theme_font_size_override("font_size", 12)
	box.add_child(_when)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 3)
	box.add_child(_rows)
	_notes = VBoxContainer.new()
	box.add_child(_notes)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _panel.visible:
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
	market = m
	_ask()
	if not _panel.visible:
		_title.text = "…"
		_when.text = ""
		_clear()
	_panel.visible = true

func close_window() -> void:
	market = -1
	_waiting = false
	_panel.visible = false

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
		_title.text = "Kein Markt"
		return
	var data: Dictionary = d.data
	_title.text = "Markt %s" % (data.region[0] if data.has("region") else str(market))
	_when.text = "Stand %d. %s" % [int(d.day) % SimTables.MONTH + 1, SimTables._date(int(d.day))]
	var columns: PackedStringArray = d.columns
	for i in columns.size():
		var key := columns[i]
		if key == "region":
			continue
		var v = data[key][0]
		var label := _label(d.labels[i], SimTables.SECONDARY)
		if v is String:
			var note := _label("%s: %s" % [d.labels[i], v], SimTables.INK)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size = Vector2(PANEL_PX - 24.0, 0)
			_notes.add_child(note)
			label.queue_free()
			continue
		label.custom_minimum_size = Vector2(LABEL_PX, 0)
		_rows.add_child(label)
		var value := _label(_value(float(v), d.units[i]), SimTables.NEGATIVE if float(v) < 0.0 else SimTables.INK)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(value)

static func _label(text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", 14)
	return l

static func _value(v: float, unit: String) -> String:
	if unit == "%":
		return "%d %%" % roundi(v * 100.0)
	var n := SimTables._number(v)
	return n if unit == "" else "%s %s" % [n, unit]
