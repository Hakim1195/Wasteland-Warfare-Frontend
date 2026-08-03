extends Node

# OUTIL §8.136 (validation VISUELLE, hors test CI) — captures PNG de LA TRANCHÉE : l'arène du duel
# aux deux postures, l'arc de grenade dosé, le laser CONDOR, la fenêtre de choix d'arme, l'écran de
# fin, et l'onglet BONUS du hub Événements avec sa carte + son panneau (file/top 50/progression).
# Un boot headless « 0 ERROR » ne prouve RIEN sur la mise en page : ces captures sont la preuve.
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire (le viewport doit rendre — recette §8.100/§8.111) :
#   & <godot_console> --path frontend res://tools/preview_trench.tscn

const DuelScene := preload("res://scenes/game/trench_duel.tscn")
const DuelScript := preload("res://scripts/game/trench_duel.gd")
const EventsScene := preload("res://scenes/ui/events.tscn")
const EventsScript := preload("res://scripts/ui/events_screen.gd")
const OUT_DIR := "C:/Users/Hakim/AppData/Local/Temp/claude/C--Users-Hakim-Documents-Wasteland-Warfare-Project/9dca86ce-9caf-4d98-b804-dbcd25f29e41/scratchpad"

# Barème de DÉMONSTRATION — miroir de `trench_sim.public_rules()` (données figées de capture).
const RULES := {
	"tick_rate_hz": 10, "rounds_to_win": 2, "round_ticks": 900, "positions": 5, "hp_max": 100,
	"move_ticks": 3, "intermission_ticks": 30, "grace_disconnect_ticks": 100, "afk_ticks": 200,
	"grenade": {"stock_start": 2, "stock_max": 3, "regen_ticks": 150,
		"flight_min_ticks": 15, "flight_max_ticks": 30, "damage_direct": 40,
		"damage_adjacent": 15},
	"weapons": [],
	"escalation": {"frelon_hits": 4, "choice_hits": 10,
		"choice_options": ["chacal", "condor"], "choice_window_ticks": 50},
}


func _demo_state(tick: int, my_stance: String, laser: bool,
		choice_deadline: int = 0) -> Dictionary:
	return {
		"type": "trench_state", "tick": tick, "phase": "playing", "round_no": 2,
		"round_start_tick": 0, "round_ticks": 900, "score": [1, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": my_stance, "hp": 64, "weapon": "frelon",
				"hits_total": 7, "grenades": 2, "choice_deadline_tick": choice_deadline,
				"laser_fire_tick": 0, "disconnected": false},
			{"slot": 2, "pos": 3, "stance": "up", "hp": 52, "weapon": "condor",
				"hits_total": 11, "grenades": 1, "choice_deadline_tick": 0,
				"laser_fire_tick": (tick + 5) if laser else 0, "disconnected": false},
		],
		"projectiles": [
			{"id": 1, "kind": "grenade", "owner_slot": 2, "from_pos": 3, "target_pos": 2,
				"launch_tick": tick - 8, "impact_tick": tick + 14},
			{"id": 2, "kind": "vipere", "owner_slot": 1, "from_pos": 2, "target_pos": 3,
				"launch_tick": tick - 1, "impact_tick": tick + 3},
		],
		"events": [],
	}


func _ready() -> void:
	var out_dir := OUT_DIR if DirAccess.dir_exists_absolute(OUT_DIR) else OS.get_user_data_dir()

	# ------------------------------------------------------------------ 1) L'ARÈNE DU DUEL
	DuelScript.pending_room_id = "999"   # empêche le retour-hub immédiat (aucun réseau ne suivra)
	var duel = DuelScene.instantiate()
	add_child(duel)
	await get_tree().process_frame
	duel._on_init({"rules": RULES, "your_slot": 1, "training": false,
		"opponent": {"name": "KOVACS", "is_bot": false}})
	# Deux états espacés pour donner une PAIRE d'interpolation au rendu (tampon 150 ms).
	duel._on_state(_demo_state(100, "up", false))
	await get_tree().create_timer(0.12).timeout
	duel._on_state(_demo_state(101, "up", false))
	await get_tree().create_timer(0.2).timeout
	await _shot(out_dir, "trench_duel_debout")

	# Posture ACCROUPIE + LASER CONDOR adverse + fenêtre de CHOIX + jauge de grenade dosée.
	duel.set_process(false)              # fige la collecte d'entrées : mise en scène blanche
	duel._pred_stance = "down"
	duel._charging = true
	duel._charge = 0.7
	duel._on_state(_demo_state(102, "down", true, 140))
	duel._open_choice({"options": ["chacal", "condor"], "deadline_tick": 140})
	duel._refresh_view(0.016)
	await get_tree().process_frame
	await _shot(out_dir, "trench_duel_accroupi_laser_choix")

	# Écran de FIN (victoire, coins, progression, palier GRENADIER).
	duel._show_result({"winner_slot": 1, "score": [2, 0], "training": false, "vs_bot": false,
		"your_slot": 1, "reason": "score",
		"rewards": {"participation_coins": 5, "participation_capped": false,
			"win_coins": 15, "win_capped": false, "new_titles": [],
			"progression": {"wins": 6, "level": 1, "level_max": 3, "next_threshold": 15,
				"thresholds": [5, 15, 40], "titles": ["trench:grenadier"]}}})
	await get_tree().process_frame
	await _shot(out_dir, "trench_result")
	duel.queue_free()
	await get_tree().process_frame

	# ------------------------------------------------------------------ 2) L'ONGLET BONUS DU HUB
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
