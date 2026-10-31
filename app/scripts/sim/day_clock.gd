extends RefCounted
## The hour of the day at the slow speeds (Ramon, 30.10.2026: daily
## routines visible, "wie RimWorld": a way takes as long as it really
## does, and the clock and the calendar agree). The sim still counts whole
## days; the hour is only the share of the real time between two sim days
## the clock has run (people_dots.gd clock_day), laid out over the day of
## that date and latitude: the sun rises and sets by the solar declination
## (Spencer's day of year, the sunrise equation), the daylight gets most of
## the real time and the night, where nothing is to be seen, NIGHT_SHARE.
## How the hours are named belongs to the epoch (RECKONINGS): the Romans
## counted twelve horae from sunrise to sunset, long in summer and short in
## winter, and four vigiliae through the night (Hannah, 2009).
##
## Read by game_clock.gd (the bar, the light), people_dots.gd and through it
## people_trips.gd (the travellers' pace and hours) and the houses' lamps.

const SimTables = preload("res://scripts/sim/sim_tables.gd")
const NIGHT_SHARE := 0.07 # of a day's real time (17 of 240 s at four minutes a day)
const WALK_KMH := 4.5 # on foot, with or without a donkey
const CART_KMH := 3.0 # an ox cart
const TWILIGHT_H := 0.75 # the light turns from day to night over this long either side of sunset and sunrise
const EARTH_KM := 6371.0088 # as landscape.gd
## How an epoch names the hours (Ramon, 30.10.2026: "nicht nur für
## römische Stunden, sondern bis in die Neuzeit"). The hours above are the
## same in every epoch, only their names change, so a later epoch adds a
## reckoning here and nothing else. "temporal": the daylight in as many
## equal parts as `day` names and the night in as many as `night` names,
## long in summer and short in winter; "equal": the 24 equal hours of a
## clock from midnight. Later, for instance, the canonical hours of the
## monasteries (prima, tertia, sexta, nona, vespera, completorium), the
## equal hours of the tower clocks from the 14th century, a factory's
## shifts.
const RECKONINGS := {
	"roman": {"kind": "temporal",
		"day": ["hora I", "hora II", "hora III", "hora IV", "hora V", "hora VI",
			"hora VII", "hora VIII", "hora IX", "hora X", "hora XI", "hora XII"],
		"night": ["vigilia I", "vigilia II", "vigilia III", "vigilia IV"]},
	"modern": {"kind": "equal"},
}
const RECKONING := "roman" # the epoch the game is set in (--reckoning=modern shows the other)

## Sunrise and sunset (hours of local solar time) on sim day `day` at
## latitude `lat` (degrees north). The sim year has 360 days from
## 1 Ianuarius (sim_tables.gd), taken as the 365 of the sun.
static func daylight(day: int, lat: float) -> Vector2:
	var n := float(posmod(day, SimTables.YEAR)) * 365.0 / float(SimTables.YEAR)
	var decl := deg_to_rad(-23.44) * cos(TAU * (n + 10.0) / 365.0)
	var c := clampf(-tan(deg_to_rad(clampf(lat, -66.0, 66.0))) * tan(decl), -1.0, 1.0)
	var half := rad_to_deg(acos(c)) / 15.0
	return Vector2(12.0 - half, 12.0 + half)

## The latitude of a point on the map (world km), as landscape.gd
## lonlat_to_world puts it.
static func latitude(world: Vector2) -> float:
	return 41.0 - rad_to_deg(world.y / EARTH_KM)

## The hour (0-24) at share `f` (0-1) of the day's real time, with the sun
## up from sun.x to sun.y.
static func hour(f: float, sun: Vector2) -> float:
	var night := 24.0 - (sun.y - sun.x)
	var dawn := NIGHT_SHARE * sun.x / night # real share of the night before sunrise
	var dusk := dawn + 1.0 - NIGHT_SHARE
	if f < dawn:
		return f / dawn * sun.x
	if f < dusk:
		return sun.x + (f - dawn) / (1.0 - NIGHT_SHARE) * (sun.y - sun.x)
	return sun.y + (f - dusk) / maxf(1.0 - dusk, 1e-6) * (24.0 - sun.y)

## The inverse: the share of the day's real time at hour `h`.
static func share(h: float, sun: Vector2) -> float:
	var night := 24.0 - (sun.y - sun.x)
	var dawn := NIGHT_SHARE * sun.x / night
	var dusk := dawn + 1.0 - NIGHT_SHARE
	if h < sun.x:
		return h / sun.x * dawn
	if h < sun.y:
		return dawn + (h - sun.x) / (sun.y - sun.x) * (1.0 - NIGHT_SHARE)
	return dusk + (h - sun.y) / maxf(24.0 - sun.y, 1e-6) * (1.0 - dusk)

## Real seconds an hour of daylight lasts when a day lasts `day_s`.
static func hour_seconds(day_s: float, sun: Vector2) -> float:
	return day_s * (1.0 - NIGHT_SHARE) / (sun.y - sun.x)

## The light: x the share of the daylight gone (0 sunrise, 0.5 noon,
## 1 sunset, weather_system.gd time_of_day), y how dark it is (0 day,
## 1 night), turning over TWILIGHT_H either side of sunrise and sunset.
static func light(h: float, sun: Vector2) -> Vector2:
	var day := clampf((h - sun.x) / (sun.y - sun.x), 0.0, 1.0)
	var from_edge := minf(h - sun.x, sun.y - h) # hours inside the day, negative at night
	return Vector2(day, 1.0 - smoothstep(-TWILIGHT_H, TWILIGHT_H, from_edge))

## The name of hour `h` in `reckoning` (RECKONINGS), "" for a reckoning
## that shows only the clock.
static func hour_name(h: float, sun: Vector2, reckoning := RECKONING) -> String:
	var r: Dictionary = RECKONINGS.get(reckoning, RECKONINGS[RECKONING])
	if r.kind != "temporal":
		return ""
	var day: Array = r.day
	var night: Array = r.night
	if h >= sun.x and h < sun.y:
		return day[clampi(int((h - sun.x) / (sun.y - sun.x) * day.size()), 0, day.size() - 1)]
	var into := fposmod(h - sun.y, 24.0) / (24.0 - (sun.y - sun.x))
	return night[clampi(int(into * night.size()), 0, night.size() - 1)]

## The hour for the bar: its name in the reckoning and our clock beside it
## as a help ("hora III · 7:42"), or only the clock where the epoch counts
## equal hours.
static func label(h: float, sun: Vector2, reckoning := RECKONING) -> String:
	var name := hour_name(h, sun, reckoning)
	return clock_text(h) if name == "" else "%s · %s" % [name, clock_text(h)]

## The hour as our clock shows it, 7:42.
static func clock_text(h: float) -> String:
	var m := int(h * 60.0) % (24 * 60)
	return "%d:%02d" % [m / 60, m % 60]
