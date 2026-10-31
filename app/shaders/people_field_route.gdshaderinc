// The way of a farmer to its household's field and home again over the
// worn ways and the lanes, not through the houses (Ramon, 31.10.2026:
// „über das Wegnetz, wie Marktgänger“). people_dots.gd hands each figure
// of the list the way from its village to its field (walk_route.gd
// field_route: the worn network, then the lot lines to the lot corner
// nearest the field), one row of field_route_w texels per figure: (count,
// km), then the points (world km). The part round the figure's own house
// is worked out here, where the house is known (people_dots_prep.gdshader
// writes which lot holds it into the place's alpha): from the spot
// straight out to the nearest side of its lot (away from the house), along
// the lot's edge to its corner nearest the way, along the lot lines to the
// lot corner nearest the way's first point and into it; after the way the
// last step into the field. Lot lines are the lanes between the lots,
// where no farmhouse stands; the worn ways are those the farmhouses keep
// off (dot_lot_way_free).
//
// people_day.gdshaderinc day_at walks the share u of the way out (0 at
// the spot, 1 in the field); field_route_pace makes the walk last as long
// as this way is long, field_route_at gives the point at share u.
//
// Needs people_dots_common.gdshaderinc.

uniform sampler2D field_route_tex : filter_nearest, repeat_disable;
const int FIELD_ROUTE_W = 32; // people_dots.gd ROUTE_W
const int FIELD_ROUTE_PRE = 6; // points of the part round the house at most

// The part round the house: the points from `home` (the spot) up to before
// the way's first point `first`, into pre; their count. `placed` is the
// place's alpha (people_dots_prep.gdshader).
int field_route_pre(vec2 home, float placed, vec2 first, out vec2 pre[FIELD_ROUTE_PRE]) {
	pre[0] = home;
	int code = int(placed + 0.5) - 2;
	if (code < 0) {
		return 1; // no house on a lot: straight to the way
	}
	float half_lot = DOT_LOT_KM * 0.5;
	vec2 lot = dot_lot(home) + vec2(float(code % 3 - 1), float(code / 3 - 1)) * DOT_LOT_KM;
	vec2 d = home - lot;
	vec2 c = clamp(d, vec2(-half_lot), vec2(half_lot));
	// out to the nearest side, away from the house in the middle
	vec2 e = abs(c.x) >= abs(c.y) ? vec2(sign(c.x + 1e-6) * half_lot, c.y) : vec2(c.x, sign(c.y + 1e-6) * half_lot);
	// the lot's corner nearest the way's first point
	vec2 corner = vec2(first.x >= lot.x ? half_lot : -half_lot, first.y >= lot.y ? half_lot : -half_lot);
	int n = 1;
	pre[n++] = lot + e;
	// along the edge it reached to that corner (through the corner between)
	vec2 bend = abs(e.x) >= half_lot - 1e-5 && abs(abs(e.y) - half_lot) > 1e-5 ? vec2(e.x, corner.y) : vec2(corner.x, e.y);
	pre[n++] = lot + bend;
	pre[n++] = lot + corner;
	// along the lot lines to the lot corner nearest the first point
	vec2 grid = world_min + round((first - world_min) / DOT_LOT_KM) * DOT_LOT_KM;
	pre[n++] = vec2(grid.x, lot.y + corner.y);
	pre[n++] = grid;
	return n;
}

int field_route_count(int id) {
	return int(texelFetch(field_route_tex, ivec2(0, id), 0).r + 0.5);
}

vec2 field_route_point(int id, int k) {
	return texelFetch(field_route_tex, ivec2(k + 1, id), 0).rg;
}

// The length of the whole way (km) from `home` to `end` (the spot in the
// field) for figure `id` of the list; 0 when it has none.
float field_route_km(int id, vec2 home, float placed, vec2 end) {
	int n = field_route_count(id);
	if (n <= 0) {
		return 0.0;
	}
	vec2 first = field_route_point(id, 0);
	vec2 pre[FIELD_ROUTE_PRE];
	int m = field_route_pre(home, placed, first, pre);
	float km = 0.0;
	for (int k = 1; k < m; k++) {
		km += distance(pre[k - 1], pre[k]);
	}
	km += distance(pre[m - 1], first);
	km += texelFetch(field_route_tex, ivec2(0, id), 0).g;
	km += distance(field_route_point(id, n - 1), end);
	return km;
}

// The way (dot_field_way: offset to the field, pace) with the pace slowed
// so a walk of length(way.xy) lasts as long as the route `km` (day_at
// times the walk by the straight offset).
vec3 field_route_pace(vec3 way, float km) {
	float straight = length(way.xy);
	if (km <= straight || straight <= 0.0) {
		return way;
	}
	return vec3(way.xy, way.z * straight / km);
}

// The point at share u of the way (0 home, 1 the field) and in `dir` the
// direction of that stretch (world x, z, towards the field).
vec2 field_route_at(int id, vec2 home, float placed, vec2 end, float km, float u, out vec2 dir) {
	int n = field_route_count(id);
	vec2 first = field_route_point(id, 0);
	vec2 pre[FIELD_ROUTE_PRE];
	int m = field_route_pre(home, placed, first, pre);
	float left = clamp(u, 0.0, 1.0) * km;
	dir = normalize(end - home + vec2(1e-6));
	vec2 a = home;
	// the stretches one after the other: round the house, the way, into the field
	for (int k = 1; k < m + n + 1; k++) {
		vec2 b = k < m ? pre[k] : (k - m < n ? field_route_point(id, k - m) : end);
		float len = distance(a, b);
		if (len > 1e-6) {
			dir = (b - a) / len;
			if (left <= len) {
				return a + dir * left;
			}
			left -= len;
		}
		a = b;
	}
	return end;
}
