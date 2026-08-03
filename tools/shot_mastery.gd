extends Node

# CAPTURES DE RECETTE — MAÎTRISE DE FACTION (§8.135).
#   & <godot_console> --path frontend res://tools/shot_mastery.tscn
#
# ⚠️ SANS `--headless` — obligatoire. En headless le pilote de rendu est factice : les PNG sortent
# VIDES et la « recette par capture » ne prouve rien (leçon §8.134.2). Recette maison validée :
# viewport → `get_image()` → PNG (§8.111), la seule qui capture aussi les surcouches.
#
# Produit dans `user://` (à ouvrir depuis %APPDATA%\Godot\app_userdata\<projet>\) :
#   mastery_borders.png   — LES 6 TRANCHES côte à côte + le rang 0 (témoin : aucune bordure)
#   mastery_evo_r0.png    — fiche ÉVOLUTION, maîtrise VERROUILLÉE (héros sous le niveau 50)
#   mastery_evo_r7.png    — fiche ÉVOLUTION, rang 7 (ÉLITE, bronze, prochain titre annoncé)
#   mastery_evo_r52.png   — fiche ÉVOLUTION, rang 52 (IMMORTEL, irisé, plus de titre à venir)
#   mastery_picker.png    — sélecteur de titre (modal calqué Classement)
#   mastery_podium.png    — podium du Rapport Post-Op, titres + bordures
#
# Le draft n'a PAS de capture dédiée : sa bordure et sa ligne de titre sont les MÊMES nœuds que
# ceux de `mastery_borders.png` et du podium (helper unique) — cf. l'écart consigné dans
# `faction_selection._refresh_mastery_frame`, le draft n'affiche pas d'adversaire à décorer.

const MasteryBorder = preload("res://scripts/ui/mastery_border.gd")
const TIERS := ["", "steel", "bronze", "silver", "gold", "platinum", "prismatic"]
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1)


func _shoot(node: Control, size: Vector2i, path: String) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = GUNMETAL
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	vp.add_child(node)
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("user://" + path)
	print("  -> user://%s  (%dx%d)" % [path, img.get_width(), img.get_height()])
	vp.free()


func _ready() -> void:
	SettingsManager.set_comfort("reduced_motion", false)
	print("[CAPTURES MAITRISE §8.135]")

	# --- 1. LES 6 TRANCHES + le témoin « rang 0 » -----------------------------------------------
	# Le rang 0 est capturé EXPRÈS : c'est le témoin qui prouve que la planche ne dessine pas
	# « quelque chose » par accident sur toutes les clés.
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 18)
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	for tier in TIERS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var b: Control = MasteryBorder.make(tier, 110.0)
		cell.add_child(b)
		var lbl := Label.new()
		lbl.text = tier.to_upper() if tier != "" else "RANG 0"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.541176, 0.592157, 0.647059, 1))
		cell.add_child(lbl)
		strip.add_child(cell)
	await _shoot(strip, Vector2i(1000, 200), "mastery_borders.png")

	# --- 2. FICHE PERSONNAGE — onglet ÉVOLUTION, trois états -------------------------------------
	for shot in [
		{"file": "mastery_evo_r0.png", "hero": _hero(0, false)},
		{"file": "mastery_evo_r7.png",
		 "hero": _hero(7, true, "elite", "bronze", {"rank": 10, "title_key": "master"})},
		{"file": "mastery_evo_r52.png", "hero": _hero(52, true, "immortal", "prismatic", null)},
	]:
		var chars = load("res://scenes/ui/characters_screen.tscn").instantiate()
		add_child(chars)
		await get_tree().process_frame
		var page := VBoxContainer.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.add_theme_constant_override("separation", 10)
		remove_child(chars)          # on ne veut QUE le bloc, pas tout l'écran
		var holder := PanelContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = GUNMETAL
		sb.set_content_margin_all(28.0)
		holder.add_theme_stylebox_override("panel", sb)
		holder.add_child(page)
		add_child(chars)
		chars._build_mastery_block(page, shot["hero"])
		await get_tree().process_frame
		remove_child(chars)
		await _shoot(holder, Vector2i(760, 460), str(shot["file"]))
		chars.queue_free()

	# --- 3. SÉLECTEUR DE TITRE -------------------------------------------------------------------
	var prof = load("res://scenes/ui/profile.tscn").instantiate()
	add_child(prof)
	await get_tree().process_frame
	var cat := MasteryBorder.faction_catalogue()
	var ids := cat.keys()
	prof._masteries = [
		{"faction_id": str(ids[0]), "rank": 23, "title_key": "legend", "border_tier": "gold",
		 "unlocked_titles": ["veteran", "elite", "master", "legend"]},
		{"faction_id": str(ids[1]), "rank": 6, "title_key": "elite", "border_tier": "bronze",
		 "unlocked_titles": ["veteran", "elite"]},
	]
	prof._equipped_title = "%s:legend" % str(ids[0])
	prof._populate_overview_tab()
	prof._open_title_picker()
	for i in range(4):
		await get_tree().process_frame
	var picker: Control = prof.find_child("TitlePicker", true, false) as Control
	if picker != null:
		prof.remove_child(picker)
		await _shoot(picker, Vector2i(900, 640), "mastery_picker.png")
	else:
		printerr("  !! selecteur introuvable — capture SAUTEE (a investiguer)")
	prof.queue_free()

	# --- 4. PODIUM DU RAPPORT POST-OP ------------------------------------------------------------
	# On garnit `GameState.players` comme le ferait une vraie fin de partie : c'est de là que le
	# podium tire titres et bordures (§3.4), pas d'une source dédiée.
	GameState.players = {
		"1": {"username": "VIPERE", "faction": str(ids[0]), "equipped_title": "%s:legend" % str(ids[0]),
			  "mastery_rank": 23, "mastery_border": "gold"},
		"2": {"username": "KORVAX", "faction": str(ids[1]), "equipped_title": "%s:veteran" % str(ids[1]),
			  "mastery_rank": 2, "mastery_border": "steel"},
		"3": {"username": "NOVICE", "faction": str(ids[2]), "equipped_title": "",
			  "mastery_rank": 0, "mastery_border": ""},
	}
	var rep = load("res://scenes/game/operation_report.tscn").instantiate()
	add_child(rep)
	await get_tree().process_frame
	rep.populate_podium([
		{"pid": 1, "medal": "01", "titles": ["TITLE_CONQUEROR"], "objective": "Contrôler 24 territoires",
		 "completed": true, "has_reveal": true, "kills": 31, "conquests": 12, "eliminations": 2},
		{"pid": 2, "medal": "02", "titles": [], "objective": "Éliminer 2 joueurs",
		 "completed": false, "has_reveal": true, "kills": 18, "conquests": 7, "eliminations": 1},
		{"pid": 3, "medal": "03", "titles": [], "objective": "Tenir l'Europe 3 tours",
		 "completed": false, "has_reveal": true, "kills": 4, "conquests": 2, "eliminations": 0},
	], true)
	for i in range(4):
		await get_tree().process_frame
	var list = rep._podium_list
	if list != null:
		list.get_parent().remove_child(list)
		var wrap := PanelContainer.new()
		wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sb2 := StyleBoxFlat.new()
		sb2.bg_color = GUNMETAL
		sb2.set_content_margin_all(24.0)
		wrap.add_theme_stylebox_override("panel", sb2)
		wrap.add_child(list)
		await _shoot(wrap, Vector2i(900, 420), "mastery_podium.png")
	rep.queue_free()

	await get_tree().process_frame
	print("[CAPTURES] terminees.")
	get_tree().quit(0)


func _hero(rank: int, unlocked: bool, title_key = null, border := "",
		next_title = {"rank": 1, "title_key": "veteran"}) -> Dictionary:
	return {
		"faction_id": "phalanges_acier", "level": 50 if unlocked else 31,
		"xp_total": 84000, "xp_in_level": 260, "xp_for_level": 900,
		"access": {"type": "free", "free_games_left": 5, "free_games_max": 5, "price": 0},
		"record": {"games": 128, "wins": 41, "losses": 87, "winrate": 32},
		"mastery": {
			"rank": rank, "title_key": title_key, "border_tier": border,
			"unlocked": unlocked, "unlocked_titles": [],
			"xp_into_rank": 3120, "xp_per_rank": 5000, "next_title": next_title,
		},
	}
