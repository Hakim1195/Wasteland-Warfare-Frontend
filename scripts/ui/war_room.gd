extends RefCounted

# WAR ROOM (E5 §8.77) — module de calcul PUR de l'Intel de guerre : agrège les 8 compteurs
# publics de GameState.statistics (§8.35/§8.47) + l'état des territoires en lignes prêtes à
# afficher, et synthétise le contrôle des continents (bonus §4.2 enfin visualisés). Aucun nœud,
# aucun autoload — testable par asserts (pattern G4). Clés de statistics = STRINGS après JSON
# (piège §5) : accès systématique via str(int(pid)).

# Indice de menace (E5 — AUCUN effet gameplay, simple tri/visualisation) :
#   territoires × 2 + kills − pertes + éliminations × 5
static func threat_index(territory_count: int, kills: int, losses: int, eliminations: int) -> int:
	return territory_count * 2 + kills - losses + eliminations * 5

# Nombre de territoires possédés par un joueur (comptage direct de l'état public `territories`).
# Exposé ici aussi (miroir de war_roster.territory_count) pour que les consommateurs de WarRoom —
# tracker d'objectif E6, podium E11 — n'aient qu'un seul module de stats à importer.
static func territory_count(territories: Dictionary, pid: int) -> int:
	var n := 0
	for tid in territories:
		var t = territories[tid]
		if typeof(t) == TYPE_DICTIONARY:
			var o = t.get("owner_id")
			if o != null and int(o) == pid:
				n += 1
	return n

# Lecture d'un compteur ventilé par joueur ({ "<pid>": n } — clés string, valeurs float JSON).
static func stat_of(statistics: Dictionary, key: String, pid: int) -> int:
	var d = statistics.get(key, {})
	if typeof(d) != TYPE_DICTIONARY:
		return 0
	return int(d.get(str(int(pid)), 0))

# Une ligne par joueur, TRIÉE par territoires possédés décroissants (à égalité : pid croissant,
# ordre stable §5). Toutes les valeurs sont des int prêts à afficher.
static func player_rows(players: Dictionary, territories: Dictionary,
		statistics: Dictionary) -> Array:
	var rows: Array = []
	for k in players.keys():
		var pid := int(k)
		var terr_n := 0
		for tid in territories:
			var t = territories[tid]
			if typeof(t) == TYPE_DICTIONARY:
				var o = t.get("owner_id")
				if o != null and int(o) == pid:
					terr_n += 1
		var kills := stat_of(statistics, "combat_kills_by_player", pid)
		var losses := stat_of(statistics, "losses_by_player", pid)
		var elims := stat_of(statistics, "eliminations_by_player", pid)
		rows.append({
			"pid": pid,
			"territories": terr_n,
			"kills": kills,
			"losses": losses,
			# Ratio kills/(kills+pertes) ∈ [0..1] — 0,5 si aucun échange (barre neutre).
			"ratio": (float(kills) / float(kills + losses)) if (kills + losses) > 0 else 0.5,
			"conquests": stat_of(statistics, "conquests_by_player", pid),
			"eliminations": elims,
			"hero_damage": stat_of(statistics, "hero_damage_by_player", pid),
			"hero_kills": stat_of(statistics, "hero_kills_by_player", pid),
			"zone_deaths": stat_of(statistics, "zone_kills_by_player", pid),
			"threat": threat_index(terr_n, kills, losses, elims),
		})
	rows.sort_custom(func(a, b) -> bool:
		if int(a["territories"]) != int(b["territories"]):
			return int(a["territories"]) > int(b["territories"])
		return int(a["pid"]) < int(b["pid"]))
	return rows

# Rang d'un joueur absent de `rankings` (état incohérent / serveur antérieur) : trié EN QUEUE,
# jamais perdu — un débriefing qui « oublie » un belligérant est pire qu'un ordre approximatif.
const RANK_UNKNOWN := 9999

# Lignes du DÉBRIEFING (§8.92) — une par joueur, pour le tableau BILAN du Rapport Post-Op.
# Repart de player_rows() (SOURCE UNIQUE des compteurs : aucune divergence possible entre le HUD
# in-game et le rapport) puis :
#   - RETRIE par `rankings` (ordre du podium) : dans un débriefing le classement final prime sur
#     les territoires possédés (tri de player_rows, pertinent en cours de partie mais pas ici) ;
#   - enrichit de l'identité et des marqueurs d'affichage.
# `winner_pid` = -1 (ou pid inconnu) → aucune ligne marquée vainqueur. Clés de `players` en STRING
# après JSON (piège §5) → accès via str(pid) avec repli sur la clé int.
static func debrief_rows(players: Dictionary, territories: Dictionary, statistics: Dictionary,
		rankings: Array, my_pid: int, winner_pid: int) -> Array:
	var rank_of := {}
	for i in range(rankings.size()):
		rank_of[int(rankings[i])] = i
	var rows: Array = player_rows(players, territories, statistics)
	for r in rows:
		var pid := int(r["pid"])
		var raw = players.get(str(pid), players.get(pid, {}))
		var p: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
		# §8.118 : repli de pseudo jadis en dur en FRANÇAIS (« JOUEUR 3 »). On RÉUTILISE la clé
		# existante `WR_PLAYER_FALLBACK` (déjà servie par war_feed.gd et player_chip.gd) au lieu
		# d'en créer une seconde pour la même phrase. ⚠️ `TranslationServer.translate` et NON `tr()` :
		# ce module est PUR (extends RefCounted, méthodes statiques) — `tr()` est une méthode de
		# Node, indisponible ici (même piège que les modules statiques du §8.104).
		r["username"] = str(p.get("username", TranslationServer.translate("WR_PLAYER_FALLBACK") % pid))
		# Repli pid < 0 : convention G2 (les bots portent des ids NÉGATIFS).
		r["is_bot"] = bool(p.get("is_bot", pid < 0))
		r["is_alive"] = str(p.get("status", "alive")) == "alive"
		r["is_me"] = (pid == my_pid)
		r["is_winner"] = (pid == winner_pid)
		r["rank"] = int(rank_of.get(pid, RANK_UNKNOWN))
	rows.sort_custom(func(a, b) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		return int(a["pid"]) < int(b["pid"]))   # ordre stable (§5)
	return rows

# Synthèse des continents : `continents` = { cid: { "name": String, "tids": Array } } (résolu par
# le contrôleur depuis MapData.get_map(map_id).continent_territories — carte courante G5).
# Retour (ordre d'itération des clés) : { "name", "total", "held" (du leader), "owner" (pid si
# TOUT le continent est à lui, sinon null), "leader_pid" (pid|null si aucun territoire possédé) }.
static func continent_rows(territories: Dictionary, continents: Dictionary) -> Array:
	var out: Array = []
	for cid in continents.keys():
		var cdef: Dictionary = continents[cid]
		var tids: Array = cdef.get("tids", [])
		var counts: Dictionary = {}
		for tid in tids:
			var t = territories.get(str(tid), null)
			if typeof(t) != TYPE_DICTIONARY:
				continue
			var o = t.get("owner_id")
			if o != null:
				counts[int(o)] = int(counts.get(int(o), 0)) + 1
		var leader_pid = null
		var leader_held := 0
		for pid in counts.keys():
			if int(counts[pid]) > leader_held \
					or (int(counts[pid]) == leader_held and leader_pid != null and int(pid) < int(leader_pid)):
				leader_pid = int(pid)
				leader_held = int(counts[pid])
		out.append({
			"name": str(cdef.get("name", cid)),
			"total": tids.size(),
			"held": leader_held,
			"owner": leader_pid if (leader_pid != null and leader_held == tids.size() and tids.size() > 0) else null,
			"leader_pid": leader_pid,
		})
	return out
