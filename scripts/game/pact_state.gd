extends RefCounted
class_name PactState

# =====================================================================================
# PACTES DE NON-AGRESSION (§8.123) — LECTURES PURES de `GameState.pacts`
# =====================================================================================
# Miroir CLIENT du module serveur `api/game/pacts.py`, réduit à ce dont une VUE a besoin :
# répondre à « qui est lié à qui », « ai-je une offre en attente », « qui a trahi ce match ».
#
# ⚠️ AUCUNE RÈGLE DE JEU ICI (Règle d'Or §6.1). Ce fichier ne DÉCIDE rien : il ne dit jamais si une
# offre est légale — c'est le serveur qui tranche, et lui seul. Il ne fait que LIRE la liste que le
# serveur nous a servie. Le client peut GRISER un bouton pour éviter un aller-retour perdu, mais
# une divergence d'avis entre les deux ne produit qu'un refus propre, jamais un état incohérent.
#
# ⚠️ CONFIDENTIALITÉ : `GameState.pacts` est **DÉJÀ REDACTÉE POUR NOUS** par le serveur (les
# négociations d'autrui n'y figurent tout simplement pas). Il n'y a donc RIEN à filtrer ici — et
# surtout aucune tentation de « masquer à l'affichage » une donnée qu'on n'aurait pas dû recevoir.
#
# ⚠️ Piège JSON float (§5) : tous les nombres arrivent en `float` → `int(...)` systématique.

const STATUS_PENDING := "pending"
const STATUS_ACTIVE := "active"
const STATUS_BROKEN := "broken"
const STATUS_DECLINED := "declined"
const STATUS_EXPIRED := "expired"


static func _entries(pacts) -> Array:
	return pacts if typeof(pacts) == TYPE_ARRAY else []


static func _pair(entry: Dictionary) -> Array:
	return [int(entry.get("a_id", -9999)), int(entry.get("b_id", -9999))]


# L'AUTRE joueur d'un pacte, ou -9999 si `pid` n'y figure pas.
static func partner_of(entry: Dictionary, pid: int) -> int:
	var pair := _pair(entry)
	if int(pid) == pair[0]:
		return pair[1]
	if int(pid) == pair[1]:
		return pair[0]
	return -9999


# Ids des joueurs liés à `pid` par un pacte ACTIF (ceux qui portent le 🤝 sur leur chip).
static func active_partners(pacts, pid: int) -> Array:
	var out: Array = []
	for e in _entries(pacts):
		if typeof(e) != TYPE_DICTIONARY or str(e.get("status", "")) != STATUS_ACTIVE:
			continue
		var other := partner_of(e, pid)
		if other != -9999 and not out.has(other):
			out.append(other)
	return out


# Le pacte ACTIF liant `a` et `b`, ou {} — sert au tooltip « PACTE X ↔ Y — EXPIRE AU ROUND N ».
static func find_active_between(pacts, a: int, b: int) -> Dictionary:
	for e in _entries(pacts):
		if typeof(e) != TYPE_DICTIONARY or str(e.get("status", "")) != STATUS_ACTIVE:
			continue
		var pair := _pair(e)
		if pair.has(int(a)) and pair.has(int(b)) and int(a) != int(b):
			return e
	return {}


# Tous MES pactes actifs, dans l'ordre de l'historique (liste compacte de la zone opérateur).
static func my_active(pacts, pid: int) -> Array:
	var out: Array = []
	for e in _entries(pacts):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("status", "")) == STATUS_ACTIVE \
				and partner_of(e, pid) != -9999:
			out.append(e)
	return out


# L'offre PENDANTE qui M'EST ADRESSÉE (jamais la mienne), ou {}. Le serveur garantit qu'il n'y en a
# au plus qu'une par paire, mais plusieurs joueurs peuvent me solliciter : on rend la PLUS ANCIENNE
# (ordre de l'historique) pour que personne ne soit doublé par un arrivant.
static func incoming_offer(pacts, pid: int) -> Dictionary:
	for e in _entries(pacts):
		if typeof(e) != TYPE_DICTIONARY or str(e.get("status", "")) != STATUS_PENDING:
			continue
		if int(e.get("proposed_by", -9999)) == int(pid):
			continue
		if partner_of(e, pid) != -9999:
			return e
	return {}


# MON offre encore en attente de réponse (bouton « OFFRE ENVOYÉE… »), ou {}.
static func outgoing_offer(pacts, pid: int) -> Dictionary:
	for e in _entries(pacts):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("status", "")) == STATUS_PENDING \
				and int(e.get("proposed_by", -9999)) == int(pid):
			return e
	return {}


# Une offre PENDANTE existe-t-elle entre ces deux joueurs, dans un sens ou dans l'autre ?
static func has_pending_between(pacts, a: int, b: int) -> bool:
	for e in _entries(pacts):
		if typeof(e) != TYPE_DICTIONARY or str(e.get("status", "")) != STATUS_PENDING:
			continue
		var pair := _pair(e)
		if pair.has(int(a)) and pair.has(int(b)) and int(a) != int(b):
			return true
	return false


# Ce joueur a-t-il rompu un pacte CE MATCH ? Pilote le petit ⚡ rouge qui reste sur sa chip pour le
# RESTE DE LA PARTIE — la seule sanction d'une trahison est qu'on s'en souvienne.
static func is_traitor(pacts, pid: int) -> bool:
	for e in _entries(pacts):
		if typeof(e) == TYPE_DICTIONARY and str(e.get("status", "")) == STATUS_BROKEN \
				and int(e.get("broken_by", -9999)) == int(pid):
			return true
	return false


# Entrée de pacte par id, ou {} (le toast d'offre garde l'id, pas l'objet : l'état est rediffusé
# entier à chaque action et les anciennes références deviendraient périmées).
static func find_by_id(pacts, pact_id: int) -> Dictionary:
	for e in _entries(pacts):
		if typeof(e) == TYPE_DICTIONARY and int(e.get("id", -1)) == int(pact_id):
			return e
	return {}


# L'offre `pact_id` attend-elle toujours une réponse ? Sert à retirer un toast devenu caduc (le
# proposant a été éliminé, le serveur a soldé l'offre, une course a été perdue…).
static func is_still_pending(pacts, pact_id: int) -> bool:
	var e := find_by_id(pacts, pact_id)
	return not e.is_empty() and str(e.get("status", "")) == STATUS_PENDING
