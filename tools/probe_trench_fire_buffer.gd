extends Node

# =================================================================================================
# SONDE §8.152.1 — LE TAMPON DE TIR ET LE RAYON PRÉDIT
#
# ╔═ CE QU'ELLE GARDE, ET POURQUOI CE N'EST PAS DU CONFORT ══════════════════════════════════════╗
# ║ Verdict de partie réelle : « la latence entre le clic et le tir effectif, et des fois ça tire  ║
# ║ même pas ». Le correctif touche à ce qui part vraiment quand le joueur clique — c'est donc du   ║
# ║ JEU, pas de la présentation, et ça se garde comme tel.                                         ║
# ║                                                                                                ║
# ║ ⛔ L'INVARIANT ABSOLU : **le tampon ne fait JAMAIS tirer plus tôt que la règle.** Il ne fait   ║
# ║ que déplacer un clic PERDU au premier instant où il est LÉGAL. S'il pouvait devancer la        ║
# ║ cadence, ce serait une triche côté client, et le refus prédit du §8.141.9 ne servirait plus    ║
# ║ à rien.                                                                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_trench_fire_buffer.tscn
#             --quit-after 900
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. le tampon vide sans repasser par les six refus     -> B2 (il devancerait la cadence)
#  2. le tampon n'est plus consomme apres usage          -> B3 (un clic armerait tous les tirs)
#  3. le tampon n'expire jamais                          -> B4
#  4. tous les refus sont memorises, pas seulement la cadence -> B5
#  5. le rayon predit n'est plus pose au clic            -> B6
#  6. le rayon predit n'expire jamais                    -> B6
# =================================================================================================

const DuelScript := preload("res://scripts/game/trench_fp.gd")

const CHECKS_ATTENDUS := 6

# Le registre du CONDOR, tel que le serveur le diffuse : 22 ticks de cadence à 20 Hz = 1,10 s, et
# 10 ticks de télégraphe = 0,50 s. Ce sont ces deux nombres qui produisent le défaut ressenti.
const RULES := {
	"tick_rate_hz": 20,
	"weapons": [{"id": "condor", "cooldown_ticks": 22, "reload_ticks": 50, "mag_size": 5,
		"dispersion_deg": 0.35, "laser_lead_ticks": 10, "flight_ticks": 1, "burst": 1}],
}

var _fails: Array = []
var _joues := 0


func _ok(nom: String, cond: bool, detail := "") -> void:
	_joues += 1
	if cond:
		print("  [OK]   %s   | %s" % [nom, detail])
	else:
		_fails.append(nom)
		print("  [ROUGE] %s   | %s" % [nom, detail])


# Un duel en état de TIRER : phase jouante, debout, chargeur plein, aucune minuterie en cours.
# ⚠️ On monte le script seul — l'état vient d'un tampon injecté, pas d'un serveur. Ce qu'on éprouve
# est une machine à états d'entrée ; elle n'a besoin ni de réseau ni de fenêtre.
func _duel():
	var d = DuelScript.new()
	d._rules = RULES
	d._tick_rate = 20.0
	d._my_slot = 1
	d._buffer = [{"data": {
		"phase": "playing", "tick": 0,
		"players": [{"slot": 1, "pos": 2, "hp": 100, "ammo": 5, "weapon": "condor",
			"reload_until_tick": 0, "bandage_until_tick": 0}],
	}}]
	d._pred_stance = "up"
	# ⚠️ `_ui_blocks_actions()` lit `_abandon_overlay.visible` et `_choice_panel.visible` — deux
	# `Control` qui n'existent que dans la scène montée. On les fournit VIDES plutôt que de
	# rendre la garde tolérante au `null` : une porte de sécurité qui accepte l'absence de ses
	# battants n'est plus une porte, et ce fichier en dépend pour six actions.
	d._abandon_overlay = Control.new()
	d._choice_panel = PanelContainer.new()
	d._abandon_overlay.visible = false
	d._choice_panel.visible = false
	d._clock = 100.0
	d._pred_fire_ready = 0.0
	return d


func _ready() -> void:
	print("\n=== SONDE 8.152.1 — LE TAMPON DE TIR DU CONDOR ===\n")
	_probe_clic_perdu()
	_probe_jamais_plus_tot()
	_probe_consomme_une_fois()
	_probe_expire()
	_probe_seule_la_cadence()
	_probe_rayon_predit()

	print("")
	if _joues != CHECKS_ATTENDUS:
		print("INCOMPLETE : %d controles joues, %d attendus" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(1)
	elif _fails.is_empty():
		print("TOUT VERT (%d/%d controles joues)" % [_joues, CHECKS_ATTENDUS])
		get_tree().quit(0)
	else:
		print("ECHEC : %d rouge(s) sur %d joues -> %s" % [_fails.size(), _joues, str(_fails)])
		get_tree().quit(1)


# =================================================================================================
# B1. ⭐⭐ LE CLIC ANTICIPÉ N'EST PLUS PERDU
# =================================================================================================
# 🩸 LE DÉFAUT SIGNALÉ. Avant, un clic arrivé pendant les 1,10 s de cadence du condor était **jeté**
# avec un clac de refus. Un joueur qui anticipe de 150 ms — ce que fait tout le monde sur une arme
# lente — perdait son tir et devait recliquer.
func _probe_clic_perdu() -> void:
	var d = _duel()
	# La cadence se referme dans 0,15 s : le joueur clique juste avant.
	d._pred_fire_ready = d._clock + 0.15
	d._queue_fire()
	var jete_avant: bool = not d._fire_queued
	var memorise: bool = d._fire_buffer_until > d._clock
	# Le temps passe jusqu'à l'ouverture de la porte.
	d._clock += 0.16
	d._vider_tampon_de_tir()
	_ok("B1 le clic anticipe de 150 ms n'est plus perdu : il part des que la cadence s'ouvre",
		jete_avant and memorise and d._fire_queued,
		"refuse sur le coup : %s · memorise : %s · parti a l'ouverture : %s"
			% [str(jete_avant), str(memorise), str(d._fire_queued)])
	d.free()


# =================================================================================================
# B2. ⭐⭐⭐ LE TAMPON NE DEVANCE JAMAIS LA RÈGLE — L'INVARIANT
# =================================================================================================
# ⛔ C'est le contrôle qui compte. Si le tampon pouvait tirer avant `_pred_fire_ready`, il
# deviendrait une triche côté client : le joueur obtiendrait une cadence plus rapide que le
# registre, et le refus prédit du §8.141.9 ne servirait plus à rien.
# On balaie TOUTE la fenêtre de cadence, pas seulement sa fin : un tampon qui ne mordrait qu'au
# dernier instant passerait un contrôle ponctuel sans rien prouver.
func _probe_jamais_plus_tot() -> void:
	var d = _duel()
	var cadence := 22.0 / 20.0
	d._pred_fire_ready = d._clock + cadence
	d._queue_fire()                       # refusé, mémorisé
	var premature := ""
	var pas := 0
	# 60 pas de 20 ms couvrent 1,20 s, soit plus que la cadence entière.
	for i in 60:
		d._clock += 0.02
		pas += 1
		d._vider_tampon_de_tir()
		if d._fire_queued and d._clock < d._pred_fire_ready:
			premature = "tir au pas %d, %.3f s AVANT la porte" % [pas,
				d._pred_fire_ready - d._clock]
			break
	_ok("B2 le tampon ne fait JAMAIS partir un tir avant la porte de cadence",
		premature == "", "cadence %.3f s balayee en 60 pas · %s"
			% [cadence, premature if premature != "" else "aucun tir premature"])
	d.free()


# =================================================================================================
# B3. ⭐ UN CLIC = UN TIR
# =================================================================================================
# ⚠️ Si le tampon n'était pas vidé après usage, un seul clic anticipé armerait tous les tirs de la
# fenêtre suivante — c'est-à-dire que le jeu tirerait à la place du joueur. C'est le défaut
# symétrique de celui qu'on corrige, et il serait bien pire.
func _probe_consomme_une_fois() -> void:
	var d = _duel()
	d._pred_fire_ready = d._clock + 0.10
	d._queue_fire()
	d._clock += 0.11
	d._vider_tampon_de_tir()
	var premier: bool = d._fire_queued
	# Le message part : le duel remet son drapeau, la porte se referme sur la cadence suivante.
	d._fire_queued = false
	d._pred_fire_ready = d._clock + 1.10
	var reste: float = d._fire_buffer_until
	d._clock += 1.20
	d._vider_tampon_de_tir()
	_ok("B3 un clic anticipe donne UN tir, pas toute la rafale suivante",
		premier and not d._fire_queued and reste == 0.0,
		"premier tir : %s · tampon apres usage : %.3f · second tir fantome : %s"
			% [str(premier), reste, str(d._fire_queued)])
	d.free()


# =================================================================================================
# B4. LE TAMPON EXPIRE
# =================================================================================================
# Un clic une seconde trop tôt n'est plus une anticipation : c'est un autre geste. L'honorer
# reviendrait à tirer sur une intention périmée.
func _probe_expire() -> void:
	var d = _duel()
	d._pred_fire_ready = d._clock + 1.10
	d._queue_fire()
	var memorise: bool = d._fire_buffer_until > 0.0
	d._clock += DuelScript.FIRE_BUFFER + 0.05
	d._vider_tampon_de_tir()
	var oublie: bool = d._fire_buffer_until == 0.0
	# Et la porte s'ouvre bien plus tard : rien ne doit partir.
	d._clock += 1.20
	d._vider_tampon_de_tir()
	_ok("B4 le tampon EXPIRE : un clic trop en avance n'est pas honore une seconde plus tard",
		memorise and oublie and not d._fire_queued,
		"fenetre %.2f s · oublie a l'echeance : %s · tir fantome : %s"
			% [DuelScript.FIRE_BUFFER, str(oublie), str(d._fire_queued)])
	d.free()


# =================================================================================================
# B5. ⭐ SEULE LA CADENCE EST MÉMORISÉE
# =================================================================================================
# ⚠️ La cadence est le seul refus où le joueur a raison sur le FOND et se trompe seulement sur
# l'INSTANT. Un clic pendant un rechargement ou un pansement est un AUTRE geste : le mémoriser
# ferait partir un tir que le joueur ne demande plus.
func _probe_seule_la_cadence() -> void:
	var fautes := []
	for cas in [["reload_until_tick", 999, "rechargement"], ["bandage_until_tick", 999, "pansement"]]:
		var d = _duel()
		var j: Dictionary = (d._buffer[0]["data"]["players"] as Array)[0]
		j[String(cas[0])] = int(cas[1])
		d._pred_fire_ready = 0.0     # la cadence, elle, est ECHUE : le refus vient d'ailleurs
		d._queue_fire()
		if d._fire_buffer_until > 0.0:
			fautes.append("%s memorise a tort" % String(cas[2]))
		d.free()
	# Contre-face : la cadence, elle, DOIT être mémorisée — sinon le contrôle serait satisfait par
	# un tampon qui ne mémorise jamais rien.
	var d2 = _duel()
	d2._pred_fire_ready = d2._clock + 0.5
	d2._queue_fire()
	var cadence_memorisee: bool = d2._fire_buffer_until > 0.0
	d2.free()
	_ok("B5 SEULE la cadence est memorisee (ni rechargement, ni pansement)",
		fautes.is_empty() and cadence_memorisee,
		"fautes : %s · la cadence est bien memorisee : %s" % [str(fautes), str(cadence_memorisee)])


# =================================================================================================
# B6. ⭐⭐ LE RAYON EST RENDU DÈS LE CLIC, ET IL EXPIRE
# =================================================================================================
# 🩸 L'AUTRE MOITIÉ DU DÉFAUT. Le pavé du §8.151-2bis affirmait que « le retour immédiat du clic
# existe déjà : c'est le rayon laser lui-même ». C'était vrai en intention et FAUX en fait : le
# rayon est rendu depuis l'ÉTAT SERVEUR, donc après un aller-retour réseau, par-dessus les 0,5 s
# de télégraphe. Entre le clic et lui : le silence complet.
# ⚠️ On ne rend rien de balistique — la règle « pas de faux coup » tient. On rend le RAYON, qui est
# exactement ce que le clic a produit côté serveur.
func _probe_rayon_predit() -> void:
	var d = _duel()
	d._aim_yaw = 3.5
	d._aim_pitch = -1.25
	d._fire_aim = Vector2(3.5, -1.25)
	d._local_fire_feedback()
	var pose: bool = d._laser_pred_until > d._clock
	var vise_juste: bool = d._laser_pred_aim == Vector2(3.5, -1.25)
	# ⚠️ La fenêtre doit couvrir AU MOINS le télégraphe (0,50 s), sinon le rayon s'éteindrait avant
	# que la balle ne parte — un rayon qui ment sur la fin du danger est pire que pas de rayon.
	var couvre: bool = d._laser_pred_until - d._clock >= 10.0 / 20.0
	# Et il expire : passé la fenêtre, seul l'état serveur parle.
	d._clock += 2.0
	var expire: bool = d._clock >= d._laser_pred_until
	_ok("B6 le rayon est PREDIT des le clic, sur la visee du tir, et il expire",
		pose and vise_juste and couvre and expire,
		"pose : %s · visee %s · couvre le telegraphe : %s · expire : %s"
			% [str(pose), str(d._laser_pred_aim), str(couvre), str(expire)])
	d.free()
