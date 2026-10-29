extends ScrollContainer
## The statistics' first tab, "Übersicht": the state of the realm at a
## glance, as EU5's economy panel opens. Four figures with their change
## since the month before and a small curve, then cards of charts: the
## grain price as a median in the band of the cheapest and dearest market,
## people by occupation and farms by kind as rings, people, harvest and
## sales, the hungry dead and the treasury over the months, the state's
## money since the start as bars. Every chart has EU5 tooltips: over a
## line the month under the mouse, over a ring its slice.
##
## sim_tables.gd hands it the tables (history, population, farms, state)
## with show_tables(); it only draws them.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const Charts = preload("res://scripts/ui/charts.gd")
const CARD_MIN := 320.0
const CHART_PX := 190.0
const DONUT_R := 74.0
const DONUT_W := 20.0
const OTHER := Color("6d7479") # the rest of a ring
const RING_MAX := 5 # slices before "Andere"

## sim_tables.gd's day format: date(day) "Martius, Jahr 3"
var date: Callable
var _tables := {}
var _grid: GridContainer
var _tiles: HBoxContainer
var _lines := {} # chart key -> {control, series: Array, unit, days}
var _rings := {} # ring key -> {control, names, values, colours, unit, legend}
var _bars: Control
var _bar_rows: Array = [] # [label, value]

func _init(date_fn: Callable) -> void:
	date = date_fn
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 8)
	column.add_child(_tiles)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_grid)
	resized.connect(func(): _grid.columns = maxi(1, int(size.x / (CARD_MIN + 12.0))) if size.x > 0.0 else 2)
	_line_card("price", "Kornpreis: Median und Spanne der Märkte", "D/kg")
	_ring_card("jobs", "Menschen nach Beruf")
	_line_card("persons", "Menschen", "")
	_ring_card("farms", "Höfe nach Art")
	_line_card("harvest", "Ernte und Verkauf im Monat", "t")
	_line_card("hunger", "Hungertote im Monat", "")
	_line_card("cash", "Staatskasse", "D")
	_bar_card("Geld des Staates seit Beginn")

## The tables by kind ("history", "population", "farms", "state"), each
## as take_table() gave it.
func show_tables(tables: Dictionary) -> void:
	_tables = tables
	var h: Dictionary = tables.get("history", {})
	if not h.is_empty():
		var d: Dictionary = h.data
		_set_line("price", h, [{"key": "price_median", "name": "Median", "colour": Charts.SERIES[0], "lo": "price_min", "hi": "price_max"}])
		_set_line("persons", h, [{"key": "persons", "name": "Menschen", "colour": Charts.SERIES[1]}])
		_set_line("harvest", h, [{"key": "harvest_t", "name": "Ernte", "colour": Charts.SERIES[0]},
			{"key": "sold_t", "name": "Verkauft", "colour": Charts.SERIES[1]}])
		_set_line("hunger", h, [{"key": "hunger_deaths", "name": "Hungertote", "colour": Charts.RED}])
		_set_line("cash", h, [{"key": "cash", "name": "Staatskasse", "colour": Charts.SERIES[3]}])
		_fill_tiles(d)
	var pop: Dictionary = tables.get("population", {})
	if not pop.is_empty() and pop.data.has("occupation"):
		var sums := {}
		for r in pop.data.persons.size():
			var job: String = pop.data.occupation[r]
			sums[job] = sums.get(job, 0.0) + float(pop.data.persons[r])
		_set_ring("jobs", sums, "Menschen")
	var farms: Dictionary = tables.get("farms", {})
	if not farms.is_empty():
		var sums := {}
		for key in ["family", "tenant", "estate"]:
			if farms.data.has(key):
				var label: String = farms.labels[Array(farms.columns).find(key)]
				var total := 0.0
				for v in farms.data[key]:
					total += float(v)
				sums[label] = total
		_set_ring("farms", sums, "Höfe")
	var state: Dictionary = tables.get("state", {})
	if not state.is_empty():
		_bar_rows = []
		for item in [["tax", 1.0], ["rent", 1.0], ["wages", -1.0], ["minted", 1.0], ["cash", 1.0]]:
			var i := Array(state.columns).find(item[0])
			if i >= 0:
				_bar_rows.append([state.labels[i], float(state.data[item[0]][0]) * item[1]])
		_bars.custom_minimum_size.y = 26.0 * _bar_rows.size() + 8.0
		_bars.queue_redraw()

# ------------------------------------------------------------------ figures

## Four figures as EU5's stat strip: the name in blue, the value, the
## change since the month before, a small curve.
func _fill_tiles(d: Dictionary) -> void:
	var specs := [["persons", "Menschen", "", 1.0, false], ["price_median", "Kornpreis", " D/kg", 1.0, true],
		["eaten", "Gegessen vom Bedarf", " %", 100.0, false], ["cash", "Staatskasse", " D", 1.0, false]]
	if _tiles.get_child_count() == 0:
		for s in specs:
			_tiles.add_child(_tile(s[0]))
	for k in specs.size():
		var s: Array = specs[k]
		var tile: PanelContainer = _tiles.get_child(k)
		if not d.has(s[0]):
			tile.visible = false
			continue
		var vals := PackedFloat64Array()
		for v in d[s[0]]:
			vals.append(float(v) * s[3])
		var n := vals.size()
		var box: VBoxContainer = tile.get_child(0)
		(box.get_child(0) as Label).text = s[1]
		(box.get_child(1) as Label).text = (Charts.label(vals[n - 1]) + s[2]) if n > 0 else "…"
		var change := box.get_child(2) as Label
		if n > 1 and vals[n - 2] != 0.0:
			var pct := (vals[n - 1] - vals[n - 2]) / absf(vals[n - 2]) * 100.0
			var good := pct < 0.0 if s[4] else pct > 0.0 # a falling price is good
			change.text = "%s %.1f %% zum Vormonat" % ["▲" if pct > 0.0 else "▼", absf(pct)]
			change.add_theme_color_override("font_color", UiStyle.TEXT if absf(pct) < 0.05 else (UiStyle.GAIN if good else UiStyle.LOSS))
		else:
			change.text = ""
		var spark: Control = box.get_child(3)
		spark.set_meta("values", vals.slice(maxi(0, n - 24)))
		spark.queue_redraw()
		tile.set_meta("tip", {"id": "tile:" + s[0], "title": s[1], "kind": "Übersicht",
			"rows": [["Diesen Monat", box.get_child(1).text], ["Vormonat", (Charts.label(vals[n - 2]) + s[2]) if n > 1 else "–"]],
			"spark": vals, "spark_title": "Alle Monate seit Beginn", "spark_unit": s[2].strip_edges(),
			"spark_from": date.call(int(d.day[0])) if n > 0 else "", "spark_to": date.call(int(d.day[n - 1])) if n > 0 else "",
			"colour": Charts.SERIES[k % Charts.SERIES.size()]})

func _tile(key: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UiStyle.inset(8))
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	box.add_child(_label("", UiStyle.CONCEPT, UiStyle.SIZE_SMALL + 1))
	var value := _label("…", UiStyle.TITLE, UiStyle.SIZE_TITLE)
	box.add_child(value)
	box.add_child(_label("", UiStyle.TEXT, UiStyle.SIZE_SMALL))
	var spark := Control.new()
	spark.custom_minimum_size = Vector2(0, 28)
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var colour: Color = Charts.RED if key == "eaten" else Charts.SERIES[_tiles.get_child_count() % Charts.SERIES.size()]
	spark.draw.connect(func():
		Charts.spark(spark, Rect2(Vector2(0, 4), spark.size - Vector2(4, 6)), spark.get_meta("values", PackedFloat64Array()), colour))
	box.add_child(spark)
	Tooltips.attach(tile, func(_at: Vector2) -> Dictionary: return tile.get_meta("tip", {}))
	return tile

# ------------------------------------------------------------------ cards

func _card(title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.inset(8))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(CARD_MIN, 0)
	_grid.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var head := _label(title, UiStyle.TEXT, UiStyle.SIZE_TEXT + 1)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	return box

func _line_card(key: String, title: String, unit: String) -> void:
	var box := _card(title)
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(0, CHART_PX)
	chart.mouse_filter = Control.MOUSE_FILTER_PASS # the wheel still scrolls
	box.add_child(chart)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 14)
	box.add_child(legend)
	var entry := {"control": chart, "series": [], "unit": unit, "days": PackedInt64Array(), "hover": -1, "legend": legend}
	_lines[key] = entry
	chart.draw.connect(func():
		var days: PackedInt64Array = entry.days
		var from: String = date.call(int(days[0])) if days.size() > 0 else ""
		var to: String = date.call(int(days[days.size() - 1])) if days.size() > 0 else ""
		Charts.line_chart(chart, Rect2(Vector2.ZERO, chart.size), entry.series, UiStyle.serif(), unit, from, to, entry.hover))
	chart.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var m := Charts.month_at(Rect2(Vector2.ZERO, chart.size), entry.days.size(), e.position.x)
			if m != entry.hover:
				entry.hover = m
				chart.queue_redraw())
	chart.mouse_exited.connect(func():
		entry.hover = -1
		chart.queue_redraw())
	Tooltips.attach(chart, func(_at: Vector2) -> Dictionary: return _line_tip(key, title))

## A line chart's series from the history: [{key, name, colour, lo?, hi?}].
func _set_line(key: String, h: Dictionary, specs: Array) -> void:
	var entry: Dictionary = _lines[key]
	var d: Dictionary = h.data
	var series := []
	for s in specs:
		if not d.has(s.key):
			continue
		var one := {"name": s.name, "colour": s.colour, "values": PackedFloat64Array(Array(d[s.key]))}
		if s.has("lo") and d.has(s.lo) and d.has(s.hi):
			one.lo = PackedFloat64Array(Array(d[s.lo]))
			one.hi = PackedFloat64Array(Array(d[s.hi]))
		series.append(one)
	entry.series = series
	entry.days = PackedInt64Array(Array(d.day))
	var legend: HFlowContainer = entry.legend
	for c in legend.get_children():
		c.queue_free()
	if series.size() > 1 or series.size() == 1 and series[0].has("lo"):
		for s in series:
			legend.add_child(_swatch(s.colour, s.name))
		if series.size() == 1:
			legend.add_child(_swatch(Color(series[0].colour, 0.35), "Spanne der Märkte, höchstens doppelter Median"))
	entry.control.queue_redraw()

## The month under the mouse: each series' value, the price's range.
func _line_tip(key: String, title: String) -> Dictionary:
	var entry: Dictionary = _lines[key]
	var m: int = entry.hover
	if m < 0 or entry.series.is_empty():
		return {}
	var unit: String = entry.unit
	var rows := []
	for s in entry.series:
		if m < s.values.size():
			rows.append([s.name, Charts.label(s.values[m], unit), s.colour if s.colour == Charts.RED else UiStyle.TEXT])
			if s.has("lo"):
				rows.append(["Billigster Markt", Charts.label(s.lo[m], unit)])
				rows.append(["Teuerster Markt", Charts.label(s.hi[m], unit)])
	if m > 0:
		var before: float = entry.series[0].values[m - 1]
		var now: float = entry.series[0].values[m]
		var diff := now - before
		rows.append(["Zum Vormonat", ("+" if diff > 0.0 else ("−" if diff < 0.0 else "±")) + Charts.label(absf(diff), unit)])
	return {"id": "line:%s:%d" % [key, m], "title": title, "kind": date.call(int(entry.days[m])), "rows": rows}

func _ring_card(key: String, title: String) -> void:
	var box := _card(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var ring := Control.new()
	ring.custom_minimum_size = Vector2(DONUT_R * 2.0 + 8.0, DONUT_R * 2.0 + 8.0)
	ring.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(ring)
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 2)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(legend)
	var entry := {"control": ring, "names": PackedStringArray(), "values": PackedFloat64Array(), "colours": [],
		"unit": "", "legend": legend, "hover": -1}
	_rings[key] = entry
	ring.draw.connect(func():
		var c := ring.size * 0.5
		Charts.donut(ring, c, DONUT_R, DONUT_W, entry.values, entry.colours, entry.hover)
		var total := 0.0
		for v in entry.values:
			total += v
		var font := UiStyle.serif()
		ring.draw_string(font, c + Vector2(-DONUT_R, 2), Charts.label(total), HORIZONTAL_ALIGNMENT_CENTER, DONUT_R * 2.0, UiStyle.SIZE_HEAD, UiStyle.TITLE)
		ring.draw_string(font, c + Vector2(-DONUT_R, 20), entry.unit, HORIZONTAL_ALIGNMENT_CENTER, DONUT_R * 2.0, UiStyle.SIZE_SMALL, UiStyle.DIM))
	ring.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var i := Charts.slice_at(ring.size * 0.5, DONUT_R, DONUT_W, entry.values, e.position)
			if i != entry.hover:
				entry.hover = i
				ring.queue_redraw())
	ring.mouse_exited.connect(func():
		entry.hover = -1
		ring.queue_redraw())
	Tooltips.attach(ring, func(_at: Vector2) -> Dictionary: return _ring_tip(key, title))

## A ring's slices, largest first, the smallest folded into "Andere".
func _set_ring(key: String, sums: Dictionary, unit: String) -> void:
	var entry: Dictionary = _rings[key]
	var names := sums.keys()
	names.sort_custom(func(a, b): return sums[a] > sums[b])
	var shown := PackedStringArray()
	var values := PackedFloat64Array()
	var colours := []
	var rest := 0.0
	for i in names.size():
		if i < RING_MAX:
			shown.append(names[i])
			values.append(sums[names[i]])
			colours.append(Charts.SERIES[i])
		else:
			rest += sums[names[i]]
	if rest > 0.0:
		shown.append("Andere")
		values.append(rest)
		colours.append(OTHER)
	entry.names = shown
	entry.values = values
	entry.colours = colours
	entry.unit = unit
	var total := 0.0
	for v in values:
		total += v
	var legend: VBoxContainer = entry.legend
	for c in legend.get_children():
		c.queue_free()
	for i in shown.size():
		var line := HBoxContainer.new()
		line.add_child(_swatch(colours[i], shown[i]))
		var share := _label("%.1f %%" % (values[i] / total * 100.0) if total > 0.0 else "", UiStyle.TEXT, UiStyle.SIZE_TEXT)
		share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		share.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(share)
		legend.add_child(line)
	entry.control.queue_redraw()

func _ring_tip(key: String, title: String) -> Dictionary:
	var entry: Dictionary = _rings[key]
	var i: int = entry.hover
	if i < 0 or i >= entry.names.size():
		return {}
	var total := 0.0
	for v in entry.values:
		total += v
	return {"id": "ring:%s:%d" % [key, i], "title": entry.names[i], "kind": title,
		"rows": [[entry.unit, Charts.label(entry.values[i])], ["Anteil", "%.1f %%" % (entry.values[i] / total * 100.0)]]}

func _bar_card(title: String) -> void:
	var box := _card(title)
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(0, 140)
	box.add_child(_bars)
	_bars.draw.connect(func():
		var font := UiStyle.serif()
		var top := 1.0
		for r in _bar_rows:
			top = maxf(top, absf(r[1]))
		var label_w := 150.0
		var value_w := 80.0
		var mid := label_w + (_bars.size.x - label_w - value_w) * 0.5
		var half := (_bars.size.x - label_w - value_w) * 0.5 - 4.0
		_bars.draw_line(Vector2(mid, 0), Vector2(mid, _bars.size.y), Color(UiStyle.DIM, 0.6), 1.0)
		for k in _bar_rows.size():
			var y := 4.0 + k * 26.0
			var v: float = _bar_rows[k][1]
			var w := absf(v) / top * half
			var colour := UiStyle.GAIN if v >= 0.0 else UiStyle.LOSS
			var rect := Rect2(mid, y + 4.0, w, 14.0) if v >= 0.0 else Rect2(mid - w, y + 4.0, w, 14.0)
			_bars.draw_rect(rect, Color(colour, 0.85))
			_bars.draw_string(font, Vector2(0, y + 16.0), _bar_rows[k][0], HORIZONTAL_ALIGNMENT_LEFT, label_w - 8.0, UiStyle.SIZE_TEXT, UiStyle.TEXT)
			_bars.draw_string(font, Vector2(_bars.size.x - value_w, y + 16.0), ("+" if v > 0.0 else ("−" if v < 0.0 else "")) + Charts.label(absf(v)),
				HORIZONTAL_ALIGNMENT_RIGHT, value_w, UiStyle.SIZE_TEXT, colour))

func _swatch(colour: Color, text: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var dot := ColorRect.new()
	dot.color = colour
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(dot)
	line.add_child(_label(text, UiStyle.TEXT, UiStyle.SIZE_TEXT))
	return line

static func _label(text: String, colour: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
