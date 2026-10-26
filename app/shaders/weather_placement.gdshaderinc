// Shared placement of cumulus clusters (multimesh, world_vertex_coords). Used by
// the visible cloud shader and the opaque shadow/mask proxy shader so both agree
// on shape and position. Where cover is high the clusters grow and merge into
// grey banks (overcast, rain, storm fronts).
#include "res://shaders/weather_field.gdshaderinc"

uniform float cloud_base = 90.0;
uniform float puff_amount = 1.0;   // scales scattered fair-weather clusters
uniform float bank_grey = 0.0;     // how grey merged banks turn (0 fair, 1 rain)

float bank_amount(float cover) { return smoothstep(0.55, 0.85, cover); }

// Cumulus: returns the world vertex; x of `info` is the cluster scale (0 = absent).
vec3 place_cluster(vec3 vertex_world, vec3 origin, vec4 custom, out vec4 info) {
	vec2 world_xz = origin.xz + air_drift;
	vec3 field = weather_field(world_xz);
	float bank = bank_amount(field.x);
	// Scattered clusters follow puff_amount; inside banks every slot fills.
	float cluster_cover = max(field.x * puff_amount, bank);
	float h = custom.x;
	float presence = smoothstep(h - 0.06, h + 0.06, cluster_cover);
	// Banks and fronts: clusters grow until they merge into one mass.
	float s = presence * (0.8 + 0.5 * field.x) * (1.0 + 2.2 * bank);
	info = vec4(s, field.x, max(field.y, bank * 0.8 * bank_grey), field.z);
	// Banks spread wide and flat; fair clusters keep their height.
	vec3 local = (vertex_world - origin) * s;
	local.y *= 1.0 - 0.7 * bank * (1.0 - field.z);
	return vec3(world_xz.x, cloud_base, world_xz.y) + local;
}
