extends Node

# TEST E11 §8.83 (style maison) — Rapport Post-Opération 2 colonnes.
# Helpers PURS (titres honorifiques départage pid, médailles) + boot du rapport avec
# (a) payload COMPLET (podium + timeline + stats perso) et (b) payload LEGACY (sections masquées,
# aucune erreur). Lancement :
#   & <godot_console> --headless --path frontend res://tools/test_e11_report.tscn

const Report := preload("res://scripts/game/operation_report.gd")
const ReportScene := preload("res://scenes/game/operation_report.tscn")

func _ready() -> void:
	# 1) Titres honorifiques — formules EXACTES + départage pid croissant.
	var stats := {
		"combat_kills_by_player": {"11": 14.0, "7": 14.0, "5": 2.0},  # égalité 11/7 → 11 (pid<)
		"conquests_by_player": {"7": 9.0},
		"hero_kills_by_player": {"5": 2.0},
		"losses_by_player": {"11": 3.0, "7": 12.0, "5": 20.0},        # min → 11
		"zone_kills_by_player": {},                                    # personne → aucun IRRADIÉ
	}
	var titles: Dictionary = Report.honor_titles(stats, [11, 7, 5])
	assert(titles[7].has("TITLE_BUTCHER"))        # égalité kills 7/11 → pid le plus petit = 7
	assert(not titles[11].has("TITLE_BUTCHER"))
	assert(titles[7].has("TITLE_CONQUEROR"))
	assert(titles[5].has("TITLE_GRAVEDIGGER"))    # hero_kills > 0
	assert(titles[11].has("TITLE_UNBREAKABLE"))   # min pertes
	# Personne n'a de morts à la zone → aucun IRRADIÉ attribué (need_positive).
	for pid in [11, 7, 5]:
		assert(not titles[pid].has("TITLE_IRRADIATED"))
	# Cumul possible : 7 = BOUCHER + CONQUÉRANT.
	assert(titles[7].size() == 2)
	print("[OK] honor_titles : formules + departage pid + cumul (7 asserts)")

	# 2) Médailles : 🥇🥈🥉 puis rangs numériques.
	assert(Report.medal_for(0) == "🥇" and Report.medal_for(2) == "🥉" and Report.medal_for(3) == "4.")
	print("[OK] medal_for : podium + rangs (1 assert)")

	# 3) Rapport COMPLET : podium (3 lignes), timeline (2 séries), stats perso.
	var report_full = ReportScene.instantiate()
	add_child(report_full)
	report_full.populate({
		"title": "VICTOIRE DE HAKIM", "title_color": Color("e0b249"),
		"stagnation": 2, "attrition": [], "worst_pseudo": "",
		"podium": [
			{"pid": 11, "medal": "🥇", "titles": ["TITLE_BUTCHER"], "objective": "Contrôler 24",
				"completed": true, "has_reveal": true, "kills": 14, "conquests": 5,
				"eliminations": 1, "points": 25},
			{"pid": 7, "medal": "🥈", "titles": [], "objective": "Contrôler 42",
				"completed": false, "has_reveal": true, "kills": 6, "conquests": 3,
				"eliminations": 0, "points": -1},
			{"pid": 5, "medal": "🥉", "titles": [], "objective": "Éliminer HAKIM",
				"completed": false, "has_reveal": true, "kills": 2, "conquests": 0,
				"eliminations": 0, "points": -1},
		],
		"timeline": [
			{"color": Color("36c5d9"), "points": [8, 10, 14, 20]},
			{"color": Color("c0654f"), "points": [8, 7, 5, 2]},
		],
		"my_stats": {"kills": 14, "losses": 3, "conquests": 5, "eliminations": 1,
			"cards_played": 4, "hero_damage": 86, "hero_kills": 1, "zone_deaths": 0,
			"hero_line": "PV 34/60 · PP +2 · NIV 14"},
	})
	assert(report_full._podium_list.get_child_count() == 3)
	assert(report_full._timeline_wrap.visible)
	assert(report_full._timeline_chart.vmax == 20)
	assert(report_full._my_stats_box.get_child_count() >= 5)
	# Inspection du champ de bataille : masque rapport + flou, émet le signal.
	var got_signal := [false]
	report_full.battlefield_inspect.connect(func(on): got_signal[0] = on)
	report_full._set_inspecting(true)
	assert(not report_full.get_node("Center").visible and got_signal[0])
	report_full._set_inspecting(false)
	assert(report_full.get_node("Center").visible and not got_signal[0])
	print("[OK] rapport COMPLET : podium 3, timeline, stats, inspection (6 asserts)")

	# 4) Rapport LEGACY (aucune clé E11) : sections masquées, aucune erreur.
	var report_legacy = ReportScene.instantiate()
	add_child(report_legacy)
	report_legacy.populate({
		"title": "OPÉRATION TERMINÉE", "title_color": Color("d6453f"),
		"stagnation": 0, "attrition": [], "worst_pseudo": "",
	})
	assert(not report_legacy._timeline_wrap.visible)     # pas de timeline
	assert(report_legacy._my_stats_box.get_child_count() == 0)  # pas de stats perso
	print("[OK] rapport LEGACY : sections masquees sans erreur (2 asserts)")

	print("[OK] TEST E11 REPORT : 16 asserts verts")
	get_tree().quit(0)
