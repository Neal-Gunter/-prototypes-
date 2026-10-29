shader_type canvas_item;
render_mode blend_mix;

uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float perfect : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float white : hint_range(0.0, 1.0) = 0.0;
uniform vec3 dark : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec2 uv = UV;
	vec2 d = abs(uv - vec2(0.5)) * vec2(1.06, 0.84);
	float dist = length(d) * 1.5;
	float v = smoothstep(0.36, 1.02, dist);

	vec3 col = dark;
	float a = v * 0.46 + 0.04;

	// 受伤：只在边缘泛红
	float h = clamp(hurt, 0.0, 1.0);
	col = mix(col, vec3(0.55, 0.05, 0.08), h * 0.8);
	a = max(a, h * (v * 0.62 + 0.01));

	// 完美拼刀：边缘泛金
	float p = clamp(perfect, 0.0, 1.0);
	col = mix(col, vec3(1.0, 0.9, 0.62), p * 0.85);
	a = max(a, p * (v * 0.55 + 0.02));

	// 第三阶段：环境变暗，中间留一点光（像举着火把）
	float dk = clamp(darken, 0.0, 1.0);
	col = mix(col, vec3(0.0, 0.004, 0.012), dk);
	a = max(a, dk * (0.24 + v * 0.36));

	// 天雷：整屏一闪
	float w = clamp(white, 0.0, 1.0);
	col = mix(col, vec3(0.86, 0.94, 1.0), w);
	a = max(a, w * 0.50);

	COLOR = vec4(col, clamp(a, 0.0, 1.0));
}
