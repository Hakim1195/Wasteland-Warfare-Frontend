extends Node
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — RENDUS DU BLOCKOUT : la matière première de l'img2img (§4.3 / §7.1).
#
# Photographie les 10 POSES de caméra du blockout en PNG 2560×1440 et les dépose dans
# `user://trench_renders/`. Ces images ne sont PAS des assets de jeu : ce sont les gabarits de
# PERSPECTIVE que Hakim passera en img2img à faible denoise (0,45-0,6) pour obtenir les décors.
#
# ╔═ POURQUOI CE DÉTOUR PLUTÔT QU'UN PROMPT DIRECT ═══════════════════════════════════════════════╗
# ║ Le décor doit s'aligner AU PIXEL avec la scène 3D qui se compose par-dessus (soldat,          ║
# ║ traçantes, marqueurs au sol). Un décor « inventé » par un modèle génératif aurait sa propre    ║
# ║ ligne d'horizon et son propre point de fuite : le soldat flotterait au-dessus du parapet ou    ║
# ║ s'y enfoncerait. En partant du RENDU de la pose, la perspective est juste par construction —   ║
# ║ l'img2img ne fait que peindre par-dessus. C'est le verrou n° 3 du chantier.                    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Le nommage de sortie est EXACTEMENT celui attendu par le jeu (`pose_{0..4}_{up|down}.png`) :
# une fois stylisées, les images se déposent telles quelles dans
# `frontend/assets/images/trench/` — aucune ligne de code à toucher (§7.1).
#
# LANCEMENT (fenêtré ou headless — le SubViewport rend dans les deux cas) :
#   & <godot_console> --path frontend res://tools/gen_trench_renders.tscn --quit-after 600
# =================================================================================================

const Geo := preload("res://scripts/game/trench_geometry.gd")
const BlockoutScene := preload("res://scenes/game/trench_arena_blockout.tscn")

const RENDER_SIZE := Vector2i(2560, 1440)
# MÊME champ de vision que la vue de jeu (`trench_fp_world.CAMERA_FOV`) — c'est la condition pour
# que le décor peint par-dessus coïncide avec la scène 3D. ⚠️ Si l'un bouge, l'autre doit suivre.
const CAMERA_FOV := 55.0
const OUT_DIR := "user://trench_renders"


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.size = RENDER_SIZE
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var arena := Node3D.new()
	viewport.add_child(arena)

	# Un ciel FRANC : l'img2img a besoin d'une séparation nette sol/ciel pour poser son horizon.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.40, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.24, 0.28)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	arena.add_child(world_env)

	var blockout = BlockoutScene.instantiate()
	arena.add_child(blockout)

	var camera := Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.near = 0.05
	camera.far = 400.0
	arena.add_child(camera)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await get_tree().process_frame

	var written := 0
	for pose in Geo.all_poses():
		var eye: Vector3 = blockout.pose_transform(int(pose["pos"]), String(pose["stance"])).origin
		camera.position = eye
		# Horizon au centre, comme au repos dans le jeu (le suivi de visée s'ajoute PAR-DESSUS).
		camera.look_at(eye + Vector3(0.0, 0.0, 1.0), Vector3.UP)
		# Deux frames : la première monte la caméra, la seconde rend la scène cadrée.
		await get_tree().process_frame
		await get_tree().process_frame
		var image := viewport.get_texture().get_image()
		var path := "%s/pose_%d_%s.png" % [OUT_DIR, int(pose["pos"]), String(pose["stance"])]
		if image.save_png(path) == OK:
			written += 1
			print("[RENDER] %s  (%dx%d)" % [ProjectSettings.globalize_path(path),
				image.get_width(), image.get_height()])
		else:
			push_error("gen_trench_renders: ecriture impossible -> %s" % path)

	print("gen_trench_renders: %d/%d poses rendues dans %s"
		% [written, Geo.all_poses().size(), ProjectSettings.globalize_path(OUT_DIR)])
	get_tree().quit(0 if written == Geo.all_poses().size() else 1)
