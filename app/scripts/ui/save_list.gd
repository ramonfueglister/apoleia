extends VBoxContainer
## The list of save games both menus show (ui/save_games.gd): name, game
## date and when it was written, the newest first. A double click or
## «Laden» loads one; in the game a name field and «Speichern» sit above it.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const SaveGames = preload("res://scripts/ui/save_games.gd")
const SimTables = preload("res://scripts/sim/sim_tables.gd")

signal load_chosen(path: String)
signal save_asked(path: String, name: String)

var _tree: Tree
var _name: LineEdit
var _load: Button
var _delete: Button
var _empty: Label
var _saves: Array[Dictionary] = []
var _armed := false # «Löschen» pressed once: the next press deletes

func _init(can_save: bool) -> void:
	add_theme_constant_override("separation", 12)
	if can_save:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		_name = LineEdit.new()
		_name.placeholder_text = "Name des Spielstands"
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.custom_minimum_size.y = 40
		_name.text_submitted.connect(func(_t): _save())
		row.add_child(_name)
		row.add_child(_button("Speichern", _save))
	_tree = Tree.new()
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.custom_minimum_size = Vector2(560, 260)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for c in 3:
		_tree.set_column_title(c, ["Spielstand", "Spieldatum", "Gespeichert"][c])
		_tree.set_column_title_alignment(c, HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_expand(c, c == 0)
		if c > 0:
			_tree.set_column_custom_minimum_width(c, 150)
	_tree.item_selected.connect(_pick)
	_tree.item_activated.connect(func(): _load_selected())
	add_child(_tree)
	_empty = Label.new()
	_empty.text = "Noch kein Spielstand. Im Spiel speichert F8 oder Esc › Spiel speichern."
	_empty.add_theme_color_override("font_color", UiStyle.DIM)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty)
	var hint := Label.new()
	hint.text = "Laden spielt die Befehle des Spielstands neu ab und dauert etwas."
	hint.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL + 1)
	hint.add_theme_color_override("font_color", UiStyle.DIM)
	add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	_delete = _button("Löschen", _delete_selected)
	_delete.add_theme_color_override("font_color", UiStyle.DIM)
	buttons.add_child(_delete)
	_load = _button("Laden", _load_selected)
	buttons.add_child(_load)
	refresh()

func first_focus() -> Control:
	return _name if _name != null else _tree

func refresh() -> void:
	_saves = SaveGames.list()
	_tree.clear()
	var root := _tree.create_item()
	for s in _saves:
		var item := _tree.create_item(root)
		item.set_text(0, s.name)
		if s.quick:
			item.set_custom_color(0, UiStyle.NAME)
		item.set_text(1, SimTables._date(s.day) if s.day >= 0 else "–")
		item.set_text(2, SaveGames.when(s.saved))
		item.set_custom_color(2, UiStyle.DIM)
	_tree.visible = not _saves.is_empty()
	_empty.visible = _saves.is_empty()
	if not _saves.is_empty():
		root.get_first_child().select(0)
	_pick()

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 40)
	b.add_theme_font_size_override("font_size", UiStyle.SIZE_HEAD)
	b.pressed.connect(action)
	return b

func _chosen() -> Dictionary:
	var item := _tree.get_selected()
	return {} if item == null else _saves[item.get_index()]

func _pick() -> void:
	var s := _chosen()
	_armed = false
	_delete.text = "Löschen"
	_load.disabled = s.is_empty()
	_delete.disabled = s.is_empty()
	if _name != null and not s.is_empty() and not s.quick:
		_name.text = s.name

func _load_selected() -> void:
	var s := _chosen()
	if not s.is_empty():
		load_chosen.emit(s.path)

func _delete_selected() -> void:
	var s := _chosen()
	if s.is_empty():
		return
	if not _armed:
		_armed = true
		_delete.text = "Wirklich löschen?"
		return
	SaveGames.remove(s.path)
	refresh()

func _save() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		name = "Spielstand"
	save_asked.emit(SaveGames.path_for(name), name)
