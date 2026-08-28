extends RefCounted
# =================================================================================================
# LA TRANCHÉE — VUE 3D (§8.152 LOT 3D-G) — LE MAILLAGE PROCÉDURAL DU SOLDAT ADVERSE.
#
# Pendant de `trench_wparts.gd` pour le CORPS : une fonction par pièce, chaque pièce bâtie
# uniquement avec les primitives de `trench_meshgen.gd`, chaque pièce POSÉE PAR RAPPORT À UN OS de
# `trench_soldier_rig.gd`. Aucun fichier de modèle, aucune texture, aucun `.glb` : la table d'os +
# ce fichier SONT le personnage.
#
# ⛔ CE FICHIER NE PRODUIT QUE DE LA GÉOMÉTRIE VISUELLE. Aucune `Area3D`, aucun `CollisionShape3D`,
# aucun corps physique — pas même « pour plus tard ». La hitbox du soldat est la BOÎTE DU SERVEUR
# (`trench_geometry.gd`, voyagée dans `trench_angles.json`) et rien d'autre. Le jour où une forme
# de collision apparaît ici, elle devient une seconde source de vérité qui divergera en silence :
# c'est exactement le patron qui a coûté une session au §8.148.
#
# ╔═ LES QUATRE CONTRAINTES DURES, ET COMMENT CHACUNE EST TENUE ══════════════════════════════════╗
# ║ 1. SOMMET DU CASQUE À 1,80 m PILE une fois `Rig.ECHELLE_CASQUE` appliquée.                     ║
# ║    `ECHELLE_CASQUE = HAUTEUR_BOITE / SOMMET_CASQUE_RENDU`. Le SEUL sommet non mis à l'échelle  ║
# ║    qui retombe sur 1,80 après multiplication est donc `SOMMET_CASQUE_RENDU` lui-même — tout    ║
# ║    autre sommet exigerait une AUTRE échelle. La demi-hauteur de coque n'est donc pas choisie :  ║
# ║    elle est DÉRIVÉE (`_casque_demi_hauteur()`), et le profil est écrit en FRACTIONS de cette    ║
# ║    demi-hauteur, dont la dernière vaut 1.0 exactement. Cf. `CASQUE_PROFIL`.                     ║
# ║ 2. DEMI-LARGEUR ≤ 0,44 m, épaules et coudes compris. Mesurée : ≈ 0,238 m au pire (les épaulières ║
# ║    du `breacher`), soit 54 % de la borne. Le contrôle est fait sur l'AABB RÉELLE du maillage    ║
# ║    par `self_check()`, pas sur une addition de cotes en commentaire.                            ║
# ║ 3. BUDGET 6 000 TRIANGLES, casque compris. Mesuré 3 780 / 3 744 / 3 840 selon la variante.      ║
# ║    Le détail par pièce est en fin de fichier ; `tri_count()` le remesure à l'exécution.         ║
# ║ 4. UNE SEULE HAUTEUR POUR LES TROIS VARIANTES. Voir le pavé « LE PIÈGE DU BREACHER » plus bas.  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️ LE PIÈGE DU BREACHER — POURQUOI `scale` EST INTERDIT ICI ═════════════════════════════════╗
# ║ Chez eux (`soldier.js:166`) les variantes portent une ÉCHELLE UNIFORME sur la racine du         ║
# ║ groupe : `vanguard` 1.0, `irregular` 0.985, `breacher` **1.025**. Le breacher culmine donc à     ║
# ║ 1,8106 × 1,025 = **1,8559 m** : 55,9 mm de casque au-dessus d'une boîte serveur qui, elle, ne   ║
# ║ change jamais. Un joueur qui vise ce casque RATE, et rien à l'écran ne le lui dit.              ║
# ║                                                                                                ║
# ║ Une boîte unique ⇒ une hauteur unique. Il n'y a pas de troisième option. Ce fichier ne produit  ║
# ║ donc AUCUNE mise à l'échelle de variante : la différence de silhouette passe intégralement par  ║
# ║ `bulk`, qui ne multiplie **que des rayons LATÉRAUX** (largeur et profondeur), et par les        ║
# ║ ACCESSOIRES. Aucune cote en Y n'est jamais touchée par `bulk` — ni le casque, ni les os, ni un  ║
# ║ profil de loft. `self_check()` mesure les trois hauteurs et les compare entre elles : c'est une ║
# ║ MESURE, pas une promesse de commentaire.                                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ CE QUE « VU À 10 MÈTRES » VEUT DIRE EN TRIANGLES ════════════════════════════════════════════╗
# ║ La cible occupe une plaque de 0,88 m de large à 10 m. La règle de tri appliquée à chaque pièce  ║
# ║ de ce fichier : **un détail plus étroit que ~2 % de la plaque (18 mm) ne se voit pas**, on ne   ║
# ║ le maille pas. C'est ce qui a fait SUPPRIMER le pouce des mains (48 tris × 2, largeur           ║
# ║ apparente 2 % de la plaque), les coutures de gant, la semelle en pièce séparée, et ce qui fait  ║
# ║ que le gilet est un ARC de tour (80 tris, qui épouse le torse) plutôt qu'une plaque extrudée    ║
# ║ (124 tris, qui flotte de 61 mm à ses bords sur un torse ovale — mesuré).                        ║
# ║ ⚠️ Le corollaire est l'inverse d'une économie : les triangles épargnés là sont dépensés sur la  ║
# ║ SILHOUETTE (casque 16 quartiers, torse 16, bassin 14), la seule chose qu'on lit à 10 m.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# REPÈRE — celui du rig, sans transposition : **pieds à y = 0, personnage tourné vers +Z**, et
# ⚠️ **la DROITE du personnage est en X NÉGATIF** (piège A de `trench_soldier_rig.gd`). Les jambes
# sont donc bâties du côté x < 0 puis MIROITÉES ; les bras, JAMAIS (`HandL` traverse à x < 0 :
# miroiter le bras droit mettrait le fusil dans la mauvaise main).
#
# ⚠️ PIÈGES DE LANGAGE respectés ici, tous déjà payés par ce dépôt :
#   • aucun `assert` (un assert échoué FIGE Godot en headless et gèle le harnais) ;
#   • aucune classe interne (elle ne verrait NI les constantes NI les `preload` de ce script) ;
#   • pas de `class_name` : le fichier est chargé par `preload` ;
#   • `%e` n'existe pas au formatage GDScript — uniquement `%s`, `%d`, `%f`, `%.Nf` ;
#   • `:=` interdit sur une valeur Variant (retour de Dictionary, indexation d'Array non typé) ;
#   • `Assembly.build()` VIDE ses seaux : `build()` ci-dessous rend l'`Assembly` NON fusionné, et
#     `tri_count()` / `self_check()` lisent `buckets` sans le vider.
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const Rig := preload("res://scripts/game/trench_soldier_rig.gd")
const Bounds := preload("res://scripts/game/trench_soldier_bounds.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")


# =================================================================================================
# LES MATÉRIAUX — huit clés, toutes LUES dans `trench_wmaterials.gd`, aucune inventée
# =================================================================================================
# ⚠️ Nommées ici en constantes plutôt qu'écrites en littéral au fil des 30 appels à `add()` : une
# clé inconnue ne lève PAS d'erreur, elle rend un magenta criard (`_build`, repli volontairement
# voyant) — donc une faute de frappe ne coûte pas une compilation, elle coûte une capture. Le
# contrôle `self_check()` passe chaque clé à `WMat.has_key()`, ce qui rend la faute impossible à
# livrer plutôt que seulement visible.
#
# ⚠️ IL N'EXISTE AUCUNE CLÉ « PEAU » DANS LE REGISTRE, et on n'en ajoute pas : `trench_wmaterials`
# est le fichier d'un autre lot, on ne l'édite pas depuis ici. On emprunte donc `glove` — cuir
# diélectrique chaud, rugosité 0,86 — qui est la surface la plus proche d'un visage à l'ombre d'une
# visière à 10 m. C'est une DETTE consignée, pas une équivalence : si une capture réclame un teint,
# la correction est une 16ᵉ entrée du registre, pas une retouche ici.
const MAT_COQUE := "polymer"          # coque de casque : composite moulé, diélectrique froid
const MAT_SANGLE := "rubber"          # jugulaire, bandeau de casque, ceinturon, bottes
# ⭐ Le gilet et les pochettes en `polymer_tan` et NON en `polymer` : la TEINTE est le seul indice
# de séparation qui survive à 10 m (c'est la décision qui porte tout `trench_wmaterials`). Le sable
# du gilet DOIT jurer avec le kaki de la toile — les « harmoniser » efface le gilet.
const MAT_GILET := "polymer_tan"
const MAT_TOILE := "sleeve"           # la toile d'uniforme : torse, bras, jambes, col
const MAT_GANT := "glove"             # mains — et, par emprunt assumé, la peau
const MAT_RENFORT := "glove_pad"      # genouillères, coudières, renforts
const MAT_FERRURE := "steel_black"    # boucles : les seules pièces métalliques du personnage
const MAT_OMBRE := "cavity"           # le VIDE sous la visière — cf. `add_tete()`


# =================================================================================================
# LES TROIS VARIANTES — LARGEUR et ACCESSOIRES, JAMAIS HAUTEUR
# =================================================================================================
# `bulk` reprend les trois valeurs de `soldier.js:123-165` (1.0 / 0.94 / 1.06), qui sont chez eux
# le SEUL levier de silhouette légitime (le rig le note déjà : « Un breacher plus MASSIF, pas plus
# GRAND »). Leur `scale` uniforme, lui, est SUPPRIMÉ, pas compensé.
#
# ⚠️ `bulk` ne s'applique PAS uniformément : un torse s'épaissit franchement, un membre beaucoup
# moins (la masse musculaire d'un avant-bras ne varie pas de 6 % entre deux fantassins d'une même
# armée). D'où `_facteur_membre()`, qui n'en prend que la moitié. Sans cette nuance, l'`irregular`
# a des bras de squelette et le `breacher` des bras de dessin animé — c'est ce qui se voit à 10 m,
# bien avant le tour de poitrine.
const VARIANTES := {
	"vanguard": {
		"bulk": 1.00,
		"accessoires": "plastrons",   # fantassin de ligne : plastrons d'épaule + poche radio
	},
	"irregular": {
		"bulk": 0.94,
		"accessoires": "musette",     # léger : écharpe, musette en bandoulière, pas de plaques
	},
	"breacher": {
		"bulk": 1.06,
		"accessoires": "epaulieres",  # massif : épaulières renforcées + renforts d'avant-bras
	},
}
const VARIANTE_DEFAUT := "vanguard"

# Le plafond de la contrainte n°3. C'est un budget d'AUTEUR, pas une cote du monde : il n'a pas de
# source de vérité ailleurs, et c'est le seul nombre de ce fichier qui a le droit d'être un
# littéral sans être dérivé de quelque chose. `self_check()` le mesure sur la géométrie réelle.
const BUDGET_TRIANGLES := 6000


# =================================================================================================
# COTES DU CASQUE — la seule pièce dont une cote est un CONTRAT, pas un choix
# =================================================================================================
# `CASQUE_CENTRE_DY` = leur `cy = by + 0.100`, « shell centre (just above the brow) »
# (`parts.js:481`), recopié parce que c'est la cote d'où `ECHELLE_CASQUE` est dérivée dans le rig.
const CASQUE_CENTRE_DY := 0.100
# Demi-largeur latérale de la coque (casque de 230 mm de large) et rapport profondeur/largeur
# (casque de 270 mm de long). Ce sont des LARGEURS : `bulk` ne les touche pas, la boîte non plus.
const CASQUE_DEMI_LARGEUR := 0.115
const CASQUE_APLAT := 1.174   # 0,135 / 0,115 — le casque est plus long que large

# ╔═ ⚠️ LE PROFIL EST EN FRACTIONS, ET LA DERNIÈRE VAUT 1.0 ══════════════════════════════════════╗
# ║ [fraction de la demi-hauteur (axiale), fraction de la demi-largeur (radiale)].                  ║
# ║ La demi-hauteur, elle, est DÉRIVÉE à l'exécution :                                              ║
# ║     `_casque_demi_hauteur()` = Rig.SOMMET_CASQUE_RENDU − os("Head").y − CASQUE_CENTRE_DY        ║
# ║                             = 1,8106 − 1,552 − 0,100 = **0,1586 m**                             ║
# ║ Donc le point de fraction 1.0 tombe sur 1,8106 m PILE, et 1,8106 × ECHELLE_CASQUE = 1,80 m PILE.║
# ║                                                                                                ║
# ║ ⛔ ÉCRIRE 1,8106 EN DUR ICI SERAIT LA FAUTE. La cote vit dans le rig, qui la tient de           ║
# ║ `trench_geometry.gd`. Une troisième copie divergerait le jour où l'une des deux bouge — et ce   ║
# ║ jour-là, `ECHELLE_CASQUE` mentirait sans qu'aucune compilation ne bronche.                      ║
# ║                                                                                                ║
# ║ ⚠️ Écart assumé avec la référence : leur coque est cotée `ry = 0.158` puis BRUITÉE              ║
# ║ (`displace(..., fbm3 * 0.0016)`, `parts.js:509`), d'où un sommet RENDU à 1,8106 et non 1,8100.  ║
# ║ On ne porte PAS le bruit (0,6 mm de relief invisible à 10 m pour un maillage entier de sommets  ║
# ║ déplacés) : les 0,6 mm sont donc versés dans la demi-hauteur elle-même. Le sommet rendu est le  ║
# ║ même ; le sommet CALCULÉ l'est aussi, ce qui est mieux — chez eux les deux diffèrent, et c'est  ║
# ║ le calcul qui ne pouvait pas servir de garde.                                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const CASQUE_PROFIL := [
	[-0.350, 0.852],   # retour intérieur du bord — ferme la tranche sans payer un capot
	[-0.366, 0.943],   # tranche basse du bord
	[-0.328, 1.000],   # lèvre extérieure : l'arête qui accroche la ligne spéculaire (règle n°1)
	[-0.189, 1.000],   # jupe, largeur maximale
	[0.000, 0.983],    # niveau du centre de coque (juste au-dessus du sourcil)
	[0.252, 0.922],
	[0.504, 0.809],
	[0.725, 0.635],
	[0.883, 0.417],
	[0.971, 0.200],
	[1.000, 0.000],    # ⛔ LE SOMMET. Fraction 1.0 EXACTEMENT — ne jamais toucher cette ligne.
]
# 16 quartiers : le casque fait ~26 % de la largeur de plaque, c'est lui qui porte la silhouette.
# En dessous de 12, on voit le polygone sur le bord — la seule courbe franche du personnage.
const CASQUE_SEG := 16


# Nombre de quartiers des autres tours. Réglés sur la LARGEUR APPARENTE de la pièce, pas sur son
# importance : le torse (37 cm) en a 16, le bassin (31 cm) 14, un membre (12 cm) 10, une main
# (8 cm) 8. C'est la même règle de tri que le budget de triangles, appliquée pièce par pièce.
const SEG_TORSE := 16
const SEG_BASSIN := 14
const SEG_MEMBRE := 10
const SEG_MAIN := 8
const SEG_PANNEAU := 10   # les arcs de gilet, sur ~114° seulement


# =================================================================================================
# ACCÈS AUX OS — lus, jamais recopiés
# =================================================================================================
# ⚠️ On passe par `Rig.resolved_bones()` et pas par `Rig.BONES` : quatre os sur vingt-cinq n'ont
# AUCUNE position dans la table (`ForearmR/L` sont résolus par le solveur de coude, `HandR/L` par
# projection sur la ligne de visée). Lire `BONES` directement rendrait `Vector3.ZERO` pour les deux
# coudes et les deux mains — c'est-à-dire des bras qui partent de l'épaule et pointent vers les
# pieds du personnage, sans la moindre erreur de compilation.
#
# ⚠️ Échelle 1.0 : ce fichier travaille TOUJOURS dans le modèle NON mis à l'échelle. C'est
# l'appelant qui applique `Rig.ECHELLE_CASQUE` **à la racine, aux os ET au maillage ensemble**
# (cf. le pavé du rig : « Jamais l'un sans l'autre »). Appliquer l'échelle ici mettrait la
# hauteur du casque à la merci d'un second facteur appliqué plus haut.
static var _os_cache: Dictionary = {}


static func os_position(nom: String) -> Vector3:
	if _os_cache.is_empty():
		var bones: Array[Dictionary] = Rig.resolved_bones()
		for b in bones:
			var n: String = b["name"]
			var p: Vector3 = b["pos"]
			_os_cache[n] = p
	if not _os_cache.has(nom):
		push_warning("[trench_soldier_parts] os inconnu : %s" % nom)
		return Vector3.ZERO
	var out: Vector3 = _os_cache[nom]
	return out


# Demi-hauteur de la coque de casque. DÉRIVÉE (cf. le pavé de `CASQUE_PROFIL`), jamais écrite.
static func _casque_demi_hauteur() -> float:
	return Rig.SOMMET_CASQUE_RENDU - os_position("Head").y - CASQUE_CENTRE_DY


# Le sommet du casque NON mis à l'échelle. Vaut `Rig.SOMMET_CASQUE_RENDU` par construction — c'est
# écrit comme une somme et non comme un renvoi pour que `self_check()` compare deux chemins de
# calcul INDÉPENDANTS, exactement comme le rig le fait pour ses deux ancres de prise.
static func sommet_casque() -> float:
	return os_position("Head").y + CASQUE_CENTRE_DY + _casque_demi_hauteur()


# Facteur latéral d'un MEMBRE, dérivé du `bulk` du torse. Cf. le pavé de `VARIANTES`.
static func _facteur_membre(bulk: float) -> float:
	return 1.0 + (bulk - 1.0) * 0.5


# =================================================================================================
# OUTILS DE POSE — trois helpers, et pas un de plus
# =================================================================================================

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `_base_os` — LA BASE ORTHONORMÉE D'UN OS, avec aplatissement de section
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Toutes les primitives de `trench_meshgen` qui tournent (lathe, rod, tube) le font autour de +Z.
# Un membre, lui, va d'un os à l'autre. Cette base envoie le +Z local sur l'axe de l'os.
#
# ⚠️ LE VECTEUR DE RÉFÉRENCE EST +Z, PAS +Y — et ce n'est pas un détail de goût. Les os de membres
# sont quasi VERTICAUX ; prendre +Y comme référence donnerait un produit vectoriel NUL sur une
# cuisse (base dégénérée, membre invisible, aucune erreur affichée). Avec +Z, le cas dégénéré ne
# survient que pour un os parallèle à l'axe de vue — il n'y en a aucun dans la table, et la garde
# reste quand même.
# ✅ Effet de bord recherché : sur un os vertical, X local = X monde (latéral) et Y local = Z monde
# (profondeur). `aplat` = rapport profondeur/largeur est donc directement lisible.
static func _base_os(dir: Vector3, aplat: float, roulis := 0.0) -> Basis:
	var z := dir.normalized()
	var x := Vector3(0.0, 0.0, 1.0).cross(z)
	if x.length_squared() < 1e-8:
		x = Vector3(1.0, 0.0, 0.0)
	x = x.normalized()
	var y := z.cross(x).normalized()
	if absf(roulis) > 1e-9:
		var q := Basis(z, roulis)
		x = q * x
		y = q * y
	# ⚠️ `aplat` porte sur la COLONNE Y seule : le déterminant reste POSITIF, donc aucun
	# retournement de faces. Un `aplat` négatif miroiterait la pièce en silence — d'où le `maxf`.
	return Basis(x, y * maxf(aplat, 1e-3), z)


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `_fuseau` — LE MEMBRE : un tronc de cône à ventre, tendu entre deux os
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Cinq points de profil, quatre segments : bouchon arrière, épaule de la pièce, VENTRE (le muscle),
# épaule avant, bouchon avant. Coût = 8 × `seg` triangles, et rien d'autre du fichier n'est aussi
# rentable : un bras entier tient en 160 triangles.
#
# `cap0`/`cap1` = fraction du rayon au bouchon. 0,62 laisse une tranche franche (la pièce s'emboîte
# dans la suivante et la jonction est cachée) ; 0,0 ferme en pointe (bout de main, orteil).
# ⚠️ `ventre` est le renflement musculaire à 42 % de la longueur, pas à 50 % : un biceps et un
# mollet culminent tous les deux au tiers supérieur. À 1,0 le membre devient un tuyau, et un tuyau
# se lit comme un mannequin de vitrine même à 10 m.
static func _fuseau(a: Vector3, b: Vector3, r0: float, r1: float, opts := {}):
	var seg: int = int(opts.get("seg", SEG_MEMBRE))
	var ventre: float = float(opts.get("ventre", 1.05))
	var aplat: float = float(opts.get("aplat", 1.0))
	var cap0: float = float(opts.get("cap0", 0.62))
	var cap1: float = float(opts.get("cap1", 0.62))
	var deb0: float = float(opts.get("deb0", 0.012))
	var deb1: float = float(opts.get("deb1", 0.012))
	var roulis: float = float(opts.get("roulis", 0.0))
	var axe := b - a
	var lg := axe.length()
	if lg < 1e-6:
		push_warning("[trench_soldier_parts] fuseau de longueur nulle — pièce ignorée")
		return null
	var profil := [
		Vector2(-deb0, maxf(r0 * cap0, 0.0)),
		Vector2(0.0, r0),
		Vector2(lg * 0.42, (r0 + r1) * 0.5 * ventre),
		Vector2(lg, r1),
		Vector2(lg + deb1, maxf(r1 * cap1, 0.0)),
	]
	var g = Meshgen.lathe_z(profil, seg)
	g.apply_transform(Transform3D(_base_os(axe / lg, aplat, roulis), a))
	return g


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `_loft_vertical` — LE TRONC : un tour autour de la VERTICALE, à profil libre
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `profil` : liste de `[y ABSOLU en espace acteur, rayon LATÉRAL en mètres]`. Écrire le Y en absolu
# et non en relatif est délibéré : chaque cote se relit alors directement contre la table d'os
# (« la taille est à 1,150, l'os `Spine` est à 1,090 »), et un profil ne peut pas dériver parce que
# quelqu'un a bougé son origine.
#
# `phi_start` / `phi_len` : un ARC au lieu d'un tour complet. C'est ce qui fait les panneaux de
# gilet — un arc de 114° qui ÉPOUSE le torse ovale, là où une plaque extrudée flotterait de 61 mm
# à ses bords (mesuré sur l'ellipse 0,168 × 0,121 du thorax). Il est ouvert, sans épaisseur : à
# 10 m sa tranche fait 0 px, et la référence assume la même chose (« les pièces se ferment en
# s'emboîtant, pas individuellement »).
#
# ⚠️⚠️ `sz` VAUT TOUJOURS 1.0. L'axe du tour (Z local) devient le Y monde après `rx = −π/2` : lui
# appliquer une échelle DÉPLACERAIT le sommet du casque, c'est-à-dire casserait la contrainte n°1
# sans qu'aucune compilation ne bronche. Seuls `sx` (largeur) et `sy` (profondeur) sont ouverts.
static func _loft_vertical(profil: Array, centre: Vector3, aplat: float, seg: int,
		phi_start := 0.0, phi_len := TAU):
	var p := []
	for pt in profil:
		p.append(Vector2(float(pt[0]) - centre.y, float(pt[1])))
	var g = Meshgen.lathe_z(p, seg, phi_start, phi_len)
	var b := Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0), EULER_ORDER_XYZ)
	b = b.scaled_local(Vector3(1.0, aplat, 1.0))
	g.apply_transform(Transform3D(b, centre))
	return g


# Après `rx = −π/2`, un point de tour d'angle φ atterrit en (r·cosφ, axial, aplat·r·sinφ) :
# **le devant du personnage est donc φ = +π/2, le dos φ = −π/2**. Les deux constantes existent pour
# que ce raisonnement ne soit pas refait (de travers) à chaque panneau.
const PHI_DEVANT := PI * 0.5
const PHI_DOS := -PI * 0.5


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `_pose_sur_ellipse` — poser une pochette SUR un tronc ovale, pas devant
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Rend le Z et le lacet d'une pièce plaquée à l'abscisse latérale `x` d'une ellipse de demi-axes
# (`r`, `r·aplat`).
# ⚠️ L'orientation vient de la NORMALE de l'ellipse (x/a², z/b²) et surtout PAS du rayon vecteur :
# sur une section aplatie à 0,72 les deux divergent de plusieurs degrés, et une pochette orientée
# au rayon vecteur rentre dans le torse par un coin — le genre de défaut qui ne se voit qu'en
# capture, jamais dans un boot headless à 0 ERROR.
static func _pose_sur_ellipse(x: float, r: float, aplat: float) -> Dictionary:
	var b := r * maxf(aplat, 1e-6)
	var cx := clampf(x / maxf(r, 1e-6), -0.999, 0.999)
	var z := b * sqrt(1.0 - cx * cx)
	return {"z": z, "ry": atan2(x / (r * r), z / (b * b))}


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `_ajouter_paire` — LE MIROIR CORRECT (et pourquoi ce n'est pas `Assembly.add_mirrored`)
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ╔═ ⚠️ CONSTAT VÉRIFIÉ, PAS UNE OPINION ════════════════════════════════════════════════════════╗
# ║ `Assembly.add_mirrored` (`trench_meshgen.gd:1372`) ne négligle QUE `x` et `sx`. Or le miroir    ║
# ║ d'une pièce transformée est M·R·p + M·t, et pour l'écrire sous la forme `basis = R'·M` il faut  ║
# ║ R' = M·R·M, c'est-à-dire **(rx, −ry, −rz)** : les rotations autour de Y et de Z CHANGENT DE     ║
# ║ SIGNE, celle autour de X non. `add_mirrored` n'est donc exact que pour une pièce sans `ry` ni   ║
# ║ `rz` — ce qui est le cas de nos jambes pré-transformées (t vide) mais PAS de nos pochettes, qui ║
# ║ portent le lacet de `_pose_sur_ellipse`.                                                        ║
# ║ ✅ Aucun défaut existant : `add_mirrored` n'a **zéro appelant** dans tout le dépôt (grep). Mais  ║
# ║ le premier appelant qui lui passerait un `ry` obtiendrait une pièce fausse en silence, du bon   ║
# ║ côté et tournée du mauvais. On ne le corrige pas depuis ici (c'est le fichier d'un autre lot),  ║
# ║ on ne l'utilise simplement pas, et le motif juste est écrit ici une seule fois.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func _ajouter_paire(asm, g, mat: String, t := {}) -> void:
	if g == null:
		return
	asm.add(g, mat, t)
	var t2 := t.duplicate()
	t2["x"] = -float(t.get("x", 0.0))
	t2["ry"] = -float(t.get("ry", 0.0))
	t2["rz"] = -float(t.get("rz", 0.0))
	t2["sx"] = -float(t.get("sx", 1.0))
	asm.add(g, mat, t2)


# =================================================================================================
# LES PIÈCES
# =================================================================================================
# Une fonction par sous-ensemble, qui boulonne sur un `Assembly` — même contrat que
# `trench_wparts.gd`. `asm` est volontairement non typé : `Assembly` est une classe interne d'un
# script préchargé, et le duck-typing est le motif déjà retenu dans `trench_wparts.gd`.


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# CASQUE — sur l'os `Head`. ⛔ LA SEULE PIÈCE QUE `bulk` NE TOUCHE JAMAIS.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Un casque d'ordonnance est d'une taille pour toute l'unité : le faire grossir de 6 % avec le
# `breacher` n'aurait aucun sens matériel — et, surtout, la moindre cote de casque touchée par une
# variante rouvre exactement le piège que ce fichier existe pour fermer.
static func add_casque(asm) -> void:
	var tete := os_position("Head")
	var demi_h := _casque_demi_hauteur()
	var cy := tete.y + CASQUE_CENTRE_DY
	# Le casque recule de 6 mm par rapport au crâne : la coque déborde davantage sur la nuque que
	# sur le front, ce qui est ce que fait un casque porté (et ce qui creuse l'ombre du visage).
	var cz := tete.z + 0.006
	var centre := Vector3(0.0, cy, cz)

	# ── La coque. 11 points × 16 quartiers = 320 triangles, le plus gros poste du fichier ─────────
	var profil := []
	for f in CASQUE_PROFIL:
		profil.append([cy + float(f[0]) * demi_h, float(f[1]) * CASQUE_DEMI_LARGEUR])
	asm.add(_loft_vertical(profil, centre, CASQUE_APLAT, CASQUE_SEG), MAT_COQUE)

	# ── Le bandeau (« cat eye band ») — 30 mm au-dessus du centre de coque ────────────────────────
	# Ce n'est pas de la décoration : c'est la seule ARÊTE HORIZONTALE du casque. Elle coupe la
	# calotte en deux et c'est elle qui empêche le casque de lire comme une bille à contre-jour.
	# Rayon 0,1082 : la coque y mesure ~0,1078, le tore de 4,5 mm dépasse donc de ~4,5 mm.
	# ⚠️ `ring` vit dans le plan XY, tube selon Z : après `rx = −π/2`, `sy` étire bien la
	# PROFONDEUR (Z monde) et `sz` l'épaisseur verticale. Ne pas intervertir les deux.
	asm.add(Meshgen.ring(0.1082, 0.0045, 14, 4), MAT_SANGLE,
		{"x": 0.0, "y": cy + 0.030, "z": cz, "rx": -PI * 0.5, "sy": CASQUE_APLAT})

	# ── La visière (le bec avant) ─────────────────────────────────────────────────────────────────
	# Contour dans le plan XY, extrudé selon Z (l'épaisseur). Après `rx = −π/2 + 0,20` l'épaisseur
	# devient verticale, le contour devient horizontal, et les 0,20 rad d'écart couchent le bec de
	# ~11° vers le bas : la pointe descend de 7,6 mm et avance de 37 mm.
	# ⚠️ Dans ce contour, **+y local = VERS L'ARRIÈRE** (rx = −π/2 envoie +y local sur −z monde) :
	# la pointe du bec est donc le point à y = −0,036, et non l'inverse.
	asm.add(Meshgen.extrude([
		[-0.098, 0.020], [-0.072, 0.036], [0.0, 0.042], [0.072, 0.036], [0.098, 0.020],
		[0.084, -0.020], [0.0, -0.036], [-0.084, -0.020],
	], 0.008, {"bevel": 0.0012}), MAT_COQUE,
		{"x": 0.0, "y": cy - 0.022, "z": tete.z + 0.052, "rx": -PI * 0.5 + 0.20})

	# ── La jugulaire : deux sangles + une boucle de menton ────────────────────────────────────────
	# Sangles de 5,5 mm d'épaisseur : sous 9 mm, `_face_seg` de `box()` rend 1 et la boîte coûte
	# 44 triangles au lieu de 188. C'est la raison pour laquelle toutes les sangles de ce fichier
	# sont épaisses de 6 à 8 mm — une cote de sangle réelle, qui se trouve aussi être la cote
	# rentable. Au-dessus de 9 mm, le prix quadruple pour un relief qu'on ne voit pas.
	# La sangle part du bord du casque (±0,092 ; y = cy − 0,046) et descend vers le menton.
	_ajouter_paire(asm, Meshgen.box(0.020, 0.0055, 0.088, 0.0015, 1), MAT_SANGLE,
		{"x": 0.092, "y": cy - 0.088, "z": cz + 0.012, "rx": 1.28, "rz": 0.16})
	# La boucle, sous la mâchoire (os `Head` moins 60 mm, la cote du bas de mâchoire du crâne).
	asm.add(Meshgen.box(0.034, 0.016, 0.007, 0.0012, 1), MAT_FERRURE,
		{"x": 0.0, "y": tete.y - 0.062, "z": tete.z + 0.052})


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# TÊTE, VISAGE, COU, COL — sur `Head` et `Neck`
# ─────────────────────────────────────────────────────────────────────────────────────────────────
static func add_tete(asm) -> void:
	var tete := os_position("Head")
	var cou := os_position("Neck")
	var spine2 := os_position("Spine2")
	var centre := Vector3(0.0, tete.y, tete.z)

	# ── Le crâne ──────────────────────────────────────────────────────────────────────────────────
	# ⚠️ Le sommet est à `tete.y + 0.244` = **1,796 m**, et le 0,244 n'est pas choisi : c'est la
	# hauteur de tête cotée par la référence (`parts.js:275`), celle-là même qui sert au rig à
	# démonter le commentaire mort « 8 heads » (piège C). Le crâne nu passe donc 14,6 mm SOUS le
	# sommet du casque — ce qui est exactement ce que le rig annonce, et une vérification gratuite :
	# si un jour le crâne dépassait le casque, c'est que l'une des deux cotes aurait bougé seule.
	asm.add(_loft_vertical([
		[tete.y - 0.060, 0.052],   # bas de mâchoire — le cou ferme dessous
		[tete.y - 0.032, 0.072],
		[tete.y + 0.008, 0.082],
		[tete.y + 0.058, 0.085],   # pommettes, largeur maximale
		[tete.y + 0.128, 0.079],
		[tete.y + 0.188, 0.060],
		[tete.y + 0.244, 0.0],     # ⚠️ 0,244 = leur hauteur de tête, cf. ci-dessus
	], centre, 1.14, 12), MAT_GANT)

	# ── Le VIDE sous la visière ───────────────────────────────────────────────────────────────────
	# ╔═ POURQUOI UNE PIÈCE POUR UNE OMBRE ═══════════════════════════════════════════════════════╗
	# ║ À 10 m, un visage éclairé sous un casque lit comme une tache CLAIRE : le contraire du seul  ║
	# ║ indice qui dit « ennemi » plutôt que « figurant ». Le matériau `cavity` est le seul du       ║
	# ║ registre qui n'a AUCUN lobe spéculaire (`metallic_specular = 0`) — sans quoi le visage       ║
	# ║ s'allume en incidence rasante, ce que la référence décrit comme « un croissant clair peint   ║
	# ║ en travers du bas de la lunette ».                                                          ║
	# ║ C'est un ARC de tour de 2 mm plus large que le crâne, pas une plaque : une plaque plate      ║
	# ║ posée devant un crâne ovale disparaît DEDANS (mesuré : 10 mm de trop) ou flotte devant.     ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	asm.add(_loft_vertical([
		[tete.y + 0.002, 0.081],
		[tete.y + 0.026, 0.085],
		[tete.y + 0.050, 0.087],
		[tete.y + 0.066, 0.082],
	], centre, 1.14, 8, PHI_DEVANT - 0.85, 1.70), MAT_OMBRE)

	# ── Le cou ────────────────────────────────────────────────────────────────────────────────────
	asm.add(_fuseau(
		Vector3(0.0, cou.y - 0.013, cou.z), Vector3(0.0, tete.y - 0.007, tete.z),
		0.058, 0.050, {"seg": SEG_MEMBRE, "ventre": 1.0, "aplat": 0.94}), MAT_GANT)

	# ── Le col relevé ─────────────────────────────────────────────────────────────────────────────
	# Il coupe la colonne cou→casque en deux et donne au personnage sa lecture « emmitouflé ».
	asm.add(_loft_vertical([
		[spine2.y + 0.055, 0.098],
		[spine2.y + 0.085, 0.104],
		[cou.y - 0.005, 0.100],
		[cou.y + 0.017, 0.086],
	], Vector3(0.0, spine2.y, spine2.z), 0.90, 12), MAT_TOILE)


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# TORSE + GILET PORTE-PLAQUES — sur `Spine1` et `Spine2`
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ⚠️ SEUL ENDROIT DU FICHIER OÙ `bulk` MORD FRANCHEMENT — et il ne touche que le RAYON latéral et
# la profondeur. Les huit cotes en Y du profil sont dérivées des os et restent identiques pour les
# trois variantes : c'est ce qui garantit qu'aucune silhouette ne dépasse la boîte.
static func add_torse(asm, bulk: float) -> void:
	var hanche := os_position("Hips")
	var spine := os_position("Spine")
	var spine1 := os_position("Spine1")
	var spine2 := os_position("Spine2")
	var cou := os_position("Neck")
	# L'axe du tronc est vertical, à mi-chemin entre `Spine1` (z = 0,000) et `Spine2` (z = +0,006).
	# ⚠️ Un tour est une surface de RÉVOLUTION : il ne peut pas suivre le serpentement en Z de la
	# colonne (±12 mm de cambrure). On assume — 12 mm à 10 m font 0 px — mais on ne le maquille pas
	# derrière un profil qui prétendrait le porter.
	var centre := Vector3(0.0, spine1.y, (spine1.z + spine2.z) * 0.5)
	var aplat := 0.72   # un torse est 28 % moins profond que large

	asm.add(_loft_vertical([
		[hanche.y + 0.015, 0.118 * bulk],   # ferme le tube par le bas, sous le bassin
		[spine.y - 0.030, 0.140 * bulk],
		[spine.y + 0.060, 0.148 * bulk],    # taille
		[spine1.y + 0.025, 0.168 * bulk],   # cage thoracique
		[spine2.y - 0.015, 0.182 * bulk],
		[spine2.y + 0.055, 0.185 * bulk],   # ligne d'épaules — les bras s'y greffent
		[spine2.y + 0.095, 0.152 * bulk],   # trapèze
		[cou.y - 0.005, 0.090],             # base du cou : fermeture, `bulk` n'a rien à y faire
	], centre, aplat, SEG_TORSE), MAT_TOILE)

	# ── Les deux panneaux du gilet ────────────────────────────────────────────────────────────────
	# Des ARCS de 114° (cf. le pavé de `_loft_vertical`), 24 mm plus larges que le torse. Le profil
	# est le même devant et derrière : c'est un porte-plaques, pas un plastron sculpté.
	var profil_gilet := [
		[spine.y + 0.020, 0.176 * bulk],
		[spine1.y - 0.035, 0.192 * bulk],
		[spine1.y + 0.055, 0.200 * bulk],
		[spine2.y + 0.005, 0.204 * bulk],
		[spine2.y + 0.055, 0.196 * bulk],
	]
	asm.add(_loft_vertical(profil_gilet, centre, aplat, SEG_PANNEAU,
		PHI_DEVANT - 1.0, 2.0), MAT_GILET)
	asm.add(_loft_vertical(profil_gilet, centre, aplat, SEG_PANNEAU,
		PHI_DOS - 1.0, 2.0), MAT_GILET)

	# ── Les bretelles d'épaule, qui relient les deux panneaux ─────────────────────────────────────
	# Sans elles, les deux panneaux flottent : c'est la bretelle qui les rend un objet unique.
	_ajouter_paire(asm, Meshgen.box(0.055, 0.008, 0.170, 0.0018, 1), MAT_GILET,
		{"x": 0.085, "y": spine2.y + 0.100, "z": centre.z, "rz": -0.08})

	# ── Le cummerbund (la ceinture large du gilet) ────────────────────────────────────────────────
	asm.add(_loft_vertical([
		[spine.y + 0.020, 0.152 * bulk],
		[spine.y + 0.045, 0.158 * bulk],
		[spine.y + 0.085, 0.150 * bulk],
	], centre, aplat, SEG_BASSIN), MAT_GILET)

	# ── Trois pochettes de poitrine ───────────────────────────────────────────────────────────────
	# Posées SUR l'ellipse du gilet (rayon 0,200·bulk), pas devant elle. Deux chargeurs de part et
	# d'autre, une pochette centrale plus basse.
	var r_gilet := 0.200 * bulk
	var pochette = Meshgen.extrude(
		Meshgen.round_rect(0.078, 0.100, 0.014, 2), 0.042, {"bevel": 0.003})
	var pose: Dictionary = _pose_sur_ellipse(0.082, r_gilet, aplat)
	_ajouter_paire(asm, pochette, MAT_GILET, {
		"x": 0.082, "y": spine1.y + 0.045, "z": centre.z + float(pose["z"]),
		"ry": float(pose["ry"])})
	var pose_c: Dictionary = _pose_sur_ellipse(0.0, r_gilet, aplat)
	asm.add(Meshgen.extrude(Meshgen.round_rect(0.086, 0.076, 0.014, 2), 0.038, {"bevel": 0.003}),
		MAT_GILET, {"x": 0.0, "y": spine.y + 0.055, "z": centre.z + float(pose_c["z"]) - 0.006})


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# BRAS — sur `UpperArm*`, `Forearm*` (coudes DÉRIVÉS) et `Hand*` (prises DÉRIVÉES)
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ╔═ ⛔ LES BRAS NE SONT **JAMAIS** MIROITÉS — c'est le piège A du rig, dit en géométrie ═════════╗
# ║ La pose de repos est un port d'arme : `HandL` (x ≈ −0,097) et `FingersL` (x ≈ −0,121) sont du   ║
# ║ côté DROIT du corps, parce que la main de soutien TRAVERSE pour tenir le garde-main. Miroiter   ║
# ║ le bras droit poserait donc la main de soutien à droite ET la main de tir à gauche : le fusil   ║
# ║ change de main, et aucun test de compilation ne bronche. Les deux bras lisent leurs quatre os   ║
# ║ chacun, séparément.                                                                            ║
# ║ ✅ Les JAMBES, elles, sont des miroirs EXACTS dans la table (±0,092 / ±0,098 / ±0,103) parce    ║
# ║ que l'arme ne les concerne pas : `add_jambes()` a donc le droit d'en bâtir une seule.           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func add_bras(asm, bulk: float) -> void:
	var k := _facteur_membre(bulk)
	_add_un_bras(asm, "UpperArmR", "ForearmR", "HandR", Rig.FINGERS_R_DIR, k)
	_add_un_bras(asm, "UpperArmL", "ForearmL", "HandL", Rig.FINGERS_L_DIR, k)


static func _add_un_bras(asm, os_epaule: String, os_coude: String, os_main: String,
		dir_doigts: Vector3, k: float) -> void:
	var epaule := os_position(os_epaule)
	var coude := os_position(os_coude)
	var poignet := os_position(os_main)

	# Haut de bras : gros au deltoïde (62 mm), fin au coude (45 mm). `cap0` à 0,88 : la tranche
	# haute reste large pour se noyer dans le trapèze du torse plutôt que de laisser un trou.
	asm.add(_fuseau(epaule, coude, 0.062 * k, 0.045 * k,
		{"seg": SEG_MEMBRE, "ventre": 1.02, "cap0": 0.88, "deb0": 0.026}), MAT_TOILE)

	# Avant-bras : ventre à 1,08 (le brachio-radial), fin au poignet.
	asm.add(_fuseau(coude, poignet, 0.048 * k, 0.034 * k,
		{"seg": SEG_MEMBRE, "ventre": 1.08, "aplat": 0.92}), MAT_TOILE)

	# ── La main ───────────────────────────────────────────────────────────────────────────────────
	# ⚠️ L'os `Hand*` EST le milieu de la paume (c'est une projection sur la ligne de visée, pas un
	# poignet anatomique) : le poing s'étend donc de 32 mm en arrière et 50 mm en avant de l'ancre,
	# pas 82 mm en avant. Cette dissymétrie n'est pas cosmétique — voir `rapport_profondeur()`.
	# ⚠️ PAS DE POUCE, PAS DE DOIGTS : 8 cm de main à 10 m font 9 % de la largeur de plaque, un
	# pouce en fait 2 %. On ne maille pas ce qui tient sous le seuil (cf. le pavé d'en-tête).
	var d := dir_doigts.normalized()
	asm.add(_fuseau(poignet - d * 0.032, poignet + d * 0.050, 0.036 * k, 0.030 * k,
		{"seg": SEG_MAIN, "ventre": 1.04, "aplat": 0.68, "cap0": 0.55,
		"cap1": 0.0, "deb0": 0.008, "deb1": 0.012}), MAT_GANT)


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# BASSIN, CEINTURON ET SES POCHES — sur `Hips`
# ─────────────────────────────────────────────────────────────────────────────────────────────────
static func add_bassin(asm, bulk: float) -> void:
	var hanche := os_position("Hips")
	var centre := Vector3(0.0, hanche.y, hanche.z)
	var aplat := 0.74

	asm.add(_loft_vertical([
		[hanche.y - 0.100, 0.108 * bulk],
		[hanche.y - 0.050, 0.140 * bulk],
		[hanche.y + 0.005, 0.155 * bulk],   # crêtes iliaques : le point le plus large du bassin
		[hanche.y + 0.060, 0.142 * bulk],
		[hanche.y + 0.110, 0.125 * bulk],   # se noie dans le bas du torse
	], centre, aplat, SEG_BASSIN), MAT_TOILE)

	# ── Le ceinturon : 8 mm de saillie sur 46 mm de haut ──────────────────────────────────────────
	# C'est la ligne horizontale qui sépare le tronc des jambes. Sans elle, un fantassin en toile
	# unie lit comme une combinaison d'une pièce.
	var r_ceinture := 0.157 * bulk
	asm.add(_loft_vertical([
		[hanche.y + 0.060, 0.150 * bulk],
		[hanche.y + 0.068, r_ceinture],
		[hanche.y + 0.106, r_ceinture],
		[hanche.y + 0.114, 0.150 * bulk],
	], centre, aplat, SEG_BASSIN), MAT_SANGLE)

	asm.add(Meshgen.box(0.048, 0.032, 0.008, 0.0015, 1), MAT_FERRURE,
		{"x": 0.0, "y": hanche.y + 0.087, "z": centre.z + r_ceinture * aplat + 0.003})

	# ── Trois pochettes de ceinture : deux sur les hanches, une dans le dos ───────────────────────
	var poche = Meshgen.extrude(
		Meshgen.round_rect(0.072, 0.086, 0.012, 2), 0.046, {"bevel": 0.003})
	var pose: Dictionary = _pose_sur_ellipse(0.105 * bulk, r_ceinture, aplat)
	_ajouter_paire(asm, poche, MAT_GILET, {
		"x": 0.105 * bulk, "y": hanche.y + 0.082, "z": centre.z + float(pose["z"]),
		"ry": float(pose["ry"])})
	asm.add(poche, MAT_GILET,
		{"x": 0.0, "y": hanche.y + 0.086, "z": centre.z - r_ceinture * aplat - 0.018})


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# JAMBES — sur `UpLeg*`, `Leg*`, `Foot*`, `Toe*`. Bâties À DROITE (x < 0), puis MIROITÉES.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ✅ Le miroir est EXACT ici : les huit os de jambes sont symétriques au bit près dans la table
# (±0,092 / ±0,098 / ±0,103, mêmes y, mêmes z). Vérifié os par os. Cf. l'avertissement de
# `add_bras()` pour la raison pour laquelle le haut du corps n'a pas ce droit.
# ⚠️ Le miroir passe par `_ajouter_paire` avec un `t` VIDE : les pièces sont déjà transformées dans
# l'espace acteur, `sx = −1` suffit donc, et l'absence de `ry`/`rz` rend la question du signe des
# angles sans objet.
static func add_jambes(asm, bulk: float) -> void:
	var k := _facteur_membre(bulk)
	var hanche_j := os_position("UpLegR")
	var genou := os_position("LegR")
	var cheville := os_position("FootR")
	var orteil := os_position("ToeR")

	# ── Cuisse ────────────────────────────────────────────────────────────────────────────────────
	# 85 mm au sommet : le grand trochanter est plus large que le bassin lui-même, et c'est correct.
	_ajouter_paire(asm, _fuseau(hanche_j, genou, 0.085 * k, 0.058 * k,
		{"seg": SEG_MEMBRE, "ventre": 1.04, "aplat": 0.92, "cap0": 0.80, "deb0": 0.030}),
		MAT_TOILE)

	# ── Genouillère ───────────────────────────────────────────────────────────────────────────────
	# Posée en avant du genou : `Leg*` est à z = +0,020, la plaque à +0,072.
	_ajouter_paire(asm, Meshgen.extrude(
		Meshgen.round_rect(0.085, 0.098, 0.018, 2), 0.026, {"bevel": 0.003}), MAT_RENFORT,
		{"x": genou.x, "y": genou.y + 0.012, "z": genou.z + 0.052, "rx": 0.10})

	# ── Mollet ────────────────────────────────────────────────────────────────────────────────────
	# `ventre` 1,18 : c'est le renflement le plus marqué du corps, et il est à 42 % de la longueur —
	# le mettre au milieu donne une jambe de poupée.
	_ajouter_paire(asm, _fuseau(genou, cheville, 0.060 * k, 0.040 * k,
		{"seg": SEG_MEMBRE, "ventre": 1.18, "aplat": 0.95}), MAT_TOILE)

	# ── Tige de botte ─────────────────────────────────────────────────────────────────────────────
	# Monte 142 mm au-dessus de la cheville et recouvre le bas du pantalon : la rupture de matériau
	# toile → caoutchouc à cette hauteur est ce qui fait lire « rangers » sans mailler un seul lacet.
	_ajouter_paire(asm, _fuseau(
		Vector3(cheville.x, cheville.y + 0.142, cheville.z + 0.024), cheville,
		0.058 * k, 0.052 * k, {"seg": SEG_MAIN, "ventre": 1.0, "aplat": 0.94}), MAT_SANGLE)

	# ── La botte ──────────────────────────────────────────────────────────────────────────────────
	# Contour de PROFIL (x local = avant, y local = haut), extrudé selon Z = la largeur du pied,
	# puis `ry = −π/2` qui envoie x local sur +Z monde et l'épaisseur sur X. C'est la seule pièce du
	# fichier dessinée « de profil », parce que c'est la seule dont la silhouette utile est un profil.
	# ⚠️ Le contour touche y = 0,000 : c'est la SEMELLE, et c'est ce qui donne son sens à « feet on
	# y = 0 » du rig. Aucun os n'y touche (le plus bas est l'orteil, à 0,030) — chercher à en caler
	# un dessus déformerait le pied.
	# Longueur totale 283 mm (talon à −0,100, bout à +0,183), pour un os d'orteil à +0,108 : le bout
	# de la botte dépasse l'articulation de 75 mm, comme un vrai pied.
	var z0 := cheville.z
	_ajouter_paire(asm, Meshgen.extrude([
		[-0.062, 0.095], [0.010, 0.100], [0.115, 0.060], [0.190, 0.038], [0.205, 0.018],
		[0.196, 0.000], [-0.060, 0.000], [-0.078, 0.030], [-0.074, 0.072],
	], 0.098, {"bevel": 0.0025}), MAT_SANGLE,
		{"x": cheville.x, "y": 0.0, "z": z0, "ry": -PI * 0.5})
	# ⚠️ `orteil` n'est pas consommé par la géométrie : le contour de profil porte déjà la longueur.
	# Il est LU quand même, pour que la sonde du lot suivant puisse comparer les deux — et pour que
	# la ligne ci-dessous rougisse si l'os d'orteil sortait un jour de la botte.
	if orteil.z > z0 + 0.196:
		push_warning("[trench_soldier_parts] l'os ToeR (z = %.3f) sort du bout de botte (z = %.3f)"
			% [orteil.z, z0 + 0.196])


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ACCESSOIRES DE VARIANTE — la deuxième moitié de la différence de silhouette
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `bulk` seul ne suffit pas : 6 % de tour de poitrine, à 10 m, c'est 4 px. Ce qui distingue
# réellement trois soldats à cette distance, c'est la DÉCOUPE de leur contour — une épaulière
# carrée, une musette qui pend, un col qui enfle. D'où ces trois jeux, tous à cotes LATÉRALES.
static func add_accessoires(asm, variante: String, bulk: float) -> void:
	var spine1 := os_position("Spine1")
	var spine2 := os_position("Spine2")
	var cou := os_position("Neck")
	var epaule := os_position("UpperArmR")
	var coude := os_position("ForearmR")
	var jeu := "plastrons"
	if VARIANTES.has(variante):
		var spec: Dictionary = VARIANTES[variante]
		jeu = String(spec["accessoires"])

	match jeu:
		"plastrons":
			# VANGUARD — le fantassin de ligne : deux plastrons d'épaule plats + une poche radio.
			_ajouter_paire(asm, Meshgen.extrude(
				Meshgen.round_rect(0.100, 0.075, 0.016, 2), 0.018, {"bevel": 0.0025}), MAT_GILET,
				{"x": -epaule.x, "y": epaule.y + 0.030, "z": epaule.z, "rx": PI * 0.5, "rz": 0.22})
			asm.add(Meshgen.extrude(
				Meshgen.round_rect(0.090, 0.110, 0.014, 2), 0.040, {"bevel": 0.003}), MAT_GILET,
				{"x": 0.052, "y": spine1.y + 0.060, "z": -0.152 * bulk})

		"musette":
			# IRREGULAR — plus léger et plus étroit : une écharpe qui gonfle le cou (c'est ELLE qui
			# porte la lecture, pas les 6 % de torse en moins) et une musette en bandoulière.
			asm.add(_loft_vertical([
				[spine2.y + 0.070, 0.106],
				[spine2.y + 0.100, 0.118],
				[cou.y + 0.010, 0.112],
				[cou.y + 0.030, 0.094],
			], Vector3(0.0, spine2.y, spine2.z), 0.94, 12), MAT_TOILE)
			asm.add(Meshgen.extrude(
				Meshgen.round_rect(0.130, 0.110, 0.020, 3), 0.052, {"bevel": 0.003}), MAT_GILET,
				{"x": -0.118, "y": spine1.y - 0.085, "z": 0.055, "ry": -0.55})
			# La bandoulière : de l'épaule droite à la hanche gauche, d'où le `rz` prononcé.
			asm.add(Meshgen.box(0.040, 0.006, 0.300, 0.0012, 1), MAT_SANGLE,
				{"x": -0.030, "y": spine1.y + 0.020, "z": 0.128 * bulk,
				"rz": 0.62, "rx": PI * 0.5})

		"epaulieres":
			# BREACHER — massif : deux épaulières RENFORCÉES, poussées de 10 mm vers l'extérieur.
			# ⚠️ C'est la pièce la plus large du personnage : |x| ≈ 0,238 m, soit 54 % de la borne
			# de 0,44. Elle remplace exactement ce que leur `scale = 1.025` faisait sortir de la
			# boîte par le haut — largeur contre hauteur, et la boîte ne change pas.
			_ajouter_paire(asm, Meshgen.extrude(
				Meshgen.round_rect(0.115, 0.095, 0.020, 3), 0.024, {"bevel": 0.003}), MAT_RENFORT,
				{"x": -epaule.x + 0.010, "y": epaule.y + 0.028, "z": epaule.z,
				"rx": PI * 0.5, "rz": 0.26})
			# Renforts d'avant-bras. Épaisseur 8 mm : sous les 9 mm de `_face_seg`, donc 44 tris.
			_ajouter_paire(asm, Meshgen.box(0.070, 0.008, 0.125, 0.0012, 1), MAT_RENFORT,
				{"x": -(coude.x + 0.010), "y": coude.y + 0.055, "z": coude.z + 0.048,
				"rx": 0.42})

		_:
			push_warning("[trench_soldier_parts] jeu d'accessoires inconnu : %s" % jeu)


# =================================================================================================
# CONSTRUCTION
# =================================================================================================
# Rend `{ "id", "body": Assembly, "nodes": {…}, "bulk", "echelle", "tris" }` — même esprit que
# `trench_weapons3d.build()`. Le soldat n'a PAS de sous-assemblages `moving` : ses pièces mobiles
# sont ses OS, et c'est le squelette (lot suivant) qui les anime, pas des `Assembly` séparés.
#
# ⚠️ L'`Assembly` rendu n'est PAS fusionné : `Assembly.build()` VIDE ses seaux et ne peut donc être
# appelé qu'une fois. C'est à l'appelant de le faire, une seule fois, quand il monte ses surfaces.
# `tri_count()` et `self_check()` lisent `buckets` sans y toucher.
#
# ⚠️⚠️ L'appelant DOIT appliquer `Rig.ECHELLE_CASQUE` à la racine — os ET maillage ensemble. Ce
# fichier ne l'applique jamais : deux endroits qui mettent à l'échelle, c'est un facteur au carré.
static func build(variante: String) -> Dictionary:
	var v := variante
	if not VARIANTES.has(v):
		push_warning("[trench_soldier_parts] variante inconnue « %s » — repli sur %s."
			% [variante, VARIANTE_DEFAUT])
		v = VARIANTE_DEFAUT
	var spec: Dictionary = VARIANTES[v]
	var bulk: float = float(spec["bulk"])

	var asm = Meshgen.Assembly.new("soldat-" + v)

	# ⛔ ORDRE VOLONTAIRE : le casque en PREMIER. C'est la seule pièce dont une cote est un contrat,
	# et la lire en tête de fonction évite qu'elle finisse noyée entre deux pochettes.
	add_casque(asm)
	add_tete(asm)
	add_torse(asm, bulk)
	add_bras(asm, bulk)
	add_bassin(asm, bulk)
	add_jambes(asm, bulk)
	add_accessoires(asm, v, bulk)

	var tete := os_position("Head")
	var sommet := sommet_casque()

	return {
		"id": v,
		"body": asm,
		"bulk": bulk,
		# L'échelle à poser sur la RACINE (os + maillage). Rendue ici pour que l'appelant n'aille
		# pas la chercher ailleurs et n'en invente pas une deuxième.
		"echelle": Rig.ECHELLE_CASQUE,
		"tris": asm.total_tris(),
		"nodes": {
			# ⛔ Le sommet EXACT du casque, AVANT échelle. × ECHELLE_CASQUE = 1,80 m pile.
			"headTop": Vector3(0.0, sommet, tete.z + 0.006),
			"helmetCentre": Vector3(0.0, tete.y + CASQUE_CENTRE_DY, tete.z + 0.006),
			# ⚠️ Hauteur d'yeux de la RÉFÉRENCE (1,665), pas celle du joueur (`EYE_UP = 1,70`) :
			# les deux n'ont pas à être égales, mais l'écart de 3,5 cm est à connaître avant de
			# fabriquer une pose « il me regarde dans les yeux ». Cf. le rig.
			"eye": Vector3(0.0, Rig.EYE_HEIGHT_REF, tete.z + 0.098),
			"neck": os_position("Neck"),
			"chest": os_position("Spine2"),
			"hip": os_position("Hips"),
			# Les deux prises, telles que le rig les projette sur la ligne de visée. C'est par ces
			# deux ancres que le lot 3D-F posera l'arme — jamais par des coordonnées recopiées.
			"gripR": Rig.GRIP_R,
			"gripL": Rig.GRIP_L,
			"boreOrigin": Rig.BORE_ORIGIN,
			"boreDir": Rig.BORE_DIR,
		},
	}


# Nombre total de triangles d'une variante. ⚠️ À appeler AVANT `Assembly.build()`.
static func tri_count(variante := VARIANTE_DEFAUT) -> int:
	var r: Dictionary = build(variante)
	var asm = r["body"]
	return int(asm.total_tris())


# Le même total, ventilé par matériau : un seau = un futur `draw call`. Sert à vérifier qu'on reste
# dans l'ordre de grandeur visé par la référence (« 6-8 draw calls » pour une arme entière).
static func tri_count_par_materiau(variante := VARIANTE_DEFAUT) -> Dictionary:
	var r: Dictionary = build(variante)
	var asm = r["body"]
	var out := {}
	for mat in asm.buckets:
		var n := 0
		for g in asm.buckets[mat]:
			n += int(g.tri_count())
		out[mat] = n
	return out


# Enveloppe RÉELLE du maillage (AABB), lue dans les seaux SANS les vider.
static func enveloppe(asm) -> AABB:
	var out := AABB()
	var premier := true
	for mat in asm.buckets:
		for g in asm.buckets[mat]:
			var a: AABB = g.aabb()
			if premier:
				out = a
				premier = false
			else:
				out = out.merge(a)
	return out


# =================================================================================================
# `rapport_profondeur` — LA MESURE QU'ON NE CACHE PAS
# =================================================================================================
# ╔═ 🩸 CE QUE LA MESURE DIT, ET POURQUOI CE N'EST **PAS** UNE ANOMALIE DE CE FICHIER ════════════╗
# ║ `Bounds.budget_profondeur()` vaut **0,3823 m** : au-delà, un morceau de corps avancé vers       ║
# ║ l'observateur est vu plus large que la fenêtre angulaire que le serveur connaît.                ║
# ║ Or l'ancre `GRIP_L` du rig est déjà à **z = +0,3669** — 96 % du budget consommé par la seule    ║
# ║ table d'os, avant qu'un triangle n'ait été posé. Le poing qui s'y accroche sort donc à           ║
# ║ **z ≈ +0,423**, soit ~41 mm au-delà. (Et le rig va plus loin encore sans nous : l'os feuille     ║
# ║ `FingersL` est à z = +0,434, soit 52 mm au-delà, alors qu'il ne porte AUCUNE géométrie ici.)     ║
# ║                                                                                                ║
# ║ ⚠️ ET POURTANT CE N'EST PAS UN MENSONGE MESURABLE, ET LE CHIFFRE LE PROUVE. La borne de          ║
# ║ profondeur est dérivée pour une pièce posée AU BORD de la silhouette (|x| = 0,44) : c'est là     ║
# ║ que ΔZ fait grossir la largeur apparente d'un quantum. Le désaccord réel d'une pièce vaut        ║
# ║   atan(|x| / (10 − ΔZ)) − atan(|x| / 10),                                                       ║
# ║ et pour la main gauche (|x| = 0,117, ΔZ = 0,423) cela fait **0,0295°** — soit moins d'UN TIERS   ║
# ║ du quantum de visée de 0,1°. Autrement dit : la borne unique de `budget_profondeur()` est        ║
# ║ correcte pour ce qu'elle borne, et conservatrice d'un facteur ~3,4 pour une pièce proche de      ║
# ║ l'axe.                                                                                          ║
# ║                                                                                                 ║
# ║ ⛔ CE QU'ON NE FAIT PAS : raccourcir la main à 31 mm pour faire passer le contrôle. Ce serait     ║
# ║ échanger un désaccord de 0,0295° (invisible) contre une main de poupée (visible), et surtout     ║
# ║ rendre VERT un contrôle sur une géométrie fausse — le patron de faux vert que ce dépôt paie      ║
# ║ depuis §8.144. La mesure est donc RENDUE, nommée, chiffrée, et c'est au lot d'intégration de     ║
# ║ trancher : soit la borne est affinée en fonction de |x|, soit `GRIP_L_T` (0,45 m) est revu.      ║
# ║ Les deux vivent ailleurs qu'ici.                                                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func rapport_profondeur(variante := VARIANTE_DEFAUT) -> Dictionary:
	var r: Dictionary = build(variante)
	var asm = r["body"]
	var env := enveloppe(asm)
	var budget := Bounds.budget_profondeur()
	var avant := env.position.z + env.size.z
	var arriere := env.position.z
	return {
		"z_avant": avant,
		"z_arriere": arriere,
		"budget": budget,
		"depassement_avant": maxf(0.0, avant - budget),
		"depassement_arriere": maxf(0.0, -arriere - budget),
	}


# =================================================================================================
# CONTRÔLE DE COHÉRENCE — sans `assert` (un assert échoué BLOQUE Godot en headless)
# =================================================================================================
# Rend la liste des anomalies. VIDE = tout va bien. Chaque point mesure une CONTRAINTE DURE sur la
# géométrie réellement produite, jamais sur une cote recopiée d'un commentaire.
#
# ⚠️ La profondeur n'est PAS ici, et c'est délibéré : elle est mesurée par `rapport_profondeur()`,
# qui explique pourquoi le dépassement de la main gauche n'est pas une anomalie de ce fichier. La
# rendre rouge ici ferait clignoter en permanence une ligne dont la cause vit dans le rig.
static func self_check() -> PackedStringArray:
	var errs := PackedStringArray()

	# 0. Les deux chemins de calcul du sommet doivent coïncider — celui d'ici (somme de cotes) et
	# celui du rig (la constante d'où `ECHELLE_CASQUE` est dérivée). Écrits INDÉPENDAMMENT, ils se
	# comparent : c'est une mesure, pas une promesse.
	var sommet := sommet_casque()
	if absf(sommet - Rig.SOMMET_CASQUE_RENDU) > 1e-9:
		errs.append("sommet calculé %.6f m != Rig.SOMMET_CASQUE_RENDU %.6f m"
			% [sommet, Rig.SOMMET_CASQUE_RENDU])

	# 1. ⛔ CONTRAINTE N°1 : le sommet du casque à 1,80 m PILE après `ECHELLE_CASQUE`.
	# ⚠️ On teste le sommet MESURÉ sur l'AABB du maillage, pas la cote théorique : c'est le seul
	# contrôle que la construction ne peut pas satisfaire par tautologie.
	var hauteurs := {}
	var largeurs := {}
	for v in VARIANTES.keys():
		var nom := String(v)
		var r: Dictionary = build(nom)
		var asm = r["body"]
		var env := enveloppe(asm)
		var haut := (env.position.y + env.size.y) * Rig.ECHELLE_CASQUE
		hauteurs[nom] = haut
		# ⚠️ TOLÉRANCE 2e-5 m (20 µm) ET NON 1e-9. Ce n'est pas de la mollesse : un `Vector3` Godot
		# est en **float32** (`real_t`), dont l'ulp vaut ~2,4e-7 autour de 1,81 — et le sommet
		# traverse un profil, une `Basis`, un `Transform3D` et une AABB, soit une poignée d'ulps.
		# Exiger 1e-9 ferait rougir ce point sur de l'arrondi machine, c'est-à-dire apprendrait à
		# l'ignorer. 20 µm restent 2 800× plus fins que les 55,9 mm que ce point existe pour
		# attraper, et 1 000× plus fins que le quantum de visée à 10 m.
		if absf(haut - Bounds.HAUT_DEBOUT) > 2e-5:
			errs.append("%s : sommet rendu %.6f m après échelle (attendu %.2f)"
				% [nom, haut, Bounds.HAUT_DEBOUT])

		# 2. ⛔ CONTRAINTE N°2 : demi-largeur ≤ 0,44 m, épaules et coudes compris.
		var demi := maxf(absf(env.position.x), absf(env.position.x + env.size.x)) \
			* Rig.ECHELLE_CASQUE
		largeurs[nom] = demi
		if demi > Bounds.DEMI_LARGEUR:
			errs.append("%s : demi-largeur %.4f m > %.2f m"
				% [nom, demi, Bounds.DEMI_LARGEUR])

		# 3. ⛔ CONTRAINTE N°3 : 6 000 triangles, casque compris.
		var tris := int(asm.total_tris())
		if tris > BUDGET_TRIANGLES:
			errs.append("%s : %d triangles > budget %d" % [nom, tris, BUDGET_TRIANGLES])

		# 4. Aucun point sous le sol. ⚠️ La semelle touche y = 0 PILE (« feet on y = 0 ») : le seuil
		# est donc une tolérance de flottant, pas une marge.
		if env.position.y < -1e-6:
			errs.append("%s : géométrie sous le sol (y = %.6f)" % [nom, env.position.y])

		# 5. Toutes les clés de matériau existent RÉELLEMENT dans le registre. Une clé fautive ne
		# lève aucune erreur à la construction : elle rend un magenta, qu'il faut une capture pour
		# voir. Ce point-ci la rend impossible à livrer.
		for mat in asm.buckets:
			if not WMat.has_key(String(mat)):
				errs.append("%s : clé de matériau « %s » absente de trench_wmaterials"
					% [nom, String(mat)])

	# 6. ⛔ CONTRAINTE N°4 : LE PIÈGE DU BREACHER. Les trois variantes doivent culminer EXACTEMENT
	# à la même hauteur. C'est le contrôle qui rougirait si quelqu'un réintroduisait leur `scale`
	# de variante — le défaut qui, chez eux, sort 55,9 mm de casque hors de la boîte serveur.
	var refh: float = float(hauteurs.get(VARIANTE_DEFAUT, 0.0))
	for v in hauteurs.keys():
		var h: float = float(hauteurs[v])
		if absf(h - refh) > 1e-6:
			errs.append("PIÈGE DU BREACHER : %s culmine à %.6f m contre %.6f m pour %s — une "
				% [String(v), h, refh, VARIANTE_DEFAUT]
				+ "variante a repris une échelle de HAUTEUR")

	# 7. Et la contre-épreuve du même piège : les largeurs, elles, doivent bien DIFFÉRER. Trois
	# variantes de largeur identique voudraient dire que `bulk` n'est branché nulle part — un
	# fichier qui passerait tous les points ci-dessus en ne produisant qu'une seule silhouette.
	var lmin := INF
	var lmax := -INF
	for v in largeurs.keys():
		var l: float = float(largeurs[v])
		lmin = minf(lmin, l)
		lmax = maxf(lmax, l)
	if lmax - lmin < 0.001:
		errs.append("les trois variantes ont la même demi-largeur (%.4f m) : `bulk` n'agit pas"
			% lmax)

	return errs


# =================================================================================================
# BUDGET DE TRIANGLES — compté À LA MAIN sur les segments, remesurable par `tri_count()`
# =================================================================================================
# Formules des primitives (relues dans `trench_meshgen.gd`, pas supposées) :
#   • `lathe_z(profil, seg)` ............ 2 · seg · (points − 1)
#   • `_fuseau` (5 points) .............. 8 · seg
#   • `extrude(pts, ...)` avec biseau ... 8 · n − 4   (capots 2(n−2) + paroi 2n + 2 couronnes 4n)
#   • `ring(r, e, seg, rings)` .......... 2 · seg · rings
#   • `box(...)` ........................ 12·fseg² + 24·seg·fseg + 8·(2seg² − seg)
#       ⚠️ `fseg = clamp(round(min(w,h,d) / 0,006), 1, 3)` : une cote mini SOUS 9 mm donne fseg = 1
#       et une boîte à 44 triangles ; au-dessus, fseg = 3 et la MÊME boîte en coûte 188. Toutes les
#       sangles et boucles de ce fichier sont épaisses de 5,5 à 8 mm pour cette raison — qui se
#       trouve être aussi la cote réelle d'une sangle.
#
# ── CASQUE (identique pour les trois variantes — `bulk` ne le touche jamais) ──────────────────────
#   coque .............. lathe 11 pts × 16 seg .......... 2·16·10 = 320
#   bandeau ............ ring 14 × 4 .................... 2·14·4  = 112
#   visière ............ extrude 8 pts .................. 8·8−4   =  60
#   jugulaire ×2 ....... box fseg 1, seg 1 .............. 2·44    =  88
#   boucle de menton ... box fseg 1, seg 1 .............. 44      =  44
#                                                          sous-total   624
# ── TÊTE / VISAGE / COL ──────────────────────────────────────────────────────────────────────────
#   crâne .............. lathe 7 pts × 12 seg ........... 2·12·6  = 144
#   ombre de visière ... arc 4 pts × 8 seg .............. 2·8·3   =  48
#   cou ................ fuseau × 10 seg ................ 8·10    =  80
#   col relevé ......... lathe 4 pts × 12 seg ........... 2·12·3  =  72
#                                                          sous-total   344
# ── TORSE / GILET ────────────────────────────────────────────────────────────────────────────────
#   torse .............. lathe 8 pts × 16 seg ........... 2·16·7  = 224
#   panneau avant ...... arc 5 pts × 10 seg ............. 2·10·4  =  80
#   panneau arrière .... arc 5 pts × 10 seg ............. 2·10·4  =  80
#   bretelles ×2 ....... box fseg 1 ..................... 2·44    =  88
#   cummerbund ......... lathe 3 pts × 14 seg ........... 2·14·2  =  56
#   pochettes ×3 ....... extrude 12 pts ................. 3·92    = 276
#                                                          sous-total   804
# ── BRAS (droit + gauche, jamais miroités) ───────────────────────────────────────────────────────
#   haut de bras ×2 .... fuseau × 10 seg ................ 2·80    = 160
#   avant-bras ×2 ...... fuseau × 10 seg ................ 2·80    = 160
#   main ×2 ............ fuseau × 8 seg ................. 2·64    = 128
#                                                          sous-total   448
# ── BASSIN / CEINTURON / JAMBES ──────────────────────────────────────────────────────────────────
#   bassin ............. lathe 5 pts × 14 seg ........... 2·14·4  = 112
#   ceinturon .......... lathe 4 pts × 14 seg ........... 2·14·3  =  84
#   boucle ............. box fseg 1 ..................... 44      =  44
#   poches ×3 .......... extrude 12 pts ................. 3·92    = 276
#   cuisse ×2 .......... fuseau × 10 seg ................ 2·80    = 160
#   genouillère ×2 ..... extrude 12 pts ................. 2·92    = 184
#   mollet ×2 .......... fuseau × 10 seg ................ 2·80    = 160
#   tige de botte ×2 ... fuseau × 8 seg ................. 2·64    = 128
#   botte ×2 ........... extrude 9 pts .................. 2·68    = 136
#                                                          sous-total  1284
#                                             ══════════════════════════════
#                                             SOCLE COMMUN            3 504
#
# ── ACCESSOIRES, par variante ────────────────────────────────────────────────────────────────────
#   vanguard   : 2 plastrons (2·92) + poche radio (92) ............  276  →  TOTAL  3 780
#   irregular  : écharpe (72) + musette (124) + bandoulière (44) ...  240  →  TOTAL  3 744
#   breacher   : 2 épaulières (2·124) + 2 renforts (2·44) ..........  336  →  TOTAL  3 840
#
# ⛔ PIRE CAS = 3 840 triangles, soit **64 % du budget de 6 000**. Les 2 160 restants sont une
# MARGE, pas un solde à dépenser : la cible fait 0,88 m de large à 10 m, et le seuil de visibilité
# (18 mm ≈ 2 % de la plaque) est déjà atteint sur les pièces mailées. Le prochain triangle utile
# n'est pas un détail de plus — c'est une passe d'ANIMATION, qui ne coûte aucun triangle.
#
# ── LES AUTRES COTES, POUR MÉMOIRE (toutes remesurées par `self_check()`) ─────────────────────────
#   sommet du casque .... 1,810600 m AVANT échelle · × 0,9941456 = **1,800000 m** APRÈS
#   crâne nu ............ 1,796 m (14,6 mm sous le casque — la cote 0,244 de la référence)
#   demi-largeur max .... 0,2376 m avant échelle → 0,2362 m après (54 % de la borne de 0,44),
#                         atteinte par l'épaulière du `breacher` ; le deltoïde nu est à 0,2331,
#                         et les trois variantes tiennent entre 0,2313 et 0,2376
#   semelle ............. y = 0,000 m pile
#   profondeur .......... z ∈ [≈ −0,172 ; +0,4226] — cf. `rapport_profondeur()` pour le +0,4226
