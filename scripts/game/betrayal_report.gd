class_name BetrayalReport
extends RefCounted

# RAPPORT DE TRAHISON (§8.121, LOT B) — module de calcul PUR (aucun nœud, aucun autoload, aucun
# `tr()`) : transforme le JOURNAL D'ATTAQUES du `game_over` (§8.121 de CONTRAT_RESEAU.md) et la
# timeline de domination (`statistics.territory_history`, §8.83) en QUATRE analyses narratives
# prêtes à afficher. Testable par asserts (pattern G4 §8.63).
#
# Répartition des responsabilités (§6.1 / Règle d'Or §6) : le SERVEUR fournit les FAITS bruts (une
# ligne par attaque), ce module en tire l'HISTOIRE, et `operation_report.gd` la met en page. Les
# seuils de décision vivent dans `CONFIG` ci-dessous — un playtest les change sans toucher au
# backend. Ce module ne traduit RIEN : il renvoie des CLÉS i18n et des nombres, la Vue appelle
# `tr()` (un module statique n'a pas de `tr()` fiable, cf. piège §8.104).
#
# Entrées telles qu'elles arrivent du réseau :
#   attack_log        Array[Dictionary] — { turn, round, attacker_id, defender_id (null = NEUTRE),
#                                           kills, conquered, hero_kill }.
#                     ⚠️ Piège JSON float (§5) : tous les nombres arrivent en `float` et toutes les
#                     clés de dictionnaire en `String` → `int(...)` / `str(int(pid))` systématiques.
#   territory_history Array[Dictionary] — [{ "<pid:str>": nb_territoires }] , un par round achevé.
#   statistics        Dictionary        — `GameState.statistics` (pour `eliminated_by_player` et
#                                         `hero_down_order`).
#
# ⚠️⚠️ ÉCART ASSUMÉ AVEC LA DÉFINITION PRODUIT DU COUP DE POIGNARD. La définition demandait « …
# alors qu'ils étaient VOISINS depuis ≥ 2 rounds ». Cette clause n'est PAS calculable : le contrat
# réseau ne transporte aucun historique de PROPRIÉTÉ (`territory_history` ne stocke que des
# COMPTES de territoires, et le journal d'attaques ne porte pas d'id de territoire — cf. §8.121.5).
# Reconstituer un graphe de voisinage par round exigerait un second champ backend bien plus lourd
# que le journal lui-même. La notion est donc portée ENTIÈREMENT par la durée de CALME entre les
# deux joueurs (`calm_rounds`), qui capture l'essentiel de l'intention : « ils se laissaient
# tranquilles, et soudain… ». Documenté plutôt que deviné (règle « interdiction de deviner »).

# Sentinelle « territoire NEUTRE » (defender_id null côté réseau). Les attaques sur du neutre sont
# des conquêtes de terrain, pas des actes d'agression envers un joueur : elles sont EXCLUES de la
# matrice et du coup de poignard (sinon un joueur qui ramasse des territoires ravagés par la zone
# apparaîtrait comme l'agresseur n° 1 de la partie).
const NEUTRAL := -9999

const CONFIG := {
	# « ne s'étaient pas affrontés depuis ≥ 2 rounds complets (ou jamais) ».
	"min_calm_rounds": 2,
	# Un coup de poignard qui ne détruit RIEN n'est pas un moment mémorable : on lui préfère le
	# repli « plus long voisinage pacifique ». (Mettre 0 accepterait les assauts ratés.)
	"min_backstab_kills": 1,
	# « plus grande variation de territoires d'un joueur sur une fenêtre de 3 snapshots ».
	"turning_window": 3,
}

# =========================================================
# Normalisation du journal
# =========================================================

# Une entrée BRUTE du réseau → entrée typée, ou {} si la ligne est inexploitable (ligne non-dict
# d'un serveur plus récent, attaquant illisible). Client défensif §9.2 : on ignore, on ne casse pas.
static func _entry(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var attacker := int(raw.get("attacker_id", NEUTRAL))
	if attacker == NEUTRAL:
		return {}
	var d = raw.get("defender_id")
	return {
		"turn": int(raw.get("turn", 0)),
		"round": maxi(1, int(raw.get("round", 1))),
		"attacker": attacker,
		"defender": NEUTRAL if d == null else int(d),
		"kills": int(raw.get("kills", 0)),
		"conquered": bool(raw.get("conquered", false)),
		"hero_kill": bool(raw.get("hero_kill", false)),
	}

# Journal typé et trié CHRONOLOGIQUEMENT. Le serveur appende déjà dans l'ordre, mais le tri est
# explicite : toute l'analyse de « calme » en dépend, et un tri implicite serait un couplage muet.
# Départage stable sur l'index d'origine (deux attaques du même tour gardent leur ordre d'arrivée).
static func normalized(attack_log: Array) -> Array:
	var out: Array = []
	for i in range(attack_log.size()):
		var e := _entry(attack_log[i])
		if not e.is_empty():
			e["seq"] = i
			out.append(e)
	out.sort_custom(func(a, b) -> bool:
		if int(a["turn"]) != int(b["turn"]):
			return int(a["turn"]) < int(b["turn"])
		return int(a["seq"]) < int(b["seq"]))
	return out

# Attaques JOUEUR contre JOUEUR uniquement (le neutre est écarté, cf. NEUTRAL ci-dessus).
static func _duels(attack_log: Array) -> Array:
	var out: Array = []
	for e in normalized(attack_log):
		if int(e["defender"]) != NEUTRAL and int(e["defender"]) != int(e["attacker"]):
			out.append(e)
	return out

# Clé d'un couple NON ORIENTÉ : « qui a frappé qui » n'importe pas pour mesurer le calme — deux
# joueurs sont en paix, ou ils ne le sont pas.
static func _pair_key(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]

# =========================================================
# 1) LA MATRICE D'AGRESSION
# =========================================================
# Grille N×N des unités détruites par couple (lignes = attaquants). Renvoie AUSSI la case maximale
# (liseré or côté Vue) et le total, pour que la Vue n'ait aucun calcul à refaire.
#   → { "cells": { att: { def: kills } },      # toutes les cases présentes, 0 compris
#       "attacks": { att: { def: nb } },       # nombre d'assauts (l'intensité ≠ le volume de kills)
#       "max": { "attacker": int, "defender": int, "kills": int },   # kills = 0 si aucune attaque
#       "total": int }
static func aggression_matrix(attack_log: Array, pids: Array) -> Dictionary:
	var known := {}
	var order: Array = []
	for p in pids:
		var pid := int(p)
		if not known.has(pid):
			known[pid] = true
			order.append(pid)
	var cells := {}
	var attacks := {}
	for a in order:
		cells[a] = {}
		attacks[a] = {}
		for d in order:
			if a != d:
				cells[a][d] = 0
				attacks[a][d] = 0
	var total := 0
	for e in _duels(attack_log):
		var att := int(e["attacker"])
		var dfd := int(e["defender"])
		# Un belligérant absent de `pids` (déconnecté avant l'envoi du game_over ?) n'a pas de
		# colonne : on l'ignore plutôt que de créer une ligne fantôme sans identité affichable.
		if not cells.has(att) or not cells[att].has(dfd):
			continue
		cells[att][dfd] += int(e["kills"])
		attacks[att][dfd] += 1
		total += int(e["kills"])
	# Case maximale — départage DÉTERMINISTE (attaquant puis défenseur croissants) : à égalité de
	# kills, le liseré or doit toujours tomber sur la même case, sinon deux joueurs de la même
	# partie verraient deux « pires agresseurs » différents.
	var best := {"attacker": NEUTRAL, "defender": NEUTRAL, "kills": 0}
	for a in order:
		for d in order:
			if a == d:
				continue
			var v := int(cells[a][d])
			if v > best["kills"]:
				best = {"attacker": a, "defender": d, "kills": v}
	return {"cells": cells, "attacks": attacks, "max": best, "total": total, "pids": order}

# =========================================================
# 2) LE COUP DE POIGNARD
# =========================================================
# Renvoie {} si la partie n'a connu AUCUN affrontement entre joueurs (« GUERRE FRONTALE » est alors
# affiché par la Vue — c'est une information, pas un trou).
#   → { "attacker", "defender", "round", "turn", "kills", "calm_rounds",
#       "conquered", "hero_kill",
#       "confirmed": bool }   # true = seuil de calme ET de kills atteints (vraie trahison) ;
#                             # false = REPLI « premier contact au plus long calme »
#
# `calm_rounds` = round de l'attaque − round du DERNIER affrontement du couple (0 s'ils ne
# s'étaient jamais affrontés). Une attaque au round 5 sur un couple qui s'était battu au round 3
# donne donc 2 : « ils ne s'étaient plus affrontés depuis 2 rounds ».
static func find_backstab(attack_log: Array, config: Dictionary = {}) -> Dictionary:
	var min_calm := int(config.get("min_calm_rounds", CONFIG["min_calm_rounds"]))
	var min_kills := int(config.get("min_backstab_kills", CONFIG["min_backstab_kills"]))
	var last_round := {}
	var confirmed: Dictionary = {}
	var first_contact: Dictionary = {}
	for e in _duels(attack_log):
		var key := _pair_key(int(e["attacker"]), int(e["defender"]))
		var previous := int(last_round.get(key, 0))
		var calm := int(e["round"]) - previous
		last_round[key] = int(e["round"])
		var cand := {
			"attacker": int(e["attacker"]), "defender": int(e["defender"]),
			"round": int(e["round"]), "turn": int(e["turn"]), "kills": int(e["kills"]),
			"calm_rounds": maxi(0, calm), "conquered": bool(e["conquered"]),
			"hero_kill": bool(e["hero_kill"]),
		}
		if calm >= min_calm and int(e["kills"]) >= min_kills:
			if confirmed.is_empty() or _better_backstab(cand, confirmed):
				confirmed = cand
		if previous == 0:
			# PREMIER contact de ce couple — matière du repli « plus long voisinage pacifique ».
			if first_contact.is_empty() or _longer_peace(cand, first_contact):
				first_contact = cand
	if not confirmed.is_empty():
		confirmed["confirmed"] = true
		return confirmed
	if not first_contact.is_empty():
		first_contact["confirmed"] = false
		return first_contact
	return {}

# Ordre de mérite d'un coup de poignard : plus de kills d'abord (« la plus grosse attaque »), puis
# le calme le plus long, puis le PLUS TÔT dans la partie, puis l'attaquant de plus petit id.
# Entièrement déterministe : deux clients de la même partie désignent le même coupable.
static func _better_backstab(cand: Dictionary, best: Dictionary) -> bool:
	if int(cand["kills"]) != int(best["kills"]):
		return int(cand["kills"]) > int(best["kills"])
	if int(cand["calm_rounds"]) != int(best["calm_rounds"]):
		return int(cand["calm_rounds"]) > int(best["calm_rounds"])
	if int(cand["turn"]) != int(best["turn"]):
		return int(cand["turn"]) < int(best["turn"])
	return int(cand["attacker"]) < int(best["attacker"])

# Repli : le couple qui a coexisté PACIFIQUEMENT le plus longtemps avant son premier échange.
static func _longer_peace(cand: Dictionary, best: Dictionary) -> bool:
	if int(cand["calm_rounds"]) != int(best["calm_rounds"]):
		return int(cand["calm_rounds"]) > int(best["calm_rounds"])
	if int(cand["turn"]) != int(best["turn"]):
		return int(cand["turn"]) < int(best["turn"])
	return int(cand["attacker"]) < int(best["attacker"])

# =========================================================
# 3) LE MOMENT DÉCISIF
# =========================================================
# Le plus grand BASCULEMENT de la timeline de domination : la plus forte variation du nombre de
# territoires d'un joueur sur une fenêtre de `turning_window` snapshots consécutifs. Aucune donnée
# nouvelle n'est requise — `territory_history` alimente déjà le graphique du Rapport Post-Op.
#   → {} si l'historique est trop court (partie éclair / serveur antérieur)
#   → { "pid", "delta", "before", "after", "round", "from_index", "to_index" }
# `round` = round dont la FIN est photographiée par le dernier snapshot de la fenêtre (le snapshot
# d'indice `i` photographie la fin du round `i+1`, cf. engine.current_global_round §8.121).
static func find_turning_point(territory_history: Array, config: Dictionary = {}) -> Dictionary:
	var window := maxi(2, int(config.get("turning_window", CONFIG["turning_window"])))
	var snaps: Array = []
	for s in territory_history:
		if typeof(s) == TYPE_DICTIONARY:
			snaps.append(s)
	if snaps.size() < window:
		return {}
	# Ensemble des joueurs vus dans l'historique (clés STRING après JSON, piège §5).
	var pids := {}
	for s in snaps:
		for k in s.keys():
			pids[int(k)] = true
	var sorted_pids: Array = pids.keys()
	sorted_pids.sort()
	var best := {}
	for i in range(snaps.size() - window + 1):
		var j := i + window - 1
		for pid in sorted_pids:
			var before := int(snaps[i].get(str(int(pid)), 0))
			var after := int(snaps[j].get(str(int(pid)), 0))
			var cand := {
				"pid": int(pid), "delta": after - before, "before": before, "after": after,
				"round": j + 1, "from_index": i, "to_index": j,
			}
			if best.is_empty() or _bigger_swing(cand, best):
				best = cand
	# Une partie strictement statique n'a pas de moment décisif : ne rien affirmer valait mieux que
	# désigner arbitrairement un joueur avec un delta de 0.
	if best.is_empty() or int(best["delta"]) == 0:
		return {}
	return best

# Ordre de mérite d'un basculement : amplitude d'abord, puis l'EFFONDREMENT avant la conquête (un
# empire qui tombe est le récit ; le gagnant est déjà au podium), puis la fenêtre la plus précoce,
# puis le pid le plus petit.
static func _bigger_swing(cand: Dictionary, best: Dictionary) -> bool:
	var ca := absi(int(cand["delta"]))
	var ba := absi(int(best["delta"]))
	if ca != ba:
		return ca > ba
	var cneg := int(cand["delta"]) < 0
	var bneg := int(best["delta"]) < 0
	if cneg != bneg:
		return cneg
	if int(cand["to_index"]) != int(best["to_index"]):
		return int(cand["to_index"]) < int(best["to_index"])
	return int(cand["pid"]) < int(best["pid"])

# Sous-fenêtre des séries du graphique (mini-vue centrée sur le moment décisif) : `series` est la
# structure DÉJÀ construite pour la `TimelineChart` ([{ color, points }]) — on la tronque au lieu
# d'en fabriquer une seconde, pour que les deux courbes ne puissent pas raconter deux histoires.
# Bornes hors plage → série renvoyée telle quelle (défensif).
static func timeline_window(series: Array, from_index: int, to_index: int) -> Array:
	var out: Array = []
	for entry in series:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pts = entry.get("points", [])
		if typeof(pts) != TYPE_ARRAY:
			continue
		var lo := clampi(from_index, 0, maxi(0, pts.size() - 1))
		var hi := clampi(to_index, lo, maxi(0, pts.size() - 1))
		var sliced: Array = []
		for i in range(lo, hi + 1):
			sliced.append(int(pts[i]))
		out.append({"color": entry.get("color", Color.WHITE), "points": sliced})
	return out

# =========================================================
# 4) LA CHAÎNE DES CHUTES
# =========================================================
# Éliminations dans l'ORDRE chronologique, avec leur auteur.
#   → [{ "victim", "killer", "round", "turn", "hero": bool }]
#
# L'ATTRIBUTION fait autorité depuis `statistics.eliminated_by_player` ({ victime : tueur }) — c'est
# le champ que le serveur maintient précisément pour ça (§8.61) ; la reconstruire depuis le journal
# se tromperait sur les doubles causes (perte du dernier territoire ET permadeath au même assaut).
# Le journal ne sert qu'à DATER : dernier assaut du tueur sur la victime. Journal tronqué par le
# plafond (§8.121) ou absent → `turn = -1` / `round = 0`, l'entrée passe en fin de chaîne sans
# mentir sur une date qu'on ne connaît pas.
static func elimination_chain(statistics: Dictionary, attack_log: Array) -> Array:
	var attributed = statistics.get("eliminated_by_player", {})
	if typeof(attributed) != TYPE_DICTIONARY or attributed.is_empty():
		return []
	# Datation : dernier assaut (tueur → victime) trouvé au journal.
	var when := {}
	for e in _duels(attack_log):
		when["%d>%d" % [int(e["attacker"]), int(e["defender"])]] = \
			{"turn": int(e["turn"]), "round": int(e["round"])}
	# Morts de HÉROS (permadeath §8.61) : marquées ◆ par la Vue. Ordre chronologique garanti côté
	# serveur (`hero_down_order`), réutilisé ici comme départage secondaire.
	var hero_order := {}
	var hd = statistics.get("hero_down_order", [])
	if typeof(hd) == TYPE_ARRAY:
		for i in range(hd.size()):
			hero_order[int(hd[i])] = i
	var rows: Array = []
	var victims: Array = []
	for k in attributed.keys():
		victims.append(int(k))
	victims.sort()
	for victim in victims:
		var killer := int(attributed.get(str(int(victim)), attributed.get(victim, NEUTRAL)))
		var stamp: Dictionary = when.get("%d>%d" % [killer, victim], {"turn": -1, "round": 0})
		rows.append({
			"victim": victim, "killer": killer,
			"turn": int(stamp["turn"]), "round": int(stamp["round"]),
			"hero": hero_order.has(victim),
			"_hero_rank": int(hero_order.get(victim, 9999)),
		})
	rows.sort_custom(func(a, b) -> bool:
		# Les entrées non datées (journal tronqué) ferment la marche, sans se mélanger aux datées.
		var ka := int(a["turn"]) if int(a["turn"]) >= 0 else 1 << 30
		var kb := int(b["turn"]) if int(b["turn"]) >= 0 else 1 << 30
		if ka != kb:
			return ka < kb
		if int(a["_hero_rank"]) != int(b["_hero_rank"]):
			return int(a["_hero_rank"]) < int(b["_hero_rank"])
		return int(a["victim"]) < int(b["victim"]))
	for r in rows:
		r.erase("_hero_rank")
	return rows

# =========================================================
# Auto-vérification (pattern G4 §8.63) — exécutée en build debug par operation_report._self_check
# =========================================================
static var _checked := false

static func self_check() -> void:
	if _checked:
		return
	_checked = true
	# Journal de démonstration, écrit EXACTEMENT comme le réseau l'envoie (nombres en float, clés
	# de dict en string) — c'est ce que le module doit savoir avaler.
	var log_ := [
		{"turn": 1.0, "round": 1.0, "attacker_id": 1.0, "defender_id": 2.0, "kills": 1.0,
			"conquered": false, "hero_kill": false},
		{"turn": 2.0, "round": 1.0, "attacker_id": 2.0, "defender_id": null, "kills": 2.0,
			"conquered": true, "hero_kill": false},            # NEUTRE → hors analyse
		{"turn": 9.0, "round": 4.0, "attacker_id": 3.0, "defender_id": 1.0, "kills": 5.0,
			"conquered": true, "hero_kill": true},             # 3 n'avait JAMAIS frappé 1
		{"turn": 10.0, "round": 4.0, "attacker_id": 1.0, "defender_id": 2.0, "kills": 9.0,
			"conquered": false, "hero_kill": false},           # calme 4−1 = 3 rounds
		"ligne pourrie",                                        # serveur plus récent → ignorée
	]
	# --- Normalisation / étanchéité du neutre ---
	assert(normalized(log_).size() == 4)          # la ligne non-dict est écartée
	assert(_duels(log_).size() == 3)              # l'attaque sur le neutre est écartée
	# --- Matrice d'agression ---
	var m := aggression_matrix(log_, [1, 2, 3])
	assert(int(m["cells"][1][2]) == 10)           # 1 + 9
	assert(int(m["cells"][3][1]) == 5)
	assert(int(m["cells"][2][1]) == 0)            # case présente même sans attaque
	assert(not m["cells"][1].has(1))              # aucune diagonale
	assert(int(m["max"]["attacker"]) == 1 and int(m["max"]["defender"]) == 2)
	assert(int(m["max"]["kills"]) == 10)
	assert(int(m["total"]) == 15)                 # 1 + 5 + 9 (le neutre ne compte pas)
	assert(int(m["attacks"][1][2]) == 2)
	# Un attaquant hors de `pids` n'invente pas de ligne fantôme.
	var m2 := aggression_matrix(log_, [1, 2])
	assert(not m2["cells"].has(3) and int(m2["cells"][1][2]) == 10)
	# --- Coup de poignard ---
	var stab := find_backstab(log_)
	assert(bool(stab["confirmed"]))
	assert(int(stab["attacker"]) == 1 and int(stab["defender"]) == 2)   # 9 kills > 5 kills
	assert(int(stab["kills"]) == 9 and int(stab["round"]) == 4 and int(stab["calm_rounds"]) == 3)
	# Départage : à kills ÉGAUX, le calme le plus long gagne.
	var tie := find_backstab([
		{"turn": 1, "round": 1, "attacker_id": 1, "defender_id": 2, "kills": 1,
			"conquered": false, "hero_kill": false},
		{"turn": 8, "round": 5, "attacker_id": 1, "defender_id": 2, "kills": 4,
			"conquered": false, "hero_kill": false},   # calme 4
		{"turn": 9, "round": 5, "attacker_id": 3, "defender_id": 2, "kills": 4,
			"conquered": false, "hero_kill": false},   # calme 5 (jamais affrontés) → gagne
	])
	assert(int(tie["attacker"]) == 3 and int(tie["calm_rounds"]) == 5)
	# Aucune trahison qualifiée → REPLI sur le premier contact au plus long calme, `confirmed` faux.
	var frontal := find_backstab([
		{"turn": 1, "round": 1, "attacker_id": 1, "defender_id": 2, "kills": 3,
			"conquered": false, "hero_kill": false},
		{"turn": 3, "round": 2, "attacker_id": 2, "defender_id": 1, "kills": 2,
			"conquered": false, "hero_kill": false},
	])
	assert(not bool(frontal["confirmed"]))
	assert(int(frontal["attacker"]) == 1 and int(frontal["calm_rounds"]) == 1)
	# Un assaut qui ne détruit RIEN ne qualifie pas (min_backstab_kills).
	var dry := find_backstab([
		{"turn": 12, "round": 6, "attacker_id": 1, "defender_id": 2, "kills": 0,
			"conquered": false, "hero_kill": false},
	])
	assert(not bool(dry["confirmed"]) and int(dry["kills"]) == 0)
	# Partie sans le moindre affrontement entre joueurs → {} (la Vue affiche « GUERRE FRONTALE »).
	assert(find_backstab([]).is_empty())
	assert(find_backstab([{"turn": 1, "round": 1, "attacker_id": 1, "defender_id": null,
		"kills": 2, "conquered": true, "hero_kill": false}]).is_empty())
	# --- Moment décisif ---
	var hist := [{"1": 14.0, "2": 14.0}, {"1": 16.0, "2": 12.0}, {"1": 22.0, "2": 6.0},
		{"1": 24.0, "2": 4.0}]
	var tp := find_turning_point(hist)
	# Fenêtres de 3 : indices 0→2 donnent 1:+8 / 2:−8 ; 1→3 donnent 1:+8 / 2:−8. À amplitude
	# égale, l'EFFONDREMENT (delta négatif) puis la fenêtre la PLUS PRÉCOCE l'emportent.
	assert(int(tp["pid"]) == 2 and int(tp["delta"]) == -8)
	assert(int(tp["from_index"]) == 0 and int(tp["to_index"]) == 2 and int(tp["round"]) == 3)
	assert(int(tp["before"]) == 14 and int(tp["after"]) == 6)
	# Historique trop court / partie statique → aucune affirmation.
	assert(find_turning_point([{"1": 5.0}, {"1": 5.0}]).is_empty())
	assert(find_turning_point([{"1": 5.0}, {"1": 5.0}, {"1": 5.0}]).is_empty())
	# Sous-fenêtre du graphique.
	var series := [{"color": Color.RED, "points": [1, 2, 3, 4, 5]}]
	var win := timeline_window(series, 1, 3)
	assert(win.size() == 1 and win[0]["points"] == [2, 3, 4])
	assert(timeline_window(series, -5, 99)[0]["points"] == [1, 2, 3, 4, 5])   # bornes clampées
	# --- Chaîne des chutes ---
	var stats := {
		"eliminated_by_player": {"1": 3.0, "5": 1.0},   # 1 tué par 3 ; 5 tué par 1
		"hero_down_order": [1.0],                        # seul le héros de 1 est tombé
	}
	var chain := elimination_chain(stats, log_ + [
		{"turn": 14.0, "round": 6.0, "attacker_id": 1.0, "defender_id": 5.0, "kills": 1.0,
			"conquered": true, "hero_kill": false}])
	assert(chain.size() == 2)
	assert(int(chain[0]["victim"]) == 1 and int(chain[0]["killer"]) == 3)
	assert(int(chain[0]["round"]) == 4 and bool(chain[0]["hero"]))
	assert(int(chain[1]["victim"]) == 5 and not bool(chain[1]["hero"]))
	assert(not chain[0].has("_hero_rank"))           # champ de tri interne nettoyé
	# Élimination non datable (journal tronqué par le plafond) → repoussée en fin de chaîne.
	var undated := elimination_chain({"eliminated_by_player": {"9": 4.0, "5": 1.0}},
		[{"turn": 14, "round": 6, "attacker_id": 1, "defender_id": 5, "kills": 1,
			"conquered": true, "hero_kill": false}])
	assert(int(undated[0]["victim"]) == 5 and int(undated[1]["victim"]) == 9)
	assert(int(undated[1]["turn"]) == -1 and int(undated[1]["round"]) == 0)
	assert(elimination_chain({}, log_).is_empty())
