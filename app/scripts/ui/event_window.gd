extends "res://scripts/ui/menu_panel.gd"
## A window for one event, as Victoria 3 shows them: the title on the
## wine-red band, below it a picture in a gold frame with the event's kind
## as a medallion on its lower edge, the date and place in italics, the
## text, the figures in green rows, the people as links, and the answers
## as wide buttons. It only shows what it is given: which events open one
## and when is decided by its caller (the events, sim/sim_events.gd).
##
##   EventWindow.open(get_tree(), {
##       "title": "Hungersnot in Ostia",
##       "kind": "Hunger", "icon": "wheat",   # the medallion; both may be left out
##       "date": "Martius, Jahr 12", "place": "Ostia",
##       "image": texture,                    # null: no picture
##       "text": "BBCode",
##       "figures": [{"label": "Verhungert", "value": "38 Menschen"}],
##       "people": [{"pid": 41, "household": 7, "label": "Haushalt 7", "role": "Dieb"}],
##       "at": Vector2(km_x, km_y),           # a «Hinfliegen» button
##       "options": [{"text": "Verstanden", "icon": "play-button", "action": callable}],
##   })
##
## The window emits fly_to(at) and person(pid, household); the caller
## moves the camera or opens the person. Any answer closes it, as does Esc.
## The people get their faces once the caller has them (show_faces), and
## a household's link then the name of the one shown, with its role.

const LAYER := 12 # over the windows (10), under tooltips (20) and the pause menu (30)
const WIDTH := 600.0
const IMAGE_PX := 290.0
const SEAL_PX := 64.0
const FACE := 0.5 # the people's faces, portrait_view.gd at 56 x 70

const PortraitView = preload("res://scripts/ui/portrait_view.gd")

signal fly_to(at: Vector2)
signal person(pid: int, household: int)

static var _layer: CanvasLayer

var _faces := {} # household -> the holder of its face, hidden until shown
var _links := {} # household -> {button, role}: named once its face is known

## Opens the window for `d` (fields above) and returns it.
static func open(tree: SceneTree, d: Dictionary) -> Control:
	if not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "EventWindows"
		_layer.layer = LAYER
		tree.root.add_child(_layer)
	var w = load("res://scripts/ui/event_window.gd").new(d)
	_layer.add_child(w)
	return w

func _init(d: Dictionary) -> void:
	super(d.get("title", "Ereignis"), WIDTH)
	closed.connect(queue_free)
	var image: Texture2D = d.get("image")
	if image != null:
		body.add_child(_picture(image, d.get("icon", ""), d.get("kind", "")))
	var when := PackedStringArray()
	for part in [d.get("date", ""), d.get("place", "")]:
		if part != "":
			when.append(part)
	set_subtitle(" · ".join(when))
	if image != null: # the date stands under the picture, not above it
		body.move_child(_sub, body.get_child_count() - 1)
	elif d.get("kind", "") != "":
		var kind := Vic3.label(d.kind, Vic3.CONCEPT, Vic3.SIZE_SMALL + 1, Vic3.italic())
		kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(kind)
		body.move_child(kind, 0)
	if d.get("text", "") != "":
		body.add_child(_text(d.text))
	var figures: Array = d.get("figures", [])
	if not figures.is_empty():
		body.add_child(_figures(figures))
	var people: Array = d.get("people", [])
	if not people.is_empty():
		body.add_child(_people(people))
	gap(body, 14)
	var options: Array = d.get("options", [])
	if options.is_empty():
		options = [{"text": "Verstanden", "icon": "play-button"}]
	if d.has("at"):
		var at: Vector2 = d.at
		options = options + [{"text": "Hinfliegen", "icon": "eagle-emblem", "action": func(): fly_to.emit(at), "stay": true}]
	for i in options.size():
		var o: Dictionary = options[i]
		var b := Vic3.button(o.get("text", ""), o.get("icon", ""), false, i == 0)
		var action: Callable = o.get("action", Callable())
		var stay: bool = o.get("stay", false)
		b.pressed.connect(func():
			if action.is_valid():
				action.call()
			if not stay:
				closed.emit())
		body.add_child(b)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()

## The picture, cut to fill its frame, the kind's medallion half over its foot.
func _picture(image: Texture2D, icon_name: String, kind: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size.y = IMAGE_PX + SEAL_PX * 0.5
	var pic := TextureRect.new()
	pic.texture = image
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.clip_contents = true
	pic.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pic.offset_bottom = IMAGE_PX
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_TOP_WIDE)
	frame.offset_bottom = IMAGE_PX
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func(): _draw_frame(frame))
	holder.add_child(frame)
	if icon_name != "":
		var seal := Vic3.Medallion.new(icon_name, kind, SEAL_PX)
		seal.mouse_default_cursor_shape = Control.CURSOR_ARROW
		seal.set_anchors_preset(Control.PRESET_CENTER_TOP)
		seal.offset_left = -SEAL_PX * 0.5
		seal.offset_right = SEAL_PX * 0.5
		seal.offset_top = IMAGE_PX - SEAL_PX * 0.5
		seal.offset_bottom = IMAGE_PX + SEAL_PX * 0.5
		holder.add_child(seal)
	return holder

## A dark edge falling into the picture, a black line and a gold one round it.
func _draw_frame(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	for k in 10:
		var a := 0.05 * (10 - k)
		c.draw_rect(r.grow(-k * 2.0), Color(0, 0, 0, a * 0.5), false, 2.0)
	c.draw_rect(r.grow(1.0), Vic3.RING, false, 2.0)
	c.draw_rect(r.grow(2.5), Vic3.GOLD, false, 1.5)

func _text(bbcode: String) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.add_theme_font_override("normal_font", Vic3.serif())
	t.add_theme_font_override("italics_font", Vic3.italic())
	t.add_theme_font_override("bold_font", Vic3.bold())
	for kind in ["normal", "italics", "bold"]:
		t.add_theme_font_size_override(kind + "_font_size", Vic3.SIZE_TEXT + 1)
	t.add_theme_color_override("default_color", Vic3.TEXT)
	t.add_theme_constant_override("line_separation", 3)
	t.text = bbcode
	return t

## The figures as rows of dark green, the value right in gold.
func _figures(figures: Array) -> Control:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	for i in figures.size():
		var f: Dictionary = figures[i]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", Vic3.box(Vic3.LEAF if i % 2 == 0 else Color("1c2724"), Color.TRANSPARENT, 0, 2, 6))
		var line := HBoxContainer.new()
		row.add_child(line)
		var what := Vic3.label(f.get("label", ""), Vic3.TEXT, Vic3.SIZE_TEXT)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(what)
		line.add_child(Vic3.label(str(f.get("value", "")), Vic3.GOLD_LIT, Vic3.SIZE_TEXT, Vic3.bold()))
		rows.add_child(row)
	return rows

## The faces of the people by household, as ApoleiaPeople.take_faces
## gives them; a household without one keeps its link alone.
func show_faces(faces: Dictionary) -> void:
	for h in _faces:
		if faces.has(h):
			var holder: Control = _faces[h]
			holder.visible = holder.get_child(0).show_person(faces[h])
			# the household by the name of the one shown, its role kept
			var face: Dictionary = faces[h]
			if face.has("name") and _links.has(h):
				var link: Dictionary = _links[h]
				var role: String = link.role
				link.button.text = "Haushalt %s %s%s" % ["der" if face.get("female", false) else "des", face.name, " (%s)" % role if role != "" else ""]

## The people the event is about, each a link that opens them, over it
## their face once it is known (show_faces), which opens them too.
func _people(people: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_child(Vic3.label("Beteiligt:", Vic3.DIM, Vic3.SIZE_TEXT, Vic3.italic()))
	for p in people:
		var pid: int = p.get("pid", -1)
		var household: int = p.get("household", -1)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		flow.add_child(column)
		var holder := Control.new()
		holder.custom_minimum_size = PortraitView.SIZE * FACE
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		holder.visible = false
		holder.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				person.emit(pid, household))
		var face := PortraitView.new()
		face.scale = Vector2(FACE, FACE)
		face.rim = 1.6
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(face)
		column.add_child(holder)
		var b := LinkButton.new()
		if household >= 0:
			_faces[household] = holder
			_links[household] = {"button": b, "role": p.get("role", "")}
		b.text = p.get("label", "")
		b.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		b.add_theme_color_override("font_color", Vic3.CONCEPT)
		b.add_theme_color_override("font_hover_color", Vic3.GOLD_LIT)
		b.add_theme_font_override("font", Vic3.serif())
		b.add_theme_font_size_override("font_size", Vic3.SIZE_TEXT)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func(): person.emit(pid, household))
		column.add_child(b)
	return flow
