extends Node

# TEST E3 §8.75 (style maison) — chrono serveur côté HUD + repli legacy.
# Instancie l'arène complète (main.tscn, autoloads réels) puis pousse des états stub :
#   (a) legacy SANS server_time → estimation locale historique (repli §9.2) ;
#   (b) serveur AVEC turn_timer → rebours calé sur l'échéance diffusée ;
#   (c) tour de BOT (turn_timer null + server_time) → "--:--" ;
#   (d) timer_update reason=time_bank → nouvelle échéance appliquée.
# Lancement : & <godot_console> --headless --path frontend res://tools/test_e3_timer.tscn

const BASE_STATE := {
	"stage": "playing",
	"current_turn": 3,
	"current_player_id": 11,
	"phase": 3,
	"turn_order": [11.0, 7.0],
	"players": {
		"11": {"username": "HAKIM", "faction": "", "is_active": true, "status": "alive"},
		"7": {"username": "VULTURE", "faction": "", "is_active": true, "status": "alive"},
	},
	"territories": {"alaska": {"owner_id": 11.0, "garrison": 4}},
}

func _ready() -> void:
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var hud = arena.get_node("HUD")

	# (a) LEGACY : état sans server_time → _srv_active faux, estimation locale armée (90 s en
	# phase d'Attaque). Le comportement historique est INTACT.
	GameState.update_from_json(BASE_STATE)
	assert(GameState.server_time == 0.0 and GameState.turn_timer.is_empty())
	hud.update_display()
	assert(not hud._srv_active)
	assert(hud._turn_limit > 0.0)
	hud._process(0.016)
	assert(str(hud.get_node("%TimerLabel").text) != "--:--")
	print("[OK] repli legacy : estimation locale intacte (4 asserts)")

	# (b) SERVEUR : turn_timer + server_time → rebours calé sur l'échéance epoch diffusée.
	var now := Time.get_unix_time_from_system()
	var srv := BASE_STATE.duplicate(true)
	srv["server_time"] = now
	srv["turn_timer"] = {"deadline_epoch": now + 42.0, "budget_seconds": 90, "time_bank_cap": 180}
	GameState.update_from_json(srv)
	hud.update_display()
	assert(hud._srv_active)
	hud._process(0.016)
	var txt := str(hud.get_node("%TimerLabel").text)
	assert(txt.begins_with("00:4"))  # ~42 s restantes
	print("[OK] chrono serveur : échéance diffusée affichée (2 asserts — " + txt + ")")

	# (c) TOUR DE BOT : turn_timer null (serveur récent) → aucun rebours ("--:--").
	var bot := BASE_STATE.duplicate(true)
	bot["current_player_id"] = -2
	bot["server_time"] = now
	GameState.update_from_json(bot)
	hud.update_display()
	assert(not hud._srv_active and hud._turn_limit == 0.0)
	hud._process(0.016)
	assert(str(hud.get_node("%TimerLabel").text) == "--:--")
	print("[OK] tour de bot : aucun compte à rebours (2 asserts)")

	# (d) timer_update time_bank : nouvelle échéance appliquée (repousse de +10 s).
	GameState.update_from_json(srv)
	hud.update_display()
	var before: float = hud._srv_deadline_epoch
	hud.apply_timer_update(before + 10.0, "time_bank", now)
	assert(absf(hud._srv_deadline_epoch - (before + 10.0)) < 0.001)
	print("[OK] timer_update time_bank : échéance repoussée (1 assert)")

	print("[OK] TEST E3 TIMER : 9 asserts verts")
	get_tree().quit(0)
