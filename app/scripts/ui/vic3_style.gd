extends RefCounted
## The look of the menus after Victoria 3 (reference shots in the project
## folder vic3-referenz/, colours measured from them): a window is a slate
## field with a fine grain in a gold rim and a black ring; its title stands
## on a band of wine-red leather with a gold line below, set in small caps
## with a large gold initial. Buttons are olive boards in a gold edge, with
## a gold icon before the text; round medallions (a gold ring round a dark
## green or red boss) carry the window's own actions. Everything lights up
## a little under the mouse.
##
## For now only the menus use it (main menu, pause menu and their pages);
## ui_style.gd keeps the look of the game's windows until both are joined.
## Icons: game-icons.net (CC BY 3.0); fonts: IM FELL English SC and
## EB Garamond (OFL); see assets/ui/LICENSE.md.

## colours, measured from Victoria 3's windows
const BAND := Color("3c1b20")       # title band, wine red
const SLATE := Color("2c2d30")      # window field
const OLIVE := Color("2c3428")      # a button
const OLIVE_ON := Color("343f28")   # the first button, or one pressed
const OLIVE_HOVER := Color("3c4a30")
const LEAF := Color("202c29")       # rows and cards, dark green
const WINE := Color("3c1b20")       # a button that leaves the game
const WINE_HOVER := Color("4e242b")
const GOLD := Color("b7aa7b")       # rims and lines
const GOLD_DIM := Color("7d7152")
const GOLD_LIT := Color("f0d590")   # a rim under the mouse, the initials
const RING := Color("1b1718")       # the dark ring round a window
const TEXT := Color("ece4cc")
const DIM := Color("a59a80")
const CONCEPT := Color("e8a060")    # a term with its own tooltip
const GAIN := Color("7fd16b")
const LOSS := Color("e0605a")
const SHADOW := Color(0, 0, 0, 0.75)

const SIZE_TITLE := 34
const SIZE_BUTTON := 20
const SIZE_TEXT := 17
const SIZE_SMALL := 14

const FONT_DIR := "res://assets/ui/fonts/"
const ICON_DIR := "res://assets/ui/icons/"

static var _title: Font
static var _serif: Font
static var _bold: Font
static var _italic: Font
static var _leather: Texture2D
static var _slate: Texture2D
static var _theme: Theme
static var _icons := {}

## The small caps of the titles.
static func title_font() -> Font:
	if _title == null:
		_title = _font("im-fell-english-sc.woff2")
	return _title

static func serif() -> Font:
	if _serif == null:
		_serif = _font("eb-garamond.woff2")
	return _serif

static func bold() -> Font:
	if _bold == null:
		_bold = _font("eb-garamond-semibold.woff2")
	return _bold

static func italic() -> Font:
	if _italic == null:
		_italic = _font("eb-garamond-italic.woff2")
	return _italic

## A bundled font with the system serif behind it, for glyphs it lacks.
static func _font(file: String) -> Font:
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Palatino", "Georgia", "Times New Roman", "serif"])
	var f: FontFile = null
	if ResourceLoader.exists(FONT_DIR + file):
		f = load(FONT_DIR + file)
	elif FileAccess.file_exists(FONT_DIR + file): # not imported yet, see texture()
		f = FontFile.new()
		if f.load_dynamic_font(FONT_DIR + file) != OK:
			f = null
	if f == null:
		return fallback
	var font := FontVariation.new()
	font.base_font = f
	font.fallbacks = [fallback]
	return font

## One of the white icons in assets/ui/icons; draw it with a modulate.
static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = texture(ICON_DIR + name + ".svg")
	return _icons[name]

## A picture from the project, or null if there is none. Godot started as a
## game (`--path app`, no editor) does not import new files, and then
## ResourceLoader knows nothing of a freshly pulled icon: every medallion
## showed only its close cross. So a file not imported yet is read raw.
static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if path.get_extension().to_lower() == "svg":
		err = img.load_svg_from_string(FileAccess.get_file_as_string(path), 0.5) # 512 px drawings, at 256 px
	else:
		err = img.load(path)
	if err != OK:
		return null
	push_warning("not imported, read raw: %s (run Godot once with --import)" % path)
	return ImageTexture.create_from_image(img)

static func leather() -> Texture2D:
	if _leather == null:
		_leather = texture("res://assets/ui/leder.png")
	return _leather

static func slate() -> Texture2D:
	if _slate == null:
		_slate = texture("res://assets/ui/schiefer.png")
	return _slate

## A texture laid in tiles over `r`, or `colour` without it.
static func _tiled(ci: CanvasItem, r: Rect2, tex: Texture2D, colour: Color) -> void:
	if tex == null:
		ci.draw_rect(r, colour)
	else:
		ci.draw_texture_rect(tex, r, true)

## Light falling from above: brighter at the top of `r`, darker below.
static func _sheen(ci: CanvasItem, r: Rect2, top: float, bottom: float) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var hi := Color(1, 0.92, 0.85, top)
	var lo := Color(0, 0, 0, bottom)
	ci.draw_polygon(pts, PackedColorArray([hi, hi, lo, lo]))

## A window: shadow, black and dark rings, gold rim, the grained slate.
static func draw_panel(ci: CanvasItem, r: Rect2) -> void:
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0)
	shadow.shadow_color = Color(0, 0, 0, 0.6)
	shadow.shadow_size = 22
	shadow.shadow_offset = Vector2(0, 10)
	ci.draw_style_box(shadow, r)
	ci.draw_rect(r.grow(5), RING)
	ci.draw_rect(r.grow(6), GOLD_DIM, false, 1.0)
	_tiled(ci, r, slate(), SLATE)
	_sheen(ci, r, 0.03, 0.15)
	ci.draw_rect(r.grow(-1), GOLD, false, 2.0)
	# small gold corners at the foot, as Victoria 3 ends its frames
	for side in [-1.0, 1.0]:
		var x := r.position.x if side < 0 else r.end.x
		var c := Vector2(x, r.end.y)
		ci.draw_line(c + Vector2(0, -26), c, GOLD_LIT, 2.0, true)
		ci.draw_line(c + Vector2(-side * 26, 0), c, GOLD_LIT, 2.0, true)
		ci.draw_circle(c, 4.0, GOLD_LIT)

## The title band: leather, light from above, a gold line and a dark one below.
static func draw_band(ci: CanvasItem, r: Rect2) -> void:
	_tiled(ci, r, leather(), BAND)
	_sheen(ci, r, 0.10, 0.35)
	ci.draw_line(Vector2(r.position.x, r.end.y - 1), Vector2(r.end.x, r.end.y - 1), GOLD, 2.0)
	ci.draw_line(Vector2(r.position.x, r.end.y + 1), Vector2(r.end.x, r.end.y + 1), RING, 1.0)

## A strip of leather rounded at its ends, in a gold rim, with a shadow:
## the bars of map modes and of the build tools.
static func draw_strip(ci: CanvasItem, r: Rect2) -> void:
	var radius := int(minf(r.size.x, r.size.y) * 0.5)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 4)
	box.set_corner_radius_all(radius)
	ci.draw_style_box(box, r)
	var plain := StyleBoxFlat.new()
	plain.bg_color = BAND
	plain.set_corner_radius_all(radius)
	plain.border_color = GOLD
	plain.set_border_width_all(2)
	plain.anti_aliasing = true
	ci.draw_style_box(plain, r)
	if leather() != null: # the grain between the rounded ends
		var inner := r.grow(-3.0)
		var end := minf(inner.size.x, inner.size.y) * 0.5
		var long := inner.grow_individual(-end, 0, -end, 0) if inner.size.x >= inner.size.y else inner.grow_individual(0, -end, 0, -end)
		ci.draw_texture_rect(leather(), long, true, Color(1, 1, 1, 0.9))
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(0, 0, 0, 0)
	ring.border_color = RING
	ring.set_border_width_all(1)
	ring.set_corner_radius_all(radius + 2)
	ring.anti_aliasing = true
	ci.draw_style_box(ring, r.grow(2.0))

## A medallion of radius `r` at `c`: a gold ring round a dark boss with
## `tex` in it, lit (glow, bright gold) or dimmed (switched off); `red` for
## closing; without a texture a cross.
static func draw_medallion(ci: CanvasItem, c: Vector2, r: float, tex: Texture2D, lit: bool, red := false, dim := false) -> void:
	if lit:
		for i in 4:
			ci.draw_circle(c, r + 2.0 + i * 1.5, Color(1.0, 0.84, 0.56, 0.10 - i * 0.02))
	ci.draw_circle(c, r + 1.5, RING)
	ci.draw_circle(c, r, GOLD_LIT if lit else (GOLD_DIM if dim else GOLD))
	var inner := r - maxf(2.5, r * 0.12)
	var dark := Color("1c0c0f") if red else Color("121a16")
	var light := Color("7a3440") if red else Color("56685d")
	ci.draw_circle(c, inner, dark)
	ci.draw_circle(c + Vector2(0, -inner * 0.22), inner * 0.78, dark.lerp(light, 0.2 if dim else 0.45))
	ci.draw_circle(c + Vector2(0, -inner * 0.35), inner * 0.5, dark.lerp(light, 0.35 if dim else 0.8))
	ci.draw_arc(c, inner - 1.0, PI * 1.1, PI * 1.9, 24, Color(1, 1, 1, 0.18), 1.5, true)
	var ink := Color("fff1c8") if lit else Color("e6d7a8")
	if dim:
		ink.a = 0.35
	if tex != null:
		var s := inner * 1.15
		ci.draw_texture_rect(tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, ink)
	else: # no icon: the cross that closes
		var d := inner * 0.42
		ci.draw_line(c + Vector2(-d, -d), c + Vector2(d, d), ink, maxf(2.0, inner * 0.16), true)
		ci.draw_line(c + Vector2(d, -d), c + Vector2(-d, d), ink, maxf(2.0, inner * 0.16), true)

## A thin rule with a gold diamond in its middle.
static func draw_rule(ci: CanvasItem, from: Vector2, to: Vector2) -> void:
	var c := (from + to) * 0.5
	var gap := Vector2(10, 0)
	ci.draw_line(from, c - gap, GOLD_DIM, 1.0)
	ci.draw_line(c + gap, to, GOLD_DIM, 1.0)
	var d := 4.0
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), GOLD)

## BBCode for a title in small caps whose words start with a large gold
## initial («Markt Roma»): for a RichTextLabel with title_font().
static func caps(text: String, font_size := SIZE_TITLE) -> String:
	var big := int(font_size * 1.4)
	var words := PackedStringArray()
	for w in text.split(" "):
		if w.is_empty():
			continue
		words.append("[font_size=%d][color=#%s]%s[/color][/font_size]%s" % [big, GOLD_LIT.to_html(false), w.left(1), w.substr(1)])
	return "[center]%s[/center]" % " ".join(words)

## A title label: small caps, large initials, a dark shadow.
static func title_label(text: String, font_size := SIZE_TITLE) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("normal_font", title_font())
	l.add_theme_font_size_override("normal_font_size", font_size)
	l.add_theme_color_override("default_color", TEXT)
	l.add_theme_color_override("font_shadow_color", SHADOW)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.text = caps(text, font_size)
	return l

static func label(text: String, colour := TEXT, font_size := SIZE_TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", font_size)
	if font != null:
		l.add_theme_font_override("font", font)
	return l

static func box(bg: Color, border: Color, width := 1, radius := 3, margin := 8.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	b.anti_aliasing = true
	return b

## Every control inside a menu window, in this look.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var th := Theme.new()
	th.default_font = serif()
	th.default_font_size = SIZE_TEXT
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_shadow_color", "Label", SHADOW)
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 1)
	for type in ["Button", "OptionButton"]:
		th.set_stylebox("normal", type, _board(OLIVE, GOLD_DIM))
		th.set_stylebox("hover", type, _board(OLIVE_HOVER, GOLD_LIT, 6))
		th.set_stylebox("pressed", type, _board(OLIVE_ON, GOLD_LIT))
		th.set_stylebox("disabled", type, _board(Color(OLIVE, 0.5), Color(GOLD_DIM, 0.4)))
		th.set_stylebox("focus", type, box(Color.TRANSPARENT, GOLD_LIT, 1, 3, 0))
		th.set_color("font_color", type, TEXT)
		th.set_color("font_hover_color", type, Color("fff6dc"))
		th.set_color("font_pressed_color", type, GOLD_LIT)
		th.set_color("font_disabled_color", type, DIM)
		th.set_color("font_shadow_color", type, SHADOW)
		th.set_constant("shadow_offset_x", type, 1)
		th.set_constant("shadow_offset_y", type, 1)
		th.set_font_size("font_size", type, SIZE_BUTTON)
		th.set_constant("h_separation", type, 10)
		th.set_color("icon_normal_color", type, GOLD)
		th.set_color("icon_hover_color", type, GOLD_LIT)
		th.set_color("icon_pressed_color", type, GOLD_LIT)
		th.set_color("icon_focus_color", type, GOLD_LIT)
		th.set_color("icon_disabled_color", type, Color(GOLD, 0.4))
	th.set_color("font_color", "CheckButton", TEXT)
	th.set_color("font_hover_color", "CheckButton", Color("fff6dc"))
	th.set_color("font_pressed_color", "CheckButton", GOLD_LIT)
	th.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	th.set_stylebox("normal", "LineEdit", box(Color("1a1c1d"), GOLD_DIM, 1, 3, 8))
	th.set_stylebox("focus", "LineEdit", box(Color("1a1c1d"), GOLD_LIT, 1, 3, 8))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", DIM)
	th.set_color("caret_color", "LineEdit", GOLD_LIT)
	th.set_stylebox("panel", "PopupMenu", box(SLATE, GOLD, 1, 2, 6))
	th.set_stylebox("hover", "PopupMenu", box(OLIVE_HOVER, Color.TRANSPARENT, 0, 2, 4))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color("fff6dc"))
	# the save list: green rows on the slate under a leather head
	th.set_stylebox("panel", "Tree", box(Color("1d2422"), GOLD_DIM, 1, 2, 2))
	th.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	var head := box(BAND, RING, 0, 0, 6)
	head.border_width_bottom = 1
	head.border_color = GOLD_DIM
	th.set_stylebox("title_button_normal", "Tree", head)
	th.set_stylebox("title_button_pressed", "Tree", head)
	th.set_stylebox("title_button_hover", "Tree", head)
	th.set_color("title_button_color", "Tree", TEXT)
	th.set_color("font_color", "Tree", TEXT)
	th.set_font_size("font_size", "Tree", SIZE_TEXT)
	th.set_font_size("title_button_font_size", "Tree", SIZE_SMALL)
	th.set_color("font_selected_color", "Tree", Color("fff6dc"))
	th.set_stylebox("selected", "Tree", box(LEAF.lightened(0.12), GOLD_LIT, 1, 2, 0))
	th.set_stylebox("selected_focus", "Tree", box(LEAF.lightened(0.12), GOLD_LIT, 1, 2, 0))
	th.set_stylebox("hovered", "Tree", box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0, 0, 0))
	th.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	th.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	th.set_constant("draw_guides", "Tree", 0)
	th.set_constant("draw_relationship_lines", "Tree", 0)
	th.set_constant("v_separation", "Tree", 10)
	th.set_constant("inner_item_margin_left", "Tree", 8)
	for bar in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("grabber", bar, box(GOLD_DIM, RING, 1, 4, 3))
		th.set_stylebox("grabber_highlight", bar, box(GOLD, RING, 1, 4, 3))
		th.set_stylebox("grabber_pressed", bar, box(GOLD_LIT, RING, 1, 4, 3))
		th.set_stylebox("scroll", bar, box(Color(0, 0, 0, 0.4), Color.TRANSPARENT, 0, 4, 3))
	_theme = th
	return th

## A button board: the colour lighter at the top, a gold edge, a glow
## round it when `glow` > 0.
static func _board(bg: Color, edge: Color, glow := 0) -> StyleBoxFlat:
	var b := box(bg, edge, 1, 3, 10)
	b.content_margin_left = 14
	b.content_margin_right = 14
	b.border_width_top = 1
	b.shadow_color = Color(GOLD_LIT, 0.25) if glow > 0 else Color(0, 0, 0, 0.35)
	b.shadow_size = glow if glow > 0 else 2
	return b

## A menu button: olive board, gold icon before the text. `wine` ones leave
## the game; `first` is the one the menu offers first, a shade brighter.
static func button(text: String, icon_name := "", wine := false, first := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 48
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
	if wine:
		b.add_theme_stylebox_override("normal", _board(WINE, Color("8f6a5a")))
		b.add_theme_stylebox_override("hover", _board(WINE_HOVER, GOLD_LIT, 6))
		b.add_theme_stylebox_override("pressed", _board(WINE_HOVER, GOLD_LIT))
	elif first:
		b.add_theme_stylebox_override("normal", _board(OLIVE_ON, GOLD))
	return b

## A round button: a gold ring round a dark boss with an icon, lit under
## the mouse or while `on` (the mode chosen). `red` for closing; without an
## icon it shows a cross.
class Medallion extends Button:
	var on := false
	var _red := false
	var _icon: Texture2D

	func _init(icon_name: String, tip: String, diameter := 44.0, red := false) -> void:
		_red = red
		if icon_name != "":
			_icon = (load("res://scripts/ui/vic3_style.gd") as GDScript).icon(icon_name)
		tooltip_text = tip
		custom_minimum_size = Vector2(diameter, diameter)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_NONE
		flat = true
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var style: GDScript = load("res://scripts/ui/vic3_style.gd")
		style.draw_medallion(self, size * 0.5, minf(size.x, size.y) * 0.5 - 2.0, _icon, is_hovered() or on, _red)
