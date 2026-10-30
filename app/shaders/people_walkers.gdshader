// Carriers and wagons on their way (people_trips.gd): one instance per
// traveller on the stretch of its route it walks now, the height from the
// terrain under it (as people_dots_common places the figures). The GPU
// walks it along the stretch (people_trips.gd writes it only when it
// reaches the stretch's end, not every frame): its transform holds, row by
// row, [d.y, 0, d.x, start x], [velocity x, 1, velocity z, start time] and
// [-d.x, 0, d.y, start z], d its heading (world km and walk_clock seconds).
// The mesh holds every part in metres (UV.x the part): the
// person (0), a donkey (1) and its sacks (2), a wagon (3), its ox (4) and
// its load (5), a hired hand's sickle (6), seed basket (7) or hoe (8);
// or a market stall (9); or, in the scenes of events, a handcart (10), a
// bundle on the back (11), a bier with its second bearer (12), an axe (13)
// or a bowl (14), a ship (15: shown instead of cart, ox and carter where
// a cart is on the sea or a lake), craft goods on a cart (16-20) and the
// wares on a stall's counter (21, dyed by the stall's good, .b, heaped by
// .g); INSTANCE_CUSTOM.r says which parts beyond the
// person show (bit part - 1), .g how many seconds it walks on from the
// start before it stops (a stall: how full its counter is), .b the tunic
// colour plus the walk's phase as the fraction (a stall: its good), .a whether it walks (0), stands (1) or is a stall without a
// person (2). Legs (UV2.x the side, UV2.y the hip in metres) swing as they
// walk.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"

uniform float km_per_m = 0.0238; // diorama scale (TileTerrain.DIORAMA_KM_PER_M)
uniform float stride = 9.0;      // leg swings per second
uniform float walk_clock = 0.0;  // people_trips.gd's clock, seconds
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)
// undyed wool and linen, madder red, woad blue, browns, a leaf green and a
// grey blue, as the figures wear them (people_figures.gdshader TUNICS, sRGB):
// none close to the skin (the first walkers in browns read as naked)
// the wares of a stall by its good (people_trips.gd GOOD_NAMES, then
// grain): wool, iron, cloth, tools, ceramics, pork, grain (sRGB)
const vec3 WARES[7] = vec3[](vec3(0.9, 0.87, 0.78), vec3(0.42, 0.42, 0.46), vec3(0.62, 0.22, 0.18),
	vec3(0.5, 0.37, 0.24), vec3(0.74, 0.4, 0.24), vec3(0.8, 0.46, 0.42), vec3(0.86, 0.72, 0.38));
const vec3 TUNICS[8] = vec3[](vec3(0.81, 0.76, 0.65), vec3(0.86, 0.83, 0.74), vec3(0.61, 0.25, 0.16),
	vec3(0.25, 0.37, 0.56), vec3(0.43, 0.29, 0.18), vec3(0.36, 0.43, 0.23), vec3(0.33, 0.24, 0.17), vec3(0.4, 0.45, 0.52));

// Whether p lies in water: the sea, a lake, or the band a river draws
// through its data tile with its bank (tile_terrain.gdshader fragment);
// the rest of a river tile is land (r11 walkers: hiding them on the whole
// tile also hid the stalls of a market on the Tiber's bank).
bool walker_wet(vec2 p) {
	float dk = tt_data_km();
	ivec2 dt = ivec2(floor((p - world_min) / dk));
	int w = tt_data_cell(dt) & 3;
	if (w == W_LAND) { return false; }
	if (w != W_RIVER) { return true; }
	const ivec2 SIDE4[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
	const vec2 MID[4] = vec2[](vec2(0.0, -0.5), vec2(0.5, 0.0), vec2(0.0, 0.5), vec2(-0.5, 0.0));
	int m = 0;
	for (int k = 0; k < 4; k++) {
		if ((tt_data_cell(dt + SIDE4[k]) & 3) != W_LAND) { m |= 1 << k; }
	}
	vec2 q = (p - world_min) / dk - vec2(dt) - 0.5;
	float half_w = clamp(0.075 / dk, 0.06, 0.22) + 0.03; // and the bank
	float d = 10.0;
	if (m == 3 || m == 6 || m == 12 || m == 9) {
		int a = m == 9 ? 3 : (m == 3 ? 0 : m == 6 ? 1 : 2);
		vec2 p0 = MID[a];
		vec2 e = MID[(a + 1) % 4] - p0;
		d = length(q - p0 - e * clamp(dot(q - p0, e) / dot(e, e), 0.0, 1.0));
	} else {
		d = length(q);
		for (int k = 0; k < 4; k++) {
			if ((m & (1 << k)) != 0) {
				vec2 e = MID[k];
				d = min(d, length(q - e * clamp(dot(q, e) / dot(e, e), 0.0, 1.0)));
			}
		}
	}
	return d < half_w;
}

// Whether p lies on the sea or a lake, where a cart goes by ship (on a
// river it takes the bridge or the ferry out of sight, as everyone).
bool walker_sea(vec2 p) {
	int w = tt_data_cell(ivec2(floor((p - world_min) / tt_data_km()))) & 3;
	return w != W_LAND && w != W_RIVER;
}

varying vec3 colour;
varying vec3 art_light; // ART_LIGHT in view space

void vertex() {
	int part = int(UV.x);
	int parts = int(INSTANCE_CUSTOM.r + 0.5);
	float still = INSTANCE_CUSTOM.a;
	bool show = part == 0 ? still < 1.5 : ((parts >> (part - 1)) & 1) == 1;
	// off the water: where a route crosses a river or a lake they take the
	// bridge or the ferry, out of sight (the first ones walked on the Tiber)
	// where it is now on its stretch, and its turn about y (front +z along d)
	vec2 velocity = vec2(MODEL_MATRIX[0].y, MODEL_MATRIX[2].y);
	vec2 at = MODEL_MATRIX[3].xz + velocity * clamp(walk_clock - MODEL_MATRIX[3].y, 0.0, INSTANCE_CUSTOM.g);
	mat3 turn = mat3(vec3(MODEL_MATRIX[0].x, 0.0, MODEL_MATRIX[0].z), vec3(0.0, 1.0, 0.0), vec3(MODEL_MATRIX[2].x, 0.0, MODEL_MATRIX[2].z));
	bool wet = walker_wet(at);
	bool ship = ((parts >> 2) & 1) == 1 && wet && walker_sea(at); // a cart (part 3) at sea
	show = part == 15 ? ship : show && !wet;
	vec3 v = VERTEX;
	if (part == 21) {
		v.y = 1.0 + (v.y - 1.0) * INSTANCE_CUSTOM.g * 1.6; // heaped on the counter (its top at 1 m)
	}
	if (UV2.x != 0.0 && still < 0.5) {
		// a leg swings about its hip, the two sides in turn
		float swing = sin(TIME * stride + fract(INSTANCE_CUSTOM.b) * 6.2831853) * UV2.x;
		v.z += swing * max(UV2.y - v.y, 0.0) * 0.45;
	}
	// the parts it does not have: all on one point behind the camera, without asking the ground
	VERTEX = vec3(0.0, 0.0, 1.0e6);
	if (show) {
		vec3 world = turn * (v * km_per_m) + vec3(at.x, 0.0, at.y);
		world.y = dot_ground_level(at) * level_h + v.y * km_per_m;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(turn * NORMAL, 0.0)).xyz);
	vec3 c = COLOR.rgb;
	if (part == 0 && all(greaterThan(c, vec3(0.99)))) { c = TUNICS[int(INSTANCE_CUSTOM.b) % 8]; } // the white tunic
	if (part == 21) { c *= WARES[int(INSTANCE_CUSTOM.b + 0.5) % 7]; }
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
