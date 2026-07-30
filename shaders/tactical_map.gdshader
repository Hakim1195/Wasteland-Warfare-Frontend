shader_type canvas_item;

// ============================================================================
// CARTE TACTIQUE — retraitement du fond de plateau (board_bg.png).
//
// Pose en `ShaderMaterial` sur le TextureRect `BoardBackground` de board.tscn.
// Convertit la carte « Risk » cartoon multicolore (fond olive) en une carte de
// COMMANDEMENT desaturee facon « Warzone Command » : degrade gunmetal -> acier,
// fines cotes gravees + lisere cyan, et un graticule (grille) cyan tres discret.
//
// NE TOUCHE NI LA GEOMETRIE NI L'ARBORESCENCE : un simple `material` pose sur le
// noeud existant. Les 42 territoires (Area2D / polygones) restent calibres a
// l'identique sur les 2200x1530 du fond -> memes proportions. Tout est pilote
// par uniformes (reglable dans l'editeur), valeurs par defaut = rendu vise.
// ============================================================================

// Rampe duotone (ombres -> surface -> terres -> hautes lumieres). Palette charte §2.
uniform vec3 c_shadow : source_color = vec3(0.043, 0.058, 0.078); // gunmetal profond
uniform vec3 c_mid    : source_color = vec3(0.101, 0.129, 0.172); // surface secondaire
uniform vec3 c_land   : source_color = vec3(0.223, 0.290, 0.341); // terres acier
uniform vec3 c_high   : source_color = vec3(0.341, 0.521, 0.580); // hautes lumieres acier-cyan

// Accent cyan tactique (#36C5D9) — cotes + graticule.
uniform vec3 accent : source_color = vec3(0.211765, 0.772549, 0.85098);

// Part de chrominance d'origine conservee (0 = monochrome total, 1 = couleurs brutes).
uniform float chroma_keep : hint_range(0.0, 0.5) = 0.07;
// Contraste applique a la luminance avant la rampe.
uniform float contrast : hint_range(0.5, 2.0) = 1.12;

// --- Cotes gravees (detection de bord sur la luminance) ---
uniform float edge_radius : hint_range(0.0, 4.0) = 1.4;   // rayon d'echantillonnage (px)
uniform float edge_gain   : hint_range(0.0, 8.0) = 3.2;   // sensibilite du bord
uniform float edge_tint   : hint_range(0.0, 1.0) = 0.22;  // teinte cyan des cotes
uniform float edge_dark   : hint_range(0.0, 1.0) = 0.30;  // assombrissement du trait

// --- Graticule (grille blueprint) ---
uniform vec2  grid_count = vec2(24.0, 16.0);              // cellules sur l'ecran
uniform float grid_width : hint_range(0.0, 0.2) = 0.018;  // finesse du trait (fraction de cellule)
uniform float grid_alpha : hint_range(0.0, 0.3) = 0.045;  // intensite

// --- Extension oceanique 16:9 (remplit les bandes laterales avec la MER) ---
// La texture (2200x1530) est mappee sur la zone CENTRALE [pad_frac, 1-pad_frac] du
// rect ; au-dela, on prolonge la mer -> image unique et uniforme au format 16:9.
// `pad_frac = 0` -> comportement d'origine (aucune bande). Voir §8.50.
uniform float pad_frac : hint_range(0.0, 0.45) = 0.0;                  // demi-bande (fraction de largeur du rect)
uniform vec3  ocean_fallback : source_color = vec3(0.42, 0.42, 0.23); // mer de repli si le bord est une terre
uniform float ocean_sat_max : hint_range(0.0, 1.0) = 0.32;            // saturation au-dela = terre -> remplacee par la mer

// --- CYCLE DE TENSION VISUEL (§8.122, LOT E) -------------------------------
// Pousse par board.set_war_intensity() (valeur DEJA lissee par main.gd — ce shader ne lisse rien
// et ne connait ni le temps ni l'etat de jeu). 0 = rendu historique a l'identique.
uniform float war_intensity : hint_range(0.0, 1.0) = 0.0;

// PLAFONDS CHIFFRES — la lisibilite tactique est le point fort n°1 du projet : ce sont des MAXIMA,
// atteints seulement a war_intensity = 1.0. NE PAS les monter sans repasser la recette daltonienne
// (mode colorblind + motifs a intensite 1,0 doit rester parfaitement lisible).
const float TENSION_DESAT_MAX     = 0.15;  // desaturation du FOND de carte
const float TENSION_VIGNETTE_MAX  = 0.25;  // opacite de la vignette PERIPHERIQUE
const float TENSION_RED_MAX       = 0.08;  // virage des COINS vers le rouge sombre
// Rayon normalise (0 = centre, 1 = coin) a partir duquel la vignette commence a exister. Sous ce
// seuil, la ZONE CENTRALE DE JEU n'est JAMAIS assombrie — c'est un interdit explicite du cahier
// des charges, pas un reglage esthetique.
const float TENSION_VIGNETTE_INNER = 0.55;
const float TENSION_VIGNETTE_OUTER = 1.0;
const vec3  TENSION_RED = vec3(0.35, 0.05, 0.05);

// ⚠️ CE SHADER NE TOUCHE PAS aux remplissages ni aux liseres de territoires : ils vivent dans
// territory_overlay.gdshader (Sprite2D distinct, dessine PAR-DESSUS ce fond). C'est ce qui garantit
// que la tension ne peut pas degrader le contraste des couleurs de joueur ni du telegraphe.

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	// Remap horizontal : zone centrale = texture ; bandes = prolongement de la mer
	// (clamp du bord, ou mer de repli si le bord echantillonne est une terre).
	float tx = (UV.x - pad_frac) / max(1.0 - 2.0 * pad_frac, 1e-4);
	bool in_pad = (tx < 0.0 || tx > 1.0);
	vec2 tuv = vec2(clamp(tx, 0.0, 1.0), UV.y);
	vec4 tex = texture(TEXTURE, tuv);

	if (in_pad) {
		float mx = max(max(tex.r, tex.g), tex.b);
		float mn = min(min(tex.r, tex.g), tex.b);
		float sat = mx > 1e-4 ? (mx - mn) / mx : 0.0;
		if (sat > ocean_sat_max) {
			tex = vec4(ocean_fallback, 1.0); // bord = terre -> on force la mer
		}
	}

	// Luminance + contraste centre sur 0.5.
	float L = lum(tex.rgb);
	L = clamp((L - 0.5) * contrast + 0.5, 0.0, 1.0);

	// Rampe duotone gunmetal -> acier -> cyan.
	vec3 grad = mix(c_shadow, c_mid,  smoothstep(0.0,  0.40, L));
	grad      = mix(grad,     c_land, smoothstep(0.34, 0.70, L));
	grad      = mix(grad,     c_high, smoothstep(0.66, 1.0,  L));

	// Reinjection d'un soupcon de chrominance d'origine (differenciation « intel »).
	vec3 chroma = tex.rgb - vec3(lum(tex.rgb));
	grad += chroma * chroma_keep;

	// Cotes gravees : magnitude du gradient de luminance (4 voisins). Echantillonne
	// en `tuv` (espace texture remappe) ; supprimees dans les bandes -> mer uniforme.
	vec2 px = TEXTURE_PIXEL_SIZE * edge_radius;
	float lx = lum(texture(TEXTURE, tuv + vec2(px.x, 0.0)).rgb)
			 - lum(texture(TEXTURE, tuv - vec2(px.x, 0.0)).rgb);
	float ly = lum(texture(TEXTURE, tuv + vec2(0.0, px.y)).rgb)
			 - lum(texture(TEXTURE, tuv - vec2(0.0, px.y)).rgb);
	float edge = clamp(length(vec2(lx, ly)) * edge_gain, 0.0, 1.0);
	if (in_pad) { edge = 0.0; }
	grad = mix(grad, grad * (1.0 - edge_dark), edge);     // creuse le trait
	grad += accent * edge * edge_tint;                    // lisere cyan

	// Graticule cyan tres discret.
	vec2 gf = fract(UV * grid_count);
	vec2 gd = min(gf, 1.0 - gf);
	float gline = min(gd.x, gd.y);
	float grid = (1.0 - smoothstep(0.0, grid_width, gline)) * grid_alpha;
	grad += accent * grid;

	// --- CYCLE DE TENSION (§8.122, LOT E) : la carte « se ferme » a mesure que la partie converge.
	// Applique EN DERNIER, apres les cotes et le graticule : la tension modifie l'ambiance du fond,
	// jamais la lecture des informations posees dessus.
	if (war_intensity > 0.0) {
		// Distance normalisee au centre : 0 au centre, ~0.71 au milieu d'un bord, 1.0 dans un coin.
		vec2 d = (UV - vec2(0.5)) * 2.0;
		float r = length(d) * 0.70710678;
		float edge = smoothstep(TENSION_VIGNETTE_INNER, TENSION_VIGNETTE_OUTER, r);
		// 1) Desaturation globale du fond (plafonnee) — la couleur quitte le monde.
		float g = lum(grad);
		grad = mix(grad, vec3(g), TENSION_DESAT_MAX * war_intensity);
		// 2) Virage chromatique des COINS vers le rouge sombre (nul au centre : facteur `edge`).
		grad = mix(grad, TENSION_RED, TENSION_RED_MAX * war_intensity * edge);
		// 3) Vignette peripherique. `edge` valant 0 sous TENSION_VIGNETTE_INNER, le centre du
		//    plateau conserve EXACTEMENT sa luminosite d'origine, a toute intensite.
		grad *= 1.0 - TENSION_VIGNETTE_MAX * war_intensity * edge;
	}

	COLOR = vec4(clamp(grad, 0.0, 1.0), tex.a);
}
