shader_type canvas_item;

// FLASH DE CONQUÊTE (E9 §8.81) : éclat radial bref appliqué transitoirement au Polygon2D de
// remplissage d'un territoire qui vient d'être conquis. `progress` (0→1, piloté par un Tween de
// board.gd) fait naître puis s'éteindre un halo à la teinte accent du conquérant. Confiné au
// remplissage (pattern §8.30 : rien hors SubViewport pour le plateau).
uniform vec4 flash_color : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Enveloppe en cloche : 0 aux extrémités, 1 au milieu du Tween → apparition + extinction.
	float bell = sin(progress * 3.14159265);
	vec4 base = COLOR;
	COLOR = vec4(mix(base.rgb, flash_color.rgb, bell), max(base.a, flash_color.a * bell));
}
