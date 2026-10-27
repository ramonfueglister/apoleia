// People dots, shared part: the people record texture and the placement
// rule. people_dots_prep.gdshader runs the rule once per person into a float
// texture (only when the people or the terrain view changed); the dot shader
// (people_dots.gdshaderinc) then only reads that texture.

#include "res://shaders/tile_terrain.gdshaderinc"

uniform sampler2DArray people_tex : filter_nearest, repeat_disable;
uniform int page_side = 64;

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

// Where the person stands: (offset x, offset z) in km from the record's
// anchor and the height in levels.
vec3 dot_place(vec4 rec) {
	uint key = uint(rec.w) >> 2u;
	vec2 p = rec.xy;
	// up to eight spots in the area, then eight in twice the area; the first
	// on land wins, so people at home never stand in the sea
	for (uint k = 0u; k < 16u; k++) {
		vec2 r = dot_rand2(key, k);
		float wide = k < 8u ? 1.0 : 2.0;
		if (rec.z > 0.0) {
			p = rec.xy + (r - 0.5) * 2.0 * rec.z * wide;
		} else {
			// disk around a city, denser in the middle
			float a = r.x * 6.2831853;
			p = rec.xy + vec2(cos(a), sin(a)) * sqrt(r.y) * -rec.z * wide;
		}
		if (tt_water(dot_tile(p)) == W_LAND) {
			break;
		}
	}
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
