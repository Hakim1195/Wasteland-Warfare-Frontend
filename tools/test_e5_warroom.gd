extends Node

# TEST E5 §8.77 (style maison) — War Room : agrégats exacts sur un état stub (2 joueurs,
# compteurs connus), tri par territoires, indice de menace, continent contrôlé vs contesté,
# smoke HUD (3ᵉ tiroir peuplé + toggle). Clés de statistics en STRING (piège §5).
#   & <godot_console> --headless --path frontend res://tools/test_e5_warroom.tscn

const WarRoom := preload("res://scripts/ui/war_room.gd")

const PLAYERS := {"11": {"username": "HAKIM"}, "7": {"username": "VULTURE"}}
const TERRITORIES := {
	"alaska": {"owner_id": 7.0, "garrison": 3},
	"alberta": {"owner_id": 7.0, "garrison": 2},
	"ontario": {"owner_id": 7.0, "garrison": 1},
	"peru": {"owner_id": 11.0, "garrison": 5},
	"venezuela": {"owner_id": 11.0, "garrison": 2},
	"brazil": {"owner_id": null, "garrison": 0},
}
const STATS := {
	"combat_kills_by_player": {"11": 14.0, "7": 6.0},
	"losses_by_player": {"11": 7.0, "7": 12.0},
	"conquests_by_player": {"11": 5.0},
	"eliminations_by_player": {"11": 1.0},
	"hero_damage_by_player": {"11": 86.0, "7": 30.0},
	"hero_kills_by_player": {"11": 1.0},
	"zone_kills_by_player": {"7": 3.0},
}

func _ready() -> void:
	# 1) Agrégats exacts + tri territoires desc (7 possède 3 territoires, 11 en a 2).
	var rows: Array = WarRoom.player_rows(PLAYERS, TERRITORIES, STATS)
	assert(rows.size() == 2)
	assert(int(rows[0]["pid"]) == 7 and int(rows[0]["territories"]) == 3)
	assert(int(rows[1]["pid"]) == 11 and int(rows[1]["territories"]) == 2)
	var r11: Dictionary = rows[1]
	assert(int(r11["kills"]) == 14 and int(r11["losses"]) == 7)
	assert(int(r11["conquests"]) == 5 and int(r11["eliminations"]) == 1)
	assert(int(r11["hero_damage"]) == 86 and int(r11["hero_kills"]) == 1)
	assert(int(r11["zone_deaths"]) == 0 and int(rows[0]["zone_deaths"]) == 3)
	assert(absf(float(r11["ratio"]) - 14.0 / 21.0) < 0.001)
	# Indice de menace documenté : territoires×2 + kills − pertes + éliminations×5.
	assert(int(r11["threat"]) == 2 * 2 + 14 - 7 + 1 * 5)
	assert(WarRoom.threat_index(3, 6, 12, 0) == int(rows[0]["threat"]))
	print("[OK] player_rows : agrégats, tri, ratio, menace (10 asserts)")

	# 2) Continents : contrôlé (SA entière à 11 sauf brazil neutre → CONTESTÉ), stub dédié.
	var continents := {
		"south_america": {"name": "Amérique du Sud",
			"tids": ["peru", "venezuela", "brazil", "argentina"]},
		"mini": {"name": "Mini", "tids": ["alaska", "alberta", "ontario"]},
	}
	var cr: Array = WarRoom.continent_rows(TERRITORIES, continents)
	assert(cr.size() == 2)
	assert(cr[0]["owner"] == null and int(cr[0]["held"]) == 2 and int(cr[0]["leader_pid"]) == 11)
	# « mini » : les 3 territoires appartiennent à 7 → CONTRÔLÉ.
	assert(cr[1]["owner"] != null and int(cr[1]["owner"]) == 7 and int(cr[1]["held"]) == 3)
	print("[OK] continent_rows : contesté vs contrôlé (3 asserts)")

	# 3) Smoke HUD : 3ᵉ tiroir construit, peuplé et togglable dans l'arène réelle.
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var hud = arena.get_node("HUD")
	assert(hud._war_intel_btn != null and hud._war_intel_panel != null)
	hud.set_war_intel(rows, cr)
	assert(hud._war_intel_players.get_child_count() == 2)
	assert(hud._war_intel_continents.get_child_count() == 2)
	hud._toggle_war_intel()
	assert(hud._war_intel_panel.visible)
	print("[OK] HUD : tiroir INTEL GUERRE construit + peuplé (4 asserts)")

	print("[OK] TEST E5 WARROOM : 17 asserts verts")
	get_tree().quit(0)
