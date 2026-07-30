extends Node

# OUTIL §8.121 (validation VISUELLE, hors test CI) — compose et EXPORTE réellement les deux formats
# de la CARTE DE PARTAGE sur un jeu de données de démonstration, puis recopie les PNG dans OUT_DIR
# pour inspection.
#
# ⚠️ LANCEMENT FENÊTRÉ OBLIGATOIRE : un run `--headless` n'a pas de renderer, le SubViewport ne
# dessine rien et `export_pngs` renvoie une liste VIDE par construction (garde explicite dans
# share_card._render_to_png). Même contrainte que tools/preview_report.tscn (§8.100).
#
#   & <godot_console> --path frontend res://tools/preview_share_card.tscn
#
# Les fichiers de production atterrissent dans `user://captures/` (le vrai dossier du joueur) ; une
# copie est déposée dans OUT_DIR ci-dessous.

const ShareCard := preload("res://scripts/game/share_card.gd")
const OUT_DIR := "C:/Users/Hakim/AppData/Local/Temp/claude/C--Users-Hakim-Documents-Wasteland-Warfare-Project/a271dbe2-d438-4f2c-a694-db39a1f9cb44/scratchpad"


func _demo_payload() -> Dictionary:
	var portrait: Texture2D = null
	for path in ["res://assets/images/heroes/phalanges.png",
			"res://assets/images/heroes/nomades.png", "res://assets/images/logo_ww.png"]:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Texture2D:
				portrait = res
				break
	return {
		"verdict": "VICTOIRE", "verdict_reason": "TEMPS ÉCOULÉ — VICTOIRE AU SCORE",
		"is_victory": true,
		"podium": [
			{"name": "HAKIM", "color": Color("36c5d9"), "medal": "01"},
			{"name": "[IA] VULTURE-7", "color": Color("c0654f"), "medal": "02"},
			{"name": "KOVACS", "color": Color("8a97a5"), "medal": "03"},
		],
		"faction_name": "Steel Phalanx",
		"leader": "GÉNÉRAL VIKTOR \"IRONLINE\" STAHL",
		"portrait": portrait,
		"accent": Color("36c5d9"),
		"titles": ["BOUCHER", "CONQUÉRANT", "INDESTRUCTIBLE"],
		"timeline": [
			{"color": Color("36c5d9"), "points": [14, 16, 22, 30, 38]},
			{"color": Color("c0654f"), "points": [14, 13, 11, 9, 4]},
			{"color": Color("8a97a5"), "points": [14, 13, 9, 3, 0]},
		],
		"betrayal_line": "✸ HAKIM A POIGNARDÉ KOVACS — ROUND 5",
		"stats": [["KILLS", "47"], ["CONQUÊTES", "14"], ["DURÉE", "12:40"]],
		"duration": "12:40", "kills": 47, "conquests": 14, "betrayals": 1,
	}


func _ready() -> void:
	var payload := _demo_payload()
	var card = ShareCard.new()
	add_child(card)
	var saved: Array = await card.export_pngs(payload)
	print("[PREVIEW] fichiers écrits : %d" % saved.size())
	for path in saved:
		print("  → %s   (%s)" % [path, ProjectSettings.globalize_path(str(path))])
		# Copie dans OUT_DIR pour inspection immédiate.
		var img := Image.load_from_file(ProjectSettings.globalize_path(str(path)))
		if img != null:
			var dest := "%s/%s" % [OUT_DIR, str(path).get_file()]
			img.save_png(dest)
			print("     copie : %s  (%dx%d)" % [dest, img.get_width(), img.get_height()])
	print("[PREVIEW] résumé presse-papiers : %s" % ShareCard.clipboard_summary(payload))
	if saved.is_empty():
		print("[PREVIEW] ⚠ AUCUN fichier : lancement en --headless ? (renderer requis)")
	card.queue_free()
	get_tree().quit(0)
