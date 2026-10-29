// People dots, large (zoomed in): the triangle is cut to a round dot.
// Code in people_dots.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

#define ROUND_DOTS
#include "res://shaders/people_dots.gdshaderinc"
