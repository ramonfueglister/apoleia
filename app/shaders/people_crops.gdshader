// The fields up close, in the voxel style of the farmhouses (Urbek): every
// sown parcel is a raised slab, a little in from the parcel lines so grass
// edges and the village lanes run between the fields. Wheat and barley are
// the slab itself, a closed sheet that grows with the season from bare
// soil through fresh and full green to ripe gold, then stubble; vegetables
// and beans stand in dense thin rows on a soil slab, vines in taller rows.
// One instance per parcel of a square around the camera (people_dots.gd
// _update_crops); the parcel's state, crop and growth come from the same
// fine layer and rule as the field colours (sim_fields.gdshaderinc). The
// crop mesh (people_dots.gd _crop_mesh) holds unit boxes (x, z in
// -0.5..0.5, y 0..1): the slab (UV.x < 0) and the rows (UV.x the row's
// place across the parcel).
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/sim_fields.gdshaderinc"

uniform vec2 crop_cell0;          // parcel index of the square's first parcel
uniform int crop_n = 48;          // parcels per side of the square
uniform float crop_rows = 12.0;   // rows per parcel
uniform float km_per_m = 0.0238;  // diorama scale (TileTerrain.DIORAMA_KM_PER_M)

varying vec3 colour;
varying vec3 art_light; // ART_LIGHT in view space
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)

// Colours (sRGB) after Urbek's farmland (gauntlet refs/urbek-landschaft-02):
// dark red-brown tilled soil, wheat and barley sheets from fresh green to
// gold, straw stubble; rows of vegetables and vines in deep greens.
const vec3 SOIL = vec3(0.47, 0.3, 0.22);
const vec3 SOIL_DRY = vec3(0.6, 0.46, 0.31);   // under the vines
const vec3 SPROUT = vec3(0.66, 0.82, 0.36);
const vec3 GREEN[2] = vec3[](vec3(0.56, 0.78, 0.3), vec3(0.66, 0.8, 0.36)); // lighter and yellower than the meadow
const vec3 RIPE[2] = vec3[](vec3(0.85, 0.8, 0.5), vec3(0.89, 0.83, 0.6));
const vec3 STUBBLE = vec3(0.8, 0.72, 0.5);
const vec3 LEAVES = vec3(0.42, 0.66, 0.26);
const vec3 VINE = vec3(0.36, 0.56, 0.2);
const vec3 VINE_BARE = vec3(0.42, 0.3, 0.2);
const float SLAB_GAP = 0.06;      // share of the parcel left free on each side

void vertex() {
	float size = tile_km * 0.5;
	vec2 cell = crop_cell0 + vec2(float(INSTANCE_ID % crop_n), float(INSTANCE_ID / crop_n));
	vec2 mid = (cell + 0.5) * size;
	vec4 f = vec4(0.0);
	int state = sim_map_on && sim_view_km <= SIM_CROPS_KM ? sim_parcel(cell, size, false, f) : 0;
	// fields lie only on open land outside the towns, as sim_fields, and
	// never on a farmhouse's lot
	ivec2 t = dot_tile(mid);
	int land = tt_ground_at(t, fract((mid - world_min) / tile_km));
	bool open = tt_town(t) == 0 && tt_water(t) == W_LAND && (land == G_FIELD || land == G_MEADOW || land == G_DRY_GRASS);
	bool show = state == 2 && open && !sim_house_lot(mid);
	float g = f.b;
	int kind = sim_crop_kind(cell); // one crop per parcel, as the ground colour
	bool grain = kind == SIM_WHEAT || kind == SIM_BARLEY;
	// the slab: its height (m) and colour by crop and season
	float slab = 0.25;
	vec3 c = SOIL;
	// the rows on it: height (m), width (share of the row spacing), colour
	float h = 0.0;
	float w = 0.0;
	vec3 rc = LEAVES;
	if (grain) {
		if (g <= 0.0) { slab = 0.15; c = STUBBLE; }
		else if (g < 0.12) { slab = 0.12; c = SOIL; }
		else if (g < 0.4) { slab = 0.3; c = SPROUT; }
		else if (g < 0.75) { slab = 0.55; c = GREEN[kind]; }
		else { slab = 0.8; c = RIPE[kind]; }
	} else if (kind == SIM_BEANS) {
		if (g < 0.12) { h = 0.0; }
		else if (g < 0.4) { h = 0.12; w = 0.25; rc = SPROUT; }
		else { h = 0.3; w = 0.35; rc = g < 0.75 ? LEAVES : mix(LEAVES, RIPE[0], 0.35); }
	} else {
		// vines stand the year round, every other row, bare in winter
		slab = 0.2;
		c = SOIL_DRY;
		h = g < 0.12 ? 0.8 : 1.1;
		w = 0.25;
		rc = g < 0.12 ? VINE_BARE : VINE;
	}
	bool base = UV.x < 0.0;
	if (!base && (h <= 0.0 || (kind == SIM_VINES && int(UV.y) % 2 == 1))) { show = false; }
	float inner = size * (1.0 - 2.0 * SLAB_GAP);
	vec2 off; // from the parcel's middle, km
	if (base) {
		off = VERTEX.xz * inner;
	} else {
		float step = inner / crop_rows;
		off = vec2(VERTEX.x * inner * 0.97, (UV.x - 0.5) * inner + VERTEX.z * w * step);
		if (sim_crop_rows_ns(cell)) { off = off.yx; }
	}
	vec2 p = mid + off;
	vec4 k = tt_corners_cached(dot_tile(p));
	vec2 uv = fract((p - world_min) / tile_km);
	float level = mix(mix(k.x, k.y, uv.x), mix(k.w, k.z, uv.x), uv.y);
	float y = base ? VERTEX.y * slab : slab + VERTEX.y * h;
	vec3 world = vec3(p.x, level * level_h + y * km_per_m, p.y);
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// flat faces: tops in the colour, sides a step darker (vertex alpha)
	colour = pow(base ? c : rc, vec3(2.2)) * COLOR.a;
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
