extends Control
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — CONTRÔLEUR du duel en VUE À LA PREMIÈRE PERSONNE.
#
# Remplace la vue de côté v1 (§1.7). La scène est 100 % code-driven (patron company_screen /
# events_screen / trench_duel v1) et se compose en QUATRE COUCHES (§2.3) :
#
#   COUCHE 1  décor PRÉ-RENDU de la pose courante (`TextureRect` plein écran)
#             → absent ? on montre le GREYBOX du blockout, aligné PAR DÉFINITION (c'est la même
#               caméra qui a servi à générer les décors — cf. tools/gen_trench_renders.gd).
#   COUCHE 2  `trench_fp_world.tscn` : SubViewport 3D transparent — blockout, soldat adverse,
#             traçantes, grenades + marqueurs au sol, laser, ET le viewmodel (choix motivé sur place).
#   COUCHE 3  le VIEWMODEL PEINT (§8.138) — `trench_viewmodel.gd`, couche 2D à frames en bas-droite.
#             → arme sans fichiers ? ce nœud s'efface et le viewmodel en PRIMITIVES du SubViewport
#               (couche 2) reprend le service pour CETTE arme. Aiguillage unique : `_apply_weapon`.
#   COUCHE 4  le HUD (LOT D).
#
# ╔═ CE QUE CE SCRIPT NE FAIT JAMAIS ═════════════════════════════════════════════════════════════╗
# ║ • Il ne DÉCIDE aucune touche. Il envoie une DIRECTION DE VISÉE ; le serveur résout contre sa   ║
# ║   table angulaire et son état. Le hitmarker ne s'allume que sur un événement `hit` CONFIRMÉ —  ║
# ║   jamais en optimiste (l'honnêteté du feedback est une règle maison, pas un détail).           ║
# ║ • Il ne devine pas une position masquée. Quand la redaction §1.6 renvoie `pos: null`,          ║
# ║   l'adversaire s'efface en fondu là où on l'a vu — et le client N'A PAS l'information.         ║
# ║ • Il n'embarque AUCUN barème : armes, chargeurs, dispersion, cotes d'arène et bandage          ║
# ║   arrivent tous dans `trench_init.rules` (`public_rules()` serveur).                           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ENTRÉES (§5.6) : Q/D ou ◀▶ = position · S ou CTRL = posture (bascule) · SOURIS = visée ·
# clic gauche = tir · G ou clic droit MAINTENU = grenade (jauge + arc) · R = rechargement ·
# 2 = bandage · 1/2 = choix d'arme pendant la fenêtre · ÉCHAP = abandon (confirmation).
# =================================================================================================

const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")
const WorldScene := preload("res://scenes/game/trench_fp_world.tscn")
const ViewmodelScript := preload("res://scripts/game/trench_viewmodel.gd")
const AmbientScript := preload("res://scripts/game/trench_ambient.gd")
const TuningScript := preload("res://scripts/game/trench_tuning.gd")
const CelebrationScript := preload("res://scripts/ui/unlock_celebration.gd")

# Arme de départ du duel (miroir de `trench_sim.STARTING_WEAPON`) — sert AVANT le premier état,
# le temps que le serveur nous dise où en est l'escalade.
const STARTING_WEAPON := "vipere"

# Cadence d'envoi : STRICTEMENT sous les 10 msg/s du serveur (anti-flood §2.3) — à 0,1 s pile, la
# gigue ferait parfois tomber 11 messages dans la même seconde serveur et le 11ᵉ (peut-être un
# TIR) serait jeté. 0,105 s garantit <= 10 par seconde pleine. (Leçon conservée de la v1.)
const SEND_INTERVAL := 0.105
# Retard de rendu : 150 ms derrière le dernier état (tampon 2 états à 10 Hz, §2.4).
const RENDER_DELAY := 0.15
const CHARGE_TIME := 1.2
const RECONNECT_DELAY := 2.0

# --- Visée ---------------------------------------------------------------------------------------
# ╔═ LA SENSIBILITÉ N'EST PLUS UNE CONSTANTE : ELLE SE RÈGLE EN JEU (touche F10) ═════════════════╗
# ║ 0,055 puis 0,040 °/px ont été choisis par raisonnement, sans jamais avoir été éprouvés — et le ║
# ║ verdict du seul essai réel a été « le mouvement de la souris est inversé et pas du tout facile ║
# ║ à gérer ». Le code cesse donc de deviner : `trench_tuning.gd` expose sensibilité, inversion Y, ║
# ║ suivi de caméra, plafond et FOV à Hakim, qui règle en jouant. 0,040 reste la valeur de départ. ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
var _sensitivity: float = TuningScript.DEFAULTS["mouse_sensitivity"]
var _invert_y: bool = TuningScript.DEFAULTS["invert_y"]
# Débattement autorisé. Le lacet doit couvrir la position adverse la plus lointaine (±24,4° depuis
# un bord) avec de la marge ; le site reste étroit — il n'y a rien à viser au ciel.
const AIM_YAW_LIMIT := 32.0
const AIM_PITCH_LIMIT := 14.0
# Quantum d'envoi (§2.4) : la visée part arrondie au dixième de degré, et SEULEMENT si elle a bougé.
const AIM_QUANTUM := 0.1

const COL_ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const COL_GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const COL_TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const COL_MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const COL_DANGER := Color(0.839216, 0.270588, 0.247059, 1)
const COL_PANEL := Color(0.058824, 0.07451, 0.094118, 0.92)

# Salle à rejoindre, posée par l'écran Événements AVANT le changement de scène (patron
# `CompanyScreen.target_tag`). "" = arrivée hors flux (retour hub immédiat).
static var pending_room_id: String = ""

# --- Réseau / état -------------------------------------------------------------------------------
var _rules: Dictionary = {}
var _my_slot: int = 1
var _training := false
var _opponent: Dictionary = {}
var _buffer: Array = []
var _result: Dictionary = {}
var _match_over := false
var _tick_rate := 10.0
var _positions := 5

# --- Prédiction locale (position/posture UNIQUEMENT — §2.4) --------------------------------------
var _pred_pos: int = 2
var _pred_stance: String = "up"
var _pred_move_ready := 0.0
var _mismatch_streak := 0

# --- Visée ---------------------------------------------------------------------------------------
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _sent_aim := Vector2(9999.0, 9999.0)

# --- Entrées coalescées entre deux envois --------------------------------------------------------
var _send_accum := 0.0
var _fire_queued := false
var _throw_queued: Dictionary = {}
var _pick_queued := ""
var _reload_queued := false
var _item_queued := ""
var _charging := false
var _charge := 0.0
var _stance_toggle := false

# --- FX éphémères --------------------------------------------------------------------------------
var _hitmarker := 0.0
var _hurt_flash := 0.0
var _hurt_dir := 0.0
var _recoil := 0.0
var _enemy_hit := 0.0
var _known_projectiles: Dictionary = {}
var _reduced_motion := false
var _clock := 0.0
var _last_seen_enemy_pos := 2.0
# Visée du DERNIER laser adverse annoncé (§5.3) : le serveur la joint à l'événement `laser`, sans
# quoi le rayon pointerait au hasard et le télégraphe mentirait sur qui est visé.
var _enemy_laser_yaw := 0.0
var _enemy_laser_pitch := 0.0
var _enemy_laser_pos := 2

# --- Nœuds ---------------------------------------------------------------------------------------
var _sky: TextureRect
var _world: Control
var _ambient: Control
var _grade: ColorRect
var _tuning: Control
var _viewmodel: Control
var _hud: Control
var _reticle: Control
var _my_hp_fill: ColorRect
var _my_hp_label: Label
var _their_hp_fill: ColorRect
var _their_name: Label
var _timer_label: Label
var _score_label: Label
var _round_label: Label
var _ammo_label: Label
var _reload_label: Label
var _weapon_label: Label
var _progress_label: Label
var _slot_grenade: Label
var _slot_bandage: Label
var _banner: Label
var _waiting_label: Label
var _conn_banner: Label
var _tune_hint: Label
var _charge_back: Panel
var _charge_bar: ColorRect
var _hurt_overlay: ColorRect
var _low_hp_vignette: ColorRect
var _choice_panel: PanelContainer
var _choice_title: Label
var _choice_countdown: Label
var _choice_buttons: Array = []
var _abandon_overlay: Control
var _result_overlay: Control
var _banner_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_reduced_motion = bool(SettingsManager.get_comfort("reduced_motion"))

	_build_layers()
	_build_hud()

	NetworkManager.trench_init_received.connect(_on_init)
	NetworkManager.trench_state_received.connect(_on_state)
	NetworkManager.trench_result_received.connect(_on_result)
	NetworkManager.server_connection_lost.connect(_on_connection_lost)
	NetworkManager.server_connected.connect(_on_reconnected)
	NetworkManager.game_error.connect(_on_game_error)

	if pending_room_id == "":
		_back_to_hub()
		return
	_capture_mouse(true)
	NetworkManager.connect_to_server(pending_room_id)


func _exit_tree() -> void:
	pending_room_id = ""
	_capture_mouse(false)


# La souris est CAPTURÉE pendant le duel (c'est une visée libre) et RELÂCHÉE dès qu'un panneau
# demande un clic — confirmation d'abandon, choix d'arme, écran de fin.
func _capture_mouse(capture: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


# =================================================================================================
# COUCHES 1 & 2
# =================================================================================================
func _build_layers() -> void:
	# COUCHE 0 — LE CIEL DE DERNIER RECOURS. Le SubViewport 3D est TRANSPARENT : partout où le
	# monde 3D ne peint rien, c'est la couleur d'effacement de la fenêtre qui sort. Depuis le
	# pivot, l'arc de ciel peint couvre ±100° sur 56° de haut et ne peut pas laisser de trou — ce
	# dégradé n'est donc plus qu'un filet de sécurité, coûtant un quad. Il reste TOUJOURS allumé :
	# la seule façon de le voir est un défaut, et un défaut doit se voir en gris, pas en néant.
	var sky := TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.18, 0.19, 0.22))     # haut : ciel de cendres
	gradient.set_color(1, Color(0.46, 0.38, 0.30))     # bas  : brume basse sur les terres brûlées
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.0, 0.0)
	gradient_texture.fill_to = Vector2(0.0, 1.0)
	sky.texture = gradient_texture
	add_child(sky)
	_sky = sky

	# ╔═ LA COUCHE « DÉCOR PRÉ-RENDU » A ÉTÉ RETIRÉE ════════════════════════════════════════════╗
	# ║ C'était un `TextureRect` plein écran portant l'un des 10 décors peints, et depuis §8.139.1 ║
	# ║ un shader qui tentait de le faire suivre la caméra. Deux défauts s'y logeaient, tous deux  ║
	# ║ mesurés dans le code : la parallaxe de position comptée DEUX FOIS (32 px de découpe + 146  ║
	# ║ px de shader), et un décalage LINÉAIRE opposé à une projection en TANGENTE (~11 % à 32°).  ║
	# ║ Aucun réglage ne les réconciliait : une image plate ne peut pas suivre une caméra libre.   ║
	# ║ Le monde 3D texturé la remplace intégralement — il répond juste parce qu'il EST le monde.  ║
	# ║ Les 10 PNG restent sur disque : ils ne sont plus chargés, ils sont une réserve (§6.4).     ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝

	# COUCHE 1 — le monde 3D transparent. Il porte désormais TOUT ce qui se voit : le sol jusqu'à
	# l'horizon, les deux parapets, les barbelés, et le ciel peint sur son arc à 300 m.
	_world = WorldScene.instantiate()
	add_child(_world)
	_world.set_reduced_motion(_reduced_motion)
	_world.set_pose(_pred_pos, _pred_stance, true)

	# COUCHE 2 bis — L'HABILLAGE PROCÉDURAL (§8.139) : brume de profondeur, cendres, braises.
	# Il s'intercale ICI, entre le monde et le viewmodel, et les deux bornes sont motivées dans
	# `trench_ambient.gd` (la brume doit voiler le soldat à 35 m, jamais mon arme à 0,60 m).
	_ambient = AmbientScript.new()
	add_child(_ambient)
	_ambient.set_reduced_motion(_reduced_motion)

	# COUCHE 3 — LE VIEWMODEL PEINT (§8.138). Il vit dans la couche ÉCRAN, AU-DESSUS du SubViewport
	# et SOUS le HUD : c'est l'ORDRE D'AJOUT qui décide, et `_build_hud()` est appelé après nous.
	# Sans fichiers pour l'arme courante, ce nœud s'efface et le viewmodel en primitives du monde 3D
	# reprend le service — d'où l'aiguillage unique `_apply_weapon()`.
	_viewmodel = ViewmodelScript.new()
	add_child(_viewmodel)
	_viewmodel.set_reduced_motion(_reduced_motion)
	_apply_weapon(STARTING_WEAPON)

	# COUCHE 3 bis — L'ÉTALONNAGE UNIFIANT (§8.139). Il LIT L'ÉCRAN : il doit donc venir après tout
	# ce qu'il teinte (décor, monde, ambiance, viewmodel) et avant le HUD — que `_build_hud()`
	# ajoutera juste après. Le HUD reste HORS étalonnage : son cyan est une convention de lecture,
	# pas une image, et l'aplatir reviendrait à dégrader la lisibilité pour un gain esthétique.
	_grade = AmbientScript.make_grade_layer()
	add_child(_grade)

	# COUCHE 3 ter — LE PANNEAU DE RÉGLAGE (F10). Au-dessus de l'étalonnage : c'est un outil, pas
	# une image du jeu — le teinter reviendrait à rendre moins lisibles les chiffres qu'on règle.
	# Il reste caché jusqu'à ce que `_on_init` sache qu'on est bien en ENTRAÎNEMENT.
	_tuning = TuningScript.new()
	add_child(_tuning)
	_tuning.changed.connect(_apply_tuning)
	_apply_tuning(_tuning.values())


# L'AIGUILLAGE peint / primitives, en UN seul endroit : les deux viewmodels ne doivent jamais être
# allumés ensemble, ni éteints ensemble.
func _apply_weapon(weapon_id: String) -> void:
	_apply_weapon_check(weapon_id)


# Même aiguillage, mais il REND ce qu'il a décidé : `true` = viewmodel peint, `false` = repli en
# primitives. Le jeu n'a pas besoin de cette réponse ; le harnais de recette, si — sans elle il
# capturerait un viewmodel de repli en croyant recetter un asset peint (§8.139).
func _apply_weapon_check(weapon_id: String) -> bool:
	if weapon_id == "" or _world == null or _viewmodel == null:
		return false
	_world.set_weapon(weapon_id)
	var painted: bool = _viewmodel.set_weapon(weapon_id)
	_world.set_viewmodel_visible(not painted)
	return painted


# =================================================================================================
# LA POSE A CHANGÉ — CE QUI RESTE À FAIRE CÔTÉ VUE
# =================================================================================================
# ╔═ IL N'Y A PLUS RIEN À RECALER, ET C'EST TOUT L'INTÉRÊT DU PIVOT ══════════════════════════════╗
# ║ Cette fonction chargeait un décor peint, poussait sa texture dans un shader, éteignait le      ║
# ║ greybox et rallumait un ciel de repli — quatre états à tenir synchronisés à chaque pas de      ║
# ║ côté. C'est là que le défaut « il n'y a pas de tranchée » s'est logé.                          ║
# ║ La caméra TRANSLATE désormais physiquement entre les positions (`set_pose`) dans un monde qui  ║
# ║ existe : la parallaxe d'un pas de côté est celle du monde réel, gratuite et juste. Il ne reste ║
# ║ donc à prévenir que l'habillage, qui suit la POSTURE — accroupi, il n'y a plus de lointain.    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _refresh_pose_view() -> void:
	if _ambient != null:
		_ambient.set_stance(_pred_stance)


# =================================================================================================
# RÉSEAU
# =================================================================================================
func _on_init(msg: Dictionary) -> void:
	_rules = msg.get("rules", {})
	_my_slot = int(msg.get("your_slot", 1))
	_training = bool(msg.get("training", false))
	_opponent = msg.get("opponent", {})
	_tick_rate = float(_rules.get("tick_rate_hz", 10))
	_positions = int(_rules.get("positions", 5))
	_pred_pos = _positions / 2
	_world.set_pose(_pred_pos, _pred_stance, true)
	_world.set_enemy_accent(_enemy_accent())
	_refresh_pose_view()

	var opp_name := str(_opponent.get("name", ""))
	if bool(_opponent.get("is_bot", false)) or opp_name == "":
		opp_name = tr("TRENCH_BOT_NAME")
	_their_name.text = opp_name + ("  ·  " + tr("TRENCH_VS_BOT_NOTE") if _training else "")
	if _tune_hint != null:
		_tune_hint.visible = _training
	var state = msg.get("state")
	if typeof(state) == TYPE_DICTIONARY:
		_push_state(state)
		# L'arme vient de l'ÉTAT, pas d'un événement : à la reconnexion en pleine manche, l'escalade
		# a déjà eu lieu et son événement est passé depuis longtemps.
		_apply_weapon(str(_player_of(state, _my_slot).get("weapon", STARTING_WEAPON)))
		_waiting_label.visible = false
	else:
		_waiting_label.text = tr("TRENCH_WAITING_OPPONENT")
		_waiting_label.visible = true


# Accent de faction du soldat d'en face (§1.8 : « l'accent de couleur d'une faction du jeu »).
# ⚙ Le duel ne transporte pas encore la faction de l'adversaire : on en dérive une STABLE depuis
# son pseudo, pour que le même adversaire porte toujours la même couleur. Le jour où `trench_init`
# gagnera un champ `faction`, c'est cette seule fonction qu'il faudra rouvrir.
func _enemy_accent() -> Color:
	var accents: Array = []
	var dir := DirAccess.open("res://resources/factions/")
	if dir != null:
		for file in dir.get_files():
			var clean := file.replace(".remap", "")
			if not clean.ends_with(".tres"):
				continue
			var res = load("res://resources/factions/" + clean)
			if res != null and res.get("accent_color") != null:
				accents.append(res.get("accent_color"))
	if accents.is_empty():
		return COL_DANGER
	var key := str(_opponent.get("name", "")) + str(3 - _my_slot)
	return accents[absi(key.hash()) % accents.size()]


func _on_state(msg: Dictionary) -> void:
	_waiting_label.visible = false
	_push_state(msg)
	for event in msg.get("events", []):
		if typeof(event) == TYPE_DICTIONARY:
			_on_duel_event(event)


func _push_state(state: Dictionary) -> void:
	_buffer.append({"at": _now(), "data": state})
	while _buffer.size() > 16:
		_buffer.pop_front()
	# Réconciliation SILENCIEUSE (§2.4) : si le serveur me voit ailleurs que ma prédiction deux
	# états de suite, c'est lui qui a raison — on se cale sans un mot.
	var me := _player_of(state, _my_slot)
	if not me.is_empty() and me.get("pos") != null:
		if int(me.get("pos")) != _pred_pos:
			_mismatch_streak += 1
			if _mismatch_streak >= 2:
				_pred_pos = int(me.get("pos"))
				_refresh_pose_view()
				_mismatch_streak = 0
		else:
			_mismatch_streak = 0
	# Mémoire des projectiles (pour rien perdre d'un impact entre deux états).
	var seen := {}
	for proj in state.get("projectiles", []):
		seen[int(proj.get("id", 0))] = true
		_known_projectiles[int(proj.get("id", 0))] = proj
	for pid in _known_projectiles.keys().duplicate():
		if not seen.has(pid):
			_known_projectiles.erase(pid)


func _on_duel_event(event: Dictionary) -> void:
	var kind := str(event.get("type", ""))
	match kind:
		"round_start":
			_show_banner(tr("TRENCH_ROUND") % int(event.get("round_no", 1)), COL_ACCENT)
		"fire":
			if int(event.get("slot", 0)) == _my_slot:
				# RECUL : kick de caméra + recul du modèle (§5.4).
				_recoil = 1.0
				# Depuis §8.138, le tween de recul s'applique au VIEWMODEL 2D peint.
				_viewmodel.notify_fire()
		"grenade_thrown":
			# L'ADVERSAIRE arme et lance : frame `throw` du sprite peint (§8.138). Mon propre
			# lancer ne déclenche rien — je ne me vois pas lancer, je vois mes mains.
			if int(event.get("slot", 0)) != _my_slot:
				_world.set_enemy_action("throw")
		"laser":
			# Le laser CONDOR adverse est rendu DÈS l'événement (la lisibilité de la menace est
			# une règle de design, §5.3) — avec la VRAIE direction du tireur.
			if int(event.get("slot", 0)) != _my_slot:
				_enemy_laser_yaw = float(event.get("aim_yaw", 0.0))
				_enemy_laser_pitch = float(event.get("aim_pitch", 0.0))
				_enemy_laser_pos = int(event.get("from_pos", 2))
		"hit":
			var victim := int(event.get("slot", 0))
			if victim != _my_slot:
				# Réaction de douleur du sprite peint (§8.138) — elle suit la VICTIME et non
				# l'auteur : une grenade peut toucher l'adversaire sans que ce soit mon tir.
				_world.set_enemy_action("hit")
			if int(event.get("by", 0)) == _my_slot:
				# HITMARKER — UNIQUEMENT sur confirmation serveur (§5.5). Jamais optimiste.
				_hitmarker = 0.35
				_enemy_hit = 0.35
			if victim == _my_slot:
				_hurt_flash = 0.5
				_hurt_dir = _last_seen_enemy_pos - float(_pred_pos)
		"escalation", "weapon_chosen":
			if int(event.get("slot", 0)) == _my_slot:
				_apply_weapon(str(event.get("weapon", STARTING_WEAPON)))
				if kind == "weapon_chosen":
					_choice_panel.visible = false
					_capture_mouse(not _match_over)
				_show_banner(tr("TRENCH_ESCALATION") % _weapon_name(str(event.get("weapon", ""))),
					COL_GOLD)
		"weapon_choice":
			if int(event.get("slot", 0)) == _my_slot:
				_open_choice(event)
		"round_end":
			var winner := int(event.get("winner_slot", 0))
			if winner == 0:
				_show_banner(tr("TRENCH_ROUND_TIE"), COL_MUTED)
			elif winner == _my_slot:
				_show_banner(tr("TRENCH_ROUND_WON"), COL_ACCENT)
			else:
				_show_banner(tr("TRENCH_ROUND_LOST"), COL_DANGER)
		"match_end":
			_match_over = true
			_charging = false
			get_tree().create_timer(1.2).timeout.connect(func():
				if _result.is_empty():
					_show_result({}))


func _on_result(msg: Dictionary) -> void:
	_result = msg
	_show_result(msg)


func _on_connection_lost(_code: int) -> void:
	if _match_over:
		return
	_conn_banner.visible = true
	get_tree().create_timer(RECONNECT_DELAY).timeout.connect(func():
		if not _match_over and is_inside_tree():
			NetworkManager.retry_connection())


func _on_reconnected() -> void:
	_conn_banner.visible = false


func _on_game_error(message: String) -> void:
	if NetworkManager.last_error_reason == "trench_room_gone":
		_back_to_hub()
	elif message != "":
		_show_banner(message, COL_DANGER)


# =================================================================================================
# ENTRÉES
# =================================================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				accept_event()
				if not _match_over:
					_abandon_overlay.visible = not _abandon_overlay.visible
					_capture_mouse(not _abandon_overlay.visible)
				return
			KEY_S, KEY_CTRL:
				# POSTURE = une BASCULE (§5.6), pas un maintien : le joueur doit pouvoir rester
				# à couvert sans garder un doigt en tension pendant 90 s.
				_stance_toggle = not _stance_toggle
			KEY_R:
				_reload_queued = true
			KEY_1:
				if _choice_panel.visible:
					_queue_pick(0)
			KEY_2:
				if _choice_panel.visible:
					_queue_pick(1)
				else:
					_item_queued = "bandage"
			KEY_F10:
				# LE PANNEAU DE RÉGLAGE — ENTRAÎNEMENT SEULEMENT. En duel, il relâcherait la souris
				# et clouerait le joueur sur place pendant qu'un adversaire, lui, continue de
				# jouer : ce serait offrir une manche par accident.
				if _training and _tuning != null and not _match_over:
					accept_event()
					_tuning.toggle()
					_capture_mouse(not _tuning.visible)
					return
	if _match_over or _abandon_overlay.visible or _choice_panel.visible:
		return
	# VISÉE : mouvement souris relatif → lacet/site, bornés.
	# ⚠️ Le SIGNE du site vient maintenant du panneau. Le testeur a rapporté « le mouvement de la
	# souris est inversé » sur un axe qui ne l'était pas — parce qu'une caméra qui ne tourne que de
	# 6° pour ±32° de visée donne exactement la même impression qu'un axe à l'envers. On lui donne
	# donc l'interrupteur plutôt qu'un avis, et on saura à la porte 1 lequel des deux c'était.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		var pitch_sign: float = 1.0 if _invert_y else -1.0
		_aim_yaw = clampf(_aim_yaw + motion.x * _sensitivity, -AIM_YAW_LIMIT, AIM_YAW_LIMIT)
		_aim_pitch = clampf(_aim_pitch + pitch_sign * motion.y * _sensitivity,
			-AIM_PITCH_LIMIT, AIM_PITCH_LIMIT)
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_fire_queued = true


# Les réglages du panneau F10, appliqués À LA FRAME. Le lacet et le site ENVOYÉS au serveur ne
# changent pas de nature : seules la vitesse à laquelle la souris les fait varier et ce que la
# caméra en montre vivent ici. Aucune règle, aucun barème, aucun message réseau n'en dépend —
# c'est la condition pour que ce panneau reste un réglage de CONFORT et pas un avantage.
func _apply_tuning(values: Dictionary) -> void:
	_sensitivity = float(values.get("mouse_sensitivity", _sensitivity))
	_invert_y = bool(values.get("invert_y", _invert_y))
	if _world != null:
		_world.apply_tuning(values)


func _gather_move_dir() -> int:
	var dir := 0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q):
		dir -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir += 1
	if dir == 0 and Input.get_connected_joypads().size() > 0:
		var axis := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		if absf(axis) > 0.5:
			dir = 1 if axis > 0.0 else -1
		elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
			dir = -1
		elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
			dir = 1
	return dir


func _process(delta: float) -> void:
	_clock += delta
	_decay(delta)
	if _match_over:
		_refresh_view(delta)
		return

	# --- Grenade : maintien (G ou clic droit) pour doser, lâcher pour lancer ---
	var holding := Input.is_key_pressed(KEY_G) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
		or (Input.get_connected_joypads().size() > 0
			and Input.is_joy_button_pressed(0, JOY_BUTTON_X))
	if holding and not _charging and _pred_stance == "up" and int(_my("grenades")) > 0:
		_charging = true
		_charge = 0.0
	elif holding and _charging:
		_charge = minf(1.0, _charge + delta / CHARGE_TIME)
	elif not holding and _charging:
		_charging = false
		_throw_queued = {"charge": _charge}
	if Input.get_connected_joypads().size() > 0 \
			and Input.is_joy_button_pressed(0, JOY_BUTTON_A):
		_fire_queued = true

	# --- Prédiction locale : posture et position immédiates (le ressenti ne dépend jamais du réseau) ---
	var wanted_stance := "down" if _stance_toggle else "up"
	var dir := _gather_move_dir()
	var pose_changed := false
	if wanted_stance != _pred_stance:
		_pred_stance = wanted_stance
		pose_changed = true
	if dir != 0 and _clock >= _pred_move_ready:
		var next_pos: int = clampi(_pred_pos + dir, 0, _positions - 1)
		if next_pos != _pred_pos:
			_pred_pos = next_pos
			_pred_move_ready = _clock + float(_rules.get("move_ticks", 3)) / _tick_rate
			pose_changed = true
	if pose_changed:
		_world.set_pose(_pred_pos, _pred_stance)
		_refresh_pose_view()

	# --- Envoi coalescé (10 Hz max) ---
	_send_accum += delta
	if _send_accum >= SEND_INTERVAL:
		_send_accum = 0.0
		var payload := {"move": dir, "stance": _pred_stance}
		# La VISÉE ne part QUE si elle a bougé (§2.4), arrondie au quantum — moins d'octets, et
		# le serveur garde la dernière direction connue entre deux envois.
		var quantized := Vector2(snappedf(_aim_yaw, AIM_QUANTUM), snappedf(_aim_pitch, AIM_QUANTUM))
		if not quantized.is_equal_approx(_sent_aim):
			payload["aim"] = {"yaw": quantized.x, "pitch": quantized.y}
			_sent_aim = quantized
		if _fire_queued:
			payload["fire"] = true
		if not _throw_queued.is_empty():
			payload["throw"] = _throw_queued
		if _pick_queued != "":
			payload["pick_weapon"] = _pick_queued
		if _reload_queued:
			payload["reload"] = true
		if _item_queued != "":
			payload["item"] = _item_queued
		NetworkManager.send_trench_input(payload)
		_log_input(payload)
		_fire_queued = false
		_throw_queued = {}
		_pick_queued = ""
		_reload_queued = false
		_item_queued = ""

	_world.set_aim(_aim_yaw, _aim_pitch)
	_track_horizon()
	_refresh_view(delta)


# ╔═ LE JOURNAL DES ENTRÉES — POUR NE PLUS JAMAIS PERDRE UN SYMPTÔME ═════════════════════════════╗
# ║ « Les déplacements ne fonctionnent pas » a été rapporté en partie réelle et n'a JAMAIS été     ║
# ║ reproduit ni diagnostiqué : le chantier s'est arrêté avant. L'hypothèse retenue est que le     ║
# ║ mensonge visuel du fond peint le donnait à voir (un pas de côté décalait le décor de 2,5 %     ║
# ║ d'écran, invisible) — un monde 3D vrai devrait donc le faire disparaître.                      ║
# ║ Mais si le symptôme PERSISTE, on ne repartira pas pour une session d'hypothèses : ce journal   ║
# ║ montre à l'écran ce que le client croit envoyer, à côté de ce que le serveur lui répond.       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _log_input(payload: Dictionary) -> void:
	if _tuning == null or not _tuning.visible:
		return
	var server_pos = _player_of(_latest(), _my_slot).get("pos")
	_tuning.set_journal("move %+d · pos %d (serveur %s) · %s · verrou %.2f s\naim %.1f / %.1f"
		% [int(payload.get("move", 0)), _pred_pos,
			"?" if server_pos == null else str(int(server_pos)), _pred_stance,
			maxf(0.0, _pred_move_ready - _clock), _aim_yaw, _aim_pitch])


# L'habillage 2D (brume, braises) est posé sur une ordonnée d'écran, pas dans le monde : il lui
# faut donc savoir où la caméra a emmené l'horizon. On ne la recalcule pas — on demande au monde 3D
# de PROJETER la direction de site nul, ce qui tient compte du FOV, de l'aspect et du suivi de
# visée d'un seul coup. Une seule source, comme partout ailleurs dans ce chantier.
func _track_horizon() -> void:
	if _ambient == null or _world == null or size.y <= 0.0:
		return
	_ambient.set_horizon_ratio(clampf(_world.project_aim(_aim_yaw, 0.0).y / size.y, -0.5, 1.5))


func _decay(delta: float) -> void:
	_hitmarker = maxf(0.0, _hitmarker - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_enemy_hit = maxf(0.0, _enemy_hit - delta * 3.0)
	_recoil = maxf(0.0, _recoil - delta * 6.0)


# =================================================================================================
# INTERPOLATION + VIEW-MODEL (150 ms derrière le serveur, §2.4)
# =================================================================================================
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _latest() -> Dictionary:
	return _buffer[-1]["data"] if not _buffer.is_empty() else {}


func _player_of(state: Dictionary, slot: int) -> Dictionary:
	for player in state.get("players", []):
		if int(player.get("slot", 0)) == slot:
			return player
	return {}


func _my(field: String):
	var me := _player_of(_latest(), _my_slot)
	return me.get(field, 0)


func _render_pair() -> Array:
	var target := _now() - RENDER_DELAY
	if _buffer.size() < 2:
		return [_latest(), _latest(), 1.0]
	for i in range(_buffer.size() - 1, 0, -1):
		if _buffer[i - 1]["at"] <= target:
			var a = _buffer[i - 1]
			var b = _buffer[i]
			var span: float = maxf(0.001, b["at"] - a["at"])
			return [a["data"], b["data"], clampf((target - a["at"]) / span, 0.0, 1.0)]
	return [_buffer[0]["data"], _buffer[0]["data"], 1.0]


func _refresh_view(delta: float) -> void:
	var latest := _latest()
	if latest.is_empty():
		return
	var pair := _render_pair()
	var s0: Dictionary = pair[0]
	var s1: Dictionary = pair[1]
	var alpha: float = pair[2]
	var render_tick := lerpf(float(s0.get("tick", 0)), float(s1.get("tick", 0)), alpha)
	var their_slot := 3 - _my_slot

	# --- L'ADVERSAIRE : visible seulement si le serveur nous donne sa position (§1.6) ---
	var they0 := _player_of(s0, their_slot)
	var they1 := _player_of(s1, their_slot)
	var visible := they1.get("pos") != null
	if visible:
		var to_pos := float(they1.get("pos"))
		var from_pos: float = float(they0.get("pos")) if they0.get("pos") != null else to_pos
		_last_seen_enemy_pos = lerpf(from_pos, to_pos, alpha)

	# --- Projectiles : traçantes dans LEUR VRAIE DIRECTION, marqueurs de grenade toujours visibles ---
	var tracers: Array = []
	var grenades: Array = []
	var markers: Array = []
	for proj in s1.get("projectiles", []):
		var launch := float(proj.get("launch_tick", 0))
		var impact := float(proj.get("impact_tick", launch + 1))
		var t := clampf((render_tick - launch) / maxf(1.0, impact - launch), 0.0, 1.0)
		var mine := int(proj.get("owner_slot", 1)) == _my_slot
		if str(proj.get("kind", "")) == "grenade":
			grenades.append({"from_pos": int(proj.get("from_pos", 2)),
				"target_pos": int(proj.get("target_pos", 2)), "mine": mine, "t": t})
			markers.append({"target_pos": int(proj.get("target_pos", 2)),
				"on_my_side": not mine,
				"eta": clampf((impact - render_tick) / maxf(1.0, impact - launch), 0.0, 1.0)})
		else:
			tracers.append({"from_pos": int(proj.get("from_pos", 2)), "mine": mine, "t": t,
				"yaw": float(proj.get("aim_yaw", 0.0)),
				"pitch": float(proj.get("aim_pitch", 0.0))})

	# --- Laser CONDOR : rendu DÈS l'événement serveur, dans la direction réelle du tireur ---
	var laser := {}
	for player in s1.get("players", []):
		if int(player.get("laser_fire_tick", 0)) > int(render_tick):
			var mine := int(player.get("slot", 0)) == _my_slot
			# Le mien suit ma visée en direct ; le SIEN suit la direction annoncée par son
			# événement `laser` — et il est forcément DEBOUT pour lasériser, donc jamais masqué.
			laser = {"active": true, "mine": mine,
				"from_pos": int(player.get("pos", 2)) if player.get("pos") != null
					else _enemy_laser_pos,
				"yaw": _aim_yaw if mine else _enemy_laser_yaw,
				"pitch": _aim_pitch if mine else _enemy_laser_pitch}

	# `aiming` et `dead` pilotent la MACHINE À FRAMES du sprite peint (§8.138). Les deux se LISENT
	# dans l'état déjà reçu — `aiming` est le drapeau de lisibilité du §8.137, `dead` se déduit des
	# PV. Aucun champ n'a été ajouté au protocole pour ce lot.
	_world.render_world({
		"enemy": {"visible": visible, "pos": _last_seen_enemy_pos, "hit": _enemy_hit,
			"aiming": bool(they1.get("aiming", false)),
			"dead": float(they1.get("hp", 1)) <= 0.0},
		"tracers": tracers, "grenades": grenades, "markers": markers, "laser": laser,
	})
	_refresh_hud(latest, _player_of(s1, _my_slot), they1, render_tick)


# =================================================================================================
# COUCHE 4 — LE HUD (LOT D)
# =================================================================================================
func _make_font(tabular := false) -> Font:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed",
		"Arial Narrow", "Arial"])
	base.font_weight = 700
	if not tabular:
		return base
	# CHIFFRES TABULAIRES (`tnum`) — le compteur de munitions et le chrono changent 10 fois par
	# seconde : sans chasse fixe, ils tressautent. Même recette que `countdown_label.gd` (§8.134) ;
	# si la police système ne porte pas la fonctionnalité, la ligne est un no-op silencieux, d'où
	# les largeurs minimales réservées plus bas.
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	if ts != null:
		fv.opentype_features = {ts.name_to_tag("tnum"): 1}
	return fv


func _label(text: String, size: int, color: Color = COL_TEXT, tabular := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _make_font(tabular))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ⚠️ DEUX PIÈGES D'ANCRAGE, tous deux vus en CAPTURE sur ce dépôt (invisibles au boot headless) :
#   1. `node.anchors_preset = X` est une commodité d'ÉDITEUR — assignée en code elle ne s'applique
#      pas : la MÉTHODE `set_anchors_preset()` fait foi ;
#   2. `position` est relatif au PARENT (elle RECALCULE les offsets) — pour placer relativement à
#      l'ANCRE, ce sont `offset_left/offset_top` qu'il faut poser.
func _anchored(node: Control, preset: int, off: Vector2, box := Vector2.ZERO) -> void:
	node.set_anchors_preset(preset)
	node.offset_left = off.x
	node.offset_top = off.y
	node.offset_right = off.x + box.x
	node.offset_bottom = off.y + box.y


func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	_build_damage_feedback()
	_build_vitals()
	_build_center()
	_build_ammo()
	_build_item_slots()
	_build_reticle()
	_build_charge_gauge()
	_build_choice_panel()
	_build_abandon_overlay()


# Flash directionnel de bord d'écran + vignette rouge sous 25 PV (§5.5).
func _build_damage_feedback() -> void:
	_hurt_overlay = ColorRect.new()
	_hurt_overlay.color = Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.0)
	_hurt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hurt_overlay)

	_low_hp_vignette = ColorRect.new()
	_low_hp_vignette.color = Color(0.45, 0.05, 0.05, 0.0)
	_low_hp_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_hp_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_low_hp_vignette)


# PV haut-gauche (barre + valeur) — §6.
func _build_vitals() -> void:
	var mine := _label(str(AuthManager.username), 15, COL_ACCENT)
	_hud.add_child(mine)
	_anchored(mine, Control.PRESET_TOP_LEFT, Vector2(26, 20), Vector2(280, 20))

	var back := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = COL_MUTED
	sb.set_border_width_all(1)
	back.add_theme_stylebox_override("panel", sb)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(back)
	_anchored(back, Control.PRESET_TOP_LEFT, Vector2(26, 44), Vector2(240, 18))
	_my_hp_fill = ColorRect.new()
	_my_hp_fill.color = COL_ACCENT
	_my_hp_fill.position = Vector2(1, 1)
	_my_hp_fill.size = Vector2(238, 16)
	back.add_child(_my_hp_fill)
	_my_hp_label = _label("100", 15, COL_TEXT, true)
	_hud.add_child(_my_hp_label)
	_anchored(_my_hp_label, Control.PRESET_TOP_LEFT, Vector2(274, 43), Vector2(60, 20))

	# L'adversaire : nom + une barre FINE (l'information compte, pas la place qu'elle prend).
	_their_name = _label("", 14, COL_MUTED)
	_hud.add_child(_their_name)
	_anchored(_their_name, Control.PRESET_TOP_LEFT, Vector2(26, 72), Vector2(360, 18))
	var their_back := Panel.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0.45)
	sb2.border_color = Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.55)
	sb2.set_border_width_all(1)
	their_back.add_theme_stylebox_override("panel", sb2)
	their_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(their_back)
	_anchored(their_back, Control.PRESET_TOP_LEFT, Vector2(26, 94), Vector2(180, 9))
	_their_hp_fill = ColorRect.new()
	_their_hp_fill.color = COL_DANGER
	_their_hp_fill.position = Vector2(1, 1)
	_their_hp_fill.size = Vector2(178, 7)
	their_back.add_child(_their_hp_fill)


# Manches / score + chrono haut-centre — §6.
func _build_center() -> void:
	_timer_label = _label("—", 30, COL_TEXT, true)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_timer_label)
	_anchored(_timer_label, Control.PRESET_CENTER_TOP, Vector2(-80, 16), Vector2(160, 34))

	_round_label = _label("", 13, COL_MUTED)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_round_label)
	_anchored(_round_label, Control.PRESET_CENTER_TOP, Vector2(-110, 52), Vector2(220, 18))

	_score_label = _label("", 17, COL_GOLD, true)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_score_label)
	_anchored(_score_label, Control.PRESET_CENTER_TOP, Vector2(-110, 72), Vector2(220, 22))

	_banner = _label("", 34, COL_ACCENT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_hud.add_child(_banner)
	_anchored(_banner, Control.PRESET_CENTER, Vector2(-260, -190), Vector2(520, 46))

	_waiting_label = _label(tr("TRENCH_WAITING_OPPONENT"), 20, COL_MUTED)
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_waiting_label)
	_anchored(_waiting_label, Control.PRESET_CENTER, Vector2(-220, -20), Vector2(440, 30))

	_conn_banner = _label(tr("NET_CONNECTION_LOST"), 19, COL_DANGER)
	_conn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_conn_banner.visible = false
	_hud.add_child(_conn_banner)
	_anchored(_conn_banner, Control.PRESET_CENTER_TOP, Vector2(-220, 108), Vector2(440, 26))

	# Le rappel de la touche F10. Il ne s'allume qu'en ENTRAÎNEMENT, quand `_on_init` l'a confirmé :
	# annoncer un raccourci qui ne répond pas serait pire que de ne rien annoncer.
	_tune_hint = _label(tr("TRENCH_TUNE_HOTKEY"), 13, COL_MUTED)
	_tune_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tune_hint.visible = false
	_hud.add_child(_tune_hint)
	_anchored(_tune_hint, Control.PRESET_TOP_RIGHT, Vector2(-320, 22), Vector2(296, 20))


# Munitions bas-droite (« 06/15 », chiffres tabulaires) + arme courante — §6.
func _build_ammo() -> void:
	_ammo_label = _label("", 40, COL_TEXT, true)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_ammo_label)
	_anchored(_ammo_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -84), Vector2(230, 46))

	_reload_label = _label("", 14, COL_GOLD)
	_reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_reload_label)
	_anchored(_reload_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -38), Vector2(230, 20))

	_weapon_label = _label("", 19, COL_TEXT)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_weapon_label)
	_anchored(_weapon_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -112), Vector2(230, 24))

	_progress_label = _label("", 12, COL_MUTED)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_progress_label)
	_anchored(_progress_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -134), Vector2(230, 18))


# Cases d'objets bas-centre : 1 GRENADE (stock) · 2 BANDAGE (état) — §6.
func _build_item_slots() -> void:
	_slot_grenade = _label("", 15, COL_GOLD)
	_slot_grenade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_slot_grenade)
	_anchored(_slot_grenade, Control.PRESET_CENTER_BOTTOM, Vector2(-190, -52), Vector2(180, 22))

	_slot_bandage = _label("", 15, COL_MUTED)
	_slot_bandage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_slot_bandage)
	_anchored(_slot_bandage, Control.PRESET_CENTER_BOTTOM, Vector2(10, -52), Vector2(180, 22))


# RÉTICULE — dessiné à la MAIN parce qu'il doit vivre : son écartement montre la dispersion de
# l'arme, et il passe au rouge chargeur vide (§6). Il suit la VISÉE, pas le centre de l'écran :
# c'est ce découplage qui permet des poses de caméra fixes avec une visée libre (§1.1).
func _build_reticle() -> void:
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_reticle.size = Vector2(80, 80)
	_hud.add_child(_reticle)
	_reticle.draw.connect(_draw_reticle)


func _draw_reticle() -> void:
	var latest := _latest()
	var me := _player_of(latest, _my_slot)
	var empty := int(me.get("ammo", 1)) <= 0 or int(me.get("reload_until_tick", 0)) > 0
	var color := COL_DANGER if empty else COL_ACCENT
	var center := _reticle.size * 0.5
	# ÉCARTEMENT = dispersion de l'arme, convertie en pixels par le même champ de vision que la
	# scène 3D. Le joueur LIT donc sa précision — la promesse du CONDOR se voit avant de tirer.
	var spread := 6.0 + _dispersion_pixels()
	var arm := 7.0
	for axis: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var start := center + axis * spread
		_reticle.draw_line(start, start + axis * arm, color, 2.0)
	_reticle.draw_circle(center, 1.5, color)
	# HITMARKER — quatre traits en croix d'André, uniquement sur touche CONFIRMÉE par le serveur.
	if _hitmarker > 0.0:
		var alpha: float = clampf(_hitmarker / 0.35, 0.0, 1.0)
		var marker := Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, alpha)
		for diagonal: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			_reticle.draw_line(center + diagonal * 5.0, center + diagonal * 12.0, marker, 2.0)


# Conversion dispersion (degrés) → pixels d'écran, au champ de vision réel de la scène 3D.
func _dispersion_pixels() -> float:
	var me := _player_of(_latest(), _my_slot)
	var weapon_id := str(me.get("weapon", "vipere"))
	var degrees := 0.0
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			degrees = float(weapon.get("dispersion_deg", 0.0))
			break
	if degrees <= 0.0:
		return 0.0
	# Le champ de vision appartient à la CAMÉRA : on le demande au monde 3D plutôt que d'en
	# recopier la valeur ici (une seule source, comme partout ailleurs dans ce chantier).
	var half_fov := deg_to_rad(_world.camera_fov()) * 0.5
	return tan(deg_to_rad(degrees)) / maxf(0.001, tan(half_fov)) * (size.y * 0.5)


func _build_charge_gauge() -> void:
	_charge_back = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.border_color = COL_GOLD
	sb.set_border_width_all(1)
	_charge_back.add_theme_stylebox_override("panel", sb)
	_charge_back.visible = false
	_charge_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_charge_back)
	_anchored(_charge_back, Control.PRESET_CENTER_BOTTOM, Vector2(-90, -86), Vector2(180, 10))
	_charge_bar = ColorRect.new()
	_charge_bar.color = COL_GOLD
	_charge_bar.position = Vector2(1, 1)
	_charge_bar.size = Vector2(0, 8)
	_charge_back.add_child(_charge_bar)


func _refresh_hud(latest: Dictionary, me: Dictionary, they: Dictionary,
		render_tick: float) -> void:
	var hp_max := float(_rules.get("hp_max", 100))
	var my_hp := float(me.get("hp", 0))
	var their_hp := float(they.get("hp", 0))
	_my_hp_fill.size.x = 238.0 * clampf(my_hp / hp_max, 0.0, 1.0)
	_their_hp_fill.size.x = 178.0 * clampf(their_hp / hp_max, 0.0, 1.0)
	_my_hp_label.text = str(int(my_hp))

	# --- Munitions « 06/15 » ---
	var mag := _mag_size(str(me.get("weapon", "vipere")))
	_ammo_label.text = "%02d/%02d" % [int(me.get("ammo", 0)), mag]
	var reloading := int(me.get("reload_until_tick", 0)) > int(render_tick)
	_ammo_label.add_theme_color_override("font_color",
		COL_DANGER if (int(me.get("ammo", 0)) <= 0 or reloading) else COL_TEXT)
	_reload_label.text = tr("TRENCH_RELOADING") if reloading else ""
	# Le VIEWMODEL PEINT (§8.138) est une VUE : il ne relit pas l'état, on le lui pousse.
	_viewmodel.set_reloading(reloading)
	_viewmodel.set_recoil(_recoil)
	_weapon_label.text = _weapon_name(str(me.get("weapon", "vipere")))
	_progress_label.text = _escalation_text(int(me.get("hits_total", 0)))

	# --- Cases d'objets ---
	_slot_grenade.text = "1  " + tr("TRENCH_GRENADES") % int(me.get("grenades", 0))
	var bandaging := int(me.get("bandage_until_tick", 0)) > int(render_tick)
	var bandages := int(me.get("bandages", 0))
	if bandaging:
		_slot_bandage.text = "2  " + tr("TRENCH_HEALING")
		_slot_bandage.add_theme_color_override("font_color", COL_ACCENT)
	else:
		_slot_bandage.text = "2  " + tr("TRENCH_ITEM_BANDAGE") + ("" if bandages > 0
			else "  " + tr("TRENCH_ITEM_USED"))
		_slot_bandage.add_theme_color_override("font_color",
			COL_GOLD if bandages > 0 else COL_MUTED)

	# --- Chrono / manche / score ---
	var phase := str(latest.get("phase", ""))
	if phase == "playing":
		var remaining := maxi(0, int(_rules.get("round_ticks", 900))
			- int(render_tick - float(latest.get("round_start_tick", 0))))
		var seconds := int(ceil(float(remaining) / _tick_rate))
		_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	else:
		_timer_label.text = "—"
	_round_label.text = tr("TRENCH_ROUND") % int(latest.get("round_no", 1))
	var score: Array = latest.get("score", [0, 0])
	if score.size() >= 2:
		_score_label.text = tr("TRENCH_SCORE") % [int(score[_my_slot - 1]), int(score[2 - _my_slot])]

	# --- Réticule : il suit la VISÉE (poses fixes + visée libre, §1.1) ---
	# Type ANNOTÉ explicitement : `_world` est typé `Control`, l'appel est donc « non sûr » aux
	# yeux de l'analyseur et rend un Variant — sans annotation, `:=` ne peut rien inférer.
	var aim_screen: Vector2 = _world.project_aim(_aim_yaw, _aim_pitch)
	if _recoil > 0.0 and not _reduced_motion:
		aim_screen.y -= _recoil * 10.0     # kick vertical du recul (§5.4)
	_reticle.position = aim_screen - _reticle.size * 0.5
	_reticle.queue_redraw()

	# --- Dégâts subis ---
	_hurt_overlay.color.a = _hurt_flash * 0.45
	_low_hp_vignette.color.a = 0.30 if my_hp <= hp_max * 0.25 and my_hp > 0.0 else 0.0

	_charge_back.visible = _charging
	if _charging:
		_charge_bar.size.x = 178.0 * _charge

	if _choice_panel.visible:
		var deadline := int(_player_of(latest, _my_slot).get("choice_deadline_tick", 0))
		if deadline > 0:
			_choice_countdown.text = str(maxi(0, int(ceil((float(deadline) - render_tick)
				/ _tick_rate))))
		else:
			_choice_panel.visible = false
			_capture_mouse(not _match_over)


func _mag_size(weapon_id: String) -> int:
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			return int(weapon.get("mag_size", 0))
	return 0


func _weapon_name(weapon_id: String) -> String:
	return tr("WEAPON_" + weapon_id.to_upper())


func _escalation_text(hits: int) -> String:
	var esc: Dictionary = _rules.get("escalation", {})
	var frelon := int(esc.get("frelon_hits", 4))
	var choice := int(esc.get("choice_hits", 10))
	if hits < frelon:
		return tr("TRENCH_NEXT_WEAPON") % [hits, frelon]
	if hits < choice:
		return tr("TRENCH_NEXT_WEAPON") % [hits, choice]
	return tr("TRENCH_ARSENAL_MAX")


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(0.9)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


# =================================================================================================
# PANNEAUX (choix d'arme, abandon, résultat) — la souris est RELÂCHÉE dès qu'un clic est attendu
# =================================================================================================
func _build_choice_panel() -> void:
	_choice_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_GOLD
	sb.set_border_width_all(1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_choice_panel.add_theme_stylebox_override("panel", sb)
	_choice_panel.visible = false
	add_child(_choice_panel)
	_anchored(_choice_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-230, -240))
	var box := VBoxContainer.new()
	_choice_panel.add_child(box)
	_choice_title = _label("", 18, COL_GOLD)
	box.add_child(_choice_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_choice_buttons = []
	for i in range(2):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(190, 42)
		btn.add_theme_font_override("font", _make_font())
		btn.add_theme_font_size_override("font_size", 16)
		WarzoneUI.apply_ghost_button(btn)
		btn.pressed.connect(_queue_pick.bind(i))
		row.add_child(btn)
		_choice_buttons.append(btn)
	_choice_countdown = _label("", 22, COL_TEXT, true)
	_choice_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_choice_countdown)


func _open_choice(event: Dictionary) -> void:
	# ⚠️ RÉFÉRENCES DIRECTES, jamais get_node : les nœuds créés par code reçoivent des noms
	# auto-générés (« @VBoxContainer@N ») — un chemin littéral échouerait (défaut vu en CAPTURE).
	var options: Array = event.get("options", [])
	if options.size() < 2 or _choice_buttons.size() < 2:
		return
	var name_a := _weapon_name(str(options[0]))
	var name_b := _weapon_name(str(options[1]))
	_choice_title.text = tr("TRENCH_WEAPON_CHOICE") % [name_a, name_b]
	(_choice_buttons[0] as Button).text = "1 · " + name_a
	(_choice_buttons[1] as Button).text = "2 · " + name_b
	_choice_panel.visible = true
	_capture_mouse(false)


func _queue_pick(index: int) -> void:
	var esc: Dictionary = _rules.get("escalation", {})
	var options: Array = esc.get("choice_options", ["chacal", "condor"])
	if index >= 0 and index < options.size():
		_pick_queued = str(options[index])
	_choice_panel.visible = false
	_capture_mouse(not _match_over)


func _build_abandon_overlay() -> void:
	_abandon_overlay = _overlay_base()
	var panel := _overlay_panel(_abandon_overlay, Vector2(420, 170))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label(tr("TRENCH_ABANDON_TITLE"), 20, COL_DANGER))
	box.add_child(_label(tr("TRENCH_ABANDON_BODY"), 14, COL_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var confirm := Button.new()
	confirm.text = tr("TRENCH_ABANDON_CONFIRM")
	confirm.custom_minimum_size = Vector2(170, 40)
	confirm.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(confirm)
	confirm.pressed.connect(func():
		NetworkManager.send_trench_forfeit()
		_abandon_overlay.visible = false)
	row.add_child(confirm)
	var cancel := Button.new()
	cancel.text = tr("TRENCH_ABANDON_CANCEL")
	cancel.custom_minimum_size = Vector2(170, 40)
	cancel.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(cancel)
	cancel.pressed.connect(func():
		_abandon_overlay.visible = false
		_capture_mouse(not _match_over))
	row.add_child(cancel)


func _overlay_base() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	add_child(overlay)
	return overlay


func _overlay_panel(overlay: Control, panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_ACCENT
	sb.set_border_width_all(1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)
	_anchored(panel, Control.PRESET_CENTER, -panel_size * 0.5)
	WarzoneUI.add_corner_notches(panel)
	return panel


# =================================================================================================
# ÉCRAN DE FIN — sobre : score, coins (avec plafond affiché), progression, REJOUER / RETOUR
# =================================================================================================
func _show_result(msg: Dictionary) -> void:
	if _result_overlay != null:
		return
	_capture_mouse(false)
	_abandon_overlay.visible = false
	_choice_panel.visible = false
	_result_overlay = _overlay_base()
	_result_overlay.visible = true
	var panel := _overlay_panel(_result_overlay, Vector2(520, 380))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var latest := _latest()
	var winner := int(msg.get("winner_slot", latest.get("winner_slot", 0)))
	var won := winner == _my_slot
	box.add_child(_label(tr("TRENCH_WIN") if won else tr("TRENCH_LOSE"), 30,
		COL_GOLD if won else COL_DANGER))
	var score: Array = msg.get("score", latest.get("score", [0, 0]))
	if score.size() >= 2:
		box.add_child(_label(tr("TRENCH_SCORE") % [int(score[_my_slot - 1]),
			int(score[2 - _my_slot])], 18, COL_TEXT, true))

	if bool(msg.get("training", _training)):
		box.add_child(_label(tr("TRENCH_VS_BOT_NOTE"), 14, COL_MUTED))
	else:
		var rewards = msg.get("rewards")
		if typeof(rewards) == TYPE_DICTIONARY:
			_fill_rewards(box, rewards, bool(msg.get("vs_bot", false)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var replay := Button.new()
	replay.text = tr("TRENCH_REPLAY")
	replay.custom_minimum_size = Vector2(190, 44)
	replay.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(replay)
	replay.pressed.connect(_back_to_hub.bind(true))
	row.add_child(replay)
	var back := Button.new()
	back.text = tr("TRENCH_BACK")
	back.custom_minimum_size = Vector2(190, 44)
	back.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(back)
	back.pressed.connect(_back_to_hub.bind(false))
	row.add_child(back)

	var new_titles: Array = []
	var rewards2 = msg.get("rewards")
	if typeof(rewards2) == TYPE_DICTIONARY:
		new_titles = rewards2.get("new_titles", [])
	if not new_titles.is_empty():
		var celebration := Control.new()
		celebration.set_script(CelebrationScript)
		add_child(celebration)
		celebration.play({"name": tr("TITLE_TRENCH_" +
			str(new_titles[0].get("title_key", "")).to_upper()), "accent": COL_GOLD})


func _fill_rewards(box: VBoxContainer, rewards: Dictionary, vs_bot: bool) -> void:
	var part := int(rewards.get("participation_coins", 0))
	var part_line := tr("TRENCH_COINS_PARTICIPATION") % part
	if bool(rewards.get("participation_capped", false)):
		part_line = tr("TRENCH_DAILY_CAP")
	box.add_child(_label("❯ " + part_line, 14, COL_TEXT))
	var win_coins := int(rewards.get("win_coins", 0))
	if win_coins > 0:
		box.add_child(_label("❯ " + tr("TRENCH_COINS_WIN") % win_coins, 14, COL_GOLD))
	elif bool(rewards.get("win_capped", false)):
		box.add_child(_label("❯ " + tr("TRENCH_DAILY_CAP"), 14, COL_MUTED))
	elif vs_bot:
		box.add_child(_label("❯ " + tr("TRENCH_BOT_NO_WIN_REWARD"), 14, COL_MUTED))
	var progression = rewards.get("progression")
	if typeof(progression) == TYPE_DICTIONARY:
		var wins := int(progression.get("wins", 0))
		var level := int(progression.get("level", 0))
		var level_max := int(progression.get("level_max", 3))
		var next = progression.get("next_threshold")
		var line := tr("TRENCH_EVENT_LEVEL") % [level, level_max, wins]
		if next != null:
			line += "  ·  " + tr("TRENCH_NEXT_LEVEL") % int(next)
		box.add_child(_label(line, 14, COL_ACCENT))


func _back_to_hub(requeue := false) -> void:
	_capture_mouse(false)
	NetworkManager.leave_room()
	var events_script := load("res://scripts/ui/events_screen.gd")
	if events_script != null and requeue:
		events_script.pending_trench_requeue = true
	TransitionManager.change_scene("res://scenes/ui/events.tscn")
