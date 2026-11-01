// Authored PBR building on exactly the same terrace as a city-plan lot.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "res://shaders/tile_terrain.gdshaderinc"
uniform vec2 lot_centre;
uniform float model_km_per_m = 0.0238;
uniform vec4 base_colour : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_texture = false;
uniform float material_roughness = 0.85;
uniform float material_metallic = 0.0;
uniform bool fixed_ground = false;
uniform bool whole_plot = false;
uniform bool foundation = false;
uniform vec4 plot_rect;
uniform vec3 emission_colour : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
void vertex() {
    if (!fixed_ground) {
        ivec2 first = ivec2(floor((lot_centre - world_min) / tile_km));
        ivec2 last = first;
        if (whole_plot) {
            first = ivec2(floor((plot_rect.xy - world_min + vec2(0.0001)) / tile_km));
            last = ivec2(floor((plot_rect.zw - world_min - vec2(0.0001)) / tile_km));
        }
        float top = -1e6;
        float bottom = 1e6;
        for (int j = 0; j < 5; j++) {
            for (int i = 0; i < 5; i++) {
                ivec2 tile = first + ivec2(i, j);
                if (tile.x <= last.x && tile.y <= last.y) {
                    vec4 c = tt_corners_cached(tile);
                    top = max(top, max(max(c.x, c.y), max(c.z, c.w)));
                    bottom = min(bottom, min(min(c.x, c.y), min(c.z, c.w)));
                }
            }
        }
        float height = top * level_h + (sub_tiles ? 0.25 * model_km_per_m : 0.0);
        if (foundation) {
            float y = VERTEX.y > 0.0 ? height : bottom * level_h - 0.002;
            VERTEX.y = (y - MODEL_MATRIX[3].y) / length(MODEL_MATRIX[1].xyz);
        } else {
            VERTEX.y += (height - MODEL_MATRIX[3].y) / length(MODEL_MATRIX[1].xyz);
        }
    }
}
void fragment() {
    ALBEDO = base_colour.rgb * (has_texture ? texture(base_texture, UV).rgb : vec3(1.0));
    ROUGHNESS = material_roughness;
    METALLIC = material_metallic;
    EMISSION = emission_colour * emission_energy;
}
