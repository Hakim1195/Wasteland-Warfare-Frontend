extends Control

# =========================================================================
# ÉCRAN DE RECHERCHE — Matchmaking 100 % serveur (§8.116)
# =========================================================================
# Remplace intégralement lobby_screen (liste de salles / scan / join par ID). Le joueur ne voit
# plus JAMAIS d'id de salle ni de liste : il choisit son mode (hérité de MatchConfig depuis le
# Menu Principal), lance une recherche (file publique ou classée) ou crée/rejoint un salon privé
# par code à 5 caractères. Règle d'Or §6.1 : VUE pure — tout passe par NetworkManager (méthodes +
# signaux), aucun appel HTTP direct ici.
#
# Deux panneaux EXCLUSIFS (un seul visible à la fois, cf. _show_config / _show_search) :
#   • CONFIGURATION : sélection de carte (casual) ou rappel classé + CTA recherche + bloc salon
#     privé (créer / rejoindre par code). Sous-état « reprise » si une partie est déjà en cours.
#   • RECHERCHE : état animé (points de suspension) + chrono discret + bouton ANNULER.
#
# Écran CODE-DRIVEN (§ brief) : la scène .tscn est réduite à un Control racine + ce script, toute
# la hiérarchie est construite ici en _ready()/_build_ui() — aucun @export, aucun câblage éditeur.

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const BG_TEXTURE := preload("res://assets/images/bg_wasteland.png")

# --- Palette canonique (§2, miroir main_menu.gd / profile.gd) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)

# --- Modes (miroir main_menu.gd::MODES — juste id -> clé de libellé) ---
const MODE_NAME_KEYS := {
	"trio": "MENU_MODE_TRIO",
	"quad": "MENU_MODE_QUAD",
	"five": "MENU_MODE_FIVE",
	"exa": "MENU_MODE_EXA",
	"ranked": "MENU_MODE_RANKED",
}

# --- Cartes proposées en casual (miroir lobby_screen.gd::_MAP_CHOICES, clés NEUVES §8.116) ---
const _MAP_CHOICES := ["classic_42", "skirmish_atlantic"]
const _MAP_KEYS := {"classic_42": "MM_MAP_CLASSIC", "skirmish_atlantic": "MM_MAP_FAST"}
# Sous-titre (visible sur la tuile) + infobulle détaillée : « CLASSIQUE » / « RAPIDE » ne disent pas
# CE QUI CHANGE. Les chiffres reflètent le registre `MapData.MAP_DEFS` / backend `map_data.MAPS`
# (classic_42 = 42 territoires sur 6 continents, 3-6 ; skirmish_atlantic = 20 territoires sur 3
# continents, 3-4) — si une carte est ajoutée/rééquilibrée un jour, mettre CES clés à jour.
const _MAP_SUB_KEYS := {"classic_42": "MM_MAP_CLASSIC_SUB", "skirmish_atlantic": "MM_MAP_FAST_SUB"}
const _MAP_HINT_KEYS := {"classic_42": "MM_MAP_CLASSIC_HINT", "skirmish_atlantic": "MM_MAP_FAST_HINT"}

# --- Classée (miroir lobby_screen.gd / backend api/game/ranked.py — RANKED_PLAYER_COUNT) ---
const RANKED_PLAYER_COUNT := 5
const RANKED_MAP_ID := "classic_42"

# --- Cadences (§8.116 : poll piloté par l'ÉCRAN, jamais par le manager, cf. brief) ---
const STATUS_POLL_INTERVAL := 2.0
const ELLIPSIS_INTERVAL := 0.5
const NOTICE_DURATION := 2.5

var _font: SystemFont

# --- Intention de partie lue de MatchConfig au _ready, FIGÉE pour la durée de l'écran (changer de
# mode implique de repasser par le Menu Principal via RETOUR). ---
var _required_players: int = 3
var _required_ranked: bool = false
var _mode_id: String = ""
var _selected_map_id: String = "classic_42"

# --- Nœuds construits en code ---
var _main_panel: PanelContainer
var _eyebrow_label: Label
var _config_panel: VBoxContainer
var _normal_config_box: VBoxContainer
var _resume_box: VBoxContainer
var _search_panel: VBoxContainer
var _back_button: Button

var _map_tiles: Dictionary = {}   # map_id -> {"panel":PanelContainer,"button":Button,"label":Label}
var _ranked_reminder_label: Label
# Ligne « explication des points » (classée : barème RP / casual : aucun RP). Une SEULE des deux
# branches est construite par écran -> une seule référence suffit. Mémorisée pour re-résoudre son
# infobulle au changement de langue (le libellé, lui, s'auto-traduit via sa clé brute).
var _points_hint_label: Label
var _points_hint_key: String = ""
var _search_cta_button: Button
var _code_input: LineEdit
var _config_status_label: Label
var _resume_button: Button

var _state_label: Label
var _chrono_label: Label
var _cancel_button: Button

var _poll_timer: Timer
var _ellipsis_timer: Timer
var _notice_timer: Timer

# --- État dynamique ---
var _dots: int = 0
var _current_state_key: String = "MM_SEARCHING"
var _since_s: int = 0
var _notice_active: bool = false
var _resume_room_id: int = -1


func _ready() -> void:
	_font = _make_font()
	WarzoneUI.animate_screen_enter(self)
	_read_match_intent()
	_build_ui()
	_wire_network_signals()
	AudioManager.start_menu_ambient()
	LocaleManager.locale_changed.connect(_on_locale_changed)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = STATUS_POLL_INTERVAL
	_poll_timer.timeout.connect(_on_poll_tick)
	add_child(_poll_timer)

	_ellipsis_timer = Timer.new()
	_ellipsis_timer.wait_time = ELLIPSIS_INTERVAL
	_ellipsis_timer.timeout.connect(_on_ellipsis_tick)
	add_child(_ellipsis_timer)

	# REJOUER (correctif) : si un re-queue est en attente, c'est CET écran qui émet la mise en file —
	# pas `NetworkManager.requeue()`. L'émetteur et l'écouteur du signal `mm_queue_result` sont ainsi
	# le MÊME nœud, déjà dans l'arbre : la réponse ne peut plus être jetée par la garde
	# `is_inside_tree()` (c'était la cause du « REJOUER coince sur l'écran de création de partie »).
	var pending: Dictionary = NetworkManager.consume_pending_requeue()
	if not pending.is_empty():
		_start_requeue(pending)
		return
	# Entrée IDEMPOTENTE (§8.116) : on interroge l'état RÉEL avant de figer un panneau -> un retour
	# arrière sauvage (navigateur, ESC…) retombe toujours sur l'état SERVEUR. Le panneau
	# CONFIGURATION reste affiché par défaut le temps de la réponse (pas de flash possible autrement,
	# la requête est asynchrone).
	NetworkManager.mm_queue_status()


# Mise en file d'un RE-QUEUE (REJOUER) : panneau RECHERCHE affiché OPTIMISTE (le joueur a cliqué, il
# doit voir tout de suite qu'il se passe quelque chose), puis requête. Un refus (`banned`, `in_room`,
# HTTP non-200) est rattrapé par `_on_mm_queue_result`, qui rebascule sur CONFIGURATION avec son
# message — l'optimisme n'avale donc aucune erreur.
# ANNULER reste MASQUÉ jusqu'à la confirmation serveur : un bouton qui annulerait un ticket encore
# inexistant serait un mensonge, et ferait diverger l'écran de l'état serveur.
func _start_requeue(mode: Dictionary) -> void:
	_current_state_key = "MM_SEARCHING"
	_since_s = 0
	_dots = 0
	_show_search()
	_cancel_button.visible = false
	_update_state_label()
	_update_chrono()
	if bool(mode.get("is_ranked", false)):
		NetworkManager.mm_queue_join("ranked")
	else:
		NetworkManager.mm_queue_join("casual", str(mode.get("map_id", "classic_42")),
			int(mode.get("max_players", 6)))


func _make_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


# Lit l'intention de partie posée par le Menu Principal (ou par requeue()) — FIGÉE pour la durée
# de l'écran. La classée force son propre effectif/carte (le serveur fait autorité de toute façon).
func _read_match_intent() -> void:
	_mode_id = str(MatchConfig.selected_mode_id)
	_required_ranked = bool(MatchConfig.selected_ranked)
	if _required_ranked:
		_required_players = RANKED_PLAYER_COUNT
		_selected_map_id = RANKED_MAP_ID
	else:
		_required_players = clampi(int(MatchConfig.selected_player_count), 3, 6) \
			if int(MatchConfig.selected_player_count) > 0 else 3
		_selected_map_id = str(MatchConfig.selected_map_id) if str(MatchConfig.selected_map_id) != "" \
			else MapData.DEFAULT_MAP_ID


func _wire_network_signals() -> void:
	NetworkManager.mm_queue_result.connect(_on_mm_queue_result)
	NetworkManager.mm_status_updated.connect(_on_mm_status_updated)
	NetworkManager.mm_left.connect(_on_mm_left)
	NetworkManager.private_created.connect(_on_private_created)
	NetworkManager.private_join_result.connect(_on_private_join_result)
	NetworkManager.game_started_signal.connect(_on_game_started)
	NetworkManager.lobby_error.connect(_on_lobby_error)
	NetworkManager.session_expired.connect(_on_session_expired)


# =========================================================
# CONSTRUCTION DE L'UI (100 % code — cf. en-tête)
# =========================================================
func _build_ui() -> void:
	# Fond statique (cohérence visuelle avec les autres écrans hub — pas de parallaxe/particules
	# ici, contrairement à l'ancien lobby_screen : hors périmètre du brief, complexité non requise).
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
	# Largeur FIXE (le sélecteur de carte ne doit pas élargir le panneau, cf. note lobby_screen) ;
	# hauteur MINIMALE seulement (le contenu casual, plus riche, peut légitimement dépasser).
	_main_panel.custom_minimum_size = Vector2(680, 560)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(GUNMETAL, 0.92)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(2)
	pstyle.border_color = Color(ACCENT, 0.7)
	pstyle.set_content_margin_all(36.0)
	_main_panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(_main_panel)
	WarzoneUI.add_corner_notches(_main_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	_main_panel.add_child(root)

	_eyebrow_label = Label.new()
	_eyebrow_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_eyebrow_label.add_theme_font_override("font", _font)
	_eyebrow_label.add_theme_font_size_override("font_size", 15)
	_eyebrow_label.add_theme_color_override("font_color", ACCENT)
	_eyebrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_eyebrow_label)
	_refresh_eyebrow()

	WarzoneUI.add_filet(root)

	# --- Panneau CONFIGURATION (état initial) ---
	_config_panel = VBoxContainer.new()
	_config_panel.add_theme_constant_override("separation", 20)
	_config_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_config_panel)
	_build_config_panel()

	# --- Panneau RECHERCHE (après mise en file), masqué au départ ---
	_search_panel = VBoxContainer.new()
	_search_panel.add_theme_constant_override("separation", 20)
	_search_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_search_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search_panel.visible = false
	root.add_child(_search_panel)
	_build_search_panel()

	# --- RETOUR (état configuration UNIQUEMENT, masqué en recherche) ---
	_back_button = Button.new()
	_back_button.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_back_button.add_theme_font_override("font", _font)
	_back_button.add_theme_font_size_override("font_size", 15)
	_back_button.text = "❮ " + tr("MM_BACK_TO_HQ")
	WarzoneUI.apply_ghost_button(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	WarzoneUI.wire_button_sfx(_back_button)
	root.add_child(_back_button)


# --- Panneau CONFIGURATION : contenu normal (ranked OU casual) + sous-état « reprise » ---
func _build_config_panel() -> void:
	_normal_config_box = VBoxContainer.new()
	_normal_config_box.add_theme_constant_override("separation", 20)
	_config_panel.add_child(_normal_config_box)

	if _required_ranked:
		_build_ranked_branch(_normal_config_box)
	else:
		_build_casual_branch(_normal_config_box)

	# Sous-état « reprise » (mm_status_updated == in_game / mm_queue_result reason == in_room) :
	# remplace le contenu normal par un unique CTA « REPRENDRE LA PARTIE ». Masqué au départ.
	_resume_box = VBoxContainer.new()
	_resume_box.add_theme_constant_override("separation", 16)
	_resume_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_resume_box.visible = false
	_config_panel.add_child(_resume_box)
	_build_resume_box()

	# Zone de statut partagée (banni / code indisponible / avertissement tentatives…).
	_config_status_label = Label.new()
	_config_status_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_config_status_label.add_theme_font_override("font", _font)
	_config_status_label.add_theme_font_size_override("font_size", 14)
	_config_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_config_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_config_status_label.visible = false
	_config_panel.add_child(_config_status_label)


# Branche CLASSÉE (§8.116 décision n° 3) : aucun choix — juste le CTA + un rappel de la modalité
# imposée (carte + effectif). Reprend le libellé DÉJÀ traduit du menu (MENU_MODE_RANKED_SUB) plutôt
# que d'inventer une clé neuve pour « CLASSIC 42 — 5 COMMANDANTS ».
func _build_ranked_branch(parent: VBoxContainer) -> void:
	_search_cta_button = Button.new()
	_style_cta(_search_cta_button)
	_search_cta_button.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_search_cta_button.text = "❯ " + tr("MM_SEARCH_CTA")
	_search_cta_button.custom_minimum_size = Vector2(0, 64)
	_search_cta_button.pressed.connect(_on_search_cta_pressed)
	WarzoneUI.wire_button_sfx(_search_cta_button)
	parent.add_child(_search_cta_button)

	_ranked_reminder_label = Label.new()
	_ranked_reminder_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_ranked_reminder_label.add_theme_font_override("font", _font)
	_ranked_reminder_label.add_theme_font_size_override("font_size", 14)
	_ranked_reminder_label.add_theme_color_override("font_color", GOLD)
	_ranked_reminder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(_ranked_reminder_label)
	_refresh_ranked_reminder()

	# Barème RP en INFOBULLE (même principe que les lignes du Classement) : la classée fait GAGNER
	# ou PERDRE des points — le joueur doit pouvoir le savoir AVANT de lancer la recherche.
	_points_hint_label = _make_hint_line(parent, "MM_RANKED_POINTS_LABEL", "MM_RANKED_POINTS_HINT", ACCENT)


# Branche CASUAL : sélecteur de carte (tuiles) + CTA + bloc SALON PRIVÉ (créer / rejoindre par code).
func _build_casual_branch(parent: VBoxContainer) -> void:
	var tiles_row := HBoxContainer.new()
	tiles_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tiles_row.add_theme_constant_override("separation", 16)
	parent.add_child(tiles_row)
	for map_id in _MAP_CHOICES:
		tiles_row.add_child(_build_map_tile(map_id))
	_restrict_map_selector_to_mode()
	_refresh_map_tiles_style()

	# Pendant du barème RP de la branche classée : ici on explique l'INVERSE (aucun RP en jeu), pour
	# que la différence entre les deux modes soit explicite des DEUX côtés.
	_points_hint_label = _make_hint_line(parent, "MM_CASUAL_NO_RP", "MM_CASUAL_NO_RP_HINT", MUTED)

	_search_cta_button = Button.new()
	_style_cta(_search_cta_button)
	_search_cta_button.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_search_cta_button.text = "❯ " + tr("MM_SEARCH_CTA")
	_search_cta_button.custom_minimum_size = Vector2(0, 64)
	_search_cta_button.pressed.connect(_on_search_cta_pressed)
	WarzoneUI.wire_button_sfx(_search_cta_button)
	parent.add_child(_search_cta_button)

	WarzoneUI.add_filet(parent)

	# --- Bloc SALON PRIVÉ ---
	var create_row := HBoxContainer.new()
	create_row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(create_row)

	var create_btn := Button.new()
	create_btn.text = "SALON_CREATE"  # clé brute -> auto-traduction FR/EN/IT
	create_btn.add_theme_font_override("font", _font)
	create_btn.add_theme_font_size_override("font_size", 15)
	create_btn.custom_minimum_size = Vector2(220, 48)
	WarzoneUI.apply_ghost_button(create_btn)
	create_btn.pressed.connect(_on_create_salon_pressed)
	WarzoneUI.wire_button_sfx(create_btn)
	create_row.add_child(create_btn)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 8)
	parent.add_child(join_row)

	_code_input = LineEdit.new()
	# auto_translate_mode s'applique à TOUT le nœud (impossible de l'activer pour placeholder_text
	# et de le couper pour .text séparément) : .text va porter la saisie VIVANTE de l'utilisateur
	# (jamais une clé i18n) -> DÉSACTIVÉ ici, et le placeholder est résolu À LA MAIN (tr() une fois,
	# re-résolu dans _on_locale_changed) plutôt que confié à l'auto-traduction.
	_code_input.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_code_input.placeholder_text = tr("MM_CODE_HINT")
	_code_input.max_length = 5
	_code_input.custom_minimum_size = Vector2(220, 48)
	_code_input.add_theme_font_override("font", _font)
	_code_input.add_theme_font_size_override("font_size", 18)
	_code_input.text_changed.connect(_on_code_text_changed)
	join_row.add_child(_code_input)

	var join_btn := Button.new()
	join_btn.text = "SALON_JOIN"  # clé brute -> auto-traduction
	join_btn.add_theme_font_override("font", _font)
	join_btn.add_theme_font_size_override("font_size", 15)
	join_btn.custom_minimum_size = Vector2(140, 48)
	WarzoneUI.apply_ghost_button(join_btn)
	join_btn.pressed.connect(_on_join_salon_pressed)
	WarzoneUI.wire_button_sfx(join_btn)
	join_row.add_child(join_btn)


# Tuile de carte cliquable (façon carte de mode du menu — cf. main_menu._make_mode_card) : un
# Button PLAT+transparent superposé capte le clic, le contenu visuel ignore la souris. Le SFX de
# clic est joué EXPLICITEMENT dans le handler (comme main_menu) — PAS de wire_button_sfx ici, qui
# doublerait le son (wire_button_sfx connecte déjà pressed -> "click").
func _build_map_tile(map_id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 92)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	var lbl := Label.new()
	lbl.text = _MAP_KEYS[map_id]  # clé brute -> auto-traduction (MM_MAP_CLASSIC / MM_MAP_FAST)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", TEXT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl)

	# Sous-titre MUET (rythme eyebrow -> valeur inversé : la valeur est le nom, le détail dessous).
	# Dit d'un coup d'œil CE QUI DIFFÈRE entre les deux cartes, sans obliger à survoler.
	var sub := Label.new()
	sub.text = _MAP_SUB_KEYS[map_id]  # clé brute -> auto-traduction
	sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.pressed.connect(_on_map_tile_pressed.bind(map_id))
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	panel.add_child(btn)

	WarzoneUI.add_corner_notches(panel, 12.0)
	_map_tiles[map_id] = {"panel": panel, "button": btn, "label": lbl}
	return panel


# Ligne d'aide discrète « libellé + infobulle » (pattern du Classement, cf. leaderboard.gd :
# `row.tooltip_text = tr(...)`). Le LIBELLÉ porte la clé brute -> auto-traduction ; l'INFOBULLE est
# résolue à la main (re-résolue dans _on_locale_changed). ⚠️ Un Label naît en MOUSE_FILTER_IGNORE :
# sans MOUSE_FILTER_STOP il ne recevrait jamais le survol et l'infobulle ne s'afficherait JAMAIS.
func _make_hint_line(parent: Node, label_key: String, hint_key: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = label_key  # clé brute -> auto-traduction FR/EN/IT
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.mouse_default_cursor_shape = Control.CURSOR_HELP
	lbl.tooltip_text = tr(hint_key)
	_points_hint_key = hint_key
	parent.add_child(lbl)
	return lbl


func _refresh_map_tiles_style() -> void:
	for map_id in _map_tiles:
		var entry: Dictionary = _map_tiles[map_id]
		var panel: PanelContainer = entry["panel"]
		var selected: bool = map_id == _selected_map_id
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(0)
		sb.set_content_margin_all(14.0)
		sb.bg_color = GUNMETAL
		if selected:
			sb.bg_color = Color(ACCENT, 0.16)
			sb.set_border_width_all(2)
			sb.border_color = ACCENT
			sb.shadow_color = Color(ACCENT, 0.45)
			sb.shadow_size = 8
		else:
			sb.set_border_width_all(1)
			sb.border_color = Color(ACCENT, 0.3)
		panel.add_theme_stylebox_override("panel", sb)


# Restriction RAPIDE (skirmish_atlantic borné 3-4) selon l'effectif du mode — migré tel quel de
# lobby_screen.gd::_restrict_map_selector_to_mode (désactivé + infobulle, PAS masqué : cohérent
# avec le mécanisme déjà éprouvé, cf. rapport). Le serveur reste seul juge (garde d'UI uniquement).
func _restrict_map_selector_to_mode() -> void:
	for map_id in _MAP_CHOICES:
		if not _map_tiles.has(map_id):
			continue
		var def: Dictionary = MapData.MAP_DEFS.get(map_id, {})
		var max_p := int(def.get("max_players", 6))
		var min_p := int(def.get("min_players", 3))
		var allowed := _required_players >= min_p and _required_players <= max_p
		var entry: Dictionary = _map_tiles[map_id]
		var btn: Button = entry["button"]
		var panel: PanelContainer = entry["panel"]
		btn.disabled = not allowed
		panel.modulate = Color(1, 1, 1, 1) if allowed else Color(1, 1, 1, 0.35)
		# Infobulle = DESCRIPTION de la carte, toujours présente (elle explique ce qui change), à
		# laquelle s'AJOUTE le motif d'indisponibilité quand l'effectif du mode dépasse ses bornes.
		# ⚠️ Un Button `disabled` n'affiche PAS d'infobulle dans Godot : on la pose donc AUSSI sur le
		# panneau (qui, lui, reste survolable) — sinon le joueur perdrait l'explication précisément
		# dans le cas où il en a le plus besoin (« pourquoi cette tuile est-elle grisée ? »).
		var hint := tr(_MAP_HINT_KEYS[map_id])
		if not allowed and _required_players > max_p:
			hint += "\n" + (tr("LOBBY_MAP_MAX_PLAYERS") % max_p)
		btn.tooltip_text = hint
		panel.tooltip_text = hint
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var kept: Dictionary = MapData.MAP_DEFS.get(_selected_map_id, {})
	if _required_players > int(kept.get("max_players", 6)) \
			or _required_players < int(kept.get("min_players", 3)):
		_selected_map_id = MapData.DEFAULT_MAP_ID
		MatchConfig.set_map(_selected_map_id)


func _build_resume_box() -> void:
	_resume_button = Button.new()
	_style_cta(_resume_button)
	_resume_button.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_resume_button.text = "❯ " + tr("MM_RESUME")
	_resume_button.custom_minimum_size = Vector2(0, 64)
	_resume_button.pressed.connect(_on_resume_pressed)
	WarzoneUI.wire_button_sfx(_resume_button)
	_resume_box.add_child(_resume_button)


# --- Panneau RECHERCHE : label d'état animé + chrono discret + ANNULER ---
func _build_search_panel() -> void:
	_state_label = Label.new()
	_state_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_state_label.add_theme_font_override("font", _font)
	_state_label.add_theme_font_size_override("font_size", 26)
	_state_label.add_theme_color_override("font_color", TEXT)
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_search_panel.add_child(_state_label)

	_chrono_label = Label.new()
	_chrono_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_chrono_label.add_theme_font_override("font", _font)
	_chrono_label.add_theme_font_size_override("font_size", 15)
	_chrono_label.add_theme_color_override("font_color", MUTED)
	_chrono_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_search_panel.add_child(_chrono_label)

	_cancel_button = Button.new()
	_cancel_button.text = "MM_CANCEL"  # clé brute -> auto-traduction
	_cancel_button.add_theme_font_override("font", _font)
	_cancel_button.add_theme_font_size_override("font_size", 15)
	_cancel_button.custom_minimum_size = Vector2(240, 48)
	_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	WarzoneUI.apply_ghost_button(_cancel_button)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	WarzoneUI.wire_button_sfx(_cancel_button)
	_search_panel.add_child(_cancel_button)


# Style CTA cyan plein (miroir main_menu.gd::_style_cta) — chevron/lueur au survol via le StyleBox.
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
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)


# =========================================================
# BASCULE DE PANNEAUX (CONFIGURATION <-> RECHERCHE)
# =========================================================
func _show_config(resume: bool) -> void:
	_exit_search_polling()
	_config_panel.visible = true
	_search_panel.visible = false
	_normal_config_box.visible = not resume
	_resume_box.visible = resume
	_back_button.visible = true

func _show_search() -> void:
	_config_panel.visible = false
	_search_panel.visible = true
	_back_button.visible = false
	if _ellipsis_timer.is_stopped():
		_ellipsis_timer.start()

func _enter_search_polling() -> void:
	_show_search()
	if _poll_timer.is_stopped():
		_poll_timer.start()

func _exit_search_polling() -> void:
	_poll_timer.stop()
	_ellipsis_timer.stop()


# =========================================================
# POLL / ANIMATION (Timers pilotés par l'ÉCRAN — cf. brief)
# =========================================================
func _on_poll_tick() -> void:
	NetworkManager.mm_queue_status()

func _on_ellipsis_tick() -> void:
	_dots = (_dots + 1) % 4
	if not _notice_active:
		_update_state_label()

func _update_state_label() -> void:
	_state_label.text = tr(_current_state_key) + ".".repeat(_dots)

func _update_chrono() -> void:
	@warning_ignore("integer_division")
	var m := int(_since_s / 60)
	var s := int(_since_s % 60)
	_chrono_label.text = "%02d:%02d" % [m, s]

func _key_for_state(state: String) -> String:
	match state:
		"searching":
			return "MM_SEARCHING"
		"extending":
			return "MM_EXTENDING"
		"starting", "ready":
			return "MM_STARTING"
		_:
			return "MM_SEARCHING"


# =========================================================
# SIGNAUX RÉSEAU (NetworkManager — Règle d'Or §6.1 : jamais d'appel HTTP direct ici)
# =========================================================
func _on_mm_queue_result(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : réponse arrivée pendant un changement de scène.
	if ok and bool(data.get("queued", false)):
		_set_config_status("", DANGER)  # efface un éventuel message resté affiché (banni, code…).
		_current_state_key = _key_for_state(str(data.get("state", "searching")))
		_since_s = 0
		_dots = 0
		_cancel_button.visible = true
		_enter_search_polling()
		_update_state_label()
		_update_chrono()
		return
	var reason := str(data.get("reason", ""))
	if reason == "banned":
		_show_banned_notice(data)
	elif reason == "in_room":
		_offer_resume(_int_or(data.get("room_id"), -1))
	else:
		# §8.118 — BRANCHE TERMINALE : tout échec NON couvert ci-dessus (HTTP non-200 → `data` vide,
		# `reason` inconnue d'un backend plus récent, `queued=false` inattendu) ne produisait RIEN :
		# le joueur cliquait « RECHERCHER », l'écran ne bougeait pas, et le CTA passait pour mort.
		# On ne laisse plus AUCUN chemin muet — un message générique vaut mieux qu'un bouton inerte.
		# Message SERVEUR prioritaire s'il en fournit un (même lecture défensive que _on_lobby_error).
		var server_msg := str(data.get("message", ""))
		# Retour à un panneau CONFIGURATION utilisable : le CTA y est de nouveau visible et cliquable
		# (il n'est jamais `disabled`), et le poll éventuel est coupé — le joueur réessaie aussitôt.
		_show_config(false)
		_set_config_status(server_msg if server_msg != "" else tr("MM_QUEUE_FAILED"), DANGER)


func _on_mm_status_updated(state: String, since_s: int, room_id: int) -> void:
	if not is_inside_tree():
		return
	match state:
		"idle":
			_poll_timer.stop()
			_show_config(false)
		"in_game":
			_offer_resume(room_id)
		_:
			_current_state_key = _key_for_state(state)
			_since_s = since_s
			_enter_search_polling()
			if not _notice_active:
				_update_state_label()
			_update_chrono()
			_cancel_button.visible = state in ["searching", "extending"]
			if state == "ready":
				_poll_timer.stop()
				NetworkManager.current_room_id = str(room_id)
				NetworkManager.connect_to_server(str(room_id))


func _on_mm_left(left: bool, reason: String) -> void:
	if not is_inside_tree():
		return
	if left:
		_exit_search_polling()
		_show_config(false)
	elif reason == "assigned":
		# « Trop tard » : le matchmaker a déjà sélectionné le ticket -> on laisse la séquence
		# continuer (le poll, déjà actif, reste seul juge de la suite : starting -> ready).
		_show_search_notice(tr("MM_TOO_LATE"))
	# reason == "not_queued" (ou "") : rien à annuler côté serveur, on ne casse rien.


func _offer_resume(room_id: int) -> void:
	_exit_search_polling()
	_resume_room_id = room_id
	_show_config(true)


func _on_game_started() -> void:
	if not is_inside_tree():
		return
	TransitionManager.change_scene("res://scenes/faction_selection/faction_selection.tscn")


func _on_private_created(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree():
		return
	if ok and bool(data.get("created", false)):
		NetworkManager.current_room_id = str(_int_or(data.get("room_id"), -1))
		NetworkManager.current_salon_code = str(data.get("code", ""))
		TransitionManager.change_scene("res://scenes/ui/salon_screen.tscn")
		return
	if str(data.get("reason", "")) == "banned":
		_show_banned_notice(data)


func _on_private_join_result(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree():
		return
	if bool(data.get("joined", false)):
		NetworkManager.current_room_id = str(_int_or(data.get("room_id"), -1))
		# Le code que l'écran affichera dans salon_screen : normalisé comme le fait le serveur.
		NetworkManager.current_salon_code = _code_input.text.strip_edges().to_upper()
		TransitionManager.change_scene("res://scenes/ui/salon_screen.tscn")
		return
	var reason := str(data.get("reason", ""))
	match reason:
		"unavailable":
			if data.has("remaining_attempts"):
				_set_config_status(tr("MM_CODE_WARN") % _int_or(data.get("remaining_attempts"), 0), GOLD)
			else:
				_set_config_status(tr("MM_CODE_UNAVAILABLE"), DANGER)
		"banned":
			_show_banned_notice(data)
		"busy":
			# Pas de clé dédiée dans la liste fournie -> repli explicitement suggéré par le brief
			# (cf. rapport de fin de tâche).
			_set_config_status(tr("MM_CODE_UNAVAILABLE"), DANGER)


func _on_lobby_error(msg: String) -> void:
	if not is_inside_tree():
		return
	if _search_panel.visible:
		_show_search_notice(msg)
		# Récupération (revue §8.116) : un échec de connexion WS à l'état `ready` (close 4000/4003,
		# serveur redéployé entre la file et l'affectation…) laissait un CUL-DE-SAC : poll stoppé,
		# ANNULER masqué, RETOUR invisible. On ré-affiche RETOUR (issue de secours) et on relance le
		# poll : le prochain /status re-propose la partie (ready/in_game → reconnexion via le peer
		# NEUF de connect_to_server) ou retombe sur idle → panneau de configuration.
		_back_button.visible = true
		if _poll_timer.is_stopped():
			_poll_timer.start()
	else:
		_set_config_status(msg, DANGER)


# Garde-fou §AC.5 : cet écran n'a PAS de top_nav (pré-partie) -> il doit gérer lui-même
# l'expiration de session, comme le faisait l'ancien lobby_screen.
func _on_session_expired() -> void:
	if not is_inside_tree():
		return
	AuthManager.session_notice = tr("AUTH_SESSION_EXPIRED")
	AuthManager.clear_session()
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")


# =========================================================
# ACTIONS UI — chaque bouton est déjà câblé via WarzoneUI.wire_button_sfx (hover+clic) : ne JAMAIS
# rejouer "click" ici (double son), sauf les tuiles de carte qui utilisent le pattern manuel dédié.
# =========================================================
func _on_cancel_pressed() -> void:
	NetworkManager.mm_queue_leave()

func _on_search_cta_pressed() -> void:
	if _required_ranked:
		# §8.129 — première mise en file CLASSÉE : RP, divisions, remise à zéro saisonnière. La
		# bulle part AVANT l'appel réseau : elle explique un choix, elle ne commente pas un résultat.
		TutorialManager.hint_once("first_ranked_queue")
		NetworkManager.mm_queue_join("ranked")
	else:
		NetworkManager.mm_queue_join("casual", _selected_map_id, _required_players)

func _on_create_salon_pressed() -> void:
	NetworkManager.private_create(_selected_map_id, _required_players)

func _on_join_salon_pressed() -> void:
	var code := _code_input.text.strip_edges().to_upper()
	if code == "":
		return
	NetworkManager.private_join(code)

func _on_back_pressed() -> void:
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

func _on_resume_pressed() -> void:
	if _resume_room_id < 0:
		return
	NetworkManager.current_room_id = str(_resume_room_id)
	NetworkManager.connect_to_server(str(_resume_room_id))

# Tuile de carte : SFX de clic joué ICI (pas de wire_button_sfx sur ces boutons, cf. _build_map_tile).
func _on_map_tile_pressed(map_id: String) -> void:
	if _map_tiles.has(map_id) and bool(_map_tiles[map_id]["button"].disabled):
		return
	AudioManager.play_sfx("click")
	_selected_map_id = map_id
	MatchConfig.set_map(map_id)
	_refresh_map_tiles_style()


# Filtre de saisie du code salon (§8.116 : 5 caractères, A-Z0-9, MAJUSCULES forcées à la frappe).
func _on_code_text_changed(new_text: String) -> void:
	var sanitized := ""
	for i in new_text.length():
		var c := new_text[i].to_upper()
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			sanitized += c
	if sanitized != new_text:
		var caret := _code_input.caret_column
		_code_input.text = sanitized
		_code_input.caret_column = mini(caret, sanitized.length())


# =========================================================
# NOTICES / STATUT
# =========================================================
func _show_banned_notice(data: Dictionary) -> void:
	_exit_search_polling()
	var epoch := _int_or(data.get("banned_until_epoch"), 0)
	_set_config_status(tr("MM_BANNED") % _format_deadline(epoch), DANGER)
	_show_config(false)

func _set_config_status(text: String, color: Color) -> void:
	_config_status_label.text = text
	_config_status_label.add_theme_color_override("font_color", color)
	_config_status_label.visible = text != ""

# Notice TRANSITOIRE affichée à la place du label d'état (panneau RECHERCHE), ex. MM_TOO_LATE ou
# une erreur réseau bénigne — n'interrompt PAS le poll, juste l'affichage pendant NOTICE_DURATION.
func _show_search_notice(text: String) -> void:
	_notice_active = true
	_state_label.text = text
	if _notice_timer == null:
		_notice_timer = Timer.new()
		_notice_timer.one_shot = true
		_notice_timer.timeout.connect(_on_notice_timeout)
		add_child(_notice_timer)
	_notice_timer.start(NOTICE_DURATION)

func _on_notice_timeout() -> void:
	_notice_active = false
	_update_state_label()


# Piège JSON float (§5) : un nombre issu de JSON.parse_string arrive en float (ou null) -> repli sûr.
func _int_or(value, fallback: int) -> int:
	if value == null:
		return fallback
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return int(value)
	return fallback


# Échéance de bannissement en horodatage NUMÉRIQUE compact et non ambigu (JJ/MM HH:MM) — le %s de
# MM_BANNED est UNIQUE (une seule substitution pour les 3 locales) : un format tout en chiffres
# évite d'encoder des mots d'une langue dans le message d'une autre. Même appel que profile.gd
# (Time.get_datetime_dict_from_unix_time), qui documente déjà ce pattern dans ce dépôt.
func _format_deadline(epoch: int) -> String:
	if epoch <= 0:
		return "—"
	var d := Time.get_datetime_dict_from_unix_time(epoch)
	return "%02d/%02d %02d:%02d" % [int(d.get("day", 1)), int(d.get("month", 1)),
		int(d.get("hour", 0)), int(d.get("minute", 0))]


# =========================================================
# LIBELLÉS COMPOSÉS (re-rendu manuel au changement de langue — auto_translate DISABLED sur ces nœuds)
# =========================================================
func _refresh_eyebrow() -> void:
	var name_key: String = MODE_NAME_KEYS.get(_mode_id, "MENU_MODE_TRIO")
	var label := tr(name_key)
	if _required_ranked:
		label += " — " + tr("MENU_MODE_RANKED_SUB")
	else:
		label += " — " + (tr("MENU_MODE_PLAYERS") % _required_players)
	_eyebrow_label.text = label

func _refresh_ranked_reminder() -> void:
	if _ranked_reminder_label == null:
		return
	_ranked_reminder_label.text = tr("LOBBY_MAP_CLASSIC") + "\n" + tr("MENU_MODE_RANKED_SUB")

func _on_locale_changed(_code: String) -> void:
	_refresh_eyebrow()
	_refresh_ranked_reminder()
	# Infobulles résolues À LA MAIN (les libellés, eux, portent des clés brutes auto-traduites) :
	# celle des tuiles de carte est recomposée par _restrict_map_selector_to_mode (idempotent —
	# mêmes bornes, mêmes conditions), celle de la ligne « points » est ré-appliquée ici.
	if not _map_tiles.is_empty():
		_restrict_map_selector_to_mode()
	if _points_hint_label != null and _points_hint_key != "":
		_points_hint_label.tooltip_text = tr(_points_hint_key)
	if _search_cta_button:
		_search_cta_button.text = "❯ " + tr("MM_SEARCH_CTA")
	if _resume_button:
		_resume_button.text = "❯ " + tr("MM_RESUME")
	if _back_button:
		_back_button.text = "❮ " + tr("MM_BACK_TO_HQ")
	if _code_input:
		_code_input.placeholder_text = tr("MM_CODE_HINT")
	_restrict_map_selector_to_mode()  # ré-traduit aussi les infobulles LOBBY_MAP_MAX_PLAYERS.
	if not _notice_active:
		_update_state_label()
