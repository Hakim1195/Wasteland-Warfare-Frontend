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
# §8.126.1 — porteur du `static var target_tag` de l'écran Compagnie (purgé au clic sur l'onglet).
const CompanyScreen = preload("res://scripts/ui/company_screen.gd")
# §8.135 — bordure de maîtrise du cadre identité (implémentation unique, cf. mastery_border.gd).
const MasteryBorder = preload("res://scripts/ui/mastery_border.gd")
const LOGO_TEX = preload("res://assets/images/logo_mark.svg")  # marque hex-nœuds (§8.57)

# Hauteur de la bande de navigation (marges + barre + filet) — calquée sur la top-bar du menu.
# Les écrans hôtes décalent leur contenu de NAV_H pour ne jamais passer dessous.
const NAV_H := 100.0
# Marges latérales de la bande (calquées sur le Hud du menu principal, 40 px de chaque côté).
# Extraites en constante depuis §8.133 : la mesure de débordement en a besoin, et deux chiffres 40
# recopiés auraient fini par diverger de la mise en page réelle.
const NAV_MARGIN_X := 40.0
# Marge BASSE interne de la bande : l'espace que le contenu de la nav laisse sous lui avant le
# filet cyan. Extraite en constante (§8.134.1) parce qu'elle sert désormais DEUX fois — ici, et
# comme respiration des écrans hôtes (ci-dessous).
const NAV_MARGIN_BOTTOM := 10.0
# Hauteur à laquelle un écran qui aligne son contenu EN HAUT doit commencer (le QG). Un écran qui
# démarre exactement à `NAV_H` vient s'ADOSSER au filet : ses cartes touchent la ligne, sans un
# pixel de respiration, là où la nav s'en accorde une au-dessus. On rend donc la même respiration
# en dessous — l'écran n'a aucun chiffre à deviner, et la relation survit à un changement de NAV_H.
# ⚠️ Ne concerne QUE les écrans à contenu haut : les autres centrent leur panneau (CenterContainer
# + `offset_top = NAV_H`) et ont déjà tout l'espace du monde.
const NAV_CONTENT_TOP := NAV_H + NAV_MARGIN_BOTTOM
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
# `profile` (JOUEUR) est REVENU à sa place historique, la 4ᵉ — entre BOUTIQUE et CLASSEMENT.
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
	# §8.134 — DÉFIS A QUITTÉ LA BARRE. L'écran des missions est devenu le 4ᵉ onglet du hub
	# ÉVÉNEMENTS ; sa pastille « ●N » a MIGRÉ sur l'onglet ÉVÉNEMENTS (cf. `_update_events_badge`).
	# La barre passe ainsi de 8 à 7 onglets — et c'est aussi 80 px de moins à faire tenir, ce qui
	# n'est pas un détail après la mesure de débordement du §8.133.
	{"id": "leaderboard", "key": "MENU_TAB_LEADERBOARD", "scene": "res://scenes/ui/leaderboard.tscn"},
	# §8.126.1 — COMPAGNIE. Placée APRÈS le Classement, dans la continuité : les deux répondent à
	# « où est-ce que je me situe ? », l'une seul, l'autre avec les siens. Avant cet onglet, l'écran
	# n'était atteignable que depuis une carte du Profil — autant dire invisible.
	{"id": "company", "key": "MENU_TAB_COMPANY", "scene": "res://scenes/ui/company_screen.tscn"},
	# §8.132 — ÉVÉNEMENTS. Placé APRÈS Compagnie (demande Hakim, 2026-08-02) : c'est la dernière
	# entrée, celle qu'on consulte « au cas où il se passerait quelque chose ce week-end ». La scène
	# `events.tscn` existait déjà en PLACEHOLDER (« section en construction ») depuis les premiers
	# chantiers ; elle porte désormais le vrai écran — on ne crée pas de seconde scène.
	{"id": "events", "key": "NAV_EVENTS", "scene": "res://scenes/ui/events.tscn"},
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
var _player_name: Label = null
# Avatar Steam (§8.114) : le cadre porte la bordure de charte et la VISIBILITÉ, la texture vit dans
# le TextureRect. Séparer les deux évite d'afficher un carré cyan vide avant l'arrivée de l'image.
var _avatar_frame: PanelContainer = null
var _avatar_rect: TextureRect = null

# --- Pastille DÉFIS (§8.94, ex-main_menu §8.65) : « DÉFIS ●N » quand N missions sont réclamables ---
# Vit désormais DANS la nav → la pastille est visible sur TOUS les écrans hub, plus seulement au menu.
var _missions_tab_btn: Button = null
var _missions_claimable: int = 0

# --- Pastille COMPAGNIE (§8.126.1) : « COMPAGNIE ●N » (non-lus, or) ou « COMPAGNIE ◦N » (camarades
# en ligne, cyan). DEUX signaux, UN emplacement, priorité aux non-lus : une notification se traite,
# une présence s'observe. Le second glyphe est un `◦` ASCII-safe (les emoji rendent en TOFU avec la
# police condensée de la charte — constat §8.117/§8.123). ---
var _company_tab_btn: Button = null
var _company_unread: int = 0
var _company_online: int = 0
# §8.132 — pastille ÉVÉNEMENTS : un simple point OR quand une opération est EN COURS. Pas de
# compteur (contrairement à DÉFIS/COMPAGNIE) : il n'y a JAMAIS qu'un seul événement actif à la
# fois — un « ●1 » perpétuel n'apprendrait rien à personne.
var _events_tab_btn: Button = null
var _event_active: bool = false

# --- Mini-profil flottant (§8.58, déplacé du menu en §8.94) ---
var _profile_flyout: Control = null
var _flyout_panel: PanelContainer = null
var _flyout_body: VBoxContainer = null
var _profile_data: Dictionary = {}
var _last_faction_id: String = ""
var _factions: Dictionary = {}

# --- Confirmation « Quitter » (§8.94, ex-main_menu) : le ⏻ ne tue plus le jeu sans demander ---
var _quit_dialog: Control = null


# =========================================================
# NAV RÉSILIENTE (§8.133) — dégradation contrôlée
# =========================================================
# INVARIANT DU CHANTIER : le CLUSTER DROIT (identité + ⚙ + ⏻) ne rétrécit jamais et ne sort JAMAIS
# de l'écran. Tout le reste plie avant lui — parce que c'est par ⚙ qu'on répare une échelle trop
# grande, et par ⏻ qu'on quitte. Les rendre inatteignables enferme le joueur (bug d'origine :
# à 115 % d'échelle sur 1920, le viewport logique tombe à 1669 px pour une rangée qui en réclame
# 1801 ; à 1600 px de fenêtre, la rangée débordait DÈS 90 %).
#
# TROIS PALIERS DE DENSITÉ, puis un DÉBORDEMENT, appliqués dans l'ordre jusqu'à ce que ça tienne :
#   0 — nominal : marges d'onglet 16 px, police 16, marque « logo + WASTELAND WARFARE ».
#   1 — compact : marges 10 px, police 14 (≈ 165 px regagnés).
#   2 — marque en LOGO SEUL, le texte est masqué (≈ 220 px de plus).
#   3+ — les onglets EXCÉDENTAIRES basculent, un par un EN PARTANT DE LA GAUCHE, dans un menu
#        « ••• » en fin de pilule. L'onglet ACTIF n'y va JAMAIS : on doit toujours voir où on est.
# Chaque palier est RÉVERSIBLE : `_relayout()` repart systématiquement du palier 0 et redescend, si
# bien qu'une fenêtre qui regrandit retrouve sa barre complète sans rien à recliquer.
const DENSITY_STEPS := 3
const TAB_MARGIN_X: Array[float] = [16.0, 10.0, 10.0]
const TAB_FONT_SIZE: Array[int] = [16, 14, 14]
const BRAND_TEXT_VISIBLE: Array[bool] = [true, true, false]

var _row: HBoxContainer = null
var _pill: PanelContainer = null
var _tabs_box: HBoxContainer = null
var _brand_title: Label = null
# id d'onglet -> Button (les trois pastilles s'en servent aussi : un seul registre, pas quatre var).
var _tab_buttons: Dictionary = {}
var _overflow_btn: MenuButton = null
# Définitions d'onglets actuellement DANS le menu « ••• » (ordre = ordre des entrées du popup).
var _overflow_tabs: Array = []
# Palier de densité courant. -1 = « jamais appliqué » → le premier `_apply_density(0)` agit.
var _density_level: int = -1
var _overflow_count: int = -1


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
	# §8.135 (LOT 0) — la réponse du claim porte DÉJÀ le nouveau solde (`coins_balance`, cf.
	# `POST /missions/claim`) : la jauge se met à jour à cet instant, sans attendre le prochain
	# `/auth/me`. On s'abonne ICI plutôt que dans `missions_panel` parce que la jauge appartient à la
	# nav : n'importe quel hôte du panneau (aujourd'hui l'onglet DÉFIS du hub, demain un autre) en
	# bénéficie sans le savoir. AUCUN appel réseau supplémentaire.
	NetworkManager.mission_claimed.connect(_on_mission_claimed)
	# §8.135 — bordure de MAÎTRISE du cadre identité (cf. le bloc dédié plus bas pour le coût réseau).
	NetworkManager.profile_stats_loaded.connect(_on_profile_stats_for_mastery)
	NetworkManager.profile_history_loaded.connect(_on_history_loaded)
	# §8.126.1 — pastille COMPAGNIE. Route VOLONTAIREMENT minuscule (`/company/badge` : deux
	# nombres), justement parce qu'elle part depuis TOUS les écrans hub à chaque navigation.
	NetworkManager.company_badge_loaded.connect(_on_company_badge)
	# §8.132 — configuration des ÉVÉNEMENTS. Même raisonnement que ci-dessus : la nav est montée
	# partout, elle charge UNE fois par écran et les écrans hôtes (QG, recherche) n'ont qu'à écouter
	# `events_loaded`. Réponse mémoïsée 60 s côté serveur → le coût réel est nul.
	NetworkManager.events_loaded.connect(_on_events_config)
	# Session expirée (§AC.5) : top_nav est l'en-tête COMMUN de tous les écrans hub → un seul point de
	# redirection vers l'auth, quel que soit l'écran affiché quand le token expire.
	NetworkManager.session_expired.connect(_on_session_expired)
	LocaleManager.locale_changed.connect(_on_locale_changed)

	AuthManager.get_profile()
	NetworkManager.fetch_missions()
	NetworkManager.fetch_profile_history(1)
	NetworkManager.fetch_company_badge()
	NetworkManager.fetch_events()
	# Le cache peut DÉJÀ être garni (navigation depuis un autre écran hub) : on peint la pastille
	# tout de suite, sans attendre l'aller-retour — sinon elle clignoterait à chaque changement
	# d'écran (absente puis présente).
	if not NetworkManager.events_config.is_empty():
		_on_events_config(NetworkManager.events_config)
	# §8.135 — bordure de maîtrise : UNE demande par SESSION, puis peinture depuis le cache statique
	# à chaque navigation (la nav est reconstruite à chaque écran — cf. le bloc dédié plus bas).
	if not _mastery_fetched:
		_mastery_fetched = true
		NetworkManager.fetch_profile_stats()
	elif _mastery_tier_cache != "":
		_apply_mastery_frame(_mastery_tier_cache)
	_start_invite_poll()

func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f

func _build() -> void:
	# Marges latérales = menu principal (Hud : 40 px). Conteneur transparent.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(NAV_MARGIN_X))
	margin.add_theme_constant_override("margin_right", int(NAV_MARGIN_X))
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", int(NAV_MARGIN_BOTTOM))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	_row = row

	# Marque (gauche) ▸ [extenseur] ▸ pastille onglets (centre) ▸ [extenseur] ▸ cluster (droite).
	row.add_child(_build_brand())
	row.add_child(_make_spacer())
	row.add_child(_build_nav_pill())
	row.add_child(_make_spacer())
	row.add_child(_build_right_cluster())

	# §8.133 — mesure du PLANCHER (nav la plus dégradée) publiée au SettingsManager, qui s'en sert
	# pour borner l'échelle d'interface. Faite ici, avant la première frame : les paliers extrêmes
	# sont posés puis immédiatement relâchés par `_relayout()`, rien n'est visible à l'écran.
	_measure_and_report_floor()
	_relayout()

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
	# §8.133 — 2ᵉ palier de dégradation : ce Label se masque et la marque redevient le seul logo.
	_brand_title = title
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
		_tab_buttons[str(t.get("id"))] = btn
		# Mémorise l'onglet Défis : sa pastille « ●N » est un texte COMPOSÉ, re-rendu à la volée.
		if str(t.get("id")) == "missions":
			_missions_tab_btn = btn
		# §8.126.1 — même mécanique pour la pastille COMPAGNIE.
		elif str(t.get("id")) == "company":
			_company_tab_btn = btn
		# §8.132 — même mécanique ENCORE (troisième usage : on RÉUTILISE, on ne duplique pas).
		elif str(t.get("id")) == "events":
			_events_tab_btn = btn
	# §8.133 — menu de DÉBORDEMENT, dernier palier de dégradation. Créé toujours, masqué tant que
	# la rangée tient : le construire à la demande obligerait à le glisser au bon rang du HBox au
	# pire moment (pendant une mesure), et un MenuButton invisible ne coûte rien.
	tabs_box.add_child(_build_overflow_button())
	_pill = pill
	_tabs_box = tabs_box
	return pill


# --- Menu « ••• » : les onglets qui ne tiennent plus, sans en perdre aucun -----------------------
func _build_overflow_button() -> MenuButton:
	var mb := MenuButton.new()
	mb.text = "•••"
	mb.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	mb.tooltip_text = tr("NAV_MORE_TOOLTIP")
	mb.visible = false
	mb.focus_mode = Control.FOCUS_NONE
	mb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mb.add_theme_font_override("font", _font)
	mb.add_theme_font_size_override("font_size", 16)
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.bg_color = Color(1, 1, 1, 0.0)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.06)
	hover.border_width_bottom = 3
	hover.border_color = Color(ACCENT, 0.5)
	mb.add_theme_stylebox_override("normal", normal)
	mb.add_theme_stylebox_override("hover", hover)
	mb.add_theme_stylebox_override("pressed", hover)
	mb.add_theme_stylebox_override("focus", normal)
	mb.add_theme_color_override("font_color", MUTED)
	mb.add_theme_color_override("font_hover_color", TEXT)
	mb.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	# L'id de l'entrée est son RANG dans `_overflow_tabs` : la liste change à chaque relayout, mais
	# le popup est reconstruit dans la foulée — les deux ne peuvent pas se désynchroniser.
	mb.get_popup().id_pressed.connect(func(idx: int) -> void:
		if idx < 0 or idx >= _overflow_tabs.size():
			return
		var t: Dictionary = _overflow_tabs[idx]
		_on_tab_pressed(str(t.get("id")), str(t.get("scene"))))
	_overflow_btn = mb
	return mb

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
	# §8.126.1 — l'onglet mène TOUJOURS à MA compagnie. On purge explicitement le porteur statique :
	# sans ça, un joueur qui vient de consulter la fiche publique d'un autre clan (Classement, profil
	# public) rouvrirait CELLE-LÀ en cliquant sur son propre onglet. `company_screen` le remet déjà à
	# "" à la lecture — cette ligne est la ceinture qui rend le raisonnement inutile.
	if id == "company":
		CompanyScreen.target_tag = ""
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

# Cadre identité encadré (= IdentityFrame du menu principal) : eyebrow JOUEUR + pseudo + jauge XP/Coins.
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
	eyebrow.text = "COMMON_PLAYER_LABEL"
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	idbox.add_child(eyebrow)

	_player_name = Label.new()
	_player_name.text = "—"
	_player_name.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_player_name.add_theme_font_override("font", _font)
	_player_name.add_theme_font_size_override("font_size", 22)
	_player_name.add_theme_color_override("font_color", TEXT)
	idbox.add_child(_player_name)

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
# MOTEUR DE DÉGRADATION (§8.133)
# =========================================================
# Redimensionnement du viewport (fenêtre tirée, plein écran, changement d'échelle d'interface) :
# la bande est ancrée pleine largeur, donc sa `size.x` EST la largeur logique disponible.
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


# Largeur logique dont la rangée a besoin dans son état courant, marges de bande comprises.
func _row_need() -> float:
	if _row == null or not is_instance_valid(_row):
		return 0.0
	return _row.get_combined_minimum_size().x + NAV_MARGIN_X * 2.0


# Cherche le palier le PLUS LÉGER qui tienne, en repartant toujours du nominal — c'est ce qui rend
# la dégradation réversible : rien ne « reste » dégradé quand la place revient.
func _relayout() -> void:
	if _row == null or not is_instance_valid(_row) or not is_inside_tree():
		return
	var avail := size.x
	if avail <= 0.0:
		return
	for lvl in range(DENSITY_STEPS):
		_apply_density(lvl)
		_set_overflow_count(0)
		if _row_need() <= avail:
			return
	# Toujours trop large au palier de densité maximal : on évacue les onglets un par un vers le
	# menu « ••• ». Borne HAUTE = tous sauf l'actif — au-delà il n'y a plus rien à retirer, et le
	# cluster droit reste intouchable par construction (invariant du chantier).
	for n in range(1, TABS.size()):
		_set_overflow_count(n)
		if _row_need() <= avail:
			return


# Applique un palier de DENSITÉ (marges + police des onglets, visibilité du texte de marque).
func _apply_density(level: int) -> void:
	level = clampi(level, 0, DENSITY_STEPS - 1)
	if level == _density_level:
		return
	_density_level = level
	var mx: float = TAB_MARGIN_X[level]
	var fs: int = TAB_FONT_SIZE[level]
	for id in _tab_buttons:
		var btn: Button = _tab_buttons[id]
		if btn == null or not is_instance_valid(btn):
			continue
		btn.add_theme_font_size_override("font_size", fs)
		# `normal`/`hover`/`pressed`/`focus` partagent deux objets seulement (cf. `_build_tab`) :
		# les parcourir tous les quatre est sans effet de bord, et à l'épreuve d'un futur 3ᵉ style.
		for style_name in ["normal", "hover", "pressed", "focus"]:
			var sb := btn.get_theme_stylebox(style_name) as StyleBoxFlat
			if sb != null:
				sb.content_margin_left = mx
				sb.content_margin_right = mx
		btn.update_minimum_size()
	if _overflow_btn != null and is_instance_valid(_overflow_btn):
		_overflow_btn.add_theme_font_size_override("font_size", fs)
		_overflow_btn.update_minimum_size()
	if _brand_title != null and is_instance_valid(_brand_title):
		_brand_title.visible = BRAND_TEXT_VISIBLE[level]
	if _tabs_box != null and is_instance_valid(_tabs_box):
		_tabs_box.update_minimum_size()


# Bascule les `n` premiers onglets NON ACTIFS (de gauche à droite) dans le menu « ••• ».
func _set_overflow_count(n: int) -> void:
	if _tabs_box == null or not is_instance_valid(_tabs_box):
		return
	n = clampi(n, 0, TABS.size() - 1)
	if n == _overflow_count:
		return
	_overflow_count = n
	var moved: Array = []
	var remaining := n
	for t in TABS:
		var id := str(t.get("id"))
		var btn: Button = _tab_buttons.get(id)
		if btn == null or not is_instance_valid(btn):
			continue
		# L'onglet ACTIF est SAUTÉ sans consommer de quota : on doit toujours voir où on est.
		var to_menu: bool = remaining > 0 and id != active_tab
		if to_menu:
			remaining -= 1
			moved.append(t)
		btn.visible = not to_menu
	_overflow_tabs = moved
	if _overflow_btn != null and is_instance_valid(_overflow_btn):
		_overflow_btn.visible = not moved.is_empty()
	_refresh_overflow_menu()
	# La visibilité d'un enfant ne réinvalide pas toujours le cache de taille minimale du parent :
	# on force, sinon la mesure qui suit lirait l'ANCIENNE largeur et la boucle croirait avoir gagné.
	_tabs_box.update_minimum_size()


# Une PASTILLE vient d'apparaître ou de disparaître (§8.134.2) : « ÉVÉNEMENTS » devient
# « ÉVÉNEMENTS ●3 », l'onglet s'élargit, et la rangée peut cesser de tenir. Les réponses réseau
# arrivent APRÈS `_build()`, donc après le seul `_relayout()` de la construction — sans ce rappel,
# une barre calculée juste à la construction déborde dès que les pastilles se posent.
# ⚠️ Pas de récursion : `_relayout()` appelle `_set_overflow_count()` → `_refresh_overflow_menu()`,
# qui ne rappelle rien. Le sens de la dépendance est à sens unique.
func _badges_changed() -> void:
	_refresh_overflow_menu()
	_relayout()


# (Re)peuple le popup. Le libellé est celui de l'onglet TEL QU'IL EST à cet instant — pastille
# comprise : une mission réclamable reste visible même quand DÉFIS a basculé dans le menu.
func _refresh_overflow_menu() -> void:
	if _overflow_btn == null or not is_instance_valid(_overflow_btn):
		return
	var pop := _overflow_btn.get_popup()
	pop.clear()
	for i in range(_overflow_tabs.size()):
		pop.add_item(_menu_entry_text(_overflow_tabs[i]), i)


func _menu_entry_text(t: Dictionary) -> String:
	var btn: Button = _tab_buttons.get(str(t.get("id")))
	# Un onglet à pastille porte un texte COMPOSÉ déjà traduit (auto-traduction coupée) : on le
	# reprend tel quel. Sinon le bouton ne contient qu'une CLÉ i18n brute, qu'il faut traduire.
	if btn != null and is_instance_valid(btn) \
			and btn.auto_translate_mode == Control.AUTO_TRANSLATE_MODE_DISABLED:
		return btn.text
	return tr(str(t.get("key")))


# Mesure du PLANCHER absolu de la barre (§8.133) : état le plus dégradé possible — densité
# maximale, tous les onglets sauf l'actif dans le menu. C'est la largeur en dessous de laquelle
# plus aucune dégradation ne peut sauver l'interface ; le SettingsManager en fait la borne de
# l'échelle. Mesuré sur la nav RÉELLE (langue et onglets du jour), jamais un chiffre en dur.
func _measure_and_report_floor() -> void:
	_apply_density(DENSITY_STEPS - 1)
	_set_overflow_count(TABS.size() - 1)
	SettingsManager.report_nav_floor_width(_row_need())


# =========================================================
# PASTILLE DÉFIS (§8.94) — « DÉFIS ●N » sur l'onglet des défis
# =========================================================
func _on_missions_loaded(data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement de scène.
	_missions_claimable = int(data.get("claimable_count", 0))
	# §8.134 — l'onglet DÉFIS n'existe plus dans la barre : `_update_missions_badge` est devenue une
	# no-op défensive (son bouton est null), et c'est la pastille ÉVÉNEMENTS qui porte le « ●N ».
	_update_missions_badge()
	_update_events_badge()
	# §8.133 — l'onglet peut être dans le menu « ••• » : sa pastille doit y suivre.
	# §8.134.2 — et la barre se re-mesure : une pastille élargit l'onglet.
	_badges_changed()

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

# =========================================================
# PASTILLE COMPAGNIE (§8.126.1) — deux signaux, un emplacement
# =========================================================
# Priorité aux NON-LUS (or, `●N`) : une notification se traite, alors qu'une présence s'observe. À
# zéro non-lu, on retombe sur les CAMARADES EN LIGNE (cyan, `◦N`) — c'est le signal qui fait revenir
# jouer. Aucun des deux → clé BRUTE, l'onglet redevient un onglet.
func _on_company_badge(data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement de scène.
	_company_unread = int(data.get("unread", 0))
	_company_online = int(data.get("online", 0))
	_update_company_badge()
	_badges_changed()   # §8.133/§8.134.2 — pastille suivie au menu « ••• », ET barre re-mesurée.
	var invite = data.get("invite", {})
	_show_company_invite(invite if typeof(invite) == TYPE_DICTIONARY else {})


# =========================================================
# INVITATION DE COMPAGNIE (finitions pré-playtest) — poll 15 s + toast
# =========================================================
# La nav ne se rafraîchissait QU'AU CHANGEMENT D'ÉCRAN : un joueur immobile au QG n'aurait jamais vu
# arriver l'invitation d'un camarade. D'où ce timer — le SEUL de la barre de navigation.
#
# ⚠️⚠️ UN SEUL TIMER, ET JAMAIS EN ARÈNE. `top_nav` est instanciée par CHAQUE écran hub : sans
# précaution, changer d'écran cinq fois ferait tourner cinq timers et quintuplerait le trafic. Le
# timer est donc enfant de CETTE instance et meurt avec elle (`queue_free` de l'écran) — il ne peut
# pas s'accumuler. Et l'arène ne monte pas de `top_nav` du tout : aucun poll ne part pendant un
# match, ce qui serait à la fois inutile (le joueur ne peut pas rejoindre) et coûteux au pire moment.
const INVITE_POLL_S := 15.0

var _invite_timer: Timer = null
var _invite_toast: PanelContainer = null
var _invite_code: String = ""

func _start_invite_poll() -> void:
	if _invite_timer != null and is_instance_valid(_invite_timer):
		return
	_invite_timer = Timer.new()
	_invite_timer.wait_time = INVITE_POLL_S
	_invite_timer.autostart = true
	_invite_timer.timeout.connect(func() -> void:
		if is_inside_tree():
			NetworkManager.fetch_company_badge())
	add_child(_invite_timer)


# `{}` = plus d'invitation (expirée, acceptée, ou escouade dissoute) → le toast disparaît SANS un
# mot. Une invitation qui expire n'est pas un évènement : l'annoncer ferait passer un non-évènement
# pour une mauvaise nouvelle.
func _show_company_invite(invite: Dictionary) -> void:
	var code := str(invite.get("squad_code", ""))
	if code == "":
		if _invite_toast != null and is_instance_valid(_invite_toast):
			_invite_toast.queue_free()
		_invite_toast = null
		_invite_code = ""
		return
	if code == _invite_code and _invite_toast != null and is_instance_valid(_invite_toast):
		return   # même invitation qu'au tick précédent : on ne la re-crée pas sous les doigts
	if _invite_toast != null and is_instance_valid(_invite_toast):
		_invite_toast.queue_free()
	_invite_code = code

	var toast := PanelContainer.new()
	toast.name = "CompanyInviteToast"
	toast.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.97)
	st.set_corner_radius_all(0)
	st.set_border_width_all(0)
	st.border_width_left = 3
	st.border_color = GOLD
	st.set_content_margin_all(12.0)
	toast.add_theme_stylebox_override("panel", st)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	toast.add_child(row)

	var label := Label.new()
	label.text = tr("COMPANY_INVITE_TOAST") % str(invite.get("from_name", "")).to_upper()
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)

	var join := Button.new()
	join.text = tr("COMPANY_INVITE_JOIN")
	join.focus_mode = Control.FOCUS_NONE
	join.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	join.add_theme_font_override("font", _font)
	join.add_theme_font_size_override("font_size", 15)
	join.add_theme_color_override("font_color", GOLD)
	join.pressed.connect(func() -> void:
		AudioManager.play_sfx("click")
		var joining := _invite_code
		_show_company_invite({})        # le joueur a tranché : le toast part tout de suite
		NetworkManager.squad_join(joining)
		TransitionManager.change_scene("res://scenes/ui/squad_screen.tscn"))
	row.add_child(join)

	# Ancré SOUS la barre de navigation, à droite : hors du chemin des onglets, et hors du centre
	# où vivent les CTA de chaque écran.
	add_child(toast)
	toast.reset_size()
	toast.position = Vector2(size.x - toast.size.x - 24.0, 96.0)

func _update_company_badge() -> void:
	if _company_tab_btn == null or not is_instance_valid(_company_tab_btn):
		return
	if _company_unread > 0:
		# Texte COMPOSÉ → auto-traduction désactivée, re-rendu manuel sur locale_changed.
		_company_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_company_tab_btn.text = "%s ●%d" % [tr("MENU_TAB_COMPANY"), _company_unread]
		_company_tab_btn.add_theme_color_override("font_color", GOLD)
		return
	if _company_online > 0:
		_company_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_company_tab_btn.text = "%s ◦%d" % [tr("MENU_TAB_COMPANY"), _company_online]
		_company_tab_btn.add_theme_color_override("font_color", ACCENT)
		return
	# Retour à la clé BRUTE : Godot reprend l'auto-traduction.
	_company_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_INHERIT
	_company_tab_btn.text = "MENU_TAB_COMPANY"
	if active_tab == "company":
		_company_tab_btn.add_theme_color_override("font_color", TEXT)
	else:
		_company_tab_btn.remove_theme_color_override("font_color")


# =========================================================
# PASTILLE ÉVÉNEMENTS (§8.132, ÉLARGIE §8.134) — une pastille, deux régimes
# =========================================================
# DÉFIS ayant quitté la barre, sa pastille « ●N » a migré ICI. Deux signaux, un emplacement, et la
# PRIORITÉ VA À L'ACTION :
#   1. des missions RÉCLAMABLES → « ●N » en or : de l'argent attend le joueur, c'est un geste ;
#   2. sinon, une opération `match`/`bonus` EN COURS → « ● » seul : il se passe quelque chose ;
#   3. sinon, rien.
#
# ⚠️ LE PERSONNAGE GRATUIT NE DÉCLENCHE JAMAIS LA PASTILLE, alors qu'il est perpétuellement actif.
# Une pastille toujours allumée est une pastille morte : au bout de trois jours, l'œil ne la voit
# plus — et le jour où un vrai mutateur tourne, elle n'apprend plus rien. D'où la lecture de
# `active_event` (les `match` seuls, contrat v1) et NON de la liste `active` de v2.
func _on_events_config(data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement de scène.
	var active = data.get("active_event", {})
	_event_active = typeof(active) == TYPE_DICTIONARY and not active.is_empty()
	_update_events_badge()
	_badges_changed()   # §8.133/§8.134.2 — pastille suivie au menu « ••• », ET barre re-mesurée.

func _update_events_badge() -> void:
	if _events_tab_btn == null or not is_instance_valid(_events_tab_btn):
		return
	# Texte COMPOSÉ → auto-traduction désactivée, re-rendu manuel sur locale_changed (même piège que
	# COMPAGNIE : sans ça, l'onglet reste en français après un changement de langue). `●` : même
	# bloc Unicode que les pastilles existantes — aucun emoji, aucun tofu.
	if _missions_claimable > 0:
		_events_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_events_tab_btn.text = "%s ●%d" % [tr("NAV_EVENTS"), _missions_claimable]
		_events_tab_btn.add_theme_color_override("font_color", GOLD)
		return
	if _event_active:
		_events_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_events_tab_btn.text = "%s ●" % tr("NAV_EVENTS")
		_events_tab_btn.add_theme_color_override("font_color", GOLD)
		return
	_events_tab_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_INHERIT
	_events_tab_btn.text = "NAV_EVENTS"
	if active_tab == "events":
		_events_tab_btn.add_theme_color_override("font_color", TEXT)
	else:
		_events_tab_btn.remove_theme_color_override("font_color")


# Session expirée (§AC.5) : purge le token mort, laisse un message et renvoie à l'écran d'auth.
# AUCUN retry — l'utilisateur se reconnecte. NetworkManager n'émet le signal qu'UNE fois.
func _on_session_expired() -> void:
	AuthManager.session_notice = tr("AUTH_SESSION_EXPIRED")
	AuthManager.clear_session()
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")


func _on_locale_changed(_code: String) -> void:
	_update_missions_badge()
	_update_company_badge()
	_update_events_badge()
	# §8.133 — les entrées du menu « ••• » sont des textes composés/traduits à la main comme les
	# pastilles : sans ce re-rendu, elles resteraient dans la langue précédente.
	_refresh_overflow_menu()
	if _overflow_btn != null and is_instance_valid(_overflow_btn):
		_overflow_btn.tooltip_text = tr("NAV_MORE_TOOLTIP")
	# Une langue plus verbeuse peut faire déborder une barre qui tenait : on re-mesure.
	_relayout()
	# Le mini-profil, s'il est ouvert, contient des valeurs formatées → re-rendu.
	if _profile_flyout != null and _profile_flyout.visible:
		_populate_profile_flyout()


# =========================================================
# MINI-PROFIL FLOTTANT (§8.58 — déplacé du menu principal en §8.94)
# =========================================================
# Le Profil n'a plus d'onglet : un clic sur la jauge XP/Coins ouvre ce menu déroulant à la charte
# (résumé express du joueur + CTA vers le profil complet), depuis N'IMPORTE QUEL écran hub.
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

	# --- En-tête : eyebrow JOUEUR + pseudo (rythme eyebrow → valeur §2) ---
	_flyout_body.add_child(_card_title("COMMON_PLAYER_LABEL"))
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

# =========================================================
# CÉLÉBRATIONS DU HUB (§8.122, LOT F) — solde animé + toast de PROMOTION
# =========================================================

# Fait DÉFILER le solde de Coins de la jauge (achat confirmé en boutique). Relais vers la brique
# xp_coins_bar, SEULE à savoir animer ce compteur (le pattern y vit depuis le Rapport Post-Op).
#
# §8.135 (LOT 0) : le solde est aussi RECOPIÉ dans `_profile_data`, qui alimente le mini-profil.
# Sans cela, la jauge disait vrai mais le mini-profil ouvert juste après annonçait encore l'ancien
# solde (deux chiffres contradictoires à l'écran) — il ne se serait recalé qu'au prochain
# `/auth/me`. Le mini-profil est repeint SEULEMENT s'il est ouvert (sinon il le sera à l'ouverture).
func animate_coins(target: int) -> void:
	target = maxi(0, target)
	if not _profile_data.is_empty():
		# Les deux noms : `coins_balance` (canonique) et `coins` (repli historique) sont lus l'un
		# OU l'autre selon les endroits — laisser l'un des deux périmé rouvrirait le même écart.
		_profile_data["coins_balance"] = target
		_profile_data["coins"] = target
	if _xp_bar != null and is_instance_valid(_xp_bar):
		_xp_bar.animate_coins_to(target)
	if _profile_flyout != null and _profile_flyout.visible:
		_populate_profile_flyout()


# Claim de mission réussi (§8.135, LOT 0) : `{ coins_balance, reward_paid, pass_bonus_applied }`.
# On ne re-demande RIEN — le serveur vient de nous donner le solde d'après-claim. Le décompte animé
# et le flash or de `xp_coins_bar` sont ceux qui existent déjà pour la boutique : une seule mise en
# scène de « quelque chose est arrivé aux Coins » dans tout le jeu.
func _on_mission_claimed(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	# Piège JSON float §5 : le solde arrive en float, il sert de valeur affichée → int() obligatoire.
	# Clé absente (réponse d'un serveur antérieur) → on ne touche à rien plutôt que d'afficher 0.
	if not data.has("coins_balance"):
		return
	animate_coins(int(data.get("coins_balance", 0)))


# --- Toast de promotion de division ---------------------------------------------------------
# Clés de la mémoire LOCALE (settings.cfg [progress]) — cf. SettingsManager.get_progress.
const PROGRESS_DIVISION_KEY := "ladder_division"
const PROGRESS_POINTS_KEY := "ladder_points"
const PROMO_TOAST_HOLD := 3.2
const PROMO_TOAST_FADE := 0.45
# Miroir de leaderboard._division_name : seule ÉLITE a besoin d'un libellé traduit (accent).
const DIVISION_LABELS := {"ELITE": "DIVISION_ELITE"}

var _promo_toast: Control = null

# Compare la division du profil (champ DÉRIVÉ `division` de /auth/me) à la dernière connue
# localement. Aucun appel réseau, aucun champ serveur neuf : on exploite ce que la nav a DÉJÀ fetché.
#
# ⚠️ POURQUOI ON COMPARE AUSSI LES POINTS : le seul changement de nom de division ne dit pas dans
# quel SENS on a bougé. Points en hausse + division différente = PROMOTION. Points en baisse (ou
# égaux) = relégation, ou remise à zéro de fin de saison — dans les deux cas on n'affiche RIEN :
# on ne célèbre pas la douleur, et on ne la souligne pas non plus (décision produit).
#
# ⚠️ ÉCHELON (« OR II ») : /auth/me n'expose PAS le tier, seulement la division et les RP bruts.
# On l'affiche donc s'il arrive un jour dans le payload, et on se contente de la division sinon.
# Le DÉRIVER ici imposerait de recopier les seuils du ladder côté client — exactement le genre de
# duplication qui finit par diverger du serveur.
func _maybe_promotion_toast(data: Dictionary) -> void:
	var division := str(data.get("division", ""))
	if division == "":
		return
	var points := int(data.get("season_points", 0))
	var last_division := SettingsManager.get_progress(PROGRESS_DIVISION_KEY)
	var last_points := int(SettingsManager.get_progress(PROGRESS_POINTS_KEY, "0"))
	SettingsManager.set_progress(PROGRESS_DIVISION_KEY, division)
	SettingsManager.set_progress(PROGRESS_POINTS_KEY, str(points))
	# Toute première lecture (nouvelle machine, profil neuf) : on mémorise, on ne célèbre pas.
	if last_division == "":
		return
	if division == last_division or points <= last_points:
		return
	var tier := str(data.get("division_tier", data.get("tier", "")))
	_show_promotion_toast(_division_label(division, tier))

func _division_label(division: String, tier: String) -> String:
	var name_txt: String = tr(str(DIVISION_LABELS[division])) if DIVISION_LABELS.has(division) \
		else division
	if tier == "":
		return name_txt
	return tr("DIVISION_TIER_FMT").format({"division": name_txt, "tier": tier})

# Toast or sous la barre de nav : apparition, maintien, disparition. Non bloquant, non cliquable.
func _show_promotion_toast(label: String) -> void:
	if _promo_toast != null and is_instance_valid(_promo_toast):
		_promo_toast.queue_free()
	var panel := PanelContainer.new()
	panel.name = "PromotionToast"
	panel.top_level = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.058824, 0.07451, 0.094118, 0.96)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = GOLD
	sb.set_content_margin_all(14.0)
	panel.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = tr("TOAST_PROMOTION") % label
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", GOLD)
	panel.add_child(lbl)

	add_child(panel)
	# Positionné APRÈS le premier calcul de taille (sinon `size` vaut zéro et le toast part à
	# gauche de l'écran).
	panel.modulate.a = 0.0
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.position = Vector2((get_viewport_rect().size.x - panel.size.x) * 0.5, NAV_H + 18.0)
	_promo_toast = panel
	AudioManager.play_sfx("promotion")
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, PROMO_TOAST_FADE)
	tw.tween_interval(PROMO_TOAST_HOLD)
	tw.tween_property(panel, "modulate:a", 0.0, PROMO_TOAST_FADE)
	tw.tween_callback(panel.queue_free)


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
	_maybe_promotion_toast(data)
	# Jauge XP + Coins (lecture défensive : clés canoniques + repli sur anciens noms, piège float §5).
	if _xp_bar:
		var level := int(data.get("player_level", data.get("niveau", 1)))
		var xp := int(data.get("current_xp", data.get("experience", 0)))
		var xp_next := int(data.get("xp_to_next_level", _xp_bar._xp_required_for_level(level) - xp))
		var coins := int(data.get("coins_balance", data.get("coins", 0)))
		_xp_bar.set_profile(level, xp, maxi(0, xp_next), coins)
	if _player_name:
		_player_name.text = str(data.get("username", tr("COMMON_PLAYER"))).to_upper()
	# Si le mini-profil est ouvert au moment où le profil (re)charge, on rafraîchit son résumé.
	if _profile_flyout != null and _profile_flyout.visible:
		_populate_profile_flyout()


# =========================================================
# MAÎTRISE DE FACTION (§8.135) — bordure du cadre identité
# =========================================================
# SOBRE, et c'est une décision (§5.6) : le cadre identité prend la bordure de la MEILLEURE maîtrise
# du joueur, SANS son titre. La nav est déjà dense (onglets, pastilles, jauge, ⚙, ⏻) ; y ajouter un
# libellé la ferait déborder — c'est exactement le défaut que §8.133 a coûté cher à corriger. La
# bordure, elle, ne prend aucune place : elle habille un cadre qui existe déjà.
#
# ⚠️ COÛT RÉSEAU MAÎTRISÉ. La donnée vit sur `/profile/stats` (`masteries_summary`, trié rang
# décroissant par le serveur), que la nav n'appelait PAS — elle ne charge que `/auth/me`. On ne la
# demande donc qu'UNE FOIS PAR SESSION (cache STATIQUE) et non à chaque écran : la nav est
# reconstruite à CHAQUE navigation de hub, et un appel par écran pour un ornement aurait multiplié
# le trafic de la barre par deux. Les navigations suivantes repeignent depuis le cache, sans réseau
# — et la valeur se rafraîchit gratuitement dès que le joueur ouvre son Profil (la nav y écoute le
# même signal).
#
# ⛔ Écarté délibérément : ajouter les champs à `/auth/me`. Cette route est sur le chemin critique de
# tout le jeu, et la maîtrise y aurait ajouté la passe de purge lazy (plusieurs requêtes) à chaque
# appel — un prix hors de proportion avec un liseré.
static var _mastery_tier_cache: String = ""
static var _mastery_fetched: bool = false
var _mastery_frame: Control = null


func _apply_mastery_frame(tier: String) -> void:
	if _avatar_frame == null or not is_instance_valid(_avatar_frame):
		return
	if _mastery_frame != null and is_instance_valid(_mastery_frame):
		_mastery_frame.queue_free()
		_mastery_frame = null
	if tier == "":
		return
	_mastery_frame = MasteryBorder.make(tier, 0.0)
	_mastery_frame.custom_minimum_size = Vector2.ZERO
	_mastery_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar_frame.add_child(_mastery_frame)


func _on_profile_stats_for_mastery(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	var rows = data.get("masteries_summary", [])
	# Première ligne = meilleur rang (tri SERVEUR) : la nav ne trie rien, elle prend la tête.
	# Réponse sans le bloc (serveur non redéployé) → "" : le cadre reste nu, jamais d'ornement
	# inventé. Écrasement SYSTÉMATIQUE : perdre une maîtrise (purge) doit retirer la bordure.
	if typeof(rows) == TYPE_ARRAY and not rows.is_empty() and typeof(rows[0]) == TYPE_DICTIONARY:
		_mastery_tier_cache = str(rows[0].get("border_tier", ""))
	else:
		_mastery_tier_cache = ""
	_apply_mastery_frame(_mastery_tier_cache)

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
