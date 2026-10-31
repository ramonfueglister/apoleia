extends CanvasLayer
## The menu a right click opens on a name, as Victoria 3's: open what it
## names, show it on the map, pin it in the outliner. In the tooltips' look
## (ui/tooltips.gd): the name on a wine-red band with the kind of thing
## below it, then one row per entry with its icon.
##
##   ContextMenu.open(node, {title = "Roma", kind = "Markt", entries = [
##       {text = "Öffnen", icon = "open-book", action = func(): …},
##       {text = "Auf der Karte zeigen", icon = "position-marker", action = …},
##   ]})
##
## An entry {} is left out. ContextMenu.entries(tree, kind, id, name, fly)
## gives the usual ones for a market, a person or a farm: open its window
## (the groups "market_window", "person_window", "farm_window"), fly there
## when `fly` is given, and pin it in the outliner (group "outliner", the
## menus' ui) while there is one.
##
## A click on an entry runs it and closes the menu; a click elsewhere or
## Esc only closes it.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Vic3Style = preload("res://scripts/ui/vic3_style.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const LAYER := 21 # over the tooltips
const ROW_PX := 30.0
const ICON_PX := 18.0
const WIDTH := 230.0
const OPEN := {"market": ["market_window", "open", "Markt öffnen"],
	"person": ["person_window", "open_person", "Person öffnen"],
	"farm": ["farm_window", "open", "Hof öffnen"]}

static var _shown: CanvasLayer

var _entries: Array = []

static func open(from: Node, d: Dictionary) -> void:
	close()
	var entries: Array = d.get("entries", []).filter(func(e): return not e.is_empty())
	if entries.is_empty() or from == null or not from.is_inside_tree():
		return
	Tooltips.close_all()
	var menu = load("res://scripts/ui/context_menu.gd").new()
	menu.name = "ContextMenu"
	menu.add_to_group("context_menu") # no tooltips while it is open
	menu.layer = LAYER
	from.get_tree().root.add_child(menu)
	menu._build(d.get("title", ""), d.get("kind", ""), entries, from.get_viewport().get_mouse_position())
	_shown = menu

static func close() -> void:
	if is_instance_valid(_shown):
		_shown.queue_free()
	_shown = null

## The usual entries for a market, a person or a farm by its id; `skip`
## leaves out opening it (the menu of its own window).
static func entries(tree: SceneTree, kind: String, id: int, name: String, fly := Callable(), skip := false) -> Array:
	var out := []
	var how: Array = OPEN.get(kind, [])
	if not skip and not how.is_empty() and tree.get_first_node_in_group(how[0]) != null:
		out.append({"text": how[2], "icon": "open-book", "action": func(): tree.call_group(how[0], how[1], id)})
	if fly.is_valid():
		out.append({"text": "Auf der Karte zeigen", "icon": "position-marker", "action": fly})
	if tree.get_first_node_in_group("outliner") != null:
		out.append({"text": "Im Outliner anheften", "icon": "pin", "action": func(): tree.call_group("outliner", "pin", kind, id, name)})
	return out

## The entries hold lambdas of other scripts: drop them while those live
## (a lambda freed after its script crashes the quit, Godot #102569).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_entries.clear()

func _build(title: String, kind: String, entries: Array, mouse: Vector2) -> void:
	_entries = entries
	# a click anywhere outside closes the menu and does nothing else
	var catcher := Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(catcher)
	var panel := PanelContainer.new()
	panel.theme = UiStyle.theme()
	panel.add_theme_stylebox_override("panel", _frame())
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	if title != "":
		var head_back := PanelContainer.new()
		head_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head_box := UiStyle.box(UiStyle.TIP_HEAD, UiStyle.GOLD, 0, 0, 0)
		head_box.border_width_bottom = 2
		head_box.content_margin_left = 12
		head_box.content_margin_right = 12
		head_box.content_margin_top = 5
		head_box.content_margin_bottom = 6
		head_back.add_theme_stylebox_override("panel", head_box)
		column.add_child(head_back)
		var titles := VBoxContainer.new()
		titles.add_theme_constant_override("separation", -2)
		titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head_back.add_child(titles)
		titles.add_child(UiStyle.label(title, Color("f8f1e6"), UiStyle.SIZE_HEAD, UiStyle.bold()))
		if kind != "":
			titles.add_child(UiStyle.label(kind, UiStyle.KIND, UiStyle.SIZE_SMALL + 1, UiStyle.italic()))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	var pad := MarginContainer.new()
	for side in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 4)
	pad.add_child(rows)
	column.add_child(pad)
	for e in entries:
		rows.add_child(_row(e))
	panel.reset_size()
	var screen := get_viewport().get_visible_rect().size
	var extent := panel.get_combined_minimum_size()
	var at := mouse + Vector2(2, 2)
	if at.x + extent.x > screen.x - 8.0:
		at.x = mouse.x - extent.x - 2.0
	if at.y + extent.y > screen.y - 8.0:
		at.y = screen.y - extent.y - 8.0
	panel.position = at.max(Vector2(8, 8))

## An entry: its icon, its name; lit under the mouse.
func _row(e: Dictionary) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(WIDTH, ROW_PX)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon: Texture2D = Vic3Style.icon(e.get("icon", "")) if e.get("icon", "") != "" else null # loaded before the first draw (GLES3)
	row.draw.connect(func():
		var lit := Rect2(Vector2.ZERO, row.size).has_point(row.get_local_mouse_position())
		if lit:
			row.draw_rect(Rect2(Vector2.ZERO, row.size), UiStyle.HOVER)
			row.draw_rect(Rect2(0, 3, 3, row.size.y - 6.0), UiStyle.GOLD)
		if icon != null:
			row.draw_texture_rect(icon, Rect2(Vector2(12.0, (row.size.y - ICON_PX) * 0.5), Vector2(ICON_PX, ICON_PX)), false,
				UiStyle.GOLD_LIT if lit else UiStyle.GOLD)
		UiStyle.text_at(row, Vector2(40.0, row.size.y * 0.5 + 6.0), e.get("text", ""), UiStyle.TITLE if lit else UiStyle.TEXT,
			UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 52.0, UiStyle.serif()))
	row.mouse_entered.connect(row.queue_redraw)
	row.mouse_exited.connect(row.queue_redraw)
	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var action: Callable = e.get("action", Callable())
			close()
			if action.is_valid():
				action.call())
	return row

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled() # the next Esc is the windows'

## The tooltips' frame: dark slate in a thin bronze-grey line, a shadow.
static func _frame() -> StyleBoxFlat:
	var b := UiStyle.box(Color(UiStyle.TIP_BODY, 0.98), UiStyle.TIP_FRAME, 1, 1, 0)
	b.expand_margin_left = 1
	b.expand_margin_right = 1
	b.expand_margin_top = 1
	b.expand_margin_bottom = 1
	b.shadow_color = Color(0, 0, 0, 0.6)
	b.shadow_size = 10
	b.shadow_offset = Vector2(0, 4)
	return b
