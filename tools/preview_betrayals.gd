extends Node

# OUTIL §8.121 (validation VISUELLE, hors test CI) — capture PNG du 5ᵉ onglet « TRAHISONS » du
# Rapport Post-Opération et de la RÉVÉLATION THÉÂTRALE, sur les données de démonstration du test.
# Un boot headless « 0 ERROR » ne prouve RIEN sur la mise en page (chevauchements, débordements,
# glyphes en « tofu ») : cette capture est la seule preuve.
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire (le viewport doit rendre — recette §8.100/§8.111) :
#   & <godot_console> --path frontend res://tools/preview_betrayals.tscn

const ReportScene := preload("res://scenes/game/operation_report.tscn")
const Harness := preload("res://tools/test_betrayal_report.gd")
const OUT_DIR := "C:/Users/Hakim/AppData/Local/Temp/claude/C--Users-Hakim-Documents-Wasteland-Warfare-Project/a271dbe2-d438-4f2c-a694-db39a1f9cb44/scratchpad"


func _ready() -> void:
	# Le harnais de test porte déjà l'état PUBLIC et les payloads de démonstration : on les
	# RÉUTILISE plutôt que d'en maintenir un second jeu, qui aurait divergé.
	var h = Harness.new()
	GameState.players = {
		"1": {"username": "HAKIM", "is_bot": false, "faction": "phalanges_acier",
			"hero_pv_current": 44, "hero_pv_max": 60, "hero_pa": 12, "hero_pp_current": 2,
			"hero_level": 9},
		"-2": {"username": "VULTURE-7", "is_bot": true, "faction": "barons_ferraille"},
		"5": {"username": "KOVACS", "is_bot": false, "faction": "chasseurs_ombres"},
	}
	GameState.statistics = h._demo_stats()

	var report = ReportScene.instantiate()
	add_child(report)
	await get_tree().process_frame
	report.populate(h._report_payload(true))
	# Podium DÉFINITIF → déclenche la révélation théâtrale (LOT C).
	report.populate_podium(h._podium_rows(), false)
	await get_tree().process_frame

	var out_dir := OUT_DIR if DirAccess.dir_exists_absolute(OUT_DIR) else OS.get_user_data_dir()

	# 1) CLASSEMENT pendant la révélation (une carte sur trois retournée).
	report._tabs.current_tab = 2
	await get_tree().create_timer(1.6).timeout
	await _shot(out_dir, "betrayals_reveal_mid")
	# 2) CLASSEMENT après le SKIP (tout révélé).
	report.skip_reveal()
	await get_tree().create_timer(0.5).timeout
	await _shot(out_dir, "betrayals_reveal_done")
	# 3) L'onglet TRAHISONS lui-même.
	report._tabs.current_tab = 4
	await get_tree().create_timer(0.4).timeout
	await _shot(out_dir, "betrayals_tab")
	print("[PREVIEW] onglet TRAHISONS visible = %s" % str(report.is_betrayal_tab_visible()))
	print("[PREVIEW] sections rendues = %d" % report.betrayal_section_count())
	# Libère le harnais : sans ça Godot signale « 1 resources still in use at exit ».
	h.free()
	get_tree().quit(0)


func _shot(dir_path: String, name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir_path, name_]
	img.save_png(path)
	print("[PREVIEW] %s  (%dx%d)" % [path, img.get_width(), img.get_height()])
