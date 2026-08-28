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

const Geo := preload("res://scripts/game/trench_geometry.gd")

const SPRITE_DIR := "res://assets/images/trench/sprites/"

# --- LE SOLDAT ADVERSE ---------------------------------------------------------------------------
# L'état de repli ABSOLU. Deux rôles : c'est la frame ambiante, et c'est le TÉMOIN du mode sprite
# (`enemy_available()`) — un jeu de sprites sans `enemy_idle.png` n'est pas un jeu de sprites.
const ENEMY_IDLE := "idle"
const ENEMY_AIM := "aim"
# ── §8.153 : LES DEUX IMAGES DE PASSAGE ────────────────────────────────────────────────────────
# `ENEMY_AIM_RISE` sert dans LES DEUX SENS (l arme qui monte, l arme qui redescend) : une pose a
# mi-chemin n a pas de direction, donc une seule image suffit pour deux transitions.
# `ENEMY_FIRE` est la seule image ou l on VOIT l adversaire tirer — jusqu ici son tir ne produisait
# qu une sphere de lueur, et son corps ne bougeait pas d un pixel.
const ENEMY_AIM_RISE := "aim_rise"
const ENEMY_FIRE := "fire"

# LE REGISTRE : état -> {durée en secondes, état suivant, DEBOUT ?}.
#   • `duration = 0` = état STATIQUE : il dure tant que la condition qui l'a levé dure.
#   • `next` ne sert qu'aux CHAÎNES réelles (`death_a` -> `death_b`) ; un état transitoire échu
#     rend la main à l'état AMBIANT (`ambient_state`), qui est la seule vérité du moment.
#   • `standing` = « cette frame montre un homme DEBOUT sur ses pieds ». Voir `pixel_size_for()` —
#     c'est ce drapeau, et lui seul, qui décide comment la frame est mise à l'échelle.
const ENEMY_FRAMES := {
	"idle": {"duration": 0.0, "next": "", "standing": true},
	"aim": {"duration": 0.0, "next": "", "standing": true},
	"throw": {"duration": 0.45, "next": "idle", "standing": true},
	"hit": {"duration": 0.25, "next": "idle", "standing": true},
	# ⚠️ SANS SUITE (`next` vide) = « rends la main a l AMBIANT ». C est ce qui permet a `aim_rise`
	# de servir dans les deux sens sans savoir ou il va : une chaine `aim_rise -> aim` forcerait la
	# pose de visee meme quand le joueur vient de RELACHER sa visee.
	# ⚙ 0,10 s pour la montee (six images a 60 Hz : un passage, pas un clignement) ; 0,14 s pour le
	# tir, qui doit se voir sans retarder le retour a la visee.
	"aim_rise": {"duration": 0.10, "next": "", "standing": true},
	"fire": {"duration": 0.14, "next": "", "standing": true},
	# La CHUTE et le CORPS AU SOL ne sont pas debout : leur cadre décrit une hauteur réelle plus
	# petite, et c'est CETTE hauteur-là qu'il faut rendre.
	"death_a": {"duration": 0.40, "next": "death_b", "standing": false},
	"death_b": {"duration": 0.0, "next": "", "standing": false},
}
# Les états déclenchés par un ÉVÉNEMENT (et non par une lecture d'état) : ils s'imposent pendant
# leur durée. `hit` interrompt tout sauf la mort ; `throw` ne coupe PAS un `hit` en cours.
# ⚠️ `aim_rise` n est PAS dans cette liste : il n est jamais pousse de l exterieur. Il est insere
# par la machine a frames quand elle voit la visee BASCULER — c est un fait qu elle observe, pas
# un acte que l hote lui annonce.
const ENEMY_TRANSIENT := ["throw", "hit", "fire"]
const ENEMY_DEATH_FIRST := "death_a"

# ÉCHELLE — LE réglage critique du lot. 1024 px de haut <-> 1,80 m dans le monde du blockout.
#
# ⚠️ LA HAUTEUR DE RÉFÉRENCE EST LUE DANS LA GÉOMÉTRIE, PAS RECOPIÉE. `SILHOUETTE_TOP` est le
# sommet du crâne d'un soldat DEBOUT dans le registre partagé avec le serveur : c'est la taille à
# laquelle la table angulaire résout les touches. Si un jour cette cote bouge, le soldat peint la
# suit tout seul — sans quoi le joueur tirerait sur une silhouette qui n'a pas la taille de sa
# fenêtre de tir.
const SPRITE_REFERENCE_PX := 1024.0
const SPRITE_REFERENCE_M := Geo.SILHOUETTE_TOP
const PIXEL_SIZE := SPRITE_REFERENCE_M / SPRITE_REFERENCE_PX


# ╔═ ⚠️⚠️ L'ADVERSAIRE RÉTRÉCISSAIT DE 25 cm DÈS QU'IL ÉPAULAIT — MESURÉ, §8.141 ═════════════════╗
# ║ Le `pixel_size` CONSTANT était présenté comme une garantie d'échelle. Il n'en est une que si    ║
# ║ toutes les frames DEBOUT sont livrées à la même hauteur de cadre — ce que le contrat demandait  ║
# ║ (1024 px) et ce que la production n'a pas tenu. Mesure des six frames :                          ║
# ║                                                                                                  ║
# ║   idle 1024 px = 1,800 m ✅ · throw 1023 px = 1,798 m ✅ · hit 1001 px = 1,760 m ✅              ║
# ║   **aim 880 px = 1,547 m ⛔** · death_a 806 px = 1,417 m (chute) · death_b 238 px = 0,418 m      ║
# ║                                                                                                  ║
# ║ `aim` est l'état AMBIANT de tout adversaire qui menace (drapeau `aiming`, §8.137) : c'est donc   ║
# ║ la frame que le joueur voit CHAQUE FOIS QU'IL A QUELQUE CHOSE À VISER. À 12 m, le parapet        ║
# ║ d'en face coupe la silhouette à 1,208 m : la part exposée passait de 0,592 m (idle) à 0,339 m    ║
# ║ (aim), soit **43 % de cible en moins au moment précis où on tire dessus**. Et le soldat          ║
# ║ « s'enfonçait » de 25 cm sous les sacs quand il épaulait, ce qui se lit comme une esquive.        ║
# ║                                                                                                  ║
# ║ ⚠️ On NORMALISE donc les frames DEBOUT à `SILHOUETTE_TOP`, et on GARDE l'échelle constante pour  ║
# ║ celles qui ne le sont pas — c'était la bonne intuition du §8.138, appliquée trop largement : un  ║
# ║ corps au sol doit rendre sa hauteur RÉELLE, un homme debout doit rendre 1,80 m quoi qu'il        ║
# ║ arrive au cadrage de son PNG. Le code cesse de faire confiance à la hauteur du fichier là où     ║
# ║ elle décrit une taille d'HOMME, et lui fait confiance là où elle décrit une POSE.                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func pixel_size_for(state: String, frame_height: int) -> float:
	if frame_height <= 0:
		return PIXEL_SIZE
	if not is_standing(state):
		return PIXEL_SIZE
	return SPRITE_REFERENCE_M / float(frame_height)


static func is_standing(state: String) -> bool:
	var entry: Dictionary = ENEMY_FRAMES.get(state, {})
	return bool(entry.get("standing", true))

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


# Cette frame-la est-elle DEPOSEE sur disque ? ⚠️ `enemy_texture()` replie silencieusement sur
# `idle` quand un fichier manque — un repli juste pour le RENDU, et faux pour la MACHINE : elle
# insererait alors une image de passage qui montre la pose de repos, c est-a-dire un clignotement.
# On lui donne donc de quoi savoir AVANT de decider.
static func has_frame(state: String) -> bool:
	return texture_at(enemy_path(state)) != null


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
