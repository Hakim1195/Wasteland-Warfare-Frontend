extends Control

# =========================================================================
# MENU PRINCIPAL — Tableau de bord asymétrique « Warzone Command » (§2 / §8.37)
# =========================================================================
# Refonte du menu d'une liste de boutons vers un lobby AAA (réf. Call of Duty: Warzone) :
#   • Top Bar : plus AUCUNE barre en dur ici (§8.94) — le menu monte le composant PARTAGÉ
#     `top_nav.gd` (`active_tab = "lobby"`), header CANONIQUE de tous les écrans hub : marque,
#     onglets, pastille défis, identité + jauge XP cliquable (mini-profil), ⚙, ⏻. Le menu ne gère
#     donc plus ni onglets, ni jauge, ni mini-profil, ni pop-up « Quitter ».
#   • Centre : HÉROS affiché par priorité (§8.93) — (1) personnage CHOISI dans l'écran Personnages
#     (SettingsManager, persistant), (2) sinon dernière faction JOUÉE (/profile/history),
#     (3) sinon défaut alphabétique du catalogue .tres.
#   • Colonne gauche : mini-classement (top 3) + carte Défis (3 vraies missions serveur, §8.92).
#   • Bas-gauche : gros CTA « START » qui lance le MODE sélectionné.
#   • Bas-centre : cartes de mode Trio(3) / Quad(4) / Five(5) / Exa(6) + Classée(5, classé).
# Règle d'Or §6.1 : VUE pure — navigation via TransitionManager, données via AuthManager /
# NetworkManager (signaux), audio via AudioManager. Aucune logique de jeu brute ici.

# --- Statut (sous le CTA) ---
@export var status_label: Label

# --- Centre : héros de la dernière faction jouée ---
@export var hero_portrait: TextureRect
@export var portrait_placeholder: ColorRect

# --- Bas-gauche : CTA principal ---
@export var mode_eyebrow: Label
@export var play_button: Button

# --- Colonne gauche : widgets ---
@export var leaderboard_content: VBoxContainer
@export var challenges_content: VBoxContainer

# --- Bas-centre : cartes de mode ---
@export var cards_row: HBoxContainer

# Helpers UI partagés de la charte (§2) — encoches, filets, sélecteur de langue, SFX, ghost.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Header CANONIQUE partagé (§8.94) : marque + onglets + pastille défis + identité/jauge + ⚙ + ⏻.
# La jauge XP/Coins (§8.47) est montée PAR la nav — le menu n'en garde aucune copie.
const TopNav = preload("res://scripts/ui/top_nav.gd")
# §8.134 — porteur du `static var target_tab` du hub ÉVÉNEMENTS (onglet d'ouverture), utilisé par
# la carte « DÉFIS EN COURS » et par la carte ÉVÉNEMENT de la colonne latérale.
const EventsScreen = preload("res://scripts/ui/events_screen.gd")
# §8.134 — UN SEUL afficheur de temps dans tout le hub (carte du QG + les 4 onglets du hub) : même
# format, même seconde de bascule, même couleur d'urgence. C'est ça, la cohérence.
const CountdownLabel = preload("res://scripts/ui/countdown_label.gd")
# Héros 3D (SubViewport transparent) — remplace le portrait 2D quand la faction a un .glb riggé.
# Préchargé (pas de class_name, par prudence vis-à-vis du cache d'import, cf. WarzoneUI).
const HeroViewport3DScene = preload("res://scenes/components/hero_viewport_3d.tscn")

# --- Palette canonique (§2, miroir de profile.gd / FRONTEND_INTERFACES.md) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)     # or (récompense / classé)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)     # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)    # acier
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)   # surface secondaire
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)   # rouge (système / quitter)

# --- Factions data-driven (résolution faction_id -> ressource), garde-fous de faction_selection.gd ---
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

# --- Modes de jeu (cartes du bas). count = effectif ; ranked = mode « Classée » (classé, =5). ---
# DÉPENDANCE BACKEND : le gate classé (is_ranked + contrainte ==5 + ladder) n'est pas encore
# appliqué côté serveur ; l'effectif (3-6) passe nativement via max_players (cf. match_config.gd).
const MODES := [
	{"id": "trio", "name_key": "MENU_MODE_TRIO", "count": 3, "ranked": false},
	{"id": "quad", "name_key": "MENU_MODE_QUAD", "count": 4, "ranked": false},
	{"id": "five", "name_key": "MENU_MODE_FIVE", "count": 5, "ranked": false},
	{"id": "exa", "name_key": "MENU_MODE_EXA", "count": 6, "ranked": false},
	{"id": "ranked", "name_key": "MENU_MODE_RANKED", "count": 5, "ranked": true},
]
const DEFAULT_MODE := "trio"

# --- MODES D'ÉQUIPE (MODE ÉQUIPES §8.124) ---
# ⚠️ AUCUNE valeur en dur ici : les playlists viennent du REGISTRE SERVEUR (`GET /squad/playlists`,
# §3.1) et sont ajoutées à la rangée à la réception. Une playlist `enabled: False` n'arrive pas dans
# la réponse → sa carte est ABSENTE, pas grisée. Une carte grisée est une promesse (« bientôt ! ») ;
# une carte absente n'est rien, ce qui est exactement ce qu'on veut d'un mode non ouvert.
# Ces cartes ne passent PAS par MatchConfig : elles mènent à l'écran ESCOUADE, qui possède son
# propre chemin de mise en file (le format est porté par la playlist, pas par un effectif).
var _team_cards: Dictionary = {}

# Nombre de défis mis en avant sur la carte du menu (§8.92) — la liste complète vit dans l'écran Défis.
const MENU_CHALLENGES_MAX := 3

# Police condensée de la charte (§2) pour les nœuds générés en code.
var _font: SystemFont
# Catalogue de factions : id -> ressource FactionData (.tres).
var _factions: Dictionary = {}
# Faction de repli (première triée) si l'historique est vide / l'id est inconnu → centre jamais vide.
var _default_faction_id: String = ""
# Cartes de mode : mode_id -> { "panel": PanelContainer, "sub": Label, "mode": Dictionary }.
var _mode_cards: Dictionary = {}
# Mode actuellement sélectionné (surbrillance + lu par le CTA START).
var _selected_mode: String = DEFAULT_MODE
# Conteneur des lignes du mini-classement (peuplé à la réception des données).
var _lb_rows: VBoxContainer = null
# Dernières entrées de classement reçues (re-rendues au changement de langue — format des victoires).
var _last_lb_entries: Array = []
# --- Carte Défis (§8.92) : conteneur des lignes + dernier payload GET /missions reçu ---
var _challenges_rows: VBoxContainer = null
# Dernier dict {daily, weekly, …} reçu, re-rendu au changement de langue (textes composés).
var _missions_data: Dictionary = {}
# False tant qu'AUCUNE réponse n'est arrivée → la carte reste sur « SYNCHRONISATION… » (jamais de
# mock, et un serveur muet laisse simplement l'état passif).
var _missions_received: bool = false
# Instance du héros 3D, montée une fois dans HeroLayer (le modèle est échangé via set_model).
# Non typée à dessein (appels dynamiques set_model/set_accent — pas de class_name sur le composant).
var _hero3d = null

# Dernière faction JOUÉE (historique) — priorité (2) du héros central (§8.93). Le mini-profil, qui
# l'affichait aussi, vit désormais dans top_nav (§8.94) et refait sa propre lecture.
var _last_faction_id: String = ""

# Statut courant (clé + args), mémorisé pour re-traduction au changement de langue (R4).
var _status_key: String = "MENU_STATUS_LOADING"
var _status_args: Array = []


func _ready() -> void:
	# §8.116 : au retour au QG, on repart d'une intention de match NEUVE (mode + carte). Sans ça, un
	# ancien choix (ou la modalité posée par requeue) traînerait pour la partie suivante. MatchConfig
	# n'était nettoyé nulle part auparavant — on corrige ici (autoload, accès défensif).
	var _mc := get_node_or_null("/root/MatchConfig")
	if _mc != null:
		_mc.clear()
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Catalogue des factions (résolution id -> ressource pour le héros central).
	_load_factions()

	# Entrée d'écran UNIFORME (§8.96) : fondu + léger glissement, identique sur tous les écrans hub.
	WarzoneUI.animate_screen_enter(self)

	# --- CTA START ---
	_style_cta(play_button)
	if play_button: play_button.pressed.connect(_on_play_pressed)

	# --- Cartes de mode (bas-centre) ---
	_build_mode_cards()

	# --- Colonne gauche : widgets ---
	_build_leaderboard_widget()
	_build_challenges_widget()

	# --- Héros central : appliqué IMMÉDIATEMENT (avant réseau) — personnage choisi (§8.93) s'il y en
	# a un, sinon repli faction par défaut ; affiné à la réception de l'historique SI aucun choix. ---
	_apply_hero(_explicit_faction())

	# Encoches biseautées sur les cartes de la colonne gauche (ADN angulaire §2).
	if leaderboard_content: WarzoneUI.add_corner_notches(leaderboard_content.get_parent())
	if challenges_content: WarzoneUI.add_corner_notches(challenges_content.get_parent())

	# --- Audio (R6) : nappe d'ambiance + SFX d'interface (no-op headless). La nav pose ses propres
	# SFX ; ici il ne reste que le CTA START. ---
	AudioManager.start_menu_ambient()
	# §8.122 (LOT C) : RADIO MILITAIRE du QG — boucle diégétique du menu principal SEULEMENT (elle
	# s'arrête d'elle-même dès qu'un sous-écran appelle start_menu_ambient, qui coupe l'ambiance
	# précédente). C'est le QG qui « vit », pas la boutique ni le classement.
	AudioManager.start_hub_ambience()
	WarzoneUI.wire_button_sfx(play_button)

	# Re-traduction des textes FORMATÉS au retour des réglages (R4) — les clés brutes se
	# re-traduisent seules.
	LocaleManager.locale_changed.connect(_on_locale_changed)

	# --- Réseau : on s'ABONNE avant de monter la nav (c'est elle qui déclenche les fetchs). ---
	AuthManager.profile_loaded.connect(_on_profile_loaded)
	AuthManager.auth_failed.connect(_on_auth_failed)
	# Héros central : historique (dernière faction jouée) — priorité (2), cf. _explicit_faction.
	NetworkManager.profile_history_loaded.connect(_on_history_loaded)
	NetworkManager.leaderboard_loaded.connect(_on_leaderboard_loaded)
	# Missions (M2 §8.65) : alimente la carte Défis de la colonne gauche (§8.92), rafraîchie à chaque
	# retour au menu → l'état après un claim dans l'écran Défis est correct sans travail en plus.
	# ⚠️ §8.94 : le menu se contente d'ÉCOUTER — c'est `top_nav` qui appelle fetch_missions() (et
	# fetch_profile_history / get_profile), sur TOUS les écrans hub. Éviter d'ajouter un fetch ici :
	# les deux consommateurs (pastille de la nav, carte du menu) partagent la même réponse.
	NetworkManager.missions_loaded.connect(_on_missions_badge_data)
	# ÉVÉNEMENTS MUTATEURS (§8.132) : même discipline que ci-dessus — le menu ÉCOUTE, c'est
	# `top_nav` qui déclenche `fetch_events()` sur tous les écrans hub. La bannière apparaît quand
	# le serveur répond, et ne s'affiche PAS du tout si rien n'est programmé.
	NetworkManager.events_loaded.connect(_on_events_config)

	_set_status("MENU_STATUS_LOADING")

	# --- PREMIÈRE OPÉRATION (§8.129) : mise en avant du BRIEFING pour un compte qui ne l'a pas
	# encore soldé. Le drapeau vient du SERVEUR et peut arriver APRÈS ce _ready (il descend avec
	# /auth/me), d'où l'abonnement en plus de la lecture immédiate. ---
	AuthManager.tutorial_state_changed.connect(_on_tutorial_state_changed)
	TutorialManager.notify_hub_entered()
	_refresh_briefing_cta()

	# --- Nav PARTAGÉE (§8.94) : header canonique, monté en dernier (au-dessus du Hud). `active_tab`
	# est réglé AVANT add_child (il est lu au _ready du composant). ---
	_mount_top_nav()

	NetworkManager.fetch_leaderboard(3)
	# Le cache peut DÉJÀ être garni (retour au QG depuis un autre écran hub) : on peint sans
	# attendre l'aller-retour, sinon la bannière apparaîtrait avec un temps de retard visible.
	_on_events_config(NetworkManager.events_config)


# =========================================================
# CARTE ÉVÉNEMENT DU QG (§8.132, DÉPLACÉE §8.134) — carte latérale, en tête de colonne
# =========================================================
# Le QG est le seul écran que TOUS les joueurs traversent : c'est là que se joue « je découvre
# qu'il se passe quelque chose ». La bannière §8.132, posée sous la rangée de cartes de mode,
# occupait la largeur de l'écran pour une seule ligne d'information et se lisait comme un bandeau
# publicitaire. Elle devient une CARTE de la colonne latérale, au MÊME gabarit que « TOP JOUEURS »
# et « DÉFIS EN COURS », et en PREMIÈRE position : c'est la plus datée des trois, donc la plus
# urgente à voir.
#
# ⚠️⚠️ CONTRADICTION DU BRIEF, TRANCHÉE PAR LE CODE (règle §8.131). Le chantier demandait une
# « carte latérale DROITE, même colonne que TOP JOUEURS / DÉFIS EN COURS ». Ces deux cartes vivent
# en réalité dans `Hud/Shell/MidRow/LeftColumn` — la colonne de GAUCHE. Les deux exigences sont
# donc incompatibles ; on retient la plus précise et la plus répétée (« MÊME colonne », « EN
# PREMIER dans la colonne »), qui préserve l'unité de la colonne d'information. Déplacer les trois
# cartes à droite reste un geste d'une ligne le jour où Hakim tranche autrement.
#
# ⚠️ AUCUN RE-PARENTAGE, AUCUNE TOUCHE AU `.tscn` : on insère dans `LeftColumn` par
# `move_child`, `challenges_content`/`leaderboard_content` gardent leurs NodePath exportés (piège
# maison — un reparentage casse les `%NomUnique` et les NodePath de scène).
#
# CONTENU = `featured_id`, calculé SERVEUR (§8.134). Le client ne classe RIEN : il cherche l'entrée
# qui porte cet id parmi les actifs puis les à-venir, et l'affiche. Une règle de vedette dupliquée
# ici aurait fini par montrer autre chose que le hub.
#
# Clic → le HUB, à l'onglet correspondant au TYPE de l'événement vedette.
var _event_card: Control = null
var _event_countdown: Node = null


func _on_events_config(data: Dictionary) -> void:
	if not is_inside_tree() or challenges_content == null:
		return
	var column := challenges_content.get_parent().get_parent()   # ChallengesCard -> LeftColumn
	if column == null:
		return

	if _event_card != null and is_instance_valid(_event_card):
		_event_card.queue_free()
		_event_card = null
		_event_countdown = null

	var featured := _featured_event(data)
	if featured.is_empty():
		# Aucune donnée du tout (hors ligne, serveur §8.132 sans bloc v2) : carte d'ATTENTE plutôt
		# que rien. Une carte absente se lit comme « il n'y a jamais rien ici » ; une carte qui dit
		# « SYNCHRONISATION… » se lit comme « ça arrive ». Jamais de contenu inventé (§9.5).
		featured = {"__syncing": true}

	_event_card = _make_event_card(featured)
	column.add_child(_event_card)
	column.move_child(_event_card, 0)   # EN PREMIER dans la colonne (décision produit).
	# Encoches biseautées, comme les deux cartes voisines (ADN angulaire §2) : sans elles, la carte
	# ÉVÉNEMENT jurait dans la colonne — constat de relecture de capture.
	WarzoneUI.add_corner_notches(_event_card)


# Retrouve l'entrée VEDETTE désignée par le serveur. Replis successifs, du plus fidèle au plus
# dégradé : `featured_id` dans les actifs → dans les à-venir → premier actif → `active_event` v1
# (serveur pas encore déployé) → `next_event` v1. Aucune règle de tri n'est réimplémentée ici.
func _featured_event(data: Dictionary) -> Dictionary:
	var featured_id := str(data.get("featured_id", ""))
	var pools: Array = []
	if typeof(data.get("active")) == TYPE_ARRAY:
		pools.append(data.get("active"))
	if typeof(data.get("upcoming")) == TYPE_ARRAY:
		pools.append(data.get("upcoming"))
	if featured_id != "":
		for pool in pools:
			for e in pool:
				var entry := _as_dict(e)
				if str(entry.get("id", "")) == featured_id:
					return entry
	for pool in pools:
		for e in pool:
			var entry := _as_dict(e)
			if not entry.is_empty():
				return entry
	# Repli v1 : un serveur antérieur à §8.134 ne sert pas `events_v2`.
	var active := _as_dict(data.get("active_event", {}))
	if not active.is_empty():
		return active
	return _as_dict(data.get("next_event", {}))


# Onglet du hub à ouvrir pour un type d'événement — miroir des ids de `events_screen.TAB_DEFS`.
func _tab_for_type(type_id: String) -> String:
	match type_id:
		"character":
			return "characters"
		"bonus":
			return "bonus"
		_:
			return "matches"


func _make_event_card(event: Dictionary) -> Control:
	var syncing := bool(event.get("__syncing", false))
	# ACTIF = la fenêtre a déjà commencé. On le déduit de l'epoch de début plutôt que d'un drapeau :
	# la même entrée sert d'« actif » et d'« à venir » selon l'heure qu'il est.
	var starts := int(event.get("starts_at_epoch", 0))
	var is_active := not syncing and starts > 0 and starts <= int(Time.get_unix_time_from_system())
	var accent: Color = GOLD if is_active else ACCENT
	var type_id := str(event.get("type", "match"))

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var st := StyleBoxFlat.new()
	st.bg_color = Color(SURFACE, 0.82)
	st.set_corner_radius_all(0)
	st.set_border_width_all(1)
	st.border_width_left = 3          # après set_border_width_all, sinon écrasé.
	st.border_color = Color(MUTED, 0.6) if syncing else accent
	st.set_content_margin_all(16.0)
	var hover := st.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.12)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", st)
	WarzoneUI.wire_button_sfx(btn)
	btn.pressed.connect(func() -> void:
		EventsScreen.target_tab = _tab_for_type(type_id)
		_go("res://scenes/ui/events.tscn"))

	# Contenu posé PAR-DESSUS le bouton (un Button n'est pas un conteneur de mise en page), en
	# plein cadre et transparent aux clics → tout le pavé reste cliquable.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16.0
	box.offset_top = 12.0
	box.offset_right = -16.0
	box.offset_bottom = -12.0
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	if syncing:
		box.add_child(_event_label(_tr_key("NAV_EVENTS"), 12, MUTED))
		box.add_child(_event_label(_tr_key("COMMON_SYNCING"), 18, MUTED))
		btn.custom_minimum_size = Vector2(0, 92)
		return btn

	# Sur-titre = TYPE (« ÉVÉNEMENT — PARTIES »). C'est lui qui rattache visuellement la carte à
	# l'onglet où le clic va atterrir.
	box.add_child(_event_label(_tr_key(_eyebrow_key(type_id)), 12, accent))
	var title := _event_label(_tr_key(str(event.get("name_key", ""))).to_upper(), 20, TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2                     # 2 lignes MAX, puis ellipsis (gabarit de colonne).
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)

	_event_countdown = CountdownLabel.make(17, accent)
	box.add_child(_event_countdown)
	_event_countdown.set_target(int(event.get("ends_at_epoch", 0)) if is_active else starts,
		"COUNTDOWN_ENDS_IN" if is_active else "COUNTDOWN_STARTS_IN")
	# La fenêtre vient de basculer (début OU fin) : on redemande la configuration au lieu d'afficher
	# un rebours figé. Réponse mémoïsée 60 s côté serveur.
	_event_countdown.expired.connect(func() -> void: NetworkManager.fetch_events())
	btn.custom_minimum_size = Vector2(0, 118)
	return btn


func _eyebrow_key(type_id: String) -> String:
	match type_id:
		"character":
			return "EVENTS_EYEBROW_CHARACTER"
		"bonus":
			return "EVENTS_EYEBROW_BONUS"
		_:
			return "EVENTS_EYEBROW_MATCH"


func _event_label(text: String, font_size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _tr_key(key: String) -> String:
	return String(TranslationServer.translate(key))


func _as_dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


# =========================================================
# NAV PARTAGÉE (§8.94)
# =========================================================
func _mount_top_nav() -> void:
	var nav := TopNav.new()
	nav.active_tab = "lobby"  # ⚠️ AVANT add_child : lu au _ready du composant.
	add_child(nav)


# =========================================================
# HÉROS CENTRAL — dernière faction jouée
# =========================================================
# Faction CHOISIE dans l'écran Personnages (§8.93), priorité (1) du héros affiché. Renvoie "" si
# aucun choix n'a jamais été fait OU si l'id persisté est inconnu du catalogue local (.tres retiré,
# sauvegarde d'une version antérieure) → on retombe alors proprement sur (2) puis (3).
# NOTE : si les factions deviennent VERROUILLÉES côté serveur (rotation/possession, lot M3), c'est
# ICI qu'il faudra revalider que le joueur a encore le droit d'arborer ce héros.
func _explicit_faction() -> String:
	var fid := SettingsManager.get_selected_faction()
	if fid != "" and _factions.has(fid):
		return fid
	return ""

# Réception de l'historique (/profile/history, le plus récent d'abord) : la 1re entrée valide donne
# la DERNIÈRE faction jouée → priorité (2) du héros affiché. Historique vide → on garde le héros de
# repli déjà affiché (compte neuf).
# ⚠️ POINT CRITIQUE (§8.93) : ce handler est ASYNCHRONE et arrive APRÈS le _ready qui a déjà posé le
# personnage choisi — il ne doit donc JAMAIS écraser un choix explicite, sinon la sélection faite
# dans Personnages « clignoterait » puis serait remplacée par la dernière faction jouée.
func _on_history_loaded(entries: Array) -> void:
	var explicit := _explicit_faction()
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			var fid := str(e.get("faction_id", ""))
			if fid != "":
				# Mémorisé DANS TOUS LES CAS : la ligne « faction de prédilection » du mini-profil
				# (§8.58) garde la sémantique « dernière jouée », indépendante du choix explicite.
				_last_faction_id = fid
				if explicit == "":
					_apply_hero(fid)
				return

# Monte (une seule fois) le composant héros 3D dans HeroLayer, au même emplacement que le
# portrait 2D (sous le HUD en verre). Idempotent ; no-op si le portrait n'est pas câblé.
func _ensure_hero3d() -> void:
	if _hero3d != null:
		return
	if hero_portrait == null:
		return
	_hero3d = HeroViewport3DScene.instantiate()
	# Ajouté dans le parent du portrait (HeroLayer) → conserve les ancres plein-cadre du composant
	# et reste DERRIÈRE le HUD (HeroLayer se dessine avant Hud).
	hero_portrait.get_parent().add_child(_hero3d)

# Affiche le héros de la faction `faction_id` (repli faction par défaut si vide/inconnu).
# 3D D'ABORD : si la faction expose un .glb valide, on le monte dans le SubViewport et on masque
# le 2D. Sinon repli sur le portrait 2D, puis placeholder coloré si l'image manque aussi — pattern
# repris de faction_selection.gd:_set_portrait.
func _apply_hero(faction_id: String) -> void:
	var f = _resolve_faction(faction_id)
	var accent: Color = SURFACE
	var model_path := ""
	var img_path := ""
	if f != null:
		if f.get("accent_color") != null:
			accent = f.accent_color
		if f.get("hero_model_path") != null:
			model_path = str(f.get("hero_model_path"))
		if f.get("hero_path") != null:
			img_path = str(f.get("hero_path"))

	# --- Chemin 3D : .glb présent → héros 3D, 2D masqué. ---
	_ensure_hero3d()
	if _hero3d != null and _hero3d.set_model(model_path):
		_hero3d.set_accent(accent)
		_hero3d.visible = true
		if hero_portrait:
			hero_portrait.visible = false
		if portrait_placeholder:
			portrait_placeholder.visible = false
		return

	# --- Repli 2D : pas (encore) de .glb pour cette faction. ---
	if _hero3d != null:
		_hero3d.visible = false
	var tex = null
	if img_path != "" and ResourceLoader.exists(img_path):
		tex = load(img_path)
	if tex != null:
		if hero_portrait:
			hero_portrait.texture = tex
			hero_portrait.visible = true
		if portrait_placeholder:
			portrait_placeholder.visible = false
	else:
		if hero_portrait:
			hero_portrait.visible = false
		if portrait_placeholder:
			portrait_placeholder.visible = true
			portrait_placeholder.color = accent.darkened(0.25)

func _resolve_faction(faction_id: String):
	if faction_id != "" and _factions.has(faction_id):
		return _factions[faction_id]
	if _default_faction_id != "" and _factions.has(_default_faction_id):
		return _factions[_default_faction_id]
	return null


# =========================================================
# CHARGEMENT DES FACTIONS (garde-fous de faction_selection.gd / profile.gd)
# =========================================================
func _load_factions() -> void:
	var paths := _scan_faction_paths()
	if paths.is_empty():
		paths = FALLBACK_PATHS.duplicate()
	var ids := []
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		# Duck-typing : on accepte toute ressource exposant un id (pas de dépendance au class_name).
		if res != null and res.get("id") != null:
			_factions[str(res.id)] = res
			ids.append(str(res.id))
	ids.sort()
	if not ids.is_empty():
		_default_faction_id = str(ids[0])

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


# =========================================================
# CARTES DE MODE (bas-centre) — Trio/Quad/Five/Exa + Classée
# =========================================================
func _build_mode_cards() -> void:
	if cards_row == null:
		return
	for m in MODES:
		var entry := _make_mode_card(m)
		cards_row.add_child(entry["panel"])
		_mode_cards[m["id"]] = entry
	_select_mode(DEFAULT_MODE)
	# MODE ÉQUIPES (§8.124) : les cartes d'équipe s'ajoutent quand le registre serveur répond.
	NetworkManager.team_playlists_loaded.connect(_on_team_playlists_loaded)
	NetworkManager.fetch_team_playlists()


# UNE SEULE carte BATTLE ROYALE — pas une par playlist (§8.125).
#
# POURQUOI ce revirement : cinq cartes d'effectif solo PLUS deux cartes d'équipe faisaient sept
# choix alignés au même niveau visuel, dont deux menaient à un tout autre jeu. Le joueur ne lisait
# pas « voici le mode entre amis », il lisait « voici deux effectifs de plus ». Le Battle Royale
# mérite d'être une DESTINATION, pas une option dans une rangée — d'où une carte PLUS GRANDE, or,
# posée TOUT À DROITE et séparée du reste. Le choix du format (2v2 / 3v3) descend d'un cran : il
# se fait DANS l'écran dédié, où il a du sens et où l'on voit ce qu'il implique.
#
# La carte n'apparaît QUE si le serveur sert au moins une playlist ouverte → serveur non redéployé
# = menu rigoureusement identique à celui d'avant (§9.2).
func _on_team_playlists_loaded(playlists: Dictionary) -> void:
	if not is_inside_tree() or cards_row == null:
		return
	if playlists.is_empty() or _team_cards.has("battle_royale"):
		return
	# Séparateur : la carte BR n'appartient PAS à la rangée d'effectifs, elle la termine.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(28, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cards_row.add_child(spacer)

	var entry := _make_battle_royale_card(playlists)
	cards_row.add_child(entry["panel"])
	_team_cards["battle_royale"] = entry


# Carte BATTLE ROYALE : plus grande (210×160 contre 150×130), liseré OR, double encoche, et un
# sous-titre qui annonce les formats disponibles TELS QUE LE SERVEUR LES DONNE (aucun libellé en
# dur — ouvrir un 2v2v2 ne demandera pas une ligne de client).
func _make_battle_royale_card(playlists: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 160)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _battle_royale_style(false))

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	# Eyebrow — rythme eyebrow → valeur de la charte (§2). AUCUN pictogramme : la carte tire déjà
	# son autorité de sa taille, de son or et de sa position ; un symbole y ajoutait du bruit sans
	# rien dire de plus.
	var eyebrow := Label.new()
	eyebrow.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	eyebrow.text = tr("MENU_MODE_EYEBROW_TEAM")
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", GOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(eyebrow)

	var name_lbl := Label.new()
	name_lbl.text = "MODE_BATTLE_ROYALE"  # clé brute -> auto-traduction
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", GOLD)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_lbl)

	var formats := PackedStringArray()
	var ids := playlists.keys()
	ids.sort()
	for pid in ids:
		formats.append(tr("MODE_" + str(pid).to_upper()))
	var sub := Label.new()
	sub.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	sub.text = " · ".join(formats)
	sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(_on_battle_royale_pressed)
	btn.mouse_entered.connect(func() -> void:
		AudioManager.play_sfx("hover")
		panel.add_theme_stylebox_override("panel", _battle_royale_style(true)))
	btn.mouse_exited.connect(func() -> void:
		panel.add_theme_stylebox_override("panel", _battle_royale_style(false)))
	panel.add_child(btn)

	WarzoneUI.add_corner_notches(panel, 20.0, GOLD)
	return {"panel": panel, "sub": sub, "mode": {"id": "battle_royale", "team": true}}


func _battle_royale_style(hovered: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(16.0)
	sb.bg_color = Color(GOLD, 0.20 if hovered else 0.10)
	sb.set_border_width_all(2)
	sb.border_color = GOLD
	sb.shadow_color = Color(GOLD, 0.55 if hovered else 0.30)
	sb.shadow_size = 16 if hovered else 8
	return sb


# La carte BATTLE ROYALE ne SÉLECTIONNE rien : elle OUVRE l'écran dédié, où le joueur choisit son
# format et forme son escouade. C'est le correctif de parcours du §8.125 — une carte de mode doit
# mener à SON mode, pas à un écran générique.
func _on_battle_royale_pressed() -> void:
	AudioManager.play_sfx("click")
	var mc := get_node_or_null("/root/MatchConfig")
	if mc != null and mc.has_method("set_team_playlist"):
		mc.set_team_playlist("")   # aucun format présélectionné : l'écran dédié fait le choix.
	_go("res://scenes/ui/squad_screen.tscn")

func _make_mode_card(m: Dictionary) -> Dictionary:
	var ranked: bool = m["ranked"]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(150, 130)
	# Cartes à largeur fixe groupées au CENTRE (la rangée CardsRow est en alignment center) — réf. photo
	# Warzone « SELECT TEAM SIZE ». (Avant : EXPAND_FILL → les cartes s'étiraient sur toute la largeur.)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _card_style(false, ranked))

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = m["name_key"]  # clé brute -> auto-traduction (FR/EN/IT)
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", GOLD if ranked else TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_lbl)

	var sub := Label.new()
	sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# Bouton transparent superposé : capte le clic sur toute la carte (le contenu ignore la souris).
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	var mode_id: String = m["id"]
	btn.pressed.connect(func() -> void: _on_mode_card_pressed(mode_id))
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	panel.add_child(btn)

	WarzoneUI.add_corner_notches(panel, 14.0, GOLD if ranked else WarzoneUI.NOTCH_COLOR)

	var entry := {"panel": panel, "sub": sub, "mode": m}
	_apply_mode_sub(entry)
	return entry

# (Re)pose le sous-titre d'une carte (formaté → re-appliqué au changement de langue).
func _apply_mode_sub(entry: Dictionary) -> void:
	var m: Dictionary = entry["mode"]
	var sub: Label = entry["sub"]
	if sub == null:
		return
	if bool(m.get("team", false)):
		return   # carte BATTLE ROYALE : son sous-titre liste les formats, il ne se recalcule pas ici.
	if m["ranked"]:
		sub.text = tr("MENU_MODE_RANKED_SUB")
	else:
		sub.text = tr("MENU_MODE_PLAYERS") % int(m["count"])

func _on_mode_card_pressed(mode_id: String) -> void:
	AudioManager.play_sfx("click")
	_select_mode(mode_id)

func _select_mode(mode_id: String) -> void:
	if not _mode_cards.has(mode_id):
		return
	_selected_mode = mode_id
	for mid in _mode_cards:
		var entry: Dictionary = _mode_cards[mid]
		var ranked: bool = entry["mode"]["ranked"]
		var panel: PanelContainer = entry["panel"]
		panel.add_theme_stylebox_override("panel", _card_style(mid == mode_id, ranked))

func _card_style(selected: bool, ranked: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(14.0)
	var accent: Color = GOLD if ranked else ACCENT
	sb.bg_color = GUNMETAL
	if selected:
		sb.bg_color = Color(accent, 0.16)
		sb.set_border_width_all(2)
		sb.border_color = accent
		sb.shadow_color = Color(accent, 0.45)
		sb.shadow_size = 8
	else:
		sb.set_border_width_all(1)
		sb.border_color = Color(accent, 0.3)
	return sb


# =========================================================
# MINI-CLASSEMENT (colonne gauche) — réutilise /leaderboard (top 3)
# =========================================================
func _build_leaderboard_widget() -> void:
	if leaderboard_content == null:
		return
	leaderboard_content.add_child(_card_title("MENU_TOP_PLAYERS"))
	WarzoneUI.add_filet(leaderboard_content)
	_lb_rows = VBoxContainer.new()
	_lb_rows.add_theme_constant_override("separation", 4)
	leaderboard_content.add_child(_lb_rows)
	var more := Button.new()
	more.text = "MENU_VIEW_ALL"
	more.add_theme_font_override("font", _font)
	more.add_theme_font_size_override("font_size", 13)
	WarzoneUI.apply_ghost_button(more)
	more.pressed.connect(_on_leaderboard_pressed)
	more.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	leaderboard_content.add_child(more)
	_set_lb_message("MENU_WIDGET_LOADING")

# Signal GLOBAL partagé avec l'écran Classement (scènes distinctes, jamais vivantes ensemble) :
# garde défensive si l'émission arrive pendant un changement de scène.
func _on_leaderboard_loaded(entries: Array, _me: Dictionary) -> void:
	if not is_inside_tree():
		return
	_last_lb_entries = entries
	_rebuild_lb_rows()

func _rebuild_lb_rows() -> void:
	if _lb_rows == null:
		return
	_clear(_lb_rows)
	if _last_lb_entries.is_empty():
		_set_lb_message("MENU_WIDGET_EMPTY")
		return
	var n: int = mini(3, _last_lb_entries.size())
	for i in range(n):
		var e = _last_lb_entries[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_lb_rows.add_child(_make_lb_row(i + 1, e))

func _make_lb_row(rank: int, e: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)

	var r := Label.new()
	r.text = "❯ %d" % rank
	r.add_theme_font_override("font", _font)
	r.add_theme_font_size_override("font_size", 14)
	r.add_theme_color_override("font_color", GOLD if rank == 1 else ACCENT)
	r.custom_minimum_size = Vector2(40, 0)
	h.add_child(r)

	# Lecture défensive (clés canoniques + alias historiques), comme leaderboard.gd.
	var u := Label.new()
	u.text = str(e.get("username", "—")).to_upper()
	u.add_theme_font_override("font", _font)
	u.add_theme_font_size_override("font_size", 14)
	u.add_theme_color_override("font_color", TEXT)
	u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	u.clip_text = true
	h.add_child(u)

	var w := Label.new()
	w.text = tr("MENU_WINS_ABBR") % int(e.get("wins", e.get("stats_victoires", 0)))
	w.add_theme_font_override("font", _font)
	w.add_theme_font_size_override("font_size", 14)
	w.add_theme_color_override("font_color", GOLD)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(w)
	return h

func _set_lb_message(key: String) -> void:
	if _lb_rows == null:
		return
	_clear(_lb_rows)
	_lb_rows.add_child(_body(key))


# =========================================================
# CARTE DÉFIS (§8.92) — les VRAIES missions du serveur (GET /missions)
# =========================================================
# Ex-placeholder décoratif (« BIENTÔT DISPONIBLE ») désormais BRANCHÉ : le menu était DÉJÀ abonné à
# NetworkManager.missions_loaded pour la pastille de l'onglet — on consomme maintenant le dict
# complet. VUE pure : aucun appel réseau propre, aucune logique de progression (tout est serveur) ;
# le claim se fait dans l'écran Défis, ici on ne fait qu'AFFICHER et renvoyer vers lui.
# Rendu compact inspiré de missions.gd::_make_row (source de vérité du rendu détaillé).
func _build_challenges_widget() -> void:
	if challenges_content == null:
		return
	challenges_content.add_child(_card_title("MENU_CHALLENGES_TITLE"))
	challenges_content.add_child(_body("MENU_CHALLENGES_SUB"))
	WarzoneUI.add_filet(challenges_content)

	_challenges_rows = VBoxContainer.new()
	_challenges_rows.add_theme_constant_override("separation", 10)
	challenges_content.add_child(_challenges_rows)

	# Pied de carte : renvoie vers l'écran Défis complet (même mécanique que « VOIR TOUT » du
	# mini-classement, et même cible que l'onglet Défis).
	var more := Button.new()
	more.text = "MENU_CHALLENGES_VIEW_ALL"  # clé brute -> auto-traduction
	more.add_theme_font_override("font", _font)
	more.add_theme_font_size_override("font_size", 13)
	WarzoneUI.apply_ghost_button(more)
	more.pressed.connect(_on_missions_pressed)
	more.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	challenges_content.add_child(more)

	_rebuild_challenges_rows()  # état d'attente « ❯ SYNCHRONISATION… » avant la 1re réponse.

# Reçoit le dict complet de GET /missions et re-rend la carte (appelé par _on_missions_badge_data).
func _populate_challenges_widget(data: Dictionary) -> void:
	_missions_data = data
	_missions_received = true
	_rebuild_challenges_rows()

# (Re)construit les lignes. AUCUN mock : tant que le serveur n'a pas répondu (ou s'il ne répond
# jamais), la carte reste sur l'état passif « SYNCHRONISATION… » — pas d'erreur bruyante.
func _rebuild_challenges_rows() -> void:
	if _challenges_rows == null:
		return
	_clear(_challenges_rows)
	if not _missions_received:
		_challenges_rows.add_child(_body("MENU_CHALLENGES_LOADING"))
		return
	var top := _pick_top_challenges(_missions_data)
	if top.is_empty():
		_challenges_rows.add_child(_body("MENU_CHALLENGES_EMPTY"))
		return
	for m in top:
		_challenges_rows.add_child(_make_challenge_row(m))

# Sélection des défis à mettre en avant : fusionne quotidiennes + hebdomadaires, EXCLUT les déjà
# réclamées, puis ordonne (1) réclamables d'abord, (2) en cours par ratio progress/target
# DÉCROISSANT (le plus proche du but en tête), (3) départage stable par id. Renvoie au plus
# MENU_CHALLENGES_MAX entrées.
func _pick_top_challenges(data: Dictionary) -> Array:
	var pool := []
	for section in ["daily", "weekly"]:
		for m in data.get(section, []):
			if typeof(m) != TYPE_DICTIONARY:
				continue
			if bool(m.get("claimed", false)):
				continue
			pool.append(m)
	pool.sort_custom(_challenge_sort)
	return pool.slice(0, mini(MENU_CHALLENGES_MAX, pool.size()))

func _challenge_sort(a: Dictionary, b: Dictionary) -> bool:
	var ca := _is_claimable(a)
	var cb := _is_claimable(b)
	if ca != cb:
		return ca  # les réclamables passent devant.
	var ra := _progress_ratio(a)
	var rb := _progress_ratio(b)
	if not is_equal_approx(ra, rb):
		return ra > rb
	# Départage déterministe (évite un ordre instable entre deux défis à égalité de ratio).
	return str(a.get("mission_id", "")) < str(b.get("mission_id", ""))

func _is_claimable(m: Dictionary) -> bool:
	return bool(m.get("completed", false)) and not bool(m.get("claimed", false))

# Piège JSON §5 : progress/target arrivent en float après parse -> int() avant tout calcul.
func _progress_ratio(m: Dictionary) -> float:
	return float(int(m.get("progress", 0))) / float(maxi(1, int(m.get("target", 1))))

# Ligne compacte : « ❯ NOM » + chip récompense « ◈ N » (or) / barre de progression cyan (or si
# réclamable) + compteur « progress/target » (remplacé par « À RÉCLAMER » quand c'est le cas).
func _make_challenge_row(m: Dictionary) -> Control:
	var cur := int(m.get("progress", 0))
	var goal := maxi(1, int(m.get("target", 1)))
	var reward := int(m.get("reward_coins", 0))
	var claimable := _is_claimable(m)
	var accent: Color = GOLD if claimable else ACCENT

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# --- Ligne 1 : intitulé + chip récompense ---
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	row.add_child(head)

	var name_lbl := Label.new()
	name_lbl.text = "❯ %s" % tr(str(m.get("name_key", "")))
	# Texte COMPOSÉ (chevron + libellé déjà traduit) → jamais ré-auto-traduit (re-rendu manuel au
	# changement de langue via _rebuild_challenges_rows).
	name_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", TEXT if claimable else MUTED)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	head.add_child(name_lbl)

	var chip := Label.new()
	chip.text = "◈ %d" % reward
	chip.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	chip.add_theme_font_override("font", _font)
	chip.add_theme_font_size_override("font_size", 13)
	chip.add_theme_color_override("font_color", GOLD)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(chip)

	# --- Ligne 2 : mini barre de progression + compteur / « À RÉCLAMER » ---
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	row.add_child(foot)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.min_value = 0.0
	bar.max_value = float(goal)
	bar.value = float(cur)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(0)
	var fg := StyleBoxFlat.new()
	fg.bg_color = accent
	fg.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	foot.add_child(bar)

	var counter := Label.new()
	counter.text = tr("MENU_CHALLENGES_CLAIMABLE") if claimable else ("%d/%d" % [cur, goal])
	counter.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	counter.add_theme_font_override("font", _font)
	counter.add_theme_font_size_override("font_size", 12)
	counter.add_theme_color_override("font_color", accent)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(counter)
	return row



# =========================================================
# PROFIL SERVEUR (pseudo / niveau / XP / Coins)
# =========================================================
# Le pseudo et la jauge XP/Coins sont désormais rendus par `top_nav` (§8.94) : le menu ne consomme
# plus le profil que pour sa ligne de STATUT. (Il ÉCOUTE seulement : c'est la nav qui appelle
# AuthManager.get_profile().)
func _on_profile_loaded(_data: Dictionary) -> void:
	_set_status("MENU_STATUS_CONNECTED")

func _on_auth_failed(message: String) -> void:
	_set_status("MENU_STATUS_ERROR", [message])


# =========================================================
# STATUT (re-traduction R4) & NAVIGATION
# =========================================================
func _set_status(key: String, args: Array = []) -> void:
	_status_key = key
	_status_args = args
	if status_label:
		status_label.text = (tr(key) % args) if not args.is_empty() else tr(key)

func _on_locale_changed(_code: String) -> void:
	# Les libellés à clé brute se re-traduisent seuls ; on ré-applique les textes FORMATÉS (status,
	# sous-titres de cartes, lignes de classement) qui ne passent pas par l'auto-traduction.
	_set_status(_status_key, _status_args)
	for mid in _mode_cards:
		_apply_mode_sub(_mode_cards[mid])
	_rebuild_lb_rows()
	# Carte Défis : intitulés composés (« ❯ NOM ») → re-rendu manuel (la pastille « ●N » de l'onglet
	# est, elle, re-rendue par top_nav qui la porte désormais, §8.94).
	_rebuild_challenges_rows()
	# §8.132 : la bannière ÉVÉNEMENT est intégralement composée (nom, description, rebours) →
	# reconstruction complète, sinon elle reste en français après un changement de langue.
	_on_events_config(NetworkManager.events_config)

func _go(path: String) -> void:
	TransitionManager.change_scene(path)

# =========================================================
# PREMIÈRE OPÉRATION — CTA de briefing (§8.129)
# =========================================================
# Un compte neuf tombait de l'authentification Steam au QG, puis dans un draft à dix factions
# asymétriques, sans un mot. On met donc le BRIEFING en avant à la place de la mise en avant du
# START — sans jamais le rendre obligatoire : START reste cliquable, il perd seulement sa
# surbrillance le temps que le briefing soit soldé.
var _briefing_panel: PanelContainer = null

func _refresh_briefing_cta() -> void:
	var show_it: bool = TutorialManager.should_offer_first_operation()
	if show_it and _briefing_panel == null:
		_build_briefing_cta()
	if _briefing_panel != null:
		_briefing_panel.visible = show_it
	if play_button != null:
		# La hiérarchie visuelle a UN seul sommet : quand le briefing est proposé, c'est lui.
		play_button.modulate = Color(1, 1, 1, 0.55) if show_it else Color(1, 1, 1, 1)


func _on_tutorial_state_changed(_done: bool) -> void:
	if is_inside_tree():
		_refresh_briefing_cta()


func _build_briefing_cta() -> void:
	if play_button == null:
		return
	var column := play_button.get_parent()
	if column == null:
		return
	_briefing_panel = PanelContainer.new()
	_briefing_panel.name = "BriefingCta"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(GOLD, 0.10)
	st.set_corner_radius_all(0)
	st.set_border_width_all(1)
	st.border_width_left = 4
	st.border_color = GOLD
	st.set_content_margin_all(16)
	_briefing_panel.add_theme_stylebox_override("panel", st)
	column.add_child(_briefing_panel)
	column.move_child(_briefing_panel, play_button.get_index())
	WarzoneUI.add_corner_notches(_briefing_panel, 14.0, GOLD)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_briefing_panel.add_child(col)

	var eyebrow := Label.new()
	eyebrow.text = "TUTO_CTA_EYEBROW"   # clé brute -> auto-traduction
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", GOLD)
	col.add_child(eyebrow)

	var title := Label.new()
	title.text = "TUTO_CTA_TITLE"
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("eef3f7"))
	col.add_child(title)

	var body := Label.new()
	body.text = "TUTO_CTA_BODY"
	body.add_theme_font_override("font", _font)
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color("8a97a5"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(420, 0)
	col.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var start_btn := Button.new()
	start_btn.text = "TUTO_CTA_START"
	start_btn.add_theme_font_override("font", _font)
	start_btn.add_theme_font_size_override("font_size", 17)
	start_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	WarzoneUI.apply_ghost_button(start_btn)
	start_btn.add_theme_color_override("font_color", GOLD)
	WarzoneUI.wire_button_sfx(start_btn)
	start_btn.pressed.connect(_on_briefing_start_pressed)
	row.add_child(start_btn)

	var known_btn := Button.new()
	known_btn.text = "TUTO_CTA_KNOWN"
	known_btn.add_theme_font_override("font", _font)
	known_btn.add_theme_font_size_override("font_size", 13)
	known_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	WarzoneUI.apply_ghost_button(known_btn)
	known_btn.add_theme_color_override("font_color", Color("8a97a5"))
	WarzoneUI.wire_button_sfx(known_btn)
	known_btn.pressed.connect(_on_briefing_known_pressed)
	row.add_child(known_btn)


func _on_briefing_start_pressed() -> void:
	_set_status("MM_SEARCH_STARTING")
	TutorialManager.start_first_operation()


# « JE CONNAIS LA GUERRE » : CONFIRMATION avant de renoncer — le clic est irréversible (le briefing
# ne sera plus proposé) et il coûte la prime. On le DIT, plutôt que de laisser le joueur le
# découvrir après coup.
func _on_briefing_known_pressed() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var pan := PanelContainer.new()
	pan.custom_minimum_size = Vector2(520, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = GOLD
	st.set_content_margin_all(24)
	pan.add_theme_stylebox_override("panel", st)
	center.add_child(pan)
	WarzoneUI.add_corner_notches(pan, 18.0, GOLD)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pan.add_child(col)

	var t := Label.new()
	t.text = "TUTO_CTA_CONFIRM_TITLE"
	t.add_theme_font_override("font", _font)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", GOLD)
	col.add_child(t)

	var b := Label.new()
	b.text = "TUTO_CTA_CONFIRM_BODY"
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Color("c8cdd6"))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(b)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	var no_btn := Button.new()
	no_btn.text = "TUTO_CTA_CONFIRM_NO"
	no_btn.add_theme_font_override("font", _font)
	no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	WarzoneUI.apply_ghost_button(no_btn)
	WarzoneUI.wire_button_sfx(no_btn)
	no_btn.pressed.connect(func() -> void: dim.queue_free())
	row.add_child(no_btn)

	var yes_btn := Button.new()
	yes_btn.text = "TUTO_CTA_CONFIRM_YES"
	yes_btn.add_theme_font_override("font", _font)
	yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	WarzoneUI.apply_ghost_button(yes_btn)
	yes_btn.add_theme_color_override("font_color", GOLD)
	WarzoneUI.wire_button_sfx(yes_btn)
	yes_btn.pressed.connect(func() -> void:
		dim.queue_free()
		TutorialManager.decline_first_operation()
		# On retire la mise en avant IMMÉDIATEMENT : la confirmation du serveur remettra la même
		# valeur, mais faire patienter le joueur devant un panneau qu'il vient de refuser serait
		# exactement le contraire de ce qu'il a demandé.
		if _briefing_panel != null:
			_briefing_panel.visible = false
		if play_button != null:
			play_button.modulate = Color(1, 1, 1, 1))
	row.add_child(yes_btn)


func _on_play_pressed() -> void:
	# Transporte le mode sélectionné jusqu'à l'écran de RECHERCHE (effectif + intention classée) via
	# MatchConfig — §8.116 : plus de lobby « liste de salles », matchmaking 100 % serveur.
	var m = _mode_def(_selected_mode)
	var mc := get_node_or_null("/root/MatchConfig")
	if mc != null and m != null:
		mc.set_mode(m["id"], int(m["count"]), bool(m["ranked"]))
	_go("res://scenes/ui/search_screen.tscn")

# Cible du pied de la carte Défis (« VOIR TOUT ❯ »). §8.134 : DÉFIS a quitté la barre de navigation
# pour devenir le 4ᵉ onglet du hub ÉVÉNEMENTS — on y va DIRECTEMENT, à l'onglet voulu, plutôt que de
# passer par la coquille de redirection `missions.tscn` (qui reste en ceinture pour les chemins
# legacy). L'onglet cible est posé AVANT le changement de scène : il est lu au `_ready` du hub.
func _on_missions_pressed() -> void:
	EventsScreen.target_tab = "missions"
	_go("res://scenes/ui/events.tscn")

# Réception des missions (§8.92) : le menu n'en tire QUE la carte Défis — la pastille « ●N » de
# l'onglet est portée par top_nav (§8.94), qui écoute le même signal global.
func _on_missions_badge_data(data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement de scène.
	_populate_challenges_widget(data)

# Cible du pied du mini-classement (« VOIR TOUT ») — même écran que l'onglet Classement de la nav.
func _on_leaderboard_pressed() -> void:
	_go("res://scenes/ui/leaderboard.tscn")

func _mode_def(mode_id: String):
	for m in MODES:
		if m["id"] == mode_id:
			return m
	return null


# =========================================================
# FABRIQUES DE NŒUDS / STYLES (charte §2, cohérent avec profile.gd)
# =========================================================
func _card_title(key: String) -> Label:
	var l := Label.new()
	l.text = key  # clé brute -> auto-traduction
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", ACCENT)
	return l

func _body(key: String) -> Label:
	var l := Label.new()
	l.text = key  # clé brute -> auto-traduction
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _style_cta(btn: Button) -> void:
	if btn == null:
		return
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
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", TEXT)


# Vide un conteneur sans laisser de doublons (cf. profile.gd / lobby_screen.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
