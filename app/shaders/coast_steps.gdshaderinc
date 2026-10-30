// Steps of the shore (graphics round H, 30.10.2026). Up close (the 0.5 km
// and the quarter tiles) the coast is drawn in voxel blocks, CS_CELLS
// columns of about COAST_CELL_KM per data tile side. On a sea tile in front
// of open land: where the coast wanders low a rock headland at the land's
// own edge level juts out up to three cells, and in front of it, all along,
// a sand ledge half way down to the water, one to three cells deep. On a
// coast cut (the 45-degree coast) the same in front of a staircase that
// fills the half cells along the diagonal, so the diagonal becomes a voxel
// stair. So the bank comes down in steps, as Urbek's, and the waterline goes
// in and out instead of along the tile edges and diagonals.
// tile_coast_steps.gdshader draws the blocks on the tiles that TileTerrain
// lists (_update_coast_list, the same rules as cs_open and cs_cut_tip);
// tile_terrain.gdshader lays the sand at their foot, the surf and the
// shallows in front of them, and no beach behind a headland.
// Needs tile_terrain.gdshaderinc. Everything here is on the 0.5 km data tiles.

// the voxel cell of the coast (1.3 diorama metres) and how far along the
// coast its width wanders from a cove to a headland (tile_terrain.gdshader)
const float COAST_CELL_KM = 0.031;
const float COAST_BAY_KM = 0.15;
const int CS_CELLS = 16; // columns per data tile side (31 m)
const ivec2 CS_CORNER[4] = ivec2[](ivec2(0, 0), ivec2(1, 0), ivec2(1, 1), ivec2(0, 1));
const ivec2 CS_SIDE[4] = ivec2[](ivec2(0, -1), ivec2(1, 0), ivec2(0, 1), ivec2(-1, 0));
// the data tiles that have steps (the prop patch up close; none further out)
uniform ivec2 steps_lo = ivec2(0);
uniform ivec2 steps_hi = ivec2(-1);

int cs_water(ivec2 t) {
	return tt_data_cell(t) & 3;
}

// Data tile t is open land up to the sea: land, not a town (its quay), not
// a coast cut (its 45-degree edge) and not a lone tile in the sea.
bool cs_open(ivec2 t) {
	int cell = tt_data_cell(t);
	if ((cell & 3) != W_LAND || cell >= 8) { return false; }
	int nb[4];
	bool lone = true;
	for (int k = 0; k < 4; k++) {
		nb[k] = tt_data_cell(t + CS_SIDE[k]);
		lone = lone && (nb[k] & 3) == W_SEA;
	}
	if (lone) { return false; }
	// tt_coast_cut_nb, on the data tiles
	for (int k = 0; k < 4; k++) {
		int a = nb[k] & 3;
		bool wet = (a == W_SEA || a == W_LAKE) && (nb[(k + 1) & 3] & 3) == a;
		bool rest_dry = (nb[(k + 2) & 3] & 3) != a && (nb[(k + 3) & 3] & 3) != a;
		if (wet && rest_dry && cs_water(t + CS_SIDE[k] + CS_SIDE[(k + 1) & 3]) == a) { return false; }
	}
	return true;
}

// Side k of sea data tile s: 0 without steps, else 1, + 2 where the land
// ends at the side's first corner (CS_CORNER[k]), + 4 at its last: there the
// steps come down to it in a 45-degree stair. Where the coast turns round
// that corner of the sea tile (open land on the next side too) they go on.
int cs_side(ivec2 s, int k) {
	if (any(lessThan(s, steps_lo)) || any(greaterThan(s, steps_hi))) { return 0; }
	if (cs_water(s) != W_SEA || !cs_open(s + CS_SIDE[k])) { return 0; }
	ivec2 e = CS_SIDE[(k + 1) & 3]; // along the side, from its first corner
	int bits = 1;
	if (!cs_open(s + CS_SIDE[k] - e) && !cs_open(s - e)) { bits |= 2; }
	if (!cs_open(s + CS_SIDE[k] + e) && !cs_open(s + e)) { bits |= 4; }
	return bits;
}

// How far the coast has wandered (0..1) at column col of side k of sea tile
// s, taken on the edge, so a column is the same all the way out.
float cs_wander(ivec2 s, int k, int col) {
	vec2 a = vec2(CS_CORNER[k]);
	vec2 e = vec2(CS_CORNER[(k + 1) & 3]) - a;
	vec2 q = world_min + (vec2(s) + a + e * ((float(col) + 0.5) / float(CS_CELLS))) * tt_data_km();
	return tt_noise(q / COAST_BAY_KM);
}

// Cells of rock headland where the coast has wandered to w (0 to 3), and of
// sand ledge in front of it (1 to 3, the most in the coves).
int cs_head(float w) {
	return int(max(0.0, 0.42 - w) * 9.0);
}

int cs_ledge(float w) {
	return 1 + min(int(w * 2.5), 2);
}

// Cells out from the edge at column col of side k (`bits` from cs_side):
// x the headland at the land's level, y the ledge below it (0: none).
ivec2 cs_depth(ivec2 s, int k, int col, int bits) {
	if ((bits & 1) == 0) { return ivec2(0); }
	float w = cs_wander(s, k, col);
	int head = cs_head(w);
	int ledge = head + cs_ledge(w);
	if ((bits & 2) != 0) { head = min(head, col); ledge = min(ledge, col + 1); }
	if ((bits & 4) != 0) { head = min(head, CS_CELLS - 1 - col); ledge = min(ledge, CS_CELLS - col); }
	return ivec2(head, ledge);
}

// Column under `uv` (data tile units of sea tile s) on side k.
int cs_column(int k, vec2 uv) {
	vec2 a = vec2(CS_CORNER[k]);
	vec2 e = vec2(CS_CORNER[(k + 1) & 3]) - a;
	return clamp(int(floor(dot(uv - a, e) * float(CS_CELLS))), 0, CS_CELLS - 1);
}

// How far `uv` (data tile units of sea tile s) lies out from side k.
float cs_out(int k, vec2 uv) {
	return dot(uv - vec2(CS_CORNER[k]), -vec2(CS_SIDE[k]));
}

// Data tile units from the front of the steps at `uv` of sea tile s, over the
// sides in `steps` (3 bits each, cs_side), or 10.
float cs_front(ivec2 s, int steps, vec2 uv) {
	float d = 10.0;
	for (int k = 0; k < 4; k++) {
		int bits = (steps >> (3 * k)) & 7;
		if (bits != 0) {
			d = min(d, cs_out(k, uv) - float(cs_depth(s, k, cs_column(k, uv), bits).y) / float(CS_CELLS));
		}
	}
	return d;
}

// A headland stands in front of `uv` (data tile units of land tile t) within
// `reach` of the edge, on one of the sides in `steps` (cs_side of the sea
// tile across each side of t, on its side back to t).
bool cs_headland(ivec2 t, int steps, vec2 uv, float reach) {
	for (int k = 0; k < 4; k++) {
		int bits = (steps >> (3 * k)) & 7;
		int ks = (k + 2) & 3;
		vec2 us = uv - vec2(CS_SIDE[k]); // in the sea tile
		if (bits != 0 && -cs_out(ks, us) < reach && cs_depth(t + CS_SIDE[k], ks, cs_column(ks, us), bits).x > 0) {
			return true;
		}
	}
	return false;
}

// ------------------------------------------------------------- coast cuts
// On a coast cut with its wet half at corner c the columns run along side c
// (from CS_CORNER[c]) and the blocks of column col stand from the diagonal
// ((CS_CELLS - col) cells in from side c) out towards side c: the first
// fills the half cell the diagonal cuts, at the land's edge level, so the
// columns make a staircase; then the headland and the ledge as on a side.
// The last columns stand out over the sea tile across side c, where the
// stair goes on into the next cut along the diagonal.

// Corner of the wet half of data tile t, a coast cut towards the sea of open
// land (land, not a town, its two wet sides and the diagonal between them
// sea), or -1.
int cs_cut_tip(ivec2 t) {
	int cell = tt_data_cell(t);
	if ((cell & 3) != W_LAND || cell >= 8) { return -1; }
	int nb[4];
	for (int k = 0; k < 4; k++) { nb[k] = tt_data_cell(t + CS_SIDE[k]) & 3; }
	for (int k = 0; k < 4; k++) {
		bool wet = nb[k] == W_SEA && nb[(k + 1) & 3] == W_SEA;
		bool rest_dry = nb[(k + 2) & 3] != W_SEA && nb[(k + 3) & 3] != W_SEA;
		if (wet && rest_dry && cs_water(t + CS_SIDE[k] + CS_SIDE[(k + 1) & 3]) == W_SEA) { return (k + 1) & 3; }
	}
	return -1;
}

// The cut of data tile t with its tip at c: 0 without steps, else 1, + 2
// where the stair ends at the diagonal's first end (CS_CORNER[c + 3], column
// 0), + 4 at its last (CS_CORNER[c + 1]), as cs_side.
int cs_cut_bits(ivec2 t, int c) {
	if (any(lessThan(t, steps_lo)) || any(greaterThan(t, steps_hi)) || cs_cut_tip(t) != c) { return 0; }
	int bits = 1;
	if (cs_cut_tip(t + CS_SIDE[(c + 3) & 3] + CS_SIDE[(c + 2) & 3]) != c) { bits |= 2; }
	if (cs_cut_tip(t + CS_SIDE[c] + CS_SIDE[(c + 1) & 3]) != c) { bits |= 4; }
	return bits;
}

// Cells of column col out from the diagonal of cut t (tip c, `bits` from
// cs_cut_bits): x the staircase and headland at the land's level, y the
// ledge (0: none).
ivec2 cs_depth_cut(ivec2 t, int c, int col, int bits) {
	if ((bits & 1) == 0) { return ivec2(0); }
	vec2 a = vec2(CS_CORNER[c]);
	vec2 e = vec2(CS_CORNER[(c + 1) & 3]) - a;
	float n = float(CS_CELLS);
	vec2 uv = a + e * ((float(col) + 0.5) / n) - vec2(CS_SIDE[c]) * ((n - 0.5 - float(col)) / n);
	float w = tt_noise((world_min + (vec2(t) + uv) * tt_data_km()) / COAST_BAY_KM);
	int head = 1 + cs_head(w);
	int ledge = head + cs_ledge(w);
	// a stair that ends: only its fill and one ledge cell at the end
	if ((bits & 2) != 0) { head = min(head, 1 + col); ledge = min(ledge, 2 + col); }
	if ((bits & 4) != 0) { head = min(head, CS_CELLS - col); ledge = min(ledge, CS_CELLS + 1 - col); }
	return ivec2(head, ledge);
}

// Data tile units from the front of the stair of cut t (tip c) at `uv` (its
// data tile units), across the diagonal (the front of column col lies
// where along + out = (CS_CELLS - ledge) cells).
float cs_front_cut(ivec2 t, int c, int bits, vec2 uv) {
	vec2 a = vec2(CS_CORNER[c]);
	vec2 e = vec2(CS_CORNER[(c + 1) & 3]) - a;
	float along = dot(uv - a, e);
	int col = clamp(int(floor(along * float(CS_CELLS))), 0, CS_CELLS - 1);
	float front = float(CS_CELLS - cs_depth_cut(t, c, col, bits).y) / float(CS_CELLS);
	return (front - along - cs_out(c, uv)) * 0.7071;
}

// The steps round data tile t for the tiles' colours, packed as in
// tile_terrain.gdshader's shore_sides from bit 16: on a cut its bits, its
// tip (bits 3-4) and bit 12; on a sea tile 3 bits per side (cs_side); on
// open land 3 bits per side for the sea tile across it (on its side back).
int cs_steps(ivec2 t) {
	int tip = cs_cut_tip(t);
	if (tip >= 0) {
		int bits = cs_cut_bits(t, tip);
		return bits == 0 ? 0 : bits | (tip << 3) | (1 << 12);
	}
	int steps = 0;
	bool sea = cs_water(t) == W_SEA;
	for (int k = 0; k < 4; k++) {
		if (sea) {
			steps |= cs_side(t, k) << (3 * k);
		} else if (cs_water(t + CS_SIDE[k]) == W_SEA) {
			steps |= cs_side(t + CS_SIDE[k], (k + 2) & 3) << (3 * k);
		}
	}
	return steps;
}

// Data tile units from the front of the steps at `uv` of data tile t, for
// `steps` from cs_steps, or 10.
float cs_steps_front(ivec2 t, int steps, vec2 uv) {
	if (steps == 0) { return 10.0; }
	if ((steps & 4096) != 0) { return cs_front_cut(t, (steps >> 3) & 3, steps & 7, uv); }
	return cs_water(t) == W_SEA ? cs_front(t, steps, uv) : 10.0;
}
