extends Node

# OUTIL §8.100 (validation VISUELLE, non versionné dans un test CI) — boote le Rapport
# Post-Opération avec un jeu de données de DÉMONSTRATION calqué sur la maquette RETEX
# (6 belligérants, vainqueur = moi, 2 éliminés) et capture UN PNG PAR ONGLET.
# Lancement FENÊTRÉ obligatoire (le viewport doit rendre — un run --headless produit du noir) :
#   & <godot_console> --path frontend res://tools/preview_report.tscn
# Les captures atterrissent dans le dossier fourni par OUT_DIR ci-dessous.

const ReportScene := preload("res://scenes/game/operation_report.tscn")
const OUT_DIR := "C:/Users/Hakim/AppData/Local/Temp/claude/C--Users-Hakim-Documents-Wasteland-Warfare-Project/4c5a756b-0be5-418d-8f4f-d397b788b1e7/scratchpad"

func _ready() -> void:
	# État PUBLIC minimal pour les briques PlayerChip du podium (pseudos + flags bots).
	GameState.players = {
		"1": {"username": "HAKIM", "is_bot": false, "faction": "pillards_poussiere",
			"hero_pv_current": 34, "hero_pv_max": 60, "hero_pa": 12, "hero_pp_current": 2,
			"hero_level": 14},
		"-2": {"username": "VULTURE-7", "is_bot": true},
		"5": {"username": "KOVACS", "is_bot": false},
		"-3": {"username": "RAZOR-3", "is_bot": true},
		"-4": {"username": "ECHO-9", "is_bot": true},
		"-5": {"username": "DELTA-4", "is_bot": true},
	}
	var report = ReportScene.instantiate()
	add_child(report)
	report.populate({
		"title": "VICTOIRE DE HAKIM", "title_color": Color("e0b249"),
		"stagnation": 2, "attrition": [], "worst_pseudo": "",
		"is_ranked": true, "has_played": true,
		"rewards": {
			"match_points": 37, "xp_earned": 118, "coins_earned": 100, "hero_coins_earned": 12,
			"level_up_triggered": true, "levels_gained": 1, "new_level": 10, "current_xp": 40,
			"xp_to_next_level": 1960, "pass_bonus_applied": true,
			"rp_delta": 25, "rp_after": 360, "rp_label": "BRONZE II", "rp_promoted": false,
			"rp_demoted": false, "rp_floor_protected": false,
			"hero_xp_earned": 281, "hero_level": 13, "hero_new_level": 14,
			"hero_levels_gained": 1, "hero_level_up": true,
			"hero_xp_in_level": 120, "hero_xp_for_level": 630,
			"hero_milestones": [{"level": 14, "bonus": {"pv_max": 50, "pa": 1}}],
		},
		"xp_detail": {
			"rank": 0, "territories_final": 18, "continents_final": 2, "conquests": 14,
			"kills": 47, "eliminations": 2, "hero_kills": 1, "hero_damage": 86,
			"objective_done": true,
		},
		"my_stats": {"kills": 47, "losses": 22, "conquests": 14, "eliminations": 2,
			"cards_played": 6, "hero_damage": 86, "hero_kills": 1, "zone_deaths": 3,
			"hero_line": "PV 34/60 · PP +2 · NIV 14", "hero_dead": false},
		"hero_panel": {"faction_name": "Les Nomades de la Poussière",
			"portrait": load("res://assets/images/heroes/nomades.png"),
			"color": Color("36c5d9"), "level": 14, "pv_current": 34, "pv_max": 60,
			"pa": 12, "pp": 2, "is_dead": false},
		"podium": [
			{"pid": 1, "medal": "01", "titles": ["TITLE_BUTCHER", "TITLE_CONQUEROR"],
				"objective": "Contrôler 24 territoires", "completed": true, "has_reveal": true,
				"kills": 47, "conquests": 14, "eliminations": 2, "points": 37},
			{"pid": -2, "medal": "02", "titles": [], "objective": "Contrôler l'Est",
				"completed": false, "has_reveal": true, "kills": 31, "conquests": 8,
				"eliminations": 1, "points": -1},
			{"pid": 5, "medal": "03", "titles": ["TITLE_GRAVEDIGGER"],
				"objective": "Éliminer HAKIM", "completed": false, "has_reveal": true,
				"kills": 28, "conquests": 6, "eliminations": 1, "points": -1},
			{"pid": -3, "medal": "04", "titles": [], "objective": "Survivre 12 rounds",
				"completed": false, "has_reveal": true, "kills": 17, "conquests": 5,
				"eliminations": 0, "points": -1},
			{"pid": -4, "medal": "05", "titles": ["TITLE_IRRADIATED"], "objective": "Tenir le Nord",
				"completed": false, "has_reveal": true, "kills": 11, "conquests": 3,
				"eliminations": 0, "points": -1},
			{"pid": -5, "medal": "06", "titles": [], "objective": "Contrôler 3 continents",
				"completed": false, "has_reveal": true, "kills": 4, "conquests": 1,
				"eliminations": 0, "points": -1},
		],
		"debrief": [
			{"pid": 1, "username": "HAKIM", "is_bot": false, "is_alive": true, "is_me": true,
				"is_winner": true, "territories": 18, "conquests": 14, "kills": 47,
				"eliminations": 2, "hero_kills": 1, "losses": 22, "zone_deaths": 3,
				"ratio": 0.68, "color": Color("36c5d9")},
			{"pid": -2, "username": "VULTURE-7", "is_bot": true, "is_alive": true, "is_me": false,
				"is_winner": false, "territories": 9, "conquests": 8, "kills": 31,
				"eliminations": 1, "hero_kills": 0, "losses": 26, "zone_deaths": 5,
				"ratio": 0.54, "color": Color("e0b249")},
			{"pid": 5, "username": "KOVACS", "is_bot": false, "is_alive": true, "is_me": false,
				"is_winner": false, "territories": 8, "conquests": 6, "kills": 28,
				"eliminations": 1, "hero_kills": 2, "losses": 19, "zone_deaths": 0,
				"ratio": 0.60, "color": Color("7fff00")},
			{"pid": -3, "username": "RAZOR-3", "is_bot": true, "is_alive": true, "is_me": false,
				"is_winner": false, "territories": 5, "conquests": 5, "kills": 17,
				"eliminations": 0, "hero_kills": 0, "losses": 24, "zone_deaths": 2,
				"ratio": 0.41, "color": Color("b04fd6")},
			{"pid": -4, "username": "ECHO-9", "is_bot": true, "is_alive": false, "is_me": false,
				"is_winner": false, "territories": 0, "conquests": 3, "kills": 11,
				"eliminations": 0, "hero_kills": 0, "losses": 18, "zone_deaths": 7,
				"ratio": 0.38, "color": Color("d97a36")},
			{"pid": -5, "username": "DELTA-4", "is_bot": true, "is_alive": false, "is_me": false,
				"is_winner": false, "territories": 0, "conquests": 1, "kills": 4,
				"eliminations": 0, "hero_kills": 0, "losses": 15, "zone_deaths": 1,
				"ratio": 0.21, "color": Color("c8cdd6")},
		],
		"timeline": [
			{"color": Color("36c5d9"), "points": [8, 10, 13, 16, 19, 21, 24]},
			{"color": Color("e0b249"), "points": [8, 8, 9, 10, 11, 10, 11]},
			{"color": Color("7fff00"), "points": [8, 8, 8, 9, 9, 10, 10]},
			{"color": Color("b04fd6"), "points": [8, 8, 7, 7, 6, 6, 7]},
			{"color": Color("d97a36"), "points": [8, 7, 5, 3, 2, 1, 0]},
			{"color": Color("c8cdd6"), "points": [8, 6, 4, 2, 1, 0, 0]},
		],
	})
	# Laisse les animations d'entrée (compteurs, jauges) se dérouler avant les captures.
	await get_tree().create_timer(2.2).timeout
	# Repli : si le dossier de sortie n'existe plus (chemin d'une session d'outillage), on écrit
	# dans user:// — l'outil reste utilisable tel quel.
	var out_dir := OUT_DIR if DirAccess.dir_exists_absolute(OUT_DIR) else OS.get_user_data_dir()
	for tab in range(4):
		report._tabs.current_tab = tab
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/report_tab_%d.png" % [out_dir, tab])
	get_tree().quit(0)
