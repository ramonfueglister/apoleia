// Every simulated person as a black dot on the tile terrain. One MultiMesh
// instance per person slot; the record comes from the people texture array
// (sim/src/view.rs: x, z, spread radius in km, key * 4 + kind), filled by
// ApoleiaPeople.sync with only the pages that changed. The vertex stage
// picks a land tile inside the person's area from a hash of the key and
// stands the dot on that tile's corner levels, as tile_props does for trees,
// so dots follow the terrain at every zoom without CPU placement.

#include "res://shaders/tile_terrain.gdshaderinc"

uniform sampler2DArray people_tex : filter_nearest, repeat_disable;
uniform int page_side = 64;
uniform float dot_px = 3.0;      // dot radius in pixels
uniform vec3 dot_colour : source_color = vec3(0.02, 0.02, 0.02);
uniform vec3 road_colour : source_color = vec3(0.45, 0.05, 0.03); // on the road or at sea
uniform float cull_margin = 1.15; // NDC margin of the early cull

varying vec2 local;
varying flat uint kind;

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

void vertex() {
	local = VERTEX.xy;
	int id = INSTANCE_ID;
	int per = page_side * page_side;
	int in_page = id % per;
	vec4 rec = texelFetch(people_tex, ivec3(in_page % page_side, in_page / page_side, id / per), 0);
	POSITION = vec4(2.0, 2.0, 2.0, 1.0); // outside the clip volume: no dot
	if (rec.z != 0.0) {
		uint key = uint(rec.w) >> 2u;
		vec2 p = rec.xy;
		kind = uint(rec.w) & 3u;
		// coarse cull on the anchor first: an area fully off screen costs
		// one texel fetch and no terrain lookups
		float spread = abs(rec.z);
		vec4 a0 = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(rec.x, 0.0, rec.y, 1.0));
		vec4 a1 = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(rec.x + spread, 0.0, rec.y + spread, 1.0));
		float slack = length(a1.xy / a1.w - a0.xy / a0.w) + 0.5;
		if (a0.w > 0.0 && all(lessThan(abs(a0.xy / a0.w), vec2(cull_margin + slack)))) {
		// up to eight spots in the area, then eight in twice the area; the
		// first on land wins, so people at home never stand in the sea
		for (uint k = 0u; k < 16u; k++) {
			vec2 r = dot_rand2(key, k);
			float wide = k < 8u ? 1.0 : 2.0;
			vec2 q;
			if (rec.z > 0.0) {
				q = rec.xy + (r - 0.5) * 2.0 * rec.z * wide;
			} else {
				// disk around a city, denser in the middle
				float a = r.x * 6.2831853;
				q = rec.xy + vec2(cos(a), sin(a)) * sqrt(r.y) * -rec.z * wide;
			}
			p = q;
			if (tt_water(dot_tile(q)) == W_LAND) {
				break;
			}
		}
		// cheap height guess for the early cull, then the exact tile surface
		float guess = max(1.0, max(tt_corner_height(dot_tile(p)), 0.0) / m_per_level) * level_h;
		vec4 c0 = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p.x, guess, p.y, 1.0));
		if (c0.w > 0.0 && all(lessThan(abs(c0.xy), vec2(cull_margin * c0.w)))) {
			float level = guess / level_h;
			if (relief_smooth < 0.999) {
				// tiles: the dot stands on its tile's corner levels (far out the
				// smooth relief already is the surface, so the guess is exact)
				ivec2 t = dot_tile(p);
				vec2 uv = fract((p - world_min) / tile_km);
				vec4 c = tt_corners_cached(t);
				level = mix(mix(c.x, c.y, uv.x), mix(c.w, c.z, uv.x), uv.y);
			}
			vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p.x, (level + 0.12) * level_h, p.y, 1.0));
			// a screen-space triangle around the dot, constant size in pixels
#ifdef ROUND_DOTS
			float size = dot_px;
#else
			float size = dot_px * 0.6; // the bare triangle about as big as the dot
#endif
			clip.xy += VERTEX.xy * size * 2.0 / VIEWPORT_SIZE * clip.w;
			POSITION = clip;
		}
		}
	}
}

void fragment() {
#ifdef ROUND_DOTS
	if (dot(local, local) > 1.0) {
		discard;
	}
#endif
	ALBEDO = kind >= 2u ? road_colour : dot_colour;
}
