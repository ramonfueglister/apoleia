// The slabs the fields stand on up close (people_crops.gdshader), shared
// with the placement of the people (people_dots_prep.gdshader), so someone
// at work in a field stands on its slab and not waist-deep in it. Needs
// people_dots_common.gdshaderinc and sim_fields.gdshaderinc before it.

const float SLAB_GAP = 0.025; // share of the parcel left free on each side

// The slab's height (m) by the parcel's state, crop and growth: a sheet
// of stubble on fallow, ripe grain a closed sheet, otherwise low soil.
float crop_slab_m(int state, int kind, float g) {
	if (state == 1) { return 0.5; }
	if (kind == SIM_WHEAT || kind == SIM_BARLEY) {
		return g <= 0.0 ? 0.15 : g >= 0.75 ? 0.9 : 0.12;
	}
	return kind == SIM_VINES ? 0.2 : 0.12;
}

// Whether a parcel with its middle at `mid` may carry a field: open land
// outside the towns as sim_fields, never a farmhouse's lot, flat tiles only
// (a ramp shows the field's colour).
bool crop_open(vec2 mid) {
	ivec2 t = dot_tile(mid);
	int land = tt_ground_at(t, fract((mid - world_min) / tile_km));
	return tt_town(t) == 0 && tt_water(t) == W_LAND && (land == G_FIELD || land == G_MEADOW || land == G_DRY_GRASS)
		&& !sim_house_lot(mid) && sim_flat(mid);
}

// The top of the slab under p (world km) in metres, 0 off the fields and
// outside the square where the crops stand (sim_crop_box).
float crop_slab_under(vec2 p) {
	if (!sim_map_on || sim_view_km > SIM_CROPS_KM) { return 0.0; }
	if (any(lessThan(p, sim_crop_box.xy)) || any(greaterThanEqual(p, sim_crop_box.zw))) { return 0.0; }
	float size = tt_data_km() * 0.5;
	vec2 cell = floor((p - world_min) / size);
	vec2 mid = world_min + (cell + 0.5) * size;
	vec2 d = abs(p - mid);
	if (max(d.x, d.y) >= size * (0.5 - SLAB_GAP)) { return 0.0; }
	vec4 f;
	int state = sim_parcel(cell, size, f);
	if (state == 0 || !crop_open(mid)) { return 0.0; }
	return crop_slab_m(state, sim_crop_kind(cell), f.b);
}
