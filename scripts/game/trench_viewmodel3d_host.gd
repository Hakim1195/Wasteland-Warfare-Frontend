extends SubViewportContainer

# =================================================================================================
# §8.152 — LOT 3D-H : L'HÔTE DU VIEWMODEL 3D
#
# ╔═ POURQUOI UN ADAPTATEUR, ET PAS UNE RÉÉCRITURE DES SITES D'APPEL ════════════════════════════╗
# ║ Le viewmodel 2D peint expose onze méthodes, appelées depuis huit endroits de `trench_fp.gd`.  ║
# ║ Les réécrire une par une, c'est huit occasions de casser quelque chose dans le fichier le plus ║
# ║ chargé du projet — et deux d'entre elles sont des crans de rafale dont le comportement est     ║
# ║ gardé par `probe_trench_falseshot`.                                                           ║
# ║                                                                                               ║
# ║ Cet hôte présente donc **exactement la même API**, et traduit vers le rig en interne. La       ║
# ║ bascule du lot devient **UNE SEULE LIGNE** : le `preload` de la couche 3 change de script.     ║
# ║ Ce qui casse, casse d'un bloc et se revient d'un bloc.                                        ║
# ║                                                                                               ║
# ║ ⚠️ Il est un `SubViewportContainer`, donc un `Control` — et ce n'est pas un détail :           ║
# ║   • `trench_fp.gd` applique la secousse d'écran en écrivant `layer.position` sur les trois     ║
# ║     couches. Un `Node3D` n'a pas de `position: Vector2`.                                       ║
# ║   • `test_trench_ambient.gd` vérifie l'ORDRE des six couches par index d'enfant.               ║
# ║ Un enfant direct de `TrenchFP` à la même place : les deux gardes continuent sans une ligne.    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ POURQUOI UN VIEWPORT SÉPARÉ — le pavé de `trench_fp_world.gd:21-30` est PÉRIMÉ ═════════════╗
# ║ Il justifie l'absence d'un second viewport par « il n'y a AUCUNE géométrie à moins de 2 m      ║
# ║ devant les yeux », et se termine par « si un jour l'arène gagne un obstacle proche, c'est CE  ║
# ║ commentaire qu'il faudra rouvrir ». On le rouvre : **c'est faux aujourd'hui.**                 ║
# ║                                                                                               ║
# ║ Le parapet proche occupe z ∈ [0 ; 0,6] et y ∈ [0 ; 1,25] (`trench_blockout.gd:238`). L'œil est ║
# ║ à z = −0,5 (`Geo.near_soldier_z()`). **Sa face proche est donc à 0,50 m de l'œil, pas à 2 m.** ║
# ║ Et accroupi (`EYE_DOWN = 0,90`) l'œil est 0,35 m SOUS le sommet des sacs, alors que l'origine  ║
# ║ du rig est 0,29 à 0,34 m devant lui et que le canon prolonge encore : **l'arme est             ║
# ║ géométriquement à l'intérieur du volume de sacs.** Sans viewport séparé, elle les traverse.    ║
# ║ ⚠️ Cotes LUES, pas rendues — la mesure d'intersection à l'image reste à faire en capture.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

const Rig := preload("res://scripts/game/trench_viewmodel3d.gd")
const Weapons := preload("res://scripts/game/trench_weapons3d.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const TuningScript := preload("res://scripts/game/trench_tuning.gd")

# ── L'ÉCLAIRAGE DU VIEWMODEL ──────────────────────────────────────────────────────────────────
# ⚠️ `ENV_OCCLUSION = 0,24` est le contrat posé au lot 3D-C, et c'est ICI qu'il s'applique : Godot
# n'a pas d'`envMapIntensity` par matériau. « Une arme à l'épaule ne voit qu'un quart du ciel » —
# sans ce facteur, le viewmodel est éclairé comme s'il flottait en plein air et se détache de la
# scène, ce qui est le défaut « autocollant » que tout le lot 3D-C cherche à éviter.
const AMBIANTE := 1.6
# Le facteur du banc de calibration du lot 3D-C. À NE PAS toucher sans re-mesurer `ALBEDO_GAIN`.
const COMPENSATION_BANC := 4.0

# Les intensités du panneau F10, que le rig ne connaît pas. Elles vivent ici, à la frontière.
var _feel_recoil: float = TuningScript.defaults()["feel_recoil"]
var _feel_flinch: float = TuningScript.defaults()["feel_flinch"]
var _reduced_motion := false

var _viewport: SubViewport
var _camera: Camera3D
var _rig

# ⛔ La durée de rechargement est une RÈGLE : elle vient du serveur, jamais d'un barème d'ici.
# L'hôte la demande à son fournisseur au lieu de la stocker — c'est ce qui lui permet de rester
# juste quand le registre arrive APRÈS la construction (cf. le piège d'ordonnancement du rig).
var reload_source: Callable = Callable()

var _weapon := ""
var _pattern := PackedFloat32Array()
var _shot := 0
var _reload_played := false
var _etat: Dictionary = {}


func _init() -> void:
	name = "TrenchViewmodel3D"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_viewport = SubViewport.new()
	# ⚠️ `transparent_bg` : le viewmodel se pose PAR-DESSUS le monde, il ne le remplace pas.
	_viewport.transparent_bg = true
	# ⚠️ `own_world_3d` : c'est tout le point du lot. Sans monde propre, l'arme partagerait la
	# profondeur de l'arène et traverserait le parapet (voir le pavé d'en-tête).
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	# 🩸 LE FACTEUR 4 N'EST PAS UN AJUSTEMENT À VUE : il vient du banc de rendu
	# `shot_vue3d_parts.gd:58`, qui est l'appareil sur lequel l'`ALBEDO_GAIN` des matériaux a
	# été CALIBRÉ au lot 3D-C, par mesure de luminance contre la capture de référence.
	# Première version : je l'avais laissé tomber. Résultat mesuré en capture : une arme
	# **quasi noire**, quatre fois plus sombre que ce sur quoi les matériaux ont été réglés.
	# ⚠️ Un éclairage n'est pas un goût quand des matériaux ont été calibrés dessus : c'est
	# une COTE, et la changer invalide silencieusement toute la calibration du lot 3D-C.
	env.ambient_light_energy = AMBIANTE * WMat.ENV_OCCLUSION * COMPENSATION_BANC
	# ⚠️ AgX, comme le monde : c'est la courbe qui décide si un chanfrein lit « alliage poli » ou
	# « trait de crayon blanc ». Deux courbes différentes feraient deux armes différentes.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 2.6
	key.light_color = Color(1.0, 0.96, 0.90)
	key.rotation_degrees = Vector3(-34, 142, 0)
	_viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.7
	fill.light_color = Color(0.60, 0.70, 0.90)
	fill.rotation_degrees = Vector3(-12, -44, 0)
	_viewport.add_child(fill)

	# ⚠️ La caméra du viewmodel est à l'ORIGINE et regarde en −Z : le rig compose ses poses dans ce
	# repère (`hip_pos.z` négatif = devant l'œil). Elle n'a AUCUN lien avec la caméra du monde, et
	# c'est délibéré — `project_aim()` et `camera_fov()` doivent continuer de lire celle du MONDE,
	# sinon le pincement de champ du viewmodel déplacerait le réticule.
	_camera = Camera3D.new()
	_camera.near = 0.005
	_camera.far = 6.0
	_camera.current = true
	_viewport.add_child(_camera)

	_rig = Rig.new()
	_viewport.add_child(_rig)


# =================================================================================================
# L'API DU VIEWMODEL 2D — mot pour mot
# =================================================================================================

# Rend `true` si l'arme est « peinte ». ⚠️ Le repli peint/primitives n'existe plus : le rig calcule
# les quatre armes, il n'y a plus de cas où l'une manque. On rend donc TOUJOURS `true`, ce qui fait
# que `trench_fp.gd` cesse d'appeler `_world.set_viewmodel_visible(...)` — le viewmodel en
# primitives de `trench_fp_world.gd` reste éteint, et il n'y a jamais deux armes à l'écran.
func set_weapon(weapon_id: String) -> bool:
	if weapon_id == "":
		return true
	if not _rig.weapons.has(weapon_id):
		_rig.add_weapon(weapon_id, _reload_seconds(weapon_id))
	_rig.set_active(weapon_id)
	_weapon = weapon_id
	_pattern = Weapons.build_recoil_pattern(weapon_id)
	_shot = 0
	return true


# ⚠️ Le rig ATTEND le recul en espace de visée — c'est ce qui fait que « the visual climb matches
# where the bullets are actually going ». Le MOTIF est une valeur de VUE (sa forme), et il est
# déterministe : même graine, même suite, sur toutes les machines.
# ⛔ Il ne décide de RIEN : la dispersion du serveur ne le lit pas et ne peut pas le lire.
func notify_fire() -> void:
	if _weapon == "" or _pattern.is_empty():
		return
	var n: int = _pattern.size() / 2
	var i: int = _shot % n
	# `_feel_recoil` est le curseur F10 : 0 = coupé, 1 = livré, 2 = doublé. 100 % cosmétique.
	var k := _feel_recoil
	_rig.add_recoil(_pattern[i * 2] * k, _pattern[i * 2 + 1] * k, _shot == 0)
	_shot += 1


# ⚠️ TROU COMBLÉ, ET LE MOYEN EST ASSUMÉ. Le rig n'a pas de couche d'encaissement : la référence
# n'en a pas non plus (son soldat en a une, pas son viewmodel). On réemploie le ressort
# d'ATTERRISSAGE, dont la forme est exactement celle qu'on veut — un plongeon vers le bas plus un
# piqué (`py -= land * 0,014` et `rx -= land * 0,05`). Ce n'est pas un détournement paresseux :
# c'est la même impulsion physique, et lui écrire un ressort jumeau n'aurait rien ajouté.
func notify_flinch() -> void:
	_rig.land(2.2 * _feel_flinch)


# ⚠️ CHANGEMENT DE NATURE, ET C'EST LE PLUS PIÉGEUX DU LOT. Le duel pousse ici un DRAPEAU CONTINU,
# à chaque frame, dérivé de `reload_until_tick > render_tick`. Le rig, lui, veut un DÉCLENCHEMENT
# PONCTUEL. Sans le souvenir ci-dessous, le clip serait relancé soixante fois par seconde et
# resterait figé sur sa première image — une arme qui « recharge » sans jamais bouger.
func set_reloading(reloading: bool) -> void:
	if reloading and not _reload_played:
		# ⛔ Le choix tac/vide se fait sur les MUNITIONS LUES DE L'ÉTAT, jamais sur un barème.
		_rig.play("reload_empty" if bool(_etat.get("empty", false)) else "reload_tac")
	elif not reloading and _reload_played:
		# Le serveur a fini avant le clip (ou l'a interrompu) : on ne laisse pas une animation
		# survivre à la règle qu'elle illustre.
		if _rig.clip_playing():
			_rig.stop_clip()
	_reload_played = reloading


# Le duel pousse la visée COURANTE ; le rig en dérive lui-même la vitesse angulaire.
# ⚠️ Les degrés sont convertis dans `_rig_state()`, côté duel. Ici on ne fait que mémoriser.
func set_aim(_yaw_deg: float, _pitch_deg: float) -> void:
	pass


func set_feel_tuning(values: Dictionary) -> void:
	_feel_recoil = clampf(float(values.get("feel_recoil", _feel_recoil)), 0.0, 2.0)
	_feel_flinch = clampf(float(values.get("feel_flinch", _feel_flinch)), 0.0, 2.0)


func set_grenade_aim(_aiming: bool) -> void:
	pass   # transporté par `low_ready` dans l'état — voir `_rig_state()` côté duel.


# ⚠️ TROU COMBLÉ : le rig n'a aucun réglage de confort. Sans ça, le balancement, le bob, la traîne
# et la respiration tourneraient toujours — une **régression d'accessibilité** par rapport au
# viewmodel 2D, qui les coupait. On le porte au niveau de l'état poussé.
func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced


# =================================================================================================
# LA BOUCLE
# =================================================================================================
# `etat` est le dictionnaire assemblé par `_rig_state()` côté duel. L'hôte n'y ajoute que ce qui
# relève du CONFORT, jamais une règle.
func pousser_etat(etat: Dictionary) -> void:
	_etat = etat


func _process(delta: float) -> void:
	if _rig == null or _rig.active.is_empty():
		return
	# ⚠️ La durée de rechargement peut arriver APRÈS la construction de l'arme (`_apply_weapon` est
	# appelé dans `_ready()`, le registre arrive à `_on_init`). On la repousse à chaque frame : le
	# rig ignore les valeurs nulles et ne reconstruit ses clips que si elle a VRAIMENT changé.
	if _weapon != "":
		_rig.set_reload_seconds(_weapon, _reload_seconds(_weapon))

	var s := _etat.duplicate()
	if _reduced_motion:
		# ⚠️ On coupe les couches CONTINUES (balancement, bob), pas le recul : un tir sans retour
		# ne serait plus lisible, et le mouvement réduit vise le confort, pas la mutilation.
		s["speed"] = 0.0
	_rig.update(delta, s)
	var fov := float(_rig.view_fov())
	if absf(_camera.fov - fov) > 1e-3:
		_camera.fov = fov


# =================================================================================================
# LECTURES
# =================================================================================================
func feel_probe() -> Dictionary:
	# ⚠️ Les unités ne sont PAS celles du viewmodel 2D (qui rendait des PIXELS et des degrés). On
	# rend les résidus du rig, en mètres et en radians, sous leurs propres noms — plutôt que de
	# fabriquer une conversion en pixels qui n'aurait aucun sens sans une distance de projection.
	# ⚠️ `probe_trench_feel_aim` lit `kick_px` : sa section 2 devra être réécrite, et c'est signalé.
	return _rig.residus()


func current_state() -> String:
	if _rig.clip_playing():
		return "clip"
	return "idle"


func is_painted() -> bool:
	return true


# ⛔ LA DURÉE DE RECHARGEMENT NE VIENT QUE DU SERVEUR. Pas de défaut, pas de barème : si le
# fournisseur n'est pas branché ou si le registre est muet, on rend 0 et le rig garde ses clips
# précédents. Un zéro se remarque ; un « 2,15 s » plausible se fondrait dans le décor et
# divergerait au premier rééquilibrage — c'est le patron du §8.148.
func _reload_seconds(weapon_id: String) -> float:
	if not reload_source.is_valid():
		return 0.0
	return float(reload_source.call(weapon_id))
