shader_type canvas_item;

// =================================================================================================
// ÉTALONNAGE UNIFIANT DE LA TRANCHÉE (§8.139, LOT D)
//
// ╔═ CE QUE CE SHADER CORRIGE, ET POURQUOI IL EST INDISPENSABLE ══════════════════════════════════╗
// ║ La vue FP empile QUATRE sources d'image qui n'ont RIEN en commun : un décor peint par un       ║
// ║ modèle génératif, un blockout 3D éclairé par Godot, des sprites détourés peints dans une autre ║
// ║ passe, et un viewmodel 2D. Rien ne garantit qu'elles partagent une lumière — et la session     ║
// ║ précédente l'a mesuré sur deux tirages VOISINS (« ciel de crépuscule chaud au-dessus d'un sol  ║
// ║ bleu-blanc qui se lisait givre »). Un étalonnage appliqué PAR-DESSUS TOUT ramène les quatre    ║
// ║ couches vers une seule dominante : c'est le seul correctif qui agisse quoi qu'aient produit    ║
// ║ les générations, sans avoir à les régénérer.                                                   ║
// ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
//
// ⚠️ IL LIT L'ÉCRAN (`hint_screen_texture`) : il doit donc être MONTÉ AU-DESSUS de tout ce qu'il
// doit teinter (décor, monde 3D, ambiance, viewmodel) et EN DESSOUS du HUD — un HUD étalonné
// perdrait le cyan de la charte, qui est une CONVENTION DE LECTURE et non une image.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Dominante gunmetal de la charte (§2). Volontairement FROIDE : elle recule le décor et laisse le
// cyan du HUD, qui n'est pas étalonné, ressortir comme la seule couleur « interface » de l'écran.
uniform vec3 tint : source_color = vec3(0.42, 0.48, 0.55);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.16;
uniform float desaturate : hint_range(0.0, 1.0) = 0.12;
uniform float contrast : hint_range(0.5, 1.5) = 1.06;
uniform float vignette : hint_range(0.0, 1.0) = 0.30;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(luma), desaturate);
	c = mix(c, c * tint * 2.0, tint_amount);
	c = clamp((c - 0.5) * contrast + 0.5, 0.0, 1.0);
	// Vignette : elle ne commence qu'au-delà de 45 % du rayon, pour ne JAMAIS assombrir le centre —
	// c'est là que se trouve la cible, et une cible moins lisible serait un défaut de jeu, pas de goût.
	float d = distance(UV, vec2(0.5)) * 1.4142;
	c *= 1.0 - vignette * smoothstep(0.45, 1.0, d);
	COLOR = vec4(c, 1.0);
}
