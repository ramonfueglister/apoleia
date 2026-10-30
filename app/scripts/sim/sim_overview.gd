extends ScrollContainer
## The statistics' first tab, "Übersicht": the state of the realm at a
## glance, as EU5's economy panel opens. Five figures with their change
## since the month before and a small curve, the months the charts show,
## then sections of cards: people, food and grain, work and money, goods,
## the state. Each card opens with what its numbers say (Knaflic: the
## finding, not only the topic), computed from them; its title's tooltip
## says what it shows. The line charts share one month under the mouse,
## and mark what happened (built, famine, price shocks). Every line, ring
## slice, bar and good has an EU5 tooltip.
##
## sim_tables.gd hands it the tables (history, population, farms, state,
## classes, goods) with show_tables(); it only draws them.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const Charts = preload("res://scripts/ui/charts.gd")
const CARD_MIN := 320.0
const CHART_PX := 170.0
const DONUT_R := 58.0
const DONUT_W := 16.0
const OTHER := Color("6d7479") # the rest of a ring
const RING_MAX := 5 # slices before "Andere"
const BAR_ROW := 26.0
## The goods table's rows in apoleia_sim::grain::GOOD_KEYS order; the
## history has each one's price as good_<key>.
const GOOD_KEYS: Array[String] = ["wool", "iron", "cloth", "tools", "pottery", "pork"]
## The classes in the order of the history's fed_<key> (grain/tables.rs).
const FED_KEYS: Array[String] = ["court", "tent", "wage", "trader", "elite"]
const FED_NAMES: Array[String] = ["Hofleute", "Im Zelt", "Lohnarbeit", "Händler", "Oberschicht"]
## A class keeps its colour in every chart (the ring of money, what it ate):
## the series colours in this order pass the colour-blind checks on the board.
const FED_COLOURS: Array[Color] = [Color("b8893a"), Color("1f9cc4"), Color("cf5f44"), Color("8f6fd0"), Color("6f9a3a")]
const TREND := Color("a09889") # a figure's small curve, its current value in gold
## What the state's bars are, for their tooltips.
const BAR_ABOUT := {
	"tax": "Steuern in Denar, die der Staat seit Beginn eingenommen hat.",
	"rent": "Pacht in Denar, die Höfe auf Staatsland seit Beginn gezahlt haben.",
	"wages": "Löhne, die der Staat seit Beginn seinen Dienern gezahlt hat: Soldaten, Beamten, Bauarbeitern.",
	"minted": "Denare, die der Staat seit Beginn neu geprägt hat.",
	"cash": "Was heute in der Staatskasse liegt.",
}

## sim_tables.gd's day format: date(day) "Martius, Jahr 3"
var date: Callable
var _tables := {}
var _column: VBoxContainer
var _grids: Array[GridContainer] = []
var _grid: GridContainer # the section the next card goes into
var _tiles: HBoxContainer
var _lines := {} # chart key -> {control, series: Array, unit, days, hover, legend, hidden}
var _rings := {} # ring key -> {control, names, values, colours, unit, legend, title, hover}
var _goods: GridContainer
var _bars: Control
var _bar_rows: Array = [] # [label, value, key]
var _findings := {} # card key -> the label with what its numbers say
var _events := {} # day -> what happened that month (history), see _find_events
## How the classes are named as a sentence's subject, and whether as many.
const FED_SUBJECTS: Array[String] = ["Die Hofleute", "Die Menschen im Zelt", "Die Lohnarbeiter", "Die Händler", "Die Oberschicht"]
## Months shown in the line charts: 12, 120 or 0 for all.
var _span := 0
var _spans: HBoxContainer

func _init(date_fn: Callable) -> void:
	date = date_fn
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # its width never widens the window
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 10)
	add_child(_column)
	# the figures as EU5's stat strip: cells of two browns in one frame
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.STAT, UiStyle.STAT_FRAME, 3, 0, 0))
	_column.add_child(strip)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 0)
	strip.add_child(_tiles)
	# the months the charts show, as EU5's time buttons
	_spans = HBoxContainer.new()
	_spans.add_theme_constant_override("separation", 6)
	_spans.alignment = BoxContainer.ALIGNMENT_END
	_column.add_child(_spans)
	var note := _label("Änderungen zum Vormonat", UiStyle.DIM, UiStyle.SIZE_SMALL)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spans.add_child(note)
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
	resized.connect(func():
		for g in _grids:
			g.columns = maxi(1, int(size.x / (CARD_MIN + 12.0))) if size.x > 0.0 else 2
		if _goods != null:
			_goods.columns = 3 if size.x > 700.0 else 2)
	_section("Menschen")
	_line_card("persons", "Menschen", "", "Alle Menschen auf der Karte, jeder einzeln simuliert.")
	_ring_card("jobs", "Menschen nach Beruf", "Die Menschen nach dem Beruf ihres Haushalts.")
	_line_card("life", "Geburten und Todesfälle", "", "Geburten und Todesfälle im Monat. Die ersten Kinder kommen erst nach etwa neun Monaten zur Welt.")
	_line_card("hunger", "Hungertote", "", "Menschen, die im Monat an Hunger sterben.")
	_section("Essen und Korn")
	_line_card("price", "Kornpreis", "D/kg", "Jeder Markt hat seinen eigenen Kornpreis. Die Linie ist der Median der Märkte, das Band reicht vom billigsten zum teuersten Markt, höchstens bis zum doppelten Median, damit ein teurer Markt wie Rom die Linie nicht flach drückt.")
	_line_card("fed", "Gegessen nach Schicht", "%", "Wie viel ihres Kornbedarfs jede Schicht im Monat gegessen hat. 100 % heisst satt.")
	_line_card("harvest", "Ernte und Verkauf", "t", "Korn, das die Höfe im Monat ernten, und Korn, das die Märkte im Monat verkaufen.")
	_line_card("granaries", "Getreide in Speichern", "t", "Korn in den Speichern des Staates (Steuerkorn), der Grundherren (Pachtkorn) und der Händler auf den Märkten.")
	_line_card("flows", "Korn ausser Handel", "t", "Korn im Monat, das verdirbt, über den Kartenrand verkauft wird, zwischen fernen Märkten gehandelt oder als Almosen verteilt wird.")
	_line_card("clothes", "Kleidung vom Bedarf", "%", "Kleidung, die die Haushalte besitzen, gemessen an dem, was sie brauchen.")
	_section("Arbeit und Geld")
	_line_card("real", "Reallohn", "kg", "Der Taglohn eines Marktes in Korn zu dessen Preis: so viel kann ein Tag Arbeit kaufen. Gestrichelt: so viel muss ein Lohnarbeiter je Arbeitstag verdienen, damit sein Teil der Familie satt wird (Bedarf der Familie durch ihre Erwachsenen und 290 Arbeitstage im Jahr, nach Columella).")
	_line_card("work", "Arbeitstage in der Woche", "Tage", "Arbeitstage der letzten Woche, die jemand gesucht und niemanden gefunden hat, und die jemand angeboten hat, ohne eingestellt zu werden.")
	_ring_card("money", "Geld nach Schicht", "Alles Geld der Haushalte nach Schicht, bei Bauern mit dem Geld ihres Hofs.")
	_ring_card("farms", "Höfe nach Art", "Familienhof: die Familie bebaut ihr eigenes Land. Pachthof: sie bebaut gepachtetes Land. Gut: ein Grundherr lässt sein Land bebauen.")
	_section("Waren")
	_goods_card()
	_section("Staat")
	_line_card("cash", "Staatskasse", "D", "Denar in der Staatskasse am Ende jedes Monats.")
	_bar_card("Geld des Staates seit Beginn", "Was der Staat seit Beginn eingenommen und ausgegeben hat, und was heute in der Kasse liegt.")

## The tables by kind ("history", "population", "farms", "state",
## "classes", "goods"), each as take_table() gave it.
func show_tables(tables: Dictionary) -> void:
	_tables = tables
	var h: Dictionary = tables.get("history", {})
	if not h.is_empty():
		var d: Dictionary = h.data
		_events = _find_events(d)
		_set_line("price", h, [{"key": "price_median", "name": "Median", "colour": Charts.SERIES[0], "lo": "price_min", "hi": "price_max",
			"band": "Billigster bis teuerster Markt"}])
		_set_line("persons", h, [{"key": "persons", "name": "Menschen", "colour": Charts.SERIES[1]}])
		_set_line("harvest", h, [{"key": "harvest_t", "name": "Ernte", "colour": Charts.SERIES[0]},
			{"key": "sold_t", "name": "Verkauft", "colour": Charts.SERIES[1]}])
		_set_line("hunger", h, [{"key": "hunger_deaths", "name": "Hungertote", "colour": Charts.RED}])
		_set_line("cash", h, [{"key": "cash", "name": "Staatskasse", "colour": Charts.SERIES[3]}])
		_set_line("real", h, [{"key": "real_p50", "name": "Median der Märkte", "colour": Charts.SERIES[4], "lo": "real_p10", "hi": "real_p90",
			"band": "Ärmstes bis reichstes Zehntel"},
			{"key": "need_wage", "name": "Nötig zum Sattwerden", "colour": Charts.RED, "dashed": true}])
		var fed := []
		for k in FED_KEYS.size():
			fed.append({"key": "fed_" + FED_KEYS[k], "name": FED_NAMES[k], "colour": FED_COLOURS[k], "scale": 100.0, "mute_above": 99.0})
		_set_line("fed", h, fed)
		_set_line("granaries", h, [{"key": "horrea_t", "name": "Staat", "colour": Charts.SERIES[3]},
			{"key": "lords_t", "name": "Grundherren", "colour": Charts.SERIES[2]},
			{"key": "market_store_t", "name": "Märkte", "colour": Charts.SERIES[0]}])
		_set_line("life", h, [{"key": "births", "name": "Geburten", "colour": Charts.SERIES[1]},
			{"key": "deaths", "name": "Todesfälle", "colour": Charts.SERIES[2]}])
		_set_line("work", h, [{"key": "vacant", "name": "Gesucht", "colour": Charts.SERIES[1]},
			{"key": "idle", "name": "Liegen geblieben", "colour": Charts.SERIES[2]}])
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
		var fixed := {}
		for k in FED_NAMES.size():
			fixed[FED_NAMES[k]] = FED_COLOURS[k]
		_set_ring("money", sums, "Denar", fixed)
	var goods: Dictionary = tables.get("goods", {})
	if not goods.is_empty() and goods.data.has("price"):
		_set_goods(goods, h.get("data", {}))
	var state: Dictionary = tables.get("state", {})
	if not state.is_empty():
		_bar_rows = []
		for item in [["tax", 1.0], ["rent", 1.0], ["wages", -1.0], ["minted", 1.0], ["cash", 1.0]]:
			var i := Array(state.columns).find(item[0])
			if i >= 0:
				_bar_rows.append([state.labels[i], float(state.data[item[0]][0]) * item[1], item[0]])
		_bars.custom_minimum_size.y = BAR_ROW * _bar_rows.size() + 8.0
		_bars.queue_redraw()
	_find_all(h.get("data", {}))

# ------------------------------------------------------------------ figures

## The figures as EU5's stat strip: the name in blue, the value, the
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
		var moved := _change(vals, n - 2, s[4])
		var change := box.get_child(2) as Label
		change.text = moved[0]
		change.add_theme_color_override("font_color", moved[1])
		var spark: Control = box.get_child(3)
		spark.set_meta("values", vals.slice(maxi(0, n - 24)))
		spark.queue_redraw()
		tile.set_meta("tip", {"id": "tile:" + s[0], "title": s[1], "kind": "Übersicht",
			"rows": [["Diesen Monat", box.get_child(1).text], ["Vormonat", (Charts.label(vals[n - 2]) + s[2]) if n > 1 else "–"],
				["Vor einem Jahr", (Charts.label(vals[n - 13]) + s[2]) if n > 12 else "–"]],
			"spark": vals, "spark_title": "Alle Monate seit Beginn", "spark_unit": s[2].strip_edges(),
			"spark_from": date.call(int(d.day[0])) if n > 0 else "", "spark_to": date.call(int(d.day[n - 1])) if n > 0 else "",
			"colour": Charts.SERIES[0]})

## "▲ 3.4 %" from month `before` to the last, and its colour: a gain is
## green, unless `falling_good` (a price).
static func _change(vals: PackedFloat64Array, before: int, falling_good: bool) -> Array:
	var n := vals.size()
	if before < 0 or before >= n - 1 or vals[before] == 0.0:
		return ["", UiStyle.TEXT]
	var pct := (vals[n - 1] - vals[before]) / absf(vals[before]) * 100.0
	if absf(pct) < 0.05:
		return ["± 0 %", UiStyle.DIM]
	var good := pct < 0.0 if falling_good else pct > 0.0
	return ["%s %.1f %%" % ["▲" if pct > 0.0 else "▼", absf(pct)], UiStyle.GAIN if good else UiStyle.LOSS]

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
	box.add_child(_label("…", UiStyle.VALUE, UiStyle.SIZE_HEAD + 4))
	box.add_child(_label("", UiStyle.TEXT, UiStyle.SIZE_SMALL))
	for l in box.get_children(): # long names clip, the strip keeps the window's width
		(l as Label).clip_text = true
		(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var spark := Control.new()
	spark.custom_minimum_size = Vector2(0, 28)
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.draw.connect(func(): # one quiet trend for all, as the figures' colours mean nothing
		Charts.spark(spark, Rect2(Vector2(0, 4), spark.size - Vector2(6, 8)), spark.get_meta("values", PackedFloat64Array()), TREND,
			PackedFloat64Array(), PackedFloat64Array(), NAN, NAN, UiStyle.GOLD_LIT))
	box.add_child(spark)
	Tooltips.attach(tile, func(_at: Vector2) -> Dictionary: return tile.get_meta("tip", {}))
	return tile

# ------------------------------------------------------------------ sections and cards

## A heading as EU5 sets one over a group: the name in gold between two
## gold rules ending in a small diamond. The cards after it go in its grid.
func _section(title: String) -> void:
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 30)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.draw.connect(func():
		var f := UiStyle.bold()
		var w := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_HEAD).x
		var mid := head.size.x * 0.5
		var y := head.size.y * 0.5 + 1.0
		UiStyle.text_at(head, Vector2(0, y + UiStyle.SIZE_HEAD * 0.35), title, UiStyle.GOLD_LIT, UiStyle.SIZE_HEAD, HORIZONTAL_ALIGNMENT_CENTER, head.size.x, f)
		for side: float in [-1.0, 1.0]:
			var inner := mid + side * (w * 0.5 + 14.0)
			var outer := mid + side * (head.size.x * 0.5 - 4.0)
			head.draw_line(Vector2(inner, y + 1.0), Vector2(outer, y + 1.0), UiStyle.EDGE, 1.0)
			head.draw_line(Vector2(inner, y), Vector2(outer, y), Color(UiStyle.GOLD, 0.7), 1.0)
			var diamond := PackedVector2Array([Vector2(inner, y - 4.0), Vector2(inner + 4.0, y), Vector2(inner, y + 4.0), Vector2(inner - 4.0, y)])
			head.draw_colored_polygon(diamond, UiStyle.GOLD))
	_column.add_child(head)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(_grid)
	_grids.append(_grid)

## A card as EU5's boxes: a dark field in a brown frame, its title on a
## dark band with a gold rule under it. The title's tooltip says what the
## card shows (`about`).
func _card(key: String, title: String, about: String) -> VBoxContainer:
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
	head.clip_text = true
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var band := UiStyle.box(UiStyle.TIP_CHART_HEAD, UiStyle.GOLD, 0, 0, 4)
	band.border_width_bottom = 1
	head.add_theme_stylebox_override("normal", band)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	Tooltips.attach(head, func(_at: Vector2) -> Dictionary: return {"id": "card:" + title, "title": title, "kind": "Diagramm", "text": about})
	column.add_child(head)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	column.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	pad.add_child(box)
	var finding := _label("", UiStyle.TEXT, UiStyle.SIZE_SMALL + 1)
	finding.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	finding.custom_minimum_size = Vector2(CARD_MIN - 40.0, 0)
	finding.visible = false
	box.add_child(finding)
	_findings[key] = finding
	return box

func _line_card(key: String, title: String, unit: String, about: String) -> void:
	var box := _card(key, title, about)
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(0, CHART_PX)
	chart.mouse_filter = Control.MOUSE_FILTER_PASS # the wheel still scrolls
	box.add_child(chart)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 12)
	legend.add_theme_constant_override("v_separation", 0)
	box.add_child(legend)
	var entry := {"control": chart, "series": [], "unit": unit, "days": PackedInt64Array(), "hover": -1, "legend": legend, "hidden": {},
		"marks": PackedInt32Array()}
	_lines[key] = entry
	chart.draw.connect(func():
		var days: PackedInt64Array = entry.days
		var from: String = date.call(int(days[0])) if days.size() > 0 else ""
		var to: String = date.call(int(days[days.size() - 1])) if days.size() > 0 else ""
		Charts.line_chart(chart, Rect2(Vector2.ZERO, chart.size), entry.series, UiStyle.serif(), unit, from, to, entry.hover, entry.marks))
	chart.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var m: int = Charts.month_at(Rect2(Vector2.ZERO, chart.size), entry.days.size(), e.position.x)
			if m != entry.hover:
				_hover_all(m))
	chart.mouse_exited.connect(func(): _hover_all(-1))
	Tooltips.attach(chart, func(_at: Vector2) -> Dictionary: return _line_tip(key, title))

## A line chart's series from the history: [{key, name, colour, lo?, hi?,
## band?, dashed?, scale?}].
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
		if s.has("mute_above"): # emphasis: only the lines that tell the story keep their colour
			var low := INF
			for v in one.values:
				low = minf(low, v)
			one.muted = low >= s.mute_above
		if s.has("lo") and d.has(s.lo) and d.has(s.hi):
			one.lo = scaled.call(s.lo)
			one.hi = scaled.call(s.hi)
			one.band = s.get("band", "Spanne")
		series.append(one)
	entry.series = series
	var days := PackedInt64Array(Array(d.day))
	entry.days = days.slice(_first(days.size()))
	var marks := PackedInt32Array()
	for i in entry.days.size():
		if _events.has(int(entry.days[i])):
			marks.append(i)
	entry.marks = marks
	var legend: HFlowContainer = entry.legend
	for c in legend.get_children():
		c.queue_free()
	if series.size() > 1 or series.size() == 1 and series[0].has("lo"):
		for s in series:
			var sw := _swatch(Charts.MUTED if s.get("muted", false) else s.colour, s.name)
			if series.size() > 1: # a click hides or shows the line, as EU5's legends
				_toggle(sw, entry, s.name)
			legend.add_child(sw)
		for one in series:
			if one.has("lo"):
				legend.add_child(_swatch(Color(one.colour, 0.35), one.band))
	entry.control.queue_redraw()

## One month under the mouse for all line charts, as linked views: the
## same month stands out in every chart at once.
func _hover_all(m: int) -> void:
	for key in _lines:
		var entry: Dictionary = _lines[key]
		var want := m if m < entry.days.size() else -1
		if entry.hover != want:
			entry.hover = want
			entry.control.queue_redraw()

## The first row the chosen span shows of n months.
func _first(n: int) -> int:
	return 0 if _span <= 0 else maxi(0, n - _span)

## A legend entry that hides and shows its series on a click.
func _toggle(sw: HBoxContainer, entry: Dictionary, name: String) -> void:
	sw.mouse_filter = Control.MOUSE_FILTER_STOP
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sw.modulate.a = 0.4 if entry.hidden.has(name) else 1.0
	Tooltips.attach(sw, func(_at: Vector2) -> Dictionary: return {"id": "legend:" + name, "title": name,
		"kind": "Linie", "hints": [["Klick", "ausblenden" if not entry.hidden.has(name) else "einblenden"]]})
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

## The month under the mouse: each series' value, the band's ends.
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
				rows.append(["  Unten im Band", Charts.label(s.lo[m], unit)])
				rows.append(["  Oben im Band", Charts.label(s.hi[m], unit)])
	if key == "real" and entry.series.size() > 1 and m < entry.series[1].values.size():
		var gap: float = entry.series[0].values[m] - entry.series[1].values[m]
		rows.append(["Median über dem Nötigen" if gap >= 0.0 else "Median fehlt zum Nötigen", Charts.label(absf(gap), unit),
			UiStyle.GAIN if gap >= 0.0 else UiStyle.LOSS])
	if m > 0:
		var before: float = entry.series[0].values[m - 1]
		var now: float = entry.series[0].values[m]
		var diff := now - before
		rows.append(["Zum Vormonat", ("+" if diff > 0.0 else ("−" if diff < 0.0 else "±")) + Charts.label(absf(diff), unit)])
	var tip := {"id": "line:%s:%d" % [key, m], "title": title, "kind": date.call(int(entry.days[m])), "rows": rows}
	var happened: Array = _events.get(int(entry.days[m]), [])
	if not happened.is_empty():
		tip.text = "[n]In diesem Monat:[/n] " + "; ".join(happened) + "."
	return tip

func _ring_card(key: String, title: String, about: String) -> void:
	var box := _card(key, title, about)
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
		"unit": "", "legend": legend, "hover": -1, "title": title}
	_rings[key] = entry
	ring.draw.connect(func():
		var c := ring.size * 0.5
		Charts.donut(ring, c, DONUT_R, DONUT_W, entry.values, entry.colours, entry.hover)
		var total := 0.0
		for v in entry.values:
			total += v
		UiStyle.text_at(ring, c + Vector2(-DONUT_R, 2), Charts.label(total), UiStyle.VALUE, UiStyle.SIZE_HEAD, HORIZONTAL_ALIGNMENT_CENTER, DONUT_R * 2.0, UiStyle.bold())
		UiStyle.text_at(ring, c + Vector2(-DONUT_R, 19), entry.unit, UiStyle.KIND, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_CENTER, DONUT_R * 2.0, UiStyle.italic()))
	ring.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var i := Charts.slice_at(ring.size * 0.5, DONUT_R, DONUT_W, entry.values, e.position)
			if i != entry.hover:
				entry.hover = i
				ring.queue_redraw())
	ring.mouse_exited.connect(func():
		entry.hover = -1
		ring.queue_redraw())
	Tooltips.attach(ring, func(_at: Vector2) -> Dictionary: return _ring_tip(key, entry.hover))

## A ring's slices, largest first, the smallest folded into "Andere". A
## slice's colour follows what it is, not its rank (`fixed` name -> colour,
## else the slot it got when it first showed), so a reordering repaints
## nothing.
func _set_ring(key: String, sums: Dictionary, unit: String, fixed := {}) -> void:
	var entry: Dictionary = _rings[key]
	var slots: Dictionary = entry.get_or_add("slots", {})
	var names := sums.keys()
	names.sort_custom(func(a, b): return sums[a] > sums[b])
	var shown := PackedStringArray()
	var values := PackedFloat64Array()
	var colours := []
	var rest := 0.0
	var top: Array = names.slice(0, RING_MAX)
	for name in slots.keys(): # a name out of the top frees its slot
		if not name in top:
			slots.erase(name)
	for i in names.size():
		if i < RING_MAX:
			if not slots.has(names[i]):
				var free := 0
				while free in slots.values():
					free += 1
				slots[names[i]] = free
			shown.append(names[i])
			values.append(sums[names[i]])
			colours.append(fixed.get(names[i], Charts.SERIES[slots[names[i]] % Charts.SERIES.size()]))
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
		bar.content_margin_top = 2
		bar.content_margin_bottom = 2
		back.add_theme_stylebox_override("panel", bar)
		back.mouse_filter = Control.MOUSE_FILTER_PASS
		Tooltips.attach(back, func(_at: Vector2) -> Dictionary: return _ring_tip(key, i))
		back.mouse_entered.connect(func():
			entry.hover = i
			entry.control.queue_redraw())
		back.mouse_exited.connect(func():
			entry.hover = -1
			entry.control.queue_redraw())
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(line)
		line.add_child(_swatch(colours[i], shown[i]))
		var share := _label("%.1f %%" % (values[i] / total * 100.0) if total > 0.0 else "", UiStyle.TEXT, UiStyle.SIZE_SMALL + 1)
		share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		share.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(share)
		legend.add_child(back)
	entry.control.queue_redraw()

func _ring_tip(key: String, i: int) -> Dictionary:
	var entry: Dictionary = _rings[key]
	if i < 0 or i >= entry.names.size():
		return {}
	var total := 0.0
	for v in entry.values:
		total += v
	return {"id": "ring:%s:%d" % [key, i], "title": entry.names[i], "kind": entry.title,
		"rows": [[entry.unit, Charts.label(entry.values[i])], ["Anteil", "%.1f %%" % (entry.values[i] / total * 100.0)]]}

# ------------------------------------------------------------------ goods

## The goods as small charts side by side, as EU5's market goods: the
## name, the median price and its change, the price over the chosen months.
## Over a good, EU5's tooltip with its price since the start.
func _goods_card() -> void:
	var box := _card("goods", "Warenpreise", "Der Preis jeder Ware ist der Median der Märkte, gewichtet nach ihren Menschen. Darunter sein Verlauf im gewählten Zeitraum.")
	_goods = GridContainer.new()
	_goods.columns = 3
	_goods.add_theme_constant_override("h_separation", 6)
	_goods.add_theme_constant_override("v_separation", 6)
	box.add_child(_goods)
	# the card fills the section's width: the grid holds just this one
	_grids.erase(_grid)
	_grid.columns = 1

func _set_goods(goods: Dictionary, h: Dictionary) -> void:
	var n: int = goods.data.good.size()
	while _goods.get_child_count() < n:
		_goods.add_child(_good_tile(_goods.get_child_count()))
	for r in n:
		var tile: PanelContainer = _goods.get_child(r)
		var key := "good_" + GOOD_KEYS[r] if r < GOOD_KEYS.size() else ""
		var all := PackedFloat64Array()
		if h.has(key):
			for v in h[key]:
				all.append(float(v))
		var unit: String = goods.data.unit[r]
		var price := float(goods.data.price[r])
		var change := _change(all, all.size() - 2, true)
		var box: VBoxContainer = tile.get_child(0)
		(box.get_child(0).get_child(0) as Label).text = goods.data.good[r]
		(box.get_child(0).get_child(1) as Label).text = "%s D je %s" % [Charts.label(price), unit]
		var moved := box.get_child(1) as Label
		moved.text = change[0] + ("  zum Vormonat" if change[0] != "" else "")
		moved.add_theme_color_override("font_color", UiStyle.DIM) # dearer is good for the maker, bad for the buyer
		var spark: Control = box.get_child(2)
		spark.set_meta("values", all.slice(_first(all.size())))
		spark.queue_redraw()
		var rows := [["Preis", "%s D je %s" % [Charts.label(price), unit]],
			["Vormonat", Charts.label(all[all.size() - 2]) + " D" if all.size() > 1 else "–"],
			["Vor einem Jahr", Charts.label(all[all.size() - 13]) + " D" if all.size() > 12 else "–"],
			["Marktlager", "%s %s" % [Charts.label(float(goods.data.store[r])), unit]]]
		# the flows since the start once the tooltip is locked, so it opens short
		var since := []
		for col in [["made", "hergestellt"], ["bought", "gekauft"], ["moved", "zwischen Märkten gehandelt"],
				["imported", "von ausserhalb gekauft"], ["exported", "nach ausserhalb verkauft"]]:
			if goods.data.has(col[0]):
				since.append("[n]%s %s[/n] %s" % [Charts.label(float(goods.data[col[0]][r])), unit, col[1]])
		var tip := {"id": "good:%d" % r, "title": goods.data.good[r], "kind": "Ware", "rows": rows,
			"text": "Der [url=price]Preis[/url] ist der Median der Märkte, gewichtet nach ihren Menschen."}
		if not since.is_empty():
			tip.more = "Seit Beginn: " + ", ".join(since) + "."
		if all.size() > 1:
			tip.spark = all
			tip.spark_title = "Preis seit Beginn"
			tip.spark_unit = "D"
			tip.spark_from = date.call(int(h.day[0]))
			tip.spark_to = date.call(int(h.day[h.day.size() - 1]))
			tip.colour = Charts.SERIES[0]
		else:
			tip.more = tip.get("more", "") + " Der Verlauf füllt sich mit jedem Monat, den das Spiel läuft."
		tile.set_meta("tip", tip)

func _good_tile(r: int) -> PanelContainer:
	var tile := PanelContainer.new()
	var back := UiStyle.box(UiStyle.ROW if r % 2 == 0 else UiStyle.ROW_DARK, UiStyle.EDGE, 1, 0, 0)
	back.content_margin_left = 8
	back.content_margin_right = 8
	back.content_margin_top = 4
	back.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", back)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name := _label("", UiStyle.CONCEPT, UiStyle.SIZE_TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name)
	top.add_child(_label("", UiStyle.VALUE, UiStyle.SIZE_TEXT))
	box.add_child(_label("", UiStyle.DIM, UiStyle.SIZE_SMALL))
	var spark := Control.new()
	spark.custom_minimum_size = Vector2(0, 40)
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.draw.connect(func(): # small multiples in one hue: the name says which good
		var colour: Color = Charts.SERIES[0]
		Charts.board(spark, Rect2(Vector2.ZERO, spark.size), false)
		Charts.spark(spark, Rect2(Vector2(4, 4), spark.size - Vector2(10, 8)), spark.get_meta("values", PackedFloat64Array()), colour))
	box.add_child(spark)
	Tooltips.attach(tile, func(_at: Vector2) -> Dictionary: return tile.get_meta("tip", {}))
	return tile

# ------------------------------------------------------------------ the state's money

func _bar_card(title: String, about: String) -> void:
	var box := _card("state", title, about)
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(0, 140)
	_bars.mouse_filter = Control.MOUSE_FILTER_PASS
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
			var y := 4.0 + k * BAR_ROW
			var v: float = _bar_rows[k][1]
			var w := absf(v) / top * half
			var colour := UiStyle.GAIN if v >= 0.0 else UiStyle.LOSS
			var rect := Rect2(mid, y + 4.0, w, 14.0) if v >= 0.0 else Rect2(mid - w, y + 4.0, w, 14.0)
			_bars.draw_rect(Rect2(0, y, _bars.size.x, BAR_ROW - 4.0), UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK)
			_bars.draw_rect(rect, Color(colour, 0.85))
			_bars.draw_rect(rect, UiStyle.EDGE, false, 1.0)
			UiStyle.text_at(_bars, Vector2(6, y + 16.0), _bar_rows[k][0], UiStyle.CONCEPT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, label_w - 8.0, font)
			UiStyle.text_at(_bars, Vector2(_bars.size.x - value_w - 6.0, y + 16.0), ("+" if v > 0.0 else ("−" if v < 0.0 else "")) + Charts.label(absf(v)),
				colour, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, value_w, font))
	Tooltips.attach(_bars, func(at: Vector2) -> Dictionary:
		var k := int((at.y - 4.0) / BAR_ROW)
		if k < 0 or k >= _bar_rows.size():
			return {}
		var v: float = _bar_rows[k][1]
		return {"id": "bar:%d" % k, "title": _bar_rows[k][0], "kind": "Geld des Staates", "text": BAR_ABOUT.get(_bar_rows[k][2], ""),
			"rows": [["Denar", ("+" if v > 0.0 else ("−" if v < 0.0 else "")) + Charts.label(absf(v))]]})

# ------------------------------------------------------------------ what happened, what it says

## What happened in which month, from the history: what the player built
## (the counts grew), a famine (at least 20 dead from hunger and three
## times the year's usual), a grain price a quarter up or down in a month.
## A run of famine or shock months is marked at its first. Day -> [text].
func _find_events(d: Dictionary) -> Dictionary:
	var out := {}
	var n: int = d.get("day", []).size()
	var note := func(i: int, text: String) -> void:
		var day := int(d.day[i])
		if not out.has(day):
			out[day] = []
		out[day].append(text)
	var builds := [["farms_built", "Ein Hof gebaut", "%d Höfe gebaut"], ["roads_built", "Ein Strassenstück gebaut", "%d Strassenstücke gebaut"],
		["fields_built", "Ein Feldstück angelegt", "%d Feldstücke angelegt"]]
	var famine := false
	var shock := false
	for i in range(1, n):
		for b in builds:
			if d.has(b[0]):
				var grew := int(d[b[0]][i]) - int(d[b[0]][i - 1])
				if grew > 0:
					note.call(i, b[1] if grew == 1 else b[2] % grew)
		if d.has("hunger_deaths"):
			var dead := float(d.hunger_deaths[i])
			var before := PackedFloat64Array()
			for j in range(maxi(0, i - 12), i):
				before.append(float(d.hunger_deaths[j]))
			before.sort()
			var now := dead >= 20.0 and dead >= 3.0 * before[before.size() / 2]
			if now and not famine:
				note.call(i, "Hungersnot: %s Hungertote" % Charts.label(dead))
			famine = now
		if d.has("price_median"):
			var p0 := float(d.price_median[i - 1])
			var change := (float(d.price_median[i]) - p0) / p0 if p0 > 0.0 else 0.0
			var now := absf(change) >= 0.25
			if now and not shock:
				note.call(i, ("Teuerung: Korn %s %% teurer" if change > 0.0 else "Preissturz: Korn %s %% billiger") % _pct(absf(change) * 100.0))
			shock = now
	return out

## Each card's finding: one sentence on what its numbers say now, against
## a year before (or the start, while the game is younger).
func _find_all(d: Dictionary) -> void:
	var says := {}
	var n: int = d.get("day", []).size()
	var period := "Im letzten Jahr" if n > 12 else "Seit Beginn"
	if n > 0:
		var persons := _col(d, "persons")
		says.persons = "%s Menschen, %s." % [_num(persons[n - 1]), _against_year(persons, "mehr", "weniger")]
		var born := _year_sum(_col(d, "births"))
		var died := _year_sum(_col(d, "deaths"))
		says.life = "%s %s Geburten und %s Todesfälle: %s." % [period, _num(born), _num(died),
			"es werden mehr geboren, als sterben" if born > died else "es sterben mehr, als geboren werden"]
		var starved := _year_sum(_col(d, "hunger_deaths"))
		says.hunger = ("%s ist niemand verhungert." % period) if starved < 0.5 else ("%s sind %s Menschen verhungert." % [period, _num(starved)])
		var price := _col(d, "price_median")
		if price.size() == n:
			says.price = "Korn kostet im Median %s D/kg, %s." % [_num(price[n - 1]), _against_year(price, "teurer", "billiger")]
			if n > 3 and price[n - 1] <= _lowest(price) * 1.0001:
				says.price += " Tiefster Stand seit Beginn."
			elif n > 3 and price[n - 1] >= _highest(price) * 0.9999:
				says.price += " Höchster Stand seit Beginn."
		var worst := -1
		var short := 0
		for k in FED_KEYS.size():
			var fed := _col(d, "fed_" + FED_KEYS[k], 100.0)
			if fed.size() == n and fed[n - 1] < 99.0:
				short += 1
				if worst < 0 or fed[n - 1] < _col(d, "fed_" + FED_KEYS[worst], 100.0)[n - 1]:
					worst = k
		if worst < 0:
			says.fed = "Alle Schichten essen sich satt."
		else:
			says.fed = "%s %s nur %d %% ihres Kornbedarfs." % [FED_SUBJECTS[worst], "isst" if worst == 4 else "essen",
				floori(_col(d, "fed_" + FED_KEYS[worst], 100.0)[n - 1])]
			if short > 1:
				says.fed += " %d Schichten bekommen nicht genug." % short
		var harvest := _col(d, "harvest_t")
		if n >= 24:
			var last := _year_sum(harvest)
			var before := _year_sum(harvest.slice(0, n - 12))
			says.harvest = "Ernte im letzten Jahr %s t, %s." % [_num(last), _versus(last, before, "mehr", "weniger", "im Jahr davor")]
		else:
			says.harvest = "%s %s t geerntet." % [period, _num(_year_sum(harvest))]
		var stored := _col(d, "horrea_t")
		for key in ["lords_t", "market_store_t"]:
			var more := _col(d, key)
			for i in mini(stored.size(), more.size()):
				stored[i] += more[i]
		if stored.size() == n:
			says.granaries = "In den Speichern liegen %s t Korn, %s." % [_num(stored[n - 1]), _against_year(stored, "mehr", "weniger")]
		var spoiled := _year_sum(_col(d, "spoiled_t"))
		says.flows = "%s sind %s t Korn verdorben." % [period, _num(spoiled)]
		var out := _year_sum(_col(d, "export_t"))
		if out > 0.0:
			says.flows += " %s t gingen über den Kartenrand." % _num(out)
		var clothes := _col(d, "clothes", 100.0)
		if clothes.size() == n:
			says.clothes = "Die Haushalte haben %d %% der Kleidung, die sie brauchen." % roundi(clothes[n - 1])
		var p10 := _col(d, "real_p10")
		var p50 := _col(d, "real_p50")
		var need := _col(d, "need_wage")
		if p10.size() == n and need.size() == n and p50.size() == n:
			var w := [_num(p10[n - 1]), _num(p50[n - 1]), _num(need[n - 1])]
			if p10[n - 1] < need[n - 1]:
				says.real = "Im ärmsten Zehntel der Märkte bringt ein Taglohn %s kg Korn, nötig wären %s kg." % [w[0], w[2]]
			elif p50[n - 1] < need[n - 1]:
				says.real = "Am Median bringt ein Taglohn %s kg Korn, nötig wären %s kg." % [w[1], w[2]]
			else:
				says.real = "Ein Taglohn reicht überall: selbst im ärmsten Zehntel der Märkte bringt er %s kg, nötig sind %s kg." % [w[0], w[2]]
		var vacant := _col(d, "vacant")
		var idle := _col(d, "idle")
		if vacant.size() == n and idle.size() == n:
			if idle[n - 1] > vacant[n - 1] * 1.2:
				says.work = "Arbeit fehlt: %s Arbeitstage blieben liegen, %s wurden vergeblich gesucht." % [_num(idle[n - 1]), _num(vacant[n - 1])]
			elif vacant[n - 1] > idle[n - 1] * 1.2:
				says.work = "Arbeiter fehlen: %s Arbeitstage wurden vergeblich gesucht, %s blieben liegen." % [_num(vacant[n - 1]), _num(idle[n - 1])]
			else:
				says.work = "Gesuchte und angebotene Arbeit halten sich die Waage."
		var cash := _col(d, "cash")
		if cash.size() == n:
			says.cash = "In der Kasse liegen %s Denar, %s." % [_num(cash[n - 1]), _against_year(cash, "mehr", "weniger")]
	for key in ["jobs", "farms"]:
		var ring: Dictionary = _rings[key]
		var total := 0.0
		for v in ring.values:
			total += v
		if total > 0.0 and ring.names.size() > 0:
			var share := roundi(ring.values[0] / total * 100.0)
			says[key] = ("Die meisten arbeiten als %s: %d %% der Menschen." if key == "jobs" else "Am häufigsten: %s, %d %% der Höfe.") % [ring.names[0], share]
	var classes: Dictionary = _tables.get("classes", {})
	if not classes.is_empty() and classes.data.has("money"):
		var top := Array(classes.data.kind).find(FED_NAMES[4])
		var money := 0.0
		var people := 0.0
		for r in classes.data.kind.size():
			money += float(classes.data.money[r])
			if classes.data.has("persons"):
				people += float(classes.data.persons[r])
		if top >= 0 and money > 0.0:
			says.money = "Die Oberschicht hält %d %% des Geldes" % roundi(float(classes.data.money[top]) / money * 100.0)
			if people > 0.0:
				says.money += ", ist aber nur %s %% der Menschen" % _pct(float(classes.data.persons[top]) / people * 100.0)
			says.money += "."
	var goods: Dictionary = _tables.get("goods", {})
	if not goods.is_empty() and n > 1:
		var moved := -1.0
		for r in mini(goods.data.good.size(), GOOD_KEYS.size()):
			var price := _col(d, "good_" + GOOD_KEYS[r])
			if price.size() == n and price[_year_back(n)] > 0.0:
				var change := absf(price[n - 1] / price[_year_back(n)] - 1.0)
				if change > moved:
					moved = change
					says.goods = "Am stärksten verändert: %s, %s." % [goods.data.good[r], _against_year(price, "teurer", "billiger")]
	var paid := 0.0
	var got := 0.0
	for r in _bar_rows:
		if r[2] == "wages":
			paid = -float(r[1])
		elif r[2] in ["tax", "rent"]:
			got += float(r[1])
	if paid > 0.0:
		says.state = "Steuern und Pacht decken %d %% dessen, was der Staat an Löhnen zahlt." % roundi(got / paid * 100.0)
	for key in _findings:
		var label: Label = _findings[key]
		label.text = says.get(key, "")
		label.visible = label.text != ""

## A history column as floats, times `scale`.
static func _col(d: Dictionary, key: String, scale := 1.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for v in d.get(key, []):
		out.append(float(v) * scale)
	return out

## The row a year before the last (or the first).
static func _year_back(n: int) -> int:
	return n - 13 if n > 12 else 0

## The last twelve months added up (or all).
static func _year_sum(vals: PackedFloat64Array) -> float:
	var sum := 0.0
	for v in vals.slice(maxi(0, vals.size() - 12)):
		sum += v
	return sum

static func _lowest(vals: PackedFloat64Array) -> float:
	var low := INF
	for v in vals:
		low = minf(low, v)
	return low

static func _highest(vals: PackedFloat64Array) -> float:
	var high := -INF
	for v in vals:
		high = maxf(high, v)
	return high

## "5 % mehr als vor einem Jahr": the last value against a year before.
static func _against_year(vals: PackedFloat64Array, up: String, down: String) -> String:
	var n := vals.size()
	if n < 2:
		return "noch ohne Vergleich"
	return _versus(vals[n - 1], vals[_year_back(n)], up, down, "vor einem Jahr" if n > 12 else "zu Beginn")

static func _versus(now: float, before: float, up: String, down: String, when: String) -> String:
	if absf(before) < 1e-9:
		return "zuvor nichts"
	var pct := (now - before) / absf(before) * 100.0
	if absf(pct) < 1.0:
		return "etwa gleich wie %s" % when
	return "%s %% %s als %s" % [_pct(absf(pct)), up if pct > 0.0 else down, when]

## A number in a sentence, Swiss style: 9’740, 56k, 1.6.
static func _num(v: float) -> String:
	var a := absf(v)
	if a >= 1000.0 and a < 1.0e4:
		return "%s%d’%03d" % ["-" if v < 0.0 else "", int(a) / 1000, int(a) % 1000]
	return Charts.label(v)

static func _pct(p: float) -> String:
	return ("%.1f" % p) if p < 10.0 else ("%d" % roundi(p))

# ------------------------------------------------------------------ parts

func _swatch(colour: Color, text: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flag := Control.new() # EU5's little pennant
	flag.custom_minimum_size = Vector2(9, 13)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag.draw.connect(func():
		var shape := PackedVector2Array([Vector2(0, 0), Vector2(9, 0), Vector2(9, 13), Vector2(4.5, 9.5), Vector2(0, 13)])
		flag.draw_colored_polygon(shape, colour)
		flag.draw_rect(Rect2(0, 0, 9, 3), Color(1, 1, 1, 0.25))
		shape.append(shape[0])
		flag.draw_polyline(shape, UiStyle.EDGE, 1.0, true))
	line.add_child(flag)
	var label := _label(text, UiStyle.TEXT, UiStyle.SIZE_SMALL + 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)
	return line

static func _label(text: String, colour: Color, font_size: int) -> Label:
	return UiStyle.label(text, colour, font_size)
