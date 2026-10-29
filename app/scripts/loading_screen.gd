extends CanvasLayer
## The loading screen while the landscape starts (Ramon 29.10.2026: "dann
## brauchen wir ladefenster", "fortschrittsbalken"): over the whole window
## the name of the game, what is loading now and a progress bar, in the
## EU5 look of the tables (app/scripts/ui/ui_style.gd: slate panel, bronze
## frame and fill, cream text, a serif). Before it the window stayed grey
## for most of a minute.
##
## landscape.gd loads in steps and calls `await step(name)` before each, so
## the screen is drawn between them; `await finish()` keeps it up over the
## first drawn frames (the shaders compile there) and fades it out. A step
## blocks while it runs, so the bar moves by steps: each step's share is
## its time on the last start (user://loading.cfg), so the bar moves
## about evenly; the first start guesses (GUESS_MS).

const TIMES_PATH := "user://loading.cfg"
const GUESS_MS := {"terrain": 6000.0, "look": 500.0, "people": 12000.0, "build": 500.0, "draw": 4000.0}
const SLATE := Color("1a222b")
const INSET := Color("10161c")
const BRONZE := Color("8a6a3c")
const BRONZE_LIT := Color("d1ad66")
const CREAM := Color("e6dcc6")
const TITLE := Color("f1e4c4")
const BAR := Vector2(560, 18)
const FADE_S := 0.35
const DRAW_FRAMES := 3 # frames drawn behind the screen before it fades

var _shares := {} # step -> share of the whole, from the last start
var _order: Array[String] = []
var _done := 0.0 # share of the steps finished
var _current := ""
var _started := 0
var _times := {} # step -> ms this start
var _root: Control
var _label: Label
var _fill: Panel
var _percent: Label

func _init(steps: Array[String]) -> void:
	layer = 100 # above the tables and the build menu
	_order = steps
	var last := ConfigFile.new()
	var ok := last.load(TIMES_PATH) == OK
	var total := 0.0
	for s in steps:
		total += float(last.get_value("ms", s, GUESS_MS.get(s, 1000.0)) if ok else GUESS_MS.get(s, 1000.0))
	for s in steps:
		var ms: float = last.get_value("ms", s, GUESS_MS.get(s, 1000.0)) if ok else GUESS_MS.get(s, 1000.0)
		_shares[s] = ms / maxf(total, 1.0)
	_build()

## Starts step `name` (one of the steps given to new()) with `text` shown,
## after the screen has been drawn with it.
func step(name: String, text: String) -> void:
	_close_step()
	_current = name
	_label.text = text
	_show_progress()
	_started = Time.get_ticks_msec()
	await _drawn() # the screen is on before the step blocks

## Ends the last step, waits for the first frames of the landscape behind
## the screen and fades it out; `quick` (snapshots, benches) takes it away
## at once.
func finish(text: String, quick := false) -> void:
	_close_step()
	if quick:
		_save()
		queue_free()
		return
	_current = "draw"
	_label.text = text
	_show_progress()
	_started = Time.get_ticks_msec()
	for i in DRAW_FRAMES:
		await _drawn()
	_close_step()
	_save()
	var fade := create_tween()
	fade.tween_property(_root, "modulate:a", 0.0, FADE_S)
	await fade.finished
	queue_free()

## A frame drawn (headless runs draw none, so a frame processed).
func _drawn() -> void:
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw

func _close_step() -> void:
	if _current == "":
		return
	_times[_current] = float(Time.get_ticks_msec() - _started)
	print(JSON.stringify({"event": "load_step", "step": _current, "ms": _times[_current]}))
	_done += _shares.get(_current, 0.0)
	_current = ""
	_show_progress()

## How far the current step is (0..1), for a step that lets frames through
## while it works (tile_terrain.gd load_data).
func part(share: float) -> void:
	_show_progress(_done + clampf(share, 0.0, 1.0) * _shares.get(_current, 0.0))

func _show_progress(done := -1.0) -> void:
	var share := clampf(_done if done < 0.0 else done, 0.0, 1.0)
	_fill.size.x = maxf(BAR.x * share - 4.0, 0.0)
	_percent.text = "%d %%" % roundi(share * 100.0)

## The times of this start for the next one; a step that did not run keeps its old time.
func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(TIMES_PATH)
	for s in _times:
		cfg.set_value("ms", s, _times[s])
	cfg.save(TIMES_PATH)

func _build() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Palatino", "Book Antiqua", "Georgia", "Times New Roman", "serif"])
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP # no clicks through to the map while it loads
	add_child(_root)
	var back := ColorRect.new()
	back.color = SLATE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(back)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	centre.add_child(column)
	var title := _text("APOLEIA", font, 64, TITLE)
	title.add_theme_constant_override("outline_size", 0)
	column.add_child(title)
	var rule := ColorRect.new()
	rule.color = BRONZE
	rule.custom_minimum_size = Vector2(BAR.x, 1)
	column.add_child(rule)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	column.add_child(spacer)
	var row := HBoxContainer.new()
	column.add_child(row)
	_label = _text("", font, 20, CREAM)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	_percent = _text("0 %", font, 20, CREAM)
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_percent)
	# the bar: an inset box framed in bronze, the fill bronze with a lighter top
	var frame := Panel.new()
	frame.custom_minimum_size = BAR
	var inset := StyleBoxFlat.new()
	inset.bg_color = INSET
	inset.border_color = BRONZE
	inset.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", inset)
	column.add_child(frame)
	_fill = Panel.new()
	_fill.position = Vector2(2, 2)
	_fill.size = Vector2(0, BAR.y - 4.0)
	var bronze := StyleBoxFlat.new()
	bronze.bg_color = BRONZE_LIT
	bronze.border_color = BRONZE_LIT.lightened(0.35)
	bronze.border_width_top = 2 # the gloss along its top
	_fill.add_theme_stylebox_override("panel", bronze)
	frame.add_child(_fill)

static func _text(s: String, font: Font, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = s
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label
