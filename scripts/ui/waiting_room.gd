extends Control

@export var title_label: Label
@export var player_list: VBoxContainer
@export var ready_button: Button
@export var leave_button: Button
@export var network_status_label: Label
# Panneau central : reçoit les encoches de coin biseautées (charte « Warzone Command » §2).
@export var panel: Control

# Helpers UI partagés de la charte « Warzone Command » (§2).
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

var is_ready: bool = false
# Remplissage IA (G2 §8.72) : échéance UNIX (s) du fill (-1 = aucun) — pilote le compte à rebours
# « REMPLISSAGE IA DANS Xs » affiché dans le statut réseau. Mis à jour à chaque lobby_state.
var _bot_fill_at: float = -1.0

func _ready():
	# Encoches biseautées sur le panneau central (charte §2).
	WarzoneUI.add_corner_notches(panel)

	# Connexion des boutons.
	leave_button.pressed.connect(_on_leave_pressed)
	ready_button.pressed.connect(_on_ready_pressed)

	# SFX d'interface (survol/clic — R6) + nappe d'ambiance des menus (idempotente, R6).
	WarzoneUI.wire_buttons_sfx([ready_button, leave_button])
	AudioManager.start_menu_ambient()

	# Signaux réseau : composition de la salle, démarrage de la partie, erreurs.
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.lobby_state_updated.connect(_on_lobby_state)
	NetworkManager.game_started_signal.connect(_on_game_started)
	NetworkManager.game_error.connect(_on_game_error)

	if title_label:
		title_label.text = tr("WR_TITLE_ROOM") % str(NetworkManager.current_room_id)

	# Si le tunnel est déjà ouvert, on demande tout de suite l'état du lobby.
	if NetworkManager.connected:
		_on_server_connected()
	else:
		network_status_label.text = tr("WR_WS_REALTIME")

func _on_server_connected():
	network_status_label.text = tr("WR_CONNECTED_WAIT")
	network_status_label.add_theme_color_override("font_color", Color(0.211765, 0.772549, 0.85098, 1))
	# On demande la composition actuelle de la salle.
	NetworkManager.request_lobby_state()

func _on_ready_pressed():
	is_ready = !is_ready
	NetworkManager.send_ready(is_ready)
	if is_ready:
		ready_button.text = tr("WR_READY_CANCEL")
		ready_button.modulate = Color(0.211765, 0.772549, 0.85098)
	else:
		ready_button.text = tr("WR_READY")
		ready_button.modulate = Color(1.0, 1.0, 1.0)

func _on_leave_pressed():
	# On coupe proprement le WebSocket et on retourne au lobby.
	NetworkManager.socket.close()
	NetworkManager.connected = false
	NetworkManager.set_process(false)
	TransitionManager.change_scene("res://scenes/ui/lobby_screen.tscn")

func _on_game_started():
	# La partie démarre : tout le monde bascule d'abord vers le Draft (sélection de faction),
	# PAS directement vers l'arène. L'arène (main.tscn) ne sera chargée qu'une fois que tous
	# les joueurs auront verrouillé leur faction (cf. faction_selection.gd).
	network_status_label.text = tr("WR_BRIEFING")
	TransitionManager.change_scene("res://scenes/faction_selection/faction_selection.tscn")

func _on_game_error(message: String):
	network_status_label.text = tr("WR_ERROR_PREFIX") % message

func _process(_delta: float) -> void:
	# Compte à rebours de remplissage IA (G2 §8.72) : tant qu'une échéance est armée, on affiche
	# le nombre de secondes restantes ; le _process s'arrête de facto quand _bot_fill_at repasse à -1.
	if _bot_fill_at > 0.0:
		var remaining := int(ceil(_bot_fill_at - Time.get_unix_time_from_system()))
		if remaining > 0:
			network_status_label.text = tr("WR_BOT_FILL_IN") % remaining
			network_status_label.add_theme_color_override("font_color", Color(0.878431, 0.698039, 0.286275, 1))

# Redessine la liste des joueurs à partir de l'état serveur (ids connectés + ids prêts + pseudos).
func _on_lobby_state(players: Array, ready_ids: Array, usernames: Dictionary = {}):
	# Échéance de remplissage IA (propriété du NetworkManager — le signal garde sa signature).
	_bot_fill_at = NetworkManager.last_bot_fill_at
	if _bot_fill_at <= 0.0:
		# Effectif de la salle (§8.87) : « X / Y joueurs » dès que le serveur le diffuse. Repli
		# SILENCIEUX sur le libellé historique si le champ est absent (VPS non redéployé, §9.2).
		var cap := NetworkManager.last_max_players
		if cap > 0:
			network_status_label.text = tr("WR_LOBBY_STATE_CAP") % [players.size(), cap,
				ready_ids.size()]
		else:
			network_status_label.text = tr("WR_LOBBY_STATE") % [players.size(), ready_ids.size()]

	for child in player_list.get_children():
		child.queue_free()

	# On trie une copie locale par id croissant pour un ordre stable (le serveur ne le garantit
	# pas forcément). On affiche le VRAI pseudo (§8.28), avec repli « Joueur N » si inconnu.
	var ordered := players.duplicate()
	ordered.sort_custom(func(a, b): return int(a) < int(b))

	for i in range(ordered.size()):
		var pid = ordered[i]
		var lbl = Label.new()
		var is_me = int(pid) == AuthManager.user_id
		var is_ready_p = ready_ids.has(pid)
		# Clés du dict usernames = strings (piège JSON §5). ⚠️ pid est un FLOAT (élément d'un Array
		# JSON, non typé) : str(pid) produirait "11.0" et raterait TOUJOURS la clé "11" du dict
		# usernames → le vrai pseudo (§8.28) ne serait jamais résolu (repli permanent « Joueur N »).
		# On coerce donc int() AVANT str(), comme partout ailleurs dans le projet (_faction_of_player…).
		var uname := str(usernames.get(str(int(pid)), ""))
		if uname == "":
			uname = tr("WR_PLAYER_FALLBACK") % (i + 1)
		# Bot de remplissage (G2 §8.72) : id NÉGATIF → préfixe « [IA] » + icône robot.
		var is_bot := int(pid) < 0
		var line = ("🤖 [IA] " + uname) if is_bot else ("👤 " + uname)
		if is_me:
			line += tr("WR_ME_SUFFIX")
		line += "   " + (tr("WR_STATUS_READY") if is_ready_p else tr("WR_STATUS_WAITING"))
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 24)
		if is_ready_p:
			lbl.add_theme_color_override("font_color", Color(0.498039, 1, 0, 1))
		player_list.add_child(lbl)
