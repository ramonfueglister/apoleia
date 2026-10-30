// A house for every village household (sim/src/view.rs Houses), drawn with
// the house mesh and look of the tile terrain (tile_props.gdshader) at the
// household's house spot. The houses near the camera are listed nearest
// first (ApoleiaPeople.houses_near) into `list_tex`; three MultiMeshes with the
// voxel farmhouse in three levels of detail (scripts/voxel/farmhouse.gd) draw
// consecutive runs of that list from `list_offset`, once for each of the
// farmhouse's four builds (`variant`), each lot showing one of them. The
// record comes from the house texture array (ApoleiaPeople.sync_houses, only
// changed pages), the spot from the house placement pass
// (people_dots_prep.gdshader with `houses`), which runs only when houses or
// the terrain view change.
shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_lambert, specular_disabled; // mirrored houses turn their faces round

#include "res://shaders/people_dots_common.gdshaderinc"

uniform sampler2D place_tex : filter_nearest, repeat_disable; // house placement pass
uniform float prop_scale = 0.24; // world units of the unit house (tile_terrain.gd HOUSE_M)
uniform sampler2D list_tex : filter_nearest, repeat_disable; // house slots to draw (float)
uniform int list_w = 128;
uniform int list_offset = 0; // this level of detail's first entry in the list
uniform int variant = 0; // the farmhouse build this MultiMesh draws (farmhouse.gd VARIANTS)
uniform sampler2D look_tex : filter_nearest, repeat_disable; // what the house has (people_house_life.gd)
uniform bool has_looks = false;
const uint VARIANTS = 4u;

varying vec3 tint;
varying vec3 normal; // the face's own normal, also on mirrored (back-facing) faces
varying vec3 art_light; // HOUSE_LIGHT in view space
varying float model_y; // metres above the lot's ground (a farm being built is cut off above `built_m`)
varying float built_m; // how high a farm being built stands, metres; large on a finished house
// towards the light on the houses, world: as high as the terrain's
// SimCity light (tile_terrain.gdshader ART_LIGHT, so roofs and yards on top
// match the ground round them) but from where the scene's sun stands
// (west-south-west, weather_system.gd), so the west walls are the lit ones,
// the fronts a step darker and the east walls in shade, in step with the
// shadows the houses cast (round 18: lit from the south-west the fronts and
// west walls came out alike and the houses looked flat)
const vec3 HOUSE_LIGHT = vec3(-0.63, 0.72, 0.294);
// plaster (cream, pink, ochre, warm white) and shutters of the town buildings (prototypes/colosseum/city_buildings.gd), sRGB; only their ratios to the first tint the farmhouse (farmhouse.gd PLASTER)
const vec3 WALLS[4] = vec3[](vec3(0.922, 0.875, 0.784), vec3(0.925, 0.769, 0.659), vec3(0.851, 0.706, 0.471), vec3(0.937, 0.886, 0.784));
const vec3 SHUTTER_GREEN = vec3(0.373, 0.498, 0.275);
const vec3 SHUTTER_BROWN = vec3(0.604, 0.353, 0.227);
// roof tiles by farm: as built, rusty, a little lighter or dark red
// (Caesar III terracotta, never orange)
const vec3 ROOFS[4] = vec3[](vec3(1.0), vec3(1.02, 0.94, 0.8), vec3(1.06, 1.02, 0.96), vec3(0.92, 0.82, 0.74));
const float ROOF_PITCH = 0.42; // rise per metre (farmhouse.gd PITCH)

void vertex() {
	int i = list_offset + INSTANCE_ID;
	int id = int(texelFetch(list_tex, ivec2(i % list_w, i / list_w), 0).r);
	int per = page_side * page_side;
	int in_page = id % per;
	ivec2 px = ivec2(in_page % page_side, (id / per) * page_side + in_page / page_side);
	vec4 rec = dot_record(px);
	vec4 place = texelFetch(place_tex, px, 0);
	vec2 p = rec.xy + place.xy - 32.0;
	// turn, mirror, size and tint by the lot, so two houses on one lot are one
	vec2 st;
	mat2 turn = dot_house_turn(p, st);
	vec3 v = VERTEX * prop_scale * st.x;
	v.xz = turn * v.xz;
	vec3 world = vec3(p.x, place.z * level_h, p.y) + v;
	vec3 nrm = NORMAL;
	nrm.xz = turn * nrm.xz;
	bool show = rec.z != 0.0 && place.a > 0.5;
	// a tent household lives in its tent (people_house_life.gdshader), not in a farmhouse
	if (has_looks && (int(texelFetch(look_tex, px, 0).g * 255.0 + 0.5) & 2) != 0) {
		show = false;
	}
	// a farm being built (a record of its own, village code negated; rec.w
	// key << 8 | built 0-255): its walls up to the share built, no roof, no
	// trees, workshop or haystack yet, a scaffold round it (SCAFFOLD, 57)
	bool site = rec.z < 0.0;
	float built = float(uint(rec.w) & 255u) / 255.0;
	model_y = VERTEX.y * 10.0; // the farmhouse mesh is in units of HOUSE_M
	built_m = site ? max(0.25, built * (variant == 3 ? 7.0 : 5.0)) : 1.0e6;
	tint = vec3(st.y);
	// each farm its own plaster (cream, pink, ochre, as the town's
	// WALLS) and shutters (green or brown), by the palette index in UV.y
	// (scripts/voxel/farmhouse.gd); the vertex colour keeps its corner shading
	ivec2 lot = ivec2(floor((p - world_min) / DOT_LOT_KM));
	uint key = dot_hash(uint(lot.x) * 0x2545f491u ^ uint(lot.y) * 0x9e3779b9u);
	// one of the four builds per lot, drawn by its own MultiMesh
	show = show && int((key >> 12u) % VARIANTS) == variant;
	int index = int(UV.y + 0.5);
	if (index == 1 || index == 2 || index == 27) {
		tint *= WALLS[key % 4u] / WALLS[0];
	} else if (index == 20) {
		tint *= (key & 16u) != 0u ? vec3(1.0) : SHUTTER_BROWN / SHUTTER_GREEN;
	} else if ((index >= 4 && index <= 6) || (index >= 29 && index <= 36)) {
		tint *= ROOFS[(key >> 9u) % 4u];
	} else if (index == 37) {
		tint = vec3(1.0); // the yard's grass alike on every farm
	}
	// each roof slope lit as one plane by the way it faces once the house
	// is turned (farmhouse.gd _tile): the treads and the risers of its tile
	// rows take the slope's normal, so the slope facing the light is lit
	// and the one turned away is shaded as a whole; the risers a step
	// darker so the rows still show (round 16: risers turned from the light
	// read as near-black stripes)
	if (index >= 29 && index <= 36) {
		int d = (index - 29) / 2;
		vec2 face = turn * (d == 0 ? vec2(1.0, 0.0) : d == 1 ? vec2(-1.0, 0.0) : d == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0));
		tint *= abs(nrm.y) < 0.5 ? 0.85 : 1.0;
		nrm = normalize(vec3(face.x * ROOF_PITCH, 1.0, face.y * ROOF_PITCH));
	}
	// not every farm has the cypresses, the olive tree or the haystack
	// on its lot (farmhouse.gd _lot)
	bool cypress = index == 21 || index == 22;
	bool olive = index >= 23 && index <= 25;
	if ((cypress && (key & 96u) == 0u) || (olive && (key & 128u) == 0u) || ((index == 26 || index == 28) && (key & 256u) == 0u)) {
		show = false;
	}
	bool roof = (index >= 4 && index <= 6) || (index >= 29 && index <= 36);
	bool extra = cypress || olive || index == 26 || index == 28 || index == 18 || index == 12 || index == 13 || index >= 41;
	if (site && (roof || extra)) {
		show = false;
	}
	if (index == 57) {
		show = show && site && built < 1.0;
	}
	// the workshop of the household's craft (farmhouse.gd _workshop; the
	// record's rec.w: craft << 22 | key << 8 | busy, busy the share of the
	// month's work the dealers took): smithy 41-46, pottery 47-50, weaving
	// 51-56, more goods about the busier it is
	if (index >= 41 && index <= 56) {
		uint w = uint(rec.w);
		uint craft = (w >> 22u) & 3u;
		uint busy = w & 255u;
		uint need = index <= 46 ? 2u : index <= 50 ? 3u : 1u;
		bool more = index == 46 ? busy > 128u : index == 50 ? busy > 100u : index == 54 ? busy > 85u
			: index == 55 ? busy > 170u : index == 56 ? busy > 50u : true;
		show = show && craft == need && more;
	}
	// empty slots: all vertices on one point behind the camera, no area
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	normal = NORMAL;
	art_light = normalize((VIEW_MATRIX * vec4(HOUSE_LIGHT, 0.0)).xyz);
}

void fragment() {
	if (model_y > built_m) { discard; }
	ALBEDO = pow(COLOR.rgb * tint, vec3(2.2)); // vertex colours are sRGB
	NORMAL = normalize(normal);
	ROUGHNESS = 1.0;
}

// The sun's light from HOUSE_LIGHT instead of its own direction; colour,
// strength and the shadows of other things stay the sun's. Faces turned
// away from the real sun are not darkened by its shadow map.

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float shadow = dot(NORMAL, LIGHT) > 0.05 ? ATTENUATION : 1.0;
		DIFFUSE_LIGHT += max(dot(NORMAL, art_light), 0.0) * shadow * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	}
}

