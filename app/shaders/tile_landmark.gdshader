// Rome's landmarks on the tile terrain (tile_terrain.gd, meshes in
// tile_prop_meshes.gd): vertex colours, lit like the houses, with the sides
// turned to the SimCity light of the terrain a little lighter.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/tile_terrain.gdshaderinc"

varying float tint;

void vertex() {
	vec3 nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 art = tt_art_light(INV_VIEW_MATRIX);
	float facing = abs(nrm.y) < 0.5 ? dot(normalize(nrm.xz), normalize(art.xz)) : 0.0;
	tint = 1.0 + 0.25 * max(facing, 0.0);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb * tint, vec3(2.2)); // vertex colours are sRGB
	ROUGHNESS = 1.0;
}
