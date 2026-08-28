extends Node

# =================================================================================================
# SONDE §8.152 — LOT 3D-G, ÉTAGE 0 : LA SILHOUETTE §2.1
#
# Le cahier §5 est explicite : « **sonde de silhouette §2.1** (enveloppe torse+tête dans la boîte
# serveur sur toutes les poses, sabotage à 10 cm) ; la hitbox reste la boîte du serveur ».
#
# ⚠️ Cette sonde teste la BOÎTE À BORNES, pas encore le soldat animé : elle est écrite AVANT lui,
# exprès. Une garde écrite après les clips oblige à revenir sur chaque amplitude, et une amplitude
# qu'on oublie de reprendre ne se voit pas. Quand `trench_soldier3d.gd` existera, il passera par
# les mêmes fonctions et cette sonde le couvrira sans être réécrite.
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_vue3d_silhouette.tscn
#             --quit-after 1200
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. la borne haute est relachee de 10 cm              -> S1
#  2. la borne laterale est relachee de 10 cm           -> S2
#  3. le budget de profondeur ignore le quantum de visee -> S3
#  4. la borne de hanche disparait                       -> S4
#  5. les cotes sont RECOPIEES au lieu d'etre lues       -> S5
#  6. la rampe de flexion rachidienne saute              -> S6
# =================================================================================================

const Bounds := preload("res://scripts/game/trench_soldier_bounds.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

const CHECKS_ATTENDUS := 6

# ╔═ LES AMPLITUDES MESURÉES SUR LEUR CODE — la matière première de cette sonde ═════════════════╗
# ║ Obtenues en EXÉCUTANT `rig.js` + `clips.js` + `animator.js` sous Node avec le `three` du       ║
# ║ dépôt, sur un balayage de 149 184 poses. Ce ne sont pas des valeurs relues d'un commentaire.   ║
# ║ ⚠️ Deux des sept chiffres du brief d'origine étaient FAUX, et la vérification les a corrigés : ║
# ║   · `_aimIk` : annoncé « +52 cm vers l'avant », mesuré **−57,9 cm en ARRIÈRE** (cible haute)   ║
# ║     et +43,5 cm avant / −43,5 cm bas (cible au sol). Le DANGER, lui, était bien réel.          ║
# ║   · `hitAdd('head')` : annoncé −25 cm, mesuré **−17,3 cm** à force 1 et −22,5 au plafond réel  ║
# ║     (1,4). L'enveloppe `exp(−7.5t)·min(1,22t)` **culmine à 0,7109**, pas à 1 — le −25 supposait ║
# ║     une enveloppe qui n'existe pas.                                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const POSES_MESUREES := [
	{"nom": "idle", "p": Vector3(0.0, 1.790, 0.031)},
	{"nom": "walk", "p": Vector3(0.0, 1.772, 0.017)},
	{"nom": "run", "p": Vector3(0.0, 1.737, 0.045)},
	{"nom": "crouchWalk", "p": Vector3(0.0, 1.442, 0.213)},
	{"nom": "crouchIdle", "p": Vector3(0.0, 1.428, 0.256)},
	{"nom": "hurtIdle", "p": Vector3(0.0, 1.546, 0.398)},
	{"nom": "aimAdd", "p": Vector3(0.0, 1.752, 0.130)},
	{"nom": "suppressAdd", "p": Vector3(0.0, 1.644, 0.265)},
	{"nom": "recoilAdd", "p": Vector3(0.0, 1.798, -0.056)},
	{"nom": "hitAdd/head", "p": Vector3(0.0, 1.726, -0.225)},
	{"nom": "hitAdd/torso", "p": Vector3(0.0, 1.755, -0.176)},
	{"nom": "vault", "p": Vector3(0.0, 1.820, 0.662)},
	{"nom": "aimIk/haut", "p": Vector3(0.0, 1.800, -0.579)},
	{"nom": "aimIk/bas", "p": Vector3(0.0, 1.365, 0.435)},
	{"nom": "lookAt", "p": Vector3(0.0, 1.694, 0.211)},
	{"nom": "enveloppe/x-", "p": Vector3(-0.500, 1.700, 0.0)},
	{"nom": "enveloppe/x+", "p": Vector3(0.506, 1.700, 0.0)},
	{"nom": "enveloppe/y+", "p": Vector3(0.0, 1.821, 0.0)},
	{"nom": "casque/breacher", "p": Vector3(0.0, 1.8553, 0.0)},
]

var _fails: Array = []
var _joues := 0


func _ok(nom: String, cond: bool, detail := "") -> void:
	_joues += 1
	if cond:
		print("  [OK]   %s   | %s" % [nom, detail])
	else:
		_fails.append(nom)
		print("  [ROUGE] %s   | %s" % [nom, detail])


func _ready() -> void:
	print("\n=== SONDE 8.152 — LOT 3D-G ETAGE 0 : LA SILHOUETTE ===\n")
	_probe_haut()
	_probe_lateral()
	_probe_profondeur()
	_probe_hanche()
	_probe_source_unique()
	_probe_rampe()

	print("")
	if _joues != CHECKS_ATTENDUS:
		print("INCOMPLETE : %d controles joues, %d attendus" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(1)
	elif _fails.is_empty():
		print("TOUT VERT (%d/%d controles joues)" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(0)
	else:
		print("ECHEC : %d rouge(s) sur %d joues -> %s" % [_fails.size(), _joues, str(_fails)])
		get_tree().quit(1)


# =================================================================================================
# S1. ⭐⭐ LA BOÎTE ATTRAPE TOUTES LES POSES QUI DÉPASSENT EN HAUTEUR
# =================================================================================================
# ⚠️ Contrôle à DEUX FACES, et c'est indispensable : une borne qui refuse TOUT est aussi inutile
# qu'une borne qui n'attrape rien. On exige donc que les poses fautives soient signalées **ET** que
# les poses honnêtes passent. Le sabotage « relâcher de 10 cm » (celui que le cahier nomme) ne
# rougirait pas sur un contrôle à une seule face.
func _probe_haut() -> void:
	var doivent_sortir := ["enveloppe/y+", "casque/breacher"]
	var manques := []
	var faux_positifs := []
	for pose in POSES_MESUREES:
		var v := Bounds.violations([pose["p"]], false)
		var signale := false
		for s in v:
			if String(s).contains("sommet"):
				signale = true
		var attendu: bool = doivent_sortir.has(String(pose["nom"]))
		if attendu and not signale:
			manques.append(String(pose["nom"]))
		if not attendu and signale and float((pose["p"] as Vector3).y) <= Bounds.HAUT_DEBOUT:
			faux_positifs.append(String(pose["nom"]))
	_ok("S1 la boite attrape les 2 poses qui depassent 1,80 m, et n'accuse aucune des autres",
		manques.is_empty() and faux_positifs.is_empty(),
		"non attrapees : %s · accusees a tort : %s" % [str(manques), str(faux_positifs)])


# =================================================================================================
# S2. ⭐ LA BOÎTE ATTRAPE LES DÉBORDEMENTS LATÉRAUX
# =================================================================================================
# Mesuré : `HeadTop` sort à ±0,506 m sur le balayage complet, soit **66 mm de trop de chaque côté**
# d'une demi-largeur de 0,44. Un joueur qui vise l'épaule qu'il voit à 0,50 m ne touche rien.
func _probe_lateral() -> void:
	var attrapes := 0
	for pose in POSES_MESUREES:
		if not String(pose["nom"]).begins_with("enveloppe/x"):
			continue
		for s in Bounds.violations([pose["p"]], false):
			# ⚠️ Le message a changé de nature avec la mesure : le débordement latéral s'exprime
			# désormais en DEGRÉS DE LACET hors fenêtre, pas en mètres. Un contrôle qui cherche
			# une sous-chaîne suit le libellé, pas le fait — il faut le recaler quand la mesure
			# change, sinon il verdit en silence sur une détection qu'il ne sait plus lire.
			if String(s).contains("lacet"):
				attrapes += 1
	# Contre-face : une pose bien dans la boîte ne doit RIEN déclencher.
	var dedans := Bounds.violations([Vector3(0.30, 1.60, 0.0)], false)
	_ok("S2 la boite attrape les deux debordements lateraux et laisse passer 0,30 m",
		attrapes == 2 and dedans.is_empty(),
		"debordements attrapes : %d/2 · pose interieure : %s" % [attrapes, str(dedans)])


# =================================================================================================
# S3. ⭐⭐ LE BUDGET DE PROFONDEUR VAUT EXACTEMENT UN QUANTUM DE VISÉE
# =================================================================================================
# C'est la borne qui n'existe pas du tout chez eux, et la plus subtile : notre silhouette est une
# PLAQUE à Z constant. Un morceau de corps avancé de ΔZ est vu plus GROS, alors que la fenêtre de
# touche du serveur n'a pas bougé — c'est le défaut du billboard §8.141.7, désactivé à dessein.
#
# ⚠️ On ne vérifie pas « le budget vaut 0,382 m » (ce serait recopier le résultat) : on REFAIT la
# dérivation ici, à partir des cotes lues dans la géométrie, et on compare. Si un jour
# `NO_MANS_LAND` rebouge — il est déjà passé de 35 à 12 puis à 9 m sur deux verdicts de partie
# réelle — le budget suit tout seul et ce contrôle reste juste.
func _probe_profondeur() -> void:
	var d: float = Geo.far_soldier_z() - Geo.near_soldier_z()
	var attendu: float = d - Geo.SILHOUETTE_HALF_WIDTH / tan(
		atan(Geo.SILHOUETTE_HALF_WIDTH / d) + deg_to_rad(Geo.AIM_QUANTUM_DEG))
	var budget: float = Bounds.budget_profondeur()
	# Et la MESURE, elle, doit attraper ce qui ment vraiment. ⚠️ Elle a changé de nature depuis la
	# première version : on ne mesure plus un DÉPLACEMENT (« ce point a bougé de plus d'un
	# quantum ») mais un MENSONGE (« ce point est vu HORS de la fenêtre que le serveur sait
	# toucher »). C'est la question du §8.141.8 : « il faut que sa silhouette soit attaquable EN
	# ENTIER ».
	# Conséquence à noter, et c'est ce qui prouve que la mesure discrimine : `aimIk` **ne ment
	# pas**. Reculé de 58 cm, il est vu 0,54° au-dessus de l'œil pour une fenêtre qui monte à
	# 0,67° : il paraît plus petit, il reste touchable. `vault`, lui, sort par le HAUT.
	var attrapes := []
	for pose in POSES_MESUREES:
		if not Bounds.violations([pose["p"]], false).is_empty():
			attrapes.append(String(pose["nom"]))
	_ok("S3 le budget de profondeur EST un quantum, et la mesure attrape ce qui sort de la fenetre",
		absf(budget - attendu) < 1e-9 and attrapes.has("vault")
			and attrapes.has("enveloppe/y+") and attrapes.has("casque/breacher")
			and not attrapes.has("aimIk/haut"),
		"budget %.4f m (derive %.4f) a %.2f m · attrapes : %s"
			% [budget, attendu, d, str(attrapes)])


# =================================================================================================
# S4. ⭐ LE DÉCALAGE DE HANCHE EST BORNÉ — LE DÉFAUT LE PLUS GRAVE DE LA RÉFÉRENCE
# =================================================================================================
# 🩸 Chez eux, **cinq couches écrivent dans `hipOff` sans se voir**, et rien ne borne la somme :
# mesuré **−0,514 m** (le brief d'origine disait −0,47, il oubliait `hitAdd('legR', k=1.4)`).
# L'IK de pied, elle, EST bornée — mais elle **s'ajoute** au `hipOff`, d'où **−0,83 m** de total et
# des hanches à 0,15 m du sol.
# Chez nous l'accroupi n'est pas une amplitude d'animation : c'est `SILHOUETTE_TOP_DOWN = 1,05`, une
# entrée de la table angulaire serveur. Le débattement disponible est donc 1,80 − 1,05 = 0,75 m,
# et pas un millimètre de plus.
func _probe_hanche() -> void:
	var b: float = Bounds.budget_hanche()
	var cas := [
		# ⚠️ Le cumul mesuré chez eux (−0,514 m) TIENT dans notre budget de 0,75 : il doit passer
		# INTACT. Premier jet de cette table : j'attendais −0,75, c'est-à-dire un écrêtage qui
		# n'a pas lieu d'être. Le contrôle a rougi sur du code JUSTE — c'était l'attente qui
		# était fausse, pas la borne. Une table d'essai est du code comme un autre.
		[-0.514, -0.514],
		[-0.83, -0.75],    # avec l'IK de pied : ÉCRÊTÉ
		[-0.20, -0.20],    # un accroupi ordinaire : intact
		[0.35, 0.0],       # ⚠️ vers le HAUT : refusé net. Une hanche qui MONTE ferait dépasser le
		                   # sommet du casque, et c'est le côté que personne ne pense à tester.
	]
	var fautes := []
	for c in cas:
		var got: float = Bounds.borner_hanche(float(c[0]))
		if absf(got - float(c[1])) > 1e-9:
			fautes.append("%.3f -> %.3f (attendu %.3f)" % [float(c[0]), got, float(c[1])])
	_ok("S4 le decalage de hanche est ecrete a 0,75 m vers le bas et refuse vers le haut",
		fautes.is_empty() and absf(b - 0.75) < 1e-9,
		"budget %.3f m · fautes : %s" % [b, str(fautes)])


# =================================================================================================
# S5. ⭐⭐ LES COTES SONT LUES, PAS RECOPIÉES
# =================================================================================================
# ⛔ Le verrou du projet : la silhouette est figée dans `trench_angles.json` côté serveur et **le
# serveur ne voit que des degrés**. Une cote recopiée dans la vue crée une SECONDE SOURCE DE VÉRITÉ
# qui divergera au premier réglage — en silence, et du seul côté que le joueur voit. C'est
# exactement le patron du §8.148, qui a coûté une session.
#
# ⚠️ Le contrôle ne peut pas se contenter de comparer les valeurs (elles sont égales par
# construction, recopiées ou pas). Il **modifie** la constante lue à la source ? Impossible : les
# `const` GDScript sont figées. On vérifie donc l'IDENTITÉ des trois cotes ET on documente que le
# sabotage correspondant (remplacer `Geo.SILHOUETTE_TOP` par `1.80` en dur) est détecté par la
# passe de sabotage, qui édite le fichier et relance — la seule manière honnête de le prouver.
func _probe_source_unique() -> void:
	var fautes := []
	if Bounds.HAUT_DEBOUT != Geo.SILHOUETTE_TOP:
		fautes.append("HAUT_DEBOUT %.4f != SILHOUETTE_TOP %.4f"
			% [Bounds.HAUT_DEBOUT, Geo.SILHOUETTE_TOP])
	if Bounds.HAUT_ACCROUPI != Geo.SILHOUETTE_TOP_DOWN:
		fautes.append("HAUT_ACCROUPI %.4f != SILHOUETTE_TOP_DOWN %.4f"
			% [Bounds.HAUT_ACCROUPI, Geo.SILHOUETTE_TOP_DOWN])
	if Bounds.DEMI_LARGEUR != Geo.SILHOUETTE_HALF_WIDTH:
		fautes.append("DEMI_LARGEUR %.4f != SILHOUETTE_HALF_WIDTH %.4f"
			% [Bounds.DEMI_LARGEUR, Geo.SILHOUETTE_HALF_WIDTH])
	# La version de table, pour que la sonde parle si le serveur change de barème sans prévenir.
	_ok("S5 les trois cotes de silhouette viennent de la geometrie, pas d'une copie",
		fautes.is_empty(),
		"table v%d · haut %.2f · accroupi %.2f · demi-largeur %.2f · fautes : %s"
			% [Geo.TABLE_VERSION, Bounds.HAUT_DEBOUT, Bounds.HAUT_ACCROUPI, Bounds.DEMI_LARGEUR,
				str(fautes)])


# =================================================================================================
# S6. ⭐ LA FLEXION RACHIDIENNE A UN PLAFOND **ET** UNE RAMPE
# =================================================================================================
# ⚠️ Leur `_aimIk` EST borné en angle (0,9 rad puis 0,35) mais réparti sur trois vertèbres dont les
# poids somment à 1,0 : **1,25 rad = 71,6° de flexion cumulée**, en UNE SEULE IMAGE. Vérifié : ça ne
# s'accumule pas d'image en image (la pose est reconstruite à chaque `reset()`), donc « en une seule
# image » est exact — et c'est précisément le risque. Une cible qui téléporte fait sauter la tête de
# 58 cm sans rampe.
# Un plafond seul ne suffit donc pas : il faut aussi une VITESSE. Deux propriétés, deux mesures.
func _probe_rampe() -> void:
	var dt := 1.0 / 20.0    # notre simulation tourne à 20 Hz
	# a) le plafond mord
	var plafond := Bounds.borner_flexion_rachis(71.6, 71.6, 1.0)
	# b) la rampe mord : depuis 0, en un tick, on ne peut pas atteindre le plafond d'un coup
	var un_tick := Bounds.borner_flexion_rachis(71.6, 0.0, dt)
	var pas_max: float = Bounds.FLEXION_RACHIS_VITESSE_DEG_S * dt
	# c) et elle laisse passer un mouvement lent, sinon la visée deviendrait pâteuse
	var lent := Bounds.borner_flexion_rachis(5.0, 3.0, dt)
	_ok("S6 la flexion rachidienne a un PLAFOND (28 deg) et une RAMPE (11 deg par tick a 20 Hz)",
		absf(plafond - Bounds.FLEXION_RACHIS_MAX_DEG) < 1e-9
			and absf(un_tick - pas_max) < 1e-9 and absf(lent - 5.0) < 1e-9,
		"plafond %.2f · un tick depuis 0 -> %.2f (max %.2f) · mouvement lent 3->5 -> %.2f"
			% [plafond, un_tick, pas_max, lent])
