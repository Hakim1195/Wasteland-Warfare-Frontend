extends Control
##
## Bootloader minimal (post-launcher) — PIPELINE_ET_BOOTLOADER.md §9.
##
## Le LANCEUR dédié gère désormais TOUTE la mise à jour (build complet via installateur Inno).
## Ce bootloader ne fait PLUS de réseau de MAJ ni de montage .pck : il lit la version gravée du
## build (application/config/version), la pose dans GameState pour le gate WS strict, puis enchaîne
## sur le flux normal (title_splash -> auth -> menu).
##

@export_file("*.tscn") var next_scene_path: String = "res://scenes/ui/title_splash.tscn"


func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	# Stockée pour le réseau : NetworkManager l'envoie au WebSocket (validation stricte serveur).
	GameState.client_version = version
	print("[BOOT] client_version=", version)
	_go_to_next_scene()


func _go_to_next_scene() -> void:
	# Bref délai pour le fondu, puis flux normal (TransitionManager §R6 si présent).
	await get_tree().create_timer(0.2).timeout
	var tm := get_node_or_null("/root/TransitionManager")
	if tm and tm.has_method("change_scene"):
		tm.change_scene(next_scene_path)
	else:
		get_tree().change_scene_to_file(next_scene_path)
