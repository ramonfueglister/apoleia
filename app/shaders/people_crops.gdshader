// The fields up close, in the voxel style of the farmhouses (Urbek): every
// sown parcel is a raised slab, a little in from the parcel lines so grass
// edges and the village lanes run between the fields. Two looks, as in
// Urbek's farmland (gauntlet refs/urbek-landschaft-02): dark tilled soil
// with green rows, and a closed sheet of grain, pale straw when ripe. Wheat
// grows from bare soil through rows of sprouts to dense green rows, barley
// to a closed sage sheet; both ripen to a straw sheet and are cut to
// stubble. Beans stand in rows of separate clumps behind a wooden fence,
// vines in taller rows. One instance per parcel of a square around the
// camera (people_dots.gd _update_crops); the parcel's state, crop and
// growth come from the same fine layer and rule as the field colours
// (sim_fields.gdshaderinc). The crop mesh (people_dots.gd _crop_mesh) holds
// unit boxes (x, z in -0.5..0.5, y 0..1): the slab (UV.x -1), the rows
// (UV.x the row's place across the parcel) and the fence (UV.x -2).
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/sim_fields.gdshaderinc"

uniform vec2 crop_cell0;          // parcel index of the square's first parcel
uniform int crop_n = 48;          // parcels per side of the square
uniform float crop_rows = 12.0;   // rows per parcel
uniform float km_per_m = 0.0238;  // diorama scale (TileTerrain.DIORAMA_KM_PER_M)

varying vec3 colour;
varying float along;  // 0..1 along a row of clumps or a fence side
varying float clumps; // clumps per row (0: a closed row)
varying vec3 art_light; // ART_LIGHT in view space
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)

// Colours (sRGB) after Urbek's farmland (gauntlet refs/urbek-landschaft-02):
// dark red-brown tilled soil, deep green rows, pale straw grain; a step
// lighter than Urbek's as the meadow round them is.
const vec3 SOIL = vec3(0.38, 0.25, 0.2);
const vec3 SOIL_DRY = vec3(0.56, 0.42, 0.3);   // under the vines
const vec3 SPROUT = vec3(0.4, 0.62, 0.26);
const vec3 GRAIN_GREEN = vec3(0.26, 0.48, 0.2);
const vec3 BARLEY_GREEN = vec3(0.3, 0.52, 0.24); // a lush sheet, darker than the meadow
const vec3 RIPE[2] = vec3[](vec3(0.68, 0.64, 0.36), vec3(0.72, 0.68, 0.46)); // wheat, barley (Urbek's wheat #c0c672 lit)
const vec3 STUBBLE = vec3(0.62, 0.54, 0.38);
const vec3 LEAVES = vec3(0.24, 0.5, 0.2);
const vec3 VINE = vec3(0.3, 0.5, 0.18);
const vec3 VINE_BARE = vec3(0.42, 0.3, 0.2);
const vec3 FENCE = vec3(0.54, 0.42, 0.28);     // the farmhouse fence (farmhouse.gd FENCE)
const float FENCE_POSTS = 6.0;   // posts per side, about two metres apart
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
	float slab = 0.12;
	vec3 c = SOIL;
	// the rows on it: height (m), width (share of the row spacing), colour,
	// clumps per row (0: closed)
	float h = 0.0;
	float w = 0.0;
	vec3 rc = LEAVES;
	clumps = 0.0;
	if (grain) {
		if (g <= 0.0) { slab = 0.15; c = STUBBLE; }
		else if (g < 0.12) { }
		else if (g < 0.4) { h = 0.12; w = 0.3; rc = SPROUT; clumps = 14.0; }
		else if (g < 0.75 && kind == SIM_WHEAT) { h = 0.4; w = 0.6; rc = GRAIN_GREEN; }
		else if (g < 0.75) { slab = 0.5; c = BARLEY_GREEN; }
		else { slab = 0.8; c = RIPE[kind]; }
	} else if (kind == SIM_BEANS) {
		if (g < 0.12) { }
		else if (g < 0.4) { h = 0.15; w = 0.3; rc = SPROUT; clumps = 12.0; }
		else { h = 0.5; w = 0.35; rc = g < 0.75 ? LEAVES : mix(LEAVES, RIPE[0], 0.3); clumps = 12.0; }
	} else {
		// vines stand the year round, every other row of plants, bare in winter
		slab = 0.2;
		c = SOIL_DRY;
		h = g < 0.12 ? 0.8 : 1.1;
		w = 0.4;
		rc = g < 0.12 ? VINE_BARE : VINE;
		clumps = 8.0;
	}
	bool base = UV.x == -1.0;
	bool fence = UV.x == -2.0;
	bool row = UV.x >= 0.0;
	if (row && (h <= 0.0 || (kind == SIM_VINES && int(UV.y) % 2 == 1))) { show = false; }
	// the bean gardens fenced, on three or four sides
	int side = int(UV.y) / 16;
	if (fence && (kind != SIM_BEANS || sim_hash(cell + float(side) * 3.3 + 0.7) > 0.8)) { show = false; }
	float inner = size * (1.0 - 2.0 * SLAB_GAP);
	vec2 off; // from the parcel's middle, km
	bool turned = false; // turned a quarter round (not mirrored, which would turn the faces inside out)
	float y;  // above the ground, m
	along = 0.0;
	if (base) {
		off = VERTEX.xz * inner;
		y = VERTEX.y * slab;
	} else if (row) {
		float step = inner / crop_rows;
		off = vec2(VERTEX.x * inner * 0.97, (UV.x - 0.5) * inner + VERTEX.z * w * step);
		// clumps in staggered rows; rows of clumps run east-west, so their
		// fronts face the camera
		along = VERTEX.x * 0.97 + 0.5 + (int(UV.y) % 2 == 1 ? 0.5 / max(clumps, 1.0) : 0.0);
		turned = sim_crop_rows_ns(cell) && clumps == 0.0;
		y = slab + VERTEX.y * h;
	} else {
		// posts (UV.y % 16 their number) and one rail (15) on a side
		int n = int(UV.y) % 16;
		float post = 0.25 * km_per_m;
		vec2 a = n == 15 ? vec2(VERTEX.x * inner, VERTEX.z * post * 0.6)
			: vec2((float(n) / (FENCE_POSTS - 1.0) - 0.5) * inner + VERTEX.x * post, VERTEX.z * post);
		float edge = (side % 2 == 0 ? -0.5 : 0.5) * inner;
		off = vec2(a.x, edge + a.y);
		turned = side >= 2;
		y = n == 15 ? 0.45 + VERTEX.y * 0.2 : VERTEX.y * 1.0;
	}
	vec3 nrm = NORMAL;
	if (turned) {
		off = vec2(-off.y, off.x);
		nrm.xz = vec2(-nrm.z, nrm.x);
	}
	vec2 p = mid + off;
	vec4 k = tt_corners_cached(dot_tile(p));
	vec2 uv = fract((p - world_min) / tile_km);
	float level = mix(mix(k.x, k.y, uv.x), mix(k.w, k.z, uv.x), uv.y);
	vec3 world = vec3(p.x, level * level_h + y * km_per_m, p.y);
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	// flat faces: tops in the colour, sides a step darker (vertex alpha)
	colour = pow(base ? c : fence ? FENCE : rc, vec3(2.2)) * COLOR.a;
	art_light = normalize((VIEW_MATRIX * vec4(ART_LIGHT, 0.0)).xyz);
}

void fragment() {
	// the gaps between the clumps of a row
	if (clumps > 0.0 && fract(along * clumps) > 0.38) { discard; }
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
