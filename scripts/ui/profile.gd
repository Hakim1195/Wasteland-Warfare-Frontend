extends Control

# =========================================================================
# Profil joueur — HUB À ONGLETS (refonte chantiers K→O) — charte « Warzone Command » §2
# =========================================================================
# Écran accessible depuis la nav (onglet JOUEUR) et par la jauge d'XP cliquable.
# Règle d'Or §6.1 : VUE PURE — le SERVEUR calcule, le client formate. Aucun agrégat n'est
# recalculé ici (winrates, places moyennes, totaux : tout arrive prêt à l'emploi), aucune valeur
# n'est écrite en dur (les barèmes de Coins viennent du bloc `constants` de /profile/finance).
#
# Structure : un EN-TÊTE D'IDENTITÉ permanent (joueur + carte DIVISION précise) surmontant
# CINQ onglets — APERÇU · STATISTIQUES · HISTORIQUE · FINANCES · PASS.
#
# Sources réseau (R2 — CONTRAT_RESEAU.md §9.1), via NetworkManager :
#   • GET /profile/stats    → identité, niveau/XP, V/D, tribut, faction favorite, crédits,
#                             + blocs `season` / `factions` / `modes` / `form` (chantier J).
#   • GET /profile/history  → matchs, filtrables (victoires / classées) et paginés.
#   • GET /profile/finance  → livre de comptes Coins + potentiel de gain par personnage.
#   • GET /profile/pass     → Pass : état, avantages, gain réel, objets obtenus.
#
# CHARGEMENT LAZY : stats + historique au `_ready` ; FINANCES et PASS seulement à la PREMIÈRE
# ouverture de leur onglet (une fois — cf. `_loaded_tabs`). L'écran s'ouvre donc sur un seul
# aller-retour.
#
# DÉGRADATION (règle §5 — le VPS n'est pas forcément redéployé) : toute lecture d'un champ neuf a
# un défaut silencieux. Sans bloc `season`, l'en-tête retombe sur l'affichage division LEGACY de
# /auth/me ; sur un 404 de /profile/finance ou /profile/pass, l'onglet affiche « DONNÉES
# INDISPONIBLES » au lieu de planter. L'écran n'est JAMAIS vide.

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var username_value: Label
@export var level_value: Label
@export var xp_bar: ProgressBar
@export var xp_value: Label
@export var coins_slot: HBoxContainer      # badge hexagonal or du solde (construit en code)
@export var division_slot: VBoxContainer   # carte DIVISION (construite en code)
@export var tabs_slot: VBoxContainer       # accueille le TabContainer (construit en code)
@export var status_label: Label

# Helpers UI partagés de la charte « Warzone Command » (§2) — encoches, badge hexagonal, filets.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Header CANONIQUE partagé (§8.94).
const TopNav = preload("res://scripts/ui/top_nav.gd")
# §8.126 — catalogue d'emblèmes (placeholders procéduraux tant qu'aucun asset n'est déposé) et écran
# Compagnie (porteur du `static var target_tag` — même mécanique que `public_profile`, §8.107).
const CompanyEmblems = preload("res://scripts/ui/company_emblems.gd")
const CompanyScreen = preload("res://scripts/ui/company_screen.gd")

# --- Palette canonique (§2) — AUCUNE couleur hors charte ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)    # or (victoire / récompense)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (eyebrow / muet)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)  # surface secondaire
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)  # rouge (défaite / dépense)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1) # fond des badges hexagonaux

# Couleurs des divisions — MIROIR de leaderboard.gd (même rang, même couleur sur les deux écrans).
const DIVISION_COLORS := {
	"BRONZE": Color("cd7f32"),
	"ARGENT": Color("c0c0c0"),
	"OR": Color(0.878431, 0.698039, 0.286275, 1),
	"PLATINE": Color("9adfea"),
	"ELITE": Color(0.211765, 0.772549, 0.85098, 1),
}
# Libellés i18n des divisions — MIROIR EXACT de leaderboard.gd. Seule ÉLITE est mappée : son id
# réseau est ASCII (« ELITE ») alors que le rendu porte l'accent. BRONZE/ARGENT/OR/PLATINE sont
# déjà corrects tels quels et n'ont PAS de clé — leur en inventer une afficherait le nom de la clé
# à l'écran (tr() sur une clé absente renvoie la clé elle-même).
const DIVISION_LABELS := {"ELITE": "DIVISION_ELITE"}

# Libellés i18n des CARTES (§8.107) : le serveur ne renvoie que l'id ASCII du registre G5 (R4 —
# aucun texte affichable côté réseau), le client le résout ici. Même repli défensif que les
# divisions : un id inconnu (carte ajoutée par un serveur plus récent) s'affiche tel quel plutôt
# que sous forme de clé i18n crue.
const MAP_LABELS := {
	"classic_42": "MAP_CLASSIC_LABEL",
	"skirmish_atlantic": "MAP_ATLANTIC_LABEL",
}

# --- Onglets (index = ordre d'ajout au TabContainer) ---
const TAB_OVERVIEW := 0
const TAB_STATS := 1
const TAB_HISTORY := 2
const TAB_FINANCE := 3
const TAB_PASS := 4

# Tailles de page / de série — constantes NOMMÉES (aucune valeur en dur, §6).
const HISTORY_PAGE := 15     # lignes par page de l'onglet HISTORIQUE (« AFFICHER PLUS »)
const FINANCE_PAGE := 20     # transactions par page de l'onglet FINANCES
const RP_SERIES_LEN := 20    # points de la courbe « RP cumulés » (dernières classées)
const FORM_SQUARE := 18.0    # côté d'un carré de la bande de forme

# Factions data-driven (resources/factions/*.tres) — mêmes garde-fous que faction_selection.gd.
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

# --- État : statistiques de campagne (peuplées par GET /profile/stats, lecture défensive) ---
# Valeurs NEUTRES par défaut : affichées tant que la réponse serveur n'est pas arrivée, puis
# écrasées par les vraies données (jamais de chiffres factices).
var _games_played: int = 0
var _wins: int = 0
var _losses: int = 0
var _heaviest_toll: int = 0
# §8.123 — compteur de RÉPUTATION à vie (pactes de non-agression rompus). 0 = aucun, OU serveur
# non redéployé : la ligne est masquée dans les deux cas.
var _pacts_broken: int = 0
var _favorite_faction_id: String = ""
var _level: int = 1
var _xp: int = 0
var _xp_max: int = 1
var _credits: int = 0
# Blocs du chantier J (vides tant que le serveur ne les fournit pas — repli legacy assuré).
var _season: Dictionary = {}
var _factions_stats: Array = []
var _modes: Dictionary = {}
var _form: Array = []
# §8.107 — agrégat PAR CARTE (vide sur un serveur antérieur : la vue affiche son état vide).
var _maps_stats: Array = []
# §8.126 — COMPAGNIE d'appartenance ({tag, name, emblem_id}) ; {} = SANS COMPAGNIE.
var _company: Dictionary = {}

# Repli LEGACY de la carte division : division + points lus de /auth/me (utilisé UNIQUEMENT si le
# bloc `season` de /profile/stats est absent, c.-à-d. serveur non redéployé).
var _legacy_season_points: int = 0
var _legacy_division: String = ""

# --- État des onglets ---
var _tabs: TabContainer = null
# Onglets déjà chargés (index -> true) : le fetch différé n'est émis QU'UNE fois par onglet.
var _loaded_tabs: Dictionary = {}
# Vue de l'onglet STATISTIQUES : "hero" (par personnage, défaut), "mode" ou "map" (§8.107).
var _stats_view: String = "hero"
# Filtre de l'onglet HISTORIQUE : "wins" (défaut — demande produit), "all" ou "ranked".
var _history_filter: String = "wins"
var _history_rows: Array = []          # entrées accumulées (pagination « AFFICHER PLUS »)
var _history_end_reached: bool = false
# Série des ΔRP des dernières parties CLASSÉES (courbe de progression de l'onglet STATISTIQUES).
var _rp_series: Array = []
# Requêtes d'historique EN VOL, mémorisées pour router les réponses : le signal est GLOBAL et
# plusieurs consommateurs coexistent (l'onglet HISTORIQUE, la courbe RP, et la nav partagée qui
# demande AUSSI un historique de son côté). On compare la requête échoée à celle qu'on a émise —
# se fier au seul ordre d'arrivée rangerait une réponse dans la mauvaise vue.
var _pending_history_req: Dictionary = {}
var _pending_rp_req: Dictionary = {}

# --- État FINANCES / PASS ---
var _finance: Dictionary = {}
var _finance_entries: Array = []
var _finance_end_reached: bool = false
var _finance_available: bool = true     # false = 404 (serveur non redéployé) → état « indisponible »
var _pass: Dictionary = {}
var _pass_available: bool = true

# Conteneurs de contenu des onglets (peuplés/vidés par les `_populate_*`).
var _overview_box: VBoxContainer = null
var _stats_box: VBoxContainer = null
var _history_box: VBoxContainer = null
var _finance_box: VBoxContainer = null
var _pass_box: VBoxContainer = null

# id de faction -> { name, color } (chargé des .tres).
var _factions: Dictionary = {}

# Police condensée de la charte (§2), construite en code pour les nœuds générés dynamiquement.
var _font: SystemFont


func _ready():
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Nav PARTAGÉE (§8.94) — onglet JOUEUR actif ; ÉCHAP (nav) remplace l'ex-bouton RETOUR.
	# ⚠️ active_tab réglé AVANT add_child (lu au _ready du composant).
	var nav := TopNav.new()
	nav.active_tab = "profile"
	add_child(nav)
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Entrée d'écran UNIFORME (§8.96) : fondu + léger glissement, identique sur tous les écrans hub.
	WarzoneUI.animate_screen_enter(self)
	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	_style_xp_bar()
	_load_factions()
	_build_tabs()

	# --- Réseau ---
	NetworkManager.profile_stats_loaded.connect(_on_profile_loaded)
	# ⚠️ On écoute la variante qui ÉCHOIE SA REQUÊTE, jamais le signal legacy : celui-ci est aussi
	# consommé par la nav partagée (montée sur CET écran), et rien n'y distingue une liste filtrée.
	NetworkManager.profile_history_page_loaded.connect(_on_history_page_loaded)
	NetworkManager.profile_finance_loaded.connect(_on_finance_loaded)
	NetworkManager.profile_pass_loaded.connect(_on_pass_loaded)
	# Chantier U : personnage GRATUIT de la semaine + crédit de parties (GET /shop/rotation).
	NetworkManager.shop_rotation_loaded.connect(_on_rotation_loaded)

	NetworkManager.fetch_profile_stats()
	NetworkManager.fetch_shop_rotation()
	_fetch_history(true)
	# Saison — REPLI LEGACY uniquement : si /profile/stats ne porte pas de bloc `season` (serveur
	# non redéployé), la division vient encore de /auth/me. Sur un serveur à jour, `season` gagne.
	AuthManager.profile_loaded.connect(_on_me_loaded)
	AuthManager.get_profile()

	# Changement de langue (§8.102) : tout le contenu est généré en code avec des textes déjà
	# résolus par tr() → re-render complet (les labels de la scène, à clé brute, se re-traduisent).
	LocaleManager.locale_changed.connect(func(_code: String) -> void: _refresh_all())

	_refresh_all()
	_set_status(tr("COMMON_SYNCING"))


# =========================================================
# RÉSEAU — lecture DÉFENSIVE (le serveur fait foi, tout champ absent a un défaut neutre)
# =========================================================
func _on_profile_loaded(data: Dictionary):
	if data.has("username"):
		_set_username(str(data["username"]))
	_level = _read_int(data, ["niveau", "level"], _level)
	_xp = _read_int(data, ["xp", "experience", "exp", "points"], _xp)
	_xp_max = _read_int(data, ["xp_max", "xp_next", "next_level_xp", "niveau_suivant_xp"], _xp_max)
	_games_played = _read_int(data, ["parties_jouees", "games_played", "matches"], _games_played)
	_wins = _read_int(data, ["victoires", "wins"], _wins)
	_losses = _read_int(data, ["defaites", "losses"], _losses)
	_heaviest_toll = _read_int(data, ["tribut", "plus_lourd_tribut", "heaviest_toll", "units_lost"], _heaviest_toll)
	# §8.123 — PACTES ROMPUS à vie. Clé ADDITIVE : absente d'un serveur non redéployé → 0, et la
	# ligne se masque d'elle-même (on n'annonce jamais « 0 pacte rompu » à qui n'a jamais pu en
	# signer un : ce serait accuser le joueur d'une vertu qu'on ne sait pas mesurer).
	_pacts_broken = _read_int(data, ["pacts_broken"], _pacts_broken)
	_credits = _read_int(data, ["credits", "coins"], _credits)

	for key in ["faction_favorite", "favorite_faction", "faction", "main_faction"]:
		if data.has(key) and str(data[key]) != "":
			_favorite_faction_id = str(data[key])
			break

	# Blocs du chantier J — chacun ABSENT sur un serveur antérieur : on garde alors le défaut vide,
	# et chaque vue affiche son état vide propre (jamais une erreur).
	if typeof(data.get("season")) == TYPE_DICTIONARY:
		_season = data["season"]
	if typeof(data.get("factions")) == TYPE_ARRAY:
		_factions_stats = data["factions"]
	if typeof(data.get("modes")) == TYPE_DICTIONARY:
		_modes = data["modes"]
	if typeof(data.get("form")) == TYPE_ARRAY:
		_form = data["form"]
	if typeof(data.get("maps")) == TYPE_ARRAY:
		_maps_stats = data["maps"]
	# §8.126 — COMPAGNIE : `null` (ou clé absente d'un serveur non redéployé) = SANS COMPAGNIE, un
	# ÉTAT affichable et non une donnée manquante. On écrase donc systématiquement, y compris par
	# {} — quitter sa compagnie doit faire disparaître la carte au rafraîchissement suivant, sans
	# quoi le Profil garderait éternellement l'appartenance d'hier.
	var comp = data.get("company")
	_company = comp if typeof(comp) == TYPE_DICTIONARY else {}

	_refresh_all()
	_set_status(tr("PROFILE_STATUS_LOADED"))


func _on_me_loaded(data: Dictionary) -> void:
	# Repli LEGACY (cf. _ready) : conservé pour qu'un serveur non redéployé continue d'afficher une
	# division. Dès que le bloc `season` existe, il prime — _build_division_card l'ignore alors.
	_legacy_season_points = _read_int(data, ["season_points"], _legacy_season_points)
	_legacy_division = str(data.get("division", _legacy_division))
	_build_division_card()


func _on_history_page_loaded(entries: Array, request: Dictionary) -> void:
	# Routage par comparaison à la requête ÉMISE (cf. _pending_history_req / _pending_rp_req).
	if request == _pending_rp_req:
		_pending_rp_req = {}
		_rp_series.clear()
		# Le serveur renvoie du plus RÉCENT au plus ancien ; la courbe se lit dans le sens du temps.
		for i in range(entries.size() - 1, -1, -1):
			var e = entries[i]
			if typeof(e) == TYPE_DICTIONARY:
				_rp_series.append(int(e.get("rp_delta", 0)))
		if _stats_view == "hero" or _stats_view == "mode":
			_populate_stats_tab()
		return

	if request != _pending_history_req:
		return  # réponse d'un AUTRE consommateur (nav partagée) — pas la nôtre.
	_pending_history_req = {}

	if int(request.get("offset", 0)) == 0:
		_history_rows.clear()
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY:
			_history_rows.append(e)
	# Page incomplète = fin de liste (le bouton « AFFICHER PLUS » disparaît).
	_history_end_reached = entries.size() < int(request.get("limit", HISTORY_PAGE))
	_populate_history_tab()


func _on_finance_loaded(data: Dictionary, request: Dictionary) -> void:
	# Dict VIDE = route absente (404, serveur non redéployé) → état « DONNÉES INDISPONIBLES ».
	_finance_available = not data.is_empty()
	if _finance_available:
		_finance = data
		var entries = data.get("entries", [])
		if typeof(entries) != TYPE_ARRAY:
			entries = []
		if int(request.get("offset", 0)) == 0:
			_finance_entries.clear()
		for e in entries:
			if typeof(e) == TYPE_DICTIONARY:
				_finance_entries.append(e)
		_finance_end_reached = entries.size() < int(request.get("limit", FINANCE_PAGE))
	_populate_finance_tab()


func _on_pass_loaded(data: Dictionary) -> void:
	_pass_available = not data.is_empty()
	if _pass_available:
		_pass = data
	_populate_pass_tab()


# Lit la première clé présente d'une liste et la convertit en int (piège float JSON §5, CLAUDE.md).
func _read_int(data: Dictionary, keys: Array, fallback: int) -> int:
	for k in keys:
		if data.has(k):
			return int(data[k])
	return fallback


func _fetch_history(reset: bool) -> void:
	var offset := 0 if reset else _history_rows.size()
	var wins_only := _history_filter == "wins"
	var ranked_only := _history_filter == "ranked"
	_pending_history_req = {"limit": HISTORY_PAGE, "offset": offset,
							"wins_only": wins_only, "ranked_only": ranked_only}
	NetworkManager.fetch_profile_history(HISTORY_PAGE, offset, wins_only, ranked_only)


# =========================================================
# RENDU GLOBAL
# =========================================================
func _refresh_all() -> void:
	if username_value and username_value.text.strip_edges() in ["", "—"]:
		# Le pseudo arrive via /auth/me ; on n'écrase pas s'il a déjà été poussé. Repli NEUTRE
		# « Joueur » (COMMON_PLAYER) — COMMON_PLAYER_LABEL est un LIBELLÉ d'eyebrow, pas un nom.
		_set_username(AuthManager.username if AuthManager.username != "" else tr("COMMON_PLAYER"))
	_update_level_xp()
	_build_coins_badge()
	_build_division_card()
	_refresh_tab_titles()
	_populate_overview_tab()
	_populate_stats_tab()
	_populate_history_tab()
	_populate_finance_tab()
	_populate_pass_tab()


func _set_username(name: String) -> void:
	if username_value:
		username_value.text = name.to_upper()


func _update_level_xp() -> void:
	if level_value:
		level_value.text = str(_level)
	if xp_bar:
		xp_bar.max_value = maxi(_xp_max, 1)
		xp_bar.value = clampi(_xp, 0, _xp_max)
	if xp_value:
		xp_value.text = tr("PROFILE_XP_FORMAT") % [_xp, _xp_max]


# Solde Coins de l'en-tête : badge hexagonal OR — MÊME convention que la boutique (le nombre seul
# dans l'hexagone, sans symbole monétaire : aucun glyphe exotique, donc aucun risque de « tofu »).
func _build_coins_badge() -> void:
	if coins_slot == null:
		return
	_clear(coins_slot)
	coins_slot.add_child(_eyebrow(tr("PROFILE_FIN_BALANCE")))
	coins_slot.add_child(WarzoneUI.make_hex_badge(
		_format_thousands(_credits), _font, 15, GOLD, GUNMETAL, 54))


# =========================================================
# CARTE DIVISION (en-tête, permanente) — chantier K.2
# =========================================================
# Source PRIORITAIRE : bloc `season` de /profile/stats (division + échelon + RP + rang mondial +
# fin de saison). REPLI LEGACY : division/points de /auth/me si le bloc est absent. Dernier repli :
# rien du tout → carte masquée (l'en-tête reste lisible, l'écran n'est jamais « cassé »).
func _build_division_card() -> void:
	if division_slot == null:
		return
	_clear(division_slot)

	var division := str(_season.get("division", ""))
	var tier := str(_season.get("tier", ""))
	var rp := int(_season.get("rp", 0))
	var has_season := division != ""
	if not has_season:
		# Repli legacy : on n'a que la division et les points, sans échelon ni rang mondial.
		division = _legacy_division
		rp = _legacy_season_points
	if division == "":
		return  # ni bloc season, ni /auth/me : rien à afficher (jamais de carte vide).

	var accent: Color = DIVISION_COLORS.get(division, MUTED)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	division_slot.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	v.add_child(_eyebrow(tr("PROFILE_STAT_DIVISION")))

	# Ligne haute : badge hexagonal à la couleur de division + libellé « OR II » + RP en or.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	# Initiale de la division dans le badge : lettre unique, toujours rendue, jamais un glyphe exotique.
	top.add_child(WarzoneUI.make_hex_badge(
		_division_name(division).substr(0, 1), _font, 20, accent, GUNMETAL, 52))

	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 0)
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(labels)
	var name_label := Label.new()
	name_label.text = _division_label(division, tier)
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", accent)
	labels.add_child(name_label)
	var rp_label := Label.new()
	rp_label.text = tr("PROFILE_RP_FORMAT") % _format_thousands(rp)
	rp_label.add_theme_font_override("font", _font)
	rp_label.add_theme_font_size_override("font_size", 16)
	rp_label.add_theme_color_override("font_color", GOLD)
	labels.add_child(rp_label)

	# Progression DANS l'échelon — masquée si `tier_span == 0` : c'est le cas en ÉLITE (ladder
	# ouvert, sans échelon) ET en repli legacy. Aucune distinction à faire côté rendu.
	var span := int(_season.get("tier_span", 0))
	if span > 0:
		var in_tier := clampi(int(_season.get("rp_in_tier", 0)), 0, span)
		var bar := _make_ratio_bar(int(round(100.0 * in_tier / span)), accent, 0.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(bar)
		var span_label := _mini(tr("PROFILE_TIER_PROGRESS_FMT") % [in_tier, span], 12, MUTED)
		span_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_child(span_label)

	# Pied : rang mondial + fin de saison (chacun masqué s'il est inconnu — aucune invention).
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	var global_rank := int(_season.get("global_rank", 0))
	foot.add_child(_mini(tr("PROFILE_GLOBAL_RANK") + "  "
		+ ("#" + _format_thousands(global_rank) if global_rank > 0 else "—"), 14,
		TEXT if global_rank > 0 else MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var days := _days_until(str(_season.get("season_ends_at", "")))
	if days >= 0:
		foot.add_child(_mini(tr("PROFILE_SEASON_ENDS_FMT") % days, 14, MUTED))


# =========================================================
# ONGLETS — construction, commutation, chargement différé (chantier K.3/K.4)
# =========================================================
func _build_tabs() -> void:
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_tabs(_tabs)
	tabs_slot.add_child(_tabs)

	_overview_box = _add_tab_page("TabOverview")
	_stats_box = _add_tab_page("TabStats")
	_history_box = _add_tab_page("TabHistory")
	_finance_box = _add_tab_page("TabFinance")
	_pass_box = _add_tab_page("TabPass")
	_refresh_tab_titles()

	_tabs.tab_changed.connect(_on_tab_changed)
	# L'onglet APERÇU est ouvert d'entrée : ses données arrivent avec /profile/stats (aucun fetch).
	_loaded_tabs[TAB_OVERVIEW] = true
	_loaded_tabs[TAB_HISTORY] = true   # première page demandée au _ready


func _add_tab_page(id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = id
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	return page


func _refresh_tab_titles() -> void:
	if _tabs == null:
		return
	var keys := ["PROFILE_TAB_OVERVIEW", "PROFILE_TAB_STATS", "PROFILE_TAB_HISTORY",
				 "PROFILE_TAB_FINANCE", "PROFILE_TAB_PASS"]
	for i in range(mini(keys.size(), _tabs.get_tab_count())):
		_tabs.set_tab_title(i, tr(keys[i]))


func _on_tab_changed(idx: int) -> void:
	AudioManager.play_sfx("click")
	_ensure_tab_loaded(idx)


# Chargement DIFFÉRÉ : une seule requête par onglet, à sa PREMIÈRE ouverture.
func _ensure_tab_loaded(idx: int) -> void:
	if _loaded_tabs.get(idx, false):
		return
	_loaded_tabs[idx] = true
	match idx:
		TAB_STATS:
			# Courbe de progression : ΔRP des dernières parties CLASSÉES. On réutilise l'endpoint
			# d'historique (aucune route dédiée) — d'où le routage par requête échoée.
			_pending_rp_req = {"limit": RP_SERIES_LEN, "offset": 0,
							   "wins_only": false, "ranked_only": true}
			NetworkManager.fetch_profile_history(RP_SERIES_LEN, 0, false, true)
		TAB_FINANCE:
			NetworkManager.fetch_profile_finance(FINANCE_PAGE, 0)
		TAB_PASS:
			NetworkManager.fetch_profile_pass()


# =========================================================
# ONGLET 1 — APERÇU (chantier K.5)
# =========================================================
func _populate_overview_tab() -> void:
	if _overview_box == null:
		return
	_clear(_overview_box)

	_overview_box.add_child(_eyebrow(tr("PROFILE_STATS_HEADER")))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview_box.add_child(grid)

	var ratio := 0
	if _wins + _losses > 0:
		ratio = int(round(100.0 * float(_wins) / float(_wins + _losses)))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_GAMES"), str(_games_played), TEXT))
	grid.add_child(_make_stat_card(tr("COMMON_WINS"), str(_wins), GOLD))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_LOSSES"), str(_losses), DANGER))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_RATIO"), "%d%%" % ratio, ACCENT))
	grid.add_child(_make_stat_card(tr("PROFILE_STAT_TOLL"), _format_thousands(_heaviest_toll), MUTED))
	# Faction favorite : déplacée ici en carte (elle quittait l'en-tête, désormais réservé à
	# l'identité et à la division). Teintée de la couleur SIGNATURE de la faction.
	var fav_info: Dictionary = _factions.get(_favorite_faction_id, {})
	var fav_name := str(fav_info.get("name", _favorite_faction_id)).to_upper()
	var fav_color: Color = fav_info.get("color", ACCENT) if not fav_info.is_empty() else MUTED
	grid.add_child(_make_stat_card(tr("PROFILE_FAVORITE_FACTION"),
		fav_name if fav_name != "" else "—", fav_color))

	# --- COMPAGNIE (§8.126) : la carte d'appartenance, juste sous les statistiques de campagne. ---
	# Placée AVANT la bande de forme, qui sort de la fonction par un `return` quand l'historique est
	# vide : la reléguer après la masquerait pour un joueur neuf — précisément celui qu'une
	# compagnie retient le mieux.
	_overview_box.add_child(_spacer(8))
	_overview_box.add_child(_build_company_card())

	# --- PERSONNAGE GRATUIT DE LA SEMAINE (chantier U) : jauge de parties restantes. -------------
	# Placé AVANT la bande de forme — celle-ci sort de la fonction par un `return` quand
	# l'historique est vide, ce qui masquerait le widget pour un nouveau joueur (précisément celui
	# à qui la rotation s'adresse le plus).
	var freeplay := _build_freeplay_card()
	if freeplay != null:
		_overview_box.add_child(_spacer(8))
		_overview_box.add_child(freeplay)

	# --- Bande de FORME : les 10 derniers résultats, le plus récent à DROITE. ---
	_overview_box.add_child(_spacer(8))
	_overview_box.add_child(_eyebrow(tr("PROFILE_FORM_TITLE")))
	if _form.is_empty():
		_overview_box.add_child(_muted_note(tr("PROFILE_HISTORY_EMPTY")))
		return
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 5)
	_overview_box.add_child(strip)
	# Le serveur renvoie du plus RÉCENT au plus ancien → on parcourt à l'envers pour que le dernier
	# match tombe à droite (sens de lecture d'une frise temporelle).
	for i in range(_form.size() - 1, -1, -1):
		var e = _form[i]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		strip.add_child(_make_form_square(bool(e.get("win", false)), bool(e.get("is_ranked", false))))


# =========================================================
# COMPAGNIE (§8.126) — carte d'appartenance de l'onglet APERÇU
# =========================================================
# DEUX états, et le premier compte autant que le second : « SANS COMPAGNIE » n'est pas un trou dans
# l'écran, c'est l'invitation à en rejoindre une (le seul endroit du jeu qui le propose).
#
# ⚠️ La carte ne montre NI score NI roster. Ce n'est pas de la place manquante : les faire venir ici
# obligerait `/profile/stats` à recalculer un agrégat de compagnie à chaque ouverture du Profil, et
# surtout créerait une DEUXIÈME source du score — la divergence exacte que le §8.106 a coûté cher à
# corriger. Le détail vit derrière le bouton OUVRIR, servi par `GET /company/mine`.
func _build_company_card() -> PanelContainer:
	var has := not _company.is_empty()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(ACCENT if has else MUTED))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(_eyebrow(tr("COMPANY_TITLE")))
	# Panneau explicatif « qu'est-ce qu'une compagnie » = modal calqué sur le Classement
	# (référence maison actée §8.125). Toujours présent, y compris quand on en a une : c'est aussi
	# là qu'on relit la règle du cooldown avant de partir.
	head.add_child(WarzoneUI.make_info_badge(self, tr("COMPANY_EXPLAIN_TITLE"),
		tr("COMPANY_EXPLAIN_BODY"), _font, 20.0))

	if not has:
		v.add_child(_mini(tr("COMPANY_NONE"), 20, MUTED))
		v.add_child(_muted_note(tr("COMPANY_NONE_HINT")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		v.add_child(row)
		row.add_child(_company_button(tr("COMPANY_CREATE")))
		row.add_child(_company_button(tr("COMPANY_JOIN")))
		return card

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	v.add_child(line)
	line.add_child(CompanyEmblems.make_badge(int(_company.get("emblem_id", 0)), 48.0, _font))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 0)
	line.add_child(titles)
	titles.add_child(_mini("[%s]" % str(_company.get("tag", "")), 15, ACCENT))
	titles.add_child(_mini(str(_company.get("name", "")).to_upper(), 20, TEXT))
	var open_btn := _company_button(tr("COMPANY_OPEN"))
	open_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(open_btn)
	return card


# Les trois boutons de la carte mènent au MÊME écran : c'est lui qui porte la création, l'adhésion
# et la gestion. Un formulaire de création dans le Profil aurait été un deuxième endroit à maintenir.
func _company_button(text: String) -> Button:
	var btn := Button.new()
	btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	btn.text = text
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 13)
	btn.custom_minimum_size = Vector2(150, 34)
	WarzoneUI.apply_ghost_button(btn)
	WarzoneUI.wire_button_feedback(btn)
	btn.pressed.connect(_open_company_screen)
	return btn


func _open_company_screen() -> void:
	# `target_tag` vide = MA compagnie (l'écran bascule alors sur `GET /company/mine`).
	CompanyScreen.target_tag = ""
	TransitionManager.change_scene("res://scenes/ui/company_screen.tscn")


# =========================================================
# PERSONNAGE GRATUIT DE LA SEMAINE (chantier U)
# =========================================================
# Données servies par GET /shop/rotation (auth OPTIONNELLE) : le personnage offert, le plafond de
# parties gratuites et — pour un joueur authentifié seulement — son crédit restant.
var _rot_faction_id: String = ""
var _rot_rotates_at: String = ""
var _rot_games_left: int = -1
var _rot_games_max: int = -1


func _on_rotation_loaded(data: Dictionary) -> void:
	var ids = data.get("free_faction_ids", [])
	_rot_faction_id = str(ids[0]) if typeof(ids) == TYPE_ARRAY and not ids.is_empty() else ""
	_rot_rotates_at = str(data.get("rotates_at", ""))
	# -1 = champ ABSENT (visiteur anonyme ou serveur antérieur) → le widget se masque plutôt que
	# d'afficher une jauge inventée (§1.5 : toute lecture nouvelle a un défaut silencieux).
	_rot_games_max = int(data.get("free_games_max", -1)) if data.has("free_games_max") else -1
	_rot_games_left = int(data.get("free_games_left", -1)) if data.has("free_games_left") else -1
	# Ne re-peupler que si l'onglet APERÇU est À L'ÉCRAN : la rotation arrive de façon asynchrone,
	# et reconstruire un onglet masqué serait du travail perdu (il se peuple à son ouverture).
	if _tabs != null and _tabs.current_tab == TAB_OVERVIEW:
		_populate_overview_tab()


# Jours restants avant la prochaine rotation (0 si la date est inconnue / non parsable).
func _rotation_days_left() -> int:
	if _rot_rotates_at == "":
		return 0
	var at := int(Time.get_unix_time_from_datetime_string(_rot_rotates_at.trim_suffix("Z")))
	# `ceil` : à J-0,3 il reste bien « 1 jour » à jouer, pas zéro.
	return maxi(0, int(ceil(float(at - int(Time.get_unix_time_from_system())) / 86400.0)))


# Un PIP hexagonal de la jauge (5 au total) — même langage visuel que le badge de Coins de la nav.
# Plein = partie encore disponible (or) ; éteint = déjà consommée (surface + bord muet).
func _make_freeplay_pip(filled: bool) -> Control:
	var pip := Label.new()
	pip.text = "◆" if filled else "◇"
	pip.add_theme_font_override("font", _font)
	pip.add_theme_font_size_override("font_size", 20)
	pip.add_theme_color_override("font_color", GOLD if filled else MUTED)
	pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return pip


# Carte « PERSONNAGE GRATUIT DE LA SEMAINE ». Renvoie null (widget MASQUÉ) si la rotation est
# inconnue, si le joueur n'est pas authentifié, ou si le serveur ne sert pas encore les compteurs.
func _build_freeplay_card() -> Control:
	if _rot_faction_id == "" or _rot_games_max <= 0 or _rot_games_left < 0:
		return null

	var info: Dictionary = _factions.get(_rot_faction_id, {})
	var fac_name := str(info.get("name", _rot_faction_id)).to_upper()
	var fac_color: Color = info.get("color", ACCENT) if not info.is_empty() else ACCENT
	var exhausted := _rot_games_left <= 0

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.set_corner_radius_all(0)
	style.border_width_left = 3
	style.border_color = MUTED if exhausted else GOLD
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", style)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	v.add_child(_eyebrow(tr("PROFILE_FREEPLAY_TITLE")))

	# Ligne d'identité : pastille à la couleur SIGNATURE + nom du personnage offert.
	var idline := HBoxContainer.new()
	idline.add_theme_constant_override("separation", 10)
	v.add_child(idline)
	var dot := ColorRect.new()
	dot.color = fac_color
	dot.custom_minimum_size = Vector2(8, 22)
	idline.add_child(dot)
	var name_lbl := Label.new()
	name_lbl.text = fac_name
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	idline.add_child(name_lbl)

	# Jauge : un pip par partie du plafond, les `left` premiers ALLUMÉS.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	v.add_child(pips)
	for i in range(_rot_games_max):
		pips.add_child(_make_freeplay_pip(i < _rot_games_left))

	if exhausted:
		var done := _muted_note(tr("PROFILE_FREEPLAY_EXHAUSTED"))
		v.add_child(done)
	else:
		var left := Label.new()
		left.text = tr("PROFILE_FREEPLAY_LEFT") % [_rot_games_left, _rot_games_max]
		left.add_theme_font_override("font", _font)
		left.add_theme_font_size_override("font_size", 14)
		left.add_theme_color_override("font_color", GOLD)
		v.add_child(left)

	var days := _rotation_days_left()
	if days > 0:
		v.add_child(_muted_note(tr("PROFILE_FREEPLAY_RESET") % days))

	WarzoneUI.add_corner_notches(card)
	return card


# Un carré de la bande de forme : or = victoire, rouge = défaite ; liseré cyan = partie classée.
func _make_form_square(win: bool, is_ranked: bool) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(FORM_SQUARE, FORM_SQUARE)
	box.tooltip_text = (tr("PROFILE_RESULT_VICTORY") if win else tr("PROFILE_RESULT_DEFEAT")) \
		+ ("  ·  " + tr("PROFILE_MODE_RANKED") if is_ranked else "")
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = GOLD if win else DANGER
	if is_ranked:
		sb.set_border_width_all(1)
		sb.border_color = ACCENT
	box.add_theme_stylebox_override("panel", sb)
	return box


# =========================================================
# ONGLET 2 — STATISTIQUES (chantier L) : par personnage × par mode + progression
# =========================================================
func _populate_stats_tab() -> void:
	if _stats_box == null:
		return
	_clear(_stats_box)

	# Sélecteur de vue (chips exclusives).
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	_stats_box.add_child(chips)
	chips.add_child(_make_chip(tr("PROFILE_STATS_BY_HERO"), _stats_view == "hero",
		func() -> void: _set_stats_view("hero")))
	chips.add_child(_make_chip(tr("PROFILE_STATS_BY_MODE"), _stats_view == "mode",
		func() -> void: _set_stats_view("mode")))
	chips.add_child(_make_chip(tr("PROFILE_STATS_BY_MAP"), _stats_view == "map",
		func() -> void: _set_stats_view("map")))
	_stats_box.add_child(_spacer(4))

	# §8.123 — RÉPUTATION : ligne NEUTRE (« PACTES ROMPUS : N »), sans jugement ni couleur d'alerte.
	# Les chiffres parlent ; le jeu, lui, ne condamne pas — rompre un pacte est parfaitement légal.
	# Masquée à 0 (cf. `_pacts_broken`) : ne rien afficher vaut mieux qu'un compteur à zéro dont on
	# ne saurait pas dire s'il signifie « loyal » ou « serveur pas à jour ».
	if _pacts_broken > 0:
		var rep := HBoxContainer.new()
		rep.add_theme_constant_override("separation", 8)
		var rep_key := Label.new()
		rep_key.text = tr("PROFILE_PACTS_BROKEN")
		rep_key.add_theme_color_override("font_color", MUTED)
		rep.add_child(rep_key)
		var rep_val := Label.new()
		rep_val.text = str(_pacts_broken)
		rep_val.add_theme_color_override("font_color", TEXT)
		rep.add_child(rep_val)
		_stats_box.add_child(rep)
		_stats_box.add_child(_spacer(4))

	match _stats_view:
		"mode":
			_build_stats_by_mode()
		"map":
			_build_stats_by_map()
		_:
			_build_stats_by_hero()

	# Monitoring de progression (commun aux deux vues) : courbe des RP cumulés.
	_build_rp_chart()


func _set_stats_view(view: String) -> void:
	if _stats_view == view:
		return
	_stats_view = view
	AudioManager.play_sfx("click")
	_populate_stats_tab()


func _build_stats_by_hero() -> void:
	if _factions_stats.is_empty():
		_stats_box.add_child(_muted_note(tr("PROFILE_STATS_EMPTY")))
		return
	for entry in _factions_stats:
		if typeof(entry) == TYPE_DICTIONARY:
			_stats_box.add_child(_make_faction_stat_row(entry))


# Une rangée-carte par personnage : identité + volume + winrate + colonnes chiffrées.
func _make_faction_stat_row(e: Dictionary) -> PanelContainer:
	var fid := str(e.get("faction_id", ""))
	var info: Dictionary = _factions.get(fid, {})
	var color: Color = info.get("color", ACCENT) if not info.is_empty() else ACCENT

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(color))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	# --- Gauche : pastille + nom de faction + niveau du héros ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_constant_override("separation", 2)
	h.add_child(left)
	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", 8)
	left.add_child(name_line)
	name_line.add_child(_make_dot(color))
	var fac := _mini(str(info.get("name", fid)).to_upper(), 17, TEXT)
	name_line.add_child(fac)
	left.add_child(_mini(tr("PROFILE_HERO_LEVEL_FMT") % int(e.get("hero_level", 1)), 12, MUTED))

	# --- Centre : volume + barre de winrate ---
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	h.add_child(center)
	var games := int(e.get("games", 0))
	var wins := int(e.get("wins", 0))
	var losses := int(e.get("losses", 0))
	center.add_child(_mini(tr("PROFILE_GAMES_WL_FMT") % [games, wins, losses], 13, MUTED))
	var wr := int(e.get("winrate", 0))
	var wr_line := HBoxContainer.new()
	wr_line.add_theme_constant_override("separation", 10)
	center.add_child(wr_line)
	var bar := _make_ratio_bar(wr, GOLD, 0.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wr_line.add_child(bar)
	wr_line.add_child(_mini("%d%%" % wr, 15, GOLD))

	# --- Droite : colonnes chiffrées alignées (place moyenne, XP, RP net) ---
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 18)
	h.add_child(right)
	# Place moyenne transportée en DIXIÈMES (piège JSON float §5) → « 2.4 » à l'affichage.
	var avg := int(e.get("avg_rank_x10", 0))
	right.add_child(_make_metric(tr("PROFILE_AVG_RANK"),
		("%.1f" % (avg / 10.0)) if avg > 0 else "—", TEXT if avg > 0 else MUTED))
	right.add_child(_make_metric(tr("COMMON_XP"),
		_format_thousands(int(e.get("xp_total", 0))), ACCENT))
	# RP NET : « — » si le personnage n'a jamais été joué en classée (0 net ET aucune classée).
	var rp_net := int(e.get("rp_net", 0))
	right.add_child(_make_metric(tr("PROFILE_RP_NET"),
		_signed(rp_net) if rp_net != 0 else "—",
		GOLD if rp_net > 0 else (DANGER if rp_net < 0 else MUTED)))
	return row


func _build_stats_by_mode() -> void:
	var ranked: Dictionary = _modes.get("ranked", {}) if typeof(_modes.get("ranked")) == TYPE_DICTIONARY else {}
	var casual: Dictionary = _modes.get("casual", {}) if typeof(_modes.get("casual")) == TYPE_DICTIONARY else {}
	if int(ranked.get("games", 0)) == 0 and int(casual.get("games", 0)) == 0:
		_stats_box.add_child(_muted_note(tr("PROFILE_STATS_EMPTY")))
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_stats_box.add_child(row)
	row.add_child(_make_mode_card(tr("PROFILE_MODE_RANKED"), ranked, GOLD, true))
	row.add_child(_make_mode_card(tr("PROFILE_MODE_CASUAL"), casual, ACCENT, false))

	# Honnêteté des données : les parties antérieures à la mise à jour sont comptées en NORMALES.
	if int(casual.get("games", 0)) > 0:
		_stats_box.add_child(_muted_note(tr("PROFILE_MODE_LEGACY_NOTE")))


func _make_mode_card(title: String, data: Dictionary, accent: Color, show_rp: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	var eb := _eyebrow(title)
	eb.add_theme_color_override("font_color", accent)
	v.add_child(eb)

	var games := int(data.get("games", 0))
	var wins := int(data.get("wins", 0))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 24)
	v.add_child(line)
	line.add_child(_make_metric(tr("PROFILE_STAT_GAMES"), str(games), TEXT))
	line.add_child(_make_metric(tr("COMMON_WINS"), str(wins), GOLD))
	if show_rp:
		var rp_net := int(data.get("rp_net", 0))
		line.add_child(_make_metric(tr("PROFILE_RP_NET"),
			_signed(rp_net) if games > 0 else "—",
			GOLD if rp_net > 0 else (DANGER if rp_net < 0 else MUTED)))

	var wr := int(data.get("winrate", 0))
	var wr_line := HBoxContainer.new()
	wr_line.add_theme_constant_override("separation", 10)
	v.add_child(wr_line)
	var bar := _make_ratio_bar(wr, accent, 0.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wr_line.add_child(bar)
	wr_line.add_child(_mini("%d%%" % wr, 15, accent))
	WarzoneUI.add_corner_notches(card)
	return card


# --- Vue PAR CARTE (§8.107) : sur quelle carte le joueur performe le mieux ---
func _build_stats_by_map() -> void:
	if _maps_stats.is_empty():
		_stats_box.add_child(_muted_note(tr("PROFILE_STATS_EMPTY")))
		return
	for entry in _maps_stats:
		if typeof(entry) == TYPE_DICTIONARY:
			_stats_box.add_child(_make_map_stat_row(entry))
	# Honnêteté des données : le serveur EXCLUT les matchs sans carte connue (tous ceux joués avant
	# cette mise à jour). La note est INCONDITIONNELLE — le client ne peut pas savoir combien de
	# lignes ont été écartées, et prétendre le contraire serait pire que de le dire simplement.
	_stats_box.add_child(_muted_note(tr("PROFILE_MAP_LEGACY_NOTE")))


func _make_map_stat_row(e: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(ACCENT))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	# Gauche : nom de carte résolu localement (repli sur l'id brut si le serveur en connaît une
	# que ce client ignore — jamais une clé i18n crue à l'écran).
	var mid := str(e.get("map_id", ""))
	var label := tr(str(MAP_LABELS[mid])) if MAP_LABELS.has(mid) else mid
	var left := _mini(label.to_upper(), 17, TEXT)
	left.custom_minimum_size = Vector2(260, 0)
	h.add_child(left)

	# Centre : volume + barre de winrate (mêmes briques que la vue PAR PERSONNAGE).
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	h.add_child(center)
	center.add_child(_mini(tr("PROFILE_GAMES_WL_FMT")
		% [int(e.get("games", 0)), int(e.get("wins", 0)), int(e.get("losses", 0))], 13, MUTED))
	var wr := int(e.get("winrate", 0))
	var wr_line := HBoxContainer.new()
	wr_line.add_theme_constant_override("separation", 10)
	center.add_child(wr_line)
	var bar := _make_ratio_bar(wr, GOLD, 0.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wr_line.add_child(bar)
	wr_line.add_child(_mini("%d%%" % wr, 15, GOLD))

	# Droite : place moyenne (DIXIÈMES → « 2.5 »), « — » si aucune place connue.
	var avg := int(e.get("avg_rank_x10", 0))
	h.add_child(_make_metric(tr("PROFILE_AVG_RANK"),
		("%.1f" % (avg / 10.0)) if avg > 0 else "—", TEXT if avg > 0 else MUTED))
	return row


# --- Courbe « RP cumulés » (chantier L.4) : polyline native, AUCUNE lib externe ---
# Masquée sous 2 points : une courbe d'un seul match ne raconte rien.
func _build_rp_chart() -> void:
	if _rp_series.size() < 2:
		return
	_stats_box.add_child(_spacer(10))
	_stats_box.add_child(_eyebrow(tr("PROFILE_RP_CHART_TITLE")))

	# Cumul des ΔRP dans le sens du temps (la série est déjà du plus ancien au plus récent).
	var cumulative: Array = []
	var running := 0
	for d in _rp_series:
		running += int(d)
		cumulative.append(running)
	var lo: int = cumulative.min()
	var hi: int = cumulative.max()

	var chart := Control.new()
	chart.custom_minimum_size = Vector2(0, 150)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_box.add_child(chart)
	# On dessine via le signal `draw` (émis PENDANT la notification de dessin) : les appels
	# draw_* y sont valides, ce qui évite un script dédié pour un seul graphique.
	chart.draw.connect(func() -> void:
		_draw_rp_chart(chart, cumulative, lo, hi))

	# Axe minimal : bornes en muet (aucune graduation bavarde — lecture d'un coup d'œil).
	var axis := HBoxContainer.new()
	_stats_box.add_child(axis)
	axis.add_child(_mini(tr("PROFILE_RP_CHART_MIN") % _signed(lo), 11, MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	axis.add_child(sp)
	axis.add_child(_mini(tr("PROFILE_RP_CHART_MAX") % _signed(hi), 11, MUTED))


func _draw_rp_chart(chart: Control, values: Array, lo: int, hi: int) -> void:
	var w := chart.size.x
	var h := chart.size.y
	if w <= 1.0 or h <= 1.0 or values.size() < 2:
		return
	# Quadrillage discret (4 lignes horizontales) — repère, pas décor.
	for i in range(5):
		var y := h * float(i) / 4.0
		chart.draw_line(Vector2(0, y), Vector2(w, y), Color(SURFACE, 0.9), 1.0)

	# Normalisation : amplitude nulle (série plate) → tout au milieu, pas de division par zéro.
	var span := float(hi - lo)
	var points := PackedVector2Array()
	for i in range(values.size()):
		var x := w * float(i) / float(values.size() - 1)
		var t := 0.5 if span <= 0.0 else (float(values[i]) - float(lo)) / span
		# y inversé : les RP hauts en HAUT. Marge de 8 px pour que les points ne touchent pas le bord.
		points.append(Vector2(x, lerpf(h - 8.0, 8.0, t)))
	chart.draw_polyline(points, ACCENT, 2.0, true)
	for p in points:
		chart.draw_circle(p, 3.0, ACCENT)


# =========================================================
# ONGLET 3 — HISTORIQUE (chantier M) : victoires par défaut, ligne enrichie
# =========================================================
func _populate_history_tab() -> void:
	if _history_box == null:
		return
	_clear(_history_box)

	# Filtres exclusifs — VICTOIRES par défaut (demande produit).
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	_history_box.add_child(chips)
	chips.add_child(_make_chip(tr("PROFILE_HIST_WINS"), _history_filter == "wins",
		func() -> void: _set_history_filter("wins")))
	chips.add_child(_make_chip(tr("PROFILE_HIST_ALL"), _history_filter == "all",
		func() -> void: _set_history_filter("all")))
	chips.add_child(_make_chip(tr("PROFILE_HIST_RANKED"), _history_filter == "ranked",
		func() -> void: _set_history_filter("ranked")))
	_history_box.add_child(_spacer(4))

	if _history_rows.is_empty():
		_history_box.add_child(_muted_note(tr("PROFILE_HISTORY_EMPTY")))
		return
	for entry in _history_rows:
		_history_box.add_child(_make_history_row(entry))

	if not _history_end_reached:
		_history_box.add_child(_make_more_button(func() -> void: _fetch_history(false)))


func _set_history_filter(f: String) -> void:
	if _history_filter == f:
		return
	_history_filter = f
	AudioManager.play_sfx("click")
	_history_rows.clear()
	_history_end_reached = false
	_populate_history_tab()      # rend immédiatement l'état « vide » + les chips à jour
	_set_status(tr("COMMON_SYNCING"))
	_fetch_history(true)


func _make_history_row(entry: Dictionary) -> PanelContainer:
	var is_win := bool(entry.get("win", false))
	var is_ranked := bool(entry.get("is_ranked", false))
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(GOLD if is_win else DANGER))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	# --- Colonne 1 : issue + place finale ---
	var col1 := VBoxContainer.new()
	col1.custom_minimum_size = Vector2(170, 0)
	col1.add_theme_constant_override("separation", 1)
	h.add_child(col1)
	var res := _mini("❯  " + (tr("PROFILE_RESULT_VICTORY") if is_win else tr("PROFILE_RESULT_DEFEAT")),
		18, GOLD if is_win else DANGER)
	col1.add_child(res)
	# ⚠️ `final_rank == 0` = place INCONNUE (ligne antérieure à la mise à jour), JAMAIS « 1ᵉʳ ».
	# On affiche « — » plutôt que d'inventer une donnée.
	var rank := int(entry.get("final_rank", 0))
	var players := int(entry.get("players_count", 0))
	var rank_text := "—"
	if rank > 0 and players > 0:
		rank_text = tr("PROFILE_HIST_RANK_FIRST_FMT") % players if rank == 1 \
			else tr("PROFILE_HIST_RANK_FMT") % [rank, players]
	col1.add_child(_mini(rank_text, 12, MUTED))

	# --- Colonne 2 : faction + badge CLASSÉE ---
	var col2 := VBoxContainer.new()
	col2.custom_minimum_size = Vector2(210, 0)
	col2.add_theme_constant_override("separation", 2)
	h.add_child(col2)
	var fid := str(entry.get("faction_id", ""))
	var info: Dictionary = _factions.get(fid, {})
	col2.add_child(_mini(str(info.get("name", fid)).to_upper() if fid != "" else "—", 16, TEXT))
	if is_ranked:
		col2.add_child(_make_badge(tr("PROFILE_HIST_RANKED_BADGE"), GOLD))

	# --- Colonne 3 : détail serveur + date relative ---
	var col3 := VBoxContainer.new()
	col3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col3.add_theme_constant_override("separation", 2)
	h.add_child(col3)
	col3.add_child(_mini(str(entry.get("detail", "")), 14, MUTED))
	var when := _relative_date(str(entry.get("created_at", "")))
	if when != "":
		col3.add_child(_mini(when, 12, MUTED))

	# --- Colonne 4 : gains (XP / RP / Coins), alignés à droite ---
	var col4 := HBoxContainer.new()
	col4.add_theme_constant_override("separation", 14)
	col4.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(col4)
	var xp_earned := int(entry.get("xp_earned", 0))
	col4.add_child(_make_metric(tr("COMMON_XP"),
		("+" + _format_thousands(xp_earned)) if xp_earned > 0 else "—",
		ACCENT if xp_earned > 0 else MUTED))
	# RP : affiché SEULEMENT pour une partie classée (il n'en est jamais distribué ailleurs).
	if is_ranked:
		var rp := int(entry.get("rp_delta", 0))
		col4.add_child(_make_metric(tr("PROFILE_RP_SHORT"), _signed(rp),
			GOLD if rp > 0 else (DANGER if rp < 0 else MUTED)))
	var coins := int(entry.get("coins_earned", 0))
	if coins > 0:
		col4.add_child(_make_metric(tr("PROFILE_FIN_BALANCE"), "+" + _format_thousands(coins), GOLD))
	return row


# =========================================================
# ONGLET 4 — FINANCES (chantier N)
# =========================================================
func _populate_finance_tab() -> void:
	if _finance_box == null:
		return
	_clear(_finance_box)

	if not _finance_available:
		_finance_box.add_child(_muted_note(tr("PROFILE_TAB_UNAVAILABLE")))
		return
	if _finance.is_empty():
		_finance_box.add_child(_muted_note(tr("COMMON_SYNCING")))
		return

	# --- Bandeau : solde / total gagné / total dépensé ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_finance_box.add_child(top)
	top.add_child(_make_stat_card(tr("PROFILE_FIN_BALANCE"),
		_format_thousands(int(_finance.get("balance", 0))), GOLD))
	top.add_child(_make_stat_card(tr("PROFILE_FIN_EARNED"),
		_format_thousands(int(_finance.get("total_earned", 0))), ACCENT))
	top.add_child(_make_stat_card(tr("PROFILE_FIN_SPENT"),
		_format_thousands(int(_finance.get("total_spent", 0))), DANGER))

	# --- Répartition par SOURCE ---
	var by_reason = _finance.get("by_reason", {})
	if typeof(by_reason) == TYPE_DICTIONARY and not by_reason.is_empty():
		_finance_box.add_child(_spacer(8))
		_finance_box.add_child(_eyebrow(tr("PROFILE_FIN_BY_SOURCE")))
		# Normalisation des barres sur le plus gros montant ABSOLU (gains et dépenses comparables).
		var max_abs := 1
		for reason in by_reason:
			max_abs = maxi(max_abs, absi(int(by_reason[reason])))
		for reason in by_reason:
			var amount := int(by_reason[reason])
			if amount == 0:
				continue   # une source à 0 net n'apprend rien : on ne l'affiche pas.
			_finance_box.add_child(_make_reason_row(str(reason), amount, max_abs))

	# --- Transactions récentes ---
	_finance_box.add_child(_spacer(8))
	_finance_box.add_child(_eyebrow(tr("PROFILE_FIN_TRANSACTIONS")))
	if _finance_entries.is_empty():
		_finance_box.add_child(_muted_note(tr("PROFILE_FIN_EMPTY")))
	else:
		for e in _finance_entries:
			_finance_box.add_child(_make_transaction_row(e))
		if not _finance_end_reached:
			_finance_box.add_child(_make_more_button(func() -> void:
				NetworkManager.fetch_profile_finance(FINANCE_PAGE, _finance_entries.size())))

	# --- Potentiel de gain par personnage ---
	var potential = _finance.get("hero_potential", [])
	if typeof(potential) == TYPE_ARRAY and not potential.is_empty():
		_finance_box.add_child(_spacer(8))
		_finance_box.add_child(_eyebrow(tr("PROFILE_FIN_POTENTIAL")))
		for p in potential:
			if typeof(p) == TYPE_DICTIONARY:
				_finance_box.add_child(_make_potential_row(p))


# Libellé i18n d'une raison de mouvement. Une raison INCONNUE (ajoutée par une version ultérieure
# du serveur) retombe sur son id brut en muet : jamais une clé nue à l'écran, jamais un trou.
func _reason_label(reason: String) -> String:
	var key := "PROFILE_FIN_SRC_" + reason.to_upper()
	var label := tr(key)
	return reason.to_upper().replace("_", " ") if label == key else label


func _make_reason_row(reason: String, amount: int, max_abs: int) -> PanelContainer:
	var positive := amount > 0
	var color := GOLD if positive else DANGER
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(color))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	var label := _mini(_reason_label(reason), 14, TEXT)
	label.custom_minimum_size = Vector2(240, 0)
	h.add_child(label)

	var bar := _make_ratio_bar(int(round(100.0 * absi(amount) / float(max_abs))), color, 0.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)

	var value := _mini(_signed(amount), 15, color)
	value.custom_minimum_size = Vector2(110, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(value)
	return row


func _make_transaction_row(e: Dictionary) -> PanelContainer:
	var delta := int(e.get("delta", 0))
	var color := GOLD if delta > 0 else DANGER
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(color))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	var amount := _mini(_signed(delta), 17, color)
	amount.custom_minimum_size = Vector2(110, 0)
	h.add_child(amount)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	h.add_child(mid)
	mid.add_child(_mini(_reason_label(str(e.get("reason", ""))), 14, TEXT))
	# `ref` (item acheté, mission réclamée…) : contexte utile, affiché en muet et seulement s'il existe.
	var ref := str(e.get("ref", ""))
	var sub := ref.to_upper().replace("_", " ") if ref != "" else ""
	var when := _relative_date(str(e.get("created_at", "")))
	if when != "":
		sub = (sub + "  ·  " + when) if sub != "" else when
	if sub != "":
		mid.add_child(_mini(sub, 12, MUTED))

	var balance := _mini(tr("PROFILE_FIN_BALANCE_AFTER_FMT")
		% _format_thousands(int(e.get("balance_after", 0))), 12, MUTED)
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	balance.custom_minimum_size = Vector2(160, 0)
	h.add_child(balance)
	return row


func _make_potential_row(p: Dictionary) -> PanelContainer:
	var fid := str(p.get("faction_id", ""))
	var info: Dictionary = _factions.get(fid, {})
	var color: Color = info.get("color", ACCENT) if not info.is_empty() else ACCENT
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style(color))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	var left := HBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 8)
	h.add_child(left)
	left.add_child(_make_dot(color))
	left.add_child(_mini(str(info.get("name", fid)).to_upper(), 15, TEXT))
	left.add_child(_mini(tr("PROFILE_HERO_LEVEL_FMT") % int(p.get("hero_level", 1)), 12, MUTED))

	var levels_left := int(p.get("levels_left", 0))
	if levels_left <= 0:
		# Héros au niveau maximum : plus rien à gagner — dit tel quel, sans fourchette à zéro.
		h.add_child(_mini(tr("PROFILE_FIN_POTENTIAL_MAX"), 14, MUTED))
		return row

	var mid := _mini(tr("PROFILE_FIN_LEVELS_LEFT_FMT") % levels_left, 13, MUTED)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	# Deux fourchettes : sans Pass (muet) puis avec Pass (or, préfixée) — argument de vente honnête.
	h.add_child(_make_metric(tr("PROFILE_FIN_WITHOUT_PASS"),
		"%s-%s" % [_format_thousands(int(p.get("coins_min", 0))),
				   _format_thousands(int(p.get("coins_max", 0)))], TEXT))
	h.add_child(_make_metric(tr("PROFILE_FIN_WITH_PASS"),
		"%s-%s" % [_format_thousands(int(p.get("coins_min_pass", 0))),
				   _format_thousands(int(p.get("coins_max_pass", 0)))], GOLD))
	return row


# =========================================================
# ONGLET 5 — PASS (chantier O) : état, avantages data-driven, gain réel, objets obtenus
# =========================================================
func _populate_pass_tab() -> void:
	if _pass_box == null:
		return
	_clear(_pass_box)

	if not _pass_available:
		_pass_box.add_child(_muted_note(tr("PROFILE_TAB_UNAVAILABLE")))
		return
	if _pass.is_empty():
		_pass_box.add_child(_muted_note(tr("COMMON_SYNCING")))
		return

	# --- Bandeau d'état ---
	var active := bool(_pass.get("active", false))
	var state := PanelContainer.new()
	state.add_theme_stylebox_override("panel", _make_card_style(GOLD if active else MUTED))
	_pass_box.add_child(state)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	state.add_child(sv)
	var title := _mini(tr("PASS_ACTIVE_TITLE") if active else tr("PASS_INACTIVE_TITLE"),
		22, GOLD if active else MUTED)
	sv.add_child(title)
	if active:
		var days := _days_until(str(_pass.get("expires_at", "")))
		if days >= 0:
			sv.add_child(_mini(tr("PASS_EXPIRES_FMT") % days, 14, MUTED))
	else:
		# Un SEUL bouton discret vers la boutique — pas de vente agressive (la boutique sera refondue).
		var btn := Button.new()
		btn.text = tr("PASS_GO_SHOP")
		btn.add_theme_font_override("font", _font)
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size = Vector2(240, 40)
		WarzoneUI.apply_ghost_button(btn)
		WarzoneUI.wire_button_feedback(btn)
		btn.pressed.connect(func() -> void:
			TransitionManager.change_scene("res://scenes/ui/shop.tscn"))
		sv.add_child(btn)
	WarzoneUI.add_corner_notches(state)

	# --- Avantages DATA-DRIVEN : un bloc par tier. Ajouter un tier côté serveur suffit à le voir
	#     apparaître ici — ce rendu n'énumère aucun avantage en dur. ---
	var tiers = _pass.get("tiers", [])
	if typeof(tiers) == TYPE_ARRAY:
		for t in tiers:
			if typeof(t) != TYPE_DICTIONARY:
				continue
			_pass_box.add_child(_spacer(8))
			_pass_box.add_child(_eyebrow(tr(str(t.get("name_key", "")))))
			var benefits = t.get("benefits", [])
			if typeof(benefits) != TYPE_ARRAY:
				continue
			for b in benefits:
				if typeof(b) == TYPE_DICTIONARY:
					_pass_box.add_child(_make_benefit_row(b))

	# --- Gain RÉEL mesuré ---
	var gains = _pass.get("gains", {})
	if typeof(gains) == TYPE_DICTIONARY:
		_pass_box.add_child(_spacer(8))
		_pass_box.add_child(_eyebrow(tr("PASS_GAINS_TITLE")))
		var grid := HBoxContainer.new()
		grid.add_theme_constant_override("separation", 12)
		_pass_box.add_child(grid)
		var bonus_xp := int(gains.get("bonus_xp_total", 0))
		var bonus_missions := int(gains.get("bonus_mission_coins_total", 0))
		var hero_coins := int(gains.get("hero_coins_with_pass_total", 0))
		var spent := int(gains.get("coins_spent_on_pass", 0))
		grid.add_child(_make_stat_card(tr("PASS_GAIN_XP"), _format_thousands(bonus_xp), ACCENT))
		grid.add_child(_make_stat_card(tr("PASS_GAIN_MISSIONS"), _format_thousands(bonus_missions), GOLD))
		grid.add_child(_make_stat_card(tr("PASS_GAIN_HERO_COINS"), _format_thousands(hero_coins), GOLD))
		grid.add_child(_make_stat_card(tr("PASS_GAIN_COST"), _format_thousands(spent), DANGER))
		# BILAN NET : seuls les COINS entrent au bilan — l'XP bonus n'est pas convertible, l'ajouter
		# gonflerait artificiellement le résultat (calcul d'affichage, cf. PASS_GAINS_NOTE).
		var net := bonus_missions + hero_coins - spent
		_pass_box.add_child(_mini(tr("PASS_NET_BALANCE_FMT") % _signed(net), 17,
			GOLD if net >= 0 else DANGER))
		_pass_box.add_child(_muted_note(tr("PASS_GAINS_NOTE")))

	# --- Objets obtenus grâce au Pass (rendu GÉNÉRIQUE par catégorie) ---
	_pass_box.add_child(_spacer(8))
	_pass_box.add_child(_eyebrow(tr("PASS_GRANTED_TITLE")))
	var granted = _pass.get("granted_items", [])
	if typeof(granted) != TYPE_ARRAY or granted.is_empty():
		_pass_box.add_child(_muted_note(tr("PASS_GRANTED_EMPTY")))
	else:
		for g in granted:
			if typeof(g) == TYPE_DICTIONARY:
				_pass_box.add_child(_make_granted_row(g))


# Une ligne d'avantage. Le `kind` pilote le FORMATAGE de la valeur ; un kind inconnu (ajouté par une
# version ultérieure) retombe sur le seul libellé — la ligne s'affiche toujours, jamais de trou.
func _make_benefit_row(b: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_mini("❯", 15, ACCENT))

	var desc := tr(str(b.get("desc_key", "")))
	var kind := str(b.get("kind", ""))
	var value = b.get("value")
	match kind:
		"percent":
			desc = desc % int(value)
		"range":
			if typeof(value) == TYPE_ARRAY and value.size() >= 2:
				desc = desc % [int(value[0]), int(value[1])]
	h.add_child(_mini(desc, 14, TEXT))
	return h


func _make_granted_row(g: Dictionary) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_mini("❯", 15, GOLD))
	h.add_child(_mini(tr(str(g.get("name_key", ""))).to_upper(), 15, TEXT))
	# Catégorie : même convention de clé que la boutique (SHOP_CAT_<CATEGORY>) → une catégorie
	# future (ex. « faction » offerte par un Pass) s'affiche sans une ligne de code de plus.
	var cat := str(g.get("category", ""))
	if cat != "":
		h.add_child(_mini(tr("SHOP_CAT_" + cat.to_upper()), 12, MUTED))
	return h


# =========================================================
# FABRIQUES DE NŒUDS / STYLES (charte §2, cohérent avec shop.gd)
# =========================================================
# Carte readout : eyebrow (libellé) + valeur en gros (couleur sémantique). Surface gunmetal,
# liseré gauche à la couleur de la valeur (§8.102).
func _make_stat_card(label: String, value: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(value_color))
	card.custom_minimum_size = Vector2(175, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	v.add_child(_eyebrow(label))

	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", _font)
	val.add_theme_font_size_override("font_size", 30)
	val.add_theme_color_override("font_color", value_color)
	v.add_child(val)

	WarzoneUI.add_corner_notches(card)
	return card


# Colonne chiffrée compacte : eyebrow muet au-dessus, valeur en dessous (rythme eyebrow→valeur §2).
func _make_metric(label: String, value: String, color: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.custom_minimum_size = Vector2(92, 0)
	var eb := _mini(label, 11, MUTED)
	v.add_child(eb)
	v.add_child(_mini(value, 16, color))
	return v


# Chip de filtre/vue : plat, MAJUSCULES, actif = fond cyan discret + filet supérieur cyan.
func _make_chip(text: String, active: bool, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_NONE

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT, 0.16) if active else Color(SURFACE, 0.5)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if active:
		sb.border_width_top = 2
		sb.border_color = ACCENT
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.24) if active else Color(ACCENT, 0.08)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)
	btn.pressed.connect(on_press)
	WarzoneUI.wire_button_sfx(btn)
	return btn


# Bouton de pagination « AFFICHER PLUS ❯ » (clé partagée avec le classement).
func _make_more_button(on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = tr("LEADERBOARD_SHOW_MORE")
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.custom_minimum_size = Vector2(0, 38)
	WarzoneUI.apply_ghost_button(btn)
	WarzoneUI.wire_button_feedback(btn)
	btn.pressed.connect(on_press)
	return btn


# Badge plat bordé (« CLASSÉE ») — remplace tout libellé à emoji (§8.100).
func _make_badge(text: String, color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(color, 0.10)
	sb.set_border_width_all(1)
	sb.border_color = Color(color, 0.65)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	badge.add_child(_mini(text, 11, color))
	return badge


# Pastille carrée de couleur de faction (ADN angulaire : jamais un rond, jamais une puce emoji).
func _make_dot(color: Color) -> PanelContainer:
	var dot := PanelContainer.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = color
	dot.add_theme_stylebox_override("panel", sb)
	return dot


# Barre de proportion horizontale (winrate, répartition financière, progression d'échelon).
# `width <= 0` → la barre s'étire dans son conteneur (poser SIZE_EXPAND_FILL côté appelant).
func _make_ratio_bar(percent: int, color: Color, width: float = 160.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(maxf(width, 0.0), 8)
	pb.min_value = 0
	pb.max_value = 100
	pb.value = clampi(percent, 0, 100)
	pb.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = SURFACE
	bg.set_corner_radius_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(0)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


func _eyebrow(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ACCENT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# Label générique de la charte (texte DÉJÀ traduit → pas d'auto-traduction par Godot).
func _mini(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


# Note discrète (état vide, avertissement d'honnêteté des données) — muette, jamais alarmante.
func _muted_note(text: String) -> Label:
	var l := _mini(text, 13, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


# Style d'une carte : surface gunmetal + liseré gauche à la couleur sémantique (charte §2).
func _make_card_style(accent: Color = ACCENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.border_width_left = 3
	sb.border_color = accent
	sb.content_margin_left = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 10.0
	return sb


# Style des onglets — MIROIR de operation_report._style_tabs (même langage sur les deux écrans).
func _style_tabs(tc: TabContainer) -> void:
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.058824, 0.07451, 0.094118, 0.55)
	panel_sb.border_color = Color(ACCENT, 0.35)
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(0)
	panel_sb.set_content_margin_all(14)
	tc.add_theme_stylebox_override("panel", panel_sb)

	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(ACCENT, 0.16)
	sel.set_corner_radius_all(0)
	sel.border_width_top = 2
	sel.border_color = ACCENT
	sel.content_margin_left = 18
	sel.content_margin_right = 18
	sel.content_margin_top = 8
	sel.content_margin_bottom = 8

	var unsel := StyleBoxFlat.new()
	unsel.bg_color = Color(SURFACE, 0.5)
	unsel.set_corner_radius_all(0)
	unsel.content_margin_left = 18
	unsel.content_margin_right = 18
	unsel.content_margin_top = 8
	unsel.content_margin_bottom = 8

	var hover := unsel.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.08)
	tc.add_theme_stylebox_override("tab_selected", sel)
	tc.add_theme_stylebox_override("tab_unselected", unsel)
	tc.add_theme_stylebox_override("tab_hovered", hover)
	tc.add_theme_color_override("font_selected_color", ACCENT)
	tc.add_theme_color_override("font_unselected_color", MUTED)
	tc.add_theme_color_override("font_hovered_color", TEXT)


# Barre d'XP cyan (fond gunmetal, remplissage cyan) — angulaire (corner_radius 0).
func _style_xp_bar() -> void:
	if xp_bar == null:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = SURFACE
	bg.set_corner_radius_all(0)
	bg.set_border_width_all(1)
	bg.border_color = Color(ACCENT, 0.35)

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(0)

	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	xp_bar.show_percentage = false


# =========================================================
# CHARGEMENT DES FACTIONS (id -> nom + couleur) — garde-fous de faction_selection.gd
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
			_factions[str(res.id)] = {
				"name": str(res.get("name")),
				"color": res.get("accent_color") if res.get("accent_color") != null else ACCENT,
			}


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
# UTILITAIRES
# =========================================================
# Libellé traduit d'une division (l'id réseau reste ASCII, seul le rendu porte l'accent).
func _division_name(division: String) -> String:
	if DIVISION_LABELS.has(division):
		return tr(str(DIVISION_LABELS[division]))
	return division


# Libellé « OR II » / « ÉLITE » — miroir de leaderboard._division_label et de rank_info().label.
func _division_label(division: String, tier: String) -> String:
	if division == "":
		return "—"
	if tier == "":
		return _division_name(division)
	return tr("DIVISION_TIER_FMT").format({"division": _division_name(division), "tier": tier})


# « +30 » / « -20 » (le signe + n'est pas posé par %d sur les positifs) — miroir de leaderboard.
func _signed(v: int) -> String:
	return ("+" + _format_thousands(v)) if v > 0 else ("-" + _format_thousands(absi(v)) if v < 0 else "0")


# Jours restants avant une date ISO 8601 « Z ». -1 = date inconnue → l'appelant MASQUE la mention
# (on n'affiche jamais « J-0 » faute de donnée). Même calcul que le compte à rebours du classement.
func _days_until(iso: String) -> int:
	if iso.strip_edges() == "":
		return -1
	var end_epoch := int(Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")))
	if end_epoch <= 0:
		return -1
	return maxi(0, int((end_epoch - int(Time.get_unix_time_from_system())) / 86400))


# Date RELATIVE compacte : « À L'INSTANT » / « IL Y A 2 H » / « IL Y A 3 J » / « 12/07 ».
# "" si la date est absente (lignes d'historique très anciennes) → l'appelant n'affiche rien.
func _relative_date(iso: String) -> String:
	if iso.strip_edges() == "":
		return ""
	var epoch := int(Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")))
	if epoch <= 0:
		return ""
	var delta := int(Time.get_unix_time_from_system()) - epoch
	if delta < 3600:
		return tr("PROFILE_DATE_NOW")
	if delta < 86400:
		@warning_ignore("integer_division")
		return tr("PROFILE_DATE_HOURS_FMT") % (delta / 3600)
	if delta < 7 * 86400:
		@warning_ignore("integer_division")
		return tr("PROFILE_DATE_DAYS_FMT") % (delta / 86400)
	# Au-delà d'une semaine : date courte. L'ORDRE jour/mois vient de la clé i18n (les locales
	# anglaises l'inversent) → jamais de format codé en dur ici.
	var d := Time.get_datetime_dict_from_unix_time(epoch)
	return tr("PROFILE_DATE_SHORT_FMT").format({
		"day": "%02d" % int(d.get("day", 1)),
		"month": "%02d" % int(d.get("month", 1)),
	})


# Sépare les milliers par une fine espace (lisibilité, comme shop._format_credits).
func _format_thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	if value < 0:
		out = "-" + out
	return out


# Vide un conteneur sans laisser de doublons (cf. lobby_screen.gd / shop.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
