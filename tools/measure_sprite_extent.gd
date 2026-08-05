extends SceneTree

# Mesure l'étendue OPAQUE réelle d'une frame de soldat : le cadre du PNG n'est pas la silhouette.
# `trench_sprites.PIXEL_SIZE` convertit des PIXELS DE CADRE en mètres ; si l'homme peint n'occupe
# que les deux tiers de son cadre, sa taille en jeu n'est pas celle qu'on croit.
# Lancement SANS `--path` :
#   & <godot_console> --headless --script tools/measure_sprite_extent.gd -- <png> [<png> ...]

const REFERENCE_PX := 1024.0
const REFERENCE_M := 1.80


func _init() -> void:
	var pixel_size: float = REFERENCE_M / REFERENCE_PX
	print("pixel_size en vigueur : %.6f m/px (%.2f m pour %d px de cadre)"
		% [pixel_size, REFERENCE_M, int(REFERENCE_PX)])
	for path in OS.get_cmdline_user_args():
		var img := Image.load_from_file(path)
		if img == null:
			print("%s : ILLISIBLE" % path)
			continue
		var w := img.get_width()
		var h := img.get_height()
		var x_min := w
		var x_max := -1
		var y_min := h
		var y_max := -1
		for y in range(h):
			for x in range(w):
				if img.get_pixel(x, y).a < 0.5:
					continue
				x_min = mini(x_min, x)
				x_max = maxi(x_max, x)
				y_min = mini(y_min, y)
				y_max = maxi(y_max, y)
		if x_max < 0:
			print("%s : entierement transparent" % path.get_file())
			continue
		var opaque_h := y_max - y_min + 1
		var opaque_w := x_max - x_min + 1
		# Le bas de la silhouette est-il collé au bas du cadre ? Si non, le soldat FLOTTE : son
		# ancrage au sol (calculé depuis la hauteur du CADRE) le suspend au-dessus de la tranchée.
		print("%-18s cadre %d x %d · opaque %d x %d (x %d..%d, y %d..%d) · marge basse %d px"
			% [path.get_file(), w, h, opaque_w, opaque_h, x_min, x_max, y_min, y_max, h - 1 - y_max])
		print("%-18s -> cadre = %.3f m · silhouette peinte = %.3f m · pieds a %.3f m du bas"
			% ["", float(h) * pixel_size, float(opaque_h) * pixel_size,
			float(h - 1 - y_max) * pixel_size])
	quit(0)
