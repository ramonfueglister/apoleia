extends Control
## The outliner at the right, as Victoria 3's (Ramon, 31.10.2026: "ich
## hätte gerne alles. wunderschön."): under the top bar and above the
## notices, a column of groups that fold open and shut. «Angeheftet» holds
## what the player pinned with a star, by kind (people, markets, farms,
## events); the other groups fill themselves from what the game already
## knows: the farms and fields being built (build_menu.gd sites()) and the
## markets where the most go hungry (the markets table the statistics ask
## for each month, sim_tables.gd). A click on a row opens its window and
## flies there; its star pins or unpins it. O (ui/keys.gd) or the button at
## the left (ui/main_buttons.gd) shows and hides it.
##
## Others pin without a reference to it (the statistics' right-click menu):
## get_tree().call_group("outliner", "pin", kind, id, name) with kind
## "person" (pid), "market" (market index), "farm" (farm index) or "event"
## (any id; a fifth argument, the world point, is where it flies), and
## "unpin" with kind and id. The pins, the groups left open and whether it
## is shown are kept in user://outliner.cfg.

const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const TopBar = preload("res://scripts/ui/top_bar.gd")
const NoticeList = preload("res://scripts/ui/notice_list.gd")
const STORE := "user://outliner.cfg"
const WIDTH := NoticeList.WIDTH
const MARGIN := 18.0 # from the right edge, as the notices (sim/sim_events.gd)
const HEAD_PX := 36.0
const ROW_PX := 30.0
const GAP := 3.0
const REFRESH_S := 1.0
const HUNGRY_MAX := 5
const HUNGRY_MIN_PERSONS := 50 # a market smaller than this is not listed for its hunger
const HUNGRY_MIN_SHARE := 0.02
const SITES_MAX := 8
const SITE_KM := 8.0 # the view width a site is shown at
const MARKET_KM := 90.0
const EVENT_KM := 12.0
const KINDS: Array[String] = ["person", "market", "farm", "event"]
const KIND_NAMES := {"person": "Menschen", "market": "Märkte", "farm": "Höfe", "event": "Ereignisse"}
const KIND_ICONS := {"person": "person", "market": "wheat", "farm": "barn", "event": "scroll-quill"}
const BUILD_NAMES: Array[String] = ["Hof", "Felder", "Strasse"] # build_menu.gd FARM, FIELD, ROAD
const BUILD_ICONS: Array[String] = ["house", "plow", "horizon-road"]

var dots: Node # people_dots.gd: the people's windows
var tables: Node # sim_tables.gd: the markets table
var landscape: Node3D
var _pins: Array[Dictionary] = [] # {kind, id, name, at}
var _open := {"pins": true, "sites": true, "hungry": true} # group -> folded open
var _shown := true
var _head: Row
var _scroll: ScrollContainer
var _list: VBoxContainer
var _clock := REFRESH_S
var _signature := ""
var _market_of := {} # a site's world point -> its market, asked of the sim once

func _init() -> void:
	name = "Outliner"
	add_to_group("outliner")
	theme = Vic3.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head = Row.new()
	_head.band = true
	_head.label = "Im Blick"
	_head.custom_minimum_size = Vector2(WIDTH, HEAD_PX)
	_head.tooltip_text = "Auf- und zuklappen  (O blendet aus)"
	_head.chosen.connect(_fold_all)
	add_child(_head)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.position = Vector2(0, HEAD_PX + GAP)
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", int(GAP))
	_list.custom_minimum_size.x = WIDTH
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)
	_load()

func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	visible = _shown
	_rebuild()

## Pins `id` of `kind` with its `name`; `at` the world point an event flies to.
func pin(kind: String, id: int, label: String, at := Vector2.INF) -> void:
	for p in _pins:
		if p.kind == kind and p.id == id:
			p.name = label
			_changed()
			return
	_pins.append({"kind": kind, "id": id, "name": label, "at": at})
	_open["pins"] = true
	_open["pins:" + kind] = true
	_changed()

func unpin(kind: String, id: int) -> void:
	var kept: Array[Dictionary] = []
	for p in _pins:
		if not (p.kind == kind and p.id == id):
			kept.append(p)
	_pins = kept
	_changed()

func is_pinned(kind: String, id: int) -> bool:
	for p in _pins:
		if p.kind == kind and p.id == id:
			return true
	return false

## Shown or hidden (O, the button at the left).
func toggle() -> void:
	_shown = not _shown
	visible = _shown
	_save()

func _changed() -> void:
	_save()
	_signature = ""
	_rebuild()

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= REFRESH_S and visible:
		_clock = 0.0
		_rebuild()
		_fit() # the notices below grow and shrink

# ------------------------------------------------------------------ rows

## The groups anew when what they show changed.
func _rebuild() -> void:
	var groups := _groups()
	var signature := var_to_str(groups) + var_to_str(_open)
	if signature == _signature:
		return
	_signature = signature
	for c in _list.get_children():
		c.free()
	_head.count = -1
	_head.folded = not _open.get("all", true)
	_head.queue_redraw()
	if _open.get("all", true):
		for g in groups:
			_add_group(g)
	_fit.call_deferred()

## What each group shows now: {key, name, icon, rows: [{...}], subs: [...]}.
func _groups() -> Array:
	var markets := _markets()
	var pinned := []
	for kind in KINDS:
		var rows := []
		for p in _pins:
			if p.kind == kind:
				rows.append({"label": p.name, "icon": KIND_ICONS[kind], "value": _pin_value(p, markets),
					"star": 1, "pin": p})
		if not rows.is_empty():
			pinned.append({"key": "pins:" + kind, "name": KIND_NAMES[kind], "rows": rows})
	var out := [{"key": "pins", "name": "Angeheftet", "star": true, "count": _pins.size(), "subs": pinned,
		"empty": "Mit dem Stern anheften: Menschen, Märkte, Höfe, Ereignisse."}]
	var sites := _sites(markets)
	out.append({"key": "sites", "name": "Baustellen", "count": sites.size(), "rows": sites,
		"empty": "Nichts im Bau. Bauen links unten."})
	var hungry := _hungry(markets)
	out.append({"key": "hungry", "name": "Hunger auf den Märkten", "count": hungry.size(), "rows": hungry,
		"empty": "Kein Markt, auf dem viele hungern." if not markets.is_empty() else "Die Märkte werden gezählt …"})
	return out

func _add_group(g: Dictionary) -> void:
	var open: bool = _open.get(g.key, true)
	var head := Row.new()
	head.head = true
	head.label = g.name
	head.count = g.count
	head.folded = not open
	head.chosen.connect(_fold.bind(g.key))
	_list.add_child(head)
	if not open:
		return
	var subs: Array = g.get("subs", [])
	var rows: Array = g.get("rows", [])
	if subs.is_empty() and rows.is_empty():
		var hint := Row.new()
		hint.hint = true
		hint.label = g.empty
		_list.add_child(hint)
	for s in subs:
		var sub_open: bool = _open.get(s.key, true)
		var sub := Row.new()
		sub.head = true
		sub.depth = 1
		sub.label = s.name
		sub.count = s.rows.size()
		sub.folded = not sub_open
		sub.chosen.connect(_fold.bind(s.key))
		_list.add_child(sub)
		if sub_open:
			for r in s.rows:
				_add_row(r, 2)
	for r in rows:
		_add_row(r, 1)

func _add_row(r: Dictionary, depth: int) -> void:
	var row := Row.new()
	row.depth = depth
	row.label = r.label
	row.value = r.get("value", "")
	row.icon_tex = Vic3.icon(r.icon)
	row.star = r.get("star", -1)
	row.share = r.get("share", -1.0)
	row.tooltip_text = r.get("tip", "")
	row.chosen.connect(_choose.bind(r))
	if row.star >= 0:
		row.starred.connect(_star.bind(r))
	_list.add_child(row)

func _fold(key: String) -> void:
	_open[key] = not _open.get(key, true)
	_changed()

func _fold_all() -> void:
	_open["all"] = not _open.get("all", true)
	_changed()

## A row clicked: its window, and the view on it.
func _choose(r: Dictionary) -> void:
	if r.has("pin"):
		var p: Dictionary = r.pin
		match p.kind:
			"person":
				if dots != null and dots.has_method("_show_household"):
					dots._show_household(p.id, -1)
			"market":
				_open_market(p.id)
			"farm":
				get_tree().call_group("farm_window", "open", p.id)
			"event":
				if p.at is Vector2 and p.at != Vector2.INF:
					_fly(p.at, EVENT_KM)
	elif r.has("market"):
		_open_market(r.market)
	elif r.has("at"):
		_fly(r.at, SITE_KM)

func _star(r: Dictionary) -> void:
	if r.has("pin"):
		unpin(r.pin.kind, r.pin.id)
	elif r.has("market"):
		if is_pinned("market", r.market):
			unpin("market", r.market)
		else:
			pin("market", r.market, r.label)

func _open_market(m: int) -> void:
	get_tree().call_group("market_window", "open", m)
	if get_tree().get_nodes_in_group("market_window").is_empty() and landscape != null:
		for c in landscape.get_children(): # before the market window joined its group
			if c.has_method("open") and c.get_script() != null and c.get_script().resource_path.ends_with("market_window.gd"):
				c.open(m)
	var at := _market_at(m)
	if at != Vector2.INF:
		_fly(at, MARKET_KM)

func _fly(at: Vector2, width_km: float) -> void:
	if landscape == null or not "_goal_target" in landscape:
		return
	landscape._goal_target = at
	landscape._goal_width = width_km

# ------------------------------------------------------------------ sources

## The markets table of the statistics' last monthly count, {} before it.
func _markets() -> Dictionary:
	if tables == null or not "_tables" in tables or tables._tables.is_empty():
		return {}
	var t: Dictionary = tables._tables[0]
	if t.is_empty() or not t.has("data"):
		return {}
	var d: Dictionary = t.data
	return d if d.has("id") and d.has("persons") else {}

func _row_of(markets: Dictionary, m: int) -> int:
	if markets.is_empty():
		return -1
	return Array(markets.id).find(m)

func _market_at(m: int) -> Vector2:
	var d := _markets()
	var r := _row_of(d, m)
	if r < 0 or not d.has("lon") or landscape == null:
		return Vector2.INF
	return landscape.lonlat_to_world(float(d.lon[r]), float(d.lat[r]))

func _pin_value(p: Dictionary, markets: Dictionary) -> String:
	if p.kind == "market":
		var r := _row_of(markets, p.id)
		if r >= 0 and markets.has("share_hungry"):
			return "%d %% hungernd" % roundi(100.0 * float(markets.share_hungry[r]))
	return ""

## The markets where the largest share went hungry last month.
func _hungry(markets: Dictionary) -> Array:
	if markets.is_empty() or not markets.has("share_hungry"):
		return []
	var rows := []
	for r in markets.id.size():
		var share := float(markets.share_hungry[r])
		if int(markets.persons[r]) >= HUNGRY_MIN_PERSONS and share >= HUNGRY_MIN_SHARE:
			rows.append(r)
	rows.sort_custom(func(a, b): return float(markets.share_hungry[a]) > float(markets.share_hungry[b]))
	var out := []
	for r in rows.slice(0, HUNGRY_MAX):
		var m := int(markets.id[r])
		out.append({"label": str(markets.region[r]), "icon": "knife-fork", "market": m,
			"value": "%d %%" % roundi(100.0 * float(markets.share_hungry[r])),
			"star": 1 if is_pinned("market", m) else 0,
			"tip": "%s Menschen, %d %% wurden im letzten Monat nicht satt." % [_amount(int(markets.persons[r])), roundi(100.0 * float(markets.share_hungry[r]))]})
	return out

## The farms being built one by one, the fields together by market.
func _sites(markets: Dictionary) -> Array:
	var build: Node = landscape.get_node_or_null("BuildMenu") if landscape != null else null
	if build == null or not build.has_method("sites"):
		return []
	var people: RefCounted = dots.people if dots != null and "people" in dots else null
	var farms := []
	var fields := {} # market -> {n, done, at}
	for s: Dictionary in build.sites():
		if not _market_of.has(s.at):
			if _market_of.size() > 20000:
				_market_of.clear()
			_market_of[s.at] = people.market_at(s.at.x, s.at.y) if people != null and people.has_method("market_at") else -1
		var m: int = _market_of[s.at]
		var place := _place_name(markets, m)
		if s.kind == 1:
			if not fields.has(m):
				fields[m] = {"n": 0, "done": 0.0, "at": s.at, "place": place}
			fields[m].n += 1
			fields[m].done += s.share
		else:
			farms.append({"label": "%s%s" % [BUILD_NAMES[s.kind], " bei " + place if place != "" else ""], "icon": BUILD_ICONS[s.kind],
				"at": s.at, "share": s.share, "value": "%d %%" % roundi(100.0 * s.share) if s.share > 0.0 else "wartet",
				"tip": "Taglöhner aus der Staatskasse bauen ihn (S113)."})
	for m in fields:
		var f: Dictionary = fields[m]
		var share: float = f.done / f.n
		farms.append({"label": "%d Felder%s" % [f.n, " bei " + f.place if f.place != "" else ""], "icon": "plow",
			"at": f.at, "share": share, "value": "%d %%" % roundi(100.0 * share) if share > 0.0 else "wartet"})
	return farms.slice(0, SITES_MAX)

func _place_name(markets: Dictionary, m: int) -> String:
	var r := _row_of(markets, m)
	return str(markets.region[r]) if r >= 0 and markets.has("region") else ""

static func _amount(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "'" + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out

# ------------------------------------------------------------------ place

## Under the top bar at the right, down to the notices (or the foot).
func _fit() -> void:
	var screen := get_viewport_rect().size
	var top := TopBar.HEIGHT + 14.0
	var bottom := screen.y - 16.0
	var notices := get_tree().get_first_node_in_group("notice_list") as Control
	if notices != null and notices.is_visible_in_tree():
		bottom = minf(bottom, notices.get_global_rect().position.y - 12.0)
	var room := maxf(bottom - top - HEAD_PX - GAP, ROW_PX * 2.0)
	var tall := minf(_list.get_combined_minimum_size().y, room)
	position = Vector2(screen.x - WIDTH - MARGIN, top)
	size = Vector2(WIDTH, HEAD_PX + GAP + tall)
	_scroll.size = Vector2(WIDTH, tall)

# ------------------------------------------------------------------ store

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(STORE) != OK:
		return
	_shown = bool(config.get_value("outliner", "shown", true))
	var open: Variant = config.get_value("outliner", "open", {})
	if open is Dictionary:
		_open.merge(open, true)
	var pins: Variant = config.get_value("outliner", "pins", [])
	if pins is Array:
		for p in pins:
			if p is Dictionary and p.has("kind") and p.has("id"):
				var at: Variant = p.get("at")
				_pins.append({"kind": str(p.kind), "id": int(p.id), "name": str(p.get("name", "?")), "at": at if at is Vector2 else Vector2.INF})

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("outliner", "shown", _shown)
	config.set_value("outliner", "open", _open)
	var pins := []
	for p in _pins: # no infinite points in the file
		pins.append({"kind": p.kind, "id": p.id, "name": p.name, "at": p.at if p.at is Vector2 and p.at.is_finite() else null})
	config.set_value("outliner", "pins", pins)
	config.save(STORE)

## One line of the outliner: the band at its top, a group's head, a row
## (icon, name, value, star, a bar of how far it got) or a hint. Drawn, not
## built of controls, so a column of them stays light.
class Row extends Control:
	const STAR_W := 30.0
	const INDENT := 14.0
	signal chosen
	signal starred
	var band := false
	var head := false
	var hint := false
	var folded := false
	var depth := 0
	var label := ""
	var value := ""
	var count := -1
	var star := -1 # -1 none, 0 not pinned, 1 pinned
	var share := -1.0 # a bar under the row, 0 … 1
	var icon_tex: Texture2D
	var _hover := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 30)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))

	func _set_hover(on: bool) -> void:
		_hover = on
		queue_redraw()

	func _ready() -> void:
		if hint:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if star >= 0 and event.position.x > size.x - STAR_W:
				starred.emit()
			else:
				chosen.emit()
			accept_event()

	func _draw() -> void:
		var style: GDScript = load("res://scripts/ui/vic3_style.gd")
		var x0 := depth * INDENT
		var r := Rect2(x0, 0, size.x - x0, size.y)
		var font: Font = style.bold() if head or band else style.serif()
		var font_size := 17 if band else (15 if head else 15)
		if band:
			style.draw_band(self, r)
			draw_rect(r, style.GOLD_DIM, false, 1.0)
			_text(font, Vector2(r.position.x + 34, 0), label, style.TEXT, font_size, r.size.x - 60, true)
			_chevron(Vector2(r.position.x + 16, size.y * 0.5), style.GOLD_LIT if _hover else style.GOLD)
			return
		var board := StyleBoxFlat.new()
		board.set_corner_radius_all(3)
		board.anti_aliasing = true
		if head:
			board.bg_color = Color("1a201f", 0.94).lightened(0.06 if _hover else 0.0)
			board.border_color = Color(style.GOLD_DIM, 0.7)
			board.border_width_bottom = 1
		elif hint:
			board.bg_color = Color("1a201f", 0.7)
		else:
			board.bg_color = Color(style.LEAF, 0.93).lightened(0.08 if _hover else 0.0)
			board.border_color = Color(style.GOLD_LIT, 0.6) if _hover else Color(0, 0, 0, 0)
			board.set_border_width_all(1)
		draw_style_box(board, r)
		var left := r.position.x + 10
		if head:
			_chevron(Vector2(left + 6, size.y * 0.5), style.GOLD_LIT if _hover else style.GOLD)
			left += 20
		elif icon_tex != null:
			draw_texture_rect(icon_tex, Rect2(left, size.y * 0.5 - 10, 20, 20), false, style.GOLD)
			left += 28
		var right := size.x - (STAR_W if star >= 0 else 10.0)
		var count_text := str(count) if head and count >= 0 else value
		if count_text != "":
			var w: float = style.serif().get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			_text(style.serif(), Vector2(right - w - 4, 0), count_text, style.DIM if head else style.TEXT, 14, w + 2, false)
			right -= w + 14
		var colour: Color = style.DIM if hint else (style.GOLD_LIT if head else style.TEXT)
		_text(font, Vector2(left, 0), label, colour, 13 if hint else font_size, right - left, false)
		if share >= 0.0:
			var bar := Rect2(r.position.x + 38, size.y - 6, r.size.x - 38 - STAR_W - 10, 3)
			draw_rect(bar, Color(0, 0, 0, 0.5))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(share, 0.0, 1.0), bar.size.y)), style.GOLD)
		if star >= 0:
			_star(Vector2(size.x - STAR_W * 0.5, size.y * 0.5), 8.0, star == 1, style)

	## `text` from `at` (top left), cut with an ellipsis to `room`.
	func _text(font: Font, at: Vector2, text: String, colour: Color, font_size: int, room: float, caps: bool) -> void:
		var t := text.to_upper() if caps else text
		while t.length() > 1 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
			t = t.left(t.length() - 2) + "…"
		var y := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
		draw_string(font, Vector2(at.x + 1, y + 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(at.x, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)

	## ▸ shut, ▾ open.
	func _chevron(c: Vector2, colour: Color) -> void:
		var d := 5.0
		var pts := PackedVector2Array([c + Vector2(-d * 0.6, -d), c + Vector2(d * 0.8, 0), c + Vector2(-d * 0.6, d)]) if folded \
			else PackedVector2Array([c + Vector2(-d, -d * 0.6), c + Vector2(d, -d * 0.6), c + Vector2(0, d * 0.8)])
		draw_colored_polygon(pts, colour)

	## A five-pointed star: filled gold when pinned, an outline when not.
	func _star(c: Vector2, radius: float, on: bool, style: GDScript) -> void:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (radius if k % 2 == 0 else radius * 0.45))
		if on:
			draw_colored_polygon(pts, style.GOLD_LIT if _hover else style.GOLD)
		else:
			pts.append(pts[0])
			draw_polyline(pts, style.GOLD_LIT if _hover else style.GOLD_DIM, 1.5, true)
