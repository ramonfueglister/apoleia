// The city plans (docs/kit2/CITY_PLANS.md, scripts/city_plans.gd): what
// stands on each 0.25 km parcel of the 860 cities, the parcels being the
// quarter tiles (tile_terrain.gd SUB_KM, aligned to world_min). Included by
// tile_terrain.gdshaderinc after tt_paving and tt_grass.
//
// Up close (the quarter tiles and the 0.5 km tiles) a parcel with a plan
// follows it: houses, public buildings, walls and gates as lot models on
// their terraces, turned as tile_terrain.gd _plan_lot says; streets as
// pieces joined to their neighbours like Urbek's road tiles, in their
// surface (basalt, limestone slabs, gravel, earth) and as wide as their
// rank, lined by houses where the town goes on beside them
// (tile_terrain.gd _plan_street); squares paved in travertine. Outside the plans the old town rule
// stands; the plan's open land suppresses it (the cells carry town 0 there).

uniform sampler2D city_page_tex : filter_nearest, repeat_disable;  // per page of parcels: atlas slot + 1 (R low, G high)
uniform sampler2D city_atlas_tex : filter_nearest, repeat_disable; // R kind, G street, B storeys or model and front
uniform int city_page_parcels = 64;
uniform int city_atlas_slots = 32;
uniform bool city_plans_on = false;

const float CP_PARCEL_KM = 0.25;
const int CP_NONE = 0;
const int CP_HOUSE = 1;
const int CP_INSULA = 2;
const int CP_DOMUS = 3;
const int CP_BUILDING = 4;
const int CP_PLAZA = 5;
const int CP_GARDEN = 6;
const int CP_STREET = 7;
const int CP_WALL = 8;
const int CP_GATE = 9;
const int CP_BRIDGE = 10;
const int CP_TOMBS = 11;
const int CP_LAND = 12;
const int CP_WATER = 13;
// tile_props place code of a plan parcel: CP_CODE + kind (the old rule's
// codes are the town class, plus 8 on a street)
const float CP_CODE = 32.0;

// R, G, B of a parcel (0 where no plan is).
ivec3 cp_texel(ivec2 parcel) {
	if (!city_plans_on || parcel.x < 0 || parcel.y < 0) { return ivec3(0); }
	ivec2 page = parcel / city_page_parcels;
	ivec2 n = textureSize(city_page_tex, 0);
	if (page.x >= n.x || page.y >= n.y) { return ivec3(0); }
	vec2 s = texelFetch(city_page_tex, page, 0).rg * 255.0;
	int slot = int(s.r + 0.5) + 256 * int(s.g + 0.5) - 1;
	if (slot < 0) { return ivec3(0); }
	ivec2 at = ivec2(slot % city_atlas_slots, slot / city_atlas_slots) * city_page_parcels + parcel % city_page_parcels;
	return ivec3(texelFetch(city_atlas_tex, at, 0).rgb * 255.0 + 0.5);
}

int cp_kind(ivec2 parcel) {
	return cp_texel(parcel).r;
}

ivec2 cp_parcel(vec2 p) {
	return ivec2(floor((p - world_min) / CP_PARCEL_KM));
}

// Built up: stands on a terrace (tile_props.gdshader prop kind 5).
bool cp_on_terrace(int k) {
	return k >= CP_HOUSE && k <= CP_BRIDGE;
}

// Holds lot models (tile_terrain.gd _plan_lots_of): a street its houses
// (_plan_street, none along a road through the fields); bridges only their
// terrace.
bool cp_has_lot(int k) {
	return (k >= CP_HOUSE && k <= CP_STREET) || k == CP_WALL || k == CP_GATE || k == CP_TOMBS;
}

// The town class a plan parcel gives its cell: built up 3, a road or the
// tombs outside 1 (no trees, no fields), open land and water 0.
int cp_town(int k) {
	return (k >= CP_HOUSE && k <= CP_GARDEN) || k == CP_WALL || k == CP_GATE ? 3
		: k == CP_STREET || k == CP_BRIDGE || k == CP_TOMBS ? 1 : 0;
}

// Street surfaces (G bits 0-1), sRGB: the carriageway and what lies beside
// it. Basalt polygons between raised travertine footways (silice strata,
// Latium, Campania and Rome); limestone slabs with kerbed footways; gravel
// (glarea strata) and beaten earth with verges of worn grass.
const vec3 CP_BASALT = vec3(0.40, 0.40, 0.41);
const vec3 CP_FOOTWAY = vec3(0.66, 0.63, 0.56);
const vec3 CP_LIMESTONE = vec3(0.70, 0.68, 0.62);
const vec3 CP_LIME_WALK = vec3(0.62, 0.59, 0.52);
const vec3 CP_GRAVEL = vec3(0.62, 0.57, 0.47); // road.gdshaderinc GRAVEL
const vec3 CP_EARTH = vec3(0.50, 0.39, 0.28);
const vec3 CP_TRAVERTINE = vec3(0.64, 0.62, 0.58); // tile_terrain.gdshader C_PLAZA
const vec3 CP_YARD = vec3(0.53, 0.505, 0.455);     // tile_terrain.gdshader C_PAVED
const vec3 CP_MEADOW = vec3(0.325, 0.525, 0.298);  // tile_terrain.gdshader GROUND_RGB meadow
// Half the carriageway's width by rank (none, via, vicus, lane), parcel units
// (a parcel is a 10 m lot): a via about 2.5 m in a band of 3.7 m between the
// houses of the street (voxel/roman_city.gd ROW_IN), the rest footway.
const float CP_HALF[4] = float[](0.1, 0.12, 0.09, 0.06);

// Basalt polygons up close: irregular stones of about 0.8 diorama metres
// (cells of a jittered grid, the nearest centre wins), dark joints between.
float cp_polygons(vec2 p) {
	vec2 q = mod(p / (0.0238 * 0.8), 4096.0);
	vec2 w = max(fwidth(q), vec2(1e-5));
	float fade = 1.0 - smoothstep(0.08, 0.2, max(w.x, w.y));
	if (fade <= 0.0) { return 1.0; }
	vec2 cell = floor(q);
	float d1 = 9.0;
	float d2 = 9.0;
	float tone = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec2 o = c + 0.2 + 0.6 * vec2(tt_hash(c + 0.31), tt_hash(c - 7.7));
			float d = length(q - o);
			if (d < d1) { d2 = d1; d1 = d; tone = tt_hash(c + 3.3); }
			else if (d < d2) { d2 = d; }
		}
	}
	float joint = 1.0 - smoothstep(0.0, 0.08 + 1.5 * w.x, d2 - d1);
	return 1.0 + fade * (0.1 * (tone - 0.5) - 0.3 * joint);
}

// Distance (parcel units) from q to the street's middle lines: from the
// parcel's middle out to each joined side (links bit 0 N, 1 E, 2 S, 3 W),
// so a corner is rounded outside and sharp inside, as Urbek's road tiles.
float cp_street_distance(vec2 q, int links) {
	if (links == 0) { return length(q); }
	float d = 9.0;
	if ((links & 1) != 0) { d = min(d, length(vec2(q.x, max(q.y, 0.0)))); }
	if ((links & 2) != 0) { d = min(d, length(vec2(min(q.x, 0.0), q.y))); }
	if ((links & 4) != 0) { d = min(d, length(vec2(q.x, min(q.y, 0.0)))); }
	if ((links & 8) != 0) { d = min(d, length(vec2(max(q.x, 0.0), q.y))); }
	return d;
}

// The street piece of G byte g at q (-0.5..0.5 in the parcel, x east, y
// south), world p (km), beside a land of colour `meadow`. sRGB.
vec3 cp_street(int g, vec2 q, vec2 p, vec3 meadow) {
	int surface = g & 3;
	int rank = (g >> 2) & 3;
	int links = g >> 4;
	float half_w = CP_HALF[rank];
	float d = cp_street_distance(q, links);
	float aa = fwidth(d) * 1.5 + 1e-5;
	float on = 1.0 - smoothstep(half_w - aa, half_w + aa, d); // 1 on the carriageway
	vec3 road;
	vec3 side;
	if (surface == 3) {
		road = CP_BASALT * cp_polygons(p);
		side = CP_FOOTWAY * tt_paving(p, vec2(1.0, 1.0));
	} else if (surface == 2) {
		road = CP_LIMESTONE * tt_paving(p, vec2(1.0, 0.6));
		side = CP_LIME_WALK * tt_paving(p, vec2(0.8, 0.8));
	} else {
		// gravel or earth: two ruts, a speckle of stones, a verge of worn grass
		vec3 base = surface == 1 ? CP_GRAVEL : CP_EARTH;
		vec2 g4 = mod(p / (0.0238 * 0.25), 4096.0);
		float n = tt_hash(floor(g4));
		float fade = 1.0 - smoothstep(0.25, 0.5, length(fwidth(g4)));
		road = base * (1.0 + (n - 0.5) * 0.16 * fade);
		float rut = abs(d - half_w * 0.55);
		road *= 1.0 - 0.1 * (1.0 - smoothstep(0.0, 0.04 + aa, rut));
		side = tt_grass(p, mix(meadow, base, 0.3));
	}
	vec3 c = mix(side, road, on);
	// the kerb: a dark line where a paved carriageway meets its footway
	if (surface >= 2) {
		c *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, aa * 1.5, abs(d - half_w)));
	}
	return c;
}

// The ground of plan parcel v at q (parcel units) and p (world km) beside
// a land of colour `meadow`, sRGB. Open land and water keep their own.
vec3 cp_surface(ivec3 v, vec2 q, vec2 p, vec3 meadow) {
	int k = v.r;
	if (k == CP_STREET || k == CP_BRIDGE || k == CP_GATE) { return cp_street(v.g, q, p, meadow); }
	if (k == CP_PLAZA) { return CP_TRAVERTINE * tt_paving(p, vec2(2.0, 1.5)); }
	if (k == CP_TOMBS || k == CP_GARDEN) { return tt_grass(p, meadow); }
	return CP_YARD * tt_paving(p, vec2(1.2, 0.8));
}

// Tile t of the current level follows a plan: up close its own parcel,
// on the 0.5 km tiles any of its four.
bool cp_planned_tile(ivec2 t) {
	if (!city_plans_on || tile_km > 0.75) { return false; }
	if (sub_tiles) { return cp_kind(t) != CP_NONE; }
	return cp_kind(t * 2) != CP_NONE || cp_kind(t * 2 + ivec2(1, 0)) != CP_NONE
		|| cp_kind(t * 2 + ivec2(0, 1)) != CP_NONE || cp_kind(t * 2 + ivec2(1, 1)) != CP_NONE;
}

// q of world point p in its parcel (-0.5..0.5).
vec2 cp_local(vec2 p) {
	return fract((p - world_min) / CP_PARCEL_KM) - 0.5;
}
