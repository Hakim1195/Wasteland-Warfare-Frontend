extends RefCounted
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — REGISTRE DE COTES + PROJECTION ANGULAIRE (module PUR, 100 % statique).
#
# ╔═ LA GÉOMÉTRIE EST LA SOURCE DE VÉRITÉ DU CHANTIER ════════════════════════════════════════════╗
# ║ Ce fichier porte les COTES MÉTRIQUES de l'arène (§2.1). Trois consommateurs, une seule table : ║
# ║   • `trench_blockout.gd` BÂTIT la scène 3D depuis ces cotes (aucune coordonnée en dur dans le  ║
# ║     .tscn → le blockout ne peut PAS diverger du registre) ;                                    ║
# ║   • `tools/gen_trench_angles.gd` PROJETTE les fenêtres angulaires et écrit `trench_angles.json`;║
# ║   • `tools/gen_trench_renders.gd` cadre les 10 poses pour l'img2img du bon de commande.        ║
# ║ Le SERVEUR ne recalcule jamais : il CHARGE le JSON (donnée injectée → la simulation reste pure ║
# ║ et le rejeu au bit près survit). Toucher une cote ICI IMPOSE de régénérer le JSON — le test de ║
# ║ checksum (`test_trench_angles.py`) le rappelle brutalement, et c'est voulu.                    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# REPÈRE (main droite, Godot : +Y haut, -Z devant la caméra par défaut — on travaille en +Z « en
# face » et on oriente les caméras d'un demi-tour, cf. `pose_basis`) :
#   • ORIGINE = plancher de MA tranchée, position centrale (index 2), au ras du parapet.
#   • +X = ma droite · +Y = le ciel · +Z = vers la tranchée ADVERSE (le no man's land).
#
# ⚠️ CONVENTION DE MIROIR (la règle qui évite le bug classique du duel symétrique) : la table est
# calculée UNE fois dans CE repère local, et sert aux DEUX joueurs. Chacun se rend « en bas »
# (tranchée proche) et voit l'autre « en face » (tranchée lointaine) SANS inversion d'index : la
# position 0 de l'adversaire est en face de ma position 0. Les deux clients rendent donc la même
# partie, et une seule fenêtre angulaire décrit les deux sens de tir.
# =================================================================================================

# --- Le no man's land et les tranchées ------------------------------------------------------------
# Largeur du no man's land (§2.1) ⚙. C'est LA cote de ressenti : elle fixe la taille apparente de
# la cible (cf. `silhouette_span_deg` — à 35 m un soldat exposé fait ~1° de large, soit ~25 px de
# large en 1920 px à 75° de FOV : petit mais franchement visable, calibre « ennemi lointain »).
const NO_MANS_LAND := 35.0

# Positions discrètes par tranchée et leur espacement (§2.1) ⚙ — 5 × 4 m = 16 m de front utile.
const POSITIONS := 5
const POSITION_SPACING := 4.0

# Parapet de sacs de sable : hauteur du sommet et épaisseur (le mur qui décide de tout le jeu).
const PARAPET_Y := 1.25
const PARAPET_THICKNESS := 0.6
# Largeur de la tranchée (plancher) et hauteur du sol du no man's land au-dessus du plancher.
const TRENCH_WIDTH := 2.2
const GROUND_Y := 1.0

# --- Le soldat ------------------------------------------------------------------------------------
# Hauteur des YEUX (§2.1) : debout au-dessus du parapet, accroupi franchement dessous.
const EYE_UP := 1.70
const EYE_DOWN := 0.90
# Recul du soldat derrière SON parapet (il ne colle pas les sacs).
const SOLDIER_SETBACK := 0.5
# Silhouette DEBOUT : boîte tête+torse. `SILHOUETTE_TOP` = sommet du crâne,
# `SILHOUETTE_BOTTOM` = bas du torse (sous le parapet — c'est LUI qui coupe, pas cette valeur).
const SILHOUETTE_TOP := 1.80
const SILHOUETTE_BOTTOM := 1.15
const SILHOUETTE_HALF_WIDTH := 0.30
# Silhouette ACCROUPI : sommet du crâne bien SOUS le parapet → jamais exposée (invariant vérifié
# par `crouched_is_covered()` et par un test de sabotage côté backend).
const SILHOUETTE_TOP_DOWN := 1.05

# Quantum d'envoi de la visée au serveur (§2.4) : le client arrondit yaw/pitch à ce pas.
const AIM_QUANTUM_DEG := 0.1
# Version de la table : à INCRÉMENTER dès qu'une cote ci-dessus bouge (voyage dans le JSON).
const TABLE_VERSION := 1


# =================================================================================================
# 1. PLACEMENT — les cotes deviennent des points (partagé blockout / générateur / rendus)
# =================================================================================================

# Abscisse d'une position discrète (index 0..POSITIONS-1), centrée sur 0.
static func position_x(index: int) -> float:
	var i := clampi(int(index), 0, POSITIONS - 1)
	return (float(i) - float(POSITIONS - 1) * 0.5) * POSITION_SPACING


# Z du plan des SOLDATS de ma tranchée (derrière mon parapet, donc négatif).
static func near_soldier_z() -> float:
	return -SOLDIER_SETBACK


# Z du plan des SOLDATS de la tranchée adverse.
static func far_soldier_z() -> float:
	return NO_MANS_LAND + SOLDIER_SETBACK


# Z de l'arête HAUTE et PROCHE du parapet adverse — l'arête qui OCCULTE le bas de la silhouette.
static func far_parapet_near_edge_z() -> float:
	return NO_MANS_LAND - PARAPET_THICKNESS


# Hauteur des yeux d'une posture ("up" | "down").
static func eye_height(stance: String) -> float:
	return EYE_DOWN if String(stance) == "down" else EYE_UP


# Point de vue (caméra) d'une pose de MON camp : (position, posture) -> Vector3.
static func eye_position(pos_index: int, stance: String) -> Vector3:
	return Vector3(position_x(pos_index), eye_height(stance), near_soldier_z())


# Nom canonique d'une pose — sert de nom de Marker3D ET de nom de fichier de décor (§7.1).
# `cam_p{0..4}_{up|down}` : le nommage EST le contrat avec le bon de commande d'assets.
static func pose_name(pos_index: int, stance: String) -> String:
	return "cam_p%d_%s" % [clampi(int(pos_index), 0, POSITIONS - 1),
		"down" if String(stance) == "down" else "up"]


# Les 10 poses de caméra, dans l'ORDRE CANONIQUE (p0_up, p0_down, p1_up, …) — l'ordre des rendus
# et l'ordre des entrées de la table. Chaque entrée : {pos, stance, name, eye}.
static func all_poses() -> Array:
	var out: Array = []
	for i in range(POSITIONS):
		for stance in ["up", "down"]:
			out.append({"pos": i, "stance": stance, "name": pose_name(i, stance),
				"eye": eye_position(i, stance)})
	return out


# =================================================================================================
# 2. OCCULTATION — jusqu'où le parapet adverse mange-t-il la silhouette ?
# =================================================================================================

# Ordonnée à laquelle la ligne de vue RASE l'arête haute du parapet adverse, évaluée au plan des
# soldats d'en face. Tout ce qui est SOUS cette ligne est caché par les sacs de sable : c'est la
# traduction géométrique de « DEBOUT = tête+torse exposés ».
#
# ⚠️ C'est un CALCUL, pas une constante : changer la hauteur du parapet, le recul du soldat ou la
# largeur du no man's land déplace automatiquement la découpe. Le blockout reste souverain.
static func occlusion_floor_at_target(eye: Vector3) -> float:
	var edge_z := far_parapet_near_edge_z()
	var span := edge_z - eye.z
	if span <= 0.0:
		return PARAPET_Y   # œil déjà au-delà du parapet adverse : cas impossible, repli prudent.
	var slope := (PARAPET_Y - eye.y) / span
	return eye.y + slope * (far_soldier_z() - eye.z)


# La partie VISIBLE de la silhouette adverse, pour une posture donnée : [y_bas, y_haut].
# Renvoie un tableau VIDE quand rien ne dépasse — c'est le cas ACCROUPI, et c'est l'invariant
# central du chantier (une balle ne peut pas toucher un accroupi : il n'a aucune fenêtre).
static func visible_band(eye: Vector3, target_stance: String) -> Array:
	var top := SILHOUETTE_TOP_DOWN if String(target_stance) == "down" else SILHOUETTE_TOP
	var bottom: float = maxf(SILHOUETTE_BOTTOM, occlusion_floor_at_target(eye))
	if top <= bottom:
		return []
	return [bottom, top]


# Contre-épreuve de cote, appelée par le générateur ET par un test : un ACCROUPI n'est jamais
# exposé, depuis AUCUNE des 5 poses debout. Si un jour une cote casse ça, la génération hurle.
static func crouched_is_covered() -> bool:
	for i in range(POSITIONS):
		var eye := eye_position(i, "up")
		for t in range(POSITIONS):
			if not visible_band(eye, "down").is_empty():
				return false
	return true


# =================================================================================================
# 3. PROJECTION ANGULAIRE — le cœur du LOT B
# =================================================================================================

# Cap (yaw) d'un point vu depuis `eye`, en degrés : 0 = droit devant (+Z), positif = vers MA droite.
static func yaw_to(eye: Vector3, point: Vector3) -> float:
	return rad_to_deg(atan2(point.x - eye.x, point.z - eye.z))


# Site (pitch) d'un point vu depuis `eye`, en degrés : positif = vers le haut.
static func pitch_to(eye: Vector3, point: Vector3) -> float:
	var dx := point.x - eye.x
	var dz := point.z - eye.z
	var horizontal: float = sqrt(dx * dx + dz * dz)
	if horizontal <= 0.0:
		return 90.0 if point.y > eye.y else -90.0
	return rad_to_deg(atan2(point.y - eye.y, horizontal))


# FENÊTRE ANGULAIRE d'une silhouette adverse vue depuis une pose : la boîte englobante en
# (yaw, pitch) des 4 coins de la partie VISIBLE. Renvoie {} quand la cible n'est pas exposée.
#
# On échantillonne les 4 coins ET les milieux d'arêtes verticales : le pitch d'un coin latéral est
# LÉGÈREMENT différent de celui du centre (la distance horizontale change), et prendre l'enveloppe
# des 6 points évite de sous-estimer la fenêtre d'un cheveu — dans le sens FAVORABLE au tireur.
static func aim_window(eye: Vector3, target_pos_index: int, target_stance: String) -> Dictionary:
	var band := visible_band(eye, target_stance)
	if band.is_empty():
		return {}
	var cx := position_x(target_pos_index)
	var cz := far_soldier_z()
	var y_lo: float = band[0]
	var y_hi: float = band[1]
	var yaw_min := INF
	var yaw_max := -INF
	var pitch_min := INF
	var pitch_max := -INF
	for x in [cx - SILHOUETTE_HALF_WIDTH, cx, cx + SILHOUETTE_HALF_WIDTH]:
		for y in [y_lo, y_hi]:
			var p := Vector3(x, y, cz)
			var yaw := yaw_to(eye, p)
			var pitch := pitch_to(eye, p)
			yaw_min = minf(yaw_min, yaw)
			yaw_max = maxf(yaw_max, yaw)
			pitch_min = minf(pitch_min, pitch)
			pitch_max = maxf(pitch_max, pitch)
	return {"yaw_min": yaw_min, "yaw_max": yaw_max,
		"pitch_min": pitch_min, "pitch_max": pitch_max}


# Largeur apparente (en degrés) d'une silhouette debout vue de face au centre — la mesure de
# lisibilité citée en tête de fichier. Sert au rapport et au réglage du réticule.
static func silhouette_span_deg() -> float:
	var window := aim_window(eye_position(2, "up"), 2, "up")
	if window.is_empty():
		return 0.0
	return float(window["yaw_max"]) - float(window["yaw_min"])


# Orientation d'une caméra posée sur une pose : elle REGARDE la tranchée adverse (+Z). Godot
# regarde -Z par défaut → demi-tour en lacet. Le pitch de repos est 0 (l'horizon au centre).
static func pose_basis() -> Basis:
	return Basis(Vector3.UP, PI)


# Transform complet d'une pose (ce que porte le Marker3D du blockout).
static func pose_transform(pos_index: int, stance: String) -> Transform3D:
	return Transform3D(pose_basis(), eye_position(pos_index, stance))


# Cotes exportées dans le JSON (traçabilité : le serveur peut afficher la géométrie qu'il applique,
# et une relecture humaine du fichier suffit à comprendre d'où sortent les angles).
static func geometry_block() -> Dictionary:
	return {
		"no_mans_land": NO_MANS_LAND,
		"positions": POSITIONS,
		"position_spacing": POSITION_SPACING,
		"parapet_y": PARAPET_Y,
		"parapet_thickness": PARAPET_THICKNESS,
		"trench_width": TRENCH_WIDTH,
		"ground_y": GROUND_Y,
		"eye_up": EYE_UP,
		"eye_down": EYE_DOWN,
		"soldier_setback": SOLDIER_SETBACK,
		"silhouette_top": SILHOUETTE_TOP,
		"silhouette_bottom": SILHOUETTE_BOTTOM,
		"silhouette_half_width": SILHOUETTE_HALF_WIDTH,
		"silhouette_top_down": SILHOUETTE_TOP_DOWN,
	}
