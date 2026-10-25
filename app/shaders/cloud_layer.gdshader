shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
// Own bounded density-volume renderer. Texture channels contain scalar noise,
// never a cloud silhouette or pre-lit colour. Macro weather is fixed in world XZ.
uniform sampler2D cloud_weather : filter_linear, repeat_enable;
uniform sampler2D cloud_structure : filter_linear, repeat_enable;
uniform sampler3D cloud_noise : filter_linear, repeat_enable;
uniform sampler3D cloud_moments1 : filter_linear, repeat_enable;
uniform sampler3D cloud_moments2 : filter_linear, repeat_enable;
uniform sampler3D cloud_moments3 : filter_linear, repeat_enable;
uniform float cloud_shape_lod = 0.0;
uniform float cloud_erosion_lod = 0.0;
uniform vec2 cloud_origin = vec2(-125.880371, 166.792725);
uniform vec2 cloud_drift = vec2(0.0);
uniform vec3 cloud_ray_direction = vec3(0.0, -0.57735, -0.816497);
uniform vec3 cloud_sun_direction = vec3(-0.354659, 0.743145, 0.567201);
uniform vec3 cloud_sun_color = vec3(1.0, 0.940, 0.840);
uniform float cloud_sun_energy = 1.05;
uniform float cloud_bottom = 109.2;
uniform float cloud_top = 147.2;
uniform float cloud_density_multiplier = 1.0;
uniform float cloud_extinction = 0.26;
varying vec3 cloud_world_pos;

vec4 raw_moments(vec3 coordinate) {
	vec3 value = texture(cloud_noise, coordinate).rgb;
	float shape = dot(value.rg, vec2(0.76, 0.24)) - 0.5;
	float erosion = 0.13 * smoothstep(0.44, 0.68, value.b) - 0.065;
	return vec4(shape, shape * shape, erosion, erosion * erosion);
}

vec4 filtered_moments(vec3 coordinate, float lod) {
	// Interpolate first AND second moments, not independent cloud layouts.
	if (lod <= 0.0) { return raw_moments(coordinate); }
	if (lod < 1.0) { return mix(raw_moments(coordinate), texture(cloud_moments1, coordinate), lod); }
	if (lod < 2.0) { return mix(texture(cloud_moments1, coordinate), texture(cloud_moments2, coordinate), lod - 1.0); }
	return mix(texture(cloud_moments2, coordinate), texture(cloud_moments3, coordinate), lod - 2.0);
}

float expected_positive(float mean, float sigma) {
	float x = mean / max(sigma, 0.0000001);
	float t = 1.0 / (1.0 + 0.2316419 * abs(x));
	float phi = exp(-0.5 * x * x) * 0.3989422804;
	float tail = phi * (0.319381530*t - 0.356563782*t*t + 1.781477937*t*t*t - 1.821255978*t*t*t*t + 1.330274429*t*t*t*t*t);
	float cdf = x >= 0.0 ? 1.0 - tail : tail;
	return sigma * phi + mean * cdf;
}

float density_transfer(float signal, float variance) {
	if (variance < 0.0000000001) { return clamp((signal - 0.645) * 5.0, 0.0, 1.0); }
	float sigma = sqrt(variance);
	// Gaussian moment approximation of the clamped ramp, rather than clipping
	// an averaged noise value and silently deleting unresolved cloud bodies.
	return clamp(5.0 * (expected_positive(signal - 0.645, sigma) - expected_positive(signal - 0.845, sigma)), 0.0, 1.0);
}

float cloud_density(vec3 position) {
	float height = (position.y - cloud_bottom) / max(cloud_top - cloud_bottom, 0.001);
	if (height <= 0.0 || height >= 1.0) { return 0.0; }
	vec2 world_xz = position.xz - cloud_drift;
	vec2 weather_uv = (world_xz - cloud_origin) / vec2(12000.0, 8000.0) + vec2(0.5);
	float weather = texture(cloud_weather, weather_uv).r;
	float macro = smoothstep(0.46, 0.72, weather);
	if (macro < 0.005) { return 0.0; }
	vec3 coordinate = vec3(world_xz.x / 96.0, (position.y - cloud_bottom) / 72.0, world_xz.y / 96.0);
	float structure = texture(cloud_structure, world_xz / 512.0).r;
	float shape;
	float erosion;
	float variance = 0.0;
	vec3 erosion_coordinate = coordinate * vec3(1.6, 2.4, 1.6) + vec3(0.17, 0.31, 0.43);
	if (cloud_shape_lod <= 0.0 && cloud_erosion_lod <= 0.0) {
		// Exact existing groups1 near path and original RGB bytes.
		vec2 noise = texture(cloud_noise, coordinate).rg;
		shape = noise.r * 0.76 + noise.g * 0.24;
		erosion = smoothstep(0.44, 0.68, texture(cloud_noise, erosion_coordinate).b) * 0.13;
	} else {
		vec4 shape_stats = filtered_moments(coordinate, cloud_shape_lod);
		vec4 erosion_stats = filtered_moments(erosion_coordinate, cloud_erosion_lod);
		shape = shape_stats.r + 0.5;
		erosion = erosion_stats.b + 0.065;
		variance = max(shape_stats.g - shape_stats.r * shape_stats.r, 0.0) + max(erosion_stats.a - erosion_stats.b * erosion_stats.b, 0.0);
	}
	float height_penalty = pow(abs(height - 0.35) / 0.65, 1.5) * 0.13;
	float signal = shape + macro * 0.25 + (structure - 0.5) * 0.16 - height_penalty;
	signal -= erosion;
	signal -= (1.0 - smoothstep(0.35, 0.62, structure)) * 0.11;
	float density = density_transfer(signal, variance);
	float profile = smoothstep(0.0, 0.10, height) * (1.0 - smoothstep(0.70, 1.0, height));
	return density * profile * cloud_density_multiplier;
}

float light_transmission(vec3 position, vec3 sun) {
	// Dense near samples matter: starting metres/kilometres beyond the visible
	// skin would skip the local optical depth and flatten every cloud to white.
	float optical_depth = cloud_density(position + sun * 0.4) * 0.8;
	optical_depth += cloud_density(position + sun * 1.5) * 1.5;
	optical_depth += cloud_density(position + sun * 3.0) * 2.5;
	optical_depth += cloud_density(position + sun * 6.0) * 5.0;
	optical_depth += cloud_density(position + sun * 12.0) * 8.0;
	optical_depth += cloud_density(position + sun * 24.0) * 16.0;
	return exp(-optical_depth * cloud_extinction * 1.35);
}

void vertex() {
	cloud_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ray = normalize(cloud_ray_direction);
	vec3 sun = normalize(cloud_sun_direction);
	float path_length = (cloud_top - cloud_bottom) / max(-ray.y, 0.05);
	float step_length = path_length / 56.0;
	float transmission = 1.0;
	vec3 radiance = vec3(0.0);
	for (int sample_index = 0; sample_index < 56; sample_index++) {
		vec3 position = cloud_world_pos + ray * ((float(sample_index) + 0.5) * step_length);
		float density = cloud_density(position);
		if (density > 0.0004) {
			float sunlight = light_transmission(position, sun);
			vec3 illumination = vec3(0.18, 0.23, 0.31) + sunlight * cloud_sun_color * cloud_sun_energy * 0.81;
			float sample_alpha = 1.0 - exp(-density * cloud_extinction * step_length);
			radiance += transmission * sample_alpha * illumination;
			transmission *= 1.0 - sample_alpha;
			if (transmission < 0.008) { break; }
		}
	}
	float alpha = 1.0 - transmission;
	if (alpha < 0.001) { discard; }
	ALBEDO = radiance / max(alpha, 0.0001);
	ALPHA = alpha;
}
