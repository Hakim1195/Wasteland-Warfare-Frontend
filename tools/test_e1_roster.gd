extends Node

# TEST E1 §8.73 (style maison, pattern backend test_*.py) — Roster de Guerre & brique identité.
# Boot headless AVEC autoloads réels (GameState/locale/audio), état STUB injecté, asserts puis quit :
#   & <godot_console> --headless --path frontend res://tools/test_e1_roster.tscn
# Succès = lignes « [OK] … » + code retour 0 + AUCUNE ligne ERROR.

const WarRoster := preload("res://scripts/ui/war_roster.gd")
const WarRosterScene := preload("res://scenes/components/war_roster.tscn")
const PlayerChipScene := preload("res://scenes/components/player_chip.tscn")

# État stub : 3 belligérants — 11 = joueur courant (héros 34/60 NIV 14) ; 7 = héros abattu +
# éliminé ; -2 = bot ([IA], G2 §8.72) hors rotation... non : DANS la rotation, comme en vrai.
# Pids en FLOAT et clés en STRING pour reproduire le piège JSON §5.
const STUB := {
	"stage": "playing",
	"current_turn": 6,
	"current_player_id": 11,
	"phase": 3,
	"turn_order": [7.0, 11.0, -2.0],
	"players": {
		"11": {"username": "HAKIM", "faction": "phalanges_acier", "is_active": true,
			"status": "alive", "cards_in_hand": [4, 6], "hero_pv_current": 34,
			"hero_pv_max": 60, "hero_level": 14, "is_dead": false},
		"7": {"username": "VULTURE", "faction": "barons_toxiques", "is_active": true,
			"status": "eliminated", "cards_in_hand": [], "hero_pv_current": 0,
			"hero_pv_max": 52, "hero_level": 9, "is_dead": true},
		"-2": {"username": "SENTINELLE-2", "faction": "", "is_bot": true,
			"is_active": true, "status": "alive", "cards_in_hand": [3],
			"hero_pv_current": 40, "hero_pv_max": 40, "hero_level": 5, "is_dead": false},
	},
	"territories": {
		"alaska": {"owner_id": 7.0, "garrison": 3},
		"quebec": {"owner_id": 7.0, "garrison": 1},
		"peru": {"owner_id": 11.0, "garrison": 5},
		"ural": {"owner_id": null, "garrison": 0},
	},
}

func _ready() -> void:
	GameState.update_from_json(STUB)

	# 1) Helpers purs : tri conforme à turn_order + comptes de territoires exacts (critère E1).
	var order: Array = WarRoster.sorted_pids(GameState.players, GameState.turn_order)
	assert(order == [7, 11, -2])
	assert(WarRoster.sorted_pids(GameState.players, []) == [-2, 7, 11])
	assert(WarRoster.territory_count(GameState.territories, 7) == 2)
	assert(WarRoster.territory_count(GameState.territories, 11) == 1)
	assert(WarRoster.territory_count(GameState.territories, -2) == 0)
	print("[OK] tri turn_order + comptes territoires (5 asserts)")

	# 2) Dégradé PV : bornes vert / or / rouge (is_equal_approx — arithmétique float du lerp).
	assert(WarRoster.pv_color(1.0).is_equal_approx(WarRoster.PV_GREEN))
	assert(WarRoster.pv_color(0.5).is_equal_approx(WarRoster.ACCENT_GOLD))
	assert(WarRoster.pv_color(0.0).is_equal_approx(WarRoster.DANGER))
	print("[OK] degrade PV vert/or/rouge (3 asserts)")

	# 3) Brique identité : pseudo résolu, préfixe [IA] pour le bot, troncature compacte.
	var chip = PlayerChipScene.instantiate()
	add_child(chip)
	chip.setup(11, false)
	assert(chip.tooltip_text.begins_with("HAKIM"))
	chip.setup(-2, true)
	assert(chip.tooltip_text.begins_with("[IA] SENTINELLE"))
	print("[OK] player_chip : pseudo + prefixe [IA] (2 asserts)")

	# 4) Roster complet sur l'état stub : une ligne par joueur, aucune erreur de construction.
	var roster = WarRosterScene.instantiate()
	add_child(roster)
	roster.refresh()
	assert(roster.debug_row_count() == 3)
	print("[OK] war_roster : 3 lignes construites depuis le stub (1 assert)")

	print("[OK] TEST E1 ROSTER : 11 asserts verts")
	get_tree().quit(0)
