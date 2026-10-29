// The farmhouse a lot would get, as a see-through ghost for the build menu
// (scripts/voxel/farmhouse_ghost.gd): the house and its yard in their own
// colours, tinted green where it can be built and red where not, without
// the trees and haystack round the lot and without the workshops and the
// scaffold (farmhouse.gd palette indices in UV.y), which not every farm has.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_lambert, specular_disabled, shadows_disabled;

uniform vec3 tint = vec3(0.55, 0.9, 0.45); // sRGB

varying flat int index;

void vertex() {
	index = int(UV.y + 0.5);
}

void fragment() {
	if ((index >= 21 && index <= 26) || index == 28 || index >= 41) { discard; }
	ALBEDO = pow(mix(COLOR.rgb, tint, 0.55), vec3(2.2)); // vertex colours are sRGB
	ALPHA = 0.6;
	ROUGHNESS = 1.0;
}
