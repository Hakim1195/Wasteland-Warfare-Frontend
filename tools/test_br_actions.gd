extends Node

# CONTRE-ÉPREUVE — LES TROIS ACTIONS BATTLE ROYALE AU HUD (finitions pré-playtest)
# Arène RÉELLE + états stub, patron maison `test_e7_command.gd`.
#   & <godot_console> --headless --path frontend res://tools/test_br_actions.tscn
#
# CE QU'ELLE VERROUILLE, et pourquoi chacun compte :
#   (a) FFA → AUCUN des trois boutons. C'est l'invariant `team_id = 0` vu depuis l'UI : une partie
#       solo ne doit pas même savoir que ce mode existe.
#   (b) Un NON-TRAÎTRE ne voit AUCUN bouton de coup d'État — pas même grisé. Un bouton grisé
#       apprendrait que le dispositif est actif dans cette partie, et comme le tirage est
#       TOUT-OU-RIEN, il révélerait du même coup que l'équipe adverse a son traître.
#   (c) Chaque grisage porte SA raison en infobulle (jamais de bouton mort muet).
#   (d) Le coût de réanimation vient de l'ÉTAT SERVEUR quand il est présent, du repli sinon.
#   (e) Les trois gestes passent par une MODALE : le clic n'envoie plus rien tout seul.

const ME := 11
const MATE := 12
const FOE := 7

# 2v2 : moi (11) + coéquipier (12) contre 7. Le coéquipier est MORT et réanimable.
static func br_state(overrides: Dictionary = {}) -> Dictionary:
	var st := {
		"stage": "playing", "current_turn": 9, "current_player_id": ME, "phase": 3,
		"turn_order": [11.0, 7.0, 12.0],
		"team_mode": "duo_2v2",
		"players": {
			"11": {"username": "HAKIM", "faction": "", "is_active": true, "status": "alive",
				"team_id": 1, "hero_pv_current": 250, "hero_pv_max": 300},
			"12": {"username": "MATE", "faction": "", "is_active": true, "status": "eliminated",
				"team_id": 1, "hero_pv_current": 0, "hero_pv_max": 300},
			"7": {"username": "VULTURE", "faction": "", "is_active": true, "status": "alive",
				"team_id": 2, "hero_pv_current": 180, "hero_pv_max": 300},
		},
		"territories": {
			"alaska": {"owner_id": 11.0, "garrison": 5},
			"alberta": {"owner_id": 11.0, "garrison": 3},
			"ontario": {"owner_id": 7.0, "garrison": 4},
		},
		# 4 snapshots → round global 5 (au-delà des seuils reddition 3 et coup 4).
		"statistics": {"territory_history": [{}, {}, {}, {}]},
		"battle_royale": {"revives_done": {}, "revived": [], "crates": {}, "surrender": {},
			"coup_used": []},
		"traitors": {},
	}
	for k in overrides:
		st[k] = overrides[k]
	return st


# Libellés des boutons actuellement dans la carte POUVOIR.
func _power_buttons(arena) -> Array:
	var out: Array = []
	for c in arena.hud.get_node("%PowerBox").get_children():
		if c is Button:
			out.append({"text": c.text, "disabled": c.disabled, "tooltip": c.tooltip_text})
	return out

func _find(buttons: Array, needle: String) -> Dictionary:
	for b in buttons:
		if str(b["text"]).findn(needle) >= 0:
			return b
	return {}


func _ready() -> void:
	AuthManager.user_id = ME
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var checks := 0

	# --- (a) FFA : AUCUN bouton Battle Royale ---------------------------------------------------
	var ffa := br_state()
	ffa["team_mode"] = ""
	for pid in ffa["players"]:
		ffa["players"][pid]["team_id"] = 0
	ffa["players"]["12"]["status"] = "alive"
	GameState.update_from_json(ffa)
	arena._push_power_card()
	var btns := _power_buttons(arena)
	assert(_find(btns, tr("BR_REVIVE")).is_empty())
	assert(_find(btns, tr("BR_SURRENDER")).is_empty())
	assert(_find(btns, tr("BR_COUP_BUTTON")).is_empty())
	checks += 3
	print("[OK] FFA : aucun des trois boutons (3 asserts)")

	# --- (b) BR, NON-TRAÎTRE : réanimer + se rendre, mais PAS de coup d'État ---------------------
	GameState.update_from_json(br_state())
	arena._push_power_card()
	btns = _power_buttons(arena)
	var revive := _find(btns, tr("BR_REVIVE"))
	var surrender := _find(btns, tr("BR_SURRENDER"))
	assert(not revive.is_empty())
	assert(not revive["disabled"])              # 250 PV − 100 ≥ 1 → actif
	assert(not surrender.is_empty())
	assert(not surrender["disabled"])           # round 5 ≥ 3 → actif
	# ⚠️ LE test du lot : pas de bouton, pas même grisé.
	assert(_find(btns, tr("BR_COUP_BUTTON")).is_empty())
	checks += 5
	print("[OK] BR non-traitre : reanimer+reddition actifs, AUCUN coup d'Etat (5 asserts)")

	# --- (c) GRISAGES : chaque refus porte SA raison en infobulle --------------------------------
	# PV insuffisants (90 − 100 < 1).
	var poor := br_state()
	poor["players"]["11"]["hero_pv_current"] = 90
	GameState.update_from_json(poor)
	arena._push_power_card()
	revive = _find(_power_buttons(arena), tr("BR_REVIVE"))
	assert(not revive.is_empty() and revive["disabled"])
	assert(revive["tooltip"] == tr("BR_ERR_NOT_ENOUGH_HP"))
	# Déjà réanimé une fois.
	var used := br_state()
	used["battle_royale"]["revives_done"] = {"11": 1}
	GameState.update_from_json(used)
	arena._push_power_card()
	revive = _find(_power_buttons(arena), tr("BR_REVIVE"))
	assert(not revive.is_empty() and revive["disabled"])
	assert(revive["tooltip"] == tr("BR_ERR_ALREADY_USED"))
	# Reddition trop tôt (round 1 : aucun snapshot d'historique).
	var early := br_state()
	early["statistics"] = {"territory_history": []}
	GameState.update_from_json(early)
	arena._push_power_card()
	surrender = _find(_power_buttons(arena), tr("BR_SURRENDER"))
	assert(not surrender.is_empty() and surrender["disabled"])
	assert(surrender["tooltip"] == tr("BR_ERR_NO_SURRENDER_YET"))
	checks += 6
	print("[OK] Grisages : 3 boutons grises, chacun avec SA raison en infobulle (6 asserts)")

	# --- (d) COÛT DE RÉANIMATION : l'état serveur prime, le repli client suit --------------------
	assert(arena._br_revive_cost() == arena.BR_REVIVE_COST)   # état sans `rules` → repli
	var ruled := br_state()
	ruled["battle_royale"]["rules"] = {"revive_hp_cost": 140, "surrender_min_round": 6,
		"coup_min_round": 9}
	GameState.update_from_json(ruled)
	assert(arena._br_revive_cost() == 140)        # le serveur fait foi
	assert(arena._br_surrender_round() == 6)
	assert(arena._br_coup_round() == 9)
	# …et le libellé annonce BIEN la valeur serveur, pas la constante.
	arena._push_power_card()
	assert(_find(_power_buttons(arena), tr("BR_REVIVE"))["text"].find("140") >= 0)
	checks += 5
	print("[OK] Reglages : etat serveur prioritaire, repli client sinon (5 asserts)")

	# --- (e) TRAÎTRE : le bouton apparaît, et le rapport de force est exact ----------------------
	var traitor := br_state()
	traitor["traitors"] = {"11": FOE}
	GameState.update_from_json(traitor)
	arena._push_power_card()
	btns = _power_buttons(arena)
	assert(not _find(btns, tr("BR_COUP_BUTTON")).is_empty())
	# Puissance = garnisons + PV héros. Moi : 5 + 3 + 250 = 258. Lui : 4 + 180 = 184.
	assert(arena._coup_power(ME) == 258)
	assert(arena._coup_power(FOE) == 184)
	checks += 3
	print("[OK] Traitre : bouton present, rapport de force exact (3 asserts)")

	# --- (f) MODALE : le clic ne poste RIEN, il ouvre une question -------------------------------
	assert(not arena.hud.is_confirm_open())
	arena._on_power_action_requested("br_coup")
	assert(arena.hud.is_confirm_open())          # 1er clic → modale, aucun envoi
	arena.hud.hide_confirm()
	assert(not arena.hud.is_confirm_open())      # annulation → retour à l'état normal
	arena._on_power_action_requested("br_revive_%d" % MATE)
	assert(arena.hud.is_confirm_open())
	arena.hud.hide_confirm()
	arena._on_power_action_requested("br_surrender")
	assert(arena.hud.is_confirm_open())
	arena.hud.hide_confirm()
	checks += 6
	print("[OK] Modale : les 3 gestes passent par une confirmation, annulable (6 asserts)")

	print("[OK] TEST BR ACTIONS : %d asserts verts" % checks)
	get_tree().quit(0)
