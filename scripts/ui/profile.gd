extends Control

# =========================================================================
# Profil utilisateur (Feuille de route R2) — charte « Warzone Command » §2
# =========================================================================
# Écran NEUF accessible depuis main_menu (« ❯ MON PROFIL »).
# Règle d'Or §6.1 : VUE pure — aucune logique de jeu brute. Les VRAIES statistiques sont
# lues du backend (R2 — CONTRAT_RESEAU.md §9.1) via NetworkManager :
#   • GET /profile/stats   → niveau, XP, parties, V/D, plus lourd tribut, faction favorite, crédits.
#   • GET /profile/history → derniers matchs (le plus récent d'abord).
# La lecture reste DÉFENSIVE (clés canoniques + alias) : le serveur fait foi, et tout champ absent
# retombe sur une valeur neutre (0 / « — »). Découplage Vue/réseau par signaux (comme shop.gd).

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var username_value: Label
@export var level_value: Label
@export var xp_bar: ProgressBar
@export var xp_value: Label
@export var faction_chevron: Label
@export var faction_value: Label
@export var stats_grid: GridContainer
@export var history_box: VBoxContainer
@export var status_label: Label

# Helpers UI partagés de la charte « Warzone Command » (§2) — encoches.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")
# Header CANONIQUE partagé (§8.93) — remplace l'ex-bouton RETOUR de l'en-tête.
const TopNav = preload("res://scripts/ui/top_nav.gd")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)    # or (victoire / récompense)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (eyebrow / muet)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)  # surface secondaire
const DANGER := Color(0.839216, 0.270588, 0.247059, 1)  # rouge (défaite)

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

# --- Statistiques de campagne (peuplées par GET /profile/stats, lecture défensive) ---
# Valeurs NEUTRES par défaut : affichées tant que la réponse serveur n'est pas arrivée, puis
# écrasées par les vraies données (jamais de chiffres factices).
var _games_played: int = 0
var _wins: int = 0
var _losses: int = 0
# « Plus lourd tribut » : pertes cumulées d'unités sur l'ensemble des campagnes (User.units_lost).
var _heaviest_toll: int = 0
# Faction de prédilection (id snake_case = clé backend, miroir factions.py). "" tant qu'inconnue.
var _favorite_faction_id: String = ""
# Niveau / XP (GET /profile/stats : level / xp / xp_max).
var _level: int = 1
var _xp: int = 0
var _xp_max: int = 1
# Historique récent (le plus récent en premier), peuplé par GET /profile/history. Chaque entrée
# affichée : victoire (bool), faction (nom résolu depuis l'id), détail (libellé serveur). Vide au départ.
var _history: Array = []

# id de faction -> { name, color } (chargé des .tres).
var _factions: Dictionary = {}

# Police condensée de la charte (§2), construite en code pour les nœuds générés dynamiquement.
var _font: SystemFont

func _ready():
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Header CANONIQUE partagé (§8.93). Écran HORS ONGLETS (on l'ouvre par la jauge XP cliquable de
	# la nav, pas par un onglet) → `active_tab = ""` : AUCUN onglet surligné. L'écran GARDE son titre
	# interne : sans onglet actif, c'est la seule chose qui le nomme. ÉCHAP (nav) remplace le RETOUR.
	# ⚠️ active_tab réglé AVANT add_child (lu au _ready du composant).
	var nav := TopNav.new()
	nav.active_tab = ""
	add_child(nav)
	# Ambiance sonore : à la charge de l'écran HÔTE (la nav ne la lance jamais) — R6, idempotent.
	AudioManager.start_menu_ambient()

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# Barre d'XP cyan (construite en code).
	_style_xp_bar()

	# Catalogue des factions (pour résoudre id -> nom + couleur d'accent).
	_load_factions()

	# Profil serveur (R2) : statistiques + historique via NetworkManager (le code ne pousse que les
	# valeurs ; les intitulés « eyebrow » statiques vivent dans la scène — rythme eyebrow→valeur §2).
	NetworkManager.profile_stats_loaded.connect(_on_profile_loaded)
	NetworkManager.profile_history_loaded.connect(_on_history_loaded)
	NetworkManager.fetch_profile_stats()
	NetworkManager.fetch_profile_history(5)
	# Saison (M6 §8.68) : division + points de saison viennent de /auth/me (season_points/division).
	AuthManager.profile_loaded.connect(_on_me_loaded)
	AuthManager.get_profile()

	# Premier rendu avec les valeurs neutres (écrasées dès que le serveur répond).
	_refresh_all()
	_set_status(tr("PROFILE_STATUS_PREVIEW"))

# --- Profil / lecture défensive --------------------------------------------
func _on_profile_loaded(data: Dictionary):
	# Pseudo (toujours présent) + niveau.
	if data.has("username"):
		_set_username(str(data["username"]))
	_level = _read_int(data, ["niveau", "level"], _level)

	# Champs encore non garantis par le backend : on les lit DÉFENSIVEMENT.
	_xp = _read_int(data, ["xp", "experience", "exp", "points"], _xp)
	_xp_max = _read_int(data, ["xp_max", "xp_next", "next_level_xp", "niveau_suivant_xp"], _xp_max)
	_games_played = _read_int(data, ["parties_jouees", "games_played", "matches"], _games_played)
	_wins = _read_int(data, ["victoires", "wins"], _wins)
	_losses = _read_int(data, ["defaites", "losses"], _losses)
	_heaviest_toll = _read_int(data, ["tribut", "plus_lourd_tribut", "heaviest_toll", "units_lost"], _heaviest_toll)

	for key in ["faction_favorite", "favorite_faction", "faction", "main_faction"]:
		if data.has(key) and str(data[key]) != "":
			_favorite_faction_id = str(data[key])
			break

	_refresh_all()
	_set_status(tr("PROFILE_STATUS_LOADED"))

# --- Saison (M6 §8.68) : division + points de saison depuis /auth/me --------
var _season_points: int = 0
var _division: String = ""
# Couleurs des divisions (miroir de leaderboard.gd — bronze/argent/or/platine/élite).
const DIVISION_COLORS := {
	"BRONZE": Color("cd7f32"),
	"ARGENT": Color("c0c0c0"),
	"OR": Color(0.878431, 0.698039, 0.286275, 1),
	"PLATINE": Color("9adfea"),
	"ELITE": Color(0.211765, 0.772549, 0.85098, 1),
}

func _on_me_loaded(data: Dictionary) -> void:
	_season_points = _read_int(data, ["season_points"], _season_points)
	_division = str(data.get("division", _division))
	_populate_stats()

# --- Historique récent (GET /profile/history) ------------------------------
# Le serveur renvoie des entrées {win, faction_id, detail}. On résout faction_id -> nom d'affichage
# via le catalogue de factions (.tres), en repli sur l'id brut si la faction est inconnue localement.
func _on_history_loaded(entries: Array) -> void:
	_history.clear()
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var fid := str(e.get("faction_id", ""))
		var info: Dictionary = _factions.get(fid, {})
		var fac_name := str(info.get("name", fid)) if fid != "" else "—"
		_history.append({
			"win": bool(e.get("win", false)),
			"faction": fac_name,
			"detail": str(e.get("detail", "")),
		})
	_populate_history()

# Lit la première clé présente d'une liste et la convertit en int (piège float JSON §5, CLAUDE.md).
func _read_int(data: Dictionary, keys: Array, fallback: int) -> int:
	for k in keys:
		if data.has(k):
			return int(data[k])
	return fallback

# --- Rendu global -----------------------------------------------------------
func _refresh_all() -> void:
	if username_value and username_value.text.strip_edges() in ["", "—"]:
		# Le pseudo arrive via /auth/me ; on n'écrase pas s'il a déjà été poussé.
		_set_username(AuthManager.username if AuthManager.username != "" else tr("COMMON_OPERATOR"))
	_update_level_xp()
	_update_faction()
	_populate_stats()
	_populate_history()

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

func _update_faction() -> void:
	var info: Dictionary = _factions.get(_favorite_faction_id, {})
	var fac_name := str(info.get("name", _favorite_faction_id)).to_upper()
	var fac_color: Color = info.get("color", ACCENT)
	if faction_chevron:
		faction_chevron.add_theme_color_override("font_color", fac_color)
	if faction_value:
		faction_value.text = fac_name

# --- Statistiques (cartes readout générées en code, Règle d'Or §6.1) --------
func _populate_stats() -> void:
	_clear(stats_grid)
	var ratio := 0.0
	if _wins + _losses > 0:
		ratio = 100.0 * float(_wins) / float(_wins + _losses)
	stats_grid.add_child(_make_stat_card(tr("PROFILE_STAT_GAMES"), str(_games_played), TEXT))
	stats_grid.add_child(_make_stat_card(tr("COMMON_WINS"), str(_wins), GOLD))
	stats_grid.add_child(_make_stat_card(tr("PROFILE_STAT_LOSSES"), str(_losses), DANGER))
	stats_grid.add_child(_make_stat_card(tr("PROFILE_STAT_RATIO"), "%d%%" % int(round(ratio)), ACCENT))
	stats_grid.add_child(_make_stat_card(tr("PROFILE_STAT_TOLL"), _format_thousands(_heaviest_toll), MUTED))
	# Saison (M6 §8.68) : division + points saisonniers (masqués tant que /auth/me n'a pas répondu).
	if _division != "":
		stats_grid.add_child(_make_stat_card(tr("PROFILE_STAT_DIVISION"), _division,
			DIVISION_COLORS.get(_division, MUTED)))
		stats_grid.add_child(_make_stat_card(tr("PROFILE_STAT_SEASON_POINTS"),
			_format_thousands(_season_points), ACCENT))

# Carte readout : eyebrow (libellé) + valeur en gros (couleur sémantique). Surface gunmetal + liseré cyan.
func _make_stat_card(label: String, value: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style())
	card.custom_minimum_size = Vector2(175, 96)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)

	v.add_child(_eyebrow(label))

	var val := Label.new()
	val.text = value
	val.add_theme_font_override("font", _font)
	val.add_theme_font_size_override("font_size", 34)
	val.add_theme_color_override("font_color", value_color)
	v.add_child(val)

	WarzoneUI.add_corner_notches(card)
	return card

# --- Historique récent (lignes générées en code) ----------------------------
func _populate_history() -> void:
	_clear(history_box)
	if _history.is_empty():
		var empty := _body_label(tr("PROFILE_HISTORY_EMPTY"))
		empty.add_theme_color_override("font_color", MUTED)
		history_box.add_child(empty)
		return
	for entry in _history:
		history_box.add_child(_make_history_row(entry))

func _make_history_row(entry: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_card_style())

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	# Résultat (or = victoire, rouge = défaite) — chevron + libellé traduit (R4).
	var is_win := bool(entry.get("win", false))
	var result := tr("PROFILE_RESULT_VICTORY") if is_win else tr("PROFILE_RESULT_DEFEAT")
	var res_label := Label.new()
	res_label.text = "❯  " + result
	res_label.add_theme_font_override("font", _font)
	res_label.add_theme_font_size_override("font_size", 18)
	res_label.add_theme_color_override("font_color", GOLD if is_win else DANGER)
	res_label.custom_minimum_size = Vector2(150, 0)
	res_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(res_label)

	# Faction utilisée (valeur).
	var fac := Label.new()
	fac.text = str(entry.get("faction", "—")).to_upper()
	fac.add_theme_font_override("font", _font)
	fac.add_theme_font_size_override("font_size", 16)
	fac.add_theme_color_override("font_color", TEXT)
	fac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fac.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(fac)

	# Détail (texte muet, aligné à droite).
	var detail := Label.new()
	detail.text = str(entry.get("detail", ""))
	detail.add_theme_font_override("font", _font)
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(detail)

	return row

# --- Fabriques de nœuds / styles (charte §2, cohérent avec shop.gd) ---------
func _eyebrow(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", ACCENT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _body_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# Style d'une carte : surface gunmetal + liseré cyan à gauche (charte §2, comme shop.gd).
func _make_card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.border_width_left = 3
	sb.border_color = ACCENT
	sb.content_margin_left = 16.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 12.0
	return sb

# Barre d'XP cyan (fond gunmetal, remplissage cyan) — angulaire (corner_radius 0).
func _style_xp_bar() -> void:
	if xp_bar == null:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = SURFACE
	bg.set_corner_radius_all(0)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.211765, 0.772549, 0.85098, 0.35)

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(0)

	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	xp_bar.show_percentage = false

# --- Chargement des factions (id -> nom + couleur), garde-fous de faction_selection.gd ---
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

# --- Utilitaires ------------------------------------------------------------
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

