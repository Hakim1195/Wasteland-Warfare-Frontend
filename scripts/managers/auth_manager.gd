extends Node

signal auth_success(message: String)
signal auth_failed(error_msg: String)
signal profile_loaded(profile_data: Dictionary)
signal user_id_loaded(user_id: int)

var base_url = "https://api.wasteland-warfare.com"
var jwt_token: String = ""
# ID numérique du joueur connecté (= User.id en base). Requis pour l'URL WebSocket
# /ws/{room_id}/{player_id}. Le JWT ne contient que le username, on le récupère donc via /auth/me.
var user_id: int = -1
# Pseudo du joueur connecté. Renseigné dès le login (claim "sub" du JWT décodé) puis confirmé
# par /auth/me. Affiché dans le HUD de l'arène (identité + couleur de faction, CONTEXTE.md §8.23).
var username: String = ""
var http_request: HTTPRequest
var _id_http: HTTPRequest

# Persistance de session (§P1) : le JWT est sauvegardé ici à la connexion réussie pour éviter de
# re-saisir ses identifiants à CHAQUE lancement. L'écran d'auth tente une reconnexion silencieuse au
# boot (try_restore_session) ; un token expiré/invalide est purgé (clear_session) → retour au login.
const SESSION_PATH := "user://session.dat"

func _ready():
	# Hôte backend : source unique ApiConfig (repli sur la prod si l'autoload manque). §P1
	var cfg := get_node_or_null("/root/ApiConfig")
	if cfg != null:
		base_url = cfg.http_host

	# Create and configure HTTPRequest node
	http_request = HTTPRequest.new()
	add_child(http_request)

	# Disable SSL certificate validation for development server
	http_request.set_tls_options(TLSOptions.client_unsafe())

	# Connect the request completed signal
	http_request.request_completed.connect(_on_request_completed)

	# HTTPRequest dédié à la récupération de l'ID joueur (évite de polluer http_request
	# qui sert au login/profil et pourrait être utilisé en parallèle par l'UI).
	_id_http = HTTPRequest.new()
	add_child(_id_http)
	_id_http.set_tls_options(TLSOptions.client_unsafe())
	_id_http.request_completed.connect(_on_id_request_completed)

# Récupère l'ID numérique du joueur via /auth/me et le stocke dans user_id.
func _fetch_user_id():
	if jwt_token == "":
		return
	var headers = ["Authorization: Bearer " + jwt_token]
	_id_http.request(base_url + "/api/v1/auth/me", headers, HTTPClient.METHOD_GET)

func _on_id_request_completed(_result, response_code, _headers, body):
	if response_code == 200:
		# Parse via instance JSON (cf. _on_request_completed) : aucun bruit dans le débogueur si la
		# réponse n'est pas du JSON valide ; data == null est géré juste en dessous.
		var _json := JSON.new()
		var data = _json.data if _json.parse(body.get_string_from_utf8()) == OK else null
		if data != null and data.has("id"):
			user_id = int(data["id"])
			# /auth/me renvoie aussi le pseudo (UserResponse.username) : source faisant foi.
			if data.has("username"):
				username = str(data["username"])
			emit_signal("user_id_loaded", user_id)
			print("AuthManager : player_id récupéré = ", user_id)

# Décode le claim "sub" (= username) d'un JWT sans vérifier la signature. Le payload est encodé
# en base64url (URL-safe, sans padding) : on le convertit en base64 standard avant décodage.
func _username_from_jwt(token: String) -> String:
	var parts := token.split(".")
	if parts.size() < 2:
		return ""
	var payload_b64: String = parts[1].replace("-", "+").replace("_", "/")
	while payload_b64.length() % 4 != 0:
		payload_b64 += "="
	var payload_json := Marshalls.base64_to_utf8(payload_b64)
	var data = JSON.parse_string(payload_json)
	if typeof(data) == TYPE_DICTIONARY and data.has("sub"):
		return str(data["sub"])
	return ""

# Garantit que user_id est chargé avant de l'utiliser (ex: avant d'ouvrir le WebSocket).
# À appeler avec await. Retourne user_id (-1 si non connecté).
func ensure_user_id() -> int:
	if user_id >= 0:
		return user_id
	if jwt_token == "":
		return -1
	_fetch_user_id()
	await user_id_loaded
	return user_id

func register(p_username, email, password):
	# Create JSON object for registration
	var register_data = {
		"username": p_username,
		"email": email,
		"password": password
	}
	
	# Convert to JSON string
	var json_string = JSON.stringify(register_data)
	
	# Set headers
	var headers = ["Content-Type: application/json"]
	
	# Send POST request
	var err = http_request.request(
		base_url + "/api/v1/auth/register",
		headers,
		HTTPClient.METHOD_POST,
		json_string
	)
	
	if err != OK:
		emit_signal("auth_failed", "Impossible d'envoyer la requête d'enregistrement")

func login(p_username, password):
	# Format data as application/x-www-form-urlencoded.
	# On ENCODE chaque valeur (§P0) : un '&', '=', '+' ou espace dans le pseudo / mot de passe
	# corromprait sinon le corps de la requête et rendrait la connexion impossible.
	var post_data = "username=" + str(p_username).uri_encode() + "&password=" + str(password).uri_encode()
	var headers = ["Content-Type: application/x-www-form-urlencoded"]
	
	# Send POST request
	var err = http_request.request(
		base_url + "/api/v1/auth/login",
		headers,
		HTTPClient.METHOD_POST,
		post_data
	)
	
	if err != OK:
		emit_signal("auth_failed", "Impossible d'envoyer la requête de connexion")

func get_profile():
	# Check if we have a token
	if jwt_token == "":
		emit_signal("auth_failed", "Aucun token d'authentification disponible")
		return
	
	# Set headers with Authorization
	var headers = ["Authorization: Bearer " + jwt_token]
	
	# Send GET request
	var err = http_request.request(
		base_url + "/api/v1/auth/me",
		headers,
		HTTPClient.METHOD_GET
	)
	
	if err != OK:
		emit_signal("auth_failed", "Impossible d'envoyer la requête de profil")

func _on_request_completed(_result, response_code, _headers, body):
	var response_text = body.get_string_from_utf8()

	# Parse via une INSTANCE JSON : sur un corps NON-JSON (ex. "Internal Server Error" brut renvoyé
	# par Starlette lors d'un 500), on récupère null SANS polluer le débogueur d'une erreur rouge —
	# contrairement au helper statique JSON.parse_string qui logge systématiquement l'échec. La suite
	# de la fonction gère déjà proprement le cas data == null (réponse non-JSON / erreur HTTP brute).
	var _json := JSON.new()
	var data = _json.data if _json.parse(response_text) == OK else null
	
	# Codes HTTP de succès (200 OK, ou 201 Created)
	if response_code == 200 or response_code == 201:
		if data != null:
			if data.has("access_token"):
				jwt_token = data["access_token"]
				# Persistance (§P1) : on mémorise le token pour la reconnexion auto au prochain boot.
				_save_session()
				# Pseudo via le claim "sub" du JWT (dispo avant la réponse /auth/me).
				var sub := _username_from_jwt(jwt_token)
				if sub != "":
					username = sub
				emit_signal("auth_success", "Connexion réussie")
				# Dès qu'on a le token, on récupère l'ID numérique du joueur en arrière-plan.
				_fetch_user_id()
			elif data.has("username") and data.has("email"):
				username = str(data["username"])
				# Le profil (/auth/me) contient l'id numérique : on en profite pour le capter.
				if data.has("id"):
					user_id = int(data["id"])
					emit_signal("user_id_loaded", user_id)
				emit_signal("profile_loaded", data)
			elif data.has("message"):
				emit_signal("auth_success", "Succès : " + str(data["message"]))
			else:
				emit_signal("auth_success", "Opération réussie")
		else:
			emit_signal("auth_success", "Succès (Réponse non-JSON)")
			
	# Codes HTTP d'erreur (400, 401, 500...)
	else:
		var error_msg = "Erreur " + str(response_code)
		if data != null:
			if data.has("detail"):
				error_msg += " : " + str(data["detail"])
			elif data.has("message"):
				error_msg += " : " + str(data["message"])
		else:
			# Si ce n'est pas du JSON (ex: Erreur 500 brute), on affiche le texte reçu
			error_msg += " : " + response_text
			
		emit_signal("auth_failed", error_msg)

# =========================================================
# PERSISTANCE DE SESSION (§P1) — reconnexion automatique
# =========================================================

# Vrai si une session a été sauvegardée (un token est présent sur disque). L'écran d'auth s'en sert
# pour décider de tenter une reconnexion silencieuse au démarrage plutôt que d'afficher le login.
func has_saved_token() -> bool:
	return FileAccess.file_exists(SESSION_PATH)

# Écrit le JWT courant sur disque (user://, propre à l'utilisateur OS). Appelé à chaque login réussi.
func _save_session() -> void:
	if jwt_token == "":
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("AuthManager: impossible d'écrire " + SESSION_PATH)
		return
	f.store_string(jwt_token)
	f.close()

# Purge complète de la session : mémoire (token/id/pseudo) ET disque. À appeler à la déconnexion,
# ou quand une reconnexion auto échoue (token expiré/invalide).
func clear_session() -> void:
	jwt_token = ""
	user_id = -1
	username = ""
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)

# Tente de restaurer une session sauvegardée et de la VALIDER auprès du serveur (/auth/me) :
#   - token valide        → signal profile_loaded (+ user_id renseigné) → l'appelant entre au menu ;
#   - token absent/expiré  → signal auth_failed → l'appelant purge et reste sur le login.
# On ne fait JAMAIS confiance au token local seul : seul /auth/me fait foi (il a pu expirer).
func try_restore_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		emit_signal("auth_failed", "Aucune session sauvegardée")
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		emit_signal("auth_failed", "Session illisible")
		return
	var t := f.get_as_text().strip_edges()
	f.close()
	if t == "":
		emit_signal("auth_failed", "Session vide")
		return
	jwt_token = t
	# Pseudo provisoire depuis le claim "sub" (confirmé ensuite par /auth/me).
	var sub := _username_from_jwt(t)
	if sub != "":
		username = sub
	# Validation serveur : /auth/me → profile_loaded (succès) ou auth_failed (401/expiré).
	get_profile()
