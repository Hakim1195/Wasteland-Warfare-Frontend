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
# Onglets (§8.127) : l'écran empilait TOUT (audio + affichage + langue + confort + déconnexion) dans
# un seul VBox, qui débordait de l'écran en 1080p et plus bas. Le contenu est désormais réparti sur
# deux PAGES exclusives — `PageMain` (audio / affichage / langue / déconnexion) et `PageComfort`
# (confort & accessibilité) — pilotées par la barre de boutons `TabsBar`, construite en code.
@export var tabs_bar: HBoxContainer
@export var page_main: VBoxContainer
@export var comfort_page: VBoxContainer
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

# --- Onglets (§8.127) ---
# Data-driven comme la barre du Shop (§8.102) : `key` est une clé i18n BRUTE posée telle quelle sur
# le bouton → Godot la traduit ET la re-traduit tout seul au changement de langue.
const TAB_DEFS := [
	{"id": "general", "key": "SETTINGS_TAB_GENERAL"},
	{"id": "comfort", "key": "SETTINGS_TAB_COMFORT"},
]

# Police condensée de la charte (§2), pour les nœuds générés/restylés en code.
var _font: SystemFont
# Poignée de slider : petit carré cyan plein (ADN angulaire §2), partagée par les 3 sliders.
var _grabber_tex: ImageTexture
# Boutons de résolution générés en code — référencés pour les griser en plein écran (la résolution
# fenêtrée n'a alors aucun effet visible, cf. SettingsManager._apply_display).
var _resolution_buttons: Array[Button] = []
# Nœuds de la section CONFORT construits par code — mémorisés pour pouvoir les RECONSTRUIRE au
# changement de langue (i18n 2026-07-18 : les libellés posés par tr() en code ne se re-traduisent
# pas tout seuls, contrairement aux nœuds .tscn).
var _comfort_nodes: Array[Node] = []
# Onglet affiché (§8.127) — "general" au premier affichage, comme dans la maquette.
var _active_tab := "general"
# id d'onglet -> bouton de la TabsBar, pour restyler la sélection sans re-chercher les nœuds.
var _tab_buttons: Dictionary = {}
# Plancher de hauteur de la zone de pages (px), mesuré à l'exécution — cf. _measure_pages_floor().
var _pages_floor := 0.0

func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700
	_grabber_tex = _make_grabber_texture()

	# Header CANONIQUE partagé (§8.94). Écran HORS ONGLETS (on s'y rend par le ⚙ de la nav, pas par
	# un onglet) → `active_tab = ""` : AUCUN onglet surligné, comportement nominal et assumé.
	# ⚠️ Avant §8.94 la valeur était "options", un id qui n'existe dans AUCUNE entrée de TABS : le
	# résultat était le même (rien de surligné) mais par accident — c'est désormais explicite.
	# L'écran conserve son titre : sans onglet actif, c'est la SEULE chose qui le nomme.
	var nav := TopNav.new()
	nav.active_tab = ""
	add_child(nav)
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Entrée d'écran UNIFORME (§8.96) : fondu + léger glissement, identique sur tous les écrans hub.
	WarzoneUI.animate_screen_enter(self)

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# Bouton DÉCONNEXION (ghost « danger » rouge) tout en bas — action destructrice (charte §2).
	# Migré du lobby : c'est désormais ICI qu'on coupe le tunnel temps réel + purge la session.
	_style_logout_button(logout_button)
	if logout_button:
		logout_button.pressed.connect(_on_logout_pressed)
		WarzoneUI.wire_button_sfx(logout_button)  # SFX d'interface (survol/clic — R6)

	# Audio : 3 sliders branchés sur le SettingsManager (+ AMBIANCE, construit par code ci-dessous).
	_setup_volume_slider(master_slider, master_value, "master")
	_setup_volume_slider(music_slider, music_value, "music")
	_setup_volume_slider(sfx_slider, sfx_value, "sfx")
	# §8.122 (LOT C/G) : 4ᵉ volume — bus `Ambience` (Geiger, vent, radio du QG). Ajouté PAR CODE
	# sous la rangée SFX plutôt que dans le .tscn : même geste que la section CONFORT, et zéro
	# retouche de scène (donc zéro risque sur les NodePath @export existants).
	_build_ambience_slider()

	# Affichage : mode fenêtre (segments) + résolution (segments numériques).
	_setup_window_mode()
	_setup_resolution()

	# Langue : on réutilise tel quel le sélecteur mutualisé (R4), câblé sur LocaleManager.
	_mount_language_selector()

	# Section CONFORT (E10 §8.82) : réglages d'accessibilité construits PAR CODE (aucune retouche
	# .tscn) et appendus à la page CONFORT — pilotés par SettingsManager.get_comfort/set_comfort.
	_build_comfort_section()

	# Barre d'onglets (§8.127) — construite APRÈS les deux pages : `_show_tab()` masque celle qui
	# n'est pas active, et on veut qu'elle soit déjà peuplée quand on la cache.
	_build_tabs()

	_set_status(tr("SETTINGS_STATUS"))

	# i18n (2026-07-18) : le sélecteur de langue vit SUR cet écran → re-traduire à chaud les
	# libellés construits par code (section confort + statut). Les nœuds .tscn se re-traduisent
	# tout seuls ; le désabonnement est implicite (signal coupé à la libération du nœud).
	LocaleManager.locale_changed.connect(_on_locale_changed_rebuild)
	# §8.122 (LOT G) : `reduced_motion` conditionne l'état de la rangée CARTE VIVANTE → relayout.
	SettingsManager.comfort_changed.connect(_on_comfort_changed_relayout)

# --- Onglets (§8.127) -------------------------------------------------------
# Deux pages EXCLUSIVES au lieu d'un empilement unique : l'écran ne tenait plus en hauteur (il
# débordait déjà en 1080p une fois la section CONFORT et le 4ᵉ volume ajoutés par code). Les pages
# sont deux VBox sœurs sous `Pages` dont on bascule `visible` — un enfant masqué ne prend aucune
# place dans un VBoxContainer, donc le panneau se recalcule tout seul.
# ⚠️ La ligne de STATUT et le filet du bas restent HORS des pages (pied de page commun) : ils
# décrivent l'écran entier (« réglages appliqués et enregistrés localement »), pas un onglet.
func _build_tabs() -> void:
	if tabs_bar == null:
		return
	for def in TAB_DEFS:
		var btn := Button.new()
		btn.text = str(def.get("key"))   # clé BRUTE -> auto-traduction (et re-traduction) par Godot
		btn.custom_minimum_size = Vector2(0, 46)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_tab_pressed.bind(str(def.get("id"))))
		tabs_bar.add_child(btn)
		_tab_buttons[str(def.get("id"))] = btn
	WarzoneUI.wire_buttons_sfx(_tab_buttons.values())   # SFX d'interface (survol/clic — R6)
	_show_tab(_active_tab)

func _on_tab_pressed(id: String) -> void:
	if id == _active_tab:
		return
	_show_tab(id)

func _show_tab(id: String) -> void:
	_active_tab = id
	for tab_id in _tab_buttons:
		_style_tab(_tab_buttons[tab_id], tab_id == _active_tab)
	if page_main:
		page_main.visible = (id == "general")
	if comfort_page:
		comfort_page.visible = (id == "comfort")
	_measure_pages_floor()

# Le panneau est centré verticalement (CenterContainer) : sans plancher commun, passer sur la page
# la plus courte le ferait REMONTER de la moitié de l'écart — l'écran « sauterait » de ~58 px à
# chaque clic d'onglet. On impose donc à la zone de pages la hauteur de la plus haute page déjà
# affichée. Le plancher ne fait que CROÎTRE, ce qui absorbe aussi les reconstructions de la page
# CONFORT (changement de langue, ou MOUVEMENT RÉDUIT qui fait apparaître la mention CARTE VIVANTE).
#
# ⚠️ Mesuré sur la taille RÉELLE (après tri des enfants), surtout PAS via
# `get_combined_minimum_size()` : les deux mentions muettes de la page CONFORT sont en autowrap, et
# la taille minimale d'un Label enroulé se calcule sur sa largeur COURANTE — hors layout elle
# explose (mesuré : 2543 px au lieu de 387). D'où l'attente d'une frame avant de lire `size`.
# Rien n'est figé en dur non plus : les métriques dépendent de la police réellement présente sur la
# machine (la chaîne Bahnschrift → … → Arial ne donne pas les mêmes hauteurs partout).
func _measure_pages_floor() -> void:
	await get_tree().process_frame
	if not is_inside_tree() or page_main == null or comfort_page == null:
		return
	var pages := page_main.get_parent() as Control
	if pages == null:
		return
	# Aucune des deux pages n'a de drapeau EXPAND : dans un VBoxContainer elles gardent leur hauteur
	# naturelle et le plancher laisse simplement du vide sous la plus courte — on mesure donc bien
	# le contenu, pas le plancher déjà posé.
	var active: Control = page_main if _active_tab == "general" else comfort_page
	_pages_floor = maxf(_pages_floor, active.size.y)
	pages.custom_minimum_size.y = _pages_floor

# Onglet : actif = fond cyan + soulignement, inactif = ghost. Même style que la barre du Shop (§2),
# volontairement DISTINCT de `_style_segment` (segments de réglage) pour ne pas confondre les deux
# niveaux de sélection présents à l'écran.
func _style_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 10.0
	if active:
		sb.bg_color = Color(ACCENT, 0.20)
		sb.border_width_bottom = 3
		sb.border_color = ACCENT
	else:
		sb.bg_color = Color(1, 1, 1, 0.03)
		sb.border_width_bottom = 1
		sb.border_color = Color(ACCENT, 0.35)

	var hover := sb.duplicate() as StyleBoxFlat
	if not active:
		hover.bg_color = Color(ACCENT, 0.10)

	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)

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

# --- Volume AMBIANCE (§8.122, LOT C/G) : 4ᵉ rangée du bloc AUDIO, construite par code ------------
# Gabarit COPIÉ des rangées .tscn (libellé 230 px, slider extensible, valeur 64 px alignée à droite)
# pour que les quatre lignes s'alignent au pixel près. Ajoutée en QUEUE de `AudioRows` : le volume
# d'ambiance vient après Général / Musique / Effets, comme dans le mixage lui-même.
func _build_ambience_slider() -> void:
	if sfx_slider == null:
		return
	var rows := sfx_slider.get_parent().get_parent()   # SfxRow -> AudioRows
	if rows == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var lbl := Label.new()
	lbl.text = "SETTINGS_AMBIENCE"   # clé BRUTE -> auto-traduction (et re-traduction) par Godot
	lbl.custom_minimum_size = Vector2(230, 0)
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", TEXT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var slider := HSlider.new()
	row.add_child(slider)

	var value := Label.new()
	value.custom_minimum_size = Vector2(64, 0)
	value.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	value.add_theme_font_override("font", _font)
	value.add_theme_font_size_override("font_size", 16)
	value.add_theme_color_override("font_color", ACCENT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)

	rows.add_child(row)
	# Câblage APRÈS insertion dans l'arbre (le helper pose la valeur initiale et branche le signal).
	_setup_volume_slider(slider, value, "ambience")

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
	# Page CONFORT = 2ᵉ onglet (§8.127), câblée en @export EXPLICITE. Avant, la section devinait son
	# parent en remontant l'arbre (`resolution_box.get_parent().get_parent()`), ce qui la collait
	# forcément en queue du RootVBox — donc dans le même empilement que le reste.
	var root: Node = comfort_page
	if root == null:
		return
	var sep := HSeparator.new()
	root.add_child(sep)
	var eyebrow := Label.new()
	eyebrow.text = tr("SETTINGS_COMFORT_EYEBROW")
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	root.add_child(eyebrow)

	# ⚠️ La rangée « AFFICHAGE DES COMBATS » (`combat_display`, E8 §8.80) est SUPPRIMÉE (décision
	# Hakim 2026-07-27) : le rythme RAPIDE est retenu comme le seul comportement, il n'y a donc plus
	# rien à choisir. Les clés i18n `SETTINGS_COMBAT_*` restent au CSV (on ne supprime jamais une
	# clé — elles deviennent simplement orphelines).
	# ui_scale : 4 segments numériques (libellés % neutres — pas de traduction).
	var scale_row := _comfort_segments("SETTINGS_UI_SCALE", "ui_scale",
		[[0.9, "90 %"], [1.0, "100 %"], [1.15, "115 %"], [1.3, "130 %"]])
	root.add_child(scale_row)
	# Bascules booléennes.
	var t1 := _comfort_toggle("SETTINGS_REDUCED_MOTION", "reduced_motion")
	var t2 := _comfort_toggle("SETTINGS_COLORBLIND", "colorblind_mode")
	var t3 := _comfort_toggle("SETTINGS_DAMAGE_NUMBERS", "damage_numbers")
	root.add_child(t1)
	root.add_child(t2)
	root.add_child(t3)
	# MODE STREAMER (§8.121, LOT E) — le seul réglage de cette section dont l'effet n'est pas
	# évident au libellé : il gagne une ligne d'explication muette juste dessous (« masque votre
	# objectif secret »), sans quoi un joueur ne saurait pas ce qu'il coupe.
	var t4 := _comfort_toggle("STREAMER_MODE_LABEL", "streamer_mode")
	root.add_child(t4)
	var hint := Label.new()
	hint.text = tr("STREAMER_MODE_HINT")
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)
	# CARTE VIVANTE (§8.122, LOT D/G) — cendres, fumées, feux de camp, éclairs, oiseaux du plateau.
	# ⚠️ GRISÉE et forcée à OFF tant que `reduced_motion` est actif : cette option n'est QUE du
	# mouvement, il n'y aurait rien à en garder. On grise plutôt que de masquer, avec la raison
	# écrite juste dessous — un réglage qui DISPARAÎT laisse croire à un bug.
	var t5 := _comfort_toggle("SETTINGS_LIVING_MAP", "living_map")
	root.add_child(t5)
	var map_hint := Label.new()
	map_hint.text = tr("SETTINGS_LIVING_MAP_HINT")
	map_hint.add_theme_font_override("font", _font)
	map_hint.add_theme_font_size_override("font_size", 12)
	map_hint.add_theme_color_override("font_color", MUTED)
	map_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(map_hint)
	if bool(SettingsManager.get_comfort("reduced_motion")):
		t5.modulate = Color(1, 1, 1, 0.35)
		for child in t5.get_children():
			if child is Button:
				child.disabled = true
	else:
		map_hint.visible = false   # la mention n'a de sens que quand l'option est neutralisée
	# Mémorisés pour la reconstruction au changement de langue (_on_locale_changed_rebuild).
	_comfort_nodes = [sep, eyebrow, scale_row, t1, t2, t3, t4, hint, t5, map_hint]

# Changement de langue À CHAUD : purge et reconstruit la section confort (seul bloc de cet écran
# dont les libellés sont posés par code), puis re-traduit la ligne de statut.
func _on_locale_changed_rebuild(_code: String) -> void:
	_rebuild_comfort_section()
	_set_status(tr("SETTINGS_STATUS"))

func _rebuild_comfort_section() -> void:
	for n in _comfort_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_comfort_nodes.clear()
	_build_comfort_section()

# §8.122 (LOT G) : basculer `reduced_motion` change l'ÉTAT d'une AUTRE rangée (CARTE VIVANTE grisée
# ou non, mention affichée ou non). Sans cette reconstruction, le joueur devrait quitter puis
# rouvrir l'écran pour voir la conséquence de son propre clic. Différée : on ne libère pas les
# nœuds pendant que le callback du bouton qui a déclenché le changement s'exécute encore.
func _on_comfort_changed_relayout(key: String, _value) -> void:
	if key == "reduced_motion":
		_rebuild_comfort_section.call_deferred()

# Rangée « libellé + segments » : un bouton par valeur, le courant actif. `values` =
# Array[[valeur, libellé]]. La valeur peut être String ou float (seul `ui_scale` s'en sert depuis
# la suppression de `combat_display` — le helper reste générique pour un futur réglage segmenté).
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
# l'identité (mémoire ET disque, §P1) via AuthManager.clear_session(), puis renvoie le joueur vers
# l'écran d'authentification — toujours via le fondu gunmetal du TransitionManager.
func _on_logout_pressed() -> void:
	# 1. Coupure du WebSocket (défensif : hors d'une partie aucun tunnel n'est ouvert). leave_room()
	#    (revue §8.116) ferme ET recrée le peer (fix STATE_CLOSING) + purge current_room_id — plus
	#    aucune Vue ne manipule NetworkManager.socket directement (Règle d'Or §6.1).
	NetworkManager.leave_room()
	# 2. Purge complète de la session (sinon la reconnexion auto §P1 relogguerait le joueur au
	#    prochain lancement malgré sa déconnexion volontaire).
	AuthManager.clear_session()
	# 3. Redirection vers l'écran d'authentification (fondu gunmetal entrant/sortant).
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")
