shader_type canvas_item;

// ============================================================================
// CRT / SCANLINES — Post-processing du PLATEAU (SubViewport `MapContent`).
// Effet « vieil ecran de bunker » : lit l'ecran deja rendu derriere lui (board
// + cendres) et applique scanlines defilantes, vignette, courbure « barrel » et
// une tres subtile aberration chromatique.
//
// CONFINEMENT : ce shader vit sur un ColorRect place DANS le SubViewport (via un
// CanvasLayer pour echapper a la TacticalCamera). L'UI flottante (HUD) etant
// HORS du SubViewport, elle n'est jamais lue par `screen_texture` -> elle reste
// parfaitement nette. Voir CONTEXTE.md §8.30.
//
// ALPHA PRESERVE : le SubViewport a `transparent_bg = true` ; les bandes
// laterales non couvertes par le board (camera plein plateau) doivent rester
// transparentes -> on ressort l'alpha de l'ecran (g.a), annule hors-cadre.
// ============================================================================

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// --- Defaults recalibres « glassmorphism militaire » : rappel materiel subtil, lisibilite
//     de la carte preservee. (Les valeurs reellement appliquees sont celles du .tres ; ces
//     defaults servent de repli/source pour tout nouveau materiau cree depuis ce shader.)
// Intensite des scanlines (0 = aucune, 1 = tres marquees). Abaissee : lignes a peine perceptibles.
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.08;
// Densite des lignes (~ nombre de scanlines sur la hauteur d'ecran).
uniform float scanline_count : hint_range(100.0, 1400.0) = 650.0;
// Vitesse de defilement vertical des scanlines. Quasi figee : le mouvement etait la 1ere cause de fatigue.
uniform float scanline_scroll : hint_range(0.0, 60.0) = 2.0;
// Force de la vignette (assombrissement des bords). Adoucie : bordure noire discrete, bords non ecrases.
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.18;
// Decalage de l'aberration chromatique (fraction d'ecran). ~1px @1080p : presque imperceptible.
uniform float aberration : hint_range(0.0, 0.01) = 0.0006;
// Courbure « barrel » de la dalle CRT (0 = ecran plat). Reduite : plateau quasi plat, coins a peine arrondis.
uniform float curvature : hint_range(0.0, 0.5) = 0.02;

// Deforme legerement l'UV pour simuler la courbure d'un tube cathodique.
vec2 barrel(vec2 uv, float amt) {
	vec2 cc = uv - 0.5;
	float dist = dot(cc, cc);
	return uv + cc * dist * amt;
}

void fragment() {
	// Courbure de la dalle.
	vec2 uv = barrel(SCREEN_UV, curvature);

	// Aberration chromatique : R et B decales horizontalement, G au centre.
	float r = texture(screen_texture, uv + vec2(aberration, 0.0)).r;
	vec4 g = texture(screen_texture, uv);
	float b = texture(screen_texture, uv - vec2(aberration, 0.0)).b;
	vec3 col = vec3(r, g.g, b);

	// Scanlines horizontales defilantes.
	float line = sin((uv.y * scanline_count) + (TIME * scanline_scroll));
	float scan = 1.0 - scanline_intensity * (0.5 - 0.5 * line);
	col *= scan;

	// Vignette radiale douce.
	vec2 vc = uv - 0.5;
	float vig = 1.0 - vignette_strength * dot(vc, vc);
	col *= clamp(vig, 0.0, 1.0);

	// La courbure peut tirer l'UV hors [0,1] -> on annule l'alpha hors-cadre
	// (coins arrondis facon CRT, fond transparent preserve).
	float in_bounds = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);

	// On PRESERVE l'alpha de l'ecran (transparent_bg du SubViewport).
	COLOR = vec4(col, g.a * in_bounds);
}
