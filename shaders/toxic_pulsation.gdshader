shader_type canvas_item;

// ============================================================================
// ZONE RADIOACTIVE — pulsation toxique d'un territoire contamine (§8.27/§8.30).
//
// Applique en `ShaderMaterial` sur le `Polygon2D` de remplissage d'un territoire
// par `board.gd` quand il ENTRE dans la zone ; retire (`material = null`) quand
// il en SORT. Fait pulser le remplissage entre l'accent de la faction
// proprietaire (`base_color`, pousse par board.gd) et le vert nucleaire
// (`rad_color` = #7fff00) via `sin(TIME * pulse_speed)`.
//
// L'opacite est pilotee par `fill_alpha` (defaut 0.62 = coherent avec l'ancien
// remplissage contamine de board.gd) ; le shader ECRASE la couleur du vertex
// -> board.gd n'a pas a teinter le Polygon2D quand le shader est actif.
// ============================================================================

// Couleur de base = accent du proprietaire (pousse par board.gd au runtime).
uniform vec4 base_color : source_color = vec4(0.35, 0.36, 0.32, 1.0);
// Couleur radioactive (vert nucleaire #7fff00 par defaut).
uniform vec4 rad_color : source_color = vec4(0.498039, 1.0, 0.0, 1.0);
// Vitesse de pulsation.
uniform float pulse_speed : hint_range(0.1, 12.0) = 3.0;
// Bornes du melange vers le vert (0 = base, 1 = full vert) -> pulse entre min/max.
uniform float pulse_min : hint_range(0.0, 1.0) = 0.25;
uniform float pulse_max : hint_range(0.0, 1.0) = 0.85;
// Opacite globale du remplissage contamine.
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	// sin ramene dans [0,1] puis mappe entre pulse_min et pulse_max.
	float t = 0.5 + 0.5 * sin(TIME * pulse_speed);
	float mix_amount = mix(pulse_min, pulse_max, t);
	vec3 col = mix(base_color.rgb, rad_color.rgb, mix_amount);
	COLOR = vec4(col, fill_alpha);
}
