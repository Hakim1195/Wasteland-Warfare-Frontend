extends Node

# TEST E11 §8.83 (style maison) — Rapport Post-Opération EN ONGLETS (4 pages depuis §8.99 :
# XP JOUEUR / XP HÉROS / CLASSEMENT / BILAN).
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

	# 2) Indicatifs de rang (§8.100 — registre militaire, plus d'emojis) : « 01 », « 02 », …
	assert(Report.medal_for(0) == "01" and Report.medal_for(2) == "03" and Report.medal_for(3) == "04")
	print("[OK] medal_for : indicatifs de rang (1 assert)")

	# 3) Rapport COMPLET : podium (3 lignes), timeline (2 séries), stats perso, BILAN (§8.100),
	#    identité héros (§8.100) et récap de zone MASQUÉ (§8.100).
	var report_full = ReportScene.instantiate()
	add_child(report_full)
	report_full.populate({
		"title": "VICTOIRE DE HAKIM", "title_color": Color("e0b249"),
		"stagnation": 2, "attrition": [], "worst_pseudo": "",
		"podium": [
			{"pid": 11, "medal": "01", "titles": ["TITLE_BUTCHER"], "objective": "Contrôler 24",
				"completed": true, "has_reveal": true, "kills": 14, "conquests": 5,
				"eliminations": 1, "points": 25},
			{"pid": 7, "medal": "02", "titles": [], "objective": "Contrôler 42",
				"completed": false, "has_reveal": true, "kills": 6, "conquests": 3,
				"eliminations": 0, "points": -1},
			{"pid": 5, "medal": "03", "titles": [], "objective": "Éliminer HAKIM",
				"completed": false, "has_reveal": true, "kills": 2, "conquests": 0,
				"eliminations": 0, "points": -1},
		],
		"timeline": [
			{"color": Color("36c5d9"), "points": [8, 10, 14, 20]},
			{"color": Color("c0654f"), "points": [8, 7, 5, 2]},
		],
		"my_stats": {"kills": 14, "losses": 3, "conquests": 5, "eliminations": 1,
			"cards_played": 4, "hero_damage": 86, "hero_kills": 1, "zone_deaths": 0,
			"hero_line": "PV 34/60 · PP +2 · NIV 14", "hero_dead": false},
		"hero_panel": {"faction_name": "Les Nomades de la Poussière", "portrait": null,
			"color": Color("36c5d9"), "level": 14, "pv_current": 34, "pv_max": 60,
			"pa": 12, "pp": 2, "is_dead": false},
		"debrief": [
			{"pid": 11, "username": "HAKIM", "is_bot": false, "is_alive": true, "is_me": true,
				"is_winner": true, "territories": 18, "conquests": 14, "kills": 47,
				"eliminations": 2, "hero_kills": 1, "losses": 22, "zone_deaths": 3,
				"ratio": 0.68, "color": Color("36c5d9")},
			{"pid": -2, "username": "VULTURE-7", "is_bot": true, "is_alive": true, "is_me": false,
				"is_winner": false, "territories": 9, "conquests": 8, "kills": 31,
				"eliminations": 1, "hero_kills": 0, "losses": 26, "zone_deaths": 5,
				"ratio": 0.54, "color": Color("e0b249")},
			{"pid": 5, "username": "KOVACS", "is_bot": false, "is_alive": false, "is_me": false,
				"is_winner": false, "territories": 0, "conquests": 6, "kills": 28,
				"eliminations": 1, "hero_kills": 2, "losses": 19, "zone_deaths": 0,
				"ratio": 0.60, "color": Color("7fff00")},
		],
	})
	assert(report_full._podium_list.get_child_count() == 3)
	assert(report_full._timeline_wrap.visible)
	assert(report_full._timeline_chart.vmax == 20)
	assert(report_full._my_stats_box.get_child_count() >= 5)
	# §8.100 — BILAN en rangées : en-têtes groupés + titres + espaceur + 3 belligérants.
	assert(report_full._debrief_rows_box.get_child_count() == 3 + 3)
	# §8.100 — identité du héros TOUJOURS rendue (panneau unique dans sa boîte).
	assert(report_full._hero_identity_box.get_child_count() == 1)
	# §8.100 — récap de zone RETIRÉ de l'onglet CLASSEMENT (nœuds .tscn masqués, jamais reparentés).
	assert(not report_full._stagnation_ref.visible and not report_full._attrition_ref.visible)
	assert(report_full._stagnation_ref.get_parent() != report_full._ranking_tab)
	# Inspection du champ de bataille : masque rapport + flou, émet le signal.
	var got_signal := [false]
	report_full.battlefield_inspect.connect(func(on): got_signal[0] = on)
	report_full._set_inspecting(true)
	assert(not report_full.get_node("Center").visible and got_signal[0])
	report_full._set_inspecting(false)
	assert(report_full.get_node("Center").visible and not got_signal[0])
	print("[OK] rapport COMPLET : podium 3, timeline, stats, BILAN, héros, zone masquée, inspection (10 asserts)")

	# 4) Rapport LEGACY (aucune clé E11) : sections masquées, aucune erreur.
	var report_legacy = ReportScene.instantiate()
	add_child(report_legacy)
	report_legacy.populate({
		"title": "OPÉRATION TERMINÉE", "title_color": Color("d6453f"),
		"stagnation": 0, "attrition": [], "worst_pseudo": "",
	})
	assert(not report_legacy._timeline_wrap.visible)     # pas de timeline
	assert(report_legacy._my_stats_box.get_child_count() == 0)  # pas de stats perso
	# §8.100 — placeholders honnêtes tant que le game_over n'est pas arrivé : onglets jamais blancs.
	assert(report_legacy._player_rewards_box.get_child_count() == 1)
	assert(report_legacy._hero_progress_box.get_child_count() == 1)
	assert(report_legacy._hero_identity_box.get_child_count() == 0)  # pas de hero_panel legacy
	# Les 4 onglets (XP JOUEUR / XP HÉROS / CLASSEMENT / BILAN §8.99) sont TOUJOURS construits par
	# _build_tabs(), quel que soit le payload — le 4ᵉ ne fait pas exception : payload legacy ici
	# (aucune clé `debrief`) → le tableau BILAN reste vide, mais son onglet existe (§9.2).
	assert(report_legacy._tabs.get_tab_count() == 4)
	# Titre du 4ᵉ onglet : verrouille l'EXISTENCE de l'onglet BILAN (pas seulement le compte) et son
	# titrage depuis l'i18n. Vérif au RUNTIME via tr() — ne JAMAIS grep le `.translation` compilé
	# (hashé/compressé → faux négatif garanti).
	assert(report_legacy._tabs.get_tab_title(3) == tr("REPORT_TAB_DEBRIEF"))
	# … et la clé est RÉELLEMENT traduite (sans ceci, l'assert ci-dessus comparerait tr() à tr() et
	# passerait même si la clé manquait du CSV, en repli silencieux sur son propre nom).
	assert(tr("REPORT_TAB_DEBRIEF") != "REPORT_TAB_DEBRIEF")
	print("[OK] rapport LEGACY : sections masquees + placeholders + 4 onglets titres (8 asserts)")

	# 4-bis) §8.100 — podium PROVISOIRE (repli local avant game_over) : rangées + note discrète ;
	# le re-populate du verdict serveur (provisional=false) retire la note.
	var report_prov = ReportScene.instantiate()
	add_child(report_prov)
	report_prov.populate({
		"title": "OPÉRATION TERMINÉE", "title_color": Color("d6453f"),
		"stagnation": 0, "attrition": [], "worst_pseudo": "",
		"podium": [
			{"pid": 3, "medal": "01", "titles": [], "objective": "", "completed": false,
				"has_reveal": false, "kills": 4, "conquests": 2, "eliminations": 0, "points": -1},
			{"pid": 9, "medal": "02", "titles": [], "objective": "", "completed": false,
				"has_reveal": false, "kills": 1, "conquests": 1, "eliminations": 0, "points": -1},
		],
		"podium_provisional": true,
	})
	assert(report_prov._podium_list.get_child_count() == 3)  # 2 rangées + note provisoire
	assert(report_prov._podium_list.get_child(2).name == "ProvisionalNote")
	report_prov.populate_podium([
		{"pid": 3, "medal": "01", "titles": [], "objective": "", "completed": false,
			"has_reveal": false, "kills": 4, "conquests": 2, "eliminations": 0, "points": 12},
		{"pid": 9, "medal": "02", "titles": [], "objective": "", "completed": false,
			"has_reveal": false, "kills": 1, "conquests": 1, "eliminations": 0, "points": -1},
	], false)
	assert(report_prov._podium_list.get_child_count() == 2)  # note retirée au verdict serveur
	print("[OK] podium provisoire : repli local + remplacement serveur (3 asserts)")

	# 5) Détail du barème (E-visuel) : helpers PURS réconciliés + rendu dans les onglets.
	assert(Report._breakdown_total(Report.player_points_breakdown(0, 5, 1, 2, 250)) == 57)
	assert(Report._breakdown_total(Report.player_xp_breakdown(0, 3, 10, 1, false)) == 205)
	assert(Report._breakdown_total(Report.player_xp_breakdown(0, 3, 10, 1, true)) == 256)
	assert(Report._breakdown_total(Report.hero_xp_breakdown(25, true, 4, 1, 55)) == 308)
	var report_detail = ReportScene.instantiate()
	add_child(report_detail)
	report_detail.populate({
		"title": "VICTOIRE", "title_color": Color("e0b249"),
		"stagnation": 0, "attrition": [], "worst_pseudo": "",
		"rewards": {
			"match_points": 37, "xp_earned": 118, "hero_xp_earned": 281,
			"new_level": 3, "current_xp": 40, "levels_gained": 1, "level_up_triggered": true,
			"coins_earned": 0, "hero_level": 4, "hero_new_level": 5,
			"hero_xp_in_level": 10, "hero_xp_for_level": 100,
		},
		"xp_detail": {
			"rank": 0, "territories_final": 5, "continents_final": 1, "conquests": 3,
			"kills": 10, "eliminations": 2, "hero_kills": 1, "hero_damage": 55, "objective_done": true,
		},
	})
	# Bloc récompenses + détail (partie SYNCHRONE) posés avant la 1re frame d'animation.
	assert(report_detail._player_rewards_box.get_child_count() >= 2)
	assert(report_detail._hero_progress_box.get_child_count() >= 2)
	print("[OK] détail barème : helpers purs + rendu onglets (6 asserts)")

	print("[OK] TEST E11 REPORT : 35 asserts verts")
	get_tree().quit(0)
