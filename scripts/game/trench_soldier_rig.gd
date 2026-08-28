extends RefCounted
# =================================================================================================
# LA TRANCHÉE — SQUELETTE DU SOLDAT ADVERSE (§8.152) — module PUR, 100 % statique, sans nœud.
#
# Port de `Claude-of-Duty-main/src/ai/rig.js` (265 lignes). 25 os, cotés EN MÈTRES dans l'espace de
# repos de l'acteur : « feet on y = 0, the character facing +Z ». Aucun asset : la table EST le
# modèle. Le fichier ne construit rien — il fournit la donnée et les deux dérivations (bore → mains,
# épaule+poignet → coude) pour que `Skeleton3D` / une hiérarchie de `Node3D` soit bâtie ailleurs.
#
# ╔═ POURQUOI PORTER LEURS COMMENTAIRES ET PAS SEULEMENT LEURS NOMBRES ═══════════════════════════╗
# ║ Chaque cote de `rig.js` est accompagnée de la raison qui la tient. Sans la raison, un nombre   ║
# ║ recopié est un nombre qu'on « corrigera » un jour au jugé — et la pose de repos partira en     ║
# ║ T-pose, le fusil changera de main, le casque repassera au-dessus de la boîte serveur. Les      ║
# ║ commentaires ci-dessous sont donc la MOITIÉ du port ; les citations entre « … » sont leurs     ║
# ║ phrases exactes, laissées en anglais quand elles portent une mesure.                           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️ PIÈGE A — LATÉRALITÉ : LA DROITE DU PERSONNAGE EST EN X **NÉGATIF** ══════════════════════╗
# ║ Repère main droite, +Y haut, +Z devant : la droite d'un personnage tourné vers +Z est          ║
# ║ droite = avant × haut = +Z × +Y = **−X**. Leur commentaire le dit sans détour :                ║
# ║   « every `*R` bone lives at x < 0. Get this backwards and the rifle ends up in the wrong      ║
# ║     hand. »                                                                                    ║
# ║ Les 9 os `*R` (ClavicleR → ToeR) sont donc TOUS à x < 0. Vérifié un par un sur la table.       ║
# ║                                                                                                ║
# ║ ⚠️⚠️ ET LE PIÈGE DANS LE PIÈGE : `HandL` — la main de SOUTIEN — est **elle aussi** en X        ║
# ║ négatif (x ≈ −0,0968), tout comme `FingersL` (x ≈ −0,1208). Ce n'est pas une faute de signe :   ║
# ║ c'est la main gauche qui TRAVERSE le corps pour tenir le garde-main, parce que l'arme est       ║
# ║ épaulée à droite. Deux os « L » sur neuf sont donc du côté négatif. « Symétriser » la table     ║
# ║ en retournant le signe des os L casse exactement la chose que la pose de repos existe pour      ║
# ║ éviter. `ForearmL` (x ≈ +0,078) est le point de bascule : le coude reste à gauche, la main      ║
# ║ passe à droite.                                                                                ║
# ║ ⚠️ Ce projet a DÉJÀ payé ce piège une fois, dans un autre repère : voir l'avertissement en      ║
# ║ tête de `trench_geometry.gd` (« CE FICHIER A LONGTEMPS ÉCRIT “+X = ma droite”. C'EST FAUX »).   ║
# ║ La règle est la même ici, et `self_check()` la garde en dur.                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️ PIÈGE B — HAUTEUR : LEUR CASQUE DÉPASSE NOTRE BOÎTE SERVEUR ═════════════════════════════╗
# ║ ⛔ CONTRAINTE ABSOLUE DU PROJET : `SILHOUETTE_TOP = 1.80` (`trench_geometry.gd:90`) est la      ║
# ║ boîte de collision du SERVEUR. Elle ne change JAMAIS — c'est la vue qui s'y adapte, jamais      ║
# ║ l'inverse : la cote voyage dans la table angulaire figée (`trench_angles.json`) et la toucher   ║
# ║ imposerait de régénérer les deux copies ET de redéployer le backend.                            ║
# ║ Or leur sommet de casque RENDU est mesuré à **1,8106 m** — un dépassement muet de 10,6 mm :     ║
# ║ le joueur verrait 10 mm de casque que le serveur déclare inatteignable.                         ║
# ║ Le mode d'emploi du recalibrage est plus bas, avec `ECHELLE_CASQUE` et `echelle_modele()`.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️ PIÈGE C — LE COMMENTAIRE MORT « (8 heads) » ═════════════════════════════════════════════╗
# ║ `rig.js:22` déclare `const H = 1.8; // reference height the proportions are authored at        ║
# ║ (8 heads)`. DEUX défauts, et on ne recopie ni l'un ni l'autre :                                 ║
# ║  1. `H` n'est référencé NULLE PART — une seule occurrence dans tout le fichier (grep). C'est    ║
# ║     une constante morte : elle ne contraint rien, elle DÉCRIT (mal) autre chose.                ║
# ║  2. « 8 heads » est FAUX. La tête est cotée 0,244 m de haut (`parts.js:275`, dernière section   ║
# ║     du loft du crâne). 1,8 / 0,244 = **7,38 têtes** ; en prenant le sommet rendu, 1,8106 /      ║
# ║     0,244 = **7,42**. Une tête de plus, c'est 24 cm : personne ne mesure « 8 têtes » ici.       ║
# ║ Le seul rôle honnête du nombre 1,8 dans ce fichier est l'os `HeadTop` (y = 1,8) et notre        ║
# ║ contrainte serveur — deux choses qui se ressemblent par coïncidence, PAS par dérivation.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# CE QUE CE FICHIER NE FAIT PAS (volontairement) : les quaternions de repos (« local +Y runs down
# the bone toward its child »), `rig.js:158-199`. L'orientation n'est nécessaire qu'au moment où on
# skinne ou on passe le squelette à un ragdoll ; la table de positions, elle, est déjà exploitable
# pour bâtir la hiérarchie. Le jour où il faudra les rotations, la recette est aux lignes citées.
# =================================================================================================


# --- Longueurs de segments (pour la hauteur de référence) -----------------------------------------
# Ce sont les DEUX longueurs qui pilotent le solveur de coude. Elles ne sont pas décoratives : le
# coude n'est pas coté dans la table, il est CALCULÉ pour que |épaule→coude| = UPPER_ARM et
# |coude→poignet| = FOREARM exactement (vérifié : les deux bras tombent à 1e-15 près).
const UPPER_ARM := 0.29
const FOREARM := 0.255
# ⚠️ `HAND` est la DEUXIÈME constante morte de `rig.js` (ligne 27, une seule occurrence, comme `H`).
# Sa valeur, elle, est bien utilisée — mais RETAPÉE en littéral dans `alongBore(0.26, 0.095)`. On
# rétablit ici le lien (voir `GRIP_R_DROP`). Si la coïncidence n'en était pas une, on ne perd rien :
# la valeur est identique au bit près ; si c'en était une, on a gagné un nom au lieu d'un 0,095.
const HAND := 0.095

# Longueur du bout d'os d'une FEUILLE (os sans enfant : FingersR/L, ToeR/L, HeadTop). Une feuille
# n'a pas d'enfant vers qui pointer : on lui greffe un moignon de 7,5 cm dans sa direction propre,
# sinon sa longueur vaut 0 et son orientation devient indéfinie.
const LEAF_STUB := 0.075


# --- Le canon, et les mains qui en DÉCOULENT ------------------------------------------------------
# ╔═ LA RELATION DOIT RESTER VRAIE SI LE CANON BOUGE ════════════════════════════════════════════╗
# ║ Chez eux les deux mains ne sont pas cotées : elles sont PROJETÉES sur la ligne de visée par    ║
# ║ `alongBore(t, dropY)` (`rig.js:60-70`). C'est ce qui garantit que la poignée pistolet et le    ║
# ║ garde-main restent sur la MÊME arme : déplacer le canon déplace les deux mains ensemble, et    ║
# ║ le solveur de coude suit derrière. Recopier ici les 6 flottants du résultat, ce serait figer   ║
# ║ une pose juste une seule fois, puis la regarder mentir au premier réglage d'arme.              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Origine de la ligne de visée en pose de repos. x < 0 : le canon est du côté DROIT (piège A).
const BORE_ORIGIN := Vector3(-0.148, 1.398, -0.078)
# Direction BRUTE, avant normalisation : « new THREE.Vector3(0.115, -0.10, 1).normalize() ».
# Elle n'est pas parallèle à +Z : le canon part vers l'extérieur (x > 0 = vers la gauche du
# personnage, donc il rentre vers l'axe du corps depuis son épaule droite) et pique légèrement.
const BORE_DIR_BRUT := Vector3(0.115, -0.10, 1.0)
# ⚠️ `static var` et non `const` : `.normalized()` est un appel de méthode, interdit dans une
# expression constante GDScript. La normalisation reste faite ICI, une fois, au chargement.
static var BORE_DIR: Vector3 = BORE_DIR_BRUT.normalized()

# Paramètres des deux prises, le long du canon. `t` = avancée sur la ligne de visée (mètres depuis
# l'origine), `drop` = combien la main tombe SOUS cette ligne.
#   • main de TIR (poignée pistolet) : 26 cm en avant, une longueur de main sous l'axe ;
#   • main de SOUTIEN (garde-main)   : 45 cm en avant, seulement 5 cm sous l'axe — le garde-main
#     se tient plus haut et plus loin, c'est ce qui donne la pose « bras tendu » caractéristique.
const GRIP_R_T := 0.26
const GRIP_R_DROP := HAND   # = 0.095, cf. la note sur la constante morte `HAND`
const GRIP_L_T := 0.45
const GRIP_L_DROP := 0.05

# ⚠️ Les deux ancres sont écrites en OPÉRATEURS purs sur des CONSTANTES (ni appel à `along_bore()`,
# ni lecture de `BORE_DIR`) : un initialiseur de `static var` s'exécute au chargement du script, et
# on n'y met aucune dépendance à l'ordre d'initialisation ni à une fonction du même script.
# La formule reste celle de `along_bore()` — et comme les deux chemins de calcul sont désormais
# INDÉPENDANTS, `self_check()` les compare : c'est une mesure, pas une promesse en commentaire.
static var GRIP_R: Vector3 = BORE_ORIGIN + BORE_DIR_BRUT.normalized() * GRIP_R_T - Vector3(0.0, GRIP_R_DROP, 0.0)
static var GRIP_L: Vector3 = BORE_ORIGIN + BORE_DIR_BRUT.normalized() * GRIP_L_T - Vector3(0.0, GRIP_L_DROP, 0.0)


# --- Épaules et vecteurs-pôles --------------------------------------------------------------------
# Les deux épaules sont symétriques (±0,172) — ce sont les seuls os du haut du corps à l'être, parce
# que c'est en AVAL de l'épaule que l'arme brise la symétrie.
const SHOULDER_R := Vector3(-0.172, 1.425, 0.004)
const SHOULDER_L := Vector3(0.172, 1.425, 0.004)
# Vecteur-pôle = « de quel côté le coude se plie ». Il n'a pas besoin d'être normalisé ni
# perpendiculaire : le solveur n'en garde que la composante orthogonale à l'axe épaule→poignet.
#   • Droite (-0.35, -1, -0.45) : coude BAS, en ARRIÈRE (z < 0) et vers l'extérieur droit (x < 0)
#     → le coude serré et reculé de la crosse en poche d'épaule.
#   • Gauche (0.55, -1, -0.2) : coude BAS et franchement vers l'extérieur gauche (x > 0)
#     → le coude « ouvert » du bras de soutien, alors même que la main, elle, traverse à droite.
const POLE_R := Vector3(-0.35, -1.0, -0.45)
const POLE_L := Vector3(0.55, -1.0, -0.2)

# Directions explicites des FEUILLES de doigts. Elles ne servent pas qu'à placer l'os : elles lui
# donnent aussi son axe (une feuille n'a pas d'enfant pour le lui donner). Les deux pointent vers
# l'AVANT (+Z ≈ 0,9) et vers le BAS : les doigts s'enroulent en avant et en dessous de la prise.
# ⚠️ Le x de `FingersR` est POSITIF (+0,30) alors que l'os est du côté droit : c'est une direction
# LOCALE ajoutée à `HandR` (x < 0), pas une position. Le résultat reste à x < 0.
const FINGERS_R_DIR := Vector3(0.30, -0.35, 0.89)
const FINGERS_L_DIR := Vector3(-0.32, -0.30, 0.90)

# Hauteur des yeux de la référence (`rig.js:218`, `this.eyeHeight = 1.665`). Notre projet a sa
# propre cote (`EYE_UP = 1.70`, `trench_geometry.gd:84`) qui est celle du JOUEUR et qui pilote la
# caméra : les deux n'ont pas à être égales, mais l'écart de 3,5 cm est à connaître avant de
# fabriquer une pose « il me regarde dans les yeux ». Après recalibrage : 1,665 × ECHELLE = 1,6553.
const EYE_HEIGHT_REF := 1.665


# --- ⚠️ PIÈGE B : le recalibrage de hauteur -------------------------------------------------------
# ╔═ D'OÙ SORTENT CES TROIS NOMBRES (vérifiés dans le source, pas repris d'un brief) ════════════╗
# ║ • `HAUTEUR_BOITE` = `SILHOUETTE_TOP` de `trench_geometry.gd:90`. Intouchable.                  ║
# ║ • `SOMMET_CASQUE_CALCULE` = os `Head` (y = 1,552, table ci-dessous)                            ║
# ║      + `cy = by + 0.100` — « shell centre (just above the brow) », `parts.js:481`               ║
# ║      + `ry = 0.158` — demi-hauteur de la coque, `parts.js:482`                                  ║
# ║   = 1,552 + 0,100 + 0,158 = **1,8100** pile. Le loft de la coque monte de `cy` à `cy + ry`      ║
# ║   (`phi` de 90° à 180°, `y = -cos(phi) * ry`) : la couronne EST le point haut.                  ║
# ║ • `SOMMET_CASQUE_RENDU` = 1,8106 : le sommet MESURÉ au rendu. Les 0,6 mm d'écart avec le        ║
# ║   calcul ne sont pas une erreur d'arrondi — c'est le bruit de surface :                         ║
# ║   `displace(shell, (x,y,z) => nz.fbm3(x*40, y*40, z*40, 3) * 0.0016)` (`parts.js:509`) pousse   ║
# ║   chaque sommet de la coque jusqu'à ±1,6 mm le long de sa normale. On calibre donc sur le       ║
# ║   RENDU (1,8106), jamais sur le calcul : c'est le rendu que le joueur vise.                     ║
# ║   ⚠️ Corollaire : le bruit étant pseudo-aléatoire, un autre germe peut monter jusqu'à 1,8116.   ║
# ║   Calibrer sur 1,8106 laisse donc ~1 mm de marge théorique à surveiller si le germe change.     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ⚠️ LE REGISTRE DE COTES EST LU, PAS RECOPIÉ.
# Première version : `HAUTEUR_BOITE := 1.80` en littéral local, « pour que l'arithmétique de
# constantes reste locale », avec un point 0 de `self_check()` chargé de le comparer au registre.
# C'est une garde honnête, mais elle rend le défaut DÉTECTABLE au lieu de le rendre IMPOSSIBLE —
# et elle ne mord que si quelqu'un appelle `self_check()`. Le §8.148 a coûté une session à cause
# d'une seconde source de vérité qui divergeait en silence ; on n'en ouvre pas une nouvelle pour
# économiser une indirection. La garde reste malgré tout : elle attrape désormais l'autre moitié
# du problème — un `SOMMET_CASQUE_RENDU` qui dériverait du modèle réel.
# le 1,80 ci-dessous est écrit en littéral pour que toute l'arithmétique de constantes reste locale,
# et c'est un test — pas un commentaire — qui garantit qu'il n'a pas dérivé du registre.
const Geo := preload("res://scripts/game/trench_geometry.gd")
const HAUTEUR_BOITE: float = Geo.SILHOUETTE_TOP   # la boîte serveur, NE CHANGE JAMAIS
const SOMMET_CASQUE_CALCULE := 1.8100
const SOMMET_CASQUE_RENDU := 1.8106
# Facteur d'échelle du MODÈLE. Valeur exacte : 0.9941455870981996 (dérivée, pas recopiée).
const ECHELLE_CASQUE := HAUTEUR_BOITE / SOMMET_CASQUE_RENDU

# ╔═ ⚠️ LE FACTEUR PORTE SUR LE MODÈLE ENTIER, PAS SUR L'OS `HeadTop` ═══════════════════════════╗
# ║ Descendre le seul os `HeadTop` de 1,8 à 1,79 ne servirait À RIEN : la coque du casque est      ║
# ║ maillée par rapport à l'os `Head` (`cy = Head.y + 0.100`), pas par rapport à `HeadTop`, qui    ║
# ║ n'est même pas cité par `parts.js`. Le casque descendrait de 0 mm et l'os mentirait en plus.   ║
# ║ Le recalibrage se pose donc là où eux posent déjà leur échelle : sur la RACINE du modèle       ║
# ║ (`agent.js:117`, `this.group.scale.setScalar(this.scale)`), ce qui met à l'échelle les os ET   ║
# ║ le maillage ensemble. Côté Godot : `scale` du `Node3D` racine, ou `resolved_bones(ECHELLE_…)`  ║
# ║ POUR LES OS **plus** la même échelle sur le maillage. Jamais l'un sans l'autre.                 ║
# ║                                                                                                ║
# ║ ⚠️⚠️ ET L'ÉCHELLE PAR VARIANTE DOIT ÊTRE SUPPRIMÉE — pas seulement « compensée ».              ║
# ║ Leurs variantes portent une échelle uniforme : `vanguard` 1.0, `irregular` 0.985, `breacher`   ║
# ║ **1.025** (`soldier.js:166`), appliquée à la racine du groupe. Le breacher culmine donc à       ║
# ║ 1,8106 × 1,025 = **1,8559 m** : 55,9 mm au-dessus de la boîte, pas 10,6. Un cinquième de tête  ║
# ║ de casque hors du monde du serveur — sur la variante la plus voyante.                          ║
# ║ Or « compenser » une échelle UNIFORME, c'est exactement l'annuler : `echelle_modele(1.025)`     ║
# ║ rend ECHELLE_CASQUE / 1.025, et le breacher redevient de la taille des autres. Il n'y a pas    ║
# ║ de troisième option tant que la boîte est unique : DEUX silhouettes de hauteurs différentes    ║
# ║ ne peuvent pas partager une boîte de 1,80 m sans que l'une des deux mente au joueur.           ║
# ║ ✅ Ce qui reste permis, et c'est là que va la différence de silhouette : `bulk` (1.0 / 0.94 /   ║
# ║ 1.06, `soldier.js:123-165`), qui épaissit le torse (`P.jacketTorso(nz, { bulk: V.bulk })`,     ║
# ║ `soldier.js:226`) SANS toucher à la hauteur. Un breacher plus MASSIF, pas plus GRAND.          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func echelle_modele(variant_scale: float = 1.0) -> float:
	# Échelle à appliquer à la racine du modèle pour qu'une variante d'échelle `variant_scale`
	# culmine EXACTEMENT à 1,80 m. Rend `ECHELLE_CASQUE` pour 1.0, et annule toute autre valeur.
	if variant_scale <= 0.0:
		push_warning("[trench_rig] echelle_modele: variant_scale <= 0, replié sur 1.0")
		variant_scale = 1.0
	return HAUTEUR_BOITE / (SOMMET_CASQUE_RENDU * variant_scale)


# =================================================================================================
# LA TABLE DES 25 OS
# =================================================================================================
# ╔═ LA POSE DE REPOS N'EST PAS UNE T-POSE, ET C'EST DÉLIBÉRÉ ═══════════════════════════════════╗
# ║ « The bind pose is not a T-pose. It is a genuine patrol carry — stock in the right shoulder    ║
# ║   pocket, support hand on the handguard — which means the geometry is modelled where the       ║
# ║   limbs actually are and the skin weights never have to survive a 90 degree shoulder           ║
# ║   rotation. » (`rig.js:14-17`)                                                                 ║
# ║ Conséquence pratique : on ne « redresse » JAMAIS cette table pour la rendre jolie dans un      ║
# ║ éditeur. Les bras pliés SONT la donnée ; les déplier revient à demander au skinning de tenir   ║
# ║ une rotation d'épaule de 90°, exactement ce que la pose évite.                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Schéma d'une entrée (Dictionary) :
#   "name"      : String  — nom d'os, IDENTIQUE à la référence (c'est le contrat avec l'animation)
#   "parent"    : String  — nom du parent, "" pour la racine (`Hips`)
#   "pos"       : Vector3 — position de repos en ESPACE ACTEUR (pieds à y = 0), en mètres.
#                           ABSENTE pour les os dérivés et les feuilles (voir ci-dessous).
#   "derived"   : String  — l'os est CALCULÉ : "ELBOW_R"/"ELBOW_L" (solveur) ou "GRIP_R"/"GRIP_L"
#                           (projection sur le canon). Sa position n'existe qu'à l'exécution.
#   "leaf_dir"  : Vector3 — feuille sans position : accrochée au PARENT, à `LEAF_STUB` dans cette
#                           direction (normalisée). Sert AUSSI d'axe de l'os.
#   "up"        : Vector3 — indice d'orientation (leur 4ᵉ champ). Non utilisé pour la position ;
#                           conservé parce qu'il sera nécessaire au calcul des rotations de repos.
#
# ⚠️ Un `const` Dictionary/Array est en LECTURE SEULE à l'exécution en Godot 4 : `resolved_bones()`
# duplique chaque entrée avant d'y écrire. Modifier une entrée en place lèverait une erreur.
# ⚠️ ORDRE : chaque parent apparaît AVANT ses enfants. `resolved_bones()` en dépend (résolution en
# une seule passe) et `self_check()` le vérifie.
const BONES := [
	# --- Colonne vertébrale : rigoureusement centrée (x = 0), le z serpente de ±12 mm ------------
	# Ce micro-serpentement (−0,005 → −0,012 → 0 → +0,006 → −0,008 → +0,004) est la cambrure : ni
	# le dos ni la nuque ne sont des colonnes droites. À x = 0 près, c'est le seul os du modèle
	# que la latéralité n'affecte pas — donc le seul endroit où une erreur de signe ne se voit pas.
	{"name": "Hips",     "parent": "",       "pos": Vector3(0.0, 0.980, -0.005)},
	{"name": "Spine",    "parent": "Hips",   "pos": Vector3(0.0, 1.090, -0.012)},
	{"name": "Spine1",   "parent": "Spine",  "pos": Vector3(0.0, 1.215, 0.000)},
	{"name": "Spine2",   "parent": "Spine1", "pos": Vector3(0.0, 1.345, 0.006)},
	{"name": "Neck",     "parent": "Spine2", "pos": Vector3(0.0, 1.475, -0.008)},
	{"name": "Head",     "parent": "Neck",   "pos": Vector3(0.0, 1.552, 0.004)},
	# ⚠️ `HeadTop` à y = 1,8 : c'est l'os, PAS le sommet rendu. Le crâne nu monte à 1,552 + 0,244 =
	# 1,796 et le casque à 1,8106 (piège B). L'os tombe entre les deux, il ne mesure ni l'un ni
	# l'autre — ne jamais s'en servir comme jauge de taille.
	{"name": "HeadTop",  "parent": "Head",   "pos": Vector3(0.0, 1.800, 0.012)},

	# --- Bras DROIT — le bras d'ARME. Tout est à x < 0 (piège A) ---------------------------------
	# La clavicule n'est qu'à 38 mm de l'axe, l'épaule à 172 mm : c'est la clavicule qui porte
	# l'épaule vers l'extérieur, pas Spine2.
	{"name": "ClavicleR", "parent": "Spine2",    "pos": Vector3(-0.038, 1.408, 0.016)},
	{"name": "UpperArmR", "parent": "ClavicleR", "pos": SHOULDER_R},
	# Coude DÉRIVÉ (jamais coté) : ~(−0,222, 1,140, −0,009). Il est plus BAS que le poignet
	# (1,140 < 1,277) et plus en ARRIÈRE (z < 0) que l'épaule : le coude est tombé et reculé sous
	# l'aisselle. C'est cette pose-là qui fait lire « crosse épaulée » à 35 m, pas le maillage.
	{"name": "ForearmR",  "parent": "UpperArmR", "derived": "ELBOW_R"},
	# Poignet = poignée pistolet, projetée sur le canon.
	{"name": "HandR",     "parent": "ForearmR",  "derived": "GRIP_R"},
	{"name": "FingersR",  "parent": "HandR",     "leaf_dir": FINGERS_R_DIR},

	# --- Bras GAUCHE — le bras de SOUTIEN. Il TRAVERSE (piège A) ---------------------------------
	{"name": "ClavicleL", "parent": "Spine2",    "pos": Vector3(0.038, 1.408, 0.016)},
	{"name": "UpperArmL", "parent": "ClavicleL", "pos": SHOULDER_L},
	# Coude DÉRIVÉ : ~(+0,078, 1,230, +0,197). Encore à gauche (x > 0) mais déjà rentré vers l'axe,
	# et poussé de 19 cm vers l'AVANT : le bras est tendu vers le garde-main.
	{"name": "ForearmL",  "parent": "UpperArmL", "derived": "ELBOW_L"},
	# ⚠️⚠️ ICI le x devient NÉGATIF (~−0,097) : la main gauche est passée du côté DROIT du corps.
	# C'est le cœur du piège A. Un « correctif de symétrie » sur cette ligne met le fusil dans la
	# mauvaise main sans qu'aucun test de compilation ne bronche.
	{"name": "HandL",     "parent": "ForearmL",  "derived": "GRIP_L"},
	{"name": "FingersL",  "parent": "HandL",     "leaf_dir": FINGERS_L_DIR},

	# --- Jambes — les seules chaînes VRAIMENT symétriques (l'arme ne les concerne pas) -----------
	# L'écartement s'ouvre légèrement en descendant (92 → 98 → 103 mm) : les pieds sont plus
	# écartés que les hanches, posture stable. Le pied recule (z = −0,022) et l'orteil avance
	# (z = +0,108) : 13 cm de pied, l'axe du pied pointe vers l'avant.
	{"name": "UpLegR", "parent": "Hips",  "pos": Vector3(-0.092, 0.945, 0.000)},
	{"name": "LegR",   "parent": "UpLegR", "pos": Vector3(-0.098, 0.505, 0.020)},
	# `up` = +Y sur les pieds/orteils : sans cet indice, l'axe de l'os (quasi horizontal pour
	# l'orteil) et l'indice par défaut (+Z) seraient presque colinéaires → base dégénérée.
	{"name": "FootR",  "parent": "LegR",  "pos": Vector3(-0.103, 0.088, -0.022), "up": Vector3(0.0, 1.0, 0.0)},
	{"name": "ToeR",   "parent": "FootR", "pos": Vector3(-0.103, 0.030, 0.108),  "up": Vector3(0.0, 1.0, 0.0)},

	{"name": "UpLegL", "parent": "Hips",  "pos": Vector3(0.092, 0.945, 0.000)},
	{"name": "LegL",   "parent": "UpLegL", "pos": Vector3(0.098, 0.505, 0.020)},
	{"name": "FootL",  "parent": "LegL",  "pos": Vector3(0.103, 0.088, -0.022), "up": Vector3(0.0, 1.0, 0.0)},
	{"name": "ToeL",   "parent": "FootL", "pos": Vector3(0.103, 0.030, 0.108),  "up": Vector3(0.0, 1.0, 0.0)},
]


# =================================================================================================
# LE SOLVEUR DE COUDE (port de `solveElbow`, `rig.js:33-47`)
# =================================================================================================
# Deux os, un vecteur-pôle. On connaît l'épaule `s`, le poignet `w` et les deux longueurs ; le coude
# est à l'intersection de deux sphères — un CERCLE — et le pôle choisit le point sur ce cercle.
#   a = (l1² − l2² + d²) / 2d  : distance épaule→projection du coude sur l'axe épaule-poignet
#   h = √(l1² − a²)            : rayon du cercle des coudes possibles
# ⚠️ `d` est BORNÉ à [ |l1−l2| + 1e-4 , l1+l2 − 1e-4 ] : hors de cet intervalle le triangle
# n'existe pas (bras trop tendu ou trop replié) et `h` deviendrait imaginaire. La borne empêche le
# NaN — elle ne rapproche PAS le poignet : si la cible est hors d'atteinte, l'avant-bras ne
# l'atteint pas, et c'est au poignet d'être corrigé, pas au solveur de mentir.
# ✅ Sur NOS deux bras aucun bornage ne se déclenche (|épaule→poignet| = 0,235 m à droite et
# 0,468 m à gauche, pour une allonge de 0,545 m) : les longueurs de segments sortent EXACTES.
static func solve_elbow(s: Vector3, w: Vector3, l1: float, l2: float, pole: Vector3) -> Vector3:
	var axis := w - s
	# Longueur mesurée AVANT normalisation (comme chez eux), puis bornée.
	var d := clampf(axis.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	# ⚠️ `normalized()` d'un vecteur nul rend Vector3.ZERO en Godot (pas d'erreur, pas de NaN) :
	# épaule et poignet confondus donneraient un coude à la position de l'épaule. Cas absent ici.
	axis = axis.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, l1 * l1 - a * a))
	var p := pole.normalized()
	# Composante du pôle PERPENDICULAIRE à l'axe de l'os — « component of the pole perpendicular to
	# the bone axis ». C'est pour ça que le pôle n'a besoin d'être ni exact ni normalisé : seule
	# sa direction transverse compte.
	var perp := p - axis * p.dot(axis)
	if perp.length_squared() < 1e-8:
		# Repli quand le pôle est colinéaire à l'os : on reprend « vers le bas » et on lui retire à
		# son tour sa composante axiale. ⚠️ L'original écrit ce retrait en double négation
		# (`addScaledVector(axis, -axis.y * -1)`), ce qui EST correct — `dot((0,−1,0), axis) =
		# −axis.y`, donc retirer `axis · (−axis.y)` revient à ajouter `axis · axis.y` — mais se lit
		# comme une faute de signe. Écrit ici en clair.
		perp = Vector3(0.0, -1.0, 0.0) + axis * axis.y
	perp = perp.normalized()
	return s + axis * a + perp * h


# Point sur la ligne de visée : `t` mètres en avant de l'origine, `drop_y` mètres sous l'axe.
# Port de `alongBore` (`rig.js:60-66`). Sert aux prises, et à tout ce qui doit rester solidaire du
# canon (bouche à feu, hausse, point d'attache de bretelle).
static func along_bore(t: float, drop_y: float) -> Vector3:
	return BORE_ORIGIN + BORE_DIR * t - Vector3(0.0, drop_y, 0.0)


# --- Coudes : résolus une fois, mémorisés ---------------------------------------------------------
# ⚠️ Pourquoi une fonction et pas une `static var` : l'initialiseur d'une `static var` tourne au
# chargement du script, et y appeler une fonction statique du MÊME script ajoute une dépendance à
# l'ordre d'initialisation dont ce projet n'a aucun précédent. On garde le motif déjà utilisé
# ailleurs ici (`combat_odds.gd` : mémo + drapeau statique), qui, lui, est éprouvé.
static var _elbows_solved := false
static var _elbow_r := Vector3.ZERO
static var _elbow_l := Vector3.ZERO

static func _solve_elbows() -> void:
	if _elbows_solved:
		return
	_elbows_solved = true
	_elbow_r = solve_elbow(SHOULDER_R, GRIP_R, UPPER_ARM, FOREARM, POLE_R)
	_elbow_l = solve_elbow(SHOULDER_L, GRIP_L, UPPER_ARM, FOREARM, POLE_L)

static func elbow_r() -> Vector3:
	_solve_elbows()
	return _elbow_r

static func elbow_l() -> Vector3:
	_solve_elbows()
	return _elbow_l

# Résout une ancre par son nom (les valeurs de la clé "derived" de la table).
static func anchor(key: String) -> Vector3:
	match key:
		"GRIP_R":
			return GRIP_R
		"GRIP_L":
			return GRIP_L
		"ELBOW_R":
			return elbow_r()
		"ELBOW_L":
			return elbow_l()
	push_warning("[trench_rig] ancre inconnue: %s" % key)
	return Vector3.ZERO


# =================================================================================================
# TABLE RÉSOLUE — c'est CE QUE consomme le constructeur de squelette
# =================================================================================================
# Rend les 25 os avec une position CONCRÈTE pour chacun (dérivées calculées, feuilles greffées) et
# les index parent, prêts pour `Skeleton3D.add_bone()` / `set_bone_parent()` ou pour une hiérarchie
# de `Node3D`. Chaque entrée est une COPIE : la table `const` reste intacte.
#
# `uniform_scale` : échelle du modèle. ⚠️ Passer `ECHELLE_CASQUE` ici ne suffit PAS à respecter la
# boîte serveur — il faut la MÊME échelle sur le maillage (cf. piège B). Le défaut est 1.0 pour que
# la table rendue soit comparable telle quelle à la référence.
static func resolved_bones(uniform_scale: float = 1.0) -> Array[Dictionary]:
	# ⚠️ `BONES[i]` est un Variant : `:=` ne peut pas en inférer le type ("Cannot infer the type").
	var index_of: Dictionary = {}
	for i in BONES.size():
		var head: Dictionary = BONES[i]
		index_of[head["name"]] = i

	var out: Array[Dictionary] = []
	var placed: Dictionary = {}   # nom -> Vector3 NON mise à l'échelle (base des feuilles)
	for i in BONES.size():
		var spec: Dictionary = BONES[i]
		var bone: Dictionary = spec.duplicate()   # la `const` est en lecture seule
		var bone_name: String = spec["name"]
		var parent_name: String = spec["parent"]
		var pos := Vector3.ZERO
		if spec.has("pos"):
			pos = spec["pos"]
		elif spec.has("derived"):
			var key: String = spec["derived"]
			pos = anchor(key)
		elif spec.has("leaf_dir"):
			# Feuille : « hang it off the parent » — la position part du PARENT, pas de l'os.
			var base: Vector3 = placed.get(parent_name, Vector3.ZERO)
			var dir: Vector3 = spec["leaf_dir"]
			pos = base + dir.normalized() * LEAF_STUB
		else:
			push_warning("[trench_rig] os sans position ni dérivation: %s" % bone_name)
		placed[bone_name] = pos
		bone["pos"] = pos * uniform_scale
		bone["index"] = i
		bone["parent_index"] = int(index_of.get(parent_name, -1))
		out.append(bone)
	return out


# Index d'un os par son nom, -1 si inconnu. (Leur `index()` lève une exception ; on rend -1 : une
# exception GDScript n'existe pas, et un `assert` FIGE Godot en headless.)
static func bone_index(bone_name: String) -> int:
	for i in BONES.size():
		var spec: Dictionary = BONES[i]
		if spec["name"] == bone_name:
			return i
	return -1


# =================================================================================================
# CONTRÔLE DE COHÉRENCE — sans `assert` (un assert échoué BLOQUE Godot en headless)
# =================================================================================================
# Rend la liste des anomalies. VIDE = tout va bien. À appeler depuis une sonde ou un test ; ne
# jamais s'en servir pour « réparer » silencieusement quoi que ce soit.
# ⚠️ Formatage : `%e` N'EXISTE PAS en GDScript (la chaîne sort BRUTE, sans erreur visible) —
# uniquement `%s`, `%d`, `%f` et `%.Nf` ici.

# Un bras : le solveur doit avoir rendu EXACTEMENT UPPER_ARM puis FOREARM. Si l'une des deux
# longueurs dérive, c'est que le bornage de `d` s'est déclenché — donc que le poignet est hors
# d'atteinte de l'épaule, et que le coude a été posé sans jamais rejoindre la main.
# (Fonction séparée : une `PackedStringArray` passée en argument serait COPIÉE, pas modifiée.)
static func _check_arm(label: String, sh: Vector3, el: Vector3, wr: Vector3) -> PackedStringArray:
	var e := PackedStringArray()
	var upper := sh.distance_to(el)
	var fore := el.distance_to(wr)
	if absf(upper - UPPER_ARM) > 1e-6:
		e.append("bras %s: |épaule-coude| = %.6f (attendu %.6f)" % [label, upper, UPPER_ARM])
	if absf(fore - FOREARM) > 1e-6:
		e.append("bras %s: |coude-poignet| = %.6f (attendu %.6f)" % [label, fore, FOREARM])
	return e


static func self_check() -> PackedStringArray:
	var errs := PackedStringArray()
	var bones := resolved_bones()

	if bones.size() != 25:
		errs.append("nombre d'os = %d (attendu 25)" % bones.size())

	# 0. ⛔ La boîte serveur est LUE (`Geo.SILHOUETTE_TOP`), donc l'égalité est vraie par
	# construction — ce contrôle-ci ne peut plus échouer, et c'est exactement ce qu'on voulait :
	# le défaut est devenu impossible au lieu d'être détectable. On le garde comme TÉMOIN, pour
	# que la ligne rougisse si quelqu'un remettait un littéral un jour.
	var top_registre := float(Geo.SILHOUETTE_TOP)
	if absf(HAUTEUR_BOITE - top_registre) > 1e-9:
		errs.append("HAUTEUR_BOITE = %.4f mais trench_geometry.SILHOUETTE_TOP = %.4f — recalculer ECHELLE_CASQUE" % [HAUTEUR_BOITE, top_registre])

	# 1. Hiérarchie : noms uniques, parent déclaré AVANT l'enfant, une seule racine.
	var seen: Dictionary = {}
	var roots := 0
	for b in bones:
		var n: String = b["name"]
		if seen.has(n):
			errs.append("os en double: %s" % n)
		seen[n] = true
		var pi: int = b["parent_index"]
		if pi < 0:
			roots += 1
			if n != "Hips":
				errs.append("racine inattendue: %s" % n)
		elif pi >= int(b["index"]):
			errs.append("%s: parent déclaré APRÈS l'enfant (résolution en une passe cassée)" % n)
	if roots != 1:
		errs.append("nombre de racines = %d (attendu 1)" % roots)

	# 2. ⚠️ PIÈGE A — latéralité. Les 9 os `*R` à x < 0 ; les os `*L` à x > 0 SAUF `HandL` et
	# `FingersL`, qui traversent pour tenir le garde-main. Cette liste d'exceptions est la
	# connaissance qu'on ne veut pas reperdre : elle est ici, en dur, et elle échoue si on
	# « symétrise » la table.
	var croisent := ["HandL", "FingersL"]
	for b in bones:
		var n: String = b["name"]
		var p: Vector3 = b["pos"]
		if n.ends_with("R"):
			if p.x >= 0.0:
				errs.append("PIÈGE A: %s est à x = %.4f (>= 0) — la droite est en X NÉGATIF" % [n, p.x])
		elif n.ends_with("L"):
			if croisent.has(n):
				if p.x >= 0.0:
					errs.append("PIÈGE A: %s devrait TRAVERSER (x < 0), trouvé x = %.4f" % [n, p.x])
			elif p.x <= 0.0:
				errs.append("PIÈGE A: %s est à x = %.4f (<= 0)" % [n, p.x])

	# 3. Les ancres inline valent bien `along_bore()` (la promesse du commentaire, mesurée).
	if GRIP_R.distance_to(along_bore(GRIP_R_T, GRIP_R_DROP)) > 1e-9:
		errs.append("GRIP_R diverge de along_bore()")
	if GRIP_L.distance_to(along_bore(GRIP_L_T, GRIP_L_DROP)) > 1e-9:
		errs.append("GRIP_L diverge de along_bore()")

	# 4. Le solveur a bien respecté les longueurs de segments (sinon le bornage s'est déclenché).
	errs.append_array(_check_arm("droit", SHOULDER_R, elbow_r(), GRIP_R))
	errs.append_array(_check_arm("gauche", SHOULDER_L, elbow_l(), GRIP_L))

	# 5. ⚠️ PIÈGE B — la boîte serveur. On teste le SOMMET RENDU recalibré, JAMAIS l'os `HeadTop`
	# (qui, lui, est à 1,8 et passerait toujours — c'est précisément le faux vert à éviter).
	if SOMMET_CASQUE_RENDU * ECHELLE_CASQUE > HAUTEUR_BOITE + 1e-9:
		errs.append("PIÈGE B: casque recalibré à %.4f m > %.2f m" % [SOMMET_CASQUE_RENDU * ECHELLE_CASQUE, HAUTEUR_BOITE])
	# Et la compensation tient pour LEURS trois échelles de variante (1.0 / 0.985 / 1.025) : quelle
	# que soit l'échelle demandée, `echelle_modele()` doit ramener le sommet à 1,80 m pile — c'est
	# la preuve mesurée que « compenser une échelle uniforme » revient bien à la supprimer.
	var echelles := PackedFloat64Array([1.0, 0.985, 1.025])
	for s in echelles:
		var top := SOMMET_CASQUE_RENDU * echelle_modele(s) * s
		if absf(top - HAUTEUR_BOITE) > 1e-9:
			errs.append("PIÈGE B: échelle de variante %.3f -> sommet %.6f m (attendu %.2f)" % [s, top, HAUTEUR_BOITE])

	# 6. Aucun os sous le sol. ⚠️ « feet on y = 0 » parle de la SEMELLE (maillage), pas d'un os :
	# l'os le plus bas de la table est l'orteil, à y = 0,030. Aucun os ne touche donc y = 0, et
	# chercher à en caler un dessus déformerait le pied.
	for b in bones:
		var p2: Vector3 = b["pos"]
		if p2.y < 0.0:
			errs.append("%s sous le sol (y = %.4f)" % [b["name"], p2.y])

	return errs
