shader_type canvas_item;
// Плёночное зерно поверх всего экрана — рвёт цветовые полосы (banding)
// на красных свечениях и градиентах. Общий шейдер для титульника и игры.
uniform sampler2D screen_tex : hint_screen_texture;
uniform float grain_strength : hint_range(0.0, 0.05) = 0.010;
uniform float dark_boost : hint_range(0.0, 0.07) = 0.024;
uniform float red_boost : hint_range(0.0, 0.07) = 0.045;
uniform float mid_boost : hint_range(0.0, 0.05) = 0.014;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// Упорядоченный дизеринг 4x4 (Bayer) — классический способ разбить
// плавные градиенты, где плёночный шум слаб.
float bayer4(vec2 px) {
	ivec2 c = ivec2(mod(px, 4.0));
	int b[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(b[c.y * 4 + c.x]) / 16.0) - 0.5;
}

void fragment() {
	vec4 scene = texture(screen_tex, SCREEN_UV);
	float lum = dot(scene.rgb, vec3(0.299, 0.587, 0.114));
	// Сильнее в тёмных, красных и среднеярких участках (где полосы заметнее).
	float strength = grain_strength
		+ dark_boost * (1.0 - lum) * (1.0 - lum)
		+ red_boost * scene.r * scene.r
		+ mid_boost * max(0.0, 1.0 - abs(lum - 0.42) * 2.4);
	// FRAGCOORD — зерно привязано к пикселю, работает на любом разрешении.
	vec2 uv = FRAGCOORD.xy;
	float t = TIME * 0.7;
	float n = hash21(uv + vec2(t, -t * 1.1));
	float n2 = hash21(uv * 1.71 + vec2(-t * 0.9, t * 0.8));
	float n3 = hash21(uv * 3.13 + vec2(t * 0.6, -t * 1.3));
	float d = (n * 0.42 + n2 * 0.34 + n3 * 0.24) * 2.0 - 1.0;
	float db = bayer4(uv);
	// Шум + дизер: шум анимирован (киноплёнка), дизер рвёт градиенты.
	COLOR = vec4(scene.rgb + vec3(d) * strength + vec3(db) * strength * 1.6, 1.0);
}
