extends Control
# =================================================================================================
# LA TRANCHÉE FP (§8.138) — LE VIEWMODEL PEINT : mains + arme, couche 2D à frames.
#
# VUE PURE : aucun réseau, aucune règle, aucune décision. L'hôte (`trench_fp.gd`) pousse une arme,
# un drapeau de rechargement, la visée à suivre, « j'ai tiré » et « j'ai encaissé » ; ce script n'en
# déduit qu'une frame et une position. Il ne sait même pas qu'il y a un duel. Depuis §8.151, le
# RECUL vit ici en ressorts (`trench_springs.gd`) — l'hôte n'envoie plus de valeur de recul.
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
const Springs := preload("res://scripts/game/trench_springs.gd")

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

# ╔═ §8.151 LOT B — LE RECUL À RESSORTS (RE-FONDATION du kick linéaire, pas une superposition) ═══╗
# ║ Avant : l'hôte poussait `_recoil` (1 → 0, décru à 6/s) et ce nœud le multipliait par 26 px.    ║
# ║ Un fondu linéaire ne PÈSE rien : il monte et descend à la même vitesse. Le recul vit désormais ║
# ║ ICI, dans trois `TrenchRecoilAxis` (deux étages §4.1) armés par `notify_fire()` : il monte     ║
# ║ d'un coup (kick en DÉPLACEMENT), claque l'aller-retour, puis se POSE — et s'assèche à ZÉRO     ║
# ║ EXACT, la propriété qui rend le repos bit-stable pour les captures (LOT E).                    ║
# ║ ⚠️ Tout est RETOUR-À-ZÉRO et rien n'écrit dans une visée : ce nœud ne sait même pas qu'une     ║
# ║ visée existe — il ne reçoit que des angles à SUIVRE en retard (la traîne, plus bas).           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Kick « quelques px » (cahier §4.2) vers le coin bas-droit + micro-roulis ⚙.
const KICK_DOWN_PX := 12.0
const KICK_SIDE_PX := 5.0
const KICK_ROLL_DEG := 1.6
# Forme de la référence (§4.1) : 9,5 Hz / zeta 0,52 / part résiduelle 0,34. ⚠️ MAIS tau résiduel
# 0,2 s au lieu de 0,3 : imposé par le REGISTRE, pas par le goût — la cadence minimale du jeu est
# de 0,8 s (min des `cooldown_ticks` servis par `public_rules`), et le kick doit être SOUS LE PIXEL
# avant le tir suivant, même à intensité F10 maximale (×2). À tau 0,3, la queue résiduelle d'un
# kick de 24 px reste > 0,5 px pendant ~0,86 s : l'effet survivrait au tir suivant, ce que le
# cahier §4.2 interdit. À 0,2, elle rend l'arme sous le demi-pixel en ~0,56 s — MESURÉ par
# `probe_trench_feel_aim`, qui compare ce temps à l'intervalle LU dans les règles.
const KICK_FREQ := 9.5
const KICK_ZETA := 0.52
const KICK_RESIDUAL_TAU := 0.2
const KICK_RESIDUAL_SHARE := 0.34
# RESPIRATION ⚙ : dérive lente de 2-3 px par `hash_noise` sur le TEMPS DE SCÈNE cumulé — jamais
# l'horloge murale : deux exécutions au même index de frame rendent le même pixel (LOT E).
const BREATH_AMP_PX := 2.5
const BREATH_RATE_X := 0.45          # cellules de bruit par seconde — une houle, pas un tremblement
const BREATH_RATE_Y := 0.37
const BREATH_SEED_X := 8151
const BREATH_SEED_Y := 8152
# TRAÎNE DE VISÉE ⚙ : l'arme suit la souris avec un léger retard (ressort CRITIQUE — zeta 1, le
# plus rapide SANS dépassement : une arme qui rebondirait après la main se lirait cassée).
# Le RÉTICULE, lui, reste exact : la traîne ne touche que ce nœud.
const TRAIL_FREQ := 5.0
const TRAIL_ZETA := 1.0
const TRAIL_PX_PER_DEG := 1.1
const TRAIL_MAX_PX := 14.0
# FLINCH ⚙ : plongeon bref à l'encaissement (le pouls rouge, lui, vit dans l'overlay de l'hôte).
const FLINCH_DIP_PX := 9.0
const FLINCH_FREQ := 7.0
const FLINCH_ZETA := 0.9

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
var _reduced_motion := false
# --- §8.151 : l'état du FEEL — trois axes de kick, un flinch, deux traînes, une horloge de scène --
var _kick_down := Springs.TrenchRecoilAxis.new(KICK_FREQ, KICK_ZETA,
	KICK_RESIDUAL_TAU, KICK_RESIDUAL_SHARE)
var _kick_side := Springs.TrenchRecoilAxis.new(KICK_FREQ, KICK_ZETA,
	KICK_RESIDUAL_TAU, KICK_RESIDUAL_SHARE)
var _kick_roll := Springs.TrenchRecoilAxis.new(KICK_FREQ, KICK_ZETA,
	KICK_RESIDUAL_TAU, KICK_RESIDUAL_SHARE)
var _flinch := Springs.TrenchSpring.new(FLINCH_FREQ, FLINCH_ZETA, 0.0)
var _trail_yaw := Springs.TrenchSpring.new(TRAIL_FREQ, TRAIL_ZETA, 0.0)
var _trail_pitch := Springs.TrenchSpring.new(TRAIL_FREQ, TRAIL_ZETA, 0.0)
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _trail_init := false
# Temps de SCÈNE cumulé (somme des delta) — la respiration s'y indexe, JAMAIS sur l'horloge murale.
var _feel_clock := 0.0
# Intensités F10 (0..2), poussées par l'hôte depuis `trench_tuning.gd`.
var _intensity_recoil := 1.0
var _intensity_breath := 1.0
var _intensity_flinch := 1.0
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
	# §8.151 — LE KICK, en DÉPLACEMENT (deux étages §4.1) : l'arme SAUTE dans le coin, le ressort
	# n'a plus qu'à revenir. ⚠️ L'hôte n'appelle ceci que pour un tir ACCEPTÉ par la prédiction des
	# six refus (§8.141.9) : un clic refusé ne passe jamais par ici — ni kick, ni frame de tir.
	# ⚠️ Seulement en mode PEINT : sans frames, ce nœud est invisible et des kicks accumulés sans
	# être intégrés ressortiraient d'un coup au retour d'une arme peinte.
	if _sprite_mode:
		var k := _intensity_recoil * (0.5 if _reduced_motion else 1.0)
		_kick_down.kick(KICK_DOWN_PX * k)
		_kick_side.kick(KICK_SIDE_PX * k)
		_kick_roll.kick(KICK_ROLL_DEG * k)
	# `reduced_motion` : UNE FRAME SUR DEUX ⚙. À la cadence du FRELON, la frame `fire` alternant
	# avec `idle` produit un stroboscope — exactement ce que le réglage de confort doit supprimer.
	# On ne supprime pas le retour visuel pour autant : le recul, lui, reste (réduit de moitié).
	if _reduced_motion and _shots % 2 == 0:
		return
	_fire_left = FIRE_FRAME_TIME


# §8.151 — L'ENCAISSEMENT : plongeon bref. `set_value` et non `impulse` (le coup ARRIVE, il ne
# pousse pas), et `maxf` pour que deux touches rapprochées ne s'empilent pas en fuite vers le bas.
func notify_flinch() -> void:
	if not _sprite_mode:
		return
	var k := _intensity_flinch * (0.5 if _reduced_motion else 1.0)
	_flinch.set_value(maxf(_flinch.value, FLINCH_DIP_PX * k))


func set_reloading(reloading: bool) -> void:
	_reloading = reloading


# §8.151 — LA TRAÎNE : l'hôte pousse la visée COURANTE (en degrés), ce nœud la suit en retard par
# ressort critique. Le premier appel COLLE (pas de fausse traîne au boot). Rien n'est renvoyé, rien
# n'est modifié côté visée : la traîne est à sens unique, de la main vers l'image.
func set_aim(yaw_deg: float, pitch_deg: float) -> void:
	_aim_yaw = yaw_deg
	_aim_pitch = pitch_deg
	if not _trail_init:
		_trail_init = true
		_snap_trail()


# Intensités du panneau F10 (`feel_*`, 0..2). Bornées ICI aussi : le fichier de réglages est une
# commodité, jamais une autorité (même règle que `trench_tuning._load`).
func set_feel_tuning(values: Dictionary) -> void:
	_intensity_recoil = clampf(float(values.get("feel_recoil", _intensity_recoil)), 0.0, 2.0)
	_intensity_breath = clampf(float(values.get("feel_breath", _intensity_breath)), 0.0, 2.0)
	_intensity_flinch = clampf(float(values.get("feel_flinch", _intensity_flinch)), 0.0, 2.0)


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
	_feel_clock += delta
	_step_feel(delta)
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


# =================================================================================================
# §8.151 — LE PAS DE FEEL : ressorts intégrés au temps de scène, offsets composés dans `_layout`
# =================================================================================================
func _step_feel(dt: float) -> void:
	_kick_down.step(dt)
	_kick_side.step(dt)
	_kick_roll.step(dt)
	_flinch.step(dt)
	if _reduced_motion:
		# Pas de traîne en mouvement réduit : le ressort COLLE à la visée, l'offset est un ZÉRO
		# exact (pas un « presque zéro » qui laisserait l'arme dériver d'un demi-pixel).
		_snap_trail()
	else:
		_trail_yaw.target = _aim_yaw
		_trail_pitch.target = _aim_pitch
		_trail_yaw.step(dt)
		_trail_pitch.step(dt)


func _snap_trail() -> void:
	_trail_yaw.target = _aim_yaw
	_trail_yaw.reset(_aim_yaw)
	_trail_pitch.target = _aim_pitch
	_trail_pitch.reset(_aim_pitch)


# La somme des offsets de feel, en px d'écran. TOUT y est à retour-à-zéro exact (assèchement §4.1) —
# au repos, cette fonction rend PILE la respiration, et la respiration seule.
func _feel_offset() -> Vector2:
	var off := Vector2(_kick_side.value, _kick_down.value + _flinch.value)
	if not _reduced_motion:
		off += _breath_offset()
		off += _trail_offset()
	return off


func _breath_offset() -> Vector2:
	return Vector2(
		Springs.hash_noise(_feel_clock * BREATH_RATE_X, BREATH_SEED_X),
		Springs.hash_noise(_feel_clock * BREATH_RATE_Y, BREATH_SEED_Y)) \
		* (BREATH_AMP_PX * _intensity_breath)


# La traîne, convertie en px. SIGNE : la main balaie, l'arme reste un instant où l'on VISAIT — or
# ce point-là a glissé du côté opposé au geste (le monde défile à l'envers de la souris). Avec
# `SCREEN_TO_WORLD_X = -1` côté hôte, souris à droite = lacet qui DÉCROÎT, donc (visée - traîne)
# négatif = arme décalée à GAUCHE : c'est le bon côté, vérifié axe par axe.
func _trail_offset() -> Vector2:
	var off := Vector2(_aim_yaw - _trail_yaw.value, _aim_pitch - _trail_pitch.value) \
		* TRAIL_PX_PER_DEG
	return off.clampf(-TRAIL_MAX_PX, TRAIL_MAX_PX)


# Lecture pour `probe_trench_feel_aim` : les offsets bruts et le témoin de repos EXACT des axes de
# kick (la respiration n'y figure pas — elle ne se repose jamais, et c'est voulu).
func feel_probe() -> Dictionary:
	return {
		"kick_px": Vector2(_kick_side.value, _kick_down.value),
		"roll_deg": _kick_roll.value,
		"flinch_px": _flinch.value,
		"trail_px": _trail_offset(),
		"breath_px": _breath_offset(),
		"kick_at_rest": _kick_side.at_rest() and _kick_down.at_rest()
			and _kick_roll.at_rest() and _flinch.at_rest(),
	}


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

	var place := Vector2(screen.x - box_w * (1.0 - BLEED_RIGHT),
		screen.y - box_h * (1.0 - BLEED_BOTTOM))
	# §8.151 — LES OFFSETS DE FEEL (kick à ressorts + flinch + respiration + traîne), tous à
	# retour-à-zéro EXACT. Ils ne déplacent que CE nœud : le réticule reste tenu par `project_aim`
	# seul, et la visée envoyée ne passe même pas par ici (« le réticule ne ment jamais », §8.141.6).
	place += _feel_offset()
	place.y += _reload_dip * box_h * RELOAD_DIP_RATIO
	place.y += _slide * box_h
	# L'ABAISSEMENT DE GRENADE — n'a d'effet que quand `vm_grenade.png` MANQUE : avec la frame
	# déposée, c'est elle qui montre la main, et la faire plonger en plus la sortirait du cadre.
	if _state != "grenade":
		place.y += _grenade_dip * box_h * GRENADE_LOWER_RATIO
	_rect.position = place
	_rect.rotation = deg_to_rad(_kick_roll.value + _reload_dip * RELOAD_DIP_DEG)


# --- Lectures, pour le harnais de recette --------------------------------------------------------
func current_state() -> String:
	return _state


func is_painted() -> bool:
	return _sprite_mode
