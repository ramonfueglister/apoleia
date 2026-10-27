shader_type spatial;
// Fades the map edge into the background colour (landscape.gd _build_edge_haze).
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 haze_color : source_color = vec4(0.624,0.761,0.839,1.0);
void fragment() {
    ALBEDO=haze_color.rgb;
    ALPHA=smoothstep(0.0,1.0,COLOR.a);
}
