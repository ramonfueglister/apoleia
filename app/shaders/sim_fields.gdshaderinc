// Where the grain fields lie (sim/godot/src/grain_map.rs, the fine layer):
// shared by the terrain's field colours (sim_map.gdshaderinc) and the crops
// standing on them (people_crops.gdshader), so both agree parcel for parcel.
//
// Fine texel: R share of the tile under fields, G sown share of them, B
// growth (0 bare … 1 ripe), A footpaths and markets (sim_map.gdshaderinc).

uniform bool sim_map_on = false;
uniform sampler2D sim_fine_tex : filter_nearest, repeat_disable;
uniform vec2 sim_fine_origin;      // world km of the window's first texel corner
uniform float sim_fine_km = 1.5625;
uniform int sim_fine_n = 0;
uniform float sim_view_km = 30.0;  // view width: what is drawn (fields, crops, paths, roads, lanes)
uniform sampler2D sim_lot_tex : filter_nearest, repeat_disable; // lots with a farmhouse (people_lots.gdshader)
uniform vec2 sim_lot_origin;       // lot index of the mask's first pixel
uniform int sim_lots_n = 0;        // lots per side of the mask, 0 without one
uniform float sim_lot_km = 0.36;   // people_dots_common.gdshaderinc DOT_LOT_KM

// View width up to which the parcels are single and the crops stand on
// them as plants; up to 30 km the fields are whole blocks of one colour.
const float SIM_CROPS_KM = 8.0;
const float SIM_FIELDS_KM = 30.0;

float sim_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Fine texel at window tile t, zero outside the window.
vec4 sim_fine_at(ivec2 t) {
	if (t.x < 0 || t.y < 0 || t.x >= sim_fine_n || t.y >= sim_fine_n) { return vec4(0.0); }
	return texelFetch(sim_fine_tex, t, 0);
}

// Whether a farmhouse stands on the lot under p (world km); its house,
// garden and yard are kept free of fields. The mask is kept only while the
// crops stand.
bool sim_house_lot(vec2 p) {
	if (sim_lots_n == 0 || sim_view_km > SIM_CROPS_KM) { return false; }
	vec2 lot = floor(p / sim_lot_km) - sim_lot_origin;
	if (lot.x < 0.0 || lot.y < 0.0 || lot.x >= float(sim_lots_n) || lot.y >= float(sim_lots_n)) { return false; }
	return texelFetch(sim_lot_tex, ivec2(lot), 0).a > 0.5;
}

// The parcel `cell` (of side `size` km): 0 not farmed, 1 fallow, 2 sown;
// `f` is its fine texel. Each fine tile farms one block around its middle,
// as large as its field share (a rounded square, with a little jitter for a
// ragged edge), so the farmland reads as calm blocks around the villages;
// a `whole` block (far) has no jitter and no fallow parcels.
int sim_parcel(vec2 cell, float size, bool whole, out vec4 f) {
	vec2 q = ((cell + 0.5) * size - sim_fine_origin) / sim_fine_km;
	f = sim_fine_at(ivec2(floor(q)));
	if (f.r <= 0.0) { return 0; }
	vec2 d = abs(fract(q) - 0.5) * 2.0;
	float r = mix(max(d.x, d.y), length(d) * 0.7071, 0.5);
	if (r * r + (whole ? 0.0 : 0.12 * (sim_hash(cell) - 0.5)) >= f.r) { return 0; }
	if (!whole && sim_hash(cell + 17.3) >= f.g) { return 1; }
	return 2;
}
