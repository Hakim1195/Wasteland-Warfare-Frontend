shader_type canvas_item;

// ============================================================================
// TITLE HEXGRID — fond animé du Splash d'ouverture (R6, charte « Warzone Command »).
//
// Pour un ColorRect plein écran : grille hexagonale gunmetal + lignes cyan, ravivée
// par un BALAYAGE RADAR tournant. Évoque une carte tactique « topographique » sans
// aucun asset raster. Le centre respire, les bords s'assombrissent (vignette).
// Opaque (COLOR.a = 1) : sert de fond, recouvre le gunmetal de base.
// ============================================================================

uniform vec3 base_color : source_color = vec3(0.043, 0.055, 0.071); // gunmetal sombre
uniform vec3 line_color : source_color = vec3(0.211, 0.772, 0.851); // cyan tactique #36C5D9
uniform float hex_scale = 16.0;                       // densité des hexagones
uniform float line_width : hint_range(0.01, 0.25) = 0.06;
uniform float grid_alpha : hint_range(0.0, 1.0) = 0.40;
uniform float sweep_speed = 0.16;                     // vitesse du radar
uniform float vignette : hint_range(0.0, 2.0) = 0.55;

// Distance au bord de la cellule hexagonale la plus proche (0 au centre, ~0.5 au bord).
float hex_dist(vec2 p) {
	p = abs(p);
	float c = dot(p, normalize(vec2(1.0, 1.7320508)));
	c = max(c, p.x);
	return c;
}

// Repère hexagonal : renvoie le vecteur local à la cellule (xy) et son identifiant (zw).
vec4 hex_coords(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;
	vec2 id = uv - gv;
	return vec4(gv, id);
}

void fragment() {
	// Coordonnées centrées + correction d'aspect (hexagones réguliers).
	vec2 uv = SCREEN_UV - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x; // = largeur / hauteur
	uv.x *= aspect;

	vec4 hc = hex_coords(uv * hex_scale);
	vec2 gv = hc.xy;

	float hd = hex_dist(gv);
	float edge = smoothstep(0.5 - line_width, 0.5, hd); // lignes vives près du bord

	// Balayage radar : ravive les cellules juste derrière la ligne tournante.
	float ang = atan(uv.y, uv.x);
	float sweep = mod(TIME * sweep_speed, 1.0) * TAU - PI;
	float trail = mod(sweep - ang + PI, TAU) / TAU;     // 0 derrière le balayage -> 1
	float sweep_glow = pow(1.0 - trail, 6.0);

	// Atténuation radiale (centre respirant, bords sombres).
	float falloff = clamp(1.0 - length(uv) * vignette, 0.0, 1.0);

	vec3 col = base_color;
	col += line_color * edge * grid_alpha * (0.35 + 0.65 * sweep_glow) * falloff;
	col += line_color * sweep_glow * 0.12 * falloff;    // halo cyan dans la traîne

	COLOR = vec4(col, 1.0);
}
