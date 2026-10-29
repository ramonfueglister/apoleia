// The people up close: a small figure of blocks (people_dots.gd _figure_mesh,
// 1 unit = 1.7 m, drawn at diorama scale like the houses and trees) at the
// spot the placement pass gave each person. Only the people near the camera
// are drawn: ApoleiaPeople.near lists their slots into `list_tex`, one
// instance per entry. Clothes and props by occupation and estate (S77):
// tools for farmers, spear and shield for soldiers, a toga with purple
// stripes for senators and knights, a cloak for the rich, an apron for
// craftsmen, a bundle for traders and labourers, bare feet for the unfree.
// In the colour modes the tunic takes the group colour as the dots do.
// People on the road walk, children at home run about their house.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"

uniform sampler2D place_tex : filter_nearest, repeat_disable; // people_dots_prep output
uniform sampler2D list_tex : filter_nearest, repeat_disable;  // slots to draw (float)
uniform int list_w = 128;
uniform float figure_scale = 0.04; // world units of the unit figure (1.7 m at diorama scale)
uniform int colour_mode = 0;
uniform vec3 palette[16];
uniform int selected_slot = -1;
uniform vec3 selected_colour : source_color = vec3(1.0, 0.9, 0.1);

varying vec3 colour;
varying vec3 local;     // unit-figure position, for the toga stripes
varying float stripes;  // stripe half width, 0 = none
varying vec3 art_light; // ART_LIGHT in view space
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)

// undyed wool and linen (a quarter), madder red, woad blue, browns, a
// leaf green and a grey blue: clothes when the people are not coloured by
// group (sRGB); clear enough to stand out on the grass and the fields, none
// close to the skin, so no one reads as naked
const vec3 TUNICS[8] = vec3[](vec3(0.81, 0.76, 0.65), vec3(0.86, 0.83, 0.74), vec3(0.61, 0.25, 0.16),
	vec3(0.25, 0.37, 0.56), vec3(0.43, 0.29, 0.18), vec3(0.36, 0.43, 0.23), vec3(0.33, 0.24, 0.17), vec3(0.4, 0.45, 0.52));
const vec3 SCARVES[4] = vec3[](vec3(0.85, 0.8, 0.68), vec3(0.62, 0.25, 0.18), vec3(0.3, 0.38, 0.55), vec3(0.45, 0.33, 0.22));
// part ids in UV.x (people_dots.gd FIG_*)
const int TUNIC = 0;
const int LEG_L = 1;
const int LEG_R = 2;
const int ARM_L = 3;
const int ARM_R = 4;
const int HAIR = 5;
const int SANDAL_L = 7;
const int SANDAL_R = 8;
const int POLE = 9;
const int HOE = 10;
const int SPEAR = 11;
const int SHIELD = 12;
const int SWORD = 13;
const int CLOAK = 14;
const int APRON = 15;
const int BUNDLE = 16;
// occupations (sim groups.rs) and estates (Stand)
const uint ADEL = 0u;
const uint UNTERNEHMER = 1u;
const uint GEISTLICHE = 2u;
const uint OFFIZIERE = 3u;
const uint HAENDLER = 4u;
const uint BEAMTE = 5u;
const uint GELEHRTE = 6u;
const uint HANDWERKER = 7u;
const uint BAUERN = 8u;
const uint PAECHTER = 9u;
const uint TAGELOEHNER = 10u;
const uint SOLDATEN = 11u;
const uint UNFREIE = 12u;
const uint RITTER = 2u;
const uint SENATOREN = 3u;
// bright dyes the well-off can afford: madder, woad, saffron, kermes, green
const vec3 DYED[5] = vec3[](vec3(0.72, 0.22, 0.16), vec3(0.24, 0.36, 0.62), vec3(0.86, 0.64, 0.2),
	vec3(0.6, 0.12, 0.2), vec3(0.3, 0.5, 0.3));
const vec3 WHITE_WOOL = vec3(0.92, 0.9, 0.84);
const vec3 PURPLE = vec3(0.42, 0.1, 0.3);
const vec3 ARMY_RED = vec3(0.66, 0.16, 0.12);

// rotates p about the horizontal x axis through height `pivot`
vec3 swing(vec3 p, float pivot, float angle) {
	float c = cos(angle), s = sin(angle);
	vec2 q = vec2(p.y - pivot, p.z);
	return vec3(p.x, pivot + c * q.x - s * q.y, s * q.x + c * q.y);
}

bool rich_family(uint job, uint estate) {
	return job == ADEL || job == UNTERNEHMER || job == OFFIZIERE || estate >= RITTER;
}

void vertex() {
	int id = INSTANCE_ID;
	int slot = int(texelFetch(list_tex, ivec2(id % list_w, id / list_w), 0).r);
	int per = page_side * page_side;
	int in_page = slot % per;
	ivec2 px = ivec2(in_page % page_side, (slot / per) * page_side + in_page / page_side);
	vec4 rec = dot_record(px);
	vec4 place = texelFetch(place_tex, px, 0);
	uint w = uint(rec.w);
	uint kind = w & 3u;
	uint estate = (w >> 2u) & 3u;
	uint job = (w >> 4u) & 15u;
	bool female = ((w >> 22u) & 1u) == 1u;
	bool child = ((w >> 23u) & 1u) == 1u;
	vec2 r = dot_rand2(uint(slot), 31u);
	vec2 r2 = dot_rand2(uint(slot), 37u);
	int part = int(UV.x + 0.5);
	// what this person wears and carries
	bool adult_man = !child && !female;
	bool rich = !child && rich_family(job, estate);
	bool robe = !child && (job == GEISTLICHE || job == GELEHRTE);
	bool hoe = !child && (job == BAUERN || job == PAECHTER);
	bool spear = adult_man && job == SOLDATEN;
	bool pole = hoe || spear || (!child && job == GEISTLICHE);
	bool shield = adult_man && (job == SOLDATEN || job == OFFIZIERE);
	bool sword = adult_man && (job == OFFIZIERE || (job == ADEL && estate >= RITTER));
	bool cloak = rich && job != BEAMTE;
	bool apron = !child && job == HANDWERKER;
	bool bundle = !child && (job == HAENDLER || job == TAGELOEHNER || job == UNFREIE);
	bool barefoot = child || job == UNFREIE;
	bool shown = part < POLE
		|| (part == POLE && pole) || (part == HOE && hoe) || (part == SPEAR && spear)
		|| (part == SHIELD && shield) || (part == SWORD && sword) || (part == CLOAK && cloak)
		|| (part == APRON && apron) || (part == BUNDLE && bundle);
	// children at home run in circles about their house; travellers walk
	bool playing = child && kind == 0u && r2.x < 0.7;
	bool walking = kind >= 2u || playing;
	vec3 v = shown ? VERTEX : vec3(0.0);
	local = v;
	// a long dress on women and a robe on clergy and scholars down to the ankles
	if ((female || robe) && part == TUNIC && v.y < 0.5) {
		v.y = 0.07;
		v.xz *= 1.25;
	}
	// walking: legs and arms swing; standing: arms hang with a slight sway.
	// The hand that holds a tool swings less, and the tool with it.
	float phase = TIME * (walking ? (playing ? 9.0 : 7.0) : 1.3) + r.y * 6.2831853;
	float leg = walking ? 0.45 * sin(phase) : 0.0;
	float arm = walking ? 0.5 * sin(phase) : 0.06 * sin(phase);
	float held = pole ? 0.25 : 1.0;
	if (part == LEG_L || part == SANDAL_L) v = swing(v, 0.47, leg);
	if (part == LEG_R || part == SANDAL_R) v = swing(v, 0.47, -leg);
	if (part == ARM_L || part == SHIELD) v = swing(v, 0.79, -arm * (shield ? 0.25 : 1.0));
	if (part == ARM_R || part == POLE || part == HOE || part == SPEAR) v = swing(v, 0.79, arm * held);
	// people standing about turn now and then; walkers face their way
	float a = r.x * 6.2831853 + (walking ? 0.0 : floor(TIME * 0.05 + r2.x * 8.0) * 2.1);
	float s = figure_scale * (child ? 0.62 : (female ? 0.94 : 1.0) * (0.94 + 0.1 * r2.y)) * (slot == selected_slot ? 1.4 : 1.0);
	vec2 p = rec.xy + place.xy - 32.0;
	if (playing) {
		// round and round, either way; facing along the circle
		float way = r.y < 0.5 ? 1.0 : -1.0;
		float turn = r.x * 6.2831853 + TIME * (0.6 + 0.4 * r2.y) * way;
		float run = figure_scale * (1.2 + 1.5 * r2.y);
		p += run * vec2(cos(turn), sin(turn));
		a = turn + (way > 0.0 ? 0.0 : 3.14159265);
	}
	mat2 rot = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	v *= s;
	v.xz = rot * v.xz;
	float lift = walking ? abs(sin(phase)) * 0.025 * s : 0.0;
	vec3 world = vec3(p.x, place.z * level_h + lift, p.y) + v;
	vec3 nrm = NORMAL;
	nrm.xz = rot * nrm.xz;
	bool show = rec.z != 0.0 && place.a > 0.5;
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	// clothes: undyed wool and linen for the common people, bright dyes for
	// the well-off, white wool with the purple stripes (clavi) for the
	// senators (broad) and the knights and officials (narrow), army red
	vec3 tunic = TUNICS[int(r.y * 7.999)];
	stripes = 0.0;
	if (child) {
		tunic = rich_family(job, estate) ? DYED[int(r2.y * 4.999)] : (job == UNFREIE ? vec3(0.46, 0.41, 0.34) : tunic);
	} else if (job == UNFREIE) {
		tunic = vec3(0.46, 0.41, 0.34);
	} else if (job == SOLDATEN || job == OFFIZIERE) {
		tunic = ARMY_RED;
	} else if (job == GEISTLICHE) {
		tunic = WHITE_WOOL;
	} else if (job == GELEHRTE) {
		tunic = vec3(0.38, 0.4, 0.46);
	} else if (adult_man && (estate >= RITTER || job == ADEL || job == BEAMTE)) {
		tunic = WHITE_WOOL;
		stripes = (estate == SENATOREN || job == ADEL) ? 0.022 : 0.01;
	} else if (rich || job == HAENDLER) {
		tunic = DYED[int(r2.y * 4.999)];
	}
	if (slot == selected_slot) {
		tunic = selected_colour;
		stripes = 0.0;
	} else if (colour_mode == 0) {
		tunic = pow(tunic, vec3(2.2));
	} else {
		tunic = palette[colour_mode == 3 ? int(estate) : int(job)];
		stripes = 0.0;
	}
	vec3 own = pow(COLOR.rgb, vec3(2.2));
	if (part == HAIR && female) {
		own = pow(SCARVES[int(r2.x * 3.999)], vec3(2.2));
	}
	if ((part == SANDAL_L || part == SANDAL_R) && barefoot) {
		own = pow(vec3(0.84, 0.64, 0.48), vec3(2.2));
	}
	if (part == CLOAK) {
		own = pow(estate == SENATOREN || job == ADEL ? PURPLE : (job == OFFIZIERE ? ARMY_RED : DYED[int(r.x * 4.999)] * 0.7), vec3(2.2));
	}
	if (part != TUNIC) {
		stripes = 0.0;
	}
	colour = (part == TUNIC ? tunic : own) * COLOR.a; // alpha: corner shading
	art_light = normalize((VIEW_MATRIX * vec4(ART_LIGHT, 0.0)).xyz);
}

void fragment() {
	// the clavi run down from the shoulders, front and back
	bool stripe = stripes > 0.0 && abs(abs(local.x) - 0.085) < stripes && local.y > 0.45;
	ALBEDO = stripe ? pow(PURPLE, vec3(2.2)) : colour;
	ROUGHNESS = 1.0;
}

// The sun's light from the terrain's fixed SimCity direction (south-west,
// ART_LIGHT) instead of its own, so the walls turned
// to the camera are the lit ones, as in Urbek and SimCity 2000; colour,
// strength and the shadows of other things stay the sun's. Faces turned
// away from the real sun are not darkened by its shadow map.

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float shadow = dot(NORMAL, LIGHT) > 0.05 ? ATTENUATION : 1.0;
		DIFFUSE_LIGHT += max(dot(NORMAL, art_light), 0.0) * shadow * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
