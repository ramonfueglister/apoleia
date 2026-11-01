shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://shaders/verona_river.gdshaderinc"
uniform sampler2D corner_tex : filter_nearest, repeat_disable;
uniform ivec2 corner_origin;
uniform ivec2 corner_size;
uniform vec2 world_min;
#include "res://shaders/verona_bank.gdshaderinc"
uniform float level_h;
uniform sampler2D vr_flags_tex : filter_nearest, repeat_disable;
uniform ivec2 vr_flags_origin;
varying vec2 river_xz;
varying float cache_valid;
varying vec3 surface_world;
varying float bank_surface;
float ground(vec2 p) {
 vec2 g=(p-world_min)/.25; ivec2 t=ivec2(floor(g)); vec2 u=fract(g);
 ivec2 px=t-corner_origin;
 if(any(lessThan(px,ivec2(0))) || any(greaterThanEqual(px,corner_size))) {return 0.0;}
 vec4 c=texelFetch(corner_tex,px,0);
 float h;
 if(abs(c.x-c.z)<=abs(c.y-c.w)) {
 h=u.x>=u.y ? c.x+(c.y-c.x)*u.x+(c.z-c.y)*u.y : c.x+(c.w-c.x)*u.y+(c.z-c.w)*u.x;
 }else{
 h=u.x+u.y<=1.0 ? c.x+(c.y-c.x)*u.x+(c.w-c.x)*u.y : c.z+(c.w-c.z)*(1.0-u.x)+(c.y-c.z)*(1.0-u.y);
 }
 return h*level_h;
}

float vr_hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
vec3 vr_grass(vec2 p, vec3 c) {
	vec2 q = mod(p / 0.0238, 4096.0);
	vec2 w = max(fwidth(q), vec2(1e-5));
	float px = max(w.x, w.y); // metres a pixel
	// darker, not more saturated (s3: our #58a340 against Urbek's #3c7a32;
	// s4 too saturated, 0.57-0.61 against 0.47), back to the palette by
	// about 25 km of view
	c *= mix(vec3(0.8, 0.85, 0.8), vec3(1.0), smoothstep(0.3, 0.6, px));
	float fine = 1.0 - smoothstep(0.08, 0.2, px);
	if (fine <= 0.0) { return c; }
	// tufts: a square of 0.4 m in some cells of 0.7 m
	vec2 cq = q / 0.7;
	vec2 cell = floor(cq);
	float r = vr_hash(cell + 0.73);
	vec2 at = vec2(vr_hash(cell + 3.1), vr_hash(cell - 5.3)) * 0.4;
	vec2 in_cell = fract(cq) - at;
	bool inside = all(greaterThanEqual(in_cell, vec2(0.0))) && all(lessThan(in_cell, vec2(0.57)));
	if (inside && r < 0.05) {
		c = mix(c, c * vec3(0.6, 0.7, 0.55), fine);
	} else if (inside && r > 0.996) {
		// a flower: white, yellow or pink
		float k = vr_hash(cell + 9.9);
		vec3 bloom = k < 0.4 ? vec3(0.86, 0.85, 0.8) : k < 0.75 ? vec3(0.9, 0.78, 0.3) : vec3(0.86, 0.55, 0.66);
		c = mix(c, bloom, fine);
	}
	return c;
}
const vec3 VR_GROUND_RGB[11] = vec3[](
	vec3(0.325, 0.525, 0.298),  // meadow (Urbek grass, #73af5f on screen)
	vec3(0.451, 0.525, 0.298),  // dry grass (Urbek's yellow grass, #9baf5f)
	vec3(0.631, 0.608, 0.369),  // field (Urbek wheat, #cdc373)
	vec3(0.278, 0.447, 0.282),  // wetland
	vec3(0.400, 0.447, 0.278),  // scrub
	vec3(0.655, 0.580, 0.408),  // sand
	vec3(0.165, 0.300, 0.150),  // forest floor (between the crowns, #2c5e26-#33692c)
	vec3(0.173, 0.302, 0.224),  // conifer forest
	vec3(0.396, 0.561, 0.322),  // alpine meadow
	// rock as far out (#c4b290, light limestone): the grey #9e928a laid the
	// Abruzzo tops at 8 km out like concrete (Kritik r16), and the crests
	// changed colour between the 0.5 and the 1 km tiles
	vec3(0.561, 0.519, 0.413),  // rock
	// snow as far out (#e8e4dc): at the cotton white #f3f6f8 the tone map
	// clipped it, a riser stood 2 % below the flat (Kritik r15, Mont Blanc
	// at 8 km a blank sheet) and the shade fell lavender under the blue sky
	vec3(0.860, 0.845, 0.810)   // snow
);
vec3 vr_ground_colour(vec2 p) {
 vec2 grid=(p-world_min)/.25;ivec2 tile=ivec2(floor(grid));vec2 uv=fract(grid);
 ivec2 px=tile-vr_flags_origin;
 ivec2 size=textureSize(vr_flags_tex,0);
 if(any(lessThan(px,ivec2(0))) || px.x*2>=size.x || px.y>=size.y){return vr_grass(p,VR_GROUND_RGB[0]);}
 int bits=int(round(texelFetch(vr_flags_tex,ivec2(px.x*2,px.y),0).r));
 int g=bits&15;int alt=(bits>>4)&15;int tip=(bits>>8)-1;
 if(tip>=0){vec2 v=vec2(float(tip==1 || tip==2),float(tip>=2));if(abs(uv.x-v.x)+abs(uv.y-v.y)<1.0){g=alt;}}
 if(g>10){g=0;}
 vec3 c=VR_GROUND_RGB[g];
 if(g==0 || g==1 || g==2 || g==3 || g==8){c=vr_grass(p,c);}
 return c;
}
float vr_relief(vec3 nw,vec2 camera_right) {
 nw=nw.y<0.0 ? -nw : nw;
 vec2 right=normalize(camera_right+vec2(1e-5,0.0));vec2 back=vec2(-right.y,right.x);
 vec2 slope=nw.xz;vec2 dir=slope/max(length(slope),1e-6);
 float fr=dot(dir,right);float fb=dot(dir,back);
 float side=fr<0.0 ? .22 : -.22;float front=fb>0.0 ? -.12 : -.24;
 float t=abs(fr)-abs(fb);float corner=min(side,front);
 float shade=t>0.0 ? mix(corner,side,smoothstep(.1,.4,t)) : mix(corner,front,smoothstep(.1,.4,-t));
 float steep=mix(.4,1.0,smoothstep(.25,.7,length(slope)));
 // Fade relief on nearly flat shoulders; a hard threshold exposed the fine mesh grid.
 return 1.0+shade*steep*smoothstep(.02,.15,length(slope));
}

void vertex(){
 river_xz=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
 ivec2 px=ivec2(floor((river_xz-world_min)/.25))-corner_origin;
 cache_valid=all(greaterThanEqual(px,ivec2(0))) && all(lessThan(px,corner_size)) ? 1.0 : 0.0;
 bank_surface=COLOR.r;
 if(COLOR.r>.5 && cache_valid>.5){VERTEX.y=vr_raw_height(river_xz,ground(river_xz)); }
 surface_world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 vec2 sample_point=vr_sample(river_xz);
 if(!verona_river_active || cache_valid<.999 || (bank_surface>.5 && (abs(sample_point.x)<.075 || !vr_inside(river_xz))) || (bank_surface<.5 && abs(sample_point.x)>.0751)){discard;}
 vec3 c=vec3(.275,.498,.780);
 if(bank_surface>.5) {
  float edge=max(abs(sample_point.x)-.075,0.0);
  float height=surface_world.y-vr_values(sample_point.y).x;
  vec3 earth=vec3(.53,.49,.36);
  vec3 meadow=vr_ground_colour(river_xz);
  c=mix(earth,meadow,smoothstep(.008,.045,edge));
  // Shade the smooth bank profile, not the tiny support triangles.
  // Actual geometry and prop contacts still use the shared centre-fan mesh.
  vec3 profile=vr_values(sample_point.y);
  float radius=sample_point.x<0.0 ? profile.y : profile.z;
  float u=clamp((abs(sample_point.x)-.0875)/max(radius-.0875,.001),0.0,1.0);
  float original_height=ground(river_xz);
  float visual_height=min(original_height,mix(profile.x,original_height,u*u*(3.0-2.0*u)));
  vec3 visual_surface=vec3(river_xz.x,visual_height,river_xz.y);
  vec3 normal=normalize(cross(dFdx(visual_surface),dFdy(visual_surface)));
  if(normal.y<0.0){normal=-normal;}
  c=vb_ground_colour(river_xz,c,abs(sample_point.x));
  c*=vr_relief(normal,INV_VIEW_MATRIX[0].xz);
 }
 ALBEDO=pow(clamp(c,0.0,1.0),vec3(2.2));
 NORMAL=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
 ROUGHNESS=bank_surface>.5 ? 1.0 : .55;
}
void light(){
 float share=bank_surface>.5 ? 1.0 : .55;
 float shade=LIGHT_IS_DIRECTIONAL ? 1.0-(1.0-ATTENUATION)*share : ATTENUATION;
 DIFFUSE_LIGHT+=clamp(dot(NORMAL,LIGHT),0.0,1.0)*shade*LIGHT_COLOR/PI;
}
