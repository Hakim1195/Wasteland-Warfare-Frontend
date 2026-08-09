extends Node

# CAPTURE DE RECETTE — ZONE LÉTALE (§8.145) : distinction ZONE COURANTE / TÉLÉGRAPHE, et rendu des
# évènements `zone_damage` au Journal de Guerre (ligne ☢ + entrée MAJEURE pour un territoire ravagé).
# ⚠️ SANS `--headless` : le rasteriseur factice rend des images vides.
#   & <godot_console> --path frontend res://tools/shot_zone_lethal.tscn -- --shots <dir>

const ME := 11
const FOE := 7

# Deux blocs DISJOINTS et voisins à l'écran (Amérique du Nord), pour que la comparaison se fasse
# d'un seul coup d'œil : ce qui tue MAINTENANT vs ce qui est ANNONCÉ.
const ZONE_NOW := ["alaska", "northwest_territory", "alberta"]
const ZONE_NEXT := ["ontario", "quebec", "greenland"]

const STATE := {
	"stage": "playing", "current_turn": 5, "current_player_id": ME, "phase": 3,
	"turn_order": [11.0, 7.0],
	"players": {
		"11": {"username": "HAKIM", "faction": "", "is_active": true, "status": "alive"},
		"7": {"username": "VULTURE", "faction": "", "is_active": true, "status": "alive"},
	},
	"territories": {
		"alaska": {"owner_id": 11.0, "garrison": 6},
		"northwest_territory": {"owner_id": 7.0, "garrison": 4},
		"alberta": {"owner_id": 11.0, "garrison": 3},
		"ontario": {"owner_id": 11.0, "garrison": 8},
		"quebec": {"owner_id": 7.0, "garrison": 5},
		"greenland": {"owner_id": 11.0, "garrison": 2},
		"western_united_states": {"owner_id": 11.0, "garrison": 7},
		"eastern_united_states": {"owner_id": 7.0, "garrison": 3},
		"kamchatka": {"owner_id": 7.0, "garrison": 9},
	},
	"contamination_zone": {"territories": ZONE_NOW, "next_territories": ZONE_NEXT,
		"probability": 1.0},
}

func _ready() -> void:
	await get_tree().process_frame
	AuthManager.user_id = ME
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	var dir: String = args[i + 1] if (i >= 0 and i + 1 < args.size()) \
		else ProjectSettings.globalize_path("user://shots")
	DirAccess.make_dir_recursive_absolute(dir)

	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	GameState.update_from_json(STATE)
	arena._refresh()
	await get_tree().process_frame

	# 1) Le plateau : bloc VERT PLEIN (zone courante, badge ☢) vs LISERÉ OR PULSANT (télégraphe,
	#    badge ⚠). Aucun remplissage sur le bloc annoncé — c'est TOUTE la distinction.
	await _shot(dir, "20_zone_courante_vs_telegraphe")

	# 2) Le Journal : les évènements structurés `zone_damage` du serveur, tels que rendus.
	#    Un territoire RAVAGÉ produit une entrée MAJEURE (elle remonte aussi au kill feed).
	arena._on_game_event({
		"event_type": "turn_passed",
		"system_events": [
			{"code": "zone_damage", "territory_id": "alaska", "owner_id": float(ME),
				"amount": 1, "ravaged": false},
			{"code": "zone_damage", "territory_id": "northwest_territory", "owner_id": float(FOE),
				"amount": 1, "ravaged": false},
			{"code": "zone_damage", "territory_id": "alberta", "owner_id": float(ME),
				"amount": 1, "ravaged": true},
			{"code": "zone_protected", "faction_id": "culte_isotope", "territory_id": "quebec"},
		],
	})
	await get_tree().process_frame
	await _shot(dir, "21_journal_zone_damage_killfeed")

	# 3) L'onglet JOURNAL lui-même, OUVERT. ⚠️ Sans ce troisième cliché, la capture 21 ne prouve
	#    QUE le kill feed et le toast : le panneau INFO s'ouvre sur OBJECTIFS et les lignes ☢
	#    resteraient invisibles (« l'écran muet » du RETEX §8.144).
	arena.hud.get_node("%InfoTabs").current_tab = arena.hud.TAB_INFO_JOURNAL
	await get_tree().process_frame
	await _shot(dir, "22_journal_ouvert")

	print("[SHOTS] termine -> %s" % dir)
	get_tree().quit(0)

func _shot(dir: String, name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[SHOT] %s.png" % name)
