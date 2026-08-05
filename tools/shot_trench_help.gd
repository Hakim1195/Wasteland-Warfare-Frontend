extends Node

# =================================================================================================
# RECETTE VISUELLE §8.141.3 — LE GUIDE DES COMMANDES (F1).
#
# ⚠️ Un panneau bâti par code ne se recette PAS au boot « 0 ERROR » : ce dépôt a déjà payé sept fois
# « un `Control` créé par code garde `size = (0,0)` », dont une où le panneau F10 atterrissait à
# x = −400, intégralement hors de l'écran, avec `visible = true` et 45 contrôles verts.
# On MESURE donc qu'il est dans l'écran, puis on le PHOTOGRAPHIE.
#
# ⚠️ LANCEMENT FENÊTRÉ :
#   & <godot_console> --path frontend res://tools/shot_trench_help.tscn

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")

var _fails: Array = []


func _ok(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _ready() -> void:
	var out := OS.get_user_data_dir() + "/trench_help_shot"
	DirAccess.make_dir_recursive_absolute(out)

	DuelScript.pending_room_id = "999"
	var duel = DuelScene.instantiate()
	add_child(duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(duel._on_connection_lost)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	duel.set_process(false)

	print("=== GUIDE DES COMMANDES (F1) ===")
	var panel: PanelContainer = duel._help_panel
	_ok("le panneau existe", panel != null)
	_ok("il demarre FERME (il ne doit pas masquer le duel avant l'intermission)", not panel.visible)

	# --- Il s'ouvre TOUT SEUL au premier bandeau d'avant-manche -------------------------------
	duel._on_state({"type": "trench_state", "tick": 5, "phase": "intermission", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 900, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": 8, "bandages": 1, "aiming": false, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": 2, "stance": "up", "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": 8, "bandages": 1, "aiming": false, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false}],
		"projectiles": [], "events": []})
	duel._refresh_view(0.016)
	await get_tree().process_frame
	_ok("il s'OUVRE tout seul pendant le bandeau d'avant-manche", panel.visible)

	# --- Il tient DANS l'écran (le piège des sept récidives) -----------------------------------
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var rect := Rect2(panel.global_position, panel.size)
	_ok("il a une taille REELLE (pas 0x0)", rect.size.x > 100.0 and rect.size.y > 100.0,
		"size = %s" % str(rect.size))
	_ok("il est ENTIEREMENT dans l'ecran",
		rect.position.x >= 0.0 and rect.position.y >= 0.0
		and rect.position.x + rect.size.x <= screen.x
		and rect.position.y + rect.size.y <= screen.y,
		"panneau %s a %s, ecran %s" % [str(rect.size), str(rect.position), str(screen)])
	_ok("il ne mange pas la souris (la visee doit continuer de tourner)",
		panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# --- Les 22 libellés sont TRADUITS (une clé non traduite s'affiche telle quelle) ------------
	var missing: Array = []
	for key in ["TRENCH_HELP_TITLE", "TRENCH_HELP_CLOSE", "TRENCH_HELP_HOTKEY",
			"TRENCH_HELP_MOVE", "TRENCH_HELP_MOVE_D", "TRENCH_HELP_STANCE", "TRENCH_HELP_STANCE_D",
			"TRENCH_HELP_AIM", "TRENCH_HELP_AIM_D", "TRENCH_HELP_FIRE", "TRENCH_HELP_FIRE_D",
			"TRENCH_HELP_GRENADE", "TRENCH_HELP_GRENADE_D", "TRENCH_HELP_RELOAD",
			"TRENCH_HELP_RELOAD_D", "TRENCH_HELP_BANDAGE", "TRENCH_HELP_BANDAGE_D",
			"TRENCH_HELP_CHOICE", "TRENCH_HELP_CHOICE_D", "TRENCH_HELP_ESCAPE",
			"TRENCH_HELP_ESCAPE_D", "TRENCH_HELP_TIP"]:
		if duel.tr(key) == key:
			missing.append(key)
	_ok("les 22 libelles sont TRADUITS (une cle non traduite s'affiche en clair)",
		missing.is_empty(), "manquantes : %s" % ", ".join(missing))

	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/guide_commandes.png" % out)
	print("[SHOT] %s/guide_commandes.png" % out)

	# --- Il se REFERME au coup d'envoi, sans que le joueur ait à s'en occuper -------------------
	duel._on_duel_event({"type": "round_start", "round_no": 1})
	_ok("il se REFERME tout seul au coup d'envoi", not panel.visible)

	print("\n%s" % ("TOUT VERT" if _fails.is_empty() else "ECHEC : " + ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)
