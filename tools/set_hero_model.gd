extends SceneTree

# Outil pour définir hero_model_path dans un .tres de faction
# Utilisation: Godot -s res://tools/set_hero_model.gd -- --tres <path.tres> --glb <model.glb>

func _initialize() -> void:
	var tres := ""
	var glb := ""
	var a := OS.get_cmdline_user_args()

	# Parser les arguments
	for i in range(a.size()):
		if a[i] == "--tres" and i + 1 < a.size():
			tres = a[i + 1]
		elif a[i] == "--glb" and i + 1 < a.size():
			glb = a[i + 1]

	# Charger la ressource .tres
	var res = ResourceLoader.load(tres)
	if res == null:
		print("LOAD_FAIL ", tres)
		quit(1)
		return

	# Afficher l'ancienne valeur
	print("PREV=", res.get("hero_model_path"))

	# Définir la nouvelle valeur
	res.hero_model_path = glb

	# Sauvegarder
	var err := ResourceSaver.save(res, tres)
	print("SET_OK" if err == OK else "SAVE_FAIL")
	quit(0 if err == OK else 1)
