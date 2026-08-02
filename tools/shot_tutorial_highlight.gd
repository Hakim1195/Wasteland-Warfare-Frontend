extends Node

# CAPTURE DE RECETTE — surlignage plateau de l'étape ATTAQUER (liseré or du télégraphe réemployé).
# ⚠️ SANS `--headless` : le rasteriseur factice rend des images vides.
#   & <godot_console> --path frontend res://tools/shot_tutorial_highlight.tscn -- --shots <dir>

const TestTH := preload("res://tools/test_tutorial_highlight.gd")

func _ready() -> void:
	await get_tree().process_frame
	AuthManager.user_id = TestTH.ME
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	var dir := args[i + 1] if (i >= 0 and i + 1 < args.size()) \
		else ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)

	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	GameState.update_from_json(TestTH.STATE)
	arena._refresh()
	await get_tree().process_frame

	# AVANT : plateau nu, aucun liseré — la comparaison est ce qui prouve que le liseré vient de là.
	await _shot(dir, "10_plateau_sans_surlignage")

	# APRÈS : le coach désigne la meilleure cible et ENRICHIT son texte.
	TutorialManager.bind_arena(arena, arena.hud)
	TutorialManager.guided = true
	TutorialManager._steps_done.clear()
	TutorialManager._current = {}
	TutorialManager._queue.clear()
	TutorialManager._arm("attack")
	await _shot(dir, "11_plateau_surlignage_attaque")

	print("[SHOTS] termine -> %s" % dir)
	get_tree().quit(0)

func _shot(dir: String, name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[SHOT] %s.png" % name)
