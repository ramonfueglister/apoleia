extends RefCounted
## How each kind of event is told (ui/game_settings.gd «Meldungen», Ramon
## 31.10.2026, as Victoria 3's message settings): as a window
## (ui/event_window.gd) and a line in the notices, only as a line in the
## notices (ui/notice_list.gd, with its pin on the map), or not at all;
## and whether the game pauses when one happens in view. Read by
## sim/sim_events.gd, kept in user://notices.cfg.

const STORE := "user://notices.cfg"
const WINDOW := 0
const LINE := 1
const NOTHING := 2
const SHOW_NAMES: Array[String] = ["Fenster", "Meldung", "Nichts"]
## the kinds of sim/src/events.rs that make notices, in its order (births,
## weddings and deaths of old age are only scenes on the map)
const KINDS: Array[String] = ["Hungertod", "Umzug", "Verlässt die Karte", "Zieht zu Verwandten", "Diebstahl", "Almosen",
	"Zelt zieht um", "Hof übernommen", "Erbteil", "Ins Zelt", "Hof nach Lex Manciana", "Hof verlassen"]
const ICONS: Array[String] = ["death-skull", "walking-boot", "exit-door", "family-house", "robber-hand", "bread",
	"camping-tent", "barn", "family-tree", "camping-tent", "scroll-quill", "exit-door"]
## rare ones open a window, the daily ones a line (as before the settings)
const DEFAULT_SHOW: Array[int] = [LINE, LINE, LINE, LINE, WINDOW, LINE, LINE, WINDOW, LINE, LINE, WINDOW, WINDOW]

static var _show: Array[int] = []
static var _pause: Array[bool] = []

static func show_of(kind: int) -> int:
	_load()
	return _show[kind] if kind >= 0 and kind < _show.size() else LINE

static func pauses(kind: int) -> bool:
	_load()
	return _pause[kind] if kind >= 0 and kind < _pause.size() else false

static func set_show(kind: int, how: int) -> void:
	_load()
	_show[kind] = how
	_keep()

static func set_pause(kind: int, on: bool) -> void:
	_load()
	_pause[kind] = on
	_keep()

static func reset() -> void:
	_show = DEFAULT_SHOW.duplicate()
	_pause.clear()
	_pause.resize(KINDS.size())
	_pause.fill(false)
	_keep()

static func _load() -> void:
	if not _show.is_empty():
		return
	_show = DEFAULT_SHOW.duplicate()
	_pause.resize(KINDS.size())
	_pause.fill(false)
	var config := ConfigFile.new()
	if config.load(STORE) != OK:
		return
	for k in KINDS.size():
		_show[k] = clampi(int(config.get_value("show", str(k), _show[k])), WINDOW, NOTHING)
		_pause[k] = bool(config.get_value("pause", str(k), false))

static func _keep() -> void:
	var config := ConfigFile.new()
	for k in KINDS.size():
		config.set_value("show", str(k), _show[k])
		config.set_value("pause", str(k), _pause[k])
	config.save(STORE)
