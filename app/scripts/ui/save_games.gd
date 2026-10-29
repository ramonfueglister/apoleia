extends RefCounted
## The save games the menus list: the quick save (F8) and named ones in
## user://saves/. A save itself is the sim's command log (apoleia_sim::game);
## beside each lies a small .cfg with its name, the game day and when it was
## written, so the list needs no replay to show them.
##
## `pending` carries a save from the main menu into the landscape scene: the
## pause menu hands it to the game clock once the world is built.

const QUICK := "user://quicksave.apgame"
const DIR := "user://saves"
const EXT := ".apgame"

static var pending := ""

## {path, name, day (-1 unknown), saved (unix seconds, 0 unknown), quick},
## the newest first.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if FileAccess.file_exists(QUICK):
		out.append(_entry(QUICK, "Schnellspeicher (F8)", true))
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(EXT):
				out.append(_entry(DIR.path_join(file), file.trim_suffix(EXT), false))
	out.sort_custom(func(a, b): return a.saved > b.saved)
	return out

static func _entry(path: String, fallback: String, quick: bool) -> Dictionary:
	var meta := ConfigFile.new()
	var known := meta.load(_meta_path(path)) == OK
	return {
		"path": path,
		"name": fallback if quick or not known else String(meta.get_value("save", "name", fallback)),
		"day": int(meta.get_value("save", "day", -1)) if known else -1,
		"saved": int(meta.get_value("save", "saved", 0)) if known else int(FileAccess.get_modified_time(path)),
		"quick": quick,
	}

## Where a new save named `name` goes: its name made safe for a file.
static func path_for(name: String) -> String:
	var safe := ""
	for c in name.strip_edges():
		safe += c if c.is_valid_identifier() or c.is_valid_int() or c in " -" else "_"
	if safe.strip_edges() == "":
		safe = "Spielstand"
	DirAccess.make_dir_recursive_absolute(DIR)
	return DIR.path_join(safe.strip_edges() + EXT)

## Notes the save's name and day beside it, once the sim has written it.
static func remember(path: String, name: String, day: int) -> void:
	var meta := ConfigFile.new()
	meta.set_value("save", "name", name)
	meta.set_value("save", "day", day)
	meta.set_value("save", "saved", int(Time.get_unix_time_from_system()))
	meta.save(_meta_path(path))

static func remove(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_meta_path(path))

static func _meta_path(path: String) -> String:
	return path.get_basename() + ".cfg"

## "heute 21:14", "gestern 19:40" or "27.10.2026 08:05".
static func when(unix: int) -> String:
	if unix <= 0:
		return "–"
	var offset := int(Time.get_time_zone_from_system().bias) * 60
	var at := Time.get_datetime_dict_from_unix_time(unix + offset)
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + offset)
	var clock := "%02d:%02d" % [at.hour, at.minute]
	var days := (Time.get_unix_time_from_datetime_dict(_day_of(now)) - Time.get_unix_time_from_datetime_dict(_day_of(at))) / 86400
	if days == 0:
		return "heute " + clock
	if days == 1:
		return "gestern " + clock
	return "%d.%d.%d %s" % [at.day, at.month, at.year, clock]

static func _day_of(d: Dictionary) -> Dictionary:
	return {"year": d.year, "month": d.month, "day": d.day, "hour": 0, "minute": 0, "second": 0}
