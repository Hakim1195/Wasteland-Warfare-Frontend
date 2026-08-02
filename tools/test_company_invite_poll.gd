extends Node

# CONTRE-ÉPREUVE CLIENT — POLL DE L'INVITATION DE COMPAGNIE (finitions pré-playtest)
#   & <godot_console> --headless --path frontend res://tools/test_company_invite_poll.tscn
#
# Les deux contre-épreuves du brief qui portent sur la BARRE DE NAVIGATION (les quatre autres, côté
# serveur, vivent dans `backend/test_company_flow.py::test_company_invite`) :
#   (a) le timer ne se DOUBLE pas quand on change d'écran — 4 requêtes / 60 s, jamais 8 ;
#   (b) AUCUN poll en arène.

const TopNav := preload("res://scripts/ui/top_nav.gd")

func _count_timers(nav) -> int:
	var n := 0
	for c in nav.get_children():
		if c is Timer:
			n += 1
	return n


func _ready() -> void:
	var checks := 0

	# --- (a) UN SEUL TIMER, ET IL MEURT AVEC SON ÉCRAN ------------------------------------------
	var nav1 := Control.new()
	nav1.set_script(TopNav)
	add_child(nav1)
	await get_tree().process_frame
	assert(_count_timers(nav1) == 1)
	# Un second appel ne doit pas empiler un timer de plus (garde de `_start_invite_poll`).
	nav1._start_invite_poll()
	assert(_count_timers(nav1) == 1)
	checks += 2

	# CHANGEMENT D'ÉCRAN : chaque écran hub monte SA `top_nav`. Le timer étant son ENFANT, il part
	# avec elle — c'est ce qui empêche l'accumulation redoutée (5 écrans visités ≠ 5 sondages).
	var nav2 := Control.new()
	nav2.set_script(TopNav)
	add_child(nav2)
	await get_tree().process_frame
	nav1.queue_free()                       # l'écran précédent est libéré par TransitionManager
	await get_tree().process_frame
	await get_tree().process_frame
	var live := 0
	for n in [nav1, nav2]:
		if is_instance_valid(n):
			live += _count_timers(n)
	assert(live == 1)                       # UN seul timer vivant après la navigation
	checks += 1

	# CADENCE : 15 s → 4 requêtes par minute. C'est le chiffre du brief (« 4, pas 8 »).
	assert(int(round(60.0 / TopNav.INVITE_POLL_S)) == 4)
	assert(nav2._invite_timer.wait_time == TopNav.INVITE_POLL_S)
	checks += 2
	print("[OK] Un seul timer, il meurt avec son ecran, cadence 4/min (5 asserts)")

	# --- (b) AUCUN POLL EN ARÈNE ----------------------------------------------------------------
	# L'arène ne monte PAS de barre de navigation : il ne peut donc y partir aucun sondage. On le
	# VÉRIFIE sur la scène réelle plutôt que de le supposer — c'est une propriété qu'un futur ajout
	# de HUD pourrait casser sans que personne n'y pense.
	nav2.queue_free()
	await get_tree().process_frame
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	var navs := 0
	var stack: Array = [arena]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_script() == TopNav:
			navs += 1
		for c in node.get_children():
			stack.append(c)
	assert(navs == 0)
	checks += 1
	print("[OK] Arene : aucune top_nav montee -> aucun poll pendant un match (1 assert)")

	print("[OK] TEST COMPANY INVITE POLL : %d asserts verts" % checks)
	get_tree().quit(0)
