extends Node

# =================================================================================================
# OUTIL §8.139 (recette VISUELLE du LOT C) — les sprites peints, à l'écran, dans le vrai duel.
#
# ⚠️ LANCEMENT FENÊTRÉ obligatoire (le viewport doit rendre — recette §8.100/§8.111) :
#   & <godot_console> --path frontend res://tools/shot_trench_sprites.tscn
#
# Couvre les quatre points de recette que le bon de commande exige pour ce lot, et qu'aucun boot
# headless ne prouve : ÉCHELLE du soldat aux deux distances extrêmes · TEINTE de faction ·
# BASCULE des frames (les 6 états du soldat, les 3 états de chaque arme) · absence de HALO.
#
# ╔═ POURQUOI UN OUTIL DE PLUS PLUTÔT QUE `preview_trench.tscn` ══════════════════════════════════╗
# ║ `preview_trench` met en scène un ÉTAT de duel, et un état ne contient qu'une arme et qu'une    ║
# ║ pose à la fois : il a montré la VIPÈRE alors que le HUD annonçait FRELON, simplement parce     ║
# ║ qu'aucun événement d'escalade n'y est joué. Recetter 4 armes × 3 états + 6 états de soldat     ║
# ║ demande de FORCER chaque combinaison, pas d'attendre qu'un état la produise.                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const Sprites := preload("res://scripts/game/trench_sprites.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")

const WEAPONS := ["vipere", "frelon", "chacal", "condor"]
const ENEMY_STATES := ["idle", "aim", "throw", "hit", "death_a", "death_b"]

var _duel: Control = null
var _out := ""
# Vrai pendant qu'on photographie l'état `fire` : voir le commentaire de la boucle des armes.
var _rearm_fire := false


func _ready() -> void:
	_out = OS.get_user_data_dir() + "/trench_sprite_shots"
	DirAccess.make_dir_recursive_absolute(_out)

	print("=== INVENTAIRE DES FICHIERS (le contrat de nommage) ===")
	var missing := 0
	for state in ENEMY_STATES:
		var ok := Sprites.texture_at(Sprites.enemy_path(state)) != null
		if not ok:
			missing += 1
		print("  enemy_%-8s %s" % [state, "OK" if ok else "ABSENT"])
	for w in WEAPONS:
		for s in Sprites.VIEWMODEL_STATES:
			var ok2 := Sprites.texture_at(Sprites.viewmodel_path(w, s)) != null
			if not ok2:
				missing += 1
			print("  vm_%s_%-7s %s" % [w, s, "OK" if ok2 else "ABSENT"])
	print("  -> %d fichier(s) manquant(s) sur 18" % missing)

	DuelScript.pending_room_id = "999"
	_duel = DuelScene.instantiate()
	add_child(_duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(_duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(_duel._on_connection_lost)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_duel.set_process(false)              # aucune entrée ne doit déplacer la mise en scène
	_duel._hud.visible = false             # le HUD masquerait les coins qu'on vient recetter

	# --- 1) LES 4 ARMES, LEURS 3 ÉTATS ---------------------------------------------------------
	# ⚠️ On passe par les VRAIES entrées (`notify_fire`, `set_reloading`) et non par une écriture
	# directe de la texture : ce qu'on recette, c'est la BASCULE, pas le fichier. Et on relit
	# `current_state()` au moment du déclenchement — une capture qui prétend montrer `fire` alors
	# que la frame est déjà retombée sur `idle` serait un faux vert de plus.
	for weapon in WEAPONS:
		var painted: bool = _duel._apply_weapon_check(weapon)
		print("  [%s] mode peint : %s" % [weapon, painted])
		for state in Sprites.VIEWMODEL_STATES:
			_duel._viewmodel.set_reloading(state == "reload")
			# ⚠️⚠️ LA FENÊTRE `fire` DURE 90 ms, ET UNE CAPTURE EN COÛTE PLUS. Premier essai : on
			# appelait `notify_fire()` une fois, on vérifiait `current_state() == "fire"` (vert), puis
			# on attendait deux frames avant de saisir l'image — et la fenêtre s'était refermée entre
			# les deux. Les quatre captures « fire » montraient en réalité la frame `idle` : 0 pixel
			# de départ de feu, mesuré. Le contrôle passait AU VERT en photographiant autre chose que
			# ce qu'il annonçait. On RÉARME donc à chaque frame, jusqu'à l'obturateur inclus.
			_rearm_fire = state == "fire"
			for _i in 3:
				if _rearm_fire:
					_duel._viewmodel.notify_fire()
				await get_tree().process_frame
			var seen: String = _duel._viewmodel.current_state()
			if seen != state:
				print("  ⚠️  %s %s : l'etat affiche est '%s'" % [weapon, state, seen])
			await _shot("vm_%s_%s" % [weapon, state])
			_rearm_fire = false
		_duel._viewmodel.set_reloading(false)

	# --- 2) LE SOLDAT : 6 ÉTATS, ET L'ÉCHELLE AUX DEUX DISTANCES EXTRÊMES ------------------------
	# ⚠️ « Les deux distances extrêmes » ne sont pas décoratives : `pixel_size` est CONSTANT, donc
	# c'est la perspective 3D seule qui doit faire varier la taille du soldat. Si les deux captures
	# rendaient la même hauteur, le billboard ne serait pas dans la scène 3D.
	# ⚠️ MESURER LE SOLDAT PAR SA COULEUR NE MARCHE PAS : le décor peint porte des ruines de brique
	# ROUGES, aussi saturées que la teinte de faction — une détection par saturation attrape le
	# décor et rend une « silhouette » de 1500 px de large. On capture donc DEUX fois la même image,
	# sprite visible puis sprite masqué : la différence ne peut être que le soldat.
	# ⚠️⚠️ FIGER L'HABILLAGE AVANT DE MESURER. Premier essai : la différence entre les deux captures
	# faisait 611 px de haut sur 1686 de large — c'est-à-dire tout l'écran. La cause n'était pas le
	# soldat : c'était la couche d'ambiance du LOT D, dont la brume défile et dont les cendres
	# tombent en continu. Deux captures prises à 0,1 s d'intervalle diffèrent alors PARTOUT, et la
	# mesure ne mesure plus rien. `reduced_motion` fige tout ça sans rien éteindre — la scène reste
	# celle du jeu, elle cesse simplement de bouger.
	_duel._ambient.set_reduced_motion(true)
	for pair in [[0, 4], [2, 2], [4, 0]]:
		_duel._pred_pos = int(pair[0])
		_duel._world.set_pose(int(pair[0]), "up", true)
		_duel._refresh_pose_view()
		# ╔═ ⚠️ IL FAUT REGARDER LA CIBLE POUR LA PHOTOGRAPHIER (§8.141) ═════════════════════════╗
		# ║ Avec l'arène à 9 m et le front à 13,6 m, la position adverse OPPOSÉE est à ±53,7° de   ║
		# ║ lacet, pour un demi-champ horizontal de ~43° en 16:9. Elle est donc HORS DE L'ÉCRAN     ║
		# ║ tant que le joueur ne tourne pas la tête — et c'est le jeu voulu (« viser d'un bout à   ║
		# ║ l'autre demande un vrai geste »). Ce harnais visait droit devant : ses deux captures     ║
		# ║ extrêmes ne montraient donc PAS de soldat, et un lecteur pressé y aurait lu un défaut    ║
		# ║ de rendu. On oriente la visée sur le CENTRE de la fenêtre de tir — c'est-à-dire là où le ║
		# ║ joueur la mettrait lui-même.                                                            ║
		# ╚═══════════════════════════════════════════════════════════════════════════════════════╝
		var eye: Vector3 = Geo.eye_position(int(pair[0]), "up")
		var window: Dictionary = Geo.aim_window(eye, int(pair[1]), "up")
		if not window.is_empty():
			_duel._aim_yaw = (float(window["yaw_min"]) + float(window["yaw_max"])) * 0.5
			_duel._aim_pitch = (float(window["pitch_min"]) + float(window["pitch_max"])) * 0.5
			_duel._world.set_aim(_duel._aim_yaw, _duel._aim_pitch)
		_push(int(pair[1]), "idle")
		await get_tree().create_timer(0.35).timeout     # > 0,2 s : le fondu d'apparition est fini
		var tag := "soldat_moi%d_lui%d" % [int(pair[0]), int(pair[1])]
		await _shot(tag)
		var node: Sprite3D = _duel._world.enemy_sprite_node()
		node.visible = false
		await get_tree().create_timer(0.1).timeout
		await _shot(tag + "_SANS")
		node.visible = true
		await get_tree().create_timer(0.1).timeout

	_duel._pred_pos = 2
	_duel._world.set_pose(2, "up", true)
	_duel._refresh_pose_view()
	for state in ENEMY_STATES:
		_push(3, state)
		await get_tree().create_timer(0.15).timeout
		await _shot("soldat_%s" % state)

	print("[SHOTS] %s" % _out)
	get_tree().quit(0)


# Pousse un état de duel MINIMAL qui place l'adversaire en `pos` dans l'état voulu. Les états
# transitoires (`throw`, `hit`) et la mort passent par les entrées prévues pour eux — c'est le
# chemin réel du jeu, pas une écriture directe dans le nœud.
func _push(enemy_pos: int, state: String) -> void:
	var enemy_hp := 0 if state.begins_with("death") else 52
	_duel._on_state({
		"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 900, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": "up", "hp": 100, "weapon": "frelon", "hits_total": 0,
				"grenades": 2, "ammo": 24, "bandages": 1, "aiming": false, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": enemy_pos, "stance": "up", "hp": enemy_hp, "weapon": "condor",
				"hits_total": 0, "grenades": 1, "ammo": 4, "bandages": 0,
				"aiming": state == "aim", "hidden": false, "choice_deadline_tick": 0,
				"laser_fire_tick": 0, "reload_until_tick": 0, "bandage_until_tick": 0,
				"disconnected": false},
		],
		"projectiles": [], "events": [],
	})
	if state == "throw" or state == "hit":
		_duel._world.set_enemy_action(state)
	# ╔═ ⚠️⚠️ CE HARNAIS PHOTOGRAPHIAIT UN SOLDAT À ALPHA 0,12 — CORRIGÉ §8.141 ═══════════════════╗
	# ║ `_render_enemy` monte `_enemy_alpha` de 0,12 PAR APPEL (fondu d'apparition), et `_refresh_   ║
	# ║ view` n'est appelée que depuis `_process` — que ce harnais coupe volontairement pour figer   ║
	# ║ la mise en scène. Un seul appel laissait donc l'adversaire à 12 % d'opacité ET, par le même  ║
	# ║ calcul, ENFONCÉ de 0,48 m derrière son parapet (`sink = (1 − alpha) × 0,55`) : littéralement ║
	# ║ invisible sur toutes les captures de soldat. Le §8 du rapport de pivot a diagnostiqué un     ║
	# ║ « rectangle blanc » en partie sur ces images-là.                                             ║
	# ║ ⚠️ On ne triche PAS en forçant `_enemy_alpha` : on APPELLE la vraie fonction jusqu'au bout du ║
	# ║ fondu. Ce qui est photographié reste ce que le jeu dessine.                                  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	for _i in 20:
		_duel._refresh_view(0.016)


func _shot(name_: String) -> void:
	if _rearm_fire:
		_duel._viewmodel.notify_fire()
	await get_tree().process_frame
	if _rearm_fire:
		_duel._viewmodel.notify_fire()
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name_])
	print("[SHOT] %s" % name_)
