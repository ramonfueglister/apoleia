// The road the build menu would build, see-through and tinted green where
// it can be built, red where not (road.gdshaderinc).
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled, depth_draw_never;

#define PREVIEW
#include "res://shaders/road.gdshaderinc"
