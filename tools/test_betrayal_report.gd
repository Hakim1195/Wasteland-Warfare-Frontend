extends Node

# TEST §8.121 (style maison) — RAPPORT DE TRAHISON (LOT B) + RÉVÉLATION THÉÂTRALE (LOT C)
# + CARTE DE PARTAGE (LOT D, composition seule).
#
#   [A] module PUR `BetrayalReport` : auto-vérification interne (self_check) + cas de bord
#       supplémentaires (journal vide, joueur inconnu, égalités) ;
#   [B] boot du Rapport Post-Op avec un payload COMPLET → 5ᵉ onglet TRAHISONS peuplé ;
#   [C] payload LEGACY (aucun `attack_log` : serveur non redéployé) → onglet TRAHISONS MASQUÉ,
#       aucune erreur (§9.2) ;
#   [D] révélation théâtrale : ordre dernier→vainqueur, SKIP instantané, mode reduced_motion ;
#   [E] carte de partage : les deux compositions se construisent (16:9 et 9:16) sans erreur —
#       le RENDU PNG lui-même exige un vrai renderer (cf. tools/preview_share_card.tscn).
#
# Lancement : & <godot_console> --headless --path frontend res://tools/test_betrayal_report.tscn

const Report := preload("res://scripts/game/operation_report.gd")
const ReportScene := preload("res://scenes/game/operation_report.tscn")
const ShareCard := preload("res://scripts/game/share_card.gd")

var _ok := 0


func _chk(cond: bool, label: String) -> void:
	assert(cond, "ÉCHEC : " + label)
	_ok += 1


# Journal d'attaques de démonstration, écrit comme le RÉSEAU l'envoie (nombres float, null pour le
# neutre) — 3 joueurs : 1 (moi), -2 (bot), 5.
func _demo_log() -> Array:
	return [
		{"turn": 1.0, "round": 1.0, "attacker_id": 1.0, "defender_id": -2.0, "kills": 2.0,
			"conquered": false, "hero_kill": false},
		{"turn": 2.0, "round": 1.0, "attacker_id": -2.0, "defender_id": null, "kills": 1.0,
			"conquered": true, "hero_kill": false},
		{"turn": 4.0, "round": 2.0, "attacker_id": 5.0, "defender_id": -2.0, "kills": 3.0,
			"conquered": true, "hero_kill": false},
		{"turn": 13.0, "round": 5.0, "attacker_id": 1.0, "defender_id": 5.0, "kills": 7.0,
			"conquered": true, "hero_kill": true},
		{"turn": 16.0, "round": 6.0, "attacker_id": 1.0, "defender_id": -2.0, "kills": 4.0,
			"conquered": true, "hero_kill": false},
	]


func _demo_stats() -> Dictionary:
	return {
		"combat_kills_by_player": {"1": 13.0, "-2": 3.0, "5": 3.0},
		"conquests_by_player": {"1": 3.0, "-2": 1.0, "5": 1.0},
		"eliminations_by_player": {"1": 2.0},
		"losses_by_player": {"1": 4.0, "-2": 9.0, "5": 7.0},
		"zone_kills_by_player": {"-2": 2.0},
		"hero_kills_by_player": {"1": 1.0},
		"hero_damage_by_player": {"1": 96.0},
		"cards_played_by_player": {"1": 4.0},
		"eliminated_by_player": {"5": 1.0, "-2": 1.0},
		"hero_down_order": [5.0],
		"territory_history": [
			{"1": 14.0, "-2": 14.0, "5": 14.0},
			{"1": 16.0, "-2": 13.0, "5": 13.0},
			{"1": 22.0, "-2": 11.0, "5": 9.0},
			{"1": 30.0, "-2": 9.0, "5": 3.0},
			{"1": 38.0, "-2": 4.0, "5": 0.0},
		],
		"zone_stagnation_turns": 2,
	}


func _ready() -> void:
	# État PUBLIC minimal (les briques PlayerChip du podium / de la matrice lisent GameState).
	GameState.players = {
		"1": {"username": "HAKIM", "is_bot": false, "faction": "phalanges_acier",
			"hero_pv_current": 44, "hero_pv_max": 60, "hero_pa": 12, "hero_pp_current": 2,
			"hero_level": 9},
		"-2": {"username": "VULTURE-7", "is_bot": true, "faction": "barons_ferraille"},
		"5": {"username": "KOVACS", "is_bot": false, "faction": "chasseurs_ombres"},
	}
	GameState.statistics = _demo_stats()

	_test_pure_module()
	await _test_report_full()
	await _test_report_legacy()
	await _test_reveal_sequence()
	await _test_share_card_composition()

	print("\n=== RAPPORT DE TRAHISON / PARTAGE (§8.121) : %d asserts OK / 0 KO ===" % _ok)
	get_tree().quit(0)


# =========================================================
# [A] Module PUR
# =========================================================
func _test_pure_module() -> void:
	BetrayalReport.self_check()
	_chk(true, "self_check() interne du module passe")

	var log_ := _demo_log()
	var pids := [1, -2, 5]

	# Matrice : les ids NÉGATIFS (bots) doivent être des citoyens de première classe du récit.
	var m := BetrayalReport.aggression_matrix(log_, pids)
	_chk(int(m["cells"][1][-2]) == 6, "matrice : 1 → -2 = 2 + 4 kills (bot en défense)")
	_chk(int(m["cells"][1][5]) == 7, "matrice : 1 → 5 = 7 kills")
	_chk(int(m["cells"][-2][5]) == 0, "matrice : couple sans échange = case à 0")
	_chk(int(m["max"]["attacker"]) == 1 and int(m["max"]["defender"]) == 5,
		"matrice : case maximale = 1 → 5")
	_chk(int(m["total"]) == 16, "matrice : total 2+3+7+4 (l'attaque sur le NEUTRE est exclue)")

	# Coup de poignard : 1 frappe 5 au round 5 sans l'avoir jamais touché → calme 5, 7 kills.
	var stab := BetrayalReport.find_backstab(log_)
	_chk(bool(stab["confirmed"]), "coup de poignard QUALIFIÉ détecté")
	_chk(int(stab["attacker"]) == 1 and int(stab["defender"]) == 5,
		"coup de poignard : 1 poignarde 5")
	_chk(int(stab["round"]) == 5 and int(stab["kills"]) == 7, "coup de poignard : round 5, 7 unités")
	_chk(int(stab["calm_rounds"]) == 5, "coup de poignard : 5 rounds de calme (jamais affrontés)")
	_chk(bool(stab["hero_kill"]), "coup de poignard : le héros de 5 y est tombé")

	# Moment décisif sur l'historique de démo. Fenêtres de 3 snapshots :
	#   (0→2) 1:+8  -2:-3  5:-5 · (1→3) 1:+14 -2:-4 5:-10 · (2→4) 1:+16 -2:-7 5:-9
	# Le plus grand basculement est donc la POUSSÉE de 1 (+16), pas la chute de 5 (−10) : le critère
	# est l'AMPLITUDE, pas le signe (le signe ne sert qu'à départager les ex æquo, cf. self_check).
	var tp := BetrayalReport.find_turning_point(_demo_stats()["territory_history"])
	_chk(not tp.is_empty(), "moment décisif détecté")
	_chk(int(tp["pid"]) == 1, "moment décisif : la plus grande amplitude est celle de 1 (+16)")
	_chk(int(tp["delta"]) == 16, "moment décisif : delta exact +16 (22 → 38)")
	_chk(int(tp["from_index"]) == 2 and int(tp["to_index"]) == 4 and int(tp["round"]) == 5,
		"moment décisif : fenêtre 2→4, round 5")
	_chk(int(tp["to_index"]) - int(tp["from_index"]) == 2, "moment décisif : fenêtre de 3 snapshots")

	# Chaîne des chutes.
	var chain := BetrayalReport.elimination_chain(_demo_stats(), log_)
	_chk(chain.size() == 2, "chaîne des chutes : 2 éliminations")
	_chk(int(chain[0]["victim"]) == 5 and int(chain[0]["killer"]) == 1,
		"chaîne : 5 tombe d'abord, tué par 1")
	_chk(bool(chain[0]["hero"]) and not bool(chain[1]["hero"]),
		"chaîne : seule la chute de 5 est une mise à mort de HÉROS")
	_chk(int(chain[1]["victim"]) == -2, "chaîne : le bot tombe ensuite")

	# Robustesse (client défensif §9.2) : journal absent / pourri.
	_chk(BetrayalReport.find_backstab([]).is_empty(), "journal vide → aucun coup de poignard")
	_chk(BetrayalReport.aggression_matrix([], pids)["total"] == 0, "journal vide → matrice à 0")
	_chk(BetrayalReport.elimination_chain(_demo_stats(), []).size() == 2,
		"journal vide mais attributions présentes → chaîne NON DATÉE mais complète")
	_chk(BetrayalReport.find_turning_point([]).is_empty(), "historique vide → aucun moment décisif")


# =========================================================
# [B] Rapport COMPLET — 5ᵉ onglet peuplé
# =========================================================
func _report_payload(with_betrayals: bool) -> Dictionary:
	var data := {
		"title": "VICTOIRE DE HAKIM", "title_color": Color("e0b249"),
		"stagnation": 2, "attrition": [], "worst_pseudo": "",
		"is_ranked": true, "has_played": false,
		"timeline": [
			{"color": Color("36c5d9"), "points": [14, 16, 22, 30, 38]},
			{"color": Color("c0654f"), "points": [14, 13, 11, 9, 4]},
			{"color": Color("8a97a5"), "points": [14, 13, 9, 3, 0]},
		],
		"my_stats": {"kills": 13, "losses": 4, "conquests": 3, "eliminations": 2,
			"cards_played": 4, "hero_damage": 96, "hero_kills": 1, "zone_deaths": 0,
			"hero_line": "PV 44/60 · PP +2 · NIV 9", "hero_dead": false},
		"hero_panel": {"faction_name": "Steel Phalanx", "portrait": null,
			"color": Color("36c5d9"), "level": 9, "pv_current": 44, "pv_max": 60,
			"pa": 12, "pp": 2, "is_dead": false},
		"debrief": [],
	}
	if with_betrayals:
		data["betrayals"] = _betrayal_payload()
	return data


# Ce que main.gd résout et pousse au rapport (View pure §6.1).
func _betrayal_payload() -> Dictionary:
	var stats := _demo_stats()
	var log_ := _demo_log()
	var pids := [1, 5, -2]
	var series: Array = [
		{"color": Color("36c5d9"), "points": [14, 16, 22, 30, 38]},
		{"color": Color("8a97a5"), "points": [14, 13, 9, 3, 0]},
	]
	var tp := BetrayalReport.find_turning_point(stats["territory_history"])
	return {
		"backstab": BetrayalReport.find_backstab(log_),
		"turning_point": tp,
		"turning_series": BetrayalReport.timeline_window(series,
			int(tp.get("from_index", 0)), int(tp.get("to_index", 0))),
		"matrix": BetrayalReport.aggression_matrix(log_, pids),
		"chain": BetrayalReport.elimination_chain(stats, log_),
		"names": {"1": "HAKIM", "5": "KOVACS", "-2": "[IA] VULTURE-7"},
		"colors": {"1": Color("36c5d9"), "5": Color("8a97a5"), "-2": Color("c0654f")},
	}


func _podium_rows() -> Array:
	return [
		{"pid": 1, "medal": "01", "titles": ["TITLE_BUTCHER"], "objective": "Contrôler 24 territoires",
			"completed": true, "has_reveal": true, "kills": 13, "conquests": 3, "eliminations": 2},
		{"pid": -2, "medal": "02", "titles": [], "objective": "Tenir l'Afrique 2 rounds",
			"completed": false, "has_reveal": true, "kills": 3, "conquests": 1, "eliminations": 0},
		{"pid": 5, "medal": "03", "titles": ["TITLE_GRAVEDIGGER"], "objective": "Tuer le héros de HAKIM",
			"completed": false, "has_reveal": true, "kills": 3, "conquests": 1, "eliminations": 0},
	]


func _test_report_full() -> void:
	var report = ReportScene.instantiate()
	add_child(report)
	await get_tree().process_frame
	report.populate(_report_payload(true))
	await get_tree().process_frame
	_chk(report.has_method("populate_betrayals"), "le rapport expose populate_betrayals()")
	_chk(report.tab_count() == 5, "5 onglets (XP JOUEUR / XP HÉROS / CLASSEMENT / BILAN / TRAHISONS)")
	_chk(report.is_betrayal_tab_visible(), "payload complet → onglet TRAHISONS VISIBLE")
	_chk(report.betrayal_section_count() >= 4,
		"les 4 sections du récit sont rendues (poignard, moment décisif, matrice, chaîne)")
	report.queue_free()
	await get_tree().process_frame


# =========================================================
# [C] Payload LEGACY — serveur non redéployé
# =========================================================
func _test_report_legacy() -> void:
	var report = ReportScene.instantiate()
	add_child(report)
	await get_tree().process_frame
	report.populate(_report_payload(false))          # aucune clé "betrayals"
	await get_tree().process_frame
	_chk(report.tab_count() == 5, "l'onglet existe toujours dans l'arbre (aucune retouche .tscn)")
	_chk(not report.is_betrayal_tab_visible(), "payload legacy → onglet TRAHISONS MASQUÉ (§9.2)")
	# Cas intermédiaire : journal PRÉSENT mais partie sans aucune trahison (guerre frontale).
	var frontal := _betrayal_payload()
	frontal["backstab"] = {}
	frontal["turning_point"] = {}
	frontal["turning_series"] = []
	frontal["chain"] = []
	report.populate_betrayals(frontal)
	await get_tree().process_frame
	_chk(report.is_betrayal_tab_visible(),
		"matrice non vide sans trahison → onglet VISIBLE (« GUERRE FRONTALE » est une info)")
	# Analyse totalement vide (journal reçu mais aucune attaque joueur-vs-joueur) → masqué.
	var empty := {"backstab": {}, "turning_point": {}, "turning_series": [],
		"matrix": BetrayalReport.aggression_matrix([], [1, 5]), "chain": [],
		"names": {}, "colors": {}}
	report.populate_betrayals(empty)
	await get_tree().process_frame
	_chk(not report.is_betrayal_tab_visible(), "analyse entièrement vide → onglet MASQUÉ")
	report.queue_free()
	await get_tree().process_frame


# =========================================================
# [D] Révélation théâtrale (LOT C)
# =========================================================
func _test_reveal_sequence() -> void:
	# 1) reduced_motion → révélation INSTANTANÉE, aucune attente.
	var previous = SettingsManager.get_comfort("reduced_motion")
	SettingsManager.set_comfort("reduced_motion", true)
	var r1 = ReportScene.instantiate()
	add_child(r1)
	await get_tree().process_frame
	r1.populate_podium(_podium_rows(), false)
	await get_tree().process_frame
	_chk(r1.reveal_pending_count() == 0, "reduced_motion → tous les objectifs révélés d'emblée")
	_chk(not r1.is_reveal_running(), "reduced_motion → aucune séquence en cours")
	r1.queue_free()
	await get_tree().process_frame

	# 2) Mode normal → séquence en cours, ordre DERNIER → VAINQUEUR, puis SKIP instantané.
	SettingsManager.set_comfort("reduced_motion", false)
	var r2 = ReportScene.instantiate()
	add_child(r2)
	await get_tree().process_frame
	r2.populate_podium(_podium_rows(), false)
	await get_tree().process_frame
	_chk(r2.is_reveal_running(), "mode normal → séquence de révélation lancée")
	_chk(r2.reveal_order_pids() == [5, -2, 1],
		"ordre de révélation : du DERNIER au vainqueur (le gagnant en dernier)")
	_chk(r2.reveal_pending_count() > 0, "des objectifs restent à révéler")
	# Le bouton REJOUER ne doit JAMAIS être bloqué par la mise en scène.
	_chk(r2.is_requeue_actionable(), "REJOUER reste actionnable pendant la révélation")
	r2.skip_reveal()
	await get_tree().process_frame
	_chk(r2.reveal_pending_count() == 0, "skip → tout est révélé immédiatement")
	_chk(not r2.is_reveal_running(), "skip → séquence terminée")
	# Idempotence : un second skip (double-clic) ne casse rien.
	r2.skip_reveal()
	_chk(r2.reveal_pending_count() == 0, "skip idempotent (double-clic sans effet de bord)")

	# 3) Podium PROVISOIRE (game_over pas encore reçu) : aucune mise en scène — il n'y a rien à
	#    révéler, et rejouer la séquence à l'arrivée du verdict serveur la doublerait.
	var r3 = ReportScene.instantiate()
	add_child(r3)
	await get_tree().process_frame
	var no_reveal := _podium_rows()
	for row in no_reveal:
		row["has_reveal"] = false
	r3.populate_podium(no_reveal, true)
	await get_tree().process_frame
	_chk(not r3.is_reveal_running(), "podium provisoire sans révélation → aucune séquence")
	r2.queue_free()
	r3.queue_free()
	await get_tree().process_frame
	SettingsManager.set_comfort("reduced_motion", previous)


# =========================================================
# [E] Carte de partage (LOT D) — composition seule
# =========================================================
func _test_share_card_composition() -> void:
	var payload := {
		"verdict": "VICTOIRE", "verdict_reason": "OBJECTIF ATTEINT", "is_victory": true,
		"podium": [{"name": "HAKIM", "color": Color("36c5d9"), "medal": "01"},
			{"name": "[IA] VULTURE-7", "color": Color("c0654f"), "medal": "02"},
			{"name": "KOVACS", "color": Color("8a97a5"), "medal": "03"}],
		"faction_name": "Steel Phalanx", "leader": "GÉNÉRAL VIKTOR \"IRONLINE\" STAHL",
		"portrait": null, "accent": Color("36c5d9"),
		"titles": ["BOUCHER", "CONQUÉRANT"],
		"timeline": [{"color": Color("36c5d9"), "points": [14, 16, 22, 30, 38]}],
		"betrayal_line": "HAKIM A POIGNARDÉ KOVACS — ROUND 5",
		"stats": [["KILLS", "13"], ["CONQUÊTES", "3"], ["DURÉE", "12:40"]],
	}
	for spec in ShareCard.FORMATS:
		var root := ShareCard.compose(payload, str(spec["id"]))
		_chk(root != null, "composition %s construite" % str(spec["id"]))
		_chk(root.custom_minimum_size == Vector2(spec["size"]),
			"composition %s dimensionnée %dx%d" % [str(spec["id"]), spec["size"].x, spec["size"].y])
		# Une composition vide serait un PNG noir livré au joueur : on vérifie qu'elle a du contenu.
		_chk(_descendants(root) > 20, "composition %s non vide (arbre peuplé)" % str(spec["id"]))
		root.free()
	# Payload MINIMAL (partie legacy : ni trahison ni timeline) → aucune erreur, sections omises.
	var bare := ShareCard.compose({"verdict": "DÉFAITE", "is_victory": false}, "landscape")
	_chk(bare != null and _descendants(bare) > 5, "payload minimal → composition dégradée mais valide")
	bare.free()
	# Résumé TEXTE du presse-papiers (aucune image : Godot 4 ne sait pas copier un PNG).
	var summary := ShareCard.clipboard_summary(payload)
	_chk(summary.find("wasteland-warfare.com") >= 0, "résumé presse-papiers : ramène vers le jeu")
	_chk(summary.find("VICTOIRE") >= 0, "résumé presse-papiers : porte le verdict")


func _descendants(n: Node) -> int:
	var total := 0
	for c in n.get_children():
		total += 1 + _descendants(c)
	return total
