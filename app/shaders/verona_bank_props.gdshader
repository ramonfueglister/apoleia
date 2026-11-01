// Original metre meshes conform vertically to the same terrain triangles.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/verona_river.gdshaderinc"
uniform sampler2D corner_tex : filter_nearest, repeat_disable;
uniform ivec2 corner_origin;
uniform ivec2 corner_size;
uniform vec2 world_min;
uniform float level_h = 0.15;
uniform bool bank_active = false;
float vb_height(vec2 p) {
	vec2 g = (p-world_min)/0.25;
	ivec2 t = ivec2(floor(g));
	vec2 uv = fract(g);
	ivec2 px = t-corner_origin;
	vec4 c = texelFetch(corner_tex,clamp(px,ivec2(0),corner_size-ivec2(1)),0);
	float h;
	if (abs(c.x-c.z)<=abs(c.y-c.w)) {
		h=uv.x>=uv.y ? c.x+(c.y-c.x)*uv.x+(c.z-c.y)*uv.y : c.x+(c.w-c.x)*uv.y+(c.z-c.w)*uv.x;
	} else {
		h=uv.x+uv.y<=1.0 ? c.x+(c.y-c.x)*uv.x+(c.w-c.x)*uv.y : c.z+(c.w-c.z)*(1.0-uv.x)+(c.y-c.z)*(1.0-uv.y);
	}
	return vr_corrected_height(p,h*level_h);
}
void vertex() {
	vec3 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float eps=0.00005;
	float dx=(vb_height(p.xz+vec2(eps,0.0))-vb_height(p.xz-vec2(eps,0.0)))/(2.0*eps);
	float dz=(vb_height(p.xz+vec2(0.0,eps))-vb_height(p.xz-vec2(0.0,eps)))/(2.0*eps);
	VERTEX.y += vb_height(p.xz)/0.0238;
	vec3 n=normalize(MODEL_NORMAL_MATRIX*NORMAL);
	n=normalize(vec3(n.x-dx*n.y,n.y,n.z-dz*n.y));
	NORMAL=normalize(inverse(MODEL_NORMAL_MATRIX)*n);
	if (!bank_active) { VERTEX=vec3(0.0,0.0,1.0e7); }
}
void fragment() { ALBEDO=COLOR.rgb; ROUGHNESS=1.0; }
