// People dots, small: triangles without discard, so the GPU keeps early
// depth testing (most dots are 1-2 px far out). Code in people_dots.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

#include "res://shaders/people_dots.gdshaderinc"
