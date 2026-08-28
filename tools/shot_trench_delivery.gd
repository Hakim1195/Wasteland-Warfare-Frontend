extends Node

# =================================================================================================
# OUTIL §8.139 (LOT E) — LA RECETTE DE LIVRAISON de LA TRANCHÉE habillée.
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire (le viewport doit rendre — recette §8.100/§8.111) :
#   & <godot_console> --path frontend res://tools/shot_trench_delivery.tscn
#
# Le MÊME outil sert deux fois, et c'est tout son intérêt :
#   • assets EN PLACE   -> les images « APRÈS » de la planche de comparaison ;
#   • assets DÉPLACÉS   -> les images « AVANT », qui SONT le test de sabotage. On ne simule pas
#     l'absence en forçant une branche de code : on retire vraiment les fichiers, et on vérifie que
#     le jeu retombe sur le greybox et les primitives sans une seule erreur.
# Il imprime en tête ce qu'il a DÉTECTÉ, pour qu'une capture ne puisse jamais mentir sur son état.

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const Sprites := preload("res://scripts/game/trench_sprites.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

const RULES := {
	"tick_rate_hz": 10, "rounds_to_win": 2, "round_ticks": 900, "positions": 5, "hp_max": 100,
	"move_ticks": 3, "intermission_ticks": 30, "grace_disconnect_ticks": 100, "afk_ticks": 200,
	"grenade": {"stock_start": 2, "stock_max": 3, "regen_ticks": 150, "radius_m": 2.5,
		"damage_max": 40, "flight_base_s": 0.9, "flight_per_metre_s": 0.07,
		"flight_floor_ticks": 15, "target_margin_m": 1.5},
	"weapons": [
		{"id": "vipere", "name_key": "WEAPON_VIPERE", "burst": 1, "damage": 12,
			"cooldown_ticks": 9, "flight_ticks": 4, "laser_lead_ticks": 0, "dispersion_deg": 0.30,
			"mag_size": 8, "reload_ticks": 15},
		{"id": "frelon", "name_key": "WEAPON_FRELON", "burst": 3, "damage": 5,
			"cooldown_ticks": 12, "flight_ticks": 3, "laser_lead_ticks": 0, "dispersion_deg": 0.85,
			"mag_size": 24, "reload_ticks": 20},
		{"id": "chacal", "name_key": "WEAPON_CHACAL", "burst": 2, "damage": 8,
			"cooldown_ticks": 8, "flight_ticks": 3, "laser_lead_ticks": 0, "dispersion_deg": 0.45,
			"mag_size": 20, "reload_ticks": 22},
		{"id": "condor", "name_key": "WEAPON_CONDOR", "burst": 1, "damage": 30,
			"cooldown_ticks": 25, "flight_ticks": 3, "laser_lead_ticks": 5, "dispersion_deg": 0.0,
			"mag_size": 4, "reload_ticks": 25},
	],
	"escalation": {"frelon_hits": 4, "choice_hits": 10, "choice_options": ["chacal", "condor"],
		"choice_window_ticks": 50},
	"bandage": {"enabled": true, "per_round": 1, "heal": 25, "channel_ticks": 20},
	# ⚠️ La géométrie est LUE dans le registre partagé (patron `perf_trench.gd::_rules_20hz`) —
	# recopier une cote en dur recréerait la désynchronisation que `_check_geometry_match` traque
	# (§8.141.6). Ce fichier l'a payé (§8.151 LOT 0) : sa v1 figée à 35 m posait la bannière rouge
	# DESYNCHRONISATION + 1 ligne ERROR sur CHAQUE capture, alors que le client rend la table v4.
	"geometry": {"version": Geo.TABLE_VERSION, "aim_quantum_deg": 0.1,
		"positions": Geo.POSITIONS, "no_mans_land": Geo.NO_MANS_LAND,
		"position_spacing": Geo.POSITION_SPACING, "parapet_y": Geo.PARAPET_Y,
		"eye_up": Geo.EYE_UP, "eye_down": Geo.EYE_DOWN},
}

var _duel: Control = null
var _out := ""
var _tag := ""


func _ready() -> void:
	# Le suffixe distingue les deux passes SANS avoir à le passer en argument : c'est l'état réel
	# du disque qui nomme les fichiers, donc une capture ne peut pas se tromper d'étiquette.
	var has_decor := ResourceLoader.exists("res://assets/images/trench/pose_2_up.png")
	var has_sprite := Sprites.enemy_available()
	# Trois passes possibles, et l'étiquette se DÉDUIT du disque : « partiel » désigne le sabotage
	# ciblé (un décor et un état de sprite retirés), qui teste la GRANULARITÉ du repli — une pose
	# doit retomber sur le greybox sans entraîner les neuf autres.
	var other_decor := ResourceLoader.exists("res://assets/images/trench/pose_0_up.png")
	if has_decor and has_sprite:
		_tag = "apres"
	elif other_decor or has_sprite:
		_tag = "partiel"
	else:
		_tag = "avant"
	_out = OS.get_user_data_dir() + "/trench_delivery"
	DirAccess.make_dir_recursive_absolute(_out)
	print("=== LIVRAISON §8.139 — passe « %s » ===" % _tag)
	print("  decor pose_2_up detecte : %s" % has_decor)
	print("  sprite enemy_idle detecte : %s" % has_sprite)
	for w in ["vipere", "frelon", "chacal", "condor"]:
		print("  viewmodel %-7s peint : %s" % [w, Sprites.viewmodel_available(w)])

	SettingsManager.set_comfort("reduced_motion", false)
	SettingsManager.set_comfort("ui_scale", 1.0)
	DuelScript.pending_room_id = "999"
	_duel = DuelScene.instantiate()
	add_child(_duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(_duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(_duel._on_connection_lost)
	_duel._conn_banner.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_duel._on_init({"rules": RULES, "your_slot": 1, "training": false,
		"opponent": {"name": "KOVACS", "is_bot": false}})
	# ⚠️ `_on_init` SANS état applique l'arme de DÉPART (VIPÈRE) ; en partie, c'est l'événement
	# d'escalade qui fait passer à l'arme suivante, et cette mise en scène n'en joue aucun. Sans
	# cette ligne, la planche montrerait un revolver sous un HUD qui annonce FRELON — une capture
	# qui se contredit elle-même, et c'est LA planche que Hakim doit juger.
	_duel._apply_weapon("frelon")
	_duel.set_process(false)

	# --- 1) DEBOUT, position centrale — la vue de référence -------------------------------------
	_pose(2, "up")
	_state(2, 3, "up", true, [])
	await _wait(0.4)
	await _shot("01_debout")

	# --- 2) ACCROUPI — le joueur est à couvert et AVEUGLE ---------------------------------------
	_pose(2, "down")
	_state(2, 3, "down", false, [])
	await _wait(0.35)
	await _shot("02_accroupi")

	# --- 3) DEBOUT, position extrême — la parallaxe entre positions ------------------------------
	_pose(0, "up")
	_state(0, 4, "up", true, [])
	await _wait(0.35)
	await _shot("03_debout_position_0")

	# --- 4) UN MOMENT DE DUEL : traçantes, grenade en vol, adversaire qui encaisse ---------------
	_pose(2, "up")
	_state(2, 3, "up", true, [
		{"id": 1, "kind": "grenade", "owner_slot": 2, "from_pos": 3, "target_pos": 2,
			"launch_tick": 92, "impact_tick": 114, "aim_yaw": 0.0, "aim_pitch": 0.0},
		{"id": 2, "kind": "frelon", "owner_slot": 1, "from_pos": 2, "target_pos": 3,
			"launch_tick": 99, "impact_tick": 102, "aim_yaw": 6.2, "aim_pitch": -0.4},
	])
	_duel._hitmarker = 0.5
	_duel._enemy_hit = 0.8
	_duel._viewmodel.notify_fire()
	_duel._refresh_view(0.016)
	await _wait(0.12)
	_duel._viewmodel.notify_fire()
	await _shot("04_moment_de_duel")

	# --- 4bis) VISÉE À L'ŒIL : le point rouge dans le verre (lot 3D-I) ---------------------------
	# ⚠️ `_process` est COUPÉ sur ce banc (`set_process(false)` plus haut), donc la rampe de visée
	# ne monterait jamais toute seule. On la pousse à la main — mais par la vraie DÉCISION
	# (`_apply_ads`) et le vrai PAS (`_step_feel`), jamais en écrivant `_ads_hud` : une capture qui
	# forcerait la variable montrerait un point que le jeu ne sait peut-être pas allumer.
	_duel._hitmarker = 0.0
	_duel._enemy_hit = 0.0
	_state(2, 3, "up", true, [])
	_duel._apply_ads(true)
	await _wait(0.9)
	await _shot("04b_visee_point_rouge")
	_duel._apply_ads(false)
	await _wait(0.6)

	# --- 5) RECETTE DE CONFORT : les deux bornes d'échelle d'UI, puis mouvement réduit -----------
	_state(2, 3, "up", true, [])
	for value in [0.9, 1.3]:
		_duel.scale = Vector2(value, value)
		_duel._refresh_view(0.016)
		await _wait(0.2)
		await _shot("05_ui_scale_%d" % int(value * 100.0))
	_duel.scale = Vector2.ONE

	_duel._ambient.set_reduced_motion(true)
	_duel._viewmodel.set_reduced_motion(true)
	await _wait(0.3)
	await _shot("06_reduced_motion")

	# --- 7) PERFORMANCE ------------------------------------------------------------------------
	# ⚠️ LE BON DE COMMANDE ATTEND « AUCUNE CHUTE vs greybox », en supposant que les décors sont des
	# textures statiques et donc gratuits. C'est vrai des DÉCORS — mais le LOT D ajoute 100
	# particules GPU et un étalonnage qui LIT L'ÉCRAN (donc une copie d'arrière-plan par frame). On
	# ne peut pas annoncer « coût nul » sans mentir : on le mesure, on le publie, et Hakim arbitre.
	_duel._ambient.set_reduced_motion(false)
	_duel._viewmodel.set_reduced_motion(false)
	_pose(2, "up")
	_state(2, 3, "up", true, [])
	print("\n=== PERFORMANCE (temps par frame, moyenne sur 150 frames) ===")
	# ⚠️⚠️ SANS CETTE LIGNE, LA MESURE EST UN FAUX VERT. Premier essai : les trois configurations
	# rendaient 13,33 ms — c'est-à-dire 75,00 FPS pile, la fréquence de l'écran. On ne mesurait pas
	# le coût du rendu, on mesurait la SYNCHRO VERTICALE, qui absorbe toute différence tant qu'on
	# reste sous le budget de frame. Trois nombres identiques n'y prouvaient rien : ils prouvaient
	# seulement que la carte attendait le balayage.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().create_timer(0.3).timeout
	var full := await _bench("decor peint + habillage complet")
	_duel._grade.visible = false
	var no_grade := await _bench("decor peint, SANS etalonnage")
	_duel._ambient.visible = false
	var bare := await _bench("decor peint, SANS habillage du tout")
	_duel._grade.visible = true
	_duel._ambient.visible = true
	print("  -> surcout de l'habillage : %+.2f ms/frame (%+.1f %%), dont %+.2f ms pour l'etalonnage"
		% [(full - bare) * 1000.0, 100.0 * (full - bare) / maxf(bare, 0.0001),
			(full - no_grade) * 1000.0])

	print("[SHOTS] %s" % _out)
	get_tree().quit(0)


# Moyenne du temps de frame, les 30 premières écartées : le temps que le pilote compile ses
# pipelines et que les particules atteignent leur régime, une mesure prise à froid est un bruit.
func _bench(label: String) -> float:
	for _w in 30:
		await get_tree().process_frame
	var total := 0.0
	for _i in 150:
		await get_tree().process_frame
		total += get_process_delta_time()
	var avg := total / 150.0
	print("  %-38s %6.2f ms/frame  (%5.1f FPS)" % [label, avg * 1000.0, 1.0 / maxf(avg, 0.0001)])
	return avg


func _pose(pos: int, stance: String) -> void:
	_duel._pred_pos = pos
	_duel._pred_stance = stance
	_duel._world.set_pose(pos, stance, true)
	_duel._refresh_pose_view()


func _state(my_pos: int, their_pos: int, stance: String, aiming: bool, projectiles: Array) -> void:
	_duel._on_state({
		"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 2,
		"round_start_tick": 0, "round_ticks": 900, "score": [1, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": my_pos, "stance": stance, "hp": 64, "weapon": "frelon",
				"hits_total": 7, "grenades": 2, "ammo": 18, "bandages": 1, "aiming": true,
				"hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": 0,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": their_pos, "stance": "up", "hp": 52, "weapon": "condor",
				"hits_total": 4, "grenades": 1, "ammo": 3, "bandages": 0, "aiming": aiming,
				"hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": 0,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false},
		],
		"projectiles": projectiles, "events": [],
	})
	_duel._refresh_view(0.016)


func _wait(seconds: float) -> void:
	# 🩸 DÉFAUT DE BANC TROUVÉ AU LOT 3D-I. Ce banc coupe `_process` du duel pour figer la scène,
	# et c'est bien : les captures doivent être reproductibles. Mais depuis la bascule 3D, c'est
	# `_process` qui pousse l'état au rig (`pousser_etat`). Sans ce poussage, la vue 3D tournait sur
	# un état VIDE : elle rendait sa pose neutre quelle que soit la planche, et aucune capture ne
	# montrait plus ce que le jeu montre. Le banc ne mentait pas sur le décor — il mentait sur l'ARME.
	# ⚠️ On pousse l'état RÉEL (`_rig_state()`), on ne fabrique rien : une capture qui inventerait
	# son état ne prouverait rien du jeu.
	var reste := seconds
	while reste > 0.0:
		var dt: float = get_process_delta_time()
		_duel._step_feel(dt)
		if _duel._viewmodel != null and _duel._viewmodel.has_method("pousser_etat"):
			_duel._viewmodel.pousser_etat(_duel._rig_state())
		_duel._refresh_view(dt)
		await get_tree().process_frame
		reste -= dt


func _shot(name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s.png" % [_out, name_, _tag])
	print("[SHOT] %s_%s.png" % [name_, _tag])
