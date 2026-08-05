extends Node

# =================================================================================================
# SONDE §8.141 — LE RECTANGLE BLANC DU SOLDAT : LA PISTE BORNÉE DU §8 DU RAPPORT DE PIVOT.
#
# ╔═ CE QUE CETTE SONDE PROUVE, ET CE QU'ELLE NE PROUVE PAS ══════════════════════════════════════╗
# ║ Le §8 du `RAPPORT_SESSION_PIVOT_3D.md` a établi PAR LA MESURE que le soldat adverse se rend en ║
# ║ blanc opaque teinté par `modulate` : nœud visible, texture liée, échelle juste, alpha du        ║
# ║ fichier correct — et pourtant `pixels rendus ≈ modulation × BLANC`. Une hypothèse (filtre       ║
# ║ réclamant des mipmaps absents) a été testée et INFIRMÉE.                                        ║
# ║                                                                                                 ║
# ║ La piste retenue était : « afficher LA MÊME texture sur un simple quad `MeshInstance3D` dans le ║
# ║ MÊME SubViewport ». C'est exactement ce que fait ce fichier — et rien de plus. Il ne corrige     ║
# ║ rien : il DÉPARTAGE, et il rend des chiffres.                                                   ║
# ║                                                                                                 ║
# ║ Conditions reproduites À L'IDENTIQUE de `trench_fp_world.gd` (sans quoi la comparaison ne vaut  ║
# ║ rien) : `SubViewport` transparent + `own_world_3d`, Environment en `BG_CLEAR_COLOR`, caméra à    ║
# ║ FOV 55 tournée vers +Z, matériaux NON ÉCLAIRÉS.                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT FENÊTRÉ OBLIGATOIRE (la leçon des outils de recette : en `--headless` le pilote de
# rendu est un bouchon, un SubViewport n'y peint rien et la sonde rendrait un faux « tout est noir ») :
#   & <godot_console> --path frontend res://tools/probe_trench_quad.tscn
#
# LES QUATRE SUJETS, côte à côte, MÊME texture, MÊME viewport, MÊME caméra :
#   A. `Sprite3D` tel qu'il est EN JEU aujourd'hui                    → le témoin du défaut
#   B. quad `MeshInstance3D` + `StandardMaterial3D` (alpha scissor)   → la piste du §8
#   C. quad `MeshInstance3D` + alpha BLEND                            → le repli si le scissor crénelle
#   D. `Sprite3D` avec filtre NEAREST                                 → 2ᵉ hypothèse, gratuite ici

const Sprites := preload("res://scripts/game/trench_sprites.gd")

# Le sujet mesuré est `enemy_aim.png` — la frame nommée par le rapport (427 × 880, vérifiée saine).
const FRAME := "aim"
const VIEW_SIZE := Vector2i(1200, 600)
# Distance des sujets à l'œil ⚙ : assez près pour que chacun couvre plusieurs milliers de pixels
# (une mesure de couleur sur 20 px ne vaut rien), assez loin pour tenir à quatre dans le cadre.
const SUBJECT_Z := 3.2
const SUBJECT_SPACING := 1.15

var _viewport: SubViewport
var _out := ""


func _ready() -> void:
	_out = OS.get_user_data_dir() + "/trench_quad_probe"
	DirAccess.make_dir_recursive_absolute(_out)

	var texture := Sprites.enemy_texture(FRAME)
	if texture == null:
		push_error("probe_trench_quad: %s introuvable — rien a sonder." % Sprites.enemy_path(FRAME))
		get_tree().quit(1)
		return
	print("=== SONDE DU RECTANGLE BLANC (§8.141) ===")
	print("texture      : %s" % Sprites.enemy_path(FRAME))
	print("classe       : %s" % texture.get_class())
	print("dimensions   : %d x %d" % [texture.get_width(), texture.get_height()])

	# ⚠️ LIRE LES PIXELS DE LA TEXTURE ELLE-MÊME, AVANT TOUT RENDU. Si l'image importée était déjà
	# blanche, le défaut serait à l'import et toute la comparaison de rendu serait hors sujet. Le
	# rapport a mesuré l'alpha du FICHIER source ; on mesure ici ce que le MOTEUR a en mémoire.
	_report_texture_pixels(texture)

	_build_viewport(texture)
	# Trois frames : une pour la mise en page, une pour le premier rendu, une de marge.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_measure()
	get_tree().quit(0)


# =================================================================================================
# 1. CE QUE LE MOTEUR A EN MÉMOIRE (avant le moindre rendu 3D)
# =================================================================================================
func _report_texture_pixels(texture: Texture2D) -> void:
	var img := texture.get_image()
	if img == null:
		print("pixels source: ILLISIBLE (get_image() rend null)")
		return
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	# Moyenne des pixels OPAQUES seulement : la moyenne globale d'une image détourée à 47 % de
	# transparence dirait surtout « du noir transparent », ce qui n'apprend rien.
	var total := Vector3.ZERO
	var count := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var px := img.get_pixel(x, y)
			if px.a < 0.5:
				continue
			total += Vector3(px.r, px.g, px.b)
			count += 1
	if count == 0:
		print("pixels source: AUCUN pixel opaque — l'asset est vide.")
		return
	var mean := total / float(count)
	print("pixels source: RGB %d/%d/%d sur %d echantillons opaques"
		% [int(mean.x * 255.0), int(mean.y * 255.0), int(mean.z * 255.0), count])
	print("  -> si ces trois nombres valent ~255/255/255, le defaut est A L'IMPORT.")


# =================================================================================================
# 2. LE BANC — quatre sujets, mêmes conditions que le jeu
# =================================================================================================
func _build_viewport(texture: Texture2D) -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ⚠️ Un `Control` créé par code garde `size = (0,0)` — 8ᵉ récidive évitée. On lui POSE sa taille.
	container.size = Vector2(VIEW_SIZE)
	add_child(container)
	container.add_child(_viewport)

	var root := Node3D.new()
	_viewport.add_child(root)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	# Aucune brume, aucune lumière : les quatre sujets sont NON ÉCLAIRÉS, comme en jeu. Tout ce qui
	# différerait entre eux ne pourrait donc venir que de leur MODE DE RENDU — c'est la question posée.
	root.add_child(env)
	env.environment = environment

	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.05
	camera.far = 400.0
	camera.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	root.add_child(camera)

	# FOND SOMBRE OPAQUE derrière les sujets : sans lui, le viewport transparent rendrait des pixels
	# à alpha nul et « blanc sur rien » ne se distinguerait pas de « rien du tout ».
	var backdrop := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40.0, 20.0, 0.1)
	backdrop.mesh = plane
	backdrop.position = Vector3(0.0, 0.0, SUBJECT_Z + 1.5)
	var backdrop_mat := StandardMaterial3D.new()
	backdrop_mat.albedo_color = Color(0.10, 0.12, 0.14)
	backdrop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop.material_override = backdrop_mat
	root.add_child(backdrop)

	var x0 := -SUBJECT_SPACING * 1.5
	root.add_child(_subject_sprite(texture, Vector3(x0, 0.0, SUBJECT_Z),
		BaseMaterial3D.TEXTURE_FILTER_LINEAR, "A_sprite3d_jeu"))
	root.add_child(_subject_quad(texture, Vector3(x0 + SUBJECT_SPACING, 0.0, SUBJECT_Z),
		true, "B_quad_scissor"))
	root.add_child(_subject_quad(texture, Vector3(x0 + SUBJECT_SPACING * 2.0, 0.0, SUBJECT_Z),
		false, "C_quad_blend"))
	root.add_child(_subject_sprite(texture, Vector3(x0 + SUBJECT_SPACING * 3.0, 0.0, SUBJECT_Z),
		BaseMaterial3D.TEXTURE_FILTER_NEAREST, "D_sprite3d_nearest"))


# SUJET A / D — le `Sprite3D` du jeu, réglages recopiés de `trench_fp_world._build_enemy_sprite()`.
func _subject_sprite(texture: Texture2D, at: Vector3, filter: int, node_name: String) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.shaded = false
	sprite.double_sided = true
	sprite.texture_filter = filter
	sprite.pixel_size = Sprites.PIXEL_SIZE
	sprite.centered = true
	sprite.position = at
	return sprite


# SUJET B / C — LA PISTE DU §8 : un quad ordinaire et un matériau ordinaire.
# ⚠️ Le quad est dimensionné DEPUIS `pixel_size`, exactement comme le `Sprite3D` : les deux sujets
# doivent couvrir le même nombre de pixels, sinon on comparerait aussi des tailles.
func _subject_quad(texture: Texture2D, at: Vector3, scissor: bool, node_name: String) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(float(texture.get_width()), float(texture.get_height())) * Sprites.PIXEL_SIZE
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# BILLBOARD_FIXED_Y : la frame tourne autour de la verticale et fait face à la caméra, sans se
	# coucher quand celle-ci pique du nez. C'est le comportement voulu pour un soldat debout.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# La leçon du ciel (§8.140, défaut n° 1) : un maillage lointain se fait effacer par la brume.
	mat.disable_fog = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if scissor:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = mat
	node.position = at
	return node


# =================================================================================================
# 3. LA MESURE — quatre bandes verticales, la couleur moyenne de ce qui n'est pas le fond
# =================================================================================================
func _measure() -> void:
	var img := _viewport.get_texture().get_image()
	if img == null:
		push_error("probe_trench_quad: le SubViewport n'a rien rendu (lancement headless ?)")
		get_tree().quit(1)
		return
	img.save_png("%s/probe.png" % _out)
	print("\n=== MESURE DU RENDU (%d x %d) ===" % [img.get_width(), img.get_height()])
	print("capture      : %s/probe.png" % _out)
	var names := ["A_sprite3d_jeu", "B_quad_scissor", "C_quad_blend", "D_sprite3d_nearest"]
	var band := img.get_width() / 4
	var verdicts: Array = []
	for i in range(4):
		var stats := _band_stats(img, i * band, band)
		var mean: Vector3 = stats["mean"]
		var count: int = int(stats["count"])
		var whiteness: float = stats["whiteness"]
		var line := "%-20s : %5d px sujet · RGB %3d/%3d/%3d · ecart-type des canaux %.3f" % [
			names[i], count, int(mean.x * 255.0), int(mean.y * 255.0), int(mean.z * 255.0),
			whiteness]
		print(line)
		verdicts.append({"name": names[i], "count": count, "mean": mean, "spread": whiteness})

	print("\n--- LECTURE ---")
	for v in verdicts:
		var count: int = int(v["count"])
		var mean: Vector3 = v["mean"]
		var spread: float = float(v["spread"])
		var luma: float = (mean.x + mean.y + mean.z) / 3.0
		var verdict := ""
		if count < 500:
			verdict = "RIEN RENDU (le sujet n'apparait pas)"
		elif spread < 0.035 and luma > 0.80:
			verdict = "APLAT BLANC — le defaut du §8 est present sur ce mode de rendu"
		else:
			verdict = "IMAGE PEINTE (la texture s'echantillonne)"
		print("  %-20s -> %s" % [v["name"], verdict])
	print("\n⚠️ Le verdict FINAL est la CAPTURE, pas ces lignes : un aplat peut avoir du grain.")


# Statistiques d'une bande verticale : on ignore le fond (la teinte exacte de `backdrop_mat`) et
# les pixels transparents. `whiteness` est l'écart-type des trois canaux MOYENS — proche de 0 sur
# un aplat gris/blanc, franchement non nul sur une image peinte (uniforme, casque, boue).
func _band_stats(img: Image, x0: int, width: int) -> Dictionary:
	var total := Vector3.ZERO
	var count := 0
	var samples: Array[Vector3] = []
	for y in range(0, img.get_height(), 2):
		for x in range(x0, mini(x0 + width, img.get_width()), 2):
			var px := img.get_pixel(x, y)
			if px.a < 0.5:
				continue
			# Le fond est un aplat sombre CONNU : tout ce qui s'en écarte de plus de 0,03 par canal
			# est du sujet. On ne devine pas — on soustrait une couleur qu'on a posée soi-même.
			if absf(px.r - 0.10) < 0.03 and absf(px.g - 0.12) < 0.03 and absf(px.b - 0.14) < 0.03:
				continue
			var v := Vector3(px.r, px.g, px.b)
			total += v
			samples.append(v)
			count += 1
	if count == 0:
		return {"mean": Vector3.ZERO, "count": 0, "whiteness": 0.0}
	var mean := total / float(count)
	# Écart-type de la LUMINANCE sur l'échantillon : un aplat uniforme le rend quasi nul, une
	# peinture (ombres du casque, boue, ciel derrière) ne peut pas.
	var variance := 0.0
	for v in samples:
		var luma: float = (v.x + v.y + v.z) / 3.0
		var mean_luma: float = (mean.x + mean.y + mean.z) / 3.0
		variance += (luma - mean_luma) * (luma - mean_luma)
	return {"mean": mean, "count": count, "whiteness": sqrt(variance / float(count))}
