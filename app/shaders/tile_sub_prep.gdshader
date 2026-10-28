// One pixel per quarter tile of a window around the patch (tile_terrain.gd,
// SUB_KM): r its cell, g its landscape, b the level of its corner c00, cut
// from the 0.5 km data tiles (tt_sub_cell, tt_sub_ground, tt_sub_corner).
// tile_terrain.gd renders it into a float viewport when the window moves on,
// and the other shaders read it with sub_tiles on (sub_tex).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/tile_terrain.gdshaderinc"

uniform ivec2 sub_window_origin;

void fragment() {
	ivec2 s = sub_window_origin + ivec2(FRAGCOORD.xy);
	COLOR = vec4(float(tt_sub_cell(s)), float(tt_sub_ground(s)), tt_sub_corner(s), 1.0);
}
