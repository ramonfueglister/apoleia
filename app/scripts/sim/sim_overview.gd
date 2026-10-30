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
const DONUT_R := 62.0
const DONUT_W := 17.0
const OTHER := Color("6d7479") # the rest of a ring
const RING_MAX := 5 # slices before "Andere"

## sim_tables.gd's day format: date(day) "Martius, Jahr 3"
var date: Callable
var _tables := {}
var _grid: GridContainer
var _tiles: HBoxContainer
var _lines := {} # chart key -> {control, series: Array, unit, days}
var _rings := {} # ring key -> {control, names, values, colours, unit, legend}
var _lists := {} # list key -> VBoxContainer
var _bars: Control
## Months shown in the line charts: 12, 120 or 0 for all.
var _span := 0
var _spans: HBoxContainer
var _bar_rows: Array = [] # [label, value]

func _init(date_fn: Callable) -> void:
	date = date_fn
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # its width never widens the window
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	# the figures as EU5's stat strip: cells of two browns in one frame
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.STAT, UiStyle.STAT_FRAME, 3, 0, 0))
	column.add_child(strip)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 0)
	strip.add_child(_tiles)
	# the months the charts show, as EU5's time buttons
	_spans = HBoxContainer.new()
	_spans.add_theme_constant_override("separation", 6)
	_spans.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_spans)
	_spans.add_child(_label("Zeitraum", UiStyle.DIM, UiStyle.SIZE_TEXT))
	for span in [[12, "1 Jahr"], [120, "10 Jahre"], [0, "Alles"]]:
		var b := Button.new()
		b.text = span[1]
		b.toggle_mode = true
		b.button_pressed = span[0] == _span
		b.custom_minimum_size = Vector2(92, 0)
		b.pressed.connect(func():
			_span = span[0]
			for other in _spans.get_children():
				if other is Button:
					other.button_pressed = other == b
			show_tables(_tables))
		_spans.add_child(b)
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
	_line_card("real", "Reallohn: Taglohn in Korn", "kg")
	_ring_card("money", "Geld nach Schicht")
	_line_card("granaries", "Getreide in Speichern", "t")
	_list_card("goods", "Warenpreise")
	_line_card("life", "Geburten und Todesfälle im Monat", "")
	_line_card("work", "Arbeitstage in der Woche", "Tage")
	_line_card("clothes", "Kleidung vom Bedarf", "%")
	_line_card("flows", "Korn ausser Handel im Monat", "t")

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
		_set_line("real", h, [{"key": "real_p50", "name": "Median der Märkte", "colour": Charts.SERIES[4], "lo": "real_p10", "hi": "real_p90",
			"band": "Ärmstes bis reichstes Zehntel der Märkte"},
			{"key": "need_wage", "name": "Nötig, damit die Familie satt wird", "colour": Charts.RED, "dashed": true}])
		_set_line("granaries", h, [{"key": "horrea_t", "name": "Staat", "colour": Charts.SERIES[3]},
			{"key": "lords_t", "name": "Grundherren", "colour": Charts.SERIES[2]},
			{"key": "market_store_t", "name": "Märkte", "colour": Charts.SERIES[0]}])
		_set_line("life", h, [{"key": "births", "name": "Geburten", "colour": Charts.SERIES[1]},
			{"key": "deaths", "name": "Todesfälle", "colour": Charts.SERIES[2]}])
		_set_line("work", h, [{"key": "vacant", "name": "Gesucht, niemand gefunden", "colour": Charts.SERIES[1]},
			{"key": "idle", "name": "Angeboten, niemand eingestellt", "colour": Charts.SERIES[2]}])
		_set_line("clothes", h, [{"key": "clothes", "name": "Alle Haushalte", "colour": Charts.SERIES[3], "scale": 100.0}])
		_set_line("flows", h, [{"key": "spoiled_t", "name": "Verdorben", "colour": Charts.SERIES[2]},
			{"key": "export_t", "name": "Ausfuhr", "colour": Charts.SERIES[3]},
			{"key": "traded_t", "name": "Fernhandel", "colour": Charts.SERIES[1]},
			{"key": "alms_t", "name": "Almosen", "colour": Charts.SERIES[4]}])
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
	var classes: Dictionary = tables.get("classes", {})
	if not classes.is_empty() and classes.data.has("money"):
		var sums := {}
		for r in classes.data.kind.size():
			sums[classes.data.kind[r]] = float(classes.data.money[r])
		_set_ring("money", sums, "Denar")
	var goods: Dictionary = tables.get("goods", {})
	if not goods.is_empty() and goods.data.has("price"):
		var rows := []
		for r in goods.data.good.size():
			rows.append([goods.data.good[r], "%s D je %s" % [Charts.label(float(goods.data.price[r])), goods.data.unit[r]],
				"Lager %s" % Charts.label(float(goods.data.store[r]))])
		_set_list("goods", rows)
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
		["eaten", "Gegessen", " %", 100.0, false], ["real_p50", "Reallohn", " kg", 1.0, false],
		["cash", "Staatskasse", " D", 1.0, false]]
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
			change.text = "%s %.1f %%" % ["▲" if pct > 0.0 else "▼", absf(pct)] # to the month before, as the tooltip says
			change.add_theme_color_override("font_color", UiStyle.TEXT if absf(pct) < 0.05 else (UiStyle.GAIN if good else UiStyle.LOSS))
		else:
			change.text = ""
		var spark: Control = box.get_child(3)
		spark.set_meta("values", vals.slice(maxi(0, n - 24)))
		spark.queue_redraw()
		tile.set_meta("tip", {"id": "tile:" + s[0], "title": s[1], "kind": "Übersicht",
			"rows": [["Diesen Monat", box.get_child(1).text], ["Vormonat", (Charts.label(vals[n - 2]) + s[2]) if n > 1 else "–"],
				["Änderung zum Vormonat", change.text if change.text != "" else "–"]],
			"spark": vals, "spark_title": "Alle Monate seit Beginn", "spark_unit": s[2].strip_edges(),
			"spark_from": date.call(int(d.day[0])) if n > 0 else "", "spark_to": date.call(int(d.day[n - 1])) if n > 0 else "",
			"colour": Charts.SERIES[k % Charts.SERIES.size()]})

func _tile(key: String) -> PanelContainer:
	var tile := PanelContainer.new()
	var cell := UiStyle.board(0, UiStyle.STAT if _tiles.get_child_count() % 2 == 0 else UiStyle.STAT_B)
	cell.set_border_width_all(0)
	cell.content_margin_left = 12
	cell.content_margin_right = 10
	cell.content_margin_top = 6
	cell.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", cell)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	box.add_child(_label("", UiStyle.CONCEPT, UiStyle.SIZE_TEXT))
	var value := _label("…", UiStyle.VALUE, UiStyle.SIZE_HEAD + 4)
	box.add_child(value)
	box.add_child(_label("", UiStyle.TEXT, UiStyle.SIZE_SMALL))
	for l in box.get_children(): # long names clip, the strip keeps the window's width
		(l as Label).clip_text = true
		(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	# a card as EU5's boxes: a dark field in a brown frame, its title on a
	# dark band with a gold rule under it
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.INSET, UiStyle.STAT_FRAME, 2, 0, 0))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(CARD_MIN, 0)
	_grid.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var head := _label(title, UiStyle.TEXT, UiStyle.SIZE_HEAD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var band := UiStyle.box(UiStyle.TIP_CHART_HEAD, UiStyle.GOLD, 0, 0, 5)
	band.border_width_bottom = 1
	head.add_theme_stylebox_override("normal", band)
	column.add_child(head)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	column.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	pad.add_child(box)
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
	var entry := {"control": chart, "series": [], "unit": unit, "days": PackedInt64Array(), "hover": -1, "legend": legend, "hidden": {}}
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
		var scale: float = s.get("scale", 1.0) # shares as per cent
		var scaled := func(key: String) -> PackedFloat64Array:
			var out := PackedFloat64Array()
			for v in d[key]:
				out.append(float(v) * scale)
			return out.slice(_first(out.size()))
		var one := {"name": s.name, "colour": s.colour, "values": scaled.call(s.key),
			"dashed": s.get("dashed", false), "hidden": entry.hidden.has(s.name)}
		if s.has("lo") and d.has(s.lo) and d.has(s.hi):
			one.lo = scaled.call(s.lo)
			one.hi = scaled.call(s.hi)
			one.band = s.get("band", "Spanne der Märkte, höchstens doppelter Median")
		series.append(one)
	entry.series = series
	var days := PackedInt64Array(Array(d.day))
	entry.days = days.slice(_first(days.size()))
	var legend: HFlowContainer = entry.legend
	for c in legend.get_children():
		c.queue_free()
	if series.size() > 1 or series.size() == 1 and series[0].has("lo"):
		for s in series:
			var sw := _swatch(s.colour, s.name)
			if series.size() > 1: # a click hides or shows the line, as EU5's legends
				_toggle(sw, entry, s.name)
			legend.add_child(sw)
		for one in series:
			if one.has("lo"):
				legend.add_child(_swatch(Color(one.colour, 0.35), one.band))
	entry.control.queue_redraw()

## The first row the chosen span shows of n months.
func _first(n: int) -> int:
	return 0 if _span <= 0 else maxi(0, n - _span)

## A legend entry that hides and shows its series on a click.
func _toggle(sw: HBoxContainer, entry: Dictionary, name: String) -> void:
	sw.mouse_filter = Control.MOUSE_FILTER_STOP
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sw.tooltip_text = "Klick: Linie aus- oder einblenden"
	sw.modulate.a = 0.4 if entry.hidden.has(name) else 1.0
	sw.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if entry.hidden.has(name):
				entry.hidden.erase(name)
			else:
				entry.hidden[name] = true
			sw.modulate.a = 0.4 if entry.hidden.has(name) else 1.0
			for one in entry.series:
				if one.name == name:
					one.hidden = entry.hidden.has(name)
			entry.control.queue_redraw())

## The month under the mouse: each series' value, the price's range.
func _line_tip(key: String, title: String) -> Dictionary:
	var entry: Dictionary = _lines[key]
	var m: int = entry.hover
	if m < 0 or entry.series.is_empty():
		return {}
	var unit: String = entry.unit
	var rows := []
	for s in entry.series:
		if m < s.values.size() and not s.hidden:
			rows.append([s.name, Charts.label(s.values[m], unit), s.colour if s.colour == Charts.RED else UiStyle.TEXT])
			if s.has("lo"):
				rows.append(["Billigster Markt", Charts.label(s.lo[m], unit)])
				rows.append(["Teuerster Markt", Charts.label(s.hi[m], unit)])
	if key == "real" and entry.series.size() > 1 and m < entry.series[1].values.size():
		var gap: float = entry.series[0].values[m] - entry.series[1].values[m]
		rows.append(["Median über dem Nötigen" if gap >= 0.0 else "Median fehlt zum Nötigen", Charts.label(absf(gap), unit),
			UiStyle.GAIN if gap >= 0.0 else UiStyle.LOSS])
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
	legend.add_theme_constant_override("separation", 3)
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
		UiStyle.text_at(ring, c + Vector2(-DONUT_R, 2), Charts.label(total), UiStyle.VALUE, UiStyle.SIZE_HEAD + 2, HORIZONTAL_ALIGNMENT_CENTER, DONUT_R * 2.0, UiStyle.bold())
		UiStyle.text_at(ring, c + Vector2(-DONUT_R, 20), entry.unit, UiStyle.KIND, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_CENTER, DONUT_R * 2.0, UiStyle.italic()))
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
	for i in shown.size(): # EU5's list beside a ring: a bar each, a pennant in its colour
		var back := PanelContainer.new()
		var bar := UiStyle.box(UiStyle.ROW if i % 2 == 0 else UiStyle.ROW_DARK, Color.TRANSPARENT, 0, 0, 0)
		bar.content_margin_left = 6
		bar.content_margin_right = 8
		bar.content_margin_top = 3
		bar.content_margin_bottom = 3
		back.add_theme_stylebox_override("panel", bar)
		var line := HBoxContainer.new()
		back.add_child(line)
		line.add_child(_swatch(colours[i], shown[i]))
		var share := _label("%.1f %%" % (values[i] / total * 100.0) if total > 0.0 else "", UiStyle.TEXT, UiStyle.SIZE_TEXT)
		share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		share.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(share)
		legend.add_child(back)
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

## A card of rows as EU5's lists: a name, a value, a note, on bars of two
## shades.
func _list_card(key: String, title: String) -> void:
	var box := _card(title)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	box.add_child(list)
	_lists[key] = list

func _set_list(key: String, rows: Array) -> void:
	var list: VBoxContainer = _lists[key]
	for c in list.get_children():
		c.queue_free()
	for i in rows.size():
		var back := PanelContainer.new()
		var bar := UiStyle.box(UiStyle.ROW if i % 2 == 0 else UiStyle.ROW_DARK, Color.TRANSPARENT, 0, 0, 0)
		bar.content_margin_left = 8
		bar.content_margin_right = 8
		bar.content_margin_top = 4
		bar.content_margin_bottom = 4
		back.add_theme_stylebox_override("panel", bar)
		var line := HBoxContainer.new()
		back.add_child(line)
		var name := _label(rows[i][0], UiStyle.CONCEPT, UiStyle.SIZE_TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		line.add_child(_label(rows[i][1], UiStyle.VALUE, UiStyle.SIZE_TEXT))
		var note := _label(rows[i][2], UiStyle.DIM, UiStyle.SIZE_SMALL)
		note.custom_minimum_size = Vector2(96, 0)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(note)
		list.add_child(back)

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
		_bars.draw_line(Vector2(mid, 0), Vector2(mid, _bars.size.y), Color(UiStyle.GOLD, 0.6), 1.0)
		for k in _bar_rows.size():
			var y := 4.0 + k * 26.0
			var v: float = _bar_rows[k][1]
			var w := absf(v) / top * half
			var colour := UiStyle.GAIN if v >= 0.0 else UiStyle.LOSS
			var rect := Rect2(mid, y + 4.0, w, 14.0) if v >= 0.0 else Rect2(mid - w, y + 4.0, w, 14.0)
			_bars.draw_rect(Rect2(0, y, _bars.size.x, 22.0), UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK)
			_bars.draw_rect(rect, Color(colour, 0.85))
			_bars.draw_rect(rect, UiStyle.EDGE, false, 1.0)
			UiStyle.text_at(_bars, Vector2(6, y + 16.0), _bar_rows[k][0], UiStyle.CONCEPT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, label_w - 8.0, font)
			UiStyle.text_at(_bars, Vector2(_bars.size.x - value_w - 6.0, y + 16.0), ("+" if v > 0.0 else ("−" if v < 0.0 else "")) + Charts.label(absf(v)),
				colour, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, value_w, font))

func _swatch(colour: Color, text: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var flag := Control.new() # EU5's little pennant
	flag.custom_minimum_size = Vector2(10, 15)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag.draw.connect(func():
		var shape := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 15), Vector2(5, 11), Vector2(0, 15)])
		flag.draw_colored_polygon(shape, colour)
		flag.draw_rect(Rect2(0, 0, 10, 3), Color(1, 1, 1, 0.25))
		shape.append(shape[0])
		flag.draw_polyline(shape, UiStyle.EDGE, 1.0, true))
	line.add_child(flag)
	line.add_child(_label(text, UiStyle.TEXT, UiStyle.SIZE_TEXT))
	return line

static func _label(text: String, colour: Color, font_size: int) -> Label:
	return UiStyle.label(text, colour, font_size)
