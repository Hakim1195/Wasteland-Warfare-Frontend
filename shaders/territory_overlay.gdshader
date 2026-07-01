shader_type canvas_item;

// ============================================================================
// OVERLAY DES TERRITOIRES — colore/contoure les territoires en suivant la
// CARTE-ID (territory_id_map.png), donc les VRAIES frontieres PEINTES de la
// carte de fond (et non les polygones-hitbox). Voir §8.51.
//
// L'index du territoire (1..TCOUNT) est encode dans le canal ROUGE de la texture
// (chargee BRUTE en NEAREST par board.gd -> valeurs exactes). La couleur de
// chaque territoire (rgb = teinte, a = alpha de remplissage) est poussee par
// board.gd dans `territory_colors`. Les BORDS (changement d'index entre pixels
// voisins) sont surbrillants -> contour neon le long des cotes reelles.
// ============================================================================

const int TCOUNT = 42;
// Carte-ID (canal rouge = index). Uniforme (donc accessible dans les fonctions, contrairement
// au built-in TEXTURE) ; filtre NEAREST -> valeurs exactes. Poussee par board.gd.
uniform sampler2D id_map : filter_nearest;
uniform vec4 territory_colors[TCOUNT];                 // index i -> territory_colors[i-1] (rgb + alpha de remplissage)
uniform float territory_edge[TCOUNT];                  // alpha du contour neon par territoire
uniform float territory_mine[TCOUNT];                  // 1 = territoire du JOUEUR LOCAL (porte une ombre de relief)
uniform float border_width : hint_range(0.0, 4.0) = 1.4;   // epaisseur du contour (px texture)
uniform float border_boost : hint_range(1.0, 4.0) = 2.3;   // surbrillance du contour
// --- Relief : ombre portee des territoires possedes par MOI (§8.52, reintroduite sur les vraies cotes) ---
uniform vec2 shadow_offset = vec2(5.0, 8.0);           // decalage de l'ombre (px carte-ID : droite + bas)
uniform float shadow_alpha : hint_range(0.0, 1.0) = 0.5;

int idx_at(vec2 uv) {
	return int(floor(texture(id_map, uv).r * 255.0 + 0.5));
}

bool is_mine(int idx) {
	return idx >= 1 && idx <= TCOUNT && territory_mine[idx - 1] > 0.5;
}

void fragment() {
	int idx = idx_at(UV);

	// --- Rendu de base : remplissage + contour neon du territoire (ou transparent). ---
	vec4 outc = vec4(0.0);
	if (idx >= 1 && idx <= TCOUNT) {
		vec4 col = territory_colors[idx - 1];
		vec2 px = TEXTURE_PIXEL_SIZE * border_width;
		bool edge = idx_at(UV + vec2(px.x, 0.0)) != idx
			|| idx_at(UV - vec2(px.x, 0.0)) != idx
			|| idx_at(UV + vec2(0.0, px.y)) != idx
			|| idx_at(UV - vec2(0.0, px.y)) != idx;
		vec3 rgb = col.rgb;
		float a = col.a;
		if (edge) {
			rgb = clamp(col.rgb * border_boost, 0.0, 1.0);
			a = max(a, territory_edge[idx - 1]);   // contour neon (mien vif / adverse attenue / neutre 0)
		}
		outc = vec4(rgb, a);
	}

	// --- Relief : ombre portee de MES territoires (silhouette decalee de shadow_offset, DERRIERE
	//     le remplissage) -> ils paraissent souleves. Suit les vraies cotes (carte-ID). ---
	if (!is_mine(idx)) {
		if (is_mine(idx_at(UV - shadow_offset * TEXTURE_PIXEL_SIZE))) {
			outc = vec4(mix(outc.rgb, vec3(0.0), shadow_alpha), max(outc.a, shadow_alpha));
		}
	}

	COLOR = outc;
}
