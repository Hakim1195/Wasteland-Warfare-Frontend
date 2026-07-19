extends Node

signal server_connected
signal rooms_loaded(rooms: Array)
signal lobby_action_success(action: String, data: Dictionary)
signal lobby_error(message: String)

# --- Signaux temps réel (arène) ---
# Émis après chaque mise à jour de l'état de jeu reçue du serveur. L'UI (HUD, plateau)
# s'y abonne au lieu de lire le réseau en direct (Règle d'Or §6.1 : découplage par signaux).
signal game_state_updated
# Chrono SERVEUR (E3 §8.75) : échéance epoch + budget + raison ("turn_start"/"phase_change"/
# "time_bank") + horloge serveur (offset client). Émis à chaque message léger `timer_update`.
signal timer_updated(deadline_epoch: float, budget_seconds: int, reason: String, server_time: float)
# Émis pour chaque évènement de jeu renvoyé par le moteur (résultat de combat, déploiement…).
signal game_event(event: Dictionary)
# Émis quand le serveur refuse une action (ex: "Ce n'est pas votre tour").
signal game_error(message: String)
# Émis quand un joueur quitte la partie.
signal player_left(player_id)
# Émis quand la composition de la salle d'attente change (joueurs connectés + prêts + pseudos).
# `usernames` = { "player_id": "pseudo" } (clés string, piège JSON §5) pour afficher les VRAIS noms.
signal lobby_state_updated(players: Array, ready: Array, usernames: Dictionary)
# Échéance UNIX (s) du remplissage IA (G2 §8.72), lue par waiting_room.gd ; -1 = aucun fill armé.
# Propriété (et non 4ᵉ arg du signal) pour ne pas casser les écouteurs existants de lobby_state.
var last_bot_fill_at: float = -1.0
# Effectif CIBLE de la salle (§8.87) = GameRoom.max_players, lu par waiting_room.gd pour
# « X / Y joueurs ». -1 = champ absent (serveur antérieur) → repli sur l'affichage historique.
# Propriété (et non arg de signal) : même pattern que last_bot_fill_at.
var last_max_players: int = -1
# Révélation des objectifs de fin de partie (E11 §8.83) — bloc PUBLIC du game_over :
# [{ player_id, username, description, completed }] ordonné par rankings. [] avant la fin
# (ou serveur antérieur) ; consommé par le Rapport Post-Op (podium).
var last_objectives_reveal: Array = []
# Émis quand la partie démarre (l'état initial est déjà appliqué à GameState).
signal game_started_signal
# Émis quand un joueur verrouille sa faction pendant le Draft (CONTEXTE.md §3, étape de sélection).
signal faction_locked(player_id, faction_id)
# Resynchronisation du Draft (G2 durci) : réponse PRIVÉE du serveur à l'action get_draft.
# `locked` = { "player_id": "faction_id" } (clés string, piège JSON §5) — TOUS les verrouillages
# déjà actés (bots compris), y compris ceux diffusés pendant la transition de scène du client.
signal draft_state_received(locked: Dictionary)
# Échéance UNIX (s) d'auto-verrouillage du draft (G2 durci) : passé ce délai, le serveur
# verrouille d'office les retardataires. Mise à jour par game_started ET draft_state ; -1 = aucune.
# Propriété (et non arg de signal) : même pattern que last_bot_fill_at.
var last_draft_deadline_at: float = -1.0
# Émis quand un joueur abandonne la partie (Fallen Empire, CONTEXTE.md §8.20). L'état diffusé
# avec le message (is_active=false, tour éventuellement déjà passé) est appliqué à GameState
# AVANT l'émission — les écouteurs peuvent donc lire player_number/players directement.
signal player_abandoned(player_id: int)
# Espionnage (Shadow Hunters, §8.3) : réponse PRIVÉE du serveur à l'action spy_objective.
# Reçue uniquement par l'espion (le secret n'est jamais diffusé). target_player_id = id de la
# cible espionnée ; description = libellé serveur (anglais invariant, REPLI) ; objective =
# forme STRUCTURÉE {type, params, volets} dont le client compose le libellé TRADUIT (§8.104).
# `objective` est {} sur un serveur antérieur → repli automatique sur `description`.
signal spy_result(target_player_id: int, description: String, objective: Dictionary)
# Chat de salle (§8.33) : message relayé par le serveur, ESTAMPILLÉ (sender_id + sender_name réels,
# pas d'usurpation). tab ∈ {"general","private"} ; target_id renseigné uniquement en privé (sinon -1).
signal chat_message_received(tab: String, sender_id: int, sender_name: String, text: String, target_id: int)
# Classement mondial (R3 — §9.2) : réponse à fetch_leaderboard. `entries` = liste d'objets triés par
# le serveur (clés canoniques rank/username/level/wins + alias historiques niveau/stats_victoires…).
# `me` = bloc {rank, username, level, wins} de l'opérateur courant si la requête est authentifiée,
# sinon dict VIDE. Le client reste tolérant à l'ancienne forme (liste plate sans `me`).
signal leaderboard_loaded(entries: Array, me: Dictionary)
# --- Profil & statistiques joueur (R2 — CONTRAT_RESEAU.md §9.1) ---
# Réponse à fetch_profile_stats : dict aux clés canoniques (level, xp, xp_max, games_played, wins,
# losses, heaviest_toll, favorite_faction, credits, username) — lu défensivement par profile.gd.
signal profile_stats_loaded(data: Dictionary)
# Réponse à fetch_profile_history : liste d'objets {win, faction_id, detail} (le plus récent d'abord).
# ⚠️ Émis UNIQUEMENT pour une requête NON FILTRÉE (aucun filtre, offset 0) — cf. la note de
# fetch_profile_history : ses écouteurs (main_menu, top_nav) veulent « les N derniers matchs »
# tout court, jamais une liste filtrée demandée par un autre écran.
signal profile_history_loaded(entries: Array)
# Chantier J — même réponse, mais accompagnée de la REQUÊTE qui l'a produite
# ({limit, offset, wins_only, ranked_only}). Indispensable à l'écran Profil, qui émet plusieurs
# requêtes d'historique de natures différentes (liste filtrée paginée + série RP des classées) :
# sans l'écho de la requête, deux réponses en vol se rangeraient dans la mauvaise vue.
signal profile_history_page_loaded(entries: Array, request: Dictionary)
# --- Profil : FINANCES & PASS (refonte Profil, chantier J) ---
# Réponse à fetch_profile_finance : dict {balance, total_earned, total_spent, by_reason,
# entries[], hero_potential[], constants}. `request` échoie la requête (pagination « AFFICHER PLUS »).
signal profile_finance_loaded(data: Dictionary, request: Dictionary)
# Réponse à fetch_profile_pass : dict {active, expires_at, tier_id, tiers[], granted_items[], gains}.
signal profile_pass_loaded(data: Dictionary)
# --- Héros / Roster (sprint RPG & Survie — écran « Personnages ») ---
# Réponse à fetch_heroes : liste des 10 héros de l'opérateur (1 par faction), chacun avec stats
# détaillées (au niveau courant ET au niveau 100), progression XP et paliers (GET /api/v1/heroes,
# authentifié). Lue défensivement par characters_screen.gd (int() sur les nombres, piège float §5).
signal heroes_loaded(heroes: Array)
# --- Boutique / Inventaire / Économie (R1 — CONTRAT_RESEAU.md §9.3) ---
# Réponse à fetch_shop_catalog : liste d'articles
# {id, category, price, name_key, desc_key, currency_type, grant_amount, hero_key}.
# `currency_type` ∈ {"virtual" (Coins), "fiat" (argent réel)} ; `grant_amount` = Coins offerts par
# un pack fiat (null sinon) ; `hero_key` = faction liée à un skin (null sinon).
signal shop_catalog_loaded(items: Array)
# Réponse à fetch_shop_inventory : dict {credits: int, items: { "<item_id>": int }, has_active_pass: bool}.
signal shop_inventory_loaded(data: Dictionary)
# Achat réussi : nouveau solde + inventaire à jour {credits, items}. Émis par purchase_item.
signal shop_purchase_success(data: Dictionary)
# Achat refusé par le serveur (HTTP 400) : message d'erreur prêt à afficher (« Crédits insuffisants »…).
signal shop_purchase_failed(message: String)
# Rotation gratuite hebdomadaire des factions payantes (M3 §8.66) :
# { week_key, free_faction_ids: [id, id], rotates_at } — émis par fetch_shop_rotation.
signal shop_rotation_loaded(data: Dictionary)
# Skin équipé/déséquipé (M5 §8.69) : réponse = inventaire complet (forme GET /shop/inventory,
# bloc `equipped` à jour). Échec (400) → message serveur.
signal skin_equipped(data: Dictionary)
signal skin_equip_failed(message: String)
# Re-queue en 1 clic (G3 §8.70) : échec de la chaîne quitter→radar→rejoindre/créer (l'écran
# appelant retombe sur le lobby). Le SUCCÈS ne signale rien : requeue() navigue lui-même.
signal requeue_failed(message: String)
# Missions quotidiennes/hebdos (M2 §8.65) : { daily: [...], weekly: [...], daily_resets_at,
# weekly_resets_at, claimable_count } — émis par fetch_missions.
signal missions_loaded(data: Dictionary)
# Claim réussi : { coins_balance, reward_paid, pass_bonus_applied } — émis par claim_mission.
signal mission_claimed(data: Dictionary)
# Claim refusé (HTTP 400/401) : message d'erreur prêt à afficher.
signal mission_claim_failed(message: String)
# Fin de partie (Économie §8.47) : le serveur diffuse `game_over` avec le détail des gains par joueur.
# `match_rewards` = { "<player_id:str>": { match_points, xp_earned, coins_earned, level_up_triggered,
# new_level, current_xp, xp_to_next_level, levels_gained } } (toutes valeurs entières — piège JSON §5).
# `rankings` = liste ordonnée des player_id (1er d'abord, départage 2e place côté serveur).
signal match_over(winner_id: int, match_type: String, rankings: Array, match_rewards: Dictionary)

# Dernier détail de récompenses reçu (cache) : lu par main.gd si le rapport Post-Op est déjà affiché
# quand le game_over arrive (course réseau état/clôture). Vidé au démarrage d'une partie.
var last_match_rewards: Dictionary = {}
# Partie CLASSÉE (§8.88) — bloc PUBLIC du game_over. Pilote le Rapport Post-Op : « POINTS DE MATCH »
# en classée, « PARTIE NON CLASSÉE » sinon. Propriété (et non arg de signal, pattern
# last_objectives_reveal) → la signature de match_over reste inchangée.
# ⚠️ Défaut `true` VOLONTAIRE : un serveur ANTÉRIEUR n'envoie pas le champ mais crédite ENCORE les
# points de classement à toutes les parties — afficher « non classée » y serait un MENSONGE.
var last_match_is_ranked: bool = true

var socket = WebSocketPeer.new()
var connected = false
# Valeurs de PRODUCTION par défaut, surchargées au boot par ApiConfig (§P1, source unique d'URL).
var websocket_url = "wss://api.wasteland-warfare.com/ws/"
var base_url = "https://api.wasteland-warfare.com/api/v1"
# Salle actuellement rejointe (renseignée par le lobby, lue par la salle d'attente / l'arène).
var current_room_id: String = ""
# Id de salle en cours de jointure (mémorisé pour le renvoyer au signal de succès).
var _pending_join_id: int = -1

func _ready() -> void:
	# Hôtes backend : source unique ApiConfig (repli sur la prod si l'autoload manque). §P1
	var cfg := get_node_or_null("/root/ApiConfig")
	if cfg != null:
		base_url = cfg.http_host + "/api/v1"
		websocket_url = cfg.ws_host + "/ws/"

# =========================================================
# PARTIE 1 : MULTIJOUEUR TEMPS RÉEL (WEBSOCKET)
# =========================================================

func connect_to_server(room_id: String):
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN or socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return

	# Le serveur écoute sur /ws/{room_id}/{player_id}. On a besoin de notre ID numérique.
	if AuthManager.user_id < 0:
		print("NETWORK: player_id inconnu, connexion WebSocket impossible. As-tu bien fini le login ?")
		lobby_error.emit(tr("NET_IDENTITY_NOT_LOADED"))
		return

	# Version du client (auto-updater §9) jointe en query string : le serveur la compare à
	# version.json et REJETTE (close 4000) tout client dont la version diffère (validation stricte).
	var cv := "1.0.0"
	if has_node("/root/GameState"):
		cv = str(GameState.client_version)
	var final_url = websocket_url + room_id + "/" + str(AuthManager.user_id) + "?client_version=" + cv.uri_encode()
	# On journalise l'URL SANS le token (le JWT ne doit jamais traîner dans les logs).
	print("NETWORK: Tentative de connexion WebSocket vers " + final_url)

	# Authentification du handshake (C2/M1) : le serveur EXIGE le JWT en query string (?token=)
	# et ferme en 4001 sinon. L'en-tête Authorization ci-dessous est conservé par compat mais
	# n'est PAS lu par le serveur (les WebSocketPeer navigateurs ne portent pas d'en-têtes).
	if AuthManager.jwt_token != "":
		final_url += "&token=" + str(AuthManager.jwt_token).uri_encode()

	var tls_options = TLSOptions.client_unsafe()

	if AuthManager.jwt_token != "":
		var headers = ["Authorization: Bearer " + AuthManager.jwt_token]
		socket.set_handshake_headers(headers)
	
	var err = socket.connect_to_url(final_url, tls_options)
	
	if err == OK:
		set_process(true)

func _process(_delta):
	socket.poll()
	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not connected:
			print("NETWORK: connecté au WebSocket.")
			connected = true
			server_connected.emit()

		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet()
			var json = JSON.parse_string(packet.get_string_from_utf8())
			if typeof(json) == TYPE_DICTIONARY:
				_handle_server_message(json)

	elif state == WebSocketPeer.STATE_CLOSED:
		# Code applicatif 4000 = version refusée par le serveur (validation stricte §9). On le
		# remonte clairement au joueur (l'arène/lobby affiche le message) ; le bootloader GARANTIT
		# désormais la bonne version (Hard Block, plus de mode hors ligne — §9.1), donc ce cas ne
		# survient en pratique que si la version serveur change ENTRE le boot et la connexion.
		var code := socket.get_close_code()
		if code == 4000:
			var reason := socket.get_close_reason()
			var msg := reason if reason != "" else tr("NET_VERSION_OUTDATED")
			print("NETWORK: connexion refusée par le serveur (version) : " + msg)
			game_error.emit(msg)
			lobby_error.emit(msg)
		elif code == 4001 or code == 4003:
			# Codes applicatifs du handshake authentifié (C2/M1) : 4001 = token absent/invalide/
			# expiré ou identité incohérente ; 4003 = pas membre de la salle demandée. On remonte
			# le message serveur (raison ASCII) tel quel — l'écran courant l'affiche en rouge.
			var auth_reason := socket.get_close_reason()
			var auth_msg := auth_reason if auth_reason != "" else tr("NET_SESSION_INVALID")
			print("NETWORK: connexion refusée par le serveur (auth %d) : %s" % [code, auth_msg])
			game_error.emit(auth_msg)
			lobby_error.emit(auth_msg)
		connected = false
		set_process(false)

# Aiguille les messages reçus du serveur selon leur champ "type".
# Format serveur (router.py) : {"type": "action_result", "event": {...}, "state": {...}}
#                              {"type": "error", "message": "..."}
#                              {"type": "player_disconnected", "player_id": ...}
func _handle_server_message(msg: Dictionary) -> void:
	var msg_type = msg.get("type", "")
	match msg_type:
		"action_result":
			if msg.has("state") and has_node("/root/GameState"):
				GameState.update_from_json(msg["state"])
			game_state_updated.emit()
			if msg.has("event"):
				game_event.emit(msg["event"])
		"error":
			var err_msg = str(msg.get("message", tr("NET_UNKNOWN_ERROR")))
			print("NETWORK: action refusée par le serveur : " + err_msg)
			game_error.emit(err_msg)
		"player_disconnected":
			player_left.emit(msg.get("player_id"))
		"lobby_state":
			# Remplissage IA (G2 §8.72) : échéance UNIX (s) du fill, ou null. Stockée en propriété
			# (le signal garde sa signature à 3 args) — waiting_room.gd la lit pour son compte à rebours.
			var bfa = msg.get("bot_fill_at", null)
			last_bot_fill_at = float(bfa) if (typeof(bfa) == TYPE_FLOAT or typeof(bfa) == TYPE_INT) else -1.0
			# Effectif de la salle (§8.87) : champ ADDITIF — absent d'un serveur antérieur → -1
			# (waiting_room.gd retombe alors sur son affichage historique).
			var mp = msg.get("max_players", null)
			last_max_players = int(mp) if (typeof(mp) == TYPE_FLOAT or typeof(mp) == TYPE_INT) else -1
			lobby_state_updated.emit(msg.get("players", []), msg.get("ready", []), msg.get("usernames", {}))
		"game_over":
			# La victoire est déjà gérée via winner_id dans l'état ; ici on relaie le RÉSULTAT
			# ÉCONOMIQUE (points/XP/Coins, §8.47) pour le Rapport Post-Op animé. Piège JSON §5 :
			# les ids/nombres arrivent en float → int() ; les clés de match_rewards restent string.
			# E11 §8.83 : match_rewards est désormais REDACTÉ par destinataire (notre seule clé) —
			# le code ci-dessous piochait déjà sa propre clé, rien ne change. Le bloc PUBLIC
			# objectives_reveal est mémorisé en propriété (signal inchangé, pattern last_bot_fill_at).
			var reveal = msg.get("objectives_reveal", [])
			last_objectives_reveal = reveal if typeof(reveal) == TYPE_ARRAY else []
			# §8.88 — is_ranked PUBLIC. Champ ADDITIF : ABSENT d'un serveur antérieur → défaut
			# `true` (ce serveur-là crédite encore le ladder sur toutes les parties : le repli
			# reproduit son comportement réel plutôt que d'annoncer à tort « non classée »).
			last_match_is_ranked = bool(msg.get("is_ranked", true))
			var rewards: Dictionary = msg.get("match_rewards", {})
			last_match_rewards = rewards
			game_event.emit({"event_type": "game_over", "winner_id": msg.get("winner_id"),
				"match_type": msg.get("match_type")})
			match_over.emit(
				int(msg.get("winner_id", -1)),
				str(msg.get("match_type", "")),
				msg.get("rankings", []),
				rewards)
		"game_started":
			# La partie démarre : on applique l'état initial puis on signale le départ.
			# L'échéance d'auto-verrouillage du draft (G2 durci) accompagne le message.
			var gda = msg.get("draft_deadline_at", null)
			last_draft_deadline_at = float(gda) if (typeof(gda) == TYPE_FLOAT or typeof(gda) == TYPE_INT) else -1.0
			if msg.has("state") and has_node("/root/GameState"):
				GameState.update_from_json(msg["state"])
			game_state_updated.emit()
			game_started_signal.emit()
		"faction_locked":
			# Un joueur a verrouillé sa faction pendant le Draft. On relaie aux écouteurs
			# (faction_selection.gd) le couple (player_id, faction_id).
			faction_locked.emit(msg.get("player_id"), msg.get("faction_id", ""))
		"draft_state":
			# Resynchronisation du Draft (G2 durci) : photographie COMPLÈTE des verrouillages —
			# rattrape les faction_locked émis pendant la transition de scène (bots notamment).
			var dda = msg.get("draft_deadline_at", null)
			last_draft_deadline_at = float(dda) if (typeof(dda) == TYPE_FLOAT or typeof(dda) == TYPE_INT) else -1.0
			var locked_map = msg.get("locked", {})
			draft_state_received.emit(locked_map if typeof(locked_map) == TYPE_DICTIONARY else {})
		"player_abandoned":
			# Fallen Empire (§8.20) : un joueur a abandonné. On applique l'état diffusé
			# (is_active=false, tour éventuellement passé au joueur actif suivant), puis
			# on relaie : refresh générique + signal dédié pour le journal/HUD (main.gd).
			if msg.has("state") and has_node("/root/GameState"):
				GameState.update_from_json(msg["state"])
			game_state_updated.emit()
			# Piège Godot des ids JSON (§5) : player_id arrive en float -> int().
			player_abandoned.emit(int(msg.get("player_id", -1)))
		"spy_result":
			# Espionnage (Shadow Hunters) : message PRIVE recu uniquement par l espion.
			# Piege des ids JSON : target_player_id arrive en float -> int().
			# §8.104 : `objective` (forme structuree) est ADDITIF — absent d un serveur
			# anterieur -> {} et le consommateur retombe sur `description`.
			var spy_obj = msg.get("objective", {})
			spy_result.emit(int(msg.get("target_player_id", -1)), str(msg.get("description", "")),
				spy_obj if typeof(spy_obj) == TYPE_DICTIONARY else {})
		"timer_update":
			# Chrono SERVEUR (E3 §8.75) : (ré)armement de minuterie ou extension Time Bank.
			# reason ∈ {"turn_start", "phase_change", "time_bank"}. main.gd relaie au HUD.
			timer_updated.emit(
				float(msg.get("deadline_epoch", 0.0)),
				int(msg.get("budget_seconds", 0)),
				str(msg.get("reason", "")),
				float(msg.get("server_time", 0.0)))
		"chat_message":
			# Chat de salle (§8.33) : relais serveur estampillé. Ids JSON en float -> int() (piège §5).
			chat_message_received.emit(
				str(msg.get("tab", "general")),
				int(msg.get("sender_id", -1)),
				str(msg.get("sender_name", "")),
				str(msg.get("text", "")),
				int(msg.get("target_id", -1)))
		_:
			# Compatibilité : ancien format brut {"state": {...}} sans enveloppe.
			if msg.has("state") and has_node("/root/GameState"):
				GameState.update_from_json(msg["state"])
				game_state_updated.emit()

# =========================================================
# ENVOI D'ACTIONS DE JEU (arène)
# =========================================================

# Envoi générique d'une action au moteur via WebSocket.
# action_type ∈ {"init_game", "deploy_units", "attack_territory", "move_units", "play_card", "pass_turn"}
# Idempotence (correctif « double déduction de PV ») : chaque action VOULUE reçoit un action_id
# UNIQUE = nonce de session + compteur monotone. Le serveur REJETTE un doublon portant le MÊME id
# (retransmission WS, rejeu) → une attaque rejouée ne re-résout jamais le duel des héros. Le nonce est
# fixé une fois par session d'app (autoload persistant) : le compteur n'est jamais remis à zéro dans
# une même exécution ET le nonce diffère d'une exécution à l'autre → aucune action légitime n'est
# faussement rejetée, même après une reconnexion à une partie dont le serveur a gardé l'état (Redis).
var _action_seq: int = 0
var _action_nonce: String = ""

func _next_action_id() -> String:
	if _action_nonce == "":
		_action_nonce = "%d-%d" % [int(Time.get_unix_time_from_system()), randi()]
	_action_seq += 1
	return "%s-%d" % [_action_nonce, _action_seq]

func send_action(action_type: String, payload: Dictionary = {}) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("NETWORK: WebSocket non ouvert, action '" + action_type + "' ignorée.")
		game_error.emit(tr("NET_NOT_CONNECTED"))
		return
	# On DUPLIQUE la charge utile pour y injecter action_id SANS muter le dict de l'appelant.
	var pl := payload.duplicate(true)
	pl["action_id"] = _next_action_id()
	var message = {"action": action_type, "payload": pl}
	socket.send_text(JSON.stringify(message))

# Demande au serveur de générer/initialiser la partie.
func send_init_game() -> void:
	send_action("init_game", {})

# Signale au serveur que le joueur est prêt (ou plus prêt) dans la salle d'attente.
func send_ready(is_ready: bool) -> void:
	send_action("ready" if is_ready else "unready", {})

# Demande au serveur l'état courant de la salle d'attente.
func request_lobby_state() -> void:
	send_action("get_lobby", {})

# Verrouille le choix de faction du joueur pendant le Draft (CONTEXTE.md §3/§4.3).
# Le serveur est censé enregistrer le choix puis rediffuser un message {"type":"faction_locked",
# "player_id":..., "faction_id":...} à toute la salle (relayé via le signal faction_locked).
func send_faction_choice(faction_id: String) -> void:
	send_action("faction_choice", {"faction_id": faction_id})

# Demande la photographie du Draft (G2 durci) : le serveur répond en PRIVÉ par un message
# "draft_state" (relayé via draft_state_received). Appelé par faction_selection à son _ready
# pour rattraper les faction_locked diffusés pendant la transition de scène.
func request_draft_state() -> void:
	send_action("get_draft", {})

# Chat de salle (§8.33) : envoi à PLAT (contrat principal) — {"type":"send_chat_message", tab, text,
# target_id}. tab ∈ {"general","private"} ; target_id REQUIS en privé. Le serveur estampille
# l'identité réelle (pas d'usurpation) et renvoie un message "chat_message" (écho à l'expéditeur
# compris) → on n'affiche jamais nos propres messages localement, on attend cet écho.
func send_chat_message(tab: String, text: String, target_id: int = -1) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		game_error.emit(tr("NET_NOT_CONNECTED"))
		return
	var message := {"type": "send_chat_message", "tab": tab, "text": text}
	if tab == "private" and target_id >= 0:
		message["target_id"] = target_id
	socket.send_text(JSON.stringify(message))

# =========================================================
# PARTIE 2 : NAVIGATEUR DE SALLES (HTTP REST)
# =========================================================

# Fonction utilitaire pour créer des requêtes sécurisées avec le Token
func _send_api_request(endpoint: String, method: int, data: Dictionary = {}, callback: Callable = Callable()):
	var http = HTTPRequest.new()
	add_child(http)
	http.set_tls_options(TLSOptions.client_unsafe())
	
	if callback.is_valid():
		http.request_completed.connect(callback.bind(http))
		
	var headers = [
		"Authorization: Bearer " + AuthManager.jwt_token,
		"Content-Type: application/json",
		# Empêche Godot/les proxys de servir une réponse en cache (liste des salles toujours fraîche).
		"Cache-Control: no-cache"
	]
	
	var json_string = JSON.stringify(data) if not data.is_empty() else ""
	var err = http.request(base_url + endpoint, headers, method, json_string)
	
	if err != OK:
		lobby_error.emit(tr("NET_SERVER_UNREACHABLE"))
		http.queue_free()

# 1. Récupérer les salles
func fetch_rooms():
	_send_api_request("/lobby/rooms", HTTPClient.METHOD_GET, {}, _on_rooms_fetched)

func _on_rooms_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_ARRAY:
			rooms_loaded.emit(data)
	else:
		lobby_error.emit(tr("NET_ROOMS_FETCH_FAILED"))

# 2. Créer une salle
# max_players par défaut = 6 (capacité maximale autorisée, cf. §4 : 3 à 6 joueurs).
# Auparavant figé à 3, ce qui bloquait toutes les salles à 3 places.
func create_room(is_private: bool, secret_code: String = "", max_players: int = 6,
		map_id: String = "classic_42", is_ranked: bool = false):
	var payload = {
		"max_players": max_players,
		"is_private": is_private,
		"secret_code": secret_code if is_private else "", # <-- Correction ici ("" au lieu de null)
		# Carte jouée (G5 §8.71) — validée serveur (400 si inconnue), max_players clampé par carte.
		"map_id": map_id,
		# Mode CLASSÉE (§8.88) : seule une partie classée crédite le ladder. Le SERVEUR fait
		# autorité — il force l'effectif à 5 quel que soit max_players ci-dessus, et refuse (400)
		# une carte qui ne supporte pas 5 joueurs. Défaut false (paramètre en QUEUE de signature →
		# les appelants historiques restent valides).
		"is_ranked": is_ranked,
	}
	_send_api_request("/lobby/rooms", HTTPClient.METHOD_POST, payload, _on_room_created)

func _on_room_created(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 200 or response_code == 201:
		lobby_action_success.emit("create", data)
	else:
		lobby_error.emit(tr("NET_ROOM_CREATE_FAILED"))

# 3. Rejoindre une salle
func join_room(room_id: int):
	# Sécurité : on garantit un entier (un float issu du JSON donnerait une URL "/rooms/11.0/join").
	room_id = int(room_id)
	# On mémorise l'id ciblé (évite le piège d'ordre des bind chaînés) pour le renvoyer au succès.
	_pending_join_id = room_id
	_send_api_request("/lobby/rooms/" + str(room_id) + "/join", HTTPClient.METHOD_POST, {}, _on_room_joined)

func _on_room_joined(_result, response_code, _headers, _body, http_node):
	http_node.queue_free()
	if response_code == 200:
		lobby_action_success.emit("join", {"id": _pending_join_id})
	else:
		lobby_error.emit(tr("NET_ROOM_JOIN_FAILED"))

# 4. Classement mondial (R3 — §9.2) : GET /leaderboard?limit=&offset= (public ; enrichi du bloc `me`
# si le token est joint). Le serveur trie par victoires décroissantes et renvoie une enveloppe
# {entries, me}. On relaie (entries, me) via leaderboard_loaded — l'écran mappe les champs.
# Bloc saison { id, ends_at } de la DERNIÈRE réponse leaderboard (M6 §8.68), lu par leaderboard.gd.
# Propriété (et non un 3ᵉ argument de signal) : leaderboard_loaded garde sa signature (entries, me)
# pour ses écouteurs existants (main_menu top-3). Vide si le backend est antérieur à M6.
var last_leaderboard_season: Dictionary = {}

# `scope` (M6 §8.68) : "season" (défaut serveur — ladder saisonnier avec divisions) | "lifetime"
# (comportement historique §9.2). Les écrans legacy qui n'envoient pas scope reçoivent le défaut.
# `division`/`tier` (§8.98) : filtre de TRANCHE du ladder saisonnier (navigation par division de
# l'écran Classement — division ∈ BRONZE/ARGENT/OR/PLATINE/ELITE, tier ∈ I/II/III, "" = pas de
# filtre). ADDITIF : omis quand vides ; un backend antérieur IGNORE ces query params inconnus
# (FastAPI) et renvoie la liste globale — le client le détecte et retombe sur l'affichage plat.
func fetch_leaderboard(limit: int = 20, offset: int = 0, scope: String = "season",
		division: String = "", tier: String = ""):
	var url := "/leaderboard?limit=%d&offset=%d&scope=%s" % [limit, offset, scope]
	if division != "":
		url += "&division=%s" % division
		if tier != "":
			url += "&tier=%s" % tier
	_send_api_request(url, HTTPClient.METHOD_GET, {}, _on_leaderboard_fetched)

func _on_leaderboard_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code != 200:
		lobby_error.emit(tr("NET_LEADERBOARD_FETCH_FAILED"))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	# Forme CANONIQUE §9.2 : enveloppe {entries, me} (+ bloc `season` depuis M6).
	if typeof(data) == TYPE_DICTIONARY:
		var entries = data.get("entries", [])
		var me = data.get("me", {})
		if typeof(entries) != TYPE_ARRAY:
			entries = []
		if typeof(me) != TYPE_DICTIONARY:
			me = {}
		var season = data.get("season", {})
		last_leaderboard_season = season if typeof(season) == TYPE_DICTIONARY else {}
		leaderboard_loaded.emit(entries, me)
	# Tolérance : ancien backend (avant redéploiement VPS) → liste plate sans bloc `me`.
	elif typeof(data) == TYPE_ARRAY:
		last_leaderboard_season = {}
		leaderboard_loaded.emit(data, {})

# =========================================================
# PARTIE 3 : PROFIL & STATISTIQUES (R2 — §9.1)
# =========================================================

# 5. Statistiques joueur : GET /profile/stats (authentifié). Relaie le dict brut via
# profile_stats_loaded ; l'écran Profil le lit défensivement (clés canoniques + alias).
func fetch_profile_stats():
	_send_api_request("/profile/stats", HTTPClient.METHOD_GET, {}, _on_profile_stats_fetched)

func _on_profile_stats_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			profile_stats_loaded.emit(data)
	else:
		lobby_error.emit(tr("NET_PROFILE_FETCH_FAILED"))

# 6. Historique récent : GET /profile/history (authentifié). Liste {win, faction_id, detail, …}.
# Chantier J — filtres et pagination ADDITIFS, tous à défaut NEUTRE : l'appel historique
# `fetch_profile_history(5)` (main_menu, top_nav) produit EXACTEMENT la même requête qu'avant.
func fetch_profile_history(limit: int = 5, offset: int = 0, wins_only: bool = false,
		ranked_only: bool = false):
	var path := "/profile/history?limit=%d&offset=%d" % [limit, offset]
	if wins_only:
		path += "&wins_only=true"
	if ranked_only:
		path += "&ranked_only=true"
	# La requête est BINDÉE au callback : le signal ne rappelant pas ses paramètres, c'est le seul
	# moyen pour un écran de savoir à quelle demande répond une liste (même piège que la file de
	# requêtes du leaderboard, §8.95).
	var request := {"limit": limit, "offset": offset,
					"wins_only": wins_only, "ranked_only": ranked_only}
	_send_api_request(path, HTTPClient.METHOD_GET, {}, _on_profile_history_fetched.bind(request))

# ⚠️ ORDRE DES PARAMÈTRES LIÉS : `_send_api_request` fait `callback.bind(http)` sur un callable
# DÉJÀ lié par `.bind(request)`. Or un second bind INSÈRE ses arguments AVANT ceux du premier
# (f.bind(a).bind(b) → f(args…, b, a)) : `http_node` arrive donc AVANT `request`. Inverser les deux
# fait échouer la toute première ligne (`http_node.queue_free()` sur un Dictionary) — la requête ne
# serait jamais relayée ET le nœud HTTPRequest fuirait à chaque appel.
func _on_profile_history_fetched(_result, response_code, _headers, body, http_node, request):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_ARRAY:
			# ⚠️ Le signal LEGACY n'est émis que pour une requête NON FILTRÉE. Ses écouteurs
			# (main_menu, top_nav — ce dernier monté sur TOUS les écrans, Profil COMPRIS) veulent
			# « les N derniers matchs » ; leur servir la liste filtrée demandée par l'onglet
			# HISTORIQUE ou la courbe RP leur ferait afficher un héros / un récap FAUX.
			if not bool(request.get("wins_only", false)) \
					and not bool(request.get("ranked_only", false)) \
					and int(request.get("offset", 0)) == 0:
				profile_history_loaded.emit(data)
			profile_history_page_loaded.emit(data, request)
	else:
		lobby_error.emit(tr("NET_HISTORY_FETCH_FAILED"))


# 7. FINANCES (chantier J) : GET /profile/finance?limit&offset (authentifié). Livre de comptes
# Coins — solde, gains/dépenses par source, transactions, potentiel de gain par personnage.
# ⚠️ Route ABSENTE d'un serveur non redéployé → 404 : on émet alors un dict VIDE plutôt qu'une
# erreur globale, et l'écran affiche « DONNÉES INDISPONIBLES » (dégradation propre, jamais un crash).
func fetch_profile_finance(limit: int = 20, offset: int = 0):
	var request := {"limit": limit, "offset": offset}
	_send_api_request("/profile/finance?limit=%d&offset=%d" % [limit, offset],
		HTTPClient.METHOD_GET, {}, _on_profile_finance_fetched.bind(request))

# Même ordre de paramètres liés que _on_profile_history_fetched (cf. la note qui y détaille le piège).
func _on_profile_finance_fetched(_result, response_code, _headers, body, http_node, request):
	http_node.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8()) if response_code == 200 else null
	profile_finance_loaded.emit(data if typeof(data) == TYPE_DICTIONARY else {}, request)


# 8. PASS (chantier J) : GET /profile/pass (authentifié). État, avantages data-driven, gain réel
# mesuré, objets obtenus grâce au Pass. Même dégradation propre qu'au-dessus sur un serveur ancien.
func fetch_profile_pass():
	_send_api_request("/profile/pass", HTTPClient.METHOD_GET, {}, _on_profile_pass_fetched)

func _on_profile_pass_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8()) if response_code == 200 else null
	profile_pass_loaded.emit(data if typeof(data) == TYPE_DICTIONARY else {})

# =========================================================
# PARTIE 3bis : HÉROS / ROSTER (sprint RPG & Survie — écran « Personnages »)
# =========================================================

# Roster des héros de l'opérateur : GET /api/v1/heroes (authentifié). Relaie la liste brute via
# heroes_loaded ; l'écran « Personnages » la lit défensivement (clés canoniques + int() sur les
# nombres, piège float §5). Forme : { "heroes": [ { faction_id, faction_name, hero_power, level,
# xp_total, xp_in_level, xp_for_level, xp_to_next, stats{}, stats_max{}, milestones[], owned } ] }.
func fetch_heroes():
	_send_api_request("/heroes", HTTPClient.METHOD_GET, {}, _on_heroes_fetched)

func _on_heroes_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			var heroes = data.get("heroes", [])
			if typeof(heroes) != TYPE_ARRAY:
				heroes = []
			heroes_loaded.emit(heroes)
	else:
		lobby_error.emit(tr("NET_HEROES_FETCH_FAILED"))

# =========================================================
# PARTIE 4 : BOUTIQUE / INVENTAIRE / ÉCONOMIE (R1 — §9.3)
# =========================================================

# 7. Catalogue : GET /shop/catalog (public). Liste d'articles {id, category, price, name_key, desc_key}.
# §8.102 : `?include_all=1` → le serveur renvoie AUSSI les articles `purchasable=false` (skins
# exclusifs de saison) avec le champ `purchasable` exposé — la boutique ne les affiche que
# POSSÉDÉS, sans CTA d'achat. Un serveur antérieur ignore simplement le paramètre (rétro-compat).
func fetch_shop_catalog():
	_send_api_request("/shop/catalog?include_all=1", HTTPClient.METHOD_GET, {}, _on_shop_catalog_fetched)

func _on_shop_catalog_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_ARRAY:
			shop_catalog_loaded.emit(data)
	else:
		lobby_error.emit(tr("NET_CATALOG_FETCH_FAILED"))

# 8. Inventaire + solde : GET /shop/inventory (authentifié). Dict {credits, items}.
func fetch_shop_inventory():
	_send_api_request("/shop/inventory", HTTPClient.METHOD_GET, {}, _on_shop_inventory_fetched)

func _on_shop_inventory_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			shop_inventory_loaded.emit(data)
	else:
		lobby_error.emit(tr("NET_INVENTORY_FETCH_FAILED"))

# 9. Achat en COINS : POST /shop/purchase/virtual {item_id} (authentifié). Pour les articles en jeu
# (faction / skin / Pass Spécial). Succès → {credits, items, has_active_pass} ; échec (HTTP 400) →
# message du serveur (« Crédits insuffisants » / « Article déjà acquis » / « Article inconnu »).
func purchase_item_virtual(item_id: String):
	_send_api_request("/shop/purchase/virtual", HTTPClient.METHOD_POST, {"item_id": item_id}, _on_purchase_completed)

# 10. Achat en ARGENT RÉEL : POST /shop/purchase/fiat {item_id} (authentifié). Pour les packs de
# Coins (catégorie « currency »). Le backend SIMULE le paiement (stub) puis crédite les Coins.
# Succès → {credits, items, has_active_pass} (le solde augmente).
func purchase_item_fiat(item_id: String):
	_send_api_request("/shop/purchase/fiat", HTTPClient.METHOD_POST, {"item_id": item_id}, _on_purchase_completed)

# Alias DÉPRÉCIÉ (clients antérieurs au split virtual/fiat) → délègue à l'achat en Coins.
func purchase_item(item_id: String):
	purchase_item_virtual(item_id)

func _on_purchase_completed(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 200 and typeof(data) == TYPE_DICTIONARY:
		shop_purchase_success.emit(data)
	else:
		# Message d'erreur lisible : on privilégie le `detail` JSON renvoyé par le backend.
		var msg := tr("NET_PURCHASE_FAILED")
		if typeof(data) == TYPE_DICTIONARY and data.has("detail"):
			msg = str(data["detail"])
		shop_purchase_failed.emit(msg)

# =========================================================
# RE-QUEUE EN 1 CLIC (G3 §8.70) — helper partagé (overlay observateur + rapport post-op)
# =========================================================
# Quitte la salle courante (WS fermé + DELETE leave), scanne le radar, REJOINT la première salle
# `waiting` non pleine, sinon CRÉE une salle (publique, 6 places par défaut), puis navigue vers
# waiting_room. Toute erreur → requeue_failed(message) (l'appelant retombe sur le lobby).
var _requeue_active := false

func requeue() -> void:
	if _requeue_active:
		return
	_requeue_active = true
	# 1) Fermer proprement le WebSocket de la salle courante (le serveur traite la déconnexion :
	#    un éliminé ne déclenche NI abandon NI minuterie — garanti côté backend §8.70).
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN \
			or socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		socket.close()
	connected = false
	set_process(false)
	# 2) Libérer la place côté base (DELETE leave — échec TOLÉRÉ : la salle a pu être détruite
	#    par la déconnexion, ou la partie n'était plus `waiting`).
	if current_room_id != "":
		_send_api_request("/lobby/rooms/" + current_room_id + "/leave",
			HTTPClient.METHOD_DELETE, {}, _on_requeue_left)
	else:
		_requeue_scan()

func _on_requeue_left(_result, _response_code, _headers, _body, http_node):
	http_node.queue_free()
	_requeue_scan()

func _requeue_scan() -> void:
	current_room_id = ""
	_send_api_request("/lobby/rooms", HTTPClient.METHOD_GET, {}, _on_requeue_rooms)

func _on_requeue_rooms(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code != 200:
		_requeue_fail(tr("NET_REQUEUE_RADAR_UNREACHABLE"))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_ARRAY:
		_requeue_fail(tr("NET_REQUEUE_RADAR_UNREADABLE"))
		return
	# Première salle `waiting` PUBLIQUE non pleine (piège JSON §5 : int() sur tous les nombres).
	for room in data:
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if bool(room.get("is_private", false)):
			continue
		var maxp := int(room.get("max_players", 0))
		var cur := int(room.get("current_players", 0))
		if str(room.get("status", "waiting")) == "waiting" and cur < maxp and maxp > 0:
			var rid := int(room.get("id", -1))
			if rid > 0:
				_send_api_request("/lobby/rooms/" + str(rid) + "/join",
					HTTPClient.METHOD_POST, {}, _on_requeue_joined.bind(rid))
				return
	# Aucune salle disponible → on en CRÉE une (défauts §8.70 : publique, 6 places).
	_send_api_request("/lobby/rooms", HTTPClient.METHOD_POST,
		{"max_players": 6, "is_private": false, "secret_code": ""}, _on_requeue_created)

# NB signature : _send_api_request bind http_node APRÈS le rid déjà lié → (…, http_node, rid).
func _on_requeue_joined(_result, response_code, _headers, _body, http_node, rid: int):
	http_node.queue_free()
	if response_code == 200:
		_requeue_enter(rid)
	else:
		# La salle s'est remplie entre le scan et le join : on retente un cycle complet.
		_requeue_scan()

func _on_requeue_created(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code != 200 and response_code != 201:
		_requeue_fail(tr("NET_REQUEUE_CREATE_FAILED"))
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var rid := int(data.get("id", -1)) if typeof(data) == TYPE_DICTIONARY else -1
	if rid <= 0:
		_requeue_fail(tr("NET_REQUEUE_ROOM_UNREADABLE"))
		return
	_requeue_enter(rid)

func _requeue_enter(room_id: int) -> void:
	_requeue_active = false
	current_room_id = str(int(room_id))
	# Socket NEUF : WebSocketPeer ne se reconnecte pas proprement après un close().
	socket = WebSocketPeer.new()
	connected = false
	connect_to_server(current_room_id)
	TransitionManager.change_scene("res://scenes/ui/waiting_room.tscn")

func _requeue_fail(message: String) -> void:
	_requeue_active = false
	requeue_failed.emit(message)

# 10 ter. Équipe un SKIN possédé (M5 §8.69) : POST /shop/equip {skin_id} — la faction est
# dérivée côté serveur (hero_key). Réponse = inventaire complet (bloc `equipped` à jour).
func equip_skin(skin_id: String):
	_send_api_request("/shop/equip", HTTPClient.METHOD_POST, {"skin_id": skin_id}, _on_skin_equipped)

# Déséquipe le skin d'une faction : POST /shop/equip {faction_id, skin_id: null}.
func unequip_skin(faction_id: String):
	_send_api_request("/shop/equip", HTTPClient.METHOD_POST,
		{"faction_id": faction_id, "skin_id": null}, _on_skin_equipped)

func _on_skin_equipped(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 200 and typeof(data) == TYPE_DICTIONARY:
		skin_equipped.emit(data)
	else:
		var msg := tr("NET_EQUIP_FAILED")
		if typeof(data) == TYPE_DICTIONARY and data.has("detail"):
			msg = str(data["detail"])
		skin_equip_failed.emit(msg)

# 10 bis. Rotation gratuite hebdomadaire (M3 §8.66) : GET /shop/rotation (PUBLIC). Les deux
# factions payantes jouables gratuitement cette semaine (déterministe, bascule lundi 04:00 UTC).
func fetch_shop_rotation():
	_send_api_request("/shop/rotation", HTTPClient.METHOD_GET, {}, _on_shop_rotation_fetched)

func _on_shop_rotation_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			shop_rotation_loaded.emit(data)
	# Pas de signal d'erreur dédié : les écrans appliquent leur REPLI GRACIEUX (M3) quand la
	# rotation reste muette (draft : griser toutes les payantes non possédées).

# 11. Missions quotidiennes & hebdomadaires (M2 §8.65) : GET /missions (authentifié). Assigne
# côté serveur au premier appel de la période (lazy, déterministe) puis renvoie la liste +
# les comptes à rebours de reset et la pastille `claimable_count`.
func fetch_missions():
	_send_api_request("/missions", HTTPClient.METHOD_GET, {}, _on_missions_fetched)

func _on_missions_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_DICTIONARY:
			missions_loaded.emit(data)
	else:
		lobby_error.emit(tr("NET_MISSIONS_FETCH_FAILED"))

# 12. Réclame la récompense d'une mission COMPLÉTÉE : POST /missions/claim {mission_id}.
# Succès → { coins_balance, reward_paid, pass_bonus_applied } (bonus Pass ×1.5 appliqué serveur).
# Échec (400 « Mission non terminée » / « Déjà réclamée ») → message du serveur.
func claim_mission(mission_id: String):
	_send_api_request("/missions/claim", HTTPClient.METHOD_POST,
		{"mission_id": mission_id}, _on_mission_claimed)

func _on_mission_claimed(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 200 and typeof(data) == TYPE_DICTIONARY:
		mission_claimed.emit(data)
	else:
		var msg := tr("NET_CLAIM_FAILED")
		if typeof(data) == TYPE_DICTIONARY and data.has("detail"):
			msg = str(data["detail"])
		mission_claim_failed.emit(msg)
