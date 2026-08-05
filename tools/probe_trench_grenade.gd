extends Node

# =================================================================================================
# SONDE §8.141 — L'INVARIANT D'HONNÊTETÉ DU RAYON (§C.1), MESURÉ EN PIXELS SUR UNE CAPTURE.
#
# ╔═ POURQUOI UNE MESURE EN PIXELS, ALORS QUE LE HARNAIS VÉRIFIE DÉJÀ LES ÉCHELLES ═══════════════╗
# ║ `test_trench_ambient.tscn` vérifie que `scale` vaut bien le rayon du registre serveur. C'est    ║
# ║ nécessaire et ce n'est PAS suffisant : une échelle juste sur un maillage dont le rayon          ║
# ║ extérieur ne vaudrait pas 1,0, un `pixel_size`, une caméra mal cadrée, un tore posé sur le      ║
# ║ mauvais axe — chacun rendrait un cercle FAUX avec un `scale` VRAI. Le §C.1 demande donc         ║
# ║ explicitement une capture et une mesure en pixels, et il a raison : c'est exactement le genre   ║
# ║ de défaut que ce dépôt n'attrape QUE par la capture (le rectangle blanc, le panneau F10 hors    ║
# ║ écran, la brume qui efface le ciel — trois fois la même leçon).                                 ║
# ║                                                                                                 ║
# ║ LA CONTRE-ÉPREUVE : on projette les deux bords théoriques du cercle (±R sur l'axe du front, au  ║
# ║ plan des soldats adverses) avec la caméra RÉELLE, et on compare à la largeur MESURÉE par        ║
# ║ différence d'images (décalque allumé / éteint). Tolérance 5 %, celle du bon de commande.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT FENÊTRÉ OBLIGATOIRE :
#   & <godot_console> --path frontend res://tools/probe_trench_grenade.tscn

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

# Le rayon SERVEUR du jour ⚙ — poussé par le vrai chemin (`set_grenade_radius`), comme `trench_init`.
const SERVER_RADIUS := 2.5
const TOLERANCE := 0.05

var _duel: Control = null
var _out := ""
var _fails: Array = []


func _ready() -> void:
	_out = OS.get_user_data_dir() + "/trench_grenade_probe"
	DirAccess.make_dir_recursive_absolute(_out)

	DuelScript.pending_room_id = "999"
	_duel = DuelScene.instantiate()
	add_child(_duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(_duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(_duel._on_connection_lost)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_duel.set_process(false)
	_duel._hud.visible = false
	_duel._ambient.set_reduced_motion(true)
	_duel._world.set_reduced_motion(true)
	_duel._world.set_pose(2, "up", true)
	_duel._world.set_grenade_radius(SERVER_RADIUS)
	await get_tree().process_frame

	print("=== SONDE §C.1 — LE CERCLE DIT-IL LA VÉRITÉ ? ===")
	print("rayon serveur : %.2f m" % SERVER_RADIUS)
	await _measure_decal(0.0, "decalque_centre")
	await _measure_decal(Geo.position_x(4), "decalque_bord")
	await _shoot_explosion()

	print("\n%s" % ("TOUT VERT" if _fails.is_empty() else "ECHEC : " + ", ".join(_fails)))
	print("[SONDE] %s" % _out)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


# LA MESURE : largeur RENDUE du cercle, en pixels, contre sa largeur PROJETÉE théorique.
func _measure_decal(at_x: float, tag: String) -> void:
	var world = _duel._world
	world.show_grenade_aim(true, at_x, Geo.far_soldier_z(), true)
	await get_tree().process_frame
	await get_tree().process_frame
	var with_decal := get_viewport().get_texture().get_image()
	world.show_grenade_aim(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var without := get_viewport().get_texture().get_image()
	with_decal.save_png("%s/%s.png" % [_out, tag])

	var box := _diff_box(with_decal, without)
	if int(box["count"]) == 0:
		_ok("%s : le cercle est RENDU" % tag, false, "aucun pixel ne change")
		return
	var measured: float = float(int(box["x_max"]) - int(box["x_min"]) + 1)

	# LA THÉORIE : les deux bords du cercle, projetés par la caméra RÉELLE (elle porte le FOV,
	# l'aspect et le suivi de visée — les recopier ici recréerait la divergence qu'on traque).
	var camera: Camera3D = world.get_node("SubViewport/Arena").get_node_or_null("Camera3D")
	if camera == null:
		for child in world.get_node("SubViewport/Arena").get_children():
			if child is Camera3D:
				camera = child
				break
	var z: float = Geo.far_soldier_z()
	var left := camera.unproject_position(Vector3(at_x - SERVER_RADIUS, 0.04, z))
	var right := camera.unproject_position(Vector3(at_x + SERVER_RADIUS, 0.04, z))
	var expected: float = absf(right.x - left.x)
	var error: float = absf(measured - expected) / maxf(1.0, expected)
	_ok("%s : le cercle RENDU mesure le rayon d'action, a %.0f %% pres" % [tag, TOLERANCE * 100.0],
		error <= TOLERANCE,
		"mesure %.0f px, theorie %.0f px, ecart %.1f %%" % [measured, expected, error * 100.0])


# L'EXPLOSION : même mesure, sur l'anneau de choc à l'instant où il a fini sa course.
func _shoot_explosion() -> void:
	var world = _duel._world
	var boom = world._explosions[0]
	boom.set_reduced_motion(false)
	boom.play(Vector3(0.0, 0.04, Geo.far_soldier_z()), SERVER_RADIUS)
	# ⚠️ On avance la séquence À LA MAIN, jusqu'à la fin de la CROISSANCE (70 % de la durée de
	# l'anneau) et pas au-delà : c'est l'instant où le cercle porte l'information, et attendre
	# l'extinction photographierait un anneau transparent.
	boom._process(0.35 * 0.7)
	await get_tree().process_frame
	await get_tree().process_frame
	var ring: MeshInstance3D = boom.get_node("ShockRing")
	print("    [diag] explosion visible=%s · anneau visible=%s · echelle=%s · position=%s · t=%.3f"
		% [boom.visible, ring.visible, ring.scale, ring.global_position, boom.elapsed()])
	var ring_mat: StandardMaterial3D = ring.material_override
	print("    [diag] alpha=%.2f · no_depth_test=%s · priorite=%d"
		% [ring_mat.albedo_color.a, ring_mat.no_depth_test, ring_mat.render_priority])
	var with_ring := get_viewport().get_texture().get_image()
	with_ring.save_png("%s/anneau_de_choc.png" % _out)
	boom.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var without := get_viewport().get_texture().get_image()
	boom.visible = true

	var box := _diff_box(with_ring, without)
	if int(box["count"]) == 0:
		_ok("anneau de choc : rendu", false, "aucun pixel ne change")
		return
	var measured: float = float(int(box["x_max"]) - int(box["x_min"]) + 1)
	var camera: Camera3D = null
	for child in world.get_node("SubViewport/Arena").get_children():
		if child is Camera3D:
			camera = child
			break
	var z: float = Geo.far_soldier_z()
	var left := camera.unproject_position(Vector3(-SERVER_RADIUS, 0.04, z))
	var right := camera.unproject_position(Vector3(SERVER_RADIUS, 0.04, z))
	var expected: float = absf(right.x - left.x)
	var error: float = absf(measured - expected) / maxf(1.0, expected)
	# ⚠️ L'anneau EXPLOSE aussi de la fumée et du feu : la boîte de différence les inclut. On borne
	# donc par le HAUT seulement — le cercle ne doit pas être PLUS PETIT que le rayon (un cercle
	# trop petit ment dans le sens dangereux : il promet un abri qui n'existe pas).
	_ok("anneau de choc : jamais PLUS PETIT que le rayon d'action",
		measured >= expected * (1.0 - TOLERANCE),
		"mesure %.0f px, theorie %.0f px, ecart %+.1f %%" % [measured, expected,
			(measured - expected) / maxf(1.0, expected) * 100.0])


func _diff_box(a: Image, b: Image) -> Dictionary:
	var w: int = mini(a.get_width(), b.get_width())
	var h: int = mini(a.get_height(), b.get_height())
	var x_min := w
	var x_max := -1
	var y_min := h
	var y_max := -1
	var count := 0
	for y in range(h):
		for x in range(w):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) < 0.03:
				continue
			x_min = mini(x_min, x); x_max = maxi(x_max, x)
			y_min = mini(y_min, y); y_max = maxi(y_max, y)
			count += 1
	return {"x_min": x_min, "x_max": x_max, "y_min": y_min, "y_max": y_max, "count": count}
