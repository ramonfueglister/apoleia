// Authored bridge cross-section. Only the three ramp modules are graded;
// tread meshes keep their authored horizontal faces and exact metre scale.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform float grade_rise_m = 0.0;
uniform float module_length_m = 10.504201680672269;
uniform vec4 base_colour : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_texture = false;
uniform float material_roughness = 0.85;
uniform float material_metallic = 0.0;
uniform vec3 emission_colour : source_color = vec3(0.0);
uniform float emission_energy = 1.0;
void vertex() {
    float slope = grade_rise_m / module_length_m;
    VERTEX.y += (VERTEX.x + module_length_m * 0.5) * slope;
    NORMAL = normalize(vec3(NORMAL.x - slope * NORMAL.y, NORMAL.y, NORMAL.z));
}
void fragment() {
    ALBEDO = base_colour.rgb * (has_texture ? texture(base_texture, UV).rgb : vec3(1.0));
    ROUGHNESS = material_roughness;
    METALLIC = material_metallic;
    EMISSION = emission_colour * emission_energy;
}
