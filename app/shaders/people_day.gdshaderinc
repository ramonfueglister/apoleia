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
// them; a traveller sleeps by the way. Nothing here goes back to the sim.
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

struct DayNow {
	vec2 offset;  // km from the person's spot by the house
	bool moved;   // away from that spot: on the ground there, not at the spot's height
	bool walking;
	vec2 way;     // direction of the walk (world x, z)
	bool inside;  // in the house, out of sight
	int pose;     // DAY_STAND, DAY_WORK, DAY_LIE
};

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
	// Baustein «Feld»: out after sunrise (at first light while the harvest
	// or the sowing presses), at work until before sunset, the way out and
	// back as long as it really takes
	if (farmer) {
		vec2 r2 = dot_rand2(slot, 62u);
		float walk = length(field) / DAY_WALK_KMH;
		float go = max(busy ? sun.x - 0.25 + 0.5 * r2.x : sun.x + 0.25 + 0.75 * r2.x, wake + 0.1);
		float back = max(busy ? sun.y - 0.25 - 0.5 * r2.y : sun.y - 0.5 - 0.75 * r2.y, go + walk);
		if (h >= go && h < back + walk) {
			bool going = h < back;
			float u = going ? clamp((h - go) / walk, 0.0, 1.0) : 1.0 - clamp((h - back) / walk, 0.0, 1.0);
			d.offset = field * u;
			d.moved = true;
			d.walking = u < 1.0;
			d.way = normalize(going ? field : -field);
			d.pose = d.walking ? DAY_STAND : DAY_WORK;
		}
	}
	return d;
}

// The same at the clock's hour.
DayNow day_now(uint slot, uint key, uint kind, uint job, bool female, bool child, vec2 look, int flags) {
	return day_at(day_hour, slot, key, kind, job, female, child, look, flags);
}
