// Carriers and wagons on their way (people_trips.gd): one instance per
// traveller, its transform the place (x, z, world km) and heading, the
// height from the terrain under it (as people_dots_common places the
// figures). The mesh holds every part in metres (UV.x the part): the
// person (0), a donkey (1) and its sacks (2), a wagon (3), its ox (4) and
// its load (5), a hired hand's sickle (6), seed basket (7) or hoe (8);
// or a market stall (9); INSTANCE_CUSTOM.r says which parts beyond the
// person show, .a whether it walks (0), stands (1) or is a stall without
// a person (2)
// (bit part - 1), .g the walk's phase, .b the tunic colour. Legs (UV2.x the
// side, UV2.y the hip in metres) swing as they walk.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"

uniform float km_per_m = 0.0238; // diorama scale (TileTerrain.DIORAMA_KM_PER_M)
uniform float stride = 9.0;      // leg swings per second
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)
// undyed wool and linen, madder red, woad blue, browns, a leaf green and a
// grey blue, as the figures wear them (people_figures.gdshader TUNICS, sRGB):
// none close to the skin (the first walkers in browns read as naked)
const vec3 TUNICS[8] = vec3[](vec3(0.81, 0.76, 0.65), vec3(0.86, 0.83, 0.74), vec3(0.61, 0.25, 0.16),
	vec3(0.25, 0.37, 0.56), vec3(0.43, 0.29, 0.18), vec3(0.36, 0.43, 0.23), vec3(0.33, 0.24, 0.17), vec3(0.4, 0.45, 0.52));

varying vec3 colour;
varying vec3 art_light; // ART_LIGHT in view space

void vertex() {
	int part = int(UV.x);
	int parts = int(INSTANCE_CUSTOM.r + 0.5);
	float still = INSTANCE_CUSTOM.a;
	bool show = part == 0 ? still < 1.5 : ((parts >> (part - 1)) & 1) == 1;
	// off the water: where a route crosses a river or a lake they take the
	// bridge or the ferry, out of sight (the first ones walked on the Tiber)
	show = show && tt_water(dot_tile(MODEL_MATRIX[3].xz)) == W_LAND;
	vec3 v = VERTEX;
	if (UV2.x != 0.0 && still < 0.5) {
		// a leg swings about its hip, the two sides in turn
		float swing = sin(TIME * stride + INSTANCE_CUSTOM.g * 6.2831853) * UV2.x;
		v.z += swing * max(UV2.y - v.y, 0.0) * 0.45;
	}
	vec2 at = MODEL_MATRIX[3].xz;
	vec3 world = (MODEL_MATRIX * vec4(v * km_per_m, 1.0)).xyz;
	world.y = dot_ground_level(at) * level_h + v.y * km_per_m;
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(NORMAL, 0.0))).xyz);
	vec3 c = COLOR.rgb;
	if (part == 0 && all(greaterThan(c, vec3(0.99)))) { c = TUNICS[int(INSTANCE_CUSTOM.b) % 8]; } // the white tunic
	colour = pow(c, vec3(2.2)) * COLOR.a; // the vertex alpha: the voxel corner shading
	art_light = normalize((VIEW_MATRIX * vec4(ART_LIGHT, 0.0)).xyz);
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}

// Lit from the terrain's SimCity direction, as the figures (people_figures.gdshader).
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float shadow = dot(NORMAL, LIGHT) > 0.05 ? ATTENUATION : 1.0;
		DIFFUSE_LIGHT += max(dot(NORMAL, art_light), 0.0) * shadow * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
