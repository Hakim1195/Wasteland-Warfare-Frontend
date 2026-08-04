extends Node

# =================================================================================================
# OUTIL §8.139 (validation VISUELLE, hors test CI) — l'habillage procédural SEUL, sur fond plat.
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire (le viewport doit rendre — recette §8.100/§8.111) :
#   & <godot_console> --path frontend res://tools/shot_trench_ambient.tscn
#
# ╔═ POURQUOI UNE CAPTURE ISOLÉE PLUTÔT QUE LA SCÈNE DE JEU ══════════════════════════════════════╗
# ║ Sur la scène complète, brume et cendres se noient dans le blockout : impossible de distinguer  ║
# ║ « la nappe est trop discrète » de « la nappe ne peint RIEN » (texture de bruit encore en cours ║
# ║ de génération, uniforme jamais poussé, nœud à taille nulle...). Sur un aplat gris de référence,║
# ║ le moindre pixel touché se COMPTE. C'est la contre-épreuve du faux vert appliquée à une image :║
# ║ on ne mesure pas si c'est joli, on mesure d'abord que ça EXISTE.                               ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

const Ambient := preload("res://scripts/game/trench_ambient.gd")
const FLAT := Color(0.5, 0.5, 0.5)


func _ready() -> void:
	var out_dir := OS.get_user_data_dir() + "/trench_ambient_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var flat := ColorRect.new()
	flat.color = FLAT
	flat.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(flat)

	# Aplat de référence AVANT toute ambiance : c'est lui qui sert de « zéro » à la mesure.
	await get_tree().create_timer(0.4).timeout
	await _shot(out_dir, "00_fond_plat")

	var amb = Ambient.new()
	add_child(amb)
	await get_tree().process_frame
	_diagnose(amb)
	# La texture de bruit se génère sur un THREAD : capturer trop tôt donnerait une nappe vide, et
	# on conclurait à tort que le shader ne peint pas. On laisse largement le temps, et la mesure
	# distinguera de toute façon « rien » de « discret ».
	await get_tree().create_timer(2.5).timeout
	await _shot(out_dir, "01_debout_mouvement_normal")

	amb.set_stance("down")
	await get_tree().create_timer(1.2).timeout
	await _shot(out_dir, "02_accroupi")

	amb.set_stance("up")
	amb.set_reduced_motion(true)
	await get_tree().create_timer(1.2).timeout
	await _shot(out_dir, "03_mouvement_reduit")

	print("[SHOTS] %s" % out_dir)
	get_tree().quit(0)


# Ce que les captures ne disent pas : une nappe à taille nulle et une nappe transparente rendent
# EXACTEMENT la même image. On imprime donc les grandeurs qui les distinguent.
func _diagnose(amb: Control) -> void:
	print("[DIAG] couche : size=%s  viewport=%s" % [amb.size, get_viewport().get_visible_rect().size])
	for child in amb.get_children():
		if child is ColorRect:
			var mat := (child as ColorRect).material as ShaderMaterial
			var tex = mat.get_shader_parameter("noise_tex") if mat != null else null
			var img_ok := false
			if tex != null and tex is Texture2D:
				var img: Image = (tex as Texture2D).get_image()
				img_ok = img != null and img.get_width() > 0
			print("[DIAG]   %s pos=%s size=%s  bruit_pret=%s"
				% [child.name, child.position, child.size, img_ok])
		elif child is GPUParticles2D:
			var p := child as GPUParticles2D
			var pm := p.process_material as ParticleProcessMaterial
			print("[DIAG]   %s pos=%s emitting=%s boite=%s"
				% [p.name, p.position, p.emitting, pm.emission_box_extents])


func _shot(dir_path: String, name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir_path, name_])
	print("[SHOT] %s/%s.png  (%dx%d)" % [dir_path, name_, img.get_width(), img.get_height()])
