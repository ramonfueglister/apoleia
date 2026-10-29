// The parcels of the square where the crops stand (people_dots.gd
// _update_crops), worked out once each: one float pixel per parcel, parcel
// `cell` at pixel cell mod the square's side, so a square moved by a few
// parcels keeps the pixels of the parcels it still holds. The crops
// (people_crops.gdshader) and the ground round their slabs
// (sim_map.gdshaderinc sim_fields) read it (sim_fields.gdshaderinc
// sim_parcel_baked) instead of asking the terrain and the lots for every
// vertex and pixel, which made the crops the dearest part of a frame up
// close (Mac tour, 29.10.2026). R the code (SIM_P_*), G the growth, B and A
// the ground level at the parcel's middle (whole levels and the fraction,
// as the half floats keep a level only to an eighth).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://shaders/people_dots_common.gdshaderinc"
#include "res://shaders/sim_fields.gdshaderinc"
#include "res://shaders/people_crop_slab.gdshaderinc"

uniform vec2 parcel_cell0; // the square's first parcel (from world_min)

void fragment() {
	float n = float(sim_parcel_n);
	vec2 px = floor(FRAGCOORD.xy);
	vec2 cell = parcel_cell0 + mod(px - parcel_cell0, n);
	float size = tt_data_km() * 0.5;
	vec2 mid = world_min + (cell + 0.5) * size;
	vec4 f;
	int state = sim_parcel(cell, size, f);
	int land = crop_land(mid);
	bool no_field = sim_no_field(mid, land);
	int code = state;
	if (crop_open_land(mid, land) && !no_field) { code |= SIM_P_OPEN; }
	if (no_field) { code |= SIM_P_NO_FIELD; }
	if (state > 0) {
		// the fields next to a farmhouse lot are fenced all round
		bool by_farm = false;
		for (int k = 0; k < 9; k++) {
			by_farm = by_farm || (k != 4 && sim_house_lot(mid + vec2(float(k % 3 - 1), float(k / 3 - 1)) * size));
		}
		if (by_farm) { code |= SIM_P_BY_FARM; }
		code |= crop_lanes(cell, size) * SIM_P_LANES;
	}
	float level = dot_ground_level(mid);
	COLOR = vec4(float(code), f.b, floor(level), fract(level));
}
