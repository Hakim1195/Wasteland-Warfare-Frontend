shader_type canvas_item;

// Fond du Rapport Post-Opération (§4 Warzone Command) : FLOU GAUSSIEN du framebuffer derrière le
// panneau (arène gelée, HUD fondu) + assombrissement vers le gunmetal. Lit l'écran déjà rendu via
// hint_screen_texture (même technique que crt_board.gdshader). Noyau 5x5 pondéré (gaussien approximé).
uniform float blur_amount : hint_range(0.0, 6.0) = 3.0;
uniform float darken : hint_range(0.0, 1.0) = 0.55;
uniform vec4 tint : source_color = vec4(0.058824, 0.07451, 0.094118, 1.0);

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * blur_amount;
	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = 1.0 / (1.0 + float(x * x + y * y));
			col += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * ps).rgb * w;
			total += w;
		}
	}
	col /= total;
	// Assombrissement + teinte gunmetal froide (lisibilité du panneau par-dessus).
	col = mix(col, tint.rgb, darken);
	COLOR = vec4(col, 1.0);
}
