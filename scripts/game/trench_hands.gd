class_name TrenchHands
extends RefCounted
# =================================================================================================
# LA TRANCHÉE — VUE 3D (§8.152 LOT 3D-D) — LES BRAS ET LES MAINS GANTÉES.
#
# Port de `War-Of-Indipendence/Claude-of-Duty-main/src/weapons/hands.js` (1 163 l.).
#
# ╔═ L'ORDRE DES OPÉRATIONS DU RIG — la phrase de leur en-tête qui gouverne tout ════════════════╗
# ║ « Two bones per arm, solved analytically FROM THE HAND (which is the thing the animation      ║
# ║ drives — the hands are welded to the weapon, the elbows follow). That is the same order of    ║
# ║ operations a real animator uses and it means **the hands can never slide off the grip**. »    ║
# ║                                                                                               ║
# ║ Conséquence structurelle : `upper_pivot`, `fore_pivot` et `hand` sont TROIS FRÈRES, pas une   ║
# ║ chaîne. Le coude n'est pas enfant de l'épaule : sa position est RECALCULÉE à chaque `solve()`.║
# ║ La main n'est pas au bout de l'avant-bras : elle est POSÉE sur sa cible, et l'avant-bras vient║
# ║ la rejoindre. Reconstruire ça en chaîne parent→enfant ferait glisser la main sur la poignée.  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️ CHIRALITÉ — LE PIÈGE N°1 DE CE FICHIER, ET IL EST CONTRE-INTUITIF ══════════════════════╗
# ║ Leur commentaire : « the geometry below puts the thumb at +X, which makes the authored mesh a ║
# ║ **LEFT hand** — so it is the RIGHT arm that needs the mirror, not the left. »                 ║
# ║ Et la conséquence du sens inverse, mesurée : « the shooting hand was a left hand on the right ║
# ║ side of the grip: the index (which setTrigger drives) came out at the **bottom-rear of the    ║
# ║ grip instead of on the trigger** ».                                                           ║
# ║                                                                                               ║
# ║ ⚠️ ÉCART ASSUMÉ : ils miroitent avec un `scale.x = -1` sur un NŒUD parent. Ici le miroir est  ║
# ║ CUIT DANS LE MAILLAGE (`apply_transform` avec `sx = -1`), ce qui retourne le sens de parcours ║
# ║ des faces au passage — automatiquement, puisque le déterminant devient négatif (lot 3D-0).    ║
# ║ Raison : une échelle négative sur un `Node3D` Godot inverse les faces SANS que le moteur ne   ║
# ║ compense, et il faudrait alors basculer le `cull_mode` du matériau — donc un matériau de plus ║
# ║ par main, et un piège permanent. Cuire le miroir une fois au build coûte zéro et ne peut pas  ║
# ║ se désynchroniser.                                                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# REPÈRE MAIN : **−Z le long des doigts, +Y sortant du dos de la main, +X vers le pouce.**
# REPÈRE OS : toute géométrie d'os est écrite le long de +Z puis retournée de π autour de Y, donc
# elle s'étend vers **−Z** ; chaque articulation propage son enfant par `position.z = −longueur`.
#
# ⚠️ TOUT SE RÉSOUT DANS L'ESPACE DU PARENT DE `root` (l'espace du rig du viewmodel), jamais en
# espace monde. C'est ce qui permet au solveur de tourner AU BUILD, hors de l'arbre de scène.
# =================================================================================================

# ╔═ ⚠️ POURQUOI CE FICHIER PORTE UN `class_name` ALORS QUE LES AUTRES DU CHANTIER N'EN ONT PAS ═╗
# ║ Une classe interne GDScript **ne voit pas la portée de son script englobant** — ni ses        ║
# ║ statiques, ni ses constantes, ni ses `preload` (vérifié dans le moteur au lot 3D-0). Ailleurs ║
# ║ dans ce chantier le problème se contourne en déplaçant le nécessaire dans une classe interne  ║
# ║ SŒUR. Ici c'est impossible : `Arm` a besoin de TOUT — les cotes, les poses, les primitives    ║
# ║ anatomiques ET le préchargement de `trench_meshgen`.                                          ║
# ║                                                                                               ║
# ║ Un `class_name` lève la contrainte : l'identifiant devient GLOBAL, et `Arm` atteint alors     ║
# ║ `TrenchHands.HAND_POSES`, `TrenchHands.Meshgen`, etc. **Vérifié dans le moteur** (une classe  ║
# ║ interne lit bien la constante, le `preload` et la statique du script nommé) — ⚠️ à condition  ║
# ║ que le projet ait été IMPORTÉ au moins une fois : le cache de classes globales est peuplé par ║
# ║ `--import`, et un `--script` lancé avant lui rend « Identifier not declared ».                ║
# ║                                                                                               ║
# ║ Les consommateurs continuent de faire `preload(...)`, comme le reste du chantier.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const Meshgen := preload("res://scripts/game/trench_meshgen.gd")


# =================================================================================================
# COTES — toutes en mètres, toutes littérales de la référence
# =================================================================================================

# ╔═ POURQUOI LES OS SONT TRICHÉS DE 10 % ═══════════════════════════════════════════════════════╗
# ║ Anatomiquement l'humérus fait 0,300 et l'avant-bras 0,272. Ici : 0,33 et 0,30. Leur raison,   ║
# ║ MESURÉE : « once the weapon is far enough from the eye for the magazine and the muzzle to be  ║
# ║ in frame at all (300 mm), the support hand is 515 mm downrange of a shoulder that has to stay ║
# ║ BEHIND the eye, and 572 mm of arm reaches that at **99,5 % extension**. The two-bone solve    ║
# ║ then clamps, the elbow locks dead straight, and the arm reads as **a broomstick with the hand ║
# ║ sliding off the handguard**. »                                                                ║
# ║ L'alternative évidente — avancer l'épaule — a été mesurée et est PIRE : « at shoulderZ −0.075 ║
# ║ the 89 mm forearm sleeve crosses the frame diagonally and occludes the barrel and muzzle      ║
# ║ outright ». Trichés à 330/300 (portée 630 mm), la même cible est à 91 % d'extension : il reste ║
# ║ un coude visiblement plié, et le coude sort DAVANTAGE du cadre — « a longer chain between      ║
# ║ fixed endpoints bends more ».                                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const L_UPPER := 0.33
const L_FORE := 0.30

# Le pouce. ⚠️ « THE PROXIMAL SEGMENT IS THE METACARPAL AS WELL AS THE PROXIMAL PHALANX, and that
# is why it is 50 mm rather than 38. » Mesuré : avec un pouce 38 + 30 mm, la solution de C-clamp
# laissait le bout à **13,2 mm du garde-main** quelle que soit l'orientation de la base — « It is
# not an aiming problem, it is a REACH problem ». Ce rig n'a aucun segment métacarpien : le
# proximal l'absorbe. 50 + 32 = 82 mm, ce qui atteint avec 10 mm de flexion en réserve.
const THUMB_L0 := 0.05
const THUMB_L1 := 0.032
const THUMB_R0 := 0.0115
const THUMB_R1 := 0.0102
const THUMB_R2 := 0.0078

# ╔═ ⚠️ SEGMENTS DE PHALANGE : 20 ET NON 12 — LE SEUL ENDROIT OÙ ON S'ÉCARTE VOLONTAIREMENT ═════╗
# ║ La référence lathe ses phalanges à **12 côtés**, alors qu'elle segmente ses manches à 32 avec ║
# ║ une justification en pixels explicite (« a 20-gon puts a facet sagitta of 0.7 px on the       ║
# ║ silhouette — countable, and countable facets are exactly what the critique measured »).       ║
# ║ Un doigt de 10 mm de rayon vu à 0,3 m occupe des dizaines de pixels : à 12 côtés, **son       ║
# ║ contour EST un dodécagone visible**. C'est littéralement la cause du mot « blocky » dans leur ║
# ║ propre aveu (« Blocky finger slabs that don't convincingly grip the weapon »).                ║
# ║                                                                                               ║
# ║ Le cahier §2.2bis B nous demande explicitement de faire MIEUX ici : « c'est le défaut n°1     ║
# ║ avoué de la référence : soigner la préhension ». 20 côtés coûtent ~35 triangles par phalange  ║
# ║ et suppriment le défaut le plus cité de leur build. **La capture de Hakim est ici la chose à  ║
# ║ BATTRE, pas à égaler.**                                                                       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const FINGER_SEG := 20
const SLEEVE_SEG := 32


# =================================================================================================
# `HAND_POSES` — les six poses de préhension
# =================================================================================================
# ⚠️ CONVENTION DE SIGNE : les flexions sont stockées POSITIVES et appliquées NÉGATIVES
# (`joint.rotation.x = -curl[j]`). Mais `thumb_base` est appliqué TEL QUEL. Inverser l'un des deux
# retourne la main.
#
# ╔═ POURQUOI UN RATIO DE FLEXION UNIFORME EST FAUX ═════════════════════════════════════════════╗
# ║ « A uniform curl ratio cannot wrap a cylinder: it traces a SPIRAL, so if the middle joint     ║
# ║ touches, the fingertip stands 20 mm off. » La répartition qui en sort (MCP ~0,6 · PIP ~1,2 ·  ║
# ║ DIP ~0,8) est aussi ce que fait une vraie main sur un tube : **c'est l'articulation du MILIEU ║
# ║ qui porte l'essentiel de l'enroulement**. Et c'est le doigt le plus LONG qui se ferme le plus,║
# ║ pas l'auriculaire — « the "little finger curls hardest" rule is a tapered-pistol-grip rule    ║
# ║ and is wrong here ».                                                                          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const HAND_POSES := {
	# Poigne de tir sur poignée pistolet. ⚠️ La ligne 0 est le REPOS DE LA DÉTENTE, et elle est
	# répétée en dur dans `set_trigger` : « the finger is already ON the trigger with the slack
	# taken up, not standing off it straight ».
	"grip": {
		"fingers": [[0.55, 0.72, 0.34], [1.15, 1.20, 0.62],
			[1.20, 1.25, 0.65], [1.22, 1.28, 0.66]],
		"thumb": [0.5, 0.34],
		"thumb_base": [0.15, -1.02, -0.62],
	},
	# Main d'appui enroulée sur un garde-main — la pose PAR DÉFAUT.
	"wrap": {
		"fingers": [[1.18, 1.05, 0.45], [1.26, 1.12, 0.50],
			[1.30, 1.16, 0.55], [1.34, 1.20, 0.60]],
		"thumb": [0.42, 0.3],
		"thumb_base": [0.1, -1.15, -0.35],
	},
	# C-clamp moderne — le repli de `fit_to_cylinder`.
	# ⚠️ Budget angulaire : « for a 47 mm handguard gripped 14 mm off the surface that is 150-165
	# deg, i.e. 2.6-2.9 rad TOTAL. Anything less and the fingertips stop in mid-air short of the far
	# side, which is the "detached grey slabs with daylight between them and the handguard" failure. »
	# Seule pose dont `thumb_base.y` est POSITIF : le pouce est couché en travers du DESSUS du
	# garde-main, pas replié en travers de la paume — « a C-clamp whose thumb is on the same side as
	# the fingers is a fist held NEXT TO the gun, not a grip ON it ».
	"clamp": {
		"fingers": [[0.612, 1.059, 0.797], [0.731, 1.286, 0.863],
			[0.730, 1.268, 0.808], [0.601, 1.105, 0.684]],
		"thumb": [0.3, 0.24],
		"thumb_base": [0.04, 0.76, -0.05],
	},
	# Pistolet à deux mains, main d'appui en coupe (§2.2quinquies : le P-19 est tenu à DEUX MAINS).
	"cup": {
		"fingers": [[1.05, 0.95, 0.40], [1.12, 1.00, 0.44],
			[1.16, 1.04, 0.48], [1.20, 1.08, 0.52]],
		"thumb": [0.28, 0.2],
		"thumb_base": [0.0, -1.25, -0.2],
	},
	# Main ouverte : saisie de chargeur, levier d'armement, inspection.
	"open": {
		"fingers": [[0.35, 0.28, 0.14], [0.32, 0.26, 0.12],
			[0.34, 0.28, 0.14], [0.40, 0.32, 0.16]],
		"thumb": [0.12, 0.1],
		"thumb_base": [0.1, -0.8, -0.35],
	},
	# Pince : levier d'armement ou chargeur par le dos. Seule pose où index et majeur sont PLUS
	# fermés que l'annulaire et l'auriculaire.
	"pinch": {
		"fingers": [[0.95, 0.85, 0.55], [1.00, 0.90, 0.60],
			[0.70, 0.60, 0.35], [0.60, 0.50, 0.30]],
		"thumb": [0.62, 0.55],
		"thumb_base": [0.25, -0.75, -0.7],
	},
}

# ╔═ LES QUATRE DOIGTS ══════════════════════════════════════════════════════════════════════════╗
# ║ `x` : décalage latéral de la racine · `len` : les 3 phalanges · `r` : les 4 rayons.           ║
# ║ ⚠️ La racine est posée à **y = −0,006**, sur la moitié PALMAIRE de la main et non sur son axe.║
# ║ Mesuré : « 3.5 mm dorsal put every finger's axis 10 mm further from whatever the hand was     ║
# ║ gripping than the palm's own contact surface, so a palm placed flush on a handguard still     ║
# ║ left the fingers hovering **8-14 mm clear of it** — the daylight the critique measured. »     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const FINGER_SPECS := [
	{"x": 0.0298, "len": [0.045, 0.028, 0.022], "r": [0.0102, 0.0096, 0.0086, 0.0062]},
	{"x": 0.0102, "len": [0.049, 0.031, 0.023], "r": [0.0104, 0.0098, 0.0088, 0.0064]},
	{"x": -0.0104, "len": [0.046, 0.029, 0.022], "r": [0.0100, 0.0094, 0.0084, 0.0060]},
	{"x": -0.0298, "len": [0.038, 0.024, 0.020], "r": [0.0092, 0.0086, 0.0078, 0.0056]},
]


# =================================================================================================
# LE REPÈRE DE MAIN — port de `handBasis` (viewmodel.js:88)
# =================================================================================================
# « Right-handed hand basis from a finger direction and a back-of-hand direction. »
#
# ⚠️ Le +Z de la main est l'OPPOSÉ de la direction des doigts : les doigts pointent en −Z local.
# `back` n'est qu'une RÉFÉRENCE de roulis — on lui retire sa composante le long de +Z avant de le
# normaliser (Gram-Schmidt), donc il n'a pas besoin d'être perpendiculaire dans le modèle. Et il
# ne l'est jamais : sur le `chacal`, `finger·back = −0,383`, soit **67°** au lieu de 90.
#
# ⚠️ Ceci est ALGORITHMIQUEMENT IDENTIQUE à `Arm._aim_bone(dir, up)` — quatre étapes comparées une
# à une. On garde pourtant DEUX fonctions, et à dessein : `_aim_bone` oriente un OS de la chaîne
# (son repli pointe vers −Z quand la direction est nulle, ce qui a un sens pour un os), tandis que
# `hand_basis` construit une CIBLE de main à partir de deux directions d'auteur lues dans le
# modèle d'arme. Les fusionner ferait dépendre le solveur d'IK d'un repli choisi pour un nœud de
# données, et l'inverse. Le doublon est de 6 lignes ; le couplage aurait duré tout le chantier.
#
# Vit ici, et pas dans la sonde, pour que les sabotages mordent du CODE DE PRODUCTION : une sonde
# qui contient elle-même la logique qu'elle contrôle ne contrôle qu'elle-même.
static func hand_basis(finger: Vector3, back: Vector3) -> Quaternion:
	var z := -finger
	if z.length_squared() < 1e-9:
		z = Vector3(0, 0, -1)
	z = z.normalized()
	var y := back - z * back.dot(z)
	if y.length_squared() < 1e-8:
		y = Vector3(0, 1, 0)
		y -= z * z.y
	y = y.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z).get_rotation_quaternion()


# =================================================================================================
# PRIMITIVES ANATOMIQUES
# =================================================================================================

# Une phalange. ⚠️ Aplatie à 0,88 en Y : « fingers are wider than they are deep » — et c'est ce qui
# met la paroi latérale exactement à `r` en X, donc là où la couture doit se poser.
static func _segment(length: float, r0: float, r1: float):
	var g = Meshgen.lathe_z([
		[0, 0], [0, r0 * 0.86], [r0 * 0.5, r0],
		[length * 0.42, r0 * 0.99], [length * 0.55, r1 * 1.04],
		[length - r1 * 0.7, r1], [length - r1 * 0.2, r1 * 0.8],
		[length, r1 * 0.35], [length, 0],
	], FINGER_SEG)
	g.scale_by(1.0, 0.88, 1.0)
	g.rotate_y(PI)
	return g


# Le coussinet palmaire d'une phalange.
static func _segment_pad(length: float, r: float):
	return Meshgen.blob(r * 1.55, r * 0.55, length * 0.78, r * 0.25, 2) \
		.translate(0, r * 0.78, -length * 0.46)


# ╔═ LES COUTURES — leur seule raison d'être est de séparer les doigts EN PIXELS ═════════════════╗
# ║ « at 40 px across the whole hand the four fingers merge into ONE PADDLE, and the only thing   ║
# ║ that still separates them is a light line at each boundary. A 1.5 mm strip at 1.4x the shell  ║
# ║ albedo survives to about 3 px, which is one pixel of separation per finger — enough. »        ║
# ║ ⚠️ Sur les DEUX flancs : « One seam per finger leaves three boundaries out of five unmarked ». ║
# ║ Et sur les deux premières phalanges seulement — « the distal phalanx is 22 mm long and a seam ║
# ║ on it is sub-pixel ».                                                                         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func _segment_seam(length: float, r0: float, r1: float, sx: float):
	return Meshgen.box(0.0015, (r0 + r1) * 0.34, length * 0.86, 0.0003, 1) \
		.translate(sx * (r0 + r1) * 0.49, r0 * 0.1, -length * 0.47)


# =================================================================================================
# `Arm` — un bras complet
# =================================================================================================
class Arm:
	extends RefCounted

	# `side` : −1 = bras GAUCHE, +1 = bras DROIT.
	var side := -1.0
	var scale_f := 1.0
	var l1 := 0.33
	var l2 := 0.30
	var shoulder := Vector3.ZERO
	# ╔═ LE PÔLE DE COUDE EST EN ESPACE RIG, PAS EN ESPACE MAIN ═════════════════════════════════╗
	# ║ « Expressing the pole in hand space is the intuitive choice and it is WRONG: the support   ║
	# ║ hand is rolled palm-up on the handguard, so its local "down" points at the sky and the     ║
	# ║ elbow swings UP — straight through the near plane, filling half the screen with forearm.   ║
	# ║ **Elbows go down and outboard, always**, exactly as they do on a real shooter. »           ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var pole := Vector3.ZERO

	# L'arbre de nœuds. `upper_pivot`, `fore_pivot` et `hand` sont TROIS FRÈRES (cf. en-tête).
	var root: Node3D
	var upper_pivot: Node3D
	var fore_pivot: Node3D
	var hand: Node3D
	var hand_inner: Node3D

	# Les articulations : `fingers[i][j]` et `thumb_joints[j]` sont des `Node3D` dont seule la
	# rotation X est pilotée (flexion pure — un seul degré de liberté, comme chez eux).
	var fingers := []
	var finger_roots := []
	var thumb_root: Node3D
	var thumb_joints := []

	# Cache de poses PAR ARME. « a pose solved against one weapon's handguard cannot leak onto
	# another's — and, critically, a clip that swaps the support hand to 'open' and back to 'clamp'
	# restores the FITTED clamp, not the authored one. »
	var poses := {}
	var pose := "wrap"

	var elbow := Vector3.ZERO

	# ╔═ ⚠️⚠️ CHIRALITÉ DES ROTATIONS — LE PIÈGE QUE LE MAILLAGE MIROIR NE COUVRE PAS ═══════╗
	# ║ La référence retourne la main d'un seul geste : `handInner.scale.x = -1` sur le NŒUD. ║
	# ║ Le miroir traverse alors tout le sous-arbre — positions ET rotations — gratuitement.  ║
	# ║ Nous avons cuit le miroir dans le MAILLAGE (une échelle négative sur un `Node3D`      ║
	# ║ Godot retourne les faces et ne se relit pas fidèlement), ce qui laisse la hiérarchie  ║
	# ║ d'articulations à notre charge — et c'est une dette qu'il faut payer EXPLICITEMENT.   ║
	# ║                                                                                       ║
	# ║ Sous un miroir en X, une rotation autour de **X est PRÉSERVÉE**, une rotation autour   ║
	# ║ de **Y ou Z change de SIGNE** (M·Rx·M = Rx, M·Ry·M = Ry⁻¹, M·Rz·M = Rz⁻¹). Toutes les  ║
	# ║ flexions de doigt et de pouce sont des rotations en X pures : elles ne demandent      ║
	# ║ rien. **La base du pouce est la SEULE rotation à trois composantes du rig** — et donc  ║
	# ║ le seul endroit où l'oubli se paie.                                                   ║
	# ║                                                                                       ║
	# ║ 🩸 MESURÉ, et invisible autrement : sans ce facteur, le bout du pouce tombait à        ║
	# ║ **−16,8 mm** (il franchit l'axe de la main : la prise en C) sur le bras GAUCHE, et à   ║
	# ║ **−90,8 mm** sur le bras DROIT — au lieu de +16,8. Les deux pouces partaient dans la   ║
	# ║ même direction ABSOLUE : le droit ne serrait rien, il pointait dans le vide. Aucun     ║
	# ║ contrôle de position de racine ne l'attrape, puisque les racines, elles, SONT miroir.  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════╝
	var chir := 1.0


	func _init(p_side: float, mats: Dictionary, opts := {}) -> void:
		side = p_side
		scale_f = float(opts.get("scale", 1.0))
		l1 = float(opts.get("upper", L_UPPER)) * scale_f
		l2 = float(opts.get("fore", L_FORE)) * scale_f
		shoulder = Vector3(
			float(opts.get("shoulderX", 0.19)) * side,
			float(opts.get("shoulderY", -0.19)),
			float(opts.get("shoulderZ", 0.12)))
		pole = Vector3(side * 0.46, -0.86, 0.22).normalized()

		root = Node3D.new()
		root.name = "arm-" + ("right" if side > 0.0 else "left")
		upper_pivot = Node3D.new()
		fore_pivot = Node3D.new()
		hand = Node3D.new()
		hand.name = "hand-" + ("right" if side > 0.0 else "left")
		hand_inner = Node3D.new()
		root.add_child(upper_pivot)
		root.add_child(fore_pivot)
		root.add_child(hand)
		hand.add_child(hand_inner)

		_build_sleeves(mats)
		_build_hand(mats)
		set_pose(String(opts.get("pose", "wrap")))


	func _build_sleeves(mats: Dictionary) -> void:
		var mat_sleeve: String = mats.get("sleeve", "sleeve")
		upper_pivot.add_child(_mesh_node(
			TrenchHands.build_sleeve(l1, 0.044 * scale_f, 0.036 * scale_f, 5, false, true),
			mat_sleeve, "upper"))
		fore_pivot.add_child(_mesh_node(
			TrenchHands.build_sleeve(l2, 0.034 * scale_f, 0.024 * scale_f, 7, true, false),
			mat_sleeve, "fore"))


	func _build_hand(mats: Dictionary) -> void:
		var s := scale_f
		var glove: String = mats.get("glove", "glove")
		var pad: String = mats.get("pad", "glove_pad")
		var seam: String = mats.get("seam", mats.get("glove", "glove_seam"))

		# ⚠️ LE MIROIR DE CHIRALITÉ, CUIT DANS LE MAILLAGE (cf. l'en-tête du fichier).
		# Le maillage écrit est une main GAUCHE : c'est le bras DROIT qu'il faut retourner.
		var mirror := side > 0.0

		var shell = TrenchHands.build_glove_shell(s)
		var pads = TrenchHands.build_glove_pads(s)
		var seams = TrenchHands.build_glove_seams(s)
		if mirror:
			shell.apply_transform(Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)),
				Vector3.ZERO))
			pads.apply_transform(Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)),
				Vector3.ZERO))
			seams.apply_transform(Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)),
				Vector3.ZERO))
		hand_inner.add_child(_mesh_node(shell, glove, "glove"))
		hand_inner.add_child(_mesh_node(pads, pad, "glove-pads"))
		hand_inner.add_child(_mesh_node(seams, seam, "glove-seams"))

		# Les quatre doigts.
		for i in 4:
			var spec: Dictionary = TrenchHands.FINGER_SPECS[i]
			var fr := Node3D.new()
			fr.name = "finger%d" % i
			var fx: float = float(spec["x"]) * (-1.0 if mirror else 1.0)
			fr.position = Vector3(fx * s, -0.006 * s, -0.096 * s)
			# ⚠️ L'ÉVENTAIL utilise `x` NON MIS À L'ÉCHELLE — reproduit tel quel (leur incohérence,
			# consignée dans le rapport de cartographie). L'écart vaut ~3,8° au maximum.
			fr.rotation = Vector3(0, -float(spec["x"]) * 2.2 * (-1.0 if mirror else 1.0), 0)
			hand_inner.add_child(fr)
			finger_roots.append(fr)
			var joints := []
			var parent: Node3D = fr
			for j in 3:
				var jn := Node3D.new()
				jn.name = "j%d" % j
				if j > 0:
					jn.position = Vector3(0, 0, -float(spec["len"][j - 1]) * s)
				parent.add_child(jn)
				var ln: float = float(spec["len"][j]) * s
				var r0: float = float(spec["r"][j]) * s
				var r1: float = float(spec["r"][j + 1]) * s
				var pieces := [TrenchHands._segment(ln, r0, r1)]
				if j < 2:
					for sx in [-1.0, 1.0]:
						pieces.append(TrenchHands._segment_seam(ln, r0, r1, sx))
				jn.add_child(_mesh_node(TrenchHands.Meshgen.merge_all(pieces), glove, "seg"))
				if j < 2:
					jn.add_child(_mesh_node(TrenchHands._segment_pad(ln, r1), pad, "pad"))
				else:
					# Pulpe distale — mêmes nombres que le patch du solveur, « so the mask and the
					# mesh agree ».
					jn.add_child(_mesh_node(
						TrenchHands.Meshgen.blob(r1 * 1.5, r1 * 0.5, ln * 0.7, r1 * 0.2, 2)
							.translate(0, -r1 * 0.72, -ln * 0.45), pad, "tip"))
				joints.append(jn)
				parent = jn
			fingers.append(joints)

		# Le pouce. ⚠️ Sa base est PALMAIRE : « a thumb rooted on the hand's centre plane rotates in
		# the plane of the back of the hand, which is why the old one read as a SPUR ».
		thumb_root = Node3D.new()
		thumb_root.name = "thumb"
		chir = -1.0 if mirror else 1.0
		var tx := 0.037 * s * chir
		thumb_root.position = Vector3(tx, -0.009 * s, -0.04 * s)
		# ⚠️ Y **et** Z portent le facteur — la version d'origine n'appliquait le miroir qu'à Y
		# et laissait le Z de −0,5 identique des deux côtés.
		thumb_root.rotation = Vector3(0.2, -0.95 * chir, -0.5 * chir)
		hand_inner.add_child(thumb_root)
		var tparent: Node3D = thumb_root
		var tl := [TrenchHands.THUMB_L0 * s, TrenchHands.THUMB_L1 * s]
		var tr := [TrenchHands.THUMB_R0 * s, TrenchHands.THUMB_R1 * s, TrenchHands.THUMB_R2 * s]
		for j in 2:
			var jn := Node3D.new()
			jn.name = "tj%d" % j
			if j > 0:
				jn.position = Vector3(0, 0, -tl[0])
			tparent.add_child(jn)
			var pieces := [TrenchHands._segment(tl[j], tr[j], tr[j + 1])]
			jn.add_child(_mesh_node(TrenchHands.Meshgen.merge_all(pieces), glove, "tseg"))
			if j == 0:
				jn.add_child(_mesh_node(TrenchHands._segment_pad(tl[0], tr[1]), pad, "tpad"))
			else:
				jn.add_child(_mesh_node(
					TrenchHands.Meshgen.blob(tr[2] * 1.6, tr[2] * 0.55, tl[1] * 0.66, 0.0012, 2)
						.translate(0, -tr[2] * 0.78, -tl[1] * 0.45), pad, "tpalm"))
				# L'ongle — seul le pouce en a un.
				jn.add_child(_mesh_node(
					TrenchHands.Meshgen.blob(0.011 * s, 0.0035 * s, 0.016 * s, 0.0012, 2)
						.translate(0, tr[2], -0.016 * s), pad, "nail"))
			thumb_joints.append(jn)
			tparent = jn


	func _mesh_node(data, mat_key: String, nom: String) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.name = nom
		mi.mesh = TrenchHands.Meshgen.to_array_mesh(data)
		# ⚠️ La géométrie vit LOIN de son origine locale : sans ça, Godot la ferait disparaître dès
		# qu'elle sort du cône de vue de son propre point d'origine. (`frustumCulled = false` chez
		# eux, pour exactement la même raison.)
		mi.extra_cull_margin = 1.0
		mi.set_meta("mat_key", mat_key)
		return mi


	# ── POSES ───────────────────────────────────────────────────────────────────────────────────
	# ⚠️ Lit `poses` (le cache AJUSTÉ par arme) AVANT `HAND_POSES` (la pose écrite à la main).
	func set_pose(name: String) -> void:
		var p: Dictionary = poses.get(name, TrenchHands.HAND_POSES.get(name,
			TrenchHands.HAND_POSES["wrap"]))
		for i in mini(4, fingers.size()):
			var curl: Array = p["fingers"][i]
			for j in 3:
				fingers[i][j].rotation.x = -float(curl[j])
		if thumb_joints.size() == 2:
			thumb_joints[0].rotation.x = -float(p["thumb"][0])
			thumb_joints[1].rotation.x = -float(p["thumb"][1])
		if p.has("thumb_base") and thumb_root != null:
			var tb: Array = p["thumb_base"]
			# Les six poses de `HAND_POSES` sont écrites dans la convention de la main GAUCHE
			# (celle du maillage d'origine, cf. « the authored mesh is a LEFT hand »).
			thumb_root.rotation = Vector3(float(tb[0]), float(tb[1]) * chir, float(tb[2]) * chir)
		pose = name


	# L'index seul, piloté par la détente. `t` ∈ [0, 1].
	# ⚠️ La pose de repos correspond EXACTEMENT à `HAND_POSES.grip.fingers[0]`.
	func set_trigger(t: float) -> void:
		if fingers.is_empty():
			return
		var c: float = clampf(t, 0.0, 1.0)
		fingers[0][0].rotation.x = -(0.55 + 0.30 * c)
		fingers[0][1].rotation.x = -(0.72 + 0.42 * c)
		fingers[0][2].rotation.x = -(0.34 + 0.30 * c)


	# ── LE SOLVEUR À DEUX OS ────────────────────────────────────────────────────────────────────
	# ⚠️ LA MAIN EST POSÉE EN PREMIER, SANS CONDITION — même si le bras ne peut pas l'atteindre.
	# Le clamp de portée modifie la CIBLE INTERNE, jamais `hand.position` : le bras se détache
	# visuellement de la main plutôt que de faire glisser la main sur la poignée.
	func solve(target_pos: Vector3, target_quat: Quaternion) -> void:
		hand.position = target_pos
		hand.quaternion = target_quat

		var t := target_pos - shoulder
		var d := t.length()
		var max_d := (l1 + l2) * 0.995
		var min_d := absf(l1 - l2) * 1.05 + 1e-4
		if d > max_d:
			t = t * (max_d / d)
			d = max_d
		elif d < min_d:
			if d < 1e-5:
				t = Vector3(0, 0, -min_d)
			else:
				t = t * (min_d / d)
			d = min_d
		var dir := t / d

		# Cercle des coudes possibles. Le `max(0, …)` est le filet contre l'arrondi.
		var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var h := sqrt(maxf(0.0, l1 * l1 - a * a))
		var perp := pole - dir * pole.dot(dir)
		if perp.length_squared() < 1e-8:
			var f := Vector3(side, -1, 0)
			perp = f - dir * f.dot(dir)
		perp = perp.normalized()
		elbow = shoulder + dir * a + perp * h

		# ⚠️ Le roulis de l'humérus prend `perp` comme référence de haut : « The elbow pad sits on
		# the bone's +Y, which must end up on the OUTSIDE of the bend — that is the pole side. »
		upper_pivot.position = shoulder
		upper_pivot.quaternion = _aim_bone(elbow - shoulder, perp)
		# Le roulis de l'avant-bras suit le DOS DE LA MAIN, pour aligner manchette et poignet.
		fore_pivot.position = elbow
		var up := target_quat * Vector3(0, 1, 0)
		fore_pivot.quaternion = _aim_bone(target_pos - elbow, up)


	# ╔═ POURQUOI PAS `look_at()` ═══════════════════════════════════════════════════════════════╗
	# ║ « This deliberately does NOT use Object3D.lookAt(): for non-camera objects lookAt aims     ║
	# ║ local **+Z** at the target (so a −Z bone would point BACKWARDS), and it interprets the     ║
	# ║ target in WORLD space, which is wrong here because every joint position is authored in the ║
	# ║ rig's local space. » Godot a exactement le même piège avec `Node3D.look_at`.               ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	static func _aim_bone(dir: Vector3, up: Vector3) -> Quaternion:
		var z := -dir
		if z.length_squared() < 1e-9:
			z = Vector3(0, 0, -1)
		z = z.normalized()
		var y := up - z * up.dot(z)
		if y.length_squared() < 1e-9:
			y = Vector3(0, 1, 0) - z * z.y
			if y.length_squared() < 1e-9:
				y = Vector3(1, 0, 0) - z * z.x
		y = y.normalized()
		var x := y.cross(z).normalized()
		return Basis(x, y, z).get_rotation_quaternion()


	# ── LE SOLVEUR DE CONTACT ───────────────────────────────────────────────────────────────────
	# ╔═ IL TOURNE UNE SEULE FOIS, AU BUILD — et il MESURE au lieu de calculer ═══════════════════╗
	# ║ Leur solveur analytique a échoué pour quatre raisons cumulées, qu'ils énumèrent : « the    ║
	# ║ analytic solve ignored (a) the 0.88 Y-scale on the finger capsules, (b) the −6 mm palmar   ║
	# ║ offset of the MCP row, (c) the fan-out rotation on each finger root and (d) the fact that  ║
	# ║ the four fingers start at four different X, so they meet the cylinder at four different    ║
	# ║ CLOCK ANGLES. » D'où : « Rather than push more algebra at it, **MEASURE it** ».            ║
	# ║                                                                                            ║
	# ║ ⚠️ BALAYAGE, PAS DICHOTOMIE : « the gap is NOT MONOTONIC in curl (past ~110 deg the tip    ║
	# ║ starts coming back OUT the far side of the tube), so a bisection can converge on the wrong ║
	# ║ root ». 49 échantillons sur la plage anatomique = 2,5° de résolution, soit 0,4 mm au bout. ║
	# ║                                                                                            ║
	# ║ ⚠️ PROXIMAL D'ABORD : « Fitting only the distal joint CANNOT wrap a cylinder […] Solving   ║
	# ║ the chain outward — each joint placing the NEXT joint's origin one finger-radius off the   ║
	# ║ surface, then the distal joint placing the actual contact patch on it — is what a finger   ║
	# ║ does, and it is stable because each stage only has ONE degree of freedom. »                ║
	# ║                                                                                            ║
	# ║ ⚠️ ÉCART D'IMPLÉMENTATION : eux remontent la chaîne de matrices du moteur à chaque          ║
	# ║ échantillon (~1000 `updateWorldMatrix` par ajustement). Ici la chaîne est composée À LA     ║
	# ║ MAIN : c'est le même résultat, ça ne dépend pas de l'arbre de scène, et ça permet au        ║
	# ║ solveur de tourner AVANT que le rig ne soit monté.                                         ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	func fit_to_cylinder(hand_pos: Vector3, hand_quat: Quaternion, axis_point: Vector3,
			axis_dir: Vector3, radius: float, opts := {}) -> Array:
		var clearance: float = opts.get("clearance", 0.001)
		var pose_name: String = opts.get("poseName", "clamp")
		set_pose(pose_name)
		hand.position = hand_pos
		hand.quaternion = hand_quat
		var axis := axis_dir.normalized()
		var contacts := []

		# Transform de la main dans l'espace `root`.
		var hand_x: Transform3D = Transform3D(Basis(hand_quat), hand_pos) * hand_inner.transform

		for i in fingers.size():
			var spec: Dictionary = TrenchHands.FINGER_SPECS[i]
			var ll := []
			var rr := []
			for k in 3:
				ll.append(float(spec["len"][k]) * scale_f)
			for k in 4:
				rr.append(float(spec["r"][k]) * scale_f)
			var base_x: Transform3D = hand_x * (finger_roots[i] as Node3D).transform
			# Articulations 0 et 1 : la cible est l'ORIGINE DE L'ARTICULATION SUIVANTE, qui est sur
			# l'axe du doigt — elle doit donc s'arrêter à un rayon de segment de la surface.
			for j in 2:
				_fit_joint(base_x, fingers[i], j, Vector3(0, 0, -ll[j]),
					-1.75, -0.05, rr[j + 1] * 0.92, axis_point, axis, radius, clearance)
			# Articulation 2 : la cible est le PATCH DE PULPE, côté paume.
			_fit_joint(base_x, fingers[i], 2, Vector3(0, -rr[3] * 1.05, -ll[2] * 0.5),
				-1.95, -0.1, 0.0, axis_point, axis, radius, clearance)
			contacts.append(_joint_point(base_x, fingers[i], 2,
				Vector3(0, -rr[3] * 1.05, -ll[2] * 0.5)))

		# ── LE POUCE, DE L'AUTRE CÔTÉ DU TUBE ──────────────────────────────────────────────────
		# ⚠️ Sa cause de défaillance était mesurée et n'était PAS un problème de visée : « the four
		# fingertips landed 0.4-0.7 mm off the handguard — a genuine grip — and the THUMB TIP was
		# **13.5 mm clear of it** ». Et : « The cause is that the two flexion joints were being
		# fitted against a base rotation that was AUTHORED, not solved. »
		# ⚠️ DEUX AXES, PAS UN : « scanning abduction alone still left the tip 13.2 mm clear […] a
		# 68 mm thumb only reaches if it is aimed at the surface in BOTH the across-the-palm and the
		# up-off-the-palm sense. 21 x 15 samples, build time. »
		if thumb_joints.size() == 2:
			var tb: Array = TrenchHands.HAND_POSES.get(pose_name,
				TrenchHands.HAND_POSES["clamp"])["thumb_base"]
			# Dans le repère du BRAS : le rappel vers la pose écrite doit tirer vers la pose écrite
			# TRADUITE, sinon sur la main droite il tire vers son symétrique — c'est-à-dire à
			# l'opposé exact de l'endroit voulu.
			var y0 := float(tb[1]) * chir
			var z0 := float(tb[2]) * chir
			# Pré-flexion pendant le balayage de base, pour mesurer où atterrit un pouce
			# naturellement recourbé.
			thumb_joints[0].rotation.x = -0.55
			thumb_joints[1].rotation.x = -0.45
			var best_cost := INF
			var best_y := y0
			var best_z := z0
			for iy in 21:
				var yy := y0 - 1.3 + (2.6 * float(iy) / 20.0)
				for iz in 15:
					var zz := z0 - 0.9 + (1.8 * float(iz) / 14.0)
					thumb_root.rotation = Vector3(float(tb[0]), yy, zz)
					var bx: Transform3D = hand_x * thumb_root.transform
					var g := _gap(_joint_point(bx, thumb_joints, 1,
						Vector3(0, -TrenchHands.THUMB_R2 * scale_f * 1.05,
							-TrenchHands.THUMB_L1 * scale_f * 0.55)),
						axis_point, axis, radius)
					# ⚠️ Le terme de RAPPEL vers la pose écrite à la main (0,0009) est ce qui
					# empêche le solveur de trouver une solution géométriquement valide mais
					# anatomiquement absurde.
					var cost := absf(g - clearance) + (absf(yy - y0) + absf(zz - z0)) * 0.0009
					if g < -0.002:
						cost += (-g - 0.002) * 10.0
					if cost < best_cost:
						best_cost = cost
						best_y = yy
						best_z = zz
			thumb_root.rotation = Vector3(float(tb[0]), best_y, best_z)
			var tbx: Transform3D = hand_x * thumb_root.transform
			# ⚠️⚠️ ICI ON S'ÉCARTE DE LA RÉFÉRENCE — et voici EXACTEMENT ce qui est mesuré.
			#
			# Elle enchaîne DEUX ajustements gloutons, articulation par articulation, chacun visant
			# l'origine de la SUIVANTE. Le substitut n'est pas la quantité qui compte : la flexion
			# proximale plaque sa phalange sur le tube sans savoir si la distale pourra encore
			# rattraper, et la distale n'a qu'un degré de liberté pour le faire.
			#
			# Deux poses de main mesurées, même arme, même tube de 27,1 mm :
			#
			#   pose            séquentiel (réf.)   descente conjointe
			#   ─────────────   ─────────────────   ──────────────────
			#   approche oblique      20,2 mm              0,47 mm
			#   approche franche       0,48 mm             0,48 mm
			#
			# ⚠️ La lecture honnête n'est PAS « leur solveur est cassé » : sur une approche franche
			# les deux donnent le même résultat, et leurs poses à eux sont dérivées du garde-main
			# réel, donc franches. Elle est : **le glouton est FRAGILE, la descente ne l'est pas.**
			# Elle n'est jamais pire (elle décroît le même coût à chaque pas depuis la même pose de
			# départ) et elle tient quand l'approche se dégrade. Or chez nous les poses de main
			# viendront du lot 3D-F et bougeront à chaque réglage d'arme : c'est précisément le cas
			# où une méthode qui perd 20 mm sur une approche oblique coûte cher, et en silence.
			#
			# Le remède : descente par coordonnées sur le coût COMPLET. Chaque passe balaie une
			# flexion de façon exhaustive (mêmes 49 échantillons que la référence) mais évalue le
			# BOUT DU POUCE ; la phalange n'est plus qu'un rappel de forme à poids réduit, plus une
			# pénalité si elle s'enfonce.
			#   Contre-épreuve : un balayage exhaustif 49×49 des DEUX flexions à la même base trouve
			#   0,5 mm — la descente atteint donc l'optimum, elle ne s'arrête pas en chemin.
			#
			# ⚠️ NE PAS étendre ce traitement aux QUATRE DOIGTS sans le remesurer. Essayé : la pulpe
			# de l'index passe de 5,1 à 4,3 mm, mais celle du majeur atteint 0,4 mm **en faisant
			# traverser le garde-main à sa phalange proximale sur 21 mm**. Le pouce a deux flexions
			# et un enroulement court ; un doigt en a trois et doit ENVELOPPER — le compromis entre
			# « toucher » et « ne pas traverser » n'y a pas le même équilibre, et une pulpe posée sur
			# une phalange enfouie est un défaut PIRE que 5 mm de jour, puisqu'il se voit.
			_fit_thumb_flexions(tbx, axis_point, axis, radius, clearance)
			contacts.append(_joint_point(tbx, thumb_joints, 1,
				Vector3(0, -TrenchHands.THUMB_R2 * scale_f * 1.05,
					-TrenchHands.THUMB_L1 * scale_f * 0.55)))
			# Mémorise la pose AJUSTÉE sous sa propre clé.
			var fitted := {"fingers": [], "thumb": [
				-thumb_joints[0].rotation.x, -thumb_joints[1].rotation.x],
				# ⚠️ Retour en convention ÉCRITE (main gauche) : `set_pose` réappliquera `chir`.
				"thumb_base": [float(tb[0]), best_y * chir, best_z * chir]}
			for i in fingers.size():
				fitted["fingers"].append([
					-fingers[i][0].rotation.x, -fingers[i][1].rotation.x,
					-fingers[i][2].rotation.x])
			poses[pose_name] = fitted
			pose = pose_name
		return contacts


	# Mesure les 5 écarts de contact SANS rien ajuster — c'est le témoin qui permet de dire si le
	# solveur a fait son travail, plutôt que de constater un chiffre absolu qui dépend surtout de la
	# qualité de la pose de main qu'on lui a donnée.
	func measure_contacts(hand_pos: Vector3, hand_quat: Quaternion, axis_point: Vector3,
			axis_dir: Vector3, radius: float) -> Array:
		hand.position = hand_pos
		hand.quaternion = hand_quat
		var axis := axis_dir.normalized()
		var hand_x: Transform3D = Transform3D(Basis(hand_quat), hand_pos) * hand_inner.transform
		var out := []
		for i in fingers.size():
			var spec: Dictionary = TrenchHands.FINGER_SPECS[i]
			var base_x: Transform3D = hand_x * (finger_roots[i] as Node3D).transform
			var p := _joint_point(base_x, fingers[i], 2, Vector3(
				0, -float(spec["r"][3]) * scale_f * 1.05,
				-float(spec["len"][2]) * scale_f * 0.5))
			out.append(_gap(p, axis_point, axis, radius))
		if thumb_joints.size() == 2:
			var tbx: Transform3D = hand_x * thumb_root.transform
			var tp := _joint_point(tbx, thumb_joints, 1, Vector3(
				0, -TrenchHands.THUMB_R2 * scale_f * 1.05,
				-TrenchHands.THUMB_L1 * scale_f * 0.55))
			out.append(_gap(tp, axis_point, axis, radius))
		return out


	# Descente par coordonnées sur les DEUX flexions du pouce, contre le coût COMPLET.
	# `passes` = 3 : mesuré, la 2ᵉ passe ne bouge déjà plus les angles de plus de 0,03 rad.
	func _fit_thumb_flexions(base_x: Transform3D, axis_point: Vector3, axis: Vector3,
		radius: float, clearance: float) -> void:
		var tip := Vector3(0, -TrenchHands.THUMB_R2 * scale_f * 1.05,
			-TrenchHands.THUMB_L1 * scale_f * 0.55)
		var knuckle := Vector3(0, 0, -TrenchHands.THUMB_L0 * scale_f)
		var standoff: float = TrenchHands.THUMB_R1 * scale_f
		var lo := [-1.45, -1.6]
		var hi := [-0.02, -0.05]
		for p in 3:
			for j in 2:
				var a0: float = float(lo[j])
				var a1: float = float(hi[j])
				var best := a0
				var best_cost := INF
				for i in 49:
					thumb_joints[j].rotation.x = a0 + (a1 - a0) * (float(i) / 48.0)
					# Ce qui compte : le bout du pouce sur la surface.
					var gt := _gap(_joint_point(base_x, thumb_joints, 1, tip),
						axis_point, axis, radius)
					var cost := absf(gt - clearance * 0.5)
					if gt < -0.0015:
						cost += (-gt - 0.0015) * 8.0
					# Rappel de forme : la phalange VOUDRAIT toucher, mais elle cède au bout.
					var gk := _gap(_joint_point(base_x, thumb_joints, 0, knuckle),
						axis_point, axis, radius) - standoff
					cost += 0.25 * absf(gk - clearance * 0.5)
					if gk < -0.0015:
						cost += (-gk - 0.0015) * 8.0
					if cost < best_cost:
						best_cost = cost
						best = thumb_joints[j].rotation.x
				thumb_joints[j].rotation.x = best


	# Balayage exhaustif à 49 échantillons d'un seul degré de liberté.
	func _fit_joint(base_x: Transform3D, chain: Array, j: int, local: Vector3,
			lo: float, hi: float, standoff: float, axis_point: Vector3, axis: Vector3,
			radius: float, clearance: float) -> void:
		var best := lo
		var best_cost := INF
		for i in 49:
			var ang := lo + (hi - lo) * (float(i) / 48.0)
			chain[j].rotation.x = ang
			var g := _gap(_joint_point(base_x, chain, j, local), axis_point, axis, radius)
			g -= standoff
			var cost := absf(g - clearance * 0.5)
			if g < -0.0015:
				cost += (-g - 0.0015) * 8.0
			if cost < best_cost:
				best_cost = cost
				best = ang
		chain[j].rotation.x = best


	# Compose la chaîne À LA MAIN jusqu'à l'articulation `j`, et rend le point `local` en espace
	# `root`. Aucune dépendance à l'arbre de scène.
	func _joint_point(base_x: Transform3D, chain: Array, j: int, local: Vector3) -> Vector3:
		var t := base_x
		for k in j + 1:
			t = t * chain[k].transform
		return t * local


	# Distance SIGNÉE d'un point à la surface d'un cylindre infini.
	static func _gap(p: Vector3, axis_point: Vector3, axis: Vector3, radius: float) -> float:
		var d := p - axis_point
		d -= axis * d.dot(axis)
		return d.length() - radius


# =================================================================================================
# LES MANCHES ET LE GANT — maillages figés, jamais déformés
# =================================================================================================

# ╔═ POURQUOI 32 SEGMENTS SUR UNE MANCHE, ET POURQUOI TROIS INFLEXIONS ══════════════════════════╗
# ║ « The support forearm's closest approach to the eye is ~0.38 m and it is ~120 px wide, so a   ║
# ║ 20-gon puts a facet sagitta of 0.7 px on the silhouette — COUNTABLE, and countable facets are ║
# ║ exactly what the critique measured. 32 takes it to 0.28 px, under the AA threshold. »         ║
# ║                                                                                               ║
# ║ « A sleeved forearm has three things a cone does not: the fabric is loose so it BELLS slightly║
# ║ behind the elbow, it is pulled TIGHT over the muscle belly a third of the way down, and it    ║
# ║ BUNCHES again at the cuff. »                                                                  ║
# ║                                                                                               ║
# ║ ⚠️ Les deux bouts sont FERMÉS : « an open lathe reads as a length of PIPE, which is exactly   ║
# ║ the "grey sausage" failure this rig has to avoid. »                                           ║
# ║                                                                                               ║
# ║ ⚠️ RAYONS MESURÉS DEUX FOIS : « At 78 mm across the elbow / 54 mm at the wrist the support    ║
# ║ forearm rendered as a 160 px-wide smooth tube crossing the lower third of every hipfire frame ║
# ║ — "a huge untextured tan tube", and **the single most-cited defect in the whole build**. »    ║
# ║ « every millimetre of radius is 2.6 px of screen at 1080p ». Et les plis vont en AUGMENTANT,  ║
# ║ pas en diminuant : « with the tube narrower the folds are what carry the silhouette ».        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func build_sleeve(length: float, r0: float, r1: float, folds: int,
		cuff: bool, elbow_pad: bool):
	var parts := []
	parts.append(Meshgen.lathe_z([
		[0, 0], [0, r0 * 0.55], [-0.004, r0 * 0.82], [-0.006, r0 * 0.98], [0.004, r0],
		[length * 0.16, r0 * 1.03], [length * 0.34, r0 * 0.9],
		[length * 0.52, (r0 + r1) * 0.5], [length * 0.72, r1 * 1.1],
		[length - 0.016, r1 * 1.0], [length - 0.005, r1 * 1.07],
		[length, r1 * 0.98], [length + 0.003, r1 * 0.8], [length + 0.004, 0],
	], SLEEVE_SEG))
	# La masse d'articulation au coude / poignet.
	parts.append(Meshgen.lathe_z([
		[length - r1 * 1.1, 0], [length - r1 * 0.9, r1 * 0.75], [length - r1 * 0.2, r1 * 1.04],
		[length + r1 * 0.5, r1 * 0.9], [length + r1 * 0.8, r1 * 0.4], [length + r1 * 0.85, 0],
	], 20).scale_by(1.0, 0.94, 1.0))
	# ╔═ LES ANNEAUX DE PLI — la seule source de CREUX de tout le membre ═════════════════════════╗
	# ║ « These are NOT decoration: they are the only concave creases on the whole limb, and the   ║
	# ║ curvature mask bake turns every one of them into a grime line with a dust-rubbed crown     ║
	# ║ either side. **That is what puts texture on a surface whose albedo is 0.013 linear.** »    ║
	# ║ « Ellipticity and a per-fold radius JITTER matter as much as the count: eight identical    ║
	# ║ circular rings equally spaced read as a HOSE. »                                            ║
	# ║ ⚠️ Le tremblement est DÉTERMINISTE (deux sinus), « so captures stay byte-identical ».      ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	for i in folds:
		var t := 0.14 + (float(i) / float(maxi(1, folds - 1))) * 0.7
		var j := sin(i * 2.399 + 0.7) * 0.5 + sin(i * 5.13) * 0.25
		var r := (r0 + (r1 - r0) * t) * (1.0 + j * 0.06)
		parts.append(Meshgen.ring(r * 0.985, r * (0.085 + j * 0.03), 24, 6)
			.rotate_x(PI * 0.5).rotate_y(j * 0.12).scale_by(1.0, 0.93, 1.0)
			.translate(0, 0, length * t + j * 0.004))
	# Deux rides longitudinales.
	for sx in [-1.0, 1.0]:
		parts.append(Meshgen.lathe_z([
			[length * 0.2, 0], [length * 0.3, r0 * 0.16], [length * 0.55, r0 * 0.2],
			[length * 0.78, r0 * 0.13], [length * 0.86, 0],
		], 10).scale_by(1.0, 0.5, 1.0).rotate_z(sx * 0.4)
			.translate(sx * (r0 + r1) * 0.46, -(r0 + r1) * 0.1, 0))
	if elbow_pad:
		parts.append(Meshgen.blob(r0 * 1.5, r0 * 0.6, length * 0.3, r0 * 0.3, 3)
			.translate(0, r0 * 0.75, length * 0.12))
	if cuff:
		# ⚠️ La manchette roulée est un TERMINATEUR DUR : « gives the wrist a hard terminator so the
		# sleeve does not appear to MELT into the glove. »
		parts.append(Meshgen.lathe_z([
			[length - 0.032, r1 * 1.02], [length - 0.029, r1 * 1.17],
			[length - 0.019, r1 * 1.16], [length - 0.016, r1 * 1.08],
			[length - 0.012, r1 * 1.08], [length - 0.009, r1 * 1.18],
			[length - 0.003, r1 * 1.17], [length, r1 * 1.02],
		], SLEEVE_SEG))
	var g = Meshgen.merge_all(parts)
	g.rotate_y(PI)
	return g


# ╔═ LA PAUME EN DEUX BLOCS, PAS UN ═════════════════════════════════════════════════════════════╗
# ║ « a single 88 x 98 mm slab is exactly what the support hand presents to the camera in a       ║
# ║ C-clamp and it reads as a BRICK. A hand is ~88 mm across the knuckles and ~72 mm across the   ║
# ║ wrist, so the taper is REAL and it is the difference between a hand silhouette and a paddle. »║
# ║                                                                                               ║
# ║ ⚠️ BUDGET DE COUVERTURE DORSALE — plafond 55 %, état actuel 30 %. Leur défaut mesuré :        ║
# ║ « because they all sat at the same height with the same material they merged into ONE         ║
# ║ continuous shelf across the whole dorsum. That shelf is the "stack of slabs" read, and no     ║
# ║ amount of retinting fixes it: what the eye is objecting to is that **the back of the hand has ║
# ║ no soft glove left on it**. » Les nervures tendineuses ont été supprimées pour cette raison.  ║
# ║ Les quatre capuchons SÉPARÉS et leurs trois jours sont tout le sujet : « they give the         ║
# ║ silhouette FOUR LOBES instead of one rectangle ».                                             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func build_glove_shell(s: float):
	var w := 0.088 * s
	var h := 0.032 * s
	var pl := 0.098 * s
	var parts := [
		Meshgen.blob(w, h, pl * 0.62, 0.012 * s, 3).translate(0, 0, -pl * 0.66),
		Meshgen.blob(w * 0.83, h * 0.96, pl * 0.52, 0.012 * s, 3)
			.translate(0, -h * 0.01, -pl * 0.26),
		# Éminence thénar (le renflement à la base du pouce).
		Meshgen.blob(w * 0.42, h * 0.92, pl * 0.6, 0.014 * s, 3)
			.translate(w * 0.3, -h * 0.06, -pl * 0.3),
		Meshgen.blob(w * 0.92, h * 0.86, 0.03 * s, 0.012 * s, 3)
			.translate(0, -h * 0.04, -0.012 * s),
	]
	# Les quatre bosses d'articulation.
	for i in 4:
		parts.append(Meshgen.dome(0.0072 * s, 10, 0.62).rotate_x(-PI * 0.5)
			.translate(w * (0.34 - i * 0.225), h * 0.42, -pl * 0.94))
	# La manchette et la sangle.
	parts.append(Meshgen.lathe_z([
		[0, w * 0.44], [0.004 * s, w * 0.47], [0.03 * s, w * 0.46], [0.034 * s, w * 0.42],
	], 16).scale_by(1.0, 0.82, 1.0).translate(0, 0, 0.004 * s))
	parts.append(Meshgen.lathe_z([
		[0, w * 0.47], [0.0022, w * 0.5], [0.009 * s, w * 0.5], [0.0112 * s, w * 0.47],
	], 16).scale_by(1.0, 0.82, 1.0).translate(0, 0, 0.02 * s))
	return Meshgen.merge_all(parts)


static func build_glove_pads(s: float):
	var w := 0.088 * s
	var h := 0.032 * s
	var pl := 0.098 * s
	var parts := []
	# Les quatre capuchons dorsaux, SÉPARÉS — c'est le jour entre eux qui fait la lecture.
	for i in 4:
		var drop: float = h * 0.055 if absf(i - 1.5) > 1.0 else 0.0
		parts.append(Meshgen.blob(w * 0.17, h * 0.3, pl * 0.3, 0.005 * s, 3)
			.translate(w * (0.335 - i * 0.223), h * 0.46 - drop, -pl * 0.82))
	# Panneau métacarpien + patch de paume.
	parts.append(Meshgen.blob(w * 0.44, h * 0.17, pl * 0.22, 0.005 * s, 3)
		.translate(0, h * 0.44, -pl * 0.4))
	parts.append(Meshgen.blob(w * 0.82, h * 0.18, pl * 0.66, 0.006 * s, 3)
		.translate(0, -h * 0.52, -pl * 0.48))
	return Meshgen.merge_all(parts)


static func build_glove_seams(s: float):
	var w := 0.088 * s
	var h := 0.032 * s
	var pl := 0.098 * s
	var parts := []
	for sx in [-1.0, 1.0]:
		parts.append(Meshgen.box(0.0016 * s, h * 0.5, pl * 0.8, 0.0004, 1)
			.translate(sx * w * 0.5, 0, -pl * 0.5))
	return Meshgen.merge_all(parts)
