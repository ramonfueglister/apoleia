// One float pixel per person slot (or house slot): where the person stands (offset from the
// anchor in km plus 32, height in levels, alpha 1 = placed). people_dots.gd renders
// this only when the people or the terrain view (zoom level, relief blend,
// corner patch) changed; the dot shader reads it. With the dots off only the
// people drawn as figures are placed (`listed`): a unit quad per entry of
// the figure list moved onto its slot's pixel, a thousand or two instead of
// every person (Mac tour, 29.10.2026: the whole pass ran with each new day).
shader_type canvas_item;
render_mode blend_disabled, unshaded, skip_vertex_transform; // the listed quads have no transforms

#define DOT_WAYS // the houses keep off the ways (dot_lot_way_free); brings sim_fields.gdshaderinc
#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/people_crop_slab.gdshaderinc"

uniform bool houses = false; // the house records (people_houses.gdshader)
uniform bool listed = false; // drawn as the quads of the figure list, not as one rectangle
uniform sampler2D list_tex : filter_nearest, repeat_disable; // slots of the figures (float)
uniform int list_w = 128;

void vertex() {
	if (listed) {
		int i = INSTANCE_ID;
		int slot = int(texelFetch(list_tex, ivec2(i % list_w, i / list_w), 0).r);
		int per = page_side * page_side;
		int in_page = slot % per;
		VERTEX += vec2(float(in_page % page_side), float((slot / per) * page_side + in_page / page_side)) + 0.5;
	}
}

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	vec4 rec = dot_record(px);
	uint slot = uint((px.y / page_side) * page_side * page_side + (px.y % page_side) * page_side + px.x);
	vec2 lot_at;
	vec3 place = dot_place_at(rec, slot, houses, lot_at);
	// up close a person in a field stands on its slab (people_crop_slab.gdshaderinc)
	if (!houses && rec.z != 0.0) {
		place.z += crop_slab_under(rec.xy + place.xy) * dot_km_per_m / level_h;
	}
	// offsets +32 km, so the float target only ever holds positive values
	// alpha: 1 placed; 2 + k with the lot of the person's farmhouse the k-th
	// (row by row) of the 3 x 3 round the lot under its spot, for its way
	// out along the lanes (people_field_route.gdshaderinc)
	float placed = 1.0;
	if (lot_at.x < 1e8) {
		// the spot as the figures read it back from this half float target
		vec2 spot = rec.xy + unpackHalf2x16(packHalf2x16(place.xy + 32.0)) - 32.0;
		ivec2 d = ivec2(round((lot_at - dot_lot(spot)) / DOT_LOT_KM));
		if (abs(d.x) <= 1 && abs(d.y) <= 1) {
			placed = 2.0 + float((d.y + 1) * 3 + d.x + 1);
		}
	}
	COLOR = rec.z != 0.0 ? vec4(place + vec3(32.0, 32.0, 0.0), placed) : vec4(0.0);
}
