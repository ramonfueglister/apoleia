// The day of the people up close at the slow speeds (Ramon, 30.10.2026:
// daily routines visible, step 2 of docs/kit1/REALTIME_GAMEPLAY.md; "wie
// RimWorld": a way takes as long as it really does). The sim counts whole
// days; the hour is the game clock's (scripts/sim/day_clock.gd, handed on
// by people_dots.gd set_day_time), and what a person does at that hour
// follows from what the sim has of it and its household, nothing more: at
// home or in a city it sleeps in its house through the night; the grown-ups
// of a household with a farm (DOT_LOOK_FARM) walk out to its fields after
// sunrise, work there and walk home before sunset, the men and the unfree
// every day and, while the farm's harvest or sowing wants hands, all of
// them; at noon a household with food to cook (DOT_LOOK_COOKS) eats in its
// house, the field hands walk home for it and back, while the harvest or
// the sowing presses the meal is brought out and eaten sitting in the
// field, and where there is nothing to cook they sit and rest instead; the
// hearth burns for the meals (day_fire, the smoke of
// people_house_life.gdshader); a traveller sleeps by the way. Nothing here
// goes back to the sim.
//
// The day is built of blocks (Bausteine), each with who (a test on the
// person), where (its spot by the house, its household's field, in the
// house out of sight), when (from and to, counted from sunrise and sunset,
// so a block holds in every epoch and at every latitude; a later block may
// count from a clock instead) and how it looks (standing, at work, lying).
// A later step adds its blocks here (the meals, the market, the workshop,
// a feast) and the figures follow: people_figures.gdshader and
// people_figure_shadows.gdshader read only day_now. At the fast speeds
// (day_hour < 0) there is no hour, and the figures stand as the sim day has
// them: out on the fields through the harvest and the sowing, else at home.
//
// Needs people_dots_common.gdshaderinc.

uniform float day_hour = -1.0;          // hour of the day (0-24), -1 at the fast speeds
uniform vec2 day_sun = vec2(6.0, 18.0); // sunrise and sunset (hours), DayClock.daylight

const float DAY_WALK_KMH = 4.5; // on foot (day_clock.gd WALK_KMH)
const uint DAY_UNFREE = 12u;     // the job of the unfree (sim groups.rs)
// how a figure looks
const int DAY_STAND = 0;
const int DAY_WORK = 1; // bent over the hoe, the sickle or the seed
const int DAY_LIE = 2;
const int DAY_SIT = 3;  // on the ground, at the meal or resting

struct DayNow {
	vec2 offset;  // km from the person's spot by the house
	bool moved;   // away from that spot: on the ground there, not at the spot's height
	bool walking;
	vec2 way;     // direction of the walk (world x, z)
	bool inside;  // in the house, out of sight
	int pose;     // DAY_STAND, DAY_WORK, DAY_LIE, DAY_SIT
};

// The midday meal (prandium) of household `key`, start and end (hours):
// about the sixth hour, each household at its own time, for three
// quarters of an hour to an hour and a quarter with the rest after it.
vec2 day_meal(uint key) {
	vec2 k = dot_rand2(key, 70u);
	float s = 0.5 * (day_sun.x + day_sun.y) - 0.5 + 1.5 * k.x;
	return vec2(s, s + 0.75 + 0.5 * k.y);
}

// Whether the hearth of household `key` burns at hour `h`: in the morning
// for the breakfast, before the midday meal, and from before sunset for
// the evening meal (the cena, the day's main meal); always at the fast
// speeds (h < 0), as the sim day has it.
bool day_fire(float h, uint key) {
	if (h < 0.0) {
		return true;
	}
	vec2 k = dot_rand2(key, 71u);
	vec2 meal = day_meal(key);
	return (h >= day_sun.x - 1.0 + 0.5 * k.x && h < day_sun.x + 0.5 + 0.5 * k.x)
		|| (h >= meal.x - 0.75 && h < meal.y - 0.25)
		|| (h >= day_sun.y - 1.5 + 0.5 * k.y && h < day_sun.y + 1.0 + k.y);
}

// A way out to the field at hour `s` and home again at `e`: the share of
// the way out at hour `h` (0 at home, 1 on the field), -1 outside it.
float day_leg(float h, float s, float e, float walk) {
	if (h < s || h >= e + walk) {
		return -1.0;
	}
	return h < e ? clamp((h - s) / walk, 0.0, 1.0) : 1.0 - clamp((h - e) / walk, 0.0, 1.0);
}

// Person `slot` of household `key` at hour `h` (< 0: no hour). kind, job,
// female, child: its record (people_dots.gd); look: dot_person_look; flags:
// dot_person_flags.
DayNow day_at(float h, uint slot, uint key, uint kind, uint job, bool female, bool child, vec2 look, int flags) {
	DayNow d;
	d.offset = vec2(0.0);
	d.moved = false;
	d.walking = false;
	d.way = vec2(0.0, 1.0);
	d.inside = false;
	d.pose = DAY_STAND;
	bool busy = look.y > 0.5; // the farm's harvest or sowing wants hands
	bool farmer = kind == 0u && !child && (busy || ((flags & DOT_LOOK_FARM) != 0 && (!female || job == DAY_UNFREE)));
	vec2 field = dot_field_offset(key, slot);
	if (h < 0.0) {
		if (farmer && busy) {
			d.offset = field;
			d.moved = true;
			d.pose = DAY_WORK;
		}
		return d;
	}
	vec2 sun = day_sun;
	vec2 r = dot_rand2(slot, 61u);
	// Baustein «Rast»: a traveller lies down by the way after dark and goes
	// on at first light
	if (kind >= 2u) {
		if (h < sun.x - 0.5 + 0.5 * r.x || h >= sun.y + 1.0 + r.y) {
			d.pose = DAY_LIE;
		}
		return d;
	}
	// Baustein «Schlaf»: at home or in a city, in the house from dusk till
	// dawn; the children in a little before sunset and out after sunrise,
	// the grown-ups in after sunset (the evening by the lamp,
	// people_house_life.gdshader) and out about sunrise
	float wake = child ? sun.x + 0.25 + 0.75 * r.x : sun.x - 0.5 + 0.75 * r.x;
	float bed = child ? sun.y - 0.25 + 0.5 * r.y : sun.y + 0.25 + 0.75 * r.y;
	if (h < wake || h >= bed) {
		d.inside = true;
		return d;
	}
	// Baustein «Essen»: the midday meal of the household, in the house
	// where it has food to cook, else sitting outside without one
	bool known = flags != 0;
	bool cooks = (flags & DOT_LOOK_COOKS) != 0;
	vec2 meal = day_meal(key);
	bool at_meal = known && h >= meal.x && h < meal.y;
	// Baustein «Feld»: out after sunrise (at first light while the harvest
	// or the sowing presses), at work until before sunset, home at noon to
	// eat unless the meal is brought out or there is none, the ways as long
	// as they really take
	if (farmer) {
		vec2 r2 = dot_rand2(slot, 62u);
		float walk = length(field) / DAY_WALK_KMH;
		float go = max(busy ? sun.x - 0.25 + 0.5 * r2.x : sun.x + 0.25 + 0.75 * r2.x, wake + 0.1);
		float back = max(busy ? sun.y - 0.25 - 0.5 * r2.y : sun.y - 0.5 - 0.75 * r2.y, go + walk);
		float noon_go = meal.x - walk - 0.15 * r2.x;
		float noon_back = meal.y + 0.15 * r2.y;
		bool home_meal = known && cooks && !busy && noon_go > go + walk && noon_back < back;
		float e = home_meal ? noon_go : back;
		float u = day_leg(h, go, e, walk);
		bool going = h < e;
		if (u < 0.0 && home_meal) {
			if (h >= noon_go + walk && h < noon_back) {
				d.inside = true;
				return d;
			}
			u = day_leg(h, noon_back, back, walk);
			going = h < back;
		}
		if (u >= 0.0) {
			d.offset = field * u;
			d.moved = true;
			d.walking = u < 1.0;
			d.way = normalize(going ? field : -field);
			d.pose = d.walking ? DAY_STAND : (at_meal ? DAY_SIT : DAY_WORK);
			return d;
		}
	}
	if (at_meal) {
		if (cooks) {
			d.inside = true;
		} else {
			d.pose = DAY_SIT;
		}
	}
	return d;
}

// The same at the clock's hour.
DayNow day_now(uint slot, uint key, uint kind, uint job, bool female, bool child, vec2 look, int flags) {
	return day_at(day_hour, slot, key, kind, job, female, child, look, flags);
}
