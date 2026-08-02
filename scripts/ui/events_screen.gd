extends Control

# =========================================================================
# ÉCRAN ÉVÉNEMENTS (§8.132) — charte « Warzone Command » §2
# =========================================================================
# La destination CANONIQUE des « opérations spéciales » : ce qui tourne ce week-end, ce qui arrive,
# et à quelles parties ça s'applique.
#
# ⚠️ CET ÉCRAN REMPLACE UN PLACEHOLDER. `scenes/ui/events.tscn` existait depuis les premiers
# chantiers avec `section_placeholder.gd` (« SECTION EN CONSTRUCTION »). On a REPRIS la scène plutôt
# que d'en créer une seconde : l'onglet de navigation, l'uid de la scène et les chemins existants
# restent valides, et il n'y a jamais deux écrans « Événements » dans le dépôt.
#
# ⚠️⚠️ AUCUNE VALEUR D'ÉVÉNEMENT EN DUR. Nom, description, dates ET effets viennent tous du serveur
# (`NetworkManager.events_config`, alimenté par `GET /squad/playlists`). Le client ne sait même pas
# combien d'événements existent. C'est ce qui permet d'ouvrir un événement en éditant un registre
# backend, sans redéployer un client.
#
# Règle d'Or §6.1 : VUE pure — aucune règle de jeu ici, uniquement du rendu.

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const TopNav = preload("res://scripts/ui/top_nav.gd")
const EventRulesModal = preload("res://scripts/ui/event_rules_modal.gd")

# --- Palette canonique (§2, miroir company_screen.gd) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)

const BAR_H := TopNav.NAV_H

var _font: Font
var _content: VBoxContainer = null
# Compte à rebours : UN seul Timer d'1 s pour tout l'écran (la carte principale est la seule à en
# porter un). Il ne redemande RIEN au serveur — il recalcule un écart contre l'epoch déjà reçu.
var _tick: Timer = null
var _countdown_label: Label = null
var _countdown_epoch: int = 0
var _countdown_key: String = ""


func _ready() -> void:
	_font = _make_font()
	WarzoneUI.animate_screen_enter(self)

	# ⚠️ LA COQUILLE D'ABORD, LA NAV ENSUITE (leçon §8.126) : les Control se dessinent dans l'ORDRE
	# DE L'ARBRE. Le fond plein écran de cet écran vit dans le `.tscn`, mais le panneau central est
	# ajouté par ce script — une nav montée AVANT lui passerait derrière. On garde donc l'ordre sûr :
	# contenu, puis nav.
	_build_shell()

	var nav := TopNav.new()
	nav.active_tab = "events"
	add_child(nav)
	AudioManager.start_menu_ambient()

	NetworkManager.events_loaded.connect(_on_events)
	LocaleManager.locale_changed.connect(func(_code: String) -> void: _render())

	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.timeout.connect(_update_countdown)
	add_child(_tick)
	_tick.start()

	# La nav lance déjà `fetch_events()` de son côté ; on peint immédiatement le cache s'il existe
	# (navigation depuis un autre écran hub) pour ne pas afficher un écran vide une demi-seconde.
	_render()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


func _build_shell() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = BAR_H
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 620)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(GUNMETAL, 0.92)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = Color(ACCENT, 0.7)
	st.set_content_margin_all(32.0)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	panel.add_child(_content)


func _on_events(_data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement de scène.
	_render()


# =========================================================
# RENDU
# =========================================================
func _render() -> void:
	if _content == null or not is_instance_valid(_content):
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_countdown_label = null
	_countdown_epoch = 0

	_content.add_child(_label(_t("NAV_EVENTS"), 13, ACCENT))
	_content.add_child(_label(_t("EVENT_SCREEN_TITLE"), 34, TEXT))
	WarzoneUI.add_filet(_content)

	var cfg: Dictionary = NetworkManager.events_config
	var active: Dictionary = _dict(cfg.get("active_event", {}))
	var upcoming: Array = cfg.get("upcoming_events", []) if typeof(cfg.get("upcoming_events")) == TYPE_ARRAY else []
	var nxt: Dictionary = _dict(cfg.get("next_event", {}))

	# --- Carte PRINCIPALE : l'ACTIF, à défaut le PROCHAIN, à défaut l'état vide ---
	if not active.is_empty():
		_content.add_child(_headline_card(active, true))
	elif not nxt.is_empty():
		_content.add_child(_headline_card(nxt, false))
	else:
		_content.add_child(_empty_state())

	# --- CALENDRIER : les 3 prochaines opérations, en heure LOCALE du joueur ---
	# On retire l'événement DÉJÀ mis en avant par la carte principale : le répéter juste en dessous
	# ferait croire à deux opérations distinctes.
	var headline_id := str(active.get("id", "")) if not active.is_empty() else str(nxt.get("id", ""))
	var rows: Array = []
	for e in upcoming:
		var entry := _dict(e)
		if entry.is_empty() or str(entry.get("id", "")) == headline_id:
			continue
		rows.append(entry)
	if not rows.is_empty():
		_content.add_child(_spacer(6))
		_content.add_child(_label(_t("EVENT_CALENDAR_TITLE"), 13, ACCENT))
		for entry in rows:
			_content.add_child(_calendar_row(entry))

	# --- NOTE DE PÉRIMÈTRE : permanente, même quand rien n'est programmé ---
	_content.add_child(_spacer(8))
	WarzoneUI.add_filet(_content)
	var scope := _label(_t("EVENT_SCOPE_NOTE"), 13, MUTED)
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(scope)

	_update_countdown()


# Carte principale, cliquable → modal de règles. Liseré OR si l'opération est en cours, CYAN si
# elle est à venir : la couleur seule dit « ça se joue maintenant » ou « prépare-toi ».
func _headline_card(event: Dictionary, is_active: bool) -> Control:
	var accent: Color = GOLD if is_active else ACCENT
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(0, 200)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SURFACE, 0.85)
	st.set_corner_radius_all(0)
	# Liseré fin sur trois côtés, ÉPAIS à gauche : la barre verticale de couleur est la signature
	# des cartes de la charte (§2). ⚠️ `set_border_width_all` D'ABORD — l'appeler après écraserait
	# la largeur gauche.
	st.set_border_width_all(1)
	st.border_width_left = 4
	st.border_color = accent
	st.set_content_margin_all(22.0)
	var hover := st.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.10)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", st)
	WarzoneUI.wire_button_sfx(btn)
	btn.pressed.connect(func() -> void:
		EventRulesModal.open(self, event, is_active, _font))

	# Le contenu est posé PAR-DESSUS le bouton (un Button ne prend pas d'enfants de mise en page) :
	# un VBox en plein cadre, transparent aux clics, pour que tout le pavé reste cliquable.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 22.0
	box.offset_top = 18.0
	box.offset_right = -22.0
	box.offset_bottom = -18.0
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	box.add_child(_label(_t("EVENT_CARD_ACTIVE" if is_active else "EVENT_CARD_UPCOMING"),
		13, accent))
	box.add_child(_label(_t(str(event.get("name_key", ""))).to_upper(), 30, TEXT))
	var desc := _label(_t(str(event.get("desc_key", ""))), 16, MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	box.add_child(_spacer(2))

	# Compte à rebours : vers la FIN si l'opération est en cours, vers le DÉBUT sinon.
	_countdown_epoch = int(event.get("ends_at_epoch", 0)) if is_active \
		else int(event.get("starts_at_epoch", 0))
	_countdown_key = "EVENT_ENDS_IN" if is_active else "EVENT_STARTS_IN"
	_countdown_label = _label("", 18, accent)
	box.add_child(_countdown_label)
	box.add_child(_label(_t("EVENT_OPEN_RULES"), 13, MUTED))
	return btn


# Ligne de calendrier : nom + fenêtre datée en heure LOCALE du joueur (conversion depuis l'epoch
# UTC — on n'affiche JAMAIS une heure serveur brute, elle serait fausse pour la moitié du monde).
func _calendar_row(event: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var chevron := _label("❯", 14, ACCENT)
	chevron.custom_minimum_size = Vector2(18, 0)
	row.add_child(chevron)
	var name_lbl := _label(_t(str(event.get("name_key", ""))).to_upper(), 16, TEXT)
	name_lbl.custom_minimum_size = Vector2(280, 0)
	row.add_child(name_lbl)
	var when := _label(_window_label(int(event.get("starts_at_epoch", 0)),
		int(event.get("ends_at_epoch", 0))), 15, MUTED)
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(when)
	return row


func _empty_state() -> Control:
	var pan := PanelContainer.new()
	pan.custom_minimum_size = Vector2(0, 180)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SURFACE, 0.6)
	st.set_corner_radius_all(0)
	st.set_border_width_all(1)
	st.border_color = Color(MUTED, 0.5)
	st.set_content_margin_all(24.0)
	pan.add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	pan.add_child(box)
	var l := _label(_t("EVENT_NONE_PLANNED"), 20, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	return pan


# =========================================================
# COMPTE À REBOURS & DATES
# =========================================================
# ⚠️ Le rebours se calcule contre l'HORLOGE LOCALE, sans aller-retour serveur : la dérive possible
# se compte en secondes sur une fenêtre de 54 h — invisible. Les timers de PARTIE, eux, utilisent
# l'offset serveur (§8.75) parce qu'une seconde y compte vraiment.
func _update_countdown() -> void:
	if _countdown_label == null or not is_instance_valid(_countdown_label):
		return
	if _countdown_epoch <= 0:
		_countdown_label.text = ""
		return
	var remaining := _countdown_epoch - int(Time.get_unix_time_from_system())
	if remaining <= 0:
		# La fenêtre vient de basculer : on redemande la configuration plutôt que d'afficher un
		# rebours négatif. Le serveur mémoïse 60 s → aucun risque de marteler l'API.
		_countdown_label.text = _t("COMMON_SYNCING")
		_countdown_epoch = 0
		NetworkManager.fetch_events()
		return
	_countdown_label.text = _t(_countdown_key) % _duration_label(remaining)


# « 2 J 06 H » / « 06 H 12 M » / « 12 M 30 S » — deux unités, jamais plus : au-delà, le joueur ne
# lit plus, il déchiffre.
func _duration_label(seconds: int) -> String:
	var d := seconds / 86400
	var h := (seconds % 86400) / 3600
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	if d > 0:
		return _t("EVENT_DUR_DH") % [d, h]
	if h > 0:
		return _t("EVENT_DUR_HM") % [h, m]
	return _t("EVENT_DUR_MS") % [m, s]


# Fenêtre datée en heure LOCALE (`Time.get_datetime_dict_from_unix_time` + décalage système).
func _window_label(start_epoch: int, end_epoch: int) -> String:
	if start_epoch <= 0:
		return ""
	var a := Time.get_datetime_dict_from_unix_time(start_epoch + _local_offset())
	var b := Time.get_datetime_dict_from_unix_time(end_epoch + _local_offset()) if end_epoch > 0 else a
	return _t("EVENT_WINDOW_FMT") % [int(a["day"]), int(a["month"]), int(a["hour"]),
		int(b["day"]), int(b["month"]), int(b["hour"])]


func _local_offset() -> int:
	# `Time.get_time_zone_from_system()["bias"]` est en MINUTES (signé).
	var tz := Time.get_time_zone_from_system()
	return int(tz.get("bias", 0)) * 60


# =========================================================
# FABRIQUES
# =========================================================
func _t(key: String) -> String:
	return String(TranslationServer.translate(key))


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _label(text: String, font_size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	# Textes DÉJÀ traduits : l'auto-traduction les re-chercherait comme des clés (piège maison).
	l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
