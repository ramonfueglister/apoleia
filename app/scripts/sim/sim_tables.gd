extends CanvasLayer
## The simulation in tables, in the manner of EU5: markets, population by
## region and occupation, farms by region and the state's accounts, in a
## window (ui/ui_window.gd) that can be moved, sized and folded and lies
## above the rest of the HUD. T (or the red seal in the top bar) opens and
## closes it. As Victoria 3's statistics it is split by topic (VIEWS): the
## window's tabs are the topics (Übersicht, Menschen, Korn, Geld, Waren,
## Höfe, Staat), the row under them each topic's views: a page of cards
## (sim_overview.gd: the overview with its Lage, the classes side by side,
## a topic's charts) or a table. The months the charts show are chosen
## right of the views; a click on a line of the Lage opens its charts. Every row has an EU5 tooltip (ui/tooltips.gd): staying on it
## locks it and shows the row's last months; its blue terms explain
## themselves. The markets show each market's price over the last
## SPARK_MONTHS months as a small curve, gathered from the monthly tables
## since the game started (the bridge has no history per market yet).
##
## ApoleiaPeople builds a table between two days (sim/src/tables.rs,
## sim/godot/src/tables.rs): ask_table(kind) asks the sim thread, and
## take_table() returns {} until the answer is there, then {kind, name, day,
## columns, labels, units, data}. data holds one packed array per key;
## columns are the keys shown, labels and units their heads. A unit "%"
## marks a share 0..1 (shown in per cent over a bar). id, lon, lat and
## extent_km in data place a row: a click on it flies the camera there. The
## panel asks again once the next monthly count is done (day 17 of a month).
##
## A click on a column head sorts by it (again: the other way round), the
## search field and the dropdowns of the text columns filter, and
## "zusammenfassen" folds the rows by the first dropdown's column, with sums,
## and shares, means ("mean" in the key) and per-unit values ("Denar/kg")
## weighted by persons. At most ROW_MAX rows are listed per level, the
## rest is counted in a last row. A table of one row without a place (the
## state) is shown as a list of its values, one per line.
##
## The history ("Verlauf", one row per month) shows each series with its
## last two months; the one picked is drawn as a curve over the months
## above the list (prices with their range).
##
## On the markets, "Karte färben" (or a map mode of the bar at the foot,
## ui/map_modes.gd, through colour_map) colours each region on the map by
## the column sorted by, in five classes (MAP_RULES: fixed bounds, people
## per area, or else equal numbers of the regions with people), regions
## without people grey, with a border where the class changes
## (ApoleiaPeople.region_map: the market of each 25 km cell;
## people_dots.gd paint_regions, sim_map.gdshaderinc sim_regions).
## The colours stay when the panel closes (it covers most of the map), with
## their legend on the bar of map modes (or at the bottom left), whose ✕
## takes them off.
##
## Command line (after --): --tables=overview|markets|goods|classes|population|farms|state|history
## (or a page of VIEWS, as grain_charts) opens the panel on that view, --tables-map=column colours the map by
## that column of the markets.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const UiWindow = preload("res://scripts/ui/ui_window.gd")
const UiTabs = preload("res://scripts/ui/ui_tabs.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const Charts = preload("res://scripts/ui/charts.gd")
const SimOverview = preload("res://scripts/sim/sim_overview.gd")
## apoleia_sim::tables::TABLES, then "overview": a page of sim_overview.gd
## (VIEWS), drawn from OVERVIEW_KINDS
const KINDS: Array[String] = ["markets", "population", "farms", "state", "history", "overview", "classes", "goods", "outside"]
const TITLES: Array[String] = ["Märkte", "Bevölkerung", "Höfe", "Staat", "Verlauf", "Übersicht", "Schichten", "Waren", "Draussen"]
const ROW_KINDS: Array[String] = ["Markt", "Berufsgruppe", "Region", "Staat", "Reihe", "", "Schicht", "Ware", "Markt draussen"] # under a tooltip's title
## The window's tabs and the views of each: [topic, [[view, page of
## sim_overview.gd or a table of KINDS], …]].
const VIEWS := [
	["Übersicht", [["Überblick", "overview"], ["Verlauf", "history"]]],
	["Menschen", [["Schichten", "people"], ["Diagramme", "people_charts"], ["Liste", "population"]]],
	["Korn", [["Diagramme", "grain_charts"], ["Märkte", "markets"], ["Draussen", "outside"]]],
	["Geld", [["Diagramme", "money_charts"], ["Schichten", "classes"]]],
	["Waren", [["Diagramme", "goods_charts"], ["Liste", "goods"]]],
	["Höfe", [["Diagramme", "farms_charts"], ["Liste", "farms"]]],
	["Staat", [["Diagramme", "state_charts"], ["Liste", "state"]]],
]
const VIEW_PX := 112.0 # a view's board
const OVERVIEW_KINDS: Array[String] = ["history", "population", "farms", "state", "classes", "goods"]
const SPARK_MONTHS := 24
const SPARK_PX := 92.0
const MONTHS: Array[String] = ["Ianuarius", "Februarius", "Martius", "Aprilis", "Maius", "Iunius",
	"Quintilis", "Sextilis", "September", "October", "November", "December"]
const YEAR := 360 # days (sim/src/life.rs)
const MONTH := 30
const COUNTED := 17 # the grain economy's monthly count is done by this day of the month
const PER_TIME: Array[String] = ["Tag", "Monat", "Jahr"] # "kg/Tag" adds up, "Denar/kg" does not
const SHORT_UNITS := {"Denar": "D", "Denar/kg": "D/kg"} # the heads stay narrow
## the HUD's older colours (game clock, events, build menu read them)
const BACKGROUND := Color("13232b")
const INK := Color("edf0e8")
const GOLD := Color("c9a45c")
const HEAD := Color("1b3440")
const SELECTED := Color("2e5260")
const SECONDARY := UiStyle.DIM
const NEGATIVE := UiStyle.LOSS # in the red, as EU5 shows it
const PANEL_MIN := 620.0
const FILTER_MAX := 64 # a text column with more values gets no dropdown
const ROW_MAX := 300
const FLY_MARGIN := 1.6 # the camera frames a place this many times its extent
const FLY_MIN_KM := 3.0
const FLY_MAX_KM := 600.0
const CHART_PX := 220.0
const NOT_SERIES: Array[String] = ["day", "year"] # the history's time, not a series
## the map's classes, few to many (pale straw to deep madder)
const CLASS_COLOURS: Array[Color] = [Color("f1e6c2"), Color("e3bf78"), Color("d08c4e"), Color("ac5637"), Color("72302a")]
const EMPTY_COLOUR := Color("6a665c") # a region without people
## How a column of the markets colours the map, where five classes of equal
## numbers would mislead: fixed bounds (most markets have no one hungry, so
## equal classes all start at 0), or people per 10’000 km² of the region,
## about one market's (a large region has more people without being denser).
## `min_persons` greys the regions with fewer people: the Gini of one or two
## people is 0 or 0.5 whatever they own.
const MAP_RULES := {
	"share_hungry": {"bounds": [0.0001, 0.05, 0.2, 0.5], "labels": ["0 %", "bis 5 %", "5–20 %", "20–50 %", "ab 50 %"]},
	"persons": {"per_km2": 10000.0, "name": "Menschen je 10’000 km²"},
	"tent_persons": {"per_km2": 10000.0, "name": "Im Zelt je 10’000 km²"},
	"price": {"name": "Kornpreis"},
	"gini": {"bounds": [0.5, 0.7, 0.8, 0.9], "labels": ["unter 0.5", "0.5–0.7", "0.7–0.8", "0.8–0.9", "ab 0.9"], "min_persons": 10},
}

var people: RefCounted
var landscape: Node3D
var open := false
var _kind := 0
var _tables: Array[Dictionary] = []
var _state: Array[Dictionary] = [] # per table: sort, desc, filters, search, folded, open groups, selected id
var _asked := -1 # the table asked for, until take_table answers
var _asked_on := PackedInt64Array() # per table: the day it was last asked for
var _win # ui_window.gd (untyped: its own members)
var _pages := {} # page -> its sim_overview.gd, made when first shown
var _page := "overview" # the page shown while _kind is "overview"
var _topic := 0
var _views: Array[UiTabs] = [] # per topic its row of views, one shown
var _span := 0 # months the charts show, 0 for all
var _spans: HBoxContainer
var _months := {} # market id -> PackedFloat64Array of its price, one per monthly count
var _months_day := -1 # the table day last added to _months
var _spark_at := -1 # the tree column of the curves, -1 for none
var _stale := false # a new table came while the mouse was on the shown one
var _tabs: UiTabs
var _stand: Label
var _search: LineEdit
var _filter_row: HFlowContainer # wraps when the window is narrow
var _fold: CheckButton
var _tree: Tree
var _note: Label
var _unit := PackedStringArray() # per column of the table shown: unit and factor shown in
var _factor := PackedFloat64Array()
var _chart: Control
var _series := "persons" # the history's curve
var _paint: CheckButton
var _legend: HBoxContainer
var _legend_box: PanelContainer
## The bar of map modes at the foot (ui/map_modes.gd, set by the game
## clock): the legend then sits on it, from its left end.
var legend_over: Control:
	set(bar):
		legend_over = bar
		bar.item_rect_changed.connect(_place_legend)
		_place_legend()
var _map_by := "" # the markets' column the map is coloured by, "" for none
var _painted := "" # column and table day last painted

## `sim` is ApoleiaPeople, `scene` the landscape whose camera a row moves.
func setup(sim: RefCounted, scene: Node3D) -> void:
	people = sim
	landscape = scene
	name = "SimTables"
	layer = 2 # over the people's labels
	_kind = KINDS.find("overview") # EU5 opens on the summary
	var start := "overview"
	for kind in KINDS:
		_asked_on.append(-1)
		_tables.append({})
		_state.append({"sort": "", "desc": true, "filters": {}, "search": "", "folded": false, "open": {}, "selected": -1})
	for arg in OS.get_cmdline_user_args():
		if arg.get_slice("=", 0) == "--tables":
			open = true
			start = arg.get_slice("=", 1)
		elif arg.get_slice("=", 0) == "--tables-map":
			_map_by = arg.get_slice("=", 1)
			_state[0].sort = _map_by
	_build()
	_terms()
	_go_to(start)
	_show(open)

# ------------------------------------------------------------------ data

func _process(_delta: float) -> void:
	# a new month waits while the mouse is on the table, so the row under it
	# (and its tooltip) stays where it is, as in EU5
	if _stale and not (_tree.visible and _tree.get_global_rect().has_point(_tree.get_global_mouse_position())):
		_stale = false
		_refresh()
	if _asked >= 0:
		var answer: Dictionary = people.take_table()
		if answer.is_empty():
			return
		_tables[_asked] = answer
		var was := _asked
		if KINDS[was] == "markets":
			_remember_months(answer)
		_asked = -1
		if open and (was == _kind or KINDS[_kind] == "overview" and KINDS[was] in OVERVIEW_KINDS):
			_stale = true
		elif was == 0:
			_paint_regions()
		return
	# the table shown (the overview's four), then the markets every month
	# for their curves and the map, open or not
	var kinds: Array[int] = [0]
	if open and KINDS[_kind] == "overview":
		kinds = []
		for k in OVERVIEW_KINDS:
			kinds.append(KINDS.find(k))
		kinds.append(0)
	elif open:
		kinds = [_kind, 0]
		if KINDS[_kind] in ["goods", "classes"]: # their rows' tooltips draw from the history
			kinds.append(KINDS.find("history"))
	var day: int = people.day()
	for kind in kinds:
		var t := _tables[kind]
		if _asked_on[kind] != day and (t.is_empty() or _count_of(day) != _count_of(int(t.day))):
			people.ask_table(KINDS[kind])
			_asked = kind
			_asked_on[kind] = day
			return

## Which monthly count a table built on `day` shows.
static func _count_of(day: int) -> int:
	return day / MONTH - (0 if day % MONTH >= COUNTED else 1)

## Each market's price of this monthly count, after the ones before.
func _remember_months(t: Dictionary) -> void:
	if int(t.day) == _months_day or not t.data.has("id") or not t.data.has("price"):
		return
	_months_day = int(t.day)
	var ids = t.data.id
	var price = t.data.price
	for r in ids.size():
		var m := int(ids[r])
		var s: PackedFloat64Array = _months.get(m, PackedFloat64Array())
		s.append(float(price[r]))
		if s.size() > SPARK_MONTHS:
			s = s.slice(s.size() - SPARK_MONTHS)
		_months[m] = s

## The rows that pass the search and the dropdowns, in table order.
func _passing(t: Dictionary) -> PackedInt32Array:
	var data: Dictionary = t.data
	var state: Dictionary = _state[_kind]
	var search: String = state.search.strip_edges().to_lower()
	var texts: Array[String] = []
	for key in t.columns:
		if _is_text(t, key):
			texts.append(key)
	var rows := PackedInt32Array()
	for r in _row_count(t):
		var ok := true
		for key in state.filters:
			if state.filters[key] != "" and data[key][r] != state.filters[key]:
				ok = false
				break
		if ok and search != "":
			ok = false
			for key in texts:
				if search in String(data[key][r]).to_lower():
					ok = true
					break
		if ok:
			rows.append(r)
	return rows

## One row and no place: shown as a list of values.
static func _is_sheet(t: Dictionary) -> bool:
	return _row_count(t) == 1 and not t.data.has("lon") and not _is_history(t)

## One row per month: shown as series.
static func _is_history(t: Dictionary) -> bool:
	return t.get("kind", "") == "history"

static func _row_count(t: Dictionary) -> int:
	var cols: PackedStringArray = t.columns
	return t.data[cols[0]].size() if cols.size() > 0 else 0

static func _is_text(t: Dictionary, key: String) -> bool:
	return t.data[key] is PackedStringArray

## The text columns that get a dropdown; rows fold by the first of them.
func _filter_keys(t: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	if _row_count(t) <= 12: # a short table needs no dropdowns
		return keys
	for key in t.columns:
		if _is_text(t, key) and _values(t, key).size() <= FILTER_MAX:
			keys.append(key)
	return keys

static func _values(t: Dictionary, key: String) -> PackedStringArray:
	var seen := {}
	for v in t.data[key]:
		seen[v] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out

## Whether rows of column i combine to a mean (weighted by persons) rather
## than a sum.
static func _is_mean(t: Dictionary, i: int) -> bool:
	var unit: String = t.units[i]
	if unit == "%" or "mean" in t.columns[i]:
		return true
	return "/" in unit and not unit.get_slice("/", 1) in PER_TIME

static func _combine(t: Dictionary, i: int, rows: PackedInt32Array) -> float:
	var col = t.data[t.columns[i]]
	if _is_mean(t, i):
		var weights = t.data.get("persons", null)
		var sum := 0.0
		var weight := 0.0
		for r in rows:
			var w := float(weights[r]) if weights != null else 1.0
			sum += float(col[r]) * w
			weight += w
		return sum / weight if weight > 0.0 else 0.0
	var total := 0.0
	for r in rows:
		total += float(col[r])
	return total

func _sorted(t: Dictionary, rows: PackedInt32Array) -> PackedInt32Array:
	var key: String = _state[_kind].sort
	if key == "" or not t.data.has(key):
		return rows
	var col = t.data[key]
	var desc: bool = _state[_kind].desc
	var order := Array(rows)
	order.sort_custom(func(a, b): return col[a] > col[b] if desc else col[a] < col[b])
	return PackedInt32Array(order)

# ------------------------------------------------------------------ view

func _refresh() -> void:
	var overview := KINDS[_kind] == "overview"
	var page = _page_node(_page) if overview else null
	for p in _pages.values():
		p.visible = p == page
	_filter_row.visible = not overview # a page has no search, dropdowns or map
	_spans.visible = overview and _page.ends_with("charts")
	_tree.visible = not overview
	_note.visible = not overview
	if overview:
		_chart.visible = false
		var shown := {}
		for k in OVERVIEW_KINDS:
			shown[k] = _tables[KINDS.find(k)]
		page.show_tables(shown)
		var h: Dictionary = shown.history
		_stand.text = ("Stand %s" % _date(int(h.day))) if not h.is_empty() else "…"
		return
	var t := _tables[_kind]
	_chart.visible = KINDS[_kind] == "history"
	_note.text = ("Klick auf eine Reihe zeichnet ihre Kurve  ·  auf ihr verweilen zeigt den Verlauf" if KINDS[_kind] == "history"
		else "Auf einer Zeile verweilen zeigt mehr  ·  Klick zeigt den Ort  ·  Spaltenkopf sortiert  ·  D = Denar" if t.get("data", {}).has("lon")
		else "Auf einer Zeile verweilen zeigt mehr  ·  Spaltenkopf sortiert  ·  D = Denar")
	_paint.visible = KINDS[_kind] == "markets"
	_paint.set_pressed_no_signal(_map_by != "")
	_paint_regions()
	if t.is_empty():
		_tree.clear()
		_stand.text = "…"
		return
	_stand.text = "Stand %s" % _date(int(t.day))
	if _state[_kind].sort == "" and t.data.has("persons"):
		_state[_kind].sort = "persons" # the largest first, as EU5 lists them
	_fill_filters(t)
	_fill_tree(t)

func _fill_filters(t: Dictionary) -> void:
	for child in _filter_row.get_children():
		if child is OptionButton:
			child.queue_free()
	var state: Dictionary = _state[_kind]
	var keys: Array[String] = []
	if not _is_sheet(t) and not _is_history(t):
		keys = _filter_keys(t)
	_search.visible = not _is_sheet(t) and not _is_history(t)
	var at := _search.get_index() + 1
	for key in keys:
		var pick := OptionButton.new()
		pick.add_item("%s: alle" % t.labels[Array(t.columns).find(key)])
		var values := _values(t, key)
		for v in values:
			pick.add_item(v)
			if v == state.filters.get(key, ""):
				pick.select(pick.item_count - 1)
		pick.item_selected.connect(func(index: int):
			state.filters[key] = "" if index == 0 else values[index - 1]
			_fill_tree(_tables[_kind]))
		pick.focus_mode = Control.FOCUS_NONE
		# as wide as its name, not its longest value, so the row fits the window
		pick.fit_to_longest_item = false
		pick.clip_text = true
		pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		pick.custom_minimum_size = Vector2(120, 0)
		_filter_row.add_child(pick)
		_filter_row.move_child(pick, at)
		at += 1
	_fold.visible = keys.size() > 0
	if _fold.visible:
		_fold.text = "nach %s zusammenfassen" % t.labels[Array(t.columns).find(keys[0])]
		_fold.set_pressed_no_signal(state.folded)
	_search.set_block_signals(true)
	_search.text = state.search
	_search.set_block_signals(false)
	_place_panel()

func _fill_tree(t: Dictionary) -> void:
	_spark_at = -1
	if _is_sheet(t):
		_fill_sheet(t)
		return
	if _is_history(t):
		_fill_history(t)
		return
	var cols: PackedStringArray = t.columns
	var state: Dictionary = _state[_kind]
	_prepare_units(t)
	var scroll := _scroll_bar()
	var at := scroll.value if scroll != null else 0.0
	_tree.set_block_signals(true) # selecting the chosen row again must not fly
	_tree.clear()
	_spark_at = Array(cols).find("price") + 1 if _has_spark(t) else -1
	_tree.columns = cols.size() + (1 if _spark_at >= 0 else 0)
	if _spark_at >= 0: # the price's last months, right after the price
		_tree.set_column_title(_spark_at, "%d Monate" % SPARK_MONTHS)
		_tree.set_column_title_alignment(_spark_at, HORIZONTAL_ALIGNMENT_CENTER)
		_tree.set_column_expand(_spark_at, false)
		_tree.set_column_clip_content(_spark_at, true)
		_tree.set_column_custom_minimum_width(_spark_at, int(SPARK_PX + 16.0))
	for d in cols.size():
		var i := _tc(d)
		var number := not _is_text(t, cols[d])
		var title: String = t.labels[d]
		if _unit[d] != "" and _unit[d] != "%":
			title += " (%s)" % _unit[d]
		if cols[d] == state.sort:
			title += "  ▼" if state.desc else "  ▲"
		_tree.set_column_title(i, title)
		_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT if number else HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_expand(i, not number) # numbers as wide as they need, names the rest
		_tree.set_column_clip_content(i, not number)
		_tree.set_column_custom_minimum_width(i, 0 if number else 150)
	var root := _tree.create_item()
	var rows := _passing(t)
	var keys := _filter_keys(t)
	var fold_key := keys[0] if state.folded and keys.size() > 0 else ""
	var total := _tree.create_item(root)
	_fill_combined(total, t, rows, {cols[0]: "Alle (%s)" % _int(rows.size())})
	var font := _tree.get_theme_font("font")
	var font_size := _tree.get_theme_font_size("font_size")
	for d in cols.size():
		var i := _tc(d)
		if total.get_custom_color(i) != NEGATIVE:
			total.set_custom_color(i, UiStyle.NAME)
		if not _is_text(t, cols[d]): # the sum is often the widest number
			_tree.set_column_custom_minimum_width(i, ceili(font.get_string_size(total.get_text(i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 20)
	if fold_key == "":
		_fill_rows(root, t, _sorted(t, rows))
	else:
		var groups := {}
		for r in rows:
			var v: String = t.data[fold_key][r]
			if not groups.has(v):
				groups[v] = PackedInt32Array()
			groups[v].append(r)
		var names := groups.keys()
		var sort_i := Array(cols).find(state.sort)
		if sort_i >= 0 and not _is_text(t, state.sort):
			var value := {}
			for g in names:
				value[g] = _combine(t, sort_i, groups[g])
			names.sort_custom(func(a, b): return value[a] > value[b] if state.desc else value[a] < value[b])
		else:
			names.sort()
			if state.sort == fold_key and state.desc:
				names.reverse()
		var line := 0
		for g in names:
			var item := _tree.create_item(root)
			_fill_combined(item, t, groups[g], {fold_key: "%s (%s)" % [g, _int(groups[g].size())]})
			item.set_meta("group", g)
			_stripe(item, line)
			line += 1
			if state.open.has(g):
				_fill_rows(item, t, _sorted(t, groups[g]))
			else:
				_tree.create_item(item) # a stand-in, so the group shows its arrow
				item.collapsed = true
	_tree.set_block_signals(false)
	if scroll != null:
		(func(): scroll.value = at).call_deferred() # once the tree has its new height

## A one-row table as a list: what, how much.
func _fill_sheet(t: Dictionary) -> void:
	var cols: PackedStringArray = t.columns
	_prepare_units(t)
	_tree.clear()
	_tree.columns = 2
	_tree.set_column_title(0, "Posten")
	_tree.set_column_title(1, "Betrag")
	_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	_tree.set_column_expand_ratio(0, 2)
	_tree.set_column_expand_ratio(1, 1)
	var root := _tree.create_item()
	for i in cols.size():
		var item := _tree.create_item(root)
		var unit: String = t.units[i]
		item.set_text(0, t.labels[i])
		if _is_text(t, cols[i]):
			item.set_text(1, t.data[cols[i]][0])
		else:
			_set_number(item, 1, float(t.data[cols[i]][0]) * _factor[i], _unit[i])
			if unit != "" and unit != "%":
				item.set_text(1, item.get_text(1) + " " + (unit if _factor[i] == 1.0 else _unit[i]))
		item.set_selectable(0, false)
		item.set_selectable(1, false)
		_stripe(item, i)

## The history as series: what, the last month, the one before and the
## change; the series picked is the curve above.
func _fill_history(t: Dictionary) -> void:
	var cols: PackedStringArray = t.columns
	var data: Dictionary = t.data
	_prepare_units(t)
	var n := _row_count(t)
	_tree.set_block_signals(true)
	_tree.clear()
	_tree.columns = 4
	var heads := ["Posten", _short_date(int(data.day[n - 1])) if n > 0 else "", _short_date(int(data.day[n - 2])) if n > 1 else "", "Veränderung"]
	for i in 4:
		_tree.set_column_title(i, heads[i])
		_tree.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		_tree.set_column_expand(i, i == 0)
		_tree.set_column_clip_content(i, i == 0)
		_tree.set_column_custom_minimum_width(i, 0 if i == 0 else 110)
	var root := _tree.create_item()
	var line := 0
	for i in cols.size():
		if cols[i] in NOT_SERIES or _is_text(t, cols[i]):
			continue
		var item := _tree.create_item(root)
		item.set_meta("series", cols[i])
		var label: String = t.labels[i]
		if _unit[i] != "" and _unit[i] != "%":
			label += " (%s)" % _unit[i]
		item.set_text(0, label)
		if n > 0:
			_set_number(item, 1, float(data[cols[i]][n - 1]) * _factor[i], _unit[i])
		if n > 1:
			var now := float(data[cols[i]][n - 1])
			var before := float(data[cols[i]][n - 2])
			_set_number(item, 2, before * _factor[i], _unit[i])
			item.set_text_alignment(3, HORIZONTAL_ALIGNMENT_RIGHT)
			if t.units[i] == "%":
				item.set_text(3, "%+d Pkt." % roundi((now - before) * 100.0))
			elif before != 0.0:
				item.set_text(3, "%+d %%" % roundi((now - before) / absf(before) * 100.0))
			item.set_custom_color(3, SECONDARY)
		_stripe(item, line)
		line += 1
		if cols[i] == _series:
			item.select(0)
	_tree.set_block_signals(false)
	_chart.queue_redraw()

## "Mar. J3": a month in a column head.
static func _short_date(day: int) -> String:
	return "%s. J%d" % [MONTHS[(day % YEAR) / MONTH].left(3), day / YEAR + 1]

## The series picked as a curve over the months, with the range of the
## prices around their median.
func _draw_chart() -> void:
	var t := _tables[_kind]
	var rect := Rect2(Vector2.ZERO, _chart.size)
	Charts.board(_chart, rect)
	if t.is_empty() or not _is_history(t):
		return
	var data: Dictionary = t.data
	var cols := Array(t.columns)
	var key := _series if data.has(_series) else "persons"
	var i := cols.find(key)
	if i < 0:
		return
	var keys: Array[String] = [key]
	if key.begins_with("price_"):
		keys = ["price_min", "price_median", "price_max"]
	var font := _chart.get_theme_default_font()
	var title: String = t.labels[i]
	if _unit.size() > i and _unit[i] != "" and _unit[i] != "%":
		title += " (%s)" % _unit[i]
	if keys.size() > 1:
		title = "Preis: Median, dazwischen min und max (%s)" % _unit[i]
	UiStyle.text_at(_chart, Vector2(12, 24), title, UiStyle.TITLE, UiStyle.SIZE_HEAD, HORIZONTAL_ALIGNMENT_LEFT, -1, font)
	var n := _row_count(t)
	if n < 2:
		UiStyle.text_at(_chart, Vector2(12, 50), "Noch zu wenige Monate", UiStyle.DIM, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.italic())
		return
	var scale := (100.0 if t.units[i] == "%" else 1.0) * (_factor[i] if _factor.size() > i else 1.0)
	var lo := INF
	var hi := -INF
	for v in data["price_median" if keys.size() > 1 else key]:
		lo = minf(lo, float(v) * scale)
		hi = maxf(hi, float(v) * scale)
	var band_lo := PackedFloat64Array()
	var band_hi := PackedFloat64Array()
	if keys.size() > 1: # the band, at most BAND_REACH times the month's median
		for r in n:
			var m := float(data.price_median[r]) * scale
			band_lo.append(maxf(float(data.price_min[r]) * scale, m / Charts.BAND_REACH))
			band_hi.append(minf(float(data.price_max[r]) * scale, m * Charts.BAND_REACH))
			lo = minf(lo, band_lo[r])
			hi = maxf(hi, band_hi[r])
	if lo >= 0.0 and lo < hi * 0.5:
		lo = 0.0 # counts from nothing
	if hi - lo < 1e-9:
		hi = lo + 1.0
	var plot := Rect2(70, 36, rect.size.x - 90, rect.size.y - 62)
	var y_of := func(v: float) -> float: return plot.end.y - (v - lo) / (hi - lo) * plot.size.y
	var x_of := func(r: int) -> float: return plot.position.x + plot.size.x * float(r) / float(n - 1)
	for g in 5:
		var v := lo + (hi - lo) * g / 4.0
		var y: float = y_of.call(v)
		var tag := ("%d %%" % roundi(v)) if t.units[i] == "%" else _number(v)
		UiStyle.text_at(_chart, Vector2(8, y + 5), tag, UiStyle.TEXT, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT, 56, font)
	var days = data.day
	for r in n: # the years along the foot
		if r == 0 or int(days[r]) / YEAR != int(days[r - 1]) / YEAR:
			var x: float = x_of.call(r)
			UiStyle.text_at(_chart, Vector2(x + 3, plot.end.y + 18), "Jahr %d" % (int(days[r]) / YEAR + 1), UiStyle.TEXT, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.italic())
	if keys.size() > 1: # the range of the prices as a band
		var band := PackedVector2Array()
		for r in n:
			band.append(Vector2(x_of.call(r), y_of.call(band_hi[r])))
		for r in range(n - 1, -1, -1):
			band.append(Vector2(x_of.call(r), y_of.call(band_lo[r])))
		if Geometry2D.triangulate_polygon(band).size() > 0:
			_chart.draw_colored_polygon(band, Color(Charts.SERIES[0], 0.2))
	var main := "price_median" if keys.size() > 1 else key
	var points := PackedVector2Array()
	for r in n:
		points.append(Vector2(x_of.call(r), y_of.call(float(data[main][r]) * scale)))
	_chart.draw_polyline(points, Color(0, 0, 0, 0.45), 4.5, true)
	_chart.draw_polyline(points, Charts.SERIES[0], 2.5, true)
	var last := points[n - 1]
	_chart.draw_circle(last, 3.5, Charts.SERIES[0])

## Lists `rows` under `parent`, at most ROW_MAX of them.
func _fill_rows(parent: TreeItem, t: Dictionary, rows: PackedInt32Array) -> void:
	var cols: PackedStringArray = t.columns
	var chosen: int = _state[_kind].selected
	for n in mini(rows.size(), ROW_MAX):
		var r := rows[n]
		var item := _tree.create_item(parent)
		item.set_meta("rows", PackedInt32Array([r]))
		for i in cols.size():
			if _is_text(t, cols[i]):
				item.set_text(_tc(i), t.data[cols[i]][r])
			else:
				_set_number(item, _tc(i), float(t.data[cols[i]][r]) * _factor[i], _unit[i])
		if _spark_at >= 0:
			item.set_cell_mode(_spark_at, TreeItem.CELL_MODE_CUSTOM)
			item.set_metadata(_spark_at, int(t.data.id[r]))
			item.set_custom_draw_callback(_spark_at, _draw_spark)
		if parent == _tree.get_root():
			_stripe(item, n)
		if t.data.has("id") and int(t.data.id[r]) == chosen:
			item.select(0)
	if rows.size() > ROW_MAX:
		var more := _tree.create_item(parent)
		more.set_text(0, "… und %s weitere (suchen oder filtern)" % _int(rows.size() - ROW_MAX))
		more.set_custom_color(0, SECONDARY)
		more.set_selectable(0, false)
		for i in range(1, cols.size()):
			more.set_selectable(i, false)

## A row standing for many: `names` gives the text of text columns by key.
func _fill_combined(item: TreeItem, t: Dictionary, rows: PackedInt32Array, names: Dictionary) -> void:
	var cols: PackedStringArray = t.columns
	item.set_meta("rows", rows)
	for i in cols.size():
		if _is_text(t, cols[i]):
			item.set_text(_tc(i), names.get(cols[i], ""))
		else:
			_set_number(item, _tc(i), _combine(t, i, rows) * _factor[i], _unit[i])

## The unit each column is shown in: kg as t where the numbers run large,
## Denar as D.
func _prepare_units(t: Dictionary) -> void:
	_unit = PackedStringArray()
	_factor = PackedFloat64Array()
	for i in t.columns.size():
		var unit: String = t.units[i]
		var factor := 1.0
		if unit.begins_with("kg") and not _is_text(t, t.columns[i]):
			var top := 0.0
			for v in t.data[t.columns[i]]:
				top = maxf(top, absf(float(v)))
			if top >= 10000.0:
				unit = "t" + unit.substr(2)
				factor = 0.001
		_unit.append(SHORT_UNITS.get(unit, unit))
		_factor.append(factor)

func _set_number(item: TreeItem, i: int, v: float, unit: String) -> void:
	item.set_text_alignment(i, HORIZONTAL_ALIGNMENT_RIGHT)
	if unit == "%":
		item.set_cell_mode(i, TreeItem.CELL_MODE_CUSTOM)
		item.set_metadata(i, v)
		item.set_custom_draw_callback(i, _draw_share.bind(i))
		item.set_text(i, "%d %%" % roundi(v * 100.0))
	else:
		item.set_text(i, _number(v))
		if v < 0.0:
			item.set_custom_color(i, NEGATIVE)

func _stripe(item: TreeItem, line: int) -> void:
	# EU5's lists: warm grey bars on the navy, every other a shade darker
	for i in _tree.columns:
		item.set_custom_bg_color(i, UiStyle.ROW if line % 2 == 0 else UiStyle.ROW_DARK)

## A share's bar along the foot of its cell, under the per cent: red for
## what is bad (the hungry), bronze for the rest.
func _draw_share(item: TreeItem, rect: Rect2, column: int) -> void:
	var t := _tables[_kind]
	var d := _dc(column)
	var key: String = t.columns[d] if not t.is_empty() and d >= 0 and d < t.columns.size() else ""
	var colour := Charts.RED if "hungry" in key else UiStyle.FRAME_LIT
	Charts.share(_tree, Rect2(rect.position.x + 8.0, rect.position.y, rect.size.x - 14.0, rect.size.y - 1.0), float(item.get_metadata(column)), colour)

## The tree column of the table's column d, and back (-1: the curves).
func _tc(d: int) -> int:
	return d + 1 if _spark_at >= 0 and d >= _spark_at else d

func _dc(c: int) -> int:
	if _spark_at < 0 or c < _spark_at:
		return c
	return -1 if c == _spark_at else c - 1

## The markets get their price's last months as a curve.
static func _has_spark(t: Dictionary) -> bool:
	return t.get("kind", "") == "markets" and t.data.has("id")

func _draw_spark(item: TreeItem, rect: Rect2) -> void:
	var s: PackedFloat64Array = _months.get(int(item.get_metadata(_spark_at)), PackedFloat64Array())
	Charts.spark(_tree, Rect2(rect.position + Vector2(8, 6), rect.size - Vector2(16, 12)), s, Charts.SERIES[0])

func _scroll_bar() -> VScrollBar:
	for child in _tree.get_children(true):
		if child is VScrollBar:
			return child
	return null

## Swiss style: 116’805, 12.5, 3.4 Mio.
static func _number(v: float) -> String:
	var a := absf(v)
	if a >= 1.0e6:
		return "%.1f Mio" % (v / 1.0e6)
	if a >= 100.0 or is_equal_approx(v, roundf(v)):
		return _int(roundi(v))
	return ("%.1f" % v) if a >= 10.0 else ("%.2f" % v)

static func _int(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "’" + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out

static func _date(day: int) -> String:
	return "%s, Jahr %d" % [MONTHS[(day % YEAR) / MONTH], day / YEAR + 1]

# ------------------------------------------------------------------ tooltips

## The row under the mouse as an EU5 tooltip: every number of the row,
## and once locked the market's price over its last months.
func _row_tip(at: Vector2) -> Dictionary:
	var t := _tables[_kind]
	var item := _tree.get_item_at_position(at)
	if t.is_empty() or item == null:
		return {}
	var cols: PackedStringArray = t.columns
	if item.has_meta("series"):
		return _series_tip(t, item.get_meta("series"))
	if not item.has_meta("rows") or _is_sheet(t):
		return {}
	var rows: PackedInt32Array = item.get_meta("rows")
	var d := {"id": "%d:%s" % [_kind, item.get_text(0)], "title": item.get_text(0).strip_edges(),
		"kind": ROW_KINDS[_kind] if rows.size() == 1 else "%s, %s zusammen" % [TITLES[_kind], _int(rows.size())],
		"rows": [], "hints": []}
	for i in cols.size():
		if _is_text(t, cols[i]) or i == 0:
			continue
		var label: String = t.labels[i]
		if _unit[i] != "" and _unit[i] != "%":
			label += " (%s)" % _unit[i]
		var colour := Charts.RED if "hungry" in cols[i] and _combine(t, i, rows) > 0.05 else UiStyle.TEXT
		d.rows.append([label, item.get_text(_tc(i)), colour])
	if KINDS[_kind] == "markets" and rows.size() == 1 and t.data.has("id"):
		var m := int(t.data.id[rows[0]])
		d.text = "Die Händler verkaufen Korn zum [url=price]Preis[/url] von [n]%s D/kg[/n]; ihr [url=store]Lager[/url] reicht für %s." % [
			_number(float(t.data.price[rows[0]])), _days_of_store(t, rows[0])]
		var s: PackedFloat64Array = _months.get(m, PackedFloat64Array())
		if s.size() > 1:
			d.spark = s
			d.spark_title = "Preis der letzten Monate"
			d.spark_unit = "D"
			d.spark_from = "vor %d Monaten" % (s.size() - 1)
			d.spark_to = _date(int(t.day))
		else:
			d.more = "Der Verlauf füllt sich mit jedem Monat, den das Spiel läuft."
	if KINDS[_kind] in ["goods", "classes"] and rows.size() == 1:
		_history_spark(d, KINDS[_kind], int(t.data.id[rows[0]]))
	if t.data.has("lon"):
		d.hints.append(["Klick", "fliegt zum Ort"])
	return d

## A good's price, or what a class ate of its need, over all months from
## the history (good_<key>, fed_<key> in apoleia_sim grain/tables.rs).
func _history_spark(d: Dictionary, kind: String, id: int) -> void:
	var h := _tables[KINDS.find("history")]
	var keys: Array[String] = SimOverview.GOOD_KEYS if kind == "goods" else SimOverview.FED_KEYS
	if h.is_empty() or id < 0 or id >= keys.size():
		return
	var key := ("good_" if kind == "goods" else "fed_") + keys[id]
	if not h.data.has(key) or h.data[key].size() < 2:
		d.more = "Der Verlauf füllt sich mit jedem Monat, den das Spiel läuft."
		return
	var s := PackedFloat64Array()
	for v in h.data[key]:
		s.append(float(v) * (1.0 if kind == "goods" else 100.0))
	d.spark = s
	d.spark_title = "Preis seit Beginn" if kind == "goods" else "Gegessen vom Bedarf, je Monat"
	d.spark_unit = "D" if kind == "goods" else "%"
	d.spark_from = _date(int(h.data.day[0]))
	d.spark_to = _date(int(h.data.day[h.data.day.size() - 1]))
	d.colour = Charts.SERIES[0] if kind == "goods" else SimOverview.FED_COLOURS[id]

## A series of the history: its whole course, prices with their range.
func _series_tip(t: Dictionary, key: String) -> Dictionary:
	var i := Array(t.columns).find(key)
	if i < 0:
		return {}
	var data: Dictionary = t.data
	var n := _row_count(t)
	var scale := (100.0 if t.units[i] == "%" else 1.0) * _factor[i]
	var s := PackedFloat64Array()
	for r in n:
		s.append(float(data[key][r]) * scale)
	var d := {"id": "series:" + key, "title": t.labels[i], "kind": "Verlauf", "spark": s,
		"spark_title": "Alle Monate seit Beginn", "spark_unit": "" if t.units[i] == "%" else " " + _unit[i],
		"colour": Charts.RED if "hunger" in key else Charts.SERIES[0], "rows": []}
	if key.begins_with("price_"):
		var lo := PackedFloat64Array()
		var hi := PackedFloat64Array()
		var mid := PackedFloat64Array()
		for r in n:
			lo.append(float(data.price_min[r]))
			hi.append(float(data.price_max[r]))
			mid.append(float(data.price_median[r]))
		d.spark = mid
		d.spark_lo = lo
		d.spark_hi = hi
		d.title = "Kornpreis"
		d.text = "Der Median der Märkte, im Band zwischen dem billigsten und dem teuersten [url=price]Preis[/url]."
	if n > 0:
		d.spark_from = _date(int(data.day[0]))
		d.spark_to = _date(int(data.day[n - 1]))
	if n > 1:
		d.rows.append([_short_date(int(data.day[n - 1])), _number(float(data[key][n - 1]) * scale)])
		d.rows.append([_short_date(int(data.day[n - 2])), _number(float(data[key][n - 2]) * scale)])
	d.hints = [["Klick", "zeichnet die Kurve oben"]]
	return d

## How long a market's store lasts at its sales, in days or months.
static func _days_of_store(t: Dictionary, r: int) -> String:
	if not t.data.has("store_kg") or not t.data.has("sales_day"):
		return "?"
	var sales := float(t.data.sales_day[r]) # kg a day
	var store := float(t.data.store_kg[r])
	if sales <= 0.0:
		return "lange"
	var days := store / sales
	return ("%d Tage" % roundi(days)) if days < 60.0 else ("%d Monate" % roundi(days / MONTH))

## The terms the tooltips explain in blue.
func _terms() -> void:
	Tooltips.term("price", func() -> Dictionary: return {"title": "Kornpreis", "kind": "Markt",
		"text": "Jeder Markt hat seinen eigenen Preis. Er steigt, wenn das [url=store]Lager[/url] der Händler für weniger Tage reicht, und sinkt, wenn es wächst. Gezahlt wird in [url=denar]Denar[/url]."})
	Tooltips.term("store", func() -> Dictionary: return {"title": "Lager", "kind": "Markt",
		"text": "Korn, das die Händler eines Marktes halten. Sie kaufen es den Höfen ab und verkaufen es an die Haushalte und andere Märkte."})
	Tooltips.term("denar", func() -> Dictionary: return {"title": "Denar", "kind": "Geld",
		"text": "Die Münze des Spiels, wie im Höchstpreisedikt Diokletians von 301 n. Chr. Die Staatskasse prägt sie und zahlt damit Soldaten, Beamte und Bauarbeiten."})

# ------------------------------------------------------------------ input

func _on_title(column: int, _button: int) -> void:
	var t := _tables[_kind]
	if t.is_empty():
		return
	column = _dc(column)
	if column < 0 or column >= t.columns.size():
		return # the curves do not sort
	var key: String = t.columns[column]
	var state: Dictionary = _state[_kind]
	if state.sort == key:
		state.desc = not state.desc
	else:
		state.sort = key
		state.desc = not _is_text(t, key) # numbers largest first, names A to Z
	if _map_by != "" and KINDS[_kind] == "markets" and not _is_text(t, key):
		_map_by = key
		_paint_regions()
	_fill_tree(t)

func _on_selected() -> void:
	var item := _tree.get_selected()
	var t := _tables[_kind]
	if item != null and item.has_meta("series"):
		_series = item.get_meta("series")
		_chart.queue_redraw()
		return
	if item == null or t.is_empty() or not item.has_meta("rows"):
		return
	var rows: PackedInt32Array = item.get_meta("rows")
	if rows.size() == 1 and t.data.has("id"):
		_state[_kind].selected = int(t.data.id[rows[0]])
	_fly(t, rows)

## A group opened the first time gets its rows; the state keeps it open
## across the monthly refresh.
func _on_collapsed(item: TreeItem) -> void:
	if not item.has_meta("group"):
		return
	var g: String = item.get_meta("group")
	var state: Dictionary = _state[_kind]
	if item.collapsed:
		state.open.erase(g)
		return
	state.open[g] = true
	var first := item.get_first_child()
	if first != null and not first.has_meta("rows"):
		first.free()
		var t := _tables[_kind]
		_tree.set_block_signals(true)
		_fill_rows(item, t, _sorted(t, item.get_meta("rows")))
		_tree.set_block_signals(false)

## Moves the camera onto the rows' places, framed by their extent, into the
## middle of the part of the window the panel leaves free.
func _fly(t: Dictionary, rows: PackedInt32Array) -> void:
	var data: Dictionary = t.data
	if landscape == null or rows.is_empty() or not (data.has("lon") and data.has("lat")):
		return
	var lo := Vector2(INF, INF)
	var hi := -lo
	var reach := 0.0
	for r in rows:
		var p: Vector2 = landscape.lonlat_to_world(float(data.lon[r]), float(data.lat[r]))
		lo = lo.min(p)
		hi = hi.max(p)
		if data.has("extent_km"):
			reach = maxf(reach, float(data.extent_km[r]))
	var screen := maxf(get_viewport().get_visible_rect().size.x, 1.0)
	var covered: float = _win.size.x if open and _win.position.x < screen * 0.5 else 0.0 # a window at the left
	var free := maxf(screen - covered, screen * 0.25)
	var w := clampf(maxf(maxf(hi.x - lo.x, hi.y - lo.y), reach) * FLY_MARGIN * screen / free, FLY_MIN_KM, FLY_MAX_KM)
	var centre := (lo + hi) * 0.5
	centre.x -= w * (covered * 0.5) / screen
	landscape._goal_target = centre
	landscape._goal_width = w
	print(JSON.stringify({"event": "tables_fly", "kind": KINDS[_kind], "rows": rows.size(), "width_km": w}))

## A topic: its row of views, the one last chosen in it.
func _on_tab(index: int) -> void:
	_topic = index
	for k in _views.size():
		_views[k].visible = k == index
	_on_view(_views[index].current_tab)

## A view of the topic shown: a page of cards or a table.
func _on_view(index: int) -> void:
	var to: String = VIEWS[_topic][1][index][1]
	if to in KINDS and to != "overview":
		_kind = KINDS.find(to)
	else:
		_kind = KINDS.find("overview")
		_page = to
	if open:
		_refresh()

## The view showing `to` (a page, or a table of KINDS), as a click on a line
## of the Lage asks.
func _go_to(to: String) -> void:
	for t in VIEWS.size():
		for v in VIEWS[t][1].size():
			if VIEWS[t][1][v][1] == to:
				_views[t].set_block_signals(true)
				_views[t].current_tab = v
				_views[t].set_block_signals(false)
				_tabs.set_block_signals(true)
				_tabs.current_tab = t
				_tabs.set_block_signals(false)
				_on_tab(t)
				return
	if to != "overview":
		_go_to("overview")

## Page `name` of sim_overview.gd, made the first time it is shown, above
## the tables.
func _page_node(name: String) -> SimOverview:
	if not _pages.has(name):
		var page := SimOverview.new(_date, name)
		page.visible = false
		page.set_span(_span)
		page.go.connect(_go_to)
		_tree.add_sibling(page)
		_tree.get_parent().move_child(page, _tree.get_index())
		_pages[name] = page
	return _pages[name]

func _show(on: bool) -> void:
	open = on
	if on:
		_win.open()
	elif _win.visible:
		_win.close()
	if on:
		_refresh()
	else:
		_place_legend()
		if _search.has_focus():
			_search.release_focus()

# ------------------------------------------------------------------ map

## Colours the map by the markets' column `column` ("" clears it), as a
## map mode of the bar at the foot does (ui/map_modes.gd).
func colour_map(column: String) -> void:
	_map_by = column
	_paint.set_pressed_no_signal(column != "")
	_paint_regions()

## The column the map is coloured by, "" for none.
func map_column() -> String:
	return _map_by

## Colours the regions by the markets' column `_map_by`, or clears them.
func _paint_regions() -> void:
	var t := _tables[0]
	var sim_view := get_parent()
	if sim_view == null or not sim_view.has_method("paint_regions"):
		return
	var on: bool = _map_by != "" and not t.is_empty() and t.data.has(_map_by) and t.data.has("id")
	_legend_box.visible = on
	if not on:
		if _painted != "":
			sim_view.paint_regions(null, {})
			_painted = ""
		return
	var stamp := "%s@%d" % [_map_by, int(t.day)]
	if stamp == _painted:
		return
	var grid: Dictionary = people.region_map()
	var cells: PackedInt32Array = grid.get("cells", PackedInt32Array())
	var rows: int = grid.get("rows", 0)
	var cols: int = grid.get("cols", 0)
	if cells.size() != rows * cols or rows == 0:
		return
	var rule: Dictionary = MAP_RULES.get(_map_by, {})
	var area := {} # market -> km² of its cells
	if rule.has("per_km2"):
		var cell_km2: float = pow(float(grid.get("cell_km", 25.0)), 2.0)
		for m in cells:
			if m >= 0:
				area[m] = area.get(m, 0.0) + cell_km2
	# the value of each market with people; the others stay grey
	var value := {}
	var ids = t.data.id
	var col = t.data[_map_by]
	var persons = t.data.get("persons", [])
	var sorted := PackedFloat64Array()
	for r in ids.size():
		if r < persons.size() and float(persons[r]) < maxf(rule.get("min_persons", 0), 0.5):
			continue
		var m := int(ids[r])
		var v := float(col[r])
		if rule.has("per_km2"):
			v = v / maxf(area.get(m, 0.0), 1.0) * float(rule.per_km2)
		value[m] = v
		sorted.append(v)
	if sorted.is_empty():
		return
	sorted.sort()
	var bounds := PackedFloat64Array()
	if rule.has("bounds"):
		bounds = PackedFloat64Array(rule.bounds)
	else: # five classes of as many regions each
		for k in range(1, CLASS_COLOURS.size()):
			bounds.append(sorted[mini(sorted.size() * k / CLASS_COLOURS.size(), sorted.size() - 1)])
	var class_of := {} # market -> class, -1 grey
	for m in value:
		class_of[m] = bounds.bsearch(value[m], false)
	var img := Image.create_empty(cols, rows, false, Image.FORMAT_RGBA8)
	for r in rows:
		for c in cols:
			var m := cells[r * cols + c]
			if m < 0:
				continue
			var k: int = class_of.get(m, -1)
			var colour: Color = CLASS_COLOURS[k] if k >= 0 else EMPTY_COLOUR
			# alpha: bit 0 coloured, bits 1-4 a border to the north, east,
			# south and west (another class or the sea)
			var bits := 1
			var nb := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
			for s in 4:
				var rr: int = r + nb[s].y
				var cc: int = c + nb[s].x
				var other := cells[rr * cols + cc] if rr >= 0 and rr < rows and cc >= 0 and cc < cols else -1
				if other < 0 or class_of.get(other, -1) != k:
					bits |= 2 << s
			colour.a8 = bits
			img.set_pixel(c, r, colour)
	sim_view.paint_regions(img, grid)
	_painted = stamp
	_fill_legend(t, bounds, rule)

## Five swatches with the bounds of their classes, and grey for the
## regions without people.
func _fill_legend(t: Dictionary, bounds: PackedFloat64Array, rule: Dictionary) -> void:
	for child in _legend.get_children():
		child.free()
	_legend_box.reset_size.call_deferred() # shrinks to a shorter legend
	var i := Array(t.columns).find(_map_by)
	var unit: String = "" if rule.has("per_km2") else SHORT_UNITS.get(t.units[i], t.units[i])
	var tag := Label.new()
	tag.text = rule.get("name", t.labels[i])
	if legend_over == null: # else the bar of map modes below names the map
		tag.text = "Karte: " + tag.text
	tag.add_theme_color_override("font_color", UiStyle.NAME)
	_legend.add_child(tag)
	if unit != "" and unit != "%":
		var u := Label.new()
		u.text = "in %s" % unit
		u.add_theme_color_override("font_color", SECONDARY)
		_legend.add_child(u)
	var share := unit == "%"
	var fmt := func(v: float) -> String: return ("%d %%" % roundi(v * 100.0)) if share else _number(v)
	for k in CLASS_COLOURS.size() + 1:
		var swatch := ColorRect.new()
		swatch.color = CLASS_COLOURS[k] if k < CLASS_COLOURS.size() else EMPTY_COLOUR
		swatch.custom_minimum_size = Vector2(18, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_legend.add_child(swatch)
		var text := Label.new()
		if k == CLASS_COLOURS.size():
			text.text = ("unter %d Menschen" % rule.min_persons) if rule.has("min_persons") else "ohne Menschen"
		elif rule.has("labels"):
			text.text = rule.labels[k]
		elif k == 0:
			text.text = "< %s" % fmt.call(bounds[0])
		elif k == CLASS_COLOURS.size() - 1:
			text.text = "≥ %s" % fmt.call(bounds[k - 1])
		else:
			text.text = "%s–%s" % [fmt.call(bounds[k - 1]), fmt.call(bounds[k])]
		text.add_theme_font_size_override("font_size", 12)
		_legend.add_child(text)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			_show(not open)
		elif event.keycode == KEY_ESCAPE and open:
			_show(false)
			get_viewport().set_input_as_handled() # the next Esc is the menu's

# ------------------------------------------------------------------ build

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	# right of the build bar, below the game clock
	_win = UiWindow.make("tables", "Statistik", Rect2(112, 64, 820, 680), Engine.get_main_loop() as SceneTree)
	_win.min_size = Vector2(PANEL_MIN, 320)
	_win.closed.connect(func():
		if open:
			_show(false))
	var column: VBoxContainer = _win.body
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	_stand = Label.new()
	_stand.add_theme_color_override("font_color", UiStyle.KIND)
	_stand.add_theme_font_override("font", UiStyle.italic())
	_stand.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL + 1)
	_stand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tabs = UiTabs.new()
	for topic in VIEWS:
		_tabs.add_tab(topic[0])
	_tabs.tab_changed.connect(_on_tab)
	head.add_child(_tabs)
	# under the topics: its views at the left, the months and the date at the right
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 12)
	column.add_child(views)
	for topic in VIEWS:
		var row := UiTabs.new(32.0, VIEW_PX)
		for view in topic[1]:
			row.add_tab(view[0])
		row.tab_changed.connect(_on_view)
		row.visible = false
		views.add_child(row)
		_views.append(row)
	_spans = SimOverview.span_buttons(func(months: int):
		_span = months
		for p in _pages.values():
			p.set_span(months), _span)
	_spans.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	views.add_child(_spans)
	_filter_row = HFlowContainer.new()
	_filter_row.add_theme_constant_override("h_separation", 8)
	_filter_row.add_theme_constant_override("v_separation", 6)
	column.add_child(_filter_row)
	_search = LineEdit.new()
	_search.placeholder_text = "Suchen …"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(180, 0)
	_search.text_changed.connect(func(text: String):
		_state[_kind].search = text
		if not _tables[_kind].is_empty():
			_fill_tree(_tables[_kind]))
	_filter_row.add_child(_search)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_row.add_child(fill)
	_stand.size_flags_horizontal = Control.SIZE_EXPAND_FILL # the date of the figures, right of the views, cut short when narrow
	_stand.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stand.clip_text = true
	_stand.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	views.add_child(_stand)
	views.move_child(_stand, _views.size()) # before the months
	_fold = CheckButton.new()
	_fold.focus_mode = Control.FOCUS_NONE
	_fold.toggled.connect(func(on: bool):
		_state[_kind].folded = on
		if not _tables[_kind].is_empty():
			_fill_tree(_tables[_kind]))
	_filter_row.add_child(_fold)
	_paint = CheckButton.new()
	_paint.text = "Karte färben"
	_paint.tooltip_text = "Färbt die Regionen nach der sortierten Spalte"
	_paint.focus_mode = Control.FOCUS_NONE
	_paint.toggled.connect(func(on: bool):
		var t := _tables[0]
		var sort: String = _state[0].sort
		_map_by = (sort if sort != "" and not t.is_empty() and t.data.has(sort) and not _is_text(t, sort) else "price") if on else ""
		if on and _state[0].sort != _map_by:
			_state[0].sort = _map_by
			_state[0].desc = true
			if not t.is_empty():
				_fill_tree(t)
		_paint_regions())
	_filter_row.add_child(_paint)
	_legend_box = PanelContainer.new()
	var legend_frame := UiStyle.frame()
	legend_frame.set_content_margin_all(8)
	_legend_box.add_theme_stylebox_override("panel", legend_frame)
	_legend_box.visible = false
	root.add_child(_legend_box)
	var legend_row := HBoxContainer.new()
	_legend_box.add_child(legend_row)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 6)
	legend_row.add_child(_legend)
	var off := Button.new()
	off.text = "✕"
	off.flat = true
	off.focus_mode = Control.FOCUS_NONE
	off.tooltip_text = "Kartenfarben aus"
	off.pressed.connect(func():
		_map_by = ""
		_paint.set_pressed_no_signal(false)
		_paint_regions())
	legend_row.add_child(off)
	_legend_box.resized.connect(_place_legend)
	_chart = Control.new()
	_chart.custom_minimum_size = Vector2(0, CHART_PX)
	_chart.draw.connect(_draw_chart)
	_chart.resized.connect(_chart.queue_redraw)
	column.add_child(_chart)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.allow_search = false # letters stay with the camera keys and T
	_tree.auto_tooltip = false # the rows have EU5 tooltips (ui/tooltips.gd)
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.column_title_clicked.connect(_on_title)
	_tree.item_selected.connect(_on_selected)
	_tree.item_collapsed.connect(_on_collapsed)
	Tooltips.attach(_tree, _row_tip)
	column.add_child(_tree)
	_note = Label.new()
	_note.text = "Auf einer Zeile verweilen zeigt mehr  ·  Klick zeigt den Ort  ·  Spaltenkopf sortiert  ·  D = Denar"
	_note.add_theme_color_override("font_color", SECONDARY)
	_note.add_theme_font_size_override("font_size", 12)
	column.add_child(_note)

func _ready() -> void:
	get_viewport().size_changed.connect(_place_legend)
	_place_legend()

## The map's legend on the bar of map modes, or else at the bottom left,
## clear of the window when it is open.
func _place_legend() -> void:
	if not is_inside_tree():
		return
	var screen := get_viewport().get_visible_rect().size
	if legend_over != null and legend_over.visible:
		var bar := legend_over.get_rect()
		var from := minf(bar.position.x, bar.end.x - _legend_box.size.x) # no further right than the bar
		_legend_box.position = Vector2(maxf(from, 12.0), bar.position.y - _legend_box.size.y - 8.0)
		return
	var x := 12.0
	if open and _win.position.x < 12.0 + _legend_box.size.x and _win.position.x + _win.size.x + 12.0 + _legend_box.size.x < screen.x - 400.0:
		x = _win.position.x + _win.size.x + 12.0 # beside the window, left of the events
	_legend_box.position = Vector2(x, screen.y - _legend_box.size.y - 12.0)

## The window keeps the size its player gave it; only the legend moves.
func _place_panel() -> void:
	_place_legend()

static func _serif() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Palatino", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	return font

static func _box(bg: Color, border: Color, border_w: int, radius: int, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_w)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box

## EU5's look (ui/ui_style.gd) for every control in the window.
static func _theme() -> Theme:
	return UiStyle.theme()
