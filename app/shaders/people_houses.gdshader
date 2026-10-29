// A house for every village household (sim/src/view.rs Houses), drawn with
// the house mesh and look of the tile terrain (tile_props.gdshader) at the
// household's house spot. The houses near the camera are listed nearest
// first (ApoleiaPeople.houses_near) into `list_tex`; three MultiMeshes with the
// voxel farmhouse in three levels of detail (scripts/voxel/farmhouse.gd) draw
// consecutive runs of that list from `list_offset`, once for each of the
// farmhouse's three builds (`variant`), each lot showing one of them. The
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
const uint VARIANTS = 3u;

varying vec3 tint;
varying vec3 normal; // the face's own normal, also on mirrored (back-facing) faces
varying vec3 art_light; // ART_LIGHT in view space
const vec3 ART_LIGHT = vec3(-0.45, 0.72, 0.53); // towards the SimCity light, world (tile_terrain.gdshader)
// plaster (cream, pink, ochre, warm white) and shutters of the town buildings (prototypes/colosseum/city_buildings.gd), sRGB; only their ratios to the first tint the farmhouse (farmhouse.gd PLASTER)
const vec3 WALLS[4] = vec3[](vec3(0.922, 0.875, 0.784), vec3(0.925, 0.769, 0.659), vec3(0.851, 0.706, 0.471), vec3(0.937, 0.886, 0.784));
const vec3 SHUTTER_GREEN = vec3(0.373, 0.498, 0.275);
const vec3 SHUTTER_BROWN = vec3(0.604, 0.353, 0.227);
// roof tiles by farm: as built, rusty, a little lighter or dark red
// (Caesar III terracotta, never orange)
const vec3 ROOFS[4] = vec3[](vec3(1.0), vec3(1.02, 0.94, 0.8), vec3(1.06, 1.02, 0.96), vec3(0.92, 0.82, 0.74));

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
	tint = vec3(st.y);
	// each farm its own plaster (cream, pink, ochre, as the town's
	// WALLS) and shutters (green or brown), by the palette index in UV.y
	// (scripts/voxel/farmhouse.gd); the vertex colour keeps its corner shading
	ivec2 lot = ivec2(floor((p - world_min) / DOT_LOT_KM));
	uint key = dot_hash(uint(lot.x) * 0x2545f491u ^ uint(lot.y) * 0x9e3779b9u);
	// one of the three builds per lot, drawn by its own MultiMesh
	show = show && int((key >> 12u) % VARIANTS) == variant;
	int index = int(UV.y + 0.5);
	if (index == 1 || index == 2 || index == 27) {
		tint *= WALLS[key % 4u] / WALLS[0];
	} else if (index == 20) {
		tint *= (key & 16u) != 0u ? vec3(1.0) : SHUTTER_BROWN / SHUTTER_GREEN;
	} else if ((index >= 4 && index <= 6) || (index >= 29 && index <= 36)) {
		tint *= ROOFS[(key >> 9u) % 4u];
	}
	// each roof slope lit by the way it faces once the house is turned
	// (farmhouse.gd _tile): turned to the sun (west) a little lighter,
	// away from it (east) darker, so the two sides of a roof differ even
	// where only the treads of the tile steps show
	if (index >= 29 && index <= 36) {
		int d = (index - 29) / 2;
		vec2 face = turn * (d == 0 ? vec2(1.0, 0.0) : d == 1 ? vec2(-1.0, 0.0) : d == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0));
		tint *= face.x < -0.5 ? 1.06 : face.x > 0.5 ? 0.86 : face.y > 0.5 ? 1.0 : 0.93;
	}
	// not every farm has the cypresses, the olive tree or the haystack
	// on its lot (farmhouse.gd _lot)
	bool cypress = index == 21 || index == 22;
	bool olive = index >= 23 && index <= 25;
	if ((cypress && (key & 96u) == 0u) || (olive && (key & 128u) == 0u) || ((index == 26 || index == 28) && (key & 256u) == 0u)) {
		show = false;
	}
	// empty slots: all vertices on one point behind the camera, no area
	VERTEX = show ? (VIEW_MATRIX * vec4(world, 1.0)).xyz : vec3(0.0, 0.0, 1.0e6);
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	normal = NORMAL;
	art_light = normalize((VIEW_MATRIX * vec4(ART_LIGHT, 0.0)).xyz);
}

void fragment() {
	ALBEDO = pow(COLOR.rgb * tint, vec3(2.2)); // vertex colours are sRGB
	NORMAL = normalize(normal);
	ROUGHNESS = 1.0;
}

// The sun's light from the terrain's fixed SimCity direction (south-west,
// ART_LIGHT) instead of its own, so the walls turned
// to the camera are the lit ones, as in Urbek and SimCity 2000; colour,
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

