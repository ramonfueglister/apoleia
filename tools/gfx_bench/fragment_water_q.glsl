
uniform vec2 view_min;
uniform vec2 view_size;
uniform bool new_coast = true; // here: round Q with the real water window (water_lines.gd)

// top-down mid zoom (0.5 and 1 km tiles), as the land and lake branches draw it
void fragment() {
	vec2 p = view_min + UV * view_size;
	vec2 q = (p - world_min) / tile_km;
	ivec2 t = ivec2(floor(q));
	vec2 f = fract(q);
	int cell = tt_cell(t);
	int w = cell & 3;
	int town = cell >> 2;
	vec4 cr = tt_corners_cached(t);
	float lv = mix(mix(cr.x, cr.y, f.x), mix(cr.w, cr.z, f.x), f.y);
	float body = min(min(cr.x, cr.y), min(cr.z, cr.w));
	float far = far_share();
	vec3 water_c = mix(C_INLAND, C_SHORE_FAR, far);
	bool Q = new_coast && water_lines;
	vec3 wl = vec3(0.0);
	if (Q) { wl = tt_water_lines(p); }
	int nc[4];
	for (int k = 0; k < 4; k++) { nc[k] = tt_cell(t + SIDE[k]); }
	int lake_cut = w == W_LAKE && !Q ? tt_lake_corner_cut(t, nc) : -1;
	ivec3 plan = tile_km < 0.75 ? cp_texel(cp_parcel(p)) : ivec3(0);
	bool planned = plan.r != CP_NONE;
	if (planned) { town = cp_town(plan.r); }
	vec3 c;
	if (w == W_SEA) {
		c = mix(C_SEA, C_SEA_FAR, far);
	} else if (w == W_LAKE && lake_cut < 0) {
		c = water_c;
		if (Q) { c = mix(contour_land_rgb(p), c, max(wl.g, wl.r)); }
	} else if (w == W_LAKE) {
		vec2 tip = vec2(CORNER[lake_cut]);
		bool wet = abs(f.x - tip.x) + abs(f.y - tip.y) < 1.0;
		c = wet ? water_c : ground_rgb_at(tt_ground(t + SIDE[(lake_cut + 1) & 3]), 0.0);
	} else {
		c = ground_rgb_at(tt_ground_at(t, f), max(body - 1.0, 0.0));
		if (town >= 2) { c = C_ROOF; }
		bool quay = w == W_RIVER && max(max(tt_town(t + ivec2(1, 0)), tt_town(t - ivec2(1, 0))), max(tt_town(t + ivec2(0, 1)), tt_town(t - ivec2(0, 1)))) >= 2;
		if (quay) { c = C_PAVED; }
		bool plan_built = planned && plan.r != CP_LAND;
		bool by_line = Q && town < 2 && !plan_built && !quay;
		if (w == W_RIVER && !by_line) {
			float half_w = clamp(0.075 / tile_km, 0.06, 0.22);
			vec2 qq = f - 0.5;
			half_w = min(max(half_w, 0.75 * length(fwidth(qq))), 0.3);
			const vec2 MID[4] = vec2[](vec2(0.0, -0.5), vec2(0.5, 0.0), vec2(0.0, 0.5), vec2(-0.5, 0.0));
			int m = 0;
			for (int k = 0; k < 4; k++) { if ((nc[k] & 3) != W_LAND) { m |= 1 << k; } }
			bool bend = m == 3 || m == 6 || m == 12 || m == 9;
			float d = 10.0;
			if (bend) {
				int a = m == 9 ? 3 : (m == 3 ? 0 : m == 6 ? 1 : 2);
				vec2 p0 = MID[a];
				vec2 p1 = MID[(a + 1) % 4];
				vec2 e = p1 - p0;
				d = length(qq - p0 - e * clamp(dot(qq - p0, e) / dot(e, e), 0.0, 1.0));
			} else {
				d = length(qq);
				for (int k = 0; k < 4; k++) {
					if ((m & (1 << k)) != 0) {
						vec2 e = MID[k];
						d = min(d, length(qq - e * clamp(dot(qq, e) / dot(e, e), 0.0, 1.0)));
					}
				}
			}
			float aa = fwidth(d) * 1.2;
			c = mix(c, C_BANK, 1.0 - smoothstep(half_w + 0.02, half_w + 0.02 + aa, d));
			c = mix(c, water_c, 1.0 - smoothstep(half_w, half_w + aa, d));
		}
		if (Q) {
			float lake = 0.0;
			if (wl.g > 0.0 && town < 2 && !plan_built) {
				bool touch = false;
				for (int k = 0; k < 8; k++) {
					ivec2 o = k < 4 ? SIDE[k] : SIDE[k - 4] + SIDE[(k - 3) & 3];
					touch = touch || tt_water(t + o) == W_LAKE;
				}
				lake = touch ? wl.g * (1.0 - smoothstep(0.35, 0.55, lv - body)) : 0.0;
			}
			float river = by_line ? wl.r : 0.0;
			c = mix(c, C_BANK, by_line ? wl.b * (1.0 - lake) : 0.0);
			c = mix(c, water_c, max(river, lake));
		}
	}
	COLOR = vec4(c, 1.0);
}
