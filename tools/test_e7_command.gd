extends Node

# TEST E7 §8.79 (style maison) — Commandement fluide : cibles valides exactes (adjacence +
# propriété), légalité du ré-assaut re-testée par état, coup de pouce « aucune action possible »,
# raccourcis de quantité (tampon borné au stock). Arène réelle + états stub.
#   & <godot_console> --headless --path frontend res://tools/test_e7_command.tscn

# État : je (11) tiens alaska (5) et alberta (1) ; 7 tient northwest_territory + ontario, tous
# adjacents à alaska. brazil (7) n'est PAS adjacent à alaska.
const STATE := {
	"stage": "playing", "current_turn": 5, "current_player_id": 11, "phase": 3,
	"turn_order": [11.0, 7.0],
	"players": {
		"11": {"username": "HAKIM", "faction": "", "is_active": true, "status": "alive"},
		"7": {"username": "VULTURE", "faction": "", "is_active": true, "status": "alive"},
	},
	"territories": {
		"alaska": {"owner_id": 11.0, "garrison": 5},
		"alberta": {"owner_id": 11.0, "garrison": 1},
		"northwest_territory": {"owner_id": 7.0, "garrison": 3},
		"ontario": {"owner_id": 7.0, "garrison": 2},
		"kamchatka": {"owner_id": 7.0, "garrison": 4},
		"brazil": {"owner_id": 7.0, "garrison": 2},
	},
}

func _ready() -> void:
	# Le contrôleur lit AuthManager.user_id pour « moi » : on l'aligne sur le joueur 11 du stub.
	AuthManager.user_id = 11
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	GameState.update_from_json(STATE)
	arena._refresh()

	# 1) Cibles valides depuis alaska : voisins ennemis (northwest_territory, kamchatka) — PAS
	# alberta (à moi), PAS brazil (non adjacent).
	var targets: Array = arena._valid_attack_targets("alaska")
	targets.sort()
	assert(targets == ["kamchatka", "northwest_territory"])
	# alberta n'a qu'1 unité → mais _valid_attack_targets ne teste QUE la source côté cibles ;
	# depuis alberta, voisins ennemis = ontario + northwest_territory.
	var t2: Array = arena._valid_attack_targets("alberta")
	assert(t2.has("ontario") and t2.has("northwest_territory"))
	print("[OK] valid_attack_targets : adjacence + propriete (2 asserts)")

	# 2) Ré-assaut : après un assaut alaska→northwest_territory, légal (source 5≥2, cible ennemie).
	arena._last_attack = {"source": "alaska", "target": "northwest_territory"}
	assert(arena._reassault_legal())
	# Cible devenue mienne → plus légal.
	arena._last_attack = {"source": "alaska", "target": "alberta"}
	assert(not arena._reassault_legal())
	# Source à 1 unité → plus légal.
	arena._last_attack = {"source": "alberta", "target": "ontario"}
	assert(arena._garrison("alberta") == 1 and not arena._reassault_legal())
	print("[OK] reassault_legal : source/cible/garnison re-testees (3 asserts)")

	# 3) Coup de pouce « aucune action » : en Phase 3 j'ai des attaques → action possible.
	assert(not arena._no_action_possible())
	# Phase 4 sans aucun voisin allié adjacent (alaska/alberta adjacents mais alberta<2… le
	# mouvement exige source≥2 ET voisin allié) : alaska(5) voisin allié = alberta → possible.
	GameState.current_phase = 4
	assert(not arena._no_action_possible())
	# Isolons : un état où je n'ai qu'UN territoire → aucun mouvement/attaque.
	GameState.territories = {"alaska": {"owner_id": 11.0, "garrison": 5},
		"brazil": {"owner_id": 7.0, "garrison": 2}}  # brazil non adjacent à alaska
	GameState.current_phase = 3
	assert(arena._no_action_possible())  # alaska n'a aucun voisin ENNEMI présent sur la carte réduite
	print("[OK] no_action_possible : detecte l'impasse (3 asserts)")

	# 4) Raccourci quantité : tampon borné au stock (Ctrl=MAX ne dépasse jamais le quota).
	# STATE est const (lecture seule) → on duplique en profondeur pour poser le stock.
	var s4: Dictionary = STATE.duplicate(true)
	s4["players"]["11"]["units_in_stock"] = 8
	GameState.update_from_json(s4)
	GameState.current_phase = 2  # renforts → déploiement
	arena.pending_deployments = {}
	arena._buffer_add("alaska", 5)          # +5
	assert(arena._pending_total() == 5)
	arena._buffer_add("alaska", 99)         # MAX simulé (delta énorme) → borné au reliquat (3)
	assert(arena._pending_total() == 8)     # jamais > quota 8
	print("[OK] buffer_add : +N borne au stock (2 asserts)")

	print("[OK] TEST E7 COMMAND : 10 asserts verts")
	get_tree().quit(0)
