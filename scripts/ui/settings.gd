extends Control

# =========================================================================
# Écran Options / Paramètres (Feuille de route R5) — charte « Warzone Command » §2
# =========================================================================
# Écran NEUF accessible depuis main_menu (« ❯ PARAMÈTRES »).
# Règle d'Or §6.1 : VUE pure. Toute la logique (lecture/écriture des réglages,
# application au moteur, persistance disque) vit dans les autoloads SettingsManager
# (audio/affichage) et LocaleManager (langue, via le sélecteur mutualisé). Cet écran
# ne fait que LIRE l'état initial des contrôles et ÉMETTRE les changements.
#
# Les libellés statiques (eyebrows, intitulés de ligne, modes d'affichage) vivent dans
# la scène .tscn en clés de traduction → re-traduits automatiquement par Godot au
# changement de langue (R4). Le code ne construit/gère que les contrôles interactifs
# (styles des sliders, segments, valeurs %, sélecteur de résolution numérique).

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var master_slider: HSlider
@export var master_value: Label
@export var music_slider: HSlider
@export var music_value: Label
@export var sfx_slider: HSlider
@export var sfx_value: Label
@export var fullscreen_button: Button
@export var windowed_button: Button
@export var resolution_box: HBoxContainer
@export var language_box: Control
@export var status_label: Label
# Bouton DÉCONNEXION (action destructrice) tout en bas de l'écran — charte « Warzone Command » §2
# (texte rouge danger #D6453F). La logique de déconnexion a MIGRÉ ici depuis le lobby (refonte navigation).
@export var logout_button: Button

# Helpers UI partagés de la charte « Warzone Command » (§2) — encoches + sélecteur de langue.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Barre de navigation supérieure partagée (hub Warzone) — montée en tête d'écran (onglet OPTIONS).
const TopNav = preload("res://scripts/ui/top_nav.gd")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (muet / inactif)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)  # rouge danger #D6453F (action destructrice)

# Police condensée de la charte (§2), pour les nœuds générés/restylés en code.
var _font: SystemFont
# Poignée de slider : petit carré cyan plein (ADN angulaire §2), partagée par les 3 sliders.
var _grabber_tex: ImageTexture
# Boutons de résolution générés en code — référencés pour les griser en plein écran (la résolution
# fenêtrée n'a alors aucun effet visible, cf. SettingsManager._apply_display).
var _resolution_buttons: Array[Button] = []

func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700
	_grabber_tex = _make_grabber_texture()

	# Header CANONIQUE partagé (§8.93). Écran HORS ONGLETS (on s'y rend par le ⚙ de la nav, pas par
	# un onglet) → `active_tab = ""` : AUCUN onglet surligné, comportement nominal et assumé.
	# ⚠️ Avant §8.93 la valeur était "options", un id qui n'existe dans AUCUNE entrée de TABS : le
	# résultat était le même (rien de surligné) mais par accident — c'est désormais explicite.
	# L'écran conserve son titre : sans onglet actif, c'est la SEULE chose qui le nomme.
	var nav := TopNav.new()
	nav.active_tab = ""
	add_child(nav)
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# Bouton DÉCONNEXION (ghost « danger » rouge) tout en bas — action destructrice (charte §2).
	# Migré du lobby : c'est désormais ICI qu'on coupe le tunnel temps réel + purge la session.
	_style_logout_button(logout_button)
	if logout_button:
		logout_button.pressed.connect(_on_logout_pressed)
		WarzoneUI.wire_button_sfx(logout_button)  # SFX d'interface (survol/clic — R6)

	# Audio : 3 sliders branchés sur le SettingsManager.
	_setup_volume_slider(master_slider, master_value, "master")
	_setup_volume_slider(music_slider, music_value, "music")
	_setup_volume_slider(sfx_slider, sfx_value, "sfx")

	# Affichage : mode fenêtre (segments) + résolution (segments numériques).
	_setup_window_mode()
	_setup_resolution()

	# Langue : on réutilise tel quel le sélecteur mutualisé (R4), câblé sur LocaleManager.
	_mount_language_selector()

	# Section CONFORT (E10 §8.82) : réglages d'accessibilité construits PAR CODE (aucune retouche
	# .tscn) et appendus au RootVBox — pilotés par SettingsManager.get_comfort/set_comfort.
	_build_comfort_section()

	_set_status(tr("SETTINGS_STATUS"))

# --- Audio : sliders de volume ---------------------------------------------
func _setup_volume_slider(slider: HSlider, value_label: Label, bus: String) -> void:
	if slider == null:
		return
	_style_slider(slider)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	# Valeur initiale AVANT branchement du signal (évite un set parasite à l'init).
	slider.value = SettingsManager.get_volume(bus)
	_update_value_label(value_label, slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		SettingsManager.set_volume(bus, v)
		_update_value_label(value_label, v))

func _update_value_label(label: Label, v: float) -> void:
	if label:
		label.text = "%d %%" % int(round(v * 100.0))

# --- Affichage : mode fenêtre (segments PLEIN ÉCRAN / FENÊTRÉ) --------------
func _setup_window_mode() -> void:
	for btn in [fullscreen_button, windowed_button]:
		if btn:
			btn.focus_mode = Control.FOCUS_NONE
			btn.add_theme_font_override("font", _font)
			btn.add_theme_font_size_override("font_size", 16)
	if fullscreen_button:
		fullscreen_button.pressed.connect(func() -> void:
			SettingsManager.set_fullscreen(true)
			_refresh_window_mode()
			_refresh_resolution_enabled())
	if windowed_button:
		windowed_button.pressed.connect(func() -> void:
			SettingsManager.set_fullscreen(false)
			_refresh_window_mode()
			_refresh_resolution_enabled())
	_refresh_window_mode()

func _refresh_window_mode() -> void:
	var fs := SettingsManager.is_fullscreen()
	_style_segment(fullscreen_button, fs)
	_style_segment(windowed_button, not fs)

# En plein écran, la résolution FENÊTRÉE n'a aucun effet visible (elle ne s'applique qu'en fenêtré) :
# on grise la ligne et on bloque le clic pour ne pas laisser croire qu'un réglage inopérant a pris.
func _refresh_resolution_enabled() -> void:
	var fs := SettingsManager.is_fullscreen()
	if resolution_box:
		resolution_box.modulate = Color(1, 1, 1, 0.35) if fs else Color(1, 1, 1, 1)
	for b in _resolution_buttons:
		b.disabled = fs

# --- Affichage : résolution (segments numériques, construits en code) -------
func _setup_resolution() -> void:
	if resolution_box == null:
		return
	resolution_box.add_theme_constant_override("separation", 8)
	var labels := SettingsManager.resolution_labels()
	var active := SettingsManager.get_resolution_index()
	var buttons: Array[Button] = []
	for i in labels.size():
		var btn := Button.new()
		btn.text = labels[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size = Vector2(132, 38)
		var this_i := i
		btn.pressed.connect(func() -> void:
			SettingsManager.set_resolution_index(this_i)
			for j in buttons.size():
				_style_segment(buttons[j], j == this_i))
		resolution_box.add_child(btn)
		buttons.append(btn)
	for i in buttons.size():
		_style_segment(buttons[i], i == active)
	_resolution_buttons = buttons
	# Cohérence initiale : si on démarre en plein écran, la ligne résolution est grisée d'emblée.
	_refresh_resolution_enabled()

# --- Langue : sélecteur mutualisé (R4) -------------------------------------
func _mount_language_selector() -> void:
	if language_box:
		language_box.add_child(WarzoneUI.build_language_selector())

# --- Styles (charte §2, cohérent avec leaderboard / shop / profile) --------
# Poignée de slider : carré cyan plein, sans arrondi (ADN angulaire §2).
func _make_grabber_texture() -> ImageTexture:
	var img := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	img.fill(ACCENT)
	return ImageTexture.create_from_image(img)

func _style_slider(s: HSlider) -> void:
	s.custom_minimum_size = Vector2(360, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE

	# Piste (fond) : fin liseré cyan sur gunmetal.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.06)
	track.set_corner_radius_all(0)
	track.set_border_width_all(1)
	track.border_color = Color(ACCENT, 0.4)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	s.add_theme_stylebox_override("slider", track)

	# Portion remplie (gauche de la poignée) : cyan translucide → cyan plein au survol.
	var area := StyleBoxFlat.new()
	area.bg_color = Color(ACCENT, 0.55)
	area.set_corner_radius_all(0)
	s.add_theme_stylebox_override("grabber_area", area)

	var area_hi := area.duplicate() as StyleBoxFlat
	area_hi.bg_color = ACCENT
	s.add_theme_stylebox_override("grabber_area_highlight", area_hi)

	s.add_theme_icon_override("grabber", _grabber_tex)
	s.add_theme_icon_override("grabber_highlight", _grabber_tex)

# Segment d'un contrôle « segmenté » : actif = rempli cyan + texte blanc, inactif = ghost acier.
func _style_segment(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12.0
	sb.content_margin_top = 7.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 7.0
	if active:
		sb.bg_color = Color(ACCENT, 0.22)
		sb.set_border_width_all(2)
		sb.border_color = ACCENT
	else:
		sb.bg_color = Color(1, 1, 1, 0.03)
		sb.set_border_width_all(1)
		sb.border_color = Color(ACCENT, 0.45)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.32 if active else 0.14)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_stylebox_override("disabled", sb)  # garde l'allure segment quand grisé (résolution en plein écran)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_disabled_color", TEXT if active else MUTED)

# Style « ghost danger » (liseré + texte ROUGE #D6453F) — bouton DÉCONNEXION (action destructrice §2).
# Même ADN angulaire que le ghost cyan, mais en rouge danger pour signaler la nature destructrice.
func _style_logout_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.025)
	normal.set_border_width_all(1)
	normal.border_color = Color(DANGER, 0.45)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 14.0
	normal.content_margin_top = 10.0
	normal.content_margin_right = 14.0
	normal.content_margin_bottom = 10.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(DANGER, 0.18)
	hover.border_color = DANGER

	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", DANGER)       # texte rouge #D6453F (action destructrice)
	btn.add_theme_color_override("font_hover_color", TEXT)   # blanc froid au survol (sur fond rouge)
	btn.add_theme_color_override("font_pressed_color", TEXT)
	btn.add_theme_color_override("font_focus_color", DANGER)

# =========================================================
# Section CONFORT (E10 §8.82) — accessibilité, construite par code
# =========================================================
func _build_comfort_section() -> void:
	# RootVBox = ancêtre commun des rows (via un nœud @export fiable).
	var root := resolution_box.get_parent().get_parent()
	root.add_child(HSeparator.new())
	var eyebrow := Label.new()
	eyebrow.text = tr("SETTINGS_COMFORT_EYEBROW")
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	root.add_child(eyebrow)

	# combat_display : 3 segments (E8).
	root.add_child(_comfort_segments("SETTINGS_COMBAT_DISPLAY", "combat_display",
		[["cinematique", "CINÉMATIQUE"], ["rapide", "RAPIDE"], ["bandeau", "BANDEAU"]]))
	# ui_scale : 4 segments numériques.
	root.add_child(_comfort_segments("SETTINGS_UI_SCALE", "ui_scale",
		[[0.9, "90 %"], [1.0, "100 %"], [1.15, "115 %"], [1.3, "130 %"]]))
	# Bascules booléennes.
	root.add_child(_comfort_toggle("SETTINGS_REDUCED_MOTION", "reduced_motion"))
	root.add_child(_comfort_toggle("SETTINGS_COLORBLIND", "colorblind_mode"))
	root.add_child(_comfort_toggle("SETTINGS_DAMAGE_NUMBERS", "damage_numbers"))

# Rangée « libellé + segments » : un bouton par valeur, le courant actif. `values` =
# Array[[valeur, libellé]]. La valeur peut être String (combat_display) ou float (ui_scale).
func _comfort_segments(label_key: String, comfort_key: String, values: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_comfort_label(label_key))
	var seg_wrap := HBoxContainer.new()
	seg_wrap.add_theme_constant_override("separation", 4)
	var current = SettingsManager.get_comfort(comfort_key)
	var buttons: Array[Button] = []
	for v in values:
		var btn := Button.new()
		btn.text = str(v[1])
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_segment(btn, _same_value(current, v[0]))
		var val = v[0]
		btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("click")
			SettingsManager.set_comfort(comfort_key, val)
			for i in range(values.size()):
				_style_segment(buttons[i], _same_value(values[i][0], val)))
		buttons.append(btn)
		seg_wrap.add_child(btn)
	row.add_child(seg_wrap)
	return row

# Rangée « libellé + ON/OFF » pour un réglage booléen.
func _comfort_toggle(label_key: String, comfort_key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_comfort_label(label_key))
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(90, 0)
	var on: bool = bool(SettingsManager.get_comfort(comfort_key))
	btn.text = tr("SETTINGS_ON") if on else tr("SETTINGS_OFF")
	_style_segment(btn, on)
	btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("click")
		var new_on: bool = not bool(SettingsManager.get_comfort(comfort_key))
		SettingsManager.set_comfort(comfort_key, new_on)
		btn.text = tr("SETTINGS_ON") if new_on else tr("SETTINGS_OFF")
		_style_segment(btn, new_on))
	row.add_child(btn)
	return row

func _comfort_label(key: String) -> Label:
	var lbl := Label.new()
	lbl.text = tr(key)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", TEXT)
	lbl.custom_minimum_size = Vector2(240, 0)
	return lbl

# Égalité de valeur robuste String/float (les segments mixent les deux types).
func _same_value(a, b) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return absf(float(a) - float(b)) < 0.001
	return str(a) == str(b)

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

# DÉCONNEXION (migrée du lobby) : coupe le tunnel temps réel s'il est ouvert, purge le token JWT +
# l'identité (mémoire ET disque, §P1) via AuthManager.clear_session(), puis renvoie l'opérateur vers
# l'écran d'authentification — toujours via le fondu gunmetal du TransitionManager.
func _on_logout_pressed() -> void:
	# 1. Coupure du WebSocket (défensif : hors d'une partie aucun tunnel n'est ouvert, l'écran
	#    Paramètres n'étant accessible que depuis le menu principal).
	if NetworkManager.socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		NetworkManager.socket.close()
	NetworkManager.connected = false
	NetworkManager.current_room_id = ""
	# 2. Purge complète de la session (sinon la reconnexion auto §P1 relogguerait l'opérateur au
	#    prochain lancement malgré sa déconnexion volontaire).
	AuthManager.clear_session()
	# 3. Redirection vers l'écran d'authentification (fondu gunmetal entrant/sortant).
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")
