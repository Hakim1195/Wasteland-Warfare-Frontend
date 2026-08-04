shader_type canvas_item;

// =================================================================================================
// FOND PANORAMIQUE DE LA TRANCHÉE (§8.139.1)
//
// ╔═ CE QU'IL CORRIGE ═══════════════════════════════════════════════════════════════════════════╗
// ║ Le décor peint était une image FIXE plaquée sur l'écran. La caméra, elle, tourne avec la visée ║
// ║ — donc le soldat adverse et les traçantes glissaient sur un paysage immobile. Le joueur bougeait║
// ║ la souris et le monde ne répondait pas : « inversé et pas du tout facile à gérer ».            ║
// ║ Ici, le décor est DÉCALÉ de l'angle exact dont la caméra a tourné. Fond et 3D redeviennent     ║
// ║ solidaires, et la souris se remet à faire ce qu'une souris fait dans un jeu en vue subjective. ║
// ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
//
// `pan` est exprimé en LARGEURS/HAUTEURS D'ÉCRAN, pas en pixels ni en UV de texture : c'est ce qui
// rend le décalage indépendant de la taille de l'image déposée. Le script le calcule comme
// `angle / champ_de_vision`, donc le fond suit la caméra au degré près.

uniform sampler2D backdrop : filter_linear_mipmap;
uniform vec2 pan = vec2(0.0);
// Tailles réelles, poussées par le script : elles reproduisent EXACTEMENT le cadrage
// `STRETCH_KEEP_ASPECT_COVERED` d'origine (§8.137) au lieu de supposer un écran 16:9.
uniform vec2 tex_size = vec2(1280.0, 720.0);
uniform vec2 rect_size = vec2(1280.0, 720.0);

// Pavage MIROIR : au-delà du bord, l'image repart en sens inverse. Le raccord est donc PARFAIT par
// construction (les deux copies partagent leur colonne de bord), sans aucune image supplémentaire à
// produire — et sur un no man's land dévasté, une ruine dupliquée en miroir ne se remarque pas.
// ⚠️ Un `repeat_enable` simple recollerait le bord DROIT au bord GAUCHE : couture franche garantie.
float mirror(float v) {
	return 1.0 - abs(2.0 * fract(v * 0.5) - 1.0);
}

void fragment() {
	// Reproduction du cadrage « couvrir » : mise à l'échelle sur la dimension contraignante, centrée.
	float scale = max(rect_size.x / tex_size.x, rect_size.y / tex_size.y);
	vec2 visible = rect_size / (tex_size * scale);      // fraction de texture réellement à l'écran
	vec2 uv = (UV - 0.5) * visible + 0.5 + pan * visible;
	COLOR = texture(backdrop, vec2(mirror(uv.x), mirror(uv.y)));
}
