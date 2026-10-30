extends RefCounted
## The look of every window, tooltip and panel, measured from EU5's
## interface (reference shots in docs/kit1/references/eu5-ui/README.md):
## a window stands in a frame of dark carved wood, its title bar is bronze
## with a lattice and gold edges, the title a large cream serif, round dark
## buttons in a bronze ring at both ends. Inside lies a deep navy field;
## tabs are slate boards, the chosen one opens into the field. Tables are
## warm grey bars on the navy, charts a brown board with a square grid in a
## brown frame. Tooltips have a brown head with a gold rule, a dark slate
## body and sunken boxes of alternating rows. Game concepts in light blue,
## gains in green, losses in red, numbers right aligned. One place for it,
## so the loading screen, the menus and the windows read as one game.

## the frame
const WOOD := Color("2a221a")       # carved frame around a window
const WOOD_CARVE := Color("4a3c2c") # the carving on it
const BAR := Color("4c3a1c")        # bronze title bar
const BAR_LATTICE := Color("6b532b")
const GOLD := Color("a8854a")       # gold edges and rules
const GOLD_LIT := Color("e2c27c")   # an edge that is active (hover, locked tooltip)
const EDGE := Color("0b0d10")       # the black line around everything
## the field inside
const PANEL := Color("111922")      # window body, navy
const INSET := Color("0c1218")      # sunken boxes in the field
const TAB := Color("252a31")        # slate tab boards (TabBar)
const TAB_ON := Color("1a232e")
const TAB_WOOD := Color("2c231a")   # EU5's wooden tab boards (ui_tabs.gd)
const TAB_WOOD_HOVER := Color("382c21")
const TAB_WOOD_ON := Color("45372a")
const ROW := Color("39352c")        # a table row, warm grey
const ROW_DARK := Color("312d26")
const ROW_HEAD := Color("212428")
const STAT := Color("3a3026")       # stat strip cells, two shades
const STAT_B := Color("4a3f33")
const STAT_FRAME := Color("5b3b2b") # the strip's reddish brown edge
const CHART := Color("2d2319")      # chart board
const CHART_GRID := Color("1f1810") # its grid, darker than the board
const CHART_FRAME := Color("604735")
const CHART_EDGE := Color("8f8573") # the thin pale line around a chart
const BUTTON_TOP := Color("1d5272") # EU5's blue buttons
const BUTTON_BOTTOM := Color("12324a")
## tooltips
const TIP_HEAD := Color("2e251c")
const TIP_BODY := Color("1d2222")
const TIP_ROW := Color("191f22")
const TIP_ROW_B := Color("1e2528")
const TIP_LINE := Color("3a3b36")
const TIP_CHART_HEAD := Color("17262a")
const TIP_CHART := Color("151716")
const TIP_FOOT := Color("473c30")
const TIP_FRAME := Color("4c4638")
## older names, kept for the code that uses them
const HEADER := BAR
const FRAME := GOLD
const FRAME_LIT := GOLD_LIT
const SELECTED := Color("2c3e52")
const HOVER := Color(1.0, 1.0, 1.0, 0.06)
const STRIPE := Color(1.0, 1.0, 1.0, 0.035)
## text
const TEXT := Color("efead8")       # cream
const DIM := Color("a09889")
const TITLE := Color("efead8")
const VALUE := Color("f9e0a5")      # a stat's value, pale gold
const NAME := Color("f0d38e")       # places, people, goods
const CONCEPT := Color("7cc6e2")    # terms with a tooltip of their own
const KIND := Color("a3c1c8")       # a tooltip's kind, below its title
const GAIN := Color("59d368")
const LOSS := Color("e26066")
const SHADOW := Color(0, 0, 0, 0.75)
const SIZE_TITLE := 28
const SIZE_HEAD := 18
const SIZE_TEXT := 15
const SIZE_SMALL := 13

static var _serif: SystemFont
static var _bold: FontVariation
static var _italic: FontVariation

## One font for all, made once: a font made anew for each draw_string
## comes out as blank boxes (its glyphs are not cached by the frame).
## EU5 sets its text in a book serif with a firm stroke.
static func serif() -> Font:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Palatino", "Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
		_serif.font_weight = 500
	return _serif

static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = serif()
		_bold.variation_embolden = 0.5
	return _bold

static func italic() -> Font:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = serif()
		_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	return _italic

static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w := 0, radius := 3, margin := 0.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(border_w)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	b.anti_aliasing = true
	return b

## A popup or legend: navy in a black line and a gold one, a shadow.
static func frame(lit := false) -> StyleBoxFlat:
	var b := box(Color(PANEL, 0.98), GOLD_LIT if lit else GOLD, 2 if lit else 1, 2)
	b.shadow_color = Color(0, 0, 0, 0.55)
	b.shadow_size = 12
	b.shadow_offset = Vector2(0, 5)
	return b

## A sunken box in the field, in a thin brown frame (EU5's stat boxes).
static func inset(margin := 8.0) -> StyleBoxFlat:
	return box(INSET, CHART_FRAME, 1, 0, margin)

## A board in the stat strip or a card: warm brown in a brown frame.
static func board(margin := 8.0, shade := STAT) -> StyleBoxFlat:
	var b := box(shade, Color(EDGE, 0.8), 1, 0, margin)
	return b

## "+12.5" in green, "−3.0" in red.
static func signed_colour(v: float) -> Color:
	return GAIN if v > 0.0 else (LOSS if v < 0.0 else TEXT)

## A label in EU5's manner: serif, with a dark shadow under it.
static func label(text: String, colour := TEXT, font_size := SIZE_TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if font != null:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Text drawn onto a canvas with EU5's shadow under it.
static func text_at(ci: CanvasItem, at: Vector2, text: String, colour := TEXT, font_size := SIZE_SMALL,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null) -> void:
	var f := font if font != null else serif()
	ci.draw_string(f, at + Vector2(1, 1), text, align, width, font_size, SHADOW)
	ci.draw_string(f, at, text, align, width, font_size, colour)

# ------------------------------------------------------------------ drawn parts

## EU5's title bar: bronze with a lattice of fine diagonals and a small
## four-leaved mark in each diamond, a gold edge above and below, darker
## towards both ends.
static func draw_bar(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, BAR)
	var step := 30.0
	var slope := Vector2(step / r.size.y, 1.0) # across one diamond from top to foot
	var c := -step
	while c < r.size.x + step:
		_cut_line(ci, r, Vector2(r.position.x + c, r.position.y), slope)
		_cut_line(ci, r, Vector2(r.position.x + c + step, r.position.y), Vector2(-slope.x, 1.0))
		var mid := Vector2(r.position.x + c + step * 0.5, r.position.y + r.size.y * 0.5)
		if mid.x > r.position.x + 6.0 and mid.x < r.end.x - 6.0:
			for d in [Vector2(0, -4), Vector2(4, 0), Vector2(0, 4), Vector2(-4, 0)]:
				ci.draw_circle(mid + d, 2.4, BAR_LATTICE)
			ci.draw_circle(mid, 1.6, Color("75603a"))
		c += step
	for k in 6: # shade towards the ends
		var w := r.size.x * 0.035
		var a := 0.07 * (6 - k)
		ci.draw_rect(Rect2(r.position.x + k * w, r.position.y, w, r.size.y), Color(0, 0, 0, a))
		ci.draw_rect(Rect2(r.end.x - (k + 1) * w, r.position.y, w, r.size.y), Color(0, 0, 0, a))
	ci.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.5, r.size.x, r.size.y * 0.5), Color(0, 0, 0, 0.12))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 4)), Color(0, 0, 0, 0.35))
	ci.draw_line(r.position + Vector2(0, 1), Vector2(r.end.x, r.position.y + 1), Color(GOLD, 0.6), 1.0)
	ci.draw_line(r.position + Vector2(0, 5), Vector2(r.end.x, r.position.y + 5), Color(GOLD, 0.8), 1.0)
	ci.draw_line(Vector2(r.position.x, r.end.y - 2), Vector2(r.end.x, r.end.y - 2), GOLD, 2.0)
	ci.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), EDGE, 1.0)

static func _cut_line(ci: CanvasItem, r: Rect2, from: Vector2, dir: Vector2) -> void:
	# from lies on the top edge, dir.y is 1; walk to the foot, cut at the sides
	var a := from
	var b := from + dir * r.size.y
	if a.x < r.position.x:
		a = a + dir * (r.position.x - a.x) / dir.x
	if a.x > r.end.x:
		a = a + dir * (r.end.x - a.x) / dir.x
	if b.x < r.position.x:
		b = b - dir * (b.x - r.position.x) / dir.x
	if b.x > r.end.x:
		b = b - dir * (b.x - r.end.x) / dir.x
	if a.y < b.y:
		ci.draw_line(a, b, Color(0, 0, 0, 0.25), 3.0, true)
		ci.draw_line(a, b, BAR_LATTICE, 1.5, true)

## EU5's window frame: dark wood with a carved strip of stacked leaves
## (chevrons) down the sides, a black line outside, a fine gold one inside.
static func draw_wood(ci: CanvasItem, r: Rect2, inner: Rect2) -> void:
	ci.draw_rect(r, WOOD)
	var side := inner.position.x - r.position.x
	if side >= 8.0:
		var d := side * 0.32
		var y := inner.position.y + 4.0
		while y < inner.end.y - 4.0:
			for x in [r.position.x + side * 0.5, r.end.x - side * 0.5]:
				var leaf := PackedVector2Array([Vector2(x - d, y), Vector2(x, y + d), Vector2(x + d, y)])
				ci.draw_polyline(leaf, Color(0, 0, 0, 0.5), 3.0, true)
				ci.draw_polyline(leaf, WOOD_CARVE, 1.5, true)
			y += d * 1.6
		for x in [r.position.x + 2.0, r.end.x - 3.0, inner.position.x - 3.0, inner.end.x + 2.0]:
			ci.draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.35), 1.0)
	ci.draw_rect(r, EDGE, false, 1.0)
	ci.draw_rect(inner.grow(1.0), EDGE, false, 2.0)
	ci.draw_rect(inner.grow(2.0), Color(GOLD, 0.45), false, 1.0)

## EU5's round button: a navy disc lit from above in a bronze ring with a
## black edge. `glyph` is "close", "fold", "back" or a letter.
static func draw_round(ci: CanvasItem, centre: Vector2, radius: float, glyph: String, hover := false, down := false) -> void:
	ci.draw_circle(centre, radius, EDGE)
	ci.draw_circle(centre, radius - 1.0, GOLD_LIT if hover else GOLD)
	ci.draw_circle(centre, radius - 3.5, EDGE)
	var disc := Color("2a3a4e") if hover else Color("1d2836")
	if down:
		disc = Color("141c26")
	ci.draw_circle(centre, radius - 4.5, disc)
	ci.draw_circle(centre - Vector2(0, radius * 0.18), radius - 7.0, Color(1, 1, 1, 0.05))
	var ink := Color("f3ecd9") if hover else Color("ddd4bf")
	var s := radius * 0.38
	match glyph:
		"close":
			for d in [Vector2(1, 1), Vector2(1, -1)]:
				ci.draw_line(centre - d * s, centre + d * s, EDGE, 5.0, true)
			for d in [Vector2(1, 1), Vector2(1, -1)]:
				ci.draw_line(centre - d * s, centre + d * s, ink, 3.0, true)
		"fold":
			ci.draw_rect(Rect2(centre - Vector2(s + 1.0, 3.0), Vector2(2.0 * s + 2.0, 6.0)), EDGE)
			ci.draw_rect(Rect2(centre - Vector2(s, 2.0), Vector2(2.0 * s, 4.0)), ink)
		"back":
			var tip := centre - Vector2(s, 0)
			ci.draw_polyline(PackedVector2Array([centre + Vector2(0, -s), tip, centre + Vector2(0, s)]), ink, 3.0, true)
			ci.draw_line(tip, centre + Vector2(s, 0), ink, 3.0, true)
		_:
			var f := bold()
			ci.draw_string(f, centre + Vector2(-radius, radius * 0.3), glyph, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(radius * 0.9), ink)

## EU5's blue button: a black line, a bronze one, the blue lit at its top.
static func _button(bg: Color, edge: Color) -> StyleBoxFlat:
	var b := box(bg, edge, 2, 4, 8)
	b.border_width_top = 2
	b.expand_margin_left = 1
	b.expand_margin_right = 1
	b.shadow_color = Color(0, 0, 0, 0.6)
	b.shadow_size = 2
	return b

## Every control inside a window, in this look.
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font = serif()
	th.default_font_size = SIZE_TEXT
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_shadow_color", "Label", SHADOW)
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	# buttons as EU5's: deep blue in a bronze frame, lit on hover
	for type in ["Button", "OptionButton"]:
		th.set_stylebox("normal", type, _button(BUTTON_BOTTOM, GOLD))
		th.set_stylebox("hover", type, _button(BUTTON_TOP, GOLD_LIT))
		th.set_stylebox("pressed", type, _button(Color("0d2638"), GOLD_LIT))
		th.set_stylebox("disabled", type, box(Color("1b2028"), Color(GOLD, 0.4), 1, 4, 7))
		th.set_stylebox("focus", type, StyleBoxEmpty.new())
		th.set_color("font_color", type, TEXT)
		th.set_color("font_hover_color", type, Color.WHITE)
		th.set_color("font_pressed_color", type, NAME)
		th.set_color("font_shadow_color", type, SHADOW)
		th.set_constant("shadow_offset_x", type, 1)
		th.set_constant("shadow_offset_y", type, 1)
	th.set_color("font_color", "CheckButton", TEXT)
	th.set_color("font_hover_color", "CheckButton", Color.WHITE)
	th.set_color("font_pressed_color", "CheckButton", NAME)
	th.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	# the search field: a dark pill in a bronze ring
	th.set_stylebox("normal", "LineEdit", box(Color("0a0e19"), GOLD, 1, 16, 8))
	th.set_stylebox("focus", "LineEdit", box(Color("0a0e19"), GOLD_LIT, 1, 16, 8))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", DIM)
	th.set_color("caret_color", "LineEdit", NAME)
	th.set_stylebox("panel", "PopupMenu", box(PANEL, GOLD, 1, 2, 6))
	th.set_stylebox("hover", "PopupMenu", box(SELECTED, Color.TRANSPARENT, 0, 2, 4))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	# tabs as EU5's: slate boards with black gaps, the chosen one darker,
	# rounded at its top, open into the field below
	var tab := box(TAB, EDGE, 2, 2, 0)
	tab.content_margin_left = 30
	tab.content_margin_right = 30
	tab.content_margin_top = 9
	tab.content_margin_bottom = 9
	var tab_on := tab.duplicate()
	tab_on.bg_color = TAB_ON
	tab_on.border_color = Color(GOLD, 0.55)
	tab_on.border_width_left = 1
	tab_on.border_width_right = 1
	tab_on.border_width_top = 2
	tab_on.border_width_bottom = 0
	tab_on.corner_radius_top_left = 14
	tab_on.corner_radius_top_right = 3
	var tab_hover := tab.duplicate()
	tab_hover.bg_color = Color("303741")
	th.set_stylebox("tab_selected", "TabBar", tab_on)
	th.set_stylebox("tab_unselected", "TabBar", tab)
	th.set_stylebox("tab_hovered", "TabBar", tab_hover)
	th.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	th.set_color("font_selected_color", "TabBar", Color.WHITE)
	th.set_color("font_unselected_color", "TabBar", TEXT)
	th.set_color("font_hovered_color", "TabBar", Color.WHITE)
	th.set_color("font_outline_color", "TabBar", Color(0, 0, 0, 0.8))
	th.set_constant("outline_size", "TabBar", 3)
	th.set_font_size("font_size", "TabBar", SIZE_HEAD)
	th.set_font("font", "TabBar", bold())
	th.set_constant("h_separation", "TabBar", 0)
	# tables: warm grey rows on the navy, a dark head
	th.set_stylebox("panel", "Tree", box(PANEL, Color(EDGE, 0.9), 1, 0, 2))
	th.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	var head := box(ROW_HEAD, EDGE, 0, 0, 6)
	head.border_width_bottom = 2
	th.set_stylebox("title_button_normal", "Tree", head)
	th.set_stylebox("title_button_pressed", "Tree", head)
	var head_hover := head.duplicate()
	head_hover.bg_color = Color("2c3036")
	th.set_stylebox("title_button_hover", "Tree", head_hover)
	th.set_color("title_button_color", "Tree", NAME)
	th.set_color("font_color", "Tree", TEXT)
	th.set_color("font_outline_color", "Tree", Color(0, 0, 0, 0.7))
	th.set_constant("outline_size", "Tree", 2)
	th.set_font_size("font_size", "Tree", SIZE_TEXT)
	th.set_font_size("title_button_font_size", "Tree", SIZE_SMALL)
	th.set_color("font_selected_color", "Tree", Color.WHITE)
	th.set_stylebox("selected", "Tree", box(SELECTED, GOLD, 1, 0, 0))
	th.set_stylebox("selected_focus", "Tree", box(SELECTED, GOLD, 1, 0, 0))
	th.set_stylebox("hovered", "Tree", box(HOVER, Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	th.set_constant("draw_guides", "Tree", 0)
	th.set_constant("draw_relationship_lines", "Tree", 0)
	th.set_constant("v_separation", "Tree", 10)
	th.set_constant("inner_item_margin_left", "Tree", 8)
	th.set_constant("inner_item_margin_right", "Tree", 8)
	# scroll bars: a thin dark groove with a bronze grip, as EU5's
	for bar in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("grabber", bar, box(Color("8c7448"), EDGE, 1, 4, 3))
		th.set_stylebox("grabber_highlight", bar, box(GOLD_LIT, EDGE, 1, 4, 3))
		th.set_stylebox("grabber_pressed", bar, box(GOLD_LIT, EDGE, 1, 4, 3))
		th.set_stylebox("scroll", bar, box(Color(0, 0, 0, 0.45), Color.TRANSPARENT, 0, 4, 3))
	return th
