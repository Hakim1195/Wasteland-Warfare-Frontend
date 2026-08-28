extends Node

# =================================================================================================
# SONDE §8.151 LOT B — « LE RÉTICULE NE MENT JAMAIS », À L'ÉPREUVE DU FEEL (probe_trench_feel_aim)
#
# ╔═ CE QU'ELLE PROUVE ═══════════════════════════════════════════════════════════════════════════╗
# ║ 1. ÉGALITÉ DE VISÉE : une séquence scriptée de 10 tirs, jouée feel AU MAXIMUM (tous les        ║
# ║    curseurs à 2,0 + punch de FOV) puis feel COUPÉ (tout à 0) → les angles figés AU POINT       ║
# ║    D'ÉMISSION (`_queue_fire` → `_fire_aim`) sont IDENTIQUES OCTET PAR OCTET entre les deux     ║
# ║    passes, ET identiques aux angles scriptés : la main du joueur, rien d'autre.                ║
# ║ 2. TEMPS DE RETOUR DU KICK (feel au max) : mesuré au pas fixe, il doit rendre l'arme sous le   ║
# ║    demi-pixel (et la caméra sous 0,05°) AVANT l'intervalle de cadence minimal — LU dans le     ║
# ║    registre des règles injecté (`rules.weapons[].cooldown_ticks / tick_rate`), jamais recopié. ║
# ║ 3. CAPTURES À FRAME FIXE (feel aux défauts livrés) : « repos 2 s » et « kick à la 6ᵉ frame »,  ║
# ║    déposées dans user://trench_feel_probe/. Deux exécutions successives de CETTE sonde doivent ║
# ║    rendre des PNG bit-identiques (porte : py tools/imagediff_trench.py <run_a> <run_b>) — la   ║
# ║    respiration est indexée sur le temps de SCÈNE, avancé ici à pas FIXES, jamais sur           ║
# ║    l'horloge murale.                                                                           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# SABOTAGE (contre-épreuve §4.3) : « -- --saboter » simule un feel qui FUIT dans la visée (écrit
# dans `_aim_pitch` entre la main et l'émission, pendant la passe MAX seulement) → l'égalité DOIT
# rougir, et la sonde imprime qu'elle l'a attrapée. Un harnais qui ne rougit pas sur la faute
# qu'il prétend traquer est un faux témoin.
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire (les captures rendent) :
#   & <godot_console> --path frontend res://tools/probe_trench_feel_aim.tscn
#   sabotage : & <godot_console> --path frontend res://tools/probe_trench_feel_aim.tscn -- --saboter
# =================================================================================================

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const TuningScript := preload("res://scripts/game/trench_tuning.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

# Pas fixes : 1/60 s pour jouer, 1/240 s pour MESURER le retour (la résolution de la mesure doit
# être plus fine que ce qu'elle mesure).
const DT_PLAY := 1.0 / 60.0
const DT_MEASURE := 1.0 / 240.0
# « Invisible » ⚙ : sous le demi-pixel, l'arrondi au pixel rend zéro ; 0,05° ≈ 1 px au FOV de 55°
# en 1080p (19,6 px/°). Ce sont les seuils de MESURE de la sonde, pas des réglages du jeu.
const PX_VISIBLE := 0.5
const DEG_VISIBLE := 0.05
# Nombre de pas de 1/60 s entre deux tirs scriptés (~0,3 s : les ressorts sont encore EN VOL au
# tir suivant — c'est exprès, une passe où le feel dort ne prouverait rien).
const STEPS_BETWEEN_SHOTS := 18
const SHOTS := 10

var _duel: Control = null
var _fails: Array = []
var _saboter := false


func _ok(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


# Le registre injecté — MÊME gabarit 20 Hz que `perf_trench._rules_20hz` (le contrat courant
# §8.141.2). La sonde ne lit AUCUNE cadence ici : elle relit `_duel._rules` une fois injecté.
func _rules_20hz() -> Dictionary:
	return {
		"tick_rate_hz": 20, "rounds_to_win": 2, "round_ticks": 1800, "positions": Geo.POSITIONS,
		"hp_max": 100, "move_ticks": 10, "intermission_ticks": 60, "grace_disconnect_ticks": 200,
		"afk_ticks": 400,
		"grenade": {"stock_start": 2, "stock_max": 3, "regen_ticks": 300, "radius_m": 2.5,
			"damage_max": 40, "flight_base_s": 0.9, "flight_per_metre_s": 0.07,
			"flight_floor_ticks": 30, "target_margin_m": 1.5},
		"weapons": [
			{"id": "vipere", "name_key": "WEAPON_VIPERE", "burst": 1, "damage": 12,
				"cooldown_ticks": 18, "flight_ticks": 1, "laser_lead_ticks": 0,
				"dispersion_deg": 0.30, "mag_size": 8, "reload_ticks": 30},
			{"id": "frelon", "name_key": "WEAPON_FRELON", "burst": 3, "damage": 5,
				"cooldown_ticks": 24, "flight_ticks": 1, "laser_lead_ticks": 0,
				"dispersion_deg": 0.85, "mag_size": 24, "reload_ticks": 40},
			{"id": "chacal", "name_key": "WEAPON_CHACAL", "burst": 2, "damage": 8,
				"cooldown_ticks": 16, "flight_ticks": 1, "laser_lead_ticks": 0,
				"dispersion_deg": 0.45, "mag_size": 20, "reload_ticks": 44},
			{"id": "condor", "name_key": "WEAPON_CONDOR", "burst": 1, "damage": 30,
				"cooldown_ticks": 50, "flight_ticks": 1, "laser_lead_ticks": 10,
				"dispersion_deg": 0.0, "mag_size": 4, "reload_ticks": 50},
		],
		"escalation": {"frelon_hits": 4, "choice_hits": 10, "choice_options": ["chacal", "condor"],
			"choice_window_ticks": 100},
		"bandage": {"enabled": true, "per_round": 1, "heal": 25, "channel_ticks": 40},
		"geometry": {"version": Geo.TABLE_VERSION, "aim_quantum_deg": 0.1,
			"positions": Geo.POSITIONS, "no_mans_land": Geo.NO_MANS_LAND,
			"position_spacing": Geo.POSITION_SPACING, "parapet_y": Geo.PARAPET_Y,
			"eye_up": Geo.EYE_UP, "eye_down": Geo.EYE_DOWN},
	}


func _ready() -> void:
	_saboter = OS.get_cmdline_user_args().has("--saboter")
	print("=== SONDE FEEL vs VISÉE (§8.151 LOT B — probe_trench_feel_aim) ===")
	print("sabotage : %s" % ("OUI (--saboter)" if _saboter else "NON"))
	print()

	DuelScript.pending_room_id = "999"
	_duel = DuelScene.instantiate()
	add_child(_duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(_duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(_duel._on_connection_lost)
	_duel._conn_banner.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_duel._on_init({"rules": _rules_20hz(), "your_slot": 1, "training": false,
		"opponent": {"name": "KOVACS", "is_bot": true}})
	# ╔═ TOUT LE TEMPS EST MANUEL ═══════════════════════════════════════════════════════════════╗
	# ║ Les `_process` du duel, du monde et du viewmodel sont COUPÉS : la sonde les appelle       ║
	# ║ elle-même à pas FIXES. C'est la condition de la reproductibilité : deux exécutions ont     ║
	# ║ alors exactement le même temps de scène à la même frame — l'horloge murale n'existe plus. ║
	# ║ L'ambiance (brume TIME + particules RNG) reste l'instabilité CONSIGNÉE du LOT 0 (§7.2,    ║
	# ║ pour le LOT E) : elle est ÉTEINTE ici, la sonde juge le FEEL, pas l'habillage.            ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	_duel.set_process(false)
	_duel._world.set_process(false)
	_duel._viewmodel.set_process(false)
	_duel._ambient.visible = false
	_duel._ambient.set_process(false)
	_push_state()
	# La caméra applique sa pose au premier pas de monde (le `_process` est manuel ici).
	_duel._world._process(DT_PLAY)

	_ok("le viewmodel est PEINT (vipere) — sans frames, le kick n'aurait rien à montrer",
		_duel._viewmodel.is_painted())

	# --- 1. LES DEUX PASSES : feel AU MAXIMUM, puis feel COUPÉ ------------------------------------
	var serie_max: Array = _fire_pass(true)
	var serie_off: Array = _fire_pass(false)
	var serie_attendue: Array = []
	for i in SHOTS:
		serie_attendue.append(var_to_bytes(Vector2(_scripted_yaw(i), _scripted_pitch(i)))
			.hex_encode())

	print()
	print("--- 1. LES DEUX SÉRIES (visée figée au point d'émission, octets de `_fire_aim`) ---")
	for i in SHOTS:
		var same: bool = serie_max[i] == serie_off[i]
		print("  tir %2d : yaw %+9.4f  pitch %+8.4f | MAX %s | OFF %s | %s" % [i + 1,
			_scripted_yaw(i), _scripted_pitch(i), serie_max[i], serie_off[i],
			"identiques" if same else "ECART"])
	if _saboter:
		# La contre-épreuve : le harnais DOIT voir la fuite qu'on vient d'injecter.
		_ok("SABOTAGE — l'écriture du feel dans la visée est ATTRAPÉE (les séries divergent)",
			serie_max != serie_off)
	else:
		_ok("10 tirs : visées MAX et COUPÉ identiques OCTET PAR OCTET", serie_max == serie_off)
		_ok("10 tirs : la visée émise EST la visée scriptée (la main, rien d'autre)",
			serie_max == serie_attendue)

	# --- 2. TEMPS DE RETOUR DU KICK (feel au max), contre le registre -----------------------------
	if not _saboter:
		print()
		print("--- 2. TEMPS DE RETOUR DU KICK — contre l'intervalle de cadence du REGISTRE ---")
		_probe_kick_return()

		# --- 3. CAPTURES à frame fixe (repos 2 s + kick 6ᵉ frame), pour la porte imagediff --------
		print()
		print("--- 3. CAPTURES à frame fixe (feel aux défauts livrés) ---")
		await _captures()

	print("\n%s" % ("TOUT VERT" if _fails.is_empty()
		else "ECHEC : " + str(_fails.size()) + " controle(s) rouge(s)"))
	get_tree().quit(0 if _fails.is_empty() else 1)


# =================================================================================================
# LA PASSE DE 10 TIRS — mêmes angles scriptés, seul le feel change
# =================================================================================================
# Angles DÉTERMINISTES, dans le débattement réel (lacet ±60°, site ±14) — pas de RNG : les deux
# passes et les deux exécutions doivent produire les mêmes octets.
func _scripted_yaw(i: int) -> float:
	return sin(float(i) * 0.7 + 0.3) * 38.0


func _scripted_pitch(i: int) -> float:
	return sin(float(i) * 0.45 + 1.1) * 6.0 - 1.0


func _apply_feel(maximum: bool) -> void:
	var values: Dictionary = TuningScript.defaults()
	for key in ["feel_recoil", "feel_shake", "feel_breath", "feel_flinch"]:
		values[key] = 2.0 if maximum else 0.0
	values["fov_punch"] = maximum
	_duel._apply_tuning(values)


func _fire_pass(feel_max: bool) -> Array:
	_apply_feel(feel_max)
	var out: Array = []
	_duel._fire_queued = false
	_duel._fire_fx_mute = 0.0
	_duel._pred_fire_ready = 0.0
	for i in SHOTS:
		# L'horloge saute LOIN devant la cadence prédite : les 10 tirs sont tous ACCEPTÉS par la
		# prédiction des six refus — un tir refusé ne figerait pas de visée du tout (§8.141.9).
		_duel._clock = 100.0 + float(i) * 10.0 + (10000.0 if feel_max else 0.0)
		_duel._aim_yaw = _scripted_yaw(i)
		_duel._aim_pitch = _scripted_pitch(i)
		if _saboter and feel_max:
			# LE SABOTAGE : un « feel » qui écrit dans la visée entre la main et l'émission —
			# exactement la faute que la sonde existe pour attraper.
			_duel._aim_pitch += 0.05
		_duel._queue_fire()
		if not _duel._fire_queued:
			_ok("passe %s, tir %d : ACCEPTÉ par la prédiction" % ["MAX" if feel_max else "OFF",
				i + 1], false, "refus inattendu")
			out.append("REFUSE")
			continue
		out.append(var_to_bytes(_duel._fire_aim).hex_encode())
		_duel._fire_queued = false
		# Le feel TOURNE entre les tirs (ressorts en vol, secousse, roulis, FOV, réticule) — une
		# passe MAX où rien ne bouge ne prouverait rien. La visée, elle, ne doit pas bouger d'un
		# octet : on la re-vérifie après chaque volée de pas.
		for _f in STEPS_BETWEEN_SHOTS:
			_duel._step_feel(DT_PLAY)
			_duel._viewmodel._process(DT_PLAY)
			_duel._world._process(DT_PLAY)
		_duel._refresh_view(DT_PLAY)
		var aim_intacte: bool = _duel._aim_yaw == _scripted_yaw(i) \
			and _duel._aim_pitch == _scripted_pitch(i)
		if not (_saboter and feel_max) and not aim_intacte:
			_ok("passe %s, tir %d : la visée est INTACTE après le feel"
				% ["MAX" if feel_max else "OFF", i + 1], false,
				"yaw %.6f pitch %.6f" % [_duel._aim_yaw, _duel._aim_pitch])
	return out


# =================================================================================================
# LE TEMPS DE RETOUR — mesuré au pas fixe, comparé au registre (jamais recopié)
# =================================================================================================
# L'intervalle de cadence MINIMAL du registre injecté : min(cooldown_ticks) / tick_rate, relu dans
# `_duel._rules` — la même source que la prédiction de cadence du client.
func _min_cadence_interval() -> float:
	var tick_rate: float = float(_duel._rules.get("tick_rate_hz", 20))
	var min_ticks := INF
	for weapon in _duel._rules.get("weapons", []):
		min_ticks = minf(min_ticks, float(weapon.get("cooldown_ticks", 0)))
	return min_ticks / maxf(tick_rate, 0.001)


func _probe_kick_return() -> void:
	_apply_feel(true)
	# Tout se pose d'abord (2 s de pas fixes) : la mesure part d'un repos propre.
	_settle(2.0)
	var interval := _min_cadence_interval()
	_duel._clock = 900.0
	_duel._pred_fire_ready = 0.0
	_duel._fire_queued = false
	_duel._aim_yaw = 0.0
	_duel._aim_pitch = 0.0
	_duel._queue_fire()
	_duel._fire_queued = false

	var horizon: float = interval + 0.5
	var t := 0.0
	var last_visible := 0.0
	var peak_px := 0.0
	while t < horizon:
		t += DT_MEASURE
		_duel._step_feel(DT_MEASURE)
		_duel._viewmodel._process(DT_MEASURE)
		var vm: Dictionary = _duel._viewmodel.feel_probe()
		var kick: Vector2 = vm["kick_px"]
		peak_px = maxf(peak_px, absf(kick.y))
		var visible: bool = absf(kick.x) >= PX_VISIBLE or absf(kick.y) >= PX_VISIBLE \
			or absf(float(vm["flinch_px"])) >= PX_VISIBLE \
			or absf(float(vm["roll_deg"])) >= DEG_VISIBLE \
			or absf(_duel._cam_roll.value) >= DEG_VISIBLE \
			or absf(_duel._fov_punch.value) >= DEG_VISIBLE
		if visible:
			last_visible = t

	print("  kick max mesuré : %.1f px (intensité F10 ×2) — pic attendu ~24 px" % peak_px)
	print("  temps de retour (arme < %.1f px ET caméra < %.2f°) : %.3f s" % [PX_VISIBLE,
		DEG_VISIBLE, last_visible])
	print("  intervalle de cadence minimal du registre : %.3f s" % interval)
	_ok("le kick est un tir SANS lendemain : retour %.3f s < cadence min %.3f s"
		% [last_visible, interval], last_visible < interval)
	_ok("le kick a bien eu lieu (pic > 10 px à intensité max)", peak_px > 10.0,
		"%.1f px" % peak_px)


func _settle(seconds: float) -> void:
	var steps := int(round(seconds / DT_PLAY))
	for _i in steps:
		_duel._step_feel(DT_PLAY)
		_duel._viewmodel._process(DT_PLAY)
		_duel._world._process(DT_PLAY)


# =================================================================================================
# LES CAPTURES — feel aux DÉFAUTS livrés, temps 100 % simulé, deux clichés
# =================================================================================================
func _captures() -> void:
	var out := OS.get_user_data_dir() + "/trench_feel_probe"
	DirAccess.make_dir_recursive_absolute(out)
	_duel._apply_tuning(TuningScript.defaults())
	_duel._aim_yaw = 0.0
	_duel._aim_pitch = 0.0

	# --- « au repos 2 s » (cahier §4.3) : la respiration TOURNE, mais sur le temps de SCÈNE ------
	_settle(2.0)
	_duel._refresh_view(DT_PLAY)
	await _shot(out, "repos_2s")

	# --- le kick, exactement 6 frames de 1/60 s après le clic ------------------------------------
	_duel._clock = 2000.0
	_duel._pred_fire_ready = 0.0
	_duel._fire_queued = false
	_duel._queue_fire()
	_duel._fire_queued = false
	for _f in 6:
		_duel._step_feel(DT_PLAY)
		_duel._viewmodel._process(DT_PLAY)
		_duel._world._process(DT_PLAY)
	_duel._refresh_view(DT_PLAY)
	await _shot(out, "kick_frame6")
	print("  [CAPTURES] %s" % out)
	print("  (deux exécutions de la sonde → deux jeux → py tools/imagediff_trench.py doit dire OK)")


# ⚠️ CETTE SONDE LOGGAIT DEUX `ERROR` EN SORTANT « TOUT VERT » (correctif §8.151 2bis). En pur
# `--headless`, le pilote d'affichage ne rend RIEN : `get_viewport().get_texture().get_image()`
# renvoie `null`, et le `save_png` dessus produisait « Parameter "t" is null. » + « Cannot call
# method 'save_png' on a null value. » — deux lignes qui vivaient HORS des contrôles PASS/FAIL,
# donc invisibles au verdict. La doctrine maison est « un boot propre = 0 ligne ERROR » : une
# sonde de référence qui en produit à chaque passe entraîne à ignorer la colonne ERROR, et c'est
# comme ça qu'on rate la vraie. On DÉCLARE donc l'absence de rendu au lieu de la subir.
func _shot(out: String, name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	# ⚠️ LA GARDE EST AVANT `get_image()`, PAS APRÈS. Sous le pilote « headless », c'est
	# `texture_2d_get` du stockage DUMMY qui logge lui-même « Parameter "t" is null. » : tester le
	# retour de `get_image()` arrive TROP TARD, la ligne ERROR est déjà écrite. On interroge donc
	# l'affichage avant de demander quoi que ce soit au rendu.
	if DisplayServer.get_name() == "headless":
		print("  [SHOT] %s.png IGNORE — aucun rendu sous --headless. Les captures de cette sonde"
			% name_)
		print("         exigent un vrai pilote : relancer SANS --headless pour les produire.")
		return
	var tex := get_viewport().get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		print("  [SHOT] %s.png IGNORE — le viewport n'a rien rendu (affichage : %s)."
			% [name_, DisplayServer.get_name()])
		return
	img.save_png("%s/%s.png" % [out, name_])
	print("  [SHOT] %s.png" % name_)


func _push_state() -> void:
	# UN SEUL état, jamais deux : à deux états, `_render_pair()` interpole sur l'HORLOGE MURALE et
	# la capture cesse d'être rejouable. L'adversaire est SANS position (`pos: null`, redaction
	# §1.6) : il ne se dessine pas — la sonde juge le feel, pas le soldat.
	_duel._on_state({"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": 8, "bandages": 1, "aiming": false, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": null, "stance": "up", "hp": 100, "weapon": "vipere",
				"hits_total": 0, "grenades": 2, "ammo": 8, "bandages": 1, "aiming": false,
				"hidden": true, "choice_deadline_tick": 0, "laser_fire_tick": 0,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false}],
		"projectiles": [], "events": []})
