extends Node

# TEST §8.122 LOTS C/D/E (style maison) — carte vivante, cycle de tension et Geiger.
#   & <godot_console> --headless --path frontend res://tools/test_ambient_layer.tscn
#
# Couvre les CRITÈRES DE RECETTE qu'un simple boot ne prouve pas :
#   • budget particules ≤ 500 et ordre de rendu (AmbientFront SOUS les badges) ;
#   • choix de la « capitale » (plus grosse garnison, égalité tranchée alphabétiquement = STABLE) ;
#   • pool de fumées : attribution, vieillissement, purge, recyclage du plus ancien ;
#   • `living_map` OFF / `reduced_motion` ON → tout est éteint (pas seulement invisible) ;
#   • uniforme `war_intensity` réellement poussé au shader du fond de carte ;
#   • distance BFS zone → mes territoires (volume du Geiger).

const AmbientLayer := preload("res://scripts/game/ambient_layer.gd")

# 11 = MOI. alaska/alberta à 5 troupes chacun → ÉGALITÉ : la capitale doit être « alaska »
# (alphabétique), et le rester d'un refresh à l'autre.
const STATE := {
	"stage": "playing", "current_turn": 4, "current_player_id": 11, "phase": 3,
	"turn_order": [11.0, 7.0, 5.0],
	"players": {
		"11": {"username": "HAKIM", "faction": "", "status": "alive",
			"hero_pv_current": 60.0, "hero_pv_max": 100.0},
		"7": {"username": "VULTURE", "faction": "", "status": "alive",
			"hero_pv_current": 30.0, "hero_pv_max": 100.0},
		"5": {"username": "GHOST", "faction": "", "status": "alive",
			"hero_pv_current": 90.0, "hero_pv_max": 100.0},
	},
	"territories": {
		"alaska": {"owner_id": 11.0, "garrison": 5},
		"alberta": {"owner_id": 11.0, "garrison": 5},
		"ontario": {"owner_id": 11.0, "garrison": 2},
		"brazil": {"owner_id": 7.0, "garrison": 9},
		"peru": {"owner_id": 7.0, "garrison": 3},
		"egypt": {"owner_id": 5.0, "garrison": 4},
	},
	"contamination_zone": {"territories": ["kamchatka"]},
}


func _ready() -> void:
	var asserts := 0
	AuthManager.user_id = 11        # perspective du joueur LOCAL (board._local_pid / main._my_id)

	# --- 1) Budget particules : garde-fou de performance chiffré du cahier des charges ----------
	var total: int = AmbientLayer.particle_total()
	assert(total <= AmbientLayer.PARTICLE_BUDGET)
	assert(total == AmbientLayer.ASH_AMOUNT
		+ AmbientLayer.SMOKE_POOL_MAX * AmbientLayer.SMOKE_AMOUNT_FRESH
		+ AmbientLayer.CAMP_MAX * AmbientLayer.CAMP_AMOUNT)
	asserts += 2
	print("[OK] budget particules : %d / %d simultanées (2 asserts)"
		% [total, AmbientLayer.PARTICLE_BUDGET])

	# --- 2) Arène réelle + état ---------------------------------------------------------------
	var arena = load("res://scenes/game/main.tscn").instantiate()
	add_child(arena)
	var board = arena.get_node("MapViewportContainer/MapContent/Board")
	GameState.update_from_json(STATE)
	SettingsManager.set_comfort("reduced_motion", false)
	SettingsManager.set_comfort("living_map", true)
	var amb = board.get_node("AmbientLayer")
	amb.set_enabled(true)
	board.generate_board()
	await get_tree().process_frame

	# --- 3) Ordre de rendu : AmbientBack sous les territoires, AmbientFront sous les badges -----
	var back := board.get_node("AmbientBack") as Node2D
	var front := board.get_node("AmbientFront") as Node2D
	var terr := board.get_node("TerritoriesContainer") as Node2D
	assert(back.get_index() < terr.get_index())          # cendres DERRIÈRE les territoires
	assert(front.z_index == 1)
	assert(board.get_node("BadgeLayer").z_index == 2)    # badges TOUJOURS au-dessus des fumées
	assert(front.z_index < board.get_node("BadgeLayer").z_index)
	asserts += 4
	print("[OK] ordre de rendu : AmbientBack < territoires, AmbientFront(1) < BadgeLayer(2) (4 asserts)")

	# --- 4) Capitales : plus grosse garnison, égalité tranchée ALPHABÉTIQUEMENT (stable) -------
	# 11 : alaska(5) == alberta(5) → alaska. 7 : brazil(9) > peru(3). 5 : egypt seul.
	var camps: Array = []
	for p in amb._camps:
		if p.emitting:
			camps.append(p)
	assert(camps.size() == 3)                            # 3 joueurs vivants = 3 feux de camp
	var alaska_pos: Vector2 = board.get_territory_position("alaska")
	var brazil_pos: Vector2 = board.get_territory_position("brazil")
	var camp_positions: Array = []
	for p in camps:
		camp_positions.append(p.position)
	assert(camp_positions.has(alaska_pos))
	assert(camp_positions.has(brazil_pos))
	assert(not camp_positions.has(board.get_territory_position("alberta")))
	# STABILITÉ : un 2ᵉ refresh sans changement d'état ne doit PAS déplacer les feux.
	board.generate_board()
	await get_tree().process_frame
	assert(amb._camps[0].position == camps[0].position)
	asserts += 5
	print("[OK] capitales : garnison max, égalité alphabétique, ordre STABLE (5 asserts)")

	# --- 5) Fumées de guerre : attribution, vieillissement, purge, recyclage -------------------
	amb.on_conquest("peru", 4)
	assert(amb._smoke_by_tid.has("peru"))
	assert(amb._smoke_pool[int(amb._smoke_by_tid["peru"])].amount == AmbientLayer.SMOKE_AMOUNT_FRESH)
	# Conquête du round PRÉCÉDENT : panache réduit dès qu'une conquête plus récente existe.
	amb.on_conquest("egypt", 3)
	amb._refresh_smoke()
	assert(amb._smoke_pool[int(amb._smoke_by_tid["egypt"])].amount == AmbientLayer.SMOKE_AMOUNT_AGED)
	# Purge par ancienneté : au round 5, la conquête du round 3 a SMOKE_MAX_AGE → elle s'éteint.
	amb._purge_smoke(5)
	assert(not amb._smoke_by_tid.has("egypt"))
	assert(amb._smoke_by_tid.has("peru"))               # round 4 : encore fraîche à l'échelle 5-4=1
	# Recyclage : au-delà du pool, le PLUS ANCIEN est repris — jamais d'allocation neuve.
	var pool_before: int = amb._smoke_pool.size()
	var ids := ["ontario", "brazil", "egypt", "quebec", "greenland", "iceland",
		"ukraine", "china", "india", "siam", "congo"]
	for tid in ids:
		amb.on_conquest(tid, 6)
	assert(amb._smoke_pool.size() == pool_before)       # taille du pool INCHANGÉE
	assert(amb._smoke_by_tid.size() <= AmbientLayer.SMOKE_POOL_MAX)
	assert(not amb._smoke_by_tid.has("peru"))           # la plus ancienne a cédé sa place
	asserts += 8
	print("[OK] fumées : pool borné à %d, vieillissement et recyclage FIFO (8 asserts)"
		% AmbientLayer.SMOKE_POOL_MAX)

	# --- 6) Réglages : living_map OFF et reduced_motion ON coupent TOUT ------------------------
	SettingsManager.set_comfort("living_map", false)
	await get_tree().process_frame
	assert(not front.visible and not back.visible)
	assert(not amb._ash.emitting)
	var any_emitting := false
	for p in amb._camps + amb._smoke_pool:
		any_emitting = any_emitting or p.emitting
	assert(not any_emitting)                            # ÉTEINTS, pas seulement invisibles
	assert(amb._lightning_timer.is_stopped() and amb._birds_timer.is_stopped())
	SettingsManager.set_comfort("living_map", true)
	SettingsManager.set_comfort("reduced_motion", true)
	await get_tree().process_frame
	assert(not front.visible)                           # reduced_motion FORCE l'extinction…
	assert(bool(SettingsManager.get_comfort("living_map")))  # …sans écraser le choix du joueur
	SettingsManager.set_comfort("reduced_motion", false)
	asserts += 6
	print("[OK] living_map OFF / reduced_motion ON : émetteurs coupés, choix préservé (6 asserts)")

	# --- 7) LOT E : l'uniforme `war_intensity` atteint VRAIMENT le shader du fond de carte ------
	var bg = board.get_node("BoardBackground")
	assert(bg.material is ShaderMaterial)
	board.set_war_intensity(0.73)
	assert(absf(float((bg.material as ShaderMaterial)
		.get_shader_parameter("war_intensity")) - 0.73) < 0.001)
	# Clamp : aucune valeur hors [0,1] ne peut franchir les plafonds du shader.
	board.set_war_intensity(4.0)
	assert(is_equal_approx(float((bg.material as ShaderMaterial)
		.get_shader_parameter("war_intensity")), 1.0))
	board.set_war_intensity(0.0)
	asserts += 3
	print("[OK] uniforme war_intensity poussé au shader + clampé (3 asserts)")

	# --- 8) LOT C : distance BFS zone → mes territoires (volume du Geiger) ---------------------
	# alaska est À MOI et voisine de kamchatka (zone) → 1 saut.
	assert(arena._zone_distance_to_me() == 1)
	_set_zone(["alaska"])
	assert(arena._zone_distance_to_me() == 0)           # la zone est CHEZ MOI
	_set_zone(["japan"])                                # japan → kamchatka → alaska
	assert(arena._zone_distance_to_me() == 2)
	_set_zone(["argentina"])                            # hors de portée du dernier palier
	assert(arena._zone_distance_to_me() == -1)
	_set_zone([])
	assert(arena._zone_distance_to_me() == -1)          # zone vide → Geiger muet
	asserts += 5
	print("[OK] Geiger : distance BFS 0/1/2 puis coupure hors portée (5 asserts)")

	print("[OK] TEST AMBIENT LAYER (§8.122 LOTS C/D/E) : %d asserts verts" % asserts)
	get_tree().quit(0)


func _set_zone(tids: Array) -> void:
	GameState.contamination_zone = {"territories": tids}
