extends ScrollContainer
## The statistics' first tab, "Übersicht": the state of the realm at a
## glance, as a grand strategy economy panel opens. Five figures with their change
## since the month before and a small curve, the months the charts show,
## then sections of cards: people, food and grain, work and money, goods,
## the state. Each card opens with what its numbers say (Knaflic: the
## finding, not only the topic), computed from them; its title's tooltip
## says what it shows. The line charts share one month under the mouse,
## and mark what happened (built, famine, price shocks). Shares are sorted
## bars, what each class ate small multiples on one scale. Every line, bar,
## row and good has a tooltip.
##
## sim_tables.gd hands it the tables (history, population, farms, state,
## classes, goods) with show_tables(); it only draws them.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const Charts = preload("res://scripts/ui/charts.gd")
const Vic3Style = preload("res://scripts/ui/vic3_style.gd")
const CARD_MIN := 320.0
const SECTION_PX := 21 # a section's heading, small caps
const CHART_PX := 170.0
const OTHER := Color("6d7479") # the medal of "Andere", the rest
const BARS_MAX := 6 # rows of a share card before "Andere"
const BAR_ROW := 26.0
const BAR_PX := 8.0 # a bar's height in its trough, as the menu's (Vic3)
const MEDAL_R := 10.5
const NAME_X := 31.0 # a row's name, right of its medal
const SHARE_PX := 56.0 # a row's share at the right
const FED_ROW := 34.0
const FED_NAME_PX := 108.0
## The medals' icons in assets/ui/icons (Vic3Style.icon), white, tinted
## when drawn; a name without one shows its first letter.
const ICONS := {
	"Hofleute": "family-house", "Im Zelt": "camping-tent", "Lohnarbeit": "anvil", "Händler": "two-coins", "Oberschicht": "roman-toga",
	"Bauern": "wheat", "Pächter": "field", "Tagelöhner": "walking-boot", "Handwerker": "anvil", "Adel": "laurel-crown",
	"Geistliche": "greek-temple", "Gelehrte": "open-book", "Beamte": "scroll-quill", "Offiziere": "eagle-emblem",
	"Unternehmer": "scales", "Familienhof": "family-house", "Pachthof": "field", "Gut": "barn",
}
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
var _shares := {} # card key -> {control, names, values, colours, ref, ref_name, total, unit, title, hover, foot}
var _icons := {} # name -> its medal's icon, or null
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
	# the figures as a stat strip: cells of two greens in one gold line
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.STAT, UiStyle.GOLD_DIM, 1, 2, 0))
	_column.add_child(strip)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 0)
	strip.add_child(_tiles)
	# the months the charts show, as time buttons
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
	_shares_card("jobs", "Menschen nach Beruf", "Die Menschen nach dem Beruf ihres Haushalts.")
	_line_card("life", "Geburten und Todesfälle", "", "Geburten und Todesfälle im Monat. Die ersten Kinder kommen erst nach etwa neun Monaten zur Welt.")
	_line_card("hunger", "Hungertote", "", "Menschen, die im Monat an Hunger sterben.")
	_section("Essen und Korn")
	_line_card("price", "Kornpreis", "D/kg", "Jeder Markt hat seinen eigenen Kornpreis. Die Linie ist der Median der Märkte, das Band reicht vom billigsten zum teuersten Markt, höchstens bis zum doppelten Median, damit ein teurer Markt wie Rom die Linie nicht flach drückt.")
	_fed_card()
	_line_card("harvest", "Ernte und Verkauf", "t", "Korn, das die Höfe im Monat ernten, und Korn, das die Märkte im Monat verkaufen.")
	_line_card("granaries", "Getreide in Speichern", "t", "Korn in den Speichern des Staates (Steuerkorn), der Grundherren (Pachtkorn) und der Händler auf den Märkten.")
	_line_card("flows", "Korn ausser Handel", "t", "Korn im Monat, das verdirbt, über den Kartenrand verkauft wird, zwischen fernen Märkten gehandelt oder als Almosen verteilt wird.")
	_line_card("clothes", "Kleidung vom Bedarf", "%", "Kleidung, die die Haushalte besitzen, gemessen an dem, was sie brauchen.")
	_section("Arbeit und Geld")
	_line_card("real", "Reallohn", "kg", "Der Taglohn eines Marktes in Korn zu dessen Preis: so viel kann ein Tag Arbeit kaufen. Gestrichelt: so viel muss ein Lohnarbeiter je Arbeitstag verdienen, damit sein Teil der Familie satt wird (Bedarf der Familie durch ihre Erwachsenen und 290 Arbeitstage im Jahr, nach Columella).")
	_line_card("work", "Arbeitstage in der Woche", "Tage", "Arbeitstage der letzten Woche, die jemand gesucht und niemanden gefunden hat, und die jemand angeboten hat, ohne eingestellt zu werden.")
	_shares_card("money", "Geld nach Schicht", "Alles Geld der Haushalte nach Schicht, bei Bauern mit dem Geld ihres Hofs.")
	_shares_card("farms", "Höfe nach Art", "Familienhof: die Familie bebaut ihr eigenes Land. Pachthof: sie bebaut gepachtetes Land. Gut: ein Grundherr lässt sein Land bebauen.")
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
		_set_fed(d)
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
		_set_shares("jobs", sums, "Menschen")
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
		_set_shares("farms", sums, "Höfe")
	var classes: Dictionary = tables.get("classes", {})
	if not classes.is_empty() and classes.data.has("money"):
		var sums := {}
		var people := {}
		for r in classes.data.kind.size():
			sums[classes.data.kind[r]] = float(classes.data.money[r])
			if classes.data.has("persons"):
				people[classes.data.kind[r]] = float(classes.data.persons[r])
		var fixed := {}
		for k in FED_NAMES.size():
			fixed[FED_NAMES[k]] = FED_COLOURS[k]
		_set_shares("money", sums, "Denar", fixed, people, "Menschen")
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

## The figures as a stat strip: the name in the concepts' colour, the value, the
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

## A heading over a group, as the menus' rules: the name in gold small
## caps between two gold rules ending in a small diamond. The cards after
## it go in its grid.
func _section(title: String) -> void:
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 30)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.draw.connect(func():
		var f := UiStyle.title_font()
		var w := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, SECTION_PX).x
		var mid := head.size.x * 0.5
		var y := head.size.y * 0.5 + 1.0
		UiStyle.text_at(head, Vector2(0, y + SECTION_PX * 0.35), title, UiStyle.GOLD_LIT, SECTION_PX, HORIZONTAL_ALIGNMENT_CENTER, head.size.x, f)
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

## A card as the columns of the menus' (Vic3) windows: no frame, its title
## in small caps on a slim band of leather with a gold line under it, the
## rest on the slate. The title's tooltip says what the card shows (`about`).
func _card(key: String, title: String, about: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(CARD_MIN, 0)
	_grid.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var head := _label(title, UiStyle.TEXT, UiStyle.SIZE_HEAD)
	head.add_theme_font_override("font", UiStyle.title_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.clip_text = true
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var band := UiStyle.box(UiStyle.BAR, UiStyle.GOLD_DIM, 0, 2, 3)
	band.border_width_bottom = 1
	band.corner_radius_bottom_left = 0
	band.corner_radius_bottom_right = 0
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

# ------------------------------------------------------------------ shares and the classes' food

## Shares of a whole as sorted bars, as the menu's (Vic3) lists: a medal,
## the name, the bar in its trough, the share. The largest on top, the
## smallest folded into "Andere" at the foot. `ref` (set by _set_shares)
## marks a second share per row as a tick: on the money card, the people.
func _shares_card(key: String, title: String, about: String) -> void:
	var box := _card(key, title, about)
	var rows := Control.new()
	rows.mouse_filter = Control.MOUSE_FILTER_PASS # the wheel still scrolls
	box.add_child(rows)
	var foot := _label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size = Vector2(CARD_MIN - 40.0, 0)
	box.add_child(foot)
	var entry := {"control": rows, "names": PackedStringArray(), "values": PackedFloat64Array(), "colours": [],
		"ref": PackedFloat64Array(), "ref_name": "", "total": 0.0, "unit": "", "title": title, "hover": -1, "foot": foot}
	_shares[key] = entry
	rows.draw.connect(func(): _draw_shares(rows, entry))
	rows.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var i := int(e.position.y / BAR_ROW)
			if i >= entry.names.size():
				i = -1
			if i != entry.hover:
				entry.hover = i
				rows.queue_redraw())
	rows.mouse_exited.connect(func():
		entry.hover = -1
		rows.queue_redraw())
	Tooltips.attach(rows, func(at: Vector2) -> Dictionary: return _shares_tip(key, int(at.y / BAR_ROW)))

## `sums` name -> amount; `colours` name -> the colour a name keeps in
## every chart (the classes), the others get a plain medal; `ref` name ->
## a second amount drawn as a tick, named `ref_name`.
func _set_shares(key: String, sums: Dictionary, unit: String, colours := {}, ref := {}, ref_name := "") -> void:
	var entry: Dictionary = _shares[key]
	var names := sums.keys()
	names.sort_custom(func(a, b): return sums[a] > sums[b])
	var ref_total := 0.0
	for name in ref:
		ref_total += float(ref[name])
	var shown := PackedStringArray()
	var values := PackedFloat64Array()
	var refs := PackedFloat64Array()
	var hues := []
	var rest := 0.0
	var rest_ref := 0.0
	var total := 0.0
	for i in names.size():
		var v := float(sums[names[i]])
		total += v
		var r := float(ref.get(names[i], 0.0)) / ref_total if ref_total > 0.0 else 0.0
		if i < BARS_MAX or names.size() == BARS_MAX + 1:
			shown.append(names[i])
			values.append(v)
			refs.append(r)
			hues.append(colours.get(names[i], Color.TRANSPARENT))
		else:
			rest += v
			rest_ref += r
	if rest > 0.0:
		shown.append("Andere")
		values.append(rest)
		refs.append(rest_ref)
		hues.append(OTHER)
	entry.names = shown
	entry.values = values
	entry.colours = hues
	entry.ref = refs if ref_total > 0.0 else PackedFloat64Array()
	entry.ref_name = ref_name
	entry.total = total
	entry.unit = unit
	var rows: Control = entry.control
	rows.custom_minimum_size.y = BAR_ROW * shown.size()
	var foot: Label = entry.foot
	foot.text = "Zusammen %s %s." % [_num(total), unit]
	if ref_total > 0.0:
		foot.text += " Der weisse Strich: Anteil an den %s." % ref_name
	rows.queue_redraw()

func _draw_shares(ci: Control, entry: Dictionary) -> void:
	var n: int = entry.names.size()
	var total: float = entry.total
	if n == 0 or total <= 0.0:
		return
	var font := UiStyle.serif()
	var top := 0.0 # the longest bar or tick fills the trough
	var name_w := 0.0
	for i in n:
		top = maxf(top, entry.values[i] / total)
		if i < entry.ref.size():
			top = maxf(top, entry.ref[i])
		name_w = maxf(name_w, font.get_string_size(entry.names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x)
	var x0 := NAME_X + minf(name_w, 140.0) + 10.0
	var x1 := ci.size.x - SHARE_PX - 8.0
	for i in n:
		var y := i * BAR_ROW
		var mid := y + (BAR_ROW - 2.0) * 0.5
		ci.draw_rect(Rect2(0, y, ci.size.x, BAR_ROW - 2.0), UiStyle.ROW if i % 2 == 0 else UiStyle.ROW_DARK)
		if i == entry.hover:
			ci.draw_rect(Rect2(0, y, ci.size.x, BAR_ROW - 2.0), UiStyle.HOVER)
		_medal(ci, Vector2(MEDAL_R + 5.0, mid), entry.names[i], entry.colours[i])
		UiStyle.text_at(ci, Vector2(NAME_X, mid + 5.0), entry.names[i], UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, x0 - NAME_X - 6.0, font)
		var share: float = entry.values[i] / total
		var trough := Rect2(x0, mid - BAR_PX * 0.5 - 2.0, x1 - x0, BAR_PX + 4.0)
		var inner := trough.size.x - 4.0
		_bar(ci, trough, x0 + 2.0, x0 + 2.0 + inner * share / top, UiStyle.GOLD)
		if i < entry.ref.size() and entry.ref[i] > 0.0:
			var x: float = x0 + 2.0 + inner * entry.ref[i] / top
			ci.draw_line(Vector2(x, trough.position.y - 3.0), Vector2(x, trough.end.y + 3.0), UiStyle.EDGE, 4.0)
			ci.draw_line(Vector2(x, trough.position.y - 2.0), Vector2(x, trough.end.y + 2.0), UiStyle.TEXT, 2.0)
		UiStyle.text_at(ci, Vector2(x1 + 4.0, mid + 5.0), _pct(share * 100.0) + " %", UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, SHARE_PX, font)

func _shares_tip(key: String, i: int) -> Dictionary:
	var entry: Dictionary = _shares[key]
	if i < 0 or i >= entry.names.size() or entry.total <= 0.0:
		return {}
	var share: float = entry.values[i] / entry.total * 100.0
	var rows := [[entry.unit, _num(entry.values[i])], ["Anteil", _pct(share) + " %"]]
	if i < entry.ref.size():
		rows.append(["Anteil an den " + entry.ref_name, _pct(entry.ref[i] * 100.0) + " %"])
		if entry.ref[i] > 0.0:
			rows.append(["Je Kopf, gemessen am Schnitt", "%s×" % _pct(share / (entry.ref[i] * 100.0))])
	return {"id": "share:%s:%d" % [key, i], "title": entry.names[i], "kind": entry.title, "rows": rows}

## What each class ate as small multiples: a row each with the class, its
## curve on one scale for all rows, and the share now (or in the month
## under the mouse). Red is what was missing to eat one's fill.
func _fed_card() -> void:
	var box := _card("fed", "Gegessen nach Schicht", "Wie viel ihres Kornbedarfs jede Schicht im Monat gegessen hat. 100 % heisst satt. Alle Zeilen haben dieselbe Skala.")
	var rows := Control.new()
	rows.custom_minimum_size = Vector2(0, FED_ROW * FED_KEYS.size())
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(rows)
	var foot := _label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size = Vector2(CARD_MIN - 40.0, 0)
	box.add_child(foot)
	# a line chart for _hover_all: the month under the mouse is shared
	var entry := {"control": rows, "series": [], "days": PackedInt64Array(), "hover": -1, "row": -1, "lo": 90.0, "foot": foot}
	_lines["fed"] = entry
	rows.draw.connect(func(): _draw_fed(rows, entry))
	rows.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var row := int(e.position.y / FED_ROW)
			if row != entry.row:
				entry.row = row
				rows.queue_redraw()
			var plot := _fed_plot(rows, 0)
			var n: int = entry.days.size()
			var m := -1
			if n > 1 and e.position.x >= plot.position.x - 4.0 and e.position.x <= plot.end.x + 4.0:
				m = clampi(roundi((e.position.x - plot.position.x) / plot.size.x * (n - 1)), 0, n - 1)
			if m != entry.hover:
				_hover_all(m))
	rows.mouse_exited.connect(func():
		entry.row = -1
		rows.queue_redraw()
		_hover_all(-1))
	Tooltips.attach(rows, func(at: Vector2) -> Dictionary: return _fed_tip(int(at.y / FED_ROW)))

func _set_fed(d: Dictionary) -> void:
	var entry: Dictionary = _lines["fed"]
	var series := []
	var lo := 100.0
	for k in FED_KEYS.size():
		var all := _col(d, "fed_" + FED_KEYS[k], 100.0)
		if all.is_empty():
			continue
		var values := all.slice(_first(all.size()))
		lo = minf(lo, _lowest(values))
		series.append({"k": k, "values": values, "all": all})
	entry.series = series
	entry.lo = clampf(floorf((lo - 5.0) / 10.0) * 10.0, 0.0, 90.0) # room below the lowest
	var days := PackedInt64Array(Array(d.day))
	entry.days = days.slice(_first(days.size()))
	var foot: Label = entry.foot
	foot.text = "Alle Zeilen von %d bis 100 %%. Gestrichelt: satt. Rot: was zum Sattwerden fehlte." % int(entry.lo)
	entry.control.custom_minimum_size.y = FED_ROW * maxi(1, series.size())
	entry.control.queue_redraw()

## Row k's plot: right of the medal and name, left of the share.
func _fed_plot(ci: Control, k: int) -> Rect2:
	var x0 := NAME_X + FED_NAME_PX
	return Rect2(x0, k * FED_ROW + 4.0, ci.size.x - x0 - SHARE_PX - 10.0, FED_ROW - 10.0)

func _draw_fed(ci: Control, entry: Dictionary) -> void:
	var font := UiStyle.serif()
	var lo: float = entry.lo
	for row in entry.series.size():
		var s: Dictionary = entry.series[row]
		var k: int = s.k
		var y: float = row * FED_ROW
		var mid := y + (FED_ROW - 2.0) * 0.5
		ci.draw_rect(Rect2(0, y, ci.size.x, FED_ROW - 2.0), UiStyle.ROW if row % 2 == 0 else UiStyle.ROW_DARK)
		if row == entry.row:
			ci.draw_rect(Rect2(0, y, ci.size.x, FED_ROW - 2.0), UiStyle.HOVER)
		_medal(ci, Vector2(MEDAL_R + 5.0, mid), FED_NAMES[k], FED_COLOURS[k])
		UiStyle.text_at(ci, Vector2(NAME_X, mid + 5.0), FED_NAMES[k], UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, FED_NAME_PX - 6.0, font)
		var plot := _fed_plot(ci, row)
		ci.draw_rect(plot.grow(1.0), UiStyle.EDGE)
		ci.draw_rect(plot, UiStyle.CHART)
		var vals: PackedFloat64Array = s.values
		var n := vals.size()
		var y_of := func(v: float) -> float: return plot.end.y - 1.0 - (clampf(v, lo, 100.0) - lo) / (100.0 - lo) * (plot.size.y - 2.0)
		var x_of := func(i: int) -> float: return plot.position.x + plot.size.x * float(i) / float(maxi(1, n - 1))
		var full: float = y_of.call(100.0)
		for part in Charts.dashes(PackedVector2Array([Vector2(plot.position.x, full), Vector2(plot.end.x, full)]), 4.0, 3.0):
			ci.draw_polyline(part, UiStyle.DIM, 1.0)
		if n >= 2:
			# the gap to 100 %, a polygon per run of hungry months
			var i := 0
			while i < n:
				if vals[i] >= 99.999:
					i += 1
					continue
				var gap := PackedVector2Array([Vector2(x_of.call(maxi(0, i - 1)), full)])
				if i == 0:
					gap.append(Vector2(x_of.call(0), full))
				while i < n and vals[i] < 99.999:
					gap.append(Vector2(x_of.call(i), y_of.call(vals[i])))
					i += 1
				gap.append(Vector2(x_of.call(mini(i, n - 1)), full))
				if gap[0] == gap[1]:
					gap.remove_at(0)
				if gap.size() >= 3 and Geometry2D.triangulate_polygon(gap).size() > 0:
					ci.draw_colored_polygon(gap, Color(Charts.RED, 0.3))
			var line := PackedVector2Array()
			for j in n:
				line.append(Vector2(x_of.call(j), y_of.call(vals[j])))
			ci.draw_polyline(line, Charts.SERIES[0], 1.5, true)
		var hovered: bool = entry.hover >= 0 and entry.hover < n
		var m: int = entry.hover if hovered else n - 1
		if hovered and n >= 2:
			var x: float = x_of.call(m)
			ci.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(UiStyle.TEXT, 0.45), 1.0)
			ci.draw_circle(Vector2(x, y_of.call(vals[m])), 2.5, UiStyle.VALUE)
		if n > 0:
			UiStyle.text_at(ci, Vector2(ci.size.x - SHARE_PX - 6.0, mid + 5.0), "%d %%" % floori(vals[m]),
				UiStyle.LOSS if vals[m] < 99.0 else UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, SHARE_PX, font)

## A class's row: the month under the mouse (or the last), its lowest
## month, how many it counts, and its whole curve since the start.
func _fed_tip(row: int) -> Dictionary:
	var entry: Dictionary = _lines["fed"]
	if row < 0 or row >= entry.series.size():
		return {}
	var s: Dictionary = entry.series[row]
	var k: int = s.k
	var vals: PackedFloat64Array = s.values
	var n := vals.size()
	if n == 0:
		return {}
	var m: int = entry.hover if entry.hover >= 0 and entry.hover < n else n - 1
	var low := 0
	for i in n:
		if vals[i] < vals[low]:
			low = i
	var rows := [["Gegessen vom Bedarf", "%d %%" % floori(vals[m]), UiStyle.LOSS if vals[m] < 99.0 else UiStyle.TEXT]]
	if m > 0:
		rows.append(["Vormonat", "%d %%" % floori(vals[m - 1])])
	rows.append(["Tiefster Monat", "%d %%, %s" % [floori(vals[low]), date.call(int(entry.days[low]))]])
	var classes: Dictionary = _tables.get("classes", {})
	if not classes.is_empty() and classes.data.has("persons"):
		var r := Array(classes.data.kind).find(FED_NAMES[k])
		if r >= 0:
			rows.append(["Menschen heute", _num(float(classes.data.persons[r]))])
	var tip := {"id": "fed:%d:%d" % [k, m], "title": FED_NAMES[k], "kind": date.call(int(entry.days[m])), "rows": rows}
	var happened: Array = _events.get(int(entry.days[m]), [])
	if not happened.is_empty():
		tip.text = "[n]In diesem Monat:[/n] " + "; ".join(happened) + "."
	var all: PackedFloat64Array = s.all
	if all.size() > 1:
		var h: Dictionary = _tables.get("history", {}).get("data", {})
		tip.spark = all
		tip.spark_title = "Gegessen seit Beginn"
		tip.spark_unit = "%"
		var full := PackedFloat64Array()
		full.resize(all.size())
		full.fill(100.0)
		tip.spark_ref = full # satt
		tip.colour = Charts.SERIES[0]
		if h.has("day"):
			tip.spark_from = date.call(int(h.day[0]))
			tip.spark_to = date.call(int(h.day[h.day.size() - 1]))
	return tip

## A bar as the menu's (Vic3) bars: a dark trough with a thin edge, the bar
## BAR_PX high inside it, dark where it starts and light where it ends.
func _bar(ci: CanvasItem, trough: Rect2, start: float, end: float, colour: Color) -> void:
	ci.draw_rect(trough, UiStyle.CHART_GRID)
	ci.draw_rect(trough, UiStyle.EDGE, false, 1.0)
	if absf(end - start) < 0.5:
		return
	var a := Vector2(start, trough.position.y + (trough.size.y - BAR_PX) * 0.5)
	var b := Vector2(end, a.y)
	var dark := colour.darkened(0.45)
	var light := colour.lightened(0.2)
	ci.draw_polygon(PackedVector2Array([a, b, b + Vector2(0, BAR_PX), a + Vector2(0, BAR_PX)]),
		PackedColorArray([dark, light, light, dark]))

## A row's round medal in a gold rim, as the menu's (Vic3) lists: its icon
## when it has one, else its first letter; on the colour the
## entity keeps in every chart, or dark.
func _medal(ci: CanvasItem, at: Vector2, name: String, colour: Color) -> void:
	ci.draw_circle(at, MEDAL_R + 1.0, UiStyle.EDGE)
	ci.draw_circle(at, MEDAL_R, UiStyle.GOLD)
	ci.draw_circle(at, MEDAL_R - 1.5, colour.darkened(0.3) if colour.a > 0.0 else UiStyle.INSET)
	var icon := _icon(name)
	if icon != null:
		var side := (MEDAL_R - 2.5) * 2.0
		ci.draw_texture_rect(icon, Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), false, UiStyle.TEXT)
	else:
		UiStyle.text_at(ci, at + Vector2(-MEDAL_R, 4.0), name.left(1), UiStyle.TEXT, UiStyle.SIZE_SMALL - 1, HORIZONTAL_ALIGNMENT_CENTER, MEDAL_R * 2.0, UiStyle.bold())

func _icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = Vic3Style.icon(ICONS[name]) if ICONS.has(name) else null
	return _icons[name]

# ------------------------------------------------------------------ goods

## The goods as small charts side by side, as a market's goods: the
## name, the median price and its change, the price over the chosen months.
## Over a good, a tooltip with its price since the start.
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
	var back := UiStyle.box(UiStyle.ROW if r % 2 == 0 else UiStyle.ROW_DARK, Color(UiStyle.GOLD_DIM, 0.6), 1, 2, 0)
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
		var x1 := _bars.size.x - value_w - 8.0
		var mid := (label_w + x1) * 0.5
		var half := (x1 - label_w) * 0.5 - 2.0
		for k in _bar_rows.size():
			var y := 4.0 + k * BAR_ROW
			var v: float = _bar_rows[k][1]
			var colour := UiStyle.GAIN if v >= 0.0 else UiStyle.LOSS
			_bars.draw_rect(Rect2(0, y, _bars.size.x, BAR_ROW - 4.0), UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK)
			var trough := Rect2(label_w, y + (BAR_ROW - 4.0 - BAR_PX) * 0.5 - 2.0, x1 - label_w, BAR_PX + 4.0)
			_bar(_bars, trough, mid, mid + signf(v) * absf(v) / top * half, colour) # from nothing in the middle
			_bars.draw_line(Vector2(mid, trough.position.y - 3.0), Vector2(mid, trough.end.y + 3.0), UiStyle.GOLD, 1.0)
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
		var bars: Dictionary = _shares[key]
		if bars.total > 0.0 and bars.names.size() > 0:
			var share := roundi(bars.values[0] / bars.total * 100.0)
			says[key] = ("Die meisten arbeiten als %s: %d %% der Menschen." if key == "jobs" else "Am häufigsten: %s, %d %% der Höfe.") % [bars.names[0], share]
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
