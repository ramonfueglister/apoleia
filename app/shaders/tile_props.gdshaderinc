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
		float share = tt_house_share(town);
		if (sub_tiles) {
			// one house on a flat quarter (a hill town steps up in terraces;
			// tt_sub_house decides which quarters hold one)
			vec4 q = tt_corners_cached(t);
			bool level = max(max(q.x, q.y), max(q.z, q.w)) - min(min(q.x, q.y), min(q.z, q.w)) < 0.01;
			show = show && slot == 0 && level && tt_sub_house(t, town);
			// now and then a courtyard in the rows of the city core
			show = show && !(town == 3 && tt_hash(vec2(t) * 1.91 + 0.7) < 0.12);
			uv = vec2(0.5) + (vec2(r1, r2) - 0.5) * 0.03;
		} else {
			int count = max(int(round(share * float(slots))), town > 0 ? 1 : 0);
			show = show && slot < count;
			show = show && !(town == 3 && tt_hash3(vec3(vec2(t), float(slot) + 9.1)) < 0.12);
			int cell_k = town == 3 ? slot : (slot * 7 + int(tt_hash(vec2(t)) * float(slots))) % slots;
			vec2 sub = vec2(float(cell_k % side), float(cell_k / side));
			uv = (sub + 0.5) / float(side) + (vec2(r1, r2) - 0.5) * 0.03;
		}
		show = show && !tt_in_landmark(world_min + (vec2(t) + uv) * tile_km);
	} else {
		show = show && town == 0;
		uv = vec2(0.5);
	}
	if (!house && show) {
		// slots on a jittered grid, so a dense wood covers the tile evenly
		int side = int(ceil(sqrt(float(slots))));
		vec2 g = vec2(float(slot % side), float(slot / side));
		uv = (g + 0.2 + 0.6 * vec2(r1, r2)) / float(side) * 0.9 + 0.05;
		// trees stand on the forest tiles (and forest halves of a split tile),
		// single ones now and then on open grassland
		vec2 at = world_min + (vec2(t) + uv) * tile_km;
		int land = tt_ground_at(t, uv);
		bool wood = land == G_FOREST || land == G_CONIFER;
		bool open = land == G_MEADOW || land == G_DRY_GRASS || land == G_ALPINE || land == G_SCRUB;
		// open land: small groves of a few trees around one spot of the data
		// tile, as in Urbek (no single trees: they read as specks)
		bool field = land == G_FIELD;
		bool grove = false;
		if (open || field) {
			ivec2 dt = sub_tiles ? t >> ivec2(1) : t;
			vec2 duv = sub_tiles ? (vec2(t & ivec2(1)) + uv) * 0.5 : uv;
			float gh = tt_hash(vec2(dt) * 0.613 + 7.1);
			vec2 spot = 0.3 + 0.4 * vec2(tt_hash(vec2(dt) + 1.7), tt_hash(vec2(dt) - 2.9));
			grove = gh < (open ? 0.07 : 0.03) && length(duv - spot) < 0.3; // three to seven trees
		}
		// up close a wood keeps the density of the 0.5 km tiles (about 2 of
		// the 4 slots of a quarter), so the ground shows between the crowns
		bool thin = sub_tiles && tt_hash3(vec3(vec2(t) * 0.37, float(slot) + 0.5)) > 0.6;
		show = show && (wood || grove) && !thin;
		edge_size = mix(0.8, 1.0, r0);
		float h = tt_height_m(at, height_lod);
		float lat = tt_latitude(at);
		show = show && h < 1400.0;
		float conifer_p = land == G_CONIFER ? 0.9 : clamp((lat - 50.0) / 4.0, 0.0, 1.0);
		// stone pines and cypresses in the warm lowlands, more of them in open land
		bool south = lat < 44.5 && h < 700.0;
		float pine_p = south ? (wood ? 0.12 : 0.45) : 0.0;
		int kind = r0 < conifer_p ? 1
			: (south && r0 < conifer_p + pine_p) ? 4
			: (south && r0 < conifer_p + pine_p + 0.1) ? 2 : 0;
		code = float(kind) + 0.25 * edge_size;
	}
	vec4 c = show ? tt_corners_cached(t) : vec4(0.0);
	if (house) { code = float(town); }
	if (!show) { return vec4(0.0, 0.0, 0.0, -1.0); }
	// on the tile's own triangles (split as in tile_terrain.gdshader), so
	// trees stand on steep two-level tiles too instead of leaving bare holes
	// nothing in the wet half of a coast cut tile; the dry half keeps its split
	int cut = tt_coast_cut(t);
	if (cut >= 0) {
		vec2 tip = vec2(float(cut == 1 || cut == 2), float(cut >= 2));
		if (abs(uv.x - tip.x) + abs(uv.y - tip.y) < 1.1) { return vec4(0.0, 0.0, 0.0, -1.0); }
	}
	float level;
	if (cut >= 0 ? (cut & 1) == 1 : abs(c.x - c.z) <= abs(c.y - c.w)) {
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
