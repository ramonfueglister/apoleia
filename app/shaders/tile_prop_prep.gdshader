// One pixel per tree or house slot of the prop patch (tt_prop_place): trees
// on the left (3 x 3 pixels per tile), houses right of tree_w. tile_terrain.gd
// renders this into a float viewport every frame, and the prop vertex shader
// reads its slot instead of placing it per vertex.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/tile_terrain.gdshaderinc"
#include "res://shaders/tile_props.gdshaderinc"

uniform ivec2 prop_origin;
uniform int prop_n = 96;
uniform int tree_slots = 9;
uniform int house_slots = 4;
uniform int tree_w = 300; // first house column

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	bool house = px.x >= tree_w;
	if (house) { px.x -= tree_w; }
	ivec2 local = px / 3;
	int slot = (px.y % 3) * 3 + px.x % 3;
	int slots = house ? house_slots : tree_slots;
	COLOR = vec4(0.0, 0.0, 0.0, -1.0);
	if (local.x < prop_n && local.y < prop_n && slot < slots) {
		COLOR = tt_prop_place(prop_origin + local, slot, slots, house);
	}
}
