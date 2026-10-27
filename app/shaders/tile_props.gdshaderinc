// Where a tree or house slot stands (tile_props.gdshader). Shared by the
// per-frame placement pass (tile_prop_prep.gdshader) and, as a fallback, the
// prop vertex shader. Needs tile_terrain.gdshaderinc first.

// One slot of tile t: xy the spot in the tile (0..1), z its level, w the code:
// < 0 empty; trees kind + 0.25 * size (0.7..1); houses the town class.
vec4 tt_prop_place(ivec2 t, int slot, int slots, bool house) {
	float code = -1.0;
	int cell = tt_cell(t);
	int water = cell & 3;
	int town = cell >> 2;
	vec2 centre = tt_tile_center(t);
	float r0 = tt_hash3(vec3(vec2(t), float(slot) * 3.17));
	float r1 = tt_hash3(vec3(vec2(t) + 11.3, float(slot) * 1.91));
	float r2 = tt_hash3(vec3(vec2(t) - 4.7, float(slot) * 5.03));
	bool show = water == W_LAND;
	float edge_size = 1.0;
	vec2 uv;
	if (house) {
		// house blocks on the street grid of the town tile (house_grid^2 = slots)
		int side = int(ceil(sqrt(float(slots))));
		float share = town == 3 ? 1.0 : town == 2 ? 0.6 : town == 1 ? 0.15 : 0.0;
		int count = max(int(round(share * float(slots))), town > 0 ? 1 : 0);
		show = show && slot < count;
		int cell_k = town == 3 ? slot : (slot * 7 + int(tt_hash(vec2(t)) * float(slots))) % slots;
		vec2 sub = vec2(float(cell_k % side), float(cell_k / side));
		uv = (sub + 0.5) / float(side) + (vec2(r1, r2) - 0.5) * 0.03;
	} else {
		show = show && town == 0;
		uv = vec2(0.5);
	}
	if (!house && show) {
		// the costly part only for slots that can hold a tree
		vec4 cov = tt_cover(centre);
		float density = tt_tree_density(centre, cov.r);
		// single trees mostly where the wood thins out, few in open land
		float edge = smoothstep(0.0, 0.25, density) * (1.0 - smoothstep(0.5, 0.9, density));
		float lone = 0.015 + 0.10 * cov.g * 0.3 + 0.35 * edge;
		float n = floor(density * float(slots) + tt_hash(vec2(t) * 0.913) * 0.8);
		bool lone_tree = slot == slots - 1 && tt_hash(vec2(t) * 1.37 + 2.0) < lone;
		show = show && (float(slot) < n || lone_tree);
		edge_size = mix(0.7, 1.0, smoothstep(0.15, 0.7, density)); // smaller at the wood edge
		float h = tt_height_m(centre, height_lod);
		float lat = tt_latitude(centre);
		show = show && h < 1400.0 && cov.g < 0.7;
		float conifer_p = clamp((h - 700.0) / 700.0, 0.0, 1.0) + clamp((lat - 50.0) / 4.0, 0.0, 1.0);
		// stone pines and cypresses in the warm lowlands, more of them in open land
		bool south = lat < 44.5 && h < 700.0;
		float pine_p = south ? 0.12 + 0.35 * (1.0 - smoothstep(0.2, 0.7, density)) : 0.0;
		int kind = r0 < conifer_p ? 1
			: (south && r0 < conifer_p + pine_p) ? 4
			: (south && r0 < conifer_p + pine_p + 0.1) ? 2 : 0;
		code = float(kind) + 0.25 * edge_size;
		// slots on a jittered grid, so a dense wood covers the tile evenly
		int side = int(ceil(sqrt(float(slots))));
		vec2 g = vec2(float(slot % side), float(slot / side));
		uv = (g + 0.2 + 0.6 * vec2(r1, r2)) / float(side) * 0.9 + 0.05;
	}
	vec4 c = show ? tt_corners_cached(t) : vec4(0.0);
	if (house) { code = float(town); }
	if (!show) { return vec4(0.0, 0.0, 0.0, -1.0); }
	// on the tile's own triangles (split as in tile_terrain.gdshader), so
	// trees stand on steep two-level tiles too instead of leaving bare holes
	float level;
	if (abs(c.x - c.z) <= abs(c.y - c.w)) {
		level = uv.x >= uv.y
			? c.x + (c.y - c.x) * uv.x + (c.z - c.y) * uv.y
			: c.x + (c.w - c.x) * uv.y + (c.z - c.w) * uv.x;
	} else {
		level = uv.x + uv.y <= 1.0
			? c.x + (c.y - c.x) * uv.x + (c.w - c.x) * uv.y
			: c.z + (c.w - c.z) * (1.0 - uv.x) + (c.y - c.z) * (1.0 - uv.y);
	}
	return vec4(uv, level, code);
}
