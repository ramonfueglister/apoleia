extends CanvasLayer
## The game clock (docs/kit1/REALTIME_GAMEPLAY.md phases 2 and 4), shown in
## the bar along the top (ui/top_bar.gd, as Victoria 3's): pause, four
## speeds and the date at the right, the number of people, the treasury's
## cash and the grain markets' figures at the left, the red seal opens the
## statistics; the map modes at the foot (ui/map_modes.gd) colour the
## markets' regions, «Handel» shows what the dealers carried between them
## (people_flows.gd, ui/trade_legend.gd). It only sets how many days a
## second the people (people_dots.gd, ApoleiaPeople) run; the sim thread
## computes them and the frame never waits for a day.
##
## The two slow speeds show the hours of the day (Ramon, 30.10.2026: daily
## routines visible, "wie RimWorld"): «Alltag», a day in DAY_MINUTES (the
## travellers walk at their real pace, so a way takes as long on the clock
## as it really does, and leave at their hour), and «Woche», a day in
## WEEK_DAY_S. At both the bar shows the hour (as the epoch names it, here
## the Roman way), the sun rises and sets
## by date and latitude (day_clock.gd) and the houses that cook light their
## lamps at dusk; from two days a second on the light stays as it was.
##
##   Space  pause / run on at the last speed
##   [ ]    slower / faster (speeds 1-6: a day in 4 minutes, a day in
##          10 seconds, then 2, 10, 30, 100 days a second)
##   F8     quick save (user://quicksave.apgame), F9 quick load
##
## Command line (after --): --day-minutes=n a day at «Alltag» in n real
## minutes (default 4; 6 and 25 to compare), --reckoning=modern names the
## hours as a clock does instead of the Roman way (day_clock.gd RECKONINGS),
## --map-mode=<column|trade> starts in a map mode (for renders).
##
## At the left edge the round buttons (ui/main_buttons.gd) open the
## statistics at their topics, the notices and the outliner; the outliner
## at the right (ui/outliner.gd) holds what the player pinned. A kind of
## event set to pause in the settings (ui/notice_settings.gd) pauses the
## game when sim_events.gd says one happened in view. The keys are the
## player's (ui/keys.gd).
##
## When the sim falls behind the speed set, the bar says how many days a
## second it manages. A save holds the seed and the build commands
## (apoleia_sim::game); loading plays them again, so it takes a while.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const SaveGames = preload("res://scripts/ui/save_games.gd")
const TopBar = preload("res://scripts/ui/top_bar.gd")
const MapModes = preload("res://scripts/ui/map_modes.gd")
const TradeLegend = preload("res://scripts/ui/trade_legend.gd")
const Vic3 = preload("res://scripts/ui/vic3_style.gd")
const DayClock = preload("res://scripts/sim/day_clock.gd")
const SimEvents = preload("res://scripts/sim/sim_events.gd")
const Keys = preload("res://scripts/ui/keys.gd")
const Outliner = preload("res://scripts/ui/outliner.gd")
const MainButtons = preload("res://scripts/ui/main_buttons.gd")
const FAST_SPEEDS: Array[float] = [2.0, 10.0, 30.0, 100.0] # days a second, after the two slow ones
const DAY_MINUTES := 4.0 # «Alltag»: a day in real minutes (Ramon, 30.10.2026)
const WEEK_DAY_S := 10.0 # «Woche»: a day in real seconds
const SLOW_NAMES: Array[String] = ["Alltag", "Woche"]
const WEEK_NIGHT := 0.6 # how dark the night gets at «Woche», where it comes every ten seconds
const SAVE_PATH := "user://quicksave.apgame"
const BEHIND := 0.8 # below this share of the speed set the bar warns
const RATE_SECONDS := 2.0 # the days a second are counted over this long
const NOTE_SECONDS := 4.0

var dots: Node # people_dots.gd
var people: RefCounted # ApoleiaPeople
var paused := false
var speeds: Array[float] = [] # days a second: «Alltag», «Woche», then FAST_SPEEDS
var speed := 3 # index into speeds
var day_minutes := DAY_MINUTES
var reckoning := DayClock.RECKONING # how the bar names the hours
var _weather: Node # weather_system.gd, whose light follows the hour at the slow speeds
var _base_time := 0.5 # its time of day as it was, for the fast speeds
var _hour := -1.0 # the hour shown (day_clock.gd), -1 at the fast speeds
var _sun := Vector2(6.0, 18.0) # sunrise and sunset today
var _bar: TopBar
var _modes: MapModes
var _tables: Node # sim_tables.gd, for the seal and the markets' figures
var _trade: TradeLegend
var _events: Node # sim_events.gd, the notices
var _outliner: Outliner
var _buttons: MainButtons
var _flows: Node # people_flows.gd
var _trading := false # the map mode «Handel» is on
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--day-minutes="):
			day_minutes = maxf(float(arg.get_slice("=", 1)), 0.1)
		elif arg.begins_with("--reckoning=") and DayClock.RECKONINGS.has(arg.get_slice("=", 1)):
			reckoning = arg.get_slice("=", 1)
	speeds = [1.0 / (60.0 * day_minutes), 1.0 / WEEK_DAY_S]
	speeds.append_array(FAST_SPEEDS)
	var started: float = dots.days_per_second
	speed = 0
	for i in speeds.size():
		if absf(log(speeds[i] / maxf(started, 0.01))) < absf(log(speeds[speed] / maxf(started, 0.01))):
			speed = i
	paused = started <= 0.0
	var land := dots.get_parent()
	if "weather" in land and land.weather != null:
		_weather = land.weather
		_base_time = _weather.time_of_day
	_bar = TopBar.new()
	_bar.speed_chosen.connect(_choose)
	_bar.save_pressed.connect(save_game)
	_bar.load_pressed.connect(load_game)
	_bar.seal_pressed.connect(_toggle_tables)
	add_child(_bar)
	_bar.set_speed_tip("Tempo  ([ ])\n%s: ein Tag dauert %s\n%s: ein Tag dauert %d Sekunden\ndann 2, 10, 30 und 100 Tage pro Sekunde" % [
		SLOW_NAMES[0], ("%d Minuten" % int(day_minutes)) if is_equal_approx(day_minutes, roundf(day_minutes)) else ("%.1f Minuten" % day_minutes),
		SLOW_NAMES[1], int(WEEK_DAY_S)])
	Keys.setup()
	for c in dots.get_children():
		if c.get_script() == SimTables:
			_tables = c
		elif c.get_script() == SimEvents:
			_events = c
	if _events != null and _events.has_signal("pause_asked"):
		_events.pause_asked.connect(_pause_for)
	_outliner = Outliner.new()
	_outliner.dots = dots
	_outliner.tables = _tables
	_outliner.landscape = land
	add_child(_outliner)
	_buttons = MainButtons.new()
	_buttons.chosen.connect(_main_button)
	add_child(_buttons)
	_modes = MapModes.new()
	_modes.chosen.connect(_colour_map)
	_modes.visible = _tables != null and _tables.has_method("colour_map")
	add_child(_modes)
	if _modes.visible:
		_tables.legend_over = _modes
	_trade = TradeLegend.new()
	add_child(_trade)
	_trade.over = _modes
	if dots.has_method("flows"):
		_flows = dots.flows()
		_trade.good_chosen.connect(_flows.choose_good)
		_flows.changed.connect(func(): _trade.show_scale(_flows))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map-mode="): # a map mode from the start, for renders
			_colour_map.call_deferred(arg.trim_prefix("--map-mode="))
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

## 0 pauses (or runs on, when already paused), 1-6 set a speed and run.
func _choose(kind: int) -> void:
	if kind == 0:
		paused = not paused
	else:
		speed = kind - 1
		paused = false
	_apply()

func _apply() -> void:
	dots.days_per_second = 0.0 if paused or _loading else speeds[speed]
	_rate_day = -1
	_show_date()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if Keys.pressed(event, "apoleia_pause"):
		_choose(0)
	elif Keys.pressed(event, "apoleia_slower"):
		_choose(maxi(speed, 1))
	elif Keys.pressed(event, "apoleia_faster"):
		_choose(mini(speed + 2, speeds.size()))
	elif Keys.pressed(event, "apoleia_quicksave"):
		save_game()
	elif Keys.pressed(event, "apoleia_quickload"):
		load_game()
	elif Keys.pressed(event, "apoleia_outliner") and _outliner != null:
		_outliner.toggle()
	else:
		return
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
	_daytime()
	_show_date()
	_light_buttons()
	if _tables != null and _tables.has_method("map_column"):
		var column: String = _tables.map_column()
		if _trading and column != "":
			_colour_map(column) # «Karte färben» in the statistics ends «Handel»
		_modes.show_mode("trade" if _trading else column) # and colours the map too

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

## The hour at the slow speeds: the light, the travellers' pace and the
## lamps follow it; at the fast speeds everything goes back to how it was.
func _daytime() -> void:
	if speed >= SLOW_NAMES.size() or _loading:
		if _hour >= 0.0:
			_hour = -1.0
			dots.set_day_time(-1.0, _sun, 0.0, false)
			if _weather != null:
				_weather.time_of_day = _base_time
				_weather.night = 0.0
		return
	var clock: float = dots.clock_day
	var day := int(floor(clock))
	var land := dots.get_parent()
	_sun = DayClock.daylight(day, DayClock.latitude(land.target) if "target" in land else 41.9)
	_hour = DayClock.hour(clock - day, _sun)
	if _weather != null and _weather.day_cycle_seconds <= 0.0:
		var light := DayClock.light(_hour, _sun)
		_weather.time_of_day = light.x
		_weather.night = light.y * (1.0 if speed == 0 else WEEK_NIGHT)
	# real pace only at «Alltag»: at ten seconds a day a walk would be a blink
	dots.set_day_time(_hour, _sun, 60.0 * day_minutes if speed == 0 else 0.0, paused)

func _show_date() -> void:
	if _bar == null or people == null:
		return
	var behind := not paused and not _loading and speeds[speed] >= 1.0 and _rate > 0.0 and _rate < speeds[speed] * BEHIND
	var date := _day_text(int(people.day()))
	if _hour >= 0.0:
		date = "%s · %s" % [DayClock.label(_hour, _sun, reckoning), date]
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
## «Karte färben» in the statistics does, or "trade": the flows of goods
## over the map greyed.
func _colour_map(column: String) -> void:
	if _tables == null or not _tables.has_method("colour_map"):
		return
	_trading = column == "trade" and _flows != null
	if column == "trade" and not _trading:
		column = ""
	if _flows != null:
		dots.mute_map(_trading)
		_flows.show_mode(_trading)
	_trade.visible = _trading
	_tables.colour_map("" if _trading else column)
	_modes.show_mode("trade" if _trading else column)

## A round button at the left: the statistics at a topic (or closed, when
## that topic is shown), the notices, the outliner.
func _main_button(key: String) -> void:
	match key:
		"events":
			if _events != null:
				_events._show(not _events.open)
		"outliner":
			_outliner.toggle()
		_:
			if _tables == null:
				return
			if _tables.open and _topic_shown() == _topic_of(key):
				_tables._show(false)
			elif _tables.has_method("open_at"):
				_tables.open_at(key)
			else:
				_tables._show(true)

## The buttons whose windows are open lit.
func _light_buttons() -> void:
	var lit := []
	if _tables != null and _tables.open:
		var topic := _topic_shown()
		for b in MainButtons.BUTTONS:
			if b[4] == 0 and _topic_of(b[0]) == topic:
				lit.append(b[0])
	if _events != null and _events.open:
		lit.append("events")
	if _outliner.visible:
		lit.append("outliner")
	_buttons.light(lit)

## The statistics' topic a button opens: the buttons of the first group
## follow the topics of sim_tables.gd VIEWS in order.
static func _topic_of(key: String) -> int:
	for i in MainButtons.BUTTONS.size():
		if MainButtons.BUTTONS[i][0] == key:
			return i if MainButtons.BUTTONS[i][4] == 0 else -1
	return -1

## The topic the statistics show (0 where they have no topics yet).
func _topic_shown() -> int:
	return int(_tables._topic) if "_topic" in _tables else 0

## A kind of event set to pause happened in view (sim_events.gd).
func _pause_for(text: String) -> void:
	if not paused and not _loading:
		paused = true
		_apply()
	_tell("Pause: %s" % text)

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
