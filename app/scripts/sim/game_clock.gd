extends CanvasLayer
## The game clock (docs/kit1/REALTIME_GAMEPLAY.md phases 2 and 4): a bar at
## the top centre with pause, four speeds, the date, the number of people and
## the treasury's cash, as in Cities: Skylines. It only sets how many days a second the people
## (people_dots.gd, ApoleiaPeople) run; the sim thread computes them and the
## frame never waits for a day.
##
##   Space  pause / run on at the last speed
##   [ ]    slower / faster (speeds 1-4: 2, 10, 30, 100 days a second)
##   F8     quick save (user://quicksave.apgame), F9 quick load
##
## When the sim falls behind the speed set, the bar says how many days a
## second it manages. A save holds the seed and the build commands
## (apoleia_sim::game); loading plays them again, so it takes a while.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const SaveGames = preload("res://scripts/ui/save_games.gd")
const SPEEDS: Array[float] = [2.0, 10.0, 30.0, 100.0] # days a second
const SAVE_PATH := "user://quicksave.apgame"
const BEHIND := 0.8 # below this share of the speed set the bar warns
const RATE_SECONDS := 2.0 # the days a second are counted over this long
const NOTE_SECONDS := 4.0

var dots: Node # people_dots.gd
var people: RefCounted # ApoleiaPeople
var paused := false
var speed := 1 # index into SPEEDS
var _buttons: Array[ClockButton] = []
var _date: Label
var _note: Label
var _note_until := 0.0
var _rate := 0.0 # days a second, measured
var _rate_day := -1
var _rate_clock := 0.0
var _saving := false
var _save_path := SAVE_PATH
var _loading := false

## Takes over the speed people_dots.gd started with (--people-days) as the
## nearest speed, and builds the bar.
func setup(people_dots: Node) -> void:
	name = "GameClock"
	layer = 4
	dots = people_dots
	people = people_dots.people
	var started: float = dots.days_per_second
	speed = 0
	for i in SPEEDS.size():
		if absf(log(SPEEDS[i] / maxf(started, 0.01))) < absf(log(SPEEDS[speed] / maxf(started, 0.01))):
			speed = i
	paused = started <= 0.0
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(SimTables.HEAD, 0.92)
	box.border_color = Color(SimTables.GOLD, 0.45)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", box)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	for kind in SPEEDS.size() + 1: # 0 pause, then the speeds
		var b := ClockButton.new()
		b.kind = kind
		b.tooltip_text = "Pause  (Leertaste)" if kind == 0 else "Tempo %d: %d Tage pro Sekunde  ([ ])" % [kind, int(SPEEDS[kind - 1])]
		b.chosen.connect(_choose.bind(kind))
		row.add_child(b)
		_buttons.append(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(6, 0)
	row.add_child(gap)
	_date = _label(16, SimTables.INK)
	_date.custom_minimum_size = Vector2(420, 0)
	row.add_child(_date)
	for kind in [ClockButton.SAVE, ClockButton.LOAD]:
		var b := ClockButton.new()
		b.kind = kind
		b.tooltip_text = "Speichern  (F8)" if kind == ClockButton.SAVE else "Laden  (F9)"
		b.chosen.connect(save_game if kind == ClockButton.SAVE else load_game)
		row.add_child(b)
	_note = _label(13, SimTables.GOLD)
	_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 58)
	_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_note)
	_apply()

static func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## 0 pauses (or runs on, when already paused), 1-4 set a speed and run.
func _choose(kind: int) -> void:
	if kind == 0:
		paused = not paused
	else:
		speed = kind - 1
		paused = false
	_apply()

func _apply() -> void:
	dots.days_per_second = 0.0 if paused or _loading else SPEEDS[speed]
	_rate_day = -1
	for b in _buttons:
		b.active = (b.kind == 0 and paused) or (not paused and b.kind == speed + 1)
		b.queue_redraw()
	_show_date()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: _choose(0)
		KEY_BRACKETLEFT: _choose(maxi(speed, 1))
		KEY_BRACKETRIGHT: _choose(mini(speed + 2, SPEEDS.size()))
		KEY_F8: save_game()
		KEY_F9: load_game()
		_: return
	get_viewport().set_input_as_handled()

## The quick save, or another file (the menus' save games, ui/save_games.gd).
func save_game(path := SAVE_PATH) -> void:
	if _saving or _loading:
		return
	_save_path = path
	people.save_game(ProjectSettings.globalize_path(path))
	_saving = true

## Plays the quick save again; the game runs on paused once it has.
func load_game(path := SAVE_PATH) -> void:
	if _loading:
		return
	if not FileAccess.file_exists(path):
		_tell("Kein Spielstand (F8 speichert)")
		return
	if not people.load_game(ProjectSettings.globalize_path(path)):
		_tell("Spielstand passt nicht zu dieser Welt")
		return
	_loading = true
	paused = true
	_apply()

func _tell(text: String) -> void:
	_note.text = text
	_note_until = Time.get_ticks_msec() / 1000.0 + NOTE_SECONDS

func _process(delta: float) -> void:
	if _saving:
		var s: Dictionary = people.take_saved()
		if not s.is_empty():
			_saving = false
			if s.ok:
				SaveGames.remember(_save_path, "", int(s.day))
			_tell("Gespeichert: %s" % _day_text(int(s.day)) if s.ok else "Speichern ging nicht: %s" % s.error)
	if _loading:
		var l: Dictionary = people.take_loaded()
		if l.is_empty():
			var at: Dictionary = people.loading()
			if not at.is_empty():
				_note.text = "Spielstand wird geladen … %d %%" % int(100.0 * at.day / maxf(at.of, 1.0))
				_note_until = INF
		else:
			_loading = false
			dots.restarted()
			_tell("Geladen: %s%s" % [_day_text(int(l.day)), "" if l.identical else " (Sim seither geändert, Welt weicht ab)"])
			_apply()
	if Time.get_ticks_msec() / 1000.0 > _note_until:
		_note.text = ""
	_measure(delta)
	_show_date()

## Days a second the sim actually made over the last RATE_SECONDS.
func _measure(delta: float) -> void:
	var day: int = people.day()
	if _rate_day < 0 or paused or _loading:
		_rate_day = day
		_rate_clock = 0.0
		return
	_rate_clock += delta
	if _rate_clock >= RATE_SECONDS:
		_rate = (day - _rate_day) / _rate_clock
		_rate_day = day
		_rate_clock = 0.0

func _show_date() -> void:
	if _date == null or people == null:
		return
	var cash: int = int(people.cash())
	# an empty treasury pays the state wage with new coins (S95)
	var purse := "Kasse %s Denar" % _amount(cash) if cash > 0 else "Kasse leer"
	var text := "%s · %s Menschen · %s" % [_day_text(int(people.day())), _amount(people.count()), purse]
	if not paused and not _loading and _rate > 0.0 and _rate < SPEEDS[speed] * BEHIND:
		text += " · Sim schafft %d Tage/s" % int(_rate)
		_date.add_theme_color_override("font_color", SimTables.GOLD)
	else:
		_date.add_theme_color_override("font_color", SimTables.INK)
	_date.text = text

static func _day_text(day: int) -> String:
	return "%d. %s" % [day % SimTables.MONTH + 1, SimTables._date(day)]

## 116805 as 116'805 (Swiss thousands).
static func _amount(n: int) -> String:
	if n < 0:
		return "-" + _amount(-n)
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "'" + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out

## A square button with a drawn sign: pause bars, one to four play
## triangles, a disk to save, an arrow out of a box to load.
class ClockButton extends Control:
	const SIZE := Vector2(34, 30)
	const SAVE := 10
	const LOAD := 11
	signal chosen
	var kind := 0
	var active := false

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var hover := get_global_rect().has_point(get_global_mouse_position())
		var box := StyleBoxFlat.new()
		box.bg_color = Color(SimTables.SELECTED if active or hover else SimTables.HEAD, 0.92)
		box.border_color = SimTables.GOLD if active else Color(SimTables.GOLD, 0.8 if hover else 0.35)
		box.set_border_width_all(2 if active else 1)
		box.set_corner_radius_all(3)
		draw_style_box(box, Rect2(Vector2.ZERO, SIZE))
		var ink := SimTables.GOLD if active else SimTables.INK
		var c := SIZE * 0.5
		match kind:
			0: # pause: two bars
				draw_rect(Rect2(c + Vector2(-6, -7), Vector2(4, 14)), ink)
				draw_rect(Rect2(c + Vector2(2, -7), Vector2(4, 14)), ink)
			SAVE: # a disk
				draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), ink, false, 2.0)
				draw_rect(Rect2(c + Vector2(-4, -8), Vector2(8, 5)), ink)
				draw_rect(Rect2(c + Vector2(-5, 2), Vector2(10, 6)), ink, false, 1.5)
			LOAD: # an arrow up out of a tray
				draw_polyline(PackedVector2Array([c + Vector2(-8, 2), c + Vector2(-8, 8), c + Vector2(8, 8), c + Vector2(8, 2)]), ink, 2.0)
				draw_line(c + Vector2(0, 4), c + Vector2(0, -8), ink, 2.0)
				draw_polyline(PackedVector2Array([c + Vector2(-4, -4), c + Vector2(0, -8), c + Vector2(4, -4)]), ink, 2.0)
			_: # speed n: n small triangles side by side
				var n := kind
				var w := 6.0
				var x0 := -(n * w) * 0.5
				for k in n:
					var x := x0 + k * w
					draw_colored_polygon(PackedVector2Array([c + Vector2(x, -6), c + Vector2(x + w, 0), c + Vector2(x, 6)]), ink)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit()
			accept_event()
