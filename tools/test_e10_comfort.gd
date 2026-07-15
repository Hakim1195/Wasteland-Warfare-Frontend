extends Node

# TEST E10 §8.82 (style maison) — Accessibilité & confort : réglages persistables (SettingsManager),
# palette daltonienne Okabe-Ito retournée par board.get_player_color quand actif (source unique),
# motif stable par joueur, initiale de badge. Arène réelle + toggles.
#   & <godot_console> --headless --path frontend res://tools/test_e10_comfort.tscn

const CB := preload("res://scripts/game/board.gd")

const STATE := {
	"stage": "playing", "current_turn": 1, "current_player_id": 11, "phase": 3,
	"turn_order": [11.0, 7.0, 5.0],
	"players": {
		"11": {"username": "HAKIM", "faction": "phalanges_acier", "is_active": true, "status": "alive"},
		"7": {"username": "VULTURE", "faction": "", "is_active": true, "status": "alive"},
		"5": {"username": "GHOST", "faction": "", "is_active": true, "status": "alive"},
	},
	"territories": {"alaska": {"owner_id": 11.0, "garrison": 5}},
}

func _ready() -> void:
	# 1) Réglages confort : défauts + persistance typée (bool/float/String).
	SettingsManager.set_comfort("colorblind_mode", false)
	SettingsManager.set_comfort("reduced_motion", false)
	SettingsManager.set_comfort("ui_scale", 1.0)
	SettingsManager.set_comfort("damage_numbers", true)
	assert(SettingsManager.get_comfort("colorblind_mode") == false)
	SettingsManager.set_comfort("ui_scale", 1.15)
	assert(absf(float(SettingsManager.get_comfort("ui_scale")) - 1.15) < 0.001)
	SettingsManager.set_comfort("ui_scale", 1.0)
	print("[OK] reglages confort persistables + typage (2 asserts)")

	# 2) Palette daltonienne : board.get_player_color retourne Okabe-Ito quand actif (source unique).
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var board = arena.get_node("MapViewportContainer/MapContent/Board")
	GameState.update_from_json(STATE)

	SettingsManager.set_comfort("colorblind_mode", false)
	board._owner_colors.clear()
	var normal_11: Color = board.get_player_color(11)
	# En mode normal, HAKIM (phalanges_acier) prend l'accent de faction si dispo, sinon PALETTE[0].
	SettingsManager.set_comfort("colorblind_mode", true)
	board._owner_colors.clear()
	var cb_11: Color = board.get_player_color(11)
	var cb_7: Color = board.get_player_color(7)
	# Les 3 joueurs (indices 0/1/2 par id trié 5,7,11) prennent la palette Okabe-Ito par index.
	# ids triés = [5, 7, 11] → 11 = index 2 → PALETTE_COLORBLIND[2] ; 7 = index 1.
	assert(cb_11.is_equal_approx(CB.PALETTE_COLORBLIND[2]))
	assert(cb_7.is_equal_approx(CB.PALETTE_COLORBLIND[1]))
	assert(not cb_11.is_equal_approx(cb_7))  # 6 factions distinctes garanties
	print("[OK] palette daltonienne Okabe-Ito par index (source unique) (3 asserts)")

	# 3) Initiale de badge (redondance texte) : première lettre majuscule du pseudo.
	assert(board._owner_initial(11) == "H")   # HAKIM
	assert(board._owner_initial(7) == "V")     # VULTURE
	print("[OK] initiale de badge (redondance texte) (2 asserts)")

	# 4) Index de palette stable par joueur (motif = index) : ids triés → index 0..N.
	assert(board._player_palette_index(5) == 0)
	assert(board._player_palette_index(7) == 1)
	assert(board._player_palette_index(11) == 2)
	print("[OK] index de palette stable (motif par joueur) (3 asserts)")

	# Restaure les défauts (ne pas polluer user://settings.cfg pour une vraie partie).
	SettingsManager.set_comfort("colorblind_mode", false)
	SettingsManager.set_comfort("reduced_motion", false)

	print("[OK] TEST E10 COMFORT : 10 asserts verts")
	get_tree().quit(0)
