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
var _queued_since: int = 0


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
	panel.custom_minimum_size = Vector2(680, 620)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(GUNMETAL, 0.92)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(2)
	pstyle.border_color = Color(ACCENT, 0.7)
	pstyle.set_content_margin_all(36.0)
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 12)
	panel.add_child(_root)

	# Rythme eyebrow → valeur (§2) : « MODE » puis le nom du mode en grand, OR.
	var eyebrow := Label.new()
	eyebrow.text = "MENU_MODE_EYEBROW_TEAM"  # clé brute -> auto-traduction
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", MUTED)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(eyebrow)

	var title := Label.new()
	title.text = "MODE_BATTLE_ROYALE"  # clé brute -> auto-traduction
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	# RÈGLES DU MODE, annoncées AVANT de s'engager. Le joueur doit savoir dans quoi il entre : la
	# partie dure 30 min, l'objectif est public, et — en 3v3 — quelqu'un à sa table a peut-être
	# reçu l'ordre de l'abattre. Le découvrir en jeu serait une trahison du joueur, pas du camp.
	var rules := _muted_label("BR_RULES_HINT", 12)
	_root.add_child(rules)

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
	_no_squad_box.add_theme_constant_override("separation", 12)
	_root.add_child(_no_squad_box)

	var hint := _muted_label("SQUAD_CODE_HINT", 13)
	_no_squad_box.add_child(hint)

	# Sélecteur de playlist — peuplé DEPUIS LE REGISTRE serveur (aucune carte en dur).
	_create_playlist_row = HBoxContainer.new()
	_create_playlist_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_create_playlist_row.add_theme_constant_override("separation", 10)
	_no_squad_box.add_child(_create_playlist_row)

	var create_btn := Button.new()
	_style_cta(create_btn)
	create_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	create_btn.text = "❯ " + tr("SQUAD_CREATE")
	create_btn.custom_minimum_size = Vector2(260, 52)
	create_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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


# --- Visage n° 2 : escouade FORMÉE (code, membres, file) ---
func _build_squad_box() -> void:
	_squad_box = VBoxContainer.new()
	_squad_box.add_theme_constant_override("separation", 10)
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
	_members_box.add_theme_constant_override("separation", 6)
	_squad_box.add_child(_members_box)

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


func _render() -> void:
	var has_squad := bool(_squad.get("squad", false))
	_no_squad_box.visible = not has_squad
	_squad_box.visible = has_squad

	if not has_squad:
		_selected_playlist = _selected_playlist if _selected_playlist != "" else \
			(str(_playlist_ids()[0]) if not _playlist_ids().is_empty() else "")
		_rebuild_playlist_buttons(_create_playlist_row, true)
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
		if reason != "":
			_set_status(_reason_key(reason))
		_render()
		return

	# Pas (ou plus) d'escouade. `in_queue` reste possible : c'est le cas du SOLO en file d'équipe.
	if data.has("in_queue"):
		_in_queue = bool(data.get("in_queue", false))
	if reason in ["", "no_squad"]:
		_squad = {}
		if _in_queue:
			_refresh_queue_status()
		else:
			_status_label.visible = false
	else:
		_set_status(_reason_key(reason))
	_render()


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
