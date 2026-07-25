extends Control

# =========================================================================
# ÉCRAN SALON PRIVÉ — Matchmaking 100 % serveur (§8.116)
# =========================================================================
# Remplace intégralement waiting_room, réservé désormais au PRIVÉ (les parties publiques/classées
# ne passent plus par un salon d'attente — cf. search_screen, panneau RECHERCHE). Le CODE est le
# héros de l'écran (très grand, or, espacé) ; AUCUN id de salle, AUCUNE liste de joueurs/pseudos
# n'apparaît nulle part (décision produit n° 2 du chantier). Règle d'Or §6.1 : VUE pure — tout
# passe par NetworkManager (méthodes + signaux), aucun appel HTTP/WS direct ici.
#
# Écran CODE-DRIVEN (§ brief) : la scène .tscn est réduite à un Control racine + ce script, toute
# la hiérarchie est construite ici en _ready()/_build_ui() — aucun @export, aucun câblage éditeur.

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const BG_TEXTURE := preload("res://assets/images/bg_wasteland.png")

# --- Palette canonique (§2, miroir main_menu.gd / profile.gd / search_screen.gd) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)

# Délai de lecture du message « le créateur a fermé le salon » avant bascule vers search_screen
# (sinon le fondu de TransitionManager — 0,35 s — ne laisserait quasiment rien lire).
const SALON_CLOSED_READ_DELAY := 1.6
# Durée d'affichage du flash « CODE COPIÉ ! » avant de revenir au libellé normal du bouton.
const COPY_FLASH_DURATION := 1.6

var _font: SystemFont

# --- Nœuds construits en code ---
var _main_panel: PanelContainer
var _code_label: Label
var _copy_button: Button
var _occupancy_label: Label
var _actions_row: HBoxContainer
var _start_bots_button: Button
var _status_label: Label

var _copy_flash_timer: Timer

# --- État dynamique ---
var _is_creator: bool = false
var _actions_ready: bool = false   # true dès que la 1re salon_state_updated a construit les boutons.
var _last_count: int = 0
var _last_max: int = 0


func _ready() -> void:
	_font = _make_font()
	WarzoneUI.animate_screen_enter(self)
	_build_ui()
	_wire_network_signals()
	AudioManager.start_menu_ambient()
	LocaleManager.locale_changed.connect(_on_locale_changed)

	_code_label.text = _code_display_text()

	# À l'arrivée (brief §DELIVERABLE B) : si le tunnel WS est déjà ouvert (venant de search_screen,
	# qui a déjà appelé connect_to_server au moment de la création/jointure), on demande directement
	# l'état du salon ; sinon on ouvre la connexion et server_connected prendra le relais.
	if NetworkManager.connected:
		NetworkManager.request_salon_state()
	else:
		NetworkManager.connect_to_server(NetworkManager.current_room_id)


func _make_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


func _wire_network_signals() -> void:
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.salon_state_updated.connect(_on_salon_state_updated)
	NetworkManager.salon_closed.connect(_on_salon_closed)
	NetworkManager.game_started_signal.connect(_on_game_started)
	NetworkManager.private_left.connect(_on_private_left)
	# Garde-fou §AC.5 : cet écran n'a pas de top_nav (pré-partie) -> il gère lui-même l'expiration
	# de session, comme search_screen (private_leave/private_start_bots sont des appels REST).
	NetworkManager.session_expired.connect(_on_session_expired)


# =========================================================
# CONSTRUCTION DE L'UI (100 % code — cf. en-tête)
# =========================================================
func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = BG_TEXTURE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(640, 520)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(GUNMETAL, 0.92)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(2)
	pstyle.border_color = Color(ACCENT, 0.7)
	pstyle.set_content_margin_all(40.0)
	_main_panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(_main_panel)
	WarzoneUI.add_corner_notches(_main_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_panel.add_child(root)

	# --- Eyebrow « SALON PRIVÉ » (rythme eyebrow -> valeur §2, la valeur étant le code ci-dessous) ---
	var eyebrow := Label.new()
	eyebrow.text = "SALON_TITLE"  # clé brute -> auto-traduction
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 15)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(eyebrow)

	# --- Le CODE en héros : très grand, or, espacé lettre par lettre ("K 7 R D 2") ---
	_code_label = Label.new()
	_code_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_code_label.add_theme_font_override("font", _font)
	_code_label.add_theme_font_size_override("font_size", 72)
	_code_label.add_theme_color_override("font_color", GOLD)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_code_label)

	_copy_button = Button.new()
	_copy_button.text = "SALON_COPY"  # clé brute -> auto-traduction (bascule vers SALON_COPIED au clic)
	_copy_button.add_theme_font_override("font", _font)
	_copy_button.add_theme_font_size_override("font_size", 14)
	_copy_button.custom_minimum_size = Vector2(210, 44)
	_copy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	WarzoneUI.apply_ghost_button(_copy_button)
	_copy_button.pressed.connect(_on_copy_pressed)
	WarzoneUI.wire_button_sfx(_copy_button)
	root.add_child(_copy_button)

	var hint := Label.new()
	hint.text = "SALON_SHARE_HINT"  # clé brute -> auto-traduction
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(420, 0)
	root.add_child(hint)

	WarzoneUI.add_filet(root)

	# --- Occupation INDIVIDUALISÉE (décision n° 2 : ni liste, ni pseudo, ni id) ---
	_occupancy_label = Label.new()
	_occupancy_label.text = "COMMON_SYNCING"  # placeholder avant la 1re réponse (cf. profile.tscn).
	_occupancy_label.add_theme_font_override("font", _font)
	_occupancy_label.add_theme_font_size_override("font_size", 22)
	_occupancy_label.add_theme_color_override("font_color", TEXT)
	_occupancy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_occupancy_label)

	WarzoneUI.add_filet(root)

	# --- Actions (contenu dépendant d'is_creator, construit à la 1re salon_state_updated) ---
	_actions_row = HBoxContainer.new()
	_actions_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions_row.add_theme_constant_override("separation", 14)
	root.add_child(_actions_row)

	# --- Statut (fermeture par l'hôte…) — masqué tant que rien à dire ---
	_status_label = Label.new()
	_status_label.add_theme_font_override("font", _font)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", DANGER)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	root.add_child(_status_label)


# Construit les boutons d'action selon le rôle — UNE SEULE FOIS (is_creator ne change jamais pour
# un joueur donné dans un salon donné) : créateur -> LANCER AVEC BOTS + FERMER ; membre -> QUITTER.
func _build_actions(is_creator: bool) -> void:
	_clear(_actions_row)
	if is_creator:
		_start_bots_button = Button.new()
		_style_cta(_start_bots_button)
		_start_bots_button.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_start_bots_button.text = "❯ " + tr("SALON_START_BOTS")
		_start_bots_button.custom_minimum_size = Vector2(240, 56)
		_start_bots_button.pressed.connect(_on_start_bots_pressed)
		WarzoneUI.wire_button_sfx(_start_bots_button)
		_actions_row.add_child(_start_bots_button)

		var close_btn := Button.new()
		close_btn.text = "SALON_CLOSE"  # clé brute -> auto-traduction
		close_btn.add_theme_font_override("font", _font)
		close_btn.add_theme_font_size_override("font_size", 15)
		close_btn.custom_minimum_size = Vector2(200, 56)
		WarzoneUI.apply_ghost_button(close_btn)
		close_btn.pressed.connect(_on_close_pressed)
		WarzoneUI.wire_button_sfx(close_btn)
		_actions_row.add_child(close_btn)
	else:
		var leave_btn := Button.new()
		leave_btn.text = "SALON_LEAVE"  # clé brute -> auto-traduction
		leave_btn.add_theme_font_override("font", _font)
		leave_btn.add_theme_font_size_override("font_size", 15)
		leave_btn.custom_minimum_size = Vector2(220, 56)
		WarzoneUI.apply_ghost_button(leave_btn)
		leave_btn.pressed.connect(_on_leave_pressed)
		WarzoneUI.wire_button_sfx(leave_btn)
		_actions_row.add_child(leave_btn)


# Style CTA cyan plein (miroir main_menu.gd / search_screen.gd::_style_cta).
func _style_cta(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(16.0)
	normal.bg_color = Color(ACCENT, 0.16)
	normal.set_border_width_all(2)
	normal.border_color = ACCENT
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.32)
	hover.shadow_color = Color(ACCENT, 0.5)
	hover.shadow_size = 12
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(ACCENT, 0.55)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)

func _set_actions_disabled(disabled: bool) -> void:
	for child in _actions_row.get_children():
		if child is Button:
			child.disabled = disabled


# Rendu du code espacé lettre par lettre ("K7RD2" -> "K 7 R D 2", cf. brief). "—" de repli si le
# code est encore vide (garde défensive — ne devrait pas arriver dans le flux normal : search_screen
# pose current_salon_code AVANT de naviguer ici).
func _code_display_text() -> String:
	var code := str(NetworkManager.current_salon_code)
	if code == "":
		return "—"
	var out := ""
	for i in code.length():
		if i > 0:
			out += " "
		out += code[i]
	return out


func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# =========================================================
# SIGNAUX RÉSEAU (NetworkManager — Règle d'Or §6.1 : jamais d'appel HTTP/WS direct ici)
# =========================================================

# Le tunnel WS vient de s'ouvrir (cas "pas déjà connecté" du brief) -> on demande l'état du salon.
func _on_server_connected() -> void:
	if not is_inside_tree():
		return
	NetworkManager.request_salon_state()


# Occupation individualisée (§8.116 décision n° 2) : AUCUNE liste, AUCUN pseudo, AUCUN id. Les
# boutons d'action ne dépendent que d'is_creator, qui ne change jamais pour un joueur donné dans un
# salon donné -> construits une seule fois, la ligne d'occupation seule se rafraîchit ensuite.
func _on_salon_state_updated(count: int, max_players: int, is_creator: bool) -> void:
	if not is_inside_tree():
		return
	_last_count = count
	_last_max = max_players
	_occupancy_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_occupancy_label.text = tr("SALON_OCCUPANCY") % [count, max_players]
	if not _actions_ready:
		_is_creator = is_creator
		_build_actions(is_creator)
		_actions_ready = true


# L'hôte a fermé le salon (bouton FERMER ou déconnexion créateur, cf. master doc §4.5) : on quitte
# proprement le WS, on affiche le message le temps de le lire, puis on retourne à la recherche.
func _on_salon_closed(_reason: String) -> void:
	if not is_inside_tree():
		return
	NetworkManager.leave_room()
	_set_actions_disabled(true)
	_status_label.text = "SALON_CLOSED_BY_HOST"  # clé brute -> auto-traduction
	_status_label.visible = true
	await get_tree().create_timer(SALON_CLOSED_READ_DELAY).timeout
	if is_inside_tree():
		TransitionManager.change_scene("res://scenes/ui/search_screen.tscn")


func _on_game_started() -> void:
	if not is_inside_tree():
		return
	TransitionManager.change_scene("res://scenes/faction_selection/faction_selection.tscn")


# Réponse à private_leave() (créateur = FERMER, ou membre = QUITTER si le double appel de
# _on_leave_pressed n'a pas déjà navigué — idempotent : change_scene/leave_room tolèrent l'appel en
# double, cf. rapport de fin de tâche).
func _on_private_left(_data: Dictionary) -> void:
	if not is_inside_tree():
		return
	NetworkManager.leave_room()
	TransitionManager.change_scene("res://scenes/ui/search_screen.tscn")


func _on_session_expired() -> void:
	if not is_inside_tree():
		return
	AuthManager.session_notice = tr("AUTH_SESSION_EXPIRED")
	AuthManager.clear_session()
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")


# =========================================================
# ACTIONS UI — chaque bouton est déjà câblé via WarzoneUI.wire_button_sfx (hover+clic) : ne JAMAIS
# rejouer "click" ici (double son).
# =========================================================
func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(str(NetworkManager.current_salon_code))
	_copy_button.text = "SALON_COPIED"  # clé brute -> auto-traduction, revient à SALON_COPY ensuite
	if _copy_flash_timer == null:
		_copy_flash_timer = Timer.new()
		_copy_flash_timer.one_shot = true
		_copy_flash_timer.timeout.connect(_on_copy_flash_timeout)
		add_child(_copy_flash_timer)
	_copy_flash_timer.start(COPY_FLASH_DURATION)

func _on_copy_flash_timeout() -> void:
	_copy_button.text = "SALON_COPY"

func _on_start_bots_pressed() -> void:
	NetworkManager.private_start_bots()

# Créateur : la navigation attend la confirmation serveur (_on_private_left) — fermer un salon
# diffuse salon_closed aux AUTRES membres, on laisse le serveur faire foi avant de partir nous-mêmes.
func _on_close_pressed() -> void:
	NetworkManager.private_leave()

# Membre simple : on quitte immédiatement (rien à attendre d'autrui) — private_leave() nettoie la
# membership côté serveur en tâche de fond, leave_room() coupe notre propre WS tout de suite.
func _on_leave_pressed() -> void:
	NetworkManager.private_leave()
	NetworkManager.leave_room()
	TransitionManager.change_scene("res://scenes/ui/search_screen.tscn")


func _on_locale_changed(_code: String) -> void:
	# Ne ré-applique le format QUE si de vraies données sont déjà arrivées — sinon on écraserait le
	# placeholder "COMMON_SYNCING" (clé brute, auto-traduite seule) par un trompeur "0/0".
	if _actions_ready:
		_occupancy_label.text = tr("SALON_OCCUPANCY") % [_last_count, _last_max]
	if _start_bots_button:
		_start_bots_button.text = "❯ " + tr("SALON_START_BOTS")
