extends Node

# =================================================================================================
# BANC DE RENDU §8.152 — PHOTOGRAPHIE CE QUE LE SOCLE FABRIQUE.
#
# ╔═ POURQUOI CET OUTIL EXISTE ══════════════════════════════════════════════════════════════════╗
# ║ Le cahier §5 exige, pour les lots 3D-A/B/C/D, des « captures des 4 armes lues et jugées », et ║
# ║ le §2.2quater impose que chaque lot livre une capture de SON rendu mise côte à côte avec la   ║
# ║ référence. Un boot headless « 0 ERROR » ne prouve RIEN du rendu (leçon §8.111) : il faut       ║
# ║ regarder. Ce banc est donc l'appareil photo du chantier, et il servira à TOUS les lots.        ║
# ║                                                                                               ║
# ║ Il répond aussi à une question légitime de Hakim : « comment tu fais de la 3D sans outil 3D ? ║
# ║ » — en montrant que les pièces sont CALCULÉES, pas importées. Chaque image ci-dessous sort de  ║
# ║ quelques lignes de GDScript, sans le moindre fichier de modèle.                               ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT **FENÊTRÉ OBLIGATOIRE** — surtout PAS `--headless` : le pilote de rendu factice
# renvoie `null` sur `viewport.get_texture()`. Un `SubViewport` a beau avoir sa propre cible de
# rendu, il n'y a aucun rasteriseur derrière. (Vérifié le 2026-08-27 ; l'en-tête de
# `gen_trench_renders.gd` affirmait le contraire et a été corrigé au même moment.)
#   & <godot_console> --path frontend res://tools/shot_vue3d_parts.tscn
# Sorties dans `user://vue3d_shots/` — le chemin absolu est imprimé à la fin.
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const WParts := preload("res://scripts/game/trench_wparts.gd")

const SHOT_SIZE := Vector2i(900, 900)
const OUT_DIR := "user://vue3d_shots"

var _lib: WMat


func _ready() -> void:
	_lib = WMat.new()
	var viewport := SubViewport.new()
	viewport.size = SHOT_SIZE
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var scene := Node3D.new()
	viewport.add_child(scene)

	# ⚠️ Un fond NEUTRE et une lumière FRANCHE, pas une jolie mise en scène : le but est de juger
	# la GÉOMÉTRIE et les MATÉRIAUX, pas l'éclairage. Une lumière rasante est ce qui révèle les
	# chanfreins — c'est exactement ce que la référence dit d'eux (« chamfers catch a specular
	# line »), donc le banc doit la fournir.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.70)
	# `ENV_OCCLUSION` du lot 3D-C : une arme à l'épaule ne voit qu'un quart du ciel. C'est ICI que
	# la constante s'applique (Godot n'a pas d'`envMapIntensity` par matériau) — cf. son pavé.
	env.ambient_light_energy = 1.6 * WMat.ENV_OCCLUSION * 4.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 3.2
	key.light_color = Color(1.0, 0.96, 0.90)
	key.rotation_degrees = Vector3(-38, 138, 0)
	scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.9
	fill.light_color = Color(0.62, 0.72, 0.92)
	fill.rotation_degrees = Vector3(-14, -46, 0)
	scene.add_child(fill)

	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.near = 0.005
	camera.far = 10.0
	scene.add_child(camera)

	var holder := Node3D.new()
	scene.add_child(holder)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await get_tree().process_frame

	var shots := _catalogue()
	var written := 0
	for shot in shots:
		for c in holder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var mi := MeshInstance3D.new()
		mi.mesh = shot["mesh"]
		holder.add_child(mi)
		_frame(camera, shot["aabb"], float(shot.get("zoom", 1.0)))
		await get_tree().process_frame
		await get_tree().process_frame
		var img := viewport.get_texture().get_image()
		var path := "%s/%s.png" % [OUT_DIR, shot["nom"]]
		if img.save_png(path) == OK:
			written += 1
			print("[SHOT] %-22s %6d triangles  -> %s"
				% [shot["nom"], int(shot["tris"]), ProjectSettings.globalize_path(path)])
		else:
			push_error("shot_vue3d_parts : ecriture impossible -> " + path)

	print("\n%d/%d vues rendues dans %s"
		% [written, shots.size(), ProjectSettings.globalize_path(OUT_DIR)])
	get_tree().quit(0 if written == shots.size() else 1)


# Cadre la caméra sur la boîte englobante de la pièce, en 3/4 — le même angle pour toutes, pour
# que les vues soient comparables entre elles et d'une passe à l'autre.
func _frame(camera: Camera3D, box: AABB, zoom: float) -> void:
	var centre := box.get_center()
	var rayon: float = maxf(box.size.length() * 0.5, 1e-4)
	var dist := rayon / tan(deg_to_rad(camera.fov * 0.5)) * 1.25 / zoom
	var dir := Vector3(0.62, 0.45, 0.65).normalized()
	camera.position = centre + dir * dist
	camera.look_at(centre, Vector3.UP)


# =================================================================================================
# LE CATALOGUE — une entrée par pièce à photographier
# =================================================================================================
func _catalogue() -> Array:
	var out := []
	out.append(_piece("01_rail_picatinny", Meshgen.picatinny(0.09), "alu"))
	out.append(_piece("02_boite_chanfreinee", Meshgen.box(0.030, 0.020, 0.050, 0.002, 3), "alu"))
	out.append(_piece("03_moleture", _molette(), "steel_black"))
	out.append(_piece("04_canon_couronne", Meshgen.tube_z(0.009, 0.0045, 0.10, 32), "steel"))
	out.append(_piece("05_chargeur_ajoure", _chargeur(), "polymer_tan"))
	out.append(_piece("06_proto_optique", _proto_optique(), "alu_fine"))
	# ── LOT 3D-A : les vraies pièces, montées avec les cotes du M4A1 de `rifle.js` ─────────────
	# ⚠️ Ces vues-ci sont MULTI-MATÉRIAUX : contrairement aux primitives ci-dessus, une pièce
	# d'arme range sa géométrie dans plusieurs seaux, et c'est précisément la séparation de
	# classes (§2.2 du lot 3D-C) qu'on veut juger à l'œil.
	out.append(_assemblage("10_optique_m4a1", _optique_m4a1()))
	out.append(_assemblage("11_rail_et_hausse", _rail_et_hausse()))
	out.append(_assemblage("12_carcasse_haute", _carcasse_haute()))
	out.append(_assemblage("13_chargeur", _chargeur_reel()))
	out.append(_assemblage("14_garde_main", _garde_main()))
	out.append(_assemblage("15_glissiere_p19", _glissiere_p19()))
	return out


# Photographie un ASSEMBLAGE complet : chaque seau reçoit son matériau, avec son usure d'arête.
# C'est le mode qui servira à toutes les comparaisons avec les captures de Hakim.
func _assemblage(nom: String, asm) -> Dictionary:
	var mesh := ArrayMesh.new()
	var tris := 0
	var boite := AABB()
	var premier := true
	for cle in asm.buckets:
		var g = Meshgen.merge_all(asm.buckets[cle])
		if g == null or g.is_empty():
			continue
		var use := WMat.apply_wear_mask(g, cle)
		var mat := _lib.get_worn(cle) if use else _lib.get_material(cle)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.to_surface_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
		tris += g.tri_count()
		if premier:
			boite = g.aabb()
			premier = false
		else:
			boite = boite.merge(g.aabb())
	return {"nom": nom, "mesh": mesh, "aabb": boite, "tris": tris}


# L'optique du M4A1, aux cotes EXACTES de `rifle.js` l. 221.
func _optique_m4a1():
	var asm = Meshgen.Assembly.new("optique")
	WParts.build_optic(asm, {
		"rTube": 0.0155, "len": 0.052, "hood": 0.007, "y": 0.142, "z": -0.022,
		"railTop": 0.1036, "matBody": "alu_fine", "matSteel": "steel",
	})
	return asm


func _rail_et_hausse():
	var asm = Meshgen.Assembly.new("rail")
	WParts.add_rail(asm, "alu", -0.10, 0.02, 0.1036)
	WParts.add_rear_sight(asm, "polymer", "alu", 0.0, 0.1036, -0.05, true)
	WParts.add_front_sight(asm, "polymer", "alu", 0.0, 0.1036, -0.09, true)
	return asm


func _carcasse_haute():
	var asm = Meshgen.Assembly.new("upper")
	WParts.add_upper_receiver(asm, "alu", "steel", "cavity", {
		"zRear": 0.055, "zFront": -0.143, "bore": 0.075, "r": 0.0192,
		"portZ": -0.052, "railTop": 0.1036,
	})
	WParts.add_rollmark(asm, "cavity",
		{"x": -0.0149, "y": 0.0355, "z": -0.031, "h": 0.0036})
	return asm


func _chargeur_reel():
	var asm = Meshgen.Assembly.new("mag")
	WParts.build_magazine(asm, null, {
		"w": 0.0255, "d": 0.0655, "len": 0.212, "curve": 0.03,
		"segs": 8, "witness": 4, "poly": "polymer",
	})
	return asm


func _garde_main():
	var asm = Meshgen.Assembly.new("handguard")
	WParts.add_handguard(asm, "alu", {
		"matPanel": "polymer", "y": 0.075, "z0": -0.145, "z1": -0.385, "r": 0.0235,
		"sides": 8, "slatW": 0.0166, "slatT": 0.0036, "slots": 4, "braces": 3,
		"topFrom": -0.187, "topTo": -0.329,
	})
	WParts.add_rail(asm, "alu", -0.381, -0.147, 0.1036)
	return asm


func _glissiere_p19():
	var asm = Meshgen.Assembly.new("slide")
	WParts.build_slide(asm, {
		"w": 0.0262, "h": 0.0248, "len": 0.183, "mat": "steel_black", "zRear": 0.052,
	})
	return asm


func _piece(nom: String, mesh_data, cle: String) -> Dictionary:
	var g = Meshgen.merge_all([mesh_data])
	# L'USURE D'ARÊTE du lot 3D-C : c'est elle qui fait qu'une pièce lit comme du métal utilisé et
	# non comme du plastique neuf. Sans elle, tout ce banc serait uniformément mat.
	var use := WMat.apply_wear_mask(g, cle)
	var mat := _lib.get_worn(cle) if use else _lib.get_material(cle)
	return {
		"nom": nom,
		"mesh": Meshgen.to_array_mesh(g, mat),
		"aabb": g.aabb(),
		"tris": g.tri_count(),
	}


# Une molette de réglage d'optique : cylindre + bande moletée + chapeau. ⭐ C'est la pièce que les
# captures de Hakim imposent (« molettes de réglage latérales, surfaces MOLETÉES »).
func _molette():
	return Meshgen.merge_all([
		Meshgen.rod_z(0.0085, 0.0085, 0.014, 28),
		Meshgen.knurl_band(0.0086, 0.011, 40, 0.00055, 5),
		Meshgen.lathe_z([
			Vector2(0.007, 0.0),
			Vector2(0.007, 0.0080),
			Vector2(0.0085, 0.0088),
			Vector2(0.0085, 0.0),
		], 28),
	])


# Un chargeur : boîte arrondie PERCÉE de sa fenêtre témoin — la pièce qui exerce la couture
# d'anneau du lot 3D-0 (celle qui a remplacé le « trou de serrure » défaillant).
func _chargeur():
	var corps := Meshgen.extrude(Meshgen.round_rect(0.026, 0.019, 0.005, 4), 0.075,
		{"bevel": 0.0012, "holes": [Meshgen.round_rect(0.017, 0.010, 0.003, 4)]})
	corps.apply_transform(Transform3D(Basis(Vector3(1, 0, 0), PI * 0.5), Vector3.ZERO))
	return corps


# Un PROTOTYPE d'optique point rouge, assemblé uniquement avec les primitives du socle : corps
# tubulaire, bagues avant/arrière, deux molettes moletées, embase et pied de montage.
# ⚠️ Ce n'est PAS le lot 3D-B2 — c'est une démonstration que le vocabulaire du socle suffit à
# bâtir la pièce. Le vrai modèle viendra de `parts.js`, avec ses cotes.
func _proto_optique():
	var parts := []
	# Corps.
	parts.append(Meshgen.tube_z(0.0155, 0.0138, 0.062, 40))
	# Bagues avant et arrière, légèrement plus larges.
	for z in [-0.031, 0.031]:
		var bague := Meshgen.lathe_z([
			Vector2(-0.004, 0.0138),
			Vector2(-0.004, 0.0172),
			Vector2(0.004, 0.0172),
			Vector2(0.004, 0.0138),
		], 40)
		bague.translate(0.0, 0.0, z)
		parts.append(bague)
		var kn := Meshgen.knurl_band(0.0173, 0.007, 56, 0.0005, 3)
		kn.translate(0.0, 0.0, z)
		parts.append(kn)
	# Les deux molettes : latérale (dérive) et supérieure (hausse).
	var m1 = _molette()
	m1.apply_transform(Transform3D(Basis(Vector3(0, 1, 0), PI * 0.5),
		Vector3(0.019, 0.0, 0.004)))
	parts.append(m1)
	var m2 = _molette()
	m2.apply_transform(Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5),
		Vector3(0.0, 0.019, 0.004)))
	parts.append(m2)
	# Pied de montage + embase sur rail.
	var pied := Meshgen.box(0.020, 0.020, 0.030, 0.0015, 2)
	pied.translate(0.0, -0.020, 0.0)
	parts.append(pied)
	var embase := Meshgen.box(0.026, 0.006, 0.034, 0.0012, 2)
	embase.translate(0.0, -0.031, 0.0)
	parts.append(embase)
	return Meshgen.merge_all(parts)
