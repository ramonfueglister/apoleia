extends RefCounted
## The look of every game window, tooltip and panel, the same as the
## menus' (vic3_style.gd, after Victoria 3): a window is grained slate in a
## gold rim and a black ring, its title stands in small caps with large gold
## initials on a band of wine-red leather, round medallions at both ends.
## Tabs are olive boards, the chosen one lit with a gold edge. Tables are
## dark green rows, charts a dark board. Tooltips are dark wine with a
## leather head. Game concepts in orange, gains in green, losses in red,
## numbers right aligned. The fonts are the menus' (EB Garamond, IM FELL
## English SC). One place for it, so the loading screen, the menus and the
## windows read as one game.

const Vic3Style = preload("res://scripts/ui/vic3_style.gd")

## the frame
const BAR := Color("3c1b20")        # the title band, wine-red leather
const GOLD := Color("b7aa7b")       # gold edges and rules
const GOLD_DIM := Color("7d7152")   # a quiet rim (an unchosen tab, a button)
const GOLD_LIT := Color("f0d590")   # an edge that is active (hover, locked tooltip)
const EDGE := Color("0d0b0b")       # the black line around everything
## the field inside
const PANEL := Color("2c2d30")      # window body, navy
const INSET := Color("222326")      # sunken boxes in the field
const TAB := Color("2c3428")        # olive tab boards (TabBar, ui_tabs.gd)
const TAB_ON := Color("3d4a30")
const TAB_HOVER := Color("343f28")
const ROW := Color("202c29")        # a table row, warm grey
const ROW_DARK := Color("1c2724")
const ROW_HEAD := Color("1a1f1e")
const STAT := Color("26302b")       # stat strip cells, two shades
const STAT_B := Color("2f3a33")
const STAT_FRAME := Color("5a4c36") # the strip's reddish brown edge
const CHART := Color("232528")      # chart board
const CHART_GRID := Color("1a1b1e") # its grid, darker than the board
const CHART_FRAME := Color("4a4538")
const CHART_EDGE := Color("8f8573") # the thin pale line around a chart
const BUTTON_TOP := Color("3d4a30") # an olive button under the mouse
const BUTTON_BOTTOM := Color("2c3428")
## tooltips
const TIP_HEAD := Color("3c1b20")
const TIP_BODY := Color("2e2527")
const TIP_ROW := Color("272022")
const TIP_ROW_B := Color("2c2426")
const TIP_LINE := Color("4a3a38")
const TIP_CHART_HEAD := Color("2a2224")
const TIP_CHART := Color("1f1a1b")
const TIP_FOOT := Color("3c2e2a")
const TIP_FRAME := Color("5a4a3c")
## older names, kept for the code that uses them
const HEADER := BAR
const FRAME := GOLD
const FRAME_LIT := GOLD_LIT
const SELECTED := Color("343f28")
const HOVER := Color(1.0, 1.0, 1.0, 0.06)
const STRIPE := Color(1.0, 1.0, 1.0, 0.035)
## text
const TEXT := Color("e9e2cc")       # cream
const DIM := Color("a59a80")
const TITLE := Color("f1e6c8")
const VALUE := Color("f0d590")      # a stat's value, pale gold
const NAME := Color("f0d590")       # places, people, goods
const CONCEPT := Color("e8a060")    # terms with a tooltip of their own
const KIND := Color("c9b896")       # a tooltip's kind, below its title
const GAIN := Color("59d368")
const LOSS := Color("e26066")
const SHADOW := Color(0, 0, 0, 0.75)
const SIZE_TITLE := 28
const SIZE_HEAD := 19
const SIZE_TEXT := 17
const SIZE_SMALL := 15

## The menus' fonts, made once in vic3_style.gd (a font made anew for each
## draw_string comes out as blank boxes): EB Garamond for text, IM FELL
## English SC for titles; the system serif stands in for missing glyphs.
static func serif() -> Font:
	return Vic3Style.serif()

static func bold() -> Font:
	return Vic3Style.bold()

static func italic() -> Font:
	return Vic3Style.italic()

static func title_font() -> Font:
	return Vic3Style.title_font()

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

## A sunken box in the field, in a thin frame.
static func inset(margin := 8.0) -> StyleBoxFlat:
	return box(INSET, CHART_FRAME, 1, 0, margin)

## A board in the stat strip or a card: warm brown in a brown frame.
static func board(margin := 8.0, shade := STAT) -> StyleBoxFlat:
	var b := box(shade, Color(EDGE, 0.8), 1, 0, margin)
	return b

## "+12.5" in green, "−3.0" in red.
static func signed_colour(v: float) -> Color:
	return GAIN if v > 0.0 else (LOSS if v < 0.0 else TEXT)

## A label: serif, with a dark shadow under it.
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

## Text drawn onto a canvas with a dark shadow under it.
static func text_at(ci: CanvasItem, at: Vector2, text: String, colour := TEXT, font_size := SIZE_SMALL,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null) -> void:
	var f := font if font != null else serif()
	ci.draw_string(f, at + Vector2(1, 1), text, align, width, font_size, SHADOW)
	ci.draw_string(f, at, text, align, width, font_size, colour)

# ------------------------------------------------------------------ drawn parts

## A window's title band, as the menus': wine-red leather lit from above,
## a gold line and a dark one at its foot.
static func draw_bar(ci: CanvasItem, r: Rect2) -> void:
	Vic3Style.draw_band(ci, r)

## A window, as the menus': its shadow, a black and a dark ring, the gold
## rim, the grained slate, gold corners at the foot.
static func draw_window(ci: CanvasItem, r: Rect2) -> void:
	Vic3Style.draw_panel(ci, r)

## A round button as the menus' medallions: a gold ring round a dark boss
## lit from above, green, red for "close". `glyph` is "close", "fold",
## "back" or a letter.
static func draw_round(ci: CanvasItem, centre: Vector2, radius: float, glyph: String, hover := false, down := false) -> void:
	if hover:
		for i in 3:
			ci.draw_circle(centre, radius + 0.5 + i * 1.5, Color(1.0, 0.84, 0.56, 0.08 - i * 0.02))
	ci.draw_circle(centre, radius, EDGE)
	ci.draw_circle(centre, radius - 1.0, GOLD_LIT if hover else GOLD)
	var inner := radius - maxf(3.0, radius * 0.14)
	var red := glyph == "close"
	var dark := Color("1c0c0f") if red else Color("121a16")
	var light := Color("7a3440") if red else Color("56685d")
	if down:
		light = light.darkened(0.35)
	ci.draw_circle(centre, inner, dark)
	ci.draw_circle(centre + Vector2(0, -inner * 0.22), inner * 0.78, dark.lerp(light, 0.45))
	ci.draw_circle(centre + Vector2(0, -inner * 0.35), inner * 0.5, dark.lerp(light, 0.8))
	ci.draw_arc(centre, inner - 1.0, PI * 1.1, PI * 1.9, 24, Color(1, 1, 1, 0.18), 1.5, true)
	var ink := Color("fff1c8") if hover else Color("e6d7a8")
	var s := inner * 0.42
	var w := maxf(2.0, inner * 0.16)
	match glyph:
		"close":
			for d in [Vector2(1, 1), Vector2(1, -1)]:
				ci.draw_line(centre - d * s, centre + d * s, ink, w, true)
		"fold":
			ci.draw_rect(Rect2(centre - Vector2(s, w * 0.5), Vector2(2.0 * s, w)), ink)
		"back":
			var tip := centre - Vector2(s, 0)
			ci.draw_polyline(PackedVector2Array([centre + Vector2(0, -s), tip, centre + Vector2(0, s)]), ink, w, true)
			ci.draw_line(tip, centre + Vector2(s, 0), ink, w, true)
		_:
			ci.draw_string(bold(), centre + Vector2(-radius, radius * 0.3), glyph, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(radius * 0.9), ink)

## A button as the menus': an olive board in a gold edge, a little lighter
## at its top, a glow round it under the mouse.
static func _button(bg: Color, edge: Color, glow := 0) -> StyleBoxFlat:
	var b := box(bg, edge, 1, 3, 8)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.shadow_color = Color(GOLD_LIT, 0.25) if glow > 0 else Color(0, 0, 0, 0.35)
	b.shadow_size = glow if glow > 0 else 2
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
	# buttons as the menus': olive boards in a gold edge, lit on hover
	for type in ["Button", "OptionButton"]:
		th.set_stylebox("normal", type, _button(BUTTON_BOTTOM, GOLD_DIM))
		th.set_stylebox("hover", type, _button(BUTTON_TOP, GOLD_LIT, 5))
		th.set_stylebox("pressed", type, _button(TAB_HOVER, GOLD_LIT))
		th.set_stylebox("disabled", type, _button(Color(BUTTON_BOTTOM, 0.5), Color(GOLD_DIM, 0.4)))
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
	# the search field: dark in a quiet gold line
	th.set_stylebox("normal", "LineEdit", box(Color("1a1c1d"), GOLD_DIM, 1, 3, 8))
	th.set_stylebox("focus", "LineEdit", box(Color("1a1c1d"), GOLD_LIT, 1, 3, 8))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", DIM)
	th.set_color("caret_color", "LineEdit", NAME)
	th.set_stylebox("panel", "PopupMenu", box(PANEL, GOLD, 1, 2, 6))
	th.set_stylebox("hover", "PopupMenu", box(SELECTED, Color.TRANSPARENT, 0, 2, 4))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	# tabs as the menus' buttons: olive boards, the chosen one lighter in gold
	var tab := box(TAB, GOLD_DIM, 1, 2, 0)
	tab.content_margin_left = 24
	tab.content_margin_right = 24
	tab.content_margin_top = 8
	tab.content_margin_bottom = 8
	var tab_on := tab.duplicate()
	tab_on.bg_color = TAB_ON
	tab_on.border_color = GOLD
	var tab_hover := tab.duplicate()
	tab_hover.bg_color = TAB_HOVER
	tab_hover.border_color = GOLD_LIT
	th.set_stylebox("tab_selected", "TabBar", tab_on)
	th.set_stylebox("tab_unselected", "TabBar", tab)
	th.set_stylebox("tab_hovered", "TabBar", tab_hover)
	th.set_stylebox("tab_focus", "TabBar", StyleBoxEmpty.new())
	th.set_color("font_selected_color", "TabBar", NAME)
	th.set_color("font_unselected_color", "TabBar", TEXT)
	th.set_color("font_hovered_color", "TabBar", Color.WHITE)
	th.set_color("font_outline_color", "TabBar", Color(0, 0, 0, 0.8))
	th.set_constant("outline_size", "TabBar", 2)
	th.set_font_size("font_size", "TabBar", SIZE_TEXT + 1)
	th.set_font("font", "TabBar", bold())
	th.set_constant("h_separation", "TabBar", 2)
	# tables: dark green rows on the slate under a leather head, as the menus' lists
	th.set_stylebox("panel", "Tree", box(Color("1d2422"), GOLD_DIM, 1, 2, 2))
	th.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	var head := box(BAR, EDGE, 0, 0, 6)
	head.border_width_bottom = 1
	head.border_color = GOLD_DIM
	th.set_stylebox("title_button_normal", "Tree", head)
	th.set_stylebox("title_button_pressed", "Tree", head)
	var head_hover := head.duplicate()
	head_hover.bg_color = Color("4e242b")
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
	# scroll bars: a thin dark groove with a gold grip, as the menus'
	for bar in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("grabber", bar, box(GOLD_DIM, EDGE, 1, 4, 3))
		th.set_stylebox("grabber_highlight", bar, box(GOLD_LIT, EDGE, 1, 4, 3))
		th.set_stylebox("grabber_pressed", bar, box(GOLD_LIT, EDGE, 1, 4, 3))
		th.set_stylebox("scroll", bar, box(Color(0, 0, 0, 0.45), Color.TRANSPARENT, 0, 4, 3))
	return th
