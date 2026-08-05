extends Node

# OUTIL §8.137 (validation VISUELLE, hors test CI) — captures PNG de LA TRANCHÉE en VUE À LA
# PREMIÈRE PERSONNE : le duel debout, la posture accroupie (mur de sacs + ciel), le laser CONDOR
# adverse, la fenêtre de choix d'arme, la jauge de grenade, l'écran de fin, le HUD aux deux
# échelles extrêmes, et l'onglet BONUS du hub.
#
# Un boot headless « 0 ERROR » ne prouve RIEN sur la mise en page (leçon §8.111) : ces captures
# sont la preuve. Les 10 poses de blockout, elles, sortent de `gen_trench_renders.tscn`.
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire (le viewport doit rendre — recette §8.100/§8.111) :
#   & <godot_console> --path frontend res://tools/preview_trench.tscn

const Geo := preload("res://scripts/game/trench_geometry.gd")
const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const EventsScene := preload("res://scenes/ui/events.tscn")
const EventsScript := preload("res://scripts/ui/events_screen.gd")

# Répertoire de sortie : la sortie de secours (`user://`) suffit si le scratchpad a changé de nom.
const OUT_DIR := "C:/Users/Hakim/AppData/Local/Temp/claude/C--Users-Hakim-Documents-Wasteland-Warfare-Project/d4df68f3-c840-46de-bda7-527ac37350dd/scratchpad"

# Barème de DÉMONSTRATION — miroir de `trench_sim.public_rules()` (données figées de capture).
const RULES := {
	"tick_rate_hz": 10, "rounds_to_win": 2, "round_ticks": 900, "positions": 5, "hp_max": 100,
	"move_ticks": 3, "intermission_ticks": 30, "grace_disconnect_ticks": 100, "afk_ticks": 200,
	"grenade": {"stock_start": 2, "stock_max": 3, "regen_ticks": 150,
		"radius_m": 2.5, "damage_max": 40, "flight_base_s": 0.9,
		"flight_per_metre_s": 0.07, "flight_floor_ticks": 15, "target_margin_m": 1.5},
	"weapons": [
		{"id": "vipere", "name_key": "WEAPON_VIPERE", "burst": 1, "damage": 12,
			"cooldown_ticks": 9, "flight_ticks": 4, "laser_lead_ticks": 0,
			"dispersion_deg": 0.30, "mag_size": 8, "reload_ticks": 15},
		{"id": "frelon", "name_key": "WEAPON_FRELON", "burst": 3, "damage": 5,
			"cooldown_ticks": 12, "flight_ticks": 3, "laser_lead_ticks": 0,
			"dispersion_deg": 0.85, "mag_size": 24, "reload_ticks": 20},
		{"id": "chacal", "name_key": "WEAPON_CHACAL", "burst": 2, "damage": 8,
			"cooldown_ticks": 8, "flight_ticks": 3, "laser_lead_ticks": 0,
			"dispersion_deg": 0.45, "mag_size": 20, "reload_ticks": 22},
		{"id": "condor", "name_key": "WEAPON_CONDOR", "burst": 1, "damage": 30,
			"cooldown_ticks": 25, "flight_ticks": 3, "laser_lead_ticks": 5,
			"dispersion_deg": 0.0, "mag_size": 4, "reload_ticks": 25},
	],
	"escalation": {"frelon_hits": 4, "choice_hits": 10,
		"choice_options": ["chacal", "condor"], "choice_window_ticks": 50},
	"bandage": {"enabled": true, "per_round": 1, "heal": 25, "channel_ticks": 20},
	"geometry": {"version": 1, "aim_quantum_deg": 0.1, "positions": 5, "no_mans_land": 35.0,
		"position_spacing": 4.0, "parapet_y": 1.25, "eye_up": 1.7, "eye_down": 0.9},
}


# Visée juste d'un tireur en `from_pos` sur une cible debout en `target_pos` — le centre de la
# fenêtre, comme le calcule le générateur (le client partage la MÊME géométrie).
func _aim(from_pos: int, target_pos: int) -> Array:
	var window: Dictionary = Geo.aim_window(Geo.eye_position(from_pos, "up"), target_pos, "up")
	if window.is_empty():
		return [0.0, 0.0]
	return [(window["yaw_min"] + window["yaw_max"]) * 0.5,
		(window["pitch_min"] + window["pitch_max"]) * 0.5]


# `hidden` : la redaction §1.6 masque la position d'un accroupi — on met `pos` à null pour que la
# capture montre RÉELLEMENT ce que le joueur voit (l'adversaire s'efface).
func _demo_state(tick: int, laser: bool, choice_deadline: int = 0,
		enemy_hidden: bool = false, reloading: bool = false) -> Dictionary:
	var my_shot := _aim(2, 3)
	var their_shot := _aim(3, 2)
	return {
		"type": "trench_state", "tick": tick, "phase": "playing", "round_no": 2,
		"round_start_tick": 0, "round_ticks": 900, "score": [1, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 64, "weapon": "frelon",
				"hits_total": 7, "grenades": 2, "choice_deadline_tick": choice_deadline,
				"laser_fire_tick": 0, "disconnected": false, "hidden": false,
				"ammo": 6 if not reloading else 0, "bandages": 1,
				"reload_until_tick": (tick + 14) if reloading else 0,
				"bandage_until_tick": 0, "aiming": not reloading},
			{"slot": 2, "pos": null if enemy_hidden else 3, "stance": "down" if enemy_hidden
				else "up", "hp": 52, "weapon": "condor", "hits_total": 11, "grenades": 1,
				"choice_deadline_tick": 0, "hidden": enemy_hidden,
				"laser_fire_tick": (tick + 5) if laser else 0, "disconnected": false,
				"ammo": 3, "reload_until_tick": 0, "bandages": 0, "bandage_until_tick": 0,
				"aiming": true},
		],
		"projectiles": [
			{"id": 1, "kind": "grenade", "owner_slot": 2, "from_pos": 3, "target_pos": 2,
				"launch_tick": tick - 8, "impact_tick": tick + 14,
				"aim_yaw": 0.0, "aim_pitch": 0.0},
			{"id": 2, "kind": "frelon", "owner_slot": 1, "from_pos": 2, "target_pos": 3,
				"launch_tick": tick - 1, "impact_tick": tick + 2,
				"aim_yaw": my_shot[0], "aim_pitch": my_shot[1]},
			{"id": 3, "kind": "condor", "owner_slot": 2, "from_pos": 3, "target_pos": 2,
				"launch_tick": tick - 1, "impact_tick": tick + 2,
				"aim_yaw": their_shot[0], "aim_pitch": their_shot[1]},
		],
		"events": [],
	}


func _ready() -> void:
	var out_dir := OUT_DIR if DirAccess.dir_exists_absolute(OUT_DIR) else OS.get_user_data_dir()

	# ------------------------------------------------------------------ 1) LE DUEL, DEBOUT
	DuelScript.pending_room_id = "999"   # empêche le retour-hub immédiat (aucun réseau ne suivra)
	var duel = DuelScene.instantiate()
	add_child(duel)
	await get_tree().process_frame
	# MISE EN SCÈNE BLANCHE : la scène a lancé un vrai `connect_to_server` qui va échouer (aucun
	# backend ici). On coupe l'abonnement AVANT que le bandeau « CONNEXION PERDUE » ne vienne
	# polluer les captures et relancer des reconnexions en boucle.
	if NetworkManager.server_connection_lost.is_connected(duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(duel._on_connection_lost)
	duel._conn_banner.visible = false
	# … et on rend la souris : le duel la CAPTURE (visée libre), ce qui piégerait le curseur de
	# l'utilisateur pendant toute la session de capture.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	duel._on_init({"rules": RULES, "your_slot": 1, "training": false,
		"opponent": {"name": "KOVACS", "is_bot": false}})
	# Deux états espacés pour donner une PAIRE d'interpolation au rendu (tampon 150 ms).
	duel._on_state(_demo_state(100, false))
	await get_tree().create_timer(0.12).timeout
	duel._on_state(_demo_state(101, false))
	# Une visée décalée : le réticule DOIT quitter le centre de l'écran (c'est tout le pivot).
	duel._aim_yaw = 6.3
	duel._aim_pitch = -0.3
	await get_tree().create_timer(0.3).timeout
	await _shot(out_dir, "trench_fp_debout")

	# ------------------------------- 1 bis) LE CONTRÔLE DU CIEL (chantier « monde 3D + ciel peint »)
	# ╔═ LA MESURE QUI CONDAMNAIT L'ANCIEN SYSTÈME ══════════════════════════════════════════════╗
	# ║ Avec un décor peint, chaque position était une DÉCOUPE différente du même panorama : d'un  ║
	# ║ bout à l'autre du front, l'horizon glissait de 128 px. Avec un ciel à 300 m, un pas de     ║
	# ║ 16 m d'un bord à l'autre vaut 3,05° de parallaxe — et l'horizon, lui, ne bouge PAS d'un    ║
	# ║ pixel, parce qu'un horizon est à l'infini quelle que soit la peinture qu'on lui donne.     ║
	# ║ On capture donc les deux bords et on compare : c'est le contrôle §2.4 du bon de commande.  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	duel._aim_yaw = 0.0
	duel._aim_pitch = 0.0
	for pos in [0, 4]:
		duel._pred_pos = pos
		duel._world.set_pose(pos, "up", true)
		duel._refresh_pose_view()
		duel._refresh_view(0.016)
		await get_tree().create_timer(0.2).timeout
		await _shot(out_dir, "trench_horizon_p%d" % pos)
	duel._pred_pos = 2
	duel._world.set_pose(2, "up", true)
	# La même chose en visant à FOND à droite : c'est là que l'ancien pan linéaire divergeait de
	# 11 % d'une projection en tangente. Un monde 3D n'a pas de « divergence » à mesurer — la
	# capture ne sert qu'à le VOIR.
	duel._aim_yaw = DuelScript.aim_yaw_limit()
	duel._refresh_view(0.016)
	await get_tree().create_timer(0.2).timeout
	await _shot(out_dir, "trench_yaw_max")
	duel._aim_yaw = 6.3

	# ---------------------------------------- 1 ter) LE PANNEAU DE RÉGLAGE (F10, entraînement)
	# ⚠️ Cette capture n'est pas décorative : un `Control` bâti par code garde `size = (0,0)` — six
	# récidives dans ce dépôt, dont la couche d'ambiance de §8.139 qui ne peignait RIEN en affichant
	# 33/33 verts. Un panneau de réglage invisible tiendrait tous les tests et ne se réglerait pas.
	duel._training = true
	duel._tuning.visible = true
	duel._log_input({"move": 1})
	duel._refresh_view(0.016)
	await get_tree().create_timer(0.25).timeout
	await _shot(out_dir, "trench_tuning_f10")
	duel._tuning.visible = false
	duel._training = false

	# ------------------------------------------------- 2) ACCROUPI : couvert total, ennemi masqué
	duel.set_process(false)              # fige la collecte d'entrées : mise en scène blanche
	duel._pred_stance = "down"
	duel._world.set_pose(duel._pred_pos, "down", true)
	duel._refresh_pose_view()
	duel._on_state(_demo_state(102, false, 0, true))
	duel._refresh_view(0.016)
	await get_tree().create_timer(0.25).timeout
	await _shot(out_dir, "trench_fp_accroupi_ennemi_masque")

	# --------------------------------------- 3) DEBOUT : laser CONDOR + choix d'arme + rechargement
	duel._pred_stance = "up"
	duel._world.set_pose(duel._pred_pos, "up", true)
	duel._refresh_pose_view()
	duel._enemy_laser_yaw = _aim(3, 2)[0]
	duel._enemy_laser_pitch = _aim(3, 2)[1]
	duel._enemy_laser_pos = 3
	# §8.141 : la jauge de charge a disparu — c'est la VISÉE DE GRENADE qui se met en scène, avec
	# son décalque au sol au rayon réel.
	duel._aiming_grenade = true
	duel._world.show_grenade_aim(true, 1.2, Geo.far_soldier_z(), true)
	duel._on_state(_demo_state(103, true, 140, false, true))
	duel._open_choice({"options": ["chacal", "condor"], "deadline_tick": 140})
	duel._refresh_view(0.016)
	await get_tree().create_timer(0.25).timeout
	await _shot(out_dir, "trench_fp_laser_choix_rechargement")

	# ------------------------------------------------------------------ 4) HUD AUX 2 ÉCHELLES
	# Contre-épreuve §6 : lisible de 0,9 à 1,3 — on capture les deux bornes.
	duel._aiming_grenade = false
	duel._world.show_grenade_aim(false)
	duel._choice_panel.visible = false
	for scale_value in [0.9, 1.3]:
		duel.scale = Vector2(scale_value, scale_value)
		duel._refresh_view(0.016)
		await get_tree().create_timer(0.15).timeout
		await _shot(out_dir, "trench_fp_hud_scale_%d" % int(scale_value * 100.0))
	duel.scale = Vector2.ONE

	# ------------------------------------------------------------------ 5) ÉCRAN DE FIN
	duel._show_result({"winner_slot": 1, "score": [2, 0], "training": false, "vs_bot": false,
		"your_slot": 1, "reason": "score",
		"rewards": {"participation_coins": 5, "participation_capped": false,
			"win_coins": 15, "win_capped": false, "new_titles": [],
			"progression": {"wins": 6, "level": 1, "level_max": 3, "next_threshold": 15,
				"thresholds": [5, 15, 40], "titles": ["trench:grenadier"]}}})
	await get_tree().process_frame
	await _shot(out_dir, "trench_fp_result")
	duel.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------------------------ 6) L'ONGLET BONUS DU HUB
	var now := int(Time.get_unix_time_from_system())
	NetworkManager.events_config = {
		"active": [{"id": "trench_week", "type": "bonus", "priority": 30,
			"name_key": "EVENT_TRENCH_NAME", "desc_key": "EVENT_TRENCH_DESC",
			"scope": "casual_ffa", "starts_at_epoch": now - 3600,
			"ends_at_epoch": now + 86400, "rules": {}}],
		"upcoming": [], "featured_id": "trench_week", "character": {},
	}
	var hub = EventsScene.instantiate()
	EventsScript.target_tab = "bonus"
	add_child(hub)
	await get_tree().process_frame
	hub._render()
	hub._on_trench_leaderboard({
		"entries": [
			{"rank": 1, "name": "SEIGNEUR_KO", "wins": 44, "level": 3},
			{"rank": 2, "name": "KOVACS", "wins": 17, "level": 2},
			{"rank": 3, "name": "HAKIM", "wins": 6, "level": 1},
		],
		"me": {"name": "HAKIM", "rank": 3, "wins": 6, "level": 1, "level_max": 3,
			"next_threshold": 15, "thresholds": [5, 15, 40],
			"titles": ["trench:grenadier"]},
		"event_active": true})
	await get_tree().create_timer(0.4).timeout
	await _shot(out_dir, "trench_hub_bonus")
	get_tree().quit(0)


func _shot(dir_path: String, name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir_path, name_]
	img.save_png(path)
	print("[PREVIEW] %s  (%dx%d)" % [path, img.get_width(), img.get_height()])
