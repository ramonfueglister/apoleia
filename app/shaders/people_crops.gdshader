// The fields up close, in the voxel style of the farmhouses (Urbek): every
// sown parcel is a raised slab, a little in from the parcel lines so grass
// edges and the village lanes run between the fields. Two looks, as in
// Urbek's farmland (gauntlet refs/urbek-landschaft-02, -05): dark tilled
// soil with green plants in rows, the soil showing between them, and a
// closed sheet of straw. Wheat and barley grow from bare soil through
// sparse sprouts to narrow lumpy green rows, ripen to a straw sheet and
// are cut to stubble; a fallow parcel lies as a sheet of dry stubble.
// Beans stand in rows of darker clumps, vines in low hedges on every other
// row; the fields next to a farmhouse are fenced, the others now and then
// fenced or hedged along a side; part of the pastures are paddocks, hedged
// or walled round. One instance per parcel of a square around the
// camera (people_dots.gd _update_crops); the parcel's state, crop and
// growth come from the same fine layer and rule as the field colours
// (sim_fields.gdshaderinc). The crop mesh (people_dots.gd _crop_mesh) holds
// unit boxes (x, z in -0.5..0.5, y 0..1): the slab (UV.x -1), the rows
// (UV.x the row's place across the parcel) with their lumps, the fence
// (UV.x -2) and the hedge (UV.x -4). The pasture parcels near the camera
// (not farmed, open land) carry a small flock of sheep instead (UV.x -3),
// and round their pasture block the balk on the hedge's boxes (round O).
shader_type spatial;
render_mode skip_vertex_transform, cull_back, diffuse_lambert, specular_disabled;

#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/sim_fields.gdshaderinc"
#include "res://shaders/people_crop_slab.gdshaderinc"

uniform vec2 crop_cell0;          // parcel index (from world_min) of the first parcel drawn
uniform int crop_nx = 40;         // parcels drawn per row: the rectangle of the square in view
uniform float crop_rows = 12.0;   // rows per parcel
uniform float km_per_m = 0.0238;  // diorama scale (TileTerrain.DIORAMA_KM_PER_M)

varying vec3 colour;
varying float along;  // 0..1 along a row of clumps or a fence side
varying float clumps; // clumps per row (0: a closed row)
varying float fill;   // share of a clump's length in its row
varying vec3 art_light; // ART_LIGHT in view space
varying vec2 slab_uv;   // place on the slab's top (-0.5..0.5), for its lit rim
varying float slab_top; // 1 on a slab's top face
varying float grains;   // how strongly a slab's top is speckled (straw more than soil)
varying vec2 ground;    // world km on the slab (the speckle runs on across a field's parcels)
varying flat int joined; // the slab's sides (bits -x, -y, +x, +y) that run on into its field (no lit lip there)
varying float vox;            // voxels along a row's ridge (-1 off the ridges)
varying flat float row_seed;  // the row's own dice, for its voxels
varying flat float gaps;      // share of the ridge's voxels missing
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)

// Colours (sRGB) after Urbek's farmland (gauntlet refs/urbek-landschaft-02):
// dark brown tilled soil, deep green rows darker than the meadow round
// them, pale straw grain.
const vec3 SOIL = vec3(0.34, 0.24, 0.18);
const vec3 SOIL_DRY = vec3(0.46, 0.34, 0.25);  // under the vines
const vec3 SPROUT = vec3(0.28, 0.5, 0.2);
const vec3 GRAIN_GREEN = vec3(0.2, 0.43, 0.15);  // Urbek's young crops #5ca040 lit, #2c6424 in shade
const vec3 BARLEY_GREEN = vec3(0.32, 0.48, 0.18); // a little yellower than the wheat
const vec3 RIPE[2] = vec3[](vec3(0.68, 0.64, 0.36), vec3(0.72, 0.68, 0.46)); // wheat, barley (Urbek's wheat #c0c672 lit)
const vec3 FALLOW = vec3(0.62, 0.6, 0.32);       // dry stubble, Urbek's wheat #cdc373 lit: the warm yellow of the farmland
const vec3 STUBBLE = vec3(0.62, 0.54, 0.38);
const vec3 FURROW = vec3(0.26, 0.18, 0.13);      // the ridges of a ploughed field, darker than its soil
const vec3 LEAVES = vec3(0.2, 0.42, 0.17);
const vec3 VINE = vec3(0.24, 0.44, 0.18);
const vec3 VINE_BARE = vec3(0.42, 0.3, 0.2);
const vec3 FENCE = vec3(0.37, 0.255, 0.157);   // the farmhouse fence (farmhouse.gd FENCE)
const float FENCE_POSTS = 6.0;   // posts per side, about two metres apart
// Field edges: Varro (rust. 1.14) names the Roman enclosures as the living
// hedge, the wooden fence, the ditch with its bank and the built wall. A
// field's outside side is fenced at FENCE_SHARE (and always next to a
// farmhouse), hedged at HEDGE_SHARE, open otherwise: Urbek fences nearly every
// field, but a fence on every parcel read as clutter (Ramon on s3).
const float FENCE_SHARE = 0.3;
const float HEDGE_SHARE = 0.25;
const float HEDGE_BLOCKS = 5.0;  // blocks per side (people_dots.gd HEDGE_BLOCKS)
const vec3 HEDGE = vec3(0.16, 0.33, 0.14); // clipped box and thorn, darker than the crops' leaves
// Paddocks (round G): the open pastures were the largest flat green left
// against Urbek (rounds E and F). A block of 2 x 2 pasture parcels is at
// PADDOCK_SHARE hedged or walled round (Varro's living hedge or the built
// dry-stone wall, maceria), with one block of it left out as the gate; the
// sheep graze in and out of them as before.
const float PADDOCK_SHARE = 0.45;
const float PADDOCK_WALLS = 0.5;  // share of the paddocks walled, not hedged
const vec3 WALL_STONE = vec3(0.6, 0.56, 0.49); // grey limestone, below the house walls
const vec3 WOOL = vec3(0.84, 0.81, 0.74); // below the house walls (brighter it was the lightest thing in the land, r11)
const vec3 SHEEP_DARK = vec3(0.33, 0.27, 0.22); // face and legs
const float FLOCK_SHARE = 0.3;   // share of the pasture parcels with a flock: fewer, larger flocks (r11: confetti)
const vec2 SHEEP_SPACING = vec2(2.2, 1.4); // m between the spots of a flock's three by three grid
// Rows (round O, 31.10.2026, Ramon: «Beides: Reihen und Weiden»): Urbek's
// rows are long narrow ridges of small voxels with lumps on them and the
// soil showing between; ours stood as large smooth clumps in a regular
// grid, like bricks (at 3 km light green 53 % of the view against Urbek's
// 21 %, soil 6 % against 18 %). A row is now a low ridge the length of the
// field, its voxels (VOX_M) in two tones and now and then one missing, and
// it carries up to CROP_LUMPS lumps (people_dots.gd, UV.y the row + 16 x
// (lump + 1)) of two to four voxels, wider and twice as high, as many as
// the stage's share.
const float CROP_LUMPS = 6.0;
const float VOX_M = 0.35;
// The balk round a pasture block (round O, sim_map.gdshaderinc
// sim_pasture): low blocks of taller, darker grass from the parcel line
// BALK_M in, and a shrub now and then (SHRUB_SHARE of the blocks); the
// balks of two blocks side by side meet on the line as one.
const vec3 BALK = vec3(0.17, 0.32, 0.13);
const float BALK_M = 0.6;  // sim_map.gdshaderinc SIM_BALK_KM
const float SHRUB_SHARE = 0.18;

void vertex() {
	float size = tt_data_km() * 0.5; // a quarter tile up close, half a data tile
	vec2 cell = crop_cell0 + vec2(float(INSTANCE_ID % crop_nx), float(INSTANCE_ID / crop_nx));
	vec2 mid = world_min + (cell + 0.5) * size;
	// the parcel as people_parcels.gdshader worked it out, once for all its vertices
	int code = 0;
	float g = 0.0;
	float level = 0.0;
	bool near = sim_map_on && sim_view_km <= SIM_CROPS_KM && sim_parcel_baked(cell, code, g, level);
	int state = near ? code & SIM_P_STATE : 0;
	// fields lie only on open land outside the towns, as sim_fields, never
	// on a farmhouse's lot and only on flat tiles (a ramp shows their colour)
	bool open = (code & SIM_P_OPEN) != 0;
	bool sheep = UV.x == -3.0;
	bool show = sheep ? near && state == 0 && open && sim_hash(cell + 3.7) < FLOCK_SHARE
		: state >= 1 && open;
	int kind = sim_crop_kind(cell); // one crop per field (sim_strip), as the ground colour
	vec3 field = sim_strip(cell);
	bool along_y = field.z > 0.5;
	bool grain = kind == SIM_WHEAT || kind == SIM_BARLEY;
	// the slab: its height (m, people_crop_slab.gdshaderinc) and colour by crop and season
	float slab = crop_slab_m(state, kind, g);
	vec3 c = SOIL;
	// the rows on it: height (m), width (share of the row spacing), colour,
	// clumps per row (0: closed); their lumps' height, width and share, and
	// the share of the ridges' voxels missing
	float h = 0.0;
	float w = 0.0;
	vec3 rc = LEAVES;
	clumps = 0.0;
	fill = 0.38;
	float lh = 0.0;
	float lw = 0.0;
	float lumps = 0.0;
	vox = -1.0;
	row_seed = 0.0;
	gaps = 0.0;
	// Urbek's rows run the length of the field as narrow lumpy ridges,
	// high enough to throw a shadow on the soil (29.10.: our sprouts in
	// short clumps read as a grid of dots; s4: low fine dashes flickered as
	// a moire over a large field; round O: bold dashes read as bricks); a
	// ploughed field shows its furrows
	if (state == 1) {
		// a flat sheet as Urbek's, high enough to show its edge (dark tufts
		// on it read as ticks, round 16; light sheaves as studs, round 18)
		c = FALLOW;
		kind = -1;
	} else if (grain) {
		if (g <= 0.0) { c = STUBBLE; h = 0.1; w = 0.35; rc = STUBBLE * 0.85; }
		else if (g < 0.12) { h = 0.12; w = 0.5; rc = FURROW; }
		else if (g < 0.4) { h = 0.2; w = 0.3; rc = SPROUT; lh = 0.35; lw = 0.45; lumps = 0.35; gaps = 0.12; }
		else if (g < 0.75) {
			h = 0.35; w = 0.35; rc = kind == SIM_WHEAT ? GRAIN_GREEN : BARLEY_GREEN;
			lh = 0.7; lw = 0.5; lumps = 0.5; gaps = 0.03;
		} else {
			c = RIPE[kind];
			// the ears stand in light rows on the sheet (a bare sheet read as
			// an empty tray, rounds 17 and 20)
			h = 0.2; w = 0.4; rc = mix(RIPE[kind], vec3(1.0, 0.95, 0.7), 0.3);
			lh = 0.35; lw = 0.6; lumps = 0.5; gaps = 0.03;
		}
	} else if (kind == SIM_BEANS) {
		if (g < 0.12) { h = 0.12; w = 0.5; rc = FURROW; }
		else if (g < 0.4) { h = 0.2; w = 0.3; rc = SPROUT; lh = 0.35; lw = 0.45; lumps = 0.35; gaps = 0.12; }
		else {
			// beans bushier than the grain: lumps on most of the row
			h = 0.35; w = 0.35; rc = g < 0.75 ? LEAVES : mix(LEAVES, RIPE[0], 0.3);
			lh = 0.7; lw = 0.55; lumps = 0.65; gaps = 0.05;
		}
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
	bool hedge = UV.x == -4.0;
	bool row = UV.x >= 0.0;
	int row_i = int(UV.y) % 16;    // the row's number
	int lump = int(UV.y) / 16 - 1; // its lump's, -1 the ridge
	if (row && (h <= 0.0 || (kind == SIM_VINES && row_i % 2 == 1))) { show = false; }
	// the fields next to a farmhouse lot fenced all round, further out a
	// fence or a hedge along a side now and then, as Urbek's farmland
	int side = int(UV.y) / 16;
	vec2 block2 = floor(cell / 2.0); // the paddock's block
	bool walled = false;
	bool balk = false;
	if (hedge && near && state == 0 && open) {
		// a paddock: all four parcels of its block pasture, its ring the
		// sides of each parcel on the block's edge (the sides are -y, +y,
		// +x, -x), less the gate
		bool paddock = sim_hash(block2 * 1.73 + 0.37) < PADDOCK_SHARE;
		for (int i = 0; i < 4; i++) {
			int c2;
			float g2;
			float l2;
			paddock = paddock && sim_parcel_baked(block2 * 2.0 + vec2(float(i % 2), float(i / 2)), c2, g2, l2)
				&& (c2 & SIM_P_STATE) == 0 && (c2 & SIM_P_OPEN) != 0;
		}
		vec2 odd = mod(cell, 2.0);
		bool rim = side == 0 ? odd.y < 0.5 : side == 1 ? odd.y > 0.5 : side == 2 ? odd.x > 0.5 : odd.x < 0.5;
		int gate = int(sim_hash(block2 * 4.13 + 1.9) * 4.0);
		bool gap = side == gate && abs((side < 2 ? odd.x : odd.y) - step(0.5, sim_hash(block2 * 6.7 + 2.3))) < 0.5
			&& int(UV.y) % 16 == 2;
		show = paddock && rim && !gap;
		walled = sim_hash(block2 * 2.91 + 5.1) < PADDOCK_WALLS;
		// round O: outside a paddock the farms' pasture has its balk on the
		// sides where its block ends (people_parcels.gdshader joins)
		int bit = side == 0 ? 2 : side == 1 ? 8 : side == 2 ? 4 : 1;
		balk = !paddock && (code & SIM_P_FARMED) != 0 && ((code / SIM_P_JOIN) & bit) == 0;
		show = show || balk;
	} else if (fence || hedge) {
		// only round a field's outside (the join bits -x, -y, +x, +y), by
		// one draw per side of the field, so a side is fenced or hedged
		// along all its parcels
		int bit = side == 0 ? 2 : side == 1 ? 8 : side == 2 ? 4 : 1;
		bool outside = ((code / SIM_P_JOIN) & bit) == 0;
		bool by_farm = (code & SIM_P_BY_FARM) != 0;
		float r = sim_hash(field.xy * 1.31 + field.z * 3.3 + float(side) * 7.7);
		show = show && outside && (fence ? state == 2 && (by_farm || r < FENCE_SHARE)
			: !by_farm && r >= FENCE_SHARE && r < FENCE_SHARE + HEDGE_SHARE);
	}
	float inner = size * (1.0 - 2.0 * SLAB_GAP);
	vec2 off; // from the parcel's middle, km
	int quarter = 0; // turned so many quarters round (never mirrored, which would turn the faces inside out)
	float y;  // above the ground, m
	along = 0.0;
	slab_uv = VERTEX.xz;
	slab_top = base && NORMAL.y > 0.5 ? 1.0 : 0.0;
	grains = state == 1 || (grain && g >= 0.75) ? 0.14 : 0.08;
	joined = code / SIM_P_JOIN;
	if (base) {
		off = VERTEX.xz * inner;
		y = VERTEX.y * slab;
	} else if (row) {
		float step = inner / crop_rows;
		float len = inner * 0.97; // a row's length, km
		row_seed = sim_hash(cell * 1.91 + float(row_i) * 0.37);
		if (lump < 0) {
			// the ridge
			off = vec2(VERTEX.x * len, (UV.x - 0.5) * inner + VERTEX.z * w * step);
			// clumps (the vines) along the field, each row shifted by its own
			// amount (a strict stagger drew a checker), so they run on from
			// parcel to parcel (the camera looks along the diagonal, so
			// either way reads alike)
			along = VERTEX.x * 0.97 + 0.5 + sim_hash(vec2(float(row_i), 2.3)) / max(clumps, 1.0);
			vox = (VERTEX.x + 0.5) * len / (VOX_M * km_per_m);
			y = slab + VERTEX.y * h;
		} else {
			// a lump of two to four voxels in its own slot along the row,
			// shifted in it by its own amount, a shade darker or lighter
			float r = sim_hash(cell * 2.63 + vec2(float(row_i) * 0.71, float(lump) * 1.37));
			if (r >= lumps) { show = false; }
			float slot = len / CROP_LUMPS;
			float l = min((2.0 + floor(sim_hash(cell * 1.17 + vec2(float(lump) * 3.1, float(row_i) * 0.53)) * 3.0)) * VOX_M * km_per_m, slot * 0.9);
			float at = (float(lump) + 0.5) * slot - 0.5 * len + (sim_hash(cell * 0.83 + vec2(float(row_i) * 1.9, float(lump) * 0.29)) - 0.5) * (slot - l);
			off = vec2(at + VERTEX.x * l, (UV.x - 0.5) * inner + VERTEX.z * lw * step);
			y = slab + VERTEX.y * lh;
			rc *= r < lumps * 0.5 ? 0.94 : 1.04;
		}
		quarter = along_y ? 1 : 0;
	} else if (sheep) {
		// sheep k (UV.y / 4) of the flock, part UV.y % 4: body, legs, head;
		// six to nine of them on their own spots of a loose three by three
		// grid about the flock's middle, so none stands in another (r11),
		// each turned its way
		int k = int(UV.y) / 4;
		int part = int(UV.y) % 4;
		if (float(k) >= 6.0 + 4.0 * sim_hash(cell + 8.1)) { show = false; }
		vec2 middle = (vec2(sim_hash(cell + 1.3), sim_hash(cell + 2.9)) - 0.5) * 0.5 * inner;
		int spot = (k + int(sim_hash(cell + 6.6) * 9.0)) % 9;
		vec2 jitter = vec2(sim_hash(cell + float(k) * 1.7), sim_hash(cell + float(k) * 2.3 + 0.5)) - 0.5;
		vec2 at = middle + (vec2(float(spot % 3), float(spot / 3)) - 1.0 + jitter * 0.3) * SHEEP_SPACING * km_per_m;
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
	} else if (hedge && balk) {
		// the balk: blocks of taller grass over the parcel's side from its
		// line BALK_M in, each a little higher or deeper than the next, now
		// and then a shrub
		int n = int(UV.y) % 16;
		float block = size / HEDGE_BLOCKS;
		float r1 = sim_hash(cell * 2.17 + float(UV.y) * 0.61);
		float r2 = sim_hash(cell * 3.31 + float(UV.y) * 0.37);
		bool shrub = r1 < SHRUB_SHARE;
		float depth = (shrub ? 0.5 + 0.3 * r2 : BALK_M * (0.8 + 0.4 * r2)) * km_per_m;
		float len = shrub ? (0.6 + 0.4 * r2) * km_per_m : block * 1.02;
		vec2 a = vec2((float(n) + 0.5) * block - 0.5 * size + VERTEX.x * len, VERTEX.z * depth);
		float edge = (side % 2 == 0 ? -1.0 : 1.0) * (0.5 * size - 0.5 * depth);
		off = vec2(a.x, edge + a.y);
		quarter = side >= 2 ? 1 : 0;
		y = VERTEX.y * (shrub ? 0.5 + 0.3 * r2 : 0.12 + 0.12 * r2);
		c = shrub ? HEDGE * (0.9 + 0.2 * r1) : BALK * (0.92 + 0.16 * r2);
	} else if (hedge) {
		// a clipped hedge on the field's edge: blocks of about two metres,
		// each a little higher or deeper than the next, so it reads as
		// voxels and not as a wall; a paddock's dry-stone wall lower and
		// thinner, its stones in lighter and darker greys
		int n = int(UV.y) % 16;
		float block = inner / HEDGE_BLOCKS;
		float r1 = sim_hash(cell * 2.17 + float(UV.y) * 0.61);
		float r2 = sim_hash(cell * 3.31 + float(UV.y) * 0.37);
		float depth = (walled ? 0.45 + 0.1 * r1 : 0.55 + 0.25 * r1) * km_per_m;
		vec2 a = vec2((float(n) + 0.5) * block - 0.5 * inner + VERTEX.x * block * 1.02, VERTEX.z * depth);
		float edge = (side % 2 == 0 ? -0.5 : 0.5) * inner;
		off = vec2(a.x, edge + a.y);
		quarter = side >= 2 ? 1 : 0;
		y = VERTEX.y * (walled ? 0.7 + 0.2 * r2 : 0.85 + 0.35 * r2);
		c = walled ? WALL_STONE * (0.88 + 0.24 * r1) : HEDGE * (0.92 + 0.16 * r1);
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
	// the slab, its rows and fence fitted into the parcel's slab (clear of
	// lanes); a pasture's join bits are its block's (people_parcels.gdshader),
	// not a slab's
	if (!sheep) {
		vec4 box = crop_box_of((code / SIM_P_LANES) & 31, state == 0 ? code % SIM_P_JOIN : code, size);
		off = (box.xy + box.zw) * 0.5 + off * (box.zw - box.xy) / inner;
	}
	vec2 p = mid + off;
	ground = p;
	// the parcel lies flat (crop_open), at the level of its middle
	vec3 world = vec3(p.x, level * level_h + y * km_per_m, p.y);
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	// flat faces: tops in the colour, sides a step darker (vertex alpha)
	colour = pow(base || sheep || hedge ? c : fence ? FENCE : rc, vec3(2.2)) * COLOR.a;
	art_light = normalize((VIEW_MATRIX * vec4(ART_LIGHT, 0.0)).xyz);
}

void fragment() {
	// the gaps between the clumps of a row
	if (clumps > 0.0 && fract(along * clumps) > fill) { discard; }
	ALBEDO = colour;
	// a ridge's voxels in two tones, now and then one missing, while they
	// are over a pixel or so (round O)
	if (vox >= 0.0) {
		float v = floor(vox);
		float r = fract(sin(dot(vec2(v, row_seed * 97.0), vec2(12.9898, 78.233))) * 43758.5453);
		float big = 1.0 - smoothstep(0.35, 0.7, fwidth(vox));
		if (r < gaps && big > 0.5) { discard; }
		ALBEDO *= mix(1.0, r < 0.5 ? 0.9 : 1.03, big);
	}
	// a lit lip of a pixel or two round the top of a slab, as the bevel of
	// Urbek's field plates, so a sheet of straw reads as a raised plate
	if (slab_top > 0.5) {
		vec2 e = 0.5 - abs(slab_uv);
		vec2 px = fwidth(slab_uv) * 1.5;
		// only round the field, not where its parcels join
		bool lip_x = e.x < px.x && (joined & (slab_uv.x < 0.0 ? 1 : 4)) == 0;
		bool lip_y = e.y < px.y && (joined & (slab_uv.y < 0.0 ? 2 : 8)) == 0;
		if (lip_x || lip_y) { ALBEDO *= 1.25; }
		// a fine speckle of voxels on the top, as the grain of Urbek's
		// straw plates (a flat tone read as a plastic tray), gone before it
		// would shimmer
		vec2 g = mod(ground / (km_per_m * 0.25), 4096.0); // voxels of a quarter metre
		float n = fract(sin(dot(floor(g), vec2(12.9898, 78.233))) * 43758.5453);
		ALBEDO *= 1.0 + (n - 0.5) * grains * (1.0 - smoothstep(0.25, 0.5, length(fwidth(g))));
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
