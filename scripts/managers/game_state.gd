extends Node

var players: Dictionary = {}
var territories: Dictionary = {}
var current_turn: int = 1
var current_player_id: int = 1
var current_phase: int = 1

# --- Pré-game (Lot 1) : exposés pour l'UI à venir (Lots 2/3), pas encore affichés ici. ---
# stage ∈ {"initiative", "placement", "playing"}.
var stage: String = "playing"
var turn_order: Array = []
var setup_index: int = 0
var initiative_rolls: Dictionary = {}
var objectives: Dictionary = {}
var winner_id = null  # null tant que la partie n'est pas gagnée
# RAISON de la victoire (§8.91) — champ PUBLIC de l'état, miroité ici depuis le chantier « Tension &
# fin de partie » (LOT B/F) : "objective" | "elimination" | "abandon" | "timeout" (valeur ADDITIVE).
# Le Rapport Post-Op en tire le sur-titre « TEMPS ÉCOULÉ — VICTOIRE AU SCORE ». "" = serveur/état
# ANTÉRIEUR au champ → aucun sur-titre, le rapport reste celui d'avant le chantier (repli §9.2).
var victory_reason: String = ""

# Carte jouée (registre multi-cartes G5 §8.71 : "classic_42" | "skirmish_atlantic").
# Posée à chaque update_from_json ; défaut classic (rétro-compat serveur antérieur).
var map_id: String = "classic_42"

# Partie issue d'un SALON PRIVÉ (§8.116) — champ PUBLIC de l'état (et de game_over). Sert au client
# à masquer « REJOUER » après une privée (salons éphémères → retour au QG). Défaut false (rétro-compat).
var is_private: bool = false

# Partie CLASSÉE (§8.88) — champ PUBLIC de l'état. Lu EN PARTIE par main.gd (§8.119 : les pouvoirs
# de héros pilotes sont `casual_only`, donc masqués en classée). À ne pas confondre avec
# `NetworkManager.last_match_is_ranked`, qui ne vaut qu'APRÈS le game_over (bilan économique).
var is_ranked: bool = false

# Version du client (auto-updater, CONTEXTE.md §9). Renseignée par le bootloader au démarrage
# à partir de user://client_version.txt (défaut "1.0.0"). Envoyée au serveur dans l'URL du
# WebSocket (network_manager) pour la validation de version stricte côté backend.
var client_version: String = "1.0.0"

# Zone radioactive (§8.27) : modèle CLUSTER {"territories": [tid, ...], "probability": float}.
# Déclarée AVEC un défaut {} pour que la propriété existe TOUJOURS sur le singleton, même avant
# le 1er message réseau. Sans ça, board.gd accédant à GameState.contamination_zone avant synchro
# plante (« Invalid access to property 'contamination_zone' ») et bloque le client sur un écran
# gris (race condition au lancement). Avec ce défaut, board retombe proprement sur un cluster vide.
var contamination_zone: Dictionary = {}

# Chrono SERVEUR (E3 §8.75) : `turn_timer` = { deadline_epoch, budget_seconds, time_bank_cap }
# diffusé dans CHAQUE état ({} si null — tour de bot / hors minuterie / serveur antérieur) ;
# `server_time` = horloge murale du serveur à l'émission (0.0 = serveur antérieur → le HUD
# retombe sur son estimation locale historique, client défensif §9.2).
var turn_timer: Dictionary = {}
var server_time: float = 0.0

# --- TIMER GLOBAL DE PARTIE (chantier « Tension & fin de partie », LOT B) ---
# `match_deadline_epoch` = échéance ABSOLUE de la partie en epoch MUR serveur. Le HUD en dérive son
# compte à rebours global avec le MÊME offset d'horloge que le chrono de tour (§8.31) — aucun
# message périodique n'est envoyé, l'epoch suffit. 0.0 = AUCUNE limite (serveur antérieur au champ,
# ou MATCH_TIME_LIMIT_S=0) → le HUD masque simplement le chip (client défensif §9.2).
var match_deadline_epoch: float = 0.0
# `final_protocol_active` : PROTOCOLE FINAL armé (T-2 min) → bandeau, chrono pulsé rouge,
# mini-classement de départage, et paris d'observateur FERMÉS. Défaut false (rétro-compat).
var final_protocol_active: bool = false

# « Mémoire Tactique » (§8.35 CONTRAT_RESEAU / §8.36 FRONTEND) : statistiques GLOBALES PUBLIQUES de
# la partie, diffusées intégralement par le serveur (non rédigées). Modèle backend `GameStatistics` :
#   - zone_kills_by_player : { "<player_id>": <kills> } — clés STR en JSON (§5), valeurs en float.
#   - zone_stagnation_turns : int — rounds globaux consécutifs sans déplacement de la zone.
# Défaut {} pour que la propriété existe TOUJOURS (même avant le 1er message, ou état Redis antérieur
# sans le champ). Consommée par main.gd (fiche joueur, Journal, Rapport Post-Op — l'ancien tiroir
# « INTEL : ZONE » a disparu à la refonte UI de l'arène), jamais par le HUD en direct
# (Règle d'Or §6.1 : le HUD est une View, le contrôleur résout pseudos + couleurs).
var statistics: Dictionary = {}

# --- PACTES DE NON-AGRESSION (§8.123) ---
# Liste des pactes de la partie TELS QUE LE SERVEUR NOUS LES SERT — c'est-à-dire **REDACTÉE pour
# nous** : les pactes `active`/`broken`/`expired` sont publics, mais les NÉGOCIATIONS
# (`pending`/`declined`) n'y figurent que si NOUS sommes l'un des deux joueurs concernés. Le client
# n'a donc AUCUN filtrage de confidentialité à faire : ce qu'il reçoit, il a le droit de l'afficher.
# Forme d'une entrée : { id, a_id (le PROPOSANT), b_id, proposed_by, status, created_round,
# expires_at_round, ended_round, broken_by } — ⚠️ tous les nombres arrivent en float (piège §5).
# [] = aucun pacte, OU serveur non redéployé → toute l'UI de pacte se masque d'elle-même.
var pacts: Array = []

# --- MODE ÉQUIPES (§8.124) ---
# Id de PLAYLIST ("duo_2v2" | "squad_3v3" | …), **"" = FFA**. C'est LA bascule de tout l'affichage
# d'équipe du client : couleurs appariées, chips groupées, onglet de chat ÉQUIPE, tracker partagé.
# Défaut "" → un serveur non redéployé donne une partie FFA, et TOUTE l'UI d'équipe se masque
# d'elle-même (§9.2) — aucun écran n'a de garde à écrire.
var team_mode: String = ""
# Objectif secret PAR ÉQUIPE, **DÉJÀ REDACTÉ pour nous** : seul celui de NOTRE équipe est lisible,
# les autres arrivent en {"type": "hidden"}. Le client n'a donc AUCUN filtrage à faire — comme pour
# `pacts`. Clés = team_id (⚠️ STRING en JSON, piège §5).
var team_objectives: Dictionary = {}
# Équipe VICTORIEUSE (-1 tant que la partie continue, et TOUJOURS -1 en FFA).
var winning_team_id: int = -1

# --- BATTLE ROYALE (§8.125) ---
# Compteurs PUBLICS des mécaniques d'équipe : `{revives_done, revived, crates, surrender,
# coup_used}`. Le HUD s'en sert pour griser ses boutons (déjà réanimé, déjà voté, coup déjà joué)
# — jamais pour APPLIQUER une règle : le serveur reste l'autorité (§9.5).
var battle_royale: Dictionary = {}
# ORDRES DE TRAHISON, **DÉJÀ REDACTÉS pour nous** : s'il y a une entrée, elle est FORCÉMENT la
# nôtre (le serveur ne sert jamais celle d'autrui). {} = je ne suis pas traître — et c'est
# rigoureusement indiscernable d'une partie SANS traître, ce qui EST la mécanique. Aucun filtrage
# de confidentialité à faire ici, comme pour `pacts`.
var traitors: Dictionary = {}

# Équipe d'un joueur (0 = SANS ÉQUIPE). Lecture UNIQUE de ce champ dans tout le client : les vues
# passent par ici plutôt que de refaire un `int(players[pid].team_id)` chacune de leur côté — le
# piège JSON float (§5) ne se paie ainsi qu'une fois.
func team_of(pid) -> int:
	var p = players.get(str(int(pid)), players.get(int(pid), null))
	if typeof(p) != TYPE_DICTIONARY:
		return 0
	return int(p.get("team_id", 0))

# Le joueur `a` est-il DU MÊME CAMP que `b` ? MIROIR EXACT de `teams.is_friendly` côté serveur —
# **en FFA, ceci vaut « c'est le même joueur »**, ce qui rend toutes les vues neutres sans garde.
func is_friendly(a, b) -> bool:
	if a == null or b == null:
		return false
	if int(a) == int(b):
		return true
	var ta := team_of(a)
	return ta != 0 and ta == team_of(b)

# Ids des coéquipiers de `pid`, LUI EXCLU. Vide en FFA (miroir de `teams.teammates`).
func teammates_of(pid) -> Array:
	var my_team := team_of(pid)
	if my_team == 0:
		return []
	var out: Array = []
	for k in players.keys():
		if int(k) != int(pid) and team_of(k) == my_team:
			out.append(int(k))
	out.sort()
	return out

# { team_id : [player_id, …] } — équipes triées, membres triés. {} en FFA.
func teams_map() -> Dictionary:
	var out: Dictionary = {}
	for k in players.keys():
		var t := team_of(k)
		if t == 0:
			continue
		if not out.has(t):
			out[t] = []
		out[t].append(int(k))
	for t in out.keys():
		out[t].sort()
	return out

func update_from_json(state_data: Dictionary):
	players = state_data.get("players", {})
	territories = state_data.get("territories", {})
	current_turn = state_data.get("current_turn", 1)
	current_player_id = state_data.get("current_player_id", 1)
	# Le serveur (state_schemas.GameState) sérialise la clé "phase" (0 à 5), pas "current_phase".
	current_phase = state_data.get("phase", 0)

	# Champs de préparation de partie.
	stage = state_data.get("stage", "playing")
	turn_order = state_data.get("turn_order", [])
	setup_index = state_data.get("setup_index", 0)
	initiative_rolls = state_data.get("initiative_rolls", {})
	objectives = state_data.get("objectives", {})
	winner_id = state_data.get("winner_id", null)
	victory_reason = str(state_data.get("victory_reason", ""))
	# Carte jouée (registre multi-cartes G5 §8.71) — diffusée dans l'état ; défaut classic
	# (serveur antérieur / état legacy). Consommée par board.gd (masquage) et MapData (adjacence).
	map_id = str(state_data.get("map_id", "classic_42"))
	# Partie issue d'un SALON PRIVÉ (§8.116) — champ PUBLIC ; défaut false (serveur/état antérieur).
	is_private = bool(state_data.get("is_private", false))
	# Partie CLASSÉE (§8.88) — champ PUBLIC de l'état, diffusé depuis toujours mais jamais miroité
	# ici : `NetworkManager.last_match_is_ranked` ne le connaît qu'à la FIN (bloc game_over), ce qui
	# ne sert à rien EN PARTIE. §8.119 en a besoin en cours de jeu (les pouvoirs de héros pilotes
	# sont `casual_only` → boutons masqués en classée). Défaut false = serveur/état antérieur, donc
	# non classée : le pire cas affiche un bouton que le serveur refusera proprement.
	is_ranked = bool(state_data.get("is_ranked", false))
	# NB : `is_bot` (G2 §8.72) est un champ PUBLIC de chaque PlayerState (dans `players`) — lu
	# directement via GameState.players[pid].is_bot par main.gd/hud.gd (pas de miroir dédié ici).
	# Le serveur sérialise la zone radioactive ; défaut {} si absente (état pré-game/placement).
	contamination_zone = state_data.get("contamination_zone", {})
	# « Mémoire Tactique » (§8.35) : statistiques globales publiques (alimente le tiroir Intel, §8.36).
	statistics = state_data.get("statistics", {})
	# PACTES (§8.123) : liste DÉJÀ redactée pour nous par le serveur (cf. la déclaration ci-dessus).
	var pk = state_data.get("pacts", [])
	pacts = pk if typeof(pk) == TYPE_ARRAY else []
	# MODE ÉQUIPES (§8.124) : champs ADDITIFS — absents d'un serveur/état antérieur → "" / {} / -1,
	# donc partie FFA, donc toute l'UI d'équipe reste masquée (§9.2).
	team_mode = str(state_data.get("team_mode", ""))
	var tobj = state_data.get("team_objectives", {})
	team_objectives = tobj if typeof(tobj) == TYPE_DICTIONARY else {}
	var wt = state_data.get("winning_team_id", null)
	winning_team_id = int(wt) if (typeof(wt) == TYPE_FLOAT or typeof(wt) == TYPE_INT) else -1
	var br = state_data.get("battle_royale", {})
	battle_royale = br if typeof(br) == TYPE_DICTIONARY else {}
	var tr_ = state_data.get("traitors", {})
	traitors = tr_ if typeof(tr_) == TYPE_DICTIONARY else {}
	# Chrono SERVEUR (E3 §8.75) : turn_timer peut être null (bot / hors minuterie) → {}.
	var tt = state_data.get("turn_timer", null)
	turn_timer = tt if typeof(tt) == TYPE_DICTIONARY else {}
	server_time = float(state_data.get("server_time", 0.0))
	# Timer GLOBAL de partie (LOT B) : champs ADDITIFS — absents d'un serveur/état antérieur → 0.0 /
	# false, et le HUD n'affiche alors NI chip de rebours global NI bandeau PROTOCOLE FINAL.
	match_deadline_epoch = float(state_data.get("match_deadline_epoch", 0.0))
	final_protocol_active = bool(state_data.get("final_protocol_active", false))
	# Le rafraîchissement de l'UI est piloté par le contrôleur d'arène (main.gd) via le
	# signal NetworkManager.game_state_updated — l'état ne connaît pas l'UI (Règle d'Or §6.1).

# Numéro de joueur SÉQUENTIEL (1..N) pour l'affichage, calculé par rang croissant des
# player_id (= User.id). Découple le libellé affiché de l'id brut de la base, dont les trous
# d'auto-incrément (inscriptions échouées, comptes supprimés) faisaient apparaître des "Joueur
# #1, #3, #4…" sans jamais de #2. Même ordre que la palette du plateau (board.gd trie aussi
# les ids), donc "Joueur N" et sa couleur sont cohérents.
func player_number(pid) -> int:
	var ids: Array = []
	for k in players.keys():
		ids.append(int(k))
	ids.sort()
	var idx := ids.find(int(pid))
	return idx + 1 if idx >= 0 else int(pid)


# =====================================================================
# COMPAGNIE (§8.126) — le TAG, partout où une identité passe
# =====================================================================
# SOURCE UNIQUE du préfixe `[TAG]`. Le serveur diffuse `company_tag` dans chaque `PlayerState`
# (champ PUBLIC, §8.126) ; ces deux fonctions sont le SEUL endroit du client qui décide de sa forme.
# Tous les sites d'identité (chips, draft, VS, kill feed, Post-Op, roster, bandeau de tour) appellent
# `tagged_name` — dupliquer la concaténation ailleurs, c'est se garantir un écran où le tag manque.
#
# ⚠️ Champ ADDITIF : absent d'un état antérieur au chantier ou d'un serveur non redéployé → "" →
# `tagged_name` rend le pseudo INCHANGÉ. Aucun écran n'a de garde à écrire.

# Tag de compagnie d'un joueur, ou "" (bot, sans compagnie, serveur antérieur).
# Clés de `players` en STR (piège JSON float §5) → str(int(pid)), jamais str(pid) sur un float.
func company_tag_of(pid) -> String:
	var p = players.get(str(int(pid)), {})
	if typeof(p) != TYPE_DICTIONARY:
		return ""
	return str(p.get("company_tag", ""))


# Pseudo PRÉFIXÉ de son tag : « [ALFA] Pseudo ». Rend `base_name` tel quel si le joueur n'a pas de
# compagnie — donc sûr à appeler systématiquement, y compris en partie 100 % sans compagnie.
#
# La TEINTE ATTÉNUÉE du tag (charte §8.126 : discret, jamais coloré par faction) n'est pas rendue
# ici : une String n'a pas deux couleurs. Les vues qui PEUVENT la rendre le font avec un nœud dédié
# (`player_chip`) ou une balise BBCode (`main._bb_pseudo`) ; les autres affichent le préfixe dans le
# corps du texte, ce que la charte accepte explicitement (« même corps de texte »).
func tagged_name(pid, base_name: String) -> String:
	var tag := company_tag_of(pid)
	return ("[%s] %s" % [tag, base_name]) if tag != "" else base_name


# =====================================================================
# Couche RPG « Héros » (sprint RPG & Survie)
# =====================================================================
# Les stats du héros sont sérialisées DANS chaque entrée players[pid] par le serveur (PlayerState) :
# hero_pv_current/max, hero_pa, hero_pb (réduction 0..0.30), hero_pp_current/min/max, hero_level,
# hero_regen, is_dead. Champs PUBLICS (aucune redaction → inspection adverse OK, cf. CONTRAT_RESEAU
# « la redaction ne masque que les objectifs »). On les expose normalisés pour le HUD/l'inspecteur.
# Piège JSON float (§5) : les clés de `players` sont des STR ("1","2") et les nombres des float → on
# normalise (int/str) ici pour que les vues n'aient jamais à le refaire.
func hero_of(pid) -> Dictionary:
	var p = players.get(str(int(pid)), null)
	if p == null:
		p = players.get(int(pid), null)
	if not (p is Dictionary):
		return {}
	return {
		"pv_current": int(p.get("hero_pv_current", 0)),
		"pv_max": int(p.get("hero_pv_max", 0)),
		"pa": int(p.get("hero_pa", 0)),
		"pb": float(p.get("hero_pb", 0.0)),
		"pp_current": int(p.get("hero_pp_current", 0)),
		"pp_min": int(p.get("hero_pp_min", 0)),
		"pp_max": int(p.get("hero_pp_max", 0)),
		"level": int(p.get("hero_level", 1)),
		"regen": float(p.get("hero_regen", 0.0)),
		"is_dead": bool(p.get("is_dead", false)),
		"faction": str(p.get("faction", "")),
		# Barre d'XP du panneau héros (snapshot méta-jeu, statique pendant le match ; 0/0 = niveau max
		# ou état pré-RPG → la vue masque la barre). Voir PlayerState.hero_xp_in_level/for_level.
		"xp_in_level": int(p.get("hero_xp_in_level", 0)),
		"xp_for_level": int(p.get("hero_xp_for_level", 0)),
	}


# Vrai si le joueur a un héros INITIALISÉ (pv_max > 0). Faux pour un état pré-RPG / pré-game : le HUD
# masque alors le panneau héros (rétro-compat, pas de jauges à 0 trompeuses).
func has_hero(pid) -> bool:
	return hero_of(pid).get("pv_max", 0) > 0
