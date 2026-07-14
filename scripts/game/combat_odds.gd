class_name CombatOdds
extends RefCounted

# =====================================================================================
# PRÉVISION DE COMBAT (G4 §8.63) — calcul EXACT, client-only, AUCUN appel réseau.
#
# Réplique fidèle de la résolution serveur `engine.py::_handle_attack` :
#   • dés triés DÉCROISSANTS, comparaison des min(a, d) paires, ÉGALITÉ AU DÉFENSEUR ;
#   • dés défenseur = min(3, garnison) ; dés attaquant côté client = clampi(garnison-1, 1, 3)
#     (choix automatique de main.gd) ;
#   • flags de faction répliqués (mêmes clés que `factions.py`) :
#       - attack_reroll_low_dice      (Phalanges)  : relance du PLUS BAS dé ≤ 2, re-tri ;
#       - attack_reroll_all_low_dice  (Pillards)   : relance de TOUS les dés ≤ 2 (une passe), re-tri ;
#       - first_strike_bonus_die      (Chasseurs)  : +N dés lancés, on garde les N meilleurs ;
#       - defense_double_extra_kill   (Aegis)      : double en défense ⇒ +1 perte attaquante
#         APRÈS comparaison, plafonnée (la source garde ≥ 1 unité après le déplacement min) ;
#       - terror_extra_kill           (Écorcheurs) : exactement 2 pertes défensives ⇒ 3ᵉ par la
#         terreur, plafonnée à la garnison défensive.
#   • les modificateurs PONCTUELS À ÉTATS (cartes, boucliers, gels, duel de héros) ne sont PAS
#     simulés — mention « (hors pouvoirs à états) » affichée par le HUD.
#
# Implémentation : au lieu d'énumérer les 6^(a+d) tirages croisés (46 656), on énumère la
# DISTRIBUTION des dés triés PAR CAMP (≤ 6^4 tirages + branches de relance, agrégés en ≤ 56
# multiensembles) puis on croise les distributions (≤ 56 × 56 paires pondérées) → exact ET
# instantané. Tout est MÉMOÏSÉ (statique) par (dés, flags, garnisons normalisées).
#
# AUTO-VÉRIFICATION (exécutée UNE fois, builds debug) : pour 3 dés vs 2 SANS flags, la
# distribution d'un échange vaut exactement 2890/7776 (déf. perd 2), 2611/7776 (1 partout),
# 2275/7776 (att. perd 2). Si l'assert casse, la réplique du moteur a divergé.
# =====================================================================================

# Plafond de garnison simulée (au-delà, tronqué — précision suffisante, G4).
const MAX_UNITS := 60

# Mémos statiques (partagés entre tous les appels ; les clés portent les flags).
static var _side_memo: Dictionary = {}
static var _exchange_memo: Dictionary = {}
static var _dp_memo: Dictionary = {}
static var _self_checked := false


# --- API PUBLIQUE --------------------------------------------------------------------

# Distribution exacte d'UN échange de dés. Renvoie { "al,dl": prob } (pertes attaquant, pertes
# défenseur). `att_garrison`/`def_garrison` servent aux plafonds Aegis/terreur (99 = « grands »).
static func exchange_distribution(a_dice: int, d_dice: int, atk_flags: Dictionary,
		def_flags: Dictionary, att_garrison: int = 99, def_garrison: int = 99) -> Dictionary:
	var fs := _flag_sig(atk_flags, def_flags)
	# Normalisation des garnisons pour la clé de mémo : seuls comptent les régimes où les
	# plafonds Aegis (att ≤ 8) / terreur & conquête (def ≤ 4) peuvent mordre.
	var an := mini(att_garrison, 8)
	var dn := mini(def_garrison, 4)
	var key := "%d|%d|%d|%d|%s" % [a_dice, d_dice, an, dn, fs]
	if _exchange_memo.has(key):
		return _exchange_memo[key]

	var atk_dist := _attacker_distribution(
		a_dice,
		int(atk_flags.get("first_strike_bonus_die", 0)),
		_truthy(atk_flags.get("attack_reroll_low_dice", 0)),
		_truthy(atk_flags.get("attack_reroll_all_low_dice", 0)))
	var def_dist := _defender_distribution(d_dice)
	var terror := _truthy(atk_flags.get("terror_extra_kill", false))
	var aegis := _truthy(def_flags.get("defense_double_extra_kill", false))

	var out: Dictionary = {}
	for ak in atk_dist:
		var a_out: Dictionary = atk_dist[ak]
		var a_rolls: Array = a_out["rolls"]
		var pa: float = a_out["p"]
		for dk in def_dist:
			var d_out: Dictionary = def_dist[dk]
			var d_rolls: Array = d_out["rolls"]
			var p: float = pa * d_out["p"]

			# Comparaison classique : plus haut contre plus haut, égalité au DÉFENSEUR.
			var al := 0
			var dl := 0
			var min_dice: int = mini(a_rolls.size(), d_rolls.size())
			for i in range(min_dice):
				if int(a_rolls[i]) > int(d_rolls[i]):
					dl += 1
				else:
					al += 1

			# Écorcheurs : 2 pertes défensives exactement ⇒ 3ᵉ par la terreur, plafonnée à la
			# garnison défensive (réplique : `defender_losses < defender_garrison`).
			if terror and dl == 2 and dl < def_garrison:
				dl += 1

			# Aegis : double en défense ⇒ +1 perte attaquante, plafonnée (réplique du moteur :
			# la source doit garder ≥ 2 unités APRÈS pertes ET déplacement minimum de conquête).
			# NB : la logique utilise les garnisons BRUTES ; (an, dn) ne servent qu'à la clé de
			# mémo — les prédicats ci-dessus ne dépendent des garnisons qu'à travers min(att, 8)
			# et min(def, 4) (pertes ≤ 3, départ ≤ 3), donc le partage de mémo est exact.
			if aegis and d_out["double"]:
				var will_conquer: bool = (def_garrison - dl) <= 0
				var units_leaving: int = a_dice if will_conquer else 0
				if (att_garrison - al - units_leaving) >= 2:
					al += 1

			var okey := "%d,%d" % [al, dl]
			out[okey] = float(out.get(okey, 0.0)) + p

	_exchange_memo[key] = out
	return out


# Probabilité de CONQUÊTE COMPLÈTE (l'attaquant enchaîne les échanges jusqu'à prendre le
# territoire, et s'arrête — échec — sous 2 unités). Programmation dynamique mémoïsée.
# Retour : { "win_prob": float, "exp_att_losses": float, "exp_def_losses": float }.
static func conquest_probability(att_units: int, def_units: int, atk_flags: Dictionary,
		def_flags: Dictionary) -> Dictionary:
	if OS.is_debug_build() and not _self_checked:
		_self_checked = true
		_self_check()
	var att: int = mini(maxi(att_units, 0), MAX_UNITS)
	var def: int = mini(maxi(def_units, 0), MAX_UNITS)
	return _dp(att, def, atk_flags, def_flags, _flag_sig(atk_flags, def_flags))


# --- DP de conquête ------------------------------------------------------------------

static func _dp(att: int, def: int, atk_flags: Dictionary, def_flags: Dictionary,
		fs: String) -> Dictionary:
	if def <= 0:
		return {"win_prob": 1.0, "exp_att_losses": 0.0, "exp_def_losses": 0.0}
	if att < 2:
		return {"win_prob": 0.0, "exp_att_losses": 0.0, "exp_def_losses": 0.0}
	var key := "%d|%d|%s" % [att, def, fs]
	if _dp_memo.has(key):
		return _dp_memo[key]

	# Choix de dés du CLIENT réel (main.gd) : toujours le max possible.
	var a_dice: int = clampi(att - 1, 1, 3)
	var d_dice: int = mini(3, def)
	var dist := exchange_distribution(a_dice, d_dice, atk_flags, def_flags, att, def)

	var win := 0.0
	var eal := 0.0
	var edl := 0.0
	for okey in dist:
		var p: float = dist[okey]
		var parts: PackedStringArray = String(okey).split(",")
		var al := int(parts[0])
		var dl := int(parts[1])
		var sub := _dp(att - al, def - dl, atk_flags, def_flags, fs)
		win += p * float(sub["win_prob"])
		eal += p * (float(al) + float(sub["exp_att_losses"]))
		edl += p * (float(dl) + float(sub["exp_def_losses"]))

	var res := {"win_prob": win, "exp_att_losses": eal, "exp_def_losses": edl}
	_dp_memo[key] = res
	return res


# --- Distributions par camp (mémoïsées) ----------------------------------------------

# Distribution des dés ATTAQUANTS triés décroissants, APRÈS application des flags de relance
# (mêmes règles et même ORDRE que le moteur : first strike → relance Phalanges → Razzia).
static func _attacker_distribution(a_dice: int, fs_extra: int, reroll_one: bool,
		reroll_all: bool) -> Dictionary:
	var key := "A%d|%d|%d|%d" % [a_dice, fs_extra, int(reroll_one), int(reroll_all)]
	if _side_memo.has(key):
		return _side_memo[key]
	var acc: Dictionary = {}
	var total: int = a_dice + fs_extra
	var w: float = 1.0 / pow(6.0, total)
	for tirage in _all_rolls(total):
		var rolls: Array = (tirage as Array).duplicate()
		rolls.sort()
		rolls.reverse()
		if fs_extra > 0:
			rolls = rolls.slice(0, a_dice)  # on garde les MEILLEURS dés (frappe en premier).
		_branch_reroll_one(rolls, w, reroll_one, reroll_all, acc)
	_side_memo[key] = acc
	return acc


# Distribution des dés DÉFENSEURS triés décroissants + indicateur de DOUBLE (Aegis).
static func _defender_distribution(d_dice: int) -> Dictionary:
	var key := "D%d" % d_dice
	if _side_memo.has(key):
		return _side_memo[key]
	var acc: Dictionary = {}
	var w: float = 1.0 / pow(6.0, d_dice)
	for tirage in _all_rolls(d_dice):
		var rolls: Array = (tirage as Array).duplicate()
		rolls.sort()
		rolls.reverse()
		_acc_outcome(rolls, w, acc)
	# Marque le double une fois par multiensemble (propriété des dés, pas du chemin).
	for k in acc:
		var rolls: Array = acc[k]["rolls"]
		acc[k]["double"] = _has_double(rolls)
	_side_memo[key] = acc
	return acc


# Relance Phalanges : UN SEUL dé, le plus bas ≤ 2 (réplique de _lowest_index_at_most), re-tri.
static func _branch_reroll_one(rolls: Array, p: float, reroll_one: bool, reroll_all: bool,
		acc: Dictionary) -> void:
	if reroll_one:
		var idx := _lowest_index_at_most(rolls, 2)
		if idx != -1:
			for v in range(1, 7):
				var nr: Array = rolls.duplicate()
				nr[idx] = v
				nr.sort()
				nr.reverse()
				_branch_reroll_all(nr, p / 6.0, reroll_all, acc)
			return
	_branch_reroll_all(rolls, p, reroll_all, acc)


# Razzia (Pillards) : relance TOUS les dés ≤ 2 en UNE passe (les relances ne sont pas re-relancées).
static func _branch_reroll_all(rolls: Array, p: float, reroll_all: bool, acc: Dictionary) -> void:
	if reroll_all:
		var low: Array = []
		for i in range(rolls.size()):
			if int(rolls[i]) <= 2:
				low.append(i)
		if not low.is_empty():
			_razzia_rec(rolls, low, 0, p, acc)
			return
	_acc_outcome(rolls, p, acc)


static func _razzia_rec(rolls: Array, low: Array, k: int, p: float, acc: Dictionary) -> void:
	if k >= low.size():
		var nr: Array = rolls.duplicate()
		nr.sort()
		nr.reverse()
		_acc_outcome(nr, p, acc)
		return
	for v in range(1, 7):
		var nr: Array = rolls.duplicate()
		nr[low[k]] = v
		_razzia_rec(nr, low, k + 1, p / 6.0, acc)


# --- Primitives ----------------------------------------------------------------------

# Tous les tirages bruts de n dés (Array d'Array[int], 6^n éléments). Appelé sous mémo (n ≤ 4).
static func _all_rolls(n: int) -> Array:
	var out: Array = [[]]
	for _i in range(n):
		var next: Array = []
		for combo in out:
			for v in range(1, 7):
				var c: Array = (combo as Array).duplicate()
				c.append(v)
				next.append(c)
		out = next
	return out


# Index du plus petit dé ≤ threshold dans une liste triée DÉCROISSANTE (-1 si aucun) —
# réplique exacte de engine._lowest_index_at_most (le dernier qui passe est le plus petit).
static func _lowest_index_at_most(rolls: Array, threshold: int) -> int:
	var idx := -1
	for i in range(rolls.size()):
		if int(rolls[i]) <= threshold:
			idx = i
	return idx


# Vrai si au moins deux dés partagent la même valeur (réplique de engine._has_double).
static func _has_double(rolls: Array) -> bool:
	var seen: Dictionary = {}
	for v in rolls:
		if seen.has(int(v)):
			return true
		seen[int(v)] = true
	return false


static func _acc_outcome(rolls: Array, p: float, acc: Dictionary) -> void:
	var key := ""
	for v in rolls:
		key += str(int(v))
	if acc.has(key):
		acc[key]["p"] = float(acc[key]["p"]) + p
	else:
		acc[key] = {"rolls": rolls.duplicate(), "p": p}


# Vérité « souple » des flags de faction (mêmes conventions que faction_modifier côté serveur :
# 1 / 1.0 / true sont vrais, 0 / null / false / absent sont faux).
static func _truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	return false


# Signature canonique des 5 flags répliqués (clé de mémo).
static func _flag_sig(atk_flags: Dictionary, def_flags: Dictionary) -> String:
	return "%d%d%d%d%d" % [
		int(atk_flags.get("first_strike_bonus_die", 0)),
		int(_truthy(atk_flags.get("attack_reroll_low_dice", 0))),
		int(_truthy(atk_flags.get("attack_reroll_all_low_dice", 0))),
		int(_truthy(atk_flags.get("terror_extra_kill", false))),
		int(_truthy(def_flags.get("defense_double_extra_kill", false))),
	]


# --- Auto-vérification (builds debug) -------------------------------------------------
# 3 dés vs 2, SANS flags : fractions EXACTES du Risk classique. Tolérance 1e-9.
static func _self_check() -> void:
	var dist := exchange_distribution(3, 2, {}, {}, 99, 99)
	var expected := {
		"0,2": 2890.0 / 7776.0,  # le défenseur perd 2
		"1,1": 2611.0 / 7776.0,  # 1 partout
		"2,0": 2275.0 / 7776.0,  # l'attaquant perd 2
	}
	for k in expected:
		var got: float = float(dist.get(k, 0.0))
		if absf(got - float(expected[k])) > 1e-9:
			push_error("CombatOdds : divergence moteur sur 3v2 %s (attendu %.10f, obtenu %.10f)"
					% [k, expected[k], got])
			assert(false)
	# La distribution 3v2 ne contient QUE ces 3 issues (somme = 1).
	var total := 0.0
	for k in dist:
		total += float(dist[k])
	if absf(total - 1.0) > 1e-9 or dist.size() != 3:
		push_error("CombatOdds : distribution 3v2 anormale (%d issues, somme %.12f)"
				% [dist.size(), total])
		assert(false)
