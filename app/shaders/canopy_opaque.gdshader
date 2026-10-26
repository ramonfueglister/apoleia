shader_type spatial;
// Full-weight clipmap forest tiles (tile_forest.gd): no ALPHA write, so
// crowns skip the alpha-hash discard path (cheap depth prepass, early-Z/HSR);
// cones are outward-wound (landscape_style _outward_triangle), so back faces
// are culled. Fading tiles keep canopy.gdshader; both share canopy.gdshaderinc.
render_mode cull_back, world_vertex_coords, diffuse_burley;
#include "res://shaders/canopy.gdshaderinc"
