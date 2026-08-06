extends Node

# =================================================================================================
# SONDE §8.141.9 — LE « FAUX COUP » : un clic montre-t-il TOUJOURS une balle qui part vraiment ?
#
# ⚠️ On CLIQUE au rythme d'un joueur énervé (toutes les 100 ms) et on compte : combien de retours
# d'arme JOUÉS localement, contre combien de tirs que le SERVEUR aurait réellement acceptés.
# Le second est calculé avec la MÊME règle que `trench_sim.step` — c'est le juge, pas le client.

const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")

var _fails: Array = []


func _ok(label: String, cond: bool, detail := "") -> void:
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _ready() -> void:
	DuelScript.pending_room_id = "999"
	var duel = DuelScene.instantiate()
	add_child(duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(duel._on_connection_lost)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	duel.set_process(false)
	duel._rules = _rules()
	duel._tick_rate = 20.0
	_push(duel, 8, "up")
	duel._refresh_view(0.016)

	print("=== LE FAUX COUP : 40 clics au rythme de 10/s, VIPÈRE (cadence 0,90 s) ===")
	var seen := 0
	var cadence: float = 18.0 / 20.0
	var next_real := 0.0
	var real := 0
	for i in range(40):
		duel._clock = float(i) * 0.10
		duel._fire_queued = false
		var before: int = duel._world._local_tracers.size()
		duel._queue_fire()
		if duel._world._local_tracers.size() > before:
			seen += 1
		# LE JUGE : la règle du serveur, appliquée à la main.
		if duel._clock >= next_real:
			real += 1
			next_real = duel._clock + cadence
		duel._world._advance_local_tracers(0.10)
	print("  retours d'arme JOUÉS : %d" % seen)
	print("  tirs RÉELS (règle serveur) : %d" % real)
	_ok("un clic joué = un tir réel (aucun faux coup)", seen == real,
		"%d joués pour %d réels" % [seen, real])

	# --- ACCROUPI : le serveur refuse, le client doit refuser aussi -----------------------------
	duel._pred_stance = "down"
	duel._clock += 10.0
	duel._fire_queued = false
	var before2: int = duel._world._local_tracers.size()
	duel._queue_fire()
	_ok("ACCROUPI : aucun retour d'arme, et le tir n'est meme pas envoye",
		duel._world._local_tracers.size() == before2 and not duel._fire_queued)
	duel._pred_stance = "up"

	# --- RECHARGEMENT ---------------------------------------------------------------------------
	_push(duel, 8, "up", 999)
	duel._refresh_view(0.016)
	duel._clock += 10.0
	duel._fire_queued = false
	var before3: int = duel._world._local_tracers.size()
	duel._queue_fire()
	_ok("RECHARGEMENT : aucun retour d'arme",
		duel._world._local_tracers.size() == before3 and not duel._fire_queued)

	# --- CHARGEUR VIDE : le clic DOIT partir (il declenche le rechargement) ----------------------
	_push(duel, 0, "up")
	duel._refresh_view(0.016)
	duel._clock += 10.0
	duel._fire_queued = false
	var before4: int = duel._world._local_tracers.size()
	duel._queue_fire()
	_ok("CHARGEUR VIDE : aucune tracante, mais le clic PART (il declenche le rechargement)",
		duel._world._local_tracers.size() == before4 and duel._fire_queued)

	print("\n%s" % ("TOUT VERT" if _fails.is_empty() else "ECHEC : " + ", ".join(_fails)))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _rules() -> Dictionary:
	return {"tick_rate_hz": 20, "positions": 5, "hp_max": 100, "move_ticks": 10,
		"weapons": [{"id": "vipere", "burst": 1, "cooldown_ticks": 18, "flight_ticks": 1,
			"laser_lead_ticks": 0, "dispersion_deg": 0.30, "mag_size": 8, "reload_ticks": 30}]}


func _push(duel, ammo: int, stance: String, reload_until := 0) -> void:
	duel._on_state({"type": "trench_state", "tick": 100, "phase": "playing", "round_no": 1,
		"round_start_tick": 0, "round_ticks": 1800, "score": [0, 0], "winner_slot": 0,
		"players": [
			{"slot": 1, "pos": 2, "stance": stance, "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": ammo, "bandages": 1, "aiming": true, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0,
				"reload_until_tick": reload_until, "bandage_until_tick": 0, "disconnected": false},
			{"slot": 2, "pos": 2, "stance": "up", "hp": 100, "weapon": "vipere", "hits_total": 0,
				"grenades": 2, "ammo": 8, "bandages": 1, "aiming": true, "hidden": false,
				"choice_deadline_tick": 0, "laser_fire_tick": 0, "reload_until_tick": 0,
				"bandage_until_tick": 0, "disconnected": false}],
		"projectiles": [], "events": []})
