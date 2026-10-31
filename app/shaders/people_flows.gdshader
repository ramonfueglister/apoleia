// The map mode «Handel» (people_flows.gd): arcs of what the dealers carried
// between the markets, with their casings, arrowheads and the markets' dots,
// in vertex colours, drawn over the land (a map's lines, not things on it).
// UV.y runs across an arc (-1 … 1) and softens its edge; arrowheads and
// dots carry 0.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

void fragment() {
	float edge = 1.0 - smoothstep(0.7, 1.0, abs(UV.y));
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ALPHA = COLOR.a * edge;
}
