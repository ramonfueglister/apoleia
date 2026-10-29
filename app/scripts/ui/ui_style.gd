extends RefCounted
## The look of every window, tooltip and panel, taken from EU5's interface
## (reference shots in docs/kit1/references/eu5-ui/README.md): dark slate
## panels in a thin bronze frame, titles in a serif in warm cream, insets
## a shade darker with faintly striped rows, game concepts in light blue,
## names in pale gold, gains in green and losses in red. Numbers right
## aligned. One place for it, so the loading screen, the build menu and the
## windows read as one game.

## panels
const PANEL := Color("1a222b")      # window body
const INSET := Color("10161d")      # sunken boxes inside a window or tooltip
const STRIPE := Color(1.0, 1.0, 1.0, 0.035)
const HEADER := Color("2a2219")     # title bars, a warm dark brown
const FRAME := Color("8a6a3c")      # bronze edges
const FRAME_LIT := Color("d1ad66")  # an edge that is active (locked tooltip, focused window)
const SELECTED := Color("2c3e4c")
const HOVER := Color(1.0, 1.0, 1.0, 0.06)
## text
const TEXT := Color("e6dcc6")       # cream
const DIM := Color("9aa3a6")
const TITLE := Color("f1e4c4")
const NAME := Color("f0d38e")       # places, people, goods
const CONCEPT := Color("8fc6e0")    # terms with a tooltip of their own
const GAIN := Color("7fcf6a")
const LOSS := Color("e3604f")
const SIZE_TITLE := 22
const SIZE_HEAD := 17
const SIZE_TEXT := 14
const SIZE_SMALL := 12

static func serif() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Palatino", "Palatino Linotype", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	return font

static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w := 0, radius := 3, margin := 0.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(border_w)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	b.anti_aliasing = true
	return b

## A window or tooltip: slate body, bronze frame, a soft shadow.
static func frame(lit := false) -> StyleBoxFlat:
	var b := box(Color(PANEL, 0.97), FRAME_LIT if lit else FRAME, 2 if lit else 1, 4)
	b.shadow_color = Color(0, 0, 0, 0.45)
	b.shadow_size = 10
	b.shadow_offset = Vector2(0, 4)
	return b

## A sunken box inside a panel.
static func inset(margin := 8.0) -> StyleBoxFlat:
	return box(INSET, Color(FRAME, 0.35), 1, 2, margin)

## "+12.5" in green, "−3.0" in red.
static func signed_colour(v: float) -> Color:
	return GAIN if v > 0.0 else (LOSS if v < 0.0 else TEXT)

## Every control inside a window, in this look.
static func theme() -> Theme:
	var th := Theme.new()
	th.default_font = serif()
	th.default_font_size = SIZE_TEXT
	th.set_color("font_color", "Label", TEXT)
	for type in ["Button", "OptionButton"]:
		th.set_stylebox("normal", type, box(HEADER, Color(FRAME, 0.8), 1, 3, 6))
		th.set_stylebox("hover", type, box(SELECTED, FRAME_LIT, 1, 3, 6))
		th.set_stylebox("pressed", type, box(SELECTED, FRAME_LIT, 1, 3, 6))
		th.set_stylebox("focus", type, StyleBoxEmpty.new())
		th.set_color("font_color", type, TEXT)
		th.set_color("font_hover_color", type, TITLE)
		th.set_color("font_pressed_color", type, NAME)
	th.set_color("font_color", "CheckButton", TEXT)
	th.set_color("font_hover_color", "CheckButton", TITLE)
	th.set_color("font_pressed_color", "CheckButton", NAME)
	th.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("normal", "LineEdit", box(INSET, Color(FRAME, 0.6), 1, 12, 7))
	th.set_stylebox("focus", "LineEdit", box(INSET, FRAME_LIT, 1, 12, 7))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", Color(DIM, 0.8))
	th.set_color("caret_color", "LineEdit", NAME)
	th.set_stylebox("panel", "PopupMenu", box(PANEL, FRAME, 1, 3, 6))
	th.set_stylebox("hover", "PopupMenu", box(SELECTED, Color.TRANSPARENT, 0, 2, 4))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", TITLE)
	# tabs as EU5's: raised boards, the chosen one lighter with a bronze edge
	var tab_on := box(Color("3a3024"), FRAME_LIT, 1, 4, 9)
	tab_on.border_width_bottom = 0
	th.set_stylebox("tab_selected", "TabBar", tab_on)
	th.set_stylebox("tab_unselected", "TabBar", box(HEADER, Color(FRAME, 0.5), 1, 4, 9))
	th.set_stylebox("tab_hovered", "TabBar", box(Color("332a20"), FRAME, 1, 4, 9))
	th.set_color("font_selected_color", "TabBar", TITLE)
	th.set_color("font_unselected_color", "TabBar", DIM)
	th.set_color("font_hovered_color", "TabBar", TEXT)
	th.set_font_size("font_size", "TabBar", SIZE_HEAD)
	th.set_constant("h_separation", "TabBar", 4)
	# tables: an inset with striped rows, heads in pale gold
	th.set_stylebox("panel", "Tree", inset(2))
	th.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	var title := box(HEADER, FRAME, 0, 0, 6)
	title.border_width_bottom = 1
	th.set_stylebox("title_button_normal", "Tree", title)
	th.set_stylebox("title_button_pressed", "Tree", title)
	var title_hover := title.duplicate()
	title_hover.bg_color = SELECTED
	th.set_stylebox("title_button_hover", "Tree", title_hover)
	th.set_color("title_button_color", "Tree", NAME)
	th.set_color("font_color", "Tree", TEXT)
	th.set_font_size("font_size", "Tree", SIZE_TEXT)
	th.set_font_size("title_button_font_size", "Tree", SIZE_SMALL + 1)
	th.set_color("font_selected_color", "Tree", TITLE)
	th.set_stylebox("selected", "Tree", box(SELECTED, Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("selected_focus", "Tree", box(SELECTED, Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("hovered", "Tree", box(HOVER, Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	th.set_constant("draw_guides", "Tree", 0)
	th.set_constant("draw_relationship_lines", "Tree", 0)
	th.set_constant("v_separation", "Tree", 8)
	th.set_constant("inner_item_margin_left", "Tree", 8)
	th.set_constant("inner_item_margin_right", "Tree", 8)
	th.set_stylebox("grabber", "VScrollBar", box(Color(FRAME, 0.7), Color.TRANSPARENT, 0, 3, 3))
	th.set_stylebox("grabber_highlight", "VScrollBar", box(FRAME_LIT, Color.TRANSPARENT, 0, 3, 3))
	th.set_stylebox("grabber_pressed", "VScrollBar", box(FRAME_LIT, Color.TRANSPARENT, 0, 3, 3))
	th.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.3), Color.TRANSPARENT, 0, 3, 3))
	return th
