extends Control

# =========================================================
# BARRE DE NAVIGATION SUPÉRIEURE — « Warzone Command » (§2)
# =========================================================
# HEADER CANONIQUE ET UNIQUE de TOUS les écrans hub (§8.94) : menu principal, personnages,
# boutique, défis, classement, profil, réglages, placeholders. Avant §8.94 il coexistait TROIS
# familles de headers (top-bar en dur du menu, ce composant, headers maison + bouton RETOUR) : ce
# fichier est désormais la SOURCE UNIQUE — les écrans n'ont plus ni HeaderBar de nav, ni RETOUR.
#
# Composant RÉUTILISABLE construit 100 % par code (même pattern que xp_coins_bar / warzone_ui) : il
# suffit de l'`add_child()` en haut d'un écran de premier niveau, après avoir réglé `active_tab`
# (⚠️ AVANT l'ajout à l'arbre : il est lu au `_ready`).
#
# Contenu (identique partout) : marque (gauche) ▸ onglets centrés dans une PASTILLE opaque, avec la
# PASTILLE DÉFIS « ●N » ▸ cluster droite = CADRE IDENTITÉ (pseudo + jauge XP/Coins CLIQUABLE →
# mini-profil flottant) + ⚙ Paramètres + ⏻ Quitter (confirmation) ▸ filet cyan sous la barre.
#
# View PURE (Règle d'Or §6.1) : navigation via TransitionManager, données via AuthManager /
# NetworkManager (signaux). Aucune logique de jeu.
#
# i18n (R4) : les libellés d'onglet sont des CLÉS de traduction posées en `text` → Godot les
# auto-traduit et les re-traduit seul au changement de langue (auto_translate AUTO par défaut). Les
# textes COMPOSÉS (pastille « DÉFIS ●3 ») sont re-rendus à la main sur LocaleManager.locale_changed.
#
# NOTE : le choix de la LANGUE ne vit pas dans la nav — il est centralisé dans l'écran Paramètres.
# NOTE : l'AMBIANCE sonore n'est PAS lancée ici — chaque écran hôte appelle start_menu_ambient().

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
const XpCoinsBarScript = preload("res://scripts/ui/xp_coins_bar.gd")
const LOGO_TEX = preload("res://assets/images/logo_mark.svg")  # marque hex-nœuds (§8.57)

# Hauteur de la bande de navigation (marges + barre + filet) — calquée sur la top-bar du menu.
# Les écrans hôtes décalent leur contenu de NAV_H pour ne jamais passer dessous.
const NAV_H := 100.0
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
# Côté de l'avatar Steam (§8.114) : calé sur la hauteur du bloc eyebrow + pseudo pour que le cadre
# identité garde exactement sa hauteur actuelle — l'ajout ne doit pas décaler la barre de navigation.
const AVATAR_SIZE := 44.0
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.95)  # fond pastille onglets (opaque)
const SURFACE := Color(0.058824, 0.07451, 0.094118, 0.85)   # fond cadre identité (= card_panel du menu)

# --- Onglets CANONIQUES (§8.94, révisé §8.97) : STRICTEMENT alignés sur l'ancien menu principal. ---
# `profile` (OPÉRATEUR) est REVENU à sa place historique, la 4ᵉ — entre BOUTIQUE et CLASSEMENT.
# §8.94 l'avait retiré au motif que le Profil s'ouvre par la jauge XP cliquable (mini-profil, §8.58)
# et y avait mis `missions` à sa place exacte. Retour d'usage de Hakim : le chemin restant
# (jauge XP → mini-profil → « VOIR LE PROFIL COMPLET ») est FONCTIONNEL mais INDÉCOUVRABLE — deux
# clics derrière une affordance que rien ne nomme « profil ». La jauge et son mini-profil RESTENT
# (raccourci pour qui le connaît) : l'onglet ne les remplace pas, il rend le chemin évident.
# `missions` (écran DÉFIS, clé MENU_TAB_MISSIONS renommée « DÉFIS » en §8.92) glisse en 5ᵉ.
# Les sections Armes / Battle Pass / Événements / Skins restent DÉBRANCHÉES (placeholders) :
# leurs scènes vivent sur disque, réactivation = remettre leur entrée ici.
const TABS := [
	{"id": "lobby", "key": "MENU_TAB_LOBBY", "scene": "res://scenes/ui/main_menu.tscn"},
	{"id": "characters", "key": "MENU_TAB_CHARACTERS", "scene": "res://scenes/ui/characters_screen.tscn"},
	{"id": "shop", "key": "MENU_TAB_SHOP", "scene": "res://scenes/ui/shop.tscn"},
	{"id": "profile", "key": "MENU_TAB_PROFILE", "scene": "res://scenes/ui/profile.tscn"},
	{"id": "missions", "key": "MENU_TAB_MISSIONS", "scene": "res://scenes/ui/missions.tscn"},
	{"id": "leaderboard", "key": "MENU_TAB_LEADERBOARD", "scene": "res://scenes/ui/leaderboard.tscn"},
]

const LOBBY_SCENE := "res://scenes/ui/main_menu.tscn"
const PROFILE_SCENE := "res://scenes/ui/profile.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings.tscn"

# --- Factions data-driven (id -> ressource .tres) : sert UNIQUEMENT à la ligne « faction de
# prédilection » du mini-profil. Mêmes garde-fous que main_menu.gd / profile.gd (scan export-safe
# + FALLBACK_PATHS + duck-typing, aucune dépendance à un class_name). ---
const FACTIONS_DIR := "res://resources/factions/"
const FALLBACK_PATHS := [
	"res://resources/factions/phalangistes.tres",
	"res://resources/factions/nomades.tres",
	"res://resources/factions/rad_hunters.tres",
	"res://resources/factions/barons_ferraille.tres",
	"res://resources/factions/gardiens_eden.tres",
	"res://resources/factions/corporation_aegis.tres",
	"res://resources/factions/ecorcheurs_cendres.tres",
	"res://resources/factions/eveilles_ruche.tres",
	"res://resources/factions/ordre_eclipse.tres",
	"res://resources/factions/chasseurs_ombres.tres",
]

# Onglet actif — À RÉGLER avant add_child (l'écran hôte indique sur quelle section il se trouve).
# "" = écran HORS ONGLETS (profil, réglages, placeholders) → AUCUN onglet surligné : comportement
# nominal et assumé (_build_tab compare simplement l'id, rien ne matche).
var active_tab: String = "lobby"

var _font: Font
var _xp_bar: PanelContainer = null
var _operator_name: Label = null
# Avatar Steam (§8.114) : le cadre porte la bordure de charte et la VISIBILITÉ, la texture vit dans
# le TextureRect. Séparer les deux évite d'afficher un carré cyan vide avant l'arrivée de l'image.
var _avatar_frame: PanelContainer = null
var _avatar_rect: TextureRect = null

# --- Pastille DÉFIS (§8.94, ex-main_menu §8.65) : « DÉFIS ●N » quand N missions sont réclamables ---
# Vit désormais DANS la nav → la pastille est visible sur TOUS les écrans hub, plus seulement au menu.
var _missions_tab_btn: Button = null
var _missions_claimable: int = 0

# --- Mini-profil flottant (§8.58, déplacé du menu en §8.94) ---
var _profile_flyout: Control = null
var _flyout_panel: PanelContainer = null
var _flyout_body: VBoxContainer = null
var _profile_data: Dictionary = {}
var _last_faction_id: String = ""
var _factions: Dictionary = {}

# --- Confirmation « Quitter » (§8.94, ex-main_menu) : le ⏻ ne tue plus le jeu sans demander ---
var _quit_dialog: Control = null


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
	_load_factions()
	_build()

	AuthManager.profile_loaded.connect(_on_profile_loaded)
	# Avatar Steam (§8.114) : on s'abonne PUIS on réclame. La nav étant reconstruite à chaque
	# changement d'écran, `ensure_avatar` répond depuis le cache mémoire de l'AuthManager (émission
	# différée) — un seul téléchargement pour toute la session, quel que soit le nombre d'écrans.
	AuthManager.avatar_loaded.connect(_on_avatar_loaded)
	AuthManager.ensure_avatar()
	# La nav est le SEUL déclencheur de ces deux fetchs sur les écrans hub (§8.94) : elle est montée
	# partout, donc un écran hôte n'a qu'à ÉCOUTER le signal global s'il en a besoin (le menu écoute
	# missions_loaded pour sa carte Défis et profile_history_loaded pour son héros) — évite le
	# double fetch qu'aurait produit « chacun son appel ».
	NetworkManager.missions_loaded.connect(_on_missions_loaded)
	NetworkManager.profile_history_loaded.connect(_on_history_loaded)
	# Session expirée (§AC.5) : top_nav est l'en-tête COMMUN de tous les écrans hub → un seul point de
	# redirection vers l'auth, quel que soit l'écran affiché quand le token expire.
	NetworkManager.session_expired.connect(_on_session_expired)
	LocaleManager.locale_changed.connect(_on_locale_changed)

	AuthManager.get_profile()
	NetworkManager.fetch_missions()
	NetworkManager.fetch_profile_history(1)

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
		var btn := _build_tab(t)
		tabs_box.add_child(btn)
		# Mémorise l'onglet Défis : sa pastille « ●N » est un texte COMPOSÉ, re-rendu à la volée.
		if str(t.get("id")) == "missions":
			_missions_tab_btn = btn
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
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))

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
	box.add_child(_build_icon_button("⚙", ACCENT, func() -> void: _go(SETTINGS_SCENE)))
	box.add_child(_build_icon_button("⏻", DANGER, _on_quit_requested))
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

	# Avatar Steam (§8.114) — placé AVANT le pseudo : c'est le premier repère que l'œil accroche au
	# retour du navigateur, là où un joueur se demande « suis-je bien connecté sur MON compte ? ».
	# Masqué tant qu'aucune texture n'est disponible (compte sans avatar, API Steam muette, hors
	# ligne) : la mise en page se referme proprement, sans gabarit vide ni trou.
	_avatar_frame = PanelContainer.new()
	_avatar_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_avatar_frame.visible = false
	var av_st := StyleBoxFlat.new()
	av_st.bg_color = Color(ACCENT, 0.08)
	av_st.set_corner_radius_all(0)          # ADN angulaire de la charte §2.
	av_st.set_border_width_all(1)
	av_st.border_color = Color(ACCENT, 0.55)
	av_st.set_content_margin_all(2)
	_avatar_frame.add_theme_stylebox_override("panel", av_st)
	row.add_child(_avatar_frame)

	_avatar_rect = TextureRect.new()
	_avatar_rect.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# L'avatar Steam est carré (184×184) : KEEP_ASPECT_COVERED est une simple assurance contre une
	# source non carrée — mieux vaut rogner que déformer un visage.
	_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar_frame.add_child(_avatar_rect)

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
	# Jauge CLIQUABLE (§8.58, généralisée §8.94) : rendue interactive APRÈS l'ajout à l'arbre (le
	# contenu existe alors → le bouton capteur reste au-dessus). C'est LE point d'entrée du Profil,
	# qui n'a plus d'onglet.
	_xp_bar.set_interactive(true)
	_xp_bar.profile_widget_clicked.connect(_on_profile_widget_clicked)
	return frame

# Glyphe « power » (⏻) DESSINÉ par code (§8.102) : U+23FB n'existe dans AUCUNE police système de
# la chaîne (tofu constaté §8.94, Segoe UI Symbol ne l'a pas non plus) → on trace le symbole IEC
# 60417-5009 (arc ouvert en haut + trait vertical). Rendu net à toute taille, aucun nouvel asset.
class PowerGlyph extends Control:
	var color: Color = Color.WHITE:
		set(v):
			color = v
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.28
		# Arc ouvert en haut (ouverture ~80° centrée sur le sommet), puis trait vertical dans l'ouverture.
		draw_arc(c, r, -PI / 2 + 0.7, -PI / 2 + TAU - 0.7, 24, color, 2.0, true)
		draw_line(c + Vector2(0, -r * 1.30), c + Vector2(0, -r * 0.15), color, 2.0, true)


# Bouton icône carré (⚙ cyan / power rouge) — même style que _style_icon_button du menu principal.
func _build_icon_button(glyph: String, accent: Color, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(44, 44)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Correctif §8.102 du « tofu » hérité (§8.94) : le bouton Quitter (⏻) reçoit un PowerGlyph
	# dessiné par code au lieu d'un caractère manquant ; le ⚙ (couvert par la police) reste un texte.
	if glyph == "⏻":
		btn.text = ""
		var pg := PowerGlyph.new()
		pg.set_anchors_preset(Control.PRESET_FULL_RECT)
		pg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pg.color = accent
		btn.add_child(pg)
		# Miroir du comportement texte (accent → blanc froid au survol).
		btn.mouse_entered.connect(func() -> void: pg.color = TEXT)
		btn.mouse_exited.connect(func() -> void: pg.color = accent)
	else:
		btn.text = glyph
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


# =========================================================
# PASTILLE DÉFIS (§8.94) — « DÉFIS ●N » sur l'onglet des défis
# =========================================================
func _on_missions_loaded(data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement de scène.
	_missions_claimable = int(data.get("claimable_count", 0))
	_update_missions_badge()

func _update_missions_badge() -> void:
	if _missions_tab_btn == null or not is_instance_valid(_missions_tab_btn):
		return
	if _missions_claimable > 0:
		# Texte COMPOSÉ → auto-traduction désactivée, re-rendu manuel sur locale_changed.
		_missions_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_missions_tab_btn.text = "%s ●%d" % [tr("MENU_TAB_MISSIONS"), _missions_claimable]
		_missions_tab_btn.add_theme_color_override("font_color", GOLD)
	else:
		# Retour à la clé BRUTE : Godot reprend l'auto-traduction.
		_missions_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_INHERIT
		_missions_tab_btn.text = "MENU_TAB_MISSIONS"
		if active_tab == "missions":
			_missions_tab_btn.add_theme_color_override("font_color", TEXT)
		else:
			_missions_tab_btn.remove_theme_color_override("font_color")

# Session expirée (§AC.5) : purge le token mort, laisse un message et renvoie à l'écran d'auth.
# AUCUN retry — l'utilisateur se reconnecte. NetworkManager n'émet le signal qu'UNE fois.
func _on_session_expired() -> void:
	AuthManager.session_notice = tr("AUTH_SESSION_EXPIRED")
	AuthManager.clear_session()
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")


func _on_locale_changed(_code: String) -> void:
	_update_missions_badge()
	# Le mini-profil, s'il est ouvert, contient des valeurs formatées → re-rendu.
	if _profile_flyout != null and _profile_flyout.visible:
		_populate_profile_flyout()


# =========================================================
# MINI-PROFIL FLOTTANT (§8.58 — déplacé du menu principal en §8.94)
# =========================================================
# Le Profil n'a plus d'onglet : un clic sur la jauge XP/Coins ouvre ce menu déroulant à la charte
# (résumé express de l'opérateur + CTA vers le profil complet), depuis N'IMPORTE QUEL écran hub.
# Construit À LA DEMANDE. Se ferme au clic extérieur, sur ÉCHAP, ou au re-clic sur la jauge.
func _on_profile_widget_clicked() -> void:
	AudioManager.play_sfx("click")
	if _profile_flyout != null and _profile_flyout.visible:
		_close_profile_flyout()
	else:
		_open_profile_flyout()

func _open_profile_flyout() -> void:
	if _profile_flyout == null:
		_build_profile_flyout()
	_populate_profile_flyout()
	# Pré-positionnement à la taille minimale estimée (évite un flash en (0,0)), affichage, puis
	# ajustement fin une fois le layout résolu (la taille réelle n'est connue qu'après une frame).
	_flyout_panel.size = _flyout_panel.get_combined_minimum_size()
	_position_profile_flyout()
	_profile_flyout.visible = true
	await get_tree().process_frame
	_position_profile_flyout()

func _close_profile_flyout() -> void:
	if _profile_flyout:
		_profile_flyout.visible = false

# Ancre le panneau JUSTE SOUS la jauge, bord droit aligné (la jauge vit dans le cluster aligné à
# droite), borné à l'écran (jamais hors cadre). Recalculé à chaque ouverture (robuste au resize).
func _position_profile_flyout() -> void:
	if _flyout_panel == null or _xp_bar == null or not is_instance_valid(_xp_bar):
		return
	var bar := _xp_bar.get_global_rect()
	var vp := get_viewport_rect().size
	var psize := _flyout_panel.size
	var x := clampf(bar.end.x - psize.x, 8.0, maxf(8.0, vp.x - psize.x - 8.0))
	var y := minf(bar.end.y + 8.0, maxf(8.0, vp.y - psize.y - 8.0))
	_flyout_panel.global_position = Vector2(x, y)

func _build_profile_flyout() -> void:
	# Calque plein-cadre, masqué par défaut. ⚠️ Il est ajouté à la NAV (dont la hauteur est NAV_H) :
	# on force donc des ancres plein-ÉCRAN via top_level, sinon le capteur serait borné à la bande.
	_profile_flyout = Control.new()
	_profile_flyout.name = "ProfileFlyout"
	_profile_flyout.top_level = true
	_profile_flyout.set_anchors_preset(Control.PRESET_FULL_RECT)
	_profile_flyout.visible = false
	add_child(_profile_flyout)
	# top_level détache le nœud du rect de son parent : on aligne explicitement sur le viewport.
	_profile_flyout.position = Vector2.ZERO
	_profile_flyout.size = get_viewport_rect().size

	# Capteur transparent plein-cadre : tout clic HORS du panneau referme le menu (clic extérieur).
	var catcher := Control.new()
	catcher.name = "Catcher"
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close_profile_flyout())
	_profile_flyout.add_child(catcher)

	# Panneau « intel » : gunmetal quasi opaque + liseré cyan + encoches d'angle + ombre (charte §2).
	# Parent = Control simple (pas un conteneur) → position/taille pilotées en code (cf. _position_…).
	_flyout_panel = PanelContainer.new()
	_flyout_panel.name = "Panel"
	_flyout_panel.custom_minimum_size = Vector2(300, 0)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(1)
	pstyle.border_color = Color(ACCENT, 0.7)
	pstyle.set_content_margin_all(18.0)
	pstyle.shadow_color = Color(0, 0, 0, 0.5)
	pstyle.shadow_size = 10
	_flyout_panel.add_theme_stylebox_override("panel", pstyle)
	_profile_flyout.add_child(_flyout_panel)

	_flyout_body = VBoxContainer.new()
	_flyout_body.add_theme_constant_override("separation", 10)
	_flyout_panel.add_child(_flyout_body)

	WarzoneUI.add_corner_notches(_flyout_panel)

# (Re)construit le contenu du mini-profil depuis les données DÉJÀ chargées (aucun appel réseau).
func _populate_profile_flyout() -> void:
	if _flyout_body == null:
		return
	_clear(_flyout_body)

	# --- En-tête : eyebrow OPÉRATEUR + pseudo (rythme eyebrow → valeur §2) ---
	_flyout_body.add_child(_card_title("COMMON_OPERATOR"))
	var name_lbl := Label.new()
	name_lbl.text = str(_profile_data.get("username", tr("COMMON_PLAYER"))).to_upper()
	name_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", TEXT)
	_flyout_body.add_child(name_lbl)

	WarzoneUI.add_filet(_flyout_body)

	# --- Lignes de résumé (libellé muet à gauche, valeur colorée à droite) ---
	var level := int(_profile_data.get("player_level", _profile_data.get("niveau", 1)))
	var coins := int(_profile_data.get("coins_balance", _profile_data.get("coins", 0)))
	_flyout_body.add_child(_flyout_stat_row("COMMON_LEVEL", "LV %d" % maxi(1, level), ACCENT))
	_flyout_body.add_child(_flyout_stat_row("SHOP_CREDITS", str(maxi(0, coins)), GOLD))

	# Dernière faction jouée (donnée RÉELLE de l'historique) — affichée si connue, à la couleur
	# d'accent de la faction (cohérent avec profile.gd). Étiquetée « FACTION DE PRÉDILECTION ».
	if _last_faction_id != "" and _factions.has(_last_faction_id):
		var f = _factions[_last_faction_id]
		if f != null and f.get("name") != null:
			var fac_color: Color = f.accent_color if f.get("accent_color") != null else ACCENT
			_flyout_body.add_child(_flyout_stat_row("PROFILE_FAVORITE_FACTION", str(f.name).to_upper(), fac_color))

	WarzoneUI.add_filet(_flyout_body)

	# --- CTA : ouvre le profil complet via TransitionManager ---
	var cta := Button.new()
	cta.text = "MENU_PROFILE_VIEW_FULL"  # clé brute -> auto-traduction (FR/EN/IT)
	cta.add_theme_font_override("font", _font)
	cta.add_theme_font_size_override("font_size", 15)
	cta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WarzoneUI.apply_ghost_button(cta)
	cta.pressed.connect(func() -> void:
		_close_profile_flyout()
		_go(PROFILE_SCENE))
	cta.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	_flyout_body.add_child(cta)

# Ligne « eyebrow → valeur » du mini-profil : libellé muet à gauche, valeur colorée à droite.
func _flyout_stat_row(label_key: String, value: String, value_color: Color) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)

	var l := Label.new()
	l.text = label_key  # clé brute -> auto-traduction
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)

	var v := Label.new()
	v.text = value
	v.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	v.add_theme_font_override("font", _font)
	v.add_theme_font_size_override("font_size", 18)
	v.add_theme_color_override("font_color", value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(v)
	return h

func _card_title(key: String) -> Label:
	var l := Label.new()
	l.text = key  # clé brute -> auto-traduction
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ACCENT)
	return l


# =========================================================
# RETOUR UNIFORME (§8.94) — ÉCHAP remplace tous les boutons RETOUR supprimés
# =========================================================
# Priorité : (1) si le mini-profil est ouvert, ÉCHAP le referme ; (2) sinon, depuis tout écran hub
# AUTRE que le QG, ÉCHAP ramène au menu principal. Au QG (active_tab == "lobby") ÉCHAP ne fait rien
# (le menu a son propre ⏻ pour quitter). _unhandled_input : ne vole jamais l'événement à un champ de
# saisie ou à un bouton focalisé.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _quit_dialog != null and _quit_dialog.visible:
		_on_quit_cancel()
		get_viewport().set_input_as_handled()
		return
	if _profile_flyout != null and _profile_flyout.visible:
		_close_profile_flyout()
		get_viewport().set_input_as_handled()
		return
	if active_tab != "lobby":
		AudioManager.play_sfx("click")
		TransitionManager.change_scene(LOBBY_SCENE)
		get_viewport().set_input_as_handled()


# =========================================================
# CONFIRMATION « QUITTER » (§8.94, portée du menu) — overlay modal à la charte
# =========================================================
# Avant §8.94 le ⏻ de cette barre tuait le jeu SANS demander (seul le menu confirmait) : en faisant
# de top_nav le header unique, on porte la confirmation ici → plus aucune sortie accidentelle.
func _on_quit_requested() -> void:
	if _quit_dialog == null:
		_build_quit_dialog()
	if _quit_dialog:
		_quit_dialog.visible = true

func _build_quit_dialog() -> void:
	var dim := ColorRect.new()
	dim.name = "QuitDialog"
	dim.color = Color(0, 0, 0, 0.6)
	# top_level : le dialogue doit couvrir TOUT l'écran, pas la seule bande de nav (hauteur NAV_H).
	dim.top_level = true
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	add_child(dim)
	dim.position = Vector2.ZERO
	dim.size = get_viewport_rect().size

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	pstyle.set_corner_radius_all(0)
	pstyle.set_border_width_all(2)
	pstyle.border_color = DANGER
	pstyle.set_content_margin_all(28.0)
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	var title := Label.new()
	title.text = "MENU_QUIT_TITLE"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var body := Label.new()
	body.text = "MENU_QUIT_BODY"
	body.add_theme_font_override("font", _font)
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", MUTED)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)

	var cancel := Button.new()
	cancel.text = "MENU_QUIT_CANCEL"
	cancel.add_theme_font_override("font", _font)
	cancel.add_theme_font_size_override("font_size", 16)
	cancel.custom_minimum_size = Vector2(150, 48)
	WarzoneUI.apply_ghost_button(cancel)
	cancel.pressed.connect(_on_quit_cancel)
	cancel.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	row.add_child(cancel)

	var ok := Button.new()
	ok.text = "MENU_QUIT_OK"
	ok.add_theme_font_override("font", _font)
	ok.add_theme_font_size_override("font_size", 16)
	ok.custom_minimum_size = Vector2(170, 48)
	_style_danger_button(ok)
	ok.pressed.connect(_on_quit_confirm)
	ok.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	row.add_child(ok)

	WarzoneUI.add_corner_notches(panel, 16.0, DANGER)
	_quit_dialog = dim

func _on_quit_cancel() -> void:
	AudioManager.play_sfx("click")
	if _quit_dialog:
		_quit_dialog.visible = false

func _on_quit_confirm() -> void:
	AudioManager.play_sfx("click")
	get_tree().quit()

func _style_danger_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.set_content_margin_all(10.0)
	normal.bg_color = Color(DANGER, 0.16)
	normal.set_border_width_all(2)
	normal.border_color = DANGER
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(DANGER, 0.32)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)


# =========================================================
# DONNÉES (AuthManager / NetworkManager)
# =========================================================
# Avatar Steam prêt (§8.114) — le cadre n'apparaît qu'à cet instant, jamais vide.
func _on_avatar_loaded(tex: Texture2D) -> void:
	if not is_inside_tree() or _avatar_rect == null:
		return
	_avatar_rect.texture = tex
	if _avatar_frame:
		_avatar_frame.visible = tex != null

func _on_profile_loaded(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	_profile_data = data  # alimente le mini-profil sans nouvel appel réseau.
	# Jauge XP + Coins (lecture défensive : clés canoniques + repli sur anciens noms, piège float §5).
	if _xp_bar:
		var level := int(data.get("player_level", data.get("niveau", 1)))
		var xp := int(data.get("current_xp", data.get("experience", 0)))
		var xp_next := int(data.get("xp_to_next_level", _xp_bar._xp_required_for_level(level) - xp))
		var coins := int(data.get("coins_balance", data.get("coins", 0)))
		_xp_bar.set_profile(level, xp, maxi(0, xp_next), coins)
	if _operator_name:
		_operator_name.text = str(data.get("username", tr("COMMON_PLAYER"))).to_upper()
	# Si le mini-profil est ouvert au moment où le profil (re)charge, on rafraîchit son résumé.
	if _profile_flyout != null and _profile_flyout.visible:
		_populate_profile_flyout()

# Historique (/profile/history, le plus récent d'abord) : la 1re entrée valide donne la DERNIÈRE
# faction jouée → alimente la ligne « faction de prédilection » du mini-profil.
func _on_history_loaded(entries: Array) -> void:
	if not is_inside_tree():
		return
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			var fid := str(e.get("faction_id", ""))
			if fid != "":
				_last_faction_id = fid
				if _profile_flyout != null and _profile_flyout.visible:
					_populate_profile_flyout()
				return


# =========================================================
# CATALOGUE DE FACTIONS (garde-fous de main_menu.gd / faction_selection.gd)
# =========================================================
func _load_factions() -> void:
	var paths := _scan_faction_paths()
	if paths.is_empty():
		paths = FALLBACK_PATHS.duplicate()
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		# Duck-typing : on accepte toute ressource exposant un id (pas de dépendance au class_name).
		if res != null and res.get("id") != null:
			_factions[str(res.id)] = res

func _scan_faction_paths() -> Array:
	var out := []
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var fn := file_name
			if fn.ends_with(".remap"):
				fn = fn.trim_suffix(".remap")
			if fn.ends_with(".tres"):
				var full := FACTIONS_DIR + fn
				if not out.has(full):
					out.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

# Vide un conteneur sans laisser de doublons (cf. main_menu.gd / profile.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
