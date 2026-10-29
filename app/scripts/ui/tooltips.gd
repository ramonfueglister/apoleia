extends CanvasLayer
## Tooltips in the manner of EU5 (and CK3, whose system it took): a tooltip
## shows after SHOW_S over anything that has one; staying LOCK_S fills the
## gold ring at its corner and locks it. A locked tooltip stays where it is,
## shows its "more" part (a curve, a breakdown), and can be entered with the
## mouse: its underlined terms open tooltips of their own, nested as deep as
## the terms go. Leaving a locked tooltip closes it after GRACE_S, so the
## mouse may cross a gap.
##
## Anything gets a tooltip with
##   Tooltips.attach(control, func(at: Vector2) -> Dictionary)
## where `at` is the mouse in the control and the answer is {} for none or
##   id     what is under the mouse (a new id is a new tooltip)
##   title  the head
##   kind   what sort of thing it is, in blue italics below ("Marktpreis")
##   text   BBCode (see _text): [url=term]word[/url] a term of the glossary
##   rows   [[label, value], …] in a striped box, "+…" green, "−…" red
##          (a third entry overrides the value's colour)
##   spark  PackedFloat64Array drawn in the locked part, EU5's "recent
##          price" box: spark_title, spark_lo/spark_hi a band around it,
##          spark_from/spark_to the first and last month, spark_unit, colour
##   more   BBCode shown only once locked
##   hints  [[key, what it does], …] at the foot ("Klick", "fliegt hin")
## and a term of the glossary with Tooltips.term(name, func() -> Dictionary).

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Charts = preload("res://scripts/ui/charts.gd")
const LAYER := 20 # over every window
const SHOW_S := 0.25
const LOCK_S := 1.0
const GRACE_S := 0.25
const WIDTH := 320.0
const OFFSET := Vector2(18, 22)
const SPARK := Vector2(WIDTH - 24.0, 46.0)

static var _shared: CanvasLayer
static var _terms := {}

var _stack: Array[Dictionary] = [] # open tooltips, outermost first
var _pending := {} # {id, depth, since}
var _just_closed := -10.0 # when the outermost tooltip last closed

static func attach(control: Control, provider: Callable) -> void:
	control.set_meta("tooltip", provider)
	_ensure(control.get_tree() if control.is_inside_tree() else Engine.get_main_loop() as SceneTree)

static func term(name: String, provider: Callable) -> void:
	_terms[name] = provider

static func _ensure(tree: SceneTree) -> void:
	if is_instance_valid(_shared) or tree == null:
		return
	_shared = load("res://scripts/ui/tooltips.gd").new()
	_shared.name = "Tooltips"
	_shared.layer = LAYER
	tree.root.add_child.call_deferred(_shared)

func _process(_delta: float) -> void:
	var vp := get_viewport()
	var mouse := vp.get_mouse_position()
	var now := Time.get_ticks_msec() / 1000.0
	# the deepest locked tooltip the mouse is in
	var inside := -1
	for i in range(_stack.size() - 1, -1, -1):
		if _stack[i].locked and _stack[i].panel.get_global_rect().grow(6.0).has_point(mouse):
			inside = i
			break
	var want := {} # what the mouse asks for at depth inside + 1
	var depth := inside + 1
	if inside >= 0:
		var hovered: String = _stack[inside].term
		if hovered != "" and _terms.has(hovered):
			want = _terms[hovered].call()
			want["id"] = "term:" + hovered
	else:
		var c := vp.gui_get_hovered_control()
		while c != null and not c.has_meta("tooltip"):
			c = c.get_parent() as Control
		if c != null and not _in_tooltip(c):
			want = c.get_meta("tooltip").call(c.get_local_mouse_position())
	# keep what is wanted and what the mouse just left (for GRACE_S)
	for i in range(_stack.size() - 1, depth - 1, -1):
		var e: Dictionary = _stack[i]
		var same: bool = i == depth and not want.is_empty() and want.get("id", want.get("title", "")) == e.id
		if same:
			e.away = -1.0
			continue
		if e.away < 0.0:
			e.away = now
		if not e.locked or now - e.away > GRACE_S:
			_close(i)
	# the tooltip wanted, now or after SHOW_S
	if want.is_empty():
		_pending = {}
	elif _stack.size() <= depth:
		var id = want.get("id", want.get("title", ""))
		if _pending.is_empty() or _pending.id != id or _pending.depth != depth:
			_pending = {"id": id, "depth": depth, "since": now}
		# moving from one row to the next shows the next at once, as EU5 does
		if now - _pending.since >= SHOW_S or (depth == 0 and _just_closed > now - 0.1):
			_open(want, depth, mouse)
			_pending = {}
	# the ring fills, then the tooltip locks
	for e in _stack:
		if not e.locked:
			var f: float = (now - e.opened) / LOCK_S
			e.ring.set_meta("f", minf(f, 1.0))
			e.ring.queue_redraw()
			if f >= 1.0:
				_lock(e)

func _in_tooltip(c: Control) -> bool:
	for e in _stack:
		if e.panel.is_ancestor_of(c) or e.panel == c:
			return true
	return false

func _close(i: int) -> void:
	while _stack.size() > i:
		var e: Dictionary = _stack.pop_back()
		e.panel.queue_free()
	if i == 0:
		_just_closed = Time.get_ticks_msec() / 1000.0

func _open(d: Dictionary, _depth: int, mouse: Vector2) -> void:
	var panel := PanelContainer.new()
	panel.theme = UiStyle.theme()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _frame(false))
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	# the head: title, below it the kind of thing in blue italics, the ring
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(titles)
	var title := _label(d.get("title", ""), UiStyle.TITLE, UiStyle.SIZE_HEAD)
	title.add_theme_font_override("font", _bold())
	titles.add_child(title)
	if d.get("kind", "") != "":
		var kind := _label(d.kind, UiStyle.CONCEPT, UiStyle.SIZE_SMALL + 1)
		kind.add_theme_font_override("font", _italic())
		titles.add_child(kind)
	var ring := Control.new()
	ring.custom_minimum_size = Vector2(16, 16)
	ring.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func():
		var f: float = ring.get_meta("f", 0.0)
		var c := Vector2(8, 8)
		ring.draw_arc(c, 6.0, 0.0, TAU, 32, Color(UiStyle.FRAME, 0.6), 2.0, true)
		if f > 0.0:
			ring.draw_arc(c, 6.0, -PI / 2.0, -PI / 2.0 + TAU * f, 32, UiStyle.FRAME_LIT, 2.0, true))
	head.add_child(ring)
	var rule := ColorRect.new()
	rule.color = Color(UiStyle.FRAME, 0.5)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var e := {"panel": panel, "ring": ring, "id": d.get("id", d.get("title", "")), "locked": false,
		"opened": Time.get_ticks_msec() / 1000.0, "away": -1.0, "term": "", "texts": [], "more": null}
	# the body: a sentence, then the rows in a sunken box, striped
	var rows: Array = d.get("rows", [])
	if d.get("text", "") != "" or not rows.is_empty():
		var box := _inset()
		column.add_child(box)
		var inner: VBoxContainer = box.get_child(0)
		if d.get("text", "") != "":
			inner.add_child(_text(d.text, e))
		for i in rows.size():
			inner.add_child(_row(rows[i], i))
	# the locked part: the curve and what more there is
	var more := VBoxContainer.new()
	more.visible = false
	more.add_theme_constant_override("separation", 8)
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(more)
	e.more = more
	if d.has("spark") and d.spark.size() > 1:
		more.add_child(_chart(d))
	if d.get("more", "") != "":
		var box := _inset()
		box.get_child(0).add_child(_text(d.more, e))
		more.add_child(box)
	for hint in d.get("hints", []): # [what to press, what it does]
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := _label(hint[0], UiStyle.NAME, UiStyle.SIZE_SMALL)
		key.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.HEADER, UiStyle.FRAME, 1, 3, 3))
		line.add_child(key)
		line.add_child(_label(hint[1], UiStyle.DIM, UiStyle.SIZE_SMALL))
		column.add_child(line)
	_stack.append(e)
	panel.reset_size()
	_place(panel, mouse)

## A row of a breakdown: name left, value right; "+" values green, "−" red.
func _row(r: Array, i: int) -> Control:
	var back := PanelContainer.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stripe := UiStyle.box(UiStyle.STRIPE if i % 2 == 0 else Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0)
	stripe.content_margin_left = 6
	stripe.content_margin_right = 6
	stripe.content_margin_top = 2
	stripe.content_margin_bottom = 2
	back.add_theme_stylebox_override("panel", stripe)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(line)
	var a := _label(str(r[0]), UiStyle.TEXT, UiStyle.SIZE_TEXT)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(a)
	var v := str(r[1])
	var colour: Color = r[2] if r.size() > 2 else (UiStyle.GAIN if v.begins_with("+") else (UiStyle.LOSS if v.begins_with("−") or v.begins_with("-") else UiStyle.TEXT))
	var b := _label(v, colour, UiStyle.SIZE_TEXT)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(b)
	return back

## "Letzte Monate" as EU5's "Recent Market Price": the highest and lowest
## value at the left, the first and last month at the foot.
func _chart(d: Dictionary) -> Control:
	var box := _inset()
	var inner: VBoxContainer = box.get_child(0)
	var head := _label(d.get("spark_title", "Verlauf"), UiStyle.TEXT, UiStyle.SIZE_TEXT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(head)
	var values: PackedFloat64Array = d.spark
	var lo := PackedFloat64Array(d.get("spark_lo", PackedFloat64Array()))
	var hi := PackedFloat64Array(d.get("spark_hi", PackedFloat64Array()))
	var top := -INF
	var bottom := INF
	for v in values + lo + hi:
		top = maxf(top, v)
		bottom = minf(bottom, v)
	var unit: String = d.get("spark_unit", "")
	var chart := Control.new()
	chart.custom_minimum_size = SPARK
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart.draw.connect(func():
		var r := Rect2(Vector2.ZERO, chart.size)
		chart.draw_rect(r, Color(0, 0, 0, 0.25))
		for k in 5: # a faint grid
			var y := r.size.y * k / 4.0
			chart.draw_line(Vector2(0, y), Vector2(r.size.x, y), Charts.GRID, 1.0)
		Charts.spark(chart, r.grow(-4.0), values, d.get("colour", Charts.SERIES[0]), lo, hi)
		var font := UiStyle.serif()
		chart.draw_string(font, Vector2(6, 16), _short(top) + unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_SMALL, UiStyle.TEXT)
		chart.draw_string(font, Vector2(6, r.size.y - 6), _short(bottom) + unit, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_SMALL, UiStyle.TEXT))
	inner.add_child(chart)
	if d.has("spark_from"):
		var foot := HBoxContainer.new()
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var from := _label(d.spark_from, UiStyle.DIM, UiStyle.SIZE_SMALL)
		from.add_theme_font_override("font", _italic())
		from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(from)
		var to := _label(d.get("spark_to", ""), UiStyle.DIM, UiStyle.SIZE_SMALL)
		to.add_theme_font_override("font", _italic())
		foot.add_child(to)
		inner.add_child(foot)
	return box

static func _short(v: float) -> String:
	var a := absf(v)
	if a >= 1.0e6:
		return "%.1f Mio " % (v / 1.0e6)
	if a >= 1000.0:
		return "%dk " % roundi(v / 1000.0)
	if a >= 10.0:
		return "%d " % roundi(v)
	return ("%.2f " % v) if a >= 0.1 else ("%.3f " % v)

func _inset() -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UiStyle.inset(6))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	inner.custom_minimum_size = Vector2(WIDTH, 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(inner)
	return box

## BBCode with EU5's colours: [url=term]…[/url] a concept in blue (with a
## tooltip of its own), [n]…[/n] a name in pale gold, [+]…[/+] a gain,
## [-]…[/-] a loss.
func _text(bbcode: String, e: Dictionary) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(WIDTH, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.meta_underlined = false
	t.add_theme_color_override("default_color", UiStyle.TEXT)
	t.add_theme_font_override("normal_font", UiStyle.serif())
	t.add_theme_font_size_override("normal_font_size", UiStyle.SIZE_TEXT)
	var c := func(colour: Color) -> String: return "[color=#%s]" % colour.to_html(false)
	t.text = (bbcode.replace("[url=", c.call(UiStyle.CONCEPT) + "[url=").replace("[/url]", "[/url][/color]")
		.replace("[n]", c.call(UiStyle.NAME)).replace("[/n]", "[/color]")
		.replace("[+]", c.call(UiStyle.GAIN)).replace("[/+]", "[/color]")
		.replace("[-]", c.call(UiStyle.LOSS)).replace("[/-]", "[/color]"))
	t.meta_hover_started.connect(func(meta): e.term = str(meta))
	t.meta_hover_ended.connect(func(_meta): e.term = "")
	e.texts.append(t)
	return t

static func _label(text: String, colour: Color, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static var _bold_font: FontVariation
static var _italic_font: FontVariation

static func _bold() -> Font:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = UiStyle.serif()
		_bold_font.variation_embolden = 0.6
	return _bold_font

static func _italic() -> Font:
	if _italic_font == null:
		_italic_font = FontVariation.new()
		_italic_font.base_font = UiStyle.serif()
		_italic_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	return _italic_font

static func _frame(lit: bool) -> StyleBoxFlat:
	var b := UiStyle.frame(lit)
	b.bg_color = Color("141b22", 0.98)
	b.set_content_margin_all(12)
	return b

func _lock(e: Dictionary) -> void:
	e.locked = true
	e.panel.mouse_filter = Control.MOUSE_FILTER_STOP
	e.panel.add_theme_stylebox_override("panel", _frame(true))
	for t in e.texts:
		t.mouse_filter = Control.MOUSE_FILTER_PASS
	e.more.visible = true
	e.panel.reset_size()
	var screen := get_viewport().get_visible_rect().size
	e.panel.position = e.panel.position.clamp(Vector2(8, 8), (screen - e.panel.get_combined_minimum_size() - Vector2(8, 8)).max(Vector2(8, 8)))

## Below right of the mouse, inside the screen.
func _place(panel: Control, mouse: Vector2) -> void:
	var screen := get_viewport().get_visible_rect().size
	var extent := panel.get_combined_minimum_size()
	var at := mouse + OFFSET
	if at.x + extent.x > screen.x - 8.0:
		at.x = mouse.x - extent.x - 8.0
	if at.y + extent.y > screen.y - 8.0:
		at.y = maxf(8.0, screen.y - extent.y - 8.0)
	panel.position = at.max(Vector2(8, 8))
