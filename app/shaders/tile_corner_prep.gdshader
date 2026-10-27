// One pixel per tile of the drawn patch: the levels of its four corners
// (c00, c10, c11, c01), the same values tt_corners() gives. tile_terrain.gd
// renders this into a float viewport every frame, and the terrain and prop
// shaders read it (tt_corners_cached) instead of evaluating the rule per vertex.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/tile_terrain.gdshaderinc"

void fragment() {
	COLOR = tt_corners(corner_origin + ivec2(FRAGCOORD.xy));
}
