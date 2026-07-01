extends Control

# =========================================================
# BARRE DE NAVIGATION SUPÉRIEURE — « Warzone Command » (§2)
# =========================================================
# Hub de navigation façon lobby Call of Duty: Warzone. Composant RÉUTILISABLE construit 100 % par
# code (même pattern que xp_coins_bar / warzone_ui) : il suffit de l'`add_child()` en haut d'un écran
# de premier niveau, après avoir réglé `active_tab` (AVANT l'ajout à l'arbre).
#
# ⚠️ TRAITEMENT IDENTIQUE À LA TOP-BAR DU MENU PRINCIPAL (main_menu.tscn) : barre TRANSPARENTE,
# marque (gauche) ▸ onglets centrés QG/Boutique/Profil/Classement dans une PASTILLE opaque ▸ cluster
# droite = CADRE IDENTITÉ (pseudo + jauge XP/Coins) + ⚙ Paramètres + ⏻ Quitter ▸ filet cyan sous la
# barre. View PURE (Règle d'Or §6.1) : navigation via TransitionManager, données via AuthManager.
# NOTE : le choix de la LANGUE ne vit plus dans la nav — il est centralisé dans l'écran Paramètres.
#
# Les écrans hôtes (boutique, réglages…) CENTRENT leur contenu (CenterContainer) → la bande du haut
# reste libre, la barre ne chevauche jamais le contenu.
#
# i18n (R4) : les libellés d'onglet sont des CLÉS de traduction posées en `text` → Godot les
# auto-traduit et les re-traduit seul au changement de langue (auto_translate AUTO par défaut).

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const XpCoinsBarScript = preload("res://scripts/ui/xp_coins_bar.gd")
const LOGO_TEX = preload("res://assets/images/logo_mark.svg")  # marque hex-nœuds (§8.57)

# Hauteur de la bande de navigation (marges + barre + filet) — calquée sur la top-bar du menu.
const NAV_H := 100.0
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.95)  # fond pastille onglets (opaque)
const SURFACE := Color(0.058824, 0.07451, 0.094118, 0.85)   # fond cadre identité (= card_panel du menu)

# Onglets de la barre — IDENTIQUES au menu principal (lobby/boutique/profil/classement).
# NOTE : les sections Armes / Battle Pass / Événements / Missions / Skins ne sont PAS dans la nav
# (placeholders débranchés). Leurs scènes restent sur disque ; pour réactiver, ajouter leur entrée ici.
const TABS := [
	{"id": "lobby", "key": "MENU_TAB_LOBBY", "scene": "res://scenes/ui/main_menu.tscn"},
	{"id": "characters", "key": "MENU_TAB_CHARACTERS", "scene": "res://scenes/ui/characters_screen.tscn"},
	{"id": "shop", "key": "MENU_TAB_SHOP", "scene": "res://scenes/ui/shop.tscn"},
	{"id": "profile", "key": "MENU_TAB_PROFILE", "scene": "res://scenes/ui/profile.tscn"},
	{"id": "leaderboard", "key": "MENU_TAB_LEADERBOARD", "scene": "res://scenes/ui/leaderboard.tscn"},
]

# Onglet actif — À RÉGLER avant add_child (l'écran hôte indique sur quelle section il se trouve).
var active_tab: String = "lobby"

var _font: Font
var _xp_bar: PanelContainer = null
var _operator_name: Label = null

func _ready() -> void:
	# Bande pleine largeur ancrée en haut (hauteur fixe NAV_H). La bande elle-même est transparente
	# et n'intercepte pas la souris (IGNORE) : seuls ses enfants interactifs captent les clics.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = NAV_H
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _make_font()
	_build()
	AuthManager.profile_loaded.connect(_on_profile_loaded)
	AuthManager.get_profile()

func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f

func _build() -> void:
	# Marges latérales = menu principal (Hud : 40 px). Conteneur transparent.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	# Marque (gauche) ▸ [extenseur] ▸ pastille onglets (centre) ▸ [extenseur] ▸ cluster (droite).
	row.add_child(_build_brand())
	row.add_child(_make_spacer())
	row.add_child(_build_nav_pill())
	row.add_child(_make_spacer())
	row.add_child(_build_right_cluster())

	# Filet cyan sous la bande (miroir du FiletSeparator du menu principal), dans les marges latérales.
	var filet := ColorRect.new()
	filet.color = Color(ACCENT, 0.5)
	filet.anchor_left = 0.0
	filet.anchor_right = 1.0
	filet.anchor_top = 1.0
	filet.anchor_bottom = 1.0
	filet.offset_left = 40.0
	filet.offset_right = -40.0
	filet.offset_top = -3.0
	filet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(filet)

func _make_spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

# --- Marque « logo + WASTELAND WARFARE » (gauche, comme le menu principal) ---
func _build_brand() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 12)

	var logo := TextureRect.new()
	logo.texture = LOGO_TEX
	logo.custom_minimum_size = Vector2(64, 64)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)
	# Halo néon cyan derrière la petite marque (§8.63) — un peu plus contenu pour ne pas baver sur le titre.
	WarzoneUI.attach_mark_glow(logo, 64.0, 0.85, 1.5)

	var title := Label.new()
	title.text = "WASTELAND WARFARE"
	title.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TEXT)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(title)
	return box

# --- Pastille opaque centrée contenant les onglets (= NavPanel du menu principal) ---
func _build_nav_pill() -> Control:
	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = GUNMETAL
	st.set_corner_radius_all(0)
	st.border_width_bottom = 2
	st.border_color = Color(ACCENT, 0.6)
	st.content_margin_left = 8.0
	st.content_margin_right = 8.0
	st.content_margin_top = 2.0
	st.content_margin_bottom = 2.0
	pill.add_theme_stylebox_override("panel", st)

	var tabs_box := HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", 2)
	pill.add_child(tabs_box)
	for t in TABS:
		tabs_box.add_child(_build_tab(t))
	return pill

# --- Un onglet (Button stylé, transparent + soulignement cyan si actif — comme main_menu) ---
func _build_tab(t: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = str(t.get("key"))  # clé i18n → auto-traduite par Godot.
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 16)
	var is_active: bool = str(t.get("id")) == active_tab

	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.bg_color = Color(1, 1, 1, 0.0)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	if is_active:
		normal.border_width_bottom = 3
		normal.border_color = ACCENT
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.06)
	hover.border_width_bottom = 3
	hover.border_color = ACCENT if is_active else Color(ACCENT, 0.5)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", TEXT if is_active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.add_theme_color_override("font_pressed_color", TEXT)

	btn.pressed.connect(_on_tab_pressed.bind(str(t.get("id")), str(t.get("scene"))))
	return btn

func _on_tab_pressed(id: String, scene: String) -> void:
	if id == active_tab:
		return  # déjà sur cette section.
	AudioManager.play_sfx("click")
	TransitionManager.change_scene(scene)

# --- Cluster de droite : CADRE IDENTITÉ ▸ ⚙ Paramètres ▸ ⏻ Quitter (comme main_menu) ---
# Le choix de la langue n'est plus ici (centralisé dans l'écran Paramètres) → identité + ⚙ glissent
# d'autant vers la droite (cluster aligné END, épinglé sur la marge droite).
func _build_right_cluster() -> Control:
	var box := HBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_END

	box.add_child(_build_identity_frame())
	box.add_child(_build_icon_button("⚙", ACCENT, func() -> void: _go("res://scenes/ui/settings.tscn")))
	box.add_child(_build_icon_button("⏻", DANGER, func() -> void: get_tree().quit()))
	return box

# Cadre identité encadré (= IdentityFrame du menu principal) : eyebrow OPÉRATEUR + pseudo + jauge XP/Coins.
func _build_identity_frame() -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = SURFACE
	st.set_corner_radius_all(0)
	st.set_border_width_all(1)
	st.border_color = Color(ACCENT, 0.3)
	st.content_margin_left = 18.0
	st.content_margin_right = 18.0
	st.content_margin_top = 10.0
	st.content_margin_bottom = 10.0
	frame.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	frame.add_child(row)

	var idbox := VBoxContainer.new()
	idbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	idbox.add_theme_constant_override("separation", 0)
	row.add_child(idbox)

	var eyebrow := Label.new()
	eyebrow.text = "COMMON_OPERATOR"
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	idbox.add_child(eyebrow)

	_operator_name = Label.new()
	_operator_name.text = "—"
	_operator_name.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_operator_name.add_theme_font_override("font", _font)
	_operator_name.add_theme_font_size_override("font_size", 22)
	_operator_name.add_theme_color_override("font_color", TEXT)
	idbox.add_child(_operator_name)

	_xp_bar = XpCoinsBarScript.new()
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_xp_bar)
	return frame

# Bouton icône carré (⚙ cyan / ⏻ rouge) — même style que _style_icon_button du menu principal.
func _build_icon_button(glyph: String, accent: Color, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = glyph
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(44, 44)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.bg_color = Color(1, 1, 1, 0.03)
	normal.set_border_width_all(1)
	normal.border_color = Color(accent, 0.5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.18)
	hover.border_color = accent
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", TEXT)
	WarzoneUI.wire_button_sfx(btn)
	btn.pressed.connect(on_pressed)
	return btn

func _go(scene: String) -> void:
	AudioManager.play_sfx("click")
	TransitionManager.change_scene(scene)

func _on_profile_loaded(data: Dictionary) -> void:
	# Jauge XP + Coins (lecture défensive : clés canoniques + repli sur anciens noms, piège float §5).
	if _xp_bar:
		var level := int(data.get("player_level", data.get("niveau", 1)))
		var xp := int(data.get("current_xp", data.get("experience", 0)))
		var xp_next := int(data.get("xp_to_next_level", _xp_bar._xp_required_for_level(level) - xp))
		var coins := int(data.get("coins_balance", data.get("coins", 0)))
		_xp_bar.set_profile(level, xp, maxi(0, xp_next), coins)
	if _operator_name:
		_operator_name.text = str(data.get("username", tr("COMMON_PLAYER"))).to_upper()
