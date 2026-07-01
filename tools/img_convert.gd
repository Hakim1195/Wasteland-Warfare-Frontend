extends SceneTree

# Outil pour convertir n'importe quelle image vers PNG
# Utilisation: Godot -s res://tools/img_convert.gd -- --in <image_path> --out <output.png>

func _initialize() -> void:
	var inp := ""
	var out := ""
	var a := OS.get_cmdline_user_args()

	# Parser les arguments
	for i in range(a.size()):
		if a[i] == "--in" and i + 1 < a.size():
			inp = a[i + 1]
		elif a[i] == "--out" and i + 1 < a.size():
			out = a[i + 1]

	# Créer une nouvelle image
	var img := Image.new()

	# Charger l'image
	var err := img.load(inp)
	if err != OK:
		print("LOAD_FAIL ", err)
		quit(1)
		return

	# Sauvegarder en PNG — vérifier la valeur de retour (échec silencieux si dossier absent)
	var serr := img.save_png(out)
	if serr != OK:
		print("SAVE_FAIL ", serr)
		quit(1)
		return
	print("CONV_OK ", out)
	quit(0)
