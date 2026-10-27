// Shared placement of cumulus clusters (multimesh, world_vertex_coords). Used by
// the visible cloud shader and the opaque shadow/mask proxy shader so both agree
// on shape and position. Where cover is high the clusters grow and merge into
// grey banks (overcast, rain, storm fronts).
#include "res://shaders/weather_field.gdshaderinc"

uniform float cloud_base = 90.0;
uniform float cluster_scale = 1.0;  // shrinks clusters in close views (largest ~10 % of view width)
uniform float puff_amount = 1.0;   // scales scattered fair-weather clusters
uniform float bank_grey = 0.0;     // how grey merged banks turn (0 fair, 1 rain)

float bank_amount(float cover) { return smoothstep(0.55, 0.85, cover); }

// One rule for every cloud type: nothing between camera and focus. Clusters whose
// horizontal distance along the view is short of the focus (fair: a little
// before it, banks/fronts: at or beyond it), or wider than 25 % of the screen,
// shrink away. Low clouds beyond the focus sit in the upper half of the picture.
uniform float near_hide_distance = 0.0;   // 3D distance for the size limit
uniform vec2 view_forward = vec2(0.0, -1.0);
uniform float focus_forward = 0.0;        // camera -> focus along view_forward
uniform float near_hide_fair = 0.85;      // fraction of focus_forward for fair clusters
uniform float near_hide_bank = 1.05;      // fraction of focus_forward for banks/fronts
uniform float bank_growth = 2.2;          // how far bank clusters grow; less in close views
uniform float view_tan = 1.0; // 2 * tan(fov/2) * aspect: screen width at unit distance
float view_keep(vec3 centre, float width, vec3 camera, float bank) {
	float d = distance(centre, camera);
	float along = dot(centre.xz - camera.xz, view_forward);
	float near = focus_forward * mix(near_hide_fair, near_hide_bank, bank);
	float screen = width / max(d * view_tan, 0.001);
	// The size limit applies near the focus; distant fronts on the horizon may be wide.
	float size_limit = 1.0 - smoothstep(0.2, 0.25, screen) * (1.0 - smoothstep(1.05, 1.3, d / max(near_hide_distance, 0.001)));
	return smoothstep(near * 0.9, near, along) * size_limit;
}

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
	// Small fair clusters in close views; banks and fronts keep their full size.
	float s = presence * (0.8 + 0.5 * field.x) * (1.0 + bank_growth * bank) * mix(cluster_scale, 1.0, bank);
	info = vec4(s, field.x, max(field.y, bank * 0.8 * bank_grey), field.z);
	// Banks spread wide and flat; fair clusters keep their height.
	vec3 local = (vertex_world - origin) * s;
	// Height:width at most about 1:3 for banks and storm fronts.
	// Fair cumulus about 1:2; banks flatten, storm towers stay tall.
	local.y *= 1.15 * (1.0 - 0.6 * bank * (1.0 - field.z));
	return vec3(world_xz.x, cloud_base, world_xz.y) + local;
}
