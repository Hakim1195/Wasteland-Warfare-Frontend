extends SceneTree

# Script JETABLE (recette §8.111) — l'alarme est capturée PAR-DESSUS L'ARÈNE : c'est la seule
# façon de vérifier qu'on voit bien le plateau à travers. À SUPPRIMER après usage.

func _initialize() -> void:
	await _run()

func _run() -> void:
	var arena = load("res://scenes/game/main.tscn").instantiate()
	root.add_child(arena)
	await create_timer(1.2).timeout

	var alarm = Control.new()
	alarm.set_script(load("res://scripts/game/coup_alarm.gd"))
	root.add_child(alarm)
	alarm.play(true, "VULTURE-7", "HAKIM")

	# Pic du clignotant (~0,23 s après le début : |sin| culmine à t = 1/(2·2,2) ≈ 0,227 s).
	await create_timer(0.25).timeout
	root.get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_alarm_peak.png"))
	# Creux du clignotant : le plateau doit y être quasi net.
	await create_timer(0.23).timeout
	root.get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_alarm_low.png"))
	# Verdict.
	await create_timer(2.3).timeout
	root.get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_alarm_verdict.png"))
	quit()
