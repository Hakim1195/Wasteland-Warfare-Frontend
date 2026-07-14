extends Control

# =========================================================================
# Classement mondial (Feuille de route R3) — charte « Warzone Command » §2
# =========================================================================
# Écran NEUF accessible depuis main_menu (« ❯ CLASSEMENT MONDIAL »).
# Règle d'Or §6.1 : VUE pure — aucune logique de jeu brute. Le classement est SERVEUR (R3 —
# CONTRAT_RESEAU.md §9.2) : GET /leaderboard renvoie une page triée par victoires + le bloc `me`
# (rang GLOBAL de l'opérateur, même hors page). Quand le serveur répond, on FAIT CONFIANCE à son
# ordre et à ses rangs ; l'opérateur courant est surligné (et ajouté en bas via `me` s'il n'est pas
# dans la page). Repli PRÉVISUALISATION : tant que le serveur est muet/hors-ligne (ou sur l'ancienne
# forme « liste plate » avant redéploiement VPS), un classement mock est trié/rangé côté client.

# Nœuds câblés via @export + NodePath (drag-drop éditeur) — cf. conventions CLAUDE.md.
@export var panel: Control
@export var back_button: Button
@export var podium_box: HBoxContainer
@export var columns_header: HBoxContainer
@export var ranking_box: VBoxContainer
@export var status_label: Label

# Helpers UI partagés de la charte « Warzone Command » (§2) — encoches + badges hexagonaux.
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

# --- Palette canonique (§2) ---
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)   # cyan tactique
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)    # or (podium / récompense)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)    # blanc froid
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)   # acier (eyebrow / muet)
const SURFACE := Color(0.101961, 0.12549, 0.156863, 1)  # surface secondaire
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1) # fond gunmetal (texte sur badge or)

# Largeurs de colonnes (partagées entre l'en-tête fixe et les lignes défilantes → alignement garanti).
const COL_RANK := 90.0
const COL_LEVEL := 120.0
const COL_WINS := 140.0

# --- Données MOCK (remplacées par l'endpoint classement quand il sera spécifié) ---
# Classement mondial fictif (déjà trié desc. par victoires, comme le ferait le serveur).
# Chaque entrée : { name, level, wins }. L'opérateur local est inséré à part (_build_entries).
var _mock_board: Array = [
	{"name": "RAVAGEUR_PRIME", "level": 58, "wins": 412},
	{"name": "VDV_KOZLOV", "level": 51, "wins": 377},
	{"name": "SISTER_OBLIVION", "level": 49, "wins": 341},
	{"name": "GHOST_OF_KIEV", "level": 47, "wins": 318},
	{"name": "RUST_BARON_IX", "level": 44, "wins": 295},
	{"name": "ATOMIC_HYENA", "level": 42, "wins": 271},
	{"name": "PROPHETE_ISOTOPE", "level": 39, "wins": 244},
	{"name": "CENDRE_NOIRE", "level": 37, "wins": 228},
	{"name": "WARLORD_MOJAVE", "level": 34, "wins": 201},
	{"name": "LA_FAUCHEUSE", "level": 31, "wins": 176},
	{"name": "FERRAILLEUR_77", "level": 28, "wins": 152},
	{"name": "NOMADE_ERRANT", "level": 25, "wins": 131},
]

# Valeurs de l'opérateur local (lues défensivement du profil ; sinon mock).
var _local_name: String = ""
var _local_level: int = 23
var _local_wins: int = 118

# Classement RÉEL renvoyé par le serveur (R3, GET /leaderboard). Tant qu'il est vide (serveur muet
# ou hors-ligne), l'écran affiche le mock ci-dessus en prévisualisation ; dès qu'il répond, il le REMPLACE.
# Chaque entrée : { name, level, wins, rank } (rank = position GLOBALE serveur, 0 si forme legacy).
var _server_board: Array = []
# Bloc « me » (§9.2) : { rank, level, wins } de l'opérateur courant, rang GLOBAL fiable même hors page.
# Vide si non authentifié ou ancien backend. Sert à surligner / ajouter l'opérateur au classement réel.
var _me: Dictionary = {}

# Police condensée de la charte (§2), construite en code pour les nœuds générés dynamiquement.
var _font: SystemFont

# --- Ladder SAISONNIER (lot M6 §8.68) ---
# Scope courant : "season" (défaut, divisions + points de saison) | "lifetime" (historique §9.2).
var _scope := "season"
# Bloc { id, ends_at } de la réponse (compte à rebours de fin de saison), lu de NetworkManager.
var _season_info: Dictionary = {}
# Vrai si le serveur fournit les divisions (backend ≥ M6). Repli legacy : false → onglet GÉNÉRAL seul.
var _has_division_data := false
# Onglets SAISON / GÉNÉRAL construits par code dans la barre d'en-tête.
var _tab_season: Button = null
var _tab_lifetime: Button = null

# Couleurs des divisions (M6 §8.68 — bronze/argent/or charte/platine cyan pâle/élite cyan tactique).
const DIVISION_COLORS := {
	"BRONZE": Color("cd7f32"),
	"ARGENT": Color("c0c0c0"),
	"OR": Color(0.878431, 0.698039, 0.286275, 1),
	"PLATINE": Color("9adfea"),
	"ELITE": Color(0.211765, 0.772549, 0.85098, 1),
}
const COL_DIVISION := 120.0

func _ready():
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Encoche biseautée d'angle sur le panneau principal (ADN angulaire §2).
	WarzoneUI.add_corner_notches(panel)

	# Bouton RETOUR (ghost) — cohérent avec shop.gd / profile.gd.
	_style_ghost_button(back_button)
	if back_button: back_button.pressed.connect(_on_back_pressed)
	WarzoneUI.wire_button_sfx(back_button)  # SFX d'interface (survol/clic — R6)

	# En-tête de colonnes (eyebrows alignés sur les lignes).
	_build_columns_header()

	# Identité locale : connue dès le login (AuthManager.username) ; le niveau/victoires arrivent
	# via /auth/me (le code ne pousse que les valeurs ; les intitulés statiques vivent dans la scène).
	_local_name = AuthManager.username if AuthManager.username != "" else tr("COMMON_OPERATOR")
	AuthManager.profile_loaded.connect(_on_profile_loaded)
	AuthManager.get_profile()

	# Onglets SAISON / GÉNÉRAL (M6 §8.68) — le classement OUVRE sur SAISON.
	_build_scope_tabs()

	# Classement mondial RÉEL (§P2) : GET /leaderboard via NetworkManager. Remplace le mock dès la réponse.
	NetworkManager.leaderboard_loaded.connect(_on_leaderboard_loaded)
	NetworkManager.fetch_leaderboard(20, 0, _scope)

	# Premier rendu avec les valeurs mock (mises à jour si /auth/me ou le classement répondent).
	_refresh()
	_set_status(tr("LEADERBOARD_STATUS_PREVIEW"))

# --- Classement serveur (R3 — §9.2) -----------------------------------------
# Mappe les entrées backend vers le format d'affichage ({name, level, wins, rank}) puis redessine.
# Lecture défensive : clés canoniques §9.2 (level/wins/rank) en priorité, repli sur les alias
# historiques (niveau/stats_victoires). Le bloc `me` fixe l'identité + le rang global de l'opérateur.
func _on_leaderboard_loaded(entries: Array, me: Dictionary) -> void:
	_me = me if typeof(me) == TYPE_DICTIONARY else {}
	# Bloc saison { id, ends_at } (M6) — stocké par NetworkManager à côté du signal (signature stable).
	_season_info = NetworkManager.last_leaderboard_season
	_server_board.clear()
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_server_board.append({
			"name": str(e.get("username", "—")),
			"level": int(e.get("level", e.get("niveau", 1))),
			"wins": int(e.get("wins", e.get("stats_victoires", 0))),
			"rank": int(e.get("rank", 0)),
			# M6 : points de saison + division (défauts sûrs sur un backend antérieur).
			"season_points": int(e.get("season_points", 0)),
			"division": str(e.get("division", "")),
		})
	# Repli LEGACY (M6, convention §9.2 client défensif) : réponse sans `division` → le backend
	# est antérieur au ladder saisonnier → onglet GÉNÉRAL seul (les onglets se masquent).
	_has_division_data = entries.size() > 0 and typeof(entries[0]) == TYPE_DICTIONARY \
		and entries[0].has("division")
	_update_scope_tabs_visibility()
	# Identité/valeurs locales depuis le bloc me (rang global fiable même si l'opérateur est hors page).
	if not _me.is_empty():
		if _me.has("username") and str(_me["username"]) != "":
			_local_name = str(_me["username"])
		_local_level = int(_me.get("level", _local_level))
		_local_wins = int(_me.get("wins", _local_wins))
	_build_columns_header()
	_refresh()
	_set_status(_season_status_line())

# Ligne de statut enrichie (M6) : division de l'opérateur + compte à rebours de fin de saison.
func _season_status_line() -> String:
	if _server_board.is_empty():
		return tr("LEADERBOARD_EMPTY")
	var base := tr("LEADERBOARD_STATUS_LOCATED")
	if _scope != "season" or not _has_division_data:
		return base
	var parts: Array = []
	if not _me.is_empty() and str(_me.get("division", "")) != "":
		parts.append(tr("LEADERBOARD_MY_DIVISION").format({"division": str(_me["division"])}))
	var days := _season_days_left()
	if days > 0:
		parts.append(tr("LEADERBOARD_SEASON_END").format({"days": days}))
	if parts.is_empty():
		return base
	return " · ".join(PackedStringArray(parts))

func _season_days_left() -> int:
	var ends := str(_season_info.get("ends_at", ""))
	if ends == "":
		return 0
	var end_epoch := int(Time.get_unix_time_from_datetime_string(ends.trim_suffix("Z")))
	return maxi(0, int((end_epoch - int(Time.get_unix_time_from_system())) / 86400))

# --- Onglets SAISON / GÉNÉRAL (M6 §8.68) -------------------------------------
func _build_scope_tabs() -> void:
	var header := back_button.get_parent()
	if header == null:
		return
	_tab_season = _make_scope_tab(tr("LEADERBOARD_TAB_SEASON"), true)
	_tab_season.pressed.connect(func() -> void: _switch_scope("season"))
	_tab_lifetime = _make_scope_tab(tr("LEADERBOARD_TAB_LIFETIME"), false)
	_tab_lifetime.pressed.connect(func() -> void: _switch_scope("lifetime"))
	# Insérés AVANT le bouton RETOUR (fin de la barre d'en-tête).
	header.add_child(_tab_season)
	header.add_child(_tab_lifetime)
	header.move_child(_tab_season, back_button.get_index())
	header.move_child(_tab_lifetime, back_button.get_index())

func _make_scope_tab(text: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
	WarzoneUI.wire_button_sfx(btn)
	_style_scope_tab(btn, active)
	return btn

func _style_scope_tab(btn: Button, active: bool) -> void:
	if btn == null:
		return
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT, 0.18) if active else Color(0, 0, 0, 0)
	if active:
		sb.border_width_bottom = 3
		sb.border_color = ACCENT
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.14)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)

func _switch_scope(scope: String) -> void:
	if scope == _scope:
		return
	_scope = scope
	_style_scope_tab(_tab_season, _scope == "season")
	_style_scope_tab(_tab_lifetime, _scope == "lifetime")
	_set_status(tr("LEADERBOARD_STATUS_PREVIEW"))
	NetworkManager.fetch_leaderboard(20, 0, _scope)

# Repli legacy (backend sans divisions) : les onglets disparaissent, on force le GÉNÉRAL.
func _update_scope_tabs_visibility() -> void:
	var show := _has_division_data or _server_board.is_empty()
	if _tab_season != null:
		_tab_season.visible = show
	if _tab_lifetime != null:
		_tab_lifetime.visible = show
	if not show and _scope != "lifetime":
		_scope = "lifetime"
		_style_scope_tab(_tab_season, false)
		_style_scope_tab(_tab_lifetime, true)

# --- Profil / lecture défensive --------------------------------------------
func _on_profile_loaded(data: Dictionary):
	if data.has("username") and str(data["username"]) != "":
		_local_name = str(data["username"])
	_local_level = _read_int(data, ["niveau", "level"], _local_level)
	# Le backend (UserResponse) expose stats_victoires : on le lit en priorité (repli défensif ensuite).
	_local_wins = _read_int(data, ["stats_victoires", "victoires", "wins"], _local_wins)
	_refresh()
	_set_status(tr("LEADERBOARD_STATUS_LOCATED"))

# Lit la première clé présente d'une liste et la convertit en int (piège float JSON §5, CLAUDE.md).
func _read_int(data: Dictionary, keys: Array, fallback: int) -> int:
	for k in keys:
		if data.has(k):
			return int(data[k])
	return fallback

# --- Construction du classement (Règle d'Or §6.1, VUE pure) ----------------
# Deux chemins : (1) classement serveur §9.2 (entries avec rang global) → on RESPECTE l'ordre et les
# rangs serveur, on surligne/ajoute l'opérateur via le bloc `me` ; (2) repli (mock de prévisualisation
# OU ancien backend « liste plate » sans rang) → tri & rang calculés côté client.
func _build_entries() -> Array:
	if not _server_board.is_empty() and int(_server_board[0].get("rank", 0)) > 0:
		return _build_server_entries()
	return _build_ranked_locally()

# Chemin SERVEUR §9.2 : ordre et rangs du serveur respectés tels quels. L'opérateur courant est
# surligné s'il figure dans la page ; sinon il est AJOUTÉ en bas avec son rang GLOBAL réel (bloc me).
func _build_server_entries() -> Array:
	var rows: Array = _server_board.duplicate(true)
	var local_upper := _local_name.to_upper()
	var present := false
	for r in rows:
		if str(r.get("name", "")).to_upper() == local_upper:
			r["is_local"] = true   # on NE touche PAS à level/wins/rank : le serveur fait foi.
			present = true
			break
	# Opérateur hors de la page renvoyée : on l'ajoute distinctement avec son rang global (si connu).
	if not present and not _me.is_empty():
		rows.append({"name": _local_name, "level": _local_level, "wins": _local_wins,
			"rank": int(_me.get("rank", 0)), "is_local": true,
			"season_points": int(_me.get("season_points", 0)),
			"division": str(_me.get("division", ""))})
	return rows

# Chemin REPLI : fusionne la source (mock, ou liste plate legacy) + l'opérateur local, trie desc.
# par victoires (départage par niveau), attribue les rangs côté client.
func _build_ranked_locally() -> Array:
	var source: Array = _server_board if not _server_board.is_empty() else _mock_board
	var rows: Array = source.duplicate(true)
	var local_upper := _local_name.to_upper()
	var present := false
	for r in rows:
		if str(r.get("name", "")).to_upper() == local_upper:
			r["wins"] = _local_wins
			r["level"] = _local_level
			r["is_local"] = true
			present = true
			break
	if not present:
		rows.append({"name": _local_name, "level": _local_level, "wins": _local_wins, "is_local": true})
	# Tri serveur simulé : victoires décroissantes (départage par niveau).
	rows.sort_custom(func(a, b):
		if int(a.get("wins", 0)) == int(b.get("wins", 0)):
			return int(a.get("level", 0)) > int(b.get("level", 0))
		return int(a.get("wins", 0)) > int(b.get("wins", 0)))
	var rank := 1
	for r in rows:
		r["rank"] = rank
		rank += 1
	return rows

func _refresh() -> void:
	var entries := _build_entries()
	_populate_podium(entries)
	_populate_ranking(entries)

# --- Podium top 3 (cartes générées en code, or pour le #1) -----------------
func _populate_podium(entries: Array) -> void:
	_clear(podium_box)
	var top := mini(3, entries.size())
	for i in top:
		podium_box.add_child(_make_podium_card(entries[i]))

# Carte de podium : badge hexagonal du rang (or pour #1, cyan pour #2/#3) + pseudo + victoires.
func _make_podium_card(entry: Dictionary) -> PanelContainer:
	var rank := int(entry.get("rank", 0))
	var is_first := rank == 1
	var is_local := bool(entry.get("is_local", false))
	var accent: Color = GOLD if is_first else ACCENT

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_card_style(accent))
	card.custom_minimum_size = Vector2(0, 150 if is_first else 132)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	# Badge hexagonal du rang (mutualisé via le helper §2 — make_hex_badge).
	var badge_fill: Color = GOLD if is_first else ACCENT
	var badge_text: Color = GUNMETAL
	var badge := WarzoneUI.make_hex_badge("#" + str(rank), _font, 26, badge_fill, badge_text, 64.0 if is_first else 54.0)
	var badge_holder := CenterContainer.new()
	badge_holder.add_child(badge)
	v.add_child(badge_holder)

	# Pseudo (cyan si c'est l'opérateur local).
	var name_label := Label.new()
	name_label.text = str(entry.get("name", "—")).to_upper()
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 22 if is_first else 19)
	name_label.add_theme_color_override("font_color", ACCENT if is_local else TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)

	# Victoires (en or = devise de gloire du classement).
	var wins := Label.new()
	wins.text = _format_thousands(int(entry.get("wins", 0))) + " " + tr("COMMON_WINS")
	wins.add_theme_font_override("font", _font)
	wins.add_theme_font_size_override("font_size", 14)
	wins.add_theme_color_override("font_color", GOLD)
	wins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wins)

	WarzoneUI.add_corner_notches(card)
	return card

# --- En-tête de colonnes (fixe, hors scroll → reste aligné sur les lignes) --
func _build_columns_header() -> void:
	if columns_header == null:
		return
	_clear(columns_header)
	columns_header.add_theme_constant_override("separation", 14)
	columns_header.add_child(_header_cell(tr("LEADERBOARD_COL_RANK"), COL_RANK, HORIZONTAL_ALIGNMENT_LEFT))
	columns_header.add_child(_header_cell(tr("COMMON_OPERATOR"), 0.0, HORIZONTAL_ALIGNMENT_LEFT, true))
	# Colonne DIVISION (M6 §8.68) — uniquement sur l'onglet SAISON avec un backend qui la fournit.
	if _show_division_column():
		columns_header.add_child(_header_cell(tr("LEADERBOARD_COL_DIVISION"), COL_DIVISION, HORIZONTAL_ALIGNMENT_CENTER))
	columns_header.add_child(_header_cell(tr("COMMON_LEVEL"), COL_LEVEL, HORIZONTAL_ALIGNMENT_CENTER))
	columns_header.add_child(_header_cell(tr("COMMON_WINS"), COL_WINS, HORIZONTAL_ALIGNMENT_RIGHT))

# La colonne division ne s'affiche que sur le ladder SAISON d'un backend ≥ M6 (repli §9.2 sinon).
func _show_division_column() -> bool:
	return _scope == "season" and _has_division_data

func _header_cell(text: String, width: float, align: int, expand: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", ACCENT)
	l.horizontal_alignment = align
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.custom_minimum_size = Vector2(width, 0)
	return l

# --- Lignes du classement (générées en code) -------------------------------
func _populate_ranking(entries: Array) -> void:
	_clear(ranking_box)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = tr("LEADERBOARD_EMPTY")
		empty.add_theme_font_override("font", _font)
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", MUTED)
		ranking_box.add_child(empty)
		return
	for entry in entries:
		ranking_box.add_child(_make_ranking_row(entry))

func _make_ranking_row(entry: Dictionary) -> PanelContainer:
	var rank := int(entry.get("rank", 0))
	var is_local := bool(entry.get("is_local", false))
	# Ligne de l'opérateur local : surface accentuée + liseré cyan plus épais (repère visuel §2).
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_row_style(is_local))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)

	# Rang (chevron + numéro ; or pour le top 3).
	var rank_label := Label.new()
	rank_label.text = "❯ %d" % rank
	rank_label.add_theme_font_override("font", _font)
	rank_label.add_theme_font_size_override("font_size", 18)
	rank_label.add_theme_color_override("font_color", GOLD if rank <= 3 else MUTED)
	rank_label.custom_minimum_size = Vector2(COL_RANK, 0)
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rank_label)

	# Pseudo (cyan + suffixe « (VOUS) » pour l'opérateur local).
	var name_label := Label.new()
	var who := str(entry.get("name", "—")).to_upper()
	if is_local:
		who += tr("LEADERBOARD_YOU")
	name_label.text = who
	name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", ACCENT if is_local else TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name_label)

	# Badge de DIVISION (M6 §8.68) : texte coloré au ton de la division + points de saison.
	if _show_division_column():
		var division := str(entry.get("division", ""))
		var div_label := Label.new()
		div_label.text = "%s · %d" % [division, int(entry.get("season_points", 0))] if division != "" else "—"
		div_label.add_theme_font_override("font", _font)
		div_label.add_theme_font_size_override("font_size", 15)
		div_label.add_theme_color_override("font_color", DIVISION_COLORS.get(division, MUTED))
		div_label.custom_minimum_size = Vector2(COL_DIVISION, 0)
		div_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		div_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(div_label)

	# Niveau (valeur centrée).
	var level_label := Label.new()
	level_label.text = str(int(entry.get("level", 0)))
	level_label.add_theme_font_override("font", _font)
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", TEXT)
	level_label.custom_minimum_size = Vector2(COL_LEVEL, 0)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(level_label)

	# Victoires (en or, aligné à droite).
	var wins_label := Label.new()
	wins_label.text = _format_thousands(int(entry.get("wins", 0)))
	wins_label.add_theme_font_override("font", _font)
	wins_label.add_theme_font_size_override("font_size", 18)
	wins_label.add_theme_color_override("font_color", GOLD)
	wins_label.custom_minimum_size = Vector2(COL_WINS, 0)
	wins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(wins_label)

	return row

# --- Fabriques de styles (charte §2, cohérent avec shop.gd / profile.gd) ----
# Style d'une carte de podium : surface gunmetal + bordure d'accent (or pour le #1).
func _make_card_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SURFACE
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 14.0
	sb.content_margin_top = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 14.0
	return sb

# Style d'une ligne de classement : surface gunmetal + liseré cyan gauche (épais + teinté si local).
func _make_row_style(is_local: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.211765, 0.772549, 0.85098, 0.10) if is_local else SURFACE
	sb.set_corner_radius_all(0)
	sb.border_width_left = 5 if is_local else 3
	sb.border_color = ACCENT
	sb.content_margin_left = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 10.0
	return sb

# Style « ghost » (fond quasi nul + liseré cyan) — bouton RETOUR (identique à shop.gd / profile.gd).
func _style_ghost_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.03)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.211765, 0.772549, 0.85098, 0.55)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 14.0
	normal.content_margin_top = 8.0
	normal.content_margin_right = 14.0
	normal.content_margin_bottom = 8.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.211765, 0.772549, 0.85098, 0.16)
	hover.border_color = ACCENT

	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)

# --- Utilitaires ------------------------------------------------------------
# Sépare les milliers par une fine espace (lisibilité, comme shop / profile).
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

# Vide un conteneur sans laisser de doublons (cf. lobby_screen.gd / shop.gd / profile.gd).
func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

func _on_back_pressed():
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")
