extends CanvasLayer
## The simulation in tables, in the manner of EU5: markets, population by
## region and occupation, farms by region and the state's accounts, in a
## panel on the left that leaves the diorama free. T (or the button at the top left) opens and closes it.
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
## On the markets, "Karte färben" colours each region on the map by the
## column sorted by, in five classes of equal numbers of regions, with the
## regions' borders (ApoleiaPeople.region_map: the market of each 25 km
## cell; people_dots.gd paint_regions, sim_map.gdshaderinc sim_regions).
## The colours stay when the panel closes (it covers most of the map), with
## their legend at the bottom left, whose ✕ takes them off.
##
## Command line (after --): --tables=markets|population|farms|state|history
## opens the panel on that table, --tables-map=column colours the map by
## that column of the markets.

const KINDS: Array[String] = ["markets", "population", "farms", "state", "history"] # apoleia_sim::tables::TABLES
const TITLES: Array[String] = ["Märkte", "Bevölkerung", "Höfe", "Staat", "Verlauf"]
const MONTHS: Array[String] = ["Ianuarius", "Februarius", "Martius", "Aprilis", "Maius", "Iunius",
	"Quintilis", "Sextilis", "September", "October", "November", "December"]
const YEAR := 360 # days (sim/src/life.rs)
const MONTH := 30
const COUNTED := 17 # the grain economy's monthly count is done by this day of the month
const PER_TIME: Array[String] = ["Tag", "Monat", "Jahr"] # "kg/Tag" adds up, "Denar/kg" does not
const SHORT_UNITS := {"Denar": "D", "Denar/kg": "D/kg"} # the heads stay narrow
## the main menu's colours (main_menu.gd), with EU5's gold for heads and lines
const BACKGROUND := Color("13232b")
const INK := Color("edf0e8")
const SECONDARY := Color("aab9bc")
const GOLD := Color("c9a45c")
const HEAD := Color("1b3440")
const SELECTED := Color("2e5260")
const ROW_ODD := Color(1.0, 1.0, 1.0, 0.035)
const NEGATIVE := Color("e8846b") # in the red, as EU5 shows it
const COLUMN_PX := 96.0 # panel width per number column
const TEXT_PX := 190.0 # and per text column
const PANEL_MIN := 560.0
const PANEL_SHARE_MAX := 0.75 # of the window width
const FILTER_MAX := 64 # a text column with more values gets no dropdown
const ROW_MAX := 300
const FLY_MARGIN := 1.6 # the camera frames a place this many times its extent
const FLY_MIN_KM := 3.0
const FLY_MAX_KM := 600.0
const CHART_PX := 220.0
const NOT_SERIES: Array[String] = ["day", "year"] # the history's time, not a series
## the map's classes, few to many (pale straw to deep madder)
const CLASS_COLOURS: Array[Color] = [Color("f1e6c2"), Color("e3bf78"), Color("d08c4e"), Color("ac5637"), Color("72302a")]

var people: RefCounted
var landscape: Node3D
var open := false
var _kind := 0
var _tables: Array[Dictionary] = []
var _state: Array[Dictionary] = [] # per table: sort, desc, filters, search, folded, open groups, selected id
var _asked := -1 # the table asked for, until take_table answers
var _asked_day := -1
var _panel: PanelContainer
var _open_button: Button
var _tabs: TabBar
var _stand: Label
var _search: LineEdit
var _filter_row: HBoxContainer
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
var _map_by := "" # the markets' column the map is coloured by, "" for none
var _painted := "" # column and table day last painted

## `sim` is ApoleiaPeople, `scene` the landscape whose camera a row moves.
func setup(sim: RefCounted, scene: Node3D) -> void:
	people = sim
	landscape = scene
	name = "SimTables"
	layer = 2 # over the people's labels
	for kind in KINDS:
		_tables.append({})
		_state.append({"sort": "", "desc": true, "filters": {}, "search": "", "folded": false, "open": {}, "selected": -1})
	for arg in OS.get_cmdline_user_args():
		if arg.get_slice("=", 0) == "--tables":
			open = true
			_kind = maxi(KINDS.find(arg.get_slice("=", 1)), 0)
		elif arg.get_slice("=", 0) == "--tables-map":
			_map_by = arg.get_slice("=", 1)
			_state[0].sort = _map_by
	_build()
	_tabs.current_tab = _kind
	_show(open)

# ------------------------------------------------------------------ data

func _process(_delta: float) -> void:
	if not open and _map_by == "":
		return
	if _asked >= 0:
		var answer: Dictionary = people.take_table()
		if answer.is_empty():
			return
		_tables[_asked] = answer
		var was := _asked
		_asked = -1
		if was == _kind and open:
			_refresh()
		elif was == 0:
			_paint_regions()
		return
	var kind := _kind if open else 0 # closed, only the markets the map is coloured by
	var day: int = people.day()
	var t := _tables[kind]
	if day != _asked_day and (t.is_empty() or _count_of(day) != _count_of(int(t.day))):
		people.ask_table(KINDS[kind])
		_asked = kind
		_asked_day = day

## Which monthly count a table built on `day` shows.
static func _count_of(day: int) -> int:
	return day / MONTH - (0 if day % MONTH >= COUNTED else 1)

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
	var t := _tables[_kind]
	_chart.visible = KINDS[_kind] == "history"
	_note.text = ("Klick auf eine Reihe zeichnet ihre Kurve  ·  T schliesst" if KINDS[_kind] == "history"
		else "Klick auf eine Zeile zeigt den Ort  ·  Spaltenkopf sortiert  ·  D = Denar  ·  T schliesst")
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
	_tree.columns = cols.size()
	for i in cols.size():
		var number := not _is_text(t, cols[i])
		var title: String = t.labels[i]
		if _unit[i] != "" and _unit[i] != "%":
			title += " (%s)" % _unit[i]
		if cols[i] == state.sort:
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
	for i in cols.size():
		if total.get_custom_color(i) != NEGATIVE:
			total.set_custom_color(i, GOLD)
		if not _is_text(t, cols[i]): # the sum is often the widest number
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
	_chart.draw_rect(rect, Color(0.0, 0.0, 0.0, 0.18))
	_chart.draw_rect(rect, Color(GOLD, 0.35), false, 1.0)
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
	_chart.draw_string(font, Vector2(12, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)
	var n := _row_count(t)
	if n < 2:
		_chart.draw_string(font, Vector2(12, 48), "Noch zu wenige Monate", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, SECONDARY)
		return
	var scale := (100.0 if t.units[i] == "%" else 1.0) * (_factor[i] if _factor.size() > i else 1.0)
	var lo := INF
	var hi := -INF
	for k in keys:
		for v in data[k]:
			lo = minf(lo, float(v) * scale)
			hi = maxf(hi, float(v) * scale)
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
		_chart.draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1.0, 1.0, 1.0, 0.07), 1.0)
		var tag := ("%d %%" % roundi(v)) if t.units[i] == "%" else _number(v)
		_chart.draw_string(font, Vector2(8, y + 4), tag, HORIZONTAL_ALIGNMENT_RIGHT, 56, 11, SECONDARY)
	var days = data.day
	for r in n: # the years along the foot
		if r == 0 or int(days[r]) / YEAR != int(days[r - 1]) / YEAR:
			var x: float = x_of.call(r)
			_chart.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1.0, 1.0, 1.0, 0.07), 1.0)
			_chart.draw_string(font, Vector2(x + 3, plot.end.y + 16), "Jahr %d" % (int(days[r]) / YEAR + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SECONDARY)
	if keys.size() > 1: # the range of the prices as a band
		var band := PackedVector2Array()
		for r in n:
			band.append(Vector2(x_of.call(r), y_of.call(float(data.price_max[r]) * scale)))
		for r in range(n - 1, -1, -1):
			band.append(Vector2(x_of.call(r), y_of.call(float(data.price_min[r]) * scale)))
		if Geometry2D.triangulate_polygon(band).size() > 0:
			_chart.draw_colored_polygon(band, Color(GOLD, 0.16))
	var main := "price_median" if keys.size() > 1 else key
	var points := PackedVector2Array()
	for r in n:
		points.append(Vector2(x_of.call(r), y_of.call(float(data[main][r]) * scale)))
	_chart.draw_polyline(points, GOLD, 2.0, true)
	var last := points[n - 1]
	_chart.draw_circle(last, 3.5, GOLD)

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
				item.set_text(i, t.data[cols[i]][r])
			else:
				_set_number(item, i, float(t.data[cols[i]][r]) * _factor[i], _unit[i])
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
			item.set_text(i, names.get(cols[i], ""))
		else:
			_set_number(item, i, _combine(t, i, rows) * _factor[i], _unit[i])

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
	if line % 2 == 1:
		for i in _tree.columns:
			item.set_custom_bg_color(i, ROW_ODD)

## A share's bar along the foot of its cell, under the per cent.
func _draw_share(item: TreeItem, rect: Rect2, column: int) -> void:
	var v := clampf(float(item.get_metadata(column)), 0.0, 1.0)
	var bar := Rect2(rect.position.x + 8.0, rect.end.y - 5.0, rect.size.x - 14.0, 3.0)
	_tree.draw_rect(bar, Color(1.0, 1.0, 1.0, 0.08))
	bar.size.x *= v
	_tree.draw_rect(bar, Color(GOLD, 0.8))

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

# ------------------------------------------------------------------ input

func _on_title(column: int, _button: int) -> void:
	var t := _tables[_kind]
	if t.is_empty():
		return
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
	var free := maxf(screen - _panel.size.x, screen * 0.25)
	var w := clampf(maxf(maxf(hi.x - lo.x, hi.y - lo.y), reach) * FLY_MARGIN * screen / free, FLY_MIN_KM, FLY_MAX_KM)
	var centre := (lo + hi) * 0.5
	centre.x -= w * (_panel.size.x * 0.5) / screen
	landscape._goal_target = centre
	landscape._goal_width = w
	print(JSON.stringify({"event": "tables_fly", "kind": KINDS[_kind], "rows": rows.size(), "width_km": w}))

func _on_tab(index: int) -> void:
	_kind = index
	_refresh()

func _show(on: bool) -> void:
	open = on
	_panel.visible = on
	_open_button.visible = not on
	if on:
		_refresh()
	else:
		_place_legend()
		if _search.has_focus():
			_search.release_focus()

# ------------------------------------------------------------------ map

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
	# the value of each market, and the bounds of five classes with as many
	# regions each
	var value := {}
	var ids = t.data.id
	var col = t.data[_map_by]
	var sorted := PackedFloat64Array()
	for r in ids.size():
		value[int(ids[r])] = float(col[r])
		sorted.append(float(col[r]))
	sorted.sort()
	var bounds := PackedFloat64Array()
	for k in range(1, CLASS_COLOURS.size()):
		bounds.append(sorted[mini(sorted.size() * k / CLASS_COLOURS.size(), sorted.size() - 1)])
	var img := Image.create_empty(cols, rows, false, Image.FORMAT_RGBA8)
	for r in rows:
		for c in cols:
			var m := cells[r * cols + c]
			if m < 0 or not value.has(m):
				continue
			var k := bounds.bsearch(value[m], false)
			var colour: Color = CLASS_COLOURS[k]
			# alpha: bit 0 coloured, bits 1-4 a border to the north, east,
			# south and west (another region or the sea)
			var bits := 1
			var nb := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
			for s in 4:
				var rr: int = r + nb[s].y
				var cc: int = c + nb[s].x
				var other := cells[rr * cols + cc] if rr >= 0 and rr < rows and cc >= 0 and cc < cols else -1
				if other != m:
					bits |= 2 << s
			colour.a8 = bits
			img.set_pixel(c, r, colour)
	sim_view.paint_regions(img, grid)
	_painted = stamp
	_fill_legend(t, bounds)

## Five swatches with the bounds of their classes.
func _fill_legend(t: Dictionary, bounds: PackedFloat64Array) -> void:
	for child in _legend.get_children():
		child.queue_free()
	var i := Array(t.columns).find(_map_by)
	var unit: String = SHORT_UNITS.get(t.units[i], t.units[i])
	var tag := Label.new()
	tag.text = "Karte: %s" % t.labels[i]
	tag.add_theme_color_override("font_color", GOLD)
	_legend.add_child(tag)
	for k in CLASS_COLOURS.size():
		var swatch := ColorRect.new()
		swatch.color = CLASS_COLOURS[k]
		swatch.custom_minimum_size = Vector2(18, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_legend.add_child(swatch)
		var text := Label.new()
		var share := unit == "%"
		var fmt := func(v: float) -> String: return ("%d %%" % roundi(v * 100.0)) if share else _number(v)
		if k == 0:
			text.text = "< %s" % fmt.call(bounds[0])
		elif k == CLASS_COLOURS.size() - 1:
			text.text = "≥ %s" % fmt.call(bounds[k - 1])
		else:
			text.text = "%s–%s" % [fmt.call(bounds[k - 1]), fmt.call(bounds[k])]
		text.add_theme_font_size_override("font_size", 12)
		_legend.add_child(text)
	if unit != "" and unit != "%":
		var u := Label.new()
		u.text = unit
		u.add_theme_color_override("font_color", SECONDARY)
		_legend.add_child(u)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_T:
			_show(not open)
		elif event.keycode == KEY_ESCAPE and open:
			_show(false)

# ------------------------------------------------------------------ build

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	_open_button = Button.new()
	_open_button.text = "Tabellen  (T)"
	_open_button.focus_mode = Control.FOCUS_NONE
	_open_button.position = Vector2(12, 12)
	_open_button.pressed.connect(func(): _show(true))
	root.add_child(_open_button)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(Color(BACKGROUND, 0.95), Color(GOLD, 0.8), 2, 4, 14))
	root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Tabellen"
	title.add_theme_font_override("font", _serif())
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GOLD)
	head.add_child(title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_stand = Label.new()
	_stand.add_theme_color_override("font_color", SECONDARY)
	head.add_child(_stand)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): _show(false))
	head.add_child(close)
	_tabs = TabBar.new()
	for t in TITLES:
		_tabs.add_tab(t)
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(_on_tab)
	column.add_child(_tabs)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 8)
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
	_legend_box.add_theme_stylebox_override("panel", _box(Color(BACKGROUND, 0.92), Color(GOLD, 0.8), 2, 4, 8))
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
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.column_title_clicked.connect(_on_title)
	_tree.item_selected.connect(_on_selected)
	_tree.item_collapsed.connect(_on_collapsed)
	column.add_child(_tree)
	_note = Label.new()
	_note.text = "Klick auf eine Zeile zeigt den Ort  ·  Spaltenkopf sortiert  ·  D = Denar  ·  T schliesst"
	_note.add_theme_color_override("font_color", SECONDARY)
	_note.add_theme_font_size_override("font_size", 12)
	column.add_child(_note)

func _ready() -> void:
	get_viewport().size_changed.connect(_place_panel)
	_place_panel()

## The map's legend at the bottom left, clear of the panel when it is open.
func _place_legend() -> void:
	if not is_inside_tree():
		return
	var screen := get_viewport().get_visible_rect().size
	var x := 12.0
	if open and _panel.position.x + _panel.size.x + 12.0 + _legend_box.size.x < screen.x - 400.0:
		x = _panel.position.x + _panel.size.x + 12.0 # beside the panel, left of the events
	_legend_box.position = Vector2(x, screen.y - _legend_box.size.y - 12.0)

## Left, full height, as wide as the table's columns need (within limits).
func _place_panel() -> void:
	var screen := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600, 900)
	var want := PANEL_MIN
	var t := _tables[_kind]
	if not t.is_empty() and not _is_sheet(t) and not _is_history(t):
		want = 40.0
		for key in t.columns:
			want += TEXT_PX if _is_text(t, key) else COLUMN_PX
	_panel.position = Vector2(12, 12)
	_panel.size = Vector2(clampf(want, PANEL_MIN, maxf(screen.x * PANEL_SHARE_MAX, PANEL_MIN)), screen.y - 24.0)
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

## Dark teal and gold for every control in the panel.
static func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	th.set_color("font_color", "Label", INK)
	for type in ["Button", "OptionButton"]:
		th.set_stylebox("normal", type, _box(HEAD, Color(GOLD, 0.45), 1, 3, 6))
		th.set_stylebox("hover", type, _box(SELECTED, Color(GOLD, 0.8), 1, 3, 6))
		th.set_stylebox("pressed", type, _box(SELECTED, GOLD, 1, 3, 6))
		th.set_stylebox("focus", type, StyleBoxEmpty.new())
		th.set_color("font_color", type, INK)
		th.set_color("font_hover_color", type, Color.WHITE)
		th.set_color("font_pressed_color", type, GOLD)
	th.set_color("font_color", "CheckButton", INK)
	th.set_color("font_hover_color", "CheckButton", Color.WHITE)
	th.set_color("font_pressed_color", "CheckButton", GOLD)
	th.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("normal", "LineEdit", _box(Color(0.0, 0.0, 0.0, 0.25), Color(GOLD, 0.45), 1, 3, 6))
	th.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, GOLD, 1, 3, 6))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", Color(SECONDARY, 0.7))
	th.set_color("caret_color", "LineEdit", GOLD)
	th.set_stylebox("panel", "PopupMenu", _box(BACKGROUND, Color(GOLD, 0.8), 1, 3, 6))
	th.set_stylebox("hover", "PopupMenu", _box(SELECTED, Color.TRANSPARENT, 0, 2, 4))
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	var tab_on := _box(SELECTED, GOLD, 0, 3, 8)
	tab_on.border_width_bottom = 2
	th.set_stylebox("tab_selected", "TabBar", tab_on)
	th.set_stylebox("tab_unselected", "TabBar", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 3, 8))
	th.set_stylebox("tab_hovered", "TabBar", _box(HEAD, Color.TRANSPARENT, 0, 3, 8))
	th.set_color("font_selected_color", "TabBar", GOLD)
	th.set_color("font_unselected_color", "TabBar", SECONDARY)
	th.set_color("font_hovered_color", "TabBar", INK)
	th.set_font_size("font_size", "TabBar", 16)
	th.set_stylebox("panel", "Tree", _box(Color(0.0, 0.0, 0.0, 0.18), Color(GOLD, 0.35), 1, 2, 2))
	th.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	var title := _box(HEAD, GOLD, 0, 0, 6)
	title.border_width_bottom = 1
	th.set_stylebox("title_button_normal", "Tree", title)
	th.set_stylebox("title_button_pressed", "Tree", title)
	var title_hover := title.duplicate()
	title_hover.bg_color = SELECTED
	th.set_stylebox("title_button_hover", "Tree", title_hover)
	th.set_color("title_button_color", "Tree", GOLD)
	th.set_color("font_color", "Tree", INK)
	th.set_font_size("font_size", "Tree", 13)
	th.set_font_size("title_button_font_size", "Tree", 13)
	th.set_color("font_selected_color", "Tree", Color.WHITE)
	th.set_stylebox("selected", "Tree", _box(SELECTED, Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("selected_focus", "Tree", _box(SELECTED, Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("hovered", "Tree", _box(Color(1.0, 1.0, 1.0, 0.06), Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	th.set_constant("draw_guides", "Tree", 0)
	th.set_constant("draw_relationship_lines", "Tree", 0)
	th.set_constant("v_separation", "Tree", 6)
	th.set_constant("inner_item_margin_left", "Tree", 6)
	th.set_constant("inner_item_margin_right", "Tree", 8)
	th.set_stylebox("grabber", "VScrollBar", _box(Color(GOLD, 0.5), Color.TRANSPARENT, 0, 3, 3))
	th.set_stylebox("grabber_highlight", "VScrollBar", _box(GOLD, Color.TRANSPARENT, 0, 3, 3))
	th.set_stylebox("scroll", "VScrollBar", _box(Color(0.0, 0.0, 0.0, 0.25), Color.TRANSPARENT, 0, 3, 3))
	return th
