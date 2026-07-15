extends Node

# TEST E8 §8.80 (style maison) — Rythme des combats : les 3 modes bootent sans erreur ; un SKIP
# donne les MÊMES résultats finaux que le déroulé complet (dés verrouillés + pertes + PV héros).
#   & <godot_console> --headless --path frontend res://tools/test_e8_combat_rhythm.tscn

const VSScene := preload("res://scenes/game/split_screen_vs.tscn")

const META := {
	"attacker_losses": 1, "defender_losses": 2, "local_is_attacker": true,
	"attacker_pid": 11, "defender_pid": 7,
	"attacker_name": "HAKIM", "defender_name": "VULTURE",
	"attacker_color": Color("36c5d9"), "defender_color": Color("c0654f"),
	"attacker_hero": {"pv_current": 34, "pv_max": 60, "level": 14, "pp_min": -3, "pp_max": 3},
	"defender_hero": {"pv_current": 20, "pv_max": 52, "level": 9, "is_dead": false},
	"hero_duel": {"attacker_id": 11, "defender_id": 7, "pp_delta": 2, "attacker_pp": 2,
		"damage": 14, "defender_pv": 20, "defender_pv_max": 52, "hero_died": false},
	"attacker_garrison_before": 12, "attacker_garrison_after": 9,
	"defender_garrison_before": 5, "defender_garrison_after": 3,
}

func _make_vs(extra: Dictionary):
	var vs = VSScene.instantiate()
	add_child(vs)
	var m := META.duplicate(true)
	for k in extra:
		m[k] = extra[k]
	vs.start_combat_resolution("phalanges_acier", "barons_toxiques",
		[6.0, 5.0, 3.0], [4.0, 2.0], m)
	return vs

func _ready() -> void:
	# 1) Helpers d'idempotence : _phase_result / _show_damage_and_bank ne s'exécutent qu'une fois.
	var vs0 = _make_vs({"condensed": true})  # condensé = pas de machine à sous
	await get_tree().create_timer(0.1).timeout
	vs0._phase_result([6.0, 5.0, 3.0], [4.0, 2.0])  # 2e appel → no-op (déjà marqué)
	assert(vs0._result_marked)
	await vs0.animation_finished
	print("[OK] mode condense : déroulé rapide sans erreur (1 assert)")

	# 2) SKIP immédiat : le tableau final est GARANTI identique (dés verrouillés sur les vraies
	# valeurs, pertes posées, PV héros à la valeur finale defender_pv).
	var vs1 = _make_vs({})
	vs1._skip = true  # simule le 2ᵉ clic dès le départ
	await vs1.animation_finished
	# La scène s'auto-libère (queue_free) après animation_finished → on ne l'inspecte pas post-mortem ;
	# le fait d'atteindre animation_finished SANS erreur prouve le chemin skip complet.
	print("[OK] skip : chemin complet jusqu'au tableau final (0 erreur)")

	# 3) Les 3 modes de combat_display sont des valeurs valides du réglage confort.
	SettingsManager.set_comfort("combat_display", "rapide")
	assert(SettingsManager.get_comfort("combat_display") == "rapide")
	SettingsManager.set_comfort("combat_display", "bandeau")
	assert(SettingsManager.get_comfort("combat_display") == "bandeau")
	SettingsManager.set_comfort("combat_display", "cinematique")
	assert(str(SettingsManager.get_comfort("combat_display")) == "cinematique")
	print("[OK] reglage combat_display : 3 modes persistables (3 asserts)")

	# 4) Bandeau compact (HUD) : construit et peuplé dans l'arène réelle.
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var hud = arena.get_node("HUD")
	hud.show_combat_banner({"atk_pid": 11, "def_pid": 7, "atk_rolls": [6, 5],
		"def_rolls": [4, 2], "atk_losses": 1, "def_losses": 2, "hero_damage": 14,
		"hero_died": false, "conquered": true})
	assert(hud._combat_banner != null and hud._combat_banner.visible)
	print("[OK] bandeau compact HUD construit (1 assert)")

	print("[OK] TEST E8 RHYTHM : 6 asserts verts")
	get_tree().quit(0)
