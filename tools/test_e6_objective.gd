extends Node

# TEST E6 §8.78 (style maison) — Tracker d'objectif vivant : progression par TYPE (conquer /
# continents / eliminate), objectif DOUBLE (2 volets, plus avancé en tête, OU), cible déjà tombée.
#   & <godot_console> --headless --path frontend res://tools/test_e6_objective.tscn

const Tracker := preload("res://scripts/ui/objective_tracker.gd")

func _ready() -> void:
	# 1) conquer_territories : 14/24 → ratio 0.583, non accompli.
	var conquer := {"type": "conquer_territories", "params": {"n": 24}}
	var p1: Dictionary = Tracker.leg_progress(conquer, {"owned_count": 14})
	assert(p1["label"] == "14/24 territoires")
	assert(absf(float(p1["ratio"]) - 14.0 / 24.0) < 0.001 and not p1["done"])
	var p1b: Dictionary = Tracker.leg_progress(conquer, {"owned_count": 24})
	assert(p1b["done"] and absf(float(p1b["ratio"]) - 1.0) < 0.001)
	print("[OK] conquer_territories : ratio + done (3 asserts)")

	# 2) control_continents : 1/2.
	var cont := {"type": "control_continents", "params": {"n": 2}}
	var p2: Dictionary = Tracker.leg_progress(cont, {"continents_owned": 1})
	assert(p2["label"] == "1/2 continents" and absf(float(p2["ratio"]) - 0.5) < 0.001)
	print("[OK] control_continents : ratio (1 assert)")

	# 3) eliminate_player : VIVANT (0.0) vs ABATTU ✔ (1.0, done).
	var elim := {"type": "eliminate_player", "params": {"target_id": 7}}
	var p3a: Dictionary = Tracker.leg_progress(elim, {"target_alive": true, "target_name": "VULTURE"})
	assert(p3a["label"] == "VULTURE : VIVANT" and float(p3a["ratio"]) == 0.0 and not p3a["done"])
	var p3b: Dictionary = Tracker.leg_progress(elim, {"target_alive": false, "target_name": "VULTURE"})
	assert(p3b["label"].find("ABATTU") >= 0 and float(p3b["ratio"]) == 1.0 and p3b["done"])
	print("[OK] eliminate_player : vivant/abattu (2 asserts)")

	# 4) DOUBLE : kill (cible vivante 0.0) OU classique (18/24 = 0.75) → classique en tête, best 0.75.
	var double := {
		"type": "double", "params": {"target_id": 7},
		"kill_objective": {"type": "eliminate_player", "params": {"target_id": 7}},
		"classic_objective": {"type": "conquer_territories", "params": {"n": 24}},
		"description": "Tuer le héros du joueur #7 — OU — Contrôler 24 territoires",
	}
	var pd: Dictionary = Tracker.progress(double, {
		"owned_count": 18, "target_alive": true, "target_name": "VULTURE"})
	assert(pd["lines"].size() == 2)
	# Plus avancé en tête : le volet classique (0.75) devant le kill (0.0).
	assert(pd["lines"][0]["label"] == "18/24 territoires")
	assert(absf(float(pd["best_ratio"]) - 0.75) < 0.001 and not pd["done"])
	# Cible déjà tombée par un tiers → volet kill accompli → done, best 1.0.
	var pd2: Dictionary = Tracker.progress(double, {
		"owned_count": 3, "target_alive": false, "target_name": "VULTURE"})
	assert(pd2["done"] and float(pd2["best_ratio"]) == 1.0)
	assert(pd2["lines"][0]["done"])  # volet kill (1.0) remonte en tête
	print("[OK] objectif DOUBLE : 2 volets, tri, OU, cible tombée (5 asserts)")

	# 5) Smoke HUD : jauge construite et peuplée dans l'arène réelle.
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var hud = arena.get_node("HUD")
	hud.set_objective_progress(pd, "desc")
	assert(hud._objective_tracker != null and hud._objective_tracker.visible)
	assert(hud._objective_tracker.get_child_count() >= 2)  # 2 barres + séparateur OU
	hud.set_objective_progress({})
	assert(not hud._objective_tracker.visible)
	print("[OK] HUD : tracker construit + masquable (3 asserts)")

	print("[OK] TEST E6 OBJECTIVE : 14 asserts verts")
	get_tree().quit(0)
