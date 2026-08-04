shader_type canvas_item;

// =================================================================================================
// NAPPE DE BRUME DE PROFONDEUR (§8.139, LOT D)
//
// Une nappe = un bruit qui défile horizontalement, enveloppé verticalement pour que la bande n'ait
// aucun bord franc. Deux nappes superposées à des vitesses et des échelles différentes suffisent à
// donner de l'air aux 35 m du no man's land — et surtout à ASSEOIR le sprite du soldat dans le
// décor peint : sans un voile qui passe devant ses pieds, un billboard détouré reste un autocollant.
//
// ⚠️⚠️ LE DÉFILEMENT VIENT D'UN UNIFORME `scroll`, JAMAIS DE `TIME`. `TIME` continue de courir quoi
// qu'on fasse : un confort « mouvement réduit » écrit avec `TIME` ne fige RIEN, il se contente de
// mentir. Ici c'est le script qui avance `scroll`, donc il lui suffit de cesser de l'avancer.

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float scroll = 0.0;
uniform float scale_x = 2.0;
uniform vec3 haze_color : source_color = vec3(0.66, 0.69, 0.72);
uniform float strength : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	float n = texture(noise_tex, vec2(UV.x * scale_x + scroll, UV.y * 0.5)).r;
	// Enveloppe au carré d'un sinus : la nappe est dense en son milieu et STRICTEMENT nulle sur ses
	// deux bords. C'est ce qui l'empêche de se lire comme un bandeau collé sur l'image.
	float env = sin(UV.y * PI);
	COLOR = vec4(haze_color, strength * n * env * env);
}
