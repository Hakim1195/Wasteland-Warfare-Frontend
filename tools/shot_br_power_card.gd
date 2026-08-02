extends Node

# CAPTURES DE RECETTE — carte POUVOIR du Battle Royale dans ses 4 états + les 3 modales.
# ⚠️ À lancer SANS `--headless` (le rasteriseur factice rend des images vides) :
#   & <godot_console> --path frontend res://tools/shot_br_power_card.tscn --quit-after 400
# Les PNG partent dans le dossier passé par `--shots <dir>` (défaut : user://shots).

const TestBR := preload("res://tools/test_br_actions.gd")

func _out_dir() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return ProjectSettings.globalize_path("user://shots")


func _ready() -> void:
	await get_tree().process_frame
	AuthManager.user_id = TestBR.ME
	var dir := _out_dir()
	DirAccess.make_dir_recursive_absolute(dir)

	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame

	# 1) AUCUNE action disponible : coéquipier VIVANT, round 1 (reddition trop tôt).
	var idle := TestBR.br_state()
	idle["players"]["12"]["status"] = "alive"
	idle["players"]["12"]["hero_pv_current"] = 200
	idle["statistics"] = {"territory_history": []}
	await _shot(arena, idle, dir, "01_aucune_action")

	# 2) RÉANIMATION POSSIBLE : coéquipier mort, PV suffisants.
	await _shot(arena, TestBR.br_state(), dir, "02_reanimation_possible")

	# 3) VOTE DE REDDITION EN COURS : mon coéquipier a déjà voté (compteur 1/1 côté vivants).
	var voting := TestBR.br_state()
	voting["players"]["12"]["status"] = "alive"
	voting["players"]["12"]["hero_pv_current"] = 200
	voting["battle_royale"]["surrender"] = {"1": [12]}
	await _shot(arena, voting, dir, "03_vote_reddition")

	# 4) ORDRE DE TRAHISON REÇU : la ligne rouge + le bouton COUP D'ÉTAT.
	var traitor := TestBR.br_state()
	traitor["traitors"] = {"11": TestBR.FOE}
	await _shot(arena, traitor, dir, "04_ordre_recu")

	# 5-7) Les trois MODALES de confirmation, sur l'état « traître ».
	for spec in [["br_revive_%d" % TestBR.MATE, "05_modale_reanimer"],
				 ["br_surrender", "06_modale_reddition"],
				 ["br_coup", "07_modale_coup_etat"]]:
		arena._on_power_action_requested(str(spec[0]))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_save(dir, str(spec[1]))
		arena.hud.hide_confirm()
		await get_tree().process_frame

	print("[SHOTS] termine -> %s" % dir)
	get_tree().quit(0)


func _shot(arena, state: Dictionary, dir: String, name: String) -> void:
	GameState.update_from_json(state)
	arena._refresh()
	arena._push_power_card()
	# Deux frames : la première applique la mise en page, la seconde la DESSINE. Sans la seconde,
	# la capture montre l'état précédent (piège §7.4 du rapport tutoriel).
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(dir, name)


func _save(dir: String, name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[SHOT] %s.png  (%dx%d)" % [name, img.get_width(), img.get_height()])
