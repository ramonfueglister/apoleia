// One float pixel per person slot (or house slot): where the person stands (offset from the
// anchor in km plus 32, height in levels, alpha 1 = placed). people_dots.gd renders
// this only when the people or the terrain view (zoom level, relief blend,
// corner patch) changed; the dot shader reads it.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/people_dots_common.gdshaderinc"

uniform bool houses = false; // the house records (people_houses.gdshader)

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	vec4 rec = dot_record(px);
	uint slot = uint((px.y / page_side) * page_side * page_side + (px.y % page_side) * page_side + px.x);
	// offsets +32 km, so the float target only ever holds positive values
	COLOR = rec.z != 0.0 ? vec4(dot_place(rec, slot, houses) + vec3(32.0, 32.0, 0.0), 1.0) : vec4(0.0);
}
