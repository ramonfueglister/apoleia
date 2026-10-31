extends Control
## The round buttons down the left edge, as Victoria 3's (Ramon, 31.10.2026:
## "ich hätte gerne alles"): under the red seal of the top bar, on a strip of
## leather, in two groups: the statistics at their topics (sim_tables.gd
## open_at: overview, people, grain and markets, money, goods, farms, the
## state), then the notices and the outliner. The button whose window is
## open is lit. It only shows and tells: chosen(key) goes to the game clock
## (sim/game_clock.gd), which opens what the key names.

const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const Keys = preload("res://scripts/ui/keys.gd")
const SIZE_PX := 42.0
const TOP_PX := 96.0 # under the seal of the top bar (ui/top_bar.gd)
const GROUP_GAP := 12.0
## key, icon, name, the action of its key (ui/keys.gd), group
const BUTTONS := [
	["overview", "scroll-unfurled", "Übersicht", "apoleia_tables", 0],
	["people", "person", "Menschen", "", 0],
	["grain_charts", "wheat", "Korn und Märkte", "", 0],
	["money_charts", "two-coins", "Geld", "", 0],
	["goods_charts", "anvil", "Waren", "", 0],
	["farms_charts", "barn", "Höfe", "", 0],
	["state_charts", "greek-temple", "Staat", "", 0],
	["events", "ringing-bell", "Ereignisse", "apoleia_events", 1],
	["outliner", "bookmark", "Im Blick", "apoleia_outliner", 1],
]

signal chosen(key: String)

var _buttons := {} # key -> Medallion
var _column: VBoxContainer

func _init() -> void:
	name = "MainButtons"
	theme = Vic3.theme() # the tooltips
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 5)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	var group := 0
	for b in BUTTONS:
		if b[4] != group:
			group = b[4]
			var gap := Control.new()
			gap.custom_minimum_size.y = GROUP_GAP
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_column.add_child(gap)
		var m := Vic3.Medallion.new(b[1], b[2], SIZE_PX)
		var key: String = b[0]
		m.pressed.connect(func(): chosen.emit(key))
		if b[3] != "": # the key as the settings have it now
			m.mouse_entered.connect(_tip.bind(m, b[2], b[3]))
		_column.add_child(m)
		_buttons[key] = m
	_column.resized.connect(_fit)

func _ready() -> void:
	_fit.call_deferred()

func _fit() -> void:
	_column.position = Vector2(12, 10)
	size = _column.size + Vector2(24, 20)
	position = Vector2(14, TOP_PX)
	queue_redraw()

## The leather strip behind the medallions, rounded at its ends, with a
## line of gold dividing the groups.
func _draw() -> void:
	Vic3.draw_strip(self, Rect2(Vector2.ZERO, size))
	for c in _column.get_children():
		if not c is Vic3.Medallion:
			var y: float = _column.position.y + c.position.y + c.size.y * 0.5
			Vic3.draw_rule(self, Vector2(8, y), Vector2(size.x - 8, y))

func _tip(m: Control, label: String, action: String) -> void:
	var key := Keys.key_of(action)
	m.tooltip_text = label if key == KEY_NONE else "%s  (%s)" % [label, Keys.key_name(key)]

## Lights the buttons of `keys` (their windows are open), the others not.
func light(keys: Array) -> void:
	for key in _buttons:
		var m: Vic3.Medallion = _buttons[key]
		var on: bool = key in keys
		if m.on != on:
			m.on = on
			m.queue_redraw()
