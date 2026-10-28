// The village lots that carry a house, as a small mask around the camera
// (one pixel per lot of DOT_LOT_KM, people_dots_common.gdshaderinc), so the
// crops (people_crops.gdshader) leave the farmhouses, their gardens and
// yards free. One instance per entry of the house list (people_houses
// .gdshader), a unit quad moved onto its lot's pixel.
shader_type canvas_item;
render_mode unshaded, blend_disabled, skip_vertex_transform; // the instances have no transforms

uniform sampler2DArray people_tex : filter_nearest, repeat_disable; // house records
uniform int page_side = 64;
uniform sampler2D place_tex : filter_nearest, repeat_disable; // house placement pass
uniform sampler2D list_tex : filter_nearest, repeat_disable;  // house slots (float)
uniform int list_w = 128;
uniform vec2 lot_origin; // lot index of the mask's first pixel
uniform float lot_km = 0.5;

void vertex() {
	int i = INSTANCE_ID;
	int slot = int(texelFetch(list_tex, ivec2(i % list_w, i / list_w), 0).r);
	int per = page_side * page_side;
	int in_page = slot % per;
	ivec2 px = ivec2(in_page % page_side, (slot / per) * page_side + in_page / page_side);
	vec4 rec = texelFetch(people_tex, ivec3(px.x, px.y % page_side, px.y / page_side), 0);
	vec4 place = texelFetch(place_tex, px, 0);
	vec2 p = rec.xy + place.xy - 32.0;
	vec2 lot = floor(p / lot_km) - lot_origin;
	bool show = rec.z > 0.0 && place.a > 0.5;
	VERTEX = show ? lot + 0.5 + VERTEX : vec2(-1.0e6);
}

void fragment() {
	COLOR = vec4(1.0);
}
