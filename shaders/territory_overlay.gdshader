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
// TELEGRAPHE de zone (G1 §8.62) : 1 = territoire ANNONCE pour la PROCHAINE zone radioactive ->
// liseré OR/ambre PULSANT le long des vraies cotes (distinct du vert toxique de la zone courante).
uniform float territory_forecast[TCOUNT];
uniform vec3 forecast_color = vec3(1.0, 0.75, 0.1);    // or/ambre (charte Warzone Command)
uniform float forecast_pulse_speed = 2.6;              // vitesse de pulsation (rad/s)
uniform float forecast_width : hint_range(0.0, 6.0) = 2.4;  // liseré plus epais que le contour normal
// SURLIGNAGE DES CIBLES VALIDES (E7 §8.79) : 1 = cible d'attaque legale -> liseré CRAMOISI PULSANT
// (meme mecanique que le télégraphe, teinte distincte). `attack_dim` > 0 quand une source est
// selectionnee -> les territoires NI cibles NI a moi sont legerement desatures (focus sur l'action).
uniform float territory_attack[TCOUNT];
uniform vec3 attack_color = vec3(0.85, 0.15, 0.15);    // cramoisi (charte danger)
uniform float attack_width : hint_range(0.0, 6.0) = 2.4;
uniform float attack_dim : hint_range(0.0, 1.0) = 0.0; // 0 = pas de contexte d'attaque
// MODE DALTONIEN (E10 §8.82) : la couleur seule ne suffit jamais -> motif par INDEX de joueur
// (1=rayures ⟋, 2=points, 3=croisillons, 4=chevrons, 5=vagues, 6=plein). 0 = aucun motif.
uniform float territory_pattern[TCOUNT];
// REDUCED MOTION (E10 §8.82) : 0 fige toutes les pulsations (telegraphe/attaque) ; 1 = normal.
uniform float motion_scale : hint_range(0.0, 1.0) = 1.0;

// Masque de motif (0/1) pour un index 1..6, en coordonnees ECRAN (SCREEN_UV mis a l'echelle) ->
// motif stable et dense quelle que soit la taille du territoire.
float pattern_mask(int pid, vec2 p) {
	p *= 46.0;
	if (pid == 1) { return step(0.5, fract((p.x + p.y) * 0.5)); }               // rayures diagonales
	if (pid == 2) { return step(0.62, length(fract(p) - 0.5) * 1.4); }          // points
	if (pid == 3) { return max(step(0.5, fract(p.x)), step(0.5, fract(p.y))); } // croisillons
	if (pid == 4) { return step(0.5, fract(abs(fract(p.y) - 0.5) + p.x * 0.5)); } // chevrons
	if (pid == 5) { return step(0.5, fract(p.x + 0.3 * sin(p.y * 3.14159))); }  // vagues
	return 1.0;  // 6 = plein (aucun ajour)
}
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
		// --- Telegraphe (G1 §8.62) : liseré OR PULSANT des territoires annonces pour la
		//     PROCHAINE zone. Detection de bord ELARGIE (forecast_width > border_width) -> le
		//     liseré est plus epais que le contour normal et reste lisible par-dessus lui.
		//     S'applique AUSSI a un territoire deja contamine (chevauchement possible des blocs).
		if (territory_forecast[idx - 1] > 0.5) {
			vec2 fpx = TEXTURE_PIXEL_SIZE * forecast_width;
			bool fedge = idx_at(UV + vec2(fpx.x, 0.0)) != idx
				|| idx_at(UV - vec2(fpx.x, 0.0)) != idx
				|| idx_at(UV + vec2(0.0, fpx.y)) != idx
				|| idx_at(UV - vec2(0.0, fpx.y)) != idx;
			if (fedge) {
				float pulse = 0.55 + 0.45 * sin(TIME * forecast_pulse_speed * motion_scale);
				rgb = forecast_color;
				a = max(a, pulse);
			}
		}
		// --- Motif daltonien (E10 §8.82) : ajour sombre par index de joueur SUR le remplissage
		//     (renforce la distinction que la couleur seule ne garantit pas). ---
		int pat = int(territory_pattern[idx - 1] + 0.5);
		if (pat >= 1 && a > 0.02) {
			float m = pattern_mask(pat, SCREEN_UV);
			rgb = mix(rgb * 0.35, rgb, m);   // creux du motif = teinte assombrie
		}
		// --- Cibles valides (E7 §8.79) : liseré CRAMOISI pulsant le long des vraies cotes. ---
		if (territory_attack[idx - 1] > 0.5) {
			vec2 apx = TEXTURE_PIXEL_SIZE * attack_width;
			bool aedge = idx_at(UV + vec2(apx.x, 0.0)) != idx
				|| idx_at(UV - vec2(apx.x, 0.0)) != idx
				|| idx_at(UV + vec2(0.0, apx.y)) != idx
				|| idx_at(UV - vec2(0.0, apx.y)) != idx;
			if (aedge) {
				float apulse = 0.5 + 0.5 * sin(TIME * forecast_pulse_speed * 1.3 * motion_scale);
				rgb = attack_color;
				a = max(a, apulse);
			}
		}
		// Desaturation douce des territoires HORS action (ni cible, ni a moi) pendant la selection.
		if (attack_dim > 0.5 && territory_attack[idx - 1] < 0.5 && territory_mine[idx - 1] < 0.5) {
			float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
			rgb = mix(rgb, vec3(lum), 0.55);
			a *= 0.7;
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
