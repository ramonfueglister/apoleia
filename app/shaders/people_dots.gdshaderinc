// Every simulated person as a black dot on the tile terrain. One MultiMesh
// instance per person slot; the record comes from the people texture array
// (sim/src/view.rs: x, z, spread radius in km, key * 4 + kind), filled by
// ApoleiaPeople.sync with only the pages that changed. Where each person
// stands (a land tile in their area, on its corner levels) is worked out once
// per person by people_dots_prep.gdshader whenever the people or the terrain
// view change; the vertex stage here only reads it, so a frame costs two
// texel fetches per dot.

#include "res://shaders/people_dots_common.gdshaderinc"

const int DOTS_PER_INSTANCE = 64; // people_dots.gd DOTS_PER_INSTANCE

uniform sampler2D place_tex : filter_nearest, repeat_disable; // people_dots_prep output
uniform float dot_px = 3.0;      // dot radius in pixels
uniform vec3 dot_colour : source_color = vec3(0.02, 0.02, 0.02);
uniform vec3 road_colour : source_color = vec3(0.45, 0.05, 0.03); // on the road or at sea

varying vec2 local;
varying flat uint kind;

void vertex() {
	local = VERTEX.xy;
	// DOTS_PER_INSTANCE triangles per instance (VERTEX.z = dot within the
	// batch): one tiny 3-vertex instance per dot would leave most lanes of
	// the GPU's vertex SIMD groups idle
	int id = INSTANCE_ID * DOTS_PER_INSTANCE + int(VERTEX.z);
	int per = page_side * page_side;
	int in_page = id % per;
	ivec2 px = ivec2(in_page % page_side, (id / per) * page_side + in_page / page_side);
	vec4 rec = dot_record(px);
	vec4 place = texelFetch(place_tex, px, 0);
	kind = uint(rec.w) & 3u;
	POSITION = vec4(2.0, 2.0, 2.0, 1.0); // outside the clip volume: no dot
	if (rec.z != 0.0 && place.a > 0.5) {
		vec2 p = rec.xy + place.xy - 32.0;
		vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(p.x, (place.z + 0.12) * level_h, p.y, 1.0));
		if (clip.w > 0.0 && all(lessThan(abs(clip.xy), vec2(1.05 * clip.w)))) {
			// a screen-space triangle around the dot, constant size in pixels
#ifdef ROUND_DOTS
			float size = dot_px;
#else
			float size = dot_px * 0.6; // the bare triangle about as big as the dot
#endif
			// city people are packed tight; smaller dots keep the roofs visible
			size *= kind == 1u ? 0.55 : 1.0;
			clip.xy += VERTEX.xy * size * 2.0 / VIEWPORT_SIZE * clip.w;
			POSITION = clip;
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
