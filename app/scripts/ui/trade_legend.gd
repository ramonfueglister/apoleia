extends PanelContainer
## The legend of the map mode «Handel» (ui/map_modes.gd, sim/people_flows.gd),
## above the strip of map modes as the markets' legend sits (sim_tables.gd
## _place_legend): a medallion for each good, the one shown lit, and the key
## of the arcs' widths, three arcs as wide as on the map with what they
## carried. good_chosen(good) goes to the game clock, which hands it to the
## flows; show_scale() fills the key once the flows are built.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const PeopleFlows = preload("res://scripts/sim/people_flows.gd")
const GOOD_PX := 30.0
const KEY_SHARES: Array[float] = [1.0, 0.25, 0.0625] # of the largest flow: the arcs of the key

signal good_chosen(good: int)

## The strip of map modes the legend sits on.
var over: Control:
	set(bar):
		over = bar
		bar.item_rect_changed.connect(_place)
		_place()

var _goods := {} # good -> its medallion
var _name: Label
var _key: HBoxContainer
var _good := PeopleFlows.GRAIN

func _init() -> void:
	name = "TradeLegend"
	theme = Vic3.theme()
	visible = false
	var frame := UiStyle.frame()
	frame.set_content_margin_all(8)
	add_theme_stylebox_override("panel", frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var tag := _label("Handel, letzte 28 Tage", UiStyle.NAME, 14)
	row.add_child(tag)
	for g in PeopleFlows.GOODS:
		var b := Vic3.Medallion.new(PeopleFlows.GOOD_ICONS[g], PeopleFlows.GOOD_NAMES[g], GOOD_PX)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(good_chosen.emit.bind(g))
		row.add_child(b)
		_goods[g] = b
	_name = _label("", UiStyle.NAME, 14)
	_name.custom_minimum_size.x = 120
	row.add_child(_name)
	_key = HBoxContainer.new()
	_key.add_theme_constant_override("separation", 6)
	row.add_child(_key)
	row.add_child(_label("Pfeil: wohin es ging", UiStyle.DIM, 13))
	resized.connect(_place)
	_name.text = PeopleFlows.GOOD_NAMES[_good]
	_key.add_child(_label("nichts gehandelt", UiStyle.DIM, 13))

func _ready() -> void:
	get_viewport().size_changed.connect(_place)
	visibility_changed.connect(_place)

static func _label(text: String, colour: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", font_size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## Lights the good the flows show and keys the widths of their arcs by
## what the largest carried (kg of grain, pieces of a craft good), as wide
## as they are on the screen.
func show_scale(flows: Node) -> void:
	var good: int = flows.good
	var largest: float = flows.largest()
	_good = good
	for g in _goods:
		var b: Vic3.Medallion = _goods[g]
		b.on = g == good
		b.queue_redraw()
	_name.text = PeopleFlows.GOOD_NAMES[good]
	for child in _key.get_children():
		child.free()
	if largest <= 0.0:
		_key.add_child(_label("nichts gehandelt", UiStyle.DIM, 13))
	else:
		var colour: Color = PeopleFlows.COLOURS[good]
		for share in KEY_SHARES:
			_key.add_child(Sample.new(maxf(flows.width_px(share), 1.5), flows.casing_px(), colour))
			_key.add_child(_label(_units(largest * share, good), UiStyle.TEXT, 13))
	reset_size.call_deferred() # shrinks to a shorter key

## 120'000 kg as "120 t", pieces as "1'200 Stück".
static func _units(n: float, good: int) -> String:
	if good != PeopleFlows.GRAIN:
		return "%s Stück" % _amount(roundi(n))
	if n >= 10000.0:
		return "%s t" % _amount(roundi(n / 1000.0))
	if n >= 1000.0:
		return "%.1f t" % (n / 1000.0)
	return "%d kg" % roundi(n)

static func _amount(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "'" + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out

func _place() -> void:
	if not is_inside_tree() or over == null:
		return
	var bar := over.get_rect()
	var from := minf(bar.position.x, bar.end.x - size.x) # no further right than the strip
	position = Vector2(maxf(from, 12.0), bar.position.y - size.y - 8.0)

## One arc of the key, straight: a ribbon `w` px wide in its dark casing,
## ending in an arrowhead, as people_flows.gd draws them on the map.
class Sample extends Control:
	const LONG := 34.0
	var _w: float
	var _rim: float
	var _colour: Color

	func _init(w: float, rim: float, colour: Color) -> void:
		_w = w
		_rim = rim
		_colour = colour
		var head := _w * PeopleFlows.ARROW_LONG
		custom_minimum_size = Vector2(LONG + head, maxf(_w * PeopleFlows.ARROW_WIDE + _rim * 2.0, 14.0))
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		var head := _w * PeopleFlows.ARROW_LONG
		var end := size.x - head
		for pass_ in 2:
			var grow := _rim if pass_ == 0 else 0.0
			var c := PeopleFlows.INK if pass_ == 0 else _colour
			draw_rect(Rect2(0.0, y - _w * 0.5 - grow, end, _w + grow * 2.0), c)
			var half := _w * PeopleFlows.ARROW_WIDE * 0.5 + grow
			draw_colored_polygon(PackedVector2Array([Vector2(end - grow, y - half), Vector2(end - grow, y + half), Vector2(size.x, y)]), c)
