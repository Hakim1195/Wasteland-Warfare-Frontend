extends Node
##
## ApiConfig (autoload) — SOURCE UNIQUE des hôtes backend (REST + WebSocket).
##
## Avant : l'URL de prod était codée en dur dans TROIS fichiers (auth_manager, network_manager,
## bootloader) → impossible de tester en local sans éditer chacun. Désormais ces managers lisent
## leur hôte ICI (au démarrage, via /root/ApiConfig). Un seul point à changer.
##
## Bascule dev/prod (par ordre de priorité) :
##   1. Fichier `user://server_host.txt` : contient une URL http(s) (ex: "http://192.168.1.20:8000").
##      Pratique pour pointer une instance précise SANS recompiler. L'hôte WS (ws/wss) en est déduit.
##   2. Argument de ligne de commande `--local` : bascule sur 127.0.0.1:8000 (backend Docker local).
##   3. Sinon : PRODUCTION (api.wasteland-warfare.com).
##
## ⚠️ Doit être le PREMIER autoload (avant AuthManager/NetworkManager) pour que ses valeurs soient
## prêtes quand ceux-ci s'initialisent. Les managers le lisent défensivement (get_node_or_null) et
## retombent sur la prod si l'autoload manque → aucune régression si on le retire.

const PROD_HTTP := "https://api.wasteland-warfare.com"
const PROD_WS := "wss://api.wasteland-warfare.com"
const LOCAL_HTTP := "http://127.0.0.1:8000"
const LOCAL_WS := "ws://127.0.0.1:8000"
const OVERRIDE_FILE := "user://server_host.txt"

# Hôte HTTP de base (sans suffixe). NetworkManager y ajoute "/api/v1", le bootloader "/api".
var http_host: String = PROD_HTTP
# Hôte WebSocket de base (sans suffixe). NetworkManager y ajoute "/ws/".
var ws_host: String = PROD_WS
# Environnement DEV LOCAL (§AC.10) : true quand on parle à un backend loopback / plaintext (--local,
# 127.0.0.1, localhost). En PRODUCTION (domaine réel, certificat Let's Encrypt via Traefik) il reste
# FALSE → le certificat est VÉRIFIÉ (anti-MITM). Recalculé à chaque résolution d'hôte.
var local_dev: bool = false


func _ready() -> void:
	# 1) Override par fichier (une URL http(s) sur la 1re ligne).
	if FileAccess.file_exists(OVERRIDE_FILE):
		var f := FileAccess.open(OVERRIDE_FILE, FileAccess.READ)
		if f != null:
			var custom := f.get_as_text().strip_edges()
			f.close()
			if custom != "":
				_apply_http_host(custom)
				print("ApiConfig: hôte personnalisé (server_host.txt) = ", http_host)
				return

	# 2) Argument --local (éditeur/dev contre un backend Docker local).
	var argv := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if argv.has("--local"):
		http_host = LOCAL_HTTP
		ws_host = LOCAL_WS
		local_dev = true
		print("ApiConfig: mode LOCAL (--local) = ", http_host)
		return

	# 3) Production (défaut).
	print("ApiConfig: mode PRODUCTION = ", http_host)


# Déduit l'hôte WebSocket (ws/wss) à partir d'un hôte HTTP fourni, et normalise (sans "/" final).
func _apply_http_host(host: String) -> void:
	host = host.rstrip("/")
	http_host = host
	ws_host = host.replace("https://", "wss://").replace("http://", "ws://")
	# Dev local si loopback ou plaintext (http/ws) → TLS non vérifié toléré ; sinon prod → vérifié.
	local_dev = host.begins_with("http://") or host.contains("127.0.0.1") or host.contains("localhost")


# Options TLS selon l'environnement (§AC.10) : PRODUCTION → certificat VÉRIFIÉ (client sécurisé,
# anti-MITM) ; dev LOCAL uniquement → certificat toléré non vérifié (backend Docker auto-signé /
# plaintext). client_unsafe() n'est ainsi JAMAIS actif contre le serveur de production.
func tls_options() -> TLSOptions:
	return TLSOptions.client_unsafe() if local_dev else TLSOptions.client()
