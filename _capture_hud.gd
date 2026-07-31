extends SceneTree

# Script JETABLE (recette §8.111) : rend la carte POUVOIR avec les actions BATTLE ROYALE, telles
# que `main._append_battle_royale_actions` les compose. À SUPPRIMER après usage.

func _initialize() -> void:
	await _run()

func _run() -> void:
	var hud = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(hud)
	await create_timer(1.0).timeout
	var h = hud.get_node_or_null("HUD")
	if h == null:
		for c in hud.get_children():
			if c.has_method("set_power_card"):
				h = c
				break
	if h == null:
		print("HUD introuvable")
		quit()
		return

	# Composition IDENTIQUE à celle produite par _append_battle_royale_actions (traître, un
	# coéquipier mort réanimable, reddition à 1 voix sur 3).
	h.set_power_card(
		[
			"RENFORTS : 5 · CARTES : 2/5",
			{"text": "⚠ " + tr("BR_COUP_ORDER") % "IRONJAW", "color": Color("d6453f")},
		],
		[
			{"label": tr("ABILITY_RATION"), "subtitle": "PP 10 → +40 PV",
			 "action": "ability_ration", "disabled": false, "tooltip": ""},
			{"label": tr("BR_REVIVE") + " — VULTURE-7",
			 "subtitle": tr("BR_REVIVE_COST_FMT") % 100,
			 "action": "br_revive_2", "disabled": false, "tooltip": tr("BR_REVIVE_DESC")},
			{"label": tr("BR_COUP_BUTTON"), "subtitle": tr("BR_COUP_SUBTITLE") % "IRONJAW",
			 "action": "br_coup", "disabled": false, "tooltip": tr("BR_COUP_DESC"),
			 "accent": Color("d6453f")},
			{"label": tr("BR_SURRENDER"), "subtitle": tr("BR_SURRENDER_VOTE") % [1, 3],
			 "action": "br_surrender", "disabled": false, "tooltip": tr("BR_SURRENDER_DESC")},
		])
	await create_timer(0.8).timeout
	root.get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_hud_br.png"))
	quit()
