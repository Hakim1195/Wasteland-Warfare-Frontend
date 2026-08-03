extends Control
# =================================================================================================
# LA TRANCHÉE (§8.136) — CONTRÔLEUR du duel 1v1 temps réel (mini-jeu de l'onglet BONUS).
#
# La scène est 100 % code-driven (patron company_screen/events_screen) : la vue pure
# `trench_render.gd` dessine le champ de bataille depuis un view-model reconstruit CHAQUE frame ;
# ce script tient le réseau, les entrées, l'interpolation et le HUD — AUCUNE règle de jeu (le
# serveur est seul autoritaire, la simulation vit dans backend/api/game/trench_sim.py).
#
# RÉSEAU (§2.3/§2.4 du chantier) :
#   • entrées envoyées À PLAT (`trench_input`) au plus toutes les SEND_INTERVAL — coalescées ici
#     (dernière direction/posture, clic de tir jamais perdu) ; le serveur JETTE le surplus ;
#   • rendu interpolé RENDER_DELAY (150 ms) derrière le dernier `trench_state` (tampon d'états) ;
#   • SEULE exception : posture/position du joueur LOCAL appliquées IMMÉDIATEMENT (prédiction),
#     réconciliées EN SILENCE si le serveur diverge deux états de suite. RIEN d'autre n'est prédit
#     — à 10 Hz avec des projectiles >= 0,3 s, c'est suffisant (ne pas sophistiquer, §2.4).
#
# ENTRÉES (§5.2) : ◀▶/Q/A/D = position · S/▼/clic droit MAINTENU = accroupi · ESPACE maintenu =
# grenade (jauge + arc) · clic gauche = tir · 1/2 = choix d'arme · ÉCHAP = abandon (confirmation).
# Manette : stick/croix = position, A(bas) = tir, B(droite) = accroupi, X(gauche) = grenade.
# =================================================================================================

const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")
const RenderScript := preload("res://scripts/game/trench_render.gd")
const CelebrationScript := preload("res://scripts/ui/unlock_celebration.gd")

# Cadence d'envoi : STRICTEMENT sous les 10 msg/s du serveur (anti-flood §2.3) — à 0,1 s pile, la
# gigue ferait parfois tomber 11 messages dans la même seconde serveur et le 11ᵉ (peut-être un
# TIR) serait jeté. 0,105 s garantit <= 10 par seconde pleine.
const SEND_INTERVAL := 0.105
# Retard de rendu : 150 ms derrière le dernier état (tampon 2 états à 10 Hz, §2.4).
const RENDER_DELAY := 0.15
# Temps de charge PLEINE de la grenade (UX pure — le DOSAGE, lui, suit le barème serveur).
const CHARGE_TIME := 1.2
# Reconnexion unique 2 s après une coupure (même politique que l'arène §8.118).
const RECONNECT_DELAY := 2.0

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
var _buffer: Array = []            # [{at: float, data: Dictionary}] — états serveur horodatés local
var _result: Dictionary = {}       # message trench_result (récompenses personnelles)
var _match_over := false
var _tick_rate := 10.0

# --- Prédiction locale (position/posture UNIQUEMENT) ---------------------------------------------
var _pred_pos: int = 2
var _pred_stance: String = "up"
var _pred_move_ready := 0.0
var _mismatch_streak := 0

# --- Entrées coalescées entre deux envois --------------------------------------------------------
var _send_accum := 0.0
var _fire_queued := false
var _throw_queued: Dictionary = {}
var _pick_queued := ""
var _charging := false
var _charge := 0.0

# --- FX éphémères (durées courtes, purgées au vol) -----------------------------------------------
var _muzzle: Dictionary = {}       # slot -> reste (s)
var _hitflash: Dictionary = {}     # slot -> reste (s)
var _explosions: Array = []        # {pos, on_mine_side, t}
var _known_projectiles: Dictionary = {}   # id -> proj (pour déclencher l'explosion à l'impact)
var _reduced_motion := false
var _clock := 0.0

# --- HUD -----------------------------------------------------------------------------------------
var _render: Node2D
var _hud: Control
var _my_hp_fill: ColorRect
var _their_hp_fill: ColorRect
var _my_hp_label: Label
var _their_hp_label: Label
var _their_name: Label
var _weapon_label: Label
var _progress_label: Label
var _grenade_label: Label
var _timer_label: Label
var _score_label: Label
var _banner: Label
var _charge_bar: ColorRect
var _charge_back: Panel
var _choice_panel: PanelContainer
var _choice_countdown: Label
var _choice_title: Label
var _choice_buttons: Array = []
var _waiting_label: Label
var _conn_banner: Label
var _result_overlay: Control
var _abandon_overlay: Control
var _banner_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_reduced_motion = bool(SettingsManager.get_comfort("reduced_motion"))

	_render = Node2D.new()
	_render.set_script(RenderScript)
	add_child(_render)
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
	NetworkManager.connect_to_server(pending_room_id)


func _exit_tree() -> void:
	pending_room_id = ""


# =================================================================================================
# RÉSEAU
# =================================================================================================
func _on_init(msg: Dictionary) -> void:
	_rules = msg.get("rules", {})
	_my_slot = int(msg.get("your_slot", 1))
	_training = bool(msg.get("training", false))
	_opponent = msg.get("opponent", {})
	_tick_rate = float(_rules.get("tick_rate_hz", 10))
	var opp_name := str(_opponent.get("name", ""))
	if bool(_opponent.get("is_bot", false)) or opp_name == "":
		opp_name = tr("TRENCH_BOT_NAME")
	_their_name.text = opp_name + ("  ·  " + tr("TRENCH_VS_BOT_NOTE") if _training else "")
	var state = msg.get("state")
	if typeof(state) == TYPE_DICTIONARY:
		_push_state(state)
		_waiting_label.visible = false
	else:
		_waiting_label.text = tr("TRENCH_WAITING_OPPONENT")
		_waiting_label.visible = true


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
	if not me.is_empty():
		if int(me.get("pos", _pred_pos)) != _pred_pos:
			_mismatch_streak += 1
			if _mismatch_streak >= 2:
				_pred_pos = int(me.get("pos", _pred_pos))
				_mismatch_streak = 0
		else:
			_mismatch_streak = 0
	# L'impact d'un projectile disparu déclenche son explosion (grenades surtout).
	var seen := {}
	for proj in state.get("projectiles", []):
		seen[int(proj.get("id", 0))] = true
		_known_projectiles[int(proj.get("id", 0))] = proj
	for pid in _known_projectiles.keys().duplicate():
		if not seen.has(pid):
			var gone: Dictionary = _known_projectiles[pid]
			if str(gone.get("kind", "")) == "grenade":
				_explosions.append({"pos": float(gone.get("target_pos", 2)),
					"on_mine_side": int(gone.get("owner_slot", 1)) != _my_slot,
					"t": 0.0})
			_known_projectiles.erase(pid)


func _on_duel_event(event: Dictionary) -> void:
	var kind := str(event.get("type", ""))
	match kind:
		"round_start":
			_show_banner(tr("TRENCH_ROUND") % int(event.get("round_no", 1)), COL_ACCENT)
		"fire":
			_muzzle[int(event.get("slot", 0))] = 0.12
		"hit":
			var victim := int(event.get("slot", 0))
			_hitflash[victim] = 0.35
			if int(event.get("by", 0)) == _my_slot:
				_show_banner(tr("TRENCH_HIT"), COL_GOLD)
			elif victim == _my_slot and not _reduced_motion:
				_shake()
		"escalation":
			if int(event.get("slot", 0)) == _my_slot:
				_show_banner(tr("TRENCH_ESCALATION") % _weapon_name(str(event.get("weapon", ""))),
					COL_GOLD)
		"weapon_choice":
			if int(event.get("slot", 0)) == _my_slot:
				_open_choice(event)
		"weapon_chosen":
			if int(event.get("slot", 0)) == _my_slot:
				_choice_panel.visible = false
				_show_banner(tr("TRENCH_ESCALATION") % _weapon_name(str(event.get("weapon", ""))),
					COL_GOLD)
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
			# L'écran de fin attend le `trench_result` PERSONNEL (récompenses) ; s'il n'arrive pas
			# (entraînement interrompu, panne), on ouvre quand même après un court délai.
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
	# Salle disparue (redémarrage serveur) : le duel n'existe plus, on rentre proprement.
	if NetworkManager.last_error_reason == "trench_room_gone":
		_back_to_hub()
	elif message != "":
		_show_banner(message, COL_DANGER)


# =================================================================================================
# ENTRÉES → envoi coalescé (10 Hz max)
# =================================================================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			accept_event()
			if not _match_over:
				_abandon_overlay.visible = not _abandon_overlay.visible
		elif event.keycode == KEY_1 and _choice_panel.visible:
			_queue_pick(0)
		elif event.keycode == KEY_2 and _choice_panel.visible:
			_queue_pick(1)
	if _match_over:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_fire_queued = true


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


func _gather_stance() -> String:
	var down := Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not down and Input.get_connected_joypads().size() > 0:
		down = Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	return "down" if down else "up"


func _process(delta: float) -> void:
	_clock += delta
	if _match_over:
		_refresh_view(delta)
		return

	# --- Grenade : maintien pour doser (jauge + arc), lâcher pour lancer ---
	var space := Input.is_key_pressed(KEY_SPACE) \
		or (Input.get_connected_joypads().size() > 0
			and Input.is_joy_button_pressed(0, JOY_BUTTON_X))
	if space and not _charging and _pred_stance == "up" and _my("grenades") > 0:
		_charging = true
		_charge = 0.0
	elif space and _charging:
		_charge = minf(1.0, _charge + delta / CHARGE_TIME)
	elif not space and _charging:
		_charging = false
		_throw_queued = {"charge": _charge}
	if Input.get_connected_joypads().size() > 0 \
			and Input.is_joy_button_pressed(0, JOY_BUTTON_A):
		_fire_queued = true

	# --- Prédiction locale : posture immédiate, pas de position à la cadence du serveur ---
	_pred_stance = _gather_stance()
	var dir := _gather_move_dir()
	if dir != 0 and _clock >= _pred_move_ready:
		var count := int(_rules.get("positions", 5))
		var next_pos: int = clampi(_pred_pos + dir, 0, count - 1)
		if next_pos != _pred_pos:
			_pred_pos = next_pos
			_pred_move_ready = _clock + float(_rules.get("move_ticks", 3)) / _tick_rate

	# --- Envoi coalescé ---
	_send_accum += delta
	if _send_accum >= SEND_INTERVAL:
		_send_accum = 0.0
		var input := {"move": dir, "stance": _pred_stance}
		if _fire_queued:
			input["fire"] = true
		if not _throw_queued.is_empty():
			input["throw"] = _throw_queued
		if _pick_queued != "":
			input["pick_weapon"] = _pick_queued
		NetworkManager.send_trench_input(input)
		_fire_queued = false
		_throw_queued = {}
		_pick_queued = ""

	_refresh_view(delta)


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
	# Les deux états qui ENCADRENT l'instant de rendu (now - 150 ms) + le facteur d'interpolation.
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

	# FX éphémères.
	for slot in _muzzle.keys().duplicate():
		_muzzle[slot] = maxf(0.0, _muzzle[slot] - delta)
	for slot in _hitflash.keys().duplicate():
		_hitflash[slot] = maxf(0.0, _hitflash[slot] - delta)
	for explosion in _explosions:
		explosion["t"] = float(explosion["t"]) + delta * 1.8
	_explosions = _explosions.filter(func(e): return float(e["t"]) < 1.0)

	# Adversaire : INTERPOLÉ. Moi : PRÉDIT (posture/position immédiates).
	var they0 := _player_of(s0, their_slot)
	var they1 := _player_of(s1, their_slot)
	var me1 := _player_of(s1, _my_slot)
	var mine := {
		"pos": float(_pred_pos), "stance": _pred_stance,
		"muzzle": _muzzle.get(_my_slot, 0.0) * 8.0,
		"hit": _hitflash.get(_my_slot, 0.0) * 3.0,
		"disconnected": false,
	}
	var theirs := {
		"pos": lerpf(float(they0.get("pos", 2)), float(they1.get("pos", 2)), alpha),
		"stance": str(they1.get("stance", "up")),
		"muzzle": _muzzle.get(their_slot, 0.0) * 8.0,
		"hit": _hitflash.get(their_slot, 0.0) * 3.0,
		"disconnected": bool(they1.get("disconnected", false)),
	}

	# Projectiles + marqueurs + lasers depuis le DERNIER état (positions par interpolation du tick).
	var projectiles: Array = []
	var markers: Array = []
	for proj in s1.get("projectiles", []):
		var launch := float(proj.get("launch_tick", 0))
		var impact := float(proj.get("impact_tick", launch + 1))
		var t := clampf((render_tick - launch) / maxf(1.0, impact - launch), 0.0, 1.0)
		var up := int(proj.get("owner_slot", 1)) == _my_slot
		projectiles.append({"kind": str(proj.get("kind", "")), "up": up, "t": t,
			"from_pos": float(proj.get("from_pos", 2)),
			"target_pos": float(proj.get("target_pos", 2))})
		if str(proj.get("kind", "")) == "grenade":
			markers.append({"target_pos": int(proj.get("target_pos", 2)),
				"on_mine_side": not up,
				"eta": clampf((impact - render_tick) / maxf(1.0, impact - launch), 0.0, 1.0)})
	var lasers: Array = []
	for player in s1.get("players", []):
		if int(player.get("laser_fire_tick", 0)) > int(render_tick):
			var up := int(player.get("slot", 0)) == _my_slot
			var shooter_pos: float = mine["pos"] if up else theirs["pos"]
			var target_pos: float = theirs["pos"] if up else mine["pos"]
			lasers.append({"up": up, "from_pos": shooter_pos, "target_pos": target_pos})

	var charge_view := {"active": _charging, "charge": _charge,
		"target_pos": _charge_target(_charge)}

	_render.set_view({
		"positions": int(_rules.get("positions", 5)),
		"reduced_motion": _reduced_motion,
		"time": _clock,
		"mine": mine, "theirs": theirs,
		"projectiles": projectiles, "markers": markers, "lasers": lasers,
		"charge": charge_view, "explosions": _explosions,
	})
	_refresh_hud(latest, me1, they1, render_tick)


func _charge_target(charge: float) -> int:
	# MIROIR EXACT du serveur (`trench_sim.grenade_target_pos`) : arrondi DEMI-SUPÉRIEUR — c'est
	# documenté au contrat §2.3, l'aperçu ne doit jamais mentir sur la position d'arrivée.
	var count := int(_rules.get("positions", 5))
	return mini(count - 1, int(clampf(charge, 0.0, 1.0) * float(count - 1) + 0.5))


# =================================================================================================
# HUD
# =================================================================================================
func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed",
		"Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


func _label(text: String, size: int, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _make_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# ⚠️ DEUX PIÈGES D'ANCRAGE, tous deux vus en CAPTURE (invisibles au boot headless) :
#   1. `node.anchors_preset = X` est une commodité d'ÉDITEUR — assignée en code elle ne s'applique
#      pas : la MÉTHODE `set_anchors_preset()` fait foi ;
#   2. `position` est relatif au PARENT (elle RECALCULE les offsets) — pour placer relativement à
#      l'ANCRE, ce sont `offset_left/offset_top` qu'il faut poser.
func _anchored(node: Control, preset: int, off: Vector2) -> void:
	node.set_anchors_preset(preset)
	node.offset_left = off.x
	node.offset_top = off.y
	node.offset_right = off.x
	node.offset_bottom = off.y


func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	# --- Plaque ADVERSAIRE (haut gauche) ---
	_their_name = _label("", 18, COL_TEXT)
	_their_name.position = Vector2(24, 14)
	_hud.add_child(_their_name)
	var their_bar := _hp_bar(Vector2(24, 40))
	_their_hp_fill = their_bar[0]
	_their_hp_label = their_bar[1]
	_their_hp_fill.color = COL_DANGER

	# --- Plaque MOI (bas gauche) ---
	var me_name := _label(str(AuthManager.username), 18, COL_ACCENT)
	_hud.add_child(me_name)
	_anchored(me_name, Control.PRESET_BOTTOM_LEFT, Vector2(24, -96))
	var my_bar := _hp_bar(Vector2(24, -70), true)
	_my_hp_fill = my_bar[0]
	_my_hp_label = my_bar[1]
	_my_hp_fill.color = COL_ACCENT

	_weapon_label = _label("", 20, COL_TEXT)
	_hud.add_child(_weapon_label)
	_anchored(_weapon_label, Control.PRESET_BOTTOM_LEFT, Vector2(24, -44))
	_progress_label = _label("", 13, COL_MUTED)
	_hud.add_child(_progress_label)
	_anchored(_progress_label, Control.PRESET_BOTTOM_LEFT, Vector2(24, -22))
	_grenade_label = _label("", 16, COL_GOLD)
	_hud.add_child(_grenade_label)
	_anchored(_grenade_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-190, -44))

	# --- Centre : chrono + score + bandeau ---
	_timer_label = _label("", 26, COL_TEXT)
	_timer_label.custom_minimum_size = Vector2(120, 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_timer_label)
	_anchored(_timer_label, Control.PRESET_CENTER_TOP, Vector2(-60, 12))
	_score_label = _label("", 16, COL_GOLD)
	_score_label.custom_minimum_size = Vector2(200, 22)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_score_label)
	_anchored(_score_label, Control.PRESET_CENTER_TOP, Vector2(-100, 46))
	_banner = _label("", 34, COL_ACCENT)
	_banner.custom_minimum_size = Vector2(400, 44)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_hud.add_child(_banner)
	_anchored(_banner, Control.PRESET_CENTER, Vector2(-200, -120))

	_waiting_label = _label(tr("TRENCH_WAITING_OPPONENT"), 22, COL_MUTED)
	_waiting_label.custom_minimum_size = Vector2(360, 32)
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_waiting_label)
	_anchored(_waiting_label, Control.PRESET_CENTER, Vector2(-180, -16))

	_conn_banner = _label(tr("NET_CONNECTION_LOST"), 20, COL_DANGER)
	_conn_banner.custom_minimum_size = Vector2(360, 30)
	_conn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_conn_banner.visible = false
	_hud.add_child(_conn_banner)
	_anchored(_conn_banner, Control.PRESET_CENTER_TOP, Vector2(-180, 80))

	# --- Jauge de grenade (au-dessus de ma plaque) ---
	_charge_back = Panel.new()
	_charge_back.custom_minimum_size = Vector2(160, 10)
	_charge_back.size = Vector2(160, 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.border_color = COL_GOLD
	sb.set_border_width_all(1)
	_charge_back.add_theme_stylebox_override("panel", sb)
	_charge_back.visible = false
	_hud.add_child(_charge_back)
	_anchored(_charge_back, Control.PRESET_BOTTOM_LEFT, Vector2(24, -122))
	_charge_bar = ColorRect.new()
	_charge_bar.color = COL_GOLD
	_charge_bar.position = Vector2(1, 1)
	_charge_bar.size = Vector2(0, 8)
	_charge_back.add_child(_charge_bar)

	_build_choice_panel()
	_build_abandon_overlay()


func _hp_bar(pos: Vector2, bottom := false) -> Array:
	var back := Panel.new()
	back.custom_minimum_size = Vector2(220, 16)
	back.size = Vector2(220, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = COL_MUTED
	sb.set_border_width_all(1)
	back.add_theme_stylebox_override("panel", sb)
	_hud.add_child(back)
	if bottom:
		_anchored(back, Control.PRESET_BOTTOM_LEFT, pos)
	else:
		back.position = pos
	var fill := ColorRect.new()
	fill.position = Vector2(1, 1)
	fill.size = Vector2(218, 14)
	back.add_child(fill)
	var value := _label("100", 12, COL_TEXT)
	value.position = Vector2(226, -1)
	back.add_child(value)
	return [fill, value]


func _refresh_hud(latest: Dictionary, me: Dictionary, they: Dictionary,
		render_tick: float) -> void:
	var hp_max := float(_rules.get("hp_max", 100))
	var my_hp := float(me.get("hp", 0))
	var their_hp := float(they.get("hp", 0))
	_my_hp_fill.size.x = 218.0 * clampf(my_hp / hp_max, 0.0, 1.0)
	_their_hp_fill.size.x = 218.0 * clampf(their_hp / hp_max, 0.0, 1.0)
	_my_hp_label.text = str(int(my_hp))
	_their_hp_label.text = str(int(their_hp))

	_weapon_label.text = _weapon_name(str(me.get("weapon", "vipere")))
	_progress_label.text = _escalation_text(int(me.get("hits_total", 0)))
	_grenade_label.text = tr("TRENCH_GRENADES") % int(me.get("grenades", 0))

	var phase := str(latest.get("phase", ""))
	if phase == "playing":
		var remaining := maxi(0, int(_rules.get("round_ticks", 900))
			- int(render_tick - float(latest.get("round_start_tick", 0))))
		var seconds := int(ceil(float(remaining) / _tick_rate))
		_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	else:
		_timer_label.text = "—"
	var score: Array = latest.get("score", [0, 0])
	var my_score := int(score[_my_slot - 1]) if score.size() >= 2 else 0
	var their_score := int(score[2 - _my_slot]) if score.size() >= 2 else 0
	_score_label.text = tr("TRENCH_SCORE") % [my_score, their_score]

	_charge_back.visible = _charging
	if _charging:
		_charge_bar.size.x = 158.0 * _charge

	if _choice_panel.visible:
		var me_latest := _player_of(latest, _my_slot)
		var deadline := int(me_latest.get("choice_deadline_tick", 0))
		if deadline > 0:
			var left := maxi(0, int(ceil((float(deadline) - render_tick) / _tick_rate)))
			_choice_countdown.text = str(left)
		else:
			_choice_panel.visible = false


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


func _shake() -> void:
	# Micro-secousse de l'écran (jamais en reduced_motion — vérifié par l'appelant).
	var tween := create_tween()
	tween.tween_property(self, "position", Vector2(4, 0), 0.04)
	tween.tween_property(self, "position", Vector2(-3, 1), 0.04)
	tween.tween_property(self, "position", Vector2.ZERO, 0.05)


# =================================================================================================
# CHOIX D'ARME (fenêtre d'escalade, 5 s)
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
	_hud.add_child(_choice_panel)
	_anchored(_choice_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-230, -190))
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
	_choice_countdown = _label("", 22, COL_TEXT)
	_choice_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_choice_countdown)


func _open_choice(event: Dictionary) -> void:
	# ⚠️ RÉFÉRENCES DIRECTES, jamais get_node : les nœuds créés par code reçoivent des noms
	# auto-générés (« @VBoxContainer@N ») — un chemin littéral échouerait (défaut vu en CAPTURE,
	# invisible au boot headless).
	var options: Array = event.get("options", [])
	if options.size() < 2 or _choice_buttons.size() < 2:
		return
	var name_a := _weapon_name(str(options[0]))
	var name_b := _weapon_name(str(options[1]))
	_choice_title.text = tr("TRENCH_WEAPON_CHOICE") % [name_a, name_b]
	(_choice_buttons[0] as Button).text = "1 · " + name_a
	(_choice_buttons[1] as Button).text = "2 · " + name_b
	_choice_panel.visible = true


func _queue_pick(index: int) -> void:
	var esc: Dictionary = _rules.get("escalation", {})
	var options: Array = esc.get("choice_options", ["chacal", "condor"])
	if index >= 0 and index < options.size():
		_pick_queued = str(options[index])
	_choice_panel.visible = false


# =================================================================================================
# ABANDON (ÉCHAP → confirmation — pause IMPOSSIBLE, temps réel §5.5)
# =================================================================================================
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
	cancel.pressed.connect(func(): _abandon_overlay.visible = false)
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
			int(score[2 - _my_slot])], 18, COL_TEXT))

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

	# Montée de niveau d'événement → célébration (unlock_celebration §5.4), par-dessus le résultat.
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
	NetworkManager.leave_room()
	var events_script := load("res://scripts/ui/events_screen.gd")
	if events_script != null and requeue:
		events_script.pending_trench_requeue = true
	TransitionManager.change_scene("res://scenes/ui/events.tscn")
