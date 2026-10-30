extends RefCounted
## The window of the person clicked (people_dots.gd), in the menus' look
## (Victoria 3): the person under a medal of their household's class, then
## cards as the statistics' (sim_overview.gd): the household's people, food,
## work and money, and the person themself. Money and food are the grain
## economy's as of its last monthly count (apoleia_sim::grain::HouseholdLook,
## people_dots.rs take_person); where the money stands is its rank among
## all people of the map and of its market, by money per head.

const UiWindow = preload("res://scripts/ui/ui_window.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Vic3Style = preload("res://scripts/ui/vic3_style.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const SimOverview = preload("res://scripts/sim/sim_overview.gd")
const PortraitView = preload("res://scripts/ui/portrait_view.gd")
const WIDTH := 430.0
const MEDAL_R := 27.0
const BADGE_R := 14.0 # the class medal on the portrait's corner
const BAR_ROW := 30.0
const BAR_PX := 8.0
const FAMILY_MAX := 8 # members listed before "und N weitere"
## The household kinds (KIND_NAMES in apoleia_sim::grain) as the
## statistics name the classes.
const CLASSES := {"Hof": "Hofleute", "Zelt": "Im Zelt", "Lohn": "Lohnarbeit", "Händler": "Händler", "Oberschicht": "Oberschicht"}
const STANDS := ["Landvolk", "Stadtvolk", "Ritter", "Senatoren"]
const CRAFT_NOTES := {"Taglohn": "Taglohn", "Weber": "Weberei", "Schmied": "Schmiede", "Töpfer": "Töpferei"}

var _win # ui_window.gd
var _column: VBoxContainer
var _head: Control
var _portrait # portrait_view.gd, kept across people
var _badge: Control # the class medal over the portrait's corner
var _note: RichTextLabel
var _cards: VBoxContainer
var _class := ""
var _icons := {}

func _init(tree: SceneTree) -> void:
	# at the bottom left, beside the build menu; moved and sized as the player likes
	_win = UiWindow.make("person", "Person", Rect2(112, -12, WIDTH, 620), tree)
	_win.visible = false
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_win.body.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 10)
	scroll.add_child(_column)
	_head = Control.new()
	_head.custom_minimum_size = Vector2(0, MEDAL_R * 2.0 + 10.0)
	_head.mouse_filter = Control.MOUSE_FILTER_PASS
	_column.add_child(_head)
	_portrait = PortraitView.new()
	_portrait.visible = false
	_head.add_child(_portrait)
	Tooltips.attach(_portrait, func(_at: Vector2) -> Dictionary:
		return {"id": "person-portrait", "title": "Gesicht", "kind": "Person", "text": "Das Gesicht wächst aus 34 Erbanlagen, je eine von Vater und Mutter. Das Gewicht zeigt, wie gut die Person isst, die Haut, wie viel sie draussen arbeitet; Kleidung und Kopfbedeckung folgen dem Beruf und dem Stand."})
	_badge = Control.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.size = Vector2(BADGE_R, BADGE_R) * 2.0 + Vector2(6.0, 6.0)
	_badge.position = PortraitView.SIZE - _badge.size + Vector2(6.0, 4.0)
	_badge.visible = false
	_badge.draw.connect(func():
		if _class != "":
			_medal(_badge, _badge.size * 0.5, BADGE_R, _class, _colour(_class)))
	_head.add_child(_badge)
	_note = RichTextLabel.new()
	_note.bbcode_enabled = true
	_note.fit_content = true
	_note.scroll_active = false
	_note.add_theme_font_override("normal_font", UiStyle.serif())
	_note.add_theme_font_override("italics_font", UiStyle.italic())
	_note.add_theme_font_size_override("normal_font_size", UiStyle.SIZE_TEXT)
	_note.add_theme_font_size_override("italics_font_size", UiStyle.SIZE_TEXT)
	_note.add_theme_color_override("default_color", UiStyle.TEXT)
	_column.add_child(_note)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	_column.add_child(_cards)

func open() -> void:
	_win.open()

func close() -> void:
	if _win.visible:
		_win.close()

func is_open() -> bool:
	return _win.visible

## While the sim thread looks the person up.
func wait() -> void:
	note("…")

## Only a line, no person: a scene with nobody to look up (a funeral), or
## someone no longer there.
func note(bbcode: String) -> void:
	_clear()
	_head.visible = false
	_note.text = bbcode

func _clear() -> void:
	for c in _cards.get_children():
		c.queue_free()
	for c in _head.get_children():
		if c != _portrait and c != _badge:
			c.queue_free()
	for c in _head.draw.get_connections():
		_head.draw.disconnect(c.callable)

## The person `p` (people_dots.rs take_person), and what they are doing on
## the road, if anything.
func show_person(p: Dictionary, doing := "") -> void:
	_clear()
	if p.is_empty():
		note("[i]nicht mehr da[/i]")
		return
	_win.set_title("%s, %d Jahre" % [_who(p.female, float(p.age)), int(p.age)])
	_class = CLASSES.get(p.get("hh_kind", ""), "")
	var lines := PackedStringArray()
	if doing != "":
		lines.append("[color=#%s]%s[/color]" % [UiStyle.GOLD_LIT.to_html(false), doing])
	if int(p.travelling) > 0:
		lines.append("[color=#%s]%s[/color]" % [UiStyle.LOSS.to_html(false), "wandert aus" if int(p.travelling) == 2 else "unterwegs"])
	# a death in the household in the last 60 days (the face mourns too)
	if p.has("loss_days"):
		var ago := int(p.loss_days)
		var when := "heute" if ago == 0 else ("vor 1 Tag" if ago == 1 else "vor %d Tagen" % ago)
		lines.append("[color=#%s]In Trauer: %s im Haushalt %s[/color]" % [UiStyle.DIM.to_html(false), "Hungertod" if bool(p.get("loss_hunger", false)) else "Todesfall", when])
	_note.text = "\n".join(lines)
	_head.visible = true
	_fill_head(p)
	_family(p)
	if p.has("hh_kind"):
		_food(p)
		_work(p)
		_money(p)
	_self(p)

# ------------------------------------------------------------------ the head

func _fill_head(p: Dictionary) -> void:
	var sub := "%s, %s" % [p.job, STANDS[clampi(int(p.stand), 0, 3)]]
	var places := PackedStringArray()
	if _class != "":
		places.append(_class)
	if p.has("market_name"):
		places.append("Markt " + str(p.market_name))
	# the face when the person has genes (portrait_view.gd), else the class
	# medal alone; beside the face the class and the market get a line each
	var face: bool = _portrait.show_person(p)
	if not face:
		places = PackedStringArray(["  ·  ".join(places)])
	_portrait.visible = face
	_badge.visible = face
	_badge.queue_redraw()
	_head.custom_minimum_size.y = PortraitView.SIZE.y + 4.0 if face else MEDAL_R * 2.0 + 10.0
	_head.draw.connect(func():
		var at := Vector2(MEDAL_R + 4.0, _head.size.y * 0.5)
		var x := at.x + MEDAL_R + 14.0
		if face:
			x = PortraitView.SIZE.x + 14.0
		else:
			_medal(_head, at, MEDAL_R, _class, _colour(_class))
		var w := _head.size.x - x
		UiStyle.text_at(_head, Vector2(x, at.y - 6.0), sub, UiStyle.VALUE, UiStyle.SIZE_HEAD + 1, HORIZONTAL_ALIGNMENT_LEFT, w, UiStyle.title_font())
		for k in places.size():
			UiStyle.text_at(_head, Vector2(x, at.y + 18.0 + 20.0 * k), places[k], UiStyle.CONCEPT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, w, UiStyle.serif()))
	_head.queue_redraw()
	Tooltips.attach(_head, func(_at: Vector2) -> Dictionary:
		if _class == "":
			return {}
		return {"id": "person-class:" + _class, "title": _class, "kind": "Schicht", "text": _class_about(_class)})

static func _who(woman: bool, age: float) -> String:
	if age < 14.0:
		return "Mädchen" if woman else "Junge"
	return "Frau" if woman else "Mann"

static func _class_about(name: String) -> String:
	match name:
		"Hofleute": return "Ein Haushalt mit eigenem oder gepachtetem Hof: er isst von seiner Ernte und verkauft, was übrig bleibt."
		"Im Zelt": return "Ein Haushalt ohne Land und ohne festes Haus: er lebt von Taglohn und Almosen."
		"Lohnarbeit": return "Ein Haushalt ohne Land, der von Lohnarbeit oder einem Handwerk lebt und sein Korn am Markt kauft."
		"Händler": return "Ein Haushalt, der Korn und Waren zwischen den Märkten handelt."
		"Oberschicht": return "Ein Haushalt der Oberschicht: Grundherren, Beamte, Offiziere, mit viel Geld."
	return ""

static func _colour(name: String) -> Color:
	var k := SimOverview.FED_NAMES.find(name)
	return SimOverview.FED_COLOURS[k] if k >= 0 else SimOverview.OTHER

# ------------------------------------------------------------------ cards

## A card as the statistics': its title in small caps on a slim band of
## leather with a gold line under it, the rest on the slate.
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
	Tooltips.attach(head, func(_at: Vector2) -> Dictionary: return {"id": "person-card:" + title, "title": title, "kind": "Person", "text": about})
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
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(left)
	var right := UiStyle.label(value, colour, UiStyle.SIZE_TEXT)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(right)
	if about != "":
		Tooltips.attach(line, func(_at: Vector2) -> Dictionary: return {"id": "person-row:" + name, "title": name, "kind": "Person", "text": about})
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
		var x1 := row.size.x - 70.0
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
		UiStyle.text_at(row, Vector2(x1 + 4.0, mid + 5.0), value, UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 62.0, font))
	if about != "":
		Tooltips.attach(row, func(_at: Vector2) -> Dictionary: return {"id": "person-bar:" + name, "title": name, "kind": "Person", "text": about})
	box.add_child(row)

## The household's people, the one shown first lit; spouse and children named.
func _family(p: Dictionary) -> void:
	var fam: Array = p.get("family", [])
	if fam.is_empty():
		return
	var box := _card("Haushalt", "Die Menschen, die mit dieser Person einen Haushalt bilden: sie essen aus einem Vorrat und teilen ihr Geld.")
	var order := fam.duplicate()
	order.sort_custom(func(a, b):
		if int(a.pid) == int(p.pid) or int(b.pid) == int(p.pid):
			return int(a.pid) == int(p.pid)
		return float(a.age) > float(b.age))
	for k in mini(order.size(), FAMILY_MAX):
		var m: Dictionary = order[k]
		var who := _who(m.female, float(m.age))
		var rel := ""
		if int(m.pid) == int(p.pid):
			rel = "diese Person"
		elif int(m.pid) == int(p.spouse):
			rel = "Ehefrau" if m.female else "Ehemann"
		var row := Control.new()
		row.custom_minimum_size = Vector2(0, 26)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var me := int(m.pid) == int(p.pid)
		var job: String = m.job
		var age := int(m.age)
		var away: bool = m.get("travelling", false)
		row.draw.connect(func():
			var font := UiStyle.serif()
			row.draw_rect(Rect2(0, 0, row.size.x, 24), UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK)
			if me:
				row.draw_rect(Rect2(0, 0, 3, 24), UiStyle.GOLD)
			UiStyle.text_at(row, Vector2(10, 18), "%s, %d" % [who, age], UiStyle.VALUE if me else UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, 120.0, font)
			UiStyle.text_at(row, Vector2(130, 18), job + ("  (unterwegs)" if away else ""), UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 240.0, font)
			UiStyle.text_at(row, Vector2(row.size.x - 110.0, 18), rel, UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT, 104.0, UiStyle.italic()))
		box.add_child(row)
	if order.size() > FAMILY_MAX:
		box.add_child(UiStyle.label("und %d weitere" % (order.size() - FAMILY_MAX), UiStyle.DIM, UiStyle.SIZE_SMALL))

func _food(p: Dictionary) -> void:
	var box := _card("Essen", "Was der Haushalt im letzten Monat von seinem Kornbedarf gegessen hat, und was er an Korn im Vorrat hat. Ein Erwachsener braucht etwa 200 kg Korn im Jahr, ein Kind die Hälfte.")
	var fed := float(p.fed) / 1000.0
	_bar_row(box, "Gegessen", fed, "%d %%" % floori(fed * 100.0), UiStyle.GAIN if fed >= 0.95 else UiStyle.LOSS,
		"Anteil seines Kornbedarfs, den der Haushalt beim letzten Zählen gegessen hat. 100 % heisst satt.")
	var need := float(p.get("need_month_kg", 0))
	var pantry := float(p.pantry_kg)
	var lasts := ""
	if need > 0.0:
		var months := pantry / need
		if months < 1.0:
			lasts = "reicht nicht für einen Monat"
		elif months < 1.5:
			lasts = "reicht etwa einen Monat"
		else:
			lasts = "reicht %d Monate" % roundi(months) if months < 24.0 else "reicht über zwei Jahre"
	_row(box, "Vorrat", "%s kg" % SimOverview._num(pantry) + (", " + lasts if lasts != "" else ""))
	_row(box, "Bedarf im Monat", "%s kg" % SimOverview._num(need))
	if p.has("grain_price"):
		_row(box, "Korn am Markt", "%s D/kg" % SimOverview._num(float(p.grain_price)))

func _work(p: Dictionary) -> void:
	var box := _card("Arbeit", "Wovon der Haushalt lebt, und wie viele Tage er an der letzten wöchentlichen Arbeitsbörse seines Marktes bei anderen gearbeitet oder auf seinem Hof Leute eingestellt hat.")
	if p.has("farm_kind"):
		_row(box, str(p.farm_kind), "%s ha Feld" % SimOverview._num(float(p.farm_ha)))
	else:
		_row(box, "Erwerb", CRAFT_NOTES.get(str(p.get("craft", "")), str(p.get("craft", ""))))
	_row(box, "Erwachsene", str(int(p.get("adults", 0))))
	var worked := int(p.get("worked_days", 0))
	var hired := int(p.get("hired_days", 0))
	_row(box, "Diese Woche bei anderen", _days(worked) if worked > 0 else "keine Tage", UiStyle.VALUE if worked > 0 else UiStyle.DIM)
	if p.has("farm_kind"):
		_row(box, "Diese Woche eingestellt", _days(hired) if hired > 0 else "niemand", UiStyle.VALUE if hired > 0 else UiStyle.DIM)
	if p.has("wage"):
		_row(box, "Taglohn am Markt", "%s D" % SimOverview._num(float(p.wage)))
	if float(p.get("earned", 0.0)) > 0.0:
		_row(box, "Verdienst im Monat", "%s D" % SimOverview._num(float(p.earned)), UiStyle.VALUE,
			"Was der Haushalt in einem Monat mit seiner Arbeit verdient, gemittelt über die letzten Monate.")

func _money(p: Dictionary) -> void:
	var box := _card("Geld", "Das Geld des Haushalts in Denar, bei Bauern mit dem Geld ihres Hofs, und wo es steht: gemessen am Geld je Kopf aller Menschen der Karte und seines Marktes.")
	_row(box, "Geld des Haushalts", "%s D" % SimOverview._num(float(p.money)))
	_row(box, "Je Kopf", "%s D" % SimOverview._num(float(p.get("money_head", 0.0))))
	var all := float(p.get("rank_all", 0.0))
	_bar_row(box, "Auf der Karte", all, "%d %%" % floori(all * 100.0), UiStyle.GOLD,
		"Anteil der Menschen der ganzen Karte, die je Kopf weniger Geld haben als dieser Haushalt.")
	if p.has("market_name"):
		var here := float(p.get("rank_market", 0.0))
		_bar_row(box, "Am Markt", here, "%d %%" % floori(here * 100.0), UiStyle.GOLD,
			"Anteil der Menschen am Markt %s, die je Kopf weniger Geld haben als dieser Haushalt." % p.market_name)
	box.add_child(UiStyle.label(_rank_words(all), UiStyle.DIM, UiStyle.SIZE_SMALL))
	var clothes := int(p.get("clothes_pct", 0))
	_row(box, "Kleidung", ("%d %% des Bedarfs" % clothes) if clothes < 100 else "genug", UiStyle.LOSS if clothes < 50 else UiStyle.VALUE,
		"Kleidung, die der Haushalt besitzt, gemessen an dem, was er braucht.")

static func _days(n: int) -> String:
	return "1 Tag" if n == 1 else "%d Tage" % n

static func _rank_words(r: float) -> String:
	if r >= 0.99:
		return "Unter den reichsten 1 % der Menschen."
	if r >= 0.9:
		return "Unter den reichsten 10 % der Menschen."
	if r <= 0.1:
		return "Unter den ärmsten 10 % der Menschen."
	return "Mehr Geld als %d %% der Menschen." % floori(r * 100.0)

func _self(p: Dictionary) -> void:
	var box := _card("Person", "Gesundheit, Herkunft und Zugehörigkeit dieser Person.")
	# health is body weight in per mille of normal weight (S84, 1000 = BMI 21)
	var weight := int(float(p.health) / 10.0)
	_row(box, "Gewicht", "%d %% (BMI %.1f)" % [weight, 21.0 * float(p.health) / 1000.0], UiStyle.LOSS if weight < 85 else UiStyle.VALUE,
		"Körpergewicht gemessen am Normalgewicht (100 % = BMI 21). Wer hungert, nimmt ab.")
	if float(p.iq) >= 0.0:
		_row(box, "IQ", str(roundi(float(p.iq))))
	_row(box, "Kultur, Religion", "%d, %d" % [int(p.culture), int(p.religion)])
	var groups: Array = Array(p.get("factions", []))
	_row(box, "Gruppe", ", ".join(groups) if not groups.is_empty() else str(p.group))
	_row(box, "Haushalt", "Nr. %d, %d Personen" % [int(p.household), int(p.members)], UiStyle.DIM)

# ------------------------------------------------------------------ parts

## A round medal in a gold rim, as the statistics': its class's icon on
## the colour the class keeps in every chart.
func _medal(ci: CanvasItem, at: Vector2, r: float, name: String, colour: Color) -> void:
	ci.draw_circle(at, r + 2.0, UiStyle.EDGE)
	ci.draw_circle(at, r + 1.0, UiStyle.GOLD)
	ci.draw_circle(at, r - 1.5, colour.darkened(0.3))
	if not _icons.has(name):
		_icons[name] = Vic3Style.icon(SimOverview.ICONS[name]) if SimOverview.ICONS.has(name) else null
	var icon: Texture2D = _icons[name]
	if icon != null:
		var side := (r - 5.0) * 2.0
		ci.draw_texture_rect(icon, Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), false, UiStyle.TEXT)
