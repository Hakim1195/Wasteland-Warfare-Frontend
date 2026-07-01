shader_type canvas_item;

// ============================================================================
// HOLOGRAMME TACTIQUE (Concept A) — territoire POSSEDE hors zone radioactive.
//
// Applique en `ShaderMaterial` sur le `Polygon2D` de remplissage par board.gd
// (`_apply_hologram_material`). Remplace le remplissage OPAQUE uni (illisible)
// par :
//   1) un CONTOUR neon lumineux qui epouse le bord INTERIEUR du polygone ;
//   2) un remplissage tres transparent en fines HACHURES diagonales qui
//      defilent lentement via TIME.
//
// CONTOUR SANS LIGNE2D : on calcule la distance du fragment au bord le plus
// proche (SDF) a partir des sommets du polygone, pousses par board.gd dans
// `edge_points` (espace LOCAL du Polygon2D, identique a VERTEX). Marche pour
// des polygones concaves (territoires dessines a la main).
//
// Le shader ECRASE COLOR -> board.gd n'a pas a teinter le Polygon2D quand il
// est actif (la couleur statique du Polygon2D ne sert que de repli).
// ============================================================================

// Accent de la faction proprietaire (pousse par board.gd au runtime).
uniform vec4 accent_color : source_color = vec4(0.42, 0.56, 0.14, 1.0);

// Sommets du polygone (espace local), fermes en boucle. `point_count` <= MAX.
const int MAX_POINTS = 64;
uniform vec2 edge_points[MAX_POINTS];
uniform int point_count = 0;

// --- Contour neon (en pixels de l'espace local du board) ---
uniform float neon_width : hint_range(1.0, 64.0) = 7.0;     // epaisseur du trait vif
uniform float glow_width : hint_range(1.0, 240.0) = 36.0;   // halo interieur diffus
uniform float glow_strength : hint_range(0.0, 1.0) = 0.32;  // intensite du halo
uniform float neon_boost : hint_range(1.0, 4.0) = 1.9;      // sur-brillance du coeur du trait

// --- Hachures diagonales defilantes (remplissage tres transparent) ---
uniform float hatch_frequency : hint_range(0.002, 0.2) = 0.028; // 1 / espacement (px^-1)
uniform float hatch_speed : hint_range(0.0, 2.0) = 0.12;        // vitesse de defilement
uniform float hatch_width : hint_range(0.02, 0.5) = 0.10;       // finesse de la raie
uniform float hatch_alpha : hint_range(0.0, 1.0) = 0.16;        // opacite du remplissage

// Position locale du fragment (= espace des points du polygone), transmise par le vertex.
varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

// Distance d'un point p au segment [a, b].
float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
	return length(p - (a + t * ab));
}

void fragment() {
	// --- Distance au bord le plus proche (SDF du contour) ---
	// Boucle a borne CONSTANTE (exigence GLSL) + break sur point_count reel.
	int n = point_count;
	if (n > MAX_POINTS) { n = MAX_POINTS; }
	float d = 1.0e9;
	if (n >= 2) {
		for (int i = 0; i < MAX_POINTS; i++) {
			if (i >= n) { break; }
			int j = i + 1;
			if (j >= n) { j = 0; } // referme la boucle (dernier -> premier)
			d = min(d, seg_dist(v_local, edge_points[i], edge_points[j]));
		}
	} else {
		d = 0.0; // pas de polygone exploitable : on retombe sur un voile uniforme.
	}

	// --- Contour neon : trait vif au ras du bord + halo diffus vers l'interieur ---
	float neon = 1.0 - smoothstep(0.0, neon_width, d);
	float glow = (1.0 - smoothstep(0.0, glow_width, d)) * glow_strength;
	float edge_a = max(neon, glow);

	// --- Hachures diagonales fines, defilant lentement (TIME) ---
	float coord = (v_local.x - v_local.y) * hatch_frequency - TIME * hatch_speed;
	float stripe = abs(fract(coord) - 0.5) * 2.0;        // 0 au centre de la raie, 1 entre deux
	float hatch = smoothstep(hatch_width, 0.0, stripe) * hatch_alpha;

	// --- Composition : remplissage hache (faible) + contour lumineux (fort) ---
	vec3 rgb = accent_color.rgb * mix(1.0, neon_boost, neon);
	float a = max(hatch, edge_a) * accent_color.a;
	COLOR = vec4(rgb, a);
}
