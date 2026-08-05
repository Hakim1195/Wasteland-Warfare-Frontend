extends Control
# =================================================================================================
# LA TRANCHÉE FP (§8.138) — LE VIEWMODEL PEINT : mains + arme, couche 2D à frames.
#
# VUE PURE : aucun réseau, aucune règle, aucune décision. L'hôte (`trench_fp.gd`) pousse une arme,
# un drapeau de rechargement, une valeur de recul et un « j'ai tiré » ; ce script n'en déduit qu'une
# frame et une position. Il ne sait même pas qu'il y a un duel.
#
# ╔═ POURQUOI UNE COUCHE 2D ET NON UN MODÈLE 3D ══════════════════════════════════════════════════╗
# ║ Les décors de LA TRANCHÉE sont PRÉ-RENDUS et peints (img2img FLUX par-dessus le blockout). Un  ║
# ║ viewmodel 3D éclairé en temps réel jurerait avec eux à chaque pose ; un sprite peint sort du   ║
# ║ MÊME pinceau. C'est le parti pris « rétro-FPS à frames » du chantier — et il a l'avantage de   ║
# ║ ne coûter ni géométrie, ni squelette, ni second viewport.                                      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# REPLI : arme sans fichiers -> ce nœud s'efface et le viewmodel en primitives de
# `trench_fp_world.gd` reprend le service POUR CETTE ARME. `set_weapon()` renvoie qui a la main.
# =================================================================================================

const Sprites := preload("res://scripts/game/trench_sprites.gd")

# CADRAGE ⚙ — calqué sur le concept validé : l'arme occupe le coin bas-droit et DÉBORDE légèrement
# de l'écran, comme dans n'importe quel FPS à frames. Le débord est ce qui évite l'effet « autocollant
# posé sur l'image » : une arme entièrement contenue dans le cadre ne se lit pas comme tenue en main.
const HEIGHT_RATIO := 0.45
const BLEED_RIGHT := 0.05
const BLEED_BOTTOM := 0.04

# La frame de tir est BRÈVE ⚙ : au-delà, la cadence du FRELON la ferait clignoter en permanence.
const FIRE_FRAME_TIME := 0.09
# Montée de la nouvelle arme à l'escalade (bas -> haut).
const SWAP_SLIDE_TIME := 0.25
# Recul : l'arme s'enfonce dans le coin et roule légèrement (le tween s'applique à CE nœud 2D).
const RECOIL_KICK_PX := 26.0
const RECOIL_ROLL_DEG := 3.5
# Rechargement : plongée légère, amenée en douceur (pas de saut à l'entrée ni à la sortie).
const RELOAD_DIP_RATIO := 0.08
const RELOAD_DIP_DEG := 4.0
const RELOAD_DIP_SPEED := 7.0

var _rect: TextureRect
var _weapon := ""
var _has_weapon := false
var _sprite_mode := false
var _state := ""
var _fire_left := 0.0
var _shots := 0
var _reloading := false
var _reload_dip := 0.0
var _slide := 0.0
var _recoil := 0.0
var _reduced_motion := false
# §8.141 — le geste de grenade : `_grenade_aim` est l'état demandé, `_grenade_dip` sa progression
# amenée en douceur (0 = arme en main, 1 = arme abaissée / grenade au poing).
var _grenade_aim := false
var _grenade_dip := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect = TextureRect.new()
	# On calcule NOUS-MÊMES la taille (hauteur relative à l'écran, largeur par le ratio de l'image) :
	# le TextureRect se contente donc de remplir la boîte qu'on lui donne.
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


# =================================================================================================
# API PUBLIQUE — appelée par `trench_fp.gd`
# =================================================================================================
func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced


# Renvoie TRUE si cette arme est PEINTE (donc si ce nœud a la main), FALSE si l'hôte doit rendre
# le viewmodel en primitives à la place.
func set_weapon(weapon_id: String) -> bool:
	var changed := weapon_id != _weapon
	_weapon = weapon_id
	_sprite_mode = Sprites.viewmodel_available(weapon_id)
	visible = _sprite_mode
	# GLISSEMENT bas -> haut à l'ESCALADE seulement : la toute première arme du duel est déjà en
	# main quand la manche commence, elle n'a pas à « monter » depuis le bas de l'écran.
	if _sprite_mode and changed and _has_weapon and not _reduced_motion:
		_slide = 1.0
	_has_weapon = true
	_state = ""
	_apply_state()
	_layout()
	return _sprite_mode


func notify_fire() -> void:
	_shots += 1
	# `reduced_motion` : UNE FRAME SUR DEUX ⚙. À la cadence du FRELON, la frame `fire` alternant
	# avec `idle` produit un stroboscope — exactement ce que le réglage de confort doit supprimer.
	# On ne supprime pas le retour visuel pour autant : le recul, lui, reste (réduit de moitié).
	if _reduced_motion and _shots % 2 == 0:
		return
	_fire_left = FIRE_FRAME_TIME


func set_reloading(reloading: bool) -> void:
	_reloading = reloading


func set_recoil(recoil: float) -> void:
	_recoil = recoil


# ╔═ LA POSE « GRENADE EN MAIN » (§B.1.1) — ET SON REPLI HONNÊTE ═════════════════════════════════╗
# ║ Le bon de commande demande la frame `vm_grenade` « si présente, sinon abaisse l'arme ». Le      ║
# ║ contrat de nommage du chantier n'a JAMAIS prévu cette frame : les 18 fichiers livrés sont       ║
# ║ 6 soldats + 4 armes × 3 états, et `vm_grenade.png` n'existe pas. On ne l'invente donc pas dans  ║
# ║ le registre (ce serait ouvrir un 19ᵉ nom que personne n'a commandé) — mais on le CHERCHE, pour  ║
# ║ que le jour où Hakim déposera le fichier, il prenne sans une ligne de code, comme tout le reste.║
# ║ En attendant, l'arme S'ABAISSE : c'est le langage universel de « j'ai les mains occupées », et  ║
# ║ ça se lit sans texte. ⚠️ Elle s'abaisse assez pour dégager la vue du décalque au sol, qui est LA ║
# ║ chose qu'on demande au joueur de regarder pendant ce geste — la descendre à moitié cacherait     ║
# ║ précisément l'information qu'on vient d'ajouter.                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const GRENADE_FRAME := "res://assets/images/trench/sprites/vm_grenade.png"
const GRENADE_LOWER_RATIO := 0.55      # fraction de la hauteur d'arme dont elle plonge ⚙
const GRENADE_LOWER_SPEED := 9.0


func set_grenade_aim(aiming: bool) -> void:
	_grenade_aim = aiming


func _process(delta: float) -> void:
	if not _sprite_mode:
		return
	_fire_left = maxf(0.0, _fire_left - delta)
	var dip_target := 1.0 if _reloading else 0.0
	if _reduced_motion:
		_reload_dip = dip_target
	else:
		_reload_dip = lerpf(_reload_dip, dip_target, minf(1.0, delta * RELOAD_DIP_SPEED))
	if _slide > 0.0:
		_slide = maxf(0.0, _slide - delta / SWAP_SLIDE_TIME)
	var grenade_target := 1.0 if _grenade_aim else 0.0
	if _reduced_motion:
		_grenade_dip = grenade_target
	else:
		_grenade_dip = lerpf(_grenade_dip, grenade_target, minf(1.0, delta * GRENADE_LOWER_SPEED))

	# ORDRE DE PRIORITÉ : la GRENADE gagne sur tout (les deux mains y sont, on ne tire pas et on ne
	# recharge pas en armant), puis le rechargement gagne sur le tir — on ne tire pas pendant un
	# rechargement (règle serveur §8.137), donc afficher `fire` par-dessus `reload` serait un
	# mensonge. L'ordre du `match` EST la règle : il n'y a pas de second endroit où elle vive.
	var wanted := "idle"
	if _grenade_aim and _grenade_texture() != null:
		wanted = "grenade"
	elif _reloading:
		wanted = "reload"
	elif _fire_left > 0.0:
		wanted = "fire"
	if wanted != _state:
		_state = wanted
		_apply_state()
	_layout()


# La frame de grenade, si Hakim l'a déposée. `null` = repli par l'abaissement de l'arme.
func _grenade_texture() -> Texture2D:
	return Sprites.texture_at(GRENADE_FRAME)


func _apply_state() -> void:
	if _rect == null:
		return
	if not _sprite_mode:
		_rect.texture = null
		return
	if _state == "":
		_state = "idle"
	# La frame de grenade n'appartient à AUCUNE arme : elle vit hors du contrat `vm_<arme>_<état>`,
	# parce que la main qui arme est la même quelle que soit l'arme rangée.
	if _state == "grenade":
		_rect.texture = _grenade_texture()
		return
	_rect.texture = Sprites.viewmodel_texture(_weapon, _state)


# ⚠️⚠️ LE CADRAGE SE PREND SUR LE VIEWPORT, JAMAIS SUR `size` — défaut vu en CAPTURE (§8.138).
# Un `Control` créé PAR CODE puis ajouté à un parent Control ne voit pas sa taille résolue par le
# seul `set_anchors_preset(PRESET_FULL_RECT)` : `size` reste (0, 0), `_layout()` sortait par la
# porte de secours et le viewmodel peint ne se dessinait NULLE PART — écran vide, aucune erreur,
# aucun symptôme au boot headless. C'est aussi ce que dit le besoin, mot pour mot : « taille
# relative à la hauteur d'ÉCRAN ». Le reste du dépôt contourne le piège autrement (les enfants de
# `unlock_celebration.gd` sont placés par ancres et containers, jamais par arithmétique sur `size`).
func _layout() -> void:
	if _rect == null or _rect.texture == null:
		return
	var screen := get_viewport_rect().size
	if screen.y <= 0.0:
		return
	var box_h := screen.y * HEIGHT_RATIO
	var tex_size := _rect.texture.get_size()
	var box_w := box_h * (tex_size.x / maxf(1.0, tex_size.y))
	_rect.size = Vector2(box_w, box_h)
	# Pivot en BAS AU CENTRE de l'image : le roulis du recul fait pivoter l'arme autour du poignet,
	# pas autour de son coin supérieur gauche (qui la ferait balayer tout l'écran).
	_rect.pivot_offset = Vector2(box_w * 0.5, box_h)

	var kick: float = _recoil * (0.5 if _reduced_motion else 1.0)
	var place := Vector2(screen.x - box_w * (1.0 - BLEED_RIGHT),
		screen.y - box_h * (1.0 - BLEED_BOTTOM))
	place.y += kick * RECOIL_KICK_PX
	place.y += _reload_dip * box_h * RELOAD_DIP_RATIO
	place.y += _slide * box_h
	# L'ABAISSEMENT DE GRENADE — n'a d'effet que quand `vm_grenade.png` MANQUE : avec la frame
	# déposée, c'est elle qui montre la main, et la faire plonger en plus la sortirait du cadre.
	if _state != "grenade":
		place.y += _grenade_dip * box_h * GRENADE_LOWER_RATIO
	_rect.position = place
	_rect.rotation = deg_to_rad(kick * RECOIL_ROLL_DEG + _reload_dip * RELOAD_DIP_DEG)


# --- Lectures, pour le harnais de recette --------------------------------------------------------
func current_state() -> String:
	return _state


func is_painted() -> bool:
	return _sprite_mode
