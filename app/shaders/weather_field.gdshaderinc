// Shared weather field: cloud cover, rain and storm at a world XZ position.
// Mirrored on the CPU in weather_system.gd (sample_field); keep both in sync.
uniform sampler2D weather_noise : filter_linear, repeat_enable;
uniform float noise_period = 1100.0;
uniform vec2 air_drift;
uniform vec4 weather_state = vec4(0.2, 0.3, 0.0, 0.0); // cover, noise amplitude, rain, storm
uniform vec4 cell_shape[16]; // centre x, centre z, radius along wind, radius across
uniform vec4 cell_param[16]; // along-axis x, along-axis z, strength, kind (0 cumulus, 1 front, 2 storm)
uniform int cell_count = 0;
uniform float earth_km = 6371.0088;

float weather_climate(vec2 p) {
	float lat = 41.0 - degrees(p.y / earth_km);
	// Dry North Africa, clear-ish Mediterranean, wetter north of the Alps.
	return mix(0.15, 1.0, smoothstep(30.0, 37.0, lat)) * mix(1.0, 1.5, smoothstep(44.0, 54.0, lat));
}

vec3 weather_field(vec2 p) {
	float n = texture(weather_noise, (p - air_drift) / noise_period).r;
	float climate = weather_climate(p);
	float cover = clamp(weather_state.x + (n - 0.5) * weather_state.y * 2.0, 0.0, 1.0) * climate;
	float rain = weather_state.z * smoothstep(0.45, 0.85, cover);
	float storm = weather_state.w * smoothstep(0.5, 0.9, cover);
	float cell_climate = min(climate * 1.2, 1.0);
	for (int i = 0; i < 16; i++) {
		if (i >= cell_count) { break; }
		vec2 local = p - cell_shape[i].xy;
		vec2 axis = cell_param[i].xy;
		float along = dot(local, axis) / cell_shape[i].z;
		float across = dot(local, vec2(-axis.y, axis.x)) / cell_shape[i].w;
		float b = cell_param[i].z * (1.0 - smoothstep(0.35, 1.0, length(vec2(along, across))));
		b *= (0.55 + 0.9 * n) * cell_climate;
		float kind = cell_param[i].w;
		cover += b * (kind < 0.5 ? 0.6 : (kind > 1.5 ? 1.6 : 1.0));
		if (kind > 0.5) { rain += b * 0.9 * smoothstep(0.2, 0.6, b); }
		if (kind > 1.5) { storm += b * smoothstep(0.3, 0.8, b); }
	}
	return clamp(vec3(cover, rain, storm), 0.0, 1.0);
}
