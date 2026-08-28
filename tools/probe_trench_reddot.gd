extends Node

# =================================================================================================
# SONDE §8.152.12 — LE POINT ROUGE EN VISÉE (lot 3D-I, option C validée par Hakim)
#
# ╔═ CE QU'ELLE GARDE ═══════════════════════════════════════════════════════════════════════════╗
# ║ Le rig RÉSOUT la pose de visée : il pose le point de visée de l'arme exactement sur l'axe de   ║
# ║ la caméra (contrôle V3 : < 1 mm sur les quatre armes). Et le réticule du HUD est déjà placé là ║
# ║ où part la balle. Les deux tombent au MÊME PIXEL par construction — c'est ce qui permet le     ║
# ║ point dans le verre **sans qu'un seul pixel ne mente**.                                        ║
# ║                                                                                                ║
# ║ ⛔ Ce n'est PAS le réticule collimaté de la référence, qui n'a pas été porté : le leur est      ║
# ║ accroché au RIG et suivrait le balancement que le tir ne suit pas. Celui-ci est accroché à la  ║
# ║ vérité serveur.                                                                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Lancement : <godot_console> --headless --path frontend res://tools/probe_trench_reddot.tscn
#             --quit-after 900
#
# ── SABOTAGES QUI DOIVENT LA FAIRE ROUGIR ──────────────────────────────────────────────────────
#  1. les traits de dispersion disparaissent en visee     -> R2 (le point mentirait sur le cone)
#  2. le point rouge s'allume sans optique                -> R3
#  3. le refus perd la main sur la couleur en visee       -> R4
#  4. la dispersion se met a lire la rampe de visee       -> R5 (l'invariant 8.141.6)
#  5. la rampe de visee n'atteint jamais ses bornes       -> R6
# =================================================================================================

const DuelScript := preload("res://scripts/game/trench_fp.gd")

const CHECKS_ATTENDUS := 6

const RULES := {
	"tick_rate_hz": 20,
	"weapons": [
		{"id": "chacal", "cooldown_ticks": 5, "reload_ticks": 44, "mag_size": 30,
			"dispersion_deg": 1.1},
		{"id": "vipere", "cooldown_ticks": 6, "reload_ticks": 30, "mag_size": 12,
			"dispersion_deg": 1.4},
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


# ⚠️ Une doublure d'hôte : la sonde ne monte pas le rig 3D (il faudrait construire quatre armes).
# Ce qu'on éprouve est la LISTE DE PEINTURE, qui ne demande à la vue qu'une seule chose — l'arme
# a-t-elle du verre. On la lui donne, et on la fait varier : c'est exactement le degré de liberté
# que le contrôle R3 doit balayer.
class HoteDouble extends Control:
	var optique := true
	func has_optic() -> bool:
		return optique
	func set_aim(_y: float, _p: float) -> void:
		pass


func _duel(arme := "chacal", optique := true):
	var d = DuelScript.new()
	d._rules = RULES
	d._tick_rate = 20.0
	d._my_slot = 1
	d._buffer = [{"data": {
		"phase": "playing", "tick": 0,
		"players": [{"slot": 1, "pos": 2, "hp": 100, "ammo": 10, "weapon": arme,
			"reload_until_tick": 0, "bandage_until_tick": 0}],
	}}]
	d._pred_stance = "up"
	d._clock = 100.0
	d._reticle = Control.new()
	d._reticle.size = Vector2(80, 80)
	var h := HoteDouble.new()
	h.optique = optique
	d._viewmodel = h
	return d


# Les traits et le cœur, extraits de la liste de peinture. ⚠️ On lit LA LISTE, jamais une fonction
# que la peinture ne serait pas tenue d'appeler : c'est la leçon structurelle du §8.151-2ter.
func _lire(d) -> Dictionary:
	var traits := []
	var coeur := {}
	for cmd: Dictionary in d._reticle_paint_list():
		if cmd[DuelScript.PAINT_KIND] == DuelScript.PAINT_LINE:
			traits.append(cmd)
		elif coeur.is_empty():
			coeur = cmd
	var longueur := 0.0
	var alpha := 0.0
	if not traits.is_empty():
		var t: Dictionary = traits[0]
		longueur = (t[DuelScript.PAINT_A] as Vector2).distance_to(t[DuelScript.PAINT_B])
		alpha = (t[DuelScript.PAINT_COLOR] as Color).a
	return {"n_traits": traits.size(), "longueur": longueur, "alpha": alpha,
		"rayon": float(coeur.get(DuelScript.PAINT_RADIUS, 0.0)),
		"couleur": coeur.get(DuelScript.PAINT_COLOR, Color.BLACK)}


func _ready() -> void:
	print("\n=== SONDE 8.152.12 — LE POINT ROUGE EN VISEE ===\n")
	_probe_hanche()
	_probe_visee()
	_probe_sans_optique()
	_probe_refus()
	_probe_invariant()
	_probe_rampe()

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
# R1. À LA HANCHE, RIEN N'A CHANGÉ
# =================================================================================================
# ⚠️ La contre-face du lot : un correctif qui n'existe qu'en visée ne doit RIEN toucher à la hanche.
# Sans ce contrôle, on pourrait « réussir » le point rouge en abîmant les 95 % du temps de jeu.
func _probe_hanche() -> void:
	var d = _duel()
	d._ads_hud = 0.0
	var r := _lire(d)
	_ok("R1 a la hanche : quatre traits pleins, coeur petit, couleur d'accent (rien n'a bouge)",
		int(r["n_traits"]) == 4 and absf(float(r["longueur"]) - DuelScript.RETICLE_ARM_PX) < 0.01
			and float(r["rayon"]) <= 1.6 and (r["couleur"] as Color) == DuelScript.COL_ACCENT,
		"%d traits de %.2f px (alpha %.2f) · coeur r=%.2f · %s"
			% [int(r["n_traits"]), float(r["longueur"]), float(r["alpha"]), float(r["rayon"]),
				str(r["couleur"])])
	d.free()


# =================================================================================================
# R2. ⭐⭐ EN VISÉE : LE POINT ROUGE, ET LA DISPERSION TOUJOURS VISIBLE
# =================================================================================================
# ⛔ LE CONTRÔLE QUI COMPTE. Un point SEUL dirait « ça part exactement là » — ce qui n'est vrai que
# pour une arme à cône nul. C'est la promesse du CONDOR (0,35°), pas celle du FRELON (2,1°), et le
# §1.9 interdit précisément ce mensonge-là. Les traits doivent donc RESTER, atténués.
func _probe_visee() -> void:
	var d = _duel()
	d._ads_hud = 0.0
	var hanche := _lire(d)
	d._ads_hud = 1.0
	var visee := _lire(d)
	var rouge := visee["couleur"] as Color
	_ok("R2 en visee : le coeur grossit et vire au rouge, MAIS les 4 traits restent (le cone se voit)",
		int(visee["n_traits"]) == 4
			and float(visee["rayon"]) > float(hanche["rayon"]) * 1.5
			and rouge.r > 0.9 and rouge.g < 0.3
			and float(visee["longueur"]) < float(hanche["longueur"])
			and float(visee["longueur"]) > 0.5
			and float(visee["alpha"]) < float(hanche["alpha"]),
		"coeur %.2f -> %.2f px · traits %.2f -> %.2f px (alpha %.2f -> %.2f) · %s"
			% [float(hanche["rayon"]), float(visee["rayon"]), float(hanche["longueur"]),
				float(visee["longueur"]), float(hanche["alpha"]), float(visee["alpha"]),
				str(rouge)])
	d.free()


# =================================================================================================
# R3. ⭐ PAS D'OPTIQUE, PAS DE POINT
# =================================================================================================
# Le `vipere` se tient au guidon et à la hausse — c'est son identité (§2.2quinquies). Lui donner un
# point rouge l'aplatirait sur les trois autres armes. ⚠️ Et le test porte sur le MODÈLE (a-t-il un
# nœud de verre ?), jamais sur l'identifiant « vipere » : le jour où une arme gagne ou perd son
# optique, le HUD suit sans qu'on rouvre le fichier.
func _probe_sans_optique() -> void:
	var d = _duel("vipere", false)
	d._ads_hud = 1.0
	var r := _lire(d)
	var couleur := r["couleur"] as Color
	_ok("R3 sans optique, la visee ne fait apparaitre AUCUN point rouge",
		couleur == DuelScript.COL_ACCENT and float(r["rayon"]) <= 1.6
			and absf(float(r["longueur"]) - DuelScript.RETICLE_ARM_PX) < 0.01,
		"coeur r=%.2f %s · traits %.2f px" % [float(r["rayon"]), str(couleur),
			float(r["longueur"])])
	d.free()


# =================================================================================================
# R4. ⭐ LE REFUS GARDE LA MAIN, MÊME EN VISÉE
# =================================================================================================
# Le §8.141.9 exige qu'un tir impossible SE VOIE. Le point rouge ne suspend pas cette règle : en
# visée comme à la hanche, un chargeur vide ou un refus de cadence peint le réticule en DANGER.
# ⚠️ Et c'est pour ça que la couleur du point est un rouge distinct de `COL_DANGER` : deux rouges
# identiques rendraient le refus illisible exactement quand il compte.
func _probe_refus() -> void:
	var d = _duel()
	d._ads_hud = 1.0
	d._fire_refuse = 0.1
	var r := _lire(d)
	var c := r["couleur"] as Color
	var distincts: bool = DuelScript.COL_DANGER.r != DuelScript.COL_RETICLE_DOT.r \
		or DuelScript.COL_DANGER.g != DuelScript.COL_RETICLE_DOT.g
	_ok("R4 un refus reste ROUGE DANGER en visee, et les deux rouges sont distincts",
		c == DuelScript.COL_DANGER and distincts,
		"couleur du coeur %s · danger %s · emetteur %s"
			% [str(c), str(DuelScript.COL_DANGER), str(DuelScript.COL_RETICLE_DOT)])
	d.free()


# =================================================================================================
# R5. ⭐⭐⭐ LA DISPERSION NE LIT PAS LA VISÉE — L'INVARIANT §8.141.6
# =================================================================================================
# ⛔ Chez la référence, `adsProgress` est exactement la variable que la dispersion consomme
# (`index.js:223` puis `:662`). Notre rig la garde privée pour ça. Le HUD a donc sa PROPRE rampe
# (`_ads_hud`) — et si elle finissait par alimenter la précision, on aurait rouvert la porte qu'on
# venait de fermer, mais par l'autre côté.
#
# ⚠️ DEUX FACES, parce qu'une lecture de source seule ne prouverait rien :
#  a) la SOURCE de `_dispersion_degrees` ne mentionne pas `_ads_hud` (on découpe à la fonction, on
#     retire les commentaires — leçon §8.145, le grep compte les commentaires) ;
#  b) la MESURE : la dispersion est bit-identique à la hanche et à pleine visée.
func _probe_invariant() -> void:
	var f := FileAccess.open("res://scripts/game/trench_fp.gd", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	var i := src.find("func _dispersion_degrees(")
	var j := src.find("\nfunc ", i + 10)
	var code := ""
	for ligne in src.substr(i, j - i).split("\n"):
		var l: String = ligne.strip_edges()
		if not l.begins_with("#"):
			code += l + "\n"

	var d = _duel()
	d._ads_hud = 0.0
	var hanche := float(d._dispersion_degrees())
	d._ads_hud = 1.0
	var visee := float(d._dispersion_degrees())
	d.free()
	_ok("R5 la dispersion IGNORE la visee : ni dans sa source, ni dans sa valeur",
		i >= 0 and not code.contains("_ads_hud") and not code.contains("_ads_active")
			and hanche == visee and hanche > 0.0,
		"source propre : %s · dispersion hanche %.6f = visee %.6f"
			% [str(not code.contains("_ads_hud")), hanche, visee])


# =================================================================================================
# R6. LA RAMPE ATTEINT SES DEUX BORNES, EXACTEMENT
# =================================================================================================
# ⚠️ `move_toward` colle sur la cible, contrairement à une décroissance exponentielle : c'est ce qui
# permet d'exiger le ZÉRO et le UN exacts. Une rampe qui n'atteindrait jamais 0 laisserait un point
# rouge fantôme à la hanche, et une capture au repos ne serait plus bit-stable.
func _probe_rampe() -> void:
	var d = _duel()
	d._ads_active = true
	for i in 60:
		d._step_feel(1.0 / 60.0)
	var monte: float = d._ads_hud
	d._ads_active = false
	for i in 60:
		d._step_feel(1.0 / 60.0)
	var redescend: float = d._ads_hud
	_ok("R6 la rampe de visee atteint EXACTEMENT 1 puis EXACTEMENT 0",
		monte == 1.0 and redescend == 0.0,
		"apres 1 s de visee : %.9f · apres 1 s de relache : %.9f" % [monte, redescend])
	d.free()
