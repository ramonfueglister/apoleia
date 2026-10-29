// The roads the player builds (scripts/road_view.gd), as narrow bands that
// lie on the ground and run with it over ramps and terraces, in the scale
// of the farmhouses: a gravel road about four diorama metres wide (Urbek's
// dirt roads, half a house front), not a whole sim tile.
//
// The mesh holds the road's middle line: VERTEX the point on it (world km,
// y unused), UV2 the way to the edge (unit vector times the share of the
// half width, -1..1, so the round caps at the ends are fans), UV.x the
// distance along the road (km), UV.y the place across (-1..1). The vertex
// shader widens it, sets it on the ground as the terrain draws it
// (dot_ground_level) and draws it a hair towards the camera, so it stays
// on top of the ground without floating above it.
//
// Every road is drawn twice (`layer`): the casing at the full width in the
// colour of the verge, then the fill a little narrower and a step nearer
// the camera. Where roads meet, each fill covers the others' verges, so a
// crossing reads as one road surface and not as two strips laid over each
// other (the casing and fill of map renderers).

#include "res://shaders/people_dots_common.gdshaderinc"

uniform int layer = 1;              // 0 the casing (full width, the verge), 1 the fill
uniform float half_km = 0.05;       // half the road's width (road_view.gd ROAD_KM)
uniform float min_half_km = 0.0;    // at least this, so a road far out stays a line of a few pixels
uniform float km_per_m = 0.0238;    // diorama scale (TileTerrain.DIORAMA_KM_PER_M)
instance uniform float built_km = 1.0e6; // built from the start up to here; beyond it the road is staked out
instance uniform float state = 0.0; // the build menu's preview: 0 none, 1 can be built, 2 cannot
instance uniform float order = 0.0; // 0..1, a fixed order where roads overlap (no flicker)

varying float along;
varying float across;
varying vec2 ground;

const float FILL = 0.78;            // the fill's share of the width; the rest is verge
const float LIFT_KM = 0.001;
const float BIAS_KM[2] = float[](0.004, 0.006); // casing, fill: towards the camera
const vec3 GRAVEL = vec3(0.62, 0.57, 0.47);     // the road, lighter than the brown farm tracks
const vec3 VERGE = vec3(0.44, 0.38, 0.29);      // its edge, the farm tracks' brown (sim_map.gdshaderinc SIM_TRACK_RGB)
const vec3 EARTH = vec3(0.46, 0.35, 0.25);      // staked out, the turf cut and the earth bare
const vec3 EARTH_EDGE = vec3(0.37, 0.28, 0.2);
const vec3 FRONT = vec3(0.3, 0.22, 0.16);       // where the gang is at work, fresh earth
const vec3 STAKE = vec3(0.8, 0.72, 0.54);       // pegs along the staked-out edges
const vec3 PREVIEW_OK = vec3(0.55, 0.9, 0.45);
const vec3 PREVIEW_NO = vec3(0.95, 0.35, 0.3);

void vertex() {
	float w = max(half_km, min_half_km) * (layer == 0 ? 1.0 : FILL);
	vec2 p = VERTEX.xz + UV2 * w;
	ground = p;
	along = UV.x;
	across = UV.y;
	vec3 world = vec3(p.x, dot_ground_level(p) * level_h + LIFT_KM, p.y);
	vec3 v = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// towards the camera along the ray: the same pixel, a little nearer
	v -= normalize(v) * (BIAS_KM[layer] + 0.001 * order);
	VERTEX = v;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz); // lit as the flat ground (tile_terrain.gdshader)
}

// The road's colour (sRGB) at a place along and across it.
vec3 road_colour(float at, float side) {
	float a = abs(side);
	bool verge = layer == 0 && a > FILL;
	if (at <= built_km) {
		vec3 c = verge ? VERGE : GRAVEL;
		// two wheel ruts a little darker
		if (!verge && a > 0.28 && a < 0.42) { c *= 0.9; }
		return c;
	}
	// staked out: bare earth, pegs every three metres along the edges, and
	// a band of fresh earth where the work has got to
	float m = km_per_m;
	if (at < built_km + 1.5 * m) { return FRONT; }
	if (a > 0.86 && fract(at / (3.0 * m)) < 0.12) { return STAKE; }
	return verge ? EARTH_EDGE : EARTH;
}

void fragment() {
	vec3 c = road_colour(along, across);
	// a fine speckle of stones on the voxel grid of a quarter metre (as
	// people_crops.gdshader), gone before it would shimmer
	vec2 g = mod(ground / (km_per_m * 0.25), 4096.0);
	float n = fract(sin(dot(floor(g), vec2(12.9898, 78.233))) * 43758.5453);
	c *= 1.0 + (n - 0.5) * 0.14 * (1.0 - smoothstep(0.25, 0.5, length(fwidth(g))));
#ifdef PREVIEW
	c = mix(c, state > 1.5 ? PREVIEW_NO : PREVIEW_OK, 0.45);
	ALPHA = 0.7;
#endif
	ALBEDO = pow(clamp(c, 0.0, 1.0), vec3(2.2));
	ROUGHNESS = 1.0;
}
