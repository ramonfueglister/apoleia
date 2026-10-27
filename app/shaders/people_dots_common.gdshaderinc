// People dots, shared part: the people record texture and the placement
// rule. people_dots_prep.gdshader runs the rule once per person into a float
// texture (only when the people or the terrain view changed); the dot shader
// (people_dots.gdshaderinc) then only reads that texture.

#include "res://shaders/tile_terrain.gdshaderinc"

uniform sampler2DArray people_tex : filter_nearest, repeat_disable;
uniform int page_side = 64;

const float DOT_CELL_HALF_KM = 12.5;    // half a 25 km sim cell
const float DOT_FINE_HALF_KM = 0.78125; // half a 1.5625 km village tile (sim/src/settle.rs)
const float DOT_VILLAGE_KM = 0.6;       // houses of a village within this radius
const float DOT_FAMILY_KM = 0.035;      // members of a household around its house
const float DOT_ROAD = 8192.0;          // sim/src/view.rs ROAD

uint dot_hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

vec2 dot_rand2(uint key, uint k) {
	uint a = dot_hash(key * 0x9e3779b9u + k * 0x632be5abu);
	uint b = dot_hash(a ^ 0x5bd1e995u);
	return vec2(float(a & 0xffffu), float(b & 0xffffu)) / 65535.0;
}

ivec2 dot_tile(vec2 p) {
	return ivec2(floor((p - world_min) / tile_km));
}

// Record of a slot: slot = layer * page_side^2 + y * page_side + x, which is
// pixel (x, layer * page_side + y) of the prep texture.
vec4 dot_record(ivec2 px) {
	return texelFetch(people_tex, ivec3(px.x, px.y % page_side, px.y / page_side), 0);
}

// First spot on land among up to 16 hashed tries in an area around `c`:
// a square of half-width `r` (r > 0) or a disk of radius -r, eight tries in
// the area, then eight in twice the area.
vec2 dot_land(vec2 c, float r, uint key) {
	vec2 p = c;
	for (uint k = 0u; k < 16u; k++) {
		vec2 h = dot_rand2(key, k);
		float wide = k < 8u ? 1.0 : 2.0;
		if (r > 0.0) {
			p = c + (h - 0.5) * 2.0 * r * wide;
		} else {
			// disk, denser in the middle
			float a = h.x * 6.2831853;
			p = c + vec2(cos(a), sin(a)) * sqrt(h.y) * -r * wide;
		}
		if (tt_water(dot_tile(p)) == W_LAND) {
			return p;
		}
	}
	return p;
}

// Village site: of 16 hashed spots in the village tile the best one on land,
// by cropland and open land (cover_tex: forest, dry, crop, wetland), so
// villages sit at fields and not in the woods or marshes. A tile without
// land (the sim picked it without the fine land data) falls back to land in
// the whole cell.
vec2 dot_village(vec2 c, float r, uint key) {
	vec2 best = c;
	float score = -1.0;
	for (uint k = 0u; k < 16u; k++) {
		vec2 p = c + (dot_rand2(key, k) - 0.5) * 2.0 * r;
		if (tt_water(dot_tile(p)) != W_LAND) {
			continue;
		}
		vec4 cov = tt_cover(p);
		float s = cov.b + 0.4 * (1.0 - cov.r) - 0.5 * cov.a + 0.05 * dot_rand2(key, k + 16u).x;
		if (s > score) {
			score = s;
			best = p;
		}
	}
	return score < 0.0 ? dot_land(c, DOT_CELL_HALF_KM, key) : best;
}

// Where the person in `slot` stands: (offset x, offset z) in km from the
// record's anchor and the height in levels. Records: sim/src/view.rs.
vec3 dot_place(vec4 rec, uint slot) {
	uint key = uint(rec.w) >> 2u;
	vec2 p;
	if (rec.z < 0.0) {
		// city: the household's house in the city disk
		p = dot_land(rec.xy, rec.z, key);
	} else if (rec.z >= DOT_ROAD) {
		// on the road: anywhere on land in the current cell
		p = dot_land(rec.xy, DOT_CELL_HALF_KM, key);
	} else {
		// the household's village tile (the sim picks it), then its house
		uint vkey = dot_hash((uint(rec.z) - 1u) * 0x2545f491u);
		vec2 v = dot_village(rec.xy, DOT_FINE_HALF_KM, vkey);
		p = dot_land(v, -DOT_VILLAGE_KM, key);
	}
	// the family around its house, one spot per person
	p += (dot_rand2(slot, 99u) - 0.5) * 2.0 * DOT_FAMILY_KM;
	// far out the smooth relief is the surface; up close the dot stands on
	// its tile's corner levels, as trees and houses do
	float level = max(1.0, max(tt_corner_height(dot_tile(p)), 0.0) / m_per_level);
	if (relief_smooth < 0.999) {
		vec2 uv = fract((p - world_min) / tile_km);
		vec4 c = tt_corners_cached(dot_tile(p));
		level = mix(mix(c.x, c.y, uv.x), mix(c.w, c.z, uv.x), uv.y);
	}
	return vec3(p - rec.xy, level);
}
