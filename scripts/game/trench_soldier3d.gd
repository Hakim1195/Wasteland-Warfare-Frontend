extends Node3D
# =================================================================================================
# LOT 3D-G (2ᵉ moitié) — L'ASSEMBLEUR DU SOLDAT : accrocher le maillage aux 25 os
# =================================================================================================
# ╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
# ║ Les cinq modules du soldat existent déjà et sont éprouvés séparément :                        ║
# ║   `trench_soldier_rig.gd`     — les 25 os, leurs positions de repos, l'échelle de casque      ║
# ║   `trench_soldier_parts.gd`   — le maillage, EN POSE DE REPOS, rangé par MATÉRIAU             ║
# ║   `trench_soldier_clips.gd`   — les poses                                                     ║
# ║   `trench_soldier_anim.gd`    — l'`Animator`, qui construit un arbre de `Node3D` et l'anime   ║
# ║   `trench_soldier_bounds.gd`  — la boîte serveur, qui NE CHANGE JAMAIS                        ║
# ║                                                                                               ║
# ║ Il manquait le pont : `parts` rend UN maillage fusionné par matériau, sans la moindre notion  ║
# ║ d'os. Ce fichier fait la jonction — il pèse chaque sommet sur les os et laisse le             ║
# ║ `Skeleton3D` déformer.                                                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ── 🩸 POURQUOI PAS UN DÉCOUPAGE RIGIDE : LE CHIFFRE A TRANCHÉ ─────────────────────────────────
# La première version accrochait chaque TRIANGLE, entier, à un seul os — pas de poids, pas de
# `Skeleton3D`, une `MeshInstance3D` par couple (os, matériau) et l'arbre de scène qui compose.
# L'argument était honnête : cet ennemi est vu de l'autre côté de la tranchée, une centaine de
# pixels de haut, et le module `parts` a déjà tranché la même question dans l'autre sens (« PAS DE
# POUCE, PAS DE DOIGTS : on ne maille pas ce qui tient sous le seuil »).
#
# ⛔ L'argument était honnête et il était FAUX, parce qu'il était invérifié. La sonde a mesuré la
# couture : **115,3 mm au genou en course, soit 9,0 pixels à 12 m**. Pas « sous le seuil » — neuf
# fois au-dessus. Le cuissard et le tibia se séparaient franchement à chaque foulée.
# ⚠️ La leçon n'est pas « le découpage rigide est mauvais » : c'est que **le seuil de visibilité ne
# se raisonne pas, il se mesure**. Le même raisonnement (« c'est trop petit pour se voir ») était
# juste pour le pouce et faux pour le genou, et rien dans le raisonnement ne permettait de le
# savoir. Seule la mesure les sépare.
#
# On pèse donc les sommets. Le coût est un `Skeleton3D` de plus, et le gain ne s'arrête pas au
# genou : une surface par MATÉRIAU au lieu d'une par (os, matériau), soit **8 au lieu de 47**.
#
# ── ⭐ LA PONDÉRATION : DEUX OS AU PLUS, ET SEULEMENT À TRAVERS UNE ARTICULATION ────────────────
# Chaque sommet cherche les deux segments de peau les plus proches. Il ne mélange QUE si les deux
# os sont voisins dans la hiérarchie (parent/enfant) — c'est-à-dire s'il y a une VRAIE articulation
# entre eux. Sinon il reste rigide sur le plus proche.
#
# ⚠️ Sans cette condition d'adjacence, une pondération par simple distance fait baver : au niveau
# de l'entrejambe les deux cuisses se touchent, et la cuisse droite se mettrait à suivre la jambe
# gauche. Le résultat est un maillage qui « respire » quand l'autre jambe bouge — un défaut
# beaucoup plus laid que la déchirure qu'on cherchait à supprimer.
#
# ── LE DÉCOUPAGE : PAR RÉGION D'ABORD, PAR SEGMENT ENSUITE ─────────────────────────────────────
# 🩸 Première idée, jetée : « chaque sommet va à l'os dont le segment est le plus proche ». Elle
# donne le bon résultat presque partout — et une absurdité à l'épaule. Le segment de clavicule
# court de x = ±0,038 à x = ±0,172 à hauteur y ≈ 1,41 : il traverse la COQUE DU TORSE. Le haut du
# torse serait donc parti avec le bras, et l'uniforme se serait déformé au trapèze dès l'épaulé.
#
# Le remède ne demande aucune heuristique : `parts` construit déjà le corps par RÉGIONS
# (`add_casque`, `add_torse`, `add_bras`, …). On appelle ces fonctions nous-mêmes, une par une, et
# chaque région ne peut choisir que parmi SES os. Le torse ne voit pas les clavicules, les jambes
# ne voient pas le bassin. C'est la structure du module qui donne l'information, pas une devinette.
#
# ⚠️ Le prix de cette astuce : cette liste d'appels DOUBLE celle de `Parts.build()`. Si quelqu'un
# ajoute une région là-bas sans la déclarer ici, le corps perdrait une pièce **en silence**. D'où
# le contrôle de somme à la construction (`rapport["tris_manquants"]`), qui compare notre total à
# celui de `Parts.tri_count()` : le nombre de triangles est le seul témoin qui ne peut pas mentir.
#
# ── L'ÉCHELLE, LE PIÈGE QUI NE SE VOIT QU'AU RENDU ─────────────────────────────────────────────
# ⛔ `parts` produit sa géométrie NON MISE À L'ÉCHELLE (mètres du modèle brut, casque à 1,8106),
# alors que `Animator` fabrique ses os DÉJÀ multipliés par `ECHELLE_CASQUE` (casque à 1,80 pile, la
# hauteur de la boîte serveur). Accrocher l'un à l'autre sans y penser donne des morceaux DÉCALÉS
# de leur os. On met donc la géométrie à l'échelle nous-mêmes, avec l'échelle que l'`Animator` a
# réellement retenue (`animator.echelle`), jamais avec une constante recopiée.
#
# ── ⛔ CE QUE CE FICHIER NE FAIT PAS ────────────────────────────────────────────────────────────
# Il ne décide RIEN. Il ne touche ni à la boîte serveur, ni à la table angulaire, ni à la cadence.
# La POSE reste la propriété exclusive de l'`Animator` : le `Skeleton3D` n'en est qu'un miroir, et
# `_miroiter()` est le seul endroit qui écrit dedans.

const Rig := preload("res://scripts/game/trench_soldier_rig.gd")
const Parts := preload("res://scripts/game/trench_soldier_parts.gd")
const Anim := preload("res://scripts/game/trench_soldier_anim.gd")
const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const Bnd := preload("res://scripts/game/trench_soldier_bounds.gd")
const Weapons := preload("res://scripts/game/trench_weapons3d.gd")

# Les régions de `parts`, et les os parmi lesquels chacune a le droit de choisir.
# ⚠️ `os` VIDE = « tous les os » : c'est le cas des accessoires, dont les pochettes vivent sur le
# ceinturon et les sangles sur la poitrine. Leur donner une liste restreinte reviendrait à décider
# à leur place où va une bretelle, ce qu'on ne sait pas mieux que la géométrie.
const REGIONS := [
	{"nom": "casque", "os": ["Neck", "Head"]},
	{"nom": "tete", "os": ["Neck", "Head"]},
	{"nom": "torse", "os": ["Hips", "Spine", "Spine1", "Spine2", "Neck"]},
	{"nom": "bras", "os": ["ClavicleR", "UpperArmR", "ForearmR", "HandR",
		"ClavicleL", "UpperArmL", "ForearmL", "HandL"]},
	{"nom": "bassin", "os": ["Hips", "UpLegR", "UpLegL"]},
	{"nom": "jambes", "os": ["UpLegR", "LegR", "FootR", "UpLegL", "LegL", "FootL"]},
	{"nom": "accessoires", "os": []},
]

# Netteté du mélange entre les deux os d'une articulation. `w1 = d2^N / (d1^N + d2^N)`.
#
# ⚠️ VALEUR BALAYÉE, PAS CHOISIE. Le raisonnement disait « N petit étale l'influence, N grand
# redonne une frontière franche : il doit exister un optimum ». Le balayage (N = 1,5 · 2 · 3 · 4 ·
# 6 · 10 · 20, pire écrasement d'arête au genou) rend **53,1 · 52,8 · 56,7 · 59,1 · 59,1 · 60,0 ·
# 75,7 mm** : quasiment PLAT sur une décade, et l'optimum vaut 11 % de mieux que le pire.
# 🩸 Le raisonnement était donc juste et sans intérêt : **la netteté n'est pas le levier**. Ce qui
# gouverne l'affaissement d'une articulation, c'est le nombre d'anneaux de maillage qui la
# traversent — et le budget de `parts` (3 780 triangles pour un corps entier) en donne un seul au
# genou. On retient 2,0 parce que c'est le minimum mesuré, pas parce qu'on l'a déduit.
const NETTETE_MELANGE := 2.0

# Distance de duel retenue pour convertir une longueur en pixels. ⚠️ Ce n'est pas un chiffre rond
# choisi pour faire joli : c'est la largeur de la tranchée telle que la géométrie serveur la pose.
const DISTANCE_DUEL_M := 12.0
const FOV_VERTICAL_DEG := 60.0
const HAUTEUR_ECRAN_PX := 1080.0

var animator                      # Anim.Animator — LA pose, source unique
var squelette: Skeleton3D = null  # le miroir de la pose, côté rendu
var variante := ""
var echelle := 1.0
var tris := 0
var rapport := {}                 # compte-rendu de montage, lisible par une sonde

var _lib: WMat = null
var _index_os := {}               # nom d'os -> index de bone dans le Skeleton3D
var _surfaces := {}               # materiau -> MeshInstance3D
# Le maillage tel qu'il a été pesé, gardé pour la MESURE (jamais pour le rendu) :
# positions déjà à l'échelle du rig, et pour chaque sommet ses deux os et ses deux poids.
var _mes_pos := PackedVector3Array()
var _mes_os := PackedInt32Array()
var _mes_poids := PackedFloat32Array()
var _mes_aretes := PackedInt32Array()
var _sommets_hauts := PackedInt32Array()   # les sommets candidats au SOMMET du corps
var _assise_chair := 0.0                   # seconde assise, exacte, calculee sur le maillage
var _arme: Node3D = null              # l arme montee dans la main droite
var _mats_arme: Array = []            # ses materiaux PROPRES, pour le fondu
var _cache_repos := {}            # nom d'os -> position de repos MONDE, à l'échelle du rig


# =================================================================================================
# CONSTRUCTION
# =================================================================================================
func construire(p_variante := Parts.VARIANTE_DEFAUT, uniform_scale := 1.0) -> void:
	variante = p_variante if Parts.VARIANTES.has(p_variante) else Parts.VARIANTE_DEFAUT
	_lib = WMat.new()

	# ⚠️ L'`Animator` reste dans l'arbre bien qu'il ne porte plus aucun maillage : il possède la
	# pose, l'assise dans la boîte et le journal d'écrêtages. Le détacher créerait un objet vivant
	# sans propriétaire dans la scène.
	animator = Anim.Animator.new(uniform_scale)
	echelle = animator.echelle
	animator.root.visible = false
	add_child(animator.root)

	_batir_squelette()

	var segments := _segments_de_peau()
	var par_materiau := {}        # materiau -> { "md": MeshData, "os": [], "poids": [] }
	var total := 0

	for region in REGIONS:
		var nom: String = region["nom"]
		var permis: Array = region["os"]
		var seaux := _construire_region(nom)
		for cle_mat in seaux:
			var src = seaux[cle_mat]
			total += src.tri_count()
			_peser(src, String(cle_mat), permis, segments, par_materiau)

	# 🩸 LE TÉMOIN QUI NE PEUT PAS MENTIR. Si `Parts.build()` gagne une région que `REGIONS`
	# ignore, le corps perd une pièce sans qu'aucune erreur ne soit levée : le boot resterait à
	# « 0 ERROR » et la capture montrerait un soldat sans casque. On compare donc les totaux.
	var attendu := Parts.tri_count(variante)
	rapport = {
		"variante": variante,
		"echelle": echelle,
		"tris": total,
		"tris_attendus": attendu,
		"tris_manquants": attendu - total,
		"surfaces": 0,
		"sommets": 0,
		"melanges": 0,
	}
	if total != attendu:
		push_warning("[trench_soldier3d] %d triangles peses pour %d attendus — une region de "
			% [total, attendu]
			+ "`trench_soldier_parts` n'est pas declaree dans REGIONS.")

	_monter(par_materiau)
	tris = total


# ── LE SQUELETTE, MIROIR DE L'ARBRE DE L'`Animator` ────────────────────────────────────────────
# Mêmes noms, mêmes parents, mêmes positions de repos. ⚠️ Les repos sont des TRANSLATIONS PURES :
# la base de repos de chaque os est l'identité, ce qui est ce que l'`Animator` suppose lui aussi
# (`_ecrire_pose` n'écrit qu'un quaternion sur un `Node3D` par ailleurs non tourné). Introduire ici
# une base de repos tournée créerait deux conventions et ferait pivoter le corps sans que la pose
# ait changé.
func _batir_squelette() -> void:
	squelette = Skeleton3D.new()
	squelette.name = "squelette"
	add_child(squelette)
	for i in Rig.BONES.size():
		var spec: Dictionary = Rig.BONES[i]
		var n: String = spec["name"]
		squelette.add_bone(n)
		_index_os[n] = i
	for i in Rig.BONES.size():
		var spec: Dictionary = Rig.BONES[i]
		var parent: String = spec["parent"]
		if parent != "":
			squelette.set_bone_parent(i, int(_index_os[parent]))
		var repos: Vector3 = animator.repos[String(spec["name"])]
		squelette.set_bone_rest(i, Transform3D(Basis.IDENTITY, repos))
		squelette.set_bone_pose_position(i, repos)


# Rejoue UNE région de `parts` dans son propre assemblage, pour récupérer sa géométrie SEULE.
func _construire_region(nom: String) -> Dictionary:
	var spec: Dictionary = Parts.VARIANTES[variante]
	var bulk: float = float(spec["bulk"])
	var asm = Meshgen.Assembly.new("soldat-" + variante + "-" + nom)
	match nom:
		"casque":
			Parts.add_casque(asm)
		"tete":
			Parts.add_tete(asm)
		"torse":
			Parts.add_torse(asm, bulk)
		"bras":
			Parts.add_bras(asm, bulk)
		"bassin":
			Parts.add_bassin(asm, bulk)
		"jambes":
			Parts.add_jambes(asm, bulk)
		"accessoires":
			Parts.add_accessoires(asm, variante, bulk)
		_:
			push_warning("[trench_soldier3d] region inconnue « %s »." % nom)
	return asm.build()


# ── LES SEGMENTS DE PEAU ───────────────────────────────────────────────────────────────────────
# Un segment par os NON-RACINE : il va de son parent à lui, et c'est le PARENT qui le possède.
# C'est la convention anatomique : la chair entre l'épaule et le coude tourne avec le bras, pas
# avec l'avant-bras. Les feuilles (`HeadTop`, `Fingers*`, `Toe*`) ne possèdent donc rien — elles ne
# sont que des extrémités, et la chair qui les dépasse revient à leur parent, ce qui est juste :
# une pointe de botte n'a pas d'articulation propre.
# ⚠️ Les segments sont en coordonnées MODÈLE (non mises à l'échelle), comme la géométrie de
# `parts` : on compare des distances, elles doivent vivre dans le même espace.
func _segments_de_peau() -> Array:
	var out := []
	for spec in Rig.BONES:
		var parent: String = spec["parent"]
		if parent == "":
			continue
		out.append({
			"os": parent,
			"a": Parts.os_position(parent),
			"b": Parts.os_position(String(spec["name"])),
		})
	return out


# Deux os sont adjacents si l'un est le parent de l'autre — c'est-à-dire s'il y a une articulation
# entre eux, et donc un sens à mélanger.
func _adjacents(a: String, b: String) -> bool:
	for spec in Rig.BONES:
		var n: String = spec["name"]
		var p: String = spec["parent"]
		if (n == a and p == b) or (n == b and p == a):
			return true
	return false


# =================================================================================================
# LA PESÉE
# =================================================================================================
func _peser(src, mat: String, permis: Array, segments: Array, par_materiau: Dictionary) -> void:
	if not par_materiau.has(mat):
		par_materiau[mat] = {"md": Meshgen.MeshData.new(), "os": [], "poids": []}
	var sac: Dictionary = par_materiau[mat]
	var cible = sac["md"]
	var decalage: int = cible.positions.size()

	var pos: PackedVector3Array = src.positions
	var nor: PackedVector3Array = src.normals
	var uv: PackedVector2Array = src.uvs
	var idx: PackedInt32Array = src.indices

	for i in pos.size():
		var p: Vector3 = pos[i]
		var duo := _deux_os(p, permis, segments)
		# ⛔ L'échelle du rig s'applique ICI, et une seule fois. La normale n'est pas touchée : une
		# mise à l'échelle UNIFORME ne la change pas, et la renormaliser ajouterait du bruit.
		cible.add_vertex(p * echelle, nor[i], uv[i] if i < uv.size() else Vector2.ZERO)
		(sac["os"] as Array).append(duo["os"])
		(sac["poids"] as Array).append(duo["poids"])

	for k in idx.size():
		cible.indices.push_back(idx[k] + decalage)


# Les deux os d'un sommet, et leurs poids. Rend toujours quatre entrées (le format que
# `ARRAY_BONES`/`ARRAY_WEIGHTS` attend), les deux dernières à poids nul.
func _deux_os(p: Vector3, permis: Array, segments: Array) -> Dictionary:
	var os1 := ""
	var os2 := ""
	var d1 := INF
	var d2 := INF
	for s in segments:
		var os: String = s["os"]
		if not permis.is_empty() and not permis.has(os):
			continue
		var d := p.distance_to(Geometry3D.get_closest_point_to_segment(p, s["a"], s["b"]))
		if d < d1:
			d2 = d1
			os2 = os1
			d1 = d
			os1 = os
		elif d < d2:
			d2 = d
			os2 = os
	if os1 == "":
		# Aucun segment permis : ne peut arriver que si une région déclare des os inexistants.
		return {"os": [0, 0, 0, 0], "poids": [1.0, 0.0, 0.0, 0.0]}
	var i1: int = _index_os[os1]
	if os2 == "" or not _adjacents(os1, os2):
		return {"os": [i1, 0, 0, 0], "poids": [1.0, 0.0, 0.0, 0.0]}
	# ⚠️ `d1` peut valoir exactement 0 (un sommet posé sur l'axe de l'os) : sans l'epsilon, la
	# puissance donne 0/0. Le repli naturel est « tout sur l'os le plus proche », ce que fait la
	# formule dès que d1 << d2.
	var a: float = pow(maxf(d1, 1e-9), NETTETE_MELANGE)
	var b: float = pow(maxf(d2, 1e-9), NETTETE_MELANGE)
	var w1: float = b / (a + b)
	return {"os": [i1, int(_index_os[os2]), 0, 0], "poids": [w1, 1.0 - w1, 0.0, 0.0]}


# =================================================================================================
# LE MONTAGE — une surface par matériau, pas une par os
# =================================================================================================
func _monter(par_materiau: Dictionary) -> void:
	var n_surf := 0
	var n_som := 0
	var n_mel := 0
	_mes_pos = PackedVector3Array()
	_mes_os = PackedInt32Array()
	_mes_poids = PackedFloat32Array()
	_mes_aretes = PackedInt32Array()

	for mat in par_materiau:
		var sac: Dictionary = par_materiau[mat]
		var md = sac["md"]
		if md.is_empty():
			continue
		var os_list: Array = sac["os"]
		var poids_list: Array = sac["poids"]

		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var base: int = _mes_pos.size()
		for i in os_list.size():
			var q: Array = os_list[i]
			var w: Array = poids_list[i]
			for k in 4:
				bones.push_back(int(q[k]))
				weights.push_back(float(w[k]))
			# La copie de mesure : positions et pesée, hors de tout `ArrayMesh`.
			_mes_pos.push_back(md.positions[i])
			_mes_os.push_back(int(q[0]))
			_mes_os.push_back(int(q[1]))
			_mes_poids.push_back(float(w[0]))
			_mes_poids.push_back(float(w[1]))
			if float(w[1]) > 0.001:
				n_mel += 1
		var k := 0
		while k < md.indices.size():
			# Les trois arêtes du triangle, en indices GLOBAUX de la copie de mesure.
			for e in [[0, 1], [1, 2], [2, 0]]:
				_mes_aretes.push_back(base + md.indices[k + e[0]])
				_mes_aretes.push_back(base + md.indices[k + e[1]])
			k += 3

		var arrays: Array = md.to_surface_arrays()
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mi := MeshInstance3D.new()
		mi.mesh = am
		# ⛔ DUPLIQUÉ, ET CE N'EST PAS DE LA PRUDENCE DÉCORATIVE. `WMat.get_material()` rend une
		# instance MISE EN CACHE, partagée : c'est le même objet `StandardMaterial3D` que le
		# viewmodel emploie pour l'arme du joueur. Le soldat, lui, doit pouvoir s'effacer en fondu
		# et blanchir quand il encaisse — deux écritures dans `albedo_color` et `emission`. Sans
		# cette duplication, **l'arme du joueur se serait effacée avec l'ennemi**, et le défaut
		# n'aurait eu aucun rapport visible avec sa cause.
		mi.material_override = (_lib.get_material(String(mat)) as StandardMaterial3D).duplicate()
		mi.name = "soldat-" + String(mat)
		# ⚠️ À L'INVERSE DU VIEWMODEL, le soldat PROJETTE une ombre : il est dans le monde, pas
		# collé à l'objectif. Un ennemi sans ombre flotte au-dessus de la boue — c'est le même
		# défaut de « sticker collé » que le §8.152.10 décrit pour l'arme, dans l'autre sens.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		squelette.add_child(mi)
		mi.skeleton = mi.get_path_to(squelette)
		mi.skin = squelette.create_skin_from_rest_transforms()
		_surfaces[String(mat)] = mi
		n_surf += 1
		n_som += md.positions.size()

	# Les candidats au sommet : tout ce qui est a moins de 20 cm de l apex au repos. Le casque
	# peut basculer, mais pas de 20 cm — et 4 131 sommets par image seraient hors de prix.
	var apex := -INF
	for p in _mes_pos:
		apex = maxf(apex, (p as Vector3).y)
	for i in _mes_pos.size():
		if (_mes_pos[i] as Vector3).y > apex - 0.20:
			_sommets_hauts.push_back(i)

	rapport["surfaces"] = n_surf
	rapport["sommets"] = n_som
	rapport["melanges"] = n_mel


# =================================================================================================
# LE MIROIR DE POSE — le seul endroit qui écrit dans le `Skeleton3D`
# =================================================================================================
# ⛔ L'`Animator` reste la source unique. Si un jour une correction de pose s'écrivait ICI, il y
# aurait deux vérités : celle que les sondes du lot 3D-G mesurent (l'arbre de `Node3D`) et celle
# que le joueur voit (le squelette). C'est exactement le défaut que le §8.152.10 a payé sur les
# sondes qui lisaient un champ privé de la vue.
func _miroiter() -> void:
	if squelette == null or animator == null:
		return
	for spec in Rig.BONES:
		var n: String = spec["name"]
		var nd: Node3D = animator.bones[n]
		var i: int = _index_os[n]
		squelette.set_bone_pose_position(i, nd.position)
		squelette.set_bone_pose_rotation(i, nd.quaternion)
	# L'assise dans la boîte est portée par la RACINE de l'animateur, pas par un os : sans cette
	# ligne, le soldat accroupi dépasserait le plafond serveur de 33 cm au rendu, alors que toutes
	# les mesures faites sur l'arbre diraient qu'il est en règle.
	squelette.position = animator.root.position


# =================================================================================================
# LA MESURE — ce que le GPU va vraiment dessiner, calculé au sol
# =================================================================================================
# Les positions des sommets APRÈS pesée, dans le monde. C'est la seule façon honnête de contrôler
# la silhouette : mesurer les OS laisserait passer 6 cm de chair, et lire l'`ArrayMesh` donnerait
# la pose de repos, pas celle qui est rendue.
#
# ⚠️ Les transformations monde sont composées À LA MAIN. Godot met les transformations globales à
# jour PARESSEUSEMENT : les lire juste après avoir écrit une pose donne celles de l'image
# précédente — le §8.152.9 a payé ce piège en croyant avoir corrigé un défaut passé de 1 344 à 782
# violations, c'est-à-dire encore faux.
func sommets_monde(pas := 1) -> PackedVector3Array:
	var out := PackedVector3Array()
	if animator == null:
		return out
	var monde := _monde()
	var seat := Vector3(0.0, _assise_chair, 0.0)
	var i := 0
	while i < _mes_pos.size():
		out.push_back(_skinner(i, monde) + seat)
		i += pas
	return out


# La position d'UN sommet après pesée, HORS seconde assise. ⚠️ L'assise en est exclue à dessein :
# `_asseoir_la_chair()` s'en sert pour CALCULER cette assise, et l'y inclure ferait boucler la
# correction sur elle-même — elle rétrécirait à chaque image jusqu'à disparaître.
func _skinner(i: int, monde: Dictionary) -> Vector3:
	var p: Vector3 = _mes_pos[i]
	var w0: float = _mes_poids[i * 2]
	var n0: String = _nom_os(_mes_os[i * 2])
	var v: Vector3 = ((monde[n0] as Transform3D) * (p - _repos_monde_de(n0))) * w0
	var w1: float = _mes_poids[i * 2 + 1]
	if w1 > 0.0:
		var n1: String = _nom_os(_mes_os[i * 2 + 1])
		v += ((monde[n1] as Transform3D) * (p - _repos_monde_de(n1))) * w1
	return v


# L'allongement d'arête : de combien la surface s'étire ou se comprime par rapport au repos.
# ⛔ C'est le contrôle qui remplace la mesure de couture du découpage rigide. Une surface pesée ne
# peut plus se DÉCHIRER (chaque sommet n'a qu'une position) — elle peut seulement s'étirer, et
# c'est cette grandeur-là qu'il faut borner.
func allongement_aretes(pas := 1) -> Dictionary:
	var courant := sommets_monde(1)
	var pire_abs := 0.0
	var pire_rel := 0.0
	var pire_ou := ""
	var n_gros := 0
	var n := 0
	var k := 0
	while k < _mes_aretes.size():
		var a: int = _mes_aretes[k]
		var b: int = _mes_aretes[k + 1]
		var l0: float = (_mes_pos[a] as Vector3).distance_to(_mes_pos[b])
		var l1: float = (courant[a] as Vector3).distance_to(courant[b])
		var d: float = absf(l1 - l0)
		if d > pire_abs:
			pire_abs = d
			pire_ou = "%s%s / %s%s  (%.1f -> %.1f mm)" % [
				_nom_os(_mes_os[a * 2]), _suffixe_poids(a),
				_nom_os(_mes_os[b * 2]), _suffixe_poids(b), l0 * 1000.0, l1 * 1000.0]
		if l0 > 1e-6:
			var r: float = d / l0
			if r > pire_rel:
				pire_rel = r
			if r > 0.25:
				n_gros += 1
		n += 1
		k += 2 * pas
	return {
		"max_m": pire_abs,
		"max_px": _en_pixels(pire_abs),
		"max_rel": pire_rel,
		"aretes": n,
		"gros": n_gros,
		"ou": pire_ou,
	}


# ── LE DIAGNOSTIC DE PESÉE ─────────────────────────────────────────────────────────────────────
# Deux grandeurs, et il en faut deux :
#   `bavure_m`      — la distance MAXIMALE entre un sommet et un os sur lequel il pèse, au repos.
#                     Une pondération qui bave (la cuisse droite qui suit la jambe gauche) la fait
#                     bondir ; un maillage correct la garde de l'ordre du rayon d'un membre.
#   `articulations` — le nombre de sommets mélangés, par couple d'os. ⚠️ Sans ce second membre, une
#                     pesée retombée sur UN SEUL os par sommet aurait une bavure PARFAITE (zéro
#                     mélange, zéro bavure) : le contrôle vanterait alors l'absence de ce qu'il est
#                     censé vérifier. Un contrôle qu'un échec satisfait est pire que pas de contrôle.
func diagnostic_pesee() -> Dictionary:
	var segments := _segments_de_peau()
	var par_os := {}
	for s in segments:
		var o: String = s["os"]
		if not par_os.has(o):
			par_os[o] = []
		(par_os[o] as Array).append(s)

	var bavure := 0.0
	var ou := ""
	var arts := {}
	var non_adjacentes := 0
	var exemple := ""
	for i in _mes_pos.size():
		# ⚠️ On revient en coordonnées MODÈLE (division par l'échelle) : les segments de peau y
		# vivent, et comparer deux espaces différents donnerait une bavure fantôme de 0,6 %.
		var p: Vector3 = _mes_pos[i] / echelle
		# La bavure ne se mesure que sur l'os DOMINANT (poids ≥ 0,5 par construction).
		# 🩸 Première version : elle la mesurait sur tout os de poids > 0,001, et l'apex du casque
		# — pesé à **0,18 %** sur `Neck` parce qu'il dépasse de 11 mm le bout du segment `Head` —
		# la faisait bondir à 259 mm. Un levier de 0,5 mm présenté comme une bavure d'un quart de
		# mètre. ⚠️ Un poids minuscule sur un os lointain n'est pas une bavure : c'est la queue
		# normale de n'importe quelle pondération continue.
		var n0: String = _nom_os(_mes_os[i * 2])
		var d := INF
		for s in par_os.get(n0, []):
			d = minf(d, p.distance_to(
				Geometry3D.get_closest_point_to_segment(p, s["a"], s["b"])))
		if d > bavure:
			bavure = d
			ou = "%s a %.0f mm de %s" % [str(p.snapped(Vector3.ONE * 0.001)), d * 1000.0, n0]
		if _mes_poids[i * 2 + 1] > 0.0:
			var b := _nom_os(_mes_os[i * 2 + 1])
			var cle: String = (n0 + "|" + b) if n0 < b else (b + "|" + n0)
			arts[cle] = int(arts.get(cle, 0)) + 1
			# ⛔ LE FAIT BINAIRE, SANS SEUIL : deux os ne se partagent un sommet que s'il y a une
			# articulation entre eux. C'est la règle d'adjacence, et elle se vérifie sans avoir à
			# choisir de tolérance — donc sans qu'on puisse la desserrer sans s'en rendre compte.
			if not _adjacents(n0, b):
				non_adjacentes += 1
				if exemple == "":
					exemple = cle
	return {
		"bavure_dominant_m": bavure,
		"ou": ou,
		"articulations": arts,
		"paires_non_adjacentes": non_adjacentes,
		"exemple": exemple,
	}


func _nom_os(i: int) -> String:
	return String(Rig.BONES[i]["name"])


func _suffixe_poids(i: int) -> String:
	var w1: float = _mes_poids[i * 2 + 1]
	if w1 <= 0.001:
		return "[rigide]"
	return "[+%s %.2f]" % [_nom_os(_mes_os[i * 2 + 1]), w1]


# Taille apparente, en pixels, d'une longueur transversale vue à distance de duel.
func _en_pixels(metres: float) -> float:
	var hauteur_visible := 2.0 * DISTANCE_DUEL_M * tan(deg_to_rad(FOV_VERTICAL_DEG) * 0.5)
	return metres / hauteur_visible * HAUTEUR_ECRAN_PX


func _repos_monde_de(n: String) -> Vector3:
	# ⚠️ Mise en cache OBLIGATOIRE, pas cosmétique : `resolved_bones()` reconstruit et résout la
	# table entière à chaque appel. Sans le cache, une seule mesure de silhouette la rebâtissait
	# 25 fois par pose, soit 3 000 fois sur un balayage de sonde.
	if _cache_repos.is_empty():
		for os in Rig.resolved_bones(echelle):
			_cache_repos[String(os["name"])] = os["pos"]
	return _cache_repos.get(n, Vector3.ZERO)


# Les transformations monde de tous les os, composées depuis la racine du soldat.
func _monde() -> Dictionary:
	var out := {}
	# 🩸 LA RACINE N'EST PAS L'IDENTITÉ, et la première version de cette fonction le supposait.
	# `_asseoir_dans_la_boite()` écrit `root.position.y` — c'est LA correction qui enfonce le
	# soldat accroupi sous le parapet, le défaut le plus grave que le lot 3D-G ait trouvé. Repartir
	# de `Transform3D.IDENTITY` la jette purement et simplement : la mesure a alors conclu à un
	# dépassement de plafond de **335 mm accroupi**, c'est-à-dire à un ennemi visible que la règle
	# déclare couvert. Un défaut majuscule, et entièrement imaginaire — il était dans la MESURE.
	# ⚠️ Une chaîne de transformations qui « oublie » sa racine ne se trompe pas un peu : elle se
	# trompe exactement de la correction que la racine portait, et c'est toujours la plus
	# intéressante, sinon personne n'aurait pris la peine de l'y mettre.
	var racine: Transform3D = animator.root.transform
	for spec in Rig.BONES:
		var n: String = spec["name"]
		var nd: Node3D = animator.bones[n]
		var parent: String = spec["parent"]
		var base: Transform3D = out[parent] if parent != "" and out.has(parent) else racine
		out[n] = base * nd.transform
	return out


# Les os réellement chargés de chair, et leur poids cumulé. Sert au contrôle « aucune feuille ne
# porte » — que le format `ARRAY_BONES` rendrait sinon illisible.
func charge_par_os() -> Dictionary:
	var out := {}
	var i := 0
	while i < _mes_pos.size():
		for k in 2:
			var w: float = _mes_poids[i * 2 + k]
			if w <= 0.001:
				continue
			var n: String = String(Rig.BONES[_mes_os[i * 2 + k]]["name"])
			out[n] = float(out.get(n, 0.0)) + w
		i += 1
	return out


# =================================================================================================
# LA FAÇADE D'ANIMATION — tout passe par l'`Animator`, rien n'est recalculé ici
# =================================================================================================
func update(dt: float, etat: Dictionary) -> void:
	if animator != null:
		animator.update(dt, etat)
		_asseoir_la_chair(bool(etat.get("accroupi", false)))
		_miroiter()


# ── ⭐ LA SECONDE ASSISE : celle que seul l'assembleur peut faire ───────────────────────────────
# 🩸 `_asseoir_dans_la_boite()` de l'`Animator` enfonce le soldat accroupi sous le parapet — la
# correction la plus importante du lot 3D-G. Mais il n'a pas le maillage : il ESTIME le sommet rendu
# à « le plus haut des os + 10,6 mm », l'écart mesuré au repos entre `HeadTop` et l'apex du casque.
# ⚠️ Cette estimation n'est juste QU'AU REPOS. Dès que la nuque s'incline, l'apex n'est plus à la
# verticale de `HeadTop` et l'écart réel grandit : mesuré, **+9 à +15 mm au-dessus du plafond
# accroupi**. Neuf millimètres, c'est peu — sauf que `SILHOUETTE_TOP_DOWN` veut dire « accroupi,
# JAMAIS exposé » et qu'un backend garde cet invariant par un test de sabotage. Un casque qui
# dépasse, c'est une cible que le joueur voit et que le serveur déclare couverte.
#
# ⛔ On ne corrige pas l'estimation de l'`Animator` : on ajoute une seconde assise, EXACTE, là où
# le maillage est connu. Deux nœuds, deux écritures, aucune ambiguïté sur qui écrit quoi — au
# contraire d'un correctif qui irait retoucher `root.position.y` par-dessus son propriétaire.
#
# ⚠️ Ne balaie que les sommets HAUTS (précalculés) : passer les 4 131 sommets à chaque image pour
# n'en garder que le maximum coûterait plus cher que tout le reste de l'animation.
func _asseoir_la_chair(accroupi: bool) -> void:
	if _sommets_hauts.is_empty():
		return
	var plafond: float = Bnd.HAUT_ACCROUPI if accroupi else Bnd.HAUT_DEBOUT
	var monde := _monde()
	var haut := -INF
	for i in _sommets_hauts:
		haut = maxf(haut, _skinner(i, monde).y)
	# ⚠️ Ne DESCEND que, jamais ne monte : une pose déjà basse reste où elle est. Une correction
	# bidirectionnelle « recalerait » vers le haut des poses honnêtes — même règle que l'`Animator`.
	_assise_chair = -maxf(0.0, haut - plafond)
	position.y = _assise_chair


func set_clip(nom: String) -> void:
	if animator != null:
		animator.set_clip(nom)


func tirer(force := 1.0) -> void:
	if animator != null:
		animator.tirer(force)


func encaisser(region: String, cote := 0.0, force := 1.0) -> void:
	if animator != null:
		animator.encaisser(region, cote, force)


func recharger(duree_s: float) -> void:
	if animator != null:
		animator.recharger(duree_s)


func tourner(sens: float) -> void:
	if animator != null:
		animator.tourner(sens)


# =================================================================================================
# L'ARME DANS SES MAINS
# =================================================================================================
# ⭐ AUCUNE COORDONNÉE N'EST INVENTÉE ICI, et c'est tout l'intérêt. Le rig posait déjà l'os `HandR`
# sur `GRIP_R` — littéralement `{"name": "HandR", "derived": "GRIP_R"}` — et `GRIP_R` est lui-même
# la projection de la poignée sur la LIGNE DE VISÉE (`BORE_ORIGIN` + t·`BORE_DIR`). De son côté,
# chaque arme de `trench_weapons3d` expose son propre nœud `gripR`. Poser l'arme, c'est donc faire
# coïncider deux ancres qui existent déjà :
#   • le `gripR` de l'ARME sur l'origine de l'os `HandR` ;
#   • le +Z de l'ARME (son axe de canon) sur `BORE_DIR`.
# ⚠️ Le pavé du rig l'annonçait : « c'est par ces deux ancres que le lot 3D-F posera l'arme —
# JAMAIS par des coordonnées recopiées ». Une pose réglée à l'œil aurait tenu sur une arme et
# glissé sur les trois autres, et le désaccord se serait vu en premier sur la ligne de tir.
#
# ⛔ `BoneAttachment3D`, pas l'arbre de l'`Animator`. Depuis la pesée, c'est le `Skeleton3D` qui
# rend ; l'arbre de `Node3D` est invisible. Une arme accrochée là-bas n'apparaîtrait tout
# simplement pas — sans erreur, sans avertissement, sans rien.
func monter_arme(weapon_id: String) -> bool:
	if squelette == null or _lib == null:
		return false
	if _arme != null:
		_arme.queue_free()
		_arme = null
	var modele: Dictionary = Weapons.build(weapon_id)
	var noeuds: Dictionary = modele["nodes"]
	if not noeuds.has("gripR"):
		push_warning("[trench_soldier3d] l'arme « %s » n'a pas de gripR." % weapon_id)
		return false
	var poignee: Vector3 = (noeuds["gripR"] as Dictionary)["pos"]

	# La base qui envoie +Z sur la ligne de visée. ⚠️ `Basis(x, y, z)` prend les COLONNES : c'est
	# bien `B * Vector3.BACK` qui vaut `BORE_DIR`, et pas l'inverse.
	var vz: Vector3 = Rig.BORE_DIR.normalized()
	var vx: Vector3 = Vector3.UP.cross(vz).normalized()
	var b := Basis(vx, vz.cross(vx), vz)

	# ╔═ 🩸 UNE MESURE QUI A CHANGÉ LA DÉCISION, PUIS UN RAISONNEMENT QUI L'A CHANGÉE EN RETOUR ═════╗
	# ║ Poser le `gripR` de l'arme sur l'os `HandR` donne : poignée à 0,0000 mm — et le MUSEAU à     ║
	# ║ **82,9 mm de la ligne de visée du rig**. La cause est dans le rig : `GRIP_R_DROP = 0,095`    ║
	# ║ suppose la poignée 95 mm sous l'axe du canon, alors que les armes réelles annoncent 33 à     ║
	# ║ 62 mm. Les deux ancres ne peuvent pas être satisfaites ensemble ; il faut choisir laquelle   ║
	# ║ porte l'écart.                                                                              ║
	# ║                                                                                             ║
	# ║ ⚠️ J'ai d'abord choisi le canon, au motif que « l'ennemi doit tirer là où il regarde ».      ║
	# ║ VÉRIFIÉ, et c'était faux : **rien ne lit la ligne de visée du soldat.** Le tir adverse part  ║
	# ║ de `_muzzle_origin()`, qui rend `(position_x, EYE_UP, far_soldier_z)` — l'ŒIL, jamais le     ║
	# ║ fusil. Et les DEUX poses donnent exactement la même DIRECTION de canon : elles ne diffèrent  ║
	# ║ que par une translation parallèle.                                                          ║
	# ║ ⛔ L'écart ne pouvait donc jamais devenir un mensonge sur la ligne de tir. Il ne reste qu'un ║
	# ║ arbitrage d'image — et là, « le fusil flotte 8 cm au-dessus du poing » se voit, tandis que   ║
	# ║ « le canon est 8 cm plus bas qu'une ligne interne que personne ne dessine » ne se voit pas.  ║
	# ║ La main gagne. ❓ Re-dériver `GRIP_R_DROP` depuis les armes réelles réconcilierait les deux, ║
	# ║ mais cela déplace l'os `HandR` et donc toutes les poses de bras : c'est un arbitrage ouvert. ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
	var att := BoneAttachment3D.new()
	att.name = "arme"
	squelette.add_child(att)
	att.bone_name = "HandR"
	_arme = Node3D.new()
	_arme.name = "arme-" + weapon_id
	# L'échelle du rig s'applique à l'arme comme au corps : elle vit dans le même modèle.
	_arme.transform = Transform3D(b.scaled(Vector3.ONE * echelle), -(b * poignee) * echelle)
	att.add_child(_arme)

	var seaux: Dictionary = (modele["body"]).build()
	for cle in seaux:
		var mi := MeshInstance3D.new()
		mi.mesh = Meshgen.to_array_mesh(seaux[cle])
		# Dupliqué pour la même raison que le corps : l'ennemi s'efface en fondu, et le cache de
		# `WMat` est partagé avec le viewmodel du joueur.
		mi.material_override = (_lib.get_material(String(cle)) as StandardMaterial3D).duplicate()
		mi.name = "arme-" + String(cle)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_arme.add_child(mi)
		_mats_arme.append(mi.material_override)
	rapport["arme"] = weapon_id
	rapport["arme_surfaces"] = seaux.size()
	return true


# ⭐ LA VÉRIFICATION DE POSE DE L'ARME — deux distances, et elles ne mesurent pas la même chose.
#
#   `poignee_m` — l'écart entre le `gripR` de l'arme et l'origine de l'os `HandR`. Vaut zéro par
#                 construction… tant que la construction est juste. Une échelle appliquée deux fois
#                 ou un signe de translation inversé le fait bondir.
#   `canon_m`   — la distance du MUSEAU à la ligne de visée du rig. ⚠️ C'est le contrôle qui compte,
#                 et il est INDÉPENDANT du premier : on peut poser la poignée exactement au bon
#                 endroit et laisser l'arme pointer de travers, auquel cas le premier reste à zéro
#                 pendant que l'ennemi tire à côté de ce qu'il regarde. Une seule des deux mesures
#                 laisserait passer l'autre défaut.
#
# ⚠️ Le museau est à ~40 cm de la poignée : une erreur d'orientation d'un degré s'y lit à 7 mm. La
# mesure est donc SENSIBLE là où l'œil ne verrait rien à 12 m.
func verif_arme() -> Dictionary:
	if _arme == null:
		return {}
	var modele: Dictionary = Weapons.build(String(rapport.get("arme", "")))
	var noeuds: Dictionary = modele["nodes"]
	var t: Transform3D = _arme.transform
	var origine_main: Vector3 = _repos_monde_de("HandR")

	var g: Vector3 = (noeuds["gripR"] as Dictionary)["pos"]
	var poignee: float = (t * g).length()

	# L'ANGLE du canon contre la direction de visée. ⛔ C'est le membre DUR : une direction fausse
	# fait pointer le fusil ailleurs que le regard, et aucune translation ne peut la rattraper.
	var axe: Vector3 = (t.basis * Vector3(0.0, 0.0, 1.0)).normalized()
	var out := {
		"poignee_m": poignee,
		"axe_deg": rad_to_deg(axe.angle_to(Rig.BORE_DIR.normalized())),
		"canon_m": -1.0,
	}
	if noeuds.has("muzzle"):
		var brut = noeuds["muzzle"]
		var m: Vector3 = (brut["pos"] if brut is Dictionary else brut)
		var monde: Vector3 = origine_main + t * m
		# Le décalage PARALLÈLE à la ligne de visée du rig — publié, pas jugé : il vaut l'écart
		# entre la garde au canon supposée par le rig et celle de l'arme réelle.
		var a: Vector3 = Rig.BORE_ORIGIN * echelle
		var d: Vector3 = Rig.BORE_DIR.normalized()
		out["canon_m"] = ((monde - a) - d * (monde - a).dot(d)).length()
	return out


# L'enveloppe MONDE de l'arme montée, pour que l'hôte puisse mesurer ce qu'elle ajoute à la
# silhouette au lieu de le supposer. Vide tant qu'aucune arme n'est montée.
func enveloppe_arme() -> AABB:
	if _arme == null:
		return AABB()
	var out := AABB()
	var premier := true
	for enfant in _arme.get_children():
		var mi := enfant as MeshInstance3D
		if mi == null:
			continue
		var t: Transform3D = _arme.global_transform
		for p in (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var w: Vector3 = t * (p as Vector3)
			if premier:
				out = AABB(w, Vector3.ZERO)
				premier = false
			else:
				out = out.expand(w)
	return out


# Les matériaux du soldat — les SIENS, dupliqués à la construction. L'hôte peut y écrire (fondu de
# rédaction, éclair de touche) sans repeindre l'arme du joueur.
func materiaux() -> Array:
	var out := []
	for cle in _surfaces:
		out.append((_surfaces[cle] as MeshInstance3D).material_override)
	# ⚠️ L ARME EN FAIT PARTIE. L oublier donnerait le pire des fondus : le corps s efface et le
	# fusil reste, opaque, suspendu en l air a la place ou l homme etait.
	out.append_array(_mats_arme)
	return out


# Le matériau d'UN habillage, pour les traitements qui ne concernent qu'une pièce — la teinte de
# faction, qui vit sur la TOILE D'UNIFORME et nulle part ailleurs.
func materiau(cle: String) -> StandardMaterial3D:
	if not _surfaces.has(cle):
		return null
	return (_surfaces[cle] as MeshInstance3D).material_override as StandardMaterial3D


# Les points de silhouette, tels que `trench_soldier_bounds.violations()` les attend.
func points_monde() -> Array:
	return [] if animator == null else animator.points_monde()


# Le journal des écrêtages de bornes de l'image courante. Vide = aucune borne n'a mordu.
func ecretages() -> Dictionary:
	return {} if animator == null else animator.ecretages
