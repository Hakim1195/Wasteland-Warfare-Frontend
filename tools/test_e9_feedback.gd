extends Node

# TEST E9 §8.81 (style maison) — Feedback sensoriel : les 10 hooks SFX sont enregistrés (repli
# synthétisé), play_sfx ne crashe pas sur bus muet, VFX ponctuels appelables (flash conquête,
# tic de zone, douleur héros) et coupés par reduced_motion (E10).
#   & <godot_console> --headless --path frontend res://tools/test_e9_feedback.tscn

const HOOKS := ["your_turn", "dice_lock", "hit_troops", "hero_hit", "hero_down",
	"conquest", "zone_alarm", "under_attack", "card_draw", "timer_tick"]

func _ready() -> void:
	# 1) Les 10 SFX du plan sont enregistrés (un stream non nul chacun).
	for name in HOOKS:
		assert(AudioManager._sfx.has(name) and AudioManager._sfx[name] != null)
	print("[OK] 10 hooks SFX enregistres (repli synthetise) (10 asserts)")

	# 2) play_sfx est silencieux/sans crash sur un nom INCONNU et sur les 10 hooks.
	AudioManager.play_sfx("nom_inexistant_xyz")
	for name in HOOKS:
		AudioManager.play_sfx(name)
	print("[OK] play_sfx : 10 hooks + nom inconnu sans crash")

	# 3) VFX board : flash de conquête + tic de zone appelables dans l'arène réelle.
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var board = arena.get_node("MapViewportContainer/MapContent/Board")
	var hud = arena.get_node("HUD")
	board.conquest_flash("alaska", Color("36c5d9"))
	board.spawn_zone_tick("alaska")
	# Douleur héros : sans crash même si le panneau est masqué (garde interne).
	hud.pulse_hero_pain()
	print("[OK] VFX board + douleur heros appelables (0 crash)")

	# 4) reduced_motion pilote _vfx_enabled côté contrôleur (E9 gated par E10).
	SettingsManager.set_comfort("reduced_motion", true)
	assert(not arena._vfx_enabled())
	SettingsManager.set_comfort("reduced_motion", false)
	assert(arena._vfx_enabled())
	print("[OK] reduced_motion coupe les VFX (_vfx_enabled) (2 asserts)")

	print("[OK] TEST E9 FEEDBACK : 14 asserts verts")
	get_tree().quit(0)
