extends Control
## The map modes, as Victoria 3's: a row of medallions on a strip of
## leather at the foot of the screen, the mode shown lit in gold, its name
## at the left. Each mode colours the regions of the markets by one column
## of the markets table (sim_tables.gd, «Karte färben»), whose legend
## then sits above the strip; the landscape shows the map without colour;
## «Handel» greys the map and draws what the dealers carried between the
## markets (sim/people_flows.gd, legend ui/trade_legend.gd). It only shows
## and tells: chosen(column) goes to the game clock (sim/game_clock.gd),
## which colours the map.

const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const NoticeList = preload("res://scripts/ui/notice_list.gd")
const SIZE_PX := 46.0
## room kept at the right for the notices (sim/sim_events.gd sets them 18
## from the edge)
const NOTICES_PX := NoticeList.WIDTH + 18.0 + 16.0
## column of the markets table ("" none), icon, name
const MODES := [
	["", "mountains", "Landschaft"],
	["persons", "family-house", "Menschen"],
	["price", "wheat", "Kornpreis"],
	["share_hungry", "knife-fork", "Hungernd"],
	["tent_persons", "camping-tent", "Im Zelt"],
	["store_kg", "granary", "Korn auf dem Markt"],
	["free_ha", "field", "Freies Land"],
	["money", "two-coins", "Geld der Händler"],
	["gini", "scales", "Arm und Reich"],
	["trade", "amphora", "Handel"], # not a column: what the dealers carried (sim/people_flows.gd)
]

signal chosen(column: String)

var _buttons: Array = []
var _name: Label
var _row: HBoxContainer
var _shown := "-"

func _init() -> void:
	name = "MapModes"
	theme = Vic3.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_name = Vic3.label("", Vic3.TEXT, Vic3.SIZE_TEXT, Vic3.title_font())
	_name.custom_minimum_size.x = 170
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_name)
	for m in MODES:
		var b := Vic3.Medallion.new(m[1], "Karte: %s" % m[2], SIZE_PX)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var column: String = m[0]
		b.pressed.connect(func(): chosen.emit(column))
		_row.add_child(b)
		_buttons.append(b)
	_row.resized.connect(_fit)
	show_mode("")

func _fit() -> void:
	custom_minimum_size = _row.size + Vector2(36, 16)
	size = custom_minimum_size
	var screen := get_viewport_rect().size
	var x := minf((screen.x - size.x) * 0.5, screen.x - NOTICES_PX - size.x) # centred, clear of the notices
	position = Vector2(maxf(x, 12.0), screen.y - size.y - 10.0)
	_row.position = Vector2(18, 8)
	queue_redraw()

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

## The leather strip, rounded at its ends, in a gold rim.
func _draw() -> void:
	Vic3.draw_strip(self, Rect2(Vector2.ZERO, size))

## Lights the mode of `column` ("" the landscape) and names it.
func show_mode(column: String) -> void:
	if column == _shown:
		return
	_shown = column
	var known := false
	for i in MODES.size():
		var b: Vic3.Medallion = _buttons[i]
		b.on = MODES[i][0] == column
		known = known or b.on
		b.queue_redraw()
	_name.text = "Karte: " + (MODES.filter(func(m): return m[0] == column)[0][2] if known else column)
