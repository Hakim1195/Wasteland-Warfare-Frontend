extends Node

# =================================================================================================
# SONDE §8.152 — LOT 3D-H, ÉTAPE 1 : LA VISÉE ET L'ÉTAT POUSSÉ AU RIG
#
# ⚠️ Cette sonde ne monte PAS le rig 3D : elle vérifie le CONTRAT entre le duel et lui, avant que
# quoi que ce soit ne soit rebranché. C'est l'étape la plus sûre de la migration — personne
# n'appelle encore `_rig_state()`, donc aucune régression n'est possible — et c'est justement pour
# ça qu'il faut la verrouiller MAINTENANT : une erreur d'unité posée ici ne se verrait qu'à travers
# trois couches d'animation.
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_vue3d_etat.tscn
#             --quit-after 900
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. les angles sont pousses en DEGRES au lieu de radians       -> H2
#  2. `cycle_time` est un bareme en dur au lieu du registre      -> H3
#  3. `_reload_seconds` prend une valeur de repli plausible      -> H4
#  4. le clic droit revient sur la grenade                       -> H5
#  5. la bascule de visee perd son front montant                 -> H1
#  6. la visee survit a la grenade ou a la fin de match          -> H1
# =================================================================================================

const DuelScript := preload("res://scripts/game/trench_fp.gd")
const TuningScript := preload("res://scripts/game/trench_tuning.gd")
const Weapons := preload("res://scripts/game/trench_weapons3d.gd")

const CHECKS_ATTENDUS := 5

# Un registre serveur PLAUSIBLE, au contrat courant (20 Hz, §8.141.2). ⚠️ Les valeurs sont celles
# de la simulation : `reload_ticks` 30/40/44/50 et des cadences distinctes par arme.
const RULES := {
	"tick_rate_hz": 20,
	"weapons": [
		{"id": "vipere", "cooldown_ticks": 6, "reload_ticks": 30, "mag_size": 12,
			"dispersion_deg": 1.4},
		{"id": "frelon", "cooldown_ticks": 3, "reload_ticks": 40, "mag_size": 30,
			"dispersion_deg": 2.1},
		{"id": "chacal", "cooldown_ticks": 5, "reload_ticks": 44, "mag_size": 30,
			"dispersion_deg": 1.1},
		{"id": "condor", "cooldown_ticks": 22, "reload_ticks": 50, "mag_size": 5,
			"dispersion_deg": 0.35, "laser_lead_ticks": 10},
	],
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


# ⚠️ On instancie le SCRIPT seul, pas la scène : monter tout le duel demanderait un serveur, des
# autoloads et une fenêtre. Ce qu'on éprouve ici est de l'arithmétique et de la logique d'entrée —
# elles n'ont besoin d'aucun de ces trois.
func _duel():
	var d = DuelScript.new()
	d._rules = RULES
	d._tick_rate = float(RULES["tick_rate_hz"])
	return d


func _ready() -> void:
	print("\n=== SONDE 8.152 — LOT 3D-H ETAPE 1 : L'ETAT POUSSE AU RIG ===\n")
	_probe_bascule()
	_probe_unites()
	_probe_cadence()
	_probe_rechargement()
	_probe_grenade()

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
# H1. ⭐ LA VISÉE : MAINTIEN, BASCULE, ET LES DEUX INTERDITS
# =================================================================================================
# ⚠️ On ne peut pas presser un bouton depuis une sonde headless. On éprouve donc la LOGIQUE en
# posant directement l'entrée simulée — ce qui est exactement la partie qui peut être fausse : le
# front montant, et les deux cas où la visée doit s'éteindre quoi qu'il arrive.
#
# 🩸 Le front montant n'est pas un détail : sans le souvenir de l'image précédente, un bouton MAINTENU
# basculerait soixante fois par seconde et la visée clignoterait. C'est un défaut qui ne se voit
# qu'en jouant, et qui n'a aucune trace dans le code.
func _probe_bascule() -> void:
	var d = _duel()
	var fautes := []

	# --- MAINTIEN (le défaut) : la visée SUIT le bouton, sans mémoire.
	d._ads_toggle = false
	for tenu in [true, true, false, false, true]:
		_simuler_ads(d, tenu)
		if d._ads_active != tenu:
			fautes.append("maintien : bouton %s -> visee %s" % [str(tenu), str(d._ads_active)])

	# --- BASCULE : seul un FRONT MONTANT change l'état.
	d._ads_toggle = true
	d._ads_active = false
	d._ads_held_prev = false
	var entrees := [true, true, true, false, false, true]
	var etats := [true, true, true, true, true, false]
	for i in entrees.size():
		_simuler_ads(d, bool(entrees[i]))
		if d._ads_active != bool(etats[i]):
			fautes.append("bascule pas %d : entree %s -> visee %s (attendu %s)"
				% [i, str(entrees[i]), str(d._ads_active), str(etats[i])])

	# --- LES DEUX INTERDITS.
	d._ads_toggle = false
	_simuler_ads(d, true)
	d._aiming_grenade = true
	_simuler_ads(d, true)
	var coupe_grenade: bool = not d._ads_active
	d._aiming_grenade = false
	_simuler_ads(d, true)
	d._match_over = true
	_simuler_ads(d, true)
	var coupe_fin: bool = not d._ads_active

	_ok("H1 la visee suit le maintien, bascule sur FRONT montant, et cede a la grenade et a la fin",
		fautes.is_empty() and coupe_grenade and coupe_fin,
		"fautes : %s · coupee par la grenade : %s · par la fin de match : %s"
			% [str(fautes.slice(0, 2)), str(coupe_grenade), str(coupe_fin)])
	d.free()


# ⚠️ APPELLE LE VRAI CODE. Première version : cette fonction **reproduisait** la logique de
# décision, faute de pouvoir presser un bouton en headless. 🩸 Le sabotage qui supprimait les deux
# interdits la laissait donc VERTE — elle éprouvait sa propre copie, pas la production.
# `trench_fp.gd` a été scindé pour ça : `_update_ads()` LIT le bouton, `_apply_ads(held)` DÉCIDE.
# **Une décision qu'on ne peut pas appeler depuis un test doit être séparée de son entrée.**
func _simuler_ads(d, tenu: bool) -> void:
	d._apply_ads(tenu)


# =================================================================================================
# H2. ⭐⭐ LES ANGLES SONT POUSSÉS EN RADIANS
# =================================================================================================
# 🩸 LE PIÈGE D'UNITÉS DU LOT. `_aim_yaw` et `_aim_pitch` sont en **DEGRÉS** (la sensibilité est en
# « degrés de visée par pixel », le site est borné à 14). Le rig, lui, dérive une vitesse angulaire
# avec `wrap_pi` : il attend des **RADIANS**.
#
# Pousser les degrés tels quels donnerait une vitesse **57 fois trop grande**, écrêtée à ±9 rad/s :
# la couche de traîne serait saturée en permanence, l'arme resterait collée en butée, et **rien
# n'aurait l'air cassé** — juste « bizarre ». Aucune compilation n'attrape ça.
func _probe_unites() -> void:
	var d = _duel()
	d._aim_yaw = 12.0
	d._aim_pitch = -7.5
	d._rig_weapon = "chacal"
	var s: Dictionary = d._rig_state()
	var yaw := float(s["yaw"])
	var pitch := float(s["pitch"])
	# Contrôle à deux faces : la valeur doit être celle du radian ET ne doit PAS être celle du degré.
	# Une seule des deux serait satisfaite par un `0.0` constant.
	var juste := absf(yaw - deg_to_rad(12.0)) < 1e-9 and absf(pitch - deg_to_rad(-7.5)) < 1e-9
	var pas_des_degres := absf(yaw - 12.0) > 1e-6
	_ok("H2 les angles sont pousses en RADIANS, pas en degres",
		juste and pas_des_degres,
		"yaw %.6f rad (attendu %.6f, degre %.1f) · pitch %.6f rad"
			% [yaw, deg_to_rad(12.0), 12.0, pitch])
	d.free()


# =================================================================================================
# H3. ⭐⭐ LA CADENCE VIENT DU REGISTRE SERVEUR, ARME PAR ARME
# =================================================================================================
# ⛔ `cycle_time` est une CADENCE, donc une RÈGLE. La référence lit `60 / def.rpm` dans son registre
# de VUE ; chez nous elle traverse la frontière comme entrée, jamais comme champ de vue.
# Contrôle à deux faces : la valeur doit suivre le registre **et** DIFFÉRER d'une arme à l'autre —
# un accesseur qui rendrait une constante passerait la première face sans rien prouver.
func _probe_cadence() -> void:
	var d = _duel()
	var fautes := []
	var vues := {}
	for w in RULES["weapons"]:
		var id: String = str((w as Dictionary)["id"])
		d._rig_weapon = id
		var got := float((d._rig_state() as Dictionary)["cycle_time"])
		var attendu := float((w as Dictionary)["cooldown_ticks"]) / float(RULES["tick_rate_hz"])
		vues[id] = got
		if absf(got - attendu) > 1e-9:
			fautes.append("%s : %.4f s (registre %.4f)" % [id, got, attendu])
	# Une arme ABSENTE du registre doit rendre 0 — une valeur qui se remarque, pas une durée
	# plausible qui se fondrait dans le décor.
	d._rig_weapon = "arme_inconnue"
	var muet: bool = absf(float((d._rig_state() as Dictionary)["cycle_time"])) < 1e-12
	var distinctes := {}
	for k in vues:
		distinctes[vues[k]] = true
	_ok("H3 la cadence vient du registre, differe par arme, et vaut 0 si le registre est muet",
		fautes.is_empty() and distinctes.size() >= 3 and muet,
		"fautes : %s · %d cadences distinctes · registre muet -> 0 : %s"
			% [str(fautes), distinctes.size(), str(muet)])
	d.free()


# =================================================================================================
# H4. ⭐⭐ LA DURÉE DE RECHARGEMENT VIENT DU REGISTRE, ET SON REPLI EST ZÉRO
# =================================================================================================
# 🩸 La référence écrit `def.reloadTac ?? 2.15`. Recopié tel quel, ça donnerait 2,15 s d'animation
# pour une VIPÈRE que le serveur recharge en **1,50 s** : la main reviendrait au garde-main 0,65 s
# APRÈS l'autorisation de tirer. C'est le patron exact du §8.148 — une seconde source de vérité qui
# diverge en silence, du seul côté que le joueur voit.
#
# ⚠️ Le repli DOIT être 0 et pas une durée plausible : **un zéro se remarque, un 2,15 se fond dans
# le décor.** L'appelant doit traiter le registre muet comme « je ne sais pas encore ».
func _probe_rechargement() -> void:
	var d = _duel()
	var fautes := []
	for w in RULES["weapons"]:
		var id: String = str((w as Dictionary)["id"])
		var got := float(d._reload_seconds(id))
		var attendu := float((w as Dictionary)["reload_ticks"]) / float(RULES["tick_rate_hz"])
		if absf(got - attendu) > 1e-9:
			fautes.append("%s : %.4f s (registre %.4f)" % [id, got, attendu])
	var muet: bool = absf(float(d._reload_seconds("arme_inconnue"))) < 1e-12
	# Et le cas qui compte vraiment : registre VIDE, comme dans `_ready()` avant `_on_init`.
	var d2 = DuelScript.new()
	var vide: bool = absf(float(d2._reload_seconds("chacal"))) < 1e-12
	_ok("H4 la duree de rechargement suit le registre (1,50 a 2,50 s) et son repli est ZERO",
		fautes.is_empty() and muet and vide,
		"fautes : %s · arme inconnue -> 0 : %s · registre VIDE -> 0 : %s"
			% [str(fautes), str(muet), str(vide)])
	d.free()
	d2.free()


# =================================================================================================
# H5. ⭐ LE CLIC DROIT A QUITTÉ LA GRENADE
# =================================================================================================
# La grenade garde `KEY_G` et la manette ; le clic droit est libéré pour la visée. ⚠️ Ce contrôle
# lit la SOURCE, pas le comportement — c'est le seul moyen d'éprouver un câblage de bouton sans
# fenêtre. Il est donc **complémentaire** de H1, qui éprouve l'algorithme : ni l'un ni l'autre ne
# suffit seul.
# ⚠️ On lit la source en la découpant à la fonction, pas en cherchant une sous-chaîne dans tout le
# fichier : le fichier PARLE du clic droit dans plusieurs pavés (leçon §8.145 — le grep compte les
# commentaires), et un contrôle qui les compterait serait rouge à jamais.
func _probe_grenade() -> void:
	var f := FileAccess.open("res://scripts/game/trench_fp.gd", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	var i := src.find("func _update_grenade_aim(")
	var j := src.find("\nfunc ", i + 10)
	var corps := src.substr(i, j - i) if i >= 0 and j > i else ""
	# On retire les commentaires AVANT de chercher : c'est la leçon §8.145, appliquée.
	var code := ""
	for ligne in corps.split("\n"):
		var l: String = ligne.strip_edges()
		if not l.begins_with("#"):
			code += l + "\n"
	var k := src.find("func _update_ads(")
	var k2 := src.find("\nfunc ", k + 10)
	var corps_ads := src.substr(k, k2 - k) if k >= 0 and k2 > k else ""
	_ok("H5 le clic droit a quitte la grenade (qui garde G) et sert desormais a la visee",
		i >= 0 and k >= 0 and not code.contains("MOUSE_BUTTON_RIGHT")
			and code.contains("KEY_G") and corps_ads.contains("MOUSE_BUTTON_RIGHT"),
		"grenade : clic droit %s · G %s | visee : clic droit %s"
			% [str(code.contains("MOUSE_BUTTON_RIGHT")), str(code.contains("KEY_G")),
				str(corps_ads.contains("MOUSE_BUTTON_RIGHT"))])
