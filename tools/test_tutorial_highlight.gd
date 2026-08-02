extends Node

# CONTRE-ÉPREUVE — SURLIGNAGE PLATEAU DE L'ÉTAPE « ATTAQUER » (finitions pré-playtest)
#   & <godot_console> --headless --path frontend res://tools/test_tutorial_highlight.tscn
#
# Ce que ça verrouille :
#   (a) la cible désignée est le MEILLEUR ratio, pas le premier voisin venu ;
#   (b) le surlignage emprunte le canal du télégraphe (aucun canal neuf) ;
#   (c) LES QUATRE CHEMINS DE NETTOYAGE éteignent le liseré. C'est le vrai risque du lot : un
#       liseré or oublié se lit comme une ZONE RADIOACTIVE ANNONCÉE — on ferait paniquer le joueur
#       pour un reste de tutoriel.

const ME := 11
const FOE := 7

# alaska (moi, 9 unités) touche northwest_territory (ennemi, 1 → proie facile) et kamchatka
# (ennemi, 12 → suicide). alberta (moi, 2) touche ontario (ennemi, 9).
# La MEILLEURE cible est donc northwest_territory, et surtout PAS kamchatka.
const STATE := {
	"stage": "playing", "current_turn": 5, "current_player_id": ME, "phase": 3,
	"turn_order": [11.0, 7.0],
	"players": {
		"11": {"username": "HAKIM", "faction": "", "is_active": true, "status": "alive"},
		"7": {"username": "VULTURE", "faction": "", "is_active": true, "status": "alive"},
	},
	"territories": {
		"alaska": {"owner_id": 11.0, "garrison": 9},
		"alberta": {"owner_id": 11.0, "garrison": 2},
		"northwest_territory": {"owner_id": 7.0, "garrison": 1},
		"kamchatka": {"owner_id": 7.0, "garrison": 12},
		"ontario": {"owner_id": 7.0, "garrison": 9},
	},
}


# Territoires dont le canal `territory_forecast` (liseré or) est ALLUMÉ dans le shader d'overlay.
# Relit l'uniforme réellement poussé par `generate_board()` et le re-traduit en ids via `_tid_index`.
func _forecast_lit(board) -> Array:
	var mat := (board._overlay.material as ShaderMaterial)
	var arr: PackedFloat32Array = mat.get_shader_parameter("territory_forecast")
	var out: Array = []
	for tid in board._tid_index:
		var oi: int = int(board._tid_index[tid]) - 1
		if oi >= 0 and oi < arr.size() and arr[oi] > 0.5:
			out.append(str(tid))
	out.sort()
	return out


func _ready() -> void:
	AuthManager.user_id = ME
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	GameState.update_from_json(STATE)
	arena._refresh()
	var board = arena.board
	var checks := 0

	# --- (a) La cible : meilleur ratio, source cohérente ----------------------------------------
	var hint: Dictionary = arena.tutorial_attack_hint()
	assert(not hint.is_empty())
	assert(str(hint["tid"]) == "northwest_territory")   # 9 contre 1, pas 9 contre 12
	assert(str(hint["source"]) == "alaska")
	assert(float(hint["prob"]) > 0.9)
	assert(str(hint["name"]) != "")                     # nom TRADUIT, jamais vide
	checks += 5
	print("[OK] Cible : meilleur ratio (northwest_territory), source alaska (5 asserts)")

	# Hors de MON tour, aucune suggestion (le coach ne pousse pas à jouer quand ce n'est pas l'heure).
	var not_mine: Dictionary = STATE.duplicate(true)
	not_mine["current_player_id"] = FOE
	GameState.update_from_json(not_mine)
	assert(arena.tutorial_attack_hint().is_empty())
	GameState.update_from_json(STATE)
	checks += 1
	print("[OK] Hors tour : aucune suggestion (1 assert)")

	# --- (b) Le canal d'overlay : allumage / extinction ------------------------------------------
	# ⚠️ On vérifie l'UNIFORME DE SHADER RÉELLEMENT POUSSÉ, pas seulement la variable interne. Une
	# capture d'écran ne peut pas trancher ici : le plateau est ANIMÉ (particules de carte vivante,
	# pulsation du liseré), donc deux images successives diffèrent partout et un diff de pixels ne
	# prouve rien. L'entrée du shader, elle, est exacte : c'est ELLE qui allume le bon territoire.
	assert(board._tutorial_tid == "")
	assert(_forecast_lit(board) == [])                       # aucun télégraphe dans cet état
	board.tutorial_highlight("northwest_territory")
	assert(board._tutorial_tid == "northwest_territory")
	assert(_forecast_lit(board) == ["northwest_territory"])  # LE bon territoire, et lui SEUL
	board.tutorial_highlight_clear()
	assert(board._tutorial_tid == "")
	assert(_forecast_lit(board) == [])
	checks += 6
	print("[OK] Canal overlay : le shader allume LE bon territoire, et lui seul (6 asserts)")

	# --- (c) LES QUATRE CHEMINS DE NETTOYAGE -----------------------------------------------------
	TutorialManager.bind_arena(arena, arena.hud)

	# 1. Première attaque lancée → `_close_step("attack")`.
	TutorialManager.guided = true
	TutorialManager._steps_done.clear()
	board.tutorial_highlight("northwest_territory")
	TutorialManager._close_step("attack")
	assert(board._tutorial_tid == "")
	checks += 1

	# 2. Changement d'étape → `_pump()` rend la main à l'étape suivante.
	TutorialManager.guided = true
	TutorialManager._steps_done.clear()
	TutorialManager._current = {}
	TutorialManager._queue.clear()
	board.tutorial_highlight("kamchatka")
	TutorialManager._arm("hero")            # une étape SANS surlignage plateau
	assert(board._tutorial_tid == "")
	checks += 1

	# 3. « PASSER LE BRIEFING ».
	TutorialManager.guided = true
	TutorialManager._steps_done.clear()
	board.tutorial_highlight("northwest_territory")
	TutorialManager._on_skip_requested()
	assert(board._tutorial_tid == "")
	checks += 1

	# 4. Fin de partie — y compris si le briefing a DÉJÀ été soldé (`guided` faux) : c'est le cas
	#    qui laissait un liseré derrière lui, la garde `guided` étant placée avant le nettoyage.
	TutorialManager.guided = false
	board.tutorial_highlight("northwest_territory")
	TutorialManager.notify_game_over()
	assert(board._tutorial_tid == "")
	checks += 1
	print("[OK] Nettoyage : les 4 chemins eteignent le lisere (4 asserts)")

	print("[OK] TEST TUTORIAL HIGHLIGHT : %d asserts verts" % checks)
	get_tree().quit(0)
