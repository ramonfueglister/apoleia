// The grain standing on the sown parcels up close, in the voxel style of the
// farmhouses (Urbek): rows of plant clumps that grow with the season, from
// sprouts on the soil to a closed sheet of ripe golden wheat, then stubble.
// One instance per parcel of a square around the camera (people_dots.gd
// _update_crops); the parcel's state and growth come from the same fine
// layer and rule as the field colours (sim_fields.gdshaderinc), so the
// plants stand exactly on the soil the terrain paints. The crop mesh
// (people_dots.gd _crop_mesh) holds unit clumps: VERTEX the offset in the
// clump (x, z in -0.5..0.5, y 0..1), UV the clump's place in the parcel.
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/sim_fields.gdshaderinc"

uniform vec2 crop_cell0;          // parcel index of the square's first parcel
uniform int crop_n = 48;          // parcels per side of the square
uniform float crop_rows = 8.0;    // rows (and clumps per row) per parcel
uniform float km_per_m = 0.0238;  // diorama scale (TileTerrain.DIORAMA_KM_PER_M)

varying vec3 colour;
varying vec3 art_light; // ART_LIGHT in view space
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)

// the plants through the season (sRGB), by crop: fresh sprouts, green
// corn, ripe wheat after Urbek's measured wheat; barley a little paler; beans
// low, bushy and dark, ripening brown; straw stubble after the harvest
const vec3 SPROUT[3] = vec3[](vec3(0.52, 0.72, 0.3), vec3(0.62, 0.78, 0.37), vec3(0.36, 0.58, 0.24));
const vec3 GREEN[3] = vec3[](vec3(0.4, 0.62, 0.24), vec3(0.55, 0.71, 0.3), vec3(0.27, 0.47, 0.2));
const vec3 RIPE[3] = vec3[](vec3(0.84, 0.77, 0.44), vec3(0.9, 0.84, 0.58), vec3(0.6, 0.53, 0.3));
const float CROP_H[3] = float[](1.0, 0.85, 0.6); // ripe height (m)
const vec3 STUBBLE = vec3(0.78, 0.68, 0.43);

void vertex() {
	float size = tile_km * 0.5;
	vec2 cell = crop_cell0 + vec2(float(INSTANCE_ID % crop_n), float(INSTANCE_ID / crop_n));
	vec2 mid = (cell + 0.5) * size;
	vec4 f = vec4(0.0);
	int state = sim_map_on && sim_view_km <= SIM_CROPS_KM ? sim_parcel(cell, size, false, f) : 0;
	// fields lie only on open land outside the towns, as sim_fields
	ivec2 t = dot_tile(mid);
	int land = tt_ground_at(t, fract((mid - world_min) / tile_km));
	bool open = tt_town(t) == 0 && tt_water(t) == W_LAND && (land == G_FIELD || land == G_MEADOW || land == G_DRY_GRASS);
	float g = f.b;
	// one crop per parcel, half of them wheat, so the farmland is a patchwork
	float pick = sim_hash(cell + 5.1);
	int kind = pick < 0.5 ? 0 : pick < 0.75 ? 1 : 2;
	// height (m) and width (share of the row spacing) by the season;
	// ploughed earth has none
	float h = 0.0;
	float w = 0.0;
	vec3 c = GREEN[kind];
	if (g <= 0.0) { h = 0.15; w = 0.9; c = STUBBLE; }
	else if (g < 0.12) { h = 0.0; }
	else if (g < 0.4) { h = 0.2 + 0.4 * (g - 0.12) / 0.28; w = 0.35; c = SPROUT[kind]; }
	else if (g < 0.75) { h = 0.6 + 0.3 * (g - 0.4) / 0.35; w = 0.6; c = GREEN[kind]; }
	else { h = 1.0; w = 1.0; c = RIPE[kind]; }
	if (kind == 2 && g > 0.0) { h *= CROP_H[2]; w = max(w, 0.75); } // beans: low bushes
	else if (g >= 0.75) { h = CROP_H[kind]; }
	// the farmhouses keep their lot (house, garden, yard) free of corn
	bool house = sim_house_lot(cell * size + UV * size);
	bool show = state == 2 && open && h > 0.0 && !house;
	float step = size / crop_rows;
	// ripe wheat closes along the row and leaves a furrow between rows
	vec2 half_w = vec2(w, w >= 1.0 ? 0.8 : w) * step;
	vec2 r = vec2(sim_hash(cell + UV * 31.0), sim_hash(cell - UV * 17.0));
	vec2 p = cell * size + UV * size + VERTEX.xz * half_w;
	vec4 k = tt_corners_cached(dot_tile(p));
	vec2 uv = fract((p - world_min) / tile_km);
	float level = mix(mix(k.x, k.y, uv.x), mix(k.w, k.z, uv.x), uv.y);
	float plant = h * km_per_m * (w >= 1.0 ? 1.0 : 0.85 + 0.3 * r.x);
	vec3 world = vec3(p.x, level * level_h + VERTEX.y * plant, p.y);
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// the tops of the sheet a touch lighter, clumps a little varied
	colour = pow(c * (0.94 + 0.12 * r.y), vec3(2.2)) * COLOR.a;
	art_light = normalize((VIEW_MATRIX * vec4(ART_LIGHT, 0.0)).xyz);
}

void fragment() {
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}

// lit like the farmhouses (people_houses.gdshader)
void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float shadow = dot(NORMAL, LIGHT) > 0.05 ? ATTENUATION : 1.0;
		DIFFUSE_LIGHT += max(dot(NORMAL, art_light), 0.0) * shadow * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}
