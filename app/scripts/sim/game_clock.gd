extends CanvasLayer
## The game clock (docs/kit1/REALTIME_GAMEPLAY.md phases 2 and 4), shown in
## the bar along the top (ui/top_bar.gd, as Victoria 3's): pause, four
## speeds and the date at the right, the number of people, the treasury's
## cash and the grain markets' figures at the left, the red seal opens the
## statistics; the map modes at the foot (ui/map_modes.gd) colour the
## markets' regions. It only sets how many days a second the people
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
const TopBar = preload("res://scripts/ui/top_bar.gd")
const MapModes = preload("res://scripts/ui/map_modes.gd")
const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const SPEEDS: Array[float] = [2.0, 10.0, 30.0, 100.0] # days a second
const SAVE_PATH := "user://quicksave.apgame"
const BEHIND := 0.8 # below this share of the speed set the bar warns
const RATE_SECONDS := 2.0 # the days a second are counted over this long
const NOTE_SECONDS := 4.0

var dots: Node # people_dots.gd
var people: RefCounted # ApoleiaPeople
var paused := false
var speed := 1 # index into SPEEDS
var _bar: TopBar
var _modes: MapModes
var _tables: Node # sim_tables.gd, for the seal and the markets' figures
var _markets_day := -1 # the markets' monthly count last shown
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
	_bar = TopBar.new()
	_bar.speed_chosen.connect(_choose)
	_bar.save_pressed.connect(save_game)
	_bar.load_pressed.connect(load_game)
	_bar.seal_pressed.connect(_toggle_tables)
	add_child(_bar)
	for c in dots.get_children():
		if c.get_script() == SimTables:
			_tables = c
	_modes = MapModes.new()
	_modes.chosen.connect(_colour_map)
	_modes.visible = _tables != null and _tables.has_method("colour_map")
	add_child(_modes)
	if _modes.visible:
		_tables.legend_over = _modes
	_note = _label(14, Vic3.GOLD_LIT)
	_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, TopBar.HEIGHT + 12)
	_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override("font_shadow_color", Vic3.SHADOW)
	_note.add_theme_constant_override("shadow_offset_y", 1)
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
	if _tables != null and _tables.has_method("map_column"):
		_modes.show_mode(_tables.map_column()) # «Karte färben» in the statistics colours it too

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
	if _bar == null or people == null:
		return
	var behind := not paused and not _loading and _rate > 0.0 and _rate < SPEEDS[speed] * BEHIND
	var date := _day_text(int(people.day()))
	if behind:
		date += " · Sim schafft %d Tage/s" % int(_rate)
	_bar.set_clock(date, paused or _loading, speed + 1, behind)
	_bar.set_figure("people", "family-house", _amount(people.count()), "Menschen", Vic3.TEXT, "Alle Menschen auf der Karte, jeder einzeln simuliert.")
	var cash: int = int(people.cash())
	# an empty treasury pays the state wage with new coins (S95)
	_bar.set_figure("cash", "two-coins", _amount(cash) if cash > 0 else "leer", "Denar in der Kasse", Vic3.TEXT if cash > 0 else Vic3.LOSS,
		"Denar in der Staatskasse. Ist sie leer, zahlt der Staat den Lohn mit neu geprägten Münzen.")
	_show_markets()

## The grain markets' figures from the markets table the statistics ask
## for each month (sim_tables.gd), once per monthly count.
func _show_markets() -> void:
	if _tables == null or not "_tables" in _tables or _tables._tables.is_empty():
		return
	var t: Dictionary = _tables._tables[0]
	if t.is_empty() or int(t.day) == _markets_day:
		return
	_markets_day = int(t.day)
	var d: Dictionary = t.data
	if not d.has("price") or not d.has("persons"):
		return
	# the price people pay: the median of the markets weighted by their people (grain.rs price_spread)
	var rows := []
	var total := 0.0
	var hungry := 0.0
	var store := 0.0
	for r in d.persons.size():
		var n := float(d.persons[r])
		if n > 0.0:
			rows.append([float(d.price[r]), n])
			total += n
			if d.has("share_hungry"):
				hungry += float(d.share_hungry[r]) * n
		if d.has("store_kg"):
			store += float(d.store_kg[r])
	if total <= 0.0:
		return
	rows.sort_custom(func(a, b): return a[0] < b[0])
	var acc := 0.0
	var median: float = rows[0][0]
	for row in rows:
		acc += row[1]
		if acc * 2.0 >= total:
			median = row[0]
			break
	var share := hungry / total
	_bar.set_figure("hungry", "knife-fork", "%.1f %%" % (100.0 * share), "hungernd", Vic3.LOSS if share >= 0.05 else Vic3.TEXT,
		"Anteil der Menschen, die im Monat nicht satt geworden sind, über alle Märkte.")
	_bar.set_figure("price", "wheat", "%.2f D/kg" % median, "Kornpreis", Vic3.TEXT,
		"Der Kornpreis, den die Menschen zahlen: der Median der Märkte, gewichtet nach ihren Menschen.")
	_bar.set_figure("store", "granary", "%s t" % _amount(int(store / 1000.0)), "Korn auf den Märkten", Vic3.TEXT,
		"Korn in den Lagern der Händler auf allen Märkten.")

## A map mode: the markets' regions coloured by `column` ("" none), as
## «Karte färben» in the statistics does.
func _colour_map(column: String) -> void:
	if _tables == null or not _tables.has_method("colour_map"):
		return
	_tables.colour_map(column)
	_modes.show_mode(column)

## The red seal: the statistics open or close, as with T.
func _toggle_tables() -> void:
	if _tables != null and _tables.has_method("_show"):
		_tables._show(not _tables.open)

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
