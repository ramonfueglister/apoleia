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
##   spark  PackedFloat64Array drawn below the rows at once, as EU5's
##          "recent price" box: spark_title, spark_lo/spark_hi a band around
##          it, spark_from/spark_to the first and last month, spark_unit,
##          colour, spark_ref a dashed level to compare with
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
const SPARK := Vector2(WIDTH, 120.0)

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
	_ensure(Engine.get_main_loop() as SceneTree) # so the layer is there to clear them

## The terms' lambdas belong to other scripts: drop them while those still
## live. The layer hangs on the root and goes in SceneTree.finalize, before
## Godot frees the scripts; a lambda freed after its script crashes the quit
## (Godot #102569: "recursive_mutex lock failed" on macOS, exit 134).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and self == _shared:
		_terms.clear()

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
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	# the head as EU5's: a brown band, the title bold, below it the kind
	# of thing in blue italics, a gold rule under it; the ring at the right
	var head_back := PanelContainer.new()
	head_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head_box := UiStyle.box(UiStyle.TIP_HEAD, UiStyle.GOLD, 0, 0, 0)
	head_box.border_width_bottom = 2
	head_box.content_margin_left = 12
	head_box.content_margin_right = 10
	head_box.content_margin_top = 6
	head_box.content_margin_bottom = 7
	head_back.add_theme_stylebox_override("panel", head_box)
	column.add_child(head_back)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_back.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(titles)
	titles.add_child(UiStyle.label(d.get("title", ""), Color("f8f1e6"), UiStyle.SIZE_HEAD, UiStyle.bold()))
	if d.get("kind", "") != "":
		titles.add_child(UiStyle.label(d.kind, UiStyle.KIND, UiStyle.SIZE_SMALL + 1, UiStyle.italic()))
	var ring := Control.new()
	ring.custom_minimum_size = Vector2(18, 18)
	ring.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func():
		var f: float = ring.get_meta("f", 0.0)
		var c := Vector2(9, 9)
		ring.draw_arc(c, 6.5, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 4.0, true)
		ring.draw_arc(c, 6.5, 0.0, TAU, 32, Color(UiStyle.GOLD, 0.45), 2.0, true)
		if f > 0.0:
			ring.draw_arc(c, 6.5, -PI / 2.0, -PI / 2.0 + TAU * f, 32, UiStyle.GOLD_LIT, 2.0, true))
	head.add_child(ring)
	var e := {"panel": panel, "ring": ring, "id": d.get("id", d.get("title", "")), "locked": false,
		"opened": Time.get_ticks_msec() / 1000.0, "away": -1.0, "term": "", "texts": [], "more": null}
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 9)
	pad.add_child(main)
	column.add_child(pad)
	# the body: a sentence, then the rows in a sunken box of alternating bars
	if d.get("text", "") != "":
		main.add_child(_text(d.text, e))
	var rows: Array = d.get("rows", [])
	if not rows.is_empty():
		var box := _inset()
		main.add_child(box)
		var inner: VBoxContainer = box.get_child(0)
		for i in rows.size():
			inner.add_child(_row(rows[i], i))
	# the curve at once, as EU5 shows a good's recent price
	if d.has("spark") and d.spark.size() > 1:
		main.add_child(_chart(d))
	# the locked part: what more there is
	var more := VBoxContainer.new()
	more.visible = false
	more.add_theme_constant_override("separation", 8)
	more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(more)
	e.more = more
	if d.get("more", "") != "":
		var box := _inset(8)
		box.get_child(0).add_child(_text(d.more, e))
		more.add_child(box)
	var hints: Array = d.get("hints", [])
	if not hints.is_empty(): # [what to press, what it does], EU5's foot line
		var foot := HFlowContainer.new()
		foot.add_theme_constant_override("h_separation", 14)
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for hint in hints:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 5)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# the key as EU5's gold keycap with dark letters
			var key := UiStyle.label(hint[0], Color("2a2014"), UiStyle.SIZE_SMALL, UiStyle.bold())
			key.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.25))
			var cap := UiStyle.box(Color("c9aa6a"), Color("6b5530"), 1, 3, 0)
			cap.content_margin_left = 6
			cap.content_margin_right = 6
			cap.border_width_bottom = 3
			key.add_theme_stylebox_override("normal", cap)
			line.add_child(key)
			line.add_child(UiStyle.label(hint[1], UiStyle.DIM, UiStyle.SIZE_SMALL, UiStyle.italic()))
			foot.add_child(line)
		main.add_child(foot)
	_stack.append(e)
	panel.reset_size()
	_place(panel, mouse)

## A row of a breakdown: name left, value right, on bars of two shades;
## "+" values green, "−" red.
func _row(r: Array, i: int) -> Control:
	var back := PanelContainer.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stripe := UiStyle.box(UiStyle.TIP_ROW if i % 2 == 0 else UiStyle.TIP_ROW_B, Color.TRANSPARENT, 0, 0, 0)
	stripe.content_margin_left = 8
	stripe.content_margin_right = 8
	stripe.content_margin_top = 3
	stripe.content_margin_bottom = 3
	back.add_theme_stylebox_override("panel", stripe)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(line)
	var a := UiStyle.label(str(r[0]), UiStyle.TEXT, UiStyle.SIZE_SMALL + 1)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(a)
	var v := str(r[1])
	var colour: Color = r[2] if r.size() > 2 else (UiStyle.GAIN if v.begins_with("+") else (UiStyle.LOSS if v.begins_with("−") or v.begins_with("-") else UiStyle.TEXT))
	var b := UiStyle.label(v, colour, UiStyle.SIZE_SMALL + 1)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(b)
	return back

## "Letzte Monate" as EU5's "Recent Market Price": a teal head with the
## title in the middle, a black board with the highest and lowest value at
## the left, a brown foot with the first and last month in italics.
func _chart(d: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.TIP_CHART, UiStyle.TIP_LINE, 1, 0, 0))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_child(inner)
	var head := UiStyle.label(d.get("spark_title", "Verlauf"), UiStyle.TEXT, UiStyle.SIZE_TEXT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var head_box := UiStyle.box(UiStyle.TIP_CHART_HEAD, Color.TRANSPARENT, 0, 0, 4)
	head_box.border_width_bottom = 1
	head_box.border_color = UiStyle.TIP_LINE
	head.add_theme_stylebox_override("normal", head_box)
	inner.add_child(head)
	var values: PackedFloat64Array = d.spark
	var lo := PackedFloat64Array(d.get("spark_lo", PackedFloat64Array()))
	var hi := PackedFloat64Array(d.get("spark_hi", PackedFloat64Array()))
	var ref := PackedFloat64Array(d.get("spark_ref", PackedFloat64Array()))
	var top := -INF
	var bottom := INF
	for v in values + lo + hi + ref:
		top = maxf(top, v)
		bottom = minf(bottom, v)
	var unit: String = d.get("spark_unit", "")
	var chart := Control.new()
	chart.custom_minimum_size = SPARK
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart.draw.connect(func():
		var r := Rect2(Vector2.ZERO, chart.size)
		var plot := Rect2(r.position + Vector2(52, 10), r.size - Vector2(60, 20))
		Charts.spark(chart, plot, values, d.get("colour", Charts.SERIES[0]), lo, hi, top, bottom)
		if ref.size() == values.size():
			var line := PackedVector2Array()
			for i in ref.size():
				line.append(Vector2(plot.position.x + plot.size.x * i / (ref.size() - 1), plot.end.y - 1.0 - (ref[i] - bottom) / maxf(top - bottom, 1e-9) * (plot.size.y - 2.0)))
			for dash in Charts.dashes(line, 8.0, 5.0):
				chart.draw_polyline(dash, Charts.RED, 1.5, true)
		UiStyle.text_at(chart, Vector2(8, 20), _short(top) + unit, UiStyle.TEXT, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.bold())
		UiStyle.text_at(chart, Vector2(8, r.size.y - 8), _short(bottom) + unit, UiStyle.TEXT, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.bold()))
	inner.add_child(chart)
	if d.has("spark_from"):
		var foot_back := PanelContainer.new()
		foot_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var foot_box := UiStyle.box(UiStyle.TIP_FOOT, Color.TRANSPARENT, 0, 0, 0)
		foot_box.content_margin_left = 8
		foot_box.content_margin_right = 8
		foot_box.content_margin_top = 3
		foot_box.content_margin_bottom = 3
		foot_back.add_theme_stylebox_override("panel", foot_box)
		var foot := HBoxContainer.new()
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foot_back.add_child(foot)
		var from := UiStyle.label(d.spark_from, UiStyle.TEXT, UiStyle.SIZE_SMALL, UiStyle.italic())
		from.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(from)
		foot.add_child(UiStyle.label(d.get("spark_to", ""), UiStyle.TEXT, UiStyle.SIZE_SMALL, UiStyle.italic()))
		inner.add_child(foot_back)
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

## A sunken box in a thin line, as EU5 sets its rows in a tooltip.
func _inset(margin := 0) -> PanelContainer:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.TIP_ROW, UiStyle.TIP_LINE, 1, 0, margin))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
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
	t.add_theme_color_override("font_shadow_color", UiStyle.SHADOW)
	t.add_theme_constant_override("shadow_offset_x", 1)
	t.add_theme_constant_override("shadow_offset_y", 1)
	t.add_theme_font_override("normal_font", UiStyle.serif())
	t.add_theme_font_size_override("normal_font_size", UiStyle.SIZE_SMALL + 1)
	var c := func(colour: Color) -> String: return "[color=#%s]" % colour.to_html(false)
	t.text = (bbcode.replace("[url=", c.call(UiStyle.CONCEPT) + "[url=").replace("[/url]", "[/url][/color]")
		.replace("[n]", c.call(UiStyle.NAME)).replace("[/n]", "[/color]")
		.replace("[+]", c.call(UiStyle.GAIN)).replace("[/+]", "[/color]")
		.replace("[-]", c.call(UiStyle.LOSS)).replace("[/-]", "[/color]"))
	t.meta_hover_started.connect(func(meta): e.term = str(meta))
	t.meta_hover_ended.connect(func(_meta): e.term = "")
	e.texts.append(t)
	return t

## EU5's tooltip: dark slate in a thin bronze-grey line and a black one,
## gold once locked.
static func _frame(lit: bool) -> StyleBoxFlat:
	var b := UiStyle.box(Color(UiStyle.TIP_BODY, 0.98), UiStyle.GOLD_LIT if lit else UiStyle.TIP_FRAME, 2 if lit else 1, 1, 0)
	b.expand_margin_left = 1
	b.expand_margin_right = 1
	b.expand_margin_top = 1
	b.expand_margin_bottom = 1
	b.shadow_color = Color(0, 0, 0, 0.6)
	b.shadow_size = 10
	b.shadow_offset = Vector2(0, 4)
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
