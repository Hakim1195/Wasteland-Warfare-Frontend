shader_type canvas_item;
// =================================================================================================
// LA TRANCHÉE FP (§8.151 LOT B) — LE FLINCH : pouls rouge DIRECTIONNEL à l'encaissement.
//
// Overlay DÉDIÉ (ColorRect monté sous le HUD, au-dessus de l'étalonnage) : on ne touche PAS à
// `trench_grade.gdshader`, propriété exclusive du LOT C — zéro couture entre les deux systèmes.
//
// ╔═ AUCUN `TIME` ICI, ET C'EST UNE RÈGLE, PAS UN OUBLI ══════════════════════════════════════════╗
// ║ `TIME` est une horloge murale : deux captures à la même frame rendraient deux images           ║
// ║ différentes — exactement la non-reproductibilité que le LOT 0 a consignée sur `trench_haze`    ║
// ║ et que le LOT E devra payer. Tout le mouvement vient donc des DEUX uniforms, poussés chaque    ║
// ║ frame par l'hôte depuis son enveloppe `_hurt_flash` (du temps de SCÈNE, décru par delta).      ║
// ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
//
// `intensity` : l'enveloppe du coup, 1 à l'impact → 0 en ~0,5 s (le rythme existant de §5.5).
// `side`      : d'où vient le coup, en ÉCRAN : -1 = bord gauche, +1 = bord droit, 0 = partout.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float side : hint_range(-1.0, 1.0) = 0.0;
// COL_DANGER de la charte — la couleur du dégât partout dans le jeu.
uniform vec4 tint : source_color = vec4(0.839216, 0.270588, 0.247059, 1.0);

void fragment() {
	// VIGNETTE : nulle au centre, pleine au cadre. La douleur mord les BORDS — le centre, là où on
	// vise et où on riposte, reste lisible : un flash plein écran serait une punition double.
	vec2 d = UV * (1.0 - UV);
	float edge = 1.0 - smoothstep(0.0, 0.16, min(d.x, d.y));
	// PONDÉRATION DIRECTIONNELLE : le bord d'où le coup est parti pèse plus lourd. À side = ±1 le
	// bord opposé tombe à ~7 % — on LIT le côté sans avoir à réfléchir ; à 0, le pouls est égal.
	float dir_w = clamp(0.62 + side * (UV.x * 2.0 - 1.0) * 0.55, 0.0, 1.2);
	// LE POULS : deux battements portés par l'ENVELOPPE elle-même (cos de 2 tours sur sa descente).
	// Un fondu linéaire se lit « écran rouge » ; deux battements se lisent « coup reçu ».
	float u = 1.0 - intensity;
	float pulse = intensity * (0.70 + 0.30 * cos(u * 12.566371));
	COLOR = vec4(tint.rgb, clamp(edge * dir_w * pulse * 0.55, 0.0, 0.55));
}
