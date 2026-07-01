extends Node

signal server_connected
signal rooms_loaded(rooms: Array)
signal lobby_action_success(action: String, data: Dictionary)
signal lobby_error(message: String)

# --- Signaux temps réel (arène) ---
# Émis après chaque mise à jour de l'état de jeu reçue du serveur. L'UI (HUD, plateau)
# s'y abonne au lieu de lire le réseau en direct (Règle d'Or §6.1 : découplage par signaux).
signal game_state_updated
# Émis pour chaque évènement de jeu renvoyé par le moteur (résultat de combat, déploiement…).
signal game_event(event: Dictionary)
# Émis quand le serveur refuse une action (ex: "Ce n'est pas votre tour").
signal game_error(message: String)
# Émis quand un joueur quitte la partie.
signal player_left(player_id)
# Émis quand la composition de la salle d'attente change (joueurs connectés + prêts + pseudos).
# `usernames` = { "player_id": "pseudo" } (clés string, piège JSON §5) pour afficher les VRAIS noms.
signal lobby_state_updated(players: Array, ready: Array, usernames: Dictionary)
# Émis quand la partie démarre (l'état initial est déjà appliqué à GameState).
signal game_started_signal
# Émis quand un joueur verrouille sa faction pendant le Draft (CONTEXTE.md §3, étape de sélection).
signal faction_locked(player_id, faction_id)
# Émis quand un joueur abandonne la partie (Fallen Empire, CONTEXTE.md §8.20). L'état diffusé
# avec le message (is_active=false, tour éventuellement déjà passé) est appliqué à GameState
# AVANT l'émission — les écouteurs peuvent donc lire player_number/players directement.
signal player_abandoned(player_id: int)
# Espionnage (Chasseurs d'Ombres, §8.3) : réponse PRIVÉE du serveur à l'action spy_objective.
# Reçue uniquement par l'espion (le secret n'est jamais diffusé). target_player_id = id de la
# cible espionnée ; description = libellé de son objectif secret.
signal spy_result(target_player_id: int, description: String)
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
signal profile_history_loaded(entries: Array)
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
# Fin de partie (Économie §8.47) : le serveur diffuse `game_over` avec le détail des gains par joueur.
# `match_rewards` = { "<player_id:str>": { match_points, xp_earned, coins_earned, level_up_triggered,
# new_level, current_xp, xp_to_next_level, levels_gained } } (toutes valeurs entières — piège JSON §5).
# `rankings` = liste ordonnée des player_id (1er d'abord, départage 2e place côté serveur).
signal match_over(winner_id: int, match_type: String, rankings: Array, match_rewards: Dictionary)

# Dernier détail de récompenses reçu (cache) : lu par main.gd si le rapport Post-Op est déjà affiché
# quand le game_over arrive (course réseau état/clôture). Vidé au démarrage d'une partie.
var last_match_rewards: Dictionary = {}

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
		print("⚠️ NETWORK: player_id inconnu, connexion WebSocket impossible. As-tu bien fini le login ?")
		lobby_error.emit("Identité joueur non chargée, réessayez.")
		return

	# Version du client (auto-updater §9) jointe en query string : le serveur la compare à
	# version.json et REJETTE (close 4000) tout client dont la version diffère (validation stricte).
	var cv := "1.0.0"
	if has_node("/root/GameState"):
		cv = str(GameState.client_version)
	var final_url = websocket_url + room_id + "/" + str(AuthManager.user_id) + "?client_version=" + cv.uri_encode()
	print("🌐 NETWORK: Tentative de connexion WebSocket vers " + final_url)
	
	var tls_options = TLSOptions.client_unsafe()
	
	# NOUVEAU : On attache le Token JWT pour prouver notre identité au WebSocket
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
			print("🟢 CONNECTÉ AU WEBSOCKET !")
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
			var msg := reason if reason != "" else "Version du jeu obsolète : mettez à jour."
			print("🚫 NETWORK: connexion refusée par le serveur (version) : " + msg)
			game_error.emit(msg)
			lobby_error.emit(msg)
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
			var err_msg = str(msg.get("message", "Erreur inconnue"))
			print("🚫 NETWORK: action refusée par le serveur : " + err_msg)
			game_error.emit(err_msg)
		"player_disconnected":
			player_left.emit(msg.get("player_id"))
		"lobby_state":
			lobby_state_updated.emit(msg.get("players", []), msg.get("ready", []), msg.get("usernames", {}))
		"game_over":
			# La victoire est déjà gérée via winner_id dans l'état ; ici on relaie le RÉSULTAT
			# ÉCONOMIQUE (points/XP/Coins, §8.47) pour le Rapport Post-Op animé. Piège JSON §5 :
			# les ids/nombres arrivent en float → int() ; les clés de match_rewards restent string.
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
			if msg.has("state") and has_node("/root/GameState"):
				GameState.update_from_json(msg["state"])
			game_state_updated.emit()
			game_started_signal.emit()
		"faction_locked":
			# Un joueur a verrouillé sa faction pendant le Draft. On relaie aux écouteurs
			# (faction_selection.gd) le couple (player_id, faction_id).
			faction_locked.emit(msg.get("player_id"), msg.get("faction_id", ""))
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
			# Espionnage (Chasseurs d Ombres) : message PRIVE recu uniquement par l espion.
			# Piege des ids JSON : target_player_id arrive en float -> int().
			spy_result.emit(int(msg.get("target_player_id", -1)), str(msg.get("description", "")))
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
func send_action(action_type: String, payload: Dictionary = {}) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		print("⚠️ NETWORK: WebSocket non ouvert, action '" + action_type + "' ignorée.")
		game_error.emit("Pas connecté au serveur temps réel.")
		return
	var message = {"action": action_type, "payload": payload}
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

# Chat de salle (§8.33) : envoi à PLAT (contrat principal) — {"type":"send_chat_message", tab, text,
# target_id}. tab ∈ {"general","private"} ; target_id REQUIS en privé. Le serveur estampille
# l'identité réelle (pas d'usurpation) et renvoie un message "chat_message" (écho à l'expéditeur
# compris) → on n'affiche jamais nos propres messages localement, on attend cet écho.
func send_chat_message(tab: String, text: String, target_id: int = -1) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		game_error.emit("Pas connecté au serveur temps réel.")
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
		lobby_error.emit("Impossible de contacter le serveur.")
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
		lobby_error.emit("Erreur lors de la récupération des salles.")

# 2. Créer une salle
# max_players par défaut = 6 (capacité maximale autorisée, cf. §4 : 3 à 6 joueurs).
# Auparavant figé à 3, ce qui bloquait toutes les salles à 3 places.
func create_room(is_private: bool, secret_code: String = "", max_players: int = 6):
	var payload = {
		"max_players": max_players,
		"is_private": is_private,
		"secret_code": secret_code if is_private else "" # <-- Correction ici ("" au lieu de null)
	}
	_send_api_request("/lobby/rooms", HTTPClient.METHOD_POST, payload, _on_room_created)

func _on_room_created(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	var data = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 200 or response_code == 201:
		lobby_action_success.emit("create", data)
	else:
		lobby_error.emit("Impossible de créer la salle.")

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
		lobby_error.emit("Impossible de rejoindre cette salle.")

# 4. Classement mondial (R3 — §9.2) : GET /leaderboard?limit=&offset= (public ; enrichi du bloc `me`
# si le token est joint). Le serveur trie par victoires décroissantes et renvoie une enveloppe
# {entries, me}. On relaie (entries, me) via leaderboard_loaded — l'écran mappe les champs.
func fetch_leaderboard(limit: int = 20, offset: int = 0):
	_send_api_request("/leaderboard?limit=" + str(limit) + "&offset=" + str(offset),
		HTTPClient.METHOD_GET, {}, _on_leaderboard_fetched)

func _on_leaderboard_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code != 200:
		lobby_error.emit("Erreur lors de la récupération du classement.")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	# Forme CANONIQUE §9.2 : enveloppe {entries, me}.
	if typeof(data) == TYPE_DICTIONARY:
		var entries = data.get("entries", [])
		var me = data.get("me", {})
		if typeof(entries) != TYPE_ARRAY:
			entries = []
		if typeof(me) != TYPE_DICTIONARY:
			me = {}
		leaderboard_loaded.emit(entries, me)
	# Tolérance : ancien backend (avant redéploiement VPS) → liste plate sans bloc `me`.
	elif typeof(data) == TYPE_ARRAY:
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
		lobby_error.emit("Erreur lors de la récupération du profil.")

# 6. Historique récent : GET /profile/history?limit=N (authentifié). Liste {win, faction_id, detail}.
func fetch_profile_history(limit: int = 5):
	_send_api_request("/profile/history?limit=" + str(limit), HTTPClient.METHOD_GET, {}, _on_profile_history_fetched)

func _on_profile_history_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_ARRAY:
			profile_history_loaded.emit(data)
	else:
		lobby_error.emit("Erreur lors de la récupération de l'historique.")

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
		lobby_error.emit("Erreur lors de la récupération des héros.")

# =========================================================
# PARTIE 4 : BOUTIQUE / INVENTAIRE / ÉCONOMIE (R1 — §9.3)
# =========================================================

# 7. Catalogue : GET /shop/catalog (public). Liste d'articles {id, category, price, name_key, desc_key}.
func fetch_shop_catalog():
	_send_api_request("/shop/catalog", HTTPClient.METHOD_GET, {}, _on_shop_catalog_fetched)

func _on_shop_catalog_fetched(_result, response_code, _headers, body, http_node):
	http_node.queue_free()
	if response_code == 200:
		var data = JSON.parse_string(body.get_string_from_utf8())
		if typeof(data) == TYPE_ARRAY:
			shop_catalog_loaded.emit(data)
	else:
		lobby_error.emit("Erreur lors de la récupération du catalogue.")

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
		lobby_error.emit("Erreur lors de la récupération de l'inventaire.")

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
		var msg := "Achat impossible."
		if typeof(data) == TYPE_DICTIONARY and data.has("detail"):
			msg = str(data["detail"])
		shop_purchase_failed.emit(msg)
