extends Node

signal auth_success(message: String)
signal auth_failed(error_msg: String)
signal profile_loaded(profile_data: Dictionary)
signal user_id_loaded(user_id: int)
# Avatar Steam prêt à l'affichage (§8.114). Émis une fois la texture décodée, et RE-émis (en différé)
# à chaque `ensure_avatar()` d'une Vue qui arrive après coup — `top_nav` est reconstruit à chaque
# changement d'écran, il doit pouvoir récupérer l'avatar sans re-télécharger.
signal avatar_loaded(texture: Texture2D)
# TUTORIEL / FTUE (§8.129) — le drapeau de briefing du COMPTE vient de changer (chargé par /auth/me,
# ou posé localement après un complete/skip réussi). Le QG s'y abonne pour retirer sa mise en avant
# de la PREMIÈRE OPÉRATION sans avoir à recharger l'écran.
signal tutorial_state_changed(done: bool)

var base_url = "https://api.wasteland-warfare.com"
var jwt_token: String = ""
# ID numérique du joueur connecté (= User.id en base). Requis pour l'URL WebSocket
# /ws/{room_id}/{player_id}. Le JWT ne contient que le username, on le récupère donc via /auth/me.
var user_id: int = -1
# Pseudo du joueur connecté. Renseigné dès le login (claim "sub" du JWT décodé) puis confirmé
# par /auth/me. Affiché dans le HUD de l'arène (identité + couleur de faction, CONTEXTE.md §8.23).
var username: String = ""
# Notice à afficher sur l'écran d'auth après une redirection (§AC.5, ex. « Session expirée — … »).
# Posée par le hub AVANT de rediriger, LUE et effacée par auth_screen à son _ready. "" = rien.
var session_notice: String = ""
var http_request: HTTPRequest
# Vrai tant qu'une requête get_profile() (/auth/me) est en vol — remis à faux par
# _on_request_completed (SEUL handler de http_request, donc reset garanti sur tout dénouement).
# Même idiome que _steam_poll_in_flight : l'appel de trop est SAUTÉ, jamais heurté.
var _profile_in_flight := false
var _id_http: HTTPRequest

# --- Avatar Steam (§8.114) : SIGNAL DE RECONNAISSANCE du compte -------------------------------
# L'URL est fournie par `/auth/me` (`steam_avatar_url`), DÉJÀ validée côté serveur comme pointant
# sur un CDN Steam — le client n'a donc pas à la re-contrôler. "" = aucun avatar connu.
var avatar_url: String = ""
# Texture décodée, mise en cache EN MÉMOIRE pour toute la session de jeu : `top_nav` est reconstruit
# à chaque écran, un cache disque n'économiserait qu'un seul téléchargement par lancement pour le
# prix d'une invalidation à gérer. Volontairement pas de persistance.
var avatar_texture: Texture2D = null
# --- TUTORIEL / FTUE (§8.129) : drapeau de briefing du COMPTE ---------------------------------
# `tutorial_done` : le joueur a-t-il soldé son briefing d'entrée (fait OU refusé) ?
# `tutorial_done_known` : le serveur a-t-il RÉELLEMENT renvoyé la clé ? Distinction indispensable —
# un serveur ANTÉRIEUR à ce chantier n'émet pas `tutorial_done`, et lire `false` par défaut ferait
# proposer la Première Opération à toute la population, y compris aux vétérans, à chaque lancement.
# Tant que ce drapeau est faux, le QG se tait : additif strict côté client comme côté serveur (§1.5).
var tutorial_done := false
var tutorial_done_known := false
var _avatar_http: HTTPRequest
# URL du téléchargement EN COURS ("" = aucun) — évite d'empiler deux requêtes sur le même avatar.
var _avatar_pending_url: String = ""

# Persistance de session (§P1) : le JWT est sauvegardé ici à la connexion réussie pour éviter de
# re-saisir ses identifiants à CHAQUE lancement. L'écran d'auth tente une reconnexion silencieuse au
# boot (try_restore_session) ; un token expiré/invalide est purgé (clear_session) → retour au login.
const SESSION_PATH := "user://session.dat"

# =========================================================
# CONNEXION STEAM (OpenID 2.0, §8.113) — SEUL moyen de connexion
# =========================================================
# Le jeu n'est pas (encore) lancé par le client Steam : l'authentification passe par le NAVIGATEUR
# EXTERNE du joueur. Godot ne peut donc pas recevoir la redirection de retour — il ouvre l'URL puis
# INTERROGE le backend, qui a mis le JWT de côté dans une « session de login » (Redis).
const STEAM_POLL_INTERVAL_S := 2.0
# Au-delà, on considère que le joueur a fermé l'onglet / renoncé. Volontairement généreux : une
# première connexion Steam avec Steam Guard (code par mail) prend facilement une minute.
const STEAM_LOGIN_TIMEOUT_MS := 180000

# HTTPRequest DÉDIÉ au flux Steam : http_request sert au profil et _id_http à l'id joueur — un
# HTTPRequest ne traite qu'UNE requête à la fois, les mutualiser produirait des ERR_BUSY.
var _steam_http: HTTPRequest
var _steam_timer: Timer
var _steam_session_id: String = ""
# Étape courante : "" (inactif) | "session" (ouverture de session) | "poll" (attente du token).
# Sert aussi de VERROU : un second clic sur le bouton ne relance pas un flux concurrent.
var _steam_phase: String = ""
var _steam_started_at_ms: int = 0
# Vrai tant qu'un poll est en vol : le tic suivant est SAUTÉ plutôt que de heurter un ERR_BUSY
# (le serveur peut mettre plusieurs secondes à répondre pendant la vérification serveur→Steam).
var _steam_poll_in_flight := false

func _ready():
	# Hôte backend : source unique ApiConfig (repli sur la prod si l'autoload manque). §P1
	var cfg := get_node_or_null("/root/ApiConfig")
	if cfg != null:
		base_url = cfg.http_host

	# Create and configure HTTPRequest node
	http_request = HTTPRequest.new()
	add_child(http_request)

	# Validation TLS selon l'environnement (§AC.10) : vérifiée en prod, tolérée en dev local seul.
	http_request.set_tls_options(_tls_options())

	# Connect the request completed signal
	http_request.request_completed.connect(_on_request_completed)

	# HTTPRequest dédié à la récupération de l'ID joueur (évite de polluer http_request
	# qui sert au login/profil et pourrait être utilisé en parallèle par l'UI).
	_id_http = HTTPRequest.new()
	add_child(_id_http)
	_id_http.set_tls_options(_tls_options())
	_id_http.request_completed.connect(_on_id_request_completed)

	# Flux Steam (§8.113) : requête dédiée + minuterie de polling créées en code (l'AuthManager est
	# un autoload sans scène). La minuterie reste ARRÊTÉE tant qu'aucune connexion n'est lancée.
	_steam_http = HTTPRequest.new()
	add_child(_steam_http)
	_steam_http.set_tls_options(_tls_options())
	_steam_http.request_completed.connect(_on_steam_request_completed)

	_steam_timer = Timer.new()
	_steam_timer.wait_time = STEAM_POLL_INTERVAL_S
	_steam_timer.one_shot = false
	add_child(_steam_timer)
	_steam_timer.timeout.connect(_on_steam_poll_tick)

	# Avatar Steam (§8.114). ⚠️ TLS VÉRIFIÉ EN DUR ici, et NON `_tls_options()` : cette requête ne
	# part pas vers NOTRE backend mais vers un CDN Steam public, toujours en https. La tolérance
	# `client_unsafe()` du mode dev local (§8.112) n'a aucune raison de s'appliquer à un tiers.
	_avatar_http = HTTPRequest.new()
	add_child(_avatar_http)
	_avatar_http.set_tls_options(TLSOptions.client())
	_avatar_http.request_completed.connect(_on_avatar_request_completed)

# Options TLS (§AC.10) : ApiConfig décide (certificat VÉRIFIÉ en prod, toléré non vérifié en dev
# local seulement) ; repli SÉCURISÉ si l'autoload manque. Jamais de client_unsafe contre la prod.
func _tls_options() -> TLSOptions:
	var cfg := get_node_or_null("/root/ApiConfig")
	if cfg != null and cfg.has_method("tls_options"):
		return cfg.tls_options()
	return TLSOptions.client()

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
			# …et l'avatar Steam (§8.114) : c'est ICI qu'il arrive le plus tôt après un login,
			# `_fetch_user_id` étant lancé dès l'obtention du token.
			_capture_avatar_url(data)
			# …et le drapeau de briefing (§8.129), pour la même raison : c'est le tout premier
			# aller-retour authentifié du lancement, donc le plus tôt où le QG peut savoir.
			_capture_tutorial_flag(data)
			emit_signal("user_id_loaded", user_id)
			print("AuthManager : player_id récupéré = ", user_id)

# =========================================================
# AVATAR STEAM (§8.114) — reconnaissance visuelle du compte
# =========================================================

# Mémorise l'URL d'avatar livrée par /auth/me et déclenche le téléchargement si elle a CHANGÉ.
# Appelée depuis les deux points d'entrée du profil (http_request et _id_http).
func _capture_avatar_url(data) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var url := str(data.get("steam_avatar_url", ""))
	if url == avatar_url:
		return
	# L'avatar a changé côté Steam (ou vient d'arriver) : la texture en cache est périmée.
	avatar_url = url
	avatar_texture = null
	if url != "":
		_download_avatar()

# =========================================================
# TUTORIEL / FTUE (§8.129) — drapeau de briefing du COMPTE
# =========================================================

# Mémorise `tutorial_done` s'il est RÉELLEMENT présent dans la réponse. Une clé absente laisse
# `tutorial_done_known` à faux : le client se tait plutôt que de supposer (serveur pas encore
# redéployé — le réseau est additif dans les DEUX sens, §1.5).
func _capture_tutorial_flag(data) -> void:
	if typeof(data) != TYPE_DICTIONARY or not data.has("tutorial_done"):
		return
	var done := bool(data["tutorial_done"])
	var changed := (not tutorial_done_known) or done != tutorial_done
	tutorial_done = done
	tutorial_done_known = true
	if changed:
		emit_signal("tutorial_state_changed", tutorial_done)

# Posé par `TutorialManager` après un `complete`/`skip` accepté par le serveur : on évite un
# aller-retour /auth/me supplémentaire, et le QG se met à jour dans la foulée.
func mark_tutorial_done() -> void:
	if tutorial_done and tutorial_done_known:
		return
	tutorial_done = true
	tutorial_done_known = true
	emit_signal("tutorial_state_changed", true)

# Point d'entrée des Vues : « donne-moi l'avatar dès que possible ». À appeler APRÈS s'être connecté
# au signal. Ne re-télécharge jamais un avatar déjà en cache.
func ensure_avatar() -> void:
	if avatar_texture != null:
		# Émission DIFFÉRÉE : l'appelant est typiquement en plein `_ready()`, un signal synchrone
		# arriverait avant que sa hiérarchie de nœuds ne soit prête à l'afficher.
		emit_signal.call_deferred("avatar_loaded", avatar_texture)
		return
	if avatar_url != "":
		_download_avatar()

func _download_avatar() -> void:
	if _avatar_http == null or avatar_url == "":
		return
	if _avatar_pending_url == avatar_url:
		return  # déjà en vol : un HTTPRequest ne traite qu'une requête à la fois.
	_avatar_pending_url = avatar_url
	var err = _avatar_http.request(avatar_url, [], HTTPClient.METHOD_GET)
	if err != OK:
		_avatar_pending_url = ""

func _on_avatar_request_completed(result, response_code, _headers, body):
	_avatar_pending_url = ""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		return
	# Steam sert du JPEG, mais le format ne fait l'objet d'aucun contrat : on tente le PNG en repli
	# plutôt que de dépendre d'une extension d'URL. Un échec est SILENCIEUX — l'avatar est un
	# confort, jamais une raison de perturber le joueur avec une erreur.
	var img := Image.new()
	var err := img.load_jpg_from_buffer(body)
	if err != OK:
		err = img.load_png_from_buffer(body)
	if err != OK:
		return
	avatar_texture = ImageTexture.create_from_image(img)
	emit_signal("avatar_loaded", avatar_texture)

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

# =========================================================
# CONNEXION STEAM — API publique (appelée par auth_screen)
# =========================================================

# Démarre une connexion Steam : ouverture d'une session côté serveur, puis du navigateur du joueur,
# puis attente du JWT par interrogation régulière. Idempotent tant qu'un flux est en cours.
func start_steam_login() -> void:
	if _steam_phase != "":
		return
	_steam_session_id = ""
	_steam_poll_in_flight = false
	_steam_started_at_ms = Time.get_ticks_msec()
	_steam_phase = "session"
	# POST sans corps : l'ouverture de session ne demande AUCUNE donnée (c'est l'étape qui précède
	# toute identité) — le serveur se contente de tirer un session_id et de le mémoriser.
	var err = _steam_http.request(
		base_url + "/api/v1/auth/steam/session",
		[],
		HTTPClient.METHOD_POST,
		""
	)
	if err != OK:
		_end_steam_login(tr("AUTHM_STEAM_SESSION_FAILED"))

# Interrompt proprement un flux Steam en cours (écran d'auth quitté, nouvelle tentative…).
# SILENCIEUX : aucun signal émis — l'appelant sait déjà qu'il annule.
func cancel_steam_login() -> void:
	_stop_steam_polling()
	_steam_phase = ""
	_steam_session_id = ""

# Arrête minuterie et requête en vol, sans toucher à l'état de session (jwt_token…).
func _stop_steam_polling() -> void:
	if _steam_timer != null:
		_steam_timer.stop()
	if _steam_http != null:
		_steam_http.cancel_request()
	_steam_poll_in_flight = false

# Fin d'un flux Steam en ÉCHEC : on remet tout à zéro puis on prévient la Vue (le bouton se
# réactive sur `auth_failed`, cf. auth_screen).
func _end_steam_login(error_msg: String) -> void:
	cancel_steam_login()
	emit_signal("auth_failed", error_msg)

# Tic d'interrogation (toutes les 2 s) : GET /auth/steam/poll tant que le joueur n'a pas fini.
func _on_steam_poll_tick() -> void:
	if _steam_phase != "poll":
		return
	if Time.get_ticks_msec() - _steam_started_at_ms > STEAM_LOGIN_TIMEOUT_MS:
		_end_steam_login(tr("AUTHM_STEAM_TIMEOUT"))
		return
	if _steam_poll_in_flight:
		return
	_steam_poll_in_flight = true
	var err = _steam_http.request(
		base_url + "/api/v1/auth/steam/poll?session_id=" + _steam_session_id.uri_encode(),
		[],
		HTTPClient.METHOD_GET
	)
	if err != OK:
		# Échec d'ÉMISSION (pile réseau occupée) : sans conséquence, le tic suivant réessaiera.
		_steam_poll_in_flight = false

func _on_steam_request_completed(_result, response_code, _headers, body):
	# Parse via une INSTANCE JSON (cf. _on_request_completed) : aucune erreur rouge au débogueur si
	# la réponse n'est pas du JSON (502 d'un reverse-proxy, page d'erreur…).
	var _json := JSON.new()
	var data = _json.data if _json.parse(body.get_string_from_utf8()) == OK else null

	if _steam_phase == "session":
		if response_code != 200 or data == null or not data.has("session_id"):
			_end_steam_login(tr("AUTHM_STEAM_SESSION_FAILED"))
			return
		_steam_session_id = str(data["session_id"])
		# Le joueur s'authentifie dans SON navigateur : Godot n'a aucun moyen d'être rappelé
		# (ni serveur HTTP local, ni deep-link) — d'où le passage en mode interrogation.
		OS.shell_open(base_url + "/api/v1/auth/steam/login?session_id=" + _steam_session_id.uri_encode())
		_steam_phase = "poll"
		_steam_timer.start()
		return

	if _steam_phase != "poll":
		return
	_steam_poll_in_flight = false

	if response_code == 200 and data != null and data.has("access_token"):
		# Succès : traitement STRICTEMENT identique à l'ancien login par mot de passe — le token
		# Steam est un JWT ordinaire (même secret, même claim `sub`), toute la suite est inchangée.
		jwt_token = str(data["access_token"])
		_stop_steam_polling()
		_steam_phase = ""
		_steam_session_id = ""
		_save_session()
		var sub := _username_from_jwt(jwt_token)
		if sub != "":
			username = sub
		emit_signal("auth_success", tr("AUTHM_LOGIN_SUCCESS"))
		_fetch_user_id()
	elif response_code == 404:
		# Session inconnue/expirée côté serveur, ou callback Steam en échec : inutile d'attendre
		# le rebours complet, le serveur ne délivrera plus rien pour ce session_id.
		_end_steam_login(tr("AUTHM_STEAM_TIMEOUT"))
	# Tout autre cas ({"status":"pending"}, incident réseau passager) : on laisse le tic suivant
	# retenter — c'est le rebours global de 180 s qui tranche.

func get_profile():
	# Check if we have a token
	if jwt_token == "":
		emit_signal("auth_failed", tr("AUTHM_NO_TOKEN"))
		return

	# Une requête /auth/me est DÉJÀ en vol : top_nav (enfant, dont le _ready précède celui de
	# l'écran hôte) et l'écran Profil/Classement appellent tous deux get_profile() au montage.
	# On SAUTE l'appel — surtout ne pas rappeler request() : le moteur LOGGE une erreur rouge
	# (http_request.cpp « Condition "requesting" is true ») AVANT même de rendre ERR_BUSY, un
	# garde sur le code de retour ne suffirait donc pas. La réponse en vol émettra profile_loaded
	# pour TOUS les auditeurs (chacun s'abonne AVANT d'appeler), personne ne perd rien.
	if _profile_in_flight:
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
		emit_signal("auth_failed", tr("AUTHM_PROFILE_SEND_FAILED"))
		return
	_profile_in_flight = true

func _on_request_completed(_result, response_code, _headers, body):
	_profile_in_flight = false
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
				emit_signal("auth_success", tr("AUTHM_LOGIN_SUCCESS"))
				# Dès qu'on a le token, on récupère l'ID numérique du joueur en arrière-plan.
				_fetch_user_id()
			# Détection de la réponse /auth/me. ⚠️ §8.113 : on teste `id` et NON PLUS `email` —
			# depuis l'authentification Steam, aucun compte n'a d'email (le champ reste EXPOSÉ mais
			# vaut `null`, si bien que `has("email")` restait vrai : contrôle devenu trompeur, et
			# faux dès qu'un serveur cesserait d'émettre la clé). `id` est TOUJOURS présent dans
			# /auth/me et absent d'une réponse token — la branche `access_token` étant testée
			# AVANT, aucune ambiguïté n'est possible.
			elif data.has("username") and data.has("id"):
				username = str(data["username"])
				# Le profil (/auth/me) contient l'id numérique : on en profite pour le capter.
				if data.has("id"):
					user_id = int(data["id"])
					emit_signal("user_id_loaded", user_id)
				_capture_avatar_url(data)
				_capture_tutorial_flag(data)
				emit_signal("profile_loaded", data)
			elif data.has("message"):
				emit_signal("auth_success", tr("AUTHM_SUCCESS_DETAIL") % str(data["message"]))
			else:
				emit_signal("auth_success", tr("AUTHM_OPERATION_SUCCESS"))
		else:
			emit_signal("auth_success", tr("AUTHM_SUCCESS_NON_JSON"))
			
	# Codes HTTP d'erreur (400, 401, 500...)
	else:
		# i18n : gabarits traduits (AUTHM_HTTP_ERROR*) — le détail renvoyé par le serveur reste
		# dynamique (intraduisible côté client), il est injecté via %s.
		var detail := ""
		if data != null:
			if data.has("detail"):
				detail = str(data["detail"])
			elif data.has("message"):
				detail = str(data["message"])
		else:
			# Si ce n'est pas du JSON (ex: Erreur 500 brute), on affiche le texte reçu
			detail = response_text

		var error_msg: String = tr("AUTHM_HTTP_ERROR") % response_code
		if detail != "":
			error_msg = tr("AUTHM_HTTP_ERROR_DETAIL") % [response_code, detail]
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
	# L'avatar fait partie de l'identité : le laisser en cache afficherait le visage du joueur
	# précédent sur l'écran de connexion du suivant (poste partagé).
	avatar_url = ""
	avatar_texture = null
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(SESSION_PATH)

# Tente de restaurer une session sauvegardée et de la VALIDER auprès du serveur (/auth/me) :
#   - token valide        → signal profile_loaded (+ user_id renseigné) → l'appelant entre au menu ;
#   - token absent/expiré  → signal auth_failed → l'appelant purge et reste sur le login.
# On ne fait JAMAIS confiance au token local seul : seul /auth/me fait foi (il a pu expirer).
func try_restore_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		emit_signal("auth_failed", tr("AUTHM_NO_SAVED_SESSION"))
		return
	var f := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		emit_signal("auth_failed", tr("AUTHM_SESSION_UNREADABLE"))
		return
	var t := f.get_as_text().strip_edges()
	f.close()
	if t == "":
		emit_signal("auth_failed", tr("AUTHM_SESSION_EMPTY"))
		return
	jwt_token = t
	# Pseudo provisoire depuis le claim "sub" (confirmé ensuite par /auth/me).
	var sub := _username_from_jwt(t)
	if sub != "":
		username = sub
	# Validation serveur : /auth/me → profile_loaded (succès) ou auth_failed (401/expiré).
	get_profile()
