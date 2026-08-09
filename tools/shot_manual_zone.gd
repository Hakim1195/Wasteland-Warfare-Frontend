extends Node

# CAPTURE DE RECETTE — MANUEL DE GUERRE, section ZONE, dans les TROIS langues (ZONE LÉTALE §8.145).
# Le Manuel est la référence consultable à froid : s'il énonce l'ANCIENNE règle, il ment à chaque
# joueur qui l'ouvre. On le regarde RENDU, pas dans le CSV (leçon §8.144 : le gabarit relu ≠ le
# gabarit rendu).
# ⚠️ SANS `--headless` : le rasteriseur factice rend des images vides.
#   & <godot_console> --path frontend res://tools/shot_manual_zone.tscn -- --shots <dir>

const WarManual := preload("res://scripts/ui/war_manual.gd")

func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	var dir: String = args[i + 1] if (i >= 0 and i + 1 < args.size()) \
		else ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)

	for loc in ["fr", "en", "it"]:
		TranslationServer.set_locale(loc)
		var manual := WarManual.new()
		add_child(manual)
		manual.focus_section("zone")
		await get_tree().process_frame
		await _shot(dir, "30_manuel_zone_%s" % loc)
		manual.queue_free()
		await get_tree().process_frame

	print("[SHOTS] termine -> %s" % dir)
	get_tree().quit(0)

func _shot(dir: String, name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[SHOT] %s.png" % name)
