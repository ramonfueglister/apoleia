extends CanvasLayer
## A farm's window, as Victoria 3 gives every building its own: who works
## it, its fields and their year, its store and money, its tools and
## flock, and who worked there at the last weekly labour exchange
## (apoleia_sim::grain::Grain::farm_look, people_dots.rs take_farm). In
## the menus' window (ui/ui_window.gd), cards as the person's window. While
## open it follows the sim once a week.
##
##   ← in its band              the farm shown before
##   → under its title          the farm's market
##   right click on its band    its menu: on the map, in the outliner
##   click on a person          their window (right click: their menu)
##   Esc or ×                   close it
##
## In the group "farm_window": call_group("farm_window", "open", id) opens
## farm `id` (take_person's "farm", the outliner, a right-click menu).

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const SimOverview = preload("res://scripts/sim/sim_overview.gd")
const UiWindow = preload("res://scripts/ui/ui_window.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Vic3Style = preload("res://scripts/ui/vic3_style.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const ContextMenu = preload("res://scripts/ui/context_menu.gd")
const PersonWindow = preload("res://scripts/sim/person_window.gd")
const REFRESH_DAYS := 7
const WIDTH := 460.0
const MEDAL_R := 27.0
const BAR_ROW := 30.0
const BAR_PX := 8.0
const ROW_PX := 26.0
const PEOPLE_MAX := 8 # people listed per card before "und N weitere"
const FLY_MAX_KM := 40.0 # the terrain draws the fields up to this width (people_dots.gd FIELDS_KM)

var landscape: Node3D
var people: RefCounted # ApoleiaPeople
var farm := -1
var _waiting := false
var _asked_day := -1
var _win # ui_window.gd
var _head: Control
var _cards: VBoxContainer
var _when: Label
var _shown := {} # the farm as last shown
var _icon: Texture2D

func setup(scene: Node3D, sim: RefCounted) -> void:
	name = "FarmWindow"
	add_to_group("farm_window")
	layer = 4
	landscape = scene
	people = sim
	_win = UiWindow.make("farm", "Hof", Rect2(560, 64, WIDTH, 760), Engine.get_main_loop() as SceneTree)
	_win.visible = false
	_win.closed.connect(func():
		farm = -1
		_waiting = false)
	_win.context = func() -> Dictionary:
		if farm < 0 or not _shown.has("kind"):
			return {}
		return {"title": str(_shown.kind), "kind": "Hof am Markt %s" % _shown.market_name,
			"entries": ContextMenu.entries(get_tree(), "farm", farm, "%s am Markt %s" % [_shown.kind, _shown.market_name], _fly_to, true)}
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_win.body.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	_head = Control.new()
	_head.custom_minimum_size = Vector2(0, MEDAL_R * 2.0 + 10.0)
	_head.draw.connect(_draw_head)
	column.add_child(_head)
	_when = UiStyle.label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	column.add_child(_when)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	column.add_child(_cards)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _win.visible:
		_win.close()
		get_viewport().set_input_as_handled()

func open(id: int) -> void:
	if people == null or id < 0:
		return
	if _win.visible and farm >= 0 and id != farm:
		var before := farm
		_win.remember(func(): open(before))
	farm = id
	_ask()
	if not _win.visible:
		_win.set_title("…")
		_win.set_subtitle("")
		_clear()
	_win.open()

func _ask() -> void:
	people.ask_farm(farm)
	_waiting = true
	_asked_day = people.day()

func _process(_delta: float) -> void:
	if farm < 0 or people == null:
		return
	if _waiting:
		var d: Dictionary = people.take_farm()
		if not d.is_empty():
			_waiting = false
			if int(d.farm) == farm:
				_show(d)
	elif people.day() - _asked_day >= REFRESH_DAYS:
		_ask()

## The camera onto the farmhouse, its fields in view.
func _fly_to() -> void:
	if landscape == null or not "_goal_target" in landscape or not _shown.has("at"):
		return
	landscape._goal_target = _shown.at
	landscape._goal_width = clampf(float(_shown.reach_km) * 2.0 * SimTables.FLY_MARGIN, SimTables.FLY_MIN_KM, FLY_MAX_KM)

func _clear() -> void:
	for c in _cards.get_children():
		c.queue_free()

func _show(d: Dictionary) -> void:
	_clear()
	_shown = d
	if not d.has("kind"):
		_win.set_title("Kein Hof")
		_win.set_subtitle("")
		_when.text = "Diesen Hof bestellt niemand mehr."
		_head.queue_redraw()
		return
	_win.set_title(str(d.kind))
	var m := int(d.market)
	_win.set_subtitle("Am Markt %s" % d.market_name, func(): get_tree().call_group("market_window", "open", m), "Den Markt öffnen")
	var day: int = people.day() if people != null else 0
	_when.text = "Stand %d. %s" % [day % SimTables.MONTH + 1, SimTables._date(day)]
	_icon = Vic3Style.icon(SimOverview.ICONS.get(str(d.kind), "field")) # loaded before the first draw (GLES3)
	_head.queue_redraw()
	_fields(d)
	_year(d)
	_store(d)
	_goods(d)
	_people(d)

# ------------------------------------------------------------------ cards

func _draw_head() -> void:
	if not _shown.has("kind"):
		return
	var at := Vector2(MEDAL_R + 6.0, MEDAL_R + 4.0)
	_head.draw_circle(at, MEDAL_R + 2.0, UiStyle.EDGE)
	_head.draw_circle(at, MEDAL_R + 1.0, UiStyle.GOLD)
	_head.draw_circle(at, MEDAL_R - 1.5, SimOverview.FED_COLOURS[0].darkened(0.3))
	if _icon != null:
		var side := (MEDAL_R - 5.0) * 2.0
		_head.draw_texture_rect(_icon, Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), false, UiStyle.TEXT)
	var x := at.x + MEDAL_R + 14.0
	var fam: Array = _shown.get("family", [])
	UiStyle.text_at(_head, Vector2(x, at.y - 4.0), "%s ha Feld" % SimOverview._num(float(_shown.area_ha)), UiStyle.TITLE, UiStyle.SIZE_HEAD, HORIZONTAL_ALIGNMENT_LEFT, _head.size.x - x, UiStyle.title_font())
	var line := "bestellt von %s" % ("einem Menschen" if fam.size() == 1 else "%d Menschen" % fam.size())
	UiStyle.text_at(_head, Vector2(x, at.y + 20.0), line, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, _head.size.x - x, UiStyle.serif())

func _fields(d: Dictionary) -> void:
	var box := _card("Felder", "Die Felder des Hofs. Gerodetes Land an Hängen und Waldrändern trägt weniger. Staatsland hat der Hof von den Feldern gepachtet, die der Spieler gebaut hat.")
	var area := float(d.area_ha)
	_row(box, "Felder", "%s ha" % SimOverview._num(area))
	if float(d.poor_ha) > 0.0:
		_row(box, "davon gerodet", "%s ha" % SimOverview._num(float(d.poor_ha)), UiStyle.VALUE,
			"Land, das der Hof an Hängen oder am Waldrand gerodet hat. Es trägt weniger als das gute Land.")
	if float(d.state_ha) > 0.0:
		_row(box, "davon Staatsland", "%s ha" % SimOverview._num(float(d.state_ha)), UiStyle.VALUE,
			"Felder auf Staatsland, die der Spieler gebaut hat. Der Hof pachtet sie.")
	var sown := float(d.sown_ha) / area if area > 0.0 else 0.0
	_bar_row(box, "Gesät", sown, "%d %%" % roundi(sown * 100.0), UiStyle.GAIN if sown >= 0.95 else UiStyle.GOLD,
		"Anteil der Felder, die in diesem Jahr gesät sind.")
	_row(box, "Ertrag", "%s kg/ha" % SimOverview._num(float(d.net_kg_ha)), UiStyle.VALUE,
		"Was eine Hektare nach Abzug des Saatguts im Mittel trägt.")
	if d.get("manciana", false):
		_row(box, "Lex Manciana", "gerodet nach dem Gesetz", UiStyle.VALUE,
			"Land, das nach der Lex Manciana gerodet wurde: Wer brachliegendes Land urbar macht, darf es bestellen und gibt dafür einen Teil der Ernte ab.")
	if int(d.idle) > 0:
		_row(box, "Brache", "%d %s ungesät" % [int(d.idle), "Jahr" if int(d.idle) == 1 else "Jahre"], UiStyle.LOSS)

func _year(d: Dictionary) -> void:
	var box := _card("Jahr", "Wann der Hof sät und erntet, und wie viel Arbeit ausserhalb von Saat und Ernte seit der letzten Ernte anfiel.")
	_row(box, "Saat", _doy(int(d.sow_doy)))
	_row(box, "Ernte", _doy(int(d.harvest_doy)))
	var need := int(d.off_need)
	if need > 0:
		var done := int(d.off_done)
		var share := float(done) / float(need)
		_bar_row(box, "Arbeit dazwischen", share, "%d von %d" % [done, need], UiStyle.GAIN if share >= 0.95 else UiStyle.GOLD,
			"Tage Arbeit ausserhalb von Saat und Ernte, die die Felder seit der letzten Ernte brauchten, und wie viele davon getan sind.")

func _store(d: Dictionary) -> void:
	var box := _card("Lager und Geld", "Korn im Hoflager, was der Hof davon verkaufen will, und sein Geld in Denar.")
	_row(box, "Kornlager", "%s kg" % SimOverview._num(float(d.store_kg)))
	if int(d.to_sell_kg) > 0:
		_row(box, "zum Verkauf", "%s kg" % SimOverview._num(float(d.to_sell_kg)), UiStyle.VALUE,
			"Korn, das der Hof über seinen Bedarf bis zur nächsten Ernte hinaus hat und auf den Markt bringt.")
	_row(box, "Vorratskrüge", SimOverview._num(roundf(float(d.jars))), UiStyle.VALUE, "Tönerne Krüge, in denen der Hof sein Korn lagert.")
	_row(box, "Geld", "%s D" % SimOverview._num(float(d.money)), UiStyle.LOSS if float(d.money) < 0.0 else UiStyle.VALUE)

func _goods(d: Dictionary) -> void:
	var box := _card("Werkzeug und Vieh", "Was der Hof an Werkzeug besitzt und wie viel Arbeit es erlaubt, dazu Schafe, Wolle und Schweine.")
	_row(box, "Werkzeug", "%s kg" % SimOverview._num(float(d.tools_kg)))
	var share := float(d.tools_share)
	_bar_row(box, "Arbeit möglich", share, "%d %%" % roundi(share * 100.0), UiStyle.GAIN if share >= 0.95 else (UiStyle.GOLD if share >= 0.75 else UiStyle.LOSS),
		"Anteil der Arbeit, den die Familie mit ihrem Werkzeug schafft. Ohne genug Werkzeug geht die Arbeit langsamer.")
	if int(d.sheep) > 0:
		_row(box, "Schafe", str(int(d.sheep)))
	if float(d.wool_kg) > 0.0:
		_row(box, "Wolle", "%s kg" % SimOverview._num(float(d.wool_kg)))
	if float(d.pork_kg_year) > 0.0:
		_row(box, "Schweinefleisch", "%s kg im Jahr" % SimOverview._num(float(d.pork_kg_year)))

func _people(d: Dictionary) -> void:
	var fam: Array = d.get("family", [])
	if not fam.is_empty():
		var box := _card("Haushalt", "Die Menschen, die den Hof bestellen. Klick öffnet eine Person.")
		for k in mini(fam.size(), PEOPLE_MAX):
			_person_row(box, fam[k], k, "")
		if fam.size() > PEOPLE_MAX:
			box.add_child(UiStyle.label("und %d weitere" % (fam.size() - PEOPLE_MAX), UiStyle.DIM, UiStyle.SIZE_SMALL))
	if d.has("landlord"):
		var box := _card("Grundherr", "Der Haushalt, dem das Land gehört. Klick öffnet eine Person daraus.")
		_person_row(box, d.landlord, 0, "")
	var workers: Array = d.get("workers", [])
	var box := _card("Diese Woche gearbeitet", "Wer an der letzten wöchentlichen Arbeitsbörse des Marktes Tage auf diesem Hof gearbeitet hat, je Haushalt eine Person.")
	if workers.is_empty():
		box.add_child(UiStyle.label("niemand", UiStyle.DIM, UiStyle.SIZE_TEXT))
		return
	var days := 0
	for w in workers:
		days += int(w.days)
	_row(box, "Zusammen", "%d %s, %s" % [workers.size(), "Haushalt" if workers.size() == 1 else "Haushalte", _days(days)])
	for k in mini(workers.size(), PEOPLE_MAX):
		var w: Dictionary = workers[k]
		_person_row(box, w, k, "%s, %s" % [w.work, _days(int(w.days))])
	if workers.size() > PEOPLE_MAX:
		box.add_child(UiStyle.label("und %d weitere" % (workers.size() - PEOPLE_MAX), UiStyle.DIM, UiStyle.SIZE_SMALL))

## A person as a row: who, their work, and `note` at the right; a click
## opens them, a right click their menu.
func _person_row(box: VBoxContainer, p: Dictionary, k: int, note: String) -> void:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, ROW_PX)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var who := "%s, %d" % [p.get("name", PersonWindow._who(p.female, float(p.age))), int(p.age)]
	var job: String = p.job
	var pid := int(p.pid)
	row.draw.connect(func():
		var font := UiStyle.serif()
		var lit := Rect2(Vector2.ZERO, row.size).has_point(row.get_local_mouse_position())
		row.draw_rect(Rect2(0, 0, row.size.x, ROW_PX - 2.0), UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK)
		if lit:
			row.draw_rect(Rect2(0, 0, row.size.x, ROW_PX - 2.0), UiStyle.HOVER)
			row.draw_rect(Rect2(0, 0, 3, ROW_PX - 2.0), UiStyle.GOLD)
		UiStyle.text_at(row, Vector2(10, 18), who, UiStyle.NAME if lit else UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 172.0, font)
		UiStyle.text_at(row, Vector2(188, 18), job, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, row.size.x - (330.0 if note != "" else 196.0), font)
		if note != "":
			UiStyle.text_at(row, Vector2(row.size.x - 140.0, 18), note, UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT, 134.0, UiStyle.italic()))
	row.mouse_entered.connect(row.queue_redraw)
	row.mouse_exited.connect(row.queue_redraw)
	row.gui_input.connect(func(e: InputEvent):
		if not e is InputEventMouseButton or e.pressed:
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			get_tree().call_group("person_window", "open_person", pid)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			ContextMenu.open(row, {"title": who, "kind": job, "entries": ContextMenu.entries(get_tree(), "person", pid, who)}))
	box.add_child(row)

# ------------------------------------------------------------------ parts

## A card as the person's window: its title on a slim band of leather.
func _card(title: String, about: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_cards.add_child(column)
	var head := UiStyle.label(title, UiStyle.TEXT, UiStyle.SIZE_HEAD)
	head.add_theme_font_override("font", UiStyle.title_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var band := UiStyle.box(UiStyle.BAR, UiStyle.GOLD_DIM, 0, 2, 3)
	band.border_width_bottom = 1
	band.corner_radius_bottom_left = 0
	band.corner_radius_bottom_right = 0
	head.add_theme_stylebox_override("normal", band)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	Tooltips.attach(head, func(_at: Vector2) -> Dictionary: return {"id": "farm-card:" + title, "title": title, "kind": "Hof", "text": about})
	column.add_child(head)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	column.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	pad.add_child(box)
	return box

## Name and value in a row, the value right; a tooltip if `about`.
func _row(box: VBoxContainer, name: String, value: String, colour := UiStyle.VALUE, about := "") -> void:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	var left := UiStyle.label(name, UiStyle.CONCEPT if about != "" else UiStyle.DIM, UiStyle.SIZE_TEXT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(left)
	var right := UiStyle.label(value, colour, UiStyle.SIZE_TEXT)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(right)
	if about != "":
		Tooltips.attach(line, func(_at: Vector2) -> Dictionary: return {"id": "farm-row:" + name, "title": name, "kind": "Hof", "text": about})
	box.add_child(line)

## A share as the menus' bars: the name, the bar in its trough, the value.
func _bar_row(box: VBoxContainer, name: String, share: float, value: String, colour: Color, about := "") -> void:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0, BAR_ROW)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.draw.connect(func():
		var font := UiStyle.serif()
		var mid := BAR_ROW * 0.5
		row.draw_rect(Rect2(0, 0, row.size.x, BAR_ROW - 2.0), UiStyle.ROW)
		UiStyle.text_at(row, Vector2(6, mid + 5.0), name, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 150.0, font)
		var x0 := 160.0
		var x1 := row.size.x - 90.0
		var trough := Rect2(x0, mid - BAR_PX * 0.5 - 3.0, x1 - x0, BAR_PX + 4.0)
		row.draw_rect(trough, UiStyle.CHART_GRID)
		row.draw_rect(trough, UiStyle.EDGE, false, 1.0)
		var end := x0 + 2.0 + (trough.size.x - 4.0) * clampf(share, 0.0, 1.0)
		if end - x0 > 2.5:
			var a := Vector2(x0 + 2.0, trough.position.y + 2.0)
			var b := Vector2(end, a.y)
			var dark := colour.darkened(0.45)
			var light := colour.lightened(0.2)
			row.draw_polygon(PackedVector2Array([a, b, b + Vector2(0, BAR_PX), a + Vector2(0, BAR_PX)]), PackedColorArray([dark, light, light, dark]))
		UiStyle.text_at(row, Vector2(x1 + 4.0, mid + 5.0), value, UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 82.0, font))
	if about != "":
		Tooltips.attach(row, func(_at: Vector2) -> Dictionary: return {"id": "farm-bar:" + name, "title": name, "kind": "Hof", "text": about})
	box.add_child(row)

## A day of the year as the game clock writes it: "14. Quintilis".
static func _doy(doy: int) -> String:
	return "%d. %s" % [doy % SimTables.MONTH + 1, SimTables.MONTHS[clampi(doy / SimTables.MONTH, 0, 11)]]

static func _days(n: int) -> String:
	return "1 Tag" if n == 1 else "%d Tage" % n
