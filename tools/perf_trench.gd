extends Node
# OUTIL (hors CI) — BUDGET DE PERFORMANCE du monde 3D texturé de LA TRANCHÉE.
#
# ╔═ ⚠️⚠️ ON MESURE DES MILLISECONDES, PAS DES IMAGES PAR SECONDE ════════════════════════════════╗
# ║ La session §8.139 a rendu « 13,33 ms pour les trois configurations, soit 75,00 FPS pile ».      ║
# ║ Ce n'était pas une performance : c'était la VSYNC. Trois rendus de coûts très différents        ║
# ║ affichaient le même chiffre parce qu'ils attendaient tous le même balayage écran. Un compteur   ║
# ║ de FPS ne peut PAS mesurer un rendu plus rapide que l'écran — il mesure l'écran.                ║
# ║ D'où les deux règles de ce fichier : vsync COUPÉE avant le premier chiffre, et temps de frame   ║
# ║ en ms (le budget du bon de commande : pas plus de +2 ms vs le greybox).                         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire : en headless, rien ne rend, donc rien ne se mesure.
#   & <godot_console> --path frontend res://tools/perf_trench.tscn

const Blockout := preload("res://scripts/game/trench_blockout.gd")
const WorldScene := preload("res://scenes/game/trench_fp_world.tscn")

const WARMUP_FRAMES := 90       # compilation des shaders, montée des caches : jamais dans la mesure
const SAMPLE_FRAMES := 240


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("vsync : %s   (0 = DISABLED)" % DisplayServer.window_get_vsync_mode())

	var greybox := await _measure(true)
	var textured := await _measure(false)
	var delta := textured - greybox
	print("\n  greybox nu ......... %6.3f ms/frame" % greybox)
	print("  monde texture ...... %6.3f ms/frame" % textured)
	print("  ecart .............. %+6.3f ms   (budget : +2,000 ms)" % delta)
	print("\n%s" % ("DANS LE BUDGET" if delta <= 2.0 else "HORS BUDGET"))
	get_tree().quit(0 if delta <= 2.0 else 1)


func _measure(greybox: bool) -> float:
	Blockout.force_greybox = greybox
	var world = WorldScene.instantiate()
	add_child(world)
	world.set_pose(2, "up", true)
	for i in range(WARMUP_FRAMES):
		await get_tree().process_frame
	# La visée BALAIE pendant la mesure : une caméra immobile ne fait travailler ni le tri, ni le
	# recouvrement, ni le pavage triplanaire sous des angles rasants — elle mesurerait le cas le
	# plus favorable et l'appellerait « la performance ».
	# ⚠️ On chronomètre la FRAME ENTIÈRE (mur à mur), et non `Performance.TIME_PROCESS` : ce dernier
	# ne compte que le script, or tout ce que ce lot ajoute est du travail de RENDU.
	var total := 0.0
	for i in range(SAMPLE_FRAMES):
		world.set_aim(sin(float(i) * 0.05) * 32.0, sin(float(i) * 0.017) * 14.0)
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		total += float(Time.get_ticks_usec() - t0) / 1000.0
	world.queue_free()
	await get_tree().process_frame
	return total / float(SAMPLE_FRAMES)
