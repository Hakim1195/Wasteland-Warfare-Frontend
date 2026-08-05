extends SceneTree

# Loupe AUTO-CENTRÉE : trouve le sujet par DIFFÉRENCE entre deux captures (avec / sans), puis
# agrandit sa boîte englobante au voisin le plus proche. C'est la parade du §8.139 au « décor qui se
# fait passer pour le soldat », et elle évite de deviner des coordonnées de crop à la main.
# Lancement SANS `--path` :
#   & <godot_console> --headless --script tools/zoom_diff.gd -- <avec.png> <sans.png> <marge> <facteur> <sortie>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		print("usage: <avec.png> <sans.png> <marge> <facteur> <sortie>")
		quit(1)
		return
	var a := Image.load_from_file(args[0])
	var b := Image.load_from_file(args[1])
	if a == null or b == null:
		print("illisible")
		quit(1)
		return
	var w: int = mini(a.get_width(), b.get_width())
	var h: int = mini(a.get_height(), b.get_height())
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	var count := 0
	for y in range(h):
		for x in range(w):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) < 0.02:
				continue
			x0 = mini(x0, x); x1 = maxi(x1, x); y0 = mini(y0, y); y1 = maxi(y1, y)
			count += 1
	if x1 < 0:
		print("AUCUNE difference : le sujet n'est pas rendu.")
		quit(1)
		return
	var margin := int(args[2])
	var factor := int(args[3])
	var rect := Rect2i(maxi(0, x0 - margin), maxi(0, y0 - margin), 0, 0)
	rect.size = Vector2i(mini(w - rect.position.x, x1 - x0 + 1 + margin * 2),
		mini(h - rect.position.y, y1 - y0 + 1 + margin * 2))
	print("sujet : x %d..%d (%d px) · y %d..%d (%d px) · %d pixels"
		% [x0, x1, x1 - x0 + 1, y0, y1, y1 - y0 + 1, count])
	var crop := a.get_region(rect)
	crop.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	crop.save_png(args[4])
	print("ecrit: %s (%d x %d)" % [args[4], crop.get_width(), crop.get_height()])
	quit(0)
