extends Control

# =========================================================================
# ÉCRAN ESCOUADE — MODE ÉQUIPES (§8.124)
# =========================================================================
# Cousin de `salon_screen.gd` (même ADN : code en héros, écran 100 % code-driven, Règle d'Or §6.1 —
# VUE pure, tout passe par NetworkManager). DEUX différences assumées, et il faut les connaître :
#
#  1. **LES PSEUDOS SONT AFFICHÉS.** Le salon privé est ANONYME (occupation « N/max », décision
#     §8.116 : un code peut circuler n'importe où). Une escouade, non : on la rejoint parce qu'un
#     AMI vous a passé le code, et voir qui est déjà là en est le minimum vital.
#  2. **L'ESCOUADE SURVIT À LA PARTIE.** Le salon meurt au lancement ; l'escouade est encore là au
#     retour, avec son bouton REJOUER groupé. C'est toute sa raison d'être.
#
# L'écran a DEUX visages selon qu'on a ou non une escouade — construits une fois chacun et
# simplement montrés/cachés (`_no_squad_box` / `_squad_box`), jamais reconstruits : rebâtir la
# hiérarchie à chaque poll ferait clignoter les champs de saisie sous les doigts du joueur.

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const BG_TEXTURE := preload("res://assets/images/bg_wasteland.png")

# --- Palette canonique (§2, miroir salon_screen.gd / search_screen.gd) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)

const COPY_FLASH_DURATION := 1.6
# Cadence du poll d'état — MÊME valeur que le heartbeat de recherche (search_screen) : c'est aussi
# ce poll qui RAFRAÎCHIT le ticket de file côté serveur quand l'escouade cherche une partie.
const POLL_INTERVAL := 2.0

var _font: SystemFont

# --- Nœuds (construits en code) ---
var _root: VBoxContainer
var _no_squad_box: VBoxContainer
var _squad_box: VBoxContainer
var _playlist_row: HBoxContainer
var _code_label: Label
var _copy_button: Button
var _members_box: VBoxContainer
var _queue_button: Button
var _leave_button: Button
var _status_label: Label
var _join_input: LineEdit
var _create_playlist_row: HBoxContainer
var _poll_timer: Timer
var _copy_flash_timer: Timer

# --- État dynamique ---
var _squad: Dictionary = {}          # dernière réponse /squad/* (vide = aucune escouade)
var _playlists: Dictionary = {}      # REGISTRE serveur — aucune valeur en dur ici (§3.1)
var _selected_playlist: String = ""
var _in_queue: bool = false
# Visage RECHERCHE du SOLO (chrono + ANNULER) et contrôles qu'il remplace — cf. `_build_no_squad_box`.
var _solo_queue_box: VBoxContainer = null
var _solo_clock: Label = null
var _no_squad_actions: Array = []
var _queued_since: int = 0
# --- PONT COMPAGNIE (§8.126) : bloc d'AFFICHAGE uniquement, aucun couplage au matchmaking. ---
var _company_box: VBoxContainer = null
var _company: Dictionary = {}   # fiche `GET /company/mine` ({} = pas de compagnie)


func _ready() -> void:
	_font = _make_font()
	WarzoneUI.animate_screen_enter(self)
	_build_ui()
	NetworkManager.squad_state_received.connect(_on_squad_state)
	NetworkManager.team_playlists_loaded.connect(_on_playlists_loaded)
	NetworkManager.mm_status_updated.connect(_on_mm_status)
	NetworkManager.session_expired.connect(_on_session_expired)
	LocaleManager.locale_changed.connect(_on_locale_changed)
	AudioManager.start_menu_ambient()

	# Le REGISTRE d'abord : sans lui on ne sait NI quelles playlists proposer, NI quelle taille
	# d'équipe afficher. L'état d'escouade suit — les deux réponses arrivent dans l'ordre qu'elles
	# veulent, chaque handler se contente de re-rendre.
	# Playlist pré-choisie au menu (carte DUO / ESCOUADE) — MatchConfig ne transporte que l'ID :
	# la carte et l'effectif viennent du registre serveur, jamais d'ici.
	var mc := get_node_or_null("/root/MatchConfig")
	if mc != null:
		_selected_playlist = str(mc.get("selected_team_playlist"))

	NetworkManager.fetch_team_playlists()
	NetworkManager.squad_status()
	# §8.126 — pont COMPAGNIE : demandé UNE fois à l'ouverture (et non à chaque poll — une compagnie
	# ne change pas toutes les 2 secondes, contrairement à une file d'attente).
	NetworkManager.company_state_received.connect(_on_company_state)
	NetworkManager.company_mine()

	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer)
	_poll_timer.start()

	# Chrono de recherche à la SECONDE (le poll, lui, ne bat que toutes les 2 s : un compteur qui
	# saute de 2 en 2 se voit et donne l'impression d'un écran qui rame).
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.timeout.connect(_on_tick)
	add_child(tick)
	tick.start()


func _on_tick() -> void:
	if _in_queue:
		_queued_since += 1
		_refresh_queue_status()


func _make_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


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

	var panel := PanelContainer.new()
	# Panneau ÉLARGI en deux temps : 680×620 → 820×560 → **1080×730** (+32 %). L'écran s'était
	# densifié (règles, formats, deux CTA, jointure par code, visage de recherche) et tout se
	# touchait. L'air entre les blocs n'est pas du vide : c'est ce qui permet de lire l'écran d'un
	# coup d'œil au lieu de le déchiffrer. `custom_minimum_size` reste un PLANCHER — le panneau
	# grandit encore tout seul si un visage demande plus de place.
	panel.custom_minimum_size = Vector2(1080, 730)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(GUNMETAL, 0.92)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(2)
	pstyle.border_color = Color(ACCENT, 0.7)
	pstyle.set_content_margin_all(48.0)
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	_root = VBoxContainer.new()
	# INTERLIGNE ÉLARGI (16 → 22 → 32) en même temps que le cadre : agrandir le panneau sans écarter
	# les lignes ne fait que déplacer la densité, il ne la réduit pas. Seuls les axes VERTICAUX sont
	# écartés — les rangées horizontales (boutons côte à côte) gardent leur écart serré, qui EST ce
	# qui les fait lire comme un groupe.
	_root.add_theme_constant_override("separation", 32)
	# CENTRAGE VERTICAL : sans lui, le contenu reste collé en haut du panneau agrandi et les 200 px
	# gagnés deviennent un TROU sous les boutons au lieu d'une respiration. C'est le centrage qui
	# transforme la hauteur en air — et il tient quel que soit le visage affiché (accueil, escouade,
	# recherche), qui n'ont pas du tout la même hauteur de contenu.
	_root.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(_root)

	# Rythme eyebrow → valeur (§2) : « MODE » puis le nom du mode en grand, OR.
	var eyebrow := Label.new()
	eyebrow.text = "MENU_MODE_EYEBROW_TEAM"  # clé brute -> auto-traduction
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", MUTED)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(eyebrow)

	# Titre + pastille « i ». Les RÈGLES DU MODE (30 min, objectif public, traître possible en 3v3)
	# vivent DANS L'INFOBULLE et non sous le titre : un pavé de trois lignes se lit une fois puis
	# devient du bruit permanent au-dessus de l'écran, alors que derrière un « i » il reste
	# disponible sans jamais encombrer. Même principe que le détail des points du Classement.
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 12)
	_root.add_child(title_row)

	var title := Label.new()
	title.text = "MODE_BATTLE_ROYALE"  # clé brute -> auto-traduction
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_row.add_child(title)

	title_row.add_child(WarzoneUI.make_info_badge(
		self, tr("MODE_BATTLE_ROYALE"), tr("BR_RULES_HINT"), _font, 22.0))

	WarzoneUI.add_filet(_root)

	_build_no_squad_box()
	_build_squad_box()

	_status_label = Label.new()
	_status_label.add_theme_font_override("font", _font)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", DANGER)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.visible = false
	_root.add_child(_status_label)

	WarzoneUI.add_filet(_root)

	var back := Button.new()
	back.text = "COMMON_BACK"  # clé brute -> auto-traduction
	back.add_theme_font_override("font", _font)
	back.add_theme_font_size_override("font_size", 14)
	back.custom_minimum_size = Vector2(180, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	WarzoneUI.apply_ghost_button(back)
	back.pressed.connect(_on_back_pressed)
	WarzoneUI.wire_button_sfx(back)
	_root.add_child(back)


# --- Visage n° 1 : AUCUNE escouade (créer / rejoindre) ---
func _build_no_squad_box() -> void:
	_no_squad_box = VBoxContainer.new()
	_no_squad_box.add_theme_constant_override("separation", 20)
	_root.add_child(_no_squad_box)

	# ⚠️ Plus de pavé explicatif sous le titre (§8.125) : il décrivait la création d'escouade, qui
	# n'est plus la voie principale — le lire juste sous « BATTLE ROYALE » envoyait le joueur seul
	# vers le mauvais bouton. Chaque CTA porte désormais SA propre infobulle, et les règles du mode
	# vivent derrière le « i » du titre.
	# Sélecteur de playlist — peuplé DEPUIS LE REGISTRE serveur (aucune carte en dur).
	_create_playlist_row = HBoxContainer.new()
	_create_playlist_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_create_playlist_row.add_theme_constant_override("separation", 10)
	_no_squad_box.add_child(_create_playlist_row)

	# CTA n° 1 — TROUVER UNE PARTIE, en UN clic et SANS RIEN D'AUTRE À FAIRE.
	#
	# ⚠️ C'est la voie du joueur qui arrive SEUL, et c'est la plus fréquente. La version précédente
	# le faisait passer par une escouade (créée ou rejointe) puis lui demandait ENCORE de cliquer
	# « METTRE EN FILE » — deux manipulations pour un joueur qui veut juste jouer. Ici on l'envoie
	# DIRECTEMENT dans la file d'équipe, sans escouade du tout : le matchmaker le place dans une
	# équipe avec d'autres solos (et complète aux bots au bout de 60 s, comme partout ailleurs).
	# Le serveur sait déjà faire exactement ça — `squad_queue` sans escouade enfile un ticket solo.
	var quick_btn := Button.new()
	_style_cta(quick_btn)
	quick_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	quick_btn.text = "❯ " + tr("SQUAD_FIND_MATCH")
	quick_btn.custom_minimum_size = Vector2(320, 58)
	quick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quick_btn.pressed.connect(_on_find_match_pressed)
	WarzoneUI.wire_button_sfx(quick_btn)
	_no_squad_box.add_child(quick_btn)

	_no_squad_box.add_child(_muted_label("SQUAD_FIND_MATCH_HINT", 12))
	_no_squad_box.add_child(_muted_label("SQUAD_OR_WITH_FRIENDS", 12))

	var create_btn := Button.new()
	_style_cta(create_btn)
	create_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	create_btn.text = "❯ " + tr("SQUAD_CREATE")
	create_btn.custom_minimum_size = Vector2(260, 52)
	create_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create_btn.tooltip_text = tr("SQUAD_CREATE_DESC")
	create_btn.pressed.connect(_on_create_pressed)
	WarzoneUI.wire_button_sfx(create_btn)
	_no_squad_box.add_child(create_btn)

	WarzoneUI.add_filet(_no_squad_box)

	var join_row := HBoxContainer.new()
	join_row.alignment = BoxContainer.ALIGNMENT_CENTER
	join_row.add_theme_constant_override("separation", 10)
	_no_squad_box.add_child(join_row)

	_join_input = LineEdit.new()
	_join_input.placeholder_text = "SQUAD_CODE_PLACEHOLDER"
	_join_input.max_length = 5
	_join_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_input.custom_minimum_size = Vector2(200, 48)
	_join_input.add_theme_font_override("font", _font)
	_join_input.add_theme_font_size_override("font_size", 24)
	_join_input.text_submitted.connect(_on_join_submitted)
	join_row.add_child(_join_input)

	var join_btn := Button.new()
	join_btn.text = "SQUAD_JOIN"  # clé brute -> auto-traduction
	join_btn.add_theme_font_override("font", _font)
	join_btn.add_theme_font_size_override("font_size", 15)
	join_btn.custom_minimum_size = Vector2(180, 48)
	WarzoneUI.apply_ghost_button(join_btn)
	join_btn.pressed.connect(_on_join_pressed)
	WarzoneUI.wire_button_sfx(join_btn)
	join_row.add_child(join_btn)

	# --- Visage RECHERCHE SOLO : le joueur est en file SANS escouade -----------------------------
	# ⚠️ DÉFAUT CORRIGÉ (signalé en jouant : « je ne peux pas annuler une recherche solo »).
	# Le bouton ANNULER vivait dans `_squad_box`, MASQUÉ tant qu'on n'a pas d'escouade — un joueur
	# parti en file seul se retrouvait donc SANS AUCUNE SORTIE, coincé jusqu'à ce qu'une partie se
	# forme. Le visage « aucune escouade » n'avait tout simplement pas d'état « en recherche ».
	# On lui en donne un, exclusif des actions : on ne crée pas d'escouade pendant qu'on cherche.
	_solo_queue_box = VBoxContainer.new()
	_solo_queue_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_solo_queue_box.add_theme_constant_override("separation", 24)
	_solo_queue_box.visible = false
	_no_squad_box.add_child(_solo_queue_box)

	_solo_queue_box.add_child(_muted_label("SQUAD_SEARCHING_TITLE", 13))

	_solo_clock = Label.new()
	_solo_clock.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_solo_clock.add_theme_font_override("font", _font)
	_solo_clock.add_theme_font_size_override("font_size", 52)
	_solo_clock.add_theme_color_override("font_color", GOLD)
	_solo_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_solo_queue_box.add_child(_solo_clock)

	_solo_queue_box.add_child(_muted_label("SQUAD_SOLO_FILL_HINT", 12))

	var cancel_btn := Button.new()
	cancel_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	cancel_btn.text = "❯ " + tr("SQUAD_CANCEL_QUEUE")
	cancel_btn.add_theme_font_override("font", _font)
	cancel_btn.add_theme_font_size_override("font_size", 15)
	cancel_btn.custom_minimum_size = Vector2(260, 50)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	WarzoneUI.apply_ghost_button(cancel_btn)
	cancel_btn.pressed.connect(_on_solo_cancel_pressed)
	WarzoneUI.wire_button_sfx(cancel_btn)
	_solo_queue_box.add_child(cancel_btn)

	# Les CONTRÔLES du visage « aucune escouade », regroupés pour être masqués d'un bloc pendant la
	# recherche (référencés APRÈS coup : ils ont été créés au-dessus, dans l'ordre de la mise en page).
	_no_squad_actions = [_create_playlist_row, quick_btn, create_btn, join_row]
	for node in _no_squad_box.get_children():
		# Les deux libellés d'aide (« vous entrez en file seul », « ou, pour jouer avec vos amis »)
		# doivent disparaître aussi : ils décrivent des actions devenues indisponibles.
		if node is Label:
			_no_squad_actions.append(node)


# --- Visage n° 2 : escouade FORMÉE (code, membres, file) ---
func _build_squad_box() -> void:
	_squad_box = VBoxContainer.new()
	_squad_box.add_theme_constant_override("separation", 20)
	_squad_box.visible = false
	_root.add_child(_squad_box)

	# Le CODE en héros — 72 px, or, espacé lettre par lettre (miroir exact du salon privé).
	_code_label = Label.new()
	_code_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_code_label.add_theme_font_override("font", _font)
	_code_label.add_theme_font_size_override("font_size", 72)
	_code_label.add_theme_color_override("font_color", GOLD)
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_squad_box.add_child(_code_label)

	_copy_button = Button.new()
	_copy_button.text = "SALON_COPY"  # clé PARTAGÉE avec le salon privé (même geste, même mot)
	_copy_button.add_theme_font_override("font", _font)
	_copy_button.add_theme_font_size_override("font_size", 14)
	_copy_button.custom_minimum_size = Vector2(210, 40)
	_copy_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	WarzoneUI.apply_ghost_button(_copy_button)
	_copy_button.pressed.connect(_on_copy_pressed)
	WarzoneUI.wire_button_sfx(_copy_button)
	_squad_box.add_child(_copy_button)

	WarzoneUI.add_filet(_squad_box)

	# Sélecteur de playlist (CHEF uniquement — désactivé pour un membre).
	_playlist_row = HBoxContainer.new()
	_playlist_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_playlist_row.add_theme_constant_override("separation", 10)
	_squad_box.add_child(_playlist_row)

	# Liste des membres AVEC PSEUDOS (différence documentée vs salon anonyme).
	_members_box = VBoxContainer.new()
	_members_box.add_theme_constant_override("separation", 12)
	_squad_box.add_child(_members_box)

	# --- PONT COMPAGNIE (§8.126) ---------------------------------------------------------------
	# Une COMPAGNIE ne se met JAMAIS en file : elle FABRIQUE des escouades. Ce bloc est donc un pont
	# d'AFFICHAGE et rien d'autre — il rappelle qui sont vos camarades de clan pendant que le code
	# d'escouade est à l'écran, à portée de copier-coller. Aucune ligne ici ne touche au matchmaking.
	#
	# ⛔ RESTE À FAIRE ASSUMÉ — bouton « INVITER LA COMPAGNIE » (push du code aux membres EN LIGNE).
	# Il exigerait deux choses que le serveur n'a PAS aujourd'hui : (1) un canal WebSocket de HUB
	# (le seul WS du jeu est `/ws/{room_id}/{player_id}` — il n'existe qu'en partie), et (2) une
	# notion de PRÉSENCE hors partie (rien ne suit qui est connecté au QG). Les inventer pour ce
	# chantier aurait été une infrastructure entière greffée sur un bouton. La v1 livre donc la
	# version AFFICHAGE : le roster + le code à partager (chat Steam, vocal…). Cf. §8.126 des docs.
	_company_box = VBoxContainer.new()
	_company_box.add_theme_constant_override("separation", 6)
	_company_box.visible = false
	_squad_box.add_child(_company_box)

	WarzoneUI.add_filet(_squad_box)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	_squad_box.add_child(actions)

	_queue_button = Button.new()
	_style_cta(_queue_button)
	_queue_button.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_queue_button.text = "❯ " + tr("SQUAD_QUEUE_CTA")
	_queue_button.custom_minimum_size = Vector2(260, 52)
	_queue_button.pressed.connect(_on_queue_pressed)
	WarzoneUI.wire_button_sfx(_queue_button)
	actions.add_child(_queue_button)

	_leave_button = Button.new()
	_leave_button.text = "SQUAD_LEAVE"  # clé brute -> auto-traduction
	_leave_button.add_theme_font_override("font", _font)
	_leave_button.add_theme_font_size_override("font_size", 15)
	_leave_button.custom_minimum_size = Vector2(180, 52)
	WarzoneUI.apply_ghost_button(_leave_button)
	_leave_button.pressed.connect(_on_leave_pressed)
	WarzoneUI.wire_button_sfx(_leave_button)
	actions.add_child(_leave_button)


func _muted_label(key: String, size: int) -> Label:
	var lbl := Label.new()
	lbl.text = key
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", MUTED)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(460, 0)
	return lbl


func _style_cta(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(14.0)
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
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)


func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


# =========================================================
# RENDU (piloté par les données — jamais de reconstruction totale)
# =========================================================
func _playlist_ids() -> Array:
	var ids := _playlists.keys()
	ids.sort()
	return ids


# Boutons de playlist bâtis DEPUIS LE REGISTRE : libellé = clé i18n dérivée de l'id
# (`duo_2v2` → MODE_DUO_2V2), sous-titre = carte + effectif venus du serveur. Une playlist ajoutée
# côté serveur apparaît donc ici sans une ligne de code — il ne manquera qu'une clé de traduction.
func _rebuild_playlist_buttons(row: HBoxContainer, editable: bool) -> void:
	_clear(row)
	for pid in _playlist_ids():
		var spec: Dictionary = _playlists[pid]
		var btn := Button.new()
		btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		btn.text = "%s  (%d)" % [tr("MODE_" + str(pid).to_upper()), int(spec.get("capacity", 0))]
		# PRIX D'ENTRÉE (chantier MODÈLE ÉCONOMIQUE) — servi par playlist dans `GET /squad/playlists`
		# et DÉJÀ remisé pour ce lecteur (le serveur applique son Pass avant d'envoyer). Il s'affiche
		# ICI, sur le bouton, parce que c'est le seul endroit où le chef choisit encore : découvrir
		# un péage après avoir cliqué, c'est un refus qu'on pouvait éviter.
		# ⚠️ UN FRAIS À 0 N'AFFICHE RIEN. Jamais « 0 COINS » : les modes cœur sont gratuits, et écrire
		# leur gratuité en prix la transformerait en tarif.
		var fee := int(spec.get("fee", 0))
		var fee_with_pass := int(spec.get("fee_with_pass", 0))
		if fee > 0:
			btn.text += "  ·  " + tr("FEE_LABEL") % fee
			# Le joueur paie plus cher qu'un détenteur de Pass : on le lui dit, sans encombrer le
			# libellé (l'infobulle est le seul canal qui ne coûte pas un pixel de large).
			if fee_with_pass < fee:
				btn.tooltip_text = tr("FEE_HALF_WITH_PASS")
		btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(200, 44)
		btn.disabled = not editable
		# ⚠️ SÉLECTION VISIBLE — défaut CONSTATÉ EN CAPTURE : avec `toggle_mode` + le style ghost,
		# la playlist choisie était RIGOUREUSEMENT identique à l'autre, et le joueur ne pouvait pas
		# savoir pour quel format il allait chercher une partie. On distingue donc par le STYLE,
		# comme les cartes de mode du QG (fond cyan + bordure pleine = choisi).
		if str(pid) == _selected_playlist:
			_style_selected_playlist(btn)
		else:
			WarzoneUI.apply_ghost_button(btn)
		if editable:
			btn.pressed.connect(_on_playlist_selected.bind(str(pid)))
			WarzoneUI.wire_button_sfx(btn)
		row.add_child(btn)


# Style du bouton de playlist SÉLECTIONNÉ (miroir de `main_menu._card_style(selected)`) : fond
# cyan translucide + bordure pleine + halo. La cohérence avec la carte de mode du QG est voulue —
# c'est le même choix, poursuivi d'un écran à l'autre.
func _style_selected_playlist(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(10.0)
	sb.bg_color = Color(ACCENT, 0.20)
	sb.set_border_width_all(2)
	sb.border_color = ACCENT
	sb.shadow_color = Color(ACCENT, 0.45)
	sb.shadow_size = 8
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_disabled_color", MUTED)


func _rebuild_members() -> void:
	_clear(_members_box)
	var members: Array = _squad.get("members", [])
	var team_size := int(_squad.get("team_size", 0))
	var header := Label.new()
	header.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	header.text = "%s  %d/%d" % [tr("SQUAD_MEMBERS"), members.size(), team_size]
	header.add_theme_font_override("font", _font)
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_members_box.add_child(header)

	for m in members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var line := Label.new()
		line.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		# ★ = le CHEF. Un caractère, pas une icône : il rend dans TOUTES les polices de repli
		# (leçon des emojis « tofu » des chantiers précédents — ✉/📢/🎯 ne rendaient pas).
		var mark := "★ " if bool(m.get("is_leader", false)) else "   "
		line.text = mark + str(m.get("name", ""))
		line.add_theme_font_override("font", _font)
		line.add_theme_font_size_override("font_size", 18)
		line.add_theme_color_override("font_color", GOLD if bool(m.get("is_leader", false)) else TEXT)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_members_box.add_child(line)

	# Places libres — affichées EXPLICITEMENT : « 1/2 » ne dit pas au joueur qu'il peut encore
	# inviter quelqu'un, une ligne « — LIBRE — » si.
	for _i in range(max(0, team_size - members.size())):
		var slot := _muted_label("SQUAD_SLOT_FREE", 15)
		slot.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_INHERIT
		_members_box.add_child(slot)


# --- PONT COMPAGNIE (§8.126) ---------------------------------------------------------------------
# Ligne de retour de l'invitation (succès ou raison de refus) — recréée avec la section compagnie.
var _invite_hint: Label = null

func _on_invite_company_pressed() -> void:
	AudioManager.play_sfx("click")
	if _invite_hint != null and is_instance_valid(_invite_hint):
		_invite_hint.text = tr("COMPANY_INVITE_SENDING")
		_invite_hint.visible = true
	NetworkManager.company_invite()


func _on_company_state(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree() or not ok:
		return
	# ⚠️ `POST /company/invite` PARTAGE ce callback (toutes les routes `/company/*` passent par le
	# même signal). Sa réponse est `{invited, reason}` et ne porte AUCUNE clé `company` : la traiter
	# comme un état ferait tomber `_company` à {} et FERAIT DISPARAÎTRE toute la section compagnie
	# au moment précis où l'on vient d'inviter. On la reconnaît donc à sa clé propre et on sort.
	if data.has("invited"):
		_show_invite_result(bool(data.get("invited", false)), str(data.get("reason", "")))
		return
	var c = data.get("company")
	_company = c if typeof(c) == TYPE_DICTIONARY else {}
	_rebuild_company_section()


# Retour de l'invitation, à côté du bouton. Les raisons de refus sont celles du serveur (convention
# zéro-4xx §8.112) : on les traduit, on n'en invente aucune.
const INVITE_REASONS := {
	"no_company": "COMPANY_INVITE_ERR_NO_COMPANY",
	"no_squad": "COMPANY_INVITE_ERR_NO_SQUAD",
	"not_leader": "COMPANY_INVITE_ERR_NOT_LEADER",
}

func _show_invite_result(invited: bool, reason: String) -> void:
	if _invite_hint == null or not is_instance_valid(_invite_hint):
		return
	_invite_hint.visible = true
	if invited:
		_invite_hint.add_theme_color_override("font_color", GOLD)
		_invite_hint.text = tr("COMPANY_INVITE_SENT")
		return
	_invite_hint.add_theme_color_override("font_color", DANGER)
	_invite_hint.text = tr(str(INVITE_REASONS.get(reason, "COMPANY_INVITE_ERR_NO_SQUAD")))


# Section « COMPAGNIE » de l'écran Escouade : le clan + son roster, à côté du code d'escouade déjà
# affiché en héros. Masquée si le joueur n'a pas de compagnie — un bandeau vide n'invite à rien.
#
# ⚠️ AUCUN STATUT « EN LIGNE ». Le serveur n'a pas de présence hors partie (cf. le commentaire de
# `_build_squad_box`) ; afficher une pastille verte devinée côté client serait un mensonge, et c'est
# précisément le genre de mensonge qui fait attendre un joueur devant un ami absent.
func _rebuild_company_section() -> void:
	if _company_box == null:
		return
	_clear(_company_box)
	if _company.is_empty():
		_company_box.visible = false
		return
	_company_box.visible = true

	var head := Label.new()
	head.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	head.text = "%s  —  [%s] %s" % [tr("COMPANY_TITLE"), str(_company.get("tag", "")),
		str(_company.get("name", "")).to_upper()]
	head.add_theme_font_override("font", _font)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_company_box.add_child(head)

	# Le code d'escouade est DÉJÀ en héros au-dessus : on ne le répète pas, on dit quoi en faire.
	var hint := _muted_label("COMPANY_SQUAD_BRIDGE_HINT", 13)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_company_box.add_child(hint)

	# INVITER LA COMPAGNIE (finitions pré-playtest) — réservé au CHEF, et seulement une fois
	# l'escouade créée : sans code à transmettre, l'invitation ne mènerait nulle part. Un membre ne
	# voit donc rien du tout ici (il n'a rien à décider), au lieu d'un bouton grisé de plus.
	if bool(_squad.get("is_leader", false)) and str(_squad.get("code", "")) != "":
		var invite := Button.new()
		invite.text = "❯ " + tr("COMPANY_INVITE_CTA")
		invite.focus_mode = Control.FOCUS_NONE
		invite.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		invite.add_theme_font_override("font", _font)
		invite.add_theme_font_size_override("font_size", 14)
		invite.add_theme_color_override("font_color", GOLD)
		invite.pressed.connect(_on_invite_company_pressed)
		_company_box.add_child(invite)
		_invite_hint = _muted_label("", 12)
		# Texte posé à la main par `tr()` → auto-traduction COUPÉE, sinon Godot re-traduirait une
		# phrase déjà traduite et rendrait la clé brute (piège maison des libellés composés).
		_invite_hint.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_invite_hint.visible = false
		_company_box.add_child(_invite_hint)

	var members: Array = _company.get("members", [])
	var names := PackedStringArray()
	for m in members:
		if typeof(m) == TYPE_DICTIONARY:
			names.append(str(m.get("name", "")).to_upper())
	if names.is_empty():
		return
	var roster := Label.new()
	roster.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	roster.text = " · ".join(names)
	roster.add_theme_font_override("font", _font)
	roster.add_theme_font_size_override("font_size", 13)
	roster.add_theme_color_override("font_color", MUTED)
	roster.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_company_box.add_child(roster)


func _render() -> void:
	var has_squad := bool(_squad.get("squad", false))
	_no_squad_box.visible = not has_squad
	_squad_box.visible = has_squad

	if not has_squad:
		_selected_playlist = _selected_playlist if _selected_playlist != "" else \
			(str(_playlist_ids()[0]) if not _playlist_ids().is_empty() else "")
		# RECHERCHE SOLO en cours → visage RECHERCHE (chrono + ANNULER), actions masquées. Les deux
		# états sont EXCLUSIFS : on ne crée pas d'escouade pendant qu'on cherche une partie.
		_solo_queue_box.visible = _in_queue
		for node in _no_squad_actions:
			if is_instance_valid(node):
				node.visible = not _in_queue
		if _in_queue:
			_refresh_queue_status()
		else:
			_rebuild_playlist_buttons(_create_playlist_row, true)
			_status_label.visible = false
		return

	_code_label.text = _spaced(str(_squad.get("code", "")))
	var is_leader := bool(_squad.get("is_leader", false))
	# ⚠️ LE CHOIX LOCAL DU CHEF FAIT AUTORITÉ TANT QU'IL N'A PAS LANCÉ LA RECHERCHE.
	#
	# Défaut corrigé (signalé après essai : « impossible de choisir le 2v2 ») — cette ligne écrasait
	# `_selected_playlist` par la valeur de l'escouade à CHAQUE rendu. Le chef cliquait « DUO 2v2 »,
	# `_on_playlist_selected` posait son choix, `_render()` le REMPLAÇAIT aussitôt par l'ancien
	# format, et le bouton se ré-allumait sur le précédent : le clic semblait mort. Le format était
	# donc figé dès la création de l'escouade — exactement le symptôme observé.
	#
	# POURQUOI le choix local doit gagner : il n'existe AUCUN endpoint « changer la playlist » côté
	# serveur (décision §8.124 — le format part avec `POST /squad/queue`). Entre le clic et la mise
	# en file, la seule source de vérité EST donc le client. Un MEMBRE, lui, n'édite rien : il
	# reflète toujours l'escouade, sinon il lirait un format que le chef n'a pas choisi.
	if not is_leader or _in_queue:
		_selected_playlist = str(_squad.get("playlist", _selected_playlist))
	elif _selected_playlist == "":
		_selected_playlist = str(_squad.get("playlist", ""))
	# Seul le CHEF change le format et lance la recherche. Les boutons du membre sont DÉSACTIVÉS
	# plutôt que cachés : il doit VOIR le format choisi, sinon il ne sait pas ce qu'il attend.
	_rebuild_playlist_buttons(_playlist_row, is_leader and not _in_queue)
	_rebuild_members()

	_queue_button.disabled = not is_leader
	if _in_queue:
		_queue_button.text = "❯ " + tr("SQUAD_CANCEL_QUEUE")
		_refresh_queue_status()
	else:
		_queue_button.text = "❯ " + tr("SQUAD_QUEUE_CTA")
		_status_label.visible = false


# Bandeau de recherche : « ESCOUADE 2/3 EN FILE — 01:24 ». Le CHRONO est le correctif de parcours
# du §8.125 : sans lui, mettre en file n'affichait rien de vivant et le joueur ne savait pas si la
# recherche tournait ou si l'écran avait planté. C'est exactement ce que le panneau RECHERCHE des
# files solo affiche depuis §8.116 — il n'y avait aucune raison que le mode équipe en soit privé.
func _refresh_queue_status() -> void:
	if not _in_queue:
		return
	# SOLO : le visage RECHERCHE porte DÉJÀ le titre, le chrono en 52 px et la mention « vous serez
	# associé à des coéquipiers ». Le bandeau de statut redirait exactement la même chose une ligne
	# plus bas (doublon constaté en capture) — on le tait et on ne met à jour que le compteur.
	if _solo_clock != null and not bool(_squad.get("squad", false)):
		_solo_clock.text = "%02d:%02d" % [_queued_since / 60, _queued_since % 60]
		_status_label.visible = false
		return
	var members: Array = _squad.get("members", []) if bool(_squad.get("squad", false)) else []
	var size := members.size() if not members.is_empty() else 1
	var cap := int(_squad.get("team_size", 0)) if bool(_squad.get("squad", false)) else 1
	var clock := "%02d:%02d" % [_queued_since / 60, _queued_since % 60]
	if bool(_squad.get("squad", false)):
		_set_status_raw("%s — %s" % [tr("SQUAD_IN_QUEUE") % [size, cap], clock], ACCENT)
	else:
		# Solo en file d'équipe : on lui rappelle qu'il sera associé à des coéquipiers, sinon
		# l'attente ressemble à une file solo qui ne trouve personne.
		_set_status_raw("%s — %s" % [tr("SQUAD_SOLO_FILL_HINT"), clock], ACCENT)


func _set_status_raw(text: String, color: Color) -> void:
	_status_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_label.visible = true


func _spaced(code: String) -> String:
	if code == "":
		return "—"
	var out := ""
	for i in code.length():
		if i > 0:
			out += " "
		out += code[i]
	return out


func _set_status(key: String, args: Array = [], color: Color = DANGER) -> void:
	_status_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_status_label.text = tr(key) % args if not args.is_empty() else tr(key)
	_status_label.add_theme_color_override("font_color", color)
	_status_label.visible = true


# =========================================================
# SIGNAUX RÉSEAU
# =========================================================
func _on_playlists_loaded(playlists: Dictionary) -> void:
	if not is_inside_tree():
		return
	_playlists = playlists
	_render()


# Réponse COMMUNE des six routes /squad/* : on la stocke telle quelle et on re-rend. Les REFUS
# (`squad:false` + `reason`) ne détruisent pas l'état affiché quand on a déjà une escouade — un
# `not_leader` ou un `full` est un message, pas une dissolution.
func _on_squad_state(ok: bool, data: Dictionary) -> void:
	if not is_inside_tree():
		return
	var reason := str(data.get("reason", ""))
	if not ok:
		_set_status("SQUAD_ERR_NETWORK")
		return

	if bool(data.get("squad", false)):
		_squad = data
		_in_queue = bool(data.get("in_queue", false))
		_queued_since = int(data.get("queued_since_s", 0))
		# 🩸 L'ORDRE COMPTE, ET IL ÉTAIT INVERSÉ. `_render()` remet `_status_label.visible = false`
		# quand l'escouade n'est pas en file — donc poser le message AVANT le rendu revenait à
		# l'EFFACER aussitôt. Un membre qui recevait `not_leader`, une escouade `full`, ou la file
		# fermée pour maintenance ne voyait STRICTEMENT RIEN : le clic passait pour mort.
		# C'est exactement la muette du §8.143 §5.8, sur un chemin que sa cartographie déclarait
		# pourtant « acceptable » — trouvé par la contre-épreuve `tools/test_mm_refusals.gd`.
		# ⛔ Ne jamais remettre `_set_status_for` avant `_render()`.
		_render()
		if reason != "":
			_set_status_for(reason, data)
		return

	# Pas (ou plus) d'escouade. `in_queue` reste possible : c'est le cas du SOLO en file d'équipe.
	if data.has("in_queue"):
		_in_queue = bool(data.get("in_queue", false))
	# ⚠️ RESYNCHRONISATION DU CHRONO sur l'ANCIENNETÉ RÉELLE du ticket (serveur). Sans cette ligne,
	# le solo ne comptait QUE ses propres tics locaux : revenir sur l'écran (ou rouvrir le client)
	# repartait de 00:00 alors que le ticket attendait depuis plusieurs minutes — le compteur
	# affichait donc une durée FAUSSE, et le joueur croyait que sa recherche venait de redémarrer.
	# La branche « escouade » faisait déjà cette resynchronisation ; celle-ci l'avait oubliée.
	if data.has("queued_since_s"):
		_queued_since = int(data.get("queued_since_s", 0))
	if reason in ["", "no_squad"]:
		_squad = {}
		if _in_queue:
			_refresh_queue_status()
		else:
			_status_label.visible = false
		_render()
	else:
		# MÊME INVERSION que ci-dessus, et même correctif : le rendu d'abord, le message ensuite.
		_render()
		_set_status_for(reason, data)


# Affiche le refus. §8.143 → SOLDÉ §8.144 : `closed` porte un champ ADDITIF `cause` qu'aucune
# signature ne transportait jusqu'ici (`_reason_key` ne reçoit que la raison) — d'où ce niveau
# intermédiaire, qui a accès au payload COMPLET.
#
# ⚠️ Une fermeture n'est pas une PANNE : c'est une info de service, en OR et non en rouge. Le reste
# des refus (banni, escouade pleine, pas chef…) garde son rouge.
func _set_status_for(reason: String, data: Dictionary) -> void:
	if reason == "closed":
		match str(data.get("cause", "")):
			"maintenance":
				_set_status("MM_CLOSED_MAINTENANCE", [], GOLD)
			_:
				# `feature_disabled`, ou une cause inconnue d'un serveur plus récent : dans les deux
				# cas la file est fermée, et le dire vaut mieux que de retomber sur « indisponible ».
				_set_status("MM_CLOSED_FEATURE", [], GOLD)
		return
	# FRAIS D'INSCRIPTION (chantier MODÈLE ÉCONOMIQUE) — MÊME raisonnement que la fermeture, et même
	# OR : ce n'est pas une panne, c'est un prix. Le refus nomme le membre BLOQUANT (`who`) parce que
	# dans une escouade de trois, un « solde insuffisant » anonyme laisse trois joueurs se regarder
	# sans savoir qui doit agir. Sans `who` (chemin solo d'un serveur plus ancien), message générique.
	if reason == "insufficient_coins":
		var who := str(data.get("who", "")).strip_edges()
		if who != "":
			_set_status("FEE_INSUFFICIENT_MEMBER", [who.to_upper()], GOLD)
		else:
			_set_status("FEE_INSUFFICIENT", [], GOLD)
		return
	_set_status(_reason_key(reason))


# Traduction du CODE machine renvoyé par le serveur (convention zéro-4xx §8.112) : le client choisit
# le message, le serveur ne renvoie jamais de texte. Code inconnu → message générique plutôt qu'un
# code brut affiché à l'écran.
func _reason_key(reason: String) -> String:
	match reason:
		"unavailable": return "SQUAD_ERR_UNAVAILABLE"
		"banned": return "SQUAD_ERR_BANNED"
		"busy": return "SQUAD_ERR_BUSY"
		"full": return "SQUAD_ERR_TOO_BIG"
		"not_leader": return "SQUAD_ERR_NOT_LEADER"
		"playlist_closed": return "SQUAD_ERR_PLAYLIST_CLOSED"
		"assigned": return "SQUAD_ERR_ASSIGNED"
		# Filet : `_set_status_for` traite normalement ce refus AVANT d'arriver ici (il a besoin de
		# `who`, que cette fonction ne reçoit pas). On le mappe quand même — un chemin sans payload
		# doit dire « solde insuffisant », pas « indisponible », qui se lit comme une panne.
		"insufficient_coins": return "FEE_INSUFFICIENT"
		# §8.144 — repli si `closed` arrivait par un chemin sans payload : mieux vaut « fermé » que
		# « indisponible », qui se lit comme une panne.
		"closed": return "MM_CLOSED_FEATURE"
		# ⚠️ La branche par défaut existait DÉJÀ ici (§8.143 §5.8 la déclarait « acceptable ») — on
		# ne la touche pas, on la garde comme filet.
		_: return "SQUAD_ERR_UNAVAILABLE"


# La file d'équipe emprunte le MÊME ticket que les files solo : `GET /matchmaking/status` reste donc
# l'autorité sur « ma partie est prête ». Dès `ready`, on bascule vers le draft comme n'importe
# quelle recherche — aucun chemin de navigation spécifique au mode équipe.
func _on_mm_status(state: String, since_s: int, room_id: int) -> void:
	if not is_inside_tree():
		return
	_queued_since = since_s
	if state == "ready" and room_id > 0:
		_poll_timer.stop()
		NetworkManager.current_room_id = str(room_id)
		NetworkManager.connect_to_server(str(room_id))
		TransitionManager.change_scene("res://scenes/faction_selection/faction_selection.tscn")
	elif state in ["idle", "in_game"] and _in_queue:
		# Le ticket a disparu (heartbeat perdu par un membre → tout le groupe sort, §4.B.3).
		_in_queue = false
		_render()


func _on_poll() -> void:
	NetworkManager.squad_status()
	if _in_queue:
		# Rafraîchit le TTL du ticket ET détecte le passage à `ready`.
		NetworkManager.mm_queue_status()


func _on_session_expired() -> void:
	if not is_inside_tree():
		return
	AuthManager.session_notice = tr("AUTH_SESSION_EXPIRED")
	AuthManager.clear_session()
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")


# =========================================================
# ACTIONS UI (déjà câblées via WarzoneUI.wire_button_sfx : ne JAMAIS rejouer "click" ici)
# =========================================================
func _on_playlist_selected(playlist_id: String) -> void:
	_selected_playlist = playlist_id
	# Escouade FORMÉE → on PERSISTE le format côté serveur : c'est une donnée de GROUPE, et sans cet
	# appel les coéquipiers continueraient de lire l'ancien (§8.125). Sans escouade, le choix reste
	# local jusqu'à la création — il n'y a encore rien à persister.
	if bool(_squad.get("squad", false)) and bool(_squad.get("is_leader", false)):
		NetworkManager.squad_set_playlist(playlist_id)
	# ⚠️ RENDU DIFFÉRÉ : `_render()` reconstruit la rangée de boutons, donc LIBÈRE celui qui est en
	# train d'émettre `pressed`. Le faire dans la foulée revient à détruire un nœud depuis son
	# propre signal — `call_deferred` attend la fin de la passe d'évènements.
	call_deferred("_render")


func _on_create_pressed() -> void:
	if _selected_playlist == "":
		_set_status("SQUAD_ERR_PLAYLIST_CLOSED")
		return
	NetworkManager.squad_create(_selected_playlist)


# TROUVER UNE PARTIE — file d'équipe en SOLO, sans escouade et sans autre geste. Le matchmaker
# compose l'équipe avec les autres solos en attente (bots à 60 s si le pool est vide).
func _on_find_match_pressed() -> void:
	AudioManager.play_sfx("click")
	if _selected_playlist == "":
		return
	_in_queue = true          # bascule d'affichage IMMÉDIATE : le chrono part au clic, pas au poll.
	_queued_since = 0
	_render()                 # bascule sur le visage RECHERCHE (chrono + ANNULER) sans attendre.
	NetworkManager.squad_queue(_selected_playlist)


# ANNULER une recherche SOLO. Même route que l'annulation d'escouade (`DELETE /squad/queue`) : le
# serveur distingue lui-même le ticket solo du groupe. On repasse au visage d'accueil IMMÉDIATEMENT
# — un bouton d'annulation qui laisse l'écran en « recherche » pendant 2 s (le temps du poll) donne
# l'impression de n'avoir rien fait, et le joueur le reclique.
func _on_solo_cancel_pressed() -> void:
	AudioManager.play_sfx("click")
	_in_queue = false
	_queued_since = 0
	_render()
	NetworkManager.squad_dequeue()


func _on_join_pressed() -> void:
	var code := _join_input.text.strip_edges().to_upper()
	if code == "":
		return
	NetworkManager.squad_join(code)


func _on_join_submitted(_text: String) -> void:
	_on_join_pressed()


func _on_queue_pressed() -> void:
	if _in_queue:
		NetworkManager.squad_dequeue()
	else:
		# §8.129 — première mise en file BATTLE ROYALE : objectif public, réanimation, caisses. Les
		# règles du mode sont déjà annoncées dans l'écran ; la bulle rappelle ce qui SURPREND.
		TutorialManager.hint_once("first_br_queue")
		NetworkManager.squad_queue(_selected_playlist)


func _on_leave_pressed() -> void:
	NetworkManager.squad_leave()


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(str(_squad.get("code", "")))
	_copy_button.text = "SALON_COPIED"
	if _copy_flash_timer == null:
		_copy_flash_timer = Timer.new()
		_copy_flash_timer.one_shot = true
		_copy_flash_timer.timeout.connect(func(): _copy_button.text = "SALON_COPY")
		add_child(_copy_flash_timer)
	_copy_flash_timer.start(COPY_FLASH_DURATION)


func _on_back_pressed() -> void:
	# ⚠️ On NE QUITTE PAS l'escouade en revenant au QG : elle survit à tout, c'est sa promesse.
	# Seul le bouton QUITTER la dissout (ou la fait quitter).
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")


func _on_locale_changed(_code: String) -> void:
	_render()
