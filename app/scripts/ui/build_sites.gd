extends Node
## Where to build, as Victoria 3's construction list (Ramon, 31.10.2026:
## "ich hätte gerne alles"): when a tool of the build menu is chosen
## (build_menu.gd), a window beside the strip lists the markets with what
## speaks for building there: the people in tents waiting for a home and
## work, the free land, the share going hungry and the grain price, from
## the markets table the statistics ask for each month (sim_tables.gd). A
## click on a title sorts by it; a click on a row flies there, close enough
## to build, and the tool stays in hand. It only shows what the sim
## counted; whether a farm there gets people the preview under the cursor
## tells, as before.

const UiWindow = preload("res://scripts/ui/ui_window.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const ROWS_MAX := 80
const SITE_KM := 16.0 # the view width it flies to: under build_menu.gd BUILD_MAX_KM
const MIN_PERSONS := 1 # a market without people is no place to build
const MIN_FREE_HA := 1.0 # nor one without free land: a farm and a field need it (build_menu.gd check status 4)
## column, title, tooltip, unit; the sort starts at the tents
const COLUMNS := [
	["region", "Ort", "Der Markt und seine Region.", ""],
	["tent_persons", "Im Zelt", "Menschen ohne Haus auf diesem Markt: sie warten auf einen Hof und arbeiten als Taglöhner.", ""],
	["free_ha", "Freies Land", "Land in der Region, das noch niemand bestellt.", "ha"],
	["share_hungry", "Hungernd", "Anteil der Menschen, die im letzten Monat nicht satt geworden sind.", "%"],
	["price", "Kornpreis", "Was ein Kilo Korn auf diesem Markt kostet.", "D/kg"],
]

signal flown(at: Vector2)
signal closed

var tables: Node # sim_tables.gd
var landscape: Node3D
var _win # ui_window.gd (untyped: its own members)
var _note: Label
var _tree: Tree
var _sort := 1 # index into COLUMNS
var _desc := true
var _day := -1 # the table day shown
var _ids := PackedInt64Array() # market id per row shown
var _at: Array[Vector2] = [] # world km per row shown

func _ready() -> void:
	_win = UiWindow.make("build_sites", "Wo bauen", Rect2(112, -96, 760, 470), get_tree())
	_win.min_size = Vector2(480, 260)
	_win.visible = false
	_win.closed.connect(func(): closed.emit())
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
	_note.add_theme_color_override("font_color", UiStyle.DIM)
	_win.body.add_child(_note)
	_tree = Tree.new()
	_tree.columns = COLUMNS.size()
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in COLUMNS.size():
		_tree.set_column_expand(c, c == 0)
		if c > 0:
			_tree.set_column_custom_minimum_width(c, 100)
		_tree.set_column_title_alignment(c, HORIZONTAL_ALIGNMENT_LEFT if c == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		_tree.set_column_title_tooltip_text(c, COLUMNS[c][2])
	_tree.column_title_clicked.connect(_on_title)
	_tree.item_mouse_selected.connect(_on_clicked)
	_win.body.add_child(_tree)

## Shown for the tool `kind` (build_menu.gd FARM, FIELD), hidden for NONE.
func show_for(kind: int, tool_name: String) -> void:
	if kind < 0:
		if _win.visible:
			_win.visible = false
		return
	_win.set_title("Wo bauen: %s" % tool_name)
	_note.text = ("Märkte mit freiem Land, wo Menschen im Zelt auf einen Hof warten. Ein Klick fliegt hin, dann den Hof auf der Karte setzen."
		if kind == 0 else
		"Märkte mit freiem Land. Ein Klick fliegt hin, dann die Felder auf der Karte aufziehen.")
	if not _win.visible:
		_win.open()
	_day = -1
	_fill()

func is_open() -> bool:
	return _win.visible

func _process(_delta: float) -> void:
	if _win.visible:
		_fill()

func _markets() -> Dictionary:
	if tables == null or not "_tables" in tables or tables._tables.is_empty():
		return {}
	var t: Dictionary = tables._tables[0]
	if t.is_empty() or not t.has("data"):
		return {}
	return t

## The rows anew when a new monthly count came or the sort changed.
func _fill() -> void:
	var t := _markets()
	if t.is_empty():
		return
	if int(t.day) == _day:
		return
	_day = int(t.day)
	var d: Dictionary = t.data
	for c in COLUMNS:
		if not d.has(c[0]):
			return
	for c in COLUMNS.size():
		var arrow := ("  ▼" if _desc else "  ▲") if c == _sort else ""
		_tree.set_column_title(c, COLUMNS[c][1] + arrow)
	var rows := []
	for r in d.id.size():
		if int(d.persons[r]) >= MIN_PERSONS and float(d.free_ha[r]) >= MIN_FREE_HA:
			rows.append(r)
	var key: String = COLUMNS[_sort][0]
	var values := []
	for r in d.id.size():
		values.append(str(d.region[r]) if key == "region" else float(d[key][r]))
	if _desc:
		rows.sort_custom(func(a, b): return values[a] > values[b])
	else:
		rows.sort_custom(func(a, b): return values[a] < values[b])
	rows = rows.slice(0, ROWS_MAX)
	_tree.clear()
	_ids.clear()
	_at.clear()
	var root := _tree.create_item()
	for i in rows.size():
		var r: int = rows[i]
		var item := _tree.create_item(root)
		item.set_text(0, str(d.region[r]))
		item.set_custom_color(0, UiStyle.NAME)
		item.set_text(1, _amount(int(d.tent_persons[r])))
		item.set_text(2, _amount(int(float(d.free_ha[r]))) + " ha")
		var hungry := float(d.share_hungry[r])
		item.set_text(3, "%.1f %%" % (100.0 * hungry))
		if hungry >= 0.05:
			item.set_custom_color(3, UiStyle.LOSS)
		item.set_text(4, "%.2f D/kg" % float(d.price[r]))
		for c in range(1, COLUMNS.size()):
			item.set_text_alignment(c, HORIZONTAL_ALIGNMENT_RIGHT)
		if i % 2 == 1:
			for c in COLUMNS.size():
				item.set_custom_bg_color(c, UiStyle.STRIPE)
		item.set_tooltip_text(0, "%s: %s Menschen\nKlick: hinfliegen" % [str(d.region[r]), _amount(int(d.persons[r]))])
		_ids.append(int(d.id[r]))
		_at.append(landscape.lonlat_to_world(float(d.lon[r]), float(d.lat[r])) if landscape != null else Vector2.ZERO)

func _on_title(column: int, _button: int) -> void:
	if column == _sort:
		_desc = not _desc
	else:
		_sort = column
		_desc = column != 0
	_day = -1
	_fill()

func _on_clicked(_at_px: Vector2, button: int) -> void:
	var item := _tree.get_selected()
	if button != MOUSE_BUTTON_LEFT:
		return
	if item == null:
		return
	var i := item.get_index()
	if i < 0 or i >= _at.size() or landscape == null:
		return
	landscape._goal_target = _at[i]
	landscape._goal_width = SITE_KM
	flown.emit(_at[i])

## 116805 as 116'805 (Swiss thousands).
static func _amount(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "'" + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
