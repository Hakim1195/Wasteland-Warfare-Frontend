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
#   • +X · +Y = le ciel · +Z = vers la tranchée ADVERSE (le no man's land).
#
# ⚠️⚠️ CE FICHIER A LONGTEMPS ÉCRIT « +X = ma droite ». C'EST FAUX, ET ÇA A COÛTÉ UNE PARTIE.
# Le repère est DROITIER : un observateur tourné vers +Z, avec +Y en haut, a sa droite en **−X**.
# Mesuré au harnais (position centrale, visée nulle) : la position adverse 4, à x = +8 m, se
# projette à 719 px, et la position 0, à x = −8 m, à 1201 px. Le « +X » du registre sort donc à
# GAUCHE de l'écran. Deux symptômes rapportés en partie réelle en découlaient : « la souris vers la
# droite fait viser à gauche » et « les flèches droite et gauche sont inversées ».
# ⚠️ La correction vit dans `trench_fp.gd` (`SCREEN_TO_WORLD_X`), au niveau des ENTRÉES, et surtout
# PAS ici : ce registre est partagé avec le serveur, et lui retourner un signe rendrait la table
# angulaire fausse pour tout le monde. Le repère n'a rien d'incorrect — seul son commentaire l'était.
#
# ⚠️ CONVENTION DE MIROIR (la règle qui évite le bug classique du duel symétrique) : la table est
# calculée UNE fois dans CE repère local, et sert aux DEUX joueurs. Chacun se rend « en bas »
# (tranchée proche) et voit l'autre « en face » (tranchée lointaine) SANS inversion d'index : la
# position 0 de l'adversaire est en face de ma position 0. Les deux clients rendent donc la même
# partie, et une seule fenêtre angulaire décrit les deux sens de tir.
# =================================================================================================

# --- Le no man's land et les tranchées ------------------------------------------------------------
# Largeur du no man's land (§2.1) ⚙. C'est LA cote de ressenti : elle fixe la taille apparente de
# la cible.
# ╔═ ⚠️⚠️ 35 m → 12 m (§8.140.1) → 9 m (§8.141), SUR VERDICT DE PARTIE RÉELLE ════════════════════╗
# ║ Premier verdict : « L'adversaire est trop loin, je le vois minuscule. » La cote de 35 m avait  ║
# ║ été calculée pour un « ennemi lointain » — le calcul était juste et la sensation mauvaise : à  ║
# ║ 35 m la part EXPOSÉE du soldat fait 0,96° de large, une vingtaine de pixels en 1920. On ne     ║
# ║ vise pas vingt pixels au pistolet. À 12 m elle faisait 2,64°.                                   ║
# ║ SECOND verdict, après de nombreux essais sur cette version-là : ENCORE trop petit. On descend   ║
# ║ donc à **9 m**, ET on resserre le front — les deux ENSEMBLE, voir le pavé suivant.              ║
# ║                                                                                                 ║
# ║ Largeur apparente du torse exposé (0,60 m) à 10,0 m de plan à plan :                            ║
# ║        35 m → 0,96°   ·   12 m → 2,64°   ·   **9 m → 3,44°**  (≈ 67 px à FOV 55 sur 1080p)      ║
# ║ Hauteur de la bande exposée (le parapet d'en face coupe à 1,194 m) :                            ║
# ║        12 m → 0,592 m = 2,61°   ·   **9 m → 0,606 m = 3,47°**  (≈ 68 px)                        ║
# ║ Un torse de plus de 60 px se VISE ; il ne se devine plus. C'est le critère du chantier.         ║
# ║                                                                                                 ║
# ║ ⚠️ CETTE COTE N'EST PAS LOCALE. Elle voyage dans `trench_angles.json`, que le SERVEUR charge et ║
# ║ ne recalcule jamais. La changer IMPOSE de régénérer la table (les deux copies) et de           ║
# ║ REDÉPLOYER le backend — sans quoi le serveur résout les touches sur une arène qui n'existe      ║
# ║ plus. `test_trench_angles.py` compare les checksums et le rappelle brutalement.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const NO_MANS_LAND := 9.0

# ╔═ ⚠️ ON NE RAPPROCHE PAS SANS RESSERRER — SINON C'EST UN TORTICOLIS ═══════════════════════════╗
# ║ 5 × 4,0 m faisaient 16 m de front. Gardé tel quel sur 9 m de profondeur, voir la position      ║
# ║ opposée depuis un bord aurait demandé **±58,0°** de lacet (`atan(16,3 / 10,0)`) : on jouerait   ║
# ║ le duel de profil. En resserrant à 3,4 m (13,6 m de front), on retombe à **±54,3°**            ║
# ║ (`atan(13,9 / 10,0)`) — plus qu'à 12 m (±51,4°), donc le pas de côté pèse toujours plus lourd,  ║
# ║ mais l'arène reste lisible d'un seul regard.                                                    ║
# ║ ⚠️ Le débattement client ne recopie PAS ce chiffre : `max_window_yaw_deg()` plus bas le CALCULE ║
# ║ depuis la table, et `trench_fp.gd` lui ajoute sa marge. Une cote qui bouge ne peut donc plus    ║
# ║ laisser un plafond de visée périmé rendre trois positions sur cinq injoignables.                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const POSITIONS := 5
const POSITION_SPACING := 3.4

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
# ╔═ ⚠️⚠️ 0,30 → 0,44 m : LA BOÎTE ÉPOUSE ENFIN LA SILHOUETTE PEINTE (§8.141.8) ══════════════════╗
# ║ Verdict de partie réelle : « la zone touchable est extrêmement petite, je la touche au hasard, ║
# ║ il faut que sa silhouette soit attaquable EN ENTIER ».                                         ║
# ║ Mesuré (`probe_trench_aim`) : le cadre du sprite fait **0,873 m** de large — l'homme AVEC ses  ║
# ║ bras et son arme — pour une fenêtre de tir de **0,60 m**, c'est-à-dire le TORSE SEUL. Rapport  ║
# ║ constant de **1,44×** : à chaque tir, près de la moitié de ce que le joueur voit n'existe pas  ║
# ║ pour le serveur. On vise un homme, on touche une colonne au milieu de lui.                      ║
# ║ 0,4365 = la demi-largeur EXACTE du cadre peint (427 px × `pixel_size`). Arrondi à 0,44.         ║
# ║                                                                                                 ║
# ║ ⚠️ CE QUE ÇA NE CASSE PAS, et c'est pour ça que c'est faisable : les fenêtres de deux positions ║
# ║ voisines restent LARGEMENT DISJOINTES (centres à 18,8° d'écart, demi-fenêtres de 2,5°) — « un   ║
# ║ pas de côté est TOUJOURS une esquive » tient toujours. Et la HAUTEUR n'avait pas à bouger :     ║
# ║ elle couvrait déjà toute la bande exposée (1,194 → 1,80 m), le parapet fait le reste.           ║
# ║ ⚠️ CETTE COTE VOYAGE DANS LA TABLE : régénérer les deux copies ET redéployer le backend.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const SILHOUETTE_HALF_WIDTH := 0.44
# Silhouette ACCROUPI : sommet du crâne bien SOUS le parapet → jamais exposée (invariant vérifié
# par `crouched_is_covered()` et par un test de sabotage côté backend).
const SILHOUETTE_TOP_DOWN := 1.05

# Quantum d'envoi de la visée au serveur (§2.4) : le client arrondit yaw/pitch à ce pas.
const AIM_QUANTUM_DEG := 0.1
# Version de la table : à INCRÉMENTER dès qu'une cote ci-dessus bouge (voyage dans le JSON).
# v2 : `NO_MANS_LAND` 35 → 12 m (§8.140.1, verdict de partie réelle).
# v3 : `NO_MANS_LAND` 12 → 9 m ET `POSITION_SPACING` 4,0 → 3,4 m (§8.141, second verdict).
# v4 : `SILHOUETTE_HALF_WIDTH` 0,30 → 0,44 m (§8.141.8, verdict « la zone touchable est minuscule »).
const TABLE_VERSION := 4


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


# Hauteur apparente (en degrés) de la bande exposée, vue de face au centre. Jumelle de la
# précédente : ensemble, elles disent en DEUX chiffres si la cible se vise ou se devine.
static func silhouette_height_deg() -> float:
	var window := aim_window(eye_position(2, "up"), 2, "up")
	if window.is_empty():
		return 0.0
	return float(window["pitch_max"]) - float(window["pitch_min"])


# ╔═ LE DÉBATTEMENT DE VISÉE SE CALCULE, IL NE SE RECOPIE PLUS (§8.141) ══════════════════════════╗
# ║ `AIM_YAW_LIMIT` a valu 32° puis 58°, deux fois posé À LA MAIN après un changement de cote —    ║
# ║ et la première fois, le laisser à 32° après le passage à 12 m aurait rendu trois positions sur ║
# ║ cinq mécaniquement INJOIGNABLES depuis les bords (la balle n'aurait même pas pu être déclarée).║
# ║ Ce plafond n'est pas un goût, c'est une CONSÉQUENCE de la géométrie : le plus grand |lacet|    ║
# ║ qu'une fenêtre de tir réclame. On le calcule donc ICI, sur les mêmes fenêtres que celles que le║
# ║ serveur résout — plus aucun rapprochement futur ne peut laisser un plafond périmé derrière lui.║
# ║ ⚠️ C'est un MAXIMUM de fenêtres, pas une marge : `trench_fp.gd` y ajoute la sienne (le joueur  ║
# ║ doit pouvoir DÉPASSER sa cible, sinon le geste bute sur un mur invisible au moment de viser).  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func max_window_yaw_deg() -> float:
	var worst := 0.0
	for shooter in range(POSITIONS):
		var eye := eye_position(shooter, "up")
		for target in range(POSITIONS):
			var window := aim_window(eye, target, "up")
			if window.is_empty():
				continue
			worst = maxf(worst, maxf(absf(float(window["yaw_min"])),
				absf(float(window["yaw_max"]))))
	return worst


# ╔═ LES DEUX BORNES DE PRÉSENTATION QUI EN DÉCOULENT ════════════════════════════════════════════╗
# ║ ⚠️ ELLES NE VOYAGENT PAS DANS LE JSON — `geometry_block()` ne les exporte pas, et le serveur   ║
# ║ n'en a que faire : il résout des fenêtres, il ne présente rien. Elles vivent ICI parce qu'elles ║
# ║ ont TROIS consommateurs client (`trench_fp` pour l'entrée souris, `trench_fp_world` pour la     ║
# ║ caméra, `trench_tuning` pour le curseur) et qu'une valeur à trois copies est une valeur qui va  ║
# ║ diverger. Elles sont la SEULE chose de ce fichier qui ne soit pas une cote métrique, et c'est   ║
# ║ assumé : ce sont des conséquences DIRECTES des cotes, calculées au même endroit qu'elles.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Marge au-delà de la fenêtre la plus excentrée ⚙ : viser, c'est passer SUR la cible et revenir. Un
# plafond posé pile sur la fenêtre extrême ferait buter la main contre un mur invisible au moment
# du tir le plus difficile du jeu. 6° ≈ deux largeurs de silhouette à 9 m.
const AIM_YAW_MARGIN := 6.0
# Marge de la caméra AU-DELÀ du débattement ⚙ : elle n'est jamais atteinte en jeu (la visée est
# déjà bornée en amont), elle n'existe que pour qu'aucune valeur aberrante ne retourne la vue.
const CAMERA_FOLLOW_SAFETY := 12.0


static func aim_yaw_limit_deg() -> float:
	return max_window_yaw_deg() + AIM_YAW_MARGIN


static func camera_follow_max_deg() -> float:
	return aim_yaw_limit_deg() + CAMERA_FOLLOW_SAFETY


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
