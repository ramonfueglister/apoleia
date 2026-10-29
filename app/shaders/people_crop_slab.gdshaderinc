// The slabs the fields stand on up close (people_crops.gdshader), shared
// with the placement of the people (people_dots_prep.gdshader), so someone
// at work in a field stands on its slab and not waist-deep in it. Needs
// people_dots_common.gdshaderinc and sim_fields.gdshaderinc before it.

const float SLAB_GAP = 0.025; // share of the parcel left free on each side

// The slab's height (m) by the parcel's state, crop and growth: a sheet
// of stubble on fallow, ripe grain a closed sheet, both with an edge as
// thick as Urbek's (round 19: a 3 px lip at 1 km), otherwise low soil.
float crop_slab_m(int state, int kind, float g) {
	if (state == 1) { return 0.8; }
	if (kind == SIM_WHEAT || kind == SIM_BARLEY) {
		return g <= 0.0 ? 0.15 : g >= 0.75 ? 1.2 : 0.12;
	}
	return kind == SIM_VINES ? 0.2 : 0.12;
}

// Whether the ground right in front of tile t (towards the camera, to the
// south) rises above it: a ramp there hides part of a slab on t, which
// then reads as a field cut off along the ramp (round 18).
bool crop_behind_ramp(ivec2 t) {
	vec4 c = tt_corners_cached(t + ivec2(0, 1));
	return max(max(c.x, c.y), max(c.z, c.w)) > tt_corners_cached(t).x + 0.01;
}

// Whether a parcel with its middle at `mid` may carry a field: open land
// outside the towns as sim_fields, never a farmhouse's lot, under trees or
// next to a town (sim_no_field), flat tiles only (a ramp shows the field's
// colour) and none at the foot of a ramp that would hide part of it.
bool crop_open(vec2 mid) {
	ivec2 t = dot_tile(mid);
	int land = tt_ground_at(t, fract((mid - world_min) / tile_km));
	return tt_town(t) == 0 && tt_water(t) == W_LAND && (land == G_FIELD || land == G_MEADOW || land == G_DRY_GRASS)
		&& !sim_house_lot(mid) && sim_flat(mid) && !crop_behind_ramp(t) && !sim_no_field(mid, land);
}

// The slab of parcel `cell` (side `size` km) about the parcel's middle, km
// (min x, min y, max x, max y): SLAB_GAP in from the parcel lines, and
// clear of a village lane or field track running along one of them
// (sim_lane_between), so the lanes run between the fields, not under them.
vec4 crop_box(vec2 cell, float size) {
	float gap = size * SLAB_GAP;
	float lane_gap = SIM_LANE_KM + gap * 0.5;
	vec4 box = vec4(vec2(-0.5 * size + gap), vec2(0.5 * size - gap));
	if (sim_lots_n == 0) { return box; }
	vec2 mid = world_min + (cell + 0.5) * size;
	vec2 lot = floor((mid - world_min) / sim_lot_km);
	vec2 lo = (mid - 0.5 * size - world_min) / sim_lot_km; // the parcel's sides in lots
	vec2 hi = (mid + 0.5 * size - world_min) / sim_lot_km;
	if (abs(lo.x - round(lo.x)) < 0.01 && sim_lane_between(lot, vec2(-1.0, 0.0))) { box.x = -0.5 * size + lane_gap; }
	if (abs(lo.y - round(lo.y)) < 0.01 && sim_lane_between(lot, vec2(0.0, -1.0))) { box.y = -0.5 * size + lane_gap; }
	if (abs(hi.x - round(hi.x)) < 0.01 && sim_lane_between(lot, vec2(1.0, 0.0))) { box.z = 0.5 * size - lane_gap; }
	if (abs(hi.y - round(hi.y)) < 0.01 && sim_lane_between(lot, vec2(0.0, 1.0))) { box.w = 0.5 * size - lane_gap; }
	return box;
}

// The top of the slab under p (world km) in metres, 0 off the fields and
// outside the square where the crops stand (sim_crop_box).
float crop_slab_under(vec2 p) {
	if (!sim_map_on || sim_view_km > SIM_CROPS_KM) { return 0.0; }
	if (any(lessThan(p, sim_crop_box.xy)) || any(greaterThanEqual(p, sim_crop_box.zw))) { return 0.0; }
	float size = tt_data_km() * 0.5;
	vec2 cell = floor((p - world_min) / size);
	vec2 mid = world_min + (cell + 0.5) * size;
	vec4 f;
	int state = sim_parcel(cell, size, f);
	if (state == 0 || !crop_open(mid)) { return 0.0; }
	vec4 box = crop_box(cell, size);
	vec2 o = p - mid;
	if (any(lessThan(o, box.xy)) || any(greaterThanEqual(o, box.zw))) { return 0.0; }
	return crop_slab_m(state, sim_crop_kind(cell), f.b);
}
