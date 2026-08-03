extends RefCounted
# =================================================================================================
# LA TRANCHÉE FP (§8.138) — LE CONTRAT DE NOMMAGE des personnages peints + la MACHINE À FRAMES.
#
# Module 100 % STATIQUE, sans état de jeu : il ne connaît ni le duel, ni le réseau, ni la 3D. Deux
# consommateurs, une seule table :
#   • `trench_fp_world.gd`   — le soldat adverse (`Sprite3D` billboard dans le SubViewport 3D) ;
#   • `trench_viewmodel.gd`  — les mains + l'arme (couche 2D en bas-droite de l'écran).
#
# ╔═ POURQUOI CE FICHIER EXISTE ══════════════════════════════════════════════════════════════════╗
# ║ Le nommage EST le contrat (doctrine maison, cf. `company_emblems.gd` §8.126 et les décors      ║
# ║ `pose_*.png` §8.137) : Hakim dépose un PNG, le jeu le prend à chaud, AUCUNE ligne à recoder.   ║
# ║ Si la convention vivait en double (une copie côté soldat, une copie côté viewmodel), une       ║
# ║ divergence d'un caractère produirait un repli SILENCIEUX — le pire des symptômes, parce qu'il  ║
# ║ ressemble à « l'asset n'est pas encore fait ». Elle vit donc ICI, et nulle part ailleurs.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# LES FICHIERS ATTENDUS (`GUIDE_PRODUCTION_TRANCHEE.md` étapes 3 et 4) :
#   assets/images/trench/sprites/enemy_{idle|aim|throw|hit|death_a|death_b}.png   (6)
#   assets/images/trench/sprites/vm_{vipere|frelon|chacal|condor}_{idle|fire|reload}.png  (12)
# PNG **avec alpha** (détourage rembg), uniforme GRIS NEUTRE pour le soldat : la teinte de faction
# est appliquée EN JEU, sans quoi il faudrait repeindre 6 images par faction.
# =================================================================================================

const SPRITE_DIR := "res://assets/images/trench/sprites/"

# --- LE SOLDAT ADVERSE ---------------------------------------------------------------------------
# L'état de repli ABSOLU. Deux rôles : c'est la frame ambiante, et c'est le TÉMOIN du mode sprite
# (`enemy_available()`) — un jeu de sprites sans `enemy_idle.png` n'est pas un jeu de sprites.
const ENEMY_IDLE := "idle"
const ENEMY_AIM := "aim"

# LE REGISTRE : état -> {durée en secondes, état suivant}.
#   • `duration = 0` = état STATIQUE : il dure tant que la condition qui l'a levé dure.
#   • `next` ne sert qu'aux CHAÎNES réelles (`death_a` -> `death_b`) ; un état transitoire échu
#     rend la main à l'état AMBIANT (`ambient_state`), qui est la seule vérité du moment.
const ENEMY_FRAMES := {
	"idle": {"duration": 0.0, "next": ""},
	"aim": {"duration": 0.0, "next": ""},
	"throw": {"duration": 0.45, "next": "idle"},
	"hit": {"duration": 0.25, "next": "idle"},
	"death_a": {"duration": 0.40, "next": "death_b"},
	"death_b": {"duration": 0.0, "next": ""},
}
# Les états déclenchés par un ÉVÉNEMENT (et non par une lecture d'état) : ils s'imposent pendant
# leur durée. `hit` interrompt tout sauf la mort ; `throw` ne coupe PAS un `hit` en cours.
const ENEMY_TRANSIENT := ["throw", "hit"]
const ENEMY_DEATH_FIRST := "death_a"

# ÉCHELLE — LE réglage critique du lot. 1024 px de haut <-> 1,80 m dans le monde du blockout
# (`trench_geometry.SILHOUETTE_TOP`, le sommet du crâne d'un soldat debout).
#
# ⚠️ `pixel_size` est une CONSTANTE, pas une normalisation par texture : c'est ce qui garantit que
# les 6 frames gardent la MÊME échelle entre elles. Une frame de mort livrée moins haute (un corps
# au sol) rend donc un corps AU SOL — et non un cadavre étiré à 1,80 m de haut.
const SPRITE_REFERENCE_PX := 1024.0
const SPRITE_REFERENCE_M := 1.80
const PIXEL_SIZE := SPRITE_REFERENCE_M / SPRITE_REFERENCE_PX

# --- LE VIEWMODEL ---------------------------------------------------------------------------------
const VIEWMODEL_IDLE := "idle"
const VIEWMODEL_STATES := ["idle", "fire", "reload"]

# Cache de résolution (chemin -> Texture2D | null). `null` est une réponse MÉMORISÉE : sans lui, un
# état sans fichier retenterait un `ResourceLoader.exists` à chaque changement de frame.
static var _cache: Dictionary = {}


# Vide le cache — réservé aux harnais de test (un jeu de sprites déposé puis retiré dans le MÊME
# processus). Le jeu, lui, ne rencontre jamais ce cas : les assets sont figés au lancement.
static func clear_cache() -> void:
	_cache.clear()


# ⚠️ `ResourceLoader.exists` et SURTOUT PAS `FileAccess.file_exists` : ce dernier échoue en build
# exporté (leçon `company_emblems.gd` §8.126). Le `is Texture2D` derrière ferme le dernier trou —
# un fichier présent mais non importé ne doit pas rendre un objet inutilisable au reste du code.
static func texture_at(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var found: Texture2D = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			found = res
	_cache[path] = found
	return found


static func enemy_path(state: String) -> String:
	return SPRITE_DIR + "enemy_%s.png" % state


static func viewmodel_path(weapon_id: String, state: String) -> String:
	return SPRITE_DIR + "vm_%s_%s.png" % [weapon_id, state]


# LA RÈGLE DE REPLI DU SOLDAT : fichier absent -> on retombe sur `idle`. Et si `idle` lui-même
# manque, on rend `null` : l'appelant bascule alors INTÉGRALEMENT sur le placeholder en primitives.
# Jamais de mélange sprite/capsule — une capsule à casque au milieu de frames peintes se lirait
# comme un bug d'affichage, pas comme un asset manquant.
static func enemy_texture(state: String) -> Texture2D:
	var found := texture_at(enemy_path(state))
	if found == null and state != ENEMY_IDLE:
		found = texture_at(enemy_path(ENEMY_IDLE))
	return found


static func enemy_available() -> bool:
	return texture_at(enemy_path(ENEMY_IDLE)) != null


# LA RÈGLE DE REPLI DU VIEWMODEL : identique par ARME. Le repli est ici PAR ARME (et non global
# comme pour le soldat) parce que deux armes différentes n'apparaissent JAMAIS à l'écran en même
# temps : le joueur ne peut pas voir une VIPÈRE peinte à côté d'un CONDOR en primitives, donc le
# « mélange » que l'on s'interdit chez le soldat n'existe tout simplement pas ici.
static func viewmodel_texture(weapon_id: String, state: String) -> Texture2D:
	var found := texture_at(viewmodel_path(weapon_id, state))
	if found == null and state != VIEWMODEL_IDLE:
		found = texture_at(viewmodel_path(weapon_id, VIEWMODEL_IDLE))
	return found


static func viewmodel_available(weapon_id: String) -> bool:
	return texture_at(viewmodel_path(weapon_id, VIEWMODEL_IDLE)) != null


# --- LECTURES PURES DU REGISTRE (testables sans un seul nœud) --------------------------------------
static func frame_duration(state: String) -> float:
	var entry: Dictionary = ENEMY_FRAMES.get(state, {})
	return float(entry.get("duration", 0.0))


static func frame_next(state: String) -> String:
	var entry: Dictionary = ENEMY_FRAMES.get(state, {})
	return str(entry.get("next", ""))


static func is_transient(state: String) -> bool:
	return ENEMY_TRANSIENT.has(state)


# L'état AMBIANT du soldat vivant : « il épaule » (drapeau `aiming` du protocole, §8.137) ou rien.
static func ambient_state(aiming: bool) -> String:
	return ENEMY_AIM if aiming else ENEMY_IDLE
