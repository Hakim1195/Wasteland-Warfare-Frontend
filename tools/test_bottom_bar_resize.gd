extends Node

# CONTRE-ÉPREUVE — BARRE BASSE : l'état replié survit aux REDIMENSIONNEMENTS.
#   & <godot_console> --headless --path frontend res://tools/test_bottom_bar_resize.tscn
#
# ⚠️ CE QUE LA MESURE A CORRIGÉ DANS LE DIAGNOSTIC. Le reste-à-faire §9 du chantier tutoriel
# décrivait « redimensionner barre repliée la fait réapparaître, bouton encore en ▲ ». Reproduit
# pas à pas, le déclencheur n'est PAS le redimensionnement en soi : hors glissement, les ancres
# (`anchor_top = anchor_bottom = 1`, `grow_vertical = BEGIN`) replacent la barre correctement toutes
# seules — vérifié à 1280×720, 1600×900 et 1024×768.
#
# Le vrai déclencheur est le REDIMENSIONNEMENT PENDANT LE GLISSEMENT : le Tween court vers un
# `target_y` calculé pour l'ANCIENNE hauteur d'écran et l'impose à l'arrivée, en écrasant le
# replacement fait par les ancres. Mesuré sans correctif : repli lancé en 1920×1080 puis passage à
# 1280×720 → la barre atterrit à **y = 1037 sur un écran de 720 px**, soit ELLE ET SON BOUTON
# entièrement sous le bord inférieur. Ce n'est donc pas cosmétique : c'est la panne irrécupérable
# du §3.1, par un autre chemin.
#
# Correctif : `_on_hud_resized` TUE le tween périmé et ré-applique l'état de vérité (le booléen).

func _collapsed_y(hud, w: Control, btn: Button) -> float:
	return hud._bottom_panel_y(w.size.y, w.get_node("GlassBody").size.y, true, hud.size.y, btn.size.y)


func _ready() -> void:
	AuthManager.user_id = 11
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	var hud = arena.hud
	var btn: Button = hud.get_node("%ToggleBottomPanelButton")
	var w: Control = btn.get_parent()
	var checks := 0

	assert(not hud._bottom_hidden and btn.text == "▼")
	checks += 1

	# --- 1. LE DÉFAUT : redimensionnement EN PLEIN GLISSEMENT ------------------------------------
	hud._toggle_bottom_panel()          # lance le repli
	await get_tree().process_frame
	hud.size = Vector2(1280, 720)       # l'écran rétrécit AVANT la fin du glissement
	for i in range(60):
		await get_tree().process_frame
	# Sans correctif : 1037 px sur un écran de 720 → barre ET bouton hors de l'écran.
	assert(hud._bottom_hidden and btn.text == "▲")
	assert(absf(w.position.y - _collapsed_y(hud, w, btn)) < 1.0)
	# La borne dure du §3.1 tient aussi : le bouton reste TOUJOURS dans l'écran.
	assert(w.position.y + btn.size.y <= hud.size.y + 0.5)
	checks += 3
	print("[OK] Resize EN PLEIN GLISSEMENT : barre repliee et bouton dans l'ecran (3 asserts)")

	# --- 2. TROIS REDIMENSIONNEMENTS, BARRE REPLIÉE, HORS GLISSEMENT ----------------------------
	for s in [Vector2(1600, 900), Vector2(1920, 1080), Vector2(1024, 768)]:
		hud.size = s
		for i in range(3):
			await get_tree().process_frame
		assert(hud._bottom_hidden)                                   # état de vérité intact
		assert(btn.text == "▲")                                      # glyphe cohérent
		assert(absf(w.position.y - _collapsed_y(hud, w, btn)) < 1.0) # position cohérente
		assert(w.position.y + btn.size.y <= hud.size.y + 0.5)        # bouton toujours atteignable
		checks += 4
	print("[OK] 3 redimensionnements barre repliee : etat, glyphe, position, bouton (12 asserts)")

	# --- 3. UN SEUL CLIC SUFFIT À ROUVRIR (le défaut en demandait deux) --------------------------
	var before: float = w.position.y
	hud._toggle_bottom_panel()
	if hud._bottom_tween and hud._bottom_tween.is_valid():
		hud._bottom_tween.kill()
	hud._apply_bottom_panel_state(false)
	assert(not hud._bottom_hidden and btn.text == "▼")
	assert(w.position.y < before)        # elle est bien REMONTÉE
	checks += 2
	print("[OK] Un seul clic rouvre la barre apres resize (2 asserts)")

	print("[OK] TEST BOTTOM BAR RESIZE : %d asserts verts" % checks)
	get_tree().quit(0)
