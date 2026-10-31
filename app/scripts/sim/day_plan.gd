extends RefCounted
## The day of one person as its figure lives it at the slow speeds
## (app/shaders/people_day.gdshaderinc), for the person's window
## («Heute», person_window.gd; Ramon, 31.10.2026, step 5 of the daily
## routines). The same blocks and the same hashes as the shader
## (people_dots_common.gdshaderinc dot_hash, dot_rand2), so the list says
## what the figure does: keep the two in step. The day is sampled every
## minute and cut where what the person does changes. Where it walks today
## as a carrier, trader or hired hand comes from people_trips.gd (`away`).

const WALK_KMH := 4.5 # people_day.gdshaderinc DAY_WALK_KMH
const UNFREE := 12 # the job of the unfree (sim groups.rs)
const LOOK_COOKS := 1 # the household flags (people_dots_common.gdshaderinc DOT_LOOK_*)
const LOOK_HARVEST := 4
const LOOK_SOWING := 8
const LOOK_FARM := 16
const LOOK_CRAFT_SHIFT := 5 # the workshop: 1 weaver, 2 smith, 3 potter
const STEPS := 24 * 60
## What a person does, as day_at tells it
const SLEEP := "sleep"
const HOME := "home"
const TO_FIELD := "to_field"
const FIELD := "field"
const TO_HOME := "to_home"
const MEAL_IN := "meal_in"
const MEAL_FIELD := "meal_field"
const REST := "rest"
const LIE := "lie"
const ROAD := "road"
const CRAFT := "craft"
const AWAY_OUT := "away_out"
const AWAY_AT := "away_at"
const AWAY_HOME := "away_home"

## a * b modulo 2^32, without leaving 64 bits
static func _mul(a: int, b: int) -> int:
	return (a * (b & 0xffff) + (((a * (b >> 16)) & 0xffff) << 16)) & 0xffffffff

static func _hash(x: int) -> int:
	x &= 0xffffffff
	x ^= x >> 16
	x = _mul(x, 0x7feb352d)
	x ^= x >> 15
	x = _mul(x, 0x846ca68b)
	x ^= x >> 16
	return x

static func _rand2(key: int, k: int) -> Vector2:
	var a := _hash(_mul(key, 0x9e3779b9) + _mul(k, 0x632be5ab))
	var b := _hash(a ^ 0x5bd1e995)
	return Vector2(float(a & 0xffff), float(b & 0xffff)) / 65535.0

## How far the household's field lies from the person's spot (km,
## dot_field_offset).
static func field_km(key: int, slot: int) -> float:
	return 0.15 + 0.07 * _rand2(slot, 43).y

## The household's midday meal, start and end (day_meal).
static func meal(key: int, sun: Vector2) -> Vector2:
	var k := _rand2(key, 70)
	var s := 0.5 * (sun.x + sun.y) - 0.5 + 1.5 * k.x
	return Vector2(s, s + 0.75 + 0.5 * k.y)

static func _leg(h: float, s: float, e: float, walk: float) -> float:
	if h < s or h >= e + walk:
		return -1.0
	return clampf((h - s) / walk, 0.0, 1.0) if h < e else 1.0 - clampf((h - e) / walk, 0.0, 1.0)

## What person `slot` of household `key` does at hour `h` (day_at): kind,
## job, female, child from its record, flags the household's (0 not known),
## away where it walks today (people_trips.gd `away`, {} if nowhere).
static func at(h: float, slot: int, key: int, kind: int, job: int, female: bool, child: bool, flags: int, sun: Vector2, away := {}) -> String:
	var busy := (flags & (LOOK_HARVEST | LOOK_SOWING)) != 0
	var farmer := kind == 0 and not child and (busy or ((flags & LOOK_FARM) != 0 and (not female or job == UNFREE)))
	var craft := (flags >> LOOK_CRAFT_SHIFT) & 3 if kind == 0 and not child else 0
	var r := _rand2(slot, 61)
	if kind >= 2:
		return LIE if h < sun.x - 0.5 + 0.5 * r.x or h >= sun.y + 1.0 + r.y else ROAD
	if not away.is_empty() and h >= _away_hour(away.leave) and h < _away_hour(away.back):
		return AWAY_OUT if h < float(away.arrive) else (AWAY_AT if h < float(away.stay) else AWAY_HOME)
	var wake := sun.x + 0.25 + 0.75 * r.x if child else sun.x - 0.5 + 0.75 * r.x
	var bed := sun.y - 0.25 + 0.5 * r.y if child else sun.y + 0.25 + 0.75 * r.y
	if h < wake or h >= bed:
		return SLEEP
	var known := flags != 0
	var cooks := (flags & LOOK_COOKS) != 0
	var m := meal(key, sun)
	var at_meal := known and h >= m.x and h < m.y
	if farmer:
		var r2 := _rand2(slot, 62)
		var walk := field_km(key, slot) / WALK_KMH
		var go := maxf(sun.x - 0.25 + 0.5 * r2.x if busy else sun.x + 0.25 + 0.75 * r2.x, wake + 0.1)
		if not away.is_empty() and _away_hour(away.back) > _away_hour(away.leave):
			go = maxf(go, _away_hour(away.back) + 0.1) # out to the field once back from the market
		var back := maxf(sun.y - 0.25 - 0.5 * r2.y if busy else sun.y - 0.5 - 0.75 * r2.y, go + walk)
		var noon_go := m.x - walk - 0.15 * r2.x
		var noon_back := m.y + 0.15 * r2.y
		var home_meal := known and cooks and not busy and noon_go > go + walk and noon_back < back
		var e := noon_go if home_meal else back
		var u := _leg(h, go, e, walk)
		var going := h < e
		if u < 0.0 and home_meal:
			if h >= noon_go + walk and h < noon_back:
				return MEAL_IN
			u = _leg(h, noon_back, back, walk)
			going = h < back
		if u >= 0.0:
			if u < 1.0:
				return TO_FIELD if going else TO_HOME
			return (MEAL_FIELD if cooks else REST) if at_meal else FIELD
	if craft > 0 and not at_meal:
		var r3 := _rand2(slot, 63)
		if h >= maxf(sun.x + 0.25 + 0.5 * r3.x, wake + 0.5) and h < sun.y - 0.5 - 0.75 * r3.y:
			return CRAFT
	if at_meal:
		return MEAL_IN if cooks else REST
	return HOME

## An hour of `away` as the figures read it (people_dots_common
## dot_person_away: in 2048ths, people_dots.gd _sync_away).
static func _away_hour(h: float) -> float:
	return float(clampi(int(round(h * 2048.0)), 0, 65535)) / 2048.0

## The person's day as blocks [{from, to, what, text}], hours 0-24, cut
## where what it does changes; the night's two ends are the first and the
## last block.
static func day(slot: int, key: int, kind: int, job: int, female: bool, child: bool, flags: int, sun: Vector2, away := {}) -> Array:
	var out: Array = []
	var last := ""
	for i in STEPS:
		var h := (float(i) + 0.5) * 24.0 / float(STEPS)
		var what := at(h, slot, key, kind, job, female, child, flags, sun, away)
		if what != last:
			if not out.is_empty():
				out[-1].to = float(i) * 24.0 / float(STEPS)
			out.append({"from": float(i) * 24.0 / float(STEPS), "to": 24.0, "what": what})
			last = what
	var playing := child and kind == 0 and _rand2(slot, 37).x < 0.7 # as people_figures.gdshader
	for i in out.size():
		out[i].text = _text(out[i].what, i == 0, flags, playing, away)
	return out

## The block for German eyes.
static func _text(what: String, first: bool, flags: int, playing: bool, away: Dictionary) -> String:
	match what:
		CRAFT:
			return ["", "webt am Webstuhl hinter dem Haus", "schmiedet am Amboss", "töpfert beim Brennofen"][(flags >> LOOK_CRAFT_SHIFT) & 3]
		AWAY_OUT, AWAY_AT, AWAY_HOME:
			var texts: Array = away.get("texts", ["unterwegs", "unterwegs", "unterwegs"])
			return texts[[AWAY_OUT, AWAY_AT, AWAY_HOME].find(what)]
		SLEEP:
			return "schläft, frühstückt im Haus" if first else "isst zu Abend, schläft im Haus"
		HOME:
			return "spielt am Haus" if playing else "am Haus"
		TO_FIELD:
			return "geht aufs Feld"
		FIELD:
			if flags & LOOK_HARVEST:
				return "erntet auf dem Feld"
			if flags & LOOK_SOWING:
				return "sät auf dem Feld"
			return "arbeitet auf dem Feld"
		TO_HOME:
			return "geht heim"
		MEAL_IN:
			return "isst zu Mittag im Haus"
		MEAL_FIELD:
			return "isst auf dem Feld, das Essen wird gebracht"
		REST:
			return "sitzt und ruht, nichts zu essen"
		LIE:
			return "schläft am Weg"
		ROAD:
			return "unterwegs"
	return what

## The block of `blocks` at hour `h`, -1 if none.
static func now(blocks: Array, h: float) -> int:
	for i in blocks.size():
		if h >= float(blocks[i].from) and h < float(blocks[i].to):
			return i
	return -1
