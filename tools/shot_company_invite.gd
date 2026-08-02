extends Node
# CAPTURE DE RECETTE — toast d'invitation de compagnie sur un écran hub. SANS `--headless`.
func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	var dir := args[i + 1] if (i >= 0 and i + 1 < args.size()) \
		else ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	for f in range(8):
		await get_tree().process_frame
	# On injecte la charge utile que servirait `GET /company/badge`.
	var nav: Node = null
	var stack: Array = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_method("_show_company_invite"):
			nav = n
			break
		for c in n.get_children():
			stack.append(c)
	if nav == null:
		print("[SHOT] top_nav introuvable"); get_tree().quit(1); return
	nav._on_company_badge({"company": true, "online": 2, "unread": 1,
		"invite": {"squad_code": "ZULU", "playlist": "duo_2v2", "from_name": "Vulture"}})
	for f in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/20_toast_invitation.png" % dir)
	print("[SHOT] 20_toast_invitation.png")
	get_tree().quit(0)
