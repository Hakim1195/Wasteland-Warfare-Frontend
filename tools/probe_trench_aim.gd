extends Node

# =================================================================================================
# SONDE §8.141.7 — « JE VISE LE SOLDAT, LA BALLE PART VERS LUI, AUCUN DÉGÂT » (surtout sur les côtés)
#
# ╔═ CE QU'ELLE COMPARE ══════════════════════════════════════════════════════════════════════════╗
# ║ Pour chaque position adverse, on balaie la visée et on confronte DEUX vérités qui devraient    ║
# ║ coïncider :                                                                                     ║
# ║   • CE QUE LE JOUEUR VOIT  — le réticule est-il sur la silhouette RENDUE à l'écran ?            ║
# ║   • CE QUE LE SERVEUR FAIT — la visée tombe-t-elle dans la fenêtre de la TABLE ANGULAIRE ?      ║
# ║ Tout écart entre les deux est un mensonge de l'image, et c'est exactement ce qu'un joueur       ║
# ║ ressent comme « j'ai visé, ça n'a rien fait ».                                                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT FENÊTRÉ : & <godot_console> --path frontend res://tools/probe_trench_aim.tscn

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

var _duel: Control = null
var _fails: Array = []


func _ok(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _ready() -> void:
	DuelScript.pending_room_id = "999"
	_duel = DuelScene.instantiate()
	add_child(_duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(_duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(_duel._on_connection_lost)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_duel.set_process(false)
	_duel._hud.visible = false
	_duel._world.set_reduced_motion(true)
	var table = JSON.parse_string(
		FileAccess.open("res://resources/trench/trench_angles.json",
			FileAccess.READ).get_as_text())

	print("=== CE QUE JE VOIS CONTRE CE QUE LE SERVEUR RÉSOUT ===")
	print("  (largeur ANGULAIRE : la silhouette RENDUE contre la fenêtre de la TABLE)")
	print()
	print("  %-22s %14s %14s %10s" % ["depuis ma pose 2, cible", "rendu (deg)", "table (deg)",
		"ecart"])

	for target in range(Geo.POSITIONS):
		_duel._pred_pos = 2
		_duel._world.set_pose(2, "up", true)
		var window := _window_of(table, 2, target)
		if window.is_empty():
			continue
		var centre_yaw: float = (float(window["yaw_min"]) + float(window["yaw_max"])) * 0.5
		var centre_pitch: float = (float(window["pitch_min"]) + float(window["pitch_max"])) * 0.5
		_duel._aim_yaw = centre_yaw
		_duel._aim_pitch = centre_pitch
		_duel._world.set_aim(centre_yaw, centre_pitch)
		_push(target)
		for _i in 20:
			_duel._refresh_view(0.016)
			_duel._world._process(0.016)
		await get_tree().create_timer(0.25).timeout
		for _i in 6:
			_duel._refresh_view(0.016)
			_duel._world._process(0.016)
		await get_tree().process_frame

		# --- CE QUE JE VOIS : la largeur ANGULAIRE de la silhouette rendue ------------------------
		# ⚠️ LE COSINUS EST OBLIGATOIRE DEPUIS QU'ON A RETIRÉ LE BILLBOARD. Le sprite est fixe dans
		# le plan de la table (Z constant) : vu de biais, sa largeur apparente se réduit en cos(θ) —
		# exactement comme la fenêtre de tir. Le mesurer sans le cosinus, c'est mesurer un billboard
		# qui n'existe plus, et surestimer l'écart aux positions extrêmes.
		var sprite: Sprite3D = _duel._world.enemy_sprite_node()
		var camera: Camera3D = null
		for child in _duel._world.get_node("SubViewport/Arena").get_children():
			if child is Camera3D:
				camera = child
		var anchor: Vector3 = _duel._world.enemy_root_node().global_position
		var distance: float = camera.global_position.distance_to(anchor)
		var to_anchor: Vector3 = anchor - camera.global_position
		var view_yaw: float = atan2(to_anchor.x, to_anchor.z)
		var half_world: float = float(sprite.texture.get_width()) * sprite.pixel_size * 0.5 			* absf(cos(view_yaw))
		var rendered_deg: float = 2.0 * rad_to_deg(atan(half_world / maxf(0.01, distance)))
		var table_deg: float = float(window["yaw_max"]) - float(window["yaw_min"])
		var ratio: float = rendered_deg / maxf(0.001, table_deg)
		print("  %-22s %13.2f %14.2f %9.2fx" % ["position %d" % target, rendered_deg, table_deg,
			ratio])

	print()
	print("  ⚠️ Un rapport > 1 = la silhouette PARAÎT plus large que sa fenêtre de tir : on peut")
	print("     viser le soldat qu'on VOIT et rater celui que le SERVEUR connaît.")
	print()

	# --- LE CŒUR : LA VISÉE QUE LE JOUEUR PRODUIT EN METTANT LE RÉTICULE SUR LE SOLDAT ------------
	print("=== LE RÉTICULE SUR LE SOLDAT PRODUIT-IL UNE VISÉE QUI TOUCHE ? ===")
	for target in range(Geo.POSITIONS):
		var window := _window_of(table, 2, target)
		if window.is_empty():
			continue
		# Le joueur met son réticule sur le CENTRE VISIBLE du soldat : la direction œil → centre de
		# la silhouette RENDUE. C'est ce que fait sa main, littéralement.
		_duel._pred_pos = 2
		_duel._world.set_pose(2, "up", true)
		_duel._world.set_aim(0.0, 0.0)
		_duel._world._process(0.016)
		_push(target)
		for _i in 20:
			_duel._refresh_view(0.016)
			_duel._world._process(0.016)
		# ╔═ ⚠️⚠️ ATTENDRE LE TAMPON DE RENDU, PAS SEULEMENT UNE FRAME ═════════════════════════════╗
		# ║ Premier essai : la sonde poussait un état puis mesurait tout de suite. `_render_pair()`  ║
		# ║ rend la paire d'états à `maintenant − RENDER_DELAY` — donc l'état PRÉCÉDENT. La sonde    ║
		# ║ mesurait un soldat vieux d'une itération et rapportait des visées décalées d'une         ║
		# ║ position, ce qui ressemblait à s'y méprendre à une INVERSION D'AXE dans le jeu.          ║
		# ║ C'était un faux rouge spectaculaire — exactement le genre de mesure qu'il ne faut pas    ║
		# ║ rapporter avant de l'avoir comprise. On laisse donc passer le tampon en TEMPS RÉEL.      ║
		# ╚═════════════════════════════════════════════════════════════════════════════════════════╝
		await get_tree().create_timer(0.25).timeout
		for _i in 6:
			_duel._refresh_view(0.016)
			_duel._world._process(0.016)
		await get_tree().process_frame
		var camera2: Camera3D = null
		for child in _duel._world.get_node("SubViewport/Arena").get_children():
			if child is Camera3D:
				camera2 = child
		# Centre de la partie EXPOSÉE de la silhouette (ce que l'œil vise), en monde.
		var anchor2: Vector3 = _duel._world.enemy_root_node().global_position
		var exposed_mid := Vector3(anchor2.x,
			(_occlusion_floor(camera2.global_position) + Geo.SILHOUETTE_TOP) * 0.5, anchor2.z)
		var to_target: Vector3 = exposed_mid - camera2.global_position
		var aim_yaw: float = rad_to_deg(atan2(to_target.x, to_target.z))
		var aim_pitch: float = rad_to_deg(atan2(to_target.y,
			sqrt(to_target.x * to_target.x + to_target.z * to_target.z)))
		var hits: bool = aim_yaw >= float(window["yaw_min"]) and aim_yaw <= float(window["yaw_max"]) \
			and aim_pitch >= float(window["pitch_min"]) and aim_pitch <= float(window["pitch_max"])
		_ok("position %d : viser le CENTRE VISIBLE touche" % target, hits,
			"vise (%.2f / %.2f) · fenetre yaw [%.2f, %.2f] pitch [%.2f, %.2f]"
			% [aim_yaw, aim_pitch, window["yaw_min"], window["yaw_max"],
				window["pitch_min"], window["pitch_max"]])

	print("\n%s" % ("TOUT VERT" if _fails.is_empty() else "ECHEC : " + str(_fails.size())
		+ " position(s) invisable(s)"))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _occlusion_floor(eye: Vector3) -> float:
	return maxf(Geo.SILHOUETTE_BOTTOM, Geo.occlusion_floor_at_target(eye))


func _window_of(table, shooter: int, target: int) -> Dictionary:
	for entry in table.get("windows", []):
		if int(entry["shooter_pos"]) == shooter and int(entry["target_pos"]) == target:
			return entry
	return {}


func _push(enemy_pos: int) -> void:
	_duel._on_state({"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 900, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": 8, "bandages": 1, "aiming": false, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": enemy_pos, "stance": "up", "hp": 100, "weapon": "vipere",
				"hits_total": 0, "grenades": 2, "ammo": 8, "bandages": 1, "aiming": true,
				"hidden": false, "choice_deadline_tick": 0, "laser_fire_tick": 0,
				"reload_until_tick": 0, "bandage_until_tick": 0, "disconnected": false}],
		"projectiles": [], "events": []})
