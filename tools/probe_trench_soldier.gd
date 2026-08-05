extends Node

# =================================================================================================
# SONDE §8.141 — LE SOLDAT DANS LE VRAI DUEL : où EXACTEMENT le blanc apparaît-il ?
#
# ╔═ POURQUOI CETTE SECONDE SONDE ════════════════════════════════════════════════════════════════╗
# ║ `probe_trench_quad.tscn` a rendu son verdict : dans un SubViewport nu, aux réglages EXACTS du   ║
# ║ jeu, le `Sprite3D` échantillonne parfaitement sa texture (RGB 58/59/58 pour une source à        ║
# ║ 60/61/60). La piste « `Sprite3D` sous GL Compatibility » du §8 est donc INFIRMÉE, et remplacer  ║
# ║ le sprite par un quad n'aurait rien corrigé — on aurait changé de nœud et gardé le défaut.      ║
# ║                                                                                                 ║
# ║ Le blanc naît donc AILLEURS, entre ce banc nu et le duel complet. Trois couches les séparent,   ║
# ║ et cette sonde les départage en photographiant le MÊME instant à trois profondeurs :            ║
# ║   1. la texture du SubViewport 3D SEULE   (ni ambiance, ni étalonnage, ni HUD)                  ║
# ║   2. l'écran complet, ambiance et étalonnage ALLUMÉS                                            ║
# ║   3. l'écran complet, ambiance et étalonnage ÉTEINTS                                            ║
# ║ Chaque profondeur est prise DEUX fois — sprite visible, puis sprite masqué : la différence ne   ║
# ║ peut être que le soldat (la parade du §8.139 au décor rouge qui se faisait passer pour lui).    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT FENÊTRÉ OBLIGATOIRE :
#   & <godot_console> --path frontend res://tools/probe_trench_soldier.tscn

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

var _duel: Control = null
var _out := ""


func _ready() -> void:
	_out = OS.get_user_data_dir() + "/trench_soldier_probe"
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
	# ⚠️ FIGER L'HABILLAGE AVANT TOUTE MESURE PAR DIFFÉRENCE (leçon §8.139) : les cendres tombent et
	# la brume défile ; deux captures prises à 0,1 s d'intervalle diffèrent alors PARTOUT et la
	# « silhouette » mesurée fait tout l'écran.
	_duel._ambient.set_reduced_motion(true)
	_duel._world.set_reduced_motion(true)

	_stage()
	# ⚠️⚠️ LE FONDU D'APPARITION DOIT ÊTRE FINI. `_render_enemy` monte `_enemy_alpha` de 0,12 PAR
	# APPEL, et `_refresh_view` n'est appelée que depuis `_process` — que le harnais vient de couper.
	# Le harnais §8.139 poussait donc UN état et photographiait un soldat à alpha 0,12, ENFONCÉ de
	# 0,48 m derrière le parapet : littéralement invisible. C'est un faux négatif, pas un défaut de
	# rendu — et il a pollué la lecture du §8.
	for _i in 20:
		_duel._refresh_view(0.016)
	await get_tree().process_frame

	_dump_sprite_state()

	# --- Profondeur 1 : LE SUBVIEWPORT 3D SEUL ---------------------------------------------------
	await _pair("1_monde3d", true)
	# --- Profondeur 2 : L'ÉCRAN COMPLET, habillage ALLUMÉ -----------------------------------------
	await _pair("2_ecran_habille", false)
	# --- Profondeur 3 : L'ÉCRAN COMPLET, habillage ÉTEINT -----------------------------------------
	_duel._ambient.visible = false
	_duel._grade.visible = false
	await get_tree().process_frame
	await _pair("3_ecran_nu", false)

	print("\n[SONDE] %s" % _out)
	get_tree().quit(0)


# L'adversaire DEBOUT, en face de moi, à la position centrale : le cas le plus favorable qui soit.
func _stage() -> void:
	_duel._pred_pos = 2
	_duel._world.set_pose(2, "up", true)
	_duel._refresh_pose_view()
	_duel._on_state({
		"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 900, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 100, "weapon": "frelon", "hits_total": 0,
				"grenades": 2, "ammo": 24, "bandages": 1, "aiming": false, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": 2, "stance": "up", "hp": 88, "weapon": "condor", "hits_total": 0,
				"grenades": 1, "ammo": 4, "bandages": 0, "aiming": true, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false},
		],
		"projectiles": [], "events": [],
	})


# Ce que le NŒUD déclare de lui-même — la colonne de gauche du tableau du §8, refaite à neuf.
func _dump_sprite_state() -> void:
	var sprite: Sprite3D = _duel._world.enemy_sprite_node()
	var root: Node3D = _duel._world.enemy_root_node()
	print("=== ÉTAT DÉCLARÉ DU SOLDAT ===")
	print("  mode peint        : %s" % _duel._world.enemy_is_painted())
	print("  frame courante    : %s" % _duel._world.enemy_frame())
	print("  racine visible    : %s  position %s" % [root.visible, root.position])
	print("  sprite visible    : %s" % sprite.visible)
	print("  sprite modulate   : %s" % sprite.modulate)
	print("  sprite pixel_size : %.6f" % sprite.pixel_size)
	print("  sprite position   : %s" % sprite.position)
	if sprite.texture == null:
		print("  texture           : ⛔ AUCUNE")
	else:
		print("  texture           : %s  %d x %d" % [sprite.texture.get_class(),
			sprite.texture.get_width(), sprite.texture.get_height()])
	print("  taille rendue     : %.3f m de haut" % (float(sprite.texture.get_height())
		* sprite.pixel_size if sprite.texture != null else 0.0))


# Une paire de captures (sprite visible / sprite masqué) + la mesure de leur différence.
func _pair(tag: String, viewport_only: bool) -> void:
	var sprite: Sprite3D = _duel._world.enemy_sprite_node()
	sprite.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var with_soldier := _grab(viewport_only)
	sprite.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var without := _grab(viewport_only)
	sprite.visible = true
	with_soldier.save_png("%s/%s.png" % [_out, tag])
	without.save_png("%s/%s_SANS.png" % [_out, tag])
	_diff(tag, with_soldier, without)


func _grab(viewport_only: bool) -> Image:
	if viewport_only:
		# ⚠️ Le SubViewport 3D du monde, et RIEN d'autre : ni ambiance, ni étalonnage, ni HUD.
		var sub: SubViewport = _duel._world.get_node("SubViewport")
		return sub.get_texture().get_image()
	return get_viewport().get_texture().get_image()


# LA MESURE : boîte englobante des pixels qui ont changé, puis couleur MOYENNE du soldat dans la
# capture « avec ». On ne devine pas où il est — on le déduit de ce qui a bougé.
func _diff(tag: String, a: Image, b: Image) -> void:
	var w: int = mini(a.get_width(), b.get_width())
	var h: int = mini(a.get_height(), b.get_height())
	var x_min := w
	var x_max := -1
	var y_min := h
	var y_max := -1
	var total := Vector3.ZERO
	var count := 0
	var spread_samples: Array[float] = []
	for y in range(h):
		for x in range(w):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) < 0.02:
				continue
			x_min = mini(x_min, x)
			x_max = maxi(x_max, x)
			y_min = mini(y_min, y)
			y_max = maxi(y_max, y)
			total += Vector3(pa.r, pa.g, pa.b)
			spread_samples.append((pa.r + pa.g + pa.b) / 3.0)
			count += 1
	print("\n--- %s (%d x %d) ---" % [tag, w, h])
	if count == 0:
		print("  ⛔ AUCUN pixel ne change : le soldat n'est pas rendu du tout a cette profondeur.")
		return
	var mean := total / float(count)
	var mean_luma: float = (mean.x + mean.y + mean.z) / 3.0
	var variance := 0.0
	for s in spread_samples:
		variance += (s - mean_luma) * (s - mean_luma)
	var sigma: float = sqrt(variance / float(count))
	print("  boite      : x %d..%d (%d px)  ·  y %d..%d (%d px)"
		% [x_min, x_max, x_max - x_min + 1, y_min, y_max, y_max - y_min + 1])
	print("  pixels     : %d" % count)
	print("  RGB moyen  : %d / %d / %d" % [int(mean.x * 255.0), int(mean.y * 255.0),
		int(mean.z * 255.0)])
	print("  ecart-type de luminance : %.4f" % sigma)
	if sigma < 0.035 and mean_luma > 0.70:
		print("  -> ⛔ APLAT CLAIR : le defaut du §8 est PRESENT a cette profondeur.")
	elif sigma < 0.035:
		print("  -> ⚠️ APLAT (sombre) : uniforme, mais pas blanc.")
	else:
		print("  -> ✅ IMAGE PEINTE : la texture s'echantillonne a cette profondeur.")
