// The fields up close, in the voxel style of the farmhouses (Urbek): every
// sown parcel is a raised slab, a little in from the parcel lines so grass
// edges and the village lanes run between the fields. Two looks, as in
// Urbek's farmland (gauntlet refs/urbek-landschaft-02, -05): dark tilled
// soil with green plants in rows, the soil showing between them, and a
// closed sheet of straw. Wheat and barley grow from bare soil through
// sparse sprouts to narrow lumpy green rows, ripen to a straw sheet and
// are cut to stubble; a fallow parcel lies as a sheet of dry stubble.
// Beans stand in rows of darker clumps, vines in low hedges on every other
// row; the fields next to a farmhouse are fenced. One instance per parcel of a square around the
// camera (people_dots.gd _update_crops); the parcel's state, crop and
// growth come from the same fine layer and rule as the field colours
// (sim_fields.gdshaderinc). The crop mesh (people_dots.gd _crop_mesh) holds
// unit boxes (x, z in -0.5..0.5, y 0..1): the slab (UV.x -1), the rows
// (UV.x the row's place across the parcel) and the fence (UV.x -2). The
// pasture parcels near the camera (not farmed, open land) carry a small
// flock of sheep instead (UV.x -3).
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/sim_fields.gdshaderinc"
#include "res://shaders/people_crop_slab.gdshaderinc"

uniform vec2 crop_cell0;          // parcel index (from world_min) of the square's first parcel
uniform int crop_n = 48;          // parcels per side of the square
uniform float crop_rows = 12.0;   // rows per parcel
uniform float km_per_m = 0.0238;  // diorama scale (TileTerrain.DIORAMA_KM_PER_M)

varying vec3 colour;
varying float along;  // 0..1 along a row of clumps or a fence side
varying float clumps; // clumps per row (0: a closed row)
varying float fill;   // share of a clump's length in its row
varying vec3 art_light; // ART_LIGHT in view space
varying vec2 slab_uv;   // place on the slab's top (-0.5..0.5), for its lit rim
varying float slab_top; // 1 on a slab's top face
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)

// Colours (sRGB) after Urbek's farmland (gauntlet refs/urbek-landschaft-02):
// dark brown tilled soil, deep green rows darker than the meadow round
// them, pale straw grain.
const vec3 SOIL = vec3(0.34, 0.24, 0.18);
const vec3 SOIL_DRY = vec3(0.46, 0.34, 0.25);  // under the vines
const vec3 SPROUT = vec3(0.32, 0.52, 0.22);
const vec3 GRAIN_GREEN = vec3(0.24, 0.45, 0.17);  // Urbek's young crops #3f7d2c-#559a3e lit
const vec3 BARLEY_GREEN = vec3(0.32, 0.48, 0.18); // a little yellower than the wheat
const vec3 RIPE[2] = vec3[](vec3(0.68, 0.64, 0.36), vec3(0.72, 0.68, 0.46)); // wheat, barley (Urbek's wheat #c0c672 lit)
const vec3 FALLOW = vec3(0.62, 0.6, 0.32);       // dry stubble, Urbek's wheat #cdc373 lit: the warm yellow of the farmland
const vec3 STUBBLE = vec3(0.62, 0.54, 0.38);
const vec3 LEAVES = vec3(0.2, 0.42, 0.17);
const vec3 VINE = vec3(0.24, 0.44, 0.18);
const vec3 VINE_BARE = vec3(0.42, 0.3, 0.2);
const vec3 FENCE = vec3(0.37, 0.255, 0.157);   // the farmhouse fence (farmhouse.gd FENCE)
const float FENCE_POSTS = 6.0;   // posts per side, about two metres apart
const vec3 WOOL = vec3(0.9, 0.87, 0.78);
const vec3 SHEEP_DARK = vec3(0.27, 0.22, 0.18); // face and legs
const float FLOCK_SHARE = 0.55;   // share of the pasture parcels with a flock

void vertex() {
	float size = tt_data_km() * 0.5; // a quarter tile up close, half a data tile
	vec2 cell = crop_cell0 + vec2(float(INSTANCE_ID % crop_n), float(INSTANCE_ID / crop_n));
	vec2 mid = world_min + (cell + 0.5) * size;
	vec4 f = vec4(0.0);
	int state = sim_map_on && sim_view_km <= SIM_CROPS_KM ? sim_parcel(cell, size, f) : 0;
	// fields lie only on open land outside the towns, as sim_fields, never
	// on a farmhouse's lot and only on flat tiles (a ramp shows their colour)
	bool open = crop_open(mid);
	bool near = sim_map_on && sim_view_km <= SIM_CROPS_KM;
	bool sheep = UV.x == -3.0;
	bool show = sheep ? near && state == 0 && open && sim_hash(cell + 3.7) < FLOCK_SHARE
		: state >= 1 && open;
	float g = f.b;
	int kind = sim_crop_kind(cell); // one crop per parcel, as the ground colour
	bool grain = kind == SIM_WHEAT || kind == SIM_BARLEY;
	// the slab: its height (m, people_crop_slab.gdshaderinc) and colour by crop and season
	float slab = crop_slab_m(state, kind, g);
	vec3 c = SOIL;
	// the rows on it: height (m), width (share of the row spacing), colour,
	// clumps per row (0: closed)
	float h = 0.0;
	float w = 0.0;
	vec3 rc = LEAVES;
	clumps = 0.0;
	fill = 0.38;
	if (state == 1) {
		// a flat sheet as Urbek's, high enough to show its edge (dark tufts
		// on it read as ticks, round 16; light sheaves as studs, round 18)
		c = FALLOW;
		kind = -1;
	} else if (grain) {
		if (g <= 0.0) { c = STUBBLE; }
		else if (g < 0.12) { }
		else if (g < 0.4) { h = 0.15; w = 0.3; rc = SPROUT; clumps = 16.0; fill = 0.35; }
		else if (g < 0.75) { h = 0.35; w = 0.4; rc = kind == SIM_WHEAT ? GRAIN_GREEN : BARLEY_GREEN; clumps = 24.0; fill = 0.8; }
		else {
			c = RIPE[kind];
			// on half the ripe fields the ears stand in light clumps
			if (sim_hash(cell + 6.2) < 0.5) { h = 0.3; w = 0.5; rc = mix(RIPE[kind], vec3(1.0, 0.95, 0.7), 0.3); clumps = 14.0; fill = 0.5; }
		}
	} else if (kind == SIM_BEANS) {
		if (g < 0.12) { }
		else if (g < 0.4) { h = 0.15; w = 0.3; rc = SPROUT; clumps = 12.0; fill = 0.35; }
		else { h = 0.45; w = 0.45; rc = g < 0.75 ? LEAVES : mix(LEAVES, RIPE[0], 0.3); clumps = 12.0; fill = 0.75; }
	} else if (kind == SIM_VINES) {
		// vines stand the year round, every other row of plants, bare in winter
		c = SOIL_DRY;
		h = g < 0.12 ? 0.6 : 0.8;
		w = 0.5;
		rc = g < 0.12 ? VINE_BARE : VINE;
		clumps = 8.0;
		fill = 0.75;
	}
	bool base = UV.x == -1.0;
	bool fence = UV.x == -2.0;
	bool row = UV.x >= 0.0;
	if (row && (h <= 0.0 || (kind == SIM_VINES && int(UV.y) % 2 == 1))) { show = false; }
	// the fields next to a farmhouse lot fenced all round, none further out
	int side = int(UV.y) / 16;
	if (fence) {
		bool by_farm = false;
		for (int k = 0; k < 9; k++) {
			by_farm = by_farm || (k != 4 && sim_house_lot(mid + vec2(float(k % 3 - 1), float(k / 3 - 1)) * size));
		}
		show = show && state == 2 && by_farm;
	}
	float inner = size * (1.0 - 2.0 * SLAB_GAP);
	vec2 off; // from the parcel's middle, km
	int quarter = 0; // turned so many quarters round (never mirrored, which would turn the faces inside out)
	float y;  // above the ground, m
	along = 0.0;
	slab_uv = VERTEX.xz;
	slab_top = base && NORMAL.y > 0.5 ? 1.0 : 0.0;
	if (base) {
		off = VERTEX.xz * inner;
		y = VERTEX.y * slab;
	} else if (row) {
		float step = inner / crop_rows;
		off = vec2(VERTEX.x * inner * 0.97, (UV.x - 0.5) * inner + VERTEX.z * w * step);
		// clumps in staggered rows; the beans' and vines' rows run
		// east-west, so their fronts face the camera; the grain's run
		// north-south, away from the camera, as lumpy lines with the soil
		// between them (east-west their stacked fronts read as blinds)
		along = VERTEX.x * 0.97 + 0.5 + (int(UV.y) % 2 == 1 ? 0.5 / max(clumps, 1.0) : 0.0);
		quarter = grain ? 1 : 0;
		y = slab + VERTEX.y * h;
	} else if (sheep) {
		// sheep k (UV.y / 4) of the flock, part UV.y % 4: body, legs, head;
		// four to eight of them about the flock's middle, each turned its way
		int k = int(UV.y) / 4;
		int part = int(UV.y) % 4;
		if (float(k) >= 4.0 + 5.0 * sim_hash(cell + 8.1)) { show = false; }
		vec2 middle = (vec2(sim_hash(cell + 1.3), sim_hash(cell + 2.9)) - 0.5) * 0.3 * inner;
		vec2 at = middle + (vec2(sim_hash(cell + float(k) * 1.7), sim_hash(cell + float(k) * 2.3 + 0.5)) - 0.5) * 0.4 * inner;
		// a long low body on short dark legs, the head at one end, half as
		// tall as a person
		vec3 half_m = part == 0 ? vec3(0.55, 0.21, 0.28) : part == 1 ? vec3(0.42, 0.15, 0.16) : vec3(0.15, 0.14, 0.12);
		vec3 mid_m = part == 0 ? vec3(0.0, 0.5, 0.0) : part == 1 ? vec3(0.0, 0.15, 0.0) : vec3(0.64, 0.66, 0.0);
		vec3 v = (mid_m + (VERTEX - vec3(0.0, 0.5, 0.0)) * 2.0 * half_m) * km_per_m;
		// facing east or west: the long side to the camera (end on, a sheep
		// reads as an upright box)
		quarter = sim_hash(cell + float(k) * 3.1) < 0.5 ? 0 : 2;
		off = v.xz;
		mid = at + mid; // the sheep's place; the quarter turn below is about its own middle
		y = v.y / km_per_m;
		c = part == 0 ? WOOL : SHEEP_DARK;
	} else {
		// posts (UV.y % 16 their number) and one rail (15) on a side
		int n = int(UV.y) % 16;
		float post = 0.25 * km_per_m;
		vec2 a = n == 15 ? vec2(VERTEX.x * inner, VERTEX.z * post * 0.6)
			: vec2((float(n) / (FENCE_POSTS - 1.0) - 0.5) * inner + VERTEX.x * post, VERTEX.z * post);
		float edge = (side % 2 == 0 ? -0.5 : 0.5) * inner;
		off = vec2(a.x, edge + a.y);
		quarter = side >= 2 ? 1 : 0;
		y = n == 15 ? 0.45 + VERTEX.y * 0.2 : VERTEX.y * 1.0;
	}
	vec3 nrm = NORMAL;
	for (int i = 0; i < quarter; i++) {
		off = vec2(-off.y, off.x);
		nrm.xz = vec2(-nrm.z, nrm.x);
	}
	// the slab, its rows and fence fitted into the parcel's slab (clear of lanes)
	if (!sheep) {
		vec4 box = crop_box(cell, size);
		off = (box.xy + box.zw) * 0.5 + off * (box.zw - box.xy) / inner;
	}
	vec2 p = mid + off;
	float level = dot_ground_level(p);
	vec3 world = vec3(p.x, level * level_h + y * km_per_m, p.y);
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	// flat faces: tops in the colour, sides a step darker (vertex alpha)
	colour = pow(base || sheep ? c : fence ? FENCE : rc, vec3(2.2)) * COLOR.a;
	art_light = normalize((VIEW_MATRIX * vec4(ART_LIGHT, 0.0)).xyz);
}

void fragment() {
	// the gaps between the clumps of a row
	if (clumps > 0.0 && fract(along * clumps) > fill) { discard; }
	ALBEDO = colour;
	// a lit lip of a pixel or two round the top of a slab, as the bevel of
	// Urbek's field plates, so a sheet of straw reads as a raised plate
	if (slab_top > 0.5) {
		vec2 e = 0.5 - abs(slab_uv);
		vec2 px = fwidth(slab_uv) * 1.5;
		if (e.x < px.x || e.y < px.y) { ALBEDO *= 1.25; }
	}
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
