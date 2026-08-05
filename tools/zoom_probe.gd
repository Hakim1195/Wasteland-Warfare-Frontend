extends SceneTree

# Loupe de recette : découpe une région d'une capture et l'agrandit au voisin le plus proche (aucun
# lissage — on veut voir les pixels tels qu'ils sont, pas une interpolation flatteuse).
# Lancement SANS `--path` (donc sans autoload) :
#   & <godot_console> --headless --script tools/zoom_probe.gd -- <png> <x> <y> <w> <h> <facteur> <sortie>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 7:
		print("usage: <png> <x> <y> <w> <h> <facteur> <sortie>")
		quit(1)
		return
	var src := Image.load_from_file(args[0])
	if src == null:
		print("illisible: %s" % args[0])
		quit(1)
		return
	var rect := Rect2i(int(args[1]), int(args[2]), int(args[3]), int(args[4]))
	var factor := int(args[5])
	var crop := src.get_region(rect)
	crop.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	crop.save_png(args[6])
	print("ecrit: %s (%d x %d)" % [args[6], crop.get_width(), crop.get_height()])
	quit(0)
