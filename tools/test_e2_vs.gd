extends Node

# TEST E2 §8.74 (style maison) — Split-Screen VS enrichi héros.
# Deux résolutions complètes en headless : (a) stub INTÉGRAL (duel + permadeath), (b) stub
# hero_duel = null (héros non initialisés). Lancement :
#   & <godot_console> --headless --path frontend res://tools/test_e2_vs.tscn
# Succès = lignes « [OK] … » + code retour 0 + AUCUNE ligne ERROR.

const VS := preload("res://scripts/game/split_screen_vs.gd")
const VSScene := preload("res://scenes/game/split_screen_vs.tscn")

func _ready() -> void:
	# 1) Helpers purs — critères d'acceptation E2 : PV avant = defender_pv + damage (borné
	# pv_max en overkill) ; jauge PP TOUJOURS bornée [pp_min, pp_max].
	assert(VS.duel_pre_pv({"defender_pv": 46, "damage": 14, "defender_pv_max": 60}) == 60)
	assert(VS.duel_pre_pv({"defender_pv": 30, "damage": 12, "defender_pv_max": 60}) == 42)
	assert(VS.duel_pre_pv({"defender_pv": 0, "damage": 99, "defender_pv_max": 60}) == 60)
	assert(VS.pp_gauge_value({"attacker_pp": 9}, {"pp_min": -3, "pp_max": 3}) == 3)
	assert(VS.pp_gauge_value({"attacker_pp": -9}, {"pp_min": -3, "pp_max": 3}) == -3)
	print("[OK] duel_pre_pv + bornage PP (5 asserts)")

	# 2) VS COMPLET (duel + permadeath) : le stub couvre identités, barres, PP, garnisons,
	# flotteurs et tampon « HÉROS ABATTU ». Jets en FLOAT (piège JSON §5).
	var meta_full := {
		"attacker_losses": 1, "defender_losses": 2, "time_bank_bonus": 10,
		"local_is_attacker": true,
		"attacker_pid": 11, "defender_pid": 7,
		"attacker_name": "HAKIM", "defender_name": "VULTURE",
		"attacker_color": Color("36c5d9"), "defender_color": Color("c0654f"),
		"attacker_hero": {"pv_current": 34, "pv_max": 60, "level": 14,
			"pp_min": -3, "pp_max": 3},
		"defender_hero": {"pv_current": 0, "pv_max": 52, "level": 9, "is_dead": true},
		"hero_duel": {"attacker_id": 11, "defender_id": 7, "pp_delta": 2, "attacker_pp": 2,
			"damage": 14, "defender_pv": 0, "defender_pv_max": 52, "hero_died": true},
		"attacker_garrison_before": 12, "attacker_garrison_after": 9,
		"defender_garrison_before": 5, "defender_garrison_after": 0,
	}
	var vs1 = VSScene.instantiate()
	add_child(vs1)
	vs1.start_combat_resolution("phalanges_acier", "barons_toxiques",
		[6.0, 5.0, 3.0], [4.0, 2.0], meta_full)
	# L'UI héros est construite AVANT le premier await interne → observable dès le retour.
	assert(vs1.debug_duel_ui_visible())
	await vs1.animation_finished
	print("[OK] VS complet (duel + permadeath) joue sans erreur")

	# 3) VS hero_duel = null : AUCUNE UI héros (pas de barre/flotteur/0 fantôme), zéro erreur.
	var vs2 = VSScene.instantiate()
	add_child(vs2)
	vs2.start_combat_resolution("", "", [3.0], [5.0], {
		"attacker_losses": 1, "defender_losses": 0, "hero_duel": null,
	})
	assert(not vs2.debug_duel_ui_visible())
	await vs2.animation_finished
	print("[OK] VS hero_duel=null : UI héros masquée")

	print("[OK] TEST E2 VS : 7 asserts verts")
	get_tree().quit(0)
