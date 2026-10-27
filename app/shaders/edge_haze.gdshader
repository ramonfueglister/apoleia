shader_type spatial;
// Fades the map edge into the background colour (landscape.gd _build_edge_haze).
// The fade width follows the view (edge_fade, km), so the overview gets a
// broad haze and close views a narrow one.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 haze_color : source_color = vec4(0.624,0.761,0.839,1.0);
uniform vec4 world_rect=vec4(0.0,0.0,1.0,1.0);
uniform float edge_fade=180.0;
varying vec2 world_xz;
void vertex() {
    world_xz=VERTEX.xz;
}
void fragment() {
    vec2 low=world_xz-world_rect.xy;
    vec2 high=world_rect.xy+world_rect.zw-world_xz;
    float inside=min(min(low.x,low.y),min(high.x,high.y));
    ALBEDO=haze_color.rgb;
    ALPHA=1.0-smoothstep(0.0,1.0,clamp(inside/max(edge_fade,1.0),0.0,1.0));
}
